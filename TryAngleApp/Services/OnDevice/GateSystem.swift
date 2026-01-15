//
//  GateSystem.swift
//  v1.5 통합 Gate System - 5단계 평가 시스템
//  작성일: 2025-12-05
//  수정일: 2025-12-07 (Phase 3 통합 + v7 피드백 문구 적용)
//
//  v7 피드백 개선 사항:
//  - 구체적인 수치 (걸음 수, 퍼센트)
//  - 친절한 설명 문구
//  - 샷 타입 + 조정 방법 명시
//  - 광각/망원 렌즈 표현
//

import Foundation
import CoreGraphics

// MARK: - 🔧 Debug Configuration
/// 디버그 로그 출력 여부 (false로 설정하면 모든 디버그 출력 비활성화)
fileprivate let DEBUG_GATE_SYSTEM = true
/// 디버그 로그 출력 간격 (초) - 너무 빈번한 출력 방지
fileprivate let DEBUG_LOG_INTERVAL: TimeInterval = 0.5

// MARK: - Gate 평가 결과
struct GateEvaluation: Equatable {
    let gate0: GateResult  // 비율
    let gate1: GateResult  // 프레이밍 (샷타입 + 점유율)
    let gate2: GateResult  // 위치/구도 (여백 + 3분할)
    let gate3: GateResult  // 압축감
    let gate4: GateResult  // 포즈

    // 🆕 샷타입 정보 (정밀평가용)
    var currentShotType: ShotTypeGate?
    var referenceShotType: ShotTypeGate?

    var allPassed: Bool {
        return gate0.passed && gate1.passed && gate2.passed && gate3.passed && gate4.passed
    }

    var passedCount: Int {
        return [gate0, gate1, gate2, gate3, gate4].filter { $0.passed }.count
    }

    var overallScore: CGFloat {
        let scores = [gate0.score, gate1.score, gate2.score, gate3.score, gate4.score]
        return scores.reduce(0, +) / CGFloat(scores.count)
    }

    /// 통과 못한 첫 번째 Gate의 피드백 반환 (우선순위 기반)
    /// 🔧 우선순위: 비율 → 프레이밍 → 위치 → 포즈 → 압축감 (순서 변경)
    /// 압축감은 미세조정이므로 가장 마지막 우선순위
    var primaryFeedback: String {
        if !gate0.passed { return gate0.feedback }  // 1. 비율 (필수)
        if !gate1.passed { return gate1.feedback }  // 2. 프레이밍 (샷타입/크기)
        if !gate2.passed { return gate2.feedback }  // 3. 위치 (좌우/상하)
        if !gate4.passed { return gate4.feedback }  // 4. 포즈
        if !gate3.passed { return gate3.feedback }  // 5. 압축감 (미세조정)
        return "✓ 완벽한 구도입니다!"
    }

    var allFeedbacks: [String] {
        return [gate0, gate1, gate2, gate3, gate4]
            .filter { !$0.passed }
            .map { $0.feedback }
    }

    /// 현재 실패한 Gate 번호 (모두 통과 시 nil)
    /// 🔧 우선순위: 비율 → 프레이밍 → 위치 → 포즈 → 압축감
    var currentFailedGate: Int? {
        if !gate0.passed { return 0 }  // 비율
        if !gate1.passed { return 1 }  // 프레이밍
        if !gate2.passed { return 2 }  // 위치
        if !gate4.passed { return 4 }  // 포즈
        if !gate3.passed { return 3 }  // 압축감
        return nil
    }

    // MARK: - 🔧 Clean Debug Summary
    /// 핵심 정보만 한 줄로 출력하는 디버그 요약
    var debugSummary: String {
        let gates = [
            ("비율", gate0),
            ("프레이밍", gate1),
            ("위치", gate2),
            ("압축감", gate3),
            ("포즈", gate4)
        ]

        // Gate 상태: ✓ or ✗ + 점수
        let gateStatus = gates.map { name, gate in
            let icon = gate.passed ? "✓" : "✗"
            return "\(name)\(icon)\(Int(gate.score * 100))%"
        }.joined(separator: " | ")

        // 실패한 게이트 피드백
        let failedInfo: String
        if let failedGate = currentFailedGate {
            let gateInfo = gates[failedGate == 4 ? 4 : failedGate]
            failedInfo = "→ \(gateInfo.1.feedback)"
        } else {
            failedInfo = "→ 완벽!"
        }

        // 샷타입 정보 (Gate 1의 debugInfo에서 추출)
        let shotTypeInfo = gate1.debugInfo ?? ""

        return "🎯 [\(gateStatus)] \(shotTypeInfo) \(failedInfo)"
    }

    /// 상세 디버그 출력 (문제 분석용)
    func printDetailedDebug() {
        guard DEBUG_GATE_SYSTEM else { return }

        print("\n" + String(repeating: "=", count: 60))
        print("📊 Gate System 분석 결과")
        print(String(repeating: "=", count: 60))

        let gates: [(Int, String, GateResult)] = [
            (0, "비율", gate0),
            (1, "프레이밍", gate1),
            (2, "위치", gate2),
            (3, "압축감", gate3),
            (4, "포즈", gate4)
        ]

        for (index, name, gate) in gates {
            let status = gate.passed ? "✅ PASS" : "❌ FAIL"
            let scoreStr = String(format: "%3.0f%%", gate.score * 100)
            print("  Gate \(index) [\(name)]: \(status) (\(scoreStr))")
            if !gate.passed || gate.score < 0.95 {
                print("         → \(gate.feedback)")
            }
            if let debug = gate.debugInfo, !debug.isEmpty {
                print("         📍 \(debug)")
            }
        }

        print(String(repeating: "-", count: 60))
        print("  총점: \(String(format: "%.1f", overallScore * 100))% | 통과: \(passedCount)/5")
        if let failedGate = currentFailedGate {
            print("  🎯 현재 목표: Gate \(failedGate) 해결")
        } else {
            print("  🎉 모든 Gate 통과!")
        }
        print(String(repeating: "=", count: 60) + "\n")
    }
}




    /* ============================================
     * 🗄️ 기존 로직 백업 (v5)
     * ============================================
     *
     * static func fromKeypoints(_ keypoints: [PoseKeypoint], confidenceThreshold: Float = 0.3) -> ShotTypeGate {
     *     guard keypoints.count >= 17 else {
     *         return .mediumShot
     *     }
     *
     *     func isVisible(_ idx: Int, threshold: Float = confidenceThreshold) -> Bool {
     *         guard idx < keypoints.count else { return false }
     *         let kp = keypoints[idx]
     *         return kp.confidence > threshold &&
     *                kp.location.y >= 0.0 && kp.location.y <= 1.05
     *     }
     *
     *     let strictThreshold: Float = 0.5
     *     let hasAnkles = isVisible(15, threshold: strictThreshold) || isVisible(16, threshold: strictThreshold)
     *     let hasFeet = keypoints.count > 22 && (17...22).contains(where: { isVisible($0, threshold: strictThreshold) })
     *     let hasKnees = isVisible(13) || isVisible(14)
     *     let hasHips = isVisible(11) || isVisible(12)
     *     let hasElbows = isVisible(7) || isVisible(8)
     *     let hasShoulders = isVisible(5) || isVisible(6)
     *
     *     func getMaxY(_ indices: [Int]) -> CGFloat {
     *         return indices.compactMap { idx -> CGFloat? in
     *             guard idx < keypoints.count, isVisible(idx) else { return nil }
     *             return keypoints[idx].location.y
     *         }.max() ?? 0.0
     *     }
     *
     *     let faceKeypointCount = keypoints.count > 90 ? (23...90).filter { isVisible($0) }.count : 0
     *     let kneeMaxY = getMaxY([13, 14])
     *     let hipMaxY = getMaxY([11, 12])
     *
     *     if hasAnkles || hasFeet {
     *         return .fullShot
     *     } else if hasKnees {
     *          return .mediumFullShot
     *     } else if hasHips {
     *         if hipMaxY < 0.8 {
     *             return .americanShot
     *         } else {
     *             return .mediumShot
     *         }
     *     } else if hasElbows {
     *         return .mediumCloseUp
     *     } else if hasShoulders {
     *         if faceKeypointCount > 50 {
     *             return .closeUp
     *         } else {
     *             return .mediumCloseUp
     *         }
     *     } else {
     *         return .extremeCloseUp
     *     }
     * }
     * ============================================
     */



// MARK: - Gate System
class GateSystem {

