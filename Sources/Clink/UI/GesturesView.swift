/**
 Gestures settings — Swipe tab (glide typing and its trail) and Backspace tab
 (rapid-delete repeat timing).
 

 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

/// Swipe typing and backspace repeat tuning.
/// `$model.settings` bindings persist via `AppModel.settings` `didSet`.
struct GesturesView: View {
    private enum Tab { case swipe, backspace }

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: Tab = .swipe

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            bottomBar: AnyView(
                                ThemedTabPicker(
                                    options: [("Swipe", Tab.swipe),
                                              ("Backspace", Tab.backspace)],
                                    selection: $selectedTab)
                            )) {
            switch selectedTab {
            case .swipe:
                swipeTab(model: model)
            case .backspace:
                backspaceTab(model: model)
            }
        }
        .tint(themeAccent)
        .navigationTitle("Gestures")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Tabs

    @ViewBuilder
    private func swipeTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection {
            ToggleRow("Swipe typing",
                      subtitle: "Trace a word by gliding across the letters. Lift to insert it. Tapping still works normally.",
                      isOn: $model.settings.swipeTypingEnabled)
        }

        if model.settings.swipeTypingEnabled {
            CardSection("Trail") {
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
            }

            CardSection("Liquid glass") {
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
        }

        CardSection("How it works") {
            Text("Swipe decoding runs fully offline against the keyboard language's word list — no network, no Full Access. The first letter is typed the instant you touch down, then replaced by the recognised word once the glide is read.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, UX.rowVPadding)
        }
    }

    @ViewBuilder
    private func backspaceTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection {
            ToggleRow("Swipe to delete word",
                      subtitle: "Swipe left on the backspace key to delete a whole word. Keep dragging for more.",
                      isOn: $model.settings.swipeToDeleteWord)
            if model.settings.swipeToDeleteWord {
                Divider()
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
        }

        CardSection("Presets") {
            PresetChips(presets: TuningPresets.timing)
                .padding(.vertical, UX.rowVPadding)
        }

        CardSection("Values") {
            SliderRow("Hold delay",
                      tooltip: "How long you must hold backspace before rapid-delete kicks in.",
                      value: $model.settings.repeatHoldDelay,
                      in: 150...800, step: 25) {
                "\(Int($0))ms"
            }
            Divider()
            SliderRow("Start speed",
                      tooltip: "Time between each deletion when rapid-delete starts. Higher is slower.",
                      value: $model.settings.repeatInitialInterval,
                      in: 50...200, step: 10) {
                "\(Int($0))ms"
            }
            Divider()
            SliderRow("Max speed",
                      tooltip: "Fastest deletion rate after the key fully accelerates. Lower is faster.",
                      value: $model.settings.repeatMinInterval,
                      in: 20...80, step: 5) {
                "\(Int($0))ms"
            }
            Divider()
            SliderRow("Acceleration",
                      tooltip: "How quickly repeat accelerates to max speed. Higher gets there faster.",
                      value: $model.settings.repeatAccelStep,
                      in: 1...20, step: 1) {
                "\(Int($0))ms/step"
            }
        }
    }
}

#if DEBUG
#Preview { GesturesView().clinkPreview() }
#endif
