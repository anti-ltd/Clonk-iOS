/**
 PyMini parser: recursive-descent over the token stream into an `[Stmt]` AST.
 Supports the subset documented in `PyInterpreter` — expressions with full
 operator precedence, f-strings, if/elif/else, while, for, def, and
 assignment / augmented assignment / tuple unpacking. Unsupported Python
 features (import, class, try, lambda, comprehensions, decorators) fail with a
 clear message rather than a cryptic syntax error.
 

 Module: pymini · Target: ClinkKit
 Learn: docs/08-pymini.md
 */
import Foundation

struct PyParser {
    private let tokens: [Token]
    private var i = 0

    init(_ tokens: [Token]) { self.tokens = tokens }

    /// Parse a complete module.
    static func parse(_ source: String) throws -> [Stmt] {
        var lexer = PyLexer(source)
        let toks = try lexer.tokenize()
        var parser = PyParser(toks)
        return try parser.parseProgram()
    }

    /// Parse a standalone expression (used for f-string embedded expressions).
    static func parseExpression(_ source: String) throws -> Expr {
        var lexer = PyLexer(source)
        let toks = try lexer.tokenize()
        var parser = PyParser(toks)
        parser.skipNewlines()
        let e = try parser.parseExpr()
        return e
    }

    // MARK: - Token cursor

    private var current: Token { tokens[i] }
    private var kind: Tok { tokens[i].kind }
    private var lineNo: Int { tokens[i].line }

    @discardableResult private mutating func advance() -> Token {
        let t = tokens[i]
        if i < tokens.count - 1 { i += 1 }
        return t
    }

    private func isOp(_ s: String) -> Bool { kind == .op(s) }
    private func isKeyword(_ s: String) -> Bool { kind == .keyword(s) }
    private var isEOF: Bool { kind == .eof }

    private mutating func matchOp(_ s: String) -> Bool {
        if isOp(s) { advance(); return true }; return false
    }
    private mutating func matchKeyword(_ s: String) -> Bool {
        if isKeyword(s) { advance(); return true }; return false
    }
    private mutating func expectOp(_ s: String) throws {
        guard matchOp(s) else { throw PyError("expected '\(s)'", line: lineNo) }
    }

    private mutating func skipNewlines() { while kind == .newline { advance() } }

    private mutating func expectStatementEnd() throws {
        if kind == .newline || kind == .eof { if kind == .newline { advance() }; return }
        throw PyError("unexpected token after statement", line: lineNo)
    }

    // MARK: - Program / blocks

    private mutating func parseProgram() throws -> [Stmt] {
        var stmts: [Stmt] = []
        skipNewlines()
        while !isEOF {
            stmts.append(try parseStatement())
            skipNewlines()
        }
        return stmts
    }

    private mutating func parseBlock() throws -> [Stmt] {
        try expectOp(":")
        if kind == .newline {
            advance()
            guard kind == .indent else { throw PyError("expected an indented block", line: lineNo) }
            advance()
            var stmts: [Stmt] = []
            skipNewlines()
            while kind != .dedent && !isEOF {
                stmts.append(try parseStatement())
                skipNewlines()
            }
            if kind == .dedent { advance() }
            if stmts.isEmpty { throw PyError("expected an indented block", line: lineNo) }
            return stmts
        }
        // Inline block: `if x: return 1` — full statement so return/break/pass work.
        return [try parseStatement()]
    }

    // MARK: - Statements

    private static let unsupported: Set<String> = [
        "import", "from", "class", "try", "with", "lambda", "global",
        "nonlocal", "assert", "del", "yield", "async", "await", "raise", "is",
    ]

