import AppKit

struct GlyphData {
    var pct: Double          // primary usage 0…1
    var pctText: String      // "46%"
    var primary: NSColor
    /// The colour for the NUMBER specifically, when it should differ from `primary`.
    ///
    /// The menu bar is a strip of system-tinted glyphs that adapt to whatever wallpaper is behind
    /// them, and a themed number sitting among them is the one thing that fights its background.
    /// The dot, the arc and the glow keep the accent (that is what makes them readable AS a
    /// gauge); the digits default to the same label colour the clock uses.
    var numberColor: NSColor? = nil
    /// Whatever the number should be drawn in.
    var digits: NSColor { numberColor ?? primary }
    var secFrac: Double      // secondary fill 0…1 (time remaining, or weekly usage)
    var secText: String      // "4h31m" or "13%"
    var secondary: NSColor
    var pLabel: String       // "S" / "" for the labeled style
    var sLabel: String       // "W" / ""
    var hasSecondary: Bool = false   // "Both" mode → styles may surface weekly too
    var weekLeftText: String = ""    // weekly reset countdown ("3d 4h") - for weeklyClock

    // ── live fields (drive the animated styles) ──
    var tokText: String = ""     // "≈3.0M" - roll
    var needle: Double = 0       // 0…1 eased token rate - pace
    var active: Bool = false     // tokens flowing right now - accent vs dim
    var rollFrom: String = ""    // previous tokText, for the odometer transition
    var rollPhase: Double = 1    // 0→1 transition (1 = settled)
    var spark: [Double] = []     // recent normalized burn-rate samples - burn / pulse
    var phase: Double = 0        // ever-advancing seconds counter (flame flicker / spark motion)
    var digitWeight: NSFont.Weight = .semibold   // menu-bar digit weight
    var smolderIntensity: Double = 1.0           // Smolder glow multiplier (area 2)
    var smolderBreathSlow = false                // Smolder: halve breath frequency
    var smolderWarmthWander = true               // Smolder: wandering hotspot on/off
    var redline: Double = 0      // 0…1 closeness to the cap - drives the "heat" (flame rages near limit)
    var flare: Double = 0        // 1 right after a data refresh → fades to 0 (glyph refresh flare)
    // ── the One Pulse fire inputs. `phase` above carries BurnClock.elapsed
    // (monotonic seconds); every fire frequency is evaluated as sin(2*pi*f*elapsed) against it.
    var tier: BurnTier = .idle   // drives every fire amplitude/frequency via the BurnTier tables
    var heat: Double = 0.15      // tier.heat, lerped at 0.06/frame (~1.1s settle) by the animator
    // FLAME ADJUST. The defaults here reproduce the original flame design exactly; the app's
    // shipped defaults are livelier, because that design's idle flame is unreadable at menu-bar scale.
    var flameSize: Double = 1.0
    var flameSparks: FlameSparks = .redline
    var flameSmoke: Bool = false
    // ── Beacon ──
    var accent: NSColor = NSColor(hex: kAccentHex) ?? .systemOrange   // the theme accent = the wink color
    var beacon: Double = 0       // 0 = the bar's own ink, 1 = full accent. The app clock owns the schedule.
    var beaconMark: BeaconMark = .percent   // what actually winks
    var beaconGlow: Double = 0              // 0…1 halo at the peak of the wink
}

// The Beacon wink clock. It owns nothing but time - when the next wink lands, and how lit the glyph is
// right now - so the QA diag can run it headless and get exactly what the menu bar gets.
struct BeaconClock {
    private(set) var firedAt: Double = -99           // start of the current/last wink, in elapsed seconds
    private(set) var length: Double = 0.42           // the length THIS wink was fired with
    private var nextAt: Double = 1.0

    /// Advance to `elapsed` (monotonic seconds) and return the wink envelope, 0…1. Call once per frame.
    /// `every` ± `jitter` sets the gap, re-rolled after every wink so it never settles into a rhythm.
    mutating func envelope(at elapsed: Double, every: Double, jitter: Double, length: Double, curve: BeaconCurve) -> Double {
        if elapsed >= nextAt {
            firedAt = nextAt                         // honour the scheduled instant, not this tick's lateness
            self.length = max(0.02, length)
            let j = max(0, min(1, jitter)) * every
            // Measure the next gap from the wink INSTANT, not from this tick - a tick can be up to a
            // frame late, and scheduling off it would let that lateness accumulate into the cadence.
            // max(elapsed,…) keeps a wake-from-sleep jump from queuing a burst of backdated winks.
            nextAt = max(elapsed, firedAt + max(0.05, Double.random(in: (every - j)...(every + j))))
        }
        return Self.level(elapsed - firedAt, self.length, curve)
    }
    /// Fire a wink right now, leaving the schedule alone - for the Settings "Wink now" button, so a
    /// long cadence doesn't mean waiting a minute to judge a change.
    mutating func fireNow(at elapsed: Double, length: Double) {
        firedAt = elapsed
        self.length = max(0.02, length)
    }
    /// The wink over time. `t` = seconds since it started, `len` its total length.
    static func level(_ t: Double, _ len: Double, _ curve: BeaconCurve) -> Double {
        guard t >= 0, t < len else { return 0 }
        let f = t / len                              // 0…1 through the wink, so every curve scales together
        switch curve {
        case .snap:  // on instantly, hold, ease off - the original blink
            if f < 0.12 { return f / 0.12 }
            if f < 0.36 { return 1 }
            return pow(1 - (f - 0.36) / 0.64, 1.6)
        case .pulse: // one smooth in-and-out, no hold: a breath
            return 0.5 - 0.5 * cos(2 * .pi * f)
        case .fade:  // instant on, long decay: a spark landing
            return pow(1 - f, 2.2)
        case .beat:  // two blinks, the second softer: a pulse
            if f < 0.30 { return 0.5 - 0.5 * cos(2 * .pi * (f / 0.30)) }
            if f < 0.42 { return 0 }
            return 0.75 * (0.5 - 0.5 * cos(2 * .pi * ((f - 0.42) / 0.58)))
        }
    }
}

enum MenuBarRenderer {
    static let PRIMARY: CGFloat = 13.5
    static func track(_ a: CGFloat = 0.20) -> NSColor { NSColor.secondaryLabelColor.withAlphaComponent(a) }

    // template=true → the whole glyph becomes a system-tinted template image
    // (used by the "None" color mode so it matches native menu-bar icons).
    static func image(style: MenuBarStyle, _ g: GlyphData, template: Bool = false) -> NSImage {
        let img = build(style: style, g)
        img.isTemplate = template
        return img
    }

    private static func build(style: MenuBarStyle, _ g: GlyphData) -> NSImage {
        switch style {
        case .smolder:  return smolder(g)
        case .burnfront: return burnfront(g)
        case .kiln:     return kiln(g)
        case .pulse:  return pulse(g)
        case .pace:   return pace(g)
        case .burn:   return burn(g)
        case .roll:   return roll(g)
        case .bars:   return bars(g)
        case .signal: return signal(g)
        case .ember:  return ember(g)
        case .flame:  return flame(g)
        case .inferno: return inferno(g)
        case .ignite:  return ignite(g)
        case .charred: return charred(g)
        case .molten:  return molten(g)
        case .coals:   return coals(g)
        case .comet:  return comet(g)
        case .beacon: return beacon(g)
        case .stack:  return stack(g)
        case .ring:   return ring(g)
        case .orbit:  return orbit(g)
        case .mini:   return textImage(g.pctText, PRIMARY, .semibold, g.digits)
        case .arc:    return arc(g)
        case .pie:    return pie(g)
        case .dual:   return dual(g)
        case .dot:    return dot(g)
        case .dial:   return dial(g)
        case .twins:    return twins(g)
        case .splitArc: return splitArc(g)
        case .halfGauge:return halfGauge(g)
        case .coPie:    return coPie(g)
        case .vsplit:   return vsplit(g)
        case .heatRows: return heatRows(g)
        case .weeklyClock: return weeklyClock(g)
        }
    }

    // MARK: primitives

