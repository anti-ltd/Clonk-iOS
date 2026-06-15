/**
 Core `Theme` value type: every color slot, material, font options, and optional
 background/gradient IDs that fully describe how the keyboard looks.
 

 Module: theme · Target: ClinkKit
 Learn: docs/11-theming.md
 */
import SwiftUI

/// Complete visual description of the keyboard: colour slots, optional photo/
/// gradient backdrops, Liquid Glass options, and font choices. Travels as JSON in
/// `KeyboardSettings.customThemes` and as `.clink` exports; photo bytes live in
/// `ThemeBackgroundStore`, referenced by id.
public struct Theme: Identifiable, Codable, Equatable, Sendable, Hashable {
    public var id: String
    public var name: String
    /// Solid keys vs Liquid Glass (translucent, refractive).
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

    // MARK: - Decoding

    // Tolerant decode: older presets and `.clink` files missing newer keys fall
    // back to defaults rather than failing the whole settings blob.
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
    /// The theme to actually *render* with. Identical to `self` except that a
    /// Liquid Glass material is forced to `.solid` while the motion profile is
    /// shedding GPU load (Low Power, thermal pressure, or — in the keyboard
    /// extension — memory pressure; see `MotionProfile.prefersSolidSurfaces`).
    /// Glass is the heaviest layer the keyboard composites and the first thing to
    /// drop frames when the extension is memory-starved, so it gives way to keep
    /// typing fluid, then restores itself once pressure clears. Resolve this ONCE
    /// where the canvas derives its theme — every downstream `material ==
    /// .liquidGlass` check then flips together, so glass never ends up half-on.
    @MainActor var effective: Theme {
        guard material == .liquidGlass, MotionProfile.shared.prefersSolidSurfaces else { return self }
        var t = self
        t.material = .solid
        return t
    }
}

