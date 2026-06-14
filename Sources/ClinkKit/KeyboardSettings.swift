/**
 All user-configurable keyboard settings in one `Codable` struct. Shared between
 the container app (writes) and the keyboard extension (reads) via the App Group.
 Also defines the settings enums: `KeyPopupStyle`, `ClipboardStyle`,
 `NotepadMode`, `PanelPickerStyle`, `EmojiScrollDirection`, `CursorMovementType`.
 

 Module: settings · Target: ClinkKit
 Learn: docs/01-settings-and-storage.md
 */
import Foundation

// MARK: - Settings enums

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

/// How clipboard history is presented in the keyboard.
public enum ClipboardStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Replaces the suggestion bar with a horizontal scroll of chips.
    case bar
    /// Pops an overlay panel over the keys — swipeable cards with text + timestamps.
    case overlay
    /// Full-keyboard overlay laying entries out as a two-column grid of tappable
    /// cards (long-press for copy / pin / delete).
    case grid

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .bar:     return "Bar"
        case .overlay: return "Panel"
        case .grid:    return "Grid"
        }
    }
}

/// What the quick notepad holds. `scratchpad` is a single persistent buffer you
/// jot into and pull from; `notes` keeps that same compose buffer but adds a
/// saved-notes archive you can store snippets into and re-insert later.
public enum NotepadMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case scratchpad
    case notes

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .scratchpad: return "Scratchpad"
        case .notes:      return "Notes"
        }
    }
}

/// How the Translate panel presents itself. `inline` composes on the suggestion
/// bar with the keys still visible (type to translate), surfacing the result as a
/// brief overlay. `panel` takes over the whole keyboard — like the trackpad —
/// with the source, language, translate action, and result all in one reachable
/// surface (input via paste, since the keys are hidden).
public enum TranslateStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case inline
    case panel

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .inline: return "Inline"
        case .panel:  return "Panel"
        }
    }
}

/// The geometric character of a key's press animation (applies when the bloom
/// is on — i.e. `keyBloomScale` > 1). All are a single `scaleEffect` per key —
/// same cost as the classic bloom, so the press stays frame-cheap on every
/// device and material.
public enum KeyPressStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Classic: the key grows uniformly on press.
    case bloom
    /// Press-in: the key shrinks slightly, like a physical key going down.
    case sink
    /// Squash wide-and-short — a playful jelly wobble.
    case jelly
    /// Stretch tall-and-narrow.
    case stretch

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .bloom:   return "Bloom"
        case .sink:    return "Press-in"
        case .jelly:   return "Jelly"
        case .stretch: return "Stretch"
        }
    }
}

/// A one-shot animation the whole key block plays each time the keyboard appears.
/// Driven by a single explicit `@State` progress (0→1) keyed to the appearance
/// counter — not a per-frame animator — so it's a one-time transition with no
/// steady-state cost. Reduced Motion collapses it to an instant settle.
public enum KeyboardEntrance: String, Codable, Sendable, CaseIterable, Identifiable {
    case none
    /// Fade the keys in.
    case fade
    /// Rise up into place while fading in.
    case rise
    /// Scale up from slightly small while fading in.
    case scale
    /// Drop down from above while fading in.
    case drop

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .none:  return "None"
        case .fade:  return "Fade"
        case .rise:  return "Rise"
        case .scale: return "Scale"
        case .drop:  return "Drop"
        }
    }
}

/// How the top-left button offers a choice when more than one action panel is
/// enabled. `popover` floats a small menu above the button; `inline` expands the
/// button into a row of panel icons across the bar; `cards` takes over the whole
/// keyboard with a tappable card per panel (like the clipboard history cards).
public enum PanelPickerStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case popover
    case inline
    /// Like `inline` but shows SF Symbol icons instead of text labels.
    case inlineIcons
    case cards

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .popover:      return "Popover"
        case .inline:       return "Inline"
        case .inlineIcons:  return "Inline Icons"
        case .cards:        return "Cards"
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

/// How the text cursor is moved from the keyboard. `spacebar` is the default —
/// slide along the space bar to nudge the cursor by characters. `trackpad` turns
/// the whole keyboard into a 2-D trackpad while the space bar is held: drag
/// anywhere to move the cursor (left/right by characters, up/down by lines),
/// release to return to the keys — mirroring the system keyboard's trackpad.
public enum CursorMovementType: String, Codable, Sendable, CaseIterable, Identifiable {
    case spacebar
    case trackpad
    /// A normal keyboard that, while the space bar is held into a cursor drag,
    /// blanks the key letters and makes the keys inert (the space bar morphs as
    /// you move). Unlike `trackpad` it never hides the keyboard — the keys stay
    /// visible, just letter-less, until you lift.
    case combined

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .spacebar: return "Spacebar"
        case .trackpad: return "Trackpad"
        case .combined: return "Combined"
        }
    }
}

/// Tactile character of the key-press haptic. Maps to `UIImpactFeedbackGenerator`
/// feedback styles (the UIKit mapping lives in `SoundPlayer`, keeping this type
/// UIKit-free so it can cross the App Group). `light` is the default subtle tap;
/// `rigid`/`heavy` read punchier and more mechanical — the "beast" end.
public enum HapticStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case light, medium, heavy, rigid, soft

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .light:  return "Light"
        case .medium: return "Medium"
        case .heavy:  return "Heavy"
        case .rigid:  return "Rigid"
        case .soft:   return "Soft"
        }
    }
}

// MARK: - KeyboardSettings

/// The full user-customizable configuration of the Clink keyboard. This is the
/// single value that crosses the process boundary between the container app
/// (which edits it) and the keyboard extension (which renders from it), via the
/// App Group store. Keep it small and `Codable`.
public struct KeyboardSettings: Codable, Equatable, Sendable {

    // MARK: - Appearance
    /// Theme used when NOT matching the system appearance.
    public var themeID: String
    /// App-only UI preference: when false (Simple mode), the settings screens
    /// hide every "Fine-tune" advanced block; when true (Advanced mode) they're
    /// shown. The toggle lives at the top of Home. The keyboard extension ignores
    /// this — it only affects which controls the app surfaces.
    public var advancedSettings: Bool
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
    /// When true (default), the app's settings UI adopts the keyboard's active
    /// theme. When false, the app uses Liquid Light / Liquid Dark regardless of
    /// which keyboard theme the user has selected.
    public var themeApp: Bool

    // MARK: - Layout & custom keys

    /// Physical key layout preset (QWERTY, AZERTY, etc.) — independent of
    /// `keyboardLanguages`, which drives prediction/spelling only.
    public var layoutID: String
    /// User-defined keys placed to the left of the space bar in the bottom row
    /// (the Gboard quick-comma layout). Empty by default. Letters plane only.
    public var spaceBarLeadingKeys: [CustomKey]
    /// User-defined keys placed to the right of the space bar, before the return
    /// key (the Gboard quick-period layout). Empty by default. Letters plane only.
    public var spaceBarTrailingKeys: [CustomKey]
    /// Whole rows of user-defined keys, placed above or below the letter rows on
    /// the letters plane. Empty by default.
    public var customRows: [CustomRow]

    // MARK: - Prediction & languages

