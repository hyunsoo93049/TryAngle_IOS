import SwiftUI
import AVFoundation

struct SettingsSheet: View {
    @Binding var showGrid: Bool
    @Binding var showFPS: Bool
    @Binding var autoCapture: Bool
    @ObservedObject var cameraManager: CameraManager
    @Environment(\.dismiss) var dismiss

    // 로컬 상태 (UI 반응성 최적화: Parent 리렌더링 방지)
    @State private var localShowGrid: Bool = false
    @State private var localShowFPS: Bool = false
    @State private var localAutoCapture: Bool = true

    // 카메라 설정 로컬 상태
    @State private var localBackResolution: Int = 24
    @State private var localFrontResolution: Int = 12
    @State private var localFPS: Int = 30
    @State private var localFrontStabilization: Bool = false
    @State private var localBackStabilization: Bool = true

    // 기기 지원 해상도
    @State private var availableFrontResolutions: [Int] = []
    @State private var availableBackResolutions: [Int] = []

    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle(isOn: $localShowGrid) {
                        HStack {
                            Image(systemName: "grid")
                                .foregroundColor(.blue)
                                .frame(width: 28)
                            Text("그리드 표시")
                        }
                    }

                    Toggle(isOn: $localAutoCapture) {
                        HStack {
                            Image(systemName: "camera.fill")
                                .foregroundColor(.blue)
                                .frame(width: 28)
                            Text("자동 촬영")
                        }
                    }
                } header: {
                    Text("촬영 옵션")
                }

                // MARK: - 카메라 설정 섹션
                Section {
                    // 후면 해상도
                    if !availableBackResolutions.isEmpty {
                        Picker(selection: $localBackResolution) {
                            ForEach(availableBackResolutions, id: \.self) { mp in
                                Text("\(mp)MP").tag(mp)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "camera.aperture")
                                    .foregroundColor(.blue)
                                    .frame(width: 28)
                                Text("후면 해상도")
                            }
                        }
                    }

                    // 전면 해상도
                    if !availableFrontResolutions.isEmpty {
                        Picker(selection: $localFrontResolution) {
                            ForEach(availableFrontResolutions, id: \.self) { mp in
                                Text("\(mp)MP").tag(mp)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "person.crop.circle")
                                    .foregroundColor(.blue)
                                    .frame(width: 28)
                                Text("전면 해상도")
                            }
                        }
                    }

                    // FPS
                    Picker(selection: $localFPS) {
                        Text("30fps").tag(30)
                        Text("60fps").tag(60)
                    } label: {
                        HStack {
                            Image(systemName: "speedometer")
                                .foregroundColor(.blue)
                                .frame(width: 28)
                            Text("프레임레이트")
                        }
                    }

                    // 후면 손떨림 보정
                    Toggle(isOn: $localBackStabilization) {
                        HStack {
                            Image(systemName: "hand.raised.slash")
                                .foregroundColor(.blue)
                                .frame(width: 28)
                            Text("후면 손떨림 보정")
                        }
                    }

                    // 전면 손떨림 보정
                    Toggle(isOn: $localFrontStabilization) {
                        HStack {
                            Image(systemName: "hand.raised.slash")
                                .foregroundColor(.blue)
                                .frame(width: 28)
                            Text("전면 손떨림 보정")
                        }
                    }
                } header: {
                    Text("카메라")
                } footer: {
                    Text("60fps는 발열이 증가할 수 있습니다. 손떨림 보정은 화각이 약간 좁아집니다.")
                }

                Section {
                    Toggle(isOn: $localShowFPS) {
                        HStack {
                            Image(systemName: "gauge.with.dots.needle.33percent")
                                .foregroundColor(.blue)
                                .frame(width: 28)
                            Text("성능 정보 표시")
                        }
                    }
                } header: {
                    Text("디버그")
                }

                Section {
                    HStack {
                        Text("버전")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("정보")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") {
                        // 촬영 옵션 적용
                        showGrid = localShowGrid
                        showFPS = localShowFPS
                        autoCapture = localAutoCapture

                        // 카메라 설정 변경 확인 및 적용
                        let newSettings = CameraFormatSettings(
                            frontResolution: localFrontResolution,
                            backResolution: localBackResolution,
                            fps: localFPS,
                            frontStabilizationEnabled: localFrontStabilization,
                            backStabilizationEnabled: localBackStabilization
                        )

                        if newSettings != cameraManager.cameraSettings {
                            cameraManager.applySettings(newSettings)
                        }

                        dismiss()
                    }
                }
            }
            .onAppear {
                // 초기값 동기화
                localShowGrid = showGrid
                localShowFPS = showFPS
                localAutoCapture = autoCapture

                // 카메라 설정 동기화
                let settings = cameraManager.cameraSettings
                localBackResolution = settings.backResolution
                localFrontResolution = settings.frontResolution
                localFPS = settings.fps
                localFrontStabilization = settings.frontStabilizationEnabled
                localBackStabilization = settings.backStabilizationEnabled

                // 기기 지원 해상도 로드
                availableFrontResolutions = CameraFormatSettings.availableResolutions(for: .front)
                availableBackResolutions = CameraFormatSettings.availableResolutions(for: .back)
            }
        }
    }
}
