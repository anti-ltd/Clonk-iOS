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
                          subtitle: "A tap on each keypress.",
                          isOn: $model.settings.hapticsEnabled)
            }

            if model.settings.hapticsEnabled {
                CardSection("Feel") {
                    Text("How each keystroke lands in your hand. Heavier styles and a higher strength read punchier and more mechanical; lighter is a faint tick.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, UX.rowVPadding)
                    Divider()
                    HStack {
                        Text("Style")
                        Spacer()
                        Picker("Style", selection: $model.settings.hapticStyle) {
                            ForEach(HapticStyle.allCases) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .padding(.vertical, UX.rowVPadding)
                    Divider()
                    SliderRow("Strength", value: $model.settings.hapticIntensity,
                              in: 0.1...1.0, step: 0.05) {
                        "\(Int(($0 * 100).rounded()))%"
                    }
                }
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
            EnableFlowView().tracksNavigationDepth()
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

#if DEBUG
#Preview { HapticsView().clinkPreview() }
#endif
