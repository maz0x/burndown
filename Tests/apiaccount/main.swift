import Foundation

// Behavioral tests for the pure logic in Sources/APIAccount.swift (compiled headlessly with that file).
let kAppVersion = "test"

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print(cond ? "  ok   \(msg)" : "  FAIL \(msg)")
    if !cond { failures += 1 }
}
func approx(_ a: Double, _ b: Double, _ tol: Double, _ msg: String) { check(abs(a - b) < tol, msg + " (got \(a))") }

var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    utc.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: y, month: m, day: d))!
}

print("queryStart:")
let nov1 = day(2026, 11, 1)
check(APIAccount.queryStart(monthStart: nov1, todayStart: day(2026, 11, 14)) == nov1, "mid-month starts at monthStart")
check(APIAccount.queryStart(monthStart: nov1, todayStart: nov1) == day(2026, 10, 31), "on the 1st starts at yesterday")

print("deriveDaily:")
let nov2 = day(2026, 11, 2), nov3 = day(2026, 11, 3), nov4 = day(2026, 11, 4)
let buckets: [Date: Double] = [nov1: 100, nov2: 250, nov3: 75]
let d1 = APIAccount.deriveDaily(buckets, monthStart: nov1, todayStart: nov4)
check(d1.daily == [100, 250, 75], "three values in date order")
check(d1.lastDayCents == 75, "lastDayCents is the newest bucket")
check(d1.lastDayIsToday == false, "lastDayIsToday false when report ends yesterday")
var withToday = buckets; withToday[nov4] = 40
let d2 = APIAccount.deriveDaily(withToday, monthStart: nov1, todayStart: nov4)
check(d2.lastDayIsToday == true && d2.lastDayCents == 40, "lastDayIsToday true when a bucket for today arrived")
var withPrev = buckets; withPrev[day(2026, 10, 31)] = 999
let d3 = APIAccount.deriveDaily(withPrev, monthStart: nov1, todayStart: nov4)
check(d3.daily == [100, 250, 75], "previous month's bucket is excluded")
let d4 = APIAccount.deriveDaily([:], monthStart: nov1, todayStart: nov4)
check(d4.daily.isEmpty && d4.lastDayCents == 0 && d4.lastDayIsToday == false, "empty input -> ([], 0, false)")

print("foldCost:")
let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
let data: [[String: Any]] = [
    ["starting_at": "2026-11-01T00:00:00Z", "ending_at": "2026-11-02T00:00:00Z",
     "results": [["amount": "100.5", "currency": "USD"], ["amount": "50", "currency": "USD"]]],
    ["starting_at": "2026-11-02T00:00:00Z", "ending_at": "2026-11-03T00:00:00Z",
     "results": [["amount": "12.5", "currency": "USD"]]],
]
let f = APIAccount.foldCost(data, iso: iso, todayStart: day(2026, 11, 4))
approx(f.month, 163.0, 1e-9, "month sums all buckets")
approx(f.today, 0, 1e-9, "today is zero when no bucket reaches todayStart")
approx(f.byDay[nov1] ?? -1, 150.5, 1e-9, "byDay Nov 1")
approx(f.byDay[nov2] ?? -1, 12.5, 1e-9, "byDay Nov 2 ('12.5' parses as 12.5)")
check(f.byDay.count == 2, "byDay has two days")

print("APISpend.lastDayLabel:")
var sp = APISpend()
check(sp.lastDayLabel == "yesterday", "default label is yesterday")
sp.lastDayIsToday = true
check(sp.lastDayLabel == "today", "label is today when lastDayIsToday")

print("looksLikeAdminKey:")
check(APIAccount.looksLikeAdminKey("sk-ant-admin01-abc"), "admin key accepted")
check(!APIAccount.looksLikeAdminKey("sk-ant-api03-abc"), "regular key rejected")
check(APIAccount.looksLikeAdminKey(" sk-ant-admin01-x "), "surrounding whitespace is trimmed")

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
