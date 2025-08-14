import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var selectedTab = 0
    @State private var showingTestAlert = false
    @State private var testMessage = ""
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("总览", systemImage: "gear")
                }
                .tag(0)
            
            CaptureSettingsView()
                .tabItem {
                    Label("采集", systemImage: "camera")
                }
                .tag(1)
            
            DetectionSettingsView()
                .tabItem {
                    Label("检测", systemImage: "eye")
                }
                .tag(2)
            
            TelegramSettingsView()
                .tabItem {
                    Label("上报", systemImage: "paperplane")
                }
                .tag(3)
            
            PrivacySettingsView()
                .tabItem {
                    Label("隐私", systemImage: "lock")
                }
                .tag(4)
            
            AdvancedSettingsView()
                .tabItem {
                    Label("高级", systemImage: "wrench.and.screwdriver")
                }
                .tag(5)
        }
        .frame(width: 500, height: 400)
        .padding()
    }
}

struct GeneralSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var appState = AppState.shared
    @State private var isSelfTesting = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("SafeAway 安全监控")
                .font(.title)
                .fontWeight(.bold)
            
            HStack {
                Circle()
                    .fill(appState.isMonitoring ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(appState.isMonitoring ? "监控中" : "未启动")
                    .foregroundColor(appState.isMonitoring ? .green : .gray)
                
                Spacer()
                
                Button(appState.isMonitoring ? "停止监控" : "开始监控") {
                    toggleMonitoring()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                Text("状态")
                    .font(.headline)
                
                HStack {
                    Text("摄像头权限:")
                    Text(PermissionManager.shared.hasCameraPermission ? "已授权" : "未授权")
                        .foregroundColor(PermissionManager.shared.hasCameraPermission ? .green : .red)
                }
                
                HStack {
                    Text("Telegram 连接:")
                    Text(settings.telegramBotToken != nil ? "已配置" : "未配置")
                        .foregroundColor(settings.telegramBotToken != nil ? .green : .orange)
                }
                
                if let lastCapture = appState.lastCaptureTime {
                    HStack {
                        Text("最后捕获:")
                        Text("\(lastCapture, formatter: dateFormatter)")
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Text("捕获次数:")
                    Text("\(appState.captureCount)")
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            Toggle("开机自动启动", isOn: $settings.launchAtLogin)
                .onChange(of: settings.launchAtLogin) { _, newValue in
                    if newValue {
                        AppSettings.shared.registerLoginItem()
                    } else {
                        AppSettings.shared.unregisterLoginItem()
                    }
                }
            
            Toggle("自动开始监控", isOn: $settings.autoStartMonitoring)
                .help("启动应用时自动开始监控")
            
            HStack {
                if isSelfTesting {
                    Button("取消自检") {
                        CaptureService.shared.cancelTest()
                        isSelfTesting = false
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.leading, 5)
                } else {
                    Button("一键自检") {
                        isSelfTesting = true
                        Task {
                            await performSelfTest()
                            isSelfTesting = false
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                Button("测试解锁录像") {
                    Task {
                        await CaptureService.shared.testUnlockRecording()
                    }
                }
                .buttonStyle(.bordered)
                .help("测试解锁录像功能")
                
                Button("清除统计") {
                    clearStats()
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }
    
    private func toggleMonitoring() {
        if appState.isMonitoring {
            appState.stopMonitoring()
        } else {
            appState.startMonitoring()
        }
    }
    
    private func clearStats() {
        appState.captureCount = 0
        appState.lastCaptureTime = nil
    }
    
    private func performSelfTest() async {
        Logger.shared.log("Starting self test", level: .info)
        
        // Test camera capture
        await CaptureService.shared.captureTestSnapshot()
        Logger.shared.log("Camera test completed", level: .info)
        
        // Test Telegram connection
        let connected = await TelegramUploader.shared.testConnection()
        if connected {
            Logger.shared.log("Telegram test successful", level: .info)
            Logger.shared.log("Self test completed successfully", level: .info)
        } else {
            Logger.shared.log("Self test completed with warning: Telegram connection error", level: .warning)
        }
    }
}

struct CaptureSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    
    var body: some View {
        Form {
            Section("抓拍设置") {
                HStack {
                    Text("息屏/锁屏抓拍间隔")
                    Slider(value: $settings.captureInterval, in: 5...60, step: 5)
                    Text("\(Int(settings.captureInterval))秒")
                        .frame(width: 50)
                }
                
                HStack {
                    Text("唤醒录影时长")
                    Slider(value: $settings.videoDuration, in: 5...30, step: 5)
                    Text("\(Int(settings.videoDuration))秒")
                        .frame(width: 50)
                }
                
                Toggle("启用录屏功能", isOn: $settings.screenRecordingEnabled)
                
                Picker("图片格式", selection: $settings.imageFormat) {
                    Text("JPEG").tag("jpeg")
                    Text("HEIF").tag("heif")
                }
                
                Picker("视频质量", selection: $settings.videoQuality) {
                    Text("720p").tag("720p")
                    Text("1080p").tag("1080p")
                    Text("4K").tag("4k")
                }
            }
        }
        .padding()
    }
}

struct DetectionSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    
    var body: some View {
        Form {
            Section("人形检测") {
                Toggle("启用人形检测", isOn: $settings.humanDetectionEnabled)
                
                HStack {
                    Text("置信度阈值")
                    Slider(value: $settings.humanDetectionThreshold, in: 0.3...1.0, step: 0.1)
                    Text(String(format: "%.1f", settings.humanDetectionThreshold))
                        .frame(width: 50)
                }
            }
            
            Section("运动检测") {
                Toggle("启用运动检测", isOn: $settings.motionDetectionEnabled)
                
                HStack {
                    Text("灵敏度")
                    Slider(value: $settings.motionDetectionSensitivity, in: 0.01...0.1, step: 0.01)
                    Text(String(format: "%.0f%%", settings.motionDetectionSensitivity * 100))
                        .frame(width: 50)
                }
            }
            
            Section("环境变化") {
                Toggle("启用环境变化检测", isOn: $settings.environmentChangeDetectionEnabled)
            }
        }
        .padding()
    }
}

struct TelegramSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var botToken = ""
    @State private var chatId = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        Form {
            Section("Telegram Bot 配置") {
                SecureField("Bot Token", text: $botToken)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Chat ID", text: $chatId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                HStack {
                    Button("保存配置") {
                        saveConfiguration()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("测试连接") {
                        testConnection()
                    }
                }
            }
            
            Section("发送选项") {
                Toggle("发送前先保存到本地", isOn: $settings.saveBeforeSending)
                
                Toggle("使用代理", isOn: $settings.useProxy)
                
                if settings.useProxy {
                    TextField("代理地址", text: $settings.proxyAddress)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
        }
        .padding()
        .onAppear {
            botToken = settings.telegramBotToken ?? ""
            chatId = settings.telegramChatId ?? ""
        }
        .alert("提示", isPresented: $showingAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func saveConfiguration() {
        if !botToken.isEmpty {
            KeychainManager.shared.saveTelegramToken(botToken)
            settings.telegramBotToken = botToken
        }
        
        if !chatId.isEmpty {
            KeychainManager.shared.saveTelegramChatId(chatId)
            settings.telegramChatId = chatId
        }
        
        alertMessage = "配置已保存"
        showingAlert = true
    }
    
    private func testConnection() {
        Task {
            let success = await TelegramUploader.shared.testConnection()
            alertMessage = success ? "连接成功" : "连接失败，请检查配置"
            showingAlert = true
        }
    }
}

struct PrivacySettingsView: View {
    @StateObject private var settings = AppSettings.shared
    
    var body: some View {
        Form {
            Section("本地存储") {
                Toggle("本地加密存储", isOn: $settings.encryptLocalStorage)
                
                Toggle("发送成功后删除本地文件", isOn: $settings.deleteAfterSending)
                
                HStack {
                    Text("本地保留天数")
                    Slider(value: $settings.localRetentionDays, in: 1...30, step: 1)
                    Text("\(Int(settings.localRetentionDays))天")
                        .frame(width: 50)
                }
            }
            
            Section("数据安全") {
                Button("清除所有本地数据") {
                    clearLocalData()
                }
                .foregroundColor(.red)
            }
        }
        .padding()
    }
    
    private func clearLocalData() {
        
    }
}

struct AdvancedSettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var logLevel = "info"
    @State private var isTestingCamera = false
    
    var body: some View {
        Form {
            Section("日志") {
                Picker("日志级别", selection: $logLevel) {
                    Text("调试").tag("debug")
                    Text("信息").tag("info")
                    Text("警告").tag("warning")
                    Text("错误").tag("error")
                }
                
                Button("导出日志") {
                    exportLogs()
                }
            }
            
            Section("诊断") {
                HStack {
                    if isTestingCamera {
                        Button("取消测试") {
                            CaptureService.shared.cancelTest()
                            isTestingCamera = false
                        }
                        .foregroundColor(.red)
                        
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.leading, 5)
                    } else {
                        Button("触发测试抓拍") {
                            isTestingCamera = true
                            Task {
                                await CaptureService.shared.captureTestSnapshot()
                                isTestingCamera = false
                            }
                        }
                    }
                }
                
                Button("测试唤醒录屏") {
                    Task {
                        Logger.shared.log("Testing wake/unlock recording", level: .info)
                        await CaptureService.shared.captureTriggeredEvidence(
                            type: .wakeUnlock,
                            duration: min(AppSettings.shared.videoDuration, 10) // Max 10 seconds for testing
                        )
                    }
                }
                .buttonStyle(.bordered)
                
                Button("查看系统信息") {
                    showSystemInfo()
                }
            }
        }
        .padding()
    }
    
    private func exportLogs() {
        Logger.shared.exportLogs()
    }
    
    private func showSystemInfo() {
        
    }
}