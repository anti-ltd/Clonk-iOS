import SwiftUI
import iUXiOS

/// Setup guide: how to add Clonk in the Settings app, and the honest pitch for
/// Full Access (off by default — it's only needed for custom sounds/haptics).
struct EnableFlowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UX.cardSpacing) {
                statusCard

                CardSection("1 · Add the keyboards") {
                    step("Open the Settings app.")
                    step("General → Keyboard → Keyboards → Add New Keyboard…")
                    step("Add both Clonk and Clonk Emoji under Third-Party Keyboards.")
                }

                CardSection("2 · Switch between them") {
                    step("In any app, tap the 🌐 globe key to cycle keyboards.")
                    step("Clonk and Clonk Emoji share these settings — configure once, both match.")
                }

                CardSection("3 · Full Access (optional)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Clonk works fully without Full Access — you get the standard system click. Turn it on only if you want custom **clonk** sound packs and haptics.")
                            .font(.callout)
                        Text("Clonk is offline and has no accounts. It never sends your keystrokes anywhere — Full Access just lets the keyboard play audio and vibrate.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, UX.rowVPadding)
                }

                Button {
                    openSettings()
                } label: {
                    Label("Open Settings", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(UX.screenPadding)
        }
        .navigationTitle("Setup")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    private var statusCard: some View {
        CardSection {
            statusRow("Clonk keyboard added", ok: model.isKeyboardEnabled)
            Divider()
            statusRow("Clonk Emoji added", ok: model.isEmojiEnabled,
                      offText: "Off — add it to type emoji")
            Divider()
            statusRow("Full Access", ok: model.hasFullAccess,
                      offText: "Off — custom sounds & haptics disabled")
        }
    }

    private func statusRow(_ label: String, ok: Bool, offText: String? = nil) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                if !ok, let offText {
                    Text(offText).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, UX.rowVPadding)
    }

    private func step(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.turn.down.right").font(.caption).foregroundStyle(.tint)
            Text(text).font(.callout)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
