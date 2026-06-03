import SwiftUI
import iUXiOS

struct ThemeEditorView: View {
    @Environment(AppModel.self) private var model

    /// Non-nil while the create/edit sheet is up. Set to a fresh draft to
    /// create, or to an existing custom theme to edit.
    @State private var builderTheme: Theme?

    /// Which appearance's themes are shown while "Match system appearance" is on —
    /// the two modes live behind a segmented tab rather than stacked sections.
    @State private var appearanceTab: Appearance = .light
    private enum Appearance: Hashable { case light, dark }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    private var customThemes: [Theme] { model.settings.customThemes }
    private func isCustom(_ theme: Theme) -> Bool {
        customThemes.contains { $0.id == theme.id }
    }

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings) {
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

                createButton
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
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
    }

    private var createButton: some View {
        Button {
            // Seed the new theme's appearance from whatever's active now.
            builderTheme = Theme.newCustom(
                id: "custom-\(UUID().uuidString.prefix(8))",
                dark: model.settings.theme.isDark)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                Text("Create a theme")
                Spacer()
            }
            .font(.body.weight(.medium))
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
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
                            Button { builderTheme = theme } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) {
                                model.deleteCustomTheme(id: theme.id)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    } else {
                        swatch
                    }
                }
            }
        }
    }
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
