/**
 Advanced-mode granular pages. Each wraps a shared `…Controls` content view (the
 same content the merged Simple-mode pages — Feel / Text / Typing / Keys — show as
 tabs) in its own `PinnedPreviewLayout`. These per-feature pages are surfaced on
 Home and in the sidebar only when `settings.advancedSettings` is on; Simple mode
 shows the merged pages instead. See `ClinkContent` / `SidebarPanel`.


 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

/// Shared chrome for a granular page: pinned preview + themed tint + title.
private struct GranularPage<Content: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var showHitboxOverlay: Bool = false
    var previewCursorActive: Bool = false
    var lockedPreviewText: String? = nil
    @ViewBuilder var content: Content

    private var accent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    var body: some View {
        PinnedPreviewLayout(settings: model.settings,
                            showHitboxOverlay: showHitboxOverlay,
                            previewCursorActive: previewCursorActive,
                            lockedPreviewText: lockedPreviewText) {
            content
        }
        .tint(accent)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Typing-group pages

struct AnimationPage: View {
    var body: some View { GranularPage(title: "Animation") { AnimationControls() } }
}
struct PopupsPage: View {
    var body: some View { GranularPage(title: "Popups") { PopupsControls() } }
}
struct CursorPage: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        GranularPage(title: "Cursor",
                     previewCursorActive: model.settings.cursorMovementType != .spacebar,
                     lockedPreviewText: "The quick brown fox jumps over the lazy dog") {
            CursorControls()
        }
    }
}
struct GesturesPage: View {
    var body: some View { GranularPage(title: "Gestures") { GesturesControls() } }
}

// MARK: - Feel-group pages

struct SoundsPage: View {
    var body: some View { GranularPage(title: "Sounds") { SoundControls() } }
}
struct HapticsPage: View {
    var body: some View { GranularPage(title: "Haptics") { HapticControls() } }
}

// MARK: - Text-group pages

struct SuggestionsPage: View {
    var body: some View { GranularPage(title: "Suggestions") { SuggestionsControls() } }
}
struct AutomationPage: View {
    var body: some View { GranularPage(title: "Automation") { AutomationControls() } }
}
struct AdaptationPage: View {
    var body: some View { GranularPage(title: "Adaptation") { AdaptationControls() } }
}

// MARK: - Keys-group pages

struct KeyGeometryPage: View {
    var body: some View { GranularPage(title: "Keys") { KeyGeometryControls() } }
}
struct HitboxesPage: View {
    var body: some View { GranularPage(title: "Hitboxes", showHitboxOverlay: true) { HitboxControls() } }
}
struct LayoutPage: View {
    @Environment(AppModel.self) private var model
    @State private var keyEditing: CustomKeysView.KeyEdit?

    var body: some View {
        @Bindable var model = model
        GranularPage(title: "Layout") {
            LayoutControls(editing: $keyEditing)
        }
        .themedSheet(isPresented: Binding(get: { keyEditing != nil },
                                          set: { if !$0 { keyEditing = nil } }),
                     title: "Custom key") {
            if let edit = keyEditing {
                CustomKeyEditorBody(
                    initial: edit.key,
                    canRemove: edit.index != nil,
                    onSave: { saved in
                        CustomKeysView.commit(model: model, edit: edit, key: saved)
                        keyEditing = nil
                    },
                    onRemove: {
                        CustomKeysView.remove(model: model, edit: edit)
                        keyEditing = nil
                    })
            }
        }
    }
}
