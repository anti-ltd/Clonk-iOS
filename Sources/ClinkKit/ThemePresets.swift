/**
 Built-in preset catalog and convenience accessors. Each preset is defined in
 its own `Theme+<Name>.swift` file; this extension aggregates them into the
 ordered `presets` array and adds default-resolution helpers.
 

 Module: theme · Target: ClinkKit
 Learn: docs/11-theming.md
 */
public extension Theme {
    /// The built-in themes, in display order. The first is the default.
    static let presets: [Theme] = [
        .graphite, .snow, .paper, .mechanical, .synthwave, .forest,
        .midnight, .carbon, .dracula, .nord, .solarizedDark, .ocean,
        .ember, .crimson, .matrix, .royal, .sakura, .mint, .lavender,
        .solarizedLight, .bubblegum, .latte, .coral, .cinder,
        .liquidDark, .liquidLight, .liquidMint, .liquidEmber,
    ]

    static let `default`: Theme = .liquidLight

    /// Defaults for the "match system" light/dark pair.
    static var defaultDark: Theme { .liquidDark }
    static var defaultLight: Theme { .liquidLight }

    /// Built-in themes for light system appearance.
    static var lightPresets: [Theme] { presets.filter { !$0.isDark } }
    /// Built-in themes for dark system appearance.
    static var darkPresets: [Theme] { presets.filter(\.isDark) }

    /// Resolve a preset id; unknown ids fall back to `.default`.
    static func preset(id: String) -> Theme {
        presets.first { $0.id == id } ?? .default
    }

    /// A fresh custom theme to start editing from — seeded from the default
    /// solid look for the chosen appearance so every colour is sensible.
    static func newCustom(id: String, dark: Bool) -> Theme {
        let base = dark ? defaultDark : defaultLight
        return Theme(
            id: id, name: "My Theme",
            background: base.background, keyFill: base.keyFill, keyText: base.keyText,
            specialKeyFill: base.specialKeyFill, specialKeyText: base.specialKeyText,
            accent: base.accent, isDark: dark, material: .solid
        )
    }
}
