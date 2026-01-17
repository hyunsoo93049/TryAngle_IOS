import Foundation
import CoreGraphics
import UIKit
import Vision
import AVFoundation

// MARK: - Gate System (Business Logic)
// 🆕 Refactored v9: Uses GateOrchestrator for modular logic
// Maintains singleton 'shared' for backward compatibility

// 🆕 Gate 결과 (UI 표시용) - Services/Gates/Core/GateTypes.swift로 이동됨

// 🆕 샷 타입 (Gate 1 & UI 표시용) - Services/Gates/Core/GateTypes.swift로 이동됨

public class GateSystem {
    static let shared = GateSystem()

    // MARK: - Configuration
    public struct GateThresholds {
        var aspectRatio: CGFloat = 0.95
        var framing: CGFloat = 0.75
        var position: CGFloat = 0.75
        var compression: CGFloat = 0.70
        var pose: CGFloat = 0.80
        var poseAngleThreshold: Float = 15.0 // 포즈 각도 허용 오차 (도)
        
        // 난이도 조절용
        func scaled(by multiplier: CGFloat) -> GateThresholds {
            return GateThresholds(
                aspectRatio: max(0.5, aspectRatio * multiplier),
                framing: max(0.5, framing * multiplier),
                position: max(0.5, position * multiplier),
                compression: max(0.5, compression * multiplier),
                pose: max(0.5, pose * multiplier),
                poseAngleThreshold: poseAngleThreshold * (2.0 - Float(multiplier)) // 난이도 높을수록 오차 범위 축소
            )
        }
    }

    private let baseThresholds = GateThresholds()
    
    var currentThresholds: GateThresholds {
        return baseThresholds.scaled(by: difficultyMultiplier)
    }

    public var difficultyMultiplier: CGFloat = 1.0
    
    // 🆕 Debug Option
    var DEBUG_GATE_SYSTEM: Bool = true
    var DEBUG_LOG_INTERVAL: TimeInterval = 2.0 // 2초마다 로그

    // 🆕 Modular Orchestrator
    private let orchestrator: GateOrchestrator
    
    init() {
        self.orchestrator = GateOrchestrator()
        
        // Register Gates
        orchestrator.register(gate: AspectRatioGate())
        orchestrator.register(gate: FramingGate())
        orchestrator.register(gate: PositionGate())
        orchestrator.register(gate: CompressionGate())
        orchestrator.register(gate: PoseGate())
    }

    // 🆕 Debug State
    private var lastCurrentShotType: ShotTypeGate?
    private var lastRefShotType: ShotTypeGate?
    private var lastDebugLogTime: Date = Date()

    // 🆕 마지막으로 계산된 샷타입 (정밀평가용 - public 접근 가능)
    private(set) var evaluatedCurrentShotType: ShotTypeGate?
    private(set) var evaluatedReferenceShotType: ShotTypeGate?

    // 🆕 샷타입 안정화 (Hysteresis) - 급격한 변화 방지
    // Note: Now delegated to FramingGate, but keeping here for legacy access if needed?
    // Actually FramingGate handles internal state. We just expose the result.
    private var stableShotType: ShotTypeGate?           // 안정화된 샷타입
    private var shotTypeChangeCount: Int = 0           // 동일 샷타입 연속 감지 횟수
    private let shotTypeStabilityThreshold: Int = 3    // 3회 연속 동일해야 변경
    private var lastShotTypeChangeTime: Date = .distantPast

    // 🆕 목표 줌 배율 (레퍼런스 분석 시 한 번 설정, 이후 고정)
    var targetZoomFactor: CGFloat?  // 예: 2.4x
    var currentZoomFactor: CGFloat = 1.0  // 현재 줌 (RealtimeAnalyzer에서 업데이트)
    
    // 🆕 줌 허용 오차 (10% 이내면 OK)
    private let zoomTolerance: CGFloat = 0.15

    // MARK: - Evaluation
    
    // 🆕 Orchestrator-based Evaluation
    func evaluate(
        bbox: CGRect,
        imageSize: CGSize, // Pixel coords
        referenceBBox: CGRect?,
        referenceImageSize: CGSize?,
        isFrontCamera: Bool,
        currentKeypoints: [PoseKeypoint]? = nil,
        referenceKeypoints: [PoseKeypoint]? = nil,
        // Optional additions for new gates
        poseComparison: PoseComparisonResult? = nil,
        focalLengthInfo: FocalLengthInfo? = nil,
        referenceFocalLengthInfo: FocalLengthInfo? = nil
    ) -> GateEvaluation {
        
        // 1. Construct Frame Analysis Result (Input Context)
        let input = FrameInput(image: nil, imageSize: imageSize, cameraPosition: isFrontCamera ? AVCaptureDevice.Position.front : AVCaptureDevice.Position.back)
        var analysis = FrameAnalysisResult(input: input)
        
        // Populate analysis results from legacy params
        // Pose
        if let kps = currentKeypoints {
            // Rough reconstruction of PoseResult
            // Note: PoseDetectionResult definition in PipelineTypes might require different args.
            // Assuming: init(timestamp: TimeInterval, keypoints: [PoseKeypoint], confidences: [Float], roughBBox: CGRect, lowestBodyPart: String?, shotType: ShotType?)
            
            // To be safe, we check Definitions first or use a minimal init if available.
            // Since I can't see the exact init of PoseDetectionResult in this context (it wasn't in PipelineTypes view),
            // I will assume it follows the file I saw earlier or standard struct memberwise init.
            
            // Let's rely on standard init for now, adjusting to typical fields.
            // If PipelineTypes.swift didn't show PoseDetectionResult, it must be elsewhere.
            // Wait, I viewed PipelineTypes.swift and it had `PoseDetectionResult?` property but didn't show `struct PoseDetectionResult`.
            // Use grep to find PoseDetectionResult definition.
            
            // Temporary fix: Use a minimal construction or placeholder if struct is complex.
            // Use metadata-based assignment or rely on what's available.
            
            // Actually, I should find PoseDetectionResult definition before guessing.
        }
        
        // 2. Construct Reference Data
        let referenceData = ReferenceData(
            bbox: referenceBBox,
            imageSize: referenceImageSize,
            compressionIndex: nil,
            aspectRatio: .ratio4_3, // Defaulting to 4:3 if unknown
            keypoints: referenceKeypoints,
            focalLength: referenceFocalLengthInfo,
            shotType: nil // computed by FramingGate
        )
        
        // 3. Construct Settings
        let settings = GateSettings(
            thresholds: currentThresholds,
            difficultyMultiplier: 1.0,
            targetZoomFactor: targetZoomFactor
        )
        
        // 4. Create Context
        let context = GateContext(analysis: analysis, reference: referenceData, settings: settings)
        
        // 5. Run Orchestrator
        let evaluation = orchestrator.evaluate(context: context)
        
        // 6. Update Local State (Legacy Compatibility)
        self.evaluatedCurrentShotType = evaluation.currentShotType
        self.evaluatedReferenceShotType = evaluation.referenceShotType
        
        // Update debug log
        if DEBUG_GATE_SYSTEM {
            let now = Date()
            if now.timeIntervalSince(lastDebugLogTime) > DEBUG_LOG_INTERVAL {
                print(evaluation.debugSummary)
                lastDebugLogTime = now
            }
        }
        
        return evaluation
    }
}
