import AVFoundation
import Foundation
import Speech

// MARK: - Protocol

protocol SpeechRecognizerProtocol: AnyObject {
    var onTranscript: ((String, Bool) -> Void)? { get set }
    func feedAudio(_ buffer: AVAudioPCMBuffer)
    func start() throws
    func stop()
}

// MARK: - Apple Speech

final class AppleSpeechRecognizer: SpeechRecognizerProtocol, @unchecked Sendable {
    var onTranscript: ((String, Bool) -> Void)?

    private let recognizer: SFSpeechRecognizer
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isRunning = false
    private let lock = NSLock()
    private var feedCount = 0
    private var restartCount = 0
    private var lastResultTime = Date()
    private var watchdogTask: Task<Void, Never>?

    init(locale: Locale) {
        NSLog("[SpeechRecognizer] Initializing with locale: %@", locale.identifier)
        if let r = SFSpeechRecognizer(locale: locale) {
            self.recognizer = r
            NSLog("[SpeechRecognizer] Created recognizer, available=%d onDevice=%d",
                  r.isAvailable ? 1 : 0, r.supportsOnDeviceRecognition ? 1 : 0)
        } else {
            NSLog("[SpeechRecognizer] Failed for %@, falling back to en-US", locale.identifier)
            self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
        }
    }

    func start() throws {
        guard recognizer.isAvailable else {
            throw SpeechRecognizerError.unavailable
        }

        let authStatus = SFSpeechRecognizer.authorizationStatus()
        DebugLog.log("Speech", "Starting, locale=\(recognizer.locale.identifier) auth=\(authStatus.rawValue)")

        // Request authorization if not yet determined
        if authStatus == .notDetermined {
            DebugLog.log("Speech", "Requesting authorization...")
            SFSpeechRecognizer.requestAuthorization { status in
                DebugLog.log("Speech", "Authorization result: \(status.rawValue)")
            }
        } else if authStatus != .authorized {
            DebugLog.log("Speech", "NOT AUTHORIZED (status=\(authStatus.rawValue))")
            throw SpeechRecognizerError.notAuthorized
        }

        isRunning = true
        feedCount = 0
        restartCount = 0
        startRecognitionTask()
        startWatchdog()
    }

    func stop() {
        NSLog("[SpeechRecognizer] Stopping, fed %d buffers, %d restarts", feedCount, restartCount)
        isRunning = false
        watchdogTask?.cancel()
        watchdogTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }

    func feedAudio(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = recognitionRequest
        lock.unlock()

        guard let request else {
            if feedCount % 100 == 0 {
                DebugLog.log("Speech", "feedAudio: NO request available! feedCount=\(feedCount)")
            }
            feedCount += 1
            return
        }
        request.append(buffer)
        feedCount += 1
        if feedCount == 1 {
            DebugLog.log("Speech", "First buffer: sr=\(buffer.format.sampleRate) ch=\(buffer.format.channelCount) frames=\(buffer.frameLength)")
        }
        if feedCount % 500 == 0 {
            DebugLog.log("Speech", "Fed \(feedCount) buffers, task state=\(recognitionTask?.state.rawValue ?? -1)")
        }
    }

    private func startRecognitionTask() {
        lock.lock()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.recognitionRequest = request
        lock.unlock()

        lastResultTime = Date()

        DebugLog.log("Speech", "Creating recognition task...")
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else {
                DebugLog.log("Speech", "Callback: self is nil!")
                return
            }
            guard self.isRunning else {
                DebugLog.log("Speech", "Callback: not running, ignoring")
                return
            }

            if let result {
                self.lastResultTime = Date()
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                DebugLog.log("Speech", "Result(\(isFinal ? "FINAL" : "partial")): \(text.prefix(60))")

                self.onTranscript?(text, isFinal)

                if isFinal {
                    self.restart()
                }
            }
            if let error {
                DebugLog.log("Speech", "Error: \(error.localizedDescription) (code=\((error as NSError).code))")
                if result == nil {
                    self.restart()
                }
            }
        }
        DebugLog.log("Speech", "Task created, state=\(recognitionTask?.state.rawValue ?? -1)")
    }

    private func restart() {
        guard isRunning else { return }
        restartCount += 1
        DebugLog.log("Speech", "Restarting (#\(restartCount))...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isRunning else { return }
            self.startRecognitionTask()
        }
    }

    /// Watchdog: if no results for 10s, force-restart.
    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, self.isRunning, !Task.isCancelled else { break }
                let elapsed = Date().timeIntervalSince(self.lastResultTime)
                if elapsed > 10 {
                    DebugLog.log("Speech", "Watchdog: no results for \(Int(elapsed))s, restarting")
                    self.restart()
                }
            }
        }
    }

    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

// MARK: - Whisper (Stub)

final class WhisperRecognizer: SpeechRecognizerProtocol, @unchecked Sendable {
    var onTranscript: ((String, Bool) -> Void)?

    private var audioBuffer: [Float] = []
    private let maxBufferSamples = 480_000
    private var transcriptionTask: Task<Void, Never>?
    private var isRunning = false
    private let lock = NSLock()
    private var lastTranscription = ""

    func start() throws {
        isRunning = true
        audioBuffer.removeAll()
        lastTranscription = ""
        startTranscriptionLoop()
    }

    func stop() {
        isRunning = false
        transcriptionTask?.cancel()
        transcriptionTask = nil
    }

    func feedAudio(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

        lock.lock()
        audioBuffer.append(contentsOf: samples)
        if audioBuffer.count > maxBufferSamples {
            audioBuffer.removeFirst(audioBuffer.count - maxBufferSamples)
        }
        lock.unlock()
    }

    private func startTranscriptionLoop() {
        transcriptionTask = Task.detached { [weak self] in
            while let self, self.isRunning, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                await self.transcribeCurrentBuffer()
            }
        }
    }

    private func transcribeCurrentBuffer() async {
        let samples: [Float] = {
            lock.lock()
            defer { lock.unlock() }
            return audioBuffer
        }()
        guard !samples.isEmpty else { return }

        let durationSeconds = Double(samples.count) / 16000.0
        let text = "[WhisperKit: \(String(format: "%.1f", durationSeconds))s buffered - add WhisperKit SPM to enable]"
        if text != lastTranscription {
            lastTranscription = text
            onTranscript?(text, false)
        }
    }
}

// MARK: - Errors

enum SpeechRecognizerError: LocalizedError {
    case unavailable
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Speech recognition is not available for the selected language."
        case .notAuthorized: return "Speech recognition permission is required."
        }
    }
}
