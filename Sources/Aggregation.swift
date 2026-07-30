import Foundation

// Foundation-pure usage aggregation: rolls raw per-call usage records up by model family,
// by project, and by day, with estimated cost via Pricing.swift's tokenCost. This is the
// shared basis for several features: attribution (#1),
// per-project (#2), history/trends (#6), export (#8), and the recap card (#9).
//
// Kept AppKit / Combine / SwiftUI free so the headless harness (run-aggregation-tests.sh)
// can compile it against the real Pricing rate table with no UI. The app's UsageEngine maps
// each parsed ~/.claude log Entry into a UsageRecord and feeds these functions; the
// aggregation never touches the log format directly.

/// One normalized usage record (the smallest unit the rollups consume).
struct UsageRecord {
    let date: Date
    let model: String
    /// Project / repo name (typically the last path component of the session cwd); "" if unknown.
    let project: String
    /// Conversation / session log file name (per-chat attribution); defaults to "" so existing
    /// call sites that do not pass it keep compiling.
    var session: String = ""
    let input: Int
    let output: Int
    let cache5m: Int
    let cache1h: Int
    let cacheRead: Int
}

extension UsageRecord {
    /// All billed tokens for this record (fresh input/output plus every cache bucket).
    var totalTokens: Int { input + output + cache5m + cache1h + cacheRead }
    /// Estimated USD cost, delegating to the shared Pricing table (Pricing.swift).
    var cost: Double {
        tokenCost(model: model, input: input, output: output,
                  cache5m: cache5m, cache1h: cache1h, cacheRead: cacheRead)
    }
}

/// A rollup bucket: summed totals for one slice of records (one model family, project, or day).
struct UsageRollup {
    var key: String
    var records = 0
    var input = 0
    var output = 0
    var cache5m = 0
    var cache1h = 0
    var cacheRead = 0
    var cost = 0.0

    var tokens: Int { input + output + cache5m + cache1h + cacheRead }
    var cacheTokens: Int { cache5m + cache1h + cacheRead }
    var freshTokens: Int { input + output }

    mutating func add(_ r: UsageRecord) {
        records += 1
        input += r.input;     output += r.output
        cache5m += r.cache5m; cache1h += r.cache1h; cacheRead += r.cacheRead
        cost += r.cost
    }
}

/// Coarse model family for attribution display (groups all Opus point releases together, etc.).
func modelFamily(_ model: String) -> String {
    let m = model.lowercased()
    if m.contains("opus")   { return "Opus" }
    if m.contains("sonnet") { return "Sonnet" }
    if m.contains("haiku")  { return "Haiku" }
    if m.contains("fable")  { return "Fable" }
    return "Other"
}

/// Group records by a key, returning rollups sorted by descending token total (biggest
/// spender first, the attribution order). Ties broken by key ascending for determinism.
func rollup(_ records: [UsageRecord], by key: (UsageRecord) -> String) -> [UsageRollup] {
    var map: [String: UsageRollup] = [:]
    for r in records {
        let k = key(r)
        var b = map[k] ?? UsageRollup(key: k)
        b.add(r)
        map[k] = b
    }
    return map.values.sorted { a, b in
        a.tokens != b.tokens ? a.tokens > b.tokens : a.key < b.key
    }
}

func rollupByModelFamily(_ records: [UsageRecord]) -> [UsageRollup] {
    rollup(records) { modelFamily($0.model) }
}

func rollupByProject(_ records: [UsageRecord]) -> [UsageRollup] {
    rollup(records) { $0.project.isEmpty ? "(unknown)" : $0.project }
}

func rollupBySession(_ records: [UsageRecord]) -> [UsageRollup] {
    rollup(records) { $0.session.isEmpty ? "(unknown)" : $0.session }
}

/// One conversation's total usage (a session log file), labeled by its actual title rather than
/// its folder, because most sessions run from the home directory and would otherwise all collapse
/// to "Home". This is what the Insights "Biggest chats" and "By project" views display.
struct SessionUsage {
    let id: String       // sessionId / file name
    let title: String    // customTitle / aiTitle / first user message / "(untitled chat)"
    let project: String  // clean name from the real cwd ("Home", "website", "research", ...)
    let date: Date       // last activity in the session
    let tokens: Int
    let cost: Double
}

/// A short, readable project name from a real cwd path. The home directory becomes "Home".
func cleanProjectName(cwd: String, home: String) -> String {
    if cwd.isEmpty { return "(unknown)" }
    if cwd == home { return "Home" }
    let last = (cwd as NSString).lastPathComponent
    return last.isEmpty ? cwd : last
}

/// Day key "YYYY-MM-DD" in the given calendar (default current). Stable for charts and export.
func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

/// Day rollups in chronological order (for trend charts and the heatmap), not token-sorted.
func rollupByDay(_ records: [UsageRecord], calendar: Calendar = .current) -> [UsageRollup] {
    rollup(records) { dayKey($0.date, calendar: calendar) }.sorted { $0.key < $1.key }
}

/// One rollup covering every record (the grand total), keyed "all".
func totals(_ records: [UsageRecord]) -> UsageRollup {
    var b = UsageRollup(key: "all")
    for r in records { b.add(r) }
    return b
}

/// Records whose date falls in [since, until). Used by the 24h / 7d / 30d windows.
func recordsInWindow(_ records: [UsageRecord], since: Date, until: Date) -> [UsageRecord] {
    records.filter { $0.date >= since && $0.date < until }
}

/// Last-7-days cost as 7 values normalized to the busiest day (0…1), oldest first, today last.
/// Powers the "This week" mini bar rhythm in the popover. Empty/quiet history → all zeros.
func dailyCostSpark(_ records: [UsageRecord], now: Date = Date(), cal: Calendar = .current) -> [Double] {
    let today = cal.startOfDay(for: now)
    var byDay = [Double](repeating: 0, count: 7)
    for r in records {
        let d = cal.startOfDay(for: r.date)
        if let days = cal.dateComponents([.day], from: d, to: today).day, days >= 0, days < 7 {
            byDay[6 - days] += r.cost
        }
    }
    let peak = byDay.max() ?? 0
    return peak > 0 ? byDay.map { $0 / peak } : byDay
}

/// The project that ate the most tokens within ±halfWidth of `t` - powers the burn chart's
/// hover forensics ("what caused this spike?"). Returns (project, tokens) or nil if quiet there.
func dominantProject(_ records: [UsageRecord], around t: Date, halfWidth: TimeInterval) -> (name: String, tok: Int)? {
    var byProject: [String: Int] = [:]
    for r in records where abs(r.date.timeIntervalSince(t)) <= halfWidth {
        byProject[r.project.isEmpty ? "unknown" : r.project, default: 0] += r.totalTokens
    }
    guard let top = byProject.max(by: { $0.value < $1.value }), top.value > 0 else { return nil }
    return (top.key, top.value)
}
