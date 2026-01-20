import Foundation

// MARK: - Gate Module Protocol

/// 하나의 평가 기준(Gate)을 담당하는 모듈
public protocol GateModule {
    /// Gate의 이름 (디버깅용)
    var name: String { get }
    
    /// 실행 우선순위 (낮을수록 먼저 실행)
    var priority: Int { get }
    
    /// 평가 수행
    /// - Parameter context: 파이프라인 분석 결과
    /// - Returns: 평가 결과 (Pass/Fail, Score, Feedback)
    func evaluate(context: GateContext) -> GateResult
}

/// Gate 평가에 필요한 모든 컨텍스트 정보
/// (FrameAnalysisResult + 레퍼런스 정보 + 기타 설정)
public struct GateContext {
    public let analysis: FrameAnalysisResult
    public let reference: ReferenceData?
    public let settings: GateSettings
    
    public init(analysis: FrameAnalysisResult, reference: ReferenceData?, settings: GateSettings) {
        self.analysis = analysis
        self.reference = reference
        self.settings = settings
    }
}

/// 레퍼런스 데이터 묶음
public struct ReferenceData {
    // 필요한 레퍼런스 정보들 (기존 GateSystem 인자 참조)
    public let bbox: CGRect?
    public let imageSize: CGSize?
    public let compressionIndex: CGFloat?
    public let aspectRatio: CameraAspectRatio
    public let keypoints: [PoseKeypoint]?
    public let focalLength: FocalLengthInfo?
    public let shotType: ShotTypeGate? // 미리 분석된 레퍼런스 샷타입

    // 🆕 LensDistanceGate용 추가 필드
    public let shoulderRatio: CGFloat?      // 레퍼런스 어깨 픽셀 비율 (0~1)
    public let estimatedDistance: Float?    // 레퍼런스 추정 거리 (meters)

    // 기존 호환성 유지하는 init (기본값 nil)
    public init(bbox: CGRect?, imageSize: CGSize?, compressionIndex: CGFloat?, aspectRatio: CameraAspectRatio, keypoints: [PoseKeypoint]?, focalLength: FocalLengthInfo?, shotType: ShotTypeGate?) {
        self.bbox = bbox
        self.imageSize = imageSize
        self.compressionIndex = compressionIndex
        self.aspectRatio = aspectRatio
        self.keypoints = keypoints
        self.focalLength = focalLength
        self.shotType = shotType
        self.shoulderRatio = nil
        self.estimatedDistance = nil
    }

    // 🆕 전체 필드 init
    public init(bbox: CGRect?, imageSize: CGSize?, compressionIndex: CGFloat?, aspectRatio: CameraAspectRatio, keypoints: [PoseKeypoint]?, focalLength: FocalLengthInfo?, shotType: ShotTypeGate?, shoulderRatio: CGFloat?, estimatedDistance: Float?) {
        self.bbox = bbox
        self.imageSize = imageSize
        self.compressionIndex = compressionIndex
        self.aspectRatio = aspectRatio
        self.keypoints = keypoints
        self.focalLength = focalLength
        self.shotType = shotType
        self.shoulderRatio = shoulderRatio
        self.estimatedDistance = estimatedDistance
    }
}

/// Gate 설정값 (Thresholds 등)
public struct GateSettings {
    public let thresholds: GateThresholds
    public let difficultyMultiplier: CGFloat
    public let targetZoomFactor: CGFloat?

    // 🆕 LensDistanceGate용 추가 필드
    public let currentZoomFactor: CGFloat   // 현재 줌 배율
    public let bodyType: BodyType           // 사용자 체형 설정

    // 기존 호환성 유지하는 init (기본값 적용)
    public init(thresholds: GateThresholds, difficultyMultiplier: CGFloat, targetZoomFactor: CGFloat?) {
        self.thresholds = thresholds
        self.difficultyMultiplier = difficultyMultiplier
        self.targetZoomFactor = targetZoomFactor
        self.currentZoomFactor = 1.0        // 기본값: 1x
        self.bodyType = .medium             // 기본값: 보통 체형
    }

    // 🆕 전체 필드 init
    public init(thresholds: GateThresholds, difficultyMultiplier: CGFloat, targetZoomFactor: CGFloat?, currentZoomFactor: CGFloat, bodyType: BodyType) {
        self.thresholds = thresholds
        self.difficultyMultiplier = difficultyMultiplier
        self.targetZoomFactor = targetZoomFactor
        self.currentZoomFactor = currentZoomFactor
        self.bodyType = bodyType
    }
}

// GateThresholds는 기존 GateSystem에 정의된 것을 사용하거나 여기로 이동.
// 일단 기존 GateSystem.GateThresholds를 typealias로 사용하거나 재정의.
// 호환성을 위해 GateSystem 내부는 유지하고 여기서 참조하도록 함.
public typealias GateThresholds = GateSystem.GateThresholds
