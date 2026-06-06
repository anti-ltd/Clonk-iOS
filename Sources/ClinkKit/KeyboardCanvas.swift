import SwiftUI
import UIKit

/// The Clink keyboard, as a pure SwiftUI view. Lives in ClinkKit so that the
/// keyboard *extension* renders it live (wired to the document proxy + sound)
/// and the container *app* renders the very same view as a true-to-life
/// preview — there is no second, drifting "preview" implementation.
///
/// The canvas owns transient UI state (shift, which symbol plane is showing)
/// and reports only two document-affecting actions back to its host —
/// `onInsert` and `onBackspace` — plus `onAnyTap` (fired on every key-down so
/// the host can clink + haptic) and an optional `onNextKeyboard` (the globe
/// key; the app preview passes nil to hide it).
/// Animation physics for key presses — bloom scale, spring response/damping —
/// built from `KeyboardSettings` so every tuning value travels in the exported config.
struct KeyPressPhysics {
    var bloomScale: CGFloat          = 1.12
    var springResponse: Double       = 0.26
    var springDamping: Double        = 0.60
    var spaceSpringResponse: Double  = 0.28
    var spaceSpringDamping: Double   = 0.78
    var spaceLeanMultiplier: CGFloat = 0.14
    var spaceCursorDragScale: CGFloat = 0.90
    var popupSpringResponse: Double  = 0.32
    var popupSpringDamping: Double   = 0.62
}

public struct KeyboardCanvas: View {
    private let settings: KeyboardSettings
    private let onInsert: (String) -> Void
    private let onBackspace: () -> Void
    private let onAnyTap: () -> Void
    private let onNextKeyboard: (() -> Void)?
    private let onSuggestion: (String) -> Void
    /// Fired when the user taps an emoji chip in the bar — inserts that emoji
    /// (replacing the word being typed). Distinct from `onSuggestion` so it never
    /// gets the word+space treatment.
    private let onEmojiSuggestion: (String) -> Void
    /// Fired when the user taps their literal word to reject the pending
    /// auto-correction (the quoted "keep what I typed" chip).
    private let onCancelAutocorrect: () -> Void
    /// Fired while dragging the space bar — a signed character delta to move the
    /// cursor by (the native space-bar trackpad).
    private let onCursorMove: (Int) -> Void
    /// Fired when the user taps a clipboard chip — the host inserts the text at
    /// the cursor and dismisses clipboard mode.
    private let onClipboardInsert: (String) -> Void
    /// Fired when the user dumps the notepad buffer (or taps a saved note) into
    /// the host document. Distinct from `onClipboardInsert` only for clarity.
    private let onNotepadInsert: (String) -> Void
    /// When true, render a semi-transparent hitbox outline over each key so the
    /// user can see exactly which area maps to each key. Used by the Advanced
    /// settings view; false for normal use.
    private let showHitboxOverlay: Bool
    /// Whether the keyboard extension currently has Full Access. Gating
    /// clipboard (which reads UIPasteboard) on this prevents a sandboxed crash.
    private let hasFullAccess: Bool

    /// Live typing state (autocomplete suggestions). The extension feeds it;
    /// the in-app preview can pass sample words. Observed so the bar updates
    /// without rebuilding the keyboard.
    private var live: KeyboardLiveState

    /// Clipboard history — observed so the bar updates when history changes.
    private var clipboard: ClipboardManager

    /// Quick-notepad store — observed so the compose buffer / notes list update.
    private var notepad: NotepadManager

    public init(
        settings: KeyboardSettings,
        live: KeyboardLiveState = KeyboardLiveState(),
        controller: KeyboardController? = nil,
        clipboard: ClipboardManager = ClipboardManager(),
        notepad: NotepadManager = NotepadManager(),
        hasFullAccess: Bool = false,
        showHitboxOverlay: Bool = false,
        onInsert: @escaping (String) -> Void,
        onBackspace: @escaping () -> Void,
        onAnyTap: @escaping () -> Void = {},
        onNextKeyboard: (() -> Void)? = nil,
        onSuggestion: @escaping (String) -> Void = { _ in },
        onEmojiSuggestion: @escaping (String) -> Void = { _ in },
        onCancelAutocorrect: @escaping () -> Void = {},
        onCursorMove: @escaping (Int) -> Void = { _ in },
        onClipboardInsert: @escaping (String) -> Void = { _ in },
        onNotepadInsert: @escaping (String) -> Void = { _ in }
    ) {
        self.settings = settings
        self.live = live
        // Use the injected controller (the showcase simulator drives a shared
        // one) or spin up a private one for ordinary finger-driven use.
        _controller = State(initialValue: controller ?? KeyboardController())
        self.clipboard = clipboard
        self.notepad = notepad
        self.hasFullAccess = hasFullAccess
        self.showHitboxOverlay = showHitboxOverlay
        self.onInsert = onInsert
        self.onBackspace = onBackspace
        self.onAnyTap = onAnyTap
        self.onNextKeyboard = onNextKeyboard
        self.onSuggestion = onSuggestion
        self.onEmojiSuggestion = onEmojiSuggestion
        self.onCancelAutocorrect = onCancelAutocorrect
        self.onCursorMove = onCursorMove
        self.onClipboardInsert = onClipboardInsert
        self.onNotepadInsert = onNotepadInsert
    }

    private typealias Plane = KeyboardController.Plane
    private typealias Shift = KeyboardController.Shift

    /// Transient keyboard state (plane / shift / simulated press). Held as a
    /// reference type so it can be shared with an external typing simulator.
    @State private var controller: KeyboardController

    /// Routes raw multitouch from a single UIKit surface to the keys, so fast
    /// overlapping presses register independently (see `KeyTouchRouter`). Each
    /// `KeyView` reads its pressed / warp state back out of this.
    @State private var touch = KeyTouchRouter()

    /// Track whether the last key pressed was sentence punctuation, so we can
    /// return to letters when the space bar is tapped (rather than immediately).
    @State private var lastKeyWasPunctuation = false

    /// The panel picker is showing (only meaningful when 2+ panels are enabled).
    /// For `.popover` it floats a menu; for `.inline` it expands the bar.
    @State private var pickerOpen = false

    /// While the notepad is in `notes` mode, whether the saved-notes archive is
    /// taking over the full keyboard (browsing) versus the inline compose strip.
    @State private var notepadBrowsing = false

    // Proxy the canvas's existing `plane` / `shift` reads & writes onto the
    // controller, so the rest of the view is untouched. `nonmutating set` works
    // because `controller` is a class — mutating it doesn't mutate the struct.
    private var plane: Plane {
        get { controller.plane }
        nonmutating set { controller.plane = newValue }
    }
    private var shift: Shift {
        get { controller.shift }
        nonmutating set { controller.shift = newValue }
    }

    /// The system appearance, so a "match system" setting can flip the theme
    /// live between its light and dark choice. In the extension this tracks the
    /// host app's appearance; in the app preview it tracks the app's.
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { settings.resolvedTheme(dark: colorScheme == .dark) }

    private var physics: KeyPressPhysics {
        KeyPressPhysics(
            bloomScale: CGFloat(settings.keyBloomScale),
            springResponse: settings.keySpringResponse,
            springDamping: settings.keySpringDamping,
            spaceSpringResponse: settings.spaceSpringResponse,
            spaceSpringDamping: settings.spaceSpringDamping,
            spaceLeanMultiplier: CGFloat(settings.spaceLeanMultiplier),
            spaceCursorDragScale: CGFloat(settings.spaceCursorDragScale),
            popupSpringResponse: settings.popupSpringResponse,
            popupSpringDamping: settings.popupSpringDamping)
    }

    /// The keyboard backdrop: clear unless the theme opts in, then a photo (when
    /// `backgroundImageID` resolves to a stored image) or the solid colour. The
    /// photo fills the keyboard region and is clipped to it; clipping lives on the
    /// image — never on the whole canvas — so key popups can still balloon above.
    @ViewBuilder private var backgroundLayer: some View {
        if settings.backgroundVisible {
            if let id = theme.backgroundImageID,
               let image = ThemeBackgroundStore.shared.image(for: id) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else if let gradient = theme.backgroundGradient {
                gradient.makeView()
            } else {
                theme.background.color
            }
        } else {
            Color.clear
        }
    }

    /// Shared vertical metrics — also used by the extension to size the keyboard
    /// to its content (no dead space above / below the keys).
    public enum Metrics {
        public static let vPadding: CGFloat = 4
        public static let suggestionBarHeight: CGFloat = 44
        /// The default row height, used when a settings value isn't supplied.
        public static let defaultRowHeight: CGFloat = 46
    }

    /// The exact content height for a given configuration, so the host can pin
    /// the keyboard to it instead of guessing and centering.
    public static func preferredHeight(for settings: KeyboardSettings, hasFullAccess: Bool = false) -> CGFloat {
        let key = CGFloat(settings.keyHeight)
        var rows = settings.layout.rows.count + 1   // letter rows + bottom row
        // The number row carries its own (possibly reduced) height; every other
        // row is a full key tall.
        var h = CGFloat(rows) * key
        if settings.showNumberRow {
            rows += 1
            h += key * CGFloat(settings.numberRowHeightScale)
        }
        h += CGFloat(rows - 1) * CGFloat(settings.rowSpacing) + Metrics.vPadding * 2
        // The bar is present for suggestions, or for the panel icon when icon
        // activation is on and at least one panel is enabled. (Slide-up-only
        // activation adds no permanent bar — the picker is transient.)
        let anyPanel = (settings.clipboardEnabled && hasFullAccess)
            || settings.notepadEnabled || settings.emojiEnabled
        if settings.suggestionsEnabled || (settings.activateWithIcon && anyPanel) {
            h += Metrics.suggestionBarHeight
        }
        return h
    }

    /// True while the held-space trackpad is engaged — the keyboard's visible
    /// chrome (bar, keys, glyphs) hides so only the move glyph shows over the
    /// keyboard's backdrop. The touch surface stays live underneath (it is never
    /// faded), so the in-progress drag keeps tracking.
    private var trackpadActive: Bool {
        settings.cursorMovementType == .trackpad && touch.spaceCursorActive
    }

    /// Combined cursor mode WHILE the space bar is held into cursor drag: the keys
    /// stay on screen but blank their letters and go inert, and the space bar
    /// morphs. The keyboard is fully normal otherwise. Distinct from
    /// `trackpadActive`, which hides the keyboard entirely.
    private var combinedActive: Bool {
        settings.cursorMovementType == .combined && touch.spaceCursorActive
    }

