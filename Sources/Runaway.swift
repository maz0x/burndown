import Foundation

// Foundation-pure adaptive runaway-burn detection. Replaces the old
// fixed 30k / 60k / 100k tokens-per-minute thresholds with a learned baseline: we take the median
// of recent burn-rate samples (robust to the odd spike) and flag the current rate as elevated or
// runaway when it is a multiple of that personal normal. This keeps the alert meaningful whether a
// user idles at 2k/min or routinely runs at 80k/min. Kept AppKit / Combine / SwiftUI free so the
// headless harness (run-runaway-tests.sh) can compile and test the real logic with no UI.

/// How hot the current burn looks relative to the learned baseline.
enum RunawayLevel: String {
    case normal
    case elevated
    case runaway
}

/// The verdict for one current-rate check against recent history.
struct RunawayResult {
    let level: RunawayLevel
    /// The learned normal rate (tokens per minute) the current rate was compared against.
    let baseline: Double
    /// The current burn rate (tokens per minute) that was evaluated.
    let current: Double
    /// current / baseline (how many times the normal rate we are burning at).
    let factor: Double
    /// Whether there was enough real activity to have an opinion at all. False means "no idea yet",
    /// which is reported as normal but must never raise an alarm.
    let enoughData: Bool
    /// Plain-English one-liner for the menu / alert (no em-dashes, per project rule).
    let summary: String
}

/// How many samples of actual burning are needed before "your normal rate" means anything.
let kRunawayMinSamples = 5

/// A rate so low that being a multiple of it still says nothing (tokens per minute).
///
/// The fixed thresholds this detector replaced started calling things elevated at 30k/min, so a
/// floor of 2k keeps a runaway verdict (4x) at 8k/min: still far more sensitive than the old fixed
/// bar, but no longer willing to describe a trickle as a multiple of a smaller trickle.
let kRunawayMinBaseline: Double = 2000

/// Median of recent burn-rate samples (tokens per minute), ignoring the idle ones.
///
/// Median, not mean, so a single runaway spike already in the window does not inflate the "normal"
/// we compare against. Zeros are dropped before the median is taken, and that is the whole point:
/// samples arrive every couple of seconds whether or not anything is happening, so a minute of
/// thinking or reading fills the window with zeros and drags the median to 0. The baseline then
/// says the user's normal rate is nothing at all, and the first token of the next reply is
/// infinitely above normal. Returns 0 when nothing was burning.
func runawayBaseline(_ history: [Double]) -> Double {
    let active = history.filter { $0 > 0 }
    if active.isEmpty { return 0 }
    let sorted = active.sorted()
    let n = sorted.count
    let mid = n / 2
    if n % 2 == 1 { return sorted[mid] }
    return (sorted[mid - 1] + sorted[mid]) / 2
}

/// Compare the current burn rate against the learned baseline and classify it.
///
/// Two guards keep this from crying wolf. The baseline is floored at minBaseline, so a near-zero
/// history cannot make the factor explode; and there must be at least kRunawayMinSamples samples of
/// real activity before any verdict above normal is possible, so the first burst after a quiet
/// spell is not measured against a window that was empty.
/// level: runaway if factor >= 4, elevated if factor >= 2, else normal.
func runawayVerdict(history: [Double], current: Double,
                    minBaseline: Double = kRunawayMinBaseline) -> RunawayResult {
    let activeCount = history.filter { $0 > 0 }.count
    let enoughData = activeCount >= kRunawayMinSamples
    let baseline = max(minBaseline, runawayBaseline(history))
    let factor = current / baseline

    let level: RunawayLevel
    if !enoughData {
        level = .normal
    } else if factor >= 4 {
        level = .runaway
    } else if factor >= 2 {
        level = .elevated
    } else {
        level = .normal
    }

    let x = String(format: "%.1f", factor)
    let summary: String
    if !enoughData {
        summary = "Not enough recent activity to know your normal rate yet"
    } else {
        switch level {
        case .runaway:
            summary = "Burn is \(x)x your normal rate, possible runaway loop"
        case .elevated:
            summary = "Burn is \(x)x your normal rate, running hot"
        case .normal:
            summary = "Burn is \(x)x your normal rate, looks normal"
        }
    }

    return RunawayResult(level: level, baseline: baseline, current: current, factor: factor,
                         enoughData: enoughData, summary: summary)
}
