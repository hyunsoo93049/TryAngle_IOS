import Foundation
import UIKit
import CoreImage
import Combine
import AVFoundation

// MARK: - Analysis Coordinator
// 역할: 실시간 분석 조율자 (RealtimeAnalyzer 대체)
// - DetectionPipeline: 포즈 감지
// - UnifiedFeedbackEngine: 평가
// - AnalysisStateManager: 상태 관리
// 목표: 1521줄 → ~200줄로 단순화

@MainActor
final class AnalysisCoordinator: ObservableObject {

    // MARK: - Dependencies
    private let pipeline = DetectionPipeline()
    private let feedbackEngine = UnifiedFeedbackEngine.shared
    private let stateManager = AnalysisStateManager.shared
    private let referenceAnalyzer = ReferenceAnalyzer.shared

    // MARK: - Processing
    private let processingQueue = DispatchQueue(label: "analysis.coordinator", qos: .userInitiated)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var cancellables = Set<AnyCancellable>()
    private var pipelineCancellables = Set<AnyCancellable>()

    // MARK: - State
    private var isPaused = false
    private var referenceAspectRatio: CameraAspectRatio = .ratio4_3
    private var currentZoomFactor: CGFloat = 1.0
    private var frameCount = 0

    // MARK: - Reference Cache
    private var referenceAnalysisData: FrameAnalysis?
    private var referenceImageSize: CGSize = .zero

    // MARK: - Published State (UI 바인딩 - Legacy 호환)
    // 이 속성들은 AnalysisStateManager에서 동기화됨

    @Published private(set) var instantFeedback: [FeedbackItem] = []
    @Published private(set) var isPerfect: Bool = false
    @Published private(set) var perfectScore: Double = 0.0
    @Published private(set) var categoryStatuses: [CategoryStatus] = []
    @Published private(set) var completedFeedbacks: [CompletedFeedback] = []
    @Published private(set) var gateEvaluation: GateEvaluation?
    @Published private(set) var unifiedFeedback: UnifiedFeedback?
    @Published private(set) var stabilityProgress: Float = 0.0
    @Published private(set) var environmentWarning: String?
    @Published private(set) var currentShotDebugInfo: String?
    @Published private(set) var activeFeedback: ActiveFeedback?
    @Published private(set) var simpleGuide: SimpleGuideResult?

    // Legacy compatibility
    var referenceAnalysis: FrameAnalysis? { referenceAnalysisData }

    // MARK: - Initialization

    init() {
        setupPipeline()
        setupStateBinding()
        referenceAnalyzer.setupDefaultModules()
    }

    // MARK: - Pipeline Setup

    private func setupPipeline() {
        // DetectionPipeline 결과 구독
        pipeline.resultPublisher
            .receive(on: processingQueue)
            .sink { [weak self] result in
                self?.processDetectionResult(result)
            }
            .store(in: &pipelineCancellables)
    }