    // MARK: - Action panels (clipboard / notepad)

    /// The panels available right now, in display order. Clipboard needs Full
    /// Access (it reads the pasteboard); notepad and emoji do not.
    private var enabledPanels: [ActionPanel] {
        var panels: [ActionPanel] = []
        if settings.clipboardEnabled && hasFullAccess { panels.append(.clipboard) }
        if settings.notepadEnabled { panels.append(.notepad) }
        if settings.emojiEnabled { panels.append(.emoji) }
        return panels
    }

    /// Whether a panel takes over the whole keyboard (true overlay) rather than
    /// living in the bar strip with the keys still visible. Clipboard honours its
    /// style setting; the notepad only goes full-screen while browsing its saved
    /// notes archive. Emoji never renders inside this canvas (it swaps to the
    /// separate `EmojiCanvas`), so it's never an in-canvas overlay.
    private func panelIsOverlay(_ panel: ActionPanel) -> Bool {
        switch panel {
        case .clipboard: return settings.clipboardStyle == .overlay
        case .notepad:   return settings.notepadMode == .notes && notepadBrowsing
        case .emoji:     return false
        }
    }

    /// The panel currently rendered as a full-keyboard overlay, if any.
    private var overlayPanel: ActionPanel? {
        guard let active = live.activePanel, panelIsOverlay(active) else { return nil }
        return active
    }

    /// True when the inline picker should expand across the bar.
    private var pickerInlineExpanded: Bool {
        pickerOpen && settings.panelPickerStyle == .inline && enabledPanels.count >= 2
    }

    /// True when the cards picker should take over the whole keyboard.
    private var pickerCardsActive: Bool {
        pickerOpen && settings.panelPickerStyle == .cards && enabledPanels.count >= 2
    }

    /// SF Symbol for the top-left button: the active panel's filled icon, the lone
    /// enabled panel's icon, or a neutral grid when a picker is needed.
    private var panelButtonIcon: String {
        if let active = live.activePanel { return active.icon(active: true) }
        let panels = enabledPanels
        if panels.count == 1 { return panels[0].icon(active: false) }
        return "square.grid.2x2"
    }

    /// Tap behaviour of the top-left button. One panel → toggle it. Many panels →
    /// close the open one, else open the picker.
    private func panelButtonTapped() {
        let panels = enabledPanels
        if panels.count == 1 {
            togglePanel(panels[0])
        } else if live.activePanel != nil {
            closePanel()
        } else {
            pickerOpen.toggle()
        }
    }

    /// Open a panel, dragging the 123 key up. Mirrors the button: lone panel
    /// opens directly, otherwise the picker.
    private func slideUpActivate() {
        let panels = enabledPanels
        guard !panels.isEmpty else { return }
        if panels.count == 1 {
            activate(panels[0])
        } else {
            withAnimation(.snappy(duration: 0.22)) { pickerOpen = true }
        }
    }

    private func togglePanel(_ panel: ActionPanel) {
        // Emoji lives in its own canvas — there's no "open emoji panel" state to
        // toggle off from here (you return via the emoji ABC key), so just open.
        if panel == .emoji { activate(.emoji); return }
        if live.activePanel == panel { closePanel() }
        else { live.activePanel = panel; pickerOpen = false }
    }

    /// Route a panel selection. Emoji flips the shared controller to swap in the
    /// emoji canvas; clipboard / notepad open in-place via `live.activePanel`.
    private func activate(_ panel: ActionPanel) {
        pickerOpen = false
        switch panel {
        case .emoji:
            withAnimation(.snappy(duration: 0.22)) { controller.showEmoji = true }
        case .clipboard, .notepad:
            live.activePanel = panel
        }
    }

    private func closePanel() {
        live.activePanel = nil
        pickerOpen = false
        notepadBrowsing = false
    }

    /// Collapse the picker (popover or inline) the moment a key is pressed — the
    /// user resumed typing rather than choosing a panel.
    private func dismissPickerOnInput() {
        guard pickerOpen else { return }
        withAnimation(.snappy(duration: 0.18)) { pickerOpen = false }
    }

    /// The top-left button (single icon) plus its divider, shown when at least
    /// one panel is enabled and the inline picker isn't expanded.
    @ViewBuilder private var actionPanelArea: some View {
        if settings.activateWithIcon && !enabledPanels.isEmpty {
            ActionPanelButton(systemName: panelButtonIcon,
                              isActive: live.activePanel != nil,
                              theme: theme,
                              hitboxScale: settings.panelButtonHitboxScale) {
                panelButtonTapped()
            }
            .frame(width: Metrics.suggestionBarHeight)
            .anchorPreference(key: BarHitboxKey.self, value: .bounds) { ["icon": $0] }
            barDivider(theme: theme)
        }
    }

    /// The bar's right-hand content: the active panel's inline strip, otherwise
    /// the suggestion bar (or empty filler).
    @ViewBuilder private var barContent: some View {
        if live.activePanel == .clipboard && settings.clipboardStyle == .bar {
            ClipboardBar(
                entries: clipboard.history, theme: theme,
                onTap: onClipboardInsert,
                onSave: { clipboard.captureFromPasteboard() },
                onClear: { clipboard.clear() }
            )
        } else if live.activePanel == .notepad {
            NotepadBar(
                text: notepad.scratch, mode: settings.notepadMode, theme: theme,
                onInsert: { onNotepadInsert(notepad.scratch) },
                onSave: { notepad.addNote(notepad.scratch); notepad.scratch = "" },
                onBrowse: { notepadBrowsing = true },
                onClear: { notepad.scratch = "" }
            )
        } else if settings.suggestionsEnabled {
            SuggestionBar(suggestions: live.suggestions,
                          autocorrection: live.autocorrection,
                          emoji: live.emojiSuggestions, theme: theme,
                          onTap: onSuggestion, onKeepTyped: onCancelAutocorrect,
                          onEmoji: onEmojiSuggestion,
                          hitboxScale: settings.suggestionHitboxScale)
                .anchorPreference(key: BarHitboxKey.self, value: .bounds) { ["bar": $0] }
        } else {
            Spacer()
        }
    }