    // Gate 통과 기준
    // Gate 통과 기준
    private let baseThresholds = GateThresholds()
    
    // 🆕 난이도 조절 (Phase 2 Adaptive Difficulty)
    var difficultyMultiplier: CGFloat = 1.0
    
    private var thresholds: GateThresholds {
        return baseThresholds.scaled(by: difficultyMultiplier)
    }

    // 🆕 Debug State (User Request: Log only on change)
    private var lastCurrentShotType: ShotTypeGate?
    private var lastRefShotType: ShotTypeGate?
    private var lastDebugLogTime: Date = Date()

    // 🆕 마지막으로 계산된 샷타입 (정밀평가용 - public 접근 가능)
    private(set) var evaluatedCurrentShotType: ShotTypeGate?
    private(set) var evaluatedReferenceShotType: ShotTypeGate?

    // 🆕 샷타입 안정화 (Hysteresis) - 급격한 변화 방지
    private var stableShotType: ShotTypeGate?           // 안정화된 샷타입
    private var shotTypeChangeCount: Int = 0           // 동일 샷타입 연속 감지 횟수
    private let shotTypeStabilityThreshold: Int = 3    // 3회 연속 동일해야 변경
    private var lastShotTypeChangeTime: Date = .distantPast

    // 🆕 목표 줌 배율 (레퍼런스 분석 시 한 번 설정, 이후 고정)
    var targetZoomFactor: CGFloat?  // 예: 2.4x
    var currentZoomFactor: CGFloat = 1.0  // 현재 줌 (RealtimeAnalyzer에서 업데이트)

    // 🆕 줌 허용 오차 (10% 이내면 OK)
    private let zoomTolerance: CGFloat = 0.15

    struct GateThresholds {
        let aspectRatio: CGFloat
        let framing: CGFloat
        let position: CGFloat
        let compression: CGFloat
        let pose: CGFloat
        
        // 🆕 Configurable Hardcoded Values
        let minPersonSize: CGFloat
        let poseAngleThreshold: Float
        
        // 🆕 Multiplier 적용
        func scaled(by multiplier: CGFloat) -> GateThresholds {
            // multiplier > 1.0 -> 기준 완화 (Lower threshold for scores, Higher for errors)
            // multiplier < 1.0 -> 기준 강화
            
            // 점수형 Gate (높을수록 좋음) -> Threshold 낮춤
            let newFraming = max(0.1, framing / multiplier)
            let newPosition = max(0.1, position / multiplier)
            let newCompression = max(0.1, compression / multiplier)
            let newPose = max(0.1, pose / multiplier)
            // 최소 사이즈도 약간 완화
            let newMinPersonSize = max(0.01, minPersonSize / multiplier)
            
            // 오차형 Gate (낮을수록 좋음) -> Threshold 높임
            let newPoseAngle = poseAngleThreshold * Float(multiplier)
            
            return GateThresholds(
                aspectRatio: aspectRatio, // 비율은 절대적
                framing: newFraming,
                position: newPosition,
                compression: newCompression,
                pose: newPose,
                minPersonSize: newMinPersonSize,
                poseAngleThreshold: newPoseAngle
            )
        }
        
        // Memberwise Init 추가 (구조체 기본 init이 private일 수 있으므로 명시)
        // 🔧 compression threshold 상향: 0.70 → 0.75 (프레이밍과 동일)
        // 이유: 초기 진입 시 압축감보다 프레이밍(샷타입/크기)이 우선되어야 함
        init(aspectRatio: CGFloat = 1.0, framing: CGFloat = 0.75, position: CGFloat = 0.80, compression: CGFloat = 0.75, pose: CGFloat = 0.70, minPersonSize: CGFloat = 0.05, poseAngleThreshold: Float = 15.0) {
            self.aspectRatio = aspectRatio
            self.framing = framing
            self.position = position
            self.compression = compression
            self.pose = pose
            self.minPersonSize = minPersonSize
            self.poseAngleThreshold = poseAngleThreshold
        }
    }

    private let marginAnalyzer = MarginAnalyzer()

    // MARK: - 전체 평가
    func evaluate(
        currentBBox: CGRect,
        referenceBBox: CGRect?,
        currentImageSize: CGSize,
        referenceImageSize: CGSize?,
        compressionIndex: CGFloat?,
        referenceCompressionIndex: CGFloat?,
        currentAspectRatio: CameraAspectRatio = .ratio4_3,
        referenceAspectRatio: CameraAspectRatio = .ratio4_3,
        poseComparison: PoseComparisonResult? = nil,
        isFrontCamera: Bool = false,
        currentKeypoints: [PoseKeypoint]? = nil,      // 🆕 현재 프레임 키포인트
        referenceKeypoints: [PoseKeypoint]? = nil,    // 🆕 레퍼런스 키포인트
        currentFocalLength: FocalLengthInfo? = nil,   // 🆕 현재 35mm 환산 초점거리
        referenceFocalLength: FocalLengthInfo? = nil  // 🆕 레퍼런스 35mm 환산 초점거리
    ) -> GateEvaluation {

        // 🆕 현재 프레임에 인물이 있는지 체크
        // BBox가 너무 작거나 없으면 인물 미검출로 판단
        let minValidSize: CGFloat = thresholds.minPersonSize  // Configurable Threshold
        let hasCurrentPerson = currentBBox.width > minValidSize && currentBBox.height > minValidSize

        // Gate 0: 비율 체크 (최우선) - 인물 없어도 체크 가능
        let gate0 = evaluateAspectRatio(
            current: currentAspectRatio,
            reference: referenceAspectRatio
        )

        // 🆕 인물이 없으면 Gate 1~4는 모두 "인물 미검출" 피드백
        guard hasCurrentPerson else {
            let noPersonResult = GateResult(
                name: "인물 미검출",
                score: 0.0,
                threshold: 0.5,
                feedback: "인물이 검출되지 않습니다. 프레임 안에 들어오세요",
                icon: "👤",
                category: "no_person"
            )
            return GateEvaluation(
                gate0: gate0,
                gate1: noPersonResult,
                gate2: noPersonResult,
                gate3: noPersonResult,
                gate4: noPersonResult,
                currentShotType: nil,
                referenceShotType: nil
            )
        }

        // Gate 1: 프레이밍 (샷타입 + 점유율) - 🆕 v6 키포인트 기반 샷타입
        let gate1 = evaluateFraming(
            bbox: currentBBox,
            imageSize: currentImageSize,
            referenceBBox: referenceBBox,
            referenceImageSize: referenceImageSize,
            isFrontCamera: isFrontCamera,
            currentKeypoints: currentKeypoints,      // 🆕 v6: 현재 프레임 키포인트
            referenceKeypoints: referenceKeypoints   // 🆕 v6: 레퍼런스 키포인트
        )

        // Gate 2: 위치/구도 (여백 균형 + 3분할)
        let gate2 = evaluatePosition(
            bbox: currentBBox,
            imageSize: currentImageSize,
            referenceBBox: referenceBBox,
            referenceImageSize: referenceImageSize,
            isFrontCamera: isFrontCamera,
            currentKeypoints: currentKeypoints,    // 🆕 v6
            referenceKeypoints: referenceKeypoints // 🆕 v6
        )

        // Gate 3: 압축감 (35mm 환산 초점거리 기반)
        let gate3 = evaluateCompression(
            currentIndex: compressionIndex,
            referenceIndex: referenceCompressionIndex,
            currentFocal: currentFocalLength,
            referenceFocal: referenceFocalLength,
            currentKeypoints: currentKeypoints ?? [],
            referenceKeypoints: referenceKeypoints ?? []
        )

        // Gate 4: 포즈
        let gate4 = evaluatePose(
            poseComparison: poseComparison,
            isFrontCamera: isFrontCamera,
            hasCurrentPerson: hasCurrentPerson
        )

        // 🔧 Clean Debug: 핵심 정보만 출력
        let evaluation = GateEvaluation(
            gate0: gate0,
            gate1: gate1,
            gate2: gate2,
            gate3: gate3,
            gate4: gate4,
            currentShotType: evaluatedCurrentShotType,
            referenceShotType: evaluatedReferenceShotType
        )

        if DEBUG_GATE_SYSTEM {
            let now = Date()
            if now.timeIntervalSince(lastDebugLogTime) > DEBUG_LOG_INTERVAL {
                print(evaluation.debugSummary)
                lastDebugLogTime = now
            }
        }

        return evaluation
    }

