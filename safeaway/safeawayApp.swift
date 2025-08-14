import SwiftUI
import AppKit

@main
struct SafeAwayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                EmptyView()
            }
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    var popover: NSPopover!
    var statusBarMenu: NSMenu!
    private var eventHub: EventHub!
    private var captureService: CaptureService!
    private var telegramUploader: TelegramUploader!
    private var monitoringMenuItem: NSMenuItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        setupStatusBar()
        initializeServices()
        requestPermissions()
        
        Logger.shared.log("SafeAway started", level: .info)
    }
    
    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem.button {
            updateStatusBarIcon()
            button.action = #selector(statusBarButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
        
        setupMenu()
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: SettingsView())
    }
    
    private func setupMenu() {
        statusBarMenu = NSMenu()
        
        monitoringMenuItem = NSMenuItem(title: "开启监控", action: #selector(toggleMonitoring), keyEquivalent: "")
        monitoringMenuItem.target = self
        updateMonitoringMenuItemTitle()
        
        let settingsMenuItem = NSMenuItem(title: "设置...", action: #selector(showSettings), keyEquivalent: ",")
        settingsMenuItem.target = self
        
        let testMenuItem = NSMenuItem(title: "测试拍照", action: #selector(testCapture), keyEquivalent: "")
        testMenuItem.target = self
        
        let aboutMenuItem = NSMenuItem(title: "关于 SafeAway", action: #selector(showAbout), keyEquivalent: "")
        aboutMenuItem.target = self
        
        let quitMenuItem = NSMenuItem(title: "退出 SafeAway", action: #selector(quitApp), keyEquivalent: "q")
        quitMenuItem.target = self
        
        statusBarMenu.addItem(monitoringMenuItem)
        statusBarMenu.addItem(NSMenuItem.separator())
        statusBarMenu.addItem(settingsMenuItem)
        statusBarMenu.addItem(testMenuItem)
        statusBarMenu.addItem(NSMenuItem.separator())
        statusBarMenu.addItem(aboutMenuItem)
        statusBarMenu.addItem(NSMenuItem.separator())
        statusBarMenu.addItem(quitMenuItem)
    }
    
    private func updateStatusBarIcon() {
        if let button = statusBarItem.button {
            let isMonitoring = AppState.shared.isMonitoring
            let iconName = isMonitoring ? "lock.shield.fill" : "lock.shield"
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "SafeAway")
            
            if isMonitoring {
                button.image?.isTemplate = false
                button.contentTintColor = NSColor.systemGreen
            } else {
                button.image?.isTemplate = true
                button.contentTintColor = nil
            }
        }
    }
    
    private func updateMonitoringMenuItemTitle() {
        let isMonitoring = AppState.shared.isMonitoring
        monitoringMenuItem.title = isMonitoring ? "关闭监控" : "开启监控"
    }
    
    private func initializeServices() {
        eventHub = EventHub.shared
        captureService = CaptureService.shared
        telegramUploader = TelegramUploader.shared
        
        // 检查是否需要自动启动监控
        if AppSettings.shared.autoStartMonitoring {
            AppState.shared.startMonitoring()
            Logger.shared.log("Auto-starting monitoring based on user preference", level: .info)
            updateMonitoringMenuItemTitle()
            updateStatusBarIcon()
        } else {
            Logger.shared.log("Services initialized, monitoring not started automatically", level: .info)
        }
    }
    
    private func requestPermissions() {
        PermissionManager.shared.requestCameraPermission { granted in
            if granted {
                Logger.shared.log("Camera permission granted", level: .info)
            } else {
                Logger.shared.log("Camera permission denied", level: .error)
            }
        }
        
        // Also request microphone permission for video recording with audio
        PermissionManager.shared.requestMicrophonePermission { granted in
            if granted {
                Logger.shared.log("Microphone permission granted", level: .info)
            } else {
                Logger.shared.log("Microphone permission denied", level: .warning)
            }
        }
    }
    
    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            showMenu()
        }
    }
    
    @objc func showMenu() {
        statusBarItem.menu = statusBarMenu
        statusBarItem.button?.performClick(nil)
        statusBarItem.menu = nil
    }
    
    @objc func toggleMonitoring() {
        if AppState.shared.isMonitoring {
            AppState.shared.stopMonitoring()
            Logger.shared.log("Monitoring stopped by user", level: .info)
        } else {
            AppState.shared.startMonitoring()
            Logger.shared.log("Monitoring started by user", level: .info)
        }
        updateMonitoringMenuItemTitle()
        updateStatusBarIcon()
    }
    
    @objc func showSettings() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            if let button = statusBarItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            }
        }
    }
    
    @objc func testCapture() {
        Task {
            Logger.shared.log("Test capture initiated by user", level: .info)
            await CaptureService.shared.captureSnapshot()
        }
    }
    
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "SafeAway"
        alert.informativeText = """
        版本 1.0.0
        
        SafeAway 是一款 macOS 安全监控应用
        可在您离开电脑时自动进行安防取证
        
        © 2024 SafeAway
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    @objc func quitApp() {
        if AppState.shared.isMonitoring {
            let alert = NSAlert()
            alert.messageText = "确认退出"
            alert.informativeText = "监控正在运行中，确定要退出吗？"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "退出")
            alert.addButton(withTitle: "取消")
            
            if alert.runModal() == .alertFirstButtonReturn {
                AppState.shared.stopMonitoring()
                NSApplication.shared.terminate(nil)
            }
        } else {
            NSApplication.shared.terminate(nil)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}