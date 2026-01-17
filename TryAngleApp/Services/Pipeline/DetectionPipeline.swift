import Foundation
import Combine
import AVFoundation
import UIKit

// MARK: - Pipeline Orchestrator

/// 감지 파이프라인 관리자
/// 카메라 프레임 입력을 받아 활성화된 모듈들의 분석을 병렬/직렬로 실행하고 결과를 집계합니다.
public class DetectionPipeline: ObservableObject {

    // MARK: - Modules
    public var poseDetector: PoseDetector?
    public var depthEstimator: DepthEstimator?
    public var subjectSegmentor: SubjectSegmentor?
    public var compositionAnalyzer: CompositionAnalyzer?

    // MARK: - State
    @Published public var isProcessing: Bool = false

    // 분석 결과 스트림
    private let resultSubject = PassthroughSubject<FrameAnalysisResult, Never>()
    public var resultPublisher: AnyPublisher<FrameAnalysisResult, Never> {
        resultSubject.eraseToAnyPublisher()
    }

    // MARK: - 🔥 병렬 처리를 위한 분리된 큐
    /// NPU 우선 작업 (YOLO, 가벼운 모델)
    private let npuQueue = DispatchQueue(label: "com.tryangle.pipeline.npu", qos: .userInteractive)
    /// CPU 부하 작업 (RTMPose의 일부, Depth의 일부)
    private let cpuQueue = DispatchQueue(label: "com.tryangle.pipeline.cpu", qos: .userInitiated)

    // MARK: - 🔥 프레임 간격 조절 (모델별 실행 빈도)
    private var frameCount: Int = 0

    /// 모델별 실행 간격 (프레임 단위)
    public struct FrameIntervals {
        var pose: Int = 1       // 매 프레임 (중요)
        var depth: Int = 10     // 10프레임마다 (느리게 변함)
        var segmentation: Int = 5  // 5프레임마다
    }
    public var intervals = FrameIntervals()

    // MARK: - 🔥 캐시된 결과 (스킵된 프레임용)
    private var cachedPoseResult: PoseDetectionResult?
    private var cachedDepthResult: DepthEstimationResult?
    private var cachedSegmentationResult: SegmentationResult?

    public init() {}
    
    // MARK: - Configuration
    
    /// 모듈 등록
    public func register(pose: PoseDetector?, depth: DepthEstimator?, segmentation: SubjectSegmentor?, composition: CompositionAnalyzer?) {
        self.poseDetector = pose
        self.depthEstimator = depth
        self.subjectSegmentor = segmentation
        self.compositionAnalyzer = composition
        
        Task {
            await initializeModules()
        }
    }
    
    private func initializeModules() async {
        do {
            try await poseDetector?.initialize()
            try await depthEstimator?.initialize()
            try await subjectSegmentor?.initialize()
            try await compositionAnalyzer?.initialize()
            print("✅ All detection modules initialized.")
        } catch {
            print("❌ Module initialization failed: \(error)")
        }
    }
    
    // MARK: - Execution
    
    // 🔥 스레드 안전한 처리 플래그 (atomic)
    private var _isProcessingInternal = false
    private let processingLock = NSLock()

    /// 프레임 처리 (입력 진입점)
    public func process(input: FrameInput) {
        // 🔥 락으로 동시 접근 방지 (메인 스레드 블로킹 없음)
        processingLock.lock()
        guard !_isProcessingInternal else {
            processingLock.unlock()
            return
        }
        _isProcessingInternal = true
        processingLock.unlock()

        // @Published는 메인 스레드에서 업데이트
        DispatchQueue.main.async { [weak self] in
            self?.isProcessing = true
        }

        Task {
            let result = await executePipeline(input: input)

            // 메인 스레드나 적절한 곳에서 결과 방출
            resultSubject.send(result)

            // 🔥 내부 플래그 먼저 해제 (다음 프레임 처리 허용)
            processingLock.lock()
            _isProcessingInternal = false
            processingLock.unlock()

            // @Published는 메인 스레드에서 업데이트
            DispatchQueue.main.async { [weak self] in
                self?.isProcessing = false
            }
        }
    }
    
