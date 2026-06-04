import Foundation

/// The shape/behaviour of the magnified key popup.
public enum KeyPopupStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    /// A detached rounded bubble floating above the key.
    case floating
    /// A balloon that necks down into the pressed key.
    case balloon

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .floating: return "Floating"
        case .balloon:  return "Balloon"
        }
    }
}

/// The full user-customizable configuration of the Clink keyboard. This is the
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
    /// How long a key stays visually pressed after the finger lifts, in seconds.
    /// A quick tap otherwise flips on→off too fast for the press bloom/colour to
    /// reach full strength (it reads dim); lingering lets it bloom then fade. 0
    /// disables the hold (instant release).
    public var keyPressLinger: Double
    /// Height of a single key row, in points. Drives the keyboard's overall
    /// height; smaller = shorter keys.
    public var keyHeight: Double
    /// Height of the number row, as a fraction of `keyHeight`. 1.0 = same as the
    /// letter rows (the default); lower makes a compact number strip. Only applies
    /// when `showNumberRow` is on.
    public var numberRowHeightScale: Double
    /// Glyph point size for the number-row digits. Defaults to 22 (the letter-key
    /// size). Only applies when `showNumberRow` is on.
    public var numberRowFontSize: Double
    /// Corner radius of each key, in points. Larger = rounder keys.
    public var keyCornerRadius: Double
    /// Fraction of the row's width the keys occupy; the remainder becomes
    /// symmetric side margins. 1.0 = edge-to-edge, lower = narrower keys.
    public var keyWidthFraction: Double
    /// Width of the space bar, as a weight relative to a letter key (which is 1).
    /// The system space bar is ~5 letter-keys wide; lower makes it narrower and
    /// gives the surrounding bottom-row keys more room.
    public var spaceWidth: Double
    /// Width of the shift and delete keys, as a weight relative to a letter key
    /// (which is 1). The system default is ~1.4; wider eats into the letter keys
    /// on their row.
    public var funcKeyWidth: Double
    /// Horizontal gap between keys in a row, in points.
    public var keySpacing: Double
    /// Vertical gap between rows, in points.
    public var rowSpacing: Double
    /// Show the autocomplete / suggestion bar above the keys.
    public var suggestionsEnabled: Bool
    /// Auto-correct the just-typed word when a space / punctuation is entered.
    public var autocorrectEnabled: Bool
    /// Add apostrophes to apostrophe-less contractions (dont → don't, ive → I've)
    /// when a space / punctuation is entered.
    public var autoPunctuationEnabled: Bool
    /// After typing sentence punctuation (. , ? ! ; : ' ") on the numbers/symbols
    /// plane, automatically flip back to the letters plane — so a quick
    /// "123 → , → keep typing" never strands you on the symbols page. Mirrors the
    /// system keyboard's feel; off by preference for those who page-hop manually.
    public var autoReturnToLetters: Bool
    /// When `autoReturnToLetters` flips back to letters after sentence
    /// punctuation, also insert a trailing space — so "123 → . → keep typing"
    /// lands you mid-sentence with the gap already there. No effect when
    /// `autoReturnToLetters` is off.
    public var autoSpaceAfterReturn: Bool
    // Clink sound + feel
    public var soundPackID: String
    public var soundEnabled: Bool
    public var soundVolume: Double      // 0.0 ... 1.0
    public var hapticsEnabled: Bool
    /// Multiplier applied to each key's frame before hit-testing. 1.0 = hitbox
    /// matches the visual key exactly. Values above 1 make the hitbox larger
    /// (more forgiving); values below 1 shrink it (more precise, with wider
    /// dead zones between keys that still route to the nearest key).
    public var hitboxScale: Double
    // Emoji
    /// The skin tone applied to any tone-capable emoji that has no per-emoji
    /// choice in `emojiSkinTones`. `.none` = neutral (yellow).
    public var defaultSkinTone: SkinTone
    /// Per-emoji skin-tone choices, keyed by the BASE (neutral) emoji string.
    /// A present entry wins over `defaultSkinTone`; an absent one falls back to
    /// it. Set by long-pressing an emoji and picking a tone.
    public var emojiSkinTones: [String: SkinTone]

    public init(
        themeID: String = Theme.default.id,
        matchSystemAppearance: Bool = true,
        lightThemeID: String = Theme.preset(id: "liquid-light").id,
        darkThemeID: String = Theme.preset(id: "liquid-dark").id,
        customThemes: [Theme] = [],
        layoutID: String = KeyboardLayout.default.id,
        showNumberRow: Bool = false,
        autoCapitalize: Bool = true,
        keyPopupEnabled: Bool = false,
        keyPopupStyle: KeyPopupStyle = .balloon,
        liquidGlassPopup: Bool = true,
        homeRowInset: Bool = true,
        homeRowInsetAmount: Double = 0.05,
        keyPressWarp: Bool = true,
        keyPressLinger: Double = 0.06,
        keyHeight: Double = 51,
        numberRowHeightScale: Double = 1.0,
        numberRowFontSize: Double = 22,
        keyCornerRadius: Double = 13,
        keyWidthFraction: Double = 1,
        spaceWidth: Double = 7,
        funcKeyWidth: Double = 1.4,
        keySpacing: Double = 1,
        rowSpacing: Double = 4,
        suggestionsEnabled: Bool = true,
        autocorrectEnabled: Bool = true,
        autoPunctuationEnabled: Bool = true,
        autoReturnToLetters: Bool = true,
        autoSpaceAfterReturn: Bool = true,
        soundPackID: String = SoundPack.default.id,
        soundEnabled: Bool = false,
        soundVolume: Double = 0.8,
        hapticsEnabled: Bool = false,
        hitboxScale: Double = 0.85,
        defaultSkinTone: SkinTone = .none,
        emojiSkinTones: [String: SkinTone] = [:]
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
        self.keyPressLinger = keyPressLinger
        self.keyHeight = keyHeight
        self.numberRowHeightScale = numberRowHeightScale
        self.numberRowFontSize = numberRowFontSize
        self.keyCornerRadius = keyCornerRadius
        self.keyWidthFraction = keyWidthFraction
        self.spaceWidth = spaceWidth
        self.funcKeyWidth = funcKeyWidth
        self.keySpacing = keySpacing
        self.rowSpacing = rowSpacing
        self.suggestionsEnabled = suggestionsEnabled
        self.autocorrectEnabled = autocorrectEnabled
        self.autoPunctuationEnabled = autoPunctuationEnabled
        self.autoReturnToLetters = autoReturnToLetters
        self.autoSpaceAfterReturn = autoSpaceAfterReturn
        self.soundPackID = soundPackID
        self.soundEnabled = soundEnabled
        self.soundVolume = soundVolume
        self.hapticsEnabled = hapticsEnabled
        self.hitboxScale = hitboxScale
        self.defaultSkinTone = defaultSkinTone
        self.emojiSkinTones = emojiSkinTones
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
        // `try?`, not `try`: a legacy persisted value (e.g. the retired "flat")
        // would otherwise throw and fail the whole settings decode. Fall back.
        keyPopupStyle = (try? c.decodeIfPresent(KeyPopupStyle.self, forKey: .keyPopupStyle)) ?? .balloon
        liquidGlassPopup = try c.decodeIfPresent(Bool.self, forKey: .liquidGlassPopup) ?? true
        homeRowInset = try c.decodeIfPresent(Bool.self, forKey: .homeRowInset) ?? true
        homeRowInsetAmount = try c.decodeIfPresent(Double.self, forKey: .homeRowInsetAmount) ?? 0.05
        keyPressWarp = try c.decodeIfPresent(Bool.self, forKey: .keyPressWarp) ?? true
        keyPressLinger = try c.decodeIfPresent(Double.self, forKey: .keyPressLinger) ?? 0.06
        keyHeight = try c.decodeIfPresent(Double.self, forKey: .keyHeight) ?? 46
        numberRowHeightScale = try c.decodeIfPresent(Double.self, forKey: .numberRowHeightScale) ?? 1.0
        numberRowFontSize = try c.decodeIfPresent(Double.self, forKey: .numberRowFontSize) ?? 22
        keyCornerRadius = try c.decodeIfPresent(Double.self, forKey: .keyCornerRadius) ?? 12
        keyWidthFraction = try c.decodeIfPresent(Double.self, forKey: .keyWidthFraction) ?? 1
        spaceWidth = try c.decodeIfPresent(Double.self, forKey: .spaceWidth) ?? 5
        funcKeyWidth = try c.decodeIfPresent(Double.self, forKey: .funcKeyWidth) ?? 1.4
        keySpacing = try c.decodeIfPresent(Double.self, forKey: .keySpacing) ?? 5
        rowSpacing = try c.decodeIfPresent(Double.self, forKey: .rowSpacing) ?? 7
        suggestionsEnabled = try c.decodeIfPresent(Bool.self, forKey: .suggestionsEnabled) ?? true
        autocorrectEnabled = try c.decodeIfPresent(Bool.self, forKey: .autocorrectEnabled) ?? true
        autoPunctuationEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoPunctuationEnabled) ?? true
        autoReturnToLetters = try c.decodeIfPresent(Bool.self, forKey: .autoReturnToLetters) ?? true
        autoSpaceAfterReturn = try c.decodeIfPresent(Bool.self, forKey: .autoSpaceAfterReturn) ?? true
        soundPackID = try c.decodeIfPresent(String.self, forKey: .soundPackID) ?? SoundPack.default.id
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? false
        soundVolume = try c.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.8
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? false
        hitboxScale = try c.decodeIfPresent(Double.self, forKey: .hitboxScale) ?? 0.85
        // `try?`: a future-retired tone case shouldn't fail the whole decode.
        defaultSkinTone = (try? c.decodeIfPresent(SkinTone.self, forKey: .defaultSkinTone)) ?? .none
        emojiSkinTones = (try? c.decodeIfPresent([String: SkinTone].self, forKey: .emojiSkinTones)) ?? [:]
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

    // MARK: - Emoji skin tones

    /// The skin tone to use for `base`: its per-emoji choice if set, else the
    /// global default.
    public func skinTone(for base: String) -> SkinTone {
        emojiSkinTones[base] ?? defaultSkinTone
    }

    /// The glyph to render/insert for the base emoji `base`, with the resolved
    /// skin tone applied. Tone-incapable emoji are returned unchanged.
    public func displayEmoji(for base: String) -> String {
        guard EmojiSkinTone.supportsSkinTone(base) else { return base }
        return EmojiSkinTone.applied(skinTone(for: base), to: base)
    }

    /// Record (or clear) a per-emoji skin-tone choice. `.none` is stored
    /// explicitly so it can pin an emoji to neutral even when the global
    /// default is a tone.
    public mutating func setSkinTone(_ tone: SkinTone, for base: String) {
        emojiSkinTones[base] = tone
    }
}
