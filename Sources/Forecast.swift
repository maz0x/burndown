import Foundation

// MARK: - Live connection state (drives the status badge)

// What the badge reports about the live data feed. Anything other than .live/.est means
// the numbers may be behind, so we say so instead of pretending everything is current.
enum LiveState: Equatable {
    case live          // fresh authoritative data from the usage API
    case est           // no live feed; showing the local-log estimate
    case stale         // had live data, but it has not refreshed in a while
    case rateLimited   // the usage API is throttling us (429 / backoff)
    case offline       // a fetch error and no live data

    var label: String {
        switch self {
        case .live: return "LIVE"
        case .est: return "EST"
        case .stale: return "STALE"
        case .rateLimited: return "LIMITED"
        case .offline: return "OFFLINE"
        }
    }
    var isLive: Bool { self == .live }
}

// MARK: - Time-to-limit forecast

/// Project a 0…1 usage fraction forward along its recent slope and return a compact
/// "time to limit" string, but only when there is genuine upward movement AND the cap
/// would be reached before the window resets. Returns nil when there is nothing useful
/// to say, so the popover stays calm rather than showing noise.
func forecastToLimit(_ samples: [TimedSample], current: Double, resetAt: Date?, now: Date = Date()) -> String? {
    guard current < 0.999, current > 0 else { return nil }
    // Recent slice (last 90 min, or everything if that is too thin) reflects the current pace.
    let cutoff = now.addingTimeInterval(-90 * 60)
    let recent = samples.filter { $0.t >= cutoff }
    let pts = recent.count >= 3 ? recent : samples
    guard let first = pts.first, let last = pts.last else { return nil }
    let dt = last.t.timeIntervalSince(first.t)
    guard dt > 120 else { return nil }                 // need a real time span to trust a slope
    let slope = (last.v - first.v) / dt                // fraction per second
    guard slope > 1e-7 else { return nil }             // flat or shrinking → no ETA
    let secs = (1.0 - current) / slope
    guard secs > 0, secs < 21 * 86400 else { return nil }   // sane horizon (≤ ~3 weeks)
    if let r = resetAt, now.addingTimeInterval(secs) > r { return nil }   // resets before it would hit the cap
    return "~\(compactETA(secs)) to limit"
}

/// Numeric form of the projection: minutes until the cap at the recent slope, or nil (flat/shrinking/
/// resets-first). Used by the forecast alert to fire when the ETA drops under a threshold.
func forecastMinutes(_ samples: [TimedSample], current: Double, resetAt: Date?, now: Date = Date()) -> Double? {
    guard current < 0.999, current > 0 else { return nil }
    let cutoff = now.addingTimeInterval(-90 * 60)
    let recent = samples.filter { $0.t >= cutoff }
    let pts = recent.count >= 3 ? recent : samples
    guard let first = pts.first, let last = pts.last else { return nil }
    let dt = last.t.timeIntervalSince(first.t)
    guard dt > 120 else { return nil }
    let slope = (last.v - first.v) / dt
    guard slope > 1e-7 else { return nil }
    let secs = (1.0 - current) / slope
    guard secs > 0, secs < 21 * 86400 else { return nil }
    if let r = resetAt, now.addingTimeInterval(secs) > r { return nil }
    return secs / 60
}
