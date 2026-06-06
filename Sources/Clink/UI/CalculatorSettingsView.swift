/**
 Calculator settings — on/off toggle for the calculator action panel.
 */
import SwiftUI
import iUXiOS

/// Settings screen for the calculator panel.
struct CalculatorSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                CardSection("Settings") {
                    ToggleRow("Calculator",
                              subtitle: "Evaluate arithmetic and insert the result wherever you type. Adds a calculator to the panel button.",
                              isOn: $model.settings.calculatorEnabled)
                }
            }
            .padding(UX.screenPadding)
        }
        .navigationTitle("Calculator")
    }
}
