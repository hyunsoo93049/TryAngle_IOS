import Foundation
import CoreGraphics

// MARK: - 개별 Gate 결과
public struct GateResult: Equatable {
    public let name: String
    public let score: CGFloat      // 0.0 ~ 1.0
    public let threshold: CGFloat  // 통과 기준
    public let passed: Bool
    public let feedback: String
    public let feedbackIcon: String  // 피드백 아이콘
    public let category: String      // 피드백 카테고리
    public let debugInfo: String?    // 🆕 디버그용 추가 정보
    public let metadata: [String: Any]? // 🆕 메타데이터 (ShotType 등 전달용)

    public init(name: String, score: CGFloat, threshold: CGFloat, feedback: String, icon: String = "📸", category: String = "general", debugInfo: String? = nil, metadata: [String: Any]? = nil) {
        self.name = name
        self.score = score
        self.threshold = threshold
        self.passed = score >= threshold
        self.feedback = feedback
        self.feedbackIcon = icon
        self.category = category
        self.debugInfo = debugInfo
        self.metadata = metadata
    }
    
    // Equatable: Ignore metadata dictionary for comparison (not equatable)
    public static func == (lhs: GateResult, rhs: GateResult) -> Bool {
        return lhs.name == rhs.name &&
               lhs.score == rhs.score &&
               lhs.passed == rhs.passed &&
               lhs.feedback == rhs.feedback
    }
    
    public var debugDescription: String {
        return "   [\(name)] \(passed ? "✅ PASS" : "❌ FAIL") (\(String(format: "%.0f%%", score * 100)))\n      - Feedback: \(feedback)\n      - Debug: \(debugInfo ?? "N/A")"
    }
}

// MARK: - 샷 타입 (Phase 3에서 가져옴)
public enum ShotTypeGate: Int, CaseIterable {
    case extremeCloseUp = 0  // 익스트림 클로즈업 (눈만)
    case closeUp = 1         // 클로즈업 (얼굴)
    case mediumCloseUp = 2   // 미디엄 클로즈업 (어깨)
    case mediumShot = 3      // 미디엄 샷 (허리)
    case americanShot = 4    // 아메리칸 샷 (무릎)
    case mediumFullShot = 5  // 미디엄 풀샷 (무릎 아래)
    case fullShot = 6        // 풀샷 (전신)
    case longShot = 7        // 롱샷 (전신 + 배경)

    public var displayName: String {
        switch self {
        case .extremeCloseUp: return "초근접샷"
        case .closeUp: return "얼굴샷"
        case .mediumCloseUp: return "바스트샷"
        case .mediumShot: return "허리샷"
        case .americanShot: return "허벅지샷"
        case .mediumFullShot: return "무릎샷"
        case .fullShot: return "전신샷"
        case .longShot: return "원거리 전신샷"
        }
    }
    
    // 🆕 v9: 피드백용 가이드 문구 (Target: 보이게 조정하세요)
    public var guideDescription: String {
        switch self {
        case .extremeCloseUp: return "이목구비가 꽉 차게"
        case .closeUp: return "얼굴 전체가 나오게"
        case .mediumCloseUp: return "가슴과 어깨까지 나오게"
        case .mediumShot: return "허리까지 나오게"
        case .americanShot: return "허벅지 중간까지 나오게"
        case .mediumFullShot: return "무릎 아래까지 나오게"
        case .fullShot: return "머리부터 발끝까지 전신이 나오게"
        case .longShot: return "전신과 배경이 넓게 나오게"
        }
    }
    
    // 🆕 v9: 특징 부위 문구 (Current: ~가 보입니다/안 보입니다)
    public var featureDescription: String {
        switch self {
        case .extremeCloseUp: return "이목구비"
        case .closeUp: return "얼굴"
        case .mediumCloseUp: return "가슴/어깨"
        case .mediumShot: return "허리"
        case .americanShot: return "허벅지"
        case .mediumFullShot: return "무릎"
        case .fullShot: return "발/전신"
        case .longShot: return "배경"
        }
    }

