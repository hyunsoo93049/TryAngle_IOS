import Foundation
import CoreGraphics

// MARK: - Guide Engine
// 단순화된 실시간 가이드 로직 (구 SimpleRealTimeGuide 대체)
public class GuideEngine {
    
    // Config
    private let zoomTolerance: CGFloat = 0.1
    
    public init() {}
    
    /// GateEvaluation 결과를 바탕으로 사용자 가이드 생성
    public func process(evaluation: GateEvaluation) -> SimpleGuideResult {
        // 1. 프레임 진입 체크 (Gate 1 No Person or Gate 4 No Person)
        // Gate 1 Fail AND category == "no_person" or similar
        // GateOrchestrator generates "no_person" feedback if missing.
        // Let's check Gate 1 (Framing) and Gate 4 (Pose)
        
        // If Gate 1 explicitly says "no_person" in category/feedback, prioritize it.
        if evaluation.gate1.category == "no_person" || evaluation.gate4.category == "pose_missing" {
             return createGuideResult(
                guide: .enterFrame,
                magnitude: "",
                stage: .frameEntry,
                debug: "인물 미검출",
                evaluation: evaluation
            )
        }
        
        // 2. 샷타입(크기) 체크 (Gate 1 Framing)
        // Gate 1이 실패하면 크기/거리 문제
        if !evaluation.gate1.passed {
            let feedback = evaluation.gate1.feedback
            
            // 피드백 텍스트 분석하여 가이드 도출 (임시: GateResult가 더 명확한 Action을 주면 좋겠지만, 지금은 텍스트/categoy 의존)
            // Gate 1 Category: "framing"
            // Feedback usually: "Full Shot을 위해 한 걸음 뒤로 물러나세요"
            
            if feedback.contains("뒤로") || feedback.contains("멀리") {
                return createGuideResult(
                    guide: .moveBackward,
                    magnitude: extractMagnitude(from: feedback),
                    stage: .shotType,
                    debug: "거리 조절 (뒤로)",
                    evaluation: evaluation
                )
            } else if feedback.contains("앞으로") || feedback.contains("가까이") {
                 return createGuideResult(
                    guide: .moveForward,
                    magnitude: extractMagnitude(from: feedback),
                    stage: .shotType,
                    debug: "거리 조절 (앞으로)",
                    evaluation: evaluation
                )
            }
        }
        
        // 3. 줌 체크 (Gate 3 Compression) - 줌은 실시간 가이드에서 거리보다 후순위지만 중요
        // v9 기획: 줌은 사용자가 바꾸기 어려우므로 거리 조절과 병행 안내하거나, 줌 불일치 시 안내.
        // Gate 3 Fail
        if !evaluation.gate3.passed {
            let feedback = evaluation.gate3.feedback
            if feedback.contains("줌인") {
                return createGuideResult(
                    guide: .zoomIn,
                    magnitude: "",
                    stage: .zoom,
                    debug: "줌 인 필요",
                    evaluation: evaluation
                )
            } else if feedback.contains("줌아웃") {
                return createGuideResult(
                    guide: .zoomOut,
                    magnitude: "",
                    stage: .zoom,
                    debug: "줌 아웃 필요",
                    evaluation: evaluation
                )
            }
        }
        
        // 4. 위치/구도 체크 (Gate 2 Position)
        if !evaluation.gate2.passed {
            let feedback = evaluation.gate2.feedback
            
            if feedback.contains("왼쪽") {
                 return createGuideResult(
                    guide: .moveLeft,
                    magnitude: extractMagnitude(from: feedback),
                    stage: .position,
                    debug: "위치 이동 (왼쪽)",
                    evaluation: evaluation
                )
            } else if feedback.contains("오른쪽") {
                 return createGuideResult(
                    guide: .moveRight,
                    magnitude: extractMagnitude(from: feedback),
                    stage: .position,
                    debug: "위치 이동 (오른쪽)",
                    evaluation: evaluation
                )
            } else if feedback.contains("위로") || feedback.contains("아래로") {
                 // 틸트 or 이동
                 if feedback.contains("틸트") {
                     return createGuideResult(
                        guide: feedback.contains("위로") ? .tiltUp : .tiltDown,
                        magnitude: extractMagnitude(from: feedback),
                        stage: .position,
                        debug: "앵글 틸트",
                        evaluation: evaluation
                    )
                 } else {
                     // 상하 이동 (몸을 굽히거나 펴기)
                     return createGuideResult(
                        guide: feedback.contains("위로") ? .tiltUp : .tiltDown, // Icon reuse
                        magnitude: extractMagnitude(from: feedback),
                        stage: .position,
                        debug: "상하 위치",
                        evaluation: evaluation
                    )
                 }
            }
        }
        
        // 5. 포즈 체크 (Gate 4 Pose)
        if !evaluation.gate4.passed {
             return createGuideResult(
                guide: .adjustPose,
                magnitude: evaluation.gate4.feedback, // 포즈는 구체적 피드백 그대로 사용
                stage: .pose,
                debug: "포즈 불일치",
                evaluation: evaluation
            )
        }
        
        // 6. Perfect
        return createGuideResult(
            guide: .perfect,
            magnitude: "셔터를 누르세요!",
            stage: .perfect,
            debug: "모든 조건 충족",
            evaluation: evaluation
        )
    }
    
    // MARK: - Helpers
    
    private func createGuideResult(
        guide: GuideType,
        magnitude: String,
        stage: FeedbackStage,
        debug: String,
        evaluation: GateEvaluation
    ) -> SimpleGuideResult {
        
        // Calculate total progress score (average of gates)
        let totalScore = (evaluation.gate1.score + evaluation.gate2.score + evaluation.gate3.score + evaluation.gate4.score) / 4.0
        
        // Extract Shot Types
        let currentType = evaluation.currentShotType?.displayName ?? "미감지"
        let targetType = evaluation.referenceShotType?.displayName ?? "미설정"
        let shotMatch = evaluation.currentShotType == evaluation.referenceShotType
        
        return SimpleGuideResult(
            guide: guide,
            magnitude: magnitude,
            progress: totalScore,
            debugInfo: debug,
            shotTypeMatch: shotMatch,
            currentShotType: currentType,
            targetShotType: targetType,
            feedbackStage: stage
        )
    }
    
    private func extractMagnitude(from text: String) -> String {
        if text.contains("반 걸음") { return "반 걸음" }
        if text.contains("한 걸음") { return "한 걸음" }
        if text.contains("두 걸음") { return "두 걸음" }
        if text.contains("조금") { return "조금" }
        if text.contains("많이") { return "많이" }
        return ""
    }
}
