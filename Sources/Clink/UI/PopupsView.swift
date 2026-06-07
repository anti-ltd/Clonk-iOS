/**
 Popups settings — key popup toggle, style, and Liquid Glass option.
 */
import SwiftUI
import iUXiOS

struct PopupsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings) {
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
        }
        .navigationTitle("Popups")
        .navigationBarTitleDisplayMode(.inline)
    }
}
