import Foundation
import Vision
import CoreGraphics

// MARK: - 포즈 타입
enum PoseType {
    case fullBody        // 전신 (머리 ~ 발목)
    case upperBody       // 상반신 (머리 ~ 골반)
    case portrait        // 흉상 (머리 ~ 어깨)
    case unknown         // 감지 실패

    var description: String {
        switch self {
        case .fullBody:
            return "전신"
        case .upperBody:
            return "상반신"
        case .portrait:
            return "흉상"
        case .unknown:
            return "알 수 없음"
        }
    }
}

// MARK: - 키포인트 그룹 (RTMPose WholeBody 133개)
enum KeypointGroup: String {
    case head           // 머리 (코, 눈, 귀) - 0~4
    case shoulders      // 어깨 - 5, 6
    case arms           // 팔 (팔꿈치, 손목) - 7~10
    case torso          // 몸통 (골반) - 11, 12
    case legs           // 다리 (무릎, 발목) - 13~16
    case feet           // 🆕 발 (발가락) - 17~22
    case face           // 🆕 얼굴 랜드마크 - 23~90
    case leftHand       // 🆕 왼손 - 91~111
    case rightHand      // 🆕 오른손 - 112~132

    var keypointIndices: [Int] {
        switch self {
        case .head:
            return [0, 1, 2, 3, 4]  // 코, 눈, 귀
        case .shoulders:
            return [5, 6]           // 어깨
        case .arms:
            return [7, 8, 9, 10]    // 팔꿈치, 손목
        case .torso:
            return [11, 12]         // 골반
        case .legs:
            return [13, 14, 15, 16] // 무릎, 발목
        case .feet:
            return Array(17...22)   // 🆕 발가락 (6개)
        case .face:
            return Array(23...90)   // 🆕 얼굴 랜드마크 (68개)
        case .leftHand:
            return Array(91...111)  // 🆕 왼손 (21개)
        case .rightHand:
            return Array(112...132) // 🆕 오른손 (21개)
        }
    }

    /// 그룹 이름 (한국어)
    var displayName: String {
        switch self {
        case .head: return "머리"
        case .shoulders: return "어깨"
        case .arms: return "팔"
        case .torso: return "몸통"
        case .legs: return "다리"
        case .feet: return "발"
        case .face: return "얼굴"
        case .leftHand: return "왼손"
        case .rightHand: return "오른손"
        }
    }
}

// MARK: - 포즈 비교 결과
struct PoseComparisonResult {
    let poseType: PoseType                  // 감지된 포즈 타입
    let visibleGroups: [KeypointGroup]      // 보이는 신체 부위
    let missingGroups: [KeypointGroup]      // 안 보이는 신체 부위
    let comparableKeypoints: [Int]          // 비교 가능한 키포인트 인덱스
    let angleDifferences: [String: Float]   // 각 부위별 각도 차이 (부호 있음: + = 올려야함, - = 내려야함)
    let angleDirections: [String: String]   // 🆕 각 부위별 방향 설명 ("올리세요", "내리세요" 등)
    let overallAccuracy: Double             // 전체 정확도 (0~1)
}

// MARK: - 적응형 포즈 비교기 (RTMPose WholeBody 133개 키포인트 지원)
class AdaptivePoseComparator {

    // 🆕 유연한 신뢰도 임계값 (Phase 2)
    private let highConfidenceThreshold: Float = 0.5    // 확실한 키포인트
    private let mediumConfidenceThreshold: Float = 0.3  // 중간 신뢰도
    private let lowConfidenceThreshold: Float = 0.1     // 최소 신뢰도 (잘림 감지용)

    // 부위별 기본 임계값
    private let confidenceThreshold: Float = 0.5        // body 기본값
    private let handConfidenceThreshold: Float = 0.3    // 손 키포인트
    private let faceConfidenceThreshold: Float = 0.4    // 얼굴 키포인트

    // 🆕 프레임 경계 임계값 (잘림 감지용)
    private let frameEdgeThreshold: CGFloat = 0.05      // 프레임 가장자리 5%

    // MARK: - RTMPose WholeBody 133개 키포인트 정의

    /// Body 키포인트 (0-16, 17개) - COCO 포맷
    private let bodyKeypointNames: [String] = [
        "nose",           // 0
        "leftEye",        // 1
        "rightEye",       // 2
        "leftEar",        // 3
        "rightEar",       // 4
        "leftShoulder",   // 5
        "rightShoulder",  // 6
        "leftElbow",      // 7
        "rightElbow",     // 8
        "leftWrist",      // 9
        "rightWrist",     // 10
        "leftHip",        // 11
        "rightHip",       // 12
        "leftKnee",       // 13
        "rightKnee",      // 14
        "leftAnkle",      // 15
        "rightAnkle"      // 16
    ]

    /// Feet 키포인트 (17-22, 6개)
    private let feetKeypointNames: [String] = [
        "leftBigToe",     // 17
        "leftSmallToe",   // 18
        "leftHeel",       // 19
        "rightBigToe",    // 20
        "rightSmallToe",  // 21
        "rightHeel"       // 22
    ]

    /// Face 키포인트 (23-90, 68개) - 얼굴 윤곽, 눈썹, 코, 눈, 입
    /// 23-39: 얼굴 윤곽 (17개)
    /// 40-49: 왼쪽 눈썹 (5개) + 오른쪽 눈썹 (5개)
    /// 50-58: 코 (9개)
    /// 59-70: 왼쪽 눈 (6개) + 오른쪽 눈 (6개)
    /// 71-90: 외부 입술 (12개) + 내부 입술 (8개)

    /// Left Hand 키포인트 (91-111, 21개)
    /// 91: 손목
    /// 92-95: 엄지 (4개)
    /// 96-99: 검지 (4개)
    /// 100-103: 중지 (4개)
    /// 104-107: 약지 (4개)
    /// 108-111: 소지 (4개)

    /// Right Hand 키포인트 (112-132, 21개)
    /// 112: 손목
    /// 113-116: 엄지 (4개)
    /// 117-120: 검지 (4개)
    /// 121-124: 중지 (4개)
    /// 125-128: 약지 (4개)
    /// 129-132: 소지 (4개)

    // MARK: - 손가락 인덱스 매핑
    private struct HandFingerIndices {
        // 왼손 (91-111)
        static let leftWrist = 91
        static let leftThumb = 92...95
        static let leftIndex = 96...99
        static let leftMiddle = 100...103
        static let leftRing = 104...107
        static let leftPinky = 108...111

