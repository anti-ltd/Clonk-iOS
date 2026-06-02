import SwiftUI
import iUXiOS

/// A live, interactive preview of the real keyboard — the exact `KeyboardCanvas`
/// the extension renders, wired to a local string so the user can try their
/// theme/layout right inside the app without leaving to another app.
struct KeyboardPreview: View {
    let settings: KeyboardSettings
    @State private var typed: String = ""
    // Sample suggestions so the preview shows the autocomplete bar populated.
    @State private var live = KeyboardLiveState(suggestions: ["clonk", "keyboard", "hello"])

    var body: some View {
        VStack(spacing: 0) {
            // Faux text field showing what's been typed.
            HStack {
                Text(typed.isEmpty ? "Try it out…" : typed)
                    .foregroundStyle(typed.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 0)
                if !typed.isEmpty {
                    Button { typed = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.background.secondary)

            // A representative backdrop sits behind the keyboard so Liquid
            // Glass themes have something to refract — mirroring how the real
            // keyboard floats over app content. Solid themes have an opaque
            // background and simply cover it.
            KeyboardCanvas(
                settings: settings,
                live: live,
                onInsert: { typed.append($0) },
                onBackspace: { if !typed.isEmpty { typed.removeLast() } },
                onSuggestion: { typed += $0 + " " }
            )
            // Pin to the same content height the extension uses, so the preview
            // has no indefinite-height gap below the keys.
            .frame(height: KeyboardCanvas.preferredHeight(for: settings))
            .background {
                LinearGradient(
                    colors: [
                        Color(.sRGB, red: 0.36, green: 0.40, blue: 0.78),
                        Color(.sRGB, red: 0.85, green: 0.42, blue: 0.55),
                        Color(.sRGB, red: 0.95, green: 0.70, blue: 0.38),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}
