//
//  PerformanceOptimizer.swift
//  온디바이스 실시간 분석 성능 최적화
//  작성일: 2025-12-06
//

import Foundation
import CoreImage
import Accelerate
import UIKit

// MARK: - 성능 최적화 매니저
class PerformanceOptimizer {

    static let shared = PerformanceOptimizer()

    // MARK: - 비동기 처리 큐

    /// Level 1: RTMPose 전용 큐 (높은 우선순위 - 매 프레임)
    let level1Queue = DispatchQueue(
        label: "com.tryangle.level1.pose",
        qos: .userInteractive,
        attributes: .concurrent
    )

    /// Level 2: Depth 전용 큐 (중간 우선순위 - 5프레임마다)
    let level2Queue = DispatchQueue(
        label: "com.tryangle.level2.depth",
        qos: .userInitiated
    )

    /// Level 3: Grounding DINO 전용 큐 (낮은 우선순위 - 30프레임마다)
    let level3Queue = DispatchQueue(
        label: "com.tryangle.level3.grounding",
        qos: .utility
    )

    /// 이미지 전처리 전용 큐 (Metal/Accelerate 활용)
    let preprocessQueue = DispatchQueue(
        label: "com.tryangle.preprocess",
        qos: .userInteractive,
        attributes: .concurrent
    )

    // MARK: - 이미지 버퍼 풀 (메모리 재사용)

    /// CGSize를 키로 사용하기 위한 래퍼 (iOS 18 미만 호환)
    private struct SizeKey: Hashable {
        let width: Int
        let height: Int

        init(_ size: CGSize) {
            self.width = Int(size.width)
            self.height = Int(size.height)
        }
    }

    private var imageBufferPool: [SizeKey: [CVPixelBuffer]] = [:]
    private let bufferPoolLock = NSLock()
    private let maxBuffersPerSize = 3

    // MARK: - 프레임 스킵 관리

    private var lastFrameHash: UInt64 = 0
    private var frameSkipCounter = 0
    private let maxConsecutiveSkips = 5  // 최대 연속 스킵

    // MARK: - 성능 통계

    private(set) var averageLevel1Time: Double = 0
    private(set) var averageLevel2Time: Double = 0
    private(set) var averageLevel3Time: Double = 0
    private var timeHistory: [String: [Double]] = [:]
    private let historySize = 30

    private init() {
        print("🚀 PerformanceOptimizer 초기화")
    }

    // MARK: - 이미지 버퍼 풀링

    /// 재사용 가능한 픽셀 버퍼 획득
    func acquireBuffer(size: CGSize) -> CVPixelBuffer? {
        bufferPoolLock.lock()
        defer { bufferPoolLock.unlock() }

        let key = SizeKey(size)
        if var buffers = imageBufferPool[key], !buffers.isEmpty {
            let buffer = buffers.removeFirst()
            imageBufferPool[key] = buffers
            return buffer
        }

        // 새 버퍼 생성
        var pixelBuffer: CVPixelBuffer?
        let options: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            options as CFDictionary,
            &pixelBuffer
        )

