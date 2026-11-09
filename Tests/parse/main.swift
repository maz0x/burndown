import Foundation

// Golden-fixture tests for the REAL Foundation-pure parsers in Sources/Parsing.swift
// (compiled together by run-parse-tests.sh). No network, no token, no live API: hardcoded
// fixtures only. Reverting parseISO/clampPct in Parsing.swift must make these fail.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { print("  ok   \(msg)") } else { failures += 1; print("  FAIL \(msg)") }
}

print("parseISO:")
let base = parseISO("2026-06-26T12:00:00Z")
check(base != nil, "plain Z timestamp parses")
check(parseISO("2026-06-26T12:00:00.123456Z").map { abs($0.timeIntervalSince(base!)) < 0.001 } ?? false,
      "6-digit fractional seconds parse to the whole-second instant")
check(parseISO("2026-06-26T12:00:00+00:00").map { abs($0.timeIntervalSince(base!)) < 0.001 } ?? false,
      "+00:00 offset equals Z")
check(parseISO("2026-06-26T12:00:00-07:00").map { abs($0.timeIntervalSince(base!) - 7 * 3600) < 0.001 } ?? false,
      "-07:00 offset resolves 7h ahead in UTC")
check(parseISO("2026-06-26T12:00:00.500-07:00").map { abs($0.timeIntervalSince(base!) - 7 * 3600) < 0.001 } ?? false,
      "fractional seconds + offset resolve to the right instant")
check(parseISO("not-a-date") == nil, "garbage string -> nil")
check(parseISO("") == nil, "empty string -> nil")
check(parseISO("2026-13-99T99:99:99Z") == nil, "out-of-range components -> nil")

print("clampPct (utilization% -> 0...1):")
check(clampPct(0) == 0.0, "0% -> 0.0")
check(clampPct(100) == 1.0, "100% -> 1.0")
check(clampPct(137) == 1.0, "137% clamps to 1.0")
check(clampPct(-5) == 0.0, "-5% clamps to 0.0")
check(abs(clampPct(50) - 0.5) < 1e-12, "50% -> 0.5")
check(abs(clampPct(99.9) - 0.999) < 1e-12, "99.9% -> 0.999")

// fastISO8601Date must match the formatter to the integer second (the CPU fix must not corrupt dates).
func fmtParse(_ s: String) -> Date? {
    let a = ISO8601DateFormatter(); a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let b = ISO8601DateFormatter(); b.formatOptions = [.withInternetDateTime]
    return a.date(from: s) ?? b.date(from: s)
}
for c in ["2026-07-06T00:26:11Z", "2026-07-06T00:26:11.123Z", "2024-02-29T12:34:56Z", "2020-01-01T00:00:00Z", "2026-12-31T23:59:59.9Z"] {
    let fast = fastISO8601Date(c)!.timeIntervalSince1970
    let slow = floor(fmtParse(c)!.timeIntervalSince1970)
    check(abs(fast - slow) < 0.001, "fastISO8601Date matches formatter for \(c)")
}
check(fastISO8601Date("garbage") == nil, "fastISO8601Date rejects garbage")

// The fast path computes a UTC instant, so a stamp carrying a zone offset must not go through it.
// It used to read the first nineteen characters and ignore the rest, which turned a local
// wall-clock time into a UTC one and moved that record by the size of the offset: a whole evening
// of work could land on the wrong day. Returning nil hands it to the tolerant formatter, which
// does honour the offset.
print("zone offsets:")
check(fastISO8601Date("2026-08-09T10:00:00+05:00") == nil, "a positive offset is refused, not silently read as UTC")
check(fastISO8601Date("2026-08-09T10:00:00-07:00") == nil, "and a negative one")
check(fastISO8601Date("2026-08-09T10:00:00.123-07:00") == nil, "including with fractional seconds")
check(fastISO8601Date("2026-08-09T10:00:00Z") != nil, "a Z stamp still takes the fast path")
check(fastISO8601Date("2026-08-09T10:00:00.123Z") != nil, "and so does one with fractional seconds")
check(fastISO8601Date("2026-08-09T10:00:00") != nil, "and a bare stamp with no suffix at all")
// The tolerant path is what actually reads the offset, so prove the pair works end to end.
let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
if let viaFormatter = iso.date(from: "2026-08-09T10:00:00+05:00"),
   let utc = fastISO8601Date("2026-08-09T05:00:00Z") {
    check(abs(viaFormatter.timeIntervalSince(utc)) < 1, "and the fallback lands on the same instant, five hours earlier")
} else {
    check(false, "the tolerant formatter should parse an offset stamp")
}

