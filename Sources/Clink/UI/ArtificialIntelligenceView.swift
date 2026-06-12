/**
 Artificial Intelligence — opt-in, on-device Apple Intelligence. Houses the
 master switch future AI features (predictive typing, translation, suggestions,
 adaptive hitboxes) will gate on, plus a live availability readout. Requires
 iOS 26+ on Apple Intelligence-capable hardware; inference runs entirely on
 device via a system process, so nothing ever leaves the phone.

 No keyboard preview: enabling AI has no visible on-screen effect yet, so this
 is a plain scrolled page (like `AdaptationView`) rather than `PinnedPreviewLayout`.
 */
import SwiftUI
import iUXiOS

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

                CardSection("Status") {
                    HStack(spacing: 12) {
                        Image(systemName: statusIcon)
                            .foregroundStyle(availability == .available ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        Text(statusText)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, UX.rowVPadding)
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
        .onAppear { availability = AIAvailability.current() }
        // Re-probe when returning from Settings.app (e.g. after turning on
        // Apple Intelligence) or once a pending model download finishes.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { availability = AIAvailability.current() }
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
        case .deviceNotEligible:            "This device doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled:  "Turn on Apple Intelligence in Settings → Apple Intelligence & Siri."
        case .modelNotReady:                "The model is downloading or preparing. Try again shortly."
        case .unavailableOther:             "Apple Intelligence is currently unavailable."
        }
    }
}

#if DEBUG
#Preview { ArtificialIntelligenceView().clinkPreview() }
#endif
