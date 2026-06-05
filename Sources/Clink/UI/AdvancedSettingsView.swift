import SwiftUI
import iUXiOS
import UniformTypeIdentifiers

/// The document type for an exported configuration — the whole `KeyboardSettings`
/// as JSON in a `.clinkconfig` file. Mirrors `.clinkTheme`, just a wider snapshot.
extension UTType {
    static var clinkConfig: UTType { UTType("ltd.anti.clink.config") ?? .json }
}

struct AdvancedSettingsView: View {
    private enum Tab { case touch, spring, timing, config }

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: Tab = .touch
    @State private var previewDark: Bool = false
    @State private var confirmResetAdvanced = false
    @State private var confirmResetAll = false

    /// Drives the share sheet for "Save configuration".
    @State private var exportingConfig = false
    /// Drives the `.clinkconfig` import picker.
    @State private var importingConfig = false
    /// A decoded configuration waiting on the user’s confirm-to-replace.
    @State private var pendingImport: KeyboardSettings?

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            showHitboxOverlay: selectedTab == .touch,
                            previewColorScheme: model.settings.matchSystemAppearance
                                ? (previewDark ? .dark : .light)
                                : nil) {
            Picker("", selection: $selectedTab) {
                Text("Touch").tag(Tab.touch)
                Text("Spring").tag(Tab.spring)
                Text("Timing").tag(Tab.timing)
                Text("Config").tag(Tab.config)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)

            switch selectedTab {
            case .touch:
                touchTab(model: model)
            case .spring:
                springTab(model: model)
            case .timing:
                timingTab(model: model)
            case .config:
                configTab
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.settings.matchSystemAppearance {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { previewDark.toggle() } label: {
                        Image(systemName: previewDark ? "moon.fill" : "sun.max")
                    }
                }
            }
        }
        .onAppear { previewDark = colorScheme == .dark }
        .fileImporter(isPresented: $importingConfig,
                      allowedContentTypes: [.clinkConfig, .json],
                      allowsMultipleSelection: false) { handleConfigImport($0) }
        .sheet(isPresented: $exportingConfig) {
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
                model.importConfiguration(imported)
                pendingImport = nil
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: { _ in
            Text("Loads every setting from the file, replacing your current configuration — including your custom themes.")
        }
    }

    // MARK: - Tabs

    @ViewBuilder
    private func touchTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Touch") {
            SliderRow("Hitbox size", value: $model.settings.hitboxScale,
                      in: 0.75...1.25, step: 0.05) {
                $0 == 1.0 ? "Default" : "\(Int(($0 * 100).rounded()))%"
            }
        }
        CardSection("Cursor") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Movement type").foregroundStyle(.secondary).font(.subheadline)
                Picker("Movement type", selection: $model.settings.cursorMovementType) {
                    ForEach(CursorMovementType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, UX.rowVPadding)
            Divider()
            Text(cursorHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, UX.rowVPadding)
            Divider()
            SliderRow("Activation time",
                      value: $model.settings.spaceCursorActivationDelay,
                      in: 0...500, step: 25) {
                $0 < 5 ? "Instant" : "\(Int($0))ms"
            }
            Divider()
            SliderRow("Scroll sensitivity",
                      value: Binding(
                        get: { 30 - model.settings.spaceCursorStride },
                        set: { model.settings.spaceCursorStride = 30 - $0 }),
                      in: 8...24, step: 2) {
                $0 == 20 ? "Default" : "\(Int(($0 / 20 * 100).rounded()))%"
            }
            Divider()
            SliderRow("Line length",
                      value: $model.settings.cursorLineStride,
                      in: 5...80, step: 5) {
                "\(Int($0)) chars"
            }
        }
    }

    @ViewBuilder
    private func springTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Key press") {
            SliderRow("Bloom", value: $model.settings.keyBloomScale,
                      in: 1.0...1.4, step: 0.02) {
                $0 == 1.0 ? "Off" : "\(Int(($0 * 100).rounded()))%"
            }
            Divider()
            SliderRow("Speed", value: $model.settings.keySpringResponse,
                      in: 0.08...0.6, step: 0.02) {
                String(format: "%.2fs", $0)
            }
            Divider()
            SliderRow("Springiness", value: $model.settings.keySpringDamping,
                      in: 0.3...1.0, step: 0.05) {
                $0 >= 0.99 ? "Firm" : String(format: "%.2f", $0)
            }
        }
        CardSection("Space bar") {
            SliderRow("Speed", value: $model.settings.spaceSpringResponse,
                      in: 0.08...0.6, step: 0.02) {
                String(format: "%.2fs", $0)
            }
            Divider()
            SliderRow("Springiness", value: $model.settings.spaceSpringDamping,
                      in: 0.3...1.0, step: 0.05) {
                $0 >= 0.99 ? "Firm" : String(format: "%.2f", $0)
            }
            Divider()
            SliderRow("Lean", value: $model.settings.spaceLeanMultiplier,
                      in: 0...0.3, step: 0.01) {
                $0 == 0 ? "Off" : String(format: "%.2f×", $0)
            }
            Divider()
            SliderRow("Cursor shrink", value: $model.settings.spaceCursorDragScale,
                      in: 0.7...1.0, step: 0.02) {
                $0 >= 0.99 ? "Off" : "\(Int(($0 * 100).rounded()))%"
            }
        }
        CardSection("Popup") {
            SliderRow("Speed", value: $model.settings.popupSpringResponse,
                      in: 0.08...0.6, step: 0.02) {
                String(format: "%.2fs", $0)
            }
            Divider()
            SliderRow("Springiness", value: $model.settings.popupSpringDamping,
                      in: 0.3...1.0, step: 0.05) {
                $0 >= 0.99 ? "Firm" : String(format: "%.2f", $0)
            }
        }
    }

    @ViewBuilder
    private func timingTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Key press") {
            SliderRow("Press linger", value: $model.settings.keyPressLinger,
                      in: 0...0.4, step: 0.02) {
                $0 < 0.005 ? "Off" : "\(Int(($0 * 1000).rounded()))ms"
            }
        }
        CardSection("Backspace repeat") {
            Text("How long to hold the key before rapid-delete begins, and how fast it accelerates.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, UX.rowVPadding)
            Divider()
            SliderRow("Hold delay", value: $model.settings.repeatHoldDelay,
                      in: 150...800, step: 25) {
                "\(Int($0))ms"
            }
            Divider()
            SliderRow("Start speed", value: $model.settings.repeatInitialInterval,
                      in: 50...200, step: 10) {
                "\(Int($0))ms"
            }
            Divider()
            SliderRow("Max speed", value: $model.settings.repeatMinInterval,
                      in: 20...80, step: 5) {
                "\(Int($0))ms"
            }
            Divider()
            SliderRow("Acceleration", value: $model.settings.repeatAccelStep,
                      in: 1...20, step: 1) {
                "\(Int($0))ms/step"
            }
        }
    }

    @ViewBuilder
    private var configTab: some View {
        CardSection("Configuration") {
            Text("Save your whole setup to a file to back it up or share it, then import it on another device.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, UX.rowVPadding)
            HStack(spacing: UX.cardSpacing) {
                actionButton("Save", systemImage: "square.and.arrow.up") {
                    exportingConfig = true
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

    // MARK: - Helpers

    private var cursorHelpText: String {
        switch model.settings.cursorMovementType {
        case .spacebar:
            return "Slide on the space bar to move the cursor — left/right by characters, up/down by lines. Raise the activation time so the cursor only engages when you hold deliberately; lower the sensitivity if it still triggers by accident."
        case .trackpad:
            return "Hold the space bar to turn the keyboard into a trackpad — drag to move the cursor (left/right by characters, up/down by lines), then lift to return to the keys. Raise the activation time so it only engages on a deliberate hold; lower the sensitivity if it triggers by accident."
        case .combined:
            return "Type as normal — but hold the space bar and the keys blank out and stop responding while you drag the cursor (left/right by characters, up/down by lines), with the space bar morphing. Lift to return to the keys."
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
        guard let data = try? Data(contentsOf: url),
              let imported = try? JSONDecoder().decode(KeyboardSettings.self, from: data) else { return }
        pendingImport = imported
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