    // MARK: - Gate 0: 비율 체크
    private func evaluateAspectRatio(
        current: CameraAspectRatio,
        reference: CameraAspectRatio
    ) -> GateResult {
        let matched = current == reference
        let score: CGFloat = matched ? 1.0 : 0.0

        let feedback: String
        if matched {
            feedback = "비율 일치"
        } else {
            feedback = "카메라 비율을 \(reference.displayName)로 변경하세요"
        }

        // 🔍 디버그: 종횡비 비교 결과
        print("📐 [Gate 0] 현재: \(current.displayName) vs 레퍼런스: \(reference.displayName) → \(matched ? "✅ 일치" : "❌ 불일치")")

        return GateResult(
            name: "비율",
            score: score,
            threshold: thresholds.aspectRatio,
            feedback: feedback,
            icon: "📐",
            category: "aspect_ratio",
            debugInfo: "현재: \(current.displayName) vs 목표: \(reference.displayName)"
        )
    }

    // MARK: - Gate 1: 프레이밍 (샷타입 + 점유율) - v7 스타일 + v6 키포인트 기반
    private func evaluateFraming(
        bbox: CGRect,
        imageSize: CGSize,
        referenceBBox: CGRect?,
        referenceImageSize: CGSize?,
        isFrontCamera: Bool,
        currentKeypoints: [PoseKeypoint]? = nil,      // 🆕 v6: 키포인트 기반 샷타입
        referenceKeypoints: [PoseKeypoint]? = nil     // 🆕 v6: 레퍼런스 키포인트
    ) -> GateResult {
        // 🆕 v9.3: 인물 감지 실패 시 즉시 피드백 (Empty Air Problem 해결)
        // 키포인트가 너무 적거나(5개 미만) 없고, BBox도 매우 작으면(0.01 미만) 인물 없음으로 간주
        let hasSufficientKeypoints = (currentKeypoints?.count ?? 0) >= 5
        let hasMeaningfulBBox = bbox.width * bbox.height > 0.01
        
        if !hasSufficientKeypoints && !hasMeaningfulBBox {
            return GateResult(
                name: "Framing",
                score: 0.0,
                threshold: 0.75,
                feedback: "피사체를 인식할 수 없습니다. 화면 중앙에 인물을 비춰주세요.",
                icon: "🕵️",
                category: "framing",
                debugInfo: "No Subject Detected"
            )
        }

        // 🆕 v6: 키포인트 기반 샷타입 우선 사용 (Python framing_analyzer.py 로직)
        let rawShotType: ShotTypeGate
        if let keypoints = currentKeypoints, keypoints.count >= 17 {
            rawShotType = ShotTypeGate.fromKeypoints(keypoints)
        } else {
            // fallback: BBox 높이 기반
            let currentHeightRatio = bbox.height
            rawShotType = ShotTypeGate.fromBBoxHeight(currentHeightRatio)
        }

        // 🆕 샷타입 안정화 (Hysteresis) - 급격한 변화 방지
        let currentShotType: ShotTypeGate
        if rawShotType == stableShotType {
            // 이전과 동일 → 유지
            shotTypeChangeCount = 0
            currentShotType = rawShotType
        } else {
            // 다른 샷타입 감지
            shotTypeChangeCount += 1
            if shotTypeChangeCount >= shotTypeStabilityThreshold {
                // 연속 N회 동일하게 감지되면 변경 허용
                stableShotType = rawShotType
                shotTypeChangeCount = 0
                lastShotTypeChangeTime = Date()
                currentShotType = rawShotType
            } else {
                // 아직 안정화 안됨 → 이전 값 유지
                currentShotType = stableShotType ?? rawShotType
            }
        }

        // 🆕 실시간 최적화: 크기/위치는 YOLOX BBox, 샷타입은 키포인트
        // - YOLOX BBox (bbox 파라미터): 매 프레임 갱신 (30ms) → 크기/위치 비교용
        // - 키포인트 BBox: 3프레임마다 갱신 → 샷타입 판단용 (위에서 이미 사용됨)

        // 🔥 YOLOX BBox는 실시간 크기 비교용으로 그대로 사용
        // 키포인트 BBox는 샷타입 판단에만 사용 (이미 currentShotType에서 처리됨)

        // 현재 점유율 (YOLOX BBox 기반 - 실시간)
        let currentCoverage = bbox.width * bbox.height

        // 🆕 YOLOX BBox 높이 (실시간 크기 비교용)
        let currentHeight = bbox.height

        // 🆕 프레임 가장자리 체크 (너무 가까워서 잘린 상태 감지)
        // BBox가 프레임 가장자리에 닿으면 인물이 프레임 밖으로 나갔을 가능성 높음
        let edgeThreshold: CGFloat = 0.02  // 2% 이내면 가장자리
        let isAtTopEdge = bbox.minY < edgeThreshold
        let isAtBottomEdge = bbox.maxY > (1.0 - edgeThreshold)
        let isAtLeftEdge = bbox.minX < edgeThreshold
        let isAtRightEdge = bbox.maxX > (1.0 - edgeThreshold)
        
        // 신체가 가장자리 여러 곳에 닿아있으면 "너무 가까움" 판단
        let edgeCount = [isAtTopEdge, isAtBottomEdge, isAtLeftEdge, isAtRightEdge].filter { $0 }.count
        let isTooCloseAndCropped = edgeCount >= 2  // 2개 이상의 가장자리에 닿음

        var score: CGFloat = 1.0
        var feedback = "인물 크기가 프레임 대비 적절합니다"

        // 🔥 v6: 레퍼런스 샷타입 계산 (항상 계산하여 UI에 표시)
        var refShotTypeStr: String = "분석 중"
        var shotTypeDistVal: Int? = nil

        if let refBBox = referenceBBox {
            // 🆕 v6: 레퍼런스 샷타입도 키포인트 기반 우선
            let refShotType: ShotTypeGate
            if let keypoints = referenceKeypoints, keypoints.count >= 17 {
                // print("🔍 [DEBUG] Reference keypoints.count = \(keypoints.count), 키포인트 기반 판별 시작")
                refShotType = ShotTypeGate.fromKeypoints(keypoints)
                // print("🔍 [DEBUG] Reference 샷타입 결과: \(refShotType.displayName)")
            } else {
                // fallback: BBox 높이 기반
                let refHeightRatio = refBBox.height
                // print("🔍 [DEBUG] Fallback: reference keypoints 없음 (count: \(referenceKeypoints?.count ?? 0)), BBox 높이 기반 사용: \(refHeightRatio)")
                refShotType = ShotTypeGate.fromBBoxHeight(refHeightRatio)
                // print("🔍 [DEBUG] Fallback Reference 샷타입 결과: \(refShotType.displayName)")
            }

            // ✅ 레퍼런스 샷타입 이름 설정
            refShotTypeStr = refShotType.displayName

            // 🆕 정밀평가용 샷타입 저장
            self.evaluatedCurrentShotType = currentShotType
            self.evaluatedReferenceShotType = refShotType

            // 🆕 실시간 최적화: 키포인트 BBox는 샷타입 판단에만 사용
            // 크기 비교는 YOLOX BBox(refBBox)로 수행 → 실시간 피드백 제공
            // (키포인트 BBox 계산 제거 - 샷타입은 이미 위에서 fromKeypoints로 처리됨)

            // ============================================
            // 🔧 v8: Gate 1은 샷타입만 체크! (점유율은 Gate 2로)
            // ============================================
            // 샷 타입 거리 (0~7)
            let shotTypeDist = currentShotType.distance(to: refShotType)
            shotTypeDistVal = shotTypeDist

            // 🔥 실시간 최적화: YOLOX BBox로 크기 비교 (30ms 간격 갱신)
            // - 크기/위치 피드백: YOLOX BBox (실시간)
            // - 샷타입 판단: 키포인트 기반 (3프레임마다 갱신, 위에서 처리됨)
            // 레퍼런스도 YOLOX BBox 기반으로 비교 (일관성)
            let targetHeight = refBBox.height  // 레퍼런스 YOLOX BBox
            let sizeRatio = targetHeight / max(currentHeight, 0.01)

            // 🔧 v9: 점수 기반이 아닌 '타입 분류별 평가' (User Request)
            // 분류가 일치하지 않으면 무조건 Fail 처리.
            // 단, 피드백 생성을 위해 거리는 계산함.
            
            // 🆕 v9.1: 샷타입이 같아도 크기 차이가 크면 Fail 처리 (User Feedback 반영)
            // 예: 같은 '허벅지샷'이라도 한 걸음 차이 날 수 있음.
            let sizeDiffThreshold: CGFloat = 1.3 // 30% 이상 차이나면 피드백 제공 (0.7 ~ 1.3 허용)
            
            if currentShotType == refShotType {
                if sizeRatio > sizeDiffThreshold {
                    // 목표가 더 큼 -> 다가가야 함
                    score = 0.6 // Fail (Threshold 0.75)
                    let stepText = sizeRatio > 1.5 ? "한 걸음" : "반 걸음"
                    let actionText = isFrontCamera ? "카메라를 가까이 하세요" : "앞으로 다가가세요"
                    let targetName = refShotType.displayName
                    feedback = "\(targetName)을 위해 \(stepText) \(actionText)"

                } else if sizeRatio < (1.0 / sizeDiffThreshold) {
                    // 목표가 더 작음 -> 물러나야 함
                    score = 0.6 // Fail
                    let stepText = sizeRatio < 0.6 ? "한 걸음" : "반 걸음"
                    let actionText = isFrontCamera ? "카메라를 멀리 하세요" : "뒤로 물러나세요"
                    let targetName = refShotType.displayName
                    feedback = "\(targetName)을 위해 \(stepText) \(actionText)"

                } else {
                    score = 1.0  // ✅ 진짜 일치 (Pass)
                    feedback = "✓ 샷타입 OK (\(currentShotType.displayName))"
                }
            } else {
                score = 0.4  // ❌ 불일치 (Fail) - 거리와 상관없이 불일치면 통과 기준 미달 처리
            }

            // 🆕 너무 가까워서 잘린 경우 특별 처리
            if isTooCloseAndCropped {
                score = max(0.2, score - 0.2)
                var croppedParts: [String] = []
                if isAtTopEdge { croppedParts.append("상단") }
                if isAtBottomEdge { croppedParts.append("하단") }
                if isAtLeftEdge { croppedParts.append("좌측") }
                if isAtRightEdge { croppedParts.append("우측") }
                let croppedDesc = croppedParts.joined(separator: "/")

                feedback = isFrontCamera
                    ? "너무 가까워요! \(croppedDesc)이 잘렸습니다. (\(refShotType.guideDescription))"
                    : "피사체가 너무 가까워요! \(croppedDesc)이 잘렸습니다. (\(refShotType.guideDescription))"
            }
            // 🆕 v9: 샷타입 불일치 피드백 개선 (User Idea: Anatomical Guide + Reason + Direction + Steps)
            // 예: "허벅지샷을 위해 두 걸음 앞으로 다가가세요"
            else if score <= 0.4 && shotTypeDist >= 1 { // matched but size diff (score 0.6) is handled above. This is for distinct types.
                
                var stepText = ""
                var actionText = ""
                
                if sizeRatio > 1.0 {
                    // 현재가 목표보다 작음 (Target=0.5, Curr=0.25 -> Ratio=2.0) -> 다가가야 함
                    if sizeRatio > 1.8 { stepText = "두 걸음" }
                    else if sizeRatio > 1.3 { stepText = "한 걸음" }
                    else { stepText = "반 걸음" }
                    
                    actionText = isFrontCamera ? "카메라를 가까이 하세요" : "앞으로 다가가세요"
                } else {
                    // 현재가 목표보다 큼 (Target=0.5, Curr=1.0 -> Ratio=0.5) -> 물러나야 함
                    if sizeRatio < 0.55 { stepText = "두 걸음" }
                    else if sizeRatio < 0.75 { stepText = "한 걸음" }
                    else { stepText = "반 걸음" }
                    
                    actionText = isFrontCamera ? "카메라를 멀리 하세요" : "뒤로 물러나세요"
                }
                
                // 2. 피드백 구성
                // "허벅지샷을 위해 [두 걸음] [앞으로 다가가세요]"
                // UnifiedFeedbackGenerator가 '앞으로/뒤로' 키워드 인식
                let targetName = refShotType.displayName
                feedback = "\(targetName)을 위해 \(stepText) \(actionText)"
            }
            // 🔧 샷타입 OK (위에서 처리됨, but catch-all for existing logic flow if needed)
            else if feedback.isEmpty {
                 feedback = "✓ 샷타입 OK (\(currentShotType.displayName))"
            }
        } else {
            // 절대 평가: 이상적 점유율 25%~50%
            if currentCoverage < 0.20 {
                score = currentCoverage / 0.20
                feedback = isFrontCamera
                    ? "인물이 너무 작아요. 카메라를 가까이 하세요"
                    : "인물이 너무 작아요. 앞으로 다가가세요"
            } else if currentCoverage > 0.55 {
                score = max(0, 1.0 - (currentCoverage - 0.55) / 0.3)
                feedback = isFrontCamera
                    ? "인물이 화면을 너무 차지해요. 뒤로 물러나세요"
                    : "인물이 화면을 너무 차지해요. 카메라를 뒤로 하세요"
            }
        }

        // 🔥 v6: 디버그용 상세 정보 (거리 포함)
        let debugInfoText = "Shot: \(currentShotType.displayName) vs Ref: \(refShotTypeStr) (Dist: \(shotTypeDistVal ?? -1))"

        // 🔥 샷타입 디버그 로그 (0.5초 스로틀링)
        let now = Date()
        if now.timeIntervalSince(lastDebugLogTime) > 0.5 {
             print("📸 [ShotType] 현재: \(currentShotType.displayName) | 목표: \(refShotTypeStr) | 점수: \(String(format: "%.1f", score * 100))%")
             lastDebugLogTime = now
        }

        // ============================================
        // 🏁 Gate 1 결과 반환 (Debug Info 포함)
        // ============================================
        // 🔥 v6: UI에 표시할 샷타입 비교 정보 (실제 분석 결과)
        let uiDebugInfo = "현재: \(currentShotType.displayName) vs 목표: \(refShotTypeStr)"

        // 🔍 디버그: UI로 전달되는 값 확인
        // print("🔍 [DEBUG] UI로 전달할 debugInfo: \(uiDebugInfo)")

        // ✅ 최종 결과 반환 (debugInfo에 UI 표시용 정보 포함)
        return GateResult(
            name: "프레이밍",
            score: score,
            threshold: thresholds.framing,
            feedback: feedback,
            icon: "📸",
            category: "framing",
            debugInfo: uiDebugInfo  // 🔥 v6: 실제 샷타입 비교 정보
        )
    }

