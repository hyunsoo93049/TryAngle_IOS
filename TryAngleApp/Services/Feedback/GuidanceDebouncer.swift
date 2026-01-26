//
//  GuidanceDebouncer.swift
//  TryAngleApp
//
//  가이드 메시지 디바운싱
//  - 최소 시간 간격 적용 (UI 깜빡임 방지)
//  - 의미있는 변화만 피드백 업데이트
//
//  Created: 2025-01-20
//

import Foundation

// MARK: - Guidance Debouncer

public class GuidanceDebouncer {

    // MARK: - Configuration

    /// 최소 피드백 간격 (초)
    private let minInterval: TimeInterval

    /// 거리 변화 임계값 (비율, 0.25 = 25%)
    private let distanceChangeThreshold: Float

    /// 초점거리 변화 임계값 (mm)
    private let focalChangeThreshold: Int

    // MARK: - State

    /// 마지막 피드백 시간
    private var lastFeedbackTime: Date = .distantPast

    /// 마지막 거리 값 (meters)
    private var lastDistance: Float = 0

    /// 마지막 초점거리 (mm)
    private var lastFocalLength: Int = 0

    /// 마지막 피드백 메시지
    private var lastFeedback: String = ""

    /// 마지막 피드백 카테고리
    private var lastCategory: String = ""

    /// 연속 동일 피드백 횟수
    private var sameMessageCount: Int = 0

    // MARK: - Initialization

    /// 가이드 디바운서 초기화
    /// - Parameters:
    ///   - minInterval: 최소 피드백 간격 (기본값 0.5초)
    ///   - distanceChangeThreshold: 거리 변화 임계값 (기본값 25%)
    ///   - focalChangeThreshold: 초점거리 변화 임계값 (기본값 5mm)
    public init(
        minInterval: TimeInterval = 0.5,
        distanceChangeThreshold: Float = 0.25,
        focalChangeThreshold: Int = 5
    ) {
        self.minInterval = minInterval
        self.distanceChangeThreshold = distanceChangeThreshold
        self.focalChangeThreshold = focalChangeThreshold
    }

    // MARK: - Public API

    /// 피드백 디바운싱 결과
    public struct DebounceResult {
        /// 표시할 피드백 메시지 (nil이면 표시 안 함)
        public let feedback: String?

        /// 업데이트 여부
        public let shouldUpdate: Bool

        /// 이유 (디버그용)
        public let reason: String
    }

    /// 피드백 디바운싱 적용
    /// - Parameters:
    ///   - distance: 현재 추정 거리 (meters)
    ///   - focalLength: 현재 초점거리 (mm)
    ///   - newFeedback: 새로 생성된 피드백 메시지
    ///   - category: 피드백 카테고리 (변경 감지용)
    /// - Returns: 디바운싱 결과
    public func debounce(
        distance: Float,
        focalLength: Int,
        newFeedback: String,
        category: String = ""
    ) -> DebounceResult {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFeedbackTime)

        // 1. 시간 조건 체크
        if elapsed < minInterval {
            return DebounceResult(
                feedback: nil,
                shouldUpdate: false,
                reason: "시간 부족 (\(String(format: "%.2f", elapsed))s < \(minInterval)s)"
            )
        }

        // 2. 카테고리 변경 체크 (카테고리가 바뀌면 즉시 업데이트)
        if !category.isEmpty && category != lastCategory {
            updateState(distance: distance, focalLength: focalLength, feedback: newFeedback, category: category, time: now)
            return DebounceResult(
                feedback: newFeedback,
                shouldUpdate: true,
                reason: "카테고리 변경 (\(lastCategory) → \(category))"
            )
        }

        // 3. 변화량 체크
        let distanceChange = lastDistance > 0.1
            ? abs(distance - lastDistance) / lastDistance
            : 1.0  // 이전 값 없으면 항상 업데이트

        let focalChange = abs(focalLength - lastFocalLength)

        let isSignificantChange = distanceChange > distanceChangeThreshold || focalChange > focalChangeThreshold

        if isSignificantChange {
            // 의미있는 변화 → 새 피드백
            updateState(distance: distance, focalLength: focalLength, feedback: newFeedback, category: category, time: now)
            return DebounceResult(
                feedback: newFeedback,
                shouldUpdate: true,
                reason: "의미있는 변화 (거리:\(String(format: "%.0f", distanceChange * 100))%, 초점:\(focalChange)mm)"
            )
        }

        // 4. 메시지 내용 변경 체크
        if newFeedback != lastFeedback {
            // 값은 비슷하지만 메시지가 다르면 (예: 방향 변경)
            updateState(distance: distance, focalLength: focalLength, feedback: newFeedback, category: category, time: now)
            return DebounceResult(
                feedback: newFeedback,
                shouldUpdate: true,
                reason: "메시지 변경"
            )
        }

        // 5. 변화 없음 - 이전 피드백 유지 (주기적 갱신 허용)
        sameMessageCount += 1

        // 동일 메시지가 5회 이상이고 2초 이상 지났으면 갱신 허용
        if sameMessageCount >= 5 && elapsed > 2.0 {
            lastFeedbackTime = now
            sameMessageCount = 0
            return DebounceResult(
                feedback: lastFeedback,
                shouldUpdate: true,
                reason: "주기적 갱신"
            )
        }

        return DebounceResult(
            feedback: nil,
            shouldUpdate: false,
            reason: "변화 없음 (연속 \(sameMessageCount)회)"
        )
    }

    /// 간단한 디바운싱 (피드백 메시지만 반환)
    /// - Returns: 표시할 피드백 (nil이면 이전 피드백 유지)
    public func debounceSimple(
        distance: Float,
        focalLength: Int,
        newFeedback: String
    ) -> String? {
        return debounce(distance: distance, focalLength: focalLength, newFeedback: newFeedback).feedback
    }

    // MARK: - Control

    /// 디바운서 리셋 (새 레퍼런스 설정 시 호출)
    public func reset() {
        lastFeedbackTime = .distantPast
        lastDistance = 0
        lastFocalLength = 0
        lastFeedback = ""
        lastCategory = ""
        sameMessageCount = 0
    }

    /// 현재 마지막 피드백 가져오기
    public var currentFeedback: String {
        return lastFeedback
    }

    /// 디버그 정보
    public var debugInfo: String {
        let elapsed = Date().timeIntervalSince(lastFeedbackTime)
        return "GuidanceDebouncer: last=\(String(format: "%.1f", elapsed))s ago, dist=\(String(format: "%.2f", lastDistance))m, focal=\(lastFocalLength)mm"
    }

    // MARK: - Private

    private func updateState(
        distance: Float,
        focalLength: Int,
        feedback: String,
        category: String,
        time: Date
    ) {
        lastFeedbackTime = time
        lastDistance = distance
        lastFocalLength = focalLength
        lastFeedback = feedback
        lastCategory = category
        sameMessageCount = 0
    }
}