    /// The languages the suggestion bar, autocomplete, and auto-correction run in,
    /// as `UITextChecker` identifiers (e.g. "en_US", "fr_FR"). More than one means
    /// simultaneous bilingual typing: completions/predictions are merged and a word
    /// is only auto-corrected when it's wrong in *every* active language. Always
    /// holds at least one entry. Drives the completion/spelling dictionary;
    /// independent of the physical key `layoutID`. Unsupported entries fall back to
    /// "en_US" inside the engine.
    public var keyboardLanguages: [String]
    /// The first active language — the one used wherever a single language is still
    /// meaningful (e.g. a default layout suggestion). Never empty.
    public var primaryLanguage: String { keyboardLanguages.first ?? "en_US" }
    /// Holding a letter key reveals a bar of accent/diacritic variants (hold "e"
    /// → è é ê ë …), slide-to-pick like the system keyboard. Optional; off leaves
    /// letter keys with no long-press behaviour.
    public var accentPopupsEnabled: Bool
    /// Show a small corner glyph on keys that have long-press variants, previewing the first alternate.
    public var longPressHintsEnabled: Bool

    // MARK: - Key appearance & geometry

    /// Persistent number row above the letter keys (letters plane only).
    public var showNumberRow: Bool
    /// Auto-shift to caps at sentence start and after sentence-ending punctuation.
    public var autoCapitalize: Bool
    /// Magnified popup above the pressed key while held.
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
    /// How long a key stays visually pressed after the finger lifts, in seconds.
    /// A quick tap otherwise flips on→off too fast for the press bloom/colour to
    /// reach full strength (it reads dim); lingering lets it bloom then fade. 0
    /// disables the hold (instant release).
    public var keyPressLinger: Double
    /// Minimum time a key reads pressed after touch-down, in seconds, no matter how
    /// fast it's released or cancelled. Screen-edge taps in the extension are
    /// deferred by iOS's edge system-gestures then delivered as a near-instant
    /// down+up, collapsing the press to a sub-frame flicker — the letter types but
    /// the key never visibly highlights. This floor keeps an edge tap lit long
    /// enough to bloom like a held centre tap. 0 disables the floor.
    public var minPressVisible: Double
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
    /// Extra space above the key block — between the suggestion bar and the keys
    /// (or the top of the keyboard when the bar is hidden). Gives breathing room,
    /// e.g. to show more of a background image. Points. Not gap-between-keys.
    public var keyboardTopPadding: Double
    /// Extra space below the key block — between the keys and the bottom of the
    /// keyboard, lifting the whole keyboard upward. Points.
    public var keyboardBottomPadding: Double

    // MARK: - Clipboard

    /// Show the clipboard history button in the suggestion bar. Requires Full
    /// Access — without it the pasteboard is not readable from the extension.
    public var clipboardEnabled: Bool
    /// How clipboard history is presented when the toggle is tapped.
    public var clipboardStyle: ClipboardStyle
    /// Dismiss the clipboard history panel automatically after a clip is pasted.
    /// Off by default — lets the user paste multiple clips in one session.
    public var clipboardCloseOnPaste: Bool
    /// Remove a pasted clip from history after inserting it. Pinned entries are
    /// never deleted by this — only unpinned clips are consumed on paste.
    public var clipboardDeleteOnPaste: Bool
    /// When clearing clipboard history, also delete pinned entries. On by default —
    /// pins are treated as preference markers, not permanent locks.
    public var clipboardIgnorePinsOnDelete: Bool
    /// Automatically capture the current pasteboard when the keyboard finishes
    /// its opening animation. Requires Full Access. Off by default.
    public var autoCopyOnKeyboardOpen: Bool
    /// Automatically capture the current pasteboard when the clipboard history
    /// panel is opened. Requires Full Access. Off by default.
    public var autoCopyOnClipboardOpen: Bool

    // MARK: - Panels & extensions

    /// Show the quick-notepad action panel behind the top-left button. Unlike
    /// clipboard it needs no Full Access (it never reads the pasteboard).
    public var notepadEnabled: Bool
    /// Show the Translate action panel behind the top-left button. Translates the
    /// typed/pasted text into a chosen language — offline via Apple's
    /// `Translation` framework by default, or via Apple Intelligence when
    /// `aiEnabled && aiTranslate`. Needs no Full Access (it never reads the
    /// pasteboard unless the user taps Paste).
    public var translateEnabled: Bool
    /// How the Translate panel presents — inline (compose on the bar) or a
    /// full-keyboard panel takeover. See `TranslateStyle`.
    public var translateStyle: TranslateStyle
    /// Whether the notepad is a single scratchpad or a scratchpad + saved-notes
    /// archive.
    public var notepadMode: NotepadMode
    /// Show the emoji keyboard as an action panel (reachable from the panel
    /// button / slide-up like clipboard and notepad). On by default — turning it
    /// off removes emoji access entirely.
    public var emojiEnabled: Bool
    /// Surface emoji from a dedicated key next to the 123 key instead of the
    /// panel picker. When on, emoji is removed from the picker list and a 🙂 key
    /// appears beside 123 / ABC in the bottom row. No effect when `emojiEnabled`
    /// is off.
    public var emojiKeyInRow: Bool
    /// Show the calculator as an action panel — evaluate arithmetic and insert
    /// the result directly into the host document.
    public var calculatorEnabled: Bool
    /// Show the user's custom actions (the Python extension SDK) as an action
    /// panel. The panel lists every enabled `ClinkExtension`; appended after the
    /// built-in panels rather than living in `extensionOrder`.
    public var userExtensionsEnabled: Bool
    /// Show the user's custom panels (full custom UIs) as an action panel.
    /// Appended after the built-in panels, like `userExtensionsEnabled`.
    public var customPanelsEnabled: Bool
    /// Global default for whether custom panels appear as their own top-level
    /// picker entries (alongside Clipboard / Notepad / …) rather than grouped
    /// behind one "Panels" button. Individual panels can override via
    /// `ClinkPanel.placement`.
    public var customPanelsStandalone: Bool
    /// Reach the action panels from the top-left button on the suggestion bar.
    public var activateWithIcon: Bool
    /// Reach the action panels by dragging the 123 key upward (the gesture emoji
    /// used to own). Independent of `activateWithIcon` — both can be on.
    public var activateWithSlideUp: Bool
    /// When true, expand the inline panel icons automatically each time the
    /// keyboard appears, collapsing when the user starts typing.
    public var autoShowPanelIcons: Bool
    /// Animate the keyboard's height change when the on-open icon bar grows in /
    /// collapses on typing. Off snaps instantly — the resize lands in one frame
    /// so it reads as "nothing moved" rather than a sweep. On by default.
    public var animatePanelBarResize: Bool
    /// Keep the panel-icons row permanently in the bar. Only applies when the
    /// suggestion bar is off (the icons take the bar's place) and at least one
    /// panel is enabled. Unlike `autoShowPanelIcons` it never collapses on typing,
    /// so the bar height is reserved up front — no grow/shrink, no transition.
    public var pinPanelIcons: Bool
    /// How the top-left icon offers a panel choice when 2+ panels are enabled.
    public var iconPickerStyle: PanelPickerStyle
    /// How the slide-up on the 123 key offers a panel choice when 2+ panels are enabled.
    public var slideUpPickerStyle: PanelPickerStyle
    /// User-chosen display order for extension panels. Stored as lowercase
    /// destination IDs ("calculator", "clipboard", "emoji", "notepad", "translate").
    public var extensionOrder: [String]

    // MARK: - Suggestions & autocorrect

