import Foundation

/// The shape/behaviour of the magnified key popup.
public enum KeyPopupStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    /// A detached rounded bubble floating above the key.
    case floating
    /// A native-style balloon that necks down into the pressed key.
    case balloon
    /// A small flat tile just above the key.
    case flat

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .floating: return "Floating"
        case .balloon:  return "Native"
        case .flat:     return "Flat"
        }
    }
}

/// The full user-customizable configuration of the Clonk keyboard. This is the
/// single value that crosses the process boundary between the container app
/// (which edits it) and the keyboard extension (which renders from it), via the
/// App Group store. Keep it small and `Codable`.
public struct KeyboardSettings: Codable, Equatable, Sendable {
    // Appearance
    /// Theme used when NOT matching the system appearance.
    public var themeID: String
    /// When true, the keyboard auto-switches between `lightThemeID` and
    /// `darkThemeID` to follow the system's light/dark mode.
    public var matchSystemAppearance: Bool
    public var lightThemeID: String
    public var darkThemeID: String
    /// User-authored themes, saved alongside the built-in presets. They travel
    /// with the settings across the App Group so the keyboard extension renders
    /// them exactly like a preset.
    public var customThemes: [Theme]
    // Mechanics
    public var layoutID: String
    public var showNumberRow: Bool
    public var autoCapitalize: Bool
    public var keyPopupEnabled: Bool
    /// The shape of the key popup (floating bubble / native balloon / flat tile).
    public var keyPopupStyle: KeyPopupStyle
    /// Render the key popup with Liquid Glass material on glass themes (instead
    /// of a solid bubble). Ignored on solid themes.
    public var liquidGlassPopup: Bool
    /// Indent the middle letter row by ~half a key, like the system keyboard.
    public var homeRowInset: Bool
    /// How far to indent the middle letter row, as a fraction of the usable row
    /// width applied to each side. ~0.05 matches the system keyboard.
    public var homeRowInsetAmount: Double
    /// Bloom/warp every key on press (the liquid deformation the space bar does
    /// while dragging) — looks best on Liquid Glass themes.
    public var keyPressWarp: Bool
    /// Height of a single key row, in points. Drives the keyboard's overall
    /// height; smaller = shorter keys.
    public var keyHeight: Double
    /// Corner radius of each key, in points. Larger = rounder keys.
    public var keyCornerRadius: Double
    /// Fraction of the row's width the keys occupy; the remainder becomes
    /// symmetric side margins. 1.0 = edge-to-edge, lower = narrower keys.
    public var keyWidthFraction: Double
    /// Horizontal gap between keys in a row, in points.
    public var keySpacing: Double
    /// Vertical gap between rows, in points.
    public var rowSpacing: Double
    /// Show the autocomplete / suggestion bar above the keys.
    public var suggestionsEnabled: Bool
    /// Auto-correct the just-typed word when a space / punctuation is entered.
    public var autocorrectEnabled: Bool
    // Clonk sound + feel
    public var soundPackID: String
    public var soundEnabled: Bool
    public var soundVolume: Double      // 0.0 ... 1.0
    public var hapticsEnabled: Bool

    public init(
        themeID: String = Theme.default.id,
        matchSystemAppearance: Bool = true,
        lightThemeID: String = Theme.defaultLight.id,
        darkThemeID: String = Theme.defaultDark.id,
        customThemes: [Theme] = [],
        layoutID: String = KeyboardLayout.default.id,
        showNumberRow: Bool = false,
        autoCapitalize: Bool = true,
        keyPopupEnabled: Bool = true,
        keyPopupStyle: KeyPopupStyle = .balloon,
        liquidGlassPopup: Bool = true,
        homeRowInset: Bool = true,
        homeRowInsetAmount: Double = 0.05,
        keyPressWarp: Bool = true,
        keyHeight: Double = 46,
        keyCornerRadius: Double = 12,
        keyWidthFraction: Double = 1,
        keySpacing: Double = 5,
        rowSpacing: Double = 7,
        suggestionsEnabled: Bool = true,
        autocorrectEnabled: Bool = true,
        soundPackID: String = SoundPack.default.id,
        soundEnabled: Bool = false,
        soundVolume: Double = 0.8,
        hapticsEnabled: Bool = false
    ) {
        self.themeID = themeID
        self.matchSystemAppearance = matchSystemAppearance
        self.lightThemeID = lightThemeID
        self.darkThemeID = darkThemeID
        self.customThemes = customThemes
        self.layoutID = layoutID
        self.showNumberRow = showNumberRow
        self.autoCapitalize = autoCapitalize
        self.keyPopupEnabled = keyPopupEnabled
        self.keyPopupStyle = keyPopupStyle
        self.liquidGlassPopup = liquidGlassPopup
        self.homeRowInset = homeRowInset
        self.homeRowInsetAmount = homeRowInsetAmount
        self.keyPressWarp = keyPressWarp
        self.keyHeight = keyHeight
        self.keyCornerRadius = keyCornerRadius
        self.keyWidthFraction = keyWidthFraction
        self.keySpacing = keySpacing
        self.rowSpacing = rowSpacing
        self.suggestionsEnabled = suggestionsEnabled
        self.autocorrectEnabled = autocorrectEnabled
        self.soundPackID = soundPackID
        self.soundEnabled = soundEnabled
        self.soundVolume = soundVolume
        self.hapticsEnabled = hapticsEnabled
    }

