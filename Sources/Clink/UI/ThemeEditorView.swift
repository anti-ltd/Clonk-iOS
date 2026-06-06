/**
 Theme picker with a live preview. Handles the preset grid, custom theme CRUD,
 and `.clink` file export / import. Also defines `ThemeSwatch` and `ShareSheet`.
 */
import SwiftUI
import iUXiOS
import UniformTypeIdentifiers

/// The document type for an exported theme — a JSON `Theme` carried in a `.clink`
/// file. Derived from the extension (not registered in Info.plist), which is
/// enough to both name exports and filter the import picker.
extension UTType {
    static var clinkTheme: UTType { UTType("ltd.anti.clink.theme") ?? .json }
}

struct ThemeEditorView: View {
    @Environment(AppModel.self) private var model

    /// Non-nil while the create/edit sheet is up. Set to a fresh draft to
    /// create, or to an existing custom theme to edit.
    @State private var builderTheme: Theme?

    /// The custom theme being exported — drives the share sheet.
    @State private var exportingTheme: Theme?
    /// Whether the `.clink` import file picker is up.
    @State private var importing = false

    /// Whether the "name your new theme" alert is up, and the dark flag the
    /// fresh theme should seed from once named.
    @State private var creatingName = false
    @State private var pendingDark = false
    /// The custom theme being renamed via long-press — drives the rename alert.
    @State private var renameTarget: Theme?
    /// Shared text buffer for both the create and rename name alerts.
    @State private var nameField = ""

    /// Which appearance's themes are shown while "Match system appearance" is on —
    /// the two modes live behind a segmented tab rather than stacked sections.
    @State private var appearanceTab: Appearance = .light
    private enum Appearance: Hashable { case light, dark }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    private var customThemes: [Theme] { model.settings.customThemes }
    private func isCustom(_ theme: Theme) -> Bool {
        customThemes.contains { $0.id == theme.id }
    }

