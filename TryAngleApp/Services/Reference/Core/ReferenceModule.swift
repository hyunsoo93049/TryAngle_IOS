import Foundation
import UIKit

// MARK: - Reference Module Protocol
// 역할: 레퍼런스 분석 모듈이 따라야 할 규칙(프로토콜)을 정의합니다.
//       새 모듈을 만들 때 이 프로토콜만 구현하면 자동으로 시스템에 통합됩니다.

/// 레퍼런스 분석 모듈 프로토콜
protocol ReferenceAnalysisModule {
    /// 모듈 이름 (디버깅 및 로깅용)
    var name: String { get }

    /// 실행 우선순위 (낮을수록 먼저 실행, 0이 가장 먼저)
    var priority: Int { get }

    /// 분석 수행
    /// - Parameters:
    ///   - input: 레퍼런스 이미지 입력 데이터
    ///   - context: 이전 모듈들의 분석 결과 (의존성 있는 모듈에서 사용)
    /// - Returns: 모듈별 분석 결과
    func analyze(input: ReferenceInput, context: inout ReferenceContext) async throws
}

// MARK: - Default Implementation

extension ReferenceAnalysisModule {
    /// 기본 우선순위 (중간)
    var priority: Int { 50 }
}
