//
//  V15FeedbackGenerator.swift
//  v1.5 피드백 생성기 - Gate System 기반
//  작성일: 2025-12-05
//
// ============================================================================
// ⚠️ LEGACY CODE - 사용되지 않음 (2025-12-29)
// ============================================================================
// 원래 용도: 133개 키포인트 기반 상세 피드백 생성 (v1.5 버전)
// 사용되지 않는 이유: 너무 복잡하고 UI에서 v15Feedback 파라미터가 무시됨
// 대체된 파일: Services/OnDevice/SimpleRealTimeGuide.swift (6단계 순차 가이드)
// 삭제 가능 여부: 가능 (어디서도 호출되지 않음)
// ============================================================================

import Foundation
import CoreGraphics

// MARK: - v1.5 피드백 생성기
class V15FeedbackGenerator {

    static let shared = V15FeedbackGenerator()

    private init() {}

    // MARK: - Gate 평가 결과를 FeedbackItem으로 변환

    /// Gate System 평가 결과를 기존 FeedbackItem 형식으로 변환
    /// GateSystem 순서: gate0=비율, gate1=프레이밍, gate2=위치, gate3=압축감, gate4=포즈
    func generateFeedbackItems(from evaluation: GateEvaluation) -> [FeedbackItem] {
        var items: [FeedbackItem] = []

        // Gate 0: 비율 (최우선)
        if !evaluation.gate0.passed {
            items.append(FeedbackItem(
                priority: 0,
                icon: "📐",
                message: evaluation.gate0.feedback,
                category: "v15_aspect_ratio",
                currentValue: Double(evaluation.gate0.score),
                targetValue: Double(evaluation.gate0.threshold),
                tolerance: 0.1,
                unit: nil
            ))
        }

        // Gate 1: 프레이밍 (샷타입 + 점유율)
        if !evaluation.gate1.passed {
            items.append(FeedbackItem(
                priority: 1,
                icon: "📸",
                message: evaluation.gate1.feedback,
                category: "v15_framing",
                currentValue: Double(evaluation.gate1.score),
                targetValue: Double(evaluation.gate1.threshold),
                tolerance: 0.1,
                unit: nil
            ))
        }

        // Gate 2: 위치/구도
        if !evaluation.gate2.passed {
            items.append(FeedbackItem(
                priority: 2,
                icon: "↔️",
                message: evaluation.gate2.feedback,
                category: "v15_position",
                currentValue: Double(evaluation.gate2.score),
                targetValue: Double(evaluation.gate2.threshold),
                tolerance: 0.1,
                unit: nil
            ))
        }

        // Gate 3: 압축감
        if !evaluation.gate3.passed {
            items.append(FeedbackItem(
                priority: 3,
                icon: "🔭",
                message: evaluation.gate3.feedback,
                category: "v15_compression",
                currentValue: Double(evaluation.gate3.score),
                targetValue: Double(evaluation.gate3.threshold),
                tolerance: 0.1,
                unit: nil
            ))
        }

        // Gate 4: 포즈
        if !evaluation.gate4.passed {
            items.append(FeedbackItem(
                priority: 4,
                icon: "🤸",
                message: evaluation.gate4.feedback,
                category: "v15_pose",
                currentValue: Double(evaluation.gate4.score),
                targetValue: Double(evaluation.gate4.threshold),
                tolerance: 0.1,
                unit: nil
            ))
        }

        return items
    }

    // MARK: - 간단한 피드백 메시지 생성

    /// Gate 평가 결과에서 가장 중요한 피드백 하나만 반환
    func generatePrimaryFeedback(from evaluation: GateEvaluation) -> String {
        return evaluation.primaryFeedback
    }

    /// Gate 평가 결과에서 모든 피드백 반환
    func generateAllFeedbacks(from evaluation: GateEvaluation) -> [String] {
        return evaluation.allFeedbacks
    }

    // MARK: - 상태 메시지 생성

    /// 현재 상태를 요약하는 메시지
    func generateStatusMessage(from evaluation: GateEvaluation) -> String {
        let passedCount = evaluation.passedCount
        let totalCount = 5  // 🔧 v6: 5개 Gate (비율, 프레이밍, 위치, 압축감, 포즈)

        if evaluation.allPassed {
            return "완벽한 구도입니다!"
        } else if passedCount >= 4 {
            return "거의 다 됐어요! (\(passedCount)/\(totalCount))"
        } else if passedCount >= 3 {
            return "조금만 더 조정하세요 (\(passedCount)/\(totalCount))"
        } else {
            return "구도를 맞춰주세요 (\(passedCount)/\(totalCount))"
        }
    }

    // MARK: - 움직임 가이드 생성

    struct MovementGuide {
        let arrow: String
        let direction: String
        let amount: String
    }

    /// 여백 분석 결과에서 움직임 가이드 생성
    func generateMovementGuide(from margins: MarginAnalysisResult) -> MovementGuide? {
        guard let movement = margins.movementDirection else {
            return nil
        }

        return MovementGuide(
            arrow: movement.primaryArrow,
            direction: movement.description,
            amount: String(format: "%.0f%%", movement.amount * 100)
        )
    }

    // MARK: - 점수 기반 피드백

    /// 점수에 따른 격려 메시지
    func generateEncouragement(score: CGFloat) -> String {
        switch score {
        case 0.9...1.0:
            return "완벽해요!"
        case 0.8..<0.9:
            return "아주 좋아요!"
        case 0.7..<0.8:
            return "좋아요, 조금만 더!"
        case 0.5..<0.7:
            return "잘하고 있어요"
        default:
            return "조정이 필요해요"
        }
    }
}

// MARK: - FeedbackItem Extension for v1.5
extension FeedbackItem {
    /// v1.5 카테고리인지 확인
    var isV15Category: Bool {
        return category.hasPrefix("v15_")
    }
}
