import Foundation
import UIKit
import CoreImage
import Combine
import CoreML
import AVFoundation

// MARK: - Analysis State (Grouped for Performance)
struct AnalysisState: Equatable {
    var instantFeedback: [FeedbackItem] = []
    var isPerfect: Bool = false
    var perfectScore: Double = 0.0
    var categoryStatuses: [CategoryStatus] = []
    var completedFeedbacks: [CompletedFeedback] = []
    var gateEvaluation: GateEvaluation?
    var v15Feedback: String = ""
    var unifiedFeedback: UnifiedFeedback?
    var stabilityProgress: Float = 0.0 // 🆕 0.0 ~ 1.0 (Temporal Lock)
    var environmentWarning: String?      // 🆕 환경 경고 (너무 어두움 등)
    var currentShotDebugInfo: String?    // 🆕 화면 표시용 샷타입 정보 (Debug Mode)

    // 🆕 안정적인 피드백 (동일 피드백은 진행률만 업데이트)
    var activeFeedback: ActiveFeedback?

    // 🆕 단순화된 실시간 가이드 결과
    var simpleGuide: SimpleGuideResult?
}

// MARK: - 실시간 분석을 위한 데이터 구조
struct FrameAnalysis {
    let faceRect: CGRect?                           // 얼굴 위치 (정규화된 좌표)
    let bodyRect: CGRect?                           // 전신 추정 영역
    let brightness: Float                           // 평균 밝기
    let tiltAngle: Float                            // 기울기 각도
    let faceYaw: Float?                             // 얼굴 좌우 회전 (정면=0)
    let facePitch: Float?                           // 얼굴 상하 각도
    let cameraAngle: CameraAngle                    // 카메라 각도
    let poseKeypoints: [(point: CGPoint, confidence: Float)]?  // 신뢰도 포함 키포인트
    let compositionType: CompositionType?           // 구도 타입
    // 🗑️ VNFaceObservation 제거 (RTMPose로 대체)
    let gaze: GazeResult?                           // 🆕 시선 추적 결과
    let depth: V15DepthResult?                      // 🔥 Depth Anything ML 기반 깊이 추정
    let aspectRatio: CameraAspectRatio              // 🆕 카메라 비율
    let imagePadding: ImagePadding?                 // 🆕 여백 정보
}

// 🆕 이미지 여백 정보
struct ImagePadding {
    let top: CGFloat        // 상단 여백 (0.0 ~ 1.0)
    let bottom: CGFloat     // 하단 여백
    let left: CGFloat       // 좌측 여백
    let right: CGFloat      // 우측 여백

    var total: CGFloat {
        return top + bottom + left + right
    }

    var hasExcessivePadding: Bool {
        // 어느 한 쪽이 15% 이상 여백이면 과도함
        return top > 0.15 || bottom > 0.15 || left > 0.15 || right > 0.15
    }
}

// MARK: - 실시간 피드백 생성기
class RealtimeAnalyzer: ObservableObject {
    // MARK: - Published State
    @Published var state = AnalysisState()
    
    // 🔥 Detection Pipeline Integration
    private let pipeline = DetectionPipeline()
    private var pipelineCancellables = Set<AnyCancellable>()
    
    // 💡 Wrapper properties for backward compatibility (read-only)
    var instantFeedback: [FeedbackItem] { state.instantFeedback }
    var isPerfect: Bool { state.isPerfect }
    var perfectScore: Double { state.perfectScore }
    var categoryStatuses: [CategoryStatus] { state.categoryStatuses }
    var completedFeedbacks: [CompletedFeedback] { state.completedFeedbacks }
    var gateEvaluation: GateEvaluation? { state.gateEvaluation }
    var v15Feedback: String { state.v15Feedback }
    var unifiedFeedback: UnifiedFeedback? { state.unifiedFeedback }
    var stabilityProgress: Float { state.stabilityProgress }

    var environmentWarning: String? { state.environmentWarning }
    var currentShotDebugInfo: String? { state.currentShotDebugInfo }
    var activeFeedback: ActiveFeedback? { state.activeFeedback }
    var simpleGuide: SimpleGuideResult? { state.simpleGuide }

    // 🐛 ContentView에서 접근 가능하도ㄱ록 internal로 변경
    var referenceAnalysis: FrameAnalysis?
    var referenceFramingResult: PhotographyFramingResult?  // 🆕 레퍼런스 사진학 프레이밍 분석 결과

    // 🆕 v1.5 캐시된 레퍼런스
    var cachedReference: CachedReference?

    private var lastAnalysisTime = Date()
    private let analysisInterval: TimeInterval = 0.05  // 50ms마다 분석 - 반응속도 개선

    // 🔥 분석 전용 백그라운드 큐 (UI 블로킹 방지)
    private let analysisQueue = DispatchQueue(label: "com.tryangle.analysis", qos: .userInitiated)
    private var isAnalyzing = false  // 분석 중복 방지 플래그
    private var isPaused = false     // 일시 중지 플래그 (탭 전환 시)

    // 히스테리시스를 위한 상태 추적
    private var feedbackHistory: [String: Int] = [:]  // 카테고리별 연속 감지 횟수
    private let historyThreshold = 3  // 🔄 3번 연속 감지되어야 표시 (약 0.3초) - 반응속도 개선
    private var perfectFrameCount = 0  // 완벽한 프레임 연속 횟수
    private let perfectThreshold = 5  // 유지용 (Temporal Lock 이전 하위 호환)

    // 🆕 Phase 2: Temporal Lock (안정화 타이머)
    private enum GateStabilityState: Equatable {
        case idle
        case arming(startedAt: Date)
        case locked
    }
    private var stabilityState: GateStabilityState = .idle
    private let lockDuration: TimeInterval = 0.5  // 0.5초 유지 시 성공

    // 🆕 고정 피드백 (한 번 표시되면 해결될 때까지 유지)
    private var stickyFeedbacks: [String: FeedbackItem] = [:]  // 카테고리별 고정 피드백

    // 🆕 이전 프레임의 피드백 (완료 감지용)
    private var previousFeedbackIds = Set<String>()
    // 🆕 완료 감지를 위한 히스테리시스
    private var disappearedFeedbackHistory: [String: Int] = [:]  // 사라진 피드백의 연속 횟수
    private let disappearedThreshold = 2  // 2번 연속 사라져야 완료로 판단 - 반응속도 개선

    // 🆕 Phase 2: Adaptive Difficulty (좌절 감지)
    private var feedbackStartTimes: [String: Date] = [:]
    private var frustrationMultiplier: CGFloat = 1.0
    private let frustrationThreshold: TimeInterval = 5.0 // 5초간 해결 못하면 난이도 완화

    // 🆕 고정 피드백 카테고리 (포즈 관련은 계속 표시)
    // pose_missing_parts는 이제 레퍼런스 기반으로 제대로 감지되므로 sticky 처리
    private let stickyCategories: Set<String> = [
        "pose_left_arm",
        "pose_right_arm",
        "pose_left_leg",
        "pose_right_leg",
        "pose_missing_parts"
    ]

    // 🔥 RTMPose 분석기 (ONNX Runtime with CoreML EP)
    private var poseMLAnalyzer: PoseMLAnalyzer!
    private let compositionAnalyzer = CompositionAnalyzer()
    private let cameraAngleDetector = CameraAngleDetector()
    
    // 🆕 Image Processing Context
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Subscription Setup
    func setupSubscription(framePublisher: AnyPublisher<CMSampleBuffer, Never>, cameraManager: CameraManager) {
        // 🔥 중복 구독 방지: 기존 구독 취소
        cancellables.removeAll()
        
        framePublisher
            .sink { [weak self] buffer in
                guard let self = self else { return }
                self.process(
                    buffer: buffer,
                    isFrontCamera: cameraManager.isFrontCamera,
                    currentAspectRatio: cameraManager.aspectRatio, // Note: Accessed on background thread?
                    zoomFactor: cameraManager.virtualZoom
                )
            }
            .store(in: &cancellables)
    }
    
