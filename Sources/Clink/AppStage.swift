/**
 `AppStage`: launch-argument wiring for the `appstage` marketing screenshot
 pipeline. DEBUG-only — not compiled into Release builds.
 */
import SwiftUI

// AppStage marketing-capture support.
//
// The AppStage pipeline (~/Projects/AppStage-MacOS) screenshots each marketing
// state by launching the app with `--appstage <slug>` and nothing else. So
// every staged screen seeds its own believable settings (a curated theme so the
// live keyboard preview looks its best) and routes itself on launch.
//
// All `#if DEBUG`: it never compiles into a Release / App Store build, matching
// the screenshot-backend-never-ships posture of our other apps.
#if DEBUG
enum AppStage {
    static let slug: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--appstage"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    static var isActive: Bool { slug != nil }

    /// Curated settings per staged screen so the in-app keyboard preview reads
    /// beautifully in each shot.
    static func settings(for slug: String) -> KeyboardSettings {
        switch slug {

        // MARK: - Hero shots
        case "glass":
            // The WOW shot: Liquid Glass mid-type. Key popups OFF — the held
            // key reads as depressed; the balloon looked off here.
            return KeyboardSettings(
                themeID: "liquid-dark", matchSystemAppearance: false,
                keyPopupEnabled: false)

        case "hero":
            // Full app home screen — card grid with the live keyboard preview.
            return KeyboardSettings(
                themeID: "liquid-dark", matchSystemAppearance: false)

        // MARK: - Customization screens
        case "themes":
            // Theme picker: Mechanical looks distinct in the swatch grid.
            return KeyboardSettings(
                themeID: "mechanical", matchSystemAppearance: false)

        case "layout":
            // Layout picker: Synthwave + number row shows off the row option.
            return KeyboardSettings(
                themeID: "synthwave", matchSystemAppearance: false,
                showNumberRow: true)

        case "animation":
            // Physics tuning — glass keys show the spring behaviour best.
            return KeyboardSettings(
                themeID: "liquid-dark", matchSystemAppearance: false)

        case "automation":
            // Automation (auto-cap, smart punctuation) — Paper: clean, minimal.
            return KeyboardSettings(
                themeID: "paper", matchSystemAppearance: false)

        case "cursor":
            // Cursor movement — Carbon: dark, focused, the space bar pops.
            return KeyboardSettings(
                themeID: "carbon", matchSystemAppearance: false)

        case "gestures":
            // Swipe typing — liquid glass + trail on shows off morph ripple.
            return KeyboardSettings(
                themeID: "liquid-dark", matchSystemAppearance: false,
                swipeTypingEnabled: true, swipeShowTrail: true,
                swipeKeyMorph: true)

        case "haptics":
            // Haptics — Graphite: mechanical feel matches the section.
            return KeyboardSettings(
                themeID: "graphite", matchSystemAppearance: false,
                hapticsEnabled: true)

        case "keys":
            // Key size & shape — Midnight: keys read crisply on pure dark.
            return KeyboardSettings(
                themeID: "midnight", matchSystemAppearance: false,
                keyPopupEnabled: true)

        case "popups":
            // Key popups — liquid glass popups are the wow.
            return KeyboardSettings(
                themeID: "liquid-dark", matchSystemAppearance: false,
                keyPopupEnabled: true, liquidGlassPopup: true)

        case "sound", "sounds":
            // Sound pack picker — Graphite, sound on so the toggle reads live.
            return KeyboardSettings(
                themeID: "graphite", matchSystemAppearance: false,
                soundEnabled: true)

        case "suggestions":
            // Suggestion / autocorrect bar — Ocean: clean bar above the keys.
            return KeyboardSettings(
                themeID: "ocean", matchSystemAppearance: false,
                suggestionsEnabled: true)

        // MARK: - Extensions
        case "clipboard":
            // Clipboard history — Graphite with clipboard enabled.
            return KeyboardSettings(
                themeID: "graphite", matchSystemAppearance: false,
                clipboardEnabled: true)

        case "emoji":
            // Emoji picker — Bubblegum: playful and colourful.
            return KeyboardSettings(
                themeID: "bubblegum", matchSystemAppearance: false,
                emojiEnabled: true)

        case "notepad":
            // Notepad — Snow: clean, writing-friendly.
            return KeyboardSettings(
                themeID: "snow", matchSystemAppearance: false,
                notepadEnabled: true)

        case "calculator":
            // Calculator — Mechanical: numeric feel.
            return KeyboardSettings(
                themeID: "mechanical", matchSystemAppearance: false,
                calculatorEnabled: true)

        // MARK: - Advanced
        case "hitboxes":
            // Hitbox overlay — Graphite with the overlay on.
            return KeyboardSettings(
                themeID: "graphite", matchSystemAppearance: false,
                showHitboxOverlay: true)

        case "overlays":
            return KeyboardSettings(
                themeID: "graphite", matchSystemAppearance: false)

        case "performance":
            return KeyboardSettings(
                themeID: "graphite", matchSystemAppearance: false)

        case "response":
            return KeyboardSettings(
                themeID: "graphite", matchSystemAppearance: false)

        // MARK: - Onboarding
        case "setup":
            return KeyboardSettings(
                themeID: "liquid-dark", matchSystemAppearance: false)

        default:
            return KeyboardSettings(
                themeID: "liquid-dark", matchSystemAppearance: false)
        }
    }
}

/// Routes a staged launch straight to the screen we want to photograph, with
/// the curated settings already applied by `AppModel`.
struct StagedRoot: View {
    let slug: String

    var body: some View {
        switch slug {

        // Hero shots
        case "glass":       StagedHeroView()
        case "hero":        RootView()

        // Customization — each wrapped in a NavigationStack so the nav bar
        // and title render exactly as they do in the live app.
        case "themes":      NavigationStack { ThemeEditorView() }
        case "layout":      NavigationStack { LayoutView() }
        case "animation":   NavigationStack { AnimationView() }
        case "automation":  NavigationStack { AutomationView() }
        case "cursor":      NavigationStack { CursorView() }
        case "gestures":    NavigationStack { GesturesView() }
        case "haptics":     NavigationStack { HapticsView() }
        case "keys":        NavigationStack { KeysView() }
        case "popups":      NavigationStack { PopupsView() }
        case "sound", "sounds": NavigationStack { SoundsView() }
        case "suggestions": NavigationStack { SuggestionsView() }

        // Extensions
        case "clipboard":   NavigationStack { ClipboardHistoryView() }
        case "emoji":       NavigationStack { EmojiSettingsView() }
        case "notepad":     NavigationStack { NotepadView() }
        case "calculator":  NavigationStack { CalculatorSettingsView() }

        // Advanced
        case "hitboxes":    NavigationStack { HitboxView() }
        case "overlays":    NavigationStack { OverlaysView() }
        case "performance": NavigationStack { PerformanceView() }
        case "response":    NavigationStack { ResponseView() }

        // Onboarding
        case "setup":       NavigationStack { EnableFlowView() }

        default:            RootView()
        }
    }
}
#endif
