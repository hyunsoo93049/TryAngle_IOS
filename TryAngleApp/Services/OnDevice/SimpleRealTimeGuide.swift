//
//  SimpleRealTimeGuide.swift
//  단순화된 실시간 가이드 시스템
//  "레퍼런스와 비슷한 구도 만들기"에 집중
//
//  작성일: 2025-12-11
//
//  핵심 철학:
//  - 3단계 가이드 (프레임 진입 → 크기 맞추기 → 위치 조정)
//  - 줌/압축감은 실시간에서 제외 (사용자가 실시간으로 조정 불가)
//  - 레퍼런스와 "비슷한 느낌 구도"가 목표
//

import Foundation
import CoreGraphics

// MARK: - 가이드 타입
enum GuideType: String, CaseIterable {
    case enterFrame = "프레임 진입"       // 인물이 화면에 없음
    case moveForward = "앞으로"           // 인물이 작음
    case moveBackward = "뒤로"            // 인물이 큼
    case moveLeft = "왼쪽으로"            // 인물이 오른쪽에 치우침
    case moveRight = "오른쪽으로"         // 인물이 왼쪽에 치우침
    case tiltUp = "위로 틸트"             // 인물이 아래에 있음
    case tiltDown = "아래로 틸트"         // 인물이 위에 있음
    case zoomIn = "줌인"                  // 줌 배율 증가 필요
    case zoomOut = "줌아웃"               // 줌 배율 감소 필요
    case adjustPose = "포즈 조정"         // 포즈 조정 필요
    case perfect = "완벽"                 // 모든 조건 충족

    var icon: String {
        switch self {
        case .enterFrame: return "👤"
        case .moveForward: return "🚶"
        case .moveBackward: return "🚶"
        case .moveLeft: return "◀️"
        case .moveRight: return "▶️"
        case .tiltUp: return "⬆️"
        case .tiltDown: return "⬇️"
        case .zoomIn: return "🔍"
        case .zoomOut: return "🔭"
        case .adjustPose: return "🤸"
        case .perfect: return "✨"
        }
    }
}

// MARK: - 피드백 단계 (UI 표시용)
enum FeedbackStage: String {
    case frameEntry = "프레임 진입"
    case shotType = "샷타입"         // 크기/거리 조정
    case position = "위치"           // 좌우/상하 위치 조정
    case zoom = "줌"                 // 줌 배율 조정
    case pose = "포즈"               // 포즈 조정
    case perfect = "완벽"            // 모든 조건 충족

    var displayName: String {
        return rawValue
    }

    var icon: String {
        switch self {
        case .frameEntry: return "👤"
        case .shotType: return "📸"
        case .position: return "↔️"
        case .zoom: return "🔍"
        case .pose: return "🤸"
        case .perfect: return "✅"
        }
    }

    var color: String {
        switch self {
        case .frameEntry: return "red"
        case .shotType: return "orange"
        case .position: return "purple"
        case .zoom: return "cyan"
        case .pose: return "pink"
        case .perfect: return "green"
        }
    }
}

// MARK: - 가이드 결과
struct SimpleGuideResult: Equatable {
    let guide: GuideType
    let magnitude: String           // "반 걸음", "한 걸음", "조금" 등
    let progress: CGFloat           // 0.0 ~ 1.0 (전체 진행률)
    let debugInfo: String           // 디버그용 정보
    let shotTypeMatch: Bool         // 샷타입 일치 여부
    let currentShotType: String     // 현재 샷타입 이름
    let targetShotType: String      // 목표 샷타입 이름
    let feedbackStage: FeedbackStage // 피드백 단계 (UI 표시용)

    // 🆕 v6 스타일 상세 정보
    let tiltAngle: Int?             // 틸트 각도 (2°, 5°, 8°, 10°, 15°)
    let positionPercent: Int?       // 이동 퍼센트 (예: 15%)
    let currentZoom: CGFloat?       // 현재 줌 배율
    let targetZoom: CGFloat?        // 목표 줌 배율

