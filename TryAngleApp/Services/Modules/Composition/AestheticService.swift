import Foundation
import UIKit

// MARK: - Aesthetic (Composition) Service

public class AestheticService: CompositionAnalyzer {
    public let name = "Composition/Aesthetic"
    public var isEnabled: Bool = true
    
    // Existing logic wrapper
    // We can reuse `CompositionAnalyzer` class if it's stateless or thread-safe, or port logic here.
    // For now, we'll wrap the existing one if possible, or implement basic logic.
    // Since `CompositionAnalyzer.swift` is simple (looked at RealtimeAnalyzer reference), we can instantiate it.
    
    private let legacyAnalyzer = RuleCompositionAnalyzer()
    
    public init() {}
    
    public func initialize() async throws {
        print("✅ AestheticService initialized")
    }
    
    public func analyze(input: FrameInput, pose: PoseDetectionResult?, depth: DepthEstimationResult?) async throws -> CompositionResult? {
        guard isEnabled else { return nil }
        
        // Re-use legacy logic
        // The legacy `CompositionAnalyzer` takes `subjectPosition` (CGPoint).
        
        var feedback: [String] = []
        var score: Float = 0.5
        
        if let pose = pose, let firstIndex = pose.keypoints.first {
             // Use nose or center of roughBBox as subject position
             // pose.roughBBox is CGRect
             
             let bbox = pose.roughBBox
             // Normalized center
             let center = CGPoint(x: bbox.midX, y: bbox.midY)
             
             // Legacy needs absolute coordinates? 
             // CompositionAnalyzer typically works on normalized or absolute depending on implementation.
             // Let's assume normalized for now or check file if needed. 
             // RealtimeAnalyzer passed: subjectPosition = CGPoint(x: faceRect.midX, y: faceRect.midY) which was normalized.
             
             // classifyComposition returns non-optional CompositionType
             let compositionType = legacyAnalyzer.classifyComposition(subjectPosition: center)
             feedback.append("Detected Composition: \(compositionType.description)")
             score = 0.8 // Dummy score
        }
        
        // Add Depth feedback if available
        if let depth = depth {
             if depth.compressionIndex > 0.7 {
                 feedback.append("High Compression (Telephoto feel)")
             }
        }
        
        return CompositionResult(
            timestamp: input.timestamp,
            feedback: feedback,
            score: score
        )
    }
}
