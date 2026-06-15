/**
 Artificial Intelligence — opt-in, on-device Apple Intelligence. Houses the
 master switch AI features gate on, the per-feature assist toggles (Suggestions,
 Auto-correction, Prediction), and a live availability readout. Requires iOS 26+
 on Apple Intelligence-capable hardware; inference runs entirely on device via a
 system process, so nothing ever leaves the phone.

 The assists are deliberately additive: the keyboard's fast offline engine still
 drives suggestions/correction/prediction instantly, and AI only runs async to
 raise result quality — it never sits in the keystroke hot path (see the
 `aiSuggestions` / `aiAutocorrect` / `aiPrediction` settings docs).

 No keyboard preview: enabling AI has no visible on-screen effect yet, so this
 is a plain scrolled page rather than `PinnedPreviewLayout`.
 

 Module: app-ui · Target: Clink
 Learn: docs/04-prediction.md
 */
import SwiftUI
import iUXiOS

/// Apple Intelligence master switch and availability readout.
/// `$model.settings.aiEnabled` persists via `AppModel.settings` `didSet`.
struct ArtificialIntelligenceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var availability: AIAvailability = .osBelowMinimum

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: UX.cardSpacing) {
                CardSection("Apple Intelligence") {
                    ToggleRow("Enable AI",
                              subtitle: "On-device intelligence for upcoming keyboard features like smarter predictions and translation.",
                              isOn: $model.settings.aiEnabled)
                        .disabled(availability != .available)
                        .opacity(availability == .available ? 1 : 0.5)
                }

                CardSection("Assists") {
                    ToggleRow("Suggestions",
                              subtitle: "AI sharpens the suggestion bar for what you're typing — more accurate, context-aware picks.",
                              isOn: $model.settings.aiSuggestions)
                    Divider()
                    ToggleRow("Auto-correction",
                              subtitle: "AI helps resolve the corrections the keyboard is least sure about.",
                              isOn: $model.settings.aiAutocorrect)
                    Divider()
                    ToggleRow("Prediction",
                              subtitle: "AI improves next-word prediction and adaptive key hitboxes.",
                              isOn: $model.settings.aiPrediction)
                }
                .disabled(!assistsActive)
                .opacity(assistsActive ? 1 : 0.5)

                CardSection("Translation") {
                    ToggleRow("Use AI for translation",
                              subtitle: "Translation works offline without AI. Turn this on to use Apple Intelligence instead for higher-quality results on this device.",
                              isOn: $model.settings.aiTranslate)
                }
                .disabled(!assistsActive)
                .opacity(assistsActive ? 1 : 0.5)

                Text("Assists are additive — the keyboard's fast offline suggestions, corrections, and prediction keep working instantly. AI runs in the background and only upgrades the result when it's ready, so nothing slows down your typing.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)

                CardSection("Status") {
                    HStack(spacing: 12) {
                        Image(systemName: statusIcon)
                            .foregroundStyle(statusColor)
                        Text(statusText)
                            .foregroundStyle(availability == .available ? AnyShapeStyle(.secondary) : AnyShapeStyle(statusColor))
                        Spacer()
                    }
                    .padding(.vertical, UX.rowVPadding)
                }

                // When AI is switched on but the device can't run it, the bar will
                // silently show no AI words — call that out so it isn't mistaken
                // for a bug.
                if model.settings.aiEnabled && availability != .available {
                    Text("AI is on, but \(unavailableReason) AI suggestions, corrections, and translation won't appear until this is resolved. Your offline suggestions keep working.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                }

                Text("AI runs entirely on this device using Apple Intelligence. It works offline, nothing you type is uploaded, and every AI feature stays off unless you turn it on here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }
            .padding(UX.screenPadding)
        }
        .navigationTitle("Artificial Intelligence")
        .navigationBarTitleDisplayMode(.inline)
        .themePageBackground()
        .onAppear {
            availability = AIAvailability.current()
            prewarmIfReady()
        }
        // Re-probe when returning from Settings.app (e.g. after turning on
        // Apple Intelligence) or once a pending model download finishes.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                availability = AIAvailability.current()
                prewarmIfReady()
            }
        }
        // Warm the model the moment the user flips AI on, so the first real
        // suggestion in the keyboard isn't gated on cold model load.
        .onChange(of: model.settings.aiEnabled) { _, _ in prewarmIfReady() }
    }

    /// The per-feature assist toggles only matter when AI is both available and
    /// switched on; otherwise they're shown dimmed and disabled.
    private var assistsActive: Bool {
        availability == .available && model.settings.aiEnabled
    }

    /// Kick off a model prewarm when AI is on and the device can run it. The
    /// engine no-ops otherwise, but gating here avoids a needless actor hop.
    private func prewarmIfReady() {
        guard model.settings.aiEnabled, availability == .available else { return }
        Task { await AIEngine.shared.prewarm() }
    }

    /// Status colour by severity: ready is the accent tint, a transient download
    /// is orange, everything blocking is also orange (actionable warning) — never
    /// a neutral grey that reads as "fine".
    private var statusColor: AnyShapeStyle {
        availability == .available ? AnyShapeStyle(.tint) : AnyShapeStyle(.orange)
    }

    /// Lower-cased, sentence-fragment form of the blocking reason, for the inline
    /// "AI is on but…" warning.
    private var unavailableReason: String {
        switch availability {
        case .available:                    "it's ready."
        case .osBelowMinimum:               "this device needs iOS 26 or later."
        case .deviceNotEligible:            "this device doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled:  "Apple Intelligence is off in Settings → Apple Intelligence & Siri."
        case .modelNotReady:                "the model is still downloading or preparing."
        case .unavailableOther:             "Apple Intelligence is currently unavailable."
        }
    }

    private var statusIcon: String {
        switch availability {
        case .available:                    "checkmark.circle"
        case .osBelowMinimum:               "exclamationmark.circle"
        case .deviceNotEligible:            "xmark.circle"
        case .appleIntelligenceNotEnabled:  "gear.badge"
        case .modelNotReady:                "arrow.down.circle.dotted"
        case .unavailableOther:             "questionmark.circle"
        }
    }

    private var statusText: String {
        switch availability {
        case .available:                    "Apple Intelligence is ready on this device."
        case .osBelowMinimum:               "Requires iOS 26 or later."
        case .deviceNotEligible:            "Apple Intelligence not supported"
        case .appleIntelligenceNotEnabled:  "Turn on Apple Intelligence in Settings → Apple Intelligence & Siri."
        case .modelNotReady:                "The model is downloading or preparing. Try again shortly."
        case .unavailableOther:             "Apple Intelligence is currently unavailable."
        }
    }
}

#if DEBUG
#Preview { ArtificialIntelligenceView().clinkPreview() }
#endif
