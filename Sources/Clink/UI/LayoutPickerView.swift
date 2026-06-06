/**
 Layout and key-shape editor. Four tabs — Layout, Size, Popups, Feel — all with a
 live keyboard preview pinned above the controls.
 */
import SwiftUI
import iUXiOS

/// Layout, key size, popups, and press-feel settings behind a tabbed preview layout.
struct LayoutPickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabbedPreviewLayout(settings: model.settings, tabs: [
            PreviewTab("Layout") {
                CardSection("Layout") {
                    HStack {
                        Text("Layout")
                        Spacer()
                        Picker("Layout", selection: $model.settings.layoutID) {
                            ForEach(KeyboardLayout.presets, id: \.id) { layout in
                                Text(layout.name).tag(layout.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, UX.rowVPadding)
                }

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
            },

            PreviewTab("Size") {
                TunedSection(title: "Size & Shape", presets: TuningPresets.size) {
                    SliderRow("Key height", value: $model.settings.keyHeight,
                              in: 38...58, step: 1) { "\(Int($0))pt" }
                    Divider()
                    SliderRow("Roundness", value: $model.settings.keyCornerRadius,
                              in: 0...22, step: 1) { "\(Int($0))pt" }
                    Divider()
                    SliderRow("Key width", value: $model.settings.keyWidthFraction,
                              in: 0.6...1, step: 0.02) { "\(Int(($0 * 100).rounded()))%" }
                    Divider()
                    SliderRow("Space bar width", value: $model.settings.spaceWidth,
                              in: 3...7, step: 0.5) { String(format: "%.1f keys", $0) }
                    Divider()
                    SliderRow("Shift & delete width", value: $model.settings.funcKeyWidth,
                              in: 1...2, step: 0.1) { String(format: "%.1f keys", $0) }
                    Divider()
                    SliderRow("Key spacing", value: $model.settings.keySpacing,
                              in: 1...12, step: 1) { "\(Int($0))pt" }
                    Divider()
                    SliderRow("Row spacing", value: $model.settings.rowSpacing,
                              in: 0...16, step: 1) { "\(Int($0))pt" }
                }
            },

            PreviewTab("Popups") {
                CardSection("Key popups") {
                    ToggleRow("Key popups",
                              subtitle: "Show an enlarged bubble when a key is pressed.",
                              isOn: $model.settings.keyPopupEnabled)
                    Divider()
                    HStack {
                        Text("Popup style")
                        Spacer()
                        Picker("Popup style", selection: $model.settings.keyPopupStyle) {
                            ForEach(KeyPopupStyle.allCases) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, UX.rowVPadding)
                    .disabled(!model.settings.keyPopupEnabled)
                    .opacity(model.settings.keyPopupEnabled ? 1 : 0.4)
                    Divider()
                    ToggleRow("Liquid Glass popups",
                              subtitle: "Render key popups as glass on Liquid Glass themes.",
                              isOn: $model.settings.liquidGlassPopup)
                    .disabled(!model.settings.keyPopupEnabled)
                    .opacity(model.settings.keyPopupEnabled ? 1 : 0.4)
                }
            },

            PreviewTab("Feel") {
                CardSection("Key press") {
                    ToggleRow("Liquid key press",
                              subtitle: "Bloom and warp each key when pressed — best on Liquid Glass.",
                              isOn: $model.settings.keyPressWarp)
                    Divider()
                    SliderRow("Press linger", value: $model.settings.keyPressLinger,
                              in: 0...0.4, step: 0.02) {
                        $0 < 0.005 ? "Off" : "\(Int(($0 * 1000).rounded()))ms"
                    }
                }
            },
        ])
        .navigationTitle("Layout & Keys")
        .navigationBarTitleDisplayMode(.inline)
    }
}
