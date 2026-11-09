import Foundation

// The live usage model and its parsers, Foundation-pure (no AppKit / SwiftUI / Combine / network)
// so the headless harness (run-parse-tests.sh) can compile the REAL code that reads the usage
// service's JSON and the live cache. UsageEngine.swift owns the fetching, the token and the
// publishing; everything that turns bytes into numbers lives here.

// MARK: - Authoritative window state from the OAuth usage API

struct WindowState: Equatable {
    var pct: Double        // 0...1
    var resetAt: Date?
}

/// A per-model weekly limit from the usage API's `limits[]` array (kind == "weekly_scoped").
/// e.g. Fable 5 has its own weekly cap distinct from the all-models weekly cap. `active` marks the
/// limit that is currently the binding constraint (`is_active`).
struct ScopedLimit: Equatable, Identifiable {
    var label: String      // model display name, e.g. "Fable"
    var pct: Double        // 0...1 utilization
    var resetAt: Date?
    var active: Bool
    var severity: String   // "normal" / "warning" / "critical" ...
    var id: String { label }
    var remaining: Double { max(0, 1 - pct) }
}

/// Where the week's allowance went, per SURFACE, as the usage service reports it
/// (`seven_day_breakdown.rows`): Claude Code, Chats, Cowork, Other. `pct` is that surface's share
/// of the weekly limit, 0...1, so the rows add up to the weekly percentage, not to one.
struct SurfaceShare: Equatable, Identifiable {
    var key: String        // "claude_code" / "chat" / "cowork" / "other"
    var label: String      // "Claude Code" / "Chats" / "Cowork" / "Other"
    var pct: Double        // 0...1 of the WEEKLY limit
    var id: String { key }
}

/// Where the week's usage actually went, per model FAMILY, from the local logs. Unlike ScopedLimit
/// (which only exists for models Anthropic has given a separate weekly cap, e.g. Fable), this covers
/// EVERY model used - Opus, Sonnet, Haiku, Fable - since they all draw from the shared weekly pool.
/// `share` is this family's fraction of the week's total spend, so the bars read as "how much of my
/// week went here". Purely local + recomputed each scan, so it needs no cache persistence.
struct ModelUse: Equatable, Identifiable {
    var label: String      // family: "Opus" / "Sonnet" / "Haiku" / "Fable"
    var cost: Double       // this family's estimated weekly spend
    var share: Double      // 0...1 fraction of the week's total spend
    var id: String { label }
}

// MARK: - One parsed answer from the usage service (or from the live cache)

struct APIUsage: Equatable {
    var fiveHour: WindowState?
    var sevenDay: WindowState?
    var sevenDaySonnet: WindowState?
    var sevenDayOpus: WindowState?
    var modelLimits: [ScopedLimit] = []
    /// The service said, in so many words, that this account has no five-hour session limit:
    /// `five_hour` was null AND `limits[]` carried no session entry. Verified Ultra accounts
    /// (Max 20x until October 30, 2026) answer this way. It is a fact about the plan, not a
    /// window the response happened to omit, so the reader must not keep an older session.
    var sessionLimitAbsent: Bool = false
    /// The week by surface (Claude Code / Chats / Cowork / Other), when the service reports it.
    var weeklyBreakdown: [SurfaceShare] = []
    /// The one-line pace sentence claude.ai shows under the week ("On track. You should reach
    /// tomorrow's reset with room to spare."), when `pace` or `indicator` carries text.
    var pace: String? = nil
}

// MARK: - Snapshot the UI renders (live API fields + local-log supplements)

struct UsageSnapshot {
    // ── Local-log estimates / token counts (supplementary) ──
    var sessionFresh: Int = 0
    /// The floor used until enough real sessions have been observed to learn the true cap. Named,
    /// because "have we learned anything yet" is a question other code has to be able to ask, and
    /// comparing against a literal repeated at the asking site is how those two drift apart.
    static let defaultSessionCap = 1_000_000
    static let defaultWeeklyCap = 2_000_000
    var sessionCap: Int = defaultSessionCap
    var resetAt: Date? = nil
    var weeklyFresh: Int = 0
    var weeklyCap: Int = defaultWeeklyCap
    var weeklyCost: Double = 0
    var sessionCost: Double = 0
    var modelUsage: [ModelUse] = []   // per-family share of this week's spend (local; all models)
    var lastUpdated = Date(timeIntervalSince1970: 0)

