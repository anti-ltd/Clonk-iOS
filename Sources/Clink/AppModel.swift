/**
 `AppModel`: app-wide observable state. Owns `KeyboardSettings`, persisting every
 change to the App Group so the keyboard extension picks it up instantly. Also
 exposes enable / Full Access status, clipboard, and notepad managers.
 */
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

    /// Last Full Access state the extension reported. Stale until the keyboard
    /// has run once, so the UI treats it as a hint, not gospel.
    private(set) var hasFullAccess: Bool = false

    let clipboard = ClipboardManager()
    let notepad = NotepadManager()

    private let store = SharedStore.shared
    private let keyboardBundleID = "ltd.anti.clink.keyboard"

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

    /// Downscale and persist a picked background photo, returning the id to store
    /// on the theme. The bytes go to the App Group (not the settings JSON) so the
    /// keyboard extension can read them; the id is unique per import so a stored
    /// image is never stale.
    func saveBackgroundImage(_ jpeg: Data) -> String {
        let id = "bg-\(UUID().uuidString.prefix(8))"
        ThemeBackgroundStore.shared.save(jpeg, for: id)
        return id
    }

    /// Insert a new custom theme or update an existing one (matched by id). If an
    /// edit swaps out the background photo, the orphaned image file is deleted.
    func saveCustomTheme(_ theme: Theme) {
        if let i = settings.customThemes.firstIndex(where: { $0.id == theme.id }) {
            let old = settings.customThemes[i]
            if let oldID = old.backgroundImageID, oldID != theme.backgroundImageID {
                ThemeBackgroundStore.shared.delete(id: oldID)
            }
            if let oldKeyID = old.keyImageID, oldKeyID != theme.keyImageID {
                ThemeBackgroundStore.shared.delete(id: oldKeyID)
            }
            settings.customThemes[i] = theme
        } else {
            settings.customThemes.append(theme)
        }
    }

    /// Remove a custom theme, reverting any selection that pointed at it back to
    /// the matching default so the keyboard never references a missing theme.
    func deleteCustomTheme(id: String) {
        if let theme = settings.customThemes.first(where: { $0.id == id }) {
            if let imageID = theme.backgroundImageID { ThemeBackgroundStore.shared.delete(id: imageID) }
            if let keyImageID = theme.keyImageID { ThemeBackgroundStore.shared.delete(id: keyImageID) }
        }
        settings.customThemes.removeAll { $0.id == id }
        if settings.themeID == id { settings.themeID = Theme.default.id }
        if settings.lightThemeID == id { settings.lightThemeID = Theme.defaultLight.id }
        if settings.darkThemeID == id { settings.darkThemeID = Theme.defaultDark.id }
    }

    /// Import a theme from a `.clink` URL (e.g. opened from Files.app).
    func importTheme(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              var theme = try? JSONDecoder().decode(Theme.self, from: data) else { return }
        theme.id = "custom-\(UUID().uuidString.prefix(8))"
        saveCustomTheme(theme)
        if settings.matchSystemAppearance {
            if theme.isDark { settings.darkThemeID = theme.id }
            else { settings.lightThemeID = theme.id }
        } else {
            settings.themeID = theme.id
        }
    }

    // MARK: - Resetting

    /// Reset just the Advanced-tab tuning (hitbox + space-bar cursor) to its
    /// defaults, leaving every other setting untouched. The single `settings`
    /// assignment persists once via `didSet`.
    func resetAdvancedSettings() {
        let d = KeyboardSettings.default
        settings.hitboxScale = d.hitboxScale
        settings.spaceCursorStride = d.spaceCursorStride
        settings.spaceCursorActivationDelay = d.spaceCursorActivationDelay
        settings.cursorMovementType = d.cursorMovementType
        settings.cursorLineStride = d.cursorLineStride
        settings.keyBloomScale = d.keyBloomScale
        settings.keySpringResponse = d.keySpringResponse
        settings.keySpringDamping = d.keySpringDamping
        settings.spaceSpringResponse = d.spaceSpringResponse
        settings.spaceSpringDamping = d.spaceSpringDamping
        settings.spaceLeanMultiplier = d.spaceLeanMultiplier
        settings.spaceCursorDragScale = d.spaceCursorDragScale
        settings.popupSpringResponse = d.popupSpringResponse
        settings.popupSpringDamping = d.popupSpringDamping
        settings.repeatHoldDelay = d.repeatHoldDelay
        settings.repeatInitialInterval = d.repeatInitialInterval
        settings.repeatMinInterval = d.repeatMinInterval
        settings.repeatAccelStep = d.repeatAccelStep
        settings.accentHoldDelay = d.accentHoldDelay
        settings.accentMoveCancel = d.accentMoveCancel
        settings.emojiToneHoldDelay = d.emojiToneHoldDelay
        settings.dragUpThreshold = d.dragUpThreshold
    }

    /// Reset everything to factory defaults, but KEEP user-created content — the
    /// custom themes, their imported background photos, and per-emoji skin
    /// tones — since those can't be recovered. Selection falls back to the
    /// default theme.
    func resetAllSettings() {
        var d = KeyboardSettings.default
        d.customThemes = settings.customThemes
        d.emojiSkinTones = settings.emojiSkinTones
        settings = d
    }

    // MARK: - Configuration export / import

    /// The whole configuration encoded as JSON, for a `.clinkconfig` export.
    func exportedConfiguration() -> Data? {
        try? JSONEncoder().encode(settings)
    }

    /// Replace the entire configuration with an imported snapshot. A full
    /// restore — the imported file's themes, mechanics, and tuning all take
    /// over. The single assignment persists once via `didSet`.
    func importConfiguration(_ imported: KeyboardSettings) {
        settings = imported
    }

    func refreshStatus() {
        let enabled = (UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String]) ?? []
        isKeyboardEnabled = enabled.contains(keyboardBundleID)
        hasFullAccess = store.lastKnownFullAccess
    }
}
