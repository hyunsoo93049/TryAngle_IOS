//
//  BodyType.swift
//  TryAngleApp
//
//  사용자 체형 설정 - 어깨너비 기준값 제공
//  거리 추정 시 어깨너비 기본값으로 사용됨
//
//  Created: 2025-01-20
//

import Foundation

// MARK: - Body Type

/// 사용자 체형 설정
/// 거리 추정 시 어깨너비 기준값으로 사용
public enum BodyType: String, CaseIterable, Codable {
    case small   // 마른/작은 체형
    case medium  // 보통 체형
    case large   // 큰 체형

    // MARK: - 어깨너비 (미터)

    /// 체형별 평균 어깨너비 (미터)
    /// - small: 34cm (마른 체형, 여성 평균)
    /// - medium: 40cm (보통 체형, 성인 평균)
    /// - large: 46cm (큰 체형, 남성 평균)
    public var shoulderWidthM: Float {
        switch self {
        case .small:  return 0.34
        case .medium: return 0.40
        case .large:  return 0.46
        }
    }

    /// 어깨너비 (센티미터) - UI 표시용
    public var shoulderWidthCM: Int {
        return Int(shoulderWidthM * 100)
    }

    // MARK: - Display

    /// 한글 표시명
    public var displayName: String {
        switch self {
        case .small:  return "마른 체형"
        case .medium: return "보통 체형"
        case .large:  return "큰 체형"
        }
    }

    /// 짧은 표시명 (UI 칩용)
    public var shortName: String {
        switch self {
        case .small:  return "S"
        case .medium: return "M"
        case .large:  return "L"
        }
    }

    /// 설명 텍스트
    public var description: String {
        switch self {
        case .small:
            return "어깨너비 약 \(shoulderWidthCM)cm (마른 체형)"
        case .medium:
            return "어깨너비 약 \(shoulderWidthCM)cm (보통 체형)"
        case .large:
            return "어깨너비 약 \(shoulderWidthCM)cm (큰 체형)"
        }
    }

    // MARK: - Icon

    /// 아이콘 (SF Symbol 또는 이모지)
    public var icon: String {
        switch self {
        case .small:  return "figure.stand"
        case .medium: return "figure.stand"
        case .large:  return "figure.stand"
        }
    }
}
