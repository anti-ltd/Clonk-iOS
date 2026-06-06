/**
 Sound and haptics settings. Toggle, volume slider, haptics switch, and the
 sound-pack list — with a Full Access nudge when a pack requires it.
 */
import SwiftUI
import iUXiOS

/// Sound and haptics picker.
struct SoundPickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
                CardSection {
                    ToggleRow("Key sounds",
                              subtitle: "Play a sound on every keypress.",
                              isOn: $model.settings.soundEnabled)
                    Divider()
                    SliderRow.percent("Volume", value: $model.settings.soundVolume)
                        .disabled(!model.settings.soundEnabled)
                        .opacity(model.settings.soundEnabled ? 1 : 0.4)
                    Divider()
                    ToggleRow("Haptics",
                              subtitle: "A subtle tap on each keypress.",
                              isOn: $model.settings.hapticsEnabled)
                }

                // Full Access notice — only the custom packs (and haptics) need it.
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
            .padding(UX.screenPadding)
        }
        .navigationTitle("Sound & Feel")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    private var needsFullAccess: Bool {
        (model.settings.soundEnabled && model.settings.soundPack.needsFullAccess) || model.settings.hapticsEnabled
    }

    private var fullAccessNotice: some View {
        NavigationLink {
            EnableFlowView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield").font(.title3).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Access required").font(.subheadline.weight(.semibold))
                    Text("Custom sounds and haptics need Full Access. The standard click works without it.")
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
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .padding(.vertical, UX.rowVPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
