import Foundation
import os.log

class Logger {
    static let shared = Logger()
    
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }
    
    private let subsystem = "com.safeaway.app"
    private let category = "SafeAway"
    private let osLog: OSLog
    private let logFileURL: URL
    private let dateFormatter: ISO8601DateFormatter
    private let queue = DispatchQueue(label: "com.safeaway.logger", qos: .utility)
    
    private init() {
        osLog = OSLog(subsystem: subsystem, category: category)
        dateFormatter = ISO8601DateFormatter()
        
        let logsDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs")
            .appendingPathComponent("SafeAway")
        
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        
        let timestamp = dateFormatter.string(from: Date())
        logFileURL = logsDirectory.appendingPathComponent("safeaway_\(timestamp).log")
    }
    
    func log(_ message: String, level: Level = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let logMessage = "[\(level.rawValue)] [\(fileName):\(line)] \(function) - \(message)"
        
        switch level {
        case .debug:
            os_log(.debug, log: osLog, "%{public}@", logMessage)
        case .info:
            os_log(.info, log: osLog, "%{public}@", logMessage)
        case .warning:
            os_log(.default, log: osLog, "%{public}@", logMessage)
        case .error:
            os_log(.error, log: osLog, "%{public}@", logMessage)
        }
        
        writeToFile(logMessage, level: level)
    }
    
    private func writeToFile(_ message: String, level: Level) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let timestamp = self.dateFormatter.string(from: Date())
            let logEntry: [String: Any] = [
                "timestamp": timestamp,
                "level": level.rawValue,
                "message": message
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: logEntry),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                
                let logLine = jsonString + "\n"
                
                if let data = logLine.data(using: .utf8) {
                    if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                        if let fileHandle = try? FileHandle(forWritingTo: self.logFileURL) {
                            fileHandle.seekToEndOfFile()
                            fileHandle.write(data)
                            fileHandle.closeFile()
                        }
                    } else {
                        try? data.write(to: self.logFileURL)
                    }
                }
            }
        }
    }
    
    func exportLogs() {
        let logsDirectory = logFileURL.deletingLastPathComponent()
        
        do {
            let _ = try FileManager.default.contentsOfDirectory(
                at: logsDirectory,
                includingPropertiesForKeys: nil
            )
            
            let exportURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
                .appendingPathComponent("SafeAway_Logs_\(Date().timeIntervalSince1970).zip")
            
            let coordinator = NSFileCoordinator()
            var error: NSError?
            
            coordinator.coordinate(writingItemAt: exportURL, options: .forReplacing, error: &error) { url in
                
            }
            
            if let error = error {
                log("Failed to export logs: \(error)", level: .error)
            } else {
                log("Logs exported to: \(exportURL.path)", level: .info)
            }
            
        } catch {
            log("Failed to export logs: \(error)", level: .error)
        }
    }
    
    func cleanOldLogs(daysToKeep: Int = 7) {
        queue.async {
            let logsDirectory = self.logFileURL.deletingLastPathComponent()
            let cutoffDate = Date().addingTimeInterval(-TimeInterval(daysToKeep * 24 * 60 * 60))
            
            do {
                let logFiles = try FileManager.default.contentsOfDirectory(
                    at: logsDirectory,
                    includingPropertiesForKeys: [.creationDateKey]
                )
                
                for fileURL in logFiles {
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                       let creationDate = attributes[.creationDate] as? Date,
                       creationDate < cutoffDate {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                }
            } catch {
                self.log("Failed to clean old logs: \(error)", level: .error)
            }
        }
    }
}