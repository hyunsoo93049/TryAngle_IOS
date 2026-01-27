import Foundation
import AVFoundation

// MARK: - 카메라 설정 (영구 저장)
struct CameraFormatSettings: Codable, Equatable {
    var frontResolution: Int  // MP (예: 12)
    var backResolution: Int   // MP (예: 24)
    var fps: Int              // 30 or 60
    var frontStabilizationEnabled: Bool
    var backStabilizationEnabled: Bool

    static let `default` = CameraFormatSettings(
        frontResolution: 12,
        backResolution: 24,
        fps: 30,
        frontStabilizationEnabled: false,
        backStabilizationEnabled: true
    )

    // MARK: - 저장/로드
    private static let userDefaultsKey = "com.tryangle.cameraSettings"

    static func load() -> CameraFormatSettings? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(CameraFormatSettings.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
            logInfo("[CameraFormatSettings] 저장 완료: front=\(frontResolution)MP, back=\(backResolution)MP, fps=\(fps), stabilization=front:\(frontStabilizationEnabled)/back:\(backStabilizationEnabled)", category: "Camera")
        }
    }

    static var isFirstLaunch: Bool {
        return UserDefaults.standard.data(forKey: userDefaultsKey) == nil
    }

    // MARK: - 해상도 MP → 픽셀 매칭
    /// MP 값에 가장 가까운 포맷의 사진 해상도를 찾기 위한 기준 픽셀 수
    static func megapixelsToPixelCount(_ mp: Int) -> Int {
        return mp * 1_000_000
    }

    /// 기기에서 지원하는 해상도(MP) 목록 반환
    static func availableResolutions(for position: AVCaptureDevice.Position) -> [Int] {
        let device: AVCaptureDevice?
        if position == .front {
            device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        } else {
            // 후면은 가장 좋은 카메라 탐색
            device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }

        guard let device = device else { return [] }

        var mpSet = Set<Int>()
        for format in device.formats {
            let mediaType = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            let isVideoFormat = mediaType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
                               mediaType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            guard isVideoFormat else { continue }

            if let maxPhotoDim = format.supportedMaxPhotoDimensions.last {
                let mp = Int(maxPhotoDim.width) * Int(maxPhotoDim.height) / 1_000_000
                if mp >= 1 {
                    mpSet.insert(mp)
                }
            }
        }

        return mpSet.sorted()
    }
}