// ── The usage service's answer (Sources/UsageParse.swift) ──
//
// The shape a verified Ultra account (Max 20x until October 30, 2026) gets from
// GET /api/oauth/usage, as recorded on 2026-11-06: five_hour is null, limits[] carries the weekly
// kinds only, and the week comes with a by-surface breakdown. No session kind anywhere.
let ultraJSON = """
{
  "five_hour": null,
  "seven_day": {"utilization": 79.0, "resets_at": "2026-11-07T21:00:00Z"},
  "seven_day_opus": null, "seven_day_sonnet": null,
  "limits": [
    {"kind":"weekly_all","group":"weekly","percent":79,"severity":"warning","resets_at":"2026-11-07T21:00:00Z","scope":null,"is_active":true},
    {"kind":"weekly_scoped","group":"weekly","percent":63,"severity":"normal","resets_at":"2026-11-07T20:59:59Z","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false}
  ],
  "seven_day_breakdown": {"as_of": "2026-11-06T18:00:00Z", "window_started_at": "2026-10-31T21:00:00Z",
    "rows": [{"key":"claude_code","display_name":"Claude Code","percent":91},{"key":"chat","display_name":"Chats","percent":0},
             {"key":"cowork","display_name":"Cowork","percent":9},{"key":"other","display_name":"Other","percent":0}]},
  "weekly_scoped_shares": [{"limit_index":1,"used_percent_of_weekly":32,"allowance_percent_of_weekly":50}],
  "pace": null, "indicator": null, "extra_usage": {}, "spend": {}
}
"""
func obj(_ json: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as? [String: Any]) ?? [:]
}

print("usage response, weekly limits only (verified Ultra):")
if let api = parseUsageResponse(obj(ultraJSON)) {
    check(api.sessionLimitAbsent, "five_hour null + no session in limits[] -> session limit reported absent")
    check(api.fiveHour == nil, "and no session window is invented for it")
    check(abs((api.sevenDay?.pct ?? -1) - 0.79) < 1e-9, "weekly is 79%")
    check(api.sevenDay?.resetAt == parseISO("2026-11-07T21:00:00Z"), "weekly reset parsed")
    check(api.modelLimits.count == 1 && api.modelLimits[0].label == "Fable", "the Fable scoped limit is the one scoped cap")
    check(abs((api.modelLimits.first?.pct ?? -1) - 0.63) < 1e-9, "and it is at 63%")
    check(api.modelLimits.first?.active == false, "it is not the binding limit")
    check(api.weeklyBreakdown.map { $0.key } == ["claude_code", "chat", "cowork", "other"], "the by-surface rows parse in order")
    check(api.weeklyBreakdown.map { $0.label } == ["Claude Code", "Chats", "Cowork", "Other"], "with their display names")
    check(abs((api.weeklyBreakdown.first?.pct ?? -1) - 0.91) < 1e-9, "Claude Code is 91% of the week")
    check(api.pace == nil, "a null pace stays nil")

    // The snapshot: a stale session reading from before the plan changed must NOT survive this
    // answer. That is the bug: the card sat at "over limit, 100%" for an account with no session.
    var snap = UsageSnapshot()
    snap.apiSession = WindowState(pct: 1.0, resetAt: parseISO("2026-11-06T10:00:00Z"))
    snap.absorb(api)
    check(snap.apiSession == nil, "absorbing it drops the stale session window")
    check(snap.sessionLimitAbsent, "and the snapshot says the session limit is absent")
    check(!snap.over, "so the card is not over limit")
    check(snap.isLive, "and still counts as live (the week is a live reading)")
    check(abs(snap.sessionPct) < 1e-9, "the session percent reads zero, not the local estimate")
    check(snap.sessionResetAt == nil, "with no session reset clock")
    check(abs(snap.primaryPct - 0.79) < 1e-9, "the primary gauge is the week")
    check(snap.primaryResetAt == api.sevenDay?.resetAt, "and its reset is the weekly reset")
    check(snap.primaryWindow == 7 * 24 * 3600, "over a seven-day window")

    // The live cache written from that state must come back as that state on relaunch.
    print("live cache round trip:")
    let cache = encodeLiveCache(api)
    check(cache["five_hour"] == nil, "the cache carries no session window")
    check((cache["session_limit_absent"] as? Bool) == true, "and records that the session limit is absent")
    var cold = UsageSnapshot()
    cold.absorb(decodeLiveCache(cache))
    check(cold.apiSession == nil, "a cold load does not resurrect a session window")
    check(cold.sessionLimitAbsent, "and comes up knowing there is none")
    check(abs(cold.weeklyPct - 0.79) < 1e-9, "weekly survives the round trip")
    check(cold.modelLimits.first?.label == "Fable" && abs((cold.modelLimits.first?.pct ?? -1) - 0.63) < 1e-9, "the Fable cap survives the round trip")
    check(cold.weeklyBreakdown.count == 4 && abs((cold.weeklyBreakdown.first?.pct ?? -1) - 0.91) < 1e-9, "the by-surface rows survive the round trip")
    // A cache from an OLDER build that recorded a session window AND is then marked absent (a
    // hand-merged or half-written file) must still not bring the session back.
    var mixed = cache
    mixed["five_hour"] = ["utilization": 100.0, "resets_at": "2026-11-06T10:00:00Z"]
    var fromMixed = UsageSnapshot(); fromMixed.absorb(decodeLiveCache(mixed))
    check(fromMixed.apiSession == nil && !fromMixed.over, "a cache marked absent ignores any session window beside it")
} else {
    check(false, "the weekly-only response parses")
}