    // Equatable 준수를 위한 기본값 초기화
    init(
        guide: GuideType,
        magnitude: String,
        progress: CGFloat,
        debugInfo: String,
        shotTypeMatch: Bool,
        currentShotType: String,
        targetShotType: String,
        feedbackStage: FeedbackStage,
        tiltAngle: Int? = nil,
        positionPercent: Int? = nil,
        currentZoom: CGFloat? = nil,
        targetZoom: CGFloat? = nil
    ) {
        self.guide = guide
        self.magnitude = magnitude
        self.progress = progress
        self.debugInfo = debugInfo
        self.shotTypeMatch = shotTypeMatch
        self.currentShotType = currentShotType
        self.targetShotType = targetShotType
        self.feedbackStage = feedbackStage
        self.tiltAngle = tiltAngle
        self.positionPercent = positionPercent
        self.currentZoom = currentZoom
        self.targetZoom = targetZoom
    }

    // 🆕 사용자 표시용 메시지 (v6 스타일 - 각도/퍼센트 포함)
    var displayMessage: String {
        switch guide {
        case .enterFrame:
            return "화면 안에 들어오세요"
        case .moveForward:
            return "\(magnitude) 앞으로 다가가세요"
        case .moveBackward:
            return "\(magnitude) 뒤로 물러나세요"
        case .moveLeft:
            if let percent = positionPercent {
                return "\(magnitude) 오른쪽으로 이동 (\(percent)%)"
            }
            return "\(magnitude) 오른쪽으로 이동하세요"
        case .moveRight:
            if let percent = positionPercent {
                return "\(magnitude) 왼쪽으로 이동 (\(percent)%)"
            }
            return "\(magnitude) 왼쪽으로 이동하세요"
        case .tiltUp:
            if let angle = tiltAngle {
                return "카메라를 \(angle)° 위로 틸트"
            }
            return "카메라를 위로 올리세요"
        case .tiltDown:
            if let angle = tiltAngle {
                return "카메라를 \(angle)° 아래로 틸트"
            }
            return "카메라를 아래로 내리세요"
        case .zoomIn:
            if let target = targetZoom, let current = currentZoom {
                return "\(String(format: "%.1fx", target))로 줌인 (현재 \(String(format: "%.1fx", current)))"
            }
            return "줌인해주세요"
        case .zoomOut:
            if let target = targetZoom, let current = currentZoom {
                return "\(String(format: "%.1fx", target))로 줌아웃 (현재 \(String(format: "%.1fx", current)))"
            }
            return "줌아웃해주세요"
        case .adjustPose:
            return "포즈를 레퍼런스처럼 맞춰주세요"
        case .perfect:
            return "완벽한 구도입니다!"
        }
    }

    // 샷타입 상태 메시지
    var shotTypeStatus: String {
        if shotTypeMatch {
            return "샷타입 OK (\(currentShotType))"
        } else {
            return "현재:\(currentShotType)을 레퍼런스:\(targetShotType)처럼 맞추세요"
        }
    }

    // 안정적 ID (SwiftUI용)
    var stableId: String {
        return "\(guide.rawValue)_\(magnitude)"
    }
}

// MARK: - 단순 실시간 가이드 시스템
class SimpleRealTimeGuide {

    static let shared = SimpleRealTimeGuide()

    // MARK: - 레퍼런스 정보 (캐시)
    private var refPersonHeight: CGFloat = 0       // 레퍼런스 인물 높이 (정규화)
    private var refPersonCenterX: CGFloat = 0.5    // 레퍼런스 인물 중심 X
    private var refPersonCenterY: CGFloat = 0.5    // 레퍼런스 인물 중심 Y
    private var refShotType: ShotTypeGate = .mediumShot  // 레퍼런스 샷타입
    private var refKeypoints: [PoseKeypoint]?      // 레퍼런스 키포인트
    private var refZoomFactor: CGFloat?            // 🆕 레퍼런스 줌 배율

    // MARK: - 허용 오차 설정
    private let sizeTolerancePercent: CGFloat = 0.20   // 크기 오차 20%
    private let positionToleranceX: CGFloat = 0.08     // 좌우 위치 오차 8%
    private let positionToleranceY: CGFloat = 0.08     // 상하 위치 오차 8%
    private let minPersonHeight: CGFloat = 0.05        // 최소 인물 높이 5%
    private let zoomTolerance: CGFloat = 0.15          // 줌 오차 15%
    private let poseThreshold: CGFloat = 0.70          // 🆕 포즈 일치 임계값 70%
    private var enablePoseCheck: Bool = true           // 🆕 포즈 체크 활성화 여부

