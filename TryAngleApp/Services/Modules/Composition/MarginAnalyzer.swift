//
//  MarginAnalyzer.swift
//  v1.5 개선된 여백 분석기 (v6 improved_margin_analyzer.py 이식)
//  작성일: 2025-12-05
//  수정일: 2025-12-07 (틸트, 하이앵글, 프레임밖 경고 추가)
//

import Foundation
import CoreGraphics
import UIKit

// MARK: - 여백 분석 결과
struct MarginAnalysisResult {
    // 절대 여백 (픽셀)
    let left: CGFloat
    let right: CGFloat
    let top: CGFloat
    let bottom: CGFloat

    // 비율 (-0.5 ~ 0.5, 음수 = 프레임 밖)
    let leftRatio: CGFloat
    let rightRatio: CGFloat
    let topRatio: CGFloat
    let bottomRatio: CGFloat

    // 균형 점수
    let horizontalBalance: CGFloat  // 좌우 균형 (1.0 = 완벽)
    let verticalBalance: CGFloat    // 상하 균형 (1.0 = 완벽)
    let overallBalance: CGFloat     // 전체 균형 점수

    // 피드백
    let horizontalFeedback: String?
    let verticalFeedback: String?
    let movementDirection: MovementDirection?

    // 🆕 v6: 인물 절대 위치 (0=상단, 1=하단)
    let personVerticalPosition: CGFloat

    // 🆕 v6: 앵글 정보
    let isHighAngle: Bool  // 하이앵글 (위에서 내려다봄)
    let isLowAngle: Bool   // 로우앵글 (아래에서 올려다봄)

    // 🆕 v6: 프레임 밖 경고
    let outOfFrameWarning: String?
}

// MARK: - 이동 방향
struct MovementDirection {
    let horizontal: HorizontalDirection?
    let vertical: VerticalDirection?
    let amount: CGFloat  // 이동량 (0.0 ~ 1.0)

    // 🆕 v6: 틸트 정보
    let tiltDirection: TiltDirection?
    let tiltAngle: Int  // 틸트 각도 (도)

    enum HorizontalDirection: String {
        case left = "왼쪽"
        case right = "오른쪽"

        var arrow: String {
            switch self {
            case .left: return "←"
            case .right: return "→"
            }
        }
    }

    enum VerticalDirection: String {
        case up = "위"
        case down = "아래"

        var arrow: String {
            switch self {
            case .up: return "↑"
            case .down: return "↓"
            }
        }
    }

    // 🆕 v6: 틸트 방향 (Python improved_margin_analyzer.py 이식)
    enum TiltDirection: String {
        case tiltUp = "위로 틸트"
        case tiltDown = "아래로 틸트"
        case lowerCamera = "카메라 낮추기"  // 하이앵글 보정

        var description: String {
            return self.rawValue
        }
    }

    var primaryArrow: String {
        if let h = horizontal, let v = vertical {
            // 더 큰 차이가 나는 방향 우선
            return amount > 0.1 ? h.arrow : v.arrow
        }
        return horizontal?.arrow ?? vertical?.arrow ?? ""
    }

    var description: String {
        var parts: [String] = []
        if let h = horizontal {
            parts.append("\(h.arrow) \(h.rawValue)")
        }
        if let v = vertical {
            parts.append("\(v.arrow) \(v.rawValue)")
        }
        // 🆕 v6: 틸트 피드백 추가
        if let tilt = tiltDirection, tiltAngle > 0 {
            parts.append("\(tilt.rawValue) \(tiltAngle)°")
        }
        return parts.joined(separator: " | ")
    }

    // 기본 생성자 (틸트 없이)
    init(horizontal: HorizontalDirection?, vertical: VerticalDirection?, amount: CGFloat) {
        self.horizontal = horizontal
        self.vertical = vertical
        self.amount = amount
        self.tiltDirection = nil
        self.tiltAngle = 0
    }

