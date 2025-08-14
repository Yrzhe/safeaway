import SwiftUI

struct NotificationSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var selectedPlatform: NotificationPlatform = .telegram
    @State private var showingTestAlert = false
    @State private var testResults: [(platform: NotificationPlatform, success: Bool)] = []
    @State private var isTesting = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Platform selection
            VStack(alignment: .leading, spacing: 10) {
                Text(L[LocalizedStringKey.selectNotificationPlatforms])
                    .font(.headline)
                
                ForEach(NotificationPlatform.allCases) { platform in
                    HStack {
                        Image(systemName: settings.enabledNotificationPlatforms.contains(platform) ? "checkmark.square.fill" : "square")
                            .foregroundColor(settings.enabledNotificationPlatforms.contains(platform) ? .accentColor : .secondary)
                            .onTapGesture {
                                togglePlatform(platform)
                            }
                        
                        Image(systemName: platform.iconName)
                            .foregroundColor(.secondary)
                        
                        Text(platform.displayName)
                        
                        Spacer()
                        
                        if settings.enabledNotificationPlatforms.contains(platform) {
                            Button(L[LocalizedStringKey.configure]) {
                                selectedPlatform = platform
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Divider()
            
            // Platform configuration
            VStack(alignment: .leading, spacing: 15) {
                Text("\(selectedPlatform.displayName) \(L[LocalizedStringKey.configuration])")
                    .font(.headline)
                
                switch selectedPlatform {
                case .telegram:
                    TelegramConfigView()
                case .feishu:
                    FeishuConfigView()
                case .wechatWork:
                    WeChatWorkConfigView()
                }
            }
            
            Divider()
            
            // Test buttons
            HStack {
                if isTesting {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(L[LocalizedStringKey.testing])
                        .foregroundColor(.secondary)
                } else {
                    Button(L[LocalizedStringKey.testAllEnabledPlatforms]) {
                        testAllPlatforms()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(settings.enabledNotificationPlatforms.isEmpty)
                }
                
                Spacer()
            }
            
            // Test results
            if !testResults.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L[LocalizedStringKey.testResults])
                        .font(.headline)
                    
                    ForEach(testResults, id: \.platform) { result in
                        HStack {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.success ? .green : .red)
                            Text(result.platform.displayName)
                            Text(result.success ? L[LocalizedStringKey.success] : L[LocalizedStringKey.failed])
                                .foregroundColor(result.success ? .green : .red)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .alert(L[LocalizedStringKey.testComplete], isPresented: $showingTestAlert) {
            Button(L[LocalizedStringKey.ok], role: .cancel) { }
        } message: {
            Text(testResultsMessage())
        }
    }
    
    private func togglePlatform(_ platform: NotificationPlatform) {
        var platforms = settings.enabledNotificationPlatforms
        if platforms.contains(platform) {
            platforms.remove(platform)
        } else {
            platforms.insert(platform)
            selectedPlatform = platform
        }
        settings.enabledNotificationPlatforms = platforms
    }
    
    private func testAllPlatforms() {
        isTesting = true
        testResults = []
        
        Task {
            let results = await NotificationManager.shared.testAllEnabledPlatforms()
            await MainActor.run {
                testResults = results
                isTesting = false
                showingTestAlert = true
            }
        }
    }
    
    private func testResultsMessage() -> String {
        let successCount = testResults.filter { $0.success }.count
        return "\(successCount)/\(testResults.count) \(L[LocalizedStringKey.platformsTestSuccess])"
    }
}

struct TelegramConfigView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var botToken = ""
    @State private var chatId = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField("Bot Token", text: $botToken)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            TextField("Chat ID", text: $chatId)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            HStack {
                Button(L[LocalizedStringKey.save]) {
                    saveConfiguration()
                }
                .buttonStyle(.borderedProminent)
                
                Button(L[LocalizedStringKey.test]) {
                    testConnection()
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            botToken = settings.telegramBotToken ?? ""
            chatId = settings.telegramChatId ?? ""
        }
        .alert(L[LocalizedStringKey.hint], isPresented: $showingAlert) {
            Button(L[LocalizedStringKey.ok], role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func saveConfiguration() {
        if !botToken.isEmpty {
            settings.telegramBotToken = botToken
        }
        if !chatId.isEmpty {
            settings.telegramChatId = chatId
        }
        alertMessage = L[LocalizedStringKey.configSaved]
        showingAlert = true
    }
    
    private func testConnection() {
        Task {
            let success = await NotificationManager.shared.testPlatform(.telegram)
            alertMessage = success ? L[LocalizedStringKey.connectionSuccess] : L[LocalizedStringKey.connectionFailed]
            showingAlert = true
        }
    }
}

struct FeishuConfigView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var accessToken = ""
    @State private var receiveId = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField(L[LocalizedStringKey.accessToken], text: $accessToken)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .help("飞书机器人的访问凭证")
            
            Picker(L[LocalizedStringKey.receiveIdType], selection: $settings.feishuReceiveIdType) {
                ForEach(FeishuReceiveIdType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(MenuPickerStyle())
            
            TextField(L[LocalizedStringKey.receiveId], text: $receiveId)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .help("消息接收者 ID，根据上面选择的类型填写对应的 ID")
            
            HStack {
                Button(L[LocalizedStringKey.save]) {
                    saveConfiguration()
                }
                .buttonStyle(.borderedProminent)
                
                Button(L[LocalizedStringKey.test]) {
                    testConnection()
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            accessToken = settings.feishuAccessToken ?? ""
            receiveId = settings.feishuReceiveId ?? ""
        }
        .alert(L[LocalizedStringKey.hint], isPresented: $showingAlert) {
            Button(L[LocalizedStringKey.ok], role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func saveConfiguration() {
        if !accessToken.isEmpty {
            settings.feishuAccessToken = accessToken
        }
        if !receiveId.isEmpty {
            settings.feishuReceiveId = receiveId
        }
        alertMessage = L[LocalizedStringKey.configSaved]
        showingAlert = true
    }
    
    private func testConnection() {
        Task {
            let success = await NotificationManager.shared.testPlatform(.feishu)
            alertMessage = success ? L[LocalizedStringKey.connectionSuccess] : L[LocalizedStringKey.connectionFailed]
            showingAlert = true
        }
    }
}

struct WeChatWorkConfigView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var webhookUrl = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L[LocalizedStringKey.webhookUrl], text: $webhookUrl)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .help("企业微信机器人的 Webhook URL")
            
            Text("示例: https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Button(L[LocalizedStringKey.save]) {
                    saveConfiguration()
                }
                .buttonStyle(.borderedProminent)
                
                Button(L[LocalizedStringKey.test]) {
                    testConnection()
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            webhookUrl = settings.wechatWorkWebhookUrl ?? ""
        }
        .alert(L[LocalizedStringKey.hint], isPresented: $showingAlert) {
            Button(L[LocalizedStringKey.ok], role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func saveConfiguration() {
        if !webhookUrl.isEmpty {
            settings.wechatWorkWebhookUrl = webhookUrl
        }
        alertMessage = L[LocalizedStringKey.configSaved]
        showingAlert = true
    }
    
    private func testConnection() {
        Task {
            let success = await NotificationManager.shared.testPlatform(.wechatWork)
            alertMessage = success ? L[LocalizedStringKey.connectionSuccess] : L[LocalizedStringKey.connectionFailed]
            showingAlert = true
        }
    }
}