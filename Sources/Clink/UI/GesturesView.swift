/**
 Gestures settings — swipe/glide typing and its trail.
 */
import SwiftUI
import iUXiOS

struct GesturesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings) {
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
        .tint(themeAccent)
        .navigationTitle("Gestures")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview { GesturesView().clinkPreview() }
#endif
