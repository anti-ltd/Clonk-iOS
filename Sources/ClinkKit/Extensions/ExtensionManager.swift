/**
 `ExtensionManager`: observable store for user-authored `ClinkExtension`s. Holds
 the ordered list, persisting to the App Group container so the keyboard
 extension and the container app see the same data — the same pattern as
 `NotepadManager` / `ClipboardManager`. Seeds the sample actions on first launch.

 A Darwin notification is posted on save so a running keyboard can reload live;
 otherwise the keyboard reads fresh on appear.
 

 Module: extensions · Target: ClinkKit
 Learn: docs/14-extensions-sdk.md
 */
import SwiftUI

/// Observable App Group store for user-authored `ClinkExtension` actions. The
/// container app edits the list; the keyboard extension reads it and runs scripts
/// via `PyEngine`. Posts a Darwin notification on save so a live keyboard reloads.
@MainActor
@Observable
public final class ExtensionManager {
    /// All user actions, in display order (also the keyboard panel order).
    public private(set) var items: [ClinkExtension] = []

    /// Darwin notification posted when the extension list changes.
    public static let didChangeNotification = "ltd.anti.clink.extensionsDidChange"

    /// Suppresses `save()` while hydrating from disk (avoids a spurious notify).
    private var loading = false

    public init() { load() }

    /// The actions that should appear in the keyboard panel.
    public var enabledItems: [ClinkExtension] { items.filter { $0.enabled } }

    // MARK: - CRUD

    /// Prepend a new action (most-recent editing position).
    public func add(_ ext: ClinkExtension) {
        items.insert(ext, at: 0)
        save()
    }

    /// Insert or replace by id.
    public func upsert(_ ext: ClinkExtension) {
        if let i = items.firstIndex(where: { $0.id == ext.id }) {
            items[i] = ext
        } else {
            items.append(ext)
        }
        save()
    }

    public func delete(id: String) {
        items.removeAll { $0.id == id }
        save()
    }

    /// Toggle visibility in the keyboard extensions panel without deleting.
    public func setEnabled(_ enabled: Bool, id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].enabled = enabled
        save()
    }

    /// Reorder the management list — display order is also the keyboard panel order.
    public func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Restore the built-in sample actions (destructive).
    public func reset() {
        items = ClinkExtension.samples
        save()
    }

    // MARK: - Running

    /// Run an action's script over the given input. Pure; safe on the main thread.
    public func run(_ ext: ClinkExtension, input: String) -> PyRunResult {
        PyEngine.run(source: ext.source, input: input)
    }

    // MARK: - Sharing (.clinkext = JSON)

    /// Encode a single extension for export / share.
    public func exportData(_ ext: ClinkExtension) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(ext)
    }

    /// Import an extension from `.clinkext` bytes (a single object or an array).
    /// Imported actions get fresh ids so they never collide with existing ones.
    /// Returns the imported items (added to the list), or [] on failure.
    @discardableResult
    public func importData(_ data: Data) -> [ClinkExtension] {
        let decoder = JSONDecoder()
        var imported: [ClinkExtension] = []
        if let one = try? decoder.decode(ClinkExtension.self, from: data) {
            imported = [one]
        } else if let many = try? decoder.decode([ClinkExtension].self, from: data) {
            imported = many
        }
        guard !imported.isEmpty else { return [] }
        let fresh = imported.map { ext -> ClinkExtension in
            var copy = ext
            copy.id = "ext-\(UUID().uuidString.prefix(8))"
            return copy
        }
        items.append(contentsOf: fresh)
        save()
        return fresh
    }

    // MARK: - Persistence (App Group file)

    private struct Payload: Codable { var items: [ClinkExtension] }

    private var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID)?
            .appendingPathComponent("clink-extensions.v1.json")
    }

    /// Reload from disk — used by the keyboard to pick up app-side edits.
    public func reload() { load() }

    private func load() {
        loading = true
        defer { loading = false }
        if let url = fileURL,
           let data = try? Data(contentsOf: url),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            items = payload.items
            return
        }
        if let data = UserDefaults.standard.data(forKey: "clink-extensions-v1"),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            items = payload.items
            return
        }
        // First launch: seed the samples so the SDK ships with working examples.
        items = ClinkExtension.samples
        save()
    }

    private func save() {
        guard !loading else { return }
        let payload = Payload(items: items)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        if let url = fileURL {
            try? data.write(to: url, options: .atomic)
        } else {
            UserDefaults.standard.set(data, forKey: "clink-extensions-v1")
        }
        postDidChange()
    }

    private func postDidChange() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(Self.didChangeNotification as CFString),
            nil, nil, true
        )
    }
}
