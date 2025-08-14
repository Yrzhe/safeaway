import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    
    private let service = "com.safeaway.app"
    private let telegramTokenKey = "telegram_bot_token"
    private let telegramChatIdKey = "telegram_chat_id"
    private let feishuAccessTokenKey = "feishu_access_token"
    private let feishuReceiveIdKey = "feishu_receive_id"
    private let wechatWorkWebhookUrlKey = "wechat_work_webhook_url"
    
    private init() {}
    
    func saveTelegramToken(_ token: String) {
        save(token, forKey: telegramTokenKey)
    }
    
    func getTelegramToken() -> String? {
        return load(forKey: telegramTokenKey)
    }
    
    func saveTelegramChatId(_ chatId: String) {
        save(chatId, forKey: telegramChatIdKey)
    }
    
    func getTelegramChatId() -> String? {
        return load(forKey: telegramChatIdKey)
    }
    
    // Feishu methods
    func saveFeishuAccessToken(_ token: String) {
        save(token, forKey: feishuAccessTokenKey)
    }
    
    func getFeishuAccessToken() -> String? {
        return load(forKey: feishuAccessTokenKey)
    }
    
    func saveFeishuReceiveId(_ id: String) {
        save(id, forKey: feishuReceiveIdKey)
    }
    
    func getFeishuReceiveId() -> String? {
        return load(forKey: feishuReceiveIdKey)
    }
    
    // WeChat Work methods
    func saveWeChatWorkWebhookUrl(_ url: String) {
        save(url, forKey: wechatWorkWebhookUrlKey)
    }
    
    func getWeChatWorkWebhookUrl() -> String? {
        return load(forKey: wechatWorkWebhookUrlKey)
    }
    
    func deleteAll() {
        delete(forKey: telegramTokenKey)
        delete(forKey: telegramChatIdKey)
        delete(forKey: feishuAccessTokenKey)
        delete(forKey: feishuReceiveIdKey)
        delete(forKey: wechatWorkWebhookUrlKey)
    }
    
    private func save(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            Logger.shared.log("Failed to save to keychain: \(key), status: \(status)", level: .error)
        }
    }
    
    private func load(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }
        
        return nil
    }
    
    private func delete(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}