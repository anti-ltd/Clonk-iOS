/**
 PyMini interpreter: a tree-walking evaluator for the parsed AST.

 Sandbox guarantees:
 - No `import`, no file/network/system access — the only callable surface is the
   builtins and container methods defined here.
 - A deterministic per-step budget (`maxSteps`) bounds runaway loops/recursion;
   container growth is capped so a script can't exhaust memory in one op.

 Supported language subset:
 - Types: int, float, str, bool, None, list, dict.
 - Operators: + - * / // % **, comparison + chaining, and/or/not, in/not in,
   unary +/-, ternary `a if c else b`.
 - Statements: assignment (incl. tuple unpack + chained), augmented assignment,
   if/elif/else, while, for, def (with default args + kwargs), return,
   break/continue/pass.
 - f-strings, indexing, slicing, a useful set of str/list/dict methods and global
   builtins (len, range, str, int, sorted, enumerate, …).
 

 Module: pymini · Target: ClinkKit
 Learn: docs/08-pymini.md
 */
import Foundation

/// A lexical scope. Functions get a child env whose parent is their closure.
final class PyEnv {
    var vars: [String: PyValue] = [:]
    let parent: PyEnv?
    init(parent: PyEnv? = nil) { self.parent = parent }

    func get(_ name: String) -> PyValue? { vars[name] ?? parent?.get(name) }
    func define(_ name: String, _ value: PyValue) { vars[name] = value }
}

final class PyInterpreter {
    let globals = PyEnv()
    private let maxSteps: Int
    private var steps = 0
    private var currentLine = 0
    /// Captured `print(...)` output, surfaced to the in-app run console.
    private(set) var printed: [String] = []

    /// Hard caps so one operation can't exhaust the keyboard's memory budget.
    private let maxContainer = 200_000
    private let maxStringLength = 1_000_000

    init(maxSteps: Int = 2_000_000) { self.maxSteps = maxSteps }

    // MARK: - Public entry points

    /// Execute the whole module (defines functions, runs top-level code).
    func run(_ program: [Stmt]) throws {
        try execBlock(program, globals)
    }

    /// Whether a top-level function with this name exists.
    func hasFunction(_ name: String) -> Bool {
        if case .function = globals.get(name) { return true }
        return false
    }

    /// Call a top-level function by name with already-evaluated arguments.
    func call(_ name: String, _ args: [PyValue]) throws -> PyValue {
        guard let v = globals.get(name) else { throw PyError("name '\(name)' is not defined") }
        return try callValue(v, args, [])
    }

    /// Reset the step budget — used when calling a warm program's function
    /// repeatedly (e.g. re-rendering a custom panel on each tap).
    func resetBudget() { steps = 0 }

    /// Clear captured `print(...)` output before another call.
    func clearPrinted() { printed.removeAll() }

    // MARK: - Step budget

    private func tick() throws {
        steps += 1
        if steps > maxSteps { throw PyError("script exceeded its step budget (possible infinite loop)", line: currentLine) }
    }

    // MARK: - Statement execution

    private func execBlock(_ stmts: [Stmt], _ env: PyEnv) throws {
        for s in stmts { try exec(s, env) }
    }

    private func exec(_ stmt: Stmt, _ env: PyEnv) throws {
        try tick()
        currentLine = stmt.line
        switch stmt {
        case .expr(let e, _):
            _ = try eval(e, env)

        case .assign(let targets, let valueExpr, _):
            let value = try eval(valueExpr, env)
            for t in targets { try assign(t, value, env) }

        case .augAssign(let target, let op, let valueExpr, _):
            let current = try eval(target, env)
            let rhs = try eval(valueExpr, env)
            try assign(target, try binaryOp(op, current, rhs), env)

        case .ifStmt(let branches, let elseBody, _):
            for (cond, body) in branches {
                if try eval(cond, env).isTruthy { try execBlock(body, env); return }
            }
            if let elseBody { try execBlock(elseBody, env) }

        case .whileStmt(let cond, let body, _):
            while try eval(cond, env).isTruthy {
                try tick()
                do { try execBlock(body, env) }
                catch PyFlow.breakLoop { break }
                catch PyFlow.continueLoop { continue }
            }

        case .forStmt(let target, let iterableExpr, let body, _):
            let seq = try iterate(try eval(iterableExpr, env))
            for item in seq {
                try tick()
                try assign(target, item, env)
                do { try execBlock(body, env) }
                catch PyFlow.breakLoop { break }
                catch PyFlow.continueLoop { continue }
            }

        case .funcDef(let name, let params, let body, _):
            env.define(name, .function(PyFunction(name: name, params: params, body: body, closure: env)))

        case .returnStmt(let e, _):
            let v = try e.map { try eval($0, env) } ?? .none
            throw PyFlow.returnValue(v)

        case .breakStmt:    throw PyFlow.breakLoop
        case .continueStmt: throw PyFlow.continueLoop
        case .passStmt:     break
        }
    }

    // MARK: - Assignment targets