    /// BBox 높이 비율로 샷 타입 추정 (fallback용)
    public static func fromBBoxHeight(_ heightRatio: CGFloat) -> ShotTypeGate {
        // heightRatio: BBox 높이 / 이미지 높이
        if heightRatio > 0.9 { return .fullShot }
        if heightRatio > 0.75 { return .mediumFullShot }
        if heightRatio > 0.6 { return .americanShot }
        if heightRatio > 0.45 { return .mediumShot }
        if heightRatio > 0.3 { return .mediumCloseUp }
        if heightRatio > 0.15 { return .closeUp }
        return .extremeCloseUp
    }

    /// 🔥 v6 (Python framing_analyzer.py 로직 이식)
    /// 핵심: 가장 낮은 보이는 신체 부위(lowest_part)를 순차 탐색하는 방식
    /// - 팔꿈치 유무로 medium_shot vs bust_shot 정확히 구분
    /// - 얼굴 랜드마크 개수로 closeup vs mediumCloseUp 구분
    public static func fromKeypoints(_ keypoints: [PoseKeypoint], confidenceThreshold: Float = 0.3) -> ShotTypeGate {
        guard keypoints.count >= 17 else {
            return .mediumShot
        }

        // Helper: Is Visible & Valid
        func isVisible(_ idx: Int, threshold: Float = confidenceThreshold) -> Bool {
            guard idx < keypoints.count else { return false }
            let kp = keypoints[idx]
            return kp.confidence > threshold &&
                   kp.location.y >= 0.0 && kp.location.y <= 1.05
        }

        // 🔥 v6 핵심: 가장 낮은 보이는 신체 부위 찾기 (Python의 lowest_part 로직)
        var lowestY: CGFloat = 0.0
        var lowestPart = "face"

        // 체크할 부위들 (순서대로: 얼굴 → 어깨 → 팔꿈치 → 엉덩이 → 무릎 → 발목)
        let checkParts: [(name: String, indices: [Int])] = [
            ("face", [0]),              // 코
            ("shoulder", [5, 6]),       // 어깨
            ("elbow", [7, 8]),          // 팔꿈치
            ("hip", [11, 12]),          // 엉덩이
            ("knee", [13, 14]),         // 무릎
            ("ankle", [15, 16])         // 발목
        ]

        // 각 부위별로 가장 낮은 Y 좌표 찾기
        for (partName, indices) in checkParts {
            for idx in indices {
                if isVisible(idx) {
                    let y = keypoints[idx].location.y
                    if y > lowestY {
                        lowestY = y
                        lowestPart = partName
                    }
                }
            }
        }

        // 발 키포인트 별도 체크 (17-22, 엄격한 임계값)
        let hasFeet = keypoints.count > 22 &&
                      (17...22).contains(where: { isVisible($0, threshold: 0.5) })

        // 얼굴 키포인트 개수 (23-90)
        let faceCount = keypoints.count > 90 ?
                        (23...90).filter { isVisible($0) }.count : 0

        // 🔥 v6 방식: 최하단 부위로 샷타입 결정
        if lowestPart == "ankle" || hasFeet {
            // 발목이나 발이 보임 → 전신샷
            return .fullShot

        } else if lowestPart == "knee" {
            // 무릎이 최하단 → 무릎샷
            return .mediumFullShot

        } else if lowestPart == "hip" {
            // 🔥 v6 핵심: 팔꿈치 유무로 medium vs american 구분
            let hasElbows = isVisible(7) || isVisible(8)
            if hasElbows {
                // 엉덩이 + 팔꿈치 보임 → 미디엄샷 (허리샷)
                return .mediumShot
            } else {
                // 엉덩이만 보임 → 아메리칸샷 (허벅지샷)
                return .americanShot
            }

        } else if lowestPart == "elbow" {
            // 팔꿈치가 최하단 → 바스트샷
            return .mediumCloseUp

        } else if lowestPart == "shoulder" {
            // 🔥 v6 방식: 얼굴 랜드마크 개수로 구분
            if faceCount > 50 {
                // 어깨 + 많은 얼굴 랜드마크 → 클로즈업
                return .closeUp
            } else {
                // 어깨만 보임 → 바스트샷
                return .mediumCloseUp
            }

        } else {
            // 얼굴만 보임 → 익스트림 클로즈업
            return .extremeCloseUp
        }
    }

