import Foundation
import CryptoKit

actor WeChatWorkUploader: NotificationService {
    static let shared = WeChatWorkUploader()
    
    private struct UploadTask: Sendable {
        let id = UUID()
        let type: MediaType
        let data: Data?
        let url: URL?
        let caption: String
        let priority: NotificationPriority
        var retryCount: Int
        let timestamp: Date
    }
    
    enum MediaType: Sendable {
        case photo
        case video
        case document
    }
    
    private var uploadQueue = [UploadTask]()
    private var isUploading = false
    private let session: URLSession
    private let maxRetries = 3
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        session = URLSession(configuration: config)
        
        Task {
            await startUploadProcessor()
        }
    }
    
    func uploadPhoto(data: Data, caption: String, priority: NotificationPriority) async throws {
        let task = UploadTask(
            type: .photo,
            data: data,
            url: nil,
            caption: caption,
            priority: priority,
            retryCount: 0,
            timestamp: Date()
        )
        
        enqueueTask(task)
    }
    
    func uploadVideo(url: URL, caption: String, priority: NotificationPriority) async throws {
        Logger.shared.log("📤 WeChatWorkUploader: Received video upload request", level: .info)
        
        let task = UploadTask(
            type: .video,
            data: nil,
            url: url,
            caption: caption,
            priority: priority,
            retryCount: 0,
            timestamp: Date()
        )
        
        enqueueTask(task)
    }
    
    func testConnection() async -> Bool {
        Logger.shared.log("🔍 Testing WeChat Work connection...", level: .info)
        
        let webhookUrl = await MainActor.run { AppSettings.shared.wechatWorkWebhookUrl }
        
        guard let webhookUrl = webhookUrl else {
            Logger.shared.log("❌ WeChat Work webhook URL not configured", level: .error)
            return false
        }
        
        do {
            try await sendTextMessage("SafeAway 连接测试成功 ✅", webhookUrl: webhookUrl)
            Logger.shared.log("✅ WeChat Work connection test successful", level: .info)
            return true
        } catch {
            Logger.shared.log("❌ WeChat Work connection test failed: \(error)", level: .error)
            return false
        }
    }
    
    func isConfigured() async -> Bool {
        let webhookUrl = await MainActor.run { AppSettings.shared.wechatWorkWebhookUrl }
        return webhookUrl != nil && !webhookUrl!.isEmpty
    }
    
    private func enqueueTask(_ task: UploadTask) {
        uploadQueue.append(task)
        uploadQueue.sort { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.timestamp < rhs.timestamp
            }
            return priorityValue(lhs.priority) > priorityValue(rhs.priority)
        }
        
        Task {
            await processQueue()
        }
    }
    
    private func priorityValue(_ priority: NotificationPriority) -> Int {
        switch priority {
        case .high: return 3
        case .normal: return 2
        case .low: return 1
        }
    }
    
    private func startUploadProcessor() async {
        while true {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            await processQueue()
        }
    }
    
    private func processQueue() async {
        guard !uploadQueue.isEmpty, !isUploading else {
            return
        }
        
        let task = uploadQueue.removeFirst()
        isUploading = true
        
        await uploadTask(task)
        
        isUploading = false
        await processQueue()
    }
    
    private func uploadTask(_ task: UploadTask) async {
        Logger.shared.log("📤 Processing WeChat Work upload task: \(task.type)", level: .info)
        
        let webhookUrl = await MainActor.run { AppSettings.shared.wechatWorkWebhookUrl }
        
        guard let webhookUrl = webhookUrl else {
            Logger.shared.log("❌ WeChat Work webhook URL not configured", level: .error)
            return
        }
        
        do {
            switch task.type {
            case .photo:
                if let data = task.data {
                    try await sendImage(data: data, caption: task.caption, webhookUrl: webhookUrl)
                }
            case .video:
                // 企业微信不直接支持视频，发送文本通知
                let message = "📹 视频警报\\n\(task.caption)"
                try await sendTextMessage(message, webhookUrl: webhookUrl)
            case .document:
                break
            }
            
            Logger.shared.log("WeChat Work upload successful: \(task.type)", level: .info)
            
        } catch {
            Logger.shared.log("WeChat Work upload failed: \(error)", level: .error)
            
            if task.retryCount < maxRetries {
                var retryTask = task
                retryTask.retryCount += 1
                
                Task {
                    let delay = UInt64(pow(2, Double(retryTask.retryCount)) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: delay)
                    self.enqueueTask(retryTask)
                }
            }
        }
    }
    
    private func sendTextMessage(_ text: String, webhookUrl: String) async throws {
        guard let url = URL(string: webhookUrl) else {
            throw WeChatWorkError.invalidWebhookUrl
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let message: [String: Any] = [
            "msgtype": "text",
            "text": [
                "content": text
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: message)
        
        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode != 200 {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    throw WeChatWorkError.apiError(errorMessage)
                }
                throw WeChatWorkError.httpError(httpResponse.statusCode)
            }
            
            // Check response for error code
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errcode = json["errcode"] as? Int,
               errcode != 0 {
                let errmsg = json["errmsg"] as? String ?? "Unknown error"
                throw WeChatWorkError.apiError("Error \(errcode): \(errmsg)")
            }
        }
    }
    
    private func sendImage(data: Data, caption: String, webhookUrl: String) async throws {
        // 企业微信支持发送 base64 编码的图片
        guard let url = URL(string: webhookUrl) else {
            throw WeChatWorkError.invalidWebhookUrl
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let base64String = data.base64EncodedString()
        let md5Hash = computeMD5(data: data)
        
        let message: [String: Any] = [
            "msgtype": "image",
            "image": [
                "base64": base64String,
                "md5": md5Hash
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: message)
        
        let (responseData, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode != 200 {
                if let errorMessage = String(data: responseData, encoding: .utf8) {
                    throw WeChatWorkError.apiError(errorMessage)
                }
                throw WeChatWorkError.httpError(httpResponse.statusCode)
            }
            
            // Check response for error code
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let errcode = json["errcode"] as? Int,
               errcode != 0 {
                let errmsg = json["errmsg"] as? String ?? "Unknown error"
                throw WeChatWorkError.apiError("Error \(errcode): \(errmsg)")
            }
        }
        
        // 发送图片后，如果有 caption，再发送文本消息
        if !caption.isEmpty {
            try await sendTextMessage(caption, webhookUrl: webhookUrl)
        }
    }
    
    private func computeMD5(data: Data) -> String {
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum WeChatWorkError: Error {
    case invalidWebhookUrl
    case httpError(Int)
    case apiError(String)
}