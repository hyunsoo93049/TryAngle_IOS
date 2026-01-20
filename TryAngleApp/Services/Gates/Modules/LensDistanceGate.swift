//
//  LensDistanceGate.swift
//  TryAngleApp
//
//  Gate 3: 렌즈/거리 평가
//  - 핀홀 카메라 모델 기반 물리적 거리 추정
//  - 초점거리 + 거리 비교로 통합 가이드 제공
//  - CompressionGate 대체
//
//  Created: 2025-01-20
//

import Foundation
import CoreGraphics

// MARK: - Lens Distance Gate

public class LensDistanceGate: GateModule {

    // MARK: - GateModule Protocol

    public let name = "렌즈/거리"
    public let priority = 3

    // MARK: - Configuration

    /// 통과 기준 점수
    private let threshold: CGFloat = 0.70

    /// 거리 허용 오차 (미터)
    private let distanceTolerance: Float = 0.3

    /// 초점거리 허용 오차 (mm)
    private let focalLengthTolerance: Int = 10

    // MARK: - Components

    /// 피드백 디바운서 (UI 안정화)
    private let guidanceDebouncer = GuidanceDebouncer()

    /// 키포인트 스무더 (떨림 감소)
    private let keypointSmoother = KeypointSmoother(alpha: 0.3)

    // MARK: - Keypoint Indices

    private let leftShoulderIndex = 5
    private let rightShoulderIndex = 6

    // MARK: - Initialization

    public init() {}

    // MARK: - GateModule Protocol

