# LensDistanceGate 통합 계획서

> CompressionGate(Gate 3)를 LensDistanceGate로 교체하는 상세 설계

---

## 1. 현재 아키텍처 분석

### 1.1 기존 Gate 시스템 흐름

```
┌─────────────────────────────────────────────────────────────────┐
│                      RealtimeAnalyzer                           │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ currentZoomFactor ← CameraManager.virtualZoom            │   │
│  │ focalLengthEstimator.focalLengthFromZoom(currentZoom)    │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              GateSystem.evaluate(...)                     │   │
│  │  - Creates GateContext(analysis, reference, settings)    │   │
│  │  - orchestrator.evaluate(context)                        │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     GateOrchestrator                            │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Gates (priority order):                                  │   │
│  │   0: AspectRatioGate                                     │   │
│  │   1: FramingGate                                         │   │
│  │   2: PositionGate                                        │   │
│  │   3: CompressionGate ◀─── 교체 대상                       │   │
│  │   4: PoseGate                                            │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 현재 데이터 구조

```swift
// GateModule.swift (line 21-31)
public struct GateContext {
    public let analysis: FrameAnalysisResult
    public let reference: ReferenceData?
    public let settings: GateSettings
}

// GateModule.swift (line 34-53)
public struct ReferenceData {
    public let bbox: CGRect?
    public let imageSize: CGSize?
    public let compressionIndex: CGFloat?     // 사용 안 함 (legacy)
    public let aspectRatio: CameraAspectRatio
    public let keypoints: [PoseKeypoint]?
    public let focalLength: FocalLengthInfo?  // ✓ 있음
    public let shotType: ShotTypeGate?
    // ❌ shoulderRatio 없음 → 추가 필요
}

// GateModule.swift (line 56-66)
public struct GateSettings {
    public let thresholds: GateThresholds
    public let difficultyMultiplier: CGFloat
    public let targetZoomFactor: CGFloat?
    // ❌ bodyType 없음 → 추가 필요
    // ❌ currentZoomFactor 없음 → 추가 필요
}
```

### 1.3 현재 CompressionGate 동작

```swift
// CompressionGate.swift - 기존 로직 요약
public func evaluate(context: GateContext) -> GateResult {
    // 1. FocalLengthInfo 비교 (current vs reference)
    // 2. BodyStructure.spanY로 거리 힌트 (가까이/멀리)
    // 3. 줌인/줌아웃 피드백 생성
}
```

**문제점:**
- 실제 물리적 거리 계산 없음
- 단순 focalLength mm 비교만
- BodyStructure.spanY는 Y축 기반 (노이즈에 취약)

---

## 2. 신규 아키텍처 설계

### 2.1 새로운 데이터 흐름

```
┌─────────────────────────────────────────────────────────────────┐
│                      RealtimeAnalyzer                           │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ currentZoomFactor ← CameraManager.virtualZoom            │   │
│  │                                                           │   │
│  │ 🆕 DeviceLensConfig.shared.focalLength(for: zoom)        │   │
│  │ 🆕 KeypointSmoother.smooth(keypoints)                    │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              GateSystem.evaluate(...)                     │   │
│  │  - Creates GateContext (🆕 with currentZoomFactor)       │   │
│  │  - orchestrator.evaluate(context)                        │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     GateOrchestrator                            │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Gates:                                                    │   │
│  │   0: AspectRatioGate                                     │   │
│  │   1: FramingGate                                         │   │
│  │   2: PositionGate                                        │   │
│  │   3: 🆕 LensDistanceGate                                 │   │
│  │       ├── DistanceEstimator (물리 거리 계산)              │   │
│  │       ├── GuidanceDebouncer (피드백 안정화)              │   │
│  │       └── DeviceLensConfig (렌즈 정보)                   │   │
│  │   4: PoseGate                                            │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 수정할 기존 파일

| 파일 | 위치 | 수정 내용 |
|------|------|----------|
| `GateModule.swift` | Services/Gates/Core/ | ReferenceData에 `shoulderRatio` 추가, GateSettings에 `bodyType`, `currentZoomFactor` 추가 |
| `GateSystem.swift` | Services/Gates/Core/ | CompressionGate → LensDistanceGate 교체, GateContext 생성 시 currentZoomFactor 전달 |
| `FocalLengthEstimator.swift` | Services/Modules/Lens/ | **필수 수정**: `focalLengthFromZoom()` 내부에서 `DeviceLensConfig` 호출하도록 변경 (충돌 방지) |

