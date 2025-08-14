import Foundation
import SwiftUI

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var isMonitoring = false
    @Published var lastCaptureTime: Date?
    @Published var captureCount = 0
    @Published var uploadQueueCount = 0
    @Published var lastError: String?
    @Published var systemStatus = SystemStatus()
    
    struct SystemStatus {
        var isCameraAvailable = false
        var isTelegramConfigured = false
        var isNetworkAvailable = true
        var currentState = EventHub.SystemState.active
    }
    
    private init() {
        updateSystemStatus()
        startStatusMonitoring()
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        EventHub.shared.startMonitoring()
        isMonitoring = true
        
        Logger.shared.log("Monitoring started", level: .info)
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        EventHub.shared.stopMonitoring()
        isMonitoring = false
        
        Logger.shared.log("Monitoring stopped", level: .info)
    }
    
    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    func updateCaptureStats() {
        lastCaptureTime = Date()
        captureCount += 1
    }
    
    func updateUploadQueue(count: Int) {
        uploadQueueCount = count
    }
    
    func setError(_ error: String?) {
        lastError = error
        
        if let error = error {
            Logger.shared.log("Error: \(error)", level: .error)
        }
    }
    
    func clearError() {
        lastError = nil
    }
    
    private func updateSystemStatus() {
        systemStatus.isCameraAvailable = PermissionManager.shared.hasCameraPermission
        systemStatus.isTelegramConfigured = AppSettings.shared.telegramBotToken != nil && AppSettings.shared.telegramChatId != nil
        systemStatus.currentState = EventHub.shared.currentState
    }
    
    private func startStatusMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                self.updateSystemStatus()
            }
        }
    }
    
    func getStatusSummary() -> String {
        var summary = "SafeAway 状态\n"
        summary += "监控: \(isMonitoring ? "开启" : "关闭")\n"
        summary += "摄像头: \(systemStatus.isCameraAvailable ? "可用" : "不可用")\n"
        summary += "Telegram: \(systemStatus.isTelegramConfigured ? "已配置" : "未配置")\n"
        summary += "网络: \(systemStatus.isNetworkAvailable ? "在线" : "离线")\n"
        summary += "系统状态: \(systemStatus.currentState)\n"
        summary += "捕获次数: \(captureCount)\n"
        summary += "待上传: \(uploadQueueCount)\n"
        
        if let lastCapture = lastCaptureTime {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            summary += "最后捕获: \(formatter.string(from: lastCapture))\n"
        }
        
        if let error = lastError {
            summary += "错误: \(error)\n"
        }
        
        return summary
    }
}