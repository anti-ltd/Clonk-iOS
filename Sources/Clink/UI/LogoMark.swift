import SwiftUI

/// Vector Clink mark — a squircle tile with the lowercase "c" knocked out.
/// Monochrome: the whole glyph renders in `color`, so it picks up the theme
/// accent at the call site. Scales to any size. SVG source: Resources/clink-logo.svg
///
/// `cornerFraction` is the key roundness ratio (keyCornerRadius / keyHeight) so the
/// tile corners and the arc end-caps track the keyboard's Roundness setting:
/// sharp keys → square corners + square arc caps, round keys → round both.
struct LogoMark: View {
    var color: Color
    var cornerFraction: CGFloat = 0.28

    private var f: CGFloat { min(max(cornerFraction, 0), 0.5) }
    private var lineCap: CGLineCap { f >= 0.18 ? .round : .square }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * f, style: .continuous)
                    .fill(color)
                CArc()
                    .stroke(style: StrokeStyle(lineWidth: s * 0.13, lineCap: lineCap))
                    .blendMode(.destinationOut)
            }
            .frame(width: s, height: s)
            .compositingGroup()
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The "c": a thick arc open on the right side, drawn relative to the frame.
private struct CArc: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = s * 0.24
        var p = Path()
        // Arc 44°..316° through 180°/left — gap on the right (the "c" mouth).
        p.addArc(center: c,
                 radius: r,
                 startAngle: .degrees(44),
                 endAngle: .degrees(316),
                 clockwise: false)
        return p
    }
}
