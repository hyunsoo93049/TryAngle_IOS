// PersonDetector.swift
// 사람 검출 - YOLOX 전용 (RTMPoseRunner 재사용)
// 작성일: 2025-12-05
// 수정일: 2025-12-10 - Vision Framework 제거, YOLOX 전용

import CoreML
import CoreImage
import UIKit

class PersonDetector {

    // RTMPoseRunner 참조 (YOLOX 재사용)
    private weak var rtmPoseRunner: RTMPoseRunner?

    // MARK: - Initialization
    init(rtmPoseRunner: RTMPoseRunner? = nil) {
        self.rtmPoseRunner = rtmPoseRunner
        print("✅ PersonDetector 초기화 (YOLOX 전용)")
    }

    // RTMPoseRunner 연결 (나중에 설정)
    func setRTMPoseRunner(_ runner: RTMPoseRunner) {
        self.rtmPoseRunner = runner
        print("✅ PersonDetector: RTMPoseRunner 연결됨 (YOLOX 사용 가능)")
    }

    // MARK: - Person Detection
    func detectPerson(in image: CIImage, completion: @escaping (CGRect?) -> Void) {
        // YOLOX 전용
        guard let runner = rtmPoseRunner, runner.isReady else {
            print("⚠️ PersonDetector: RTMPoseRunner not ready")
            completion(nil)
            return
        }
        detectPersonWithYOLOX(in: image, using: runner, completion: completion)
    }