    /// Settings used only for the live preview — pins the theme to whichever
    /// appearance tab is selected so the preview tracks the tab, not the system
    /// dark/light mode.
    private var previewSettings: KeyboardSettings {
        var s = model.settings
        guard s.matchSystemAppearance else { return s }
        s.matchSystemAppearance = false
        s.themeID = appearanceTab == .light ? s.lightThemeID : s.darkThemeID
        return s
    }

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: previewSettings) {
                CardSection("Background") {
                    ToggleRow("Show background",
                              subtitle: "Paint the selected theme's background — a custom theme's photo, or its colour — behind the keys. Off keeps the keyboard transparent so it blends with the app.",
                              isOn: $model.settings.backgroundVisible)
                }

                if model.settings.matchSystemAppearance {
                    Picker("Appearance", selection: $appearanceTab) {
                        Text("Light").tag(Appearance.light)
                        Text("Dark").tag(Appearance.dark)
                    }
                    .pickerStyle(.segmented)

                    switch appearanceTab {
                    case .light:
                        grid(nil, themes: Theme.lightPresets + customThemes.filter { !$0.isDark },
                             selectedID: model.settings.lightThemeID) { model.settings.lightThemeID = $0 }
                    case .dark:
                        grid(nil, themes: Theme.darkPresets + customThemes.filter(\.isDark),
                             selectedID: model.settings.darkThemeID) { model.settings.darkThemeID = $0 }
                    }
                } else {
                    grid(nil, themes: model.settings.allThemes,
                         selectedID: model.settings.themeID) { model.settings.themeID = $0 }
                }

                bottomBar
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.clinkTheme, .json],
                      allowsMultipleSelection: false) { handleImport($0) }
        .sheet(item: $exportingTheme) { theme in
            if let url = exportURL(for: theme) {
                ShareSheet(items: [url])
            } else {
                Text("Couldn’t prepare this theme for export.").padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.settings.matchSystemAppearance.toggle()
                } label: {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(model.settings.matchSystemAppearance
                                         ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .accessibilityLabel("Match system appearance")
                .accessibilityValue(model.settings.matchSystemAppearance ? "On" : "Off")
            }
        }
        .sheet(item: $builderTheme) { theme in
            ThemeBuilderView(theme: theme)
        }
        .alert("New Theme", isPresented: $creatingName) {
            TextField("Theme name", text: $nameField)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                var theme = Theme.newCustom(
                    id: "custom-\(UUID().uuidString.prefix(8))", dark: pendingDark)
                let trimmed = nameField.trimmingCharacters(in: .whitespacesAndNewlines)
                theme.name = trimmed.isEmpty ? "My Theme" : trimmed
                builderTheme = theme
            }
        } message: {
            Text("Name your theme.")
        }
        .alert("Rename Theme",
               isPresented: Binding(get: { renameTarget != nil },
                                    set: { if !$0 { renameTarget = nil } })) {
            TextField("Theme name", text: $nameField)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") {
                if var theme = renameTarget {
                    let trimmed = nameField.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { theme.name = trimmed }
                    model.saveCustomTheme(theme)
                }
                renameTarget = nil
            }
        }
    }

    /// Two equal-width actions: make a fresh theme, or pull one in from a `.clink`
    /// file someone shared.
    private var bottomBar: some View {
        HStack(spacing: UX.cardSpacing) {
            actionButton("Create", systemImage: "plus.circle.fill") {
                // Name first via a dialog — the builder no longer carries a text
                // field, which trapped the software keyboard in the pinned layout.
                pendingDark = model.settings.theme.isDark
                nameField = ""
                creatingName = true
            }
            actionButton("Import", systemImage: "square.and.arrow.down") {
                importing = true
            }
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

    // MARK: - Export / import

    /// Write `theme` to a `<name>.clink` file in the temp dir and hand back its URL
    /// for the share sheet. A `.clink` is just the theme's JSON.
    private func exportURL(for theme: Theme) -> URL? {
        guard let data = try? JSONEncoder().encode(theme) else { return nil }
        let trimmed = theme.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = (trimmed.isEmpty ? "Theme" : trimmed)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).clink")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    /// Decode the picked `.clink` file into a fresh custom theme, save it, and
    /// select it. A new id is minted so importing never clobbers an existing theme
    /// (and re-importing yields a distinct copy rather than a silent overwrite).
    private func handleImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              var theme = try? JSONDecoder().decode(Theme.self, from: data) else { return }
        theme.id = "custom-\(UUID().uuidString.prefix(8))"
        model.saveCustomTheme(theme)
        if model.settings.matchSystemAppearance {
            if theme.isDark { model.settings.darkThemeID = theme.id }
            else { model.settings.lightThemeID = theme.id }
            appearanceTab = theme.isDark ? .dark : .light
        } else {
            model.settings.themeID = theme.id
        }
    }

    private func duplicate(_ theme: Theme) -> Theme {
        var copy = theme
        copy.id = "custom-\(UUID().uuidString.prefix(8))"
        copy.name = "\(theme.name) Copy"
        return copy
    }

    @ViewBuilder
    private func grid(_ title: String?, themes: [Theme], selectedID: String, select: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(themes) { theme in
                    let custom = isCustom(theme)
                    let swatch = ThemeSwatch(theme: theme, selected: theme.id == selectedID, isCustom: custom)
                        .onTapGesture { select(theme.id) }
                    if custom {
                        swatch.contextMenu {
                            Button { nameField = theme.name; renameTarget = theme } label: { Label("Rename", systemImage: "character.cursor.ibeam") }
                            Button { builderTheme = theme } label: { Label("Edit", systemImage: "pencil") }
                            Button { builderTheme = duplicate(theme) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                            Button { exportingTheme = theme } label: { Label("Export…", systemImage: "square.and.arrow.up") }
                            Button(role: .destructive) {
                                model.deleteCustomTheme(id: theme.id)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    } else {
                        swatch.contextMenu {
                            Button { builderTheme = duplicate(theme) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                        }
                    }
                }
            }
        }
    }
}

/// A thin wrapper over `UIActivityViewController` so a custom theme can be shared
/// as a `.clink` file (AirDrop, Files, Messages…).
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct ThemeSwatch: View {
    let theme: Theme
    let selected: Bool
    var isCustom: Bool = false

    private var isGlass: Bool { theme.material == .liquidGlass }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Miniature keyboard: backdrop + three sample keys + an accent key.
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in miniKey(accent: false) }
                miniKey(accent: true).frame(width: 18)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background {
                swatchBackdrop
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 5) {
                Text(theme.name).font(.subheadline.weight(.medium)).lineLimit(1)
                if isCustom {
                    Image(systemName: "pencil")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if isGlass {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                }
            }
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2)
        )
        .contentShape(Rectangle())
    }

    /// One sample key in the swatch — glass themes render a translucent
    /// material key so the picker communicates the Liquid Glass look.
    @ViewBuilder private func miniKey(accent: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        if isGlass {
            shape.fill(.ultraThinMaterial)
                .overlay(accent ? shape.fill(theme.accent.color.opacity(0.55)) : nil)
                .overlay(shape.strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                .frame(height: 26)
        } else {
            shape.fill(accent ? theme.accent.color : theme.keyFill.color)
                .frame(height: 26)
        }
    }

    /// Glass swatches sit on a representative gradient so the translucency
    /// reads; solid swatches use the theme's own background.
    @ViewBuilder private var swatchBackdrop: some View {
        if isGlass {
            LinearGradient(
                colors: theme.isDark
                    ? [Color(hex: 0x3A3A52), Color(hex: 0x15151F)]
                    : [Color(hex: 0xAEC6E8), Color(hex: 0xE8DCC8)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if let id = theme.backgroundImageID,
                  let image = ThemeBackgroundStore.shared.image(for: id) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            theme.background.color
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
