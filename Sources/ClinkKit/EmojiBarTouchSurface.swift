/**
 UIKit tap surface for the emoji suggestion bar. `EmojiBarTouchSurface` /
 `EmojiBarTouchView` handle raw touches on the horizontal emoji-bar strip,
 bypassing SwiftUI's gesture recogniser stack. Also defines `EmojiBarFrameKey`.
 */
import SwiftUI
import UIKit

// MARK: - UIKit tap surface for the emoji bar
//
// Mirrors the letter keyboard's `MultiTouchSurface`: SwiftUI publishes each
// tile's frame, and this bare UIView hit-tests a touch to the nearest tile and
// fires on touch-down — reliable where SwiftUI's own button taps are not.

/// Publishes each category tile's frame (in scroll-content space) so the tab tap
/// surface can resolve which tile a touch landed on.
struct EmojiBarFrameKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

@MainActor
final class EmojiBarTouchView: UIView {
    var frames: [Int: CGRect] = [:]
    var onHit: (Int) -> Void = { _ in }

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        var best: Int?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for (id, f) in frames {
            if f.contains(p) { onHit(id); return }
            let dx = p.x - f.midX, dy = p.y - f.midY
            let d = dx * dx + dy * dy
            if d < bestDist { bestDist = d; best = id }
        }
        if let best { onHit(best) }
    }
}

struct EmojiBarTouchSurface: UIViewRepresentable {
    let frames: [Int: CGRect]
    let onHit: (Int) -> Void

    func makeUIView(context: Context) -> EmojiBarTouchView {
        let v = EmojiBarTouchView()
        v.frames = frames
        v.onHit = onHit
        return v
    }

    func updateUIView(_ uiView: EmojiBarTouchView, context: Context) {
        uiView.frames = frames
        uiView.onHit = onHit
    }
}
