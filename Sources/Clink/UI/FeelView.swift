/**
 Feel settings — sounds and haptics under one page, two tabs (Sound · Haptics).
 Merges the former separate Sounds and Haptics pages to cut a Home card and a
 sidebar row. Each tab is a single scroll; custom sound packs and haptics need
 Full Access (noted inline).


 Module: app-ui · Target: Clink
 Learn: docs/06-sound.md
 */
import SwiftUI
import iUXiOS

/// Sound + haptic feedback, two tabs sharing one pinned preview.
/// `$model.settings` bindings persist via `AppModel.settings` `didSet`.
struct FeelView: View {
    private enum Tab { case sound, haptics }

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: Tab = .sound

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    var body: some View {
        @Bindable var model = model
        PinnedPreviewLayout(settings: model.settings,
                            bottomBar: AnyView(
                                ThemedTabPicker(
                                    options: [("Sound", Tab.sound), ("Haptics", Tab.haptics)],
                                    selection: $selectedTab)
                            )) {
            switch selectedTab {
            case .sound:   SoundControls()
            case .haptics: HapticControls()
            }
        }
        .tint(themeAccent)
        .navigationTitle("Feel")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sound

/// Key-sound toggle, volume, and sound-pack picker — a single scroll.
struct SoundControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }
    private var needsFullAccess: Bool {
        model.settings.soundEnabled && model.settings.soundPack.needsFullAccess
    }

    var body: some View {
        @Bindable var model = model
        CardSection {
            ToggleRow("Key sounds",
                      subtitle: "Play a sound on every keypress.",
                      isOn: $model.settings.soundEnabled)
            Divider()
            SliderRow.percent("Volume", value: $model.settings.soundVolume)
                .gated(model.settings.soundEnabled,
                       reason: "Turn on Key sounds to set the volume.")
        }
        if needsFullAccess && !model.hasFullAccess {
            fullAccessNotice
        }
        GatedCard("Sound pack", enabled: model.settings.soundEnabled,
                  reason: "Turn on Key sounds to choose a pack.") {
            ForEach(Array(SoundPack.presets.enumerated()), id: \.element.id) { idx, pack in
                if idx > 0 { Divider() }
                packRow(pack)
            }
        }
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

// MARK: - Haptics

/// Key-press haptic toggle, style, and strength — a single scroll. Requires Full
/// Access to fire in the extension.
struct HapticControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if !model.hasFullAccess {
            fullAccessNotice
        }
        CardSection {
            ToggleRow("Key press haptics",
                      subtitle: "A tap on each keypress.",
                      isOn: $model.settings.hapticsEnabled)
        }
        GatedCard("Feel", enabled: model.settings.hapticsEnabled,
                  reason: "Turn on Key press haptics to adjust the feel.") {
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
            SliderRow("Strength",
                      tooltip: "Higher feels punchier and more mechanical. Lower is a faint tick.",
                      value: $model.settings.hapticIntensity,
                      in: 0.1...1.0, step: 0.05) {
                "\(Int(($0 * 100).rounded()))%"
            }
        }
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
#Preview { FeelView().clinkPreview() }
#endif
