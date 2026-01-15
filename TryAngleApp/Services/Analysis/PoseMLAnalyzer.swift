import Foundation
import UIKit
import Vision  // FaceAnalysisResult의 VNFaceObservation 타입 때문에 필요

// MARK: - PoseML 분석기 (RTMPose via ONNX Runtime)
// RTMPose 133 키포인트로 얼굴 + 포즈 동시 분석
class PoseMLAnalyzer {

    // RTMPose Runner (ONNX Runtime)
    // 🔥 public으로 노출하여 PersonDetector에서 YOLOX 재사용 가능
    let rtmPoseRunner: RTMPoseRunner?

    // 🐛 디버그 로그 파일 경로
    private lazy var logFileURL: URL? = {
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documentsPath.appendingPathComponent("pose_debug.txt")
        }
        return nil
    }()

    init() {
        print("🚀 PoseMLAnalyzer init() 시작")

        // RTMPose Runner 초기화 시도 (stored property 먼저 초기화)
        rtmPoseRunner = RTMPoseRunner()

        // 초기화 완료 후 로그
        logToFile("🚀 PoseMLAnalyzer init() 시작 - \(Date())")

        if rtmPoseRunner != nil {
            print("✅ RTMPose Runner 초기화 성공")
            logToFile("✅ RTMPose 사용 (ONNX Runtime with CoreML EP)")
        } else {
            print("❌ RTMPose Runner 초기화 실패 - ONNX 모델을 찾을 수 없음")
            logToFile("❌ RTMPose 초기화 실패")
        }

        print("🚀 PoseMLAnalyzer init() 완료")
    }

    // 🐛 파일에 로그 기록
    private func logToFile(_ message: String) {
        guard let logFileURL = logFileURL else { return }

        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = "[\(timestamp)] \(message)\n"

        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }

        // 콘솔에도 출력
        print(message)
    }

    // MARK: - 얼굴 + 포즈 동시 분석 (VisionAnalyzer와 동일한 인터페이스)
    private var analysisCallCount = 0
    func analyzeFaceAndPose(from image: UIImage) -> (face: FaceAnalysisResult?, pose: PoseAnalysisResult?) {
        analysisCallCount += 1

        // 10번마다 로그 (너무 많은 로그 방지)
        if analysisCallCount % 10 == 1 {
            logToFile("🔍 analyzeFaceAndPose() 호출됨 (호출 횟수: \(analysisCallCount))")
        }

        // RTMPose 포즈 감지 (ONNX Runtime)
        let poseResult = detectPoseWithRTMPose(from: image)

        // 얼굴 정보 추출 (RTMPose 키포인트 기반)
        let faceResult = extractFaceFromPose(poseResult: poseResult, imageSize: image.size)

        // 10번마다 상세 로그
        if analysisCallCount % 10 == 1 {
            logToFile("   얼굴: \(faceResult != nil ? "✓" : "✗") | 포즈: \(poseResult != nil ? "✓ (RTMPose)" : "✗")")
        }

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

    // MARK: - RTMPose 포즈 감지
    private func detectPoseWithRTMPose(from image: UIImage) -> PoseAnalysisResult? {
        guard let runner = rtmPoseRunner else {
            return nil
        }

        guard let rtmResult = runner.detectPose(from: image) else {
            return nil
        }

        // 🔥 RTMPose 133개 키포인트를 전체 사용
        // RTMPose는 133개 키포인트 제공 (전신 17 + 얼굴 68 + 손 42 + 발 6)
        // 더 정밀한 포즈 비교를 위해 전체 키포인트 사용

        print("✅ RTMPose: \(rtmResult.keypoints.count)개 키포인트 검출")

        return PoseAnalysisResult(keypoints: rtmResult.keypoints)
    }

    /// 밝기 계산 (VisionAnalyzer와 호환)
    func calculateBrightness(from cgImage: CGImage) -> Float {
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

    /// 전신 영역 추정 (VisionAnalyzer와 호환)
    func estimateBodyRect(from faceRect: CGRect?) -> CGRect? {
        guard let face = faceRect else { return nil }

        let bodyWidth = face.width * 3
        let bodyHeight = face.height * 7
        let bodyX = face.midX - bodyWidth / 2
        let bodyY = face.minY

        return CGRect(x: bodyX, y: bodyY, width: bodyWidth, height: bodyHeight)
    }
}
