import Foundation

// Pure, Foundation-only alert DECISION logic, split out of UsageAlerts so it can be unit-tested
// headlessly (run-alert-tests.sh) with no UNUserNotificationCenter / AppSettings. UsageAlerts
// applies the returned state and performs the notification side effect; the rules live here.

/// A genuine new window: never observed before, a reset time was gained/lost, or the reset jumped
/// FORWARD by more than 2 min. Ignores tiny jitter and any live<->estimate source flip, which would
/// otherwise re-arm the cycle and re-fire the threshold alert on every refresh.
func isNewCycle(_ stored: Date??, _ reset: Date?) -> Bool {
    guard let prev = stored else { return true }
    switch (prev, reset) {
    case (nil, nil): return false
    case (nil, _), (_, nil): return true
    case let (a?, b?): return b.timeIntervalSince(a) > 120
    }
}

// MARK: - Threshold (%) alerts: fire once per level per window, optional repeat-while-over.

struct AlertPctState { var fired: Set<Int> = []; var cycle: Date?? = nil; var lastFire: Date? = nil }
enum AlertPctAction: Equatable { case none; case fire(level: Int, cur: Int); case repeatOver(cur: Int) }

/// Decide whether a percentage crossed a not-yet-fired level (fire once per level per window),
/// or is due for a repeat-while-over reminder. Mutates `state` exactly as the live path does.
func alertPctEval(pct: Double, reset: Date?, base: Int, repeatMin: Double, now: Date,
                  state: inout AlertPctState) -> AlertPctAction {
    if isNewCycle(state.cycle, reset) { state.cycle = .some(reset); state.fired.removeAll(); state.lastFire = nil }
    let cur = Int((pct * 100).rounded())
    let levels = Array(Set([max(1, min(100, base)), 100])).sorted()
    if let hit = levels.last(where: { cur >= $0 && !state.fired.contains($0) }) {
        for l in levels where l <= hit { state.fired.insert(l) }
        state.lastFire = now
        return .fire(level: hit, cur: cur)
    } else if repeatMin > 0, cur >= (levels.first ?? base), let lf = state.lastFire,
              now.timeIntervalSince(lf) >= repeatMin * 60 {
        state.lastFire = now
        return .repeatOver(cur: cur)
    }
    return .none
}

// MARK: - Burn-rate spike: fire once past the threshold, re-arm only after falling well below (hysteresis).

/// Returns true exactly when a burn alert should fire; flips `armed` per the hysteresis rule
/// (re-arm only once burn drops strictly below 0.7x the threshold).
func alertBurnEval(burn: Double, threshold: Double, armed: inout Bool) -> Bool {
    if burn >= threshold, armed { armed = false; return true }
    else if burn < threshold * 0.7 { armed = true }
    return false
}

// MARK: - Forecast: fire once when the projected ETA drops under the threshold, re-arm on a new window.

struct AlertForecastState { var fired = false; var cycle: Date?? = nil }

/// Returns the rounded minutes-to-limit to announce, or nil when nothing should fire.
func alertForecastEval(minsLeft: Double?, threshold: Double, reset: Date?, state: inout AlertForecastState) -> Int? {
    if isNewCycle(state.cycle, reset) { state.cycle = .some(reset); state.fired = false }
    guard let m = minsLeft else { return nil }
    if m <= threshold, !state.fired { state.fired = true; return Int(m.rounded()) }
    return nil
}
