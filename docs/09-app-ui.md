# Container app UI

## What it is

The Clink settings app: collapsible sidebar navigation, live keyboard preview on
most screens, and one SwiftUI view per settings area. All mutations go through
`AppModel.settings`, which persists to the App Group on every change.

Built on [iUX-ios](https://github.com/anti-ltd/iUX-ios) for shared design
components (`CardSection`, `ToggleRow`, `NavRow`, etc.).

---

## Where it sits

```
ClinkApp
    └── RootView (sidebar shell)
            ├── SidebarState (@Environment)
            ├── AppModel (@Environment)
            └── DetailHost → per-destination NavigationStack
                    └── [settings views with KeyboardPreview]
```

---

## Files

### Shell & state

| File | Role |
|---|---|
| `ClinkApp.swift` | `@main`; URL handler for `.clink` / `.clinkconfig` imports; SHOWCASE/AppStage routing |
| `AppModel.swift` | Settings owner; enable status; theme/config import; manager instances |
| `AppStage.swift` | DEBUG `--appstage <slug>` marketing screenshot routing |
| `UI/RootView.swift` | Collapsible sidebar; destination enum; home page sections |
| `UI/ThemedSheet.swift` | Bottom sheet with drag-to-expand |
| `UI/LogoMark.swift` | Vector logo; corner radius tracks key roundness setting |
| `UI/TuningPresets.swift` | `PresetChips`, `TunedSection`, named tuning preset catalogs |
| `MotionHUD.swift` | DEBUG FPS/hitch overlay (`--motion-hud`) |
| `MotionMetrics.swift` | DEBUG MetricKit animation hitch subscriber |

### Preview infrastructure

| File | Role |
|---|---|
| `UI/KeyboardPreview.swift` | `KeyboardPreview`, `PinnedPreviewLayout`, `TabbedPreviewLayout`, themed picker chrome |

Most settings screens embed `KeyboardPreview` so changes reflect live.

### Theme & appearance

| File | Role |
|---|---|
| `UI/ThemeEditorView.swift` | Preset grid, custom theme CRUD, `.clink` export/import |
| `UI/ThemeBuilderView.swift` | Custom theme editor + `GradientEditorView` |
| `UI/AnimationView.swift` | Key/space/popup spring tuning |
| `UI/PopupsView.swift` | Popup toggle, style, glass option |
| `UI/KeysView.swift` | Key size, shape, padding |
| `UI/OverlaysView.swift` | Debug overlay toggles |

### Layout & keys

| File | Role |
|---|---|
| `UI/LayoutView.swift` | Layout picker, rows, custom keys tabs |
| `UI/LayoutPickerView.swift` | Row toggles with pinned preview |
| `UI/CustomKeysView.swift` | Custom key builder + editor body |
| `UI/GesturesView.swift` | Swipe typing, backspace repeat |
| `UI/HitboxView.swift` | Static + adaptive hitbox tuning |
| `UI/ResponseView.swift` | Hold/slide timing thresholds |
| `UI/CursorView.swift` | Space-bar cursor mode and feel |

### Typing & language

| File | Role |
|---|---|
| `UI/TypingView.swift` | Smart text master settings |
| `UI/SuggestionsView.swift` | Suggestion bar + autocorrect |
| `UI/AutomationView.swift` | Auto-cap, punctuation, symbol returns |
| `UI/AdaptationView.swift` | On-device learning |
| `UI/LocalizationView.swift` | Checker language picker |
| `UI/ArtificialIntelligenceView.swift` | Apple Intelligence opt-in |

### Panels & extensions

| File | Role |
|---|---|
| `UI/ClipboardHistoryView.swift` | Clipboard settings + history browser |
| `UI/NotepadView.swift` | Notepad settings + note editors |
| `UI/CalculatorSettingsView.swift` | Calculator panel toggle |
| `UI/EmojiSettingsView.swift` | Emoji preferences |
| `UI/Panels/PanelsView.swift` | Custom panel list |
| `UI/Panels/PanelEditorView.swift` | Panel script editor + preview |
| `UI/Extensions/ExtensionsView.swift` | Custom action list |
| `UI/Extensions/ExtensionEditorView.swift` | Action script editor + run console |

### Sound, backup, onboarding

| File | Role |
|---|---|
| `UI/SoundsView.swift` | Sound toggle, volume, packs |
| `UI/SoundPickerView.swift` | Combined sound + haptics |
| `UI/HapticsView.swift` | Haptic toggle + style |
| `UI/PerformanceView.swift` | Responsiveness + compute budget |
| `UI/BackupView.swift` | `.clinkconfig` export/import, reset |
| `UI/AdvancedSettingsView.swift` | Legacy touch/spring tuning tab layout |
| `UI/EnableFlowView.swift` | Keyboard enable + Full Access guide |

### DEBUG / marketing

| File | Role |
|---|---|
| `UI/ShowcaseView.swift` | `SHOWCASE` build — automated typing simulator |
| `UI/StagedHeroView.swift` | AppStage hero marketing shot |

---

## How it works

### Navigation model

`RootView` uses a collapsible sidebar (overlay from left edge) rather than a
fixed split view. `SidebarState` is `@Environment`-injected so any child can
open/close the sidebar or trigger root-level sheets.

Destinations are `SidebarDestination` enum cases. Home page groups settings into
cards (Style, Typing, Feel, Setup). Each `NavRow` pushes a detail view inside
a per-destination `NavigationStack`.

### Settings binding pattern

```swift
@Environment(AppModel.self) private var model
@Bindable var model = model

ToggleRow("Feature", isOn: $model.settings.someFlag)
```

`AppModel.settings.didSet` → `SharedStore.save()` → keyboard picks up change.

Managers (clipboard, notepad, extensions, panels) are `let` properties on
`AppModel` — shared instances, not recreated per view.

### Live preview pattern

```swift
PinnedPreviewLayout {
    KeyboardPreview(settings: model.settings)
} content: {
    // settings controls below or beside preview
}
```

Preview uses the real `KeyboardCanvas` with stub document callbacks. Theme
resolved from `model.settings.resolvedTheme(for: colorScheme)`.

### Theme page background

Settings pages can adopt the active keyboard theme as page background via
`.themePageBackground()` and `@Environment(\.resolvedKeyboardTheme)`.

### Onboarding flow

`EnableFlowView` deep-links to iOS Settings for keyboard enable + Full Access.
`AppModel.refreshStatus()` reads `AppleKeyboards` UserDefaults and
`SharedStore.lastKnownFullAccess` on foreground.

`LocalizationView` shown early — sets checker languages before user types.

### URL import

`ClinkApp.onOpenURL` handles:

- `.clink` → stage theme import (`pendingThemeImport`)
- `.clinkconfig` → stage config import (`pendingConfigImport`)

User confirms in a sheet before `AppModel` commits.

---

## Gotchas

- **Advanced fine-tune controls go in a `FineTune { }` block.** It renders a
  collapsed "Fine-tune" disclosure only in Advanced mode and vanishes in Simple
  mode (Home's Simple/Advanced toggle → `settings.advancedSettings`, default
  Simple). Never hand-roll a `DisclosureGroup("Fine-tune")` — use `FineTune`
  (in `TuningPresets.swift`) so the global Simple-mode hide applies. It can also
  gate: `FineTune(enabledWhen:reason:)`.

- **Don't hide settings behind an off feature — disable them with a reason.**
  When a control only does something once a feature toggle is on, show it
  *disabled + dimmed* with a one-line reason, not hidden, so the page never goes
  empty and users see what's on offer. Use `GatedCard(title, enabled:, reason:)`
  for a whole card or `.gated(_ enabled:, reason:)` for an inline block (both in
  `TuningPresets.swift`). Applies to top-level feature gates; tiny numeric
  refinements under an adjacent sub-toggle may stay hidden.

- **AppStage seeds theme in `AppModel.init`** without triggering `didSet` — DEBUG
  capture shots get curated themes that don't persist.

- **`SidebarState.navigate` callback** wired in `RootView` — onboarding "next step"
  buttons jump between destinations without manual sidebar navigation.

- **`tracksNavigationDepth()`** hides sidebar button when a pushed detail view
  shows its own back button.

- **Sheets from sidebar** (`showExtensionPicker`, `showBackupSheet`) present at
  root level so they render full-width above the sidebar scrim.

- **iUX-ios is a local SPM dep** — must be cloned as sibling `../iUX-ios`.

---

## Read order

1. `ClinkApp.swift` — entry and import handling
2. `AppModel.swift` — state ownership
3. `RootView.swift` — navigation structure (large file — skim `SidebarDestination` first)
4. `KeyboardPreview.swift` — preview embedding pattern
5. Pick any settings view similar to what you're building

---

## See also

- [01-settings-and-storage](01-settings-and-storage.md) — what AppModel persists
- [02-keyboard-core](02-keyboard-core.md) — what KeyboardPreview renders
- [11-theming](11-theming.md) — theme editor specifics