    private mutating func parseStatement() throws -> Stmt {
        if case .keyword(let kw) = kind {
            switch kw {
            case "if":       return try parseIf()
            case "while":    return try parseWhile()
            case "for":      return try parseFor()
            case "def":      return try parseDef()
            case "return":   return try parseReturn()
            case "break":    let l = lineNo; advance(); try expectStatementEnd(); return .breakStmt(line: l)
            case "continue": let l = lineNo; advance(); try expectStatementEnd(); return .continueStmt(line: l)
            case "pass":     let l = lineNo; advance(); try expectStatementEnd(); return .passStmt(line: l)
            default: break
            }
        }
        if case .name(let n) = kind, Self.unsupported.contains(n) {
            throw PyError("'\(n)' is not supported in extension scripts", line: lineNo)
        }
        return try parseSimpleStatement()
    }

    private mutating func parseIf() throws -> Stmt {
        let l = lineNo
        advance() // if
        var branches: [(Expr, [Stmt])] = []
        let cond = try parseExpr()
        let body = try parseBlock()
        branches.append((cond, body))
        skipNewlines()
        while isKeyword("elif") {
            advance()
            let c = try parseExpr()
            let b = try parseBlock()
            branches.append((c, b))
            skipNewlines()
        }
        var elseBody: [Stmt]? = nil
        if isKeyword("else") {
            advance()
            elseBody = try parseBlock()
        }
        return .ifStmt(branches: branches, elseBody: elseBody, line: l)
    }

    private mutating func parseWhile() throws -> Stmt {
        let l = lineNo
        advance()
        let cond = try parseExpr()
        let body = try parseBlock()
        return .whileStmt(cond: cond, body: body, line: l)
    }

    private mutating func parseFor() throws -> Stmt {
        let l = lineNo
        advance()
        let target = try parseTargetList()
        guard matchKeyword("in") else { throw PyError("expected 'in' in for-loop", line: lineNo) }
        let iterable = try parseExpr()
        let body = try parseBlock()
        return .forStmt(target: target, iterable: iterable, body: body, line: l)
    }

    /// Parse a comma-separated assignment / loop target into a name or tuple.
    private mutating func parseTargetList() throws -> Expr {
        var items: [Expr] = [try parsePostfix()]
        var sawComma = false
        while isOp(",") {
            advance()
            sawComma = true
            if isKeyword("in") || isOp("=") { break }
            items.append(try parsePostfix())
        }
        if sawComma { return .tuple(items) }
        return items[0]
    }

    private mutating func parseDef() throws -> Stmt {
        let l = lineNo
        advance()
        guard case .name(let name) = kind else { throw PyError("expected function name", line: lineNo) }
        advance()
        try expectOp("(")
        var params: [PyFunction.Param] = []
        while !isOp(")") {
            guard case .name(let p) = kind else { throw PyError("expected parameter name", line: lineNo) }
            advance()
            var def: Expr? = nil
            if matchOp("=") { def = try parseExpr() }
            params.append(.init(name: p, defaultValue: def))
            if !matchOp(",") { break }
        }
        try expectOp(")")
        let body = try parseBlock()
        return .funcDef(name: name, params: params, body: body, line: l)
    }

    private mutating func parseReturn() throws -> Stmt {
        let l = lineNo
        advance()
        if kind == .newline || kind == .eof {
            try expectStatementEnd()
            return .returnStmt(nil, line: l)
        }
        let e = try parseExpr()
        try expectStatementEnd()
        return .returnStmt(e, line: l)
    }

    private static let augOps: [String: BinOp] = [
        "+=": .add, "-=": .sub, "*=": .mul, "/=": .div,
    ]

    private mutating func parseSimpleStatement() throws -> Stmt {
        let l = lineNo
        let first = try parseExprOrTuple()
        // Augmented assignment.
        if case .op(let o) = kind, let binop = Self.augOps[o] {
            advance()
            let value = try parseExpr()
            try expectStatementEnd()
            return .augAssign(target: first, op: binop, value: value, line: l)
        }
        // Plain / chained assignment: `a = b = value`. Every part before the
        // final `=` is a target; the last is the value.
        if isOp("=") {
            var parts: [Expr] = [first]
            while matchOp("=") {
                parts.append(try parseExprOrTuple())
            }
            let value = parts.removeLast()
            try expectStatementEnd()
            return .assign(targets: parts, value: value, line: l)
        }
        try expectStatementEnd()
        return .expr(first, line: l)
    }

