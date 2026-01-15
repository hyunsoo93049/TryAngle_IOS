import Foundation
import UIKit
import Vision

// MARK: - 사진 분석기 (촬영 이미지 vs 레퍼런스 비교)

class PhotoAnalyzer {

    // MARK: - 싱글톤
    static let shared = PhotoAnalyzer()
    private init() {}

    // MARK: - 분석 실행

    /// 촬영된 사진을 레퍼런스와 비교 분석
    func analyze(
        capturedImage: UIImage,
        referenceImage: UIImage?,
        referenceAnalysis: FrameAnalysis?,
        gateEvaluation: GateEvaluation?
    ) async -> PhotoAnalysisResult {

        // 1. Gate System 결과 활용 (있으면)
        let gateScores = extractGateScores(from: gateEvaluation)

        // 2. 카테고리별 비교 분석
        let categories = buildCategories(
            referenceAnalysis: referenceAnalysis,
            gateScores: gateScores
        )

        // 3. 샷 타입 결정 (GateSystem 감지 결과 우선 사용)
        let shotType = determineShotType(from: referenceAnalysis, gateEvaluation: gateEvaluation)

        // 4. 종합 점수 계산
        let overallScore = calculateOverallScore(categories: categories)

        // 5. 요약 텍스트 생성
        let summaryText = generateSummary(score: overallScore, shotType: shotType)

        return PhotoAnalysisResult(
            capturedImage: capturedImage,
            referenceImage: referenceImage,
            overallScore: overallScore,
            categories: categories,
            shotType: shotType.type,
            shotDescription: shotType.description,
            summaryText: summaryText
        )
    }

    // MARK: - Gate 점수 추출

    private func extractGateScores(from evaluation: GateEvaluation?) -> GateScores {
        guard let eval = evaluation else {
            return GateScores()
        }

        return GateScores(
            aspectRatio: eval.gate0.score,
            framing: eval.gate1.score,
            position: eval.gate2.score,
            compression: eval.gate3.score,
            pose: eval.gate4.score
        )
    }

    // MARK: - 카테고리 빌드

    private func buildCategories(
        referenceAnalysis: FrameAnalysis?,
        gateScores: GateScores
    ) -> [AnalysisCategory] {

        var categories: [AnalysisCategory] = []

        // 1. 포즈
        let poseScore = gateScores.pose
        let poseMatched = poseScore >= 0.7
        categories.append(AnalysisCategory(
            type: .pose,
            score: poseScore,
            isMatched: poseMatched,
            feedback: poseMatched ? "포즈가 레퍼런스와 유사합니다!" : generatePoseFeedback(score: poseScore)
        ))

        // 2. 구도 (프레이밍 + 위치)
        let compositionScore = (gateScores.framing + gateScores.position) / 2
        let compositionMatched = compositionScore >= 0.7
        categories.append(AnalysisCategory(
            type: .composition,
            score: compositionScore,
            isMatched: compositionMatched,
            feedback: compositionMatched ? "구도가 잘 맞았습니다!" : generateCompositionFeedback(score: compositionScore)
        ))

        // 3. 시점 (비율 기반)
        let viewpointScore = gateScores.aspectRatio
        let viewpointMatched = viewpointScore >= 0.8
        categories.append(AnalysisCategory(
            type: .viewpoint,
            score: viewpointScore,
            isMatched: viewpointMatched,
            feedback: viewpointMatched ? "같은 아이레벨 뷰입니다!" : "카메라 높이를 조절해보세요"
        ))

        // 4. 색감 (현재는 기본값, 추후 확장)
        let colorScore = 0.75  // TODO: 색상 분석 추가
        let colorMatched = colorScore >= 0.7
        categories.append(AnalysisCategory(
            type: .color,
            score: colorScore,
            isMatched: colorMatched,
            feedback: "색감이 비슷합니다!"  // TODO: 색상 분석 로직 추가 후 조건부 메시지로 변경
        ))

        // 5. 감성 (압축감 기반)
        let moodScore = gateScores.compression
        let moodMatched = moodScore >= 0.7
        categories.append(AnalysisCategory(
            type: .mood,
            score: moodScore,
            isMatched: moodMatched,
            feedback: moodMatched ? "레퍼런스와 마찬가지로 분위기가 유사합니다." : "배경 보케나 압축감을 조절해보세요."
        ))

        // 6. 조명 (빠른 피드백용)
        let lightingScore = 0.7  // TODO: 조명 분석 추가
        categories.append(AnalysisCategory(
            type: .lighting,
            score: lightingScore,
            isMatched: lightingScore >= 0.7,
            feedback: "조명이 적절합니다!" // TODO: 로직 구현 후 조건부 메시지로 변경
        ))

        // 7. 초점 (빠른 피드백용)
        let focusScore = 0.8  // TODO: 초점 분석 추가
        categories.append(AnalysisCategory(
            type: .focus,
            score: focusScore,
            isMatched: focusScore >= 0.7,
            feedback: "초점이 잘 맞았습니다!" // TODO: 로직 구현 후 조건부 메시지로 변경
        ))

        return categories
    }

