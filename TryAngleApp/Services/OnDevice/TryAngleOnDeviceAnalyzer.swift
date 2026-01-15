//
//  TryAngleOnDevice.swift
//  완전한 온디바이스 실행 시스템
//  작성일: 2025-12-05
//  API 서버 없이 iOS에서 직접 실행
//

import Foundation
import UIKit
import AVFoundation
import Vision
import CoreML

// MARK: - 온디바이스 통합 분석기
class TryAngleOnDeviceAnalyzer {

    // 모델들
    private let rtmposeRunner: RTMPoseRunner
    private let depthEstimator: DepthAnythingCoreML
    private let personDetector: PersonDetector?  // 사람 검출기 (선택적)

    // 피드백 생성기
    private let feedbackGenerator: OnDeviceFeedbackGenerator

    // 성능 추적
    private var performanceStats = PerformanceStats()

    // 설정
    private let useLegacySystem: Bool

    init(enableLegacySystem: Bool = false) {
        print("🚀 TryAngle 온디바이스 시스템 초기화...")

        self.useLegacySystem = enableLegacySystem

        // RTMPose (ONNX)
        if let rtmpose = RTMPoseRunner() {
            self.rtmposeRunner = rtmpose
            print("✅ RTMPose ONNX 로드 완료")
        } else {
            fatalError("❌ RTMPose 초기화 실패")
        }

        // Depth Anything (CoreML) - 🔥 싱글톤 사용 (메모리 최적화)
        self.depthEstimator = DepthAnythingCoreML.shared
        print("✅ Depth Anything CoreML 싱글톤 연결 완료")

        // Person Detector (선택적 - 레거시 시스템)
        // 🔥 YOLOX 재사용: RTMPoseRunner 전달
        if enableLegacySystem {
            self.personDetector = PersonDetector(rtmPoseRunner: self.rtmposeRunner)
            print("✅ Person Detector 로드 완료 (YOLOX 재사용 모드)")
        } else {
            self.personDetector = nil
            print("ℹ️ 레거시 시스템 비활성화 (RTMPose만 사용)")
        }

        // 피드백 생성기
        self.feedbackGenerator = OnDeviceFeedbackGenerator(useLegacySystem: enableLegacySystem)
        print("✅ 피드백 생성기 초기화 완료")

        print("🎯 온디바이스 시스템 준비 완료!")
    }

    // MARK: - 메인 분석 함수
    func analyzeFrame(_ image: UIImage, completion: @escaping (TryAngleFeedback) -> Void) {
        let startTime = CFAbsoluteTimeGetCurrent()

        // 병렬 처리를 위한 DispatchGroup
        let group = DispatchGroup()

        var poseResult: RTMPoseResult?
        var depthResult: V15DepthResult?
        var legacyBBox: CGRect?

        // 1. RTMPose 처리 (비동기)
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            poseResult = self?.rtmposeRunner.detectPose(from: image)
            group.leave()
        }

        // 2. Depth Anything 처리 (비동기)
        group.enter()
        depthEstimator.estimateDepth(from: image) { result in
            if case .success(let depth) = result {
                depthResult = depth
            }
            group.leave()
        }

        // 3. Person Detector 처리 (레거시 모드일 때만)
        if useLegacySystem, let personDetector = personDetector {
            group.enter()
            let ciImage = CIImage(image: image)!
            personDetector.detectPerson(in: ciImage) { bbox in
                legacyBBox = bbox
                group.leave()
            }
        }

        // 4. 모든 처리 완료 후 피드백 생성
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            // 처리 시간 계산
            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
            self.performanceStats.update(processingTime: processingTime)

            // 피드백 생성 (레거시 bbox 포함)
            let feedback = self.feedbackGenerator.generateFeedback(
                pose: poseResult,
                depth: depthResult,
                legacyBBox: legacyBBox,
                imageSize: image.size,
                processingTime: processingTime
            )