    // MARK: - YOLOX Detection (RTMPoseRunner 재사용)
    private func detectPersonWithYOLOX(in image: CIImage, using runner: RTMPoseRunner, completion: @escaping (CGRect?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // CIImage → UIImage 변환
            let context = CIContext()
            guard let cgImage = context.createCGImage(image, from: image.extent) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let uiImage = UIImage(cgImage: cgImage)

            // YOLOX로 검출
            let bbox = runner.detectPersonBBox(from: uiImage)

            if let bbox = bbox {
                // YOLOX BBox는 픽셀 좌표 → 정규화 좌표로 변환
                let imageSize = image.extent.size
                let normalizedBBox = CGRect(
                    x: bbox.origin.x / imageSize.width,
                    y: bbox.origin.y / imageSize.height,
                    width: bbox.width / imageSize.width,
                    height: bbox.height / imageSize.height
                )

                DispatchQueue.main.async {
                    completion(normalizedBBox)
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    // MARK: - Multiple Person Detection
    func detectAllPersons(in image: CIImage, completion: @escaping ([Detection]) -> Void) {
        guard let runner = rtmPoseRunner, runner.isReady else {
            print("⚠️ PersonDetector: RTMPoseRunner not ready")
            completion([])
            return
        }
        detectAllPersonsWithYOLOX(in: image, using: runner, completion: completion)
    }

    private func detectAllPersonsWithYOLOX(in image: CIImage, using runner: RTMPoseRunner, completion: @escaping ([Detection]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let context = CIContext()
            guard let cgImage = context.createCGImage(image, from: image.extent) else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let uiImage = UIImage(cgImage: cgImage)
            let imageSize = image.extent.size

            let boxes = runner.detectAllPersonBBoxes(from: uiImage)

            let detections = boxes.map { bbox -> Detection in
                // 픽셀 좌표 → 정규화 좌표
                let normalizedBBox = CGRect(
                    x: bbox.origin.x / imageSize.width,
                    y: bbox.origin.y / imageSize.height,
                    width: bbox.width / imageSize.width,
                    height: bbox.height / imageSize.height
                )
                return Detection(label: "person", confidence: 0.9, boundingBox: normalizedBBox)
            }

            DispatchQueue.main.async {
                completion(detections)
            }
        }
    }

    // MARK: - Text-Guided Detection (호환성 유지)
    func detectWithText(in image: CIImage, text: String, completion: @escaping ([Detection]) -> Void) {
        if text.lowercased().contains("person") || text.lowercased().contains("사람") {
            detectAllPersons(in: image, completion: completion)
        } else {
            print("⚠️ 현재 'person' 검출만 지원됩니다")
            completion([])
        }
    }

    // MARK: - Model Info
    var isUsingYOLOX: Bool {
        return rtmPoseRunner?.isReady ?? false
    }

    var modelDescription: String {
        return "YOLOX (RTMPoseRunner 재사용)"
    }
}

// MARK: - Detection Result
struct Detection {
    let label: String
    let confidence: Float
    let boundingBox: CGRect
}

// MARK: - Legacy System Port
extension PersonDetector {

    // legacy_analyzer.py의 calculate_margins를 Swift로 포팅
    func calculateMargins(personBBox: CGRect, imageSize: CGSize) -> MarginAnalysis {
        let imageWidth = imageSize.width
        let imageHeight = imageSize.height

        // bbox를 픽셀 좌표로 변환 (Vision/YOLOX는 normalized coordinates 사용)
        let x = personBBox.origin.x * imageWidth
        let y = personBBox.origin.y * imageHeight
        let w = personBBox.width * imageWidth
        let h = personBBox.height * imageHeight

        // 여백 계산
        let leftMargin = x
        let rightMargin = imageWidth - (x + w)
        let topMargin = y
        let bottomMargin = imageHeight - (y + h)

        // 비율 계산
        let leftRatio = leftMargin / imageWidth
        let rightRatio = rightMargin / imageWidth
        let topRatio = topMargin / imageHeight
        let bottomRatio = bottomMargin / imageHeight

        // 균형 점수 계산
        let horizontalBalance = 1.0 - abs(leftRatio - rightRatio)
        let verticalBalance = 1.0 - abs(topRatio - bottomRatio * 0.5) // 하단 2:1 비율 선호
        let balanceScore = (horizontalBalance + verticalBalance) / 2.0

        return MarginAnalysis(
            left: leftMargin,
            right: rightMargin,
            top: topMargin,
            bottom: bottomMargin,
            leftRatio: leftRatio,
            rightRatio: rightRatio,
            topRatio: topRatio,
            bottomRatio: bottomRatio,
            balanceScore: balanceScore
        )
    }

    // 프레이밍 분석
    func analyzeFraming(personBBox: CGRect, imageSize: CGSize) -> V15FramingAnalysis {
        let margins = calculateMargins(personBBox: personBBox, imageSize: imageSize)

        // 프레이밍 타입 결정
        let framingType: V15FramingType
        let bboxHeightRatio = personBBox.height

        if bboxHeightRatio > 0.8 {
            framingType = .tooTight
        } else if bboxHeightRatio < 0.3 {
            framingType = .tooLoose
        } else if bboxHeightRatio > 0.6 {
            framingType = .closeUp
        } else if bboxHeightRatio > 0.4 {
            framingType = .medium
        } else {
            framingType = .wide
        }

        // 크롭 이슈 체크
        let hasCropIssue = margins.left < 10 || margins.right < 10 ||
                           margins.top < 10 || margins.bottom < 10

        return V15FramingAnalysis(
            type: framingType,
            score: margins.balanceScore,
            hasCropIssue: hasCropIssue,
            margins: margins
        )
    }
}

// MARK: - Data Structures
struct MarginAnalysis {
    let left: CGFloat
    let right: CGFloat
    let top: CGFloat
    let bottom: CGFloat
    let leftRatio: CGFloat
    let rightRatio: CGFloat
    let topRatio: CGFloat
    let bottomRatio: CGFloat
    let balanceScore: CGFloat
}

struct V15FramingAnalysis {
    let type: V15FramingType
    let score: CGFloat
    let hasCropIssue: Bool
    let margins: MarginAnalysis
}

enum V15FramingType {
    case tooTight
    case tooLoose
    case closeUp
    case medium
    case wide
}
