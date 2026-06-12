/**
 Layout editor — row toggles with a live keyboard preview pinned above.
 

 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

/// Row layout settings: number row and home-row inset.
struct LayoutPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings) {
            CardSection("Rows") {
                ToggleRow("Number row",
                          subtitle: "Always show 1–0 above the letters.",
                          isOn: $model.settings.showNumberRow)
                if model.settings.showNumberRow {
                    Divider()
                    SliderRow("Number row height", value: $model.settings.numberRowHeightScale,
                              in: 0.5...1.2, step: 0.05) {
                        "\(Int((model.settings.keyHeight * $0).rounded()))pt"
                    }
                    Divider()
                    SliderRow("Number row text size", value: $model.settings.numberRowFontSize,
                              in: 14...30, step: 1) { "\(Int($0))pt" }
                }
                Divider()
                ToggleRow("Inset home row",
                          subtitle: "Indent the middle letter row, like the system keyboard.",
                          isOn: $model.settings.homeRowInset)
                if model.settings.homeRowInset {
                    Divider()
                    SliderRow("Inset amount", value: $model.settings.homeRowInsetAmount,
                              in: 0...0.12, step: 0.005) { "\(Int(($0 * 100).rounded()))%" }
                }
            }
        }
        .tint(themeAccent)
        .navigationTitle("Layout & Keys")
        .navigationBarTitleDisplayMode(.inline)
    }
}
