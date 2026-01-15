import AVFoundation
import UIKit
import Combine
import Metal
import CoreImage

// MARK: - 렌즈 타입 정의 (순수하게 현재 물리 렌즈 상태만 표현)
enum CameraLensType: String {
    case ultraWide = "Ultra Wide" // 초광각
    case wide = "Wide"            // 광각
    case telephoto = "Telephoto"  // 망원

    // EXIF 저장 및 디버그 표시용
    var description: String {
        return self.rawValue
    }
}

class CameraManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isAuthorized = false
    // @Published var currentFrame: UIImage?  <- REMOVED: Using Combine stream
    @Published var isSessionRunning = false
    @Published var isFlashOn = false
    @Published var currentFPS: Double = 0.0
    @Published var currentZoom: CGFloat = 1.0
    @Published var virtualZoom: CGFloat = 1.0  // 사용자에게 표시되는 줌 (0.5, 1, 2, 3 등)
    @Published var aspectRatio: CameraAspectRatio = .ratio4_3
    @Published var isFrontCamera: Bool = false
    
    // 🆕 Frame Stream for Analysis (Background Thread)
    public let frameSubject = PassthroughSubject<CMSampleBuffer, Never>()
    public let frameImageSubject = PassthroughSubject<UIImage, Never>() // For UI if absolutely needed (throttled)

    // 🆕 현재 활성화된 물리 렌즈 (상태 표시용)
    @Published var currentLens: CameraLensType = .wide
    
    // 🆕 세션 설정 완료 상태 (Preview Layer 연결 타이밍 제어)
    @Published var isSessionConfigured: Bool = false

    // 🆕 UI에 표시할 줌 버튼 리스트 (기기별 자동 생성)
    @Published var zoomButtons: [CGFloat] = [1.0]

    // MARK: - Camera Properties
    private let session = AVCaptureSession()
    private var videoOutput = AVCaptureVideoDataOutput()
    private var photoOutput = AVCapturePhotoOutput()
    private var currentCamera: AVCaptureDevice?
    private var currentInput: AVCaptureDeviceInput?
    private var photoCaptureCompletion: ((Data?, Error?) -> Void)?

    private var isUsingVirtualDevice = false
    private var minZoomFactor: CGFloat = 1.0
    private var maxZoomFactor: CGFloat = 10.0
    
    // [자동화] 배율 보정값 (User 1x가 Device 몇 배인지)
    private var zoomFactorScale: CGFloat = 1.0
    
    // 렌즈 전환 포인트 (물리 렌즈가 바뀌는 지점)
    private var switchOverZoomFactors: [CGFloat] = []

    // MARK: - Performance Properties
    private let ciContext: CIContext = {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: metalDevice, options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false])
        } else {
            return CIContext(options: [.useSoftwareRenderer: false, .workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        }
    }()
    private var lastBufferTime: TimeInterval = 0
    private var fpsFrameCount = 0
    private var lastFPSUpdate = Date()
    private var lastFrameUpdateTime: CFTimeInterval = 0  // 프레임 UI 업데이트 시간
    private let minFrameUpdateInterval: CFTimeInterval = 1.0 / 20.0  // 20fps로 제한

    // ✅ 줌 디바운싱
    private var pendingZoomWorkItem: DispatchWorkItem?

    // MARK: - Base Focal Length (For EXIF)
    private var baseFocalLength35mm: CGFloat = 24.0

    // MARK: - Preview Layer
    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect // 🔥 중요: Fill 대신 Aspect로 변경하여 4:3 전체 영역 표시 (WYSIWYG)
        return layer
    }()

    // MARK: - Initialization
    override init() {
        super.init()
        checkAuthorization()
    }

    private func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: isAuthorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async { self?.isAuthorized = granted }
            }
        default: isAuthorized = false
        }
    }

    // MARK: - Session Setup
    func setupSession(completion: (() -> Void)? = nil) {
        guard isAuthorized else {
            completion?()
            return
        }

        // 🔥 UI 반응성 개선: 백그라운드에서 초기화 (Safe Queue 사용)
        sessionQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion?() }
                return
            }

            self.session.beginConfiguration()

            // 후면 카메라 우선 탐색
            let camera = self.findBestBackCamera()
            guard let camera = camera else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { completion?() }
                return
            }

            self.configureSession(with: camera)
            self.session.commitConfiguration()

            // 줌 및 렌즈 설정 (Commit 후에 해야 함)
            self.setupZoomFactors(for: camera)

            // 🔥 설정 완료 후 콜백 호출
            DispatchQueue.main.async {
                self.isSessionConfigured = true  // 🆕 Preview Layer 연결 허용
                completion?()
            }
        }
    }
    
    private func configureSession(with camera: AVCaptureDevice) {
        currentCamera = camera
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
                currentInput = input
            }
            
            // 포맷 설정
            configureHighQualityFormat(for: camera)
            analyzeCameraCharacteristics(for: camera)

            // 비디오 출력
            let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInteractive, attributes: [])
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

            // 사진 출력
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
                if #available(iOS 16.0, *) {
                    photoOutput.maxPhotoDimensions = camera.activeFormat.supportedMaxPhotoDimensions.first ?? CMVideoDimensions(width: 4032, height: 3024)
                } else {
                    photoOutput.isHighResolutionCaptureEnabled = true
                }
            }

            // 방향 설정
            if let connection = videoOutput.connection(with: .video) {
                connection.videoRotationAngle = 90
                connection.isVideoMirrored = (camera.position == .front)
            }
        } catch {
            print("❌ Session configuration failed: \(error)")
        }
    }

    // MARK: - Smart Zoom Setup (핵심 로직)
    private func setupZoomFactors(for device: AVCaptureDevice) {
        minZoomFactor = device.minAvailableVideoZoomFactor
        maxZoomFactor = min(device.maxAvailableVideoZoomFactor, 15.0 * 2.0)
        
        // 렌즈 전환 포인트
        switchOverZoomFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        
        print("🔭 [Zoom Setup] Device: \(device.deviceType.rawValue)")
        print("🔭 [Zoom Setup] SwitchOver Factors: \(switchOverZoomFactors)")
        print("🔭 [Zoom Setup] Min: \(minZoomFactor), Max: \(maxZoomFactor)")

        // 1. 배율 스케일 결정 (전면/후면 통합 로직)
        if device.position == .back {
            switch device.deviceType {
            case .builtInTripleCamera, .builtInDualWideCamera:
                // 🔥 초광각(0.5x)이 있는 모델: 첫 번째 전환점이 곧 Wide(1.0x) 렌즈의 시작점입니다.
                // 기기마다 2.0이 아닐 수 있으므로(예: 1.5 ~ 3.0), 하드웨어 값을 직접 사용하여 오차를 없앱니다.
                if let wideLensZoom = switchOverZoomFactors.first {
                    zoomFactorScale = wideLensZoom
                } else {
                    // Fallback: 스위치오버 값이 없더라도 이 기기들은 구조상 0.5x(Ultra)가 Base(1.0)임.
                    // 따라서 User 1.0x = Device 2.0x (approx)
                    zoomFactorScale = 2.0
                }
                
                // 🛠 보정: 만약 Scale이 1.1 이하인데 기기 타입이 UltraWide 포함이라면 강제로 2.0으로 보정 (0.5x 버튼 보장)
                if zoomFactorScale < 1.1 {
                    zoomFactorScale = 2.0
                    print("⚠️ [Zoom Setup] Forced Scale to 2.0 for DualWide/Triple Camera")
                }
                
                print("🔭 [Zoom Setup] Scale determined as: \(zoomFactorScale) (UltraWide Base)")
            case .builtInDualCamera:
                 // Wide + Tele (No Ultra Wide)
                 // Base is Wide (1.0). Tele starts at switchOver (e.g. 2.0)
                 zoomFactorScale = 1.0
                 print("🔭 [Zoom Setup] Scale: 1.0 (Wide+Tele Base)")
            default:
                zoomFactorScale = 1.0 // 일반 모델 (Device 1.0 = User 1.0)
                print("🔭 [Zoom Setup] Scale: 1.0 (Standard Base)")
            }
        } else {
            // 전면 카메라
            zoomFactorScale = 1.0
        }
        
        // 2. 버튼 생성 로직
        var buttons: [CGFloat] = []
        
        if device.position == .back {
            // --- 후면 카메라 버튼 ---
            // Scale이 1.1보다 크다 = Base가 UltraWide다 = 0.5x 지원
            if zoomFactorScale > 1.1 { buttons.append(0.5) }
            buttons.append(1.0)
            buttons.append(2.0)
            
            // 망원 렌즈 확인
            // Triple/DualWide (Base: Ultra) -> Index 1 is Tele
            // Dual (Base: Wide) -> Index 0 is Tele
            var teleDeviceZoom: CGFloat?
            
            if zoomFactorScale > 1.1 {
                // Triple/DualWide
                if switchOverZoomFactors.count > 1 {
                    teleDeviceZoom = switchOverZoomFactors[1]
                }
            } else {
                // Dual (Wide+Tele)
                if switchOverZoomFactors.count > 0 {
                    teleDeviceZoom = switchOverZoomFactors[0]
                }
            }
            
            if let teleDev = teleDeviceZoom {
                let teleDisplay = deviceZoomToDisplayZoom(teleDev)
                // 5배줌(Pro Max) vs 3배줌(Pro) 구분 (오차 범위 감안)
                if abs(teleDisplay - 5.0) < 0.5 { buttons.append(5.0) }
                else if abs(teleDisplay - 3.0) < 0.5 { buttons.append(3.0) }
                else { buttons.append(round(teleDisplay * 10) / 10.0) } // 그 외 배율 (예: 2.5)
            }
        } else {
            // --- 전면 카메라 버튼 (동적 감지) ---
            // 최신 아이폰 전면 카메라는 줌 아웃(0.xxx)을 지원할 수 있음
            buttons.append(1.0)
            
            // 전면 카메라가 줌을 지원하는지 확인 (보통 1배보다 작게 줌아웃 가능하거나, 1배보다 크게 줌인 가능)
            // 예: iPhone 12 전면은 1x가 기본이지만 화각을 넓힐 수 있음 (UI상 버튼으로 제공하진 않고 화살표로 제공하지만, 여기선 버튼화 가능)
            // 여기서는 심플하게 1배만 제공하거나, 필요시 로직 추가.
            // (피드백 반영: 전면 카메라는 보통 '화각' 토글이지만, 줌 팩터로는 1.0이 max인 경우가 많음. 일단 1.0 유지하되 확장 가능성 열어둠)
        }

        // 메인 스레드에서 @Published 속성 업데이트
        DispatchQueue.main.async {
            self.zoomButtons = Array(Set(buttons)).sorted()
        }

        // 3. 초기 줌 설정 (1.0x)
        let initialUserZoom: CGFloat = 1.0
        let initialDeviceZoom = displayZoomToDeviceZoom(initialUserZoom)
        
        do {
            try device.lockForConfiguration()
            device.cancelVideoZoomRamp()
            // 범위 체크
            let safeZoom = max(device.minAvailableVideoZoomFactor, min(initialDeviceZoom, device.maxAvailableVideoZoomFactor))
            device.videoZoomFactor = safeZoom
            device.unlockForConfiguration()

            // 메인 스레드에서 @Published 속성 업데이트
            DispatchQueue.main.async {
                self.currentZoom = safeZoom
                self.virtualZoom = self.deviceZoomToDisplayZoom(safeZoom)
                self.updateCurrentLensType(for: safeZoom) // 초기 렌즈 상태 업데이트
            }
        } catch {
            print("❌ Zoom setup failed: \(error)")
        }
    }

    // MARK: - Zoom Helpers
    private func displayZoomToDeviceZoom(_ displayZoom: CGFloat) -> CGFloat {
        return displayZoom * zoomFactorScale
    }

    private func deviceZoomToDisplayZoom(_ deviceZoom: CGFloat) -> CGFloat {
        return deviceZoom / zoomFactorScale
    }

    // MARK: - Public Controls
    // MARK: - Safe Session Control
    private let sessionQueue = DispatchQueue(label: "com.TryAngle.sessionQueue")
    private var pendingPauseWorkItem: DispatchWorkItem? // 지연된 일시정지 작업

    func startSession() {
        // 대기 중인 일시정지 작업이 있다면 취소 (즉시 복귀 시 세션 유지)
        pendingPauseWorkItem?.cancel()
        pendingPauseWorkItem = nil

        // 🔥 UI Guard 제거: 실제 세션 상태는 sessionQueue에서 확인해야 함 (Race Condition 방지)
        // guard !isSessionRunning else { return } <--- 제거
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 중복 실행 방지 (Serial Queue 내부에서 확인)
            guard !self.session.isRunning else {
                print("⚠️ [CameraManager] Start requested but session is already running.")
                DispatchQueue.main.async { self.isSessionRunning = true }
                return
            }
            
            print("🚀 [CameraManager] calling session.startRunning()")
            self.session.startRunning()
            print("✅ [CameraManager] session.startRunning() completed")
            
            DispatchQueue.main.async { self.isSessionRunning = true }
        }
    }

    func stopSession() {
        // 즉시 중지 (앱 종료 등)
        pendingPauseWorkItem?.cancel()
        
        // 🔥 UI Guard 제거: UI 상태와 실제 세션 상태 불일치 방지
        // guard isSessionRunning else { return } <--- 제거
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 실행 중이지 않은데 굳이 멈출 필요 없음 (단, 확실한 cleanup을 위해 체크)
            guard self.session.isRunning else {
                print("⚠️ [CameraManager] Stop requested but session is already stopped.")
                DispatchQueue.main.async { self.isSessionRunning = false }
                return
            }
            
            print("🛑 [CameraManager] calling session.stopRunning()")
            self.session.stopRunning()
            print("✅ [CameraManager] session.stopRunning() completed")
            
            DispatchQueue.main.async { self.isSessionRunning = false }
        }
    }
    
    // 탭 전환 대응 (비동기 처리 + 지연 효과)
    func pauseSession(immediate: Bool = false) {
        // 즉시 중지 요청인 경우
        if immediate {
            print("⏸️ 카메라 세션 즉시 중지 (Tab 전환 / Background)")
            pendingPauseWorkItem?.cancel()
            stopSession() // sessionQueue에서 처리됨
            return
        }
        
        // 5초 지연 대기
        let workItem = DispatchWorkItem { [weak self] in
            print("💤 5초 경과: 카메라 세션 중지")
            self?.stopSession()
        }
        pendingPauseWorkItem = workItem
        // 메인 큐에서 딜레이 후 실행 (취소 가능하도록) -> 실제 stop은 sessionQueue에서
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: workItem)
    }

    func resumeSession() {
        // 복귀 시 startSession 호출 -> 내부에서 pending item 취소됨
        startSession()
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let current = self.currentCamera else { return }
            let newPosition: AVCaptureDevice.Position = (current.position == .back) ? .front : .back
            
            self.session.beginConfiguration()
            if let input = self.currentInput { self.session.removeInput(input) }
            
            // 새 카메라 찾기
            let newCamera = (newPosition == .front)
                ? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                : self.findBestBackCamera()
            
            guard let camera = newCamera else {
                self.session.commitConfiguration()
                return
            }
            
            self.configureSession(with: camera) // 세션 재설정 (여기서 포맷, 방향 등 다 처리됨)
            
            self.session.commitConfiguration()
            
            // 메인 스레드에서 @Published 속성 업데이트
            DispatchQueue.main.async {
                self.isFrontCamera = (newPosition == .front)
            }
            
            // 줌 재설정 (매우 중요: 전면/후면 특성이 다르므로 다시 계산)
            self.setupZoomFactors(for: camera)
        }
    }

    func setZoomAnimated(_ displayFactor: CGFloat) {
        guard let device = currentCamera else { return }
        let deviceFactor = displayZoomToDeviceZoom(displayFactor)
        let clampedFactor = max(minZoomFactor, min(deviceFactor, maxZoomFactor))

        do {
            try device.lockForConfiguration()
            device.ramp(toVideoZoomFactor: clampedFactor, withRate: 30.0) // 부드러운 줌
            device.unlockForConfiguration()

            // ✅ 메인 스레드에서 @Published 속성 업데이트
            DispatchQueue.main.async {
                self.currentZoom = clampedFactor
                self.virtualZoom = self.deviceZoomToDisplayZoom(clampedFactor)
                self.updateCurrentLensType(for: clampedFactor)
            }
        } catch {
            print("❌ Failed to set zoom: \(error)")
        }
    }

    // MARK: - Pinch Zoom (제스처용)
    // MARK: - Pinch Zoom (제스처용)
    // 델타가 아닌 절대값(User Scale)을 받아 즉시 적용
    func setZoomImmediate(_ displayZoom: CGFloat) {
        let deviceFactor = displayZoomToDeviceZoom(displayZoom)
        let clampedFactor = max(minZoomFactor, min(deviceFactor, maxZoomFactor))

        // ✅ 디바운싱: 이전 작업 취소
        pendingZoomWorkItem?.cancel()

        // ✅ 핀치는 반응성이 중요하므로 즉시 실행 (단, 너무 잦은 호출 방지 위해 아주 짧은 딜레이나 스로틀링 고려 가능)
        // 여기서는 부드러운 UI 반응을 위해 디바운싱 없이 즉시 적용하되, 
        // 하드웨어 부하를 줄이기 위해 Global Queue에서 실행
        
        // *수정*: 디바운싱을 하면 뚝뚝 끊김. 핀치는 연속적이므로 즉시 적용해야 함.
        // 다만 lock/unlock 오버헤드가 있으므로 메인 스레드 블로킹 방지가 핵심.
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, let device = self.currentCamera else { return }

            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clampedFactor  // ramp 없이 즉시 변경
                device.unlockForConfiguration()

                // UI 업데이트는 메인에서
                DispatchQueue.main.async {
                    self.currentZoom = clampedFactor
                    self.virtualZoom = self.deviceZoomToDisplayZoom(clampedFactor)
                    self.updateCurrentLensType(for: clampedFactor)
                }
            } catch {
                print("❌ Failed to apply pinch zoom: \(error)")
            }
        }
        
        // 백그라운드에서 즉시 실행
        sessionQueue.async(execute: workItem)
    }

    // 🔥 물리 렌즈 상태 판단 (UI 버튼과 무관하게, 현재 하드웨어 상태)
    private func updateCurrentLensType(for deviceZoom: CGFloat) {
        // 메인 스레드에서 @Published 속성 업데이트
        DispatchQueue.main.async {
            // 전면 카메라는 보통 단일 렌즈
            if self.isFrontCamera {
                self.currentLens = .wide
                return
            }

            // 1. 초광각 구간
            if let wideStart = self.switchOverZoomFactors.first, deviceZoom < wideStart {
                self.currentLens = .ultraWide
                return
            }

            // 2. 망원 구간 (있다면)
            if self.switchOverZoomFactors.count > 1 {
                let teleStart = self.switchOverZoomFactors[1]
                if deviceZoom >= teleStart {
                    self.currentLens = .telephoto
                    return
                }
            }

            // 3. 그 외는 광각 (디지털 줌 포함)
            self.currentLens = .wide
        }
    }
    
    // MARK: - Helper Methods
    private func findBestBackCamera() -> AVCaptureDevice? {
        if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
            isUsingVirtualDevice = true; return triple
        }
        if let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            isUsingVirtualDevice = true; return dualWide
        }
        if let dual = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            isUsingVirtualDevice = true; return dual
        }
        isUsingVirtualDevice = false
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    // MARK: - Format Configuration
    private func configureHighQualityFormat(for device: AVCaptureDevice) {
        let formats = device.formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let mediaType = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            let isVideoFormat = mediaType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
                               mediaType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            // 720p 이상만 (너무 낮은 비디오 포맷 제외)
            guard isVideoFormat && dimensions.height >= 720 else { return false }
            return true
        }

        let sortedFormats = formats.sorted { f1, f2 in
            // 1. 🔥 사진 해상도 우선 (12MP 4032 vs 2MP 1920)
            // supportedMaxPhotoDimensions가 비어있으면 0 취급
            let w1 = f1.supportedMaxPhotoDimensions.last?.width ?? 0
            let w2 = f2.supportedMaxPhotoDimensions.last?.width ?? 0
            
            // 유의미한 차이가 있다면 (예: 4000 vs 1920) 해상도 높은 것 우선
            if abs(Int(w1) - Int(w2)) > 100 {
                return w1 > w2
            }

            // 2. FPS 우선 (60fps)
            let maxFPS1 = f1.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
            let maxFPS2 = f2.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0

            // 60fps 지원 여부를 최우선
            if maxFPS1 >= 59 && maxFPS2 < 59 { return true }
            if maxFPS1 < 59 && maxFPS2 >= 59 { return false }
            
            // 3. 4:3 비율 우선 (센서 비율 매칭)
            let d1 = CMVideoFormatDescriptionGetDimensions(f1.formatDescription)
            let d2 = CMVideoFormatDescriptionGetDimensions(f2.formatDescription)
            let r1 = Float(d1.width) / Float(d1.height)
            let r2 = Float(d2.width) / Float(d2.height)
            
            let is43_1 = abs(r1 - 4.0/3.0) < 0.05
            let is43_2 = abs(r2 - 4.0/3.0) < 0.05
            
            if is43_1 && !is43_2 { return true }
            if !is43_1 && is43_2 { return false }

            // 4. 비디오 해상도는 너무 크지 않은 것 선호 (프리뷰 성능 및 발열 관리)
            // 4K(8MP) vs FHD(2MP) -> 12MP 사진이 가능하다면 FHD가 더 가벼움
            // 단, 사진 해상도가 같다면 비디오 해상도가 높은게 더 선명할 수 있음.
            // 여기서는 사진 해상도가 같다는 전제이므로, 3MP 근처 선호(기존 로직 유지)
            let p1 = Int(d1.width) * Int(d1.height)
            let p2 = Int(d2.width) * Int(d2.height)
            return abs(p1 - 3_000_000) < abs(p2 - 3_000_000)
        }

        if let bestFormat = sortedFormats.first {
            do {
                try device.lockForConfiguration()
                device.activeFormat = bestFormat
                
                // 설정된 포맷 정보 로그
                let dim = CMVideoFormatDescriptionGetDimensions(bestFormat.formatDescription)
                let maxPhoto = bestFormat.supportedMaxPhotoDimensions.last
                print("✅ [설정됨] 포맷: Video=\(dim.width)x\(dim.height), Photo=\(maxPhoto?.width ?? 0)x\(maxPhoto?.height ?? 0)")

                // 🔥 60fps 설정 (안전하게 설정)
                // 만약 60fps를 지원한다면 설정하고, 아니라면 최대 지원 FPS로 설정
                if let maxFPSRange = bestFormat.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) {
                    // 고해상도(4K 이상)에서는 60fps가 발열을 유발하거나 불안정할 수 있음 -> 30fps로 fallback 고려 가능
                    // 여기서는 지원 범위 내에서만 안전하게 설정
                    let safeMaxFPS = maxFPSRange.maxFrameRate
                    let verifyFPS = (safeMaxFPS >= 59.0) ? 60.0 : 30.0
                    
                    // 실제 설정 (Range 체크)
                    if safeMaxFPS >= verifyFPS {
                        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(verifyFPS))
                        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(verifyFPS))
                        print("✅ [FPS 설정] Target: \(verifyFPS)fps (Max Support: \(safeMaxFPS))")
                    } else {
                        print("⚠️ [FPS 설정] 60fps 미지원 -> 기본값 유지 (Max: \(safeMaxFPS))")
                    }
                }
                device.unlockForConfiguration()
            } catch {
                print("❌ 포맷 설정 실패 (Fig Error 가능성): \(error)")
            }
        }
    }

    private func analyzeCameraCharacteristics(for device: AVCaptureDevice) {
        // 광각 카메라의 FOV를 통해 35mm 환산 초점거리 계산
        if let wideCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            for format in wideCamera.formats {
                let wideFov = format.videoFieldOfView
                if wideFov > 0 && wideFov < 90 {
                    let wide35mm = 36.0 / (2.0 * tan(CGFloat(wideFov) * .pi / 180.0 / 2.0))
                    baseFocalLength35mm = wide35mm
                    break
                }
            }
        } else {
            baseFocalLength35mm = 24.0
        }
    }
    
    // MARK: - EXIF Info
    var focalLengthIn35mm: Int {
        if isFrontCamera { return 24 } // 전면 고정값

        // 현재 물리 렌즈의 35mm 환산 초점거리
        let baseFocal35mm: Int
        switch currentLens {
        case .ultraWide:
            baseFocal35mm = 13  // 초광각 13mm
        case .wide:
            baseFocal35mm = 24  // 광각 24mm (기본 카메라와 동일)
        case .telephoto:
            baseFocal35mm = 77  // 망원 77mm (3배줌 기준)
        }

        // 디지털 줌 적용 (물리 렌즈 기준에서 추가 확대)
        // 예: wide(24mm) + 2배 디지털 줌 = 48mm
        return Int(round(Double(baseFocal35mm) * Double(virtualZoom)))
    }

    var actualFocalLength: Double {
        // 실제 물리적 초점거리 (mm) - 센서 크기 반영
        if isFrontCamera {
            return 2.71  // 전면 카메라 고정값
        }

        // 후면 카메라: 현재 물리 렌즈의 실제 초점거리
        let baseFocal: Double
        switch currentLens {
        case .ultraWide:
            baseFocal = 1.54  // 초광각 1.54mm (13mm in 35mm)
        case .wide:
            baseFocal = 4.25  // 광각 4.25mm (24mm in 35mm) - 기본 카메라
        case .telephoto:
            baseFocal = 9.0   // 망원 9.0mm (77mm in 35mm, 3배줌)
        }

        return baseFocal  // 실제 초점거리는 물리 렌즈 값만 반환 (디지털 줌 미적용)
    }

    var currentAperture: Double {
        // 조리개값 (f-number) - 렌즈별 고정값
        if isFrontCamera {
            return 2.2  // 전면 카메라 f/2.2
        }

        switch currentLens {
        case .ultraWide:
            return 2.4   // 초광각 f/2.4
        case .wide:
            return 1.78  // 광각 f/1.78 (기본 카메라)
        case .telephoto:
            return 2.8   // 망원 f/2.8
        }
    }

    // 사진 촬영, 플래시 등 나머지 기능은 기존 유지
    func capturePhoto(completion: @escaping (Data?, Error?) -> Void) {
        guard isSessionRunning else { return }
        photoCaptureCompletion = completion
        let settings = AVCapturePhotoSettings()
        settings.flashMode = (isFlashOn && currentCamera?.hasFlash == true) ? .on : .off
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func toggleFlash() {
        guard let device = currentCamera, device.hasTorch else { return }
        try? device.lockForConfiguration()
        if device.torchMode == .on {
            device.torchMode = .off
            isFlashOn = false
        } else {
            try? device.setTorchModeOn(level: 1.0)
            isFlashOn = true
        }
        device.unlockForConfiguration()
    }

    // MARK: - Aspect Ratio & Focus
    func setAspectRatio(_ ratio: CameraAspectRatio) {
        // 🔥 UI 상태만 업데이트 (하드웨어 포맷 변경 X -> 깜빡임 제거)
        // 4:3 센서를 그대로 사용하고, UI에서 마스킹함.
        DispatchQueue.main.async {
            self.aspectRatio = ratio
        }
    }

    private func configureFormatForAspectRatio(_ ratio: CameraAspectRatio, device: AVCaptureDevice) {
        let targetRatio: Float
        switch ratio {
        case .ratio16_9: targetRatio = 16.0 / 9.0
        case .ratio4_3: targetRatio = 4.0 / 3.0
        case .ratio1_1: targetRatio = 4.0 / 3.0  // 1:1은 4:3을 크롭해서 사용
        }

        // 비율에 맞는 포맷 필터링
        let formats = device.formats.filter { format in
            let dim = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let mediaType = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            let isVideoFormat = mediaType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
                               mediaType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            guard isVideoFormat && dim.height >= 1080 else { return false }
            let fr = Float(dim.width) / Float(dim.height)
            return abs(fr - targetRatio) < 0.01
        }

        // 🔥 60fps 지원하는 포맷 우선 선택
        let sortedFormats = formats.sorted { f1, f2 in
            // FPS 범위 확인
            let maxFPS1 = f1.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
            let maxFPS2 = f2.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0

            // 60fps 지원 여부를 최우선
            if maxFPS1 >= 60 && maxFPS2 < 60 { return true }
            if maxFPS1 < 60 && maxFPS2 >= 60 { return false }

            // 해상도는 적당한 크기 선호 (3MP 근처)
            let d1 = CMVideoFormatDescriptionGetDimensions(f1.formatDescription)
            let d2 = CMVideoFormatDescriptionGetDimensions(f2.formatDescription)
            let p1 = Int(d1.width) * Int(d1.height)
            let p2 = Int(d2.width) * Int(d2.height)
            return abs(p1 - 3_000_000) < abs(p2 - 3_000_000)
        }

        if let bestFormat = sortedFormats.first {
            do {
                try device.lockForConfiguration()
                device.activeFormat = bestFormat

                // 🔥 60fps 설정 (매우 중요!)
                if let maxFPSRange = bestFormat.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) {
                    let targetFPS = min(maxFPSRange.maxFrameRate, 60.0)
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
                    device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
                    print("✅ 화면비 변경: \(ratio) @ \(targetFPS)fps")
                }

                device.unlockForConfiguration()
            } catch {
                print("❌ 화면비 포맷 설정 실패: \(error)")
            }
        }
    }

    func setFocus(at point: CGPoint) {
        guard let device = currentCamera else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
        } catch {
            print("❌ 포커스 설정 실패: \(error)")
        }
    }
}

