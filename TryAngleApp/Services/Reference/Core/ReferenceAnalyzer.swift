import Foundation
import UIKit

// MARK: - Reference Analyzer
// 역할: 등록된 모듈들을 순서대로 실행하고 결과를 취합하는 관리자(오케스트레이터)입니다.
//       콘센트처럼 모듈들을 꽂으면 알아서 실행해주는 역할을 합니다.

class ReferenceAnalyzer {

    // MARK: - Singleton
    static let shared = ReferenceAnalyzer()

    // MARK: - Properties

    /// 등록된 모듈들 (우선순위 순으로 정렬됨)
    private var modules: [ReferenceAnalysisModule] = []

    /// 기존 DetectionPipeline 재사용 (Pose, Depth, Segmentation)
    private let pipeline: DetectionPipeline

    /// 디버그 모드
    var debugMode: Bool = true

    // MARK: - Initialization

    init(pipeline: DetectionPipeline = DetectionPipeline()) {
        self.pipeline = pipeline
    }

    // MARK: - Module Registration

    /// 모듈 등록
    func register(module: ReferenceAnalysisModule) {
        modules.append(module)
        modules.sort { $0.priority < $1.priority }

        if debugMode {
            print("📦 ReferenceAnalyzer: '\(module.name)' 모듈 등록됨 (priority: \(module.priority))")
        }
    }

    /// 여러 모듈 한번에 등록
    func register(modules: [ReferenceAnalysisModule]) {
        modules.forEach { register(module: $0) }
    }

    /// 모듈 초기화 (기본 모듈들 등록)
    func setupDefaultModules() {
        register(modules: [
            EXIFModule(),        // priority 0: EXIF 메타데이터
            DepthModule(),       // priority 5: 깊이/압축감
            FramingModule(),     // priority 10: 샷타입/프레이밍
            BBoxModule(),        // priority 15: 정밀 바운딩박스
            CompositionModule()  // priority 20: 구도 타입
        ])

        // 🔧 FIX: Pipeline 모듈 즉시 초기화 (비동기 제거 - race condition 방지)
        // analyze()가 호출되기 전에 poseDetector가 설정되어야 함
        initializePipelineSync()
    }

    /// 🔧 동기식 파이프라인 초기화 (race condition 방지)
    private func initializePipelineSync() {
        // 🔥 싱글톤 사용 (메모리 절약 - 새 인스턴스 생성하면 모델이 중복 로드됨!)
        let poseService = RTMPoseService.shared
        let depthService = DepthService.shared

        // 동기적으로 등록 (모델 초기화는 각 서비스에서 이미 처리됨)
        pipeline.poseDetector = poseService
        pipeline.depthEstimator = depthService

        print("✅ ReferenceAnalyzer: Pipeline 즉시 초기화 완료 (poseDetector: \(pipeline.poseDetector != nil), depthEstimator: \(pipeline.depthEstimator != nil))")
    }

    // MARK: - Analysis

    /// 레퍼런스 이미지 분석 (메인 진입점)
    func analyze(image: UIImage, imageData: Data? = nil) async -> ReferenceAnalysisResult {
        let startTime = Date()
        let input = ReferenceInput(image: image, imageData: imageData)

        if debugMode {
            print("🎯 레퍼런스 분석 시작...")
            print("   - 이미지 크기: \(Int(input.imageSize.width))x\(Int(input.imageSize.height))")
            print("   - 등록된 모듈: \(modules.map { $0.name }.joined(separator: ", "))")
        }

        // 1. Context 초기화
        var context = ReferenceContext()

        // 2. DetectionPipeline으로 기본 분석 (Pose, Depth)
        await runPipeline(input: input, context: &context)

        // 3. 등록된 모듈들 순차 실행
        for module in modules {
            do {
                let moduleStart = Date()
                try await module.analyze(input: input, context: &context)

                if debugMode {
                    let elapsed = Date().timeIntervalSince(moduleStart) * 1000
                    print("   ✅ \(module.name): \(String(format: "%.1fms", elapsed))")
                }
            } catch {
                if debugMode {
                    print("   ❌ \(module.name): \(error.localizedDescription)")
                }
            }
        }

        // 4. 최종 결과 생성
        let result = ReferenceAnalysisResult(input: input, context: context)

        if debugMode {
            let totalTime = Date().timeIntervalSince(startTime) * 1000
            print("🏁 레퍼런스 분석 완료: \(String(format: "%.0fms", totalTime))")
            print("   \(result.debugSummary)")
        }

        return result
    }

    // MARK: - Pipeline Execution

    private func runPipeline(input: ReferenceInput, context: inout ReferenceContext) async {
        // FrameInput 생성
        let frameInput = FrameInput(
            image: input.image,
            timestamp: Date().timeIntervalSince1970,
            cameraPosition: input.cameraPosition
        )

        // Pipeline을 동기적으로 실행 (단일 이미지용)
        // 기존 pipeline.process()는 비동기 스트림용이므로, 직접 모듈 호출

        // Pose 분석
        if let poseDetector = pipeline.poseDetector {
            if debugMode {
                print("   🔍 Pose 분석 시작 (poseDetector: \(type(of: poseDetector)))")
            }
            do {
                context.poseResult = try await poseDetector.detect(input: frameInput)
                if debugMode {
                    if let pose = context.poseResult {
                        print("   ✅ Pose 분석 성공: \(pose.keypoints.count)개 키포인트")
                    } else {
                        print("   ⚠️ Pose 분석 결과 nil (인물 미검출?)")
                    }
                }
            } catch {
                if debugMode {
                    print("   ❌ Pose 분석 실패: \(error.localizedDescription)")
                }
            }
        } else {
            if debugMode {
                print("   ❌ poseDetector가 nil입니다! (pipeline 초기화 실패)")
            }
        }

        // Depth 분석
        if let depthEstimator = pipeline.depthEstimator {
            do {
                context.depthResult = try await depthEstimator.estimate(input: frameInput)
            } catch {
                if debugMode {
                    print("   ⚠️ Depth 분석 실패: \(error.localizedDescription)")
                }
            }
        }
    }
}
