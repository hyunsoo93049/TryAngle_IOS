import Foundation
import UIKit
import CoreImage

// MARK: - BBox Module
// 역할: YOLO11n을 사용해서 피사체의 정밀한 바운딩박스를 검출합니다.
//       인물의 정확한 위치와 크기를 알 수 있습니다.

class BBoxModule: ReferenceAnalysisModule {
    let name = "BBox"
    let priority = 15  // Framing 후

    init() {}

    func analyze(input: ReferenceInput, context: inout ReferenceContext) async throws {
        guard let runner = RTMPoseRunner.shared, runner.isReady else {
            return
        }

        // RTMPoseRunner로 직접 BBox 검출 (YOLO11n)
        let bbox = runner.detectPersonBBox(from: input.image)

        if let bbox = bbox {
            // 픽셀 좌표 → 정규화 좌표 변환
            let imageSize = input.image.size
            context.preciseBBox = CGRect(
                x: bbox.origin.x / imageSize.width,
                y: bbox.origin.y / imageSize.height,
                width: bbox.width / imageSize.width,
                height: bbox.height / imageSize.height
            )
        }
    }
}
