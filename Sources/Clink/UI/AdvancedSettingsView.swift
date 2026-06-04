import SwiftUI
import iUXiOS

struct AdvancedSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings, showHitboxOverlay: true) {
            CardSection("Touch") {
                SliderRow("Hitbox size", value: $model.settings.hitboxScale,
                          in: 0.75...1.25, step: 0.05) {
                    $0 == 1.0 ? "Default" : "\(Int(($0 * 100).rounded()))%"
                }
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }
}
