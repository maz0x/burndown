import Foundation

// Headless tests for the Foundation-pure budget logic (Sources/Budget.swift). Self-contained:
// the enums and structs live in Budget.swift, so this file only drives them. Same check()/failures
// /exit(1) pattern as Tests/chartdata/main.swift.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print(cond ? "  ok   \(msg)" : "  FAIL \(msg)")
    if !cond { failures += 1 }
}

let weeklyUSD = BudgetConfig(metric: .usd, limit: 100, period: .week)
let dailyTokens = BudgetConfig(metric: .tokens, limit: 1_000_000, period: .day)

print("budgetProjectedEnd:")
// Halfway through the period, spent 30 -> projected 60.
check(budgetProjectedEnd(spent: 30, config: weeklyUSD, elapsedFraction: 0.5) == 60,
      "halfway, spent 30 -> projects 60")
// elapsedFraction <= 0 cannot pace -> falls back to raw spent (no divide by zero).
check(budgetProjectedEnd(spent: 42, config: weeklyUSD, elapsedFraction: 0) == 42,
      "zero elapsed -> returns spent unchanged")
check(budgetProjectedEnd(spent: 42, config: weeklyUSD, elapsedFraction: -0.1) == 42,
      "negative elapsed -> returns spent unchanged")
// Fully elapsed -> projection equals spent.
check(budgetProjectedEnd(spent: 80, config: weeklyUSD, elapsedFraction: 1) == 80,
      "fully elapsed -> projection equals spent")

print("budgetStatus levels:")
// ok: well under, early in the period and on pace.
let okS = budgetStatus(spent: 20, config: weeklyUSD, elapsedFraction: 0.5)  // projects 40
check(okS.level == .ok, "20 of 100 -> ok")
check(!okS.willExceed, "projected 40 < 100 -> will not exceed")
check(okS.summary == "Within budget, 20% used", "ok summary reads plainly")

// warn boundary: fractionUsed exactly 0.8.
let warnS = budgetStatus(spent: 80, config: weeklyUSD, elapsedFraction: 1)
check(warnS.level == .warn, "fractionUsed 0.8 -> warn (boundary)")
check(abs(warnS.fractionUsed - 0.8) < 1e-9, "fractionUsed computes to 0.8")

// over boundary: fractionUsed exactly 1.0.
let overBoundary = budgetStatus(spent: 100, config: weeklyUSD, elapsedFraction: 1)
check(overBoundary.level == .over, "fractionUsed 1.0 -> over (boundary)")

// over: past the limit.
let overS = budgetStatus(spent: 130, config: weeklyUSD, elapsedFraction: 1)
check(overS.level == .over, "130 of 100 -> over")
check(overS.willExceed, "projected 130 > 100 -> will exceed")

print("budgetStatus pacing summary:")
// On pace to overshoot: 65 spent at 50% elapsed projects 130 = 1.3x of 100.
let paceS = budgetStatus(spent: 65, config: weeklyUSD, elapsedFraction: 0.5)
check(paceS.projectedSpend == 130, "65 at 50% elapsed -> projects 130")
check(paceS.willExceed, "projected 130 > 100 -> will exceed")
check(paceS.summary == "On pace to use 1.3x your weekly budget", "pacing summary uses the multiple and period")

// Daily token budget, pacing phrasing flips to "daily".
let dayPace = budgetStatus(spent: 600_000, config: dailyTokens, elapsedFraction: 0.5)  // projects 1.2M
check(dayPace.summary == "On pace to use 1.2x your daily budget", "daily period word in summary")

print("budgetStatus edge cases:")
// Empty / zero spend.
let zeroS = budgetStatus(spent: 0, config: weeklyUSD, elapsedFraction: 0.5)
check(zeroS.level == .ok, "zero spend -> ok")
check(zeroS.fractionUsed == 0, "zero spend -> 0 fractionUsed")
check(!zeroS.willExceed, "zero spend -> will not exceed")
check(zeroS.summary == "Within budget, 0% used", "zero spend summary")

// Zero limit: guard against divide by zero, fractionUsed pinned to 0, no exceed.
let zeroLimit = BudgetConfig(metric: .usd, limit: 0, period: .day)
let zeroLimitS = budgetStatus(spent: 10, config: zeroLimit, elapsedFraction: 0.5)
check(zeroLimitS.fractionUsed == 0, "zero limit -> fractionUsed 0 (no divide by zero)")
check(zeroLimitS.level == .ok, "zero limit -> ok (no false over from the guarded fractionUsed)")
// Per the spec willExceed = projectedSpend > limit, so any spend over a zero limit will exceed.
check(zeroLimitS.willExceed, "zero limit with spend -> projected 20 > 0, will exceed")

// Zero elapsed at the very start of a period: projection falls back to spent, not infinity.
let startS = budgetStatus(spent: 5, config: weeklyUSD, elapsedFraction: 0)
check(startS.projectedSpend == 5, "start of period -> projection is just spent")
check(!startS.willExceed, "small spend at start -> will not exceed")

// raw fields are passed through faithfully.
check(overS.spent == 130 && overS.limit == 100, "spent and limit echoed on status")

// One minute past midnight is seven hundredths of a percent of a day, so a single call then used
// to be scaled up fourteen hundred times and reported as a budget about to be blown. Below the
// threshold the honest projection is simply what has been spent.
print("no pacing from the first sliver of a period:")
do {
    let cfg = BudgetConfig(metric: .usd, limit: 50, period: .day)
    check(budgetProjectedEnd(spent: 2, config: cfg, elapsedFraction: 0.0007) == 2,
          "a minute into the day projects what was actually spent, not 1400x it")
    check(!budgetStatus(spent: 2, config: cfg, elapsedFraction: 0.0007).willExceed,
          "so it does not claim a $50 budget is about to be blown by $2")
    check(budgetProjectedEnd(spent: 2, config: cfg, elapsedFraction: 0.5) == 4,
          "but halfway through the day it paces normally")
    check(budgetProjectedEnd(spent: 5, config: cfg, elapsedFraction: kBudgetMinElapsed) == 100,
          "and the threshold itself is the first point that paces")
}

print(failures == 0 ? "\nALL BUDGET TESTS PASSED" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
