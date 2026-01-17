import Foundation
import CoreGraphics

// MARK: - Pose Keypoint

/// 포즈 키포인트 (위치 + 신뢰도)
/// 포즈 키포인트 (위치 + 신뢰도)
public struct PoseKeypoint {
    public let location: CGPoint
    public let confidence: Float
    
    public init(location: CGPoint, confidence: Float) {
        self.location = location
        self.confidence = confidence
    }
}

// MARK: - Camera Aspect Ratio

/// 카메라 비율
public enum CameraAspectRatio: String, Codable, CaseIterable, Hashable {
    case ratio16_9 = "16:9"
    case ratio4_3 = "4:3"
    case ratio1_1 = "1:1"

    var displayName: String { rawValue }

    var ratio: CGFloat {
        switch self {
        case .ratio16_9: return 16.0 / 9.0
        case .ratio4_3: return 4.0 / 3.0
        case .ratio1_1: return 1.0
        }
    }

    /// 레퍼런스 이미지로부터 비율 감지
    static func detect(from size: CGSize) -> CameraAspectRatio {
        // 세로/가로 무관하게 긴 변 / 짧은 변으로 비율 계산
        let longSide = max(size.width, size.height)
        let shortSide = min(size.width, size.height)
        let ratio = longSide / shortSide

        // 가장 가까운 비율 찾기
        let ratios: [(CameraAspectRatio, CGFloat)] = [
            (.ratio16_9, abs(ratio - 16.0/9.0)),
            (.ratio4_3, abs(ratio - 4.0/3.0)),
            (.ratio1_1, abs(ratio - 1.0))
        ]

        return ratios.min(by: { $0.1 < $1.1 })?.0 ?? .ratio4_3
    }
}

// MARK: - Feedback Category System

/// 피드백 카테고리 (우선순위 순서)
public enum FeedbackCategory: String, Codable, CaseIterable {
    case pose = "pose"               // 1순위: 포즈
    case position = "position"       // 2순위: 인물 위치 (프레임 내)
    case framing = "framing"         // 3순위: 프레이밍 (거리/줌)
    case angle = "angle"             // 4순위: 카메라 앵글
    case composition = "composition" // 5순위: 구도
    case gaze = "gaze"               // 6순위: 시선

    /// 카테고리별 우선순위 (낮을수록 높은 우선순위)
    var priority: Int {
        switch self {
        case .pose: return 1
        case .position: return 2
        case .framing: return 3
        case .angle: return 4
        case .composition: return 5
        case .gaze: return 6
        }
    }

    /// 카테고리 한글 이름
    var displayName: String {
        switch self {
        case .pose: return "포즈"
        case .position: return "인물 위치"
        case .framing: return "프레이밍"
        case .angle: return "카메라 앵글"
        case .composition: return "구도"
        case .gaze: return "시선"
        }
    }

    /// 카테고리별 아이콘
    var icon: String {
        switch self {
        case .pose: return "💪"
        case .position: return "📍"
        case .framing: return "🔍"
        case .angle: return "📷"
        case .composition: return "🎨"
        case .gaze: return "👀"
        }
    }

    /// 기존 category 문자열을 FeedbackCategory로 매핑
    static func from(categoryString: String) -> FeedbackCategory? {
        // 포즈 관련
        if categoryString.hasPrefix("pose_") || categoryString == "pose" {
            return .pose
        }

        // 위치 관련
        if categoryString == "position_x" || categoryString == "position_y" {
            return .position
        }

        // 프레이밍 관련 (거리/줌/비율/여백/사진학 프레이밍)
        if categoryString == "distance" || categoryString == "aspect_ratio" || categoryString == "padding" || categoryString == "framing" || categoryString == "photography_framing" {
            return .framing
        }

        // 앵글 관련
        if categoryString == "camera_angle" || categoryString == "tilt" {
            return .angle
        }

        // 구도 관련
        if categoryString == "composition" {
            return .composition
        }

        // 시선 관련
        if categoryString == "gaze" || categoryString == "face_yaw" {
            return .gaze
        }

        return nil
    }
}

/// 카테고리별 상태 (UI 체크 표시용)
struct CategoryStatus: Identifiable, Equatable {
    let category: FeedbackCategory
    let isSatisfied: Bool           // 만족 여부 (체크 표시)
    let activeFeedbacks: [FeedbackItem]  // 현재 활성화된 피드백들

    var id: String { category.rawValue }

    /// 카테고리별 우선순위
    var priority: Int { category.priority }

    /// 대표 피드백 메시지 (가장 우선순위 높은 것)
    var primaryMessage: String? {
        activeFeedbacks.first?.message
    }
}

// MARK: - API Response Models

struct AnalysisResponse: Codable {
    let userFeedback: [FeedbackItem]
    let cameraSettings: CameraSettings
    let processingTime: String
    let timestamp: Double
}

struct FeedbackItem: Codable, Identifiable, Equatable {
    let priority: Int
    let icon: String
    let message: String
    let category: String

    // 실시간 진행도 추적
    let currentValue: Double?      // 현재 값 (예: 현재 기울기 10도)
    let targetValue: Double?       // 목표 값 (예: 목표 기울기 0도)
    let tolerance: Double?         // 허용 오차 (예: ±3도)
    let unit: String?              // 단위 (예: "도", "걸음")

    // 🔥 ID를 category만으로 하면 같은 카테고리는 숫자만 업데이트됨
    var id: String { category }