### 2.3 신규 생성 파일

| 파일 | 위치 | 역할 |
|------|------|------|
| `LensDistanceGate.swift` | Services/Gates/Modules/ | Gate 3 교체 (핵심) |
| `DistanceEstimator.swift` | Services/Modules/Lens/ | 핀홀 카메라 모델 기반 거리 계산 |
| `DeviceLensConfig.swift` | Services/Modules/Lens/ | iPhone 모델별 렌즈 스펙 하드코딩 |
| `KeypointSmoother.swift` | Services/Modules/Pose/ | EMA 기반 키포인트 스무딩 |
| `GuidanceDebouncer.swift` | Services/Utils/ | 가이드 메시지 디바운싱 |
| `BodyType.swift` | Services/Models/ | 체형별 어깨너비 enum |

---

## 2.4 충돌 방지 필수 조치

### 2.4.1 FocalLengthEstimator 수정 (충돌 방지)

```swift
// FocalLengthEstimator.swift - focalLengthFromZoom() 수정
func focalLengthFromZoom(_ zoomFactor: CGFloat) -> FocalLengthInfo {
    // ❌ 기존: let focalLength = Int(round(CGFloat(Self.iPhoneBaseFocalLength) * zoomFactor))
    // ✅ 변경: DeviceLensConfig에 위임
    let focalLength = DeviceLensConfig.shared.focalLengthMM(for: zoomFactor)

    return FocalLengthInfo(
        focalLength35mm: focalLength,
        source: .zoomFactor,
        confidence: 1.0
    )
}
```

**이유**: RealtimeAnalyzer와 LensDistanceGate가 다른 값을 사용하면 가이드가 꼬임

### 2.4.2 실제 PoseKeypoint 구조 (중요!)

```swift
// Feedback.swift - 실제 구조
public struct PoseKeypoint {
    public let location: CGPoint  // ⚠️ 'point' 아님!
    public let confidence: Float
    // ❌ name 필드 없음
    // ❌ index 필드 없음
}

// 키포인트는 배열 인덱스로 접근
// Index 5 = 왼쪽 어깨
// Index 6 = 오른쪽 어깨
```

### 2.4.3 GateSettings/ReferenceData 기본값

```swift
// 기본값 제공으로 기존 호출 호환성 유지
public init(
    ...,
    currentZoomFactor: CGFloat = 1.0,     // 기본값
    bodyType: BodyType = .medium          // 기본값
)

public init(
    ...,
    shoulderRatio: CGFloat? = nil,        // Optional
    estimatedDistance: Float? = nil       // Optional
)
```

---

## 3. 상세 구현 명세

### 3.0 FocalLengthEstimator.swift 수정 (선행 필수!)

```swift
// Services/Modules/Lens/FocalLengthEstimator.swift
// Line 106~ focalLengthFromZoom() 함수 수정

func focalLengthFromZoom(_ zoomFactor: CGFloat) -> FocalLengthInfo {
    // ❌ 삭제: let focalLength = Int(round(CGFloat(Self.iPhoneBaseFocalLength) * zoomFactor))

    // ✅ 추가: DeviceLensConfig에 위임 (기기별 정확한 값 사용)
    let focalLength = DeviceLensConfig.shared.focalLengthMM(for: zoomFactor)

    return FocalLengthInfo(
        focalLength35mm: focalLength,
        source: .zoomFactor,
        confidence: 1.0
    )
}
```

**주의**: DeviceLensConfig.swift를 먼저 생성해야 이 수정이 컴파일됨!
→ 실제 순서: DeviceLensConfig 생성 → FocalLengthEstimator 수정

---

### 3.1 GateModule.swift 수정

```swift
// 🔧 ReferenceData 수정 (line 34~)
public struct ReferenceData {
    public let bbox: CGRect?
    public let imageSize: CGSize?
    public let compressionIndex: CGFloat?     // legacy, 유지
    public let aspectRatio: CameraAspectRatio
    public let keypoints: [PoseKeypoint]?
    public let focalLength: FocalLengthInfo?
    public let shotType: ShotTypeGate?

    // 🆕 추가
    public let shoulderRatio: CGFloat?        // 어깨픽셀비율 (normalized 0~1)
    public let estimatedDistance: Float?      // 추정 거리 (meters)
}

// 🔧 GateSettings 수정 (line 56~)
public struct GateSettings {
    public let thresholds: GateThresholds
    public let difficultyMultiplier: CGFloat
    public let targetZoomFactor: CGFloat?

    // 🆕 추가
    public let currentZoomFactor: CGFloat     // 현재 줌 배율
    public let bodyType: BodyType             // 체형 설정
}
```

