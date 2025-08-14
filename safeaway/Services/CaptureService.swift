import Foundation
import AVFoundation
import AppKit
import Vision

enum CaptureType {
    case snapshot
    case wakeUnlock
    case humanDetected
    case motionDetected
}

final class CaptureService: NSObject, @unchecked Sendable {
    static let shared = CaptureService()
    
    // These properties are only accessed from sessionQueue
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureMovieFileOutput?
    private var currentDevice: AVCaptureDevice?
    
    private let visionService = VisionService.shared
    private let sessionQueue = DispatchQueue(label: "com.safeaway.capture.session", qos: .userInitiated)
    private var lastCapturedImage: NSImage?
    private var isRecording = false
    private var videoCompletionHandler: ((URL?) -> Void)?
    private var isTestingInProgress = false
    
    override private init() {
        super.init()
        setupCaptureSession()
    }
    
    private func setupCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let session = AVCaptureSession()
            session.sessionPreset = .hd1280x720
            
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) else {
                Logger.shared.log("No camera device available", level: .error)
                return
            }
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                
                if session.canAddInput(input) {
                    session.addInput(input)
                }
                
                let photoOut = AVCapturePhotoOutput()
                if session.canAddOutput(photoOut) {
                    session.addOutput(photoOut)
                }
                
                let videoOut = AVCaptureMovieFileOutput()
                // Set maximum recording duration
                videoOut.maxRecordedDuration = CMTime(seconds: 30, preferredTimescale: 600)
                // Don't use movie fragments - record as a single file
                videoOut.movieFragmentInterval = CMTime.invalid
                
                // Set connection video settings
                if session.canAddOutput(videoOut) {
                    session.addOutput(videoOut)
                    
                    // Configure video connection if available
                    if videoOut.connection(with: .video) != nil {
                        // Video stabilization is iOS-only, skip on macOS
                        Logger.shared.log("Video connection configured", level: .debug)
                    }
                    
                    Logger.shared.log("Video output added to capture session", level: .info)
                } else {
                    Logger.shared.log("Failed to add video output to capture session", level: .error)
                }
                
                // Store references (only accessed from sessionQueue)
                self.captureSession = session
                self.currentDevice = device
                self.photoOutput = photoOut
                self.videoOutput = videoOut
                
                Logger.shared.log("Capture session setup completed", level: .info)
                
            } catch {
                Logger.shared.log("Failed to setup capture session: \(error)", level: .error)
            }
        }
    }
    
    func captureSnapshot() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                if self.captureSession?.isRunning != true {
                    self.captureSession?.startRunning()
                    Thread.sleep(forTimeInterval: 0.5)
                }
                
                let settings = AVCapturePhotoSettings()
                settings.flashMode = .off
                
                self.photoOutput?.capturePhoto(with: settings, delegate: self)
                
                Logger.shared.log("Snapshot capture initiated", level: .debug)
                continuation.resume()
            }
        }
    }
    
    func captureTestSnapshot() async {
        Logger.shared.log("Starting test snapshot", level: .info)
        
        // Mark as testing
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                // If already testing, don't start another test
                if self.isTestingInProgress {
                    Logger.shared.log("Test already in progress, skipping", level: .warning)
                    continuation.resume()
                    return
                }
                
                self.isTestingInProgress = true
                Logger.shared.log("Test mode activated", level: .debug)
                continuation.resume()
            }
        }
        
        // Capture a single snapshot
        await captureSnapshot()
        
        // Wait a bit for photo processing to complete
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Stop testing and camera
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                self?.isTestingInProgress = false
                self?.stopCaptureSessionInternal()
                Logger.shared.log("Test mode deactivated and camera stopped", level: .debug)
                continuation.resume()
            }
        }
        
        Logger.shared.log("Test snapshot completed successfully", level: .info)
    }
    
    func testUnlockRecording() async {
        Logger.shared.log("🔧 ===== TESTING UNLOCK RECORDING FEATURE =====", level: .info)
        Logger.shared.log("📹 Simulating wake/unlock event with 5 second video", level: .info)
        
        // Test with a shorter duration for testing
        await captureTriggeredEvidence(type: .wakeUnlock, duration: 5.0)
        
        Logger.shared.log("✅ Test unlock recording completed", level: .info)
        Logger.shared.log("Check Telegram for the video message", level: .info)
    }
    
    func cancelTest() {
        sessionQueue.async { [weak self] in
            if self?.isTestingInProgress == true {
                self?.isTestingInProgress = false
                self?.stopCaptureSessionInternal()
                Logger.shared.log("Test cancelled", level: .info)
            }
        }
    }
    
    var isTesting: Bool {
        get async {
            await withCheckedContinuation { continuation in
                sessionQueue.async { [weak self] in
                    continuation.resume(returning: self?.isTestingInProgress ?? false)
                }
            }
        }
    }
    
    private func stopCaptureSessionInternal() {
        // Must be called from sessionQueue
        if captureSession?.isRunning == true {
            captureSession?.stopRunning()
            Logger.shared.log("Capture session stopped", level: .debug)
        }
    }
    
    func stopCaptureSession() {
        sessionQueue.async { [weak self] in
            self?.stopCaptureSessionInternal()
        }
    }
    
    func startCaptureSession() {
        sessionQueue.async { [weak self] in
            if self?.captureSession?.isRunning != true {
                self?.captureSession?.startRunning()
                Logger.shared.log("Capture session started", level: .debug)
            }
        }
    }
    
    func captureTriggeredEvidence(type: CaptureType, duration: TimeInterval) async {
        Logger.shared.log("🚨 Starting triggered evidence capture: \(type), duration: \(duration)s", level: .info)
        
        // For wake/unlock events, prioritize video recording
        if type == .wakeUnlock {
            Logger.shared.log("🔓 Wake/Unlock event detected - starting video capture", level: .info)
            // Start capture session
            startCaptureSession()
            
            // Give camera time to warm up properly
            Logger.shared.log("Warming up camera for video recording...", level: .debug)
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds for better initialization
            
            // Record video FIRST
            Logger.shared.log("📹 Starting video recording for \(type) with duration \(duration)s", level: .info)
            await recordVideo(duration: duration, type: type)
            Logger.shared.log("✅ Video recording completed for \(type)", level: .info)
            
            // After video, capture a snapshot for quick preview
            Logger.shared.log("Capturing snapshot after video for preview", level: .info)
            await captureSnapshot()
        } else {
            // For other types, keep the original behavior
            startCaptureSession()
            
            // Give camera time to warm up properly
            Logger.shared.log("Warming up camera...", level: .debug)
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds for better initialization
            
            // Capture 3 quick snapshots
            Logger.shared.log("Starting snapshot capture sequence for \(type)", level: .info)
            for i in 1...3 {
                await captureSnapshot()
                Logger.shared.log("Snapshot \(i)/3 captured", level: .info)
                if i < 3 {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds between shots
                }
            }
            
            // Wait a moment before starting video to ensure camera is ready
            Logger.shared.log("Preparing for video recording...", level: .debug)
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second wait
            
            // Record video
            Logger.shared.log("Starting video recording for \(type) with duration \(duration)s", level: .info)
            await recordVideo(duration: duration, type: type)
            Logger.shared.log("Video recording completed for \(type)", level: .info)
        }
        
        Logger.shared.log("Triggered evidence capture completed: \(type)", level: .info)
    }
    
    func recordVideo(duration: TimeInterval, type: CaptureType) async {
        guard !isRecording else {
            Logger.shared.log("Already recording, skipping new request", level: .warning)
            return
        }
        
        Logger.shared.log("recordVideo called with duration: \(duration), type: \(type)", level: .info)
        
        // Check camera permission first
        let videoAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        Logger.shared.log("Camera authorization status: \(videoAuthStatus.rawValue)", level: .info)
        
        if videoAuthStatus != .authorized {
            Logger.shared.log("Camera not authorized for video recording!", level: .error)
            if videoAuthStatus == .notDetermined {
                Logger.shared.log("Requesting camera permission...", level: .info)
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if !granted {
                    Logger.shared.log("Camera permission denied by user", level: .error)
                    return
                }
            } else {
                return
            }
        }
        
        // Check microphone permission for video with audio
        let audioAuthStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        Logger.shared.log("Microphone authorization status: \(audioAuthStatus.rawValue)", level: .info)
        
        if audioAuthStatus != .authorized {
            Logger.shared.log("Microphone not authorized for video recording!", level: .warning)
            if audioAuthStatus == .notDetermined {
                Logger.shared.log("Requesting microphone permission...", level: .info)
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                if !granted {
                    Logger.shared.log("Microphone permission denied by user", level: .warning)
                    // Continue without audio
                }
            }
        }
        
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    Logger.shared.log("Self is nil in recordVideo", level: .error)
                    continuation.resume()
                    return
                }
                
                // Ensure capture session is running
                if self.captureSession?.isRunning != true {
                    Logger.shared.log("Capture session not running, starting it now", level: .info)
                    self.captureSession?.startRunning()
                    // Give camera time to warm up
                    Thread.sleep(forTimeInterval: 1.0) // Increased from 0.5 to 1.0 for better stability
                }
                
                // Check if video output is ready
                guard let videoOutput = self.videoOutput else {
                    Logger.shared.log("Video output not available - videoOutput is nil", level: .error)
                    continuation.resume()
                    return
                }
                
                let timestamp = ISO8601DateFormatter().string(from: Date())
                // Use .mov extension as AVCaptureMovieFileOutput creates QuickTime files
                let fileName = "evidence_\(type)_\(timestamp).mov"
                
                // Create a temporary directory that persists for the upload
                let tempDir = FileManager.default.temporaryDirectory
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                
                let outputURL = tempDir.appendingPathComponent(fileName)
                Logger.shared.log("📁 Video will be saved to: \(outputURL.path)", level: .info)
                
                // Remove file if it exists
                try? FileManager.default.removeItem(at: outputURL)
                
                self.isRecording = true
                
                // Set up completion handler that will be called when recording finishes
                self.videoCompletionHandler = { url in
                    Logger.shared.log("📹 Video completion handler called", level: .info)
                    if let url = url {
                        Logger.shared.log("📹 Video recording completed, file at: \(url.path)", level: .info)
                        
                        // Verify file exists before processing
                        if FileManager.default.fileExists(atPath: url.path) {
                            Logger.shared.log("✅ Video file exists, size check...", level: .info)
                            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                               let fileSize = attributes[.size] as? Int64 {
                                let sizeMB = Double(fileSize) / (1024 * 1024)
                                Logger.shared.log("📊 Video file size: \(String(format: "%.2f", sizeMB)) MB", level: .info)
                            }
                            
                            // Process video immediately without switching contexts
                            Task {
                                Logger.shared.log("📤 Starting video upload to Telegram...", level: .info)
                                await self.processVideo(url: url, type: type)
                                Logger.shared.log("✅ Video upload process completed", level: .info)
                            }
                        } else {
                            Logger.shared.log("❌ Video file does not exist at completion: \(url.path)", level: .error)
                        }
                    } else {
                        Logger.shared.log("❌ Video recording failed - no URL provided", level: .error)
                    }
                    continuation.resume()
                }
                
                // Check if video output is available
                let connectionCount = videoOutput.connections.count
                Logger.shared.log("Video output connections count: \(connectionCount)", level: .info)
                
                guard connectionCount > 0 else {
                    Logger.shared.log("No connections available for video output", level: .error)
                    self.isRecording = false
                    self.videoCompletionHandler = nil
                    continuation.resume()
                    return
                }
                
                // Check if we can actually record
                if !videoOutput.isRecording {
                    Logger.shared.log("Starting video recording to: \(outputURL.path)", level: .info)
                    Logger.shared.log("Video output isRecording before start: \(videoOutput.isRecording)", level: .debug)
                    
                    // Check for active connection
                    if let connection = videoOutput.connection(with: .video) {
                        Logger.shared.log("Video connection found, isActive: \(connection.isActive), isEnabled: \(connection.isEnabled)", level: .info)
                        
                        // Ensure connection is enabled
                        if !connection.isEnabled {
                            Logger.shared.log("Enabling video connection", level: .info)
                            connection.isEnabled = true
                        }
                    } else {
                        Logger.shared.log("No video connection found!", level: .error)
                        self.isRecording = false
                        self.videoCompletionHandler = nil
                        continuation.resume()
                        return
                    }
                    
                    // Ensure we have available recording time
                    let availableTime = videoOutput.maxRecordedDuration
                    Logger.shared.log("Max recording duration: \(availableTime.seconds) seconds", level: .debug)
                    
                    videoOutput.startRecording(to: outputURL, recordingDelegate: self)
                    
                    // Wait a moment and check if recording actually started
                    Thread.sleep(forTimeInterval: 1.0) // Increased wait time to 1 second
                    Logger.shared.log("Video output isRecording after start: \(videoOutput.isRecording)", level: .info)
                    
                    if !videoOutput.isRecording {
                        Logger.shared.log("WARNING: Video recording did not start! Checking if file exists anyway...", level: .error)
                        if FileManager.default.fileExists(atPath: outputURL.path) {
                            Logger.shared.log("File exists at output path despite isRecording being false", level: .warning)
                        }
                        self.isRecording = false
                        self.videoCompletionHandler = nil
                        continuation.resume()
                        return
                    }
                    
                    Logger.shared.log("Video recording confirmed started - type: \(type), duration: \(duration)s", level: .info)
                } else {
                    Logger.shared.log("Video output already recording, cannot start new recording", level: .error)
                    self.isRecording = false
                    self.videoCompletionHandler = nil
                    continuation.resume()
                    return
                }
                
                // Schedule stop after duration
                Logger.shared.log("Scheduling video stop after \(duration) seconds", level: .debug)
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                    self?.sessionQueue.async {
                        if let videoOutput = self?.videoOutput {
                            if videoOutput.isRecording {
                                Logger.shared.log("Stopping video recording after \(duration)s - isRecording: true", level: .info)
                                videoOutput.stopRecording()
                            } else {
                                Logger.shared.log("Video output is not recording when trying to stop", level: .warning)
                            }
                        } else {
                            Logger.shared.log("Video output is nil when trying to stop", level: .error)
                        }
                        
                        if self?.isRecording == true {
                            Logger.shared.log("Internal isRecording flag was still true", level: .debug)
                        }
                    }
                }
                
                Logger.shared.log("Video recording scheduled for \(duration)s, continuation will resume when recording completes", level: .info)
            }
        }
        
        Logger.shared.log("recordVideo function completed, waiting for processing", level: .debug)
    }
    
    private func processSnapshot(_ image: NSImage) async {
        // Skip processing if it's a test
        let isTest = await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                continuation.resume(returning: self?.isTestingInProgress ?? false)
            }
        }
        
        if isTest {
            Logger.shared.log("Test snapshot captured, skipping upload", level: .info)
            return
        }
        
        // Update capture statistics
        await MainActor.run {
            AppState.shared.updateCaptureStats()
        }
        
        let hasHuman = await visionService.detectHuman(in: image)
        let hasMotion = await visionService.detectMotion(current: image, previous: lastCapturedImage)
        
        lastCapturedImage = image
        
        let priority: TelegramUploader.Priority = hasHuman ? .high : .normal
        let tags = [hasHuman ? "human" : nil, hasMotion ? "motion" : nil].compactMap { $0 }
        
        let caption = buildCaption(type: .snapshot, tags: tags)
        
        if let imageData = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: imageData),
           let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            
            await TelegramUploader.shared.uploadPhoto(
                data: jpegData,
                caption: caption,
                priority: priority
            )
        }
    }
    
    private func processVideo(url: URL, type: CaptureType) async {
        Logger.shared.log("📤 Processing video for Telegram upload at: \(url.path)", level: .info)
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            Logger.shared.log("❌ Video file does not exist at: \(url.path)", level: .error)
            return
        }
        
        // Get file size for logging
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attributes[.size] as? Int64 {
            let sizeMB = Double(fileSize) / (1024 * 1024)
            Logger.shared.log("Video file size: \(String(format: "%.2f", sizeMB)) MB", level: .info)
        }
        
        // Update capture statistics
        await MainActor.run {
            AppState.shared.updateCaptureStats()
        }
        
        let caption = buildCaption(type: type, tags: [])
        Logger.shared.log("📝 Video caption: \(caption)", level: .info)
        Logger.shared.log("🚀 Uploading video to Telegram with high priority...", level: .info)
        
        await TelegramUploader.shared.uploadVideo(
            url: url,
            caption: caption,
            priority: type == .wakeUnlock ? .high : .normal
        )
        
        Logger.shared.log("✅ Video upload to Telegram completed", level: .info)
        
        // Don't clean up immediately - let the uploader handle it
        Logger.shared.log("📁 Video file kept at: \(url.path) for upload processing", level: .debug)
    }
    
    private func buildCaption(type: CaptureType, tags: [String]) -> String {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        let typeStr = switch type {
        case .snapshot: "定时快照"
        case .wakeUnlock: "唤醒/解锁"
        case .humanDetected: "检测到人形"
        case .motionDetected: "检测到运动"
        }
        
        var caption = "🔒 SafeAway\n"
        caption += "📅 \(timestamp)\n"
        caption += "📸 \(typeStr)\n"
        
        if !tags.isEmpty {
            caption += "🏷 \(tags.joined(separator: ", "))\n"
        }
        
        if let deviceName = Host.current().localizedName {
            caption += "💻 \(deviceName)"
        }
        
        return caption
    }
}

