import Foundation
import UIKit

// MARK: - RTMPose Service Adapter

public class RTMPoseService: PoseDetector {
    public let name = "RTMPose"
    public var isEnabled: Bool = true
    
    // 기존 Runner 재사용
    private var runner: RTMPoseRunner?
    
    public init() {}
    
    public func initialize() async throws {
        // 백그라운드 스레드에서 초기화 (ONNX 모델 로딩 등)
        print("🚀 RTMPoseService initializing...")
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                if let runner = RTMPoseRunner() {
                    self?.runner = runner
                    print("✅ RTMPoseService initialized successfully.")
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "RTMPoseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize RTMPoseRunner"]))
                }
            }
        }
    }
    
    public func detect(input: FrameInput) async throws -> PoseDetectionResult? {
        guard isEnabled, let runner = runner else { return nil }
        
        // 이미지 방향 처리? RTMPoseRunner는 .up을 갼정하는 경우가 많음.
        // 현재는 input.image를 그대로 전달.
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // 1. Pose Inference
                guard let result = runner.detectPose(from: input.image),
                      let firstPerson = result.first else {
                    // 감지 실패 또는 사람 없음
                    continuation.resume(returning: nil)
                    return
                }
                
                // 2. Convert raw keypoints to Result format
                // RTMPoseResult uses (point: CGPoint, confidence: Float)
                let keypoints = firstPerson.keypoints.map { $0.point }
                let confidences = firstPerson.keypoints.map { $0.confidence }
                let bbox = firstPerson.boundingBox ?? CGRect.zero
                
                // 3. Optional: Calculate ShotType/LowestPart logic here or in a separate analyzer.
                // For now, we perform basic analysis to populate the fields.
                // We'll reuse the logic from GateSystem/ShotTypeGate logically here.
                
                let analysis = self.analyzePose(keypoints: firstPerson.keypoints)
                
                let poseResult = PoseDetectionResult(
                    timestamp: input.timestamp,
                    keypoints: keypoints,
                    confidences: confidences,
                    roughBBox: bbox,
                    lowestBodyPart: analysis.lowestPart,
                    shotType: analysis.shotType
                )
                
                continuation.resume(returning: poseResult)
            }
        }
    }
    
    // MARK: - Local Analysis Helpers (Ported/Simplified from GateSystem)
    
    private struct PoseAnalysis {
        let lowestPart: String
        let shotType: String
    }
    
    private func analyzePose(keypoints: [(point: CGPoint, confidence: Float)]) -> PoseAnalysis {
        // 17개 키포인트(COCO format) 기준 분석
        // 0:nose, 1:LEye, 2:REye, 3:LEar, 4:REar, 5:LShoulder, 6:RShoulder
        // 7:LElbow, 8:RElbow, 9:LWrist, 10:RWrist, 11:LHip, 12:RHip
        // 13:LKnee, 14:RKnee, 15:LAnkle, 16:RAnkle
        
        guard keypoints.count >= 17 else { return PoseAnalysis(lowestPart: "unknown", shotType: "unknown") }
        
        func isVisible(_ idx: Int) -> Bool {
            return keypoints[idx].confidence > 0.3
        }
        
        // Find lowest visible part
        // y 좌표가 클수록 아래쪽 (Vision 좌표계가 아닌 UIKit 좌표계 기준: Top-Left가 0,0)
        // RTMPoseResult는 정규화된 좌표(0~1)를 반환한다고 가정 (Runner 코드 확인 필요)
        // RTMPoseRunner.swift:540 -> point = ... / imageSize (0~1 normalized)
        
        var lowestY: CGFloat = 0.0
        var lowestPart = "face"
        
        let parts = [
            ("ankle", [15, 16]),
            ("knee", [13, 14]),
            ("hip", [11, 12]),
            ("elbow", [7, 8]),
            ("shoulder", [5, 6]),
            ("face", [0])
        ]
        
        for (name, indices) in parts {
            for idx in indices {
                if isVisible(idx) {
                    let y = keypoints[idx].point.y
                    if y > lowestY {
                        lowestY = y
                        lowestPart = name
                    }
                }
            }
        }
        
        // Shot Type Logic (Simplified)
        var shotType = "unknown"
        switch lowestPart {
        case "ankle": shotType = "fullShot"
        case "knee": shotType = "mediumFullShot"
        case "hip": shotType = "mediumShot" // Or americanShot if no elbows
        case "elbow": shotType = "mediumCloseUp"
        case "shoulder": shotType = "closeUp"
        case "face": shotType = "extremeCloseUp"
        default: shotType = "unknown"
        }
        
        return PoseAnalysis(lowestPart: lowestPart, shotType: shotType)
    }
}
