import Foundation
import AppKit
import Combine

enum SystemEvent {
    case screenDidSleep
    case screenDidWake
    case screenIsLocked
    case screenIsUnlocked
    case systemWillSleep
    case systemDidWake
}

@MainActor
class EventHub: ObservableObject {
    static let shared = EventHub()
    
    @Published var currentState: SystemState = .active
    @Published var isMonitoring = false
    
    private var captureScheduler: CaptureScheduler?
    private var cancellables = Set<AnyCancellable>()
    private let eventSubject = PassthroughSubject<SystemEvent, Never>()
    
    var eventPublisher: AnyPublisher<SystemEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }
    
    enum SystemState {
        case active
        case screenLocked
        case screenSleep
        case systemSleep
    }
    
    private init() {
        setupEventHandlers()
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        Logger.shared.log("Event monitoring started", level: .info)
        
        registerNotifications()
        
        captureScheduler = CaptureScheduler()
        
        eventPublisher
            .sink { [weak self] event in
                self?.handleEvent(event)
            }
            .store(in: &cancellables)
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        
        unregisterNotifications()
        
        cancellables.removeAll()
        
        Task {
            await captureScheduler?.stop()
            captureScheduler = nil
        }
        
        Logger.shared.log("Event monitoring stopped", level: .info)
    }
    
    private func registerNotifications() {
        let workspace = NSWorkspace.shared
        let nc = workspace.notificationCenter
        
        nc.addObserver(
            self,
            selector: #selector(screenDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        
        nc.addObserver(
            self,
            selector: #selector(screenDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        
        nc.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        
        nc.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenIsLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenIsUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }
    
    private func unregisterNotifications() {
        let workspace = NSWorkspace.shared
        let nc = workspace.notificationCenter
        
        nc.removeObserver(self, name: NSWorkspace.screensDidSleepNotification, object: nil)
        nc.removeObserver(self, name: NSWorkspace.screensDidWakeNotification, object: nil)
        nc.removeObserver(self, name: NSWorkspace.willSleepNotification, object: nil)
        nc.removeObserver(self, name: NSWorkspace.didWakeNotification, object: nil)
        
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }
    
    @objc private func screenDidSleep() {
        Logger.shared.log("Screen did sleep", level: .info)
        eventSubject.send(.screenDidSleep)
        currentState = .screenSleep
    }
    
    @objc private func screenDidWake() {
        Logger.shared.log("🔆 SCREEN WAKE - Current state: \(currentState), Monitoring: \(isMonitoring)", level: .info)
        eventSubject.send(.screenDidWake)
        if currentState == .screenSleep {
            currentState = .active
        }
    }
    
    @objc private func screenIsLocked() {
        Logger.shared.log("Screen is locked - Current state: \(currentState), Monitoring: \(isMonitoring)", level: .info)
        eventSubject.send(.screenIsLocked)
        currentState = .screenLocked
    }
    
    @objc private func screenIsUnlocked() {
        Logger.shared.log("🔓 SCREEN UNLOCKED - Current state: \(currentState), Monitoring: \(isMonitoring)", level: .info)
        eventSubject.send(.screenIsUnlocked)
        if currentState == .screenLocked {
            currentState = .active
        }
    }
    
    @objc private func systemWillSleep() {
        Logger.shared.log("System will sleep", level: .info)
        eventSubject.send(.systemWillSleep)
        currentState = .systemSleep
    }
    
    @objc private func systemDidWake() {
        Logger.shared.log("System did wake", level: .info)
        eventSubject.send(.systemDidWake)
        if currentState == .systemSleep {
            currentState = .active
        }
    }
    
    private func setupEventHandlers() {
        
    }
    
    private func handleEvent(_ event: SystemEvent) {
        guard isMonitoring else { return }
        
        Task {
            switch event {
            case .screenDidSleep, .screenIsLocked:
                await startCapturing()
                
            case .screenDidWake, .screenIsUnlocked:
                await handleWakeOrUnlock()
                
            case .systemWillSleep:
                await captureScheduler?.stop()
                
            case .systemDidWake:
                if currentState == .screenLocked || currentState == .screenSleep {
                    await startCapturing()
                }
            }
        }
    }
    
    private func startCapturing() async {
        await captureScheduler?.start(interval: AppSettings.shared.captureInterval)
    }
    
    private func handleWakeOrUnlock() async {
        Logger.shared.log("🔓 ============ WAKE/UNLOCK EVENT DETECTED ============", level: .info)
        Logger.shared.log("Current monitoring state: \(isMonitoring)", level: .info)
        Logger.shared.log("Video duration setting: \(AppSettings.shared.videoDuration) seconds", level: .info)
        
        // Stop any ongoing scheduled captures first
        await captureScheduler?.stop()
        
        // Wait a moment to ensure capture session is ready
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        Logger.shared.log("📹 Triggering evidence capture for wake/unlock...", level: .info)
        // Capture evidence (this will handle starting the session internally)
        await CaptureService.shared.captureTriggeredEvidence(
            type: .wakeUnlock,
            duration: AppSettings.shared.videoDuration
        )
        
        Logger.shared.log("✅ Wake/unlock evidence capture completed", level: .info)
        Logger.shared.log("============ WAKE/UNLOCK EVENT FINISHED ============", level: .info)
        
        // If we're back to active state and not locked/sleeping, stop scheduled captures
        if currentState == .active {
            await captureScheduler?.stop()
        } else {
            // If still locked/sleeping, restart scheduled captures
            await startCapturing()
        }
    }
}

actor CaptureScheduler {
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.safeaway.capture", qos: .utility)
    private var isActive = false
    
    func start(interval: TimeInterval) {
        stop()
        
        isActive = true
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: interval)
        timer?.setEventHandler { [weak self] in
            Task {
                guard await self?.isActive == true else { return }
                await self?.performScheduledCapture()
            }
        }
        timer?.resume()
        
        Logger.shared.log("Capture scheduler started with interval: \(interval)s", level: .debug)
    }
    
    func stop() {
        isActive = false
        timer?.cancel()
        timer = nil
        Task { @MainActor in
            CaptureService.shared.stopCaptureSession()
        }
        Logger.shared.log("Capture scheduler stopped", level: .debug)
    }
    
    private func performScheduledCapture() async {
        guard isActive else { return }
        await CaptureService.shared.captureSnapshot()
    }
}