    // MARK: - Gate 2: 위치/구도 (v6 improved_margin_analyzer.py 전체 이식)
    private func evaluatePosition(
        bbox: CGRect,
        imageSize: CGSize,
        referenceBBox: CGRect?,
        referenceImageSize: CGSize?,
        isFrontCamera: Bool,
        currentKeypoints: [PoseKeypoint]? = nil,    // 🆕 v6
        referenceKeypoints: [PoseKeypoint]? = nil   // 🆕 v6
    ) -> GateResult {

        // 🆕 v8: Keypoint Alignment 우선 시도 (정확도 높음)
        if let currentKP = currentKeypoints, let refKP = referenceKeypoints,
           let kpResult = evaluateKeypointAlignment(current: currentKP, reference: refKP, isFrontCamera: isFrontCamera) {
            return kpResult
        }

        // 🔥 실시간 최적화: 위치 분석에 YOLOX BBox 직접 사용
        // - 키포인트 정렬이 안 될 때 Fallback으로 YOLOX BBox 여백 분석
        // - YOLOX는 매 프레임 갱신되므로 실시간 피드백 가능
        // (기존: 키포인트 BBox 계산 → 제거하고 YOLOX BBox 직접 사용)

        // Fallback: YOLOX BBox 기반 여백 분석 (실시간)
        let curMargins = marginAnalyzer.analyze(bbox: bbox, imageSize: imageSize)

        var score: CGFloat = 1.0
        var feedback = "인물 위치가 레퍼런스와 잘 맞습니다"
        var feedbackParts: [String] = []
        
        // 디버그 정보
        var debugDetails: String = "Cur Margins: L\(String(format: "%.2f", curMargins.leftRatio)) R\(String(format: "%.2f", curMargins.rightRatio)) T\(String(format: "%.2f", curMargins.topRatio)) B\(String(format: "%.2f", curMargins.bottomRatio))"

        // 🆕 v6: 프레임 밖 경고 우선 표시
        if let warning = curMargins.outOfFrameWarning {
            feedbackParts.append(warning)
        }

        if let refBBox = referenceBBox, let refSize = referenceImageSize {
            // 🔥 실시간 최적화: 레퍼런스도 YOLOX BBox 직접 사용 (일관성)
            // (키포인트 BBox 계산 제거)

            // 레퍼런스와 비교 (YOLOX BBox 사용)
            let refMargins = marginAnalyzer.analyze(bbox: refBBox, imageSize: refSize)
            debugDetails += "\n      Ref Margins: L\(String(format: "%.2f", refMargins.leftRatio)) R\(String(format: "%.2f", refMargins.rightRatio)) T\(String(format: "%.2f", refMargins.topRatio)) B\(String(format: "%.2f", refMargins.bottomRatio))"

            // 🆕 v6: 좌우 균형 분석 (Python _analyze_horizontal_balance)
            let horizontalResult = analyzeHorizontalBalance(
                curMargins: curMargins, refMargins: refMargins, isFrontCamera: isFrontCamera
            )
            score = horizontalResult.score

            if let horizontalFeedback = horizontalResult.feedback {
                feedbackParts.append(horizontalFeedback)
            }

            // 🆕 v6: 상하 균형 분석 + 틸트 (Python _analyze_vertical_balance)
            let verticalResult = analyzeVerticalBalance(
                curMargins: curMargins, refMargins: refMargins, isFrontCamera: isFrontCamera
            )
            score = (score + verticalResult.score) / 2.0

            if let verticalFeedback = verticalResult.feedback {
                feedbackParts.append(verticalFeedback)
            }

            // 🆕 v6: 하단 특별 분석 (Python _analyze_bottom_special)
            let bottomResult = analyzeBottomSpecial(
                curMargins: curMargins, refMargins: refMargins
            )
            score = score * 0.7 + bottomResult.score * 0.3  // 하단 30% 가중치

            if let bottomFeedback = bottomResult.feedback {
                feedbackParts.append(bottomFeedback)
            }

        } else {
            // 절대 평가: 3분할 선 기준 (YOLOX BBox 사용 - 실시간)
            let centerX = bbox.midX
            let centerY = bbox.midY
            let thirdLines: [CGFloat] = [1.0/3.0, 0.5, 2.0/3.0]

            let minHorizontalDistance = thirdLines.map { abs(centerX - $0) }.min() ?? 0.5
            let minVerticalDistance = thirdLines.map { abs(centerY - $0) }.min() ?? 0.5

            let horizontalScore = max(0, 1.0 - (minHorizontalDistance / 0.2))
            let verticalScore = max(0, 1.0 - (minVerticalDistance / 0.2))
            score = (horizontalScore + verticalScore) / 2.0

            if score < thresholds.position {
                let targetX = thirdLines.min(by: { abs($0 - centerX) < abs($1 - centerX) }) ?? 0.5
                let targetY = thirdLines.min(by: { abs($0 - centerY) < abs($1 - centerY) }) ?? 0.5

                if centerX < targetX - 0.05 {
                    feedbackParts.append(isFrontCamera
                        ? "피사체를 화면의 왼쪽으로 이동하세요"
                        : "피사체를 화면의 오른쪽으로 이동하세요")
                } else if centerX > targetX + 0.05 {
                    feedbackParts.append(isFrontCamera
                        ? "피사체를 화면의 오른쪽으로 이동하세요"
                        : "피사체를 화면의 왼쪽으로 이동하세요")
                }

                if centerY < targetY - 0.05 {
                    feedbackParts.append("피사체를 화면의 아래쪽으로 이동하세요")
                } else if centerY > targetY + 0.05 {
                    feedbackParts.append("피사체를 화면의 위쪽으로 이동하세요")
                }
            }
        }

        if !feedbackParts.isEmpty {
            feedback = feedbackParts.joined(separator: "\n")
        }

        return GateResult(
            name: "위치",
            score: score,
            threshold: thresholds.position,
            feedback: feedback,
            icon: "↔️",
            category: "position",
            debugInfo: debugDetails
        )
    }