    private func setupStateBinding() {
        // AnalysisStateManager → Published 속성 동기화
        stateManager.$simpleGuide
            .receive(on: DispatchQueue.main)
            .sink { [weak self] guide in
                self?.simpleGuide = guide
            }
            .store(in: &cancellables)

        stateManager.$gateEvaluation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] eval in
                self?.gateEvaluation = eval
            }
            .store(in: &cancellables)

        stateManager.$isPerfect
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.isPerfect = value
            }
            .store(in: &cancellables)

        stateManager.$stabilityProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.stabilityProgress = value
            }
            .store(in: &cancellables)

        stateManager.$activeFeedback
            .receive(on: DispatchQueue.main)
            .sink { [weak self] feedback in
                self?.activeFeedback = feedback
            }
            .store(in: &cancellables)

        stateManager.$environmentWarning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] warning in
                self?.environmentWarning = warning
            }
            .store(in: &cancellables)
    }

    // MARK: - Subscription Setup

    func setupSubscription(framePublisher: AnyPublisher<CMSampleBuffer, Never>, cameraManager: CameraManager) {
        cancellables.removeAll()
        setupStateBinding()

        framePublisher
            .sink { [weak self] buffer in
                guard let self = self else { return }
                Task { @MainActor in
                    self.process(
                        buffer: buffer,
                        isFrontCamera: cameraManager.isFrontCamera,
                        currentAspectRatio: cameraManager.aspectRatio,
                        zoomFactor: cameraManager.virtualZoom
                    )
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Frame Processing

    private func process(buffer: CMSampleBuffer, isFrontCamera: Bool, currentAspectRatio: CameraAspectRatio, zoomFactor: CGFloat) {
        guard !isPaused else { return }

        self.currentZoomFactor = zoomFactor
        frameCount += 1

        processingQueue.async { [weak self] in
            autoreleasepool {
                guard let self = self else { return }
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }

                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                guard let cgImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

                let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)

                let input = FrameInput(
                    image: image,
                    timestamp: Date().timeIntervalSince1970,
                    cameraPosition: isFrontCamera ? .front : .back,
                    orientation: .up,
                    metadata: nil
                )

                self.pipeline.process(input: input)
            }
        }
    }

    // MARK: - Detection Result Processing

    private func processDetectionResult(_ result: FrameAnalysisResult) {
        guard !isPaused, referenceAnalysisData != nil else { return }

        // 키포인트 추출 (keypoints와 confidences를 zip)
        let currentKeypoints: [PoseKeypoint]
        if let poseResult = result.poseResult {
            currentKeypoints = zip(poseResult.keypoints, poseResult.confidences).map {
                PoseKeypoint(location: $0.0, confidence: $0.1)
            }
        } else {
            currentKeypoints = []
        }

        let hasPersonDetected = !currentKeypoints.isEmpty && currentKeypoints.count >= 17

        // 평가 수행
        let evaluation = feedbackEngine.evaluate(
            currentKeypoints: currentKeypoints,
            hasPersonDetected: hasPersonDetected,
            currentAspectRatio: result.input.cameraPosition == .front ? referenceAspectRatio : referenceAspectRatio,
            currentZoom: currentZoomFactor,
            isFrontCamera: result.input.cameraPosition == .front
        )

        // 상태 업데이트 (메인 스레드)
        Task { @MainActor in
            stateManager.updateSimpleGuide(evaluation.simpleGuide)
            stateManager.updateGateEvaluation(evaluation.gateEvaluation)
            stateManager.updateTemporalLock(isPerfect: evaluation.isPerfect)

            // Debug info
            if let gate1 = evaluation.gateEvaluation?.gate1 {
                self.currentShotDebugInfo = gate1.debugInfo
            }

            // Perfect score
            self.perfectScore = evaluation.gateEvaluation?.overallScore.doubleValue ?? 0.0
        }
    }

    // MARK: - Reference Analysis

    func analyzeReference(_ image: UIImage, imageData: Data? = nil) {
        print("[Coordinator] 레퍼런스 분석 시작...")

        Task {
            await MainActor.run {
                stateManager.updateReference(.analyzing)
            }

            // RTMPoseRunner 대기
            var waitCount = 0
            while RTMPoseRunner.shared == nil && waitCount < 50 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waitCount += 1
            }

            // 분석 수행
            let result = await referenceAnalyzer.analyze(image: image, imageData: imageData)

            await MainActor.run {
                self.processReferenceResult(result, image: image)
            }
        }
    }

    private func processReferenceResult(_ result: ReferenceAnalysisResult, image: UIImage) {
        let context = result.context
        let imageSize = result.input.imageSize

        // 키포인트 변환
        let keypoints = context.poseKeypoints?.map {
            PoseKeypoint(location: $0.point, confidence: $0.confidence)
        }

        // FrameAnalysis 생성 (Legacy 호환)
        let depth: V15DepthResult?
        if let depthResult = context.depthResult {
            depth = V15DepthResult(
                depthImage: nil,
                compressionIndex: depthResult.compressionIndex,
                cameraType: .normal
            )
        } else {
            depth = nil
        }

        let aspectRatio = context.aspectRatio ?? .ratio4_3

        referenceAnalysisData = FrameAnalysis(
            faceRect: nil,
            bodyRect: context.preciseBBox,
            brightness: 0,
            tiltAngle: 0,
            faceYaw: nil,
            facePitch: nil,
            cameraAngle: .eyeLevel,
            poseKeypoints: context.poseKeypoints,
            compositionType: context.compositionType,
            gaze: nil,
            depth: depth,
            aspectRatio: aspectRatio,
            imagePadding: nil
        )

        referenceAspectRatio = aspectRatio
        referenceImageSize = imageSize

        // UnifiedFeedbackEngine에 레퍼런스 설정
        if let kps = keypoints, !kps.isEmpty {
            feedbackEngine.setReference(
                keypoints: kps,
                imageSize: imageSize,
                aspectRatio: aspectRatio,
                zoomFactor: nil
            )

            let shotType = ShotTypeGate.fromKeypoints(kps)
            stateManager.updateReference(.ready(shotType: shotType.displayName, aspectRatio: aspectRatio.displayName))
        } else if let bbox = context.preciseBBox {
            feedbackEngine.setReferenceFallback(
                bbox: bbox,
                imageSize: imageSize,
                aspectRatio: aspectRatio,
                zoomFactor: nil
            )
            stateManager.updateReference(.ready(shotType: "BBox 기반", aspectRatio: aspectRatio.displayName))
        } else {
            stateManager.updateReference(.failed(reason: "분석 실패"))
        }

        print("[Coordinator] 레퍼런스 분석 완료!")
    }

    // MARK: - Pause/Resume

    func pauseAnalysis() {
        isPaused = true
        instantFeedback = []
        stateManager.resetAll()
    }

    func resumeAnalysis() {
        isPaused = false
    }

    // MARK: - Capture Reset

    func resetAfterCapture() {
        stateManager.resetAfterCapture()
    }
}

// MARK: - CGFloat Extension

private extension CGFloat {
    var doubleValue: Double { Double(self) }
}
