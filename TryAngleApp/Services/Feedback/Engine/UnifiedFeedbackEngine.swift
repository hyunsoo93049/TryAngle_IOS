import Foundation
import CoreGraphics
import AVFoundation

// MARK: - Unified Feedback Engine
// 역할: GateSystem + SimpleRealTimeGuide를 하나로 통합
// - 기술적 평가 (GateEvaluation)
// - 사용자 친화적 가이드 (SimpleGuideResult)
// - 히스테리시스 (안정화) 내장

final class UnifiedFeedbackEngine {

    // MARK: - Singleton
    static let shared = UnifiedFeedbackEngine()

    // MARK: - Configuration
    struct Config {
        var aspectRatioTolerance: CGFloat = 0.0   // 비율은 정확히 일치
        var sizeTolerance: CGFloat = 0.20         // 크기 20% 오차
        var positionToleranceX: CGFloat = 0.08    // 좌우 8% 오차
        var positionToleranceY: CGFloat = 0.08    // 상하 8% 오차
        var zoomTolerance: CGFloat = 0.15         // 줌 15% 오차
        var poseThreshold: CGFloat = 0.70         // 포즈 70% 일치
        var minPersonHeight: CGFloat = 0.05       // 최소 인물 높이 5%

        init() {}
    }

    private var config = Config()

    // MARK: - Reference Data (캐시)
    private var referenceKeypoints: [PoseKeypoint]?
    private var referencePersonHeight: CGFloat = 0
    private var referenceCenterX: CGFloat = 0.5
    private var referenceCenterY: CGFloat = 0.5
    private var referenceShotType: ShotTypeGate = .mediumShot
    private var referenceZoomFactor: CGFloat?
    private var referenceAspectRatio: CameraAspectRatio = .ratio4_3
    private var referenceImageSize: CGSize = .zero

    // MARK: - Hysteresis (안정화)
    private var lastGuide: GuideType = .enterFrame
    private var lastGuideTime: Date = .distantPast
    private var sameGuideCount: Int = 0
    private let stabilityThreshold: Int = 2              // 2번 연속 같아야 변경

    // Shot type hysteresis
    private var stableShotType: ShotTypeGate?
    private var shotTypeChangeCount: Int = 0
    private let shotTypeStabilityThreshold: Int = 3      // 3회 연속 동일해야 변경

    // MARK: - Debug
    private var lastDebugLogTime: Date = .distantPast
    private let debugLogInterval: TimeInterval = 2.0

    // MARK: - Initialization

    private init() {}

    // MARK: - Configuration

    func configure(_ config: Config) {
        self.config = config
    }

    // MARK: - Reference Management

    /// 레퍼런스 설정 (키포인트 기반)
    func setReference(
        keypoints: [PoseKeypoint],
        imageSize: CGSize,
        aspectRatio: CameraAspectRatio,
        zoomFactor: CGFloat? = nil
    ) {
        guard !keypoints.isEmpty else {
            print("[UnifiedEngine] 레퍼런스 키포인트 없음")
            return
        }

        self.referenceKeypoints = keypoints
        self.referenceZoomFactor = zoomFactor
        self.referenceAspectRatio = aspectRatio
        self.referenceImageSize = imageSize

        // BBox 계산
        if let bbox = ShotTypeGate.calculateKeypointBBox(keypoints) {
            referencePersonHeight = bbox.height
            referenceCenterX = bbox.midX
            referenceCenterY = bbox.midY
        }

        // Shot type 결정
        if keypoints.count >= 17 {
            referenceShotType = ShotTypeGate.fromKeypoints(keypoints)
        }

        // 히스테리시스 리셋
        resetHysteresis()

        print("[UnifiedEngine] 레퍼런스 설정: \(referenceShotType.displayName), 높이=\(String(format: "%.2f", referencePersonHeight))")
    }

