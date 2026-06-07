/**
 PyMini abstract syntax tree: `Expr` (expressions) and `Stmt` (statements),
 plus the operator enums the parser produces and the interpreter walks.
 */
import Foundation

enum BinOp { case add, sub, mul, div, floordiv, mod, pow }
enum CmpOp { case eq, ne, lt, le, gt, ge, inOp, notIn }
enum UnOp { case neg, pos, not }
enum BoolKind { case and, or }

/// One segment of an f-string: a literal run or an embedded expression.
enum FStringPart {
    case literal(String)
    case expr(Expr)
}

indirect enum Expr {
    case noneLit
    case boolLit(Bool)
    case intLit(Int)
    case doubleLit(Double)
    case stringLit(String)
    case fstring([FStringPart])
    case name(String)
    case list([Expr])
    case dict([(Expr, Expr)])
    case unary(UnOp, Expr)
    case binary(BinOp, Expr, Expr)
    case boolOp(BoolKind, Expr, Expr)
    /// Chained comparison: `left op a op b …` → (left, [(op, rhs), …]).
    case compare(Expr, [(CmpOp, Expr)])
    case ternary(cond: Expr, then: Expr, orElse: Expr)
    case call(callee: Expr, args: [Expr], kwargs: [(String, Expr)])
    case index(Expr, Expr)
    case slice(Expr, lower: Expr?, upper: Expr?, step: Expr?)
    case attribute(Expr, String)
    /// A bare comma list on the LHS of `=` (tuple unpacking target) or in a
    /// `for a, b in …` target.
    case tuple([Expr])
}

indirect enum Stmt {
    case expr(Expr, line: Int)
    /// `a = b = value` → targets = [a, b].
    case assign(targets: [Expr], value: Expr, line: Int)
    case augAssign(target: Expr, op: BinOp, value: Expr, line: Int)
    case ifStmt(branches: [(Expr, [Stmt])], elseBody: [Stmt]?, line: Int)
    case whileStmt(cond: Expr, body: [Stmt], line: Int)
    case forStmt(target: Expr, iterable: Expr, body: [Stmt], line: Int)
    case funcDef(name: String, params: [PyFunction.Param], body: [Stmt], line: Int)
    case returnStmt(Expr?, line: Int)
    case breakStmt(line: Int)
    case continueStmt(line: Int)
    case passStmt(line: Int)
}

extension Stmt {
    var line: Int {
        switch self {
        case .expr(_, let l), .assign(_, _, let l), .augAssign(_, _, _, let l),
             .ifStmt(_, _, let l), .whileStmt(_, _, let l), .forStmt(_, _, _, let l),
             .funcDef(_, _, _, let l), .returnStmt(_, let l),
             .breakStmt(let l), .continueStmt(let l), .passStmt(let l):
            return l
        }
    }
}
