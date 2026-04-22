import AppKit
import Foundation
import Speech
#if canImport(Translation)
import Translation
#endif

/// Checks whether on-device speech recognition and translation
/// models are installed for the user's selected language pair.
@MainActor
enum ModelAvailability {
    enum SpeechStatus {
        case available          // on-device model ready
        case serverOnly         // works but needs network
        case unsupported        // locale not supported at all
    }

    enum TranslationStatus {
        case installed
        case supported          // can be downloaded
        case unsupported
        case unknown            // macOS < 26
    }

    /// Check speech recognition model status for a BCP-47 locale.
    static func speechStatus(for localeID: String) -> SpeechStatus {
        let locale: Locale
        if localeID == "auto" {
            locale = Locale.current
        } else {
            locale = Locale(identifier: localeID)
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            return .unsupported
        }
        if recognizer.supportsOnDeviceRecognition {
            return .available
        }
        return .serverOnly
    }

    /// Check if translation is installed between two BCP-47 codes.
    static func translationStatus(from source: String, to target: String) async -> TranslationStatus {
        guard source != target else { return .installed }

        #if canImport(Translation)
        guard #available(macOS 26.0, *) else { return .unknown }

        let sourceLang = Locale.Language(identifier: source == "auto" ? "en" : source)
        let targetLang = Locale.Language(identifier: target)

        let availability = LanguageAvailability()
        let status = await availability.status(from: sourceLang, to: targetLang)
        switch status {
        case .installed: return .installed
        case .supported: return .supported
        case .unsupported: return .unsupported
        @unknown default: return .unknown
        }
        #else
        return .unknown
        #endif
    }
}

/// Deep links to the right System Settings panels.
enum SettingsDeepLink {
    /// Opens Language & Region → Translation Languages area.
    static func openLanguageRegion() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens Keyboard → Dictation (for speech recognition language downloads).
    static func openDictation() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens Privacy → Speech Recognition.
    static func openSpeechPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
            NSWorkspace.shared.open(url)
        }
    }
}