extension CaptureService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            Logger.shared.log("Photo capture error: \(error)", level: .error)
            return
        }
        
        guard let data = photo.fileDataRepresentation(),
              let image = NSImage(data: data) else {
            Logger.shared.log("Failed to create image from photo data", level: .error)
            return
        }
        
        Task {
            await self.processSnapshot(image)
        }
    }
}

extension CaptureService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        Logger.shared.log("Video recording STARTED at: \(fileURL.path)", level: .info)
    }
    
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Logger.shared.log("🎥 fileOutput delegate called - Recording FINISHED at: \(outputFileURL.path)", level: .info)
        Logger.shared.log("📁 File URL scheme: \(outputFileURL.scheme ?? "none")", level: .debug)
        Logger.shared.log("📁 File URL absolute: \(outputFileURL.absoluteString)", level: .debug)
        
        sessionQueue.async { [weak self] in
            self?.isRecording = false
            
            if let error = error {
                Logger.shared.log("❌ Video recording error: \(error.localizedDescription)", level: .error)
                
                // Check for specific error codes
                let nsError = error as NSError
                Logger.shared.log("Error domain: \(nsError.domain), code: \(nsError.code)", level: .error)
                
                self?.videoCompletionHandler?(nil)
            } else {
                Logger.shared.log("✅ Video recording completed successfully", level: .info)
                Logger.shared.log("📁 Video saved to: \(outputFileURL.path)", level: .info)
                
                // Verify file exists and get its size
                if FileManager.default.fileExists(atPath: outputFileURL.path) {
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: outputFileURL.path),
                       let fileSize = attributes[.size] as? Int64 {
                        let sizeMB = Double(fileSize) / (1024 * 1024)
                        Logger.shared.log("📊 Video file verified, size: \(String(format: "%.2f", sizeMB)) MB", level: .info)
                    }
                    
                    // Pass the URL directly to the handler
                    Logger.shared.log("🚀 Calling video completion handler with URL: \(outputFileURL.path)", level: .info)
                    self?.videoCompletionHandler?(outputFileURL)
                } else {
                    Logger.shared.log("❌ Video file not found after recording at: \(outputFileURL.path)", level: .error)
                    
                    // Check temp directory
                    let tempDir = FileManager.default.temporaryDirectory
                    Logger.shared.log("📁 Checking temp directory: \(tempDir.path)", level: .debug)
                    if let files = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
                        Logger.shared.log("📁 Files in temp after recording:", level: .debug)
                        for file in files.prefix(10) {
                            Logger.shared.log("  - \(file.lastPathComponent)", level: .debug)
                        }
                    }
                    
                    self?.videoCompletionHandler?(nil)
                }
            }
            
            self?.videoCompletionHandler = nil
            // Don't stop the capture session immediately - it might be needed for future captures
            Logger.shared.log("Video recording delegate processing completed", level: .debug)
        }
    }
}