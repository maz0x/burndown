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
        let snap = Self.computeSnapshot(entries: entries, cap: newCap, weeklyCap: newWeekly, now: now,
                                        weeklyResetAt: self.snapshot.weeklyResetAt)
        print(String(format: "session: $%.2f  (%ld fresh tokens)", snap.sessionCost, snap.sessionFresh))
        print(String(format: "weekly:  $%.2f  (%ld fresh tokens)", snap.weeklyCost, snap.weeklyFresh))
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
        // Read every piece of shared state on the caller's thread, the way quickRefresh does.
        // recordDays is written by the settings sink on main, and reading it from the background
        // closure is a plain unsynchronized cross-thread read of a value the user can change at any
        // moment. prevWeeklyReset is the same story: it belongs to the published snapshot.
        let days = max(30, self.recordDays)
        let prevWeeklyReset = self.snapshot.weeklyResetAt
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let entries = self.loadEntries(since: Date().addingTimeInterval(-Double(days) * 24 * 3600))
            let blocks = Self.buildBlocks(entries)
            let now = Date()
            let activeStart = blocks.last.flatMap { now < $0.start.addingTimeInterval(FIVE_HOURS) ? $0.start : nil }
            let newCap = self.resolveCap(blocks: blocks, excludingStart: activeStart)
            let newWeekly = self.resolveWeeklyCap(entries: entries, now: now)
            let snap = Self.computeSnapshot(entries: entries, cap: newCap, weeklyCap: newWeekly, now: now,
                                            weeklyResetAt: prevWeeklyReset)
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
    /// The same coalescing for the full-history scan, plus everyone waiting on the one in flight.
    /// Both are touched only on the main thread (scanAllUsage is called from the Insights window).
    private var scanInFlight = false
    private var scanWaiters: [([UsageRecord], [SessionUsage]) -> Void] = []
    func quickRefresh() {
        if refreshInFlight { return }     // a scan is already running; the next tick will catch up
        refreshInFlight = true
        let cap = self.cap, weeklyCap = self.weeklyCap
        let prevWeeklyReset2 = self.snapshot.weeklyResetAt
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let scanStart = Date().addingTimeInterval(-WEEK - FIVE_HOURS)
            let entries = self.loadEntries(since: scanStart)
            let snap = Self.computeSnapshot(entries: entries, cap: cap, weeklyCap: weeklyCap, now: Date(),
                                            weeklyResetAt: prevWeeklyReset2)
            let now2 = Date()
            let activeStart = Self.buildBlocks(entries).last.flatMap { now2 < $0.start.addingTimeInterval(FIVE_HOURS) ? $0.start : nil }
            // Built here, not on main. This maps a week of parsed entries into records, and it ran
            // inside the main-thread block below on every live tick: a couple of seconds apart,
            // forever, on the thread that also has to draw. The filter that follows it stays on
            // main because it reads the published store, and one pass over that array is cheap
            // next to building this one.
            let fresh = Self.recordsFrom(entries)
            DispatchQueue.main.async {
                var s = snap; s.copyLive(from: self.snapshot)
                self.snapshot = s; self.ready = true
                // MERGE the fresh window into the record store instead of replacing it: the quick
                // scan only covers ~7 days, and overwriting would snap every 14/30/90-day chart
                // back to a week of data until the next deep scan.
                let tail = self.records.filter { $0.date < scanStart }
                self.records = tail + fresh
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
        // Coalesced, like quickRefresh. The caller's own guard cannot do this job: Insights only
        // marks itself scanned when the scan COMPLETES, and its window is kept alive across close
        // and reopen, so closing it during the first multi-second scan and opening it again starts
        // a second one. Two scans then walk a thousand files at once and both write the cache.
        // Everyone waiting gets the single result.
        scanWaiters.append(completion)
        if scanInFlight { return }
        scanInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { DispatchQueue.main.async { completion([], []) }; return }
            let (recs, sessions) = self.scanFilesSync()
            DispatchQueue.main.async {
                self.scanInFlight = false
                let waiting = self.scanWaiters
                self.scanWaiters = []
                for done in waiting { done(recs, sessions) }
            }
        }
    }

    /// The conversation title for a session log, read once and remembered.
    ///
    /// Bounded work: only for a session id the index has never seen, only that one file, and only
    /// its title-bearing lines. Everything after the title is found is skipped, so a huge log costs
    /// a few lines rather than a full parse. This is the live path, so it must never be expensive.
    static func resolvedTitle(sid: String, url: URL) -> String {
        if let known = SessionTitles.shared.title(for: sid) { return known }
        var customTitle: String?, aiTitle: String?, firstUser: String?
        // Only the head of the file. A title and the opening user message are both written at the
        // start of a conversation, and these logs run to hundreds of megabytes: reading one whole
        // just to learn its name would put exactly the kind of stall on the live path that this
        // release is removing.
        var head: String? = nil
        if let h = try? FileHandle(forReadingFrom: url) {
            let data = (try? h.read(upToCount: 256 * 1024)) ?? Data()
            try? h.close()
            // Cut back to the last complete line so a title is never half-decoded.
            if let nl = data.lastIndex(of: 0x0A) {
                head = String(data: data[..<nl], encoding: .utf8)
            } else {
                head = String(data: data, encoding: .utf8)
            }
        }
        if let text = head {
            var scanned = 0
            text.enumerateLines { line, stop in
                scanned += 1
                // A proper title, if there is one, is written near the top. Past a few hundred
                // lines it is not coming, and the first user message is already in hand.
                if scanned > 400 || (customTitle != nil) { stop = true; return }
                if line.contains("\"customTitle\""), let o = jsonLine(line),
                   let t = o["customTitle"] as? String, !t.isEmpty { customTitle = t; stop = true; return }
                if aiTitle == nil, line.contains("\"aiTitle\""), let o = jsonLine(line),
                   let t = o["aiTitle"] as? String, !t.isEmpty { aiTitle = t }
                if firstUser == nil, line.contains("\"type\":\"user\""), let o = jsonLine(line) {
                    firstUser = firstUserText(o)
                }
            }
        }
        let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let title = cleanChatTitle(customTitle) ?? cleanChatTitle(aiTitle)
            ?? cleanChatTitle(firstUser) ?? untitledChatLabel(mod)
        SessionTitles.shared.set(title, for: sid)
        return title
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

    /// Full-history scan over every ~/.claude session log, backed by an on-disk cache.
    ///
    /// The first version read every file in full and JSON-decoded every interesting line, on every
    /// Insights open. On a working machine that is over a gigabyte across a thousand-plus files, so
    /// the window sat on a spinner for seconds each time, recomputing an answer that had not
    /// changed. Yesterday's logs cannot change, so now only files whose modification date or size
    /// moved are touched, and a file that merely grew is read from where the last scan stopped.
    /// Read-only, off the live path, still exact.
    func scanFilesSync() -> ([UsageRecord], [SessionUsage]) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: projectsDir, includingPropertiesForKeys: nil,
                                         options: [.skipsHiddenFiles]) else { return ([], []) }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFrac = ISO8601DateFormatter(); isoNoFrac.formatOptions = [.withInternetDateTime]

        let t0 = Date()
        let cache = ScanCache.load()
        var next: [String: CachedFile] = [:]
        var reused = 0, parsed = 0
        var foundTitles: [String: String] = [:]

        for case let url as URL in walker {
            guard url.pathExtension == "jsonl" else { continue }
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let modDate = vals?.contentModificationDate else { continue }
            let mod = modDate.timeIntervalSince1970
            let size = UInt64(vals?.fileSize ?? 0)
            let path = url.path
            let sid = url.deletingPathExtension().lastPathComponent

            if let c = cache[path], c.mod == mod, c.size == size {
                next[path] = c; reused += 1
                foundTitles[sid] = c.title
                continue
            }

            // Grown since last time: keep what was parsed and read only the new bytes. Anything
            // else (new file, shrank, rewritten) is read from the start.
            let prior = cache[path]
            let canAppend = prior != nil && size >= prior!.size && size >= prior!.offset
            let base = canAppend ? prior!.offset : 0
            guard let h = try? FileHandle(forReadingFrom: url) else { continue }
            try? h.seek(toOffset: base)
            let data = h.readDataToEndOfFile()
            try? h.close()

            // The project and the title come from the head of the file, so they are only worth
            // reading when this file has never been parsed before.
            let project = prior?.project ?? Self.resolvedProject(url: url, home: home)
            let title = (canAppend ? prior?.title : nil) ?? Self.resolvedTitle(sid: sid, url: url)
            foundTitles[sid] = title

            let (items, consumed) = Self.parseUsageBytes(data, project: project, session: title,
                                                         iso, isoNoFrac)
            var recs = canAppend ? (prior?.records ?? []) : []
            recs.append(contentsOf: items.map {
                CachedRecord(ts: $0.0.ts.timeIntervalSince1970, model: $0.0.model,
                             input: $0.0.input, output: $0.0.output, cache5m: $0.0.cache5m,
                             cache1h: $0.0.cache1h, cacheRead: $0.0.cacheRead,
                             key: ScanCache.keyHash($0.1))
            })
            next[path] = CachedFile(mod: mod, size: size, offset: base + consumed,
                                    project: project, title: title, records: recs)
            parsed += 1
        }

        ScanCache.save(next)
        SessionTitles.shared.merge(foundTitles)
        if ProcessInfo.processInfo.environment["CUB_SCAN_TIME"] != nil {
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            print("CUB_SCAN: \(ms)ms  reused=\(reused) reparsed=\(parsed) "
                  + "records=\(next.values.reduce(0) { $0 + $1.records.count })")
            fflush(stdout)
        }

        // Flatten. De-duplication happens across the whole set, not per file, because the same
        // message really does appear in more than one log: Claude Code copies a conversation's
        // earlier usage lines into the new file when it is resumed or compacted. Counting those
        // copies inflated every Insights total, and the per-chat rows worst of all, since the
        // duplicates all land on the same conversation. The live path has always de-duped this way;
        // this one silently did not, so the card and Insights disagreed about the same day.
        //
        // Files are visited in a dictionary's arbitrary order, so which copy is kept is arbitrary
        // too. That is fine, because the copies are identical by construction: same message id,
        // same request id, same token counts.
        var records: [UsageRecord] = []
        var sessions: [SessionUsage] = []
        var seen = Set<UInt64>()
        records.reserveCapacity(next.values.reduce(0) { $0 + $1.records.count })
        for (path, f) in next {
            guard !f.records.isEmpty else { continue }
            var tokens = 0
            var cost = 0.0
            var maxTs = Date(timeIntervalSince1970: 0)
            for r in f.records {
                // key 0 means the line carried no message id, so there is nothing to match on and
                // the row is kept. Dropping unidentifiable rows would lose real usage.
                if r.key != 0 {
                    if seen.contains(r.key) { continue }
                    seen.insert(r.key)
                }
                let date = Date(timeIntervalSince1970: r.ts)
                let rec = UsageRecord(date: date, model: r.model, project: f.project, session: f.title,
                                      input: r.input, output: r.output, cache5m: r.cache5m,
                                      cache1h: r.cache1h, cacheRead: r.cacheRead)
                records.append(rec)
                tokens += rec.totalTokens
                cost += tokenCost(model: r.model, input: r.input, output: r.output,
                                  cache5m: r.cache5m, cache1h: r.cache1h, cacheRead: r.cacheRead)
                if date > maxTs { maxTs = date }
            }
            // Every row in this file was a copy of one already counted, which is exactly what a
            // resumed conversation's older log looks like once the newer one has been read. It
            // contributes nothing, and listing it would put an empty chat dated 1970 in front of
            // the reader.
            guard tokens > 0 || cost > 0 else { continue }
            sessions.append(SessionUsage(id: path, title: f.title, project: f.project,
                                         date: maxTs, tokens: tokens, cost: cost))
        }
        if ProcessInfo.processInfo.environment["CUB_SCAN_TIME"] != nil {
            let raw = next.values.reduce(0) { $0 + $1.records.count }
            print("CUB_SCAN: kept \(records.count) of \(raw) records "
                  + "(\(raw - records.count) were copies of a resumed conversation), "
                  + "\(sessions.count) chats")
            fflush(stdout)
        }
        return (records, sessions)
    }

    /// The project name for a log, read from the cwd recorded inside it.
    ///
    /// The encoded folder name would be cheaper but it contains the account name for anything run
    /// from the home directory, which must never reach the screen. Only the head of the file is
    /// read: cwd is written at the start of a session.
    static func resolvedProject(url: URL, home: String) -> String {
        var cwd: String?
        if let h = try? FileHandle(forReadingFrom: url) {
            let data = (try? h.read(upToCount: 256 * 1024)) ?? Data()
            try? h.close()
            let head = data.lastIndex(of: 0x0A).map { data[..<$0] } ?? data[...]
            if let text = String(data: head, encoding: .utf8) {
                var scanned = 0
                text.enumerateLines { line, stop in
                    scanned += 1
                    if scanned > 400 { stop = true; return }
                    if line.contains("\"cwd\""), let o = jsonLine(line), let c = o["cwd"] as? String {
                        cwd = c; stop = true
                    }
                }
            }
        }
        return cleanProjectName(cwd: cwd ?? "", home: home)
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
                    // Keep the last good reading for any window this response did not carry.
                    //
                    // A response is a success when it parses, not when it is complete: the service
                    // can answer with the five-hour window and omit the per-model ones, and
                    // assigning the missing pieces straight through replaced real numbers with
                    // nothing. The reader watches a cap row vanish and reappear for no reason they
                    // can see. A window that is genuinely gone stays visible until the next full
                    // answer, which is the better of the two wrong states: stale beats absent, and
                    // liveUpdated already says how old the reading is.
                    s.apiSession = api.fiveHour ?? s.apiSession
                    s.apiWeekly = api.sevenDay ?? s.apiWeekly
                    s.apiSonnet = api.sevenDaySonnet ?? s.apiSonnet
                    s.apiOpus = api.sevenDayOpus ?? s.apiOpus
                    if !api.modelLimits.isEmpty { s.modelLimits = api.modelLimits }
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
        // Created private, then appended to. The append path cannot set permissions, so the file
        // has to exist with the right mode before the first byte goes into it.
        if !FileManager.default.fileExists(atPath: url.path) { writePrivate(Data(), to: url) }
        // The modern throwing API, not seekToEndOfFile/write. The legacy pair raises an
        // Objective-C exception on a write failure (a full disk, a revoked permission), and a
        // raised exception in Swift is not catchable: it terminates the process. A diagnostic log
        // must never be able to take the app down, least of all while it is recording a problem.
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            do {
                try h.seekToEnd()
                try h.write(contentsOf: data)
            } catch { /* the log is best effort; losing a line is not worth reporting */ }
        } else {
            writePrivate(data, to: url)
        }
    }

    /// Empty the diagnostic log (sign-out, or the Settings reset).
    static func truncateDebugLog() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/burndown/live-debug.log")
        writePrivate(Data(), to: url)
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

