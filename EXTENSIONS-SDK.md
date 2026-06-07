# Clink Extension SDK

Write your own keyboard actions in Python. An **action** takes some input (the
word you're typing, the clipboard, the text before the cursor, or nothing), runs
a small Python script over it, and inserts whatever the script returns.

Manage actions in the app under **Custom Actions** (sidebar → Customization →
Custom Actions). Enabled actions appear behind the keyboard's action button
(the ⧉ puzzle-piece panel), alongside Clipboard / Notepad / Calculator.

## The script contract

A script must define `transform(text)`:

```python
def transform(text):
    return text.upper()
```

- `text` is the action's **input** (see Input sources below).
- The return value is `str()`-ified and inserted. Return `None` to insert
  nothing.
- For a quick experiment you may instead assign a top-level `result` variable
  instead of defining `transform`.
- `print(...)` writes to the in-app run console only — never to the document.

### Input sources

| Source              | `text` is…                                  |
|---------------------|----------------------------------------------|
| Nothing             | `""` — generate from scratch                  |
| Current word        | the word being typed (it gets replaced)       |
| Clipboard           | the clipboard contents (needs Full Access)    |
| Text before cursor  | everything before the cursor                   |

When the input is **Current word**, the typed word is deleted and replaced with
the output. Other sources insert the output at the cursor.

## Why a custom interpreter (not CPython)

Clink's keyboard runs under iOS's hard keyboard-extension memory budget
(~50 MB; exceed it and the system jetsam-kills the keyboard). Embedding CPython
(~15 MB binary + multi-MB runtime heap) would blow that budget. So actions run on
**PyMini** — a small, dependency-free Python-subset interpreter written in Swift
(`Sources/ClinkKit/PyMini/`). It is:

- **Sandboxed by construction** — no `import`, no file/network/system access. The
  only callable surface is the builtins and container methods below.
- **Bounded** — a deterministic per-step budget stops runaway loops/recursion,
  and container/string growth is capped, so a script can't hang or OOM the
  keyboard.

## Supported language

- **Types:** `int`, `float`, `str`, `bool`, `None`, `list`, `dict`.
- **Operators:** `+ - * / // % **`, comparisons (incl. chaining `a < b < c`),
  `and` / `or` / `not`, `in` / `not in`, unary `+`/`-`, ternary `a if c else b`.
- **Statements:** assignment (incl. tuple-unpack `a, b = …` and chained
  `a = b = …`), augmented assignment (`+= -= *= /=`), `if`/`elif`/`else`,
  `while`, `for … in …`, `def` (default args + keyword args), `return`,
  `break`, `continue`, `pass`.
- **f-strings:** `f"{n} words"` (no format specs).
- Indexing and slicing (`s[i]`, `s[a:b:c]`, negative indices).

**Builtins:** `len str repr print int float bool abs round min max sum range
sorted reversed list dict enumerate zip ord chr any all type`

**str methods:** `upper lower title capitalize swapcase strip lstrip rstrip
replace split rsplit splitlines join startswith endswith find count zfill ljust
rjust isdigit isalpha isalnum isspace isupper islower removeprefix removesuffix
format`

**list methods:** `append extend pop insert remove index count sort reverse
clear copy`

**dict methods:** `keys values items get pop setdefault update clear copy`

Not supported (fail with a clear message): `import`, `class`, `try`, `with`,
`lambda`, comprehensions, decorators, generators, sets.

## Custom panels

An **action** is one-shot text-in/text-out. A **panel** is a full custom UI
rendered inside the keyboard (a calculator, snippet board, picker…). Manage them
under **Custom Panels**; enabled panels appear behind the keyboard's panels
button (▦).

A panel script defines `view(state)` (and optionally `initial()`), returning a UI
tree built from helper functions. It's an Elm/MVU loop: a button either `insert`s
text into the document or `set`s new state (which re-renders `view`).

```python
def initial():
    return {"count": 0}

def view(state):
    return vstack([
        text("Count: " + str(state["count"]), size=22, weight="bold"),
        hstack([
            button("-", set={"count": state["count"] - 1}),
            button("+", set={"count": state["count"] + 1}),
        ]),
        button("Insert", insert=str(state["count"]), style="primary"),
    ])
```

- **State** holds only scalars (str/number/bool). It's passed into `view(state)`
  on every render; transitions are computed at view-build time (e.g.
  `set={"cur": state["cur"] + d}`).
- The interpreter stays warm across renders, so re-rendering each tap is cheap and
  step-budget bounded.

### UI builders

| Builder | Notes |
|---------|-------|
| `text(s, size=17, weight="regular", color="")` | `weight`: regular/medium/semibold/bold/heavy/light/thin. `color`: name or `#RRGGBB`. |
| `button(label, insert="", set=None, style="plain")` | `style`: `plain` or `primary` (accent-filled). |
| `field(key, placeholder="", value="")` | text input bound to `state[key]`. |
| `vstack(children, spacing=6)` / `hstack(children, spacing=6)` | stacks. |
| `grid(children, columns=4, spacing=6)` | flowed grid. |
| `spacer()` / `divider()` | layout. |

Panels are solid-rendered (no per-cell glass, per the keyboard memory budget) and
share as `.clinkpanel` files.

## Sharing

Each action exports as a `.clinkext` file (JSON) — share it via the editor's
**Share action** button (AirDrop / Messages / Files). Import via **Custom
Actions → Import action…**. Imported actions get fresh ids so they never collide.

## Architecture

| File | Role |
|------|------|
| `Sources/ClinkKit/PyMini/PyValue.swift` | runtime value model + helpers |
| `Sources/ClinkKit/PyMini/PyAST.swift` | expression / statement AST |
| `Sources/ClinkKit/PyMini/PyLexer.swift` | indentation-aware tokenizer + f-strings |
| `Sources/ClinkKit/PyMini/PyParser.swift` | recursive-descent parser |
| `Sources/ClinkKit/PyMini/PyInterpreter.swift` | tree-walking evaluator + builtins/methods |
| `Sources/ClinkKit/PyMini/PyEngine.swift` | `PyEngine.run` / `.validate` facade + script contract |
| `Sources/ClinkKit/Extensions/ClinkExtension.swift` | the Codable action model + seed samples |
| `Sources/ClinkKit/Extensions/ExtensionManager.swift` | App Group store (mirrors `NotepadManager`) |
| `Sources/ClinkKit/Extensions/ExtensionsPanel.swift` | the keyboard panel listing actions |
| `Sources/Clink/UI/Extensions/ExtensionsView.swift` | manage list (new/import/reorder/enable/delete) |
| `Sources/Clink/UI/Extensions/ExtensionEditorView.swift` | in-app code editor + live run console |

Execution seam in the keyboard: `KeyboardCanvas` renders `ExtensionsPanel`; a tap
calls `onRunExtension`, handled by `KeyboardViewController.runExtension(_:)`, which
gathers the input, runs `PyEngine`, and inserts via the existing
`insertMirrored` path.
