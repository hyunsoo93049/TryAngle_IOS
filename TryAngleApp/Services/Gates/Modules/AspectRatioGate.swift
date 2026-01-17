import Foundation
import CoreGraphics
import UIKit

public class AspectRatioGate: GateModule {
    public let name = "비율"
    public let priority = 0
    
    public init() {}
    
    public func evaluate(context: GateContext) -> GateResult {
        // 1. 레퍼런스 없으면 패스 (비율 비교 불가)
        guard let reference = context.reference else {
            return GateResult(
                name: name,
                score: 1.0,
                threshold: 0.0,
                feedback: "레퍼런스 없음",
                icon: "📐",
                category: "aspect_ratio",
                debugInfo: "No Reference"
            )
        }
        
        // 2. 현재 비율 계산
        let currentSize = context.analysis.input.imageSize
        let currentRatio = CameraAspectRatio.detect(from: currentSize)
        let refRatio = reference.aspectRatio
        
        // 3. 비교
        let matched = currentRatio == refRatio
        let score: CGFloat = matched ? 1.0 : 0.0
        
        let feedback: String
        let debugInfo = "현재: \(currentRatio.displayName) vs 목표: \(refRatio.displayName)"
        
        if matched {
            feedback = "비율 일치"
        } else {
            feedback = "카메라 비율을 \(refRatio.displayName)로 변경하세요"
        }
        
        return GateResult(
            name: name,
            score: score,
            threshold: 1.0, // 반드시 일치해야 함 (1.0)
            feedback: feedback,
            icon: "📐",
            category: "aspect_ratio",
            debugInfo: debugInfo
        )
    }
}
