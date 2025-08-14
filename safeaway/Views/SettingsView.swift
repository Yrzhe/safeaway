import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var localization = LocalizationManager.shared
    @State private var selectedTab = 0
    @State private var showingTestAlert = false
    @State private var testMessage = ""
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label(L[LocalizedStringKey.general], systemImage: "gear")
                }
                .tag(0)
            
            CaptureSettingsView()
                .tabItem {
                    Label(L[LocalizedStringKey.capture], systemImage: "camera")
                }
                .tag(1)
            
            DetectionSettingsView()
                .tabItem {
                    Label(L[LocalizedStringKey.detection], systemImage: "eye")
                }
                .tag(2)
            
            NotificationSettingsView()
                .tabItem {
                    Label(L[LocalizedStringKey.notifications], systemImage: "bell")
                }
                .tag(3)
            
            PrivacySettingsView()
                .tabItem {
                    Label(L[LocalizedStringKey.privacy], systemImage: "lock")
                }
                .tag(4)
            
            AdvancedSettingsView()
                .tabItem {
                    Label(L[LocalizedStringKey.advanced], systemImage: "wrench.and.screwdriver")
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
    @StateObject private var localization = LocalizationManager.shared
    @State private var isSelfTesting = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L[LocalizedStringKey.appName])
                    .font(.title)
                    .fontWeight(.bold)
            
            HStack {
                Circle()
                    .fill(appState.isMonitoring ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(appState.isMonitoring ? L[LocalizedStringKey.monitoring] : L[LocalizedStringKey.notStarted])
                    .foregroundColor(appState.isMonitoring ? .green : .gray)
                
                Spacer()
                
                Button(appState.isMonitoring ? L[LocalizedStringKey.stopMonitoring] : L[LocalizedStringKey.startMonitoring]) {
                    toggleMonitoring()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                Text(L[LocalizedStringKey.status])
                    .font(.headline)
                
                HStack {
                    Text(L[LocalizedStringKey.cameraPermission])
                    Text(PermissionManager.shared.hasCameraPermission ? L[LocalizedStringKey.authorized] : L[LocalizedStringKey.unauthorized])
                        .foregroundColor(PermissionManager.shared.hasCameraPermission ? .green : .red)
                }
                
                HStack {
                    Text(L[LocalizedStringKey.telegramConnection])
                    Text(settings.telegramBotToken != nil ? L[LocalizedStringKey.configured] : L[LocalizedStringKey.notConfigured])
                        .foregroundColor(settings.telegramBotToken != nil ? .green : .orange)
                }
                
                if let lastCapture = appState.lastCaptureTime {
                    HStack {
                        Text(L[LocalizedStringKey.lastCapture])
                        Text("\(lastCapture, formatter: dateFormatter)")
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Text(L[LocalizedStringKey.captureCount])
                    Text("\(appState.captureCount)")
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            HStack {
                Text(L[LocalizedStringKey.language])
                Picker("", selection: $localization.currentLanguage) {
                    ForEach(Language.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 150)
            }
            
            Toggle(L[LocalizedStringKey.launchAtLogin], isOn: $settings.launchAtLogin)
                .onChange(of: settings.launchAtLogin) { _, newValue in
                    if newValue {
                        AppSettings.shared.registerLoginItem()
                    } else {
                        AppSettings.shared.unregisterLoginItem()
                    }
                }
            
            Toggle(L[LocalizedStringKey.autoStartMonitoring], isOn: $settings.autoStartMonitoring)
                .help(L[LocalizedStringKey.autoStartMonitoring])
            
            HStack {
                if isSelfTesting {
                    Button(L[LocalizedStringKey.cancelTest]) {
                        CaptureService.shared.cancelTest()
                        isSelfTesting = false
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.leading, 5)
                } else {
                    Button(L[LocalizedStringKey.selfTest]) {
                        isSelfTesting = true
                        Task {
                            await performSelfTest()
                            isSelfTesting = false
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                Button(L[LocalizedStringKey.testUnlockRecording]) {
                    Task {
                        await CaptureService.shared.testUnlockRecording()
                    }
                }
                .buttonStyle(.bordered)
                .help(L[LocalizedStringKey.testUnlockRecording])
                
                Button(L[LocalizedStringKey.clearStats]) {
                    clearStats()
                }
                .buttonStyle(.bordered)
            }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            Section(L[LocalizedStringKey.captureSettings]) {
                HStack {
                    Text(L[LocalizedStringKey.lockScreenCaptureInterval])
                    Slider(value: $settings.captureInterval, in: 5...60, step: 5)
                    Text("\(Int(settings.captureInterval))\(L[LocalizedStringKey.seconds])")
                        .frame(width: 50)
                }
                
                HStack {
                    Text(L[LocalizedStringKey.wakeVideoLength])
                    Slider(value: $settings.videoDuration, in: 5...30, step: 5)
                    Text("\(Int(settings.videoDuration))\(L[LocalizedStringKey.seconds])")
                        .frame(width: 50)
                }
                
                Toggle(L[LocalizedStringKey.enableScreenRecording], isOn: $settings.screenRecordingEnabled)
                
                Picker(L[LocalizedStringKey.imageFormat], selection: $settings.imageFormat) {
                    Text("JPEG").tag("jpeg")
                    Text("HEIF").tag("heif")
                }
                
                Picker(L[LocalizedStringKey.videoQuality], selection: $settings.videoQuality) {
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
            Section(L[LocalizedStringKey.humanDetection]) {
                Toggle(L[LocalizedStringKey.enableHumanDetection], isOn: $settings.humanDetectionEnabled)
                
                HStack {
                    Text(L[LocalizedStringKey.confidenceThreshold])
                    Slider(value: $settings.humanDetectionThreshold, in: 0.3...1.0, step: 0.1)
                    Text(String(format: "%.1f", settings.humanDetectionThreshold))
                        .frame(width: 50)
                }
            }
            
            Section(L[LocalizedStringKey.motionDetection]) {
                Toggle(L[LocalizedStringKey.enableMotionDetection], isOn: $settings.motionDetectionEnabled)
                
                HStack {
                    Text(L[LocalizedStringKey.sensitivity])
                    Slider(value: $settings.motionDetectionSensitivity, in: 0.01...0.1, step: 0.01)
                    Text(String(format: "%.0f%%", settings.motionDetectionSensitivity * 100))
                        .frame(width: 50)
                }
            }
            
            Section(L[LocalizedStringKey.environmentChange]) {
                Toggle(L[LocalizedStringKey.enableEnvironmentDetection], isOn: $settings.environmentChangeDetectionEnabled)
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
            Section(L[LocalizedStringKey.telegramBotConfig]) {
                SecureField("Bot Token", text: $botToken)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Chat ID", text: $chatId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                HStack {
                    Button(L[LocalizedStringKey.saveConfig]) {
                        saveConfiguration()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(L[LocalizedStringKey.testConnection]) {
                        testConnection()
                    }
                }
            }
            
            Section(L[LocalizedStringKey.sendOptions]) {
                Toggle(L[LocalizedStringKey.saveBeforeSending], isOn: $settings.saveBeforeSending)
                
                Toggle(L[LocalizedStringKey.useProxy], isOn: $settings.useProxy)
                
                if settings.useProxy {
                    TextField(L[LocalizedStringKey.proxyAddress], text: $settings.proxyAddress)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
        }
        .padding()
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
            KeychainManager.shared.saveTelegramToken(botToken)
            settings.telegramBotToken = botToken
        }
        
        if !chatId.isEmpty {
            KeychainManager.shared.saveTelegramChatId(chatId)
            settings.telegramChatId = chatId
        }
        
        alertMessage = L[LocalizedStringKey.configSaved]
        showingAlert = true
    }
    
    private func testConnection() {
        Task {
            let success = await TelegramUploader.shared.testConnection()
            alertMessage = success ? L[LocalizedStringKey.connectionSuccess] : L[LocalizedStringKey.connectionFailed]
            showingAlert = true
        }
    }
}

struct PrivacySettingsView: View {
    @StateObject private var settings = AppSettings.shared
    
    var body: some View {
        Form {
            Section(L[LocalizedStringKey.localStorage]) {
                Toggle(L[LocalizedStringKey.encryptLocalStorage], isOn: $settings.encryptLocalStorage)
                
                Toggle(L[LocalizedStringKey.deleteAfterSending], isOn: $settings.deleteAfterSending)
                
                HStack {
                    Text(L[LocalizedStringKey.retentionDays])
                    Slider(value: $settings.localRetentionDays, in: 1...30, step: 1)
                    Text("\(Int(settings.localRetentionDays))\(L[LocalizedStringKey.days])")
                        .frame(width: 50)
                }
            }
            
            Section(L[LocalizedStringKey.dataSecurity]) {
                Button(L[LocalizedStringKey.clearAllData]) {
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
            Section(L[LocalizedStringKey.logs]) {
                Picker(L[LocalizedStringKey.logLevel], selection: $logLevel) {
                    Text(L[LocalizedStringKey.debug]).tag("debug")
                    Text(L[LocalizedStringKey.info]).tag("info")
                    Text(L[LocalizedStringKey.warning]).tag("warning")
                    Text(L[LocalizedStringKey.error]).tag("error")
                }
                
                Button(L[LocalizedStringKey.exportLogs]) {
                    exportLogs()
                }
            }
            
            Section(L[LocalizedStringKey.diagnostics]) {
                HStack {
                    if isTestingCamera {
                        Button(L[LocalizedStringKey.cancel]) {
                            CaptureService.shared.cancelTest()
                            isTestingCamera = false
                        }
                        .foregroundColor(.red)
                        
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.leading, 5)
                    } else {
                        Button(L[LocalizedStringKey.triggerTestCapture]) {
                            isTestingCamera = true
                            Task {
                                await CaptureService.shared.captureTestSnapshot()
                                isTestingCamera = false
                            }
                        }
                    }
                }
                
                Button(L[LocalizedStringKey.testWakeRecording]) {
                    Task {
                        Logger.shared.log("Testing wake/unlock recording", level: .info)
                        await CaptureService.shared.captureTriggeredEvidence(
                            type: .wakeUnlock,
                            duration: min(AppSettings.shared.videoDuration, 10) // Max 10 seconds for testing
                        )
                    }
                }
                .buttonStyle(.bordered)
                
                Button(L[LocalizedStringKey.viewSystemInfo]) {
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