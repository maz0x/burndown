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
    /// Plain-English one-liner for the menu / alert (no em-dashes, per project rule).
    let summary: String
}

/// Median of recent burn-rate samples (tokens per minute). Median, not mean, so a single runaway
/// spike already in the window does not inflate the "normal" we compare against. Returns 0 if empty.
func runawayBaseline(_ history: [Double]) -> Double {
    if history.isEmpty { return 0 }
    let sorted = history.sorted()
    let n = sorted.count
    let mid = n / 2
    if n % 2 == 1 { return sorted[mid] }
    return (sorted[mid - 1] + sorted[mid]) / 2
}

/// Compare the current burn rate against the learned baseline and classify it. The baseline is
/// floored at minBaseline (default 1.0 tokens/min) so a near-zero or empty history cannot make the
/// factor explode to infinity. level: runaway if factor >= 4, elevated if factor >= 2, else normal.
func runawayVerdict(history: [Double], current: Double, minBaseline: Double = 1.0) -> RunawayResult {
    let baseline = max(minBaseline, runawayBaseline(history))
    let factor = current / baseline

    let level: RunawayLevel
    if factor >= 4 {
        level = .runaway
    } else if factor >= 2 {
        level = .elevated
    } else {
        level = .normal
    }

    let x = String(format: "%.1f", factor)
    let summary: String
    switch level {
    case .runaway:
        summary = "Burn is \(x)x your normal rate, possible runaway loop"
    case .elevated:
        summary = "Burn is \(x)x your normal rate, running hot"
    case .normal:
        summary = "Burn is \(x)x your normal rate, looks normal"
    }

    return RunawayResult(level: level, baseline: baseline, current: current, factor: factor, summary: summary)
}
