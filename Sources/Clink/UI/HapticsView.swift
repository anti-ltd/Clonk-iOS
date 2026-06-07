/**
 Haptics settings — key press haptic feedback toggle.
 */
import SwiftUI
import iUXiOS

struct HapticsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings) {
            CardSection {
                ToggleRow("Key press haptics",
                          subtitle: "A subtle tap on each keypress.",
                          isOn: $model.settings.hapticsEnabled)
            }

            if model.settings.hapticsEnabled && !model.hasFullAccess {
                fullAccessNotice
            }
        }
        .tint(themeAccent)
        .navigationTitle("Haptics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var fullAccessNotice: some View {
        NavigationLink {
            EnableFlowView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield").font(.title3).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Access required").font(.subheadline.weight(.semibold))
                    Text("Haptics need Full Access to work.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
