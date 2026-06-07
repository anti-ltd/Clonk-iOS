/**
 `PanelManager`: observable App Group store for user-authored `ClinkPanel`s,
 mirroring `ExtensionManager`. Seeds the sample panels on first launch and posts a
 Darwin notification on save so a running keyboard can reload.
 */
import SwiftUI

@MainActor
@Observable
public final class PanelManager {
    public private(set) var items: [ClinkPanel] = []

    public static let didChangeNotification = "ltd.anti.clink.panelsDidChange"

    private var loading = false

    public init() { load() }

    public var enabledItems: [ClinkPanel] { items.filter { $0.enabled } }

    // MARK: - CRUD

    public func add(_ panel: ClinkPanel) { items.insert(panel, at: 0); save() }

    public func upsert(_ panel: ClinkPanel) {
        if let i = items.firstIndex(where: { $0.id == panel.id }) { items[i] = panel }
        else { items.append(panel) }
        save()
    }

    public func delete(id: String) { items.removeAll { $0.id == id }; save() }

    public func setEnabled(_ enabled: Bool, id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].enabled = enabled
        save()
    }

    public func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    public func reset() { items = ClinkPanel.samples; save() }

    // MARK: - Sharing (.clinkpanel = JSON)

    public func exportData(_ panel: ClinkPanel) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(panel)
    }

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
