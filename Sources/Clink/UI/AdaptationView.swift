/**
 Adaptation — on-device personalization. Houses the opt-in learning that
 remembers the words you actually type, boosts the ones you pick from the bar,
 and stops re-applying corrections you reject. Everything here stays on the
 device (App Group file, see `UserAdaptation`); nothing is ever uploaded.

 Two tabs — General (learning toggle) and History (clear control plus the list
 of learned words). No keyboard preview: learning has no visible on-screen
 effect to show.


 Module: app-ui · Target: Clink
 Learn: docs/04-prediction.md
 */
import SwiftUI
import iUXiOS

/// On-device learning toggle and learned-word management.
/// `$model.settings.learningEnabled` persists via `AppModel.settings` `didSet`.
/// Learned words live in `UserAdaptation` (App Group file), not settings JSON.
struct AdaptationView: View {
    private enum Tab { case general, history }

    @Environment(AppModel.self) private var model
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    @State private var selectedTab: Tab = .general
    /// Learned words, read fresh on appear. The keyboard runs in a separate
    /// process and writes the store coalesced, so a fresh read reflects what it
    /// last saved — `UserAdaptation.shared` here would be a stale,
    /// app-launch-time snapshot.
    @State private var learnedWords: [String] = []
    @State private var justCleared = false
    @State private var openRow: Int? = nil

    private var learnedCount: Int { learnedWords.count }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: UX.cardSpacing) {
                    switch selectedTab {
                    case .general: generalTab(model: model)
                    case .history: historyTab
                    }
                }
                .padding(UX.screenPadding)
            }
            .id(selectedTab)

            ThemedTabPicker(
                options: [("General", Tab.general), ("History", Tab.history)],
                selection: $selectedTab,
                disabledTags: model.settings.learningEnabled ? [] : [.history]
            )
            .padding(.horizontal, UX.screenPadding)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Divider().opacity(0.4) }
        }
        .navigationTitle("Adaptation")
        .navigationBarTitleDisplayMode(.inline)
        .themePageBackground()
        .onAppear {
            learnedWords = UserAdaptation().organicLearnedWords()
            if learnedCount > 0 { justCleared = false }
        }
    }

    // MARK: - Tabs

    @ViewBuilder
    private func generalTab(model: AppModel) -> some View {
        @Bindable var model = model
        CardSection("Learning") {
            ToggleRow("Learn from your typing",
                      subtitle: "Remember words you use often, favour the ones you pick from the bar, and stop re-applying corrections you reject.",
                      isOn: $model.settings.learningEnabled)
        }

        Text("Learning happens entirely on this device. Nothing you type is uploaded, and clearing wipes the learned words immediately.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var historyTab: some View {
        CardSection("History Control") {
            HStack {
                Text(countLabel)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, UX.rowVPadding)
            Divider()
            Button(role: .destructive) {
                // Fresh instance, not `.shared` (an app-launch snapshot): `clear`
                // keeps pinned custom words, and the live file may hold custom
                // words added this session that the stale snapshot lacks — using
                // `.shared` would drop them. See `forget` below.
                UserAdaptation().clear()
                learnedWords = []
                justCleared = true
            } label: {
                HStack {
                    Text(justCleared ? "Learned words cleared" : "Clear learned words")
                        .foregroundStyle(justCleared || learnedCount == 0
                                         ? AnyShapeStyle(.secondary)
                                         : AnyShapeStyle(Color.red))
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.vertical, UX.rowVPadding)
            }
            .buttonStyle(.plain)
            .disabled(justCleared || learnedCount == 0)
        }

        if !learnedWords.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Learned words")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                VStack(spacing: 8) {
                    ForEach(Array(learnedWords.enumerated()), id: \.element) { index, word in
                        SwipeRow(id: index, cornerRadius: cardCornerRadius, actions: [
                            SwipeAction(icon: "trash.fill", label: "Forget",
                                        tint: .red) { forget(word) },
                        ], openID: $openRow,
                           cardBackground: {
                            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                                )
                        }) {
                            HStack {
                                Text(word)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
        }
    }

    private func forget(_ word: String) {
        // Fresh instance loads the latest on-disk store (the keyboard writes it
        // from another process) and removes just this one key — so we don't
        // clobber words learned since the app launched, the way the stale
        // `.shared` snapshot would.
        UserAdaptation().forgetLearnedWord(word)
        learnedWords.removeAll { $0 == word }
    }

    private var countLabel: String {
        switch learnedCount {
        case 0:  "No words learned yet"
        case 1:  "1 word learned"
        default: "\(learnedCount) words learned"
        }
    }
}

#if DEBUG
#Preview { AdaptationView().clinkPreview() }
#endif
