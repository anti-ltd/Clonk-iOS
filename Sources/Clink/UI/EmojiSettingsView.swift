/**
 Emoji settings split across three tabs: General (enable/key), Layout (scroll,
 grid, recent, size), and Skin Tones (default tone + per-emoji reset).
 

 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

struct EmojiSettingsView: View {
    private enum Tab { case general, layout, skinTones }

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.specialKeyTint) private var specialKeyTint
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @State private var selectedTab: Tab = .general

    private var resolvedTheme: Theme {
        model.settings.resolvedTheme(dark: colorScheme == .dark)
    }
    private var themeAccent: Color { resolvedTheme.accent.color }

    private let sample = "👋"

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            EmojiPreview(
                settings: model.settings,
                onSetSkinTone: { base, tone in model.settings.emojiSkinTones[base] = tone }
            )
            .padding(.horizontal, UX.screenPadding)
            .padding(.top, UX.screenPadding)
            .padding(.bottom, UX.cardSpacing)
            .overlay(alignment: .bottom) { Divider().opacity(0.4) }

            ScrollView {
                VStack(spacing: UX.cardSpacing) {
                    switch selectedTab {
                    case .general:   generalTab(model: model)
                    case .layout:    layoutTab(model: model)
                    case .skinTones: skinTonesTab(model: model)
                    }
                }
                .padding(.horizontal, UX.screenPadding)
                .padding(.top, UX.cardSpacing)
                .padding(.bottom, UX.screenPadding)
                .animation(Motion.settingsReveal.animation, value: model.settings.emojiEnabled)
            }
            .id(selectedTab)

            ThemedTabPicker(
                options: [("General", Tab.general), ("Layout", Tab.layout), ("Skin Tones", Tab.skinTones)],
                selection: $selectedTab,
                disabledTags: model.settings.emojiEnabled ? [] : [.layout, .skinTones]
            )
            .tint(themeAccent)
            .environment(\.specialKeyTint, specialKeyTint ?? resolvedTheme.specialKeyFill.color)
            .environment(\.cardCornerRadius, cardCornerRadius)
            .padding(.horizontal, UX.screenPadding)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Divider().opacity(0.4) }
        }
        .navigationTitle("Emoji")
        .navigationBarTitleDisplayMode(.inline)
        .themePageBackground()
    }

    // MARK: - Tabs

    @ViewBuilder
    private func generalTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Emoji panel") {
            ToggleRow("Emoji keyboard",
                      subtitle: "Reach emoji from the panel button or by sliding up on 123. Off removes emoji entirely.",
                      isOn: $model.settings.emojiEnabled)
            if model.settings.emojiEnabled {
                Divider()
                ToggleRow("Emoji key next to 123",
                          subtitle: "Add a dedicated 🙂 key beside the 123 key. This removes emoji from the panel picker.",
                          isOn: $model.settings.emojiKeyInRow)
            }
        }
        if model.settings.emojiEnabled {
            CardSection("Recent") {
                ToggleRow("Show recent emoji",
                          subtitle: "Add a tab of your recently used emoji at the start of the emoji keyboard.",
                          isOn: $model.settings.showRecentEmoji)
                if model.settings.showRecentEmoji {
                    Divider()
                    Button(role: .destructive) {
                        model.settings.recentEmoji.removeAll()
                    } label: {
                        HStack {
                            Text("Clear recent emoji")
                            Spacer()
                            Text("\(model.settings.recentEmoji.count)")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, UX.rowVPadding)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.settings.recentEmoji.isEmpty)
                    .opacity(model.settings.recentEmoji.isEmpty ? 0.4 : 1)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(Motion.settingsReveal.animation, value: model.settings.showRecentEmoji)
        }
    }

    @ViewBuilder
    private func layoutTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Scroll") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Scroll direction")
                    .font(.subheadline)
                    .padding(.top, 4)
                OptionChips(
                    options: EmojiScrollDirection.allCases.map { ($0.label, $0) },
                    selection: $model.settings.emojiScrollDirection
                )
                .padding(.bottom, 4)
            }
            .padding(.vertical, UX.rowVPadding)
            if model.settings.emojiScrollDirection == .vertical {
                Divider()
                HStack {
                    Text("Columns")
                    Spacer()
                    Text("\(model.settings.emojiColumnCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    ThemedStepper(value: $model.settings.emojiColumnCount, in: 4...12)
                }
                .padding(.vertical, UX.rowVPadding)
            }
            if model.settings.emojiScrollDirection == .horizontal {
                Divider()
                HStack {
                    Text("Rows")
                    Spacer()
                    Text("\(model.settings.emojiRowCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    ThemedStepper(value: $model.settings.emojiRowCount, in: 2...8)
                }
                .padding(.vertical, UX.rowVPadding)
            }
        }

        CardSection("Size & spacing") {
            sliderRow(title: "Emoji size",
                      value: $model.settings.emojiGlyphScale,
                      range: 0.4...1.3,
                      display: "\(Int((model.settings.emojiGlyphScale * 100).rounded()))%")
            Divider()
            sliderRow(title: "Cell spacing",
                      value: $model.settings.emojiCellSpacing,
                      range: 0...14,
                      display: "\(Int(model.settings.emojiCellSpacing.rounded()))")
        }
    }

    @ViewBuilder
    private func skinTonesTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Default skin tone") {
            Text("Applied to emoji that can take a skin tone, unless you’ve set one for that emoji by holding it down in the keyboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, UX.rowVPadding)
            Divider()
            swatches
                .padding(.vertical, UX.rowVPadding)
        }

        CardSection("Per-emoji tones") {
            Button(role: .destructive) {
                model.settings.emojiSkinTones.removeAll()
            } label: {
                HStack {
                    Text("Reset saved emoji skin tones")
                    Spacer()
                    Text("\(model.settings.emojiSkinTones.count)")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, UX.rowVPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.settings.emojiSkinTones.isEmpty)
            .opacity(model.settings.emojiSkinTones.isEmpty ? 0.4 : 1)
        }
    }

    // MARK: - Helpers

    private func sliderRow<V: BinaryFloatingPoint>(
        title: String, value: Binding<V>, range: ClosedRange<V>, display: String
    ) -> some View where V.Stride: BinaryFloatingPoint {
        let doubleBinding = Binding<Double>(
            get: { Double(value.wrappedValue) },
            set: { value.wrappedValue = V($0) }
        )
        let doubleRange = Double(range.lowerBound)...Double(range.upperBound)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(display).foregroundStyle(.secondary).monospacedDigit()
            }
            ThemedSlider(value: doubleBinding, in: doubleRange)
        }
        .padding(.vertical, UX.rowVPadding)
    }

    private var swatches: some View {
        HStack(spacing: 8) {
            ForEach(SkinTone.allCases) { tone in
                let selected = model.settings.defaultSkinTone == tone
                Button {
                    model.settings.defaultSkinTone = tone
                } label: {
                    Text(EmojiSkinTone.applied(tone, to: sample))
                        .font(.system(size: 30))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(
                            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                                .fill(selected ? themeAccent.opacity(0.18) : specialKeyTint ?? Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                                .strokeBorder(selected ? themeAccent : Color.primary.opacity(0.1),
                                              lineWidth: selected ? 2 : 0.5)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tone.label)
            }
        }
    }
}

#if DEBUG
#Preview { EmojiSettingsView().clinkPreview() }
#endif
