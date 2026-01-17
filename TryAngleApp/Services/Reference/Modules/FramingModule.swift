import Foundation
import UIKit

// MARK: - Framing Module
// 역할: 키포인트를 기반으로 사진학적 프레이밍(샷타입, 헤드룸, 카메라앵글)을 분석합니다.
//       "이 사진이 바스트샷인지 전신샷인지" 같은 정보를 알려줍니다.

class FramingModule: ReferenceAnalysisModule {
    let name = "Framing"
    let priority = 10  // Pose 분석 후 실행

    private let photographyFramingAnalyzer = PhotographyFramingAnalyzer()

    init() {}

    func analyze(input: ReferenceInput, context: inout ReferenceContext) async throws {
        // Pose 결과 필요
        guard let keypoints = context.poseKeypoints, keypoints.count >= 17 else {
            return
        }

        // 사진학 기반 프레이밍 분석
        let result = photographyFramingAnalyzer.analyze(
            keypoints: keypoints,
            imageSize: input.imageSize
        )

        context.framingResult = result

        // 비율도 함께 계산
        context.aspectRatio = CameraAspectRatio.detect(from: input.imageSize)
    }
}
