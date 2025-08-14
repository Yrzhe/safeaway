import Foundation
import SwiftUI

enum Language: String, CaseIterable {
    case english = "en"
    case chinese = "zh"
    
    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .chinese:
            return "中文"
        }
    }
}

// Thread-safe bundle manager
class BundleManager {
    static let shared = BundleManager()
    private var currentBundle: Bundle = Bundle.main
    private let queue = DispatchQueue(label: "com.safeaway.localization", attributes: .concurrent)
    
    private init() {
        updateBundle()
    }
    
    func updateBundle() {
        let savedLanguage = UserDefaults.standard.string(forKey: "AppLanguage") ?? "en"
        
        queue.async(flags: .barrier) {
            if let path = Bundle.main.path(forResource: savedLanguage, ofType: "lproj"),
               let languageBundle = Bundle(path: path) {
                self.currentBundle = languageBundle
            } else {
                self.currentBundle = Bundle.main
            }
        }
    }
    
    func localizedString(for key: String) -> String {
        var result = ""
        queue.sync {
            result = currentBundle.localizedString(forKey: key, value: nil, table: nil)
        }
        return result
    }
}

// ObservableObject for SwiftUI views
@MainActor
class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: Language {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "AppLanguage")
            BundleManager.shared.updateBundle()
        }
    }
    
    private init() {
        let savedLanguage = UserDefaults.standard.string(forKey: "AppLanguage") ?? "en"
        self.currentLanguage = Language(rawValue: savedLanguage) ?? .english
    }
    
    func setLanguage(_ language: Language) {
        currentLanguage = language
    }
}

// Global function for easy access - thread-safe
func LocalizedString(_ key: String) -> String {
    return BundleManager.shared.localizedString(for: key)
}

// Convenient accessor - thread-safe
struct L {
    static subscript(key: String) -> String {
        return LocalizedString(key)
    }
}

// Localization keys
struct LocalizedStringKey {
    static let appName = "app_name"
    static let startMonitoring = "start_monitoring"
    static let stopMonitoring = "stop_monitoring"
    static let settings = "settings"
    static let testCapture = "test_capture"
    static let about = "about"
    static let quit = "quit"
    static let monitoring = "monitoring"
    static let notStarted = "not_started"
    static let cameraPermission = "camera_permission"
    static let authorized = "authorized"
    static let unauthorized = "unauthorized"
    static let telegramConnection = "telegram_connection"
    static let configured = "configured"
    static let notConfigured = "not_configured"
    static let lastCapture = "last_capture"
    static let captureCount = "capture_count"
    static let launchAtLogin = "launch_at_login"
    static let autoStartMonitoring = "auto_start_monitoring"
    static let selfTest = "self_test"
    static let cancelTest = "cancel_test"
    static let testUnlockRecording = "test_unlock_recording"
    static let clearStats = "clear_stats"
    static let general = "general"
    static let capture = "capture"
    static let detection = "detection"
    static let upload = "upload"
    static let privacy = "privacy"
    static let advanced = "advanced"
    static let status = "status"
    static let version = "version"
    static let confirmExit = "confirm_exit"
    static let exitWhileMonitoring = "exit_while_monitoring"
    static let exit = "exit"
    static let cancel = "cancel"
    static let ok = "ok"
    static let warning = "warning"
    static let error = "error"
    static let info = "info"
    static let success = "success"
    static let failed = "failed"
    static let permissionDenied = "permission_denied"
    static let permissionRequired = "permission_required"
    static let openSystemSettings = "open_system_settings"
    static let later = "later"
    static let welcomeTitle = "welcome_title"
    static let welcomeMessage = "welcome_message"
    static let startSetup = "start_setup"
    static let captureSettings = "capture_settings"
    static let captureInterval = "capture_interval"
    static let videoDuration = "video_duration"
    static let enableScreenRecording = "enable_screen_recording"
    static let imageFormat = "image_format"
    static let videoQuality = "video_quality"
    static let seconds = "seconds"
    static let humanDetection = "human_detection"
    static let enableHumanDetection = "enable_human_detection"
    static let confidenceThreshold = "confidence_threshold"
    static let motionDetection = "motion_detection"
    static let enableMotionDetection = "enable_motion_detection"
    static let sensitivity = "sensitivity"
    static let environmentChange = "environment_change"
    static let enableEnvironmentDetection = "enable_environment_detection"
    static let telegramBotConfig = "telegram_bot_config"
    static let saveConfig = "save_config"
    static let testConnection = "test_connection"
    static let sendOptions = "send_options"
    static let saveBeforeSending = "save_before_sending"
    static let useProxy = "use_proxy"
    static let proxyAddress = "proxy_address"
    static let configSaved = "config_saved"
    static let connectionSuccess = "connection_success"
    static let connectionFailed = "connection_failed"
    static let localStorage = "local_storage"
    static let encryptLocalStorage = "encrypt_local_storage"
    static let deleteAfterSending = "delete_after_sending"
    static let retentionDays = "retention_days"
    static let days = "days"
    static let dataSecurity = "data_security"
    static let clearAllData = "clear_all_data"
    static let logs = "logs"
    static let logLevel = "log_level"
    static let debug = "debug"
    static let exportLogs = "export_logs"
    static let diagnostics = "diagnostics"
    static let triggerTestCapture = "trigger_test_capture"
    static let testWakeRecording = "test_wake_recording"
    static let viewSystemInfo = "view_system_info"
    static let hint = "hint"
    static let camera = "camera"
    static let microphone = "microphone"
    static let location = "location"
    static let screenRecording = "screen_recording"
    static let needScreenPermission = "need_screen_permission"
    static let screenPermissionInstructions = "screen_permission_instructions"
    static let lockScreenCaptureInterval = "lock_screen_capture_interval"
    static let wakeVideoLength = "wake_video_length"
    static let language = "language"
    static let selectLanguage = "select_language"
    static let notifications = "notifications"
    static let selectNotificationPlatforms = "select_notification_platforms"
    static let configure = "configure"
    static let configuration = "configuration"
    static let testAllEnabledPlatforms = "test_all_enabled_platforms"
    static let testing = "testing"
    static let testResults = "test_results"
    static let testComplete = "test_complete"
    static let platformsTestSuccess = "platforms_test_success"
    static let save = "save"
    static let test = "test"
    static let accessToken = "access_token"
    static let receiveIdType = "receive_id_type"
    static let receiveId = "receive_id"
    static let webhookUrl = "webhook_url"
}