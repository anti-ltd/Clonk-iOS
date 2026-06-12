/**
 PyEngine — the public facade over the PyMini lexer/parser/interpreter.

 The Clink extension contract: a script defines

     def transform(text):
         return text.upper()

 `text` is the action's input (the current word, clipboard, whole field, or "").
 The function's return value is `str()`-ified and inserted into the host
 document. Scripts may also `print(...)` for debugging — captured into `log` and
 shown in the in-app run console, never inserted.

 As a convenience for quick experiments, a script with no `transform` may instead
 assign a top-level `result` variable; its value is used as the output.
 

 Module: pymini · Target: ClinkKit
 Learn: docs/08-pymini.md
 */
import Foundation

/// The outcome of running an extension script.
public struct PyRunResult: Sendable {
    /// The text the action produces (already `str()`-ified). nil = insert nothing.
    public let output: String?
    /// A user-facing error (syntax or runtime), or nil on success.
    public let error: String?
    /// Lines emitted via `print(...)`.
    public let log: [String]

    public init(output: String?, error: String?, log: [String]) {
        self.output = output
        self.error = error
        self.log = log
    }

    public var isSuccess: Bool { error == nil }
}

public enum PyEngine {
    /// Parse + run `source` with `input` bound for `transform(text)`.
    /// Pure and synchronous; safe to call on the main thread (step-budget bounded).
    public static func run(source: String, input: String, maxSteps: Int = 2_000_000) -> PyRunResult {
        let program: [Stmt]
        do {
            program = try PyParser.parse(source)
        } catch let e as PyError {
            return PyRunResult(output: nil, error: "Syntax error — \(e.display)", log: [])
        } catch {
            return PyRunResult(output: nil, error: "Syntax error", log: [])
        }

        let interp = PyInterpreter(maxSteps: maxSteps)
        do {
            try interp.run(program)
            let result: PyValue
            if interp.hasFunction("transform") {
                result = try interp.call("transform", [.string(input)])
            } else if let r = interp.globals.get("result") {
                result = r
            } else {
                result = .none
            }
            let output: String? = { if case .none = result { return nil }; return pyStr(result) }()
            return PyRunResult(output: output, error: nil, log: interp.printed)
        } catch let e as PyError {
            return PyRunResult(output: nil, error: e.display, log: interp.printed)
        } catch let flow as PyFlow {
            // A bare top-level return/break/continue — treat its value as output.
            if case .returnValue(let v) = flow {
                return PyRunResult(output: pyStr(v), error: nil, log: interp.printed)
            }
            return PyRunResult(output: nil, error: "'break'/'continue' outside a loop", log: interp.printed)
        } catch {
            return PyRunResult(output: nil, error: "Runtime error", log: interp.printed)
        }
    }

    /// Parse-only check. Returns an error message, or nil if the syntax is valid.
    public static func validate(source: String) -> String? {
        do { _ = try PyParser.parse(source); return nil }
        catch let e as PyError { return e.display }
        catch { return "Syntax error" }
    }
}