            completion(feedback)
        }
    }

    // MARK: - 레퍼런스 분석
    func analyzeReference(_ image: UIImage) -> ReferenceAnalysis {
        // 레퍼런스 이미지 정밀 분석
        let pose = rtmposeRunner.detectPose(from: image)

        var depth: V15DepthResult?
        let semaphore = DispatchSemaphore(value: 0)

        depthEstimator.estimateDepth(from: image) { result in
            if case .success(let d) = result {
                depth = d
            }
            semaphore.signal()
        }
        semaphore.wait()

        return ReferenceAnalysis(
            pose: pose,
            depth: depth,
            timestamp: Date()
        )
    }

    // MARK: - 성능 통계
    func getPerformanceStats() -> PerformanceStats {
        return performanceStats
    }
}

// MARK: - 온디바이스 피드백 생성기
class OnDeviceFeedbackGenerator {

    // 한국어 메시지
    private let messages = FeedbackMessages()
    private let useLegacySystem: Bool

    init(useLegacySystem: Bool = false) {
        self.useLegacySystem = useLegacySystem
    }

    func generateFeedback(pose: RTMPoseResult?,
                         depth: V15DepthResult?,
                         legacyBBox: CGRect? = nil,
                         imageSize: CGSize? = nil,
                         processingTime: TimeInterval) -> TryAngleFeedback {

        var primary = ""
        var suggestions = [String]()
        var movement: MovementGuide?
        var marginInfo: MarginInfo?

        // 1. BBox 선택 (레거시 우선, 없으면 RTMPose)
        let effectiveBBox: CGRect?
        if let legacyBBox = legacyBBox {
            effectiveBBox = legacyBBox
            print("📐 레거시 BBox 사용")
        } else if let pose = pose, let poseBBox = pose.boundingBox {
            // RTMPose bbox를 normalized coordinates로 변환
            effectiveBBox = CGRect(
                x: poseBBox.origin.x / UIScreen.main.bounds.width,
                y: poseBBox.origin.y / UIScreen.main.bounds.height,
                width: poseBBox.width / UIScreen.main.bounds.width,
                height: poseBBox.height / UIScreen.main.bounds.height
            )
            print("🤖 RTMPose BBox 사용")
        } else {
            effectiveBBox = nil
            primary = "인물을 찾을 수 없습니다"
        }

        // 2. 여백 분석 (레거시 스타일)
        if let bbox = effectiveBBox, let size = imageSize {
            let margins = calculateLegacyMargins(bbox: bbox, imageSize: size)
            marginInfo = margins

            // 여백 피드백 생성
            if margins.leftRatio < 0.05 {
                suggestions.append("왼쪽 여백이 부족합니다")
            } else if margins.leftRatio > 0.4 {
                suggestions.append("왼쪽 여백이 너무 큽니다")
            }

            if margins.rightRatio < 0.05 {
                suggestions.append("오른쪽 여백이 부족합니다")
            } else if margins.rightRatio > 0.4 {
                suggestions.append("오른쪽 여백이 너무 큽니다")
            }

            if margins.topRatio < 0.05 {
                suggestions.append("상단 여백이 부족합니다")
            } else if margins.topRatio > 0.3 {
                suggestions.append("상단 여백이 너무 큽니다")
            }

            // 균형 체크
            if margins.balanceScore < 0.6 {
                primary = "구도 균형을 맞춰주세요"
            } else if margins.balanceScore > 0.85 {
                primary = "좋은 구도입니다!"
            }
        }

        // 3. 포즈 기반 피드백 (RTMPose 키포인트)
        if let pose = pose {
            let poseFeedback = analyzePose(pose)
            if primary.isEmpty, let primaryPose = poseFeedback.primary {
                primary = primaryPose
            }
            suggestions.append(contentsOf: poseFeedback.suggestions)
            movement = poseFeedback.movement
        }

        // 4. 깊이 기반 피드백
        if let depth = depth {
            let depthFeedback = analyzeDepth(depth)
            suggestions.append(contentsOf: depthFeedback)
        }

        // 5. 우선순위 정렬
        if suggestions.count > 3 {
            suggestions = Array(suggestions.prefix(3))
        }

        return TryAngleFeedback(
            primary: primary.isEmpty ? "카메라 위치 조정 중..." : primary,
            suggestions: suggestions,
            movement: movement,
            compressionInfo: depth.map { CompressionInfo(
                index: $0.compressionIndex,
                cameraType: $0.cameraType.description,
                suggestion: $0.cameraType.recommendation
            )},
            marginInfo: marginInfo,
            processingTime: processingTime,
            isOnDevice: true,
            usedLegacySystem: legacyBBox != nil
        )
    }

