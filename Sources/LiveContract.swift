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
    let burnPerMin: Double?
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
