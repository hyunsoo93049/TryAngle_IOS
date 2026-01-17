import Foundation
import UIKit
import ImageIO

// MARK: - EXIF Module
// 역할: 레퍼런스 이미지에서 EXIF 메타데이터(초점거리, 조리개, ISO 등)를 추출합니다.
//       사진이 어떤 카메라/렌즈 설정으로 찍혔는지 알 수 있습니다.

class EXIFModule: ReferenceAnalysisModule {
    let name = "EXIF"
    let priority = 0  // 가장 먼저 실행 (다른 모듈에서 참조할 수 있음)

    init() {}

    func analyze(input: ReferenceInput, context: inout ReferenceContext) async throws {
        guard let imageData = input.imageData else {
            return
        }

        // CGImageSource로 EXIF 추출
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return
        }

        // EXIF Dictionary
        let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]

        // TIFF Dictionary (일부 정보는 여기에 있음)
        let tiffDict = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]

        // 값 추출
        let focalLength = exifDict?[kCGImagePropertyExifFocalLength as String] as? Double
        let focalLength35mm = exifDict?[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? Double
        let aperture = exifDict?[kCGImagePropertyExifFNumber as String] as? Double
        let iso = (exifDict?[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first
        let exposureTime = exifDict?[kCGImagePropertyExifExposureTime as String] as? Double
        let lensModel = exifDict?[kCGImagePropertyExifLensModel as String] as? String
            ?? tiffDict?[kCGImagePropertyTIFFModel as String] as? String

        // Context에 저장
        context.exifInfo = EXIFInfo(
            focalLength: focalLength,
            focalLength35mm: focalLength35mm,
            aperture: aperture,
            iso: iso,
            exposureTime: exposureTime,
            lensModel: lensModel
        )
    }
}
