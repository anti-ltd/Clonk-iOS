/**
 Sounds settings — key sounds toggle, volume, and sound pack selection.
 */
import SwiftUI
import iUXiOS

struct SoundsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings) {
            CardSection {
                ToggleRow("Key sounds",
                          subtitle: "Play a sound on every keypress.",
                          isOn: $model.settings.soundEnabled)
                Divider()
                SliderRow.percent("Volume", value: $model.settings.soundVolume)
                    .disabled(!model.settings.soundEnabled)
                    .opacity(model.settings.soundEnabled ? 1 : 0.4)
            }

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
        .tint(themeAccent)
        .navigationTitle("Sounds")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var needsFullAccess: Bool {
        model.settings.soundEnabled && model.settings.soundPack.needsFullAccess
    }

    private var fullAccessNotice: some View {
        NavigationLink {
            EnableFlowView()
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