    /// Parse an expression that may be a bare comma tuple (for `a, b = ...`).
    private mutating func parseExprOrTuple() throws -> Expr {
        let first = try parseExpr()
        if isOp(",") {
            var items = [first]
            while matchOp(",") {
                if isOp("=") || kind == .newline || kind == .eof { break }
                items.append(try parseExpr())
            }
            return .tuple(items)
        }
        return first
    }

    // MARK: - Expressions (precedence climbing)

    private mutating func parseExpr() throws -> Expr { try parseTernary() }

    private mutating func parseTernary() throws -> Expr {
        let value = try parseOr()
        if isKeyword("if") {
            advance()
            let cond = try parseOr()
            guard matchKeyword("else") else { throw PyError("expected 'else' in conditional expression", line: lineNo) }
            let orElse = try parseTernary()
            return .ternary(cond: cond, then: value, orElse: orElse)
        }
        return value
    }

    private mutating func parseOr() throws -> Expr {
        var left = try parseAnd()
        while matchKeyword("or") { left = .boolOp(.or, left, try parseAnd()) }
        return left
    }

    private mutating func parseAnd() throws -> Expr {
        var left = try parseNot()
        while matchKeyword("and") { left = .boolOp(.and, left, try parseNot()) }
        return left
    }

    private mutating func parseNot() throws -> Expr {
        if matchKeyword("not") { return .unary(.not, try parseNot()) }
        return try parseComparison()
    }

    private mutating func parseComparison() throws -> Expr {
        let left = try parseAdd()
        var pairs: [(CmpOp, Expr)] = []
        while true {
            var op: CmpOp? = nil
            if case .op(let o) = kind {
                switch o {
                case "==": op = .eq; case "!=": op = .ne
                case "<": op = .lt; case "<=": op = .le
                case ">": op = .gt; case ">=": op = .ge
                default: break
                }
            } else if isKeyword("in") {
                op = .inOp
            } else if isKeyword("not") {
                // `not in`
                if tokens[i + 1].kind == .keyword("in") { advance(); op = .notIn }
            }
            guard let op else { break }
            advance() // consume the operator (the `in` for notIn was already advanced past `not`)
            pairs.append((op, try parseAdd()))
        }
        if pairs.isEmpty { return left }
        return .compare(left, pairs)
    }

    private mutating func parseAdd() throws -> Expr {
        var left = try parseMul()
        while true {
            if matchOp("+") { left = .binary(.add, left, try parseMul()) }
            else if matchOp("-") { left = .binary(.sub, left, try parseMul()) }
            else { break }
        }
        return left
    }

    private mutating func parseMul() throws -> Expr {
        var left = try parseFactor()
        while true {
            if matchOp("*") { left = .binary(.mul, left, try parseFactor()) }
            else if matchOp("/") { left = .binary(.div, left, try parseFactor()) }
            else if matchOp("//") { left = .binary(.floordiv, left, try parseFactor()) }
            else if matchOp("%") { left = .binary(.mod, left, try parseFactor()) }
            else { break }
        }
        return left
    }

    private mutating func parseFactor() throws -> Expr {
        if matchOp("-") { return .unary(.neg, try parseFactor()) }
        if matchOp("+") { return .unary(.pos, try parseFactor()) }
        return try parsePower()
    }

    private mutating func parsePower() throws -> Expr {
        let base = try parsePostfix()
        if matchOp("**") {
            // Right-associative; exponent may carry its own unary sign.
            return .binary(.pow, base, try parseFactor())
        }
        return base
    }

