import Foundation
import CoreGraphics
import UIKit

public class CompressionGate: GateModule {
    public let name = "압축감"
    public let priority = 3
    
    // Config
    private let zoomTolerance: CGFloat = 0.1
    private let threshold: CGFloat = 0.70 // Base Threshold
    
    public init() {}
    
    public func evaluate(context: GateContext) -> GateResult {
        let analysis = context.analysis
        let reference = context.reference
        let currentKeypoints = analysis.poseResult?.asPoseKeypoints ?? []
        let referenceKeypoints = reference?.keypoints ?? [] // If nil, empty list
        
        let currentFocal = analysis.depthResult?.focalLengthInfo
        let referenceFocal = reference?.focalLength
        
        // Fallback: Check if currentFocal exists
        if let currentFL = currentFocal {
            return evaluateCompressionByFocalLength(
                current: currentFL,
                reference: referenceFocal,
                currentKeypoints: currentKeypoints,
                referenceKeypoints: referenceKeypoints
            )
        }
        
        // Fallback: No focal info -> Skip
        return GateResult(
            name: name,
            score: 0.0,
            threshold: threshold,
            feedback: "깊이 정보를 분석 중입니다...",
            icon: "🔭",
            category: "compression_missing"
        )
    }
    
    // MARK: - Logic
    
    private func evaluateCompressionByFocalLength(
        current: FocalLengthInfo,
        reference: FocalLengthInfo?,
        currentKeypoints: [PoseKeypoint],
        referenceKeypoints: [PoseKeypoint]
    ) -> GateResult {
        
        let currentMM = current.focalLength35mm
        let currentLens = current.lensType
        
        // 1. Check Reference
        guard let ref = reference else {
            return createSkippedCompressionResult(currentMM)
        }
        
        if ref.source == .fallback {
            return createSkippedCompressionResult(currentMM)
        }
        
        let refMM = ref.focalLength35mm
        
        // 2. Calculate Diff
        let diff = abs(currentMM - refMM)
        
        var score: CGFloat = 1.0
        var feedback = "\(currentMM)mm \(currentLens.displayName)으로 촬영 중"
        var isDistanceMismatch = false
        
        let isEstimated = ref.source == .depthEstimate || ref.confidence < 0.8
        let reliabilityIcon = isEstimated ? "🪄" : "📸"
        let diffThreshold: Int = isEstimated ? 30 : 15
        
        // 3. Compare Focal Length
        if diff > diffThreshold {
             // Score degrades as difference increases
             score = max(0, 1.0 - CGFloat(diff) / 50.0)
             let targetZoom = CGFloat(refMM) / CGFloat(24) // Assuming 24mm base for "1x"
             let zoomText = String(format: "%.1fx", targetZoom)
             
             // Distance Hint Logic (Body Span)
             var distanceHint = ""
             if let currStruct = BodyStructure.extract(from: currentKeypoints),
                let refStruct = BodyStructure.extract(from: referenceKeypoints),
                currStruct.lowestTier == refStruct.lowestTier {
                 
                 let scaleRatio = currStruct.spanY / max(0.01, refStruct.spanY)
                 
                 if currentMM < refMM {
                     // Need Zoom In -> Move Back to keep subject size
                     if scaleRatio > 1.3 { distanceHint = "많이 " }
                     else if scaleRatio < 0.85 { distanceHint = "조금만 " }
                 } else {
                     // Need Zoom Out -> Move Forward
                     if scaleRatio > 1.15 { distanceHint = "조금만 " }
                     else if scaleRatio < 0.7 { distanceHint = "많이 " }
                 }
             }
             
             if currentMM < refMM {
                 feedback = "📐 \(distanceHint)뒤로 물러나서 \(zoomText)로 줌인 (배경 압축)"
             } else {
                 feedback = "📐 \(distanceHint)앞으로 다가가서 \(zoomText)로 줌아웃 (원근감 강조)"
             }
             
             if isEstimated { feedback += " [AI 추정]" }
             
        } else {
            // 4. Focal Length Matched -> Check Physical Distance (Perspective)
            if let currStruct = BodyStructure.extract(from: currentKeypoints),
               let refStruct = BodyStructure.extract(from: referenceKeypoints) {
                
                if currStruct.lowestTier == refStruct.lowestTier {
                    let scaleRatio = currStruct.spanY / max(0.01, refStruct.spanY)
                    let scaleDiff = abs(1.0 - scaleRatio)
                    
                    if scaleDiff > 0.15 {
                        isDistanceMismatch = true
                        score = max(0.2, score - scaleDiff)
                        
                        let steps = max(1, Int(round(scaleDiff * 5)))
                        if scaleRatio > 1.0 {
                            feedback = "렌즈는 비슷하지만 너무 가깝습니다. 뒤로 \(steps)걸음 물러나세요"
                        } else {
                            feedback = "렌즈는 비슷하지만 너무 멉니다. 앞으로 \(steps)걸음 다가가세요"
                        }
                    }
                }
            }
            
            if !isDistanceMismatch {
                feedback = "✓ 압축감/거리 완벽함 (\(currentMM)mm)"
                if isEstimated { feedback += " \(reliabilityIcon)" }
            }
        }
        
        return GateResult(
            name: name,
            score: score,
            threshold: threshold,
            feedback: feedback,
            icon: "🔭",
            category: "compression",
            debugInfo: "Lens: \(currentMM)mm vs \(refMM)mm"
        )
    }
    
    private func createSkippedCompressionResult(_ currentMM: Int) -> GateResult {
        return GateResult(
            name: name,
            score: 1.0,
            threshold: threshold,
            feedback: "레퍼런스 렌즈 정보 없음 (현재: \(currentMM)mm)",
            icon: "🔭",
            category: "compression_skipped"
        )
    }
}