### 3.2 GateSystem.swift 수정

```swift
// 🔧 Gate 등록 변경 (line 62)
init() {
    self.orchestrator = GateOrchestrator()

    orchestrator.register(gate: AspectRatioGate())
    orchestrator.register(gate: FramingGate())
    orchestrator.register(gate: PositionGate())
    orchestrator.register(gate: LensDistanceGate())  // 🆕 교체
    orchestrator.register(gate: PoseGate())
}

// 🔧 GateSettings 생성 변경 (line 145~)
let settings = GateSettings(
    thresholds: currentThresholds,
    difficultyMultiplier: 1.0,
    targetZoomFactor: targetZoomFactor,
    currentZoomFactor: currentZoomFactor,     // 🆕 추가
    bodyType: .medium                          // 🆕 추가 (or user setting)
)
```

### 3.3 BodyType.swift (신규)

```swift
public enum BodyType: String, CaseIterable {
    case small   // 마른 체형
    case medium  // 보통 체형
    case large   // 큰 체형

    /// 어깨너비 (미터)
    var shoulderWidthM: Float {
        switch self {
        case .small:  return 0.34
        case .medium: return 0.40
        case .large:  return 0.46
        }
    }

    var displayName: String {
        switch self {
        case .small:  return "마른 체형"
        case .medium: return "보통 체형"
        case .large:  return "큰 체형"
        }
    }
}
```

### 3.4 DeviceLensConfig.swift (신규)

```swift
public struct DeviceLensConfig {
    public static let shared = DeviceLensConfig()

    /// iPhone 모델별 물리 렌즈 구성 [displayZoom: physicalMM]
    private let lensConfigs: [String: [CGFloat: Int]] = [
        // iPhone 15 Pro / 15 Pro Max
        "iPhone16,1": [0.5: 13, 1.0: 24, 2.0: 48, 3.0: 77],  // 15 Pro
        "iPhone16,2": [0.5: 13, 1.0: 24, 2.0: 48, 5.0: 120], // 15 Pro Max

        // iPhone 14 Pro / 14 Pro Max
        "iPhone15,2": [0.5: 13, 1.0: 24, 2.0: 48, 3.0: 77],
        "iPhone15,3": [0.5: 13, 1.0: 24, 2.0: 48, 3.0: 77],

        // iPhone 13/14 (듀얼 렌즈)
        "iPhone14,2": [0.5: 13, 1.0: 26],  // 13 Pro
        "iPhone14,3": [0.5: 13, 1.0: 26, 3.0: 77],  // 13 Pro Max

        // 기본값 (알 수 없는 모델)
        "default": [0.5: 13, 1.0: 24, 2.0: 48]
    ]

    /// 현재 기기의 모델 식별자
    private var currentModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return String(bytes: Data(bytes: &systemInfo.machine,
                                   count: Int(_SYS_NAMELEN)),
                      encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters) ?? "default"
    }

    /// 디스플레이 줌에서 실제 초점거리(mm) 계산
    public func focalLengthMM(for displayZoom: CGFloat) -> Int {
        let config = lensConfigs[currentModel] ?? lensConfigs["default"]!

        // 정확히 일치하는 물리 렌즈가 있으면 사용
        if let exactMM = config[displayZoom] {
            return exactMM
        }

        // 디지털 줌 계산 (가장 가까운 물리 렌즈 기준)
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
        return Int(Float(baseLensMM) * Float(digitalRatio))
    }
}
```

### 3.5 DistanceEstimator.swift (신규)

