/**
 `PanelEditorView`: in-app editor for a custom panel. Edit the metadata and the
 PyMini `view(state)` script, then interact with a **live preview** of the real
 keyboard panel — taps insert into a log (instead of a text field) and `set`
 transitions re-render exactly as they will in the keyboard. Mirrors
 `ExtensionEditorView`.
 

 Module: app-ui · Target: Clink
 Learn: docs/07-custom-panels.md
 */
import SwiftUI
import iUXiOS
import UniformTypeIdentifiers

extension UTType {
    static var clinkPanel: UTType { UTType("ltd.anti.clink.panel") ?? .json }
}

/// In-app editor for one `ClinkPanel`: metadata, icon, placement, PyMini source,
/// and a live preview whose tap/insert callbacks log locally (stub — no document proxy).
struct PanelEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.resolvedKeyboardTheme) private var theme

    let isNew: Bool
    @State private var draft: ClinkPanel
    @State private var syntaxError: String?
    @State private var previewNonce = 0
    @State private var insertLog: [String] = []
    @State private var sharing = false
    @State private var confirmDelete = false

    private let iconChoices = [
        "square.grid.2x2", "square.grid.3x3", "plusminus", "face.smiling",
        "text.badge.plus", "die.face.5", "paintpalette", "slider.horizontal.3",
        "calendar", "clock", "list.bullet", "keyboard", "star", "heart",
        "flag", "tag", "bolt", "gift", "music.note", "globe",
    ]

    init(draft: ClinkPanel, isNew: Bool) {
        self.isNew = isNew
        _draft = State(initialValue: draft)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                detailsCard
                iconCard
                placementCard
                codeCard
                previewCard
                if !isNew { manageCard }
            }
            .padding(UX.screenPadding)
        }
        .navigationTitle(isNew ? "New Panel" : draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .themePageBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .sheet(isPresented: $sharing) {
            if let url = exportURL() { ShareSheet(items: [url]) }
            else { Text("Couldn't prepare the panel for sharing.").padding() }
        }
        .confirmationDialog("Delete this panel?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { model.panels.delete(id: draft.id); dismiss() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { revalidate() }
    }

    private var detailsCard: some View {
        CardSection("Details") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: $draft.name).textInputAutocapitalization(.words)
                Divider()
                TextField("Summary (optional)", text: $draft.summary)
            }
            .padding(.vertical, UX.rowVPadding)
        }
    }

    private var iconCard: some View {
        CardSection("Icon") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(iconChoices, id: \.self) { sym in
                        Button { draft.icon = sym } label: {
                            Image(systemName: sym)
                                .font(.system(size: 18))
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(draft.icon == sym ? Color.accentColor.opacity(0.25) : Color(.secondarySystemBackground)))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(draft.icon == sym ? Color.accentColor : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, UX.rowVPadding)
            }
        }
    }

    private var placementCard: some View {
        CardSection("Placement") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Placement", selection: $draft.placement) {
                    ForEach(PanelPlacement.allCases) { p in Text(p.label).tag(p) }
                }
                .pickerStyle(.segmented)
                Text(draft.placement.detail)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, UX.rowVPadding)
        }
    }

    private var codeCard: some View {
        CardSection("Script") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Define view(state) — return a tree from vstack / hstack / grid / text / button / field. Optionally define initial().")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $draft.source)
                    .font(.system(.callout, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 240)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.secondarySystemBackground)))
                    .onChange(of: draft.source) { _, _ in revalidate() }
                if let syntaxError {
                    Label(syntaxError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.vertical, UX.rowVPadding)
        }
    }

    private var previewCard: some View {
        CardSection("Live preview") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Interact with it — buttons work.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { previewNonce += 1; insertLog.removeAll() } label: {
                        Label("Reload", systemImage: "arrow.clockwise").font(.caption)
                    }
                }
                CustomPanelView(
                    source: draft.source,
                    theme: theme,
                    cornerRadius: CGFloat(model.settings.keyCornerRadius),
                    onInsert: { text in insertLog.append(text) })
                    .id(previewNonce)   // rebuild (reset state) only on Reload
                    .frame(height: 320)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.background.color))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.secondary.opacity(0.25)))

                if !insertLog.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("INSERTED").font(.caption2.weight(.semibold)).foregroundStyle(.green)
                        Text(insertLog.joined(separator: " "))
                            .font(.system(.callout, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.tertiarySystemBackground)))
                }
            }
            .padding(.vertical, UX.rowVPadding)
        }
    }

    private var manageCard: some View {
        CardSection("Manage") {
            Button("Share panel", systemImage: "square.and.arrow.up") { sharing = true }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, UX.rowVPadding)
            Divider()
            Button("Delete panel", systemImage: "trash", role: .destructive) { confirmDelete = true }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, UX.rowVPadding)
        }
    }

    private func revalidate() { syntaxError = PyEngine.validate(source: draft.source) }

    private func save() { model.panels.upsert(draft); dismiss() }

    private func exportURL() -> URL? {
        guard let data = model.panels.exportData(draft) else { return nil }
        let safe = draft.name.isEmpty ? "Panel" : draft.name
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).clinkpanel")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
