import Foundation

// The One Pulse motion system (spec 7.2). The whole app's heart rate: every periodic motion samples
// this single clock rather than a free-running timer. Foundation-pure so the tier ladder is unit-testable
// (run-burnclock-tests.sh); the app advances `elapsed` from its one 30 Hz animator and calls `retier`.

enum BurnTier: String, CaseIterable {
    case idle, low, mid, heavy, redline, overLimit
    /// The tempo ladder (the only breathing periods in the product).
    var period: TimeInterval {
        switch self {
        case .idle: return 8.0
        case .low: return 6.0
        case .mid: return 4.5
        case .heavy: return 3.2
        case .redline: return 2.4
        case .overLimit: return 10.0
        }
    }
    var amplitude: Double {
        switch self {
        case .idle: return 0.5
        case .low, .mid: return 1.0
        case .heavy: return 1.25
        case .redline: return 1.5
        case .overLimit: return 0.6
        }
    }
}

// ── Fire motion tables (spec 3.1-3.5). Every fire frequency in the product lives HERE, in Hz, and is
// evaluated against BurnClock.elapsed as sin(2*pi*f*elapsed). Nothing derives motion from burn rate
// directly, and nothing uses the wrapped phase (that was the drafts' discontinuity bug).
extension BurnTier {
    /// spec 3.1: the single `heat` scalar. Renderers lerp toward this at 0.06/frame.
    var heat: Double {
        switch self {
        case .idle: return 0.15
        case .low: return 0.30
        case .mid: return 0.50
        case .heavy: return 0.85
        case .redline: return 1.00
        case .overLimit: return 0.10   // coals, not rage
        }
    }
    /// Halo (3.5 L1) and Smolder's wandering warmth (3.2 L4) are "mid+" only.
    var isMidPlus: Bool { self == .mid || self == .heavy || self == .redline }

    static let hzCeiling: Double = 2.5   // spec 7.2: hard oscillation ceiling, everywhere, no exceptions

    /// The fastest thing this tier animates, in Hz. The render rate is derived from THIS rather than
    /// guessed: sampling at ~14x the motion's own frequency is far above Nyquist and reads as perfectly
    /// smooth, so a 0.20 Hz idle sway does not need 30fps (its excursion is sub-pixel), while a 2.4 Hz
    /// redline flick does. Buttery by derivation, cheap as a side effect.
    var fastestHz: Double { max(flameFlick.hz, max(flameFlick2?.hz ?? 0, max(flameSway.hz, max(seamHz, smolderBreathHz)))) }
    /// Frames per second needed for this tier's motion to look continuous (clamped to a sane band).
    var renderFPS: Double { min(30, max(10, fastestHz * 14)) }

