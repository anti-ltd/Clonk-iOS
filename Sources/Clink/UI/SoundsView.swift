/**
 Sounds settings — two tabs: General (toggle + volume) and Sound pack (pack list).
 */
import SwiftUI
import iUXiOS

struct SoundsView: View {
    private enum Tab { case general, soundPack }

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: Tab = .general

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            bottomBar: AnyView(
                                ThemedTabPicker(
                                    options: [("General", Tab.general), ("Sound pack", Tab.soundPack)],
                                    selection: $selectedTab)
                            )) {
            switch selectedTab {
            case .general:
                generalTab(model: model)
            case .soundPack:
                soundPackTab(model: model)
            }
        }
        .tint(themeAccent)
        .navigationTitle("Sounds")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Tabs

    @ViewBuilder
    private func generalTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection {
            ToggleRow("Key sounds",
                      subtitle: "Play a sound on every keypress.",
                      isOn: $model.settings.soundEnabled)
            if model.settings.soundEnabled {
                Divider()
                SliderRow.percent("Volume", value: $model.settings.soundVolume)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.settingsReveal.animation, value: model.settings.soundEnabled)
    }

    @ViewBuilder
    private func soundPackTab(model: AppModel) -> some View {
        @Bindable var model = model
        if needsFullAccess && !model.hasFullAccess {
            fullAccessNotice
        }
        CardSection("Sound pack") {
            ForEach(Array(SoundPack.presets.enumerated()), id: \.element.id) { idx, pack in
                if idx > 0 { Divider() }
                packRow(pack)
            }
        }
        .opacity(model.settings.soundEnabled ? 1 : 0.4)
        .disabled(!model.settings.soundEnabled)
    }

    // MARK: - Helpers

    private var needsFullAccess: Bool {
        model.settings.soundEnabled && model.settings.soundPack.needsFullAccess
    }

    private var fullAccessNotice: some View {
        NavigationLink {
            EnableFlowView().tracksNavigationDepth()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield").font(.title3).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Access required").font(.subheadline.weight(.semibold))
                    Text("Custom sounds need Full Access. The standard click works without it.")
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

    private func packRow(_ pack: SoundPack) -> some View {
        Button {
            model.settings.soundPackID = pack.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(pack.name)
                        if pack.needsFullAccess {
                            Image(systemName: "lock.fill")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Text(pack.blurb).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if pack.id == model.settings.soundPackID {
                    Image(systemName: "checkmark").foregroundStyle(themeAccent)
                }
            }
            .padding(.vertical, UX.rowVPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview { SoundsView().clinkPreview() }
#endif
