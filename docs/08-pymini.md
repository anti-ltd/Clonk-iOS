# PyMini interpreter

## What it is

A dependency-free Python-subset interpreter in Swift. Powers custom actions
(`transform(text)`) and custom panel UI scripts. Exists because embedding CPython
(~15 MB + runtime heap) would blow the keyboard extension's ~50 MB jetsam budget.

Sandboxed by construction: no `import`, no file/network/system access, deterministic
step budget, capped container growth.

---

## Where it sits

```
PyEngine.run(source, input)          ← public facade (actions)
PanelRuntime                         ← panels (initial/view/on_action)
    ↓
PyParser.parse(source) → [Stmt]
    ↓
PyInterpreter.run(program)           ← tree-walking evaluator
    ↓
PyValue                              ← runtime values
```

Pipeline: **Lexer → Parser → AST → Interpreter**

---

## Files

| File | Role |
|---|---|
| `PyMini/PyEngine.swift` | Public facade — `run`, `validate`; `PyRunResult` |
| `PyMini/PyLexer.swift` | Tokenizer; significant indentation; f-string segments |
| `PyMini/PyParser.swift` | Recursive-descent parser → statement list |
| `PyMini/PyAST.swift` | Expression and statement node types |
| `PyMini/PyInterpreter.swift` | Tree-walking evaluator; step counter; sandbox |
| `PyMini/PyValue.swift` | Runtime values (`int`, `float`, `str`, `bool`, `None`, `list`, `dict`); errors; flow control |
| `PyMini/PyProgram.swift` | Warm module — parsed defs callable across renders |

Consumers:

| File | Role |
|---|---|
| `Extensions/ExtensionsPanel.swift` | Runs action scripts on tap |
| `Panels/PanelRuntime.swift` | Runs panel scripts for UI tree |
| `UI/Extensions/ExtensionEditorView.swift` | Validate + run console in app |

---

## How it works

### Action contract (PyEngine)

```python
def transform(text):
    return text.upper()
```

- `text` = action input source (current word, clipboard, field text, or `""`)
- Return value `str()`-ified and inserted
- Return `None` → insert nothing
- `print(...)` → captured in `PyRunResult.log` (in-app console only)

Convenience: top-level `result = …` if no `transform` defined.

### Execution model

1. Parse source to `[Stmt]` — syntax errors return immediately
2. Create `PyInterpreter(maxSteps: 2_000_000)` (default budget)
3. Run top-level statements (defines functions, sets globals)
4. Call `transform(input)` or read `result`
5. Return `PyRunResult(output:error:log:)`

Synchronous, main-thread safe — bounded step count prevents hangs.

### Sandbox surface

**Allowed types:** `int`, `float`, `str`, `bool`, `None`, `list`, `dict`

**Allowed statements:** assign, augmented assign, `if`/`elif`/`else`, `while`,
`for`, `def`, `return`, `break`, `continue`, `pass`

**Allowed operators:** arithmetic, comparisons (incl. chaining), `and`/`or`/`not`,
`in`, unary `+`/`-`, ternary

**f-strings:** `f"{n} words"` (no format specs)

**Builtins:** `len str repr print int float bool abs round min max sum range
sorted reversed list dict enumerate zip ord chr any all type`

**str methods:** `upper lower title strip split replace join startswith endswith
find count …` (see [14-extensions-sdk](14-extensions-sdk.md) for full list)

**Explicitly rejected:** `import`, `class`, `try`, `with`, `lambda`,
comprehensions, decorators, generators, sets

### PyProgram (warm modules)

Panel scripts re-render frequently. `PyProgram` holds parsed function defs so
`PanelRuntime` doesn't re-parse on every state change — only re-evaluates
`view(state)`.

### Error display

`PyError.display` produces user-facing messages shown in the extension UI
(error state on action/panel) and the in-app run console.

---

## Gotchas

- **Step budget is real.** Infinite loops terminate with a runtime error, not a hang.

- **No I/O escape hatches.** The interpreter doesn't expose `open`, `os`, `sys`,
  or any import mechanism. Security is structural, not policy.

- **String/container growth capped** inside interpreter — scripts can't OOM via
  huge concatenations.

- **Validate before save** — `ExtensionEditorView` and `PanelEditorView` call
  `PyEngine.validate` on edit; runtime errors still possible for logic bugs.

- **Same interpreter for actions and panels** but different entry points —
  `PyEngine.run` vs `PanelRuntime`'s multi-function dispatch.

---

## Read order

1. [14-extensions-sdk](14-extensions-sdk.md) — language reference (user-facing)
2. `PyEngine.swift` — entry point, 80 lines
3. `PyLexer.swift` → `PyParser.swift` → `PyAST.swift` — front end
4. `PyInterpreter.swift` — evaluator (largest file)
5. `PyValue.swift` — value operations

---

## See also

- [14-extensions-sdk](14-extensions-sdk.md) — script author guide
- [07-custom-panels](07-custom-panels.md) — panel MVU on top of PyMini
- [10-extension-host](10-extension-host.md) — where scripts run in the extension
