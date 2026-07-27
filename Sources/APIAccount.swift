import Foundation

// MARK: - Developer API account tracking (separate from the subscription)
//
// Burndown's main gauges track a Claude SUBSCRIPTION (Max/Pro) via the OAuth usage endpoint.
// This module adds tracking of a Claude DEVELOPER API account (console.anthropic.com,
// pay-as-you-go) via Anthropic's Admin "Usage & Cost" API. They are two different accounts
// with two different billing systems, so this is additive and never touches the subscription
// path: if no Admin key is configured, nothing here runs.
//
// Requirements (surfaced to the user in the Account window):
//  - An **Admin API key** (`sk-ant-admin01-...`), created at console.anthropic.com by an org
//    owner. A regular `sk-ant-api...` key CANNOT read usage/cost.
//  - The Admin API is unavailable for INDIVIDUAL accounts; the key's org must be a Console org.
// Docs: platform.claude.com/docs/en/manage-claude/usage-cost-api

/// Live snapshot of the developer API account's spend, in USD.
struct APISpend: Equatable {
    var configured = false     // an Admin key is saved
    var monthToDate = 0.0      // USD, current calendar month (UTC) to now
    var today = 0.0            // USD, today (UTC)
    var fetchedAt: Date? = nil
    var error: String? = nil   // human-readable failure (bad key, no org, http error)
    var daily: [Double] = []   // USD per day, oldest -> newest, this calendar month (C2 sparkline + average)
    /// Trailing daily average over the days we have (this month to date).
    var dailyAvg: Double { daily.isEmpty ? 0 : daily.reduce(0, +) / Double(daily.count) }
}

enum APIAccount {
    static var keyURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/burndown/api-admin-key.json")
    }

    // ── Local, chmod-600 key storage (mirrors the OAuth token.json approach) ──
    static func loadKey() -> String? {
        guard let d = try? Data(contentsOf: keyURL),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let k = o["adminKey"] as? String, !k.isEmpty else { return nil }
        return k
    }
    static func saveKey(_ k: String) {
        let dir = keyURL.deletingLastPathComponent()
        // Created private (0600 inside a 0700 dir), never chmod'd after the fact.
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        if let d = try? JSONSerialization.data(withJSONObject: ["adminKey": k]) {
            FileManager.default.createFile(atPath: keyURL.path, contents: d,
                                           attributes: [.posixPermissions: 0o600])
        }
    }
    static func clearKey() { try? FileManager.default.removeItem(at: keyURL) }

    /// Admin keys begin with `sk-ant-admin`. We reject obvious non-admin keys before spending a
    /// round trip, so the user gets an instant, specific message instead of a 401.
    static func looksLikeAdminKey(_ k: String) -> Bool {
        k.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("sk-ant-admin")
    }

    /// Pure, headless-testable: fold the cost_report `data` buckets into (monthCents, todayCents).
    /// `amount` is a decimal string in the currency's lowest units (cents); the caller divides by 100.
    static func foldCost(_ data: [[String: Any]], iso: ISO8601DateFormatter, todayStart: Date) -> (month: Double, today: Double, byDay: [Date: Double]) {
        var month = 0.0, today = 0.0, byDay: [Date: Double] = [:]
        for bucket in data {
            let start = (bucket["starting_at"] as? String).flatMap { iso.date(from: $0) }
            let results = bucket["results"] as? [[String: Any]] ?? []
            let sum = results.reduce(0.0) { $0 + (Double(($1["amount"] as? String) ?? "0") ?? 0) }
            month += sum
            if let s = start { byDay[s, default: 0] += sum; if s >= todayStart { today += sum } }
        }
        return (month, today, byDay)
    }

    /// Fetch month-to-date + today USD spend from the Admin Cost Report API. Synchronous;
    /// call OFF the main thread. Handles pagination. Never throws; failures land in `.error`.
    static func fetchSpend(adminKey: String) -> APISpend {
        var out = APISpend(configured: true)
        guard looksLikeAdminKey(adminKey) else {
            out.error = "That is not an Admin key. It must start with sk-ant-admin (create one at console.anthropic.com, Settings, Admin keys)."
            return out
        }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
        guard let monthStart = utc.date(from: utc.dateComponents([.year, .month], from: now)) else {
            out.error = "date error"; return out
        }
        let todayStart = utc.startOfDay(for: now)

        var page: String? = nil, monthCents = 0.0, todayCents = 0.0, guardN = 0
        var dayCents: [Date: Double] = [:]
        repeat {
            var comp = URLComponents(string: "https://api.anthropic.com/v1/organizations/cost_report")!
            var items = [URLQueryItem(name: "starting_at", value: iso.string(from: monthStart)),
                         URLQueryItem(name: "ending_at", value: iso.string(from: now)),
                         URLQueryItem(name: "bucket_width", value: "1d"),
                         URLQueryItem(name: "limit", value: "31")]
            if let p = page { items.append(URLQueryItem(name: "page", value: p)) }
            comp.queryItems = items
            var req = URLRequest(url: comp.url!, timeoutInterval: 15)
            req.setValue(adminKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("Burndown/\(kAppVersion) (https://github.com/maz0x)", forHTTPHeaderField: "User-Agent")

            let sem = DispatchSemaphore(value: 0)
            var body: Data? = nil, code = 0
            URLSession.shared.dataTask(with: req) { d, r, _ in
                body = d; code = (r as? HTTPURLResponse)?.statusCode ?? 0; sem.signal()
            }.resume()
            _ = sem.wait(timeout: .now() + 18)

            guard code == 200, let d = body,
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                out.error = Self.errorText(code: code, body: body)
                return out
            }
            let (m, t, byDay) = foldCost(o["data"] as? [[String: Any]] ?? [], iso: iso, todayStart: todayStart)
            monthCents += m; todayCents += t
            for (d, c) in byDay { dayCents[d, default: 0] += c }
            page = (o["has_more"] as? Bool == true) ? (o["next_page"] as? String) : nil
            guardN += 1
        } while page != nil && guardN < 12

        out.monthToDate = monthCents / 100.0
        out.today = todayCents / 100.0
        out.daily = dayCents.keys.sorted().map { dayCents[$0]! / 100.0 }   // oldest -> newest
        out.fetchedAt = Date()
        out.error = nil
        return out
    }

    private static func errorText(code: Int, body: Data?) -> String {
        let msg = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
        switch code {
        case 401: return "Key rejected. Make sure it is a valid Admin key (sk-ant-admin) for your organization."
        case 403: return msg ?? "Not permitted. The Admin API is unavailable for individual accounts; it needs a Console organization."
        case 404: return "Endpoint not found. Your account may not have the Usage and Cost API enabled."
        case 429: return "Rate limited by Anthropic. Try again in a minute."
        case 0:   return "Could not reach api.anthropic.com (offline or blocked)."
        default:  return msg ?? "HTTP \(code) from the cost report API."
        }
    }
}