    /// The inline picker: a close button then one labelled chip per panel,
    /// expanded across the whole bar.
    @ViewBuilder private var inlinePickerRow: some View {
        ActionPanelButton(systemName: "xmark", isActive: false, theme: theme) {
            pickerOpen = false
        }
        .frame(width: Metrics.suggestionBarHeight)
        barDivider(theme: theme)
        ForEach(Array(enabledPanels.enumerated()), id: \.element) { idx, panel in
            if idx > 0 { barDivider(theme: theme) }
            Button { activate(panel) } label: {
                HStack(spacing: 7) {
                    Image(systemName: panel.icon(active: false))
                        .font(.system(size: 15))
                    Text(panel.label)
                        .font(.system(size: 15))
                }
                .foregroundStyle(theme.keyText.color.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// The popover picker: a small floating menu under the button, over a
    /// transparent tap-to-dismiss catcher that fills the keyboard.
    private var panelPopover: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture { pickerOpen = false }
            VStack(spacing: 0) {
                ForEach(Array(enabledPanels.enumerated()), id: \.element) { idx, panel in
                    if idx > 0 {
                        Rectangle().fill(theme.keyText.color.opacity(0.12)).frame(height: 0.5)
                    }
                    Button { activate(panel) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: panel.icon(active: false))
                                .font(.system(size: 15))
                                .frame(width: 18)
                            Text(panel.label)
                                .font(.system(size: 15))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(theme.keyText.color)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 168)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.keyFill.color.opacity(0.35)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.keyText.color.opacity(0.12), lineWidth: 0.5))
            }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .padding(.leading, 6)
            .offset(y: Metrics.suggestionBarHeight - 4)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // The bar shows for suggestions, for the icon (when icon activation is
            // on and a panel exists), whenever a panel is open in-bar, or while
            // the inline picker is expanded (e.g. opened via slide-up).
            let showBar = settings.suggestionsEnabled
                || (settings.activateWithIcon && !enabledPanels.isEmpty)
                || live.activePanel != nil
                || pickerInlineExpanded

            if let overlay = overlayPanel {
                // Full-keyboard replacement: panel header + scrollable content.
                // No background set here — backgroundLayer renders behind it normally.
                switch overlay {
                case .emoji:
                    // Never an in-canvas overlay (it swaps to EmojiCanvas).
                    EmptyView()
                case .clipboard:
                    ClipboardPanel(
                        entries: clipboard.history,
                        theme: theme,
                        cornerRadius: CGFloat(settings.keyCornerRadius),
                        onTap: { text in onClipboardInsert(text) },
                        onSave: { clipboard.captureFromPasteboard() },
                        onDismiss: { closePanel() },
                        onCopy: { idx in
                            guard clipboard.history.indices.contains(idx) else { return }
                            UIPasteboard.general.string = clipboard.history[idx].text
                        },
                        onTogglePin: { idx in clipboard.togglePin(at: idx) },
                        onDelete: { idx in clipboard.delete(at: idx) },
                        onClear: { clipboard.clear() }
                    )
                case .notepad:
                    NotepadBrowsePanel(
                        notes: notepad.notes,
                        theme: theme,
                        cornerRadius: CGFloat(settings.keyCornerRadius),
                        onTap: { text in onNotepadInsert(text) },
                        onLoad: { text in notepad.scratch = text; notepadBrowsing = false },
                        onDelete: { idx in notepad.deleteNote(at: idx) },
                        onClear: { notepad.clearNotes() },
                        onDismiss: { notepadBrowsing = false }
                    )
                }
            } else if pickerCardsActive {
                // Cards picker: full-keyboard switcher, one card per panel.
                PanelSwitcherPanel(
                    panels: enabledPanels,
                    theme: theme,
                    cornerRadius: CGFloat(settings.keyCornerRadius),
                    onSelect: { activate($0) },
                    onDismiss: { pickerOpen = false }
                )
            } else {
                // The whole suggestion/panel bar is removed while the trackpad
                // is live — nothing but the move glyph should show. (Keys stay
                // rendered but invisible below, so the touch surface keeps frames.)
                if showBar && !trackpadActive {
                    HStack(spacing: 0) {
                        if pickerInlineExpanded {
                            inlinePickerRow
                        } else {
                            actionPanelArea
                            barContent
                        }
                    }
                    .frame(height: Metrics.suggestionBarHeight)
                }
                keys
                    .backgroundPreferenceValue(KeyFrameKey.self) { anchors in
                        keyImageLayer(anchors: anchors)
                    }
                    // Hide the keys (and their glass backdrop) while the trackpad
                    // is live — the move glyph shows alone. The touch surface is
                    // added AFTER this opacity, so it stays fully live for the drag.
                    .opacity(trackpadActive ? 0 : 1)
                    .padding(.vertical, Metrics.vPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlayPreferenceValue(KeyFrameKey.self) { anchors in
                        GeometryReader { proxy in
                            MultiTouchSurface(
                                router: touch,
                                frames: anchors.mapValues { proxy[$0] },
                                resolveSpec: { currentKeySpecs()[$0] },
                                // Pressing any key while the picker is open
                                // dismisses it — the user's typing, not choosing.
                                onPressDown: { dismissPickerOnInput(); onAnyTap() },
                                lingerDuration: settings.keyPressLinger,
                                hitboxScale: settings.hitboxScale,
                                cursorStride: CGFloat(settings.spaceCursorStride),
                                cursorActivationDelay: settings.spaceCursorActivationDelay / 1000,
                                cursorLineStride: Int(settings.cursorLineStride),
                                cursorCombined: settings.cursorMovementType == .combined,
                                repeatHoldDelay: settings.repeatHoldDelay / 1000,
                                repeatInitialInterval: Int(settings.repeatInitialInterval),
                                repeatMinInterval: Int(settings.repeatMinInterval),
                                repeatAccelStep: Int(settings.repeatAccelStep))
                        }
                    }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: live.activePanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: pickerOpen)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: notepadBrowsing)
        // Backdrop. By default transparent so the keyboard blends with whatever
        // sits behind it — iOS's own keyboard surface in the extension, the
        // preview's backdrop in-app — and only the keys carry colour, reading as
        // floating keys rather than an opaque slab. When the global
        // `settings.backgroundVisible` switch is on, we paint the active theme's
        // background — a photo if one's set, otherwise its solid `background`
        // colour — behind the keys.
        .background { backgroundLayer }
        // Glyph layer: every key's letter, drawn ON TOP of the glass container so
        // the morph (which blends a bloomed key into its neighbours) can't drag
        // the glyph off-centre. Each glyph blooms in place with its key.
        .overlayPreferenceValue(KeyGlyphKey.self) { glyphs in
            GeometryReader { proxy in
                ForEach(glyphs) { g in
                    glyphLabel(g)
                        .scaleEffect(x: g.scaleX, y: g.scaleY, anchor: .center)
                        // Offset rides BEFORE the spring: while dragging, only
                        // `g.offsetX` changes (scale is constant) so it tracks the
                        // finger live — no spring backlog. On release the scale flips
                        // too, so the spring fires and carries the offset back to
                        // centre in sync with the bar, instead of snapping.
                        .offset(x: g.offsetX)
                        .position(x: proxy[g.anchor].midX, y: proxy[g.anchor].midY)
                        .animation(.interactiveSpring(response: settings.keySpringResponse, dampingFraction: settings.keySpringDamping), value: g.scaleX)
                }
            }
            .allowsHitTesting(false)
            // Blank the key letters while the trackpad covers them, and always in
            // combined mode (the keys stay visible but show no glyphs).
            .opacity(trackpadActive || combinedActive ? 0 : 1)
        }
        // Single popup layer above every key — its shape follows the chosen style.
        .overlayPreferenceValue(KeyPopupKey.self) { popup in
            GeometryReader { proxy in
                if let popup {
                    popup_view(popup.glyph, keyRect: proxy[popup.anchor], bounds: proxy.size)
                }
            }
            .allowsHitTesting(false)
            .opacity(trackpadActive ? 0 : 1)
        }
        // Hitbox debug overlay: outlines each key's touch area. Only visible in
        // the Advanced settings view (showHitboxOverlay = true).
        .overlayPreferenceValue(KeyFrameKey.self) { anchors in
            if showHitboxOverlay {
                GeometryReader { proxy in
                    let scale = CGFloat(settings.hitboxScale)
                    ForEach(anchors.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                        let f = proxy[pair.value]
                        let w = f.width * scale
                        let h = f.height * scale
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.cyan.opacity(0.75), lineWidth: 1.5)
                            .frame(width: w, height: h)
                            .position(x: f.midX, y: f.midY)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        // Hitbox debug overlay for the suggestion bar + panel icon: same cyan
        // outline as the keys, scaled vertically by their own multipliers. Only
        // the anchors that are actually rendered (bar / icon when enabled) appear.
        .overlayPreferenceValue(BarHitboxKey.self) { anchors in
            if showHitboxOverlay {
                GeometryReader { proxy in
                    ForEach(anchors.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                        let f = proxy[pair.value]
                        let scale = pair.key == "icon"
                            ? settings.panelButtonHitboxScale
                            : settings.suggestionHitboxScale
                        let h = f.height * CGFloat(scale)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.cyan.opacity(0.75), lineWidth: 1.5)
                            .frame(width: f.width, height: h)
                            .position(x: f.midX, y: f.midY)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        // Trackpad cursor glyph: while the space bar is held into cursor mode and
        // the user chose the trackpad type, the keyboard chrome above is hidden, so
        // only this centred move glyph shows over the keyboard's own backdrop
        // (which still paints behind the now-hidden keys, or stays clear when the
        // background switch is off). Purely visual — `allowsHitTesting(false)`.
        .overlay {
            if trackpadActive {
                TrackpadPanel(theme: theme)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: touch.spaceCursorActive)
        // Floating picker menu (popover style) — anchored under the top-left
        // button, with a transparent catcher behind it to tap-dismiss. Added LAST
        // so it sits above the key-glyph overlay (which is itself an overlay layer
        // — otherwise the letters behind the menu bleed through it).
        .overlay(alignment: .topLeading) {
            if pickerOpen && settings.panelPickerStyle == .popover && enabledPanels.count >= 2 {
                panelPopover
            }
        }
    }

    /// One key's glyph for the on-top glyph layer (text or animated symbol).
    @ViewBuilder private func glyphLabel(_ g: KeyGlyphInfo) -> some View {
        Group {
            if g.isSystem {
                Image(systemName: g.glyph)
                    .font(.system(size: 18, weight: .medium))
                    // Animate symbol swaps both ways — e.g. the return glyph
                    // tracking the host field (return ⇄ go ⇄ send …).
                    .contentTransition(.symbolEffect(.replace))
                    // Bounce on each held-delete repeat (no-op elsewhere).
                    .symbolEffect(.bounce, value: g.deleteTick)
                    // Pin identity to the symbol name. A press re-renders the
                    // same identity (name unchanged) → the replace transition
                    // has nothing to cross-fade, so it can't mis-fire and drop
                    // the glyph (the intermittent delete-icon vanish). A real
                    // name swap changes identity and still animates below.
                    .id(g.glyph)
                    .animation(.snappy(duration: 0.25), value: g.glyph)
            } else {
                Text(g.glyph)
                    .font(.system(size: g.fontSize ?? (g.multiChar ? 16 : 22),
                                  weight: theme.keyFontWeight.fontWeight,
                                  design: theme.keyFontDesign.fontDesign))
            }
        }
        .foregroundStyle(g.color)
        .opacity(g.hidden ? 0 : 1)
    }

    /// Corner radius shared by the popup chrome — tracks the key roundness, a
    /// touch tighter so the larger popup doesn't read as rounder than the keys.
    private var popupCorner: CGFloat { max(CGFloat(settings.keyCornerRadius) - 2, 0) }

    @ViewBuilder private func popup_view(_ glyph: String, keyRect: CGRect, bounds: CGSize) -> some View {
        switch settings.keyPopupStyle {
        case .floating:
            positioned(tilePopup(glyph, width: 48, height: 56, fontSize: 30),
                       height: 56, centerY: keyRect.minY - 30, midX: keyRect.midX, bounds: bounds)
        case .balloon:
            balloonPopup(glyph, keyRect: keyRect, bounds: bounds)
        }
    }

    /// Place a popup, clamping it inside the keyboard so the top row's bubble is
    /// never cut off by the keyboard's top edge (an extension can't draw past it).
    private func positioned<V: View>(_ content: V, height: CGFloat,
                                     centerY: CGFloat, midX: CGFloat, bounds: CGSize) -> some View {
        let clamped = max(centerY, height / 2 + 2)
        return content.position(x: midX, y: clamped)
    }

    /// A rounded-rectangle popup (the floating style).
    private func tilePopup(_ glyph: String, width: CGFloat, height: CGFloat, fontSize: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: popupCorner, style: .continuous)
        return Text(glyph)
            .font(.system(size: fontSize,
                          weight: theme.keyFontWeight.fontWeight,
                          design: theme.keyFontDesign.fontDesign))
            .foregroundStyle(theme.keyText.color)
            .frame(width: width, height: height)
            .modifier(PopupChrome(shape: shape, theme: theme,
                                  glass: theme.material == .liquidGlass && settings.liquidGlassPopup))
    }

    /// A balloon drawn as one continuous shape over the whole pressed key: the
    /// bulb swells up out of the key, sharing its width / corner radius / accent
    /// tint, so there is no seam between popup and key. The magnified glyph rides
    /// in the bulb; the key's own footprint is covered by the balloon's foot. The
    /// bulb is bottom-anchored to the key (so it always lines up) and rises above
    /// — clamped so the top row's bulb doesn't poke past the keyboard's top edge.
    private func balloonPopup(_ glyph: String, keyRect: CGRect, bounds: CGSize) -> some View {
        // Wide rounded-rect head (~1.4× the key) on a short neck above the key.
        let headWidth = max(keyRect.width * 1.4, 48)
        let headHeight: CGFloat = 40
        let neck: CGFloat = 16
        let bulbRise = headHeight + neck                 // head + neck above the key top
        let top = max(2, keyRect.minY - bulbRise)
        let bottom = keyRect.maxY
        let totalHeight = bottom - top
        let shoulderY = keyRect.minY - top               // key's top edge within the frame
        let keyCorner = CGFloat(settings.keyCornerRadius)
        let shape = BalloonPopupShape(keyWidth: keyRect.width, headHeight: headHeight,
                                      shoulderY: shoulderY, topCorner: max(popupCorner, 14),
                                      bottomCorner: keyCorner)
        // Magnified glyph centred in the head.
        let glyphOffset = headHeight * 0.5 - totalHeight / 2
        // Full accent — the balloon covers the key, so it reads as the active key.
        let tint = theme.accent.color
        return BalloonPopup(glyph: glyph, bulbWidth: headWidth, totalHeight: totalHeight,
                            glyphOffset: glyphOffset, shape: shape, tint: tint, theme: theme,
                            glass: theme.material == .liquidGlass && settings.liquidGlassPopup,
                            springResponse: settings.popupSpringResponse,
                            springDamping: settings.popupSpringDamping)
            .position(x: keyRect.midX, y: (top + bottom) / 2)
    }

    /// The Liquid-Glass key-image backdrop: one photo spanning the key area,
    /// masked to the union of the key shapes so only the keys reveal it (each key
    /// shows the slice behind it). Drawn behind the keys, it becomes the backdrop
    /// the glass refracts. Nil unless this is a glass theme with a resolvable
    /// `keyImageID`.
    @ViewBuilder private func keyImageLayer(anchors: [String: Anchor<CGRect>]) -> some View {
        if theme.material == .liquidGlass {
            if let id = theme.keyImageID,
               let image = ThemeBackgroundStore.shared.image(for: id) {
                GeometryReader { proxy in
                    let rects = anchors.values.map { proxy[$0] }
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .mask { keyMaskShapes(rects: rects) }
                }
            } else if let gradient = theme.keyGradient {
                GeometryReader { proxy in
                    let rects = anchors.values.map { proxy[$0] }
                    gradient.makeView()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .mask { keyMaskShapes(rects: rects) }
                }
            }
        }
    }

    @ViewBuilder private func keyMaskShapes(rects: [CGRect]) -> some View {
        ZStack {
            ForEach(Array(rects.enumerated()), id: \.offset) { _, r in
                RoundedRectangle(cornerRadius: CGFloat(settings.keyCornerRadius), style: .continuous)
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)
            }
        }
    }

    /// The stack of rows, wrapped in a `GlassEffectContainer` for Liquid Glass
    /// themes (iOS 26+) so adjacent keys blend / morph correctly.
    @ViewBuilder private var keys: some View {
        // The keys occupy `keyWidthFraction` of the width; the rest splits into
        // symmetric side margins (atop a 4pt base inset so keys never touch the
        // edges). Measured here so the per-row geometry sees the reduced width.
        GeometryReader { geo in
            let sideInset = 4 + geo.size.width * (1 - CGFloat(settings.keyWidthFraction)) / 2
            rowStack(usableWidth: geo.size.width - sideInset * 2)
                .padding(.horizontal, sideInset)
        }
    }

    @ViewBuilder private func rowStack(usableWidth: CGFloat) -> some View {
        let rows = currentRows
        // ~half a key per side, so the home row's keys line up under the gaps of
        // the row above — the native keyboard's signature middle-row indent.
        let homeInset = usableWidth * CGFloat(settings.homeRowInsetAmount)
        let stack = VStack(spacing: CGFloat(settings.rowSpacing)) {
            if settings.showNumberRow, plane == .letters {
                row(KeyboardLayout.numberRows[0].map { plainKey($0, fontSize: CGFloat(settings.numberRowFontSize)) },
                    rowID: "num",
                    fixedHeight: CGFloat(settings.keyHeight) * CGFloat(settings.numberRowHeightScale))
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, r in
                // The middle letter row (index 1 of a 3-row letter layout) is
                // the home row — the only one iOS indents.
                let isHomeRow = plane == .letters && rows.count == 3 && idx == 1
                row(r, rowID: "r\(idx)")
                    .padding(.horizontal, isHomeRow && settings.homeRowInset ? homeInset : 0)
            }
            bottomRow
        }
        // The glass *backgrounds* live in the container so a bloomed key blends
        // into its neighbours (the liquid merge). The glyphs are drawn in a
        // separate layer on top of this (see `glyphLayer`), out of the morph's
        // reach, so they stay centred.
        if theme.material == .liquidGlass, #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: CGFloat(settings.keySpacing)) { stack }
        } else {
            stack
        }
    }

    // MARK: - Plane → rows

    private var currentRows: [[KeySpec]] {
        switch plane {
        case .letters:
            let rows = settings.layout.rows
            return rows.enumerated().map { idx, keys in
                if idx == rows.count - 1 {
                    // Last letter row gets shift (lead) + backspace (trail).
                    return [shiftKey] + keys.map { letterKey($0) } + [backspaceKey]
                }
                return keys.map { letterKey($0) }
            }
        case .numbers:
            return symbolPlaneRows(KeyboardLayout.numberRows)
        case .symbols:
            return symbolPlaneRows(KeyboardLayout.symbolRows)
        }
    }

    private func symbolPlaneRows(_ source: [[String]]) -> [[KeySpec]] {
        source.enumerated().map { idx, keys in
            if idx == source.count - 1 {
                let switchGlyph = plane == .numbers ? "#+=" : "123"
                let toPlane: Plane = plane == .numbers ? .symbols : .numbers
                return [planeKey(switchGlyph, to: toPlane, weight: 1.4)]
                    + keys.map { plainKey($0) }
                    + [backspaceKey]
            }
            return keys.map { plainKey($0) }
        }
    }

    // MARK: - Bottom function row

    private var bottomRow: some View {
        row(bottomRowSpecs, rowID: "bottom")
    }

    private var bottomRowSpecs: [KeySpec] {
        var specs: [KeySpec] = []
        // 123 / ABC plane toggle. On the letters plane, dragging the 123 key
        // upward (toward shift) opens the action panels — a lone panel directly,
        // or the picker when several are enabled. Emoji is one of those panels,
        // preserving the old "drag up for emoji" feel by default. Gated on the
        // slide-up activation setting; a plain tap still switches to numbers.
        if plane == .letters {
            let slideUp: (() -> Void)? =
                (settings.activateWithSlideUp && !enabledPanels.isEmpty)
                ? { slideUpActivate() } : nil
            specs.append(planeKey("123", to: .numbers, weight: 1.4, onDragUp: slideUp))
        } else {
            specs.append(planeKey("ABC", to: .letters, weight: 1.4))
        }
        // Globe — only in the extension (host passes a handler).
        if onNextKeyboard != nil {
            specs.append(.init(kind: .function, label: .system("globe"), weight: 1.2,
                               isNextKeyboard: true) {
                onNextKeyboard?()
            })
        }
        // Blank space bar, like the system keyboard — no "space" caption. Taps
        // type a space; press-and-drag slides the cursor (trackpad mode).
        specs.append(.init(kind: .character, label: .text(""), weight: settings.spaceWidth,
                           isSpace: true, onCursorMove: onCursorMove) {
            insert(" ")
            // Return to letters if the last key was sentence punctuation, completing
            // the "punctuation → space → resume typing" flow. Opt-out via settings.
            if lastKeyWasPunctuation {
                if settings.autoReturnToLetters,
                   plane != .letters {
                    plane = .letters
                }
                lastKeyWasPunctuation = false
            }
        })
        // Return key follows the host field: a ⏎ glyph for a plain return, the
        // action word ("Go", "Search", "Send", …) otherwise — prominent (accent)
        // for action types, exactly like the system keyboard.
        let returnLabel: KeySpec.Label = live.returnKeySymbol.map { .system($0) }
            ?? .text(live.returnKeyTitle)
        specs.append(.init(kind: .function, label: returnLabel,
                           weight: 1.8, highlighted: live.returnKeyProminent) {
            insert("\n")
        })
        return specs
    }

    /// Every on-screen key, keyed by the same `"\(rowID)-\(index)"` ID the rows
    /// render with — so the multitouch router can resolve a hit-tested key back to
    /// its current spec (action + behaviour). Rebuilt on demand at touch time, so
    /// it always reflects the live plane / shift. Mirrors `rowStack` exactly.
    private func currentKeySpecs() -> [String: KeySpec] {
        var map: [String: KeySpec] = [:]
        func add(_ specs: [KeySpec], _ rowID: String) {
            for (i, s) in specs.enumerated() { map["\(rowID)-\(i)"] = s }
        }
        if settings.showNumberRow, plane == .letters {
            add(KeyboardLayout.numberRows[0].map { plainKey($0) }, "num")
        }
        for (idx, r) in currentRows.enumerated() { add(r, "r\(idx)") }
        add(bottomRowSpecs, "bottom")
        return map
    }

    // MARK: - Key specs

    private var shiftKey: KeySpec {
        let glyph = shift == .locked ? "capslock.fill" : (shift == .on ? "shift.fill" : "shift")
        return KeySpec(kind: .function, label: .system(glyph), weight: settings.funcKeyWidth,
                       highlighted: shift != .off, isShift: true) {
            switch shift {
            case .off:    shift = .on
            case .on:     shift = .locked
            case .locked: shift = .off
            }
        }
    }

    private var backspaceKey: KeySpec {
        KeySpec(kind: .function, label: .system("delete.left"), weight: settings.funcKeyWidth,
                isDestructive: true, isRepeatable: true) {
            backspace()
        }
    }

    private func letterKey(_ base: String) -> KeySpec {
        let shifted = shift != .off
        let glyph = shifted ? base.uppercased() : base
        return KeySpec(kind: .character, label: .text(glyph), weight: 1) {
            insert(glyph)
            if shift == .on { shift = .off }  // sticky shift releases after one key
        }
    }

    /// A symbol/number key with no shift behaviour.
    private func plainKey(_ glyph: String, fontSize: CGFloat? = nil) -> KeySpec {
        KeySpec(kind: .character, label: .text(glyph), weight: 1, fontSize: fontSize) {
            insert(glyph)
            // Mark that a punctuation was pressed, so we can return to letters when
            // the space bar is tapped (implements "return after space" behaviour).
            if settings.autoReturnToLetters,
               plane != .letters,
               Self.autoReturnPunctuation.contains(glyph) {
                lastKeyWasPunctuation = true
            } else {
                // Clear the flag if pressing a non-punctuation key, so we don't
                // unexpectedly return to letters if the user was just continuing
                // to enter symbols after the punctuation.
                lastKeyWasPunctuation = false
            }
        }
    }

    /// Sentence/prose punctuation that returns the keyboard to letters when
    /// `autoReturnToLetters` is on. Deliberately excludes digits, math, currency,
    /// and brackets — there you usually keep entering symbols/numbers.
    private static let autoReturnPunctuation: Set<String> = [
        ".", ",", "?", "!", ";", ":",
        "'", "\u{2019}", "\u{2018}", "\"", "\u{201C}", "\u{201D}",
    ]

    /// Subset of `autoReturnPunctuation` that takes a following space when
    /// `autoSpaceAfterReturn` is on. Excludes quotes/apostrophes, which hug the
    /// next character rather than sitting before a gap.
    private static let autoSpacePunctuation: Set<String> = [
        ".", ",", "?", "!", ";", ":",
    ]

    private func planeKey(_ glyph: String, to target: Plane, weight: Double,
                          onDragUp: (() -> Void)? = nil) -> KeySpec {
        KeySpec(kind: .function, label: .text(glyph), weight: weight,
                onDragUp: onDragUp) {
            plane = target
            lastKeyWasPunctuation = false
        }
    }

    /// Single choke point for every character / space / newline the keys emit.
    /// While the notepad is composing, keystrokes feed its buffer instead of the
    /// host document; otherwise they go to the host via `onInsert`.
    private func insert(_ s: String) {
        if live.activePanel == .notepad {
            notepad.scratch += s
        } else {
            onInsert(s)
        }
    }

    /// Backspace, routed the same way as `insert`.
    private func backspace() {
        if live.activePanel == .notepad {
            if !notepad.scratch.isEmpty { notepad.scratch.removeLast() }
        } else {
            onBackspace()
        }
    }

    // MARK: - Row renderer (proportional widths, à la EmbeddedKeyboard)

    @ViewBuilder
    private func row(_ specs: [KeySpec], rowID: String, fixedHeight: CGFloat? = nil) -> some View {
        let total = specs.map(\.weight).reduce(0, +)
        let spacing = CGFloat(settings.keySpacing)
        let content = GeometryReader { geo in
            let gaps = spacing * CGFloat(max(specs.count - 1, 0))
            let unit = max((geo.size.width - gaps) / CGFloat(total), 0)
            HStack(spacing: spacing) {
                ForEach(Array(specs.enumerated()), id: \.offset) { i, spec in
                    KeyView(spec: spec, theme: theme, cornerRadius: CGFloat(settings.keyCornerRadius),
                            popupEnabled: settings.keyPopupEnabled, pressWarp: settings.keyPressWarp,
                            keyID: "\(rowID)-\(i)",
                            simulatedPressed: controller.pressedKeyID == "\(rowID)-\(i)",
                            router: touch,
                            physics: physics)
                        .frame(width: unit * CGFloat(spec.weight))
                }
            }
        }
        // A `fixedHeight` row (the number strip) takes exactly that; the rest leave
        // height flexible and divide the host evenly, so there's never a top/bottom
        // gap.
        if let fixedHeight {
            content.frame(height: fixedHeight)
        } else {
            content.frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Trackpad cursor panel

/// The full-keyboard trackpad shown while the space bar is held in trackpad
/// cursor mode — just a single centred 2-D move glyph, tinted the theme accent,
/// over the keyboard's own backdrop (painted by the canvas). Purely visual: the
/// drag is tracked by the multitouch surface beneath it, so it takes no touches.
struct TrackpadPanel: View {
    let theme: Theme

    var body: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(theme.accent.color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Key-popup plumbing
//
// The pressed-key bubble must float above the WHOLE keyboard — a per-key
// overlay escaping its bounds gets occluded by the keys in the row above. So
// each pressed character key publishes its glyph + bounds up via an anchor
// preference, and the canvas draws a single popup on top of everything.

struct KeyPopup {
    let glyph: String
    let anchor: Anchor<CGRect>
}

struct KeyPopupKey: PreferenceKey {
    static let defaultValue: KeyPopup? = nil
    static func reduce(value: inout KeyPopup?, nextValue: () -> KeyPopup?) {
        if let next = nextValue() { value = next }
    }
}

// MARK: - Glyph layer plumbing
//
// Each key publishes its glyph + bounds + bloom transform; the canvas draws them
// all in one layer ABOVE the glass container, so the container's morph (which
// blends a bloomed key into its neighbours) never displaces the letter.

struct KeyGlyphInfo: Identifiable, Equatable {
    let id: String
    let anchor: Anchor<CGRect>
    let isSystem: Bool
    let glyph: String
    let color: Color
    let scaleX: CGFloat
    let scaleY: CGFloat
    let offsetX: CGFloat
    let hidden: Bool
    let deleteTick: Int
    let multiChar: Bool
    /// Override glyph point size (number row); nil = default sizing.
    var fontSize: CGFloat? = nil
}

struct KeyGlyphKey: PreferenceKey {
    static let defaultValue: [KeyGlyphInfo] = []
    static func reduce(value: inout [KeyGlyphInfo], nextValue: () -> [KeyGlyphInfo]) {
        value.append(contentsOf: nextValue())
    }
}

/// Fills a popup's shape with the right material (Liquid Glass or an opaque
/// bubble) plus a drop shadow — shared by every popup style.
private struct PopupChrome<S: Shape>: ViewModifier {
    let shape: S
    let theme: Theme
    let glass: Bool
    /// When set, the popup takes this tint instead of the resting key fill — used
    /// by the balloon so it matches the pressed key it rises out of, blending into
    /// one continuous shape rather than reading as a detached blob.
    var tint: Color? = nil
    /// Override the drop shadow (opacity, radius, y). The balloon dips into the
    /// key, so it wants a faint shadow — a strong one paints a dark line across
    /// the key where the two shapes overlap. Defaults to the floating tile's.
    var shadow: (opacity: Double, radius: CGFloat, y: CGFloat) = (0.3, 6, 2)

    @ViewBuilder func body(content: Content) -> some View {
        if glass, #available(iOS 26.0, *) {
            content
                .glassEffect(tint.map { .regular.tint($0) } ?? .regular, in: shape)
                .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
        } else {
            let resting: Color = theme.material == .liquidGlass
                ? (theme.isDark ? Color(.sRGB, white: 0.16) : Color(.sRGB, white: 0.98))
                : theme.keyFill.color
            content
                .background(tint ?? resting, in: shape)
                .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
        }
    }
}

/// A key-popup outline drawn as ONE continuous shape spanning the whole pressed
/// key: a wide, flat-topped rounded-rectangle head (like the system keyboard's
/// magnifier) that eases down through a short concave neck to the key's width,
/// then runs straight to a rounded foot. Because the balloon *is* the key (it
/// covers it exactly, same width / corners / tint) there's no seam — the head
/// reads as the key broadening upward.
private struct BalloonPopupShape: Shape {
    let keyWidth: CGFloat
    /// Height of the rounded-rectangle head, before the neck begins.
    let headHeight: CGFloat
    /// Y of the key's top edge within the frame; below it the sides run straight
    /// down to the foot, above it is the head + neck.
    let shoulderY: CGFloat
    /// Roundness of the head's top corners.
    let topCorner: CGFloat
    /// Roundness of the foot's corners — the key's own corner radius.
    let bottomCorner: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2
        let rt = min(topCorner, w / 2)
        let kHalf = min(keyWidth, w) / 2
        let leftK = cx - kHalf, rightK = cx + kHalf
        let br = min(bottomCorner, kHalf)
        let shoulder = min(max(shoulderY, rt + 8), h - br - 1)
        // Head's straight sides end a little above the shoulder, leaving a short
        // neck to ease in to the key width.
        let headB = min(headHeight, shoulder - 8)

        var p = Path()
        // Head — wide rounded-rectangle top.
        p.move(to: CGPoint(x: rt, y: 0))
        p.addLine(to: CGPoint(x: w - rt, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: rt), control: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: headB))
        // Short right neck — concave ease to the key's right edge (vertical
        // tangents at both ends so head and key sides flow in smoothly).
        p.addCurve(to: CGPoint(x: rightK, y: shoulder),
                   control1: CGPoint(x: w, y: shoulder),
                   control2: CGPoint(x: rightK, y: headB))
        // Straight down the key's right side to the foot.
        p.addLine(to: CGPoint(x: rightK, y: h - br))
        p.addQuadCurve(to: CGPoint(x: rightK - br, y: h), control: CGPoint(x: rightK, y: h))
        p.addLine(to: CGPoint(x: leftK + br, y: h))
        p.addQuadCurve(to: CGPoint(x: leftK, y: h - br), control: CGPoint(x: leftK, y: h))
        // Up the key's left side, then the mirrored neck back to the head.
        p.addLine(to: CGPoint(x: leftK, y: shoulder))
        p.addCurve(to: CGPoint(x: 0, y: headB),
                   control1: CGPoint(x: leftK, y: headB),
                   control2: CGPoint(x: 0, y: shoulder))
        p.addLine(to: CGPoint(x: 0, y: rt))
        p.addQuadCurve(to: CGPoint(x: rt, y: 0), control: CGPoint(x: 0, y: 0))
        p.closeSubpath()
        return p
    }
}

/// The balloon popup, with its "droplet" emerge: on press it springs up out of
/// the key — anchored at the foot, it stretches from a low squash to full height
/// and settles with a soft wobble, like a droplet drawn upward. A faint shadow
/// keeps the foot from painting a line across the key it overlaps.
private struct BalloonPopup: View {
    let glyph: String
    let bulbWidth: CGFloat
    let totalHeight: CGFloat
    /// Signed offset of the glyph from the frame centre, up into the bulb.
    let glyphOffset: CGFloat
    let shape: BalloonPopupShape
    let tint: Color
    let theme: Theme
    let glass: Bool
    var springResponse: Double = 0.32
    var springDamping: Double  = 0.62

    @State private var emerged = false

    var body: some View {
        Text(glyph)
            .font(.system(size: 26, weight: .regular))
            .foregroundStyle(.white)
            .offset(y: glyphOffset)                   // lift glyph into the bulb
            .frame(width: bulbWidth, height: totalHeight)
            .modifier(PopupChrome(shape: shape, theme: theme, glass: glass,
                                  tint: tint, shadow: (0.22, 5, 1.5)))
            // Droplet emerge: scale up from the foot (the key), so the bulb is
            // drawn upward out of the key rather than fading in over it.
            .scaleEffect(x: emerged ? 1 : 0.9, y: emerged ? 1 : 0.5, anchor: .bottom)
            .opacity(emerged ? 1 : 0.5)
            .onAppear {
                withAnimation(.spring(response: springResponse, dampingFraction: springDamping)) { emerged = true }
            }
    }
}

// MARK: - Key spec + view

/// A single key's appearance + behaviour. Value type so rows can be rebuilt
/// cheaply on every shift/plane change.
struct KeySpec: Identifiable {
    enum Kind { case character, function }
    enum Label { case text(String); case system(String) }

    let id = UUID()
    let kind: Kind
    let label: Label
    let weight: Double
    let highlighted: Bool
    /// Pressed state glows red instead of accent (the backspace key).
    let isDestructive: Bool
    /// The space bar — taps insert a space, press-and-drag moves the cursor.
    let isSpace: Bool
    /// Repeats `action` while held (the backspace key).
    let isRepeatable: Bool
    /// Fired when this key is pressed and dragged upward past a threshold (the
    /// 123→emoji gesture). When it fires, the key's normal tap `action` is
    /// suppressed for that touch. nil for keys with no drag-up behaviour.
    let onDragUp: (() -> Void)?
    /// The shift key — it has its own glass + symbol animation, so it opts out
    /// of the generic press-warp bloom (which would double up and look janky).
    let isShift: Bool
    /// The globe / next-keyboard key — kept tappable in combined cursor mode so
    /// the user can always switch away (every other key is rebound to the pad).
    let isNextKeyboard: Bool
    /// Called with a signed character delta while dragging the space bar.
    let onCursorMove: ((Int) -> Void)?
    /// Override glyph point size (the number row uses this); nil = default sizing.
    let fontSize: CGFloat?
    let action: () -> Void

    init(kind: Kind, label: Label, weight: Double, highlighted: Bool = false,
         isDestructive: Bool = false, isSpace: Bool = false, isRepeatable: Bool = false,
         isShift: Bool = false, isNextKeyboard: Bool = false,
         onCursorMove: ((Int) -> Void)? = nil,
         onDragUp: (() -> Void)? = nil, fontSize: CGFloat? = nil,
         action: @escaping () -> Void) {
        self.kind = kind; self.label = label; self.weight = weight
        self.highlighted = highlighted; self.isDestructive = isDestructive
        self.isSpace = isSpace; self.isRepeatable = isRepeatable; self.isShift = isShift
        self.isNextKeyboard = isNextKeyboard
        self.onCursorMove = onCursorMove; self.onDragUp = onDragUp
        self.fontSize = fontSize; self.action = action
    }
}

/// Renders one key and detects key-*down* (via a zero-distance drag) so the
/// host clinks the instant the finger lands, then fires the action on release.
/// A one-shot, additive "tap registered" flash, replayed on every press.
///
/// Keyed to `KeyTouchRouter`'s per-key tap tick (which bumps on every
/// touch-down), so it fires even when the same key is re-pressed while it's
/// still in the pressed/linger state — the case where the bloom, sprung on
/// `isPressed`, can't re-animate. It briefly brightens the key over its own
/// shape and fades out; it changes no geometry, so it layers on top of the
/// bloom/popup without overriding either. Gated on the same `keyPressWarp`
/// switch as the bloom, so turning press visuals off silences it too.
private struct TapPulse: ViewModifier {
    let trigger: Int
    let shape: RoundedRectangle
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, flash in
                view.overlay {
                    shape.fill(.white)
                        .opacity(flash)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(0.0, duration: 0.001)
                    CubicKeyframe(0.34, duration: 0.05)   // snap bright
                    CubicKeyframe(0.0, duration: 0.20)    // ease back out
                }
            }
        } else {
            content
        }
    }
}

private struct KeyView: View {
    let spec: KeySpec
    let theme: Theme
    let cornerRadius: CGFloat
    let popupEnabled: Bool
    /// Bloom/warp the key on press (optional, per `keyPressWarp`).
    let pressWarp: Bool
    /// Stable identity (row-col) so the glyph layer can track this key across
    /// rebuilds for its symbol animations.
    let keyID: String
    /// Driven by an external typing simulator (the device showcase) — shows the
    /// key as pressed even though no finger is on it.
    let simulatedPressed: Bool
    /// Shared multitouch state — this key's press / warp is read out of here,
    /// written by the single UIKit touch surface (see `KeyTouchRouter`).
    let router: KeyTouchRouter
    let physics: KeyPressPhysics

    /// Pressed for any reason: a real finger (the router) or the simulator.
    private var isPressed: Bool { router.pressed.contains(keyID) || simulatedPressed }
    /// Space-bar trackpad drag state (only the space key reads these).
    private var cursorActive: Bool { router.spaceCursorActive }
    private var dragX: CGFloat { router.spaceDragX }
    /// Bumped on every auto-repeat delete to bounce the glyph as feedback.
    private var deleteTick: Int { router.deleteTick }

    /// iOS-style destructive red for the pressed backspace key.
    private static let destructiveTint = Color(.sRGB, red: 0.91, green: 0.22, blue: 0.18)

    private var isCharacter: Bool { spec.kind == .character }

    /// Whether this key is currently showing its magnified popup — if so the key
    /// skips the press bloom (the popup is the press feedback). The key keeps its
    /// own glyph; the popup floats above it like the system keyboard.
    private var showsPopup: Bool {
        guard isPressed, popupEnabled, isCharacter else { return false }
        if case let .text(g) = spec.label, g.count == 1 { return true }
        return false
    }

    /// The colour a key glows when pressed — red for destructive (backspace),
    /// the theme accent otherwise.
    private var pressedTint: Color {
        spec.isDestructive ? Self.destructiveTint : theme.accent.color
    }

    private var fill: Color {
        if spec.highlighted { return theme.accent.color }
        return (isCharacter ? theme.keyFill : theme.specialKeyFill).color
    }
    private var textColor: Color {
        if spec.highlighted { return .white }
        return (isCharacter ? theme.keyText : theme.specialKeyText).color
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    /// Liquid "warp": the space bar stretches toward the finger (and squashes
    /// vertically) while dragging the cursor; with `pressWarp` on, every key
    /// blooms a little on press. Both spring back on release.
    private var warp: (scaleX: CGFloat, scaleY: CGFloat, offset: CGFloat) {
        if spec.isSpace, isPressed {
            // The bar leans toward the finger the whole time it's held (tracking
            // `dragX` from the first move — no frozen dead zone) and SHRINKS a fixed
            // amount once a real drag engages, holding that size for the whole drag.
            // The lean is applied as a NON-animated `.offset` in `body`, so it glides
            // live with the finger; on glass that means one liquid-merge morph per
            // finger frame instead of a spring's backlog of them (the drag stutter).
            let maxLean: CGFloat = 28
            let offset = max(min(dragX * physics.spaceLeanMultiplier, maxLean), -maxLean)
            let scale: CGFloat = cursorActive ? physics.spaceCursorDragScale
                                              : (pressWarp && !showsPopup ? 1.04 : 1)
            return (scale, scale, offset)
        }
        // Visible bloom on press for the generic keys. The shift key opts out —
        // it has its own interactive-glass morph (see `glass` / `surface`).
        if pressWarp, isPressed, !showsPopup, !spec.isShift {
            return (physics.bloomScale, physics.bloomScale, 0)
        }
        return (1, 1, 0)
    }

    var body: some View {
        let w = warp
        // Generic keys: only the SURFACE blooms here (and morphs in the
        // container); the glyph is drawn on top by the canvas glyph layer.
        // The shift key draws its OWN glyph as glass content, so its interactive
        // glass can animate the glyph along with it (the caps-lock morph).
        return surface
            .scaleEffect(x: w.scaleX, y: w.scaleY, anchor: .center)
            // The lean offset rides BEFORE the springs below. While dragging, only
            // `dragX` (the offset) changes — `isPressed`/`cursorActive` are steady —
            // so no spring fires and the bar tracks the finger live, 1:1: one
            // liquid-merge morph per finger frame, not a spring's backlog of them
            // (that backlog was the drag stutter). On RELEASE the springs DO fire and
            // carry the offset back to centre together with the scale, so it glides
            // home instead of snapping.
            .offset(x: w.offset)
            // Press bloom (non-space). For the SPACE bar this uses the SAME spring as
            // the cursor shrink below, so a drag-release — where `isPressed` and
            // `cursorActive` clear in the same frame — settles on ONE spring instead
            // of two different ones fighting over the scale (the release stutter).
            .animation(spec.isSpace
                       ? .interactiveSpring(response: physics.spaceSpringResponse, dampingFraction: physics.spaceSpringDamping)
                       : (pressWarp && !spec.isShift
                          ? .interactiveSpring(response: physics.springResponse, dampingFraction: physics.springDamping) : nil),
                       value: isPressed)
            // The space bar's trackpad shrink in/out — a one-shot at engage/release,
            // matched to the spring above. Scoped to space so a space drag never
            // re-animates any other key.
            .animation(spec.isSpace
                       ? .interactiveSpring(response: physics.spaceSpringResponse, dampingFraction: physics.spaceSpringDamping) : nil,
                       value: cursorActive)
            // Additive "tap registered" flash. The bloom above is sprung on
            // `isPressed`, which never re-toggles when the SAME key is tapped
            // twice inside the linger window (the second `l` in "tell") — so the
            // re-press reads as dropped though the character did insert. This
            // pulse is keyed to the router's per-press tick, which bumps on every
            // landing, so each tap gets its own confirmation. It only flashes a
            // brief highlight over the key — it never touches the bloom geometry,
            // so it adds to the press effect rather than overriding it.
            .modifier(TapPulse(trigger: router.tapTick(keyID), shape: shape, enabled: pressWarp))
            // Publish the glyph for the on-top layer — except shift, which draws
            // its own so it can morph with its interactive glass.
            .anchorPreference(key: KeyGlyphKey.self, value: .bounds) { anchor in
                spec.isShift ? [] : [glyphInfo(anchor: anchor, warp: w)]
            }
            // Publish bounds + glyph to the popup layer while pressed.
            .anchorPreference(key: KeyPopupKey.self, value: .bounds) { anchor in
                // Only magnify single-glyph keys (letters, numbers, symbols) —
                // never multi-character keys like "space", which would just show
                // a truncated "S…" bubble.
                guard isPressed, popupEnabled, isCharacter,
                      case let .text(g) = spec.label, g.count == 1 else { return nil }
                return KeyPopup(glyph: g, anchor: anchor)
            }
            // Publish this key's frame so the multitouch surface can hit-test to
            // it. Every key (including shift / space / function) is touchable.
            .anchorPreference(key: KeyFrameKey.self, value: .bounds) { [keyID: $0] }
    }

    /// Describe this key's glyph for the canvas glyph layer.
    private func glyphInfo(anchor: Anchor<CGRect>,
                           warp: (scaleX: CGFloat, scaleY: CGFloat, offset: CGFloat)) -> KeyGlyphInfo {
        let isSystem: Bool
        let glyph: String
        let multiChar: Bool
        switch spec.label {
        case .text(let t):   isSystem = false; glyph = t; multiChar = t.count > 1
        case .system(let n): isSystem = true;  glyph = n; multiChar = false
        }
        return KeyGlyphInfo(
            id: keyID, anchor: anchor, isSystem: isSystem, glyph: glyph,
            color: isPressed ? .white : textColor,
            scaleX: warp.scaleX, scaleY: warp.scaleY, offsetX: warp.offset,
            // Only the backspace key bounces on auto-repeat; every other key
            // feeds 0 so a delete burst doesn't jiggle shift / globe / return.
            // The key keeps its own glyph even while popping — the popup sits
            // above it (à la the system keyboard), so the letter stays put.
            hidden: false, deleteTick: spec.isRepeatable ? deleteTick : 0, multiChar: multiChar,
            fontSize: spec.fontSize)
    }

    /// The key's drawn surface: shift carries its own glyph (so its interactive
    /// glass morphs the glyph too); every other key is just the bare surface, its
    /// glyph painted by the canvas glyph layer.
    @ViewBuilder private var surface: some View {
        if spec.isShift {
            shiftSurface
        } else {
            keyBackground
        }
    }

    /// Just the key's surface (glass or solid fill). The glyph is drawn ON TOP by
    /// the canvas glyph layer, so it never rides along with the glass morph.
    @ViewBuilder private var keyBackground: some View {
        switch theme.material {
        case .liquidGlass:
            if #available(iOS 26.0, *) {
                Color.clear.glassEffect(glass, in: shape)
            } else {
                // Pre-26 fallback: system blur material + a faint theme tint.
                shape.fill(.ultraThinMaterial).overlay(shape.fill(glassFallbackTint))
            }
        case .solid:
            shape
                .fill(isPressed ? pressedTint.opacity(0.85) : fill)
                .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.18), radius: 0, y: 1)
        }
    }

    /// The shift key, with its glyph as the glass's content (so the interactive
    /// material animates the glyph during the caps-lock morph), plus the animated
    /// shift ⇄ caps-lock symbol swap.
    @ViewBuilder private var shiftSurface: some View {
        let content = shiftLabel
            .foregroundStyle(isPressed ? Color.white : textColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        switch theme.material {
        case .liquidGlass:
            if #available(iOS 26.0, *) {
                content.glassEffect(glass, in: shape)
            } else {
                content.background {
                    shape.fill(.ultraThinMaterial).overlay(shape.fill(glassFallbackTint))
                }
            }
        case .solid:
            content.background {
                shape
                    .fill(isPressed ? pressedTint.opacity(0.85) : fill)
                    .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.18), radius: 0, y: 1)
            }
        }
    }

