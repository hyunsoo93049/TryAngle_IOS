import Foundation
import UIKit
import Combine

// MARK: - Detection Module Interfaces

/// 모든 감지 모듈의 기본 프로토콜
public protocol DetectionModule {
    /// 모듈 초기화 (비동기 로딩 등)
    func initialize() async throws
    
    /// 모듈 이름 (디버깅용)
    var name: String { get }
    
    /// 활성화 여부
    var isEnabled: Bool { get set }
}

/// 포즈 감지 모듈 인터페이스
public protocol PoseDetector: DetectionModule {
    func detect(input: FrameInput) async throws -> PoseDetectionResult?
}

/// 깊이/렌즈 심도 추정 모듈 인터페이스
public protocol DepthEstimator: DetectionModule {
    func estimate(input: FrameInput) async throws -> DepthEstimationResult?
}

/// 인물/객체 분할(Silhouette) 모듈 인터페이스
public protocol SubjectSegmentor: DetectionModule {
    func segment(input: FrameInput) async throws -> SegmentationResult?
}

/// 구도/심미성 분석 모듈 인터페이스
public protocol CompositionAnalyzer: DetectionModule {
    func analyze(input: FrameInput, pose: PoseDetectionResult?, depth: DepthEstimationResult?) async throws -> CompositionResult?
}

// MARK: - Result Types placeholder (세부 구현 시 구체화)
// 이 타입들은 각 모듈 구현 파일이나 별도 Types 파일에서 확장될 수 있습니다.

public struct PoseDetectionResult: DetectionResult {
    public let timestamp: TimeInterval
    public let keypoints: [CGPoint] // 정규화된 좌표 (0~1)
    public let confidences: [Float]
    public let roughBBox: CGRect
    
    // v6 로직 호환용
    public let lowestBodyPart: String 
    public let shotType: String
    
    public init(timestamp: TimeInterval, keypoints: [CGPoint], confidences: [Float], roughBBox: CGRect, lowestBodyPart: String = "unknown", shotType: String = "unknown") {
        self.timestamp = timestamp
        self.keypoints = keypoints
        self.confidences = confidences
        self.roughBBox = roughBBox
        self.lowestBodyPart = lowestBodyPart
        self.shotType = shotType
    }
}

public struct DepthEstimationResult: DetectionResult {
    public let timestamp: TimeInterval
    public let depthMap: CVPixelBuffer? // 또는 MLMultiArray
    public let compressionIndex: Float // 압축감 지수
    
    public init(timestamp: TimeInterval, depthMap: CVPixelBuffer?, compressionIndex: Float) {
        self.timestamp = timestamp
        self.depthMap = depthMap
        self.compressionIndex = compressionIndex
    }
}

public struct SegmentationResult: DetectionResult {
    public let timestamp: TimeInterval
    public let mask: UIImage? // 이진 마스크
    
    public init(timestamp: TimeInterval, mask: UIImage?) {
        self.timestamp = timestamp
        self.mask = mask
    }
}

public struct CompositionResult: DetectionResult {
    public let timestamp: TimeInterval
    public let feedback: [String] // 심미성 피드백
    public let score: Float       // 심미성 점수 (0~1)
    
    public init(timestamp: TimeInterval, feedback: [String], score: Float) {
        self.timestamp = timestamp
        self.feedback = feedback
        self.score = score
    }
}
