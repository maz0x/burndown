import Foundation

/// When Burndown may ask Claude's usage service for fresh numbers. Foundation-pure, so
/// `run-fetchschedule-tests.sh` compiles the real rule.
///
/// The rule used to be spread over three places that did not know about each other: the live loop
/// in main.swift (which ticks every 2 seconds while tokens flow), a fixed 20 second floor in the
/// engine, and the 429 retry. The floor was the only thing between the 2 second tick and the
/// service, so a user who chose "Refresh every 1m" was polling every 20 seconds whenever a chat was
/// burning, and about one request in seven came back 429. The retry then went out on top of the
/// ordinary ticks rather than in place of one.
///
/// One rule now: an automatic fetch goes out no sooner than the user's own interval after the
/// previous fetch, and no sooner than the end of a 429 backoff. Only a fetch the user asked for
/// by hand (`force`) skips it.
enum FetchSchedule {
    /// The service rate-limits hard, so nothing automatic goes faster than this, whatever the
    /// setting says. "Refresh every 2s / 5s / 10s" still speeds up the local readings.
    static let hardFloor: TimeInterval = 20
    /// A remembered 429 is only worth resuming while it is recent. A quiet gap this long starts
    /// the ladder over instead of making the first fresh 429 cost minutes.
    static let rateLimitMemory: TimeInterval = 900
    static let maxBackoffStep = 3

    /// Seconds that must pass between two automatic fetches, for a "Refresh every" setting.
    static func minInterval(refreshSeconds: Int) -> TimeInterval {
        max(hardFloor, TimeInterval(refreshSeconds))
    }

    /// The wait that applies after the previous fetch, given how it ended.
    ///
    /// A fetch that FAILED for a reason other than a rate limit (no network, a timeout, a server
    /// error) brought nothing back, so making the reader wait out a whole "5m" interval for the
    /// next try would leave the card on "offline" for five minutes after a blip. Such a failure is
    /// retried at the floor, which is what every fetch used to wait before this file existed. A
    /// rate limit is not that case: it has its own ladder, and the full interval still applies.
    static func wait(after lastFailed: Bool, interval: TimeInterval) -> TimeInterval {
        lastFailed ? min(interval, hardFloor) : interval
    }

    /// The earliest moment an automatic fetch may go out.
    static func nextAllowed(lastFetch: Date, interval: TimeInterval, backoffUntil: Date?) -> Date {
        let byInterval = lastFetch.addingTimeInterval(interval)
        guard let backoffUntil else { return byInterval }
        return max(byInterval, backoffUntil)
    }

    /// Whether a fetch may go out now. `force` is a fetch the user asked for by hand.
    static func mayFetch(now: Date, lastFetch: Date, interval: TimeInterval,
                         backoffUntil: Date?, force: Bool) -> Bool {
        force || now >= nextAllowed(lastFetch: lastFetch, interval: interval, backoffUntil: backoffUntil)
    }

    /// How long the live loop should wait before a tick can fetch again; 0 when it already can.
    /// A backoff is left out on purpose: the engine books its own retry for the moment one ends.
    static func waitForInterval(now: Date, lastFetch: Date, interval: TimeInterval) -> TimeInterval {
        max(0, lastFetch.addingTimeInterval(interval).timeIntervalSince(now))
    }

    /// The backoff step for a 429 arriving at `now`: one up from the previous step while the last
    /// 429 is recent, back to the bottom of the ladder otherwise.
    static func backoffStep(previous: Int, lastRateLimitAt: Date?, now: Date) -> Int {
        let recent = lastRateLimitAt.map { now.timeIntervalSince($0) <= rateLimitMemory } ?? false
        return recent ? min(previous + 1, maxBackoffStep) : 1
    }

    /// The ladder: 30, 60, 120 seconds.
    static func backoffDelay(step: Int) -> TimeInterval {
        30.0 * pow(2.0, Double(min(max(step, 1), maxBackoffStep) - 1))
    }

    /// When to try again after a 429 that arrived at `now`, for a fetch that went out at
    /// `lastFetch`. The retry REPLACES the next scheduled fetch: it waits out the ladder, and it
    /// also never comes sooner than the user's interval would have allowed the next fetch anyway.
    static func retryAt(now: Date, lastFetch: Date, interval: TimeInterval, step: Int) -> Date {
        max(now.addingTimeInterval(backoffDelay(step: step)), lastFetch.addingTimeInterval(interval))
    }
}
