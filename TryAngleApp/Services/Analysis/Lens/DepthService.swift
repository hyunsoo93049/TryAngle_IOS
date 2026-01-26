import Foundation
import UIKit
import CoreVideo

// MARK: - Depth Service

public class DepthService: DepthEstimator {
    // MARK: - Singleton
    public static let shared = DepthService()

    public let name = "DepthAnything"
    public var isEnabled: Bool = true

    // 🔧 수정: computed property로 변경 (항상 최신 shared 인스턴스 사용)
    private var core: DepthAnythingCoreML {
        DepthAnythingCoreML.shared
    }

    public init() {
        // 초기화 시 아무것도 하지 않음 - core는 사용 시점에 접근
    }
    
    public func initialize() async throws {
        // DepthAnythingCoreML initializes model on init or first use mostly.
        // We can force a check or just assume it's ready.
        // The existing class has a `setupModel()` called in init.
        print("✅ DepthService initialized (Wrapper around DepthAnythingCoreML)")
    }
    
    public func estimate(input: FrameInput) async throws -> DepthEstimationResult? {
        guard isEnabled else { return nil }
        
        guard let image = input.image else {
            return nil
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            core.estimateDepth(from: image) { result in
                switch result {
                case .success(let v15Result):
                    // Convert V15DepthResult to DepthEstimationResult
                    // V15DepthResult usually generates stats, we might not get raw map unless modified.
                    // The current `estimateDepth` returns V15DepthResult which has `compressionIndex` but nil depthImage/map by default for optimization.
                    
                    let depthResult = DepthEstimationResult(
                        timestamp: input.timestamp,
                        depthMap: nil, // Current implementation optimizes this out
                        compressionIndex: v15Result.compressionIndex
                    )
                    continuation.resume(returning: depthResult)
                    
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
