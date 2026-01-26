import Foundation

// MARK: - Unified Feedback Types
// 통합 피드백에서 사용하는 타입들

/// 사용자 조정 동작
enum AdjustmentAction: String, CaseIterable {
    // 기본 동작
    case moveForward    // 앞으로
    case moveBackward   // 뒤로
    case moveLeft       // 왼쪽
    case moveRight      // 오른쪽
    case tiltUp         // 위로 기울이기
    case tiltDown       // 아래로 기울이기
    case zoomIn         // 줌 인
    case zoomOut        // 줌 아웃

    // 복합 동작
    case zoomInThenMoveBack     // 줌 인 후 뒤로
    case zoomInThenMoveForward  // 줌 인 후 앞으로
    case zoomOutThenMoveBack    // 줌 아웃 후 뒤로
    case zoomOutThenMoveForward // 줌 아웃 후 앞으로
}

/// 통합 피드백 (하나의 동작 → 여러 Gate 해결)
struct UnifiedFeedback {
    let primaryAction: AdjustmentAction    // 주요 조정 동작
    let mainMessage: String                 // 메인 메시지
    let affectedGates: [Int]               // 영향 받는 Gate 인덱스들
    let expectedResults: [String]          // 예상 결과 설명들
    let priority: Int                       // 우선순위 Gate 인덱스

    init(primaryAction: AdjustmentAction, mainMessage: String, affectedGates: [Int], expectedResults: [String], priority: Int? = nil) {
        self.primaryAction = primaryAction
        self.mainMessage = mainMessage
        self.affectedGates = affectedGates
        self.expectedResults = expectedResults
        self.priority = priority ?? affectedGates.first ?? 0
    }
}