    private func assign(_ target: Expr, _ value: PyValue, _ env: PyEnv) throws {
        switch target {
        case .name(let n):
            env.define(n, value)
        case .tuple(let items):
            let parts = try iterate(value)
            guard parts.count == items.count else {
                throw PyError("cannot unpack \(parts.count) values into \(items.count) targets", line: currentLine)
            }
            for (t, v) in zip(items, parts) { try assign(t, v, env) }
        case .index(let baseExpr, let idxExpr):
            let base = try eval(baseExpr, env)
            let idx = try eval(idxExpr, env)
            switch base {
            case .list(let l):
                let i = try listIndex(idx, count: l.items.count)
                l.items[i] = value
            case .dict(let d):
                guard let key = PyHashable(idx) else { throw PyError("unhashable type: '\(idx.typeName)'", line: currentLine) }
                d[key] = value
            default:
                throw PyError("'\(base.typeName)' object does not support item assignment", line: currentLine)
            }
        default:
            throw PyError("cannot assign to this expression", line: currentLine)
        }
    }

    // MARK: - Expression evaluation

    private func eval(_ expr: Expr, _ env: PyEnv) throws -> PyValue {
        try tick()
        switch expr {
        case .noneLit:          return .none
        case .boolLit(let b):   return .bool(b)
        case .intLit(let i):    return .int(i)
        case .doubleLit(let d): return .double(d)
        case .stringLit(let s): return .string(s)

        case .fstring(let parts):
            var out = ""
            for p in parts {
                switch p {
                case .literal(let s): out += s
                case .expr(let e):    out += pyStr(try eval(e, env))
                }
                if out.count > maxStringLength { throw PyError("string too large", line: currentLine) }
            }
            return .string(out)

        case .name(let n):
            if let v = env.get(n) { return v }
            // Not a user binding — fall back to a builtin function reference so
            // `len`, `str`, `range`, … resolve (they live in `callBuiltin`).
            if Self.builtinNames.contains(n) { return .builtin(n) }
            throw PyError("name '\(n)' is not defined", line: currentLine)

        case .list(let items):
            return .list(PyList(try items.map { try eval($0, env) }))

        case .dict(let pairs):
            let d = PyDict()
            for (k, v) in pairs {
                let key = try eval(k, env)
                guard let hk = PyHashable(key) else { throw PyError("unhashable type: '\(key.typeName)'", line: currentLine) }
                d[hk] = try eval(v, env)
            }
            return .dict(d)

        case .tuple(let items):
            // No distinct tuple type — surface as a list (good enough for unpacking).
            return .list(PyList(try items.map { try eval($0, env) }))

        case .unary(let op, let e):
            return try unaryOp(op, try eval(e, env))

        case .binary(let op, let l, let r):
            return try binaryOp(op, try eval(l, env), try eval(r, env))

        case .boolOp(let kind, let l, let r):
            let lv = try eval(l, env)
            switch kind {
            case .and: return lv.isTruthy ? try eval(r, env) : lv
            case .or:  return lv.isTruthy ? lv : try eval(r, env)
            }

        case .compare(let first, let pairs):
            var left = try eval(first, env)
            for (op, rExpr) in pairs {
                let right = try eval(rExpr, env)
                if !(try compareOp(op, left, right)) { return .bool(false) }
                left = right
            }
            return .bool(true)

        case .ternary(let cond, let then, let orElse):
            return try eval(cond, env).isTruthy ? try eval(then, env) : try eval(orElse, env)

        case .index(let baseExpr, let idxExpr):
            return try index(try eval(baseExpr, env), try eval(idxExpr, env))

        case .slice(let baseExpr, let lo, let hi, let st):
            let base = try eval(baseExpr, env)
            let lower = try lo.map { try eval($0, env) }
            let upper = try hi.map { try eval($0, env) }
            let step = try st.map { try eval($0, env) }
            return try slice(base, lower, upper, step)

        case .attribute:
            throw PyError("attribute access is only supported in a method call", line: currentLine)

        case .call(let callee, let argExprs, let kwargExprs):
            let args = try argExprs.map { try eval($0, env) }
            let kwargs = try kwargExprs.map { ($0.0, try eval($0.1, env)) }
            // Method call: `obj.method(...)` is dispatched without a bound-method value.
            if case .attribute(let objExpr, let method) = callee {
                let obj = try eval(objExpr, env)
                return try callMethod(obj, method, args, kwargs)
            }
            let fn = try eval(callee, env)
            return try callValue(fn, args, kwargs)
        }
    }

    // MARK: - Calls

    private func callValue(_ callee: PyValue, _ args: [PyValue], _ kwargs: [(String, PyValue)]) throws -> PyValue {
        switch callee {
        case .function(let f):
            return try callFunction(f, args, kwargs)
        case .builtin(let name):
            guard kwargs.isEmpty || Self.kwargBuiltins.contains(name) else {
                throw PyError("\(name)() takes no keyword arguments", line: currentLine)
            }
            return try callBuiltin(name, args, kwargs)
        default:
            throw PyError("'\(callee.typeName)' object is not callable", line: currentLine)
        }
    }

