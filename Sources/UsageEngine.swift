import Foundation
import Combine
import CryptoKit

// MARK: - Model pricing
// Price, priceFor, and the pure tokenCost(...) live in Sources/Pricing.swift (headless-testable).

private struct Entry {
    let ts: Date
    let input, output, cache5m, cache1h, cacheRead: Int
    let model: String
    let project: String
    let session: String
    var freshTokens: Int { input + output + cache5m + cache1h }
    var cost: Double { tokenCost(model: model, input: input, output: output, cache5m: cache5m, cache1h: cache1h, cacheRead: cacheRead) }
}

private struct Block { var start: Date; var lastTs: Date; var fresh: Int = 0; var cost: Double = 0 }

// MARK: - Authoritative window state from the OAuth usage API

struct WindowState: Equatable {
    var pct: Double        // 0...1
    var resetAt: Date?
}

/// A per-model weekly limit from the usage API's new `limits[]` array (kind == "weekly_scoped").
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

// MARK: - Snapshot the UI renders (live API fields + local-log supplements)

struct UsageSnapshot {
    // ── Local-log estimates / token counts (supplementary) ──
    var sessionFresh: Int = 0
    var sessionCap: Int = 1_000_000
    var resetAt: Date? = nil
    var weeklyFresh: Int = 0
    var weeklyCap: Int = 2_000_000
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
    var liveUpdated: Date? = nil
    var liveError: String? = nil
    var plan: String? = nil   // "Pro" / "Max" - from the OAuth credential, for the header
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
    var isLive: Bool { apiSession != nil }
    var sessionPct: Double { apiSession?.pct ?? localSessionPct }
    var sessionResetAt: Date? { apiSession?.resetAt ?? resetAt }
    var weeklyPct: Double { apiWeekly?.pct ?? localWeeklyPct }
    var weeklyResetAt: Date? { apiWeekly?.resetAt }
    var over: Bool { sessionPct >= 1.0 }
    var weeklyOver: Bool { weeklyPct >= 1.0 }

    mutating func copyLive(from o: UsageSnapshot) {
        apiSession = o.apiSession; apiWeekly = o.apiWeekly
        apiSonnet = o.apiSonnet; apiOpus = o.apiOpus; modelLimits = o.modelLimits
        liveUpdated = o.liveUpdated; liveError = o.liveError; plan = o.plan
        accountEmail = o.accountEmail; accountOrg = o.accountOrg
    }
    mutating func copyLocal(from o: UsageSnapshot) {
        sessionFresh = o.sessionFresh; sessionCap = o.sessionCap; resetAt = o.resetAt
        weeklyFresh = o.weeklyFresh; weeklyCap = o.weeklyCap
        weeklyCost = o.weeklyCost; sessionCost = o.sessionCost
        modelUsage = o.modelUsage; lastUpdated = o.lastUpdated
    }
}

private let FIVE_HOURS: TimeInterval = 5 * 3600
private let WEEK: TimeInterval = 7 * 24 * 3600

// MARK: - OAuth usage API constants
private let USAGE_URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
private let OAUTH_BETA = "oauth-2025-04-20"
private let CLIENT_UA = "claude-code/2.0.0"   // required prefix; without it → 429s
private let KEYCHAIN_SERVICE = "Claude Code-credentials"
private let OAUTH_CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"  // Claude Code public client
private let TOKEN_URL = URL(string: "https://api.anthropic.com/v1/oauth/token")!

// Task.detached requires Sendable captures. UsageEngine is main-confined by discipline: every
// mutation of its published state happens through a DispatchQueue.main hop - the exact contract
// the GCD version ran under, which dispatch closures simply never type-checked. Asserted here,
// not compiler-checked; keep the main-hop rule when touching the fetch paths.
extension UsageEngine: @unchecked Sendable {}

final class UsageEngine: ObservableObject {
    @Published var snapshot = UsageSnapshot()
    @Published var ready = false
    @Published var refreshAnchor = Date()   // when the current refresh cycle started (drives the LIVE countdown)
    /// The refresh heartbeat GATE. Bumped ONLY when a refresh succeeded AND it actually
    /// changed what is displayed (a rendered numeral differs after rounding, or session/week moved
    /// at least 0.5 points), and never within 5s of the last beat. A silent refresh is silent; a
    /// failed refresh never fakes a pulse. The countdown ring refills off `refreshAnchor` regardless.
    @Published private(set) var heartbeat: Int = 0
    private var lastBeatAt: Date = .distantPast
    private var lastBeatSession: Double = -1
    private var lastBeatWeekly: Double = -1

    private func considerHeartbeat(_ s: UsageSnapshot, succeeded: Bool) {
        guard succeeded else { return }                                  // never fake a pulse on stale data
        let moved = abs(s.sessionPct - lastBeatSession) >= 0.005         // 0.5 percentage points
                 || abs(s.weeklyPct - lastBeatWeekly) >= 0.005
        let renumbered = Int((s.sessionPct * 100).rounded()) != Int((max(0, lastBeatSession) * 100).rounded())
                      || Int((s.weeklyPct * 100).rounded()) != Int((max(0, lastBeatWeekly) * 100).rounded())
        guard moved || renumbered else { return }                        // a silent refresh is silent
        guard Date().timeIntervalSince(lastBeatAt) >= OneShot.heartbeat else { return }   // the second is swallowed
        lastBeatAt = Date(); lastBeatSession = s.sessionPct; lastBeatWeekly = s.weeklyPct
        heartbeat &+= 1
    }
    @Published var refreshPeriod: Double = 30   // current effective refresh interval (adapts to activity)
    // Normalized per-call usage records (last ~30d) + the active 5h block start, feeding the
    // attribution / per-project / history / export / recap features.
    @Published var records: [UsageRecord] = []
    @Published var activeBlockStart: Date? = nil
    @Published var apiSpend = APISpend()     // developer API account spend (separate from the subscription)
    private var lastAPIFetch = Date(timeIntervalSince1970: 0)

