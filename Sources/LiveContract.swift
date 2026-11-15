import Foundation

// Stable JSON contract for Burndown's live numbers (the CLI / JSON local API), so external
// tools (Raycast, Stream Deck, statuslines, scripts) can read a documented, versioned shape instead of
// scraping the UI. Foundation-pure (no AppKit / SwiftUI / Combine / network) so the headless harness
// (run-livecontract-tests.sh) can compile the real encode / decode round-trip with no UI.
//
// Contract notes:
//   schemaVersion starts at 1 and only bumps on a breaking change to the shape.
//   pct fields (sessionPct, weeklyPct, opusPct, sonnetPct) are fractions in 0..1, not percentages.
//   date strings (generatedAt, sessionResetAt, weeklyResetAt) are ISO8601.
//   optional fields are omitted only when nil per the Codable default; consumers should treat a missing
//   optional as "unknown", not zero.
//   sessionLimitAbsent is present (and true) only on a plan with a weekly limit and no five-hour
//   session. sessionPct is 0 and sessionResetAt is missing there, and without this field a consumer
//   could not tell that from a real 0%: read weeklyPct as the one limit instead.
//   modelLimits lists every model the plan caps separately (Fable, for example). opusPct and
//   sonnetPct are the older per-model fields; the service only fills them for some accounts.
//   Both fields are additions to schema 1: a consumer written before them keeps working.

/// One model with its own weekly cap, as the contract reports it.
struct BurndownLiveCap: Codable, Equatable {
    let label: String
    let pct: Double
    let resetAt: String?
}

/// The documented, versioned snapshot of Burndown's live numbers that the JSON API emits.
struct BurndownLive: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: String
    let plan: String?
    let sessionPct: Double
    let weeklyPct: Double
    let opusPct: Double?
    let sonnetPct: Double?
    let sessionResetAt: String?
    let weeklyResetAt: String?
    /// Tokens per minute over the last 60s, and the session's estimated API-list cost. Both are
    /// LIVE readings, so only the running app knows them: a cold `Burndown --json` reads a cache
    /// and correctly reports null for each rather than inventing a figure. Optional, so adding
    /// sessionCost does not break a consumer written against the original shape.
    let burnPerMin: Double?
    let sessionCost: Double?
    /// True on a plan with no five-hour session limit; omitted on every other plan.
    var sessionLimitAbsent: Bool? = nil
    /// The models this plan caps separately; omitted when there are none.
    var modelLimits: [BurndownLiveCap]? = nil
}

/// Encode a BurndownLive to a pretty-printed, sorted-keys UTF8 JSON string. Sorted keys make the output
/// byte-stable (good for diffs, caching, and statusline consumers); pretty-printing keeps it readable in
/// a terminal. Returns "{}" only in the (practically unreachable) case the encoder or UTF8 decode fails.
func encodeBurndownLive(_ live: BurndownLive) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(live),
          let json = String(data: data, encoding: .utf8) else { return "{}" }
    return json
}

/// Decode a BurndownLive from a JSON string (for round-trip tests and external consumers). Returns nil on
/// malformed JSON or a shape that does not match the contract.
func decodeBurndownLive(_ json: String) -> BurndownLive? {
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(BurndownLive.self, from: data)
}
