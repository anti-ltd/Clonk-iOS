/**
 `SwipeRow<Content, Background>`: a swipe-to-reveal list row for the clipboard
 and notepad history screens. Reveal pans left to show tappable action buttons;
 the content is any SwiftUI view over any background shape.
 */
import SwiftUI
import UIKit

private struct VisibleKey: PreferenceKey {
    static let defaultValue: CGFloat = 1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct RowWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A trailing action revealed by swiping a `SwipeRow` left.
public struct SwipeAction: Identifiable {
    public let id = UUID()
    public let icon: String
    public let label: String
    public let tint: Color
    public let action: () -> Void

    public init(icon: String, label: String, tint: Color, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.tint = tint
        self.action = action
    }
}

/// Swipe-to-reveal row. Dragging shrinks the card from the right (its text stays
/// left-aligned and visible) and pops in circular `actions`.
///
/// The card is split in two so liquid glass composites correctly: `cardBackground`
/// (the glass/solid surface) lives *inside* the per-row `GlassEffectContainer`
/// with the action circles — so card and the nearest circle stretch into a gooey
/// bridge — while `content` (the text) is drawn as an overlay *above* the glass,
/// staying crisp. `SwipeRow` owns the row tap (`onTap`) so it can swallow it while
/// open or mid-swipe. Works anywhere (not just `List`).
public struct SwipeRow<Content: View, Background: View>: View {
    private let id: Int
    private let actions: [SwipeAction]
    private let cornerRadius: CGFloat
    private let glass: Bool
    /// When true the row reveals on a *rightward* swipe with the actions anchored
    /// to the leading edge — a horizontal mirror of the default. Used by the
    /// clipboard grid's right column so its actions open toward the centre gutter.
    /// Only the anchoring, gesture direction, and reveal order flip; the open
    /// magnitude (`offset`/`slid`) and the glass-morph math are identical.
    private let mirror: Bool
    /// Inset (pt) pulling the revealed action strip in from the open edge, so the
    /// outermost button isn't flush against (or clipped by) the row's edge. 0 for
    /// the full-width list; the clipboard grid uses a few points so the buttons sit
    /// comfortably inside each clipped cell.
    private let actionInset: CGFloat
    private let onTap: (() -> Void)?
    private let cardBackground: Background
    private let content: Content
    // Shared "which row is open" — opening this row closes any other.
    @Binding private var openID: Int?
    // Scroll viewport tracking (optional): coordinate-space name + visible height.
    // When `viewportHeight <= 0` the scroll-away close is disabled.
    private let scrollSpace: String?
    private let viewportHeight: CGFloat

    @State private var offset: CGFloat = 0
    // Base offset captured when a horizontal drag engages; nil when not dragging.
    @State private var dragStart: CGFloat? = nil
    // 1 = fully in the viewport, 0 = scrolled out.
    @State private var visible: CGFloat = 1
    // Row width, captured for right-edge swipe gating.
    @State private var rowWidth: CGFloat = 0

    private let slotWidth: CGFloat
    private let circle: CGFloat
    private let lensDelay: CGFloat = 22
    private let edgeGrab: CGFloat = 50

    public init(id: Int = 0,
                cornerRadius: CGFloat = 14,
                actions: [SwipeAction],
                glass: Bool = false,
                mirror: Bool = false,
                actionInset: CGFloat = 0,
                slotWidth: CGFloat = 56,
                circle: CGFloat = 40,
                openID: Binding<Int?> = .constant(nil),
                scrollSpace: String? = nil,
                viewportHeight: CGFloat = 0,
                onTap: (() -> Void)? = nil,
                @ViewBuilder cardBackground: () -> Background,
                @ViewBuilder content: () -> Content) {
        self.id = id
        self.cornerRadius = cornerRadius
        self.actions = actions
        self.glass = glass
        self.mirror = mirror
        self.slotWidth = slotWidth
        self.circle = circle
        self.actionInset = actionInset
        self._openID = openID
        self.scrollSpace = scrollSpace
        self.viewportHeight = viewportHeight
        self.onTap = onTap
        self.cardBackground = cardBackground()
        self.content = content()
    }

    private var openWidth: CGFloat { CGFloat(actions.count) * slotWidth }
    /// Full drag distance: the circle region plus `lensDelay`, so the last
    /// (leftmost) lens still reaches full size once the card is fully open.
    private var openDistance: CGFloat { openWidth + lensDelay }

