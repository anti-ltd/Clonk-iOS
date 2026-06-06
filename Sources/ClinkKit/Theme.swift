import SwiftUI

// MARK: - Gradient types

public enum GradientType: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case linear, radial, angular
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .linear:  return "Linear"
        case .radial:  return "Radial"
        case .angular: return "Angular"
        }
    }
}

/// One color stop in a `ThemeGradient`. The `id` is ephemeral (not persisted)
/// so ForEach can track stops without requiring stable encoded identifiers.
public struct GradientStop: Sendable, Equatable, Hashable, Identifiable {
    public var id = UUID()
    public var color: RGBA
    public var position: Double  // 0…1

    public init(color: RGBA, position: Double) {
        self.color = color; self.position = position
    }
}

extension GradientStop: Codable {
    private enum CodingKeys: String, CodingKey { case color, position }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        color = try c.decode(RGBA.self, forKey: .color)
        position = try c.decode(Double.self, forKey: .position)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(color, forKey: .color)
        try c.encode(position, forKey: .position)
    }
}

public struct ThemeGradient: Codable, Sendable, Equatable, Hashable {
    public var type: GradientType
    /// Rotation in degrees (0–360). Used by linear and angular; ignored by radial.
    public var rotation: Double
    public var stops: [GradientStop]

    public init(type: GradientType = .linear, rotation: Double = 180, stops: [GradientStop]) {
        self.type = type; self.rotation = rotation; self.stops = stops
    }

    /// A two-stop gradient seeded from `color`, lightened toward the second stop.
    public static func seed(from color: RGBA) -> ThemeGradient {
        let lighter = RGBA(min(color.r + 0.25, 1), min(color.g + 0.25, 1), min(color.b + 0.25, 1), color.a)
        return ThemeGradient(stops: [
            GradientStop(color: color, position: 0),
            GradientStop(color: lighter, position: 1),
        ])
    }
}

public extension ThemeGradient {
    private var swiftGradient: Gradient {
        let sorted = stops.sorted { $0.position < $1.position }
        return Gradient(stops: sorted.map { .init(color: $0.color.color, location: $0.position) })
    }

    @ViewBuilder func makeView() -> some View {
        let g = swiftGradient
        switch type {
        case .linear:
            LinearGradient(gradient: g, startPoint: linearStart, endPoint: linearEnd)
        case .radial:
            RadialGradient(gradient: g, center: .center, startRadius: 0, endRadius: 800)
        case .angular:
            AngularGradient(gradient: g, center: .center, angle: .degrees(rotation))
        }
    }

    private var linearStart: UnitPoint {
        let rad = (rotation - 90) * .pi / 180
        return UnitPoint(x: 0.5 - cos(rad) * 0.5, y: 0.5 - sin(rad) * 0.5)
    }
    private var linearEnd: UnitPoint {
        let rad = (rotation - 90) * .pi / 180
        return UnitPoint(x: 0.5 + cos(rad) * 0.5, y: 0.5 + sin(rad) * 0.5)
    }
}

// MARK: - Font design / weight

public enum ThemeFontDesign: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case `default`, rounded, serif, monospaced
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .default:    return "Default"
        case .rounded:    return "Rounded"
        case .serif:      return "Serif"
        case .monospaced: return "Mono"
        }
    }
    public var fontDesign: Font.Design {
        switch self {
        case .default:    return .default
        case .rounded:    return .rounded
        case .serif:      return .serif
        case .monospaced: return .monospaced
        }
    }
}

public enum ThemeFontWeight: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case thin, ultraLight, light, regular, medium, semibold, bold, heavy, black
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .thin:       return "Thin"
        case .ultraLight: return "Ultra Light"
        case .light:      return "Light"
        case .regular:    return "Regular"
        case .medium:     return "Medium"
        case .semibold:   return "Semibold"
        case .bold:       return "Bold"
        case .heavy:      return "Heavy"
        case .black:      return "Black"
        }
    }
    public var fontWeight: Font.Weight {
        switch self {
        case .thin:       return .thin
        case .ultraLight: return .ultraLight
        case .light:      return .light
        case .regular:    return .regular
        case .medium:     return .medium
        case .semibold:   return .semibold
        case .bold:       return .bold
        case .heavy:      return .heavy
        case .black:      return .black
        }
    }
}

