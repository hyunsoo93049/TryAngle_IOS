//
//  UnifiedFeedbackGenerator.swift
//  통합 피드백 시스템
//  "하나의 동작 → 여러 Gate 동시 해결"
//
//  작성일: 2025-12-07
//
// ============================================================================
// ⚠️ LEGACY CODE - 사용되지 않음 (2025-12-29)
// ============================================================================
// 원래 용도: 여러 Gate 결과를 통합하여 하나의 피드백 메시지 생성
// 사용되지 않는 이유: FeedbackOverlay에서 unifiedFeedback 파라미터가 무시됨
// 대체된 파일: Services/OnDevice/SimpleRealTimeGuide.swift
// 삭제 가능 여부: 주의 - UnifiedFeedback 구조체가 다른 곳에서 참조됨
//                타입 정의만 별도 분리 후 삭제 가능
// ============================================================================

import Foundation
import CoreGraphics

// MARK: - 조정 동작 타입
enum AdjustmentAction: String, CaseIterable {
    case moveForward = "앞으로 이동"
    case moveBackward = "뒤로 이동"
    case moveLeft = "왼쪽으로 이동"
    case moveRight = "오른쪽으로 이동"
    case tiltUp = "카메라 위로 틸트"
    case tiltDown = "카메라 아래로 틸트"
    case zoomIn = "줌 인"
    case zoomOut = "줌 아웃"
    // 🆕 복합 동작 (줌 + 거리)
    case zoomInThenMoveBack = "줌인 후 뒤로 이동"
    case zoomInThenMoveForward = "줌인 후 앞으로 이동"
    case zoomOutThenMoveBack = "줌아웃 후 뒤로 이동"
    case zoomOutThenMoveForward = "줌아웃 후 앞으로 이동"

    /// 이 동작이 영향을 주는 Gate들
    var affectedGates: Set<Int> {
        switch self {
        case .moveForward, .moveBackward:
            return [1, 2]     // 🔧 샷타입 + 여백 (압축감은 거리로 안 바뀜!)
        case .moveLeft, .moveRight:
            return [2]        // 여백만
        case .tiltUp, .tiltDown:
            return [2]        // 여백만
        case .zoomIn, .zoomOut:
            return [1, 3]     // 샷타입 + 압축감
        case .zoomInThenMoveBack, .zoomInThenMoveForward,
             .zoomOutThenMoveBack, .zoomOutThenMoveForward:
            return [1, 2, 3]  // 🆕 복합: 전부
        }
    }

    /// 전면 카메라일 때 방향 반전 여부
    var needsMirrorForFrontCamera: Bool {
        switch self {
        case .moveLeft, .moveRight:
            return true
        default:
            return false
        }
    }

    /// 🆕 줌 동작인지 확인
    var involvesZoom: Bool {
        switch self {
        case .zoomIn, .zoomOut,
             .zoomInThenMoveBack, .zoomInThenMoveForward,
             .zoomOutThenMoveBack, .zoomOutThenMoveForward:
            return true
        default:
            return false
        }
    }
}

// MARK: - 통합 피드백 결과
struct UnifiedFeedback: Equatable {
    let primaryAction: AdjustmentAction   // 주요 동작
    let magnitude: String                  // 크기 (걸음 수, 각도 등)
    let affectedGates: [Int]               // 영향 받는 Gate들
    let expectedResults: [String]          // 예상 결과들
    let priority: Int                      // 우선순위 (낮을수록 높음)

    // 🆕 줌 관련 상세 정보
    let targetZoom: CGFloat?               // 목표 줌 배율 (예: 2.0)
    let zoomFirst: Bool                    // 줌을 먼저 해야 하는지

    init(
        primaryAction: AdjustmentAction,
        magnitude: String,
        affectedGates: [Int],
        expectedResults: [String],
        priority: Int,
        targetZoom: CGFloat? = nil,
        zoomFirst: Bool = false
    ) {
        self.primaryAction = primaryAction
        self.magnitude = magnitude
        self.affectedGates = affectedGates
        self.expectedResults = expectedResults
        self.priority = priority
        self.targetZoom = targetZoom
        self.zoomFirst = zoomFirst
    }

    /// 사용자에게 보여줄 메인 메시지
    var mainMessage: String {
        if let zoom = targetZoom, primaryAction.involvesZoom {
            let zoomText = String(format: "%.1fx", zoom)
            switch primaryAction {
            case .zoomIn:
                return "\(zoomText)로 줌인"
            case .zoomOut:
                return "\(zoomText)로 줌아웃"
            case .zoomInThenMoveBack:
                return "\(zoomText)로 줌인 후, \(magnitude) 뒤로 (배경 압축)"
            case .zoomInThenMoveForward:
                return "\(zoomText)로 줌인 후, \(magnitude) 앞으로 (배경 압축)"
            case .zoomOutThenMoveBack:
                return "\(zoomText)로 줌아웃 후, \(magnitude) 뒤로 (원근감 강조)"
            case .zoomOutThenMoveForward:
                return "\(zoomText)로 줌아웃 후, \(magnitude) 앞으로 (원근감 강조)"
            default:
                return "\(magnitude) \(primaryAction.rawValue)"
            }
        }
        return "\(magnitude) \(primaryAction.rawValue)"
    }

