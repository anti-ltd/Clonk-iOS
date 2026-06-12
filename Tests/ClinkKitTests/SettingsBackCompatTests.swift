/**
 Backwards-compatibility freeze for `KeyboardSettings` decoding. The blob below is
 a REAL user's "stable" v1 `.clinkconfig` export, pinned verbatim. The import path
 (`AppModel.importConfiguration`) decodes with `try? … else { return }`, so a decode
 failure does NOT surface an error — it silently no-ops the import. That makes a
 broken decode invisible in the app, so we guard it here instead: this payload must
 keep decoding, every present field must round-trip to its stored value, and every
 field the v1 schema lacked must fall back to its default.

 If you change `KeyboardSettings` and this test fails, you've broken an existing
 user's saved config. Add a migration in `init(from:)`, don't change this blob.
 */
import Foundation
import Testing

@Suite struct SettingsBackCompatTests {

    /// A real v1 "stable" config, exactly as exported (theme keys stripped by the
    /// exporter, the singular legacy `keyboardLanguage` already gone). Do not edit.
    private static let stableV1JSON = #"""
    {"emojiScrollDirection":"vertical","panelPickerStyle":"popover","swipeMorphRadius":1.3,"activateWithIcon":true,"learningEnabled":true,"spaceLeanMultiplier":0.080000000000000002,"keyPressInstant":true,"clipboardStyle":"grid","keyBloomScale":1.0600000000000001,"accentHoldDelay":300,"themeApp":true,"numberRowHeightScale":1,"accentMoveCancel":18,"autoReturnToLetters":false,"hapticsEnabled":true,"autoSpaceAfterReturn":false,"customPanelsEnabled":true,"repeatMinInterval":40,"swipeKeyMorph":true,"autocorrectEnabled":false,"tapFlashStrength":0.34000000000000002,"repeatAccelStep":6,"showRecentEmoji":true,"customRows":[],"emojiGlyphScale":0.8027624309392265,"spaceBloomScale":1.02,"suggestionsEnabled":true,"liquidGlassPopup":true,"swipeTrailWidth":4,"spaceCursorActivationDelay":100,"clipboardCloseOnPaste":true,"spaceCursorStride":10,"keyPopupEnabled":false,"clipboardIgnorePinsOnDelete":false,"autoPunctuationEnabled":true,"recentEmoji":["✋","😉"],"soundEnabled":false,"homeRowInsetAmount":0.035000000000000003,"popupSpringResponse":0.20000000000000001,"swipeToDeleteWord":true,"layoutID":"qwerty","dragUpThreshold":16,"clipboardEnabled":true,"keyPressLinger":0,"matchSystemAppearance":true,"emojiSkinTones":{"✋":"none"},"showHitboxOverlay":false,"keyboardLanguages":["en_US"],"spaceSpringDamping":0.88,"keySpringResponse":0.16,"funcKeyWidth":1.3999999999999999,"clipboardDeleteOnPaste":false,"swipeMorphStrength":0.20000000000000001,"adaptivePredictionWeight":0.65000000000000002,"keyboardTopPadding":0,"glassReleaseResponse":0.059999999999999998,"deleteWordSwipeStride":42,"panelButtonHitboxScale":1.5,"swipeTypingEnabled":false,"showNumberRow":true,"keyPressWarp":true,"adaptiveShrink":0.90000000000000002,"adaptiveGrow":1.5,"cursorMovementType":"combined","activateWithSlideUp":true,"extensionOrder":["calculator","clipboard","emoji","notepad"],"autoCapitalize":false,"homeRowInset":true,"rowSpacing":8,"deleteWordSwipeEngage":24,"repeatInitialInterval":110,"keySpringDamping":0.84999999999999998,"userExtensionsEnabled":true,"customPanelsStandalone":false,"emojiColumnCount":8,"numberRowFontSize":22,"notepadMode":"scratchpad","emojiKeyInRow":true,"emojiEnabled":true,"spaceWidth":7,"autoCopyOnKeyboardOpen":true,"defaultSkinTone":"light","spaceCursorDragScale":0.94999999999999996,"calculatorEnabled":false,"suggestionDebounceDelay":80,"spaceBarLeadingKeys":[{"action":{"insert":{"_0":","}},"id":"F67B7A3D-1A29-4EDA-B757-1A0360C861EF","glyph":",","isSymbol":false,"width":1.5,"alternates":[";",":"]}],"hapticIntensity":1,"popupSpringDamping":0.84999999999999998,"notepadEnabled":false,"spaceSpringResponse":0.16,"autoCopyOnClipboardOpen":true,"glassBloomFactor":0,"adaptivePredictAtWordStart":false,"soundPackID":"system","adaptiveHitboxes":true,"minPressVisible":0.089999999999999997,"emojiToneHoldDelay":180,"repeatHoldDelay":450,"spaceBarTrailingKeys":[{"alternates":["?","!","…"],"id":"A5782AE7-4A4C-41C8-A041-89AC9F6C4095","glyph":".","isSymbol":false,"width":1.5,"action":{"insert":{"_0":"."}}}],"keySpacing":5,"suggestionHitboxScale":1,"keyCornerRadius":8,"soundVolume":0.80000000000000004,"hapticStyle":"rigid","accentPopupsEnabled":true,"keyboardBottomPadding":30,"keyPopupStyle":"balloon","keyWidthFraction":1,"emojiRowCount":5,"revertAutocorrectOnDelete":true,"swipeShowTrail":true,"hitboxScale":1.25,"keyHeight":50,"backgroundVisible":false,"cursorLineStride":30,"emojiCellSpacing":4}
    """#

    private static func decoded() throws -> KeyboardSettings {
        try JSONDecoder().decode(KeyboardSettings.self, from: Data(stableV1JSON.utf8))
    }

    @Test func stableV1Decodes() throws {
        // The whole point: this must not throw. The import path swallows a throw,
        // so a regression here would silently drop a user's settings in the app.
        _ = try Self.decoded()
    }

    @Test func structuredKeysSurvive() throws {
        let s = try Self.decoded()

        // Space-bar custom keys are decoded with a hard `try` (not `try?`) — a shape
        // change to CustomKey / CustomKeyAction would fail the ENTIRE settings decode.
        #expect(s.spaceBarLeadingKeys.count == 1)
        let lead = try #require(s.spaceBarLeadingKeys.first)
        #expect(lead.glyph == ",")
        #expect(lead.isSymbol == false)
        #expect(lead.width == 1.5)
        #expect(lead.alternates == [";", ":"])
        #expect(lead.action == .insert(","))

        #expect(s.spaceBarTrailingKeys.count == 1)
        let trail = try #require(s.spaceBarTrailingKeys.first)
        #expect(trail.glyph == ".")
        #expect(trail.action == .insert("."))
        #expect(trail.alternates == ["?", "!", "…"])

        // Enums must still carry their v1 raw values.
        #expect(s.clipboardStyle == .grid)
        #expect(s.cursorMovementType == .combined)
        #expect(s.hapticStyle == .rigid)
        #expect(s.iconPickerStyle == .popover)      // migrated from legacy panelPickerStyle
        #expect(s.slideUpPickerStyle == .popover)   // migrated from legacy panelPickerStyle
        #expect(s.keyPopupStyle == .balloon)
        #expect(s.notepadMode == .scratchpad)
        #expect(s.emojiScrollDirection == .vertical)

        // Skin tones (decoded with `try?`, but should still round-trip cleanly).
        #expect(s.defaultSkinTone == .light)
        #expect(s.emojiSkinTones == ["✋": .none])

        #expect(s.keyboardLanguages == ["en_US"])
        #expect(s.recentEmoji == ["✋", "😉"])
        #expect(s.extensionOrder == ["calculator", "clipboard", "emoji", "notepad"])
    }

    @Test func scalarValuesRoundTrip() throws {
        let s = try Self.decoded()
        // Spot-check a spread of scalar fields, including ones whose v1 value differs
        // from the current default — they must keep the user's value, not the default.
        #expect(s.learningEnabled == true)          // default is false
        #expect(s.autocorrectEnabled == false)      // default is true
        #expect(s.autoCapitalize == false)          // default is true
        #expect(s.keyPressInstant == true)          // default is false
        #expect(s.showNumberRow == true)            // default is false
        #expect(s.keyHeight == 50)
        #expect(s.keyCornerRadius == 8)
        #expect(s.keySpacing == 5)
        #expect(s.rowSpacing == 8)
        #expect(s.keyboardBottomPadding == 30)
        #expect(s.emojiColumnCount == 8)
        #expect(s.hapticIntensity == 1)
        #expect(s.glassBloomFactor == 0)
    }

    @Test func absentKeysFallBackToDefaults() throws {
        let s = try Self.decoded()
        // This v1 export omits these config keys — they must default cleanly rather
        // than throw or leave the value undefined. (Theme keys are a SEPARATE system
        // and are intentionally not part of the config, so they're not asserted here.)
        #expect(s.longPressHintsEnabled == false)
        #expect(s.suggestionTopPadding == 0)
        // AI is opt-in: a legacy config without the key must decode to OFF.
        #expect(s.aiEnabled == false)
    }
}