    // 진행률 계산 (0.0 ~ 1.0)
    var progress: Double {
        guard let current = currentValue,
              let target = targetValue else {
            return 0.0
        }

        let diff = abs(target - current)
        let maxDiff = abs(target) + 50.0 // 최대 차이를 임의로 설정
        return max(0.0, min(1.0, 1.0 - (diff / maxDiff)))
    }

    // 완료 여부
    var isCompleted: Bool {
        guard let current = currentValue,
              let target = targetValue,
              let tol = tolerance else {
            return false
        }

        return abs(current - target) <= tol
    }

    // 초과 여부
    var isOvershot: Bool {
        guard let current = currentValue,
              let target = targetValue else {
            return false
        }

        // 목표를 넘어섰는지 체크
        return (target >= 0 && current > target) || (target < 0 && current < target)
    }
}

struct CameraSettings: Codable {
    let iso: Int?
    let wbKelvin: Int?
    let evCompensation: Double?

    enum CodingKeys: String, CodingKey {
        case iso
        case wbKelvin
        case evCompensation
    }
}

// MARK: - Completed Feedback Tracking

// MARK: - 🆕 Active Feedback (안정적인 피드백 표시)

/// 활성 피드백 - 동일 피드백은 진행률만 업데이트, 해결될 때까지 유지
struct ActiveFeedback: Equatable {
    let gateIndex: Int                      // 현재 활성 Gate (0-4)
    let feedbackType: String                // 피드백 타입 (예: "move_left", "zoom_in")
    let message: String                     // 고정 표시할 메시지
    let startTime: Date                     // 시작 시간

    // 진행률 추적
    private(set) var progressHistory: [CGFloat]  // 최근 N개 프레임의 진행률
    private(set) var smoothedProgress: CGFloat   // 스무딩된 진행률
    private(set) var displayedProgress: CGFloat  // 실제 표시되는 진행률 (임계값 적용)

    // 상태
    var isResolved: Bool = false            // 해결 여부
    var resolvedTime: Date?                 // 해결된 시간

    // 설정
    static let historySize = 5              // 이동 평균 크기
    static let minDisplayDuration: TimeInterval = 2.0  // 최소 표시 시간 (초)
    static let progressThreshold: CGFloat = 0.05       // 진행률 변화 임계값 (5%)
    static let resolvedDisplayDuration: TimeInterval = 1.5  // 해결 후 표시 시간

    /// 고유 ID
    var id: String { "\(gateIndex)_\(feedbackType)" }

    init(gateIndex: Int, feedbackType: String, message: String, initialProgress: CGFloat = 0.0) {
        self.gateIndex = gateIndex
        self.feedbackType = feedbackType
        self.message = message
        self.startTime = Date()
        self.progressHistory = [initialProgress]
        self.smoothedProgress = initialProgress
        self.displayedProgress = initialProgress
    }

    /// 진행률 업데이트 (스무딩 + 임계값 적용)
    mutating func updateProgress(_ newProgress: CGFloat) {
        // 히스토리에 추가
        progressHistory.append(newProgress)
        if progressHistory.count > Self.historySize {
            progressHistory.removeFirst()
        }

        // 이동 평균 계산
        smoothedProgress = progressHistory.reduce(0, +) / CGFloat(progressHistory.count)

        // 임계값 적용: 변화가 크거나 완료에 가까울 때만 업데이트
        let diff = abs(smoothedProgress - displayedProgress)
        if diff >= Self.progressThreshold || smoothedProgress >= 0.95 {
            displayedProgress = smoothedProgress
        }

        // 해결 체크 (진행률 100%)
        if smoothedProgress >= 1.0 && !isResolved {
            isResolved = true
            resolvedTime = Date()
        }
    }

    /// 표시 시간 (시작부터 현재까지)
    var displayDuration: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    /// 최소 표시 시간이 지났는지
    var hasMinDisplayTimePassed: Bool {
        displayDuration >= Self.minDisplayDuration
    }

    /// 해결 후 표시 시간이 지났는지 (페이드아웃 완료)
    var shouldRemove: Bool {
        guard isResolved, let resolved = resolvedTime else { return false }
        return Date().timeIntervalSince(resolved) >= Self.resolvedDisplayDuration
    }

    /// 해결 후 페이드 진행률 (0.0 ~ 1.0)
    var fadeProgress: CGFloat {
        guard isResolved, let resolved = resolvedTime else { return 1.0 }
        let elapsed = Date().timeIntervalSince(resolved)
        if elapsed < 0.5 {
            return 1.0  // 0.5초 동안 완전히 보임
        } else {
            // 0.5초 ~ 1.5초 사이에 페이드아웃
            return max(0.0, 1.0 - CGFloat((elapsed - 0.5) / 1.0))
        }
    }
}

/// 완료된 피드백 (사라지는 애니메이션용)
struct CompletedFeedback: Identifiable, Equatable {
    let item: FeedbackItem
    let completedAt: Date

    var id: String { item.id }

    /// 완료된 지 얼마나 지났는지 (초)
    var elapsedTime: TimeInterval {
        Date().timeIntervalSince(completedAt)
    }

    /// 아직 표시되어야 하는지 (2초 동안 표시)
    var shouldDisplay: Bool {
        elapsedTime < 2.0
    }

    /// 페이드아웃 진행도 (0.0 ~ 1.0, 1.5초부터 페이드 시작)
    var fadeProgress: Double {
        if elapsedTime < 1.5 {
            return 1.0  // 완전히 보임
        } else {
            // 1.5초 ~ 2.0초 사이에 페이드아웃
            let fadeTime = elapsedTime - 1.5
            return max(0.0, 1.0 - (fadeTime / 0.5))
        }
    }
}
