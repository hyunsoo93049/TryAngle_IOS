import Foundation
import CoreGraphics

// MARK: - 구도 타입 분류
enum CompositionType: Equatable {
    // 3분할 구도 (Rule of Thirds) - 9개 영역
    case ruleOfThirdsLeftUpper      // 왼쪽 상단 교점
    case ruleOfThirdsRightUpper     // 오른쪽 상단 교점
    case ruleOfThirdsLeftLower      // 왼쪽 하단 교점
    case ruleOfThirdsRightLower     // 오른쪽 하단 교점
    case ruleOfThirdsCenter         // 중앙 (4개 교점 중심)

    // 황금비율 구도 (Golden Ratio)
    case goldenRatioLeft            // 황금비율 왼쪽
    case goldenRatioRight           // 황금비율 오른쪽
    case goldenRatioUpper           // 황금비율 상단
    case goldenRatioLower           // 황금비율 하단

    // 중앙 집중 구도
    case centerFocus                // 정중앙

    // 커스텀 구도
    case custom(position: CGPoint)  // 사용자 정의 위치

    var description: String {
        switch self {
        case .ruleOfThirdsLeftUpper:
            return "왼쪽 위"
        case .ruleOfThirdsRightUpper:
            return "오른쪽 위"
        case .ruleOfThirdsLeftLower:
            return "왼쪽 아래"
        case .ruleOfThirdsRightLower:
            return "오른쪽 아래"
        case .ruleOfThirdsCenter:
            return "화면 중앙"
        case .goldenRatioLeft:
            return "조금 왼쪽"
        case .goldenRatioRight:
            return "조금 오른쪽"
        case .goldenRatioUpper:
            return "조금 위쪽"
        case .goldenRatioLower:
            return "조금 아래쪽"
        case .centerFocus:
            return "화면 정중앙"
        case .custom:
            return "현재 위치"
        }
    }
}

// MARK: - 구도 분석기
class CompositionAnalyzer {

    // 허용 오차 (%)
    private let ruleOfThirdsTolerance: CGFloat = 0.08  // 8%
    private let goldenRatioTolerance: CGFloat = 0.08   // 8%
    private let centerTolerance: CGFloat = 0.15        // 15%

    // 황금비율 상수
    private let goldenRatio: CGFloat = 0.618  // (√5 - 1) / 2 ≈ 0.618

    /// 피사체 위치로부터 구도 타입 자동 분류
    /// - Parameter subjectPosition: 피사체 중심 위치 (0~1 정규화 좌표)
    /// - Returns: 감지된 구도 타입
    func classifyComposition(subjectPosition: CGPoint) -> CompositionType {
        let x = subjectPosition.x
        let y = subjectPosition.y

        // 1. 중앙 집중 체크 (최우선)
        if isCenterFocus(x: x, y: y) {
            return .centerFocus
        }

        // 2. 3분할 그리드 체크
        if let ruleOfThirdsType = checkRuleOfThirds(x: x, y: y) {
            return ruleOfThirdsType
        }

        // 3. 황금비율 체크
        if let goldenRatioType = checkGoldenRatio(x: x, y: y) {
            return goldenRatioType
        }

        // 4. 커스텀 구도
        return .custom(position: subjectPosition)
    }

    /// 레퍼런스와 현재 구도 비교 (정확도 계산)
    /// - Parameters:
    ///   - referencePosition: 레퍼런스 피사체 위치
    ///   - currentPosition: 현재 피사체 위치
    /// - Returns: 구도 매칭 정확도 (0~1)
    func compareComposition(referencePosition: CGPoint, currentPosition: CGPoint) -> Double {
        let xDiff = abs(referencePosition.x - currentPosition.x)
        let yDiff = abs(referencePosition.y - currentPosition.y)

        // 유클리드 거리 계산
        let distance = sqrt(xDiff * xDiff + yDiff * yDiff)

        // 최대 거리는 대각선 길이 (√2 ≈ 1.414)
        let maxDistance: CGFloat = sqrt(2.0)

        // 정확도: 1.0 (완벽) ~ 0.0 (정반대)
        let accuracy = max(0.0, 1.0 - Double(distance / maxDistance))

        return accuracy
    }

