//
//  FocalLengthEstimator.swift
//  35mm 환산 초점거리 추정 시스템
//
//  - EXIF 있으면 직접 사용
//  - EXIF 없으면 뎁스맵으로 역추정
//  - 아이폰 기준: 1x = 24mm
//
//  작성일: 2025-12-07
//

import Foundation
import CoreML
import UIKit
import ImageIO

// MARK: - 초점거리 정보
struct FocalLengthInfo {
    let focalLength35mm: Int      // 35mm 환산 초점거리 (mm)
    let source: FocalLengthSource // 정보 출처
    let confidence: Float         // 신뢰도 (0.0 ~ 1.0)

    var lensType: LensType {
        return LensType.from(focalLength: focalLength35mm)
    }

    var displayName: String {
        return "\(focalLength35mm)mm \(lensType.displayName)"
    }
}

// MARK: - 초점거리 정보 출처
enum FocalLengthSource {
    case exif           // EXIF 메타데이터에서 추출
    case zoomFactor     // 줌 배율에서 계산
    case depthEstimate  // 뎁스맵으로 역추정
    case userInput      // 사용자 입력
    case fallback       // 기본값 사용

    var description: String {
        switch self {
        case .exif: return "EXIF"
        case .zoomFactor: return "줌 배율"
        case .depthEstimate: return "뎁스 분석"
        case .userInput: return "사용자 입력"
        case .fallback: return "추정값"
        }
    }
}

// MARK: - 렌즈 타입 (35mm 환산 기준)
enum LensType: String {
    case ultraWide  // 초광각: ~20mm
    case wide       // 광각: 21-35mm
    case normal     // 표준: 36-60mm
    case shortTele  // 준망원: 61-100mm
    case telephoto  // 망원: 101mm~

    var displayName: String {
        switch self {
        case .ultraWide: return "초광각"
        case .wide: return "광각"
        case .normal: return "표준"
        case .shortTele: return "준망원"
        case .telephoto: return "망원"
        }
    }

    var focalLengthRange: ClosedRange<Int> {
        switch self {
        case .ultraWide: return 1...20
        case .wide: return 21...35
        case .normal: return 36...60
        case .shortTele: return 61...100
        case .telephoto: return 101...500
        }
    }

    static func from(focalLength: Int) -> LensType {
        switch focalLength {
        case ...20: return .ultraWide
        case 21...35: return .wide
        case 36...60: return .normal
        case 61...100: return .shortTele
        default: return .telephoto
        }
    }
}

// MARK: - Focal Length Estimator
class FocalLengthEstimator {

    // 아이폰 기본 초점거리 (1x = 24mm)
    static let iPhoneBaseFocalLength: Int = 24

    // 싱글톤
    static let shared = FocalLengthEstimator()

    private init() {}

    // MARK: - 현재 카메라에서 초점거리 계산

    /// 줌 배율에서 35mm 환산 초점거리 계산
    /// - Parameter zoomFactor: 카메라 줌 배율 (0.5, 1.0, 2.0, 3.0 등)
    /// - Returns: 35mm 환산 초점거리 정보
    func focalLengthFromZoom(_ zoomFactor: CGFloat) -> FocalLengthInfo {
        // 아이폰 기준: 1x = 24mm
        // 0.5x = 13mm (초광각)
        // 1x = 24mm (광각)
        // 2x = 48mm (표준)
        // 3x = 72mm (준망원)
        // 5x = 120mm (망원)

        let focalLength = Int(round(CGFloat(Self.iPhoneBaseFocalLength) * zoomFactor))

        return FocalLengthInfo(
            focalLength35mm: max(13, focalLength),  // 최소 13mm (0.5x)
            source: .zoomFactor,
            confidence: 1.0  // 줌 배율은 정확함
        )
    }

    // MARK: - 레퍼런스 이미지에서 초점거리 추출

    /// 이미지에서 EXIF 초점거리 추출
    /// - Parameter image: UIImage
    /// - Returns: 초점거리 정보 (EXIF 없으면 nil)
    func extractFocalLengthFromEXIF(_ imageData: Data?) -> FocalLengthInfo? {
        guard let data = imageData else { return nil }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] else {
            return nil
        }

        // 35mm 환산 초점거리 우선 사용
        if let focalLength35mm = exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? Int {
            return FocalLengthInfo(
                focalLength35mm: focalLength35mm,
                source: .exif,
                confidence: 1.0
            )
        }

        // 실제 초점거리만 있는 경우 (센서 크기 모르면 정확도 낮음)
        if let focalLength = exif[kCGImagePropertyExifFocalLength as String] as? Double {
            // 스마트폰 센서 기준 대략적 변환 (crop factor ~6-7x)
            let estimated35mm = Int(focalLength * 6.5)
            return FocalLengthInfo(
                focalLength35mm: estimated35mm,
                source: .exif,
                confidence: 0.7  // 변환 추정이므로 신뢰도 낮음
            )
        }