    // 🆕 v6: 틸트 포함 생성자
    init(horizontal: HorizontalDirection?, vertical: VerticalDirection?, amount: CGFloat,
         tiltDirection: TiltDirection?, tiltAngle: Int) {
        self.horizontal = horizontal
        self.vertical = vertical
        self.amount = amount
        self.tiltDirection = tiltDirection
        self.tiltAngle = tiltAngle
    }
}

// MARK: - 여백 분석기 (v6 improved_margin_analyzer.py 이식)
class MarginAnalyzer {

    // 설정 상수
    private let minMarginRatio: CGFloat = 0.03      // 최소 여백 비율 (3%)
    private let maxMarginRatio: CGFloat = 0.35      // 최대 여백 비율 (35%)
    private let balanceThreshold: CGFloat = 0.08   // 균형 허용 오차 (8%)
    private let idealBottomRatio: CGFloat = 2.0     // 이상적인 하단:상단 비율 (2:1)

    // 🆕 v6: Python improved_margin_analyzer.py 임계값
    private let horizontalThresholds = (perfect: 0.05, good: 0.10, needsAdjustment: 0.15)
    private let verticalThresholds = (perfect: 0.05, good: 0.10, needsAdjustment: 0.15)

    // MARK: - 메인 분석 함수 (v6 개선)
    func analyze(bbox: CGRect, imageSize: CGSize, isNormalized: Bool = true) -> MarginAnalysisResult {

        // bbox를 픽셀 좌표로 변환
        let pixelBBox: CGRect
        if isNormalized {
            pixelBBox = CGRect(
                x: bbox.origin.x * imageSize.width,
                y: bbox.origin.y * imageSize.height,
                width: bbox.width * imageSize.width,
                height: bbox.height * imageSize.height
            )
        } else {
            pixelBBox = bbox
        }

        // 절대 여백 계산
        let left = pixelBBox.origin.x
        let right = imageSize.width - (pixelBBox.origin.x + pixelBBox.width)
        let top = pixelBBox.origin.y
        let bottom = imageSize.height - (pixelBBox.origin.y + pixelBBox.height)

        // 🆕 v6: 비율 계산 (음수 허용 - 프레임 밖 의미)
        // Python: margins_safe[key] = max(-0.5, min(0.5, value))
        let leftRatioRaw = left / imageSize.width
        let rightRatioRaw = right / imageSize.width
        let topRatioRaw = top / imageSize.height
        let bottomRatioRaw = bottom / imageSize.height

        // 안전한 범위로 제한 (-0.5 ~ 0.5)
        let leftRatio = max(-0.5, min(0.5, leftRatioRaw))
        let rightRatio = max(-0.5, min(0.5, rightRatioRaw))
        let topRatio = max(-0.5, min(0.5, topRatioRaw))
        let bottomRatio = max(-0.5, min(0.5, bottomRatioRaw))

        // 🆕 v6: 인물 절대 위치 계산 (0=상단, 1=하단)
        // Python: curr_position = curr['top'] / (curr['top'] + curr['bottom'])
        let totalVertical = max(0.001, topRatio + bottomRatio)  // 0 나누기 방지
        let personVerticalPosition = topRatio / totalVertical

        // 🆕 v6: 앵글 감지
        // Python: curr_is_high_angle = curr['bottom'] > curr['top']
        let isHighAngle = bottomRatio > topRatio  // 하단 여백 > 상단 = 하이앵글
        let isLowAngle = topRatio > bottomRatio * 1.5  // 상단 여백이 하단의 1.5배 이상 = 로우앵글

        // 🆕 v6: 프레임 밖 경고 생성
        let outOfFrameWarning = generateOutOfFrameWarning(
            leftRatio: leftRatioRaw, rightRatio: rightRatioRaw,
            topRatio: topRatioRaw, bottomRatio: bottomRatioRaw
        )

        // 균형 점수 계산
        let horizontalBalance = calculateHorizontalBalance(leftRatio: leftRatio, rightRatio: rightRatio)
        let verticalBalance = calculateVerticalBalance(topRatio: topRatio, bottomRatio: bottomRatio)
        let overallBalance = (horizontalBalance + verticalBalance) / 2.0

        // 피드백 생성
        let (horizontalFeedback, horizontalDirection) = generateHorizontalFeedback(leftRatio: leftRatio, rightRatio: rightRatio)

        // 🆕 v6: 틸트 포함 상하 피드백
        let (verticalFeedback, verticalDirection, tiltDirection, tiltAngle) = generateVerticalFeedbackV6(
            topRatio: topRatio, bottomRatio: bottomRatio,
            isHighAngle: isHighAngle, personPosition: personVerticalPosition
        )

        // 이동 방향 계산 (틸트 포함)
        let movementAmount = max(abs(leftRatio - rightRatio), abs(topRatio - bottomRatio))
        let movement: MovementDirection? = (horizontalDirection != nil || verticalDirection != nil || tiltDirection != nil) ?
            MovementDirection(
                horizontal: horizontalDirection,
                vertical: verticalDirection,
                amount: movementAmount,
                tiltDirection: tiltDirection,
                tiltAngle: tiltAngle
            ) : nil

        return MarginAnalysisResult(
            left: left,
            right: right,
            top: top,
            bottom: bottom,
            leftRatio: leftRatio,
            rightRatio: rightRatio,
            topRatio: topRatio,
            bottomRatio: bottomRatio,
            horizontalBalance: horizontalBalance,
            verticalBalance: verticalBalance,
            overallBalance: overallBalance,
            horizontalFeedback: horizontalFeedback,
            verticalFeedback: verticalFeedback,
            movementDirection: movement,
            personVerticalPosition: personVerticalPosition,
            isHighAngle: isHighAngle,
            isLowAngle: isLowAngle,
            outOfFrameWarning: outOfFrameWarning
        )
    }

