# Motion

How animation works in Clink. The short version: **every curve lives in one
file, resolves through one chokepoint, and is frozen by tests.** SwiftUI's
animator does the actual work — there is no frame loop, and there must never
be one.

## The pieces (`Sources/ClinkKit/Motion/`)

| File | What it is |
| --- | --- |
| `Motion.swift` | The vocabulary: every fixed curve in the app/keyboard as a named `MotionToken` (curve + role). Call sites use `Motion.pickerOpen.animation`, never inline literals. |
| `MotionProfile.swift` | The resolver every token passes through. Maps system state (Reduce Motion, Low Power, thermal) to a tier and degrades tokens by role. In the `.full` tier — every normal user — resolution is identity: byte-identical to the old literals. |
| `MotionSequence.swift` | `runMotionSequence(_:)`: the blessed pattern for multi-phase effects (cancellable Task + explicit `withAnimation` writes). |
| `MotionDiagnostics.swift` | Signpost events/intervals for Instruments. Compiles to nothing in Release. |

User-tunable springs (key press, space bar, popup) stay in `KeyPressPhysics`
(`KeyboardCanvas.swift`) and `KeyboardSettings` — they join the system through
`MotionToken.userSpring` / the `KeyPressPhysics` animation accessors, so the
profile can intercept them too without losing the live tuning UI.

## Adding or changing an animation

1. **New animation?** Add a token to `Motion.swift` (pick the role honestly —
   it decides Reduce-Motion behavior), add its frozen row to
   `Tests/ClinkKitTests/MotionTests.swift`, use `Motion.<name>.animation` at
   the call site.
2. **Changing a feel on purpose?** Update the token AND its test row in the
   same change. A freeze-test failure with no test update means you changed a
   feel by accident.
3. **Never** write `withAnimation(.spring(...))` with literals at a call site.
   The audit for stragglers:

   ```sh
   grep -rnE "\.spring\(response|interactiveSpring\(response|snappy\(duration|smooth\(duration|easeInOut\(duration|easeOut\(duration|linear\(duration" Sources --include="*.swift" | grep -v "Motion/"
   ```

   The only legitimate matches are `MotionToken(curve:` constructions for
   user-tuned springs.

## Token roles → Reduce Motion / Low Power behavior

| Role | Meaning | `.reduced` (Reduce Motion) | `.conserving` (Low Power / thermal) |
| --- | --- | --- | --- |
| `essential` | Tracks/settles a finger | untouched | untouched |
| `feedback` | Confirms an action | easeOut, no overshoot | untouched |
| `transition` | Moves chrome | short flat easeInOut (≤0.15s) | untouched |
| `decorative` | Ambience | instant | untouched (loop gate below) |

Two extra gates on `MotionProfile.shared`, checked where the content mounts
(they're view layers, not curves):

- `allowsExpensiveEffects` — the additive `.plusLighter` flashes and the emoji
  glass droplet. These are the layers that historically dropped frames on
  older GPUs; they rest under pressure. (`TapPulse`, `EmojiTapPulse`,
  `EmojiCanvas.flashOverlay`.)
- `allowsAmbientMotion` — **every `repeatForever` call site must check this
  before starting the loop.** A forever loop can't be softened by resolving
  to a shorter curve; a zero-duration forever loop spins hot. (`CursorView`.)

## The three blessed patterns

1. **Render-side multi-phase effects** — explicit `@State` writes inside
   `withAnimation`, sequenced by `runMotionSequence`, previous task cancelled
   on re-trigger, every path ending at the rest pose.
   NOT `keyframeAnimator` (its content closure re-runs on the main thread
   every frame — per-frame compositing over glass dropped the press bloom to a
   crawl) and NOT `phaseAnimator` (a mid-cycle re-trigger can park it on the
   bright phase: the stuck-lit-key bug). Template: `EmojiGlassFlashView`.
2. **Per-element observable press state** — each key observes only its own
   `KeyPressState`, so a press invalidates one view, not the grid. Never
   re-introduce a shared "pressed keys" set. Template: `KeyTouchRouter` /
   `KeyView`.
3. **Gesture-live, spring-on-release** — while a finger drags, apply offsets
   un-animated (1:1 tracking, no spring backlog = no stutter); let the spring
   fire only on release, keyed to state that flips at release time. Template:
   the space-bar lean in `KeyView.warp`.

## Anti-patterns (rejected on purpose — don't relitigate without a trace)

- A `CADisplayLink`/`TimelineView` render loop driving animation values.
- Custom interpolators or a keyframe engine.
- `glassEffect` per cell/key for one-shot effects — mount ONE flash view while
  in flight (`flashOverlay`), zero glass cost at rest.
- Inline animation literals (see audit above).

## Measuring

- **Keyboard extension**: Instruments → os_signpost / Points of Interest,
  attached to the ClinkKeyboard process while typing in a host app.
  `MotionDiagnostics.event/interval` marks panel opens, emoji flashes, height
  changes — add events where you're investigating.
- **App**: launch with `--motion-hud` (Xcode scheme → Run → Arguments) for a
  live FPS / worst-frame overlay (`MotionHUD`, DEBUG-only). Frames >34ms read
  as hitches. MetricKit daily hitch/hang payloads log to console in DEBUG
  (`MotionMetrics`).
- Tune by measurement, not by feel alone: capture a trace before and after.

## Verifying nothing changed

`make test` runs the freeze table (`MotionTests`): every token equals its
historical literal, `.full`-tier resolution is identity, and the degraded
tiers map exactly by role. The grep audit above proves coverage.