    // ── Authoritative live data from api.anthropic.com/api/oauth/usage ──
    var apiSession: WindowState? = nil
    var apiWeekly: WindowState? = nil
    var apiSonnet: WindowState? = nil
    var apiOpus: WindowState? = nil
    var modelLimits: [ScopedLimit] = []   // per-model weekly caps from limits[] (e.g. Fable 5)
    /// True when the usage service said this plan has no five-hour session limit (verified
    /// Ultra). `apiSession` is nil then, and stays nil: an older session reading must never be
    /// carried forward into this state, which is how a stale "over limit" froze on the card.
    var sessionLimitAbsent: Bool = false
    var weeklyBreakdown: [SurfaceShare] = []   // the week by surface, when the service reports it
    var weeklyPace: String? = nil              // claude.ai's one-line pace sentence, when present
    var liveUpdated: Date? = nil
    var liveError: String? = nil
    /// When the app will try the usage service again after being rate limited. Nil when nothing is
    /// waiting. The badge says it out loud, because "we are backing off" is otherwise invisible and
    /// the numbers just look frozen.
    var liveRetryAt: Date? = nil
    var plan: String? = nil   // "Pro" / "Max" / "Ultra" - from the OAuth credential, for the header
    var accountEmail: String? = nil   // from the OAuth token-exchange `account`
    var accountOrg: String? = nil

    // ── Local fallbacks ──
    private var localSessionPct: Double {
        sessionCap > 0 ? min(1.0, Double(sessionFresh)/Double(sessionCap)) : 0
    }
    private var localWeeklyPct: Double {
        weeklyCap > 0 ? min(1.0, Double(weeklyFresh)/Double(weeklyCap)) : 0
    }

    // ── Effective values: prefer live, fall back to local estimate ──
    /// Live means the service answered: with a session window, or with the word that there is
    /// none and a weekly window in its place.
    var isLive: Bool { apiSession != nil || (sessionLimitAbsent && apiWeekly != nil) }
    var hasSessionLimit: Bool { !sessionLimitAbsent }
    /// Zero, not the local estimate, on a plan with no session limit: the local five-hour block
    /// is a reading of the logs, and showing it as a limit would invent a cap the plan does not have.
    var sessionPct: Double { apiSession?.pct ?? (sessionLimitAbsent ? 0 : localSessionPct) }
    var sessionResetAt: Date? { apiSession?.resetAt ?? (sessionLimitAbsent ? nil : resetAt) }
    var weeklyPct: Double { apiWeekly?.pct ?? localWeeklyPct }
    var weeklyResetAt: Date? { apiWeekly?.resetAt }
    var over: Bool { hasSessionLimit && sessionPct >= 1.0 }
    var weeklyOver: Bool { weeklyPct >= 1.0 }

    // ── The primary gauge: the session where the plan has one, the week where it does not ──
    // The menu bar, the ember line, the burn clock and the badge key on these, so a plan with
    // weekly limits only reads its week everywhere the session used to be, and a plan with both
    // reads exactly what it always did.
    var primaryPct: Double { sessionLimitAbsent ? weeklyPct : sessionPct }
    var primaryResetAt: Date? { sessionLimitAbsent ? weeklyResetAt : sessionResetAt }
    var primaryOver: Bool { sessionLimitAbsent ? weeklyOver : over }
    /// The length of the primary window, for countdown fractions (five hours or seven days).
    var primaryWindow: TimeInterval { sessionLimitAbsent ? 7 * 24 * 3600 : 5 * 3600 }

