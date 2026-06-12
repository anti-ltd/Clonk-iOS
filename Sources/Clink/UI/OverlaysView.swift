/**
 Overlays settings screen — toggles for visual overlays rendered on the live
 keyboard (e.g. the hitbox debug outline).
 

 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

struct OverlaysView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            showHitboxOverlay: model.settings.showHitboxOverlay) {
            CardSection("Debug") {
                ToggleRow("Hitbox overlay",
                          subtitle: "Show touch target outlines on the real keyboard",
                          isOn: $model.settings.showHitboxOverlay)
            }
        }
        .navigationTitle("Overlays")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview { OverlaysView().clinkPreview() }
#endif
