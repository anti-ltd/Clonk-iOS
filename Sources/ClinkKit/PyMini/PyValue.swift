/**
 PyMini — a small, sandboxed Python-subset interpreter that powers user-authored
 Clink extension actions.

 Why a hand-rolled interpreter instead of embedding CPython: the keyboard
 extension runs under a hard ~50 MB jetsam budget (the same constraint that makes
 per-cell glass crash it). Embedding CPython (~15 MB binary + a multi-MB runtime
 heap) would blow that budget. PyMini is a few hundred KB of Swift, has no binary
 dependencies, and is sandboxed *by construction*: there is no `import`, no file,
 network, or system access — only the builtins defined in `PyInterpreter`. A
 deterministic per-step budget (not a wall clock) bounds runaway scripts.

 `PyValue` is the runtime value model. Lists and dicts are reference types
 (`PyList` / `PyDict`) so Python's mutation semantics (`x.append(...)`) work.
 

 Module: pymini · Target: ClinkKit
 Learn: docs/08-pymini.md
 */
import Foundation

/// A runtime value in the PyMini interpreter.
indirect enum PyValue {
    case none
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case list(PyList)
    case dict(PyDict)
    case function(PyFunction)
    /// A named builtin (e.g. `len`, `str.upper`) dispatched in the interpreter.
    case builtin(String)
}

/// Reference-typed list box — mutations (`append`, subscript assign) alias like Python.
final class PyList {
    var items: [PyValue]
    init(_ items: [PyValue] = []) { self.items = items }
}

/// Reference-typed, insertion-ordered dict box. Keys must be hashable scalars.
final class PyDict {
    private(set) var keys: [PyHashable] = []
    private var map: [PyHashable: PyValue] = [:]

    init() {}
    init(_ pairs: [(PyHashable, PyValue)]) { for (k, v) in pairs { self[k] = v } }

    var count: Int { keys.count }

    subscript(_ key: PyHashable) -> PyValue? {
        get { map[key] }
        set {
            if let newValue {
                if map[key] == nil { keys.append(key) }
                map[key] = newValue
            } else {
                map[key] = nil
                keys.removeAll { $0 == key }
            }
        }
    }

    var orderedPairs: [(PyHashable, PyValue)] { keys.map { ($0, map[$0]!) } }
}

/// The hashable subset of values usable as dict keys (list/dict/function are rejected).
enum PyHashable: Hashable {
    case none
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    var value: PyValue {
        switch self {
        case .none:          return .none
        case .bool(let b):   return .bool(b)
        case .int(let i):    return .int(i)
        case .double(let d): return .double(d)
        case .string(let s): return .string(s)
        }
    }

    init?(_ v: PyValue) {
        switch v {
        case .none:          self = .none
        case .bool(let b):   self = .bool(b)
        case .int(let i):    self = .int(i)
        case .double(let d): self = .double(d)
        case .string(let s): self = .string(s)
        default:             return nil   // unhashable
        }
    }
}

/// A user-defined function (`def`). Captures the environment it was defined in.
final class PyFunction {
    let name: String
    let params: [Param]
    let body: [Stmt]
    let closure: PyEnv

    struct Param {
        let name: String
        /// AST default expression, evaluated in the closure at call time when omitted.
        let defaultValue: Expr?
    }

    init(name: String, params: [Param], body: [Stmt], closure: PyEnv) {
        self.name = name
        self.params = params
        self.body = body
        self.closure = closure
    }
}

// MARK: - Errors

/// A Python-style error surfaced to the user (syntax or runtime). `line` is
/// 1-based when known.
struct PyError: Error {
    let message: String
    var line: Int?

    init(_ message: String, line: Int? = nil) {
        self.message = message
        self.line = line
    }

    /// Human-facing one-liner, e.g. `Line 3: name 'foo' is not defined`.
    var display: String {
        if let line { return "Line \(line): \(message)" }
        return message
    }
}

