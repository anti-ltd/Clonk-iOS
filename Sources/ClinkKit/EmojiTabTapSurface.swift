/**
 UIKit tap surface for the scrollable emoji category tab bar. Handles taps on
 the tab strip independently of SwiftUI's gesture stack to avoid scroll conflicts.
 

 Module: emoji · Target: ClinkKit
 Learn: docs/05-emoji.md
 */
import SwiftUI
import UIKit

// MARK: - Scrollable tab tap surface
//
// Rides *inside* the horizontal scroll content (so its frames stay valid as the
// strip scrolls) and tells a tap from a drag: a quick touch-up with little
// movement selects the tile under it, while any real drag is left to the scroll
// view's pan (which cancels our touch). This is why the strip scrolls where a
// SwiftUI Button — which claims the horizontal drag — would not.

@MainActor
final class EmojiTabTapView: UIView {
    var frames: [Int: CGRect] = [:]
    var onPress: (Int) -> Void = { _ in }
    var onRelease: () -> Void = {}
    var onCommit: (Int) -> Void = { _ in }

    private var startPoint: CGPoint = .zero
    private var moved = false
    private var pressedID: Int?

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func tile(at p: CGPoint) -> Int? {
        frames.first { $0.value.contains(p) }?.key
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        moved = false
        startPoint = p
        pressedID = tile(at: p)
        if let id = pressedID { onPress(id) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !moved, let p = touches.first?.location(in: self) else { return }
        // Past the slop it's a scroll, not a tap — drop the press and let the
        // scroll view's pan take over.
        if abs(p.x - startPoint.x) > 10 || abs(p.y - startPoint.y) > 10 {
            moved = true
            pressedID = nil
            onRelease()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !moved, let id = pressedID { onCommit(id) }
        pressedID = nil
        onRelease()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        moved = true
        pressedID = nil
        onRelease()
    }
}

/// UIKit tap surface for the scrollable category strip. Distinguishes tap from
/// horizontal drag so the `ScrollView` can pan without swallowing tab selection.
struct EmojiTabTapSurface: UIViewRepresentable {
    let frames: [Int: CGRect]
    let onPress: (Int) -> Void
    let onRelease: () -> Void
    let onCommit: (Int) -> Void

    func makeUIView(context: Context) -> EmojiTabTapView {
        let v = EmojiTabTapView()
        apply(to: v)
        return v
    }

    func updateUIView(_ uiView: EmojiTabTapView, context: Context) { apply(to: uiView) }

    private func apply(to v: EmojiTabTapView) {
        v.frames = frames
        v.onPress = onPress
        v.onRelease = onRelease
        v.onCommit = onCommit
    }
}
