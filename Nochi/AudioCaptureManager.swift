import AVFoundation
import CoreAudio
import Foundation

final class AudioCaptureManager: @unchecked Sendable {
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onError: ((Error) -> Void)?

    private var tapDescription: CATapDescription?
    private var tapObjectID: AudioObjectID = .init(kAudioObjectUnknown)
    private var aggregateDeviceID: AudioObjectID = .init(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var tapFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var bufferCount = 0

    func startCapture() async throws {
        // 1. Create tap — capture all system audio as stereo, unmuted
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.name = "NochiSystemTap"
        desc.muteBehavior = .unmuted
        desc.isPrivate = true
        tapDescription = desc

        // 2. Create the process tap
        var status = AudioHardwareCreateProcessTap(desc, &tapObjectID)
        guard status == noErr else {
            throw AudioCaptureError.tapCreationFailed(status)
        }
        NSLog("[AudioCapture] Process tap created (id=%d)", tapObjectID)

        // 3. Read the tap's native audio format
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        status = AudioObjectGetPropertyData(tapObjectID, &addr, 0, nil, &size, &asbd)
        guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
            throw AudioCaptureError.formatUnavailable
        }
        tapFormat = format
        NSLog("[AudioCapture] Tap format: sr=%.0f ch=%d interleaved=%d",
              format.sampleRate, format.channelCount, format.isInterleaved ? 1 : 0)

        // 4. Build aggregate device containing the tap
        let tapUID = desc.uuid.uuidString
        let aggDesc: NSDictionary = [
            kAudioAggregateDeviceUIDKey: "com.nochi.systemtap-\(UUID().uuidString)",
            kAudioAggregateDeviceNameKey: "Nochi System Tap",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
            kAudioAggregateDeviceTapAutoStartKey: false,
        ]
        status = AudioHardwareCreateAggregateDevice(aggDesc, &aggregateDeviceID)
        guard status == noErr else {
            throw AudioCaptureError.aggregateDeviceFailed(status)
        }
        NSLog("[AudioCapture] Aggregate device created (id=%d)", aggregateDeviceID)

        // 5. Convert to mono for speech recognition
        let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate, channels: 1, interleaved: false)!
        guard let conv = AVAudioConverter(from: format, to: monoFormat) else {
            throw AudioCaptureError.formatUnavailable
        }
        self.converter = conv
        NSLog("[AudioCapture] Converter: %dch -> 1ch mono", format.channelCount)

        // 6. Register IO proc to receive audio buffers
        let capturedFormat = format
        let handler = onAudioBuffer
        let audioConverter = conv
        let outputFormat = monoFormat
        var logCount = 0
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDeviceID, nil) {
            _, inInputData, _, _, _ in
            var abl = inInputData.pointee
            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: capturedFormat,
                bufferListNoCopy: &abl,
                deallocator: nil
            ) else { return }
            guard inputBuffer.frameLength > 0 else { return }

            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: inputBuffer.frameLength) else { return }
            var error: NSError?
            audioConverter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return inputBuffer
            }
            guard error == nil, outputBuffer.frameLength > 0 else { return }

            logCount += 1
            if logCount == 1 || logCount % 500 == 0 {
                NSLog("[AudioCapture] Buffer #%d: frames=%d mono", logCount, outputBuffer.frameLength)
            }
            handler?(outputBuffer)
        }
        guard status == noErr else {
            throw AudioCaptureError.ioProcFailed(status)
        }

        // 7. Start — triggers TCC prompt on first run
        status = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard status == noErr else {
            throw AudioCaptureError.startFailed(status)
        }
        NSLog("[AudioCapture] Capture started (Process Tap)")
    }

    func stopCapture() {
        if let procID = ioProcID {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            ioProcID = nil
        }
        if aggregateDeviceID != .init(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = .init(kAudioObjectUnknown)
        }
        if tapObjectID != .init(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapObjectID)
            tapObjectID = .init(kAudioObjectUnknown)
        }
        tapDescription = nil
        tapFormat = nil
        converter = nil
        bufferCount = 0
        NSLog("[AudioCapture] Capture stopped")
    }
}

enum AudioCaptureError: LocalizedError {
    case tapCreationFailed(OSStatus)
    case formatUnavailable
    case aggregateDeviceFailed(OSStatus)
    case ioProcFailed(OSStatus)
    case startFailed(OSStatus)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .tapCreationFailed(let s):
            return "Failed to create audio tap (OSStatus \(s)). Grant Audio Recording permission in System Settings > Privacy & Security."
        case .formatUnavailable:
            return "Could not read audio format from the tap."
        case .aggregateDeviceFailed(let s):
            return "Failed to create aggregate audio device (OSStatus \(s))."
        case .ioProcFailed(let s):
            return "Failed to register audio IO proc (OSStatus \(s))."
        case .startFailed(let s):
            return "Failed to start audio capture (OSStatus \(s))."
        case .permissionDenied:
            return "Audio Recording permission is required. Please enable it in System Settings > Privacy & Security."
        }
    }
}
