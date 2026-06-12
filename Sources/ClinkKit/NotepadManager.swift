/**
 `NotepadManager`: observable backing store for the quick notepad. Holds the
 compose buffer and the saved-notes archive, persisted to the App Group container.
 

 Module: settings · Target: ClinkKit
 Learn: docs/01-settings-and-storage.md
 */
import SwiftUI

/// Backing store for the quick notepad. Holds one always-on compose buffer
/// (`scratch` — what the keys type into while the notepad panel is open) plus,
/// in `notes` mode, an archive of saved snippets. Persists to the App Group
/// container so the keyboard extension and the container app see the same data,
/// falling back to `UserDefaults.standard` when the group is unavailable — the
/// same pattern as `ClipboardManager`.
@MainActor
@Observable
public final class NotepadManager {
    /// The live compose buffer. Bound to the panel and written by the keyboard's
    /// keys while the notepad is open. Persisted on every change so a jot in
    /// progress survives the keyboard being torn down between host apps.
    public var scratch: String = "" {
        didSet {
            guard !loading, scratch != oldValue else { return }
            save()
        }
    }

    /// Saved snippets (newest first), used only in `NotepadMode.notes`.
    public private(set) var notes: [NotepadNote] = []

    private let maxNotes = 50
    /// Suppresses `scratch`'s `didSet` save while hydrating from disk.
    private var loading = false

    public init() { load() }

    // MARK: - Notes archive

    /// Save the given text as a new note at the front. No-op for blank text.
    public func addNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        notes.insert(NotepadNote(text: trimmed), at: 0)
        if notes.count > maxNotes { notes = Array(notes.prefix(maxNotes)) }
        save()
    }

    /// Remove one saved note by index in `notes`.
    public func deleteNote(at index: Int) {
        guard notes.indices.contains(index) else { return }
        notes.remove(at: index)
        save()
    }

    /// Wipe the saved-notes archive (scratch buffer is untouched).
    public func clearNotes() {
        notes.removeAll()
        save()
    }

    // MARK: - Persistence (App Group file, mirrors ClipboardManager)

    private struct Payload: Codable {
        var scratch: String
        var notes: [NotepadNote]
    }

    private var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID)?
            .appendingPathComponent("clink-notepad.v1.json")
    }

    private func load() {
        loading = true
        defer { loading = false }
        if let url = fileURL,
           let data = try? Data(contentsOf: url),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            scratch = payload.scratch
            notes = payload.notes
            return
        }
        if let data = UserDefaults.standard.data(forKey: "clink-notepad-v1"),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            scratch = payload.scratch
            notes = payload.notes
        }
    }

    private func save() {
        let payload = Payload(scratch: scratch, notes: notes)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        if let url = fileURL {
            try? data.write(to: url, options: .atomic)
            return
        }
        UserDefaults.standard.set(data, forKey: "clink-notepad-v1")
    }
}