    /// 상세 결과 메시지
    var detailMessage: String {
        if expectedResults.isEmpty {
            return ""
        }
        return expectedResults.joined(separator: "\n")
    }

    // 안정적인 ID (SwiftUI 변경 감지용)
    var stableId: String {
        return "\(primaryAction.rawValue)_\(magnitude)"
    }

    // Equatable: 주요 속성만 비교 (세부 결과는 무시)
    static func == (lhs: UnifiedFeedback, rhs: UnifiedFeedback) -> Bool {
        return lhs.primaryAction == rhs.primaryAction &&
               lhs.magnitude == rhs.magnitude
    }
}

// MARK: - Gate별 문제 분석 결과
struct GateProblem {
    let gateIndex: Int
    let problemType: ProblemType
    let currentValue: CGFloat
    let targetValue: CGFloat
    let severity: CGFloat  // 0.0 ~ 1.0 (심각도)

    enum ProblemType {
        // Gate 1: 프레이밍
        case shotTypeTooWide      // 샷이 너무 넓음 (전신→바스트 필요)
        case shotTypeTooNarrow    // 샷이 너무 좁음 (바스트→전신 필요)
        case coverageTooLow       // 점유율 낮음
        case coverageTooHigh      // 점유율 높음

        // Gate 2: 여백
        case marginLeftHigh       // 좌측 여백 많음 (우측 치우침)
        case marginRightHigh      // 우측 여백 많음 (좌측 치우침)
        case marginTopHigh        // 상단 여백 많음
        case marginBottomHigh     // 하단 여백 많음
        case marginTopLow         // 상단 여백 부족 (잘림)
        case marginBottomLow      // 하단 여백 부족 (잘림)

        // Gate 3: 압축감
        case compressionTooLow    // 광각 효과 너무 강함
        case compressionTooHigh   // 망원 효과 너무 강함

        // Gate 4: 포즈
        case poseAngleDiff        // 포즈 각도 차이
    }
}

// MARK: - 통합 피드백 생성기
class UnifiedFeedbackGenerator {

    static let shared = UnifiedFeedbackGenerator()

    // 🆕 피드백 안정화를 위한 상태
    private var lastFeedback: UnifiedFeedback?
    private var lastFeedbackTime: Date = .distantPast
    private var sameActionCount: Int = 0
    private var consecutiveSameAction: Int = 0  // 🆕 연속 동일 동작 횟수
    private var lastCameraPosition: Bool = false  // 🆕 마지막 카메라 (front/back)

    // 안정화 설정
    private let minFeedbackInterval: TimeInterval = 0.3  // 🔧 0.5초 → 0.3초로 단축
    private let stabilityThreshold: Int = 3  // 3번 연속 동일해야 변경
    private let maxSameActionCount: Int = 30  // 🆕 30회 이상 동일하면 강제 리셋 (stuck 방지)

    private init() {}

    // 🆕 피드백 캐시 리셋 (카메라 전환 시 호출)
    func resetCache() {
        lastFeedback = nil
        lastFeedbackTime = .distantPast
        sameActionCount = 0
        consecutiveSameAction = 0
        #if DEBUG
        print("🔄 [UnifiedFeedback] Cache reset")
        #endif
    }

    // MARK: - 메인 피드백 생성

    /// GateEvaluation에서 통합 피드백 생성
    /// - Parameters:
    ///   - evaluation: Gate 평가 결과
    ///   - isFrontCamera: 전면 카메라 여부
    ///   - currentZoom: 현재 줌 배율 (1.0 = 24mm)
    ///   - targetZoom: 목표 줌 배율 (레퍼런스 기준)
    ///   - currentSubjectSize: 현재 인물 점유율 (0.0 ~ 1.0)
    ///   - targetSubjectSize: 목표 인물 점유율
    func generateUnifiedFeedback(
        from evaluation: GateEvaluation,
        isFrontCamera: Bool = false,
        currentZoom: CGFloat = 1.0,
        targetZoom: CGFloat? = nil,
        currentSubjectSize: CGFloat? = nil,
        targetSubjectSize: CGFloat? = nil
    ) -> UnifiedFeedback? {

        // 🆕 카메라 전환 감지 → 캐시 리셋
        if isFrontCamera != lastCameraPosition {
            #if DEBUG
            print("📷 [UnifiedFeedback] Camera switched: \(lastCameraPosition ? "front" : "back") → \(isFrontCamera ? "front" : "back")")
            #endif
            resetCache()
            lastCameraPosition = isFrontCamera
        }

        // 1. 모든 Gate 통과 시 nil 반환 + 상태 초기화
        if evaluation.allPassed {
            lastFeedback = nil
            sameActionCount = 0
            consecutiveSameAction = 0
            return nil
        }

        // ============================================
        // 🔒 Gate 0 (비율) - 절대 우선! 비율 안 맞으면 다른 피드백 무시
        // ============================================
        if !evaluation.gate0.passed {
            let aspectFeedback = UnifiedFeedback(
                primaryAction: .zoomOut,  // 비율 변경은 동작이 아니므로 placeholder
                magnitude: "",
                affectedGates: [0],
                expectedResults: [],
                priority: 0
            )
            return stabilizeFeedback(aspectFeedback)
        }

        // ============================================
        // 🆕 압축감 기반 스마트 피드백 로직
        // ============================================

        let compressionOK = evaluation.gate3.passed
        let _ = evaluation.gate1.passed
        let _ = evaluation.gate2.passed  // marginOK는 현재 미사용

        // 🔑 핵심 분기: 압축감 상태에 따라 피드백 전략 결정
        if compressionOK {
            // ============================================
            // Case A: 압축감 OK → 거리/위치만 조정 (줌 언급 안함!)
            // ============================================
            return generateDistanceOnlyFeedback(
                evaluation: evaluation,
                isFrontCamera: isFrontCamera
            )
        } else {
            // ============================================
            // Case B: 압축감 NG → 줌 + 거리 복합 조정
            // ============================================
            return generateZoomAndDistanceFeedback(
                evaluation: evaluation,
                isFrontCamera: isFrontCamera,
                currentZoom: currentZoom,
                targetZoom: targetZoom ?? currentZoom,
                currentSubjectSize: currentSubjectSize,
                targetSubjectSize: targetSubjectSize
            )
        }
    }

