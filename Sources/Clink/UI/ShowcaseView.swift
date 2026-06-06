/**
 Device showcase — a typing simulator for capturing demo footage.

 Built ONLY into the `make device-showcase` build (SHOWCASE compilation
 condition), never into the App Store product. Boots straight into this screen
 instead of RootView.

 Layout, top to bottom:
   - Control panel: configure script, speed, and backgrounds (CROP THIS OUT)
   - A bubble styled like the keys: text auto-types into it, centered
   - The real KeyboardCanvas: right keys depress, shift toggles for capitals,
     planes switch for numbers/symbols, all in lockstep with the text

 A screen recording cropped below the controls shows the bubble filling above a
 keyboard that visibly types — no human hands, no fat-fingering, same phrase
 every take.
 */
#if SHOWCASE
import SwiftUI
import iUXiOS

struct ShowcaseView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var typer = ShowcaseTyper()

    private var theme: Theme { model.settings.resolvedTheme(dark: colorScheme == .dark) }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // ---- Controls (crop everything above the bubble) ----
                ScrollView {
                    ControlPanel(typer: typer)
                        .padding(UX.screenPadding)
                }
                .frame(maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))

                // ---- The cropped showcase region: bubble + keyboard ----
                ZStack(alignment: .bottom) {
                    typer.background.swiftUIView.ignoresSafeArea()
                    VStack(spacing: 14) {
                        Spacer(minLength: 0)
                        TypingBubble(text: typer.displayed, running: typer.isRunning, theme: theme)
                            .padding(.horizontal, 18)
                        keyboardArea
                    }
                    .padding(.bottom, geo.safeAreaInsets.bottom > 0 ? 0 : 10)
                }
                .frame(height: showcaseRegionHeight)
            }
            .ignoresSafeArea(.keyboard)
        }
        .onAppear {
            typer.settings = model.settings
            // Optional: `--showcase-autostart` begins typing on launch, so a
            // capture pipeline can record without a tap.
            if ProcessInfo.processInfo.arguments.contains("--showcase-autostart") {
                typer.start()
            }
        }
        .onChange(of: model.settings) { _, new in typer.settings = new }
    }

    private var showcaseRegionHeight: CGFloat {
        KeyboardCanvas.preferredHeight(for: model.settings) + 230
    }

    /// The keyboard, optionally sitting on a configurable tray.
    private var keyboardArea: some View {
        keyboard
            .frame(height: KeyboardCanvas.preferredHeight(for: model.settings))
            .padding(.horizontal, typer.tray == .off ? 0 : 6)
            .padding(.top, typer.tray == .off ? 0 : 8)
            .background(alignment: .bottom) {
                typer.tray.swiftUIView.ignoresSafeArea(edges: .bottom)
            }
            .animation(.easeInOut(duration: 0.3), value: typer.controller.showEmoji)
    }

    /// The letter keyboard or the emoji keyboard, swapped with a slide+fade when
    /// the simulator needs an emoji — exactly like tapping the 🙂 key.
    @ViewBuilder private var keyboard: some View {
        if typer.controller.showEmoji {
            EmojiCanvas(
                settings: model.settings,
                controller: typer.controller,
                onInsert: { typer.manualInsert($0) },
                onBackspace: { typer.manualBackspace() },
                onSetSkinTone: { base, tone in model.settings.emojiSkinTones[base] = tone }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            KeyboardCanvas(
                settings: model.settings,
                live: typer.live,
                controller: typer.controller,
                onInsert: { typer.manualInsert($0) },
                onBackspace: { typer.manualBackspace() },
                onSuggestion: { typer.manualInsert($0 + " ") }
            )
            .transition(.opacity)
        }
    }
}

// MARK: - The bubble (centered, styled like the keys)

private struct TypingBubble: View {
    let text: String
    let running: Bool
    let theme: Theme
    @State private var caretOn = true

    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .frame(minHeight: 46)
            .frame(maxWidth: 460)
            .modifier(BubbleGlass(shape: shape, theme: theme))
            .frame(maxWidth: .infinity)   // centered in the row
            .onReceive(Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()) { _ in
                caretOn.toggle()
            }
    }

    /// Text + an inline caret. The caret is part of the same `Text` run so it
    /// hugs the end of the (possibly wrapped) text — and the whole thing is
    /// centered.
    private var content: some View {
        (Text(text) + caret)
            .font(.system(size: 21))
            .foregroundStyle(theme.keyText.color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .animation(.none, value: text)
    }

    private var caret: Text {
        // Always the same glyph (constant width, so centered text never jumps) —
        // it just blinks by toggling its colour to clear.
        let visible = running && caretOn
        return Text("▏").foregroundColor(visible ? theme.accent.color : .clear)
    }
}

