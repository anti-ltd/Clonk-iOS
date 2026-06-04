import SwiftUI
import iUXiOS

/// Setup guide: how to add Clink in the Settings app, and the honest pitch for
/// Full Access (off by default — it's only needed for custom sounds/haptics).
struct EnableFlowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UX.cardSpacing) {
                statusCard

                CardSection("1 · Add the keyboard") {
                    step("Open the Settings app.")
                    step("General → Keyboard → Keyboards → Add New Keyboard…")
                    step("Add Clink under Third-Party Keyboards.")
                }

                CardSection("2 · Use emoji") {
                    step("In any app, tap the 🌐 globe key to switch to Clink.")
                    step("Tap the emoji key (or swipe up from 123) to browse emoji right inside Clink — no extra keyboard needed.")
                }

                CardSection("3 · Full Access (optional)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Clink works fully without Full Access — you get the standard system click. Turn it on only if you want custom **clink** sound packs and haptics.")
                            .font(.callout)
                        Text("Clink is offline and has no accounts. It never sends your keystrokes anywhere — Full Access just lets the keyboard play audio and vibrate.")
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
            statusRow("Clink keyboard added", ok: model.isKeyboardEnabled)
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
