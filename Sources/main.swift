import AppKit
import SwiftUI
import Combine
import ApplicationServices
import UserNotifications
import ServiceManagement

// MARK: - Tide line (the Ember Line)

let kTideThick: CGFloat = 12   // Ember Line canvas: a ~2.5pt meter line at the edge + room for the burn-front cluster

/// A luminous filament hugging a chosen screen edge, spanning the FULL edge. The whole line is
/// always drawn (a dim warm track) so it reads edge-to-edge; the BRIGHT segment = remaining session
/// budget and recedes as you drain. Hue warms with burn rate and reddens near the cap. Click-through.
/// `horizontal` = top/bottom edges (fills along X); otherwise left/right (fills along Y).
// The Ember Line: the fuse of the burning-number identity along the screen edge. The line
// nearly disappears (ash track); the burn front is the jewel. Overlays use the DARK-scheme role values
// (emissive-token rule) blended with the theme-independent fire palette.
// The Ember Line: eight edge-meter styles with a breathing burn-front cluster.
// Drawing is done in a normalized space (the line runs left->right along the bottom, interior upward);
// a per-edge context transform maps it to whichever screen edge the panel hugs.
final class TideLineView: NSView {
    var remaining: CGFloat = 1
    var heat: CGFloat = 0
    var redline: CGFloat = 0
    var horizontal = true
    var edge: DockEdge = .top
    var phase: Double = 0
    var clockPeriod: TimeInterval = 8
    var style: EmberLineStyle = .emberLine
    var flames = 2
    var glowMul: CGFloat = 1.0
    var thickness: CGFloat = 2.5     // Hairline / Standard / Bold
    var sparkRate: Double = 1.0      // Off(0) / Calm(1) / Lively(2.2)
    var smoke = true                 // smoke wisps off the burn front
    var sessionCol: NSColor = NSColor(hex: "DB7551") ?? .orange   // session (dark value)
    var overCol: NSColor = NSColor(hex: "D2553A") ?? .red         // overLimit (dark value)
    override var isOpaque: Bool { false }

    // Only the burn front breathes; the rest of the line is a static fill. Advancing the breath
    // therefore invalidates ONLY a small strip around the front (plus over-limit's leading ember),
    // not the whole full-screen-width panel - that difference is the app's active CPU.
    func advanceBreath(phase newPhase: Double, period: TimeInterval) {
        phase = newPhase; clockPeriod = period
        let m: CGFloat = 40                              // covers drift + cluster + spark/smoke spread
        let over = redline >= 1 || remaining <= 0.0001
        if horizontal {
            let fx = over ? 24 : bounds.width * max(0, min(1, remaining))
            setNeedsDisplay(NSRect(x: max(0, fx - m), y: 0, width: over ? 40 : m * 2, height: bounds.height))
        } else {
            let fy = over ? 24 : bounds.height * max(0, min(1, remaining))
            setNeedsDisplay(NSRect(x: 0, y: max(0, fy - m), width: bounds.width, height: over ? 40 : m * 2))
        }
    }

    private let fGlow = NSColor(hex: "F0A05A") ?? .orange
    private let fCore = NSColor(hex: "FFE2C2") ?? .white
    private let fWhite = NSColor(hex: "FFF4E4") ?? .white
    private let inkDark = NSColor(hex: "F2EFE8") ?? .white   // ash track
    private let bgDark = NSColor(hex: "1A1917") ?? .black    // core keyline

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds
        ctx.saveGState()
        var L = b.width, T = b.height
        switch edge {
        case .top:
            ctx.translateBy(x: 0, y: b.height); ctx.scaleBy(x: 1, y: -1); L = b.width; T = b.height
        case .bottom, .off:
            L = b.width; T = b.height
        case .left:
            ctx.concatenate(CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)); L = b.height; T = b.width
        case .right:
            ctx.translateBy(x: b.width, y: 0); ctx.scaleBy(x: -1, y: 1)
            ctx.concatenate(CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)); L = b.height; T = b.width
        }
        drawEmber(L, T)
        ctx.restoreGState()
    }

    private func fill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor) {
        c.setFill(); NSBezierPath(rect: NSRect(x: x, y: y, width: max(0, w), height: max(0, h))).fill()
    }
    private func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: NSColor) {
        c.setFill(); NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
    }

    private func drawEmber(_ L: CGFloat, _ T: CGFloat) {
        let r = min(1, max(0, redline)), h = min(1, max(0, heat)), g = glowMul
        let base = sessionCol.blended(to: fGlow, 0.6 * h).blended(to: overCol, r)
        let breath = 0.75 + 0.25 * CGFloat((sin(phase * 2 * .pi / max(1, clockPeriod)) + 1) / 2)
        let frac = max(0, min(1, remaining))
        let mt = min(T, thickness)   // configured line thickness
        let fx = max(0.5, min(L - 0.5, L * frac))
        let coreCol = base.blended(to: .white, 0.4 + 0.3 * h).withAlphaComponent(0.95)

        if r >= 1 || frac <= 0.0001 {   // over limit: ember-red band + dying ember (all styles)
            fill(0, 0, L, mt, overCol.withAlphaComponent(0.18))
            fill(0, 0, 24, mt, overCol.blended(to: fCore, 0.3).withAlphaComponent(0.30 * breath))
            return
        }

        switch style {
        case .emberLine:
            fill(0, 0, L, mt, inkDark.withAlphaComponent(0.07))
            fill(0, 0, fx, mt, base.withAlphaComponent(0.62))
            fill(0, mt / 2 - 0.5, fx, 1, base.blended(to: .white, 0.25).withAlphaComponent(0.20))
            NSGradient(colors: [base.withAlphaComponent(0), base.withAlphaComponent((0.45 + 0.35 * h) * breath * g)], atLocations: [0, 1], colorSpace: .sRGB)?
                .draw(in: NSRect(x: max(0, fx - 16), y: 0, width: min(16, fx), height: mt), angle: 0)
            emberCap(fx, mt, coreCol, breath)
            cluster(fx, mt, base, h, breath, g)
        case .filament:
            fill(0, mt / 2 - 0.75, fx, 1.5, base.blended(to: .white, 0.3).withAlphaComponent(0.9))
            emberCap(fx, mt, coreCol, breath)
        case .segmented:
            var x: CGFloat = 0; let seg: CGFloat = 7, gap: CGFloat = 3
            while x < fx { fill(x, 0, min(seg, fx - x), mt, base.withAlphaComponent(0.7)); x += seg + gap }
            emberCap(fx, mt, coreCol, breath)
        case .comet:
            NSGradient(colors: [base.withAlphaComponent(0), base.withAlphaComponent(0.7 * g)], atLocations: [0, 1], colorSpace: .sRGB)?
                .draw(in: NSRect(x: 0, y: 0, width: fx, height: mt), angle: 0)
            emberCap(fx, mt, coreCol.blended(to: fWhite, r), breath)
        case .taper:
            NSGradient(colors: [base.withAlphaComponent(0.25), base.withAlphaComponent(0.85 * g)], atLocations: [0, 1], colorSpace: .sRGB)?
                .draw(in: NSRect(x: 0, y: 0, width: fx, height: mt), angle: 0)
            emberCap(fx, mt, coreCol, breath)
        case .pulseBeads:
            var x: CGFloat = 2; var i = 0; let step: CGFloat = 6
            while x < fx {
                dot(x, mt / 2, mt * 0.5, base.withAlphaComponent((0.4 + 0.5 * CGFloat((sin(phase * 2 + Double(i) * 0.6) + 1) / 2)) * g))
                x += step; i += 1
            }
            emberCap(fx, mt, coreCol, breath)
        case .sparkFront:
            fill(0, mt / 2 - 0.5, fx, 1, base.withAlphaComponent(0.5))
            emberCap(fx, mt, coreCol, breath)
            for i in 0..<3 {
                let t = ((phase * 1.1) + Double(i) * 0.7).truncatingRemainder(dividingBy: 2.1) / 2.1
                let sy = mt + CGFloat(t) * (T - mt) * 0.7
                let sx = fx + CGFloat(sin(phase * 3 + Double(i))) * 1.5
                dot(sx, sy, 0.8 - 0.3 * CGFloat(t), fCore.withAlphaComponent(max(0, (1 - CGFloat(t)) * 0.7 * g)))
            }
        case .minimalNode:
            let rr = (2.0 + 1.0 * h) * breath
            dot(fx, mt / 2, rr * 2, base.withAlphaComponent(0.25 * g))
            dot(fx, mt / 2, rr, coreCol)
        }
    }

    private func emberCap(_ fx: CGFloat, _ mt: CGFloat, _ core: NSColor, _ breath: CGFloat) {
        let cl = 3 + 1.5 * breath
        fill(fx - cl, 0, cl, 0.5, bgDark.withAlphaComponent(0.6))
        fill(fx - cl, mt - 0.5, cl, 0.5, bgDark.withAlphaComponent(0.6))
        fill(fx - cl, 0.5, cl, mt - 1, core)
    }

    private func cluster(_ fx: CGFloat, _ mt: CGFloat, _ base: NSColor, _ h: CGFloat, _ breath: CGFloat, _ g: CGFloat) {
        guard flames > 0 else { return }
        base.blended(to: fGlow, 0.5).withAlphaComponent(0.18 * g * breath).setFill()   // ground glow
        NSBezierPath(ovalIn: NSRect(x: fx - 4, y: mt - 2, width: 8, height: 4)).fill()
        for i in 0..<min(3, flames) {
            let fxo = fx + CGFloat(i - 1) * 2.2
            let sway = CGFloat(sin(phase * 2.0 + Double(i) * 1.3)) * 1.2 * breath
            let fh = (3.5 + 3.0 * h) * breath + CGFloat(i % 2) * 1.2
            let p = NSBezierPath()
            p.move(to: NSPoint(x: fxo - 1.5, y: mt))
            p.curve(to: NSPoint(x: fxo + sway, y: mt + fh), controlPoint1: NSPoint(x: fxo - 1.5, y: mt + fh * 0.5), controlPoint2: NSPoint(x: fxo - 0.5 + sway, y: mt + fh * 0.85))
            p.curve(to: NSPoint(x: fxo + 1.5, y: mt), controlPoint1: NSPoint(x: fxo + 0.5 + sway, y: mt + fh * 0.85), controlPoint2: NSPoint(x: fxo + 1.5, y: mt + fh * 0.5))
            p.close()
            base.blended(to: fGlow, 0.45).withAlphaComponent(0.6 * breath).setFill(); p.fill()
            let p2 = NSBezierPath()
            p2.move(to: NSPoint(x: fxo - 0.6, y: mt))
            p2.curve(to: NSPoint(x: fxo + sway * 0.6, y: mt + fh * 0.6), controlPoint1: NSPoint(x: fxo - 0.6, y: mt + fh * 0.3), controlPoint2: NSPoint(x: fxo - 0.2 + sway * 0.6, y: mt + fh * 0.5))
            p2.curve(to: NSPoint(x: fxo + 0.6, y: mt), controlPoint1: NSPoint(x: fxo + 0.2 + sway * 0.6, y: mt + fh * 0.5), controlPoint2: NSPoint(x: fxo + 0.6, y: mt + fh * 0.3))
            p2.close()
            fCore.withAlphaComponent(0.7 * breath).setFill(); p2.fill()
        }
        // Lifting sparks off the burn front, count/liveliness from the Sparks control.
        if sparkRate > 0 {
            let n = sparkRate >= 2 ? 3 : 2
            for i in 0..<n {
                let t = ((phase * (0.7 + 0.5 * sparkRate)) + Double(i) * 0.6).truncatingRemainder(dividingBy: 1)
                let sy = mt + CGFloat(t) * (3.5 + 4.0 * h)
                let sx = fx + CGFloat(sin(phase * 3 + Double(i))) * 1.4
                dot(sx, sy, 0.7 - 0.3 * CGFloat(t), fCore.withAlphaComponent(max(0, (1 - CGFloat(t)) * 0.7 * breath)))
            }
        }
        if smoke, h > 0.3 {   // thin rising smoke (Smoke toggle)
            dot(fx + CGFloat(sin(phase)) * 1.5, mt + (4 + 4 * h) * breath, 1.0, inkDark.withAlphaComponent(0.10 * breath))
        }
    }
}

// Peek readout capsule: "46% left · 4h 30m" over the Ember Line.
struct TidePeekView: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
            .foregroundStyle(Color(hex: "F2EFE8"))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color(hex: "1A1917").opacity(0.92)))
            .overlay(Capsule().strokeBorder(Color(hex: "F0A05A").opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Edge-dock window helpers (file scope so the CUB_EDGE diagnostic exercises the real code)

/// The Claude Desktop window to dock against, in AppKit (bottom-left origin) coords, or nil.
/// Among normal (layer 0), reasonably sized Claude windows we pick the one with the largest
/// area that is actually VISIBLE on some screen, so a remembered off-screen or secondary
/// display window can never win and push the widget off-screen.
func claudeDockWindowRect(bundleID: String) -> NSRect? {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { !$0.isTerminated }) else { return nil }
    let pid = Int(app.processIdentifier)
    let primaryH = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
                 ?? NSScreen.main?.frame.height ?? 0
    let screens = NSScreen.screens.map { $0.frame }
    guard let infos = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
    // The REAL Claude window can sit at a NON-zero window level (Electron / Cowork runs it at
    // layer 3, while layer-0 entries are off-screen ghosts), so we must NOT filter by layer == 0.
    // Pick the Claude window that is actually visible: on-screen, sizable, overlapping a display,
    // choosing the largest visible area. If nothing reports on-screen (flag unavailable), fall
    // back to best screen overlap.
    func pick(requireOnScreen: Bool) -> NSRect? {
        var best: NSRect?; var bestVisible: CGFloat = 0
        for w in infos {
            guard (w[kCGWindowOwnerPID as String] as? Int) == pid,
                  (w[kCGWindowLayer as String] as? Int ?? 0) < 100,                 // skip system overlays (layer 1000)
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: bd as CFDictionary),
                  cg.width > 300, cg.height > 300 else { continue }                 // a real content window
            if requireOnScreen, (w[kCGWindowIsOnscreen as String] as? Bool) != true { continue }
            let rect = NSRect(x: cg.minX, y: primaryH - cg.minY - cg.height, width: cg.width, height: cg.height)
            let visible = screens.reduce(CGFloat(0)) { acc, sf in
                let i = sf.intersection(rect); return acc + (i.isNull ? 0 : i.width * i.height)
            }
            if visible > bestVisible { bestVisible = visible; best = rect }          // most-visible window wins
        }
        return bestVisible > 0 ? best : nil
    }
    return pick(requireOnScreen: true) ?? pick(requireOnScreen: false)
}

