/**
 Keys settings. One scrolling page, no tabs:

   • Size & shape — a size preset + every geometry and padding slider in one
                    collapsed "Fine-tune" disclosure (grouped Keys / Padding).
   • Long press   — the per-key long-press preview toggle.

 Backspace repeat timing lives under Gestures → Backspace.
 `$model.settings` bindings persist via `AppModel.settings` `didSet`.


 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

/// Key geometry, padding, and long-press hint toggle, as a single calm scroll.
struct KeysView: View {
    @Environment(AppModel.self) private var model
    @State private var fineTuneExpanded = false

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings) {
            CardSection("Size & shape") {
                PresetChips(presets: TuningPresets.size)
                    .padding(.vertical, UX.rowVPadding)
                Divider()
                DisclosureGroup("Fine-tune", isExpanded: $fineTuneExpanded) {
                    VStack(spacing: 0) {
                        geometryFineTune(model: model)
                        paddingFineTune(model: model)
                    }
                    .padding(.top, 6)
                }
                .tint(.primary)
                .padding(.vertical, UX.rowVPadding)
            }

            CardSection("Long press") {
                ToggleRow("Long press previews",
                          subtitle: "Show a small glyph on each key previewing its first long-press alternate.",
                          isOn: $model.settings.longPressHintsEnabled)
            }
        }
        .navigationTitle("Keys")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func geometryFineTune(model: AppModel) -> some View {
        @Bindable var model = model
        Group {
            fineTuneHeader("Keys")
            SliderRow("Key height",
                      tooltip: "Taller keys are easier to tap accurately. Shorter keys give more screen room.",
                      value: $model.settings.keyHeight,
                      in: 38...58, step: 1) { "\(Int($0))pt" }
            Divider()
            SliderRow("Roundness",
                      tooltip: "Corner radius of each key. 0 is square, higher values make rounder caps.",
                      value: $model.settings.keyCornerRadius,
                      in: 0...22, step: 1) { "\(Int($0))pt" }
            Divider()
            SliderRow("Key width",
                      tooltip: "Width of each letter key within its grid cell. Lower values add more space between keys.",
                      value: $model.settings.keyWidthFraction,
                      in: 0.6...1, step: 0.02) { "\(Int(($0 * 100).rounded()))%" }
            Divider()
            SliderRow("Space bar width",
                      tooltip: "Width of the space bar in key units. Narrower leaves room for keys on either side.",
                      value: $model.settings.spaceWidth,
                      in: 3...7, step: 0.5) { String(format: "%.1f keys", $0) }
        }
        Group {
            Divider()
            SliderRow("Shift & delete width",
                      tooltip: "Width of the shift and backspace keys relative to a standard letter key.",
                      value: $model.settings.funcKeyWidth,
                      in: 1...2, step: 0.1) { String(format: "%.1f keys", $0) }
            Divider()
            SliderRow("Key spacing",
                      tooltip: "Horizontal gap between adjacent keys in the same row.",
                      value: $model.settings.keySpacing,
                      in: 1...12, step: 1) { "\(Int($0))pt" }
            Divider()
            SliderRow("Row spacing",
                      tooltip: "Vertical gap between rows of keys.",
                      value: $model.settings.rowSpacing,
                      in: 0...16, step: 1) { "\(Int($0))pt" }
        }
    }

    @ViewBuilder
    private func paddingFineTune(model: AppModel) -> some View {
        @Bindable var model = model
        fineTuneHeader("Padding")
        SliderRow("Suggestion bar padding",
                  tooltip: "Extra space above the suggestion bar.",
                  value: $model.settings.suggestionTopPadding,
                  in: 0...20, step: 1) {
            $0 == 0 ? "None" : "\(Int($0)) pt"
        }
        .gated(model.settings.suggestionsEnabled,
               reason: "Turn on the Suggestion bar to adjust this.")
        Divider()
        SliderRow("Top padding",
                  tooltip: "Space between the suggestion bar and the top row of keys.",
                  value: $model.settings.keyboardTopPadding,
                  in: 0...48, step: 1) { "\(Int($0))pt" }
        Divider()
        SliderRow("Bottom padding",
                  tooltip: "Lifts the entire keyboard up from the bottom edge of the keyboard extension.",
                  value: $model.settings.keyboardBottomPadding,
                  in: 0...64, step: 1) { "\(Int($0))pt" }
    }

    /// A small group label between blocks inside the Fine-tune disclosure.
    @ViewBuilder
    private func fineTuneHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .padding(.bottom, 2)
    }
}

#if DEBUG
#Preview { KeysView().clinkPreview() }
#endif