    /// Show the autocomplete / suggestion bar above the keys.
    public var suggestionsEnabled: Bool
    /// Auto-correct the just-typed word when a space / punctuation is entered.
    public var autocorrectEnabled: Bool
    /// Pressing delete right after an auto-correction undoes it, restoring the
    /// word you actually typed (e.g. "Dawg" after it was corrected to "Done").
    public var revertAutocorrectOnDelete: Bool
    /// Opt-in, on-device learning: remember words you type repeatedly, boost
    /// words you accept from the bar, and stop re-applying corrections you
    /// reject. Stored locally (App Group file), never leaves the device, and
    /// can be wiped from the app's settings. Off by default.
    public var learningEnabled: Bool
    /// Master switch for on-device Apple Intelligence features (iOS 26+ on
    /// Apple Intelligence-capable hardware). Fully offline — inference runs in
    /// a system process and nothing ever leaves the device. Future AI features
    /// (predictive typing, translation, suggestions) all gate on this.
    /// Off by default.
    public var aiEnabled: Bool
    /// AI-assisted suggestion bar. When on (and `aiEnabled`), the on-device
    /// model refines the bar's candidates for higher-quality, more context-aware
    /// suggestions. Strictly additive: the fast offline engine still produces the
    /// bar instantly; any AI pass runs async off the keystroke path and only
    /// upgrades results once ready — it never blocks or delays a keypress.
    /// On by default, but inert unless `aiEnabled`.
    public var aiSuggestions: Bool
    /// AI-assisted auto-correction. When on (and `aiEnabled`), the model helps
    /// resolve ambiguous corrections the deterministic scorer is unsure about.
    /// The existing fast autocorrect path is unchanged and authoritative for the
    /// common case; AI only weighs in async on low-confidence cases, never
    /// gating the keystroke. On by default, but inert unless `aiEnabled`.
    public var aiAutocorrect: Bool
    /// AI-assisted prediction — next-word prediction in the bar and smarter
    /// adaptive-hitbox biasing. When on (and `aiEnabled`), the model sharpens
    /// what the keyboard expects next. Runs entirely async and only feeds hints
    /// into the existing predictors; the per-keystroke hitbox/prediction math
    /// stays as fast as today with no AI in its hot path. On by default, but
    /// inert unless `aiEnabled`.
    public var aiPrediction: Bool
    /// Use Apple Intelligence for translation instead of the default offline
    /// `Translation` framework. Translation always works offline without AI (the
    /// system framework, wider device support); when on (and `aiEnabled`), the
    /// on-device model handles it instead for higher-quality, more idiomatic
    /// output on capable hardware. On by default, but inert unless `aiEnabled` —
    /// with it off, translation silently falls back to the offline framework.
    public var aiTranslate: Bool
    /// How long (ms) after the last keystroke before the suggestion engine runs.
    /// Higher = fewer UITextChecker invocations during fast bursts (saves CPU/battery);
    /// lower = snappier bar updates. Default 80ms matches the historical hardcoded value.
    public var suggestionDebounceDelay: Double
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

    // MARK: - Swipe typing

    /// Glide/swipe typing: trace a continuous path across the letter keys and the
    /// gesture is decoded into a word on lift (the first letter is typed instantly
    /// on touch-down as usual, then replaced by the decoded word once the trace is
    /// recognised). Tapping keys still types normally — only a deliberate slide
    /// across keys engages the swipe path. Off by default.
    public var swipeTypingEnabled: Bool
    /// Draw the live finger trail while swiping. Purely visual; no effect on the
    /// decode. Only meaningful when `swipeTypingEnabled`.
    public var swipeShowTrail: Bool
    /// Stroke width (pt) of the swipe trail.
    public var swipeTrailWidth: Double
    /// On liquid-glass themes, swell each key as the swiping finger passes over it
    /// — the glass flows under the trace like a travelling ripple. Glass-only;
    /// ignored on solid themes. On by default.
    public var swipeKeyMorph: Bool
    /// Peak extra scale a key reaches when the swipe finger is dead-centre on it
    /// (0 = no swell). Only meaningful with `swipeKeyMorph`.
    public var swipeMorphStrength: Double
    /// How far past a key's own size the ripple reaches, as a multiple of the key
    /// size — higher swells more neighbours at once (a wider wave). Only meaningful
    /// with `swipeKeyMorph`.
    public var swipeMorphRadius: Double

    // MARK: - Sound & haptics

    public var soundPackID: String
    public var soundEnabled: Bool
    /// Key-press sample volume, 0…1.
    public var soundVolume: Double
    public var hapticsEnabled: Bool
    /// Tactile character of the key-press haptic (light → rigid). Picks the
    /// `UIImpactFeedbackGenerator` style. Only fires when `hapticsEnabled` and
    /// Full Access are on.
    public var hapticStyle: HapticStyle
    /// Strength of each key-press haptic, 0...1. Lower is a faint tick, 1.0 is a
    /// firm thwack. Passed straight to `impactOccurred(intensity:)`.
    public var hapticIntensity: Double

    // MARK: - Hitboxes & adaptive

    /// Debug overlay drawing each key's effective hit region (dev tuning aid).
    public var showHitboxOverlay: Bool
    /// Multiplier applied to each key's frame before hit-testing. 1.0 = hitbox
    /// matches the visual key exactly. Values above 1 make the hitbox larger
    /// (more forgiving); values below 1 shrink it (more precise, with wider
    /// dead zones between keys that still route to the nearest key).
    public var hitboxScale: Double
    /// Multiplier applied to the suggestion-bar chips' tap height before
    /// hit-testing — mirrors `hitboxScale` for the keys. Only takes effect while
    /// the suggestion bar is shown (`suggestionsEnabled`). 1.0 = matches the bar
    /// exactly; >1 makes the chips taller to hit; <1 shrinks them.
    public var suggestionHitboxScale: Double
    /// Extra space above the suggestion bar — between the bar's top edge and the
    /// keyboard's top. Points. Default 0.
    public var suggestionTopPadding: Double
    /// Multiplier applied to the top-left panel button's tap height before
    /// hit-testing. Only takes effect while icon activation is on
    /// (`activateWithIcon` with at least one panel enabled).
    public var panelButtonHitboxScale: Double
    /// Adaptive hitboxes: predict the next letter from what was just typed and
    /// quietly grow the likely keys' touch targets (shrinking the unlikely ones)
    /// without moving the visible keys — mirrors iOS's native behaviour. The
    /// visual keys never move; only the hit regions flex (see `AdaptiveHitbox`).
    public var adaptiveHitboxes: Bool
    /// Adaptive: how large a *likely* next letter's hit region may grow (1.0 = no
    /// growth). Higher = the keyboard leans harder toward the predicted key.
    public var adaptiveGrow: Double
    /// Adaptive: how small an *unlikely* next letter's hit region may shrink to
    /// (1.0 = no shrink). Lower = unlikely keys give up more of their gap.
    public var adaptiveShrink: Double
    /// Adaptive: prediction strength (0...1). 0 = size by base letter frequency
    /// only (ignore what you just typed); 1 = size purely by the bigram context.
    public var adaptivePredictionWeight: Double
    /// Adaptive: also flex the keys at the start of a word (before any letter is
    /// typed), biasing toward common opening letters. Off = keys stay neutral
    /// until there's a previous letter to predict from.
    public var adaptivePredictAtWordStart: Bool

    // MARK: - Cursor movement

    /// How far (in points) a finger must slide across the space bar to move the
    /// text cursor by one character — also the threshold before a press flips
    /// from "tap to type a space" into cursor-trackpad mode. Smaller = more
    /// sensitive (the cursor flies, and a slight wobble can trigger it); larger =
    /// firmer (you must drag deliberately, fewer accidental scrolls). Default 16
    /// (the "Deliberate" feel preset).
    public var spaceCursorStride: Double
    /// How long (ms) the space bar must be held before cursor-trackpad mode can
    /// engage. 0 = instant (movement alone triggers it); higher values require an
    /// intentional hold, reducing accidental activation when typing fast. Works
    /// hand-in-hand with `spaceCursorStride`. Default 150 (the "Deliberate" feel
    /// preset).
    public var spaceCursorActivationDelay: Double
    /// How the cursor is moved: slide on the space bar (`spacebar`, default) or
    /// hold the space bar to open a full-keyboard 2-D trackpad (`trackpad`).
    public var cursorMovementType: CursorMovementType
    /// Characters the cursor jumps per vertical "line" step when dragging up/down.
    /// The text API only moves the cursor by character offset, so a line is an
    /// estimate — raise it for long lines, lower it for short ones. Applies to
    /// both the space-bar slide and the trackpad. Default 30.
    public var cursorLineStride: Double

