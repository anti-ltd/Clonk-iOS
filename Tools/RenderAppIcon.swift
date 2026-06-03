#!/usr/bin/env swift
//
// RenderAppIcon.swift — renders the Clink iOS app icon into the asset catalog.
//
// Run via `make icon`. Clink's mark is a single **liquid-glass keycap**: a
// translucent slab floating on a luminous indigo gradient, with a refracted
// glow pulled through its body, a broad specular sheen, bright edge caustics,
// and a frosted "C" lensed inside the glass.
//
// iOS specifics, both required:
//   • the background is drawn full-bleed and fully opaque (no squircle clip,
//     no rim stroke) — iOS applies its own icon mask, and App Store icons must
//     not have an alpha channel.
//   • a single 1024px PNG (plus a 512px gallery copy) instead of an .iconset.
//
import AppKit

let size = 1024.0
let outDir = "Resources/Assets.xcassets/AppIcon.appiconset"
let outPath = "\(outDir)/icon-1024.png"
let galleryPath = "Resources/icon-512.png"

func renderPNG(size: CGFloat) -> Data? {
    let px = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    draw(in: ctx.cgContext, size: size)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

func draw(in cg: CGContext, size: CGFloat) {
    let space = CGColorSpaceCreateDeviceRGB()
    func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: a)
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // The scene behind the glass: a richer violet → blue → navy gradient (a
    // spread of hues for the glass to bend), a warm magenta bloom lower-right,
    // and a bright luminous core. Drawn once full-bleed, then again *inside*
    // the keycap so light genuinely reads through the translucent slab.
    let bgGrad = CGGradient(colorsSpace: space, colors: [
        rgb(0.42, 0.32, 0.72),
        rgb(0.20, 0.24, 0.58),
        rgb(0.06, 0.07, 0.18),
    ] as CFArray, locations: [0, 0.50, 1])!
    let warm = CGGradient(colorsSpace: space, colors: [
        rgb(0.85, 0.35, 0.78, 0.45),
        rgb(0.85, 0.35, 0.78, 0.00),
    ] as CFArray, locations: [0, 1])!
    let warmC = CGPoint(x: rect.maxX - size * 0.12, y: rect.minY + size * 0.16)
    let core = CGGradient(colorsSpace: space, colors: [
        rgb(0.72, 0.90, 1.00, 1.00),
        rgb(0.48, 0.70, 1.00, 0.55),
        rgb(0.44, 0.60, 0.98, 0.00),
    ] as CFArray, locations: [0, 0.40, 1])!
    let glowC = CGPoint(x: rect.midX, y: rect.midY + size * 0.03)

    func paintBackground() {
        cg.drawLinearGradient(bgGrad,
                              start: CGPoint(x: rect.minX, y: rect.maxY),
                              end: CGPoint(x: rect.maxX, y: rect.minY),
                              options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        cg.drawRadialGradient(warm, startCenter: warmC, startRadius: 0,
                              endCenter: warmC, endRadius: size * 0.55, options: [])
        cg.drawRadialGradient(core, startCenter: glowC, startRadius: 0,
                              endCenter: glowC, endRadius: size * 0.52, options: [])
    }

    // ── Background (full-bleed, opaque — iOS supplies the corner mask) ───────
    cg.saveGState()
    cg.addRect(rect)
    cg.clip()
    paintBackground()
    cg.restoreGState()

    // ── Keycap geometry ──────────────────────────────────────────────────────
    let capSide = size * 0.52
    let capX = (size - capSide) / 2
    let capY = (size - capSide) / 2 + size * 0.006
    let radius = capSide * 0.30                  // soft squircle
    let capRect = CGRect(x: capX, y: capY, width: capSide, height: capSide)
    let capPath = CGPath(roundedRect: capRect, cornerWidth: radius,
                         cornerHeight: radius, transform: nil)

    // ── Cast shadow — the glass floats above the surface ──────────────────────
    cg.saveGState()
    cg.addPath(capPath)
    cg.setShadow(offset: CGSize(width: 0, height: -size * 0.028),
                 blur: size * 0.075, color: rgb(0, 0, 0, 0.50))
    cg.setFillColor(rgb(0.02, 0.03, 0.08, 1))
    cg.fillPath()
    cg.restoreGState()

    // ════════════════════════════════════════════════════════════════════════
    //  GLASS BODY — everything below is clipped to the keycap.
    // ════════════════════════════════════════════════════════════════════════
    cg.saveGState()
    cg.addPath(capPath)
    cg.clip()

    // 0. Repaint the lit scene inside the slab — this is what makes the glass
    //    translucent: the same background, seen *through* the keycap (and it
    //    overwrites the opaque fill the cast-shadow pass left behind).
    paintBackground()

    // 1. Base tint — clearer glass: low-alpha so the lit background reads
    //    *through* the slab; only a gentle deepening toward the bottom.
    let tint = CGGradient(colorsSpace: space, colors: [
        rgb(0.82, 0.90, 1.00, 0.22),
        rgb(0.50, 0.62, 0.92, 0.09),
        rgb(0.10, 0.14, 0.34, 0.32),
    ] as CFArray, locations: [0, 0.5, 1])!
    cg.drawLinearGradient(tint, start: CGPoint(x: 0, y: capRect.maxY),
                          end: CGPoint(x: 0, y: capRect.minY), options: [])

    // 2. Refraction — the luminous core, magnified (larger than its source)
    //    and pulled toward the lower half the way a real lens bends light.
    let refr = CGGradient(colorsSpace: space, colors: [
        rgb(0.78, 0.93, 1.00, 0.85),
        rgb(0.52, 0.74, 1.00, 0.34),
        rgb(0.48, 0.66, 1.00, 0.00),
    ] as CFArray, locations: [0, 0.5, 1])!
    let refrC = CGPoint(x: capRect.midX, y: capRect.minY + capSide * 0.32)
    cg.drawRadialGradient(refr, startCenter: refrC, startRadius: 0,
                          endCenter: refrC, endRadius: capSide * 0.72, options: [])

    // 2b. Lens hotspot — a small intense focus of light low in the slab.
    let hot = CGGradient(colorsSpace: space, colors: [
        rgb(1, 1, 1, 0.55),
        rgb(0.80, 0.92, 1.00, 0.0),
    ] as CFArray, locations: [0, 1])!
    let hotC = CGPoint(x: capRect.midX, y: capRect.minY + capSide * 0.26)
    cg.drawRadialGradient(hot, startCenter: hotC, startRadius: 0,
                          endCenter: hotC, endRadius: capSide * 0.26, options: [])

    // 3. Specular sheen — a broad, soft glossy reflection across the top,
    //    squashed into an ellipse and biased to the upper-left.
    cg.saveGState()
    cg.translateBy(x: capRect.midX - capSide * 0.06, y: capRect.maxY - capSide * 0.24)
    cg.scaleBy(x: 1.0, y: 0.52)
    let sheen = CGGradient(colorsSpace: space, colors: [
        rgb(1, 1, 1, 0.60),
        rgb(1, 1, 1, 0.10),
        rgb(1, 1, 1, 0.00),
    ] as CFArray, locations: [0, 0.6, 1])!
    cg.drawRadialGradient(sheen, startCenter: .zero, startRadius: 0,
                          endCenter: .zero, endRadius: capSide * 0.5, options: [])
    cg.restoreGState()

    // 3b. Specular glint — a small, crisp hotspot near the top-left edge where
    //     a hard reflection would land. Tight falloff so it reads as wet glass,
    //     and a short streak trailing along the top edge.
    cg.saveGState()
    let glintC = CGPoint(x: capRect.minX + capSide * 0.27,
                         y: capRect.maxY - capSide * 0.16)
    let glint = CGGradient(colorsSpace: space, colors: [
        rgb(1, 1, 1, 0.95),
        rgb(1, 1, 1, 0.55),
        rgb(1, 1, 1, 0.00),
    ] as CFArray, locations: [0, 0.4, 1])!
    cg.drawRadialGradient(glint, startCenter: glintC, startRadius: 0,
                          endCenter: glintC, endRadius: capSide * 0.11, options: [])
    // Thin streak trailing toward the top-right, hugging the edge.
    cg.translateBy(x: glintC.x + capSide * 0.16, y: glintC.y + capSide * 0.015)
    cg.scaleBy(x: 2.6, y: 0.42)
    let streak = CGGradient(colorsSpace: space, colors: [
        rgb(1, 1, 1, 0.55),
        rgb(1, 1, 1, 0.00),
    ] as CFArray, locations: [0, 1])!
    cg.drawRadialGradient(streak, startCenter: .zero, startRadius: 0,
                          endCenter: .zero, endRadius: capSide * 0.09, options: [])
    cg.restoreGState()

    // 4. Frosted "C" — lensed into the glass: a soft shadow gives it depth
    //    below the surface, the light fill reads as etched frost.
    let glyphSize = capSide * 0.66
    let font: NSFont = {
        let base = NSFont.systemFont(ofSize: glyphSize, weight: .black)
        if let d = base.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: d, size: glyphSize) ?? base
        }
        return base
    }()
    func drawGlyph(_ color: NSColor, dx: CGFloat, dy: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let glyph = NSAttributedString(string: "C", attributes: attrs)
        let gSize = glyph.size()
        glyph.draw(at: CGPoint(x: capRect.midX - gSize.width / 2 + dx,
                               y: capRect.midY - gSize.height / 2 + dy))
    }
    // Depth shadow beneath the letter.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -size * 0.006),
                 blur: size * 0.016, color: rgb(0.03, 0.05, 0.16, 0.55))
    drawGlyph(NSColor(white: 1, alpha: 0.92), dx: 0, dy: 0)
    cg.restoreGState()
    // Top highlight edge of the letter — frost catching the light.
    drawGlyph(NSColor(white: 1, alpha: 0.30), dx: 0, dy: size * 0.006)

    cg.restoreGState()  // end glass-body clip

    // ── Edge caustics — light pooling at the rims of the glass slab ───────────
    // Chromatic dispersion: the rim splits into cool/warm fringes, offset in
    // opposite diagonals the way glass disperses light into a spectrum.
    let fringe = size * 0.0055
    cg.saveGState()
    cg.translateBy(x: -fringe, y: fringe)
    cg.addPath(capPath)
    cg.setLineWidth(size * 0.007)
    cg.setStrokeColor(rgb(0.40, 0.85, 1.00, 0.55))   // cyan
    cg.strokePath()
    cg.restoreGState()

    cg.saveGState()
    cg.translateBy(x: fringe, y: -fringe)
    cg.addPath(capPath)
    cg.setLineWidth(size * 0.007)
    cg.setStrokeColor(rgb(1.00, 0.45, 0.85, 0.50))   // magenta
    cg.strokePath()
    cg.restoreGState()

    // Crisp bright rim centred between the fringes.
    cg.saveGState()
    cg.addPath(capPath)
    cg.setLineWidth(size * 0.006)
    cg.setStrokeColor(rgb(0.92, 0.97, 1.00, 0.75))
    cg.strokePath()
    cg.restoreGState()

    // Bright top-edge highlight, fading downward (a thick inner band).
    cg.saveGState()
    cg.addPath(capPath)
    cg.clip()
    cg.addPath(capPath)
    cg.setLineWidth(size * 0.022)
    cg.replacePathWithStrokedPath()
    cg.clip()
    let topRim = CGGradient(colorsSpace: space, colors: [
        rgb(1, 1, 1, 0.85),
        rgb(1, 1, 1, 0.0),
    ] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(topRim, start: CGPoint(x: 0, y: capRect.maxY),
                          end: CGPoint(x: 0, y: capRect.midY), options: [])
    cg.restoreGState()

    // Cyan caustic pooling along the bottom inner edge.
    cg.saveGState()
    cg.addPath(capPath)
    cg.clip()
    cg.addPath(capPath)
    cg.setLineWidth(size * 0.030)
    cg.replacePathWithStrokedPath()
    cg.clip()
    let botRim = CGGradient(colorsSpace: space, colors: [
        rgb(0.55, 0.82, 1.0, 0.70),
        rgb(0.55, 0.82, 1.0, 0.0),
    ] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(botRim, start: CGPoint(x: 0, y: capRect.minY),
                          end: CGPoint(x: 0, y: capRect.midY), options: [])
    cg.restoreGState()
}

// Write the 1024 app-icon and a 512 gallery copy.
guard let png1024 = renderPNG(size: size) else { fatalError("failed to render 1024") }
try! png1024.write(to: URL(fileURLWithPath: outPath))
print("→ \(outPath)")

if let png512 = renderPNG(size: 512) {
    try! png512.write(to: URL(fileURLWithPath: galleryPath))
    print("→ \(galleryPath)")
}
