import SwiftUI

struct FeedbackOverlay: View {
    let feedbackItems: [FeedbackItem]
    let categoryStatuses: [CategoryStatus]  // 🗑️ 레거시 (호환용)
    let completedFeedbacks: [CompletedFeedback]
    let processingTime: String
    let gateEvaluation: GateEvaluation?  // 🆕 Gate System 평가 결과
    let unifiedFeedback: UnifiedFeedback?  // 🆕 통합 피드백 (하나의 동작 → 여러 Gate 해결)
    let stabilityProgress: Float  // 🆕 0.0 ~ 1.0 (Temporal Lock 진행도)

    let environmentWarning: String?  // 🆕 환경 경고 (너무 어두움 등)
    let currentShotDebugInfo: String? // 🆕 화면 표시용 샷타입 정보 (Debug Mode)

    // 🆕 안정적인 피드백 (진행률 바 포함)
    let activeFeedback: ActiveFeedback?

    // 🆕 단순화된 실시간 가이드
    let simpleGuide: SimpleGuideResult?

    // 🆕 종횡비 불일치 여부 (다른 피드백 숨김 조건)
    private var isAspectRatioMismatch: Bool {
        guard let eval = gateEvaluation else { return false }
        return !eval.gate0.passed
    }

    var body: some View {
        ZStack {
            // ============================================
            // 🚨 종횡비 불일치 시: 오직 비율 피드백만 표시
            // ============================================
            if isAspectRatioMismatch {
                // 종횡비 피드백만 표시 (다른 피드백 모두 숨김)
                VStack {
                    Spacer()

                    if let eval = gateEvaluation {
                        AspectRatioFeedbackView(feedback: eval.gate0.feedback)
                            .padding(.horizontal, 20)
                    }

                    Spacer()
                }
            } else {
                // ============================================
                // ✅ 종횡비 일치 시: 기존 피드백 로직
                // ============================================

                // 🆕 상단 고정: Gate 상태바
                VStack {
                    GateStatusBar(evaluation: gateEvaluation, simpleGuide: simpleGuide)
                        .padding(.top, 8)
                        .padding(.horizontal, 16)

                    Spacer()

                    // 🆕 하단: SimpleGuide 메인 피드백
                    if let guide = simpleGuide {
                        SimpleGuideFeedbackView(guide: guide)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 120)
                    }
                }

                // 🆕 중앙: Temporal Lock (Circular Ring) - 완벽 상태일 때만 표시
                if stabilityProgress > 0.0 {
                    VStack {
                        Spacer()
                        ZStack {
                            CircularGateProgressView(progress: stabilityProgress)

                            if stabilityProgress >= 1.0 {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.bottom, 300)
                        Spacer()
                    }
                    .transition(.opacity)
                    .animation(.easeInOut, value: stabilityProgress > 0)
                }

                // 🆕 환경 경고
                if let warning = environmentWarning {
                    VStack {
                        Text(warning)
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(12)
                            .padding(.top, 60)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut, value: warning)
                }
            }
        }
    }

    // 🆕 현재 Gate의 피드백 메시지
    private var currentGateFeedback: String? {
        guard let eval = gateEvaluation else { return nil }
        if eval.allPassed { return nil }
        return eval.primaryFeedback
    }

    // 카테고리별 강조 색상
    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "pose":
            return .purple
        case "distance":
            return .blue
        case "composition":
            return .orange
        default:
            return .gray
        }
    }
}