    // MARK: - 🆕 Case A: 압축감 OK - 거리만 조정

    private func generateDistanceOnlyFeedback(
        evaluation: GateEvaluation,
        isFrontCamera: Bool
    ) -> UnifiedFeedback? {

        // Gate 1, 2만 분석 (Gate 3 압축감은 OK이므로 제외)
        var problems = analyzeProblems(from: evaluation).filter { $0.gateIndex >= 1 && $0.gateIndex <= 2 }

        // 🆕 Gate 1 우선 법칙 (Sequential Feedback)
        // 샷타입(Gate 1)이 틀리면 위치(Gate 2) 피드백은 무시한다.
        // 이유: 거리를 맞추느라 위치가 어차피 변하기 때문.
        if problems.contains(where: { $0.gateIndex == 1 }) {
            problems = problems.filter { $0.gateIndex == 1 }
        }

        if problems.isEmpty {
            lastFeedback = nil
            sameActionCount = 0
            return nil
        }

        // 🔑 핵심: 줌 동작 제외한 가능한 동작만 계산
        let possibleActions = calculateDistanceOnlyActions(for: problems)

        // 최적 동작 선택
        guard let bestAction = selectBestAction(
            possibleActions,
            problems: problems,
            gate1Score: evaluation.gate1.score
        ) else {
            return stabilizeFeedback(createFallbackFeedback(from: evaluation, isFrontCamera: isFrontCamera))
        }

        // 피드백 생성
        let newFeedback = createUnifiedFeedback(
            action: bestAction,
            problems: problems,
            isFrontCamera: isFrontCamera
        )

        return stabilizeFeedback(newFeedback)
    }

    // MARK: - 🆕 Case B: 압축감 NG - 줌 + 거리 복합 조정

    private func generateZoomAndDistanceFeedback(
        evaluation: GateEvaluation,
        isFrontCamera: Bool,
        currentZoom: CGFloat,
        targetZoom: CGFloat,
        currentSubjectSize: CGFloat?,
        targetSubjectSize: CGFloat?
    ) -> UnifiedFeedback? {

        let zoomRatio = targetZoom / currentZoom
        let needZoomIn = zoomRatio > 1.1   // 10% 이상 차이
        let needZoomOut = zoomRatio < 0.9

        // 줌 변경이 필요 없으면 거리만 조정
        if !needZoomIn && !needZoomOut {
            return generateDistanceOnlyFeedback(evaluation: evaluation, isFrontCamera: isFrontCamera)
        }

        // 줌 후 예상 인물 크기 계산
        let curSize = currentSubjectSize ?? 0.5
        let tgtSize = targetSubjectSize ?? 0.4
        let predictedSizeAfterZoom = curSize * zoomRatio

        // 줌 + 거리 조정 결정
        let action: AdjustmentAction
        let magnitude: String
        var expectedResults: [String] = []

        if needZoomIn {
            // 줌인 필요
            if predictedSizeAfterZoom > tgtSize * 1.15 {
                // 줌인 후 너무 커짐 → 뒤로 이동 필요
                action = .zoomInThenMoveBack
                let sizeRatio = predictedSizeAfterZoom / tgtSize
                magnitude = calculateDistanceMagnitude(sizeRatio: sizeRatio)
                expectedResults = ["압축감이 맞춰집니다", "인물 크기가 조정됩니다"]
            } else if predictedSizeAfterZoom < tgtSize * 0.85 {
                // 줌인 후 너무 작아짐 → 앞으로 이동 필요
                action = .zoomInThenMoveForward
                let sizeRatio = tgtSize / predictedSizeAfterZoom
                magnitude = calculateDistanceMagnitude(sizeRatio: sizeRatio)
                expectedResults = ["압축감이 맞춰집니다", "인물 크기가 조정됩니다"]
            } else {
                // 줌인만 하면 크기도 OK
                action = .zoomIn
                magnitude = ""
                expectedResults = ["압축감이 맞춰집니다", "인물 크기도 맞아집니다"]
            }
        } else {
            // 줌아웃 필요
            if predictedSizeAfterZoom < tgtSize * 0.85 {
                // 줌아웃 후 너무 작아짐 → 앞으로 이동 필요
                action = .zoomOutThenMoveForward
                let sizeRatio = tgtSize / predictedSizeAfterZoom
                magnitude = calculateDistanceMagnitude(sizeRatio: sizeRatio)
                expectedResults = ["압축감이 맞춰집니다", "인물 크기가 조정됩니다"]
            } else if predictedSizeAfterZoom > tgtSize * 1.15 {
                // 줌아웃 후 너무 커짐 → 뒤로 이동 필요
                action = .zoomOutThenMoveBack
                let sizeRatio = predictedSizeAfterZoom / tgtSize
                magnitude = calculateDistanceMagnitude(sizeRatio: sizeRatio)
                expectedResults = ["압축감이 맞춰집니다", "인물 크기가 조정됩니다"]
            } else {
                // 줌아웃만 하면 크기도 OK
                action = .zoomOut
                magnitude = ""
                expectedResults = ["압축감이 맞춰집니다", "인물 크기도 맞아집니다"]
            }
        }

        let feedback = UnifiedFeedback(
            primaryAction: action,
            magnitude: magnitude,
            affectedGates: [1, 2, 3],
            expectedResults: expectedResults,
            priority: 3,  // 압축감 우선
            targetZoom: targetZoom,
            zoomFirst: true
        )

        return stabilizeFeedback(feedback)
    }

