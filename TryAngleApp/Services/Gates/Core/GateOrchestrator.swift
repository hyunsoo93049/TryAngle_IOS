import Foundation

// MARK: - Gate Orchestrator

public class GateOrchestrator {
    private var gates: [GateModule] = []
    
    public init() {}
    
    public func register(gate: GateModule) {
        gates.append(gate)
        // 우선순위 정렬 (낮은 번호 먼저)
        gates.sort { $0.priority < $1.priority }
    }
    
    /// 모든 Gate 평가 수행
    public func evaluate(context: GateContext) -> GateEvaluation {
        var results: [GateResult] = []
        
        // Gate 0~4 결과 저장용 (인덱스 접근을 위해 미리 채움? 아니면 Dictionary?)
        // GateEvaluation 구조체가 gate0, gate1... 명시적 프로퍼티를 가지므로 매핑 필요.
        
        // 각 Gate 실행
        var gateResultsMap: [Int: GateResult] = [:]
        
        for gate in gates {
            let result = gate.evaluate(context: context)
            gateResultsMap[gate.priority] = result
        }
        
        // 기본값 (실행 안 된 경우 Fail 처리)
        let fallbackResult = GateResult(name: "Unknown", score: 0, threshold: 0, feedback: "Error", icon: "⚠️", category: "error")
        
        return GateEvaluation(
            gate0: gateResultsMap[0] ?? fallbackResult,
            gate1: gateResultsMap[1] ?? fallbackResult,
            gate2: gateResultsMap[2] ?? fallbackResult,
            gate3: gateResultsMap[3] ?? fallbackResult,
            gate4: gateResultsMap[4] ?? fallbackResult,
            currentShotType: nil, // TODO: Gate 1에서 반환된 정보로 채워야 함 (GateResult 확장 필요?)
            referenceShotType: context.reference?.shotType
        )
    }
}
