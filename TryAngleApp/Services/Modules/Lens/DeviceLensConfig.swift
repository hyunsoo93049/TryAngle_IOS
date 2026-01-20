//
//  DeviceLensConfig.swift
//  TryAngleApp
//
//  iPhone 모델별 렌즈 초점거리 하드코딩 설정
//  - 각 모델의 물리 렌즈별 35mm 환산 초점거리 저장
//  - 디지털 줌 시 정확한 초점거리 계산
//
//  Created: 2025-01-20
//

import Foundation

// MARK: - Device Lens Configuration

public struct DeviceLensConfig {

    public static let shared = DeviceLensConfig()

    // MARK: - iPhone 모델별 물리 렌즈 구성
    // Key: 모델 식별자, Value: [displayZoom: focalLengthMM]

    private let lensConfigs: [String: [CGFloat: Int]] = [
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // iPhone 16 Series (2024)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        "iPhone17,1": [0.5: 13, 1.0: 24, 2.0: 48, 5.0: 120],  // 16 Pro
        "iPhone17,2": [0.5: 13, 1.0: 24, 2.0: 48, 5.0: 120],  // 16 Pro Max
        "iPhone17,3": [0.5: 13, 1.0: 26, 2.0: 52],             // 16
        "iPhone17,4": [0.5: 13, 1.0: 26, 2.0: 52],             // 16 Plus

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // iPhone 15 Series (2023)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        "iPhone16,1": [0.5: 13, 1.0: 24, 2.0: 48, 3.0: 77],   // 15 Pro
        "iPhone16,2": [0.5: 13, 1.0: 24, 2.0: 48, 5.0: 120],  // 15 Pro Max
        "iPhone15,4": [0.5: 13, 1.0: 26, 2.0: 52],             // 15
        "iPhone15,5": [0.5: 13, 1.0: 26, 2.0: 52],             // 15 Plus

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // iPhone 14 Series (2022)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        "iPhone15,2": [0.5: 13, 1.0: 24, 2.0: 48, 3.0: 77],   // 14 Pro
        "iPhone15,3": [0.5: 13, 1.0: 24, 2.0: 48, 3.0: 77],   // 14 Pro Max
        "iPhone14,7": [0.5: 13, 1.0: 26],                      // 14
        "iPhone14,8": [0.5: 13, 1.0: 26],                      // 14 Plus

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // iPhone 13 Series (2021)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        "iPhone14,2": [0.5: 13, 1.0: 26, 3.0: 77],            // 13 Pro
        "iPhone14,3": [0.5: 13, 1.0: 26, 3.0: 77],            // 13 Pro Max
        "iPhone14,5": [0.5: 13, 1.0: 26],                      // 13
        "iPhone14,4": [0.5: 13, 1.0: 26],                      // 13 mini

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // iPhone 12 Series (2020)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        "iPhone13,3": [0.5: 13, 1.0: 26, 2.5: 65],            // 12 Pro
        "iPhone13,4": [0.5: 13, 1.0: 26, 2.5: 65],            // 12 Pro Max
        "iPhone13,2": [0.5: 13, 1.0: 26],                      // 12
        "iPhone13,1": [0.5: 13, 1.0: 26],                      // 12 mini

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // iPhone 11 Series (2019)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        "iPhone12,3": [0.5: 13, 1.0: 26, 2.0: 52],            // 11 Pro
        "iPhone12,5": [0.5: 13, 1.0: 26, 2.0: 52],            // 11 Pro Max
        "iPhone12,1": [0.5: 13, 1.0: 26],                      // 11

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // iPhone SE Series
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        "iPhone14,6": [1.0: 26],                               // SE 3rd (2022)
        "iPhone12,8": [1.0: 28],                               // SE 2nd (2020)
    ]

    // MARK: - 기본값 (알 수 없는 모델용)
    private let defaultConfig: [CGFloat: Int] = [0.5: 13, 1.0: 24, 2.0: 48]

    private init() {}

    // MARK: - 현재 기기 모델 식별자

    private var currentModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    // MARK: - 캐시된 현재 기기 설정

    private lazy var currentConfig: [CGFloat: Int] = {
        let model = currentModelIdentifier
        return lensConfigs[model] ?? defaultConfig
    }()

    // MARK: - Public API

    /// 디스플레이 줌 배율에서 35mm 환산 초점거리(mm) 계산
    /// - Parameter displayZoom: 카메라 앱에 표시되는 줌 배율 (0.5, 1.0, 2.0, 3.0, 5.0 등)
    /// - Returns: 35mm 환산 초점거리 (mm)
    public func focalLengthMM(for displayZoom: CGFloat) -> Int {
        let config = lensConfigs[currentModelIdentifier] ?? defaultConfig

        // 1. 정확히 일치하는 물리 렌즈가 있으면 사용
        if let exactMM = config[displayZoom] {
            return exactMM
        }

        // 2. 디지털 줌 계산 (가장 가까운 낮은 물리 렌즈 기준)
        let sortedZooms = config.keys.sorted()
        var baseLensZoom: CGFloat = 1.0
        var baseLensMM: Int = 24

        for zoom in sortedZooms {
            if zoom <= displayZoom {
                baseLensZoom = zoom
                baseLensMM = config[zoom]!
            }
        }

        // 디지털 줌 비율 적용
        let digitalRatio = displayZoom / baseLensZoom
        return Int(round(Float(baseLensMM) * Float(digitalRatio)))
    }

    /// 현재 기기에서 사용 가능한 물리 렌즈 줌 배율 목록
    public var availablePhysicalZooms: [CGFloat] {
        let config = lensConfigs[currentModelIdentifier] ?? defaultConfig
        return config.keys.sorted()
    }

    /// 현재 기기 모델명 (디버그용)
    public var deviceModel: String {
        return currentModelIdentifier
    }

    /// 특정 줌이 물리 렌즈인지 디지털 줌인지 확인
    public func isPhysicalLens(zoom: CGFloat) -> Bool {
        let config = lensConfigs[currentModelIdentifier] ?? defaultConfig
        return config[zoom] != nil
    }
}
