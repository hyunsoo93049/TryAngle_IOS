import SwiftUI
import AVFoundation
import UIKit

struct CameraView: UIViewRepresentable {
    let cameraManager: CameraManager
    let isSessionConfigured: Bool
    let aspectRatio: CameraAspectRatio

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.backgroundColor = .black
        
        // 핀치 제스처 (줌)
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)

        // 탭 제스처 (초점)
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)

        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        // Layer 연결 로직
        if isSessionConfigured && uiView.previewLayer == nil {
            let layer = cameraManager.previewLayer
            uiView.setPreviewLayer(layer)
            print("✅ [CameraView] Preview Layer 연결 (Custom View)")
        }
        
        // 화면비 업데이트
        uiView.updateAspectRatio(aspectRatio)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(cameraManager: cameraManager)
    }

    // MARK: - Internal Custom View (Layout Robustness)
    class CameraPreviewView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer?
        
        func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
            guard previewLayer == nil else { return } // 중복 추가 방지
            
            self.previewLayer = layer
            layer.frame = bounds
            layer.contentsGravity = .resizeAspect
            layer.backgroundColor = UIColor.black.cgColor
            layer.addSublayer(CALayer()) // Dummy to force layout? No.
            
            self.layer.insertSublayer(layer, at: 0)
        }
        
        func updateAspectRatio(_ ratio: CameraAspectRatio) {
            guard let layer = previewLayer else { return }
            
            let targetGravity: AVLayerVideoGravity = (ratio == .ratio16_9) ? .resizeAspectFill : .resizeAspect
            
            if layer.videoGravity != targetGravity {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.videoGravity = targetGravity
                CATransaction.commit()
            }
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            
            // 🔥 핵심: 뷰 크기가 변할 때마다 무조건 레이어 프레임 동기화
            if let layer = previewLayer {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.frame = bounds
                CATransaction.commit()
            }
        }
    }

    class Coordinator: NSObject {
        let cameraManager: CameraManager
        private var initialZoom: CGFloat = 1.0

        init(cameraManager: CameraManager) {
            self.cameraManager = cameraManager
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                initialZoom = cameraManager.virtualZoom
            case .changed:
                let targetZoom = initialZoom * gesture.scale
                cameraManager.setZoomImmediate(targetZoom)
            case .ended, .cancelled:
                initialZoom = 1.0
            default:
                break
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? CameraPreviewView, 
                  let previewLayer = view.previewLayer else { return }
            
            let point = gesture.location(in: view)
            let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
            
            cameraManager.setFocus(at: devicePoint)
            print("👆 Tap to Focus: \(devicePoint)")
        }
    }
}
