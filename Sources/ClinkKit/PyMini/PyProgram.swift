/**
 `PyProgram`: a parsed + loaded PyMini module whose top-level `def`s stay defined
 so its functions can be called many times on a warm interpreter — used by custom
 panels, which call `view(state)` again on every interaction. Each call resets the
 step budget and `print` buffer so one render can't be starved by an earlier one.
 

 Module: pymini · Target: ClinkKit
 Learn: docs/08-pymini.md
 */
import Foundation

/// The result of calling a function in a `PyProgram`.
struct PyCallResult {
    let value: PyValue?
    let error: String?
    let log: [String]
}

final class PyProgram {
    private let interp = PyInterpreter()
    /// A load-time (parse / top-level) error, or nil if the module loaded.
    let loadError: String?

    init(source: String) {
        var err: String?
        do {
            let program = try PyParser.parse(source)
            try interp.run(program)
        } catch let e as PyError {
            err = e.display
        } catch let flow as PyFlow {
            // A bare top-level return is harmless when loading a module.
            if case .returnValue = flow { err = nil } else { err = "control flow outside a loop" }
        } catch {
            err = "load error"
        }
        loadError = err
    }

    func has(_ name: String) -> Bool { interp.hasFunction(name) }

    func call(_ name: String, _ args: [PyValue]) -> PyCallResult {
        interp.resetBudget()
        interp.clearPrinted()
        do {
            let v = try interp.call(name, args)
            return PyCallResult(value: v, error: nil, log: interp.printed)
        } catch let e as PyError {
            return PyCallResult(value: nil, error: e.display, log: interp.printed)
        } catch {
            return PyCallResult(value: nil, error: "runtime error", log: interp.printed)
        }
    }
}
