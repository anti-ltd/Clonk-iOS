import SwiftUI

/// App-wide state for the Clink container app. Owns the editable
/// `KeyboardSettings` and persists every change straight to the App Group so
/// the keyboard extension picks it up. Also surfaces the two bits of status
/// the setup screen needs: is our keyboard enabled, and does it have Full
/// Access.
@MainActor
@Observable
final class AppModel {
    /// The live settings. Mutating any field (or a nested field) persists the
    /// whole value to the shared store and notifies a running keyboard.
    var settings: KeyboardSettings {
        didSet { store.save(settings) }
    }

    /// Whether "Clink" appears in the user's enabled keyboards. Refreshed on
    /// foreground. Read from the `AppleKeyboards` default — the documented-by-
    /// convention list of enabled keyboard bundle identifiers.
    private(set) var isKeyboardEnabled: Bool = false

    /// Whether the emoji keyboard is in the user's enabled keyboards.
    private(set) var isEmojiEnabled: Bool = false

    /// Last Full Access state the extension reported. Stale until the keyboard
    /// has run once, so the UI treats it as a hint, not gospel.
    private(set) var hasFullAccess: Bool = false

    private let store = SharedStore.shared
    private let keyboardBundleID = "ltd.anti.clink.keyboard"
    private let emojiBundleID = "ltd.anti.clink.emoji"

    init() {
        settings = store.load()
        #if DEBUG
        // AppStage capture: seed a curated theme so the preview looks its best.
        // Assigning in init doesn't trigger `didSet`, so this never persists.
        if let slug = AppStage.slug {
            settings = AppStage.settings(for: slug)
        }
        #endif
        refreshStatus()
    }

    // MARK: - Custom themes

    /// Insert a new custom theme or update an existing one (matched by id).
    func saveCustomTheme(_ theme: Theme) {
        if let i = settings.customThemes.firstIndex(where: { $0.id == theme.id }) {
            settings.customThemes[i] = theme
        } else {
            settings.customThemes.append(theme)
        }
    }

    /// Remove a custom theme, reverting any selection that pointed at it back to
    /// the matching default so the keyboard never references a missing theme.
    func deleteCustomTheme(id: String) {
        settings.customThemes.removeAll { $0.id == id }
        if settings.themeID == id { settings.themeID = Theme.default.id }
        if settings.lightThemeID == id { settings.lightThemeID = Theme.defaultLight.id }
        if settings.darkThemeID == id { settings.darkThemeID = Theme.defaultDark.id }
    }

    func refreshStatus() {
        let enabled = (UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String]) ?? []
        isKeyboardEnabled = enabled.contains(keyboardBundleID)
        isEmojiEnabled = enabled.contains(emojiBundleID)
        hasFullAccess = store.lastKnownFullAccess
    }
}
