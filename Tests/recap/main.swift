import Foundation

// UsageRecord / UsageRollup and the rollup helpers come from the real Aggregation.swift + Pricing.swift
// (compiled in by run-recap-tests.sh), so nothing is redeclared here. Same check()/failures/exit pattern
// as Tests/chartdata/main.swift.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print(cond ? "  ok   \(msg)" : "  FAIL \(msg)")
    if !cond { failures += 1 }
}

// Fixed UTC calendar so day keys are deterministic regardless of the host timezone.
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!

func day(_ s: String) -> Date {
    let f = DateFormatter()
    f.calendar = cal
    f.timeZone = cal.timeZone
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
}

func rec(_ when: String, model: String, project: String, input: Int = 0, output: Int = 0,
         cache5m: Int = 0, cache1h: Int = 0, cacheRead: Int = 0) -> UsageRecord {
    UsageRecord(date: day(when), model: model, project: project,
                input: input, output: output, cache5m: cache5m, cache1h: cache1h, cacheRead: cacheRead)
}

print("compactTokens:")
check(compactTokens(940) == "940", "small counts stay raw")
check(compactTokens(0) == "0", "zero stays 0")
check(compactTokens(999) == "999", "just under 1K stays raw")
check(compactTokens(1_000) == "1K", "exactly 1K with no trailing .0")
check(compactTokens(530_000) == "530K", "thousands -> K")
check(compactTokens(4_200_000) == "4.2M", "millions keep one decimal")
check(compactTokens(4_000_000) == "4M", "round millions drop the .0")
check(compactTokens(-2_500_000) == "-2.5M", "negatives keep their sign")

print("recap (empty input):")
let empty = recap([], label: "Today", calendar: cal)
check(empty.totalTokens == 0, "empty -> 0 tokens")
check(empty.costUSD == 0, "empty -> $0")
check(empty.dayCount == 0, "empty -> 0 days")
check(empty.topProject == "(none)", "empty -> top project (none)")
check(empty.topModelFamily == "(none)", "empty -> top family (none)")
check(empty.busiestDay == "", "empty -> busiest day blank")
check(recapText(empty) == "Today: 0 tokens, ~$0.00, across 0 days", "empty recap text has no detail clauses")

print("recap (normal multi-day):")
let records = [
    // 2026-06-01: Opus heavy on project alpha (1M input)
    rec("2026-06-01 09:00", model: "claude-opus-4-8", project: "alpha", input: 1_000_000),
    // 2026-06-02: even bigger Opus day on project alpha (3M input) -> busiest day
    rec("2026-06-02 10:00", model: "claude-opus-4-8", project: "alpha", input: 3_000_000),
    // 2026-06-02: a little Sonnet on project beta the same day
    rec("2026-06-02 14:00", model: "claude-sonnet-4-5", project: "beta", input: 200_000),
    // 2026-06-03: small Sonnet day on beta
    rec("2026-06-03 11:00", model: "claude-sonnet-4-5", project: "beta", input: 100_000),
]
let r = recap(records, label: "This week", calendar: cal)
check(r.label == "This week", "label is carried through")
check(r.totalTokens == 4_300_000, "total tokens sum across all records")
check(r.dayCount == 3, "three distinct calendar days")
check(r.topProject == "alpha", "alpha is the biggest project by tokens")
check(r.topModelFamily == "Opus", "Opus is the dominant model family")
check(r.busiestDay == "2026-06-02", "2026-06-02 is the busiest day")
check(r.costUSD > 0, "cost is positive for real usage")

print("recapText (normal):")
let text = recapText(r)
check(text.contains("This week: 4.3M tokens"), "headline shows label and compact tokens")
check(text.contains("across 3 days"), "shows the day count with plural")
check(text.contains("top project alpha"), "names the top project")
check(text.contains("mostly Opus"), "names the dominant family")
check(text.contains("busiest Tue Jun 2"), "names the busiest day as a human date")
let emDash = Character(UnicodeScalar(0x2014)!)
check(!text.contains(emDash), "no em-dashes in the recap text")

print("recap (boundary: single day, single record):")
let one = [rec("2026-06-05 12:00", model: "claude-haiku-4-5", project: "solo", input: 500)]
let r1 = recap(one, label: "Today", calendar: cal)
check(r1.dayCount == 1, "single day counts as 1")
check(r1.busiestDay == "2026-06-05", "the only day is the busiest")
check(recapText(r1).contains("across 1 day"), "uses singular day for a one-day window")
check(r1.topModelFamily == "Haiku", "single Haiku record -> Haiku family")

print("recap (boundary: tie-break busiest day favors earlier date):")
let tie = [
    rec("2026-06-10 09:00", model: "claude-opus-4-8", project: "x", input: 1_000),
    rec("2026-06-11 09:00", model: "claude-opus-4-8", project: "x", input: 1_000),
]
let rt = recap(tie, label: "Tie", calendar: cal)
check(rt.busiestDay == "2026-06-10", "equal-token days resolve to the earlier date")

print(failures == 0 ? "\nALL RECAP TESTS PASSED" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