/// Keep a panel rect fully on the screen that best contains `anchor` (the docking edge point),
/// so quirky window geometry (off-screen edges, disconnected displays) can never hide the widget.
func clampToScreen(_ rect: NSRect, near anchor: NSPoint) -> NSRect {
    let frame = NSScreen.screens.first(where: { $0.frame.contains(anchor) })?.frame
              ?? NSScreen.screens.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })?.frame
              ?? NSScreen.main?.frame ?? rect
    var r = rect
    if r.width <= frame.width  { r.origin.x = min(max(r.origin.x, frame.minX), frame.maxX - r.width) }
    if r.height <= frame.height { r.origin.y = min(max(r.origin.y, frame.minY), frame.maxY - r.height) }
    return r
}

extension Notification.Name {
    static let openChartSettings = Notification.Name("com.maz.burndown.openChartSettings")
    static let fireTestAlert = Notification.Name("com.maz.burndown.fireTestAlert")
    static let beaconWinkNow = Notification.Name("com.maz.burndown.beaconWinkNow")
    static let burndownDidSignIn = Notification.Name("com.maz.burndown.didSignIn")
    static let burndownDidSignOut = Notification.Name("com.maz.burndown.didSignOut")
    static let showWelcomeTour = Notification.Name("com.maz.burndown.showWelcomeTour")
}

