import Foundation
import UIKit

// MARK: - Depth Module
// 역할: Depth Anything 모델을 사용해서 이미지의 깊이(압축감)를 추정합니다.
//       배경과 피사체의 분리 정도를 알 수 있습니다.

class DepthModule: ReferenceAnalysisModule {
    let name = "Depth"
    let priority = 5  // EXIF 후, Framing 전

    private let depthAnything = DepthAnythingCoreML.shared

    init() {}

    func analyze(input: ReferenceInput, context: inout ReferenceContext) async throws {
        // Depth Anything으로 깊이 추정
        let depthResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DepthEstimationResult?, Error>) in
            depthAnything.estimateDepth(from: input.image) { result in
                switch result {
                case .success(let v15Result):
                    let depthEstimation = DepthEstimationResult(
                        timestamp: Date().timeIntervalSince1970,
                        depthMap: nil,
                        compressionIndex: v15Result.compressionIndex
                    )
                    continuation.resume(returning: depthEstimation)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        context.depthResult = depthResult
    }
}
