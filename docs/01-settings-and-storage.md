# Settings & storage

## What it is

Everything the app and keyboard agree on lives in `KeyboardSettings` — a single
`Codable` struct persisted as JSON in the App Group. Managers for clipboard,
notepad, extensions, and custom panels own their own JSON files alongside it.
`SharedStore` is the file bridge and change-notification bus.

---

## Where it sits

```
AppModel.settings ──save──▶ SharedStore ──▶ clink-settings.v1.json
                                ▲
KeyboardViewController ──load──┘
                                │
                    Darwin notification (live reload)

ClipboardManager  ──▶ clink-clipboard.v2.json
NotepadManager    ──▶ clink-notepad.v1.json
ExtensionManager  ──▶ clink-extensions.v1.json
PanelManager      ──▶ clink-panels.v1.json
ThemeBackgroundStore ──▶ theme-photos/<id>.jpg
```

---

## Files

| File | Role |
|---|---|
| `KeyboardSettings.swift` | The config blob + all setting enums (`KeyPopupStyle`, `ClipboardStyle`, `NotepadMode`, layout IDs, tuning knobs, etc.) |
| `SharedStore.swift` | Load/save settings; report/observe Full Access; Darwin notify |
| `FeatureFlags.swift` | Launch-arg flags (`--experimental`, `--motion-hud`) — DEBUG tooling |
| `ClipboardManager.swift` | FIFO clipboard history, pin/delete, v1→v2 migration |
| `ClipboardEntry.swift` | One history item + relative date label |
| `NotepadManager.swift` | Scratch buffer + saved notes archive |
| `NotepadNote.swift` | One saved note (`id`, `text`, `createdAt`) |
| `ExtensionManager.swift` | CRUD + reorder for custom PyMini actions |
| `Extensions/ClinkExtension.swift` | One action: name, script, input source, enabled flag |
| `PanelManager.swift` | CRUD for custom PyMini UI panels |
| `Panels/ClinkPanel.swift` | Panel definition: placement, `view(state)` script |
| `ThemeBackgroundStore.swift` | Downscaled JPEG storage for theme photos |

App-side wiring:

| File | Role |
|---|---|
| `AppModel.swift` | Owns `settings`; `didSet` → `store.save()`; theme import/export; enable status |
| `BackupView.swift` | `.clinkconfig` whole-config export/import |

---

## How it works

### KeyboardSettings

One struct, ~100+ fields. Grouped roughly as:

- **Theme** — `themeID`, `customThemes`, match-system-appearance light/dark IDs
- **Layout** — `layoutID`, number row, key geometry, custom keys/rows
- **Typing** — suggestions, autocorrect, languages, smart punctuation, learning
- **Panels** — clipboard/notepad/calculator/emoji/extensions toggles + styles
- **Feel** — springs, hitboxes, cursor mode, swipe typing, haptics
- **Sound** — pack ID, volume, enabled flags

Adding a field requires three edits (see [EXTENDING.md](../EXTENDING.md) §2):

```swift
public var snippetsEnabled: Bool          // property
snippetsEnabled: Bool = false,            // init param with default
snippetsEnabled = try c.decodeIfPresent(Bool.self, forKey: .snippetsEnabled) ?? false
```

`CodingKeys` and `encode(to:)` are synthesized — you only touch property, init, decode.

### SharedStore.save(notify:)

Most writes use `notify: true` (default) so a running keyboard reloads immediately.

Pass `notify: false` for high-frequency, self-originated writes where the writer
already updates its own UI — e.g. recording recent emoji as they're tapped.
A reload mid-burst would cause unnecessary churn.

### Full Access status

Only the extension can read `hasFullAccess`. It writes
`clink-status.v1.json` on launch. The app reads it for the setup screen.

Uses a file, not UserDefaults, because keyboard extensions can't write to App
Group UserDefaults *without* Full Access — which would be circular.

### Manager persistence pattern

All managers follow the same shape:

```swift
@MainActor @Observable final class XManager {
    private var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID)?
            .appendingPathComponent("clink-x.v1.json")
    }
    // load on init, save on mutation
    // UserDefaults.standard fallback when App Group unavailable (unsigned builds)
}
```

Both processes share the same file. Save in the app → keyboard sees it on next read.

### Backup formats

| Extension | Contents |
|---|---|
| `.clink` | Single `Theme` export |
| `.clinkconfig` | Full `KeyboardSettings` JSON |
| `.clinkext` | One `ClinkExtension` |
| `.clinkpanel` | One `ClinkPanel` |

---

## Gotchas

- **`decodeIfPresent ?? default` always.** Plain `try decode` on a new key throws, and the whole settings load fails — user gets factory defaults and loses everything.

- **Enum decode tolerance.** Retired enum cases can poison decode. Use `(try? c.decodeIfPresent(MyEnum.self, …)) ?? .defaultCase`.

- **App Group unavailable on unsigned builds.** Every load/save path has a `UserDefaults.standard` fallback so dev builds without matching provisioning profiles still work (within one process).

- **Orphan theme photos.** When deleting or editing a custom theme, `AppModel.deleteCustomTheme` and `saveCustomTheme` delete orphaned `backgroundImageID` / `keyImageID` files from `ThemeBackgroundStore`.

- **ExtensionManager / PanelManager post their own Darwin notifications** so the keyboard reloads script changes without a settings write.

---

## Read order

1. `SharedStore.swift` — the IPC mechanism and why files not UserDefaults
2. `KeyboardSettings.swift` — skim the struct; you'll reference it constantly
3. `AppModel.swift` — how the app side persists and imports
4. Pick one manager (`ClipboardManager.swift`) as the template for the rest

---

## See also

- [00-overview](00-overview.md) — process topology
- [EXTENDING.md](../EXTENDING.md) §2 — adding settings fields for new panels
- [THEMING.md](../THEMING.md) — theme fields and photo storage
