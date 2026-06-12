# Custom panels (PyMini UI)

## What it is

User-authored keyboard panels defined in a Python-subset scripting language.
Scripts describe a small UI tree (`view(state)`) that renders as native SwiftUI
via `CustomPanelView`. State mutations round-trip through `PanelRuntime`.

Distinct from **custom actions** ([EXTENSIONS-SDK.md](../EXTENSIONS-SDK.md)) —
actions run `transform(text)` and insert a result; panels render interactive UI.

---

## Where it sits

```
PanelManager (App Group JSON)
    ↓
KeyboardCanvas → CustomPanelsContainer
    ↓
PanelRuntime.runView(state, script) → PanelValue tree
    ↓
CustomPanelView (native SwiftUI renderer)
```

---

## Files

| File | Role |
|---|---|
| `Panels/ClinkPanel.swift` | Codable panel: id, name, placement, `viewScript`, enabled |
| `Panels/PanelManager.swift` | Observable store; CRUD; Darwin notification on save |
| `Panels/PanelRuntime.swift` | MVU bridge — `initial()`, `view(state)`, `set`/`insert` callbacks |
| `Panels/CustomPanelView.swift` | Renders `PanelValue` node tree; `CustomPanelsContainer` wrapper |

App:

| File | Role |
|---|---|
| `UI/Panels/PanelsView.swift` | Panel list, enable/disable, reorder |
| `UI/Panels/PanelEditorView.swift` | Script editor + live preview |

---

## How it works

### MVU pattern

Each panel script defines:

```python
def initial():
    return {"count": 0}

def view(state):
    return ["column", [
        ["text", f"Count: {state['count']}"],
        ["button", "Increment", "inc"]
    ]]

def on_action(action, state):
    if action == "inc":
        state["count"] = state["count"] + 1
    return state
```

`PanelRuntime` parses with PyMini, calls `initial()` once, re-runs `view(state)`
on each state change, routes button taps through `on_action`.

### PanelValue node tree

Scripts return nested lists tagged by node type:

| Tag | Renders as |
|---|---|
| `text` | `Text` |
| `button` | tappable button; action ID passed to `on_action` |
| `column` / `row` | `VStack` / `HStack` |
| `scroll` | `ScrollView` |
| `textfield` | display-only label (no real text input in extension) |
| `spacer` | flexible space |

`CustomPanelView` walks the tree recursively. Unknown tags render nothing.

### Placement

`ClinkPanel.placement` determines where the panel appears:

- `.overlay` — full keyboard replacement (like calculator)
- `.bar` — inline strip above keys

Enabled panels join `enabledPanels` in `KeyboardCanvas` alongside built-in ones.

### Warm modules

`PyProgram` caches parsed AST across renders so panel scripts aren't re-parsed
every frame. See [08-pymini](08-pymini.md).

### Persistence

`clink-panels.v1.json` in App Group. Save posts Darwin notification —
keyboard reloads panel list without a full settings write.

---

## Gotchas

- **No real text input in extension panels.** `textfield` nodes are display-only.
  Route keyboard keys into state if you need compose (notepad pattern).

- **Same glass rule as built-in panels** — no per-cell `glassEffect`. One
  container material layer.

- **Step budget applies.** Runaway loops in panel scripts hit PyMini's step limit
  and show an error state, not a hang.

- **Panel scripts share PyMini sandbox** with custom actions — no imports, no I/O.

---

## Read order

1. [EXTENSIONS-SDK.md](../EXTENSIONS-SDK.md) — PyMini language surface (shared)
2. `PanelRuntime.swift` — MVU bridge and callback wiring
3. `CustomPanelView.swift` — node → SwiftUI mapping
4. `PanelEditorView.swift` — how the app previews panels

---

## See also

- [08-pymini](08-pymini.md) — interpreter internals
- [EXTENDING.md](../EXTENDING.md) — built-in panels (different system, similar render rules)
- [EXTENSIONS-SDK.md](../EXTENSIONS-SDK.md) — custom actions (transform, not UI)
