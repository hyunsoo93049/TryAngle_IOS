import Foundation
import CoreGraphics

// MARK: - 가이드 타입
public enum GuideType: String, CaseIterable {
    case enterFrame = "프레임 진입"       // 인물이 화면에 없음
    case moveForward = "앞으로"           // 인물이 작음
    case moveBackward = "뒤로"            // 인물이 큼
    case moveLeft = "왼쪽으로"            // 인물이 오른쪽에 치우침
    case moveRight = "오른쪽으로"         // 인물이 왼쪽에 치우침
    case tiltUp = "위로 틸트"             // 인물이 아래에 있음
    case tiltDown = "아래로 틸트"         // 인물이 위에 있음
    case zoomIn = "줌인"                  // 줌 배율 증가 필요
    case zoomOut = "줌아웃"               // 줌 배율 감소 필요
    case adjustPose = "포즈 조정"         // 포즈 조정 필요
    case perfect = "완벽"                 // 모든 조건 충족

    public var icon: String {
        switch self {
        case .enterFrame: return "👤"
        case .moveForward: return "🚶"
        case .moveBackward: return "🚶"
        case .moveLeft: return "◀️"
        case .moveRight: return "▶️"
        case .tiltUp: return "⬆️"
        case .tiltDown: return "⬇️"
        case .zoomIn: return "🔍"
        case .zoomOut: return "🔭"
        case .adjustPose: return "🤸"
        case .perfect: return "✨"
        }
    }
}

// MARK: - 피드백 단계 (UI 표시용)
public enum FeedbackStage: String {
    case frameEntry = "프레임 진입"
    case shotType = "샷타입"         // 크기/거리 조정
    case position = "위치"           // 좌우/상하 위치 조정
    case zoom = "줌"                 // 줌 배율 조정
    case pose = "포즈"               // 포즈 조정
    case perfect = "완벽"            // 모든 조건 충족

    public var displayName: String {
        return rawValue
    }

    public var icon: String {
        switch self {
        case .frameEntry: return "👤"
        case .shotType: return "📸"
        case .position: return "↔️"
        case .zoom: return "🔍"
        case .pose: return "🤸"
        case .perfect: return "✅"
        }
    }

    public var color: String {
        switch self {
        case .frameEntry: return "red"
        case .shotType: return "orange"
        case .position: return "purple"
        case .zoom: return "cyan"
        case .pose: return "pink"
        case .perfect: return "green"
        }
    }
}

// MARK: - 가이드 결과
public struct SimpleGuideResult: Equatable {
    public let guide: GuideType
    public let magnitude: String           // "반 걸음", "한 걸음", "조금" 등
    public let progress: CGFloat           // 0.0 ~ 1.0 (전체 진행률)
    public let debugInfo: String           // 디버그용 정보
    public let shotTypeMatch: Bool         // 샷타입 일치 여부
    public let currentShotType: String     // 현재 샷타입 이름
    public let targetShotType: String      // 목표 샷타입 이름
    public let feedbackStage: FeedbackStage // 피드백 단계 (UI 표시용)

    // 🆕 상세 정보
    public let tiltAngle: Int?             // 틸트 각도
    public let positionPercent: Int?       // 이동 퍼센트
    public let currentZoom: CGFloat?       // 현재 줌 배율
    public let targetZoom: CGFloat?        // 목표 줌 배율

    public init(
        guide: GuideType,
        magnitude: String,
        progress: CGFloat,
        debugInfo: String,
        shotTypeMatch: Bool,
        currentShotType: String,
        targetShotType: String,
        feedbackStage: FeedbackStage,
        tiltAngle: Int? = nil,
        positionPercent: Int? = nil,
        currentZoom: CGFloat? = nil,
        targetZoom: CGFloat? = nil
    ) {
        self.guide = guide
        self.magnitude = magnitude
        self.progress = progress
        self.debugInfo = debugInfo
        self.shotTypeMatch = shotTypeMatch
        self.currentShotType = currentShotType
        self.targetShotType = targetShotType
        self.feedbackStage = feedbackStage
        self.tiltAngle = tiltAngle
        self.positionPercent = positionPercent
        self.currentZoom = currentZoom
        self.targetZoom = targetZoom
    }

    // MARK: - Computed Properties

    /// UI 표시용 메시지
    public var displayMessage: String {
        switch guide {
        case .enterFrame:
            return "프레임 안으로 들어오세요"
        case .moveForward, .moveBackward:
            return "\(magnitude) \(guide.rawValue)"
        case .moveLeft, .moveRight:
            return "\(guide.rawValue)으로 \(magnitude)"
        case .tiltUp, .tiltDown:
            if let angle = tiltAngle {
                return "\(guide.rawValue) \(angle)°"
            }
            return guide.rawValue
        case .zoomIn, .zoomOut:
            if let current = currentZoom, let target = targetZoom {
                return "\(guide.rawValue) (현재 \(String(format: "%.1fx", current)) → \(String(format: "%.1fx", target)))"
            }
            return guide.rawValue
        case .adjustPose:
            return "포즈를 조정해주세요"
        case .perfect:
            return "완벽한 구도입니다!"
        }
    }
}
