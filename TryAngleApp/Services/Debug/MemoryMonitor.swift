import Foundation

// MARK: - Memory Monitor
// ⚠️ DEPRECATED: SystemMonitor를 사용하세요
// 역할: 앱의 메모리 사용량을 측정하고 로깅합니다.

@available(*, deprecated, message: "Use SystemMonitor instead")
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
        // Redirect to SystemMonitor
        SystemMonitor.shared.logSystemStats(tag: tag)
    }

    /// 메모리 경고 체크 (임계값 초과 시 경고)
    func checkMemoryWarning(threshold: Double = 500) {
        SystemMonitor.shared.checkMemoryWarning(threshold: threshold)
    }

    /// 주요 컴포넌트별 메모리 체크 (앱 시작 시 호출)
    func logInitialMemoryBreakdown() {
        AppLogger.shared.info("========== 시스템 사용량 분석 ==========", category: "System")
        SystemMonitor.shared.logSystemStats(tag: "초기 상태")
        AppLogger.shared.info("=========================================", category: "System")
    }
}

// MARK: - 편의 함수
@available(*, deprecated, message: "Use SystemMonitor.shared.logSystemStats() instead")
func logMemory(_ tag: String) {
    SystemMonitor.shared.logSystemStats(tag: tag)
}
