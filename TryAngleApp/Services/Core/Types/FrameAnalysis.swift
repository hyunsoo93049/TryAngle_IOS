import Foundation
import CoreGraphics
import UIKit

// MARK: - Frame Analysis
// 단일 프레임의 분석 결과를 담는 구조체
// Legacy 호환성을 위해 유지

struct FrameAnalysis {
    let faceRect: CGRect?
    let bodyRect: CGRect?
    let brightness: Float
    let tiltAngle: Float
    let faceYaw: Float?
    let facePitch: Float?
    let cameraAngle: CameraAngle
    let poseKeypoints: [(point: CGPoint, confidence: Float)]?
    let compositionType: CompositionType?
    let gaze: GazeResult?
    let depth: V15DepthResult?
    let aspectRatio: CameraAspectRatio
    let imagePadding: ImagePadding?
}

// MARK: - Supporting Types
// Note: GazeResult는 GazeTracker.swift에 정의됨

struct ImagePadding {
    let top: CGFloat
    let bottom: CGFloat
    let left: CGFloat
    let right: CGFloat

    static let zero = ImagePadding(top: 0, bottom: 0, left: 0, right: 0)
}