    @ViewBuilder private var shiftLabel: some View {
        if case let .system(name) = spec.label {
            Image(systemName: name)
                .font(.system(size: 18, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                // The interactive glass lens re-renders this content on every
                // touch; pinning identity to the name keeps those press
                // re-renders from re-entering the replace transition and
                // dropping the glyph. Only a real shift ⇄ caps-lock swap
                // changes identity and cross-fades.
                .id(name)
                .animation(.snappy(duration: 0.25), value: name)
        }
    }

    /// Tint applied to a glass key: character keys take the key fill, function keys
    /// the function-key fill, pressed / latched keys glow with the accent. The
    /// theme fills are low-opacity by design (see the builder's hint), so they
    /// colour the glass without killing its translucency.
    private var glassTint: Color? {
        if isPressed { return pressedTint }
        if spec.highlighted { return theme.accent.color }
        // The resting fill tint is dialled by the theme's glass tint strength —
        // lower lets more clear glass through so the refraction reads.
        let base = (isCharacter ? theme.keyFill : theme.specialKeyFill).color
        return base.opacity(theme.glassTintStrength)
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        // Variant (regular / clear) and tint come from the theme. Interactive is
        // always on for shift (it draws its own glyph, so the lens morphs it — the
        // caps-lock animation) and otherwise opt-in per theme: generic key glyphs
        // are drawn in a separate layer, so an interactive lens warps the material
        // under the finger without dragging the glyph off-centre.
        var base: Glass = theme.glassVariant == .clear ? .clear : .regular
        if spec.isShift || theme.glassInteractive { base = base.interactive() }
        return glassTint.map { base.tint($0) } ?? base
    }

    private var glassFallbackTint: Color {
        if isPressed { return pressedTint.opacity(0.85) }
        if spec.highlighted { return theme.accent.color.opacity(0.85) }
        let base = (isCharacter ? theme.keyFill : theme.specialKeyFill).color
        return base.opacity(theme.glassTintStrength)
    }
}

// MARK: - Suggestion bar

/// The autocomplete strip above the keys, à la the native iOS predictive bar.
/// When an auto-correction is pending it leads with the user's literal word in
/// quotes (tap to keep) and shows the fix as a highlighted "primary" chip that
/// `space` will apply — then fills the rest with predictions. With no pending
/// correction it's just the predictions. Empty slots hold space so the bar
/// always fills the top of the keyboard.
struct SuggestionBar: View {
    let suggestions: [String]
    let autocorrection: Autocorrection?
    /// Emoji matching the word being typed — rendered as plain chips on the right
    /// and inserted (replacing the word) only when tapped. Never space-applied.
    let emoji: [String]
    let theme: Theme
    let onTap: (String) -> Void
    let onKeepTyped: () -> Void
    let onEmoji: (String) -> Void
    /// Vertical hit-target multiplier — see `KeyboardSettings.suggestionHitboxScale`.
    var hitboxScale: Double = 1.0

    private enum Kind { case keep, primary, normal, emoji }
    private struct Candidate: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
    }

    private var candidates: [Candidate] {
        var words: [Candidate] = []
        if let c = autocorrection {
            words.append(Candidate(text: c.from, kind: .keep))
            words.append(Candidate(text: c.to, kind: .primary))
            for s in suggestions
            where s.caseInsensitiveCompare(c.to) != .orderedSame
                && s.caseInsensitiveCompare(c.from) != .orderedSame {
                words.append(Candidate(text: s, kind: .normal))
            }
        } else {
            for s in suggestions { words.append(Candidate(text: s, kind: .normal)) }
        }
        // Reserve the right end for emoji chips when there are any, so they're
        // never crowded out — always leaving at least one word slot.
        let emojiCands = emoji.prefix(2).map { Candidate(text: $0, kind: .emoji) }
        let wordSlots = max(1, 3 - emojiCands.count)
        return Array(words.prefix(wordSlots)) + emojiCands
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { idx, cand in
                if idx > 0 { divider }
                chip(cand)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func chip(_ c: Candidate) -> some View {
        Button {
            switch c.kind {
            case .keep:  onKeepTyped()
            case .emoji: onEmoji(c.text)
            default:     onTap(c.text)
            }
        } label: {
            chipLabel(c)
                .font(.system(size: 17))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .hitboxExpand(hitboxScale, baseHeight: KeyboardCanvas.Metrics.suggestionBarHeight)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func chipLabel(_ c: Candidate) -> some View {
        switch c.kind {
        case .keep:
            // The literal typed word, quoted — tap to reject the correction.
            Text("“\(c.text)”")
                .foregroundStyle(theme.keyText.color.opacity(0.7))
        case .primary:
            // The correction `space` will apply — highlighted like iOS, and
            // matching the theme: a real glass pill on Liquid Glass, a tinted
            // capsule on solid.
            let pill = Text(c.text)
                .foregroundStyle(theme.keyText.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            if theme.material == .liquidGlass, #available(iOS 26.0, *) {
                pill.glassEffect(.regular.tint(theme.accent.color.opacity(0.55)).interactive(),
                                 in: Capsule())
            } else {
                pill.background(theme.accent.color.opacity(0.22), in: Capsule())
            }
        case .normal:
            Text(c.text).foregroundStyle(theme.keyText.color)
        case .emoji:
            // A plain (non-primary) emoji chip — slightly larger so the glyph
            // reads, and tinted nothing so it never looks like the space-applied
            // correction.
            Text(c.text).font(.system(size: 24))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.keyText.color.opacity(0.15))
            .frame(width: 0.5)
            .padding(.vertical, 11)
    }
}

// MARK: - Clipboard bar support

/// Shared thin vertical rule used between the clipboard icon and bar content.
private func barDivider(theme: Theme) -> some View {
    Rectangle()
        .fill(theme.keyText.color.opacity(0.15))
        .frame(width: 0.5)
        .padding(.vertical, 11)
}

/// The top-left action-panel button on the suggestion bar. Renders whatever SF
/// Symbol the canvas resolves (lone panel icon, active panel's filled icon, or a
/// neutral grid when a picker is needed), accent-tinted while a panel is open.
struct ActionPanelButton: View {
    let systemName: String
    let isActive: Bool
    let theme: Theme
    /// Vertical hit-target multiplier — see `KeyboardSettings.panelButtonHitboxScale`.
    var hitboxScale: Double = 1.0
    let onTap: () -> Void

    var body: some View {
        Button { onTap() } label: {
            Image(systemName: systemName)
                .font(.system(size: 16))
                .foregroundStyle(isActive
                    ? theme.accent.color
                    : theme.keyText.color.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .hitboxExpand(hitboxScale, baseHeight: KeyboardCanvas.Metrics.suggestionBarHeight)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Notepad bar support

/// The notepad's inline compose strip — the keys type into `text` while this is
/// shown. Displays the buffer (tail-truncated so the caret end stays visible)
/// with trailing actions: browse saved notes + save (notes mode only), insert
/// the buffer into the host document, and clear.
struct NotepadBar: View {
    let text: String
    let mode: NotepadMode
    let theme: Theme
    let onInsert: () -> Void
    let onSave: () -> Void
    let onBrowse: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(text.isEmpty ? "Type to jot a note…" : text)
                .font(.system(size: 16))
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(text.isEmpty
                    ? theme.keyText.color.opacity(0.35)
                    : theme.keyText.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
            if mode == .notes {
                chipDivider
                iconButton("tray.full", action: onBrowse)
                chipDivider
                iconButton("plus", action: onSave)
            }
            chipDivider
            iconButton("text.insert", action: onInsert)
            chipDivider
            iconButton("xmark", action: onClear)
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(theme.keyText.color.opacity(0.5))
                .frame(width: 40)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chipDivider: some View {
        Rectangle()
            .fill(theme.keyText.color.opacity(0.15))
            .frame(width: 0.5)
            .padding(.vertical, 11)
    }
}

// MARK: - Notepad browse panel (saved-notes archive)

/// Full-keyboard overlay listing the saved notes archive (notes mode). Mirrors
/// `ClipboardPanel`: swipeable cards with insert / load-into-buffer / delete.
/// Tapping a card inserts it into the host document; the load action drops it
/// into the compose buffer for further editing.
struct NotepadBrowsePanel: View {
    let notes: [NotepadNote]
    let theme: Theme
    let cornerRadius: CGFloat
    let onTap: (String) -> Void
    let onLoad: (String) -> Void
    let onDelete: (Int) -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void

    @State private var openRow: Int? = nil
    private let scrollSpace = "noteScroll"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: "note.text")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.accent.color)
                    .frame(width: KeyboardCanvas.Metrics.suggestionBarHeight)
                divider
                Spacer()
                divider
                headerButton("trash", action: onClear)
                divider
                headerButton("xmark", action: onDismiss)
            }
            .frame(height: KeyboardCanvas.Metrics.suggestionBarHeight)

            if notes.isEmpty {
                Text("No saved notes yet")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.keyText.color.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { vp in
                    ScrollView(.vertical, showsIndicators: false) {
                        cardList(viewportHeight: vp.size.height)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    .mask(
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.06),
                            .init(color: .black, location: 0.94),
                            .init(color: .clear, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    )
                }
                .coordinateSpace(name: scrollSpace)
            }
        }
    }

    @ViewBuilder private func cardList(viewportHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                SwipeRow(id: index, cornerRadius: cornerRadius, actions: [
                    SwipeAction(icon: "pencil", label: "Load",
                                tint: theme.accent.color) { onLoad(note.text) },
                    SwipeAction(icon: "trash.fill", label: "Delete",
                                tint: .red) { onDelete(index) },
                ], glass: theme.material == .liquidGlass,
                   openID: $openRow, scrollSpace: scrollSpace, viewportHeight: viewportHeight,
                   onTap: { onTap(note.text) },
                   cardBackground: { cardSurface }) {
                    noteText(note)
                }
            }
        }
    }

    private func noteText(_ note: NotepadNote) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.keyText.color)
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
            Text(note.date.clipboardRelative)
                .font(.system(size: 11))
                .foregroundStyle(theme.keyText.color.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch theme.material {
        case .liquidGlass:
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.tint(theme.keyFill.color.opacity(theme.glassTintStrength)), in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(theme.keyFill.color.opacity(theme.glassTintStrength)))
            }
        case .solid:
            shape.fill(theme.keyFill.color)
        }
    }

    private func headerButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.keyText.color.opacity(0.5))
                .frame(width: 22, height: 22)
                .frame(width: 52, height: KeyboardCanvas.Metrics.suggestionBarHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.keyText.color.opacity(0.15))
            .frame(width: 0.5)
            .padding(.vertical, 11)
    }
}