    // MARK: - 안정화 (히스테리시스)
    private var lastGuide: GuideType = .enterFrame
    private var lastGuideTime: Date = .distantPast
    private var sameGuideCount: Int = 0
    private let stabilityThreshold: Int = 2            // 2번 연속 같아야 변경
    private let minGuideInterval: TimeInterval = 0.2   // 최소 0.2초 간격

    // 🆕 샷타입 안정화 (급격한 변화 방지)
    private var stableShotType: ShotTypeGate?          // 안정화된 현재 샷타입
    private var shotTypeChangeCount: Int = 0           // 동일 샷타입 연속 감지 횟수
    private let shotTypeStabilityThreshold: Int = 3    // 3회 연속 동일해야 변경

    // MARK: - 디버그
    private var lastDebugLogTime: Date = .distantPast
    private let debugLogInterval: TimeInterval = 0.5

    private init() {}

    // MARK: - 레퍼런스 설정

    /// 레퍼런스 이미지 정보 설정
    /// - Parameters:
    ///   - keypoints: 레퍼런스 이미지의 포즈 키포인트
    ///   - imageSize: 레퍼런스 이미지 크기
    ///   - zoomFactor: 레퍼런스 이미지 촬영 시 줌 배율 (옵션)
    func setReference(keypoints: [PoseKeypoint], imageSize: CGSize, zoomFactor: CGFloat? = nil) {
        guard !keypoints.isEmpty else {
            print("⚠️ [SimpleGuide] 레퍼런스 키포인트 없음")
            return
        }

        self.refKeypoints = keypoints
        self.refZoomFactor = zoomFactor  // 🆕 줌 배율 저장

        // 키포인트에서 BBox 계산
        if let bbox = ShotTypeGate.calculateKeypointBBox(keypoints) {
            refPersonHeight = bbox.height
            refPersonCenterX = bbox.midX
            refPersonCenterY = bbox.midY

            print("📸 [SimpleGuide] 레퍼런스 설정: 높이=\(String(format: "%.2f", refPersonHeight)), 중심=(\(String(format: "%.2f", refPersonCenterX)), \(String(format: "%.2f", refPersonCenterY)))")
        }

        // 샷타입 결정
        if keypoints.count >= 17 {
            refShotType = ShotTypeGate.fromKeypoints(keypoints)
            print("📸 [SimpleGuide] 레퍼런스 샷타입: \(refShotType.displayName)")
        }

        if let zoom = zoomFactor {
            print("📸 [SimpleGuide] 레퍼런스 줌: \(String(format: "%.1fx", zoom))")
        }
    }

    /// 레퍼런스 초기화
    func clearReference() {
        refPersonHeight = 0
        refPersonCenterX = 0.5
        refPersonCenterY = 0.5
        refShotType = .mediumShot
        refKeypoints = nil
        refZoomFactor = nil  // 🆕 줌 초기화
        lastGuide = .enterFrame
        sameGuideCount = 0
        // 샷타입 안정화 변수 초기화
        stableShotType = nil
        shotTypeChangeCount = 0
        print("🔄 [SimpleGuide] 레퍼런스 초기화됨")
    }

    // MARK: - 메인 평가 함수

