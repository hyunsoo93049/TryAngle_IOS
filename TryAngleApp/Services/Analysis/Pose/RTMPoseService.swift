import Foundation
import UIKit

// MARK: - RTMPose Service Adapter
// 역할: RTMPoseRunner 싱글톤을 사용하여 포즈 검출 서비스를 제공합니다.
//       PoseDetector 프로토콜을 구현하여 DetectionPipeline에서 사용됩니다.
//       실시간 분석용 얼굴+포즈 동시 분석 기능도 제공합니다.

public class RTMPoseService: PoseDetector {

    // MARK: - Singleton
    public static let shared = RTMPoseService()

    public let name = "RTMPose"
    public var isEnabled: Bool = true

    // 싱글톤 Runner 사용
    private var runner: RTMPoseRunner? { RTMPoseRunner.shared }

    public init() {}

    public func initialize() async throws {
        // 싱글톤이므로 별도 초기화 불필요 (앱 시작 시 이미 초기화됨)
        
        logInfo("RTMPoseService 초기화 시작 (shared RTMPoseRunner 사용)", category: "RTMPose")

        guard runner != nil else {
            //rtmpose service 초기화 실패 시
            logError("RTMPoseService 초기화 실패 - RTMPoseRunner.shared is nil", category: "RTMPose")
            throw NSError(domain: "RTMPoseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "RTMPoseRunner.shared is nil"])
        }
        
        logInfo("RTMPoseService 초기화 완료", category: "RTMPose")
    }
    
    public func detect(input: FrameInput) async throws -> PoseDetectionResult? {
        guard isEnabled, let runner = runner else { return nil }
        
        // 이미지 방향 처리? RTMPoseRunner는 .up을 갼정하는 경우가 많음.
        // 현재는 input.image를 그대로 전달.
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // 1. Pose Inference
                guard let image = input.image,
                      let result = runner.detectPose(from: image) else {
                    // 감지 실패 또는 사람 없음
                    continuation.resume(returning: nil)
                    return
                }
                
                // 2. Convert raw keypoints to Result format
                // RTMPoseResult uses (point: CGPoint, confidence: Float)
                let keypoints = result.keypoints.map { $0.point }
                let confidences = result.keypoints.map { $0.confidence }
                let bbox = result.boundingBox ?? CGRect.zero
                
                // 3. Optional: Calculate ShotType/LowestPart logic here or in a separate analyzer.
                // For now, we perform basic analysis to populate the fields.
                // We'll reuse the logic from GateSystem/ShotTypeGate logically here.
                
                let analysis = self.analyzePose(keypoints: result.keypoints)
                
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

    // MARK: - 실시간 분석용 얼굴+포즈 동시 분석 (동기 버전)

    /// 얼굴 + 포즈 동시 분석 (RealtimeAnalyzer에서 사용)
    func analyzeFaceAndPose(from image: UIImage) -> (face: FaceAnalysisResult?, pose: PoseAnalysisResult?) {
        guard let runner = runner else {
            return (nil, nil)
        }

        // RTMPose로 포즈 감지
        guard let rtmResult = runner.detectPose(from: image) else {
            return (nil, nil)
        }

        // PoseAnalysisResult 생성
        let poseResult = PoseAnalysisResult(keypoints: rtmResult.keypoints)

        // 얼굴 정보 추출 (RTMPose 키포인트 기반)
        let faceResult = extractFaceFromPose(poseResult: poseResult, imageSize: image.size)

        return (faceResult, poseResult)
    }

    // MARK: - RTMPose 키포인트에서 얼굴 정보 추출

    private func extractFaceFromPose(poseResult: PoseAnalysisResult?, imageSize: CGSize) -> FaceAnalysisResult? {
        guard let pose = poseResult, pose.keypoints.count >= 23 else {
            return nil
        }

        // RTMPose 얼굴 키포인트 (23~90번): 68개
        let faceKeypoints = Array(pose.keypoints[23..<min(91, pose.keypoints.count)])

        // 신뢰도 있는 얼굴 키포인트 필터링
        let validFacePoints = faceKeypoints.filter { $0.confidence > 0.3 }
        guard validFacePoints.count >= 5 else {
            return nil  // 최소 5개 이상의 키포인트 필요
        }

        // 얼굴 바운딩 박스 계산
        let facePoints = validFacePoints.map { $0.point }
        let minX = facePoints.map { $0.x }.min() ?? 0
        let maxX = facePoints.map { $0.x }.max() ?? 0
        let minY = facePoints.map { $0.y }.min() ?? 0
        let maxY = facePoints.map { $0.y }.max() ?? 0

        // 정규화된 좌표로 변환 (0.0 ~ 1.0)
        let faceRect = CGRect(
            x: minX / imageSize.width,
            y: minY / imageSize.height,
            width: (maxX - minX) / imageSize.width,
            height: (maxY - minY) / imageSize.height
        )

        // yaw, pitch, roll 추정 (RTMPose 눈/코/입 키포인트에서)
        let (yaw, pitch, roll) = estimateFaceAngles(from: pose.keypoints, imageSize: imageSize)

        return FaceAnalysisResult(
            faceRect: faceRect,
            landmarks: nil,  // Vision landmarks 없음
            yaw: yaw,
            pitch: pitch,
            roll: roll,
            observation: nil  // VNFaceObservation 없음
        )
    }

    // MARK: - 얼굴 각도 추정 (RTMPose 키포인트 기반)

    private func estimateFaceAngles(from keypoints: [(point: CGPoint, confidence: Float)], imageSize: CGSize) -> (Float?, Float?, Float?) {
        guard keypoints.count >= 17 else { return (nil, nil, nil) }

        // 눈 키포인트 (1: left_eye, 2: right_eye)
        let leftEye = keypoints[1]
        let rightEye = keypoints[2]
        let nose = keypoints[0]

        guard leftEye.confidence > 0.5, rightEye.confidence > 0.5 else {
            return (nil, nil, nil)
        }

        // Roll (좌우 기울기): 두 눈의 y 차이
        let eyeDy = leftEye.point.y - rightEye.point.y
        let eyeDx = leftEye.point.x - rightEye.point.x
        let roll = atan2(eyeDy, eyeDx)  // 라디안

        // Yaw (좌우 회전): 두 눈의 x 거리 비율
        let eyeDistance = abs(leftEye.point.x - rightEye.point.x)
        let faceWidth = imageSize.width * 0.3  // 평균 얼굴 너비
        let yaw = (eyeDistance - faceWidth) / faceWidth * 0.5  // 정규화

        // Pitch (상하 각도): 코와 눈의 y 차이
        let pitch: Float? = nose.confidence > 0.5 ? Float((nose.point.y - leftEye.point.y) / imageSize.height) : nil

        return (Float(yaw), pitch, Float(roll))
    }

    // MARK: - 유틸리티

    /// 밝기 계산
    public func calculateBrightness(from cgImage: CGImage) -> Float {
        let width = min(cgImage.width, 100)
        let height = min(cgImage.height, 100)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0.5 }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return 0.5 }

        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var totalBrightness: Float = 0

        for i in stride(from: 0, to: width * height * 4, by: 4) {
            let r = Float(buffer[i]) / 255.0
            let g = Float(buffer[i + 1]) / 255.0
            let b = Float(buffer[i + 2]) / 255.0
            totalBrightness += (r + g + b) / 3.0
        }

        return totalBrightness / Float(width * height)
    }

    /// 전신 영역 추정 (fallback용)
    public func estimateBodyRect(from faceRect: CGRect?) -> CGRect? {
        guard let face = faceRect else { return nil }

        let bodyWidth = face.width * 3
        let bodyHeight = face.height * 7
        let bodyX = face.midX - bodyWidth / 2
        let bodyY = face.minY

        return CGRect(x: bodyX, y: bodyY, width: bodyWidth, height: bodyHeight)
    }
}
