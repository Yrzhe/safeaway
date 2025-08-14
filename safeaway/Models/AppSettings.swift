import Foundation
import SwiftUI
import ServiceManagement

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    @AppStorage("captureInterval") var captureInterval: Double = 15.0
    @AppStorage("videoDuration") var videoDuration: Double = 15.0
    @AppStorage("screenRecordingEnabled") var screenRecordingEnabled: Bool = false
    @AppStorage("imageFormat") var imageFormat: String = "jpeg"
    @AppStorage("videoQuality") var videoQuality: String = "720p"
    
    @AppStorage("humanDetectionEnabled") var humanDetectionEnabled: Bool = true
    @AppStorage("humanDetectionThreshold") var humanDetectionThreshold: Double = 0.6
    @AppStorage("motionDetectionEnabled") var motionDetectionEnabled: Bool = true
    @AppStorage("motionDetectionSensitivity") var motionDetectionSensitivity: Double = 0.03
    @AppStorage("environmentChangeDetectionEnabled") var environmentChangeDetectionEnabled: Bool = false
    
    @AppStorage("saveBeforeSending") var saveBeforeSending: Bool = false
    @AppStorage("useProxy") var useProxy: Bool = false
    @AppStorage("proxyAddress") var proxyAddress: String = ""
    
    @AppStorage("encryptLocalStorage") var encryptLocalStorage: Bool = true
    @AppStorage("deleteAfterSending") var deleteAfterSending: Bool = true
    @AppStorage("localRetentionDays") var localRetentionDays: Double = 7.0
    
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("autoStartMonitoring") var autoStartMonitoring: Bool = false
    
    // Notification platforms
    @AppStorage("enabledNotificationPlatforms") private var enabledPlatformsData: Data = Data()
    
    var enabledNotificationPlatforms: Set<NotificationPlatform> {
        get {
            guard let platforms = try? JSONDecoder().decode(Set<NotificationPlatform>.self, from: enabledPlatformsData) else {
                return []
            }
            return platforms
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                enabledPlatformsData = data
            }
        }
    }
    
    // Telegram settings
    var telegramBotToken: String? {
        get { KeychainManager.shared.getTelegramToken() }
        set {
            if let token = newValue {
                KeychainManager.shared.saveTelegramToken(token)
            }
        }
    }
    
    var telegramChatId: String? {
        get { KeychainManager.shared.getTelegramChatId() }
        set {
            if let chatId = newValue {
                KeychainManager.shared.saveTelegramChatId(chatId)
            }
        }
    }
    
    // Feishu settings
    var feishuAccessToken: String? {
        get { KeychainManager.shared.getFeishuAccessToken() }
        set {
            if let token = newValue {
                KeychainManager.shared.saveFeishuAccessToken(token)
            }
        }
    }
    
    @AppStorage("feishuReceiveIdType") private var feishuReceiveIdTypeRaw: String = FeishuReceiveIdType.userId.rawValue
    
    var feishuReceiveIdType: FeishuReceiveIdType {
        get { FeishuReceiveIdType(rawValue: feishuReceiveIdTypeRaw) ?? .userId }
        set { feishuReceiveIdTypeRaw = newValue.rawValue }
    }
    
    var feishuReceiveId: String? {
        get { KeychainManager.shared.getFeishuReceiveId() }
        set {
            if let id = newValue {
                KeychainManager.shared.saveFeishuReceiveId(id)
            }
        }
    }
    
    // WeChat Work settings
    var wechatWorkWebhookUrl: String? {
        get { KeychainManager.shared.getWeChatWorkWebhookUrl() }
        set {
            if let url = newValue {
                KeychainManager.shared.saveWeChatWorkWebhookUrl(url)
            }
        }
    }
    
    private init() {
        setupDefaults()
    }
    
    private func setupDefaults() {
        
    }
    
    func registerLoginItem() {
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        } else {
            let appPath = Bundle.main.bundlePath
            let url = URL(fileURLWithPath: appPath)
            
            LSRegisterURL(url as CFURL, true)
            
            SMLoginItemSetEnabled("com.safeaway.app" as CFString, true)
        }
    }
    
    func unregisterLoginItem() {
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.unregister()
        } else {
            SMLoginItemSetEnabled("com.safeaway.app" as CFString, false)
        }
    }
    
    func exportSettings() -> Data? {
        let settings: [String: Any] = [
            "captureInterval": captureInterval,
            "videoDuration": videoDuration,
            "screenRecordingEnabled": screenRecordingEnabled,
            "imageFormat": imageFormat,
            "videoQuality": videoQuality,
            "humanDetectionEnabled": humanDetectionEnabled,
            "humanDetectionThreshold": humanDetectionThreshold,
            "motionDetectionEnabled": motionDetectionEnabled,
            "motionDetectionSensitivity": motionDetectionSensitivity,
            "environmentChangeDetectionEnabled": environmentChangeDetectionEnabled,
            "saveBeforeSending": saveBeforeSending,
            "useProxy": useProxy,
            "proxyAddress": proxyAddress,
            "encryptLocalStorage": encryptLocalStorage,
            "deleteAfterSending": deleteAfterSending,
            "localRetentionDays": localRetentionDays,
            "launchAtLogin": launchAtLogin
        ]
        
        return try? JSONSerialization.data(withJSONObject: settings)
    }
    
    func importSettings(from data: Data) {
        guard let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        if let value = settings["captureInterval"] as? Double {
            captureInterval = value
        }
        if let value = settings["videoDuration"] as? Double {
            videoDuration = value
        }
        if let value = settings["screenRecordingEnabled"] as? Bool {
            screenRecordingEnabled = value
        }
        if let value = settings["imageFormat"] as? String {
            imageFormat = value
        }
        if let value = settings["videoQuality"] as? String {
            videoQuality = value
        }
        if let value = settings["humanDetectionEnabled"] as? Bool {
            humanDetectionEnabled = value
        }
        if let value = settings["humanDetectionThreshold"] as? Double {
            humanDetectionThreshold = value
        }
        if let value = settings["motionDetectionEnabled"] as? Bool {
            motionDetectionEnabled = value
        }
        if let value = settings["motionDetectionSensitivity"] as? Double {
            motionDetectionSensitivity = value
        }
        if let value = settings["environmentChangeDetectionEnabled"] as? Bool {
            environmentChangeDetectionEnabled = value
        }
        if let value = settings["saveBeforeSending"] as? Bool {
            saveBeforeSending = value
        }
        if let value = settings["useProxy"] as? Bool {
            useProxy = value
        }
        if let value = settings["proxyAddress"] as? String {
            proxyAddress = value
        }
        if let value = settings["encryptLocalStorage"] as? Bool {
            encryptLocalStorage = value
        }
        if let value = settings["deleteAfterSending"] as? Bool {
            deleteAfterSending = value
        }
        if let value = settings["localRetentionDays"] as? Double {
            localRetentionDays = value
        }
        if let value = settings["launchAtLogin"] as? Bool {
            launchAtLogin = value
        }
    }
}