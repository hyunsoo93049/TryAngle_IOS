import Foundation
import os.log

// MARK: - App Logger
/// 앱 전체에서 사용하는 통합 로깅 시스템
/// OSLog를 기반으로 구조화된 로깅 제공

public enum LogLevel {
    case debug
    case info
    case warning
    case error
    case fault
    
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .fault: return .fault
        }
    }
    
    /// 로그 레벨 문자열 (8자리 왼쪽 정렬용)
    var displayName: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        }
    }
}

public class AppLogger {
    // MARK: - Singleton
    public static let shared = AppLogger()
    
    // MARK: - Configuration
    private let subsystem = Bundle.main.bundleIdentifier ?? "com.tryangle.app"
    private var loggers: [String: Logger] = [:]
    private let loggersLock = NSLock()
    
    // 로깅 활성화 플래그
    public var isEnabled: Bool = true
    public var logToConsole: Bool = true  // Xcode 콘솔에 print 출력
    public var logToFile: Bool = true     // 파일 로깅 활성화
    public var minLevel: LogLevel = .debug  // 최소 로그 레벨
    
    // 파일 로깅 설정
    private let logDirectory: URL
    private var currentLogFile: URL
    private let fileManager = FileManager.default
    private let fileLock = NSLock()
    private let maxLogFiles = 3  // 최근 3일 치 보관
    private var lastRotationDate: Date?
    
    // MARK: - Initialization
    private init() {
        // 로그 디렉토리 설정 (Documents/Logs/)
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        logDirectory = documentsPath.appendingPathComponent("Logs", isDirectory: true)
        
        // 로그 파일명: app_YYMMDD.log
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyMMdd"
        let dateString = dateFormatter.string(from: Date())
        currentLogFile = logDirectory.appendingPathComponent("app_\(dateString).log")
        
        // 디렉토리 생성
        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        
        // 오래된 로그 파일 정리
        cleanupOldLogs()
        
        // 자정 로테이션 타이머 설정
        scheduleRotationAtMidnight()
    }
    
    /// 카테고리별 Logger 가져오기 (없으면 생성)
    private func getLogger(for category: String) -> Logger? {
        loggersLock.lock()
        defer { loggersLock.unlock() }
        
        if let logger = loggers[category] {
            return logger
        }
        
        if #available(iOS 14.0, *) {
            let logger = Logger(subsystem: subsystem, category: category)
            loggers[category] = logger
            return logger
        }
        
