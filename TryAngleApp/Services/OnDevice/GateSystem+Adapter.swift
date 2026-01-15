import Foundation
import CoreGraphics
import UIKit

// MARK: - GateSystem Adapter for DetectionPipeline

extension GateSystem {
    
    /// 새로운 파이프라인 결과(FrameAnalysisResult)를 받아 평가를 수행합니다.
    /// 기존 evaluate() 메서드를 호출하는 어댑터 역할을 합니다.
    func evaluate(result: FrameAnalysisResult, 
                  referenceBBox: CGRect?, 
                  referenceImageSize: CGSize?,
                  currentImageSize: CGSize? = nil, // Optional: if nil, use FrameInput metadata or default
                  referenceAnalysis: FrameAnalysis? = nil // Legacy reference data if needed
    ) -> GateEvaluation {
        
        // 1. Unpack FrameAnalysisResult
        let pose = result.poseResult
        let depth = result.depthResult
        
        // 2. Prepare Arguments for Legacy evaluate()
        
        // BBox: Prefer Pose RoughBBox, fallback to zero
        let currentBBox = pose?.roughBBox ?? CGRect.zero
        
        // Image Size: Use input image size
        let imageSize = currentImageSize ?? result.input.image.size
        
        // Compression Index
        let compressionIndex = depth?.compressionIndex.map { CGFloat($0) }
        
        // Aspect Ratio
        let currentAspectRatio = CameraAspectRatio.detect(from: imageSize)
        // Reference Aspect Ratio (If ref size exists)
        let referenceAspectRatio = referenceImageSize != nil ? CameraAspectRatio.detect(from: referenceImageSize!) : .ratio4_3
        
        // Keypoints conversion for Legacy GateSystem (PoseKeypoint)
        // PoseDetectionResult uses [CGPoint]
        var currentKeypoints: [PoseKeypoint]? = nil
        if let pose = pose {
            currentKeypoints = zip(pose.keypoints, pose.confidences).map { point, conf in
                PoseKeypoint(location: point, confidence: conf)
            }
        }
        
        // Reference Keypoints (From legacy reference wrapper if exists)
        // This part relies on how Reference is managed. Ideally Ref should also be FrameAnalysisResult.
        // For now, we assume nil or use the legacy object passed in.
        let referenceKeypoints = referenceAnalysis?.poseKeypoints?.map { PoseKeypoint(location: $0.point, confidence: $0.confidence) }
        
        // 3. Call Legacy evaluate()
        // We use the existing shared instance logic
        return self.evaluate(
            currentBBox: currentBBox,
            referenceBBox: referenceBBox,
            currentImageSize: imageSize,
            referenceImageSize: referenceImageSize,
            compressionIndex: compressionIndex,
            referenceCompressionIndex: nil, // TODO: Pass this if available
            currentAspectRatio: currentAspectRatio,
            referenceAspectRatio: referenceAspectRatio,
            poseComparison: nil, // TODO: Add Pose Comparison Logic if needed
            isFrontCamera: result.input.cameraPosition == .front,
            currentKeypoints: currentKeypoints,
            referenceKeypoints: referenceKeypoints,
            currentFocalLength: nil, // TODO: Add Lens info
            referenceFocalLength: nil
        )
    }
}
