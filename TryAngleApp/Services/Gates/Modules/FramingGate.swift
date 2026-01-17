import Foundation
import CoreGraphics
import UIKit

public class FramingGate: GateModule {
    public let name = "프레이밍"
    public let priority = 1
    
    // 🆕 샷타입 안정화 (Hysteresis)
    private var stableShotType: ShotTypeGate?
    private var shotTypeChangeCount: Int = 0
    private let shotTypeStabilityThreshold: Int = 3
    
    // 🆕 이전 분석 결과 저장 (정밀 평가용)
    public private(set) var currentShotType: ShotTypeGate?
    
    public init() {}
    
    public func evaluate(context: GateContext) -> GateResult {
        // 1. 필요한 데이터 추출
        let analysis = context.analysis
        let bbox = analysis.poseResult?.roughBBox ?? .zero // YOLOX Result usually gives roughBBox or use Pose BBox
        let imageSize = analysis.input.imageSize
        let currentKeypoints = analysis.poseResult?.asPoseKeypoints
        let reference = context.reference
        
        // 🆕 v9.3: 인물 감지 실패 체크 (Empty Air Problem)
        let hasSufficientKeypoints = (currentKeypoints?.count ?? 0) >= 5
        let hasMeaningfulBBox = bbox.width * bbox.height > 0.01
        
        if !hasSufficientKeypoints && !hasMeaningfulBBox {
            return GateResult(
                name: name,
                score: 0.0,
                threshold: 0.75,
                feedback: "피사체를 인식할 수 없습니다. 화면 중앙에 인물을 비춰주세요.",
                icon: "🕵️",
                category: "framing",
                debugInfo: "No Subject Detected"
            )
        }
        
        // 2. 샷 타입 감지 (키포인트 우선, 없으면 BBox Fallback)
        let rawShotType: ShotTypeGate
        if let kps = currentKeypoints, kps.count >= 17 {
            rawShotType = ShotTypeGate.fromKeypoints(kps)
        } else {
            rawShotType = ShotTypeGate.fromBBoxHeight(bbox.height) // bbox is normalized?
            // Assuming bbox is normalized (0~1). GateSystem logic used bbox.height directly as ratio.
        }
        
        // 3. 안정화 (Hysteresis)
        let detectedShotType: ShotTypeGate
        if rawShotType == stableShotType {
            shotTypeChangeCount = 0
            detectedShotType = rawShotType
        } else {
            shotTypeChangeCount += 1
            if shotTypeChangeCount >= shotTypeStabilityThreshold {
                stableShotType = rawShotType
                shotTypeChangeCount = 0
                detectedShotType = rawShotType
            } else {
                detectedShotType = stableShotType ?? rawShotType
            }
        }
        
        // 저장 (외부 접근용)
        self.currentShotType = detectedShotType
        
        // 4. 레퍼런스 비교
        guard let ref = reference else {
            // 레퍼런스 없으면 적절하다고 판단
            return GateResult(
                name: name,
                score: 1.0,
                threshold: 0.0,
                feedback: "인물 크기가 적절합니다",
                icon: "📸",
                category: "framing",
                debugInfo: "No Reference, ShotType: \(detectedShotType.displayName)"
            )
        }
        
        // 레퍼런스 샷타입 (이미 ReferenceData에 있음)
        // 만약 ReferenceData에 없다면 fallback 계산 필요하지만, ReferenceData 생성 시 계산됨.
        let refShotType = ref.shotType ?? .mediumShot
        
        // 5. 프레임 가장자리 체크 (Edge Cropping)
        let edgeThreshold: CGFloat = 0.02
        let isAtTop = bbox.minY < edgeThreshold
        let isAtBottom = bbox.maxY > (1.0 - edgeThreshold)
        let isAtLeft = bbox.minX < edgeThreshold
        let isAtRight = bbox.maxX > (1.0 - edgeThreshold)
        let edgeCount = [isAtTop, isAtBottom, isAtLeft, isAtRight].filter { $0 }.count
        // let isTooClose = edgeCount >= 2 // Not used for direct failure unless zoomed in too much?
        
        // 6. 평가 및 피드백 생성
        var score: CGFloat = 1.0
        var feedback = "인물 크기가 프레임 대비 적절합니다"
        
        // 크기 비율 비교
        let currentHeight = bbox.height
        let refHeight = ref.bbox?.height ?? 0.5 // Fallback
        let sizeRatio = refHeight / max(currentHeight, 0.01)
        
        // 허용 오차 (30%)
        let sizeDiffThreshold: CGFloat = 1.3
        
        // 샷타입 일치 여부
        if detectedShotType == refShotType {
            // 샷타입 같아도 크기가 많이 다르면 피드백
            if sizeRatio > sizeDiffThreshold {
                // 목표가 더 큼 -> 다가가야 함
                score = 0.6
                let stepText = sizeRatio > 1.5 ? "한 걸음" : "반 걸음"
                let actionText = "앞으로 다가가세요" // Front camera? Needs camera settings?
                feedback = "\(refShotType.displayName)을 위해 \(stepText) \(actionText)"
            } else if sizeRatio < (1.0 / sizeDiffThreshold) {
                // 목표가 더 작음 -> 물러나야 함
                score = 0.6
                let stepText = sizeRatio < 0.6 ? "한 걸음" : "반 걸음"
                let actionText = "뒤로 물러나세요"
                feedback = "\(refShotType.displayName)을 위해 \(stepText) \(actionText)"
            } else {
                // Good
                score = 1.0
                feedback = "완벽한 \(refShotType.displayName)입니다!"
            }
        } else {
            // 샷타입 다름 -> 이동 지시
            // ShotTypeGaterawValue가 작을수록 CloudUp(가까움), 클수록 FullShot(멂)
            let diff = detectedShotType.rawValue - refShotType.rawValue
            score = max(0.0, 1.0 - CGFloat(abs(diff)) * 0.2) // 차이만큼 감점
            
            if diff < 0 {
                // 현재가 더 가까움 (RawValue 작음) -> 뒤로
                feedback = "\(refShotType.displayName)을 위해 뒤로 물러나세요"
            } else {
                // 현재가 더 멂 (RawValue 큼) -> 앞으로
                feedback = "\(refShotType.displayName)을 위해 앞으로 다가가세요"
            }
        }
        
        // 가장자리 경고 (보조 피드백)
        if score < 0.9 && edgeCount >= 2 {
             feedback += " (너무 가까워요)"
        }
        
        // 🆕 GateResult에 메타데이터 포함 (Orchestrator나 Debugger가 쓸 수 있게)
        // GateResult는 struct이므로 확장은 못하고 debugInfo에 녹임.
        // 하지만 나중에 GateEvaluation.currentShotType 채울 때 필요함.
        // GateOrchestrator가 FramingGate 인스턴스를 직접 접근해서 currentShotType을 읽을 수 있음 (Type casting or specific interface).
        
        return GateResult(
            name: name,
            score: score,
            threshold: 0.75,
            feedback: feedback,
            icon: "📸",
            category: "framing",
            debugInfo: "현재: \(detectedShotType.displayName) vs 목표: \(refShotType.displayName)",
            metadata: ["shotType": detectedShotType]
        )
    }
}
