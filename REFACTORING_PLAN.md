# TryAngle iOS 하이브리드 구조 리팩토링 계획서

**작성일:** 2026-01-27
**목표:** Services 폴더를 하이브리드 레이어 구조로 재구성 + AdaptivePoseComparator 연결

---

## 목차
1. [현재 구조 vs 목표 구조](#1-현재-구조-vs-목표-구조)
2. [위험 포인트 (절대 주의)](#2-위험-포인트-절대-주의)
3. [Phase 1: 폴더 구조 생성](#phase-1-폴더-구조-생성)
4. [Phase 2: Core 타입 정리](#phase-2-core-타입-정리)
5. [Phase 3: Inference 레이어 구성](#phase-3-inference-레이어-구성)
6. [Phase 4: Domain 레이어 구성](#phase-4-domain-레이어-구성)
7. [Phase 5: Evaluation 레이어 구성](#phase-5-evaluation-레이어-구성)
8. [Phase 6: Pipeline 레이어 구성](#phase-6-pipeline-레이어-구성)
9. [Phase 7: AdaptivePoseComparator 분리](#phase-7-adaptiveposecomparator-분리)
10. [Phase 8: 파이프라인 연결](#phase-8-파이프라인-연결)
11. [Phase 9: import 수정](#phase-9-import-수정)
12. [Phase 10: 빌드 & 검증](#phase-10-빌드--검증)
13. [롤백 계획](#롤백-계획)

---

## 1. 현재 구조 vs 목표 구조

### 현재 구조
```
Services/
├── Analysis/           ← 역할 기준 (혼재)
├── APIService.swift
├── CameraManager.swift
├── Comparison/         ← 역할 기준
├── Core/               ← 일부 정리됨
├── Feedback/           ← 역할 기준
├── Gates/              ← 역할 기준
├── Legacy/
├── Models/             ← 공유 타입
├── Modules/            ← 도메인 기준 (혼재)
├── Pipeline/
├── Reference/
├── RuleEngine/
└── Utils/
```

### 목표 구조
```
Services/
├── Core/                    ← [레이어 0] 공유 타입 (변경 최소화)
│   ├── Types/
│   │   ├── Feedback.swift           (기존 Models/Feedback.swift)
│   │   ├── PipelineTypes.swift      (기존)
│   │   ├── DetectionInterfaces.swift (기존)
│   │   ├── GateTypes.swift          (기존 Gates/Core/)
│   │   └── GuideModels.swift        (기존 Feedback/Models/)
│   ├── State/                       (기존 유지)
│   ├── Cache/                       (기존 유지)
│   ├── Optimization/                (기존 유지)
│   └── Utils/                       (기존 Utils/ 이동)
│
├── Inference/               ← [레이어 1] AI 모델 실행
│   ├── RTMPoseRunner.swift
│   ├── DepthAnythingRunner.swift    (기존 DepthAnythingCoreML.swift)
│   ├── VisionAnalyzer.swift
│   └── PersonDetector.swift         (기존 Legacy/)
│
├── Domain/                  ← [레이어 2] 도메인별 처리
│   ├── Pose/
│   │   ├── PoseTypes.swift          (AdaptivePoseComparator에서 분리)
│   │   ├── PoseComparator.swift     (AdaptivePoseComparator에서 분리)
│   │   ├── PoseFeedbackGenerator.swift (분리)
│   │   ├── RTMPoseService.swift     (기존 Modules/Pose/)
│   │   └── KeypointSmoother.swift   (기존 Modules/Pose/)
│   ├── Framing/
│   │   ├── PhotographyFramingAnalyzer.swift
│   │   └── FramingAnalyzer.swift
│   ├── Composition/
│   │   ├── MarginAnalyzer.swift
│   │   ├── OnDeviceCompositionAnalyzer.swift
│   │   ├── CompositionAnalyzer.swift
│   │   └── AestheticService.swift
│   ├── Depth/
│   │   └── DepthService.swift
│   ├── Lens/
│   │   ├── FocalLengthEstimator.swift
│   │   ├── DistanceEstimator.swift
│   │   └── DeviceLensConfig.swift
│   └── Gaze/
│       └── GazeTracker.swift
│
├── Evaluation/              ← [레이어 3] 종합 평가
│   ├── Gates/
│   │   ├── GateSystem.swift
│   │   ├── GateOrchestrator.swift
│   │   ├── GateModule.swift
│   │   ├── GateHelpers.swift
│   │   └── Modules/
│   │       ├── AspectRatioGate.swift
│   │       ├── FramingGate.swift
│   │       ├── PositionGate.swift
│   │       ├── LensDistanceGate.swift
│   │       └── PoseGate.swift
│   ├── UnifiedFeedbackEngine.swift
│   ├── GuideEngine.swift
│   └── PhotoAnalyzer.swift
│
├── Pipeline/                ← [레이어 4] 흐름 조율
│   ├── DetectionPipeline.swift
│   └── AnalysisCoordinator.swift
│
├── Reference/               ← 레퍼런스 처리 (기존 유지)
│   └── (기존 구조 유지)
│
├── Camera/                  ← 카메라 관리
│   ├── CameraManager.swift
│   └── CameraAngleDetector.swift
│
└── API/                     ← 외부 통신
    └── APIService.swift
```

---

## 2. 위험 포인트 (절대 주의)

### 🔴 CRITICAL - 절대 수정 금지

| 타입 | 파일 | 참조 수 | 이유 |
|------|------|---------|------|
| `PoseKeypoint` | Models/Feedback.swift | 14+ | 모든 Gate, 분석기에서 사용 |
| `CameraAspectRatio` | Models/Feedback.swift | 17+ | 카메라, 분석, 피드백 전체 |
| `ShotTypeGate` | Gates/Core/GateTypes.swift | 12+ | Gate 평가의 핵심 |
| `GateEvaluation` | Gates/Core/GateTypes.swift | 10+ | gate0~gate4 고정 구조 |
| `SimpleGuideResult` | Feedback/Models/GuideModels.swift | 8+ | UI 피드백 표시 |
| `RTMPoseRunner.shared` | Analysis/RTMPoseRunner.swift | - | Singleton, 앱 전체 의존 |

### 🟡 WARNING - 신중하게 처리

| 파일 | 이유 |
|------|------|
| `AdaptivePoseComparator.swift` | PoseComparisonResult 타입 정의 포함 |
| `UnifiedFeedbackEngine.swift` | EvaluationResult 내부 타입 정의 |
| `DetectionPipeline.swift` | 여러 Analysis 모듈 조율 |
| `AnalysisCoordinator.swift` | ContentView에서 직접 참조 |

### 🟢 SAFE - 자유롭게 이동 가능

| 파일 | 이유 |
|------|------|
| `GuidanceDebouncer.swift` | 의존성 없음 |
| `MarginAnalyzer.swift` | 제한적 참조 |
| `Reference/Modules/*.swift` | ReferenceAnalyzer에서만 사용 |

---

## Phase 1: 폴더 구조 생성

### 체크리스트

```bash
# 실행할 명령어 (순서대로)
```

- [ ] `Services/Core/Types/` 생성
- [ ] `Services/Inference/` 생성
- [ ] `Services/Domain/Pose/` 생성
- [ ] `Services/Domain/Framing/` 생성
- [ ] `Services/Domain/Composition/` 생성
- [ ] `Services/Domain/Depth/` 생성
- [ ] `Services/Domain/Lens/` 생성
- [ ] `Services/Domain/Gaze/` 생성
- [ ] `Services/Evaluation/Gates/Modules/` 생성
- [ ] `Services/Camera/` 생성
- [ ] `Services/API/` 생성

### 검증
- [ ] 모든 폴더 생성 확인
- [ ] 빌드 성공 (아직 파일 이동 전)

---

## Phase 2: Core 타입 정리

### 목표
공유 타입들을 `Core/Types/`로 모으기 (참조 경로 변경 최소화)

### 이동 계획

| # | 현재 위치 | 새 위치 | 참조 수 | 주의사항 |
|---|----------|---------|---------|----------|
| 2.1 | `Models/Feedback.swift` | `Core/Types/Feedback.swift` | 14+ | ⚠️ 외부 참조 많음 |
| 2.2 | `Gates/Core/GateTypes.swift` | `Core/Types/GateTypes.swift` | 12+ | ⚠️ Gate 전체 의존 |
| 2.3 | `Feedback/Models/GuideModels.swift` | `Core/Types/GuideModels.swift` | 8+ | ⚠️ UI 의존 |
| 2.4 | `Core/PipelineTypes.swift` | `Core/Types/PipelineTypes.swift` | 9+ | 경로만 변경 |
| 2.5 | `Core/DetectionInterfaces.swift` | `Core/Types/DetectionInterfaces.swift` | 10+ | 경로만 변경 |
| 2.6 | `Models/BodyType.swift` | `Core/Types/BodyType.swift` | 3 | 낮은 위험 |

### 체크리스트

- [ ] 2.1 `Models/Feedback.swift` → `Core/Types/Feedback.swift`
  - [ ] 파일 이동
  - [ ] Xcode 프로젝트 참조 업데이트
  - [ ] 빌드 확인
- [ ] 2.2 `Gates/Core/GateTypes.swift` → `Core/Types/GateTypes.swift`
  - [ ] 파일 이동
  - [ ] Xcode 프로젝트 참조 업데이트
  - [ ] 빌드 확인
- [ ] 2.3 `Feedback/Models/GuideModels.swift` → `Core/Types/GuideModels.swift`
  - [ ] 파일 이동
  - [ ] Xcode 프로젝트 참조 업데이트
  - [ ] 빌드 확인
- [ ] 2.4 `Core/PipelineTypes.swift` → `Core/Types/PipelineTypes.swift`
  - [ ] 파일 이동
  - [ ] 빌드 확인
- [ ] 2.5 `Core/DetectionInterfaces.swift` → `Core/Types/DetectionInterfaces.swift`
  - [ ] 파일 이동
  - [ ] 빌드 확인
- [ ] 2.6 `Models/BodyType.swift` → `Core/Types/BodyType.swift`
  - [ ] 파일 이동
  - [ ] 빌드 확인

### Phase 2 완료 검증
- [ ] `Core/Types/` 폴더에 6개 파일 존재
- [ ] 빌드 성공
- [ ] 기존 `Models/` 폴더 비어있음 (삭제 가능)
- [ ] **커밋**: "refactor: Phase 2 - Core 타입 정리"

---

## Phase 3: Inference 레이어 구성

### 목표
AI 모델 실행 파일들을 `Inference/`로 모으기

### 이동 계획

| # | 현재 위치 | 새 위치 | 줄 수 | 주의사항 |
|---|----------|---------|-------|----------|
| 3.1 | `Analysis/RTMPoseRunner.swift` | `Inference/RTMPoseRunner.swift` | 580 | ⚠️ Singleton, TryAngleApp 참조 |
| 3.2 | `Modules/Lens/DepthAnythingCoreML.swift` | `Inference/DepthAnythingRunner.swift` | 444 | 파일명 변경 |
| 3.3 | `Analysis/VisionAnalyzer.swift` | `Inference/VisionAnalyzer.swift` | 231 | 낮은 위험 |
| 3.4 | `Modules/Pose/Legacy/PersonDetector.swift` | `Inference/PersonDetector.swift` | 243 | BBoxModule에서 사용 |

### 체크리스트

- [ ] 3.1 `Analysis/RTMPoseRunner.swift` → `Inference/RTMPoseRunner.swift`
  - [ ] 파일 이동
  - [ ] TryAngleApp.swift 참조 확인 (RTMPoseRunner.initializeInBackground)
  - [ ] Xcode 프로젝트 참조 업데이트
  - [ ] 빌드 확인
- [ ] 3.2 `Modules/Lens/DepthAnythingCoreML.swift` → `Inference/DepthAnythingRunner.swift`
  - [ ] 파일 이동 + 이름 변경
  - [ ] 클래스명 변경 필요 여부 확인
  - [ ] Xcode 프로젝트 참조 업데이트
  - [ ] 빌드 확인
- [ ] 3.3 `Analysis/VisionAnalyzer.swift` → `Inference/VisionAnalyzer.swift`
  - [ ] 파일 이동
  - [ ] 빌드 확인
- [ ] 3.4 `Modules/Pose/Legacy/PersonDetector.swift` → `Inference/PersonDetector.swift`
  - [ ] 파일 이동
  - [ ] BBoxModule.swift 참조 확인
  - [ ] Legacy 폴더에서 제거
  - [ ] 빌드 확인

### Phase 3 완료 검증
- [ ] `Inference/` 폴더에 4개 파일 존재
- [ ] RTMPoseRunner.shared 정상 작동
- [ ] 빌드 성공
- [ ] **커밋**: "refactor: Phase 3 - Inference 레이어 구성"

---

## Phase 4: Domain 레이어 구성

### 목표
도메인별 처리 파일들을 `Domain/`으로 모으기

### 4.1 Domain/Pose/

| # | 현재 위치 | 새 위치 | 줄 수 |
|---|----------|---------|-------|
| 4.1.1 | `Modules/Pose/RTMPoseService.swift` | `Domain/Pose/RTMPoseService.swift` | 277 |
| 4.1.2 | `Modules/Pose/KeypointSmoother.swift` | `Domain/Pose/KeypointSmoother.swift` | 192 |

- [ ] 4.1.1 RTMPoseService.swift 이동
- [ ] 4.1.2 KeypointSmoother.swift 이동
- [ ] 빌드 확인

### 4.2 Domain/Framing/

| # | 현재 위치 | 새 위치 | 줄 수 |
|---|----------|---------|-------|
| 4.2.1 | `Analysis/PhotographyFramingAnalyzer.swift` | `Domain/Framing/PhotographyFramingAnalyzer.swift` | 989 |
| 4.2.2 | `Analysis/FramingAnalyzer.swift` | `Domain/Framing/FramingAnalyzer.swift` | 314 |

- [ ] 4.2.1 PhotographyFramingAnalyzer.swift 이동
- [ ] 4.2.2 FramingAnalyzer.swift 이동
- [ ] 빌드 확인

### 4.3 Domain/Composition/

| # | 현재 위치 | 새 위치 | 줄 수 |
|---|----------|---------|-------|
| 4.3.1 | `Modules/Composition/MarginAnalyzer.swift` | `Domain/Composition/MarginAnalyzer.swift` | 502 |
| 4.3.2 | `Analysis/OnDeviceCompositionAnalyzer.swift` | `Domain/Composition/OnDeviceCompositionAnalyzer.swift` | 388 |
| 4.3.3 | `RuleEngine/CompositionAnalyzer.swift` | `Domain/Composition/CompositionAnalyzer.swift` | 256 |
| 4.3.4 | `Modules/Composition/AestheticService.swift` | `Domain/Composition/AestheticService.swift` | 64 |

- [ ] 4.3.1 MarginAnalyzer.swift 이동
- [ ] 4.3.2 OnDeviceCompositionAnalyzer.swift 이동
- [ ] 4.3.3 CompositionAnalyzer.swift 이동
- [ ] 4.3.4 AestheticService.swift 이동
- [ ] 빌드 확인

### 4.4 Domain/Depth/

| # | 현재 위치 | 새 위치 | 줄 수 |
|---|----------|---------|-------|
| 4.4.1 | `Modules/Depth/DepthService.swift` | `Domain/Depth/DepthService.swift` | 58 |

- [ ] 4.4.1 DepthService.swift 이동
- [ ] 빌드 확인

### 4.5 Domain/Lens/

| # | 현재 위치 | 새 위치 | 줄 수 |
|---|----------|---------|-------|
| 4.5.1 | `Modules/Lens/FocalLengthEstimator.swift` | `Domain/Lens/FocalLengthEstimator.swift` | 326 |
| 4.5.2 | `Modules/Lens/DistanceEstimator.swift` | `Domain/Lens/DistanceEstimator.swift` | 206 |
| 4.5.3 | `Modules/Lens/DeviceLensConfig.swift` | `Domain/Lens/DeviceLensConfig.swift` | 149 |

- [ ] 4.5.1 FocalLengthEstimator.swift 이동
- [ ] 4.5.2 DistanceEstimator.swift 이동
- [ ] 4.5.3 DeviceLensConfig.swift 이동
- [ ] 빌드 확인

### 4.6 Domain/Gaze/

| # | 현재 위치 | 새 위치 | 줄 수 |
|---|----------|---------|-------|
| 4.6.1 | `Analysis/GazeTracker.swift` | `Domain/Gaze/GazeTracker.swift` | 244 |

- [ ] 4.6.1 GazeTracker.swift 이동
- [ ] 빌드 확인

### Phase 4 완료 검증
- [ ] `Domain/` 하위 6개 폴더 존재
- [ ] 총 14개 파일 이동 완료
- [ ] 빌드 성공
- [ ] **커밋**: "refactor: Phase 4 - Domain 레이어 구성"

---

## Phase 5: Evaluation 레이어 구성

### 목표
평가 및 피드백 파일들을 `Evaluation/`으로 모으기

### 5.1 Evaluation/Gates/

| # | 현재 위치 | 새 위치 | 줄 수 |
|---|----------|---------|-------|
| 5.1.1 | `Gates/Core/GateSystem.swift` | `Evaluation/Gates/GateSystem.swift` | 223 |
| 5.1.2 | `Gates/Core/GateOrchestrator.swift` | `Evaluation/Gates/GateOrchestrator.swift` | 118 |
| 5.1.3 | `Gates/Core/GateModule.swift` | `Evaluation/Gates/GateModule.swift` | 83 |
| 5.1.4 | `Gates/Core/GateHelpers.swift` | `Evaluation/Gates/GateHelpers.swift` | 256 |

- [ ] 5.1.1 GateSystem.swift 이동
- [ ] 5.1.2 GateOrchestrator.swift 이동
- [ ] 5.1.3 GateModule.swift 이동
- [ ] 5.1.4 GateHelpers.swift 이동
- [ ] 빌드 확인

### 5.2 Evaluation/Gates/Modules/

| # | 현재 위치 | 새 위치 | 줄 수 |
|---|----------|---------|-------|
| 5.2.1 | `Gates/Modules/AspectRatioGate.swift` | `Evaluation/Gates/Modules/AspectRatioGate.swift` | 67 |
| 5.2.2 | `Gates/Modules/FramingGate.swift` | `Evaluation/Gates/Modules/FramingGate.swift` | 246 |
| 5.2.3 | `Gates/Modules/PositionGate.swift` | `Evaluation/Gates/Modules/PositionGate.swift` | 186 |
| 5.2.4 | `Gates/Modules/LensDistanceGate.swift` | `Evaluation/Gates/Modules/LensDistanceGate.swift` | 213 |
| 5.2.5 | `Gates/Modules/PoseGate.swift` | `Evaluation/Gates/Modules/PoseGate.swift` | 156 |

- [ ] 5.2.1 AspectRatioGate.swift 이동
- [ ] 5.2.2 FramingGate.swift 이동
- [ ] 5.2.3 PositionGate.swift 이동
- [ ] 5.2.4 LensDistanceGate.swift 이동
- [ ] 5.2.5 PoseGate.swift 이동
- [ ] 빌드 확인

### 5.3 Evaluation/ (루트)

| # | 현재 위치 | 새 위치 | 줄 수 |
|---|----------|---------|-------|
| 5.3.1 | `Feedback/Engine/UnifiedFeedbackEngine.swift` | `Evaluation/UnifiedFeedbackEngine.swift` | 675 |
| 5.3.2 | `Feedback/Logic/GuideEngine.swift` | `Evaluation/GuideEngine.swift` | 185 |
| 5.3.3 | `Analysis/PhotoAnalyzer.swift` | `Evaluation/PhotoAnalyzer.swift` | 243 |

- [ ] 5.3.1 UnifiedFeedbackEngine.swift 이동
- [ ] 5.3.2 GuideEngine.swift 이동
- [ ] 5.3.3 PhotoAnalyzer.swift 이동
- [ ] 빌드 확인

### Phase 5 완료 검증
- [ ] `Evaluation/Gates/Modules/` 폴더에 5개 Gate 파일
- [ ] `Evaluation/Gates/` 폴더에 4개 Core 파일
- [ ] `Evaluation/` 루트에 3개 Engine 파일
- [ ] 빌드 성공
- [ ] **커밋**: "refactor: Phase 5 - Evaluation 레이어 구성"

---

## Phase 6: Pipeline 레이어 구성

### 목표
조율 파일들을 `Pipeline/`으로 모으기

| # | 현재 위치 | 새 위치 | 줄 수 | 주의사항 |
|---|----------|---------|-------|----------|
| 6.1 | `Pipeline/DetectionPipeline.swift` | 유지 | 239 | 경로 변경 없음 |
| 6.2 | `Core/Coordinator/AnalysisCoordinator.swift` | `Pipeline/AnalysisCoordinator.swift` | 334 | ⚠️ ContentView 참조 |

### 체크리스트

- [ ] 6.1 DetectionPipeline.swift - 이미 Pipeline/에 있음 (확인만)
- [ ] 6.2 `Core/Coordinator/AnalysisCoordinator.swift` → `Pipeline/AnalysisCoordinator.swift`
  - [ ] 파일 이동
  - [ ] ContentView.swift 참조 확인
  - [ ] CameraView.swift 참조 확인
  - [ ] 빌드 확인

### Phase 6 완료 검증
- [ ] `Pipeline/` 폴더에 2개 파일
- [ ] ContentView에서 정상 참조
- [ ] 빌드 성공
- [ ] **커밋**: "refactor: Phase 6 - Pipeline 레이어 구성"

---

## Phase 7: AdaptivePoseComparator 분리

### 목표
1207줄짜리 AdaptivePoseComparator.swift를 3개 파일로 분리

### 현재 파일 구조 분석

```swift
// AdaptivePoseComparator.swift (1207줄)

// 1~75줄: 타입 정의
public enum PoseType { ... }
public enum KeypointGroup { ... }
public struct PoseComparisonResult { ... }

// 76~600줄: 비교 로직
public class AdaptivePoseComparator {
    // 키포인트 정의
    // 비교 메서드들
    // comparePoses() → PoseComparisonResult
}

// 600~1207줄: 피드백 생성 로직
extension AdaptivePoseComparator {
    // generateFeedback()
    // 각 부위별 피드백 생성
}
```

### 분리 계획

| # | 새 파일 | 내용 | 예상 줄 수 |
|---|--------|------|-----------|
| 7.1 | `Domain/Pose/PoseTypes.swift` | PoseType, KeypointGroup, PoseComparisonResult | ~180 |
| 7.2 | `Domain/Pose/PoseComparator.swift` | AdaptivePoseComparator 클래스 (비교 로직) | ~500 |
| 7.3 | `Domain/Pose/PoseFeedbackGenerator.swift` | 피드백 생성 extension | ~450 |

### 체크리스트

- [ ] 7.1 `Domain/Pose/PoseTypes.swift` 생성
  - [ ] PoseType enum 이동
  - [ ] KeypointGroup enum 이동
  - [ ] PoseComparisonResult struct 이동
  - [ ] 빌드 확인 (타입 참조)

- [ ] 7.2 `Domain/Pose/PoseComparator.swift` 생성
  - [ ] AdaptivePoseComparator 클래스 이동
  - [ ] 키포인트 정의 (bodyKeypointNames 등)
  - [ ] comparePoses() 메서드
  - [ ] detectCroppedGroups() 메서드
  - [ ] import PoseTypes 추가
  - [ ] 빌드 확인

- [ ] 7.3 `Domain/Pose/PoseFeedbackGenerator.swift` 생성
  - [ ] generateFeedback() extension 이동
  - [ ] 각 부위별 피드백 메서드
  - [ ] import PoseTypes, PoseComparator 추가
  - [ ] 빌드 확인

- [ ] 7.4 기존 `Comparison/AdaptivePoseComparator.swift` 삭제
  - [ ] Xcode 프로젝트에서 제거
  - [ ] 빌드 확인

### Phase 7 완료 검증
- [ ] `Domain/Pose/` 폴더에 5개 파일 (기존 2개 + 새 3개)
- [ ] PoseComparisonResult 타입 정상 참조 (PoseGate, FrameAnalysisResult)
- [ ] 기존 Comparison/ 폴더 비어있음
- [ ] 빌드 성공
- [ ] **커밋**: "refactor: Phase 7 - AdaptivePoseComparator 분리"

---

## Phase 8: 파이프라인 연결

### 목표
AdaptivePoseComparator가 실제로 호출되도록 연결

### 현재 문제
```
FrameAnalysisResult.poseComparison = nil (항상)
↓
PoseGate.evaluate() → early return (포즈 평가 안 됨)
↓
AdaptivePoseComparator.comparePoses() → 아무도 안 부름
```

### 연결 계획

#### 8.1 FrameAnalysisResult에 poseComparison 설정

**위치:** `Pipeline/DetectionPipeline.swift` 또는 `Pipeline/AnalysisCoordinator.swift`

```swift
// 연결할 위치 찾기:
// 1. FrameAnalysisResult 생성 시점
// 2. 레퍼런스 키포인트와 현재 키포인트가 모두 있을 때

// 추가할 코드:
let comparator = AdaptivePoseComparator()
let comparison = comparator.comparePoses(
    reference: referenceKeypoints,
    current: currentKeypoints
)
result.poseComparison = comparison
```

### 체크리스트

- [ ] 8.1 연결 위치 확인
  - [ ] FrameAnalysisResult 생성 위치 찾기
  - [ ] referenceKeypoints 접근 가능한지 확인
  - [ ] currentKeypoints 접근 가능한지 확인

- [ ] 8.2 AdaptivePoseComparator 인스턴스 생성
  - [ ] Singleton 패턴 사용 여부 결정
  - [ ] 또는 매번 새 인스턴스

- [ ] 8.3 comparePoses() 호출 추가
  - [ ] 레퍼런스 있을 때만 호출
  - [ ] 결과를 poseComparison에 할당

- [ ] 8.4 PoseGate 작동 확인
  - [ ] poseComparison이 nil이 아닌지 확인
  - [ ] Gate 4 (포즈) 평가 작동 확인

### Phase 8 완료 검증
- [ ] poseComparison 값이 설정됨
- [ ] PoseGate.evaluate() 정상 작동
- [ ] Gate 4 평가 결과 UI에 표시
- [ ] 빌드 성공
- [ ] **커밋**: "feat: Phase 8 - AdaptivePoseComparator 파이프라인 연결"

---

## Phase 9: import 수정

### 목표
파일 이동으로 인한 import 경로 수정

### 주의사항
- Swift는 같은 타겟 내에서 import 불필요 (대부분의 경우)
- Xcode 프로젝트 파일(.pbxproj) 참조만 정확하면 됨
- 외부 참조 (ContentView 등)만 확인 필요

### 체크리스트

- [ ] 9.1 외부 파일 참조 확인
  - [ ] TryAngleApp.swift → RTMPoseRunner 참조
  - [ ] ContentView.swift → CameraManager, AnalysisCoordinator 참조
  - [ ] CameraView.swift → CameraManager 참조
  - [ ] FeedbackOverlay.swift → 타입 참조
  - [ ] DiagnosticDashboard.swift → DetectionPipeline 참조

- [ ] 9.2 Xcode 프로젝트 파일 정리
  - [ ] 삭제된 파일 참조 제거
  - [ ] 새 파일 참조 추가
  - [ ] 그룹 구조 정리

### Phase 9 완료 검증
- [ ] 모든 외부 참조 정상
- [ ] Xcode 프로젝트 구조 정리됨
- [ ] 빌드 성공
- [ ] **커밋**: "chore: Phase 9 - import 및 프로젝트 참조 정리"

---

## Phase 10: 빌드 & 검증

### 체크리스트

- [ ] 10.1 빌드 검증
  - [ ] Debug 빌드 성공
  - [ ] Release 빌드 성공
  - [ ] 경고 확인 및 정리

- [ ] 10.2 런타임 검증
  - [ ] 앱 실행
  - [ ] 카메라 작동
  - [ ] 레퍼런스 분석 작동
  - [ ] 실시간 분석 작동
  - [ ] Gate 0~4 모두 평가
  - [ ] 포즈 비교 작동 (Gate 4)
  - [ ] 피드백 UI 표시

- [ ] 10.3 최종 정리
  - [ ] 빈 폴더 삭제 (Legacy 검토)
  - [ ] 불필요한 파일 삭제
  - [ ] README 업데이트

### Phase 10 완료 검증
- [ ] 앱 정상 작동
- [ ] 모든 기능 테스트 완료
- [ ] **최종 커밋**: "refactor: 하이브리드 구조 리팩토링 완료"

---

## 롤백 계획

### Phase별 롤백

각 Phase 커밋 후 문제 발생 시:

```bash
# 마지막 커밋 취소
git reset --hard HEAD~1

# 또는 특정 커밋으로 복구
git reset --hard <commit-hash>
```

### 전체 롤백

리팩토링 시작 전 브랜치 생성:

```bash
# 시작 전
git checkout -b refactor/hybrid-structure
git push -u origin refactor/hybrid-structure

# 문제 시 main으로 복귀
git checkout main
```

---

## 진행 상황

| Phase | 상태 | 완료일 | 커밋 |
|-------|------|--------|------|
| Phase 1 | ⬜ 대기 | - | - |
| Phase 2 | ⬜ 대기 | - | - |
| Phase 3 | ⬜ 대기 | - | - |
| Phase 4 | ⬜ 대기 | - | - |
| Phase 5 | ⬜ 대기 | - | - |
| Phase 6 | ⬜ 대기 | - | - |
| Phase 7 | ⬜ 대기 | - | - |
| Phase 8 | ⬜ 대기 | - | - |
| Phase 9 | ⬜ 대기 | - | - |
| Phase 10 | ⬜ 대기 | - | - |

---

## 파일 이동 요약

### 총 파일 수

| 카테고리 | 파일 수 |
|----------|---------|
| Core/Types/ 이동 | 6 |
| Inference/ 이동 | 4 |
| Domain/ 이동 | 14 |
| Evaluation/ 이동 | 12 |
| Pipeline/ 이동 | 1 |
| Camera/ 이동 | 2 |
| API/ 이동 | 1 |
| 분리 (새 파일) | 3 |
| **총합** | **43** |

### 삭제 예정

| 파일 | 이유 |
|------|------|
| `Comparison/AdaptivePoseComparator.swift` | 분리 후 삭제 |
| `Pipeline/Legacy/TryAngleOnDeviceAnalyzer.swift` | 미사용 레거시 |
| 빈 폴더들 | 파일 이동 후 |
