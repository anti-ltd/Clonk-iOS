# Extension host

## What it is

`KeyboardViewController` — the keyboard extension's principal class. Hosts
`KeyboardCanvas` / `EmojiCanvas` inside `UIInputViewController`, wires document
proxy callbacks, runs the suggestion engine, plays sound, captures clipboard,
executes PyMini scripts, and reloads on cross-process settings changes.

Everything ClinkKit *can't* do (touch the host document, read pasteboard, report
Full Access) happens here.

---

## Where it sits

```
UIInputViewController (system)
    └── KeyboardViewController
            ├── ClinkInputView (UIInputViewAudioFeedback)
            ├── UIHostingController<AnyView>
            │       └── KeyboardCanvas | EmojiCanvas
            ├── SharedStore (read settings, report Full Access)
            ├── SuggestionEngine (debounced, quiet-gated)
            ├── ClipboardManager / NotepadManager / ExtensionManager / PanelManager
            ├── SoundPlayer
            ├── KeyboardController (plane/shift/emoji)
            └── KeyboardLiveState (suggestions, active panel)
```

---

## Files

| File | Role |
|---|---|
| `ClinkKeyboard/KeyboardViewController.swift` | Entire extension — ~1100 lines |

That's it for the extension target. All rendering logic lives in ClinkKit.

---

## How it works

### Lifecycle

| Phase | What happens |
|---|---|
| `loadView` | Creates `ClinkInputView`; seeds intrinsic height before first system measurement |
| `viewDidLoad` | Loads settings; builds hosting controller; registers Darwin observer |
| `viewWillAppear` | Fresh settings read; reports Full Access; re-seeds text mirror |
| `viewDidAppear` | Clears `isSettling` once frame reaches target height |
| `deinit` | Drops Darwin notification token |

`@objc(KeyboardViewController)` — bare name in Info.plist's
`NSExtensionPrincipalClass` resolves without module prefix.

### Document callbacks

Canvas → controller wiring:

| Callback | Controller action |
|---|---|
| `onInsert` | `insertMirrored(_:)` → proxy + mirror update + smart punctuation |
| `onBackspace` | `backspaceMirrored()` → proxy + mirror; may revert autocorrect |
| `onAnyTap` | `sound.play(settings:hasFullAccess:)` |
| `onNextKeyboard` | `advanceToNextInputMode()` |
| `onClipboardInsert` | insert text; close panel; schedule suggestions |
| `onNotepadInsert` | same pattern |
| `onExtensionRun` | PyMini `PyEngine.run`; insert output |
| Panel callbacks | `PanelRuntime` state mutations |

**Always use `insertMirrored` / `backspaceMirrored`**, not raw `textDocumentProxy` —
keeps autocomplete mirror in sync.

### Text mirror

`recentTail` holds last 32 chars before cursor. Updated synchronously on our
edits; re-seeded from proxy on focus change or external edit.

`isApplyingEdit` brackets our mutations so `textDidChange` callbacks don't
mistake them for external edits and invalidate the mirror.

### Suggestion scheduling

```
key down → lastKeyActivity = now
         → scheduleSuggestionUpdate (cancel previous work item)
         → dispatch after debounce
         → quietGatedCompute (wait until touch-free for 0.45s)
         → engine.compute(…) → live.suggestions / live.autocorrection
```

Space-press autocorrect uses mirror synchronously — doesn't wait for debounce.

### Clipboard capture

On insert (when clipboard enabled + Full Access), reads pasteboard and appends
to `ClipboardManager` if content changed. Gated on Full Access — iOS blocks
pasteboard reads without it.

### Settings reload

Darwin notification from `SharedStore.observeChanges` → reload settings →
reconfigure engine languages/layout/adaptation → SwiftUI re-render.

Separate observers on `ExtensionManager` and `PanelManager` for script changes.

### Height & appearance settling

System animates extension view from ~full-screen down to target height on every
appearance. Controller hides content during descent (`isSettling`), reveals when
frame settles. Content pinned bottom-aligned at fixed height — keys don't track
the resize animation.

`InputViewHeight` tames encapsulated layout constraint.

### Extension script execution

`ExtensionsPanel` tap → controller gathers input per `ExtInputSource` →
`PyEngine.run(source:input:)` → insert output or show error.

Current-word input deletes the typed word first, then inserts result.

---

## Gotchas

- **Only place with `textDocumentProxy`.** ClinkKit never imports UIKit document APIs.

- **`insertMirrored` is the choke point** for all document writes. Bypassing it
  breaks suggestions and autocorrect revert.

- **`quietGatedCompute` exists because checker work is @MainActor** and takes
  tens of ms — running it during key release spring caused visible jank.

- **Full Access reported on every `viewWillAppear`** — app UI treats it as hint
  until keyboard has run at least once.

- **Fresh VC per appearance** — `isSettling` defaults true each time; settling
  hide/show re-arms automatically.

- **WeakBox for Darwin callback** — notification closure is `@Sendable`; hops
  back to MainActor controller via weak box.

---

## Read order

1. `KeyboardViewController.swift` — read top doc comment and property block first
2. Search `insertMirrored` — follow the insert path
3. Search `scheduleSuggestionUpdate` — follow suggestion path
4. Search `rebuildHosting` — see canvas construction and callback wiring
5. [02-keyboard-core](02-keyboard-core.md) — what the hosted canvas does

---

## See also

- [00-overview](00-overview.md) — process topology
- [04-prediction](04-prediction.md) — engine details
- [06-sound](06-sound.md) — audio feedback wiring
- [08-pymini](08-pymini.md) — script execution
- [01-settings-and-storage](01-settings-and-storage.md) — what gets loaded
