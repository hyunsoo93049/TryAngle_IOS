//
//  DepthAnythingCoreML.swift
//  Depth Anything CoreML Integration
//  작성일: 2025-12-05
//

import Foundation
import CoreML
import Vision
import UIKit

// MARK: - Depth Anything CoreML Wrapper
class DepthAnythingCoreML {

    private var model: VNCoreMLModel?
    private let modelType: ModelType

    // 🔥 메모리 최적화: CIContext 싱글톤 (약 100MB 절약)
    private static let sharedContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false
    ])

    // 🔥 동시 실행 방지 (메모리 폭발 방지)
    private var isProcessing = false
    private let processingQueue = DispatchQueue(label: "depth.processing", qos: .userInitiated)

    enum ModelType {
        case small
        case base

        var modelName: String {
            switch self {
            case .small: return "DepthAnythingV2SmallF16"
            case .base: return "DepthAnythingV2SmallF16"  // 같은 모델 사용
            }
        }
    }

    init(modelType: ModelType = .small) {
        self.modelType = modelType
        setupModel()
    }

    // MARK: - 모델 설정
    private func setupModel() {
        // 방법 1: Apple 공식 CoreML 모델 사용 (다운로드 필요)
        // https://huggingface.co/apple/coreml-depth-anything-v2-small

        guard let modelURL = Bundle.main.url(forResource: modelType.modelName, withExtension: "mlmodelc") else {
            print("❌ Depth Anything 모델 파일을 찾을 수 없습니다")
            print("   다운로드: https://huggingface.co/apple/coreml-depth-anything-v2-small")
            return
        }

        do {
            let mlModel = try MLModel(contentsOf: modelURL)
            model = try VNCoreMLModel(for: mlModel)
            print("✅ Depth Anything CoreML 모델 로드 성공")
        } catch {
            print("❌ Depth Anything 모델 로드 실패: \(error)")
        }
    }

    // MARK: - 깊이 추정
    func estimateDepth(from image: UIImage, completion: @escaping (Result<V15DepthResult, Error>) -> Void) {
        // 🔥 동시 실행 방지 (이미 처리 중이면 스킵)
        guard !isProcessing else {
            print("⏭️ Depth Anything: 이미 처리 중 - 스킵")
            return
        }

        guard let model = model else {
            print("❌ Depth Anything: 모델이 로드되지 않음")
            completion(.failure(DepthError.modelNotLoaded))
            return
        }

        isProcessing = true

        // 🔥 메모리 최적화: 이미지 다운샘플링 (518x518로 리사이즈)
        let targetSize = CGSize(width: 518, height: 518)
        guard let resizedImage = image.resized(to: targetSize),
              let cgImage = resizedImage.cgImage else {
            print("❌ Depth Anything: 이미지 리사이즈 실패")
            completion(.failure(DepthError.invalidImage))
            return
        }

        // Vision 요청 생성
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            defer {
                self?.isProcessing = false  // 🔥 처리 완료 플래그
            }

            if let error = error {
                print("❌ Depth Anything Vision 에러: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            // 🔧 디버그: 결과 타입 확인
            if let results = request.results {
                print("🔍 Depth Anything 결과 타입: \(type(of: results)), 개수: \(results.count)")
                if let first = results.first {
                    print("🔍 첫 번째 결과 타입: \(type(of: first))")
                }
            }

            // 방법 1: VNCoreMLFeatureValueObservation (MLMultiArray 출력)
            if let results = request.results as? [VNCoreMLFeatureValueObservation],
               let depthMap = results.first?.featureValue.multiArrayValue {
                print("✅ Depth Anything: MLMultiArray 출력 사용")
                guard let strongSelf = self else { return }
                let result = strongSelf.processDepthMap(depthMap, originalImage: image)
                completion(.success(result))
                return
            }

            // 방법 2: VNPixelBufferObservation (CVPixelBuffer 출력 - Apple 모델)
            if let results = request.results as? [VNPixelBufferObservation],
               let pixelBuffer = results.first?.pixelBuffer {
                print("✅ Depth Anything: PixelBuffer 출력 사용")
                guard let strongSelf = self else { return }
                let result = strongSelf.processPixelBuffer(pixelBuffer, originalImage: image)
                completion(.success(result))
                return
            }

            // 방법 3: VNCoreMLFeatureValueObservation에서 다른 타입 시도
            if let results = request.results as? [VNCoreMLFeatureValueObservation],
               let first = results.first {
                print("🔍 FeatureValue 타입: \(first.featureValue.type.rawValue)")
                // 이미지 출력일 수도 있음
                if let imageBuffer = first.featureValue.imageBufferValue {
                    print("✅ Depth Anything: ImageBuffer 출력 사용")
                    guard let strongSelf = self else { return }
                    let result = strongSelf.processPixelBuffer(imageBuffer, originalImage: image)
                    completion(.success(result))
                    return
                }
            }

            print("❌ Depth Anything: 지원하지 않는 출력 형식")
            completion(.failure(DepthError.processingFailed))
        }

        // 입력 이미지 크기 설정 (518x518)
        request.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop

        // 요청 실행 (메모리 최적화)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            autoreleasepool {
                // 🔥 CIContext 옵션 제거 (Vision이 자체적으로 관리)
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([request])
                } catch {
                    print("❌ Depth Anything perform 에러: \(error.localizedDescription)")
                    self?.isProcessing = false  // 에러 시에도 플래그 해제
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - PixelBuffer 처리 (Apple CoreML 모델용)
    private func processPixelBuffer(_ pixelBuffer: CVPixelBuffer, originalImage: UIImage) -> V15DepthResult {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        var foregroundDepth: Float = 0
        var backgroundDepth: Float = 0
        var foregroundCount = 0
        var backgroundCount = 0

        // Float32 또는 Float16 데이터 처리
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        print("🔍 PixelBuffer 형식: \(pixelFormat), 크기: \(width)x\(height)")

        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

            // 상단 1/3 (배경)
            for y in 0..<(height/3) {
                for x in 0..<width {
                    let offset = y * bytesPerRow + x * MemoryLayout<Float>.size
                    let value = baseAddress.load(fromByteOffset: offset, as: Float.self)
                    if !value.isNaN && !value.isInfinite {
                        backgroundDepth += value
                        backgroundCount += 1
                    }
                }
            }

            // 하단 1/4 (전경)
            for y in (3*height/4)..<height {
                for x in 0..<width {
                    let offset = y * bytesPerRow + x * MemoryLayout<Float>.size
                    let value = baseAddress.load(fromByteOffset: offset, as: Float.self)
                    if !value.isNaN && !value.isInfinite {
                        foregroundDepth += value
                        foregroundCount += 1
                    }
                }
            }
        }

        // 평균 계산
        let avgBackground = backgroundCount > 0 ? backgroundDepth / Float(backgroundCount) : 0
        let avgForeground = foregroundCount > 0 ? foregroundDepth / Float(foregroundCount) : 0

        // 압축감 지수 계산
        let depthRange = abs(avgBackground - avgForeground)
        let compressionIndex = 1.0 - min(depthRange * 2, 1.0)

        print("🔍 Depth: 배경=\(avgBackground), 전경=\(avgForeground), 압축감=\(compressionIndex)")

        let cameraType = determineCameraType(compression: compressionIndex)

        return V15DepthResult(
            depthImage: nil,
            compressionIndex: compressionIndex,
            cameraType: cameraType
        )
    }

    // MARK: - 깊이맵 처리
    private func processDepthMap(_ depthMap: MLMultiArray, originalImage: UIImage) -> V15DepthResult {
        // 압축감 계산
        let compressionIndex = calculateCompression(from: depthMap)

        // 카메라 타입 판정
        let cameraType = determineCameraType(compression: compressionIndex)

        // 깊이맵을 이미지로 변환 (옵션 - 디버깅용)
        // 🔥 메모리 절약을 위해 기본적으로 nil 반환
        // let depthImage = convertToImage(depthMap)

        return V15DepthResult(
            depthImage: nil,  // 🔥 메모리 최적화: 필요시에만 생성
            compressionIndex: compressionIndex,
            cameraType: cameraType
        )
    }

    // MARK: - 압축감 계산
    private func calculateCompression(from depthMap: MLMultiArray) -> Float {
        // 깊이맵에서 전경과 배경의 깊이 차이 계산
        let shape = depthMap.shape
        let height = shape[0].intValue
        let width = shape[1].intValue

        var foregroundDepth: Float = 0
        var backgroundDepth: Float = 0

        // 상단 1/3 (배경)
        for y in 0..<(height/3) {
            for x in 0..<width {
                let index = y * width + x
                backgroundDepth += depthMap[index].floatValue
            }
        }
        backgroundDepth /= Float(height * width / 3)

        // 하단 1/4 (전경)
        for y in (3*height/4)..<height {
            for x in 0..<width {
                let index = y * width + x
                foregroundDepth += depthMap[index].floatValue
            }
        }
        foregroundDepth /= Float(height * width / 4)

        // 압축감 지수 (0=광각, 1=망원)
        let depthRange = abs(backgroundDepth - foregroundDepth)
        let compressionIndex = 1.0 - min(depthRange * 2, 1.0)

        return compressionIndex
    }

    // MARK: - 카메라 타입 판정
    private func determineCameraType(compression: Float) -> V15CameraType {
        switch compression {
        case ..<0.3:
            return .wide
        case 0.3..<0.5:
            return .normal
        case 0.5..<0.7:
            return .semiTele
        default:
            return .telephoto
        }
    }

    // MARK: - 깊이맵을 이미지로 변환
    private func convertToImage(_ depthMap: MLMultiArray) -> UIImage? {
        let shape = depthMap.shape
        let height = shape[0].intValue
        let width = shape[1].intValue

        // 정규화
        var minDepth = Float.greatestFiniteMagnitude
        var maxDepth = Float.leastNormalMagnitude

        for i in 0..<depthMap.count {
            let value = depthMap[i].floatValue
            minDepth = min(minDepth, value)
            maxDepth = max(maxDepth, value)
        }

        let range = maxDepth - minDepth

        // 그레이스케일 이미지 생성
        var pixels = [UInt8]()
        for i in 0..<depthMap.count {
            let normalized = (depthMap[i].floatValue - minDepth) / range
            pixels.append(UInt8(normalized * 255))
        }

        // CGImage 생성
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - 결과 구조체 (v1.5 전용 - 기존 DepthResult와 충돌 방지)
// 🔥 MLMultiArray 제거하여 메모리 최적화 (약 4MB 절약)
struct V15DepthResult {
    let depthImage: UIImage?       // 시각화용 (옵션)
    let compressionIndex: Float    // 압축감 지수 (0=광각, 1=망원)
    let cameraType: V15CameraType  // 추정 카메라 타입
}

enum V15CameraType {
    case wide       // 광각 (24-35mm)
    case normal     // 표준 (35-50mm)
    case semiTele   // 준망원 (50-85mm)
    case telephoto  // 망원 (85mm+)

    var description: String {
        switch self {
        case .wide: return "광각"
        case .normal: return "표준"
        case .semiTele: return "준망원"
        case .telephoto: return "망원"
        }
    }

    var recommendation: String? {
        switch self {
        case .wide: return "더 가까이 접근하거나 망원 렌즈 사용"
        case .normal: return nil
        case .semiTele: return nil
        case .telephoto: return "강한 압축감 - 광각 렌즈 고려"
        }
    }
}

// MARK: - 에러 타입
enum DepthError: LocalizedError {
    case modelNotLoaded
    case invalidImage
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Depth Anything 모델이 로드되지 않았습니다"
        case .invalidImage:
            return "유효하지 않은 이미지입니다"
        case .processingFailed:
            return "깊이 추정 처리 실패"
        }
    }
}

// MARK: - 싱글톤 (메모리 절약)
extension DepthAnythingCoreML {
    static let shared = DepthAnythingCoreML(modelType: .small)
}

// MARK: - UIImage 리사이즈 Extension (메모리 효율적)
extension UIImage {
    func resized(to targetSize: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // @1x로 강제 (메모리 절약)

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}