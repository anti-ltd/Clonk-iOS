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

/// Which way the emoji grid scrolls. Vertical (rows wrap downward, scroll down
/// for more) is the default; horizontal (columns fill top-to-bottom, swipe
/// sideways for more) mirrors the older system emoji keyboard.
public enum EmojiScrollDirection: String, Codable, Sendable, CaseIterable, Identifiable {
    case vertical
    case horizontal

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .vertical:   return "Vertical"
        case .horizontal: return "Horizontal"
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
    /// Global "show background" switch. When on, the active theme's background —
    /// its photo if it has one, otherwise its solid `background` colour — is
    /// painted behind the keys; when off (the default) the keyboard stays
    /// transparent and the keys float. Applies to every theme uniformly.
    public var backgroundVisible: Bool
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
    /// width applied to each side. Defaults to 0.01 (a subtle nudge).
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
    /// Show the clipboard history button in the suggestion bar. Requires Full
    /// Access — without it the pasteboard is not readable from the extension.
    public var clipboardEnabled: Bool
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
    /// How far (in points) a finger must slide across the space bar to move the
    /// text cursor by one character — also the threshold before a press flips
    /// from "tap to type a space" into cursor-trackpad mode. Smaller = more
    /// sensitive (the cursor flies, and a slight wobble can trigger it); larger =
    /// firmer (you must drag deliberately, fewer accidental scrolls). Default 10.
    public var spaceCursorStride: Double
    /// How long (ms) the space bar must be held before cursor-trackpad mode can
    /// engage. 0 = instant (the existing behaviour — movement alone triggers it);
    /// higher values require an intentional hold, reducing accidental activation
    /// when typing fast. Works hand-in-hand with `spaceCursorStride`.
    public var spaceCursorActivationDelay: Double
    // Key press physics
    /// Scale applied to each key when it blooms on press (1.0 = no bloom).
    public var keyBloomScale: Double
    /// Spring response (seconds) for the key press/release bloom — lower = snappier.
    public var keySpringResponse: Double
    /// Spring damping for the key press bloom — lower = bouncier, 1.0 = no oscillation.
    public var keySpringDamping: Double
    // Space bar physics
    /// Spring response (seconds) for the space bar press and cursor-drag animations.
    public var spaceSpringResponse: Double
    /// Spring damping for the space bar.
    public var spaceSpringDamping: Double
    /// How far the space bar leans toward the dragging finger as a multiplier on the
    /// raw horizontal translation. 0 = no lean; 0.14 = default subtle follow.
    public var spaceLeanMultiplier: Double
    /// Scale the space bar shrinks to once cursor-trackpad mode engages.
    /// 1.0 = no shrink; 0.9 = default subtle squeeze.
    public var spaceCursorDragScale: Double
    // Popup physics
    /// Spring response for the key popup emerge animation.
    public var popupSpringResponse: Double
    /// Spring damping for the key popup emerge animation.
    public var popupSpringDamping: Double
    // Backspace auto-repeat timing
    /// How long (ms) to hold backspace before auto-repeat begins.
    public var repeatHoldDelay: Double
    /// Starting interval (ms) between auto-repeat deletions.
    public var repeatInitialInterval: Double
    /// Minimum interval (ms) between repeats at full speed.
    public var repeatMinInterval: Double
    /// How many ms to subtract from the repeat interval each step (acceleration).
    public var repeatAccelStep: Double
    // Emoji
    /// The skin tone applied to any tone-capable emoji that has no per-emoji
    /// choice in `emojiSkinTones`. `.none` = neutral (yellow).
    public var defaultSkinTone: SkinTone
    /// Per-emoji skin-tone choices, keyed by the BASE (neutral) emoji string.
    /// A present entry wins over `defaultSkinTone`; an absent one falls back to
    /// it. Set by long-pressing an emoji and picking a tone.
    public var emojiSkinTones: [String: SkinTone]
    /// Which way the emoji grid scrolls — vertical (default) or horizontal.
    public var emojiScrollDirection: EmojiScrollDirection
    /// Show a "Recently used" tab (the leading clock category) on the emoji
    /// keyboard, populated from `recentEmoji`.
    public var showRecentEmoji: Bool
    /// Recently-inserted emoji, most-recent first, as neutral BASE glyphs (the
    /// per-emoji skin tone is applied at render time, same as every other
    /// category). Capped at `recentEmojiCap`; surfaced as the recents tab when
    /// `showRecentEmoji` is on.
    public var recentEmoji: [String]

