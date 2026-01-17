import Foundation

// MARK: - Memory Monitor
// 역할: 앱의 메모리 사용량을 측정하고 로깅합니다.

class MemoryMonitor {

    static let shared = MemoryMonitor()

    private init() {}

    /// 현재 메모리 사용량 (MB)
    func currentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0
        }
        return 0
    }

    /// 메모리 사용량 로깅
    func logMemory(tag: String) {
        let usage = currentMemoryUsage()
        print("📊 [\(tag)] 메모리: \(String(format: "%.1f", usage)) MB")
    }

    /// 메모리 경고 체크 (임계값 초과 시 경고)
    func checkMemoryWarning(threshold: Double = 500) {
        let usage = currentMemoryUsage()
        if usage > threshold {
            print("⚠️🔴 메모리 경고! 현재: \(String(format: "%.1f", usage)) MB (임계값: \(threshold) MB)")
        }
    }

    /// 주요 컴포넌트별 메모리 체크 (앱 시작 시 호출)
    func logInitialMemoryBreakdown() {
        print("========== 메모리 사용량 분석 ==========")
        logMemory(tag: "현재 총 사용량")
        print("=========================================")
    }
}

// MARK: - 편의 함수
func logMemory(_ tag: String) {
    MemoryMonitor.shared.logMemory(tag: tag)
}