// Lightweight notification-path tracing → ~/.config/burndown/notif-debug.log
// Private to the user (0600) and size-capped like the live-debug log.
func notifLog(_ s: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/burndown/notif-debug.log")
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(s)\n"
    guard let d = line.data(using: .utf8) else { return }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
       size > 1_000_000, let all = try? Data(contentsOf: url) {
        try? all.suffix(all.count / 4).write(to: url)
    }
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(d); try? h.close() }
    else { try? d.write(to: url) }
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    // Show alert banners even when the app is frontmost (e.g. Settings open), so the test alert + live alerts actually appear.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        notifLog("willPresent: \(notification.request.content.title)")
        completionHandler([.banner, .list, .sound])
    }
    // Handle the banner buttons (Snooze / Open) and a plain click on the banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        notifLog("didReceive: \(response.actionIdentifier)")
        switch response.actionIdentifier {
        case UsageAlerts.actionSnooze:
            alerts.snooze(15)
        case UsageAlerts.actionOpen, UNNotificationDefaultActionIdentifier:
            DispatchQueue.main.async { [weak self] in self?.openFromNotification() }
        default: break
        }
        completionHandler()
    }
    private func openFromNotification() {
        NSApp.activate(ignoringOtherApps: true)
        if let p = popover, !p.isShown { togglePopover() }
    }
    let engine = UsageEngine()
    let settings = AppSettings()
    let liveActivity = LiveActivity()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow!
    private var floatingPanel: NSPanel?
    // While the floating card's corner grip is dragged, hold this top-left corner still so the
    // panel grows DOWN-RIGHT under the cursor (an AppKit window otherwise grows from bottom-left).
    private var floatResizePin: NSPoint?
    private var edgePanel: NSPanel?          // small widget docked to the Claude Desktop window edge
    let edgeState = EdgeState()               // shared lost/rescan state for the widget
    private var tidePanels: [NSPanel] = []   // screen-edge tide line, one overlay per display
    // Peek: a hover readout. The tide panels are click-through, so a global mouse monitor watches
    // for the cursor entering the line's band and shows a tiny capsule; the line itself never eats clicks.
    private var tidePeekPanel: NSPanel?
    private var tidePeekMonitor: Any?
    private var edgeTimer: Timer?            // tracks the Claude window position while docked
    private var edgeTimerInterval: TimeInterval = 0   // current poll cadence (60fps fallback vs 2s AX reconcile)
    private var edgeDragging = false         // user is hand-dragging the widget → don't fight it
    private var edgeDragAt = Date(timeIntervalSince1970: 0)
    private var lastEdgeOrigin = NSPoint.zero  // last origin WE set (to tell our moves from the user's)
    private var axObserver: AXObserver?       // event-driven window tracking (zero lag) when Accessibility is granted
    private var axPID: pid_t = 0
    private var axPrompted = false
    private let claudeBundleID = "com.anthropic.claudefordesktop"
    private var cancellables = Set<AnyCancellable>()
    private let alerts = UsageAlerts()
    private var fullTimer: Timer?
    private var liveTimer: Timer?
    private var usageTimer: Timer?            // coarse ~60s sampler for the Usage chart series

    // Menu-bar animation state (for the live styles).
    private var animTimer: Timer?
    private var displayNeedle: Double = 0      // eased toward liveActivity.norm
    private var animPhase: Double = 0          // ever-advancing seconds (flame flicker / spark motion)
    private var burnClock = BurnClock()        // the One Pulse clock: elapsed + tier + breath
    private var lastAnimUptime: TimeInterval = 0   // monotonic, for real-dt frame advance (adaptive rate)
    private var glyphLayer: CALayer?          // the menu-bar glyph, driven via CA (never button.image)
    private var lastTideUptime: TimeInterval = 0   // the full-width tide redraws at its own slow cap
    private var displayHeat: Double = BurnTier.idle.heat   // lerps toward tier.heat at 0.06/frame
    private var beaconClock = BeaconClock()    // Beacon's wink: a 3-5s timer, advanced off animPhase
    private var beaconEnv: Double = 0          // this frame's wink envelope (the clock advances once/frame)
    private var lastBeaconKey = ""             // every input the Beacon glyph draws from
    private var lastTokText = ""
    private var rollFrom = ""
    private var rollPhase: Double = 1          // 1 = settled
    private var lastQuick = Date(timeIntervalSince1970: 0)
    private var activeRefresh = false          // are we currently in the fast (active) cadence?
    private let activePeriod: Double = 2       // refresh cadence while tokens are flowing
    private var liveInterval: Double = 30       // current backoff interval (Smart refresh)

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self   // so alert banners show (incl. when foreground)
        registerNotificationCategory()
        setupStatusItem()
        applyTheme()
        bind()
        // Escape / Cmd+W close whichever auxiliary window is key. An LSUIElement app has no main
        // menu, so Cmd+W has no File > Close to route to and both were dead keys; every aux
        // window could only be closed with the mouse. Escape defers to an active text editor
        // first (field editors are NSTextView), so it still cancels editing before closing.
        keyDismissMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, let win = NSApp.keyWindow,
                  [self.settingsWindow, self.accountWindow, self.insightsWindow,
                   self.aboutWindow, self.welcomeWindow].contains(where: { $0 === win }) else { return e }
            let esc = e.keyCode == 53 && !(win.firstResponder is NSTextView)
            let cmdW = e.keyCode == 13 && e.modifierFlags.contains(.command)
            if esc || cmdW { win.performClose(nil); return nil }
            return e
        }
        // QA (CUB_OPEN_POPOVER=1): open the popover and PIN it open, so its steady-state cost can be
        // profiled with `top`/`sample`. Transient behavior would close it the moment focus moved.
        if ProcessInfo.processInfo.environment["CUB_OPEN_POPOVER"] != nil {
            popover.behavior = .applicationDefined
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.togglePopover() }
            // QA (CUB_QA_POPRESIZE=<width>x<boost>): prove the live reflow path end to end with no
            // mouse. Prints the popover's contentSize before and after a runtime width + chart-boost
            // change (the exact settings a grip drag drives) plus the window id, so
            // `screencapture -l` can shoot it.
            // ⚠️ cardWidth/cardChartBoost PERSIST: the QA runner must restore the user's values
            // afterwards (`defaults write com.maz.burndown cardWidth <saved>` etc).
            if let qa = ProcessInfo.processInfo.environment["CUB_QA_POPRESIZE"] {
                let parts = qa.split(separator: "x").compactMap { Double($0) }
                let w = parts.count > 0 ? parts[0] : 380, b = parts.count > 1 ? parts[1] : 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    guard let self else { return }
                    let s0 = self.popover.contentSize
                    print("CUB_POP_BEFORE=\(Int(s0.width))x\(Int(s0.height)) w=\(self.settings.cardWidth) boost=\(self.settings.cardChartBoost)")
                    self.popover.animates = false
                    self.settings.cardWidth = CardResize.clampW(w)
                    self.settings.cardChartBoost = CardResize.clampB(b)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        let s1 = self.popover.contentSize
                        print("CUB_POP_AFTER=\(Int(s1.width))x\(Int(s1.height)) w=\(self.settings.cardWidth) boost=\(self.settings.cardChartBoost)")
                        if let win = self.popover.contentViewController?.view.window {
                            print("CUB_POP_WINID=\(win.windowNumber) frame=\(Int(win.frame.width))x\(Int(win.frame.height))")
                        }
                        fflush(stdout)   // the QA runner reads these mid-run from a redirected pipe
                    }
                }
            }
        }

        // QA (CUB_QA_FLOATPIN=1): reproduce a grip drag on the floating card with no mouse.
        // Pins the top-left exactly like ResizeGrip.began, then steps cardWidth like drag ticks.
        // This crashed with a re-entrant setFrameOrigin before the windowDidResize defer fix
        // (three identical SIGABRTs on 2026-08-01); it must print survived after.
        if ProcessInfo.processInfo.environment["CUB_QA_FLOATPIN"] != nil {
            // Marker file so a headless runner can tell "survived" from "died" without parsing
            // stdout. Defaults under the app's own config dir; CUB_QA_FLOATPIN_OUT overrides it.
            let markPath = ProcessInfo.processInfo.environment["CUB_QA_FLOATPIN_OUT"]
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".config/burndown/floatpin.state").path
            let mark: (String) -> Void = { try? Data($0.utf8).write(to: URL(fileURLWithPath: markPath)) }
            mark("armed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self, let panel = self.floatingPanel else { mark("no-panel"); return }
                self.floatResizePin = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
                var w = CardResize.minWidth
                var b = 0.0
                Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
                    guard let self else { t.invalidate(); return }
                    w += 3; b += 2
                    if w > 380 {
                        t.invalidate(); self.floatResizePin = nil
                        mark("survived")
                        return
                    }
                    // Both axes, like a real diagonal drag: width reflows, boost changes HEIGHT
                    // (the natH preference -> outer frame path, which a width-only sim missed).
                    self.settings.cardWidth = w
                    self.settings.cardChartBoost = min(CardResize.maxBoost, b)
                }
            }
        }

        engine.usageEnabled = settings.usageAPI   // honor the opt-in gate before any live fetch
        engine.recordDays = settings.chartDays    // record depth follows the Day span setting
        UsageEngine.cliBootstrapAllowed = settings.borrowCLI   // consent gate for the CLI credential
        // Sign-in/out lifecycle: completing OAuth counts as opting in to live usage; signing out
        // revokes both the live opt-in and the CLI-borrow consent, so it sticks.
        NotificationCenter.default.addObserver(forName: .burndownDidSignIn, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if !self.settings.usageAPI { self.settings.usageAPI = true }
        }
        NotificationCenter.default.addObserver(forName: .burndownDidSignOut, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.settings.usageAPI { self.settings.usageAPI = false }
            if self.settings.borrowCLI { self.settings.borrowCLI = false }
        }
        // QA: CUB_UPDATE_NOW=1 forces a foreground check + install and narrates each state, so
        // run-update-e2e.sh can verify the whole download/verify/swap path against a real release.
        if ProcessInfo.processInfo.environment["CUB_UPDATE_NOW"] != nil {
            print("E2E current=\(kAppVersion) dev=\(Updater.shared.isDevBuild)")
            Updater.shared.$state
                .removeDuplicates()
                .sink { st in print("E2E state=\(st)"); fflush(stdout) }
                .store(in: &cancellables)
            Updater.shared.check {
                if case .available = Updater.shared.state { Updater.shared.downloadAndInstall() }
                else { print("E2E no-update-available"); fflush(stdout); exit(3) }
            }
        }

        // Updates: one quiet check a few seconds after launch (if enabled and due), then the
        // 10-minute housekeeping timer re-tests the 24h interval. Never on a dev checkout.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self else { return }
            Updater.shared.checkInBackgroundIfDue(enabled: self.settings.autoUpdateCheck)
        }
        // First run: the welcome tour introduces the app and hosts the connect choices.
        if !settings.onboarded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.showWelcome() }
        }
        NotificationCenter.default.addObserver(forName: .showWelcomeTour, object: nil, queue: .main) { [weak self] _ in
            self?.showWelcome()
        }
        engine.fullScan()
        engine.fetchLive()
        engine.refreshAPISpend()   // developer-API spend, if an Admin key was saved
        engine.logPlanFields()
        engine.publishAccount()
        liveActivity.start()
        rescheduleTimers()
        startUsageSampler()
        syncFloating()   // restore the on-screen monitor if it was left open
        // QA only: open a window on launch so the window-activation fix can be verified headlessly.
        if let o = ProcessInfo.processInfo.environment["CUB_OPEN"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                switch o {
                case "account":  self.showAccount()
                case "insights": self.showInsights()
                default:         self.openSettings()
                }
                let w = (o == "account") ? self.accountWindow
                      : (o == "insights") ? self.insightsWindow : self.settingsWindow
                // CUB_TALL=<points> grows the window for documentation captures, so a long
                // settings pane can be photographed whole instead of scrolled.
                if let t = ProcessInfo.processInfo.environment["CUB_TALL"], let h = Double(t) {
                    w?.setContentSize(NSSize(width: w?.contentView?.frame.width ?? 660, height: h))
                }
                if ProcessInfo.processInfo.environment["CUB_ONSCREEN"] == nil {
                    w?.setFrameOrigin(NSPoint(x: -4000, y: 300))   // QA: render off the user's screen
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if let n = w?.windowNumber { print("CUB_WINID=\(n)"); fflush(stdout) }
                }
            }
        }
        // Show/hide the docked edge widget the instant Claude Desktop activates/deactivates.
        let wc = NSWorkspace.shared.notificationCenter
        wc.addObserver(self, selector: #selector(claudeActivationChanged),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        wc.addObserver(self, selector: #selector(claudeActivationChanged),
                       name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
        syncEdgeDock()   // start the edge-dock widget if it was left enabled
        syncTideLine()   // restore the screen-edge tide line if it was left enabled
        // Rebuild tide overlays when displays are added/removed/resized or rearranged.
        NotificationCenter.default.addObserver(self, selector: #selector(tideScreensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Chart gear → open Settings on the Charts & Data tab.
        NotificationCenter.default.addObserver(forName: .openChartSettings, object: nil, queue: .main) { [weak self] _ in
            self?.settings.pendingTab = "data"; self?.openSettings()
        }
        NotificationCenter.default.addObserver(forName: .fireTestAlert, object: nil, queue: .main) { [weak self] _ in
            notifLog("observer: fireTestAlert received")
            self?.alerts.fireTest(soundName: self?.settings.alertSoundName ?? "")
        }
        // Settings "Wink now": fire one immediately so a long cadence isn't a minute of waiting.
        NotificationCenter.default.addObserver(forName: .beaconWinkNow, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.beaconClock.fireNow(at: self.animPhase, length: self.settings.beaconLength)
            self.ensureAnimating()
        }
    }

    // Register the Snooze / Open buttons that appear on every Burndown alert banner.
    private func registerNotificationCategory() {
        let snooze = UNNotificationAction(identifier: UsageAlerts.actionSnooze, title: "Snooze 15 min", options: [])
        let open = UNNotificationAction(identifier: UsageAlerts.actionOpen, title: "Open Burndown", options: [.foreground])
        let cat = UNNotificationCategory(identifier: UsageAlerts.category, actions: [snooze, open],
                                         intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([cat])
    }

    // MARK: - Edge dock (a small widget glued to a side of the Claude Desktop window)

    @objc private func claudeActivationChanged(_ n: Notification) { setupAXTracking(); retuneEdgeTimer(); updateEdgeDock() }

    // While docking is enabled, run a steady tracker. The widget shows itself only when a Claude
    // Desktop window is actually visible on a display (decided in updateEdgeDock) and follows it.
    // No longer gated on Claude being frontmost, which made it feel like it never appeared.
    private func syncEdgeDock() {
        guard settings.dockEdge != .off else {
            edgeTimer?.invalidate(); edgeTimer = nil; edgeTimerInterval = 0
            edgePanel?.orderOut(nil)
            teardownAX()
            return
        }
        setupAXTracking()   // upgrade to instant, event-driven tracking if Accessibility is granted
        retuneEdgeTimer()
        updateEdgeDock()
    }

    /// The poll is the FALLBACK, not the engine: 60fps only while AX event delivery is absent.
    /// Once the observer is live it drops to a 2s reconcile that catches what AX cannot see
    /// (silent observer death, Claude quitting, display reconfiguration). Polling at 60Hz on top
    /// of working AX events re-derived the same frame sixty times a second for nothing.
    private func retuneEdgeTimer() {
        guard settings.dockEdge != .off else { return }
        let want: TimeInterval = axObserver != nil ? 2.0 : 1.0 / 60.0
        guard edgeTimerInterval != want || edgeTimer == nil else { return }
        edgeTimer?.invalidate()
        let t = Timer(timeInterval: want, repeats: true) { [weak self] _ in self?.updateEdgeDock() }
        RunLoop.main.add(t, forMode: .common); edgeTimer = t; edgeTimerInterval = want
    }

    // Event-driven window tracking: when the user has granted Accessibility, observe Claude's
    // window-moved / resized events and reposition the widget the instant they fire (zero lag).
    // If permission is absent we never create the observer, so behavior is exactly the 60fps timer.
    private func setupAXTracking() {
        guard settings.dockEdge != .off,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: claudeBundleID).first(where: { !$0.isTerminated })
        else { return }
        let pid = app.processIdentifier
        if axObserver != nil && axPID == pid { return }   // already observing this Claude instance
        teardownAX()
        guard AXIsProcessTrusted() else {
            if !axPrompted {   // ask once; macOS opens System Settings > Privacy > Accessibility
                axPrompted = true
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary)
            }
            return   // fall back to the 60fps timer until granted
        }
        // Synchronous callback on the main run loop (no dispatch hop = no added latency).
        let cb: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue().updateEdgeDock()
        }
        var obs: AXObserver?
        guard AXObserverCreate(pid, cb, &obs) == .success, let observer = obs else { return }
        let appEl = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // App-level: re-resolve which window to follow on focus / activation changes.
        for n in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXApplicationActivatedNotification] {
            AXObserverAddNotification(observer, appEl, n as CFString, refcon)
        }
        // Window-level: move/resize fire on the focused window element itself.
        var winRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
           let we = winRef, CFGetTypeID(we) == AXUIElementGetTypeID() {
            let winEl = we as! AXUIElement   // safe: typeID checked above
            AXObserverAddNotification(observer, winEl, kAXWindowMovedNotification as CFString, refcon)
            AXObserverAddNotification(observer, winEl, kAXWindowResizedNotification as CFString, refcon)
        }
        // THE fix: add to .commonModes. With .defaultMode, AX notifications are queued (not
        // delivered) during a live window drag (event-tracking run-loop mode) → that was the lag.
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        axObserver = observer; axPID = pid
    }
    private func teardownAX() {
        if let o = axObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(o), .commonModes) }   // must match the add mode
        axObserver = nil; axPID = 0
    }

    // MARK: - Tide line: a luminous filament hugging a chosen screen edge, on EVERY
    // screen. It spans the full edge; the bright segment = REMAINING session budget (recedes as you
    // drain), warming with burn rate and reddening near the cap. Rebuilds when displays change.
    private func syncTideLine() {
        if settings.tideLine { rebuildTidePanels() }
        else { clearTidePanels() }
        updateTidePeek()
        ensureAnimating()   // the tide breath is driven by the shared animator (starts/stops it)
    }

    private func clearTidePanels() {
        for p in tidePanels { p.orderOut(nil) }
        tidePanels.removeAll()
    }

    private func makeTidePanel() -> NSPanel {
        let view = TideLineView(frame: NSRect(x: 0, y: 0, width: 100, height: kTideThick))
        let panel = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = view
        panel.isFloatingPanel = true
        // Above the menu bar so the TOP edge sits flush at the very top of the screen, not under the bar.
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true                       // pure overlay, never steals clicks
        return panel
    }

    // Frame flush to the given edge of a screen. `length` spans a centered fraction of the edge.
    private func tideFrame(_ edge: DockEdge, _ f: NSRect, length: CGFloat = 1) -> NSRect {
        let t = kTideThick, len = max(0.4, min(1, length))
        switch edge {
        case .top:    let w = f.width * len;  return NSRect(x: f.midX - w / 2, y: f.maxY - t, width: w, height: t)
        case .bottom: let w = f.width * len;  return NSRect(x: f.midX - w / 2, y: f.minY, width: w, height: t)
        case .left:   let h = f.height * len; return NSRect(x: f.minX, y: f.midY - h / 2, width: t, height: h)
        case .right:  let h = f.height * len; return NSRect(x: f.maxX - t, y: f.midY - h / 2, width: t, height: h)
        case .off:    return .zero
        }
    }

    /// Displays picker: which screens carry the Ember Line.
    private func tideShows(_ screen: NSScreen) -> Bool {
        switch settings.tideDisplays {
        case .all:    return true
        case .main:   return screen == NSScreen.main
        case .claude:
            guard let r = claudeDockWindowRect(bundleID: claudeBundleID) else { return screen == NSScreen.main }
            return NSPointInRect(NSPoint(x: r.midX, y: r.midY), screen.frame)
        }
    }

    // (Re)create exactly one overlay per screen. Called on enable, edge change, and display changes.
    private func rebuildTidePanels() {
        clearTidePanels()
        guard settings.tideLine, settings.tideEdge != .off else { return }
        for _ in NSScreen.screens { tidePanels.append(makeTidePanel()) }
        updateTideLine()
        for p in tidePanels { p.orderFront(nil) }
    }

    private func updateTideLine() {
        guard settings.tideLine, settings.tideEdge != .off else { clearTidePanels(); return }
        let screens = NSScreen.screens
        if tidePanels.count != screens.count { rebuildTidePanels(); return }   // display set changed
        let edge = settings.tideEdge
        let s = engine.snapshot
        let rem = CGFloat(max(0, 1 - s.sessionPct))
        let heat = CGFloat(liveActivity.active ? max(0, min(1, liveActivity.norm)) : 0)
        let red = CGFloat(s.over ? 1 : max(0, (min(1, s.sessionPct) - 0.85) / 0.15))
        for (i, screen) in screens.enumerated() {
            let panel = tidePanels[i]
            panel.setFrame(tideFrame(edge, screen.frame, length: CGFloat(settings.tideLength)), display: false)
            panel.alphaValue = tideShows(screen) ? CGFloat(settings.tideOpacity) : 0   // displays + transparency
            if let v = panel.contentView as? TideLineView {
                v.horizontal = edge.horizontal
                v.edge = edge
                v.style = settings.tideStyle
                v.flames = settings.tideFlames
                v.glowMul = CGFloat(settings.tideGlow)
                v.thickness = settings.tideThickness.points
                v.sparkRate = settings.tideSparks.rate
                v.smoke = settings.tideSmoke
                v.remaining = rem; v.heat = heat; v.redline = red
                // All elements share phase EXCEPT the tide line, which lags 0.25 phase
                // as a deliberate echo. This is the only sanctioned offset in the product.
                v.phase = animPhase - 0.25 * burnClock.period
                v.clockPeriod = burnClock.period
                v.sessionCol = NSColor(Palette.of(.dark).session)   // emissive-token rule: DARK role values
                v.overCol = NSColor(Palette.of(.dark).overLimit)
                v.needsDisplay = true
            }
        }
    }

    // Displays added / removed / resized (or resolution/arrangement change) → rebuild every overlay.
    @objc private func tideScreensChanged() {
        if settings.tideLine { rebuildTidePanels() }
    }

    // Peek readout: install/remove the global hover monitor based on the setting.
    func updateTidePeek() {
        let want = settings.tideLine && settings.tidePeek && settings.tideEdge != .off
        if want, tidePeekMonitor == nil {
            tidePeekMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                self?.tidePeekTick()
            }
        } else if !want, let m = tidePeekMonitor {
            NSEvent.removeMonitor(m); tidePeekMonitor = nil
            tidePeekPanel?.orderOut(nil)
        }
    }

    private func tidePeekTick() {
        let edge = settings.tideEdge
        let mouse = NSEvent.mouseLocation                    // global, bottom-left origin
        guard let screen = NSScreen.screens.first(where: { NSPointInRect(mouse, $0.frame) }), tideShows(screen) else {
            tidePeekPanel?.orderOut(nil); return
        }
        let f = screen.frame, band: CGFloat = 14
        let near: Bool
        switch edge {
        case .top:    near = mouse.y >= f.maxY - band
        case .bottom: near = mouse.y <= f.minY + band
        case .left:   near = mouse.x <= f.minX + band
        case .right:  near = mouse.x >= f.maxX - band
        case .off:    near = false
        }
        guard near else { tidePeekPanel?.orderOut(nil); return }
        let s = engine.snapshot
        let pct = Int(((1 - min(1, s.sessionPct)) * 100).rounded())
        let left = s.sessionResetAt.map { weekLeftString($0) } ?? "--"
        showTidePeek("\(pct)% left · \(left)", at: mouse, edge: edge, screen: screen)
    }

    private func showTidePeek(_ text: String, at mouse: NSPoint, edge: DockEdge, screen: NSScreen) {
        let panel: NSPanel
        if let p = tidePeekPanel { panel = p }
        else {
            panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 160, height: 22),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            panel.isFloatingPanel = true; panel.level = .statusBar; panel.hasShadow = true
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            tidePeekPanel = panel
        }
        let label = TidePeekView(text: text)
        let host = NSHostingView(rootView: label)
        host.frame = NSRect(x: 0, y: 0, width: 168, height: 24)
        panel.contentView = host
        let w: CGFloat = 168, h: CGFloat = 24, pad: CGFloat = 8
        var x = mouse.x - w / 2, y = mouse.y
        switch edge {
        case .top:    y = screen.frame.maxY - h - pad - kTideThick
        case .bottom: y = screen.frame.minY + pad + kTideThick
        case .left:   x = screen.frame.minX + pad + kTideThick; y = mouse.y - h / 2
        case .right:  x = screen.frame.maxX - w - pad - kTideThick; y = mouse.y - h / 2
        case .off:    break
        }
        x = max(screen.frame.minX + 4, min(screen.frame.maxX - w - 4, x))
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        panel.orderFront(nil)
    }

    private func ensureEdgePanel() -> NSPanel {
        if let p = edgePanel { return p }
        edgeState.onRescan = { [weak self] in self?.updateEdgeDock() }
        let host = NSHostingController(rootView: EdgeDockView(engine: engine, settings: settings, edgeState: edgeState))
        host.sizingOptions = [.preferredContentSize]   // panel hugs the widget (resizes when orientation changes)
        let panel = NSPanel(contentViewController: host)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)  // sit above Claude's own window level
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                 // the SwiftUI card draws its own shadow
        panel.ignoresMouseEvents = false        // receive drags so the user can slide it along the edge
        panel.isMovableByWindowBackground = true
        panel.delegate = self                   // windowDidMove → recompute the along-edge offset
        panel.appearance = themeAppearance()
        panel.alphaValue = settings.windowOpacity
        edgePanel = panel
        return panel
    }

    private func onAnyScreen(_ rect: NSRect) -> Bool {
        let c = NSPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.contains { $0.frame.contains(c) }
    }

    // The Claude Desktop window we should dock to, in AppKit coords (or nil). Delegates to a
    // file-scope helper that prefers the most on-screen window (never a remembered off-screen one).
    private func claudeWindowRect() -> NSRect? { claudeDockWindowRect(bundleID: claudeBundleID) }

    private func updateEdgeDock() {
        guard settings.dockEdge != .off else { edgePanel?.orderOut(nil); return }
        guard let win = claudeWindowRect() else {
            // Lost state: if Claude is running but its window can't be found, show the
            // "not found / click to re-scan" plaque at the last position rather than vanishing.
            // If Claude is not running at all, hide entirely.
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: claudeBundleID).contains { !$0.isTerminated }
            if running {
                edgeState.lost = true
                let panel = ensureEdgePanel()
                if lastEdgeOrigin != .zero { panel.setFrameOrigin(lastEdgeOrigin) }
                else if let sc = NSScreen.main { panel.setFrameOrigin(NSPoint(x: sc.frame.midX - 80, y: sc.frame.midY)) }
                if !panel.isVisible { panel.orderFront(nil) }
            } else {
                edgePanel?.orderOut(nil)
            }
            return
        }
        edgeState.lost = false
        let panel = ensureEdgePanel()
        if !panel.isVisible { panel.orderFront(nil) }
        if settings.dockLocked { return }   // locked, so stay where the user placed it
        // While the user is hand-dragging it, leave it where they put it; resume tracking shortly after.
        if edgeDragging {
            if Date().timeIntervalSince(edgeDragAt) > 0.35 { edgeDragging = false } else { return }
        }
        let placed = clampToScreen(edgeFrame(for: win, panel.frame.size), near: edgeAnchor(for: win))
        lastEdgeOrigin = placed.origin          // record BEFORE moving so windowDidMove ignores our own move
        panel.setFrameOrigin(placed.origin)
    }

    // Where the widget should sit, honoring inside/outside and the along-edge offset (0..1).
    private func edgeFrame(for win: NSRect, _ size: NSSize) -> NSRect {
        let w = size.width, h = size.height, pad = kEdgePad
        let inside = settings.dockInside, px = settings.edgePx, fromEnd = settings.edgeFromEnd
        var origin = NSPoint.zero
        switch settings.dockEdge {
        case .right, .left:
            let x: CGFloat = (settings.dockEdge == .right)
                ? (inside ? win.maxX - w + pad : win.maxX - pad)
                : (inside ? win.minX - pad : win.minX - w + pad)
            // Fixed point distance from the anchored corner so a window resize never moves it.
            let y: CGFloat = px < 0 ? (win.midY - h / 2)
                : (fromEnd ? win.minY + px : win.maxY - h - px)
            origin = NSPoint(x: x, y: y)
        case .top, .bottom:
            let y: CGFloat = (settings.dockEdge == .top)
                ? (inside ? win.maxY - h + pad : win.maxY - pad)
                : (inside ? win.minY - pad : win.minY - h + pad)
            let x: CGFloat = px < 0 ? (win.midX - w / 2)
                : (fromEnd ? win.maxX - w - px : win.minX + px)
            origin = NSPoint(x: x, y: y)
        case .off: break
        }
        return NSRect(origin: origin, size: size)
    }
    private func edgeAnchor(for win: NSRect) -> NSPoint {
        switch settings.dockEdge {
        case .right:  return NSPoint(x: win.maxX, y: win.midY)
        case .left:   return NSPoint(x: win.minX, y: win.midY)
        case .top:    return NSPoint(x: win.midX, y: win.maxY)
        case .bottom: return NSPoint(x: win.midX, y: win.minY)
        case .off:    return NSPoint(x: win.midX, y: win.midY)
        }
    }

    // User dragged the widget → convert its new position into an along-edge offset (0..1) and save.
    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow, panel === edgePanel,
              let win = claudeWindowRect() else { return }
        let o = panel.frame.origin
        // Ignore our own programmatic moves (they match lastEdgeOrigin).
        if abs(o.x - lastEdgeOrigin.x) < 2 && abs(o.y - lastEdgeOrigin.y) < 2 { return }
        let w = panel.frame.width, h = panel.frame.height
        // Store a FIXED distance from whichever corner is nearer, so resizing the window keeps it put.
        if settings.dockEdge.horizontal {
            let fromLeft = o.x - win.minX, fromRight = win.maxX - (o.x + w)
            if fromRight < fromLeft { settings.edgeFromEnd = true;  settings.edgePx = max(0, fromRight) }
            else                    { settings.edgeFromEnd = false; settings.edgePx = max(0, fromLeft) }
        } else {
            let fromBottom = o.y - win.minY, fromTop = win.maxY - (o.y + h)
            if fromBottom < fromTop { settings.edgeFromEnd = true;  settings.edgePx = max(0, fromBottom) }
            else                    { settings.edgeFromEnd = false; settings.edgePx = max(0, fromTop) }
        }
        edgeDragging = true; edgeDragAt = Date()
    }

    // A coarse, refresh-independent sampler that records the session % once a minute,
    // so the Usage chart builds a clean ~1/60s, 6-hour curve no matter how fast or slow
    // the live refresh runs. (recordUsage self-throttles, so this never over-samples.)
    private func startUsageSampler() {
        liveActivity.recordUsage(session: engine.snapshot.sessionPct, weekly: engine.snapshot.weeklyPct)   // seed an immediate point
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.liveActivity.recordUsage(session: self.engine.snapshot.sessionPct, weekly: self.engine.snapshot.weeklyPct)
            self.engine.liveBurnPerMin = self.liveActivity.rate
        }
        RunLoop.main.add(t, forMode: .common); usageTimer = t
    }

    // MARK: - Floating "always on screen" monitor (same card as the popover)

    private func syncFloating() {
        if settings.floatingShown {
            if floatingPanel == nil { showFloating() }
        } else {
            floatingPanel?.close()   // → windowWillClose nils it
        }
    }

    private func showFloating() {
        let host = NSHostingController(rootView: MenuCard(
            engine: engine, settings: settings, live: liveActivity,
            onRefresh: { [weak self] in self?.manualRefresh() },
            floating: true,
            onSettings: { [weak self] in self?.openSettings() },
            onHideFloating: { [weak self] in self?.settings.floatingShown = false },
            onSignIn: { [weak self] in self?.showAccount() },
            onOpenLogs: { [weak self] in self?.openLogs() },
            onResizing: { [weak self] active in
                guard let self, let panel = self.floatingPanel else { return }
                self.floatResizePin = active ? NSPoint(x: panel.frame.minX, y: panel.frame.maxY) : nil
            }))
        host.sizingOptions = [.preferredContentSize]   // panel hugs the card
        let panel = NSPanel(contentViewController: host)
        if settings.floatingChrome {
            panel.styleMask = [.titled, .closable, .utilityWindow, .nonactivatingPanel]
            panel.title = kAppName
        } else {
            panel.styleMask = [.borderless, .nonactivatingPanel]   // clean, chrome-free card
        }
        panel.isFloatingPanel = true
        panel.level = settings.pinnedOnTop ? .floating : .normal   // pin = stay above other windows
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]  // follow across Spaces
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        // ⚠️ hasShadow stays at its DEFAULT (true) deliberately. Setting it false (2026-08-01,
        // chasing a stacked-shadow cosmetic) coincided with intermittent aborts inside
        // -[NSWindow _reallySetFrame:] on this panel's data-driven resizes; the borderless +
        // transparent + nonactivating + constraint-sized combination is exactly where AppKit's
        // server-side shadow bookkeeping is fragile. The doubled shadow is cosmetic; the crash
        // was not. If the cosmetic bothers again, test any change with a LONG soak (the abort
        // takes 1-2 minutes and needs live data resizes), not a quick drag.
        // ⚠️ Do NOT set wantsLayer on the content view here. It is an NSHostingView that manages
        // its own layer configuration; forcing it made every constraint-driven panel resize throw
        // inside -[NSWindow _reallySetFrame:] (the 2026-08-01 grip-drag crash), and it did not
        // change the glass compositing anyway (that difference is behind-window vibrancy).
        panel.delegate = self
        panel.setFrameAutosaveName("ClaudeMonitorFloating")
        // First open (or off-screen) → tuck under the menu bar, top-right.
        if panel.frame.origin == .zero || !NSScreen.screens.contains(where: { $0.frame.intersects(panel.frame) }) {
            if let vf = NSScreen.main?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: vf.maxX - panel.frame.width - 16, y: vf.maxY - panel.frame.height - 16))
            }
        }
        panel.appearance = themeAppearance()
        panel.isOpaque = false                     // let the frosted-glass slider show through
        panel.backgroundColor = .clear
        panel.alphaValue = settings.windowOpacity
        floatingPanel = panel
        panel.orderFront(nil)
    }

    func windowDidResize(_ notification: Notification) {
        // Grip drag on the floating card: re-pin the top-left corner after each content-driven
        // resize, so growth goes down-right, matching the cursor at the bottom-right grip.
        // ⚠️ DEFERRED on purpose. This notification arrives INSIDE -[NSWindow _reallySetFrame:]
        // while the constraint engine is mid-modification; a synchronous setFrameOrigin re-enters
        // the engine and AppKit aborts with an uncaught exception (three identical crash logs,
        // 2026-08-01, reproduced headless by CUB_QA_FLOATPIN). One runloop hop later the layout
        // pass is finished and the re-pin is safe.
        if let pin = floatResizePin, let w = notification.object as? NSWindow, w === floatingPanel {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.floatResizePin != nil, let panel = self.floatingPanel else { return }
                panel.setFrameOrigin(NSPoint(x: pin.x, y: pin.y - panel.frame.height))
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        let w = notification.object as? NSWindow
        if w === floatingPanel {
            floatingPanel = nil
            if settings.floatingShown { settings.floatingShown = false }   // user closed it → remember
        } else if w === settingsWindow {
            NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)   // menu-bar-only unless the Dock icon is on
        } else if w === welcomeWindow {
            settings.onboarded = true   // closing the tour counts as done; reopen from About any time
        }
    }

    @objc private func toggleFloating() { settings.floatingShown.toggle() }
    @objc private func togglePinnedOnTop() { settings.pinnedOnTop.toggle() }

    private func themeAppearance() -> NSAppearance? {
        switch settings.theme {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }

    // Apply the chosen theme to EVERY surface at once, so toggling it instantly
    // repaints the popover, Settings, the floating monitor, and About.
    private func applyTheme() {
        let a = themeAppearance()
        popover?.appearance = a
        settingsWindow?.appearance = a
        floatingPanel?.appearance = a
        aboutWindow?.appearance = a
        welcomeWindow?.appearance = a
        edgePanel?.appearance = a
        accountWindow?.appearance = a
    }

    // MARK: - Menu bar item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(statusClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            // Per-frame glyph goes into our OWN CALayer, never button.image. Setting button.image
            // runs a full Auto Layout intrinsic-content-size invalidation cascade + notifications on
            // EVERY call (measured: ~5ms, i.e. ~15% CPU at 30fps - it dwarfed the 90us of actual
            // drawing). A layer's `contents` is a plain CA property: the render server composites it,
            // costing the app nothing, so the fire can run buttery at 30fps.
            button.wantsLayer = true
            let l = CALayer()
            l.contentsGravity = .center
            l.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]  // no implicit fades
            button.layer?.addSublayer(l)
            glyphLayer = l
            updateStatusItem(engine.snapshot)
            // Display scale can change under a running status item (moving the bar between a
            // Retina and a 1x display, or a resolution switch). The glyph layer's contentsScale
            // is read per render, so one immediate re-render adopts the new scale; without this
            // the glyph stays soft or oversharp until the next data tick.
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeBackingPropertiesNotification,
                                                   object: nil, queue: .main) { [weak self] n in
                guard let self, let w = n.object as? NSWindow,
                      w === self.statusItem.button?.window else { return }
                self.updateStatusItem(self.engine.snapshot)
            }
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.appearance = nil   // follow system light/dark
        popover.delegate = self
        // The content is built on show and TORN DOWN on close (popoverDidClose). The MenuCard observes
        // live token flow and runs breathing TimelineViews; left resident, it re-rendered continuously
        // while HIDDEN - pinning a core during any active burn. A closed popover now costs nothing.
    }

    private func makePopoverHost() -> NSViewController {
        let h = NSHostingController(rootView: MenuCard(
            engine: engine, settings: settings, live: liveActivity,
            onRefresh: { [weak self] in self?.manualRefresh() },
            onSignIn: { [weak self] in self?.showAccount() },
            onOpenLogs: { [weak self] in self?.openLogs() },
            // Grip drag: kill the popover's size animation so the card tracks the cursor 1:1,
            // restore it on mouse-up. (.preferredContentSize sizing does the actual resizing.)
            onResizing: { [weak self] active in self?.popover.animates = !active }
        ).noFocusRing())
        h.sizingOptions = [.preferredContentSize]   // popover grows/shrinks to fit the card
        return h
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil   // stop the hidden card from rendering
    }

    // MARK: - Settings window (separate window - keeps the popover display-only)

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                settings: settings, engine: engine, live: liveActivity,
                loginInitially: isLoginInstalled(),
                onLogin: { [weak self] on in self?.setLogin(on) },
                onResetData: { [weak self] in self?.resetData() }
            )
            let hosting = NSHostingController(rootView: view)
            // Fixed-size sidebar Settings window (the SwiftUI root frames itself to match).
            let win = NSWindow(contentViewController: hosting)
            win.styleMask = [.titled, .closable]
            win.title = kAppName
            win.isReleasedWhenClosed = false
            win.setContentSize(NSSize(width: 660, height: 640))
            win.appearance = themeAppearance()
            win.center()
            win.delegate = self
            settingsWindow = win
        }
        NSApp.setActivationPolicy(.regular)   // foreground app while Settings is open so controls respond on the first click
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()   // accessory app: force the window above the active app
    }

    // Resize the Settings window to fit its content (capped to the screen), keeping the
    // top edge fixed and animating - so collapse/expand of Advanced feels graceful.
    private func resizeSettings(to contentHeight: CGFloat) {
        guard let win = settingsWindow, win.isVisible else { return }
        let cap = (NSScreen.main?.visibleFrame.height ?? 900) * 0.88
        let target = win.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 360, height: min(max(160, contentHeight), cap))).size
        if abs(win.frame.height - target.height) < 1.5 { return }
        var f = win.frame
        f.origin.y += f.size.height - target.height   // keep the top edge anchored
        f.size = target
        if let vf = NSScreen.main?.visibleFrame {      // keep fully on-screen as it grows
            if f.maxY > vf.maxY { f.origin.y = vf.maxY - f.height }
            if f.minY < vf.minY { f.origin.y = vf.minY }
        }
        win.setFrame(f, display: true, animate: true)
    }

    // MARK: - Account window (sign-in lives here now, not in Settings)

    private var accountWindow: NSWindow?
    private var insightsWindow: NSWindow?
    @objc private func showAccount() {
        if accountWindow == nil {
            let view = AccountView(
                engine: engine,
                settings: settings,
                onStartSignIn: { [weak self] in
                    if let url = self?.engine.signInURL() { NSWorkspace.shared.open(url) }
                },
                onFinishSignIn: { [weak self] code, done in
                    guard let self else { done(false); return }
                    self.engine.completeSignIn(code, completion: done)
                },
                onOpenLogs: { [weak self] in self?.openLogs() }
            )
            let host = NSHostingController(rootView: view.noFocusRing())
            host.sizingOptions = [.preferredContentSize]   // window hugs the content
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable]
            w.title = "Account"
            w.isReleasedWhenClosed = false
            w.appearance = themeAppearance()
            w.center()
            accountWindow = w
        }
        // Opening the Account window re-checks the plan + usage, so a plan change (e.g. Pro -> Max)
        // is picked up without a restart. force bypasses the 20s poll floor.
        engine.logPlanFields()
        engine.fetchLive(force: true)
        NSApp.activate(ignoringOtherApps: true)
        accountWindow?.makeKeyAndOrderFront(nil)
        accountWindow?.orderFrontRegardless()
    }

    @objc private func toggleDemo() {
        liveActivity.setDemo(!liveActivity.demo)
        ensureAnimating()
        updateStatusItem(engine.snapshot)
        updateTideLine()
    }

    // MARK: - Claude Code terminal gauge (Symbiosis v1)
    // A statusline script that renders Burndown's LIVE numbers inside every Claude Code session,
    // fed from ~/.config/burndown/burndown-live.json (already written on each refresh).
    // Fully reversible: settings.json is backed up once before the first install, and Remove
    // deletes only the statusLine key we added.

    private var claudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }
    private var gaugeScriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/burndown/statusline.sh")
    }

    private func gaugeInstalled() -> Bool {
        guard let d = try? Data(contentsOf: claudeSettingsURL),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let sl = o["statusLine"] as? [String: Any],
              let cmd = sl["command"] as? String else { return false }
        return cmd.contains("burndown")
    }

    @objc private func toggleGauge() {
        if gaugeInstalled() { removeGauge() } else { installGauge() }
    }

    private func installGauge() {
        let script = """
        #!/bin/sh
        # Burndown terminal gauge - your live Claude limits in the Claude Code statusline.
        # Installed by Burndown.app (menu > Install Terminal Gauge). Data: burndown-live.json.
        # Brand-mapped xterm-256. Compose segments with BURNDOWN_STATUSLINE (default bar,pct,resets,week):
        #   bar,pct,resets,week,cost,rate  ·  BURNDOWN_ASCII=1 swaps the flame for * and cells for # / -.
        exec /usr/bin/python3 - <<'PY'
        import json, os, datetime
        p = os.path.expanduser("~/.config/burndown/burndown-live.json")
        try:
            d = json.load(open(p))
        except Exception:
            print("Burndown: no live data (open the Burndown app)"); raise SystemExit
        ascii_m = os.environ.get("BURNDOWN_ASCII") == "1"
        s = d.get("sessionPct") or 0.0
        w = d.get("weeklyPct") or 0.0
        thr = 0.85
        rst = "\\033[0m"; bold = "\\033[1m"; track = "38;5;240"
        def hue():
            if s >= 1.0: return "38;5;124"   # overLimit A0341A -> 124
            if s >= thr: return "38;5;172"   # warning B8801C -> 172
            return "38;5;173"                # session C25A35 -> 173
        def paint(code, text): return "\\033[" + code + "m" + text + rst
        def left(iso):
            if not iso: return ""
            try:
                t = datetime.datetime.fromisoformat(iso.replace("Z", "+00:00"))
                secs = (t - datetime.datetime.now(datetime.timezone.utc)).total_seconds()
                if secs <= 0: return ""
                dd = int(secs // 86400); h = int(secs % 86400 // 3600); m = int(secs % 3600 // 60)
                if dd: return str(dd) + "d " + str(h) + "h"
                return (str(h) + "h " + ("%02d" % m) + "m") if h else (str(m) + "m")
            except Exception: return ""
        def bar():
            n = 10; k = int(round(min(1, max(0, s)) * n))
            fill = "#" if ascii_m else "\\u2593"; empt = "-" if ascii_m else "\\u2591"
            return paint(hue(), fill * k) + paint(track, empt * (n - k))
        def seg(name):
            if name == "bar": return ("bar", bar())
            if name == "pct":
                val = paint(hue(), bold + str(int(round(s*100))) + "%")
                sess = (bold + "session" + rst) if s >= thr else "session"
                return ("pct", val + " " + sess)
            if name == "resets":
                r = left(d.get("sessionResetAt")); return ("resets", "resets " + r) if r else None
            if name == "week":
                return ("week", "week " + bold + str(int(round(w*100))) + "%" + rst)
            if name == "cost":
                v = d.get("sessionCost")
                return ("cost", bold + "$" + str(int(round(v))) + rst) if v else None
            if name == "rate":
                v = d.get("burnPerMin")
                if not v: return None
                r = (str(int(round(v/1000))) + "k") if v >= 1000 else str(int(round(v)))
                return ("rate", bold + r + rst + " tok/min")
            return None
        order = os.environ.get("BURNDOWN_STATUSLINE", "bar,pct,resets,week").split(",")
        parts = [x for x in (seg(n.strip()) for n in order) if x]
        flame = "*" if ascii_m else "\\U0001F525"
        line = flame + " "
        for i, (kind, text) in enumerate(parts):
            if i == 0:
                line += text
            else:
                line += (" " if parts[i-1][0] == "bar" else " \\u00b7 ") + text
        print(line)
        PY
        """
        do {
            try script.write(to: gaugeScriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gaugeScriptURL.path)
            // An existing settings.json that will not parse is a hard stop, never an empty
            // object: merging into {} and writing it back would replace every setting the user
            // has with a lone statusLine key. Better to install nothing than to eat their file.
            var obj: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: claudeSettingsURL.path) {
                guard let d = try? Data(contentsOf: claudeSettingsURL),
                      let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                    notifLog("gauge install aborted: ~/.claude/settings.json is not readable JSON")
                    try? FileManager.default.removeItem(at: gaugeScriptURL)
                    return
                }
                obj = o
            }
            // One-time backup of the pre-Burndown settings (never overwritten on reinstall).
            let bak = claudeSettingsURL.deletingLastPathComponent().appendingPathComponent("settings.json.pre-burndown.bak")
            if FileManager.default.fileExists(atPath: claudeSettingsURL.path),
               !FileManager.default.fileExists(atPath: bak.path) {
                try? FileManager.default.copyItem(at: claudeSettingsURL, to: bak)
            }
            obj["statusLine"] = ["type": "command", "command": gaugeScriptURL.path]
            let out = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: claudeSettingsURL)
            notifLog("gauge installed")
        } catch { notifLog("gauge install failed: \(error.localizedDescription)") }
    }

    private func removeGauge() {
        guard let d = try? Data(contentsOf: claudeSettingsURL),
              var o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        // Only remove what we added - if the user switched to their own statusline, leave it be.
        if let sl = o["statusLine"] as? [String: Any], let cmd = sl["command"] as? String, cmd.contains("burndown") {
            o.removeValue(forKey: "statusLine")
            if let out = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) {
                try? out.write(to: claudeSettingsURL)
            }
        }
        try? FileManager.default.removeItem(at: gaugeScriptURL)
        notifLog("gauge removed")
    }

    @objc private func showInsights() {
        if insightsWindow == nil {
            let host = NSHostingController(rootView: InsightsView(engine: engine, settings: settings))
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .resizable]
            w.title = "Insights"
            w.isReleasedWhenClosed = false
            w.appearance = themeAppearance()
            w.setContentSize(NSSize(width: 420, height: 640))
            w.center()
            insightsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        insightsWindow?.makeKeyAndOrderFront(nil)
        insightsWindow?.orderFrontRegardless()
    }

    // Left-click → usage popover. Right/control-click → context menu.
    @objc private func statusClick() {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || (e?.modifierFlags.contains(.control) ?? false) {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        func item(_ title: String, _ sel: Selector?, _ key: String = "", _ symbol: String? = nil) -> NSMenuItem {
            let m = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            if sel != nil { m.target = self }
            if let symbol { m.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            return m
        }
        // Account status line (disabled, informational) - plan + which account.
        let statusTitle: String = {
            guard engine.isSignedIn() else { return "Not signed in" }
            let plan = engine.snapshot.plan.map { "Claude \($0)" } ?? "Signed in"
            if let e = engine.snapshot.accountEmail { return "\(plan) · \(e)" }
            return plan
        }()
        let status = item(statusTitle, nil)
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        // An available update gets one calm row at the top; clicking opens Settings, where the
        // card explains what will happen before anything is downloaded.
        // Menus are always built on the main thread; assumeIsolated makes that explicit to the compiler.
        if let v = MainActor.assumeIsolated({ Updater.shared.pendingVersion }) {
            menu.addItem(item("Update to \(v) available\u{2026}", #selector(openUpdateSettings), "", "arrow.down.circle"))
            menu.addItem(.separator())
        }
        menu.addItem(item(settings.floatingShown ? "Hide Floating Window" : "Show Floating Window",
                          #selector(toggleFloating), "", settings.floatingShown ? "rectangle.slash" : "macwindow.on.rectangle"))
        menu.addItem(item("Refresh Now", #selector(refreshNow), "r", "arrow.clockwise"))
        menu.addItem(item(engine.isSignedIn() ? "Account…" : "Sign in…", #selector(showAccount), "", "person.crop.circle"))
        menu.addItem(item("Settings…", #selector(openSettings), ",", "gearshape"))
        menu.addItem(item("Insights…", #selector(showInsights), "i", "chart.bar.xaxis"))
        menu.addItem(.separator())
        // Demo Mode: synthetic burn so every live surface (flame, charts, tide, popover) can be
        // seen in motion without spending real tokens. Checkmark shows it's on; never persisted.
        let demoItem = item("Demo Mode", #selector(toggleDemo), "", "flame")
        demoItem.state = liveActivity.demo ? .on : .off
        menu.addItem(demoItem)
        // Terminal gauge: live limits rendered inside Claude Code's statusline.
        menu.addItem(item(gaugeInstalled() ? "Remove Terminal Gauge" : "Install Terminal Gauge",
                          #selector(toggleGauge), "", "terminal"))
        menu.addItem(.separator())
        // Help & Feedback: one row that opens onto the guide, the welcome tour, and the two
        // places to reach a human. A submenu so it costs no vertical space until it is wanted.
        let helpItem = item("Help & Feedback", nil, "", "questionmark.circle")
        let helpMenu = NSMenu()
        helpMenu.addItem(item("Read the Guide…", #selector(openGuide), "", "book"))
        helpMenu.addItem(item("Show Welcome Tour…", #selector(showWelcome), "", "sparkles"))
        helpMenu.addItem(.separator())
        helpMenu.addItem(item("Ask a Question…", #selector(openDiscussions), "", "bubble.left.and.bubble.right"))
        helpMenu.addItem(item("Report a Problem…", #selector(openIssues), "", "exclamationmark.bubble"))
        helpItem.submenu = helpMenu
        menu.addItem(helpItem)
        menu.addItem(item("About \(kAppName)", #selector(showAbout), "", "info.circle"))
        menu.addItem(item("Quit \(kAppName)", #selector(quitApp), "q", "power"))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    @objc private func openGuide() {
        NSWorkspace.shared.open(URL(string: "https://burndown-app.pages.dev/guide")!)
    }
    @objc private func openDiscussions() {
        NSWorkspace.shared.open(URL(string: "https://github.com/maz0x/burndown/discussions")!)
    }
    @objc private func openIssues() {
        NSWorkspace.shared.open(URL(string: "https://github.com/maz0x/burndown/issues")!)
    }

    private var aboutWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var keyDismissMonitor: Any?   // Escape / Cmd+W closer for the titled aux windows
    @objc private func showAbout() {
        if aboutWindow == nil {
            let host = NSHostingController(rootView: AboutView())
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable]
            w.title = "About \(kAppName)"
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 300, height: 360))
            w.appearance = themeAppearance()
            w.center()
            aboutWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.makeKeyAndOrderFront(nil)
        aboutWindow?.orderFrontRegardless()
    }

    /// First-run welcome tour. Reopenable from the About window, so it is never a one-shot trap.
    @objc func showWelcome() {
        if welcomeWindow == nil {
            let host = NSHostingController(rootView: WelcomeView(settings: settings, engine: engine,
                                                                 openAccount: { [weak self] in self?.showAccount() }))
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable]
            w.title = "Welcome to \(kAppName)"
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 340, height: 430))
            w.appearance = themeAppearance()
            w.center()
            w.delegate = self
            welcomeWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow?.makeKeyAndOrderFront(nil)
        welcomeWindow?.orderFrontRegardless()
    }

    @objc private func openUpdateSettings() {
        settings.pendingTab = SettingsTab.general.rawValue
        openSettings()
    }

    @objc private func refreshNow() { manualRefresh(); engine.fullScan() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    private func compactTime(_ resetAt: Date?, total: TimeInterval) -> (Double, String) {
        guard let r = resetAt else { return (0, "-") }
        let s = max(0, r.timeIntervalSinceNow)
        let frac = min(1.0, s / total)   // time REMAINING - full now, depletes toward reset
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60
        if h >= 24 { return (frac, "\(h / 24)d\(h % 24)h") }
        if h > 0 { return (frac, "\(h)h\(m)m") }
        return (frac, "\(m)m")
    }

    private func pctStr(_ p: Double) -> String {
        let n = Int((p * 100).rounded())
        return settings.menuNumberFormat == .bare ? "\(n)" : "\(n)%"   // labeled S/W handled in Both mode
    }

    private func updateStatusItem(_ s: UsageSnapshot) {
        guard let button = statusItem.button else { return }
        let mode = settings.colorMode
        // Beacon is exempt from template mode: a template image is tinted wholesale by AppKit, which
        // would erase the wink. It draws the system ink itself (barInk), so "None" still looks native.
        let template = (mode == .system) && settings.menuBarStyle != .beacon
        let accent = NSColor(hex: settings.accentHex) ?? NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
        // In system/template mode draw in black so macOS tints it like a native icon.
        func usageCol(_ pct: Double, _ over: Bool) -> NSColor {
            template ? .black : usageNSColor(pct: pct, over: over, accent: accent, mode: mode)
        }
        let sec: NSColor = template ? .black : secondaryNSColor(accent: accent, mode: mode)
        var g: GlyphData
        switch settings.menuBarShow {
        case .session:
            let (frac, text) = compactTime(s.sessionResetAt, total: 5 * 3600)
            g = GlyphData(pct: s.sessionPct, pctText: pctStr(s.sessionPct), primary: usageCol(s.sessionPct, s.over),
                          secFrac: frac, secText: text, secondary: sec, pLabel: "", sLabel: "")
        case .weekly:
            let (frac, text) = compactTime(s.weeklyResetAt, total: 7 * 24 * 3600)
            g = GlyphData(pct: s.weeklyPct, pctText: pctStr(s.weeklyPct), primary: usageCol(s.weeklyPct, s.weeklyOver),
                          secFrac: frac, secText: text, secondary: sec, pLabel: "", sLabel: "")
        case .both:
            // Weekly shares the usage color family (matches the popover's weekly), so the
            // menu bar doesn't introduce a foreign hue - distinguished by shape, not color.
            let wcol = usageCol(s.weeklyPct, s.weeklyOver)
            g = GlyphData(pct: s.sessionPct, pctText: pctStr(s.sessionPct), primary: usageCol(s.sessionPct, s.over),
                          secFrac: s.weeklyPct, secText: pctStr(s.weeklyPct), secondary: wcol,
                          pLabel: "S", sLabel: "W")
        }
        g.hasSecondary = (settings.menuBarShow == .both)
        g.digitWeight = settings.menuBoldDigits ? .semibold : .regular      // Semibold / Regular
        g.smolderIntensity = settings.smolderIntensity
        g.smolderBreathSlow = settings.smolderBreathSlow
        g.smolderWarmthWander = settings.smolderWarmthWander
        g.flameSize = settings.flameSize        // FLAME ADJUST
        g.flameSparks = settings.flameSparks
        g.flameSmoke = settings.flameSmoke
        if !settings.menuShowPct, settings.menuBarStyle == .flame { g.pctText = "" }   // area 2: flame-only
        // Time to reset (fire family only): append a short mono countdown, capped at 5 chars.
        if settings.menuTimeToReset, [.smolder, .burnfront, .kiln, .flame].contains(settings.menuBarStyle) {
            let (_, t) = compactTime(s.sessionResetAt, total: 5 * 3600)
            if !t.isEmpty { g.pctText += " " + String(t.prefix(5)) }
        }
        if let r = s.weeklyResetAt { g.weekLeftText = weekLeftString(r) }   // for the weeklyClock style
        // Live fields for the animated styles (pulse / pace / burn / roll).
        g.costText = money(s.sessionCost)
        g.tokText = "≈" + fmtTok(s.sessionFresh)
        g.needle = displayNeedle
        g.active = liveActivity.active
        g.rollFrom = rollFrom
        g.rollPhase = rollPhase
        g.spark = liveActivity.history
        g.phase = animPhase          // BurnClock.elapsed: monotonic seconds, what every fire Hz samples
        g.tier = burnClock.tier      // fire tiers ARE the BurnClock tiers
        g.heat = displayHeat         // tier.heat, lerped at 0.06/frame (~1.1s settle)
        // Beacon winks to the theme accent - or, with "By usage" on, to its own usage ramp: a warm
        // accent deepens toward rust as you approach the cap; a cool one jumps to the warm scale
        // (amber -> rust) instead of blending through mud. The COLOUR carries the reading.
        g.accent = settings.beaconUsageColor
            ? beaconUsageNSColor(pct: settings.menuBarShow == .weekly ? s.weeklyPct : s.sessionPct,
                                 over: settings.menuBarShow == .weekly ? s.weeklyOver : s.over,
                                 accent: accent)
            : accent
        g.beacon = beaconEnv
        g.beaconMark = settings.beaconMark
        g.beaconGlow = settings.beaconGlow
        // Refresh flare: 1 right after a fetch cycle starts, fading over ~0.9s (drawn by flame).
        g.flare = max(0, 1 - Date().timeIntervalSince(engine.refreshAnchor) / 0.9)
        // Heat: 0 below 85%, ramping to 1 at the cap (over = full). Drives the flame's rage
        // and the Redline state. Keyed to whichever metric the menu bar is showing.
        func heat(_ p: Double, _ over: Bool) -> Double { over ? 1 : max(0, (min(1, p) - 0.85) / 0.15) }
        switch settings.menuBarShow {
        case .session: g.redline = heat(s.sessionPct, s.over)
        case .weekly:  g.redline = heat(s.weeklyPct, s.weeklyOver)
        case .both:    g.redline = max(heat(s.sessionPct, s.over), heat(s.weeklyPct, s.weeklyOver))
        }
        // Brand-new install with nothing to show: a quiet "--" instead of a burning "0%", so the
        // glyph never claims a live zero it cannot know. Any real data (an estimate
        // from local logs counts) flips it back to numbers.
        if !engine.isSignedIn(), s.sessionPct == 0, s.weeklyPct == 0, !liveActivity.active {
            g.pctText = settings.menuBarStyle == .flame ? "" : "--"
            button.toolTip = "Burndown: nothing to measure yet. Click to connect or just start using Claude."
        } else {
            button.toolTip = nil
        }
        let img = MenuBarRenderer.image(style: settings.menuBarStyle, g, template: template)
        // Template mode ("None" colour) needs AppKit's automatic menu-bar tinting, which only happens
        // via button.image - it is a static, rarely-updating style, so the layout cost is irrelevant
        // there. Every other style takes the fast CA path.
        if template {
            if glyphLayer?.contents != nil { glyphLayer?.contents = nil }
            button.image = img
            return
        }
        if button.image != nil { button.image = nil }
        // Reserve the width via statusItem.length ONLY when it actually changes (this is the part that
        // legitimately needs layout); the per-frame path below touches nothing but layer contents.
        if abs(statusItem.length - img.size.width) > 0.5 { statusItem.length = img.size.width }
        if let l = glyphLayer {
            let scale = button.window?.backingScaleFactor ?? 2
            let r = NSRect(x: (button.bounds.width - img.size.width) / 2,
                           y: (button.bounds.height - img.size.height) / 2,
                           width: img.size.width, height: img.size.height)
            if l.frame != r { l.frame = r }
            if l.contentsScale != scale { l.contentsScale = scale }
            var pr = NSRect(origin: .zero, size: img.size)
            l.contents = img.cgImage(forProposedRect: &pr, context: nil, hints: nil)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            // Activate so Core Animation runs the popover at full frame rate
            // (accessory apps get throttled animations when inactive).
            NSApp.activate(ignoringOtherApps: true)
            if popover.contentViewController == nil { popover.contentViewController = makePopoverHost() }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            if let win = popover.contentViewController?.view.window {
                win.contentView?.wantsLayer = true
                win.contentView?.layer?.shouldRasterize = false
                win.alphaValue = settings.windowOpacity
                win.isOpaque = false; win.backgroundColor = .clear   // glass is always on; let the desktop show through
            }
        }
    }

    // MARK: - Login item
    // SMAppService registers the app bundle by identity, so it survives the app being moved,
    // renamed, or translocated (the raw-plist approach captured the executable path at toggle
    // time and silently broke in all three cases). The legacy plist is still honored
    // as "installed" and removed on toggle-off, and remains the fallback if registration fails
    // (e.g. an unsigned dev build in an unusual location).

    private var loginPlist: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.maz.burndown.plist")
    }
    private func isLoginInstalled() -> Bool {
        if SMAppService.mainApp.status == .enabled { return true }
        return FileManager.default.fileExists(atPath: loginPlist.path)
    }
    private func setLogin(_ on: Bool) {
        if on {
            do { try SMAppService.mainApp.register() }
            catch {
                // Fall back to the legacy LaunchAgent so the toggle still works for dev builds.
                let bin = Bundle.main.executablePath ?? ""
                let xml = """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0"><dict>
                  <key>Label</key><string>com.maz.burndown</string>
                  <key>ProgramArguments</key><array><string>\(bin)</string></array>
                  <key>RunAtLoad</key><true/><key>KeepAlive</key><false/>
                  <key>ProcessType</key><string>Interactive</string>
                </dict></plist>
                """
                try? xml.write(to: loginPlist, atomically: true, encoding: .utf8)
            }
        } else {
            try? SMAppService.mainApp.unregister()
            // Only delete a LaunchAgent that is actually OURS: one whose ProgramArguments point at
            // this bundle. Never remove a hand-managed or third-party agent that happens to share
            // the label, and never leave the user with no login item they did not ask to lose.
            if let d = try? Data(contentsOf: loginPlist),
               let plist = try? PropertyListSerialization.propertyList(from: d, options: [], format: nil) as? [String: Any],
               let args = plist["ProgramArguments"] as? [String],
               let first = args.first,
               first == (Bundle.main.executablePath ?? "") {
                try? FileManager.default.removeItem(at: loginPlist)
            }
        }
    }

    private func openLogs() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/burndown")
        NSWorkspace.shared.open(dir)
        popover.performClose(nil)
    }

    // Settings → Charts & Data → Reset: clear stored chart history + truncate the diagnostic log.
    private func resetData() {
        liveActivity.resetHistory()
        let log = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/burndown/live-debug.log")
        try? "".write(to: log, atomically: true, encoding: .utf8)
    }

    // MARK: - Wiring

    private func bind() {
        engine.$snapshot.receive(on: RunLoop.main)
            .sink { [weak self] s in
                guard let self else { return }
                // Detect a change in the live token figure → kick the odometer roll.
                let t = "≈" + fmtTok(s.sessionFresh)
                if !self.lastTokText.isEmpty && t != self.lastTokText {
                    self.rollFrom = self.lastTokText; self.rollPhase = 0
                }
                self.lastTokText = t
                self.ensureAnimating()
                // For LIVE styles the animator is the sole glyph renderer (setImage recomposites the
                // menu bar, so double-rendering from here + the animator was pinning a core). Static
                // styles have no animator, so they must render on data change.
                if !self.settings.menuBarStyle.isLive { self.updateStatusItem(s) }
                self.updateTideLine()   // data changed (~2s cadence): repaint the static remaining-fill
                if self.settings.alertsEnabled {
                    self.alerts.enable()   // idempotent; prompts for permission the first time
                    self.alerts.check(session: s.sessionPct, weekly: s.weeklyPct,
                                      opus: s.apiOpus?.pct, sonnet: s.apiSonnet?.pct,
                                      sessionReset: s.sessionResetAt, weeklyReset: s.weeklyResetAt,
                                      burn: self.liveActivity.rate,
                                      forecastMin: forecastMinutes(self.liveActivity.usageSamples, current: s.sessionPct, resetAt: s.sessionResetAt),
                                      topChat: self.liveActivity.activeStreams.max(by: { $0.tok < $1.tok })?.name,
                                      s: self.settings)
                    self.alerts.checkBudgetRunaway(burn: self.liveActivity.rate,
                                                   records: self.engine.records, s: self.settings)
                    self.alerts.checkWeeklyDigest(records: self.engine.records, s: self.settings)
                }
            }.store(in: &cancellables)

        // Live token flow: redraw (sparkline / idle needle), keep the animator alive,
        // nudge a quick local rescan, and switch to the fast cadence while active.
        liveActivity.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.ensureAnimating()
                    // Live styles render via the animator only (see above); do not also setImage here.
                    if !self.settings.menuBarStyle.isLive { self.updateStatusItem(self.engine.snapshot) }
                    if self.liveActivity.active != self.activeRefresh {
                        self.activeRefresh = self.liveActivity.active
                        // Tokens just started → speed up immediately (don't wait out a long idle tick).
                        if self.liveActivity.active && self.settings.smartRefresh {
                            self.liveInterval = min(self.activePeriod, Double(self.settings.refreshSeconds))
                            self.scheduleLive()
                        }
                    }
                    // (No quickRefresh here: the live loop already refreshes on its own cadence, and
                    // re-scanning the logs on every token-flow tick was redundant CPU.)
                }
            }.store(in: &cancellables)

        // Re-render the menu bar when any setting changes. objectWillChange fires
        // BEFORE the value updates, so defer to the next runloop to read the new value.
        settings.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.applyTheme()
                    self.ensureAnimating()
                    self.updateStatusItem(self.engine.snapshot)
                }
            }
            .store(in: &cancellables)

        settings.$usageAPI.receive(on: RunLoop.main)
            .sink { [weak self] on in
                guard let self else { return }
                self.engine.usageEnabled = on
                if on { self.engine.fetchLive(force: true) }   // opted in: fetch right away
            }.store(in: &cancellables)

        settings.$refreshSeconds.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rescheduleTimers() }.store(in: &cancellables)

        // Day span drives how deep the record scan reaches; growing it triggers a deep scan so the
        // longer charts fill in right away instead of waiting for the next 10-minute pass.
        settings.$chartDays.receive(on: RunLoop.main)
            .sink { [weak self] days in
                guard let self else { return }
                let grew = days > self.engine.recordDays
                self.engine.recordDays = days
                if grew { self.engine.fullScan() }
            }.store(in: &cancellables)

        settings.$smartRefresh.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rescheduleTimers() }.store(in: &cancellables)

        settings.$floatingShown.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncFloating() }.store(in: &cancellables)

        settings.$floatingChrome.receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.settings.floatingShown else { return }
                let old = self.floatingPanel; self.floatingPanel = nil; old?.close(); self.showFloating()
            }.store(in: &cancellables)

        settings.$pinnedOnTop.receive(on: RunLoop.main)
            .sink { [weak self] on in self?.floatingPanel?.level = on ? .floating : .normal }.store(in: &cancellables)

        settings.$dockEdge.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncEdgeDock() }.store(in: &cancellables)

        settings.$tideLine.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncTideLine() }.store(in: &cancellables)

        settings.$tideEdge.receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildTidePanels(); self?.updateTidePeek() }.store(in: &cancellables)

        // Ember Line style / flames / glow: apply live.
        settings.$tideStyle.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateTideLine() }.store(in: &cancellables)
        settings.$tideFlames.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateTideLine() }.store(in: &cancellables)
        settings.$tideGlow.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateTideLine() }.store(in: &cancellables)
        settings.$tideThickness.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateTideLine() }.store(in: &cancellables)
        settings.$tideSparks.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateTideLine() }.store(in: &cancellables)
        settings.$tideSmoke.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateTideLine() }.store(in: &cancellables)
        settings.$tideLength.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateTideLine() }.store(in: &cancellables)
        settings.$tideOpacity.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateTideLine() }.store(in: &cancellables)
        settings.$tideDisplays.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateTideLine() }.store(in: &cancellables)
        settings.$tidePeek.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateTidePeek() }.store(in: &cancellables)

        settings.$windowOpacity.receive(on: RunLoop.main)
            .sink { [weak self] v in self?.applyWindowOpacity(v) }.store(in: &cancellables)
    }

    // Apply the overall window-transparency slider to every translucent surface, live.
    private func applyWindowOpacity(_ v: Double) {
        let a = CGFloat(max(0.1, min(1, v)))
        popover.contentViewController?.view.window?.alphaValue = a
        floatingPanel?.alphaValue = a
        edgePanel?.alphaValue = a
    }

    // The animator is a SELF-RESCHEDULING timer whose rate adapts to what is actually moving, so idle
    // costs almost nothing. A fixed 30fps loop was the app's whole idle CPU: the idle fire breath is a
    // 0.12-0.20 Hz wave (a 5-8s cycle) that looks identical sampled at 2fps. So idle ticks at 2fps,
    // ramping up only while tokens flow or a value is settling, and stopping entirely when a
    // non-breathing style has nothing left to move.
    private func ensureAnimating() {
        if settings.menuBarStyle.isLive || settings.tideLine {
            if animTimer == nil { lastAnimUptime = ProcessInfo.processInfo.systemUptime; scheduleAnimTick(0.03) }
        } else {
            animTimer?.invalidate(); animTimer = nil
            displayNeedle = 0; rollPhase = 1
        }
    }

    private func scheduleAnimTick(_ delay: TimeInterval) {
        animTimer?.invalidate()
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.animFrame() }
        RunLoop.main.add(t, forMode: .common); animTimer = t
    }

    private func animFrame() {
        // Real elapsed time since the last tick, so motion is identical at any tick rate.
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.75, max(0.001, now - lastAnimUptime))
        lastAnimUptime = now
        let frames = dt * 30                                         // "how many 30fps frames' worth"
        animPhase += dt                                             // BurnClock.elapsed: real seconds
        let bs = engine.snapshot
        burnClock.elapsed = animPhase
        burnClock.retier(usage: bs.sessionPct, over: bs.over, burnRatio: displayNeedle * 2,
                         threshold: settings.alertSessionAt, tokensFlowing: liveActivity.active)
        // Frame-rate-independent easing (matches the old per-frame constants at 30fps).
        let target = liveActivity.active ? liveActivity.norm : 0.0   // needle falls to rest when idle
        displayNeedle += (target - displayNeedle) * (1 - pow(0.82, frames))   // was 0.18/frame
        if abs(target - displayNeedle) < 0.004 { displayNeedle = target }
        let heatTarget = burnClock.tier.heat                         // ~1.1s settle
        displayHeat += (heatTarget - displayHeat) * (1 - pow(0.94, frames))   // was 0.06/frame
        if abs(heatTarget - displayHeat) < 0.002 { displayHeat = heatTarget }
        if rollPhase < 1 { rollPhase = min(1, rollPhase + 0.07 * frames) }
        // Beacon: advance the wink clock exactly once per frame. Every knob is read live, so dragging a
        // slider in Settings changes the next wink (and the current one's shape) with no restart.
        // "Follows burn": the gap itself becomes the signal - up to 4x faster at full token rate, back to
        // your setting when nothing is flowing. The rhythm tells you Claude is working without you reading
        // a number. (displayNeedle is the eased live rate the other live styles already ride.)
        let every = settings.beaconFollowsBurn ? settings.beaconEvery / (1 + 3 * max(0, min(1, displayNeedle)))
                                               : settings.beaconEvery
        // "Double-wink near the limit": the shape carries the warning, so a glance is enough.
        let hot = bs.over || bs.sessionPct >= settings.alertSessionAt
        let curve: BeaconCurve = (settings.beaconAlertBeat && hot) ? .beat : settings.beaconCurve
        beaconEnv = beaconClock.envelope(at: animPhase, every: every, jitter: settings.beaconJitter,
                                         length: settings.beaconLength, curve: curve)
            * max(0, min(1, settings.beaconStrength))

        // The tick RATE is the frame rate now, so render the (small, cheap) glyph every tick - EXCEPT for
        // Beacon, whose glyph is bit-identical between winks. Every input it draws from is in the key
        // below, so an unchanged key means an unchanged image, and recompositing the menu bar 10x a
        // second for the same pixels is the whole idle cost of a breathing style. (Anything NOT in this
        // key must not be able to change the Beacon glyph.)
        var skipGlyph = false
        if settings.menuBarStyle == .beacon {
            let key = [String(Int((beaconEnv * 512).rounded())), String(Int((bs.sessionPct * 1e4).rounded())),
                       String(Int((bs.weeklyPct * 1e4).rounded())), settings.accentHex,
                       settings.menuBarShow.rawValue, settings.menuNumberFormat.rawValue,
                       settings.menuBoldDigits ? "b" : "r",
                       // Sign-in only reaches the glyph through the "--" placeholder, which needs both
                       // metrics at zero. Guarding it keeps isSignedIn() (not free) off the 10fps path.
                       (bs.sessionPct == 0 && bs.weeklyPct == 0) ? (engine.isSignedIn() ? "in" : "out") : "-",
                       liveActivity.active ? "live" : "idle",
                       settings.beaconMark.rawValue, String(Int(settings.beaconGlow * 100)),
                       settings.beaconUsageColor ? "u" : "a",
                       NSApp.effectiveAppearance.name.rawValue].joined(separator: "|")
            skipGlyph = (key == lastBeaconKey)
            lastBeaconKey = key
        }
        if !skipGlyph { updateStatusItem(bs) }
        // The Ember Line breath. Its own motion is slow (flame sway ~0.32 Hz, breath on the tier
        // period), so 10fps is ~30 samples/cycle - continuous to the eye. It invalidates ONLY the
        // burn-front strip; the static remaining-fill repaints on the ~2s data-change sink.
        if settings.tideLine, now - lastTideUptime >= 1.0 / 10.0 {
            lastTideUptime = now
            let tidePhase = animPhase - 0.25 * burnClock.period   // the one sanctioned 0.25 lag
            for p in tidePanels { (p.contentView as? TideLineView)?.advanceBreath(phase: tidePhase, period: burnClock.period) }
        }

        // Pick the next interval from what is moving. Fully settled + nothing that breathes → STOP.
        let settled = !liveActivity.active && displayNeedle == target && rollPhase >= 1
            && abs(heatTarget - displayHeat) < 0.002
        let breathes = settings.menuBarStyle.burnsIdle || settings.tideLine
        if settled && !breathes { animTimer?.invalidate(); animTimer = nil; return }
        // Rate DERIVED from the motion (BurnTier.renderFPS = ~14x the tier's fastest Hz, clamped
        // 10...30). Idle sways at 0.20 Hz with a sub-pixel excursion, so 10fps is already continuous
        // to the eye; a 2.4 Hz redline flick gets the full 30. Smooth everywhere, wasteful nowhere.
        // (A glyph rebuild is ~90us - see CUB_BENCH - so even 30fps is ~0.3%.)
        // A wink is over in under half a second, so sample it at the full rate whatever the tier says -
        // at the idle 10fps the ramp would land in 4 frames and read as a stutter, not a blink.
        let winking = animPhase - beaconClock.firedAt < beaconClock.length + 0.05
        let fps = (settings.menuBarStyle == .beacon && winking) ? 30 : burnClock.tier.renderFPS
        scheduleAnimTick(1.0 / fps)
    }

    // Smart refresh = gradual backoff: snap to the fast cadence the moment tokens flow,
    // then ramp the interval back up (2s → ~3 → 5 → 8 … → your chosen interval) as things
    // stay quiet - so we update live when it matters but don't keep hitting the usage
    // endpoint when nothing's happening. Smart off = the fixed interval, always.
    // (The OAuth usage fetch is also self-throttled to ≥20s, so the server is never hit
    // faster than that even at a 2s UI cadence.)
    private func nextLiveInterval() -> Double {
        let base = Double(settings.refreshSeconds)
        if !settings.smartRefresh { return base }
        if liveActivity.active { return min(activePeriod, base) }   // burning → fast
        return min(base, max(activePeriod, liveInterval * 1.6))     // quiet → ramp toward base
    }

    private func scheduleLive() {
        liveTimer?.invalidate()
        engine.refreshPeriod = liveInterval
        engine.refreshAnchor = Date()              // restart the LIVE countdown/fill
        let t = Timer(timeInterval: max(1, liveInterval), repeats: false) { [weak self] _ in self?.liveTick() }
        RunLoop.main.add(t, forMode: .common); liveTimer = t
    }

    private func liveTick() {
        engine.fetchLive()                         // OAuth % (self-throttled to ≥20s)
        engine.refreshAPISpend()                   // developer-API spend (self-throttled to ≥5m; no-op if no key)
        engine.quickRefresh()                      // local burn / tokens / cost (cheap)
        liveActivity.recordBurn()                  // one Burn point per refresh
        liveActivity.recordUsage(session: engine.snapshot.sessionPct, weekly: engine.snapshot.weeklyPct)   // Usage point (self-throttled to ~1/min)
        liveInterval = nextLiveInterval()          // gradual backoff
        scheduleLive()
    }

    private func rescheduleTimers() {
        fullTimer?.invalidate()
        liveInterval = settings.smartRefresh
            ? (liveActivity.active ? min(activePeriod, Double(settings.refreshSeconds)) : Double(settings.refreshSeconds))
            : Double(settings.refreshSeconds)
        scheduleLive()
        let full = Timer(timeInterval: 600, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.engine.fullScan()
            let auto = self.settings.autoUpdateCheck
            DispatchQueue.main.async { Updater.shared.checkInBackgroundIfDue(enabled: auto) }
        }
        RunLoop.main.add(full, forMode: .common); fullTimer = full
    }

    // LIVE pressed → force a refresh and restart the cycle immediately.
    private func manualRefresh() {
        engine.fetchLive(force: true)
        engine.quickRefresh()
        liveActivity.recordBurn()                  // a manual refresh adds a Burn point too
        liveActivity.recordUsage(session: engine.snapshot.sessionPct, weekly: engine.snapshot.weeklyPct)
        rescheduleTimers()
    }
}

