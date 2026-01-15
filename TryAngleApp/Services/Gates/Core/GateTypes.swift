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
    public let debugInfo: String?    // 🆕 디버그용 추가 정보 (사용자 요청)

    public init(name: String, score: CGFloat, threshold: CGFloat, feedback: String, icon: String = "📸", category: String = "general", debugInfo: String? = nil) {
        self.name = name
        self.score = score
        self.threshold = threshold
        self.passed = score >= threshold
        self.feedback = feedback
        self.feedbackIcon = icon
        self.category = category
        self.debugInfo = debugInfo
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
