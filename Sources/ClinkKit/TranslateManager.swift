/**
 `TranslateManager`: observable backing store for the Translate panel. Holds the
 compose buffer (what the keys type into / clipboard pastes into) and the chosen
 target language, persisted to the App Group container — the same pattern as
 `NotepadManager` / `ClipboardManager`.


 Module: panels · Target: ClinkKit
 Learn: docs/13-extending-panels.md
 */
import SwiftUI

/// One translatable language: a BCP-47 id (e.g. "es", "zh-Hans") and a display
/// name. The name is also what the AI backend is asked to translate *into*.
public struct TranslateLanguage: Identifiable, Hashable, Sendable {
    public let id: String       // BCP-47, e.g. "es"
    public let name: String     // English display name, e.g. "Spanish"
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public extension TranslateLanguage {
    /// A curated set of common languages. Covers the offline `Translation`
    /// framework's supported set and reads well in the picker; not exhaustive.
    static let common: [TranslateLanguage] = [
        .init(id: "ar",      name: "Arabic"),
        .init(id: "zh-Hans", name: "Chinese"),
        .init(id: "nl",      name: "Dutch"),
        .init(id: "en",      name: "English"),
        .init(id: "fr",      name: "French"),
        .init(id: "de",      name: "German"),
        .init(id: "hi",      name: "Hindi"),
        .init(id: "it",      name: "Italian"),
        .init(id: "ja",      name: "Japanese"),
        .init(id: "ko",      name: "Korean"),
        .init(id: "pl",      name: "Polish"),
        .init(id: "pt",      name: "Portuguese"),
        .init(id: "ru",      name: "Russian"),
        .init(id: "es",      name: "Spanish"),
        .init(id: "sv",      name: "Swedish"),
        .init(id: "tr",      name: "Turkish"),
        .init(id: "uk",      name: "Ukrainian"),
    ]

    /// Look up a language by id, falling back to Spanish (the default target).
    static func resolve(_ id: String) -> TranslateLanguage {
        common.first { $0.id == id } ?? common.first { $0.id == "es" }!
    }
}

/// Outcome of one translation request, shared between the panel and its backend
/// runners. Top-level (not nested) so the offline runner can report it back.
public enum TranslatePhase: Equatable, Sendable {
    case translating
    case done(String)
    case failed(String)
}

/// Backing store for the Translate panel: the live compose buffer (the keys type
/// into it while the panel is open) and the persisted target language. Persists
/// to the App Group container so the app and keyboard extension agree, falling
/// back to `UserDefaults.standard` when the group is unavailable.
@MainActor
@Observable
public final class TranslateManager {
    /// The text to translate — typed via the keys or pasted from the clipboard
    /// while the Translate panel is open. Persisted so an in-progress entry
    /// survives the keyboard being torn down between host apps.
    public var compose: String = "" {
        didSet {
            guard !loading, compose != oldValue else { return }
            save()
        }
    }

    /// BCP-47 id of the target language. Persisted so the user's choice sticks.
    public var targetLanguageID: String = "es" {
        didSet {
            guard !loading, targetLanguageID != oldValue else { return }
            save()
        }
    }

    /// Convenience: the resolved target language.
    public var targetLanguage: TranslateLanguage { .resolve(targetLanguageID) }

    /// Suppresses the `didSet` saves while hydrating from disk.
    private var loading = false

    public init() { load() }

    // MARK: - Persistence (App Group file, mirrors NotepadManager)

    private struct Payload: Codable {
        var compose: String
        var targetLanguageID: String
    }

    private var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID)?
            .appendingPathComponent("clink-translate.v1.json")
    }

    private func load() {
        loading = true
        defer { loading = false }
        if let url = fileURL,
           let data = try? Data(contentsOf: url),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            compose = payload.compose
            targetLanguageID = payload.targetLanguageID
            return
        }
        if let data = UserDefaults.standard.data(forKey: "clink-translate-v1"),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            compose = payload.compose
            targetLanguageID = payload.targetLanguageID
        }
    }

    private func save() {
        let payload = Payload(compose: compose, targetLanguageID: targetLanguageID)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        if let url = fileURL {
            try? data.write(to: url, options: .atomic)
            return
        }
        UserDefaults.standard.set(data, forKey: "clink-translate-v1")
    }
}
