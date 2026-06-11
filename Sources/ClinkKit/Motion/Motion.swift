/**
 `Motion`: the single source of truth for every animation curve in Clink.

 Every fixed duration/spring in the app and keyboard lives here as a named
 token, one per distinct (curve, intent) pair. Call sites read
 `Motion.<token>.animation` instead of building literals, so:

   - the whole motion vocabulary is auditable in one file,
   - every animation resolves through `MotionProfile` (one chokepoint for
     Reduce Motion / Low Power degradation — see that file),
   - the values are frozen by `MotionTests`, which asserts each token still
     equals its historical literal. Changing a feel on purpose means updating
     the token AND its test row — changing it by accident is impossible.

 Tokens store raw curve parameters (an `Equatable` enum), not opaque
 `Animation` values, precisely so the freeze test can compare them.

 The user-tunable key-press springs are NOT here — they live in
 `KeyPressPhysics` (built from `KeyboardSettings`, tuned live in the app's
 Animation screen) and join the system via `MotionToken.userSpring`, so they
 resolve through the same profile without losing their knobs.
 */
import SwiftUI

// MARK: - Token

/// One named animation: a curve plus the role it plays, which decides how it
/// may degrade under Reduce Motion / Low Power (see `MotionProfile`).
struct MotionToken: Equatable, Sendable {
    /// Raw curve parameters. Mirrors the SwiftUI factory the call site used to
    /// build, so `.animation` in the `.full` tier is byte-identical to the
    /// original literal.
    enum Curve: Equatable, Sendable {
        case spring(response: Double, damping: Double)
        case interactiveSpring(response: Double, damping: Double)
        case snappy(duration: Double)
        case smooth(duration: Double)
        case easeInOut(duration: Double)
        case easeOut(duration: Double)
        case linear(duration: Double)

        /// The SwiftUI animation this curve describes, built exactly as the
        /// original call site did.
        var animation: Animation {
            switch self {
            case .spring(let r, let d):            .spring(response: r, dampingFraction: d)
            case .interactiveSpring(let r, let d): .interactiveSpring(response: r, dampingFraction: d)
            case .snappy(let d):                   .snappy(duration: d)
            case .smooth(let d):                   .smooth(duration: d)
            case .easeInOut(let d):                .easeInOut(duration: d)
            case .easeOut(let d):                  .easeOut(duration: d)
            case .linear(let d):                   .linear(duration: d)
            }
        }

        /// A plain duration for UIKit call sites (`UIView.animate`) and for the
        /// profile's shortened fallbacks. Springs report their response — the
        /// perceptual "time to mostly settled".
        var duration: TimeInterval {
            switch self {
            case .spring(let r, _), .interactiveSpring(let r, _): r
            case .snappy(let d), .smooth(let d), .easeInOut(let d),
                 .easeOut(let d), .linear(let d): d
            }
        }
    }

    /// What the animation is FOR — the contract `MotionProfile` degrades by.
    enum Role: Sendable {
        /// Tracks or settles a finger (press blooms, drag snap-backs). Never
        /// degraded: removing it would make touch feel broken, not calmer.
        case essential
        /// Confirms an action (tap flashes, highlights). May soften (lose
        /// overshoot) but never disappears.
        case feedback
        /// Moves chrome (panels, sheets, pickers). Shortens and flattens under
        /// Reduce Motion.
        case transition
        /// Pure ambience (idle pulses, repeat-forever shimmer). First to go.
        /// `repeatForever` call sites must also gate on
        /// `MotionProfile.shared.allowsAmbientMotion` — see that property.
        case decorative
    }

    var curve: Curve
    var role: Role

    /// The animation to use at the call site, resolved through the active
    /// motion profile. In the `.full` tier (every current user) this is
    /// byte-identical to building the literal directly.
    @MainActor var animation: Animation { MotionProfile.shared.resolve(self) }

    /// Duration for the UIKit call sites (e.g. the keyboard height resize).
    var uiDuration: TimeInterval { curve.duration }

    /// A user-tuned spring (from `KeyboardSettings` via `KeyPressPhysics`),
    /// wrapped as a token so it resolves through the same profile as the
    /// fixed vocabulary below.
    static func userSpring(response: Double, damping: Double,
                           role: Role = .essential) -> MotionToken {
        MotionToken(curve: .interactiveSpring(response: response, damping: damping), role: role)
    }
}

// MARK: - The vocabulary

/// Every fixed animation in Clink, by name. Values are frozen by `MotionTests`.
enum Motion {

    // MARK: Keyboard — panels & pickers

    /// Action panel / suggestion-bar area swapping content (clipboard, notepad…).
    static let panelTransition = MotionToken(curve: .spring(response: 0.30, damping: 0.85), role: .transition)
    /// Panel picker (and emoji canvas) opening; also the cards back-navigation.
    static let pickerOpen = MotionToken(curve: .snappy(duration: 0.22), role: .transition)
    /// Panel picker dismissing (and the slide-up drag's quicker open).
    static let pickerClose = MotionToken(curve: .snappy(duration: 0.18), role: .transition)
    /// Keyboard height resize (emoji search grows taller) — UIKit, use `uiDuration`.
    static let keyboardHeight = MotionToken(curve: .easeInOut(duration: 0.28), role: .transition)

    // MARK: Keyboard — keys