    // 🆕 v6: 좌우 균형 분석 (Python _analyze_horizontal_balance 이식)
    private struct BalanceAnalysisResult {
        let score: CGFloat
        let feedback: String?
    }

    private func analyzeHorizontalBalance(
        curMargins: MarginAnalysisResult,
        refMargins: MarginAnalysisResult,
        isFrontCamera: Bool
    ) -> BalanceAnalysisResult {

        // Python: curr_balance = curr['left'] - curr['right']
        let currBalance = curMargins.leftRatio - curMargins.rightRatio
        let refBalance = refMargins.leftRatio - refMargins.rightRatio

        // Python: center_shift = curr_balance - ref_balance
        let centerShift = currBalance - refBalance

        // 임계값 (Python thresholds)
        let perfect: CGFloat = 0.05
        let good: CGFloat = 0.10
        let needsAdjustment: CGFloat = 0.15

        // 점수 계산
        let score: CGFloat
        if abs(centerShift) < perfect {
            score = 0.95
        } else if abs(centerShift) < good {
            score = 0.85
        } else if abs(centerShift) < needsAdjustment {
            score = 0.70
        } else {
            score = max(0.50, 0.85 - abs(centerShift))
        }

        // 피드백 생성 (Python: camera_action + person_action)
        var feedback: String? = nil
        if abs(centerShift) > good {
            let percent = min(50, Int(abs(centerShift) * 100))
            let steps = toSteps(percent: CGFloat(percent))  // 🆕 걸음수 변환

            if centerShift > 0 {
                // 현재가 더 왼쪽 치우침 → 오른쪽으로 이동
                feedback = isFrontCamera
                    ? "오른쪽으로 \(steps) 이동 (\(percent)%)"
                    : "왼쪽으로 \(steps) 이동 (\(percent)%)"
            } else {
                // 현재가 더 오른쪽 치우침 → 왼쪽으로 이동
                feedback = isFrontCamera
                    ? "왼쪽으로 \(steps) 이동 (\(percent)%)"
                    : "오른쪽으로 \(steps) 이동 (\(percent)%)"
            }
        }

        return BalanceAnalysisResult(score: score, feedback: feedback)
    }

    // 🆕 v6: 상하 균형 분석 + 틸트 (Python _analyze_vertical_balance 이식)
    private func analyzeVerticalBalance(
        curMargins: MarginAnalysisResult,
        refMargins: MarginAnalysisResult,
        isFrontCamera: Bool
    ) -> BalanceAnalysisResult {

        // Python: 인물의 절대 위치 (0=상단, 1=하단)
        let currPosition = curMargins.personVerticalPosition
        let refPosition = refMargins.personVerticalPosition

        // Python: position_diff = curr_position - ref_position
        let positionDiff = currPosition - refPosition

        // 임계값
        let perfect: CGFloat = 0.05
        let good: CGFloat = 0.10
        let needsAdjustment: CGFloat = 0.15

        // 점수 계산
        let score: CGFloat
        if abs(positionDiff) < perfect {
            score = 0.95
        } else if abs(positionDiff) < good {
            score = 0.85
        } else if abs(positionDiff) < needsAdjustment {
            score = 0.70
        } else {
            score = max(0.50, 0.85 - abs(positionDiff))
        }

        // 피드백 생성 (틸트 + 인물 행동)
        var feedback: String? = nil
        if abs(positionDiff) > good {
            // Python: _to_tilt_angle
            let tiltAngle = toTiltAngle(percent: abs(positionDiff) * 100)

            if positionDiff > 0 {
                // 현재가 더 아래에 위치 (상단 여백 많음) - Python 로직
                if curMargins.isHighAngle {
                    // 하이앵글 + 인물 아래 = 카메라 낮추고 평행하게
                    // Python: camera_action + person_action
                    feedback = isFrontCamera
                        ? "카메라를 낮추고 \(tiltAngle)° 평행하게 (또는 프레임 아래로 이동)"
                        : "카메라를 낮추고 \(tiltAngle)° 평행하게"
                } else {
                    // 평행 앵글 + 인물 아래 = 틸트 다운
                    // Python: person_action = "앉거나 자세를 낮추기"
                    feedback = isFrontCamera
                        ? "카메라를 \(tiltAngle)° 아래로 틸트 (또는 자세를 낮추기)"
                        : "카메라를 \(tiltAngle)° 아래로 틸트"
                }
            } else {
                // 현재가 더 위에 위치 (하단 여백 많음)
                // Python: person_action = "일어서거나 자세를 높이기"
                feedback = isFrontCamera
                    ? "카메라를 \(tiltAngle)° 위로 틸트 (또는 자세를 높이기)"
                    : "카메라를 \(tiltAngle)° 위로 틸트"
            }
        }

        return BalanceAnalysisResult(score: score, feedback: feedback)
    }

