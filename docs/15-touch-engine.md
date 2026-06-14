# Touch engine

## What it is

The unified owner of every finger event in the keyboard: hit-testing, key
commit, gestures (swipe, accent, space cursor, backspace repeat, drag-up), and
the press/animation state the renderer reads. Promotes the old `KeyTouchRouter`
into a single subsystem with **one hard contract**:

> **Text-first.** A keystroke is committed to the document independently of, and
> never behind, any animation work. Animation may drop frames freely; the
> character is already in the document.

This exists to make fast typing never drop a keystroke.

---

## Why it was dropping keys

Two separate causes, fixed in order:

1. **SwiftUI gesture system dropped simultaneous touches** (a fast typist presses
   the next key before lifting the last). Fixed earlier by routing all touches
   through one UIKit `UIView` with `isMultipleTouchEnabled`
   (`KeyGridTouchView`) — see [03-touch-and-input](03-touch-and-input.md).

2. **The letter commit shared a queue with the animations.** Each letter insert
   was deferred with `DispatchQueue.main.async`. That deferral existed to let the
   press bloom render before the insert ran a *synchronous* autocorrect
   (`UITextChecker`). But autocorrect was later moved to a debounce
   (`KeyboardViewController.scheduleSuggestionUpdate`), so the deferral became
   dead weight: it only parked each keystroke on the **same main queue the
   press/release springs flood**. Under animation load at speed the deferred
   block landed late, piled up, and in the memory-pressured extension could be
   lost. Fixed by committing letters **synchronously inside the touch event**
   (`TouchEngine.touchDown`).

The commit-timing rule that came out of (2):

| Key | Commit | Why |
|---|---|---|
| Letter (non-space character) | **Synchronous** on touch-down | Cheap (proxy enqueue + mirror), and the drop-prone fast-burst case |
| Space (terminator) | Deferred one runloop hop | Runs the correction-only `UITextChecker` synchronously (tens of ms); deferring keeps that off the release spring's first frames. Not drop-prone — one deliberate press at the end-of-word pause |
| Function (shift/123/return/globe) | On touch-up | Fire on release by design |
| Backspace | Touch-down + hold-to-repeat | — |

> **Rule:** commit synchronously when **cheap AND drop-prone**; defer when
> **heavy AND not drop-prone**.

---

## Architecture (target — the unification)

Three concerns, deliberately separated so input can never starve behind render:

```
KeyGridTouchView (UIKit, isMultipleTouchEnabled)
    │  raw UITouch began/moved/ended/cancelled
    ▼
TouchEngine
    ├── InputCore     — hit-test → bind touch → COMMIT (synchronous, text-first)
    │                   never reads/writes a spring; only the document + mirror
    ├── GestureCore   — swipe / accent / space-cursor / backspace-repeat /
    │                   drag-up state machines (each a small, testable unit)
    └── RenderDriver  — pushes animation INTENT into per-key @Observable state
                        (isPressed, tapTick, neighborTick, bulge); the only thing
                        KeyView reads. Frame drops here cost zero keystrokes.
```

`KeyPressState` (per key, `@Observable`) stays exactly as is — the per-key
observation that keeps a press from invalidating the whole grid is load-bearing
and measured. RenderDriver writes it; KeyView reads its own.

The point of the split: **InputCore has no dependency on RenderDriver.** A
keystroke's correctness path touches the document and the local mirror and
nothing else. Animation is a downstream consumer of intent, not a gate on it.

---

## Files

| File | Role |
|---|---|
| `TouchEngine.swift` | Today: the whole engine + `MultiTouchSurface` bridge + `KeyGridTouchView`. Target: split InputCore / GestureCore / RenderDriver (see plan) |
| `KeyView.swift` | Reads `KeyPressState`; renders surface/bloom/bulge. Pure consumer of RenderDriver |
| `KeyboardCanvas.swift` | Hosts `MultiTouchSurface`, publishes key frames (`KeyFrameKey`), wires host callbacks |
| `KeyboardViewController.swift` | The document side: commit closures (`onInsert`/`onBackspace`/…), local text mirror, debounced autocorrect |

---

## Implementation plan (staged, each stage compile-green)

- [x] **Stage 1 — Commit inversion.** Letters commit synchronously in
  `touchDown`; space stays deferred with the rationale above. *This is the
  review-killer; the rest is structure around it.*
- [x] **Stage 2 — Rename + reframe.** `KeyTouchRouter` → `TouchEngine`
  (`KeyTouchRouter.swift` → `TouchEngine.swift`). No behavior change; the file's
  `// MARK:` sections are tagged `InputCore` / `GestureCore` / `RenderDriver` so
  the boundaries are explicit before Stage 3-4 enforce them.
- [x] **Stage 3 — Extract RenderDriver.** Press-state writes (`pressDown` /
  `release` / `clearPress` / `recomputePressed` / linger / `neighborTick` /
  `bulge` / neighbour map) now live in a `RenderDriver` the engine owns. The
  engine pushes into it one-way; it's never read back to decide input. `KeyView`
  is unchanged — the engine forwards `state(for:)` / `pressed`. Engine keeps
  `frames` for hit-test and pushes a copy to the driver on layout change.
- [x] **Stage 4 — GestureCore (method extraction).** `touchMoved`'s branching
  giant is split into a small priority dispatcher calling per-gesture handlers —
  `deleteWordMove` / `dragUpMove` (each returns `Bool`: did it consume the move?)
  and `spaceCursorMove`. Same state, same order, same behavior — pure extraction.
  Deliberately *not* full struct-ification with separate published state: the
  gesture render state (`spaceDragX`, `accentKeyID`, `deleteTick`, …) is read
  directly by `KeyView`, so ripping it into structs is high-churn, regression-
  prone on finicky timing, and buys zero behavior. The `// MARK: GestureCore`
  sections + the handler split give the boundary without that risk.
- [x] **Stage 5 — Instrument.** `MotionDiagnostics` signposts (DEBUG-only, zero
  Release cost) on the commit path: `commit.char` interval around the synchronous
  letter commit (the text-first regression guard — a widening interval means
  someone re-stalled the touch event), `touch.down` event per real key landing
  (align keystrokes against frame drops), and `commit.space` interval around the
  deferred space commit (confirm its `UITextChecker` lands in the quiet window,
  not on the release spring). Profile by attaching Instruments' Points of
  Interest to the `ClinkKeyboard` process while typing. The extension can't use
  MetricKit (see `MotionMetrics`), so signposts are the in-extension tool.

Verification: device-only (no simulator builds on this machine). Each stage is
parse-checked (`swiftc -frontend -parse`) and then run on `lambda-ios` via
`make device`. Behavior stages (1, 3, 4) need a fast-typing pass on device to
confirm no dropped keys and no animation regression.

---

## Gotchas

- **Never let InputCore depend on RenderDriver.** The whole point is that the
  commit path can't be starved by animation. If a commit needs to read a spring
  value, the design is wrong.
- **Keep per-key `KeyPressState`.** Re-introducing a shared pressed-keys set
  re-renders the grid and drops the press-bloom frame (measured).
- **Space stays deferred.** Don't "consistency-fix" it to synchronous — that
  re-hitches the release spring (see the commit table).
- **Letters stay synchronous.** Don't re-defer them for any animation-ordering
  reason; that reintroduces the queue contention this whole engine exists to
  remove.

---

## See also

- [03-touch-and-input](03-touch-and-input.md) — hit-testing, adaptive hitboxes, gestures
- [04-prediction](04-prediction.md) — autocorrect / suggestion debounce (the off-hot-path work)
- [12-motion](12-motion.md) — press bloom springs the RenderDriver feeds
