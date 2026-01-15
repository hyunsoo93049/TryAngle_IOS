# Legacy Code 정리 가이드

## 개요
이 문서는 TryAngle iOS 앱에서 **사용되지 않는 레거시 코드**를 정리한 내용입니다.
각 파일은 원래 위치에 그대로 있으며, 파일 상단에 `⚠️ LEGACY CODE` 주석이 추가되어 있습니다.

---

## 레거시 파일 목록

| 파일 | 위치 | 삭제 가능 | 대체 파일 |
|------|------|----------|----------|
| SimplifiedFeedbackOverlay.swift | Views/ | ✅ 가능 | FeedbackOverlay.swift |
| UnifiedFeedbackGenerator.swift | Services/OnDevice/ | ⚠️ 주의 (타입 참조) | SimpleRealTimeGuide.swift |
| V15FeedbackGenerator.swift | Services/OnDevice/ | ✅ 가능 | SimpleRealTimeGuide.swift |
| FramingAnalyzer.swift | Services/Analysis/ | ✅ 가능 | PhotographyFramingAnalyzer.swift |

---

## 상세 설명

### 1. SimplifiedFeedbackOverlay.swift
- **원래 용도**: 단순화된 피드백 오버레이 UI
- **미사용 이유**: `FeedbackOverlay.swift`가 모든 UI 담당
- **삭제 가능**: ✅ (어디서도 호출되지 않음)

### 2. UnifiedFeedbackGenerator.swift
- **원래 용도**: 여러 Gate 결과를 통합하여 하나의 피드백 생성
- **미사용 이유**: FeedbackOverlay에서 `unifiedFeedback` 파라미터 무시
- **삭제 주의**: `UnifiedFeedback` 구조체가 다른 곳에서 참조됨
  - 삭제 전 타입 정의를 별도 파일로 분리 필요

### 3. V15FeedbackGenerator.swift
- **원래 용도**: 133개 키포인트 기반 상세 피드백 (v1.5)
- **미사용 이유**: 너무 복잡, UI에서 무시됨
- **삭제 가능**: ✅ (어디서도 호출되지 않음)

### 4. FramingAnalyzer.swift
- **원래 용도**: 레퍼런스/현재 이미지 프레이밍 분석
- **미사용 이유**: 인스턴스화만 되고 메서드 호출 없음
- **삭제 가능**: ✅ (메서드 호출 없음)
- **대체 파일들**:
  - `PhotographyFramingAnalyzer.swift` (사진학 기반)
  - `GateSystem.swift` (Gate별 분석)
  - `MarginAnalyzer.swift` (마진 전문)

---

## 정리 이력

| 날짜 | 작업 |
|------|------|
| 2025-12-29 | Python v6 비교 중 레거시 코드 발견 |
| 2025-12-29 | `SimpleRealTimeGuide`로 피드백 시스템 통합 |
| 2025-12-29 | 레거시 파일에 LEGACY 헤더 추가 |
| 2025-12-29 | RealtimeAnalyzer에서 framingAnalyzer 인스턴스 제거 |

---

## 현재 피드백 시스템 아키텍처

```
SimpleRealTimeGuide.swift (메인)
├── 6단계 순차 가이드
│   ├── 1. 프레임 진입
│   ├── 2. 샷타입
│   ├── 3. 위치 (틸트 각도 포함)
│   ├── 4. 크기
│   ├── 5. 줌
│   └── 6. 포즈
│
├── v6 스타일 피드백 메시지
│   ├── "카메라를 5° 위로 틸트"
│   ├── "왼쪽으로 이동 (15%)"
│   └── "1.5x로 줌인 (현재 1.0x)"
│
└── FeedbackOverlay.swift (UI)
    └── SimpleGuideFeedbackView
```

---

## 완전 삭제 방법

1. Xcode에서 해당 파일 선택
2. Delete → "Move to Trash" 선택
3. `UnifiedFeedbackGenerator.swift` 삭제 시:
   - 먼저 `UnifiedFeedback` 타입 사용처 확인
   - 필요시 타입 정의만 별도 파일로 이동
