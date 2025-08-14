import Foundation

actor TelegramUploader {
    static let shared = TelegramUploader()
    
    enum Priority {
        case high
        case normal
        case low
    }
    
    private struct UploadTask: Sendable {
        let id = UUID()
        let type: MediaType
        let data: Data?
        let url: URL?
        let caption: String
        let priority: Priority
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
    
    private let rateLimiter = RateLimiter()
    private var lastMessageTime: Date?
    private let messageInterval: TimeInterval = 1.0
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
    
    func uploadPhoto(data: Data, caption: String, priority: Priority) async {
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
    
    func uploadVideo(url: URL, caption: String, priority: Priority) async {
        Logger.shared.log("📤 TelegramUploader: Received video upload request", level: .info)
        Logger.shared.log("  URL: \(url.path)", level: .debug)
        Logger.shared.log("  Priority: \(priority)", level: .debug)
        
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
        Logger.shared.log("📥 Video task enqueued for upload", level: .info)
    }
    
    private func enqueueTask(_ task: UploadTask) {
        uploadQueue.append(task)
        uploadQueue.sort { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.timestamp < rhs.timestamp
            }
            return priorityValue(lhs.priority) > priorityValue(rhs.priority)
        }
        
        Logger.shared.log("Enqueued upload task: \(task.type), priority: \(task.priority)", level: .debug)
        
        Task {
            await processQueue()
        }
    }
    
    private func priorityValue(_ priority: Priority) -> Int {
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
        Logger.shared.log("📤 Processing upload task: \(task.type)", level: .info)
        
        let (botToken, chatId) = await MainActor.run {
            (AppSettings.shared.telegramBotToken, AppSettings.shared.telegramChatId)
        }
        guard let botToken = botToken,
              let chatId = chatId else {
            Logger.shared.log("❌ Telegram credentials not configured! Bot token: \(botToken != nil), Chat ID: \(chatId != nil)", level: .error)
            return
        }
        
        Logger.shared.log("✅ Telegram credentials found, proceeding with upload", level: .debug)
        
        await rateLimiter.waitIfNeeded()
        
        do {
            switch task.type {
            case .photo:
                if let data = task.data {
                    try await sendPhoto(data: data, caption: task.caption, botToken: botToken, chatId: chatId)
                }
            case .video:
                if let url = task.url {
                    try await sendVideo(url: url, caption: task.caption, botToken: botToken, chatId: chatId)
                } else {
                    Logger.shared.log("❌ Video upload task has no URL", level: .error)
                }
            case .document:
                break
            }
            
            Logger.shared.log("Upload successful: \(task.type)", level: .info)
            
        } catch {
            Logger.shared.log("Upload failed: \(error)", level: .error)
            
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
    
    private func sendPhoto(data: Data, caption: String, botToken: String, chatId: String) async throws {
        Logger.shared.log("Starting photo upload, size: \(data.count) bytes", level: .info)
        
        let url = URL(string: "https://api.telegram.org/bot\(botToken)/sendPhoto")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(chatId)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"caption\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(caption)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        Logger.shared.log("Sending photo to Telegram, body size: \(body.count) bytes", level: .debug)
        
        let (responseData, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            Logger.shared.log("Telegram response status: \(httpResponse.statusCode)", level: .debug)
            
            if httpResponse.statusCode == 429 {
                throw TelegramError.rateLimited
            } else if httpResponse.statusCode != 200 {
                if let errorMessage = String(data: responseData, encoding: .utf8) {
                    Logger.shared.log("Telegram API error: \(errorMessage)", level: .error)
                    throw TelegramError.apiError(errorMessage)
                }
                throw TelegramError.httpError(httpResponse.statusCode)
            } else {
                Logger.shared.log("Photo uploaded successfully to Telegram", level: .info)
            }
        }
    }
    
    private func sendVideo(url: URL, caption: String, botToken: String, chatId: String) async throws {
        Logger.shared.log("🚀 Starting Telegram video upload from: \(url.path)", level: .info)
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            Logger.shared.log("❌ Video file not found at: \(url.path)", level: .error)
            
            // List files in temporary directory for debugging
            let tempDir = FileManager.default.temporaryDirectory
            Logger.shared.log("📁 Temp directory path: \(tempDir.path)", level: .debug)
            if let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
                Logger.shared.log("📁 Files in temp directory:", level: .debug)
                for file in files {
                    Logger.shared.log("  - \(file.lastPathComponent)", level: .debug)
                }
            }
            
            throw TelegramError.apiError("Video file not found")
        }
        
        let apiUrl = URL(string: "https://api.telegram.org/bot\(botToken)/sendVideo")!
        
        let videoData = try Data(contentsOf: url)
        Logger.shared.log("Video data loaded, size: \(videoData.count) bytes", level: .debug)
        
        var request = URLRequest(url: apiUrl)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(chatId)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"caption\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(caption)\r\n".data(using: .utf8)!)
        
        // Determine content type based on file extension
        let fileExtension = url.pathExtension.lowercased()
        let contentType = fileExtension == "mov" ? "video/quicktime" : "video/mp4"
        let filename = url.lastPathComponent
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        Logger.shared.log("Sending video to Telegram, body size: \(body.count) bytes", level: .debug)
        
        let (responseData, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            Logger.shared.log("Telegram response status: \(httpResponse.statusCode)", level: .debug)
            
            if httpResponse.statusCode == 429 {
                Logger.shared.log("⚠️ Rate limited by Telegram", level: .warning)
                throw TelegramError.rateLimited
            } else if httpResponse.statusCode != 200 {
                if let errorMessage = String(data: responseData, encoding: .utf8) {
                    Logger.shared.log("❌ Telegram API error: \(errorMessage)", level: .error)
                    throw TelegramError.apiError(errorMessage)
                }
                throw TelegramError.httpError(httpResponse.statusCode)
            } else {
                Logger.shared.log("✅ Video uploaded successfully to Telegram!", level: .info)
                Logger.shared.log("  Video file: \(url.lastPathComponent)", level: .debug)
                
                // Clean up the video file after successful upload
                try? FileManager.default.removeItem(at: url)
                Logger.shared.log("🗑 Video file cleaned up after successful upload", level: .debug)
            }
        }
    }
    
    func testConnection() async -> Bool {
        Logger.shared.log("🔍 Testing Telegram connection...", level: .info)
        
        let botToken = await MainActor.run { AppSettings.shared.telegramBotToken }
        let chatId = await MainActor.run { AppSettings.shared.telegramChatId }
        
        guard let botToken = botToken else { 
            Logger.shared.log("❌ Telegram bot token not configured", level: .error)
            return false 
        }
        
        guard let chatId = chatId else {
            Logger.shared.log("❌ Telegram chat ID not configured", level: .error)
            return false
        }
        
        Logger.shared.log("✅ Telegram credentials found: Bot token length: \(botToken.count), Chat ID: \(chatId)", level: .info)
        
        let url = URL(string: "https://api.telegram.org/bot\(botToken)/getMe")!
        
        do {
            let (data, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let result = json["result"] as? [String: Any],
                       let username = result["username"] as? String {
                        Logger.shared.log("✅ Connected to Telegram bot: @\(username)", level: .info)
                    }
                    return true
                } else {
                    Logger.shared.log("❌ Telegram API returned status: \(httpResponse.statusCode)", level: .error)
                    if let errorString = String(data: data, encoding: .utf8) {
                        Logger.shared.log("Error details: \(errorString)", level: .error)
                    }
                }
            }
        } catch {
            Logger.shared.log("❌ Telegram connection test failed: \(error)", level: .error)
        }
        
        return false
    }
}

enum TelegramError: Error {
    case rateLimited
    case httpError(Int)
    case apiError(String)
    case invalidCredentials
}

actor RateLimiter {
    private var lastRequestTime: Date?
    private let minInterval: TimeInterval = 1.0
    
    func waitIfNeeded() async {
        if let lastTime = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minInterval {
                let waitTime = minInterval - elapsed
                let nanoseconds = UInt64(waitTime * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
        
        lastRequestTime = Date()
    }
}