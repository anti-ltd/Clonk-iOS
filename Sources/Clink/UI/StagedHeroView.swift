// Staged "hero" marketing shot — the dark Liquid Glass keyboard caught mid-type
// on a subtle dark gradient, for the App Store / README hero. The WOW shot.
//
// DEBUG-only, reached via `--appstage glass` (see AppStage / StagedRoot). It's a
// deterministic STILL, not the live typing simulator: a phrase part-typed into a
// glass bubble, the next key held down so its popup balloons, and a live
// suggestion bar — composed so every capture is byte-for-byte identical. Reuses
// the real `KeyboardCanvas` (the exact view the extension renders), so what you
// see is what ships. Never compiled into Release.
#if DEBUG
import SwiftUI

struct StagedHeroView: View {
    @Environment(AppModel.self) private var model
    // On iPad (regular width) the bubble must grow with the canvas, otherwise the
    // 460pt phone cap leaves it marooned in dead space. Compact == iPhone, unchanged.
    @Environment(\.horizontalSizeClass) private var hSize
    private var isPad: Bool { hSize == .regular }

    /// The frozen "mid-type" moment: caps lock is engaged (the shift key glows)
    /// and the keyboard holds the key that types `nextChar` — so the shot glows
    /// from both sides: the caps-lock key on the left and the pressed key on the
    /// right, spelling out the brand.
    private let typed = "This is CLIN"
    private let nextChar: Character = "K"

    @State private var controller = KeyboardController()
    @State private var live = KeyboardLiveState(suggestions: ["CLINK", "clinic", "cling"])

    private var theme: Theme { model.settings.theme }

    var body: some View {
        ZStack(alignment: .bottom) {
            HeroBackground().ignoresSafeArea()

            VStack(spacing: isPad ? 28 : 18) {
                Spacer(minLength: 0)
                HeroBubble(text: typed, theme: theme, isPad: isPad)
                    .padding(.horizontal, 22)
                KeyboardCanvas(
                    settings: model.settings,
                    live: live,
                    controller: controller,
                    onInsert: { _ in },
                    onBackspace: {},
                    onSuggestion: { _ in })
                    .frame(height: KeyboardCanvas.preferredHeight(for: model.settings))
            }
            .padding(.bottom, 8)
        }
        .ignoresSafeArea(.keyboard)
        .onAppear(perform: freezeMidType)
    }

    /// Engage caps lock (the shift key glows) and press the key that types the
    /// next character, so both the caps-lock key and the held key read as active.
    private func freezeMidType() {
        controller.shift = .locked
        guard let hit = controller.locate(nextChar, settings: model.settings) else { return }
        controller.plane = hit.plane
        controller.pressedKeyID = hit.id
    }
}

// MARK: - Subtle dark gradient backdrop

private struct HeroBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.sRGB, red: 0.055, green: 0.055, blue: 0.085),
                    Color(.sRGB, red: 0.025, green: 0.025, blue: 0.045),
                ],
                startPoint: .top, endPoint: .bottom)
            // A faint indigo bloom behind the bubble — the brand accent, barely
            // there, so the dark reads rich rather than flat.
            RadialGradient(
                colors: [Color(.sRGB, red: 0.22, green: 0.24, blue: 0.55).opacity(0.32), .clear],
                center: UnitPoint(x: 0.5, y: 0.30), startRadius: 0, endRadius: 480)
        }
    }
}

// MARK: - The typed-into bubble (glass, centered)

private struct HeroBubble: View {
    let text: String
    let theme: Theme
    var isPad: Bool = false
    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        (Text(text) + Text("▏").foregroundColor(theme.accent.color))
            .font(.system(size: isPad ? 34 : 22))
            .foregroundStyle(theme.keyText.color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, isPad ? 30 : 20)
            .padding(.vertical, isPad ? 22 : 14)
            .frame(minHeight: isPad ? 72 : 48)
            .frame(maxWidth: isPad ? 880 : 460)
            // Frosted neutral matching the glass key popups — opaque so it never
            // re-samples the gradient as a translucent panel would.
            .background(Color(.sRGB, white: 0.16), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 5)
            .frame(maxWidth: .infinity)   // centered in the row
    }
}
#endif
