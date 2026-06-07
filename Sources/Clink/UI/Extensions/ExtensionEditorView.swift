/**
 `ExtensionEditorView`: the in-app code editor for a custom action. Edit the
 metadata (name / icon / input source) and the PyMini `transform` script, then
 test it live in the run console — input goes in, the inserted output (plus any
 `print(...)` log and errors) comes out — before saving. Mirrors the app's
 CardSection / themed-page conventions.
 */
import SwiftUI
import iUXiOS
import UniformTypeIdentifiers

/// The document type for a shared action: a single `ClinkExtension` as JSON.
extension UTType {
    static var clinkExt: UTType { UTType("ltd.anti.clink.ext") ?? .json }
}

struct ExtensionEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// True when creating a brand-new action (vs. editing an existing one).
    let isNew: Bool

    @State private var draft: ClinkExtension
    @State private var testInput: String = "Hello world"
    @State private var result: PyRunResult?
    @State private var syntaxError: String?
    @State private var sharing = false
    @State private var confirmDelete = false

    /// Common, recognizable SF Symbols offered for the action's icon.
    private let iconChoices = [
        "wand.and.stars", "textformat", "textformat.size.larger", "number",
        "arrow.left.arrow.right", "lasso", "sparkles", "function",
        "quote.bubble", "link", "calendar", "clock", "percent", "die.face.5",
        "globe", "envelope", "creditcard", "barcode", "face.smiling", "flame",
    ]

    init(draft: ClinkExtension, isNew: Bool) {
        self.isNew = isNew
        _draft = State(initialValue: draft)
        // Word actions read better tested against a single word.
        _testInput = State(initialValue: draft.input == .none ? "" : "Hello world")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                detailsCard
                iconCard
                inputCard
                codeCard
                consoleCard
                if !isNew { deleteCard }
            }
            .padding(UX.screenPadding)
        }
        .navigationTitle(isNew ? "New Action" : draft.name)
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
            else { Text("Couldn't prepare the action for sharing.").padding() }
        }
        .confirmationDialog("Delete this action?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.extensions.delete(id: draft.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { revalidate() }
    }

    // MARK: - Cards

    private var detailsCard: some View {
        CardSection("Details") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: $draft.name)
                    .textInputAutocapitalization(.words)
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
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(draft.icon == sym ? Color.accentColor.opacity(0.25) : Color(.secondarySystemBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(draft.icon == sym ? Color.accentColor : .clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, UX.rowVPadding)
            }
        }
    }

    private var inputCard: some View {
        CardSection("Input") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Input", selection: $draft.input) {
                    ForEach(ExtInputSource.allCases) { src in
                        Text(src.label).tag(src)
                    }
                }
                .pickerStyle(.segmented)
                Text(draft.input.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, UX.rowVPadding)
        }
    }

    private var codeCard: some View {
        CardSection("Script") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Define transform(text) — its return value is inserted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft.source)
                    .font(.system(.callout, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 200)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.secondarySystemBackground)))
                    .onChange(of: draft.source) { _, _ in revalidate() }
                if let syntaxError {
                    Label(syntaxError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, UX.rowVPadding)
        }
    }

    private var consoleCard: some View {
        CardSection("Run console") {
            VStack(alignment: .leading, spacing: 10) {
                if draft.input != .none {
                    TextField("Test input", text: $testInput, axis: .vertical)
                        .font(.system(.callout, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .lineLimit(1...4)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.secondarySystemBackground)))
                }
                Button { runTest() } label: {
                    Label("Run", systemImage: "play.fill")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                if let result {
                    resultView(result)
                }
            }
            .padding(.vertical, UX.rowVPadding)
        }
    }

    @ViewBuilder
    private func resultView(_ r: PyRunResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = r.error {
                consoleBlock(title: "Error", text: error, color: .red, mono: true)
            } else {
                consoleBlock(title: "Inserts", text: r.output ?? "(nothing)", color: .green, mono: true)
            }
            if !r.log.isEmpty {
                consoleBlock(title: "print()", text: r.log.joined(separator: "\n"), color: .secondary, mono: true)
            }
        }
    }

    private func consoleBlock(title: String, text: String, color: Color, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
            Text(text)
                .font(mono ? .system(.callout, design: .monospaced) : .callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.tertiarySystemBackground)))
    }

    private var deleteCard: some View {
        CardSection("Manage") {
            Button("Share action", systemImage: "square.and.arrow.up") { sharing = true }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, UX.rowVPadding)
            Divider()
            Button("Delete action", systemImage: "trash", role: .destructive) { confirmDelete = true }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, UX.rowVPadding)
        }
    }

    // MARK: - Actions

    private func revalidate() {
        syntaxError = PyEngine.validate(source: draft.source)
    }

    private func runTest() {
        result = PyEngine.run(source: draft.source, input: draft.input == .none ? "" : testInput)
    }

    private func save() {
        var ext = draft
        if ext.summary.isEmpty { ext.summary = "" }
        model.extensions.upsert(ext)
        dismiss()
    }

    private func exportURL() -> URL? {
        guard let data = model.extensions.exportData(draft) else { return nil }
        let safe = draft.name.isEmpty ? "Action" : draft.name
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).clinkext")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }
}

/// Thin wrapper over `UIActivityViewController` for sharing a `.clinkext` file.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
