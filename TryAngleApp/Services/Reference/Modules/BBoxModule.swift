import Foundation
import UIKit
import CoreImage

// MARK: - BBox Module
// 역할: YOLOX를 사용해서 피사체의 정밀한 바운딩박스를 검출합니다.
//       인물의 정확한 위치와 크기를 알 수 있습니다.

class BBoxModule: ReferenceAnalysisModule {
    let name = "BBox"
    let priority = 15  // Framing 후

    private let personDetector = PersonDetector()

    init() {}

    func analyze(input: ReferenceInput, context: inout ReferenceContext) async throws {
        guard let ciImage = CIImage(image: input.image) else {
            return
        }

        // PersonDetector로 정밀 BBox 검출
        let bbox = await withCheckedContinuation { continuation in
            personDetector.detectPerson(in: ciImage) { bbox in
                continuation.resume(returning: bbox)
            }
        }

        context.preciseBBox = bbox
    }
}