    private static func attrs(_ s: CGFloat, _ w: NSFont.Weight, _ c: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: s, weight: w), .foregroundColor: c]
    }
    private static func img(_ w: CGFloat, _ h: CGFloat, _ draw: () -> Void) -> NSImage {
        let i = NSImage(size: NSSize(width: max(2, w), height: max(2, h))); i.lockFocus(); draw(); i.unlockFocus()
        i.isTemplate = false; return i
    }
    private static func drawRing(_ r: NSRect, _ lw: CGFloat, _ frac: Double, _ color: NSColor) {
        let c = NSPoint(x: r.midX, y: r.midY), rad = min(r.width, r.height)/2 - lw/2
        let t = NSBezierPath(); t.appendArc(withCenter: c, radius: rad, startAngle: 0, endAngle: 360)
        t.lineWidth = lw; track().setStroke(); t.stroke()
        let p = NSBezierPath()
        p.appendArc(withCenter: c, radius: rad, startAngle: 90, endAngle: 90 - 360 * CGFloat(min(1, max(0.001, frac))), clockwise: true)
        p.lineWidth = lw; p.lineCapStyle = .round; color.setStroke(); p.stroke()
    }
    private static func textImage(_ s: String, _ size: CGFloat, _ w: NSFont.Weight, _ c: NSColor) -> NSImage {
        let a = attrs(size, w, c); let ts = (s as NSString).size(withAttributes: a)
        return img(ceil(ts.width), ceil(ts.height)) { (s as NSString).draw(at: .zero, withAttributes: a) }
    }
    // A burn-rate polyline filling [0,w] × [0,h]; nil/short data → a flat baseline.
    private static func sparkPath(_ pts: [Double], _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
        let line = NSBezierPath()
        if pts.count >= 2 {
            let stepX = w / CGFloat(pts.count - 1)
            for (i, v) in pts.enumerated() {
                let x = CGFloat(i) * stepX, yy = CGFloat(max(0, min(1, v))) * (h - 1)
                if i == 0 { line.move(to: NSPoint(x: x, y: yy)) } else { line.line(to: NSPoint(x: x, y: yy)) }
            }
        }
        return line
    }

    // A slim weekly fill bar across the bottom - used by the live styles in "Both" mode.
    private static func weeklyBar(_ w: CGFloat, _ frac: Double, _ col: NSColor, _ h: CGFloat = 2.5) {
        track(0.28).setFill(); NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: h), xRadius: h/2, yRadius: h/2).fill()
        let fw = max(h, CGFloat(max(0, min(1, frac))) * w)
        col.setFill(); NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: fw, height: h), xRadius: h/2, yRadius: h/2).fill()
    }

    // MARK: static styles

    // % over weekly/time - two stacked lines, color-coded, just text-width wide.
    private static func stack(_ g: GlyphData) -> NSImage {
        let at = attrs(11, .semibold, g.digits), ab = attrs(9.5, .medium, g.secondary)
        let t = (g.pctText as NSString).size(withAttributes: at), b = (g.secText as NSString).size(withAttributes: ab)
        let w = max(ceil(t.width), ceil(b.width)), h = ceil(t.height) + ceil(b.height) - 1
        return img(w, h) {
            (g.pctText as NSString).draw(at: NSPoint(x: 0, y: ceil(b.height) - 1), withAttributes: at)
            (g.secText as NSString).draw(at: NSPoint(x: 0, y: 0), withAttributes: ab)
        }
    }

    // A single ring (time remaining) with the usage % inside it. Tiniest.
    private static func ring(_ g: GlyphData) -> NSImage {
        let s: CGFloat = 19, num = g.pctText.replacingOccurrences(of: "%", with: "")
        let a = attrs(9, .bold, g.digits); let ts = (num as NSString).size(withAttributes: a)
        return img(s, s) {
            drawRing(NSRect(x: 0, y: 0, width: s, height: s), 2.2, g.secFrac, g.secondary)
            (num as NSString).draw(at: NSPoint(x: (s - ts.width)/2, y: (s - ts.height)/2), withAttributes: a)
        }
    }

    // Two nested rings - usage outside, time inside.
    private static func orbit(_ g: GlyphData) -> NSImage {
        let s: CGFloat = 18
        return img(s, s) {
            drawRing(NSRect(x: 0, y: 0, width: s, height: s), 2.6, min(1, g.pct), g.primary)
            let i: CGFloat = 4.8
            drawRing(NSRect(x: i, y: i, width: s - 2*i, height: s - 2*i), 2.2, g.secFrac, g.secondary)
        }
    }

    // MARK: live styles

    // The % with a live burn-rate spark stacked underneath - tall, never wide.
    // In "Both" mode it also grows a slim weekly progress bar at the very bottom.
    private static func pulse(_ g: GlyphData) -> NSImage {
        let a = attrs(11.5, .semibold, g.digits)
        let ts = (g.pctText as NSString).size(withAttributes: a)
        let sh: CGFloat = 5, gap: CGFloat = 1.5
        let wk = g.hasSecondary                       // show the weekly bar?
        let wkH: CGFloat = 2.5, wkGap: CGFloat = 2.5
        let w = max(20, ceil(ts.width))
        let h = ceil(ts.height) + gap + sh + (wk ? wkGap + wkH : 0)
        let sparkY = wk ? wkGap + wkH : 0             // lift spark above the weekly bar
        return img(w, h) {
            (g.pctText as NSString).draw(at: NSPoint(x: (w - ts.width)/2, y: sparkY + sh + gap), withAttributes: a)
            if g.spark.count >= 2 {
                let line = sparkPath(g.spark, w, sh); line.transform(using: AffineTransform(translationByX: 0, byY: sparkY))
                line.lineWidth = 1.4; line.lineJoinStyle = .round; line.lineCapStyle = .round
                (g.active ? g.primary : g.primary.withAlphaComponent(0.6)).setStroke(); line.stroke()
            } else {
                let b = NSBezierPath(); b.move(to: NSPoint(x: 0, y: sparkY + 0.7)); b.line(to: NSPoint(x: w, y: sparkY + 0.7))
                b.lineWidth = 1; track(0.3).setStroke(); b.stroke()
            }
            if wk {                                   // weekly fill bar (slate), pinned to the bottom
                let tr = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: wkH), xRadius: wkH/2, yRadius: wkH/2)
                track(0.28).setFill(); tr.fill()
                let fw = max(wkH, CGFloat(max(0, min(1, g.secFrac))) * w)
                let fp = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: fw, height: wkH), xRadius: wkH/2, yRadius: wkH/2)
                g.secondary.setFill(); fp.fill()
            }
        }
    }

    // Digital gauge: a 3/4 arc (open at the bottom) that revs with the live token
    // RATE, with the usage number sitting inside it. No needle, no text beside it -
    // compact, square. Brightens when tokens are flowing.
    private static func pace(_ g: GlyphData) -> NSImage {
        let s: CGFloat = 22
        let num = g.pctText.replacingOccurrences(of: "%", with: "")   // "46" reads cleaner inside
        let a = attrs(10, .bold, g.digits)
        let ts = (num as NSString).size(withAttributes: a)
        let frac = max(0, min(1, g.needle))
        let startA: CGFloat = 235, sweep: CGFloat = 290               // gap centered at the bottom
        return img(s, s) {
            let c = NSPoint(x: s/2, y: s/2), r = s/2 - 2
            let t = NSBezierPath()
            t.appendArc(withCenter: c, radius: r, startAngle: startA, endAngle: startA - sweep, clockwise: true)
            t.lineWidth = 2.3; t.lineCapStyle = .round; track().setStroke(); t.stroke()
            if frac > 0.01 {
                let p = NSBezierPath()
                p.appendArc(withCenter: c, radius: r, startAngle: startA, endAngle: startA - sweep * CGFloat(frac), clockwise: true)
                p.lineWidth = 2.3; p.lineCapStyle = .round
                (g.active ? g.primary : g.primary.withAlphaComponent(0.5)).setStroke(); p.stroke()
            }
            (num as NSString).draw(at: NSPoint(x: (s - ts.width)/2, y: (s - ts.height)/2 - 0.5), withAttributes: a)
        }
    }

    // A live burn-rate sparkline beside the %.
    private static func burn(_ g: GlyphData) -> NSImage {
        let sw: CGFloat = 30, sh: CGFloat = 13, gap: CGFloat = 4, a = attrs(PRIMARY, .semibold, g.digits)
        let ts = (g.pctText as NSString).size(withAttributes: a), w = sw + gap + ceil(ts.width), h = max(sh, ceil(ts.height)), y0 = (h - sh)/2
        return img(w, h) {
            let base = NSBezierPath(); base.move(to: NSPoint(x: 0, y: y0)); base.line(to: NSPoint(x: sw, y: y0))
            base.lineWidth = 0.8; track(0.25).setStroke(); base.stroke()
            if g.spark.count >= 2 {
                let line = sparkPath(g.spark, sw, sh); line.transform(using: AffineTransform(translationByX: 0, byY: y0))
                line.lineWidth = 1.5; line.lineJoinStyle = .round; line.lineCapStyle = .round
                (g.active ? g.primary : g.primary.withAlphaComponent(0.7)).setStroke(); line.stroke()
                if let last = g.spark.last {
                    let yy = y0 + CGFloat(max(0, min(1, last))) * (sh - 1)
                    g.primary.setFill(); NSBezierPath(ovalIn: NSRect(x: sw - 1.6, y: yy - 1.6, width: 3.2, height: 3.2)).fill()
                }
            }
            (g.pctText as NSString).draw(at: NSPoint(x: sw + gap, y: (h - ts.height)/2), withAttributes: a)
        }
    }

    // The % beside a token figure that rolls (odometer) when it changes.
    private static func roll(_ g: GlyphData) -> NSImage {
        let ap = attrs(12.5, .semibold, g.digits)
        // Idle ink is the digit colour faded, not `secondary`: that is the WEEKLY metric's hue, and
        // borrowing it made an idle session figure look like a weekly one. This is also the only
        // style that tints its TEXT by activity at all, so it has to be the quietest version of the
        // same colour rather than a different colour.
        let at = attrs(12.5, .semibold, g.active ? g.digits : g.digits.withAlphaComponent(0.55))
        let pT = g.pctText as NSString, pS = pT.size(withAttributes: ap)
        let tokNew = g.tokText as NSString, tokOld = (g.rollFrom.isEmpty ? g.tokText : g.rollFrom) as NSString
        let tN = tokNew.size(withAttributes: at), tO = tokOld.size(withAttributes: at)
        // Reserve the wider of the two ONLY while a roll is actually in progress. Settled, the old
        // value is irrelevant, and reserving room for it left the item padded by however much
        // longer the previous number happened to be, which is what made the menu bar twitch when a
        // figure shrank.
        let rolling = g.rollPhase < 1 && !g.rollFrom.isEmpty && g.rollFrom != g.tokText
        let tokW = rolling ? max(tN.width, tO.width) : tN.width
        let gap: CGFloat = 5
        let w = ceil(pS.width) + gap + ceil(tokW), h = max(ceil(pS.height), ceil(tN.height))
        let phase = max(0, min(1, g.rollPhase))
        return img(w, h) {
            pT.draw(at: NSPoint(x: 0, y: (h - pS.height) / 2), withAttributes: ap)
            let tx = ceil(pS.width) + gap, baseY = (h - tN.height) / 2
            if !rolling {
                tokNew.draw(at: NSPoint(x: tx, y: baseY), withAttributes: at)
            } else {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: tx, y: 0, width: tokW, height: h)).addClip()
                tokNew.draw(at: NSPoint(x: tx, y: baseY - h * CGFloat(1 - phase)), withAttributes: at)  // rises in
                tokOld.draw(at: NSPoint(x: tx, y: baseY + h * CGFloat(phase)), withAttributes: at)        // rises out
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    // A live equalizer: five pill bars whose heights track the most recent burn-rate
    // samples. Tiny, no text - pure motion. Dims when nothing's flowing.
    private static func bars(_ g: GlyphData) -> NSImage {
        let n = 5, bw: CGFloat = 2.0, gap: CGFloat = 1.4, barsH: CGFloat = 13
        let w = CGFloat(n) * bw + CGFloat(n - 1) * gap
        let wk = g.hasSecondary, wkH: CGFloat = 2.5, wkGap: CGFloat = 3
        let barsY = wk ? wkGap + wkH : 0, h = barsH + barsY
        var vals = Array(g.spark.suffix(n))
        while vals.count < n { vals.insert(vals.first ?? 0, at: 0) }
        let col = g.active ? g.primary : g.primary.withAlphaComponent(0.5)
        return img(w, h) {
            for i in 0..<n {
                let x = CGFloat(i) * (bw + gap)
                let bh = max(bw, CGFloat(max(0, min(1, vals[i]))) * barsH)
                col.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: barsY, width: bw, height: bh), xRadius: bw/2, yRadius: bw/2).fill()
            }
            if wk { weeklyBar(w, g.secFrac, g.secondary, wkH) }   // slim weekly bar beneath
        }
    }

    // Signal-strength bars: four ascending bars, lit from the left as the live token
    // RATE climbs (all faint at rest). Tiny, no text.
    private static func signal(_ g: GlyphData) -> NSImage {
        let n = 4, bw: CGFloat = 2.2, gap: CGFloat = 1.6, barsH: CGFloat = 12
        let w = CGFloat(n) * bw + CGFloat(n - 1) * gap
        let wk = g.hasSecondary, wkH: CGFloat = 2.5, wkGap: CGFloat = 3
        let barsY = wk ? wkGap + wkH : 0, h = barsH + barsY
        let lit = Int((Double(n) * max(0, min(1, g.needle))).rounded(.up))
        let on = g.active ? g.primary : g.primary.withAlphaComponent(0.7)
        return img(w, h) {
            for i in 0..<n {
                let x = CGFloat(i) * (bw + gap)
                let bh = barsH * (0.3 + 0.7 * CGFloat(i) / CGFloat(n - 1))
                (i < lit ? on : track(0.28)).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: barsY, width: bw, height: bh), xRadius: bw/2, yRadius: bw/2).fill()
            }
            if wk { weeklyBar(w, g.secFrac, g.secondary, wkH) }
        }
    }

    // A glowing ember beside the %: the dot's core + halo swell and brighten with the
    // live rate, and settle to a dim coal at rest.
    private static func ember(_ g: GlyphData) -> NSImage {
        let a = attrs(PRIMARY, .semibold, g.digits)
        let ts = (g.pctText as NSString).size(withAttributes: a)
        let slot: CGFloat = 11, gap: CGFloat = 4
        let w = slot + gap + ceil(ts.width), h = max(slot, ceil(ts.height))
        let intensity: CGFloat = g.active ? 0.4 + 0.6 * CGFloat(max(0, min(1, g.needle))) : 0.22
        return img(w, h) {
            let cx = slot/2, cy = h/2
            let glowR = 3.0 + 2.6 * intensity
            g.primary.withAlphaComponent(0.20 * intensity).setFill()
            NSBezierPath(ovalIn: NSRect(x: cx - glowR, y: cy - glowR, width: glowR*2, height: glowR*2)).fill()
            let coreR = 2.1 + 1.4 * intensity
            (g.active ? g.primary : g.primary.withAlphaComponent(0.6)).setFill()
            NSBezierPath(ovalIn: NSRect(x: cx - coreR, y: cy - coreR, width: coreR*2, height: coreR*2)).fill()
            (g.pctText as NSString).draw(at: NSPoint(x: slot + gap, y: (h - ts.height)/2), withAttributes: a)
        }
    }

    // THE LIVING EMBER - a real flame rendered live beside the %. Height + brightness track
    // the burn rate (tokens/min), the core runs cooler-orange at a simmer and white-hot under a
    // heavy Opus run, it flickers and throws sparks while tokens flow, and rages toward the
    // limit (redline). Idle = a calm banked coal. This is Burndown's signature glyph.
    private static func flame(_ g: GlyphData) -> NSImage {
        let a = attrs(PRIMARY, .semibold, g.digits)
        let ts = (g.pctText as NSString).size(withAttributes: a)
        // Geometry: 13pt slot + 4pt gap + text; cx = 6.5, baseY = 1.5 + botPad.
        // FLAME ADJUST scales the flame, so the slot has to widen with it or a big flame clips.
        let sz = CGFloat(max(0.8, min(2.0, g.flameSize)))
        let slot: CGFloat = 13 * max(1, sz * 0.82), gap: CGFloat = 4
        let wk = g.hasSecondary                              // Both mode → slim weekly bar beneath
        let wkH: CGFloat = 2.5, botPad: CGFloat = wk ? wkH + 2.0 : 0
        let w = slot + gap + ceil(ts.width), h = max(16, ceil(ts.height) + 2) + botPad

        let tier = g.tier
        let heat = CGFloat(max(0, min(1, g.heat)))           // tier heat, lerped by the animator
        let r = CGFloat(max(0, min(1, g.redline)))           // redline overlay
        let e = g.phase                                      // BurnClock.elapsed (monotonic seconds)
        let over = tier == .overLimit
        /// Every fire frequency in the product: sin(2*pi*f*elapsed). Never the wrapped phase.
        func osc(_ hz: Double) -> CGFloat { CGFloat(sin(2 * .pi * hz * e)) }

        // Fire palette, emissive and theme-independent. Redline is the overLimit token.
        let coal = sEmber, outer = sFlame, mid = sGlow, hot = sCore, anger = sRedline

        return img(w, h) {
            let cx = slot / 2, baseY: CGFloat = 1.5 + botPad
            let maxH = h - baseY - 1.5

            // Motion straight off the BurnTier tables (amplitude pt, Hz), evaluated on elapsed.
            // Amplitudes scale with FLAME ADJUST so a bigger flame also moves proportionally more
            // (the 2.5 Hz frequency ceiling is untouched - only amplitude scales).
            let f1 = tier.flameFlick, sw = tier.flameSway
            var flick = CGFloat(f1.amp) * osc(f1.hz)
            if let f2 = tier.flameFlick2 { flick += CGFloat(f2.amp) * osc(f2.hz) }   // heavy/redline secondary
            flick *= sz
            let tipSway = CGFloat(sw.amp) * osc(sw.hz) * sz

            // Reserve headroom above the tip when smoke is on, so the wisps have somewhere to rise.
            let ceiling = g.flameSmoke ? maxH - 2.2 : maxH

            // L3 body geometry. Height first: it is HARD-CAPPED by the menu bar box, so scaling the
            // size can only make the flame as tall as the bar allows. Width is then clamped to a
            // flame-like aspect (never wider than ~0.62 of the height), otherwise a large size just
            // fattens a capped-height flame into a blob.
            var flameH = min(ceiling, (5.0 + (maxH - 5.0) * heat) * sz + flick + r * 1.6 + CGFloat(g.flare) * 0.8)
            if over { flameH = min(ceiling, (2.0 * sz) + flick) }
            let bodyW = min((4.6 + 1.8 * heat) * sz, flameH * 0.62)

            // L1 Halo (spec: mid+ only). It is the flame's readability on a busy menu bar, so a
            // scaled-up flame keeps a faint halo at every tier.
            if tier.isMidPlus || sz > 1.15 {
                let hh = flameH + 3 * min(sz, 1.8)
                let a0 = tier.isMidPlus ? (0.10 + 0.08 * heat + 0.30 * r) : 0.07
                // A soft radial falloff, not a flat ellipse - a hard-edged halo reads as a smudge.
                let col = outer.blended(to: anger, r)
                let hc = NSPoint(x: cx, y: baseY + flameH * 0.42)
                NSGradient(colors: [col.withAlphaComponent(a0), col.withAlphaComponent(0)])?
                    .draw(fromCenter: hc, radius: 0, toCenter: hc, radius: hh * 0.62, options: [])
            }

            // L2 Base ember: lying ellipse 2.6 x 1.1pt at (cx, baseY - 0.4).
            coal.blended(to: mid, 0.25 * heat).withAlphaComponent(0.9).setFill()
            let er = max(1.3, bodyW * 0.42)
            NSBezierPath(ovalIn: NSRect(x: cx - er, y: baseY - 0.95, width: er * 2, height: 1.1 * min(sz, 1.8))).fill()

            // L3/L4: the FlameMark silhouette - a TEARDROP, not a cone: a rounded belly low down,
            // tapering to a pointed crown, leaning asymmetric (the right belly sits lower, at 0.30h,
            // so the flame reads as licking to one side rather than as an isoceles triangle).
            func flamePath(_ ww: CGFloat, _ hh: CGFloat, _ shift: CGFloat, _ lift: CGFloat = 0) -> NSBezierPath {
                let b = baseY + lift
                let p = NSBezierPath()
                p.move(to: NSPoint(x: cx, y: b))                                     // narrow foot
                p.curve(to: NSPoint(x: cx - ww / 2, y: b + hh * 0.38),               // out to the left belly
                        controlPoint1: NSPoint(x: cx - ww * 0.42, y: b),
                        controlPoint2: NSPoint(x: cx - ww / 2, y: b + hh * 0.18))
                p.curve(to: NSPoint(x: cx + shift, y: b + hh),                       // up to the crown
                        controlPoint1: NSPoint(x: cx - ww / 2, y: b + hh * 0.68),
                        controlPoint2: NSPoint(x: cx - ww * 0.16 + shift, y: b + hh * 0.90))
                p.curve(to: NSPoint(x: cx + ww / 2, y: b + hh * 0.30),               // down the right, lower belly
                        controlPoint1: NSPoint(x: cx + ww * 0.20 + shift, y: b + hh * 0.88),
                        controlPoint2: NSPoint(x: cx + ww / 2, y: b + hh * 0.62))
                p.curve(to: NSPoint(x: cx, y: b),                                    // round back to the foot
                        controlPoint1: NSPoint(x: cx + ww / 2, y: b + hh * 0.12),
                        controlPoint2: NSPoint(x: cx + ww * 0.42, y: b))
                p.close(); return p
            }
            // Two shells, not three (layers L3 + L4). The core is NESTED IN THE LOWER BELLY - it is
            // lifted off the foot and kept short, so it reads as a heart of light inside the flame
            // rather than a white wedge filling the bottom.
            outer.blended(to: anger, 0.5 * r).withAlphaComponent(1.0).setFill()
            flamePath(bodyW, flameH, tipSway).fill()
            hot.blended(to: sWhite, r).withAlphaComponent(min(1, 0.92 + 0.15 * CGFloat(g.flare))).setFill()
            flamePath(bodyW * 0.40, flameH * 0.50, tipSway * 0.6, flameH * 0.10).fill()

            // L5 Sparks: max two, 1.8s cycles offset 50 percent, scheduled from elapsed (never a
            // particle system). The default fires them at redline only; FLAME ADJUST can fire them at
            // every tier, where their brightness rides the heat instead of the redline overlay.
            let sparkOn = !over && (g.flameSparks == .always || (g.flameSparks == .redline && r > 0))
            if sparkOn {
                let bright = g.flameSparks == .always ? max(0.35, heat) : r
                for i in 0..<2 {
                    let t = ((e / 1.8) + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)   // 0→1 rise
                    let sy = baseY + flameH * 0.55 + CGFloat(t) * (maxH * 0.5)
                    let sx = cx + tipSway * 0.5 + CGFloat(sin(2 * .pi * (0.5 + Double(i) * 0.3) * e)) * 0.8 * sz
                    let rad = (0.50 - 0.16 * CGFloat(t)) * sz
                    hot.blended(to: sWhite, r).withAlphaComponent(max(0, (1 - CGFloat(t)) * 0.85 * bright)).setFill()
                    NSBezierPath(ovalIn: NSRect(x: sx - rad, y: sy - rad, width: rad * 2, height: rad * 2)).fill()
                }
            }
            // Smoke (FLAME ADJUST only; the default glyph has none): thin wisps drifting off the tip.
            if g.flameSmoke, !over {
                let tipY = baseY + flameH
                for i in 0..<3 {
                    let t = CGFloat(((e / 2.6) + Double(i) * 0.333).truncatingRemainder(dividingBy: 1))
                    let sy = tipY + t * (h - tipY - 0.5)
                    let sx = cx + tipSway * 0.4 + CGFloat(sin(2 * .pi * 0.3 * e + Double(i) * 1.2)) * (0.7 + t * 1.8) * sz
                    let rad = (0.45 + t * 0.9) * sz
                    NSColor(calibratedWhite: 0.62, alpha: max(0, (0.13 + 0.10 * heat) * (1 - t))).setFill()
                    NSBezierPath(ovalIn: NSRect(x: sx - rad, y: sy - rad, width: rad * 2, height: rad * 2)).fill()
                }
            }
            // The % beside the flame, in the ordinary metric ink (the flame is the fire here;
            // the burning-number styles are Hearth / Burnfront / Kiln).
            (g.pctText as NSString).draw(at: NSPoint(x: slot + gap, y: botPad + ((h - botPad) - ts.height) / 2),
                                         withAttributes: a)
            if wk { weeklyBar(w, g.secFrac, g.secondary, wkH) }   // weekly fill pinned to the bottom
        }
    }

    // INFERNO - the % numeral itself is cast in fire: a vertical flame gradient fills the glyphs,
    // running deeper red at the base and brighter at the crown, and the whole palette heats up as
    // usage climbs (calm clay at 0% → molten amber/white toward the cap). Pure typography, no icon.
    private static func inferno(_ g: GlyphData) -> NSImage {
        let a = attrs(PRIMARY + 1, .bold, .white)
        let ts = (g.pctText as NSString).size(withAttributes: a)
        let wk = g.hasSecondary                                  // Both mode → slim weekly bar beneath
        let wkH: CGFloat = 2.5, botPad: CGFloat = wk ? wkH + 2.0 : 0
        let w = ceil(ts.width), h = ceil(ts.height) + botPad
        let heat = CGFloat(max(0, min(1, g.pct))) // palette temperature follows usage level
        let baseCol = (NSColor(hex: "B23207") ?? .red).blended(to: NSColor(hex: "E2510B") ?? .orange, heat)
        let midCol  = (NSColor(hex: "E2510B") ?? .orange).blended(to: NSColor(hex: "F9A825") ?? .yellow, heat)
        let tipCol  = (NSColor(hex: "F9A825") ?? .yellow).blended(to: NSColor(hex: "FFF3C4") ?? .white, heat)
        // Text mask: white glyphs on clear.
        let mask = img(w, h) { (g.pctText as NSString).draw(at: NSPoint(x: 0, y: botPad), withAttributes: a) }
        return img(w, h) {
            // Fill the rect with the flame gradient, then keep it only where the text is.
            NSGradient(colors: [baseCol, midCol, tipCol])?.draw(in: NSRect(x: 0, y: botPad, width: w, height: h - botPad), angle: 90)
            mask.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .destinationIn, fraction: 1)
            if wk { weeklyBar(w, g.secFrac, g.secondary, wkH) }
        }
    }

    // ── BURNING-NUMBER styles: the % text itself is the fire. Shared machinery ──

    // Fire palette (fixed identity colors, independent of the accent).
    private static let fRust   = NSColor(hex: "A0341A") ?? .red
    private static let fOrange = NSColor(hex: "E2510B") ?? .orange
    private static let fAmber  = NSColor(hex: "F9A825") ?? .yellow
    private static let fCream  = NSColor(hex: "FFF3C4") ?? .white
    private static let fSpark  = NSColor(hex: "FFE9A8") ?? .white

    // The fire palette (typographic heat). char keys off the bar material; the rest are constants.
    // Redline red inside fire is the overLimit token (dark value, emissive rule).
    private static let sEmber   = NSColor(hex: "A63A22") ?? .brown
    private static let sFlame   = NSColor(hex: "D95B2E") ?? .orange
    private static let sGlow    = NSColor(hex: "F0A05A") ?? .orange
    private static let sCore    = NSColor(hex: "FFE2C2") ?? .white
    private static let sWhite   = NSColor(hex: "FFF4E4") ?? .white
    private static let sRedline = NSColor(hex: "D2553A") ?? .red
    // NSApp can be nil in the headless snapshot tools; default to a dark bar there (menu bars usually are).
    private static func barIsDark() -> Bool { (NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .darkAqua) == .darkAqua }
    private static func sChar() -> NSColor { NSColor(hex: barIsDark() ? "4A2E22" : "3A2A22") ?? .darkGray }
    // What a native template icon resolves to on this bar. Any style that wants to pass for a system
    // icon draws in this, NOT in labelColor (which follows the APP theme, not the menu bar's).
    private static func barInk() -> NSColor { barIsDark() ? .white : (NSColor(hex: "1C1C1C") ?? .black) }

    // BEACON: a readout that passes for a native menu-bar icon, then winks. The digits rest in the
    // bar's own ink; g.beacon (0…1, driven by the app's 3-5s wink clock) blends them to the accent for
    // a fraction of a second. No glow, no motion, no shape change - the color IS the whole event.
    private static func beacon(_ g: GlyphData) -> NSImage {
        let e = CGFloat(max(0, min(1, g.beacon)))
        let base = barInk(), lit = base.blended(to: g.accent, e)
        let glow = CGFloat(max(0, min(1, g.beaconGlow))) * e
        let a = attrs(PRIMARY, g.digitWeight, base)
        let ts = (g.pctText as NSString).size(withAttributes: a)
        let wk = g.hasSecondary
        let wkH: CGFloat = 2.5, botPad: CGFloat = wk ? wkH + 2.0 : 0
        let mark = g.beaconMark
        // A halo needs room to fall off or it clips to a hard square at the glyph's edge. The pad keys
        // off the SETTING, not the envelope, so the glyph never changes width mid-wink.
        let gp: CGFloat = g.beaconGlow > 0.01 ? 8 : 0

        // A soft halo behind whatever is winking. One radial gradient, only while lit - free at rest.
        func halo(_ c: NSPoint, _ r: CGFloat) {
            guard glow > 0.01 else { return }
            NSGradient(colors: [g.accent.withAlphaComponent(0.55 * glow), g.accent.withAlphaComponent(0)])?
                .draw(fromCenter: c, radius: 0, toCenter: c, radius: r, options: [])
        }

        if mark.isBare {                       // no digits at all: the glyph IS the mark
            let d: CGFloat = mark == .ringOnly ? 9.5 : 7, pad: CGFloat = 3 + gp
            let W = d + pad * 2, H = d + pad * 2 + botPad
            return img(W, H) {
                let c = NSPoint(x: W / 2, y: botPad + (H - botPad) / 2)
                halo(c, d * 1.4)
                let box = NSRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)
                if mark == .dotOnly {
                    // Rest is a dim dot (still legible as "the app is here"), the wink brings it up.
                    base.withAlphaComponent(0.55 + 0.45 * e).blended(to: g.accent, e).setFill()
                    NSBezierPath(ovalIn: box).fill()
                } else {
                    // The ring carries the usage fraction, so it stays readable at rest - the wink is
                    // the arc lighting up. Its own track, in the bar's ink: the shared one is tuned
                    // for coloured glyphs and disappears here.
                    let lw: CGFloat = 1.8, rad = d / 2 - lw / 2
                    let track = NSBezierPath()
                    track.appendArc(withCenter: c, radius: rad, startAngle: 0, endAngle: 360)
                    track.lineWidth = lw; base.withAlphaComponent(0.22).setStroke(); track.stroke()
                    let arc = NSBezierPath()
                    arc.appendArc(withCenter: c, radius: rad, startAngle: 90,
                                  endAngle: 90 - 360 * CGFloat(min(1, max(0.02, g.pct))), clockwise: true)
                    arc.lineWidth = lw; arc.lineCapStyle = .round
                    base.withAlphaComponent(0.75).blended(to: g.accent, e).setStroke(); arc.stroke()
                }
                if wk { weeklyBar(W, g.secFrac, lit, wkH) }
            }
        }

        // Marks that keep the number: measure the digits, then add room for the mark itself.
        let dotGap: CGFloat = 2.5, dotD: CGFloat = 3.5
        let extraW: CGFloat = (mark == .dot) ? dotGap + dotD : 0
        let extraH: CGFloat = (mark == .pip) ? 1.5 : (mark == .underline ? 2.5 : 0)
        let tw = ceil(ts.width), th = ceil(ts.height)
        let W = tw + extraW + gp * 2, H = th + botPad + extraH + gp * 2
        let x0 = gp, y0 = botPad + gp        // the text origin, inside any glow padding
        // "% sign only" splits the string: the digits stay in the bar's ink, the sign carries the wink.
        let signIdx = g.pctText.lastIndex(of: "%")
        return img(W, H) {
            switch mark {
            case .percent:
                // Two lobes rather than one big circle: a single radial over a wide number either
                // clips at the glyph edge or needs padding that shoves the neighbouring icons around.
                halo(NSPoint(x: x0 + tw * 0.28, y: y0 + th / 2), th * 0.95)
                halo(NSPoint(x: x0 + tw * 0.72, y: y0 + th / 2), th * 0.95)
                (g.pctText as NSString).draw(at: NSPoint(x: x0, y: y0), withAttributes: attrs(PRIMARY, g.digitWeight, lit))
            case .sign:
                if let i = signIdx {
                    let head = String(g.pctText[g.pctText.startIndex..<i]), tail = String(g.pctText[i...])
                    let ha = attrs(PRIMARY, g.digitWeight, base)
                    (head as NSString).draw(at: NSPoint(x: x0, y: y0), withAttributes: ha)
                    let hx = x0 + ceil((head as NSString).size(withAttributes: ha).width)
                    halo(NSPoint(x: hx + 4, y: y0 + th / 2), 9)
                    (tail as NSString).draw(at: NSPoint(x: hx, y: y0), withAttributes: attrs(PRIMARY, g.digitWeight, lit))
                } else {   // bare-number format has no sign to wink; fall back to the whole readout
                    (g.pctText as NSString).draw(at: NSPoint(x: x0, y: y0), withAttributes: attrs(PRIMARY, g.digitWeight, lit))
                }
            case .dot:
                (g.pctText as NSString).draw(at: NSPoint(x: x0, y: y0), withAttributes: a)
                let c = NSPoint(x: x0 + tw + dotGap + dotD / 2, y: y0 + th * 0.42)
                halo(c, dotD * 2.6)
                base.withAlphaComponent(0.35 + 0.65 * e).blended(to: g.accent, e).setFill()
                NSBezierPath(ovalIn: NSRect(x: c.x - dotD / 2, y: c.y - dotD / 2, width: dotD, height: dotD)).fill()
            case .pip:
                (g.pctText as NSString).draw(at: NSPoint(x: x0, y: y0), withAttributes: a)
                let d: CGFloat = 2, c = NSPoint(x: x0 + tw - d, y: y0 + th + 0.5)
                halo(c, 6)
                lit.withAlphaComponent(0.25 + 0.75 * e).setFill()
                NSBezierPath(ovalIn: NSRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)).fill()
            case .underline:
                (g.pctText as NSString).draw(at: NSPoint(x: x0, y: y0 + extraH), withAttributes: a)
                // The line sweeps out from the centre as the wink rises, so it reads as motion, not a bar.
                let lw = tw * e, r = NSRect(x: x0 + (tw - lw) / 2, y: y0, width: lw, height: 1.5)
                halo(NSPoint(x: x0 + tw / 2, y: y0), 10)
                g.accent.withAlphaComponent(0.9 * Double(e)).setFill()
                NSBezierPath(roundedRect: r, xRadius: 0.75, yRadius: 0.75).fill()
            case .dotOnly, .ringOnly: break   // handled above
            }
            if wk { weeklyBar(W, g.secFrac, mark == .percent ? lit : base, wkH) }
        }
    }

    // SMOLDER: charcoal-warm ember digits lit from below, breathing. The quiet default.
    // No sparks, no cracks, ever. All motion derives from g.phase (BurnClock elapsed).
    private static func smolder(_ g: GlyphData) -> NSImage {
        let a = attrs(PRIMARY, g.digitWeight, .white)
        let ts = (g.pctText as NSString).size(withAttributes: a)
        let wk = g.hasSecondary
        let wkH: CGFloat = 2.5, botPad: CGFloat = wk ? wkH + 2.0 : 0
        let W = ceil(ts.width), H = ceil(ts.height) + botPad, th = ceil(ts.height)
        let tier = g.tier
        let heat = CGFloat(max(0, min(1, g.heat)))                                  // tier heat, lerped
        let r = CGFloat(max(0, min(1, g.redline))), e = g.phase                     // e = BurnClock.elapsed
        func osc(_ hz: Double) -> CGFloat { CGFloat(sin(2 * .pi * hz * e)) }
        let size = NSSize(width: W, height: H)
        let mask = cachedTextMask(g.pctText, a, size: size, at: NSPoint(x: 0, y: botPad),
                                  key: maskKey(g.pctText, g.digitWeight, size, botPad))
        let body = sEmber.blended(to: sRedline, 0.35 * r)                          // L5 redline tints the body
        let intensity = CGFloat(g.smolderIntensity)                                 // SMOLDER ADJUST (area 2)
        let bf = (g.smolderBreathSlow ? 0.5 : 1.0)                                  // Breath: Slow halves frequency
        // L3 baseline smolder: A = 0.22 + 0.18*heat + 0.10*sin(2pi f elapsed), f + peak from the tier table.
        let bHz = tier.smolderBreathHz * bf
        let bA = max(0, min(CGFloat(tier.smolderPeakAlpha), (0.22 + 0.18 * heat + 0.10 * osc(bHz)) * intensity))
        let comp = throughText(size, mask: mask) {
            body.setFill(); NSRect(x: 0, y: botPad, width: W, height: th).fill()   // L2 solid ember body
            NSGradient(colors: [sGlow.withAlphaComponent(bA), sGlow.withAlphaComponent(0)])?
                .draw(in: NSRect(x: 0, y: botPad, width: W, height: th * 0.42), angle: 90)   // L3 baseline smolder
            if tier.isMidPlus, g.smolderWarmthWander {                               // L4 wandering warmth (mid+ only)
                // one hotspot on a 14s drift
                let cx = W * (0.5 + 0.32 * CGFloat(sin(2 * .pi * e / 14))), cy = botPad + th * 0.35
                NSGradient(colors: [sCore.withAlphaComponent(0.18 * heat), sCore.withAlphaComponent(0)])?
                    .draw(fromCenter: NSPoint(x: cx, y: cy), radius: 0,
                          toCenter: NSPoint(x: cx, y: cy), radius: 4.5 + 2.0 * heat, options: [])
            }
            if r > 0 {                                                              // L5 fire/white capline
                sWhite.withAlphaComponent(0.4 * r).setFill()
                NSRect(x: 0, y: botPad + th * 0.78, width: W, height: 1).fill()
            }
        }
        return img(W, H) {
            comp.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            if wk { weeklyBar(W, g.secFrac, g.secondary, wkH) }
        }
    }

    // BURNFRONT: the number is consumed left to right; the burn front IS the usage fraction.
    // The whole fire of the style is one incandescent seam hairline.
    private static func burnfront(_ g: GlyphData) -> NSImage {
        let a = attrs(PRIMARY, g.digitWeight, .white)
        let ts = (g.pctText as NSString).size(withAttributes: a)
        let wk = g.hasSecondary
        let wkH: CGFloat = 2.5, botPad: CGFloat = wk ? wkH + 2.0 : 0
        let th = ceil(ts.height)
        let W = ceil(ts.width), H = th + botPad + 4.5              // headroom: the fire rides high above the top run
        let tier = g.tier
        let heat = CGFloat(max(0, min(1, g.heat)))                 // tier heat, lerped
        let r = CGFloat(max(0, min(1, g.redline))), e = g.phase    // e = BurnClock.elapsed
        func osc(_ hz: Double) -> CGFloat { CGFloat(sin(2 * .pi * hz * e)) }
        let pct = CGFloat(max(0, min(1, g.pct)))
        // drift = 0.4 * sin(2pi * 0.125 * elapsed) pt at idle (8s cycle), amplitude 0.8pt at heavy.
        let drift = (0.4 + 0.4 * heat) * osc(0.125)
        let frontX = max(1, min(W - 1, pct * W + drift))
        let size = NSSize(width: W, height: H)
        let mask = cachedTextMask(g.pctText, a, size: size, at: NSPoint(x: 0, y: botPad),
                                  key: maskKey(g.pctText, g.digitWeight, size, botPad))
        let barInk = barIsDark() ? NSColor.white : (NSColor(hex: "1C1C1C") ?? .black)   // L1 pinned bar ink (unburned)
        // L2 burned digits: fire/char at alpha 0.92 with a slow smolder, blending toward fire/flame by
        // 0.06 + 0.06*sin(2pi elapsed/10) (amplitude doubles at redline, L6). These deliberately recede:
        // Burnfront L2 takes a deliberate CONTRAST EXEMPTION (2:1, below the 3:1 graphics floor),
        // because spent budget should recede - the data is carried by the seam and the unburned digits.
        let smAmp: CGFloat = 0.06 * (1 + r)
        let burned = sChar().blended(to: sFlame, 0.06 + smAmp * CGFloat(sin(2 * .pi * e / 10)))
        let comp = throughText(size, mask: mask) {
            burned.withAlphaComponent(0.92).setFill(); NSRect(x: 0, y: botPad, width: frontX, height: th).fill()  // L2 burned
            barInk.setFill(); NSRect(x: frontX, y: botPad, width: W - frontX, height: th).fill()                  // L1 unburned
            // L3 ember falloff on the just-burned side only; widens to 4.5pt at redline and blends 40% to overLimit.
            let w3 = r > 0 ? 4.5 : 3.0 + 1.5 * heat
            NSGradient(colors: [sFlame.withAlphaComponent(0), sFlame.blended(to: sRedline, 0.4 * r).withAlphaComponent(0.35)])?
                .draw(in: NSRect(x: frontX - w3, y: botPad, width: w3, height: th), angle: 0)
            // L4 seam filament: the entire fire of the style is one incandescent hairline.
            let seamW: CGFloat = r > 0 ? 1.5 : 1.0                                         // L6 widens at redline
            sCore.blended(to: sWhite, r).withAlphaComponent(0.55 + 0.25 * osc(tier.seamHz)).setFill()
            NSRect(x: frontX - seamW / 2, y: botPad, width: seamW, height: th).fill()
        }
        // Every seam CROSSING gets treated by rank. Find the ink runs the cut passes through
        // (a `4` is cut twice, a `%` up to three times) and rank them top-down: the TOP run carries
        // the full flame lick + spark + a thin smoke wisp, the SECOND run a 0.55-0.6x lick, deeper
        // runs glow only (the L3 falloff above already glows every crossing). Smoke on the burning
        // NUMBER is sanctioned here; the FlameMark itself still never has smoke.
        let mkey = maskKey(g.pctText, g.digitWeight, size, botPad)
        // The seam drifts sub-pixel per frame; bucket the column so the run scan is a cache hit
        // on nearly every frame instead of re-reading the raster 30 times a second.
        let colKey = "\(mkey)@\(Int((frontX * 2).rounded()))"
        let runs: [(lo: CGFloat, hi: CGFloat)]
        if let cached = runsCache[colKey] { runs = cached }
        else {
            let r = maskRep(g.pctText, a, size: size, at: NSPoint(x: 0, y: botPad), key: mkey)
                .map { inkRuns($0, atX: frontX, size: size) } ?? []
            if runsCache.count > 96 { runsCache.removeAll(keepingCapacity: true) }
            runsCache[colKey] = r
            runs = r
        }
        let ranked = runs.sorted { $0.hi > $1.hi }        // topmost ink run first
        let lightBar = !barIsDark()

        return img(W, H) {
            comp.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            let baseLick = 1.2 + 2.2 * heat + r * 0.8
            /// One flame tongue rising off a crossing, swaying on the seam frequency.
            func lick(_ topY: CGFloat, _ hgt: CGFloat, _ alpha: CGFloat) {
                let sway = 0.6 * osc(tier.seamHz * 2)
                let p = NSBezierPath()
                p.move(to: NSPoint(x: frontX - 1.0, y: topY - 0.8))
                p.curve(to: NSPoint(x: frontX + sway, y: topY + hgt),
                        controlPoint1: NSPoint(x: frontX - 1.0, y: topY + hgt * 0.45),
                        controlPoint2: NSPoint(x: frontX - 0.1 + sway, y: topY + hgt * 0.85))
                p.curve(to: NSPoint(x: frontX + 1.0, y: topY - 0.8),
                        controlPoint1: NSPoint(x: frontX + 0.1 + sway, y: topY + hgt * 0.85),
                        controlPoint2: NSPoint(x: frontX + 1.0, y: topY + hgt * 0.30))
                p.close()
                sFlame.blended(to: sRedline, 0.5 * r).withAlphaComponent(alpha).setFill(); p.fill()
                sCore.blended(to: sWhite, r).withAlphaComponent(alpha * 0.85).setFill()
                NSBezierPath(ovalIn: NSRect(x: frontX + sway * 0.5 - 0.45, y: topY + hgt * 0.35,
                                            width: 0.9, height: max(0.6, hgt * 0.4))).fill()
            }
            if let top = ranked.first {
                lick(top.hi, baseLick, 0.95)                       // TOP run: the full lick
                // ...plus a thin smoke wisp riding off it.
                for i in 0..<2 {
                    let t = CGFloat(((e / 3.0) + Double(i) * 0.5).truncatingRemainder(dividingBy: 1))
                    let sy = top.hi + baseLick + t * 3.0
                    let sx = frontX + CGFloat(sin(2 * .pi * 0.35 * e + Double(i))) * (0.8 + t * 1.4)
                    let rad = 0.5 + t * 0.7
                    NSColor(calibratedWhite: 0.62, alpha: max(0, (0.10 + 0.08 * heat) * (1 - t))).setFill()
                    NSBezierPath(ovalIn: NSRect(x: sx - rad, y: sy - rad, width: rad * 2, height: rad * 2)).fill()
                }
                // ...plus the spark (heavy/redline; ONE alive at a time), born at the TOP run, rising 3pt.
                if let cycle = tier.seamSparkCycle {
                    let t = CGFloat((e / cycle).truncatingRemainder(dividingBy: 1))
                    let sx = frontX + 0.8 * osc(0.9), sy = top.hi + t * 3
                    let rad = 0.7 - 0.3 * t
                    sCore.withAlphaComponent(max(0, (1 - t) * 0.6)).setFill()
                    NSBezierPath(ovalIn: NSRect(x: sx - rad, y: sy - rad, width: rad * 2, height: rad * 2)).fill()
                }
                // Light menu-bar material: core-white sparks read weakly, so earn a SECOND spark
                // from mid heat, drawn in fire/flame at higher alpha.
                if lightBar, heat >= BurnTier.mid.heat {
                    let t = CGFloat(((e / 2.0) + 0.5).truncatingRemainder(dividingBy: 1))
                    let sx = frontX - 0.7 * osc(1.1), sy = top.hi + t * 3
                    let rad = 0.65 - 0.25 * t
                    sFlame.withAlphaComponent(max(0, (1 - t) * 0.85)).setFill()
                    NSBezierPath(ovalIn: NSRect(x: sx - rad, y: sy - rad, width: rad * 2, height: rad * 2)).fill()
                }
            }
            if ranked.count > 1 { lick(ranked[1].hi, baseLick * 0.58, 0.72) }   // SECOND run: 0.55-0.6x
            // Deeper runs (index 2+) glow only - the L3 ember falloff already lights every crossing.
            if wk { weeklyBar(W, g.secFrac, g.secondary, wkH) }
        }
    }

    // KILN: metal in a kiln - one warm mass with a single band of interior light convecting up.
    private static func kiln(_ g: GlyphData) -> NSImage {
        let a = attrs(PRIMARY, g.digitWeight, .white)
        let ts = (g.pctText as NSString).size(withAttributes: a)
        let wk = g.hasSecondary
        let wkH: CGFloat = 2.5, botPad: CGFloat = wk ? wkH + 2.0 : 0
        let W = ceil(ts.width), H = ceil(ts.height) + botPad, th = ceil(ts.height)
        let tier = g.tier
        let heat = CGFloat(max(0, min(1, g.heat)))                                   // tier heat, lerped
        let r = CGFloat(max(0, min(1, g.redline))), e = g.phase                      // e = BurnClock.elapsed
        let size = NSSize(width: W, height: H)
        let mask = cachedTextMask(g.pctText, a, size: size, at: NSPoint(x: 0, y: botPad),
                                  key: maskKey(g.pctText, g.digitWeight, size, botPad))
        let bottom = sEmber.blended(to: sRedline, 0.30 * r)
        let v = tier.kilnBandSpeed                                                   // band speed pt/s (BurnTier table)
        let span = Double(th + 6)
        // y = (elapsed * v) mod (textH + 6) - 3; scrolls upward and wraps. No sparks, no sway, ever.
        let bandY = botPad + CGFloat((e * v).truncatingRemainder(dividingBy: span)) - 3
        let bandCol = sCore.blended(to: sWhite, r).withAlphaComponent(0.20 + 0.15 * heat + 0.25 * r)
        func band(_ y: CGFloat) {
            NSGradient(colors: [bandCol.withAlphaComponent(0), bandCol, bandCol.withAlphaComponent(0)])?
                .draw(in: NSRect(x: -1, y: y - 2, width: W + 2, height: 4), angle: 98)
        }
        let comp = throughText(size, mask: mask) {
            NSGradient(colors: [bottom, sFlame])?.draw(in: NSRect(x: 0, y: botPad, width: W, height: th), angle: 90)  // L1
            band(bandY)                                                              // L2 convection band
            if r > 0.3 { band(bandY - CGFloat(span) * 0.5) }                         // L4 second band at redline
            sFlame.blended(to: sGlow, 0.12).setFill()                               // L3 crown light
            NSRect(x: 0, y: botPad + th - 1, width: W, height: 1).fill()
        }
        return img(W, H) {
            comp.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            if wk { weeklyBar(W, g.secFrac, g.secondary, wkH) }
        }
    }

    /// White text mask at the given origin inside a canvas of `size` - used with
    /// .destinationIn to trap fire textures inside the glyphs.
    private static func textMask(_ str: String, _ a: [NSAttributedString.Key: Any], size: NSSize, at origin: NSPoint) -> NSImage {
        img(size.width, size.height) { (str as NSString).draw(at: origin, withAttributes: a) }
    }

    // The glyph mask is identical from frame to frame - only the fire moving THROUGH it changes.
    // Rebuilding it every animation frame (an NSImage + lockFocus + a full text draw) was most of
    // the burning-number styles' cost at 30fps. Cache it, keyed by everything that can change it.
    // Main-thread only; small and bounded (one entry per live text/size, plus Settings previews).
    private static var maskCache: [String: NSImage] = [:]
    private static func cachedTextMask(_ str: String, _ a: [NSAttributedString.Key: Any],
                                       size: NSSize, at origin: NSPoint, key: String) -> NSImage {
        if let m = maskCache[key] { return m }
        if maskCache.count > 24 { maskCache.removeAll(keepingCapacity: true) }   // bounded, never grows
        let m = textMask(str, a, size: size, at: origin)
        maskCache[key] = m
        return m
    }
    /// The identity of a glyph mask: text, weight, canvas, baseline.
    private static func maskKey(_ str: String, _ w: NSFont.Weight, _ size: NSSize, _ originY: CGFloat) -> String {
        "\(str)|\(w.rawValue)|\(Int(size.width))x\(Int(size.height))|\(Int(originY * 2))"
    }

    // ── The Burnfront multi-crossing seam ────────────────────────────────────────────────
    // The seam is a vertical cut. To treat every ink crossing correctly we need the actual ink
    // runs the seam column passes through ("segmentsAt"): a `4` at the seam may be cut twice, a
    // `%` three times. Rasterizing the mask is the only honest way to know. The rep is cached
    // because the glyph text rarely changes while the seam drifts every frame.
    private static var maskRepCache: (key: String, rep: NSBitmapImageRep)?
    private static var runsCache: [String: [(lo: CGFloat, hi: CGFloat)]] = [:]
    private static func maskRep(_ str: String, _ a: [NSAttributedString.Key: Any],
                                size: NSSize, at origin: NSPoint, key: String) -> NSBitmapImageRep? {
        if let c = maskRepCache, c.key == key { return c.rep }
        guard let tiff = textMask(str, a, size: size, at: origin).tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        maskRepCache = (key, rep)
        return rep
    }

    /// Vertical ink runs (bottom-up, in POINTS) that a cut at `x` passes through.
    /// Anti-aliased gaps under 2pt merge, so one stroke never splits into two licks.
    private static func inkRuns(_ rep: NSBitmapImageRep, atX x: CGFloat, size: NSSize) -> [(lo: CGFloat, hi: CGFloat)] {
        let pw = rep.pixelsWide, ph = rep.pixelsHigh
        guard pw > 0, ph > 0, size.width > 0, size.height > 0 else { return [] }
        let px = max(0, min(pw - 1, Int((x / size.width) * CGFloat(pw))))
        let ptPerPx = size.height / CGFloat(ph)
        var runs: [(lo: CGFloat, hi: CGFloat)] = []
        var start: Int? = nil
        for i in 0...ph {                                   // i = bottom-up pixel row; ph closes a trailing run
            let inked: Bool
            if i == ph { inked = false } else {
                let a = rep.colorAt(x: px, y: ph - 1 - i)?.alphaComponent ?? 0   // rep rows are top-down
                inked = a > 0.35
            }
            if inked, start == nil { start = i }
            if !inked, let s = start {
                runs.append((CGFloat(s) * ptPerPx, CGFloat(i) * ptPerPx)); start = nil
            }
        }
        // Merge anti-aliasing gaps under 2pt so one stroke never splits.
        var merged: [(lo: CGFloat, hi: CGFloat)] = []
        for r in runs {
            if var last = merged.last, r.lo - last.hi < 2.0 { last.hi = r.hi; merged[merged.count - 1] = last }
            else { merged.append(r) }
        }
        return merged
    }

    /// Composite `draw` through the glyph mask: whatever is drawn survives only inside the text.
    private static func throughText(_ size: NSSize, mask: NSImage, _ draw: () -> Void) -> NSImage {
        let i = NSImage(size: size); i.lockFocus()
        draw()
        mask.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .destinationIn, fraction: 1)
        i.unlockFocus(); i.isTemplate = false
        return i
    }

    /// Deterministic per-slot jitter (stable across frames; varies by slot).
    private static func hash01(_ i: Int) -> CGFloat { CGFloat((Double(i) * 12.9898).truncatingRemainder(dividingBy: 1)) }

    // IGNITE - the showpiece. The digits wear the fire: a rust→amber gradient body, flame
    // tongues licking off the top of the glyphs (anchored across the ink, swaying and
    // flickering), sparks popping upward, everything scaling with the live burn rate and
    // raging red at the limit. Gently alive at idle.
    private static func ignite(_ g: GlyphData) -> NSImage {
        let a = attrs(PRIMARY + 1, .bold, .white)
        let ts = (g.pctText as NSString).size(withAttributes: a)
        let wk = g.hasSecondary
        let wkH: CGFloat = 2.5, botPad: CGFloat = wk ? wkH + 2.0 : 0
        let head: CGFloat = 4.5                                     // headroom for tongues + sparks
        let W = ceil(ts.width), H = ceil(ts.height) + botPad + head
        let need = CGFloat(max(0, min(1, g.needle)))
        let rage = CGFloat(max(0, min(1, g.redline)))
        let calm: CGFloat = g.active ? 1 : 0.5
        let ph = g.phase
        let capY = botPad + ceil(ts.height) * 0.80                  // the digits' visual top edge
        let size = NSSize(width: W, height: H)
        let mask = cachedTextMask(g.pctText, a, size: size, at: NSPoint(x: 0, y: botPad),
                                  key: maskKey(g.pctText, g.digitWeight, size, botPad))
        let baseCol = fRust.blended(to: fOrange, 0.35 + 0.3 * rage)
        let topCol = fAmber.blended(to: fCream, 0.25 + 0.45 * need + 0.3 * rage)
        // Gradient-filled glyph body.
        let body = throughText(size, mask: mask) {
            NSGradient(colors: [baseCol, fOrange.blended(to: fAmber, 0.5), topCol])?
                .draw(in: NSRect(x: 0, y: botPad, width: W, height: ceil(ts.height)), angle: 90)
        }
        return img(W, H) {
            body.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
            // Flame tongues grow FROM the glyph tops (drawn over, slightly overlapping the cap
            // line so they read as fire wrapping the digits - never a fence floating above).
            // Few, narrow, organically varied; heights breathe with the burn.
            let anchors: [CGFloat] = [0.14, 0.38, 0.62, 0.86]
            for (i, fx) in anchors.enumerated() {
                let x = fx * W + sin(ph * (1.0 + Double(i) * 0.31)) * 1.3 * calm
                let vary = 0.55 + 0.45 * CGFloat(sin(ph * (4.2 + Double(i) * 1.45) * Double(calm)))
                let hgt = (1.3 + 3.8 * need + 1.5 * rage) * vary * calm + 1.0 + hash01(i * 5) * 0.8
                let wdt = 1.1 + 0.6 * need + hash01(i * 7) * 0.5
                let tip = x + CGFloat(sin(ph * (2.7 + Double(i) * 0.85) * Double(calm))) * 1.5 * calm
                let baseY = capY - 0.8                              // overlap the cap for a rooted look
                let p = NSBezierPath()
                p.move(to: NSPoint(x: x - wdt, y: baseY))
                p.curve(to: NSPoint(x: tip, y: baseY + hgt),
                        controlPoint1: NSPoint(x: x - wdt * 0.5, y: baseY + hgt * 0.5),
                        controlPoint2: NSPoint(x: tip - 0.4, y: baseY + hgt * 0.82))
                p.curve(to: NSPoint(x: x + wdt, y: baseY),
                        controlPoint1: NSPoint(x: tip + 0.4, y: baseY + hgt * 0.82),
                        controlPoint2: NSPoint(x: x + wdt * 0.5, y: baseY + hgt * 0.5))
                p.close()
                fOrange.blended(to: rage > 0.3 ? fRust : fAmber, 0.45).withAlphaComponent(0.9).setFill()
                p.fill()
                // hot core of the tongue
                let p2 = NSBezierPath()
                p2.move(to: NSPoint(x: x - wdt * 0.4, y: baseY))
                p2.curve(to: NSPoint(x: tip, y: baseY + hgt * 0.55),
                         controlPoint1: NSPoint(x: x - wdt * 0.18, y: baseY + hgt * 0.26),
                         controlPoint2: NSPoint(x: tip - 0.25, y: baseY + hgt * 0.45))
                p2.curve(to: NSPoint(x: x + wdt * 0.4, y: baseY),
                         controlPoint1: NSPoint(x: tip + 0.25, y: baseY + hgt * 0.45),
                         controlPoint2: NSPoint(x: x + wdt * 0.18, y: baseY + hgt * 0.26))
                p2.close()
                fSpark.withAlphaComponent(0.85).setFill()
                p2.fill()
            }
            // Sparks rising off the crown (slot pattern; count tracks burn).
            let slots = 1 + Int(need * 3)
            for k in 0..<slots {
                let t = ((ph * (0.5 + Double(need) * 1.6)) + Double(k) * 0.41).truncatingRemainder(dividingBy: 1)
                let sx = (0.15 + hash01(k * 3 + 1) * 0.7) * W + CGFloat(sin(t * 8 + Double(k))) * 1.5
                let sy = capY + 1 + CGFloat(t) * (head + 1)
                fSpark.withAlphaComponent((1 - CGFloat(t)) * (0.45 + 0.55 * need)).setFill()
                let r = 0.8 * (1.15 - CGFloat(t))
                NSBezierPath(ovalIn: NSRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)).fill()
            }
            if wk { weeklyBar(W, g.secFrac, g.secondary, wkH) }
        }
    }

    // MOLTEN - liquid fire flows upward INSIDE the digits (scrolling wrapped gradient),
    // swaying gently, rushing under heavy burn; a thin warm rim keeps the edges crisp.
    private static func molten(_ g: GlyphData) -> NSImage {
        let a = attrs(PRIMARY + 1, .bold, .white)
        let ts = (g.pctText as NSString).size(withAttributes: a)
        let wk = g.hasSecondary
        let wkH: CGFloat = 2.5, botPad: CGFloat = wk ? wkH + 2.0 : 0
        let W = ceil(ts.width), H = ceil(ts.height) + botPad
        let need = CGFloat(max(0, min(1, g.needle)))
        let rage = CGFloat(max(0, min(1, g.redline)))
        let ph = g.phase
        let th = ceil(ts.height)
        let size = NSSize(width: W, height: H)
        let mask = cachedTextMask(g.pctText, a, size: size, at: NSPoint(x: 0, y: botPad),
                                  key: maskKey(g.pctText, g.digitWeight, size, botPad))
        // Scrolling wrapped fire: two stacked gradients slide upward through the glyphs.
        let speed = 3.0 + Double(need) * 26 + Double(rage) * 12
        let yo = CGFloat((ph * speed).truncatingRemainder(dividingBy: Double(th)))
        let sway = CGFloat(sin(ph * 2.0)) * (0.5 + 1.2 * need)
        let hot = fCream.blended(to: .white, rage)
        let grad = NSGradient(colors: [fRust.blended(to: fOrange, rage * 0.7), fOrange, fAmber, hot, fOrange, fRust.blended(to: fOrange, rage * 0.7)])
        let body = throughText(size, mask: mask) {
            grad?.draw(in: NSRect(x: sway, y: botPad + yo - th, width: W, height: th), angle: 90)
            grad?.draw(in: NSRect(x: sway, y: botPad + yo, width: W, height: th), angle: 90)
        }
        return img(W, H) {
            body.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
            // Crisp warm rim so the numerals never smear.
            var rim = a
            rim[.foregroundColor] = fOrange.withAlphaComponent(0.55 + 0.25 * rage)
            rim[.strokeWidth] = 2.2
            rim[.strokeColor] = fOrange.withAlphaComponent(0.55 + 0.25 * rage)
            (g.pctText as NSString).draw(at: NSPoint(x: 0, y: botPad), withAttributes: rim)
            if wk { weeklyBar(W, g.secFrac, g.secondary, wkH) }
        }
    }

    // CHARRED - the number burns left→right and the burn front IS your usage: charred
    // behind, unburned ahead, a live glowing seam chewing across, sparks at the front.
    // You read the meter twice: the position of the front, and the digits themselves.
    private static func charred(_ g: GlyphData) -> NSImage {
        let a = attrs(PRIMARY + 1, .bold, .white)
        let ts = (g.pctText as NSString).size(withAttributes: a)
        let wk = g.hasSecondary
        let wkH: CGFloat = 2.5, botPad: CGFloat = wk ? wkH + 2.0 : 0
        let W = ceil(ts.width), H = ceil(ts.height) + botPad
        let need = CGFloat(max(0, min(1, g.needle)))
        let rage = CGFloat(max(0, min(1, g.redline)))
        let ph = g.phase
        let th = ceil(ts.height)
        let size = NSSize(width: W, height: H)
        let frontX = CGFloat(max(0, min(1, g.pct))) * W + CGFloat(sin(ph * 1.4)) * (0.6 + 1.2 * need)
        let charCol = fRust.blended(to: .black, 0.45)
        return img(W, H) {
            // Unburned (ahead of the front): the adaptive primary color - readable on any bar.
            var ua = a; ua[.foregroundColor] = g.primary
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: frontX, y: 0, width: W - frontX, height: H)).addClip()
            (g.pctText as NSString).draw(at: NSPoint(x: 0, y: botPad), withAttributes: ua)
            NSGraphicsContext.current?.restoreGraphicsState()
            // Charred (behind the front): dark ember body with a low smolder.
            var ca = a; ca[.foregroundColor] = charCol.blended(to: fOrange, 0.12 + 0.15 * CGFloat(sin(ph * 1.1)) * 0.5 + rage * 0.25)
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: frontX, height: H)).addClip()
            (g.pctText as NSString).draw(at: NSPoint(x: 0, y: botPad), withAttributes: ca)
            NSGraphicsContext.current?.restoreGraphicsState()
            // The combustion seam: a glowing vertical zone at the front, trapped inside the glyphs.
            if g.pct > 0.005 {
                let seam = throughText(size, mask: textMask(g.pctText, a, size: size, at: NSPoint(x: 0, y: botPad))) {
                    let zone = 2.5 + 2.5 * need + 2.0 * rage
                    let flick = 0.55 + 0.35 * CGFloat(sin(ph * (4 + Double(need) * 5)))
                    NSGradient(colors: [fCream.withAlphaComponent(0), fSpark.blended(to: .white, rage).withAlphaComponent(flick), fCream.withAlphaComponent(0)])?
                        .draw(in: NSRect(x: frontX - zone, y: 0, width: zone * 2, height: H), angle: 0)
                }
                seam.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
                // Sparks popping off the seam.
                for k in 0..<(1 + Int(need * 3)) {
                    let t = ((ph * (0.8 + Double(need))) + Double(k) * 0.47).truncatingRemainder(dividingBy: 1)
                    let sx = frontX + CGFloat(t) * 3.5 - 1
                    let sy = botPad + th * 0.8 + CGFloat(t) * 4
                    fSpark.withAlphaComponent((1 - CGFloat(t)) * 0.85).setFill()
                    let r = 0.8 * (1.1 - CGFloat(t))
                    NSBezierPath(ovalIn: NSRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)).fill()
                }
            }
            if wk { weeklyBar(W, g.secFrac, g.secondary, wkH) }
        }
    }

    // COALS - charcoal digits alive from within: glowing cracks pulsing at their own
    // rhythms, a warm hotspot wandering through the strokes, a lazy spark now and then.
    // Calm and beautiful at idle; breathing faster as the burn picks up.
    private static func coals(_ g: GlyphData) -> NSImage {
        let a = attrs(PRIMARY + 1, .bold, .white)
        let ts = (g.pctText as NSString).size(withAttributes: a)
        let wk = g.hasSecondary
        let wkH: CGFloat = 2.5, botPad: CGFloat = wk ? wkH + 2.0 : 0
        let W = ceil(ts.width), H = ceil(ts.height) + botPad + 2
        let need = CGFloat(max(0, min(1, g.needle)))
        let rage = CGFloat(max(0, min(1, g.redline)))
        let ph = g.phase
        let th = ceil(ts.height)
        let size = NSSize(width: W, height: H)
        let mask = cachedTextMask(g.pctText, a, size: size, at: NSPoint(x: 0, y: botPad),
                                  key: maskKey(g.pctText, g.digitWeight, size, botPad))
        let bodyCol = fRust.blended(to: .black, 0.35).blended(to: fOrange, rage * 0.3)
        let inner = throughText(size, mask: mask) {
            // char body
            bodyCol.setFill(); NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
            // feet in heat: smolder rising from the baseline
            NSGradient(colors: [fOrange.withAlphaComponent(0.35 + 0.5 * need), fOrange.withAlphaComponent(0)])?
                .draw(in: NSRect(x: 0, y: botPad, width: W, height: th * 0.45), angle: 90)
            // wandering hotspot: a warm glow drifting through the digits
            let hx = W * (0.5 + CGFloat(sin(ph * 0.55)) * 0.34)
            let hy = botPad + th * (0.45 + CGFloat(sin(ph * 0.9)) * 0.18)
            let hr = 5.5 + 2.5 * need + 3.0 * rage
            NSGradient(colors: [fCream.blended(to: .white, rage).withAlphaComponent(0.55 + 0.25 * need),
                                fAmber.withAlphaComponent(0.25), fAmber.withAlphaComponent(0)])?
                .draw(fromCenter: NSPoint(x: hx, y: hy), radius: 0, toCenter: NSPoint(x: hx, y: hy), radius: hr, options: [])
            // glowing cracks: short seeded segments pulsing independently
            for i in 0..<10 {
                let cx = (0.06 + hash01(i * 7 + 2) * 0.88) * W
                let cy = botPad + (0.18 + hash01(i * 5 + 1) * 0.6) * th
                let ang = Double(hash01(i * 3 + 4)) * .pi
                let len = 1.8 + hash01(i * 11 + 3) * 2.6
                let pulse = 0.5 + 0.5 * CGFloat(sin(ph * (1.2 + Double(need) * 4.5) + Double(i) * 2.4))
                let dx = CGFloat(cos(ang)) * len, dy = CGFloat(sin(ang)) * len
                let seg = NSBezierPath()
                seg.move(to: NSPoint(x: cx - dx, y: cy - dy)); seg.line(to: NSPoint(x: cx + dx, y: cy + dy))
                seg.lineWidth = 2.2; fOrange.withAlphaComponent(0.28 * pulse).setStroke(); seg.stroke()
                seg.lineWidth = 1.0 + 0.5 * rage
                fAmber.blended(to: fCream, pulse).withAlphaComponent(0.35 + 0.65 * pulse).setStroke(); seg.stroke()
            }
        }
        return img(W, H) {
            inner.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
            // a lone lazy spark drifting off the top
            let t = (ph * (0.35 + Double(need) * 1.2)).truncatingRemainder(dividingBy: 1)
            if t < 0.8 {
                let sx = W * (0.25 + hash01(Int(ph * 0.35) + 9) * 0.5)
                let sy = botPad + th * 0.85 + CGFloat(t) * 4
                fSpark.withAlphaComponent((0.8 - CGFloat(t)) * (0.5 + 0.5 * need)).setFill()
                NSBezierPath(ovalIn: NSRect(x: sx - 0.8, y: sy - 0.8, width: 1.6, height: 1.6)).fill()
            }
            if wk { weeklyBar(W, g.secFrac, g.secondary, wkH) }
        }
    }

    // A comet beside the %: a bright head with a tail that streaks longer + brighter the
    // faster you burn, fading to a dim coal at rest.
    private static func comet(_ g: GlyphData) -> NSImage {
        let a = attrs(PRIMARY, .semibold, g.digits)
        let ts = (g.pctText as NSString).size(withAttributes: a)
        let tail: CGFloat = 18, gap: CGFloat = 4, headR: CGFloat = 2.3
        let w = tail + gap + ceil(ts.width), h = max(8, ceil(ts.height)), cy = h/2
        let intensity: CGFloat = g.active ? 0.35 + 0.65 * CGFloat(max(0, min(1, g.needle))) : 0.18
        return img(w, h) {
            let n = 6
            for i in 0..<n {                                  // tail dots: faint (left) → bright (head)
                let f = CGFloat(i) / CGFloat(n - 1)
                let r = headR * (0.35 + 0.65 * f)
                g.primary.withAlphaComponent(min(1, (0.10 + 0.9 * f) * intensity)).setFill()
                NSBezierPath(ovalIn: NSRect(x: f * tail - r, y: cy - r, width: 2*r, height: 2*r)).fill()
            }
            (g.active ? g.primary : g.primary.withAlphaComponent(0.6)).setFill()
            NSBezierPath(ovalIn: NSRect(x: tail - headR, y: cy - headR, width: 2*headR, height: 2*headR)).fill()
            (g.pctText as NSString).draw(at: NSPoint(x: tail + gap, y: (h - ts.height)/2), withAttributes: a)
        }
    }

    // A static half-circle gauge filled to the usage %, with the % beside it.
    private static func arc(_ g: GlyphData) -> NSImage {
        let gw: CGFloat = 22, gh: CGFloat = 12, gap: CGFloat = 3, a = attrs(PRIMARY, .semibold, g.digits)
        let ts = (g.pctText as NSString).size(withAttributes: a)
        let w = gw + gap + ceil(ts.width), h = max(gh, ceil(ts.height))
        let frac = max(0, min(1, g.pct))
        return img(w, h) {
            let c = NSPoint(x: gw/2, y: (h - gh)/2 + 1), r = gw/2 - 2
            let t = NSBezierPath(); t.appendArc(withCenter: c, radius: r, startAngle: 180, endAngle: 0, clockwise: true)
            t.lineWidth = 2.6; t.lineCapStyle = .round; track().setStroke(); t.stroke()
            if frac > 0.01 {
                let p = NSBezierPath(); p.appendArc(withCenter: c, radius: r, startAngle: 180, endAngle: 180 - 180 * CGFloat(frac), clockwise: true)
                p.lineWidth = 2.6; p.lineCapStyle = .round; g.primary.setStroke(); p.stroke()
            }
            (g.pctText as NSString).draw(at: NSPoint(x: gw + gap, y: (h - ts.height)/2), withAttributes: a)
        }
    }

    // A filled pie wedge that grows clockwise from 12 o'clock to the usage %. Tiniest,
    // no text - a faint full ring marks the 100% boundary.
    private static func pie(_ g: GlyphData) -> NSImage {
        let s: CGFloat = 16, frac = max(0, min(1, g.pct))
        return img(s, s) {
            let c = NSPoint(x: s/2, y: s/2), r = s/2 - 1.5
            let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2*r, height: 2*r))
            ring.lineWidth = 1; track(0.35).setStroke(); ring.stroke()
            if frac > 0.001 {
                let wedge = NSBezierPath(); wedge.move(to: c)
                wedge.appendArc(withCenter: c, radius: r, startAngle: 90, endAngle: 90 - 360 * CGFloat(frac), clockwise: true)
                wedge.close(); g.primary.setFill(); wedge.fill()
            }
        }
    }

    // Two slim vertical bars side by side - usage (primary) and the secondary metric
    // (time remaining, or weekly). A faint track shows each bar's full height.
    private static func dual(_ g: GlyphData) -> NSImage {
        let bw: CGFloat = 3.4, gap: CGFloat = 2.6, h: CGFloat = 14
        let w = bw * 2 + gap
        func bar(_ x: CGFloat, _ frac: Double, _ col: NSColor) {
            track(0.25).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: bw, height: h), xRadius: bw/2, yRadius: bw/2).fill()
            let bh = max(bw, CGFloat(max(0, min(1, frac))) * h)
            col.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: bw, height: bh), xRadius: bw/2, yRadius: bw/2).fill()
        }
        return img(w, h) {
            bar(0, g.pct, g.primary)
            bar(bw + gap, g.secFrac, g.secondary)
        }
    }

    // A status dot colored by level, beside the %. Clean and quiet.
    private static func dot(_ g: GlyphData) -> NSImage {
        let a = attrs(PRIMARY, .semibold, g.digits)
        let ts = (g.pctText as NSString).size(withAttributes: a)
        let d: CGFloat = 7, gap: CGFloat = 4
        let w = d + gap + ceil(ts.width), h = max(d, ceil(ts.height))
        return img(w, h) {
            g.primary.setFill()
            NSBezierPath(ovalIn: NSRect(x: 0, y: (h - d)/2, width: d, height: d)).fill()
            (g.pctText as NSString).draw(at: NSPoint(x: d + gap, y: (h - ts.height)/2), withAttributes: a)
        }
    }

    // A round dial: a full ring with a needle pointing from 12 o'clock, clockwise, to
    // the usage %. The % sits beside it.
    private static func dial(_ g: GlyphData) -> NSImage {
        let s: CGFloat = 17, gap: CGFloat = 3, a = attrs(11, .semibold, g.digits)
        let ts = (g.pctText as NSString).size(withAttributes: a)
        let w = s + gap + ceil(ts.width), h = max(s, ceil(ts.height))
        let frac = max(0, min(1, g.pct))
        return img(w, h) {
            let c = NSPoint(x: s/2, y: h/2), r = s/2 - 1.5
            let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2*r, height: 2*r))
            ring.lineWidth = 1.4; track(0.4).setStroke(); ring.stroke()
            let ang = (90 - 360 * CGFloat(frac)) * .pi / 180, nl = r - 1.5
            let tip = NSPoint(x: c.x + cos(ang) * nl, y: c.y + sin(ang) * nl)
            let nd = NSBezierPath(); nd.move(to: c); nd.line(to: tip)
            nd.lineWidth = 1.5; nd.lineCapStyle = .round; g.primary.setStroke(); nd.stroke()
            g.primary.setFill(); NSBezierPath(ovalIn: NSRect(x: c.x - 1.4, y: c.y - 1.4, width: 2.8, height: 2.8)).fill()
            (g.pctText as NSString).draw(at: NSPoint(x: s + gap, y: (h - ts.height)/2), withAttributes: a)
        }
    }

    // MARK: Both-only styles (session = pct/primary, weekly = secFrac/secondary)

    // Session % big and leading, weekly % small beneath - aligned, color-coded.
    private static func twins(_ g: GlyphData) -> NSImage {
        let top = attrs(11.5, .semibold, g.digits), bot = attrs(8, .semibold, g.secondary)
        let l1 = g.pctText as NSString, l2 = "wk \(g.secText)" as NSString
        let s1 = l1.size(withAttributes: top), s2 = l2.size(withAttributes: bot)
        let w = max(ceil(s1.width), ceil(s2.width)), h = ceil(s1.height) + ceil(s2.height) - 2
        return img(w, h) {
            l1.draw(at: NSPoint(x: 0, y: ceil(s2.height) - 2), withAttributes: top)
            l2.draw(at: NSPoint(x: 0, y: 0), withAttributes: bot)
        }
    }

    // Two nested 3/4 arc gauges - session outside, weekly inside.
    private static func splitArc(_ g: GlyphData) -> NSImage {
        let s: CGFloat = 20, startA: CGFloat = 235, sweep: CGFloat = 290
        return img(s, s) {
            let c = NSPoint(x: s/2, y: s/2)
            func gauge(_ r: CGFloat, _ lw: CGFloat, _ frac: Double, _ col: NSColor) {
                let t = NSBezierPath()
                t.appendArc(withCenter: c, radius: r, startAngle: startA, endAngle: startA - sweep, clockwise: true)
                t.lineWidth = lw; t.lineCapStyle = .round; track().setStroke(); t.stroke()
                if frac > 0.01 {
                    let p = NSBezierPath()
                    p.appendArc(withCenter: c, radius: r, startAngle: startA, endAngle: startA - sweep * CGFloat(min(1, frac)), clockwise: true)
                    p.lineWidth = lw; p.lineCapStyle = .round; col.setStroke(); p.stroke()
                }
            }
            gauge(s/2 - 2, 2.3, g.pct, g.primary)          // outer = session
            gauge(s/2 - 6.5, 2.0, g.secFrac, g.secondary)  // inner = weekly
        }
    }

    // Horizontal twin gauge - session fills from the left toward center, weekly from the right.
    private static func halfGauge(_ g: GlyphData) -> NSImage {
        let w: CGFloat = 24, h: CGFloat = 8, half = w/2
        return img(w, h) {
            let cap = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: h), xRadius: h/2, yRadius: h/2)
            track(0.25).setFill(); cap.fill()
            NSGraphicsContext.saveGraphicsState(); cap.addClip()
            let sw = CGFloat(min(1, g.pct)) * half
            g.primary.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: sw, height: h)).fill()
            let ww = CGFloat(min(1, g.secFrac)) * half
            g.secondary.setFill(); NSBezierPath(rect: NSRect(x: w - ww, y: 0, width: ww, height: h)).fill()
            NSGraphicsContext.restoreGraphicsState()
            track(0.7).setFill(); NSBezierPath(rect: NSRect(x: half - 0.5, y: 0, width: 1, height: h)).fill()
        }
    }

    // Nested pie - session = outer ring, weekly = inner wedge.
    private static func coPie(_ g: GlyphData) -> NSImage {
        let s: CGFloat = 17
        return img(s, s) {
            drawRing(NSRect(x: 0, y: 0, width: s, height: s), 2.6, min(1, g.pct), g.primary)
            let c = NSPoint(x: s/2, y: s/2), r: CGFloat = 4.4
            if g.secFrac > 0.001 {
                let wdg = NSBezierPath(); wdg.move(to: c)
                wdg.appendArc(withCenter: c, radius: r, startAngle: 90, endAngle: 90 - 360 * CGFloat(min(1, g.secFrac)), clockwise: true)
                wdg.close(); g.secondary.setFill(); wdg.fill()
            }
        }
    }

    // Two side-by-side tanks - session (left) and weekly (right) fill bottom-up.
    private static func vsplit(_ g: GlyphData) -> NSImage {
        let w: CGFloat = 12, h: CGFloat = 15, half = w/2
        return img(w, h) {
            let cap = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: h), xRadius: 2, yRadius: 2)
            track(0.25).setFill(); cap.fill()
            NSGraphicsContext.saveGraphicsState(); cap.addClip()
            g.primary.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: half, height: CGFloat(min(1, g.pct)) * h)).fill()
            g.secondary.setFill(); NSBezierPath(rect: NSRect(x: half, y: 0, width: half, height: CGFloat(min(1, g.secFrac)) * h)).fill()
            NSGraphicsContext.restoreGraphicsState()
            track(0.7).setFill(); NSBezierPath(rect: NSRect(x: half - 0.4, y: 0, width: 0.8, height: h)).fill()
        }
    }

    // Two 8-cell rows that light up with value - session on top, weekly below.
    private static func heatRows(_ g: GlyphData) -> NSImage {
        let cols = 8, cw: CGFloat = 2, gap: CGFloat = 0.9, ch: CGFloat = 3.2, rgap: CGFloat = 1.8
        let w = CGFloat(cols) * cw + CGFloat(cols - 1) * gap, h = ch * 2 + rgap
        func row(_ y: CGFloat, _ frac: Double, _ col: NSColor) {
            let lit = Int((Double(cols) * max(0, min(1, frac))).rounded())
            for i in 0..<cols {
                let x = CGFloat(i) * (cw + gap)
                ((i < lit) ? col : track(0.3)).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: cw, height: ch), xRadius: 0.6, yRadius: 0.6).fill()
            }
        }
        return img(w, h) { row(ch + rgap, g.pct, g.primary); row(0, g.secFrac, g.secondary) }
    }

    // Session % (big, leading) beside the weekly reset countdown ("3d 4h"), small + quiet.
    private static func weeklyClock(_ g: GlyphData) -> NSImage {
        let big = attrs(11.5, .semibold, g.digits), small = attrs(8, .semibold, g.secondary)
        let l1 = g.pctText as NSString
        let wk = g.weekLeftText.isEmpty ? g.secText : g.weekLeftText
        let l2 = wk as NSString   // just the countdown (no "wk" prefix; saves horizontal space)
        let s1 = l1.size(withAttributes: big), s2 = l2.size(withAttributes: small)
        let w = max(ceil(s1.width), ceil(s2.width)), h = ceil(s1.height) + ceil(s2.height) - 2
        return img(w, h) {
            l1.draw(at: NSPoint(x: 0, y: ceil(s2.height) - 2), withAttributes: big)
            l2.draw(at: NSPoint(x: 0, y: 0), withAttributes: small)
        }
    }
}