        return nil
    }

    // MARK: - 뎁스맵으로 초점거리 역추정

    /// 뎁스맵 분석으로 초점거리 추정
    /// - Parameter depthMap: MLMultiArray 뎁스맵
    /// - Returns: 추정된 초점거리 정보
    func estimateFocalLengthFromDepth(_ depthMap: MLMultiArray) -> FocalLengthInfo {
        let depthVariance = calculateDepthVariance(depthMap)

        // 뎁스 차이 → 초점거리 매핑
        // 큰 차이 = 광각 (원근감 강조)
        // 작은 차이 = 망원 (압축됨)

        let (focalLength, confidence) = mapDepthVarianceToFocalLength(depthVariance)

        print("📐 뎁스 분석: variance=\(String(format: "%.3f", depthVariance)) → 추정 \(focalLength)mm")

        return FocalLengthInfo(
            focalLength35mm: focalLength,
            source: .depthEstimate,
            confidence: confidence
        )
    }

    /// 뎁스맵의 전경-배경 깊이 차이 계산
    private func calculateDepthVariance(_ depthMap: MLMultiArray) -> Float {
        let shape = depthMap.shape
        guard shape.count >= 2 else { return 0.5 }

        let height = shape[0].intValue
        let width = shape.count > 1 ? shape[1].intValue : 1

        guard height > 0 && width > 0 else { return 0.5 }

        // 상단 1/4 (배경)
        var backgroundSum: Float = 0
        var backgroundCount = 0
        for y in 0..<(height/4) {
            for x in 0..<width {
                let index = y * width + x
                if index < depthMap.count {
                    backgroundSum += depthMap[index].floatValue
                    backgroundCount += 1
                }
            }
        }
        let backgroundAvg = backgroundCount > 0 ? backgroundSum / Float(backgroundCount) : 0.5

        // 중앙 1/3 (인물/전경)
        var foregroundSum: Float = 0
        var foregroundCount = 0
        let startY = height / 3
        let endY = 2 * height / 3
        let startX = width / 4
        let endX = 3 * width / 4

        for y in startY..<endY {
            for x in startX..<endX {
                let index = y * width + x
                if index < depthMap.count {
                    foregroundSum += depthMap[index].floatValue
                    foregroundCount += 1
                }
            }
        }
        let foregroundAvg = foregroundCount > 0 ? foregroundSum / Float(foregroundCount) : 0.5

        // 깊이 차이 (0 ~ 1 범위로 정규화)
        let variance = abs(backgroundAvg - foregroundAvg)
        return min(1.0, variance)
    }

    /// 뎁스 차이를 초점거리로 매핑
    private func mapDepthVarianceToFocalLength(_ variance: Float) -> (focalLength: Int, confidence: Float) {
        // 뎁스 차이가 클수록 광각 (원근감 강조)
        // 뎁스 차이가 작을수록 망원 (압축됨)

        switch variance {
        case 0.5...:
            // 큰 차이 = 확실히 광각
            return (24, 0.8)
        case 0.35..<0.5:
            // 중간-큰 차이 = 광각~준광각
            return (28, 0.7)
        case 0.25..<0.35:
            // 중간 차이 = 표준
            return (50, 0.6)
        case 0.15..<0.25:
            // 작은 차이 = 준망원
            return (70, 0.6)
        case 0.08..<0.15:
            // 매우 작은 차이 = 망원
            return (85, 0.5)
        default:
            // 거의 차이 없음 = 강한 망원
            return (100, 0.4)
        }
    }

    // MARK: - 통합 추정 (EXIF 우선, 없으면 뎁스 분석)

    /// 레퍼런스 이미지의 초점거리 추정 (EXIF → 뎁스 순서)
    func estimateReferenceFocalLength(
        imageData: Data?,
        depthMap: MLMultiArray?,
        fallback: Int = 50
    ) -> FocalLengthInfo {
        // 1순위: EXIF
        if let exifInfo = extractFocalLengthFromEXIF(imageData) {
            print("📐 EXIF에서 초점거리 추출: \(exifInfo.focalLength35mm)mm")
            return exifInfo
        }

        // 2순위: 뎁스맵 분석
        if let depth = depthMap {
            let depthInfo = estimateFocalLengthFromDepth(depth)
            print("📐 뎁스맵에서 초점거리 추정: \(depthInfo.focalLength35mm)mm (신뢰도: \(Int(depthInfo.confidence * 100))%)")
            return depthInfo
        }

        // 3순위: 기본값
        print("📐 초점거리 정보 없음 - 기본값 \(fallback)mm 사용")
        return FocalLengthInfo(
            focalLength35mm: fallback,
            source: .fallback,
            confidence: 0.3
        )
    }

    // MARK: - 줌 추천 계산

    /// 레퍼런스 초점거리에 맞추기 위한 줌 배율 계산
    func recommendedZoom(
        currentZoom: CGFloat,
        targetFocalLength: Int
    ) -> (zoomFactor: CGFloat, description: String) {

        let currentFocal = focalLengthFromZoom(currentZoom)
        let currentMM = currentFocal.focalLength35mm

        // 목표 줌 = 목표초점거리 / 기본초점거리
        let targetZoom = CGFloat(targetFocalLength) / CGFloat(Self.iPhoneBaseFocalLength)

        // 차이 계산
        let diff = targetFocalLength - currentMM
        let zoomDiff = targetZoom - currentZoom

        var description: String

        if abs(diff) <= 5 {
            description = "현재 \(currentMM)mm로 적절해요"
        } else if diff > 0 {
            // 줌인 필요
            if zoomDiff >= 2.0 {
                description = "\(String(format: "%.1f", targetZoom))x로 줌인하세요 (\(currentMM)mm → \(targetFocalLength)mm)"
            } else if zoomDiff >= 1.0 {
                description = "\(String(format: "%.1f", targetZoom))x로 줌인하세요"
            } else {
                description = "조금 줌인하세요 (\(currentMM)mm → \(targetFocalLength)mm)"
            }
        } else {
            // 줌아웃 필요
            if currentZoom - targetZoom >= 1.0 {
                description = "\(String(format: "%.1f", targetZoom))x로 줌아웃하세요 (\(currentMM)mm → \(targetFocalLength)mm)"
            } else {
                description = "조금 줌아웃하세요 (\(currentMM)mm → \(targetFocalLength)mm)"
            }
        }

        return (targetZoom, description)
    }
}
