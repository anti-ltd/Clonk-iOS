/**
 Adaptation — on-device personalization. Houses the opt-in learning that
 remembers the words you actually type, boosts the ones you pick from the bar,
 and stops re-applying corrections you reject. Everything here stays on the
 device (App Group file, see `UserAdaptation`); nothing is ever uploaded.

 No keyboard preview: learning has no visible on-screen effect to show, so this
 is a plain scrolled page (like `BackupView`) rather than `PinnedPreviewLayout`.
 

 Module: app-ui · Target: Clink
 Learn: docs/04-prediction.md
 */
import SwiftUI
import iUXiOS

/// On-device learning toggle and learned-word management.
/// `$model.settings.learningEnabled` persists via `AppModel.settings` `didSet`.
/// Learned words live in `UserAdaptation` (App Group file), not settings JSON.
struct AdaptationView: View {
    @Environment(AppModel.self) private var model
    /// Current learned-word count, read fresh on appear. The keyboard runs in a
    /// separate process and writes the store coalesced, so a fresh read reflects
    /// what it last saved — `UserAdaptation.shared` here would be a stale,
    /// app-launch-time snapshot.
    @State private var learnedCount = 0
    @State private var justCleared = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: UX.cardSpacing) {
                CardSection("Learning") {
                    ToggleRow("Learn from your typing",
                              subtitle: "Remember words you use often, favour the ones you pick from the bar, and stop re-applying corrections you reject.",
                              isOn: $model.settings.learningEnabled)
                }

                if model.settings.learningEnabled {
                    CardSection("Learned words") {
                        HStack {
                            Text(countLabel)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, UX.rowVPadding)
                        Divider()
                        Button(role: .destructive) {
                            UserAdaptation.shared.clear()
                            learnedCount = 0
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
                }

                Text("Learning happens entirely on this device. Nothing you type is uploaded, and clearing wipes the learned words immediately.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }
            .padding(UX.screenPadding)
        }
        .navigationTitle("Adaptation")
        .navigationBarTitleDisplayMode(.inline)
        .themePageBackground()
        .onAppear {
            learnedCount = UserAdaptation().learnedWords().count
            if learnedCount > 0 { justCleared = false }
        }
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
