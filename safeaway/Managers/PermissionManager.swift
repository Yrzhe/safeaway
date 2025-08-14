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
            showPermissionAlert(for: L[LocalizedStringKey.camera])
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
            showPermissionAlert(for: L[LocalizedStringKey.microphone])
        @unknown default:
            completion(false)
        }
    }
    
    func requestLocationPermission() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        } else if locationManager.authorizationStatus == .denied {
            showPermissionAlert(for: L[LocalizedStringKey.location])
        }
    }
    
    func requestScreenRecordingPermission() {
        showScreenRecordingInstructions()
    }
    
    private func showPermissionAlert(for permission: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "\(permission) \(L[LocalizedStringKey.permissionDenied])"
            alert.informativeText = "SafeAway \(L[LocalizedStringKey.permissionRequired])"
            alert.alertStyle = .warning
            alert.addButton(withTitle: L[LocalizedStringKey.openSystemSettings])
            alert.addButton(withTitle: L[LocalizedStringKey.cancel])
            
            if alert.runModal() == .alertFirstButtonReturn {
                self.openSystemPreferences()
            }
        }
    }
    
    private func showScreenRecordingInstructions() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = L[LocalizedStringKey.needScreenPermission]
            alert.informativeText = L[LocalizedStringKey.screenPermissionInstructions]
            alert.alertStyle = .informational
            alert.addButton(withTitle: L[LocalizedStringKey.openSystemSettings])
            alert.addButton(withTitle: L[LocalizedStringKey.later])
            
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
            alert.messageText = L[LocalizedStringKey.welcomeTitle]
            alert.informativeText = L[LocalizedStringKey.welcomeMessage]
            alert.alertStyle = .informational
            alert.addButton(withTitle: L[LocalizedStringKey.startSetup])
            alert.addButton(withTitle: L[LocalizedStringKey.later])
            
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