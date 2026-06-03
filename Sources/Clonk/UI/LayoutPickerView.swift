import SwiftUI
import iUXiOS

struct LayoutPickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                KeyboardPreview(settings: model.settings)

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

                CardSection("Size & Shape") {
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
                    SliderRow("Key spacing", value: $model.settings.keySpacing,
                              in: 1...12, step: 1) { "\(Int($0))pt" }
                    Divider()
                    SliderRow("Row spacing", value: $model.settings.rowSpacing,
                              in: 0...16, step: 1) { "\(Int($0))pt" }
                }

                CardSection("Keys") {
                    ToggleRow("Number row",
                              subtitle: "Always show 1–0 above the letters.",
                              isOn: $model.settings.showNumberRow)
                    Divider()
                    ToggleRow("Auto-capitalize",
                              subtitle: "Capitalize the first letter of a sentence.",
                              isOn: $model.settings.autoCapitalize)
                    Divider()
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
                    Divider()
                    ToggleRow("Inset home row",
                              subtitle: "Indent the middle letter row, like the system keyboard.",
                              isOn: $model.settings.homeRowInset)
                    if model.settings.homeRowInset {
                        Divider()
                        SliderRow("Inset amount", value: $model.settings.homeRowInsetAmount,
                                  in: 0...0.12, step: 0.005) { "\(Int(($0 * 100).rounded()))%" }
                    }
                    Divider()
                    ToggleRow("Liquid key press",
                              subtitle: "Bloom and warp each key when pressed — best on Liquid Glass.",
                              isOn: $model.settings.keyPressWarp)
                    Divider()
                    SliderRow("Press linger", value: $model.settings.keyPressLinger,
                              in: 0...0.4, step: 0.02) {
                        $0 < 0.005 ? "Off" : "\(Int(($0 * 1000).rounded()))ms"
                    }
                    Divider()
                    ToggleRow("Suggestions",
                              subtitle: "Offline autocomplete bar above the keys.",
                              isOn: $model.settings.suggestionsEnabled)
                    Divider()
                    ToggleRow("Auto-correction",
                              subtitle: "Fix the word when you type a space or punctuation.",
                              isOn: $model.settings.autocorrectEnabled)
                    Divider()
                    ToggleRow("Auto punctuation",
                              subtitle: "Add apostrophes to contractions like “dont” → “don’t”.",
                              isOn: $model.settings.autoPunctuationEnabled)
                    Divider()
                    ToggleRow("Return to letters",
                              subtitle: "After typing punctuation on the symbols page, flip back to letters.",
                              isOn: $model.settings.autoReturnToLetters)
                }
            }
            .padding(UX.screenPadding)
        }
        .navigationTitle("Layout & Keys")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }
}
