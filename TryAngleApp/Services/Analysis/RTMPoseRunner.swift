import Foundation
import UIKit
import CoreGraphics
import Accelerate
import simd
import Vision
import CoreML

// MARK: - RTMPose 결과 구조체
struct RTMPoseResult {
    let keypoints: [(point: CGPoint, confidence: Float)]  // 133개 키포인트
    let boundingBox: CGRect?  // 인물 검출 박스
}

// MARK: - RTMPose Runner (CoreML + ONNX Runtime)
// 역할: YOLO11n(사람 검출, CoreML) + RTMPose(133개 키포인트, ONNX) 모델을 실행하는 핵심 러너입니다.
//       싱글톤으로 구현되어 앱 전체에서 하나의 인스턴스만 사용합니다.
class RTMPoseRunner {

    // MARK: - Singleton (지연 초기화)
    private static var _shared: RTMPoseRunner?
    private static let initQueue = DispatchQueue(label: "rtmpose.init", qos: .userInitiated)
    private static var isInitializing = false

    static var shared: RTMPoseRunner? {
        if let instance = _shared { return instance }

        // 🔥 백그라운드에서 아직 초기화 안됨 → nil 반환 (나중에 다시 시도)
        initializeInBackground()
        return _shared
    }

    /// 🔥 백그라운드에서 모델 초기화 (앱 시작 시 호출)
    static func initializeInBackground(completion: (() -> Void)? = nil) {
        guard _shared == nil && !isInitializing else {
            completion?()
            return
        }

        isInitializing = true

        initQueue.async {
            print("🚀 RTMPoseRunner 백그라운드 초기화 시작")
            _shared = RTMPoseRunner()
            isInitializing = false
            print("✅ RTMPoseRunner 백그라운드 초기화 완료")

            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    // YOLO11n CoreML (사람 검출)
    private var yoloModel: VNCoreMLModel?

    // RTMPose ONNX (포즈 추정)
    private var poseSession: ORTSession?
    private var env: ORTEnv?

    // 모델 경로
    private let poseModelPath: String

    // 모델 입력 크기
    private let detectorInputSize = CGSize(width: 640, height: 640)
    private let poseInputSize = CGSize(width: 192, height: 256)

    private init?() {
        // 🔥 이 init은 백그라운드 스레드에서만 호출됨
        print("🚀 RTMPoseRunner init() 시작 (백그라운드)")

        // YOLO11n CoreML 모델 (사람 검출) - 메모리 효율적
        guard let yoloURL = Bundle.main.url(forResource: "YOLO11nDetector", withExtension: "mlmodelc") else {
            print("❌ YOLO11nDetector.mlmodelc 파일을 찾을 수 없습니다")
            return nil
        }

        // RTMPose ONNX 모델 (포즈 추정)
        guard let poseURL = Bundle.main.url(forResource: "rtmpose_int8", withExtension: "onnx") else {
            print("❌ rtmpose_int8.onnx 파일을 찾을 수 없습니다")
            return nil
        }

        poseModelPath = poseURL.path

        print("✅ 모델 경로 확인:")
        print("   Detector (YOLO11n CoreML): \(yoloURL.path)")
        print("   Pose (RTMPose ONNX): \(poseModelPath)")

        // CoreML 모델 로드 (백그라운드)
        setupCoreMLDetector(yoloURL: yoloURL)

        // ONNX Runtime 초기화 (백그라운드)
        setupONNXRuntime()
    }

    deinit {
        print("🗑️ RTMPoseRunner deinit")
    }

    // MARK: - CoreML Detector 초기화 (YOLO11n)
    private func setupCoreMLDetector(yoloURL: URL) {
        print("🔧 YOLO11n CoreML 초기화 시작...")
        logMemory("YOLO11n 로드 전")

        do {
            // CoreML 모델 로드 (컴파일)
            let config = MLModelConfiguration()
            config.computeUnits = .all  // Neural Engine + GPU + CPU 자동 선택

            let mlModel = try MLModel(contentsOf: yoloURL, configuration: config)
            yoloModel = try VNCoreMLModel(for: mlModel)
            print("✅ YOLO11n CoreML 로드 성공 (Neural Engine 가속)")
            logMemory("YOLO11n 로드 후")
        } catch {
            print("❌ YOLO11n CoreML 로드 실패: \(error)")
            yoloModel = nil
        }
    }

    // MARK: - ONNX Runtime 초기화 (RTMPose만)
    private func setupONNXRuntime() {
        print("🔧 ONNX Runtime 초기화 시작 (RTMPose)...")

        do {
            // 1. Environment 생성
            env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
            print("✅ Environment 생성 성공")

            // 2. RTMPose용 Session Options (CoreML GPU 가속)
            let poseOptions = try ORTSessionOptions()

            // 🔥 CoreML Execution Provider 활성화 (GPU 가속)
            do {
                try poseOptions.appendCoreMLExecutionProvider()
                print("✅ RTMPose: CoreML GPU 가속 활성화")
            } catch {
                print("⚠️ RTMPose CoreML 활성화 실패, CPU 폴백: \(error)")
            }

            // 병렬 처리 설정 (최대 성능)
            try poseOptions.setIntraOpNumThreads(6)
            try poseOptions.setGraphOptimizationLevel(.all)

            // 3. RTMPose 세션 생성
            logMemory("RTMPose 로드 전")

            print("📦 Pose 모델 로딩 중... (\(poseModelPath))")
            poseSession = try ORTSession(env: env!, modelPath: poseModelPath, sessionOptions: poseOptions)
            print("✅ RTMPose 로드 성공 (CoreML GPU)")
            logMemory("RTMPose 로드 후")

            print("🔧 ONNX Runtime 초기화 완료")

        } catch {
            print("❌ ONNX Runtime 초기화 실패: \(error)")
            env = nil
            poseSession = nil
        }
    }

    // MARK: - YOLO11n CoreML로 사람 검출 (BBox만 필요할 때)
    func detectPersonBBox(from image: UIImage) -> CGRect? {
        guard let yoloModel = yoloModel else {
            print("❌ YOLO11n CoreML 모델이 초기화되지 않음")
            return nil
        }

        return detectPersonWithCoreML(from: image, model: yoloModel)
    }

    // MARK: - YOLO11n CoreML로 모든 사람 검출 (멀티 person)
    func detectAllPersonBBoxes(from image: UIImage) -> [CGRect] {
        guard let yoloModel = yoloModel else {
            print("❌ YOLO11n CoreML 모델이 초기화되지 않음")
            return []
        }

        return detectAllPersonsWithCoreML(from: image, model: yoloModel)
    }

    // MARK: - 세션 상태 확인
    var isReady: Bool {
        return yoloModel != nil && poseSession != nil && env != nil
    }

    // MARK: - 포즈 추정
    func detectPose(from image: UIImage) -> RTMPoseResult? {
        guard let yoloModel = yoloModel,
              let poseSession = poseSession,
              let env = env else {
            print("❌ RTMPose 세션이 초기화되지 않음")
            return nil
        }

        // 1. YOLO11n CoreML로 사람 검출
        guard let detectedBox = detectPersonWithCoreML(from: image, model: yoloModel) else {
            // 🔧 수정: 사람 검출 실패 시 RTMPose 실행 안 함
            print("⚠️ YOLO11n: 사람 검출 안됨 → 포즈 추정 건너뜀")
            return nil
        }

        print("✅ YOLO11n: 사람 검출 성공 - \(detectedBox)")

        // 2. 검출된 영역으로 포즈 추정
        let keypoints = estimatePose(from: image, boundingBox: detectedBox, using: poseSession, env: env)

        if let keypoints = keypoints {
            print("✅ RTMPose: \(keypoints.count)개 키포인트 검출 성공")
        } else {
            print("❌ RTMPose: 포즈 추정 실패")
        }

        return keypoints.map { RTMPoseResult(keypoints: $0, boundingBox: detectedBox) }
    }

    // MARK: - YOLO11n CoreML 사람 검출 (단일)
    private static let visionQueue = DispatchQueue(label: "yolo11n.vision", qos: .userInitiated)

    private func detectPersonWithCoreML(from image: UIImage, model: VNCoreMLModel) -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }

        var resultBox: CGRect?
        let semaphore = DispatchSemaphore(value: 0)
        let imageWidth = cgImage.width
        let imageHeight = cgImage.height

        // 백그라운드 스레드에서 Vision 요청 실행
        Self.visionQueue.async {
            // 🔥 메모리 누수 방지: Vision 요청 객체 즉시 해제
            autoreleasepool {
                let request = VNCoreMLRequest(model: model) { request, error in
                    if let error = error {
                        print("❌ YOLO11n 추론 오류: \(error)")
                        semaphore.signal()
                        return
                    }

                    // VNRecognizedObjectObservation으로 결과 파싱
                    guard let results = request.results as? [VNRecognizedObjectObservation] else {
                        print("⚠️ YOLO11n: 결과 형식 불일치")
                        semaphore.signal()
                        return
                    }

                    // person 클래스만 필터링하고 가장 높은 confidence 선택
                    var bestBox: CGRect?
                    var bestConfidence: Float = 0.3  // 최소 임계값

                    for observation in results {
                        // person 클래스 확인 (COCO 클래스 0)
                        if let topLabel = observation.labels.first,
                           topLabel.identifier == "person" || topLabel.identifier == "0",
                           topLabel.confidence > bestConfidence {
                            bestConfidence = topLabel.confidence
                            // Vision 좌표계 (좌하단 원점) → UIKit 좌표계 변환
                            let bbox = observation.boundingBox
                            bestBox = CGRect(
                                x: bbox.minX * CGFloat(imageWidth),
                                y: (1 - bbox.maxY) * CGFloat(imageHeight),
                                width: bbox.width * CGFloat(imageWidth),
                                height: bbox.height * CGFloat(imageHeight)
                            )
                        }
                    }

                    resultBox = bestBox
                    semaphore.signal()
                }

                request.imageCropAndScaleOption = .scaleFill

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    print("❌ YOLO11n Vision 실행 오류: \(error)")
                    semaphore.signal()
                }
            }
        }