    // MARK: - Key press physics
    /// Scale applied to each key when it blooms on press (1.0 = no bloom).
    public var keyBloomScale: Double
    /// Spring response (seconds) for the key press/release bloom — lower = snappier.
    public var keySpringResponse: Double
    /// Spring damping for the key press bloom — lower = bouncier, 1.0 = no oscillation.
    public var keySpringDamping: Double
    /// Drop the press spring entirely — the key snaps to its bloom/colour with no
    /// animation, mirroring the stock keyboard's instant highlight. Zero latency
    /// on the visual press at the cost of the liquid ease. Overrides the spring
    /// speed/damping when on.
    public var keyPressInstant: Bool
    /// The geometric character of the key press warp (bloom / press-in / jelly /
    /// stretch). Same single-`scaleEffect` cost regardless of choice. Applies when
    /// the bloom is on (`keyBloomScale` > 1).
    public var keyPressStyle: KeyPressStyle
    /// Soft accent-coloured glow behind a key while it's pressed (0 = off). A
    /// blurred tinted halo on the few currently-pressed keys; gated on the motion
    /// profile's expensive-effects tier so it drops under power/thermal pressure.
    public var keyPressGlow: Double
    /// A one-shot animation the key block plays when the keyboard appears (none /
    /// fade / rise / scale / drop). A single explicit transition, no steady-state
    /// cost; collapses to instant under Reduce Motion.
    public var keyboardEntrance: KeyboardEntrance

    // MARK: - Space bar physics
    /// Scale the space bar blooms to on press (its own knob — letters use
    /// `keyBloomScale`). 1.0 = no bloom; the space bar historically used a dead
    /// 1.04 so it felt flatter than the letter keys.
    public var spaceBloomScale: Double
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

    // MARK: - Popup physics
    /// Spring response for the key popup emerge animation.
    public var popupSpringResponse: Double
    /// Spring damping for the key popup emerge animation.
    public var popupSpringDamping: Double

    // MARK: - Liquid Glass press
    /// On Liquid Glass themes, the spring response (seconds) for a key RETURNING
    /// to rest. Lower = a quicker snap = fewer frames of the expensive glass
    /// merge = less chance of an on-release hitch. The press *rise* still uses
    /// `keySpringResponse`. Glass themes only.
    public var glassReleaseResponse: Double

    // MARK: - Backspace auto-repeat
    /// How long (ms) to hold backspace before auto-repeat begins.
    public var repeatHoldDelay: Double
    /// Starting interval (ms) between auto-repeat deletions.
    public var repeatInitialInterval: Double
    /// Minimum interval (ms) between repeats at full speed.
    public var repeatMinInterval: Double
    /// How many ms to subtract from the repeat interval each step (acceleration).
    public var repeatAccelStep: Double
    /// Swipe left on the backspace key to delete a whole word at a time (keep
    /// dragging for more). On by default; tapping/holding backspace is unchanged.
    public var swipeToDeleteWord: Bool
    /// Leftward travel (pt) on backspace before the swipe-to-delete-word gesture
    /// engages. Lower = more sensitive. Only meaningful when `swipeToDeleteWord`.
    public var deleteWordSwipeEngage: Double
    /// Travel (pt) per additional word once the backspace swipe has engaged.
    /// Lower deletes words faster as you keep dragging. Only meaningful when
    /// `swipeToDeleteWord`.
    public var deleteWordSwipeStride: Double

    // MARK: - Gesture thresholds
    /// How long (ms) a letter key must be held still before its accent/diacritic
    /// bar appears. Lower = accents pop sooner; higher = fewer accidental popups
    /// while typing fast. Only applies when `accentPopupsEnabled` is on.
    public var accentHoldDelay: Double
    /// How far (pt) the finger may drift during an accent hold before the pending
    /// popup is cancelled (read as a swipe, not a steady press). Higher = more
    /// forgiving of a shaky hold; lower = the slightest move cancels.
    public var accentMoveCancel: Double
    /// How long (ms) an emoji must be held before its skin-tone picker appears —
    /// mirrors `accentHoldDelay` for the emoji grid.
    public var emojiToneHoldDelay: Double
    /// How far (pt) the 123 key must be dragged upward to open the action-panel
    /// picker (the slide-up gesture). Lower = the panel opens with a short flick;
    /// higher = a longer, deliberate drag. Only applies when `activateWithSlideUp`.
    public var dragUpThreshold: Double

