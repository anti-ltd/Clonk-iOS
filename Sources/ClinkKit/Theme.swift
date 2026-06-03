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
