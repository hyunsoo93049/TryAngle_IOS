import Foundation
import UIKit

// MARK: - 사진 분석 결과 모델

struct PhotoAnalysisResult {
    let capturedImage: UIImage
    let referenceImage: UIImage?
    let overallScore: Double  // 0.0 ~ 10.0
    let categories: [AnalysisCategory]
    let shotType: String  // "야경 측면샷", "클로즈업" 등
    let shotDescription: String  // 샷 설명
    let summaryText: String  // 종합 평가 문구

    // 빠른 피드백용 (3가지)
    var quickFeedback: [QuickFeedbackItem] {
        return [
            QuickFeedbackItem(
                name: "구도",
                nameEn: "Composition",
                score: categories.first { $0.type == .composition }?.score ?? 0,
                color: .green
            ),
            QuickFeedbackItem(
                name: "조명",
                nameEn: "Lighting",
                score: categories.first { $0.type == .lighting }?.score ?? 0,
                color: .blue
            ),
            QuickFeedbackItem(
                name: "초점",
                nameEn: "Focus",
                score: categories.first { $0.type == .focus }?.score ?? 0,
                color: .orange
            )
        ]
    }
}

// MARK: - 빠른 피드백 아이템

struct QuickFeedbackItem {
    let name: String
    let nameEn: String
    let score: Double  // 0.0 ~ 1.0
    let color: FeedbackColor

    enum FeedbackColor {
        case green, blue, orange, red, purple

        var uiColor: UIColor {
            switch self {
            case .green: return .systemGreen
            case .blue: return .systemBlue
            case .orange: return .systemOrange
            case .red: return .systemRed
            case .purple: return .systemPurple
            }
        }
    }
}

// MARK: - 상세 분석 카테고리

struct AnalysisCategory: Identifiable {
    let id = UUID()
    let type: CategoryType
    let score: Double  // 0.0 ~ 1.0
    let isMatched: Bool  // 레퍼런스와 일치 여부
    let feedback: String  // 피드백 문구

    var emoji: String {
        type.emoji
    }

    var name: String {
        type.name
    }

    enum CategoryType: String, CaseIterable {
        case pose       // 포즈
        case composition // 구도
        case viewpoint  // 시점
        case color      // 색감
        case mood       // 감성
        case lighting   // 조명 (빠른 피드백용)
        case focus      // 초점 (빠른 피드백용)

        var name: String {
            switch self {
            case .pose: return "포즈"
            case .composition: return "구도"
            case .viewpoint: return "시점"
            case .color: return "색감"
            case .mood: return "감성"
            case .lighting: return "조명"
            case .focus: return "초점"
            }
        }

        var emoji: String {
            switch self {
            case .pose: return "🌿"
            case .composition: return "📸"
            case .viewpoint: return "🌿"
            case .color: return "🎨"
            case .mood: return "✨"
            case .lighting: return "💡"
            case .focus: return "🎯"
            }
        }
    }
}

// MARK: - 분석 상태

enum PhotoAnalysisState {
    case idle
    case analyzing
    case completed(PhotoAnalysisResult)
    case failed(String)
}