    /// 구도 차이를 피드백 메시지로 변환
    /// - Parameters:
    ///   - referenceType: 레퍼런스 구도
    ///   - referencePosition: 레퍼런스 위치
    ///   - currentPosition: 현재 위치
    /// - Returns: 피드백 메시지 및 이동 방향
    func generateCompositionFeedback(
        referenceType: CompositionType,
        referencePosition: CGPoint,
        currentPosition: CGPoint
    ) -> (message: String, xDirection: String?, yDirection: String?) {

        let xDiff = (currentPosition.x - referencePosition.x)
        let yDiff = (currentPosition.y - referencePosition.y)

        var xDirection: String? = nil
        var yDirection: String? = nil
        var message = ""

        // X축 방향
        if abs(xDiff) > 0.05 {  // 5% 이상 차이
            xDirection = xDiff > 0 ? "왼쪽" : "오른쪽"
        }

        // Y축 방향
        if abs(yDiff) > 0.05 {
            yDirection = yDiff > 0 ? "아래쪽" : "위쪽"
        }

        // 방향 메시지 조합
        if let xDir = xDirection, let yDir = yDirection {
            message = "\(referenceType.description)쪽으로 (\(xDir) + \(yDir))"
        } else if let xDir = xDirection {
            message = "\(xDir)으로 이동"
        } else if let yDir = yDirection {
            message = "\(yDir)으로 이동"
        } else {
            message = "\(referenceType.description) 위치 유지"
        }

        return (message, xDirection, yDirection)
    }

    // MARK: - Private Helpers

    /// 중앙 집중 구도 체크
    private func isCenterFocus(x: CGFloat, y: CGFloat) -> Bool {
        let centerX: CGFloat = 0.5
        let centerY: CGFloat = 0.5

        let xDist = abs(x - centerX)
        let yDist = abs(y - centerY)

        return xDist <= centerTolerance && yDist <= centerTolerance
    }

    /// 3분할 그리드 체크
    private func checkRuleOfThirds(x: CGFloat, y: CGFloat) -> CompositionType? {
        // 3분할 교점 좌표
        let leftLine: CGFloat = 1.0 / 3.0    // 0.333
        let rightLine: CGFloat = 2.0 / 3.0   // 0.667
        let upperLine: CGFloat = 1.0 / 3.0   // 0.333
        let lowerLine: CGFloat = 2.0 / 3.0   // 0.667

        // 왼쪽 상단 교점 (0.333, 0.333)
        if abs(x - leftLine) <= ruleOfThirdsTolerance &&
           abs(y - upperLine) <= ruleOfThirdsTolerance {
            return .ruleOfThirdsLeftUpper
        }

        // 오른쪽 상단 교점 (0.667, 0.333)
        if abs(x - rightLine) <= ruleOfThirdsTolerance &&
           abs(y - upperLine) <= ruleOfThirdsTolerance {
            return .ruleOfThirdsRightUpper
        }

        // 왼쪽 하단 교점 (0.333, 0.667)
        if abs(x - leftLine) <= ruleOfThirdsTolerance &&
           abs(y - lowerLine) <= ruleOfThirdsTolerance {
            return .ruleOfThirdsLeftLower
        }

        // 오른쪽 하단 교점 (0.667, 0.667)
        if abs(x - rightLine) <= ruleOfThirdsTolerance &&
           abs(y - lowerLine) <= ruleOfThirdsTolerance {
            return .ruleOfThirdsRightLower
        }

        // 중앙 영역 (4개 교점의 중심)
        let centerX: CGFloat = 0.5
        let centerY: CGFloat = 0.5
        if abs(x - centerX) <= ruleOfThirdsTolerance &&
           abs(y - centerY) <= ruleOfThirdsTolerance {
            return .ruleOfThirdsCenter
        }

        return nil
    }

    /// 황금비율 체크
    private func checkGoldenRatio(x: CGFloat, y: CGFloat) -> CompositionType? {
        // 황금비율 분할선
        let goldenLeft = 1.0 - goldenRatio   // 0.382
        let goldenRight = goldenRatio         // 0.618
        let goldenUpper = 1.0 - goldenRatio  // 0.382
        let goldenLower = goldenRatio        // 0.618

        // 왼쪽 황금비율 라인
        if abs(x - goldenLeft) <= goldenRatioTolerance {
            return .goldenRatioLeft
        }

        // 오른쪽 황금비율 라인
        if abs(x - goldenRight) <= goldenRatioTolerance {
            return .goldenRatioRight
        }

        // 상단 황금비율 라인
        if abs(y - goldenUpper) <= goldenRatioTolerance {
            return .goldenRatioUpper
        }

        // 하단 황금비율 라인
        if abs(y - goldenLower) <= goldenRatioTolerance {
            return .goldenRatioLower
        }

        return nil
    }

    /// 3분할 그리드 라인 좌표 반환 (UI 그리기용)
    func getRuleOfThirdsLines() -> (vertical: [CGFloat], horizontal: [CGFloat]) {
        let verticalLines: [CGFloat] = [1.0 / 3.0, 2.0 / 3.0]
        let horizontalLines: [CGFloat] = [1.0 / 3.0, 2.0 / 3.0]
        return (verticalLines, horizontalLines)
    }

    /// 황금비율 라인 좌표 반환 (UI 그리기용)
    func getGoldenRatioLines() -> (vertical: [CGFloat], horizontal: [CGFloat]) {
        let verticalLines: [CGFloat] = [1.0 - goldenRatio, goldenRatio]
        let horizontalLines: [CGFloat] = [1.0 - goldenRatio, goldenRatio]
        return (verticalLines, horizontalLines)
    }
}