// The fallback that already existed: a response whose top-level five_hour is null but whose
// limits[] carries a session entry still yields a session window from limits[].
print("usage response, session carried by limits[] only:")
let sessionInLimits = """
{
  "five_hour": null,
  "seven_day": null,
  "limits": [
    {"kind":"session","group":"session","percent":42,"severity":"normal","resets_at":"2026-11-06T20:00:00Z","scope":null,"is_active":true},
    {"kind":"weekly_all","group":"weekly","percent":17,"severity":"normal","resets_at":"2026-11-10T08:00:00Z","scope":null,"is_active":false}
  ]
}
"""
if let api = parseUsageResponse(obj(sessionInLimits)) {
    check(!api.sessionLimitAbsent, "a session entry in limits[] means the plan has a session limit")
    check(abs((api.fiveHour?.pct ?? -1) - 0.42) < 1e-9, "the session window comes from limits[] (42%)")
    check(api.fiveHour?.resetAt == parseISO("2026-11-06T20:00:00Z"), "with its reset")
    check(abs((api.sevenDay?.pct ?? -1) - 0.17) < 1e-9, "and so does the weekly (17%)")
    var snap = UsageSnapshot(); snap.absorb(api)
    check(snap.apiSession != nil && !snap.sessionLimitAbsent && snap.isLive, "the snapshot keeps a session gauge")
    check(abs(snap.primaryPct - 0.42) < 1e-9, "and the session stays the primary gauge")
} else {
    check(false, "the limits[]-only response parses")
}

// The Pro / Max shape: both windows present. Unchanged behaviour, including the merge rule that
// keeps a last-good window when a later answer omits it.
print("usage response, session and week (Pro / Max):")
let maxJSON = """
{"five_hour": {"utilization": 46.0, "resets_at": "2026-11-06T22:30:00Z"},
 "seven_day": {"utilization": 13.0, "resets_at": "2026-11-09T21:00:00Z"},
 "limits": [{"kind":"session","percent":46,"resets_at":"2026-11-06T22:30:00Z","is_active":true},
            {"kind":"weekly_all","percent":13,"resets_at":"2026-11-09T21:00:00Z","is_active":false}]}
"""
if let api = parseUsageResponse(obj(maxJSON)) {
    check(!api.sessionLimitAbsent && abs((api.fiveHour?.pct ?? -1) - 0.46) < 1e-9, "a present five_hour is a session limit (46%)")
    var snap = UsageSnapshot(); snap.absorb(api)
    check(snap.isLive && abs(snap.primaryPct - 0.46) < 1e-9, "live, with the session as the primary gauge")
    // An answer that drops the five_hour KEY entirely (old / partial shape) keeps the last session.
    if let partial = parseUsageResponse(obj("""
        {"seven_day": {"utilization": 14.0, "resets_at": "2026-11-09T21:00:00Z"}}
        """)) {
        snap.absorb(partial)
        check(snap.apiSession != nil && !snap.sessionLimitAbsent, "an answer with no five_hour key at all keeps the last session (field missing, not absent)")
        check(abs(snap.weeklyPct - 0.14) < 1e-9, "while the week it did carry moves on")
    } else { check(false, "the partial response parses") }
    // And the plan can change under a running app: the next answer says no session, so it goes.
    snap.absorb(parseUsageResponse(obj(ultraJSON))!)
    check(snap.apiSession == nil && snap.sessionLimitAbsent, "a later weekly-only answer clears the session it had")
    let cache = encodeLiveCache(api)
    var cold = UsageSnapshot(); cold.absorb(decodeLiveCache(cache))
    check(abs(cold.sessionPct - 0.46) < 1e-9 && !cold.sessionLimitAbsent, "the Max cache round-trips its session window")
} else {
    check(false, "the Pro / Max response parses")
}
check(parseUsageResponse(obj("{\"hello\": 1}")) == nil, "an unrecognised shape parses to nil (last good data is kept)")
check(parseUsageResponse(obj("{\"five_hour\": null, \"seven_day\": null, \"limits\": []}")) == nil,
      "nothing but nulls is not a weekly-only plan, it is an empty answer")

// Plan names since the October 30, 2026 rename.
print("plan names:")
check(planDisplayName(tier: "default_claude_max_20x", type: "", sub: "max") == "Ultra", "max_20x is Ultra")
check(planDisplayName(tier: "default_claude_max_5x", type: "", sub: "max") == "Max", "max_5x is Max")
check(planDisplayName(tier: "", type: "claude_max", sub: "max") == "Max", "a max type with no tier is Max")
check(planDisplayName(tier: "default_claude_pro", type: "claude_pro", sub: "pro") == "Pro", "Pro stays Pro")
check(planDisplayName(tier: "", type: "claude_team", sub: nil) == "Team", "Team stays Team")
check(planDisplayName(tier: "", type: "claude_enterprise", sub: nil) == "Enterprise", "Enterprise stays Enterprise")
check(planDisplayName(tier: "", type: "", sub: "max") == "Max", "the credential's subscription type alone reads as Max")
check(planDisplayName(tier: "", type: "", sub: nil) == nil, "nothing known -> nil")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