    /// Key glyph swapping (shift ⇄ caps-lock symbol, plane changes).
    static let glyphSwap = MotionToken(curve: .snappy(duration: 0.25), role: .feedback)
    /// Backspace swipe-to-delete-word engaging (glyph highlight).
    static let deleteSwipe = MotionToken(curve: .snappy(duration: 0.22), role: .feedback)
    /// Key glyphs fading while the space-bar cursor drag is active.
    static let spaceCursorFade = MotionToken(curve: .easeOut(duration: 0.15), role: .feedback)
    /// Additive tap flash: snap bright…
    static let tapFlashIn = MotionToken(curve: .linear(duration: 0.05), role: .feedback)
    /// …then ease back out. Both halves shared by keys and the emoji delete tile.
    static let tapFlashOut = MotionToken(curve: .easeOut(duration: 0.20), role: .feedback)
    /// Swipe ripple: a passing glide finger swells each key.
    static let swipeRipple = MotionToken(curve: .interactiveSpring(response: 0.16, damping: 0.72), role: .essential)
    /// Accent picker option highlight following the finger.
    static let accentHighlight = MotionToken(curve: .snappy(duration: 0.14), role: .feedback)

    // MARK: Keyboard — emoji

    /// Emoji search field expanding / collapsing.
    static let emojiSearchToggle = MotionToken(curve: .snappy(duration: 0.28), role: .transition)
    /// Programmatic scrolls inside the emoji grid / category strip.
    static let emojiScroll = MotionToken(curve: .easeInOut(duration: 0.2), role: .transition)
    /// Category tab selection changing.
    static let emojiTabSelect = MotionToken(curve: .snappy(duration: 0.26), role: .feedback)
    /// Category strip auto-centering the selected tab.
    static let emojiTabScroll = MotionToken(curve: .snappy(duration: 0.24), role: .transition)
    /// Category tab / delete tile press bloom.
    static let emojiTabPress = MotionToken(curve: .interactiveSpring(response: 0.26, damping: 0.6), role: .essential)
    /// Emoji cell press bloom (button style + showcase simulation).
    static let emojiCellPress = MotionToken(curve: .interactiveSpring(response: 0.22, damping: 0.6), role: .essential)
    /// Skin-tone picker highlight + swatch session open/close.
    static let skinTonePick = MotionToken(curve: .snappy(duration: 0.16), role: .feedback)
    /// Glass press flash, phase 1: droplet opacity blooms in…
    static let emojiFlashBloom = MotionToken(curve: .linear(duration: 0.06), role: .feedback)
    /// …phase 2: scale morphs out past full…
    static let emojiFlashMorph = MotionToken(curve: .easeOut(duration: 0.15), role: .feedback)
    /// …phase 3: opacity eases away…
    static let emojiFlashFade = MotionToken(curve: .easeOut(duration: 0.32), role: .feedback)
    /// …phase 4: scale settles back in.
    static let emojiFlashSettle = MotionToken(curve: .easeInOut(duration: 0.23), role: .feedback)

    // MARK: Keyboard — swipe rows (clipboard / notepad entries)

    /// Swipe-action row springing back to rest.
    static let swipeRowSettle = MotionToken(curve: .smooth(duration: 0.25), role: .essential)

    // MARK: App — chrome

    /// Sidebar open/close (offset + scrim).
    static let sidebar = MotionToken(curve: .spring(response: 0.32, damping: 0.86), role: .transition)
    /// Bottom sheet sliding up / gesture spring-backs.
    static let sheetPresent = MotionToken(curve: .spring(response: 0.35, damping: 0.88), role: .transition)
    /// Bottom sheet sliding away. (`.spring(response: 0.3)` — SwiftUI's default
    /// damping 0.825 made explicit.)
    static let sheetDismiss = MotionToken(curve: .spring(response: 0.30, damping: 0.825), role: .transition)
    /// Sheet expanding to a taller detent mid-gesture.
    static let sheetExpand = MotionToken(curve: .spring(response: 0.38, damping: 0.85), role: .transition)
    /// Theme-builder popup dismissing. (`.spring(response: 0.35)`, default damping.)
    static let popupDismiss = MotionToken(curve: .spring(response: 0.35, damping: 0.825), role: .transition)
    /// Settings sections revealing/hiding as toggles flip.
    static let settingsReveal = MotionToken(curve: .spring(response: 0.35, damping: 0.85), role: .transition)
    /// Selection highlights and copy-confirmation fades.
    static let selectionFade = MotionToken(curve: .easeInOut(duration: 0.15), role: .feedback)
    /// Scroll-edge hint arrows fading in/out.
    static let scrollHintFade = MotionToken(curve: .easeInOut(duration: 0.2), role: .feedback)
    /// Showcase typer crossfading between keyboard and emoji canvas.
    static let showcaseFade = MotionToken(curve: .easeInOut(duration: 0.3), role: .transition)
    /// Draggable card snapping while tracking.
    static let dragSnap = MotionToken(curve: .interactiveSpring(response: 0.25, damping: 0.8), role: .essential)
    /// Card springing home on release.
    static let cardSpring = MotionToken(curve: .spring(response: 0.30, damping: 0.8), role: .transition)
    /// Preview key press in the in-app keyboard mock.
    static let previewKeyPress = MotionToken(curve: .easeOut(duration: 0.12), role: .feedback)
    /// In-app preview popup show/hide.
    static let previewPopup = MotionToken(curve: .snappy(duration: 0.2), role: .transition)
    /// Cursor demo's idle breathing pulse (repeat-forever — gate the loop on
    /// `MotionProfile.shared.allowsAmbientMotion`).
    static let cursorPulse = MotionToken(curve: .easeInOut(duration: 1.5), role: .decorative)
}
