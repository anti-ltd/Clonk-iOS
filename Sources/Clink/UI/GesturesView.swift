/**
 Gestures settings. One scrolling page, no tabs:

   • Swipe typing — the on/off toggle (primary), with the trail + glass-ripple
                    options tucked inside one collapsed "Fine-tune" disclosure.
   • Backspace    — the swipe-to-delete-word toggle, plus the rapid-delete repeat
                    feel as presets with the raw timing sliders collapsed.

 `$model.settings` bindings persist via `AppModel.settings` `didSet`.


 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

/// Swipe typing and backspace repeat tuning, as a single calm scroll.
struct GesturesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var swipeFineTuneExpanded = false
    @State private var repeatFineTuneExpanded = false

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings) {
            swipeCard(model: model)
            backspaceCard(model: model)
            Text("Swipe decoding runs fully offline against the keyboard language's word list — no network, no Full Access. The first letter is typed the instant you touch down, then replaced by the recognised word once the glide is read.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        }
        .tint(themeAccent)
        .navigationTitle("Gestures")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Swipe typing

    @ViewBuilder
    private func swipeCard(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Swipe typing") {
            ToggleRow("Swipe typing",
                      subtitle: "Trace a word by gliding across the letters. Lift to insert it. Tapping still works normally.",
                      isOn: $model.settings.swipeTypingEnabled)
            Divider()
            DisclosureGroup("Fine-tune", isExpanded: $swipeFineTuneExpanded) {
                VStack(spacing: 0) { swipeFineTune(model: model) }
                    .padding(.top, 6)
            }
            .tint(.primary)
            .padding(.vertical, UX.rowVPadding)
            .gated(model.settings.swipeTypingEnabled,
                   reason: "Turn on Swipe typing to adjust the trail and ripple.")
        }
    }

    @ViewBuilder
    private func swipeFineTune(model: AppModel) -> some View {
        @Bindable var model = model
        ToggleRow("Show trail",
                  subtitle: "Draw the finger path while you swipe.",
                  isOn: $model.settings.swipeShowTrail)
        if model.settings.swipeShowTrail {
            Divider()
            SliderRow("Thickness",
                      tooltip: "Width of the trail line drawn under your finger while swiping.",
                      value: $model.settings.swipeTrailWidth,
                      in: 2...8, step: 0.5) {
                String(format: "%.1f pt", $0)
            }
        }
        Divider()
        ToggleRow("Key ripple",
                  subtitle: "Keys swell under your finger as you glide on glass themes. No effect on solid themes.",
                  isOn: $model.settings.swipeKeyMorph)
        if model.settings.swipeKeyMorph {
            Divider()
            SliderRow("Swell",
                      tooltip: "How much each key bulges outward as your finger passes over it.",
                      value: $model.settings.swipeMorphStrength,
                      in: 0.05...0.40, step: 0.01) {
                "\(Int(($0 * 100).rounded()))%"
            }
            Divider()
            SliderRow("Wave width",
                      tooltip: "How wide the ripple spreads. Larger values swell more neighbouring keys.",
                      value: $model.settings.swipeMorphRadius,
                      in: 1.0...2.5, step: 0.1) {
                String(format: "%.1f×", $0)
            }
        }
    }

    // MARK: - Backspace

    @ViewBuilder
    private func backspaceCard(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Backspace") {
            ToggleRow("Swipe to delete word",
                      subtitle: "Swipe left on the backspace key to delete a whole word. Keep dragging for more.",
                      isOn: $model.settings.swipeToDeleteWord)
            Divider()
            VStack(spacing: 0) {
                SliderRow("Swipe distance",
                          tooltip: "How far you must drag left before the first word is deleted. Lower is more sensitive.",
                          value: $model.settings.deleteWordSwipeEngage,
                          in: 12...60, step: 2) { "\(Int($0))pt" }
                Divider()
                SliderRow("Words per drag",
                          tooltip: "Distance you drag to delete each additional word. Lower deletes words faster.",
                          value: $model.settings.deleteWordSwipeStride,
                          in: 24...80, step: 2) { "\(Int($0))pt" }
            }
            .gated(model.settings.swipeToDeleteWord,
                   reason: "Turn on Swipe to delete word to adjust these.")
            Divider()
            // Rapid-delete (hold-to-repeat) feel: presets up front, raw timing
            // collapsed.
            Text("Rapid delete")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            PresetChips(presets: TuningPresets.timing)
                .padding(.vertical, UX.rowVPadding)
            Divider()
            DisclosureGroup("Fine-tune", isExpanded: $repeatFineTuneExpanded) {
                VStack(spacing: 0) { repeatFineTune(model: model) }
                    .padding(.top, 6)
            }
            .tint(.primary)
            .padding(.vertical, UX.rowVPadding)
        }
        .animation(Motion.settingsReveal.animation, value: model.settings.swipeToDeleteWord)
    }

    @ViewBuilder
    private func repeatFineTune(model: AppModel) -> some View {
        @Bindable var model = model
        SliderRow("Hold delay",
                  tooltip: "How long you must hold backspace before rapid-delete kicks in.",
                  value: $model.settings.repeatHoldDelay,
                  in: 150...800, step: 25) { "\(Int($0))ms" }
        Divider()
        SliderRow("Start speed",
                  tooltip: "Time between each deletion when rapid-delete starts. Higher is slower.",
                  value: $model.settings.repeatInitialInterval,
                  in: 50...200, step: 10) { "\(Int($0))ms" }
        Divider()
        SliderRow("Max speed",
                  tooltip: "Fastest deletion rate after the key fully accelerates. Lower is faster.",
                  value: $model.settings.repeatMinInterval,
                  in: 20...80, step: 5) { "\(Int($0))ms" }
        Divider()
        SliderRow("Acceleration",
                  tooltip: "How quickly repeat accelerates to max speed. Higher gets there faster.",
                  value: $model.settings.repeatAccelStep,
                  in: 1...20, step: 1) { "\(Int($0))ms/step" }
    }
}

#if DEBUG
#Preview { GesturesView().clinkPreview() }
#endif
