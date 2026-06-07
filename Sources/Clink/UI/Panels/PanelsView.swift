/**
 `PanelsView`: manage user-authored custom panels (full custom keyboard UIs).
 Create, edit, reorder, enable/disable, import, and share `ClinkPanel`s. Mirrors
 `ExtensionsView`.
 */
import SwiftUI
import iUXiOS
import UniformTypeIdentifiers

struct PanelsView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var importMessage: String?

    var body: some View {
        @Bindable var m = model
        List {
            Section {
                Toggle("Show in keyboard", isOn: $m.settings.customPanelsEnabled)
                Toggle("Show alongside built-in panels", isOn: $m.settings.customPanelsStandalone)
                    .disabled(!m.settings.customPanelsEnabled)
                Button { importing = true } label: {
                    Label("Import panel…", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Custom Panels")
            } footer: {
                Text("Build full custom keyboard UIs in Python — calculators, snippet boards, pickers. “Alongside built-in panels” gives each its own button in the panel picker instead of nesting them behind one Panels button; individual panels can override this in their editor.")
            }

            Section("Your panels") {
                NavigationLink {
                    PanelEditorView(
                        draft: ClinkPanel(name: "New Panel", summary: "", source: ClinkPanel.starterSource),
                        isNew: true)
                } label: {
                    Label("New panel", systemImage: "plus.circle.fill").foregroundStyle(.tint)
                }

                ForEach(model.panels.items) { panel in
                    NavigationLink {
                        PanelEditorView(draft: panel, isNew: false)
                    } label: {
                        row(panel)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            model.panels.setEnabled(!panel.enabled, id: panel.id)
                        } label: {
                            Label(panel.enabled ? "Disable" : "Enable",
                                  systemImage: panel.enabled ? "eye.slash" : "eye")
                        }
                        .tint(panel.enabled ? .gray : .green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.panels.delete(id: panel.id)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                .onMove { model.panels.move(from: $0, to: $1) }

                if model.panels.items.isEmpty {
                    Text("No panels yet — tap “New panel” to create one.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(role: .destructive) { model.panels.reset() } label: {
                    Label("Reset to sample panels", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Custom Panels")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.clinkPanel, .json],
                      allowsMultipleSelection: false) { handleImport($0) }
        .alert("Import", isPresented: Binding(get: { importMessage != nil },
                                              set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) { importMessage = nil }
        } message: { Text(importMessage ?? "") }
    }

    private func row(_ panel: ClinkPanel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: panel.icon.isEmpty ? "square.grid.2x2" : panel.icon)
                .font(.system(size: 18)).foregroundStyle(.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(panel.name).font(.body)
                if !panel.summary.isEmpty {
                    Text(panel.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if !panel.enabled {
                Text("Off").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
            }
        }
        .opacity(panel.enabled ? 1 : 0.5)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { importMessage = "Couldn't read that file."; return }
        let imported = model.panels.importData(data)
        importMessage = imported.isEmpty
            ? "That file isn't a valid Clink panel."
            : "Imported \(imported.count) panel\(imported.count == 1 ? "" : "s")."
    }
}
