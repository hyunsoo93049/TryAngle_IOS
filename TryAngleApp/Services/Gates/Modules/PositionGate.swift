import Foundation
import CoreGraphics
import UIKit

public class PositionGate: GateModule {
    public let name = "위치"
    public let priority = 2
    
    // 🆕 v6: Margin Analyzer Logic (Simplified implementation of Python logic)
    private struct MarginAnalysisResult {
        let leftRatio: CGFloat
        let rightRatio: CGFloat
        let topRatio: CGFloat
        let bottomRatio: CGFloat
        let outOfFrameWarning: String?
    }

    
    public init() {}
    
    public func evaluate(context: GateContext) -> GateResult {
        let analysis = context.analysis
        let bbox = analysis.poseResult?.roughBBox ?? .zero
        let imageSize = analysis.input.imageSize
        let currentKeypoints = analysis.poseResult?.asPoseKeypoints
        let reference = context.reference
        
        let isFrontCamera = false // TODO: Pass this in Context? context.isFrontCamera
        // Note: For now assuming back camera or handled by caller logic reversing instructions if needed.
        // Actually FrameInput metadata might have it, or GateContext.
        
        // 1. Try Keypoint Alignment (Superior v8 Logic)
        if let currentKP = currentKeypoints, let refKP = reference?.keypoints,
           let kpResult = evaluateKeypointAlignment(current: currentKP, reference: refKP, isFrontCamera: isFrontCamera) {
            return kpResult
        }
        
        // 2. Fallback to BBox/Margin Analysis
        return evaluatedFallback(bbox: bbox, imageSize: imageSize, referenceBBox: reference?.bbox, referenceImageSize: nil, isFrontCamera: isFrontCamera)
    }
    
    // MARK: - Keypoint Logic
    private func evaluateKeypointAlignment(current: [PoseKeypoint], reference: [PoseKeypoint], isFrontCamera: Bool) -> GateResult? {
        guard let currStruct = BodyStructure.extract(from: current),
              let refStruct = BodyStructure.extract(from: reference) else {
            return nil
        }
        
        var score: CGFloat = 1.0
        var feedbackParts: [String] = []
        
        // Horizontal Alignment
        let diffX = currStruct.centroid.x - refStruct.centroid.x
        let thresholdX: CGFloat = 0.05
        
        // Helper toSteps
        func toSteps(percent: CGFloat) -> Int {
            return max(1, Int(round(percent * 10)))
        }
        
        if abs(diffX) > thresholdX {
            let percent = Int(abs(diffX) * 100)
            let steps = toSteps(percent: CGFloat(percent))
            
            if diffX > 0 {
                // Live Right -> Move Left
                 if isFrontCamera {
                     feedbackParts.append("왼쪽으로 \(steps) 이동")
                } else {
                     feedbackParts.append("카메라를 오른쪽으로 이동")
                }
            } else {
                 if isFrontCamera {
                     feedbackParts.append("오른쪽으로 \(steps) 이동")
                } else {
                     feedbackParts.append("카메라를 왼쪽으로 이동")
                }
            }
            score -= abs(diffX) * 2.0
        }
        
        // Vertical Tilt (Top Anchor) - Only if Tiers match
        if currStruct.lowestTier == refStruct.lowestTier {
             let diffY = currStruct.topAnchorY - refStruct.topAnchorY
             if abs(diffY) > 0.05 {
                  func toTiltAngle(percent: CGFloat) -> Int {
                      if percent < 5 { return 2 }
                      else if percent < 10 { return 5 }
                      else { return 10 }
                  }
                  
                  let angle = toTiltAngle(percent: abs(diffY) * 100)
                  score -= abs(diffY) * 2.0
                  
                  if diffY > 0 {
                      feedbackParts.append("카메라를 \(angle)° 아래로 틸트")
                  } else {
                      feedbackParts.append("카메라를 \(angle)° 위로 틸트")
                  }
             }
        }
        
        if feedbackParts.isEmpty {
            return GateResult(
                name: name,
                score: 1.0,
                threshold: 0.75,
                feedback: "✓ 위치/크기 완벽함",
                icon: "✨",
                category: "position_perfect"
            )
        }
        
        return GateResult(
            name: name,
            score: max(0.1, score),
            threshold: 0.75,
            feedback: feedbackParts.joined(separator: "\n"),
            icon: "↔️",
            category: "position_keypoint"
        )
    }
    
    // MARK: - Fallback Logic (ROI/BBox)
    private func evaluatedFallback(bbox: CGRect, imageSize: CGSize, referenceBBox: CGRect?, referenceImageSize: CGSize?, isFrontCamera: Bool) -> GateResult {
        // Simple Center logic
        let centerX = bbox.midX
        let centerY = bbox.midY
        let targetX: CGFloat = 0.5
        let targetY: CGFloat = 0.5
        
        var score: CGFloat = 1.0
        var feedbackParts: [String] = []
        
        if abs(centerX - targetX) > 0.1 {
            score -= abs(centerX - targetX)
            if centerX < targetX {
                feedbackParts.append("오른쪽으로 이동")
            } else {
                feedbackParts.append("왼쪽으로 이동")
            }
        }
        
        if abs(centerY - targetY) > 0.1 {
            score -= abs(centerY - targetY)
            if centerY < targetY {
                feedbackParts.append("아래로 이동")
            } else {
                feedbackParts.append("위로 이동")
            }
        }
        
        let feedback = feedbackParts.isEmpty ? "위치 양호" : feedbackParts.joined(separator: ", ")
        
        return GateResult(
            name: name,
            score: score,
            threshold: 0.70,
            feedback: feedback,
            icon: "↔️",
            category: "position_fallback"
        )
    }
}