        // 오른손 (112-132)
        static let rightWrist = 112
        static let rightThumb = 113...116
        static let rightIndex = 117...120
        static let rightMiddle = 121...124
        static let rightRing = 125...128
        static let rightPinky = 129...132
    }

    // MARK: - 얼굴 랜드마크 인덱스
    private struct FaceIndices {
        static let contour = 23...39        // 얼굴 윤곽 (17개)
        static let leftEyebrow = 40...44    // 왼쪽 눈썹 (5개)
        static let rightEyebrow = 45...49   // 오른쪽 눈썹 (5개)
        static let nose = 50...58           // 코 (9개)
        static let leftEye = 59...64        // 왼쪽 눈 (6개)
        static let rightEye = 65...70       // 오른쪽 눈 (6개)
        static let outerLips = 71...82      // 외부 입술 (12개)
        static let innerLips = 83...90      // 내부 입술 (8개)
    }

    // MARK: - 샷 타입 기반 필수 키포인트 (Phase 2)

    /// 샷 타입별 필수 키포인트 반환
    /// - Parameter shotType: 사진 샷 타입
    /// - Returns: 필수로 보여야 하는 키포인트 인덱스 배열
    private func getRequiredKeypoints(for shotType: ShotType) -> [Int] {
        switch shotType {
        case .extremeCloseUp, .closeUp:
            // 클로즈업: 머리, 얼굴, 손 (손 제스처 중요!)
            return [0, 1, 2, 3, 4] + Array(23...90) + Array(91...132)  // head + face + hands

        case .mediumCloseUp:
            // 미디엄 클로즈업: 머리, 얼굴, 어깨, 손
            return [0, 1, 2, 3, 4, 5, 6] + Array(23...90) + Array(91...132)  // head + shoulders + face + hands

        case .mediumShot:
            // 미디엄샷 (상반신): 머리~엉덩이 + 얼굴 + 손 (손 제스처 매우 중요!)
            // 하반신(다리 13-16, 발 17-22)은 제외
            return Array(0...12) + Array(23...90) + Array(91...132)  // upper body + face + hands

        case .americanShot:
            // 아메리칸샷 (무릎 위): 머리~무릎 + 얼굴 + 손
            // 발목(15-16), 발(17-22) 제외
            return Array(0...14) + Array(23...90) + Array(91...132)  // + knees + face + hands

        case .fullShot, .mediumFullShot, .longShot:
            // 풀샷 (전신): 모든 키포인트 (0-132 전부)
            return Array(0...132)  // 모든 키포인트
        }
    }

    /// 샷 타입별 선택적 키포인트 (있으면 좋지만 없어도 됨)
    private func getOptionalKeypoints(for shotType: ShotType) -> [Int] {
        switch shotType {
        case .extremeCloseUp, .closeUp:
            return [5, 6]  // 어깨는 선택적

        case .mediumCloseUp, .mediumShot:
            return Array(91...132)  // 손은 선택적

        case .americanShot:
            return Array(91...132) + [15, 16]  // 손 + 발목 선택적

        case .fullShot, .mediumFullShot, .longShot:
            return Array(17...22) + Array(91...132)  // 발가락 + 손 선택적
        }
    }

