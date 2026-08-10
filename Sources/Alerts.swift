import Foundation
import UserNotifications
import AppKit

/// macOS notifications for usage. Per-metric (session %, weekly %, burn-rate spike), plus
/// window-reset notices, an optional sound, and "repeat while over" re-alerts. Threshold crossings
/// fire once per level per window (re-arming when the window resets); burn spikes use hysteresis.
final class UsageAlerts {
    private var sessionFired: Set<Int> = []
    private var weeklyFired: Set<Int> = []
    private var sessionCycle: Date??
    private var weeklyCycle: Date??
    private var sessionLastFire: Date?
    private var weeklyLastFire: Date?
    private var burnArmed = true
    private var sessionResetSeen: Date??
    private var weeklyResetSeen: Date??
    private var opusFired: Set<Int> = []; private var opusCycle: Date??; private var opusLastFire: Date?
    private var sonnetFired: Set<Int> = []; private var sonnetCycle: Date??; private var sonnetLastFire: Date?
    private var forecastFired = false; private var forecastCycle: Date??
    private var authorized = false
    private var requested = false
    private var soundName = ""                 // which bundled sound to play ("" = system default)
    private var snoozeUntil: Date?             // set by the Snooze action; suppresses all alerts until then
    private var burnHistory: [Double] = []     // rolling burn-rate samples for adaptive runaway detection
    private var lastBudgetLevel: BudgetLevel = .ok   // fire budget alerts only when the level rises

    /// Mute every alert for `minutes` (driven by the notification's Snooze button).
    func snooze(_ minutes: Double, now: Date = Date()) { snoozeUntil = now.addingTimeInterval(minutes * 60) }

    // Spam backstop: never re-post the SAME notification title within this window. Persisted to
    // UserDefaults so an app restart (rebuild / login / crash respawn) cannot re-fire an alert the
    // user already saw. This makes "the same notification over and over" impossible regardless of
    // which eval triggered it. 10 min sits comfortably under the smallest repeat-while-over interval
    // (15 min), so it never fights an intentional re-alert, only true duplicates.
    private let dedupWindow: TimeInterval = 10 * 60
    private let dStore = appDefaults   // never the real domain during a QA run
    private let dKey = "alertLastPosted"
    private lazy var lastPosted: [String: Date] = {
        (dStore.dictionary(forKey: dKey) as? [String: Double])?.mapValues { Date(timeIntervalSince1970: $0) } ?? [:]
    }()
    private func rememberPost(_ title: String, _ now: Date) {
        lastPosted[title] = now
        let cutoff = now.addingTimeInterval(-86_400)
        lastPosted = lastPosted.filter { $0.value > cutoff }   // keep the stored map small
        dStore.set(lastPosted.mapValues { $0.timeIntervalSince1970 }, forKey: dKey)
    }

    // isNewCycle + the eval decision logic now live in Sources/AlertLogic.swift (Foundation-pure,
    // headless-testable). The methods below apply the returned state and do the notification side effect.

    private func quietNow(_ s: AppSettings, _ now: Date) -> Bool {
        guard s.quietHours else { return false }
        let h = Calendar.current.component(.hour, from: now)
        let from = Int(s.quietFrom), to = Int(s.quietTo)
        if from == to { return false }
        return from < to ? (h >= from && h < to) : (h >= from || h < to)
    }

