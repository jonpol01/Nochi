import Foundation
#if swift(>=6.2)
import Translation
#endif

@MainActor
final class TranslationService {
    private var session: Any?
    private var currentSourceLanguage: Locale.Language?
    private var currentTargetLanguage: Locale.Language?

    func translate(
        _ text: String,
        from source: Locale.Language?,
        to target: Locale.Language
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        #if swift(>=6.2)
        guard #available(macOS 26.0, *) else {
            return text
        }

        // Recreate session if language pair changed
        if session == nil ||
           currentSourceLanguage != source ||
           currentTargetLanguage != target {
            session = nil
            let sourceLanguage = source ?? Locale.Language(identifier: "en")
            NSLog("[Translation] Creating session: \(sourceLanguage) -> \(target)")
            session = TranslationSession(installedSource: sourceLanguage, target: target)
            currentSourceLanguage = source
            currentTargetLanguage = target
        }

        guard let session = session as? TranslationSession else {
            throw TranslationError.sessionNotAvailable
        }

        let response = try await session.translate(text)
        return response.targetText
        #else
        return text
        #endif
    }

    func teardown() {
        session = nil
        currentSourceLanguage = nil
        currentTargetLanguage = nil
    }
}

enum TranslationError: LocalizedError {
    case sessionNotAvailable
    case languageNotSupported

    var errorDescription: String? {
        switch self {
        case .sessionNotAvailable:
            return "Translation session could not be created. The language pair may not be available."
        case .languageNotSupported:
            return "The selected language pair is not supported. Please download the language pack in System Settings."
        }
    }
}