    /// How many recents to keep — a few rows' worth, like the system keyboard.
    public static let recentEmojiCap = 36

    public init(
        themeID: String = Theme.default.id,
        matchSystemAppearance: Bool = true,
        lightThemeID: String = Theme.preset(id: "liquid-light").id,
        darkThemeID: String = Theme.preset(id: "liquid-dark").id,
        customThemes: [Theme] = [],
        backgroundVisible: Bool = false,
        layoutID: String = KeyboardLayout.default.id,
        showNumberRow: Bool = false,
        autoCapitalize: Bool = true,
        keyPopupEnabled: Bool = false,
        keyPopupStyle: KeyPopupStyle = .balloon,
        liquidGlassPopup: Bool = true,
        homeRowInset: Bool = true,
        homeRowInsetAmount: Double = 0.01,
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
        clipboardEnabled: Bool = false,
        suggestionsEnabled: Bool = true,
        autocorrectEnabled: Bool = true,
        autoPunctuationEnabled: Bool = true,
        autoReturnToLetters: Bool = true,
        autoSpaceAfterReturn: Bool = true,
        soundPackID: String = SoundPack.default.id,
        soundEnabled: Bool = false,
        soundVolume: Double = 0.8,
        hapticsEnabled: Bool = false,
        hitboxScale: Double = 0.90,
        spaceCursorStride: Double = 10,
        spaceCursorActivationDelay: Double = 0,
        keyBloomScale: Double = 1.12,
        keySpringResponse: Double = 0.26,
        keySpringDamping: Double = 0.60,
        spaceSpringResponse: Double = 0.28,
        spaceSpringDamping: Double = 0.78,
        spaceLeanMultiplier: Double = 0.14,
        spaceCursorDragScale: Double = 0.90,
        popupSpringResponse: Double = 0.32,
        popupSpringDamping: Double = 0.62,
        repeatHoldDelay: Double = 450,
        repeatInitialInterval: Double = 110,
        repeatMinInterval: Double = 40,
        repeatAccelStep: Double = 6,
        defaultSkinTone: SkinTone = .none,
        emojiSkinTones: [String: SkinTone] = [:],
        emojiScrollDirection: EmojiScrollDirection = .vertical,
        showRecentEmoji: Bool = true,
        recentEmoji: [String] = []
    ) {
        self.themeID = themeID
        self.matchSystemAppearance = matchSystemAppearance
        self.lightThemeID = lightThemeID
        self.darkThemeID = darkThemeID
        self.customThemes = customThemes
        self.backgroundVisible = backgroundVisible
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
        self.clipboardEnabled = clipboardEnabled
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
        self.spaceCursorStride = spaceCursorStride
        self.spaceCursorActivationDelay = spaceCursorActivationDelay
        self.keyBloomScale = keyBloomScale
        self.keySpringResponse = keySpringResponse
        self.keySpringDamping = keySpringDamping
        self.spaceSpringResponse = spaceSpringResponse
        self.spaceSpringDamping = spaceSpringDamping
        self.spaceLeanMultiplier = spaceLeanMultiplier
        self.spaceCursorDragScale = spaceCursorDragScale
        self.popupSpringResponse = popupSpringResponse
        self.popupSpringDamping = popupSpringDamping
        self.repeatHoldDelay = repeatHoldDelay
        self.repeatInitialInterval = repeatInitialInterval
        self.repeatMinInterval = repeatMinInterval
        self.repeatAccelStep = repeatAccelStep
        self.defaultSkinTone = defaultSkinTone
        self.emojiSkinTones = emojiSkinTones
        self.emojiScrollDirection = emojiScrollDirection
        self.showRecentEmoji = showRecentEmoji
        self.recentEmoji = recentEmoji
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
        backgroundVisible = try c.decodeIfPresent(Bool.self, forKey: .backgroundVisible) ?? false
        layoutID = try c.decodeIfPresent(String.self, forKey: .layoutID) ?? KeyboardLayout.default.id
        showNumberRow = try c.decodeIfPresent(Bool.self, forKey: .showNumberRow) ?? false
        autoCapitalize = try c.decodeIfPresent(Bool.self, forKey: .autoCapitalize) ?? true
        keyPopupEnabled = try c.decodeIfPresent(Bool.self, forKey: .keyPopupEnabled) ?? true
        // `try?`, not `try`: a legacy persisted value (e.g. the retired "flat")
        // would otherwise throw and fail the whole settings decode. Fall back.
        keyPopupStyle = (try? c.decodeIfPresent(KeyPopupStyle.self, forKey: .keyPopupStyle)) ?? .balloon
        liquidGlassPopup = try c.decodeIfPresent(Bool.self, forKey: .liquidGlassPopup) ?? true
        homeRowInset = try c.decodeIfPresent(Bool.self, forKey: .homeRowInset) ?? true
        homeRowInsetAmount = try c.decodeIfPresent(Double.self, forKey: .homeRowInsetAmount) ?? 0.01
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
        clipboardEnabled = try c.decodeIfPresent(Bool.self, forKey: .clipboardEnabled) ?? false
        suggestionsEnabled = try c.decodeIfPresent(Bool.self, forKey: .suggestionsEnabled) ?? true
        autocorrectEnabled = try c.decodeIfPresent(Bool.self, forKey: .autocorrectEnabled) ?? true
        autoPunctuationEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoPunctuationEnabled) ?? true
        autoReturnToLetters = try c.decodeIfPresent(Bool.self, forKey: .autoReturnToLetters) ?? true
        autoSpaceAfterReturn = try c.decodeIfPresent(Bool.self, forKey: .autoSpaceAfterReturn) ?? true
        soundPackID = try c.decodeIfPresent(String.self, forKey: .soundPackID) ?? SoundPack.default.id
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? false
        soundVolume = try c.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.8
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? false
        hitboxScale = try c.decodeIfPresent(Double.self, forKey: .hitboxScale) ?? 0.90
        spaceCursorStride = try c.decodeIfPresent(Double.self, forKey: .spaceCursorStride) ?? 10
        spaceCursorActivationDelay = try c.decodeIfPresent(Double.self, forKey: .spaceCursorActivationDelay) ?? 0
        keyBloomScale = try c.decodeIfPresent(Double.self, forKey: .keyBloomScale) ?? 1.12
        keySpringResponse = try c.decodeIfPresent(Double.self, forKey: .keySpringResponse) ?? 0.26
        keySpringDamping = try c.decodeIfPresent(Double.self, forKey: .keySpringDamping) ?? 0.60
        spaceSpringResponse = try c.decodeIfPresent(Double.self, forKey: .spaceSpringResponse) ?? 0.28
        spaceSpringDamping = try c.decodeIfPresent(Double.self, forKey: .spaceSpringDamping) ?? 0.78
        spaceLeanMultiplier = try c.decodeIfPresent(Double.self, forKey: .spaceLeanMultiplier) ?? 0.14
        spaceCursorDragScale = try c.decodeIfPresent(Double.self, forKey: .spaceCursorDragScale) ?? 0.90
        popupSpringResponse = try c.decodeIfPresent(Double.self, forKey: .popupSpringResponse) ?? 0.32
        popupSpringDamping = try c.decodeIfPresent(Double.self, forKey: .popupSpringDamping) ?? 0.62
        repeatHoldDelay = try c.decodeIfPresent(Double.self, forKey: .repeatHoldDelay) ?? 450
        repeatInitialInterval = try c.decodeIfPresent(Double.self, forKey: .repeatInitialInterval) ?? 110
        repeatMinInterval = try c.decodeIfPresent(Double.self, forKey: .repeatMinInterval) ?? 40
        repeatAccelStep = try c.decodeIfPresent(Double.self, forKey: .repeatAccelStep) ?? 6
        // `try?`: a future-retired tone case shouldn't fail the whole decode.
        defaultSkinTone = (try? c.decodeIfPresent(SkinTone.self, forKey: .defaultSkinTone)) ?? .none
        emojiSkinTones = (try? c.decodeIfPresent([String: SkinTone].self, forKey: .emojiSkinTones)) ?? [:]
        emojiScrollDirection = (try? c.decodeIfPresent(EmojiScrollDirection.self, forKey: .emojiScrollDirection)) ?? .vertical
        showRecentEmoji = try c.decodeIfPresent(Bool.self, forKey: .showRecentEmoji) ?? true
        recentEmoji = try c.decodeIfPresent([String].self, forKey: .recentEmoji) ?? []
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

    // MARK: - Recent emoji

    /// Record that `base` (a neutral base glyph) was just used: move it to the
    /// front, drop any earlier occurrence, and trim to `recentEmojiCap`.
    public mutating func pushRecentEmoji(_ base: String) {
        recentEmoji.removeAll { $0 == base }
        recentEmoji.insert(base, at: 0)
        if recentEmoji.count > Self.recentEmojiCap {
            recentEmoji.removeLast(recentEmoji.count - Self.recentEmojiCap)
        }
    }
}
