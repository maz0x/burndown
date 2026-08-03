import AppKit
import SwiftUI

// MARK: - Breathing, done by the render server

// SwiftUI's `.animation(.repeatForever)` is NOT handed off to Core Animation. SwiftUI keeps its own
// display link alive for the whole life of the animation and re-renders the display list - and, in an
// NSHostingView, re-runs `NSHostingView.layout()` - on EVERY display frame, even though no `body`
// re-evaluates. In the floating window (a 264x900 card over a blurred glass material) one 6pt
// breathing dot cost ~23% of a CPU core continuously; body evaluations were only ~1.5/s.
//
// A real `CABasicAnimation` is different: the app hands the render server a start value, an end value
// and a curve, and then does nothing at all. Interpolation happens out of process, at the display's
// full rate, for free. These two views are that - the same breath, none of the cost.
//
// Rule of thumb for this codebase: a *perpetual* animation must be CA. A *transient* one (a ping, a
// flare, a milestone pulse) is fine in SwiftUI, because the display link stops when it finishes.

enum Breathing {
    /// `ImageRenderer` cannot rasterize an `NSViewRepresentable` - it paints the "unsupported content"
    /// placeholder instead, which silently wrecked the QA popover sheet the first time these views went
    /// in. Every offline render in this app is a `CUB_SNAP*` mode, so detect that once and let the
    /// breathing views fall back to a plain SwiftUI shape (frozen at the top of the breath).
    /// Derived from the environment, not set per call site, so a new snapshot mode is covered for free.
    static let staticRendering = ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("CUB_SNAP") }
}

/// A filled circle whose opacity breathes `lo` <-> `hi` forever, driven entirely by Core Animation.
struct BreathDot: View {
    var color: Color
    var size: CGFloat
    var lo: Double
    var hi: Double
    var period: TimeInterval
    var still: Bool = false
    var body: some View {
        if Breathing.staticRendering {
            Circle().fill(color).frame(width: size, height: size).opacity(hi)
        } else {
            BreathDotLayer(color: color, size: size, lo: lo, hi: hi, period: period, still: still)
        }
    }
}

private struct BreathDotLayer: NSViewRepresentable {
    var color: Color
    var size: CGFloat
    var lo: Double
    var hi: Double
    /// One full breath (out and back), in seconds.
    var period: TimeInterval
    /// Reduce motion (or any caller that wants it still) pins the dot at `hi` with no animation.
    var still: Bool = false

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        v.wantsLayer = true
        let l = v.layer!
        l.cornerRadius = size / 2
        l.masksToBounds = true
        apply(l)
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        guard let l = v.layer else { return }
        l.cornerRadius = size / 2
        apply(l)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }

    private func apply(_ l: CALayer) {
        l.backgroundColor = NSColor(color).cgColor
        let key = "breathe"
        if still || period <= 0 {
            l.removeAnimation(forKey: key)
            l.opacity = Float(hi)
            return
        }
        // Re-adding an identical animation would restart the phase on every SwiftUI update, so leave a
        // running one alone unless its shape actually changed.
        if let cur = l.animation(forKey: key) as? CABasicAnimation,
           cur.duration == period / 2,
           (cur.fromValue as? Double) == lo, (cur.toValue as? Double) == hi { return }
        l.opacity = Float(lo)
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = lo
        a.toValue = hi
        a.duration = period / 2          // out and back == one period
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.isRemovedOnCompletion = false
        l.add(a, forKey: key)
    }
}

/// A capsule-shaped glow that breathes forever behind its content. Replaces a 4fps `TimelineView`,
/// which re-rendered the whole card on every tick for one pill's halo.
struct BreathHalo: View {
    var color: Color
    var opacityRange: ClosedRange<Double>
    var radiusRange: ClosedRange<CGFloat>
    var period: TimeInterval
    var still: Bool = false
    var body: some View {
        if Breathing.staticRendering {
            Capsule().fill(color.opacity(0.001))
                .shadow(color: color.opacity(opacityRange.upperBound), radius: radiusRange.upperBound)
        } else {
            BreathHaloLayer(color: color, opacityRange: opacityRange, radiusRange: radiusRange,
                            period: period, still: still)
        }
    }
}

private struct BreathHaloLayer: NSViewRepresentable {
    var color: Color
    var opacityRange: ClosedRange<Double>
    var radiusRange: ClosedRange<CGFloat>
    var period: TimeInterval
    var still: Bool = false

    func makeNSView(context: Context) -> NSView {
        let v = HaloView()
        v.wantsLayer = true
        configure(v)
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        guard let v = v as? HaloView else { return }
        configure(v)
    }