    /// 레퍼런스와 현재 포즈 적응형 비교 (RTMPose WholeBody 133개 키포인트)
    /// - Parameters:
    ///   - referenceKeypoints: 레퍼런스 키포인트 (133개, confidence 포함)
    ///   - currentKeypoints: 현재 키포인트 (133개, confidence 포함)
    /// - Returns: 비교 결과
    func comparePoses(
        referenceKeypoints: [(point: CGPoint, confidence: Float)],
        currentKeypoints: [(point: CGPoint, confidence: Float)]
    ) -> PoseComparisonResult {

        // 1. 보이는 키포인트 필터링 (부위별 다른 임계값 적용)
        let visibleRefIndices = filterVisibleKeypointsAdaptive(referenceKeypoints)
        let visibleCurIndices = filterVisibleKeypointsAdaptive(currentKeypoints)

        // 2. 공통으로 보이는 키포인트만 추출
        let comparableIndices = Set(visibleRefIndices).intersection(visibleCurIndices)

        // 3. 포즈 타입 자동 감지
        _ = detectPoseType(visibleIndices: Array(comparableIndices))
        let currentPoseType = detectPoseType(visibleIndices: Array(comparableIndices))

        // 4. 보이는/안 보이는 그룹 분류 (133개 키포인트 그룹 포함)
        let visibleGroups = classifyVisibleGroups(visibleIndices: Array(comparableIndices))
        let allGroups: Set<KeypointGroup> = [.head, .shoulders, .arms, .torso, .legs, .feet, .face, .leftHand, .rightHand]
        let missingGroups = Array(allGroups.subtracting(visibleGroups))

        // 5. 각 부위별 각도 차이 + 벡터 방향 + 상대적 위치 비교
        var angleDifferences: [String: Float] = [:]
        var angleDirections: [String: String] = [:]  // 🆕 구체적인 방향 설명

        // 왼팔 비교 (각도 + 벡터 방향 + 상대 위치)
        if canCompareLeftArm(indices: comparableIndices) {
            let refAngle = calculateArmAngle(
                shoulder: referenceKeypoints[5].point,
                elbow: referenceKeypoints[7].point,
                wrist: referenceKeypoints[9].point
            )
            let curAngle = calculateArmAngle(
                shoulder: currentKeypoints[5].point,
                elbow: currentKeypoints[7].point,
                wrist: currentKeypoints[9].point
            )

            // 🆕 벡터 방향 유사도 추가 (코사인 유사도)
            let refVector1 = normalizeVector(from: referenceKeypoints[5].point, to: referenceKeypoints[7].point)
            let curVector1 = normalizeVector(from: currentKeypoints[5].point, to: currentKeypoints[7].point)
            let refVector2 = normalizeVector(from: referenceKeypoints[7].point, to: referenceKeypoints[9].point)
            let curVector2 = normalizeVector(from: currentKeypoints[7].point, to: currentKeypoints[9].point)

            let directionSimilarity1 = cosineSimilarity(v1: refVector1, v2: curVector1)
            let directionSimilarity2 = cosineSimilarity(v1: refVector2, v2: curVector2)
            let avgDirectionSimilarity = (directionSimilarity1 + directionSimilarity2) / 2.0

            // 각도 차이와 방향 차이를 결합 (방향이 30% 이상 다르면 각도에 페널티)
            let directionPenalty = max(0, (1.0 - avgDirectionSimilarity) * 30.0)  // 최대 30도 페널티
            let totalDiff = abs(refAngle - curAngle) + Float(directionPenalty)
            angleDifferences["left_arm"] = totalDiff

            // 🆕 구체적인 방향 계산 (손목의 Y 좌표 비교)
            let refWristY = referenceKeypoints[9].point.y
            let curWristY = currentKeypoints[9].point.y
            let yDiff = curWristY - refWristY

            if abs(yDiff) > 0.05 {  // 5% 이상 차이나면
                if yDiff > 0 {
                    angleDirections["left_arm"] = "왼팔을 위로 올리세요"
                } else {
                    angleDirections["left_arm"] = "왼팔을 아래로 내리세요"
                }
            } else {
                // Y 좌표는 비슷한데 각도가 다르면 팔꿈치 위치 문제
                angleDirections["left_arm"] = "왼팔 각도를 조정하세요 (팔꿈치 위치)"
            }
        }

        // 오른팔 비교 (각도 + 벡터 방향 + 상대 위치)
        if canCompareRightArm(indices: comparableIndices) {
            let refAngle = calculateArmAngle(
                shoulder: referenceKeypoints[6].point,
                elbow: referenceKeypoints[8].point,
                wrist: referenceKeypoints[10].point
            )
            let curAngle = calculateArmAngle(
                shoulder: currentKeypoints[6].point,
                elbow: currentKeypoints[8].point,
                wrist: currentKeypoints[10].point
            )

            // 🆕 벡터 방향 유사도 추가
            let refVector1 = normalizeVector(from: referenceKeypoints[6].point, to: referenceKeypoints[8].point)
            let curVector1 = normalizeVector(from: currentKeypoints[6].point, to: currentKeypoints[8].point)
            let refVector2 = normalizeVector(from: referenceKeypoints[8].point, to: referenceKeypoints[10].point)
            let curVector2 = normalizeVector(from: currentKeypoints[8].point, to: currentKeypoints[10].point)

            let directionSimilarity1 = cosineSimilarity(v1: refVector1, v2: curVector1)
            let directionSimilarity2 = cosineSimilarity(v1: refVector2, v2: curVector2)
            let avgDirectionSimilarity = (directionSimilarity1 + directionSimilarity2) / 2.0

            let directionPenalty = max(0, (1.0 - avgDirectionSimilarity) * 30.0)
            let totalDiff = abs(refAngle - curAngle) + Float(directionPenalty)
            angleDifferences["right_arm"] = totalDiff

            // 🆕 구체적인 방향 계산 (손목의 Y 좌표 비교)
            let refWristY = referenceKeypoints[10].point.y
            let curWristY = currentKeypoints[10].point.y
            let yDiff = curWristY - refWristY

            if abs(yDiff) > 0.05 {  // 5% 이상 차이나면
                if yDiff > 0 {
                    angleDirections["right_arm"] = "오른팔을 위로 올리세요"
                } else {
                    angleDirections["right_arm"] = "오른팔을 아래로 내리세요"
                }
            } else {
                angleDirections["right_arm"] = "오른팔 각도를 조정하세요 (팔꿈치 위치)"
            }
        }

        // 왼다리 비교 (각도 + 벡터 방향)
        if canCompareLeftLeg(indices: comparableIndices) {
            let refAngle = calculateLegAngle(
                hip: referenceKeypoints[11].point,
                knee: referenceKeypoints[13].point,
                ankle: referenceKeypoints[15].point
            )
            let curAngle = calculateLegAngle(
                hip: currentKeypoints[11].point,
                knee: currentKeypoints[13].point,
                ankle: currentKeypoints[15].point
            )

            // 🆕 벡터 방향 유사도 추가
            let refVector1 = normalizeVector(from: referenceKeypoints[11].point, to: referenceKeypoints[13].point)
            let curVector1 = normalizeVector(from: currentKeypoints[11].point, to: currentKeypoints[13].point)
            let refVector2 = normalizeVector(from: referenceKeypoints[13].point, to: referenceKeypoints[15].point)
            let curVector2 = normalizeVector(from: currentKeypoints[13].point, to: currentKeypoints[15].point)

            let directionSimilarity1 = cosineSimilarity(v1: refVector1, v2: curVector1)
            let directionSimilarity2 = cosineSimilarity(v1: refVector2, v2: curVector2)
            let avgDirectionSimilarity = (directionSimilarity1 + directionSimilarity2) / 2.0

            let directionPenalty = max(0, (1.0 - avgDirectionSimilarity) * 30.0)
            let totalDiff = abs(refAngle - curAngle) + Float(directionPenalty)
            angleDifferences["left_leg"] = totalDiff

            // 🆕 구체적인 방향 계산 (무릎의 X 좌표 비교 - 다리 벌림/모음)
            let refKneeX = referenceKeypoints[13].point.x
            let curKneeX = currentKeypoints[13].point.x
            let xDiff = abs(curKneeX - refKneeX)

            if xDiff > 0.05 {  // 5% 이상 차이나면
                if curKneeX > refKneeX {
                    angleDirections["left_leg"] = "왼다리를 안쪽으로 모으세요"
                } else {
                    angleDirections["left_leg"] = "왼다리를 바깥쪽으로 벌리세요"
                }
            } else {
                angleDirections["left_leg"] = "왼다리 각도를 조정하세요"
            }
        }

        // 오른다리 비교 (각도 + 벡터 방향)
        if canCompareRightLeg(indices: comparableIndices) {
            let refAngle = calculateLegAngle(
                hip: referenceKeypoints[12].point,
                knee: referenceKeypoints[14].point,
                ankle: referenceKeypoints[16].point
            )
            let curAngle = calculateLegAngle(
                hip: currentKeypoints[12].point,
                knee: currentKeypoints[14].point,
                ankle: currentKeypoints[16].point
            )

            // 🆕 벡터 방향 유사도 추가
            let refVector1 = normalizeVector(from: referenceKeypoints[12].point, to: referenceKeypoints[14].point)
            let curVector1 = normalizeVector(from: currentKeypoints[12].point, to: currentKeypoints[14].point)
            let refVector2 = normalizeVector(from: referenceKeypoints[14].point, to: referenceKeypoints[16].point)
            let curVector2 = normalizeVector(from: currentKeypoints[14].point, to: currentKeypoints[16].point)

            let directionSimilarity1 = cosineSimilarity(v1: refVector1, v2: curVector1)
            let directionSimilarity2 = cosineSimilarity(v1: refVector2, v2: curVector2)
            let avgDirectionSimilarity = (directionSimilarity1 + directionSimilarity2) / 2.0

            let directionPenalty = max(0, (1.0 - avgDirectionSimilarity) * 30.0)
            let totalDiff = abs(refAngle - curAngle) + Float(directionPenalty)
            angleDifferences["right_leg"] = totalDiff

            // 🆕 구체적인 방향 계산 (무릎의 X 좌표 비교 - 다리 벌림/모음)
            let refKneeX = referenceKeypoints[14].point.x
            let curKneeX = currentKeypoints[14].point.x
            let xDiff = abs(curKneeX - refKneeX)

            if xDiff > 0.05 {  // 5% 이상 차이나면
                if curKneeX < refKneeX {
                    angleDirections["right_leg"] = "오른다리를 안쪽으로 모으세요"
                } else {
                    angleDirections["right_leg"] = "오른다리를 바깥쪽으로 벌리세요"
                }
            } else {
                angleDirections["right_leg"] = "오른다리 각도를 조정하세요"
            }
        }

        // 🆕 발 비교 (RTMPose 17-22)
        if canCompareFeet(indices: comparableIndices, keypoints: referenceKeypoints) &&
           canCompareFeet(indices: comparableIndices, keypoints: currentKeypoints) {
            let feetDiff = compareFeetPosition(
                reference: referenceKeypoints,
                current: currentKeypoints,
                indices: comparableIndices
            )
            if feetDiff > 0 {
                angleDifferences["feet"] = feetDiff
            }
        }

        // 🆕 왼손 비교 (RTMPose 91-111)
        if canCompareHand(indices: comparableIndices, handRange: 91...111, keypoints: referenceKeypoints) &&
           canCompareHand(indices: comparableIndices, handRange: 91...111, keypoints: currentKeypoints) {
            let leftHandDiff = compareHandShape(
                reference: referenceKeypoints,
                current: currentKeypoints,
                handRange: 91...111
            )
            if leftHandDiff > 0 {
                angleDifferences["left_hand"] = leftHandDiff
            }
        }

        // 🆕 오른손 비교 (RTMPose 112-132)
        if canCompareHand(indices: comparableIndices, handRange: 112...132, keypoints: referenceKeypoints) &&
           canCompareHand(indices: comparableIndices, handRange: 112...132, keypoints: currentKeypoints) {
            let rightHandDiff = compareHandShape(
                reference: referenceKeypoints,
                current: currentKeypoints,
                handRange: 112...132
            )
            if rightHandDiff > 0 {
                angleDifferences["right_hand"] = rightHandDiff
            }
        }

        // 🆕 얼굴 방향 비교 (RTMPose 23-90)
        if canCompareFace(indices: comparableIndices, keypoints: referenceKeypoints) &&
           canCompareFace(indices: comparableIndices, keypoints: currentKeypoints) {
            let faceDiff = compareFaceDirection(
                reference: referenceKeypoints,
                current: currentKeypoints
            )
            if faceDiff > 0 {
                angleDifferences["face"] = faceDiff
            }
        }

        // 🆕 어깨 기울기 비교 (몸통 기울기)
        if comparableIndices.contains(5) && comparableIndices.contains(6) {
            let refTilt = calculateShoulderTilt(keypoints: referenceKeypoints)
            let curTilt = calculateShoulderTilt(keypoints: currentKeypoints)
            let tiltDiff = abs(refTilt - curTilt)

            if tiltDiff > 5.0 {  // 5도 이상 차이
                angleDifferences["shoulder_tilt"] = Float(tiltDiff)

                // 방향 설명
                if curTilt > refTilt + 5.0 {
                    angleDirections["shoulder_tilt"] = "몸을 왼쪽으로 기울이세요"
                } else if curTilt < refTilt - 5.0 {
                    angleDirections["shoulder_tilt"] = "몸을 오른쪽으로 기울이세요"
                }
            }
        }

        // 6. 전체 정확도 계산
        let accuracy = calculateOverallAccuracy(angleDifferences: angleDifferences)

        return PoseComparisonResult(
            poseType: currentPoseType,
            visibleGroups: visibleGroups,
            missingGroups: missingGroups,
            comparableKeypoints: Array(comparableIndices).sorted(),
            angleDifferences: angleDifferences,
            angleDirections: angleDirections,  // 🆕 구체적인 방향 설명
            overallAccuracy: accuracy
        )
    }

