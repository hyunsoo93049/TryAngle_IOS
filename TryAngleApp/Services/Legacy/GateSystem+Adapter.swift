import Foundation
import CoreGraphics
import UIKit
import AVFoundation

// MARK: - GateSystem Adapter for DetectionPipeline

extension GateSystem {

    /// 새로운 파이프라인 결과(FrameAnalysisResult)를 받아 평가를 수행합니다.
    /// 새로운 evaluate() 메서드를 호출하는 어댑터 역할을 합니다.
    func evaluate(result: FrameAnalysisResult,
                  referenceBBox: CGRect?,
                  referenceImageSize: CGSize?,
                  currentImageSize: CGSize? = nil,
                  referenceAnalysis: FrameAnalysis? = nil
    ) -> GateEvaluation {

        // 1. Unpack FrameAnalysisResult
        let pose = result.poseResult

        // 2. Prepare Arguments for new evaluate()

        // BBox: Prefer Pose RoughBBox, fallback to zero
        let currentBBox = pose?.roughBBox ?? CGRect.zero

        // Image Size: Use input image size (with safe unwrap)
        let imageSize = currentImageSize ?? result.input.imageSize

        // Keypoints conversion for GateSystem (PoseKeypoint)
        var currentKeypoints: [PoseKeypoint]? = nil
        if let pose = pose {
            currentKeypoints = zip(pose.keypoints, pose.confidences).map { point, conf in
                PoseKeypoint(location: point, confidence: conf)
            }
        }

        // Reference Keypoints
        let referenceKeypoints = referenceAnalysis?.poseKeypoints?.map { PoseKeypoint(location: $0.point, confidence: $0.confidence) }

        // 3. Call new evaluate()
        return self.evaluate(
            bbox: currentBBox,
            imageSize: imageSize,
            referenceBBox: referenceBBox,
            referenceImageSize: referenceImageSize,
            isFrontCamera: result.input.cameraPosition == .front,
            currentKeypoints: currentKeypoints,
            referenceKeypoints: referenceKeypoints,
            poseComparison: nil,
            focalLengthInfo: nil,
            referenceFocalLengthInfo: nil
        )
    }
}