/// Non-error control-flow signals, thrown and caught inside the evaluator.
enum PyFlow: Error {
    case breakLoop
    case continueLoop
    case returnValue(PyValue)
}

// MARK: - Value helpers

extension PyValue {
    /// Python type name, for error messages and `type()`-ish reporting.
    var typeName: String {
        switch self {
        case .none:     return "NoneType"
        case .bool:     return "bool"
        case .int:      return "int"
        case .double:   return "float"
        case .string:   return "str"
        case .list:     return "list"
        case .dict:     return "dict"
        case .function, .builtin: return "function"
        }
    }

    /// Python truthiness.
    var isTruthy: Bool {
        switch self {
        case .none:            return false
        case .bool(let b):     return b
        case .int(let i):      return i != 0
        case .double(let d):   return d != 0
        case .string(let s):   return !s.isEmpty
        case .list(let l):     return !l.items.isEmpty
        case .dict(let d):     return d.count != 0
        case .function, .builtin: return true
        }
    }

    /// Numeric value as Double, or nil when not a number. `bool` counts (True==1).
    var asDouble: Double? {
        switch self {
        case .bool(let b):   return b ? 1 : 0
        case .int(let i):    return Double(i)
        case .double(let d): return d
        default:             return nil
        }
    }

    /// Integer value when this is an int or bool (not a float), else nil.
    var asInt: Int? {
        switch self {
        case .bool(let b): return b ? 1 : 0
        case .int(let i):  return i
        default:           return nil
        }
    }
}

/// `str(value)` — the human display form.
func pyStr(_ v: PyValue) -> String {
    switch v {
    case .none:          return "None"
    case .bool(let b):   return b ? "True" : "False"
    case .int(let i):    return String(i)
    case .double(let d): return formatDouble(d)
    case .string(let s): return s
    case .list, .dict:   return pyRepr(v)
    case .function(let f): return "<function \(f.name)>"
    case .builtin(let n):  return "<builtin \(n)>"
    }
}

/// `repr(value)` — strings get quotes; containers recurse with repr.
func pyRepr(_ v: PyValue) -> String {
    switch v {
    case .string(let s):
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "'\(escaped)'"
    case .list(let l):
        return "[" + l.items.map(pyRepr).joined(separator: ", ") + "]"
    case .dict(let d):
        return "{" + d.orderedPairs.map { "\(pyRepr($0.0.value)): \(pyRepr($0.1))" }.joined(separator: ", ") + "}"
    default:
        return pyStr(v)
    }
}

/// Format a Double the way Python prints floats: integral values keep a trailing
/// `.0`, others use the shortest round-tripping representation.
func formatDouble(_ d: Double) -> String {
    if d.isNaN { return "nan" }
    if d.isInfinite { return d < 0 ? "-inf" : "inf" }
    if d == d.rounded() && abs(d) < 1e16 {
        return String(format: "%.1f", d)
    }
    // %.17g round-trips; trim to the shortest that still parses back to d.
    for p in 1...17 {
        let s = String(format: "%.\(p)g", d)
        if Double(s) == d { return s }
    }
    return String(format: "%.17g", d)
}

/// Python `==` value equality (cross-numeric: 1 == 1.0 == True).
func pyEquals(_ a: PyValue, _ b: PyValue) -> Bool {
    switch (a, b) {
    case (.none, .none): return true
    case (.string(let x), .string(let y)): return x == y
    case (.list(let x), .list(let y)):
        guard x.items.count == y.items.count else { return false }
        return zip(x.items, y.items).allSatisfy { pyEquals($0, $1) }
    case (.dict(let x), .dict(let y)):
        guard x.count == y.count else { return false }
        for (k, v) in x.orderedPairs {
            guard let yv = y[k], pyEquals(v, yv) else { return false }
        }
        return true
    default:
        if let x = a.asDouble, let y = b.asDouble { return x == y }
        return false
    }
}