    /// Ask for notification permission once. Triggers the system prompt the first time alerts are on.
    func enable() {
        guard !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] ok, _ in
            self?.authorized = ok
        }
    }

    /// Send a sample notification. If permission was denied (macOS won't re-prompt), open System
    /// Settings so the user can turn it on; if undecided, prompt; if allowed, just fire.
    func fireTest(soundName: String = "") {
        self.soundName = soundName
        notifLog("fireTest: called")
        let c = UNUserNotificationCenter.current()
        c.getNotificationSettings { [weak self] s in
            notifLog("fireTest: status=\(s.authorizationStatus.rawValue) alertSetting=\(s.alertSetting.rawValue)")
            DispatchQueue.main.async {
                switch s.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    self?.authorized = true
                    self?.post("Test alert", "Notifications are working. You'll be alerted at your thresholds.", true, force: true)
                    notifLog("fireTest: posted (sound=\(self?.soundName ?? ""))")
                case .notDetermined:
                    self?.requested = true
                    c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
                        self?.authorized = ok
                        if ok { self?.post("Test alert", "Notifications are working.", true, force: true) }
                        else { self?.openNotificationSettings() }
                    }
                default:   // denied
                    self?.openNotificationSettings()
                }
            }
        }
    }

    private func openNotificationSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(u)
        }
    }

    func check(session: Double, weekly: Double, opus: Double?, sonnet: Double?, sessionReset: Date?, weeklyReset: Date?, burn: Double, forecastMin: Double?, topChat: String? = nil, s: AppSettings, now: Date = Date()) {
        // No `authorized` gate: attempt posts and let macOS gate delivery. This avoids a stale flag
        // once the user enables notifications in System Settings (we never re-prompt after a denial).
        soundName = s.alertSoundName
        if let su = snoozeUntil, now < su { return }   // user hit Snooze: stay quiet until it lapses
        if quietNow(s, now) { return }   // quiet hours: defer everything until the window ends
        if s.alertForecast { evalForecast(forecastMin, s.alertForecastMin, sessionReset, s.alertSound) }
        if s.alertSession {
            evalPct("Session", session, sessionReset, Int((s.alertSessionAt * 100).rounded()),
                    &sessionFired, &sessionCycle, &sessionLastFire, s.alertRepeatMin, s.alertSound, now)
        }
        if s.alertWeekly {
            evalPct("This week", weekly, weeklyReset, Int((s.alertWeeklyAt * 100).rounded()),
                    &weeklyFired, &weeklyCycle, &weeklyLastFire, s.alertRepeatMin, s.alertSound, now)
        }
        if s.alertOpus, let o = opus {
            evalPct("Opus", o, weeklyReset, Int((s.alertOpusAt * 100).rounded()),
                    &opusFired, &opusCycle, &opusLastFire, s.alertRepeatMin, s.alertSound, now)
        }
        if s.alertSonnet, let sn = sonnet {
            evalPct("Sonnet", sn, weeklyReset, Int((s.alertSonnetAt * 100).rounded()),
                    &sonnetFired, &sonnetCycle, &sonnetLastFire, s.alertRepeatMin, s.alertSound, now)
        }
        if s.alertBurn { evalBurn(burn, s.alertBurnAt, topChat, s.alertSound) }
        if s.alertOnReset {
            evalReset("Session", sessionReset, &sessionResetSeen, s.alertSound)
            evalReset("Weekly", weeklyReset, &weeklyResetSeen, s.alertSound)
        }
    }

    /// Self-imposed budget + adaptive runaway-burn checks. Called alongside check() each tick.
    /// Both rely on post(...)'s dedup-by-title backstop, so they never spam.
    func checkBudgetRunaway(burn: Double, records: [UsageRecord], s: AppSettings, now: Date = Date()) {
        soundName = s.alertSoundName
        if let su = snoozeUntil, now < su { return }
        if quietNow(s, now) { return }

        if s.alertRunaway {
            let v = runawayVerdict(history: burnHistory, current: burn)
            // Learn from calm, not from the emergency. The window holds only a minute or two, so a
            // runaway that lasts that long would otherwise become the new "normal" and the alert
            // would fall silent while the thing it warned about was still running. Samples taken
            // while the verdict is elevated are watched, never learned from.
            if v.level == .normal {
                burnHistory.append(burn)
                if burnHistory.count > 40 { burnHistory.removeFirst(burnHistory.count - 40) }
            }
            if v.level == .runaway { post("Possible runaway burn", v.summary + ".", s.alertSound) }
        }

        if s.budgetEnabled, s.alertBudget, s.budgetLimit > 0 {
            let metric: BudgetMetric = s.budgetMetric == "tokens" ? .tokens : .usd
            let period: BudgetPeriod = s.budgetPeriod == "day" ? .day : .week
            let windowStart = period == .day
                ? Calendar.current.startOfDay(for: now)
                : now.addingTimeInterval(-7 * 86_400)
            let agg = totals(recordsInWindow(records, since: windowStart, until: now.addingTimeInterval(1)))
            let spent = metric == .tokens ? Double(agg.tokens) : agg.cost
            let elapsed = period == .day ? min(1, max(0.0001, now.timeIntervalSince(windowStart) / 86_400)) : 1.0
            let st = budgetStatus(spent: spent,
                                  config: BudgetConfig(metric: metric, limit: s.budgetLimit, period: period),
                                  elapsedFraction: elapsed)
            if budgetRank(st.level) > budgetRank(lastBudgetLevel) {
                post(st.level == .over ? "Budget exceeded" : "Approaching budget", st.summary + ".", s.alertSound)
            }
            lastBudgetLevel = st.level
        }
    }

    private func budgetRank(_ l: BudgetLevel) -> Int { l == .over ? 2 : (l == .warn ? 1 : 0) }

    /// The fourth notification moment: an OPT-IN weekly digest, posted once on a Monday.
    /// Quiet hours and snooze suppress it like any other moment; it never fires twice in a week.
    func checkWeeklyDigest(records: [UsageRecord], s: AppSettings, now: Date = Date()) {
        guard s.weeklyDigest else { return }
        if let su = snoozeUntil, now < su { return }
        if quietNow(s, now) { return }
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2                                   // Monday
        guard cal.component(.weekday, from: now) == 2 else { return }
        let week = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let d = appDefaults   // a QA run must not consume the real weekly-digest stamp
        if let last = d.object(forKey: "lastWeeklyDigestAt") as? Date, last >= week { return }
        let since = now.addingTimeInterval(-7 * 86_400)
        let agg = totals(recordsInWindow(records, since: since, until: now.addingTimeInterval(1)))
        guard agg.tokens > 0 else { return }                   // nothing to report is not a report
        d.set(now, forKey: "lastWeeklyDigestAt")
        let cost = String(format: "$%.2f", agg.cost)
        post("Last week", "You burned \(fmtTok(agg.tokens)) tokens, about \(cost).", s.alertSound, force: true)
    }

    private func evalPct(_ name: String, _ pct: Double, _ reset: Date?, _ base: Int,
                         _ fired: inout Set<Int>, _ cycle: inout Date??, _ lastFire: inout Date?,
                         _ repeatMin: Double, _ sound: Bool, _ now: Date) {
        var st = AlertPctState(fired: fired, cycle: cycle, lastFire: lastFire)
        let action = alertPctEval(pct: pct, reset: reset, base: base, repeatMin: repeatMin, now: now, state: &st)
        fired = st.fired; cycle = st.cycle; lastFire = st.lastFire
        switch action {
        case .none: break
        case let .fire(hit, cur):
            if hit >= 100 {
                // Over-limit carries the ONE number that matters: time to the fresh window.
                let body = reset.map { r -> String in
                    let s = max(0, r.timeIntervalSince(now)); let h = Int(s) / 3600; let m = (Int(s) % 3600) / 60
                    return h > 0 ? "Resets in \(h)h \(m)m." : "Resets in \(m)m."
                } ?? "A fresh window will start soon."
                post("\(noun(name).capitalized) limit reached", body, sound)
            }
            else { post("\(name) at \(hit)%", "Usage is at \(cur)% of your \(noun(name)) allowance.", sound) }
        case let .repeatOver(cur):
            post("\(name) still at \(cur)%", "Still over your \(noun(name)) alert level.", sound)
        }
    }

    // Burn spikes are noisy → fire once when it rises past the threshold, re-arm only after it falls well below.
    private func evalBurn(_ burn: Double, _ threshold: Double, _ topChat: String?, _ sound: Bool) {
        if alertBurnEval(burn: burn, threshold: threshold, armed: &burnArmed) {
            // Name the responsible chat when one is clearly burning, else the bare rate.
            let body = topChat.map { "\($0) is burning \(fmtTok(Int(burn))) tokens/min." }
                ?? "\(fmtTok(Int(burn))) tokens/min right now."
            post("High burn rate", body, sound)
        }
    }

    // Fire once when the projected time-to-limit drops under the threshold; re-arm when the session resets.
    private func evalForecast(_ minsLeft: Double?, _ threshold: Double, _ reset: Date?, _ sound: Bool) {
        var st = AlertForecastState(fired: forecastFired, cycle: forecastCycle)
        let mins = alertForecastEval(minsLeft: minsLeft, threshold: threshold, reset: reset, state: &st)
        forecastFired = st.fired; forecastCycle = st.cycle
        if let mins { post("Approaching session limit", "At the current pace, about \(mins) min to your session limit.", sound) }
    }

    private func evalReset(_ name: String, _ reset: Date?, _ seen: inout Date??, _ sound: Bool) {
        if seen == nil { seen = .some(reset); return }   // first observation: don't alert
        if isNewCycle(seen, reset) { seen = .some(reset); post("\(name) window reset", "A fresh \(noun(name)) window has started.", sound) }
    }

    // "This week" reads wrong possessed ("your this week allowance"); map display names to a noun
    // that composes into a sentence.
    private func noun(_ name: String) -> String { name == "This week" ? "weekly" : name.lowercased() }

    private func post(_ title: String, _ body: String, _ sound: Bool, force: Bool = false) {
        let now = Date()
        if !force {
            if let last = lastPosted[title], now.timeIntervalSince(last) < dedupWindow {
                notifLog("dedup: suppressed '\(title)' (\(Int(now.timeIntervalSince(last)))s since last)")
                return
            }
            rememberPost(title, now)
        }
        let c = UNMutableNotificationContent()
        // Every notification leads with the product name. (Dedup keys off the raw title.)
        c.title = title.hasPrefix("Burndown:") ? title : "Burndown: \(title)"
        c.body = body
        c.categoryIdentifier = UsageAlerts.category   // gives the banner the Snooze / Open buttons
        if sound {
            c.sound = soundName.isEmpty ? .default : UNNotificationSound(named: UNNotificationSoundName("\(soundName).wav"))
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    static let category = "BURNDOWN_ALERT"
    static let actionSnooze = "BURNDOWN_SNOOZE"
    static let actionOpen = "BURNDOWN_OPEN"
}
