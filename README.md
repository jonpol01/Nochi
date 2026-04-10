<div align="center">

# Murmur

### Real-time live translation of system audio displayed as subtitles in the macOS notch area.

<br>

[![Swift](https://img.shields.io/badge/Swift-5.0-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-15.0+-000000?style=for-the-badge&logo=apple&logoColor=white)](https://developer.apple.com/macos/)
[![ScreenCaptureKit](https://img.shields.io/badge/ScreenCaptureKit-System_Audio-333333?style=for-the-badge&logo=apple&logoColor=white)](https://developer.apple.com/documentation/screencapturekit)
[![Translation](https://img.shields.io/badge/Apple_Translation-On--Device-7C3AED?style=for-the-badge&logo=apple&logoColor=white)](https://developer.apple.com/documentation/translation)

[![Speech](https://img.shields.io/badge/Speech_Framework-Real--Time-4285F4?style=for-the-badge&logo=apple&logoColor=white)](https://developer.apple.com/documentation/speech)
[![WhisperKit](https://img.shields.io/badge/WhisperKit-CoreML-22c55e?style=for-the-badge&logo=huggingface&logoColor=white)](https://github.com/argmaxinc/WhisperKit)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)](LICENSE)

<br>

</div>

---

## What It Does

A macOS menu bar app that captures **system audio** (not the microphone) via ScreenCaptureKit, performs **real-time speech recognition**, translates to a target language using **Apple's on-device Translation framework**, and displays live subtitles in a **notch-shaped overlay** pinned to the top of the screen.

Watch a YouTube video in Japanese, join a meeting in Spanish, or listen to a podcast in Korean — Murmur shows you live translated subtitles without touching your mic or sending anything to the cloud.

---

## Pipeline

<div align="center">
<img src="assets/pipeline.svg" width="100%" alt="Murmur Translation Pipeline" />
</div>

---

## Features

### Audio Capture
- **System audio only** — captures all sound output via ScreenCaptureKit, no microphone needed
- **Excludes own audio** — `excludesCurrentProcessAudio` prevents feedback loops
- **Zero-config** — taps the default display audio, works with any app

### Speech Recognition
- **Apple Speech** — `SFSpeechRecognizer` with real-time partial results, on-device when available
- **WhisperKit** (pluggable) — CoreML-accelerated Whisper for higher accuracy, 3-second chunked transcription
- **Auto-restart** — seamlessly restarts on Apple Speech's ~60s timeout
- **Watchdog** — detects silent failures and force-restarts recognition

### Translation
- **Apple Translation** — fully on-device, private, no API keys
- **20+ language pairs** — Japanese, Korean, Chinese, Spanish, French, German, and more
- **Real-time** — translates partial results as speech is recognized, not just final sentences
- **Smart debounce** — translates immediately on 3+ new characters, throttles small changes

### Notch Overlay
- **Notch-shaped UI** — custom `AppleNotchShape` with rounded lower corners, blends with the hardware notch
- **Two display modes** — "Translation Only" (clean subtitles) or "Original + Translation" (language learning)
- **In-overlay language picker** — switch source/target language without opening settings
- **Control buttons** — start/stop, display mode toggle, font size, quit
- **Always on top** — `NSPanel` at `.screenSaver` level, joins all Spaces, non-activating

### Global Hotkeys
- **Carbon Events API** — system-wide shortcuts that work even when the app is in the background

| Shortcut | Action |
|----------|--------|
| `Opt+Cmd+L` | Start / Stop listening |
| `Opt+Cmd+O` | Toggle overlay visibility |
| `Opt+Cmd+D` | Toggle display mode |
| `Opt+Cmd+=` | Increase font size |
| `Opt+Cmd+-` | Decrease font size |

---

## Architecture

<div align="center">
<img src="assets/architecture.svg" width="100%" alt="Murmur System Architecture" />
</div>

---

## Key Files

| File | Purpose |
|------|---------|
| `MurmurApp.swift` | `@main` entry point with `@NSApplicationDelegateAdaptor` |
| `AppDelegate.swift` | Menu bar, overlay controller, hotkey manager, Combine wiring |
| `TranslatorModel.swift` | Central `@MainActor ObservableObject` — pipeline state, settings, UserDefaults |
| `AudioCaptureManager.swift` | ScreenCaptureKit `SCStream` — system audio capture, `CMSampleBuffer` to `AVAudioPCMBuffer` |
| `SpeechRecognizer.swift` | `SpeechRecognizerProtocol` + Apple Speech (with auto-restart) + WhisperKit stub |
| `TranslationService.swift` | Apple `TranslationSession` wrapper for on-device translation |
| `OverlayWindowController.swift` | `NSPanel` at `.screenSaver` level — notch overlay positioning and visibility |
| `OverlayView.swift` | `AppleNotchShape` + subtitle text + language picker + control buttons |
| `ContentView.swift` | Settings UI — languages, engine, display mode, appearance, permissions |
| `GlobalHotkeyManager.swift` | Carbon Events hotkey registration and dispatch |
| `ScreenSelection.swift` | Multi-monitor display selection (prefers built-in with notch) |

---

## Speech Engines

| Engine | How It Works | Latency | Best For |
|--------|-------------|---------|----------|
| **Apple Speech** (default) | `SFSpeechRecognizer` streams partial + final results | Real-time | Casual video, meetings, podcasts |
| **WhisperKit** | CoreML Whisper model, 3-second chunked transcription | ~3s | Higher accuracy, noisy audio |

Switch engines in Settings. WhisperKit requires adding the [WhisperKit SPM package](https://github.com/argmaxinc/WhisperKit).

---

## Supported Languages

Source and target languages can be mixed freely. Common pairs:

| Source | Target | Use Case |
|--------|--------|----------|
| Japanese | English | Anime, YouTube, meetings |
| Korean | English | K-drama, livestreams |
| Spanish | English | Calls, podcasts |
| English | Japanese | Language learning |
| Chinese | English | Video, conferences |
| French | English | Film, meetings |

> Any pair supported by Apple Translation works. Language packs download on first use via System Settings.

---

## Requirements

- **macOS 15.0+** (Sequoia — required for Apple Translation framework)
- **MacBook with notch** (works without notch too, overlay pins to top of screen)
- **Xcode 16+**
- **Screen Recording** permission (for ScreenCaptureKit system audio capture)
- **Speech Recognition** permission (for `SFSpeechRecognizer`)
- Translation language packs (downloaded via System Settings > General > Language & Region > Translation Languages)

---

## Setup

### 1. Clone

```bash
git clone https://github.com/jonpol01/Murmur.git
cd Murmur
```

### 2. Build and run

```bash
open Murmur.xcodeproj
# Product -> Run (or Cmd+R)
```

No CocoaPods, no SPM dependencies for the base build. Pure Apple frameworks.

### 3. Grant permissions

On first launch:
1. **Screen Recording** — macOS will prompt, or go to System Settings > Privacy & Security > Screen Recording
2. **Speech Recognition** — grant when prompted, or via System Settings > Privacy & Security > Speech Recognition

### 4. Download translation languages

Go to **System Settings > General > Language & Region > Translation Languages** and download the language pair you need (e.g., Japanese + English).

### 5. Start translating

Press **Opt+Cmd+L** or click the waveform icon in the menu bar > "Start Listening". Play any audio and watch subtitles appear in the notch.

---

## Adding WhisperKit (optional)

For higher accuracy speech recognition via local Whisper models:

1. In Xcode, go to **File > Add Package Dependencies**
2. Enter: `https://github.com/argmaxinc/WhisperKit`
3. Replace the stub in `SpeechRecognizer.swift` with actual WhisperKit calls
4. The model (~150 MB) downloads on first use

---

## Related Repositories

| Repo | Description |
|------|-------------|
| [notchprompt](https://github.com/jonpol01/notchprompt) | Teleprompter in the notch — the UI architecture Murmur is built on |

---

## License

MIT

---

<div align="center">

**Built with Swift, ScreenCaptureKit, Apple Speech, and Apple Translation**

</div>