    private mutating func parsePostfix() throws -> Expr {
        var e = try parseAtom()
        while true {
            if isOp("(") {
                e = try parseCall(e)
            } else if isOp("[") {
                e = try parseSubscript(e)
            } else if matchOp(".") {
                guard case .name(let attr) = kind else { throw PyError("expected attribute name", line: lineNo) }
                advance()
                e = .attribute(e, attr)
            } else {
                break
            }
        }
        return e
    }

    private mutating func parseCall(_ callee: Expr) throws -> Expr {
        advance() // (
        var args: [Expr] = []
        var kwargs: [(String, Expr)] = []
        while !isOp(")") {
            // kwarg: name = expr  (but not ==)
            if case .name(let n) = kind, tokens[i + 1].kind == .op("=") {
                advance(); advance()
                kwargs.append((n, try parseExpr()))
            } else {
                args.append(try parseExpr())
            }
            if !matchOp(",") { break }
        }
        try expectOp(")")
        return .call(callee: callee, args: args, kwargs: kwargs)
    }

    private mutating func parseSubscript(_ base: Expr) throws -> Expr {
        advance() // [
        var lower: Expr? = nil
        var isSlice = false
        if !isOp(":") { lower = try parseExpr() }
        var upper: Expr? = nil
        var step: Expr? = nil
        if isOp(":") {
            isSlice = true
            advance()
            if !isOp(":") && !isOp("]") { upper = try parseExpr() }
            if isOp(":") {
                advance()
                if !isOp("]") { step = try parseExpr() }
            }
        }
        try expectOp("]")
        if isSlice { return .slice(base, lower: lower, upper: upper, step: step) }
        guard let lower else { throw PyError("invalid subscript", line: lineNo) }
        return .index(base, lower)
    }

    private mutating func parseAtom() throws -> Expr {
        switch kind {
        case .int(let v):    advance(); return .intLit(v)
        case .double(let v): advance(); return .doubleLit(v)
        case .str(let s):    advance(); return .stringLit(s)
        case .fstring(let parts):
            advance()
            return try buildFString(parts)
        case .keyword("True"):  advance(); return .boolLit(true)
        case .keyword("False"): advance(); return .boolLit(false)
        case .keyword("None"):  advance(); return .noneLit
        case .name(let n):   advance(); return .name(n)
        case .op("("):       return try parseGroupOrTuple()
        case .op("["):       return try parseListLiteral()
        case .op("{"):       return try parseDictLiteral()
        default:
            throw PyError("unexpected token in expression", line: lineNo)
        }
    }

    private mutating func parseGroupOrTuple() throws -> Expr {
        advance() // (
        if isOp(")") { advance(); return .tuple([]) }
        let first = try parseExpr()
        if isOp(",") {
            var items = [first]
            while matchOp(",") {
                if isOp(")") { break }
                items.append(try parseExpr())
            }
            try expectOp(")")
            return .tuple(items)
        }
        try expectOp(")")
        return first
    }

    private mutating func parseListLiteral() throws -> Expr {
        advance() // [
        var items: [Expr] = []
        while !isOp("]") {
            items.append(try parseExpr())
            if !matchOp(",") { break }
        }
        try expectOp("]")
        return .list(items)
    }

    private mutating func parseDictLiteral() throws -> Expr {
        advance() // {
        var pairs: [(Expr, Expr)] = []
        while !isOp("}") {
            let key = try parseExpr()
            try expectOp(":")
            let value = try parseExpr()
            pairs.append((key, value))
            if !matchOp(",") { break }
        }
        try expectOp("}")
        return .dict(pairs)
    }

    private func buildFString(_ parts: [FRawPart]) throws -> Expr {
        var built: [FStringPart] = []
        for part in parts {
            switch part {
            case .lit(let s): built.append(.literal(s))
            case .expr(let src):
                let e = try PyParser.parseExpression(src)
                built.append(.expr(e))
            }
        }
        return .fstring(built)
    }
}