    /// 레퍼런스 설정 (BBox 폴백)
    func setReferenceFallback(
        bbox: CGRect,
        imageSize: CGSize,
        aspectRatio: CameraAspectRatio,
        zoomFactor: CGFloat? = nil
    ) {
        self.referenceKeypoints = nil
        self.referenceZoomFactor = zoomFactor
        self.referenceAspectRatio = aspectRatio
        self.referenceImageSize = imageSize

        referencePersonHeight = bbox.height
        referenceCenterX = bbox.midX
        referenceCenterY = bbox.midY

        // Shot type 추정 (BBox 높이 기반)
        referenceShotType = ShotTypeGate.fromBBoxHeight(bbox.height)

        // 히스테리시스 리셋
        resetHysteresis()

        print("[UnifiedEngine] Fallback 레퍼런스: \(referenceShotType.displayName)")
    }

    /// 레퍼런스 클리어
    func clearReference() {
        referenceKeypoints = nil
        referencePersonHeight = 0
        referenceCenterX = 0.5
        referenceCenterY = 0.5
        referenceShotType = .mediumShot
        referenceZoomFactor = nil
        referenceImageSize = .zero

        resetHysteresis()
        print("[UnifiedEngine] 레퍼런스 초기화")
    }

    private func resetHysteresis() {
        lastGuide = .enterFrame
        lastGuideTime = .distantPast
        sameGuideCount = 0
        stableShotType = nil
        shotTypeChangeCount = 0
    }

    // MARK: - Main Evaluation

    /// 통합 평가 (SimpleGuideResult + GateEvaluation 동시 반환)
    func evaluate(
        currentKeypoints: [PoseKeypoint],
        hasPersonDetected: Bool,
        currentAspectRatio: CameraAspectRatio,
        currentZoom: CGFloat,
        isFrontCamera: Bool
    ) -> EvaluationResult {

        // 1. 레퍼런스 체크
        guard referencePersonHeight > 0 else {
            return createIdleResult(reason: "레퍼런스 미설정")
        }

        // 2. 비율 체크 (최우선)
        if currentAspectRatio != referenceAspectRatio {
            return createAspectRatioMismatchResult(
                current: currentAspectRatio,
                target: referenceAspectRatio
            )
        }

        // 3. 인물 감지 체크
        guard hasPersonDetected, !currentKeypoints.isEmpty else {
            return createFrameEntryResult(reason: "인물 미감지")
        }

        // 4. BBox 계산
        guard let currentBBox = ShotTypeGate.calculateKeypointBBox(currentKeypoints) else {
            return createFrameEntryResult(reason: "BBox 계산 실패")
        }

        // 5. 인물 크기 체크
        if currentBBox.height < config.minPersonHeight {
            return createFrameEntryResult(reason: "인물 너무 작음")
        }

        // 6. 샷타입 계산 (히스테리시스 적용)
        let rawShotType = currentKeypoints.count >= 17
            ? ShotTypeGate.fromKeypoints(currentKeypoints)
            : ShotTypeGate.fromBBoxHeight(currentBBox.height)

        let currentShotType = stabilizeShotType(rawShotType)

        // 7. 순차 평가 (SimpleGuide 방식)
        let guide = evaluateSequential(
            currentBBox: currentBBox,
            currentShotType: currentShotType,
            currentKeypoints: currentKeypoints,
            currentZoom: currentZoom,
            isFrontCamera: isFrontCamera
        )

        // 8. Gate 평가 (기술적 점수)
        let gateEval = evaluateGates(
            currentBBox: currentBBox,
            currentShotType: currentShotType,
            currentKeypoints: currentKeypoints,
            currentZoom: currentZoom,
            currentAspectRatio: currentAspectRatio
        )

        // 9. 히스테리시스 적용
        let stabilizedGuide = stabilizeGuide(guide)

        return EvaluationResult(
            simpleGuide: stabilizedGuide,
            gateEvaluation: gateEval,
            isPerfect: stabilizedGuide.guide == .perfect
        )
    }

    // MARK: - Sequential Evaluation (SimpleGuide 방식)

