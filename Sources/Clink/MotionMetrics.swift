/**
 `MotionMetrics`: DEBUG-only MetricKit subscriber for the container app.

 Logs the OS's own animation-hitch and hang measurements (collected system-wide,
 delivered daily) so regressions in animation smoothness show up in the console
 without any in-process measurement cost. App only — MetricKit delivery is
 unreliable inside extension processes and the keyboard's memory budget is
 precious, so the extension is profiled via `MotionDiagnostics` signposts in
 Instruments instead.
 

 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
#if DEBUG
import Foundation
import MetricKit
import OSLog

/// DEBUG MetricKit subscriber. Logs daily OS animation-hitch and hang histograms
/// to the console — zero in-process measurement cost. App target only.
final class MotionMetrics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MotionMetrics()

    private let log = Logger(subsystem: "ltd.anti.clink", category: "MotionMetrics")

    /// Subscribe to daily metric payloads. Call once at app launch.
    func start() {
        MXMetricManager.shared.add(self)
    }

    /// Delivered by MetricKit on a background queue, typically once per day.
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            if let animation = payload.animationMetrics {
                log.info("Animation hitch time ratio: \(animation.scrollHitchTimeRatio, privacy: .public)")
            }
            if let responsiveness = payload.applicationResponsivenessMetrics {
                log.info("Hang time histogram: \(responsiveness.histogrammedApplicationHangTime.totalBucketCount, privacy: .public) buckets")
            }
        }
    }
}
#endif
