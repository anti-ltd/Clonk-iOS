import SwiftUI

// AppStage marketing-capture support.
//
// The AppStage pipeline (~/Projects/appstage) screenshots each marketing state
// by launching the app with `--appstage <slug>` and nothing else. So every
// staged screen seeds its own believable settings (a curated theme so the live
// keyboard preview looks its best) and routes itself on launch.
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
        case "sound":
            return KeyboardSettings(
                themeID: "graphite", matchSystemAppearance: false,
                soundPackID: "tactile", soundEnabled: true, hapticsEnabled: true)
        case "layout":
            return KeyboardSettings(
                themeID: "synthwave", matchSystemAppearance: false, showNumberRow: true)
        case "themes":
            return KeyboardSettings(themeID: "mechanical", matchSystemAppearance: false)
        case "glass":
            // The hero shot: Liquid Glass, dark. Key popups OFF — the held key
            // just reads as depressed; the magnified balloon looked off here.
            return KeyboardSettings(
                themeID: "liquid-dark", matchSystemAppearance: false, keyPopupEnabled: false)
        default: // hero
            return KeyboardSettings(themeID: "liquid-dark", matchSystemAppearance: false)
        }
    }
}

/// Routes a staged launch straight to the screen we want to photograph, with
/// the curated settings already applied by `AppModel`.
struct StagedRoot: View {
    let slug: String

    var body: some View {
        switch slug {
        case "glass":  StagedHeroView()   // the WOW shot: glass keyboard mid-type
        case "themes": NavigationStack { ThemeEditorView() }
        case "layout": NavigationStack { LayoutPickerView() }
        case "sound":  NavigationStack { SoundPickerView() }
        case "setup":  NavigationStack { EnableFlowView() }
        default:       RootView()   // hero — the full app with the live preview
        }
    }
}
#endif