    /// 포즈 비교 결과로부터 피드백 생성
    /// - Parameters:
    ///   - currentResult: 현재 프레임의 비교 결과
    ///   - referenceResult: 레퍼런스의 비교 결과 (어떤 부위가 있는지 확인용)
    /// - Returns: 피드백 아이템 배열
    func generateFeedback(
        from currentResult: PoseComparisonResult,
        referenceResult: PoseComparisonResult
    ) -> [(message: String, category: String)] {
        var feedback: [(message: String, category: String)] = []

        // 🔥 중요: 레퍼런스에 포즈 키포인트가 없으면 비교 불가
        if referenceResult.comparableKeypoints.isEmpty {
            print("⚠️ 레퍼런스에 포즈 키포인트가 없어서 비교 불가")
            return []  // 빈 배열 반환 (포즈 피드백 없음)
        }

        // 1. 레퍼런스와 현재 모두에서 보이는 부위만 비교
        let referenceVisibleGroups = Set(referenceResult.visibleGroups)
        let currentVisibleGroups = Set(currentResult.visibleGroups)

        // 레퍼런스에 있지만 현재 없는 중요 부위만 알림
        let missingImportantGroups = referenceVisibleGroups.subtracting(currentVisibleGroups)

        // 포즈 타입별로 중요한 부위 정의
        let importantGroups: Set<KeypointGroup>
        switch referenceResult.poseType {
        case .fullBody:
            importantGroups = [.head, .shoulders, .arms, .torso, .legs]
        case .upperBody:
            importantGroups = [.head, .shoulders, .arms, .torso]
        case .portrait:
            importantGroups = [.head, .shoulders]
        case .unknown:
            importantGroups = []
        }

        // 중요한 부위 중 빠진 것만 피드백
        let actuallyMissing = missingImportantGroups.intersection(importantGroups)

        if !actuallyMissing.isEmpty && actuallyMissing.count > 1 {
            // 너무 많은 부위가 안 보이면 전체적인 피드백
            feedback.append((
                message: "화면에 포즈가 잘 보이도록 조정해주세요",
                category: "pose_not_visible"
            ))
            return feedback  // 포즈가 제대로 안 보이면 다른 피드백 생략
        }

        // 2. 🆕 포즈 피드백 (직관적 표현 + 통합)
        // 🔧 tolerance 조정: 10도 → 15도 (너무 민감하면 계속 피드백이 나옴)
        // 하지만 실제 큰 차이는 감지해야 함
        let angleTolerance: Float = 15.0

        // 🔥 디버그: 포즈 각도 차이 출력
        #if DEBUG
        if !currentResult.angleDifferences.isEmpty {
            print("📊 포즈 각도 차이:")
            for (key, value) in currentResult.angleDifferences.sorted(by: { $0.key < $1.key }) {
                let status = abs(value) > angleTolerance ? "⚠️" : "✅"
                print("   \(status) \(key): \(String(format: "%.1f", value))°")
            }
        }
        #endif

        // 팔 피드백 통합 (왼팔/오른팔 따로 안내하지 않고 통합)
        let leftArmDiff = currentResult.angleDifferences["left_arm"] ?? 0
        let rightArmDiff = currentResult.angleDifferences["right_arm"] ?? 0
        let maxArmDiff = max(abs(leftArmDiff), abs(rightArmDiff))

        if maxArmDiff > angleTolerance {
            let message = generateArmFeedback(
                leftDiff: leftArmDiff,
                rightDiff: rightArmDiff,
                tolerance: angleTolerance
            )
            if let msg = message {
                feedback.append((message: msg, category: "pose_arms"))
            }
        }

        // 다리 피드백 통합
        let leftLegDiff = currentResult.angleDifferences["left_leg"] ?? 0
        let rightLegDiff = currentResult.angleDifferences["right_leg"] ?? 0
        let maxLegDiff = max(abs(leftLegDiff), abs(rightLegDiff))

        if maxLegDiff > angleTolerance {
            let message = generateLegFeedback(
                leftDiff: leftLegDiff,
                rightDiff: rightLegDiff,
                tolerance: angleTolerance
            )
            if let msg = message {
                feedback.append((message: msg, category: "pose_legs"))
            }
        }

        // 손 피드백 통합
        let leftHandDiff = currentResult.angleDifferences["left_hand"] ?? 0
        let rightHandDiff = currentResult.angleDifferences["right_hand"] ?? 0
        let maxHandDiff = max(abs(leftHandDiff), abs(rightHandDiff))

        if maxHandDiff > angleTolerance {
            let message = generateHandFeedback(
                leftDiff: leftHandDiff,
                rightDiff: rightHandDiff,
                tolerance: angleTolerance
            )
            if let msg = message {
                feedback.append((message: msg, category: "pose_hands"))
            }
        }

        // 발 피드백
        if let feetDiff = currentResult.angleDifferences["feet"],
           abs(feetDiff) > angleTolerance {
            let level = differenceLevel(from: feetDiff)
            feedback.append((
                message: "발 위치를 \(level) 조정해주세요",
                category: "pose_feet"
            ))
        }

        // 얼굴 방향 피드백
        if let faceDiff = currentResult.angleDifferences["face"],
           abs(faceDiff) > 5.0 {
            let level = differenceLevel(from: faceDiff)
            feedback.append((
                message: "고개를 \(level) 돌려주세요",
                category: "pose_face"
            ))
        }

        return feedback
    }

