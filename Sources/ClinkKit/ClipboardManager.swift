/**
 `ClipboardManager`: observable FIFO clipboard history, persisted to the App
 Group container so both the container app and keyboard extension see the same
 entries. Handles pin, delete, and clear operations.
 

 Module: settings · Target: ClinkKit
 Learn: docs/01-settings-and-storage.md
 */
import SwiftUI
import UIKit

/// Stores a short FIFO history of copied strings and persists it across sessions
/// via the App Group container — the same store the keyboard extension reads for
/// settings. Reading the pasteboard requires Full Access; the caller is responsible
/// for gating on `hasFullAccess` before calling `captureFromPasteboard()`.
@MainActor
@Observable
public final class ClipboardManager {
    public private(set) var history: [ClipboardEntry] = []

    private let maxItems = 20

    public init() { load() }

    /// Add `string` to the front of the history. Deduplicates (existing entry
    /// moves to front, keeping its pin state) and trims to `maxItems`. Pinned
    /// entries always sort first and are exempt from trimming. Persists immediately.
    public func capture(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let wasPinned = history.first { $0.text == trimmed }?.pinned ?? false
        history.removeAll { $0.text == trimmed }
        history.insert(ClipboardEntry(text: trimmed, pinned: wasPinned), at: 0)
        normalize()
        save()
    }

    /// Toggle the pinned state of the entry at `index`. Pinned entries float to
    /// the top and survive trimming and "clear".
    public func togglePin(at index: Int) {
        guard history.indices.contains(index) else { return }
        history[index].pinned.toggle()
        normalize()
        save()
    }

    /// Stable-partition pinned entries to the front (preserving recency within
    /// each group) and trim the unpinned tail to `maxItems`.
    private func normalize() {
        let pinned = history.filter { $0.pinned }
        var unpinned = history.filter { !$0.pinned }
        if unpinned.count > maxItems { unpinned = Array(unpinned.prefix(maxItems)) }
        history = pinned + unpinned
    }

    /// Read `UIPasteboard.general.string` and capture it. Only call this when
    /// Full Access is confirmed — without it the pasteboard returns nil.
    public func captureFromPasteboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        capture(string: text)
    }

    /// Remove a single entry by index.
    public func delete(at index: Int) {
        guard history.indices.contains(index) else { return }
        history.remove(at: index)
        save()
    }

    /// Remove the first unpinned entry matching `text`. Pinned entries are skipped.
    public func deleteUnpinned(text: String) {
        guard let index = history.firstIndex(where: { $0.text == text && !$0.pinned }) else { return }
        history.remove(at: index)
        save()
    }

    /// Wipe the history except pinned entries and persist.
    public func clear() {
        history = history.filter { $0.pinned }
        save()
    }

    /// Wipe the history, optionally including pinned entries.
    public func clearAll(ignoringPins: Bool) {
        history = ignoringPins ? [] : history.filter { $0.pinned }
        save()
    }

    // MARK: - Persistence (App Group file, same pattern as SharedStore)

    private var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID)?
            .appendingPathComponent("clink-clipboard.v2.json")
    }

    private var legacyFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID)?
            .appendingPathComponent("clink-clipboard.v1.json")
    }

    private func load() {
        // v2: [ClipboardEntry] with timestamps
        if let url = fileURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data) {
            history = decoded
            return
        }
        // v1 migration: plain [String] — convert to entries with .distantPast date
        if let url = legacyFileURL,
           let data = try? Data(contentsOf: url),
           let strings = try? JSONDecoder().decode([String].self, from: data) {
            history = strings.map { ClipboardEntry(text: $0, date: .distantPast) }
            save()
            return
        }
        // UserDefaults fallback (v1)
        if let data = UserDefaults.standard.data(forKey: "clink-clipboard-v1"),
           let strings = try? JSONDecoder().decode([String].self, from: data) {
            history = strings.map { ClipboardEntry(text: $0, date: .distantPast) }
            save()
        }
    }

    private func save() {
        if let url = fileURL,
           let data = try? JSONEncoder().encode(history) {
            try? data.write(to: url, options: .atomic)
            return
        }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "clink-clipboard-v2")
        }
    }
}