// MARK: - 개별 피드백 아이템 뷰 (실시간 진행도 표시)
struct FeedbackItemView: View {
    let item: FeedbackItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 상단: 아이콘 + 메시지
            HStack(spacing: 12) {
                Text(item.icon)
                    .font(.title2)

                Text(item.message)
                    .font(.body)
                    .foregroundColor(.white)
                    .lineLimit(2)

                Spacer()

                // 완료 체크 표시
                if item.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }
            }

            // 하단: 실시간 진행도 표시
            if let current = item.currentValue,
               let target = item.targetValue,
               let unit = item.unit {

                HStack(spacing: 12) {
                    // 현재값 → 목표값
                    Text(String(format: "%.0f%@ → %.0f%@", current, unit, target, unit))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .monospacedDigit()

                    Spacer()

                    // 차이값 표시
                    let diff = abs(target - current)
                    Text(String(format: "차이: %.0f%@", diff, unit))
                        .font(.caption)
                        .foregroundColor(diff <= (item.tolerance ?? 3.0) ? .green : .orange)
                        .monospacedDigit()
                }

                // 프로그레스 바
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // 배경
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 8)

                        // 진행 바
                        RoundedRectangle(cornerRadius: 4)
                            .fill(progressColor)
                            .frame(width: geometry.size.width * progressWidth, height: 8)
                            .animation(.easeInOut(duration: 0.3), value: progressWidth)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.black.opacity(0.7)
                .overlay(
                    categoryColor(item.category)
                        .frame(width: 4),
                    alignment: .leading
                )
        )
        .cornerRadius(12)
    }

    // 진행도 바 너비 계산
    private var progressWidth: CGFloat {
        guard let current = item.currentValue,
              let target = item.targetValue else {
            return 0.0
        }

        let diff = abs(target - current)
        let tolerance = item.tolerance ?? 3.0

        // 차이가 허용 오차 이내면 100%
        if diff <= tolerance {
            return 1.0
        }

        // 차이가 클수록 진행도 낮음 (최대 50도 기준)
        let maxDiff = 50.0
        return max(0.0, min(1.0, 1.0 - (diff / maxDiff)))
    }

    // 진행도에 따른 색상
    private var progressColor: Color {
        if item.isCompleted {
            return .green
        } else if progressWidth > 0.7 {
            return .yellow
        } else if progressWidth > 0.4 {
            return .orange
        } else {
            return .red
        }
    }

    // 카테고리별 강조 색상
    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "pose":
            return .purple
        case "distance":
            return .blue
        case "composition":
            return .orange
        default:
            return .gray
        }
    }
}

// MARK: - 완료된 피드백 뷰 (초록색 + 페이드아웃)
struct CompletedFeedbackView: View {
    let completed: CompletedFeedback

    var body: some View {
        HStack(spacing: 12) {
            // 체크 아이콘
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.white)

            Text(completed.item.icon)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(completed.item.message)
                    .font(.body)
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text("완료!")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.green.opacity(0.9)
                .overlay(
                    Color.white.opacity(0.2)
                        .frame(width: 4),
                    alignment: .leading
                )
        )
        .cornerRadius(12)
        .shadow(color: .green.opacity(0.5), radius: 10, x: 0, y: 5)
        .opacity(completed.fadeProgress)
        .scaleEffect(completed.fadeProgress * 0.1 + 0.9)  // 살짝 작아지면서 사라짐
    }
}

// MARK: - 🆕 Gate 피드백 뷰 (현재 Gate의 피드백만 표시)
struct GateFeedbackView: View {
    let feedback: String
    let gateIndex: Int

    private let gateInfo: [(name: String, icon: String, color: Color)] = [
        ("비율", "📐", .blue),
        ("프레이밍", "📸", .orange),
        ("위치", "↔️", .purple),
        ("압축감", "🔭", .cyan),
        ("포즈", "🤸", .pink)
    ]

