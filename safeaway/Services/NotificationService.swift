import Foundation

protocol NotificationService: Actor {
    func uploadPhoto(data: Data, caption: String, priority: NotificationPriority) async throws
    func uploadVideo(url: URL, caption: String, priority: NotificationPriority) async throws
    func testConnection() async -> Bool
    func isConfigured() async -> Bool
}

enum NotificationPriority: Sendable {
    case high
    case normal
    case low
}

enum NotificationPlatform: String, CaseIterable, Codable, Identifiable {
    case telegram = "telegram"
    case feishu = "feishu"
    case wechatWork = "wechatWork"
    
    var displayName: String {
        switch self {
        case .telegram:
            return "Telegram"
        case .feishu:
            return "飞书"
        case .wechatWork:
            return "企业微信"
        }
    }
    
    var iconName: String {
        switch self {
        case .telegram:
            return "paperplane"
        case .feishu:
            return "message.badge"
        case .wechatWork:
            return "message.circle"
        }
    }
    
    var id: String { self.rawValue }
}

struct NotificationConfig: Codable {
    var enabledPlatforms: Set<NotificationPlatform> = []
    
    var telegramBotToken: String?
    var telegramChatId: String?
    
    var feishuAccessToken: String?
    var feishuReceiveIdType: FeishuReceiveIdType = .userId
    var feishuReceiveId: String?
    
    var wechatWorkWebhookUrl: String?
}

enum FeishuReceiveIdType: String, CaseIterable, Codable, Identifiable {
    case openId = "open_id"
    case userId = "user_id"
    case unionId = "union_id"
    case email = "email"
    case chatId = "chat_id"
    
    var displayName: String {
        switch self {
        case .openId:
            return "Open ID"
        case .userId:
            return "User ID"
        case .unionId:
            return "Union ID"
        case .email:
            return "Email"
        case .chatId:
            return "Chat ID"
        }
    }
    
    var id: String { self.rawValue }
}