import SwiftUI

// MARK: - 상세 분석 화면 (Image #3)

struct DetailedAnalysisView: View {
    let analysisResult: PhotoAnalysisResult
    let onReanalyze: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 네비게이션 헤더
            navigationHeader

            ScrollView {
                VStack(spacing: 20) {
                    // 썸네일 + 샷 타입
                    shotTypeSection

                    // 5가지 상세 피드백 카드
                    feedbackCardsSection

                    // 종합 점수
                    scoreSection

                    // 다시 평가받기 버튼
                    reanalyzeButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 네비게이션 헤더
    private var navigationHeader: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
            }

            Spacer()

            Text("피드백")
                .font(.system(size: 18, weight: .semibold))

            Spacer()

            // 빈 공간 (대칭용)
            Color.clear.frame(width: 24, height: 24)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
    }

    // MARK: - 샷 타입 섹션
    private var shotTypeSection: some View {
        VStack(spacing: 16) {
            // 썸네일
            Image(uiImage: analysisResult.capturedImage)
                .resizable()
                .scaledToFill()
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)

            // 샷 타입 뱃지
            VStack(spacing: 8) {
                Text(analysisResult.shotType)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color(.systemGray))
                    )

                Text(analysisResult.shotDescription)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 피드백 카드 섹션
    private var feedbackCardsSection: some View {
        VStack(spacing: 12) {
            // 상단 2개
            HStack(spacing: 12) {
                if let pose = analysisResult.categories.first(where: { $0.type == .pose }) {
                    FeedbackCard(category: pose)
                }
                if let composition = analysisResult.categories.first(where: { $0.type == .composition }) {
                    FeedbackCard(category: composition)
                }
            }

            // 중간 2개
            HStack(spacing: 12) {
                if let viewpoint = analysisResult.categories.first(where: { $0.type == .viewpoint }) {
                    FeedbackCard(category: viewpoint)
                }
                if let color = analysisResult.categories.first(where: { $0.type == .color }) {
                    FeedbackCard(category: color)
                }
            }

            // 하단 1개 (감성 - 전체 너비)
            if let mood = analysisResult.categories.first(where: { $0.type == .mood }) {
                FeedbackCardWide(category: mood)
            }
        }
    }

    // MARK: - 점수 섹션
    private var scoreSection: some View {
        HStack(spacing: 12) {
            // 점수 카드
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("🏆")
                        .font(.system(size: 16))
                    Text("Score")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Text(String(format: "%.1f", analysisResult.overallScore))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // 요약 텍스트 카드
            VStack(alignment: .leading, spacing: 4) {
                Text(analysisResult.summaryText)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - 다시 평가받기 버튼
    private var reanalyzeButton: some View {
        Button(action: onReanalyze) {
            Text("다시 평가받기")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 26)
                        .fill(Color.pink)
                )
        }
        .padding(.top, 8)
    }
}

// MARK: - 피드백 카드 (작은 사이즈)

struct FeedbackCard: View {
    let category: AnalysisCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 이모지 + 타이틀
            HStack(spacing: 4) {
                Text(category.emoji)
                    .font(.system(size: 14))
                Text(category.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }

            // 피드백 텍스트
            Text(category.feedback)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(category.isMatched ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
    }
}

// MARK: - 피드백 카드 (넓은 사이즈 - 감성용)

struct FeedbackCardWide: View {
    let category: AnalysisCategory

    var body: some View {
        VStack(spacing: 8) {
            // 이모지 + 타이틀
            HStack(spacing: 4) {
                Text(category.emoji)
                    .font(.system(size: 14))
                Text(category.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }

            // 피드백 텍스트
            Text(category.feedback)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(category.isMatched ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

struct DetailedAnalysisView_Previews: PreviewProvider {
    static var previews: some View {
        DetailedAnalysisView(
            analysisResult: PhotoAnalysisResult(
                capturedImage: UIImage(systemName: "photo")!,
                referenceImage: nil,
                overallScore: 8.3,
                categories: [
                    AnalysisCategory(type: .pose, score: 0.9, isMatched: true, feedback: "포즈가 레퍼런스와 유사합니다!"),
                    AnalysisCategory(type: .composition, score: 0.7, isMatched: false, feedback: "인물이 오른쪽으로 이동 필요"),
                    AnalysisCategory(type: .viewpoint, score: 0.85, isMatched: true, feedback: "사진과 같은 아이레벨 뷰입니다!"),
                    AnalysisCategory(type: .color, score: 0.6, isMatched: false, feedback: "색감이 조금 더 따뜻해야 합니다!"),
                    AnalysisCategory(type: .mood, score: 0.8, isMatched: true, feedback: "레퍼런스와 마찬가지로 낭만적이고 몽환적인 분위기입니다.")
                ],
                shotType: "야경 측면샷",
                shotDescription: "화면 오른쪽을 쳐다보는 포즈의 클로즈업 야경샷",
                summaryText: "전체적으로 밸런스가 잘 잡힌 야경 배경 포즈샷입니다!"
            ),
            onReanalyze: {},
            onDismiss: {}
        )
    }
}