    /// 🔥 실제 파이프라인 실행 로직 (완전 병렬화)
    private func executePipeline(input: FrameInput) async -> FrameAnalysisResult {
        frameCount += 1
        var result = FrameAnalysisResult(input: input)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // 🔥 모든 독립 작업을 동시에 시작 (완전 병렬)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // 1. Pose: 매 프레임 실행 (가장 중요)
        let shouldRunPose = frameCount % intervals.pose == 0
        async let poseTask: PoseDetectionResult? = shouldRunPose && poseDetector?.isEnabled == true
            ? runPoseDetection(input: input)
            : nil

        // 2. Depth: N프레임마다 실행 (느리게 변함)
        let shouldRunDepth = frameCount % intervals.depth == 0
        async let depthTask: DepthEstimationResult? = shouldRunDepth && depthEstimator?.isEnabled == true
            ? runDepthEstimation(input: input)
            : nil

        // 3. Segmentation: N프레임마다 실행
        let shouldRunSeg = frameCount % intervals.segmentation == 0
        async let segTask: SegmentationResult? = shouldRunSeg && subjectSegmentor?.isEnabled == true
            ? runSegmentation(input: input)
            : nil

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // 🔥 모든 병렬 작업 완료 대기
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        let (poseResult, depthResult, segResult) = await (poseTask, depthTask, segTask)

        // 새 결과가 있으면 캐시 업데이트, 없으면 캐시 사용
        if let pose = poseResult {
            cachedPoseResult = pose
        }
        result.poseResult = cachedPoseResult

        if let depth = depthResult {
            cachedDepthResult = depth
        }
        result.depthResult = cachedDepthResult

        if let seg = segResult {
            cachedSegmentationResult = seg
        }
        result.segmentationResult = cachedSegmentationResult

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // 4. Composition: 의존성 있음 (Pose, Depth 결과 필요)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        if compositionAnalyzer?.isEnabled == true {
            do {
                result.compositionResult = try await compositionAnalyzer?.analyze(
                    input: input,
                    pose: result.poseResult,
                    depth: result.depthResult
                )
            } catch {
                print("⚠️ Composition Analysis Warning: \(error)")
            }
        }

        return result
    }

    // MARK: - 🔥 개별 모듈 실행 (에러 처리 포함)

    private func runPoseDetection(input: FrameInput) async -> PoseDetectionResult? {
        do {
            return try await poseDetector?.detect(input: input)
        } catch {
            print("⚠️ Pose Detection Error: \(error.localizedDescription)")
            return nil
        }
    }

    private func runDepthEstimation(input: FrameInput) async -> DepthEstimationResult? {
        do {
            return try await depthEstimator?.estimate(input: input)
        } catch {
            print("⚠️ Depth Estimation Error: \(error.localizedDescription)")
            return nil
        }
    }

    private func runSegmentation(input: FrameInput) async -> SegmentationResult? {
        do {
            return try await subjectSegmentor?.segment(input: input)
        } catch {
            print("⚠️ Segmentation Error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 🔥 발열 상태에 따른 동적 간격 조절

    public func adjustIntervalsForThermalState(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal:
            intervals = FrameIntervals(pose: 1, depth: 10, segmentation: 5)
        case .fair:
            intervals = FrameIntervals(pose: 2, depth: 15, segmentation: 8)
        case .serious:
            intervals = FrameIntervals(pose: 3, depth: 20, segmentation: 10)
        case .critical:
            intervals = FrameIntervals(pose: 5, depth: 30, segmentation: 15)
        @unknown default:
            intervals = FrameIntervals(pose: 2, depth: 15, segmentation: 8)
        }
        print("🌡️ 발열 상태 변경 → 간격 조절: pose=\(intervals.pose), depth=\(intervals.depth), seg=\(intervals.segmentation)")
    }

    // MARK: - 캐시 초기화

    public func clearCache() {
        cachedPoseResult = nil
        cachedDepthResult = nil
        cachedSegmentationResult = nil
        frameCount = 0
    }
}
