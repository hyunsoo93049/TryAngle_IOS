//
//  DistanceEstimator.swift
//  TryAngleApp
//
//  핀홀 카메라 모델 기반 거리 추정
//  어깨 픽셀 너비 + 초점거리로 피사체까지 거리 계산
//
//  공식: distance = (H × f) / h
//  - H: 실제 어깨 너비 (meters)
//  - f: 35mm 환산 초점거리 (mm)
//  - h: 센서 위 어깨 크기 (mm)
//
//  Created: 2025-01-20
//

import Foundation
import CoreGraphics

// MARK: - Distance Estimator

public struct DistanceEstimator {

    // MARK: - Constants

    /// 35mm 필름 기준 센서 너비 (4:3 비율 보정)
    /// - 35mm 필름: 36mm x 24mm
    /// - 4:3 비율 보정: sqrt((36^2 + 24^2) / (4^2 + 3^2)) * 4 ≈ 34.6mm
    private static let sensorReferenceWidthMM: Float = 34.6

    // MARK: - Keypoint Indices (RTMPose 133 keypoints)

    /// 왼쪽 어깨 인덱스
    public static let leftShoulderIndex: Int = 5

    /// 오른쪽 어깨 인덱스
    public static let rightShoulderIndex: Int = 6

    /// 어깨 감지 최소 신뢰도
    private static let minConfidence: Float = 0.3

    // MARK: - Public API

    /// 핀홀 카메라 모델로 거리 추정
    /// - Parameters:
    ///   - shoulderPixelWidth: 어깨 픽셀 너비 (절대값, 정규화되지 않은 픽셀)
    ///   - imageWidth: 이미지 전체 너비 (pixels)
    ///   - focalLengthMM: 35mm 환산 초점거리 (mm)
    ///   - shoulderWidthM: 실제 어깨 너비 (meters)
    /// - Returns: 추정 거리 (meters), 계산 불가 시 nil
    public static func estimateDistance(
        shoulderPixelWidth: CGFloat,
        imageWidth: CGFloat,
        focalLengthMM: Int,
        shoulderWidthM: Float
    ) -> Float? {
        // 유효성 검사
        guard shoulderPixelWidth > 0,
              imageWidth > 0,
              focalLengthMM > 0,
              shoulderWidthM > 0 else {
            return nil
        }

        // 어깨가 센서에서 차지하는 비율
        let shoulderRatioOnSensor = Float(shoulderPixelWidth / imageWidth)

        // 비율이 너무 작으면 무시 (노이즈)
        guard shoulderRatioOnSensor > 0.01 else {
            return nil
        }

        // 센서 위 어깨 크기 (mm)
        let shoulderOnSensorMM = shoulderRatioOnSensor * sensorReferenceWidthMM

        // 핀홀 공식: distance = (H × f) / h
        // H = 실제 어깨 너비 (m)
        // f = 초점거리 (mm)
        // h = 센서 위 어깨 크기 (mm)
        //
        // 단위 분석:
        // (m × mm) / mm = m ✓
        let distanceM = (shoulderWidthM * Float(focalLengthMM)) / shoulderOnSensorMM

        // 합리적 범위 체크 (0.3m ~ 30m)
        guard distanceM > 0.3 && distanceM < 30 else {
            return nil
        }

        return distanceM
    }

