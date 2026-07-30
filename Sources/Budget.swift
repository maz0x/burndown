import Foundation

// Foundation-pure self-imposed spend budgets with pacing guardrails. This is
// distinct from the Anthropic-limit alerts: those track the plan's hard usage caps, whereas a
// budget is a soft target the user sets on their own spend (tokens or USD) over a day or a week, with
// a projection so the menu bar can warn early ("on pace to blow the weekly budget") rather than
// only after the line is crossed.
//
// Kept AppKit / Combine / SwiftUI free so the headless harness (run-budget-tests.sh) can compile
// and test the real pacing math with no UI. elapsedFraction is how far into the period we are
// (0 at the start, 1 at the end); the caller computes it from the clock and the period length.

enum BudgetPeriod: String { case day, week }

enum BudgetMetric: String { case tokens, usd }

/// A user-set budget: a limit (in tokens or USD per the metric) over one period.
struct BudgetConfig {
    let metric: BudgetMetric
    let limit: Double
    let period: BudgetPeriod
}

enum BudgetLevel: String { case ok, warn, over }

/// The evaluated state of a budget at a point in time, ready for the menu bar / charts.
struct BudgetStatus {
    let level: BudgetLevel
    let spent: Double
    let limit: Double
    let fractionUsed: Double
    let projectedSpend: Double
    let willExceed: Bool
    let summary: String
}

/// Projected end-of-period spend: scale what has been spent so far by how far into the period we
/// are. Exposed on its own so charts can draw the projected end point without rebuilding a full
/// BudgetStatus. With no elapsed time yet (elapsedFraction <= 0) we cannot pace, so we fall back
/// to the raw spent value rather than dividing by zero.
func budgetProjectedEnd(spent: Double, config: BudgetConfig, elapsedFraction: Double) -> Double {
    elapsedFraction > 0 ? spent / elapsedFraction : spent
}

/// Evaluate a budget: how much is used, the projected end-of-period spend, whether that pace will
/// exceed the limit, and a plain-English one-liner. warn at fractionUsed >= 0.8, over at >= 1.0.
func budgetStatus(spent: Double, config: BudgetConfig, elapsedFraction: Double) -> BudgetStatus {
    let projectedSpend = budgetProjectedEnd(spent: spent, config: config, elapsedFraction: elapsedFraction)
    let willExceed = projectedSpend > config.limit
    let fractionUsed = config.limit > 0 ? spent / config.limit : 0

    let level: BudgetLevel
    if fractionUsed >= 1 { level = .over }
    else if fractionUsed >= 0.8 { level = .warn }
    else { level = .ok }

    let periodWord = config.period == .day ? "daily" : "weekly"
    let summary: String
    if willExceed && config.limit > 0 {
        // e.g. "On pace to use 1.3x your weekly budget"
        let multiple = projectedSpend / config.limit
        summary = String(format: "On pace to use %.1fx your %@ budget", multiple, periodWord)
    } else {
        // e.g. "Within budget, 42% used"
        let pct = Int((fractionUsed * 100).rounded())
        summary = "Within budget, \(pct)% used"
    }

    return BudgetStatus(level: level, spent: spent, limit: config.limit,
                        fractionUsed: fractionUsed, projectedSpend: projectedSpend,
                        willExceed: willExceed, summary: summary)
}