    // 🆕 v6: 프레임 밖 경고 생성 (Python improved_margin_analyzer.py 이식)
    private func generateOutOfFrameWarning(
        leftRatio: CGFloat, rightRatio: CGFloat,
        topRatio: CGFloat, bottomRatio: CGFloat
    ) -> String? {
        var warnings: [String] = []

        // 좌우 프레임 밖
        if leftRatio < 0 && rightRatio < 0 {
            warnings.append("인물이 좌우로 프레임을 벗어났습니다 (너무 가까움)")
        } else if leftRatio < 0 {
            warnings.append("인물이 왼쪽 프레임을 벗어났습니다")
        } else if rightRatio < 0 {
            warnings.append("인물이 오른쪽 프레임을 벗어났습니다")
        }

        // 상하 프레임 밖
        if topRatio < 0 && bottomRatio < 0 {
            warnings.append("인물이 상하로 프레임을 벗어났습니다 (너무 가까움)")
        } else if topRatio < 0 {
            warnings.append("머리가 프레임을 벗어났습니다")
        } else if bottomRatio < 0 {
            warnings.append("발이 프레임을 벗어났습니다")
        }

        return warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    }

    // MARK: - 레퍼런스와 비교 분석
    func compareWithReference(
        current: CGRect,
        reference: CGRect,
        currentImageSize: CGSize,
        referenceImageSize: CGSize
    ) -> MarginComparisonResult {

        let currentMargins = analyze(bbox: current, imageSize: currentImageSize)
        let referenceMargins = analyze(bbox: reference, imageSize: referenceImageSize)

        // 비율 차이 계산
        let leftDiff = currentMargins.leftRatio - referenceMargins.leftRatio
        let rightDiff = currentMargins.rightRatio - referenceMargins.rightRatio
        let topDiff = currentMargins.topRatio - referenceMargins.topRatio
        let bottomDiff = currentMargins.bottomRatio - referenceMargins.bottomRatio

        // 매칭 점수 (0.0 ~ 1.0)
        let horizontalMatch = 1.0 - min(abs(leftDiff) + abs(rightDiff), 1.0)
        let verticalMatch = 1.0 - min(abs(topDiff) + abs(bottomDiff), 1.0)
        let overallMatch = (horizontalMatch + verticalMatch) / 2.0

        // 구체적인 조정 피드백
        let adjustmentFeedback = generateAdjustmentFeedback(
            leftDiff: leftDiff,
            rightDiff: rightDiff,
            topDiff: topDiff,
            bottomDiff: bottomDiff
        )

        return MarginComparisonResult(
            currentMargins: currentMargins,
            referenceMargins: referenceMargins,
            horizontalMatch: horizontalMatch,
            verticalMatch: verticalMatch,
            overallMatch: overallMatch,
            adjustmentFeedback: adjustmentFeedback
        )
    }