    // 🆕 v6: 하단 특별 분석 (Python _analyze_bottom_special 이식)
    private func analyzeBottomSpecial(
        curMargins: MarginAnalysisResult,
        refMargins: MarginAnalysisResult
    ) -> BalanceAnalysisResult {

        let currBottom = curMargins.bottomRatio
        let refBottom = refMargins.bottomRatio

        // Python: 하단 여백 차이
        let diff = abs(currBottom - refBottom)

        // 점수 계산
        let score: CGFloat
        if diff < 0.05 {
            score = 0.95
        } else if diff < 0.10 {
            score = 0.85
        } else if diff < 0.15 {
            score = 0.75
        } else {
            score = max(0.60, 0.90 - diff)
        }

        // 특별 케이스 피드백 (Python: table_heavy, too_much_bottom 등)
        var feedback: String? = nil

        // Python: table_heavy = curr_bottom < -0.1 (하단 10% 이상 잘림)
        if currBottom < -0.1 {
            feedback = "하단이 잘렸어요. 카메라를 위로 들거나 뒤로 물러나세요"
        }
        // Python: too_much_bottom = curr_bottom > ref_bottom + 0.15
        else if currBottom > refBottom + 0.15 {
            feedback = "하단 여백이 너무 많아요. 카메라를 아래로 내리세요"
        }
        // Python: too_little_bottom = curr_bottom < ref_bottom - 0.15
        else if currBottom < refBottom - 0.15 {
            feedback = "하단 여백이 부족해요. 카메라를 위로 올리세요"
        }

        return BalanceAnalysisResult(score: score, feedback: feedback)
    }

    // 🆕 v6: 퍼센트를 틸트 각도로 변환 (Python _to_tilt_angle)
    private func toTiltAngle(percent: CGFloat) -> Int {
        if percent < 5 {
            return 2
        } else if percent < 10 {
            return 5
        } else if percent < 15 {
            return 8
        } else if percent < 20 {
            return 10
        } else {
            return min(15, Int(percent * 0.5))
        }
    }

    // 🆕 v6: 퍼센트를 걸음수로 변환 (Python _to_steps 이식)
    private func toSteps(percent: CGFloat) -> String {
        if percent < 5 {
            return "아주 조금"
        } else if percent < 10 {
            return "반 걸음"
        } else if percent < 20 {
            return "한 걸음"
        } else if percent < 30 {
            return "두 걸음"
        } else if percent < 40 {
            return "세 걸음"
        } else {
            return "네 걸음 이상"
        }
    }

    // 🆕 단순화된 줌 체크 (목표 줌 vs 현재 줌만 비교)
    private func evaluateZoomSimple(currentZoom: CGFloat, targetZoom: CGFloat) -> GateResult {
        let zoomRatio = currentZoom / targetZoom
        let diff = abs(1.0 - zoomRatio)

        // 점수 계산 (오차가 적을수록 높은 점수)
        let score = max(0, 1.0 - diff)

        // 피드백 생성
        let feedback: String
        let passed = diff <= zoomTolerance

        if passed {
            feedback = "✓ 줌 OK (\(String(format: "%.1fx", currentZoom)))"
        } else if currentZoom < targetZoom {
            // 줌인 필요
            feedback = "\(String(format: "%.1fx", targetZoom))로 줌인해주세요 (현재 \(String(format: "%.1fx", currentZoom)))"
        } else {
            // 줌아웃 필요
            feedback = "\(String(format: "%.1fx", targetZoom))로 줌아웃해주세요 (현재 \(String(format: "%.1fx", currentZoom)))"
        }

        return GateResult(
            name: "압축감",
            score: score,
            threshold: 1.0 - zoomTolerance,  // 허용 오차 내면 통과
            feedback: feedback,
            icon: "🔭",
            category: "compression",
            debugInfo: "Zoom: \(String(format: "%.1fx", currentZoom)) vs Target: \(String(format: "%.1fx", targetZoom))"
        )
    }

    // MARK: - Gate 3: 압축감 - 단순화 (목표 줌 vs 현재 줌)
    private func evaluateCompression(
        currentIndex: CGFloat?,
        referenceIndex: CGFloat?,
        currentFocal: FocalLengthInfo?,
        referenceFocal: FocalLengthInfo?,
        currentKeypoints: [PoseKeypoint],
        referenceKeypoints: [PoseKeypoint]
    ) -> GateResult {

        // 🆕 단순화: 목표 줌이 설정되어 있으면 현재 줌과 비교만
        if let target = targetZoomFactor {
            return evaluateZoomSimple(currentZoom: currentZoomFactor, targetZoom: target)
        }

        // 🆕 35mm 환산 초점거리 우선 사용 (목표 줌 미설정 시 fallback)
        if let currentFL = currentFocal {
            return evaluateCompressionByFocalLength(
                current: currentFL,
                reference: referenceFocal,
                currentKeypoints: currentKeypoints,
                referenceKeypoints: referenceKeypoints
            )
        }

        // Fallback: 기존 compressionIndex 방식
        guard let current = currentIndex else {
            return GateResult(
                name: "압축감",
                score: 0.0,
                threshold: thresholds.compression,
                feedback: "깊이 정보를 분석 중입니다...",
                icon: "🔭",
                category: "compression"
            )
        }

        // 렌즈 타입 판별 함수 (레거시)
        func describeLensType(_ value: CGFloat) -> (name: String, type: String) {
            if value < 0.3 {
                return ("광각렌즈", "wide")
            } else if value < 0.45 {
                return ("준광각", "semi-wide")
            } else if value < 0.6 {
                return ("표준렌즈", "normal")
            } else if value < 0.75 {
                return ("중망원", "medium-tele")
            } else {
                return ("망원렌즈", "telephoto")
            }
        }

        let currentLens = describeLensType(current)
        var score: CGFloat = 1.0
        var feedback = "압축감이 레퍼런스와 유사합니다 (\(currentLens.name))"

        if let reference = referenceIndex {
            let referenceLens = describeLensType(reference)
            let diff = abs(current - reference)
            let diffPercent = Int(diff * 100)

            score = max(0, 1.0 - (diff / 0.5))

            if diff >= 0.15 {
                if current < reference {
                    feedback = "배경 압축이 부족해요. 줌인하거나 \(max(1, diffPercent / 10))걸음 가까이 가세요 (현재: \(currentLens.name) → 목표: \(referenceLens.name))"
                } else {
                    feedback = "배경이 너무 압축되어요. 줌아웃하거나 \(max(1, diffPercent / 10))걸음 뒤로 가세요 (현재: \(currentLens.name) → 목표: \(referenceLens.name))"
                }
            }
        } else {
            // 🔧 레퍼런스 없으면 압축감 비교 불가능 → 무조건 Pass
            // 절대 평가 제거 (초기 상태에서 불필요한 피드백 방지)
            score = 1.0
            feedback = "레퍼런스 없음 (현재: \(currentLens.name))"
        }

        return GateResult(
            name: "압축감",
            score: score,
            threshold: thresholds.compression,
            feedback: feedback,
            icon: "🔭",
            category: "compression"
        )
    }