    /// 현재 프레임 평가
    /// - Parameters:
    ///   - currentKeypoints: 현재 프레임의 키포인트
    ///   - hasPersonDetected: 인물 감지 여부
    ///   - isFrontCamera: 전면 카메라 여부
    ///   - currentZoom: 현재 카메라 줌 배율 (옵션)
    /// - Returns: 가이드 결과
    func evaluate(
        currentKeypoints: [PoseKeypoint],
        hasPersonDetected: Bool,
        isFrontCamera: Bool = false,
        currentZoom: CGFloat? = nil
    ) -> SimpleGuideResult {

        // 레퍼런스 없으면 기본 가이드
        guard refPersonHeight > 0 else {
            return createResult(
                guide: .enterFrame,
                magnitude: "",
                progress: 0,
                debugInfo: "레퍼런스 미설정",
                shotTypeMatch: false,
                currentShotType: "없음",
                targetShotType: refShotType.displayName,
                feedbackStage: .frameEntry
            )
        }

        // ========================================
        // Guide 1: 프레임 진입 체크
        // ========================================
        guard hasPersonDetected, !currentKeypoints.isEmpty else {
            return stabilizeGuide(
                createResult(
                    guide: .enterFrame,
                    magnitude: "",
                    progress: 0,
                    debugInfo: "인물 미감지",
                    shotTypeMatch: false,
                    currentShotType: "없음",
                    targetShotType: refShotType.displayName,
                    feedbackStage: .frameEntry
                )
            )
        }

        // 현재 키포인트에서 BBox 계산
        guard let currentBBox = ShotTypeGate.calculateKeypointBBox(currentKeypoints) else {
            return stabilizeGuide(
                createResult(
                    guide: .enterFrame,
                    magnitude: "",
                    progress: 0.1,
                    debugInfo: "BBox 계산 실패",
                    shotTypeMatch: false,
                    currentShotType: "측정불가",
                    targetShotType: refShotType.displayName,
                    feedbackStage: .frameEntry
                )
            )
        }

        // 인물이 너무 작으면 (프레임 밖에 있는 것처럼)
        if currentBBox.height < minPersonHeight {
            return stabilizeGuide(
                createResult(
                    guide: .enterFrame,
                    magnitude: "",
                    progress: 0.1,
                    debugInfo: "인물 너무 작음: \(String(format: "%.2f", currentBBox.height))",
                    shotTypeMatch: false,
                    currentShotType: "너무 멂",
                    targetShotType: refShotType.displayName,
                    feedbackStage: .frameEntry
                )
            )
        }

        // 현재 샷타입 (원시값)
        let rawShotType = currentKeypoints.count >= 17
            ? ShotTypeGate.fromKeypoints(currentKeypoints)
            : ShotTypeGate.fromBBoxHeight(currentBBox.height)

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
                currentShotType = rawShotType
            } else {
                // 아직 안정화 안됨 → 이전 값 유지
                currentShotType = stableShotType ?? rawShotType
            }
        }

        // ========================================
        // Guide 2: 샷타입 맞추기 (앞/뒤 이동)
        // ========================================
        // 🔧 샷타입 기반 방향 결정 (rawValue 사용)
        // - rawValue가 작을수록 클로즈업 (가까움)
        // - rawValue가 클수록 전신샷 (멂)
        // 예: 무릎샷(5) → 전신샷(6) = 뒤로 가야 함
        //     허리샷(3) → 전신샷(6) = 뒤로 가야 함
        //     전신샷(6) → 허리샷(3) = 앞으로 가야 함

        let shotTypeDiff = currentShotType.rawValue - refShotType.rawValue
        // shotTypeDiff < 0: 현재가 더 가까움 → 뒤로 가야 함
        // shotTypeDiff > 0: 현재가 더 멂 → 앞으로 가야 함
        // shotTypeDiff == 0: 샷타입 일치

        // 샷타입 일치 여부
        let shotTypeMatch = currentShotType == refShotType

        // 샷타입 거리 (얼마나 다른지)
        let shotTypeDistance = abs(shotTypeDiff)
        let shotTypeScore: CGFloat = 1.0 - min(CGFloat(shotTypeDistance) / 7.0, 1.0)

        // 샷타입이 다르면 방향 피드백
        if !shotTypeMatch {
            let magnitude = getMagnitudeFromShotTypeDistance(shotTypeDistance)

            if shotTypeDiff < 0 {
                // 현재가 더 가까움 (예: 무릎샷 vs 전신샷) → 뒤로 물러나야 함
                return stabilizeGuide(
                    createResult(
                        guide: .moveBackward,
                        magnitude: magnitude,
                        progress: 0.3 + shotTypeScore * 0.3,
                        debugInfo: "샷타입 \(currentShotType.displayName) → \(refShotType.displayName)",
                        shotTypeMatch: false,
                        currentShotType: currentShotType.displayName,
                        targetShotType: refShotType.displayName,
                        feedbackStage: .shotType
                    )
                )
            } else {
                // 현재가 더 멂 (예: 전신샷 vs 허리샷) → 앞으로 다가가야 함
                return stabilizeGuide(
                    createResult(
                        guide: .moveForward,
                        magnitude: magnitude,
                        progress: 0.3 + shotTypeScore * 0.3,
                        debugInfo: "샷타입 \(currentShotType.displayName) → \(refShotType.displayName)",
                        shotTypeMatch: false,
                        currentShotType: currentShotType.displayName,
                        targetShotType: refShotType.displayName,
                        feedbackStage: .shotType
                    )
                )
            }
        }

        // ========================================
        // 샷타입 일치 → 다음 단계(위치)로 진행
        // ========================================

        // ========================================
        // Guide 3: 위치 조정 (좌우/상하)
        // ========================================
        let currentCenterX = currentBBox.midX
        let currentCenterY = currentBBox.midY

        // 좌우 차이 (전면 카메라는 미러링 고려)
        var diffX = currentCenterX - refPersonCenterX
        if isFrontCamera {
            diffX = -diffX  // 전면 카메라는 반전
        }

        // 상하 차이
        let diffY = currentCenterY - refPersonCenterY

        // 위치 점수
        let positionScoreX: CGFloat = 1.0 - min(abs(diffX) / 0.5, 1.0)
        let positionScoreY: CGFloat = 1.0 - min(abs(diffY) / 0.5, 1.0)
        let positionScore = (positionScoreX + positionScoreY) / 2.0

        // 좌우 조정이 필요한 경우
        if abs(diffX) > positionToleranceX {
            let magnitude = getMagnitudePosition(diff: abs(diffX))
            let guide: GuideType = diffX > 0 ? .moveLeft : .moveRight
            let percent = min(50, Int(abs(diffX) * 100))  // 🆕 퍼센트 계산

            return stabilizeGuide(
                createResult(
                    guide: guide,
                    magnitude: magnitude,
                    progress: 0.6 + positionScore * 0.2,
                    debugInfo: "좌우 차이: \(String(format: "%.0f", diffX * 100))%",
                    shotTypeMatch: shotTypeMatch,
                    currentShotType: currentShotType.displayName,
                    targetShotType: refShotType.displayName,
                    feedbackStage: .position,
                    positionPercent: percent  // 🆕 v6 스타일 퍼센트 추가
                )
            )
        }

        // 상하 조정이 필요한 경우 (틸트 각도 포함)
        if abs(diffY) > positionToleranceY {
            let guide: GuideType = diffY > 0 ? .tiltUp : .tiltDown
            let tiltAngle = toTiltAngle(percent: abs(diffY) * 100)  // 🆕 틸트 각도 계산

            return stabilizeGuide(
                createResult(
                    guide: guide,
                    magnitude: "",
                    progress: 0.6 + positionScore * 0.1,
                    debugInfo: "상하 차이: \(String(format: "%.0f", diffY * 100))%",
                    shotTypeMatch: shotTypeMatch,
                    currentShotType: currentShotType.displayName,
                    targetShotType: refShotType.displayName,
                    feedbackStage: .position,
                    tiltAngle: tiltAngle  // 🆕 v6 스타일 각도 추가
                )
            )
        }

        // ========================================
        // Guide 4: 크기 조정 (앞/뒤 이동)
        // ========================================
        let currentHeight = currentBBox.height
        let targetHeight = refPersonHeight
        let sizeRatio = currentHeight / max(targetHeight, 0.01)
        let sizeScore: CGFloat = 1.0 - min(abs(1.0 - sizeRatio), 1.0)

        if sizeRatio < (1.0 - sizeTolerancePercent) {
            // 현재가 작음 → 앞으로 이동
            let magnitude = getMagnitude(diff: 1.0 - sizeRatio)
            return stabilizeGuide(
                createResult(
                    guide: .moveForward,
                    magnitude: magnitude,
                    progress: 0.7 + sizeScore * 0.2,
                    debugInfo: "크기 \(String(format: "%.0f", sizeRatio * 100))% (목표 100%)",
                    shotTypeMatch: true,
                    currentShotType: currentShotType.displayName,
                    targetShotType: refShotType.displayName,
                    feedbackStage: .zoom  // 크기 조정은 zoom 단계로 표시
                )
            )
        } else if sizeRatio > (1.0 + sizeTolerancePercent) {
            // 현재가 큼 → 뒤로 이동
            let magnitude = getMagnitude(diff: sizeRatio - 1.0)
            return stabilizeGuide(
                createResult(
                    guide: .moveBackward,
                    magnitude: magnitude,
                    progress: 0.7 + sizeScore * 0.2,
                    debugInfo: "크기 \(String(format: "%.0f", sizeRatio * 100))% (목표 100%)",
                    shotTypeMatch: true,
                    currentShotType: currentShotType.displayName,
                    targetShotType: refShotType.displayName,
                    feedbackStage: .zoom  // 크기 조정은 zoom 단계로 표시
                )
            )
        }

        // ========================================
        // Guide 5: 줌 배율 체크 (카메라 줌)
        // ========================================
        if let targetZoom = refZoomFactor, let curZoom = currentZoom {
            let zoomRatio = curZoom / targetZoom
            let zoomDiff = abs(1.0 - zoomRatio)

            if zoomDiff > zoomTolerance {
                if curZoom < targetZoom {
                    // 줌인 필요
                    return stabilizeGuide(
                        createResult(
                            guide: .zoomIn,
                            magnitude: "",
                            progress: 0.85,
                            debugInfo: "줌 \(String(format: "%.1fx", curZoom)) → \(String(format: "%.1fx", targetZoom))",
                            shotTypeMatch: true,
                            currentShotType: currentShotType.displayName,
                            targetShotType: refShotType.displayName,
                            feedbackStage: .zoom,
                            currentZoom: curZoom,
                            targetZoom: targetZoom
                        )
                    )
                } else {
                    // 줌아웃 필요
                    return stabilizeGuide(
                        createResult(
                            guide: .zoomOut,
                            magnitude: "",
                            progress: 0.85,
                            debugInfo: "줌 \(String(format: "%.1fx", curZoom)) → \(String(format: "%.1fx", targetZoom))",
                            shotTypeMatch: true,
                            currentShotType: currentShotType.displayName,
                            targetShotType: refShotType.displayName,
                            feedbackStage: .zoom,
                            currentZoom: curZoom,
                            targetZoom: targetZoom
                        )
                    )
                }
            }
        }

        // ========================================
        // Guide 6: 포즈 체크 (마지막 단계)
        // ========================================
        if enablePoseCheck, let refKps = refKeypoints, refKps.count >= 17, currentKeypoints.count >= 17 {
            let poseSimilarity = calculatePoseSimilarity(current: currentKeypoints, reference: refKps)

            if poseSimilarity < poseThreshold {
                return stabilizeGuide(
                    createResult(
                        guide: .adjustPose,
                        magnitude: "",
                        progress: 0.90,
                        debugInfo: "포즈 유사도: \(String(format: "%.0f", poseSimilarity * 100))%",
                        shotTypeMatch: true,
                        currentShotType: currentShotType.displayName,
                        targetShotType: refShotType.displayName,
                        feedbackStage: .pose
                    )
                )
            }
        }

        // ========================================
        // 완벽! 모든 조건 충족
        // ========================================
        return stabilizeGuide(
            createResult(
                guide: .perfect,
                magnitude: "",
                progress: 1.0,
                debugInfo: "샷타입 OK, 위치 OK, 크기 OK, 줌 OK, 포즈 OK",
                shotTypeMatch: true,
                currentShotType: currentShotType.displayName,
                targetShotType: refShotType.displayName,
                feedbackStage: .perfect
            )
        )
    }

    // MARK: - 헬퍼 함수

    /// 결과 생성 (v6 스타일 상세 정보 포함)
    private func createResult(
        guide: GuideType,
        magnitude: String,
        progress: CGFloat,
        debugInfo: String,
        shotTypeMatch: Bool,
        currentShotType: String,
        targetShotType: String,
        feedbackStage: FeedbackStage,
        tiltAngle: Int? = nil,
        positionPercent: Int? = nil,
        currentZoom: CGFloat? = nil,
        targetZoom: CGFloat? = nil
    ) -> SimpleGuideResult {
        return SimpleGuideResult(
            guide: guide,
            magnitude: magnitude,
            progress: progress,
            debugInfo: debugInfo,
            shotTypeMatch: shotTypeMatch,
            currentShotType: currentShotType,
            targetShotType: targetShotType,
            feedbackStage: feedbackStage,
            tiltAngle: tiltAngle,
            positionPercent: positionPercent,
            currentZoom: currentZoom,
            targetZoom: targetZoom
        )
    }

    /// 🆕 v6: 퍼센트를 틸트 각도로 변환 (Python _to_tilt_angle 이식)
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

    /// 차이에 따른 크기 설명 (앞뒤 이동)
    private func getMagnitude(diff: CGFloat) -> String {
        if diff < 0.15 {
            return "조금"
        } else if diff < 0.30 {
            return "반 걸음"
        } else if diff < 0.50 {
            return "한 걸음"
        } else {
            return "두 걸음"
        }
    }

    /// 차이에 따른 크기 설명 (좌우 이동)
    private func getMagnitudePosition(diff: CGFloat) -> String {
        if diff < 0.10 {
            return "조금"
        } else if diff < 0.20 {
            return "반 걸음"
        } else {
            return "한 걸음"
        }
    }

    /// 샷타입 거리에 따른 이동량 설명
    /// - Parameter distance: 샷타입 rawValue 차이 (0~7)
    private func getMagnitudeFromShotTypeDistance(_ distance: Int) -> String {
        switch distance {
        case 1:
            return "조금"
        case 2:
            return "반 걸음"
        case 3...4:
            return "한 걸음"
        default:
            return "두 걸음"
        }
    }

    /// 🆕 포즈 유사도 계산 (정규화된 키포인트 비교)
    /// - Returns: 0.0 ~ 1.0 (1.0이 완전 일치)
    private func calculatePoseSimilarity(current: [PoseKeypoint], reference: [PoseKeypoint]) -> CGFloat {
        // 주요 신체 부위 인덱스 (COCO 17 keypoints 기준)
        // 0: nose, 5-6: shoulders, 7-8: elbows, 9-10: wrists, 11-12: hips, 13-14: knees, 15-16: ankles
        let importantIndices = [0, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]

        // BBox로 정규화
        guard let curBBox = ShotTypeGate.calculateKeypointBBox(current),
              let refBBox = ShotTypeGate.calculateKeypointBBox(reference) else {
            return 0.5  // 계산 실패 시 중간값
        }

        var totalScore: CGFloat = 0
        var validCount: CGFloat = 0

        for idx in importantIndices {
            guard idx < current.count, idx < reference.count else { continue }

            let curKp = current[idx]
            let refKp = reference[idx]

            // 낮은 신뢰도 키포인트는 건너뜀
            if curKp.confidence < 0.3 || refKp.confidence < 0.3 { continue }

            // BBox 기준 정규화된 상대 위치 계산
            let curRelX = (curKp.location.x - curBBox.minX) / max(curBBox.width, 0.01)
            let curRelY = (curKp.location.y - curBBox.minY) / max(curBBox.height, 0.01)

            let refRelX = (refKp.location.x - refBBox.minX) / max(refBBox.width, 0.01)
            let refRelY = (refKp.location.y - refBBox.minY) / max(refBBox.height, 0.01)

            // 유클리드 거리 계산
            let dx = curRelX - refRelX
            let dy = curRelY - refRelY
            let distance = sqrt(dx * dx + dy * dy)

            // 거리를 점수로 변환 (거리가 작을수록 높은 점수)
            // 거리 0 = 1.0, 거리 0.5 이상 = 0.0
            let score = max(0, 1.0 - distance * 2)
            totalScore += score
            validCount += 1
        }

        guard validCount > 0 else { return 0.5 }
        return totalScore / validCount
    }

    /// 가이드 안정화 (히스테리시스)
    private func stabilizeGuide(_ newResult: SimpleGuideResult) -> SimpleGuideResult {
        let now = Date()

        // 동일 가이드 카운트
        if newResult.guide == lastGuide {
            sameGuideCount += 1
        } else {
            sameGuideCount = 1
        }

        // 안정화 조건: 일정 횟수 이상 동일해야 변경
        let shouldChange = sameGuideCount >= stabilityThreshold ||
                           now.timeIntervalSince(lastGuideTime) > 1.0  // 1초 지나면 강제 변경

        if shouldChange && newResult.guide != lastGuide {
            lastGuide = newResult.guide
            lastGuideTime = now

            // 디버그 로그
            if now.timeIntervalSince(lastDebugLogTime) > debugLogInterval {
                print("🎯 [SimpleGuide] \(newResult.guide.icon) \(newResult.displayMessage) | \(newResult.debugInfo)")
                lastDebugLogTime = now
            }
        }

        return newResult
    }
}

// MARK: - PoseKeypoint Extension (기존 호환성)
extension PoseKeypoint {
    /// tuple에서 변환
    init(from tuple: (point: CGPoint, confidence: Float)) {
        self.init(location: tuple.point, confidence: tuple.confidence)
    }
}
