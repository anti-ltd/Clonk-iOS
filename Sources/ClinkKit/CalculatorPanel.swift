/**
 `CalculatorPanel`: full-keyboard overlay calculator. Evaluates arithmetic
 expressions and lets the user insert the result into the host document.
 No manager needed — purely stateless computation.
 */
import SwiftUI

/// Full-keyboard overlay showing a standard calculator. The user taps the
/// return button to insert the current display value into the host document.
struct CalculatorPanel: View {
    let theme: Theme
    let cornerRadius: CGFloat
    let onInsert: (String) -> Void
    let onCopy: (String) -> Void
    let onSaveToClipboard: (String) -> Void
    let onDismiss: () -> Void
    /// Top-left "back" action; nil leaves the leading icon decorative.
    var onBack: (() -> Void)? = nil

    @State private var display = "0"
    @State private var storedValue: Double? = nil
    @State private var pendingOp: CalcOp? = nil
    @State private var freshInput = true

    private enum CalcOp { case add, sub, mul, div }

    private let layout: [[String]] = [
        ["C", "±", "%", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
    ]

    private var isGlass: Bool { theme.material == .liquidGlass }
    /// Spacing between cells — glass uses real gaps so adjacent cells merge/round;
    /// solid uses 0 so the pixel-border grid reads flush.
    private var cellSpacing: CGFloat { isGlass ? 6 : 0 }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            GeometryReader { geo in
                // Account for the edge inset so cells don't overflow the container.
                let edgePad: CGFloat = isGlass ? cellSpacing / 2 : 0
                let innerW = geo.size.width - edgePad * 2
                let innerH = geo.size.height - edgePad * 2
                let cw = (innerW - cellSpacing * 3) / 4
                let rh = (innerH - cellSpacing * 4) / 5
                gridContent(cw: cw, rh: rh)
                    .padding(edgePad)
            }
        }
    }

    // MARK: - Grid

    @ViewBuilder private func gridContent(cw: CGFloat, rh: CGFloat) -> some View {
        let grid = VStack(spacing: cellSpacing) {
            ForEach(0..<4, id: \.self) { r in
                HStack(spacing: cellSpacing) {
                    ForEach(layout[r], id: \.self) { label in
                        calcBtn(label, w: cw, h: rh)
                    }
                }
            }
            HStack(spacing: cellSpacing) {
                calcBtn("0", w: cw * 2 + cellSpacing, h: rh)
                calcBtn(".", w: cw, h: rh)
                calcBtn("=", w: cw, h: rh)
            }
        }
        if isGlass, #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: cellSpacing) { grid }
        } else {
            grid
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 0) {
            PanelLeadingIcon("numbers.rectangle", theme: theme, onBack: onBack)
            headerDivider
            Text(display)
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.keyText.color)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
            headerDivider
            headerButton("return", tooltip: "Insert") {
                guard display != "Error" else { return }
                onInsert(display)
            }
            headerDivider
            headerButton("doc.on.doc", tooltip: "Copy") {
                guard display != "Error" else { return }
                onCopy(display)
            }
            headerDivider
            headerButton("tray.and.arrow.down", tooltip: "Save to history") {
                guard display != "Error" else { return }
                onSaveToClipboard(display)
            }
            headerDivider
            headerButton("xmark", tooltip: "Dismiss", action: onDismiss)
        }
        .frame(height: KeyboardCanvas.Metrics.suggestionBarHeight)
    }

    private func headerButton(_ symbol: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.keyText.color.opacity(0.5))
                .frame(width: 22, height: 22)
                .frame(width: 44, height: KeyboardCanvas.Metrics.suggestionBarHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var headerDivider: some View {
        Rectangle()
            .fill(theme.keyText.color.opacity(0.15))
            .frame(width: 0.5)
            .padding(.vertical, 11)
    }

    // MARK: - Buttons

    private func calcBtn(_ label: String, w: CGFloat, h: CGFloat) -> some View {
        Button { handleTap(label) } label: {
            btnBody(label)
                .frame(width: w, height: h)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func btnBody(_ label: String) -> some View {
        if isGlass, #available(iOS 26.0, *) {
            glassCell(label)
        } else {
            solidCell(label)
        }
    }

    // MARK: Glass cell

    @available(iOS 26.0, *)
    private func glassCell(_ label: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let g: Glass = {
            var base: Glass = theme.glassVariant == .clear ? .clear : .regular
            base = base.interactive()
            if let tint = glassTint(label) { base = base.tint(tint) }
            return base
        }()
        return Text(label)
            .font(.system(size: 20, weight: isOperator(label) ? .semibold : .regular))
            .foregroundStyle(btnFg(label))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(g, in: shape)
    }

    private func glassTint(_ label: String) -> Color? {
        switch label {
        case "=":
            return theme.accent.color
        case "÷", "×", "−", "+":
            return theme.accent.color.opacity(theme.glassTintStrength * 0.55)
        case "C", "±", "%":
            return theme.specialKeyFill.color.opacity(theme.glassTintStrength)
        default:
            return theme.keyFill.color.opacity(theme.glassTintStrength)
        }
    }

    // MARK: Solid cell

    private func solidCell(_ label: String) -> some View {
        ZStack {
            btnBg(label)
            Text(label)
                .font(.system(size: 20, weight: isOperator(label) ? .semibold : .regular))
                .foregroundStyle(btnFg(label))
        }
        .overlay(
            Rectangle()
                .stroke(theme.keyText.color.opacity(0.08), lineWidth: 0.5)
        )
    }

    @ViewBuilder private func btnBg(_ label: String) -> some View {
        switch label {
        case "=":
            theme.accent.color
        case "÷", "×", "−", "+":
            theme.accent.color.opacity(0.18)
        case "C", "±", "%":
            theme.keyText.color.opacity(0.12)
        default:
            theme.keyFill.color
        }
    }

    private func btnFg(_ label: String) -> Color {
        if label == "=" { return .white }
        if isOperator(label) { return theme.accent.color }
        return theme.keyText.color
    }

    private func isOperator(_ label: String) -> Bool {
        ["÷", "×", "−", "+", "="].contains(label)
    }

    // MARK: - Logic

    private func handleTap(_ label: String) {
        if display == "Error" {
            if label == "C" {
                display = "0"; storedValue = nil; pendingOp = nil; freshInput = true
            } else if label.first?.isNumber == true {
                display = label; freshInput = false
            }
            return
        }
        switch label {
        case "C":
            display = "0"; storedValue = nil; pendingOp = nil; freshInput = true
        case "±":
            if let v = Double(display) { display = format(-v) }
        case "%":
            if let v = Double(display) { display = format(v / 100) }
        case "÷": setOp(.div)
        case "×": setOp(.mul)
        case "−": setOp(.sub)
        case "+": setOp(.add)
        case "=": evaluate()
        case ".":
            if freshInput { display = "0."; freshInput = false; return }
            if !display.contains(".") { display += "." }
        default:
            if freshInput { display = label; freshInput = false }
            else if display == "0" { display = label }
            else if display.count < 12 { display += label }
        }
    }

    private func setOp(_ op: CalcOp) {
        if let stored = storedValue, let current = Double(display), !freshInput {
            let chained = applyOp(stored, pendingOp, current)
            display = format(chained)
            storedValue = chained.isNaN ? nil : chained
        } else {
            storedValue = Double(display)
        }
        pendingOp = op
        freshInput = true
    }

    private func evaluate() {
        guard let stored = storedValue, let op = pendingOp,
              let current = Double(display) else { return }
        let result = applyOp(stored, op, current)
        display = format(result)
        storedValue = nil
        pendingOp = nil
        freshInput = true
    }

    private func applyOp(_ a: Double, _ op: CalcOp?, _ b: Double) -> Double {
        switch op {
        case .add: return a + b
        case .sub: return a - b
        case .mul: return a * b
        case .div: return b == 0 ? .nan : a / b
        case nil:  return b
        }
    }

    private func format(_ v: Double) -> String {
        if v.isNaN || v.isInfinite { return "Error" }
        if v.truncatingRemainder(dividingBy: 1) == 0 && abs(v) < 1e15 {
            return String(format: "%.0f", v)
        }
        return String(format: "%.8g", v)
    }
}
