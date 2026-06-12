/**
 `PanelManager`: observable App Group store for user-authored `ClinkPanel`s,
 mirroring `ExtensionManager`. Seeds the sample panels on first launch and posts a
 Darwin notification on save so a running keyboard can reload.
 

 Module: custom-panels · Target: ClinkKit
 Learn: docs/07-custom-panels.md
 */
import SwiftUI

/// Observable App Group store for user-authored `ClinkPanel` custom UIs. Mirrors
/// `ExtensionManager`: the app edits, the keyboard renders via `PanelRuntime`.
/// Darwin notification on save for live reload.
@MainActor
@Observable
public final class PanelManager {
    /// All custom panels, in display / picker order.
    public private(set) var items: [ClinkPanel] = []

    /// Darwin notification posted when the panel list changes.
    public static let didChangeNotification = "ltd.anti.clink.panelsDidChange"

    /// Suppresses `save()` while hydrating from disk.
    private var loading = false

    public init() { load() }

    /// Panels that should appear in the keyboard picker.
    public var enabledItems: [ClinkPanel] { items.filter { $0.enabled } }

    // MARK: - CRUD

    public func add(_ panel: ClinkPanel) { items.insert(panel, at: 0); save() }

    /// Insert or replace by id.
    public func upsert(_ panel: ClinkPanel) {
        if let i = items.firstIndex(where: { $0.id == panel.id }) { items[i] = panel }
        else { items.append(panel) }
        save()
    }

    public func delete(id: String) { items.removeAll { $0.id == id }; save() }

    /// Toggle visibility in the picker without deleting.
    public func setEnabled(_ enabled: Bool, id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].enabled = enabled
        save()
    }

    public func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Restore built-in sample panels (destructive).
    public func reset() { items = ClinkPanel.samples; save() }

    // MARK: - Sharing (.clinkpanel = JSON)

    /// Encode a single panel for export / share.
    public func exportData(_ panel: ClinkPanel) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(panel)
    }

    /// Import from `.clinkpanel` bytes (single object or array). Fresh ids avoid
    /// collisions with existing panels. Returns imported items, or [] on failure.
    @discardableResult
    public func importData(_ data: Data) -> [ClinkPanel] {
        let decoder = JSONDecoder()
        var imported: [ClinkPanel] = []
        if let one = try? decoder.decode(ClinkPanel.self, from: data) { imported = [one] }
        else if let many = try? decoder.decode([ClinkPanel].self, from: data) { imported = many }
        guard !imported.isEmpty else { return [] }
        let fresh = imported.map { p -> ClinkPanel in
            var copy = p; copy.id = "panel-\(UUID().uuidString.prefix(8))"; return copy
        }
        items.append(contentsOf: fresh)
        save()
        return fresh
    }

    // MARK: - Persistence

    private struct Payload: Codable { var items: [ClinkPanel] }

    private var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID)?
            .appendingPathComponent("clink-panels.v1.json")
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
        if let data = UserDefaults.standard.data(forKey: "clink-panels-v1"),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            items = payload.items
            return
        }
        items = ClinkPanel.samples
        save()
    }

    private func save() {
        guard !loading else { return }
        let payload = Payload(items: items)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        if let url = fileURL { try? data.write(to: url, options: .atomic) }
        else { UserDefaults.standard.set(data, forKey: "clink-panels-v1") }
        postDidChange()
    }

    private func postDidChange() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center, CFNotificationName(Self.didChangeNotification as CFString), nil, nil, true)
    }
}