    /// 🔥 v6 (Python v6 방식): 키포인트에서 BBox 계산
    /// v6는 모든 분석(샷타입, 크기, 여백)을 키포인트 기반으로 일관되게 처리
    /// - YOLOX BBox는 crop용으로만 사용, 분석에는 키포인트 BBox 사용
    public static func calculateKeypointBBox(_ keypoints: [PoseKeypoint], confidenceThreshold: Float = 0.3) -> CGRect? {
        var allPoints: [CGPoint] = []

        // Body keypoints (0-16) - v6와 동일
        for i in 0...16 {
            guard i < keypoints.count else { break }
            let kp = keypoints[i]
            if kp.confidence > confidenceThreshold {
                allPoints.append(kp.location)
            }
        }

        // Face landmarks (23-90) - v6와 동일
        for i in 23...min(90, keypoints.count - 1) {
            let kp = keypoints[i]
            if kp.confidence > confidenceThreshold {
                allPoints.append(kp.location)
            }
        }

        // 최소 5개 키포인트 필요 (v6 로직)
        guard allPoints.count >= 5 else { return nil }

        let xs = allPoints.map { $0.x }
        let ys = allPoints.map { $0.y }

        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else {
            return nil
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
}

// MARK: - 전체 Gate 평가 결과
public struct GateEvaluation: Equatable {
    public let gate0: GateResult // 비율
    public let gate1: GateResult // 프레임
    public let gate2: GateResult // 위치
    public let gate3: GateResult // 압축감
    public let gate4: GateResult // 포즈

    public let currentShotType: ShotTypeGate?
    public let referenceShotType: ShotTypeGate?

    public init(
        gate0: GateResult,
        gate1: GateResult,
        gate2: GateResult,
        gate3: GateResult,
        gate4: GateResult,
        currentShotType: ShotTypeGate? = nil,
        referenceShotType: ShotTypeGate? = nil
    ) {
        self.gate0 = gate0
        self.gate1 = gate1
        self.gate2 = gate2
        self.gate3 = gate3
        self.gate4 = gate4
        self.currentShotType = currentShotType
        self.referenceShotType = referenceShotType
    }

    // MARK: - Computed Properties (기존 GateSystem 호환)

    public var allPassed: Bool {
        return gate0.passed && gate1.passed && gate2.passed && gate3.passed && gate4.passed
    }

    public var passedCount: Int {
        return [gate0, gate1, gate2, gate3, gate4].filter { $0.passed }.count
    }

    public var overallScore: CGFloat {
        let scores = [gate0.score, gate1.score, gate2.score, gate3.score, gate4.score]
        return scores.reduce(0, +) / CGFloat(scores.count)
    }

    /// 통과 못한 첫 번째 Gate의 피드백 반환 (우선순위 기반)
    /// 우선순위: 비율 → 프레이밍 → 위치 → 포즈 → 압축감
    public var primaryFeedback: String {
        if !gate0.passed { return gate0.feedback }  // 1. 비율 (필수)
        if !gate1.passed { return gate1.feedback }  // 2. 프레이밍 (샷타입/크기)
        if !gate2.passed { return gate2.feedback }  // 3. 위치 (좌우/상하)
        if !gate4.passed { return gate4.feedback }  // 4. 포즈
        if !gate3.passed { return gate3.feedback }  // 5. 압축감 (미세조정)
        return "✓ 완벽한 구도입니다!"
    }

    public var allFeedbacks: [String] {
        return [gate0, gate1, gate2, gate3, gate4]
            .filter { !$0.passed }
            .map { $0.feedback }
    }

    /// 현재 실패한 Gate 번호 (모두 통과 시 nil)
    /// 우선순위: 비율 → 프레이밍 → 위치 → 포즈 → 압축감
    public var currentFailedGate: Int? {
        if !gate0.passed { return 0 }  // 비율
        if !gate1.passed { return 1 }  // 프레이밍
        if !gate2.passed { return 2 }  // 위치
        if !gate4.passed { return 4 }  // 포즈
        if !gate3.passed { return 3 }  // 압축감
        return nil
    }
    
    // 이전 GateSystem에 있던 디버그 요약 로직 이식
    public var debugSummary: String {
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

        // 실패한 게이트 중 가장 낮은 우선순위(번호) 피드백 표시
        // (Gate 0, 1, 2, 3, 4 순서)
        var failedInfo = "→ 완벽!"
        for (_, gate) in gates {
            if !gate.passed {
                failedInfo = "→ \(gate.feedback)"
                break
            }
        }

        return "🎯 [\(gateStatus)] \(failedInfo)"
    }
}
