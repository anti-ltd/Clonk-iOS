import SwiftUI

/// A keyboard color theme. Themes are pure data so they round-trip through the
/// App Group and can be edited in the container app, then read by the keyboard
/// extension. v0.1 ships a set of presets; a future version lets users author
/// and save their own (the model already supports it).
/// How a theme's keys are rendered.
public enum KeyMaterial: String, Codable, Sendable, Hashable {
    /// Opaque key faces filled with the theme's colors.
    case solid
    /// Apple's Liquid Glass — translucent, refractive keys (iOS 26+, with an
    /// `.ultraThinMaterial` fallback below that). The theme's colors become
    /// tints and text colors; the background goes translucent so the keys
    /// refract the system keyboard backdrop.
    case liquidGlass
}

public struct Theme: Identifiable, Codable, Equatable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var material: KeyMaterial
    /// Whole-keyboard backdrop.
    public var background: RGBA
    /// Letter / number key faces.
    public var keyFill: RGBA
    /// Glyph color on letter keys.
    public var keyText: RGBA
    /// Function keys (shift, delete, return, mode switch).
    public var specialKeyFill: RGBA
    /// Glyph color on function keys.
    public var specialKeyText: RGBA
    /// Pressed-state / popup highlight.
    public var accent: RGBA
    /// Drives the extension's `UIInputView` appearance + status bar.
    public var isDark: Bool

    public init(
        id: String, name: String,
        background: RGBA, keyFill: RGBA, keyText: RGBA,
        specialKeyFill: RGBA, specialKeyText: RGBA, accent: RGBA,
        isDark: Bool, material: KeyMaterial = .solid
    ) {
        self.id = id; self.name = name; self.material = material
        self.background = background; self.keyFill = keyFill; self.keyText = keyText
        self.specialKeyFill = specialKeyFill; self.specialKeyText = specialKeyText
        self.accent = accent; self.isDark = isDark
    }
}

