import AppKit
import SwiftUI

extension NSColor {
    // Parse "RRGGBB" or "#RGB"/"#RRGGBB", case-insensitive. Returns nil only when truly
    // unparseable; the token layer (Color(hex:)) turns any nil into a safe accent/label fallback.
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }   // shorthand: ABC to AABBCC
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
                  green: CGFloat((v >> 8) & 0xff) / 255,
                  blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "D97757" }
        return String(format: "%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
    /// Darken + saturate as usage rises - so the chosen accent drives the whole
    /// "by level" ramp (default clay → burnt → rust falls out of #D97757).
    func darkened(_ amount: CGFloat) -> NSColor {
        guard let c = usingColorSpace(.deviceRGB) else { return self }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(1, s + amount * 0.35), brightness: b * (1 - amount * 0.85), alpha: a)
    }

    /// Linear sRGB blend toward another color (0 = self, 1 = other).
    func blended(to other: NSColor, _ t: CGFloat) -> NSColor {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return self }
        let k = max(0, min(1, t))
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * k,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * k,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * k, alpha: 1)
    }
}

extension Color {
    // Token-layer color. Never nil and never raw black or white: a bad hex falls back to the brand
    // accent, then to the adaptive label color, so a token typo can never blank out or invert a surface.
    init(hex: String) { self.init(nsColor: NSColor(hex: hex) ?? NSColor(hex: kAccentHex) ?? .labelColor) }

    /// Lift brightness toward white (0 = unchanged, 1 = white). Used for glow tips and highlights.
    func brighten(_ amount: Double) -> Color {
        Color(nsColor: NSColor(self).blended(to: .white, CGFloat(amount)))
    }

    /// Blend toward another role color (0 = self, 1 = other). The SwiftUI mirror of NSColor.blended.
    func blended(to other: Color, _ t: Double) -> Color {
        Color(nsColor: NSColor(self).blended(to: NSColor(other), CGFloat(max(0, min(1, t)))))
    }
}

extension NSColor {
    /// WCAG relative luminance (sRGB).
    var wcagLuminance: Double {
        guard let c = usingColorSpace(.sRGB) else { return 0 }
        func lin(_ v: CGFloat) -> Double { let d = Double(v); return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }
    /// WCAG contrast ratio between two colors (1.0 ... 21.0).
    static func wcagContrast(_ a: NSColor, _ b: NSColor) -> Double {
        let la = a.wcagLuminance, lb = b.wcagLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

// The slate "secondary" accent (time / weekly), fixed unless monochrome.
let kSlateHex = "5E7186"    // weekly role (Stone & Clay slate); secondaryNSColor lifts it for dark
let kDangerHex = "A0341A"   // rust, the high-usage end of the Adaptive ramp
let kAccentHex = "D97757"   // brand clay accent; the safe fallback for an unparseable token hex

// Usage color for a given level.
// .system → label color (popover; the menu bar uses a template image instead).
// .level (Adaptive) keeps the accent through normal usage and only shifts toward
//   rust as you approach the cap - so toggling to .flat barely changes the color
//   at typical levels (no jarring brightness jump), and the warning reads clearly.
func usageNSColor(pct: Double, over: Bool, accent: NSColor, mode: ColorMode) -> NSColor {
    switch mode {
    case .system: return .labelColor
    case .flat:   return accent
    case .level:
        let danger = NSColor(hex: kDangerHex) ?? accent
        let t = over ? 1.0 : max(0, (min(1.0, pct) - 0.5) / 0.5)   // 0 below 50%, →1 at the cap
        return accent.blended(to: danger, CGFloat(t))
    }
}
func secondaryNSColor(accent: NSColor, mode: ColorMode) -> NSColor {
    switch mode {
    case .system: return .secondaryLabelColor
    case .flat:   return accent
    case .level:  return NSColor(hex: kSlateHex) ?? .gray
    }
}

// MARK: - Fire palette (spec 2.2) - emissive brand constants, theme-independent.
// TYPOGRAPHIC HEAT ONLY: burning numbers, the Ember Line, blooms. This palette NEVER recolors the
// FlameMark, which keeps the app-icon hues verbatim (FFF6D6/F9A825/E2510B/A0341A). That split is the
// ratified "two registers, one family" color canon (prompt area 1). Redline red inside any fire
// execution is the overLimit token (dark value, emissive rule), not a private hex.
enum Fire {
    static let charLight = "3A2A22"   // spent material on a LIGHT menu bar
    static let charDark  = "4A2E22"   // spent material on a DARK menu bar
    static let ember     = "A63A22"   // body base, coolest visible heat
    static let flame     = "D95B2E"   // active heat, sibling of the D97757 brand clay
    static let glow      = "F0A05A"   // warm light: gradients + halos only, never a body fill
    static let core      = "FFE2C2"   // highlight heart, budget-capped
    static let white     = "FFF4E4"   // redline-only white heat
    // fire/char keys off the menu bar's effectiveAppearance, not the app theme.
    static func char(dark: Bool) -> String { dark ? charDark : charLight }
    static func ns(_ hex: String) -> NSColor { NSColor(hex: hex) ?? .systemOrange }
}

extension NSColor {
    /// Shift HSL lightness by `deltaL` percentage points (of 0...100), preserving hue and saturation.
    /// Backs the session numeral gradient ink (spec 2.3: the session color at L+7 and L-7).
    func lightnessShifted(_ deltaL: CGFloat) -> NSColor {
        guard let c = usingColorSpace(.sRGB) else { return self }
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent, a = c.alphaComponent
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let l = (mx + mn) / 2
        var h: CGFloat = 0, s: CGFloat = 0
        if d != 0 {
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            switch mx {
            case r: h = (g - b) / d + (g < b ? 6 : 0)
            case g: h = (b - r) / d + 2
            default: h = (r - g) / d + 4
            }
            h /= 6
        }
        let nl = max(0, min(1, l + deltaL / 100))
        if s == 0 { return NSColor(srgbRed: nl, green: nl, blue: nl, alpha: a) }
        func hue2rgb(_ p: CGFloat, _ q: CGFloat, _ t0: CGFloat) -> CGFloat {
            var t = t0
            if t < 0 { t += 1 }; if t > 1 { t -= 1 }
            if t < 1/6 { return p + (q - p) * 6 * t }
            if t < 1/2 { return q }
            if t < 2/3 { return p + (q - p) * (2/3 - t) * 6 }
            return p
        }
        let q = nl < 0.5 ? nl * (1 + s) : nl + s - nl * s
        let p = 2 * nl - q
        return NSColor(srgbRed: hue2rgb(p, q, h + 1/3), green: hue2rgb(p, q, h), blue: hue2rgb(p, q, h - 1/3), alpha: a)
    }
}

extension Color {
    /// The session numeral gradient ink (spec 2.3): the one permanent gradient in the product,
    /// vertical, the session color at HSL lightness +7 (top) to -7 (bottom).
    static func sessionGradientInk(_ session: Color) -> LinearGradient {
        let ns = NSColor(session)
        return LinearGradient(colors: [Color(nsColor: ns.lightnessShifted(7)), Color(nsColor: ns.lightnessShifted(-7))],
                              startPoint: .top, endPoint: .bottom)
    }
}