/// The bubble surface. Deliberately OPAQUE and size/position-independent: a
/// translucent glass bubble re-samples the wallpaper gradient as it grows onto a
/// new line, so its darkness visibly jumps. We use the theme's solid key fill on
/// solid themes, and the same frosted neutral the key *popups* use on glass
/// themes — so it still reads like a key, but never shifts as it grows.
private struct BubbleGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let theme: Theme

    private var fill: Color {
        switch theme.material {
        case .solid: return theme.keyFill.color
        case .liquidGlass: return theme.isDark ? Color(.sRGB, white: 0.16) : Color(.sRGB, white: 0.98)
        }
    }

    func body(content: Content) -> some View {
        content
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(
                .white.opacity(theme.material == .liquidGlass ? 0.18 : 0), lineWidth: 0.5))
            .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.18), radius: 10, y: 4)
    }
}

// MARK: - Configurable backgrounds + keyboard tray

enum ShowcaseBackground: String, CaseIterable, Identifiable {
    case sunset, ocean, mint, graphite, paper, black, white
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    @ViewBuilder var swiftUIView: some View {
        switch self {
        case .sunset:
            gradient([(0.36, 0.40, 0.78), (0.85, 0.42, 0.55), (0.95, 0.70, 0.38)])
        case .ocean:
            gradient([(0.10, 0.30, 0.55), (0.15, 0.55, 0.70), (0.45, 0.80, 0.80)])
        case .mint:
            gradient([(0.55, 0.85, 0.70), (0.75, 0.90, 0.80), (0.95, 0.95, 0.80)])
        case .graphite:
            gradient([(0.12, 0.13, 0.16), (0.20, 0.21, 0.25), (0.10, 0.11, 0.14)])
        case .paper:
            gradient([(0.96, 0.95, 0.93), (0.90, 0.90, 0.92), (0.93, 0.92, 0.95)])
        case .black: Color.black
        case .white: Color.white
        }
    }

