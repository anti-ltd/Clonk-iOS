import SwiftUI
import UIKit

/// Stores a short FIFO history of copied strings and persists it across sessions
/// via the App Group container — the same store the keyboard extension reads for
/// settings. Reading the pasteboard requires Full Access; the caller is responsible
/// for gating on `hasFullAccess` before calling `captureFromPasteboard()`.
@MainActor
@Observable
public final class ClipboardManager {
    public private(set) var history: [String] = []

    private let maxItems = 20

    public init() { load() }

    /// Add `string` to the front of the history. Deduplicates (existing entry
    /// moves to front) and trims to `maxItems`. Persists immediately.
    public func capture(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        history.removeAll { $0 == trimmed }
        history.insert(trimmed, at: 0)
        if history.count > maxItems { history = Array(history.prefix(maxItems)) }
        save()
    }

    /// Read `UIPasteboard.general.string` and capture it. Only call this when
    /// Full Access is confirmed — without it the pasteboard returns nil.
    public func captureFromPasteboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        capture(string: text)
    }

    /// Wipe the full history and persist.
    public func clear() {
        history = []
        save()
    }

    // MARK: - Persistence (App Group file, same pattern as SharedStore)

    private var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID)?
            .appendingPathComponent("clink-clipboard.v1.json")
    }

    private func load() {
        if let url = fileURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            history = decoded
            return
        }
        if let data = UserDefaults.standard.data(forKey: "clink-clipboard-v1"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            history = decoded
        }
    }

    private func save() {
        if let url = fileURL,
           let data = try? JSONEncoder().encode(history) {
            try? data.write(to: url, options: .atomic)
            return
        }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "clink-clipboard-v1")
        }
    }
}
