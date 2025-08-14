import Foundation
import Vision
import AppKit
import CoreImage

actor VisionService {
    static let shared = VisionService()
    
    private var lastFramePixels: [UInt8]?
    private var lastDetectionTime: Date?
    private let detectionThrottle: TimeInterval = 60
    
    private init() {}
    
    nonisolated func detectHuman(in image: NSImage) async -> Bool {
        // Convert NSImage to CGImage first to avoid passing NSImage across boundaries
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            Task {
                await performHumanDetection(on: cgImage, continuation: continuation)
            }
        }
    }
    
    private func performHumanDetection(on cgImage: CGImage, continuation: CheckedContinuation<Bool, Never>) async {
        let threshold = await MainActor.run { AppSettings.shared.humanDetectionThreshold }
        
        let humanRequest = VNDetectHumanRectanglesRequest { request, error in
            if let error = error {
                Logger.shared.log("Human detection error: \(error)", level: .error)
                continuation.resume(returning: false)
                return
            }
            
            guard let observations = request.results as? [VNHumanObservation] else {
                continuation.resume(returning: false)
                return
            }
            
            let hasHuman = observations.contains { $0.confidence >= Float(threshold) }
            
            if hasHuman {
                Logger.shared.log("Human detected with confidence: \(observations.first?.confidence ?? 0)", level: .info)
            }
            
            continuation.resume(returning: hasHuman)
        }
        
        humanRequest.revision = VNDetectHumanRectanglesRequestRevision2
        
        let faceRequest = VNDetectFaceRectanglesRequest { request, error in
            if error != nil {
                return
            }
            
            if let observations = request.results as? [VNFaceObservation],
               !observations.isEmpty {
                Logger.shared.log("Face detected with confidence: \(observations.first?.confidence ?? 0)", level: .info)
            }
        }
        
        faceRequest.revision = VNDetectFaceRectanglesRequestRevision3
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([humanRequest, faceRequest])
        } catch {
            Logger.shared.log("Vision request failed: \(error)", level: .error)
            continuation.resume(returning: false)
        }
    }
    
    nonisolated func detectMotion(current: NSImage, previous: NSImage?) async -> Bool {
        guard let previous = previous else { return false }
        
        let motionDetectionEnabled = await MainActor.run { AppSettings.shared.motionDetectionEnabled }
        guard motionDetectionEnabled else { return false }
        
        // Convert images to CGImage first
        guard let currentCG = current.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let previousCG = previous.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        
        return await detectMotionInCGImages(current: currentCG, previous: previousCG)
    }
    
    nonisolated private func detectMotionInCGImages(current: CGImage, previous: CGImage) async -> Bool {
        let changeRate = calculateFrameDifference(current: current, previous: previous)
        let sensitivity = await MainActor.run { AppSettings.shared.motionDetectionSensitivity }
        let threshold = Float(sensitivity)
        
        if changeRate > threshold {
            Logger.shared.log("Motion detected with change rate: \(changeRate)", level: .info)
            Task {
                await updateLastDetectionTime()
            }
            return true
        }
        
        return false
    }
    
    private func updateLastDetectionTime() {
        lastDetectionTime = Date()
    }
    
    nonisolated private func calculateFrameDifference(current: CGImage, previous: CGImage) -> Float {
        let width = 320
        let height = 240
        
        guard let currentResized = resizeImage(current, to: CGSize(width: width, height: height)),
              let previousResized = resizeImage(previous, to: CGSize(width: width, height: height)) else {
            return 0
        }
        
        guard let currentPixels = getPixelData(from: currentResized),
              let previousPixels = getPixelData(from: previousResized) else {
            return 0
        }
        
        var changedPixels = 0
        let totalPixels = width * height
        let threshold: UInt8 = 30
        
        for i in 0..<totalPixels {
            let idx = i * 4
            
            let rDiff = abs(Int(currentPixels[idx]) - Int(previousPixels[idx]))
            let gDiff = abs(Int(currentPixels[idx + 1]) - Int(previousPixels[idx + 1]))
            let bDiff = abs(Int(currentPixels[idx + 2]) - Int(previousPixels[idx + 2]))
            
            if rDiff > threshold || gDiff > threshold || bDiff > threshold {
                changedPixels += 1
            }
        }
        
        return Float(changedPixels) / Float(totalPixels)
    }
    
    nonisolated private func resizeImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let context = CIContext()
        let ciImage = CIImage(cgImage: image)
        
        let scaleX = size.width / CGFloat(image.width)
        let scaleY = size.height / CGFloat(image.height)
        
        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
        let scaled = ciImage.transformed(by: transform)
        
        return context.createCGImage(scaled, from: CGRect(origin: .zero, size: size))
    }
    
    nonisolated private func getPixelData(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return pixelData
    }
    
    nonisolated func detectEnvironmentChange(current: NSImage) async -> Bool {
        let environmentChangeDetectionEnabled = await MainActor.run { AppSettings.shared.environmentChangeDetectionEnabled }
        guard environmentChangeDetectionEnabled else { return false }
        
        guard let currentCG = current.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        
        let _ = calculateHistogram(for: currentCG)
        
        return false
    }
    
    nonisolated private func calculateHistogram(for image: CGImage) -> [Float] {
        guard let pixelData = getPixelData(from: image) else {
            return []
        }
        
        var histogram = [Float](repeating: 0, count: 256)
        let pixelCount = image.width * image.height
        
        for i in stride(from: 0, to: pixelData.count, by: 4) {
            let r = pixelData[i]
            let g = pixelData[i + 1]
            let b = pixelData[i + 2]
            
            let gray = Int(0.299 * Float(r) + 0.587 * Float(g) + 0.114 * Float(b))
            histogram[min(gray, 255)] += 1
        }
        
        for i in 0..<256 {
            histogram[i] /= Float(pixelCount)
        }
        
        return histogram
    }
}