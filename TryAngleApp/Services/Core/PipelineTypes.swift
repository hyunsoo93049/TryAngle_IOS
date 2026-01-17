import Foundation
import CoreGraphics
import UIKit
import AVFoundation

// MARK: - Pipeline Data Types

/// 결과 데이터의 기본 타입
public protocol DetectionResult {
    var timestamp: TimeInterval { get }
}

/// 분석에 사용될 입력 데이터
public struct FrameInput {
    public let image: UIImage? // 🔧 Optional for metadata-only processing
    public let imageSize: CGSize // 🆕 Direct access to size
    public let timestamp: TimeInterval
    public let cameraPosition: AVCaptureDevice.Position
    public let orientation:  UIImage.Orientation
    
    // 추가적인 메타데이터 (Exif 등)
    public let metadata: [String: Any]?
    
    public init(image: UIImage? = nil, 
                imageSize: CGSize? = nil,
                timestamp: TimeInterval = Date().timeIntervalSince1970, 
                cameraPosition: AVCaptureDevice.Position = .back,
                orientation: UIImage.Orientation = .up,
                metadata: [String: Any]? = nil) {
        self.image = image
        // 🔧 Derive size from image if provided, otherwise required
        if let img = image {
            self.imageSize = img.size
        } else if let size = imageSize {
            self.imageSize = size
        } else {
            self.imageSize = .zero
        }
        self.timestamp = timestamp
        self.cameraPosition = cameraPosition
        self.orientation = orientation
        self.metadata = metadata
    }
}

/// 모든 모듈의 분석 결과를 담는 컨테이너
public struct FrameAnalysisResult {
    public let timestamp: TimeInterval
    public let input: FrameInput
    
    // 각 모듈별 결과 (Optional)
    public var poseResult: PoseDetectionResult?
    public var depthResult: DepthEstimationResult?
    public var segmentationResult: SegmentationResult?
    public var compositionResult: CompositionResult?
    public var poseComparison: PoseComparisonResult? // 🆕 Added for Gate 4
    
    public init(input: FrameInput, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.input = input
        self.timestamp = timestamp
    }
}