    /// 키포인트 배열에서 어깨 픽셀 너비 추출
    /// - Parameters:
    ///   - keypoints: PoseKeypoint 배열 (index 5 = 왼쪽어깨, index 6 = 오른쪽어깨)
    ///   - imageWidth: 이미지 너비 (정규화 해제용)
    /// - Returns: 어깨 픽셀 너비 (nil if not detected)
    /// - Note: keypoints의 location은 정규화된 좌표(0~1)라고 가정
    public static func extractShoulderPixelWidth(
        from keypoints: [Any],  // PoseKeypoint 배열
        imageWidth: CGFloat
    ) -> CGFloat? {
        // 어깨 인덱스 범위 체크
        guard keypoints.count > rightShoulderIndex else {
            return nil
        }

        // PoseKeypoint 타입으로 캐스팅 시도
        // GateHelpers.swift의 asPoseKeypoints 반환 타입과 호환
        guard let leftShoulder = keypoints[leftShoulderIndex] as? (location: CGPoint, confidence: Float),
              let rightShoulder = keypoints[rightShoulderIndex] as? (location: CGPoint, confidence: Float) else {
            // 다른 구조체 형태 시도 (PoseKeypoint)
            return extractShoulderWidthFromPoseKeypoints(keypoints, imageWidth: imageWidth)
        }

        // 신뢰도 체크
        guard leftShoulder.confidence > minConfidence,
              rightShoulder.confidence > minConfidence else {
            return nil
        }

        // X축만 사용하여 노이즈 감소 (Y축 기울기 무시)
        let normalizedWidth = abs(leftShoulder.location.x - rightShoulder.location.x)

        // 정규화 해제 (0~1 → pixels)
        return normalizedWidth * imageWidth
    }

    /// PoseKeypoint 구조체 배열에서 어깨 너비 추출
    /// - Note: Feedback.swift의 PoseKeypoint 구조체 사용
    private static func extractShoulderWidthFromPoseKeypoints(
        _ keypoints: [Any],
        imageWidth: CGFloat
    ) -> CGFloat? {
        guard keypoints.count > rightShoulderIndex else {
            return nil
        }

        // Mirror를 사용하여 동적으로 프로퍼티 접근
        let leftMirror = Mirror(reflecting: keypoints[leftShoulderIndex])
        let rightMirror = Mirror(reflecting: keypoints[rightShoulderIndex])

        var leftLocation: CGPoint?
        var leftConfidence: Float?
        var rightLocation: CGPoint?
        var rightConfidence: Float?

        for child in leftMirror.children {
            if child.label == "location", let point = child.value as? CGPoint {
                leftLocation = point
            }
            if child.label == "confidence", let conf = child.value as? Float {
                leftConfidence = conf
            }
        }

        for child in rightMirror.children {
            if child.label == "location", let point = child.value as? CGPoint {
                rightLocation = point
            }
            if child.label == "confidence", let conf = child.value as? Float {
                rightConfidence = conf
            }
        }

        guard let leftLoc = leftLocation,
              let rightLoc = rightLocation,
              let leftConf = leftConfidence,
              let rightConf = rightConfidence,
              leftConf > minConfidence,
              rightConf > minConfidence else {
            return nil
        }

        let normalizedWidth = abs(leftLoc.x - rightLoc.x)
        return normalizedWidth * imageWidth
    }

    // MARK: - Convenience

    /// 키포인트 + 줌 배율로 거리 추정 (편의 메서드)
    /// - Parameters:
    ///   - keypoints: PoseKeypoint 배열
    ///   - imageWidth: 이미지 너비 (pixels)
    ///   - zoomFactor: 현재 줌 배율 (0.5, 1.0, 2.0 등)
    ///   - bodyType: 사용자 체형
    /// - Returns: 추정 거리 (meters)
    public static func estimateDistance(
        keypoints: [Any],
        imageWidth: CGFloat,
        zoomFactor: CGFloat,
        bodyType: BodyType
    ) -> Float? {
        guard let shoulderWidth = extractShoulderPixelWidth(from: keypoints, imageWidth: imageWidth) else {
            return nil
        }

        let focalLengthMM = DeviceLensConfig.shared.focalLengthMM(for: zoomFactor)

        return estimateDistance(
            shoulderPixelWidth: shoulderWidth,
            imageWidth: imageWidth,
            focalLengthMM: focalLengthMM,
            shoulderWidthM: bodyType.shoulderWidthM
        )
    }
}