    // MARK: - 🆕 통합 피드백 생성 헬퍼

    /// 팔 피드백 생성 (좌우 통합)
    private func generateArmFeedback(leftDiff: Float, rightDiff: Float, tolerance: Float) -> String? {
        let leftNeedsAdjust = abs(leftDiff) > tolerance
        let rightNeedsAdjust = abs(rightDiff) > tolerance

        if leftNeedsAdjust && rightNeedsAdjust {
            // 양팔 모두 조정 필요
            let level = differenceLevel(from: max(abs(leftDiff), abs(rightDiff)))
            return "양팔 위치를 \(level) 조정해주세요"
        } else if leftNeedsAdjust {
            let level = differenceLevel(from: leftDiff)
            return "왼팔을 \(level) 조정해주세요"
        } else if rightNeedsAdjust {
            let level = differenceLevel(from: rightDiff)
            return "오른팔을 \(level) 조정해주세요"
        }
        return nil
    }

    /// 다리 피드백 생성 (좌우 통합)
    private func generateLegFeedback(leftDiff: Float, rightDiff: Float, tolerance: Float) -> String? {
        let leftNeedsAdjust = abs(leftDiff) > tolerance
        let rightNeedsAdjust = abs(rightDiff) > tolerance

        if leftNeedsAdjust && rightNeedsAdjust {
            let level = differenceLevel(from: max(abs(leftDiff), abs(rightDiff)))
            return "다리 위치를 \(level) 조정해주세요"
        } else if leftNeedsAdjust {
            let level = differenceLevel(from: leftDiff)
            return "왼다리를 \(level) 조정해주세요"
        } else if rightNeedsAdjust {
            let level = differenceLevel(from: rightDiff)
            return "오른다리를 \(level) 조정해주세요"
        }
        return nil
    }

    /// 손 피드백 생성 (좌우 통합)
    private func generateHandFeedback(leftDiff: Float, rightDiff: Float, tolerance: Float) -> String? {
        let leftNeedsAdjust = abs(leftDiff) > tolerance
        let rightNeedsAdjust = abs(rightDiff) > tolerance

        if leftNeedsAdjust && rightNeedsAdjust {
            let level = differenceLevel(from: max(abs(leftDiff), abs(rightDiff)))
            return "손 모양을 \(level) 조정해주세요"
        } else if leftNeedsAdjust {
            let level = differenceLevel(from: leftDiff)
            return "왼손을 \(level) 조정해주세요"
        } else if rightNeedsAdjust {
            let level = differenceLevel(from: rightDiff)
            return "오른손을 \(level) 조정해주세요"
        }
        return nil
    }

    /// 차이 정도에 따른 직관적 표현
    private func differenceLevel(from diff: Float) -> String {
        let absDiff = abs(diff)
        if absDiff > 30 {
            return "많이"
        } else if absDiff > 15 {
            return "조금"
        } else {
            return "살짝"
        }
    }