```swift
public struct DistanceEstimator {

    /// 35mm 필름 기준 센서 너비 (4:3 비율 보정)
    private static let sensorReferenceWidthMM: Float = 34.6

    /// 핀홀 카메라 모델로 거리 추정
    /// - Parameters:
    ///   - shoulderPixelWidth: 어깨 픽셀 너비 (abs)
    ///   - imageWidth: 이미지 전체 너비 (pixels)
    ///   - focalLengthMM: 35mm 환산 초점거리 (mm)
    ///   - shoulderWidthM: 실제 어깨 너비 (meters)
    /// - Returns: 추정 거리 (meters)
    public static func estimateDistance(
        shoulderPixelWidth: CGFloat,
        imageWidth: CGFloat,
        focalLengthMM: Int,
        shoulderWidthM: Float
    ) -> Float {
        guard shoulderPixelWidth > 0, imageWidth > 0, focalLengthMM > 0 else {
            return 0
        }

        // 어깨가 센서에서 차지하는 비율
        let shoulderRatioOnSensor = Float(shoulderPixelWidth / imageWidth)

        // 센서 위 어깨 크기 (mm)
        let shoulderOnSensorMM = shoulderRatioOnSensor * sensorReferenceWidthMM

        // 핀홀 공식: distance = (H × f) / h
        // H = 실제 어깨 너비 (m → mm)
        // f = 초점거리 (mm)
        // h = 센서 위 어깨 크기 (mm)
        let distance = (shoulderWidthM * 1000 * Float(focalLengthMM)) / (shoulderOnSensorMM * 1000)

        // 단위 정리: (mm × mm) / mm = mm → m로 변환 필요 없음 (이미 m 단위)
        // 실제: (m × mm) / mm = m ✓

        return distance
    }

    /// 키포인트 배열에서 어깨 너비 추출 (인덱스 기반, X축만 사용)
    /// - Parameter keypoints: PoseKeypoint 배열 (index 5 = 왼쪽어깨, index 6 = 오른쪽어깨)
    /// - Returns: 어깨 픽셀 너비 (nil if not detected)
    public static func extractShoulderWidth(from keypoints: [PoseKeypoint]) -> CGFloat? {
        // 어깨 인덱스: 5 = 왼쪽, 6 = 오른쪽
        guard keypoints.count > 6 else { return nil }

        let leftShoulder = keypoints[5]
        let rightShoulder = keypoints[6]

        // 신뢰도 체크
        guard leftShoulder.confidence > 0.3,
              rightShoulder.confidence > 0.3 else {
            return nil
        }

        // X축만 사용하여 노이즈 감소 (Y축 기울기 무시)
        // ⚠️ location 사용 (point 아님!)
        return abs(leftShoulder.location.x - rightShoulder.location.x)
    }
}
```

### 3.6 KeypointSmoother.swift (신규)

```swift
public class KeypointSmoother {

    /// EMA 스무딩 계수 (0.3 = 새 값 30%, 이전 값 70%)
    private let alpha: CGFloat = 0.3

    /// 이전 프레임 키포인트 (배열 인덱스 기반)
    private var previousLocations: [CGPoint] = []

    public init() {}

    /// 키포인트 스무딩 적용
    /// - Parameter keypoints: PoseKeypoint 배열 (인덱스 = 신체 부위)
    /// - Returns: 스무딩된 PoseKeypoint 배열
    public func smooth(_ keypoints: [PoseKeypoint]) -> [PoseKeypoint] {
        // 첫 프레임이면 이전 값 초기화
        if previousLocations.isEmpty {
            previousLocations = keypoints.map { $0.location }
            return keypoints
        }

        // 크기 불일치 시 리셋
        if previousLocations.count != keypoints.count {
            previousLocations = keypoints.map { $0.location }
            return keypoints
        }

        var smoothed: [PoseKeypoint] = []

        for (index, kp) in keypoints.enumerated() {
            let prev = previousLocations[index]
            let newLoc = kp.location

            // EMA: smoothed = prev * (1-α) + new * α
            let smoothedLocation = CGPoint(
                x: prev.x * (1 - alpha) + newLoc.x * alpha,
                y: prev.y * (1 - alpha) + newLoc.y * alpha
            )

            previousLocations[index] = smoothedLocation

            smoothed.append(PoseKeypoint(
                location: smoothedLocation,
                confidence: kp.confidence
            ))
        }

        return smoothed
    }

    /// 스무더 리셋 (새 레퍼런스 시)
    public func reset() {
        previousLocations.removeAll()
    }
}
```

### 3.7 GuidanceDebouncer.swift (신규)