    // MARK: - Private Methods

    private func calculateHorizontalBalance(leftRatio: CGFloat, rightRatio: CGFloat) -> CGFloat {
        // 좌우 균형: 차이가 작을수록 1.0에 가까움
        let diff = abs(leftRatio - rightRatio)
        return max(0, 1.0 - (diff / 0.5))  // 50% 차이면 0점
    }

    private func calculateVerticalBalance(topRatio: CGFloat, bottomRatio: CGFloat) -> CGFloat {
        // 상하 균형: 하단이 상단의 약 2배가 이상적
        // 예: top=0.1, bottom=0.2 → 이상적
        let idealBottom = topRatio * idealBottomRatio
        let diff = abs(bottomRatio - idealBottom)
        return max(0, 1.0 - (diff / 0.3))  // 30% 차이면 0점
    }

    private func generateHorizontalFeedback(leftRatio: CGFloat, rightRatio: CGFloat) -> (String?, MovementDirection.HorizontalDirection?) {
        let diff = leftRatio - rightRatio

        if abs(diff) < balanceThreshold {
            return (nil, nil)  // 균형 잡힘
        }

        if diff > 0 {
            // 왼쪽 여백이 더 큼 → 카메라를 오른쪽으로
            let percentage = Int(abs(diff) * 100)
            return ("카메라를 오른쪽으로 \(percentage)% 이동", .right)
        } else {
            // 오른쪽 여백이 더 큼 → 카메라를 왼쪽으로
            let percentage = Int(abs(diff) * 100)
            return ("카메라를 왼쪽으로 \(percentage)% 이동", .left)
        }
    }

    private func generateVerticalFeedback(topRatio: CGFloat, bottomRatio: CGFloat) -> (String?, MovementDirection.VerticalDirection?) {
        // 이상적 비율: 하단이 상단의 2배
        let idealBottom = topRatio * idealBottomRatio
        let diff = bottomRatio - idealBottom

        if abs(diff) < balanceThreshold {
            return (nil, nil)  // 균형 잡힘
        }

        // 여백 부족 체크
        if topRatio < minMarginRatio {
            return ("상단 여백이 부족합니다", .down)
        }
        if bottomRatio < minMarginRatio {
            return ("하단 여백이 부족합니다", .up)
        }

        // 균형 조정
        if diff > 0 {
            // 하단 여백이 너무 큼 → 카메라를 아래로
            return ("카메라를 아래로 이동", .down)
        } else {
            // 하단 여백이 부족 → 카메라를 위로
            return ("카메라를 위로 이동", .up)
        }
    }

