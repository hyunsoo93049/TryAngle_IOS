import Foundation
import CoreGraphics
import UIKit

// MARK: - Gate Helpers
// Gate 모듈들에서 공통으로 사용하는 유틸리티

// BodyStructure (기존 GateSystem 내부 Struct)
// 공용으로 사용하기 위해 이동
public struct BodyStructure {
    public let centroid: CGPoint
    public let topAnchorY: CGFloat
    public let spanY: CGFloat
    public let lowestTier: Int // 0:Shoulder, 1:Hip, 2:Knee, 3:Ankle

    public static func extract(from keypoints: [PoseKeypoint]) -> BodyStructure? {
        // Helper: Safe Keypoint Access
        func getPoint(_ idx: Int) -> CGPoint? {
            guard idx < keypoints.count, keypoints[idx].confidence > 0.3 else { return nil }
            return keypoints[idx].location
        }

        var validPoints: [CGPoint] = []
        // Body & Head Anchors
        let coreIndices = [0, 1, 2, 3, 4, 5, 6, 11, 12]
        for idx in coreIndices {
            if let p = getPoint(idx) { validPoints.append(p) }
        }

        // Fallback to face contour
        if validPoints.count < 3 {
            for idx in 23...90 {
                 if let p = getPoint(idx) { validPoints.append(p) }
            }
        }

        guard !validPoints.isEmpty else { return nil }

        let centroidX = validPoints.reduce(0) { $0 + $1.x } / CGFloat(validPoints.count)
        let centroidY = validPoints.reduce(0) { $0 + $1.y } / CGFloat(validPoints.count)

        var lowestY: CGFloat?
        var currentTier = 0

        // Check Tiers
        let feetIndices = [15, 16] + Array(17...22)
        if let maxFeet = feetIndices.compactMap({ getPoint($0)?.y }).max() {
            lowestY = maxFeet
            currentTier = 3
        } else if let maxKnee = [13, 14].compactMap({ getPoint($0)?.y }).max() {
            lowestY = maxKnee
            currentTier = 2
        } else if let maxHip = [11, 12].compactMap({ getPoint($0)?.y }).max() {
            lowestY = maxHip
            currentTier = 1
        } else {
            lowestY = [5, 6].compactMap({ getPoint($0)?.y }).max()
            currentTier = 0
        }

        guard let bottomY = lowestY else { return nil }

        let topCandidates = [0, 1, 2, 3, 4]
        var topY = topCandidates.compactMap({ getPoint($0)?.y }).min()

        if topY == nil {
            topY = (Array(23...90) + [5, 6]).compactMap({ getPoint($0)?.y }).min()
        }

        guard let validTopY = topY else { return nil }

        return BodyStructure(
            centroid: CGPoint(x: centroidX, y: centroidY),
            topAnchorY: validTopY,
            spanY: bottomY - validTopY,
            lowestTier: currentTier
        )
    }
}

// 🆕 Helper: Convert PoseDetectionResult to [PoseKeypoint]
// Gates logic relies on [PoseKeypoint]
extension PoseDetectionResult {
    public var asPoseKeypoints: [PoseKeypoint] {
        return zip(keypoints, confidences).map { point, conf in
            PoseKeypoint(location: point, confidence: conf)
        }
    }
}
