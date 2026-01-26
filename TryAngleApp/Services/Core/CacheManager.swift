//
//  CacheManager.swift
//  v1.5 레퍼런스 캐싱 시스템
//  작성일: 2025-12-05
//

import Foundation
import UIKit

// MARK: - 캐시된 레퍼런스 데이터
struct CachedReference {
    let id: String
    let image: UIImage
    let bbox: CGRect                    // 정규화된 좌표
    let imageSize: CGSize
    let margins: MarginAnalysisResult
    let compressionIndex: CGFloat?
    let timestamp: Date

    // 추가 분석 데이터
    var keypoints: [[CGFloat]]?         // RTMPose 133 키포인트
    var framingType: FramingType?
    var cameraType: CameraType?

    enum FramingType: String {
        case fullBody = "전신"
        case threeQuarter = "무릎샷"
        case waist = "웨이스트샷"
        case bust = "바스트샷"
        case closeUp = "클로즈업"
    }

    enum CameraType: String {
        case wide = "광각"
        case normal = "표준"
        case telephoto = "망원"
    }
}

// MARK: - 캐시 관리자
class CacheManager {

    static let shared = CacheManager()

    // 메모리 캐시
    private var referenceCache: [String: CachedReference] = [:]
    private var calibrationFactors: [String: CalibrationFactor] = [:]

    // 캐시 설정
    private let maxCacheSize = 5          // 최대 캐시 개수
    private let cacheTimeout: TimeInterval = 3600  // 1시간

    private init() {}

    // MARK: - 레퍼런스 캐싱

    /// 레퍼런스 분석 결과 캐싱
    func cacheReference(
        id: String,
        image: UIImage,
        bbox: CGRect,
        margins: MarginAnalysisResult,
        compressionIndex: CGFloat? = nil
    ) -> CachedReference {

        // 캐시 크기 관리
        if referenceCache.count >= maxCacheSize {
            removeOldestCache()
        }

        let cached = CachedReference(
            id: id,
            image: image,
            bbox: bbox,
            imageSize: image.size,
            margins: margins,
            compressionIndex: compressionIndex,
            timestamp: Date()
        )

        referenceCache[id] = cached
        print("📦 레퍼런스 캐시 저장: \(id)")

        return cached
    }

    /// 캐시된 레퍼런스 가져오기
    func getReference(id: String) -> CachedReference? {
        guard let cached = referenceCache[id] else {
            return nil
        }

        // 만료 확인
        if Date().timeIntervalSince(cached.timestamp) > cacheTimeout {
            referenceCache.removeValue(forKey: id)
            print("⏰ 캐시 만료됨: \(id)")
            return nil
        }

        return cached
    }

    /// 현재 활성 레퍼런스 가져오기
    func getCurrentReference() -> CachedReference? {
        // 가장 최근에 캐시된 레퍼런스 반환
        return referenceCache.values
            .sorted { $0.timestamp > $1.timestamp }
            .first
    }

    // MARK: - 보정 계수

    struct CalibrationFactor {
        let topRatio: CGFloat
        let bottomRatio: CGFloat
        let leftRatio: CGFloat
        let rightRatio: CGFloat

        static let identity = CalibrationFactor(
            topRatio: 1.0,
            bottomRatio: 1.0,
            leftRatio: 1.0,
            rightRatio: 1.0
        )
    }

    /// 보정 계수 저장
    func saveCalibration(id: String, factor: CalibrationFactor) {
        calibrationFactors[id] = factor
        print("🔧 보정 계수 저장: \(id)")
    }

    /// 보정 계수 가져오기
    func getCalibration(id: String) -> CalibrationFactor {
        return calibrationFactors[id] ?? .identity
    }

    /// 여백에 보정 적용
    func applyCalibration(margins: MarginAnalysisResult, calibrationId: String) -> MarginAnalysisResult {
        let factor = getCalibration(id: calibrationId)

        return MarginAnalysisResult(
            left: margins.left,
            right: margins.right,
            top: margins.top,
            bottom: margins.bottom,
            leftRatio: margins.leftRatio * factor.leftRatio,
            rightRatio: margins.rightRatio * factor.rightRatio,
            topRatio: margins.topRatio * factor.topRatio,
            bottomRatio: margins.bottomRatio * factor.bottomRatio,
            horizontalBalance: margins.horizontalBalance,
            verticalBalance: margins.verticalBalance,
            overallBalance: margins.overallBalance,
            horizontalFeedback: margins.horizontalFeedback,
            verticalFeedback: margins.verticalFeedback,
            movementDirection: margins.movementDirection,
            // 🆕 v6: 새로 추가된 필드들
            personVerticalPosition: margins.personVerticalPosition,
            isHighAngle: margins.isHighAngle,
            isLowAngle: margins.isLowAngle,
            outOfFrameWarning: margins.outOfFrameWarning
        )
    }

    // MARK: - 캐시 관리

    /// 특정 캐시 삭제
    func removeCache(id: String) {
        referenceCache.removeValue(forKey: id)
        calibrationFactors.removeValue(forKey: id)
        print("🗑️ 캐시 삭제: \(id)")
    }

    /// 모든 캐시 삭제
    func clearAllCache() {
        referenceCache.removeAll()
        calibrationFactors.removeAll()
        print("🗑️ 모든 캐시 삭제됨")
    }

    /// 가장 오래된 캐시 삭제
    private func removeOldestCache() {
        guard let oldest = referenceCache.values.min(by: { $0.timestamp < $1.timestamp }) else {
            return
        }
        removeCache(id: oldest.id)
    }

    // MARK: - 통계

    var cacheCount: Int {
        return referenceCache.count
    }

    var cachedIds: [String] {
        return Array(referenceCache.keys)
    }
}