    private func evaluateSequential(
        currentBBox: CGRect,
        currentShotType: ShotTypeGate,
        currentKeypoints: [PoseKeypoint],
        currentZoom: CGFloat,
        isFrontCamera: Bool
    ) -> SimpleGuideResult {

        // Stage 1: 샷타입 맞추기
        let shotTypeDiff = currentShotType.rawValue - referenceShotType.rawValue
        let shotTypeMatch = currentShotType == referenceShotType

        if !shotTypeMatch {
            let magnitude = getMagnitudeFromShotTypeDistance(abs(shotTypeDiff))
            let guide: GuideType = shotTypeDiff < 0 ? .moveBackward : .moveForward
            let progress = 0.3 + CGFloat(1.0 - CGFloat(abs(shotTypeDiff)) / 7.0) * 0.3

            return SimpleGuideResult(
                guide: guide,
                magnitude: magnitude,
                progress: progress,
                debugInfo: "샷타입 \(currentShotType.displayName) → \(referenceShotType.displayName)",
                shotTypeMatch: false,
                currentShotType: currentShotType.displayName,
                targetShotType: referenceShotType.displayName,
                feedbackStage: .shotType
            )
        }

        // Stage 2: 위치 조정
        let currentCenterX = currentBBox.midX
        let currentCenterY = currentBBox.midY

        var diffX = currentCenterX - referenceCenterX
        if isFrontCamera { diffX = -diffX }
        let diffY = currentCenterY - referenceCenterY

        let positionScoreX = 1.0 - min(abs(diffX) / 0.5, 1.0)
        let positionScoreY = 1.0 - min(abs(diffY) / 0.5, 1.0)
        let positionScore = (positionScoreX + positionScoreY) / 2.0

        // 좌우 조정
        if abs(diffX) > config.positionToleranceX {
            let magnitude = getMagnitudePosition(diff: abs(diffX))
            let guide: GuideType = diffX > 0 ? .moveLeft : .moveRight
            let percent = min(50, Int(abs(diffX) * 100))

            return SimpleGuideResult(
                guide: guide,
                magnitude: magnitude,
                progress: 0.6 + positionScore * 0.2,
                debugInfo: "좌우 차이: \(String(format: "%.0f", diffX * 100))%",
                shotTypeMatch: true,
                currentShotType: currentShotType.displayName,
                targetShotType: referenceShotType.displayName,
                feedbackStage: .position,
                positionPercent: percent
            )
        }

        // 상하 조정
        if abs(diffY) > config.positionToleranceY {
            let guide: GuideType = diffY > 0 ? .tiltUp : .tiltDown
            let tiltAngle = toTiltAngle(percent: abs(diffY) * 100)

            return SimpleGuideResult(
                guide: guide,
                magnitude: "",
                progress: 0.6 + positionScore * 0.1,
                debugInfo: "상하 차이: \(String(format: "%.0f", diffY * 100))%",
                shotTypeMatch: true,
                currentShotType: currentShotType.displayName,
                targetShotType: referenceShotType.displayName,
                feedbackStage: .position,
                tiltAngle: tiltAngle
            )
        }

        // Stage 3: 크기 조정
        let sizeRatio = currentBBox.height / max(referencePersonHeight, 0.01)
        let sizeScore = 1.0 - min(abs(1.0 - sizeRatio), 1.0)

        if sizeRatio < (1.0 - config.sizeTolerance) {
            let magnitude = getMagnitude(diff: 1.0 - sizeRatio)
            return SimpleGuideResult(
                guide: .moveForward,
                magnitude: magnitude,
                progress: 0.7 + sizeScore * 0.2,
                debugInfo: "크기 \(String(format: "%.0f", sizeRatio * 100))%",
                shotTypeMatch: true,
                currentShotType: currentShotType.displayName,
                targetShotType: referenceShotType.displayName,
                feedbackStage: .zoom
            )
        } else if sizeRatio > (1.0 + config.sizeTolerance) {
            let magnitude = getMagnitude(diff: sizeRatio - 1.0)
            return SimpleGuideResult(
                guide: .moveBackward,
                magnitude: magnitude,
                progress: 0.7 + sizeScore * 0.2,
                debugInfo: "크기 \(String(format: "%.0f", sizeRatio * 100))%",
                shotTypeMatch: true,
                currentShotType: currentShotType.displayName,
                targetShotType: referenceShotType.displayName,
                feedbackStage: .zoom
            )
        }

        // Stage 4: 줌 체크
        if let targetZoom = referenceZoomFactor {
            let zoomRatio = currentZoom / targetZoom
            let zoomDiff = abs(1.0 - zoomRatio)

            if zoomDiff > config.zoomTolerance {
                let guide: GuideType = currentZoom < targetZoom ? .zoomIn : .zoomOut
                return SimpleGuideResult(
                    guide: guide,
                    magnitude: "",
                    progress: 0.85,
                    debugInfo: "줌 \(String(format: "%.1fx", currentZoom)) → \(String(format: "%.1fx", targetZoom))",
                    shotTypeMatch: true,
                    currentShotType: currentShotType.displayName,
                    targetShotType: referenceShotType.displayName,
                    feedbackStage: .zoom,
                    currentZoom: currentZoom,
                    targetZoom: targetZoom
                )
            }
        }

        // Stage 5: 포즈 체크
        if let refKps = referenceKeypoints, refKps.count >= 17, currentKeypoints.count >= 17 {
            let poseSimilarity = calculatePoseSimilarity(current: currentKeypoints, reference: refKps)

            if poseSimilarity < config.poseThreshold {
                return SimpleGuideResult(
                    guide: .adjustPose,
                    magnitude: "",
                    progress: 0.90,
                    debugInfo: "포즈 유사도: \(String(format: "%.0f", poseSimilarity * 100))%",
                    shotTypeMatch: true,
                    currentShotType: currentShotType.displayName,
                    targetShotType: referenceShotType.displayName,
                    feedbackStage: .pose
                )
            }
        }

        // Perfect!
        return SimpleGuideResult(
            guide: .perfect,
            magnitude: "",
            progress: 1.0,
            debugInfo: "모든 조건 충족",
            shotTypeMatch: true,
            currentShotType: currentShotType.displayName,
            targetShotType: referenceShotType.displayName,
            feedbackStage: .perfect
        )
    }

