/**
 `AppModel`: app-wide observable state. Owns `KeyboardSettings`, persisting every
 change to the App Group so the keyboard extension picks it up instantly. Also
 exposes enable / Full Access status, clipboard, and notepad managers.
 

 Module: settings · Target: Clink
 Learn: docs/01-settings-and-storage.md
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
    let extensions = ExtensionManager()
    let panels = PanelManager()
    /// App Group store — every `settings` mutation goes through `save`.
    private let store = SharedStore.shared
    private let keyboardBundleID = "ltd.anti.clink.keyboard"

    init() {
        // Load persisted settings once. Subsequent UI edits assign through
        // `settings` and auto-save via `didSet`; init assignment does NOT fire `didSet`.
        settings = store.load()
        #if DEBUG
        // AppStage capture: seed a curated theme so the preview looks its best.
        // Assigning in init doesn't trigger `didSet`, so this never persists.
        if let slug = AppStage.slug {
            settings = AppStage.settings(for: slug)
        }
        // Daily OS-collected animation hitch + hang metrics, logged to console.
        MotionMetrics.shared.start()
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

    /// Staged import: decoded theme waiting for user confirmation. Set by
    /// `importTheme(from:)`; consumed by `confirmThemeImport()`.
    var pendingThemeImport: Theme? = nil

    /// Staged import: raw config data waiting for user confirmation. Set by
    /// `importConfigurationFromURL(_:)`; consumed by `confirmConfigImport()`.
    var pendingConfigImport: Data? = nil

    /// Parse a shared `.clinktheme` URL and stage it for confirmation instead of
    /// applying immediately — lets the UI show a preview sheet first.
    func importTheme(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              var theme = try? JSONDecoder().decode(Theme.self, from: data) else { return }
        theme.id = "custom-\(UUID().uuidString.prefix(8))"
        pendingThemeImport = theme
    }

    /// Apply the staged theme import and clear the pending state.
    func confirmThemeImport() {
        guard let theme = pendingThemeImport else { return }
        saveCustomTheme(theme)
        if settings.matchSystemAppearance {
            if theme.isDark { settings.darkThemeID = theme.id }
            else { settings.lightThemeID = theme.id }
        } else {
            settings.themeID = theme.id
        }
        pendingThemeImport = nil
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
        settings.glassBloomFactor = d.glassBloomFactor
        settings.glassReleaseResponse = d.glassReleaseResponse
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

    // Theme identity fields are never written to or read from .clinkconfig files.
    // Themes travel separately as .clinktheme; config covers everything else.
    private static let themeConfigKeys: Set<String> = [
        "themeID", "lightThemeID", "darkThemeID", "customThemes"
    ]

    /// Non-theme settings encoded as JSON, for a `.clinkconfig` export.
    func exportedConfiguration() -> Data? {
        guard let data = try? JSONEncoder().encode(settings),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        Self.themeConfigKeys.forEach { dict.removeValue(forKey: $0) }
        return try? JSONSerialization.data(withJSONObject: dict)
    }

    /// Apply imported settings without touching the current theme state.
    func importConfiguration(from data: Data) {
        guard var importedDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let currentData = try? JSONEncoder().encode(settings),
              let currentDict = try? JSONSerialization.jsonObject(with: currentData) as? [String: Any] else { return }
        for key in Self.themeConfigKeys {
            if let val = currentDict[key] { importedDict[key] = val }
        }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: importedDict),
              let merged = try? JSONDecoder().decode(KeyboardSettings.self, from: mergedData) else { return }
        settings = merged
    }

    /// Parse a shared `.clinkconfig` URL and stage it for confirmation instead of
    /// applying immediately — lets the UI show a warning dialog first.
    func importConfigurationFromURL(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        pendingConfigImport = data
    }

    /// Apply the staged config import and clear the pending state.
    func confirmConfigImport() {
        guard let data = pendingConfigImport else { return }
        importConfiguration(from: data)
        pendingConfigImport = nil
    }

    /// Reads enable / Full Access from UserDefaults + the App Group snapshot
    /// the extension last reported. Called on launch and when returning active.
    func refreshStatus() {
        let enabled = (UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String]) ?? []
        isKeyboardEnabled = enabled.contains(keyboardBundleID)
        hasFullAccess = store.lastKnownFullAccess
    }
}
