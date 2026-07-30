import Foundation

// Headless tests for Sources/Runaway.swift. Same check()/failures/exit(1) pattern as
// Tests/chartdata/main.swift; the logic file is compiled in alongside this harness.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print(cond ? "  ok   \(msg)" : "  FAIL \(msg)")
    if !cond { failures += 1 }
}

func close(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) < eps }

print("runawayBaseline:")
check(runawayBaseline([]) == 0, "empty -> 0")
check(runawayBaseline([42]) == 42, "single sample -> that sample")
check(runawayBaseline([10, 20, 30]) == 20, "odd count -> middle value")
check(runawayBaseline([10, 20, 30, 40]) == 25, "even count -> mean of two middles")
check(runawayBaseline([30, 10, 20]) == 20, "unsorted input still finds the median")
check(runawayBaseline([5, 5, 5, 5, 1000]) == 5, "median ignores a lone spike")

print("runawayVerdict levels:")
let normal = runawayVerdict(history: [100, 100, 100], current: 120)
check(normal.level == .normal, "1.2x is normal")
check(close(normal.baseline, 100), "baseline is the median 100")
check(close(normal.factor, 1.2), "factor = 120 / 100")

let elevatedLow = runawayVerdict(history: [100, 100, 100], current: 200)
check(elevatedLow.level == .elevated, "exactly 2x is elevated (boundary)")

let elevatedHigh = runawayVerdict(history: [100, 100, 100], current: 399)
check(elevatedHigh.level == .elevated, "just under 4x is elevated")

let runaway = runawayVerdict(history: [100, 100, 100], current: 400)
check(runaway.level == .runaway, "exactly 4x is runaway (boundary)")
check(close(runaway.factor, 4.0), "factor = 400 / 100")

let runawayHigh = runawayVerdict(history: [100, 100, 100], current: 420)
check(runawayHigh.level == .runaway, "4.2x is runaway")
check(runawayHigh.summary.contains("4.2x"), "summary names the multiple")
check(runawayHigh.summary.contains("runaway"), "runaway summary mentions runaway")
check(!runawayHigh.summary.contains("\u{2014}") && !runawayHigh.summary.contains("\u{2013}"),
      "summary has no em-dash or en-dash")

print("runawayVerdict baseline floor:")
let empty = runawayVerdict(history: [], current: 50)
check(close(empty.baseline, 1.0), "empty history floors baseline to minBaseline 1.0")
check(close(empty.factor, 50), "factor uses the floored baseline (50 / 1)")
check(empty.level == .runaway, "50x a floored baseline is runaway")

let zeroCurrent = runawayVerdict(history: [100, 100, 100], current: 0)
check(zeroCurrent.level == .normal, "zero current burn is normal")
check(close(zeroCurrent.factor, 0), "zero current -> 0 factor")

let customFloor = runawayVerdict(history: [0.1, 0.2, 0.3], current: 20, minBaseline: 10)
check(close(customFloor.baseline, 10), "tiny median is raised to the custom floor")
check(customFloor.level == .elevated, "20 over a floor of 10 is exactly 2x, elevated")

print(failures == 0 ? "\nALL RUNAWAY TESTS PASSED" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