    // MARK: - 샷 타입 결정

    private func determineShotType(
        from reference: FrameAnalysis?,
        gateEvaluation: GateEvaluation?
    ) -> (type: String, description: String) {

        // 🆕 GateSystem에서 감지한 샷타입 우선 사용
        if let currentShotType = gateEvaluation?.currentShotType {
            let name = currentShotType.displayName
            return (name, "\(name) 구도로 촬영된 사진입니다")
        }

        // 레퍼런스 샷타입 (fallback)
        if let refShotType = gateEvaluation?.referenceShotType {
            let name = refShotType.displayName
            return (name, "\(name) 구도로 촬영된 사진입니다")
        }

        // 레퍼런스 분석 결과에서 얼굴/바디 크기로 샷타입 추정 (legacy fallback)
        if let faceRect = reference?.faceRect {
            let faceHeight = faceRect.height

            if faceHeight > 0.5 {
                return ("클로즈업", "얼굴이 크게 보이는 클로즈업 샷")
            } else if faceHeight > 0.3 {
                return ("바스트샷", "가슴 위로 보이는 바스트 샷")
            } else if faceHeight > 0.15 {
                return ("웨이스트샷", "허리 위로 보이는 웨이스트 샷")
            } else if faceHeight > 0.08 {
                return ("니샷", "무릎 위로 보이는 니 샷")
            } else {
                return ("전신샷", "전신이 보이는 풀샷")
            }
        }

        // 기본값
        return ("인물 사진", "인물이 포함된 사진입니다")
    }

    // MARK: - 피드백 생성

    private func generatePoseFeedback(score: Double) -> String {
        if score >= 0.5 {
            return "포즈가 비슷하지만 조금 더 조정이 필요합니다"
        } else {
            return "레퍼런스 포즈를 참고해서 다시 시도해보세요"
        }
    }

    private func generateCompositionFeedback(score: Double) -> String {
        if score >= 0.5 {
            return "인물 위치를 조금만 더 조정해보세요"
        } else {
            return "인물이 프레임 중앙에서 벗어났습니다"
        }
    }

    // MARK: - 종합 점수 계산

    private func calculateOverallScore(categories: [AnalysisCategory]) -> Double {
        // 주요 5개 카테고리만 사용 (조명, 초점 제외)
        let mainCategories = categories.filter {
            [.pose, .composition, .viewpoint, .color, .mood].contains($0.type)
        }

        guard !mainCategories.isEmpty else { return 5.0 }

        let avgScore = mainCategories.map { $0.score }.reduce(0, +) / Double(mainCategories.count)
        return min(10.0, avgScore * 10.0)
    }

    // MARK: - 요약 생성

    private func generateSummary(score: Double, shotType: (type: String, description: String)) -> String {
        if score >= 8.5 {
            return "전체적으로 밸런스가 잘 잡힌 \(shotType.type)입니다!"
        } else if score >= 7.0 {
            return "좋은 \(shotType.type)이지만 조금 더 개선할 수 있습니다."
        } else if score >= 5.0 {
            return "기본적인 구도는 잡혔지만 여러 부분에서 조정이 필요합니다."
        } else {
            return "레퍼런스를 참고해서 다시 촬영해보세요."
        }
    }
}

// MARK: - Gate 점수 구조체

private struct GateScores {
    var aspectRatio: Double = 0.5
    var framing: Double = 0.5
    var position: Double = 0.5
    var compression: Double = 0.5
    var pose: Double = 0.5
}