    // 🆕 크기 비율에서 거리 조정량 계산
    private func calculateDistanceMagnitude(sizeRatio: CGFloat) -> String {
        if sizeRatio < 1.2 {
            return "반 걸음"
        } else if sizeRatio < 1.5 {
            return "한 걸음"
        } else if sizeRatio < 2.0 {
            return "두 걸음"
        } else {
            return "세 걸음"
        }
    }

    // 🆕 줌 제외한 동작만 계산
    private func calculateDistanceOnlyActions(for problems: [GateProblem]) -> [AdjustmentAction] {
        var actions: Set<AdjustmentAction> = []

        let problemTypes = Set(problems.map { $0.problemType })

        // 스마트 상관관계 분석 (기존 로직 유지)
        let hasShotTypeWide = problemTypes.contains(.shotTypeTooWide) || problemTypes.contains(.coverageTooLow)
        let hasShotTypeNarrow = problemTypes.contains(.shotTypeTooNarrow) || problemTypes.contains(.coverageTooHigh)
        let hasTopMarginHigh = problemTypes.contains(.marginTopHigh)
        let hasBottomMarginHigh = problemTypes.contains(.marginBottomHigh)
        let hasTopMarginLow = problemTypes.contains(.marginTopLow)
        let hasBottomMarginLow = problemTypes.contains(.marginBottomLow)

        // 스마트 추론
        if hasShotTypeWide && hasTopMarginHigh {
            actions.insert(.tiltDown)
        }
        if hasShotTypeWide && hasBottomMarginHigh {
            actions.insert(.tiltUp)
        }
        if hasShotTypeNarrow && (hasTopMarginLow || hasBottomMarginLow) {
            actions.insert(.moveBackward)
        }

        for problem in problems {
            switch problem.problemType {
            // 🔑 핵심: 샷타입 문제는 거리로만 해결 (줌 제외!)
            case .shotTypeTooWide, .coverageTooLow:
                actions.insert(.moveForward)
                actions.insert(.tiltDown)
                actions.insert(.tiltUp)
                // ❌ zoomIn 제외!
            case .shotTypeTooNarrow, .coverageTooHigh:
                actions.insert(.moveBackward)
                // ❌ zoomOut 제외!

            // 좌우 여백
            case .marginLeftHigh:
                actions.insert(.moveRight)
            case .marginRightHigh:
                actions.insert(.moveLeft)

            // 상하 여백
            case .marginTopHigh:
                actions.insert(.tiltDown)
            case .marginBottomHigh:
                actions.insert(.tiltUp)
            case .marginTopLow:
                actions.insert(.tiltUp)
                actions.insert(.moveBackward)
            case .marginBottomLow:
                actions.insert(.tiltDown)
                actions.insert(.moveBackward)

            // 압축감 문제는 여기서 처리 안함 (Case B에서 처리)
            case .compressionTooLow, .compressionTooHigh:
                break

            // 포즈
            case .poseAngleDiff:
                break
            }
        }

        return Array(actions)
    }

    // MARK: - 🆕 피드백 안정화 (깜빡임 방지)

    private func stabilizeFeedback(_ newFeedback: UnifiedFeedback?) -> UnifiedFeedback? {
        guard let newFeedback = newFeedback else {
            lastFeedback = nil
            sameActionCount = 0
            consecutiveSameAction = 0
            return nil
        }

        let now = Date()

        // 이전 피드백과 동일한지 확인
        if let last = lastFeedback {
            let isSameAction = (last.primaryAction == newFeedback.primaryAction)

            if isSameAction {
                // 동일한 피드백
                sameActionCount += 1
                consecutiveSameAction += 1

                // 🆕 너무 오래 같은 피드백이 유지되면 강제로 새 피드백 허용
                if consecutiveSameAction >= maxSameActionCount {
                    #if DEBUG
                    print("⚠️ [UnifiedFeedback] Force reset after \(consecutiveSameAction) same actions")
                    #endif
                    consecutiveSameAction = 0
                    // 새 피드백으로 갱신 허용 (아래로 계속)
                } else {
                    // magnitude가 다르면 갱신
                    if last.magnitude != newFeedback.magnitude {
                        lastFeedback = newFeedback
                        lastFeedbackTime = now
                        return newFeedback
                    }
                    return last  // 동일 피드백 유지
                }
            } else {
                // 🔧 다른 피드백이 감지됨 - 즉시 반영!
                // (기존에는 minFeedbackInterval 체크가 있었으나 제거)
                #if DEBUG
                print("🔄 [UnifiedFeedback] Action changed: \(last.primaryAction.rawValue) → \(newFeedback.primaryAction.rawValue)")
                #endif
                consecutiveSameAction = 0
                sameActionCount = 1
            }
        }

        // 새 피드백으로 교체
        lastFeedback = newFeedback
        lastFeedbackTime = now
        sameActionCount = 1
        return newFeedback
    }