```swift
public class GuidanceDebouncer {

    /// 최소 피드백 간격 (초)
    private let minInterval: TimeInterval = 0.5

    /// 변화 임계값 (25%)
    private let changeThreshold: Float = 0.25

    /// 마지막 피드백 시간
    private var lastFeedbackTime: Date = .distantPast

    /// 마지막 피드백 값
    private var lastDistance: Float = 0
    private var lastFocalLength: Int = 0
    private var lastFeedback: String = ""

    public init() {}

    /// 피드백 디바운싱
    /// - Returns: 출력할 피드백 (변화 없으면 이전 피드백, 시간 안됐으면 nil)
    public func debounce(
        distance: Float,
        focalLength: Int,
        newFeedback: String
    ) -> String? {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFeedbackTime)

        // 시간 조건 체크
        guard elapsed >= minInterval else {
            return nil  // 너무 빠름 - 무시
        }

        // 변화량 체크
        let distanceChange = abs(distance - lastDistance) / max(lastDistance, 0.1)
        let focalChange = abs(focalLength - lastFocalLength)

        let isSignificantChange = distanceChange > changeThreshold || focalChange > 5

        if isSignificantChange {
            // 의미있는 변화 → 새 피드백
            lastFeedbackTime = now
            lastDistance = distance
            lastFocalLength = focalLength
            lastFeedback = newFeedback
            return newFeedback
        } else {
            // 변화 없음 → 이전 피드백 유지
            return lastFeedback
        }
    }

    /// 리셋 (새 레퍼런스 시)
    public func reset() {
        lastFeedbackTime = .distantPast
        lastDistance = 0
        lastFocalLength = 0
        lastFeedback = ""
    }
}
```

### 3.8 LensDistanceGate.swift (신규 - 핵심)

