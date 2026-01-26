import Foundation
import Vision
import CoreGraphics

// MARK: - 카메라 앵글 타입
enum CameraAngle: String {
    case veryLow = "very_low"       // 초저각 (극단적 로우앵글)
    case low = "low"                // 로우앵글 (아래에서 위로)
    case eyeLevel = "eye_level"     // 아이레벨 (정면)
    case high = "high"              // 하이앵글 (위에서 아래로)
    case veryHigh = "very_high"     // 초고각 (극단적 하이앵글)
    case dutch = "dutch"            // 더치 틸트 (기울어짐)
    case unknown = "unknown"        // 알 수 없음

    var description: String {
        switch self {
        case .veryLow:
            return "초저각 (극로우앵글)"
        case .low:
            return "로우앵글"
        case .eyeLevel:
            return "아이레벨 (정면)"
        case .high:
            return "하이앵글"
        case .veryHigh:
            return "초고각 (극하이앵글)"
        case .dutch:
            return "더치 틸트"
        case .unknown:
            return "알 수 없음"
        }
    }
}

// MARK: - 카메라 앵글 감지기
class CameraAngleDetector {

    /// 3가지 방법 융합으로 카메라 앵글 감지
    /// - Parameters:
    ///   - faceRect: 얼굴 영역 (정규화 좌표)
    ///   - facePitch: 얼굴 pitch 각도 (라디안)
    ///   - faceObservation: Vision 얼굴 관찰 결과 (랜드마크 포함)
    /// - Returns: 감지된 카메라 앵글
    func detectCameraAngle(
        faceRect: CGRect?,
        facePitch: Float?,
        faceObservation: VNFaceObservation?
    ) -> CameraAngle {

        var scores: [CameraAngle: Double] = [:]

        // Method 1: 얼굴 위치 기반 (가장 기본)
        if let faceRect = faceRect {
            let method1Result = detectByFacePosition(faceRect: faceRect)
            scores[method1Result] = (scores[method1Result] ?? 0) + 1.0
        }

        // Method 2: 얼굴 랜드마크 Y 비율 (더 정확)
        if let landmarks = faceObservation?.landmarks {
            let method2Result = detectByLandmarkRatio(landmarks: landmarks)
            scores[method2Result] = (scores[method2Result] ?? 0) + 2.0  // 가중치 2배
        }

        // Method 3: Pitch 각도 기반 (가장 정확하지만 항상 사용 가능한 것은 아님)
        if let facePitch = facePitch {
            let method3Result = detectByPitchAngle(pitchRadians: facePitch)
            scores[method3Result] = (scores[method3Result] ?? 0) + 1.5  // 가중치 1.5배
        }

        // 점수 기반 최종 판정
        let sortedResults = scores.sorted { $0.value > $1.value }
        return sortedResults.first?.key ?? .unknown
    }

    /// 간단한 앵글 비교 (레퍼런스 vs 현재)
    /// - Parameters:
    ///   - referenceAngle: 레퍼런스 앵글
    ///   - currentAngle: 현재 앵글
    /// - Returns: 일치 여부
    func compareAngles(reference: CameraAngle, current: CameraAngle) -> Bool {
        return reference == current
    }

    /// 앵글 차이를 피드백 메시지로 변환
    /// 🆕 더 구체적인 안내: 앞으로/뒤로 기울이기 구분
    /// - Parameters:
    ///   - referenceAngle: 레퍼런스 앵글
    ///   - currentAngle: 현재 앵글
    /// - Returns: 피드백 메시지
    func generateAngleFeedback(reference: CameraAngle, current: CameraAngle) -> String? {
        if reference == current {
            return nil  // 일치하면 피드백 없음
        }

        // current가 reference보다 높은지 낮은지 비교
        let refLevel = angleLevel(reference)
        let curLevel = angleLevel(current)

        // 🆕 레벨 차이로 직관적 표현 결정
        let diff = abs(curLevel - refLevel)
        let intensity = diff >= 2 ? "많이" : "조금"

        if curLevel > refLevel {
            // 현재가 더 높음 (하이앵글) → 로우앵글로 만들어야 함
            // = 카메라를 낮추거나, 카메라 상단을 뒤로 기울여야 함
            switch reference {
            case .veryLow, .low:
                // 극단적인 로우앵글을 원함
                return "카메라를 \(intensity) 낮추고 위를 향하게 기울여주세요"
            case .eyeLevel:
                // 아이레벨로 맞추기
                return "카메라를 \(intensity) 눈높이로 낮춰주세요"
            default:
                return "카메라를 \(intensity) 낮춰주세요"
            }
        } else if curLevel < refLevel {
            // 현재가 더 낮음 (로우앵글) → 하이앵글로 만들어야 함
            // = 카메라를 높이거나, 카메라 상단을 앞으로 기울여야 함
            switch reference {
            case .veryHigh, .high:
                // 극단적인 하이앵글을 원함
                return "카메라를 \(intensity) 높이고 아래를 향하게 기울여주세요"
            case .eyeLevel:
                // 아이레벨로 맞추기
                return "카메라를 \(intensity) 눈높이로 올려주세요"
            default:
                return "카메라를 \(intensity) 올려주세요"
            }
        }

        // 더치 틸트 (좌우 기울기)
        if reference == .dutch && current != .dutch {
            return "카메라를 좌우로 기울여주세요 (더치 앵글)"
        }

        return nil
    }

    /// 앵글의 높이 레벨 (낮은 순서)
    private func angleLevel(_ angle: CameraAngle) -> Int {
        switch angle {
        case .veryLow: return 1
        case .low: return 2
        case .eyeLevel: return 3
        case .high: return 4
        case .veryHigh: return 5
        case .dutch, .unknown: return 3  // 중간으로 간주
        }
    }

