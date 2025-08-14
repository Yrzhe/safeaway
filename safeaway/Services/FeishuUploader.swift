import Foundation

actor FeishuUploader: NotificationService {
    static let shared = FeishuUploader()
    
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
        Logger.shared.log("📤 FeishuUploader: Received video upload request", level: .info)
        
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
        Logger.shared.log("🔍 Testing Feishu connection...", level: .info)
        
        let (accessToken, receiveIdType, receiveId) = await MainActor.run {
            (AppSettings.shared.feishuAccessToken,
             AppSettings.shared.feishuReceiveIdType,
             AppSettings.shared.feishuReceiveId)
        }
        
        guard let accessToken = accessToken,
              let receiveId = receiveId else {
            Logger.shared.log("❌ Feishu credentials not configured", level: .error)
            return false
        }
        
        do {
            try await sendMessage(text: "SafeAway 连接测试成功 ✅", accessToken: accessToken, receiveIdType: receiveIdType, receiveId: receiveId)
            Logger.shared.log("✅ Feishu connection test successful", level: .info)
            return true
        } catch {
            Logger.shared.log("❌ Feishu connection test failed: \(error)", level: .error)
            return false
        }
    }
    
    func isConfigured() async -> Bool {
        let (accessToken, receiveId) = await MainActor.run {
            (AppSettings.shared.feishuAccessToken, AppSettings.shared.feishuReceiveId)
        }
        return accessToken != nil && receiveId != nil
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
        Logger.shared.log("📤 Processing Feishu upload task: \(task.type)", level: .info)
        
        let (accessToken, receiveIdType, receiveId) = await MainActor.run {
            (AppSettings.shared.feishuAccessToken,
             AppSettings.shared.feishuReceiveIdType,
             AppSettings.shared.feishuReceiveId)
        }
        
        guard let accessToken = accessToken,
              let receiveId = receiveId else {
            Logger.shared.log("❌ Feishu credentials not configured", level: .error)
            return
        }
        
        do {
            switch task.type {
            case .photo:
                if let data = task.data {
                    try await sendPhoto(data: data, caption: task.caption, accessToken: accessToken, receiveIdType: receiveIdType, receiveId: receiveId)
                }
            case .video:
                // 飞书视频上传需要先上传到文件服务器，暂时发送文本消息通知
                try await sendMessage(text: "📹 \(task.caption)", accessToken: accessToken, receiveIdType: receiveIdType, receiveId: receiveId)
            case .document:
                break
            }
            
            Logger.shared.log("Feishu upload successful: \(task.type)", level: .info)
            
        } catch {
            Logger.shared.log("Feishu upload failed: \(error)", level: .error)
            
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
    
    private func sendMessage(text: String, accessToken: String, receiveIdType: FeishuReceiveIdType, receiveId: String) async throws {
        let url = URL(string: "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=\(receiveIdType.rawValue)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        // Build content JSON properly
        let contentDict = ["text": text]
        let contentJSON = try JSONSerialization.data(withJSONObject: contentDict)
        let contentString = String(data: contentJSON, encoding: .utf8) ?? "{}"
        
        let message: [String: Any] = [
            "receive_id": receiveId,
            "msg_type": "text",
            "content": contentString
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: message)
        
        Logger.shared.log("Feishu API Request: \(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "")", level: .debug)
        
        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            Logger.shared.log("Feishu API Response Status: \(httpResponse.statusCode)", level: .debug)
            
            if httpResponse.statusCode != 200 {
                if let errorMessage = String(data: data, encoding: .utf8) {
                    Logger.shared.log("Feishu API Error: \(errorMessage)", level: .error)
                    throw FeishuError.apiError(errorMessage)
                }
                throw FeishuError.httpError(httpResponse.statusCode)
            }
            
            // Check for API-level errors in successful response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let code = json["code"] as? Int, code != 0 {
                    let msg = json["msg"] as? String ?? "Unknown error"
                    throw FeishuError.apiError("Error \(code): \(msg)")
                }
                Logger.shared.log("Feishu message sent successfully", level: .debug)
            }
        }
    }
    
    private func sendPhoto(data: Data, caption: String, accessToken: String, receiveIdType: FeishuReceiveIdType, receiveId: String) async throws {
        // 首先上传图片获取 image_key
        let imageKey = try await uploadImage(data: data, accessToken: accessToken)
        
        // 然后发送图片消息
        let url = URL(string: "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=\(receiveIdType.rawValue)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        // Build content JSON properly
        let contentDict = ["image_key": imageKey]
        let contentJSON = try JSONSerialization.data(withJSONObject: contentDict)
        let contentString = String(data: contentJSON, encoding: .utf8) ?? "{}"
        
        let message: [String: Any] = [
            "receive_id": receiveId,
            "msg_type": "image",
            "content": contentString
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: message)
        
        let (responseData, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode != 200 {
                if let errorMessage = String(data: responseData, encoding: .utf8) {
                    throw FeishuError.apiError(errorMessage)
                }
                throw FeishuError.httpError(httpResponse.statusCode)
            }
        }
        
        // 发送图片后再发送文字说明
        if !caption.isEmpty {
            try await sendMessage(text: caption, accessToken: accessToken, receiveIdType: receiveIdType, receiveId: receiveId)
        }
    }
    
    private func uploadImage(data: Data, accessToken: String) async throws -> String {
        let url = URL(string: "https://open.feishu.cn/open-apis/im/v1/images")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        var body = Data()
        
        // Add image_type field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image_type\"\r\n\r\n".data(using: .utf8)!)
        body.append("message\r\n".data(using: .utf8)!)
        
        // Add image field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        
        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (responseData, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                   let data = json["data"] as? [String: Any],
                   let imageKey = data["image_key"] as? String {
                    return imageKey
                }
            }
        }
        
        throw FeishuError.apiError("Failed to upload image")
    }
}

enum FeishuError: Error {
    case httpError(Int)
    case apiError(String)
    case invalidCredentials
}