public extension Theme {
    /// The built-in themes, in display order. The first is the default.
    static let presets: [Theme] = [
        Theme(
            id: "graphite", name: "Graphite",
            background: RGBA(hex: 0x1C1C1E),
            keyFill: RGBA(hex: 0x3A3A3C),
            keyText: RGBA(hex: 0xFFFFFF),
            specialKeyFill: RGBA(hex: 0x2C2C2E),
            specialKeyText: RGBA(hex: 0xEBEBF0),
            accent: RGBA(hex: 0x0A84FF),
            isDark: true
        ),
        Theme(
            id: "snow", name: "Snow",
            background: RGBA(hex: 0xD1D3D9),
            keyFill: RGBA(hex: 0xFFFFFF),
            keyText: RGBA(hex: 0x1C1C1E),
            specialKeyFill: RGBA(hex: 0xACB0BA),
            specialKeyText: RGBA(hex: 0x1C1C1E),
            accent: RGBA(hex: 0x007AFF),
            isDark: false
        ),
        Theme(
            id: "paper", name: "Paper",
            background: RGBA(hex: 0xE8E2D4),
            keyFill: RGBA(hex: 0xFBF7EE),
            keyText: RGBA(hex: 0x3A352B),
            specialKeyFill: RGBA(hex: 0xC9C1AE),
            specialKeyText: RGBA(hex: 0x3A352B),
            accent: RGBA(hex: 0xC2683A),
            isDark: false
        ),
        Theme(
            id: "mechanical", name: "Mechanical",
            background: RGBA(hex: 0x2B2622),
            keyFill: RGBA(hex: 0x4A423A),
            keyText: RGBA(hex: 0xF4E9D8),
            specialKeyFill: RGBA(hex: 0x352F29),
            specialKeyText: RGBA(hex: 0xD8C7AE),
            accent: RGBA(hex: 0xE0A458),
            isDark: true
        ),
        Theme(
            id: "synthwave", name: "Synthwave",
            background: RGBA(hex: 0x1A1033),
            keyFill: RGBA(hex: 0x2D1B5E),
            keyText: RGBA(hex: 0xF7F0FF),
            specialKeyFill: RGBA(hex: 0x221248),
            specialKeyText: RGBA(hex: 0xFF6FD8),
            accent: RGBA(hex: 0x2DE2E6),
            isDark: true
        ),
        Theme(
            id: "forest", name: "Forest",
            background: RGBA(hex: 0x12241B),
            keyFill: RGBA(hex: 0x1F4332),
            keyText: RGBA(hex: 0xEAF6EE),
            specialKeyFill: RGBA(hex: 0x18301F),
            specialKeyText: RGBA(hex: 0xBFE3CC),
            accent: RGBA(hex: 0x55D98C),
            isDark: true
        ),
        Theme(
            id: "midnight", name: "Midnight",
            background: RGBA(hex: 0x0B1026),
            keyFill: RGBA(hex: 0x1B2347),
            keyText: RGBA(hex: 0xE6ECFF),
            specialKeyFill: RGBA(hex: 0x141A38),
            specialKeyText: RGBA(hex: 0xB9C4E6),
            accent: RGBA(hex: 0x5B8CFF),
            isDark: true
        ),
        Theme(
            id: "carbon", name: "Carbon",
            background: RGBA(hex: 0x000000),
            keyFill: RGBA(hex: 0x141414),
            keyText: RGBA(hex: 0xFFFFFF),
            specialKeyFill: RGBA(hex: 0x0A0A0A),
            specialKeyText: RGBA(hex: 0xBFBFBF),
            accent: RGBA(hex: 0xFF453A),
            isDark: true
        ),
        Theme(
            id: "dracula", name: "Dracula",
            background: RGBA(hex: 0x282A36),
            keyFill: RGBA(hex: 0x44475A),
            keyText: RGBA(hex: 0xF8F8F2),
            specialKeyFill: RGBA(hex: 0x21222C),
            specialKeyText: RGBA(hex: 0xBD93F9),
            accent: RGBA(hex: 0xFF79C6),
            isDark: true
        ),
        Theme(
            id: "nord", name: "Nord",
            background: RGBA(hex: 0x2E3440),
            keyFill: RGBA(hex: 0x3B4252),
            keyText: RGBA(hex: 0xECEFF4),
            specialKeyFill: RGBA(hex: 0x272C36),
            specialKeyText: RGBA(hex: 0xD8DEE9),
            accent: RGBA(hex: 0x88C0D0),
            isDark: true
        ),
        Theme(
            id: "solarized-dark", name: "Solarized Dark",
            background: RGBA(hex: 0x002B36),
            keyFill: RGBA(hex: 0x073642),
            keyText: RGBA(hex: 0xD3CBB7),
            specialKeyFill: RGBA(hex: 0x00252E),
            specialKeyText: RGBA(hex: 0x93A1A1),
            accent: RGBA(hex: 0x2AA198),
            isDark: true
        ),
        Theme(
            id: "ocean", name: "Ocean",
            background: RGBA(hex: 0x0A1F2B),
            keyFill: RGBA(hex: 0x123C4A),
            keyText: RGBA(hex: 0xE0F7FA),
            specialKeyFill: RGBA(hex: 0x0C2D38),
            specialKeyText: RGBA(hex: 0xA7DDE6),
            accent: RGBA(hex: 0x21D4C6),
            isDark: true
        ),
        Theme(
            id: "ember", name: "Ember",
            background: RGBA(hex: 0x2A1410),
            keyFill: RGBA(hex: 0x4A211A),
            keyText: RGBA(hex: 0xFFE9DF),
            specialKeyFill: RGBA(hex: 0x381812),
            specialKeyText: RGBA(hex: 0xF3B9A3),
            accent: RGBA(hex: 0xFF6B35),
            isDark: true
        ),
        Theme(
            id: "crimson", name: "Crimson",
            background: RGBA(hex: 0x1F0A0D),
            keyFill: RGBA(hex: 0x3D161B),
            keyText: RGBA(hex: 0xFFE8EC),
            specialKeyFill: RGBA(hex: 0x2C0F13),
            specialKeyText: RGBA(hex: 0xE9A8B2),
            accent: RGBA(hex: 0xFF2D55),
            isDark: true
        ),
        Theme(
            id: "matrix", name: "Matrix",
            background: RGBA(hex: 0x000A00),
            keyFill: RGBA(hex: 0x062E06),
            keyText: RGBA(hex: 0x4DFF4D),
            specialKeyFill: RGBA(hex: 0x031B03),
            specialKeyText: RGBA(hex: 0x2ECC40),
            accent: RGBA(hex: 0x00FF41),
            isDark: true
        ),
        Theme(
            id: "royal", name: "Royal",
            background: RGBA(hex: 0x12100A),
            keyFill: RGBA(hex: 0x252013),
            keyText: RGBA(hex: 0xF7EFD8),
            specialKeyFill: RGBA(hex: 0x1A1610),
            specialKeyText: RGBA(hex: 0xD9C58C),
            accent: RGBA(hex: 0xE8B923),
            isDark: true
        ),
        Theme(
            id: "sakura", name: "Sakura",
            background: RGBA(hex: 0xF6DCE3),
            keyFill: RGBA(hex: 0xFFF2F5),
            keyText: RGBA(hex: 0x4A2E36),
            specialKeyFill: RGBA(hex: 0xE8B6C4),
            specialKeyText: RGBA(hex: 0x4A2E36),
            accent: RGBA(hex: 0xE8567E),
            isDark: false
        ),
        Theme(
            id: "mint", name: "Mint",
            background: RGBA(hex: 0xD6EFE2),
            keyFill: RGBA(hex: 0xF4FBF7),
            keyText: RGBA(hex: 0x1E3A2C),
            specialKeyFill: RGBA(hex: 0xB2DCC6),
            specialKeyText: RGBA(hex: 0x1E3A2C),
            accent: RGBA(hex: 0x12B886),
            isDark: false
        ),
        Theme(
            id: "lavender", name: "Lavender",
            background: RGBA(hex: 0xE5DFF5),
            keyFill: RGBA(hex: 0xF8F5FF),
            keyText: RGBA(hex: 0x352A4A),
            specialKeyFill: RGBA(hex: 0xC9BCE6),
            specialKeyText: RGBA(hex: 0x352A4A),
            accent: RGBA(hex: 0x7C5CFF),
            isDark: false
        ),
        Theme(
            id: "solarized-light", name: "Solarized Light",
            background: RGBA(hex: 0xEEE8D5),
            keyFill: RGBA(hex: 0xFDF6E3),
            keyText: RGBA(hex: 0x586E75),
            specialKeyFill: RGBA(hex: 0xDDD6C1),
            specialKeyText: RGBA(hex: 0x657B83),
            accent: RGBA(hex: 0xCB4B16),
            isDark: false
        ),
        Theme(
            id: "bubblegum", name: "Bubblegum",
            background: RGBA(hex: 0xFCE1F0),
            keyFill: RGBA(hex: 0xFFFFFF),
            keyText: RGBA(hex: 0x5A2A47),
            specialKeyFill: RGBA(hex: 0xF6BFE0),
            specialKeyText: RGBA(hex: 0x5A2A47),
            accent: RGBA(hex: 0xFF4FA3),
            isDark: false
        ),
        Theme(
            id: "latte", name: "Latte",
            background: RGBA(hex: 0xE6D9C8),
            keyFill: RGBA(hex: 0xFBF4EA),
            keyText: RGBA(hex: 0x4A3B2A),
            specialKeyFill: RGBA(hex: 0xCDB89E),
            specialKeyText: RGBA(hex: 0x4A3B2A),
            accent: RGBA(hex: 0xB5651D),
            isDark: false
        ),
        // Liquid Glass — colors act as tints; translucent backdrop so the keys
        // refract the system keyboard background.
        Theme(
            id: "liquid-dark", name: "Liquid Dark",
            background: RGBA(hex: 0x1C1C1E, a: 0.28),
            keyFill: RGBA(hex: 0xFFFFFF, a: 0.10),
            keyText: RGBA(hex: 0xFFFFFF),
            specialKeyFill: RGBA(hex: 0xFFFFFF, a: 0.06),
            specialKeyText: RGBA(hex: 0xF2F2F7),
            accent: RGBA(hex: 0x0A84FF),
            isDark: true, material: .liquidGlass
        ),
        Theme(
            id: "liquid-light", name: "Liquid Light",
            background: RGBA(hex: 0xF5F5F7, a: 0.22),
            keyFill: RGBA(hex: 0xFFFFFF, a: 0.32),
            keyText: RGBA(hex: 0x1C1C1E),
            specialKeyFill: RGBA(hex: 0x000000, a: 0.06),
            specialKeyText: RGBA(hex: 0x1C1C1E),
            accent: RGBA(hex: 0x007AFF),
            isDark: false, material: .liquidGlass
        ),
        Theme(
            id: "liquid-mint", name: "Liquid Mint",
            background: RGBA(hex: 0xD6EFE2, a: 0.20),
            keyFill: RGBA(hex: 0xFFFFFF, a: 0.30),
            keyText: RGBA(hex: 0x143324),
            specialKeyFill: RGBA(hex: 0x000000, a: 0.05),
            specialKeyText: RGBA(hex: 0x143324),
            accent: RGBA(hex: 0x12B886),
            isDark: false, material: .liquidGlass
        ),
        Theme(
            id: "liquid-ember", name: "Liquid Ember",
            background: RGBA(hex: 0x2A1410, a: 0.30),
            keyFill: RGBA(hex: 0xFFFFFF, a: 0.10),
            keyText: RGBA(hex: 0xFFF0E8),
            specialKeyFill: RGBA(hex: 0xFFFFFF, a: 0.06),
            specialKeyText: RGBA(hex: 0xFFD9C7),
            accent: RGBA(hex: 0xFF6B35),
            isDark: true, material: .liquidGlass
        ),
    ]

    static let `default`: Theme = presets[0]

    /// Defaults for the "match system" light/dark pair.
    static var defaultDark: Theme { presets.first(where: \.isDark) ?? presets[0] }
    static var defaultLight: Theme { presets.first(where: { !$0.isDark }) ?? presets[0] }

    static var lightPresets: [Theme] { presets.filter { !$0.isDark } }
    static var darkPresets: [Theme] { presets.filter(\.isDark) }

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