    // MARK: - 레거시 여백 계산
    private func calculateLegacyMargins(bbox: CGRect, imageSize: CGSize) -> MarginInfo {
        // legacy_analyzer.py의 로직을 Swift로 포팅

        let x = bbox.origin.x * imageSize.width
        let y = bbox.origin.y * imageSize.height
        let w = bbox.width * imageSize.width
        let h = bbox.height * imageSize.height

        let leftMargin = x
        let rightMargin = imageSize.width - (x + w)
        let topMargin = y
        let bottomMargin = imageSize.height - (y + h)

        let leftRatio = leftMargin / imageSize.width
        let rightRatio = rightMargin / imageSize.width
        let topRatio = topMargin / imageSize.height
        let bottomRatio = bottomMargin / imageSize.height

        // 균형 점수 계산 (레거시 스타일)
        let horizontalBalance = 1.0 - abs(leftRatio - rightRatio)
        let verticalBalance = 1.0 - abs(topRatio - bottomRatio * 0.5)  // 하단 2:1 비율
        let balanceScore = (horizontalBalance + verticalBalance) / 2.0

        return MarginInfo(
            left: leftMargin,
            right: rightMargin,
            top: topMargin,
            bottom: bottomMargin,
            leftRatio: leftRatio,
            rightRatio: rightRatio,
            topRatio: topRatio,
            bottomRatio: bottomRatio,
            balanceScore: balanceScore
        )
    }

    // MARK: - 포즈 분석
    private func analyzePose(_ pose: RTMPoseResult) -> (primary: String?, suggestions: [String], movement: MovementGuide?) {
        guard let bbox = pose.boundingBox else {
            return (nil, [], nil)
        }

        // 화면 중앙과의 거리 계산
        let screenCenter = CGPoint(x: 0.5, y: 0.5)
        let personCenter = CGPoint(
            x: bbox.midX / UIScreen.main.bounds.width,
            y: bbox.midY / UIScreen.main.bounds.height
        )

        let dx = personCenter.x - screenCenter.x
        let dy = personCenter.y - screenCenter.y

        var primary: String?
        var suggestions = [String]()
        var movement: MovementGuide?

        // 위치 피드백
        if abs(dx) > 0.1 || abs(dy) > 0.1 {
            let direction: String
            let arrow: String

            if abs(dx) > abs(dy) {
                // 수평 이동
                if dx > 0 {
                    direction = "왼쪽으로"
                    arrow = "←"
                } else {
                    direction = "오른쪽으로"
                    arrow = "→"
                }
            } else {
                // 수직 이동
                if dy > 0 {
                    direction = "위로"
                    arrow = "↑"
                } else {
                    direction = "아래로"
                    arrow = "↓"
                }
            }

            let amount = String(format: "%.0f%%", max(abs(dx), abs(dy)) * 100)
            primary = "카메라를 \(direction) 이동하세요"

            movement = MovementGuide(
                direction: direction,
                arrow: arrow,
                amount: amount
            )
        }

        // 크기 피드백
        let bboxArea = bbox.width * bbox.height
        let screenArea = UIScreen.main.bounds.width * UIScreen.main.bounds.height
        let sizeRatio = bboxArea / screenArea

        if sizeRatio < 0.15 {
            suggestions.append("더 가까이 접근하세요")
        } else if sizeRatio > 0.5 {
            suggestions.append("조금 뒤로 물러나세요")
        }

        // 133 키포인트 분석
        let visibleKeypoints = pose.keypoints.filter { $0.confidence > 0.5 }
        if visibleKeypoints.count < 50 {
            suggestions.append("전신이 보이도록 조정하세요")
        }

        return (primary, suggestions, movement)
    }

