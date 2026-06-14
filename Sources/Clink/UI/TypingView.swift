/**
 Typing — how the keyboard moves and responds, under one page with four tabs:

   • Animation — press springs, bloom, and the optional effects.
   • Popups    — key popup style and spring.
   • Cursor    — space-bar cursor movement and feel.
   • Gestures  — swipe typing, the glide trail, and backspace.

 Merges the former Animation, Popups, Cursor, and Gestures pages to cut Home cards
 and sidebar rows. The pinned preview adapts per tab (the Cursor tab runs it in
 locked cursor-drag mode). `$model.settings` persists via `AppModel.settings` `didSet`.


 Module: app-ui · Target: Clink
 Learn: docs/12-motion.md
 */
import SwiftUI
import iUXiOS

/// Animation, popups, cursor, and gestures — four tabs sharing one pinned preview.
struct TypingView: View {
    private enum Tab { case animation, popups, cursor, gestures }

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: Tab = .animation

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(
            settings: model.settings,
            // The Cursor tab demos cursor drags on a locked sentence; other tabs
            // use the normal preview.
            previewCursorActive: selectedTab == .cursor
                && model.settings.cursorMovementType != .spacebar,
            lockedPreviewText: selectedTab == .cursor
                ? "The quick brown fox jumps over the lazy dog" : nil,
            bottomBar: AnyView(
                ThemedTabPicker(
                    options: [("Animation", Tab.animation), ("Popups", Tab.popups),
                              ("Cursor", Tab.cursor), ("Gestures", Tab.gestures)],
                    selection: $selectedTab)
            )) {
            switch selectedTab {
            case .animation: AnimationControls()
            case .popups:    PopupsControls()
            case .cursor:    CursorControls()
            case .gestures:  GesturesControls()
            }
        }
        .tint(themeAccent)
        .navigationTitle("Typing")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview { TypingView().clinkPreview() }
#endif
