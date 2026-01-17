import Foundation
import UIKit
import AVFoundation

// MARK: - Reference Types
// 역할: 레퍼런스 분석에서 사용되는 모든 데이터 구조(입력, 출력, 컨텍스트)를 정의합니다.
//       모듈 간 데이터 전달의 표준 형식입니다.

// MARK: - Input

/// 레퍼런스 분석 입력 데이터
struct ReferenceInput {
    /// 레퍼런스 이미지
    let image: UIImage

    /// 원본 이미지 데이터 (EXIF 추출용)
    let imageData: Data?

    /// 이미지 크기
    let imageSize: CGSize

    /// 카메라 위치 (앨범에서 가져온 경우 unknown)
    let cameraPosition: AVCaptureDevice.Position

    init(image: UIImage, imageData: Data? = nil, cameraPosition: AVCaptureDevice.Position = .unspecified) {
        self.image = image
        self.imageData = imageData ?? image.jpegData(compressionQuality: 1.0)
        self.imageSize = image.size
        self.cameraPosition = cameraPosition
    }
}

// MARK: - Context (모듈 간 공유 데이터)

/// 분석 컨텍스트 - 모듈들이 결과를 저장하고 다음 모듈에서 참조할 수 있는 공유 저장소
struct ReferenceContext {
    // MARK: - Pipeline 결과 (DetectionPipeline에서 채워짐)
    var poseResult: PoseDetectionResult?
    var depthResult: DepthEstimationResult?
    var segmentationResult: SegmentationResult?

    // MARK: - 모듈별 결과
    var exifInfo: EXIFInfo?
    var framingResult: PhotographyFramingResult?
    var compositionType: CompositionType?
    var aspectRatio: CameraAspectRatio?
    var preciseBBox: CGRect?

    // MARK: - 키포인트 (편의 접근)
    var poseKeypoints: [(point: CGPoint, confidence: Float)]? {
        guard let pose = poseResult else { return nil }
        return zip(pose.keypoints, pose.confidences).map { (point: $0, confidence: $1) }
    }

    init() {}
}

// MARK: - EXIF Info

/// EXIF 메타데이터 정보
struct EXIFInfo {
    let focalLength: Double?          // 실제 초점거리 (mm)
    let focalLength35mm: Double?      // 35mm 환산 초점거리
    let aperture: Double?             // 조리개 (f-number)
    let iso: Int?                     // ISO 감도
    let exposureTime: Double?         // 노출 시간 (초)
    let lensModel: String?            // 렌즈 모델명

    init(focalLength: Double? = nil, focalLength35mm: Double? = nil,
         aperture: Double? = nil, iso: Int? = nil,
         exposureTime: Double? = nil, lensModel: String? = nil) {
        self.focalLength = focalLength
        self.focalLength35mm = focalLength35mm
        self.aperture = aperture
        self.iso = iso
        self.exposureTime = exposureTime
        self.lensModel = lensModel
    }
}

// MARK: - Final Result

/// 레퍼런스 분석 최종 결과
struct ReferenceAnalysisResult {
    let input: ReferenceInput
    let context: ReferenceContext
    let timestamp: Date

    /// 분석 성공 여부 (최소한 포즈가 검출되어야 성공)
    var isValid: Bool {
        return context.poseResult != nil
    }

    /// 디버그용 요약
    var debugSummary: String {
        var parts: [String] = []
        parts.append("Pose: \(context.poseResult != nil ? "✅" : "❌")")
        parts.append("Depth: \(context.depthResult != nil ? "✅" : "❌")")
        parts.append("EXIF: \(context.exifInfo != nil ? "✅" : "❌")")
        parts.append("Framing: \(context.framingResult != nil ? "✅" : "❌")")
        return "📸 Reference: [\(parts.joined(separator: " | "))]"
    }

    init(input: ReferenceInput, context: ReferenceContext) {
        self.input = input
        self.context = context
        self.timestamp = Date()
    }
}