        return pixelBuffer
    }

    /// 버퍼 반환 (재사용)
    func releaseBuffer(_ buffer: CVPixelBuffer, size: CGSize) {
        bufferPoolLock.lock()
        defer { bufferPoolLock.unlock() }

        let key = SizeKey(size)
        if imageBufferPool[key] == nil {
            imageBufferPool[key] = []
        }

        if imageBufferPool[key]!.count < maxBuffersPerSize {
            imageBufferPool[key]!.append(buffer)
        }
    }

    // MARK: - Accelerate 기반 빠른 이미지 리사이즈

    /// vImage를 사용한 고속 이미지 리사이즈
    func fastResize(cgImage: CGImage, targetSize: CGSize) -> CGImage? {
        let width = Int(targetSize.width)
        let height = Int(targetSize.height)

        // 소스 버퍼 생성
        guard let srcData = cgImage.dataProvider?.data,
              let srcPointer = CFDataGetBytePtr(srcData) else {
            return nil
        }

        var srcBuffer = vImage_Buffer(
            data: UnsafeMutableRawPointer(mutating: srcPointer),
            height: vImagePixelCount(cgImage.height),
            width: vImagePixelCount(cgImage.width),
            rowBytes: cgImage.bytesPerRow
        )

        // 목적지 버퍼 생성
        guard let destData = malloc(width * height * 4) else {
            return nil
        }

        var destBuffer = vImage_Buffer(
            data: destData,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: width * 4
        )

        // 고속 리사이즈 (Lanczos 알고리즘)
        let error = vImageScale_ARGB8888(
            &srcBuffer,
            &destBuffer,
            nil,
            vImage_Flags(kvImageHighQualityResampling)
        )

        guard error == kvImageNoError else {
            free(destData)
            return nil
        }

        // CGImage 생성
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: destData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            free(destData)
            return nil
        }

        let result = context.makeImage()
        free(destData)
        return result
    }

    // MARK: - Accelerate 기반 빠른 정규화

    /// vDSP를 사용한 고속 이미지 정규화 (ImageNet 기준)
    func fastNormalize(cgImage: CGImage, size: CGSize) -> [Float]? {
        let width = Int(size.width)
        let height = Int(size.height)
        let pixelCount = width * height

        // 픽셀 데이터 추출
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: pixelCount * 4)

        // RGB 채널별 분리 및 정규화 (CHW 포맷)
        var result = [Float](repeating: 0, count: pixelCount * 3)

        // ImageNet 평균/표준편차
        let mean: [Float] = [0.485, 0.456, 0.406]
        let std: [Float] = [0.229, 0.224, 0.225]

        // vDSP를 사용한 벡터화된 연산
        for c in 0..<3 {
            var channelData = [Float](repeating: 0, count: pixelCount)

            // UInt8 → Float 변환 (수동 루프)
            for i in 0..<pixelCount {
                channelData[i] = Float(buffer[i * 4 + c])
            }

            // /255.0 정규화
            var scale: Float = 1.0 / 255.0
            vDSP_vsmul(channelData, 1, &scale, &channelData, 1, vDSP_Length(pixelCount))

            // (x - mean) / std
            var negMean = -mean[c]
            vDSP_vsadd(channelData, 1, &negMean, &channelData, 1, vDSP_Length(pixelCount))

            var invStd = 1.0 / std[c]
            vDSP_vsmul(channelData, 1, &invStd, &channelData, 1, vDSP_Length(pixelCount))

            // CHW 포맷으로 복사
            let offset = c * pixelCount
            for i in 0..<pixelCount {
                result[offset + i] = channelData[i]
            }
        }

        return result
    }

    // MARK: - 프레임 변화 감지 (스킵 결정)

    /// 프레임 변화량 계산 (움직임이 적으면 스킵 가능)
    func shouldSkipFrame(image: CGImage) -> Bool {
        // 썸네일로 빠르게 해시 계산
        let thumbSize = CGSize(width: 32, height: 32)
        guard let thumb = fastResize(cgImage: image, targetSize: thumbSize),
              let thumbData = thumb.dataProvider?.data,
              let ptr = CFDataGetBytePtr(thumbData) else {
            return false
        }

        // 간단한 해시 계산
        var hash: UInt64 = 0
        let length = CFDataGetLength(thumbData)
        let step = max(1, length / 64)

        for i in stride(from: 0, to: length, by: step) {
            hash = hash &* 31 &+ UInt64(ptr[i])
        }

        // 이전 프레임과 비교
        let isSimilar = (hash == lastFrameHash)
        lastFrameHash = hash

        // 연속 스킵 제한
        if isSimilar && frameSkipCounter < maxConsecutiveSkips {
            frameSkipCounter += 1
            return true
        }

        frameSkipCounter = 0
        return false
    }

    // MARK: - 성능 측정

    /// 실행 시간 측정 및 평균 계산
    func measureTime(level: String, block: () -> Void) -> Double {
        let start = CACurrentMediaTime()
        block()
        let elapsed = (CACurrentMediaTime() - start) * 1000  // ms

        // 히스토리 업데이트
        if timeHistory[level] == nil {
            timeHistory[level] = []
        }
        timeHistory[level]!.append(elapsed)
        if timeHistory[level]!.count > historySize {
            timeHistory[level]!.removeFirst()
        }

        // 평균 계산
        let average = timeHistory[level]!.reduce(0, +) / Double(timeHistory[level]!.count)

        switch level {
        case "level1":
            averageLevel1Time = average
        case "level2":
            averageLevel2Time = average
        case "level3":
            averageLevel3Time = average
        default:
            break
        }

        return elapsed
    }

    /// 성능 리포트
    func getPerformanceReport() -> String {
        return """
        📊 성능 리포트:
        - Level 1 (RTMPose): \(String(format: "%.1f", averageLevel1Time))ms
        - Level 2 (Depth): \(String(format: "%.1f", averageLevel2Time))ms
        - Level 3 (Grounding): \(String(format: "%.1f", averageLevel3Time))ms
        - 총 프레임 시간: \(String(format: "%.1f", averageLevel1Time + averageLevel2Time/5 + averageLevel3Time/30))ms
        """
    }
}