    private func callFunction(_ f: PyFunction, _ args: [PyValue], _ kwargs: [(String, PyValue)]) throws -> PyValue {
        let env = PyEnv(parent: f.closure)
        var bound = Set<String>()
        guard args.count <= f.params.count else {
            throw PyError("\(f.name)() takes \(f.params.count) arguments but \(args.count) were given", line: currentLine)
        }
        for (i, a) in args.enumerated() {
            env.define(f.params[i].name, a)
            bound.insert(f.params[i].name)
        }
        let names = Set(f.params.map { $0.name })
        for (k, v) in kwargs {
            guard names.contains(k) else { throw PyError("\(f.name)() got an unexpected keyword argument '\(k)'", line: currentLine) }
            env.define(k, v)
            bound.insert(k)
        }
        for p in f.params where !bound.contains(p.name) {
            guard let def = p.defaultValue else { throw PyError("\(f.name)() missing required argument '\(p.name)'", line: currentLine) }
            env.define(p.name, try eval(def, f.closure))
        }
        do { try execBlock(f.body, env) }
        catch PyFlow.returnValue(let v) { return v }
        return .none
    }

    // MARK: - Operators

    private func unaryOp(_ op: UnOp, _ v: PyValue) throws -> PyValue {
        switch op {
        case .not: return .bool(!v.isTruthy)
        case .pos:
            if v.asInt != nil || v.asDouble != nil { return v }
            throw PyError("bad operand type for unary +: '\(v.typeName)'", line: currentLine)
        case .neg:
            if let i = v.asInt, case .int = v { return .int(-i) }
            if let i = v.asInt, case .bool = v { return .int(-i) }
            if let d = v.asDouble { return .double(-d) }
            throw PyError("bad operand type for unary -: '\(v.typeName)'", line: currentLine)
        }
    }

    private func binaryOp(_ op: BinOp, _ a: PyValue, _ b: PyValue) throws -> PyValue {
        // String / list `+` and `*` specialisations.
        if op == .add {
            if case .string(let x) = a, case .string(let y) = b {
                let r = x + y
                if r.count > maxStringLength { throw PyError("string too large", line: currentLine) }
                return .string(r)
            }
            if case .list(let x) = a, case .list(let y) = b {
                let items = x.items + y.items
                if items.count > maxContainer { throw PyError("list too large", line: currentLine) }
                return .list(PyList(items))
            }
        }
        if op == .mul {
            if let r = try repeatSeq(a, b) ?? repeatSeq(b, a) { return r }
        }

        guard let x = a.asDouble, let y = b.asDouble else {
            throw PyError("unsupported operand type(s) for \(opSymbol(op)): '\(a.typeName)' and '\(b.typeName)'", line: currentLine)
        }
        let bothInt = a.asInt != nil && b.asInt != nil
        switch op {
        case .add: return numeric(x + y, bothInt)
        case .sub: return numeric(x - y, bothInt)
        case .mul: return numeric(x * y, bothInt)
        case .div:
            if y == 0 { throw PyError("division by zero", line: currentLine) }
            return .double(x / y)
        case .floordiv:
            if y == 0 { throw PyError("integer division or modulo by zero", line: currentLine) }
            return numeric((x / y).rounded(.down), bothInt)
        case .mod:
            if y == 0 { throw PyError("integer division or modulo by zero", line: currentLine) }
            // Python modulo takes the sign of the divisor.
            let r = x - (x / y).rounded(.down) * y
            return numeric(r, bothInt)
        case .pow:
            let r = pow(x, y)
            return numeric(r, bothInt && y >= 0)
        }
    }

    /// `seq * n` repetition for str/list when exactly one side is an int.
    private func repeatSeq(_ seq: PyValue, _ n: PyValue) throws -> PyValue? {
        guard let count = n.asInt, case .int = n else {
            if case .bool = n, let c = n.asInt { return try repeatSeqApply(seq, c) }
            return nil
        }
        return try repeatSeqApply(seq, count)
    }

    private func repeatSeqApply(_ seq: PyValue, _ count: Int) throws -> PyValue? {
        let n = max(0, count)
        switch seq {
        case .string(let s):
            if s.count * n > maxStringLength { throw PyError("string too large", line: currentLine) }
            return .string(String(repeating: s, count: n))
        case .list(let l):
            if l.items.count * n > maxContainer { throw PyError("list too large", line: currentLine) }
            var out: [PyValue] = []
            for _ in 0..<n { out += l.items }
            return .list(PyList(out))
        default:
            return nil
        }
    }

    private func numeric(_ d: Double, _ asInt: Bool) -> PyValue {
        if asInt && d == d.rounded() && abs(d) < 9.007e15 { return .int(Int(d)) }
        return .double(d)
    }

    private func opSymbol(_ op: BinOp) -> String {
        switch op {
        case .add: return "+"; case .sub: return "-"; case .mul: return "*"
        case .div: return "/"; case .floordiv: return "//"; case .mod: return "%"; case .pow: return "**"
        }
    }

    private func compareOp(_ op: CmpOp, _ a: PyValue, _ b: PyValue) throws -> Bool {
        switch op {
        case .eq: return pyEquals(a, b)
        case .ne: return !pyEquals(a, b)
        case .inOp: return try contains(b, a)
        case .notIn: return !(try contains(b, a))
        case .lt, .le, .gt, .ge:
            let c = try order(a, b)
            switch op {
            case .lt: return c < 0
            case .le: return c <= 0
            case .gt: return c > 0
            case .ge: return c >= 0
            default: return false
            }
        }
    }