```swift
import Foundation
import CoreGraphics

public class LensDistanceGate: GateModule {
    public let name = "렌즈/거리"
    public let priority = 3

    // Config
    private let threshold: CGFloat = 0.70
    private let distanceTolerance: Float = 0.3     // 30cm 허용 오차
    private let focalLengthTolerance: Int = 10     // 10mm 허용 오차

    // Components
    private let guidanceDebouncer = GuidanceDebouncer()

    public init() {}

    public func evaluate(context: GateContext) -> GateResult {
        let analysis = context.analysis
        let reference = context.reference
        let settings = context.settings

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // 1. 현재 상태 추출
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        let currentKeypoints = analysis.poseResult?.asPoseKeypoints ?? []
        let imageWidth = analysis.input.imageSize.width

        // 현재 초점거리 계산 (DeviceLensConfig 사용)
        let currentZoom = settings.currentZoomFactor
        let currentFocalMM = DeviceLensConfig.shared.focalLengthMM(for: currentZoom)

        // 현재 어깨 너비 추출 (인덱스 기반: 5=왼쪽어깨, 6=오른쪽어깨)
        guard let shoulderPixelWidth = DistanceEstimator.extractShoulderWidth(
            from: currentKeypoints
        ) else {
            return createMissingResult("어깨 감지 대기 중...")
        }

        // 현재 거리 추정
        let bodyType = settings.bodyType
        let currentDistance = DistanceEstimator.estimateDistance(
            shoulderPixelWidth: shoulderPixelWidth,
            imageWidth: imageWidth,
            focalLengthMM: currentFocalMM,
            shoulderWidthM: bodyType.shoulderWidthM
        )

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // 2. 레퍼런스 확인
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        guard let ref = reference,
              let refFocal = ref.focalLength else {
            return createSkippedResult(currentFocalMM, currentDistance)
        }

        let refFocalMM = refFocal.focalLength35mm
        let refDistance = ref.estimatedDistance ?? 2.0  // 기본 2m

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // 3. 비교 및 가이드 생성
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        let focalDiff = currentFocalMM - refFocalMM
        let distanceDiff = currentDistance - refDistance

        var score: CGFloat = 1.0
        var feedback = ""
        var category = "lens_distance"

        let needsZoomChange = abs(focalDiff) > focalLengthTolerance
        let needsDistanceChange = abs(distanceDiff) > distanceTolerance

        if needsZoomChange && needsDistanceChange {
            // 케이스 A: 줌 + 거리 모두 조정 필요
            score = 0.3
            feedback = generateCombinedGuidance(
                focalDiff: focalDiff,
                distanceDiff: distanceDiff,
                targetFocal: refFocalMM,
                targetDistance: refDistance
            )
            category = "lens_distance_both"

        } else if needsZoomChange {
            // 케이스 B: 줌만 조정 필요
            score = 0.5
            feedback = generateZoomGuidance(
                focalDiff: focalDiff,
                currentFocal: currentFocalMM,
                targetFocal: refFocalMM
            )
            category = "lens_only"

        } else if needsDistanceChange {
            // 케이스 C: 거리만 조정 필요
            score = 0.6
            feedback = generateDistanceGuidance(
                distanceDiff: distanceDiff,
                currentDistance: currentDistance,
                targetDistance: refDistance
            )
            category = "distance_only"

        } else {
            // 케이스 D: 완벽
            score = 1.0
            feedback = "✓ 렌즈/거리 완벽 (\(currentFocalMM)mm, \(String(format: "%.1f", currentDistance))m)"
            category = "lens_distance_perfect"
        }

        // 디바운싱 적용
        if let debouncedFeedback = guidanceDebouncer.debounce(
            distance: currentDistance,
            focalLength: currentFocalMM,
            newFeedback: feedback
        ) {
            feedback = debouncedFeedback
        }

        return GateResult(
            name: name,
            score: score,
            threshold: threshold,
            feedback: feedback,
            icon: "📐",
            category: category,
            debugInfo: "Focal:\(currentFocalMM)mm→\(refFocalMM)mm, Dist:\(String(format: "%.1f", currentDistance))m→\(String(format: "%.1f", refDistance))m"
        )
    }

    // MARK: - Guidance Generators

    private func generateCombinedGuidance(
        focalDiff: Int,
        distanceDiff: Float,
        targetFocal: Int,
        targetDistance: Float
    ) -> String {
        let targetZoom = CGFloat(targetFocal) / 24.0
        let zoomText = String(format: "%.1fx", targetZoom)

        if focalDiff < 0 && distanceDiff < 0 {
            // 줌인 + 뒤로
            let steps = Int(abs(distanceDiff) * 2)
            return "\(steps)걸음 뒤로 물러나서 \(zoomText)로 줌인"
        } else if focalDiff < 0 && distanceDiff > 0 {
            // 줌인 + 앞으로 (드문 케이스)
            return "\(zoomText)로 줌인하세요"
        } else if focalDiff > 0 && distanceDiff > 0 {
            // 줌아웃 + 앞으로
            let steps = Int(abs(distanceDiff) * 2)
            return "\(steps)걸음 앞으로 다가가서 \(zoomText)로 줌아웃"
        } else {
            // 줌아웃 + 뒤로 (드문 케이스)
            return "\(zoomText)로 줌아웃하세요"
        }
    }

    private func generateZoomGuidance(
        focalDiff: Int,
        currentFocal: Int,
        targetFocal: Int
    ) -> String {
        let targetZoom = CGFloat(targetFocal) / 24.0
        let zoomText = String(format: "%.1fx", targetZoom)

        if focalDiff < 0 {
            return "\(zoomText)로 줌인 (\(currentFocal)mm → \(targetFocal)mm)"
        } else {
            return "\(zoomText)로 줌아웃 (\(currentFocal)mm → \(targetFocal)mm)"
        }
    }

    private func generateDistanceGuidance(
        distanceDiff: Float,
        currentDistance: Float,
        targetDistance: Float
    ) -> String {
        let steps = max(1, Int(abs(distanceDiff) * 2))

        if distanceDiff < 0 {
            // 현재가 더 가까움 → 뒤로
            return "\(steps)걸음 뒤로 (\(String(format: "%.1f", currentDistance))m → \(String(format: "%.1f", targetDistance))m)"
        } else {
            // 현재가 더 멀음 → 앞으로
            return "\(steps)걸음 앞으로 (\(String(format: "%.1f", currentDistance))m → \(String(format: "%.1f", targetDistance))m)"
        }
    }

    // MARK: - Helper Results

    private func createMissingResult(_ message: String) -> GateResult {
        return GateResult(
            name: name,
            score: 0.0,
            threshold: threshold,
            feedback: message,
            icon: "📐",
            category: "lens_distance_missing"
        )
    }

    private func createSkippedResult(_ currentFocal: Int, _ currentDistance: Float) -> GateResult {
        return GateResult(
            name: name,
            score: 1.0,
            threshold: threshold,
            feedback: "레퍼런스 없음 (현재: \(currentFocal)mm, \(String(format: "%.1f", currentDistance))m)",
            icon: "📐",
            category: "lens_distance_skipped"
        )
    }
}
```

