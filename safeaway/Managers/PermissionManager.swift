import Foundation
import AVFoundation
import CoreLocation
import AppKit
import ScreenCaptureKit

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var hasCameraPermission = false
    @Published var hasMicrophonePermission = false
    @Published var hasScreenRecordingPermission = false
    @Published var hasLocationPermission = false
    
    private let locationManager = CLLocationManager()
    
    private init() {
        checkAllPermissions()
    }
    
    func checkAllPermissions() {
        checkCameraPermission()
        checkMicrophonePermission()
        checkScreenRecordingPermission()
        checkLocationPermission()
    }
    
    func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasCameraPermission = true
        case .notDetermined:
            hasCameraPermission = false
        case .denied, .restricted:
            hasCameraPermission = false
        @unknown default:
            hasCameraPermission = false
        }
    }
    
    func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasMicrophonePermission = true
        case .notDetermined:
            hasMicrophonePermission = false
        case .denied, .restricted:
            hasMicrophonePermission = false
        @unknown default:
            hasMicrophonePermission = false
        }
    }
    
    func checkScreenRecordingPermission() {
        if #available(macOS 12.3, *) {
            Task {
                do {
                    let _ = try await SCShareableContent.current
                    await MainActor.run {
                        self.hasScreenRecordingPermission = true
                    }
                } catch {
                    await MainActor.run {
                        self.hasScreenRecordingPermission = false
                    }
                }
            }
        } else {
            hasScreenRecordingPermission = false
        }
    }
    
    func checkLocationPermission() {
        switch locationManager.authorizationStatus {
        case .authorized, .authorizedAlways:
            hasLocationPermission = true
        case .notDetermined, .denied, .restricted:
            hasLocationPermission = false
        @unknown default:
            hasLocationPermission = false
        }
    }
    
    func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasCameraPermission = true
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.hasCameraPermission = granted
                    completion(granted)
                }
            }
        case .denied, .restricted:
            hasCameraPermission = false
            completion(false)
            showPermissionAlert(for: "摄像头")
        @unknown default:
            completion(false)
        }
    }
    
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasMicrophonePermission = true
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.hasMicrophonePermission = granted
                    completion(granted)
                }
            }
        case .denied, .restricted:
            hasMicrophonePermission = false
            completion(false)
            showPermissionAlert(for: "麦克风")
        @unknown default:
            completion(false)
        }
    }
    
    func requestLocationPermission() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        } else if locationManager.authorizationStatus == .denied {
            showPermissionAlert(for: "位置")
        }
    }
    
    func requestScreenRecordingPermission() {
        showScreenRecordingInstructions()
    }
    
    private func showPermissionAlert(for permission: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "\(permission)权限被拒绝"
            alert.informativeText = "SafeAway 需要\(permission)权限才能正常工作。请在系统设置中授予权限。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            
            if alert.runModal() == .alertFirstButtonReturn {
                self.openSystemPreferences()
            }
        }
    }
    
    private func showScreenRecordingInstructions() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "需要屏幕录制权限"
            alert.informativeText = """
            请按照以下步骤授权：
            1. 打开系统设置
            2. 前往「隐私与安全性」
            3. 选择「屏幕录制」
            4. 勾选 SafeAway
            5. 重启应用
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后")
            
            if alert.runModal() == .alertFirstButtonReturn {
                self.openSystemPreferences()
            }
        }
    }
    
    private func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func showOnboardingIfNeeded() {
        let hasShownOnboarding = UserDefaults.standard.bool(forKey: "HasShownOnboarding")
        
        if !hasShownOnboarding {
            showOnboarding()
            UserDefaults.standard.set(true, forKey: "HasShownOnboarding")
        }
    }
    
    private func showOnboarding() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "欢迎使用 SafeAway"
            alert.informativeText = """
            SafeAway 是一款安全监控应用，可以在您离开电脑时自动进行安防取证。
            
            主要功能：
            • 息屏/锁屏时自动拍照
            • 检测人形和运动
            • 通过 Telegram Bot 发送通知
            • 本地加密存储
            
            接下来将请求必要的系统权限。
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "开始设置")
            alert.addButton(withTitle: "稍后")
            
            if alert.runModal() == .alertFirstButtonReturn {
                self.requestAllPermissions()
            }
        }
    }
    
    func requestAllPermissions() {
        requestCameraPermission { _ in
            self.requestMicrophonePermission { _ in
                self.requestLocationPermission()
                self.requestScreenRecordingPermission()
            }
        }
    }
}