// MARK: - Delegate Extensions
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 1. Send straight to analysis pipeline (Background Thread)
        frameSubject.send(sampleBuffer)
        
        guard let _ = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 중복 버퍼 방지 (Timestamp check)
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        if timestamp == lastBufferTime { return }
        lastBufferTime = timestamp

        // FPS 계산 (Throttled update)
        fpsFrameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSUpdate)
        if elapsed >= 1.0 {
            let fps = Double(fpsFrameCount) / elapsed
            // UI Update on Main Thread
            DispatchQueue.main.async { [weak self] in
                self?.currentFPS = fps
            }
            fpsFrameCount = 0
            lastFPSUpdate = now
        }
        
        // 2. Optional: Create UIImage for UI Preview *only if needed* (e.g. for small thumbnail or specific logic)
        // Since we use AVCaptureVideoPreviewLayer, we DO NOT need to convert every frame to UIImage for the main preview.
        // If ContentView needs `currentFrame` for some other logic (like analysis visualization overlay), we can throttle it here.
        
        /*
        // 이미지 변환 (Expensive!)
        // Only do this if strictly necessary for UI other than preview
        /*
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        // ... (Orientation logic) ...
        
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: imageOrientation)
        
        // Send to UI stream (Throttled)
        let currentTime = CACurrentMediaTime()
        if currentTime - lastFrameUpdateTime >= minFrameUpdateInterval {
            lastFrameUpdateTime = currentTime
            DispatchQueue.main.async { [weak self] in
                 self?.frameImageSubject.send(image)
            }
        }
        */
         */
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        photoCaptureCompletion?(data, error)
    }
}