    var body: some View {
        let info = gateInfo[min(gateIndex, 4)]

        VStack(alignment: .leading, spacing: 8) {
            // 상단: Gate 정보
            HStack(spacing: 8) {
                // Gate 번호
                Text("Gate \(gateIndex + 1)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow)
                    .cornerRadius(4)

                Text(info.icon)
                    .font(.title2)

                Text(info.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                Spacer()
            }

            // 피드백 메시지
            Text(feedback)
                .font(.body)
                .foregroundColor(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.black.opacity(0.8)
                .overlay(
                    info.color.frame(width: 4),
                    alignment: .leading
                )
        )
        .cornerRadius(12)
    }
}

// MARK: - 🆕 통합 피드백 뷰 (하나의 동작 → 여러 Gate 해결)
struct UnifiedFeedbackView: View {
    let feedback: UnifiedFeedback

    private let gateInfo: [(name: String, icon: String, color: Color)] = [
        ("비율", "📐", .blue),
        ("프레이밍", "📸", .orange),
        ("위치", "↔️", .purple),
        ("압축감", "🔭", .cyan),
        ("포즈", "🤸", .pink)
    ]

    // 동작별 아이콘
    private func actionIcon(_ action: AdjustmentAction) -> String {
        switch action {
        case .moveForward: return "⬆️"
        case .moveBackward: return "⬇️"
        case .moveLeft: return "⬅️"
        case .moveRight: return "➡️"
        case .tiltUp: return "🔼"
        case .tiltDown: return "🔽"
        case .zoomIn: return "🔍"
        case .zoomOut: return "🔎"
        // 🆕 복합 동작
        case .zoomInThenMoveBack: return "🔍⬇️"
        case .zoomInThenMoveForward: return "🔍⬆️"
        case .zoomOutThenMoveBack: return "🔎⬇️"
        case .zoomOutThenMoveForward: return "🔎⬆️"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 상단: 메인 동작 지시
            HStack(spacing: 12) {
                // 동작 아이콘
                Text(actionIcon(feedback.primaryAction))
                    .font(.system(size: 32))

                VStack(alignment: .leading, spacing: 2) {
                    // 메인 메시지 (크기 + 동작)
                    Text(feedback.mainMessage)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    // 영향 받는 Gate 뱃지들
                    HStack(spacing: 6) {
                        ForEach(feedback.affectedGates, id: \.self) { gateIdx in
                            let info = gateInfo[min(gateIdx, 4)]
                            HStack(spacing: 2) {
                                Text(info.icon)
                                    .font(.system(size: 10))
                                Text(info.name)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(info.color.opacity(0.3))
                            .cornerRadius(4)
                        }
                    }
                }

                Spacer()

                // 다중 Gate 해결 표시
                if feedback.affectedGates.count > 1 {
                    VStack(spacing: 2) {
                        Text("\(feedback.affectedGates.count)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.green)
                        Text("Gates")
                            .font(.system(size: 10))
                            .foregroundColor(.green.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(8)
                }
            }

            // 하단: 예상 결과들
            if !feedback.expectedResults.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.3))

                VStack(alignment: .leading, spacing: 4) {
                    Text("예상 결과")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    ForEach(feedback.expectedResults, id: \.self) { result in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 12))
                                .foregroundColor(.green.opacity(0.8))
                            Text(result)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.85),
                    Color.black.opacity(0.75)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                // 왼쪽 강조선 (첫 번째 영향 Gate 색상)
                gateInfo[min(feedback.priority, 4)].color.frame(width: 4),
                alignment: .leading
            )
        )
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 🆕 비율 피드백 뷰 (Gate 0 - 간결한 버전)
struct AspectRatioFeedbackView: View {
    let feedback: String

    var body: some View {
        HStack(spacing: 12) {
            // 비율 아이콘
            Text("📐")
                .font(.system(size: 28))

            VStack(alignment: .leading, spacing: 4) {
                Text("비율 불일치")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.orange)

                Text(feedback)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Color.black.opacity(0.85)
                .overlay(
                    Color.red.frame(width: 4),
                    alignment: .leading
                )
        )
        .cornerRadius(16)
        .shadow(color: .red.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 카테고리 체크리스트 뷰 (레거시)
struct CategoryChecklistView: View {
    let categoryStatuses: [CategoryStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(categoryStatuses) { status in
                CategoryCheckItem(status: status)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.6))
        )
    }
}

// MARK: - 개별 카테고리 체크 아이템
struct CategoryCheckItem: View {
    let status: CategoryStatus

    var body: some View {
        HStack(spacing: 6) {
            // 카테고리 이름
            Text(status.category.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(status.isSatisfied ? .white.opacity(0.7) : .white)

            // 체크 아이콘 (글자 바로 옆)
            Image(systemName: status.isSatisfied ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundColor(status.isSatisfied ? .green : .white.opacity(0.5))
                .animation(.easeInOut(duration: 0.3), value: status.isSatisfied)
        }
    }
}

struct FeedbackOverlay_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // 🆕 SimpleGuide 미리보기
            FeedbackOverlay(
                feedbackItems: [],
                categoryStatuses: [],
                completedFeedbacks: [],
                processingTime: "0.8s",
                gateEvaluation: nil,
                unifiedFeedback: nil,
                stabilityProgress: 0.5,
                environmentWarning: nil,
                currentShotDebugInfo: "현재: 전신샷 vs 목표: 허벅지샷",
                activeFeedback: nil,
                simpleGuide: SimpleGuideResult(
                    guide: .moveForward,
                    magnitude: "한 걸음",
                    progress: 0.6,
                    debugInfo: "크기 75%",
                    shotTypeMatch: false,
                    currentShotType: "전신샷",
                    targetShotType: "허벅지샷",
                    feedbackStage: .shotType
                )
            )

            // 완벽 상태 미리보기
            FeedbackOverlay(
                feedbackItems: [],
                categoryStatuses: [],
                completedFeedbacks: [],
                processingTime: "0.8s",
                gateEvaluation: nil,
                unifiedFeedback: nil,
                stabilityProgress: 1.0,
                environmentWarning: nil,
                currentShotDebugInfo: nil,
                activeFeedback: nil,
                simpleGuide: SimpleGuideResult(
                    guide: .perfect,
                    magnitude: "",
                    progress: 1.0,
                    debugInfo: "완벽",
                    shotTypeMatch: true,
                    currentShotType: "허벅지샷",
                    targetShotType: "허벅지샷",
                    feedbackStage: .perfect
                )
            )
        }
        .background(Color.black)
    }
}


// MARK: - 🆕 Active Feedback View (안정적인 피드백 + 진행률 바)
struct ActiveFeedbackView: View {
    let feedback: ActiveFeedback
    let gateEvaluation: GateEvaluation?

    private let gateInfo: [(name: String, icon: String, color: Color)] = [
        ("비율", "📐", .blue),
        ("프레이밍", "📸", .orange),
        ("위치", "↔️", .purple),
        ("압축감", "🔭", .cyan),
        ("포즈", "🤸", .pink)
    ]

    var body: some View {
        let info = gateInfo[min(feedback.gateIndex, 4)]

        VStack(alignment: .leading, spacing: 10) {
            // 상단: Gate 정보 + 메시지
            HStack(spacing: 12) {
                // Gate 아이콘
                Text(info.icon)
                    .font(.system(size: 28))

                VStack(alignment: .leading, spacing: 2) {
                    // Gate 이름 + 번호
                    HStack(spacing: 6) {
                        Text("Gate \(feedback.gateIndex + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow)
                            .cornerRadius(4)

                        Text(info.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    // 메인 메시지 (고정)
                    Text(feedback.message)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }

                Spacer()

                // 해결됨 표시
                if feedback.isResolved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            // 🆕 진행률 바 (비동기 애니메이션)
            ProgressBarView(
                progress: feedback.displayedProgress,
                isResolved: feedback.isResolved,
                color: info.color
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(feedback.isResolved ? 0.7 : 0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(feedback.isResolved ? Color.green.opacity(0.5) : info.color.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: feedback.isResolved ? .green.opacity(0.3) : .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 진행률 바 (비동기 애니메이션)
struct ProgressBarView: View {
    let progress: CGFloat
    let isResolved: Bool
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 배경
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.15))

                // 진행 바
                RoundedRectangle(cornerRadius: 4)
                    .fill(progressGradient)
                    .frame(width: geometry.size.width * min(progress, 1.0))
            }
        }
        .frame(height: 8)
        .animation(.easeInOut(duration: 0.3), value: progress)
    }

    private var progressGradient: LinearGradient {
        if isResolved {
            return LinearGradient(
                colors: [.green, .green.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        // 진행률에 따른 색상
        let progressColor: Color
        if progress >= 0.8 {
            progressColor = .green
        } else if progress >= 0.5 {
            progressColor = .yellow
        } else if progress >= 0.3 {
            progressColor = .orange
        } else {
            progressColor = color
        }

        return LinearGradient(
            colors: [progressColor, progressColor.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - 🆕 Temporal Lock UI (Circular Ring)
struct CircularGateProgressView: View {
    let progress: Float
    
    var body: some View {
        ZStack {
            // 배경 링
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 6)
            
            // 진행 링 (반시계 방향 CCW)
            // SwiftUI trim은 기본적으로 시계방향이므로, scaleEffect(x:-1)로 반전
            Circle()
                .trim(from: 0.0, to: CGFloat(progress))
                .stroke(
                    progress >= 1.0 ? Color.green : Color.yellow,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(Angle(degrees: -90)) // 12시 방향부터 시작
                .scaleEffect(x: -1, y: 1) // 반시계 방향으로 채우기
                .animation(.linear(duration: 0.05), value: progress)
        }
        .frame(width: 80, height: 80)
        .shadow(color: .black.opacity(0.3), radius: 4)
    }
}

// MARK: - 🆕 SimpleGuide Feedback View (단순화된 가이드)
struct SimpleGuideFeedbackView: View {
    let guide: SimpleGuideResult

    // 피드백 단계별 색상
    private var stageColor: Color {
        switch guide.feedbackStage {
        case .frameEntry:
            return .red
        case .shotType:
            return .orange
        case .position:
            return .purple
        case .zoom:
            return .cyan
        case .pose:
            return .pink
        case .perfect:
            return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 상단: 아이콘 + 메인 메시지
            HStack(spacing: 12) {
                // 가이드 아이콘
                Text(guide.guide.icon)
                    .font(.system(size: 32))

                VStack(alignment: .leading, spacing: 4) {
                    // 🆕 피드백 단계 표시 (샷타입, 위치, 줌, 포즈)
                    Text(guide.feedbackStage.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(stageColor)
                        .cornerRadius(6)

                    // 메인 메시지 (샷타입 단계에서는 샷타입 비교 문구 사용)
                    if guide.feedbackStage == .shotType && !guide.shotTypeMatch {
                        // 샷타입 불일치: 현재/레퍼런스 샷타입 비교
                        VStack(alignment: .leading, spacing: 2) {
                            Text("현재: \(guide.currentShotType)")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                            Text("레퍼런스: \(guide.targetShotType)처럼 맞추세요")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.orange)
                        }

                        // 방향 힌트 (앞으로/뒤로)
                        Text(guide.displayMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    } else {
                        // 다른 단계: 기존 메시지 사용
                        Text(guide.displayMessage)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                }

                Spacer()

                // 완벽 상태 체크마크
                if guide.guide == .perfect {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            // 진행률 바
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 배경
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.15))

                    // 진행 바
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressGradient)
                        .frame(width: geometry.size.width * guide.progress)
                }
            }
            .frame(height: 8)
            .animation(.easeInOut(duration: 0.3), value: guide.progress)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(guide.guide == .perfect ? 0.7 : 0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(stageColor.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: guide.guide == .perfect ? .green.opacity(0.3) : .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    private var progressGradient: LinearGradient {
        let progressColor: Color
        if guide.progress >= 0.9 {
            progressColor = .green
        } else if guide.progress >= 0.6 {
            progressColor = .yellow
        } else if guide.progress >= 0.3 {
            progressColor = .orange
        } else {
            progressColor = stageColor
        }

        return LinearGradient(
            colors: [progressColor, progressColor.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - 🆕 Gate 상태바 (상단 고정)
struct GateStatusBar: View {
    let evaluation: GateEvaluation?
    let simpleGuide: SimpleGuideResult?  // 🆕 SimpleGuide 기반 상태 판단

    // Gate 항목 정의 (순서대로)
    private let gateNames = ["비율", "샷타입", "위치", "줌", "포즈"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<gateNames.count, id: \.self) { index in
                let isPassed = isGatePassed(index: index)

                GateStatusItem(name: gateNames[index], isPassed: isPassed)

                // 구분선 (마지막 제외)
                if index < gateNames.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1, height: 16)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.75))
        )
    }

    /// 🆕 Gate 통과 여부 판단 (SimpleGuide 기반 - 안정적)
    private func isGatePassed(index: Int) -> Bool {
        // 🔥 비율(gate0)은 GateEvaluation에서만 판단 (SimpleGuide에 비율 정보 없음)
        if index == 0 {
            return evaluation?.gate0.passed ?? true  // 비율 정보 없으면 통과로 간주
        }

        // 나머지 게이트는 SimpleGuide 기반으로 안정적으로 판단
        guard let guide = simpleGuide else {
            return false  // 정보 없음
        }

        // SimpleGuide의 feedbackStage로 현재 단계 파악
        // 현재 단계 이전은 통과, 현재 단계는 미통과
        switch guide.feedbackStage {
        case .frameEntry:
            // 프레임 진입 단계: 모두 미통과
            return false
        case .shotType:
            // 샷타입 조정 단계: 비율만 통과 (index 0은 위에서 처리)
            return false
        case .position:
            // 위치 조정 단계: 샷타입 통과
            return index == 1
        case .zoom:
            // 줌 조정 단계: 샷타입 + 위치 통과
            return index <= 2
        case .pose:
            // 포즈 조정 단계: 샷타입 + 위치 + 줌 통과
            return index <= 3
        case .perfect:
            // 완벽: 모두 통과
            return true
        }
    }
}

// MARK: - Gate 상태 아이템 (개별)
struct GateStatusItem: View {
    let name: String
    let isPassed: Bool

    var body: some View {
        HStack(spacing: 4) {
            // 체크 표시
            Image(systemName: isPassed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isPassed ? .green : .white.opacity(0.4))

            // 항목 이름
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isPassed ? .green : .white.opacity(0.6))
        }
        .animation(.easeInOut(duration: 0.2), value: isPassed)
    }
}