// MARK: - Key material

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

/// Which Liquid Glass variant the keys use. `regular` is the frostier, more
/// material look; `clear` is thinner and far more see-through — it refracts the
/// backdrop more strongly. Maps to SwiftUI's `Glass.regular` / `Glass.clear`.
public enum GlassVariant: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case regular
    case clear

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .regular: return "Regular"
        case .clear:   return "Clear"
        }
    }
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
    /// When set (custom themes only), the id of a background **photo** in
    /// `ThemeBackgroundStore`. When the global `KeyboardSettings.backgroundVisible`
    /// switch is on, a present image is painted behind the keys in place of the
    /// solid `background` colour; if the file is missing (e.g. a `.clink` imported
    /// from another device) rendering falls back to `backgroundGradient`, then
    /// `background`.
    public var backgroundImageID: String?
    /// Optional gradient painted behind the keys when `backgroundVisible` is on.
    /// Overrides the solid `background` colour but is itself overridden by
    /// `backgroundImageID` when an image resolves.
    public var backgroundGradient: ThemeGradient?
    /// When set on a **Liquid Glass** custom theme, the id of a photo in
    /// `ThemeBackgroundStore` that fills the keys: one image is laid behind the
    /// whole key area and each key reveals (masks to) the slice sitting behind it
    /// — Q shows the image's top-left, P its top-right — with the glass on top
    /// refracting that slice. Ignored on solid themes or if the file is missing.
    public var keyImageID: String?
    /// Optional gradient used as the per-key Liquid Glass backdrop — the same
    /// masked-to-key-shapes approach as `keyImageID` but painted from a gradient
    /// instead of a photo. Overridden by `keyImageID` when an image resolves.
    /// Ignored on solid themes.
    public var keyGradient: ThemeGradient?
    /// Liquid Glass variant for the keys (regular / clear). Ignored on solid
    /// themes. Defaults to `.regular` — the look every preset shipped with.
    public var glassVariant: GlassVariant
    /// Use the interactive glass lens on every key (not just shift), so the
    /// material warps under a press. Off by default. Ignored on solid themes.
    public var glassInteractive: Bool
    /// How strongly the theme colours tint the glass, 0…1 — a multiplier on the
    /// key-fill tint's own opacity. 1 = full tint (default); lower lets more clear
    /// glass through so the refraction reads. Ignored on solid themes.
    public var glassTintStrength: Double
    /// Font design applied to character keys (Default / Rounded / Serif / Mono).
    public var keyFontDesign: ThemeFontDesign
    /// Font weight applied to character keys.
    public var keyFontWeight: ThemeFontWeight

    public init(
        id: String, name: String,
        background: RGBA, keyFill: RGBA, keyText: RGBA,
        specialKeyFill: RGBA, specialKeyText: RGBA, accent: RGBA,
        isDark: Bool, material: KeyMaterial = .solid,
        backgroundImageID: String? = nil,
        backgroundGradient: ThemeGradient? = nil,
        keyImageID: String? = nil,
        keyGradient: ThemeGradient? = nil,
        glassVariant: GlassVariant = .regular,
        glassInteractive: Bool = false,
        glassTintStrength: Double = 1.0,
        keyFontDesign: ThemeFontDesign = .default,
        keyFontWeight: ThemeFontWeight = .regular
    ) {
        self.id = id; self.name = name; self.material = material
        self.background = background; self.keyFill = keyFill; self.keyText = keyText
        self.specialKeyFill = specialKeyFill; self.specialKeyText = specialKeyText
        self.accent = accent; self.isDark = isDark
        self.backgroundImageID = backgroundImageID
        self.backgroundGradient = backgroundGradient
        self.keyImageID = keyImageID
        self.keyGradient = keyGradient
        self.glassVariant = glassVariant
        self.glassInteractive = glassInteractive
        self.glassTintStrength = glassTintStrength
        self.keyFontDesign = keyFontDesign
        self.keyFontWeight = keyFontWeight
    }

    // Custom decoder so older payloads (presets and `.clink` files written before
    // `material` / `backgroundImageID` existed) still decode — the new keys fall
    // back to their defaults rather than failing the whole settings blob.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        material = try c.decodeIfPresent(KeyMaterial.self, forKey: .material) ?? .solid
        background = try c.decode(RGBA.self, forKey: .background)
        keyFill = try c.decode(RGBA.self, forKey: .keyFill)
        keyText = try c.decode(RGBA.self, forKey: .keyText)
        specialKeyFill = try c.decode(RGBA.self, forKey: .specialKeyFill)
        specialKeyText = try c.decode(RGBA.self, forKey: .specialKeyText)
        accent = try c.decode(RGBA.self, forKey: .accent)
        isDark = try c.decode(Bool.self, forKey: .isDark)
        backgroundImageID = try c.decodeIfPresent(String.self, forKey: .backgroundImageID)
        backgroundGradient = try c.decodeIfPresent(ThemeGradient.self, forKey: .backgroundGradient)
        keyImageID = try c.decodeIfPresent(String.self, forKey: .keyImageID)
        keyGradient = try c.decodeIfPresent(ThemeGradient.self, forKey: .keyGradient)
        glassVariant = (try? c.decodeIfPresent(GlassVariant.self, forKey: .glassVariant)) ?? .regular
        glassInteractive = try c.decodeIfPresent(Bool.self, forKey: .glassInteractive) ?? false
        glassTintStrength = try c.decodeIfPresent(Double.self, forKey: .glassTintStrength) ?? 1.0
        keyFontDesign = (try? c.decodeIfPresent(ThemeFontDesign.self, forKey: .keyFontDesign)) ?? .default
        keyFontWeight = (try? c.decodeIfPresent(ThemeFontWeight.self, forKey: .keyFontWeight)) ?? .regular
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
        Theme(
            id: "coral", name: "Coral",
            background: RGBA(hex: 0xF9F5EF),
            keyFill: RGBA(hex: 0xFFFFFF),
            keyText: RGBA(hex: 0x2A1F1A),
            specialKeyFill: RGBA(hex: 0xEDE4D8),
            specialKeyText: RGBA(hex: 0x2A1F1A),
            accent: RGBA(hex: 0xD4614A),
            isDark: false,
            keyFontDesign: .serif
        ),
        Theme(
            id: "cinder", name: "Cinder",
            background: RGBA(hex: 0x1A1512),
            keyFill: RGBA(hex: 0x2E2521),
            keyText: RGBA(hex: 0xF2EDE4),
            specialKeyFill: RGBA(hex: 0x231B17),
            specialKeyText: RGBA(hex: 0xC4B8AE),
            accent: RGBA(hex: 0xD4614A),
            isDark: true,
            keyFontDesign: .serif
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
        Theme(
            id: "dobble", name: "Dobble",
            background: RGBA(0.10980392156862745, 0.10980392156862745, 0.11764705882352941, 1),
            keyFill: RGBA(0.9553680419921875, 0.9195098876953125, 1, 0.9384483098983765),
            keyText: RGBA(0.5051727294921875, 0, 0.5771484375, 1),
            specialKeyFill: RGBA(0.99664306640625, 0.846649169921875, 1, 0.9178984761238098),
            specialKeyText: RGBA(0.5908203125, 0, 0.7106170654296875, 1),
            accent: RGBA(0.85614013671875, 0.6346588134765625, 1, 0.9738767743110657),
            isDark: false, material: .liquidGlass
        ),
        Theme(
            id: "snobble", name: "Snobble",
            background: RGBA(0.10980392156862745, 0.10980392156862745, 0.11764705882352941, 1),
            keyFill: RGBA(0.1396636962890625, 0, 0.1912689208984375, 0.5608813166618347),
            keyText: RGBA(0.87738037109375, 0.846649169921875, 1, 1),
            specialKeyFill: RGBA(0.161346435546875, 0, 0.1606597900390625, 0.8113809823989868),
            specialKeyText: RGBA(0.8345794677734375, 0.7075347900390625, 1, 1),
            accent: RGBA(0.2863311767578125, 0, 0.533447265625, 0.8581883311271667),
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
