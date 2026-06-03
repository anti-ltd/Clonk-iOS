import SwiftUI
import iUXiOS

/// A settings screen whose live keyboard preview stays pinned at the top while
/// the controls scroll beneath it — so every change is visible the moment you
/// make it, without scrolling the preview off-screen. Used by the Layout, Theme,
/// and Typing editors so they all feel the same.
struct PinnedPreviewLayout<Content: View>: View {
    let settings: KeyboardSettings
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            KeyboardPreview(settings: settings)
                .padding(.horizontal, UX.screenPadding)
                .padding(.top, UX.screenPadding)
                .padding(.bottom, UX.cardSpacing)
                .background(Color(.systemGroupedBackground))
                // A hairline keeps the pinned preview visually distinct from the
                // controls sliding under it as you scroll.
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.4)
                }

            ScrollView {
                VStack(spacing: UX.cardSpacing) {
                    content
                }
                .padding(.horizontal, UX.screenPadding)
                .padding(.top, UX.cardSpacing)
                .padding(.bottom, UX.screenPadding)
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// One tab in a `TabbedPreviewLayout`: a short label and the controls shown when
/// it's selected.
struct PreviewTab: Identifiable {
    let id: String
    let label: String
    let content: AnyView

    init<V: View>(_ label: String, @ViewBuilder content: () -> V) {
        self.id = label
        self.label = label
        self.content = AnyView(content())
    }
}

/// Like `PinnedPreviewLayout`, but the controls below the pinned preview are
/// split across a segmented tab bar — so a screen with many sections becomes a
/// few short, scannable pages instead of one long scroll. The preview AND the
/// tab bar stay fixed; only the selected tab's controls scroll.
struct TabbedPreviewLayout: View {
    let settings: KeyboardSettings
    let tabs: [PreviewTab]
    @State private var selection: String

    init(settings: KeyboardSettings, tabs: [PreviewTab]) {
        self.settings = settings
        self.tabs = tabs
        _selection = State(initialValue: tabs.first?.id ?? "")
    }

    private var current: PreviewTab? {
        tabs.first { $0.id == selection } ?? tabs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            KeyboardPreview(settings: settings)
                .padding(.horizontal, UX.screenPadding)
                .padding(.top, UX.screenPadding)
                .padding(.bottom, 12)

            Picker("Section", selection: $selection) {
                ForEach(tabs) { tab in
                    Text(tab.label).tag(tab.id)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, UX.screenPadding)
            .padding(.bottom, 12)
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .bottom) { Divider().opacity(0.4) }

            ScrollView {
                VStack(spacing: UX.cardSpacing) {
                    current?.content
                }
                .padding(.horizontal, UX.screenPadding)
                .padding(.top, UX.cardSpacing)
                .padding(.bottom, UX.screenPadding)
            }
            // Reset to the top when switching tabs so each page starts fresh.
            .id(selection)
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// A live, interactive preview of the real keyboard — the exact `KeyboardCanvas`
/// the extension renders, wired to a local string so the user can try their
/// theme/layout right inside the app without leaving to another app.
struct KeyboardPreview: View {
    let settings: KeyboardSettings
    @State private var typed: String = ""
    // Sample suggestions so the preview shows the autocomplete bar populated.
    @State private var live = KeyboardLiveState(suggestions: ["clink", "keyboard", "hello"])

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
