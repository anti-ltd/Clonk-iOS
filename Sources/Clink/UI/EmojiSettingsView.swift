import SwiftUI
import iUXiOS

/// Emoji preferences — the default skin tone applied to tone-capable emoji, plus
/// a reset for the per-emoji choices made by long-pressing in the keyboard.
///
/// Precedence at type time: a per-emoji choice wins; otherwise the global
/// default here applies; otherwise the neutral (yellow) base.
struct EmojiSettingsView: View {
    @Environment(AppModel.self) private var model

    /// The emoji shown in the swatch picker — a tone-capable hand.
    private let sample = "👋"

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: UX.cardSpacing) {
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
        .navigationTitle("Emoji")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
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
                                .fill(selected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tone.label)
            }
        }
    }
}