    // 🆕 35mm 환산 초점거리 기반 압축감 평가
    private func evaluateCompressionByFocalLength(
        current: FocalLengthInfo,
        reference: FocalLengthInfo?,
        currentKeypoints: [PoseKeypoint],
        referenceKeypoints: [PoseKeypoint]
    ) -> GateResult {

        let currentMM = current.focalLength35mm
        let currentLens = current.lensType

        // 🔧 v8 Refactor: 레퍼런스 초점거리 정보가 없으면 평가 생략하되,
        // AI 추정값(.depthEstimate)이 있으면 평가를 진행 (User Request)
        // .fallback(기본값 50mm)인 경우에만 평가 생략 (Soft Pass)
        guard let ref = reference else {
            // 아예 데이터가 없는 경우
            return createSkippedCompressionResult(currentMM)
        }
        
        // 🆕 Fallback(단순 추측)인 경우에만 생략
        if ref.source == .fallback {
            print("📐 [압축감] 레퍼런스 EXIF 없음 & 뎁스 추정 실패 → 평가 생략 (Score 1.0)")
            return createSkippedCompressionResult(currentMM)
        }

        // Helper to convert % difference to "steps"
        func toSteps(percent: CGFloat) -> Int {
            return max(1, Int(round(percent * 10))) // 10% diff = 1 step
        }
        
        var isDistanceMismatch = false // 🆕 Scope fix: Declare early
        
        let refMM = ref.focalLength35mm
        
        var score: CGFloat = 1.0
        var feedback = "\(currentMM)mm \(currentLens.displayName)으로 촬영 중"

        let diff = abs(currentMM - refMM)

        // 🆕 AI 추정값 사용 시 신뢰도 반영 (감점 요인 X, 정보 표시용)
        let isEstimated = ref.source == .depthEstimate || ref.confidence < 0.8
        let reliabilityIcon = isEstimated ? "🪄" : "📸"

        // 🔧 임계값: EXIF 15mm, AI 추정 30mm (추정 불확실성 고려)
        // 초기 진입 시 사용자 줌 선호도 존중 (1x ↔ 2x 차이 허용)
        let diffThreshold: Int = isEstimated ? 30 : 15

        if diff > diffThreshold {
            // 차이 큼 → 점수 계산 및 피드백 생성
            score = max(0, 1.0 - CGFloat(diff) / 50.0)
            let targetZoom = CGFloat(refMM) / CGFloat(FocalLengthEstimator.iPhoneBaseFocalLength)
            let zoomText = String(format: "%.1fx", targetZoom)

            // 🔥 통합 피드백: 거리도 함께 체크하여 힌트 제공
            var distanceHint = ""  // "많이", "조금만", ""

            if let currStruct = BodyStructure.extract(from: currentKeypoints),
               let refStruct = BodyStructure.extract(from: referenceKeypoints),
               currStruct.lowestTier == refStruct.lowestTier {
                let scaleRatio = currStruct.spanY / max(0.01, refStruct.spanY)

                if currentMM < refMM {
                    // 줌인 필요 → 뒤로 가야 피사체 크기 유지
                    if scaleRatio > 1.3 {
                        distanceHint = "많이 "  // 이미 너무 가까움
                    } else if scaleRatio < 0.85 {
                        distanceHint = "조금만 "  // 너무 멈
                    }
                } else {
                    // 줌아웃 필요 → 앞으로 가야 피사체 크기 유지
                    if scaleRatio > 1.15 {
                        distanceHint = "조금만 "  // 이미 가까움
                    } else if scaleRatio < 0.7 {
                        distanceHint = "많이 "  // 너무 멈
                    }
                }
            }

            if currentMM < refMM {
                // 현재가 더 광각 (예: 24mm) vs 목표가 망원 (예: 50mm)
                // 원근감이 너무 강함 → 뒤로 물러나서(원근감 줄임) + 줌인(피사체 크기 유지)
                feedback = "📐 \(distanceHint)뒤로 물러나서 \(zoomText)로 줌인 (배경 압축)"
            } else {
                // 현재가 더 망원 (예: 70mm) vs 목표가 광각 (예: 24mm)
                // 원근감이 너무 없음 → 앞으로 다가가서(원근감 강조) + 줌아웃(피사체 크기 유지)
                feedback = "📐 \(distanceHint)앞으로 다가가서 \(zoomText)로 줌아웃 (원근감 강조)"
            }

            // 추정값인 경우 표시 (User Feedback 반영)
            if isEstimated {
                feedback += " [AI 추정]"
            }
        } else {
            // Lens Focal Length Matches (< 10mm Diff) -> Now Check Scale/Distance
            
            // var isDistanceMismatch = false <- Removed (declared at top)
            
            // 🆕 Distance Consistency Check
            if let currStruct = BodyStructure.extract(from: currentKeypoints),
               let refStruct = BodyStructure.extract(from: referenceKeypoints) {
                
                // Only if Tiers match (e.g. both Full Body)
                if currStruct.lowestTier == refStruct.lowestTier {
                    let scaleRatio = currStruct.spanY / max(0.01, refStruct.spanY)
                    let scaleDiff = abs(1.0 - scaleRatio)
                     
                    // Tolerance 15% (Strict but fair)
                    if scaleDiff > 0.15 {
                        isDistanceMismatch = true
                        
                        // Penalty
                        score = max(0.2, score - scaleDiff) // Significantly degrade score
                        
                        let steps = toSteps(percent: scaleDiff * 50)
                        if scaleRatio > 1.0 {
                            feedback = "렌즈는 비슷하지만 너무 가깝습니다. 뒤로 \(steps) 물러나세요 (원근감 불일치)"
                        } else {
                            feedback = "렌즈는 비슷하지만 너무 멉니다. 앞으로 \(steps) 다가가세요 (원근감 불일치)"
                        }
                    }
                    
                    // 🔧 DEBUG LOGGING (Inside scope)
                    // if isDistanceMismatch { ... } // 불필요하게 복잡해지지 않도록 통합
                    // print("   🔭 [Gate 3 Distance Check] ...")
                    if isDistanceMismatch {
                         print("   🔭 [Gate 3 Distance Check] FAIL: Scale Diff \(String(format: "%.2f", abs(1.0 - (currStruct.spanY)/(max(0.01, refStruct.spanY))))) > 15%")
                    }
                }
            }
            
            if !isDistanceMismatch {
                // 차이가 적음 & 거리도 비슷함 -> 유사함
                feedback = "✓ 압축감/거리 완벽함 (\(currentMM)mm)"
                if isEstimated { feedback += " \(reliabilityIcon)" }
            }
        }

        // 🆕 항상 디버그 출력
        // print("📐 [압축감(\(ref.source))] 현재:\(currentMM)mm vs 목표:\(refMM)mm → 점수:\(String(format: "%.2f", score))")

        return GateResult(
            name: "압축감",
            score: score,
            threshold: thresholds.compression,
            feedback: feedback,
            icon: "🔭",
            category: "compression",
            debugInfo: "Lens: \(currentMM)mm vs \(refMM)mm (\(isDistanceMismatch ? "DistMismatch" : "DistOK"))"
        )
    }
    
    // 🆕 Helper: 압축감 평가 생략 결과 생성
    private func createSkippedCompressionResult(_ currentMM: Int) -> GateResult {
        return GateResult(
            name: "압축감",
            score: 1.0,
            threshold: thresholds.compression,
            feedback: "레퍼런스 렌즈 정보 없음 (현재: \(currentMM)mm)",
            icon: "🔭",
            category: "compression_skipped"
        )
    }

    // MARK: - Gate 4: 포즈
    private func evaluatePose(
        poseComparison: PoseComparisonResult?,
        isFrontCamera: Bool,
        hasCurrentPerson: Bool = true  // 🆕 현재 프레임에 인물 있는지
    ) -> GateResult {

        // 🆕 현재 프레임에 인물이 없으면 우선 피드백
        guard hasCurrentPerson else {
            return GateResult(
                name: "포즈",
                score: 0.0,
                threshold: thresholds.pose,
                feedback: "인물이 검출되지 않습니다. 프레임 안에 들어오세요",
                icon: "🤸",
                category: "pose"
            )
        }

        guard let pose = poseComparison else {
            // 🔧 수정: 포즈 비교 결과 없음 - 통과가 아닌 대기 상태
            return GateResult(
                name: "포즈",
                score: 0.0,  // 🔧 1.0 → 0.0 (미통과)
                threshold: thresholds.pose,
                feedback: "포즈를 분석 중입니다...",
                icon: "🤸",
                category: "pose"
            )
        }

        // 전체 정확도를 점수로 사용
        let score = CGFloat(pose.overallAccuracy)

        // 각도 차이가 큰 부위 찾기
        let angleDiffThreshold: Float = thresholds.poseAngleThreshold
        var feedbackParts: [String] = []

        // 우선순위 순서로 체크
        let priorityParts = ["shoulder_tilt", "face", "left_arm", "right_arm", "left_leg", "right_leg"]

        for part in priorityParts {
            if let diff = pose.angleDifferences[part], abs(diff) > angleDiffThreshold {
                // angleDirections에서 구체적인 메시지 가져오기
                if let direction = pose.angleDirections[part] {
                    feedbackParts.append(direction)
                } else {
                    // fallback
                    switch part {
                    case "shoulder_tilt":
                        feedbackParts.append("몸 기울기 조정")
                    case "face":
                        feedbackParts.append("고개 방향 조정")
                    case "left_arm":
                        feedbackParts.append("왼팔 각도 조정")
                    case "right_arm":
                        feedbackParts.append("오른팔 각도 조정")
                    case "left_leg":
                        feedbackParts.append("왼다리 각도 조정")
                    case "right_leg":
                        feedbackParts.append("오른다리 각도 조정")
                    default:
                        break
                    }
                }

                // 최대 2개만 표시
                if feedbackParts.count >= 2 { break }
            }
        }

        // 🔧 v6: missingGroups "잘렸어요" 피드백 제거
        // 상반신샷에서 다리가 안 보이는 건 정상이므로, 샷타입과 무관하게 표시하면 혼란스러움
        // Python v6에서도 이런 피드백은 없음 - 샷타입 분석에서 처리
        // (필요시 currentShotType을 파라미터로 받아 필터링 가능)

        let feedback = feedbackParts.isEmpty ? "포즈 일치" : feedbackParts.joined(separator: ", ")

        return GateResult(
            name: "포즈",
            score: score,
            threshold: thresholds.pose,
            feedback: feedback,
            icon: "🤸",
            category: "pose"
        )
    }