    // MARK: - Gate Evaluation (기술적 점수)

    private func evaluateGates(
        currentBBox: CGRect,
        currentShotType: ShotTypeGate,
        currentKeypoints: [PoseKeypoint],
        currentZoom: CGFloat,
        currentAspectRatio: CameraAspectRatio
    ) -> GateEvaluation {

        // Gate 0: 비율 (항상 통과 - 이미 체크됨)
        let gate0 = GateResult(
            name: "비율",
            score: 1.0,
            threshold: 1.0,
            feedback: "",
            icon: "📐",
            category: "aspect_ratio"
        )

        // Gate 1: 프레이밍 (샷타입)
        let shotTypeMatch = currentShotType == referenceShotType
        let shotTypeScore = shotTypeMatch ? 1.0 : max(0, 1.0 - CGFloat(abs(currentShotType.rawValue - referenceShotType.rawValue)) / 7.0)
        let gate1Feedback = shotTypeMatch ? "" : "\(currentShotType.displayName) → \(referenceShotType.displayName)"
        let gate1 = GateResult(
            name: "프레이밍",
            score: shotTypeScore,
            threshold: 0.75,
            feedback: gate1Feedback,
            icon: "📸",
            category: "framing",
            debugInfo: "현재: \(currentShotType.displayName) vs 목표: \(referenceShotType.displayName)",
            metadata: ["shotType": currentShotType]
        )

        // Gate 2: 위치
        let diffX = abs(currentBBox.midX - referenceCenterX)
        let diffY = abs(currentBBox.midY - referenceCenterY)
        let positionScore = 1.0 - (diffX + diffY)
        var positionFeedback = ""
        if diffX > config.positionToleranceX {
            positionFeedback = currentBBox.midX > referenceCenterX ? "왼쪽으로 이동" : "오른쪽으로 이동"
        } else if diffY > config.positionToleranceY {
            positionFeedback = currentBBox.midY > referenceCenterY ? "위로 틸트" : "아래로 틸트"
        }
        let gate2 = GateResult(
            name: "위치",
            score: positionScore,
            threshold: 0.75,
            feedback: positionFeedback,
            icon: "↔️",
            category: "position"
        )

        // Gate 3: 압축감/줌
        var zoomScore: CGFloat = 1.0
        var zoomFeedback = ""
        if let targetZoom = referenceZoomFactor {
            let zoomRatio = currentZoom / targetZoom
            zoomScore = 1.0 - min(abs(1.0 - zoomRatio), 1.0)
            if abs(1.0 - zoomRatio) > config.zoomTolerance {
                zoomFeedback = currentZoom < targetZoom ? "줌인 필요" : "줌아웃 필요"
            }
        }
        let gate3 = GateResult(
            name: "압축감",
            score: zoomScore,
            threshold: 0.70,
            feedback: zoomFeedback,
            icon: "🔍",
            category: "compression"
        )

        // Gate 4: 포즈
        var poseScore: CGFloat = 1.0
        var poseFeedback = ""
        if let refKps = referenceKeypoints, refKps.count >= 17, currentKeypoints.count >= 17 {
            poseScore = calculatePoseSimilarity(current: currentKeypoints, reference: refKps)
            if poseScore < config.poseThreshold {
                poseFeedback = "포즈를 조정하세요"
            }
        }
        let gate4 = GateResult(
            name: "포즈",
            score: poseScore,
            threshold: config.poseThreshold,
            feedback: poseFeedback,
            icon: "🤸",
            category: "pose"
        )

        return GateEvaluation(
            gate0: gate0,
            gate1: gate1,
            gate2: gate2,
            gate3: gate3,
            gate4: gate4,
            currentShotType: currentShotType,
            referenceShotType: referenceShotType
        )
    }