    /// Three-way ordering for numbers, strings, and lists (lexicographic).
    private func order(_ a: PyValue, _ b: PyValue) throws -> Int {
        if let x = a.asDouble, let y = b.asDouble { return x < y ? -1 : (x > y ? 1 : 0) }
        if case .string(let x) = a, case .string(let y) = b { return x < y ? -1 : (x > y ? 1 : 0) }
        if case .list(let x) = a, case .list(let y) = b {
            for (xi, yi) in zip(x.items, y.items) {
                let c = try order(xi, yi)
                if c != 0 { return c }
            }
            return x.items.count < y.items.count ? -1 : (x.items.count > y.items.count ? 1 : 0)
        }
        throw PyError("'<' not supported between '\(a.typeName)' and '\(b.typeName)'", line: currentLine)
    }

    private func contains(_ container: PyValue, _ item: PyValue) throws -> Bool {
        switch container {
        case .string(let s):
            guard case .string(let sub) = item else { throw PyError("'in <string>' requires string as left operand", line: currentLine) }
            return sub.isEmpty || s.contains(sub)
        case .list(let l):
            return l.items.contains { pyEquals($0, item) }
        case .dict(let d):
            guard let key = PyHashable(item) else { return false }
            return d[key] != nil
        default:
            throw PyError("argument of type '\(container.typeName)' is not iterable", line: currentLine)
        }
    }

    // MARK: - Indexing / slicing / iteration

    private func iterate(_ value: PyValue) throws -> [PyValue] {
        switch value {
        case .string(let s): return s.map { .string(String($0)) }
        case .list(let l):   return l.items
        case .dict(let d):   return d.keys.map { $0.value }
        default:
            throw PyError("'\(value.typeName)' object is not iterable", line: currentLine)
        }
    }

    private func listIndex(_ idx: PyValue, count: Int) throws -> Int {
        guard let raw = idx.asInt else { throw PyError("indices must be integers", line: currentLine) }
        let i = raw < 0 ? raw + count : raw
        guard i >= 0 && i < count else { throw PyError("index out of range", line: currentLine) }
        return i
    }

    private func index(_ base: PyValue, _ idx: PyValue) throws -> PyValue {
        switch base {
        case .string(let s):
            let arr = Array(s)
            let i = try listIndex(idx, count: arr.count)
            return .string(String(arr[i]))
        case .list(let l):
            return l.items[try listIndex(idx, count: l.items.count)]
        case .dict(let d):
            guard let key = PyHashable(idx) else { throw PyError("unhashable type: '\(idx.typeName)'", line: currentLine) }
            guard let v = d[key] else { throw PyError("KeyError: \(pyRepr(idx))", line: currentLine) }
            return v
        default:
            throw PyError("'\(base.typeName)' object is not subscriptable", line: currentLine)
        }
    }

    private func slice(_ base: PyValue, _ lo: PyValue?, _ hi: PyValue?, _ st: PyValue?) throws -> PyValue {
        let step = st?.asInt ?? 1
        if step == 0 { throw PyError("slice step cannot be zero", line: currentLine) }
        func sliceArray<T>(_ arr: [T]) throws -> [T] {
            let n = arr.count
            var start: Int
            var stop: Int
            if step > 0 {
                start = lo?.asInt.map { $0 < 0 ? max(0, $0 + n) : min($0, n) } ?? 0
                stop = hi?.asInt.map { $0 < 0 ? max(0, $0 + n) : min($0, n) } ?? n
            } else {
                start = lo?.asInt.map { $0 < 0 ? $0 + n : min($0, n - 1) } ?? (n - 1)
                stop = hi?.asInt.map { $0 < 0 ? $0 + n : $0 } ?? -1
            }
            var out: [T] = []
            var i = start
            if step > 0 { while i < stop { if i >= 0 && i < n { out.append(arr[i]) }; i += step } }
            else { while i > stop { if i >= 0 && i < n { out.append(arr[i]) }; i += step } }
            return out
        }
        switch base {
        case .string(let s): return .string(String(try sliceArray(Array(s))))
        case .list(let l):   return .list(PyList(try sliceArray(l.items)))
        default: throw PyError("'\(base.typeName)' object is not subscriptable", line: currentLine)
        }
    }

    // MARK: - Builtins

    /// Names that resolve to a builtin when not shadowed by a user binding.
    static let builtinNames: Set<String> = [
        "len", "str", "repr", "print", "int", "float", "bool", "abs", "round",
        "min", "max", "sum", "range", "sorted", "reversed", "list", "dict",
        "enumerate", "zip", "ord", "chr", "any", "all", "type",
        // Custom-panel UI builders (see `PanelRuntime`).
        "text", "button", "vstack", "hstack", "grid", "spacer", "divider", "field",
    ]

    /// Builtins that accept keyword arguments (everything else rejects them).
    static let kwargBuiltins: Set<String> = [
        "sorted", "text", "button", "vstack", "hstack", "grid", "field",
    ]

    /// The custom-panel UI builders — return plain dict "nodes" the renderer walks.
    private static let panelBuilders: Set<String> = [
        "text", "button", "vstack", "hstack", "grid", "spacer", "divider", "field",
    ]