    // MARK: - 깊이 분석
    private func analyzeDepth(_ depth: V15DepthResult) -> [String] {
        var suggestions = [String]()

        switch depth.cameraType {
        case .wide:
            suggestions.append("광각 렌즈 - 더 가까이 접근하거나 망원 렌즈 사용")
        case .telephoto:
            suggestions.append("망원 렌즈 - 배경과의 분리감이 좋습니다")
        case .normal, .semiTele:
            // 적절함
            break
        }

        if depth.compressionIndex < 0.3 {
            suggestions.append("배경이 너무 넓게 보입니다")
        } else if depth.compressionIndex > 0.8 {
            suggestions.append("배경이 너무 압축되어 있습니다")
        }

        return suggestions
    }
}

// MARK: - 데이터 구조체
struct TryAngleFeedback {
    let primary: String
    let suggestions: [String]
    let movement: MovementGuide?
    let compressionInfo: CompressionInfo?
    let marginInfo: MarginInfo?  // 레거시 여백 정보
    let processingTime: TimeInterval
    let isOnDevice: Bool
    let usedLegacySystem: Bool  // 레거시 시스템 사용 여부
}

struct MovementGuide {
    let direction: String
    let arrow: String
    let amount: String
}

struct CompressionInfo {
    let index: Float
    let cameraType: String
    let suggestion: String?
}

struct MarginInfo {
    let left: CGFloat
    let right: CGFloat
    let top: CGFloat
    let bottom: CGFloat
    let leftRatio: CGFloat
    let rightRatio: CGFloat
    let topRatio: CGFloat
    let bottomRatio: CGFloat
    let balanceScore: CGFloat
}

struct ReferenceAnalysis {
    let pose: RTMPoseResult?
    let depth: V15DepthResult?
    let timestamp: Date
}

struct PerformanceStats {
    var totalFrames: Int = 0
    var averageTime: TimeInterval = 0
    var minTime: TimeInterval = Double.greatestFiniteMagnitude
    var maxTime: TimeInterval = 0

    mutating func update(processingTime: TimeInterval) {
        totalFrames += 1
        averageTime = ((averageTime * Double(totalFrames - 1)) + processingTime) / Double(totalFrames)
        minTime = min(minTime, processingTime)
        maxTime = max(maxTime, processingTime)
    }

    var fps: Double {
        return averageTime > 0 ? 1.0 / averageTime : 0
    }
}

// MARK: - 피드백 메시지
struct FeedbackMessages {
    let movement = [
        "up": "위로 이동하세요",
        "down": "아래로 이동하세요",
        "left": "왼쪽으로 이동하세요",
        "right": "오른쪽으로 이동하세요"
    ]

    let composition = [
        "center": "중앙에 위치시키세요",
        "rule_of_thirds": "3분할 선에 맞추세요",
        "leading_space": "시선 방향에 공간을 두세요"
    ]

    let framing = [
        "too_tight": "프레임이 너무 타이트합니다",
        "too_loose": "프레임이 너무 느슨합니다",
        "good": "좋은 프레이밍입니다"
    ]
}

// MARK: - 카메라 뷰컨트롤러 (온디바이스)
class TryAngleOnDeviceCameraViewController: UIViewController {

    // 분석기
    private let analyzer = TryAngleOnDeviceAnalyzer()