    // MARK: - Detection Methods

    /// Method 1: 얼굴 위치 기반 (가장 간단)
    private func detectByFacePosition(faceRect: CGRect) -> CameraAngle {
        let faceY = faceRect.midY

        // Vision의 좌표계: (0, 0)은 왼쪽 하단, (1, 1)은 오른쪽 상단
        // faceY가 높을수록 (1에 가까울수록) 얼굴이 화면 위쪽에 위치
        // → 카메라가 낮은 것 (로우앵글)

        if faceY > 0.8 {
            return .veryLow  // 얼굴이 매우 위쪽 → 초저각
        } else if faceY > 0.6 {
            return .low      // 얼굴이 위쪽 → 로우앵글
        } else if faceY >= 0.4 {
            return .eyeLevel // 얼굴이 중앙 → 아이레벨
        } else if faceY >= 0.2 {
            return .high     // 얼굴이 아래쪽 → 하이앵글
        } else {
            return .veryHigh // 얼굴이 매우 아래쪽 → 초고각
        }
    }

    /// Method 2: 얼굴 랜드마크 Y 비율 (더 정확)
    /// 로우앵글: 턱/입이 눈보다 더 위쪽에 보임 (비율 증가)
    /// 하이앵글: 이마/눈이 입보다 더 위쪽에 보임 (비율 감소)
    private func detectByLandmarkRatio(landmarks: VNFaceLandmarks2D) -> CameraAngle {
        // 얼굴 랜드마크 추출
        guard let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye,
              let _ = landmarks.nose,
              let outerLips = landmarks.outerLips else {
            return .unknown
        }

        // 평균 Y 좌표 계산
        let eyeY = (averageY(leftEye.normalizedPoints) + averageY(rightEye.normalizedPoints)) / 2.0
        // let noseY = averageY(nose.normalizedPoints)
        let mouthY = averageY(outerLips.normalizedPoints)

        // Y 비율 계산
        // Vision 좌표계에서 Y가 높을수록 위쪽
        // let eyeToNoseRatio = (noseY - eyeY)  // 양수: 코가 눈보다 위 (정상은 아래)
        let eyeToMouthRatio = (mouthY - eyeY)  // 양수: 입이 눈보다 위 (정상은 아래)

        // 로우앵글: 얼굴 하부(턱/입)가 더 위로 올라감 → 비율 증가
        // 하이앵글: 얼굴 상부(이마/눈)가 더 위로 올라감 → 비율 감소

        if eyeToMouthRatio > 0.15 {  // 입이 눈보다 훨씬 위 (비정상)
            return .veryLow
        } else if eyeToMouthRatio > 0.08 {
            return .low
        } else if eyeToMouthRatio > -0.08 {
            return .eyeLevel  // 정상 범위
        } else if eyeToMouthRatio > -0.15 {
            return .high
        } else {
            return .veryHigh
        }
    }

    /// Method 3: Face Pitch 각도 기반 (가장 정확)
    /// Pitch: 얼굴이 위/아래를 보는 각도
    /// - 양수(+): 얼굴이 위를 봄 → 로우앵글 (카메라가 아래에서 촬영)
    /// - 음수(-): 얼굴이 아래를 봄 → 하이앵글 (카메라가 위에서 촬영)
    private func detectByPitchAngle(pitchRadians: Float) -> CameraAngle {
        let pitchDegrees = pitchRadians * 180 / .pi

        if pitchDegrees > 20 {
            return .veryLow   // 얼굴이 많이 위를 봄
        } else if pitchDegrees > 10 {
            return .low       // 얼굴이 약간 위를 봄
        } else if pitchDegrees >= -10 {
            return .eyeLevel  // 얼굴이 정면
        } else if pitchDegrees >= -20 {
            return .high      // 얼굴이 약간 아래를 봄
        } else {
            return .veryHigh  // 얼굴이 많이 아래를 봄
        }
    }

    /// 랜드마크 포인트들의 평균 Y 좌표 계산
    private func averageY(_ points: [CGPoint]) -> CGFloat {
        guard !points.isEmpty else { return 0 }
        let sum = points.reduce(0.0) { $0 + $1.y }
        return sum / CGFloat(points.count)
    }

    /// 더치 틸트 (기울기) 감지
    /// - Parameters:
    ///   - faceObservation: 얼굴 관찰 결과
    ///   - isFrontCamera: 전면 카메라 여부
    /// - Returns: 기울기 각도 (도)
    func detectDutchTilt(faceObservation: VNFaceObservation?, isFrontCamera: Bool = false) -> Float? {
        guard let landmarks = faceObservation?.landmarks,
              let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye else {
            return nil
        }

        // 양 눈의 중심점 계산
        let leftEyeCenter = centroid(leftEye.normalizedPoints)
        let rightEyeCenter = centroid(rightEye.normalizedPoints)

        // 기울기 각도 계산
        let deltaX = rightEyeCenter.x - leftEyeCenter.x
        let deltaY = rightEyeCenter.y - leftEyeCenter.y

        let angleRadians = atan2(deltaY, deltaX)
        var angleDegrees = Float(angleRadians * 180 / .pi)

        // 🔥 전면 카메라는 좌우 반전 (미러 이미지)
        if isFrontCamera {
            angleDegrees = -angleDegrees
        }

        return angleDegrees
    }

    /// 포인트들의 중심점 계산
    private func centroid(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sumX = points.reduce(0.0) { $0 + $1.x }
        let sumY = points.reduce(0.0) { $0 + $1.y }
        return CGPoint(x: sumX / CGFloat(points.count), y: sumY / CGFloat(points.count))
    }
}