    private func callBuiltin(_ name: String, _ args: [PyValue], _ kwargs: [(String, PyValue)]) throws -> PyValue {
        if Self.panelBuilders.contains(name) { return try panelBuilder(name, args, kwargs) }
        switch name {
        case "len":
            try arity(name, args, 1)
            return .int(try length(args[0]))
        case "str":  return .string(args.isEmpty ? "" : pyStr(args[0]))
        case "repr": try arity(name, args, 1); return .string(pyRepr(args[0]))
        case "print":
            printed.append(args.map { pyStr($0) }.joined(separator: " "))
            return .none
        case "int":  return try toInt(args)
        case "float": return try toFloat(args)
        case "bool": return .bool(args.first?.isTruthy ?? false)
        case "abs":
            try arity(name, args, 1)
            if let i = args[0].asInt, case .int = args[0] { return .int(abs(i)) }
            guard let d = args[0].asDouble else { throw PyError("bad operand type for abs()", line: currentLine) }
            return .double(abs(d))
        case "round": return try roundBuiltin(args)
        case "min": return try minmax(args, wantMax: false)
        case "max": return try minmax(args, wantMax: true)
        case "sum": return try sumBuiltin(args)
        case "range": return try rangeBuiltin(args)
        case "sorted": return try sortedBuiltin(args, kwargs)
        case "reversed":
            try arity(name, args, 1)
            return .list(PyList(try iterate(args[0]).reversed()))
        case "list":
            return .list(PyList(args.isEmpty ? [] : try iterate(args[0])))
        case "dict":
            return .dict(PyDict())
        case "enumerate": return try enumerateBuiltin(args)
        case "zip": return try zipBuiltin(args)
        case "ord":
            try arity(name, args, 1)
            guard case .string(let s) = args[0], s.count == 1, let u = s.unicodeScalars.first else {
                throw PyError("ord() expected a character", line: currentLine)
            }
            return .int(Int(u.value))
        case "chr":
            try arity(name, args, 1)
            guard let i = args[0].asInt, let scalar = Unicode.Scalar(i) else { throw PyError("chr() arg not in range", line: currentLine) }
            return .string(String(scalar))
        case "any": try arity(name, args, 1); return .bool(try iterate(args[0]).contains { $0.isTruthy })
        case "all": try arity(name, args, 1); return .bool(try iterate(args[0]).allSatisfy { $0.isTruthy })
        case "type": try arity(name, args, 1); return .string(args[0].typeName)
        default:
            throw PyError("name '\(name)' is not defined", line: currentLine)
        }
    }

    /// Build a custom-panel UI "node" — a plain dict the SwiftUI renderer walks.
    /// These let a script return a declarative view tree, e.g.
    /// `vstack([text("Hi"), button("A", insert="a")])`.
    private func panelBuilder(_ name: String, _ args: [PyValue], _ kwargs: [(String, PyValue)]) throws -> PyValue {
        func kw(_ k: String) -> PyValue? { kwargs.first { $0.0 == k }?.1 }
        func node(_ pairs: [(String, PyValue)]) -> PyValue {
            .dict(PyDict(pairs.map { (PyHashable.string($0.0), $0.1) }))
        }
        switch name {
        case "text":
            let s = args.first ?? kw("s") ?? .string("")
            return node([("t", .string("text")), ("s", .string(pyStr(s))),
                         ("size", kw("size") ?? .int(17)),
                         ("weight", kw("weight") ?? .string("regular")),
                         ("color", kw("color") ?? .string(""))])
        case "button":
            let label = args.first ?? kw("label") ?? .string("")
            return node([("t", .string("button")), ("label", .string(pyStr(label))),
                         ("insert", kw("insert") ?? .string("")),
                         ("set", kw("set") ?? .none),
                         ("style", kw("style") ?? .string("plain"))])
        case "field":
            let key = args.first ?? kw("key") ?? .string("")
            return node([("t", .string("field")), ("key", .string(pyStr(key))),
                         ("placeholder", kw("placeholder") ?? .string("")),
                         ("value", kw("value") ?? .string(""))])
        case "vstack", "hstack":
            let children = args.first ?? kw("children") ?? .list(PyList())
            return node([("t", .string(name)), ("children", children),
                         ("spacing", kw("spacing") ?? .int(6))])
        case "grid":
            let children = args.first ?? kw("children") ?? .list(PyList())
            return node([("t", .string("grid")), ("children", children),
                         ("columns", kw("columns") ?? .int(4)),
                         ("spacing", kw("spacing") ?? .int(6))])
        case "spacer":  return node([("t", .string("spacer"))])
        case "divider": return node([("t", .string("divider"))])
        default: throw PyError("unknown panel builder '\(name)'", line: currentLine)
        }
    }

    private func arity(_ name: String, _ args: [PyValue], _ n: Int) throws {
        guard args.count == n else { throw PyError("\(name)() takes \(n) argument(s) but \(args.count) were given", line: currentLine) }
    }

    private func length(_ v: PyValue) throws -> Int {
        switch v {
        case .string(let s): return s.count
        case .list(let l):   return l.items.count
        case .dict(let d):   return d.count
        default: throw PyError("object of type '\(v.typeName)' has no len()", line: currentLine)
        }
    }

