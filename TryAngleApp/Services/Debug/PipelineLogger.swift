import Foundation
import Combine

// MARK: - Pipeline Logger

public class PipelineLogger: ObservableObject {
    public static let shared = PipelineLogger()
    
    @Published public var logs: [String] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    public func attach(to pipeline: DetectionPipeline) {
        pipeline.resultPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                self?.logResult(result)
            }
            .store(in: &cancellables)
    }
    
    private func logResult(_ result: FrameAnalysisResult) {
        let timestamp = Date().timeIntervalSince1970
        var logEntry = "[\(String(format: "%.3f", timestamp))] Frame Processed"
        
        if let pose = result.poseResult {
            logEntry += " | Pose: \(pose.keypoints.count) pts (Lowest: \(pose.lowestBodyPart))"
        }
        
        if let depth = result.depthResult {
            logEntry += " | Depth: \(String(format: "%.2f", depth.compressionIndex))"
        }
        
        if let comp = result.compositionResult {
            logEntry += " | Score: \(String(format: "%.2f", comp.score))"
        }
        
        // Keep last 50 logs
        if logs.count > 50 {
            logs.removeFirst()
        }
        logs.append(logEntry)
    }
    
    public func clear() {
        logs.removeAll()
    }
}
