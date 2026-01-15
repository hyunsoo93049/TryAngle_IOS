import Foundation
import UIKit
import Combine

// MARK: - Pipeline Integration

extension RealtimeAnalyzer {
    
    func setupPipeline() {
        print("🚀 Setting up Detection Pipeline...")
        
        let pose = RTMPoseService()
        let depth = DepthService()
        let seg = SAMService()
        let aesthetic = AestheticService()
        
        // Debug Logger
        PipelineLogger.shared.attach(to: pipeline)
        
        pipeline.register(pose: pose, depth: depth, segmentation: seg, composition: aesthetic)
        
        pipeline.resultPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                self?.handlePipelineResult(result)
            }
            .store(in: &pipelineCancellables)
    }
    
    private func handlePipelineResult(_ result: FrameAnalysisResult) {
        guard !isPaused else { return }
        
        // 1. Extract Metadata
        let brightness = result.input.metadata?["BrightnessValue"] as? Double
        // Brightness Check (Gate 0.5) logic copied from analyzeFrameInternal
        if let b = brightness, b < -2.0 {
            var newState = self.state
            newState.environmentWarning = "너무 어두워요 💡"
            newState.isPerfect = false
            newState.stabilityProgress = 0.0
            self.state = newState
            // Proceed anyway but with warning
        }
        
        guard let reference = referenceAnalysis else {
             // Reference check logic
             var newState = self.state
             newState.instantFeedback = []
             newState.perfectScore = 0.0
             newState.isPerfect = false
             self.state = newState
             return
        }
        
        // 2. Map Results to Legacy Types
        
        var faceResult: FaceAnalysisResult? = nil
        var poseResult: PoseAnalysisResult? = nil
        
        if let pose = result.poseResult {
            // Map PoseDetectionResult -> PoseAnalysisResult
            // PoseAnalysisResult expects keypoints with confidences
            let keypoints = zip(pose.keypoints, pose.confidences).map { (point: $0, confidence: $1) }
            
            poseResult = PoseAnalysisResult(
                keypoints: keypoints,
                boundingBox: pose.roughBBox // roughBBox is CGRect
            )
            
            // Simulate FaceResult from Pose if available
            // If pose has face keypoints (0..4), we can estimate face rect
            // Roughly index 0 is nose.
            if let nose = pose.keypoints.first {
                // Dummy Face Rect around nose?
                // Or simply use the whole pose bbox as fallback check?
                // Legacy code used `faceResult?.faceRect` for composition.
                // We'll create a dummy FaceAnalysisResult just to pass the checks in processAnalysisResult
                let dummyRect = CGRect(x: nose.x - 0.1, y: nose.y - 0.1, width: 0.2, height: 0.2)
                faceResult = FaceAnalysisResult(
                    faceRect: dummyRect,
                    yaw: 0,
                    pitch: 0,
                    roll: 0
                )
            }
        }
        
        guard let cgImage = result.input.image.cgImage else { return }
        
        // 3. Call Legacy Processor
        self.processAnalysisResult(
            faceResult: faceResult,
            poseResult: poseResult,
            cgImage: cgImage,
            reference: reference, // Passed safely
            isFrontCamera: result.input.cameraPosition == .front,
            currentAspectRatio: CameraAspectRatio.detect(from: result.input.image.size)
        )
    }
}