    // MARK: - Emoji
    /// The skin tone applied to any tone-capable emoji that has no per-emoji
    /// choice in `emojiSkinTones`. `.none` = neutral (yellow).
    public var defaultSkinTone: SkinTone
    /// Per-emoji skin-tone choices, keyed by the BASE (neutral) emoji string.
    /// A present entry wins over `defaultSkinTone`; an absent one falls back to
    /// it. Set by long-pressing an emoji and picking a tone.
    public var emojiSkinTones: [String: SkinTone]
    /// Which way the emoji grid scrolls — vertical (default) or horizontal.
    public var emojiScrollDirection: EmojiScrollDirection
    /// Number of columns in the emoji grid when `emojiScrollDirection` is `.vertical`.
    public var emojiColumnCount: Int
    /// Number of rows in the emoji grid when `emojiScrollDirection` is `.horizontal`.
    public var emojiRowCount: Int
    /// Gap (points) between emoji cells, both axes. Default 4.
    public var emojiCellSpacing: CGFloat
    /// Emoji glyph size as a fraction of its cell square (0.4–0.85). Default 0.62.
    public var emojiGlyphScale: Double
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
        themeID: String = Theme.preset(id: "liquid-light").id,
        advancedSettings: Bool = false,
        matchSystemAppearance: Bool = true,
        lightThemeID: String = Theme.preset(id: "liquid-light").id,
        darkThemeID: String = Theme.preset(id: "liquid-dark").id,
        customThemes: [Theme] = [],
        backgroundVisible: Bool = false,
        themeApp: Bool = true,
        layoutID: String = KeyboardLayout.default.id,
        spaceBarLeadingKeys: [CustomKey] = [],
        spaceBarTrailingKeys: [CustomKey] = [],
        customRows: [CustomRow] = [],
        keyboardLanguages: [String] = ["en_US"],
        accentPopupsEnabled: Bool = true,
        longPressHintsEnabled: Bool = false,
        showNumberRow: Bool = false,
        autoCapitalize: Bool = true,
        keyPopupEnabled: Bool = false,
        keyPopupStyle: KeyPopupStyle = .balloon,
        liquidGlassPopup: Bool = true,
        homeRowInset: Bool = true,
        homeRowInsetAmount: Double = 0.01,
        keyPressLinger: Double = 0.0,
        minPressVisible: Double = 0.09,
        keyHeight: Double = 51,
        numberRowHeightScale: Double = 1.0,
        numberRowFontSize: Double = 22,
        keyCornerRadius: Double = 13,
        keyWidthFraction: Double = 1,
        spaceWidth: Double = 7,
        funcKeyWidth: Double = 1.4,
        keySpacing: Double = 1,
        rowSpacing: Double = 4,
        keyboardTopPadding: Double = 0,
        keyboardBottomPadding: Double = 0,
        clipboardEnabled: Bool = false,
        clipboardStyle: ClipboardStyle = .bar,
        clipboardCloseOnPaste: Bool = false,
        clipboardDeleteOnPaste: Bool = false,
        clipboardIgnorePinsOnDelete: Bool = false,
        autoCopyOnKeyboardOpen: Bool = false,
        autoCopyOnClipboardOpen: Bool = false,
        notepadEnabled: Bool = false,
        translateEnabled: Bool = false,
        translateStyle: TranslateStyle = .inline,
        notepadMode: NotepadMode = .scratchpad,
        emojiEnabled: Bool = true,
        emojiKeyInRow: Bool = false,
        calculatorEnabled: Bool = false,
        userExtensionsEnabled: Bool = true,
        customPanelsEnabled: Bool = true,
        customPanelsStandalone: Bool = false,
        activateWithIcon: Bool = true,
        activateWithSlideUp: Bool = true,
        autoShowPanelIcons: Bool = false,
        animatePanelBarResize: Bool = true,
        pinPanelIcons: Bool = false,
        iconPickerStyle: PanelPickerStyle = .popover,
        slideUpPickerStyle: PanelPickerStyle = .popover,
        extensionOrder: [String] = ["calculator", "clipboard", "emoji", "notepad", "translate"],
        suggestionsEnabled: Bool = true,
        autocorrectEnabled: Bool = true,
        revertAutocorrectOnDelete: Bool = true,
        learningEnabled: Bool = false,
        aiEnabled: Bool = false,
        aiSuggestions: Bool = true,
        aiAutocorrect: Bool = true,
        aiPrediction: Bool = true,
        aiTranslate: Bool = true,
        suggestionDebounceDelay: Double = 80.0,
        autoPunctuationEnabled: Bool = true,
        autoReturnToLetters: Bool = true,
        autoSpaceAfterReturn: Bool = true,
        swipeTypingEnabled: Bool = false,
        swipeShowTrail: Bool = true,
        swipeTrailWidth: Double = 4,
        swipeKeyMorph: Bool = true,
        swipeMorphStrength: Double = 0.20,
        swipeMorphRadius: Double = 1.3,
        soundPackID: String = SoundPack.default.id,
        soundEnabled: Bool = false,
        soundVolume: Double = 0.8,
        hapticsEnabled: Bool = false,
        hapticStyle: HapticStyle = .light,
        hapticIntensity: Double = 0.6,
        showHitboxOverlay: Bool = false,
        hitboxScale: Double = 0.90,
        suggestionHitboxScale: Double = 1.0,
        suggestionTopPadding: Double = 0,
        panelButtonHitboxScale: Double = 1.0,
        adaptiveHitboxes: Bool = false,
        adaptiveGrow: Double = AdaptiveHitbox.defaultGrow,
        adaptiveShrink: Double = AdaptiveHitbox.defaultShrink,
        adaptivePredictionWeight: Double = AdaptiveHitbox.defaultPredictionWeight,
        adaptivePredictAtWordStart: Bool = true,
        spaceCursorStride: Double = 16,
        spaceCursorActivationDelay: Double = 150,
        cursorMovementType: CursorMovementType = .spacebar,
        cursorLineStride: Double = 30,
        keyBloomScale: Double = 1.06,
        keySpringResponse: Double = 0.12,
        keySpringDamping: Double = 0.90,
        keyPressInstant: Bool = false,
        keyPressStyle: KeyPressStyle = .bloom,
        keyPressGlow: Double = 0,
        keyboardEntrance: KeyboardEntrance = .none,
        spaceBloomScale: Double = 1.04,
        spaceSpringResponse: Double = 0.14,
        spaceSpringDamping: Double = 0.90,
        spaceLeanMultiplier: Double = 0.14,
        spaceCursorDragScale: Double = 0.90,
        popupSpringResponse: Double = 0.32,
        popupSpringDamping: Double = 0.62,
        glassReleaseResponse: Double = 0.12,
        repeatHoldDelay: Double = 450,
        repeatInitialInterval: Double = 110,
        repeatMinInterval: Double = 40,
        repeatAccelStep: Double = 6,
        swipeToDeleteWord: Bool = true,
        deleteWordSwipeEngage: Double = 24,
        deleteWordSwipeStride: Double = 42,
        accentHoldDelay: Double = 500,
        accentMoveCancel: Double = 12,
        emojiToneHoldDelay: Double = 280,
        dragUpThreshold: Double = 24,
        defaultSkinTone: SkinTone = .none,
        emojiSkinTones: [String: SkinTone] = [:],
        emojiScrollDirection: EmojiScrollDirection = .vertical,
        emojiColumnCount: Int = 8,
        emojiRowCount: Int = 5,
        emojiCellSpacing: CGFloat = 4,
        emojiGlyphScale: Double = 0.62,
        showRecentEmoji: Bool = true,
        recentEmoji: [String] = []
    ) {
        self.themeID = themeID
        self.advancedSettings = advancedSettings
        self.matchSystemAppearance = matchSystemAppearance
        self.lightThemeID = lightThemeID
        self.darkThemeID = darkThemeID
        self.customThemes = customThemes
        self.backgroundVisible = backgroundVisible
        self.themeApp = themeApp
        self.layoutID = layoutID
        self.spaceBarLeadingKeys = spaceBarLeadingKeys
        self.spaceBarTrailingKeys = spaceBarTrailingKeys
        self.customRows = customRows
        self.keyboardLanguages = keyboardLanguages.isEmpty ? ["en_US"] : keyboardLanguages
        self.accentPopupsEnabled = accentPopupsEnabled
        self.longPressHintsEnabled = longPressHintsEnabled
        self.showNumberRow = showNumberRow
        self.autoCapitalize = autoCapitalize
        self.keyPopupEnabled = keyPopupEnabled
        self.keyPopupStyle = keyPopupStyle
        self.liquidGlassPopup = liquidGlassPopup
        self.homeRowInset = homeRowInset
        self.homeRowInsetAmount = homeRowInsetAmount
        self.keyPressLinger = keyPressLinger
        self.minPressVisible = minPressVisible
        self.keyHeight = keyHeight
        self.numberRowHeightScale = numberRowHeightScale
        self.numberRowFontSize = numberRowFontSize
        self.keyCornerRadius = keyCornerRadius
        self.keyWidthFraction = keyWidthFraction
        self.spaceWidth = spaceWidth
        self.funcKeyWidth = funcKeyWidth
        self.keySpacing = keySpacing
        self.rowSpacing = rowSpacing
        self.keyboardTopPadding = keyboardTopPadding
        self.keyboardBottomPadding = keyboardBottomPadding
        self.clipboardEnabled = clipboardEnabled
        self.clipboardStyle = clipboardStyle
        self.clipboardCloseOnPaste = clipboardCloseOnPaste
        self.clipboardDeleteOnPaste = clipboardDeleteOnPaste
        self.clipboardIgnorePinsOnDelete = clipboardIgnorePinsOnDelete
        self.autoCopyOnKeyboardOpen = autoCopyOnKeyboardOpen
        self.autoCopyOnClipboardOpen = autoCopyOnClipboardOpen
        self.notepadEnabled = notepadEnabled
        self.translateEnabled = translateEnabled
        self.translateStyle = translateStyle
        self.notepadMode = notepadMode
        self.emojiEnabled = emojiEnabled
        self.emojiKeyInRow = emojiKeyInRow
        self.calculatorEnabled = calculatorEnabled
        self.userExtensionsEnabled = userExtensionsEnabled
        self.customPanelsEnabled = customPanelsEnabled
        self.customPanelsStandalone = customPanelsStandalone
        self.activateWithIcon = activateWithIcon
        self.activateWithSlideUp = activateWithSlideUp
        self.autoShowPanelIcons = autoShowPanelIcons
        self.animatePanelBarResize = animatePanelBarResize
        self.pinPanelIcons = pinPanelIcons
        self.iconPickerStyle = iconPickerStyle
        self.slideUpPickerStyle = slideUpPickerStyle
        self.extensionOrder = extensionOrder
        self.suggestionsEnabled = suggestionsEnabled
        self.autocorrectEnabled = autocorrectEnabled
        self.revertAutocorrectOnDelete = revertAutocorrectOnDelete
        self.learningEnabled = learningEnabled
        self.aiEnabled = aiEnabled
        self.aiSuggestions = aiSuggestions
        self.aiAutocorrect = aiAutocorrect
        self.aiPrediction = aiPrediction
        self.aiTranslate = aiTranslate
        self.suggestionDebounceDelay = suggestionDebounceDelay
        self.autoPunctuationEnabled = autoPunctuationEnabled
        self.autoReturnToLetters = autoReturnToLetters
        self.autoSpaceAfterReturn = autoSpaceAfterReturn
        self.swipeTypingEnabled = swipeTypingEnabled
        self.swipeShowTrail = swipeShowTrail
        self.swipeTrailWidth = swipeTrailWidth
        self.swipeKeyMorph = swipeKeyMorph
        self.swipeMorphStrength = swipeMorphStrength
        self.swipeMorphRadius = swipeMorphRadius
        self.soundPackID = soundPackID
        self.soundEnabled = soundEnabled
        self.soundVolume = soundVolume
        self.hapticsEnabled = hapticsEnabled
        self.hapticStyle = hapticStyle
        self.hapticIntensity = hapticIntensity
        self.showHitboxOverlay = showHitboxOverlay
        self.hitboxScale = hitboxScale
        self.suggestionHitboxScale = suggestionHitboxScale
        self.suggestionTopPadding = suggestionTopPadding
        self.panelButtonHitboxScale = panelButtonHitboxScale
        self.adaptiveHitboxes = adaptiveHitboxes
        self.adaptiveGrow = adaptiveGrow
        self.adaptiveShrink = adaptiveShrink
        self.adaptivePredictionWeight = adaptivePredictionWeight
        self.adaptivePredictAtWordStart = adaptivePredictAtWordStart
        self.spaceCursorStride = spaceCursorStride
        self.spaceCursorActivationDelay = spaceCursorActivationDelay
        self.cursorMovementType = cursorMovementType
        self.cursorLineStride = cursorLineStride
        self.keyBloomScale = keyBloomScale
        self.keySpringResponse = keySpringResponse
        self.keySpringDamping = keySpringDamping
        self.keyPressInstant = keyPressInstant
        self.keyPressStyle = keyPressStyle
        self.keyPressGlow = keyPressGlow
        self.keyboardEntrance = keyboardEntrance
        self.spaceBloomScale = spaceBloomScale
        self.spaceSpringResponse = spaceSpringResponse
        self.spaceSpringDamping = spaceSpringDamping
        self.spaceLeanMultiplier = spaceLeanMultiplier
        self.spaceCursorDragScale = spaceCursorDragScale
        self.popupSpringResponse = popupSpringResponse
        self.popupSpringDamping = popupSpringDamping
        self.glassReleaseResponse = glassReleaseResponse
        self.repeatHoldDelay = repeatHoldDelay
        self.repeatInitialInterval = repeatInitialInterval
        self.repeatMinInterval = repeatMinInterval
        self.repeatAccelStep = repeatAccelStep
        self.swipeToDeleteWord = swipeToDeleteWord
        self.deleteWordSwipeEngage = deleteWordSwipeEngage
        self.deleteWordSwipeStride = deleteWordSwipeStride
        self.accentHoldDelay = accentHoldDelay
        self.accentMoveCancel = accentMoveCancel
        self.emojiToneHoldDelay = emojiToneHoldDelay
        self.dragUpThreshold = dragUpThreshold
        self.defaultSkinTone = defaultSkinTone
        self.emojiSkinTones = emojiSkinTones
        self.emojiScrollDirection = emojiScrollDirection
        self.emojiColumnCount = emojiColumnCount
        self.emojiRowCount = emojiRowCount
        self.emojiCellSpacing = emojiCellSpacing
        self.emojiGlyphScale = emojiGlyphScale
        self.showRecentEmoji = showRecentEmoji
        self.recentEmoji = recentEmoji
    }

    public static let `default` = KeyboardSettings()

    // MARK: - Decoding

    /// Keys that no longer map to a stored property but must still be readable from
    /// older saved payloads for migration. `keyboardLanguage` (singular) became the
    /// `keyboardLanguages` array.
    private enum LegacyKeys: String, CodingKey {
        case keyboardLanguage
        /// Pre-split picker style key — migrated into `iconPickerStyle` + `slideUpPickerStyle`.
        case panelPickerStyle
        /// Retired master switch for all key-press effects. Effects now self-gate
        /// on their own strengths; a payload that turned this OFF migrates by
        /// zeroing bloom / tap-flash / glow (see `init(from:)`).
        case keyPressWarp
        /// Retired glass bloom multiplier. The single `keyBloomScale` now applies
        /// on every theme and auto-softens on glass (`KeyPressPhysics`); old
        /// values are simply ignored.
        case glassBloomFactor
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        themeID = try c.decodeIfPresent(String.self, forKey: .themeID) ?? Theme.default.id
        advancedSettings = try c.decodeIfPresent(Bool.self, forKey: .advancedSettings) ?? false
        matchSystemAppearance = try c.decodeIfPresent(Bool.self, forKey: .matchSystemAppearance) ?? true
        lightThemeID = try c.decodeIfPresent(String.self, forKey: .lightThemeID) ?? Theme.defaultLight.id
        darkThemeID = try c.decodeIfPresent(String.self, forKey: .darkThemeID) ?? Theme.defaultDark.id
        customThemes = try c.decodeIfPresent([Theme].self, forKey: .customThemes) ?? []
        backgroundVisible = try c.decodeIfPresent(Bool.self, forKey: .backgroundVisible) ?? false
        themeApp = try c.decodeIfPresent(Bool.self, forKey: .themeApp) ?? true
        layoutID = try c.decodeIfPresent(String.self, forKey: .layoutID) ?? KeyboardLayout.default.id
        spaceBarLeadingKeys = try c.decodeIfPresent([CustomKey].self, forKey: .spaceBarLeadingKeys) ?? []
        spaceBarTrailingKeys = try c.decodeIfPresent([CustomKey].self, forKey: .spaceBarTrailingKeys) ?? []
        customRows = try c.decodeIfPresent([CustomRow].self, forKey: .customRows) ?? []
        // Prefer the new multi-language array; migrate a payload that only has the
        // legacy single `keyboardLanguage` string; default to English otherwise.
        if let langs = try c.decodeIfPresent([String].self, forKey: .keyboardLanguages), !langs.isEmpty {
            keyboardLanguages = langs
        } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
                    .decodeIfPresent(String.self, forKey: .keyboardLanguage),
                  !legacy.isEmpty {
            keyboardLanguages = [legacy]
        } else {
            keyboardLanguages = ["en_US"]
        }
        accentPopupsEnabled = try c.decodeIfPresent(Bool.self, forKey: .accentPopupsEnabled) ?? true
        longPressHintsEnabled = try c.decodeIfPresent(Bool.self, forKey: .longPressHintsEnabled) ?? false
        showNumberRow = try c.decodeIfPresent(Bool.self, forKey: .showNumberRow) ?? false
        autoCapitalize = try c.decodeIfPresent(Bool.self, forKey: .autoCapitalize) ?? true
        keyPopupEnabled = try c.decodeIfPresent(Bool.self, forKey: .keyPopupEnabled) ?? true
        // `try?`, not `try`: a legacy persisted value (e.g. the retired "flat")
        // would otherwise throw and fail the whole settings decode. Fall back.
        keyPopupStyle = (try? c.decodeIfPresent(KeyPopupStyle.self, forKey: .keyPopupStyle)) ?? .balloon
        liquidGlassPopup = try c.decodeIfPresent(Bool.self, forKey: .liquidGlassPopup) ?? true
        homeRowInset = try c.decodeIfPresent(Bool.self, forKey: .homeRowInset) ?? true
        homeRowInsetAmount = try c.decodeIfPresent(Double.self, forKey: .homeRowInsetAmount) ?? 0.01
        keyPressLinger = try c.decodeIfPresent(Double.self, forKey: .keyPressLinger) ?? 0.06
        minPressVisible = try c.decodeIfPresent(Double.self, forKey: .minPressVisible) ?? 0.09
        keyHeight = try c.decodeIfPresent(Double.self, forKey: .keyHeight) ?? 46
        numberRowHeightScale = try c.decodeIfPresent(Double.self, forKey: .numberRowHeightScale) ?? 1.0
        numberRowFontSize = try c.decodeIfPresent(Double.self, forKey: .numberRowFontSize) ?? 22
        keyCornerRadius = try c.decodeIfPresent(Double.self, forKey: .keyCornerRadius) ?? 12
        keyWidthFraction = try c.decodeIfPresent(Double.self, forKey: .keyWidthFraction) ?? 1
        spaceWidth = try c.decodeIfPresent(Double.self, forKey: .spaceWidth) ?? 5
        funcKeyWidth = try c.decodeIfPresent(Double.self, forKey: .funcKeyWidth) ?? 1.4
        keySpacing = try c.decodeIfPresent(Double.self, forKey: .keySpacing) ?? 5
        rowSpacing = try c.decodeIfPresent(Double.self, forKey: .rowSpacing) ?? 7
        keyboardTopPadding = try c.decodeIfPresent(Double.self, forKey: .keyboardTopPadding) ?? 0
        keyboardBottomPadding = try c.decodeIfPresent(Double.self, forKey: .keyboardBottomPadding) ?? 0
        clipboardEnabled = try c.decodeIfPresent(Bool.self, forKey: .clipboardEnabled) ?? false
        clipboardStyle = (try? c.decodeIfPresent(ClipboardStyle.self, forKey: .clipboardStyle)) ?? .bar
        clipboardCloseOnPaste = try c.decodeIfPresent(Bool.self, forKey: .clipboardCloseOnPaste) ?? false
        clipboardDeleteOnPaste = try c.decodeIfPresent(Bool.self, forKey: .clipboardDeleteOnPaste) ?? false
        clipboardIgnorePinsOnDelete = try c.decodeIfPresent(Bool.self, forKey: .clipboardIgnorePinsOnDelete) ?? false
        autoCopyOnKeyboardOpen = try c.decodeIfPresent(Bool.self, forKey: .autoCopyOnKeyboardOpen) ?? false
        autoCopyOnClipboardOpen = try c.decodeIfPresent(Bool.self, forKey: .autoCopyOnClipboardOpen) ?? false
        notepadEnabled = try c.decodeIfPresent(Bool.self, forKey: .notepadEnabled) ?? false
        translateEnabled = try c.decodeIfPresent(Bool.self, forKey: .translateEnabled) ?? false
        translateStyle = (try? c.decodeIfPresent(TranslateStyle.self, forKey: .translateStyle)) ?? .inline
        notepadMode = (try? c.decodeIfPresent(NotepadMode.self, forKey: .notepadMode)) ?? .scratchpad
        emojiEnabled = try c.decodeIfPresent(Bool.self, forKey: .emojiEnabled) ?? true
        emojiKeyInRow = try c.decodeIfPresent(Bool.self, forKey: .emojiKeyInRow) ?? false
        calculatorEnabled = try c.decodeIfPresent(Bool.self, forKey: .calculatorEnabled) ?? false
        userExtensionsEnabled = try c.decodeIfPresent(Bool.self, forKey: .userExtensionsEnabled) ?? true
        customPanelsEnabled = try c.decodeIfPresent(Bool.self, forKey: .customPanelsEnabled) ?? true
        customPanelsStandalone = try c.decodeIfPresent(Bool.self, forKey: .customPanelsStandalone) ?? false
        activateWithIcon = try c.decodeIfPresent(Bool.self, forKey: .activateWithIcon) ?? true
        activateWithSlideUp = try c.decodeIfPresent(Bool.self, forKey: .activateWithSlideUp) ?? true
        autoShowPanelIcons = try c.decodeIfPresent(Bool.self, forKey: .autoShowPanelIcons) ?? false
        animatePanelBarResize = try c.decodeIfPresent(Bool.self, forKey: .animatePanelBarResize) ?? true
        pinPanelIcons = try c.decodeIfPresent(Bool.self, forKey: .pinPanelIcons) ?? false
        let legacyPickerStyle = (try? decoder.container(keyedBy: LegacyKeys.self)
            .decodeIfPresent(PanelPickerStyle.self, forKey: .panelPickerStyle)) ?? .popover
        iconPickerStyle = (try? c.decodeIfPresent(PanelPickerStyle.self, forKey: .iconPickerStyle)) ?? legacyPickerStyle
        slideUpPickerStyle = (try? c.decodeIfPresent(PanelPickerStyle.self, forKey: .slideUpPickerStyle)) ?? legacyPickerStyle
        extensionOrder = try c.decodeIfPresent([String].self, forKey: .extensionOrder) ?? ["calculator", "clipboard", "emoji", "notepad", "translate"]
        suggestionsEnabled = try c.decodeIfPresent(Bool.self, forKey: .suggestionsEnabled) ?? true
        autocorrectEnabled = try c.decodeIfPresent(Bool.self, forKey: .autocorrectEnabled) ?? true
        revertAutocorrectOnDelete = try c.decodeIfPresent(Bool.self, forKey: .revertAutocorrectOnDelete) ?? true
        learningEnabled = try c.decodeIfPresent(Bool.self, forKey: .learningEnabled) ?? false
        aiEnabled = try c.decodeIfPresent(Bool.self, forKey: .aiEnabled) ?? false
        aiSuggestions = try c.decodeIfPresent(Bool.self, forKey: .aiSuggestions) ?? true
        aiAutocorrect = try c.decodeIfPresent(Bool.self, forKey: .aiAutocorrect) ?? true
        aiPrediction = try c.decodeIfPresent(Bool.self, forKey: .aiPrediction) ?? true
        aiTranslate = try c.decodeIfPresent(Bool.self, forKey: .aiTranslate) ?? true
        suggestionDebounceDelay = try c.decodeIfPresent(Double.self, forKey: .suggestionDebounceDelay) ?? 80.0
        autoPunctuationEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoPunctuationEnabled) ?? true
        autoReturnToLetters = try c.decodeIfPresent(Bool.self, forKey: .autoReturnToLetters) ?? true
        autoSpaceAfterReturn = try c.decodeIfPresent(Bool.self, forKey: .autoSpaceAfterReturn) ?? true
        swipeTypingEnabled = try c.decodeIfPresent(Bool.self, forKey: .swipeTypingEnabled) ?? false
        swipeShowTrail = try c.decodeIfPresent(Bool.self, forKey: .swipeShowTrail) ?? true
        swipeTrailWidth = try c.decodeIfPresent(Double.self, forKey: .swipeTrailWidth) ?? 4
        swipeKeyMorph = try c.decodeIfPresent(Bool.self, forKey: .swipeKeyMorph) ?? true
        swipeMorphStrength = try c.decodeIfPresent(Double.self, forKey: .swipeMorphStrength) ?? 0.20
        swipeMorphRadius = try c.decodeIfPresent(Double.self, forKey: .swipeMorphRadius) ?? 1.3
        soundPackID = try c.decodeIfPresent(String.self, forKey: .soundPackID) ?? SoundPack.default.id
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? false
        soundVolume = try c.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.8
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? false
        hapticStyle = (try? c.decodeIfPresent(HapticStyle.self, forKey: .hapticStyle)) ?? .light
        hapticIntensity = try c.decodeIfPresent(Double.self, forKey: .hapticIntensity) ?? 0.6
        showHitboxOverlay = try c.decodeIfPresent(Bool.self, forKey: .showHitboxOverlay) ?? false
        hitboxScale = try c.decodeIfPresent(Double.self, forKey: .hitboxScale) ?? 0.90
        suggestionHitboxScale = try c.decodeIfPresent(Double.self, forKey: .suggestionHitboxScale) ?? 1.0
        suggestionTopPadding = try c.decodeIfPresent(Double.self, forKey: .suggestionTopPadding) ?? 0
        panelButtonHitboxScale = try c.decodeIfPresent(Double.self, forKey: .panelButtonHitboxScale) ?? 1.0
        adaptiveHitboxes = try c.decodeIfPresent(Bool.self, forKey: .adaptiveHitboxes) ?? false
        adaptiveGrow = try c.decodeIfPresent(Double.self, forKey: .adaptiveGrow) ?? AdaptiveHitbox.defaultGrow
        adaptiveShrink = try c.decodeIfPresent(Double.self, forKey: .adaptiveShrink) ?? AdaptiveHitbox.defaultShrink
        adaptivePredictionWeight = try c.decodeIfPresent(Double.self, forKey: .adaptivePredictionWeight) ?? AdaptiveHitbox.defaultPredictionWeight
        adaptivePredictAtWordStart = try c.decodeIfPresent(Bool.self, forKey: .adaptivePredictAtWordStart) ?? true
        spaceCursorStride = try c.decodeIfPresent(Double.self, forKey: .spaceCursorStride) ?? 16
        spaceCursorActivationDelay = try c.decodeIfPresent(Double.self, forKey: .spaceCursorActivationDelay) ?? 150
        cursorMovementType = (try? c.decodeIfPresent(CursorMovementType.self, forKey: .cursorMovementType)) ?? .spacebar
        cursorLineStride = try c.decodeIfPresent(Double.self, forKey: .cursorLineStride) ?? 30
        keyBloomScale = try c.decodeIfPresent(Double.self, forKey: .keyBloomScale) ?? 1.12
        keySpringResponse = try c.decodeIfPresent(Double.self, forKey: .keySpringResponse) ?? 0.26
        keySpringDamping = try c.decodeIfPresent(Double.self, forKey: .keySpringDamping) ?? 0.60
        keyPressInstant = try c.decodeIfPresent(Bool.self, forKey: .keyPressInstant) ?? false
        keyPressStyle = (try? c.decodeIfPresent(KeyPressStyle.self, forKey: .keyPressStyle)) ?? .bloom
        keyPressGlow = try c.decodeIfPresent(Double.self, forKey: .keyPressGlow) ?? 0
        // Migrate the retired master switch: a payload that turned `keyPressWarp`
        // OFF meant "no key-press effects". Effects now self-gate on their own
        // strengths, so reproduce that intent by zeroing bloom and glow. (Default
        // true → leave the decoded strengths as-is.)
        if let legacyWarp = try? decoder.container(keyedBy: LegacyKeys.self)
            .decodeIfPresent(Bool.self, forKey: .keyPressWarp), legacyWarp == false {
            keyBloomScale = 1.0
            keyPressGlow = 0
        }
        keyboardEntrance = (try? c.decodeIfPresent(KeyboardEntrance.self, forKey: .keyboardEntrance)) ?? .none
        spaceBloomScale = try c.decodeIfPresent(Double.self, forKey: .spaceBloomScale) ?? 1.04
        spaceSpringResponse = try c.decodeIfPresent(Double.self, forKey: .spaceSpringResponse) ?? 0.28
        spaceSpringDamping = try c.decodeIfPresent(Double.self, forKey: .spaceSpringDamping) ?? 0.78
        spaceLeanMultiplier = try c.decodeIfPresent(Double.self, forKey: .spaceLeanMultiplier) ?? 0.14
        spaceCursorDragScale = try c.decodeIfPresent(Double.self, forKey: .spaceCursorDragScale) ?? 0.90
        popupSpringResponse = try c.decodeIfPresent(Double.self, forKey: .popupSpringResponse) ?? 0.32
        popupSpringDamping = try c.decodeIfPresent(Double.self, forKey: .popupSpringDamping) ?? 0.62
        glassReleaseResponse = try c.decodeIfPresent(Double.self, forKey: .glassReleaseResponse) ?? 0.12
        repeatHoldDelay = try c.decodeIfPresent(Double.self, forKey: .repeatHoldDelay) ?? 450
        repeatInitialInterval = try c.decodeIfPresent(Double.self, forKey: .repeatInitialInterval) ?? 110
        repeatMinInterval = try c.decodeIfPresent(Double.self, forKey: .repeatMinInterval) ?? 40
        repeatAccelStep = try c.decodeIfPresent(Double.self, forKey: .repeatAccelStep) ?? 6
        swipeToDeleteWord = try c.decodeIfPresent(Bool.self, forKey: .swipeToDeleteWord) ?? true
        deleteWordSwipeEngage = try c.decodeIfPresent(Double.self, forKey: .deleteWordSwipeEngage) ?? 24
        deleteWordSwipeStride = try c.decodeIfPresent(Double.self, forKey: .deleteWordSwipeStride) ?? 42
        accentHoldDelay = try c.decodeIfPresent(Double.self, forKey: .accentHoldDelay) ?? 500
        accentMoveCancel = try c.decodeIfPresent(Double.self, forKey: .accentMoveCancel) ?? 12
        emojiToneHoldDelay = try c.decodeIfPresent(Double.self, forKey: .emojiToneHoldDelay) ?? 280
        dragUpThreshold = try c.decodeIfPresent(Double.self, forKey: .dragUpThreshold) ?? 24
        // `try?`: a future-retired tone case shouldn't fail the whole decode.
        defaultSkinTone = (try? c.decodeIfPresent(SkinTone.self, forKey: .defaultSkinTone)) ?? .none
        emojiSkinTones = (try? c.decodeIfPresent([String: SkinTone].self, forKey: .emojiSkinTones)) ?? [:]
        emojiScrollDirection = (try? c.decodeIfPresent(EmojiScrollDirection.self, forKey: .emojiScrollDirection)) ?? .vertical
        emojiColumnCount = try c.decodeIfPresent(Int.self, forKey: .emojiColumnCount) ?? 8
        emojiRowCount = try c.decodeIfPresent(Int.self, forKey: .emojiRowCount) ?? 5
        emojiCellSpacing = try c.decodeIfPresent(CGFloat.self, forKey: .emojiCellSpacing) ?? 4
        emojiGlyphScale = try c.decodeIfPresent(Double.self, forKey: .emojiGlyphScale) ?? 0.62
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
    /// Resolved sound pack for `soundPackID`.
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
