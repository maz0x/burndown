import Foundation

// Foundation-pure screen-time recap: condenses a window of usage records into a single
// plain-English summary line for the recap card. Builds entirely on Aggregation.swift's rollups and
// totals plus Pricing.swift's cost math, so it stays AppKit / Combine / SwiftUI free and the headless
// harness (run-recap-tests.sh) can compile and test it with no UI.

/// One recap of a labelled period (e.g. "This week", "Today"): the headline numbers plus the
/// biggest project, the dominant model family, and the busiest single day.
struct RecapSummary {
    let label: String
    let totalTokens: Int
    let costUSD: Double
    let dayCount: Int
    let topProject: String
    let topModelFamily: String
    let busiestDay: String
}

/// Summarize a set of usage records into a RecapSummary.
/// - totalTokens / costUSD come from the grand totals(records) rollup.
/// - dayCount is the number of distinct day keys touched.
/// - topProject / topModelFamily are the highest-token rollup keys (or "(none)" when empty).
/// - busiestDay is the day key with the most tokens (or "" when there are no records).
func recap(_ records: [UsageRecord], label: String, calendar: Calendar = .current) -> RecapSummary {
    let grand = totals(records)

    // Distinct calendar days touched by the records.
    var days = Set<String>()
    for r in records { days.insert(dayKey(r.date, calendar: calendar)) }

    let topProject = rollupByProject(records).first?.key ?? "(none)"
    let topModelFamily = rollupByModelFamily(records).first?.key ?? "(none)"

    // Busiest day: the day rollup with the most tokens. rollupByDay returns chronological order,
    // so pick the max explicitly (ties resolve to the earlier day for determinism).
    let dayRollups = rollupByDay(records, calendar: calendar)
    let busiest = dayRollups.max { a, b in
        a.tokens != b.tokens ? a.tokens < b.tokens : a.key > b.key
    }
    let busiestDay = busiest?.key ?? ""

    return RecapSummary(
        label: label,
        totalTokens: grand.tokens,
        costUSD: grand.cost,
        dayCount: days.count,
        topProject: topProject,
        topModelFamily: topModelFamily,
        busiestDay: busiestDay
    )
}

/// Format a token count compactly: 4_200_000 -> "4.2M", 530_000 -> "530K", 940 -> "940".
/// Drops a trailing ".0" so round numbers read as "4M" / "2K" rather than "4.0M".
func compactTokens(_ n: Int) -> String {
    func trim(_ value: Double, _ suffix: String) -> String {
        // One decimal place, then strip a redundant ".0".
        var s = String(format: "%.1f", value)
        if s.hasSuffix(".0") { s = String(s.dropLast(2)) }
        return s + suffix
    }
    let a = abs(n)
    let sign = n < 0 ? "-" : ""
    if a >= 1_000_000 { return sign + trim(Double(a) / 1_000_000, "M") }
    if a >= 1_000     { return sign + trim(Double(a) / 1_000, "K") }
    return sign + String(a)
}

/// A raw "yyyy-MM-dd" day key as a human day, e.g. "Tue Jun 2". Falls back to the raw key if it
/// does not parse (defensive; keys are produced in this same format).
func prettyDayKey(_ key: String) -> String {
    let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"; inF.locale = Locale(identifier: "en_US_POSIX")
    guard let d = inF.date(from: key) else { return key }
    let outF = DateFormatter(); outF.dateFormat = "EEE MMM d"
    return outF.string(from: d)
}

/// One plain-English recap line. No em-dashes (project rule): clauses are joined with commas,
/// semicolons, and the word "and". Example:
/// "This week: 4.2M tokens, ~$12.30, across 5 days; top project alpha, mostly Opus, busiest 2026-06-02"
func recapText(_ r: RecapSummary) -> String {
    let tokens = compactTokens(r.totalTokens)
    let cost = String(format: "~$%.2f", r.costUSD)
    let dayWord = r.dayCount == 1 ? "day" : "days"

    var line = "\(r.label): \(tokens) tokens, \(cost), across \(r.dayCount) \(dayWord)"

    // Trailing detail clauses, only when there is something to say.
    var details: [String] = []
    // "top project Home folder" says nothing: that bucket is everything not run inside a project
    // folder, which for many people is most of their work. The sentence skips it rather than
    // dressing it up as a finding.
    // kUnknownProject, not the literal "(unknown)" it used to be called. The rename left this
    // guard testing a string the app no longer produces, so "top project No folder recorded"
    // could reach the sentence: the one bucket that means "we could not tell" presented as a
    // finding about the reader's week.
    if r.topProject != "(none)", r.topProject != kHomeProject, r.topProject != kUnknownProject {
        details.append("top project \(r.topProject)")
    }
    if r.topModelFamily != "(none)" { details.append("mostly \(r.topModelFamily)") }
    if !r.busiestDay.isEmpty { details.append("busiest \(prettyDayKey(r.busiestDay))") }

    if !details.isEmpty { line += "; " + details.joined(separator: ", ") }
    return line
}