---

## 4. 구현 순서 (의존성 기준)

```
Phase 0: 기존 파일 수정 (선행 필수)
└── 0.1 FocalLengthEstimator.swift 수정 (focalLengthFromZoom → DeviceLensConfig 위임)

Phase 1: 기반 모듈 (Phase 0 완료 필요)
├── 1.1 BodyType.swift
├── 1.2 DeviceLensConfig.swift
└── 1.3 DistanceEstimator.swift

Phase 2: 안정화 모듈 (의존성 없음)
├── 2.1 KeypointSmoother.swift
└── 2.2 GuidanceDebouncer.swift

Phase 3: 데이터 구조 수정 (Phase 1 완료 필요)
├── 3.1 GateModule.swift 수정 (ReferenceData, GateSettings)
└── 3.2 GateSystem.swift 수정 (Settings 생성 부분만)

Phase 4: 핵심 게이트 (Phase 1~3 완료 필요)
└── 4.1 LensDistanceGate.swift

Phase 5: 연결 및 테스트
├── 5.1 GateSystem.swift에서 CompressionGate → LensDistanceGate 교체
├── 5.2 RealtimeAnalyzer에서 KeypointSmoother 적용
└── 5.3 통합 테스트
```

---

## 5. 파일 위치 정리

```
TryAngleApp/Services/
├── Gates/
│   ├── Core/
│   │   ├── GateModule.swift      ← 수정
│   │   ├── GateSystem.swift      ← 수정
│   │   └── GateOrchestrator.swift
│   └── Modules/
│       ├── CompressionGate.swift ← 삭제 or 보관
│       └── LensDistanceGate.swift ← 신규
├── Modules/
│   ├── Lens/
│   │   ├── FocalLengthEstimator.swift
│   │   ├── DeviceLensConfig.swift ← 신규
│   │   └── DistanceEstimator.swift ← 신규
│   └── Pose/
│       └── KeypointSmoother.swift ← 신규
├── Utils/
│   └── GuidanceDebouncer.swift ← 신규
└── Models/
    └── BodyType.swift ← 신규
```

---

## 6. 마이그레이션 체크리스트

### 6.1 구현 전 확인
- [ ] 개발_초점계산_로직설계.md 최종 확인
- [x] PoseKeypoint 구조체 확인 완료 → `location`, `confidence` 필드만 존재, 인덱스 기반 접근 필요 (5=왼쪽어깨, 6=오른쪽어깨)
- [ ] 기존 CompressionGate 백업

### 6.2 Phase 1 체크
- [ ] BodyType.swift 컴파일 확인
- [ ] DeviceLensConfig.shared.focalLengthMM(for: 1.0) == 24 확인
- [ ] DistanceEstimator 단위 테스트 (2m에서 어깨 40cm → ~0.4m 픽셀비율?)

### 6.3 Phase 2 체크
- [ ] KeypointSmoother 스무딩 동작 확인
- [ ] GuidanceDebouncer 0.5초 디바운싱 확인

### 6.4 Phase 3 체크
- [ ] GateModule.swift 컴파일 오류 없음
- [ ] 기존 ReferenceData 사용처 호환성 확인
- [ ] GateSettings init 호출부 업데이트

### 6.5 Phase 4 체크
- [ ] LensDistanceGate.evaluate() 정상 작동
- [ ] GateResult 피드백 메시지 자연스러움

### 6.6 Phase 5 체크
- [ ] CompressionGate → LensDistanceGate 교체 완료
- [ ] 앱 실행 시 Gate 3 정상 작동
- [ ] 실제 촬영 테스트 (거리 추정 정확도)

---

## 7. 롤백 계획

만약 새 구현에 문제가 있을 경우:

1. `GateSystem.swift`에서 `LensDistanceGate()` → `CompressionGate()`로 복원
2. `GateModule.swift` 수정 사항 revert (shoulderRatio, bodyType 제거)
3. 신규 파일들은 삭제하지 않고 유지 (추후 디버깅용)

```swift
// 롤백 시 GateSystem.swift
orchestrator.register(gate: CompressionGate())  // 원복
```

---

*작성일: 2025-01-20*
*상태: 설계 완료 - 구현 대기*