    // MARK: - Private Helpers

    /// 신뢰도 임계값 이상의 키포인트만 필터링
    private func filterVisibleKeypoints(
        _ keypoints: [(point: CGPoint, confidence: Float)]
    ) -> [Int] {
        return keypoints.enumerated().compactMap { index, kp in
            kp.confidence >= confidenceThreshold ? index : nil
        }
    }

    /// 포즈 타입 자동 감지
    private func detectPoseType(visibleIndices: [Int]) -> PoseType {
        let hasHead = visibleIndices.contains(where: { [0, 1, 2, 3, 4].contains($0) })
        let hasShoulders = visibleIndices.contains(5) || visibleIndices.contains(6)
        let hasTorso = visibleIndices.contains(11) || visibleIndices.contains(12)
        let hasLegs = visibleIndices.contains(where: { [13, 14, 15, 16].contains($0) })

        if hasHead && hasShoulders && hasTorso && hasLegs {
            return .fullBody
        } else if hasHead && hasShoulders && hasTorso {
            return .upperBody
        } else if hasHead && hasShoulders {
            return .portrait
        } else {
            return .unknown
        }
    }

    /// 보이는 신체 그룹 분류 (RTMPose 133개 키포인트 전체 지원)
    private func classifyVisibleGroups(visibleIndices: [Int]) -> [KeypointGroup] {
        var groups: [KeypointGroup] = []

        // 🆕 모든 그룹을 포함 (기존 5개 + 새로운 4개)
        let allGroups: [KeypointGroup] = [
            .head, .shoulders, .arms, .torso, .legs,  // 기존
            .feet, .face, .leftHand, .rightHand       // 🆕 새로운 그룹
        ]

        for group in allGroups {
            let groupIndices = group.keypointIndices
            let visibleCount = groupIndices.filter { visibleIndices.contains($0) }.count

            // 그룹별 다른 임계값 적용
            let threshold: Double
            switch group {
            case .face:
                threshold = 0.3  // 얼굴은 30% 이상 (68개 중 20개)
            case .leftHand, .rightHand:
                threshold = 0.5  // 손은 50% 이상 (21개 중 10개)
            case .feet:
                threshold = 0.6  // 발은 60% 이상 (6개 중 4개)
            default:
                threshold = 0.5  // 기본 50%
            }

            if Double(visibleCount) / Double(groupIndices.count) >= threshold {
                groups.append(group)
            }
        }

        return groups
    }

    /// 왼팔 비교 가능 여부
    private func canCompareLeftArm(indices: Set<Int>) -> Bool {
        return indices.contains(5) && indices.contains(7) && indices.contains(9)
    }

    /// 오른팔 비교 가능 여부
    private func canCompareRightArm(indices: Set<Int>) -> Bool {
        return indices.contains(6) && indices.contains(8) && indices.contains(10)
    }

    /// 왼다리 비교 가능 여부
    private func canCompareLeftLeg(indices: Set<Int>) -> Bool {
        return indices.contains(11) && indices.contains(13) && indices.contains(15)
    }

    /// 오른다리 비교 가능 여부
    private func canCompareRightLeg(indices: Set<Int>) -> Bool {
        return indices.contains(12) && indices.contains(14) && indices.contains(16)
    }

    /// 팔 각도 계산 (어깨-팔꿈치-손목)
    private func calculateArmAngle(
        shoulder: CGPoint,
        elbow: CGPoint,
        wrist: CGPoint
    ) -> Float {
        return calculateAngle(p1: shoulder, p2: elbow, p3: wrist)
    }

    /// 다리 각도 계산 (골반-무릎-발목)
    private func calculateLegAngle(
        hip: CGPoint,
        knee: CGPoint,
        ankle: CGPoint
    ) -> Float {
        return calculateAngle(p1: hip, p2: knee, p3: ankle)
    }

    /// 세 점으로 각도 계산 (p2가 꼭짓점)
    private func calculateAngle(p1: CGPoint, p2: CGPoint, p3: CGPoint) -> Float {
        let v1 = CGVector(dx: p1.x - p2.x, dy: p1.y - p2.y)
        let v2 = CGVector(dx: p3.x - p2.x, dy: p3.y - p2.y)

        let dot = v1.dx * v2.dx + v1.dy * v2.dy
        let mag1 = sqrt(v1.dx * v1.dx + v1.dy * v1.dy)
        let mag2 = sqrt(v2.dx * v2.dx + v2.dy * v2.dy)

        if mag1 == 0 || mag2 == 0 {
            return 0
        }

        let cosAngle = dot / (mag1 * mag2)
        let angleRad = acos(max(-1, min(1, cosAngle)))
        return Float(angleRad * 180 / .pi)
    }

    /// 전체 정확도 계산
    private func calculateOverallAccuracy(angleDifferences: [String: Float]) -> Double {
        guard !angleDifferences.isEmpty else {
            return 1.0  // 비교할 게 없으면 완벽
        }

        let maxDiff: Float = 180.0  // 최대 각도 차이
        var totalAccuracy: Double = 0.0

        for (_, diff) in angleDifferences {
            let accuracy = max(0.0, 1.0 - Double(diff / maxDiff))
            totalAccuracy += accuracy
        }

        return totalAccuracy / Double(angleDifferences.count)
    }

    /// 그룹 이름 한국어 변환
    private func groupName(_ group: KeypointGroup) -> String {
        return group.displayName
    }

    // MARK: - 🆕 RTMPose WholeBody 133개 키포인트 비교 함수들

    /// 적응형 신뢰도 임계값으로 키포인트 필터링
    private func filterVisibleKeypointsAdaptive(
        _ keypoints: [(point: CGPoint, confidence: Float)]
    ) -> [Int] {
        return keypoints.enumerated().compactMap { index, kp in
            let threshold: Float
            if index >= 91 {
                // 손 키포인트 (91-132)
                threshold = handConfidenceThreshold
            } else if index >= 23 && index <= 90 {
                // 얼굴 키포인트 (23-90)
                threshold = faceConfidenceThreshold
            } else {
                // 몸통/발 키포인트 (0-22)
                threshold = confidenceThreshold
            }
            return kp.confidence >= threshold ? index : nil
        }
    }

