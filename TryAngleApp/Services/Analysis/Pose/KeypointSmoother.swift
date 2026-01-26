//
//  KeypointSmoother.swift
//  TryAngleApp
//
//  EMA(지수이동평균) 기반 키포인트 스무딩
//  프레임 간 키포인트 떨림을 줄여 안정적인 거리 추정 지원
//
//  알고리즘: smoothed = previous × (1-α) + current × α
//  α = 0.3 (새 값 30%, 이전 값 70%)
//
//  Created: 2025-01-20
//

import Foundation
import CoreGraphics

// MARK: - Keypoint Smoother

public class KeypointSmoother {

    // MARK: - Configuration

    /// EMA 스무딩 계수
    /// - 0.3 = 새 값 30%, 이전 값 70%
    /// - 값이 작을수록 더 부드러움 (지연 증가)
    /// - 값이 클수록 더 반응적 (떨림 증가)
    private let alpha: CGFloat

    /// 신뢰도 기반 가중치 사용 여부
    private let useConfidenceWeighting: Bool

    // MARK: - State

    /// 이전 프레임 키포인트 위치 (배열 인덱스 기반)
    private var previousLocations: [CGPoint] = []

    /// 이전 프레임 신뢰도
    private var previousConfidences: [Float] = []

    /// 스무딩 적용 횟수 (워밍업 체크용)
    private var frameCount: Int = 0

    // MARK: - Initialization

    /// 키포인트 스무더 초기화
    /// - Parameters:
    ///   - alpha: EMA 계수 (기본값 0.3)
    ///   - useConfidenceWeighting: 신뢰도 기반 가중치 사용 여부 (기본값 true)
    public init(alpha: CGFloat = 0.3, useConfidenceWeighting: Bool = true) {
        self.alpha = max(0.1, min(1.0, alpha))  // 0.1 ~ 1.0 범위로 제한
        self.useConfidenceWeighting = useConfidenceWeighting
    }

    // MARK: - Public API

    /// CGPoint 배열 스무딩
    /// - Parameters:
    ///   - locations: 현재 프레임 키포인트 위치 배열
    ///   - confidences: 현재 프레임 신뢰도 배열 (optional)
    /// - Returns: 스무딩된 키포인트 위치 배열
    public func smooth(
        locations: [CGPoint],
        confidences: [Float]? = nil
    ) -> [CGPoint] {
        frameCount += 1

        // 첫 프레임이면 초기화 후 그대로 반환
        if previousLocations.isEmpty {
            previousLocations = locations
            previousConfidences = confidences ?? Array(repeating: 1.0, count: locations.count)
            return locations
        }

        // 크기 불일치 시 리셋
        if previousLocations.count != locations.count {
            previousLocations = locations
            previousConfidences = confidences ?? Array(repeating: 1.0, count: locations.count)
            return locations
        }

        let confs = confidences ?? Array(repeating: 1.0, count: locations.count)
        var smoothedLocations: [CGPoint] = []

        for (index, newLoc) in locations.enumerated() {
            let prevLoc = previousLocations[index]
            let newConf = confs[index]
            let prevConf = previousConfidences[index]

            // 스무딩 계수 계산 (신뢰도 기반 가중치 적용)
            let effectiveAlpha: CGFloat
            if useConfidenceWeighting {
                // 신뢰도가 높을수록 새 값에 더 가중치
                // 신뢰도가 낮으면 이전 값 유지
                let confRatio = CGFloat(newConf) / max(CGFloat(prevConf), 0.1)
                effectiveAlpha = alpha * min(confRatio, 1.5)  // 최대 1.5배까지
            } else {
                effectiveAlpha = alpha
            }

            // EMA: smoothed = prev × (1-α) + new × α
            let smoothedX = prevLoc.x * (1 - effectiveAlpha) + newLoc.x * effectiveAlpha
            let smoothedY = prevLoc.y * (1 - effectiveAlpha) + newLoc.y * effectiveAlpha

            let smoothedPoint = CGPoint(x: smoothedX, y: smoothedY)
            smoothedLocations.append(smoothedPoint)

            // 상태 업데이트
            previousLocations[index] = smoothedPoint
        }

        previousConfidences = confs
        return smoothedLocations
    }

    /// 특정 인덱스의 키포인트만 스무딩
    /// - Parameters:
    ///   - index: 키포인트 인덱스
    ///   - location: 현재 위치
    ///   - confidence: 신뢰도
    /// - Returns: 스무딩된 위치
    public func smoothSingle(
        index: Int,
        location: CGPoint,
        confidence: Float = 1.0
    ) -> CGPoint {
        // 인덱스 범위 확장
        while previousLocations.count <= index {
            previousLocations.append(location)
            previousConfidences.append(confidence)
        }

        let prevLoc = previousLocations[index]
        let prevConf = previousConfidences[index]

        // 신뢰도 기반 알파
        let effectiveAlpha: CGFloat
        if useConfidenceWeighting {
            let confRatio = CGFloat(confidence) / max(CGFloat(prevConf), 0.1)
            effectiveAlpha = alpha * min(confRatio, 1.5)
        } else {
            effectiveAlpha = alpha
        }

        // EMA
        let smoothedX = prevLoc.x * (1 - effectiveAlpha) + location.x * effectiveAlpha
        let smoothedY = prevLoc.y * (1 - effectiveAlpha) + location.y * effectiveAlpha
        let smoothedPoint = CGPoint(x: smoothedX, y: smoothedY)

        // 상태 업데이트
        previousLocations[index] = smoothedPoint
        previousConfidences[index] = confidence

        return smoothedPoint
    }

    /// 어깨 키포인트만 스무딩 (거리 추정용 최적화)
    /// - Parameters:
    ///   - leftShoulder: 왼쪽 어깨 (index 5)
    ///   - rightShoulder: 오른쪽 어깨 (index 6)
    ///   - leftConf: 왼쪽 어깨 신뢰도
    ///   - rightConf: 오른쪽 어깨 신뢰도
    /// - Returns: (스무딩된 왼쪽 어깨, 스무딩된 오른쪽 어깨)
    public func smoothShoulders(
        leftShoulder: CGPoint,
        rightShoulder: CGPoint,
        leftConf: Float = 1.0,
        rightConf: Float = 1.0
    ) -> (left: CGPoint, right: CGPoint) {
        let smoothedLeft = smoothSingle(index: 5, location: leftShoulder, confidence: leftConf)
        let smoothedRight = smoothSingle(index: 6, location: rightShoulder, confidence: rightConf)
        return (smoothedLeft, smoothedRight)
    }

    // MARK: - Control

    /// 스무더 리셋 (새 레퍼런스 설정 시 호출)
    public func reset() {
        previousLocations.removeAll()
        previousConfidences.removeAll()
        frameCount = 0
    }

    /// 워밍업 완료 여부 (최소 3프레임 이상 처리)
    public var isWarmedUp: Bool {
        return frameCount >= 3
    }

    /// 현재 상태 정보 (디버그용)
    public var debugInfo: String {
        return "KeypointSmoother: frames=\(frameCount), points=\(previousLocations.count), alpha=\(alpha)"
    }
}
