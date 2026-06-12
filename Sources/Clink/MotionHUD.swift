/**
 `MotionHUD`: DEBUG-only frame-rate / hitch overlay for the container app.

 The ONLY `CADisplayLink` in the project, and deliberately so — it exists to
 measure animation smoothness while hand-testing, never to drive animation.
 Shown only when the app is launched with `--motion-hud` (Xcode scheme → Run →
 Arguments), which also means it can never run in the keyboard extension
 process. Compiled out of Release entirely.

 Reads: current FPS over a half-second window, plus the worst single frame in
 that window (a 60Hz frame is 16.7ms; anything beyond ~34ms is a visible hitch).
 

 Module: app-ui · Target: Clink
 Learn: docs/09-app-ui.md
 */
#if DEBUG
import SwiftUI
import QuartzCore

/// Half-second-windowed FPS + worst-frame meter driven by a display link.
@MainActor @Observable
final class FPSMonitor: NSObject {
    private(set) var fps: Double = 0
    private(set) var worstFrameMS: Double = 0

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var frames = 0
    @ObservationIgnored private var windowStart: CFTimeInterval = 0
    @ObservationIgnored private var lastTimestamp: CFTimeInterval = 0
    @ObservationIgnored private var worst: CFTimeInterval = 0

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        if lastTimestamp > 0 {
            worst = max(worst, link.timestamp - lastTimestamp)
            frames += 1
            let elapsed = link.timestamp - windowStart
            if elapsed >= 0.5 {
                fps = Double(frames) / elapsed
                worstFrameMS = worst * 1000
                frames = 0
                worst = 0
                windowStart = link.timestamp
            }
        } else {
            windowStart = link.timestamp
        }
        lastTimestamp = link.timestamp
    }
}

struct MotionHUD: View {
    @State private var monitor = FPSMonitor()

    var body: some View {
        HStack(spacing: 8) {
            Text("\(Int(monitor.fps.rounded())) fps")
            Text("\(monitor.worstFrameMS, specifier: "%.0f")ms")
                .foregroundStyle(monitor.worstFrameMS > 34 ? .red : .secondary)
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.65), in: Capsule())
        .foregroundStyle(.white)
        .allowsHitTesting(false)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}
#endif
