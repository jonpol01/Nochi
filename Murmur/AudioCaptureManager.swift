import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

final class AudioCaptureManager: NSObject, @unchecked Sendable {
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onError: ((Error) -> Void)?

    private var stream: SCStream?
    private let audioQueue = DispatchQueue(label: "com.murmur.audio", qos: .userInitiated)
    private var bufferCount = 0
    private static var cachedContent: SCShareableContent?

    func startCapture() async throws {
        let content: SCShareableContent
        if let cached = Self.cachedContent {
            content = cached
        } else {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            Self.cachedContent = content
        }
        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplay
        }
        NSLog("[AudioCapture] Found display: %dx%d", display.width, display.height)

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.channelCount = 1
        config.sampleRate = 48000
        // Minimize video capture since we only need audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        // Must also add screen output or ScreenCaptureKit errors on every video frame
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: audioQueue)
        NSLog("[AudioCapture] Starting capture...")
        try await stream.startCapture()
        self.stream = stream
        NSLog("[AudioCapture] Capture started successfully")
    }

    func stopCapture() {
        guard let stream else { return }
        Task {
            try? await stream.stopCapture()
        }
        self.stream = nil
        bufferCount = 0
        NSLog("[AudioCapture] Capture stopped")
    }

    static func requestPermission() async -> Bool {
        if cachedContent != nil { return true }
        do {
            cachedContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return true
        } catch {
            return false
        }
    }

    private func sampleBufferToPCMBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = sampleBuffer.formatDescription,
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        var asbd = asbdPtr.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            if bufferCount == 0 { NSLog("[AudioCapture] Failed to create AVAudioFormat") }
            return nil
        }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return nil }

        if bufferCount == 0 {
            NSLog("[AudioCapture] Audio format: sr=%.0f ch=%d interleaved=%d bitsPerChannel=%d",
                  format.sampleRate, format.channelCount, format.isInterleaved ? 1 : 0,
                  asbd.mBitsPerChannel)
        }

        // Get raw audio data pointer directly from the CMSampleBuffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }

        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<CChar>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let dataPointer else { return nil }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            if bufferCount == 0 { NSLog("[AudioCapture] Failed to create AVAudioPCMBuffer") }
            return nil
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        // Copy audio data into the PCM buffer
        if format.isInterleaved {
            // Interleaved: single buffer with all channels mixed
            if let dest = pcmBuffer.audioBufferList.pointee.mBuffers.mData {
                let bytesToCopy = min(totalLength, Int(pcmBuffer.audioBufferList.pointee.mBuffers.mDataByteSize))
                memcpy(dest, dataPointer, bytesToCopy)
            }
        } else {
            // Non-interleaved: separate buffer per channel
            let channelCount = Int(format.channelCount)
            let bytesPerFrame = Int(asbd.mBytesPerFrame)
            let bytesPerChannel = frameCount * bytesPerFrame
            let ablPointer = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
            for ch in 0..<min(channelCount, ablPointer.count) {
                if let dest = ablPointer[ch].mData {
                    let srcOffset = ch * bytesPerChannel
                    let bytesToCopy = min(bytesPerChannel, Int(ablPointer[ch].mDataByteSize))
                    if srcOffset + bytesToCopy <= totalLength {
                        memcpy(dest, dataPointer.advanced(by: srcOffset), bytesToCopy)
                    }
                }
            }
        }

        bufferCount += 1
        if bufferCount == 1 || bufferCount % 500 == 0 {
            NSLog("[AudioCapture] Buffer #%d: frames=%d totalBytes=%d", bufferCount, frameCount, totalLength)
        }

        return pcmBuffer
    }
}

extension AudioCaptureManager: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("[AudioCapture] Stream stopped with error: %@", error.localizedDescription)
        onError?(error)
    }
}

extension AudioCaptureManager: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let pcmBuffer = sampleBufferToPCMBuffer(sampleBuffer) else { return }
        guard pcmBuffer.frameLength > 0 else { return }
        onAudioBuffer?(pcmBuffer)
    }
}

enum AudioCaptureError: LocalizedError {
    case noDisplay
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display found for audio capture."
        case .permissionDenied: return "Screen Recording permission is required. Please enable it in System Settings > Privacy & Security."
        }
    }
}