// MARK: - Panel switcher (cards picker style)

/// Full-keyboard switcher shown when `panelPickerStyle == .cards` and 2+ panels
/// are enabled. One tappable card per panel — icon, label, one-line summary — in
/// the same visual language as the clipboard / notepad card lists. Selecting a
/// card routes through the canvas's `activate(_:)`.
struct PanelSwitcherPanel: View {
    let panels: [ActionPanel]
    let theme: Theme
    let cornerRadius: CGFloat
    let onSelect: (ActionPanel) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.accent.color)
                    .frame(width: KeyboardCanvas.Metrics.suggestionBarHeight)
                divider
                Spacer()
                divider
                headerButton("xmark", action: onDismiss)
            }
            .frame(height: KeyboardCanvas.Metrics.suggestionBarHeight)

            GeometryReader { vp in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(panels) { panel in
                            Button { onSelect(panel) } label: { cardRow(panel) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(minHeight: vp.size.height, alignment: .top)
                }
            }
        }
    }

    private func cardRow(_ panel: ActionPanel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: panel.icon(active: false))
                .font(.system(size: 20))
                .foregroundStyle(theme.accent.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(panel.label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.keyText.color)
                Text(panel.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.keyText.color.opacity(0.5))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.keyText.color.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { cardSurface }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch theme.material {
        case .liquidGlass:
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.tint(theme.keyFill.color.opacity(theme.glassTintStrength)), in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(theme.keyFill.color.opacity(theme.glassTintStrength)))
            }
        case .solid:
            shape.fill(theme.keyFill.color)
        }
    }

    private func headerButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.keyText.color.opacity(0.5))
                .frame(width: 22, height: 22)
                .frame(width: 52, height: KeyboardCanvas.Metrics.suggestionBarHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.keyText.color.opacity(0.15))
            .frame(width: 0.5)
            .padding(.vertical, 11)
    }
}

