import SwiftUI

@main
struct TryAngleApp: App {
    init() {
        // 🔧 로깅 시스템 설정
        configureLogging()
        
        AppLogger.shared.info("+ start init system manager", category: "App")
        
        // 📊 시스템 모니터링 시작 (10초 간격)
        SystemMonitor.shared.startPeriodicMonitoring(interval: 10.0)

        // 🔥 AI 모델 백그라운드 초기화 (메인 스레드 블로킹 방지)
        initializeMLModelsInBackground()
        
        AppLogger.shared.info("- end init system manager", category: "App")
    }
    
    /// 로깅 시스템 초기 설정
    private func configureLogging() {
        #if DEBUG
        // Debug 빌드: 모든 로그 활성화, 콘솔 출력
        AppLogger.shared.isEnabled = true
        AppLogger.shared.logToConsole = true
        AppLogger.shared.minLevel = .debug
        #else
        // Release 빌드: Warning 이상만 로깅, 콘솔 출력 비활성화
        AppLogger.shared.isEnabled = true
        AppLogger.shared.logToConsole = false
        AppLogger.shared.minLevel = .warning
        #endif
    }

    /// 🔥 AI 모델들을 백그라운드에서 미리 로드
    private func initializeMLModelsInBackground() {
        // RTMPose (YOLO11n + ONNX) 백그라운드 로드
        RTMPoseRunner.initializeInBackground {
            AppLogger.shared.info("     - RTMPoseRunner ready", category: "ML")
        }

        // DepthAnything CoreML 백그라운드 로드
        DepthAnythingCoreML.initializeInBackground {
            AppLogger.shared.info("     - DepthAnythingCoreML ready", category: "ML")
        }
    }

    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            if showSplash {
                SplashView(isActive: $showSplash)
            } else {
                MainTabView()
            }
        }
    }
}


