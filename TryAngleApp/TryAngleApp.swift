import SwiftUI

@main
struct TryAngleApp: App {
    init() {
        print("🎯🎯🎯 앱 시작! TryAngleApp init() 🎯🎯🎯")
        NSLog("🎯🎯🎯 NSLog: 앱 시작! TryAngleApp init() 🎯🎯🎯")

        // 📊 메모리 모니터링 시작
        logMemory("앱 시작")

        // 🔥 AI 모델 백그라운드 초기화 (메인 스레드 블로킹 방지)
        initializeMLModelsInBackground()

        // 파일로도 로그 저장
        let logMessage = "🎯 앱 시작 시각: \(Date())\n"
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let logFile = documentsPath.appendingPathComponent("app_log.txt")
            try? logMessage.write(to: logFile, atomically: true, encoding: .utf8)
            print("📝 로그 파일 위치: \(logFile.path)")
        }
    }

    /// 🔥 AI 모델들을 백그라운드에서 미리 로드
    private func initializeMLModelsInBackground() {
        // RTMPose (YOLO11n + ONNX) 백그라운드 로드
        RTMPoseRunner.initializeInBackground {
            print("✅ RTMPoseRunner 준비 완료")
        }

        // DepthAnything CoreML 백그라운드 로드
        DepthAnythingCoreML.initializeInBackground {
            print("✅ DepthAnythingCoreML 준비 완료")
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


