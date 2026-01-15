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
    
    // 처리 큐 (비동기 작업용)
    private let processingQueue = DispatchQueue(label: "com.tryangle.pipeline.processing", qos: .userInitiated)
    
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
    
    /// 프레임 처리 (입력 진입점)
    public func process(input: FrameInput) {
        guard !isProcessing else { return } // 드롭 프레임 (이전 처리 중이면 스킵)
        
        isProcessing = true
        
        Task {
            let result = await executePipeline(input: input)
            
            // 메인 스레드나 적절한 곳에서 결과 방출
            // UI 업데이트 등을 위해 메인에서 받을 수 있도록 함 (구독자 측에서 receive(on:) 처리 권장하지만 여기서도 배려 가능)
            resultSubject.send(result)
            
            DispatchQueue.main.async { [weak self] in
                self?.isProcessing = false
            }
        }
    }
    
    /// 실제 파이프라인 실행 로직
    private func executePipeline(input: FrameInput) async -> FrameAnalysisResult {
        var result = FrameAnalysisResult(input: input)
        
        // 1. Pose & Segmentation (Parallel)
        // 포즈와 세그멘테이션은 서로 의존성이 없으므로 병렬 실행 가능
        // (단, 기기 발열이나 리소스에 따라 직렬로 변경 가능성 있음)
        async let poseTask = poseDetector?.isEnabled == true ? poseDetector?.detect(input: input) : nil
        async let segTask = subjectSegmentor?.isEnabled == true ? subjectSegmentor?.segment(input: input) : nil
        
        do {
            let (pose, seg) = await (try poseTask, try segTask)
            result.poseResult = pose
            result.segmentationResult = seg
        } catch {
            print("⚠️ Detection Warning: Parallel tasks specific error: \(error)")
        }
        
        // 2. Depth (Requires Lens info? No, separate)
        // Depth도 독립적일 수 있으나 발열 관리를 위해 순차 실행을 고려할 수 있음.
        // 현재는 편의상 독립 실행.
        if depthEstimator?.isEnabled == true {
            do {
                result.depthResult = try await depthEstimator?.estimate(input: input)
            } catch {
                print("⚠️ Depth Estimation Warning: \(error)")
            }
        }
        
        // 3. Composition (Depends on Pose & Depth & Segmentation)
        // 구도 분석은 객체 위치(Pose)나 배경 분리(Seg), 심도(Depth) 정보를 종합해서 판단할 수 있음.
        if compositionAnalyzer?.isEnabled == true {
            do {
                result.compositionResult = try await compositionAnalyzer?.analyze(input: input, pose: result.poseResult, depth: result.depthResult)
            } catch {
                print("⚠️ Composition Analysis Warning: \(error)")
            }
        }
        
        return result
    }
}