    /// 발 비교 가능 여부 (최소 4개 키포인트 필요)
    private func canCompareFeet(
        indices: Set<Int>,
        keypoints: [(point: CGPoint, confidence: Float)]
    ) -> Bool {
        guard keypoints.count >= 23 else { return false }  // 최소 23개 있어야 발 포함
        let feetIndices = Set(17...22)
        let visibleFeet = indices.intersection(feetIndices)
        return visibleFeet.count >= 4
    }

    /// 발 위치 비교 (발가락 위치 유사도)
    private func compareFeetPosition(
        reference: [(point: CGPoint, confidence: Float)],
        current: [(point: CGPoint, confidence: Float)],
        indices: Set<Int>
    ) -> Float {
        guard reference.count >= 23 && current.count >= 23 else { return 0 }

        var totalDiff: CGFloat = 0
        var count = 0

        // 왼발 (17-19), 오른발 (20-22) 비교
        for i in 17...22 {
            guard indices.contains(i) else { continue }
            let refPoint = reference[i].point
            let curPoint = current[i].point

            // 정규화된 거리 계산
            let dx = refPoint.x - curPoint.x
            let dy = refPoint.y - curPoint.y
            let distance = sqrt(dx * dx + dy * dy)
            totalDiff += distance
            count += 1
        }

        guard count > 0 else { return 0 }

        // 평균 거리를 각도 차이로 변환 (0.1 거리 = 약 15도)
        let avgDiff = totalDiff / CGFloat(count)
        return Float(avgDiff * 150)  // 스케일링
    }

    /// 손 비교 가능 여부 (최소 10개 키포인트 필요)
    private func canCompareHand(
        indices: Set<Int>,
        handRange: ClosedRange<Int>,
        keypoints: [(point: CGPoint, confidence: Float)]
    ) -> Bool {
        guard keypoints.count >= handRange.upperBound + 1 else { return false }
        let handIndices = Set(handRange)
        let visibleHand = indices.intersection(handIndices)
        return visibleHand.count >= 10  // 21개 중 10개 이상
    }

    /// 손 모양 비교 (손가락 펴짐/접힘 + 손 방향)
    private func compareHandShape(
        reference: [(point: CGPoint, confidence: Float)],
        current: [(point: CGPoint, confidence: Float)],
        handRange: ClosedRange<Int>
    ) -> Float {
        guard reference.count >= handRange.upperBound + 1 &&
              current.count >= handRange.upperBound + 1 else { return 0 }

        let wristIdx = handRange.lowerBound
        let fingerRanges = [
            handRange.lowerBound + 1...handRange.lowerBound + 4,   // 엄지
            handRange.lowerBound + 5...handRange.lowerBound + 8,   // 검지
            handRange.lowerBound + 9...handRange.lowerBound + 12,  // 중지
            handRange.lowerBound + 13...handRange.lowerBound + 16, // 약지
            handRange.lowerBound + 17...handRange.lowerBound + 20  // 소지
        ]

        var totalDiff: Float = 0
        var fingerCount = 0

        for fingerRange in fingerRanges {
            // 손가락 끝 인덱스
            let tipIdx = fingerRange.upperBound

            guard reference[tipIdx].confidence > handConfidenceThreshold &&
                  current[tipIdx].confidence > handConfidenceThreshold &&
                  reference[wristIdx].confidence > handConfidenceThreshold &&
                  current[wristIdx].confidence > handConfidenceThreshold else { continue }

            // 손목에서 손가락 끝까지의 벡터 비교
            let refVector = normalizeVector(from: reference[wristIdx].point, to: reference[tipIdx].point)
            let curVector = normalizeVector(from: current[wristIdx].point, to: current[tipIdx].point)

            let similarity = cosineSimilarity(v1: refVector, v2: curVector)
            let diff = (1.0 - similarity) * 30.0  // 차이를 각도로 변환

            totalDiff += Float(diff)
            fingerCount += 1
        }

        guard fingerCount > 0 else { return 0 }
        return totalDiff / Float(fingerCount)
    }

    /// 얼굴 비교 가능 여부 (최소 20개 키포인트 필요)
    private func canCompareFace(
        indices: Set<Int>,
        keypoints: [(point: CGPoint, confidence: Float)]
    ) -> Bool {
        guard keypoints.count >= 91 else { return false }  // 91개 이상이어야 얼굴 포함
        let faceIndices = Set(23...90)
        let visibleFace = indices.intersection(faceIndices)
        return visibleFace.count >= 20  // 68개 중 20개 이상
    }

    /// 얼굴 방향 비교 (얼굴 윤곽과 코 기반)
    private func compareFaceDirection(
        reference: [(point: CGPoint, confidence: Float)],
        current: [(point: CGPoint, confidence: Float)]
    ) -> Float {
        guard reference.count >= 91 && current.count >= 91 else { return 0 }

        // 얼굴 중심 (코 끝 - 인덱스 54)
        let noseIdx = 54
        // 얼굴 좌우 끝 (윤곽 - 인덱스 23, 31)
        let leftContourIdx = 23
        let rightContourIdx = 31

        guard reference[noseIdx].confidence > faceConfidenceThreshold &&
              current[noseIdx].confidence > faceConfidenceThreshold &&
              reference[leftContourIdx].confidence > faceConfidenceThreshold &&
              current[leftContourIdx].confidence > faceConfidenceThreshold &&
              reference[rightContourIdx].confidence > faceConfidenceThreshold &&
              current[rightContourIdx].confidence > faceConfidenceThreshold else {
            return 0
        }

        // 코에서 양쪽 윤곽까지의 거리 비율로 얼굴 방향 추정
        let refLeftDist = distance(from: reference[noseIdx].point, to: reference[leftContourIdx].point)
        let refRightDist = distance(from: reference[noseIdx].point, to: reference[rightContourIdx].point)
        let curLeftDist = distance(from: current[noseIdx].point, to: current[leftContourIdx].point)
        let curRightDist = distance(from: current[noseIdx].point, to: current[rightContourIdx].point)

        // 좌우 비율 계산 (1.0이면 정면)
        let refRatio = refLeftDist / max(refRightDist, 0.001)
        let curRatio = curLeftDist / max(curRightDist, 0.001)

        // 비율 차이를 각도로 변환
        let ratioDiff = abs(refRatio - curRatio)
        return Float(ratioDiff * 30.0)  // 스케일링
    }