    // MARK: - 문제점 분석

    private func analyzeProblems(from evaluation: GateEvaluation) -> [GateProblem] {
        var problems: [GateProblem] = []

        // Gate 1: 프레이밍 분석
        if !evaluation.gate1.passed {
            let framingProblems = analyzeFramingProblems(evaluation.gate1)
            problems.append(contentsOf: framingProblems)
        }

        // Gate 2: 위치/여백 분석
        if !evaluation.gate2.passed {
            let positionProblems = analyzePositionProblems(evaluation.gate2)
            problems.append(contentsOf: positionProblems)
        }

        // Gate 3: 압축감 분석
        if !evaluation.gate3.passed {
            let compressionProblems = analyzeCompressionProblems(evaluation.gate3)
            problems.append(contentsOf: compressionProblems)
        }

        // Gate 4: 포즈 분석 (참고용)
        if !evaluation.gate4.passed {
            let poseProblems = analyzePoseProblems(evaluation.gate4)
            problems.append(contentsOf: poseProblems)
        }

        return problems
    }

    private func analyzeFramingProblems(_ gate: GateResult) -> [GateProblem] {
        var problems: [GateProblem] = []
        let severity = 1.0 - gate.score
        let feedback = gate.feedback

        // 🔧 개선된 패턴 매칭: 순서가 중요! (더 구체적인 패턴 먼저)

        // "너무 가까워요" - 뒤로 가야 함 (shotTypeTooNarrow)
        // ⚠️ "가까이 가세요"와 혼동 방지: "가까워요"는 "뒤로", "가까이"는 "앞으로"
        let needsBackward = feedback.contains("뒤로") ||
                            feedback.contains("물러") ||
                            feedback.contains("작게") || feedback.contains("조금 더 작게") || // 🔧 "조금 더 작게"
                            feedback.contains("멀리") ||       // 🔧 "멀리 하세요"
                            feedback.contains("가까워요") ||
                            feedback.contains("너무 가까") ||
                            feedback.contains("잘렸어요")

        let needsForward = feedback.contains("앞으로") ||
                           feedback.contains("가까이 가") ||   // 🔧 더 구체적: "가까이 가세요"
                           feedback.contains("가까이 하") ||   // 🔧 "가까이 하세요"
                           feedback.contains("다가가") ||      // 🔧 "다가가세요"
                           feedback.contains("더 크게") ||     // 🔧 "조금 더 크게"
                           feedback.contains("작아요")         // 🔧 "인물이 너무 작아요"

        // 🔧 핵심: needsBackward와 needsForward가 둘 다 true일 때
        // "뒤로"가 우선 (안전한 선택 - 잘림 방지)
        // 하지만 "앞으로 다가"와 같이 명확한 forward 지시가 있으면 forward

        if needsForward && !needsBackward {
            // 명확히 앞으로만 필요
            problems.append(GateProblem(
                gateIndex: 1,
                problemType: .shotTypeTooWide,
                currentValue: gate.score,
                targetValue: 1.0,
                severity: severity
            ))
        } else if needsBackward {
            // 뒤로 필요 (또는 둘 다 매칭되면 뒤로 우선)
            problems.append(GateProblem(
                gateIndex: 1,
                problemType: .shotTypeTooNarrow,
                currentValue: gate.score,
                targetValue: 1.0,
                severity: severity
            ))
        } else if !gate.passed {
            // 🆕 어떤 패턴도 매칭되지 않았지만 Gate 1이 실패함
            // 점수 기반 추론: 낮은 점수 = 큰 차이 = 문제 있음
            // 기본값: shotTypeTooWide (앞으로 가라) - 안전한 쪽
            #if DEBUG
            print("⚠️ [UnifiedFeedback] Gate1 failed but no pattern matched: \"\(feedback)\"")
            #endif
            problems.append(GateProblem(
                gateIndex: 1,
                problemType: .shotTypeTooWide,  // 기본값: 앞으로
                currentValue: gate.score,
                targetValue: 1.0,
                severity: severity * 0.5  // 불확실하므로 심각도 낮춤
            ))
        }

        return problems
    }