    mutating func copyLive(from o: UsageSnapshot) {
        apiSession = o.apiSession; apiWeekly = o.apiWeekly
        apiSonnet = o.apiSonnet; apiOpus = o.apiOpus; modelLimits = o.modelLimits
        sessionLimitAbsent = o.sessionLimitAbsent; weeklyBreakdown = o.weeklyBreakdown; weeklyPace = o.weeklyPace
        liveUpdated = o.liveUpdated; liveError = o.liveError; liveRetryAt = o.liveRetryAt; plan = o.plan
        accountEmail = o.accountEmail; accountOrg = o.accountOrg
    }
    mutating func copyLocal(from o: UsageSnapshot) {
        sessionFresh = o.sessionFresh; sessionCap = o.sessionCap; resetAt = o.resetAt
        weeklyFresh = o.weeklyFresh; weeklyCap = o.weeklyCap
        weeklyCost = o.weeklyCost; sessionCost = o.sessionCost
        modelUsage = o.modelUsage; lastUpdated = o.lastUpdated
    }

    /// Forget every live window (sign-out, or a reading that must not survive).
    mutating func clearLive() {
        apiSession = nil; apiWeekly = nil; apiSonnet = nil; apiOpus = nil; modelLimits = []
        sessionLimitAbsent = false; weeklyBreakdown = []; weeklyPace = nil
    }

    /// Take a parsed answer into the snapshot, keeping the last good reading for any window this
    /// answer did not carry.
    ///
    /// A response is a success when it parses, not when it is complete: the service can answer
    /// with the five-hour window and omit the per-model ones, and assigning the missing pieces
    /// straight through replaced real numbers with nothing. The reader watches a cap row vanish
    /// and reappear for no reason they can see. A window that is genuinely gone stays visible
    /// until the next full answer, which is the better of the two wrong states: stale beats
    /// absent, and liveUpdated already says how old the reading is.
    ///
    /// The one exception is a session the service has said does not exist. That is not a window
    /// the answer omitted, it is the plan, so the old session is dropped rather than kept: kept, it
    /// froze a stale "over limit" on the card for as long as the account stayed on Ultra.
    mutating func absorb(_ api: APIUsage) {
        if api.sessionLimitAbsent {
            apiSession = nil
            sessionLimitAbsent = true
        } else if let five = api.fiveHour {
            apiSession = five
            sessionLimitAbsent = false
        }
        apiWeekly = api.sevenDay ?? apiWeekly
        apiSonnet = api.sevenDaySonnet ?? apiSonnet
        apiOpus = api.sevenDayOpus ?? apiOpus
        if !api.modelLimits.isEmpty { modelLimits = api.modelLimits }
        if !api.weeklyBreakdown.isEmpty { weeklyBreakdown = api.weeklyBreakdown }
        if let pace = api.pace { weeklyPace = pace }
    }
}

// MARK: - Parsing the usage service's answer

/// Read one `{"utilization": 79.0, "resets_at": "..."}` window. Nil when the key is missing or null.
private func usageWindow(_ obj: [String: Any], _ key: String) -> WindowState? {
    guard let d = obj[key] as? [String: Any], let u = d["utilization"] as? Double else { return nil }
    return WindowState(pct: clampPct(u), resetAt: (d["resets_at"] as? String).flatMap(parseISO))
}