    // 🆕 v6: 틸트 포함 상하 피드백 생성 (Python improved_margin_analyzer.py _analyze_vertical_balance 이식)
    private func generateVerticalFeedbackV6(
        topRatio: CGFloat,
        bottomRatio: CGFloat,
        isHighAngle: Bool,
        personPosition: CGFloat  // 0=상단, 1=하단
    ) -> (String?, MovementDirection.VerticalDirection?, MovementDirection.TiltDirection?, Int) {

        // 위치 차이 기준 (10% 이상이면 조정 필요)
        let positionThreshold: CGFloat = 0.10

        // 기본값
        var feedback: String? = nil
        var verticalDirection: MovementDirection.VerticalDirection? = nil
        var tiltDirection: MovementDirection.TiltDirection? = nil
        var tiltAngle: Int = 0

        // 인물 위치 분석 (Python: position_diff = curr_position - ref_position)
        // 여기서는 절대 위치 기준 분석 (0.5가 중앙)
        let idealPosition: CGFloat = 0.35  // 이상적 위치 (살짝 위쪽)
        let positionDiff = personPosition - idealPosition

        // 🔧 여백 부족 체크 (프레임 밖)
        if topRatio < 0 {
            return ("머리가 잘렸어요. 카메라를 아래로 내리세요", .down, .lowerCamera, 5)
        }
        if bottomRatio < 0 {
            return ("발이 잘렸어요. 카메라를 위로 올리세요", .up, .tiltUp, 5)
        }

        // 위치 차이가 작으면 OK
        if abs(positionDiff) < positionThreshold {
            return (nil, nil, nil, 0)
        }

        // 🆕 v6: 틸트 각도 계산 (Python: _to_tilt_angle)
        // 위치 차이를 틸트 각도로 변환
        tiltAngle = toTiltAngle(percent: abs(positionDiff) * 100)

        // 케이스 분석 (Python _analyze_vertical_balance 로직)
        if positionDiff > 0 {
            // 인물이 아래쪽에 위치 (상단 여백이 많음)
            if isHighAngle {
                // 하이앵글 + 인물이 아래 = 카메라를 내리고 앵글 평행하게
                tiltDirection = .lowerCamera
                feedback = "카메라를 낮추고 앵글을 \(tiltAngle)° 평행하게"
                verticalDirection = .down
            } else {
                // 평행 앵글 + 인물이 아래 = 틸트 다운
                tiltDirection = .tiltDown
                feedback = "카메라를 \(tiltAngle)° 아래로 틸트"
                verticalDirection = .down
            }
        } else {
            // 인물이 위쪽에 위치 (하단 여백이 많음)
            tiltDirection = .tiltUp
            feedback = "카메라를 \(tiltAngle)° 위로 틸트"
            verticalDirection = .up
        }

        return (feedback, verticalDirection, tiltDirection, tiltAngle)
    }

    // 🆕 v6: 퍼센트를 틸트 각도로 변환 (Python _to_tilt_angle 이식)
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

    private func generateAdjustmentFeedback(
        leftDiff: CGFloat,
        rightDiff: CGFloat,
        topDiff: CGFloat,
        bottomDiff: CGFloat
    ) -> String {
        var feedbacks: [String] = []
        let threshold: CGFloat = 0.05  // 5% 이상 차이나면 피드백

        // 수평 조정
        let horizontalShift = (leftDiff - rightDiff) / 2
        if abs(horizontalShift) > threshold {
            if horizontalShift > 0 {
                feedbacks.append("← 왼쪽으로")
            } else {
                feedbacks.append("→ 오른쪽으로")
            }
        }

        // 수직 조정
        let verticalShift = (topDiff - bottomDiff) / 2
        if abs(verticalShift) > threshold {
            if verticalShift > 0 {
                feedbacks.append("↑ 위로")
            } else {
                feedbacks.append("↓ 아래로")
            }
        }

        if feedbacks.isEmpty {
            return "✓ 레퍼런스와 일치"
        }

        return feedbacks.joined(separator: " | ")
    }
}

// MARK: - 비교 결과
struct MarginComparisonResult {
    let currentMargins: MarginAnalysisResult
    let referenceMargins: MarginAnalysisResult
    let horizontalMatch: CGFloat  // 0.0 ~ 1.0
    let verticalMatch: CGFloat    // 0.0 ~ 1.0
    let overallMatch: CGFloat     // 0.0 ~ 1.0
    let adjustmentFeedback: String

    var isMatched: Bool {
        return overallMatch > 0.85
    }
}
