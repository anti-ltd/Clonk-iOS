/**
 `ExtensionsView`: manage the user's custom actions (the Python extension SDK).
 Create, edit, reorder, enable/disable, import, and share `ClinkExtension`s, plus
 the master toggle that surfaces them as a keyboard action panel.
 */
import SwiftUI
import iUXiOS
import UniformTypeIdentifiers

struct ExtensionsView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var importMessage: String?

    var body: some View {
        @Bindable var m = model
        List {
            Section {
                Toggle("Show in keyboard", isOn: $m.settings.userExtensionsEnabled)
                Button {
                    importing = true
                } label: {
                    Label("Import action…", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Custom Actions")
            } footer: {
                Text("Write your own keyboard actions in Python. Enabled actions appear behind the keyboard's action button. Tap an action to edit it; swipe to enable or delete.")
            }

            Section("Your actions") {
                NavigationLink {
                    ExtensionEditorView(
                        draft: ClinkExtension(name: "New Action", summary: "", source: ClinkExtension.starterSource),
                        isNew: true)
                } label: {
                    Label("New action", systemImage: "plus.circle.fill")
                        .foregroundStyle(.tint)
                }

                ForEach(model.extensions.items) { ext in
                    NavigationLink {
                        ExtensionEditorView(draft: ext, isNew: false)
                    } label: {
                        row(ext)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            model.extensions.setEnabled(!ext.enabled, id: ext.id)
                        } label: {
                            Label(ext.enabled ? "Disable" : "Enable",
                                  systemImage: ext.enabled ? "eye.slash" : "eye")
                        }
                        .tint(ext.enabled ? .gray : .green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.extensions.delete(id: ext.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onMove { model.extensions.move(from: $0, to: $1) }

                if model.extensions.items.isEmpty {
                    Text("No actions yet — tap “New action” to create one.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    model.extensions.reset()
                } label: {
                    Label("Reset to sample actions", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Custom Actions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.clinkExt, .json],
                      allowsMultipleSelection: false) { handleImport($0) }
        .alert("Import", isPresented: Binding(get: { importMessage != nil },
                                              set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func row(_ ext: ClinkExtension) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ext.icon.isEmpty ? "wand.and.stars" : ext.icon)
                .font(.system(size: 18))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(ext.name).font(.body)
                if !ext.summary.isEmpty {
                    Text(ext.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if !ext.enabled {
                Text("Off")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
            }
        }
        .opacity(ext.enabled ? 1 : 0.5)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            importMessage = "Couldn't read that file."
            return
        }
        let imported = model.extensions.importData(data)
        importMessage = imported.isEmpty
            ? "That file isn't a valid Clink action."
            : "Imported \(imported.count) action\(imported.count == 1 ? "" : "s")."
    }
}