    public func evaluate(context: GateContext) -> GateResult {
        let analysis = context.analysis
        let reference = context.reference
        let settings = context.settings

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // 1. 현재 상태 추출
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        let currentKeypoints = analysis.poseResult?.asPoseKeypoints ?? []
        let imageWidth = analysis.input.imageSize.width

        // 이미지 크기 유효성 체크
        guard imageWidth > 0 else {
            return createMissingResult("이미지 정보 대기 중...")
        }

        // 현재 초점거리 계산
        let currentZoom = settings.currentZoomFactor
        let currentFocalMM = DeviceLensConfig.shared.focalLengthMM(for: currentZoom)

        // 어깨 키포인트 추출 및 스무딩
        guard let shoulderPixelWidth = extractSmoothedShoulderWidth(
            from: currentKeypoints,
            imageWidth: imageWidth
        ) else {
            return createMissingResult("어깨 감지 대기 중...")
        }

        // 현재 거리 추정
        let bodyType = settings.bodyType
        guard let currentDistance = DistanceEstimator.estimateDistance(
            shoulderPixelWidth: shoulderPixelWidth,
            imageWidth: imageWidth,
            focalLengthMM: currentFocalMM,
            shoulderWidthM: bodyType.shoulderWidthM
        ) else {
            return createMissingResult("거리 계산 중...")
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // 2. 레퍼런스 확인
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        guard let ref = reference,
              let refFocal = ref.focalLength else {
            return createSkippedResult(currentFocalMM, currentDistance)
        }

        let refFocalMM = refFocal.focalLength35mm

        // 레퍼런스 거리 (저장된 값 또는 기본값)
        let refDistance = ref.estimatedDistance ?? 2.0

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // 3. 비교 및 가이드 생성
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        let focalDiff = currentFocalMM - refFocalMM
        let distanceDiff = currentDistance - refDistance

        let needsZoomChange = abs(focalDiff) > focalLengthTolerance
        let needsDistanceChange = abs(distanceDiff) > distanceTolerance

        // 🔧 수정: 목표와의 거리에 비례한 점수 계산
        // 초점거리 점수: 허용오차 내 = 1.0, 벗어날수록 감점 (최대 50mm 차이 = 0점)
        let focalScore: CGFloat = max(0, 1.0 - CGFloat(abs(focalDiff)) / 50.0)
        // 거리 점수: 허용오차 내 = 1.0, 벗어날수록 감점 (최대 2m 차이 = 0점)
        let distanceScore: CGFloat = max(0, 1.0 - CGFloat(abs(distanceDiff)) / 2.0)
        // 종합 점수: 두 점수의 평균
        var score: CGFloat = (focalScore + distanceScore) / 2.0

        var feedback = ""
        var category = "lens_distance"

        if needsZoomChange && needsDistanceChange {
            // 케이스 A: 줌 + 거리 모두 조정 필요
            feedback = generateCombinedGuidance(
                focalDiff: focalDiff,
                distanceDiff: distanceDiff,
                targetFocal: refFocalMM,
                targetDistance: refDistance
            )
            category = "lens_distance_both"

        } else if needsZoomChange {
            // 케이스 B: 줌만 조정 필요
            score = focalScore  // 초점거리 점수만 사용
            feedback = generateZoomGuidance(
                focalDiff: focalDiff,
                currentFocal: currentFocalMM,
                targetFocal: refFocalMM
            )
            category = "lens_only"

        } else if needsDistanceChange {
            // 케이스 C: 거리만 조정 필요
            score = distanceScore  // 거리 점수만 사용
            feedback = generateDistanceGuidance(
                distanceDiff: distanceDiff,
                currentDistance: currentDistance,
                targetDistance: refDistance
            )
            category = "distance_only"

        } else {
            // 케이스 D: 완벽
            score = 1.0
            feedback = "렌즈/거리 완벽 (\(currentFocalMM)mm, \(String(format: "%.1f", currentDistance))m)"
            category = "lens_distance_perfect"
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // 4. 디바운싱 적용
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        let debounceResult = guidanceDebouncer.debounce(
            distance: currentDistance,
            focalLength: currentFocalMM,
            newFeedback: feedback,
            category: category
        )

        // 디바운싱으로 피드백이 nil이면 이전 피드백 유지
        let finalFeedback = debounceResult.feedback ?? guidanceDebouncer.currentFeedback

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // 5. 결과 반환
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        return GateResult(
            name: name,
            score: score,
            threshold: threshold,
            feedback: finalFeedback,
            icon: "📐",
            category: category,
            debugInfo: "Focal:\(currentFocalMM)mm→\(refFocalMM)mm, Dist:\(String(format: "%.1f", currentDistance))m→\(String(format: "%.1f", refDistance))m"
        )
    }

    // MARK: - Shoulder Extraction with Smoothing

    private func extractSmoothedShoulderWidth(
        from keypoints: [PoseKeypoint],
        imageWidth: CGFloat
    ) -> CGFloat? {
        // 인덱스 범위 체크
        guard keypoints.count > rightShoulderIndex else {
            return nil
        }

        let leftShoulder = keypoints[leftShoulderIndex]
        let rightShoulder = keypoints[rightShoulderIndex]

        // 신뢰도 체크
        guard leftShoulder.confidence > 0.3,
              rightShoulder.confidence > 0.3 else {
            return nil
        }

        // 스무딩 적용
        let smoothed = keypointSmoother.smoothShoulders(
            leftShoulder: leftShoulder.location,
            rightShoulder: rightShoulder.location,
            leftConf: leftShoulder.confidence,
            rightConf: rightShoulder.confidence
        )

        // X축만 사용 (Y축 노이즈 무시)
        let normalizedWidth = abs(smoothed.left.x - smoothed.right.x)

        // 정규화 해제 (0~1 → pixels)
        return normalizedWidth * imageWidth
    }

    // MARK: - Guidance Generators

    private func generateCombinedGuidance(
        focalDiff: Int,
        distanceDiff: Float,
        targetFocal: Int,
        targetDistance: Float
    ) -> String {
        let targetZoom = CGFloat(targetFocal) / 24.0
        let zoomText = String(format: "%.1fx", targetZoom)
        let steps = max(1, Int(abs(distanceDiff) * 2))

        if focalDiff < 0 && distanceDiff < 0 {
            // 현재 줌 부족, 현재 너무 가까움 → 뒤로 물러나서 줌인
            return "\(steps)걸음 뒤로 물러나서 \(zoomText)로 줌인"
        } else if focalDiff < 0 && distanceDiff > 0 {
            // 현재 줌 부족, 현재 너무 멀음 → 줌인 (거리는 유지)
            return "\(zoomText)로 줌인하세요"
        } else if focalDiff > 0 && distanceDiff > 0 {
            // 현재 줌 과다, 현재 너무 멀음 → 앞으로 다가가서 줌아웃
            return "\(steps)걸음 앞으로 다가가서 \(zoomText)로 줌아웃"
        } else {
            // 현재 줌 과다, 현재 너무 가까움 → 줌아웃 (거리는 유지)
            return "\(zoomText)로 줌아웃하세요"
        }
    }

    private func generateZoomGuidance(
        focalDiff: Int,
        currentFocal: Int,
        targetFocal: Int
    ) -> String {
        let targetZoom = CGFloat(targetFocal) / 24.0
        let zoomText = String(format: "%.1fx", targetZoom)

        if focalDiff < 0 {
            return "\(zoomText)로 줌인 (\(currentFocal)mm → \(targetFocal)mm)"
        } else {
            return "\(zoomText)로 줌아웃 (\(currentFocal)mm → \(targetFocal)mm)"
        }
    }

    private func generateDistanceGuidance(
        distanceDiff: Float,
        currentDistance: Float,
        targetDistance: Float
    ) -> String {
        let steps = max(1, Int(abs(distanceDiff) * 2))
        let currentText = String(format: "%.1f", currentDistance)
        let targetText = String(format: "%.1f", targetDistance)

        if distanceDiff < 0 {
            // 현재가 더 가까움 → 뒤로
            return "\(steps)걸음 뒤로 (\(currentText)m → \(targetText)m)"
        } else {
            // 현재가 더 멀음 → 앞으로
            return "\(steps)걸음 앞으로 (\(currentText)m → \(targetText)m)"
        }
    }

    // MARK: - Helper Results

    private func createMissingResult(_ message: String) -> GateResult {
        return GateResult(
            name: name,
            score: 0.0,
            threshold: threshold,
            feedback: message,
            icon: "📐",
            category: "lens_distance_missing"
        )
    }

    private func createSkippedResult(_ currentFocal: Int, _ currentDistance: Float) -> GateResult {
        return GateResult(
            name: name,
            score: 1.0,
            threshold: threshold,
            feedback: "레퍼런스 없음 (현재: \(currentFocal)mm, \(String(format: "%.1f", currentDistance))m)",
            icon: "📐",
            category: "lens_distance_skipped"
        )
    }

    // MARK: - Reset

    /// 새 레퍼런스 설정 시 호출
    public func reset() {
        guidanceDebouncer.reset()
        keypointSmoother.reset()
    }
}
