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
// Samples arrive every couple of seconds whether or not anything is burning, so idle time fills the
// window with zeros. A median that counts them says the user's normal rate is nothing at all, and
// then the first token after a quiet minute is infinitely above normal.
check(runawayBaseline([0, 0, 0, 100, 0, 0, 0]) == 100, "idle samples do not drag the baseline to zero")
check(runawayBaseline([0, 0, 0]) == 0, "all idle -> no baseline at all")
check(runawayBaseline([0, 10, 0, 20, 0, 30]) == 20, "the median is taken over the active samples only")

print("runawayVerdict levels:")
let normal = runawayVerdict(history: [4000, 4000, 4000, 4000, 4000], current: 4800)
check(normal.level == .normal, "1.2x is normal")
check(close(normal.baseline, 4000), "baseline is the median 4000")
check(close(normal.factor, 1.2), "factor = 4800 / 4000")

let elevatedLow = runawayVerdict(history: [4000, 4000, 4000, 4000, 4000], current: 8000)
check(elevatedLow.level == .elevated, "exactly 2x is elevated (boundary)")

let elevatedHigh = runawayVerdict(history: [4000, 4000, 4000, 4000, 4000], current: 15960)
check(elevatedHigh.level == .elevated, "just under 4x is elevated")

let runaway = runawayVerdict(history: [4000, 4000, 4000, 4000, 4000], current: 16000)
check(runaway.level == .runaway, "exactly 4x is runaway (boundary)")
check(close(runaway.factor, 4.0), "factor = 16000 / 4000")

let runawayHigh = runawayVerdict(history: [4000, 4000, 4000, 4000, 4000], current: 16800)
check(runawayHigh.level == .runaway, "4.2x is runaway")
check(runawayHigh.summary.contains("4.2x"), "summary names the multiple")
check(runawayHigh.summary.contains("runaway"), "runaway summary mentions runaway")
check(!runawayHigh.summary.contains("\u{2014}") && !runawayHigh.summary.contains("\u{2013}"),
      "summary has no em-dash or en-dash")

print("no opinion without evidence:")
// This is the bug this suite used to certify: an EMPTY history produced a runaway verdict, because
// the floored baseline of 1.0 made any real rate a huge multiple of it. After a quiet minute the
// window is all zeros, which is the same situation, and that is precisely when the next reply
// starts. The alert has to stay silent until it has actually seen the user working.
let empty = runawayVerdict(history: [], current: 50_000)
check(empty.level == .normal, "an empty history never raises an alarm, however fast the current rate")
check(!empty.enoughData, "and it says outright that it has no basis for a verdict")
check(!empty.summary.contains("x your normal"), "so the summary does not quote a meaningless multiple")

let justIdled = runawayVerdict(history: Array(repeating: 0, count: 40), current: 50_000)
check(justIdled.level == .normal, "forty idle samples are still no evidence, so no alarm")

let barelyActive = runawayVerdict(history: [1000, 1000, 1000, 0, 0, 0], current: 50_000)
check(barelyActive.level == .normal, "three active samples are under the minimum, so still no verdict")

let enough = runawayVerdict(history: [1000, 1000, 1000, 1000, 1000, 0, 0], current: 50_000)
check(enough.level == .runaway, "five active samples are enough, and 50x the median is a runaway")
check(enough.enoughData, "and it reports that it had the evidence")
check(close(enough.baseline, 2000), "the baseline floor holds a 1000/min median up to 2000")

print("the floor is physical, not nominal:")
// A floor of 1.0 tokens/min meant four tokens a minute counted as a runaway. The replacement floor
// keeps a runaway verdict at 8k/min, still far below the 30k/min fixed threshold this replaced.
let trickle = runawayVerdict(history: [0.1, 0.2, 0.3, 0.4, 0.5], current: 4)
check(trickle.level == .normal, "four tokens a minute is not a runaway, whatever the ratio says")
let realBurst = runawayVerdict(history: [0.1, 0.2, 0.3, 0.4, 0.5], current: 8000)
check(realBurst.level == .runaway, "8k/min over the floor still is one")

let customFloor = runawayVerdict(history: [0.1, 0.2, 0.3, 0.4, 0.5], current: 20, minBaseline: 10)
check(close(customFloor.baseline, 10), "a caller can still set its own floor")
check(customFloor.level == .elevated, "20 over a floor of 10 is exactly 2x, elevated")

let zeroCurrent = runawayVerdict(history: [100, 100, 100, 100, 100], current: 0)
check(zeroCurrent.level == .normal, "zero current burn is normal")
check(close(zeroCurrent.factor, 0), "zero current -> 0 factor")

print(failures == 0 ? "\nALL RUNAWAY TESTS PASSED" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