    // Note: accessing cameraManager properties (published) from background sink might be racey if not thread safe.
    // However, CameraManager @Published props are updated on Main Thread.
    // Reading them from background thread is generally TSan unsafe but widely done.
    // Ideally, we should receive these values as a combined stream.
    // But for now, since they change rarely compared to frames, reading current value is acceptable risk or we can assume `process` usage.
    // Actually, `process` does `analysisQueue.async`.
    // So we are capturing `cameraManager` instance.
    // Better approach: combineLatest? 
    // Frame comes at 60fps. Changes in zoom/ratio are rare.
    // `cameraManager` is ObservableObject.
    // We can just read properties.
    
    // MARK: - Buffer Processing (Combine Bridge)
    func process(buffer: CMSampleBuffer, isFrontCamera: Bool, currentAspectRatio: CameraAspectRatio, zoomFactor: CGFloat) {
        // Drop frame if analyzing
        // guard !isAnalyzing else { return } // Pipeline handles dropping? Pipeline has isProcessing check.
        // We use pipeline.isProcessing internally. 
        
        // Throttling handled by Pipeline implicitly if we don't await? 
        // Actually pipeline.process is async fire-and-forget but checks isProcessing.
        
        guard !isPaused else { return }
        
        self.currentZoomFactor = zoomFactor
        
        // Extract brightness
        var brightness: Double?
        if let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) {
             let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
             if let exif = ciImage.properties["{Exif}"] as? [String: Any] {
                 brightness = exif["BrightnessValue"] as? Double
             }
        }
        
        // Create FrameInput
        // Note: Creating UIImage from buffer is heavy. Pipeline expects FrameInput.
        // If pipeline can take buffer, better. But FrameInput takes UIImage.
        // conversion logic:
        