// QA: diagnose notification delivery (auth status + request + add errors), then exit.
if ProcessInfo.processInfo.environment["CUB_NOTIFTEST"] != nil {
    let c = UNUserNotificationCenter.current()
    c.getNotificationSettings { s in
        print("authStatus=\(s.authorizationStatus.rawValue)  (0=notDetermined 1=denied 2=authorized 3=provisional)")
        c.requestAuthorization(options: [.alert, .sound]) { ok, err in
            print("requestAuthorization ok=\(ok) err=\(err.map { String(describing: $0) } ?? "nil")")
            let n = UNMutableNotificationContent(); n.title = "Burndown test"; n.body = "diagnostic"; n.sound = .default
            c.add(UNNotificationRequest(identifier: UUID().uuidString, content: n, trigger: nil)) { e in
                print("add err=\(e.map { String(describing: $0) } ?? "nil")")
            }
        }
    }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 4))
    exit(0)
}

// QA: render the style sheet and exit, when asked.
if let flamePath = ProcessInfo.processInfo.environment["CUB_SNAP_FLAME"] {
    StyleSheet.renderFlames(to: flamePath)
    exit(0)
}
if let burnPath = ProcessInfo.processInfo.environment["CUB_SNAP_BURN"] {
    StyleSheet.renderBurners(to: burnPath)
    exit(0)
}
if ProcessInfo.processInfo.environment["CUB_BEACON_DIAG"] != nil {
    StyleSheet.beaconDiag()
    exit(0)
}
if let beaconPath = ProcessInfo.processInfo.environment["CUB_SNAP_BEACON"] {
    StyleSheet.renderBeacon(to: beaconPath)
    exit(0)
}
if let fs = ProcessInfo.processInfo.environment["CUB_SNAP_FLAMESIZE"] {
    StyleSheet.renderFlameSizes(to: fs)
    exit(0)
}
if ProcessInfo.processInfo.environment["CUB_BENCH"] != nil {
    StyleSheet.bench()
    exit(0)
}
if ProcessInfo.processInfo.environment["CUB_SCAN_SELFTEST"] != nil {
    print(UsageEngine.scanSelfTest())
    exit(0)
}
if ProcessInfo.processInfo.environment["CUB_MOTION_DIAG"] != nil {
    StyleSheet.motionDiag()
    exit(0)
}
if let solo = ProcessInfo.processInfo.environment["CUB_SNAP_SOLO"],
   let out = ProcessInfo.processInfo.environment["CUB_SOLO_OUT"] {
    MainActor.assumeIsolated { StyleSheet.renderSolo(solo, to: out) }
    exit(0)
}
if let tidePath = ProcessInfo.processInfo.environment["CUB_SNAP_TIDE"] {
    MainActor.assumeIsolated { StyleSheet.renderTide(to: tidePath) }
    exit(0)
}
if let aboutPath = ProcessInfo.processInfo.environment["CUB_SNAP_ABOUT"] {
    MainActor.assumeIsolated { StyleSheet.renderAbout(to: aboutPath, dark: ProcessInfo.processInfo.environment["CUB_DARK"] != nil) }
    exit(0)
}
if ProcessInfo.processInfo.environment["CUB_TIDE_DIAG"] != nil {
    // Verify per-screen edge geometry: for every display, print its frame and the tide-line
    // frame for each edge, so we can confirm full-span + flush-to-edge across multiple screens.
    let t = kTideThick
    for (i, s) in NSScreen.screens.enumerated() {
        let f = s.frame
        print("screen[\(i)] frame = \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))")
        print("   top    = \(Int(f.minX)),\(Int(f.maxY - t)) \(Int(f.width))x\(Int(t))  (spans full width, flush to very top)")
        print("   bottom = \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(t))")
        print("   left   = \(Int(f.minX)),\(Int(f.minY)) \(Int(t))x\(Int(f.height))  (spans full height)")
        print("   right  = \(Int(f.maxX - t)),\(Int(f.minY)) \(Int(t))x\(Int(f.height))")
    }
    exit(0)
}
if let snapPath = ProcessInfo.processInfo.environment["CUB_SNAP"] {
    StyleSheet.render(to: snapPath)
    exit(0)
}
// One menu-bar glyph on transparency, so the hero composite can show the icon sitting in a real
// menu bar. CUB_SNAP_GLYPH=/path.png [CUB_GLYPH_STYLE=smolder].
if let gPath = ProcessInfo.processInfo.environment["CUB_SNAP_GLYPH"] {
    let style = MenuBarStyle(rawValue: ProcessInfo.processInfo.environment["CUB_GLYPH_STYLE"] ?? "") ?? .smolder
    StyleSheet.renderGlyph(style, to: gPath)
    exit(0)
}
if let popPath = ProcessInfo.processInfo.environment["CUB_SNAP_POP"] {
    MainActor.assumeIsolated { StyleSheet.renderPopover(to: popPath, dark: ProcessInfo.processInfo.environment["CUB_DARK"] != nil) }
    exit(0)
}
if let wPath = ProcessInfo.processInfo.environment["CUB_SNAP_WIDGET"] {
    MainActor.assumeIsolated { StyleSheet.renderWidget(to: wPath, dark: ProcessInfo.processInfo.environment["CUB_DARK"] != nil) }
    exit(0)
}
if let iPath = ProcessInfo.processInfo.environment["CUB_SNAP_INSIGHTS"] {
    MainActor.assumeIsolated { StyleSheet.renderInsights(to: iPath, dark: ProcessInfo.processInfo.environment["CUB_DARK"] != nil) }
    exit(0)
}
if let aPath = ProcessInfo.processInfo.environment["CUB_SNAP_ACCOUNT"] {
    MainActor.assumeIsolated { StyleSheet.renderAccount(to: aPath, dark: ProcessInfo.processInfo.environment["CUB_DARK"] != nil) }
    exit(0)
}
if let sPath = ProcessInfo.processInfo.environment["CUB_SNAP_SETTINGS"] {
    MainActor.assumeIsolated { StyleSheet.renderSettings(to: sPath, dark: ProcessInfo.processInfo.environment["CUB_DARK"] != nil) }
    exit(0)
}
if let cPath = ProcessInfo.processInfo.environment["CUB_SNAP_CHARTS"] {
    MainActor.assumeIsolated { StyleSheet.renderChartSheet(to: cPath, dark: ProcessInfo.processInfo.environment["CUB_DARK"] != nil,
                                                           usage: ProcessInfo.processInfo.environment["CUB_USAGE"] != nil) }
    exit(0)
}
if let wsPath = ProcessInfo.processInfo.environment["CUB_SNAP_WIDGETS"] {
    MainActor.assumeIsolated { StyleSheet.renderWidgetSheet(to: wsPath, dark: ProcessInfo.processInfo.environment["CUB_DARK"] != nil,
                                                            horizontal: ProcessInfo.processInfo.environment["CUB_HORIZ"] != nil) }
    exit(0)
}
if let wPath = ProcessInfo.processInfo.environment["CUB_SNAP_WELCOME"] {
    // QA: render all four welcome-tour pages side by side (CUB_DARK=1 for dark).
    MainActor.assumeIsolated {
        let dark = ProcessInfo.processInfo.environment["CUB_DARK"] != nil
        let settings = StyleSheet.qaSettings()
        let view = HStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { i in
                WelcomeView(settings: settings, engine: UsageEngine(), openAccount: {}, initialPage: i)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black.opacity(0.15)))
            }
        }
        .padding(14)
        .background(dark ? Color.black.opacity(0.9) : Color(white: 0.93))
        .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: wPath))
        }
    }
    exit(0)
}
if ProcessInfo.processInfo.environment["CUB_COST"] != nil {
    UsageEngine().cliDump()
    exit(0)
}
// Troubleshooting flag for the docked widget: prints the frontmost app, the persisted
// dockEdge, and every on-screen window owned by Claude Desktop (pid/layer/bounds), so a
// user can report whether window detection, which drives placement, finds Claude's window.
if ProcessInfo.processInfo.environment["CUB_EDGE"] != nil {
    let bundleID = "com.anthropic.claudefordesktop"
    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
    print("frontmost:", front)
    print("dockEdge setting:", UserDefaults.standard.string(forKey: "dockEdge") ?? "(unset → off)")
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    print("claude instances:", apps.count)
    guard let app = apps.first(where: { !$0.isTerminated }) else { print("→ no running Claude app found"); exit(0) }
    let pid = Int(app.processIdentifier)
    print("claude pid:", pid, "active:", app.isActive)
    // ALL windows (every Space, on and off screen) so we can see windows even when Claude
    // is in the background, and whether they belong to the main pid or an Electron helper.
    let infos = (CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
    print("windows total (all spaces):", infos.count)
    var owned = 0, qualified = 0, claudeNamed = 0
    for w in infos {
        let wpid = w[kCGWindowOwnerPID as String] as? Int ?? -1
        let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
        let byMain = wpid == pid
        let byName = owner.lowercased().contains("claude")
        guard byMain || byName else { continue }
        if byMain { owned += 1 }
        if byName { claudeNamed += 1 }
        let layer = w[kCGWindowLayer as String] as? Int ?? -999
        let onScreen = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
        var dims = "?"; var big = false
        if let bd = w[kCGWindowBounds as String] as? NSDictionary, let cg = CGRect(dictionaryRepresentation: bd as CFDictionary) {
            dims = "\(Int(cg.minX)),\(Int(cg.minY)) \(Int(cg.width))x\(Int(cg.height))"
            big = cg.width > 200 && cg.height > 200
        }
        if byMain && layer == 0 && big { qualified += 1 }
        print("  owner='\(owner)' pid=\(wpid) byMainPid=\(byMain) layer=\(layer) onScreen=\(onScreen) bounds=\(dims) big=\(big)")
    }
    print("windows owned by Claude MAIN pid:", owned, "→ qualifying:", qualified, "| windows named Claude (any pid):", claudeNamed)
    // Is the LIVE app (login-agent instance) actually placing the edge panel right now?
    if let me = NSRunningApplication.runningApplications(withBundleIdentifier: "com.maz.burndown")
        .first(where: { !$0.isTerminated && Int($0.processIdentifier) != Int(ProcessInfo.processInfo.processIdentifier) }) {
        let mpid = Int(me.processIdentifier)
        let mine = infos.filter { ($0[kCGWindowOwnerPID as String] as? Int) == mpid }
        print("our LIVE app pid:", mpid, "→ windows:", mine.count)
        for w in mine {
            let layer = w[kCGWindowLayer as String] as? Int ?? -999
            let onScreen = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
            var dims = "?"
            if let bd = w[kCGWindowBounds as String] as? NSDictionary, let cg = CGRect(dictionaryRepresentation: bd as CFDictionary) {
                dims = "\(Int(cg.minX)),\(Int(cg.minY)) \(Int(cg.width))x\(Int(cg.height))"
            }
            let num = w[kCGWindowNumber as String] as? Int ?? -1
            print("  ours: winid=\(num) layer=\(layer) onScreen=\(onScreen) bounds=\(dims)")
        }
    } else { print("our LIVE app: not found running") }
    print("screens:")
    for s in NSScreen.screens { print("  frame=\(s.frame) isPrimary(origin0)=\(s.frame.origin == .zero)") }
    if let r = claudeDockWindowRect(bundleID: bundleID) {
        let onScr = NSScreen.screens.contains { !$0.frame.intersection(r).isNull }
        print("→ claudeDockWindowRect picked (AppKit):", r, "| on a screen:", onScr)
        // Replicate the right-edge placement + clamp exactly, to see what the live app computes.
        let w: CGFloat = 70, h: CGFloat = 159, pad: CGFloat = 14
        let y = r.midY - h / 2
        let outside = r.maxX - pad, inside = r.maxX - w + pad
        let outOnScreen = NSScreen.screens.contains { $0.frame.contains(NSPoint(x: outside + w / 2, y: y + h / 2)) }
        let ox = outOnScreen ? outside : inside
        let placed = clampToScreen(NSRect(x: ox, y: y, width: w, height: h), near: NSPoint(x: r.maxX, y: r.midY))
        print("→ REPLICATED right placement origin:", placed.origin, "| pre-clamp x:", ox, "| win.maxX:", r.maxX)
    } else {
        print("→ claudeDockWindowRect returned nil (no visible window) → widget hidden")
    }
    exit(0)
}

// Local JSON API: `Burndown --json` prints the live numbers in a stable, versioned
// shape (BurndownLive) read from the live cache, then exits. Lets Raycast / Stream Deck / scripts /
// custom statuslines consume Burndown without the UI.
if CommandLine.arguments.contains("--json") {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let cacheURL = home.appendingPathComponent(".config/burndown/live.json")
    let root = ((try? Data(contentsOf: cacheURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any]
    func win(_ key: String) -> [String: Any]? { root?[key] as? [String: Any] }
    func pct(_ key: String) -> Double? { (win(key)?["utilization"] as? Double).map { min(1.0, max(0.0, $0 / 100.0)) } }
    func reset(_ key: String) -> String? { win(key)?["resets_at"] as? String }
    let live = BurndownLive(
        schemaVersion: 1,
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        plan: root?["plan"] as? String,
        sessionPct: pct("five_hour") ?? 0,
        weeklyPct: pct("seven_day") ?? 0,
        opusPct: pct("seven_day_opus"),
        sonnetPct: pct("seven_day_sonnet"),
        sessionResetAt: reset("five_hour"),
        weeklyResetAt: reset("seven_day"),
        // A cold read of the cache cannot know a live rate or an in-flight session cost.
        // Null is the contract's "unknown"; the running app writes both into
        // ~/.config/burndown/burndown-live.json, which is what statuslines read.
        burnPerMin: nil,
        sessionCost: nil
    )
    print(encodeBurndownLive(live))
    exit(0)
}

// QA: `Burndown --sessions` prints the biggest chats (by title), to verify attribution labels.
if CommandLine.arguments.contains("--sessions") {
    let (_, sessions) = UsageEngine().scanFilesSync()
    for s in sessions.sorted(by: { $0.tokens > $1.tokens }).prefix(15) {
        print(String(format: "%14d  $%9.2f  [%@]  %@", s.tokens, s.cost, s.project, s.title))
    }
    exit(0)
}

// An accessory app has no UI state worth restoring, and the crash-restore prompt AppKit raises
// on the launch after a crash is INVISIBLE behind a menu-bar-only app: the main thread parks in
// promptToIgnorePersistentState and the app never finishes launching (seen 2026-08-01, when a
// crash made every relaunch hang as "it will not open"). Opting out of persistent UI removes
// both the prompt and the state writes. First set takes effect on the NEXT launch; the login
// agent restarts on every build, so in practice immediately.
if UserDefaults.standard.object(forKey: "ApplePersistenceIgnoreState") == nil {
    UserDefaults.standard.set(true, forKey: "ApplePersistenceIgnoreState")
}

// Last words: macOS crash logs strip ObjC exception reasons and Swift symbol names, which made
// a real crash here (2026-08-01) nearly undiagnosable. Write the name, reason, and symbolicated
// stack to the config dir before dying; 0600 like every other file there.
NSSetUncaughtExceptionHandler { e in
    let msg = "\(Date())\n\(e.name.rawValue): \(e.reason ?? "no reason")\n\(e.callStackSymbols.joined(separator: "\n"))\n"
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/burndown/last-exception.log")
    try? Data(msg.utf8).write(to: url)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(delegate.settings.showDockIcon ? .regular : .accessory)   // Show Dock icon setting
app.run()
