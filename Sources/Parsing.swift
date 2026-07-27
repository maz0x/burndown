import Foundation

// Foundation-pure parsing helpers, kept in their own file so the headless test harness
// (run-parse-tests.sh) can compile the REAL implementations in isolation - no AppKit /
// Combine / network. Both the app (build.sh globs Sources/*.swift) and the tests use these.

/// Fast ISO-8601 parse for the Claude log timestamp shape (YYYY-MM-DDTHH:MM:SS[.fff][Z], UTC), by
/// pure integer math + the civil-days algorithm. Roughly 100x faster than ISO8601DateFormatter, which
/// otherwise pins a core while re-reading the JSONL logs on every refresh. Returns nil when the shape
/// does not match so the caller can fall back to the tolerant formatter path.
func fastISO8601Date(_ s: String) -> Date? {
    let b = Array(s.utf8)
    guard b.count >= 19 else { return nil }
    @inline(__always) func num(_ i: Int, _ n: Int) -> Int {
        var v = 0
        for k in 0..<n { let c = b[i + k]; if c < 48 || c > 57 { return -1 }; v = v * 10 + Int(c - 48) }
        return v
    }
    // Separators: - - (T|space) : :  -> reject anything that is not the expected shape.
    guard b[4] == 45, b[7] == 45, b[10] == 84 || b[10] == 32, b[13] == 58, b[16] == 58 else { return nil }
    let Y = num(0, 4), M = num(5, 2), D = num(8, 2), h = num(11, 2), mi = num(14, 2), se = num(17, 2)
    guard Y >= 0, M >= 1, M <= 12, D >= 1, D <= 31, h >= 0, h < 24, mi >= 0, mi < 60, se >= 0, se < 62 else { return nil }
    let y = M <= 2 ? Y - 1 : Y
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let doy = (153 * (M > 2 ? M - 3 : M + 9) + 2) / 5 + D - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    let days = era * 146097 + doe - 719468   // days since 1970-01-01 (UTC)
    return Date(timeIntervalSince1970: Double(days * 86400 + h * 3600 + mi * 60 + se))
}

/// Parse an ISO-8601 instant, tolerating fractional seconds and offsets. Returns nil on garbage.
func parseISO(_ s: String) -> Date? {
    let stripped = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
    if let d = f.date(from: stripped) { return d }
    let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f2.date(from: s)
}

/// Clamp a 0…100 utilization percentage to a 0…1 fraction (the conversion used by every
/// usage-window reader). Out-of-range input saturates instead of producing a bogus bar.
func clampPct(_ u: Double) -> Double { min(1.0, max(0.0, u / 100.0)) }
