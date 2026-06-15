/**
 Reusable layout containers for settings screens with a live keyboard preview, and
 the `KeyboardPreview` widget itself — a fully interactive `KeyboardCanvas` inside
 the app for real-time theme and layout feedback.
 

 Module: app-ui · Target: Clink
 Learn: docs/02-keyboard-core.md
 */
import SwiftUI
import UIKit
import iUXiOS

/// A settings screen whose live keyboard preview stays pinned at the top while
/// the controls scroll beneath it — so every change is visible the moment you
/// make it, without scrolling the preview off-screen. Used by the Layout, Theme,
/// and Typing editors so they all feel the same.
struct PinnedPreviewLayout<Content: View>: View {
    @Environment(\.resolvedKeyboardTheme) private var theme
    @Environment(\.colorScheme) private var systemScheme
    let settings: KeyboardSettings
    var showHitboxOverlay: Bool = false
    var previewColorScheme: ColorScheme? = nil
    var previewCursorActive: Bool = false
    /// When set, the preview field is pre-filled and key taps are disabled so only
    /// cursor drags work — used by the Cursor settings page.
    var lockedPreviewText: String? = nil
    /// Optional bar pinned to the BOTTOM, below the scrolling controls (e.g. the
    /// Theme editor's Light/Dark tab). Stays fixed while the content scrolls.
    var bottomBar: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            KeyboardPreview(settings: settings, showHitboxOverlay: showHitboxOverlay,
                            previewCursorActive: previewCursorActive,
                            lockedText: lockedPreviewText)
                .padding(.horizontal, UX.screenPadding)
                .padding(.top, UX.screenPadding)
                .padding(.bottom, UX.cardSpacing)
                // A hairline keeps the pinned preview visually distinct from the
                // controls sliding under it as you scroll.
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.4)
                }

            ScrollView {
                VStack(spacing: UX.cardSpacing) {
                    content
                }
                .padding(.horizontal, UX.screenPadding)
                .padding(.top, UX.cardSpacing)
                .padding(.bottom, UX.screenPadding)
            }

            if let bottomBar {
                bottomBar
                    .tint(theme.accent.color)
                    .padding(.horizontal, UX.screenPadding)
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Divider().opacity(0.4) }
            }
        }
        .themePageBackground()
        // When a specific appearance is requested, drive the whole page (preview
        // and any colorScheme-resolving controls) into it, regardless of device.
        .environment(\.colorScheme, previewColorScheme ?? systemScheme)
        .preferredColorScheme(previewColorScheme)
    }
}

/// One tab in a `TabbedPreviewLayout`: a short label and the controls shown when
/// it's selected.
struct PreviewTab: Identifiable {
    let id: String
    let label: String
    let content: AnyView

    init<V: View>(_ label: String, @ViewBuilder content: () -> V) {
        self.id = label
        self.label = label
        self.content = AnyView(content())
    }
}

/// Like `PinnedPreviewLayout`, but the controls below the pinned preview are
/// split across tabs whose bar is pinned to the BOTTOM — like a normal tabbed
/// page. The preview AND the tab bar stay fixed; only the selected tab's
/// controls scroll between them.
struct TabbedPreviewLayout: View {
    @Environment(\.resolvedKeyboardTheme) private var theme
    let settings: KeyboardSettings
    let tabs: [PreviewTab]
    /// Forces the preview AND its controls into a specific appearance, so a theme
    /// can be previewed dark even while the device is light (and vice versa).
    var previewColorScheme: ColorScheme? = nil
    @State private var selection: String

    init(settings: KeyboardSettings, previewColorScheme: ColorScheme? = nil, tabs: [PreviewTab]) {
        self.settings = settings
        self.previewColorScheme = previewColorScheme
        self.tabs = tabs
        _selection = State(initialValue: tabs.first?.id ?? "")
    }

    private var current: PreviewTab? {
        tabs.first { $0.id == selection } ?? tabs.first
    }

    /// The theme being previewed, taken from `settings` rather than the inherited
    /// environment — so the tab pills track the theme under edit, not the app's.
    private var previewTheme: Theme { settings.theme }