    public static let `default` = KeyboardSettings()

    // MARK: - Decoding (tolerate older payloads missing the new keys)

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        themeID = try c.decodeIfPresent(String.self, forKey: .themeID) ?? Theme.default.id
        matchSystemAppearance = try c.decodeIfPresent(Bool.self, forKey: .matchSystemAppearance) ?? true
        lightThemeID = try c.decodeIfPresent(String.self, forKey: .lightThemeID) ?? Theme.defaultLight.id
        darkThemeID = try c.decodeIfPresent(String.self, forKey: .darkThemeID) ?? Theme.defaultDark.id
        customThemes = try c.decodeIfPresent([Theme].self, forKey: .customThemes) ?? []
        layoutID = try c.decodeIfPresent(String.self, forKey: .layoutID) ?? KeyboardLayout.default.id
        showNumberRow = try c.decodeIfPresent(Bool.self, forKey: .showNumberRow) ?? false
        autoCapitalize = try c.decodeIfPresent(Bool.self, forKey: .autoCapitalize) ?? true
        keyPopupEnabled = try c.decodeIfPresent(Bool.self, forKey: .keyPopupEnabled) ?? true
        keyPopupStyle = try c.decodeIfPresent(KeyPopupStyle.self, forKey: .keyPopupStyle) ?? .balloon
        liquidGlassPopup = try c.decodeIfPresent(Bool.self, forKey: .liquidGlassPopup) ?? true
        homeRowInset = try c.decodeIfPresent(Bool.self, forKey: .homeRowInset) ?? true
        homeRowInsetAmount = try c.decodeIfPresent(Double.self, forKey: .homeRowInsetAmount) ?? 0.05
        keyPressWarp = try c.decodeIfPresent(Bool.self, forKey: .keyPressWarp) ?? true
        keyHeight = try c.decodeIfPresent(Double.self, forKey: .keyHeight) ?? 46
        keyCornerRadius = try c.decodeIfPresent(Double.self, forKey: .keyCornerRadius) ?? 12
        keyWidthFraction = try c.decodeIfPresent(Double.self, forKey: .keyWidthFraction) ?? 1
        keySpacing = try c.decodeIfPresent(Double.self, forKey: .keySpacing) ?? 5
        rowSpacing = try c.decodeIfPresent(Double.self, forKey: .rowSpacing) ?? 7
        suggestionsEnabled = try c.decodeIfPresent(Bool.self, forKey: .suggestionsEnabled) ?? true
        autocorrectEnabled = try c.decodeIfPresent(Bool.self, forKey: .autocorrectEnabled) ?? true
        soundPackID = try c.decodeIfPresent(String.self, forKey: .soundPackID) ?? SoundPack.default.id
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? false
        soundVolume = try c.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.8
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? false
    }

    // MARK: - Resolved convenience accessors

    /// Every selectable theme: built-in presets plus the user's custom ones.
    public var allThemes: [Theme] { Theme.presets + customThemes }

    /// Resolve an id against custom themes first, then the presets, then the
    /// default — so a custom theme renders just like a preset everywhere.
    public func theme(withID id: String) -> Theme {
        customThemes.first { $0.id == id } ?? Theme.preset(id: id)
    }

    /// The theme to render right now, given the current system appearance.
    /// Honours `matchSystemAppearance`; otherwise uses the fixed `themeID`.
    public func resolvedTheme(dark: Bool) -> Theme {
        guard matchSystemAppearance else { return theme(withID: themeID) }
        return theme(withID: dark ? darkThemeID : lightThemeID)
    }

    public var theme: Theme { theme(withID: themeID) }
    public var layout: KeyboardLayout { KeyboardLayout.preset(id: layoutID) }
    public var soundPack: SoundPack { SoundPack.preset(id: soundPackID) }
}
