import Foundation
import UIKit
import CoreGraphics
import Combine

// MARK: - 이미지/디바이스 방향
enum ImageOrientation: String, Codable {
    case portrait   // 세로 (높이 > 너비)
    case landscape  // 가로 (너비 > 높이)

    var description: String {
        switch self {
        case .portrait: return "세로"
        case .landscape: return "가로"
        }
    }

    /// 이미지 크기로부터 방향 감지
    static func detect(from size: CGSize) -> ImageOrientation {
        return size.height > size.width ? .portrait : .landscape
    }

    /// UIImage로부터 방향 감지
    static func detect(from image: UIImage) -> ImageOrientation {
        return detect(from: image.size)
    }
}

// MARK: - 디바이스 방향 관리자
class DeviceOrientationManager: ObservableObject {
    @Published var currentOrientation: ImageOrientation = .portrait

    private var orientationObserver: NSObjectProtocol?

    init() {
        // 초기 방향 설정
        updateOrientation()

        // 방향 변경 감지
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateOrientation()
        }
    }

    deinit {
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func updateOrientation() {
        let device = UIDevice.current

        switch device.orientation {
        case .portrait, .portraitUpsideDown:
            currentOrientation = .portrait
        case .landscapeLeft, .landscapeRight:
            currentOrientation = .landscape
        default:
            // Unknown이나 FaceUp/FaceDown은 이전 상태 유지
            break
        }
    }

    /// 현재 디바이스 방향이 레퍼런스와 일치하는지 확인
    func isMatchingOrientation(reference: ImageOrientation) -> Bool {
        return currentOrientation == reference
    }
}