    // MARK: - Helper Methods

    private func stabilizeShotType(_ rawType: ShotTypeGate) -> ShotTypeGate {
        if rawType == stableShotType {
            shotTypeChangeCount = 0
            return rawType
        } else {
            shotTypeChangeCount += 1
            if shotTypeChangeCount >= shotTypeStabilityThreshold {
                stableShotType = rawType
                shotTypeChangeCount = 0
                return rawType
            } else {
                return stableShotType ?? rawType
            }
        }
    }

    private func stabilizeGuide(_ result: SimpleGuideResult) -> SimpleGuideResult {
        let now = Date()

        if result.guide == lastGuide {
            sameGuideCount += 1
        } else {
            sameGuideCount = 1
        }

        let shouldChange = sameGuideCount >= stabilityThreshold ||
                           now.timeIntervalSince(lastGuideTime) > 1.0

        if shouldChange && result.guide != lastGuide {
            lastGuide = result.guide
            lastGuideTime = now

            if now.timeIntervalSince(lastDebugLogTime) > debugLogInterval {
                print("[UnifiedEngine] \(result.guide.icon) \(result.displayMessage) | \(result.debugInfo)")
                lastDebugLogTime = now
            }
        }

        return result
    }

    private func calculatePoseSimilarity(current: [PoseKeypoint], reference: [PoseKeypoint]) -> CGFloat {
        let importantIndices = [0, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]

        guard let curBBox = ShotTypeGate.calculateKeypointBBox(current),
              let refBBox = ShotTypeGate.calculateKeypointBBox(reference) else {
            return 0.5
        }

        var totalScore: CGFloat = 0
        var validCount: CGFloat = 0

        for idx in importantIndices {
            guard idx < current.count, idx < reference.count else { continue }

            let curKp = current[idx]
            let refKp = reference[idx]

            if curKp.confidence < 0.3 || refKp.confidence < 0.3 { continue }

            let curRelX = (curKp.location.x - curBBox.minX) / max(curBBox.width, 0.01)
            let curRelY = (curKp.location.y - curBBox.minY) / max(curBBox.height, 0.01)

            let refRelX = (refKp.location.x - refBBox.minX) / max(refBBox.width, 0.01)
            let refRelY = (refKp.location.y - refBBox.minY) / max(refBBox.height, 0.01)

            let distance = sqrt(pow(curRelX - refRelX, 2) + pow(curRelY - refRelY, 2))
            let score = max(0, 1.0 - distance * 2)

            totalScore += score
            validCount += 1
        }

        guard validCount > 0 else { return 0.5 }
        return totalScore / validCount
    }

