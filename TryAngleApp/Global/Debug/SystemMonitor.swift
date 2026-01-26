import Foundation
import UIKit
import Combine

// MARK: - System Monitor
/// 시스템 리소스 통합 모니터링 (메모리, CPU, 발열, 배터리)
/// MemoryMonitor + ThermalStateManager 통합 버전

class SystemMonitor: ObservableObject {
    
    static let shared = SystemMonitor()
    
    // MARK: - Published Properties
    @Published var currentThermalState: ProcessInfo.ThermalState = .nominal
    @Published var isLowPowerMode: Bool = false
    @Published var batteryLevel: Float = 1.0
    @Published var recommendedAnalysisInterval: TimeInterval = 0.016  // 기본 60fps
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var monitoringTimer: Timer?
    
    // MARK: - Initialization
    private init() {
        setupMonitoring()
        updateRecommendedInterval()
    }
    
    // MARK: - Monitoring Setup
    private func setupMonitoring() {
        // 🔥 발열 상태 모니터링
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateThermalState()
            }
            .store(in: &cancellables)
        
        // 🔋 저전력 모드 모니터링
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .sink { [weak self] _ in
                self?.updatePowerState()
            }
            .store(in: &cancellables)
        
        // 🔋 배터리 레벨 모니터링
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateBatteryLevel()
            }
            .store(in: &cancellables)
        
        // 초기값 설정
        updateThermalState()
        updatePowerState()
        updateBatteryLevel()
    }
    
    // MARK: - Memory Monitoring
    
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
    
    /// 메모리 사용 비율 (%)
    func memoryUsagePercentage() -> Double {
        let totalMemory = Double(ProcessInfo.processInfo.physicalMemory) / 1024.0 / 1024.0
        let usedMemory = currentMemoryUsage()
        return (usedMemory / totalMemory) * 100.0
    }
    
    // MARK: - CPU Monitoring
    
    /// 현재 CPU 사용률 (%)
    func currentCPUUsage() -> Double {
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = task_threads(mach_task_self_, &threadsList, &threadsCount)
        
        if threadsResult != KERN_SUCCESS {
            return 0
        }
        
        var totalUsage: Double = 0
        
        if let threads = threadsList {
            for index in 0..<Int(threadsCount) {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threads[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }
                
                guard infoResult == KERN_SUCCESS else { continue }
                
                let threadBasic = threadInfo as thread_basic_info
                if threadBasic.flags & TH_FLAGS_IDLE == 0 {
                    totalUsage += Double(threadBasic.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                }
            }
            
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
        }
        
        return totalUsage
    }
    
    /// 활성 스레드 수
    func activeThreadCount() -> Int {
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = task_threads(mach_task_self_, &threadsList, &threadsCount)
        
        if threadsResult == KERN_SUCCESS, let threads = threadsList {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)), vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
            return Int(threadsCount)
        }
        
        return 0
    }
    
    // MARK: - System Stats Logging
    
    /// 시스템 통계 로깅 (통합 포맷)
    func logSystemStats(tag: String = "SYSTEM") {
        let memoryMB = currentMemoryUsage()
        let memoryPercent = memoryUsagePercentage()
        let cpu = currentCPUUsage()
        let threads = activeThreadCount()
        let thermal = thermalStateString()
        let battery = batteryLevel > 0 ? Int(batteryLevel * 100) : -1
        
        let statsMessage = String(format: "SYSTEM STATS - Memory %.2fMB (%.2f%%), CPU: %.2f%%, Threads: %d, Battery: %d%%, Thermal: %@",
                                 memoryMB, memoryPercent, cpu, threads, battery, thermal)
        
        AppLogger.shared.debug(statsMessage, category: "System")
    }
    
    /// 메모리 경고 체크
    func checkMemoryWarning(threshold: Double = 500) {
        let usage = currentMemoryUsage()
        if usage > threshold {
            let message = String(format: "--- Memory Warning! Current: %.1fMB", usage)
            AppLogger.shared.warning(message, category: "System")
        }
    }
    
    /// 주기적 모니터링 시작 (선택사항)
    func startPeriodicMonitoring(interval: TimeInterval = 5.0) {
        stopPeriodicMonitoring()
        
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.logSystemStats(tag: "PERIODIC")
        }
        
        AppLogger.shared.info("-- System monitor started (interval: \(Int(interval))s)", category: "System")
    }
    
    /// 주기적 모니터링 중지
    func stopPeriodicMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    // MARK: - Thermal State Management
    
    private func updateThermalState() {
        DispatchQueue.main.async {
            self.currentThermalState = ProcessInfo.processInfo.thermalState
            self.updateRecommendedInterval()
            // Thermal state is logged in logSystemStats()
        }
    }
    
    private func updatePowerState() {
        DispatchQueue.main.async {
            self.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            self.updateRecommendedInterval()
            
            let status = self.isLowPowerMode ? "ON" : "OFF"
            AppLogger.shared.info("--- Low Power Mode: \(status)", category: "System")
        }
    }
    
    private func updateBatteryLevel() {
        DispatchQueue.main.async {
            self.batteryLevel = UIDevice.current.batteryLevel
            self.updateRecommendedInterval()
        }
    }
    
    // MARK: - 권장 분석 간격 계산
    private func updateRecommendedInterval() {
        let interval: TimeInterval
        
        switch currentThermalState {
        case .nominal:
            interval = 0.016  // 60fps
        case .fair:
            interval = 0.016  // 60fps
        case .serious:
            interval = 0.022  // 45fps
        case .critical:
            interval = 0.033  // 30fps
        @unknown default:
            interval = 0.033
        }
        
        // 🔋 저전력 모드나 저배터리면 제한
        if isLowPowerMode {
            recommendedAnalysisInterval = max(interval, 0.022)
        } else if batteryLevel > 0 && batteryLevel < 0.2 {
            recommendedAnalysisInterval = max(interval, 0.022)
        } else {
            recommendedAnalysisInterval = interval
        }
    }
    
    // MARK: - Thermal State (included in System Stats)
    // Thermal state changes are now logged as part of logSystemStats()
    
    private func thermalStateString() -> String {
        switch currentThermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
    
    // MARK: - Performance Optimization
    
    /// 분석 실행 가능 여부
    func shouldPerformAnalysis() -> Bool {
        return true  // 모든 프레임 분석, interval로만 조절
    }
    
    /// CoreML 옵션 최적화
    func getCoreMLFlags() -> UInt32 {
        if isLowPowerMode || currentThermalState == .serious || currentThermalState == .critical {
            return 1  // COREML_FLAG_ONLY_ENABLE_DEVICE_WITH_ANE
        }
        return 0
    }
}

// MARK: - 편의 함수 (하위 호환성)
func logMemory(_ tag: String) {
    SystemMonitor.shared.logSystemStats(tag: tag)
}
