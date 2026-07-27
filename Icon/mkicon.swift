import AppKit
// Burndown app icon - "Living Ember": deep charcoal squircle, a radial-gradient teardrop flame
// (white-hot core → amber → orange → rust), a coal glow at its base, and two rising sparks.
// Matches the in-app FlameMark (Views.swift) and the menu-bar Flame glyph.
let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func hex(_ s: String) -> NSColor {
    let v = Int(s, radix: 16) ?? 0
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff)/255, green: CGFloat((v >> 8) & 0xff)/255, blue: CGFloat(v & 0xff)/255, alpha: 1)
}
let bgTop  = hex("2A1A12"), bgBot = hex("140D0A")
let rust   = hex("A0341A"), orange = hex("E2510B"), amber = hex("F9A825")
let creamy = hex("FFF6D6"), sparkC = hex("FFE9A8")

// Squircle tile
let margin = size * 0.085
let rect = CGRect(x: margin, y: margin, width: size - 2*margin, height: size - 2*margin)
let rr = NSBezierPath(roundedRect: rect, xRadius: rect.width*0.225, yRadius: rect.width*0.225)
NSGradient(starting: bgTop, ending: bgBot)!.draw(in: rr, angle: -90)

// Coal glow behind the flame base
rr.addClip()
let glow = NSGradient(starting: orange.withAlphaComponent(0.55), ending: orange.withAlphaComponent(0))!
glow.draw(fromCenter: CGPoint(x: size/2, y: size*0.32), radius: 0,
          toCenter: CGPoint(x: size/2, y: size*0.32), radius: size*0.30, options: [])

// Flame silhouette (teardrop: pointed crown, round belly). AppKit y-up: crown at top.
func flamePath(cx: CGFloat, baseY: CGFloat, w: CGFloat, h: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    let crown = CGPoint(x: cx, y: baseY + h)
    let bellyC = CGPoint(x: cx, y: baseY + w/2)
    p.move(to: crown)
    p.curve(to: CGPoint(x: cx - w/2, y: bellyC.y),
            controlPoint1: CGPoint(x: cx - w*0.10, y: baseY + h*0.74),
            controlPoint2: CGPoint(x: cx - w/2, y: baseY + h*0.52))
    // Round belly: sweep the BOTTOM half of the circle (180° → 270° → 360° in y-up coords).
    // AppKit sweeps counterclockwise when clockwise:false, i.e. increasing angle → through 270 (down).
    p.appendArc(withCenter: bellyC, radius: w/2, startAngle: 180, endAngle: 360, clockwise: false)
    p.curve(to: crown,
            controlPoint1: CGPoint(x: cx + w/2, y: baseY + h*0.52),
            controlPoint2: CGPoint(x: cx + w*0.10, y: baseY + h*0.74))
    p.close()
    return p
}

// Outer flame with layered radial fills (rust rim → orange → amber → cream heart)
let fw = size*0.46, fh = size*0.58, fx = size/2, fy = size*0.20
let outer = flamePath(cx: fx, baseY: fy, w: fw, h: fh)
rust.setFill(); outer.fill()
NSGraphicsContext.current?.saveGraphicsState()
outer.addClip()
let heart = CGPoint(x: fx, y: fy + fw*0.42)
NSGradient(colorsAndLocations: (creamy, 0.0), (amber, 0.34), (orange, 0.72), (rust, 1.0))!
    .draw(fromCenter: heart, radius: 0, toCenter: heart, radius: fh*0.86, options: [])
NSGraphicsContext.current?.restoreGraphicsState()

// White-hot core flame
let core = flamePath(cx: fx, baseY: fy + size*0.035, w: fw*0.42, h: fh*0.44)
creamy.withAlphaComponent(0.94).setFill(); core.fill()

// Rising sparks
func spark(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: NSColor, _ a: CGFloat) {
    c.withAlphaComponent(a).setFill()
    NSBezierPath(ovalIn: CGRect(x: x - r, y: y - r, width: 2*r, height: 2*r)).fill()
}
spark(size*0.52, size*0.845, size*0.016, sparkC, 0.95)
spark(size*0.615, size*0.775, size*0.011, amber, 0.75)
spark(size*0.42,  size*0.80,  size*0.009, sparkC, 0.6)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Icon/AppIcon-1024.png"))
print("wrote Icon/AppIcon-1024.png")