        return nil
    }
    
    // MARK: - Public Logging Methods
    
    /// 일반 로그 (카테고리, 레벨 지정)
    public func log(_ message: String, 
                   category: String = "App", 
                   level: LogLevel = .info,
                   file: String = #file,
                   function: String = #function,
                   line: Int = #line) {
        guard isEnabled else { return }
        
        let fileName = (file as NSString).lastPathComponent
        let formattedMessage = formatMessage(message, 
                                            category: category, 
                                            level: level, 
                                            file: fileName, 
                                            function: function, 
                                            line: line)
        
        // OSLog로 로깅
        if #available(iOS 14.0, *), let logger = getLogger(for: category) {
            logger.log(level: level.osLogType, "\(formattedMessage)")
        } else {
            // iOS 14 미만 fallback
            os_log("%{public}@", log: OSLog(subsystem: subsystem, category: category), 
                   type: level.osLogType, formattedMessage)
        }
        
        // 콘솔에도 출력 (개발 중 편의성)
        if logToConsole {
            print(formattedMessage)
        }
        
        // 파일에도 저장
        if logToFile {
            writeToFile(formattedMessage)
        }
    }
    
    /// Debug 로그
    public func debug(_ message: String, category: String = "App", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, category: category, level: .debug, file: file, function: function, line: line)
    }
    
    /// Info 로그
    public func info(_ message: String, category: String = "App", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, category: category, level: .info, file: file, function: function, line: line)
    }
    
    /// Warning 로그
    public func warning(_ message: String, category: String = "App", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, category: category, level: .warning, file: file, function: function, line: line)
    }
    
    /// Error 로그
    public func error(_ message: String, category: String = "App", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, category: category, level: .error, file: file, function: function, line: line)
    }
    
    /// Fault 로그 (심각한 오류)
    public func fault(_ message: String, category: String = "App", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, category: category, level: .fault, file: file, function: function, line: line)
    }
    
    // MARK: - Performance Logging
    
    /// 성능 측정 로그 (시간 측정)
    public func measure<T>(_ operation: String, 
                          category: String = "Performance",
                          block: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            info("⏱️ \(operation): \(String(format: "%.1fms", elapsed))", category: category)
        }
        return try block()
    }
    
    /// 비동기 성능 측정
    public func measureAsync<T>(_ operation: String,
                               category: String = "Performance",
                               block: () async throws -> T) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            info("⏱️ \(operation): \(String(format: "%.1fms", elapsed))", category: category)
        }
        return try await block()
    }
    
    // MARK: - Private Helpers
    
    /// 타임스탐프 포맷: YY/MM/DD HH:mm:ss.SSS
    private func formatTimestamp(_ date: Date = Date()) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        
        let year = String(format: "%02d", (components.year ?? 0) % 100)
        let month = String(format: "%02d", components.month ?? 0)
        let day = String(format: "%02d", components.day ?? 0)
        let hour = String(format: "%02d", components.hour ?? 0)
        let minute = String(format: "%02d", components.minute ?? 0)
        let second = String(format: "%02d", components.second ?? 0)
        let milliseconds = String(format: "%03d", (components.nanosecond ?? 0) / 1_000_000)
        
        return "\(year)/\(month)/\(day) \(hour):\(minute):\(second).\(milliseconds)"
    }
    
    /// 로그 메시지 포맷: YY/MM/DD HH:mm:ss.SSS LEVEL    [CATEGORY]    MESSAGE
    private func formatMessage(_ message: String,
                              category: String,
                              level: LogLevel,
                              file: String,
                              function: String,
                              line: Int) -> String {
        let timestamp = formatTimestamp()
        let levelName = level.displayName.padding(toLength: 8, withPad: " ", startingAt: 0)
        let categoryTag = "[\(category)]"
        
        #if DEBUG
        // Debug 빌드: 상세 정보 포함
        return "\(timestamp) \(levelName) \(categoryTag) \(message) (\(file):\(line))"
        #else
        // Release 빌드: 간소화
        return "\(timestamp) \(levelName) \(categoryTag) \(message)"
        #endif
    }
    
    // MARK: - File Logging
    
    /// 파일에 로그 작성
    private func writeToFile(_ message: String) {
        fileLock.lock()
        defer { fileLock.unlock() }
        
        // 자정이 지났는지 확인하고 로테이션
        checkAndRotateIfNeeded()
        
        guard let data = (message + "\n").data(using: .utf8) else { return }
        
        // 파일이 없으면 생성, 있으면 append
        if fileManager.fileExists(atPath: currentLogFile.path) {
            if let fileHandle = try? FileHandle(forWritingTo: currentLogFile) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                try? fileHandle.close()
            }
        } else {
            try? data.write(to: currentLogFile, options: .atomic)
        }
    }
    
    /// 자정이 지났는지 확인하고 로그 로테이션
    private func checkAndRotateIfNeeded() {
        let calendar = Calendar.current
        let now = Date()
        
        // 마지막 로테이션 날짜와 오늘 날짜 비교
        if let lastRotation = lastRotationDate {
            let lastDay = calendar.startOfDay(for: lastRotation)
            let today = calendar.startOfDay(for: now)
            
            if today > lastDay {
                rotateLogFile()
            }
        } else {
            lastRotationDate = now
        }
    }
    
    /// 로그 파일 로테이션 (새로운 날짜의 파일 생성)
    private func rotateLogFile() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyMMdd"
        let dateString = dateFormatter.string(from: Date())
        
        currentLogFile = logDirectory.appendingPathComponent("app_\(dateString).log")
        lastRotationDate = Date()
        
        // 오래된 로그 파일 정리
        cleanupOldLogs()
    }
    
    /// 최근 3일 이전 로그 파일 삭제
    private func cleanupOldLogs() {
        guard let files = try? fileManager.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else {
            return
        }
        
        // 로그 파일만 필터링 (app_*.log)
        let logFiles = files.filter { $0.lastPathComponent.hasPrefix("app_") && $0.pathExtension == "log" }
        
        // 생성 날짜 기준 정렬 (최신순)
        let sortedFiles = logFiles.sorted { file1, file2 in
            guard let date1 = try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  let date2 = try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate else {
                return false
            }
            return date1 > date2
        }
        
        // 최근 3개 파일 제외하고 삭제
        if sortedFiles.count > maxLogFiles {
            for fileToDelete in sortedFiles.dropFirst(maxLogFiles) {
                try? fileManager.removeItem(at: fileToDelete)
            }
        }
    }
    
    /// 자정에 로그 로테이션 수행하도록 타이머 설정
    private func scheduleRotationAtMidnight() {
        let calendar = Calendar.current
        let now = Date()
        
        // 다음 자정 시간 계산
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let nextMidnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: tomorrow) else {
            return
        }
        
        let timeInterval = nextMidnight.timeIntervalSince(now)
        
        // 타이머 설정 (자정에 실행)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeInterval) { [weak self] in
            self?.fileLock.lock()
            self?.rotateLogFile()
            self?.fileLock.unlock()
            
            // 다음 날 자정을 위해 재귀 호출
            self?.scheduleRotationAtMidnight()
        }
    }
    
    /// 로그 디렉토리 경로 반환
    public func getLogDirectory() -> URL {
        return logDirectory
    }
    
    /// 현재 로그 파일 경로 반환
    public func getCurrentLogFile() -> URL {
        return currentLogFile
    }
    
    /// 모든 로그 파일 목록 반환
    public func getAllLogFiles() -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return []
        }
        return files.filter { $0.lastPathComponent.hasPrefix("app_") && $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}

// MARK: - Global Convenience Functions (Optional)
/// 전역 함수로 간편하게 사용 가능

public func logDebug(_ message: String, category: String = "App") {
    AppLogger.shared.debug(message, category: category)
}

public func logInfo(_ message: String, category: String = "App") {
    AppLogger.shared.info(message, category: category)
}

public func logWarning(_ message: String, category: String = "App") {
    AppLogger.shared.warning(message, category: category)
}

public func logError(_ message: String, category: String = "App") {
    AppLogger.shared.error(message, category: category)
}