    var body: some View {
        VStack(spacing: 0) {
            KeyboardPreview(settings: settings)
                .padding(.horizontal, UX.screenPadding)
                .padding(.top, UX.screenPadding)
                .padding(.bottom, UX.cardSpacing)
                .overlay(alignment: .bottom) { Divider().opacity(0.4) }

            ScrollView {
                VStack(spacing: UX.cardSpacing) {
                    current?.content
                }
                .padding(.horizontal, UX.screenPadding)
                .padding(.top, UX.cardSpacing)
                .padding(.bottom, UX.screenPadding)
            }
            // Reset to the top when switching tabs so each page starts fresh.
            .id(selection)

            ThemedTabPicker(options: tabs.map { ($0.label, $0.id) }, selection: $selection)
                .tint(previewTheme.accent.color)
                .environment(\.specialKeyTint, previewTheme.specialKeyFill.color)
                .environment(\.cardCornerRadius, settings.keyCornerRadius)
                .padding(.horizontal, UX.screenPadding)
                .padding(.vertical, 12)
                .overlay(alignment: .top) { Divider().opacity(0.4) }
        }
        .themePageBackground()
        // Pin the whole editor — preview and the controls resolving theme via
        // colorScheme — to the previewed appearance, regardless of the device.
        .environment(\.colorScheme, previewColorScheme ?? systemScheme)
        .preferredColorScheme(previewColorScheme)
    }

    @Environment(\.colorScheme) private var systemScheme
}

/// A value-bound picker drawn as a row of themed chips — the same look as
/// `PresetChips` (accent fill when selected, special-key fill otherwise), but
/// for picking a discrete value rather than applying a preset. Use in place of
/// `Picker(.segmented)` so option pickers match the rest of the app.
struct ThemedChipPicker<Tag: Hashable>: View {
    @Environment(\.cardCornerRadius) private var cornerRadius
    let options: [(label: String, tag: Tag)]
    @Binding var selection: Tag
    /// Selected-chip fill — pass the theme accent.
    var accent: Color
    /// Unselected-chip fill — pass the theme's special-key fill.
    var inactive: Color
    /// When true, chips share the width equally. When false they size to their
    /// label and the row scrolls horizontally — use for many options.
    var fillWidth: Bool = true

