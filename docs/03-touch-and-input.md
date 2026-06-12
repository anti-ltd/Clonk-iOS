# Touch & input

## What it is

How finger events become key presses. SwiftUI's per-view `DragGesture` can't
track two simultaneous touches across sibling keys — fast typists overlap keys
and the second press gets dropped. Clink routes all touches through one UIKit
view with `isMultipleTouchEnabled`, then maps coordinates to key IDs.

Also covers adaptive hitboxes (next-letter target sizing), long-press accent
variants, and swipe/glide typing geometry.

---

## Where it sits

```
MultiTouchSurface (UIKit)
    └── KeyTouchRouter
            ├── KeyPressState (per key — @Observable)
            ├── KeyView (reads its own state)
            ├── AdaptiveHitbox (sizes targets from lexicon)
            └── SwipeDecoder (finger trace → words)
```

---

## Files

| File | Role |
|---|---|
| `KeyTouchRouter.swift` | Multitouch router; `MultiTouchSurface` UIViewRepresentable; bar hitboxes; swipe trail; backspace repeat |
| `KeyView.swift` | Reads `KeyPressState` for pressed/bloom/bulge; space-bar trackpad |
| `AdaptiveHitbox.swift` | Next-letter hit target sizing from letter bigram model |
| `AccentMap.swift` | Long-press diacritic variant tables (Latin scripts) |
| `AccentPicker.swift` | Accent variant bar during letter long-press |
| `SwipeDecoder.swift` | Glide-typing geometry — finger trace → ranked words |
| `SwipeLexicon.swift` | Bundled frequency-ordered English word list (swipe fallback) |
| `TrackpadPanel.swift` | Visual overlay during space-bar trackpad cursor mode |

App tuning screens:

| File | Role |
|---|---|
| `HitboxView.swift` | Static + adaptive hitbox sliders |
| `GesturesView.swift` | Swipe typing + backspace repeat settings |
| `ResponseView.swift` | Hold/slide timing thresholds |
| `CursorView.swift` | Space-bar cursor mode (slide / trackpad / combined) |
| `OverlaysView.swift` | Debug hitbox outline toggle |

---

## How it works

### Why UIKit for touches

From the doc comment in `KeyTouchRouter.swift`:

> SwiftUI's gesture system doesn't reliably track two simultaneous touches across
> sibling views — so when you type *fast* and press the next key before lifting
> the last, the second press is dropped or arrives late.

`MultiTouchSurface` is a single `UIView` covering the key grid. Each `UITouch`
binds to the key it lands on independently.

### Per-key press semantics

| Key type | Commit timing |
|---|---|
| Character keys | Touch-down (instant) |
| Function keys (shift, 123, return) | Touch-up |
| Backspace | Touch-down + hold-to-repeat |
| Space | Tap, or drag for cursor (mode-dependent) |

### KeyPressState

Each key gets its own `@Observable` instance. `KeyView` reads only its own —
a press invalidates one view, not the grid.

Important fields:

- `isPressed` — held or lingering after release
- `tapTick` — bumped every touch-down; drives tap-flash even when re-pressing during linger
- `neighborTick` — glass only; wakes adjacent keys for liquid merge
- `bulge` — swipe-ripple swell, 0…1

The old shared `Set<String>` of pressed keys re-rendered all ~35 keys several
times per keystroke. On glass that dropped the frame showing the press bloom.

### Adaptive hitboxes

`AdaptiveHitbox` reads the compiled `.clex` lexicon's letter-bigram matrix to
widen the touch target toward likely next letters. "Hel" → `l` gets a bigger
target than `z`. Tunable in settings; can be disabled.

Runs synchronously on main — lexicon lookups are mmap point reads, cheap enough
for the hot path.

### Accent long-press

Hold on a letter key → `AccentMap` variants → `AccentPicker` bar. Release on
variant inserts it; release elsewhere cancels.

### Swipe typing

Finger down on first key → sample trail on move → `SwipeDecoder` matches
geometry against vocabulary → ranked candidates fed to `SuggestionEngine`.

Vocabulary prebuilt in `SuggestionEngine.prebuildSwipeVocabulary()` when
language/layout/adaptation changes. Falls back to `SwipeLexicon` bundled list.

### Space-bar cursor

Three modes in settings:

| Mode | Behaviour |
|---|---|
| Slide | Horizontal drag moves cursor by character |
| Trackpad | Two-finger-style trackpad overlay (`TrackpadPanel`) |
| Combined | Both |

Activation delay, scroll sensitivity, line stride all in `KeyboardSettings`.

---

## Gotchas

- **Never re-introduce a shared pressed-keys set.** The per-key observable pattern
  exists because of measured frame drops on device.

- **Glass keys need `neighborTick`.** `GlassEffectContainer` merge only refreshes
  when views on both sides of a blend re-evaluate.

- **`tapTick` exists because `isPressed` can't re-fire bloom on double-tap same key**
  during the linger window ("tell" → second `l` felt dropped).

- **Swipe trail writes `bulge` only when value moved** — avoids re-rendering the whole grid per sample.

- **Bar hitboxes** (suggestion row, panel icon) use separate preference keys
  (`BarHitboxKey`) collected by the router for panel picker drag-hit-testing.

---

## Read order

1. `KeyTouchRouter.swift` — doc comment explains the why; then `MultiTouchSurface`
2. `KeyView.swift` — how press state becomes visuals
3. `AdaptiveHitbox.swift` — if you care about target sizing
4. `SwipeDecoder.swift` — if you care about glide typing

---

## See also

- [02-keyboard-core](02-keyboard-core.md) — canvas composition
- [04-prediction](04-prediction.md) — swipe candidates in suggestion engine
- [MOTION.md](../MOTION.md) — press bloom animation patterns