    private func gradient(_ stops: [(Double, Double, Double)]) -> some View {
        LinearGradient(
            colors: stops.map { Color(.sRGB, red: $0.0, green: $0.1, blue: $0.2) },
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum KeyboardTray: String, CaseIterable, Identifiable {
    case off, system, light, dark
    var id: String { rawValue }
    var label: String { self == .off ? "Off" : rawValue.capitalized }

    /// The tray surface drawn behind the keys (nothing when off).
    @ViewBuilder var swiftUIView: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
        switch self {
        case .off: Color.clear
        case .system: shape.fill(.regularMaterial)
        case .light: shape.fill(Color(.sRGB, white: 0.92))
        case .dark: shape.fill(Color(.sRGB, white: 0.12))
        }
    }
}

// MARK: - Controls (cropped out of the shot)

private struct ControlPanel: View {
    @Bindable var typer: ShowcaseTyper

    var body: some View {
        VStack(spacing: UX.cardSpacing) {
            CardSection("Script") {
                Text("One phrase per line. They type out in order, each held then deleted. Emoji and punctuation work as-is.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $typer.script)
                    .font(.system(size: 16))
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background.secondary,
                               in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            CardSection("Behaviour") {
                ToggleRow("Auto-capitalize",
                          subtitle: "Capitalize the start of each sentence",
                          isOn: $typer.autoCaps)
                Divider()
                ToggleRow("Delete between phrases",
                          subtitle: "Backspace the line away before the next one",
                          isOn: $typer.autoDelete)
                Divider()
                ToggleRow("Loop", subtitle: "Restart from the top after the last phrase",
                          isOn: $typer.loop)
                Divider()
                SliderRow("Speed", value: $typer.charsPerSecond, in: 2...20, step: 1) {
                    "\(Int($0)) cps"
                }
                Divider()
                SliderRow("Hold", value: $typer.holdSeconds, in: 0.3...5, step: 0.1) {
                    String(format: "%.1fs", $0)
                }
            }

            CardSection("Backdrop") {
                Picker("Background", selection: $typer.background) {
                    ForEach(ShowcaseBackground.allCases) { Text($0.label).tag($0) }
                }
                Divider()
                Picker("Keyboard tray", selection: $typer.tray) {
                    ForEach(KeyboardTray.allCases) { Text($0.label).tag($0) }
                }
            }

            HStack(spacing: 12) {
                Button {
                    typer.isRunning ? typer.stop() : typer.start()
                } label: {
                    Label(typer.isRunning ? "Stop" : "Start",
                          systemImage: typer.isRunning ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(typer.isRunning ? .red : .accentColor)

                Button { typer.restart() } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button { typer.clear() } label: {
                    Label("Clear", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
    }
}

// MARK: - The typing engine

/// Drives the bubble text AND the keyboard: types a script out grapheme by
/// grapheme with humanish timing, pressing the matching key, toggling shift for
/// capitals, switching planes for numbers/symbols — then holds, backspaces, and
/// loops. The bubble text and the keyboard presses come from this one engine, so
/// they're always in sync.
@MainActor
@Observable
final class ShowcaseTyper {
    // Config (bound by the control panel).
    var script: String = "hello from clink! 👋\nthe keyboard you can actually make your own.\nsounds, themes, layouts… all yours. 🎛️"
    var autoCaps = true
    var autoDelete = true
    var loop = true
    var charsPerSecond: Double = 8
    var holdSeconds: Double = 1.6
    var background: ShowcaseBackground = .sunset
    var tray: KeyboardTray = .off

    /// Layout/keymap source for resolving characters → keys. Kept in sync with
    /// the app's live settings by the view.
    var settings: KeyboardSettings = .default

    // Live output.
    private(set) var displayed = ""
    private(set) var isRunning = false

    /// Shared with the on-screen `KeyboardCanvas` so we can drive its plane,
    /// shift, and pressed-key visuals.
    let controller = KeyboardController()

    /// Live suggestion-bar state, fed real predictions as we type — the same
    /// engine the keyboard extension uses, so the bar behaves like the real one.
    let live = KeyboardLiveState()
    private let suggestEngine = SuggestionEngine()

    private var task: Task<Void, Never>?

    private var phrases: [String] {
        script.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func start() {
        guard !isRunning else { return }
        let lines = phrases
        guard !lines.isEmpty else { return }
        isRunning = true
        displayed = ""
        task = Task { [weak self] in await self?.run(lines) }
    }

    func stop() {
        task?.cancel(); task = nil
        controller.pressedKeyID = nil
        controller.pressedEmoji = nil
        controller.showEmoji = false
        isRunning = false
    }

    func restart() { stop(); start() }

    func clear() { stop(); displayed = "" }

    // Manual typing via the on-screen keyboard, when the simulator is idle.
    func manualInsert(_ s: String) {
        guard !isRunning else { return }
        displayed.append(s); refreshSuggestions()
    }
    func manualBackspace() {
        guard !isRunning, !displayed.isEmpty else { return }
        displayed.removeLast(); refreshSuggestions()
    }

    // MARK: - Loop

    private func run(_ lines: [String]) async {
        repeat {
            for line in lines {
                await typeOut(autoCapped(line))
                if Task.isCancelled { break }
                await sleep(holdSeconds)
                if Task.isCancelled { break }
                if autoDelete { await deleteAll() } else { displayed = ""; await sleep(0.4) }
                if Task.isCancelled { break }
                await sleep(0.35)
            }
        } while loop && !Task.isCancelled
        if !Task.isCancelled { stop() }
    }

    /// Type a phrase, pressing the right key for each grapheme cluster.
    private func typeOut(_ text: String) async {
        displayed = ""
        refreshSuggestions()          // sentence-starter predictions on the empty bar
        controller.shift = .on        // sentence starts capitalized (pre-engaged, no flash)
        // Don't reset the plane silently — let the first character's plane switch
        // animate the ABC keypress if we're coming back from numbers/symbols.
        for ch in text {
            if Task.isCancelled { return }
            await type(ch)
        }
    }

    /// Type one grapheme cluster: emoji route through the emoji keyboard, every
    /// other character through the letter/number/symbol planes.
    private func type(_ ch: Character) async {
        if let cat = controller.emojiCategoryIndex(for: ch) {
            await enterEmoji()
            if controller.emojiCategory != cat {
                controller.emojiCategory = cat
                await sleep(0.18)        // beat for the category tab to change
            }
            controller.pressedEmoji = String(ch)
            displayed.append(ch)
            refreshSuggestions()
            await sleep(max(dwell, 0.1) * 1.4)
            controller.pressedEmoji = nil
            await sleep(interval(after: ch))
            return
        }
        // Non-emoji: make sure we're back on the letter keyboard, then press.
        await exitEmoji()
        let id = await keyID(for: ch)
        if Task.isCancelled { return }
        if let id { controller.pressedKeyID = id }
        displayed.append(ch)             // insert on key-down, like a real keyboard
        refreshSuggestions()
        await sleep(dwell)
        controller.pressedKeyID = nil
        await sleep(interval(after: ch))
    }

    /// Swap to the emoji keyboard (like tapping 🙂), if not already showing.
    private func enterEmoji() async {
        guard !controller.showEmoji else { return }
        controller.showEmoji = true
        await sleep(0.36)                // let the keyboard swap settle
    }

    /// Swap back to the letter keyboard, landing on the letters plane.
    private func exitEmoji() async {
        guard controller.showEmoji else { return }
        controller.showEmoji = false
        controller.plane = .letters
        await sleep(0.36)
    }

    /// Delete by HOLDING the backspace key down (sustained pressed state) while
    /// characters disappear — with an initial beat then acceleration, like iOS
    /// auto-repeat — rather than tapping it once per character.
    private func deleteAll() async {
        await exitEmoji()               // delete on the letter keyboard
        guard !displayed.isEmpty else { return }
        controller.pressedKeyID = controller.backspaceID(settings: settings)
        await sleep(0.3)                // hold a moment before the repeat kicks in
        var step = 0.11
        while !displayed.isEmpty {
            if Task.isCancelled { break }
            displayed.removeLast()
            refreshSuggestions()
            await sleep(step)
            step = max(0.035, step - 0.006)   // accelerate as it repeats
        }
        controller.pressedKeyID = nil   // release
    }

    // MARK: - Driving the keyboard

    /// Resolve the key for a character, performing any plane/shift transitions
    /// (each flashed on its own key) so the keyboard mirrors a real sequence.
    private func keyID(for ch: Character) async -> String? {
        if ch == "\n" { return controller.returnID }
        if ch == " " { return controller.spaceID }
        guard let hit = controller.locate(ch, settings: settings) else {
            return nil   // emoji / off-keyboard glyph: insert with no keypress
        }
        await switchPlane(to: hit.plane)
        if hit.plane == .letters {
            let want: KeyboardController.Shift = hit.needsShift ? .on : .off
            if controller.shift != want {
                await flash(controller.shiftID(settings: settings))
                controller.shift = want
                await sleep(0.03)
            }
        }
        return hit.id
    }

    private func switchPlane(to target: KeyboardController.Plane) async {
        guard controller.plane != target else { return }
        switch target {
        case .letters:
            await flash(controller.planeToggleID)           // ABC
            controller.plane = .letters
        case .numbers:
            await flash(controller.plane == .symbols
                        ? controller.symbolPageToggleID      // 123 (from symbols)
                        : controller.planeToggleID)          // 123 (from letters)
            controller.plane = .numbers
        case .symbols:
            if controller.plane == .letters {
                await flash(controller.planeToggleID)        // letters → numbers first
                controller.plane = .numbers
                await sleep(0.04)
            }
            await flash(controller.symbolPageToggleID)       // #+=
            controller.plane = .symbols
        }
        await sleep(0.04)
    }

    /// Briefly press a key (no character inserted) — used for shift / plane keys.
    private func flash(_ id: String) async {
        controller.pressedKeyID = id
        await sleep(dwell)
        controller.pressedKeyID = nil
        await sleep(0.03)
    }

    // MARK: - Timing & text

    /// How long a key stays depressed, scaled to typing speed but clamped so the
    /// press is always visible.
    private var dwell: Double { min(max(0.5 / max(charsPerSecond, 1), 0.05), 0.11) }

    /// Per-character gap: base from the speed slider, ±35% jitter, with an extra
    /// beat after whitespace / sentence punctuation for a human cadence.
    private func interval(after ch: Character) -> Double {
        let base = 1.0 / max(charsPerSecond, 1)
        var t = base * Double.random(in: 0.65...1.35)
        if ch == " " { t += base * 0.6 }
        if ".!?,".contains(ch) { t += base * 1.2 }
        return t
    }

    // MARK: - Live suggestions

    /// Recompute the suggestion bar from the text typed so far, exactly like the
    /// keyboard extension does. Auto-correction is left off so the showcase types
    /// the scripted text verbatim, but the predictions update live.
    private func refreshSuggestions() {
        guard settings.suggestionsEnabled else {
            if !live.suggestions.isEmpty { live.suggestions = [] }
            if live.autocorrection != nil { live.autocorrection = nil }
            if !live.emojiSuggestions.isEmpty { live.emojiSuggestions = [] }
            return
        }
        let before = displayed
        let partial = SmartPunctuation.trailingPartialWord(in: before)
        let result = suggestEngine.compute(
            partial: partial,
            previousWord: previousWord(before: before, partial: partial),
            sentenceStart: isSentenceStart(before: before, partial: partial),
            autocorrect: false,
            autoPunctuation: false,
            rejected: nil)
        live.suggestions = result.predictions
        live.autocorrection = result.correction
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

    private func autoCapped(_ s: String) -> String {
        guard autoCaps else { return s }
        var out = ""
        var capNext = true
        for ch in s {
            if capNext, ch.isLetter {
                out += ch.uppercased(); capNext = false
            } else {
                out.append(ch)
            }
            if ch == "." || ch == "!" || ch == "?" { capNext = true }
        }
        return out
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
#endif