        semaphore.wait()
        return resultBox
    }

    // MARK: - YOLO11n CoreML 모든 사람 검출 (멀티)
    private func detectAllPersonsWithCoreML(from image: UIImage, model: VNCoreMLModel) -> [CGRect] {
        guard let cgImage = image.cgImage else { return [] }

        var resultBoxes: [CGRect] = []
        let semaphore = DispatchSemaphore(value: 0)
        let imageWidth = cgImage.width
        let imageHeight = cgImage.height

        // 백그라운드 스레드에서 Vision 요청 실행
        Self.visionQueue.async {
            // 🔥 메모리 누수 방지: Vision 요청 객체 즉시 해제
            autoreleasepool {
                let request = VNCoreMLRequest(model: model) { request, error in
                    if let error = error {
                        print("❌ YOLO11n 추론 오류: \(error)")
                        semaphore.signal()
                        return
                    }

                    guard let results = request.results as? [VNRecognizedObjectObservation] else {
                        semaphore.signal()
                        return
                    }

                    let threshold: Float = 0.3

                    for observation in results {
                        if let topLabel = observation.labels.first,
                           topLabel.identifier == "person" || topLabel.identifier == "0",
                           topLabel.confidence > threshold {
                            let bbox = observation.boundingBox
                            let box = CGRect(
                                x: bbox.minX * CGFloat(imageWidth),
                                y: (1 - bbox.maxY) * CGFloat(imageHeight),
                                width: bbox.width * CGFloat(imageWidth),
                                height: bbox.height * CGFloat(imageHeight)
                            )
                            resultBoxes.append(box)
                        }
                    }
                    semaphore.signal()
                }

                request.imageCropAndScaleOption = .scaleFill

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    print("❌ YOLO11n Vision 실행 오류: \(error)")
                    semaphore.signal()
                }
            }
        }

        semaphore.wait()
        return resultBoxes
    }

    // MARK: - RTMPose 포즈 추정
    private func estimatePose(from image: UIImage, boundingBox: CGRect, using session: ORTSession, env: ORTEnv) -> [(point: CGPoint, confidence: Float)]? {
        guard let cgImage = image.cgImage else { return nil }

        // 바운딩 박스 영역 크롭
        guard let croppedImage = cropImage(cgImage, rect: boundingBox) else { return nil }

        // 192x256으로 리사이즈
        let inputSize = poseInputSize
        guard let resizedImage = resizeImage(croppedImage, targetSize: inputSize) else { return nil }

        // 이미지를 Float 배열로 변환
        let pixelData = preprocessImage(resizedImage, size: inputSize)

        do {
            // 입력 텐서 생성 - [1, 3, 256, 192]
            let inputShape: [NSNumber] = [1, 3, NSNumber(value: Int(inputSize.height)), NSNumber(value: Int(inputSize.width))]
            let inputTensor = try ORTValue(
                tensorData: NSMutableData(data: pixelData),
                elementType: .float,
                shape: inputShape
            )

            // 추론 실행
            let outputs = try session.run(
                withInputs: ["input": inputTensor],
                outputNames: ["simcc_x", "simcc_y"],
                runOptions: nil
            )

            guard let simccX = outputs["simcc_x"],
                  let simccY = outputs["simcc_y"] else {
                print("❌ RTMPose 출력(SimCC)을 찾을 수 없음")
                return nil
            }

            // SimCC 출력 파싱하여 키포인트 추출 (133개)
            let imageSize = image.size
            return parseRTMPoseSimCCOutput(simccX: simccX, simccY: simccY, boundingBox: boundingBox, imageSize: imageSize)

        } catch {
            print("❌ RTMPose 추론 오류: \(error)")
            return nil
        }
    }

    // MARK: - 이미지 전처리 헬퍼 함수들
    private func resizeImage(_ cgImage: CGImage, targetSize: CGSize) -> CGImage? {
        let width = Int(targetSize.width)
        let height = Int(targetSize.height)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        return context.makeImage()
    }

    private func cropImage(_ cgImage: CGImage, rect: CGRect) -> CGImage? {
        // 바운딩 박스를 충분히 확장 (손이 포함되도록 패딩 증가)
        // 🔥 손 인식 개선: 패딩을 0.2에서 0.4로 증가
        let padding: CGFloat = 0.4  // 40% 패딩으로 손까지 포함
        let expandedRect = CGRect(
            x: rect.minX - rect.width * padding,
            y: rect.minY - rect.height * padding,
            width: rect.width * (1 + 2 * padding),
            height: rect.height * (1 + 2 * padding)
        ).intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        return cgImage.cropping(to: expandedRect)
    }

    // 🔥 Accelerate 기반 고속 이미지 전처리
    private func preprocessImage(_ cgImage: CGImage, size: CGSize) -> Data {
        let width = Int(size.width)
        let height = Int(size.height)
        let pixelCount = width * height

        var rawData = [UInt8](repeating: 0, count: pixelCount * 4)

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return Data()
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 🔥 vDSP를 사용한 벡터화된 정규화 (ImageNet 평균/표준편차)
        var floatData = [Float](repeating: 0, count: pixelCount * 3)
        let mean: [Float] = [0.485, 0.456, 0.406]
        let std: [Float] = [0.229, 0.224, 0.225]

        // 각 채널별 처리 (병렬화)
        DispatchQueue.concurrentPerform(iterations: 3) { c in
            var channelData = [Float](repeating: 0, count: pixelCount)

            // RGBA에서 해당 채널 추출 (stride로 접근)
            for i in 0..<pixelCount {
                channelData[i] = Float(rawData[i * 4 + c])
            }

            // vDSP: /255.0 정규화
            var scale: Float = 1.0 / 255.0
            vDSP_vsmul(channelData, 1, &scale, &channelData, 1, vDSP_Length(pixelCount))

            // vDSP: (x - mean) 빼기
            var negMean = -mean[c]
            vDSP_vsadd(channelData, 1, &negMean, &channelData, 1, vDSP_Length(pixelCount))

            // vDSP: / std 나누기
            var invStd = 1.0 / std[c]
            vDSP_vsmul(channelData, 1, &invStd, &channelData, 1, vDSP_Length(pixelCount))

            // CHW 포맷으로 복사
            let offset = c * pixelCount
            for i in 0..<pixelCount {
                floatData[offset + i] = channelData[i]
            }
        }

        return Data(bytes: &floatData, count: floatData.count * MemoryLayout<Float>.size)
    }

    // MARK: - RTMPose SimCC 출력 파싱
    private func parseRTMPoseSimCCOutput(simccX: ORTValue, simccY: ORTValue, boundingBox: CGRect, imageSize: CGSize) -> [(point: CGPoint, confidence: Float)]? {
        // SimCC 출력 형식:
        // simcc_x: [1, num_keypoints, 384] - x 좌표 확률 분포
        // simcc_y: [1, num_keypoints, 512] - y 좌표 확률 분포

        guard let xData = try? simccX.tensorData() as NSData,
              let yData = try? simccY.tensorData() as NSData else { return nil }
        guard let xShape = try? simccX.tensorTypeAndShapeInfo().shape,
              let yShape = try? simccY.tensorTypeAndShapeInfo().shape else { return nil }

        let numKeypoints = xShape[1].intValue
        let xBins = xShape[2].intValue  // 384
        let yBins = yShape[2].intValue  // 512

        if numKeypoints != 133 {
            print("⚠️ 예상치 못한 키포인트 수: \(numKeypoints)")
            return nil
        }

        var keypoints: [(point: CGPoint, confidence: Float)] = []
        let xPointer = xData.bytes.bindMemory(to: Float.self, capacity: xData.length / MemoryLayout<Float>.size)
        let yPointer = yData.bytes.bindMemory(to: Float.self, capacity: yData.length / MemoryLayout<Float>.size)

        for i in 0..<numKeypoints {
            // x 좌표: argmax 찾기
            let xOffset = i * xBins
            var maxXIdx = 0
            var maxXVal: Float = -Float.infinity
            for j in 0..<xBins {
                let val = xPointer[xOffset + j]
                if val > maxXVal {
                    maxXVal = val
                    maxXIdx = j
                }
            }

            // y 좌표: argmax 찾기
            let yOffset = i * yBins
            var maxYIdx = 0
            var maxYVal: Float = -Float.infinity
            for j in 0..<yBins {
                let val = yPointer[yOffset + j]
                if val > maxYVal {
                    maxYVal = val
                    maxYIdx = j
                }
            }

            // SimCC 좌표를 픽셀 좌표로 변환
            // 384 bins -> 192 pixels, 512 bins -> 256 pixels (각각 2배 해상도)
            let xNorm = CGFloat(maxXIdx) / CGFloat(xBins) * poseInputSize.width
            let yNorm = CGFloat(maxYIdx) / CGFloat(yBins) * poseInputSize.height

            // 바운딩 박스 기준으로 변환 후 이미지 크기로 정규화 (0.0~1.0)
            let point = CGPoint(
                x: (boundingBox.minX + (xNorm / poseInputSize.width) * boundingBox.width) / imageSize.width,
                y: (boundingBox.minY + (yNorm / poseInputSize.height) * boundingBox.height) / imageSize.height
            )

            // 신뢰도: 두 확률의 평균
            let confidence = (maxXVal + maxYVal) / 2.0

            keypoints.append((point: point, confidence: confidence))

            // 🔍 손 키포인트 디버그 (91-132번)
            if i >= 91 && i <= 132 {
                if confidence < 0.3 {
                    let handName = i <= 111 ? "왼손" : "오른손"
                    let keypointIndex = i <= 111 ? i - 91 : i - 112
                    if keypointIndex % 5 == 0 {  // 5개마다 한 번만 로그
                        print("⚠️ \(handName) 키포인트 \(keypointIndex): 신뢰도 낮음 (\(String(format: "%.2f", confidence)))")
                    }
                }
            }
        }

        // 손 키포인트 요약 통계
        let leftHandConfidences = (91...111).compactMap { keypoints[$0].confidence }
        let rightHandConfidences = (112...132).compactMap { keypoints[$0].confidence }

        let leftHandAvg = leftHandConfidences.reduce(0, +) / Float(leftHandConfidences.count)
        let rightHandAvg = rightHandConfidences.reduce(0, +) / Float(rightHandConfidences.count)

        if leftHandAvg < 0.5 || rightHandAvg < 0.5 {
            print("📊 손 인식 평균 신뢰도 - 왼손: \(String(format: "%.2f", leftHandAvg)), 오른손: \(String(format: "%.2f", rightHandAvg))")
            if leftHandAvg < 0.3 || rightHandAvg < 0.3 {
                print("💡 손이 화면에서 잘렸거나 가려졌을 수 있습니다. 전체 신체가 프레임 안에 들어오도록 조정해보세요.")
            }
        }

        return keypoints
    }
}
