import Foundation
import CoreGraphics
import UIKit

public class PoseGate: GateModule {
    public let name = "포즈"
    public let priority = 4
    
    // Config
    private let poseAngleThreshold: Float = 15.0 // Tolerance
    private let threshold: CGFloat = 0.80      // Pass score
    
    public init() {}
    
    public func evaluate(context: GateContext) -> GateResult {
        let analysis = context.analysis
        
        // 🆕 Check if person exists in current frame
        // Using "hasCurrentPerson" logic from GateSystem:
        // GateSystem passed this explicitly. Here we derive it from poseResult.
        let hasCurrentPerson: Bool
        if let kp = analysis.poseResult?.asPoseKeypoints, !kp.isEmpty {
            hasCurrentPerson = true
        } else if let bbox = analysis.poseResult?.roughBBox, bbox != .zero {
            hasCurrentPerson = true
        } else {
            hasCurrentPerson = false
        }
        
        // 1. Missing Person Check
        guard hasCurrentPerson else {
            return GateResult(
                name: name,
                score: 0.0,
                threshold: threshold,
                feedback: "인물이 검출되지 않습니다. 프레임 안에 들어오세요",
                icon: "🤸",
                category: "pose_missing"
            )
        }
        
        // 2. Check Comparison Result
        // analysis.poseComparison is of type PoseComparisonResult?
        // Note: We need to import the definition of PoseComparisonResult or it must be public.
        // It's in AdaptivePoseComparator.swift (internal by default?).
        // If internal, it works within the app target. Assuming yes.
        
        guard let pose = analysis.poseComparison else {
            return GateResult(
                name: name,
                score: 0.0,
                threshold: threshold,
                feedback: "포즈를 분석 중입니다...",
                icon: "🤸",
                category: "pose_analyzing"
            )
        }
        
        // 3. Evaluate Score
        let score = CGFloat(pose.overallAccuracy)
        
        // 4. Generate Feedback
        // Logic extracted from GateSystem.evaluatePose
        let angleDiffThreshold: Float = poseAngleThreshold
        var feedbackParts: [String] = []
        
        // Priority parts to check
        let priorityParts = ["shoulder_tilt", "face", "left_arm", "right_arm", "left_leg", "right_leg", "left_hand", "right_hand"]
        
        for part in priorityParts {
            if let diff = pose.angleDifferences[part], abs(diff) > angleDiffThreshold {
                // Get direction message from comparison result
                if let direction = pose.angleDirections[part] {
                    feedbackParts.append(direction)
                } else {
                    // Fallback messages
                    switch part {
                    case "shoulder_tilt": feedbackParts.append("몸 기울기 조정")
                    case "face":          feedbackParts.append("고개 방향 조정")
                    case "left_arm":      feedbackParts.append("왼팔 각도 조정")
                    case "right_arm":     feedbackParts.append("오른팔 각도 조정")
                    case "left_leg":      feedbackParts.append("왼다리 각도 조정")
                    case "right_leg":     feedbackParts.append("오른다리 각도 조정")
                    case "left_hand":     feedbackParts.append("왼손 모양 조정")
                    case "right_hand":    feedbackParts.append("오른손 모양 조정")
                    default: break
                    }
                }
                
                // Limit feedback items to 2 to avoid clutter
                if feedbackParts.count >= 2 { break }
            }
        }
        
        let feedback = feedbackParts.isEmpty ? "포즈 일치" : feedbackParts.joined(separator: ", ")
        
        // 5. Return Result
        return GateResult(
            name: name,
            score: score,
            threshold: threshold,
            feedback: feedback,
            icon: "🤸",
            category: "pose",
            debugInfo: "Acc: \(Int(score * 100))%"
        )
    }
}