    // MARK: - 🆕 v8 Robust Keypoint Alignment Logic (RTMPose 133 Support)
    
    private struct BodyStructure {
        let centroid: CGPoint
        let topAnchorY: CGFloat
        let spanY: CGFloat
        let lowestTier: Int // 0:Shoulder, 1:Hip, 2:Knee, 3:Ankle
        
        static func extract(from keypoints: [PoseKeypoint]) -> BodyStructure? {
            // Helper: Safe Keypoint Access
            func getPoint(_ idx: Int) -> CGPoint? {
                guard idx < keypoints.count, keypoints[idx].confidence > 0.3 else { return nil }
                return keypoints[idx].location
            }
            
            // 1. Dynamic Centroid (Robust to occlusion)
            // Candidates: Nose(0), Eyes(1,2), Ears(3,4), Shoulders(5,6), Hips(11,12)
            // RTMPose 133: Hands(91-132), Feet(17-22), Face(23-90) included if highly confident
            
            var validPoints: [CGPoint] = []
            
            // Body & Head Anchors
            let coreIndices = [0, 1, 2, 3, 4, 5, 6, 11, 12]
            for idx in coreIndices {
                if let p = getPoint(idx) { validPoints.append(p) }
            }
            
            // If body is sparse, try face contour for head center (Back view/Side view fallback)
            if validPoints.count < 3 {
                for idx in 23...90 { // Face alignment
                     if let p = getPoint(idx) { validPoints.append(p) }
                }
            }
            
            guard !validPoints.isEmpty else { return nil }
            
            let centroidX = validPoints.reduce(0) { $0 + $1.x } / CGFloat(validPoints.count)
            let centroidY = validPoints.reduce(0) { $0 + $1.y } / CGFloat(validPoints.count)
            
            // 2. Vertical Span & Topology Tier
            // Determines "Lowest Visible Part" to ensure we compare apples to apples.
            
            var lowestY: CGFloat?
            var currentTier = 0
            
            // Check Tier 3: Ankles/Feet (Full Shot)
            let feetIndices = [15, 16] + Array(17...22)
            if let maxFeet = feetIndices.compactMap({ getPoint($0)?.y }).max() {
                lowestY = maxFeet
                currentTier = 3
            } 
            // Check Tier 2: Knees (American Shot)
            else if let maxKnee = [13, 14].compactMap({ getPoint($0)?.y }).max() {
                lowestY = maxKnee
                currentTier = 2
            }
            // Check Tier 1: Hips (Medium Shot)
            else if let maxHip = [11, 12].compactMap({ getPoint($0)?.y }).max() {
                lowestY = maxHip
                currentTier = 1
            }
            // Tier 0: Shoulders (Close Up) - Fallback
            else {
                lowestY = [5, 6].compactMap({ getPoint($0)?.y }).max()
                currentTier = 0
            }
            
            guard let bottomY = lowestY else { return nil }
            
            // Top Anchor: Nose > Eyes > Ears > Head Top (Face Contour Min)
            let topCandidates = [0, 1, 2, 3, 4]
            var topY = topCandidates.compactMap({ getPoint($0)?.y }).min()
            
            if topY == nil {
                // Fallback to face contour or shoulders
                topY = (Array(23...90) + [5, 6]).compactMap({ getPoint($0)?.y }).min()
            }
            
            guard let validTopY = topY else { return nil }
            
            return BodyStructure(
                centroid: CGPoint(x: centroidX, y: centroidY),
                topAnchorY: validTopY,
                spanY: bottomY - validTopY,
                lowestTier: currentTier
            )
        }
    }
    
    private func evaluateKeypointAlignment(
        current: [PoseKeypoint],
        reference: [PoseKeypoint],
        isFrontCamera: Bool
    ) -> GateResult? {
        guard let currStruct = BodyStructure.extract(from: current),
              let refStruct = BodyStructure.extract(from: reference) else {
            return nil
        }
        
        var score: CGFloat = 1.0
        var feedbackParts: [String] = []
        
        // 1. Horizontal Alignment (Centroid X)
        let diffX = currStruct.centroid.x - refStruct.centroid.x
        let thresholdX: CGFloat = 0.05
        
        if abs(diffX) > thresholdX {
            let percent = Int(abs(diffX) * 100)
            let steps = toSteps(percent: CGFloat(percent))
            
            if diffX > 0 {
                // Live Right -> Move Left
                 if isFrontCamera {
                     feedbackParts.append("왼쪽으로 \(steps) 이동")
                } else {
                     feedbackParts.append("카메라를 오른쪽으로 이동") // Camera Right -> Subject Left
                }
            } else {
                // Live Left -> Move Right
                 if isFrontCamera {
                     feedbackParts.append("오른쪽으로 \(steps) 이동")
                } else {
                     feedbackParts.append("카메라를 왼쪽으로 이동")
                }
            }
            score -= abs(diffX) * 2.0
        }
        
        // 2. Topology Check & Vertical Scale
        // Only compare Scale if Tiers match (e.g. both are Full Shots).
        // If mismatched (e.g. Full vs Upper), Scale comparison is invalid.
        
        if currStruct.lowestTier == refStruct.lowestTier {
            let scaleRatio = currStruct.spanY / max(0.01, refStruct.spanY)
            let scaleDiff = abs(1.0 - scaleRatio)
            
            if scaleDiff > 0.08 { // 8% difference
                score -= scaleDiff
                let steps = toSteps(percent: scaleDiff * 50)
                
                if scaleRatio > 1.0 {
                    // Too Big -> Move Back
                    feedbackParts.append(isFrontCamera ? "뒤로 \(steps) 가세요" : "뒤로 물러나세요")
                } else {
                    // Too Small -> Move Forward
                    feedbackParts.append(isFrontCamera ? "앞으로 \(steps) 가세요" : "가까이 다가가세요")
                }
                
                // If scale is way off, skip Tilt check
                if scaleDiff > 0.25 {
                     return GateResult(
                        name: "위치(거리)",
                        score: max(0.2, score),
                        threshold: thresholds.position,
                        feedback: feedbackParts.joined(separator: "\n"),
                        icon: "↔️",
                        category: "position_keypoint"
                    )
                }
            }
        }
        
        // 3. Vertical Tilt (Top Anchor)
        // Only valid if Scale is roughly correct OR Tier matches
        let diffY = currStruct.topAnchorY - refStruct.topAnchorY
        
        if abs(diffY) > 0.05 {
             let angle = toTiltAngle(percent: abs(diffY) * 100)
             score -= abs(diffY) * 2.0
             
             if diffY > 0 {
                 // Live Lower -> Tilt DOWN
                 feedbackParts.append("카메라를 \(angle)° 아래로 틸트")
             } else {
                 // Live Higher -> Tilt UP
                 feedbackParts.append("카메라를 \(angle)° 위로 틸트")
             }
        }
        
        if feedbackParts.isEmpty {
            return GateResult(
                name: "위치",
                score: 1.0,
                threshold: thresholds.position,
                feedback: "✓ 위치/크기 완벽함",
                icon: "✨",
                category: "position_perfect"
            )
        }
        
        return GateResult(
            name: "위치",
            score: max(0.1, score),
            threshold: thresholds.position,
            feedback: feedbackParts.joined(separator: "\n"),
            icon: "↔️",
            category: "position_keypoint"
        )
    }
}

// MARK: - Gate System 싱글톤
extension GateSystem {
    static let shared = GateSystem()
}
