import Foundation
import UIKit

// MARK: - Composition Module
// 역할: 피사체 위치를 기반으로 구도 타입(삼분할, 중앙, 황금비 등)을 분류합니다.
//       "이 사진이 삼분할 구도인지 중앙 구도인지" 같은 정보를 알려줍니다.

class CompositionModule: ReferenceAnalysisModule {
    let name = "Composition"
    let priority = 20  // Framing 분석 후 실행

    private let compositionAnalyzer = RuleCompositionAnalyzer()

    init() {}

    func analyze(input: ReferenceInput, context: inout ReferenceContext) async throws {
        // 피사체 중심점 계산 (키포인트 또는 BBox 기반)
        let subjectCenter: CGPoint

        if let keypoints = context.poseKeypoints, keypoints.count >= 5 {
            // 키포인트 중심 (어깨, 엉덩이 평균)
            subjectCenter = calculateSubjectCenter(from: keypoints)
        } else if let bbox = context.preciseBBox {
            // BBox 중심
            subjectCenter = CGPoint(x: bbox.midX, y: bbox.midY)
        } else {
            return
        }

        // 구도 타입 분류
        context.compositionType = compositionAnalyzer.classifyComposition(subjectPosition: subjectCenter)
    }

    // MARK: - Helpers

    private func calculateSubjectCenter(from keypoints: [(point: CGPoint, confidence: Float)]) -> CGPoint {
        // 어깨(5,6)와 엉덩이(11,12)의 중심점 계산
        let indices = [5, 6, 11, 12]  // 좌우 어깨, 좌우 엉덩이
        var validPoints: [CGPoint] = []

        for idx in indices {
            if idx < keypoints.count && keypoints[idx].confidence > 0.3 {
                validPoints.append(keypoints[idx].point)
            }
        }

        guard !validPoints.isEmpty else {
            // Fallback: 코(0) 위치
            if keypoints.count > 0 && keypoints[0].confidence > 0.3 {
                return keypoints[0].point
            }
            return CGPoint(x: 0.5, y: 0.5)
        }

        let sumX = validPoints.reduce(0) { $0 + $1.x }
        let sumY = validPoints.reduce(0) { $0 + $1.y }

        return CGPoint(
            x: sumX / CGFloat(validPoints.count),
            y: sumY / CGFloat(validPoints.count)
        )
    }
}
