import Foundation

// Headless harness for the usage-fetch scheduling rule (Sources/FetchSchedule.swift). Same
// check()/failures/exit(1) pattern as Tests/livecontract/main.swift. FetchSchedule is
// Foundation-pure, so the suite compiles the real rule rather than a copy of it.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print(cond ? "  ok   \(msg)" : "  FAIL \(msg)")
    if !cond { failures += 1 }
}

let t0 = Date(timeIntervalSince1970: 1_800_000_000)
func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

print("minInterval: the user's setting, with a floor")
check(FetchSchedule.minInterval(refreshSeconds: 60) == 60, "1m setting is 60s")
check(FetchSchedule.minInterval(refreshSeconds: 300) == 300, "5m setting is 300s")
check(FetchSchedule.minInterval(refreshSeconds: 30) == 30, "30s setting is 30s")
check(FetchSchedule.minInterval(refreshSeconds: 2) == 20, "2s setting is floored at 20s")
check(FetchSchedule.minInterval(refreshSeconds: 10) == 20, "10s setting is floored at 20s")

print("mayFetch: never sooner than the setting")
check(!FetchSchedule.mayFetch(now: at(20), lastFetch: at(0), interval: 60, backoffUntil: nil, force: false),
      "20s after a fetch, 60s setting: no (this is the bug: it used to say yes)")
check(!FetchSchedule.mayFetch(now: at(59.9), lastFetch: at(0), interval: 60, backoffUntil: nil, force: false),
      "59.9s after a fetch, 60s setting: no")
check(FetchSchedule.mayFetch(now: at(60), lastFetch: at(0), interval: 60, backoffUntil: nil, force: false),
      "60s after a fetch, 60s setting: yes")
check(FetchSchedule.mayFetch(now: at(5), lastFetch: at(0), interval: 60, backoffUntil: nil, force: true),
      "a manual refresh goes out at once")
check(FetchSchedule.mayFetch(now: at(0), lastFetch: Date(timeIntervalSince1970: 0), interval: 300,
                             backoffUntil: nil, force: false),
      "the first fetch after launch goes out at once")

print("mayFetch: a backoff blocks, and only a manual refresh passes it")
check(!FetchSchedule.mayFetch(now: at(100), lastFetch: at(0), interval: 60, backoffUntil: at(120), force: false),
      "inside a backoff: no, even though the interval has passed")
check(FetchSchedule.mayFetch(now: at(120), lastFetch: at(0), interval: 60, backoffUntil: at(120), force: false),
      "at the end of the backoff: yes")
check(FetchSchedule.mayFetch(now: at(100), lastFetch: at(0), interval: 60, backoffUntil: at(120), force: true),
      "a manual refresh passes a backoff")
check(!FetchSchedule.mayFetch(now: at(40), lastFetch: at(0), interval: 60, backoffUntil: at(30), force: false),
      "a backoff that ended early does not shorten the interval")

print("a 2 second live loop, simulated: fetches land on the setting, not on the floor")
do {
    // The live loop ticks every 2s while tokens flow. Count the fetches the rule lets through.
    var last = Date(timeIntervalSince1970: 0)
    var fetches: [TimeInterval] = []
    var t: TimeInterval = 0
    while t <= 600 {
        if FetchSchedule.mayFetch(now: at(t), lastFetch: last, interval: 60, backoffUntil: nil, force: false) {
            last = at(t); fetches.append(t)
        }
        t += 2
    }
    check(fetches.count == 11, "ten minutes of 2s ticks at a 60s setting: 11 fetches (got \(fetches.count); it was 31)")
    let gaps = zip(fetches.dropFirst(), fetches).map { $0 - $1 }
    check(gaps.allSatisfy { $0 >= 60 }, "no two fetches closer than 60s (smallest gap \(gaps.min() ?? 0)s)")
}

