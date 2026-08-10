import Foundation

// Foundation-pure weekly pacing advisor: turns the current weekly burn into a
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
        //
        // The session count is dropped entirely when sessionFraction is 0, which is how the caller
        // says "nothing has been learned about the caps yet". Dividing one placeholder by another
        // produced a confident "about 2 sessions left" that was arithmetic on two guesses. The
        // verdict itself still holds: it comes from the rate and the time, not from the caps.
        // Rounded DOWN otherwise. "About 3 sessions left" is a promise the reader plans against,
        // and rounding 2.5 up to 3 promises a session that is not there.
        if sessionFraction > 0 {
            let n = max(0, Int(sessionsRemaining.rounded(.down)))
            summary = "On pace to finish the week with headroom, about \(n) \(n == 1 ? "session" : "sessions") left"
        } else {
            summary = "On pace to finish the week with headroom"
        }
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
        // Rounding can carry a shade under an hour up to a flat sixty, and "60m" is a unit the
        // reader has to convert themselves when the whole point of this is not to make them.
        if mins >= 60 { return "1h" }
        return "\(mins)m"
    }
    return "\(Int(h.rounded()))h"
}

// MARK: - Pace strips (the "Pace" chart)

/// One row of the pace chart: how fast a budget is going against how fast its window refills.
///
/// Kept here, Foundation-pure and tested, rather than inside the chart body, because "am I
/// overspending, and by how much" is the actual claim the chart makes and it should not live
/// somewhere a test cannot reach it.
struct PaceReading {
    /// Spent share of the budget divided by elapsed share of the window. 1.0 is exactly on pace.
    let ratio: Double
    /// Seconds until the budget is gone at this pace. nil when nothing is being spent.
    let secondsToEmpty: Double?
    /// Seconds of window still to run once the budget is gone, when that happens first.
    let dryEarlyBy: Double?
    /// Plain English, for the line under the bar.
    let caption: String
}

/// nil when the window has barely started, because a pace read off the first minute of a five hour
/// window is noise, not information.
func paceReading(pct: Double, secondsToReset: Double, window: Double, atLimitLabel: String = "limit") -> PaceReading? {
    let elapsed = window - max(0, secondsToReset)
    guard elapsed > 60, window > 0 else { return nil }
    let timeShare = min(1, elapsed / window)
    guard timeShare > 0.01 else { return nil }
    let ratio = pct / timeShare

    let used = max(0, pct)
    let ratePerSecond = used / elapsed
    let remaining = max(0, 1 - used)
    let toEmpty: Double? = ratePerSecond > 0 ? remaining / ratePerSecond : nil
    let left = max(0, secondsToReset)

    var dryEarlyBy: Double? = nil
    let caption: String
    if used >= 1 {
        caption = "\(atLimitLabel) reached, resets in \(compactETA(left))"
    } else if let t = toEmpty, t < left {
        dryEarlyBy = left - t
        caption = "at this pace the \(atLimitLabel) arrives \(compactETA(left - t)) before the reset"
    } else if toEmpty == nil {
        caption = "nothing spent in this window yet"
    } else {
        caption = "at this pace it lasts past the reset"
    }
    return PaceReading(ratio: ratio, secondsToEmpty: toEmpty, dryEarlyBy: dryEarlyBy, caption: caption)
}
