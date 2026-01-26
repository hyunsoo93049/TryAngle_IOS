import Foundation
import UIKit
import Combine

// MARK: - Analysis State Manager
// 역할: 앱 전체 분석 상태를 중앙 관리
// @MainActor로 스레드 안전성 보장 (레이스 컨디션 방지)

@MainActor
final class AnalysisStateManager: ObservableObject {

    // MARK: - Singleton
    static let shared = AnalysisStateManager()

    // MARK: - Published State (UI 바인딩)

    /// 현재 피드백 상태
    @Published private(set) var feedbackState: FeedbackState = .idle

    /// 진행률 상태 (Temporal Lock)
    @Published private(set) var progressState: ProgressState = .none

    /// 레퍼런스 상태
    @Published private(set) var referenceState: ReferenceState = .none

    /// 환경 경고 (너무 어두움 등)
    @Published private(set) var environmentWarning: String?

    /// 디버그 정보
    @Published private(set) var debugInfo: DebugInfo?

    // MARK: - Legacy Compatibility (기존 UI 호환)

    /// SimpleGuideResult 호환
    @Published private(set) var simpleGuide: SimpleGuideResult?

    /// GateEvaluation 호환
    @Published private(set) var gateEvaluation: GateEvaluation?

    /// ActiveFeedback 호환
    @Published private(set) var activeFeedback: ActiveFeedback?

    /// 완벽 상태 여부
    @Published private(set) var isPerfect: Bool = false

    /// Temporal Lock 진행률 (0.0 ~ 1.0)
    @Published private(set) var stabilityProgress: Float = 0.0

    // MARK: - State Types

    enum FeedbackState: Equatable {
        case idle
        case aspectRatioMismatch(current: String, target: String)
        case guiding(stage: FeedbackStage, message: String, magnitude: String)
        case perfect

        var isAspectRatioMismatch: Bool {
            if case .aspectRatioMismatch = self { return true }
            return false
        }
    }

    enum ProgressState: Equatable {
        case none
        case arming(progress: Float)
        case locked

        var isLocked: Bool {
            if case .locked = self { return true }
            return false
        }
    }

    enum ReferenceState: Equatable {
        case none
        case analyzing
        case ready(shotType: String, aspectRatio: String)
        case failed(reason: String)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    struct DebugInfo: Equatable {
        let shotTypeInfo: String?
        let keypointCount: Int
        let evaluationTime: TimeInterval
        let frameCount: Int
    }

    // MARK: - Temporal Lock State Machine

    private enum StabilityState: Equatable {
        case idle
        case arming(startedAt: Date)
        case locked
    }

    private var stabilityState: StabilityState = .idle
    private let lockDuration: TimeInterval = 0.5  // 0.5초 유지 시 성공

    // MARK: - Initialization

    private init() {}

    // MARK: - State Updates (원자적 업데이트)

    /// 피드백 상태 업데이트
    func updateFeedback(_ newState: FeedbackState) {
        feedbackState = newState
    }

    /// SimpleGuide 결과 업데이트 (Legacy 호환)
    func updateSimpleGuide(_ guide: SimpleGuideResult?) {
        simpleGuide = guide

        // FeedbackState도 동기화
        if let guide = guide {
            switch guide.guide {
            case .perfect:
                feedbackState = .perfect
            case .enterFrame:
                feedbackState = .guiding(stage: .frameEntry, message: guide.displayMessage, magnitude: guide.magnitude)
            default:
                feedbackState = .guiding(stage: guide.feedbackStage, message: guide.displayMessage, magnitude: guide.magnitude)
            }
        } else {
            feedbackState = .idle
        }
    }

    /// GateEvaluation 업데이트 (Legacy 호환)
    func updateGateEvaluation(_ evaluation: GateEvaluation?) {
        gateEvaluation = evaluation

        // 비율 불일치 체크
        if let eval = evaluation, !eval.gate0.passed {
            feedbackState = .aspectRatioMismatch(
                current: extractCurrentRatio(from: eval.gate0.debugInfo),
                target: extractTargetRatio(from: eval.gate0.debugInfo)
            )
        }
    }

