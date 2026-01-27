import SwiftUI
import Photos
import ImageIO
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    // MARK: - State
    @Binding var referenceImage: UIImage?  // 레퍼런스 이미지 (MainTabView에서 전달)
    @Binding var referenceImageData: Data?  // 🆕 EXIF 추출용 원본 데이터
    var isActiveTab: Bool = true  // 현재 탭이 활성화 상태인지 (MainTabView에서 전달)
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var realtimeAnalyzer = AnalysisCoordinator()  // 실시간 분석 (리팩토링됨)
    @ObservedObject private var thermalManager = SystemMonitor.shared  // 🔥 발열/배터리 관리
    @State private var feedbackItems: [FeedbackItem] = []
    @State private var serverFeedbackItems: [FeedbackItem] = []  // 서버 피드백 (포즈 등)
    @State private var processingTime: String = ""
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var analysisTimer: Timer?

    // @State private var frameUpdateTimer: Timer?  <- REMOVED: Using Combine

    // 🔥 UI 반응성 개선: 초기화 상태 관리
    @State private var isInitializing = true  // 초기화 중 플래그
    @State private var appLaunchTime = Date()  // 앱 시작 시간

    // UI 상태
    @State private var showGrid = false
    @State private var showFPS = false
    @State private var autoCapture = true
    @State private var capturedImage: UIImage?
    @State private var showCaptureFlash = false
    @State private var selectedAspectRatio: CameraAspectRatio = .ratio4_3
    @State private var showSettings = false  // 설정 시트
    @State private var showCameraOptions = false  // 카메라 옵션 펼침/접기

    // 🆕 사진 분석 관련 상태
    @State private var photoAnalysisResult: PhotoAnalysisResult?
    @State private var showQuickFeedback = false  // 빠른 피드백 시트
    @State private var showDetailedAnalysis = false  // 상세 분석 화면
    @State private var isAnalyzingPhoto = false  // 분석 중 상태

    // 🆕 레퍼런스 이미지 전체화면 보기
    @State private var showReferenceFullScreen = false

    // AI 분석은 레퍼런스 선택 시 자동 활성화
    private var analysisEnabled: Bool {
        referenceImage != nil
    }

    // 통합 피드백 (실시간 + 서버)
    private var combinedFeedback: [FeedbackItem] {
        var combined: [FeedbackItem] = []

        // 1순위: 실시간 피드백 (프레이밍, 구도)
        combined.append(contentsOf: realtimeAnalyzer.instantFeedback)

        // 🔍 디버그
        if !realtimeAnalyzer.instantFeedback.isEmpty {
            print("🎯 ContentView combinedFeedback: \(realtimeAnalyzer.instantFeedback.count)개")
        }

        // 2순위: 서버 피드백 (포즈) - 실시간 피드백과 중복되지 않는 것만
        let realtimeCategories = Set(realtimeAnalyzer.instantFeedback.map { $0.category })
        let uniqueServerFeedback = serverFeedbackItems.filter {
            !realtimeCategories.contains($0.category) && $0.category == "pose"
        }
        combined.append(contentsOf: uniqueServerFeedback)

        // 우선순위로 정렬하고 상위 5개만 반환
        let result = Array(combined.sorted { $0.priority < $1.priority }.prefix(5))

        if !result.isEmpty {
            print("✅ 최종 combinedFeedback: \(result.count)개")
        }

        return result
    }

    // 피드백 업데이트
    private func updateCombinedFeedback() {
        // combinedFeedback은 computed property라서 자동 업데이트됨
        // 필요시 추가 로직
    }

    // 사진 촬영 (실제 카메라 촬영 사용)
    private func performCapture() {
        // 🆕 촬영 즉시 Temporal Lock 리셋 (연속 촬영 방지)
        realtimeAnalyzer.resetAfterCapture()

        // 🆕 실제 카메라로 사진 촬영 (줌 배율 그대로 적용)
        cameraManager.capturePhoto { [self] imageData, error in
            // ✅ 이미지 처리를 백그라운드로 이동 (메인 스레드 프리징 방지)
            DispatchQueue.global(qos: .userInitiated).async {
                // 에러 체크
                if let error = error {
                    print("❌ 촬영 실패: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        errorMessage = "촬영 실패: \(error.localizedDescription)"
                    }
                    return
                }

                guard let imageData = imageData,
                      let originalImage = UIImage(data: imageData) else {
                    print("❌ 이미지 변환 실패")
                    return
                }

                // 🔥 무거운 작업: 이미지 크롭 (백그라운드)
                let croppedImage = cropImage(originalImage, to: selectedAspectRatio)

                // 메인 스레드에서 UI만 업데이트
                DispatchQueue.main.async {
                    // 미리보기 이미지 설정
                    capturedImage = croppedImage

                    print("📸 사진 촬영 완료! (줌: \(cameraManager.virtualZoom)x, 초점거리: \(cameraManager.focalLengthIn35mm)mm)")

                    // 5초 후 다시 촬영 가능
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        capturedImage = nil
                    }
                }

                // 🔥 무거운 작업: EXIF 포함 저장 (최저 우선순위 백그라운드)
                DispatchQueue.global(qos: .background).async {
                    savePhotoDataToLibrary(imageData, croppedImage: croppedImage)
                }
            }
        }
    }

    // 🆕 크롭된 이미지를 EXIF와 함께 저장
    private func savePhotoDataToLibrary(_ originalData: Data, croppedImage: UIImage) {
        // 원본 EXIF 메타데이터 추출
        var metadata: [String: Any] = [:]
        if let source = CGImageSourceCreateWithData(originalData as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            metadata = properties
        }

        // 추가 EXIF 정보 (앱에서 계산한 35mm 환산 초점거리)
        var exifDict = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        exifDict[kCGImagePropertyExifFocalLenIn35mmFilm as String] = cameraManager.focalLengthIn35mm
        exifDict[kCGImagePropertyExifLensModel as String] = getLensModelString()
        metadata[kCGImagePropertyExifDictionary as String] = exifDict

        // 크롭된 이미지를 EXIF와 함께 JPEG로 변환
        guard let finalData = createJPEGWithEXIF(image: croppedImage, exifData: metadata) else {
            print("❌ 최종 이미지 생성 실패")
            return
        }

        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                print("⚠️ 사진 라이브러리 권한 없음")
                return
            }

            PHPhotoLibrary.shared().performChanges {
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: finalData, options: nil)
            } completionHandler: { success, error in
                if success {
                    print("✅ 사진 저장 성공 (EXIF 포함: \(self.cameraManager.focalLengthIn35mm)mm)")
                } else if let error = error {
                    print("❌ 사진 저장 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    // 이미지를 선택한 비율로 크롭
    private func cropImage(_ image: UIImage, to aspectRatio: CameraAspectRatio) -> UIImage {
        // 1. 이미지 회전 보정 (정방향으로 그리기)
        // 백그라운드 스레드에서 실행되므로 UIGraphicsImageRenderer 사용 가능 (iOS 10+)
        // 원본 해상도 유지
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        
        let normalizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        
        guard let cgImage = normalizedImage.cgImage else { return image }
        
        // 2. 논리적 좌표계(회전 보정됨)에서의 크기
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let currentRatio = width / height
        let targetRatio = aspectRatio.ratio // 4:3(1.33), 16:9(1.77)
        
        // 3. 목표 비율에 맞는 크롭 영역 계산 (세로 모드 기준: 1.0 / targetRatio 역수 사용 아님)
        // 여기서는 이미 정방향(세로)이므로, 목표 비율도 세로 비율(Short/Long)을 따르거나,
        // 가로가 짧은 세로 사진(Portrait)이라면 aspect ratio는 (Width < Height)이므로 3/4(0.75), 9/16(0.56)가 됨.
        
        // CameraAspectRatio가 정의한 .ratio 값:
        // .ratio4_3 = 4/3 (1.33)
        // .ratio16_9 = 16/9 (1.77)
        // .ratio1_1 = 1.0
        
        // 현재 이미지가 Portrait (W < H) 인지 Landscape (W > H) 인지 확인
        let isPortrait = width < height
        
        // 목표 비율 (긴변 / 짧은변)
        // 4:3 -> 1.333
        // 16:9 -> 1.777
        let targetLongOverShort = targetRatio >= 1 ? targetRatio : 1.0/targetRatio
        
        // 실제 적용할 가로/세로 비율
        // Portrait라면: Width / Height = 1 / targetLongOverShort (0.75, 0.56)
        // Landscape라면: Width / Height = targetLongOverShort (1.33, 1.77)
        let targetWH = isPortrait ? (1.0 / targetLongOverShort) : targetLongOverShort
        
        var cropRect: CGRect
        
        if currentRatio > targetWH {
            // 현재가 더 넓적함 (가로를 잘라내야 함)
            // Height 기준, Width를 줄임
            let targetWidth = height * targetWH
            let xOffset = (width - targetWidth) / 2
            cropRect = CGRect(x: xOffset, y: 0, width: targetWidth, height: height)
        } else {
            // 현재가 더 길쭉함 (세로를 잘라내야 함)
            // Width 기준, Height를 줄임
            let targetHeight = width / targetWH
            let yOffset = (height - targetHeight) / 2
            cropRect = CGRect(x: 0, y: yOffset, width: width, height: targetHeight)
        }
        
        // 4. 크롭 실행
        guard let croppedCG = cgImage.cropping(to: cropRect) else { return image }
        
        return UIImage(cgImage: croppedCG, scale: normalizedImage.scale, orientation: .up)
    }

    // 🔧 사진을 EXIF 데이터와 함께 저장
    private func saveImageToPhotoLibrary(_ image: UIImage) {
        // EXIF 메타데이터 생성
        let exifData = createEXIFMetadata()

        // 이미지를 EXIF가 포함된 JPEG Data로 변환
        guard let imageData = createJPEGWithEXIF(image: image, exifData: exifData) else {
            print("❌ EXIF 포함 JPEG 생성 실패")
            return
        }

        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                print("⚠️ 사진 라이브러리 권한 없음")
                return
            }

            PHPhotoLibrary.shared().performChanges {
                // EXIF가 포함된 Data로 저장
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: imageData, options: nil)
            } completionHandler: { success, error in
                if success {
                    print("✅ 사진 저장 성공 (EXIF 포함: \(self.cameraManager.focalLengthIn35mm)mm)")
                } else if let error = error {
                    print("❌ 사진 저장 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    /// EXIF 메타데이터 생성 (렌즈 정보 포함)
    private func createEXIFMetadata() -> [String: Any] {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let dateString = dateFormatter.string(from: now)

        // EXIF 딕셔너리
        var exif: [String: Any] = [
            kCGImagePropertyExifDateTimeOriginal as String: dateString,
            kCGImagePropertyExifDateTimeDigitized as String: dateString,
            kCGImagePropertyExifFocalLenIn35mmFilm as String: cameraManager.focalLengthIn35mm,
            kCGImagePropertyExifFocalLength as String: cameraManager.actualFocalLength,
            kCGImagePropertyExifFNumber as String: cameraManager.currentAperture,  // 조리개값
            kCGImagePropertyExifLensMake as String: "Apple",
            kCGImagePropertyExifLensModel as String: getLensModelString(),
            kCGImagePropertyExifColorSpace as String: 1,  // sRGB
        ]

        // ISO (가능하면)
        if let iso = getCurrentISO() {
            exif[kCGImagePropertyExifISOSpeedRatings as String] = [iso]
        }

        // TIFF 딕셔너리 (카메라 제조사 정보)
        let tiff: [String: Any] = [
            kCGImagePropertyTIFFMake as String: "Apple",
            kCGImagePropertyTIFFModel as String: getDeviceModel(),
            kCGImagePropertyTIFFSoftware as String: "TryAngle",
            kCGImagePropertyTIFFDateTime as String: dateString,
        ]

        return [
            kCGImagePropertyExifDictionary as String: exif,
            kCGImagePropertyTIFFDictionary as String: tiff,
        ]
    }

    /// 렌즈 모델 문자열 생성
    private func getLensModelString() -> String {
        if cameraManager.isFrontCamera {
            return "iPhone Front Camera"
        }

        let focalLength = cameraManager.focalLengthIn35mm
        let aperture = String(format: "%.2f", cameraManager.currentAperture)

        // currentLens에 따라 정확한 렌즈 이름 반환
        switch cameraManager.currentLens {
        case .ultraWide:
            return "iPhone \(focalLength)mm f/\(aperture)"  // 예: "iPhone 13mm f/2.40"
        case .wide:
            return "iPhone \(focalLength)mm f/\(aperture)"  // 예: "iPhone 24mm f/1.78"
        case .telephoto:
            return "iPhone \(focalLength)mm f/\(aperture)"  // 예: "iPhone 77mm f/2.80"
        }
    }

    /// 디바이스 모델명 가져오기
    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    /// 현재 ISO 가져오기 (가능하면)
    private func getCurrentISO() -> Int? {
        // CameraManager에서 현재 ISO를 가져오는 로직
        // 현재는 nil 반환 (추후 확장 가능)
        return nil
    }

    /// UIImage를 EXIF 메타데이터가 포함된 JPEG Data로 변환
    private func createJPEGWithEXIF(image: UIImage, exifData: [String: Any]) -> Data? {
        guard let cgImage = image.cgImage else { return nil }

        let mutableData = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        // 이미지 방향 정보 추가
        var properties = exifData
        properties[kCGImagePropertyOrientation as String] = cgImageOrientationFromUIImage(image)

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }

        return mutableData as Data
    }

    /// UIImage orientation → CGImage orientation 변환
    private func cgImageOrientationFromUIImage(_ image: UIImage) -> Int {
        switch image.imageOrientation {
        case .up: return 1
        case .down: return 3
        case .left: return 8
        case .right: return 6
        case .upMirrored: return 2
        case .downMirrored: return 4
        case .leftMirrored: return 5
        case .rightMirrored: return 7
        @unknown default: return 1
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let safeAreaTop = geometry.safeAreaInsets.top
            let _ = geometry.safeAreaInsets.bottom
            let screenHeight = geometry.size.height
            let screenWidth = geometry.size.width

            // 카메라 뷰박스 높이 계산
            let captureHeight: CGFloat = {
                switch selectedAspectRatio {
                case .ratio4_3:
                    return screenWidth * 4.0 / 3.0
                case .ratio1_1:
                    return screenWidth
                case .ratio16_9:
                    return screenWidth * 16.0 / 9.0
                }
            }()
            let maskHeight = max(0, (screenHeight - captureHeight) / 2)

            ZStack {
                if cameraManager.isAuthorized {
                    authorizedContent(geometry: geometry, captureHeight: captureHeight, maskHeight: maskHeight, safeAreaTop: safeAreaTop)
                } else {
                    unauthorizedView
                }
            }
        }
        .onChange(of: realtimeAnalyzer.isPerfect) { oldValue, newValue in
            // ✅ 연속 촬영 가능: capturedImage 조건 제거
            if newValue && autoCapture {
                performCapture()
            }
        }
        .onChange(of: selectedAspectRatio) { oldValue, newValue in
            // 🔥 비동기 처리 (UI 블로킹 방지)
            Task {
                cameraManager.setAspectRatio(newValue)

                // 비율 변경시 즉시 프레임 재분석 로직은 스트림이 알아서 처리함
                // Force analysis update if needed? 
                // Combine stream will pick up next frame with new ratio.
            }
        }
        .onChange(of: referenceImage) { _, newImage in
            // 레퍼런스 이미지 변경 시 분석 시작
            if let image = newImage {
                print("🎯🎯🎯 레퍼런스 이미지 선택됨!")

                // 🔥 레퍼런스 이미지를 먼저 analyzeReference로 분석 (🆕 EXIF 데이터 포함)
                // ⚠️ 비동기 함수: 분석은 백그라운드에서 진행됨
                realtimeAnalyzer.analyzeReference(image, imageData: referenceImageData)
                print("📤 레퍼런스 이미지 분석 시작됨 (비동기, EXIF data: \(referenceImageData != nil ? "있음" : "없음"))")
            } else {
                // 레퍼런스 이미지가 없으면 분석 중지
                print("⏹️ 레퍼런스 제거됨 - 분석 중지")
            }
        }
        .onChange(of: isActiveTab) { _, isActive in
            // 탭 전환 감지: 카메라 탭으로 돌아오면 재개, 다른 탭으로 가면 중지
            if isActive {
                print("🎬 카메라 탭 활성화: 카메라 및 분석 재개")
                cameraManager.resumeSession()
                realtimeAnalyzer.resumeAnalysis()

                // 🆕 세션 복구 보장: 0.5초 후 세션 상태 확인 및 재시작
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if isActiveTab && !cameraManager.isSessionRunning {
                        print("⚠️ 카메라 세션 미실행 감지 - 재시작 시도")
                        cameraManager.startSession()
                    }
                }
            } else {
                print("⏸️ 카메라 탭 비활성화: 카메라 및 분석 중지")
                // 🔥 Gallery Crash 방지: 다른 탭(특히 갤러리/포토피커) 진입 시 즉시 자원 해제
                cameraManager.pauseSession(immediate: true)
                realtimeAnalyzer.pauseAnalysis()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                showGrid: $showGrid,
                showFPS: $showFPS,
                autoCapture: $autoCapture,
                cameraManager: cameraManager
            )
        }
        // 🆕 빠른 피드백 시트
        .sheet(isPresented: $showQuickFeedback) {
            if let result = photoAnalysisResult {
                QuickFeedbackSheet(
                    analysisResult: result,
                    onDetailTap: {
                        showQuickFeedback = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showDetailedAnalysis = true
                        }
                    },
                    onDismiss: {
                        showQuickFeedback = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        // 🆕 상세 분석 화면
        .fullScreenCover(isPresented: $showDetailedAnalysis) {
            if let result = photoAnalysisResult {
                DetailedAnalysisView(
                    analysisResult: result,
                    onReanalyze: {
                        showDetailedAnalysis = false
                        // 다시 촬영하도록 유도
                        capturedImage = nil
                        photoAnalysisResult = nil
                    },
                    onDismiss: {
                        showDetailedAnalysis = false
                    }
                )
            }
        }
        // 🆕 레퍼런스 이미지 전체화면 보기
        .fullScreenCover(isPresented: $showReferenceFullScreen) {
            if let refImage = referenceImage {
                ReferenceImageFullScreenView(
                    image: refImage,
                    onDismiss: {
                        showReferenceFullScreen = false
                    }
                )
            }
        }
        // 🆕 시트/커버 열릴 때 분석 일시 중지 (UI 반응성 확보)
        .onChange(of: showSettings) { _, isShown in
            if isShown {
                print("⚙️ 설정 열림: 분석 일시 중지")
                realtimeAnalyzer.pauseAnalysis()
            } else if isActiveTab {
                print("⚙️ 설정 닫힘: 분석 재개")
                realtimeAnalyzer.resumeAnalysis()
            }
        }
        .onChange(of: showQuickFeedback) { _, isShown in
            if isShown { realtimeAnalyzer.pauseAnalysis() }
            else if isActiveTab && !showDetailedAnalysis { realtimeAnalyzer.resumeAnalysis() }
        }
        .onChange(of: showDetailedAnalysis) { _, isShown in
            if isShown { realtimeAnalyzer.pauseAnalysis() }
            else if isActiveTab { realtimeAnalyzer.resumeAnalysis() }
        }
        // 🆕 ScenePhase Handling (Replaces NotificationCenter)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                print("☀️ 포어그라운드 진입: 카메라 및 분석 재개")
                cameraManager.startSession()
                if referenceImage != nil {
                     realtimeAnalyzer.resumeAnalysis()
                }

                // 🆕 세션 복구 보장: 1초 후 세션 상태 확인 및 재시작
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if isActiveTab && !cameraManager.isSessionRunning {
                        print("⚠️ [ScenePhase] 카메라 세션 미실행 감지 - 재시작 시도")
                        cameraManager.startSession()
                    }
                }
            } else if newPhase == .background {
                print("🌙 백그라운드 진입: 카메라 및 분석 중단 (배터리 절약)")
                cameraManager.stopSession()
                realtimeAnalyzer.pauseAnalysis()
            }
        }
    }

    // MARK: - 사진 분석 및 피드백 표시

    /// 촬영된 이미지를 분석하고 피드백 시트 열기
    private func analyzeAndShowFeedback(image: UIImage) {
        guard !isAnalyzingPhoto else { return }

        isAnalyzingPhoto = true

        Task {
            let result = await PhotoAnalyzer.shared.analyze(
                capturedImage: image,
                referenceImage: referenceImage,
                referenceAnalysis: realtimeAnalyzer.referenceAnalysis,
                gateEvaluation: realtimeAnalyzer.gateEvaluation
            )

            await MainActor.run {
                photoAnalysisResult = result
                isAnalyzingPhoto = false
                showQuickFeedback = true
            }
        }
    }

    // MARK: - Analysis Control

    /// 실시간 프레임 분석 시작 (클라이언트 사이드) - 적응형 속도
    // MARK: - Legacy Timer Removed
    // startRealtimeAnalysis / stopRealtimeAnalysis methods removed. 
    // Logic is now handled by Combine subscription in RealtimeAnalyzer.
    
    /// 서버 분석 시작 (포즈 등 복잡한 분석용)
    private func startAnalysis() {
        guard referenceImage != nil else { return }

        // 기존 타이머 중지
        stopAnalysis()

        // 2초마다 서버 분석 (포즈만)
        let timer = Timer(timeInterval: 2.0, repeats: true) { _ in
            Task {
                await performAnalysis()
            }
        }

        // 🔥 UI 반응성 개선: common 모드로 추가
        RunLoop.main.add(timer, forMode: .common)
        analysisTimer = timer
    }

    /// 서버 분석 중지
    private func stopAnalysis() {
        analysisTimer?.invalidate()
        analysisTimer = nil
        serverFeedbackItems = []
        processingTime = ""
    }

    // MARK: - Helper Functions

    /// 발열 상태 이모지
    private func thermalStateEmoji(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "❄️"
        case .fair: return "☁️"
        case .serious: return "🔥"
        case .critical: return "🚨"
        @unknown default: return "❓"
        }
    }

    /// 발열 상태 색상
    private func thermalColor(_ state: ProcessInfo.ThermalState) -> Color {
        switch state {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }

    // MARK: - Lifecycle with ScenePhase
    @Environment(\.scenePhase) private var scenePhase

    // (Removed manual setupBackgroundHandling / removeBackgroundHandling)


    /// 실제 분석 수행 (V1: 온디바이스만 사용, 서버 연결 비활성화)
    private func performAnalysis() async {
        // 분석 모드가 꺼져있으면 스킵
        guard analysisEnabled else {
            return
        }

        // 이미 분석 중이면 스킵 (중복 요청 방지)
        guard !isAnalyzing else {
            print("⏭️ 이전 분석이 진행 중이므로 스킵")
            return
        }

        guard referenceImage != nil else {
              // cameraManager.currentFrame != nil check removed as it is no longer published
             return
        }

        isAnalyzing = true
        errorMessage = nil

        // V1: 온디바이스 분석만 사용 (서버 연결 안 함)
        // RealtimeAnalyzer가 모든 분석을 처리함 (YOLO + MoveNet + Vision)
        // serverFeedbackItems는 사용하지 않음 (combinedFeedback에서 realtimeAnalyzer.instantFeedback만 사용)

        await MainActor.run {
            serverFeedbackItems = []  // 서버 피드백 비우기
            processingTime = "On-Device"  // 온디바이스 표시
            isAnalyzing = false
        }
    }
}

// MARK: - Aspect Ratio Mask View

struct AspectRatioMaskView: View {
    let selectedRatio: CameraAspectRatio

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height

            // 실제 iPhone 카메라처럼: 4:3이 기본(전체 화면), 나머지는 위아래 크롭
            // iPhone 화면 비율은 대략 19.5:9 (2.16:1)

            let captureHeight: CGFloat = {
                switch selectedRatio {
                case .ratio4_3:
                    // 4:3 - 세로 모드에서 4:3 비율 (width x width*4/3)
                    // iPhone 카메라 센서의 기본 비율 (가로:세로 = 4:3)
                    // 세로 모드에서는 너비를 기준으로 높이 계산
                    return screenWidth * 4.0 / 3.0

                case .ratio1_1:
                    // 1:1 - 정사각형, 너비를 기준으로 높이 설정
                    return screenWidth

                case .ratio16_9:
                    // 16:9 - 와이드, 가장 좁은 높이
                    return screenWidth * 16.0 / 9.0
                }
            }()

            // 위아래 마스크 높이 계산
            let maskHeight = max(0, (screenHeight - captureHeight) / 2)

            ZStack {
                if maskHeight > 0 {
                    // 상단 마스크 (완전 불투명)
                    VStack {
                        Rectangle()
                            .fill(Color.black)
                            .frame(height: maskHeight)
                        Spacer()
                    }

                    // 하단 마스크 (완전 불투명)
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(Color.black)
                            .frame(height: maskHeight)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Lens Selector (자동 생성된 버튼 사용)
struct LensSelector: View {
    @ObservedObject var cameraManager: CameraManager

    var body: some View {
        Group {
            // 후면 카메라일 때만 표시
            if !cameraManager.isFrontCamera {
                HStack(spacing: 8) {
                    // 🔥 CameraManager가 기기 분석 후 만들어준 버튼 리스트를 그대로 사용
                    ForEach(cameraManager.zoomButtons, id: \.self) { zoom in
                        // 현재 줌 상태에 따라 활성화된 버튼인지 판단 (Range Logic)
                        // 예: 1.0 ~ 2.9 -> 1x 버튼 활성화, 표시값은 1.5x 등 변경
                        let isActive = isButtonActive(zoom)
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                cameraManager.setZoomAnimated(zoom)
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(isActive ? Color.yellow.opacity(0.8) : Color.black.opacity(0.5))
                                    .frame(width: 30, height: 30)
                                
                                // 활성화된 경우: 실시간 줌 배율 표시 (소수점 1자리)
                                // 비활성 경우: 버튼의 기본 배율 표시 (0.5, 1, 3 등)
                                Text(isActive ? String(format: "%.1fx", cameraManager.virtualZoom) : "\(String(format: "%g", zoom))")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(isActive ? .black : .white)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.3))
                )
                .padding(.bottom, 16)
            }
        }
    }
    
    // 현재 줌 배율이 어떤 버튼 범위에 속하는지 판단
    private func isButtonActive(_ buttonZoom: CGFloat) -> Bool {
        let currentZoom = cameraManager.virtualZoom
        let buttons = cameraManager.zoomButtons.sorted()
        
        // 버튼이 하나뿐이면 그게 활성
        if buttons.count <= 1 { return buttonZoom == buttons.first }
        
        // 현재 줌보다 작거나 같은 버튼 중 가장 큰 것 찾기 (Base Lens)
        // 단, 0.5와 1.0 사이처럼 구간이 명확한 경우
        
        guard let index = buttons.firstIndex(of: buttonZoom) else { return false }
        
        // 마지막 버튼인 경우: 자기보다 크면 다 자기꺼
        if index == buttons.count - 1 {
            return currentZoom >= buttonZoom - 0.1
        }
        
        // 중간 버튼인 경우: 자기 이상 ~ 다음 버튼 미만
        let nextButtonZoom = buttons[index + 1]
        return currentZoom >= buttonZoom - 0.1 && currentZoom < nextButtonZoom - 0.1
    }
}

// MARK: - Debug Overlay (성능 최적화: 별도 View로 분리)
struct DebugOverlay: View {
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var thermalManager: SystemMonitor
    @ObservedObject var realtimeAnalyzer: AnalysisCoordinator
    let referenceImage: UIImage?
    let thermalStateEmoji: (ProcessInfo.ThermalState) -> String
    let thermalColor: (ProcessInfo.ThermalState) -> Color

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    // FPS
                    Text(String(format: "%.1f FPS", cameraManager.currentFPS))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(6)

                    // 🔥 발열 상태
                    let thermalEmoji = thermalStateEmoji(thermalManager.currentThermalState)
                    let targetFPS = Int(1.0 / thermalManager.recommendedAnalysisInterval)
                    Text("\(thermalEmoji) 목표: \(targetFPS)fps")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(thermalColor(thermalManager.currentThermalState))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(6)

                    // 🔋 배터리/저전력 모드
                    if thermalManager.isLowPowerMode {
                        Text("⚡️ 저전력")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                    }

                    // 레퍼런스 포즈 키포인트
                    if let refPose = realtimeAnalyzer.referenceAnalysis?.poseKeypoints {
                        let visibleCount = refPose.filter { $0.confidence >= 0.5 }.count
                        let color: Color = visibleCount >= 10 ? .green : (visibleCount >= 5 ? .yellow : .red)
                        Text("레퍼런스: \(visibleCount)/\(refPose.count)개")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                    }

                    // 완성도
                    if referenceImage != nil {
                        let score = Int(realtimeAnalyzer.perfectScore * 100)
                        Text("완성도: \(score)%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 200)  // 하단 버튼 위에 표시
            }
        }
    }
}

// MARK: - Refactored View Builders
extension ContentView {
    
    // 권한 없을 때 화면
    var unauthorizedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("카메라 권한이 필요합니다")
                .font(.title3)
                .foregroundColor(.white)

            Text("설정 > TryAngle > 카메라 허용")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // 권한 있을 때 메인 화면
    @ViewBuilder
    func authorizedContent(geometry: GeometryProxy, captureHeight: CGFloat, maskHeight: CGFloat, safeAreaTop: CGFloat) -> some View {
        ZStack {
            // 1. 카메라 프리뷰 & 마스크
            ZStack {
                CameraView(
                    cameraManager: cameraManager,
                    isSessionConfigured: cameraManager.isSessionConfigured,
                    aspectRatio: selectedAspectRatio
                )
                    .ignoresSafeArea()

                AspectRatioMaskView(selectedRatio: selectedAspectRatio)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            
            // 2. 그리드 & 피드백
            mainOverlayLayer(captureHeight: captureHeight, maskHeight: maskHeight)
            
            // 3. 컨트롤 & 상태 표시
            controlsAndStatusLayer(geometry: geometry, safeAreaTop: safeAreaTop)
        }
        .onAppear {
            appLaunchTime = Date()
            isInitializing = true

            cameraManager.setupSession {
                self.cameraManager.startSession()
                
                self.realtimeAnalyzer.setupSubscription(
                    framePublisher: self.cameraManager.frameSubject.eraseToAnyPublisher(),
                    cameraManager: self.cameraManager
                )
                
                print("✅ 카메라 세션 설정 완료 및 시작 (Combine Wired)")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                isInitializing = false
                print("✅ 초기화 완료: UI 완전 활성화")
            }
        }
        .onDisappear {
            // 앱 종료/화면 전환 시 세션 정리 (MainTab으로 갈 때 등)
            cameraManager.stopSession()
            realtimeAnalyzer.pauseAnalysis()
            stopAnalysis()
        }
    }
    
    // 그리드 및 피드백 레이어
    @ViewBuilder
    func mainOverlayLayer(captureHeight: CGFloat, maskHeight: CGFloat) -> some View {
        // Grid
        if showGrid {
            GridOverlay()
                .frame(height: captureHeight)
                .clipped()
                .ignoresSafeArea()
        }
        
        // Feedback Overlay
        VStack(spacing: 0) {
            Spacer().frame(height: maskHeight)
            
            if referenceImage != nil {
                FeedbackOverlay(
                    feedbackItems: realtimeAnalyzer.instantFeedback,
                    categoryStatuses: realtimeAnalyzer.categoryStatuses,
                    completedFeedbacks: realtimeAnalyzer.completedFeedbacks,
                    processingTime: processingTime,
                    gateEvaluation: realtimeAnalyzer.gateEvaluation,
                    unifiedFeedback: realtimeAnalyzer.unifiedFeedback,
                    stabilityProgress: realtimeAnalyzer.stabilityProgress,
                    environmentWarning: realtimeAnalyzer.environmentWarning,
                    currentShotDebugInfo: realtimeAnalyzer.currentShotDebugInfo,
                    activeFeedback: realtimeAnalyzer.activeFeedback,
                    simpleGuide: realtimeAnalyzer.simpleGuide  // 🆕 단순화된 가이드
                )
                .frame(height: captureHeight)
                .clipped()
                .onChange(of: realtimeAnalyzer.instantFeedback) { _, _ in updateCombinedFeedback() }
                .onChange(of: serverFeedbackItems) { _, _ in updateCombinedFeedback() }
            } else {
                Spacer().frame(height: captureHeight)
            }
            
            Spacer().frame(height: maskHeight)
        }
        .allowsHitTesting(false)
    }

    // 컨트롤 및 상태 표시 레이어
    @ViewBuilder
    func controlsAndStatusLayer(geometry: GeometryProxy, safeAreaTop: CGFloat) -> some View {
        let screenHeight = geometry.size.height
        
        // 상단 카메라 옵션
        topCameraOptionsView
        
        // 레퍼런스 안내
        if referenceImage == nil {
            referenceGuideView(safeAreaTop: safeAreaTop, screenHeight: screenHeight)
        }
        
        // 완벽 상태 표시
        if referenceImage != nil && realtimeAnalyzer.isPerfect {
            perfectIndicatorView(safeAreaTop: safeAreaTop, screenHeight: screenHeight)
        }
        
        // 썸네일 (레퍼런스 & 캡처)
        thumbnailsView
        
        // 하단 컨트롤 (셔터 등)
        bottomControlsView
        
        // 에러 메시지
        if let error = errorMessage {
            VStack {
                Text("⚠️ \(error)")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
                    .padding(.top, safeAreaTop + 80)
                Spacer()
            }
        }
        
        // 분석 중 표시
        if isAnalyzing {
            VStack {
                HStack {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("분석 중...").font(.caption).foregroundColor(.white)
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
                .padding(.top, safeAreaTop + 80)
                Spacer()
            }
        }
        
        // 디버그 오버레이
        if showFPS {
            DebugOverlay(
                cameraManager: cameraManager,
                thermalManager: thermalManager,
                realtimeAnalyzer: realtimeAnalyzer,
                referenceImage: referenceImage,
                thermalStateEmoji: thermalStateEmoji,
                thermalColor: thermalColor
            )
        }
    }
    
    // MARK: - Subviews for Controls
    
    var topCameraOptionsView: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                // 🔧 세로 레이아웃: 버튼 위로 옵션들이 펼쳐짐
                VStack(spacing: 10) {
                    if showCameraOptions {
                        // 옵션 버튼들 (위로 쌓임)
                        Button(action: { cameraManager.toggleFlash() }) {
                            Image(systemName: cameraManager.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                                .font(.system(size: 20))
                                .foregroundColor(cameraManager.isFlashOn ? .yellow : .white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .transition(.scale.combined(with: .opacity))

                        Button(action: {
                            let allCases = CameraAspectRatio.allCases
                            if let currentIndex = allCases.firstIndex(of: selectedAspectRatio) {
                                let nextIndex = (currentIndex + 1) % allCases.count
                                selectedAspectRatio = allCases[nextIndex]
                            }
                        }) {
                            Text(selectedAspectRatio.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .transition(.scale.combined(with: .opacity))

                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .transition(.scale.combined(with: .opacity))
                    }

                    // 메인 토글 버튼 (항상 표시)
                    Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showCameraOptions.toggle() } }) {
                        Image(systemName: showCameraOptions ? "xmark" : "ellipsis")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.5))
                            .clipShape(Circle())
                            .rotationEffect(.degrees(showCameraOptions ? 90 : 0))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 210)
        }
    }
    
    func referenceGuideView(safeAreaTop: CGFloat, screenHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: safeAreaTop + screenHeight * 0.15)
            Text("레퍼런스 이미지를 선택하세요")
                .font(.caption).fontWeight(.medium).foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.blue.opacity(0.7)).cornerRadius(8)
            Text("하단 '레퍼런스' 탭에서\n따라 찍고 싶은 사진을 선택하세요")
                .font(.caption2).foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center).padding(.top, 6)
            Spacer()
        }
    }
    
    func perfectIndicatorView(safeAreaTop: CGFloat, screenHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: safeAreaTop + screenHeight * 0.25)
            HStack {
                Spacer()
                VStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Color.green.opacity(0.9)).frame(width: 100, height: 100)
                            .overlay(Circle().stroke(Color.white, lineWidth: 4))
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark").font(.system(size: 40, weight: .bold)).foregroundColor(.white)
                            Text("완벽!").font(.headline).foregroundColor(.white)
                        }
                    }
                    if autoCapture {
                        Text("자동 촬영!").font(.caption).foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color.green.opacity(0.8)).cornerRadius(20)
                    }
                }
                Spacer()
            }
            Spacer()
        }
    }
    
    var thumbnailsView: some View {
        ZStack(alignment: .bottomLeading) {
            if let refImage = referenceImage {
                VStack {
                    Spacer()
                    HStack {
                        Image(uiImage: refImage)
                            .resizable().scaledToFill()
                            .frame(width: 70, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white, lineWidth: 2))
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                            .padding(.leading, 20).padding(.bottom, 70)
                            .onTapGesture {
                                showReferenceFullScreen = true
                            }
                        Spacer()
                    }
                }
            }
            
            if let captured = capturedImage {
                VStack {
                    Spacer()
                    HStack {
                        Button(action: { analyzeAndShowFeedback(image: captured) }) {
                            ZStack {
                                Image(uiImage: captured)
                                    .resizable().scaledToFill()
                                    .frame(width: 70, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.green, lineWidth: 3))
                                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                                if isAnalyzingPhoto {
                                    RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.5)).frame(width: 70, height: 70)
                                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                }
                            }
                        }
                        .padding(.leading, 20).padding(.bottom, 150)
                        Spacer()
                    }
                }
            }
        }
    }
    
    var bottomControlsView: some View {
        VStack {
            Spacer()
            LensSelector(cameraManager: cameraManager)
            ZStack {
                Button(action: { performCapture() }) {
                    ZStack {
                        Circle().stroke(Color.white, lineWidth: 4).frame(width: 80, height: 80)
                        Circle().fill(Color.white).frame(width: 68, height: 68)
                    }
                }
                HStack {
                    Spacer()
                    Button(action: { cameraManager.switchCamera() }) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 24)).foregroundColor(.white)
                            .frame(width: 50, height: 50).background(.ultraThinMaterial).clipShape(Circle())
                    }
                    .padding(.trailing, 30)
                }
            }
            .frame(maxWidth: .infinity).padding(.bottom, 70)
        }
    }

    }



struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(
            referenceImage: .constant(nil),
            referenceImageData: .constant(nil),
            isActiveTab: true
        )
    }
}

// MARK: - 🆕 레퍼런스 이미지 전체화면 뷰
struct ReferenceImageFullScreenView: View {
    let image: UIImage
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // 배경
            Color.black.ignoresSafeArea()

            // 이미지
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .ignoresSafeArea()

            // 닫기 버튼
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.5), radius: 4)
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 60)
                }
                Spacer()
            }

            // 하단 안내 텍스트
            VStack {
                Spacer()
                Text("레퍼런스 이미지")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 50)
            }
        }
        .onTapGesture {
            onDismiss()
        }
    }
}
