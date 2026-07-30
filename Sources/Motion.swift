import SwiftUI

// The One Pulse motion tokens. FOUR curves, the only four, and ONE duration ladder.
// Anything that animates in this product picks a curve from here and a duration from `Dur`.
// New animation code picks a curve from here and a duration from `Dur`; a few older ad-hoc
// timing curves remain in Views.swift and Onboarding.swift and are being migrated.

extension Animation {
    /// Default property changes: color, opacity, layout, hovers, expands.
    static func emberEase(_ d: Double) -> Animation { .timingCurve(0.42, 0.0, 0.20, 1.0, duration: d) }
    /// One-shot attack: pings, blooms, refills.
    static func flare(_ d: Double) -> Animation { .timingCurve(0.16, 0.84, 0.28, 1.0, duration: d) }
    /// Numbers, bars, rings, segmented selection moving to a new value.
    static var settle: Animation { .spring(response: 0.45, dampingFraction: 0.88) }
    /// Anything measuring time literally: countdown ring, time rings, tide drain.
    static func drain(_ d: Double) -> Animation { .linear(duration: d) }
}

/// The duration ladder: the ONLY allowed values, in seconds.
/// The universal reduce-motion cross-fade is `Dur.crossFade` (240ms).
enum Dur {
    static let d120 = 0.120
    static let d160 = 0.160
    static let d240 = 0.240
    static let d320 = 0.320
    static let d480 = 0.480
    static let d720 = 0.720
    static let d960 = 0.960
    static let d1440 = 1.440

    /// The universal reduce-motion cross-fade.
    static let crossFade = d240
    /// Over-limit entry, "bank the fire".
    static let bankTheFire = d1440
}

/// Minimum re-fire intervals for one-shots. Every one-shot has an id and a floor.
enum OneShot {
    static let heartbeat: TimeInterval = 5             // 5s: the second heartbeat is swallowed
    static let milestone: TimeInterval = 10 * 60       // 10 min dedup on milestone crossings
    static let badgeBump: TimeInterval = 2             // badge state-change bump
}