    private func toInt(_ args: [PyValue]) throws -> PyValue {
        guard let a = args.first else { return .int(0) }
        switch a {
        case .int, .bool: return .int(a.asInt!)
        case .double(let d): return .int(Int(d.rounded(.towardZero)))
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespaces)
            guard let i = Int(t) else { throw PyError("invalid literal for int(): \(pyRepr(a))", line: currentLine) }
            return .int(i)
        default: throw PyError("int() argument must be a string or a number", line: currentLine)
        }
    }

    private func toFloat(_ args: [PyValue]) throws -> PyValue {
        guard let a = args.first else { return .double(0) }
        if let d = a.asDouble { return .double(d) }
        if case .string(let s) = a, let d = Double(s.trimmingCharacters(in: .whitespaces)) { return .double(d) }
        throw PyError("could not convert to float: \(pyRepr(a))", line: currentLine)
    }

    private func roundBuiltin(_ args: [PyValue]) throws -> PyValue {
        guard let a = args.first, let d = a.asDouble else { throw PyError("round() needs a number", line: currentLine) }
        let ndigits = args.count > 1 ? (args[1].asInt ?? 0) : 0
        if args.count > 1 {
            let m = pow(10.0, Double(ndigits))
            return .double((d * m).rounded(.toNearestOrEven) / m)
        }
        return .int(Int(d.rounded(.toNearestOrEven)))
    }

    private func minmax(_ args: [PyValue], wantMax: Bool) throws -> PyValue {
        let items: [PyValue]
        if args.count == 1 { items = try iterate(args[0]) } else { items = args }
        guard var best = items.first else { throw PyError("\(wantMax ? "max" : "min")() arg is an empty sequence", line: currentLine) }
        for v in items.dropFirst() {
            let c = try order(v, best)
            if (wantMax && c > 0) || (!wantMax && c < 0) { best = v }
        }
        return best
    }

    private func sumBuiltin(_ args: [PyValue]) throws -> PyValue {
        guard let first = args.first else { throw PyError("sum() needs an iterable", line: currentLine) }
        var acc: PyValue = args.count > 1 ? args[1] : .int(0)
        for v in try iterate(first) { acc = try binaryOp(.add, acc, v) }
        return acc
    }

    private func rangeBuiltin(_ args: [PyValue]) throws -> PyValue {
        let nums = try args.map { v -> Int in
            guard let i = v.asInt else { throw PyError("range() argument must be an integer", line: currentLine) }
            return i
        }
        var start = 0, stop = 0, step = 1
        switch nums.count {
        case 1: stop = nums[0]
        case 2: start = nums[0]; stop = nums[1]
        case 3: start = nums[0]; stop = nums[1]; step = nums[2]
        default: throw PyError("range() takes 1 to 3 arguments", line: currentLine)
        }
        if step == 0 { throw PyError("range() step must not be zero", line: currentLine) }
        var out: [PyValue] = []
        var i = start
        while (step > 0 && i < stop) || (step < 0 && i > stop) {
            out.append(.int(i))
            if out.count > maxContainer { throw PyError("range too large", line: currentLine) }
            i += step
        }
        return .list(PyList(out))
    }

    private func sortedBuiltin(_ args: [PyValue], _ kwargs: [(String, PyValue)]) throws -> PyValue {
        try arity("sorted", args, 1)
        var items = try iterate(args[0])
        let reverse = kwargs.first { $0.0 == "reverse" }?.1.isTruthy ?? false
        // Stable insertion sort using the three-way order (throws on mixed types).
        try insertionSort(&items)
        if reverse { items.reverse() }
        return .list(PyList(items))
    }

    private func insertionSort(_ items: inout [PyValue]) throws {
        for i in 1..<max(1, items.count) {
            var j = i
            while j > 0, try order(items[j], items[j - 1]) < 0 {
                items.swapAt(j, j - 1)
                j -= 1
                try tick()
            }
        }
    }

    private func enumerateBuiltin(_ args: [PyValue]) throws -> PyValue {
        guard let first = args.first else { throw PyError("enumerate() needs an iterable", line: currentLine) }
        let startIdx = args.count > 1 ? (args[1].asInt ?? 0) : 0
        let seq = try iterate(first)
        var out: [PyValue] = []
        for (offset, v) in seq.enumerated() {
            out.append(.list(PyList([.int(startIdx + offset), v])))
        }
        return .list(PyList(out))
    }

    private func zipBuiltin(_ args: [PyValue]) throws -> PyValue {
        let seqs = try args.map { try iterate($0) }
        guard let shortest = seqs.map({ $0.count }).min() else { return .list(PyList()) }
        var out: [PyValue] = []
        for i in 0..<shortest { out.append(.list(PyList(seqs.map { $0[i] }))) }
        return .list(PyList(out))
    }

    // MARK: - Methods (str / list / dict)

    func callMethod(_ obj: PyValue, _ name: String, _ args: [PyValue], _ kwargs: [(String, PyValue)]) throws -> PyValue {
        switch obj {
        case .string(let s): return try stringMethod(s, name, args)
        case .list(let l):   return try listMethod(l, name, args)
        case .dict(let d):   return try dictMethod(d, name, args)
        default:
            throw PyError("'\(obj.typeName)' object has no method '\(name)'", line: currentLine)
        }
    }

    private func argStr(_ args: [PyValue], _ i: Int, _ method: String) throws -> String {
        guard i < args.count, case .string(let s) = args[i] else {
            throw PyError("\(method)() expects a string argument", line: currentLine)
        }
        return s
    }

    private func stringMethod(_ s: String, _ name: String, _ args: [PyValue]) throws -> PyValue {
        switch name {
        case "upper": return .string(s.uppercased())
        case "lower": return .string(s.lowercased())
        case "title": return .string(s.capitalized)
        case "capitalize":
            guard let first = s.first else { return .string("") }
            return .string(first.uppercased() + s.dropFirst().lowercased())
        case "swapcase":
            return .string(String(s.map { $0.isUppercase ? Character($0.lowercased()) : Character($0.uppercased()) }))
        case "strip":  return .string(trim(s, args, both: true, left: true, right: true))
        case "lstrip": return .string(trim(s, args, both: false, left: true, right: false))
        case "rstrip": return .string(trim(s, args, both: false, left: false, right: true))
        case "replace":
            let from = try argStr(args, 0, "replace"), to = try argStr(args, 1, "replace")
            if from.isEmpty { return .string(s) }
            return .string(s.replacingOccurrences(of: from, with: to))
        case "split":  return try splitMethod(s, args, fromEnd: false)
        case "rsplit": return try splitMethod(s, args, fromEnd: true)
        case "splitlines":
            return .list(PyList(s.split(separator: "\n", omittingEmptySubsequences: false).map { .string(String($0)) }))
        case "join":
            guard let it = args.first else { throw PyError("join() needs an iterable", line: currentLine) }
            let parts = try iterate(it).map { v -> String in
                guard case .string(let str) = v else { throw PyError("join() requires str items", line: currentLine) }
                return str
            }
            return .string(parts.joined(separator: s))
        case "startswith": return .bool(s.hasPrefix(try argStr(args, 0, "startswith")))
        case "endswith":   return .bool(s.hasSuffix(try argStr(args, 0, "endswith")))
        case "find":
            let sub = try argStr(args, 0, "find")
            if let r = s.range(of: sub) { return .int(s.distance(from: s.startIndex, to: r.lowerBound)) }
            return .int(-1)
        case "count":
            let sub = try argStr(args, 0, "count")
            if sub.isEmpty { return .int(s.count + 1) }
            return .int(s.components(separatedBy: sub).count - 1)
        case "zfill":
            let width = args.first?.asInt ?? 0
            if s.count >= width { return .string(s) }
            let pad = String(repeating: "0", count: width - s.count)
            if let f = s.first, f == "-" || f == "+" { return .string(String(f) + pad + s.dropFirst()) }
            return .string(pad + s)
        case "ljust": return .string(pad(s, args, left: false))
        case "rjust": return .string(pad(s, args, left: true))
        case "isdigit": return .bool(!s.isEmpty && s.allSatisfy { $0.isNumber })
        case "isalpha": return .bool(!s.isEmpty && s.allSatisfy { $0.isLetter })
        case "isalnum": return .bool(!s.isEmpty && s.allSatisfy { $0.isLetter || $0.isNumber })
        case "isspace": return .bool(!s.isEmpty && s.allSatisfy { $0.isWhitespace })
        case "isupper": return .bool(s.contains { $0.isLetter } && s == s.uppercased())
        case "islower": return .bool(s.contains { $0.isLetter } && s == s.lowercased())
        case "removeprefix":
            let p = try argStr(args, 0, "removeprefix")
            return .string(s.hasPrefix(p) ? String(s.dropFirst(p.count)) : s)
        case "removesuffix":
            let p = try argStr(args, 0, "removesuffix")
            return .string(s.hasSuffix(p) ? String(s.dropLast(p.count)) : s)
        case "format": return .string(try formatMethod(s, args))
        default:
            throw PyError("'str' object has no method '\(name)'", line: currentLine)
        }
    }

    private func trim(_ s: String, _ args: [PyValue], both: Bool, left: Bool, right: Bool) -> String {
        let chars: Set<Character>
        if case .string(let cut)? = args.first { chars = Set(cut) } else { chars = Set(" \t\n\r") }
        var out = Substring(s)
        if left { while let f = out.first, chars.contains(f) { out = out.dropFirst() } }
        if right { while let l = out.last, chars.contains(l) { out = out.dropLast() } }
        return String(out)
    }

    private func pad(_ s: String, _ args: [PyValue], left: Bool) -> String {
        let width = args.first?.asInt ?? 0
        var fill: Character = " "
        if args.count > 1, case .string(let f) = args[1], let c = f.first { fill = c }
        if s.count >= width { return s }
        let padding = String(repeating: fill, count: width - s.count)
        return left ? padding + s : s + padding
    }

    private func splitMethod(_ s: String, _ args: [PyValue], fromEnd: Bool) throws -> PyValue {
        if let first = args.first, case .string(let sep) = first {
            if sep.isEmpty { throw PyError("empty separator", line: currentLine) }
            let parts = s.components(separatedBy: sep)
            return .list(PyList(parts.map { .string($0) }))
        }
        // No separator: split on runs of whitespace, dropping empties.
        let parts = s.split(whereSeparator: { $0.isWhitespace }).map { String($0) }
        return .list(PyList(parts.map { .string($0) }))
    }

    /// Minimal `str.format` — positional `{}` / `{0}` only (no format specs).
    private func formatMethod(_ s: String, _ args: [PyValue]) throws -> String {
        var out = ""
        var auto = 0
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "{" {
                if i + 1 < chars.count, chars[i + 1] == "{" { out.append("{"); i += 2; continue }
                var inner = ""
                i += 1
                while i < chars.count, chars[i] != "}" { inner.append(chars[i]); i += 1 }
                i += 1 // consume }
                let key = inner.trimmingCharacters(in: .whitespaces)
                let idx: Int
                if key.isEmpty { idx = auto; auto += 1 }
                else if let n = Int(key) { idx = n }
                else { throw PyError("named format fields are not supported", line: currentLine) }
                guard idx < args.count else { throw PyError("format index out of range", line: currentLine) }
                out += pyStr(args[idx])
            } else if c == "}" {
                if i + 1 < chars.count, chars[i + 1] == "}" { out.append("}"); i += 2; continue }
                out.append("}"); i += 1
            } else {
                out.append(c); i += 1
            }
        }
        _ = chars
        return out
    }

    private func listMethod(_ l: PyList, _ name: String, _ args: [PyValue]) throws -> PyValue {
        switch name {
        case "append":
            try arity("append", args, 1)
            if l.items.count + 1 > maxContainer { throw PyError("list too large", line: currentLine) }
            l.items.append(args[0]); return .none
        case "extend":
            guard let it = args.first else { throw PyError("extend() needs an iterable", line: currentLine) }
            l.items.append(contentsOf: try iterate(it))
            if l.items.count > maxContainer { throw PyError("list too large", line: currentLine) }
            return .none
        case "pop":
            guard !l.items.isEmpty else { throw PyError("pop from empty list", line: currentLine) }
            let idx = args.first?.asInt ?? (l.items.count - 1)
            let i = idx < 0 ? idx + l.items.count : idx
            guard i >= 0 && i < l.items.count else { throw PyError("pop index out of range", line: currentLine) }
            return l.items.remove(at: i)
        case "insert":
            try arity("insert", args, 2)
            let raw = args[0].asInt ?? 0
            let i = max(0, min(l.items.count, raw < 0 ? raw + l.items.count : raw))
            l.items.insert(args[1], at: i); return .none
        case "remove":
            try arity("remove", args, 1)
            guard let i = l.items.firstIndex(where: { pyEquals($0, args[0]) }) else { throw PyError("list.remove(x): x not in list", line: currentLine) }
            l.items.remove(at: i); return .none
        case "index":
            try arity("index", args, 1)
            guard let i = l.items.firstIndex(where: { pyEquals($0, args[0]) }) else { throw PyError("\(pyRepr(args[0])) is not in list", line: currentLine) }
            return .int(i)
        case "count":
            try arity("count", args, 1)
            return .int(l.items.filter { pyEquals($0, args[0]) }.count)
        case "sort":
            try insertionSort(&l.items); return .none
        case "reverse":
            l.items.reverse(); return .none
        case "clear":
            l.items.removeAll(); return .none
        case "copy":
            return .list(PyList(l.items))
        default:
            throw PyError("'list' object has no method '\(name)'", line: currentLine)
        }
    }

    private func dictMethod(_ d: PyDict, _ name: String, _ args: [PyValue]) throws -> PyValue {
        switch name {
        case "keys":   return .list(PyList(d.keys.map { $0.value }))
        case "values": return .list(PyList(d.orderedPairs.map { $0.1 }))
        case "items":  return .list(PyList(d.orderedPairs.map { .list(PyList([$0.0.value, $0.1])) }))
        case "get":
            guard let k = args.first, let key = PyHashable(k) else { throw PyError("unhashable key", line: currentLine) }
            return d[key] ?? (args.count > 1 ? args[1] : .none)
        case "pop":
            guard let k = args.first, let key = PyHashable(k) else { throw PyError("unhashable key", line: currentLine) }
            if let v = d[key] { d[key] = nil; return v }
            if args.count > 1 { return args[1] }
            throw PyError("KeyError: \(pyRepr(k))", line: currentLine)
        case "setdefault":
            guard let k = args.first, let key = PyHashable(k) else { throw PyError("unhashable key", line: currentLine) }
            if let v = d[key] { return v }
            let def = args.count > 1 ? args[1] : .none
            d[key] = def; return def
        case "update":
            guard case .dict(let other)? = args.first else { throw PyError("update() expects a dict", line: currentLine) }
            for (k, v) in other.orderedPairs { d[k] = v }
            return .none
        case "clear":
            for k in d.keys { d[k] = nil }
            return .none
        case "copy":
            let n = PyDict(); for (k, v) in d.orderedPairs { n[k] = v }
            return .dict(n)
        default:
            throw PyError("'dict' object has no method '\(name)'", line: currentLine)
        }
    }
}
