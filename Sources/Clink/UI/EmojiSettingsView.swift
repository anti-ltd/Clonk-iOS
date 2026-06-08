/**
 Emoji settings: scroll direction, recent-emoji toggle, global skin tone default,
 and the per-emoji skin-tone reset.
 */
import SwiftUI
import iUXiOS

/// Emoji preferences — the default skin tone applied to tone-capable emoji, plus
/// a reset for the per-emoji choices made by long-pressing in the keyboard.
///
/// Precedence at type time: a per-emoji choice wins; otherwise the global
/// default here applies; otherwise the neutral (yellow) base.
struct EmojiSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    /// The emoji shown in the swatch picker — a tone-capable hand.
    private let sample = "👋"

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if model.settings.emojiEnabled {
                EmojiPreview(
                    settings: model.settings,
                    onSetSkinTone: { base, tone in model.settings.emojiSkinTones[base] = tone }
                )
                .padding(.horizontal, UX.screenPadding)
                .padding(.top, UX.screenPadding)
                .padding(.bottom, UX.cardSpacing)
                .overlay(alignment: .bottom) { Divider().opacity(0.4) }
            }
            controls
        }
        .navigationTitle("Emoji")
        .navigationBarTitleDisplayMode(.inline)
        .themePageBackground()
    }

    private var controls: some View {
        @Bindable var model = model
        return ScrollView {
            VStack(spacing: UX.cardSpacing) {
                CardSection("Emoji panel") {
                    ToggleRow("Emoji keyboard",
                              subtitle: "Reach emoji from the panel button or by sliding up on 123. Off removes emoji entirely.",
                              isOn: $model.settings.emojiEnabled)
                }

                CardSection("Layout") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scroll direction").foregroundStyle(.secondary).font(.subheadline)
                        Picker("Scroll direction", selection: $model.settings.emojiScrollDirection) {
                            ForEach(EmojiScrollDirection.allCases) { dir in
                                Text(dir.label).tag(dir)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, UX.rowVPadding)
                    if model.settings.emojiScrollDirection == .vertical {
                        Divider()
                        Stepper(value: $model.settings.emojiColumnCount, in: 4...12) {
                            HStack {
                                Text("Columns")
                                Spacer()
                                Text("\(model.settings.emojiColumnCount)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, UX.rowVPadding)
                        }
                    }
                    if model.settings.emojiScrollDirection == .horizontal {
                        Divider()
                        Stepper(value: $model.settings.emojiRowCount, in: 2...8) {
                            HStack {
                                Text("Rows")
                                Spacer()
                                Text("\(model.settings.emojiRowCount)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, UX.rowVPadding)
                        }
                    }
                    Divider()
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
            .padding(UX.screenPadding)
        }
    }

    /// A labelled slider row: title + live value on top, the slider beneath. Used
    /// for the emoji size / spacing controls, tinted to the theme accent.
    private func sliderRow<V: BinaryFloatingPoint>(
        title: String, value: Binding<V>, range: ClosedRange<V>, display: String
    ) -> some View where V.Stride: BinaryFloatingPoint {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(display).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: range).tint(themeAccent)
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
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? themeAccent.opacity(0.18) : Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selected ? themeAccent : .clear, lineWidth: 2)
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
