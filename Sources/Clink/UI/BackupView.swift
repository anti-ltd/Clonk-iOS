/**
 Backup and restore. Exports / imports `KeyboardSettings` as a `.clinkconfig`
 file and surfaces the reset-to-defaults actions. The controls live in
 `BackupControls`, hosted both as a pushed screen (`BackupView`) and as a
 themedSheet from the sidebar.
 */
import SwiftUI
import iUXiOS
import UniformTypeIdentifiers

/// The document type for an exported configuration — the whole `KeyboardSettings`
/// as JSON in a `.clinkconfig` file. Mirrors `.clinkTheme`, just a wider snapshot.
extension UTType {
    static var clinkConfig: UTType { UTType("ltd.anti.clink.config") ?? .json }
}

/// Backup & restore the whole configuration, plus the reset actions. These are
/// app-level management — pulled out of "Advanced" (which is now just keyboard
/// tuning) and surfaced under Setup, where someone actually looks to back up or
/// start over.
struct BackupView: View {
    var body: some View {
        ScrollView {
            BackupControls()
                .padding(UX.screenPadding)
        }
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.inline)
        .themePageBackground()
    }
}

/// The save / import / reset controls, shared by the pushed screen and the sheet.
struct BackupControls: View {
    @Environment(AppModel.self) private var model

    @State private var confirmResetAdvanced = false
    @State private var confirmResetAll = false

    /// Drives the system share sheet (AirDrop / Messages / …).
    @State private var sharingConfig = false
    /// Drives the save-to-Files exporter.
    @State private var savingConfig = false
    /// Drives the `.clinkconfig` import picker.
    @State private var importingConfig = false
    /// Raw bytes of an imported .clinkconfig waiting on the user’s confirm-to-replace.
    @State private var pendingImport: Data?

    var body: some View {
        VStack(spacing: UX.cardSpacing) {
            CardSection("Configuration") {
                Text("Save your whole setup to a file to back it up or share it, then import it on another device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, UX.rowVPadding)
                HStack(spacing: UX.cardSpacing) {
                    actionButton("Save", systemImage: "folder") {
                        savingConfig = true
                    }
                    actionButton("Share", systemImage: "square.and.arrow.up") {
                        sharingConfig = true
                    }
                    actionButton("Import", systemImage: "square.and.arrow.down") {
                        importingConfig = true
                    }
                }
                .padding(.bottom, UX.rowVPadding)
            }

            CardSection("Reset") {
                Button("Reset advanced settings") { confirmResetAdvanced = true }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, UX.rowVPadding)
                Divider()
                Button("Reset all settings", role: .destructive) { confirmResetAll = true }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, UX.rowVPadding)
            }
        }
        .fileImporter(isPresented: $importingConfig,
                      allowedContentTypes: [.clinkConfig, .json],
                      allowsMultipleSelection: false) { handleConfigImport($0) }
        .fileExporter(isPresented: $savingConfig,
                      document: ConfigDocument(data: model.exportedConfiguration() ?? Data()),
                      contentType: .clinkConfig,
                      defaultFilename: "Clink Configuration") { _ in }
        .sheet(isPresented: $sharingConfig) {
            if let url = exportConfigURL() {
                ShareSheet(items: [url])
            } else {
                Text("Couldn’t prepare the configuration for export.").padding()
            }
        }
        .confirmationDialog("Reset advanced settings to their defaults?",
                            isPresented: $confirmResetAdvanced, titleVisibility: .visible) {
            Button("Reset advanced settings", role: .destructive) {
                model.resetAdvancedSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restores hitbox size, cursor scroll sensitivity, and all physics values. Other settings are untouched.")
        }
        .confirmationDialog("Reset all settings to their defaults?",
                            isPresented: $confirmResetAll, titleVisibility: .visible) {
            Button("Reset all settings", role: .destructive) {
                model.resetAllSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restores every setting to default. Your custom themes and saved emoji skin tones are kept.")
        }
        .confirmationDialog("Replace your settings with the imported file?",
                            isPresented: Binding(get: { pendingImport != nil },
                                                 set: { if !$0 { pendingImport = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingImport) { imported in
            Button("Replace settings", role: .destructive) {
                model.importConfiguration(from: imported)
                pendingImport = nil
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: { _ in
            Text("Loads settings from the file. Your themes are untouched.")
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.body.weight(.medium))
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Configuration export / import

    private func exportConfigURL() -> URL? {
        guard let data = model.exportedConfiguration() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clink Configuration.clinkconfig")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    private func handleConfigImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        pendingImport = data
    }
}

/// Minimal `FileDocument` wrapping the exported configuration bytes, so "Save"
/// can write a `.clinkconfig` straight into Files via the system exporter.
private struct ConfigDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.clinkConfig, .json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// A thin wrapper over `UIActivityViewController` so the configuration can be
/// shared as a `.clinkconfig` file (AirDrop, Files, Messages…).
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#if DEBUG
#Preview { BackupView().clinkPreview() }
#endif
