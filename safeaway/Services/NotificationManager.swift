import Foundation

actor NotificationManager {
    static let shared = NotificationManager()
    
    private init() {}
    
    func sendNotification(photo: Data? = nil, video: URL? = nil, caption: String, priority: NotificationPriority) async {
        let platforms = await MainActor.run { AppSettings.shared.enabledNotificationPlatforms }
        
        guard !platforms.isEmpty else {
            Logger.shared.log("⚠️ No notification platforms enabled", level: .warning)
            return
        }
        
        await withTaskGroup(of: Void.self) { group in
            for platform in platforms {
                group.addTask {
                    await self.sendToPlatform(platform, photo: photo, video: video, caption: caption, priority: priority)
                }
            }
        }
    }
    
    private func sendToPlatform(_ platform: NotificationPlatform, photo: Data?, video: URL?, caption: String, priority: NotificationPriority) async {
        let service = getService(for: platform)
        
        // Check if platform is configured
        guard await service.isConfigured() else {
            Logger.shared.log("⚠️ \(platform.displayName) not configured, skipping", level: .warning)
            return
        }
        
        do {
            if let photo = photo {
                try await service.uploadPhoto(data: photo, caption: caption, priority: priority)
                Logger.shared.log("✅ Sent photo to \(platform.displayName)", level: .info)
            } else if let video = video {
                try await service.uploadVideo(url: video, caption: caption, priority: priority)
                Logger.shared.log("✅ Sent video to \(platform.displayName)", level: .info)
            }
        } catch {
            Logger.shared.log("❌ Failed to send to \(platform.displayName): \(error)", level: .error)
        }
    }
    
    func testPlatform(_ platform: NotificationPlatform) async -> Bool {
        let service = getService(for: platform)
        return await service.testConnection()
    }
    
    func testAllEnabledPlatforms() async -> [(platform: NotificationPlatform, success: Bool)] {
        let platforms = await MainActor.run { AppSettings.shared.enabledNotificationPlatforms }
        
        return await withTaskGroup(of: (NotificationPlatform, Bool).self) { group in
            for platform in platforms {
                group.addTask {
                    let success = await self.testPlatform(platform)
                    return (platform, success)
                }
            }
            
            var results: [(NotificationPlatform, Bool)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }
    
    private func getService(for platform: NotificationPlatform) -> NotificationService {
        switch platform {
        case .telegram:
            return TelegramUploaderAdapter.shared
        case .feishu:
            return FeishuUploader.shared
        case .wechatWork:
            return WeChatWorkUploader.shared
        }
    }
}

// Adapter to make TelegramUploader conform to NotificationService protocol
actor TelegramUploaderAdapter: NotificationService {
    static let shared = TelegramUploaderAdapter()
    
    private init() {}
    
    func uploadPhoto(data: Data, caption: String, priority: NotificationPriority) async throws {
        let telegramPriority: TelegramUploader.Priority
        switch priority {
        case .high:
            telegramPriority = .high
        case .normal:
            telegramPriority = .normal
        case .low:
            telegramPriority = .low
        }
        await TelegramUploader.shared.uploadPhoto(data: data, caption: caption, priority: telegramPriority)
    }
    
    func uploadVideo(url: URL, caption: String, priority: NotificationPriority) async throws {
        let telegramPriority: TelegramUploader.Priority
        switch priority {
        case .high:
            telegramPriority = .high
        case .normal:
            telegramPriority = .normal
        case .low:
            telegramPriority = .low
        }
        await TelegramUploader.shared.uploadVideo(url: url, caption: caption, priority: telegramPriority)
    }
    
    func testConnection() async -> Bool {
        return await TelegramUploader.shared.testConnection()
    }
    
    func isConfigured() async -> Bool {
        let (token, chatId) = await MainActor.run {
            (AppSettings.shared.telegramBotToken, AppSettings.shared.telegramChatId)
        }
        return token != nil && chatId != nil
    }
}