    var body: some View {
        if fillWidth {
            HStack(spacing: 8) { chips }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { chips }.padding(.horizontal, 2)
            }
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(options, id: \.tag) { option in
            let isSelected = selection == option.tag
            Button { selection = option.tag } label: {
                Text(option.label)
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: fillWidth ? .infinity : nil)
                    .padding(.horizontal, fillWidth ? 0 : 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .background(
                        isSelected ? AnyShapeStyle(accent) : AnyShapeStyle(inactive),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .animation(Motion.selectionFade.animation, value: isSelected)
        }
    }
}

/// A solid-fill button style that follows the theme — accent (or any passed)
/// fill, white label, key rounding. Replaces `.buttonStyle(.bordered)` so action
/// buttons match the rest of the themed editor.
struct ThemedFillButtonStyle: ButtonStyle {
    var fill: Color
    var corner: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(fill, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Motion.previewKeyPress.animation, value: configuration.isPressed)
    }
}

/// A themed segmented tab picker — accent fill on the selected tab, matching
/// the key corner radius. Replaces `Picker(.segmented)` which ignores `.tint`
/// for the selected background on iOS 26.
struct ThemedTabPicker<Tag: Hashable>: View {
    @Environment(\.cardCornerRadius) private var cornerRadius
    @Environment(\.specialKeyTint) private var specialKeyTint
    let options: [(label: String, tag: Tag)]
    @Binding var selection: Tag
    var disabledTags: Set<Tag> = []

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.tag) { option in
                let isSelected = selection == option.tag
                let isDisabled = disabledTags.contains(option.tag)
                Button { selection = option.tag } label: {
                    Text(option.label)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear),
                            in: RoundedRectangle(cornerRadius: max(2, cornerRadius - 4), style: .continuous)
                        )
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .opacity(isDisabled ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .animation(Motion.selectionFade.animation, value: isSelected)
            }
        }
        .padding(4)
        .background(specialKeyTint ?? Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A live, interactive preview of the real keyboard — the exact `KeyboardCanvas`
/// the extension renders, wired to a local string so the user can try their
/// theme/layout right inside the app without leaving to another app.
///
/// Callbacks are preview stubs: they mutate local `@State` (`typed`, `cursorPos`)
/// instead of a document proxy. `lockedText` disables insert/backspace so cursor
/// tuning pages can drag in isolation.
struct KeyboardPreview: View {
    @Environment(\.resolvedKeyboardTheme) private var envTheme
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @Environment(AppModel.self) private var appModel
    let settings: KeyboardSettings
    var showHitboxOverlay: Bool = false
    var previewCursorActive: Bool = false
    /// When set the field is pre-filled with this text on appear and key taps
    /// (insert, backspace, suggestions) become no-ops — only cursor drags work.
    var lockedText: String? = nil
    @State private var typed: String = ""
    @State private var cursorPos: Int = 0
    // The bar starts empty and fills from the real engine as the user types —
    // same `KeyboardLiveState` the extension drives. Locked previews pass a
    // throwaway state so tapping a chip can't mutate the sample text.
    @State private var live = KeyboardLiveState()
    /// The real suggestion engine, so the in-app preview produces the exact same
    /// predictions / completions / emoji the keyboard extension does — including
    /// learned and custom-dictionary words via `UserAdaptation`.
    private let suggestEngine = SuggestionEngine()
    /// In-flight Apple Intelligence prediction + a seq guard, mirroring the
    /// extension so a slow response can't overwrite newer preview text.
    @State private var aiTask: Task<Void, Never>?
    @State private var aiSeq = 0

    /// Triadic gradient derived from the theme accent — vibrant enough to give
    /// glass something to refract, distinct enough not to blend with the keyboard.
    private var backdropGradient: LinearGradient {
        let ui = UIColor(envTheme.accent.color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Clamp to a vibrant, visible range so dark/desaturated accents still pop
        let vs = max(0.5, min(1.0, s))
        let vb = max(0.55, min(0.95, b))
        let c1 = Color(UIColor(hue: h,                   saturation: vs,       brightness: vb,              alpha: 1))
        let c2 = Color(UIColor(hue: fmod(h + 0.33, 1.0), saturation: vs * 0.9, brightness: min(1, vb * 1.1), alpha: 1))
        let c3 = Color(UIColor(hue: fmod(h + 0.67, 1.0), saturation: vs * 0.8, brightness: vb * 0.85,       alpha: 1))
        return LinearGradient(colors: [c1, c2, c3], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var displayText: AttributedString {
        guard !typed.isEmpty else { return AttributedString() }
        let pos = min(cursorPos, typed.count)
        let idx = typed.index(typed.startIndex, offsetBy: pos)
        var result = AttributedString(typed[..<idx])
        var cursor = AttributedString("│")
        cursor.foregroundColor = UIColor(envTheme.accent.color)
        result += cursor
        result += AttributedString(typed[idx...])
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Faux text field showing what's been typed, with a cursor marker
            // at the current position so cursor-mode drags are visible.
            HStack {
                if typed.isEmpty {
                    Text("Try it out…").foregroundStyle(.secondary)
                } else {
                    Text(displayText).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                // Clear button is hidden in locked mode so the sample text
                // can't be erased and cursor drags always have text to navigate.
                if !typed.isEmpty && lockedText == nil {
                    Button {
                        typed = ""
                        cursorPos = 0
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(envTheme.keyFill.color)

            // A representative backdrop sits behind the keyboard so Liquid
            // Glass themes have something to refract — mirroring how the real
            // keyboard floats over app content. Solid themes have an opaque
            // background and simply cover it.
            // Preview stub callbacks: mutate local `typed` / `cursorPos` only.
            // In locked mode (`lockedText != nil`) insert/backspace/suggestion
            // handlers no-op so cursor drags can be tuned in isolation.
            KeyboardCanvas(
                settings: settings,
                live: lockedText != nil ? KeyboardLiveState() : live,
                clipboard: appModel.clipboard,
                notepad: appModel.notepad,
                extensions: appModel.extensions,
                panels: appModel.panels,
                hasFullAccess: appModel.hasFullAccess,
                showHitboxOverlay: showHitboxOverlay,
                previewCursorActive: previewCursorActive,
                onInsert: { text in
                    guard lockedText == nil else { return }
                    let idx = typed.index(typed.startIndex, offsetBy: min(cursorPos, typed.count))
                    typed.insert(contentsOf: text, at: idx)
                    cursorPos = min(typed.count, cursorPos + text.count)
                },
                onBackspace: {
                    guard lockedText == nil else { return }
                    guard cursorPos > 0, !typed.isEmpty else { return }
                    let pos = min(cursorPos, typed.count)
                    let idx = typed.index(typed.startIndex, offsetBy: pos - 1)
                    typed.remove(at: idx)
                    cursorPos = pos - 1
                },
                onDeleteWord: {
                    guard lockedText == nil, cursorPos > 0, !typed.isEmpty else { return }
                    let pos = min(cursorPos, typed.count)
                    let endIdx = typed.index(typed.startIndex, offsetBy: pos)
                    var idx = endIdx
                    // Step back over trailing spaces, then over the word.
                    while idx > typed.startIndex && typed[typed.index(before: idx)] == " " {
                        idx = typed.index(before: idx)
                    }
                    while idx > typed.startIndex && typed[typed.index(before: idx)] != " " {
                        idx = typed.index(before: idx)
                    }
                    let deleteCount = typed.distance(from: idx, to: endIdx)
                    typed.removeSubrange(idx ..< endIdx)
                    cursorPos = pos - deleteCount
                },
                onAnyTap: {
                    guard settings.hapticsEnabled else { return }
                    let style: UIImpactFeedbackGenerator.FeedbackStyle = {
                        switch settings.hapticStyle {
                        case .light:  return .light
                        case .medium: return .medium
                        case .heavy:  return .heavy
                        case .rigid:  return .rigid
                        case .soft:   return .soft
                        }
                    }()
                    let gen = UIImpactFeedbackGenerator(style: style)
                    gen.impactOccurred(intensity: settings.hapticIntensity)
                },
                onSuggestion: { text in
                    guard lockedText == nil else { return }
                    typed += text + " "
                    cursorPos = typed.count
                },
                onEmojiSuggestion: { emoji in
                    guard lockedText == nil else { return }
                    // Replace the word before the cursor with the emoji.
                    let pos = min(cursorPos, typed.count)
                    let head = typed[..<typed.index(typed.startIndex, offsetBy: pos)]
                    let wordStart: String.Index
                    if let lastSpace = head.lastIndex(of: " ") {
                        wordStart = head.index(after: lastSpace)
                    } else {
                        wordStart = head.startIndex
                    }
                    typed.replaceSubrange(wordStart ..< typed.index(typed.startIndex, offsetBy: pos), with: emoji + " ")
                    cursorPos = typed.distance(from: typed.startIndex, to: wordStart) + emoji.count + 1
                },
                onCursorMove: { delta in
                    cursorPos = max(0, min(typed.count, cursorPos + delta))
                },
                onClipboardInsert: { text in
                    guard lockedText == nil else { return }
                    let idx = typed.index(typed.startIndex, offsetBy: min(cursorPos, typed.count))
                    typed.insert(contentsOf: text, at: idx)
                    cursorPos = min(typed.count, cursorPos + text.count)
                },
                onNotepadInsert: { text in
                    guard lockedText == nil else { return }
                    let idx = typed.index(typed.startIndex, offsetBy: min(cursorPos, typed.count))
                    typed.insert(contentsOf: text, at: idx)
                    cursorPos = min(typed.count, cursorPos + text.count)
                },
                onCalculatorInsert: { text in
                    guard lockedText == nil else { return }
                    let idx = typed.index(typed.startIndex, offsetBy: min(cursorPos, typed.count))
                    typed.insert(contentsOf: text, at: idx)
                    cursorPos = min(typed.count, cursorPos + text.count)
                },
                onPanelInsert: { text in
                    guard lockedText == nil else { return }
                    let idx = typed.index(typed.startIndex, offsetBy: min(cursorPos, typed.count))
                    typed.insert(contentsOf: text, at: idx)
                    cursorPos = min(typed.count, cursorPos + text.count)
                }
            )
            // Pin to the same content height the extension uses, so the preview
            // has no indefinite-height gap below the keys.
            .frame(height: KeyboardCanvas.preferredHeight(for: settings, hasFullAccess: appModel.hasFullAccess))
            .background { backdropGradient }
        }
        .onAppear {
            // In locked mode, pre-fill the field with the sample text and place
            // the cursor in the middle so there's room to drag in either direction.
            if let lockedText, typed.isEmpty {
                typed = lockedText
                cursorPos = lockedText.count / 2
            }
            // Locked previews are for cursor tuning and pass an empty live state,
            // so there's nothing to compute. Otherwise prime the engine.
            guard lockedText == nil else { return }
            suggestEngine.setLanguages(settings.keyboardLanguages)
            suggestEngine.setAdaptation(UserAdaptation.shared)
            // Warm the model so the first AI suggestion isn't slow. No-op when AI
            // is off / unavailable (the actor guards internally).
            if settings.aiEnabled && settings.aiCompletions {
                Task { await AIEngine.shared.prewarm(instructions: AIEngine.suggestionInstructions) }
            }
            refreshSuggestions()
            refreshAISuggestions()
        }
        .onChange(of: typed) { _, _ in
            guard lockedText == nil else { return }
            refreshSuggestions()
            refreshAISuggestions()
        }
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    // MARK: - Live suggestions

    /// Recompute the bar from the text typed so far, exactly like the extension's
    /// `fastComputeSuggestions`. Auto-correction is left off — the preview is for
    /// trying predictions, not for silently rewriting what the user types.
    private func refreshSuggestions() {
        guard settings.suggestionsEnabled else {
            if !live.suggestions.isEmpty { live.suggestions = [] }
            if !live.emojiSuggestions.isEmpty { live.emojiSuggestions = [] }
            return
        }
        let before = String(typed.prefix(min(cursorPos, typed.count)))
        let partial = SmartPunctuation.trailingPartialWord(in: before)
        let result = suggestEngine.compute(
            partial: partial,
            previousWord: previousWord(before: before, partial: partial),
            sentenceStart: isSentenceStart(before: before, partial: partial),
            autocorrect: false,
            autoPunctuation: false,
            rejected: nil)
        live.suggestions = result.predictions
        live.emojiSuggestions = result.emoji
    }

    private func previousWord(before: String, partial: String) -> String? {
        guard partial.isEmpty else { return nil }
        let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, !".!?".contains(last) else { return nil }
        let word = SmartPunctuation.trailingPartialWord(in: trimmed)
        return word.isEmpty ? nil : word
    }

    private func isSentenceStart(before: String, partial: String) -> Bool {
        guard partial.isEmpty else { return false }
        let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if let last = trimmed.last, ".!?".contains(last) { return true }
        return false
    }

    /// Augment the bar with Apple Intelligence predictions, exactly like the
    /// extension's `aiComputeSuggestions`. On the simulator this uses the host
    /// Mac's Apple Intelligence; on a non-eligible setup the availability guard
    /// just clears any stale AI words.
    private func refreshAISuggestions() {
        aiTask?.cancel()
        guard settings.suggestionsEnabled, settings.aiEnabled, settings.aiCompletions,
              AIAvailability.current() == .available else {
            if !live.aiSuggestions.isEmpty { live.aiSuggestions = [] }
            return
        }
        let before = String(typed.prefix(min(cursorPos, typed.count)))
        let partial = SmartPunctuation.trailingPartialWord(in: before)
        // Completions only — nothing to complete at a word boundary.
        guard !partial.isEmpty else {
            if !live.aiSuggestions.isEmpty { live.aiSuggestions = [] }
            return
        }
        aiSeq += 1
        let seq = aiSeq
        aiTask = Task {
            let words = try? await AIEngine.shared.completions(context: before, partial: partial)
            guard let words, !Task.isCancelled, seq == aiSeq else { return }
            let lp = partial.lowercased()
            live.aiSuggestions = words.filter { $0.lowercased().hasPrefix(lp) && $0.count > lp.count }
        }
    }
}

/// A live, interactive preview of the real emoji keyboard — the exact
/// `EmojiCanvas` the extension renders, wired to a local buffer so the user can
/// browse, tone, and search emoji right inside the settings page while tuning
/// the layout controls beneath it. Mirrors `KeyboardPreview`.
struct EmojiPreview: View {
    @Environment(\.resolvedKeyboardTheme) private var envTheme
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    let settings: KeyboardSettings
    /// Persist a per-emoji skin-tone pick made by holding in the preview.
    var onSetSkinTone: (String, SkinTone) -> Void = { _, _ in }
    @State private var typed: String = ""

    /// Triadic gradient derived from the theme accent — same backdrop the letter
    /// preview floats over so Liquid Glass themes have something to refract.
    private var backdropGradient: LinearGradient {
        let ui = UIColor(envTheme.accent.color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let vs = max(0.5, min(1.0, s))
        let vb = max(0.55, min(0.95, b))
        let c1 = Color(UIColor(hue: h,                   saturation: vs,       brightness: vb,              alpha: 1))
        let c2 = Color(UIColor(hue: fmod(h + 0.33, 1.0), saturation: vs * 0.9, brightness: min(1, vb * 1.1), alpha: 1))
        let c3 = Color(UIColor(hue: fmod(h + 0.67, 1.0), saturation: vs * 0.8, brightness: vb * 0.85,       alpha: 1))
        return LinearGradient(colors: [c1, c2, c3], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Faux text field showing what's been inserted.
            HStack {
                Text(typed.isEmpty ? "Try it out…" : typed)
                    .foregroundStyle(typed.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 0)
                if !typed.isEmpty {
                    Button { typed = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(envTheme.keyFill.color)

            EmojiCanvas(
                settings: settings,
                onInsert: { typed.append($0) },
                onBackspace: { if !typed.isEmpty { typed.removeLast() } },
                onSetSkinTone: onSetSkinTone
            )
            .frame(height: EmojiCanvas.preferredHeight(for: settings))
            .background { backdropGradient }
        }
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}

/// A live preview of the clipboard panel — sample entries, stub tap/save handlers.
struct ClipboardPreview: View {
    @Environment(\.resolvedKeyboardTheme) private var envTheme
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    let settings: KeyboardSettings

    private static let sampleEntries: [ClipboardEntry] = [
        ClipboardEntry(text: "Meeting at 3pm in the main conference room", date: Date(), pinned: true),
        ClipboardEntry(text: "hey! can you send me that file?", date: Date()),
        ClipboardEntry(text: "https://clink.app", date: Date()),
    ]

    private var backdropGradient: LinearGradient {
        let ui = UIColor(envTheme.accent.color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let vs = max(0.5, min(1.0, s))
        let vb = max(0.55, min(0.95, b))
        let c1 = Color(UIColor(hue: h,                   saturation: vs,       brightness: vb,              alpha: 1))
        let c2 = Color(UIColor(hue: fmod(h + 0.33, 1.0), saturation: vs * 0.9, brightness: min(1, vb * 1.1), alpha: 1))
        let c3 = Color(UIColor(hue: fmod(h + 0.67, 1.0), saturation: vs * 0.8, brightness: vb * 0.85,       alpha: 1))
        return LinearGradient(colors: [c1, c2, c3], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ClipboardPanel(
            entries: Self.sampleEntries,
            theme: envTheme,
            cornerRadius: cardCornerRadius,
            gridLayout: settings.clipboardStyle == .grid,
            onTap: { _ in },
            onSave: {},
            onDismiss: {},
            onCopy: { _ in },
            onTogglePin: { _ in },
            onDelete: { _ in },
            onClear: {}
        )
        .frame(height: KeyboardCanvas.preferredHeight(for: settings))
        .background { backdropGradient }
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}

/// A live preview of the notepad browse panel — sample notes, stub tap/load handlers.
struct NotepadPreview: View {
    @Environment(\.resolvedKeyboardTheme) private var envTheme
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    let settings: KeyboardSettings

    private static let sampleNotes: [NotepadNote] = [
        NotepadNote(text: "Don't forget to pick up groceries", date: Date()),
        NotepadNote(text: "Meeting notes:\n- Discussed roadmap\n- Q3 targets", date: Date()),
        NotepadNote(text: "Wi-Fi: sunshine2024", date: Date()),
    ]

    private var backdropGradient: LinearGradient {
        let ui = UIColor(envTheme.accent.color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let vs = max(0.5, min(1.0, s))
        let vb = max(0.55, min(0.95, b))
        let c1 = Color(UIColor(hue: h,                   saturation: vs,       brightness: vb,              alpha: 1))
        let c2 = Color(UIColor(hue: fmod(h + 0.33, 1.0), saturation: vs * 0.9, brightness: min(1, vb * 1.1), alpha: 1))
        let c3 = Color(UIColor(hue: fmod(h + 0.67, 1.0), saturation: vs * 0.8, brightness: vb * 0.85,       alpha: 1))
        return LinearGradient(colors: [c1, c2, c3], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        NotepadBrowsePanel(
            notes: Self.sampleNotes,
            theme: envTheme,
            cornerRadius: cardCornerRadius,
            onTap: { _ in },
            onLoad: { _ in },
            onDelete: { _ in },
            onClear: {},
            onDismiss: {}
        )
        .frame(height: KeyboardCanvas.preferredHeight(for: settings))
        .background { backdropGradient }
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}

/// A live, interactive preview of the calculator panel — the exact `CalculatorPanel`
/// the extension renders, wired to a local buffer so the user can try arithmetic
/// right inside the settings page. Mirrors `KeyboardPreview` and `EmojiPreview`.
struct CalculatorPreview: View {
    @Environment(\.resolvedKeyboardTheme) private var envTheme
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    let settings: KeyboardSettings
    @State private var typed: String = ""

    private var backdropGradient: LinearGradient {
        let ui = UIColor(envTheme.accent.color)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let vs = max(0.5, min(1.0, s))
        let vb = max(0.55, min(0.95, b))
        let c1 = Color(UIColor(hue: h,                   saturation: vs,       brightness: vb,              alpha: 1))
        let c2 = Color(UIColor(hue: fmod(h + 0.33, 1.0), saturation: vs * 0.9, brightness: min(1, vb * 1.1), alpha: 1))
        let c3 = Color(UIColor(hue: fmod(h + 0.67, 1.0), saturation: vs * 0.8, brightness: vb * 0.85,       alpha: 1))
        return LinearGradient(colors: [c1, c2, c3], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(typed.isEmpty ? "Try it out…" : typed)
                    .foregroundStyle(typed.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 0)
                if !typed.isEmpty {
                    Button { typed = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(envTheme.keyFill.color)

            CalculatorPanel(
                theme: envTheme,
                cornerRadius: cardCornerRadius,
                onInsert: { typed = $0 },
                onCopy: { _ in },
                onSaveToClipboard: { _ in },
                onDismiss: {}
            )
            .frame(height: KeyboardCanvas.preferredHeight(for: settings))
            .background { backdropGradient }
        }
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}

// MARK: - ThemedToolbarBackground

/// Apply to the Image/label inside a toolbar Button (pair with `.buttonStyle(.plain)`)
/// so iOS 26's automatic glass chrome is fully replaced by theme-aware styling.
struct ThemedToolbarBackground: ViewModifier {
    @Environment(\.useGlassCards) private var useGlassCards
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @Environment(\.specialKeyTint) private var specialKeyTint

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
        if useGlassCards, #available(iOS 26.0, *) {
            // .plain strips system chrome — replace it with our own glass.
            content
                .frame(width: 36, height: 36)
                .background { Color.clear.glassEffect(.regular, in: shape) }
        } else {
            // 44pt solid fill — large enough to paint over the system chrome.
            shape
                .fill(specialKeyTint ?? Color(.systemGray5))
                .frame(width: 44, height: 44)
                .overlay { content }
        }
    }
}

extension View {
    func themedToolbarBackground() -> some View {
        modifier(ThemedToolbarBackground())
    }
}

// MARK: - NavBarState + ThemeNavButton

/// Shared state that destination views write their trailing nav-bar button to.
/// `RootView` reads it and renders the button as a custom overlay — bypassing
/// UIKit's circular glass chrome that iOS 26 applies to all UIBarButtonItems.
@Observable @MainActor
final class NavBarState {
    var trailingIcon: String? = nil
    var trailingAction: (() -> Void)? = nil
}

/// A nav-bar button that renders with the theme's corner radius and either a
/// Liquid Glass or solid fill — never a UIBarButtonItem, so no iOS 26 chrome.
struct ThemeNavButton: View {
    @Environment(\.useGlassCards) private var useGlassCards
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @Environment(\.specialKeyTint) private var specialKeyTint
    @Environment(\.resolvedKeyboardTheme) private var theme
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.primary)
        }
        .buttonStyle(ThemeNavButtonStyle(
            useGlass: useGlassCards,
            cornerRadius: cardCornerRadius,
            fill: specialKeyTint ?? Color(.systemGray5),
            accent: theme.accent.color))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
}

struct ThemeNavButtonStyle: ButtonStyle {
    let useGlass: Bool
    let cornerRadius: CGFloat
    let fill: Color
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if useGlass {
                if #available(iOS 26.0, *) {
                    configuration.label
                        .frame(width: 36, height: 36)
                        .background { Color.clear.glassEffect(.regular.interactive(), in: shape) }
                        .overlay(shape.strokeBorder(accent.opacity(0.5), lineWidth: 1))
                } else {
                    configuration.label
                        .frame(width: 36, height: 36)
                        .background(fill.opacity(0.15), in: shape)
                        .overlay(shape.strokeBorder(accent.opacity(0.5), lineWidth: 1))
                }
            } else {
                configuration.label
                    .frame(width: 36, height: 36)
                    .background(fill, in: shape)
                    .overlay(shape.strokeBorder(accent.opacity(0.5), lineWidth: 1))
            }
        }
        .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Text-label variant of `ThemeNavButtonStyle` — auto-sizes to the label width
/// instead of using the fixed 36×36 icon frame.
struct ThemeNavTextButtonStyle: ButtonStyle {
    let useGlass: Bool
    let cornerRadius: CGFloat
    let fill: Color
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if useGlass {
                if #available(iOS 26.0, *) {
                    configuration.label
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background { Color.clear.glassEffect(.regular.interactive(), in: shape) }
                        .overlay(shape.strokeBorder(accent.opacity(0.4), lineWidth: 1))
                } else {
                    configuration.label
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(fill.opacity(0.15), in: shape)
                        .overlay(shape.strokeBorder(accent.opacity(0.5), lineWidth: 1))
                }
            } else {
                configuration.label
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(fill, in: shape)
            }
        }
        .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Xcode preview support

#if DEBUG
extension View {
    /// Inject the standard app environment (`AppModel` + `SidebarState` +
    /// `NavBarState`) and a `NavigationStack` so any panel renders in the Xcode
    /// canvas — most panels trap on a missing `AppModel` otherwise. Lives here (an
    /// existing in-target file) rather than a new file, since the project uses
    /// explicit pbxproj file refs and a brand-new file wouldn't be compiled.
    ///
    /// Usage at the bottom of a panel file:
    ///
    ///     #if DEBUG
    ///     #Preview { TypingView().clinkPreview() }
    ///     #endif
    ///
    /// Select the **Clink** app scheme (not ClinkKeyboard) before previewing.
    func clinkPreview() -> some View {
        NavigationStack { self }
            .environment(AppModel())
            .environment(SidebarState())
            .environment(NavBarState())
    }
}
#endif

/// Registers a trailing nav-bar button for the current view's lifetime.
/// Clears on disappear so the button vanishes when the view is not active.
private struct NavTrailingButtonModifier: ViewModifier {
    @Environment(NavBarState.self) private var navBar
    let icon: String
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                navBar.trailingIcon = icon
                navBar.trailingAction = action
            }
    }
}

extension View {
    func navTrailingButton(_ icon: String, action: @escaping () -> Void) -> some View {
        modifier(NavTrailingButtonModifier(icon: icon, action: action))
    }
}

// MARK: - ThemePopover

/// Custom themed dropdown. Glass themes: glassEffect container. Solid themes:
/// solid key-fill card with the theme's corner radius. Always renders as an
/// overlay anchored to the top-trailing corner of the modified view so the
/// system popover chrome (which is always glass on iOS 26) is never used.
private struct ThemePopoverModifier<PopoverContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(\.useGlassCards) private var useGlassCards
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @Environment(\.cardTint) private var cardTint
    @ViewBuilder var popoverContent: () -> PopoverContent

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack(alignment: .topTrailing) {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(Motion.previewPopup.animation) { isPresented = false }
                            }
                        menuCard
                            .padding(.top, 8)
                            .padding(.trailing, 16)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)))
                }
            }
            .animation(Motion.previewPopup.animation, value: isPresented)
    }

    @ViewBuilder private var menuCard: some View {
        let r = cardCornerRadius
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        if useGlassCards, #available(iOS 26.0, *) {
            popoverContent()
                .clipShape(shape)
                .background { Color.clear.glassEffect(.regular, in: shape) }
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        } else {
            let fill = cardTint ?? Color(.secondarySystemBackground)
            popoverContent()
                .clipShape(shape)
                .background {
                    shape.fill(fill)
                        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.25), radius: 14, y: 5)
                }
        }
    }
}

extension View {
    func themePopover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(ThemePopoverModifier(isPresented: isPresented, popoverContent: content))
    }
}
