import AppKit
import SwiftUI

// QA harness: set CUB_SNAP=/path.png and launch the binary directly to render a
// sheet of every menu-bar style with sample data, then exit. Lets us eyeball the
// glyphs (incl. the animated ones, frozen mid-motion) without the menu bar - the
// status-item image can't be captured by the screenshot tools (accessory app).
enum StyleSheet {
    static func sampleGlyph() -> GlyphData {
        let clay = NSColor(hex: "D97757") ?? .orange
        let slate = NSColor(hex: "7E8EA6") ?? .gray
        var g = GlyphData(pct: 0.46, pctText: "46%", primary: clay,
                          secFrac: 0.9, secText: "4h31m", secondary: slate, pLabel: "S", sLabel: "W")
        g.costText = "$112"; g.tokText = "≈3.0M"; g.needle = 0.62; g.active = true; g.rollPhase = 1
        g.hasSecondary = true   // exercise the "Both" weekly bar (e.g. pulse)
        g.weekLeftText = "3d 4h"
        g.spark = [0.05, 0.12, 0.08, 0.22, 0.18, 0.4, 0.32, 0.55, 0.6, 0.5, 0.78, 0.7, 0.62, 0.84]
        return g
    }

    // One glyph, at its true menu-bar size, on transparency. The hero composite pastes this into
    // a drawn menu bar so the landing page can show WHERE the app lives, not just what it draws.
    static func renderGlyph(_ style: MenuBarStyle, to path: String) {
        let img = MenuBarRenderer.image(style: style, sampleGlyph())
        let s = img.size
        // 2x, matching every other asset in docs/screenshots.
        let out = NSImage(size: NSSize(width: s.width * 2, height: s.height * 2))
        out.lockFocus()
        img.draw(in: NSRect(x: 0, y: 0, width: s.width * 2, height: s.height * 2),
                 from: .zero, operation: .sourceOver, fraction: 1,
                 respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    // QA: render the flame across burn intensities x redline, at two flicker phases each,
    // so we can eyeball the temperature ramp (coal -> white-hot), the rage near the limit,
    // and the sparks. CUB_SNAP_FLAME=/path.png.
    static func renderFlames(to path: String) {
        let clay = NSColor(hex: "D97757") ?? .orange
        let cases: [(String, Bool, Double, Double)] = [
            ("idle coal",      false, 0.0, 0.0),
            ("simmer .2",      true,  0.2, 0.0),
            ("burn .5",        true,  0.5, 0.0),
            ("heavy .8",       true,  0.8, 0.0),
            ("max 1.0",        true,  1.0, 0.0),
            ("redline .5",     true,  0.7, 0.5),
            ("REDLINE 1.0",    true,  0.9, 1.0),
            ("over-limit idle",false, 0.2, 1.0),
        ]
        let phases: [Double] = [0.0, 0.37]
        let scale: CGFloat = 4.0, rowH: CGFloat = 64, labelX: CGFloat = 220, W: CGFloat = 420
        let H = CGFloat(cases.count) * rowH + 24
        let sheet = NSImage(size: NSSize(width: W, height: H)); sheet.lockFocus()
        NSColor(calibratedWhite: 0.10, alpha: 1).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()
        let la: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1)]
        for (i, c) in cases.enumerated() {
            let y = H - CGFloat(i + 1) * rowH + 12
            for (j, ph) in phases.enumerated() {
                var g = GlyphData(pct: 0.46, pctText: "46%", primary: clay, secFrac: 0.9, secText: "", secondary: clay, pLabel: "", sLabel: "")
                g.active = c.1; g.needle = c.2; g.redline = c.3; g.phase = ph
                let glyph = MenuBarRenderer.image(style: .flame, g); let gs = glyph.size
                let gx: CGFloat = 20 + CGFloat(j) * 95, gy = y + (rowH - gs.height * scale) / 2
                glyph.draw(in: NSRect(x: gx, y: gy, width: gs.width * scale, height: gs.height * scale),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            }
            (c.0 as NSString).draw(at: NSPoint(x: labelX, y: y + rowH / 2 - 8), withAttributes: la)
            NSColor(calibratedWhite: 1, alpha: 0.06).setFill(); NSBezierPath(rect: NSRect(x: 0, y: y, width: W, height: 0.5)).fill()
        }
        sheet.unlockFocus()
        if let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    // QA: render every burning-number style across (idle / mid / heavy / redline) x 2 flicker
    // phases, so the whole fire family can be eyeballed frozen mid-motion. CUB_SNAP_BURN=/path.png
    static func renderBurners(to path: String) {
        let clay = NSColor(hex: "D97757") ?? .orange
        let styles: [MenuBarStyle] = [.smolder, .burnfront, .kiln, .flame]
        // (label, tier, pct). The fire's amplitude/frequency comes from the BurnTier tables.
        let states: [(String, BurnTier, Double)] = [
            ("idle", .idle, 0.46), ("mid", .mid, 0.46), ("heavy", .heavy, 0.72), ("REDLINE", .redline, 0.95),
        ]
        // Sample each tier at elapsed 0 and at HALF its tip-sway period, i.e. maximum excursion, so the
        // two columns show the extremes of the motion rather than two near-identical instants.
        func sweep(_ t: BurnTier) -> [Double] { [0.0, 1.0 / (2 * t.flameSway.hz)] }
        let scale: CGFloat = 3.0, rowH: CGFloat = 72, W: CGFloat = 1030
        let H = CGFloat(styles.count) * rowH + 30
        let sheet = NSImage(size: NSSize(width: W, height: H)); sheet.lockFocus()
        NSColor(calibratedWhite: 0.11, alpha: 1).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()
        let la: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: 0.9, alpha: 1)]
        let sa: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1)]
        for (r, style) in styles.enumerated() {
            let y = H - CGFloat(r + 1) * rowH + 10
            (style.label as NSString).draw(at: NSPoint(x: 14, y: y + rowH / 2 - 6), withAttributes: la)
            for (c, st) in states.enumerated() {
                for (j, e) in sweep(st.1).enumerated() {
                    var g = GlyphData(pct: st.2, pctText: "\(Int(st.2 * 100))%", primary: clay,
                                      secFrac: 0.4, secText: "", secondary: NSColor(hex: "7E8EA6") ?? .gray, pLabel: "", sLabel: "")
                    g.tier = st.1; g.heat = st.1.heat; g.phase = e
                    g.active = (st.1 != .idle); g.redline = (st.1 == .redline) ? 1.0 : 0.0
                    let glyph = MenuBarRenderer.image(style: style, g); let gs = glyph.size
                    let gx = 120 + CGFloat(c) * 220 + CGFloat(j) * 105
                    glyph.draw(in: NSRect(x: gx, y: y + (rowH - gs.height * scale) / 2, width: gs.width * scale, height: gs.height * scale),
                               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
                }
                if r == 0 { (states[c].0 as NSString).draw(at: NSPoint(x: 120 + CGFloat(c) * 220, y: H - 16), withAttributes: sa) }
            }
            NSColor(calibratedWhite: 1, alpha: 0.05).setFill(); NSBezierPath(rect: NSRect(x: 0, y: y - 8, width: W, height: 0.5)).fill()
        }
        sheet.unlockFocus()
        if let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    // QA: FLAME ADJUST sweep - the Flame at several sizes x tiers, so the size slider can be judged
    // against a real menu-bar scale rather than guessed. CUB_SNAP_FLAMESIZE=/path.png
    static func renderFlameSizes(to path: String) {
        let clay = NSColor(hex: "D97757") ?? .orange
        let sizes: [Double] = [1.0, 1.45, 1.9, 2.5]
        let tiers: [BurnTier] = [.idle, .mid, .heavy, .redline]
        let scale: CGFloat = 3.0, rowH: CGFloat = 78, W: CGFloat = 1000
        let H = CGFloat(sizes.count) * rowH + 30
        let sheet = NSImage(size: NSSize(width: W, height: H)); sheet.lockFocus()
        NSColor(calibratedWhite: 0.11, alpha: 1).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()
        let la: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: 0.9, alpha: 1)]
        let sa: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1)]
        for (rIdx, size) in sizes.enumerated() {
            let y = H - CGFloat(rIdx + 1) * rowH + 12
            (String(format: "%.2fx", size) as NSString).draw(at: NSPoint(x: 14, y: y + rowH / 2 - 6), withAttributes: la)
            for (c, tier) in tiers.enumerated() {
                var g = GlyphData(pct: 0.46, pctText: "46%", primary: clay, secFrac: 0.4, secText: "",
                                  secondary: NSColor(hex: "7E8EA6") ?? .gray, pLabel: "", sLabel: "")
                g.tier = tier; g.heat = tier.heat; g.phase = 1.7
                g.active = (tier != .idle); g.redline = (tier == .redline) ? 1.0 : 0.0
                g.flameSize = size; g.flameSparks = .always; g.flameSmoke = true
                let glyph = MenuBarRenderer.image(style: .flame, g); let gs = glyph.size
                let gx = 90 + CGFloat(c) * 225
                glyph.draw(in: NSRect(x: gx, y: y + (rowH - gs.height * scale) / 2, width: gs.width * scale, height: gs.height * scale),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
                if rIdx == 0 { (tier.rawValue as NSString).draw(at: NSPoint(x: gx, y: H - 16), withAttributes: sa) }
            }
            NSColor(calibratedWhite: 1, alpha: 0.05).setFill(); NSBezierPath(rect: NSRect(x: 0, y: y - 8, width: W, height: 0.5)).fill()
        }
        sheet.unlockFocus()
        if let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    // QA: BEACON - the wink sampled across its own length, on a dark bar and a light bar, so the
    // resting ink can be checked against a native icon and the flash against the accent.
    // CUB_SNAP_BEACON=/path.png
    static func renderBeacon(to path: String) {
        // CUB_BEACON_ACCENT=00DCC3 for a custom accent, CUB_BEACON_GLOW=0.6 to preview the halo,
        // CUB_BEACON_MARKS=1 to sweep the marks instead of the curves, CUB_BEACON_LIGHT=1 for a light bar.
        let env = ProcessInfo.processInfo.environment
        let accent = NSColor(hex: env["CUB_BEACON_ACCENT"] ?? kAccentHex) ?? .orange
        let glow = Double(env["CUB_BEACON_GLOW"] ?? "") ?? 0
        let dark = env["CUB_BEACON_LIGHT"] == nil
        let marksMode = env["CUB_BEACON_MARKS"] != nil
        let len = 0.42
        // Ten instants across one wink (plus a resting frame), so each row IS the animation.
        let times: [Double] = [-0.2] + (0...9).map { Double($0) / 9 * len * 0.98 }
        // Rows: either every curve at the default mark, or every mark on the default curve.
        // CUB_BEACON_USAGE=1: one row per usage level, each winking the adaptive ramp's colour for it -
        // what "Wink colour: By usage" actually looks like as you climb toward the cap.
        let usageMode = env["CUB_BEACON_USAGE"] != nil
        let levels: [(String, Double, Bool)] = [("18%", 0.18, false), ("46%", 0.46, false),
                                                ("72%", 0.72, false), ("91%", 0.91, false), ("over", 1.0, true)]
        let rows: [(String, BeaconMark, BeaconCurve)] = usageMode
            ? levels.map { ($0.0, .percent, .snap) }
            : (marksMode ? BeaconMark.allCases.map { ($0.label, $0, .snap) }
                         : BeaconCurve.allCases.map { ($0.label, .percent, $0) })
        let scale: CGFloat = 3.0, rowH: CGFloat = 62, colW: CGFloat = 104, lx: CGFloat = 108
        let W = lx + CGFloat(times.count) * colW, H = CGFloat(rows.count) * rowH + 34
        let sheet = NSImage(size: NSSize(width: W, height: H)); sheet.lockFocus()
        NSApplication.shared.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        (dark ? NSColor(calibratedWhite: 0.13, alpha: 1) : NSColor(calibratedWhite: 0.94, alpha: 1)).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()
        let inkW = dark ? 0.92 : 0.18
        let la: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: inkW, alpha: 1)]
        let sa: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor(calibratedWhite: dark ? 0.55 : 0.45, alpha: 1)]
        for (r, rowDef) in rows.enumerated() {
            let y = H - CGFloat(r + 1) * rowH
            (rowDef.0 as NSString).draw(at: NSPoint(x: 14, y: y + rowH / 2 - 7), withAttributes: la)
            for (c, t) in times.enumerated() {
                var g = GlyphData(pct: 0.46, pctText: "46%", primary: accent, secFrac: 0.13, secText: "",
                                  secondary: accent, pLabel: "", sLabel: "")
                g.accent = accent; g.beaconMark = rowDef.1; g.beaconGlow = glow
                if usageMode {
                    let lv = levels[r]
                    g.pct = lv.1; g.pctText = "\(Int((lv.1 * 100).rounded()))%"
                    g.accent = beaconUsageNSColor(pct: lv.1, over: lv.2, accent: accent)
                }
                g.beacon = BeaconClock.level(t, len, rowDef.2)
                let glyph = MenuBarRenderer.image(style: .beacon, g); let gs = glyph.size
                let gx = lx + CGFloat(c) * colW
                glyph.draw(in: NSRect(x: gx, y: y + (rowH - gs.height * scale) / 2, width: gs.width * scale, height: gs.height * scale),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
                if r == 0 {
                    (t < 0 ? "rest" : String(format: "%.0fms", t * 1000) as NSString).draw(at: NSPoint(x: gx, y: H - 16), withAttributes: sa)
                }
            }
            NSColor(calibratedWhite: dark ? 1 : 0, alpha: 0.06).setFill(); NSBezierPath(rect: NSRect(x: 0, y: y, width: W, height: 0.5)).fill()
        }
        sheet.unlockFocus()
        if let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    // QA (CUB_BEACON_DIAG=1): run the REAL wink clock headless for 5 minutes at 30fps and report the
    // cadence - gaps must land in 3-5s and never repeat, each wink must be over inside half a second,
    // and the glyph must be at rest the vast majority of the time.
    static func beaconDiag() {
        var clock = BeaconClock()
        let env = ProcessInfo.processInfo.environment
        let every = Double(env["CUB_BEACON_EVERY"] ?? "") ?? 4.0
        let jitter = Double(env["CUB_BEACON_JITTER"] ?? "") ?? 0.5
        let len = Double(env["CUB_BEACON_LENGTH"] ?? "") ?? 0.42
        let curve = BeaconCurve(rawValue: env["CUB_BEACON_CURVE"] ?? "") ?? .snap
        let fps = 30.0, span = 300.0
        var gaps: [Double] = [], durations: [Double] = []
        var lastFired = -99.0, litFrames = 0, frames = 0, runLit = 0.0
        for k in 1...Int(span * fps) {
            let e = Double(k) / fps
            let lvl = clock.envelope(at: e, every: every, jitter: jitter, length: len, curve: curve)
            frames += 1
            if clock.firedAt != lastFired {
                if lastFired > 0 { gaps.append(clock.firedAt - lastFired) }
                if runLit > 0 { durations.append(runLit) }
                lastFired = clock.firedAt; runLit = 0
            }
            if lvl > 0 { litFrames += 1; runLit += 1 / fps }
        }
        if runLit > 0 { durations.append(runLit) }
        func stats(_ a: [Double]) -> String {
            guard !a.isEmpty else { return "none" }
            return String(format: "n=%d  min %.2fs  max %.2fs  mean %.2fs", a.count, a.min()!, a.max()!, a.reduce(0, +) / Double(a.count))
        }
        print(String(format: "BEACON wink clock - %ds at %dfps  (every %.2fs ±%.0f%%, length %.2fs, %@)",
                     Int(span), Int(fps), every, jitter * 100, len, curve.label))
        print("  gap between winks : \(stats(gaps))")
        print("  wink duration     : \(stats(durations))")
        print(String(format: "  lit frames        : %d / %d  (%.1f%% of the time coloured)", litFrames, frames, Double(litFrames) / Double(frames) * 100))
        let distinct = Set(gaps.map { Int($0 * 100) }).count
        print("  distinct gaps     : \(distinct) of \(gaps.count)  (a fixed interval would collapse to 1)")
        let lo = every * (1 - jitter) - 0.02, hi = every * (1 + jitter) + 0.02
        let bad = gaps.filter { $0 < lo || $0 > hi }.count + durations.filter { $0 > len + 0.05 }.count
        print(bad == 0 ? "  PASS - every sample inside the configured window" : "  FAIL - \(bad) sample(s) outside the window")
    }

    // QA (CUB_BENCH=1): time the REAL per-frame work so frame rates are chosen from data, not fear.
    // Prints microseconds per glyph rebuild for each fire style, and the implied CPU% at 30/15/5 fps.
    static func bench() {
        let clay = NSColor(hex: "D97757") ?? .orange
        let styles: [MenuBarStyle] = [.smolder, .burnfront, .kiln, .flame, .pulse]
        func mk(_ tier: BurnTier, _ e: Double) -> GlyphData {
            var g = GlyphData(pct: 0.46, pctText: "46%", primary: clay, secFrac: 0.4, secText: "",
                              secondary: NSColor(hex: "7E8EA6") ?? .gray, pLabel: "", sLabel: "")
            g.tier = tier; g.heat = tier.heat; g.phase = e; g.active = true
            g.hasSecondary = true; g.flameSize = 1.7; g.flameSparks = .always; g.flameSmoke = true
            return g
        }
        print("style       us/frame   @30fps   @15fps   @5fps")
        for st in styles {
            // warm caches first so we time steady state, not first-touch
            for i in 0..<20 { _ = MenuBarRenderer.image(style: st, mk(.mid, Double(i) / 30)) }
            let n = 200
            let t0 = ProcessInfo.processInfo.systemUptime
            for i in 0..<n { _ = MenuBarRenderer.image(style: st, mk(.mid, 5 + Double(i) / 30)) }
            let dt = ProcessInfo.processInfo.systemUptime - t0
            let us = dt / Double(n) * 1_000_000
            func pct(_ fps: Double) -> String { String(format: "%5.1f%%", us * fps / 10_000) }
            print(String(format: "%-11@ %8.0f  %@  %@  %@", st.rawValue as NSString, us, pct(30), pct(15), pct(5)))
        }
    }

    // QA: PROVE the fire moves. For every fire style x BurnClock tier, render a real time sweep on
    // `elapsed` (30fps for 8s, covering even idle's 8s sway cycle) and report:
    //   excursion% = max bytes differing between frame 0 and any later frame (does it move at all?)
    //   perFrame%  = max bytes differing between consecutive frames (is the motion smooth or steppy?)
    // A frozen glyph reports 0.00% excursion. CUB_MOTION_DIAG=1
    static func motionDiag() {
        let clay = NSColor(hex: "D97757") ?? .orange
        let styles: [MenuBarStyle] = [.smolder, .burnfront, .kiln, .flame]
        let tiers: [BurnTier] = [.idle, .low, .mid, .heavy, .redline, .overLimit]
        func rep(_ style: MenuBarStyle, _ tier: BurnTier, _ e: Double) -> NSBitmapImageRep? {
            var g = GlyphData(pct: 0.46, pctText: "46%", primary: clay, secFrac: 0.4, secText: "",
                              secondary: NSColor(hex: "7E8EA6") ?? .gray, pLabel: "", sLabel: "")
            g.tier = tier; g.heat = tier.heat; g.phase = e
            g.active = (tier != .idle)
            g.redline = (tier == .redline) ? 1.0 : 0.0
            guard let tiff = MenuBarRenderer.image(style: style, g).tiffRepresentation else { return nil }
            return NSBitmapImageRep(data: tiff)
        }
        func delta(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Double {
            guard let pa = a.bitmapData, let pb = b.bitmapData else { return 0 }
            let n = min(a.bytesPerPlane, b.bytesPerPlane)
            guard n > 0 else { return 0 }
            var changed = 0
            for i in 0..<n where abs(Int(pa[i]) - Int(pb[i])) > 3 { changed += 1 }
            return Double(changed) / Double(n)
        }
        func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
        print("style       tier        excursion%   perFrame%   (0.00% excursion = FROZEN)")
        for style in styles {
            for tier in tiers {
                guard let f0 = rep(style, tier, 0) else { continue }
                var exc = 0.0, per = 0.0
                var prev = f0
                for k in 1...240 {                     // 8 seconds at 30fps
                    guard let f = rep(style, tier, Double(k) / 30.0) else { continue }
                    exc = max(exc, delta(f0, f))
                    per = max(per, delta(prev, f))
                    prev = f
                }
                print(pad(style.rawValue, 12) + pad(tier.rawValue, 12)
                      + pad(String(format: "%6.2f%%", exc * 100), 13)
                      + String(format: "%6.2f%%", per * 100))
            }
        }
    }

    // QA: render the tide line at several (remaining, heat, redline) states on a dark strip,
    // so we can eyeball the fill length, warmth ramp, leading-edge bloom, and reddening.
    static func renderTide(to path: String) {
        let styles = EmberLineStyle.allCases   // one row per style, at a simmering state
        let W: CGFloat = 900, rowH: CGFloat = 40, top: CGFloat = 10, labelW: CGFloat = 150
        let H = CGFloat(styles.count) * rowH + top
        let img = NSImage(size: NSSize(width: W, height: H)); img.lockFocus()
        NSColor(calibratedWhite: 0.13, alpha: 1).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()
        let la: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1)]
        for (i, st) in styles.enumerated() {
            let y = H - CGFloat(i + 1) * rowH + 6
            let v = TideLineView(frame: NSRect(x: 0, y: 0, width: W - labelW, height: kTideThick))
            v.remaining = 0.62; v.heat = 0.6; v.redline = 0.0; v.horizontal = true
            v.edge = .bottom; v.style = st; v.flames = 2; v.glowMul = 1.0; v.phase = 0.7
            v.sessionCol = NSColor(hex: "DB7551") ?? .orange; v.overCol = NSColor(hex: "D2553A") ?? .red
            let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
            v.cacheDisplay(in: v.bounds, to: rep)
            NSImage(cgImage: rep.cgImage!, size: v.bounds.size).draw(at: NSPoint(x: labelW, y: y + 8), from: .zero, operation: .sourceOver, fraction: 1)
            (st.label as NSString).draw(at: NSPoint(x: 12, y: y + 12), withAttributes: la)
        }
        img.unlockFocus()
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    // QA: render the About window (brand mark + credits). CUB_SNAP_ABOUT=/path.png [CUB_DARK=1].
    @MainActor static func renderAbout(to path: String, dark: Bool) {
        let view = AboutView().environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    // The menu-bar style contact sheet. Every glyph sits inside a dark chip shaped like the
    // menu bar it will actually live in, at close to true size, grouped by the same families
    // the Settings picker uses. The previous version was a two-column table of very tall rows,
    // which left each small glyph stranded in whitespace and gave no clue these were menu-bar
    // icons at all.
    static func render(to path: String) {
        let g = sampleGlyph()
        // Only styles a user can actually choose. allCases still carries six retired styles
        // (kiln, inferno, ignite, charred, molten, coals) that the picker hides, and publishing
        // them advertises glyphs nobody can select.
        let families: [(MenuBarStyle.Family, [MenuBarStyle])] = MenuBarStyle.Family.allCases.map { fam in
            (fam, MenuBarStyle.allCases.filter { $0.family == fam && !$0.isRetired })
        }.filter { !$0.1.isEmpty }

        // POINTS, not pixels: lockFocus renders on a Retina backing store, so the PNG comes out
        // at 2x these numbers and is published at this width. Getting that wrong is how the old
        // sheet ended up twice the size it meant to be.
        let cols = 4
        let chipW: CGFloat = 186, chipH: CGFloat = 56, chipR: CGFloat = 10
        let gapX: CGFloat = 18, labelH: CGFloat = 22, rowGap: CGFloat = 20
        let padX: CGFloat = 24, padY: CGFloat = 22, headH: CGFloat = 32
        let cellH = chipH + labelH + rowGap
        // The glyphs are already at true menu-bar size; a touch over 1x keeps them honest while
        // staying legible in a contact sheet.
        let glyphScale: CGFloat = 1.25

        let W = padX * 2 + CGFloat(cols) * chipW + CGFloat(cols - 1) * gapX
        var H = padY * 2
        for (_, items) in families {
            H += headH + CGFloat((items.count + cols - 1) / cols) * cellH
        }

        let sheet = NSImage(size: NSSize(width: W, height: H))
        sheet.lockFocus()
        // The app's own paper, so the sheet belongs with every other documentation image.
        (NSColor(hex: "F5F3EE") ?? .white).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()

        let headAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(hex: "8A8378") ?? .gray,
            .kern: 1.2]
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(hex: "3A3733") ?? .black]

        var y = H - padY
        for (fam, items) in families {
            let head = fam.rawValue.uppercased() as NSString
            let hs = head.size(withAttributes: headAttrs)
            head.draw(at: NSPoint(x: padX, y: y - hs.height), withAttributes: headAttrs)
            y -= headH

            for (i, style) in items.enumerated() {
                let col = i % cols, row = i / cols
                let cx = padX + CGFloat(col) * (chipW + gapX)
                let cy = y - CGFloat(row + 1) * cellH + rowGap

                // The chip: a slice of a dark menu bar, which is what makes these read as
                // menu-bar icons rather than loose artwork.
                let chip = NSRect(x: cx, y: cy + labelH, width: chipW, height: chipH)
                NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
                NSBezierPath(roundedRect: chip, xRadius: chipR, yRadius: chipR).fill()
                NSColor(calibratedWhite: 1, alpha: 0.07).setStroke()
                let edge = NSBezierPath(roundedRect: chip.insetBy(dx: 0.5, dy: 0.5), xRadius: chipR, yRadius: chipR)
                edge.lineWidth = 1
                edge.stroke()

                let glyph = MenuBarRenderer.image(style: style, g)
                let dw = glyph.size.width * glyphScale, dh = glyph.size.height * glyphScale
                glyph.draw(in: NSRect(x: chip.midX - dw / 2, y: chip.midY - dh / 2, width: dw, height: dh),
                           from: .zero, operation: .sourceOver, fraction: 1,
                           respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])

                // A live style gets the same small accent dot the Settings picker uses.
                if style.isLive {
                    (NSColor(hex: "D97757") ?? .orange).setFill()
                    let d: CGFloat = 5
                    NSBezierPath(ovalIn: NSRect(x: chip.maxX - d - 7, y: chip.maxY - d - 7,
                                                width: d, height: d)).fill()
                }

                let name = style.label.replacingOccurrences(of: " (live)", with: "") as NSString
                let ns = name.size(withAttributes: nameAttrs)
                name.draw(at: NSPoint(x: chip.midX - ns.width / 2, y: cy + (labelH - ns.height) / 2),
                          withAttributes: nameAttrs)
            }
            y -= CGFloat((items.count + cols - 1) / cols) * cellH
        }

        sheet.unlockFocus()
        guard let tiff = sheet.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    // A throwaway settings store (clean code defaults) so QA renders never touch the
    // user's real UserDefaults domain. CUB_CHARTMODE / CUB_PCT mutate only this suite.
    static func qaSettings() -> AppSettings {
        let suite = "com.maz.burndown.qa"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let s = AppSettings(defaults: UserDefaults(suiteName: suite) ?? .standard)
        let env = ProcessInfo.processInfo.environment
        if env["CUB_ALERTS"] != nil { s.alertsEnabled = true }
        s.modelsExpanded = env["CUB_MODELS"] == "1"   // QA: render the BY MODEL split open/closed
        return s
    }

    // Render the popover (DetailCard) with sample data to a PNG, for QA of the layout.
    @MainActor
    static func renderPopover(to path: String, dark: Bool) {
        let env = ProcessInfo.processInfo.environment
        // QA: CUB_STATE=live|est|stale|offline|rate|reauth|over|signedout|loading exercises every popover state.
        let state = env["CUB_STATE"] ?? "live"
        let pct = env["CUB_PCT"].flatMap { Double($0) } ?? (state == "over" ? 1.0 : 0.46)
        var s = UsageSnapshot()
        s.apiSession = WindowState(pct: pct, resetAt: Date().addingTimeInterval(4 * 3600 + 31 * 60))
        s.apiWeekly = WindowState(pct: 0.13, resetAt: Date().addingTimeInterval(3 * 86400 + 4 * 3600))
        s.apiOpus = WindowState(pct: 0.31, resetAt: nil)
        s.apiSonnet = WindowState(pct: 0.22, resetAt: nil)
        s.modelLimits = [ScopedLimit(label: "Fable", pct: 0.32, resetAt: Date().addingTimeInterval(3 * 86400), active: true, severity: "normal")]
        s.modelUsage = [ModelUse(label: "Fable", cost: 384, share: 0.40),
                        ModelUse(label: "Opus", cost: 288, share: 0.30),
                        ModelUse(label: "Sonnet", cost: 240, share: 0.25),
                        ModelUse(label: "Haiku", cost: 48, share: 0.05)]
        s.sessionFresh = 3_000_000; s.sessionCost = 112
        s.weeklyFresh = 29_000_000; s.weeklyCost = 960
        s.plan = "Max 20×"
        s.liveUpdated = Date()
        switch state {
        case "est":
            s.apiSession = nil; s.apiWeekly = nil; s.apiOpus = nil; s.apiSonnet = nil
            s.sessionCap = 1_000_000; s.sessionFresh = Int(pct * 1_000_000)
            s.weeklyCap = 1_000_000; s.weeklyFresh = 130_000; s.liveUpdated = nil
        case "offline":
            s.apiSession = nil; s.apiWeekly = nil
            s.sessionCap = 1_000_000; s.sessionFresh = Int(pct * 1_000_000)
            s.weeklyCap = 1_000_000; s.weeklyFresh = 130_000
            s.liveError = "http 500"; s.liveUpdated = Date().addingTimeInterval(-320)
        case "rate":
            s.apiSession = nil
            s.sessionCap = 1_000_000; s.sessionFresh = Int(pct * 1_000_000)
            s.liveError = "rate limited"; s.liveUpdated = Date().addingTimeInterval(-180)
        case "stale": s.liveUpdated = Date().addingTimeInterval(-1200)
        case "reauth": s.liveError = "http 401"
        default: break
        }
        let signedIn = state != "signedout"
        let loading = state == "loading"
        let p = Palette.of(dark ? .dark : .light)
        let settings = qaSettings()
        if let m = ProcessInfo.processInfo.environment["CUB_CHARTMODE"] {
            // QA: CUB_CHARTMODE=<ChartKind rawValue>[,<rawValue>...] selects the popover chart(s).
            let kinds = m.split(separator: ",").compactMap { ChartKind(rawValue: String($0)) }
            if !kinds.isEmpty { settings.chartKinds = kinds }
        }
        if let c = ProcessInfo.processInfo.environment["CUB_COLORMODE"], let cm = ColorMode(rawValue: c) {
            settings.colorMode = cm   // QA: CUB_COLORMODE=level|flat|system
        }
        if let pal = ProcessInfo.processInfo.environment["CUB_PALETTE"], let pp = PalettePreset(rawValue: pal) {
            settings.palette = pp     // QA: CUB_PALETTE=claude|graphite|midnight|forest|paper (sets Palette.current via didSet)
        }
        if let secs = ProcessInfo.processInfo.environment["CUB_SECTIONS"] {   // QA: e.g. "chart" or "chart,session,header,week"
            let want = secs.split(separator: ",").map(String.init).filter { CardSection(rawValue: $0) != nil }
            settings.sectionOrder = want + CardSection.allCases.map { $0.rawValue }.filter { !want.contains($0) }
            settings.sectionsHidden = CardSection.allCases.map { $0.rawValue }.filter { !want.contains($0) }
        }
        let live = LiveActivity()
        if ProcessInfo.processInfo.environment["CUB_IDLE"] != nil {
            live.seedForPreview(history: Array(repeating: 0.02, count: 16), rate: 0, active: false)
        } else if ProcessInfo.processInfo.environment["CUB_HOT"] != nil {
            // Heavy/spiky burn (values >1 scale past 60k) - exercises the stepped Y ceiling.
            live.seedForPreview(history: [0.3, 0.5, 0.4, 1.6, 0.6, 3.4, 0.8, 2.2, 0.5, 1.2, 2.8, 0.7, 1.5, 0.9, 3.6, 1.1],
                                rate: 28_000, active: true)
        } else {
            live.seedForPreview(history: [0.05, 0.12, 0.08, 0.22, 0.18, 0.4, 0.32, 0.55, 0.6, 0.5, 0.78, 0.7, 0.62, 0.84, 0.7, 0.9],
                                rate: 14_000, active: true)
        }
        if let tsS = ProcessInfo.processInfo.environment["CUB_TEXTSCALE"], let ts = Double(tsS) { settings.textScale = ts }
        // Reflow QA: card width and per-chart height boost, the two corner-grip axes.
        if let cwS = ProcessInfo.processInfo.environment["CUB_CARDWIDTH"], let cw = Double(cwS) { settings.cardWidth = cw }
        if let cbS = ProcessInfo.processInfo.environment["CUB_CARDBOOST"], let cb = Double(cbS) { settings.cardChartBoost = cb }
        if ProcessInfo.processInfo.environment["CUB_QUIET"] != nil { settings.quietHours = true; settings.quietFrom = 0; settings.quietTo = 23 }
        let scale = max(0.7, min(1.6, settings.textScale))   // the Popover size zoom (slider range)
        // Render DetailCard directly so QA can force any state, over a plain bg (the live app uses glass).
        let heat = s.over ? 1.0 : max(0, (min(1, s.sessionPct) - 0.85) / 0.15)
        // QA: CUB_API_MOCK=connected|error exercises the developer-API popover line.
        var apiMock = APISpend()
        if let m = ProcessInfo.processInfo.environment["CUB_API_MOCK"], m != "off" {
            apiMock = m == "error" ? APISpend(configured: true, error: "unavailable")
                                   : APISpend(configured: true, monthToDate: 128.40, today: 12.10, fetchedAt: Date())
        }
        let qaRecords = qaChartRecords()
        let view = DetailCard(snapshot: s, settings: settings, live: live, refreshAnchor: Date(), period: 30,
                              signedIn: signedIn, loading: loading,
                              dailySpark: [0.25, 0.55, 0.35, 0.8, 1.0, 0.45, 0.6],   // QA: 7-day rhythm bars
                              records: qaRecords,
                              apiSpend: apiMock,
                              onRefresh: {})
            .background(p.bg)   // DetailCard frames its own width from settings.cardWidth
            .overlay(RedlineOverlay(heat: heat, radius: 16, p: p))   // QA: exercise the feature-14 popover glow
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        // textScale is a uniform zoom of the 264pt design, so rendering the same layout at a
        // denser raster IS the scaled card, pixel for pixel. (A scaleEffect inside the fixed
        // canvas, as this did before, clipped >100% and letterboxed <100%.)
        renderer.scale = 2 * scale
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    /// QA record history: 14 days of bursty traffic (idle stretches, heavy afternoons, several models
    /// and projects) so every chart in the catalogue has something real to draw instead of its empty
    /// state. Deterministic - no randomness - so renders are comparable between runs.
    static func qaChartRecords() -> [UsageRecord] {
        let now = Date()
        let cal = Calendar.current
        // Neutral sample names: these render inside the app (Settings gallery previews), not just QA.
        let models = ["claude-fable-5", "claude-opus-4-8", "claude-sonnet-4-5", "claude-haiku-4-5"]
        let projects = ["website", "research", "api-server", "writing"]
        // Weight per hour of day: quiet nights, a morning ramp, an afternoon peak.
        let byHour: [Double] = [0, 0, 0, 0, 0, 0, 0.05, 0.2, 0.5, 0.8, 0.7, 0.6,
                                0.4, 0.9, 1.0, 0.85, 0.6, 0.45, 0.3, 0.5, 0.35, 0.2, 0.08, 0]
        var out: [UsageRecord] = []
        for back in 0..<14 {
            guard let day = cal.date(byAdding: .day, value: -back, to: now) else { continue }
            let weekday = cal.component(.weekday, from: day)
            let dayScale = (weekday == 1 || weekday == 7) ? 0.25 : 1.0   // quieter weekends
            for h in 0..<24 {
                let w = byHour[h] * dayScale * (back % 3 == 0 ? 0.6 : 1.0)
                guard w > 0.02 else { continue }
                guard let slot = cal.date(bySettingHour: h, minute: 10, second: 0, of: day), slot <= now else { continue }
                let m = models[(back + h) % models.count]
                let pr = projects[(h / 3 + back) % projects.count]
                // Ordered to line up with `projects` above, which is indexed identically: a sample
                // chat should sit in a project its title would plausibly belong to.
                let chats = ["Draft the launch plan", "Plan the research trip",
                             "Debug the importer", "Rewrite the onboarding copy"]
                out.append(UsageRecord(date: slot, model: m, project: pr, session: chats[(h / 3 + back) % chats.count],
                                       input: Int(w * 38_000), output: Int(w * 8_000),
                                       cache5m: Int(w * 11_000), cache1h: 0, cacheRead: Int(w * 90_000)))
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// Sample burn/usage/weekly series matching seedForPreview's shape, without spinning up a
    /// LiveActivity (whose init touches disk). Used by the Settings chart gallery previews.
    static func qaSampleSeries(now: Date = Date()) -> (burn: [TimedSample], usage: [TimedSample], weekly: [TimedSample]) {
        let hist: [Double] = [0.05, 0.12, 0.08, 0.22, 0.18, 0.4, 0.32, 0.55, 0.6, 0.5, 0.78, 0.7, 0.62, 0.84, 0.7, 0.9]
        func lerp(_ f: Double) -> Double {
            let idx = f * Double(hist.count - 1)
            let lo = Int(idx), hi = min(hist.count - 1, lo + 1)
            return hist[lo] + (hist[hi] - hist[lo]) * (idx - Double(lo))
        }
        let bn = 50
        let burn = (0..<bn).map { i in
            TimedSample(t: now.addingTimeInterval(-Double(bn - 1 - i) * 60), v: lerp(Double(i) / Double(bn - 1)) * LiveActivity.RATE_FULL) }
        let un = 180
        let usage = (0..<un).map { i in
            TimedSample(t: now.addingTimeInterval(-Double(un - 1 - i) * 100), v: 0.18 + Double(i) / Double(un - 1) * 0.28) }
        let weekly = (0..<un).map { i in
            TimedSample(t: now.addingTimeInterval(-Double(un - 1 - i) * 100), v: 0.06 + Double(i) / Double(un - 1) * 0.07) }
        return (burn, usage, weekly)
    }

    // Render a contact sheet of the chart catalogue, for QA.
    @MainActor
    static func renderChartSheet(to path: String, dark: Bool, usage: Bool) {
        let live = LiveActivity()
        live.seedForPreview(history: [0.05, 0.12, 0.08, 0.22, 0.18, 0.4, 0.32, 0.55, 0.6, 0.5, 0.78, 0.7, 0.62, 0.84, 0.7, 0.9],
                            rate: 14_000, active: true)
        let p = Palette.of(dark ? .dark : .light)
        let accent = Color(nsColor: NSColor(hex: "D97757") ?? .orange)
        // A contact sheet of every ChartKind, so all twelve can be eyeballed side by side. `usage`
        // selects the half of the catalogue to render (they do not all fit one readable image).
        // CUB_PART=0..3 selects a quarter of the catalogue (24 charts will not fit one readable image).
        // CUB_GROUP=Burn|Limits|Breakdown|Rhythm|Detail renders exactly that group (marketing
        // sheets read better when they match the catalogue's own grouping); otherwise CUB_PART
        // slices the catalogue six at a time.
        let all = ChartKind.allCases
        let per = 6
        var title: String
        var kinds: [ChartKind]
        if let g = ProcessInfo.processInfo.environment["CUB_GROUP"], ChartKind.groupOrder.contains(g) {
            kinds = all.filter { $0.group == g }
            title = g.uppercased()
        } else {
            let part = Int(ProcessInfo.processInfo.environment["CUB_PART"] ?? "") ?? (usage ? 1 : 0)
            kinds = Array(all.dropFirst(part * per).prefix(per))
            title = "CHARTS \(part * per + 1)-\(min(all.count, part * per + per))"
        }
        let qaRecords = qaChartRecords()
        // Two columns so the sheet is wide and short instead of a tall ribbon.
        let rows = stride(from: 0, to: kinds.count, by: 2).map { i in
            Array(kinds[i..<min(i + 2, kinds.count)])
        }
        let view = VStack(alignment: .leading, spacing: 30) {
            Text(title).font(.system(size: 13, weight: .bold)).tracking(1.4).foregroundStyle(p.ink)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
              HStack(alignment: .top, spacing: 40) {
                ForEach(row) { k in
                VStack(alignment: .leading, spacing: 7) {
                    Text(k.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                    MonitorChart(live: live, kinds: [k],
                                 sessionPct: 0.46, weeklyPct: 0.13, accent: accent, secondary: kSlate, p: p,
                                 anchor: Date().addingTimeInterval(-12), period: 30,
                                 burnSpan: .h6, chartStyle: .area,
                                 sessionResetAt: Date().addingTimeInterval(2.5 * 3600),
                                 weeklyResetAt: Date().addingTimeInterval(3 * 86400),
                                 chartDays: 14,
                                 modelLimits: [ScopedLimit(label: "Fable", pct: 0.74, resetAt: nil, active: true, severity: "warning"),
                                               ScopedLimit(label: "Opus", pct: 0.18, resetAt: nil, active: false, severity: "normal")],
                                 showChats: false,
                                 chatsOpen: .constant(false),
                                 records: qaRecords, chrome: false)
                        .frame(width: 244)
                }
                }
                if row.count == 1 { Spacer().frame(width: 244) }
              }
            }
        }
        .padding(30).frame(width: 610).background(p.bg).environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    // Render a contact sheet of every WidgetStyle, for QA / picking.
    @MainActor
    static func renderWidgetSheet(to path: String, dark: Bool, horizontal: Bool) {
        let p = Palette.of(dark ? .dark : .light)
        let accent = NSColor(hex: "D97757") ?? .orange
        let sc = Color(nsColor: usageNSColor(pct: 0.61, over: false, accent: accent, mode: .level))
        let wc = Color(nsColor: secondaryNSColor(accent: accent, mode: .level))
        let d = WData(s: 0.61, w: 0.38, sc: sc, wc: wc, p: p)
        let r: CGFloat = horizontal ? 11 : 12
        func card(_ st: WidgetStyle) -> some View {
            VStack(spacing: 6) {
                widgetContent(st, d, horizontal: horizontal)
                    .padding(.vertical, horizontal ? 3 : 9).padding(.horizontal, horizontal ? 11 : 6)
                    .background(RoundedRectangle(cornerRadius: r).fill(p.bg))
                    .overlay(RoundedRectangle(cornerRadius: r).stroke(p.divider, lineWidth: 0.6))
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                Text(st.label).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.white)
            }
            .frame(width: horizontal ? 210 : 84, height: horizontal ? 58 : 122)
        }
        let cols = horizontal ? [GridItem(.flexible())] : [GridItem(.fixed(96)), GridItem(.fixed(96)), GridItem(.fixed(96))]
        let view = LazyVGrid(columns: cols, spacing: 16) { ForEach(WidgetStyle.allCases) { card($0) } }
            .padding(20).frame(width: horizontal ? 250 : 330)
            .background(Color(white: dark ? 0.18 : 0.45))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    /// One companion, alone, on a TRANSPARENT background. The landing page composites these
    /// into little scenes (widget docked to a window, ember line along a screen edge), and the
    /// rule for marketing art is that it is assembled from real renders and never redrawn by
    /// hand, so an illustration can never drift from what the app actually draws.
    /// CUB_SNAP_SOLO=widget|tide  CUB_SOLO_OUT=/path.png
    @MainActor static func renderSolo(_ which: String, to path: String) {
        var data: Data?
        switch which {
        case "widget":
            let p = Palette.of(.light)
            let accent = NSColor(hex: "D97757") ?? .orange
            let sc = Color(nsColor: usageNSColor(pct: 0.61, over: false, accent: accent, mode: .level))
            let wc = Color(nsColor: secondaryNSColor(accent: accent, mode: .level))
            let d = WData(s: 0.61, w: 0.38, sc: sc, wc: wc, p: p)
            let view = widgetContent(.bigTile, d, horizontal: false)
                .padding(.vertical, 9).padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 12).fill(p.bg))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.divider, lineWidth: 0.6))
                .frame(width: 84)
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            renderer.isOpaque = false
            if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff) {
                data = rep.representation(using: .png, properties: [:])
            }
        case "tide":
            // The real Ember Line view, full span, at a mid-session simmer.
            let W: CGFloat = 900
            let v = TideLineView(frame: NSRect(x: 0, y: 0, width: W, height: kTideThick))
            v.remaining = 0.62; v.heat = 0.6; v.redline = 0.0; v.horizontal = true
            v.edge = .bottom; v.style = .emberLine; v.flames = 2; v.glowMul = 1.0; v.phase = 0.7
            v.sessionCol = NSColor(hex: "DB7551") ?? .orange
            v.overCol = NSColor(hex: "D2553A") ?? .red
            if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                data = rep.representation(using: .png, properties: [:])
            }
        default: break
        }
        if let data { try? data.write(to: URL(fileURLWithPath: path)) }
    }

    // Render the Settings window content for QA (verifies the info-dot cleanup).
    @MainActor
    static func renderSettings(to path: String, dark: Bool) {
        let settings = qaSettings()
        // The Charts gallery pane is far taller than the rest; give its QA render the full height.
        let noScroll = ProcessInfo.processInfo.environment["CUB_NOSCROLL"] != nil
        let isCharts = ProcessInfo.processInfo.environment["CUB_TAB"] == "data"
        let h: CGFloat = noScroll ? (isCharts ? 3450 : 1180) : 580
        let view = SettingsView(settings: settings, engine: UsageEngine(), live: LiveActivity(),
                                loginInitially: false, onLogin: { _ in })
            .frame(width: 660, height: h)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 660, height: h)
        renderer.scale = 2
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    /// Render the Insights window with the deterministic sample history, for QA and marketing shots.
    @MainActor
    static func renderInsights(to path: String, dark: Bool) {
        let settings = qaSettings()
        let engine = UsageEngine()
        // Seed the engine's published state so the window has something real to draw.
        engine.records = qaChartRecords()
        engine.activeBlockStart = Date().addingTimeInterval(-2.5 * 3600)
        var snap = UsageSnapshot()
        snap.apiSession = WindowState(pct: 0.46, resetAt: Date().addingTimeInterval(2.5 * 3600))
        snap.apiWeekly = WindowState(pct: 0.38, resetAt: Date().addingTimeInterval(3 * 86400))
        snap.plan = "Max 20×"
        snap.sessionCost = 112; snap.weeklyCost = 960
        snap.sessionFresh = 3_000_000; snap.weeklyFresh = 29_000_000
        engine.snapshot = snap
        let p = Palette.of(dark ? .dark : .light)
        // The attribution rows are DERIVED from the same sample records that drive the recap and
        // the 14-day bars, never hand-written alongside them. A separate hand-written list drifted
        // out of step and published a screenshot where "this week" was larger than "all time" and
        // the recap named a different top project than the chart under it.
        let recs = qaChartRecords()
        var perChat: [String: (project: String, tokens: Int, date: Date)] = [:]
        for r in recs {
            let tokens = r.input + r.output + r.cache5m + r.cache1h + r.cacheRead
            if var e = perChat[r.session] {
                e.tokens += tokens; e.date = max(e.date, r.date); perChat[r.session] = e
            } else {
                perChat[r.session] = (r.project, tokens, r.date)
            }
        }
        let sessions = perChat.sorted { $0.value.tokens > $1.value.tokens }.enumerated().map { i, kv in
            SessionUsage(id: "sample-\(i)", title: kv.key, project: kv.value.project,
                         date: kv.value.date, tokens: kv.value.tokens,
                         cost: Double(kv.value.tokens) / 1_000_000 * 12.5)
        }
        let view = InsightsView(engine: engine, settings: settings, preview: (recs, sessions))
            .frame(width: 640, height: 1500, alignment: .topLeading)
            .background(p.bg)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 640, height: 1500)
        renderer.scale = 2
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    // Render the Account window content for QA.
    @MainActor
    static func renderAccount(to path: String, dark: Bool) {
        var s = UsageSnapshot()
        s.apiSession = WindowState(pct: 0.05, resetAt: Date().addingTimeInterval(4 * 3600 + 36 * 60))
        s.apiWeekly = WindowState(pct: 0.40, resetAt: Date().addingTimeInterval(86400 + 19 * 3600))
        s.apiSonnet = WindowState(pct: 0.22, resetAt: nil)
        s.apiOpus = WindowState(pct: 0.31, resetAt: nil)
        s.modelLimits = [ScopedLimit(label: "Fable", pct: 0.32, resetAt: Date().addingTimeInterval(3*86400), active: true, severity: "normal"),
                         ScopedLimit(label: "Opus", pct: 0.18, resetAt: Date().addingTimeInterval(3*86400), active: false, severity: "normal")]
        s.modelUsage = [ModelUse(label: "Opus", cost: 420, share: 0.42),
                        ModelUse(label: "Fable", cost: 300, share: 0.30),
                        ModelUse(label: "Sonnet", cost: 230, share: 0.23),
                        ModelUse(label: "Haiku", cost: 50, share: 0.05)]
        s.plan = "Max 20×"; s.accountEmail = "sam@example.com"; s.accountOrg = "Example Studio"
        s.resetAt = s.apiSession?.resetAt
        let engine = UsageEngine(); engine.snapshot = s
        // QA: CUB_API_MOCK=error shows the developer-API failure state; default is connected.
        if ProcessInfo.processInfo.environment["CUB_API_MOCK"] == "error" {
            engine.apiSpend = APISpend(configured: true, error: "This account cannot use the usage API. It needs a Console organization, which individual accounts do not have.")
        } else {
            engine.apiSpend = APISpend(configured: true, monthToDate: 128.40, today: 12.10,
                                       fetchedAt: Date().addingTimeInterval(-120), error: nil,
                                       daily: [3.2, 5.1, 4.0, 7.8, 6.2, 9.1, 4.5, 8.0, 5.5, 11.2, 7.0, 6.1, 9.4, 12.1])
        }
        let view = AccountView(engine: engine, settings: qaSettings(),
                               onStartSignIn: {}, onFinishSignIn: { _, d in d(true) }, onOpenLogs: {},
                               previewSignedIn: ProcessInfo.processInfo.environment["CUB_SIGNEDOUT"] == nil)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    // Render the edge-dock widget on a neutral backdrop, for QA of how it looks docked.
    @MainActor
    static func renderWidget(to path: String, dark: Bool) {
        var s = UsageSnapshot()
        s.apiSession = WindowState(pct: 0.46, resetAt: Date().addingTimeInterval(4 * 3600))
        s.apiWeekly = WindowState(pct: 0.13, resetAt: Date().addingTimeInterval(3 * 86400))
        s.plan = "Max 20×"
        let engine = UsageEngine(); engine.snapshot = s
        let settings = qaSettings()
        // QA: CUB_DOCK=top|bottom|left|right selects the dock orientation (default bottom = the bar).
        settings.dockEdge = DockEdge(rawValue: ProcessInfo.processInfo.environment["CUB_DOCK"] ?? "bottom") ?? .bottom
        let view = EdgeDockView(engine: engine, settings: settings, edgeState: EdgeState())
            .environment(\.colorScheme, dark ? .dark : .light)
            .padding(24)
            .background(Color(white: dark ? 0.16 : 0.55))   // mid-gray so the card + shadow read
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