/// The clipboard-mode content of the suggestion bar: a horizontally scrollable
/// row of saved items on the left, with save and clear buttons pinned right.
/// Save reads the current UIPasteboard and appends to history.
/// Clear wipes the full history.
struct ClipboardBar: View {
    let entries: [ClipboardEntry]
    let theme: Theme
    let onTap: (String) -> Void
    let onSave: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if entries.isEmpty {
                Text("Nothing saved yet")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.keyText.color.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { idx, entry in
                            if idx > 0 { chipDivider }
                            clipChip(entry.text)
                        }
                    }
                    .padding(.horizontal, 6)
                }
            }
            chipDivider
            iconButton("square.and.arrow.down", action: onSave)
            chipDivider
            iconButton("trash", action: onClear)
        }
    }

    private func clipChip(_ text: String) -> some View {
        Button { onTap(text) } label: {
            Text(text)
                .font(.system(size: 16))
                .lineLimit(1)
                .foregroundStyle(theme.keyText.color)
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(theme.keyText.color.opacity(0.5))
                .frame(width: 40)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chipDivider: some View {
        Rectangle()
            .fill(theme.keyText.color.opacity(0.15))
            .frame(width: 0.5)
            .padding(.vertical, 11)
    }
}

// MARK: - Clipboard overlay panel (overlay style)

/// Full-keyboard replacement shown when `clipboardStyle == .overlay` and the
/// user opens the clipboard panel. Takes over the full keyboard frame (bar +
/// keys area). Sets NO background — the keyboard's `backgroundLayer` renders
/// behind it exactly as it does behind the keys.
struct ClipboardPanel: View {
    let entries: [ClipboardEntry]
    let theme: Theme
    let cornerRadius: CGFloat
    let onTap: (String) -> Void
    let onSave: () -> Void
    let onDismiss: () -> Void
    let onCopy: (Int) -> Void
    let onTogglePin: (Int) -> Void
    let onDelete: (Int) -> Void
    let onClear: () -> Void

    @State private var openRow: Int? = nil

    private let scrollSpace = "clipScroll"

    var body: some View {
        VStack(spacing: 0) {
            // Header — same height and icon positioning as the suggestion bar.
            HStack(spacing: 0) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.accent.color)
                    .frame(width: KeyboardCanvas.Metrics.suggestionBarHeight)
                divider
                Spacer()
                divider
                headerButton("square.and.arrow.down", action: onSave)
                divider
                headerButton("trash", action: onClear)
                divider
                headerButton("xmark", action: onDismiss)
            }
            .frame(height: KeyboardCanvas.Metrics.suggestionBarHeight)

            // Content area
            if entries.isEmpty {
                Text("Nothing saved yet")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.keyText.color.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { vp in
                    ScrollView(.vertical, showsIndicators: false) {
                        cardList(viewportHeight: vp.size.height)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    // Soft fade at the scrolling edges, like the emoji grid.
                    .mask(
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.06),
                            .init(color: .black, location: 0.94),
                            .init(color: .clear, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    )
                }
                // Name the *non-scrolling* viewport so each row's frame in this
                // space reflects scrolling (on the ScrollView it'd be content
                // space — constant — and rows would never close on scroll).
                .coordinateSpace(name: scrollSpace)
            }
        }
    }

    /// The swipeable cards. The card's glass surface and the action circles share
    /// one per-row `GlassEffectContainer` (see `SwipeRow.glassWrap`) so they morph
    /// into a gooey bridge as the card is dragged; the card text rides above the
    /// glass as a `SwipeRow` overlay so the material never frosts it.
    @ViewBuilder private func cardList(viewportHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                SwipeRow(id: index, cornerRadius: cornerRadius, actions: [
                    SwipeAction(icon: "doc.on.doc.fill", label: "Copy",
                                tint: .gray) { onCopy(index) },
                    SwipeAction(icon: entry.pinned ? "pin.slash.fill" : "pin.fill",
                                label: entry.pinned ? "Unpin" : "Pin",
                                tint: theme.accent.color) { onTogglePin(index) },
                    SwipeAction(icon: "trash.fill", label: "Delete",
                                tint: .red) { onDelete(index) },
                ], glass: theme.material == .liquidGlass,
                   openID: $openRow, scrollSpace: scrollSpace, viewportHeight: viewportHeight,
                   onTap: { onTap(entry.text) },
                   cardBackground: { cardSurface }) {
                    entryText(entry)
                }
            }
        }
    }

    private func entryText(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 10) {
            if entry.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.accent.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.keyText.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if entry.date != .distantPast {
                    Text(entry.date.clipboardRelative)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.keyText.color.opacity(0.45))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Card surface that tracks the keyboard's material: a theme-tinted liquid
    /// glass lens (so swiped-under action circles refract through it) when the
    /// keyboard is glass, an opaque key-fill otherwise.
    @ViewBuilder private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch theme.material {
        case .liquidGlass:
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.tint(theme.keyFill.color.opacity(theme.glassTintStrength)), in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(theme.keyFill.color.opacity(theme.glassTintStrength)))
            }
        case .solid:
            shape.fill(theme.keyFill.color)
        }
    }

    private func headerButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            // Fixed square glyph box, centered, so every icon shares the same
            // optical center regardless of its intrinsic shape.
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.keyText.color.opacity(0.5))
                .frame(width: 22, height: 22)
                .frame(width: 52, height: KeyboardCanvas.Metrics.suggestionBarHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.keyText.color.opacity(0.15))
            .frame(width: 0.5)
            .padding(.vertical, 11)
    }
}