    /// Temporal Lock 업데이트
    func updateTemporalLock(isPerfect: Bool) {
        if isPerfect {
            switch stabilityState {
            case .idle:
                stabilityState = .arming(startedAt: Date())
                stabilityProgress = 0.0
                progressState = .arming(progress: 0.0)

            case .arming(let startedAt):
                let elapsed = Date().timeIntervalSince(startedAt)
                let progress = Float(min(elapsed / lockDuration, 1.0))
                stabilityProgress = progress
                progressState = .arming(progress: progress)

                if elapsed >= lockDuration {
                    stabilityState = .locked
                    stabilityProgress = 1.0
                    progressState = .locked
                    self.isPerfect = true
                }

            case .locked:
                stabilityProgress = 1.0
                progressState = .locked
                self.isPerfect = true
            }
        } else {
            // 조건 깨짐 → 즉시 리셋
            stabilityState = .idle
            stabilityProgress = 0.0
            progressState = .none
            self.isPerfect = false
        }
    }

    /// 레퍼런스 상태 업데이트
    func updateReference(_ newState: ReferenceState) {
        referenceState = newState
    }

    /// 환경 경고 업데이트
    func updateEnvironmentWarning(_ warning: String?) {
        environmentWarning = warning
    }

    /// 디버그 정보 업데이트
    func updateDebugInfo(_ info: DebugInfo?) {
        debugInfo = info
    }

    /// ActiveFeedback 업데이트
    func updateActiveFeedback(_ feedback: ActiveFeedback?) {
        activeFeedback = feedback
    }

    // MARK: - Reset Methods

    /// 촬영 완료 후 리셋
    func resetAfterCapture() {
        stabilityState = .idle
        stabilityProgress = 0.0
        progressState = .none
        isPerfect = false
    }

    /// 전체 상태 리셋
    func resetAll() {
        feedbackState = .idle
        progressState = .none
        referenceState = .none
        environmentWarning = nil
        debugInfo = nil
        simpleGuide = nil
        gateEvaluation = nil
        activeFeedback = nil
        isPerfect = false
        stabilityProgress = 0.0
        stabilityState = .idle
    }

    /// 레퍼런스 클리어
    func clearReference() {
        referenceState = .none
        feedbackState = .idle
        simpleGuide = nil
        gateEvaluation = nil
    }

    // MARK: - Helper Methods

    private func extractCurrentRatio(from debugInfo: String?) -> String {
        guard let info = debugInfo else { return "?" }
        // "현재: 16:9 vs 목표: 4:3" 형식에서 추출
        if let range = info.range(of: "현재: ") {
            let start = range.upperBound
            if let endRange = info[start...].range(of: " vs") {
                return String(info[start..<endRange.lowerBound])
            }
        }
        return "?"
    }

    private func extractTargetRatio(from debugInfo: String?) -> String {
        guard let info = debugInfo else { return "?" }
        if let range = info.range(of: "목표: ") {
            return String(info[range.upperBound...])
        }
        return "?"
    }
}

// MARK: - Convenience Extensions

extension AnalysisStateManager {

    /// 현재 상태가 피드백을 표시해야 하는지
    var shouldShowFeedback: Bool {
        switch feedbackState {
        case .idle:
            return false
        case .aspectRatioMismatch, .guiding, .perfect:
            return true
        }
    }

    /// 현재 피드백 메시지
    var currentFeedbackMessage: String? {
        switch feedbackState {
        case .idle:
            return nil
        case .aspectRatioMismatch(let current, let target):
            return "카메라 비율을 \(target)로 변경하세요 (현재: \(current))"
        case .guiding(_, let message, _):
            return message
        case .perfect:
            return "완벽한 구도입니다!"
        }
    }
}