    private func analyzePositionProblems(_ gate: GateResult) -> [GateProblem] {
        var problems: [GateProblem] = []
        let severity = 1.0 - gate.score
        let feedback = gate.feedback

        // 좌우 분석 (GateSystem: "오른쪽으로 한 걸음 이동", "왼쪽으로 이동")
        if feedback.contains("오른쪽으로") {
            problems.append(GateProblem(
                gateIndex: 2,
                problemType: .marginLeftHigh,  // 왼쪽 여백 많음 → 오른쪽으로
                currentValue: gate.score,
                targetValue: 1.0,
                severity: severity
            ))
        }
        if feedback.contains("왼쪽으로") {
            problems.append(GateProblem(
                gateIndex: 2,
                problemType: .marginRightHigh,  // 오른쪽 여백 많음 → 왼쪽으로
                currentValue: gate.score,
                targetValue: 1.0,
                severity: severity
            ))
        }

        // 🆕 상하 분석 - GateSystem 실제 피드백 패턴 매칭
        // "카메라를 5° 아래로 틸트" → 상단 여백 많음 (인물이 프레임 아래에 있음)
        if feedback.contains("아래로 틸트") || feedback.contains("아래로 내리") {
            problems.append(GateProblem(
                gateIndex: 2,
                problemType: .marginTopHigh,
                currentValue: gate.score,
                targetValue: 1.0,
                severity: severity
            ))
        }
        // "카메라를 5° 위로 틸트" → 하단 여백 많음 (인물이 프레임 위에 있음)
        if feedback.contains("위로 틸트") || feedback.contains("위로 올리") {
            problems.append(GateProblem(
                gateIndex: 2,
                problemType: .marginBottomHigh,
                currentValue: gate.score,
                targetValue: 1.0,
                severity: severity
            ))
        }
        // "하단 여백이 너무 많아요" → 하단 여백 많음
        if feedback.contains("하단 여백") && feedback.contains("많") {
            problems.append(GateProblem(
                gateIndex: 2,
                problemType: .marginBottomHigh,
                currentValue: gate.score,
                targetValue: 1.0,
                severity: severity
            ))
        }
        // "하단이 잘렸어요" → 하단 잘림
        if feedback.contains("하단") && feedback.contains("잘") {
            problems.append(GateProblem(
                gateIndex: 2,
                problemType: .marginBottomLow,
                currentValue: gate.score,
                targetValue: 1.0,
                severity: severity
            ))
        }
        // "상단이 잘렸어요" or "머리가 잘렸어요"
        if (feedback.contains("상단") || feedback.contains("머리")) && feedback.contains("잘") {
            problems.append(GateProblem(
                gateIndex: 2,
                problemType: .marginTopLow,
                currentValue: gate.score,
                targetValue: 1.0,
                severity: severity
            ))
        }
        // "하단 여백이 부족해요"
        if feedback.contains("하단 여백") && feedback.contains("부족") {
            problems.append(GateProblem(
                gateIndex: 2,
                problemType: .marginBottomLow,
                currentValue: gate.score,
                targetValue: 1.0,
                severity: severity
            ))
        }

        return problems
    }

    private func analyzeCompressionProblems(_ gate: GateResult) -> [GateProblem] {
        var problems: [GateProblem] = []
        let severity = 1.0 - gate.score
        let feedback = gate.feedback

        // 🔥 통합 피드백 파싱 개선: "줌인"/"줌아웃" 우선 체크
        // 통합 피드백: "📐 많이 뒤로 물러나서 2.1x로 줌인 (배경 압축)"
        // → "줌인" 키워드가 핵심 (뒤로는 거리 조정)

        if feedback.contains("줌인") {
            // 줌인 필요 (광각 → 망원)
            problems.append(GateProblem(
                gateIndex: 3,
                problemType: .compressionTooLow,
                currentValue: gate.score,
                targetValue: 1.0,
                severity: severity
            ))
        } else if feedback.contains("줌아웃") {
            // 줌아웃 필요 (망원 → 광각)
            problems.append(GateProblem(
                gateIndex: 3,
                problemType: .compressionTooHigh,
                currentValue: gate.score,
                targetValue: 1.0,
                severity: severity
            ))
        } else if feedback.contains("가까이") {
            // 레거시 피드백: 가까이 가기
            problems.append(GateProblem(
                gateIndex: 3,
                problemType: .compressionTooLow,
                currentValue: gate.score,
                targetValue: 1.0,
                severity: severity
            ))
        } else if feedback.contains("물러나") && !feedback.contains("줌") {
            // 단독 "물러나" 피드백만 (줌 언급 없을 때)
            problems.append(GateProblem(
                gateIndex: 3,
                problemType: .compressionTooHigh,
                currentValue: gate.score,
                targetValue: 1.0,
                severity: severity
            ))
        }

        return problems
    }

    private func analyzePoseProblems(_ gate: GateResult) -> [GateProblem] {
        // 포즈는 동작으로 해결하기 어려우므로 별도 처리
        if !gate.passed {
            return [GateProblem(
                gateIndex: 4,
                problemType: .poseAngleDiff,
                currentValue: gate.score,
                targetValue: 1.0,
                severity: 1.0 - gate.score
            )]
        }
        return []
    }

    // MARK: - 가능한 동작 계산