/// Turn the decoded JSON of `GET /api/oauth/usage` into an APIUsage. Nil when the shape carries
/// nothing we recognise, so a 200 with an unfamiliar body never zeroes the live windows or
/// overwrites a good cache: the last good numbers survive an API shape change until a build
/// understands the new one.
///
/// `limits[]` is the canonical source: session, all-models weekly, and per-model "weekly_scoped"
/// caps (e.g. Fable 5). The old seven_day_opus/sonnet top-level keys are now null, so scoped
/// limits MUST come from here. The top-level windows are still preferred when present, with
/// limits[] as the fallback should Anthropic null them too.
///
/// A null `five_hour` with no session entry in `limits[]` is the verified-Ultra shape: the
/// account has no five-hour limit at all. That is reported as `sessionLimitAbsent`, which the
/// snapshot treats as a fact about the plan rather than as a window to carry forward.
func parseUsageResponse(_ obj: [String: Any]) -> APIUsage? {
    var scoped: [ScopedLimit] = []
    var sessionFromLimits: WindowState?, weeklyFromLimits: WindowState?
    var sawLimits = false
    if let limits = obj["limits"] as? [[String: Any]] {
        sawLimits = true
        for l in limits {
            let pct = clampPct((l["percent"] as? Double) ?? 0)
            let reset = (l["resets_at"] as? String).flatMap(parseISO)
            switch l["kind"] as? String {
            case "session":     sessionFromLimits = WindowState(pct: pct, resetAt: reset)
            case "weekly_all":  weeklyFromLimits = WindowState(pct: pct, resetAt: reset)
            case "weekly_scoped":
                let name = ((l["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                if let name, !name.isEmpty {
                    scoped.append(ScopedLimit(label: name, pct: pct, resetAt: reset,
                                              active: (l["is_active"] as? Bool) ?? false,
                                              severity: (l["severity"] as? String) ?? "normal"))
                }
            default: break
            }
        }
    }
    let fiveHour = usageWindow(obj, "five_hour") ?? sessionFromLimits
    let sevenDay = usageWindow(obj, "seven_day") ?? weeklyFromLimits
    // "No session limit" has to be said by the service, not inferred from silence: the key must
    // be present (null counts), limits[] must be present without a session entry, and a weekly
    // window must exist. An answer with no five_hour key at all is an old or partial shape, and
    // is treated as "field missing, keep what we had", exactly as before.
    let fiveHourKeyPresent = obj.keys.contains("five_hour")
    let absent = fiveHour == nil && fiveHourKeyPresent && sawLimits && sessionFromLimits == nil && sevenDay != nil
    var breakdown: [SurfaceShare] = []
    if let bd = obj["seven_day_breakdown"] as? [String: Any], let rows = bd["rows"] as? [[String: Any]] {
        for r in rows {
            guard let key = r["key"] as? String, !key.isEmpty else { continue }
            let label = (r["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? key
            let pct = (r["percent"] as? Double) ?? (r["percent"] as? Int).map(Double.init) ?? 0
            breakdown.append(SurfaceShare(key: key, label: label, pct: clampPct(pct)))
        }
    }
    // `pace` and `indicator` are null today; should either start carrying text, keep it.
    func text(_ key: String) -> String? {
        if let s = obj[key] as? String, !s.isEmpty { return s }
        if let d = obj[key] as? [String: Any] {
            for k in ["text", "message", "summary", "label"] {
                if let s = d[k] as? String, !s.isEmpty { return s }
            }
        }
        return nil
    }
    let api = APIUsage(fiveHour: fiveHour, sevenDay: sevenDay,
                       sevenDaySonnet: usageWindow(obj, "seven_day_sonnet"), sevenDayOpus: usageWindow(obj, "seven_day_opus"),
                       modelLimits: scoped.sorted { $0.pct > $1.pct },
                       sessionLimitAbsent: absent, weeklyBreakdown: breakdown,
                       pace: text("pace") ?? text("indicator"))
    guard api.fiveHour != nil || api.sevenDay != nil || !api.modelLimits.isEmpty else { return nil }
    return api
}

// MARK: - The live cache (~/.config/burndown/live.json): percentages only, no secrets

/// The windows half of the cache, as the JSON object the engine writes. The engine adds the
/// account identity (plan, email, org) and the timestamp around it.
func encodeLiveCache(_ api: APIUsage) -> [String: Any] {
    let iso = ISO8601DateFormatter()
    func enc(_ w: WindowState?) -> [String: Any]? {
        guard let w else { return nil }
        var d: [String: Any] = ["utilization": w.pct * 100]
        if let r = w.resetAt { d["resets_at"] = iso.string(from: r) }
        return d
    }
    var root: [String: Any] = [:]
    if let v = enc(api.fiveHour) { root["five_hour"] = v }
    if let v = enc(api.sevenDay) { root["seven_day"] = v }
    if let v = enc(api.sevenDaySonnet) { root["seven_day_sonnet"] = v }
    if let v = enc(api.sevenDayOpus) { root["seven_day_opus"] = v }
    // Per-model weekly caps (limits[]) so Fable 5 etc. show instantly on relaunch, not blank.
    if !api.modelLimits.isEmpty {
        root["model_limits"] = api.modelLimits.map { m -> [String: Any] in
            var d: [String: Any] = ["label": m.label, "pct": m.pct, "active": m.active, "severity": m.severity]
            if let r = m.resetAt { d["resets_at"] = iso.string(from: r) }
            return d
        }
    }
    // The plan's word that there is no session limit is a fact worth a relaunch, like the
    // windows: without it the card would come up in estimate mode and draw a session gauge from
    // the local logs until the first fetch answered.
    if api.sessionLimitAbsent { root["session_limit_absent"] = true }
    if !api.weeklyBreakdown.isEmpty {
        root["seven_day_breakdown"] = api.weeklyBreakdown.map { r -> [String: Any] in
            ["key": r.key, "display_name": r.label, "percent": r.pct * 100]
        }
    }
    if let pace = api.pace { root["pace"] = pace }
    return root
}

/// Read the windows back from a cache object written by `encodeLiveCache`. Never nil: an empty
/// or foreign object simply yields no windows, and a cache that says the session limit is absent
/// comes back saying so, with no session window beside it whatever else the file holds.
func decodeLiveCache(_ obj: [String: Any]) -> APIUsage {
    var api = APIUsage()
    api.sessionLimitAbsent = (obj["session_limit_absent"] as? Bool) ?? false
    api.fiveHour = api.sessionLimitAbsent ? nil : usageWindow(obj, "five_hour")
    api.sevenDay = usageWindow(obj, "seven_day")
    api.sevenDaySonnet = usageWindow(obj, "seven_day_sonnet")
    api.sevenDayOpus = usageWindow(obj, "seven_day_opus")
    if let ml = obj["model_limits"] as? [[String: Any]] {
        api.modelLimits = ml.compactMap { d in
            guard let label = d["label"] as? String, let pct = d["pct"] as? Double else { return nil }
            return ScopedLimit(label: label, pct: pct, resetAt: (d["resets_at"] as? String).flatMap(parseISO),
                               active: (d["active"] as? Bool) ?? false, severity: (d["severity"] as? String) ?? "normal")
        }
    }
    if let rows = obj["seven_day_breakdown"] as? [[String: Any]] {
        api.weeklyBreakdown = rows.compactMap { r in
            guard let key = r["key"] as? String, let pct = r["percent"] as? Double else { return nil }
            return SurfaceShare(key: key, label: (r["display_name"] as? String) ?? key, pct: clampPct(pct))
        }
    }
    if let pace = obj["pace"] as? String, !pace.isEmpty { api.pace = pace }
    return api
}

// MARK: - Plan names

/// Map Anthropic tier/type identifiers to the plan's display name.
///
/// The names are the ones Anthropic has used since October 30, 2026: the plan that was "Max 20x"
/// is "Ultra" and the one that was "Max 5x" is simply "Max". The tier identifiers in the
/// credential did not change with the rename, so `default_claude_max_20x` still means Ultra.
/// Pro, Team and Enterprise read as they always did.
func planDisplayName(tier: String, type: String, sub: String?) -> String? {
    let t = tier.lowercased(), ty = type.lowercased()
    if t.contains("max_20x") || t.contains("ultra") || ty.contains("ultra") { return "Ultra" }
    if t.range(of: #"max_\d+x"#, options: .regularExpression) != nil { return "Max" }
    if ty.contains("max") || t.contains("max") { return "Max" }
    if ty.contains("enterprise") { return "Enterprise" }
    if ty.contains("team") { return "Team" }
    if ty.contains("pro") || t.contains("pro") { return "Pro" }
    if let s = sub, !s.isEmpty { return s.capitalized }
    return nil
}