    /// 두 점 사이의 거리
    private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }

    /// 어깨 기울기 계산 (도)
    private func calculateShoulderTilt(
        keypoints: [(point: CGPoint, confidence: Float)]
    ) -> CGFloat {
        guard keypoints.count > 6 else { return 0 }

        let leftShoulder = keypoints[5]
        let rightShoulder = keypoints[6]

        guard leftShoulder.confidence > confidenceThreshold,
              rightShoulder.confidence > confidenceThreshold else {
            return 0
        }

        let dx = rightShoulder.point.x - leftShoulder.point.x
        let dy = rightShoulder.point.y - leftShoulder.point.y

        // atan2로 각도 계산
        let angleRadians = atan2(dy, dx)
        let angleDegrees = angleRadians * 180 / .pi

        return CGFloat(angleDegrees)
    }

    // MARK: - 🆕 벡터 연산 Helper Functions

    /// 두 점 사이의 정규화된 벡터 계산
    private func normalizeVector(from p1: CGPoint, to p2: CGPoint) -> CGVector {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let magnitude = sqrt(dx * dx + dy * dy)

        // 영벡터 방지
        if magnitude < 0.0001 {
            return CGVector(dx: 0, dy: 0)
        }

        return CGVector(dx: dx / magnitude, dy: dy / magnitude)
    }

    /// 두 벡터의 코사인 유사도 계산 (0~1, 1이 완전히 같은 방향)
    private func cosineSimilarity(v1: CGVector, v2: CGVector) -> Double {
        let dot = v1.dx * v2.dx + v1.dy * v2.dy
        let mag1 = sqrt(v1.dx * v1.dx + v1.dy * v1.dy)
        let mag2 = sqrt(v2.dx * v2.dx + v2.dy * v2.dy)

        // 영벡터 방지
        if mag1 < 0.0001 || mag2 < 0.0001 {
            return 0.0
        }

        // 코사인 값을 0~1로 정규화 (-1~1 → 0~1)
        let cosine = dot / (mag1 * mag2)
        return (Double(cosine) + 1.0) / 2.0
    }

    // MARK: - 🆕 잘림 감지 로직 (Phase 2)

    /// 키포인트가 프레임 경계에서 잘렸는지 감지
    /// - Parameters:
    ///   - keypoint: 확인할 키포인트 (정규화된 좌표 0.0~1.0)
    ///   - confidence: 키포인트 신뢰도
    ///   - referenceConfidence: 레퍼런스에서의 신뢰도 (옵션)
    /// - Returns: 잘렸는지 여부
    private func isKeypointCropped(
        keypoint: (point: CGPoint, confidence: Float),
        referenceConfidence: Float?
    ) -> Bool {
        // 조건 1: 현재 신뢰도가 낮음 (0.1~0.3)
        let hasLowConfidence = keypoint.confidence >= lowConfidenceThreshold &&
                               keypoint.confidence < mediumConfidenceThreshold

        // 조건 2: 프레임 경계 근처에 위치
        let isNearEdge = keypoint.point.x < frameEdgeThreshold ||
                         keypoint.point.x > (1.0 - frameEdgeThreshold) ||
                         keypoint.point.y < frameEdgeThreshold ||
                         keypoint.point.y > (1.0 - frameEdgeThreshold)

        // 조건 3 (선택): 레퍼런스에서는 확실했음
        var wasConfidentInReference = true
        if let refConf = referenceConfidence {
            wasConfidentInReference = refConf >= highConfidenceThreshold
        }

        // 모든 조건이 만족되면 잘렸다고 판단
        return hasLowConfidence && isNearEdge && wasConfidentInReference
    }

    /// 잘린 키포인트 그룹 감지
    /// - Parameters:
    ///   - referenceKeypoints: 레퍼런스 키포인트
    ///   - currentKeypoints: 현재 키포인트
    ///   - shotType: 샷 타입
    /// - Returns: 잘린 것으로 판단되는 키포인트 그룹들
    func detectCroppedGroups(
        referenceKeypoints: [(point: CGPoint, confidence: Float)],
        currentKeypoints: [(point: CGPoint, confidence: Float)],
        shotType: ShotType
    ) -> [KeypointGroup] {
        guard referenceKeypoints.count >= 133 && currentKeypoints.count >= 133 else {
            return []
        }

        var croppedGroups: [KeypointGroup] = []
        let requiredIndices = Set(getRequiredKeypoints(for: shotType))

        // 각 그룹별로 잘림 감지
        let allGroups: [KeypointGroup] = [.head, .shoulders, .arms, .torso, .legs, .feet, .leftHand, .rightHand]

        for group in allGroups {
            let groupIndices = group.keypointIndices

            // 필수 키포인트가 아니면 스킵
            let relevantIndices = groupIndices.filter { requiredIndices.contains($0) }
            guard !relevantIndices.isEmpty else { continue }

            // 그룹 내에서 잘린 키포인트 개수 확인
            var croppedCount = 0
            for idx in relevantIndices {
                if isKeypointCropped(
                    keypoint: currentKeypoints[idx],
                    referenceConfidence: referenceKeypoints[idx].confidence
                ) {
                    croppedCount += 1
                }
            }

            // 그룹의 50% 이상이 잘렸으면 해당 그룹이 잘렸다고 판단
            if Double(croppedCount) / Double(relevantIndices.count) >= 0.5 {
                croppedGroups.append(group)
            }
        }

        return croppedGroups
    }

    /// 잘린 부위에 대한 피드백 생성
    /// - Parameter croppedGroups: 잘린 키포인트 그룹들
    /// - Returns: 피드백 메시지
    func generateCroppingFeedback(croppedGroups: [KeypointGroup]) -> String? {
        guard !croppedGroups.isEmpty else { return nil }

        // 우선순위: legs > arms > feet > hands
        if croppedGroups.contains(.legs) {
            return "다리가 잘렸어요. 조금 뒤로 가세요"
        } else if croppedGroups.contains(.feet) {
            return "발이 잘렸어요. 조금 뒤로 가세요"
        } else if croppedGroups.contains(.arms) {
            return "팔이 잘렸어요. 프레임을 넓혀주세요"
        } else if croppedGroups.contains(.leftHand) || croppedGroups.contains(.rightHand) {
            return "손이 잘렸어요. 프레임을 조정하세요"
        } else if croppedGroups.contains(.head) {
            return "머리가 잘렸어요. 프레임을 조정하세요"
        }

        return "\(croppedGroups.first?.displayName ?? "신체 일부")가 잘렸어요"
    }
}