    public var body: some View {
        // Scale the open amount by visibility so the card eases closed as it
        // scrolls out of view — but not while actively dragging, or scroll jitter
        // would feed back into the drag and stutter it.
        let v = dragStart == nil ? visible : 1
        let slid = -clamp(offset) * v

        // Foreground: the card text (sizes the row) plus a clear spacer carving
        // out the right gap. Living OUTSIDE the glass container keeps it crisp,
        // and the clear spacer isn't hit-testable, so taps in the gap reach the
        // action circles behind it.
        HStack(spacing: 0) {
            // Mirror: the vacated gap sits on the leading side so the card shrinks
            // from the left and actions reveal there.
            if mirror { Color.clear.frame(width: slid) }
            content
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    if offset != 0 { close() } else { onTap?() }
                }
                // Tall transparent grab band so the swipe keeps tracking through
                // vertical drift.
                .background {
                    Color.clear
                        .padding(.vertical, -28)
                        .contentShape(Rectangle())
                }
            if !mirror { Color.clear.frame(width: slid) }
        }
        .background {
            ZStack(alignment: mirror ? .leading : .trailing) {
                // Glass layer: card surface + circle lenses in one container so they
                // morph into a gooey bridge; sized to the foreground's height.
                glassWrap(
                    ZStack(alignment: mirror ? .leading : .trailing) {
                        lensStrip(slid: slid)
                            .frame(width: openWidth)
                            .padding(mirror ? .leading : .trailing, actionInset)
                        cardBackground
                            .frame(maxWidth: .infinity)
                            // Color-shifting glow on the card's inner open-side edge
                            // to mask a lens as it emerges; clipped to the card so it
                            // never spills outside.
                            .overlay(alignment: mirror ? .leading : .trailing) { edgeGlow(slid: slid) }
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                            .padding(mirror ? .leading : .trailing, slid)
                    }
                    // Expand the clip so a circle's press-morph isn't cut off.
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).inset(by: -14))
                )
                // Glyphs ride ABOVE the glass, animating their own size/opacity so
                // they stay crisp and centered while the lens does its gooey morph.
                glyphStrip(slid: slid)
                    .frame(width: openWidth)
                    .padding(mirror ? .leading : .trailing, actionInset)
            }
        }
        // Transparent tap targets over the circle positions, in the FRONT so taps
        // land reliably (Buttons inside the background glass container can miss).
        // Only present while open so they don't block the closed card or scroll.
        .overlay(alignment: mirror ? .leading : .trailing) {
            if slid > 1 {
                HStack(spacing: 0) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { _, action in
                        Button {
                            action.action()
                            close()
                        } label: {
                            Color.clear.contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(action.label)
                        .frame(width: slotWidth)
                        .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: openWidth)
                .padding(mirror ? .leading : .trailing, actionInset)
            }
        }
        // Track how much of the row is in the scroll viewport, and its width.
        .background {
            GeometryReader { geo in
                Color.clear
                    .preference(key: VisibleKey.self, value: visibleFraction(geo))
                    .preference(key: RowWidthKey.self, value: geo.size.width)
            }
        }
        .onPreferenceChange(RowWidthKey.self) { rowWidth = $0 }
        .onPreferenceChange(VisibleKey.self) { f in
            // Track scroll position directly — scroll already gives continuous
            // frames, so the card eases closed as it leaves the viewport.
            visible = f
            // Once mostly out of view, commit it closed so it doesn't reopen on
            // scroll-back. Never while dragging.
            if dragStart == nil && f < 0.6 && offset != 0 {
                offset = 0
                if openID == id { openID = nil }
            }
        }
        // Another row opened — close this one.
        .onChange(of: openID) { _, newValue in
            if newValue != id && offset != 0 {
                withAnimation(.smooth(duration: 0.25)) { offset = 0 }
            }
        }
        // The swipe lives on the whole (stable, full-width) row, NOT the card
        // content: the card shrinks as it opens, so a gesture bound to it would
        // slide under the finger and feed back into the drag (the right-column
        // stagger). The outer row never moves, so translation stays clean for both
        // directions. `startLocation` is in row space, matching the edge gating.
        .simultaneousGesture(swipeGesture)
    }

    /// Fraction of the row inside the scroll viewport (1 fully in … 0 fully out).
    private func visibleFraction(_ geo: GeometryProxy) -> CGFloat {
        guard viewportHeight > 0, let scrollSpace else { return 1 }
        let r = geo.frame(in: .named(scrollSpace))
        guard r.height > 0 else { return 1 }
        let top = max(r.minY, 0)
        let bottom = min(r.maxY, viewportHeight)
        return max(0, min(1, (bottom - top) / r.height))
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                // `offset` is always negative when open (the open *magnitude*); for
                // a mirror row a rightward drag opens, so negate its translation so
                // the same negative-offset math drives both directions.
                let tx = mirror ? -value.translation.width : value.translation.width
                // Engage only on a predominantly-horizontal drag so vertical
                // scrolling still works; once engaged, keep tracking live.
                if dragStart == nil {
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    // Only engage from the card's (current) open-side edge so the
                    // rest of the card scrolls the list freely: the right edge
                    // normally, the left edge when mirrored.
                    let cardWidth = rowWidth + clamp(offset)   // rowWidth - slid
                    let nearOpenEdge = mirror
                        ? value.startLocation.x < (rowWidth - cardWidth) + edgeGrab
                        : value.startLocation.x > cardWidth - edgeGrab
                    guard rowWidth == 0 || nearOpenEdge else { return }
                    dragStart = offset
                    // Claim the open slot as the swipe begins, so an already-open
                    // card animates closed in sync as this one opens.
                    openID = id
                }
                offset = clamp((dragStart ?? 0) + tx)
            }
            .onEnded { value in
                let base = dragStart ?? offset
                dragStart = nil
                // Decide open/close from the velocity-projected end so a fast flick
                // opens even if it didn't travel past halfway. `offset` already
                // holds the release position, so it animates smoothly from there.
                let ptx = mirror ? -value.predictedEndTranslation.width : value.predictedEndTranslation.width
                let projected = base + ptx
                let willOpen = projected < -openDistance / 2
                withAnimation(.smooth(duration: 0.25)) {
                    offset = willOpen ? -openDistance : 0
                }
                // Opening this row makes it the sole open row.
                if willOpen { openID = id }
                else if openID == id { openID = nil }
            }
    }

    /// Wrap the glass layer (card surface + circles) in one `GlassEffectContainer`
    /// when the theme is glass, so card and nearest circle stretch into a gooey
    /// liquid bridge as the card is dragged open.
    @ViewBuilder private func glassWrap(_ layer: some View) -> some View {
        if glass, #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 14) { layer }
        } else {
            layer
        }
    }

    /// The tappable circle lenses (no glyph). The enclosing `glassWrap` container
    /// drives the gooey morph between them and the card.
    @ViewBuilder private func lensStrip(slid: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { idx, action in
                let p = lensReveal(slid: slid, index: idx)
                // Only render once its slot starts to uncover — the glass union
                // ignores `opacity(0)`, so an un-revealed lens would show at rest.
                if p > 0 {
                    Button {
                        action.action()
                        close()
                    } label: {
                        lensSurface(action.tint)
                            .frame(width: circle, height: circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.label)
                    .frame(width: slotWidth)
                    .frame(maxHeight: .infinity)
                    // Grow from zero so the lens doesn't pop in at a fixed size.
                    .scaleEffect(p)
                } else {
                    // Hold the slot so siblings keep their position.
                    Color.clear.frame(width: slotWidth)
                }
            }
        }
    }

    /// The glyphs, drawn above the glass and animating their own scale + opacity
    /// independently of the lens morph — so they stay crisp and centered.
    @ViewBuilder private func glyphStrip(slid: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { idx, action in
                // Delay the glyph until its lens has cleared the card edge, then
                // ramp it over the remaining travel — so it doesn't flash while
                // the lens is still half-refracted under the card.
                let gp = glyphReveal(slid: slid, index: idx)
                Image(systemName: action.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: slotWidth)
                    .frame(maxHeight: .infinity)
                    .scaleEffect(gp)
                    .opacity(gp)
            }
        }
        .allowsHitTesting(false)
    }

    /// A soft glow hugging the card's open-side edge (right normally, left when
    /// mirrored). Its colour continuously lerps between adjacent action tints as
    /// they emerge (red→orange→…, no gap), and its strength stays up across the
    /// whole reveal, fading only at the ends.
    @ViewBuilder private func edgeGlow(slid: CGFloat) -> some View {
        // Only glass themes need the glow (it masks a lens emerging from under the
        // translucent card); a solid card already hides it.
        if glass {
            let g = glow(slid: slid)
            RadialGradient(
                gradient: Gradient(colors: [g.color.opacity(0.8), g.color.opacity(0)]),
                center: mirror ? .leading : .trailing, startRadius: 0, endRadius: 80
            )
            .opacity(g.strength)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
    }

    /// Glow colour + strength for the current slide. `g = slid / slotWidth` runs
    /// 0…count as circles uncover right-to-left; the colour blends from the tint
    /// of the emerging circle toward the next one, so it sweeps the palette with
    /// no dead frame in between.
    private func glow(slid: CGFloat) -> (color: Color, strength: Double) {
        let n = actions.count
        guard n > 0 else { return (.clear, 0) }
        let g = Double(slid / slotWidth)
        let strength = max(0, min(1, min(g, Double(n) - g)))
        guard strength > 0 else { return (.clear, 0) }
        let k = min(n - 1, max(0, Int(g)))
        let frac = min(1, max(0, g - Double(k)))
        // Hold the current colour, then transition late in the slot (smoothstep
        // over the back portion) so it doesn't start shifting too early.
        let t = min(1, max(0, (frac - 0.45) / 0.55))
        let eased = t * t * (3 - 2 * t)
        let a = actions[n - 1 - k].tint
        let b = actions[max(0, n - 2 - k)].tint
        return (lerp(a, b, eased), strength)
    }

    private func lerp(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ua = UIColor(a), ub = UIColor(b)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        ua.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        ub.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let f = CGFloat(t)
        return Color(red: Double(r1 + (r2 - r1) * f),
                     green: Double(g1 + (g2 - g1) * f),
                     blue: Double(b1 + (b2 - b1) * f))
    }

    /// The tinted circle behind a glyph: an interactive (morphing) glass lens when
    /// the theme is glass, a solid tinted fill otherwise.
    @ViewBuilder private func lensSurface(_ tint: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if glass, #available(iOS 26.0, *) {
            shape.fill(.clear)
                .glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            shape.fill(tint)
        }
    }

    /// Per-button reveal driven by slide distance. The strip is anchored
    /// trailing, so the rightmost button uncovers first; each circle scales and
    /// fades in over the one slot-width during which its slot appears.
    private func reveal(slid: CGFloat, index: Int) -> Double {
        let start = openWidth - CGFloat(revealRank(index) + 1) * slotWidth
        return Double(min(1, max(0, (slid - start) / slotWidth)))
    }

    /// Lens reveal: like `reveal` but held back by `lensDelay` points so the
    /// circle stays hidden until it's a bit past the card edge — no faint
    /// half-emerged blob.
    private func lensReveal(slid: CGFloat, index: Int) -> Double {
        let start = openWidth - CGFloat(revealRank(index) + 1) * slotWidth + lensDelay
        return Double(min(1, max(0, (slid - start) / slotWidth)))
    }

    /// Order in which slots uncover. The strip uncovers from its anchored edge, so
    /// the slot nearest the card emerges first: that's the last array index when
    /// anchored trailing (default), and the first index when mirrored (leading).
    private func revealRank(_ index: Int) -> Int {
        mirror ? actions.count - 1 - index : index
    }

    /// Glyph reveal: begins after the lens has uncovered `glyphDelay` of its
    /// ramp, so the glyph appears once the circle is clear of the card.
    private func glyphReveal(slid: CGFloat, index: Int) -> Double {
        let glyphDelay = 0.5
        let p = lensReveal(slid: slid, index: index)
        return min(1, max(0, (p - glyphDelay) / (1 - glyphDelay)))
    }

    private func close() {
        withAnimation(.smooth(duration: 0.25)) { offset = 0 }
        if openID == id { openID = nil }
    }

    private func clamp(_ x: CGFloat) -> CGFloat {
        // Clamp to [-openDistance, 0] with a little rubber-band past open.
        min(0, max(-openDistance - 24, x))
    }
}
