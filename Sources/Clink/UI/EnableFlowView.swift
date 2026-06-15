/**
 Step-by-step keyboard setup guide: how to add Clink and the honest pitch for
 Full Access. Also shows live enable / Full Access status.
 

 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
import SwiftUI
import iUXiOS

/// Setup guide: how to add Clink in Settings and the honest pitch for Full Access.
/// Status rows refresh when the app returns to foreground (`ClinkApp.onChange`).
struct EnableFlowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.cardCornerRadius) private var cardCornerRadius
    /// Navigation title — "Setup" when pushed from the Setup page, "Permissions"
    /// when shown as the onboarding Permissions page.
    var title: String = "Setup"

    private var themeAccent: Color {
        model.settings.resolvedTheme(dark: colorScheme == .dark).accent.color
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UX.cardSpacing) {
                statusCard

                CardSection("1 · Add the keyboard") {
                    step("Open the Settings app.")
                    Divider()
                    step("General → Keyboard → Keyboards → Add New Keyboard…")
                    Divider()
                    step("Add Clink under Third-Party Keyboards.")
                }

                CardSection("2 · Switch to Clink") {
                    step("In any app, tap the 🌐 globe key to switch to Clink.")
                    Divider()
                    step("Tap the emoji key, or swipe up on 123, to open emoji inside Clink. No second keyboard.")
                }

                CardSection("3 · Full Access (optional)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Clink works fully without Full Access. You still get the standard system click. Flip it on if you want custom **clink** sound packs and haptics.")
                            .font(.callout)
                        Text("Clink is offline with no accounts. Your keystrokes never leave the device. Full Access only lets the keyboard play audio and vibrate.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, UX.rowVPadding)
                }

                Button {
                    openSettings()
                } label: {
                    Label("Open Settings", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(ThemedFillButtonStyle(fill: themeAccent, corner: cardCornerRadius))
            }
            .padding(.horizontal, UX.screenPadding)
            .padding(.top, UX.cardSpacing)
            .padding(.bottom, UX.screenPadding)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .themePageBackground()
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
