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
        
        // 샷타입 추출 (Gate 1 - FramingGate 결과에서)
        var detectedShotType: ShotTypeGate?
        if let gate1Result = gateResultsMap[1],
           let meta = gate1Result.metadata,
           let type = meta["shotType"] as? ShotTypeGate {
            detectedShotType = type
        }
        
        return GateEvaluation(
            gate0: gateResultsMap[0] ?? fallbackResult,
            gate1: gateResultsMap[1] ?? fallbackResult,
            gate2: gateResultsMap[2] ?? fallbackResult,
            gate3: gateResultsMap[3] ?? fallbackResult,
            gate4: gateResultsMap[4] ?? fallbackResult,
            currentShotType: detectedShotType,
            referenceShotType: context.reference?.shotType
        )
    }
}