    /// spec 3.5 flame height flick: (amplitude pt, Hz)
    var flameFlick: (amp: Double, hz: Double) {
        switch self {
        case .idle:      return (0.30, 0.20)
        case .low:       return (0.40, 0.50)
        case .mid:       return (0.50, 1.20)
        case .heavy:     return (0.70, 1.80)
        case .redline:   return (0.70 * 1.25, min(Self.hzCeiling, 1.80 * 1.25))
        case .overLimit: return (0.15, 0.10)   // the 2pt stub breathes on the overLimit tier
        }
    }
    /// spec 3.5: heavy/redline add a secondary flick.
    var flameFlick2: (amp: Double, hz: Double)? {
        switch self {
        case .heavy:   return (0.25, 2.40)
        case .redline: return (0.25 * 1.25, min(Self.hzCeiling, 2.40 * 1.25))
        default:       return nil
        }
    }
    /// spec 3.5 flame tip sway: (amplitude pt, Hz)
    var flameSway: (amp: Double, hz: Double) {
        switch self {
        case .idle:      return (0.60, 0.125)
        case .low:       return (0.70, 0.25)
        case .mid:       return (0.90, 0.50)
        case .heavy:     return (1.20, 0.80)
        case .redline:   return (1.20 * 1.25, min(Self.hzCeiling, 0.80 * 1.25))
        case .overLimit: return (0.25, 0.08)
        }
    }
    /// spec 3.2 Smolder: baseline-smolder breath Hz, and the L3 peak alpha.
    var smolderBreathHz: Double {
        switch self {
        case .idle: return 0.12
        case .low: return 0.18
        case .mid: return 0.25
        case .heavy: return 0.45
        case .redline: return 0.60
        case .overLimit: return 0.10
        }
    }
    var smolderPeakAlpha: Double {
        switch self {
        case .idle: return 0.30
        case .low: return 0.36
        case .mid: return 0.42
        case .heavy: return 0.55
        case .redline: return 0.60
        case .overLimit: return 0.26
        }
    }
    /// spec 3.3 Burnfront: seam-filament Hz.
    var seamHz: Double {
        switch self {
        case .idle: return 0.15
        case .low: return 0.25
        case .mid: return 0.40
        case .heavy: return 0.70
        case .redline: return 1.00
        case .overLimit: return 0.12
        }
    }
    /// spec 3.3 L5: one spark alive at a time; cycle seconds. nil = no sparks at this tier.
    var seamSparkCycle: Double? {
        switch self {
        case .heavy: return 2.4
        case .redline: return 1.6
        default: return nil
        }
    }
    /// spec 3.4 Kiln: convection band speed, pt/s. Redline runs two bands.
    var kilnBandSpeed: Double {
        switch self {
        case .idle: return 1.2
        case .low: return 2.0
        case .mid: return 2.8
        case .heavy: return 6.0
        case .redline: return 8.0
        case .overLimit: return 1.0
        }
    }
}

struct BurnClock {
    var elapsed: TimeInterval = 0          // monotonic seconds; all Hz formulas use THIS
    private(set) var tier: BurnTier = .idle
    /// Spec 7.2: "Tempo changes interpolate ... with phase preserved ... never snap." Changing the
    /// period would otherwise make `elapsed mod period` jump discontinuously on every retier, so we
    /// carry an origin that is re-anchored at each tier change to hold the phase steady across it.
    private var phaseOrigin: TimeInterval = 0

    var period: TimeInterval { tier.period }
    /// 0..1, wraps every `period` seconds, continuous across tempo changes.
    var phase: Double {
        guard period > 0 else { return 0 }
        let p = (elapsed - phaseOrigin).truncatingRemainder(dividingBy: period) / period
        return p < 0 ? p + 1 : p
    }
    /// 0.5 - 0.5*cos(phase*2pi), scaled by the tier amplitude.
    var breath: Double { (0.5 - 0.5 * cos(phase * 2 * .pi)) * tier.amplitude }

    /// The tier from the usage fraction, the burn ratio (burn / rolling average), and the session alert
    /// threshold. `over` forces overLimit; escalation compresses tempo, never adds noise (spec law 3).
    static func tier(usage: Double, over: Bool, burnRatio: Double, threshold: Double, tokensFlowing: Bool) -> BurnTier {
        if over { return .overLimit }
        if usage >= threshold { return .redline }
        if burnRatio > 1.5 || usage >= threshold - 0.15 { return .heavy }
        if !tokensFlowing { return .idle }
        if burnRatio < 0.5 { return .low }
        return .mid
    }
    mutating func retier(usage: Double, over: Bool, burnRatio: Double, threshold: Double, tokensFlowing: Bool) {
        let next = BurnClock.tier(usage: usage, over: over, burnRatio: burnRatio, threshold: threshold, tokensFlowing: tokensFlowing)
        guard next != tier else { return }
        let held = phase                       // the crest we are on right now
        tier = next                            // period changes here...
        phaseOrigin = elapsed - held * period  // ...so re-anchor to land on the same crest
    }
}