/// One token refresh at a time, and everyone else gets ITS answer.
///
/// Coalescing rather than queueing, because a second refresh is not merely wasteful here: refreshing
/// rotates the refresh token, so the loser of a race presents one that was invalidated a moment ago,
/// fails, and drops the user back to local estimates with nothing on screen to explain it.
actor RefreshGate {
    private var inFlight: Task<String?, Never>?
    func run(_ make: @Sendable @escaping () async -> String?) async -> String? {
        if let t = inFlight { return await t.value }
        let t = Task { await make() }
        inFlight = t
        let v = await t.value
        inFlight = nil
        return v
    }
}

    /// Serialises token refreshes. A refresh ROTATES the refresh token: the old one stops working
    /// the moment the new one is issued. Two refreshes racing means the slower one presents a token
    /// that has just been invalidated, fails, and drops the user back to local estimates with no
    /// explanation. Only one may be in flight, and whoever else arrives waits and re-reads the
    /// result rather than starting a second one.
    private static let refreshGate = RefreshGate()

    private static func ensureAccessToken() async -> String? {
        let now = Date().timeIntervalSince1970 * 1000
        if let s = loadStored() {
            if s.expMs > now + 60_000 { return s.access }
            let got: String? = await refreshGate.run {
                // Re-read inside the gate: another caller may have refreshed while this one waited,
                // in which case there is a perfectly good token on disk and nothing left to do.
                let fresh = Date().timeIntervalSince1970 * 1000
                let base = loadStored() ?? s
                if base.expMs > fresh + 60_000 { return base.access }
                if let r = await refresh(base) { saveStored(r); dbg("refresh=ok(stored)"); return r.access }
                dbg("refresh=failed(stored)")
                return nil
            }
            if let got { return got }
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
        // Owner-only from the instant it exists: this holds account email, org and plan.
        if let data = try? JSONSerialization.data(withJSONObject: root, options: .prettyPrinted) {
            writePrivate(data, to: cacheURL)
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
        // Carries the current chat's name, so it is owner-only like everything else here.
        if let d = encodeBurndownLive(live).data(using: .utf8) { writePrivate(d, to: url) }
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

    private static func computeSnapshot(entries: [Entry], cap: Int, weeklyCap: Int, now: Date,
                                        weeklyResetAt: Date? = nil) -> UsageSnapshot {
        var snap = UsageSnapshot()
        snap.sessionCap = cap
        snap.weeklyCap = weeklyCap
        let blocks = buildBlocks(entries)
        if let active = blocks.last, now < active.start.addingTimeInterval(FIVE_HOURS) {
            snap.sessionFresh = active.fresh
            snap.sessionCost = active.cost
            snap.resetAt = active.start.addingTimeInterval(FIVE_HOURS)
        }
        // The local estimate covers the same week the service is measuring, when the last live
        // answer told us where that week starts. A rolling seven days does not line up with a fixed
        // window, so the estimate disagreed with the live figure it stands in for, most visibly
        // right after a reset when a rolling week still carries the previous week's work.
        let weekAgo = weeklyResetAt.flatMap { $0 > now ? $0.addingTimeInterval(-WEEK) : nil }
            ?? now.addingTimeInterval(-WEEK)
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
    /// Display name from Claude Code's ENCODED project folder, e.g. "-Users-someone-dev-app".
    /// The encoding just swaps "/" for "-", so the home directory encodes to a string containing
    /// the ACCOUNT NAME. That must never reach the screen: it is unreadable as a project name and
    /// it puts the user's identity into every screenshot. The full-parse path above resolves the
    /// real cwd instead; this one runs on the hot incremental read, which deliberately never
    /// re-reads the file head, so it decodes what it has and refuses to show the home prefix.
    private static func projectDisplayName(_ url: URL, home: String) -> String {
        let parts = url.pathComponents
        guard let i = parts.firstIndex(of: "projects"), i + 1 < parts.count else { return kUnknownProject }
        let encoded = parts[i + 1]
        let encodedHome = home.replacingOccurrences(of: "/", with: "-")
        if encoded == encodedHome { return kHomeProject }
        var rest = encoded
        if encoded.hasPrefix(encodedHome + "-") { rest = String(encoded.dropFirst(encodedHome.count + 1)) }
        let leaf = rest.split(separator: "-").last.map(String.init) ?? rest
        return leaf.isEmpty ? kHomeProject : leaf
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
        // Parse ONLY the complete lines. The trailing piece after the last newline is not consumed
        // (see `consumed` below), so parsing it here would hand back an entry whose bytes the next
        // scan reads again: one write landing exactly on a line boundary, and that message is
        // counted twice. Deciding the boundary once, before the loop, is what keeps the two in step.
        let lastNL = data.lastIndex(of: 0x0A)
        let complete = lastNL.map { data[data.startIndex...$0] } ?? Data()[...]
        for lineData in complete.split(separator: 0x0A, omittingEmptySubsequences: false) {
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
        // Consume exactly what was parsed: through the last newline. A trailing partial line is
        // left for the next scan, which reads it once the rest of it exists.
        let consumed = lastNL.map { UInt64(data.distance(from: data.startIndex, to: $0) + 1) } ?? 0
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
            let project = Self.projectDisplayName(url, home: FileManager.default.homeDirectoryForCurrentUser.path)
            let sid = url.deletingPathExtension().lastPathComponent
            // The file is named after a UUID and the conversation's title lives inside it. Naming
            // records by the filename is what put raw session ids in front of the reader wherever
            // this path feeds a chart. Look the title up once per session and remember it.
            let session = Self.resolvedTitle(sid: sid, url: url)
            // Read only the appended bytes when the file only grew; otherwise (new / shrank / rotated)
            // read the whole thing.
            // Appending is only safe when the file has GROWN. Comparing against the parse offset
            // alone misses the case where a log was rewritten shorter and then grew again past that
            // offset: the bytes before it are different bytes now, and reading from there splices
            // the middle of a new file onto entries from an old one. The scan path already tests
            // both; this one is the same rule, written the same way.
            let canAppend = cached != nil && size >= cached!.size && size >= cached!.offset
            let base = canAppend ? cached!.offset : 0
            var items = canAppend ? cached!.items : []
            guard let h = try? FileHandle(forReadingFrom: url) else {
                // Leave the cache entry exactly as it was. Stamping the file's CURRENT date and
                // size onto an entry we failed to read makes it look freshly parsed, so the
                // unchanged check skips it from then on and that conversation's usage is frozen
                // for the life of the process. A file we could not open is a file we know nothing
                // new about; the next pass should try again.
                continue
            }
            try? h.seek(toOffset: base)
            let data = h.readDataToEndOfFile(); try? h.close()
            let (newItems, consumed) = Self.parseUsageBytes(data, project: project, session: session, iso, isoNoFrac)
            items.append(contentsOf: newItems)
            entryCache[path] = FileEntries(mod: mod, size: size, offset: base + consumed, items: items)
        }
        // Drop deleted files, and also files that have fallen entirely out of the window. Only the
        // first of those used to happen, so every log ever touched kept its parsed entries in
        // memory for the life of the process: on a machine with a thousand logs the cache grew
        // without limit and never gave anything back. A file that returns to the window later is
        // simply re-read from the start, which is what happens for one it had never seen.
        entryCache = entryCache.filter { path, fe in
            guard live.contains(path) else { return false }
            guard let newest = fe.items.last?.entry.ts else { return true }   // parsed, nothing in it
            return newest >= since
        }
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
