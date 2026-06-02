#!/usr/bin/env swift
//
// RenderAppIcon.swift — renders the Clonk iOS app icon into the asset catalog.
//
// Run via `make icon`. This is the iOS port of clonk-macos's AppIconRenderer:
// the same indigo-charcoal keycap with a rounded "C" and concentric "clonk"
// ripples. Differences from the macOS version, both required for iOS:
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

    // ── Background (full-bleed, opaque — iOS supplies the corner mask) ──────
    cg.saveGState()
    cg.addRect(rect)
    cg.clip()

    // Deep diagonal gradient — indigo-charcoal, light from top-left.
    let bgGrad = CGGradient(colorsSpace: space, colors: [
        rgb(0.26, 0.27, 0.38),
        rgb(0.13, 0.13, 0.20),
        rgb(0.05, 0.05, 0.09),
    ] as CFArray, locations: [0, 0.55, 1])!
    cg.drawLinearGradient(bgGrad,
                          start: CGPoint(x: rect.minX, y: rect.maxY),
                          end: CGPoint(x: rect.maxX, y: rect.minY),
                          options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Soft radial glow behind the keycap for depth.
    let glow = CGGradient(colorsSpace: space, colors: [
        rgb(0.42, 0.46, 0.72, 0.55),
        rgb(0.42, 0.46, 0.72, 0.0),
    ] as CFArray, locations: [0, 1])!
    cg.drawRadialGradient(glow,
                          startCenter: CGPoint(x: rect.midX, y: rect.midY + size * 0.04),
                          startRadius: 0,
                          endCenter: CGPoint(x: rect.midX, y: rect.midY + size * 0.04),
                          endRadius: rect.width * 0.62, options: [])
    cg.restoreGState()

    // ── Keycap geometry ─────────────────────────────────────────────────────
    let capSide = size * 0.46
    let capX = (size - capSide) / 2
    let capY = (size - capSide) / 2 + size * 0.012
    let depth = size * 0.062            // visible height of the cap "wall"
    let radius = capSide * 0.235

    // ── Ripple — concentric superellipse rings echoing the keycap ───────────
    let cx = capX + capSide / 2
    let cy = capY + (capSide - depth) / 2
    let halfW = capSide / 2
    let halfH = (capSide + depth) / 2
    let sqExp = 4.2

    func rippleRing(_ e: CGFloat) -> CGPath {
        let hw = Double(halfW + e), hh = Double(halfH + e)
        let path = CGMutablePath()
        let steps = 1024
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * .pi
            let ct = cos(t), st = sin(t)
            let x = Double(cx) + hw * copysign(pow(abs(ct), 2 / sqExp), ct)
            let y = Double(cy) + hh * copysign(pow(abs(st), 2 / sqExp), st)
            let pt = CGPoint(x: x, y: y)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    cg.saveGState()
    cg.setLineJoin(.round)
    let ripple: [(inset: Double, r: Double, g: Double, b: Double, alpha: Double, width: Double)] = [
        (0.028, 0.66, 0.91, 1.00, 0.50, 0.018),
        (0.052, 0.56, 0.83, 0.97, 0.28, 0.015),
        (0.076, 0.49, 0.71, 0.91, 0.14, 0.012),
        (0.100, 0.44, 0.60, 0.85, 0.05, 0.010),
    ]
    for ring in ripple {
        cg.addPath(rippleRing(size * ring.inset))
        cg.setStrokeColor(rgb(ring.r, ring.g, ring.b, ring.alpha))
        cg.setLineWidth(size * ring.width)
        cg.setShadow(offset: .zero, blur: size * 0.011,
                     color: rgb(0.42, 0.80, 0.97, ring.alpha * 0.5))
        cg.strokePath()
    }
    cg.restoreGState()

    // Contact shadow cast on the background.
    cg.saveGState()
    let shadowRect = CGRect(x: capX, y: capY - depth - size * 0.018,
                            width: capSide, height: capSide)
    cg.addPath(CGPath(roundedRect: shadowRect, cornerWidth: radius,
                      cornerHeight: radius, transform: nil))
    cg.setShadow(offset: CGSize(width: 0, height: -size * 0.022),
                 blur: size * 0.06,
                 color: rgb(0, 0, 0, 0.55))
    cg.setFillColor(rgb(0, 0, 0, 0.9))
    cg.fillPath()
    cg.restoreGState()

    // Cap wall (the side) — darker, vertical gradient.
    let sideRect = CGRect(x: capX, y: capY - depth, width: capSide, height: capSide)
    cg.saveGState()
    cg.addPath(CGPath(roundedRect: sideRect, cornerWidth: radius,
                      cornerHeight: radius, transform: nil))
    cg.clip()
    let wallGrad = CGGradient(colorsSpace: space, colors: [
        rgb(0.62, 0.64, 0.74),
        rgb(0.28, 0.29, 0.38),
    ] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(wallGrad, start: CGPoint(x: 0, y: sideRect.maxY),
                          end: CGPoint(x: 0, y: sideRect.minY), options: [])
    cg.restoreGState()

    // Cap top face — bright, with a diagonal sheen and a dished centre.
    let topRect = CGRect(x: capX, y: capY, width: capSide, height: capSide)
    let topPath = CGPath(roundedRect: topRect, cornerWidth: radius,
                         cornerHeight: radius, transform: nil)
    cg.saveGState()
    cg.addPath(topPath)
    cg.clip()
    let topGrad = CGGradient(colorsSpace: space, colors: [
        rgb(1.00, 1.00, 1.00),
        rgb(0.93, 0.94, 0.97),
        rgb(0.80, 0.82, 0.89),
    ] as CFArray, locations: [0, 0.5, 1])!
    cg.drawLinearGradient(topGrad, start: CGPoint(x: topRect.minX, y: topRect.maxY),
                          end: CGPoint(x: topRect.maxX, y: topRect.minY),
                          options: [])
    let dish = CGGradient(colorsSpace: space, colors: [
        rgb(0, 0, 0, 0.0),
        rgb(0.20, 0.22, 0.32, 0.18),
    ] as CFArray, locations: [0.62, 1])!
    cg.drawRadialGradient(dish,
                          startCenter: CGPoint(x: topRect.midX, y: topRect.midY),
                          startRadius: 0,
                          endCenter: CGPoint(x: topRect.midX, y: topRect.midY),
                          endRadius: capSide * 0.62, options: [])
    cg.restoreGState()

    // Soft inner highlight along the top edge of the cap.
    cg.saveGState()
    cg.addPath(topPath)
    cg.clip()
    cg.addPath(topPath)
    cg.setLineWidth(size * 0.018)
    cg.replacePathWithStrokedPath()
    cg.clip()
    let rimGrad = CGGradient(colorsSpace: space, colors: [
        rgb(1, 1, 1, 0.75),
        rgb(1, 1, 1, 0.0),
    ] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(rimGrad, start: CGPoint(x: 0, y: topRect.maxY),
                          end: CGPoint(x: 0, y: topRect.midY), options: [])
    cg.restoreGState()

    // ── Letterform ──────────────────────────────────────────────────────────
    let glyphSize = capSide * 0.7
    let font: NSFont = {
        let base = NSFont.systemFont(ofSize: glyphSize, weight: .black)
        if let d = base.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: d, size: glyphSize) ?? base
        }
        return base
    }()
    func drawGlyph(color: NSColor, dx: CGFloat, dy: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let glyph = NSAttributedString(string: "C", attributes: attrs)
        let gSize = glyph.size()
        glyph.draw(at: CGPoint(x: topRect.midX - gSize.width / 2 + dx,
                               y: topRect.midY - gSize.height / 2 + dy))
    }
    cg.saveGState()
    cg.addPath(topPath)
    cg.clip()
    drawGlyph(color: NSColor(white: 1, alpha: 0.7), dx: 0, dy: -size * 0.007)
    let glyphImg = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        drawGlyph(color: .black, dx: 0, dy: 0)
        return true
    }
    if let cgImg = glyphImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        cg.saveGState()
        cg.clip(to: CGRect(x: 0, y: 0, width: size, height: size), mask: cgImg)
        let gGrad = CGGradient(colorsSpace: space, colors: [
            rgb(0.30, 0.33, 0.48),
            rgb(0.12, 0.13, 0.22),
        ] as CFArray, locations: [0, 1])!
        cg.drawLinearGradient(gGrad, start: CGPoint(x: 0, y: topRect.maxY),
                              end: CGPoint(x: 0, y: topRect.minY), options: [])
        cg.restoreGState()
    }
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
