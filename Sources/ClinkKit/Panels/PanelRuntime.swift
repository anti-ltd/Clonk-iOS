/**
 Custom-panel runtime: bridges a PyMini panel script to the native SwiftUI
 renderer (`CustomPanelView`).

 A panel script defines two functions:

     def initial():
         return {"display": "0"}

     def view(state):
         return vstack([
             text(state["display"], size=28),
             grid([button(str(n), set={"display": str(n)}) for n in range(9)]),
         ])

 (comprehensions aren't supported — build lists with loops/helpers instead.)

 State is held Swift-side as scalar key/values (`PanelValue`) and passed into
 `view(state)` on every render. Buttons carry `insert` (typed into the document)
 and/or `set` (merged into state → re-render) — an Elm/MVU loop. The interpreter
 stays warm across renders (`PyProgram`), so re-rendering on each tap is cheap and
 step-budget bounded — safe inside the keyboard's tight memory budget.
 

 Module: custom-panels · Target: ClinkKit
 Learn: docs/07-custom-panels.md
 */
import Foundation

/// A scalar panel-state value (state holds only scalars — no nested containers).
public enum PanelValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case none

    var pyValue: PyValue {
        switch self {
        case .string(let s): return .string(s)
        case .number(let d): return d == d.rounded() ? .int(Int(d)) : .double(d)
        case .bool(let b):   return .bool(b)
        case .none:          return .none
        }
    }

    /// String form for UI fields and error messages.
    public var asString: String {
        switch self {
        case .string(let s): return s
        case .number(let d): return d == d.rounded() ? String(Int(d)) : String(d)
        case .bool(let b):   return b ? "True" : "False"
        case .none:          return ""
        }
    }
}

/// A node in a panel's declarative view tree, parsed from PyMini builder dicts.
public indirect enum PanelNode {
    case text(String, size: Double, weight: String, color: String)
    /// `insert` types into the document; `set` merges into panel state and re-renders.
    case button(label: String, insert: String?, set: [String: PanelValue]?, style: String)
    case field(key: String, placeholder: String, value: String)
    case vstack([PanelNode], spacing: Double)
    case hstack([PanelNode], spacing: Double)
    case grid([PanelNode], columns: Int, spacing: Double)
    case spacer
    case divider
}

/// Outcome of one `render()` — a node tree, a user-facing error, or debug log.
public struct PanelRender {
    public let node: PanelNode?
    public let error: String?
    public let log: [String]
}

/// Bridges a PyMini panel script to native SwiftUI via `CustomPanelView`.
///
/// Scripts define `initial()` (optional state dict) and `view(state)` (node tree).
/// State is scalar-only Swift-side; buttons carry `insert` and/or `set` keys.
/// The underlying `PyProgram` stays warm — each render gets a fresh step budget.
@MainActor
public final class PanelRuntime {
    private let program: PyProgram
    private var state: [String: PanelValue] = [:]
    /// A load-time error (parse / top-level), nil if the script loaded.
    public let loadError: String?

    /// Parse and load `source`. Runs top-level code once; keeps `def`s for later calls.
    /// Calls `initial()` when present to seed scalar state.
    public init(source: String) {
        program = PyProgram(source: source)
        loadError = program.loadError
        if loadError == nil, program.has("initial") {
            let r = program.call("initial", [])
            if let v = r.value, case .dict = v { state = Self.scalars(from: v) }
        }
    }

    /// Render the current state into a node tree.
    /// Re-invokes `view(state)` on the warm interpreter (fresh step budget per call).
    public func render() -> PanelRender {
        if let loadError { return PanelRender(node: nil, error: loadError, log: []) }
        guard program.has("view") else {
            return PanelRender(node: nil, error: "Define a function: def view(state): …", log: [])
        }
        let r = program.call("view", [stateAsPy()])
        if let error = r.error { return PanelRender(node: nil, error: error, log: r.log) }
        guard let v = r.value else { return PanelRender(node: nil, error: "view() returned nothing", log: r.log) }
        do { return PanelRender(node: try Self.parseNode(v), error: nil, log: r.log) }
        catch let e as PyError { return PanelRender(node: nil, error: e.display, log: r.log) }
        catch { return PanelRender(node: nil, error: "invalid view", log: r.log) }
    }

    /// Apply a button's `set` merge to state. Returns whether anything changed.
    @discardableResult
    public func apply(set: [String: PanelValue]?) -> Bool {
        guard let set, !set.isEmpty else { return false }
        for (k, v) in set { state[k] = v }
        return true
    }

    /// Write a text field's value into its state key.
    public func setField(_ key: String, _ value: String) {
        state[key] = .string(value)
    }

    public func value(forField key: String) -> String {
        state[key]?.asString ?? ""
    }

    // MARK: - State <-> PyValue

    private func stateAsPy() -> PyValue {
        let d = PyDict()
        for (k, v) in state { d[.string(k)] = v.pyValue }
        return .dict(d)
    }

    private static func scalars(from value: PyValue) -> [String: PanelValue] {
        guard case .dict(let d) = value else { return [:] }
        var out: [String: PanelValue] = [:]
        for (k, v) in d.orderedPairs {
            if case .string(let key) = k.value, let scalar = scalar(v) { out[key] = scalar }
        }
        return out
    }

    private static func scalar(_ v: PyValue) -> PanelValue? {
        switch v {
        case .string(let s): return .string(s)
        case .int(let i):    return .number(Double(i))
        case .double(let d): return .number(d)
        case .bool(let b):   return .bool(b)
        case .none:          return PanelValue.none
        default:             return nil   // containers aren't valid state
        }
    }

    // MARK: - Node parsing

    private static func parseNode(_ v: PyValue) throws -> PanelNode {
        // A bare string is shorthand for a text node.
        if case .string(let s) = v { return .text(s, size: 17, weight: "regular", color: "") }
        guard case .dict(let d) = v else {
            throw PyError("view() must return a node (use vstack/text/button/…)")
        }
        let t = str(d, "t")
        switch t {
        case "text":
            return .text(str(d, "s"), size: num(d, "size", 17), weight: str(d, "weight"), color: str(d, "color"))
        case "button":
            let setVal = d[.string("set")]
            let set: [String: PanelValue]? = {
                if let setVal, case .dict = setVal { return scalars(from: setVal) }
                return nil
            }()
            let insert = str(d, "insert")
            return .button(label: str(d, "label"),
                           insert: insert.isEmpty ? nil : insert,
                           set: set,
                           style: str(d, "style"))
        case "field":
            return .field(key: str(d, "key"), placeholder: str(d, "placeholder"), value: str(d, "value"))
        case "vstack":
            return .vstack(try children(d), spacing: num(d, "spacing", 6))
        case "hstack":
            return .hstack(try children(d), spacing: num(d, "spacing", 6))
        case "grid":
            return .grid(try children(d), columns: Int(num(d, "columns", 4)), spacing: num(d, "spacing", 6))
        case "spacer":  return .spacer
        case "divider": return .divider
        default:
            throw PyError("unknown panel node '\(t)'")
        }
    }

    private static func children(_ d: PyDict) throws -> [PanelNode] {
        guard case .list(let l)? = d[.string("children")] else { return [] }
        return try l.items.map { try parseNode($0) }
    }

    private static func str(_ d: PyDict, _ key: String) -> String {
        if case .string(let s)? = d[.string(key)] { return s }
        return ""
    }

    private static func num(_ d: PyDict, _ key: String, _ fallback: Double) -> Double {
        switch d[.string(key)] {
        case .int(let i)?:    return Double(i)
        case .double(let x)?: return x
        default:              return fallback
        }
    }
}