    private func calculatePossibleActions(for problems: [GateProblem]) -> [AdjustmentAction] {
        var actions: Set<AdjustmentAction> = []

        // 🆕 문제 유형 집합 (상관관계 분석용)
        let problemTypes = Set(problems.map { $0.problemType })

        // 🆕 샷타입 + 여백 상관관계 분석
        let hasShotTypeWide = problemTypes.contains(.shotTypeTooWide) || problemTypes.contains(.coverageTooLow)
        let hasShotTypeNarrow = problemTypes.contains(.shotTypeTooNarrow) || problemTypes.contains(.coverageTooHigh)
        let hasTopMarginHigh = problemTypes.contains(.marginTopHigh)
        let hasBottomMarginHigh = problemTypes.contains(.marginBottomHigh)
        let hasTopMarginLow = problemTypes.contains(.marginTopLow)
        let hasBottomMarginLow = problemTypes.contains(.marginBottomLow)

        // 🔥 스마트 동작 추론: 여백 조정으로 샷타입도 해결
        // 샷타입 넓음 + 상단 여백 많음 → 틸트 다운 (여백 줄이면서 샷타입도 좁아짐)
        if hasShotTypeWide && hasTopMarginHigh {
            actions.insert(.tiltDown)  // 우선 추천
        }
        // 샷타입 넓음 + 하단 여백 많음 → 틸트 업
        if hasShotTypeWide && hasBottomMarginHigh {
            actions.insert(.tiltUp)  // 우선 추천
        }
        // 샷타입 좁음 + 상단 잘림 → 뒤로 이동 (둘 다 해결)
        if hasShotTypeNarrow && hasTopMarginLow {
            actions.insert(.moveBackward)
        }
        // 샷타입 좁음 + 하단 잘림 → 뒤로 이동 (둘 다 해결)
        if hasShotTypeNarrow && hasBottomMarginLow {
            actions.insert(.moveBackward)
        }

        for problem in problems {
            switch problem.problemType {
            // 샷타입 문제 (기본 동작)
            case .shotTypeTooWide, .coverageTooLow:
                actions.insert(.moveForward)
                actions.insert(.zoomIn)
                // 🆕 여백 조정도 가능한 옵션으로 추가
                actions.insert(.tiltDown)
                actions.insert(.tiltUp)
            case .shotTypeTooNarrow, .coverageTooHigh:
                actions.insert(.moveBackward)
                actions.insert(.zoomOut)

            // 좌우 여백 문제
            case .marginLeftHigh:
                actions.insert(.moveRight)
            case .marginRightHigh:
                actions.insert(.moveLeft)

            // 상하 여백 문제
            case .marginTopHigh:
                actions.insert(.tiltDown)
            case .marginBottomHigh:
                actions.insert(.tiltUp)
            case .marginTopLow:
                actions.insert(.tiltUp)
                actions.insert(.moveBackward)
            case .marginBottomLow:
                actions.insert(.tiltDown)
                actions.insert(.moveBackward)

            // 압축감 문제
            case .compressionTooLow:
                actions.insert(.moveForward)
                actions.insert(.zoomIn)
            case .compressionTooHigh:
                actions.insert(.moveBackward)
                actions.insert(.zoomOut)

            // 포즈는 동작으로 해결 불가
            case .poseAngleDiff:
                break
            }
        }

        return Array(actions)
    }

    // MARK: - 최적 동작 선택

    private func selectBestAction(
        _ actions: [AdjustmentAction],
        problems: [GateProblem],
        gate1Score: CGFloat = 0  // 🆕 샷타입 점수
    ) -> AdjustmentAction? {

        if actions.isEmpty {
            return nil
        }

        // 🆕 샷타입이 대충 맞았는지 판단 (70% 이상)
        let shotTypeOK = gate1Score >= 0.7

        // 🆕 여백 관련 동작들 (Gate 2 우선)
        let marginActions: Set<AdjustmentAction> = [.moveLeft, .moveRight, .tiltUp, .tiltDown]

        // 각 동작이 해결하는 문제 수 계산
        var actionScores: [(action: AdjustmentAction, score: Int, minGate: Int, isMargin: Bool)] = []

        for action in actions {
            var solvedCount = 0
            var minGateIndex = 5

            for problem in problems {
                if canSolveProblem(action: action, problem: problem) {
                    solvedCount += 1
                    minGateIndex = min(minGateIndex, problem.gateIndex)
                }
            }

            if solvedCount > 0 {
                let isMarginAction = marginActions.contains(action)
                actionScores.append((action, solvedCount, minGateIndex, isMarginAction))
            }
        }

        // 🆕 정렬 로직 개선
        actionScores.sort { (a, b) in
            // 샷타입이 OK면 여백 동작 우선
            if shotTypeOK {
                // 여백 동작 vs 거리 동작이면 여백 우선
                if a.isMargin != b.isMargin {
                    return a.isMargin  // 여백 동작이 앞으로
                }
            }

            // 해결 수 많은 순
            if a.score != b.score {
                return a.score > b.score
            }

            // Gate 번호 낮은 순
            return a.minGate < b.minGate
        }

        return actionScores.first?.action
    }