    private func configure(_ v: HaloView) {
        guard let l = v.layer else { return }
        l.shadowColor = NSColor(color).cgColor
        l.shadowOffset = .zero
        l.backgroundColor = NSColor(color).withAlphaComponent(0.001).cgColor
        v.needsLayout = true

        let key = "halo"
        if still || period <= 0 {
            l.removeAnimation(forKey: key)
            l.shadowOpacity = Float(opacityRange.lowerBound)
            l.shadowRadius = radiusRange.lowerBound
            return
        }
        if let cur = l.animation(forKey: key) as? CAAnimationGroup, cur.duration == period / 2 { return }
        l.shadowOpacity = Float(opacityRange.lowerBound)
        l.shadowRadius = radiusRange.lowerBound
        func ramp(_ path: String, _ from: Any, _ to: Any) -> CABasicAnimation {
            let a = CABasicAnimation(keyPath: path)
            a.fromValue = from; a.toValue = to
            return a
        }
        let group = CAAnimationGroup()
        group.animations = [ramp("shadowOpacity", opacityRange.lowerBound, opacityRange.upperBound),
                            ramp("shadowRadius", radiusRange.lowerBound, radiusRange.upperBound)]
        group.duration = period / 2
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        group.isRemovedOnCompletion = false
        l.add(group, forKey: key)
    }

    /// The glow follows the capsule outline, so the shadow path has to track the layer's size.
    final class HaloView: NSView {
        override func layout() {
            super.layout()
            guard let l = layer else { return }
            l.cornerRadius = bounds.height / 2
            l.shadowPath = CGPath(roundedRect: bounds, cornerWidth: bounds.height / 2,
                                  cornerHeight: bounds.height / 2, transform: nil)
        }
    }
}

/// The redline bloom: a radial gradient fading from `color` at the top edge to clear, whose opacity
/// breathes forever. Same deal - `CAGradientLayer` plus one `CABasicAnimation`, zero per-frame app work.
struct BreathingBloom: View {
    var color: Color
    var peak: Double
    var lo: Double
    var hi: Double
    var period: TimeInterval
    var cornerRadius: CGFloat
    var endRadius: CGFloat
    var still: Bool = false
    var body: some View {
        if Breathing.staticRendering {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(RadialGradient(colors: [color.opacity(peak), .clear],
                                     center: .top, startRadius: 8, endRadius: endRadius))
                .opacity(hi)
        } else {
            BreathingBloomLayer(color: color, peak: peak, lo: lo, hi: hi, period: period,
                                cornerRadius: cornerRadius, endRadius: endRadius, still: still)
        }
    }
}

private struct BreathingBloomLayer: NSViewRepresentable {
    var color: Color
    var peak: Double          // gradient alpha at the centre
    var lo: Double            // opacity floor of the breath
    var hi: Double            // opacity ceiling
    var period: TimeInterval
    var cornerRadius: CGFloat
    /// Gradient radius in points, matched to the SwiftUI `RadialGradient(endRadius:)` it replaces.
    var endRadius: CGFloat
    var still: Bool = false

    func makeNSView(context: Context) -> NSView {
        let v = BloomView()
        v.wantsLayer = true
        v.layer = v.gradient
        v.layerContentsRedrawPolicy = .onSetNeedsDisplay
        configure(v)
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        guard let v = v as? BloomView else { return }
        configure(v)
    }

    private func configure(_ v: BloomView) {
        let g = v.gradient
        g.type = .radial
        g.cornerRadius = cornerRadius
        g.masksToBounds = true
        g.colors = [NSColor(color).withAlphaComponent(CGFloat(peak)).cgColor,
                    NSColor(color).withAlphaComponent(0).cgColor]
        g.locations = [0, 1]
        v.endRadius = endRadius
        v.needsLayout = true

        let key = "breathe"
        if still || period <= 0 {
            g.removeAnimation(forKey: key)
            g.opacity = Float(hi)
            return
        }
        if let cur = g.animation(forKey: key) as? CABasicAnimation,
           cur.duration == period / 2,
           (cur.fromValue as? Double) == lo, (cur.toValue as? Double) == hi { return }
        g.opacity = Float(lo)
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = lo
        a.toValue = hi
        a.duration = period / 2
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.isRemovedOnCompletion = false
        g.add(a, forKey: key)
    }

    /// The gradient is anchored to the TOP CENTRE with a fixed point radius, matching
    /// `RadialGradient(center: .top, endRadius:)`. CAGradientLayer takes unit coordinates, so the
    /// end point has to be recomputed whenever the layer resizes.
    final class BloomView: NSView {
        let gradient = CAGradientLayer()
        var endRadius: CGFloat = 110
        override var isFlipped: Bool { true }
        override func layout() {
            super.layout()
            let w = max(1, bounds.width), h = max(1, bounds.height)
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5 + endRadius / w, y: endRadius / h)
        }
    }
}