        analysisQueue.async { [weak self] in
            guard let self = self else { return }
            
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = self.ciContext
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
            
            let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
            
            var metadata: [String: Any] = [:]
            if let b = brightness {
                metadata["BrightnessValue"] = b
            }
            
            let input = FrameInput(
                image: image,
                timestamp: Date().timeIntervalSince1970,
                cameraPosition: isFrontCamera ? .front : .back,
                orientation: .up,
                metadata: metadata
            )
            
            self.pipeline.process(input: input)
        }
    }
    
    private func resetAnalyzingFlag() {
        DispatchQueue.main.async { self.isAnalyzing = false }
    }
    private let gazeTracker = GazeTracker()
    private let depthAnything = DepthAnythingCoreML.shared  // 🔥 싱글톤 사용 (메모리 최적화)
    private let poseComparator = AdaptivePoseComparator()
    // framingAnalyzer 제거됨 - Legacy 폴더로 이동 (2025-12-29)
    private let photographyFramingAnalyzer = PhotographyFramingAnalyzer()  // 사진학 기반 프레이밍 분석기

    // 🆕 v1.5 통합 Gate System (5단계)
    private let gateSystem = GateSystem.shared
    private let marginAnalyzer = MarginAnalyzer()
    private let personDetector = PersonDetector()  // 정밀 BBox (30프레임마다) - YOLOX 재사용
    private let focalLengthEstimator = FocalLengthEstimator.shared  // 🆕 35mm 환산 초점거리

    // 🆕 단순화된 실시간 가이드 시스템 (GateSystem 대체용)
    private let simpleRealTimeGuide = SimpleRealTimeGuide.shared

    // 🆕 v1.5 프레임 카운터 (Level 처리용)
    private var frameCount = 0
    private var lastYOLOXBBox: CGRect?           // 🆕 YOLOX BBox 캐시 (매 프레임 갱신)
    private var lastPoseKeypoints: [(point: CGPoint, confidence: Float)]?  // 🆕 RTMPose 키포인트 캐시
    private var lastPoseResult: PoseAnalysisResult?  // 🆕 RTMPose 결과 캐시
    private var lastCompressionIndex: CGFloat?  // 마지막 압축감 캐시
    private var lastDepthResult: V15DepthResult?   // 🔥 Depth Anything 결과 캐시

    // 🆕 RTMPose 호출 주기 (매 프레임 - iPhone 16 Pro 최적화)
    // A18 Pro Neural Engine이 충분히 처리 가능, 발열 시 다시 2~3으로 조정
    private let rtmPoseInterval: Int = 1

    // 🆕 35mm 환산 초점거리 관련
    private var referenceImageData: Data?       // 레퍼런스 EXIF 추출용
    private var referenceDepthMap: MLMultiArray?  // 레퍼런스 뎁스맵 (EXIF 없을 때 fallback)
    private var referenceFocalLength: FocalLengthInfo?  // 캐시된 레퍼런스 초점거리
    var currentZoomFactor: CGFloat = 1.0        // 현재 줌 배율 (CameraManager에서 업데이트)

    // 🆕 목표 줌 배율 (레퍼런스 분석 시 한 번만 계산, 이후 고정)
    private var targetZoomFactor: CGFloat?      // 예: 2.4x - nil이면 줌 체크 안함

    // 🔥 성능 최적화
    private let thermalManager = ThermalStateManager()
    private let frameSkipper = AdaptiveFrameSkipper()
    private var lastPerformanceLog = Date()

    // 🆕 초기화
    init() {
        // Setup Pipeline
        self.setupPipeline()
        
        // ... (Keep existing bg init for Reference Analyzer if needed)

        // print("🎬🎬🎬 RealtimeAnalyzer init() 호출됨 🎬🎬🎬")

        // 🔥 PoseMLAnalyzer를 백그라운드에서 미리 로드 (앱 시작 시 17초 지연 방지)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // print("🔥 RealtimeAnalyzer: PoseMLAnalyzer 백그라운드 초기화 시작")
            let startTime = CACurrentMediaTime()
            let analyzer = PoseMLAnalyzer()
            let loadTime = (CACurrentMediaTime() - startTime) * 1000
            // print("✅ RealtimeAnalyzer: PoseMLAnalyzer 초기화 완료 (\(String(format: "%.0f", loadTime))ms)")

            DispatchQueue.main.async {
                self?.poseMLAnalyzer = analyzer

                // 🔥 PersonDetector에 RTMPoseRunner 연결 (YOLOX 재사용)
                if let rtmRunner = analyzer.rtmPoseRunner {
                    self?.personDetector.setRTMPoseRunner(rtmRunner)
                }
            }
        }
    }


    // MARK: - Helper Methods

    /// 여백 계산 (RTMPose 구조적 키포인트 기반)
    private func calculatePaddingFromKeypoints(
        keypoints: [(point: CGPoint, confidence: Float)]
    ) -> ImagePadding? {
        // 구조적 키포인트만 사용 (0-16: 몸통 키포인트, 손가락/얼굴 랜드마크 제외)
        let structuralIndices = PhotographyFramingAnalyzer.StructuralKeypoints.all

        // 신뢰도 0.3 이상인 키포인트만 필터링
        let validPoints = structuralIndices.compactMap { idx -> CGPoint? in
            guard idx < keypoints.count else { return nil }
            return keypoints[idx].confidence > 0.3 ? keypoints[idx].point : nil
        }

        // 최소 3개 이상의 키포인트가 필요
        guard validPoints.count >= 3 else { return nil }

        // 바운딩 박스 계산 (정규화된 좌표: 0.0 ~ 1.0)
        let minX = validPoints.map { $0.x }.min() ?? 0
        let maxX = validPoints.map { $0.x }.max() ?? 1
        let minY = validPoints.map { $0.y }.min() ?? 0
        let maxY = validPoints.map { $0.y }.max() ?? 1

        // 여백 계산 (정규화된 좌표계)
        let top = 1.0 - maxY     // 상단 여백
        let bottom = minY        // 하단 여백
        let left = minX          // 좌측 여백
        let right = 1.0 - maxX   // 우측 여백

        return ImagePadding(
            top: top,
            bottom: bottom,
            left: left,
            right: right
        )
    }

    /// 🗑️ 구식 여백 계산 (얼굴 위치 기반 bodyRect 추정) - 더 이상 사용 안함
    @available(*, deprecated, message: "Use calculatePaddingFromKeypoints instead")
    private func calculatePadding(bodyRect: CGRect?, imageSize: CGSize) -> ImagePadding? {
        guard let body = bodyRect else { return nil }

        // 🔥 Vision 좌표계: Y=0(화면 하단), Y=1(화면 상단)
        // body.minY = 인물의 아래쪽 경계 (Y 작은 값)
        // body.maxY = 인물의 위쪽 경계 (Y 큰 값)

        let top = 1.0 - body.maxY  // 화면 상단 여백 (인물 위 공간)
        let bottom = body.minY     // 화면 하단 여백 (인물 아래 공간)
        let left = body.minX       // 좌측 여백
        let right = 1.0 - body.maxX  // 우측 여백

        return ImagePadding(
            top: top,
            bottom: bottom,
            left: left,
            right: right
        )
    }

    /// 🆕 v6: 키포인트에서 인물 바운딩 박스 계산 (Python improved_margin_analyzer._calculate_person_bbox 이식)
    /// - Returns: 정규화된 좌표 (0.0 ~ 1.0)의 바운딩 박스
    private func calculateBodyRectFromKeypoints(_ keypoints: [(point: CGPoint, confidence: Float)], imageSize: CGSize) -> CGRect? {
        // 신뢰도 0.3 이상인 구조적 키포인트(0-16)만 필터링
        let structuralIndices = PhotographyFramingAnalyzer.StructuralKeypoints.all

        let validPoints = structuralIndices.compactMap { idx -> CGPoint? in
            guard idx < keypoints.count else { return nil }
            return keypoints[idx].confidence > 0.3 ? keypoints[idx].point : nil
        }

        // 최소 3개 이상의 키포인트가 필요
        guard validPoints.count >= 3 else { return nil }

        // 바운딩 박스 계산 (픽셀 좌표)
        let minX = validPoints.map { $0.x }.min() ?? 0
        let maxX = validPoints.map { $0.x }.max() ?? 1
        let minY = validPoints.map { $0.y }.min() ?? 0
        let maxY = validPoints.map { $0.y }.max() ?? 1

        // 🆕 정규화 (0.0 ~ 1.0)
        let normalizedX = minX / imageSize.width
        let normalizedY = minY / imageSize.height
        let normalizedWidth = (maxX - minX) / imageSize.width
        let normalizedHeight = (maxY - minY) / imageSize.height

        return CGRect(x: normalizedX, y: normalizedY, width: normalizedWidth, height: normalizedHeight)
    }

    // MARK: - 레퍼런스 이미지 분석
    func analyzeReference(_ image: UIImage, imageData: Data? = nil) {
        print("🎯 레퍼런스 이미지 분석 시작...")

        // 🆕 EXIF 추출용 이미지 데이터 저장
        self.referenceImageData = imageData ?? image.jpegData(compressionQuality: 1.0)

        guard let cgImage = image.cgImage else {
            print("❌ cgImage 없음")
            return
        }

        // 🆕 모델 로딩 대기
        guard let analyzer = poseMLAnalyzer else {
            print("⏳ PoseMLAnalyzer 로딩 중... 레퍼런스 분석 대기")
            // 0.5초 후 재시도
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.analyzeReference(image)
            }
            return
        }

        // print("🎯 레퍼런스 이미지 크기: \(cgImage.width) x \(cgImage.height)")
        // print("🎯 레퍼런스 이미지 orientation: \(image.imageOrientation.rawValue)")

        // 🔥 RTMPose로 얼굴+포즈 동시 분석 (ONNX Runtime with CoreML EP)
        // print("🎯 PoseMLAnalyzer.analyzeFaceAndPose() 호출 중...")
        let (faceResult, poseResult) = analyzer.analyzeFaceAndPose(from: image)
        // print("🎯 분석 완료:")
        // print("   - 얼굴: \(faceResult != nil ? "✅ 검출됨" : "❌ 검출 안됨")")
        // print("   - 포즈: \(poseResult != nil ? "✅ 검출됨 (\(poseResult!.keypoints.count)개 키포인트)" : "❌ 검출 안됨")")

        if let pose = poseResult {
            let visibleCount = pose.keypoints.filter { $0.confidence >= 0.5 }.count
            // print("   - 포즈 신뢰도 ≥ 0.5: \(visibleCount)/\(pose.keypoints.count)개")
        }

        // 🔥 디버그: 포즈 검출 실패 시 이미지 저장
        if poseResult == nil {
            saveDebugImage(image, reason: "pose_detection_failed")
        }

        let faceRect = faceResult?.faceRect
        let faceYaw = faceResult?.yaw
        let facePitch = faceResult?.pitch
        let poseKeypoints = poseResult?.keypoints

        // 밝기 계산
        let brightness = poseMLAnalyzer.calculateBrightness(from: cgImage)

        // 🆕 더치 틸트 감지 (RTMPose 키포인트 기반)
        let tiltAngle = cameraAngleDetector.detectDutchTilt(faceObservation: nil) ?? 0.0

        // 전신 영역 추정
        let bodyRect = poseMLAnalyzer.estimateBodyRect(from: faceRect)

        // 카메라 앵글 감지 (RTMPose 키포인트 기반)
        let cameraAngle = cameraAngleDetector.detectCameraAngle(
            faceRect: faceRect,
            facePitch: facePitch,
            faceObservation: nil
        )

        // 구도 타입 분류
        var compositionType: CompositionType? = nil
        if let faceRect = faceRect {
            let subjectPosition = CGPoint(x: faceRect.midX, y: faceRect.midY)
            compositionType = compositionAnalyzer.classifyComposition(subjectPosition: subjectPosition)
        }

        // 🗑️ 시선 추적 비활성화 (VNFaceObservation 제거)
        let gaze: GazeResult? = nil

        // 🔥 Depth Anything ML 기반 깊이 추정 (완전 비동기 처리)
        // ✅ 세마포어 제거: 백그라운드 큐에서 비동기 체인으로 처리
        // ⚠️ 메모리 최적화: autoreleasepool로 임시 메모리 즉시 해제

        // 🆕 비율 감지 (먼저 계산)
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let aspectRatio = CameraAspectRatio.detect(from: imageSize)

        // 🔍 디버그: 레퍼런스 이미지 비율 감지 결과
        let longSide = max(imageSize.width, imageSize.height)
        let shortSide = min(imageSize.width, imageSize.height)
        let rawRatio = longSide / shortSide
        print("📐 [레퍼런스 비율] 이미지: \(Int(imageSize.width))x\(Int(imageSize.height)) → 비율: \(String(format: "%.3f", rawRatio)) → 감지: \(aspectRatio.displayName)")

        // 🆕 여백 계산 (RTMPose 키포인트 기반)
        // 🔧 RTMPose가 이미 정규화된 좌표(0.0~1.0)를 반환하므로 그대로 사용
        var padding: ImagePadding? = nil
        if let keypoints = poseKeypoints, keypoints.count >= 17 {
            // 구조적 키포인트(0-16)로 여백 계산
            padding = calculatePaddingFromKeypoints(keypoints: keypoints)
        }

        // 🆕 사진학 기반 프레이밍 분석 (RTMPose 133개 키포인트)
        // 🔧 RTMPose가 이미 정규화된 좌표(0.0~1.0)를 반환하므로 그대로 사용
        if let keypoints = poseKeypoints, keypoints.count >= 133 {
            referenceFramingResult = photographyFramingAnalyzer.analyze(
                keypoints: keypoints,
                imageSize: imageSize
            )
            if let refFraming = referenceFramingResult {
                // print("   - 📸 레퍼런스 샷 타입: \(refFraming.shotType.rawValue)")
                // print("   - 📸 레퍼런스 헤드룸: \(String(format: "%.1f%%", refFraming.headroom * 100))")
                // print("   - 📸 레퍼런스 카메라 앵글: \(refFraming.cameraAngle.rawValue)")
            }
        } else {
            referenceFramingResult = nil
            // print("   - ⚠️ 사진학 프레이밍 분석 불가 (키포인트 부족)")
        }

        // 🔥 비동기 체인 시작: Depth 추정 → PersonDetector → 최종 분석 완료
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            autoreleasepool {
                // Step 1: Depth 추정 (비동기)
                self.depthAnything.estimateDepth(from: image) { [weak self] result in
                    guard let self = self else { return }

                    let depth: V15DepthResult?
                    switch result {
                    case .success(let depthResult):
                        depth = depthResult
                        // print("✅ Depth Anything 분석 완료: 압축감 \(String(format: "%.2f", depthResult.compressionIndex))")
                    case .failure(let error):
                        // print("⚠️ Depth Anything 분석 실패: \(error.localizedDescription)")
                        depth = nil
                    }

                    // Step 2: PersonDetector (비동기)
                    if let ciImage = CIImage(image: image) {
                        self.personDetector.detectPerson(in: ciImage) { [weak self] preciseBBox in
                            guard let self = self else { return }

                            // Step 3: 최종 분석 완료 (백그라운드에서)
                            self.finalizeReferenceAnalysis(
                                faceRect: faceRect,
                                bodyRect: bodyRect,
                                brightness: Double(brightness),
                                tiltAngle: Double(tiltAngle),
                                faceYaw: faceYaw.map { Double($0) },
                                facePitch: facePitch.map { Double($0) },
                                cameraAngle: cameraAngle,
                                poseKeypoints: poseKeypoints,
                                compositionType: compositionType,
                                gaze: gaze,
                                depth: depth,
                                aspectRatio: aspectRatio,
                                padding: padding,
                                preciseBBox: preciseBBox,
                                image: image,
                                imageSize: imageSize
                            )
                        }
                    } else {
                        // PersonDetector 실행 불가 시 바로 완료
                        self.finalizeReferenceAnalysis(
                            faceRect: faceRect,
                            bodyRect: bodyRect,
                            brightness: Double(brightness),
                            tiltAngle: Double(tiltAngle),
                            faceYaw: faceYaw.map { Double($0) },
                            facePitch: facePitch.map { Double($0) },
                            cameraAngle: cameraAngle,
                            poseKeypoints: poseKeypoints,
                            compositionType: compositionType,
                            gaze: gaze,
                            depth: depth,
                            aspectRatio: aspectRatio,
                            padding: padding,
                            preciseBBox: nil,
                            image: image,
                            imageSize: imageSize
                        )
                    }
                }
            }
        }
    }

    // MARK: - 레퍼런스 분석 최종 처리 (비동기 완료 후)
    private func finalizeReferenceAnalysis(
        faceRect: CGRect?,
        bodyRect: CGRect?,
        brightness: Double,
        tiltAngle: Double,
        faceYaw: Double?,
        facePitch: Double?,
        cameraAngle: CameraAngle,
        poseKeypoints: [(point: CGPoint, confidence: Float)]?,
        compositionType: CompositionType?,
        gaze: GazeResult?,
        depth: V15DepthResult?,
        aspectRatio: CameraAspectRatio,
        padding: ImagePadding?,
        preciseBBox: CGRect?,
        image: UIImage,
        imageSize: CGSize
    ) {
        // 백그라운드 큐에서 실행됨

        // 🆕 v1.5: 여백 분석 및 캐싱
        // 🔧 bbox가 없어도 cachedReference는 항상 설정 (비율 게이트 등 동작 보장)
        let bbox = preciseBBox ?? bodyRect ?? CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)  // 기본값: 이미지 중앙 80%

        let marginResult = marginAnalyzer.analyze(
            bbox: bbox,
            imageSize: imageSize,
            isNormalized: true
        )

        // 캐시 저장
        let refId = UUID().uuidString
        let cachedRef = CacheManager.shared.cacheReference(
            id: refId,
            image: image,
            bbox: bbox,
            margins: marginResult,
            compressionIndex: depth.map { CGFloat($0.compressionIndex) }
        )

        // 메인 스레드에서 캐시 업데이트
        DispatchQueue.main.async { [weak self] in
            self?.cachedReference = cachedRef
        }

        if preciseBBox == nil && bodyRect == nil {
            // print("⚠️ 레퍼런스 BBox 없음 → 기본값 사용 (비율 게이트는 동작)")
        }

        // 🆕 35mm 환산 초점거리 추정 (EXIF → 뎁스맵 순서)
        let refFL = focalLengthEstimator.estimateReferenceFocalLength(
            imageData: referenceImageData,
            depthMap: referenceDepthMap,
            fallback: 50
        )

        // 📸 레퍼런스 분석 요약 (한 줄)
        // 🔧 샷타입은 ShotTypeGate.fromKeypoints() 기준으로 통일 (GateSystem/SimpleGuide와 동일)
        let shotTypeStr: String
        if let keypoints = poseKeypoints {
            let poseKeypointsConverted = keypoints.map { PoseKeypoint(location: $0.point, confidence: $0.confidence) }
            shotTypeStr = ShotTypeGate.fromKeypoints(poseKeypointsConverted).displayName
        } else {
            shotTypeStr = "분석실패"
        }
        let compressionStr = depth.map { String(format: "%.2f", $0.compressionIndex) } ?? "N/A"
        let keypointCount = poseKeypoints?.filter { $0.confidence >= 0.5 }.count ?? 0

        print("📸 [레퍼런스] 비율:\(aspectRatio.displayName) | 샷타입:\(shotTypeStr) | 압축:\(compressionStr) | 초점:\(refFL.focalLength35mm)mm | 키포인트:\(keypointCount)개")

        // 메인 스레드에서 referenceAnalysis 및 referenceFocalLength 업데이트
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.referenceAnalysis = FrameAnalysis(
                faceRect: faceRect,
                bodyRect: bodyRect,
                brightness: Float(brightness),
                tiltAngle: Float(tiltAngle),
                faceYaw: faceYaw.map { Float($0) },
                facePitch: facePitch.map { Float($0) },
                cameraAngle: cameraAngle,
                poseKeypoints: poseKeypoints,
                compositionType: compositionType,
                gaze: gaze,
                depth: depth,
                aspectRatio: aspectRatio,
                imagePadding: padding
            )

            self.referenceFocalLength = refFL

            // 🆕 목표 줌 배율 계산 및 고정 (한 번만!)
            // 레퍼런스가 50mm로 찍혔고, iPhone 기본이 24mm라면 → 50/24 ≈ 2.1x 줌 필요
            if refFL.focalLength35mm > FocalLengthEstimator.iPhoneBaseFocalLength {
                let targetZoom = CGFloat(refFL.focalLength35mm) / CGFloat(FocalLengthEstimator.iPhoneBaseFocalLength)
                self.targetZoomFactor = targetZoom
                print("📐 [목표 줌 설정] \(String(format: "%.1fx", targetZoom)) (레퍼런스 \(refFL.focalLength35mm)mm)")
            } else {
                // 레퍼런스가 광각이면 1x로 고정
                self.targetZoomFactor = 1.0
                print("📐 [목표 줌 설정] 1.0x (레퍼런스 광각 \(refFL.focalLength35mm)mm)")
            }

            // 🆕 SimpleRealTimeGuide에 레퍼런스 설정 (줌 정보 포함)
            if let keypoints = poseKeypoints {
                let poseKeypointsConverted = keypoints.map { PoseKeypoint(location: $0.point, confidence: $0.confidence) }
                self.simpleRealTimeGuide.setReference(
                    keypoints: poseKeypointsConverted,
                    imageSize: imageSize,
                    zoomFactor: self.targetZoomFactor  // 🆕 목표 줌 전달
                )
            }

            print("✅ 레퍼런스 분석 완료 - 실시간 피드백 모드 준비!")
        }
    }

    // MARK: - Pause/Resume (탭 전환용)
    func pauseAnalysis() {
        // print("⏸️ RealtimeAnalyzer: 분석 일시 중지 (탭 전환)")
        isPaused = true

        // 피드백 초기화
        DispatchQueue.main.async {
            var newState = self.state
            newState.instantFeedback = []
            newState.isPerfect = false
            newState.perfectScore = 0.0
            newState.unifiedFeedback = nil
            newState.activeFeedback = nil  // 🆕 활성 피드백 초기화
            self.state = newState
        }
    }

    func resumeAnalysis() {
        // print("▶️ RealtimeAnalyzer: 분석 재개 (탭 복귀)")
        isPaused = false

        // 상태 초기화 (새롭게 시작)
        lastAnalysisTime = Date()
        feedbackHistory.removeAll()
        disappearedFeedbackHistory.removeAll()
        perfectFrameCount = 0
    }

    /// 🆕 촬영 완료 후 Temporal Lock 리셋 (연속 촬영 방지)
    func resetAfterCapture() {
        print("📷 촬영 완료 - Temporal Lock 리셋")
        stabilityState = .idle

        DispatchQueue.main.async {
            var newState = self.state
            newState.stabilityProgress = 0.0
            newState.isPerfect = false
            self.state = newState
        }
    }

    // MARK: - 실시간 프레임 분석

    
    // MARK: - Internal Analysis Logic
    // Renamed from analyzeFrame to separate public/private concerns if needed.
    // Kept public analyzeFrame for legacy calls if any, but logic moved here.
    func analyzeFrame(_ image: UIImage, isFrontCamera: Bool = false, currentAspectRatio: CameraAspectRatio = .ratio4_3) {
        // Adapter for old timer-based calls (will be removed, but kept for safety during refactor)
        guard !isAnalyzing, !isPaused else { return }
        guard Date().timeIntervalSince(lastAnalysisTime) >= thermalManager.recommendedAnalysisInterval else { return }
        isAnalyzing = true
        lastAnalysisTime = Date()
        
        analysisQueue.async { [weak self] in
            self?.analyzeFrameInternal(image, isFrontCamera: isFrontCamera, currentAspectRatio: currentAspectRatio, brightness: nil)
        }
    }

    private func analyzeFrameInternal(_ image: UIImage, isFrontCamera: Bool, currentAspectRatio: CameraAspectRatio, brightness: Double?) {
        // 🆕 Environment Check (Gate 0.5)
        if let b = brightness, b < -2.0 {
            DispatchQueue.main.async {
                var newState = self.state
                newState.environmentWarning = "너무 어두워요 💡"
                newState.isPerfect = false
                newState.stabilityProgress = 0.0
                // Gate 평가 중단은 아니지만 경고 표시
                self.state = newState
            }
            // 너무 어두우면 분석 중단? (사용자 경험상 계속 분석하는게 나을 수도 있지만, 정확도가 떨어짐)
            // 여기서는 경고만 띄우고 분석은 진행 (단, 결과 신뢰도가 낮음)
        } else {
             // 경고 해제는 processAnalysisResult에서 처리 또는 state 업데이트 시
             // 하지만 여기서 async로 해제하면 타이밍 이슈가 있을 수 있음.
             // processAnalysisResult까지 전달해서 처리하는게 안전.
        }
        // Safe check for reference
        guard let reference = referenceAnalysis else {
            // 🔧 DEBUG: referenceAnalysis nil 원인 추적
            // print("⏭️ 실시간 분석 스킵: referenceAnalysis nil (레퍼런스 분석 대기 중)")
            DispatchQueue.main.async {
                var newState = self.state
                newState.instantFeedback = []
                newState.perfectScore = 0.0
                newState.isPerfect = false
                self.state = newState
                self.isAnalyzing = false
            }
            return
        }
        
         guard let cgImage = image.cgImage else {
             resetAnalyzingFlag()
             return 
         }

        // 🆕 모델 로딩 대기 (앱 시작 직후)
        guard let analyzer = self.poseMLAnalyzer else {
            // print("⏳ PoseMLAnalyzer 로딩 중... 분석 스킵")
            resetAnalyzingFlag()
            return
        }

        let analysisStart = CACurrentMediaTime()  // 🔍 프로파일링

        // 🆕 YOLOX + RTMPose 분리 실행
        // - YOLOX: 매 프레임 (~30ms) → 인물 BBox
        // - RTMPose: 3프레임마다 (~175ms) → 키포인트 (캐시 사용)

        var faceResult: FaceAnalysisResult? = nil
        var poseResult: PoseAnalysisResult? = nil

        // 🔥 RTMPose 직접 실행 (YOLOX 의존 제거)
        // RTMPose가 YOLOX 실패 시 자동으로 전체 이미지에서 키포인트 검출
        // 상반신, 무릎샷 등 부분 인물도 검출 가능

        let shouldRunRTMPose = (frameCount % rtmPoseInterval == 0) || lastPoseResult == nil

        if shouldRunRTMPose {
            let poseStart = CACurrentMediaTime()
            let (face, pose) = analyzer.analyzeFaceAndPose(from: image)
            faceResult = face
            poseResult = pose

            // 캐시 업데이트
            if let pose = pose {
                self.lastPoseResult = pose
                self.lastPoseKeypoints = pose.keypoints

                // 🆕 RTMPose 키포인트에서 BBox 계산 (YOLOX 대체)
                if let bbox = ShotTypeGate.calculateKeypointBBox(
                    pose.keypoints.map { PoseKeypoint(location: $0.point, confidence: $0.confidence) }
                ) {
                    self.lastYOLOXBBox = bbox
                }
            }

            let poseTime = (CACurrentMediaTime() - poseStart) * 1000
            // print("📊 [RTMPose] \(String(format: "%.1f", poseTime))ms (프레임 \(frameCount))")
        } else {
            // 캐시된 키포인트 사용
            poseResult = lastPoseResult
            // print("📦 [RTMPose 캐시] 프레임 \(frameCount)")
        }

        let analysisEnd = CACurrentMediaTime()  // 🔍

        // 🔍 프로파일링 로그
        let totalTime = (analysisEnd - analysisStart) * 1000
        // print("📊 [RealtimeAnalyzer] 총분석: \(String(format: "%.1f", totalTime))ms")

        // 분석 완료 후 메인 스레드에서 UI 업데이트
        DispatchQueue.main.async {
            self.isAnalyzing = false
            self.processAnalysisResult(
                faceResult: faceResult,
                poseResult: poseResult,
                cgImage: cgImage,
                reference: reference, // Passed safely
                isFrontCamera: isFrontCamera,
                currentAspectRatio: currentAspectRatio
            )
        }
    }

    // MARK: - 분석 결과 처리 (메인 스레드)
    private func processAnalysisResult(
        faceResult: FaceAnalysisResult?,
        poseResult: PoseAnalysisResult?,
        cgImage: CGImage,
        reference: FrameAnalysis,
        isFrontCamera: Bool,
        currentAspectRatio: CameraAspectRatio
    ) {
        // 🆕 v1.5: 프레임 카운터 증가
        frameCount += 1

        // 🔥 성능 로그 (10초마다)
        if Date().timeIntervalSince(lastPerformanceLog) >= 10 {
            lastPerformanceLog = Date()
            // print(PerformanceOptimizer.shared.getPerformanceReport())
            // print("🌡️ 발열 상태: \(thermalManager.currentThermalState.rawValue), 분석 간격: \(Int(thermalManager.recommendedAnalysisInterval * 1000))ms")
        }

        // 🆕 종횡비 체크는 얼굴 감지와 무관하게 항상 수행
        // Gate 0 (종횡비)는 가장 먼저 체크되어야 함
        let aspectRatioMatched = (currentAspectRatio == reference.aspectRatio)

        // 얼굴이 감지되지 않으면 완성도 0으로 설정
        guard faceResult != nil else {
            // Update grouped state
            var newState = self.state

            // 🔥 종횡비 불일치 시: 종횡비 피드백만 표시
            if !aspectRatioMatched {
                // Gate 0만 포함된 최소 GateEvaluation 생성
                let gate0Result = GateResult(
                    name: "비율",
                    score: 0.0,
                    threshold: 1.0,
                    feedback: "카메라 비율을 \(reference.aspectRatio.displayName)로 변경하세요",
                    icon: "📐",
                    category: "aspect_ratio",
                    debugInfo: "현재: \(currentAspectRatio.displayName) vs 목표: \(reference.aspectRatio.displayName)"
                )
                let dummyGate = GateResult(name: "-", score: 0, threshold: 1, feedback: "", icon: "", category: "")
                newState.gateEvaluation = GateEvaluation(
                    gate0: gate0Result,
                    gate1: dummyGate,
                    gate2: dummyGate,
                    gate3: dummyGate,
                    gate4: dummyGate
                )
                newState.instantFeedback = []
                print("📐 [No Face] 종횡비 불일치: \(currentAspectRatio.displayName) vs \(reference.aspectRatio.displayName)")
            } else {
                // 종횡비는 맞지만 얼굴 없음
                newState.instantFeedback = [FeedbackItem(
                    priority: 1,
                    icon: "👤",
                    message: "얼굴을 화면에 보여주세요",
                    category: "no_face",
                    currentValue: nil,
                    targetValue: nil,
                    tolerance: nil,
                    unit: nil
                )]
                newState.gateEvaluation = nil
            }

            newState.perfectScore = 0.0
            newState.isPerfect = false

            if self.state != newState {
                self.state = newState
            }
            return
        }

        // 밝기 및 기울기
        let brightness = poseMLAnalyzer.calculateBrightness(from: cgImage)
        let tilt = cameraAngleDetector.detectDutchTilt(faceObservation: nil) ?? 0.0

        // 🆕 이미지 크기 (정규화에 필요)
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        // 🆕 전신 영역 - RTMPose 키포인트에서 정확하게 계산 (정규화된 좌표)
        let bodyRect: CGRect? = {
            if let keypoints = poseResult?.keypoints, !keypoints.isEmpty {
                return calculateBodyRectFromKeypoints(keypoints, imageSize: imageSize)
            }
            // RTMPose 키포인트가 없으면 얼굴 기반 추정 (fallback) - 이미 정규화됨
            return poseMLAnalyzer.estimateBodyRect(from: faceResult?.faceRect)
        }()

        // 카메라 앵글 (RTMPose 키포인트 기반)
        let cameraAngle = cameraAngleDetector.detectCameraAngle(
            faceRect: faceResult?.faceRect,
            facePitch: faceResult?.pitch,
            faceObservation: nil
        )

        // 구도
        var compositionType: CompositionType? = nil
        if let faceRect = faceResult?.faceRect {
            let subjectPosition = CGPoint(x: faceRect.midX, y: faceRect.midY)
            compositionType = compositionAnalyzer.classifyComposition(subjectPosition: subjectPosition)
        }

        // 🗑️ 시선 비활성화 (VNFaceObservation 제거)
        let gaze: GazeResult? = nil

        // 🔥 Level 2: Depth Anything ML 깊이 추정 (동적 프레임 스킵)
        let depth: V15DepthResult? = lastDepthResult  // 캐시된 값 사용
        if frameSkipper.shouldExecute(level: 2, frameCount: frameCount) {
            // 동적 간격으로 새로 계산 (비동기 → 백그라운드)
            let uiImage = UIImage(cgImage: cgImage)
            depthAnything.estimateDepth(from: uiImage) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let depthResult):
                        self?.lastDepthResult = depthResult  // 캐시 업데이트
                    case .failure:
                        break  // 실패 시 기존 캐시 유지
                    }
                }
            }
        }

        // 🆕 현재 이미지 크기 (위에서 이미 계산됨)
        let currentImageSize = imageSize

        // 🆕 여백 계산 (RTMPose 키포인트 기반)
        var currentPadding: ImagePadding? = nil
        if let keypoints = poseResult?.keypoints, keypoints.count >= 17 {
            // 키포인트를 정규화된 좌표로 변환 (0.0 ~ 1.0)
            let normalizedKeypoints = keypoints.map { kp -> (point: CGPoint, confidence: Float) in
                let normalizedPoint = CGPoint(
                    x: kp.point.x / currentImageSize.width,
                    y: kp.point.y / currentImageSize.height
                )
                return (point: normalizedPoint, confidence: kp.confidence)
            }
            // 구조적 키포인트(0-16)로 여백 계산
            currentPadding = calculatePaddingFromKeypoints(keypoints: normalizedKeypoints)
        }

        // 🆕 프레이밍 분석 추가 (최우선)
        let _ = FrameAnalysis(
            faceRect: faceResult?.faceRect,
            bodyRect: bodyRect,
            brightness: brightness,
            tiltAngle: tilt,
            faceYaw: faceResult?.yaw,
            facePitch: faceResult?.pitch,
            cameraAngle: cameraAngle,
            poseKeypoints: poseResult?.keypoints,
            compositionType: compositionType,
            gaze: gaze,
            depth: depth,
            aspectRatio: currentAspectRatio,
            imagePadding: currentPadding
        )

        // ============================================
        // 🆕 v1.5 통합 Gate System 평가 (5단계)
        // ============================================

        // 🆕 Level 3 YOLOX 중복 호출 제거
        // YOLOX는 이미 analyzeFrameInternal에서 매 프레임 실행됨 (lastYOLOXBBox에 저장)
        // 여기서 별도로 호출할 필요 없음

        // 🆕 현재 BBox 결정 - YOLOX 결과 우선 사용
        // YOLOX는 매 프레임 실행되므로 가장 최신 BBox임
        let currentBBox: CGRect
        if let yoloxBBox = lastYOLOXBBox {
            // YOLOX에서 인물 감지됨 → 가장 정확한 BBox
            currentBBox = yoloxBBox
        } else if let body = bodyRect {
            // YOLOX 실패 시 Vision bodyRect 사용 (fallback)
            currentBBox = body
        } else {
            // 둘 다 인물 없음 → 작은 기본값 (인물 미검출로 처리됨)
            currentBBox = CGRect(x: 0.45, y: 0.45, width: 0.01, height: 0.01)
        }

        // 🔧 FIX: 압축감은 현재 프레임 값 사용 (캐시 의존 제거)
        // depth가 nil이면 압축감도 nil로 전달 → Gate에서 "분석 중" 표시
        let currentCompressionIndex: CGFloat?
        if let depthResult = depth {
            currentCompressionIndex = CGFloat(depthResult.compressionIndex)
            lastCompressionIndex = currentCompressionIndex  // 캐시도 업데이트
        } else {
            // 🔧 캐시 사용하지 않음 - 현재 프레임에 depth 없으면 nil
            currentCompressionIndex = nil
        }



        // ✅ 무거운 연산을 백그라운드로 이동
        // 백그라운드에서 Gate System 평가 및 피드백 생성
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 🆕 v6: 키포인트 변환 (tuple → PoseKeypoint)
            let currentPoseKeypoints: [PoseKeypoint]? = poseResult?.keypoints.map { kp in
                PoseKeypoint(location: kp.point, confidence: kp.confidence)
            }
            let referencePoseKeypoints: [PoseKeypoint]? = reference.poseKeypoints?.map { kp in
                PoseKeypoint(location: kp.point, confidence: kp.confidence)
            }

            // 🚀 Optimization: Move Pose Comparison to Background
            var poseComparison: PoseComparisonResult? = nil
            if let refKeypoints = reference.poseKeypoints,
               let curKeypoints = poseResult?.keypoints,
               refKeypoints.count >= 133 && curKeypoints.count >= 133 {
                poseComparison = self.poseComparator.comparePoses(
                    referenceKeypoints: refKeypoints,
                    currentKeypoints: curKeypoints
                )
            }

            var stableFeedback: [FeedbackItem] = []
            var evaluation: GateEvaluation?
            var unifiedFeedback: UnifiedFeedback?

            // 🆕 SimpleRealTimeGuide 평가 (GateSystem 대체)
            let hasPersonDetected = currentBBox.height > 0.05  // 최소 5% 이상이면 인물 감지
            let simpleGuideResult = self.simpleRealTimeGuide.evaluate(
                currentKeypoints: currentPoseKeypoints ?? [],
                hasPersonDetected: hasPersonDetected,
                isFrontCamera: isFrontCamera,
                currentZoom: self.currentZoomFactor  // 🆕 줌 정보 전달
            )

            if let cached = self.cachedReference {
                // 🔧 DEBUG: Gate 평가 시작
                print("🚦 Gate 시스템 평가 시작 (cachedReference 존재)")

                // 🆕 35mm 환산 초점거리 계산
                let currentFocalLength = self.focalLengthEstimator.focalLengthFromZoom(self.currentZoomFactor)

                // 🆕 Adaptive Difficulty 적용
                self.gateSystem.difficultyMultiplier = self.frustrationMultiplier

                // 🆕 목표 줌과 현재 줌을 GateSystem에 전달
                self.gateSystem.targetZoomFactor = self.targetZoomFactor
                self.gateSystem.currentZoomFactor = self.currentZoomFactor

                // 🔥 무거운 연산: Gate System 평가 (백그라운드에서)
                evaluation = self.gateSystem.evaluate(
                    currentBBox: currentBBox,
                    referenceBBox: cached.bbox,
                    currentImageSize: currentImageSize,
                    referenceImageSize: cached.imageSize,
                    compressionIndex: currentCompressionIndex,
                    referenceCompressionIndex: cached.compressionIndex,
                    currentAspectRatio: currentAspectRatio,
                    referenceAspectRatio: reference.aspectRatio,
                    poseComparison: poseComparison,
                    isFrontCamera: isFrontCamera,
                    currentKeypoints: currentPoseKeypoints,
                    referenceKeypoints: referencePoseKeypoints,
                    currentFocalLength: currentFocalLength,
                    referenceFocalLength: self.referenceFocalLength
                )

                // 🔥 무거운 연산: UnifiedFeedback 생성 (백그라운드에서)
                if let eval = evaluation {
                    let targetZoomValue = self.referenceFocalLength.map {
                        CGFloat($0.focalLength35mm) / CGFloat(FocalLengthEstimator.iPhoneBaseFocalLength)
                    }

                    unifiedFeedback = UnifiedFeedbackGenerator.shared.generateUnifiedFeedback(
                        from: eval,
                        isFrontCamera: isFrontCamera,
                        currentZoom: self.currentZoomFactor,
                        targetZoom: targetZoomValue,
                        targetSubjectSize: cached.bbox.width * cached.bbox.height
                    )
                    
                    // 🆕 UI 표시용 Debug String (Gate 1 - Shot Type)
                    // 🆕 UI 표시용 Debug String (Gate 1 - Shot Type)
                    // (RealtimeAnalyzer.process 내에서 직접 할당)

                    // 🔍 DEBUG: Unified Feedback Generation
                    /*
                    if let unified = unifiedFeedback {
                         print("✨ Unified Feedback Generated: [\(unified.primaryAction.rawValue)] \(unified.mainMessage)")
                    }
                    */

                    // Gate System 피드백 생성
                    let gateFeedbacks = V15FeedbackGenerator.shared.generateFeedbackItems(from: eval)

                    // 히스테리시스 적용
                    for fb in gateFeedbacks {
                        self.feedbackHistory[fb.category, default: 0] += 1
                    }

                    // 히스테리시스 및 좌절 감지 (Adaptive Difficulty)
                    if eval.allPassed {
                        // 성공 시 난이도 및 타이머 리셋
                        self.frustrationMultiplier = 1.0
                        self.feedbackStartTimes.removeAll()
                    } else {
                        // 현재 주요 피드백 추적
                        let primary = eval.primaryFeedback
                        if self.feedbackStartTimes[primary] == nil {
                            self.feedbackStartTimes[primary] = Date()
                        } else if let startTime = self.feedbackStartTimes[primary], Date().timeIntervalSince(startTime) > self.frustrationThreshold {
                            // 5초 이상 동일 피드백 -> 난이도 완화
                            if self.frustrationMultiplier == 1.0 { // 아직 완화 안 된 상태면
                                print("😤 좌절 감지! 난이도 완화 (Thresholds relax 1.2x)")
                                self.frustrationMultiplier = 1.2
                            }
                        }
                    }

                    for category in gateFeedbacks.map({ $0.category }) {
                        if self.feedbackHistory[category]! >= self.historyThreshold {
                            if let fb = gateFeedbacks.first(where: { $0.category == category }) {
                                stableFeedback.append(fb)
                            }
                        }
                    }
                    
                    // 사라진 카테고리 초기화
                    let currentCategories = Set(gateFeedbacks.map { $0.category })
                    for category in self.feedbackHistory.keys {
                        if !currentCategories.contains(category) {
                            self.feedbackHistory[category] = 0
                            // 해결된 피드백의 타이머도 제거
                            // (정확히 매핑하기 어려우면 전체 리셋하지 않고 유지하다가 주요 피드백 변경 시 처리됨)
                        }
                    }

                    print("🎯 v1.5 Gate: \(eval.passedCount)/5 통과, 점수: \(String(format: "%.0f%%", Double(eval.overallScore) * 100))")
                }
            } else {
                // 🔧 DEBUG: cachedReference nil
                print("⏭️ Gate 평가 스킵: cachedReference nil (레퍼런스 캐시 대기 중)")
            }

            // 완벽 상태 감지 (Gate System 기준)
            let isCurrentlyPerfect = evaluation?.allPassed ?? false
            let score = evaluation.map { Double($0.overallScore) } ?? 0.0

            // 완료된 피드백 감지 (히스테리시스 적용)
            let currentFeedbackIds = Set(stableFeedback.map { $0.id })
            let disappeared = self.previousFeedbackIds.subtracting(currentFeedbackIds)

            var completedToAdd: [CompletedFeedback] = []

            // 사라진 피드백의 연속 횟수 추적
            for disappearedId in disappeared {
                self.disappearedFeedbackHistory[disappearedId, default: 0] += 1

                // 5번 연속 사라지면 완료로 판단
                if self.disappearedFeedbackHistory[disappearedId]! >= self.disappearedThreshold {
                    if let completedItem = self.instantFeedback.first(where: { $0.id == disappearedId }) {
                        let completed = CompletedFeedback(item: completedItem, completedAt: Date())
                        completedToAdd.append(completed)
                    }
                    // 완료 처리 후 히스토리 초기화
                    self.disappearedFeedbackHistory[disappearedId] = 0
                }
            }

            // 다시 나타난 피드백은 히스토리 초기화
            for (feedbackId, _) in self.disappearedFeedbackHistory {
                if currentFeedbackIds.contains(feedbackId) {
                    self.disappearedFeedbackHistory[feedbackId] = 0
                }
            }

            // 카테고리별 상태 계산
            let categoryStatuses = self.calculateCategoryStatuses(from: stableFeedback)

            // 메인 스레드로 UI 업데이트만 전달
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                var newState = self.state

                // ✅ Phase 1 최적화: 조건 없이 할당 (Equatable이 마지막에 비교)
                if let eval = evaluation {
                    newState.gateEvaluation = eval
                    newState.v15Feedback = eval.primaryFeedback
                    // 🆕 샷타입 디버그 정보 전달
                    newState.currentShotDebugInfo = eval.gate1.debugInfo

                    // 🔍 디버그: UI로 전달되는 값 확인
                    print("🔍 [RealtimeAnalyzer] currentShotDebugInfo 설정: \(eval.gate1.debugInfo ?? "nil")")
                }

                if let unified = unifiedFeedback {
                    newState.unifiedFeedback = unified
                }

                // 🆕 SimpleRealTimeGuide 결과 설정
                newState.simpleGuide = simpleGuideResult

                // 🆕 ActiveFeedback 관리 (안정적인 피드백 표시)
                newState.activeFeedback = self.updateActiveFeedback(
                    currentActive: newState.activeFeedback,
                    newEvaluation: evaluation,
                    newUnified: unifiedFeedback
                )

                newState.instantFeedback = stableFeedback
                newState.perfectScore = score  // 조건 제거 (Equatable이 알아서 비교)
                newState.categoryStatuses = categoryStatuses

                // 🆕 Phase 2: Temporal Lock Logic (State Machine)
                var currentProgress: Float = 0.0

                // 🆕 SimpleGuide 기반 완벽 상태 판단 (GateSystem 대체)
                let isSimpleGuidePerfect = simpleGuideResult.guide == .perfect

                if isSimpleGuidePerfect {
                    switch self.stabilityState {
                    case .idle:
                        // 이제 막 완벽해짐 -> 타이머 시작
                        self.stabilityState = .arming(startedAt: Date())
                        currentProgress = 0.0
                        
                    case .arming(let startedAt):
                        // 유지 중 -> 시간 계산
                        let elapsed = Date().timeIntervalSince(startedAt)
                        currentProgress = Float(min(elapsed / self.lockDuration, 1.0))
                        
                        if elapsed >= self.lockDuration {
                            self.stabilityState = .locked
                            currentProgress = 1.0
                            // 📳 Haptic Logic could go here (Triggered once)
                        }
                        
                    case .locked:
                        // 이미 잠김 -> 유지
                        currentProgress = 1.0
                    }
                } else {
                    // 조건 깨짐 -> 즉시 리셋
                    self.stabilityState = .idle
                    currentProgress = 0.0
                }

                newState.stabilityProgress = currentProgress
                newState.isPerfect = (self.stabilityState == .locked)

                // 완료된 피드백: 변경사항이 있을 때만 업데이트
                var updatedCompletedFeedbacks = newState.completedFeedbacks
                
                // 1. 새로 완료된 항목 추가
                if !completedToAdd.isEmpty {
                    updatedCompletedFeedbacks.append(contentsOf: completedToAdd)
                }
                
                // 2. 만약 현재 다시 발생한 피드백이 있다면, 완료 목록에서 제거 (User Request: 다시 피드백 시작)
                // 현재 활성 피드백 ID 목록
                let activeIds = Set(stableFeedback.map { $0.id })
                if !activeIds.isEmpty {
                    updatedCompletedFeedbacks.removeAll { completed in
                        // 완료된 항목의 ID가 현재 활성 목록에 있다면 제거 (다시 문제 발생)
                       activeIds.contains(completed.item.id)
                    }
                }
                
                updatedCompletedFeedbacks.removeAll { !$0.shouldDisplay }
                newState.completedFeedbacks = updatedCompletedFeedbacks

                // 이전 피드백 업데이트 (Internal state, not published)
                self.previousFeedbackIds = currentFeedbackIds

                // ✅ Final State Update: Equatable 한 번만 비교
                if self.state != newState {
                    self.state = newState
                }
            }
        }
    }

    // MARK: - 🆕 Active Feedback Management (안정적인 피드백 표시)

    /// ActiveFeedback 업데이트 - 동일 피드백은 진행률만, 다른 피드백은 최소 시간 후 교체
    private func updateActiveFeedback(
        currentActive: ActiveFeedback?,
        newEvaluation: GateEvaluation?,
        newUnified: UnifiedFeedback?
    ) -> ActiveFeedback? {
        guard let eval = newEvaluation else {
            // 평가 결과 없음 → 활성 피드백 유지 (해결 중일 수 있음)
            if var active = currentActive, active.shouldRemove {
                return nil  // 페이드아웃 완료
            }
            return currentActive
        }

        // 모든 Gate 통과 → 해결 처리
        if eval.allPassed {
            if var active = currentActive {
                if !active.isResolved {
                    active.updateProgress(1.0)  // 100%로 설정
                }
                if active.shouldRemove {
                    return nil  // 페이드아웃 완료
                }
                return active
            }
            return nil
        }

        // 현재 실패한 Gate 정보 (없으면 모두 통과)
        guard let newGateIndex = eval.currentFailedGate else {
            // 모두 통과했지만 allPassed 조건에서 안 걸린 경우
            return currentActive
        }

        let newFeedbackType = extractFeedbackType(from: newUnified, gateIndex: newGateIndex)
        let newMessage = newUnified?.mainMessage ?? eval.primaryFeedback
        let newProgress = calculateProgress(for: eval, gateIndex: newGateIndex)

        // 현재 활성 피드백이 없으면 새로 생성
        guard var active = currentActive else {
            return ActiveFeedback(
                gateIndex: newGateIndex,
                feedbackType: newFeedbackType,
                message: newMessage,
                initialProgress: newProgress
            )
        }

        // 같은 피드백이면 진행률만 업데이트
        if active.gateIndex == newGateIndex && active.feedbackType == newFeedbackType {
            active.updateProgress(newProgress)
            return active
        }

        // 다른 피드백이지만 최소 표시 시간이 안 지났으면 유지
        if !active.hasMinDisplayTimePassed && !active.isResolved {
            // 기존 피드백 진행률은 유지하되 내부적으로 새 피드백 추적
            return active
        }

        // 새 피드백으로 교체
        return ActiveFeedback(
            gateIndex: newGateIndex,
            feedbackType: newFeedbackType,
            message: newMessage,
            initialProgress: newProgress
        )
    }

    /// UnifiedFeedback 또는 gateIndex에서 피드백 타입 추출
    private func extractFeedbackType(from unified: UnifiedFeedback?, gateIndex: Int) -> String {
        if let unified = unified {
            return unified.primaryAction.rawValue
        }
        // Gate별 기본 타입
        switch gateIndex {
        case 0: return "aspect_ratio"
        case 1: return "framing"
        case 2: return "position"
        case 3: return "compression"
        case 4: return "pose"
        default: return "unknown"
        }
    }

    /// Gate별 진행률 계산 (0.0 ~ 1.0) - GateResult.score 기반
    private func calculateProgress(for eval: GateEvaluation, gateIndex: Int) -> CGFloat {
        // 각 Gate의 score를 직접 사용 (0.0 ~ 1.0)
        switch gateIndex {
        case 0: return eval.gate0.score
        case 1: return eval.gate1.score
        case 2: return eval.gate2.score
        case 3: return eval.gate3.score
        case 4: return eval.gate4.score
        default: return 0.0
        }
    }

    // MARK: - Category Status Calculation

    /// 카테고리별 상태 계산
    private func calculateCategoryStatuses(from feedbacks: [FeedbackItem]) -> [CategoryStatus] {
        // 모든 카테고리에 대해 상태 생성
        var statusMap: [FeedbackCategory: CategoryStatus] = [:]

        // 각 카테고리 초기화 (모두 만족 상태로 시작)
        for category in FeedbackCategory.allCases {
            statusMap[category] = CategoryStatus(
                category: category,
                isSatisfied: true,
                activeFeedbacks: []
            )
        }

        // 피드백이 있는 카테고리는 불만족 상태로 변경
        for feedback in feedbacks {
            if let category = FeedbackCategory.from(categoryString: feedback.category) {
                var activeFeedbacks = statusMap[category]?.activeFeedbacks ?? []
                activeFeedbacks.append(feedback)

                statusMap[category] = CategoryStatus(
                    category: category,
                    isSatisfied: false,
                    activeFeedbacks: activeFeedbacks.sorted { $0.priority < $1.priority }
                )
            }
        }

        // 우선순위 순서로 정렬하여 반환
        return Array(statusMap.values).sorted { $0.priority < $1.priority }
    }

    // MARK: - 디버그 헬퍼
    private func saveDebugImage(_ image: UIImage, reason: String) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }

        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            .replacingOccurrences(of: ":", with: "-")
        let filename = "debug_\(reason)_\(timestamp).jpg"

        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = documentsPath.appendingPathComponent(filename)
            try? data.write(to: fileURL)
            print("🔍 디버그 이미지 저장: \(fileURL.path)")
        }
    }
}
