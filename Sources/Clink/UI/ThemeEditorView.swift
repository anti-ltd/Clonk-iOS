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
    static var clinkTheme: UTType { UTType(exportedAs: "ltd.anti.clink.theme") }
}

struct ThemeEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    /// Non-nil while the create/edit sheet is up. Set to a fresh draft to
    /// create, or to an existing custom theme to edit.
    @State private var builderTheme: Theme?

    /// The custom theme being exported — drives the share sheet.
    @State private var exportingTheme: Theme?
    /// Whether the "export all custom themes" share sheet is up.
    @State private var exportingAll = false
    /// Whether the `.clink` import file picker is up.
    @State private var importing = false

    /// The top-right options popover (match-system, background, create, import).
    @State private var showOptions = false

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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

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

    /// Force the preview into the appearance of the selected tab so a dark theme
    /// previews dark even on a light-mode device (and vice versa). Nil — follow
    /// the device — unless matching the system, where the tab picks the mode.
    private var previewColorScheme: ColorScheme? {
        guard model.settings.matchSystemAppearance else { return nil }
        return appearanceTab == .dark ? .dark : .light
    }

    /// The resolved theme for the current tab — drives the app-wide theming
    /// override while this page is visible.
    private var previewTheme: Theme {
        if model.settings.matchSystemAppearance {
            let id = appearanceTab == .light ? model.settings.lightThemeID : model.settings.darkThemeID
            return model.settings.theme(withID: id)
        }
        return model.settings.theme(withID: model.settings.themeID)
    }

    var body: some View {
        PinnedPreviewLayout(settings: previewSettings,
                            previewColorScheme: previewColorScheme,
                            bottomBar: appearanceBar) {
                if model.settings.matchSystemAppearance {
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
        }
        .environment(\.resolvedKeyboardTheme, previewTheme)
        .environment(\.cardTint, previewTheme.keyFill.color)
        .environment(\.useGlassCards, previewTheme.material == .liquidGlass)
        .themePopover(isPresented: $showOptions) { optionsPopover }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            appearanceTab = colorScheme == .dark ? .dark : .light
        }
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
        .sheet(isPresented: $exportingAll) {
            let urls = customThemes.compactMap { exportURL(for: $0) }
            if urls.isEmpty {
                Text("No custom themes to export.").padding()
            } else {
                ShareSheet(items: urls)
            }
        }
        .navTrailingButton("ellipsis.circle") { showOptions.toggle() }
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

    /// The Light/Dark tab, pinned to the bottom while themes scroll. Only shown
    /// while matching the system appearance (the only time both modes are picked).
    private var appearanceBar: AnyView? {
        guard model.settings.matchSystemAppearance else { return nil }
        return AnyView(
            ThemedTabPicker(options: [("Light", Appearance.light), ("Dark", Appearance.dark)],
                            selection: $appearanceTab)
        )
    }

    /// The top-right options menu: appearance + background toggles and the
    /// create / import / export-all theme actions. Actions close the popover, then
    /// trigger the matching alert / file picker (which live on the main view).
    private var optionsPopover: some View {
        ThemeOptionsPopover(
            hasCustomThemes: !customThemes.isEmpty,
            onCreate: {
                showOptions = false
                // Name first via a dialog — the builder no longer carries a text
                // field, which trapped the software keyboard in the pinned layout.
                pendingDark = model.settings.theme.isDark
                nameField = ""
                creatingName = true
            },
            onImport: {
                showOptions = false
                importing = true
            },
            onExportAll: {
                showOptions = false
                exportingAll = true
            })
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
            LazyVGrid(columns: columns, spacing: 10) {
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

/// The Theme page's top-right options popover: the appearance + background
/// toggles (moved off the page) and the create / import actions.
private struct ThemeOptionsPopover: View {
    @Environment(AppModel.self) private var model
    var hasCustomThemes: Bool
    var onCreate: () -> Void
    var onImport: () -> Void
    var onExportAll: () -> Void

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            ToggleRow("Match system appearance",
                      subtitle: "Switches theme automatically with the system light/dark mode.",
                      isOn: $model.settings.matchSystemAppearance)
            Divider()
            ToggleRow("Show background",
                      subtitle: "Draws the theme background colour or photo behind the keys.",
                      isOn: $model.settings.backgroundVisible)
            Divider()
            menuButton("Create theme", systemImage: "plus.circle.fill", action: onCreate)
            Divider()
            menuButton("Import theme", systemImage: "square.and.arrow.down", action: onImport)
            Divider()
            menuButton("Export all themes", systemImage: "square.and.arrow.up.on.square",
                       action: onExportAll)
                .disabled(!hasCustomThemes)
                .opacity(hasCustomThemes ? 1 : 0.4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 300)
    }

    private func menuButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).frame(width: 22)
                Text(title)
                Spacer()
            }
            .font(.body)
            .foregroundStyle(.primary)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    @Environment(\.cardTint) private var cardTint
    @Environment(\.useGlassCards) private var useGlassCards
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    let theme: Theme
    let selected: Bool
    var isCustom: Bool = false

    private var isGlass: Bool { theme.material == .liquidGlass }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Miniature keyboard: backdrop + two sample keys + an accent key.
            HStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { _ in miniKey(accent: false) }
                miniKey(accent: true).frame(width: 13)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background {
                swatchBackdrop
                    .clipShape(RoundedRectangle(cornerRadius: max(2, cardCornerRadius - 4), style: .continuous))
            }

            HStack(spacing: 3) {
                Text(theme.name).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                if isCustom {
                    Image(systemName: "pencil")
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                }
                if isGlass {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(theme.accent.color)
                }
            }
        }
        .padding(8)
        .background(cardTint ?? Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(UX.Glass.outlineOpacity),
                              lineWidth: UX.Glass.outlineWidth)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(selected ? AnyShapeStyle(theme.accent.color) : AnyShapeStyle(.clear), lineWidth: 2)
        }
        .contentShape(Rectangle())
    }

    /// One sample key in the swatch — glass themes render a translucent
    /// material key so the picker communicates the Liquid Glass look.
    @ViewBuilder private func miniKey(accent: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: max(1, cardCornerRadius - 8), style: .continuous)
        if isGlass {
            shape.fill(.ultraThinMaterial)
                .overlay(accent ? shape.fill(theme.accent.color.opacity(0.55)) : nil)
                .overlay(shape.strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                .frame(height: 22)
        } else {
            shape.fill(accent ? theme.accent.color : theme.keyFill.color)
                .frame(height: 22)
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
