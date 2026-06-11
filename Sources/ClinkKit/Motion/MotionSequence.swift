/**
 `MotionSequence`: the blessed pattern for multi-phase, render-side animations.

 Codifies what `TapPulse` and `EmojiGlassFlashView` proved out by hand: a
 cancellable `Task` that sleeps between explicit `withAnimation` state writes.
 This is deliberately NOT `keyframeAnimator` (its content closure re-runs on
 the main thread every frame — per-frame `.plusLighter` compositing over glass
 dropped the press bloom to a crawl) and NOT `phaseAnimator` (a re-trigger
 mid-cycle can park it on a bright phase, leaving the element visibly stuck
 lit). A sequence re-trigger cancels the in-flight task; design every sequence
 so the LAST steps return the element to rest, and a stuck pose is impossible
 as long as the caller cancels the previous task before starting a new one.

 Usage (the emoji glass flash):
     playTask?.cancel()
     playTask = runMotionSequence([
         MotionStep(animation: Motion.emojiFlashBloom.animation)  { opacity = 0.85 },
         MotionStep(animation: Motion.emojiFlashMorph.animation)  { scale = 1.08 },
         MotionStep(delay: .seconds(0.06),
                    animation: Motion.emojiFlashFade.animation)   { opacity = 0 },
         MotionStep(delay: .seconds(0.09),
                    animation: Motion.emojiFlashSettle.animation) { scale = 0.97 },
     ])
 */
import SwiftUI

/// One step of a motion sequence: wait `delay` (measured from the previous
/// step), then apply the state write inside `animation` (or with no animation
/// when nil — a snap).
@MainActor
struct MotionStep {
    var delay: Duration = .zero
    var animation: Animation?
    var apply: () -> Void

    init(delay: Duration = .zero, animation: Animation? = nil, apply: @escaping () -> Void) {
        self.delay = delay
        self.animation = animation
        self.apply = apply
    }
}

/// Run the steps in order on the main actor, returning the task so the caller
/// can cancel it on re-trigger (always keep and cancel it — see header).
/// Cancellation is checked after every sleep; steps already applied stay.
@MainActor @discardableResult
func runMotionSequence(_ steps: [MotionStep]) -> Task<Void, Never> {
    Task { @MainActor in
        for step in steps {
            if step.delay > .zero {
                try? await Task.sleep(for: step.delay)
                guard !Task.isCancelled else { return }
            }
            if let animation = step.animation {
                withAnimation(animation) { step.apply() }
            } else {
                step.apply()
            }
        }
    }
}