// MARK: - 동적 프레임 스킵 전략
class AdaptiveFrameSkipper {

    private let thermalManager = ThermalStateManager()

    /// 현재 상태에 따른 Level별 실행 주기
    /// 🔧 Level 3 (Grounding DINO) 주기 단축하여 더 정교한 감지
    func getFrameIntervals() -> (level1: Int, level2: Int, level3: Int) {
        switch thermalManager.currentThermalState {
        case .nominal:
            // 정상: 최대 성능 (🔧 Level 3: 30 → 10)
            return (level1: 1, level2: 3, level3: 10)

        case .fair:
            // 약간 따뜻: 약간 느리게 (🔧 Level 3: 30 → 15)
            return (level1: 1, level2: 5, level3: 15)

        case .serious:
            // 뜨거움: Level 2, 3 주기 증가
            return (level1: 2, level2: 8, level3: 30)

        case .critical:
            // 매우 뜨거움: 모든 주기 증가
            return (level1: 3, level2: 15, level3: 60)

        @unknown default:
            return (level1: 2, level2: 8, level3: 30)
        }
    }

    /// Level별 실행 여부 결정
    func shouldExecute(level: Int, frameCount: Int) -> Bool {
        let intervals = getFrameIntervals()

        switch level {
        case 1:
            return frameCount % intervals.level1 == 0
        case 2:
            return frameCount % intervals.level2 == 0
        case 3:
            return frameCount % intervals.level3 == 0
        default:
            return true
        }
    }
}

// MARK: - 비동기 파이프라인 실행기
class AsyncPipeline {

    typealias Level1Result = (face: FaceAnalysisResult?, pose: PoseAnalysisResult?)
    typealias Level2Result = V15DepthResult?  // 🔥 Depth Anything ML 기반
    typealias Level3Result = CGRect?

    private let optimizer = PerformanceOptimizer.shared

    /// 모든 레벨 병렬 실행
    func executeParallel(
        image: UIImage,
        frameCount: Int,
        level1Handler: @escaping (UIImage) -> Level1Result,
        level2Handler: @escaping (CGRect?) -> Level2Result,
        level3Handler: @escaping (CIImage) -> Level3Result,
        completion: @escaping (Level1Result, Level2Result, Level3Result) -> Void
    ) {
        let group = DispatchGroup()

        var level1Result: Level1Result = (nil, nil)
        var level2Result: Level2Result = nil
        var level3Result: Level3Result = nil

        // Level 1: RTMPose (매 프레임)
        group.enter()
        optimizer.level1Queue.async {
            let _ = self.optimizer.measureTime(level: "level1") {
                level1Result = level1Handler(image)
            }
            group.leave()
        }

        // Level 2: Depth (5프레임마다)
        if frameCount % 5 == 0 {
            group.enter()
            optimizer.level2Queue.async {
                let _ = self.optimizer.measureTime(level: "level2") {
                    level2Result = level2Handler(level1Result.face?.faceRect)
                }
                group.leave()
            }
        }

        // Level 3: Grounding DINO (30프레임마다)
        if frameCount % 30 == 0 {
            if let ciImage = CIImage(image: image) {
                group.enter()
                optimizer.level3Queue.async {
                    let _ = self.optimizer.measureTime(level: "level3") {
                        level3Result = level3Handler(ciImage)
                    }
                    group.leave()
                }
            }
        }

        // 모든 결과 수집 후 콜백
        group.notify(queue: .main) {
            completion(level1Result, level2Result, level3Result)
        }
    }
}
