import Foundation

// Foundation-pure weekly pacing advisor (feature #5): turns the current weekly burn into a
// plain-language projection of when the weekly cap is hit and how many sessions are left before
// the reset. Kept AppKit / Combine / SwiftUI free so the headless harness (run-pacing-tests.sh)
// can compile and test the real projection math with no UI.
//
// Inputs are all unit-free fractions and hours so the caller (UsageEngine) can feed whatever
// window it tracks: fractionUsed is 0...1 of the weekly cap consumed, ratePerHour is the
// fraction-of-cap burned per hour at the current pace, hoursUntilReset is time left in the
// weekly window, and sessionFraction is the typical fraction one session consumes.

/// Projection of how the current pace lands against the weekly cap before the reset.
struct PacingProjection {
    /// True when the cap is reached before the weekly window resets (at the current pace).
    let hitsCapBeforeReset: Bool
    /// Hours from now until the cap is reached, or nil when the rate is zero (cap never reached).
    let hoursUntilCap: Double?
    /// Estimated sessions of headroom left before the cap (0 when a session size is unknown).
    let sessionsRemaining: Double
    /// Plain-English one-liner for the menu (no em-dashes per project style).
    let summary: String
}

/// Project the weekly pace into a cap-hit estimate and remaining-session count.
/// remaining = max(0, 1 - fractionUsed). hoursUntilCap = remaining / ratePerHour when the rate is
/// positive (else nil). The cap is hit before reset when that time is within hoursUntilReset.
func weeklyPacing(fractionUsed: Double, ratePerHour: Double, hoursUntilReset: Double, sessionFraction: Double) -> PacingProjection {
    let remaining = max(0, 1 - fractionUsed)
    let hoursUntilCap: Double? = ratePerHour > 0 ? remaining / ratePerHour : nil
    let hitsCapBeforeReset = (hoursUntilCap != nil && hoursUntilCap! <= hoursUntilReset)
    let sessionsRemaining = sessionFraction > 0 ? remaining / sessionFraction : 0

    let summary: String
    if remaining <= 0 {
        // Already at (or past) the cap: nothing left until the reset.
        summary = "Weekly cap reached, resets in about \(hoursText(hoursUntilReset))"
    } else if hitsCapBeforeReset, let h = hoursUntilCap {
        summary = "At this pace you reach the weekly cap in ~\(hoursText(h)), before the reset"
    } else {
        // On pace to coast to the reset with room to spare.
        let n = Int(sessionsRemaining.rounded())
        summary = "On pace to finish the week with headroom, about \(n) \(n == 1 ? "session" : "sessions") left"
    }

    return PacingProjection(hitsCapBeforeReset: hitsCapBeforeReset,
                            hoursUntilCap: hoursUntilCap,
                            sessionsRemaining: sessionsRemaining,
                            summary: summary)
}

/// Compact human duration for summaries: minutes under an hour, whole hours otherwise.
func hoursText(_ hours: Double) -> String {
    let h = max(0, hours)
    if h < 1 {
        let mins = Int((h * 60).rounded())
        return "\(mins)m"
    }
    return "\(Int(h.rounded()))h"
}
