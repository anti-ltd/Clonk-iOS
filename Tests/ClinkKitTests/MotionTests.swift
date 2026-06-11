/**
 Motion freeze tests: every token in the `Motion` vocabulary is pinned to the
 historical literal its call sites used before the token migration. A failure
 here means an animation's feel changed — if that was on purpose, update the
 token AND its row below in the same change; if not, you just caught a
 regression the eye might have missed.
 */
import SwiftUI
import Testing

@Suite struct MotionTests {

    /// The frozen vocabulary: token → the exact pre-migration literal.
    private static let frozen: [(name: String, token: MotionToken, value: MotionToken.Curve)] = [
        // Keyboard — panels & pickers
        ("panelTransition", Motion.panelTransition, .spring(response: 0.30, damping: 0.85)),
        ("pickerOpen", Motion.pickerOpen, .snappy(duration: 0.22)),
        ("pickerClose", Motion.pickerClose, .snappy(duration: 0.18)),
        ("keyboardHeight", Motion.keyboardHeight, .easeInOut(duration: 0.28)),
        // Keyboard — keys
        ("glyphSwap", Motion.glyphSwap, .snappy(duration: 0.25)),
        ("deleteSwipe", Motion.deleteSwipe, .snappy(duration: 0.22)),
        ("spaceCursorFade", Motion.spaceCursorFade, .easeOut(duration: 0.15)),
        ("tapFlashIn", Motion.tapFlashIn, .linear(duration: 0.05)),
        ("tapFlashOut", Motion.tapFlashOut, .easeOut(duration: 0.20)),
        ("swipeRipple", Motion.swipeRipple, .interactiveSpring(response: 0.16, damping: 0.72)),
        ("accentHighlight", Motion.accentHighlight, .snappy(duration: 0.14)),
        // Keyboard — emoji
        ("emojiSearchToggle", Motion.emojiSearchToggle, .snappy(duration: 0.28)),
        ("emojiScroll", Motion.emojiScroll, .easeInOut(duration: 0.2)),
        ("emojiTabSelect", Motion.emojiTabSelect, .snappy(duration: 0.26)),
        ("emojiTabScroll", Motion.emojiTabScroll, .snappy(duration: 0.24)),
        ("emojiTabPress", Motion.emojiTabPress, .interactiveSpring(response: 0.26, damping: 0.6)),
        ("emojiCellPress", Motion.emojiCellPress, .interactiveSpring(response: 0.22, damping: 0.6)),
        ("skinTonePick", Motion.skinTonePick, .snappy(duration: 0.16)),
        ("emojiFlashBloom", Motion.emojiFlashBloom, .linear(duration: 0.06)),
        ("emojiFlashMorph", Motion.emojiFlashMorph, .easeOut(duration: 0.15)),
        ("emojiFlashFade", Motion.emojiFlashFade, .easeOut(duration: 0.32)),
        ("emojiFlashSettle", Motion.emojiFlashSettle, .easeInOut(duration: 0.23)),
        // Keyboard — swipe rows
        ("swipeRowSettle", Motion.swipeRowSettle, .smooth(duration: 0.25)),
        // App — chrome
        ("sidebar", Motion.sidebar, .spring(response: 0.32, damping: 0.86)),
        ("sheetPresent", Motion.sheetPresent, .spring(response: 0.35, damping: 0.88)),
        ("sheetDismiss", Motion.sheetDismiss, .spring(response: 0.30, damping: 0.825)),
        ("sheetExpand", Motion.sheetExpand, .spring(response: 0.38, damping: 0.85)),
        ("popupDismiss", Motion.popupDismiss, .spring(response: 0.35, damping: 0.825)),
        ("settingsReveal", Motion.settingsReveal, .spring(response: 0.35, damping: 0.85)),
        ("selectionFade", Motion.selectionFade, .easeInOut(duration: 0.15)),
        ("scrollHintFade", Motion.scrollHintFade, .easeInOut(duration: 0.2)),
        ("showcaseFade", Motion.showcaseFade, .easeInOut(duration: 0.3)),
        ("dragSnap", Motion.dragSnap, .interactiveSpring(response: 0.25, damping: 0.8)),
        ("cardSpring", Motion.cardSpring, .spring(response: 0.30, damping: 0.8)),
        ("previewKeyPress", Motion.previewKeyPress, .easeOut(duration: 0.12)),
        ("previewPopup", Motion.previewPopup, .snappy(duration: 0.2)),
        ("cursorPulse", Motion.cursorPulse, .easeInOut(duration: 1.5)),
    ]

    @Test func everyTokenMatchesItsHistoricalLiteral() {
        for row in Self.frozen {
            #expect(row.token.curve == row.value, "\(row.name) drifted from its frozen value")
        }
    }

    /// `.full` (the default tier, every current user) must resolve every token
    /// to exactly the animation its original literal built — the engine is
    /// invisible until a system condition says otherwise.
    @MainActor @Test func fullTierResolutionIsIdentity() {
        #expect(MotionProfile.shared.tier == .full)
        for row in Self.frozen {
            #expect(MotionProfile.shared.resolve(row.token) == row.token.curve.animation,
                    "\(row.name) not identity-resolved in .full")
        }
    }

    /// The explicit-default spring shorthands some call sites used must equal
    /// their spelled-out token curves (SwiftUI's default dampingFraction is
    /// 0.825 — if an SDK ever changes that, this catches it).
    @Test func defaultDampingShorthandsStillMatch() {
        #expect(Motion.sheetDismiss.curve.animation == .spring(response: 0.3))
        #expect(Motion.popupDismiss.curve.animation == .spring(response: 0.35))
    }

    /// `.conserving` keeps every curve — its levers are the expensive-effects
    /// and ambient-motion gates, not the curves.
    @MainActor @Test func conservingTierKeepsCurves() {
        for row in Self.frozen {
            #expect(MotionProfile.resolve(row.token, tier: .conserving) == row.token.curve.animation,
                    "\(row.name) curve changed under .conserving")
        }
    }

    /// `.reduced` never touches essential (finger-tracking) animations, and
    /// maps the other roles to their calmer equivalents.
    @MainActor @Test func reducedTierDegradesByRole() {
        for row in Self.frozen {
            let resolved = MotionProfile.resolve(row.token, tier: .reduced)
            switch row.token.role {
            case .essential:
                #expect(resolved == row.token.curve.animation, "\(row.name) essential degraded")
            case .feedback:
                #expect(resolved == .easeOut(duration: row.token.uiDuration), "\(row.name) feedback mapping")
            case .transition:
                #expect(resolved == .easeInOut(duration: min(row.token.uiDuration, 0.15)), "\(row.name) transition mapping")
            case .decorative:
                #expect(resolved == .linear(duration: 0), "\(row.name) decorative mapping")
            }
        }
    }

    /// User-tuned springs wrap into tokens without distortion.
    @Test func userSpringPreservesParameters() {
        let token = MotionToken.userSpring(response: 0.26, damping: 0.60)
        #expect(token.curve == .interactiveSpring(response: 0.26, damping: 0.60))
        #expect(token.role == .essential)
    }

    /// UIKit fallback durations: plain curves report their duration, springs
    /// their response.
    @Test func uiDurationsAreSane() {
        #expect(Motion.keyboardHeight.uiDuration == 0.28)
        #expect(Motion.sidebar.uiDuration == 0.32)
    }
}