    // 카메라
    private var captureSession: AVCaptureSession!
    private var videoOutput: AVCaptureVideoDataOutput!
    private var previewLayer: AVCaptureVideoPreviewLayer!

    // UI
    private let feedbackLabel = UILabel()
    private let movementArrow = UILabel()
    private let performanceLabel = UILabel()
    private let compressionLabel = UILabel()

    // 프레임 스킵
    private var frameCounter = 0
    private let processEveryNFrames = 3  // 3프레임마다 처리

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupUI()
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .hd1280x720

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else { return }

        captureSession.addInput(input)

        videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video.queue"))
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        captureSession.addOutput(videoOutput)

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)

        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    private func setupUI() {
        // 피드백 레이블
        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        feedbackLabel.textColor = .white
        feedbackLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        feedbackLabel.textAlignment = .center
        feedbackLabel.numberOfLines = 0
        feedbackLabel.layer.cornerRadius = 10
        feedbackLabel.clipsToBounds = true
        feedbackLabel.font = .systemFont(ofSize: 16, weight: .medium)
        view.addSubview(feedbackLabel)

        // 움직임 화살표
        movementArrow.translatesAutoresizingMaskIntoConstraints = false
        movementArrow.textColor = .systemYellow
        movementArrow.font = .systemFont(ofSize: 48)
        movementArrow.textAlignment = .center
        view.addSubview(movementArrow)

        // 성능 레이블
        performanceLabel.translatesAutoresizingMaskIntoConstraints = false
        performanceLabel.textColor = .systemGreen
        performanceLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        performanceLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        view.addSubview(performanceLabel)

        // 압축감 레이블
        compressionLabel.translatesAutoresizingMaskIntoConstraints = false
        compressionLabel.textColor = .white
        compressionLabel.font = .systemFont(ofSize: 14)
        compressionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        compressionLabel.layer.cornerRadius = 5
        compressionLabel.clipsToBounds = true
        view.addSubview(compressionLabel)

        NSLayoutConstraint.activate([
            // 피드백
            feedbackLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            feedbackLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            feedbackLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            feedbackLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),

            // 화살표
            movementArrow.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            movementArrow.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            // 성능
            performanceLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            performanceLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),

            // 압축감
            compressionLabel.topAnchor.constraint(equalTo: performanceLabel.bottomAnchor, constant: 5),
            compressionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10)
        ])

        // 온디바이스 표시
        let onDeviceLabel = UILabel()
        onDeviceLabel.text = "📱 On-Device"
        onDeviceLabel.textColor = .systemBlue
        onDeviceLabel.font = .systemFont(ofSize: 12, weight: .bold)
        onDeviceLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(onDeviceLabel)

        NSLayoutConstraint.activate([
            onDeviceLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            onDeviceLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10)
        ])
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension TryAngleOnDeviceCameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 프레임 스킵
        frameCounter += 1
        if frameCounter % processEveryNFrames != 0 {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // UIImage 변환
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)

        // 분석
        analyzer.analyzeFrame(uiImage) { [weak self] feedback in
            DispatchQueue.main.async {
                self?.updateUI(with: feedback)
            }
        }
    }

    private func updateUI(with feedback: TryAngleFeedback) {
        // 피드백 텍스트
        var feedbackText = feedback.primary
        if !feedback.suggestions.isEmpty {
            feedbackText += "\n" + feedback.suggestions.joined(separator: " • ")
        }
        feedbackLabel.text = feedbackText

        // 움직임 화살표
        movementArrow.text = feedback.movement?.arrow ?? ""

        // 성능
        let fps = 1.0 / feedback.processingTime
        performanceLabel.text = String(format: "%.0f FPS | %.0fms", fps, feedback.processingTime * 1000)

        // 압축감
        if let compression = feedback.compressionInfo {
            compressionLabel.text = "\(compression.cameraType) (\(String(format: "%.2f", compression.index)))"
        }
    }
}