    private let projectsDir: URL
    private let configURL: URL
    private let cacheURL: URL          // live percentages cache (no secrets)
    private var cap = 1_000_000
    private var weeklyCap = 2_000_000
    private var liveBackoffUntil: Date? = nil   // set on 429; skip fetches until then
    private var liveBackoffStep = 0
    private var lastLiveFetch = Date(timeIntervalSince1970: 0)
    private let minLiveInterval: TimeInterval = 20   // never poll the OAuth endpoint faster than this

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        projectsDir = home.appendingPathComponent(".claude/projects")
        configURL = home.appendingPathComponent(".config/burndown/config.json")
        cacheURL = home.appendingPathComponent(".config/burndown/live.json")
        loadLiveCache()
        apiSpend.configured = APIAccount.loadKey() != nil
    }

    // MARK: - Developer API account (optional, additive; never affects the subscription gauges)

    /// Refresh developer-API spend from the Admin Cost Report API. Only runs when an Admin key is
    /// saved. Throttled to 5 min (the data is daily-granularity, ~5 min fresh) unless `force`.
    func refreshAPISpend(force: Bool = false) {
        guard let key = APIAccount.loadKey() else {
            if apiSpend.configured { DispatchQueue.main.async { self.apiSpend = APISpend() } }
            return
        }
        if !force, Date().timeIntervalSince(lastAPIFetch) < 300 { return }
        lastAPIFetch = Date()
        Task.detached(priority: .utility) { [weak self] in
            let s = await APIAccount.fetchSpend(adminKey: key)
            DispatchQueue.main.async { self?.apiSpend = s }
        }
    }

    /// Save an Admin key, verify it against the live API, and report success (key kept only if it works).
    func setAdminKey(_ raw: String, completion: @escaping (Bool, String?) -> Void) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        Task.detached(priority: .userInitiated) { [weak self] in
            let s = await APIAccount.fetchSpend(adminKey: key)
            DispatchQueue.main.async {
                if s.error == nil {
                    APIAccount.saveKey(key)
                    self?.lastAPIFetch = Date()
                    self?.apiSpend = s
                    completion(true, nil)
                } else {
                    completion(false, s.error)   // do not save a key that failed
                }
            }
        }
    }

    func clearAdminKey() {
        APIAccount.clearKey()
        apiSpend = APISpend()
    }

    // QA: synchronously compute and print session/weekly + per-calendar-day cost,
    // to validate against ccusage's daily table (same-window comparison).
    func cliDump() {
        let now = Date()
        let entries = loadEntries(since: now.addingTimeInterval(-30 * 24 * 3600))
        let blocks = Self.buildBlocks(entries)
        let activeStart = blocks.last.flatMap { now < $0.start.addingTimeInterval(FIVE_HOURS) ? $0.start : nil }
        let newCap = resolveCap(blocks: blocks, excludingStart: activeStart)
        let newWeekly = resolveWeeklyCap(entries: entries, now: now)
        let snap = Self.computeSnapshot(entries: entries, cap: newCap, weeklyCap: newWeekly, now: now)
        print(String(format: "session: $%.2f  (%d fresh tokens)", snap.sessionCost, snap.sessionFresh))
        print(String(format: "weekly:  $%.2f  (%d fresh tokens)", snap.weeklyCost, snap.weeklyFresh))
        // Per calendar day (local), to line up with ccusage's daily rows.
        let cal = Calendar.current
        var byDay: [Date: Double] = [:]
        for e in entries { byDay[cal.startOfDay(for: e.ts), default: 0] += e.cost }
        let f = DateFormatter(); f.dateFormat = "MM-dd"
        print("by day:")
        for k in byDay.keys.sorted() where k >= now.addingTimeInterval(-8 * 86400) {
            print(String(format: "  %@  $%.2f", f.string(from: k), byDay[k]!))
        }
    }

    // MARK: - Local-log refreshes (token counts + cost)

    /// How many days of per-call records to keep for the day-scale charts. Follows the Day span
    /// setting (7/14/30/90) so a 90-day chart actually has 90 days behind it. The limit math never
    /// depends on this; it always derives from its own fixed windows.
    var recordDays: Int = 30

    func fullScan() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let entries = self.loadEntries(since: Date().addingTimeInterval(-Double(max(30, self.recordDays)) * 24 * 3600))
            let blocks = Self.buildBlocks(entries)
            let now = Date()
            let activeStart = blocks.last.flatMap { now < $0.start.addingTimeInterval(FIVE_HOURS) ? $0.start : nil }
            let newCap = self.resolveCap(blocks: blocks, excludingStart: activeStart)
            let newWeekly = self.resolveWeeklyCap(entries: entries, now: now)
            let snap = Self.computeSnapshot(entries: entries, cap: newCap, weeklyCap: newWeekly, now: now)
            DispatchQueue.main.async {
                self.cap = newCap; self.weeklyCap = newWeekly
                var s = snap; s.copyLive(from: self.snapshot)
                self.snapshot = s; self.ready = true
                self.records = Self.recordsFrom(entries)
                self.activeBlockStart = activeStart
            }
        }
    }

    private var refreshInFlight = false   // coalesce: never pile up overlapping full-week log scans
    func quickRefresh() {
        if refreshInFlight { return }     // a scan is already running; the next tick will catch up
        refreshInFlight = true
        let cap = self.cap, weeklyCap = self.weeklyCap
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let scanStart = Date().addingTimeInterval(-WEEK - FIVE_HOURS)
            let entries = self.loadEntries(since: scanStart)
            let snap = Self.computeSnapshot(entries: entries, cap: cap, weeklyCap: weeklyCap, now: Date())
            let now2 = Date()
            let activeStart = Self.buildBlocks(entries).last.flatMap { now2 < $0.start.addingTimeInterval(FIVE_HOURS) ? $0.start : nil }
            DispatchQueue.main.async {
                var s = snap; s.copyLive(from: self.snapshot)
                self.snapshot = s; self.ready = true
                // MERGE the fresh window into the record store instead of replacing it: the quick
                // scan only covers ~7 days, and overwriting would snap every 14/30/90-day chart
                // back to a week of data until the next deep scan.
                let tail = self.records.filter { $0.date < scanStart }
                self.records = tail + Self.recordsFrom(entries)
                self.activeBlockStart = activeStart
                self.refreshInFlight = false
            }
        }
    }

    /// One-off FULL-history scan (all ~/.claude logs, not just the live 30-day window), off the
    /// main thread, for the Insights all-time per-project and lifetime views. Heavier than the
    /// live refresh, so it runs only when the Insights window opens. The logs already hold the
    /// complete past, so this is fully retroactive and non-intrusive (read-only).
    func scanAllUsage(completion: @escaping ([UsageRecord], [SessionUsage]) -> Void) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { DispatchQueue.main.async { completion([], []) }; return }
            let (recs, sessions) = self.scanFilesSync()
            DispatchQueue.main.async { completion(recs, sessions) }
        }
    }

    private static func jsonLine(_ line: String) -> [String: Any]? {
        guard let d = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
    private static func firstUserText(_ o: [String: Any]) -> String? {
        guard let m = o["message"] as? [String: Any] else { return nil }
        if let s = m["content"] as? String { return s }
        if let arr = m["content"] as? [[String: Any]] {
            for b in arr where (b["type"] as? String) == "text" { return b["text"] as? String }
        }
        return nil
    }

    /// Full-history scan over every ~/.claude session log. Per file it sums usage into UsageRecords
    /// AND captures the conversation title (customTitle / aiTitle / first user message) + real cwd,
    /// emitting one SessionUsage. Read-only; runs off the live path (only when Insights opens).
    func scanFilesSync() -> ([UsageRecord], [SessionUsage]) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: projectsDir, includingPropertiesForKeys: nil,
                                         options: [.skipsHiddenFiles]) else { return ([], []) }
        var records: [UsageRecord] = []
        var sessions: [SessionUsage] = []
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter(); isoNoFrac.formatOptions = [.withInternetDateTime]
        for case let url as URL in walker {
            guard url.pathExtension == "jsonl" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let proj = Self.projectName(url)
            let sid = url.deletingPathExtension().lastPathComponent
            var fileRecs: [UsageRecord] = []
            var customTitle: String?; var aiTitle: String?; var firstUser: String?; var cwd: String?
            var maxTs = Date(timeIntervalSince1970: 0)
            var seen = Set<String>()
            text.enumerateLines { line, _ in
                if cwd == nil, line.contains("\"cwd\""), let o = Self.jsonLine(line) { cwd = o["cwd"] as? String }
                if line.contains("\"customTitle\""), let o = Self.jsonLine(line),
                   let t = (o["customTitle"] as? String), !t.isEmpty { customTitle = t }
                else if line.contains("\"aiTitle\""), let o = Self.jsonLine(line),
                        let t = (o["aiTitle"] as? String), !t.isEmpty { aiTitle = t }
                if firstUser == nil, line.contains("\"type\":\"user\""), let o = Self.jsonLine(line) { firstUser = Self.firstUserText(o) }
                guard line.contains("\"usage\"") else { return }
                guard let o = Self.jsonLine(line),
                      let tsStr = o["timestamp"] as? String,
                      let message = o["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else { return }
                guard let ts = fastISO8601Date(tsStr) ?? iso.date(from: tsStr) ?? isoNoFrac.date(from: tsStr) else { return }
                if let id = message["id"] as? String {
                    let key = id + ":" + ((o["requestId"] as? String) ?? "")
                    if seen.contains(key) { return }; seen.insert(key)
                }
                let cc = usage["cache_creation"] as? [String: Any]
                let totalCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
                let c5 = (cc?["ephemeral_5m_input_tokens"] as? Int)
                let c1 = (cc?["ephemeral_1h_input_tokens"] as? Int) ?? 0
                fileRecs.append(UsageRecord(
                    date: ts, model: (message["model"] as? String) ?? "unknown", project: proj, session: sid,
                    input: (usage["input_tokens"] as? Int) ?? 0, output: (usage["output_tokens"] as? Int) ?? 0,
                    cache5m: c5 ?? (cc == nil ? totalCreate : 0), cache1h: c1,
                    cacheRead: (usage["cache_read_input_tokens"] as? Int) ?? 0))
                if ts > maxTs { maxTs = ts }
            }
            records.append(contentsOf: fileRecs)
            guard !fileRecs.isEmpty else { continue }
            let agg = totals(fileRecs)
            var title = (customTitle ?? aiTitle ?? firstUser ?? "(untitled chat)")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            while title.hasPrefix(">") { title.removeFirst() }
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { title = "(untitled chat)" }
            if title.count > 80 { title = String(title.prefix(80)) + "\u{2026}" }
            sessions.append(SessionUsage(id: sid, title: title,
                                         project: cleanProjectName(cwd: cwd ?? "", home: home),
                                         date: maxTs, tokens: agg.tokens, cost: agg.cost))
        }
        return (records, sessions)
    }

    // MARK: - Live API fetch (authoritative %)

    /// Forget our private refreshed token, re-bootstrap from the Claude Code login
    /// (Keychain / ~/.claude credentials), and report success/failure so the UI can
    /// give the user real feedback. Backs the settings "Re-authenticate…" button.
    func reauthenticate(completion: @escaping (Bool) -> Void) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/burndown/token.json")
        try? FileManager.default.removeItem(at: url)
        liveBackoffUntil = nil; liveBackoffStep = 0
        lastLiveFetch = Date(timeIntervalSince1970: 0)
        logPlanFields()                       // refresh the plan name from the credential too
        fetchLive(force: true, completion: completion)
    }

    // MARK: - In-app OAuth sign-in (PKCE) - no Terminal needed
    // Flow (matches Claude Code's public client): open claude.ai/oauth/authorize in the
    // browser → user approves → Anthropic shows a "code#state" string → user pastes it →
    // we exchange it for tokens at the OAuth token endpoint and store them privately.

    private var pendingVerifier: String?

    /// Have we stored our own OAuth token (i.e., the user signed in)?
    func isSignedIn() -> Bool {
        FileManager.default.fileExists(atPath: Self.tokenStore().path)
    }

    /// Forget the stored token and clear live data → back to the signed-out state. Also revokes the
    /// CLI-borrow consent (via .burndownDidSignOut → settings), truncates the diagnostic log, and
    /// clears the published identity, so signing out actually stops everything and stays stopped.
    func signOut() {
        try? FileManager.default.removeItem(at: Self.tokenStore())
        try? FileManager.default.removeItem(at: cacheURL)
        Self.cliBootstrapAllowed = false
        Self.truncateDebugLog()
        var s = snapshot
        s.apiSession = nil; s.apiWeekly = nil; s.apiSonnet = nil; s.apiOpus = nil; s.modelLimits = []
        s.liveUpdated = nil; s.liveError = nil; s.plan = nil
        s.accountEmail = nil; s.accountOrg = nil
        snapshot = s
        NotificationCenter.default.post(name: .burndownDidSignOut, object: nil)
    }

    private static func b64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// Build the authorize URL and remember the PKCE verifier for the exchange.
    func signInURL() -> URL? {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Self.b64url(Data(bytes))
        pendingVerifier = verifier
        let challenge = Self.b64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        var c = URLComponents(string: "https://claude.ai/oauth/authorize")!
        c.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "client_id", value: OAUTH_CLIENT_ID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: "https://console.anthropic.com/oauth/code/callback"),
            .init(name: "scope", value: "org:create_api_key user:profile user:inference"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: verifier),
        ]
        return c.url
    }

    /// Exchange the pasted "code#state" for tokens; on success, refresh everything.
    func completeSignIn(_ pasted: String, completion: @escaping (Bool) -> Void) {
        guard let verifier = pendingVerifier else { completion(false); return }
        let t = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = t.split(separator: "#", maxSplits: 1).map(String.init)
        let code = parts.first ?? t
        let state = parts.count > 1 ? parts[1] : verifier
        Task.detached(priority: .userInitiated) { [weak self] in
            let body: [String: Any] = ["grant_type": "authorization_code", "code": code, "state": state,
                                       "client_id": OAUTH_CLIENT_ID,
                                       "redirect_uri": "https://console.anthropic.com/oauth/code/callback",
                                       "code_verifier": verifier]
            var ok = false
            for u in ["https://api.anthropic.com/v1/oauth/token", "https://console.anthropic.com/v1/oauth/token"] {
                if let url = URL(string: u), let tok = await Self.postTokenJSON(url, body) { Self.saveStored(tok); ok = true; break }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if ok {
                    self.pendingVerifier = nil
                    self.liveBackoffUntil = nil; self.liveBackoffStep = 0
                    self.lastLiveFetch = Date(timeIntervalSince1970: 0)
                    // Completing sign-in IS opting in to live usage: without this, a fresh install
                    // (usageAPI off) would guard out the first fetch and report a successful
                    // exchange as a failed code. The notification persists the setting.
                    self.usageEnabled = true
                    NotificationCenter.default.post(name: .burndownDidSignIn, object: nil)
                    self.logPlanFields()
                    self.publishAccount()
                    self.fetchLive(force: true) { live in completion(live) }
                } else { completion(false) }
            }
        }
    }

    // async (was a DispatchSemaphore.wait over dataTask): the request suspends instead of parking
    // a GCD worker thread for up to 18s. The URLRequest timeout still bounds the wait.
    private static func postTokenJSON(_ url: URL, _ body: [String: Any]) async -> Tok? {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(CLIENT_UA, forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
            dbg("signin@\(url.host ?? "")=0"); return nil
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200,
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let a = o["access_token"] as? String else {
            // Only an ERROR body may be logged. Reaching here with a 200 means the response
            // parsed as something other than the expected token pair, so the body is still
            // the credential; the log is written for users to paste into a public issue.
            if code == 200 {
                dbg("signin@\(url.host ?? "")=200 but the body was not a token pair")
            } else if let b = String(data: data, encoding: .utf8) {
                dbg("signin@\(url.host ?? "")=\(code) \(b.prefix(120))")
            } else { dbg("signin@\(url.host ?? "")=\(code)") }
            return nil
        }
        let rt = (o["refresh_token"] as? String) ?? ""
        let exp = Date().timeIntervalSince1970 * 1000 + (((o["expires_in"] as? Double) ?? 28800) * 1000)
        let scopes = (o["scopes"] as? [String]) ?? (o["scope"] as? String).map { $0.split(separator: " ").map(String.init) } ?? []
        let acct = o["account"] as? [String: Any]
        let email = (acct?["email_address"] as? String) ?? (acct?["emailAddress"] as? String) ?? (acct?["email"] as? String)
        let org = (o["organization"] as? [String: Any])?["name"] as? String
        return Tok(access: a, refresh: rt, expMs: exp, scopes: scopes, email: email, org: org)
    }

    var usageEnabled = true   // opt-in gate: when false, we never call the OAuth usage API (estimate-only mode)

    /// Diagnostics only (Account window drawer): when the stored private token expires.
    /// Reads the token file on call; never exposes the token itself.
    var tokenExpiry: Date? { Self.loadStored().map { Date(timeIntervalSince1970: $0.expMs / 1000) } }

    func fetchLive(force: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard usageEnabled else { completion?(false); return }   // user has not opted into the live usage API
        if !force, let until = liveBackoffUntil, Date() < until { completion?(false); return }   // honor 429 backoff (manual bypasses)
        // Decouple the OAuth poll from the (possibly 2s) UI refresh - the endpoint
        // rate-limits hard. Manual refresh (force) bypasses the floor.
        if !force, Date().timeIntervalSince(lastLiveFetch) < minLiveInterval { completion?(false); return }
        lastLiveFetch = Date()
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let result = await Self.queryUsageAPI()
            let freshPlan = Self.planFromClaudeJson()   // live plan/tier, independent of the token
            DispatchQueue.main.async {
                var s = self.snapshot
                if let freshPlan { s.plan = freshPlan }   // pick up plan upgrades (5x→20x) without a restart
                var ok = false
                switch result {
                case .success(let api):
                    s.apiSession = api.fiveHour
                    s.apiWeekly = api.sevenDay
                    s.apiSonnet = api.sevenDaySonnet
                    s.apiOpus = api.sevenDayOpus
                    s.modelLimits = api.modelLimits
                    s.liveUpdated = Date()
                    s.liveError = nil
                    self.liveBackoffStep = 0
                    self.liveBackoffUntil = nil
                    self.writeLiveCache(api)
                    ok = true
                case .failure(let e):
                    s.liveError = e.text       // keep last-good apiSession/Weekly visible
                    if e.text == "rate limited" {
                        self.liveBackoffStep = min(self.liveBackoffStep + 1, 4)
                        let delay = 60.0 * pow(2.0, Double(self.liveBackoffStep - 1))  // 60,120,240,480s
                        self.liveBackoffUntil = Date().addingTimeInterval(delay)
                    }
                }
                self.snapshot = s
                self.ready = true
                self.considerHeartbeat(s, succeeded: ok)   // heartbeat gate: only a real data change counts
                completion?(ok)
            }
        }
    }

    private struct APIUsage {
        var fiveHour: WindowState?
        var sevenDay: WindowState?
        var sevenDaySonnet: WindowState?
        var sevenDayOpus: WindowState?
        var modelLimits: [ScopedLimit] = []
    }

    private struct LiveError: Error { let text: String }

    // Non-secret diagnostics (never the token) to help debug auth/endpoint issues.
    // Private to the user (0600) and size-capped: past ~2 MB the file is cut back to its last
    // quarter, so it can never grow without bound on a user's machine.
    private static func dbg(_ s: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/burndown/live-debug.log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = ISO8601DateFormatter().string(from: Date()) + " " + s + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
           size > 2_000_000, let all = try? Data(contentsOf: url) {
            try? all.suffix(all.count / 4).write(to: url)
        }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: url)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Empty the diagnostic log (sign-out, or the Settings reset).
    static func truncateDebugLog() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/burndown/live-debug.log")
        try? Data().write(to: url)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func queryUsageAPI() async -> Result<APIUsage, LiveError> {
        guard var token = await ensureAccessToken() else { dbg("token=unavailable"); return .failure(LiveError(text: "no token")) }
        var (code, data) = await callUsage(token)
        if code == 401 {                          // token rejected → force one refresh + retry
            dbg("usage=401 forcing refresh")
            if let s = loadStored(), let r = await refresh(s) { saveStored(r); token = r.access; (code, data) = await callUsage(token) }
        }
        if code != 200 { dbg("usage=\(code)") }   // quiet in steady state
        guard code == 200, let data = data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(LiveError(text: code == 429 ? "rate limited" : "http \(code)"))
        }
        func win(_ key: String) -> WindowState? {
            guard let d = obj[key] as? [String: Any], let u = d["utilization"] as? Double else { return nil }
            return WindowState(pct: clampPct(u), resetAt: (d["resets_at"] as? String).flatMap(parseISO))
        }
        // The new `limits[]` array is the canonical source: session, all-models weekly, and per-model
        // "weekly_scoped" caps (e.g. Fable 5). The old seven_day_opus/sonnet top-level keys are now
        // null, so scoped limits MUST come from here.
        var scoped: [ScopedLimit] = []
        var sessionFromLimits: WindowState?, weeklyFromLimits: WindowState?
        if let limits = obj["limits"] as? [[String: Any]] {
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
        // Prefer the (still-present) top-level windows; fall back to limits[] if Anthropic nulls them too.
        let api = APIUsage(fiveHour: win("five_hour") ?? sessionFromLimits,
                           sevenDay: win("seven_day") ?? weeklyFromLimits,
                           sevenDaySonnet: win("seven_day_sonnet"), sevenDayOpus: win("seven_day_opus"),
                           modelLimits: scoped.sorted { $0.pct > $1.pct })
        // A 200 whose shape we no longer recognize must NOT zero the live windows and overwrite the
        // good cache: treat "parsed nothing meaningful" as a soft failure so the last
        // good numbers survive an API shape change until a build understands the new shape.
        guard api.fiveHour != nil || api.sevenDay != nil || !api.modelLimits.isEmpty else {
            dbg("usage=200 but unrecognized shape; keeping last good data")
            return .failure(LiveError(text: "unexpected response"))
        }
        return .success(api)
    }

    private static func callUsage(_ token: String) async -> (Int, Data?) {
        var req = URLRequest(url: USAGE_URL, timeoutInterval: 12)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(OAUTH_BETA, forHTTPHeaderField: "anthropic-beta")
        req.setValue(CLIENT_UA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return (0, nil) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code != 200, let b = String(data: data, encoding: .utf8) { dbg("usageBody=\(b.prefix(140))") }
        return (code, data)
    }

    // MARK: - OAuth token manager
    // Reads the CLI credential ONCE to bootstrap, then maintains its own private
    // refreshed token at ~/.config/burndown/token.json (chmod 600).
    // Never writes back to the Keychain. Token never logged.

    private struct Tok { var access: String; var refresh: String; var expMs: Double; var scopes: [String]; var plan: String? = nil; var email: String? = nil; var org: String? = nil }

    private static func tokenStore() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/burndown/token.json")
    }

    private static func loadStored() -> Tok? {
        guard let d = try? Data(contentsOf: tokenStore()),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let a = o["access_token"] as? String, let r = o["refresh_token"] as? String else { return nil }
        return Tok(access: a, refresh: r, expMs: (o["expires_at"] as? Double) ?? 0,
                   scopes: (o["scopes"] as? [String]) ?? [],
                   email: o["email"] as? String, org: o["org"] as? String)
    }

    private static func saveStored(_ t: Tok) {
        var o: [String: Any] = ["access_token": t.access, "refresh_token": t.refresh,
                                "expires_at": t.expMs, "scopes": t.scopes]
        if let e = t.email { o["email"] = e }
        if let g = t.org { o["org"] = g }
        let url = tokenStore()
        // Private from birth: 0700 directory, and the file is CREATED with 0600 (no window where
        // a default-permission file exists before a later chmod). Keychain storage is queued for
        // the Developer ID build; an ad-hoc identity changes every rebuild and would re-prompt.
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        if let d = try? JSONSerialization.data(withJSONObject: o) {
            FileManager.default.createFile(atPath: url.path, contents: d,
                                           attributes: [.posixPermissions: 0o600])
        }
    }

    /// Email/org are returned only in the OAuth token-exchange response - capture them
    /// there (or fall back to Claude Code's ~/.claude.json oauthAccount).
    private static func readClaudeJsonAccount() -> (String?, String?) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let d = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let acct = o["oauthAccount"] as? [String: Any] else { return (nil, nil) }
        let email = (acct["emailAddress"] as? String) ?? (acct["email_address"] as? String) ?? (acct["email"] as? String)
        let org = (acct["organizationName"] as? String) ?? (acct["organization_name"] as? String)
        return (email, org)
    }

    /// Derive the plan label from the LIVE ~/.claude.json oauthAccount, which reflects the account
    /// currently signed into Claude Code/Desktop. This is authoritative. The Keychain
    /// "subscriptionType" can be a stale, dead credential from an older CLI login (it can stay
    /// frozen on "pro" after an account is upgraded to Max), so we prefer this source.
    static func planFromClaudeJson() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let d = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let acct = o["oauthAccount"] as? [String: Any] else { return nil }
        let tier = (acct["organizationRateLimitTier"] as? String)
            ?? (acct["userRateLimitTier"] as? String) ?? ""
        let type = (acct["organizationType"] as? String) ?? ""
        return planLabel(tier: tier, type: type, sub: acct["subscriptionType"] as? String)
    }

    /// Map Anthropic tier/type identifiers to a display label: "Max 5×", "Max", "Team", "Pro"…
    static func planLabel(tier: String, type: String, sub: String?) -> String? {
        let t = tier.lowercased(), ty = type.lowercased()
        // "…max_5x" / "…max_20x" → "Max 5×"
        if let r = t.range(of: #"max_(\d+)x"#, options: .regularExpression) {
            let mult = t[r].replacingOccurrences(of: "max_", with: "").replacingOccurrences(of: "x", with: "")
            return "Max \(mult)×"
        }
        if ty.contains("max") || t.contains("max") { return "Max" }
        if ty.contains("enterprise") { return "Enterprise" }
        if ty.contains("team") { return "Team" }
        if ty.contains("pro") || t.contains("pro") { return "Pro" }
        if let s = sub, !s.isEmpty { return s.capitalized }
        return nil
    }

    /// Publish the signed-in identity (email/org) to the snapshot for the Account UI.
    func publishAccount() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var email = Self.loadStored()?.email
            var org = Self.loadStored()?.org
            if email == nil { let a = Self.readClaudeJsonAccount(); email = a.0; org = org ?? a.1 }
            DispatchQueue.main.async {
                guard let self else { return }
                var s = self.snapshot; s.accountEmail = email; s.accountOrg = org; self.snapshot = s
            }
        }
    }

    /// Consent gate for borrowing Claude Code's credential. Set from settings.borrowCLI at startup
    /// and on change. When false, the app NEVER reads ~/.claude/.credentials.json or the CLI's
    /// Keychain item, so sign-out sticks and a fresh install touches nothing without permission.
    static var cliBootstrapAllowed = false

    private static func ensureAccessToken() async -> String? {
        let now = Date().timeIntervalSince1970 * 1000
        if let s = loadStored() {
            if s.expMs > now + 60_000 { return s.access }
            if let r = await refresh(s) { saveStored(r); dbg("refresh=ok(stored)"); return r.access }
            dbg("refresh=failed(stored)")
        }
        guard cliBootstrapAllowed else { dbg("bootstrap=disabled(no consent)"); return nil }
        guard let kc = readKeychainCreds() else { dbg("bootstrap=no-creds"); return nil }
        // Use the CLI's credential only while its access token is still valid. Spending the CLI's
        // refresh token would rotate it and could invalidate the user's own Claude Code login, so
        // when it expires we surface the sign-in cue instead of refreshing on its behalf.
        if kc.expMs > now + 60_000 { saveStored(kc); return kc.access }
        dbg("bootstrap=cli-token-expired (not spending the CLI refresh token)")
        return nil
    }

    private static func refresh(_ t: Tok) async -> Tok? {
        guard !t.refresh.isEmpty else { return nil }
        var req = URLRequest(url: TOKEN_URL, timeoutInterval: 12)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Minimal body only. Sending `scope` or an `anthropic-version` header on the refresh
        // grant makes Anthropic reject it with invalid_grant - that was the real cause of the
        // token dying every time the 8h access token expired. Verified: this minimal form works.
        let body: [String: Any] = ["grant_type": "refresh_token", "client_id": OAUTH_CLIENT_ID,
                                   "refresh_token": t.refresh, "expires_in": 28800]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
            dbg("refreshHTTP=0"); return nil
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200,
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let a = o["access_token"] as? String else {
            // Same rule as the sign-in path: a 200 body here is the rotated token pair.
            if code == 200 {
                dbg("refreshHTTP=200 but the body was not a token pair")
            } else if let b = String(data: data, encoding: .utf8) {
                dbg("refreshHTTP=\(code) body=\(b.prefix(140))")
            } else { dbg("refreshHTTP=\(code)") }
            return nil
        }
        let rt = (o["refresh_token"] as? String) ?? t.refresh
        let exp = Date().timeIntervalSince1970 * 1000 + (((o["expires_in"] as? Double) ?? 28800) * 1000)
        return Tok(access: a, refresh: rt, expMs: exp, scopes: t.scopes)
    }

    /// Is a Claude Code sign-in present on this Mac? Presence check only: the credential file's
    /// existence, or the Keychain item's existence (no -w, so the secret itself is never read).
    static func cliSignInPresent() -> Bool {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if FileManager.default.fileExists(atPath: file.path) { return true }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", KEYCHAIN_SERVICE]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private static func readKeychainCreds() -> Tok? {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: file), let t = parseCreds(data) { return t }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { dbg("keychain=launch-failed"); return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { dbg("keychain=exit\(p.terminationStatus)"); return nil }
        return parseCreds(data)
    }

    private static func parseCreds(_ data: Data) -> Tok? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { dbg("parseCreds=not-json"); return nil }
        let inner = (obj["claudeAiOauth"] as? [String: Any]) ?? obj
        dbg("parseCreds keys=[\(inner.keys.sorted().joined(separator: ","))] sub=\((inner["subscriptionType"] as? String) ?? "nil") tier=\((inner["rateLimitTier"] as? String) ?? "nil") hasToken=\(inner["accessToken"] != nil)")
        guard let a = inner["accessToken"] as? String, !a.isEmpty else { return nil }
        let exp = (inner["expiresAt"] as? Double) ?? (inner["expiresAt"] as? Int).map(Double.init) ?? 0
        var plan: String? = nil
        if let sub = inner["subscriptionType"] as? String, !sub.isEmpty {
            plan = sub.capitalized   // "max" → "Max"
            if let tier = inner["rateLimitTier"] as? String,
               let r = tier.range(of: #"\d+x"#, options: .regularExpression) {
                plan! += " " + tier[r].replacingOccurrences(of: "x", with: "×")   // "Max 20×"
            }
        }
        return Tok(access: a, refresh: (inner["refreshToken"] as? String) ?? "", expMs: exp,
                   scopes: (inner["scopes"] as? [String]) ?? [], plan: plan)
    }

    /// One-shot: read the Keychain credential for the plan name (no rotation) and publish it.
    func logPlanFields() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // Prefer the live account record; fall back to the Keychain credential only if absent.
            let jsonPlan = Self.planFromClaudeJson()
            let plan = jsonPlan ?? Self.readKeychainCreds()?.plan
            Self.dbg("logPlanFields plan=\(plan ?? "nil") json=\(jsonPlan ?? "nil")")
            guard let plan else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                var s = self.snapshot; s.plan = plan; self.snapshot = s
            }
        }
    }

    // MARK: - Live cache (percentages only, for resilience + instant first paint)

    private func writeLiveCache(_ api: APIUsage) {
        func enc(_ w: WindowState?) -> [String: Any]? {
            guard let w else { return nil }
            var d: [String: Any] = ["utilization": w.pct * 100]
            if let r = w.resetAt { d["resets_at"] = ISO8601DateFormatter().string(from: r) }
            return d
        }
        var root: [String: Any] = ["updated": ISO8601DateFormatter().string(from: Date())]
        if let v = enc(api.fiveHour) { root["five_hour"] = v }
        if let v = enc(api.sevenDay) { root["seven_day"] = v }
        if let v = enc(api.sevenDaySonnet) { root["seven_day_sonnet"] = v }
        if let v = enc(api.sevenDayOpus) { root["seven_day_opus"] = v }
        // Per-model weekly caps (limits[]) so Fable 5 etc. show instantly on relaunch, not blank.
        if !api.modelLimits.isEmpty {
            root["model_limits"] = api.modelLimits.map { m -> [String: Any] in
                var d: [String: Any] = ["label": m.label, "pct": m.pct, "active": m.active, "severity": m.severity]
                if let r = m.resetAt { d["resets_at"] = ISO8601DateFormatter().string(from: r) }
                return d
            }
        }
        // Persist the account identity too (no secrets) so the menu + Account window are instant on
        // relaunch instead of waiting on a network fetch (which caused lag + a growing/relocating window).
        if let pl = snapshot.plan { root["plan"] = pl }
        if let em = snapshot.accountEmail { root["email"] = em }
        if let og = snapshot.accountOrg { root["org"] = og }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: root, options: .prettyPrinted) {
            try? data.write(to: cacheURL)
            // Owner-only: this now holds account email/org/plan. Keep it private even though it lives
            // in a local (non-synced) ~/.config path, matching how the token file is locked down.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
        }
        writeBurndownContract()
    }

    /// Tokens/min over the last 60s, pushed in by the app layer (which owns LiveActivity).
    /// The engine cannot compute it: it is a streaming reading, not a cumulative API figure.
    var liveBurnPerMin: Double = 0

    /// Stable machine-readable contract for external tools (Raycast / Stream Deck / scripts /
    /// statuslines): mirrors the live numbers into ~/.config/burndown/burndown-live.json
    /// using the versioned BurndownLive shape (Sources/LiveContract.swift).
    private func writeBurndownContract() {
        let iso = ISO8601DateFormatter()
        let live = BurndownLive(
            schemaVersion: 1,
            generatedAt: iso.string(from: Date()),
            plan: snapshot.plan,
            sessionPct: snapshot.sessionPct,
            weeklyPct: snapshot.weeklyPct,
            opusPct: snapshot.apiOpus?.pct,
            sonnetPct: snapshot.apiSonnet?.pct,
            sessionResetAt: snapshot.sessionResetAt.map { iso.string(from: $0) },
            weeklyResetAt: snapshot.weeklyResetAt.map { iso.string(from: $0) },
            burnPerMin: liveBurnPerMin > 0 ? liveBurnPerMin : nil,
            sessionCost: snapshot.sessionCost > 0 ? snapshot.sessionCost : nil
        )
        let url = cacheURL.deletingLastPathComponent().appendingPathComponent("burndown-live.json")
        try? encodeBurndownLive(live).data(using: .utf8)?.write(to: url)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func loadLiveCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        func win(_ key: String) -> WindowState? {
            guard let d = obj[key] as? [String: Any], let u = d["utilization"] as? Double else { return nil }
            return WindowState(pct: clampPct(u), resetAt: (d["resets_at"] as? String).flatMap(parseISO))
        }
        snapshot.apiSession = win("five_hour")
        snapshot.apiWeekly = win("seven_day")
        snapshot.apiSonnet = win("seven_day_sonnet")
        snapshot.apiOpus = win("seven_day_opus")
        if let ml = obj["model_limits"] as? [[String: Any]] {
            snapshot.modelLimits = ml.compactMap { d in
                guard let label = d["label"] as? String, let pct = d["pct"] as? Double else { return nil }
                return ScopedLimit(label: label, pct: pct, resetAt: (d["resets_at"] as? String).flatMap(parseISO),
                                   active: (d["active"] as? Bool) ?? false, severity: (d["severity"] as? String) ?? "normal")
            }
        }
        if let pl = obj["plan"] as? String { snapshot.plan = pl }
        if let em = obj["email"] as? String { snapshot.accountEmail = em }
        if let og = obj["org"] as? String { snapshot.accountOrg = og }
        // Restore the cache's own age: without it, a relaunch shows hours-old numbers
        // under a fresh LIVE badge. With it, the existing stale threshold engages immediately.
        snapshot.liveUpdated = (obj["updated"] as? String).flatMap(parseISO)
    }

    // MARK: - Local cap resolution

    private func resolveCap(blocks: [Block], excludingStart: Date?) -> Int {
        if let o = configuredCap("sessionCap"), o > 0 { return o }
        let prior = blocks.filter { $0.start != excludingStart && $0.fresh > 50_000 }.map { $0.fresh }.sorted()
        guard !prior.isEmpty else { return 1_000_000 }
        return max(1_000_000, prior[Int((Double(prior.count - 1) * 0.90).rounded())])
    }

    private func resolveWeeklyCap(entries: [Entry], now: Date) -> Int {
        if let o = configuredCap("weeklyCap"), o > 0 { return o }
        let cal = Calendar.current
        var byDay: [Date: Int] = [:]
        for e in entries { byDay[cal.startOfDay(for: e.ts), default: 0] += e.freshTokens }
        guard let firstDay = byDay.keys.min() else { return 2_000_000 }
        let today = cal.startOfDay(for: now)
        var sums: [Int] = []
        var end = cal.date(byAdding: .day, value: 6, to: firstDay)!
        while end < today {
            var s = 0
            for k in 0..<7 { if let day = cal.date(byAdding: .day, value: -k, to: end) { s += byDay[day] ?? 0 } }
            sums.append(s); end = cal.date(byAdding: .day, value: 1, to: end)!
        }
        let prior = sums.filter { $0 > 100_000 }.sorted()
        guard !prior.isEmpty else { return 2_000_000 }
        return max(2_000_000, prior[Int((Double(prior.count - 1) * 0.90).rounded())])
    }

    private func configuredCap(_ key: String) -> Int? {
        guard let data = try? Data(contentsOf: configURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cap = obj[key] as? Int else { return nil }
        return cap
    }

    // MARK: - Local snapshot computation

    private static func computeSnapshot(entries: [Entry], cap: Int, weeklyCap: Int, now: Date) -> UsageSnapshot {
        var snap = UsageSnapshot()
        snap.sessionCap = cap
        snap.weeklyCap = weeklyCap
        let blocks = buildBlocks(entries)
        if let active = blocks.last, now < active.start.addingTimeInterval(FIVE_HOURS) {
            snap.sessionFresh = active.fresh
            snap.sessionCost = active.cost
            snap.resetAt = active.start.addingTimeInterval(FIVE_HOURS)
        }
        let weekAgo = now.addingTimeInterval(-WEEK)
        var byFamily: [String: Double] = [:]
        for e in entries where e.ts >= weekAgo {
            snap.weeklyFresh += e.freshTokens
            snap.weeklyCost += e.cost
            byFamily[modelFamily(e.model), default: 0] += e.cost
        }
        // Per-model share of the week (all models, not just the API-capped ones). Sorted biggest
        // first; ties broken by name for determinism. Drops zero/negative-cost families.
        let total = byFamily.values.reduce(0, +)
        snap.modelUsage = byFamily
            .filter { $0.value > 0 }
            .map { ModelUse(label: $0.key, cost: $0.value, share: total > 0 ? $0.value / total : 0) }
            .sorted { $0.cost != $1.cost ? $0.cost > $1.cost : $0.label < $1.label }
        snap.lastUpdated = now
        return snap
    }

    private static func buildBlocks(_ entries: [Entry]) -> [Block] {
        guard !entries.isEmpty else { return [] }
        let sorted = entries.sorted { $0.ts < $1.ts }
        var blocks: [Block] = []
        func floorHour(_ d: Date) -> Date {
            Date(timeIntervalSinceReferenceDate: (d.timeIntervalSinceReferenceDate / 3600).rounded(.down) * 3600)
        }
        for e in sorted {
            if var last = blocks.last,
               e.ts < last.start.addingTimeInterval(FIVE_HOURS),
               e.ts.timeIntervalSince(last.lastTs) < FIVE_HOURS {
                last.fresh += e.freshTokens; last.cost += e.cost; last.lastTs = e.ts
                blocks[blocks.count - 1] = last
            } else {
                var b = Block(start: floorHour(e.ts), lastTs: e.ts)
                b.fresh = e.freshTokens; b.cost = e.cost
                blocks.append(b)
            }
        }
        return blocks
    }

    private static func recordsFrom(_ entries: [Entry]) -> [UsageRecord] {
        entries.map {
            UsageRecord(date: $0.ts, model: $0.model, project: $0.project,
                        session: $0.session, input: $0.input, output: $0.output,
                        cache5m: $0.cache5m, cache1h: $0.cache1h, cacheRead: $0.cacheRead)
        }
    }

    /// The ~/.claude/projects/<dir> folder a log file belongs to (the project key for attribution).
    private static func projectName(_ url: URL) -> String {
        let parts = url.pathComponents
        if let i = parts.firstIndex(of: "projects"), i + 1 < parts.count { return parts[i + 1] }
        return ""
    }

    // Per-file parsed-entry cache. loadEntries used to re-read and re-parse EVERY file modified in the
    // last week, in full, on every call - and it is called every ~2s while active, so on a heavy user
    // it pegged a background core. Now each file's parsed entries are cached by (mod-date, size); an
    // unchanged file is skipped entirely, so only the one or two files actually being written get
    // re-parsed. Keyed items carry the dedup key so cross-file de-duplication still happens at merge.
    // `offset` = bytes already parsed (a line boundary); `size` = file size at last scan (for the
    // unchanged check). A grown file is read from `offset` only; the trailing partial line is left
    // for the next scan.
    private struct FileEntries { let mod: Date; let size: UInt64; let offset: UInt64; let items: [(entry: Entry, key: String)] }
    private var entryCache: [String: FileEntries] = [:]
    private let entryCacheLock = NSLock()
    private static let usageNeedle = Data("\"usage\"".utf8)

    /// Parse the usage lines out of a byte buffer (only lines whose bytes contain the usage needle are
    /// decoded, so huge tool-output lines cost a memchr). Returns the parsed items and how many bytes
    /// were consumed up to the last complete line (the trailing partial line is not consumed).
    private static func parseUsageBytes(_ data: Data, project: String, session: String,
                                        _ iso: ISO8601DateFormatter, _ isoNoFrac: ISO8601DateFormatter) -> (items: [(Entry, String)], consumed: UInt64) {
        var items: [(Entry, String)] = []
        for lineData in data.split(separator: 0x0A, omittingEmptySubsequences: false) {
            guard lineData.range(of: Self.usageNeedle) != nil, let line = String(data: lineData, encoding: .utf8),
                  let ld = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: ld) as? [String: Any],
                  let tsStr = obj["timestamp"] as? String,
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let ts = fastISO8601Date(tsStr) ?? iso.date(from: tsStr) ?? isoNoFrac.date(from: tsStr) else { continue }
            let key = (message["id"] as? String).map { $0 + ":" + ((obj["requestId"] as? String) ?? "") } ?? ""
            let cc = usage["cache_creation"] as? [String: Any]
            let totalCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
            let c5 = (cc?["ephemeral_5m_input_tokens"] as? Int)
            let c1 = (cc?["ephemeral_1h_input_tokens"] as? Int) ?? 0
            items.append((Entry(
                ts: ts,
                input: (usage["input_tokens"] as? Int) ?? 0,
                output: (usage["output_tokens"] as? Int) ?? 0,
                cache5m: c5 ?? (cc == nil ? totalCreate : 0),   // no breakdown → treat as 5m
                cache1h: c1,
                cacheRead: (usage["cache_read_input_tokens"] as? Int) ?? 0,
                model: (message["model"] as? String) ?? "unknown",
                project: project, session: session), key))
        }
        // Consume only through the last newline; a trailing partial line is re-read next scan.
        let consumed: UInt64
        if let lastNL = data.lastIndex(of: 0x0A) { consumed = UInt64(data.distance(from: data.startIndex, to: lastNL) + 1) }
        else { consumed = 0 }
        return (items, consumed)
    }

    // QA (CUB_SCAN_SELFTEST): prove the delta read counts identically to a full read, on the REAL
    // logs. For each file: parse it whole, then parse it in two chunks split at a byte boundary
    // exactly the way the incremental scanner would (chunk 1 to its last newline, chunk 2 from there),
    // and assert the token totals + entry counts match. This is the correctness guarantee for the
    // partial-line / offset handling.
    static func scanSelfTest() -> String {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter(); isoNoFrac.formatOptions = [.withInternetDateTime]
        guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return "no projects dir" }
        var files = 0, mismatches = 0, tFull = 0, tDelta = 0, cFull = 0, cDelta = 0
        for case let url as URL in walker {
            guard url.pathExtension == "jsonl", let all = try? Data(contentsOf: url), all.count > 4 else { continue }
            files += 1
            let full = parseUsageBytes(all, project: "p", session: "s", iso, isoNoFrac).items
            let mid = all.count / 2
            let (i1, consumed1) = parseUsageBytes(Data(all[0..<mid]), project: "p", session: "s", iso, isoNoFrac)
            let (i2, _) = parseUsageBytes(Data(all[Int(consumed1)..<all.count]), project: "p", session: "s", iso, isoNoFrac)
            let delta = i1 + i2
            let ff = full.reduce(0) { $0 + $1.0.freshTokens }, fd = delta.reduce(0) { $0 + $1.0.freshTokens }
            tFull += ff; tDelta += fd; cFull += full.count; cDelta += delta.count
            if ff != fd || full.count != delta.count { mismatches += 1 }
        }
        let ok = tFull == tDelta && cFull == cDelta && mismatches == 0
        return "files=\(files) fullTokens=\(tFull) deltaTokens=\(tDelta) fullCount=\(cFull) deltaCount=\(cDelta) mismatches=\(mismatches) -> \(ok ? "PASS" : "FAIL")"
    }

    private func loadEntries(since: Date) -> [Entry] {
        entryCacheLock.lock(); defer { entryCacheLock.unlock() }
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: projectsDir,
                                         includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                         options: [.skipsHiddenFiles]) else { return [] }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter(); isoNoFrac.formatOptions = [.withInternetDateTime]
        var live = Set<String>()
        for case let url as URL in walker {
            guard url.pathExtension == "jsonl" else { continue }
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let mod = vals?.contentModificationDate else { continue }
            let size = UInt64(vals?.fileSize ?? 0)
            let path = url.path; live.insert(path)
            let cached = entryCache[path]
            if let c = cached, c.mod == mod, c.size == size { continue }   // unchanged → reuse cache
            if mod < since, cached == nil { continue }                     // old + never parsed → skip
            let project = Self.projectName(url)
            let session = url.deletingPathExtension().lastPathComponent
            // Read only the appended bytes when the file only grew; otherwise (new / shrank / rotated)
            // read the whole thing.
            let base = (cached != nil && size >= cached!.offset) ? cached!.offset : 0
            var items = base > 0 ? cached!.items : []
            guard let h = try? FileHandle(forReadingFrom: url) else {
                entryCache[path] = FileEntries(mod: mod, size: size, offset: base, items: items); continue
            }
            try? h.seek(toOffset: base)
            let data = h.readDataToEndOfFile(); try? h.close()
            let (newItems, consumed) = Self.parseUsageBytes(data, project: project, session: session, iso, isoNoFrac)
            items.append(contentsOf: newItems)
            entryCache[path] = FileEntries(mod: mod, size: size, offset: base + consumed, items: items)
        }
        entryCache = entryCache.filter { live.contains($0.key) }   // drop deleted files
        // Merge cached items, de-duped by message id (identical copies, so order is irrelevant), filtered by `since`.
        var seen = Set<String>(); var out: [Entry] = []
        for (_, fe) in entryCache {
            for (e, key) in fe.items where e.ts >= since {
                if !key.isEmpty { if seen.contains(key) { continue }; seen.insert(key) }
                out.append(e)
            }
        }
        return out
    }
}

// MARK: - ISO8601 parse tolerant of 6-digit fractional seconds + offset

// parseISO + clampPct now live in Sources/Parsing.swift (Foundation-pure, headless-testable).