    private func getMagnitude(diff: CGFloat) -> String {
        if diff < 0.15 { return "조금" }
        if diff < 0.30 { return "반 걸음" }
        if diff < 0.50 { return "한 걸음" }
        return "두 걸음"
    }

    private func getMagnitudePosition(diff: CGFloat) -> String {
        if diff < 0.10 { return "조금" }
        if diff < 0.20 { return "반 걸음" }
        return "한 걸음"
    }

    private func getMagnitudeFromShotTypeDistance(_ distance: Int) -> String {
        switch distance {
        case 1: return "조금"
        case 2: return "반 걸음"
        case 3...4: return "한 걸음"
        default: return "두 걸음"
        }
    }

    private func toTiltAngle(percent: CGFloat) -> Int {
        if percent < 5 { return 2 }
        if percent < 10 { return 5 }
        if percent < 15 { return 8 }
        if percent < 20 { return 10 }
        return min(15, Int(percent * 0.5))
    }

    // MARK: - Result Factory Methods

    private func createIdleResult(reason: String) -> EvaluationResult {
        let guide = SimpleGuideResult(
            guide: .enterFrame,
            magnitude: "",
            progress: 0,
            debugInfo: reason,
            shotTypeMatch: false,
            currentShotType: "-",
            targetShotType: referenceShotType.displayName,
            feedbackStage: .frameEntry
        )
        return EvaluationResult(simpleGuide: guide, gateEvaluation: nil, isPerfect: false)
    }

    private func createFrameEntryResult(reason: String) -> EvaluationResult {
        let guide = SimpleGuideResult(
            guide: .enterFrame,
            magnitude: "",
            progress: 0.1,
            debugInfo: reason,
            shotTypeMatch: false,
            currentShotType: "-",
            targetShotType: referenceShotType.displayName,
            feedbackStage: .frameEntry
        )
        return EvaluationResult(simpleGuide: guide, gateEvaluation: nil, isPerfect: false)
    }

    private func createAspectRatioMismatchResult(
        current: CameraAspectRatio,
        target: CameraAspectRatio
    ) -> EvaluationResult {
        let guide = SimpleGuideResult(
            guide: .enterFrame,
            magnitude: "",
            progress: 0,
            debugInfo: "비율 불일치: \(current.displayName) → \(target.displayName)",
            shotTypeMatch: false,
            currentShotType: "-",
            targetShotType: "-",
            feedbackStage: .frameEntry
        )

        // Gate 0 실패 포함 GateEvaluation 생성
        let gate0 = GateResult(
            name: "비율",
            score: 0.0,
            threshold: 1.0,
            feedback: "카메라 비율을 \(target.displayName)로 변경하세요",
            icon: "📐",
            category: "aspect_ratio",
            debugInfo: "현재: \(current.displayName) vs 목표: \(target.displayName)"
        )
        let dummyGate = GateResult(name: "-", score: 0, threshold: 1, feedback: "", icon: "", category: "")
        let gateEval = GateEvaluation(
            gate0: gate0,
            gate1: dummyGate,
            gate2: dummyGate,
            gate3: dummyGate,
            gate4: dummyGate
        )

        return EvaluationResult(simpleGuide: guide, gateEvaluation: gateEval, isPerfect: false)
    }
}

// MARK: - Evaluation Result

extension UnifiedFeedbackEngine {

    struct EvaluationResult {
        let simpleGuide: SimpleGuideResult
        let gateEvaluation: GateEvaluation?
        let isPerfect: Bool
    }
}
