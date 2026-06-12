/**
 PyMini lexer: turns source text into a token stream with Python-style
 significant indentation (synthetic INDENT / DEDENT / NEWLINE tokens) and
 f-string segmentation. Newlines inside (), [], {} are ignored (implicit line
 joining); `#` starts a comment to end of line.
 

 Module: pymini · Target: ClinkKit
 Learn: docs/08-pymini.md
 */
import Foundation

/// One segment of an f-string as seen by the lexer; the embedded expression is
/// kept as raw source and parsed later by the parser.
enum FRawPart: Equatable {
    /// Literal text between `{...}` placeholders (after `{{`/`}}` unescaping).
    case lit(String)
    /// Raw source inside `{...}`, handed to `PyParser.parseExpression`.
    case expr(String)
}

/// Token kinds emitted by `PyLexer`. Python-style significant indentation is
/// expressed as synthetic `.indent` / `.dedent`; statement boundaries use `.newline`.
enum Tok: Equatable {
    case int(Int)
    case double(Double)
    case str(String)
    case fstring([FRawPart])
    case name(String)
    case keyword(String)
    case op(String)
    /// Ends a logical line (blank lines collapse to one).
    case newline
    /// Block opened — emitted when indentation increases.
    case indent
    /// Block closed — emitted when indentation decreases.
    case dedent
    case eof
}

/// A token plus its 1-based source line (for error messages).
struct Token {
    let kind: Tok
    let line: Int
}

private let pyKeywords: Set<String> = [
    "if", "elif", "else", "while", "for", "in", "def", "return",
    "break", "continue", "pass", "True", "False", "None", "and", "or", "not",
]

/// Tokenizes PyMini source into a stream the parser consumes. Handles
/// significant indentation, implicit line joining inside brackets, comments,
/// string/f-string literals, and Python-style numeric literals.
struct PyLexer {
    private let chars: [Character]
    private var pos = 0
    private var line = 1
    private var indentStack: [Int] = [0]
    private var bracketDepth = 0
    private var tokens: [Token] = []
    private var atLineStart = true

    init(_ source: String) {
        // Normalise newlines so \r\n / \r behave like \n.
        let normalised = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        self.chars = Array(normalised)
    }

    // Multi-char operators, longest first so `**`/`//`/`==` beat their prefixes.
    private static let multiOps = ["**", "//", "==", "!=", "<=", ">=", "+=", "-=", "*=", "/="]
    private static let singleOps = Set("+-*/%<>=(),:.[]{}")

    /// Scan the whole source. Throws `PyError` on bad indentation, unterminated
    /// strings, or unexpected characters. Always ends with `.eof`.
    mutating func tokenize() throws -> [Token] {
        while pos < chars.count {
            if atLineStart && bracketDepth == 0 {
                try handleLineStart()
                if pos >= chars.count { break }
            }
            let c = chars[pos]

            if c == "\n" {
                pos += 1
                line += 1
                if bracketDepth == 0 {
                    emitNewline()
                    atLineStart = true
                }
                continue
            }
            if c == " " || c == "\t" { pos += 1; continue }
            if c == "#" { skipComment(); continue }

            if c == "f" || c == "F", peek(1) == "\"" || peek(1) == "'" {
                try lexFString()
                continue
            }
            if c == "\"" || c == "'" { try lexString(); continue }
            if c.isNumber || (c == "." && (peek(1)?.isNumber ?? false)) { try lexNumber(); continue }
            if c.isLetter || c == "_" { lexIdentifier(); continue }

            try lexOperator()
        }
        // Close out any open indentation, then EOF.
        if !tokens.isEmpty, tokens.last?.kind != .newline { emitNewline() }
        while indentStack.count > 1 { indentStack.removeLast(); tokens.append(Token(kind: .dedent, line: line)) }
        tokens.append(Token(kind: .eof, line: line))
        return tokens
    }

    // MARK: - Indentation

    private mutating func handleLineStart() throws {
        var width = 0
        let lineStart = pos
        while pos < chars.count {
            let c = chars[pos]
            if c == " " { width += 1; pos += 1 }
            else if c == "\t" { width += 8 - (width % 8); pos += 1 }
            else { break }
        }
        // Blank line or comment-only line: not significant for indentation.
        if pos >= chars.count || chars[pos] == "\n" || chars[pos] == "#" {
            atLineStart = false
            // Let the main loop consume the newline / comment.
            _ = lineStart
            return
        }
        atLineStart = false
        let current = indentStack.last ?? 0
        if width > current {
            indentStack.append(width)
            tokens.append(Token(kind: .indent, line: line))
        } else if width < current {
            while let top = indentStack.last, width < top {
                indentStack.removeLast()
                tokens.append(Token(kind: .dedent, line: line))
            }
            if indentStack.last != width {
                throw PyError("inconsistent indentation", line: line)
            }
        }
    }

    private mutating func emitNewline() {
        // Collapse runs of blank lines into a single logical NEWLINE.
        if let last = tokens.last?.kind, last == .newline || last == .indent { return }
        if tokens.isEmpty { return }
        tokens.append(Token(kind: .newline, line: line))
    }

    private mutating func skipComment() {
        while pos < chars.count, chars[pos] != "\n" { pos += 1 }
    }

    // MARK: - Literals