print("a failed fetch that was not a rate limit is retried at the floor")
check(FetchSchedule.wait(after: false, interval: 300) == 300, "after a good fetch: the whole 5m interval")
check(FetchSchedule.wait(after: true, interval: 300) == 20, "after a failed fetch: 20s, not 5 minutes of 'offline'")
check(FetchSchedule.wait(after: true, interval: 60) == 20, "same at a 1m setting")
check(FetchSchedule.wait(after: true, interval: 20) == 20, "and never under the floor")
check(FetchSchedule.mayFetch(now: at(21), lastFetch: at(0),
                             interval: FetchSchedule.wait(after: true, interval: 300), backoffUntil: nil, force: false),
      "21s after a failed fetch at a 5m setting: yes")
check(!FetchSchedule.mayFetch(now: at(21), lastFetch: at(0),
                              interval: FetchSchedule.wait(after: false, interval: 300), backoffUntil: nil, force: false),
      "21s after a good fetch at a 5m setting: no")

print("waitForInterval: how long the live loop waits for its next chance")
check(FetchSchedule.waitForInterval(now: at(59.5), lastFetch: at(0), interval: 60) == 0.5, "0.5s short of the interval")
check(FetchSchedule.waitForInterval(now: at(75), lastFetch: at(0), interval: 60) == 0, "already past it")

print("the 429 ladder is unchanged: 30, 60, 120 seconds")
check(FetchSchedule.backoffDelay(step: 1) == 30, "step 1 is 30s")
check(FetchSchedule.backoffDelay(step: 2) == 60, "step 2 is 60s")
check(FetchSchedule.backoffDelay(step: 3) == 120, "step 3 is 120s")
check(FetchSchedule.backoffDelay(step: 9) == 120, "the ladder tops out at 120s")
check(FetchSchedule.backoffStep(previous: 0, lastRateLimitAt: nil, now: at(0)) == 1, "a first 429 is step 1")
check(FetchSchedule.backoffStep(previous: 1, lastRateLimitAt: at(0), now: at(60)) == 2, "a second within memory is step 2")
check(FetchSchedule.backoffStep(previous: 3, lastRateLimitAt: at(0), now: at(60)) == 3, "step 3 stays at 3")
check(FetchSchedule.backoffStep(previous: 3, lastRateLimitAt: at(0), now: at(901)) == 1,
      "a 429 after a quiet 15 minutes starts the ladder over")

print("retryAt: the retry replaces the next fetch, it is not an extra one")
check(FetchSchedule.retryAt(now: at(1), lastFetch: at(0), interval: 60, step: 1) == at(60),
      "60s setting, step 1 (30s): the retry is the next ordinary slot, 60s after the failed fetch")
check(FetchSchedule.retryAt(now: at(1), lastFetch: at(0), interval: 60, step: 3) == at(121),
      "60s setting, step 3 (120s): the ladder is longer, so the ladder decides")
check(FetchSchedule.retryAt(now: at(1), lastFetch: at(0), interval: 30, step: 1) == at(31),
      "30s setting, step 1 (30s): the ladder decides")
check(FetchSchedule.retryAt(now: at(1), lastFetch: at(0), interval: 300, step: 3) == at(300),
      "5m setting: never sooner than 5 minutes after the failed fetch")
do {
    // A 429 at t=60 on a 60s setting, with the 2s loop still ticking: exactly one fetch (the
    // retry) may go out before t=180, where there used to be the retry AND the ordinary ticks.
    let failedAt = at(60)
    let until = FetchSchedule.retryAt(now: failedAt.addingTimeInterval(0.4), lastFetch: failedAt, interval: 60, step: 1)
    var last = failedAt
    var fetches: [TimeInterval] = []
    var t: TimeInterval = 62
    while t < 180 {
        if FetchSchedule.mayFetch(now: at(t), lastFetch: last, interval: 60, backoffUntil: until, force: false) {
            last = at(t); fetches.append(t)
        }
        t += 2
    }
    check(fetches == [120], "after a 429 at 60s, the only fetch before 180s is the one at 120s (got \(fetches))")
}

print(failures == 0 ? "\nAll fetch-schedule tests passed." : "\n\(failures) fetch-schedule test(s) FAILED.")
exit(failures == 0 ? 0 : 1)