    private func canSolveProblem(action: AdjustmentAction, problem: GateProblem) -> Bool {
        switch (action, problem.problemType) {
        // 앞으로 이동
        case (.moveForward, .shotTypeTooWide),
             (.moveForward, .coverageTooLow),
             (.moveForward, .compressionTooLow):
            return true

        // 뒤로 이동
        case (.moveBackward, .shotTypeTooNarrow),
             (.moveBackward, .coverageTooHigh),
             (.moveBackward, .compressionTooHigh),
             (.moveBackward, .marginTopLow),
             (.moveBackward, .marginBottomLow):
            return true

        // 좌우 이동
        case (.moveRight, .marginLeftHigh),
             (.moveLeft, .marginRightHigh):
            return true

        // 🆕 틸트 - 여백 + 샷타입 동시 해결 가능
        case (.tiltUp, .marginBottomHigh),
             (.tiltUp, .marginTopLow),
             (.tiltUp, .shotTypeTooWide):  // 🆕 하단 여백 줄이면서 샷타입도 조정
            return true
        case (.tiltDown, .marginTopHigh),
             (.tiltDown, .marginBottomLow),
             (.tiltDown, .shotTypeTooWide):  // 🆕 상단 여백 줄이면서 샷타입도 조정
            return true

        // 줌
        case (.zoomIn, .shotTypeTooWide),
             (.zoomIn, .compressionTooLow),
             (.zoomOut, .shotTypeTooNarrow),
             (.zoomOut, .compressionTooHigh):
            return true

        default:
            return false
        }
    }

    // MARK: - 피드백 생성

    private func createUnifiedFeedback(
        action: AdjustmentAction,
        problems: [GateProblem],
        isFrontCamera: Bool
    ) -> UnifiedFeedback {

        // 크기 계산 (문제 심각도 기반)
        let maxSeverity = problems.map { $0.severity }.max() ?? 0.5
        let magnitude = calculateMagnitude(action: action, severity: maxSeverity)

        // 영향 받는 Gate 계산
        let affectedGates = problems
            .filter { canSolveProblem(action: action, problem: $0) }
            .map { $0.gateIndex }
            .sorted()

        // 예상 결과 생성
        var expectedResults: [String] = []
        for problem in problems {
            if canSolveProblem(action: action, problem: problem) {
                if let result = getExpectedResult(for: problem) {
                    expectedResults.append(result)
                }
            }
        }

        // 전면 카메라 방향 반전
        var finalAction = action
        if isFrontCamera && action.needsMirrorForFrontCamera {
            finalAction = mirrorAction(action)
        }

        return UnifiedFeedback(
            primaryAction: finalAction,
            magnitude: magnitude,
            affectedGates: affectedGates,
            expectedResults: expectedResults,
            priority: affectedGates.first ?? 5
        )
    }

    private func calculateMagnitude(action: AdjustmentAction, severity: CGFloat) -> String {
        switch action {
        case .moveForward, .moveBackward:
            if severity < 0.2 {
                return "반 걸음"
            } else if severity < 0.4 {
                return "한 걸음"
            } else if severity < 0.6 {
                return "두 걸음"
            } else {
                return "세 걸음"
            }

        case .moveLeft, .moveRight:
            let percent = Int(severity * 30)
            if severity < 0.3 {
                return "조금 (\(percent)%)"
            } else {
                return "한 걸음 (\(percent)%)"
            }

        case .tiltUp, .tiltDown:
            let angle = Int(severity * 15) + 2
            return "\(angle)°"

        case .zoomIn, .zoomOut:
            if severity < 0.3 {
                return "약간"
            } else {
                return "한 단계"
            }

        // 🆕 복합 동작 - 이미 magnitude가 설정되므로 기본값 반환
        case .zoomInThenMoveBack, .zoomInThenMoveForward,
             .zoomOutThenMoveBack, .zoomOutThenMoveForward:
            return ""  // 복합 동작은 별도 계산됨
        }
    }

    private func getExpectedResult(for problem: GateProblem) -> String? {
        switch problem.problemType {
        case .shotTypeTooWide:
            return "샷 타입이 좁아집니다"
        case .shotTypeTooNarrow:
            return "샷 타입이 넓어집니다"
        case .coverageTooLow:
            return "인물이 더 크게 보입니다"
        case .coverageTooHigh:
            return "인물이 더 작게 보입니다"
        case .marginLeftHigh:
            return "좌우 균형이 맞춰집니다"
        case .marginRightHigh:
            return "좌우 균형이 맞춰집니다"
        case .marginTopHigh:
            return "상단 여백이 줄어듭니다"
        case .marginBottomHigh:
            return "하단 여백이 줄어듭니다"
        case .marginTopLow:
            return "상단 잘림이 해결됩니다"
        case .marginBottomLow:
            return "하단 잘림이 해결됩니다"
        case .compressionTooLow:
            return "배경 압축이 자연스러워집니다"
        case .compressionTooHigh:
            return "배경 압축이 완화됩니다"
        case .poseAngleDiff:
            return nil  // 포즈는 동작으로 해결 불가
        }
    }

    private func mirrorAction(_ action: AdjustmentAction) -> AdjustmentAction {
        switch action {
        case .moveLeft: return .moveRight
        case .moveRight: return .moveLeft
        default: return action
        }
    }

    // MARK: - Fallback 피드백

    private func createFallbackFeedback(
        from evaluation: GateEvaluation,
        isFrontCamera: Bool
    ) -> UnifiedFeedback? {

        // 첫 번째 실패 Gate의 피드백 사용
        let feedback = evaluation.primaryFeedback

        if feedback.isEmpty || feedback.contains("완벽") {
            return nil
        }

        return UnifiedFeedback(
            primaryAction: .moveForward,  // 기본값
            magnitude: "",
            affectedGates: [evaluation.currentFailedGate ?? 1],
            expectedResults: [feedback],
            priority: evaluation.currentFailedGate ?? 1
        )
    }
}
