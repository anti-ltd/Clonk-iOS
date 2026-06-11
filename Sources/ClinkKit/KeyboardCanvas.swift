/**
 `KeyboardCanvas`: the full keyboard view rendered by both the keyboard extension
 and the in-app live preview. Composes `KeyView` rows, the `SuggestionBar`, and
 all action-panel overlays. Also defines `KeyPressPhysics` (spring tuning struct).
 */
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
    /// Drop the press spring — snap to bloom/colour instantly (native highlight).
    var instant: Bool                = false
    /// Strength of the additive tap-flash (0 = off).
    var tapFlashStrength: CGFloat    = 0.34
    /// Space-bar press bloom scale (its own knob, not `bloomScale`).
    var spaceBloomScale: CGFloat     = 1.04
    var spaceSpringResponse: Double  = 0.28
    var spaceSpringDamping: Double   = 0.78
    var spaceLeanMultiplier: CGFloat = 0.14
    var spaceCursorDragScale: CGFloat = 0.90
    var popupSpringResponse: Double  = 0.32
    var popupSpringDamping: Double   = 0.62
}

/// Collects each popover-picker row's frame (in global/window coords) so both the
/// button drag and the 123 slide-up drag can hit-test the finger against options.
private struct PanelRowFrameKey: PreferenceKey {
    static let defaultValue: [ActionPanel: CGRect] = [:]
    static func reduce(value: inout [ActionPanel: CGRect],
                       nextValue: () -> [ActionPanel: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Holds the last-built keyspec map for a given plane/shift so repeated touch-time
/// resolutions are O(1). A reference type (held in `@State`) so the value-type
/// `KeyboardCanvas` can mutate it from a non-mutating context. Plane/shift are the
/// only inputs that change while typing; every other input invalidates explicitly.
@MainActor
final class KeySpecCache {
    private var plane: KeyboardController.Plane?
    private var shift: KeyboardController.Shift?
    private var specs: [String: KeySpec] = [:]
    private var valid = false

    func resolve(plane: KeyboardController.Plane,
                 shift: KeyboardController.Shift,
                 build: () -> [String: KeySpec]) -> [String: KeySpec] {
        if valid, plane == self.plane, shift == self.shift { return specs }
        specs = build()
        self.plane = plane
        self.shift = shift
        valid = true
        return specs
    }

    func invalidate() { valid = false }
}

public struct KeyboardCanvas: View {
    private let settings: KeyboardSettings
    private let onInsert: (String) -> Void
    private let onBackspace: () -> Void
    /// Delete the word before the cursor (backspace swipe-to-delete-word). Defaults
    /// to a no-op so the in-app preview / showcase canvases need not supply it.
    private let onDeleteWord: () -> Void
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
    /// Fired when the user taps the insert button in the calculator panel.
    private let onCalculatorInsert: (String) -> Void
    /// Fired when the user taps a custom action in the extensions panel — the
    /// host gathers the action's input, runs its script, and inserts the result.
    private let onRunExtension: (ClinkExtension) -> Void
    /// Fired when a custom panel's button inserts text — typed at the cursor.
    private let onPanelInsert: (String) -> Void
    /// Fired the instant a swipe/glide trace engages — the host deletes the stray
    /// letter typed on touch-down so the decoded word can replace it.
    private let onSwipeStart: () -> Void
    /// Fired on lift with the traced path + the live letter-key centres — the host
    /// decodes a word and inserts it. See `KeyTouchRouter` swipe session.
    private let onSwipeEnd: ([CGPoint], [Character: CGPoint]) -> Void
    /// When true, render a semi-transparent hitbox outline over each key so the
    /// user can see exactly which area maps to each key. Used by the Advanced
    /// settings view; false for normal use.
    private let showHitboxOverlay: Bool
    /// When true, pretend `spaceCursorActive` is set — used by the in-app preview
    /// to render the cursor-mode visual (keys blanked for trackpad, letters blanked
    /// for combined) without needing real touch input.
    private let previewCursorActive: Bool
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

    /// User-authored custom actions — observed so the panel reflects edits.
    private var extensions: ExtensionManager

    /// User-authored custom panels — observed so the list reflects edits.
    private var panels: PanelManager

    public init(
        settings: KeyboardSettings,
        live: KeyboardLiveState = KeyboardLiveState(),
        controller: KeyboardController? = nil,
        clipboard: ClipboardManager = ClipboardManager(),
        notepad: NotepadManager = NotepadManager(),
        extensions: ExtensionManager = ExtensionManager(),
        panels: PanelManager = PanelManager(),
        hasFullAccess: Bool = false,
        showHitboxOverlay: Bool = false,
        previewCursorActive: Bool = false,
        onInsert: @escaping (String) -> Void,
        onBackspace: @escaping () -> Void,
        onDeleteWord: @escaping () -> Void = {},
        onAnyTap: @escaping () -> Void = {},
        onNextKeyboard: (() -> Void)? = nil,
        onSuggestion: @escaping (String) -> Void = { _ in },
        onEmojiSuggestion: @escaping (String) -> Void = { _ in },
        onCancelAutocorrect: @escaping () -> Void = {},
        onCursorMove: @escaping (Int) -> Void = { _ in },
        onClipboardInsert: @escaping (String) -> Void = { _ in },
        onNotepadInsert: @escaping (String) -> Void = { _ in },
        onCalculatorInsert: @escaping (String) -> Void = { _ in },
        onRunExtension: @escaping (ClinkExtension) -> Void = { _ in },
        onPanelInsert: @escaping (String) -> Void = { _ in },
        onSwipeStart: @escaping () -> Void = {},
        onSwipeEnd: @escaping ([CGPoint], [Character: CGPoint]) -> Void = { _, _ in }
    ) {
        self.settings = settings
        self.live = live
        // Use the injected controller (the showcase simulator drives a shared
        // one) or spin up a private one for ordinary finger-driven use.
        _controller = State(initialValue: controller ?? KeyboardController())
        self.clipboard = clipboard
        self.notepad = notepad
        self.extensions = extensions
        self.panels = panels
        self.hasFullAccess = hasFullAccess
        self.showHitboxOverlay = showHitboxOverlay
        self.previewCursorActive = previewCursorActive
        self.onInsert = onInsert
        self.onBackspace = onBackspace
        self.onDeleteWord = onDeleteWord
        self.onAnyTap = onAnyTap
        self.onNextKeyboard = onNextKeyboard
        self.onSuggestion = onSuggestion
        self.onEmojiSuggestion = onEmojiSuggestion
        self.onCancelAutocorrect = onCancelAutocorrect
        self.onCursorMove = onCursorMove
        self.onClipboardInsert = onClipboardInsert
        self.onNotepadInsert = onNotepadInsert
        self.onCalculatorInsert = onCalculatorInsert
        self.onRunExtension = onRunExtension
        self.onPanelInsert = onPanelInsert
        self.onSwipeStart = onSwipeStart
        self.onSwipeEnd = onSwipeEnd
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

    /// Memoizes `currentKeySpecs()` so the per-touch hit-test/adaptive/swipe loops
    /// don't rebuild the whole keyboard's specs on every key resolution.
    @State private var keySpecCache = KeySpecCache()

    /// Track whether the last key pressed was sentence punctuation, so we can
    /// return to letters when the space bar is tapped (rather than immediately).
    @State private var lastKeyWasPunctuation = false

    /// The panel picker is showing (only meaningful when 2+ panels are enabled).
    /// For `.popover` it floats a menu; for `.inline` it expands the bar.
    @State private var pickerOpen = false

    /// How the popover picker was opened, so it can anchor itself near whatever
    /// the user touched: under the top-left icon, or above the 123 key.
    private enum PickerOrigin { case icon, slideUp }
    @State private var pickerOrigin: PickerOrigin = .icon

    /// While the notepad is in `notes` mode, whether the saved-notes archive is
    /// taking over the full keyboard (browsing) versus the inline compose strip.
    @State private var notepadBrowsing = false

    // Press-hold-drag-release support for the popover picker. The button's drag
    // gesture opens the menu on press, highlights the row under the finger, and
    // on release selects (over a row) or dismisses (off-menu). A plain tap (no
    // movement) just toggles the menu open/closed.
    /// Each popover row's frame in global/window coords, for hit-testing the
    /// finger against options during a button or 123 slide-up drag.
    @State private var panelRowFrames: [ActionPanel: CGRect] = [:]
    /// The row the finger is currently over during a drag (highlighted).
    @State private var pickerDragHover: ActionPanel? = nil
    /// Whether the current drag moved beyond the tap threshold.
    @State private var pickerDragMoved = false
    /// Whether the menu was already open when this press began (so a tap on an
    /// open menu closes it).
    @State private var pickerWasOpenAtStart = false
    /// Whether a press sequence is currently in flight.
    @State private var pickerDragActive = false

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
            instant: settings.keyPressInstant,
            tapFlashStrength: CGFloat(settings.tapFlashStrength),
            spaceBloomScale: CGFloat(settings.spaceBloomScale),
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
            || settings.calculatorEnabled
        if settings.suggestionsEnabled || (settings.activateWithIcon && anyPanel) {
            h += Metrics.suggestionBarHeight
        }
        // User-chosen top/bottom breathing room around the key block.
        h += CGFloat(settings.keyboardTopPadding) + CGFloat(settings.keyboardBottomPadding)
        return h
    }

    /// True while the held-space trackpad is engaged — the keyboard's visible
    /// chrome (bar, keys, glyphs) hides so only the move glyph shows over the
    /// keyboard's backdrop. The touch surface stays live underneath (it is never
    /// faded), so the in-progress drag keeps tracking.
    private var trackpadActive: Bool {
        settings.cursorMovementType == .trackpad &&
            (touch.spaceCursorActive || previewCursorActive)
    }

    /// Combined cursor mode WHILE the space bar is held into cursor drag: the keys
    /// stay on screen but blank their letters and go inert, and the space bar
    /// morphs. The keyboard is fully normal otherwise. Distinct from
    /// `trackpadActive`, which hides the keyboard entirely.
    private var combinedActive: Bool {
        settings.cursorMovementType == .combined &&
            (touch.spaceCursorActive || previewCursorActive)
    }

    // MARK: - Action panels (clipboard / notepad)

    /// The panels available right now, in user-defined display order. Clipboard
    /// needs Full Access (it reads the pasteboard); notepad and emoji do not.
    private var enabledPanels: [ActionPanel] {
        var result = settings.extensionOrder.compactMap { id -> ActionPanel? in
            guard let panel = ActionPanel(rawValue: id) else { return nil }
            switch panel.kind {
            case .clipboard:  return (settings.clipboardEnabled && hasFullAccess) ? panel : nil
            case .notepad:    return settings.notepadEnabled    ? panel : nil
            // Emoji leaves the picker when it has its own dedicated key by 123.
            case .emoji:      return (settings.emojiEnabled && !settings.emojiKeyInRow) ? panel : nil
            case .calculator: return settings.calculatorEnabled ? panel : nil
            default:          return nil   // custom kinds appended below, not in extensionOrder
            }
        }
        // Custom actions / panels live outside `extensionOrder`; append when
        // enabled and the user has at least one enabled item.
        if FeatureFlags.experimental {
            if settings.userExtensionsEnabled && !extensions.enabledItems.isEmpty {
                result.append(.extensions)
            }
            if settings.customPanelsEnabled {
                // Standalone custom panels become their own entries; the rest are
                // collapsed behind a single grouped "Panels" entry.
                for p in standaloneCustomPanels {
                    result.append(.customPanel(id: p.id, name: p.name, icon: p.icon))
                }
                if !groupedCustomPanels.isEmpty { result.append(.customPanels) }
            }
        }
        return result
    }

    /// Enabled custom panels that resolve to standalone (own picker entry).
    private var standaloneCustomPanels: [ClinkPanel] {
        panels.enabledItems.filter { $0.isStandalone(globalDefault: settings.customPanelsStandalone) }
    }

    /// Enabled custom panels that resolve to grouped (behind the "Panels" entry).
    private var groupedCustomPanels: [ClinkPanel] {
        panels.enabledItems.filter { !$0.isStandalone(globalDefault: settings.customPanelsStandalone) }
    }

    /// Whether a panel takes over the whole keyboard (true overlay) rather than
    /// living in the bar strip with the keys still visible. Clipboard honours its
    /// style setting; the notepad only goes full-screen while browsing its saved
    /// notes archive. Emoji never renders inside this canvas (it swaps to the
    /// separate `EmojiCanvas`), so it's never an in-canvas overlay.
    private func panelIsOverlay(_ panel: ActionPanel) -> Bool {
        switch panel.kind {
        case .clipboard:   return settings.clipboardStyle != .bar
        case .notepad:     return settings.notepadMode == .notes && notepadBrowsing
        case .emoji:       return false
        case .calculator, .extensions, .customPanels, .customPanel: return true
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
            pickerOrigin = .icon
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
            pickerOrigin = .slideUp
            withAnimation(.snappy(duration: 0.22)) { pickerOpen = true }
        }
    }

    /// While dragging up from the 123 key with the popover open, highlight the row
    /// under the finger. `windowPoint` is in window coords, matching the rows'
    /// `.global` frames. Only the popover picker supports drag-onto-row.
    private func slideHoverUpdate(_ windowPoint: CGPoint) {
        guard settings.panelPickerStyle == .popover, pickerOpen else { return }
        pickerDragHover = panelRowFrames.first { $0.value.contains(windowPoint) }?.key
    }

    /// Release of a 123 drag-up: select the row under the finger, or dismiss the
    /// popover if released away from any row. A drag-up is always a deliberate
    /// gesture (it had to cross the engage threshold), so releasing off a row
    /// dismisses — matching the suggestion-bar icon's "dragged off → dismiss".
    private func slideDragEnd(_ windowPoint: CGPoint) {
        defer { pickerDragHover = nil }
        guard settings.panelPickerStyle == .popover, pickerOpen else { return }
        if let hover = panelRowFrames.first(where: { $0.value.contains(windowPoint) })?.key {
            activate(hover)
        } else {
            withAnimation(.snappy(duration: 0.18)) { pickerOpen = false }
        }
    }

    private func togglePanel(_ panel: ActionPanel) {
        // Emoji lives in its own canvas — there's no "open emoji panel" state to
        // toggle off from here (you return via the emoji ABC key), so just open.
        if panel.kind == .emoji { activate(.emoji); return }
        if live.activePanel == panel { closePanel() }
        else { live.activePanel = panel; pickerOpen = false }
    }

    /// Route a panel selection. Emoji flips the shared controller to swap in the
    /// emoji canvas; everything else opens in-place via `live.activePanel`.
    private func activate(_ panel: ActionPanel) {
        pickerOpen = false
        switch panel.kind {
        case .emoji:
            withAnimation(.snappy(duration: 0.22)) { controller.showEmoji = true }
        case .clipboard, .notepad, .calculator, .extensions, .customPanels, .customPanel:
            live.activePanel = panel
        }
    }

    private func closePanel() {
        live.activePanel = nil
        pickerOpen = false
        notepadBrowsing = false
    }

    /// The top-left "back" action while a panel is open. Returns to the cards
    /// picker when that's the active style (and there's a picker to return to —
    /// 2+ panels); otherwise there's no picker to fall back to, so it closes to
    /// the main keyboard. `closePanel()` already clears `notepadBrowsing`.
    private func backToPicker() {
        let canPick = settings.panelPickerStyle == .cards && enabledPanels.count >= 2
        guard canPick else { closePanel(); return }
        withAnimation(.snappy(duration: 0.22)) {
            live.activePanel = nil
            notepadBrowsing = false
            pickerOpen = true
        }
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
            Group {
                // Popover with 2+ panels gets the press-hold-drag-release button;
                // every other case is a plain tap button.
                if settings.panelPickerStyle == .popover && enabledPanels.count >= 2 {
                    panelDragButton
                } else {
                    ActionPanelButton(systemName: panelButtonIcon,
                                      isActive: live.activePanel != nil,
                                      theme: theme,
                                      hitboxScale: settings.panelButtonHitboxScale) {
                        panelButtonTapped()
                    }
                }
            }
            .frame(width: Metrics.suggestionBarHeight)
            .anchorPreference(key: BarHitboxKey.self, value: .bounds) { ["icon": $0] }
            barDivider(theme: theme)
        }
    }

    /// The popover trigger that supports both a plain tap (toggle the menu) and a
    /// press-hold-drag-release flow: hold opens the menu, drag highlights the row
    /// under the finger, release over a row selects it, release off-menu dismisses.
    private var panelDragButton: some View {
        Image(systemName: panelButtonIcon)
            .font(.system(size: 16))
            .foregroundStyle(live.activePanel != nil
                ? theme.accent.color
                : theme.keyText.color.opacity(0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .hitboxExpand(settings.panelButtonHitboxScale,
                          baseHeight: Metrics.suggestionBarHeight)
            .gesture(panelDragGesture)
    }

    private var panelDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                if !pickerDragActive {
                    pickerDragActive = true
                    pickerWasOpenAtStart = pickerOpen
                    pickerDragMoved = false
                    if !pickerOpen {
                        pickerOrigin = .icon
                        withAnimation(.snappy(duration: 0.18)) { pickerOpen = true }
                    }
                }
                let moved = hypot(v.location.x - v.startLocation.x,
                                  v.location.y - v.startLocation.y)
                if moved > 8 { pickerDragMoved = true }
                pickerDragHover = panelRowFrames.first { $0.value.contains(v.location) }?.key
            }
            .onEnded { v in
                defer {
                    pickerDragActive = false
                    pickerDragHover = nil
                    pickerDragMoved = false
                }
                if let hover = panelRowFrames.first(where: { $0.value.contains(v.location) })?.key {
                    activate(hover)                       // released over an option → select
                } else if pickerDragMoved {
                    withAnimation(.snappy(duration: 0.18)) { pickerOpen = false }   // dragged off → dismiss
                } else if pickerWasOpenAtStart {
                    withAnimation(.snappy(duration: 0.18)) { pickerOpen = false }   // tap on open menu → close
                }
                // else: a tap that opened the menu — leave it open for a follow-up tap.
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
            // The live suggestions are read inside this CHILD view, not here —
            // so each debounced suggestion recompute re-renders only the bar,
            // never this whole canvas (and with it the entire key grid).
            LiveSuggestionBar(live: live, theme: theme,
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

    /// Width of the floating popover menu.
    private static let popoverWidth: CGFloat = 168
    /// Height of one popover row (matches the row `.frame(height:)` below).
    private static let popoverRowHeight: CGFloat = 40

    /// The popover picker: a small floating menu, over a transparent
    /// tap-to-dismiss catcher that fills the keyboard. It anchors near whatever
    /// the user touched to open it — under the top-left icon for icon
    /// activation, or floating just above the 123 key for a 123 slide-up.
    /// `slideUpKeyFrame` is the 123 key's frame (in this overlay's coordinate
    /// space) when opened via slide-up; `nil` anchors under the icon.
    private func panelPopover(slideUpKeyFrame: CGRect?) -> some View {
        // Estimated menu height from the rows (height + 0.5pt dividers), so the
        // slide-up variant can sit its bottom edge just above the 123 key.
        let rows = CGFloat(enabledPanels.count)
        let menuHeight = rows * Self.popoverRowHeight + max(rows - 1, 0) * 0.5
        let originX: CGFloat
        let originY: CGFloat
        let scaleAnchor: UnitPoint
        if let kf = slideUpKeyFrame {
            originX = kf.minX
            originY = kf.minY - 6 - menuHeight
            scaleAnchor = .bottomLeading
        } else {
            originX = 6
            originY = Metrics.suggestionBarHeight - 4
            scaleAnchor = .topLeading
        }
        return ZStack(alignment: .topLeading) {
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
                        // Highlight the row the finger is dragging over.
                        .background(pickerDragHover == panel
                                    ? theme.accent.color.opacity(0.22) : .clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // Report this row's frame (in window/global coords) so both the
                    // button drag and the 123 slide-up drag can hit-test it.
                    .background(GeometryReader { proxy in
                        Color.clear.preference(
                            key: PanelRowFrameKey.self,
                            value: [panel: proxy.frame(in: .global)])
                    })
                }
            }
            .onPreferenceChange(PanelRowFrameKey.self) { panelRowFrames = $0 }
            .frame(width: Self.popoverWidth)
            .background {
                let r = CGFloat(settings.keyCornerRadius)
                let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
                if theme.material == .liquidGlass {
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.fill(theme.keyFill.color.opacity(0.35)))
                        .overlay(shape.strokeBorder(theme.keyText.color.opacity(0.12), lineWidth: 0.5))
                } else {
                    shape.fill(theme.keyFill.color)
                        .overlay(shape.strokeBorder(theme.keyText.color.opacity(0.15), lineWidth: 0.5))
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .offset(x: originX, y: originY)
            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: scaleAnchor)))
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
                switch overlay.kind {
                case .emoji:
                    // Never an in-canvas overlay (it swaps to EmojiCanvas).
                    EmptyView()
                case .clipboard:
                    ClipboardPanel(
                        entries: clipboard.history,
                        theme: theme,
                        cornerRadius: CGFloat(settings.keyCornerRadius),
                        gridLayout: settings.clipboardStyle == .grid,
                        onTap: { text in onClipboardInsert(text) },
                        onSave: { clipboard.captureFromPasteboard() },
                        onDismiss: { closePanel() },
                        onBack: { backToPicker() },
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
                        onDismiss: { notepadBrowsing = false },
                        onBack: { notepadBrowsing = false }
                    )
                case .calculator:
                    CalculatorPanel(
                        theme: theme,
                        cornerRadius: CGFloat(settings.keyCornerRadius),
                        onInsert: { text in onCalculatorInsert(text) },
                        onCopy: { text in UIPasteboard.general.string = text },
                        onSaveToClipboard: { text in clipboard.capture(string: text) },
                        onDismiss: { closePanel() },
                        onBack: { backToPicker() }
                    )
                case .extensions:
                    if FeatureFlags.experimental {
                        ExtensionsPanel(
                            extensions: extensions.enabledItems,
                            theme: theme,
                            cornerRadius: CGFloat(settings.keyCornerRadius),
                            onRun: { ext in onRunExtension(ext) },
                            onDismiss: { closePanel() },
                            onBack: { backToPicker() }
                        )
                    }
                case .customPanels:
                    if FeatureFlags.experimental {
                        CustomPanelsContainer(
                            panels: groupedCustomPanels,
                            standalone: nil,
                            theme: theme,
                            cornerRadius: CGFloat(settings.keyCornerRadius),
                            onInsert: { text in onPanelInsert(text) },
                            onDismiss: { closePanel() },
                            onBack: { backToPicker() }
                        )
                    }
                case .customPanel:
                    if FeatureFlags.experimental {
                        // A standalone custom panel — open straight to it.
                        CustomPanelsContainer(
                            panels: [],
                            standalone: panels.items.first { $0.id == overlay.panelID },
                            theme: theme,
                            cornerRadius: CGFloat(settings.keyCornerRadius),
                            onInsert: { text in onPanelInsert(text) },
                            onDismiss: { closePanel() },
                            onBack: { backToPicker() }
                        )
                    }
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
                            // Swipe trail rides in the SAME coordinate space the
                            // touch surface reports points in (this GeometryReader's
                            // local space == the UIView's local space), so it tracks
                            // the finger exactly. Below the surface but above the
                            // keys; never intercepts touches.
                            // The live trail is read inside this CHILD view, not
                            // here — so a glide sample redraws only the stroke,
                            // never this closure (which would rebuild the
                            // MultiTouchSurface per sample). The keys' ripple
                            // doesn't depend on this either: the router PUSHES
                            // each key's bulge into its own KeyPressState.
                            if settings.swipeTypingEnabled, settings.swipeShowTrail {
                                SwipeTrailOverlay(touch: touch,
                                                  color: theme.accent.color.opacity(0.55),
                                                  lineWidth: CGFloat(settings.swipeTrailWidth))
                            }
                            MultiTouchSurface(
                                router: touch,
                                frames: anchors.mapValues { proxy[$0] },
                                resolveSpec: { currentKeySpecs()[$0] },
                                // Pressing any key while the picker is open
                                // dismisses it — the user's typing, not choosing.
                                onPressDown: { dismissPickerOnInput(); onAnyTap() },
                                lingerDuration: settings.keyPressLinger,
                                minPressVisible: settings.minPressVisible,
                                hitboxScale: settings.hitboxScale,
            adaptiveEnabled: settings.adaptiveHitboxes,
            adaptiveGrow: settings.adaptiveGrow,
            adaptiveShrink: settings.adaptiveShrink,
            adaptivePredictionWeight: settings.adaptivePredictionWeight,
            adaptivePredictAtWordStart: settings.adaptivePredictAtWordStart,
            // Pulled at touch time, so per-keystroke updates never re-render
            // the surface. Word-aware (lexicon-derived); nil → English tables.
            predictedDistribution: { [live] in live.predictedDistribution },
                                cursorStride: CGFloat(settings.spaceCursorStride),
                                cursorActivationDelay: settings.spaceCursorActivationDelay / 1000,
                                cursorLineStride: Int(settings.cursorLineStride),
                                cursorCombined: settings.cursorMovementType == .combined,
                                repeatHoldDelay: settings.repeatHoldDelay / 1000,
                                repeatInitialInterval: Int(settings.repeatInitialInterval),
                                repeatMinInterval: Int(settings.repeatMinInterval),
                                repeatAccelStep: Int(settings.repeatAccelStep),
                                accentsEnabled: settings.accentPopupsEnabled,
                                accentHoldDelay: settings.accentHoldDelay / 1000,
                                accentMoveCancel: CGFloat(settings.accentMoveCancel),
                                deleteWordEngage: CGFloat(settings.deleteWordSwipeEngage),
                                deleteWordStride: CGFloat(settings.deleteWordSwipeStride),
                                dragUpThreshold: CGFloat(settings.dragUpThreshold),
                                surfaceWidth: proxy.size.width,
                                // Only while typing into the host — never with a
                                // panel (notepad/calc/…) composing, where the swipe
                                // callbacks' host-document edits wouldn't apply.
                                swipeEnabled: settings.swipeTypingEnabled && live.activePanel == nil,
                                swipeMorphEnabled: settings.swipeTypingEnabled && settings.swipeKeyMorph,
                                swipeMorphRadius: CGFloat(settings.swipeMorphRadius),
                                onSwipeStart: onSwipeStart,
                                onSwipeEnd: onSwipeEnd)
                        }
                    }
                    // User breathing room: space above the keys (below the bar) and
                    // below the keys (lifting the keyboard up). Wraps the touch
                    // overlay too, so hit frames shift with the keys.
                    .padding(.top, CGFloat(settings.keyboardTopPadding))
                    .padding(.bottom, CGFloat(settings.keyboardBottomPadding))
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
                        .animation(settings.keyPressInstant ? nil : .interactiveSpring(response: settings.keySpringResponse, dampingFraction: settings.keySpringDamping), value: g.scaleX)
                        // GlassEffectContainer's implicit animation bleeds into this
                        // ForEach, fading out removed items (e.g. delete glyph at its
                        // old keyID) before the replacement fades in — leaving a gap.
                        // Identity transition snaps glyphs in/out immediately so the
                        // delete key never disappears during a plane switch.
                        .transition(.identity)
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
        // Accent long-press bar: floats above the held key, options + highlight
        // driven live by the router (slide to choose, release to commit).
        .overlayPreferenceValue(AccentPopupKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, !touch.accentOptions.isEmpty {
                    let keyRect = proxy[anchor]
                    let count = touch.accentOptions.count
                    let w = AccentPicker.width(count: count)
                    let left = AccentPicker.barLeft(keyMidX: keyRect.midX, count: count,
                                                    containerWidth: proxy.size.width)
                    AccentPicker(options: touch.accentOptions, selected: touch.accentIndex, theme: theme, cornerRadius: CGFloat(settings.keyCornerRadius))
                        .position(x: left + w / 2,
                                  y: max(AccentPicker.height / 2 + 2, keyRect.minY - AccentPicker.height / 2 - 6))
                }
            }
            .allowsHitTesting(false)
        }
        // Hitbox debug overlay: outlines each key's touch area. Only visible in
        // the Advanced settings view (showHitboxOverlay = true).
        .overlayPreferenceValue(KeyFrameKey.self) { anchors in
            if showHitboxOverlay {
                GeometryReader { proxy in
                    let base = CGFloat(settings.hitboxScale)
                    // Adaptive on: mirror the router's per-letter flex so the
                    // outlines show the *real* hit regions (green grown, orange
                    // shrunk) for the predicted next letter.
                    let adaptive = settings.adaptiveHitboxes
                        && (touch.predictedFrom != nil || settings.adaptivePredictAtWordStart)
                    let specs = adaptive ? currentKeySpecs() : [:]
                    // Mirror the router's preference: the engine's word-aware
                    // distribution when present, the English tables otherwise.
                    let factors: [Character: Double] = if !adaptive {
                        [:]
                    } else if let dist = live.predictedDistribution {
                        AdaptiveHitbox.factorMap(distribution: dist,
                                                 grow: settings.adaptiveGrow,
                                                 shrink: settings.adaptiveShrink)
                    } else {
                        AdaptiveHitbox.factorMap(prev: touch.predictedFrom,
                                                 grow: settings.adaptiveGrow,
                                                 shrink: settings.adaptiveShrink,
                                                 predictionWeight: settings.adaptivePredictionWeight)
                    }
                    ForEach(anchors.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                        let f = proxy[pair.value]
                        let letter = adaptive ? glyphLetter(specs[pair.key]) : nil
                        let factor = letter.flatMap { factors[$0] } ?? 1.0
                        let scale = base * CGFloat(factor)
                        let w = f.width * scale
                        let h = f.height * scale
                        let color = adaptive ? AdaptiveHitbox.tint(factor) : Color.cyan
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(color.opacity(0.75), lineWidth: 1.5)
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
        .overlayPreferenceValue(KeyFrameKey.self) { anchors in
            if pickerOpen && settings.panelPickerStyle == .popover && enabledPanels.count >= 2 {
                GeometryReader { proxy in
                    // The 123 key (bottom row, index 0) in this overlay's space,
                    // so a slide-up popover can float right above it. Falls back
                    // to the icon anchor if the frame isn't available.
                    let keyFrame = anchors["bottom-0"].map { proxy[$0] }
                    panelPopover(slideUpKeyFrame: pickerOrigin == .slideUp ? keyFrame : nil)
                }
            }
        }
        .onChange(of: live.activePanel) { _, new in
            guard new == .clipboard, settings.autoCopyOnClipboardOpen, hasFullAccess else { return }
            clipboard.captureFromPasteboard()
        }
        // Invalidate the keyspec cache when anything other than plane/shift (which
        // the cache keys on directly) changes the keys: settings, the host-driven
        // return-key label, or whether any panel is enabled (drives the 123 key's
        // slide-up handlers).
        .onChange(of: settings) { keySpecCache.invalidate() }
        .onChange(of: keySpecExternalsSignature) { keySpecCache.invalidate() }
    }

    /// A cheap Equatable fingerprint of the non-plane/shift inputs to the keyspecs
    /// (the return-key label + whether any panel is enabled). Changing it clears
    /// the cache so the next resolve rebuilds.
    private var keySpecExternalsSignature: String {
        "\(live.returnKeySymbol ?? "")|\(live.returnKeyTitle)|\(live.returnKeyProminent)|\(enabledPanels.isEmpty)"
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
        // Lean left and swell while swiping to delete words — a continuous cue that
        // rides over the discrete per-word bounce. Pure geometry: it never touches
        // the symbol's name/content, so it can't trip the replace transition and
        // drop the glyph. No-op on every non-delete glyph.
        .scaleEffect(g.deleteSwiping ? 1.18 : 1, anchor: .center)
        .offset(x: g.deleteSwiping ? -4 : 0)
        .animation(.snappy(duration: 0.22), value: g.deleteSwiping)
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
                // The middle letter row is the home row — the only one iOS indents.
                // `homeRowIndex` accounts for any custom rows placed above letters.
                let isHomeRow = idx == homeRowIndex
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

    /// Index within `currentRows` of the home (middle letter) row — the only row
    /// iOS indents. Shifts down by however many non-empty custom rows sit above
    /// the letters. nil off the letters plane or when the layout isn't 3 rows.
    private var homeRowIndex: Int? {
        guard plane == .letters, settings.layout.rows.count == 3 else { return nil }
        let aboveCount = settings.customRows
            .filter { $0.position == .aboveLetters && !$0.keys.isEmpty }.count
        return aboveCount + 1
    }

    private var currentRows: [[KeySpec]] {
        switch plane {
        case .letters:
            let rows = settings.layout.rows
            let letterRows: [[KeySpec]] = rows.enumerated().map { idx, keys in
                if idx == rows.count - 1 {
                    // Last letter row gets shift (lead) + backspace (trail).
                    return [shiftKey] + keys.map { letterKey($0) } + [backspaceKey]
                }
                return keys.map { letterKey($0) }
            }
            // User-defined rows wrap the letters: `aboveLetters` on top (under the
            // number row), `belowLetters` underneath (above the function row).
            // Empty rows are skipped so they don't leave a blank gap.
            func customSpecRows(_ pos: CustomRowPosition) -> [[KeySpec]] {
                settings.customRows
                    .filter { $0.position == pos && !$0.keys.isEmpty }
                    .map { $0.keys.map { customKeySpec($0) } }
            }
            return customSpecRows(.aboveLetters) + letterRows + customSpecRows(.belowLetters)
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
            let slideEnabled = settings.activateWithSlideUp && !enabledPanels.isEmpty
            specs.append(planeKey(
                "123", to: .numbers, weight: Self.planeToggleWeight,
                onDragUp: slideEnabled ? { slideUpActivate() } : nil,
                // Continuous tracking only matters for the popover picker, where the
                // finger can drag onto a row; inline/cards just open on the up-gesture.
                onDragUpMove: slideEnabled ? { slideHoverUpdate($0) } : nil,
                onDragUpEnd: slideEnabled ? { slideDragEnd($0) } : nil))
        } else {
            specs.append(planeKey("ABC", to: .letters, weight: Self.planeToggleWeight))
        }
        // Dedicated emoji key (opt-in): sits right next to 123 / ABC and opens
        // the emoji keyboard directly. When on, emoji leaves the panel picker
        // (see `enabledPanels`), so this is its sole entry point.
        let emojiKey = settings.emojiKeyInRow && settings.emojiEnabled
        if emojiKey {
            specs.append(.init(kind: .function, label: .system("face.smiling"), weight: Self.emojiRowKeyWeight) {
                activate(.emoji)
            })
        }
        // Globe — only in the extension (host passes a handler).
        if onNextKeyboard != nil {
            specs.append(.init(kind: .function, label: .system("globe"), weight: 1.2,
                               isNextKeyboard: true) {
                onNextKeyboard?()
            })
        }
        // User-defined keys to the left of the space bar (the Gboard quick-comma
        // layout). Letters plane only; the proportional row auto-narrows space.
        if plane == .letters {
            specs.append(contentsOf: settings.spaceBarLeadingKeys.map { customKeySpec($0) })
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
        // User-defined keys to the right of the space bar, before the return key
        // (the Gboard quick-period layout). Letters plane only.
        if plane == .letters {
            specs.append(contentsOf: settings.spaceBarTrailingKeys.map { customKeySpec($0) })
        }
        // Return key follows the host field: a ⏎ glyph for a plain return, the
        // action word ("Go", "Search", "Send", …) otherwise — prominent (accent)
        // for action types, exactly like the system keyboard.
        let returnLabel: KeySpec.Label = live.returnKeySymbol.map { .system($0) }
            ?? .text(live.returnKeyTitle)
        // With the dedicated emoji key on the leading side, widen the return key to
        // match 123 + emoji so the space bar stays centred between equal flanks.
        let returnWeight = emojiKey ? (Self.planeToggleWeight + Self.emojiRowKeyWeight) : 1.8
        specs.append(.init(kind: .function, label: returnLabel,
                           weight: returnWeight, highlighted: live.returnKeyProminent) {
            insert("\n")
        })
        return specs
    }

    /// Weight of the 123 / ABC plane-toggle key in the bottom row.
    private static let planeToggleWeight: Double = 1.4
    /// Weight of the optional dedicated emoji key beside 123.
    private static let emojiRowKeyWeight: Double = 1.2

    /// Every on-screen key, keyed by the same `"\(rowID)-\(index)"` ID the rows
    /// render with — so the multitouch router can resolve a hit-tested key back to
    /// its current spec (action + behaviour). Rebuilt on demand at touch time, so
    /// it always reflects the live plane / shift. Mirrors `rowStack` exactly.
    /// keyID → spec for the live plane/shift. Resolved on every touch (often many
    /// times per gesture by the hit-test / adaptive / swipe loops), so it's
    /// memoized: rebuilt only when the plane or shift actually changes (the inputs
    /// that vary while typing). Settings / return-key / panel changes invalidate
    /// the cache from the body's `.onChange` handlers.
    private func currentKeySpecs() -> [String: KeySpec] {
        keySpecCache.resolve(plane: plane, shift: shift) { buildKeySpecs() }
    }

    private func buildKeySpecs() -> [String: KeySpec] {
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

    /// The lowercased letter a key types, or nil for non-letter keys — used by the
    /// adaptive hitbox overlay to size/tint each outline like the router does.
    private func glyphLetter(_ spec: KeySpec?) -> Character? {
        guard let spec, spec.kind == .character, !spec.isSpace,
              case let .text(s) = spec.label, let ch = s.lowercased().first, ch.isLetter
        else { return nil }
        return ch
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
                isDestructive: true, isRepeatable: true,
                onDeleteWord: settings.swipeToDeleteWord ? { [self] in deleteWord() } : nil) {
            backspace()
        }
    }

    private func letterKey(_ base: String) -> KeySpec {
        let shifted = shift != .off
        let glyph = shifted ? base.uppercased() : base
        // Accent options (base + its diacritics, cased to match) for the
        // long-press bar; empty disables the bar on this key.
        let accents = settings.accentPopupsEnabled ? AccentMap.options(forCasedGlyph: glyph) : []
        return KeySpec(kind: .character, label: .text(glyph), weight: 1,
                       accents: accents,
                       onAccentCommit: accents.isEmpty ? nil : { [self] chosen in
                           // The base was already inserted on touch-down; only
                           // replace it when a different variant was picked.
                           guard chosen != glyph else { return }
                           backspace()
                           insert(chosen)
                       }) {
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

    /// A user-defined key (Layout → Custom tab). `insert` keys type their payload
    /// and, when single-character, expose long-press alternates through the same
    /// accent machinery as letter keys (independent of the letter-accent toggle
    /// via `accentsAlwaysOn`). The other actions mirror behaviours the canvas
    /// already drives — cursor nudge, plane switch, emoji panel, backspace.
    private func customKeySpec(_ key: CustomKey) -> KeySpec {
        let label: KeySpec.Label = key.isSymbol ? .system(key.glyph) : .text(key.glyph)
        switch key.action {
        case let .insert(text):
            // Long-press alternates only for a single-character insert: the base
            // is typed on touch-down and a chosen variant replaces it with a
            // single backspace, which only lines up when the base is one glyph.
            let options = (text.count == 1 && !key.alternates.isEmpty) ? [text] + key.alternates : []
            return KeySpec(kind: .character, label: label, weight: key.width,
                           accents: options,
                           onAccentCommit: options.isEmpty ? nil : { [self] chosen in
                               guard chosen != text else { return }
                               backspace()
                               insert(chosen)
                           },
                           accentsAlwaysOn: !options.isEmpty) {
                insert(text)
                lastKeyWasPunctuation = false
            }
        case .cursorLeft:
            return KeySpec(kind: .function, label: label, weight: key.width) { [self] in
                onCursorMove(-1)
            }
        case .cursorRight:
            return KeySpec(kind: .function, label: label, weight: key.width) { [self] in
                onCursorMove(1)
            }
        case .tab:
            return KeySpec(kind: .character, label: label, weight: key.width) { [self] in
                insert("\t")
            }
        case .numbersPlane:
            return KeySpec(kind: .function, label: label, weight: key.width) { [self] in
                plane = .numbers
                lastKeyWasPunctuation = false
            }
        case .emoji:
            return KeySpec(kind: .function, label: label, weight: key.width) { [self] in
                activate(.emoji)
            }
        case .backspace:
            return KeySpec(kind: .function, label: label, weight: key.width,
                           isDestructive: true, isRepeatable: true,
                           onDeleteWord: settings.swipeToDeleteWord ? { [self] in deleteWord() } : nil) { [self] in
                backspace()
            }
        }
    }

    private func planeKey(_ glyph: String, to target: Plane, weight: Double,
                          onDragUp: (() -> Void)? = nil,
                          onDragUpMove: ((CGPoint) -> Void)? = nil,
                          onDragUpEnd: ((CGPoint) -> Void)? = nil) -> KeySpec {
        KeySpec(kind: .function, label: .text(glyph), weight: weight,
                onDragUp: onDragUp, onDragUpMove: onDragUpMove, onDragUpEnd: onDragUpEnd) {
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

    /// Delete the whole word before the cursor (backspace swipe gesture). Routed
    /// like `backspace`; on the notepad scratch buffer it strips trailing
    /// whitespace and then the preceding word locally.
    private func deleteWord() {
        if live.activePanel == .notepad {
            var s = notepad.scratch
            while let last = s.last, last == " " || last == "\n" || last == "\t" { s.removeLast() }
            while let last = s.last, !(last == " " || last == "\n" || last == "\t") { s.removeLast() }
            notepad.scratch = s
        } else {
            onDeleteWord()
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
                            swipeMorph: settings.swipeTypingEnabled && settings.swipeKeyMorph,
                            swipeMorphStrength: CGFloat(settings.swipeMorphStrength),
                            keyID: "\(rowID)-\(i)",
                            simulatedPressed: controller.pressedKeyID == "\(rowID)-\(i)",
                            router: touch,
                            physics: physics)
                        .frame(width: unit * CGFloat(spec.weight))
                        // Plane switches (ABC ⇄ 123 ⇄ #+=) change a row's key count,
                        // so the tail keys insert/remove. Inside GlassEffectContainer
                        // that runs the glass *appear* animation — the "key builds in"
                        // glitch (e.g. the " key on the symbols plane). Snap them in/out
                        // instead, exactly as the glyph layer does (see its note above).
                        .transition(.identity)
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

/// Render-isolation wrapper for the swipe trail: the router's live trail is
/// read in THIS body, so each finger sample re-renders only the stroke — not
/// the surrounding overlay closure that hosts the `MultiTouchSurface`. The
/// keys' ripple is independent of this view: the router pushes per-key bulge
/// values into each `KeyPressState` as the trail advances.
private struct SwipeTrailOverlay: View {
    var touch: KeyTouchRouter
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        if touch.swipeActive, touch.swipeTrail.count > 1 {
            SwipeTrailShape(points: touch.swipeTrail)
                .stroke(color,
                        style: StrokeStyle(lineWidth: lineWidth,
                                           lineCap: .round, lineJoin: .round))
                .allowsHitTesting(false)
        }
    }
}

/// Render-isolation wrapper for the suggestion bar: the observable `live`
/// suggestion properties are read in THIS body, so a suggestion recompute
/// invalidates just this view — `KeyboardCanvas.body` (and the whole key grid
/// it builds) stays untouched.
private struct LiveSuggestionBar: View {
    var live: KeyboardLiveState
    let theme: Theme
    let onTap: (String) -> Void
    let onKeepTyped: () -> Void
    let onEmoji: (String) -> Void
    let hitboxScale: Double

    var body: some View {
        SuggestionBar(suggestions: live.suggestions,
                      autocorrection: live.autocorrection,
                      emoji: live.emojiSuggestions, theme: theme,
                      onTap: onTap, onKeepTyped: onKeepTyped,
                      onEmoji: onEmoji,
                      hitboxScale: hitboxScale)
    }
}
