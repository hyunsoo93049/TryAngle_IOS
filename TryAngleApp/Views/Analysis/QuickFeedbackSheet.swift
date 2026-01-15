import SwiftUI

// MARK: - 빠른 피드백 시트 (Image #2)

struct QuickFeedbackSheet: View {
    let analysisResult: PhotoAnalysisResult
    let onDetailTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 상단 핸들
            handleBar

            // 스크롤 컨텐츠
            ScrollView {
                VStack(spacing: 24) {
                    // 헤더 (닫기 버튼, 정보 버튼)
                    headerBar

                    // 피드백 제목 + 점수
                    feedbackHeader

                    // 촬영 이미지
                    capturedImageView

                    // 세부 평가 바
                    evaluationBars

                    // 자세히 분석하기 버튼
                    detailButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - 핸들 바
    private var handleBar: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(Color(.systemGray4))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 8)
    }

    // MARK: - 헤더 바
    private var headerBar: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(.systemGray6)))
            }

            Spacer()

            Button(action: {
                // 정보 버튼 액션
            }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(.systemGray6)))
            }
        }
    }

    // MARK: - 피드백 헤더 (제목 + 점수)
    private var feedbackHeader: some View {
        VStack(spacing: 8) {
            Text("피드백")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            // 점수 뱃지
            HStack(spacing: 4) {
                Text(String(format: "%.1f", analysisResult.overallScore))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text("/ 10")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(scoreColor(analysisResult.overallScore / 10.0))
            )
        }
    }

    // MARK: - 촬영 이미지
    private var capturedImageView: some View {
        Image(uiImage: analysisResult.capturedImage)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 400)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
    }

    // MARK: - 세부 평가 바
    private var evaluationBars: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("세부 평가")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            VStack(spacing: 12) {
                ForEach(analysisResult.quickFeedback, id: \.name) { item in
                    EvaluationBarRow(item: item)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
        }
    }

    // MARK: - 자세히 분석하기 버튼
    private var detailButton: some View {
        Button(action: onDetailTap) {
            Text("자세히 분석하기")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 26)
                        .fill(Color.pink)
                )
        }
    }

    // MARK: - 점수 색상
    private func scoreColor(_ score: Double) -> Color {
        if score >= 0.8 {
            return .green
        } else if score >= 0.6 {
            return .blue
        } else if score >= 0.4 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - 평가 바 행

struct EvaluationBarRow: View {
    let item: QuickFeedbackItem

    var body: some View {
        HStack(spacing: 12) {
            // 카테고리 이름
            Text("\(item.name) (\(item.nameEn))")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 120, alignment: .leading)

            // 프로그레스 바
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 배경 바
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray4))
                        .frame(height: 8)

                    // 채워진 바
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geometry.size.width * item.score, height: 8)
                }
            }
            .frame(height: 8)
        }
    }

    private var barColor: Color {
        switch item.color {
        case .green: return .green
        case .blue: return .blue
        case .orange: return .orange
        case .red: return .red
        case .purple: return .purple
        }
    }
}

// MARK: - Preview

struct QuickFeedbackSheet_Previews: PreviewProvider {
    static var previews: some View {
        QuickFeedbackSheet(
            analysisResult: PhotoAnalysisResult(
                capturedImage: UIImage(systemName: "photo")!,
                referenceImage: nil,
                overallScore: 8.7,
                categories: [
                    AnalysisCategory(type: .composition, score: 0.85, isMatched: true, feedback: "구도가 잘 맞았습니다!"),
                    AnalysisCategory(type: .lighting, score: 0.7, isMatched: false, feedback: "조명이 조금 어둡습니다"),
                    AnalysisCategory(type: .focus, score: 0.6, isMatched: false, feedback: "초점이 약간 흐립니다")
                ],
                shotType: "야경 측면샷",
                shotDescription: "화면 오른쪽을 쳐다보는 포즈의 클로즈업 야경샷",
                summaryText: "전체적으로 밸런스가 잘 잡힌 야경 배경 포즈샷입니다!"
            ),
            onDetailTap: {},
            onDismiss: {}
        )
    }
}