    private mutating func lexNumber() throws {
        var s = ""
        var isDouble = false
        while pos < chars.count {
            let c = chars[pos]
            if c.isNumber { s.append(c); pos += 1 }
            else if c == "_" { pos += 1 } // digit grouping
            else if c == "." { isDouble = true; s.append(c); pos += 1 }
            else if c == "e" || c == "E" {
                isDouble = true; s.append(c); pos += 1
                if pos < chars.count, chars[pos] == "+" || chars[pos] == "-" { s.append(chars[pos]); pos += 1 }
            } else { break }
        }
        if isDouble {
            guard let d = Double(s) else { throw PyError("invalid number '\(s)'", line: line) }
            tokens.append(Token(kind: .double(d), line: line))
        } else if let i = Int(s) {
            tokens.append(Token(kind: .int(i), line: line))
        } else if let d = Double(s) {
            tokens.append(Token(kind: .double(d), line: line))
        } else {
            throw PyError("invalid number '\(s)'", line: line)
        }
    }

    private mutating func lexString() throws {
        let quote = chars[pos]
        pos += 1
        let s = try scanStringBody(quote: quote)
        tokens.append(Token(kind: .str(s), line: line))
    }

    /// Scan a string body up to the closing `quote`, applying escapes. Assumes
    /// the opening quote was already consumed.
    private mutating func scanStringBody(quote: Character) throws -> String {
        var s = ""
        while pos < chars.count {
            let c = chars[pos]
            if c == "\\" {
                pos += 1
                guard pos < chars.count else { break }
                s += escape(chars[pos])
                pos += 1
            } else if c == quote {
                pos += 1
                return s
            } else if c == "\n" {
                throw PyError("unterminated string", line: line)
            } else {
                s.append(c)
                pos += 1
            }
        }
        throw PyError("unterminated string", line: line)
    }

    /// Apply a string escape. Unrecognized escapes keep the backslash, matching
    /// Python (e.g. `"\_"` stays `\_`) — so the shrug ¯\_(ツ)_/¯ survives.
    private func escape(_ c: Character) -> String {
        switch c {
        case "n": return "\n"
        case "t": return "\t"
        case "r": return "\r"
        case "0": return "\0"
        case "\\": return "\\"
        case "'": return "'"
        case "\"": return "\""
        default: return "\\" + String(c)
        }
    }

    /// Lex `f"..."` into segments. `{{`/`}}` are literal braces; `{ expr }` holds
    /// raw expression source (parsed later). A `:format` spec after the expr is
    /// not supported and is dropped with the expr kept.
    private mutating func lexFString() throws {
        pos += 1 // consume f/F
        let quote = chars[pos]
        pos += 1
        var parts: [FRawPart] = []
        var lit = ""
        while pos < chars.count {
            let c = chars[pos]
            if c == "\\" {
                pos += 1
                if pos < chars.count { lit += escape(chars[pos]); pos += 1 }
                continue
            }
            if c == quote { pos += 1
                if !lit.isEmpty { parts.append(.lit(lit)) }
                tokens.append(Token(kind: .fstring(parts), line: line))
                return
            }
            if c == "{" {
                if peek(1) == "{" { lit.append("{"); pos += 2; continue }
                if !lit.isEmpty { parts.append(.lit(lit)); lit = "" }
                pos += 1
                var exprSrc = ""
                var depth = 1
                while pos < chars.count, depth > 0 {
                    let e = chars[pos]
                    if e == "{" { depth += 1 }
                    else if e == "}" { depth -= 1; if depth == 0 { break } }
                    if depth > 0 { exprSrc.append(e) }
                    pos += 1
                }
                guard pos < chars.count else { throw PyError("unterminated f-string expression", line: line) }
                pos += 1 // consume closing }
                // Drop any :format spec — keep the expression itself.
                if let colon = exprSrc.firstIndex(of: ":") { exprSrc = String(exprSrc[..<colon]) }
                parts.append(.expr(exprSrc.trimmingCharacters(in: .whitespaces)))
                continue
            }
            if c == "}" {
                if peek(1) == "}" { lit.append("}"); pos += 2; continue }
                throw PyError("single '}' in f-string", line: line)
            }
            if c == "\n" { throw PyError("unterminated string", line: line) }
            lit.append(c)
            pos += 1
        }
        throw PyError("unterminated string", line: line)
    }

    private mutating func lexIdentifier() {
        var s = ""
        while pos < chars.count, chars[pos].isLetter || chars[pos].isNumber || chars[pos] == "_" {
            s.append(chars[pos]); pos += 1
        }
        if pyKeywords.contains(s) { tokens.append(Token(kind: .keyword(s), line: line)) }
        else { tokens.append(Token(kind: .name(s), line: line)) }
    }

    private mutating func lexOperator() throws {
        // Try two-char operators first.
        if pos + 1 < chars.count {
            let two = String(chars[pos]) + String(chars[pos + 1])
            if Self.multiOps.contains(two) {
                tokens.append(Token(kind: .op(two), line: line))
                pos += 2
                return
            }
        }
        let c = chars[pos]
        guard Self.singleOps.contains(c) else {
            throw PyError("unexpected character '\(c)'", line: line)
        }
        switch c {
        case "(", "[", "{": bracketDepth += 1
        case ")", "]", "}": bracketDepth = max(0, bracketDepth - 1)
        default: break
        }
        tokens.append(Token(kind: .op(String(c)), line: line))
        pos += 1
    }

    private func peek(_ n: Int) -> Character? {
        let i = pos + n
        return i < chars.count ? chars[i] : nil
    }
}
