import SwiftUI
import Charts

extension View {
    /// Kill the system keyboard-focus ring (the roaming green box under Full Keyboard Access) across a
    /// whole subtree. Applied at the popover/account roots so no control ever draws a focus outline in
    /// these display-only surfaces. macOS 14+ disables the effect subtree-wide; on 13 it is a no-op and
    /// the per-button `.focusable(false)` handles the interactive rows.
    @ViewBuilder func noFocusRing() -> some View {
        if #available(macOS 14.0, *) { self.focusEffectDisabled() } else { self }
    }
}

/// The whole self-explanation affordance: one faint 8.5pt question dot whose tooltip carries the
/// plain-English note. Subtle by design (owner rule: explanations take no space). Gated by the
/// "Explain each section" setting; the tooltip on the label itself works even when the dot is off.
struct ExplainDot: View {
    var text: String
    var p: Palette
    var on: Bool = true
    var body: some View {
        if on {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 8.5))
                .foregroundStyle(p.faint).opacity(0.55)
                .help(text)
                .accessibilityLabel("What is this?")
                .accessibilityHint(text)
        }
    }
}

// Preview an alert sound when the user picks one in Settings. Plays the exact bundled asset the
// notification will use (falling back to the named system sound, or a beep for the default).
func previewAlertSound(_ name: String) {
    if name.isEmpty { NSSound.beep(); return }
    if let url = Bundle.main.url(forResource: name, withExtension: "wav"),
       let s = NSSound(contentsOf: url, byReference: true) { s.play() }
    else { NSSound(named: name)?.play() }
}

// MARK: - Claude palette

// Usage accent: clay → burnt → rust. Works on light and dark.
func gaugeColor(_ pct: Double, _ over: Bool) -> Color {
    if over || pct >= 0.90 { return Color(red: 0.63, green: 0.20, blue: 0.10) }   // rust  #A0341A
    if pct >= 0.60         { return Color(red: 0.76, green: 0.37, blue: 0.24) }   // burnt #C15F3C
    return Color(red: 0.85, green: 0.47, blue: 0.34)                              // clay  #D97757
}
let kSlate = Color(red: 0.49, green: 0.56, blue: 0.65)   // time accent #7E8EA6

struct Palette {
    var bg, ink, sub, faint, track, divider, live, session, weekly, warning, overLimit, raisedBg: Color
    // The selected whole-app palette. AppSettings keeps this in sync; views read it via of().
    static var current: PalettePreset = .stoneClay
    // raisedBg (spec 2.1): inner chart-card / raised-surface fill. Derived per preset as bg blended
    // 30% toward track in the same scheme, unless an explicit anchor hex is passed (Stone & Clay).
    private static func pal(_ bg: String, _ ink: String, _ sub: String, _ faint: String, _ track: String, _ divider: String, _ live: String, _ session: String, _ weekly: String, _ warning: String, _ overLimit: String, _ raised: String? = nil) -> Palette {
        let raisedC: Color = raised.map { Color(hex: $0) }
            ?? Color(nsColor: (NSColor(hex: bg) ?? .windowBackgroundColor).blended(to: NSColor(hex: track) ?? .windowBackgroundColor, 0.30))
        return Palette(bg: Color(hex: bg), ink: Color(hex: ink), sub: Color(hex: sub), faint: Color(hex: faint), track: Color(hex: track), divider: Color(hex: divider), live: Color(hex: live), session: Color(hex: session), weekly: Color(hex: weekly), warning: Color(hex: warning), overLimit: Color(hex: overLimit), raisedBg: raisedC)
    }
    // Theme generator (spec area 7 mk()): derive the neutral roles from a bg/ink pair + two hero hues,
    // so a new theme needs only four hexes per scheme. sub/faint/track/divider fall out by blending; live,
    // warning, and overLimit use the shared scheme-aware role constants, keeping the role contract intact.
    private static func gen(_ bg: String, _ ink: String, _ session: String, _ weekly: String, dark: Bool) -> Palette {
        let bgN = NSColor(hex: bg) ?? .windowBackgroundColor, inkN = NSColor(hex: ink) ?? .labelColor
        let track = bgN.blended(to: inkN, 0.11)
        func c(_ t: CGFloat) -> Color { Color(nsColor: inkN.blended(to: bgN, t)) }   // ink shaded toward bg
        return Palette(bg: Color(hex: bg), ink: Color(hex: ink), sub: c(0.42), faint: c(0.60),
                       track: Color(nsColor: track), divider: Color(nsColor: bgN.blended(to: inkN, 0.13)),
                       live: Color(hex: dark ? "5FB585" : "4E9E6E"), session: Color(hex: session), weekly: Color(hex: weekly),
                       warning: Color(hex: dark ? "E0A23F" : "B8801C"), overLimit: Color(hex: dark ? "D2553A" : "A0341A"),
                       raisedBg: Color(nsColor: bgN.blended(to: track, 0.30)))
    }
    static func of(_ s: ColorScheme) -> Palette {
        let dark = s == .dark
        // pal(bg, ink, sub, faint, track, divider, live, SESSION, WEEKLY, WARNING, OVERLIMIT). session +
        // weekly are the two hero metric colors; warning + overLimit are the threshold + over-limit roles,
        // no longer borrowed from the accent ramp. All 11 roles are defined per theme, light and dark.
        switch current {
        case .stoneClay:       return dark ? pal("1A1917", "F2EFE8", "9C958A", "726B60", "2E2C28", "2E2C28", "5FB585", "DB7551", "8696AC", "E0A23F", "D2553A", "211F1C") : pal("F6F3ED", "211F1B", "6E685F", "938C81", "E5E0D6", "E5E0D6", "4E9E6E", "C25A35", "5E7186", "B8801C", "A0341A", "EEEAE1")
        case .clayLedger:      return dark ? pal("1B1A18", "F3EFE7", "A9A294", "6F695D", "2C2A26", "34312C", "E08A6B", "E08A6B", "8C9BB0", "E0A23F", "D2553A") : pal("F4F2EC", "1F1E1D", "6F6A60", "A39C8E", "E4DFD4", "DAD4C8", "C75D3C", "C75D3C", "5E7186", "B8801C", "A0341A")
        case .graphiteSlate:   return dark ? pal("161B21", "E8ECF2", "97A4B5", "5E6B7C", "242C35", "2D3640", "8FA3C0", "DE8158", "8FA3C0", "E0A23F", "DE6A4A") : pal("F2F4F7", "1C2530", "5E6B7C", "9AA6B5", "E1E6EC", "D5DBE3", "4F6B92", "C2633E", "4F6B92", "B8801C", "A33A1E")
        case .paperWhite:      return dark ? pal("0A0A0A", "FAFAFA", "B0B0B0", "6E6E6E", "1E1E1E", "2A2A2A", "FF6A45", "FF6A45", "9AA6B5", "E0A23F", "E8492B") : pal("FFFFFF", "111111", "5A5A5A", "9A9A9A", "ECECEC", "E0E0E0", "C53D1C", "C53D1C", "596A7B", "B8801C", "A0341A")
        case .sageLinen:       return dark ? pal("171A14", "ECEFE4", "9BA78C", "626B55", "252A20", "2E3427", "7FB089", "D89A63", "82B58E", "E0A23F", "D2553A") : pal("F1F3EC", "23291F", "5C6852", "97A189", "E2E6D9", "D6DBCB", "4C7A58", "B26A34", "4C7A58", "B8801C", "A0341A")
        case .midnightInk:     return dark ? pal("0E1620", "E6EEF6", "8FA3B7", "56697E", "1A2532", "22303F", "5BA3D0", "E0A24A", "5BA3D0", "E0A23F", "D2553A") : pal("EEF2F6", "16202B", "566678", "90A0B2", "DEE5EC", "D1DAE3", "2E7CB0", "C97A28", "2E7CB0", "B8801C", "A0341A")
        case .blushPastel:     return dark ? pal("1E1619", "F4E8ED", "B795A1", "735C64", "2C2126", "362830", "D88FAB", "E08FAE", "B49ACB", "E0A23F", "D2553A") : pal("FBF1F4", "2E2228", "7A6068", "BAA1A9", "F1E0E6", "EAD3DB", "B85F80", "B85F80", "7E6AA0", "B8801C", "A0341A")
        case .monoSlate:       return dark ? pal("1A1A19", "F0F0EE", "A0A09C", "65655F", "272725", "30302D", "C9C9C5", "C49A78", "9AA4B2", "E0A23F", "D2553A") : pal("F5F5F4", "1A1A19", "646461", "9E9E9A", "E6E6E4", "DBDBD8", "3D3D3B", "9A6F4E", "5F6B7A", "B8801C", "A0341A")
        case .electricPlum:    return dark ? pal("15101F", "EEE8FA", "A493C7", "665789", "211934", "2C2145", "A26BFF", "E0865E", "B07BE0", "E0A23F", "D2553A") : pal("F4F1FB", "1E1830", "615680", "9E92BD", "E6DEF6", "DAD0EF", "8B2FB0", "C2603A", "8B2FB0", "B8801C", "A0341A")
        case .harvestAmber:    return dark ? pal("1C1710", "F4ECDA", "B49C72", "766443", "2A2216", "352B1C", "E0A23F", "E0A23F", "8FA3C0", "C98A3A", "D2553A") : pal("FAF4E8", "2A2113", "73603B", "B39F75", "EFE4CC", "E7D8B9", "B5701A", "B5701A", "5E7186", "9A6A12", "A0341A")
        case .tealMist:        return dark ? pal("0F1A18", "E3F1ED", "86A8A0", "4E6B64", "1A2925", "22332F", "3FB7A1", "DE8158", "4FC0AA", "E0A23F", "D2553A") : pal("EDF5F3", "152824", "4F6E68", "8AA8A2", "DCEAE6", "CCE0DB", "1E8472", "C2633E", "1E8472", "B8801C", "A0341A")
        case .carbonLime:      return dark ? pal("121309", "EDEFE2", "9DA486", "5C6147", "1E2012", "272A18", "A6E22E", "A6E22E", "8FA3C0", "E0A23F", "D2553A") : pal("F3F4EE", "1C1F14", "5E6450", "979C82", "E4E6DA", "D8DBCB", "6F9913", "6F9913", "5E7186", "B8801C", "A0341A")
        case .porcelainIndigo: return dark ? pal("13141C", "ECEDF4", "9499B8", "585D7C", "1F2130", "282A3C", "7385F0", "DB7551", "7385F0", "E0A23F", "D2553A") : pal("F6F5F1", "1A1C2B", "555A78", "9398B4", "E7E6E0", "DCDBD3", "3848BE", "C2603A", "3848BE", "B8801C", "A0341A")
        // Generator-derived presets (spec area 7): bg, ink, session, weekly - the neutrals fall out.
        case .rosewood:     return dark ? gen("1C1614", "F2E7E4", "D9765F", "B29098", dark: true) : gen("FBF3F1", "2B1F1E", "B04A3E", "8A6E74", dark: false)
        case .forestNight:  return dark ? gen("121A14", "E6EFE6", "E0975C", "6FB07E", dark: true) : gen("F0F4EE", "1B241B", "C2703A", "4C7A55", dark: false)
        case .oceanDeep:    return dark ? gen("0E181F", "E4EEF4", "E0805F", "56B0CC", dark: true) : gen("EEF3F6", "16232B", "C65A44", "2E7A96", dark: false)
        case .sandstone:    return dark ? gen("1C1810", "F1E9DA", "E0925A", "97A0B0", dark: true) : gen("F7F1E8", "2A2318", "BE6A34", "6B7280", dark: false)
        case .plumDusk:     return dark ? gen("18131E", "EDE6F2", "DB6FA0", "9184D6", dark: true) : gen("F4F1F6", "241C2A", "B5487F", "6355A0", dark: false)
        case .espresso:     return dark ? gen("17110C", "EEE6DA", "E0A63F", "A79C8E", dark: true) : gen("F3EEE9", "241C15", "B0781E", "70685E", dark: false)
        case .arcticBlue:   return dark ? gen("0E141C", "E6EEF6", "5A9FE0", "8F9AAC", dark: true) : gen("F0F4F8", "1A222C", "2E6FB0", "5E6B7A", dark: false)
        case .honeyOat:     return dark ? gen("1B170E", "F1EAD8", "E0B355", "9FAC7E", dark: true) : gen("FAF5E9", "292417", "C08A2E", "6E7A52", dark: false)
        }
    }
}

// fmtTok + money moved to Sources/Format.swift (Foundation-pure, headless-testable).
func resetDayString(_ date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "EEE h:mm a"; return f.string(from: date)
}

/// Clock time alone ("4:12 PM"), or with the weekday when it is not today - a run-out three days out
/// must not read as this afternoon.
func shortClock(_ date: Date, now: Date = Date()) -> String {
    let f = DateFormatter()
    f.dateFormat = Calendar.current.isDate(date, inSameDayAs: now) ? "h:mm a" : "EEE h a"
    return f.string(from: date)
}

/// Label for the ends of a chart window. A 7-day window starts and ends on the SAME weekday, so a
/// clock-and-weekday format would print "Mon 11 PM" at both ends; anything spanning more than a day
/// gets the calendar date instead.
func windowEdgeLabel(_ date: Date, window: TimeInterval) -> String {
    let f = DateFormatter()
    f.dateFormat = window > 36 * 3600 ? "MMM d" : "h:mm a"
    return f.string(from: date)
}

// weekLeftString + weekRingText + ringText moved to Sources/Format.swift (now: Date = Date() for testability).

// MARK: - Bar + ring

struct HBar: View {
    var pct: Double; var color: Color; var track: Color; var height: CGFloat = 9
    /// 0 at rest, ramping to 1 at the cap. Spec 4.2 DELETES the permanent progress-bar glow:
    /// the bar is a FLAT fill at rest and only earns its glow (and the overLimit tint) at redline.
    var redline: Double = 0
    var overLimit: Color? = nil
    var a11yLabel: String? = nil       // spec 4.8: bars announce their value + updatesFrequently
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        GeometryReader { g in
            let w = max(height, g.size.width * pct)
            let r = max(0, min(1, redline))
            let fill = (r > 0 && overLimit != nil) ? color.blended(to: overLimit!, r) : color
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)                                                   // flat fill at rest (4.2)
                    .frame(width: w)
                    .shadow(color: fill.opacity(0.45 * r), radius: r > 0 ? 6 : 0) // redline-only glow (4.4.3)
                    .animation(reduce ? nil : .settle, value: pct)                // 480ms settle (7.5)
                    .animation(reduce ? nil : .emberEase(Dur.d320), value: r)
            }
        }.frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(a11yLabel ?? "Usage bar")
        .accessibilityValue("\(Int((min(1, max(0, pct)) * 100).rounded())) percent")
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityHidden(a11yLabel == nil)   // unlabeled decorative bars stay silent
    }
}

// A per-model WEEKLY CAP line (limits[]): reads as a LIMIT - a "used" bar + "% left" - matching the
// all-models weekly bar. The binding (is_active) cap gets the bolder name + a leading ember dot.
// Shared by the popover and the Account window so both speak the same language.
struct CapLimitRow: View {
    let m: ScopedLimit; let p: Palette; var barColor: Color = kSlate; var nameWidth: CGFloat = 52
    var body: some View {
        HStack(spacing: 8) {
            if m.active { Circle().fill(p.session).frame(width: 4, height: 4) } else { Spacer().frame(width: 4) }
            Text(m.label).font(.system(size: 12, weight: m.active ? .semibold : .regular))
                .foregroundStyle(m.active ? p.ink : p.sub).frame(width: nameWidth, alignment: .leading).lineLimit(1)
            HBar(pct: m.pct, color: m.active ? barColor : barColor.opacity(0.6), track: p.track, height: 5,
                 a11yLabel: "\(m.label) weekly cap")
            Text("\(Int((m.remaining * 100).rounded()))% left")
                .font(.system(size: 12, weight: .medium, design: .monospaced)).monospacedDigit()
                .foregroundStyle(p.ink).fixedSize()
        }
        .help("\(m.label): \(Int((m.pct * 100).rounded()))% of its own weekly cap used" + (m.resetAt.map { ", resets \(resetDayString($0))" } ?? ""))
    }
}


// A restrained, on-brand hue per model family for the BY MODEL share split (clay / slate / sage /
// sand). Distinct enough to read at a glance, muted enough to stay calm.
func modelHue(_ family: String, _ p: Palette) -> Color {
    switch family {
    case "Fable":  return Color(hex: kAccentHex)
    case "Opus":   return kSlate
    case "Sonnet": return Color(red: 0.46, green: 0.58, blue: 0.52)
    case "Haiku":  return Color(red: 0.66, green: 0.56, blue: 0.44)
    default:       return p.sub
    }
}

// BY MODEL = where the week actually went: ONE segmented bar (not a stack of per-model progress bars,
// which duplicated the Fable cap bar) split by each model's share, with a compact 2-column legend
// beneath so up to four models fit the narrow popover without the labels wrapping.
struct ByModelSplit: View {
    let usage: [ModelUse]; let p: Palette
    var body: some View {
        let legend = Array(usage.prefix(4))
        let rows = stride(from: 0, to: legend.count, by: 2).map { Array(legend[$0 ..< min($0 + 2, legend.count)]) }
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { g in
                let gap: CGFloat = 1.5
                let avail = max(0, g.size.width - gap * CGFloat(max(0, usage.count - 1)))
                HStack(spacing: gap) {
                    ForEach(usage) { u in
                        modelHue(u.label, p).frame(width: avail * min(1, max(0, u.share)))
                    }
                }
            }
            .frame(height: 7).clipShape(Capsule())
            VStack(alignment: .leading, spacing: 5) {
                ForEach(rows.indices, id: \.self) { ri in
                    HStack(spacing: 0) {
                        ForEach(rows[ri]) { u in
                            HStack(spacing: 5) {
                                Circle().fill(modelHue(u.label, p)).frame(width: 6, height: 6)
                                Text(u.label).font(.system(size: 11)).foregroundStyle(p.sub).fixedSize()
                                Text(u.share < 0.005 ? "<1%" : "\(Int((u.share * 100).rounded()))%")
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(p.faint).monospacedDigit().fixedSize()
                            }
                            .frame(width: 108, alignment: .leading)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

struct TimeRing: View {
    var frac: Double; var big: String; var small: String
    var track: Color; var ink: Color; var faint: Color; var ring: Color; var size: CGFloat = 60
    var body: some View {
        let lw = max(2.2, size * 0.05)
        let f = max(0.001, min(1, frac))
        ZStack {
            Circle().stroke(track, lineWidth: lw)
            // No implicit animation: the arc must not sweep in from 0 on first paint
            // (that read as bits of the ring "flying" onto the popover).
            // Angular gradient along the arc (dim tail, bright head) for depth.
            Circle().trim(from: 0, to: f)
                .stroke(AngularGradient(colors: [ring.opacity(0.55), ring], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * f)),
                        style: StrokeStyle(lineWidth: lw, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // Rounded end cap dot, sitting EXACTLY on the arc centerline (radius = size/2, the
            // same circle the stroke is centered on). Same color as the arc head so it reads as
            // the arc's own tip, not a separate ornament; hidden when the arc is tiny or full.
            if f > 0.10, f < 0.985 {
                Circle().fill(ring)
                    .frame(width: lw * 1.3, height: lw * 1.3)
                    .offset(y: -size / 2)
                    .rotationEffect(.degrees(360 * f))
                    // Spec 4.4.2: the end dot is the arc's own tip - arc color, no halo, no glow, ever.
            }
            VStack(spacing: 0) {
                Text(big).font(.system(size: size * 0.30, weight: .medium, design: .serif)).foregroundStyle(ink)
                Text(small).font(.system(size: size * 0.185, weight: .medium)).foregroundStyle(faint)
            }
        }.frame(width: size, height: size)
    }
}

// MARK: - Usage detail (Layout B, Claude theme)

struct DetailCard: View {
    var snapshot: UsageSnapshot
    @ObservedObject var settings: AppSettings
    @ObservedObject var live: LiveActivity
    var refreshAnchor: Date = Date()
    var heartbeat: Int = 0          // spec 7.4: the gated refresh heartbeat (0 in QA harnesses)
    var period: Double = 30
    var signedIn: Bool = true            // false to show the inline sign-in card
    var loading: Bool = false            // true on cold start, before any data (skeleton)
    var dailySpark: [Double] = []        // last-7-days cost, normalized 0…1 (This-week mini bars)
    var records: [UsageRecord] = []      // per-call records (burn-chart spike attribution)
    var apiSpend: APISpend = APISpend()  // developer-API spend (separate account); popover line only when configured
    var onRefresh: () -> Void = {}
    var onSignIn: () -> Void = {}         // sign-in card + re-auth banner action
    var onOpenLogs: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var milestonePulse = false      // one heartbeat when crossing 25/50/75/threshold
    @State private var lastSessionPct: Double = 0
    @State private var milestoneFiredAt: [Int: Date] = [:]   // spec 7.5: 10-minute dedup per milestone
    // BY MODEL disclosure state lives in settings (not @State) so it survives the popover teardown on
    // close and reopens the way it was left. QA renders drive it via CUB_MODELS in qaSettings().

    @ViewBuilder
    private func eyebrow(_ t: String, _ p: Palette, note: String? = nil) -> some View {
        // The one eyebrow token (spec 2.3): SF 11pt semibold, +1.4 tracking, sub, uppercase.
        // Chrome-gated: the eyebrows-off switch (area 3) drops every section label.
        // The self-explanation layer is a single faint dot beside the label; the plain-English
        // note lives in its hover tooltip, so it costs zero space and zero attention.
        if settings.popoverEyebrows {
            HStack(spacing: 5) {
                Text(t.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(p.sub)
                if let note { ExplainDot(text: note, p: p, on: settings.popoverExplain) }
            }
            .padding(.bottom, settings.popoverCompact ? 6 : 8)
        }
    }

    // Compact dollar amount: "$112" or "$1.2k".
    private func money1k(_ v: Double) -> String { v < 1000 ? "$\(Int(v.rounded()))" : String(format: "$%.1fk", v / 1000) }

    // The one contextual line under the Session number. Returns (text, color).
    // Covers offline/stale ("last updated"), fresh window, sparse-forecast (low confidence),
    // approaching-limit (warning), and the normal time-to-limit forecast. Over-limit is shown
    // by the hero pill instead, so this returns nil there.
    private func sessionStateLine(_ liveState: LiveState, _ sColor: Color, _ p: Palette) -> (String, Color)? {
        let sp = snapshot.sessionPct
        if liveState == .offline || liveState == .stale {
            if let u = snapshot.liveUpdated {
                let s = max(0, Date().timeIntervalSince(u))
                let ago = s < 60 ? "\(Int(s))s" : s < 3600 ? "\(Int(s / 60))m" : "\(Int(s / 3600))h"
                return ("Last updated \(ago) ago, retrying", p.sub)
            }
            return ("Reconnecting", p.sub)
        }
        // Spec 4.6 over-limit: the reset time is the non-color cue (the OverPill above carries the
        // "Limit reached" label, so the caption adds the reset detail without repeating it).
        if snapshot.over {
            if let r = snapshot.sessionResetAt { return ("Resets in \(weekLeftString(r))", p.overLimit) }
            return nil
        }
        if sp <= 0.005 { return ("Fresh 5h window, nothing burned yet", p.faint) }
        guard let f = forecastToLimit(live.usageSamples, current: sp, resetAt: snapshot.sessionResetAt) else { return nil }
        let clean = f.replacingOccurrences(of: "~", with: "")
        // Sparse data: a confident-looking ETA can rest on a thin recent slice, so flag low confidence.
        let recent = live.usageSamples.filter { $0.t >= Date().addingTimeInterval(-90 * 60) }
        if recent.count < 3 { return ("Rough estimate, still warming up", p.sub) }
        if sp >= 0.8 { return (clean, p.warning) }
        return (clean, sColor.opacity(0.9))
    }

    // The Session readout line under the hero numeral: estimated cost and live burn rate, each shown
    // only when its Popover toggle is on, so "Estimated cost" / "Token rate" actually control something.
    private func sessionMeta() -> String {
        var parts: [String] = []
        if settings.showCost { parts.append("≈\(money1k(snapshot.sessionCost))") }
        if settings.showTokens { parts.append("\(fmtTok(Int(max(0, live.rate)))) tok/min") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let p = Palette.of(scheme)
        let userAccent = NSColor(hex: settings.accentHex) ?? NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
        let mode = settings.colorMode
        // Session follows the THEME's session color, unless the user picked a custom accent (then theirs wins).
        let accent = (settings.accentHex.uppercased() == kDefaultAccent.uppercased()) ? NSColor(p.session) : userAccent
        let sBase = Color(nsColor: usageNSColor(pct: snapshot.sessionPct, over: false, accent: accent, mode: mode))
        let sColor = snapshot.over ? p.overLimit : sBase
        // Week + rings use the theme's weekly color; over-limit flips to the overLimit role.
        let wColor = snapshot.weeklyOver ? p.overLimit : p.weekly
        let ringC = p.weekly
        let liveAccent = (mode == .system) ? p.sub : Color(nsColor: accent)
        let liveDot: Color = {
            switch settings.liveColor {
            case .theme:  return p.live
            case .accent: return Color(nsColor: accent)
            case .green:  return Color(hex: kLiveGreen)
            case .off:    return p.sub
            }
        }()
        let liveState: LiveState = {
            if !snapshot.isLive {
                if let e = snapshot.liveError, !e.isEmpty {
                    let le = e.lowercased()
                    return (le.contains("429") || le.contains("rate") || le.contains("limit")) ? .rateLimited : .offline
                }
                return .est
            }
            if let u = snapshot.liveUpdated, Date().timeIntervalSince(u) > max(150, period * 4) { return .stale }
            return .live
        }()
        // Re-auth: signed in but the token was rejected (no usable token / 401 / invalid).
        let reauth: Bool = {
            guard signedIn, let e = snapshot.liveError?.lowercased() else { return false }
            return e.contains("no token") || e.contains("401") || e.contains("auth") || e.contains("invalid")
        }()
        let title = snapshot.plan.map { "Claude \($0)" } ?? kAppName

        Group {
            if !signedIn {
                signedOutCard(p)
            } else if loading {
                skeletonCard(p)
            } else {
                liveCard(p: p, title: title, sColor: sColor, wColor: wColor, ringC: ringC,
                         liveAccent: liveAccent, liveDot: liveDot, liveState: liveState, reauth: reauth)
            }
        }
        .padding(16)
        .frame(width: 264, alignment: .leading)
    }

    // Signed-in: the modular, reorderable, hideable sections (order + visibility from Settings).
    @ViewBuilder
    private func liveCard(p: Palette, title: String, sColor: Color, wColor: Color, ringC: Color,
                          liveAccent: Color, liveDot: Color, liveState: LiveState, reauth: Bool) -> some View {
        // The chart element folds the whole chart section away (spec area 3), dropping its divider too.
        let sections = settings.visibleSections().filter { $0 != .chart || settings.showBurnChart }
        VStack(alignment: .leading, spacing: 0) {
            if reauth { reauthBanner(p).padding(.bottom, 13) }
            ForEach(Array(sections.enumerated()), id: \.element) { idx, sec in
                if idx > 0, settings.popoverDividers {
                    // Flat 1px divider hairline (spec 4.2: gradient dividers CUT). Chrome-gated;
                    // when off, the 12pt block spacing alone separates sections.
                    Rectangle().fill(p.divider).frame(height: 1)
                        .padding(.vertical, settings.popoverCompact ? 10 : 12)
                } else if idx > 0 {
                    Spacer().frame(height: settings.popoverCompact ? 16 : 20)
                }
                switch sec {
                case .header:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(p.ink).tracking(-0.1)
                            Text("usage").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.faint)
                        }.lineLimit(1).minimumScaleFactor(0.6).layoutPriority(1)
                        Spacer(minLength: 6)
                        // Quiet-hours moon (spec 4.6 / area 3): a crescent leading the badge, text in the
                        // tooltip so the header title keeps its room; distinct from the connection state
                        // (data can be LIVE while alerts are muted).
                        if settings.quietHoursActive() {
                            Image(systemName: "moon.fill").font(.system(size: 10))
                                .foregroundStyle(p.faint).fixedSize()
                                .help("Alerts quiet until \(settings.quietUntilString)")
                                .accessibilityLabel("Alerts quiet until \(settings.quietUntilString)")
                        }
                        StatusBadge(state: liveState, over: snapshot.over, reauth: reauth, liveColor: liveDot, p: p,
                                    updated: snapshot.liveUpdated, period: period, anchor: refreshAnchor, heartbeat: heartbeat, onTap: onRefresh,
                                    tipAbove: (sections.firstIndex(of: .header) ?? 0) * 2 >= sections.count)
                            .fixedSize()
                    }
                    // Header aura CUT (spec 4.2): its attention job transfers to the redline bloom.
                    .zIndex(1)   // keep the badge's hover tooltip above the following divider/section
                case .session:
                    sessionSection(p: p, sColor: sColor, ringC: ringC, liveState: liveState)
                case .chart:
                    chartSection(p: p, liveAccent: liveAccent, ringC: ringC)
                case .week:
                    weekSection(p: p, wColor: wColor, ringC: ringC)
                }
            }
            // Developer API spend (spec area 4): one opt-in line at the very bottom, only when a key is
            // configured. No key -> neither this line nor its hairline exist, layout byte-for-byte unchanged.
            if settings.showDeveloperApiLine, apiSpend.configured, apiSpend.error == nil {
                Rectangle().fill(p.divider).frame(height: 1).padding(.vertical, settings.popoverCompact ? 10 : 12)
                developerApiLine(p)
            }
        }
    }

    // The one Developer-API line: a separate account, so it never merges into the SESSION or WEEK
    // percent blocks. Eyebrow + connection dot on the left, dollars (its only unit) right-aligned.
    private func developerApiLine(_ p: Palette) -> some View {
        HStack(spacing: 7) {
            Text("DEVELOPER API").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(p.sub).fixedSize()
            Circle().fill(p.live).frame(width: 5, height: 5)
            Spacer(minLength: 6)
            Text("$\(Int(apiSpend.monthToDate.rounded())) mo · $\(Int(apiSpend.today.rounded())) today")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(p.sub)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Developer API spend, \(Int(apiSpend.monthToDate.rounded())) dollars this month, \(Int(apiSpend.today.rounded())) dollars today")
    }

    private func sessionSection(p: Palette, sColor: Color, ringC: Color, liveState: LiveState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("Session", p, note: "Claude counts usage in 5-hour sessions. This is the current one: how much is used, and the time until a fresh session starts.")
            if snapshot.over { OverPill(color: p.overLimit).padding(.bottom, 7) }
            // Hero numeral and the draining reset ring share the top row; the cost and status lines run
            // full-width beneath so they share the left edge with the bar and never get boxed/truncated.
            HStack(alignment: .top, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    // Hero numeral (design rev 11): INK at rest, warming to the session L+-7 gradient FROM the
                    // heavy tier, flat overLimit past 100%. There is no permanent gradient - the card is a cool
                    // instrument until you burn hot.
                    let warmth = snapshot.over ? 1.0 : max(0, min(1, (snapshot.sessionPct - (settings.alertSessionAt - 0.15)) / 0.15))
                    let heroBase = Color(nsColor: NSColor(p.ink).blended(to: NSColor(sColor), CGFloat(warmth)))
                    Text("\(Int((snapshot.sessionPct * 100).rounded()))")
                        .font(.system(size: 60, weight: .semibold, design: .serif)).tracking(-0.5)
                        .foregroundStyle(snapshot.over ? AnyShapeStyle(p.overLimit)
                            : warmth > 0.02 ? AnyShapeStyle(LinearGradient(colors: [heroBase.brighten(0.10 * warmth), heroBase], startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(p.ink))
                        .monospacedDigit().numberAnim(reduce ? .none : settings.numberStyle, Int((snapshot.sessionPct * 100).rounded()))
                        .scaleEffect(milestonePulse ? 1.035 : 1, anchor: .leading)
                    Text("%").font(.system(size: 28, weight: .regular, design: .serif)).foregroundStyle(p.sub)
                }
                // Spec 4.8: the session block reads as ONE element with the full sentence.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Session")
                .accessibilityValue({
                    var s = snapshot.over ? "limit reached" : "\(Int((snapshot.sessionPct * 100).rounded())) percent used"
                    if settings.showCost { s += ", about \(money1k(snapshot.sessionCost))" }
                    if let r = snapshot.sessionResetAt { s += ", \(weekLeftString(r)) until reset" }
                    return s
                }())
                .accessibilityAddTraits(.updatesFrequently)
                // Milestone pulse (spec 7.5): UPWARD crossings of 25 / 50 / 75 / the user's threshold.
                // Numeral only, scale 1.0 -> 1.035 -> 1.0 on a 480ms settle, deduped for 10 minutes so a
                // value oscillating across a line does not strobe.
                .onChange(of: snapshot.sessionPct) { new in
                    let old = lastSessionPct; lastSessionPct = new
                    guard !reduce else { return }
                    let marks = [0.25, 0.50, 0.75, settings.alertSessionAt]
                    for m in marks where old < m && new >= m {
                        let key = Int((m * 1000).rounded())
                        if let fired = milestoneFiredAt[key], Date().timeIntervalSince(fired) < OneShot.milestone { continue }
                        milestoneFiredAt[key] = Date()
                        withAnimation(.settle) { milestonePulse = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + Dur.d240) {
                            withAnimation(.settle) { milestonePulse = false }
                        }
                        break   // one heartbeat per commit even if two lines are crossed at once
                    }
                }
                Spacer(minLength: 0)
                if settings.showTimeRing {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let rt = ringText(snapshot.sessionResetAt)
                    // Reset-imminent pulse: under 15 minutes to reset, the ring softly breathes -
                    // "hold on, a fresh window is close."
                    let secsLeft = snapshot.sessionResetAt.map { $0.timeIntervalSince(ctx.date) } ?? .infinity
                    let breathe = secsLeft > 0 && secsLeft < 10 * 60 && !reduce
                    // One Pulse (spec 7.2): breathe on the BurnClock tier period, not a free-running rate.
                    let tier = BurnClock.tier(usage: snapshot.sessionPct, over: snapshot.over,
                                              burnRatio: min(2, live.norm * 2), threshold: settings.alertSessionAt,
                                              tokensFlowing: live.active)
                    let ph = breathe ? (1 - cos(ctx.date.timeIntervalSinceReferenceDate * 2 * .pi / tier.period)) / 2 : 0
                    TimeRing(frac: rt.0, big: rt.1, small: rt.2, track: p.track, ink: p.ink, faint: p.faint, ring: ringC, size: 62)
                        .shadow(color: ringC.opacity(0.18 + 0.30 * ph), radius: breathe ? 5 : 0)
                        .accessibilityLabel("Session resets in \(rt.1) \(rt.2)")
                }
                }
            }.padding(.top, 2)
            if !sessionMeta().isEmpty {
                Text(sessionMeta())
                    .font(.system(size: 13, design: .monospaced)).foregroundStyle(p.sub).padding(.top, 8).lineLimit(1)
                    .help("What this session's usage would have cost at pay-as-you-go API prices (you are not billed this; your subscription covers it), and how many tokens per minute are flowing right now. Tokens are the small chunks of text Claude reads and writes.")
            }
            // The forecast line is user-hideable, but the over-limit / offline STATE cue always shows
            // (it is a fact about the data, not a projection).
            if (settings.showForecastLine || snapshot.over || liveState == .offline || liveState == .stale),
               let st = sessionStateLine(liveState, sColor, p) {
                Text(st.0).font(.system(size: 13, weight: .medium)).foregroundStyle(st.1).padding(.top, 2).lineLimit(1)
                    .help("Session status: time to limit, approaching limit, offline, or a fresh window.")
            }
            // Spec 4.2/4.4.3: flat fill at rest; the glow and the overLimit tint are redline-only.
            HBar(pct: snapshot.sessionPct, color: sColor, track: p.track, height: 7,
                 redline: snapshot.over ? 1 : max(0, (min(1, snapshot.sessionPct) - 0.85) / 0.15),
                 overLimit: p.overLimit, a11yLabel: "Session usage").padding(.top, 13)
        }
    }

    // The chart in its own quiet card: a 4% ink tint, not elevation (no inner shadow).
    private func chartSection(p: Palette, liveAccent: Color, ringC: Color) -> some View {
        MonitorChart(live: live, kinds: settings.chartKinds, sessionPct: snapshot.sessionPct,
                     weeklyPct: snapshot.weeklyPct, accent: liveAccent, secondary: ringC, p: p,
                     anchor: refreshAnchor, period: period, burnSpan: settings.burnSpan,
                     chartStyle: settings.chartStyle, showCadence: settings.showCountdownRing,
                     sessionResetAt: snapshot.sessionResetAt, weeklyResetAt: snapshot.weeklyResetAt,
                     chartDays: settings.chartDays, modelLimits: snapshot.modelLimits,
                     chartHover: settings.chartHover,
                     showChats: settings.showChatsBurning, chatsOpen: $settings.chatsExpanded,
                     truncation: settings.chatTruncation, records: records, explain: settings.popoverExplain)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(p.raisedBg))
    }

    private func weekSection(p: Palette, wColor: Color, ringC: Color) -> some View {
        // Layout groups by SCOPE so nothing reads out of place:
        //   ALL MODELS  -> the big weekly % + its 7-day history spark (both are the whole-account total)
        //   PER MODEL   -> the model caps that have their own weekly limit (Fable), always visible since
        //                  a cap can be the binding constraint; then a COLLAPSED "by model" share split.
        // The share split is one segmented bar (not per-model progress bars), so a model never shows two
        // separate bars, and the spark no longer sits marooned between a cap row and the share list.
        let resetCaption = settings.showWeekResets ? snapshot.weeklyResetAt.map { weekLeftString($0) + " left" } : nil
        let caps = snapshot.modelLimits
        let usage = snapshot.modelUsage
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if settings.popoverEyebrows {
                    Text("THIS WEEK").font(.system(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(p.sub)
                    ExplainDot(text: "Your weekly allowance across every model. Some models also carry their own weekly cap, listed below.", p: p, on: settings.popoverExplain)
                }
                Spacer(minLength: 8)
                if let rc = resetCaption {
                    Text(rc).font(.system(size: 12, design: .monospaced)).foregroundStyle(p.sub).lineLimit(1)
                }
            }.padding(.bottom, settings.popoverCompact ? 6 : 8)
            // ── ALL MODELS: the weekly pool everything counts against ──
            if settings.showWeekPercent {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int((snapshot.weeklyPct * 100).rounded()))")
                            .font(.system(size: 30, weight: .semibold, design: .serif)).tracking(-0.25)
                            .foregroundStyle(wColor)
                            .monospacedDigit().numberAnim(reduce ? .none : settings.numberStyle, Int((snapshot.weeklyPct * 100).rounded()))
                        Text("%").font(.system(size: 15, weight: .regular, design: .serif)).foregroundStyle(p.sub)
                    }
                    HBar(pct: snapshot.weeklyPct, color: wColor, track: p.track, height: 5, a11yLabel: "Weekly usage, all models").padding(.bottom, 6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("This week, all models")
                .accessibilityValue("\(Int((snapshot.weeklyPct * 100).rounded())) percent used")
            } else {
                HBar(pct: snapshot.weeklyPct, color: wColor, track: p.track, height: 5, a11yLabel: "Weekly usage").padding(.top, 4)
            }
            // 7-day history belongs with the all-models total, right beneath it.
            if settings.showLast7Days, dailySpark.contains(where: { $0 > 0 }) {
                HStack(alignment: .bottom, spacing: 5) {
                    HStack(alignment: .bottom, spacing: 3) {   // 5pt bars / 3pt gap (design annotation 9)
                        ForEach(Array(dailySpark.suffix(7).enumerated()), id: \.offset) { i, v in
                            let isToday = i == min(6, dailySpark.count - 1)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(isToday ? wColor : wColor.opacity(0.55))
                                .frame(width: 5, height: 3 + 13 * max(0, min(1, v)) + (isToday ? 1 : 0))
                        }
                    }
                    Spacer(minLength: 8)   // "LAST 7 DAYS" label right-aligned (design)
                    Text("LAST 7 DAYS").font(.system(size: 9, weight: .bold)).tracking(0.8)
                        .foregroundStyle(p.sub).padding(.bottom, 1)
                }
                .frame(height: 16, alignment: .bottom).padding(.top, 8)
                .help("Your daily usage over the last 7 days, tallest bar = your busiest day. Today is the highlighted bar on the right.")
            }
            // ── PER MODEL: caps (a model with its own weekly limit) stay visible; the share split hides ──
            if !caps.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(caps) { capRow($0, p, wColor) }
                }.padding(.top, 12)
            }
            if settings.showOpusShare, !usage.isEmpty {
                Button { withAnimation(.emberEase(Dur.d120)) { settings.modelsExpanded.toggle() } } label: {
                    HStack(spacing: 6) {
                        Text("BY MODEL").font(.system(size: 10, weight: .semibold)).tracking(1.0).foregroundStyle(p.sub)
                        Text("share of week").font(.system(size: 9)).foregroundStyle(p.faint)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(p.faint).rotationEffect(.degrees(settings.modelsExpanded ? 90 : 0))
                    }.frame(height: 22).contentShape(Rectangle())
                }.buttonStyle(.plain).focusable(false).padding(.top, caps.isEmpty ? 12 : 9)
                if settings.modelsExpanded {
                    ByModelSplit(usage: usage, p: p).padding(.top, 6)
                }
            }
        }
    }

    private func capRow(_ m: ScopedLimit, _ p: Palette, _ wColor: Color) -> some View {
        CapLimitRow(m: m, p: p, barColor: wColor)
    }

    // A labeled footer row: a fixed-width uppercase label clearly owns its value.
    // Footer row; pass `bar` (0…1) to add a micro progress bar after the value, so the per-model
    // weekly shares read at a glance instead of as bare numbers.
    private func footRow(_ label: String, _ value: String, _ p: Palette,
                         bar: Double? = nil, barColor: Color = .clear, active: Bool = false) -> some View {
        // Footer row: label left, value right-aligned. Plain rows (resets) stay text-only per the
        // design; a per-model weekly row passes `bar` to add a small usage bar and, when it's the
        // binding limit (`active`), an ember dot + the session-hue label so it reads as "the one to watch".
        HStack(spacing: 8) {
            if active { Circle().fill(p.session).frame(width: 4, height: 4) }
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.0)
                .foregroundStyle(active ? p.session : p.sub).lineLimit(1)
            if let bar {
                ZStack(alignment: .leading) {
                    Capsule().fill(p.track).frame(width: 34, height: 4)
                    Capsule().fill(barColor).frame(width: max(2, 34 * min(1, max(0, bar))), height: 4)
                }
            }
            Spacer(minLength: 8)
            Text(value).font(.system(size: 13, weight: active ? .medium : .regular))
                .foregroundStyle(active ? p.ink : p.sub).lineLimit(1).monospacedDigit()
        }
    }

    // Re-auth banner: the token expired; tap to sign in again.
    private func reauthBanner(_ p: Palette) -> some View {
        Button(action: onSignIn) {
            HStack(spacing: 9) {
                Image(systemName: "key.fill").font(.system(size: 11))
                Text("Sign-in expired").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 6)
                Text("Re-auth").font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(p.overLimit)
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(p.overLimit.opacity(0.13)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(p.overLimit.opacity(0.30), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    // Signed-out: an inline sign-in card replaces the whole popover body.
    private func signedOutCard(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(kAppName).font(.system(size: 16, weight: .bold, design: .serif)).foregroundStyle(p.ink)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill").font(.system(size: 9))
                    Text("SIGNED OUT").font(.system(size: 10, weight: .bold)).tracking(0.8).lineLimit(1)
                }.fixedSize().foregroundStyle(p.sub).padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(p.faint.opacity(0.22)))
            }.padding(.bottom, 13)
            Rectangle().fill(p.divider).frame(height: 1)
            VStack(spacing: 0) {
                LivingFlameMark(size: 34).padding(.top, 16).padding(.bottom, 12)   // spec area 1: living in the sign-in card
                Text("Connect your plan").font(.system(size: 19, weight: .semibold, design: .serif)).foregroundStyle(p.ink)
                Text("See your session and weekly usage the moment you sign in.")
                    .font(.system(size: 13)).foregroundStyle(p.sub).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 200)
                    .padding(.top, 4).padding(.bottom, 16)
                Button(action: onSignIn) {
                    Text("Sign in to Claude").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 9).fill(p.session))
                }.buttonStyle(.plain)
                Button(action: onOpenLogs) {
                    Text("Open diagnostic logs").font(.system(size: 12)).foregroundStyle(p.sub)
                }.buttonStyle(.plain).padding(.top, 10)
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill").font(.system(size: 9))
                    Text(kTrustSentence).font(.system(size: 11)).multilineTextAlignment(.center)
                }.foregroundStyle(p.faint).padding(.top, 13)
            }.frame(maxWidth: .infinity).padding(.top, 14)
        }
    }

    // Warming-up skeleton: cold start, before the first data lands.
    private func skeletonCard(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Claude").font(.system(size: 16, weight: .bold)).foregroundStyle(p.ink)
                Text("usage").font(.system(size: 16, weight: .semibold)).foregroundStyle(p.faint)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "clock").font(.system(size: 9, weight: .bold))
                    Text("WARMING UP").font(.system(size: 10, weight: .bold)).tracking(0.8).lineLimit(1)
                }.fixedSize().foregroundStyle(p.warning).padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(p.warning.opacity(0.16)))
            }.padding(.bottom, 13)
            Rectangle().fill(p.divider).frame(height: 1).padding(.bottom, 14)
            eyebrow("Session", p)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) { Skeleton(w: 120, h: 48, p: p); Skeleton(w: 60, h: 13, p: p) }
                Spacer()
                Skeleton(w: 62, h: 62, p: p, circle: true)
            }
            Skeleton(w: nil, h: 7, p: p).padding(.top, 14)
            Rectangle().fill(p.divider).frame(height: 1).padding(.vertical, 14)
            Skeleton(w: nil, h: 74, p: p, radius: 12)
        }
    }
}

// One expanding-and-fading ring - fires once per refresh (recreated via .id).
private struct PingRing: View {
    var color: Color
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        Circle().stroke(color, lineWidth: 1).frame(width: 7, height: 7)
            .scaleEffect(on ? 2.1 : 1).opacity(on ? 0 : 0.45)
            .onAppear { if !reduce { withAnimation(.easeOut(duration: 0.9)) { on = true } } }   // reduce motion: static ring
    }
}

struct StatusBadge: View {
    var state: LiveState
    var over: Bool = false
    var reauth: Bool = false
    var liveColor: Color
    var p: Palette
    var updated: Date?
    var period: Double = 30
    var anchor: Date = Date()      // when the current refresh cycle started (pings the dot)
    var heartbeat: Int = 0         // spec 7.4: bumped ONLY by a gated refresh heartbeat
    var onTap: () -> Void = {}
    var tipAbove: Bool = false     // show the tooltip above the badge (when the header sits low in the card)
    @State private var pingID = 0
    @State private var bump = false
    @State private var breathe = false   // CA-driven LIVE-dot breath (no per-frame SwiftUI work)
    @State private var hoverTip = false
    @State private var hoverToken = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduce

    private enum Kind { case live, est, stale, rate, offline, reauth, over }
    private var kind: Kind {
        if over { return .over }
        if reauth { return .reauth }
        switch state {
        case .live: return .live
        case .est: return .est
        case .stale: return .stale
        case .rateLimited: return .rate
        case .offline: return .offline
        }
    }
    private var label: String {
        switch kind {
        case .live: return "Live"; case .est: return "Est"
        case .stale:                                   // spec 4.6: STALE shows its age
            if let u = updated {
                let s = max(0, Date().timeIntervalSince(u))
                return "Stale " + (s < 3600 ? "\(Int(s / 60))m" : "\(Int(s / 3600))h")
            }
            return "Stale"
        case .rate: return "Rate-limited"; case .offline: return "Offline"
        case .reauth: return "Re-auth"; case .over: return "Over limit"
        }
    }
    // Distinct roles per state (no longer borrowing amber/rust from the accent ramp).
    private var tint: Color {
        switch kind {
        case .live: return liveColor
        case .est, .stale, .rate: return p.warning
        case .offline: return p.sub
        case .reauth, .over: return p.overLimit
        }
    }
    // Leading glyph so the state never reads by color alone. Live uses a pulsing dot instead.
    private var icon: String? {
        switch kind {
        case .live: return nil
        case .est: return "circle"
        case .stale: return "clock.arrow.circlepath"
        case .rate: return "hourglass"
        case .offline: return "wifi.slash"
        case .reauth: return "key.fill"
        case .over: return "exclamationmark.triangle.fill"
        }
    }
    private func fire() {
        pingID += 1
        guard !reduce else { return }   // reduce motion: no dot bump
        // Spec 7.4 @T+80: scale 1.0 -> 1.35 -> 1.0 on the flare curve, 720ms total.
        withAnimation(.flare(Dur.d240)) { bump = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + Dur.d240) {
            withAnimation(.emberEase(Dur.d480)) { bump = false }
        }
    }
    private var tipText: String {
        // Every state explains itself in plain English (audit M4): the badge is jargon to a
        // stranger, so the tooltip says what the state means and what to do about it.
        let age: String? = updated.map {
            let s = max(0, Date().timeIntervalSince($0))
            return s < 60 ? "\(Int(s))s" : s < 3600 ? "\(Int(s / 60))m" : "\(Int(s / 3600))h"
        }
        switch kind {
        case .live:
            return "Live: numbers straight from Claude's usage service." + (age.map { " Updated \($0) ago," } ?? "") + " click to refresh"
        case .est:
            return "Estimated from the Claude logs on this Mac. Sign in and turn on live usage for exact numbers. Click to refresh"
        case .stale:
            return "Live data is older than expected" + (age.map { " (\($0) ago)" } ?? "") + ". Showing the last numbers received. Click to retry"
        case .rate:
            return "Claude's usage service is asking us to slow down. Burndown retries gently on its own"
        case .offline:
            return "Could not reach Claude. Showing the last known numbers. Click to retry"
        case .reauth:
            return "Your sign-in expired or was revoked. Open Account from the menu and sign in again"
        case .over:
            return "You have hit this limit. Claude pauses until the window resets"
        }
    }

    var body: some View {
        let c = tint
        HStack(spacing: 5) {
            if kind == .live {
                ZStack {
                    PingRing(color: c).id(pingID)
                    // Spec 7.3: between heartbeats the LIVE dot breathes 0.80 + 0.20b on the tier
                    // period; its ping scales 1.0 -> 1.35 -> 1.0 (7.4).
                    // Driven by CORE ANIMATION, not a TimelineView. A TimelineView re-runs SwiftUI and
                    // re-commits the ENTIRE popover window (chart layers and all) on every tick - that
                    // is what made an idle popover cost 12-15%. A repeating opacity animation is
                    // interpolated by the render server instead: perfectly smooth at the display's full
                    // rate, and the app does no per-frame work at all.
                    Circle().fill(c).frame(width: 6, height: 6)
                        .opacity(breathe ? 1.0 : 0.80)
                        .animation(reduce ? nil : .easeInOut(duration: BurnTier.idle.period / 2)
                                                    .repeatForever(autoreverses: true), value: breathe)
                        .scaleEffect(bump ? 1.35 : 1)
                        .onAppear { breathe = true }
                }.frame(width: 7, height: 7)
            } else if let ic = icon {
                Image(systemName: ic).font(.system(size: 9, weight: .bold))
            }
            Text(label.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.8)
        }
        .foregroundStyle(c)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(c.opacity(0.16)))
        .contentShape(Capsule())
        .onTapGesture { onTap() }                       // → manualRefresh resets anchor → pings below
        // Fast custom tooltip (~600ms) - the system .help() tooltip takes ~2s. Anchored to the badge's
        // trailing edge so it flows left into the card, and flipped above when the header sits low.
        .overlay(alignment: tipAbove ? .bottomTrailing : .topTrailing) {
            if hoverTip {
                Text(tipText).font(.system(size: 10, weight: .medium)).foregroundStyle(.primary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.12), lineWidth: 0.5))
                    .fixedSize().offset(y: tipAbove ? -26 : 26).zIndex(10).transition(.opacity)
            }
        }
        .onHover { inside in
            if inside {
                let token = UUID(); hoverToken = token
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if hoverToken == token { withAnimation(.easeOut(duration: 0.12)) { hoverTip = true } }
                }
            } else { hoverToken = UUID(); withAnimation(.easeOut(duration: 0.1)) { hoverTip = false } }
        }
        // Spec 7.4: the heartbeat fires only when the refreshed data actually changed what is
        // displayed (gated + 5s rate-limited in UsageEngine). A silent refresh is silent.
        .onChange(of: heartbeat) { _ in if kind == .live { fire() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connection status: \(label)")
        .accessibilityValue(tipText)
        .accessibilityAddTraits(.isButton)
    }
}


// MARK: - MonitorChart (the real, instrumented analytics chart)


private func fmtMins(_ m: Double) -> String { m >= 90 ? String(format: "%.1fh", m / 60) : "\(Int(m.rounded()))m" }

// The in-popover chart picker (chip + overlay gallery) is gone on purpose: chart selection lives in
// Settings > Charts, which has room for real previews. The popover header now just names the chart.

struct MonitorChart: View {
    @ObservedObject var live: LiveActivity
    var kinds: [ChartKind]
    var sessionPct: Double
    var weeklyPct: Double
    var accent: Color        // session / burn series (clay / chosen accent / mono in None)
    var secondary: Color     // weekly line (slate / mono in None)
    var p: Palette
    var anchor: Date = Date()
    var period: Double = 30
    var burnSpan: ChartSpan = .h1
    var chartStyle: ChartStyle = .area
    var showCadence = true
    var sessionResetAt: Date? = nil   // burndown needs the window end to draw the pace line
    var weeklyResetAt: Date? = nil
    var chartDays: Int = 14           // span for the day-scale charts (cost, hour profile, heatmap)
    var modelLimits: [ScopedLimit] = []   // per-model weekly caps, for the Model limits chart
    var chartHover: Bool = true
    var showChats = true
    // Bound (not @State) so the chats list reopens the way the user left it: the popover discards its
    // content view on close, which would reset any local state (ADDENDUM C area 3).
    @Binding var chatsOpen: Bool
    var truncation: ChatTruncation = .middle
    var records: [UsageRecord] = []   // per-call usage records (spike attribution on hover)
    var explain = false               // self-explanation layer: each chart's blurb under its title
    /// Contact sheets label each cell themselves, so they turn the per-chart title row off to
    /// avoid printing the name twice.
    var chrome = true
    @State private var gearHover = false
    @ObservedObject private var chatNames = ChatNames.shared
    @State private var renaming: String? = nil
    @State private var renameText = ""

    /// Everything the chart bodies read, assembled once.
    private var ctx: ChartCtx {
        ChartCtx(burnSamples: live.burnSamples, usageSamples: live.usageSamples,
                 weeklySamples: live.weeklySamples, records: records,
                 sessionPct: sessionPct, weeklyPct: weeklyPct,
                 sessionResetAt: sessionResetAt, weeklyResetAt: weeklyResetAt,
                 modelLimits: modelLimits,
                 accent: accent, secondary: secondary, p: p, style: chartStyle,
                 window: burnSpan.seconds, days: chartDays, hover: chartHover)
    }

    var body: some View {
        let on = live.active
        let shown = kinds.isEmpty ? [ChartKind.burnBars] : kinds
        VStack(alignment: .leading, spacing: 7) {
            // One block per selected chart: a quiet title naming the view (its tooltip explains it in a
            // sentence), the body, and 14pt of air before the next. The gear on the first row opens
            // Settings > Charts, where selection and every chart option live.
            ForEach(Array(shown.enumerated()), id: \.element) { i, kind in
                if i > 0 { Spacer().frame(height: 7) }
                if chrome {
                HStack(spacing: 6) {
                    Text(kind.label.uppercased())
                        .font(.system(size: 9.5, weight: .semibold)).tracking(1.0)
                        .foregroundStyle(p.faint)
                        .help(kind.blurb)
                    ExplainDot(text: kind.blurb, p: p, on: explain)
                    Spacer()
                    if i == 0 {
                        Button { NotificationCenter.default.post(name: .openChartSettings, object: nil) } label: {
                            Image(systemName: "gearshape").font(.system(size: 10.5))
                                .foregroundStyle(gearHover ? p.sub : p.faint).opacity(gearHover ? 1 : 0.5)
                        }
                        .buttonStyle(.plain).focusable(false).help("Choose charts and chart options")
                        .onHover { gearHover = $0 }
                        .animation(.easeInOut(duration: 0.15), value: gearHover)
                    }
                }
                }
                ChartBodyView(kind: kind, ctx: ctx)
                    // One place for the refresh indicator: it lands on the trailing edge of the LAST
                    // chart's stat line, instead of every chart re-implementing it.
                    .overlay(alignment: .bottomTrailing) {
                        if showCadence, i == shown.count - 1 {
                            LiveCadence(on: on, accent: accent, faint: p.faint, track: p.track, anchor: anchor, period: period)
                        }
                    }
            }
            // Chats burning now (spec 4.4.5 / addendum 3): calm single-line rows, set off from the
            // chart by its own hairline with 12pt of air. Ranked ember dot + middle-truncated name +
            // rate. No per-row share bars. Roomy 12pt gaps.
            if showChats, !live.activeStreams.isEmpty {
                Rectangle().fill(p.divider).frame(height: 1).padding(.top, 12)
                VStack(alignment: .leading, spacing: 12) {
                    // Eyebrow row: the count lives IN the eyebrow (spec 4.4.5); the whole row is the
                    // collapse control (ADDENDUM C area 3), and its chevron reflects the state.
                    Button {
                        withAnimation(.emberEase(Dur.d240)) { chatsOpen.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(live.activeStreams.count == 1 ? "1 CHAT BURNING NOW" : "\(live.activeStreams.count) CHATS BURNING NOW")
                                .font(.system(size: 11, weight: .semibold)).tracking(1.1).foregroundStyle(p.sub).fixedSize()
                            Spacer(minLength: 6)
                            Image(systemName: chatsOpen ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .semibold)).foregroundStyle(p.faint)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chatsOpen ? "Hide burning chats" : "Show burning chats")
                    if chatsOpen {
                    ForEach(Array(live.activeStreams.prefix(3).enumerated()), id: \.offset) { i, s in
                        HStack(spacing: 8) {
                            Circle().fill(p.session.opacity(i == 0 ? 1.0 : 0.55)).frame(width: 5, height: 5)
                            if renaming == s.name {
                                TextField("", text: $renameText, onCommit: { chatNames.setAlias(renameText, for: s.name); renaming = nil })
                                    .textFieldStyle(.plain).font(.system(size: 12.5)).foregroundStyle(p.ink)
                            } else {
                                Text(chatNames.display(s.name)).font(.system(size: 12.5)).foregroundStyle(p.ink)
                                    .lineLimit(1).truncationMode(truncation == .end ? .tail : .middle)
                                    .contextMenu {
                                        Button("Rename") { renameText = chatNames.display(s.name); renaming = s.name }
                                        if chatNames.aliases[s.name] != nil { Button("Reset to original") { chatNames.reset(s.name) } }
                                    }
                            }
                            Spacer(minLength: 8)
                            Text("\(fmtTok(s.tok))/min").font(.system(size: 12, design: .monospaced)).foregroundStyle(p.sub)
                                .monospacedDigit()
                        }
                        .help(chatNames.display(s.name))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(chatNames.display(s.name))
                        .accessibilityValue("\(fmtTok(s.tok)) tokens per minute")
                    }
                    // Spec 4.3: max 3 rows, then the overflow is named in `faint`.
                    if live.activeStreams.count > 3 {
                        Text("+ \(live.activeStreams.count - 3) more")
                            .font(.system(size: 11.5)).foregroundStyle(p.faint)
                    }
                    }
                }
                .padding(.top, 12)
                .help("Claude chats burning tokens right now. Busiest first; the number is tokens over the last minute.")
            }
        }
    }
}

// Bottom-right live indicator: a calm pulsing dot + the refresh cadence label ("live" / "30s").
// (Replaced the draining countdown ring, which re-rendered every second and read as a fidgety little
// clock; a slow opacity breath on a single dot says "live and updating" without the busywork.)
struct LiveCadence: View {
    var on: Bool
    var accent: Color
    var faint: Color
    var track: Color = .gray
    var anchor: Date
    var period: Double
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        HStack(spacing: 5) {
            if on {
                Circle().fill(accent).frame(width: 6, height: 6)
                    .opacity(reduce ? 1 : (pulse ? 1.0 : 0.4))
                    .animation(reduce ? nil : .easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
                    .help("Live - updates every \(fmtCadence(period))")
            } else {
                Image(systemName: "pause.fill").font(.system(size: 8)).foregroundStyle(faint).frame(width: 8, height: 8)
                    .help("Paused")
            }
            Text(on ? fmtCadence(period) : "paused").font(.system(size: 11)).foregroundStyle(faint).monospacedDigit()
        }
    }
}

// ema moved to Sources/ChartData.swift (Foundation-pure, headless-testable).

// One contiguous-run point for a Swift Charts series. A new `seg` starts after a
// sleep-sized time gap so the line + area break there instead of bridging the gap.
struct ChartPoint: Identifiable { let id: Int; let t: Date; let v: Double; let seg: Int }

// segmentize moved to Sources/ChartData.swift.

// bucketed moved to Sources/ChartData.swift.

// relTimeLabel + fmtCadence moved to Sources/Format.swift.

// percentile moved to Sources/Format.swift.

// nearestSample moved to Sources/ChartData.swift.

// burnCeiling moved to Sources/Format.swift.

// The hover crosshair callout (value + when).
// Glassy hover callout: frosted material card with a hairline, deeper drop shadow, and a warm
// accent tick on the leading edge - reads as a premium inspector, not a plain tag.
// `detail` (optional) gets its OWN line with room to breathe - long project names shown whole,
// middle-truncated only past ~30 characters, never chopped to a useless fragment.
func chartCallout(_ big: String, _ small: String, _ p: Palette, detail: String? = nil) -> some View {
    HStack(spacing: 6) {
        RoundedRectangle(cornerRadius: 1).fill(Color(hex: kAccentHex)).frame(width: 2.5)
        VStack(alignment: .leading, spacing: 0) {
            Text(big).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(p.ink)
            Text(small).font(.system(size: 8.5)).foregroundStyle(p.faint)
            if let detail {
                Text(detail).font(.system(size: 8.5, weight: .medium)).foregroundStyle(p.sub)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 190, alignment: .leading)
            }
        }
    }
    .padding(.horizontal, 6).padding(.vertical, 4)
    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.regularMaterial))
    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(p.bg.opacity(0.55)))
    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(p.divider, lineWidth: 0.5))
    .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
    .fixedSize(horizontal: false, vertical: true)
}

// A calm empty/warming-up state for the chart, so a brand-new install (no samples yet) shows a clear
// placeholder instead of bare axes or being handed an empty Swift Charts series.
@ViewBuilder func chartPlaceholder(_ text: String, _ p: Palette) -> some View {
    HStack { Spacer()
        VStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2).fill(p.track).frame(width: 54, height: 2)
            Text(text).font(.system(size: 11)).foregroundStyle(p.faint)
        }
        Spacer() }.frame(height: 74)
}






struct OverPill: View {
    var color: Color
    var label: String = "Limit reached"
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
            Text(label).font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
        // Ember breathing: a slow warm pulse around the pill while over the limit - urgency you
        // feel peripherally, without a flashing alarm.
        .background {
            if !reduce {
                TimelineView(.periodic(from: .now, by: 0.25)) { ctx in   // 4fps: slow warm pulse
                    let ph = (sin(ctx.date.timeIntervalSinceReferenceDate * 1.6) + 1) / 2
                    Capsule().fill(color.opacity(0.001))
                        .shadow(color: color.opacity(0.25 + 0.3 * ph), radius: 4 + 3 * ph)
                }
            }
        }
    }
}

// The Burndown mark: four descending steps on a baseline (remaining allowance burning down left to
// right). Pure SwiftUI shapes so it renders in ImageRenderer too. Fill is the active session role.
struct BurndownMark: View {
    var size: CGFloat
    var fill: Color
    var track: Color
    private func bar(_ x: CGFloat, _ y: CGFloat, _ h: CGFloat, _ op: Double, _ u: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1 * u).fill(fill.opacity(op))
            .frame(width: 3.6 * u, height: h * u).offset(x: x * u, y: y * u)
    }
    var body: some View {
        let u = size / 24
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 0.7 * u).fill(track).frame(width: 20 * u, height: 1.4 * u).offset(x: 2 * u, y: 20.3 * u)
            bar(3, 6, 15, 1.0, u)
            bar(8.2, 10, 11, 0.82, u)
            bar(13.4, 13.5, 7.5, 0.64, u)
            bar(18.6, 16.5, 4.5, 0.46, u)
        }.frame(width: size, height: size, alignment: .topLeading)
    }
}

// A static placeholder block for the warming-up skeleton (no shimmer, so it is reduce-motion safe).
struct Skeleton: View {
    var w: CGFloat?
    var h: CGFloat
    var p: Palette
    var circle: Bool = false
    var radius: CGFloat = 6
    var body: some View {
        Group {
            if circle { Circle().fill(p.track) }
            else { RoundedRectangle(cornerRadius: radius).fill(p.track) }
        }
        .frame(width: w, height: h)
        .frame(maxWidth: w == nil ? .infinity : nil, alignment: .leading)
    }
}

// MARK: - Edge dock widget (follows the Claude Desktop window)

// Transparent margin around the card so its drop shadow never clips at the panel edge.
let kEdgePad: CGFloat = 14

// A bottom-anchored vertical fill bar (side card).
struct VBar: View {
    var frac: Double; var color: Color; var track: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottom) {
                Capsule().fill(track)
                Capsule().fill(color).frame(height: max(3, g.size.height * min(1, max(0, frac))))
            }
        }.frame(width: 7)
    }
}

// A leading-anchored horizontal fill bar (top/bottom bar).
struct HFill: View {
    var frac: Double; var color: Color; var track: Color; var width: CGFloat
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(track)
            Capsule().fill(color).frame(width: max(4, width * min(1, max(0, frac))))
        }.frame(width: width, height: 5)
    }
}

// Session / weekly colors for the dock, on the shared role palette so the widget recolors with the
// theme exactly like the popover (weekly was previously a fixed slate that ignored the palette).
private func dockColors(_ s: UsageSnapshot, _ settings: AppSettings, _ p: Palette) -> (s: Color, w: Color) {
    let custom = settings.accentHex.uppercased() != kDefaultAccent.uppercased()
    let accent = NSColor(hex: settings.accentHex) ?? NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
    let sBase = custom ? Color(nsColor: usageNSColor(pct: s.sessionPct, over: false, accent: accent, mode: settings.colorMode)) : p.session
    return (s.over ? p.overLimit : sBase, s.weeklyOver ? p.overLimit : p.weekly)
}

// Vertical side card (Left / Right): % over twin vertical bars (Session + Weekly).
struct EdgeWidget: View {
    @ObservedObject var engine: UsageEngine
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let s = engine.snapshot, p = Palette.of(scheme), c = dockColors(s, settings, p)
        VStack(spacing: 6) {
            Text("\(Int((s.sessionPct * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .serif)).foregroundStyle(c.s).lineLimit(1).fixedSize()
            HStack(alignment: .bottom, spacing: 6) {
                VBar(frac: s.sessionPct, color: c.s, track: p.track)
                VBar(frac: s.weeklyPct, color: c.w, track: p.track)
            }.frame(height: 78)
            HStack(spacing: 6) {
                Text("S").font(.system(size: 7, weight: .bold)).foregroundStyle(p.faint).frame(width: 7)
                Text("W").font(.system(size: 7, weight: .bold)).foregroundStyle(p.faint).frame(width: 7)
            }
        }
        .padding(.vertical, 9).padding(.horizontal, 9).frame(width: 42)
        .background(RoundedRectangle(cornerRadius: 12).fill(p.bg))
        // Heat wash: nearing the session cap warms the card - a rust tint + glowing border,
        // so the docked widget itself signals "close to the limit" from across the room.
        .background {
            let heat = s.over ? 1.0 : max(0, (min(1, s.sessionPct) - 0.85) / 0.15)
            RoundedRectangle(cornerRadius: 12).fill(p.overLimit.opacity(0.10 * heat))
        }
        .overlay {
            let heat = s.over ? 1.0 : max(0, (min(1, s.sessionPct) - 0.85) / 0.15)
            RoundedRectangle(cornerRadius: 12).stroke(heat > 0 ? p.overLimit.opacity(0.25 + 0.4 * heat) : p.divider,
                                                      lineWidth: heat > 0 ? 1 : 0.6)
        }
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .padding(kEdgePad)
    }
}

// Slim horizontal bar (Top / Bottom): Session + Weekly progress; blends at the window edge.
struct EdgeBar: View {
    @ObservedObject var engine: UsageEngine
    @ObservedObject var settings: AppSettings
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let s = engine.snapshot, p = Palette.of(scheme), c = dockColors(s, settings, p)
        HStack(spacing: 10) {
            metric("S", s.sessionPct, c.s, p)
            Rectangle().fill(p.divider).frame(width: 0.6, height: 14)
            metric("W", s.weeklyPct, c.w, p)
        }
        .padding(.vertical, 6).padding(.horizontal, 12)
        .background(Capsule().fill(p.bg))
        .overlay(Capsule().stroke(p.divider, lineWidth: 0.6))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .padding(kEdgePad)
    }
    private func metric(_ label: String, _ frac: Double, _ color: Color, _ p: Palette) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 8, weight: .bold)).foregroundStyle(p.faint)
            HFill(frac: frac, color: color, track: p.track, width: 60)
            Text("\(Int((frac * 100).rounded()))%").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color).frame(width: 30, alignment: .leading).lineLimit(1)
        }
    }
}

// Adaptive container - bar for Top/Bottom, card for Left/Right.
// Shared UI state for the edge-dock widget (the lost/rescan state lives in AppKit, the view reads it).
final class EdgeState: ObservableObject {
    @Published var lost = false
    var onRescan: () -> Void = {}
}

struct EdgeDockView: View {
    @ObservedObject var engine: UsageEngine
    @ObservedObject var settings: AppSettings
    @ObservedObject var edgeState: EdgeState
    @Environment(\.colorScheme) private var scheme
    @State private var natSize = CGSize(width: 100, height: 60)
    var body: some View {
        if edgeState.lost { lostPlaque } else { widget }
    }

    // Spec 6.2 lost state: a 160x44 plaque when Claude is running but its window can't be found.
    private var lostPlaque: some View {
        let p = Palette.of(scheme)
        return Button(action: edgeState.onRescan) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(p.sub)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude window not found").font(.system(size: 11, weight: .medium)).foregroundStyle(p.ink)
                    Text("Click to re-scan").font(.system(size: 10)).foregroundStyle(p.sub)
                }
            }
            .padding(.horizontal, 12).frame(width: 160, height: 44)
            .background(RoundedRectangle(cornerRadius: 11).fill(p.bg))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(p.divider, lineWidth: 0.6))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }.buttonStyle(.plain)
    }

    private var widget: some View {
        let s = engine.snapshot, p = Palette.of(scheme), c = dockColors(s, settings, p)
        let horizontal = settings.dockEdge.horizontal
        let d = WData(s: s.sessionPct, w: s.weeklyPct, sc: c.s, wc: c.w, p: p)
        let r: CGFloat = horizontal ? 11 : 12
        let scale = max(0.7, min(1.8, settings.widgetScale))
        return widgetContent(settings.widgetStyle, d, horizontal: horizontal, scale: scale)
            .padding(.vertical, horizontal ? 3 : 9).padding(.horizontal, horizontal ? 11 : 6)
            .background(RoundedRectangle(cornerRadius: r).fill(p.bg))
            .overlay(RoundedRectangle(cornerRadius: r).stroke(p.divider, lineWidth: 0.6))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            // Adjustable size: measure the natural card, scale it, then reserve the scaled size so the panel hugs it.
            .background(GeometryReader { g in Color.clear.preference(key: WidgetSizeKey.self, value: g.size) })
            .scaleEffect(scale, anchor: .center)
            .frame(width: natSize.width * scale, height: natSize.height * scale)
            .onPreferenceChange(WidgetSizeKey.self) { natSize = $0 }
            .padding(kEdgePad)
            // Spec 6.2: right-click position presets along the docked edge, plus a lock.
            .contextMenu {
                let vertical = !settings.dockEdge.horizontal
                Button(vertical ? "Top" : "Start") { settings.edgePx = 0; settings.edgeFromEnd = false }
                Button("Center") { settings.edgePx = -1 }
                Button(vertical ? "Bottom" : "End") { settings.edgePx = 0; settings.edgeFromEnd = true }
                Divider()
                Toggle("Dock inside the window", isOn: $settings.dockInside)
                Toggle("Lock position", isOn: $settings.dockLocked)
            }
    }
}

private struct WidgetSizeKey: PreferenceKey {
    static var defaultValue = CGSize(width: 100, height: 60)
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { let n = nextValue(); if n != .zero { value = n } }
}

// MARK: - Settings (in-popover, themed)

// MARK: - About

// The Living Ember brand mark: Burndown's flame, drawn in code so it scales anywhere.
// A teardrop flame with a white-hot core over a warm coal glow - matches the menu-bar Flame glyph.
struct FlameMark: View {
    var size: CGFloat
    var body: some View {
        let u = size / 100
        // C1 (the ratified flame canon, Option C): the MARK uses the app-icon hues VERBATIM. The
        // spec 2.2 fire palette is reserved for typographic heat and never recolors the mark.
        // Anatomy: teardrop + warm radial gradient from the heart, a nested cream core at 94% in
        // the lower belly, THREE embers above the crown, over a soft warm halo. Never smoke.
        // Degradation: below 20pt the mark drops its sparks; below 14pt it also drops the core.
        let showSparks = size >= 20
        let showCore = size >= 14
        ZStack {
            // soft warm halo
            Ellipse().fill(Color(hex: "E2510B").opacity(0.25))
                .frame(width: 62 * u, height: 26 * u).offset(y: 34 * u).blur(radius: 4 * u)
            // outer teardrop, radial gradient from the heart point (stops per C1)
            FlameShape()
                .fill(RadialGradient(stops: [.init(color: Color(hex: "FFF6D6"), location: 0.0),
                                             .init(color: Color(hex: "F9A825"), location: 0.34),
                                             .init(color: Color(hex: "E2510B"), location: 0.72),
                                             .init(color: Color(hex: "A0341A"), location: 1.0)],
                                     center: .init(x: 0.5, y: 0.72), startRadius: 1 * u, endRadius: 62 * u))
                .frame(width: 62 * u, height: 78 * u)
            // nested cream core in the lower belly, 94 percent
            if showCore {
                FlameShape().fill(Color(hex: "FFF6D6").opacity(0.94))
                    .frame(width: 26 * u, height: 34 * u).offset(y: 14 * u)
            }
            // three embers above the crown: FFE9A8 / F9A825 / FFE9A8
            if showSparks {
                Circle().fill(Color(hex: "FFE9A8").opacity(0.90)).frame(width: 4 * u).offset(x: 2 * u, y: -44 * u)
                Circle().fill(Color(hex: "F9A825").opacity(0.70)).frame(width: 3 * u).offset(x: 14 * u, y: -34 * u)
                Circle().fill(Color(hex: "FFE9A8").opacity(0.55)).frame(width: 2.4 * u).offset(x: -9 * u, y: -37 * u)
            }
        }
        .frame(width: size, height: size)
    }
}

// Teardrop flame silhouette in a unit rect: pointed crown, round belly.
struct FlameShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.62),
                   control1: CGPoint(x: r.midX - w * 0.10, y: r.minY + h * 0.26),
                   control2: CGPoint(x: r.minX, y: r.minY + h * 0.38))
        p.addArc(center: CGPoint(x: r.midX, y: r.minY + h * 0.62), radius: w / 2,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY),
                   control1: CGPoint(x: r.maxX, y: r.minY + h * 0.38),
                   control2: CGPoint(x: r.midX + w * 0.10, y: r.minY + h * 0.26))
        p.closeSubpath()
        return p
    }
}

// The FlameMark, alive (spec area 1 / addendum B.1): the same silhouette on a LOCKED outline, breathing
// in scale about its centroid with a breathing warm halo behind it, so it always reads as the logo. Used
// in exactly two places: About and the signed-out "Connect your plan" card. Reduce motion: the static mark.
struct LivingFlameMark: View {
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        if reduce {
            FlameMark(size: size)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 6.0)) { ctx in   // 6fps: a slow breath needs no more
                let t = ctx.date.timeIntervalSinceReferenceDate
                let breath = 0.5 - 0.5 * cos(t * 2 * .pi / 4)   // 4s breath (spec 3.5 halo cadence)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: Fire.glow).opacity(0.24 + 0.12 * breath), .clear],
                                             center: .center, startRadius: 0, endRadius: size * 0.7))
                        .frame(width: size * 1.7, height: size * 1.7)
                    FlameMark(size: size).scaleEffect(1.0 + 0.026 * breath, anchor: .center)
                }
            }
        }
    }
}

struct AboutView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var copied = false
    @State private var hoverLink: String? = nil
    @State private var kindled = false
    private func aboutLink(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).foregroundStyle(Palette.of(scheme).session).underline(hoverLink == label)
        }.buttonStyle(.plain).onHover { hoverLink = $0 ? label : nil }
    }
    var body: some View {
        let p = Palette.of(scheme)
        VStack(spacing: 0) {
            // The living FlameMark (spec area 1): breathing on a locked outline with its own warm halo.
            LivingFlameMark(size: 42).padding(.top, 28)
            Text(kAppName).font(.system(size: 26, weight: .semibold, design: .serif)).tracking(-0.2)
                .foregroundStyle(p.ink).padding(.top, 14)
            // Version pill: click copies the full build string.
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(kAppName) \(kAppVersion)", forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Text(copied ? "Copied" : "Version \(kAppVersion)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced)).foregroundStyle(p.sub)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().stroke(p.divider, lineWidth: 1))
            }.buttonStyle(.plain).padding(.top, 8).help("Click to copy the version")
            Text("See the limit coming.")
                .font(.system(size: 12.5)).foregroundStyle(p.sub).padding(.top, 10)
            Rectangle().fill(p.divider).frame(width: 156, height: 1).padding(.vertical, 16)
            // The lock is part of the sentence, not a sibling of it. As an HStack item it was
            // centred against a two-line paragraph, so it floated in the gap between the lines
            // and read as a stray icon; concatenated Text lets it sit on the first line and
            // wrap with the words.
            (Text(Image(systemName: "lock.fill")).font(.system(size: 8.5))
             + Text("  ") + Text(kTrustSentence).font(.system(size: 11)))
                .foregroundStyle(p.sub).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .help("Stored at ~/.config/burndown, permissions 600, never synced.")
            // Clickable, but still the anchor of the credit block: keeping it ink rather than
            // accent stops it competing with the three real links below it.
            Button {
                NSWorkspace.shared.open(URL(string: "https://github.com/maz0x")!)
            } label: {
                Text("Made by maz0x").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(p.ink).underline(hoverLink == "maz0x")
            }
            .buttonStyle(.plain).padding(.top, 12)
            .onHover { hoverLink = $0 ? "maz0x" : nil }
            .help("Open github.com/maz0x")
            // Hovering the home line makes the mark catch: the static mark becomes the living
            // one and the text warms up. Motion is opt-in by pointer and honours reduce motion.
            HStack(spacing: 4) {
                Text("Kindled in California").font(.system(size: 11))
                    .foregroundStyle(kindled ? p.session : p.faint)
                Group {
                    if kindled && !reduce { LivingFlameMark(size: 12) } else { FlameMark(size: 10) }
                }
                .frame(width: 13, height: 13)   // fixed box: swapping marks must not nudge the row
                .scaleEffect(kindled ? 1.12 : 1)
            }
            .padding(.top, 1)
            .onHover { kindled = $0 }
            .animation(.easeOut(duration: 0.28), value: kindled)
            // Links row (spec 5.5): middle-dot separated, accent, hover underline. Every link works:
            // What's new + Privacy open docs bundled with the app; the tour reopens onboarding.
            HStack(spacing: 6) {
                aboutLink("What's new") { openBundledDoc("RELEASE_NOTES") }
                Text("·").foregroundStyle(p.faint)
                aboutLink("Privacy") { openBundledDoc("PRIVACY") }
                Text("·").foregroundStyle(p.faint)
                aboutLink("Welcome tour") { NotificationCenter.default.post(name: .showWelcomeTour, object: nil) }
            }.font(.system(size: 11)).padding(.top, 10)
            // Brand adjacency, not impersonation: the third-party line lives on the app's own face.
            Text("An independent project, not affiliated with Anthropic.")
                .font(.system(size: 9.5)).foregroundStyle(p.faint).padding(.top, 8)
            Spacer(minLength: 0)
        }
        .frame(width: 300, height: 360).background(p.bg)
    }

    /// Open a markdown doc shipped inside the app bundle (Resources/<name>.md).
    private func openBundledDoc(_ name: String) {
        if let u = Bundle.main.url(forResource: name, withExtension: "md") {
            NSWorkspace.shared.open(u)
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Account (its own window - opened from the menu; not in Settings)

/// Hold-to-copy (spec 5.4): press 0.35s, the value fills accent 12 percent (radius 4), a "Copied"
/// chip fades in 120ms, holds 960ms, fades 240ms. Reduce motion: no fades. VoiceOver custom action.
struct HoldToCopy<Label: View>: View {
    var value: String
    var accent: Color
    var p: Palette
    var voiceLabel: String
    @ViewBuilder var label: () -> Label
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var pressing = false
    @State private var copied = false
    private func copy() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
        withAnimation(reduce ? nil : .emberEase(Dur.d120)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + Dur.d120 + Dur.d960) {
            withAnimation(reduce ? nil : .emberEase(Dur.d240)) { copied = false }
        }
    }
    var body: some View {
        label()
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(accent.opacity(pressing || copied ? 0.12 : 0)))
            .overlay(alignment: .trailing) {
                if copied {
                    Text("Copied").font(.system(size: 10.5, weight: .medium)).foregroundStyle(p.bg)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(p.ink.opacity(0.85)))
                        .offset(x: 44).transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.35, pressing: { pressing = $0 }, perform: copy)
            .accessibilityElement()
            .accessibilityLabel(voiceLabel)
            .accessibilityValue(value)
            .accessibilityAction(named: "Copy") { copy() }
    }
}

struct AccountView: View {
    @ObservedObject var engine: UsageEngine
    @ObservedObject var settings: AppSettings
    var onStartSignIn: () -> Void
    var onFinishSignIn: (String, @escaping (Bool) -> Void) -> Void
    var onOpenLogs: () -> Void
    var previewSignedIn: Bool? = nil   // QA-only override for the headless snapshot harness
    private var signedInNow: Bool { previewSignedIn ?? engine.isSignedIn() }
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var signInStep = false
    @State private var codeText = ""
    @State private var authBusy = false
    @State private var authResult: Bool? = nil
    @State private var recheckBusy = false
    // Developer API account (Admin key) state
    @State private var apiKeyField = ""
    @State private var apiBusy = false
    @State private var apiError: String? = nil
    @State private var apiEditing = false

    private func money2(_ v: Double) -> String { v >= 1000 ? String(format: "$%.0f", v) : String(format: "$%.2f", v) }
    private func agoShort(_ d: Date) -> String {
        let s = max(0, Date().timeIntervalSince(d))
        return s < 60 ? "just now" : s < 3600 ? "\(Int(s / 60))m ago" : "\(Int(s / 3600))h ago"
    }
    // The ONE eyebrow token (spec 2.3): 11pt semibold, +1.4 tracking, `sub`.
    private func eyebrow(_ t: String, _ p: Palette) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(p.sub)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    // A shared card token (radius 12, 14pt padding, raisedBg, no border/shadow).
    @ViewBuilder private func card<C: View>(_ p: Palette, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { c() }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.raisedBg))
    }
    // A 26pt stat row: label SF 13pt sub, value SF 13pt medium ink MONO.
    private func statRow(_ k: String, _ v: String, _ p: Palette) -> some View {
        HStack { Text(k).font(.system(size: 13)).foregroundStyle(p.sub); Spacer(minLength: 8)
                 Text(v).font(.system(size: 13, weight: .medium, design: .monospaced)).monospacedDigit()
                     .foregroundStyle(p.ink).lineLimit(1) }
            .frame(height: 26)
    }
    // Opus / Sonnet split row with a 40x4pt micro-bar in `session` at 70 percent.
    private func splitRow(_ k: String, _ pct: Double, _ p: Palette) -> some View {
        HStack(spacing: 8) {
            Text(k).font(.system(size: 12)).foregroundStyle(p.sub).frame(width: 52, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(p.track).frame(width: 40, height: 4)
                Capsule().fill(p.session.opacity(0.7)).frame(width: max(4, 40 * min(1, max(0, pct))), height: 4)
            }
            Spacer(minLength: 6)
            Text("\(Int((pct * 100).rounded()))%").font(.system(size: 12, weight: .medium, design: .monospaced))
                .monospacedDigit().foregroundStyle(p.ink)
        }.frame(height: 22)
    }

    // One per-model weekly cap (limits[]): name, usage bar, and how much is LEFT. The binding limit
    // (`active`) gets an ember dot + the session hue.

    // DEVELOPER API card (C2 / area 4): a distinct login, in the shared card token.
    @ViewBuilder private func apiCard(_ p: Palette, _ coral: Color) -> some View {
        let spend = engine.apiSpend
        card(p) {
            HStack(spacing: 6) {
                eyebrow("DEVELOPER API", p)
                Text("SEPARATE ACCOUNT").font(.system(size: 8.5, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(p.faint).padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().strokeBorder(p.divider, lineWidth: 1))
            }
            if spend.configured && !apiEditing {
                if spend.error == nil {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "key.fill").font(.system(size: 15)).foregroundStyle(coral).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(money2(spend.monthToDate))
                                .font(.system(size: 22, weight: .semibold, design: .serif)).monospacedDigit().foregroundStyle(p.ink)
                            Text("THIS MONTH").font(.system(size: 8.5, weight: .semibold)).tracking(0.8).foregroundStyle(p.faint)
                            Text("\(money2(spend.today)) / today  ·  \(money2(spend.dailyAvg)) / day avg")
                                .font(.system(size: 11.5)).foregroundStyle(p.sub).padding(.top, 3)
                        }
                        Spacer(minLength: 4)
                    }
                    if spend.daily.count >= 2 {
                        DailyCostSpark(values: Array(spend.daily.suffix(14)), color: p.session.opacity(0.55))
                            .frame(height: 22)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(p.live).frame(width: 5, height: 5)
                        if let f = spend.fetchedAt { Text("Updated " + agoShort(f)).font(.system(size: 10.5)).foregroundStyle(p.faint) }
                        Spacer(minLength: 8)
                        Button("Change") { apiEditing = true; apiKeyField = ""; apiError = nil }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(coral)
                        Button("Remove") { engine.clearAdminKey(); apiKeyField = ""; apiError = nil }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(p.sub)
                    }
                } else if let e = spend.error {
                    Text(e).font(.system(size: 11.5)).foregroundStyle(p.warning).fixedSize(horizontal: false, vertical: true)
                    HStack { Spacer()
                        Button("Change") { apiEditing = true; apiKeyField = ""; apiError = nil }
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(coral)
                        Button("Remove") { engine.clearAdminKey() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(p.sub)
                    }
                }
            } else {
                Text("A separate pay-as-you-go account. The key stays on this Mac and reads only your own spend. It needs an Admin key beginning sk-ant-admin, created by an org owner at console.anthropic.com under Settings, Admin keys.")
                    .font(.system(size: 11.5)).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    TextField("sk-ant-admin-...", text: $apiKeyField)
                        .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced)).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(p.track))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(coral.opacity(apiKeyField.isEmpty ? 0 : 0.6), lineWidth: 1))
                    Button {
                        guard !apiBusy, !apiKeyField.isEmpty else { return }
                        apiBusy = true; apiError = nil
                        engine.setAdminKey(apiKeyField) { ok, err in
                            apiBusy = false
                            if ok { apiKeyField = ""; withAnimation(.emberEase(Dur.d240)) { apiEditing = false } } else { apiError = err }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if apiBusy { ProgressView().controlSize(.mini).scaleEffect(0.7) }
                            Text(apiBusy ? "Checking\u{2026}" : "Verify").font(.system(size: 12, weight: .medium))
                        }.padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(apiKeyField.isEmpty ? p.sub.opacity(0.35) : coral)).foregroundStyle(.white)
                    }.buttonStyle(.plain).disabled(apiKeyField.isEmpty || apiBusy)
                }
                if let e = apiError {
                    Text(e).font(.system(size: 11.5)).foregroundStyle(p.warning).fixedSize(horizontal: false, vertical: true)
                }
                if spend.configured {
                    Button("Cancel") { withAnimation(.emberEase(Dur.d240)) { apiEditing = false }; apiKeyField = ""; apiError = nil }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(p.sub)
                }
            }
        }
    }

    var body: some View {
        let p = Palette.of(scheme)
        // The scroll wrapper only exists in the live window; ImageRenderer (QA) cannot size a
        // ScrollView, so preview mode renders the content directly at a fixed height.
        Group {
            if previewSignedIn == nil {
                ScrollView { content(p) }
            } else {
                content(p).frame(height: 450, alignment: .top)
            }
        }
        .frame(width: 340, height: 450)
        .background(p.bg)
        .onAppear { engine.refreshAPISpend() }
    }

    @ViewBuilder private func content(_ p: Palette) -> some View {
        let coral = Color(hex: settings.accentHex)
        VStack(alignment: .leading, spacing: 16) {
                // Masthead (spec 5.1 shared chrome + 5.4).
                VStack(alignment: .leading, spacing: 3) {
                    Text("Account").font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(p.ink)
                    Text("Your Claude subscription connection.").font(.system(size: 11)).foregroundStyle(p.sub)
                }

                if signedInNow {
                    signedIn(p, coral)
                } else if !signInStep {
                    signedOut(p, coral)
                } else {
                    oauthFlow(p, coral)
                }

                apiCard(p, coral)   // the Developer API is a coequal source, always shown

                // Privacy footer (spec 5.4): lock + trust sentence, no chmod here; logs link below.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill").font(.system(size: 9))
                        Text(kTrustSentence).font(.system(size: 11))
                    }.foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
                    Button(action: onOpenLogs) { Text("Open diagnostic logs").font(.system(size: 12)) }
                        .buttonStyle(.plain).foregroundStyle(coral)
                }
        }
        .padding(20)
    }

    // MARK: signed-in
    @ViewBuilder private func signedIn(_ p: Palette, _ coral: Color) -> some View {
        let snap = engine.snapshot
        VStack(alignment: .leading, spacing: 16) {
            // Plan hero: NO seal badge; plan name serif with a quiet checkmark.circle in live.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(snap.plan.map { "Claude \($0)" } ?? "Claude subscription")
                            .font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(p.ink)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Image(systemName: "checkmark.circle").font(.system(size: 14)).foregroundStyle(p.live)
                    }
                    if let e = snap.accountEmail {
                        HoldToCopy(value: e, accent: coral, p: p, voiceLabel: "Copy email address") {
                            Text(e).font(.system(size: 12.5)).foregroundStyle(p.sub).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Button(recheckBusy ? "Checking\u{2026}" : "Re-check") {
                        recheckBusy = true; engine.reauthenticate { _ in recheckBusy = false }
                    }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(coral).disabled(recheckBusy)
                    .help("Re-read your plan and refresh usage now (picks up a plan upgrade).")
                    HoverUnderline("Sign out", size: 13, color: p.sub) {
                        engine.signOut(); signInStep = false; authResult = nil; codeText = ""
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                eyebrow("RESET TIMELINE", p)
                if let r = snap.sessionResetAt { statRow("Session", "resets in " + weekLeftString(r), p) }
                if let r = snap.weeklyResetAt { statRow("Weekly", "resets " + resetDayString(r), p) }
            }

            if let w = snap.apiWeekly {
                // Same coherent split as the popover: WEEKLY LIMITS first (the all-models pool + any
                // per-model caps, all "% left"), then a clearly separate BY MODEL attribution list
                // (each model's share of the week, one consistent metric). Never mixed in one column.
                VStack(alignment: .leading, spacing: 9) {
                    eyebrow("WEEKLY LIMITS", p)
                    HStack(spacing: 8) {
                        Text("All models").font(.system(size: 13)).foregroundStyle(p.sub)
                            .frame(width: 66, alignment: .leading)
                        HBar(pct: w.pct, color: kSlate, track: p.track, height: 5, a11yLabel: "Weekly usage, all models")
                        Text("\(Int(((1 - w.pct) * 100).rounded()))% left").font(.system(size: 13, weight: .medium, design: .monospaced))
                            .monospacedDigit().foregroundStyle(p.ink).fixedSize()
                    }
                    ForEach(snap.modelLimits) { m in CapLimitRow(m: m, p: p, barColor: kSlate, nameWidth: 66) }
                }

                if !snap.modelUsage.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 6) {
                            eyebrow("BY MODEL", p)
                            Text("share of week").font(.system(size: 10)).foregroundStyle(p.faint)
                        }
                        ByModelSplit(usage: snap.modelUsage, p: p)
                    }
                }
            }

            if let o = snap.accountOrg {
                VStack(alignment: .leading, spacing: 4) {
                    eyebrow("CONTACT", p)
                    HStack(alignment: .top) {
                        Text("Organization").font(.system(size: 13)).foregroundStyle(p.sub)
                        Spacer(minLength: 8)
                        Text(o).font(.system(size: 13, weight: .medium)).foregroundStyle(p.ink)
                            .multilineTextAlignment(.trailing).lineLimit(2)
                            .frame(width: 190, alignment: .trailing).help(o)
                    }
                }
            }
        }
    }

    // MARK: signed-out
    @ViewBuilder private func signedOut(_ p: Palette, _ coral: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Spacer()
                VStack(spacing: 10) {
                    FlameMark(size: 32).opacity(0.6)
                    Text("Not signed in").font(.system(size: 17, weight: .semibold, design: .serif)).foregroundStyle(p.ink)
                    Text("Connect your Claude account to see real limits.")
                        .font(.system(size: 12)).foregroundStyle(p.sub).multilineTextAlignment(.center)
                    Text(kTrustSentence).font(.system(size: 11)).foregroundStyle(p.faint)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Button {
                        authResult = nil; codeText = ""; onStartSignIn()
                        withAnimation(.emberEase(Dur.d240)) { signInStep = true }
                    } label: {
                        Text("Sign in with Claude").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).frame(height: 30).background(Capsule().fill(coral))
                    }.buttonStyle(.plain).help("Opens claude.ai in your browser to approve access.")
                }
                Spacer()
            }.padding(.vertical, 8)
        }
    }

    // MARK: OAuth flow
    @ViewBuilder private func oauthFlow(_ p: Palette, _ coral: Color) -> some View {
        // Tri-state stepper: active = the paste step until a result lands.
        let active = 2
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                ForEach(Array(["Approve in browser", "Copy the code", "Paste it here"].enumerated()), id: \.offset) { i, label in
                    OAuthStep(index: i, label: label, state: i < active ? .done : (i == active ? .active : .upcoming), p: p, accent: coral)
                    if i < 2 { Rectangle().fill(p.divider).frame(height: 1).frame(maxWidth: .infinity) }
                }
            }
            Text("Approve in the browser, copy the code it shows, then paste it here:")
                .font(.system(size: 11.5)).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                TextField("Paste your code", text: $codeText)
                    .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(p.track))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(coral.opacity(codeText.isEmpty ? 0 : 0.6), lineWidth: 1))
                Button {
                    guard !authBusy, !codeText.isEmpty else { return }
                    authBusy = true; authResult = nil
                    onFinishSignIn(codeText) { ok in
                        authBusy = false
                        withAnimation(.emberEase(Dur.d240)) { authResult = ok }
                        if ok { codeText = ""; DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { signInStep = false } } }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if authBusy { ProgressView().controlSize(.mini).scaleEffect(0.7) }
                        Text(authBusy ? "Connecting\u{2026}" : "Connect").font(.system(size: 12, weight: .medium))
                    }.padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(codeText.isEmpty ? p.sub.opacity(0.35) : coral)).foregroundStyle(.white)
                }.buttonStyle(.plain).disabled(codeText.isEmpty || authBusy)
            }
            HStack(spacing: 12) {
                HoverUnderline("Open sign-in again", size: 11, color: p.sub) { onStartSignIn() }
                HoverUnderline("Cancel", size: 11, color: p.sub) { withAnimation { signInStep = false }; codeText = ""; authResult = nil }
                Spacer()
            }
            if authResult == true {
                Text("Signed in. Your usage is updating.").font(.system(size: 11.5)).foregroundStyle(p.live)
            } else if authResult == false {
                Text("That code did not work. Open sign-in again, approve, and paste the fresh code.")
                    .font(.system(size: 11.5)).foregroundStyle(p.warning).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Spec 5.2.7: the Appearance live glass preview + AA contrast readout. Shows the current glass
/// settings over a checker + a warm/cool sample, with sample text, and reports the WCAG contrast of
/// `ink` against the synthetic worst-case backing (white in light, black in dark) at the chosen
/// opacity, warning below 4.5:1.
struct GlassPreview: View {
    @ObservedObject var settings: AppSettings
    var p: Palette
    var scheme: ColorScheme
    private var effOpacity: Double { max(0.55, settings.glassOpacity / 100) }   // clamped to the legibility floor
    private var contrast: Double {
        // Worst-case desktop showing through, blended with the palette backing at the glass opacity.
        let worst = NSColor(white: scheme == .dark ? 0 : 1, alpha: 1)
        let tint: NSColor = {
            switch settings.glassTint {
            case .none:   return NSColor(p.bg)
            case .theme:  return NSColor(p.bg)
            case .accent: return NSColor(hex: settings.accentHex) ?? NSColor(p.bg)
            }
        }()
        let backing = NSColor(p.bg).blended(to: tint, CGFloat(settings.glassTintIntensity / 100 * 0.5))
        let effective = worst.blended(to: backing, CGFloat(effOpacity))
        return NSColor.wcagContrast(NSColor(p.ink), effective)
    }
    var body: some View {
        let ok = contrast >= 4.5
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                // checker + a warm/cool wash, so the glass has something to sit over
                Checker().opacity(0.5)
                LinearGradient(colors: [Color(hex: "6B8CC7"), Color(hex: "C77E5B")], startPoint: .leading, endPoint: .trailing).opacity(0.5)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(p.bg.opacity(effOpacity))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(p.divider, lineWidth: 1))
                    .padding(8)
                    .overlay(
                        HStack {
                            Text("46%").font(.system(size: 20, weight: .semibold, design: .serif)).foregroundStyle(p.ink)
                            Spacer()
                            Text("Sample").font(.system(size: 11)).foregroundStyle(p.sub)
                        }.padding(.horizontal, 20)
                    )
            }
            .frame(height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 5) {
                if !ok { Image(systemName: "exclamationmark.triangle").font(.system(size: 9)).foregroundStyle(p.warning) }
                Text(String(format: "AA %.1f:1", contrast))
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(ok ? p.sub : p.warning)
                Text(ok ? "text stays legible" : "clamped to the 55% floor for legibility")
                    .font(.system(size: 10.5)).foregroundStyle(p.faint)
                Spacer()
            }
        }
    }
}

/// A small light/dark checkerboard used behind the glass preview.
struct Checker: View {
    var body: some View {
        GeometryReader { g in
            let s: CGFloat = 10
            let cols = Int(g.size.width / s) + 1, rows = Int(g.size.height / s) + 1
            Canvas { ctx, _ in
                for r in 0..<rows { for c in 0..<cols where (r + c) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: CGFloat(c) * s, y: CGFloat(r) * s, width: s, height: s)), with: .color(.gray.opacity(0.5)))
                } }
            }
        }
    }
}

/// A small daily-cost bar sparkline (C2: 14-day API spend history, session clay).
struct DailyCostSpark: View {
    var values: [Double]; var color: Color
    var body: some View {
        GeometryReader { g in
            let mx = max(values.max() ?? 1, 0.0001)
            let n = max(values.count, 1)
            let gap: CGFloat = 2
            let bw = max(1.5, (g.size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    Capsule().fill(color)
                        .frame(width: bw, height: max(1.5, g.size.height * CGFloat(v / mx)))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .accessibilityElement()
        .accessibilityLabel("14 day spend history")
    }
}

/// A quiet text button that underlines on hover (spec 5.4 "Sign out" etc.).
struct HoverUnderline: View {
    let title: String; var size: CGFloat; var color: Color; var action: () -> Void
    @State private var hover = false
    init(_ title: String, size: CGFloat, color: Color, action: @escaping () -> Void) {
        self.title = title; self.size = size; self.color = color; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: size)).foregroundStyle(color).underline(hover)
        }.buttonStyle(.plain).onHover { hover = $0 }
    }
}

/// One OAuth step dot (spec 5.4): 18pt circle, tri-state, with its label beneath.
struct OAuthStep: View {
    enum State { case upcoming, active, done }
    var index: Int; var label: String; var state: State; var p: Palette; var accent: Color
    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                switch state {
                case .upcoming:
                    Circle().fill(p.track).frame(width: 18, height: 18)
                    Text("\(index + 1)").font(.system(size: 10)).foregroundStyle(p.faint)
                case .active:
                    Circle().fill(accent).frame(width: 18, height: 18)
                    Circle().strokeBorder(accent.opacity(0.3), lineWidth: 1).frame(width: 24, height: 24)
                    Text("\(index + 1)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                case .done:
                    Circle().fill(p.live).frame(width: 18, height: 18)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                }
            }.frame(width: 24, height: 24)
            Text(label).font(.system(size: 10.5)).foregroundStyle(state == .upcoming ? p.faint : p.sub)
                .fixedSize().multilineTextAlignment(.center)
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1): \(label)")
        .accessibilityValue(state == .done ? "done" : state == .active ? "current" : "upcoming")
    }
}

// The Settings window is a native sidebar layout: pick a category on the left, see its
// controls on the right. Keeps the surface calm while keeping the high-value controls
// (menu-bar style, transparency, chart ranges) one click away, never buried.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, alerts, menuBar, appearance, popover, data
    var id: String { rawValue }
    var label: String {
        switch self {
        case .general:    return "General"
        case .alerts:     return "Alerts"
        case .menuBar:    return "Menu Bar"
        case .appearance: return "Appearance"
        case .popover:    return "Popover"
        case .data:       return "Charts"
        }
    }
    var icon: String {
        switch self {
        case .general:    return "gearshape"
        case .alerts:     return "bell.badge"
        case .menuBar:    return "menubar.rectangle"
        case .appearance: return "paintpalette"
        case .popover:    return "rectangle.portrait.on.rectangle.portrait"
        case .data:       return "chart.xyaxis.line"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var engine: UsageEngine
    @ObservedObject var live: LiveActivity
    var loginInitially: Bool
    var onLogin: (Bool) -> Void
    var onResetData: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @State private var login = false
    @State private var tab: SettingsTab? = SettingsTab(rawValue: ProcessInfo.processInfo.environment["CUB_TAB"] ?? "") ?? .general
    @State private var confirmReset = false
    @State private var exportNote: String?
    @State private var testNote: String?
    @ObservedObject private var updater = Updater.shared
    @State private var lastDock: DockEdge = .bottom   // remembers the edge so the on/off toggle can restore it
    @State private var galleryLive = false            // chart gallery previews: sample data or my data

    var body: some View {
        let p = Palette.of(scheme)
        // Custom sidebar (plain Buttons drive a @State selection) instead of NavigationSplitView's
        // List(selection:), which silently failed to switch panes on click.
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(SettingsTab.allCases) { t in sidebarRow(t, p) }
                Spacer()
            }
            .padding(.top, 16).padding(.horizontal, 10)
            .frame(width: 188)
            .frame(maxHeight: .infinity)
            .background(p.track.opacity(0.4))

            Divider()

            Group {
                if ProcessInfo.processInfo.environment["CUB_NOSCROLL"] != nil {
                    // QA only: render the whole pane without a ScrollView so ImageRenderer captures it.
                    VStack(alignment: .leading, spacing: 16) { pane(tab ?? .general, p) }
                        .padding(22).frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            pane(tab ?? .general, p)
                        }
                        .padding(22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(p.bg)
        }
        .frame(width: 660,
               // QA renders (no ScrollView) need the full pane height; the Charts gallery is the tall one.
               height: ProcessInfo.processInfo.environment["CUB_NOSCROLL"] != nil ? ((tab ?? .general) == .data ? 3450 : 1180) : 580)
        .onAppear {
            login = loginInitially
            if let t = settings.pendingTab.flatMap({ SettingsTab(rawValue: $0) }) { tab = t; settings.pendingTab = nil }
        }
        .onChange(of: settings.pendingTab) { v in
            if let t = v.flatMap({ SettingsTab(rawValue: $0) }) { tab = t; settings.pendingTab = nil }
        }
        .onChange(of: settings.menuBarShow) { show in
            if !settings.menuBarStyle.supports(show) {
                settings.menuBarStyle = MenuBarStyle.allCases.first { $0.supports(show) } ?? .pulse
            }
        }
        .alert("Reset chart history and logs?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { onResetData() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently clears your stored usage history and the on-disk diagnostic log. Your Claude account, limits, and settings are not affected, and live tracking keeps running.")
        }
    }

    private var updateFailed: Bool { if case .failed = updater.state { return true }; return false }

    @ViewBuilder private func updateButton(_ p: Palette, _ coral: Color) -> some View {
        switch updater.state {
        case .checking, .verifying, .readyToRelaunch:
            ProgressView().controlSize(.small)
        case .downloading:
            Text("Downloading").font(.system(size: 12)).foregroundStyle(p.sub)
        case .available(let rel):
            Button { updater.downloadAndInstall() } label: {
                Text("Update to \(rel.version)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(coral))
            }.buttonStyle(.plain).fixedSize()
                .help("Downloads the release, checks it against its published checksum, installs it in place, and restarts Burndown.")
        default:
            Button { updater.check() } label: {
                Text("Check now").font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().stroke(coral, lineWidth: 1)).foregroundStyle(coral)
            }.buttonStyle(.plain).fixedSize()
                .help("Asks GitHub for the newest Burndown release and compares it to this build.")
        }
    }

    private func sidebarRow(_ t: SettingsTab, _ p: Palette) -> some View {
        let on = (tab ?? .general) == t
        let coral = Color(hex: settings.accentHex)
        return Button { tab = t } label: {
            HStack(spacing: 9) {
                Image(systemName: t.icon).font(.system(size: 13)).frame(width: 19)
                Text(t.label).font(.system(size: 13, weight: on ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(on ? coral : p.ink)
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? coral.opacity(0.15) : Color.clear))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).focusable(false)
    }

    // MARK: - Panes

    @ViewBuilder private func pane(_ tab: SettingsTab, _ p: Palette) -> some View {
        switch tab {
        case .general:    generalPane(p)
        case .alerts:     alertsPane(p)
        case .menuBar:    menuBarPane(p)
        case .appearance: appearancePane(p)
        case .popover:    popoverPane(p)
        case .data:       dataPane(p)
        }
    }

    @ViewBuilder private func generalPane(_ p: Palette) -> some View {
        let coral = Color(hex: settings.accentHex)
        header("General", p)
        card(p) {
            row("Open at login", p) {
                // Ignore no-op writes: a SwiftUI rebuild that re-sends the current value must never
                // reach onLogin, because turning this OFF removes a login item from disk.
                Toggle("", isOn: Binding(get: { login },
                                         set: { v in guard v != login else { return }; login = v; onLogin(v) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
            }
            div(p)
            row("Show Dock icon", p, info: "Also show Burndown in the Dock and app switcher. Off keeps it menu-bar only.") {
                Toggle("", isOn: Binding(get: { settings.showDockIcon }, set: { v in
                    settings.showDockIcon = v
                    NSApp.setActivationPolicy(v ? .regular : .accessory)
                })).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
            }
            div(p)
            row("Live usage from Claude", p, info: "When on, Burndown reads your real limits from Claude's usage API using your signed-in account. When off, it shows an estimate from your local logs only and never contacts Claude's servers.") {
                Toggle("", isOn: $settings.usageAPI).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
            }
            div(p)
            row("Refresh every", p, info: "How often to check your usage. One minute is plenty: the live burn animation rides a separate fast tracker, so a slower poll costs nothing visually and is gentler on the rate limited usage API.") {
                Segmented(options: [("2s", 2), ("5s", 5), ("10s", 10), ("30s", 30), ("1m", 60), ("5m", 300)],
                          selection: $settings.refreshSeconds, p: p)
            }
            div(p)
            row("Smart refresh", p, info: "Speeds up to about 2 seconds while tokens are flowing, then settles back to your interval. Off keeps your chosen interval exactly.") {
                Toggle("", isOn: $settings.smartRefresh).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
            }
        }
        subhead("Updates", p)
        card(p) {
            row("Check for updates automatically", p, info: "Looks for a newer Burndown once a day. The check is a version lookup at github.com; nothing about you or your usage is sent.") {
                Toggle("", isOn: $settings.autoUpdateCheck).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
            }
            div(p)
            HStack(spacing: 8) {
                Text("Burndown \(kAppVersion)").font(.system(size: 13)).foregroundStyle(p.ink)
                Text(updater.statusLine)
                    .font(.system(size: 11)).foregroundStyle(updateFailed ? Color(hex: kDangerHex) : p.sub)
                    .lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                updateButton(p, coral)
            }.frame(minHeight: 32)
            if case .downloading(let f) = updater.state {
                ProgressView(value: f).progressViewStyle(.linear).tint(coral).padding(.bottom, 8)
            }
            div(p)
            Button {
                if let u = URL(string: "https://github.com/\(Updater.repo)/releases") { NSWorkspace.shared.open(u) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward.square").font(.system(size: 11))
                    Text("Releases and source on GitHub").font(.system(size: 12.5, weight: .medium))
                    Spacer()
                }.foregroundStyle(p.ink).frame(height: 32)
            }.buttonStyle(.plain)
                .help("Opens the Burndown project page, where every release and all of the source code live.")
        }
        subhead("Companions", p)
        card(p) {
            row("Floating window", p, info: "Shows the card as a floating window that stays on top, so you can watch usage without clicking the menu bar. The menu bar calls this Show / Hide Floating Window.") {
                Toggle("", isOn: $settings.floatingShown).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
            }
            if settings.floatingShown {
                div(p)
                row("Window title bar", p, info: "Show the floating window's title bar with its close button and name. Turn it off for a clean, chrome-free card.") {
                    Toggle("", isOn: $settings.floatingChrome).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
                }
            }
            div(p)
            row("Dock to Claude window", p, info: "Attaches a usage widget to an edge of the Claude Desktop window and follows it. Turn it on, then pick the edge below. The first time, macOS asks for Accessibility permission; that is what lets the widget follow the window instantly instead of lagging behind it.") {
                Toggle("", isOn: Binding(get: { settings.dockEdge != .off },
                                         set: { on in settings.dockEdge = on ? (lastDock == .off ? .bottom : lastDock) : .off }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
            }
            if settings.dockEdge != .off {
                div(p)
                row("Edge", p, info: "Which edge of the Claude window the widget attaches to: a slim bar on Top or Bottom, a card on Left or Right.") {
                    Segmented(options: [("Top", DockEdge.top), ("Bottom", .bottom), ("Left", .left), ("Right", .right)],
                              selection: Binding(get: { settings.dockEdge == .off ? .bottom : settings.dockEdge },
                                                 set: { settings.dockEdge = $0; lastDock = $0 }), p: p)
                }
                div(p)
                row("Place inside the window", p, info: "Tuck the widget just inside the window edge instead of just outside it. Combine with Position to sit it snugly in a corner, like the bottom right.") {
                    Toggle("", isOn: $settings.dockInside).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
                }
                div(p)
                row("Position", p, info: "Where the widget sits along the edge. You can also drag it; it then keeps a fixed distance from that corner when the window resizes.") {
                    Segmented(options: [(settings.dockEdge.horizontal ? "Left" : "Top", 0), ("Center", 1), (settings.dockEdge.horizontal ? "Right" : "Bottom", 2)],
                              selection: Binding(get: { settings.edgePx < 0 ? 1 : (settings.edgeFromEnd ? 2 : 0) },
                                                 set: { v in if v == 1 { settings.edgePx = -1 } else { settings.edgeFromEnd = (v == 2); settings.edgePx = 0 } }),
                              p: p)
                }
                div(p)
                row("Widget style", p, info: "The look of the docked widget.") {
                    DropPicker(options: WidgetStyle.allCases.map { ($0.label, $0) }, selection: $settings.widgetStyle, p: p)
                }
                div(p)
                gslider("Widget size", p, Binding(get: { settings.widgetScale * 100 }, set: { settings.widgetScale = $0 / 100 }),
                        70...180, "%", "Scales the docked widget larger or smaller.")
            }
            div(p)
            row("Ember line", p, info: "A quiet ember line along a screen edge, on every display. The bright span is what remains of your 5-hour session; the glowing tip is the burn front, breathing faster as you burn hotter and turning red near the limit.") {
                Toggle("", isOn: $settings.tideLine).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
            }
            if settings.tideLine {
                div(p)
                row("Edge", p, info: "Which screen edge the ember line hugs. It appears on all connected displays and follows when you add, remove, or rearrange screens.") {
                    Segmented(options: [("Top", DockEdge.top), ("Bottom", .bottom), ("Left", .left), ("Right", .right)],
                              selection: $settings.tideEdge, p: p)
                }
                div(p)
                row("Style", p, info: "How the ember line draws: the default Ember Line, a thin Filament, dashed Segmented, a Comet tail, a brightness Taper, Pulse Beads, Spark Front, or a Minimal Node at the burn front.") {
                    DropPicker(options: EmberLineStyle.allCases.map { ($0.label, $0) }, selection: $settings.tideStyle, p: p)
                }
                div(p)
                row("Flames at the front", p, info: "Little flame licks dancing at the burn front (Ember Line style).") {
                    Segmented(options: [("Off", 0), ("1", 1), ("2", 2), ("3", 3)], selection: $settings.tideFlames, p: p)
                }
                div(p)
                row("Glow", p, info: "How brightly the ember line glows.") {
                    Segmented(options: [("Low", 0.7), ("Standard", 1.0), ("High", 1.3)], selection: $settings.tideGlow, p: p)
                }
                div(p)
                row("Thickness", p, info: "How thick the line is drawn.") {
                    Segmented(options: TideThickness.allCases.map { ($0.label, $0) }, selection: $settings.tideThickness, p: p)
                }
                div(p)
                row("Sparks", p, info: "Embers lifting off the burn front.") {
                    Segmented(options: TideSparks.allCases.map { ($0.label, $0) }, selection: $settings.tideSparks, p: p)
                }
                div(p)
                row("Smoke", p, info: "A thin wisp of smoke rising from the burn front when tokens are flowing.") {
                    Toggle("", isOn: $settings.tideSmoke).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
                }
                div(p)
                row("Length", p, info: "How much of the edge the line spans, centered.") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.tideLength, in: 0.4...1.0).frame(width: 120).controlSize(.small).tint(coral)
                        Text("\(Int((settings.tideLength * 100).rounded()))%").font(.system(size: 11, design: .monospaced))
                            .monospacedDigit().foregroundStyle(p.sub).frame(width: 38, alignment: .trailing)
                    }
                }
                div(p)
                row("Transparency", p, info: "How solid the line is. Lower is more see-through.") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.tideOpacity, in: 0.3...1.0).frame(width: 120).controlSize(.small).tint(coral)
                        Text("\(Int((settings.tideOpacity * 100).rounded()))%").font(.system(size: 11, design: .monospaced))
                            .monospacedDigit().foregroundStyle(p.sub).frame(width: 38, alignment: .trailing)
                    }
                }
                div(p)
                row("Displays", p, info: "Which screens carry the ember line: all connected displays, the main display only, or whichever display currently holds the Claude window.") {
                    Segmented(options: TideDisplays.allCases.map { ($0.label, $0) }, selection: $settings.tideDisplays, p: p)
                }
                div(p)
                row("Peek readout", p, info: "Hover the line to see remaining percent and time left in a small capsule. The line stays click-through.") {
                    Toggle("", isOn: $settings.tidePeek).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
                }
            }
        }
    }

    @ViewBuilder private func alertsPane(_ p: Palette) -> some View {
        let coral = Color(hex: settings.accentHex)
        header("Alerts", p)
        card(p) {
            row("Usage alerts", p, info: "macOS notifications when usage crosses your levels. You'll be asked to allow notifications the first time.") {
                Toggle("", isOn: $settings.alertsEnabled).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
            }
            if settings.alertsEnabled {
                // Each trigger is one row: "Off" plus its levels inline; pick a level to enable it.
                alertGroup("Thresholds", p)
                row("Session", p, info: "Alert when the 5-hour session crosses this level, and again at 100%. Off disables it.") {
                    pctAlertControl(p, on: $settings.alertSession, level: $settings.alertSessionAt, levels: [0.75, 0.9, 0.95])
                }
                div(p)
                row("Weekly", p, info: "Alert when the weekly window crosses this level, and again at 100%.") {
                    pctAlertControl(p, on: $settings.alertWeekly, level: $settings.alertWeeklyAt, levels: [0.6, 0.9, 0.95])
                }
                div(p)
                row("Opus (weekly)", p, info: "Alert when Opus weekly usage crosses this level.") {
                    pctAlertControl(p, on: $settings.alertOpus, level: $settings.alertOpusAt, levels: [0.75, 0.9, 0.95])
                }
                div(p)
                row("Sonnet (weekly)", p, info: "Alert when Sonnet weekly usage crosses this level.") {
                    pctAlertControl(p, on: $settings.alertSonnet, level: $settings.alertSonnetAt, levels: [0.75, 0.9, 0.95])
                }
                div(p)
                row("Burn spike", p, info: "Alert when the token burn rate jumps above this (re-arms after it settles).") {
                    Segmented(options: [("Off", -1.0), ("30k", 30_000), ("60k", 60_000), ("100k", 100_000)],
                              selection: Binding(get: { settings.alertBurn ? settings.alertBurnAt : -1 },
                                                 set: { v in if v < 0 { settings.alertBurn = false } else { settings.alertBurn = true; settings.alertBurnAt = v } }), p: p)
                }
                div(p)
                row("Forecast", p, info: "Alert when you're within this much time of the session limit at the current pace.") {
                    Segmented(options: [("Off", -1.0), ("30m", 30), ("1h", 60), ("2h", 120)],
                              selection: Binding(get: { settings.alertForecast ? settings.alertForecastMin : -1 },
                                                 set: { v in if v < 0 { settings.alertForecast = false } else { settings.alertForecast = true; settings.alertForecastMin = v } }), p: p)
                }
                alertGroup("Behavior", p)
                row("Window reset", p, info: "Notify when a fresh session or weekly window starts.") {
                    Toggle("", isOn: $settings.alertOnReset).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
                }
                div(p)
                row("Weekly digest", p, info: "A single Monday summary of what you burned last week. Off by default.") {
                    Toggle("", isOn: $settings.weeklyDigest).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
                }
                div(p)
                row("Repeat while over", p, info: "Re-alert at this interval while still over a level. Once = a single alert per window.") {
                    Segmented(options: [("Once", 0.0), ("15m", 15), ("30m", 30), ("1h", 60)], selection: $settings.alertRepeatMin, p: p)
                }
                div(p)
                row("Sound", p, info: "Play a sound with each alert.") {
                    Toggle("", isOn: $settings.alertSound).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
                }
                if settings.alertSound {
                    div(p)
                    row("Sound style", p, info: "Which sound plays with each alert. Selecting one previews it.") {
                        DropPicker(options: AppSettings.soundOptions, selection: $settings.alertSoundName, p: p)
                            .onChange(of: settings.alertSoundName) { v in previewAlertSound(v) }
                    }
                }
                div(p)
                row("Quiet hours", p, info: "Suppress alerts during these hours; anything crossed is alerted once the window ends.") {
                    Toggle("", isOn: $settings.quietHours).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
                }
                if settings.quietHours {
                    div(p)
                    row("Quiet from", p) { DropPicker(options: hourOptions, selection: $settings.quietFrom, p: p) }
                    div(p)
                    row("Quiet to", p) { DropPicker(options: hourOptions, selection: $settings.quietTo, p: p) }
                }
                alertGroup("Budget & runaway", p)
                row("Budget alert", p, info: "Warn when your spend or tokens approach the budget you set in the Insights window (right-click the menu bar icon, Insights).") {
                    Toggle("", isOn: $settings.alertBudget).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
                }
                div(p)
                row("Runaway burn alert", p, info: "Warn when the burn rate suddenly runs far above your own recent normal, which usually means a loop or a runaway agent. The threshold adapts to how you actually work.") {
                    Toggle("", isOn: $settings.alertRunaway).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
                }
                alertGroup("Test", p)
                Button {
                    NotificationCenter.default.post(name: .fireTestAlert, object: nil)
                    testNote = "Test sent. If no banner appears: System Settings, Notifications, Burndown, set the alert style to Banners or Alerts (not None), and turn off Focus / Do Not Disturb."
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.badge").font(.system(size: 11))
                        Text("Send a test alert").font(.system(size: 12.5, weight: .medium))
                        Spacer()
                    }.foregroundStyle(coral).frame(height: 30)
                }.buttonStyle(.plain)
                if let n = testNote {
                    Text(n).font(.system(size: 10.5)).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true).padding(.bottom, 4)
                }
            }
        }
    }

    @ViewBuilder private func menuBarPane(_ p: Palette) -> some View {
        header("Menu Bar", p)
        card(p) {
            row("Menu bar shows", p) {
                Segmented(options: [("Session", MenuBarShow.session), ("Weekly", .weekly), ("Both", .both)],
                          selection: $settings.menuBarShow, p: p)
            }
            div(p)
            row("Preview chips with", p, info: "Sample shows the styles with example numbers so they always look good. Live shows your real usage right now.") {
                Segmented(options: [("Sample", false), ("Live", true)], selection: $settings.chipLivePreview, p: p)
            }
        }
        card(p) {
            row("Number format", p, info: "How the menu-bar number reads: with a percent sign, bare, or S/W-labeled.") {
                Segmented(options: MenuNumberFormat.allCases.map { ($0.label, $0) }, selection: $settings.menuNumberFormat, p: p)
            }
            div(p)
            row("Time to reset", p, info: "Append a short reset countdown to the fire styles (Smolder, Burnfront, Kiln, Flame).") {
                Toggle("", isOn: $settings.menuTimeToReset).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(Color(hex: settings.accentHex))
            }
            div(p)
            row("Digit weight", p, info: "The weight of the menu-bar digits.") {
                Segmented(options: [("Regular", false), ("Semibold", true)], selection: $settings.menuBoldDigits, p: p)
            }
            div(p)
            row("Percentage", p, info: "Show the percent number. Off makes the Flame style flame-only (the glyph carries the tier).") {
                Segmented(options: [("On", true), ("Off", false)], selection: $settings.menuShowPct, p: p)
            }
        }
        if settings.menuBarStyle == .flame {
            subhead("Flame adjust", p)
            card(p) {
                row("Size", p, info: "How big the flame is drawn. 1.0x is the design's size. Above that the flame grows until it fills the menu bar, which physically caps its height, so the largest sizes mainly help at low usage.") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.flameSize, in: 0.8...2.0)
                            .frame(width: 132).controlSize(.small).tint(Color(hex: settings.accentHex))
                        Text(String(format: "%.2fx", settings.flameSize))
                            .font(.system(size: 11, design: .monospaced)).monospacedDigit()
                            .foregroundStyle(p.sub).frame(width: 42, alignment: .trailing)
                    }
                }
                div(p)
                row("Sparks", p, info: "Redline is the design's spark policy (sparks only near your limit). Always keeps two embers rising at every tier.") {
                    Segmented(options: FlameSparks.allCases.map { ($0.label, $0) }, selection: $settings.flameSparks, p: p)
                }
                div(p)
                row("Smoke", p, info: "A thin wisp drifting off the flame tip. Not in the design; on because a bare flame reads as a blob at this size.") {
                    Segmented(options: [("Off", false), ("On", true)], selection: $settings.flameSmoke, p: p)
                }
            }
        }
        if settings.menuBarStyle == .smolder {
            subhead("Smolder adjust", p)
            card(p) {
                row("Intensity", p, info: "How bright the ember glow burns. The tier caps still hold.") {
                    Segmented(options: [("Soft", 0.75), ("Standard", 1.0), ("Bright", 1.25)], selection: $settings.smolderIntensity, p: p)
                }
                div(p)
                row("Breath", p, info: "How fast the ember breathes.") {
                    Segmented(options: [("Slow", true), ("Standard", false)], selection: $settings.smolderBreathSlow, p: p)
                }
                div(p)
                row("Warmth", p, info: "A wandering hotspot drifts inside the digits, or stays fixed.") {
                    Segmented(options: [("Fixed", false), ("Wander", true)], selection: $settings.smolderWarmthWander, p: p)
                }
            }
        }
        subhead("Style", p)
        // Curated Core set first, then the full library grouped by family (Live / Static gauge /
        // Static text / Both-only). Nothing is cut; the heavy library is just made discoverable.
        let show = settings.menuBarShow
        let core = MenuBarStyle.allCases.filter { $0.isCore && !$0.isRetired && $0.supports(show) }
        if !core.isEmpty { alertGroup("Core", p); glyphGrid(core, p) }
        ForEach(MenuBarStyle.Family.allCases) { fam in
            let items = MenuBarStyle.allCases.filter { $0.family == fam && !$0.isCore && !$0.isRetired && $0.supports(show) }
            if !items.isEmpty { alertGroup(fam.rawValue, p); glyphGrid(items, p) }
        }
        Text(settings.menuBarStyle.desc(settings.menuBarShow))
            .font(.system(size: 11.5)).foregroundStyle(p.sub)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
    }

    private func glyphGrid(_ styles: [MenuBarStyle], _ p: Palette) -> some View {
        let coral = Color(hex: settings.accentHex)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(styles) { st in
                StyleChip(name: st.label, preview: previewGlyph(st), selected: settings.menuBarStyle == st,
                          coral: coral, p: p, live: st.isLive) { settings.menuBarStyle = st }
            }
        }
    }

    @ViewBuilder private func appearancePane(_ p: Palette) -> some View {
        header("Appearance", p)
        card(p) {
            row("Color palette", p, info: "Recolors the whole app. Pick one that suits your desktop or matches Claude.") {
                DropPicker(options: PalettePreset.allCases.map { ($0.label, $0) }, selection: $settings.palette, p: p)
            }
            div(p)
            row("Theme", p) {
                Segmented(options: [("System", AppTheme.system), ("Light", .light), ("Dark", .dark)],
                          selection: $settings.theme, p: p)
            }
            div(p)
            row("Accent color", p) {
                HStack(spacing: 8) {
                    Button { settings.accentHex = kDefaultAccent } label: {
                        Circle().fill(Color(hex: kDefaultAccent)).frame(width: 16, height: 16)
                            .overlay(Circle().stroke(p.ink.opacity(settings.accentHex.uppercased() == kDefaultAccent ? 0.55 : 0), lineWidth: 1.5))
                            .overlay(Circle().stroke(p.divider, lineWidth: 0.5))
                    }.buttonStyle(.plain).help("Reset to Claude orange")
                    ColorPicker("", selection: Binding(get: { Color(hex: settings.accentHex) },
                                                       set: { settings.accentHex = NSColor($0).hexString })).labelsHidden()
                }
            }
            div(p)
            row("Tint by usage", p, info: "Adaptive tints the readout toward red as you near your limit. Solid keeps one fixed color. None uses the system menu bar tint.") {
                Segmented(options: ColorMode.allCases.map { ($0.label, $0) }, selection: $settings.colorMode, p: p)
            }
            div(p)
            row("Live indicator", p, info: "The LIVE badge color: follow the palette, use the accent, a fixed green, or no color.") {
                Segmented(options: [("Theme", LiveColor.theme), ("Accent", .accent), ("Green", .green), ("None", .off)], selection: $settings.liveColor, p: p)
            }
            div(p)
            gslider("Popover size", p, Binding(get: { settings.textScale * 100 }, set: { settings.textScale = $0 / 100 }),
                    70...160, "%", "Scales the whole popover and floating window - text, numbers, chart, and spacing - from compact to large. (Widget size is under Dock, in General.)")
        }
        subhead("Background", p)
        card(p) {
            // Spec 5.2.7: a live glass preview over a checker + sample, and an AA contrast readout that
            // computes ink-on-backing against the synthetic worst case (white in light, black in dark).
            GlassPreview(settings: settings, p: p, scheme: scheme)
            div(p)
            row("Style", p, info: "Liquid Glass uses the real macOS 26 glass that refracts the desktop; Frosted is a classic blur; Clear shows the desktop through just the tint. Applies to the popover and floating window.") {
                Segmented(options: GlassStyle.allCases.map { ($0.label, $0) }, selection: $settings.glassStyle, p: p)
            }
            div(p)
            HStack(spacing: 6) {
                Text("Presets").font(.system(size: 13)).foregroundStyle(p.ink)
                InfoDot(text: "One-tap looks. Crystal stays clear but readable; Minimal is fully clear; Frosted is a soft blur; Vivid is saturated and tinted.", p: p, accent: Color(hex: settings.accentHex))
                Spacer()
                ForEach(AppSettings.glassPresets, id: \.self) { name in
                    Button { settings.applyGlassPreset(name) } label: {
                        Text(name).font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(p.track.opacity(0.7)))
                            .foregroundStyle(p.sub)
                    }.buttonStyle(.plain).focusable(false)
                }
            }.padding(.vertical, 7)
            if settings.glassStyle == .frosted {
                div(p)
                row("Material", p, info: "The frosted-glass material used for the Frosted style.") {
                    DropPicker(options: GlassMaterial.allCases.map { ($0.label, $0) }, selection: $settings.glassMaterial, p: p)
                }
            }
            div(p)
            gslider("Glass opacity", p, $settings.glassOpacity, 55...100, "%", "How opaque the glass layer is behind text. Clamped at 55 percent so text stays legible over any desktop (spec 5.2.7).")
            div(p)
            gslider("Blur radius", p, $settings.glassBlur, 0...40, "pt", "Extra blur on top of the material. 0 keeps the material's native blur; higher softens the backdrop more.")
            div(p)
            gslider("Saturation", p, $settings.glassSaturation, 0...100, "%", "Boosts the color of whatever shows through the glass. 0 is normal.")
            div(p)
            row("Tint", p, info: "A color wash over the glass. None stays fully clear; Theme or Accent tint it and lift text contrast.") {
                Segmented(options: GlassTint.allCases.map { ($0.label, $0) }, selection: $settings.glassTint, p: p)
            }
            if settings.glassTint != .none {
                div(p)
                gslider("Tint intensity", p, $settings.glassTintIntensity, 0...100, "%", "How strong the tint wash is.")
            }
            div(p)
            gslider("Border opacity", p, $settings.glassBorderOpacity, 0...100, "%", "Visibility of a hairline border around the glass edge.")
            div(p)
            gslider("Border width", p, $settings.glassBorderWidth, 0...6, "pt", "Thickness of the glass-edge border. 0 hides it.")
            div(p)
            gslider("Corner radius", p, $settings.glassCornerRadius, 0...28, "pt", "Roundness of the glass corners. 0 is fully square.")
            div(p)
            gslider("Shadow", p, $settings.glassShadow, 0...100, "%", "Depth of the soft drop shadow under the floating window.")
            div(p)
            gslider("Overall transparency", p,
                    Binding(get: { (1 - settings.windowOpacity) / (1 - kMinWindowAlpha) * 100 },
                            set: { settings.windowOpacity = 1 - ($0 / 100) * (1 - kMinWindowAlpha) }),
                    0...100, "%", "How see-through the whole window is (fades everything, including text). Separate from the glass Opacity above.")
            div(p)
            Button { settings.resetGlass() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 11))
                    Text("Reset to defaults").font(.system(size: 12.5, weight: .medium))
                    Spacer()
                }.foregroundStyle(Color(hex: settings.accentHex)).frame(height: 30)
            }.buttonStyle(.plain)
        }
        subhead("Numbers", p)
        card(p) {
            row("Number animation", p, info: "How numbers transition when they change (session %, cost, tokens). The chart is unaffected. Tap Shuffle below to preview.") {
                DropPicker(options: NumberStyle.allCases.map { ($0.label, $0) }, selection: $settings.numberStyle, p: p)
            }
            div(p)
            NumberDemoRow(settings: settings, p: p)
        }
    }

    @ViewBuilder private func popoverPane(_ p: Palette) -> some View {
        let coral = Color(hex: settings.accentHex)
        header("Popover", p)
        subhead("Sections", p)
        Text("Drag to reorder the panels in the popover. Use the eye to hide any you do not need. The app name stays pinned at the bottom.")
            .font(.system(size: 11.5)).foregroundStyle(p.sub).frame(maxWidth: .infinity, alignment: .leading)
        sectionsEditor(p, coral)
        subhead("Session line", p)
        card(p) {
            row("Estimated cost", p, info: "Show the estimated pay-as-you-go API price of the tokens you have used (what it would cost without a subscription) on the Session and This week lines. An estimate, not a bill.") {
                Toggle("", isOn: $settings.showCost).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
            }
            div(p)
            row("Token rate", p, info: "Show the live tokens-per-minute burn rate beside the cost on the Session line.") {
                Toggle("", isOn: $settings.showTokens).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
            }
        }
        // Per-element visibility (spec area 3): grouped eye toggles. Each hides one popover element and
        // the card content-hugs to a shorter height with no gaps.
        subhead("Session", p)
        card(p) {
            visRow("Time ring", $settings.showTimeRing, "The reset-countdown ring beside the session number.", p, coral); div(p)
            visRow("Forecast line", $settings.showForecastLine, "The time-to-limit / status line under the session number.", p, coral)
        }
        subhead("This week", p)
        card(p) {
            visRow("Week percentage", $settings.showWeekPercent, "The large weekly percentage and its bar.", p, coral); div(p)
            visRow("Last 7 days", $settings.showLast7Days, "The seven small daily-usage bars.", p, coral); div(p)
            visRow("Week resets", $settings.showWeekResets, "When the weekly window resets.", p, coral); div(p)
            visRow("By model breakdown", $settings.showOpusShare, "The BY MODEL split showing each model's share of the week, and any per-model caps.", p, coral)
        }
        subhead("Chart & chats", p)
        card(p) {
            visRow("Chart section", $settings.showBurnChart, "The chart card. Off hides the whole chart section and its divider. Pick which charts it shows in the Charts tab.", p, coral); div(p)
            visRow("Chats burning now", $settings.showChatsBurning, "The list of chats currently using tokens.", p, coral); div(p)
            visRow("Chats expanded", $settings.chatsExpanded, "Show the chat rows expanded. The popover remembers whichever way you leave it.", p, coral); div(p)
            row("Chat name truncation", p, info: "How long chat names are shortened: keep the middle, keep the start, or the full name on hover.") {
                DropPicker(options: ChatTruncation.allCases.map { ($0.label, $0) }, selection: $settings.chatTruncation, p: p)
            }
        }
        subhead("Developer API", p)
        card(p) {
            visRow("Developer API line", $settings.showDeveloperApiLine, "Show your pay-as-you-go API spend as one line at the bottom, when an Admin key is connected.", p, coral)
        }
        subhead("Chrome", p)
        card(p) {
            visRow("Section dividers", $settings.popoverDividers, "The hairlines between sections. Off leaves the spacing alone to separate them.", p, coral); div(p)
            visRow("Section eyebrows", $settings.popoverEyebrows, "The small uppercase labels (SESSION, THIS WEEK).", p, coral); div(p)
            visRow("Compact spacing", $settings.popoverCompact, "Tighten the vertical spacing to fit more in less height.", p, coral)
        }
    }

    // One eye/switch visibility row for the Popover pane (spec area 3).
    @ViewBuilder private func visRow(_ label: String, _ bind: Binding<Bool>, _ info: String, _ p: Palette, _ coral: Color) -> some View {
        row(label, p, info: info) {
            Toggle("", isOn: bind).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(coral)
        }
    }

    /// The chart gallery data context: sample data (deterministic, always looks alive) or the user's
    /// real data, per the toggle. Hover is off so previews stay calm.
    private func galleryCtx(_ p: Palette) -> ChartCtx {
        let accent = Color(hex: settings.accentHex)
        if galleryLive {
            return ChartCtx(burnSamples: live.burnSamples, usageSamples: live.usageSamples,
                            weeklySamples: live.weeklySamples, records: engine.records,
                            sessionPct: engine.snapshot.sessionPct, weeklyPct: engine.snapshot.weeklyPct,
                            sessionResetAt: engine.snapshot.sessionResetAt, weeklyResetAt: engine.snapshot.weeklyResetAt,
                            modelLimits: engine.snapshot.modelLimits,
                            accent: accent, secondary: kSlate, p: p, style: settings.chartStyle,
                            window: settings.burnSpan.seconds, days: settings.chartDays, hover: false)
        }
        let series = StyleSheet.qaSampleSeries()
        return ChartCtx(burnSamples: series.burn, usageSamples: series.usage, weeklySamples: series.weekly,
                        records: StyleSheet.qaChartRecords(),
                        sessionPct: 0.46, weeklyPct: 0.13,
                        sessionResetAt: Date().addingTimeInterval(2.5 * 3600),
                        weeklyResetAt: Date().addingTimeInterval(3 * 86400),
                        modelLimits: [ScopedLimit(label: "Fable", pct: 0.74, resetAt: nil, active: true, severity: "warning"),
                                      ScopedLimit(label: "Opus", pct: 0.18, resetAt: nil, active: false, severity: "normal")],
                        accent: accent, secondary: kSlate, p: p, style: settings.chartStyle,
                        window: 6 * 3600, days: 14, hover: false)
    }

    private static let kMaxPopoverCharts = 6

    /// One gallery card: name, live preview, one-line description, and its slot number when selected.
    private func chartCard(_ k: ChartKind, _ p: Palette, ctx: ChartCtx) -> some View {
        let coral = Color(hex: settings.accentHex)
        let slot = settings.chartKinds.firstIndex(of: k)
        let on = slot != nil
        return Button {
            if let i = settings.chartKinds.firstIndex(of: k) {
                guard settings.chartKinds.count > 1 else { return }   // the popover always shows at least one
                settings.chartKinds.remove(at: i)
            } else {
                guard settings.chartKinds.count < Self.kMaxPopoverCharts else { return }
                settings.chartKinds.append(k)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(k.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(p.ink)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 4)
                    if let i = slot {
                        // The slot number doubles as the order the popover stacks them in.
                        Text("\(i + 1)")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(coral))
                            .help("Shown in the popover, position \(i + 1). Click to remove.")
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(p.faint)
                            .frame(width: 16, height: 16)
                            .background(Circle().stroke(p.divider, lineWidth: 1))
                            .help("Click to show this chart in the popover.")
                    }
                }
                ChartBodyView(kind: k, ctx: ctx)
                    .allowsHitTesting(false)
                    .padding(.top, 6)   // room for top axis labels and the avg annotation
                    .frame(height: 104, alignment: .top)
                    .clipped()
                Text(k.blurb)
                    .font(.system(size: 9.5)).foregroundStyle(p.faint)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.track.opacity(on ? 0.55 : 0.3)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(on ? coral.opacity(0.75) : p.divider, lineWidth: on ? 1.5 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain).focusable(false)
        .accessibilityLabel(k.label)
        .accessibilityValue(on ? "Shown in the popover" : "Not shown")
        .accessibilityHint(k.blurb)
    }

    @ViewBuilder private func dataPane(_ p: Palette) -> some View {
        let coral = Color(hex: settings.accentHex)
        let ctx = galleryCtx(p)
        header("Charts", p)
        // ── The gallery: every chart, drawn for real, click to choose what the popover shows ──
        Text("Click a chart to show it in the popover; click again to remove it. The number is its position, top to bottom. You can show up to \(Self.kMaxPopoverCharts) at once.")
            .font(.system(size: 11.5)).foregroundStyle(p.sub)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 8) {
            Text(settings.chartKinds.count == 1 ? "1 chart in the popover" : "\(settings.chartKinds.count) charts in the popover")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(coral)
            Spacer()
            Text("Preview with").font(.system(size: 11)).foregroundStyle(p.faint)
            Segmented(options: [("Sample", false), ("My data", true)], selection: $galleryLive, p: p)
        }
        ForEach(ChartKind.groupOrder, id: \.self) { g in
            subhead(g, p)
            let items = ChartKind.allCases.filter { $0.group == g }
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { i in
                HStack(alignment: .top, spacing: 8) {
                    chartCard(items[i], p, ctx: ctx)
                    if i + 1 < items.count {
                        chartCard(items[i + 1], p, ctx: ctx)
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        subhead("Chart options", p)
        card(p) {
            row("Chart style", p, info: "The look of the line and area charts, where it applies. \(settings.chartStyle.blurb)") {
                DropPicker(options: ChartStyle.allCases.map { ($0.label, $0) }, selection: $settings.chartStyle, p: p)
            }
            div(p)
            windowPicker("Time window", p, $settings.burnSpan,
                         "How far back the rolling charts reach, from 30 minutes up to all of your retained history. Applies to the Burn, Steps, Volume, Cumulative, Spread, Usage %, By model, By project, Top chats, the two Mix bars, Cache efficiency, and Input vs output.")
            div(p)
            row("Day span", p, info: "How many days the day-scale charts cover: Cost per day, Hour of day, Day of week, Tokens per day, Session blocks, Spend to date, and the Activity heatmap (the heatmap always shows the most recent 7).") {
                DropPicker(options: [("7 days", 7), ("14 days", 14), ("30 days", 30), ("90 days", 90)],
                           selection: $settings.chartDays, p: p)
            }
            div(p)
            row("Hover readout", p, info: "Point at the chart to read the exact value under the cursor, tagged on the chart itself. Turn off for a static chart.") {
                Toggle("", isOn: $settings.chartHover).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(Color(hex: settings.accentHex))
            }
            div(p)
            row("Refresh countdown", p, info: "The small pulsing dot and interval on the chart card showing that data is live and how often it refreshes. Turn off to hide it.") {
                Toggle("", isOn: $settings.showCountdownRing).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(Color(hex: settings.accentHex))
            }
            div(p)
            row("Explain each section", p, info: "Shows a small, faint question dot beside each popover section and chart title. Hover it for a plain-English explanation. Off hides the dots; the tooltips on the labels themselves stay.") {
                Toggle("", isOn: $settings.popoverExplain).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(Color(hex: settings.accentHex))
            }
        }
        subhead("Stored data", p)
        card(p) {
            Text("Your usage history is kept on this Mac and survives restarts. Export it for your own analysis, or clear it. Your Claude account, limits, and settings are not affected.")
                .font(.system(size: 11)).foregroundStyle(p.sub).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7)
            div(p)
            Button {
                if let u = live.exportCSV() {
                    NSWorkspace.shared.activateFileViewerSelecting([u])
                    exportNote = "Saved \(u.lastPathComponent) to Downloads"
                } else { exportNote = "Could not write the file." }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 11))
                    Text("Export history as CSV…").font(.system(size: 12.5, weight: .medium))
                    Spacer()
                }.foregroundStyle(p.ink).frame(height: 32)
            }.buttonStyle(.plain)
            if let n = exportNote {
                Text(n).font(.system(size: 11)).foregroundStyle(p.sub).padding(.bottom, 6)
            }
            div(p)
            Button { confirmReset = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash").font(.system(size: 11))
                    Text("Reset chart history and logs…").font(.system(size: 12.5, weight: .medium))
                    Spacer()
                }.foregroundStyle(Color(hex: kDangerHex)).frame(height: 32)
            }.buttonStyle(.plain)
        }
    }

    // MARK: - Building blocks

    private func header(_ title: String, _ p: Palette) -> some View {
        Text(title).font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(p.ink)
    }
    private func subhead(_ title: String, _ p: Palette) -> some View {
        Text(title).font(.system(size: 11, weight: .medium)).tracking(0.4).foregroundStyle(p.faint).padding(.top, 4)
    }
    private func card<C: View>(_ p: Palette, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 12).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 10).fill(p.track.opacity(0.45)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.divider, lineWidth: 0.5))
    }
    private func row<C: View>(_ title: String, _ p: Palette, @ViewBuilder _ control: @escaping () -> C) -> some View {
        SettingRow(title: title, accent: Color(hex: settings.accentHex), p: p, control: control)
    }
    private func row<C: View>(_ title: String, _ p: Palette, info: String, @ViewBuilder _ control: @escaping () -> C) -> some View {
        SettingRow(title: title, info: info, accent: Color(hex: settings.accentHex), p: p, control: control)
    }
    private func div(_ p: Palette) -> some View { Rectangle().fill(p.divider).frame(height: 1) }

    // An in-card group header for long cards (e.g. Alerts: Thresholds / Behavior / Test).
    private func alertGroup(_ t: String, _ p: Palette) -> some View {
        Text(t.uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(0.8).foregroundStyle(p.faint)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 11).padding(.bottom, 3)
    }

    // A percent-threshold alert control: "Off" + levels in one segmented, bound to an on-flag + level.
    private func pctAlertControl(_ p: Palette, on: Binding<Bool>, level: Binding<Double>, levels: [Double]) -> some View {
        let opts: [(String, Double)] = [("Off", -1.0)] + levels.map { ("\(Int($0 * 100))%", $0) }
        // Snap a stored/migrated level to the nearest offered chip so the control always shows exactly
        // one selection. A legacy threshold like 0.8 is not one of the chips and would highlight none.
        func snap(_ v: Double) -> Double { levels.min(by: { abs($0 - v) < abs($1 - v) }) ?? v }
        return Segmented(options: opts,
                         selection: Binding(get: { on.wrappedValue ? snap(level.wrappedValue) : -1 },
                                            set: { v in if v < 0 { on.wrappedValue = false } else { on.wrappedValue = true; level.wrappedValue = v } }),
                         p: p)
    }
    private func hourLabel(_ h: Int) -> String {
        h == 0 ? "12 AM" : h < 12 ? "\(h) AM" : h == 12 ? "12 PM" : "\(h - 12) PM"
    }
    private var hourOptions: [(String, Double)] { (0..<24).map { (hourLabel($0), Double($0)) } }

    // A full window picker (30m … all) as one unified, equal-width 5x2 grid in a single track.
    private func windowPicker(_ title: String, _ p: Palette, _ sel: Binding<ChartSpan>, _ info: String) -> some View {
        let opts = ChartSpan.allCases
        let cols = 5
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 13)).foregroundStyle(p.ink)
                InfoDot(text: info, p: p, accent: Color(hex: settings.accentHex))
                Spacer()
            }
            VStack(spacing: 2) {
                ForEach(0..<((opts.count + cols - 1) / cols), id: \.self) { r in
                    HStack(spacing: 2) {
                        ForEach(0..<cols, id: \.self) { c in
                            let idx = r * cols + c
                            if idx < opts.count {
                                let o = opts[idx]; let on = sel.wrappedValue == o
                                Text(o.tiny).font(.system(size: 11, weight: on ? .semibold : .regular))
                                    .frame(maxWidth: .infinity).padding(.vertical, 4)
                                    .background(on ? p.bg : .clear).foregroundStyle(on ? p.ink : p.sub)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1, y: 0.5)
                                    .contentShape(Rectangle())
                                    .onTapGesture { sel.wrappedValue = o }
                            } else {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }.padding(2).background(p.track).clipShape(RoundedRectangle(cornerRadius: 8))
        }.padding(.vertical, 7)
    }

    private func slider(_ title: String, _ p: Palette, _ value: Binding<Double>, info: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 13)).foregroundStyle(p.ink)
                InfoDot(text: info, p: p, accent: Color(hex: settings.accentHex))
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))").font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(p.sub)
            }
            Slider(value: value, in: 0...100).controlSize(.small).tint(Color(hex: settings.accentHex))
        }.padding(.vertical, 7)
    }

    // Slider with an explicit range and a unit suffix in the readout (used by the glass tuning panel).
    private func gslider(_ title: String, _ p: Palette, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ unit: String, _ info: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 13)).foregroundStyle(p.ink)
                InfoDot(text: info, p: p, accent: Color(hex: settings.accentHex))
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))\(unit)").font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(p.sub)
            }
            Slider(value: value, in: range).controlSize(.small).tint(Color(hex: settings.accentHex))
        }.padding(.vertical, 7)
    }

    // Drag-to-reorder list of popover modules, with an eye to hide each.
    private func sectionsEditor(_ p: Palette, _ coral: Color) -> some View {
        List {
            ForEach(settings.sectionOrder, id: \.self) { raw in
                if let sec = CardSection(rawValue: raw) {
                    let hidden = settings.isHidden(sec)
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal").font(.system(size: 11)).foregroundStyle(p.faint)
                        Text(sec.label).font(.system(size: 13)).foregroundStyle(hidden ? p.faint : p.ink)
                        Spacer()
                        Button { settings.toggleHidden(sec) } label: {
                            Image(systemName: hidden ? "eye.slash.circle" : "eye.circle.fill").font(.system(size: 16))
                        }.buttonStyle(.plain).foregroundStyle(hidden ? p.faint : coral)
                    }
                    .listRowInsets(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .onMove { from, to in settings.sectionOrder.move(fromOffsets: from, toOffset: to) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .frame(height: CGFloat(settings.sectionOrder.count) * 38 + 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(p.track.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(p.divider, lineWidth: 0.5))
    }

    // MARK: - Menu-bar chip preview (sample data, or the user's real live data)

    private func previewGlyph(_ style: MenuBarStyle) -> NSImage {
        MenuBarRenderer.image(style: style, baseGlyph())
    }
    private func baseGlyph() -> GlyphData {
        let accent = NSColor(hex: settings.accentHex) ?? NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
        let mode = settings.colorMode
        let sec = (mode == .system) ? NSColor.labelColor : secondaryNSColor(accent: accent, mode: mode)
        func uc(_ pct: Double) -> NSColor { (mode == .system) ? .labelColor : usageNSColor(pct: pct, over: false, accent: accent, mode: mode) }
        func pctStr(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
        var g: GlyphData
        if settings.chipLivePreview {
            let s = engine.snapshot
            let sP = s.sessionPct, wP = s.weeklyPct
            switch settings.menuBarShow {
            case .session: g = GlyphData(pct: sP, pctText: pctStr(sP), primary: uc(sP), secFrac: 0.9, secText: s.sessionResetAt.map { weekLeftString($0) } ?? "-", secondary: sec, pLabel: "", sLabel: "")
            case .weekly:  g = GlyphData(pct: wP, pctText: pctStr(wP), primary: uc(wP), secFrac: 0.6, secText: s.weeklyResetAt.map { weekLeftString($0) } ?? "-", secondary: sec, pLabel: "", sLabel: "")
            case .both:    g = GlyphData(pct: sP, pctText: pctStr(sP), primary: uc(sP), secFrac: wP, secText: pctStr(wP), secondary: uc(wP), pLabel: "S", sLabel: "W")
            }
            g.costText = money(s.sessionCost); g.tokText = "≈" + fmtTok(s.sessionFresh)
            g.needle = min(1, live.rate / LiveActivity.RATE_FULL); g.active = live.active; g.rollPhase = 1
            g.hasSecondary = (settings.menuBarShow == .both)
            if let r = s.weeklyResetAt { g.weekLeftText = weekLeftString(r) }
            g.spark = live.history.isEmpty ? [0.1, 0.2, 0.15, 0.3, 0.25, 0.4] : live.history
            return g
        }
        switch settings.menuBarShow {
        case .session: g = GlyphData(pct: 0.46, pctText: "46%", primary: uc(0.46), secFrac: 0.9, secText: "4h31m", secondary: sec, pLabel: "", sLabel: "")
        case .weekly:  g = GlyphData(pct: 0.13, pctText: "13%", primary: uc(0.13), secFrac: 0.6, secText: "3d", secondary: sec, pLabel: "", sLabel: "")
        case .both:    g = GlyphData(pct: 0.46, pctText: "46%", primary: uc(0.46), secFrac: 0.13, secText: "13%", secondary: sec, pLabel: "S", sLabel: "W")
        }
        g.costText = "$112"; g.tokText = "≈3.0M"; g.needle = 0.62; g.active = true; g.rollPhase = 1
        g.hasSecondary = (settings.menuBarShow == .both)
        g.weekLeftText = "3d 4h"
        g.spark = [0.05, 0.12, 0.08, 0.22, 0.18, 0.4, 0.32, 0.55, 0.6, 0.5, 0.78, 0.7]
        return g
    }
}

// A small info affordance - CLICK the ⓘ to open a native popover with the explanation
// (instant; also opens on a brief hover). Replaces the slow, non-clickable `.help()` tooltip.
// A live preview of the number-change animation (numbers rarely change, so this lets you try styles).
struct NumberDemoRow: View {
    @ObservedObject var settings: AppSettings
    var p: Palette
    @State private var demo = 46
    var body: some View {
        HStack {
            Text("Preview").font(.system(size: 13)).foregroundStyle(p.ink)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(demo)").font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(Color(hex: settings.accentHex))
                    .monospacedDigit().numberAnim(settings.numberStyle, demo)
                Text("%").font(.system(size: 12, weight: .medium)).foregroundStyle(Color(hex: settings.accentHex).opacity(0.7))
            }
            Button("Shuffle") { demo = (demo + 23) % 100 }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Color(hex: settings.accentHex)).padding(.leading, 12)
        }.frame(height: 42)
    }
}

// The one unified settings row: a 46pt baseline, label 13.5/medium with an optional info-dot and
// description, control right-aligned, and a 4% ink hover tint. Replaces the old 34pt ad-hoc rows so
// every pane shares one rhythm.
struct SettingRow<C: View>: View {
    let title: String
    var desc: String? = nil
    var info: String? = nil
    var accent: Color = Color(hex: kDefaultAccent)
    let p: Palette
    @ViewBuilder let control: () -> C
    @State private var hover = false
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(p.ink)
                    if let info { InfoDot(text: info, p: p, accent: accent) }
                }
                if let desc {
                    Text(desc).font(.system(size: 11.5)).foregroundStyle(p.sub).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .frame(minHeight: 46)
        .contentShape(Rectangle())
        .background(hover ? p.ink.opacity(0.04) : Color.clear)
        .onHover { hover = $0 }
    }
}

/// C10: ONE reusable info affordance, identical everywhere. A 13pt circle with a 1px `faint`
/// border and an 8.5pt sans semibold "i" in `sub` (NOT an SF Symbol), help cursor; click opens a
/// 240ms card (radius 10, `raisedBg`, max 240pt, body 11.5 / line spacing 1.5). It replaces every
/// ad-hoc info glyph in Settings and Account. Budget: 3 per card, about 20 app-wide.
struct InfoDot: View {
    var text: String; var p: Palette
    var accent: Color = Color(hex: kDefaultAccent)
    @State private var show = false
    @State private var hoverTok = UUID()
    var body: some View {
        ZStack {
            Circle().strokeBorder(show ? accent : p.faint, lineWidth: 1)
            Text("i").font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(show ? accent : p.sub)
        }
        .frame(width: 13, height: 13)
        .contentShape(Circle())
        .onTapGesture { withAnimation(.emberEase(Dur.d240)) { show.toggle() } }
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            guard inside else { hoverTok = UUID(); return }
            let tok = UUID(); hoverTok = tok
            DispatchQueue.main.asyncAfter(deadline: .now() + Dur.d320) { if hoverTok == tok { show = true } }
        }
        .accessibilityLabel("More information")
        .accessibilityValue(text)
        .accessibilityAddTraits(.isButton)
        .popover(isPresented: $show, arrowEdge: .bottom) {
            Text(text)
                .font(.system(size: 11.5)).lineSpacing(1.5).foregroundStyle(p.ink)
                .frame(maxWidth: 240, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.raisedBg))
        }
    }
}

struct Segmented<T: Equatable>: View {
    var options: [(String, T)]
    @Binding var selection: T
    var p: Palette
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let on = options[i].1 == selection
                Text(options[i].0)
                    .font(.system(size: 11, weight: on ? .semibold : .regular))
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(on ? p.bg : .clear)
                    .foregroundStyle(on ? p.ink : p.sub)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1, y: 0.5)
                    .onTapGesture { selection = options[i].1 }
            }
        }.padding(2).background(p.track).clipShape(RoundedRectangle(cornerRadius: 8)).fixedSize()
    }
}

// A compact dropdown for when there are too many options for a segmented control.
struct DropPicker<T: Hashable>: View {
    var options: [(String, T)]
    @Binding var selection: T
    var p: Palette
    var recommended: T? = nil    // appends "· Recommended" to this option in the menu
    private var current: String { options.first { $0.1 == selection }?.0 ?? "-" }
    var body: some View {
        Menu {
            ForEach(options, id: \.1) { opt in
                Button { selection = opt.1 } label: {
                    let label = opt.1 == recommended ? "\(opt.0)  ·  Recommended" : opt.0
                    if opt.1 == selection { Label(label, systemImage: "checkmark") } else { Text(label) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(current).font(.system(size: 11, weight: .medium)).foregroundStyle(p.ink)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(p.faint)
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(p.track))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}

// A real menu-bar-like translucent material (so the style chips sit on a surface that
// matches the actual menu bar instead of a flat gray swatch).
struct MenuBarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView(); v.material = .menu; v.blendingMode = .behindWindow; v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct StyleChip: View {
    var name: String; var preview: NSImage; var selected: Bool; var coral: Color; var p: Palette; var live = false; var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    MenuBarMaterial().clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(p.divider, lineWidth: 0.5))
                    Image(nsImage: preview)
                }.frame(height: 24)
                // A small real-time dot marks the live (token-reactive) styles vs the static ones.
                .overlay(alignment: .topTrailing) { if live { Circle().fill(coral).frame(width: 4, height: 4).padding(3) } }
                Text(name).font(.system(size: 9, weight: selected ? .semibold : .regular))
                    .lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(selected ? coral : p.sub)
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? coral.opacity(0.15) : p.track.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? coral.opacity(0.6) : .clear, lineWidth: 1))
        }.buttonStyle(.plain).focusable(false)
    }
}

// MARK: - Popover host (display only - settings live in their own window)

// Frosted-glass backing (a real NSVisualEffectView behind the window). Used by the card
// surfaces so the Frosted-glass slider can blend from solid (today's look) to full frost.
func nsMaterial(_ g: GlassMaterial) -> NSVisualEffectView.Material {
    switch g {
    case .popover:     return .popover
    case .menu:        return .menu
    case .hud:         return .hudWindow
    case .sidebar:     return .sidebar
    case .fullScreen:  return .fullScreenUI
    case .underWindow: return .underWindowBackground
    }
}

struct GlassBG: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = .behindWindow; v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

// True macOS 26 "Liquid Glass": reach the real NSGlassEffectView via the ObjC runtime (the build SDK
// predates it, but the OS at runtime has it). It refracts and reflects the desktop behind the window
// instead of just blurring it. On anything older, it transparently falls back to the frosted material.
struct LiquidGlassBG: NSViewRepresentable {
    var fallback: NSVisualEffectView.Material = .underWindowBackground
    func makeNSView(context: Context) -> NSView {
        if let cls = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let v = cls.init(frame: .zero)
            v.wantsLayer = true
            return v
        }
        let ve = NSVisualEffectView()
        ve.material = fallback; ve.blendingMode = .behindWindow; ve.state = .active
        return ve
    }
    func updateNSView(_ v: NSView, context: Context) {}
}

// The themed surface for the popover / floating card, honoring the Frosted-glass slider + material.
// glassiness 0 = solid theme background (unchanged); 1 = full frosted material.
struct CardSurface: View {
    @ObservedObject var settings: AppSettings
    var p: Palette
    var body: some View {
        let s = settings
        let tint: Color = {
            switch s.glassTint {
            case .none:   return .clear
            case .theme:  return p.bg
            case .accent: return Color(hex: s.accentHex)
            }
        }()
        ZStack {
            // The material (refraction/blur), with adjustable extra blur + saturation applied to the
            // composited backdrop. Clear = no material, just the tint scrim over the live desktop.
            Group {
                switch s.glassStyle {
                case .liquid:  LiquidGlassBG()
                case .frosted: GlassBG(material: nsMaterial(s.glassMaterial))
                case .clear:   Color.clear
                }
            }
            .saturation(1 + s.glassSaturation / 100)
            .blur(radius: s.glassBlur)
            // Tint scrim: tints the glass and lifts text contrast over busy wallpapers.
            tint.opacity(min(1, s.glassTintIntensity / 100 * 0.7))
        }
        .opacity(max(0.05, min(1, s.glassOpacity / 100)))
        .clipShape(RoundedRectangle(cornerRadius: s.glassCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: s.glassCornerRadius, style: .continuous)
                .strokeBorder(p.ink.opacity(s.glassBorderOpacity / 100), lineWidth: s.glassBorderWidth)
        )
        .shadow(color: .black.opacity(s.glassShadow / 100 * 0.45), radius: s.glassShadow / 100 * 22, y: 6)
    }
}

struct BlurMod: ViewModifier { var r: CGFloat; func body(content: Content) -> some View { content.blur(radius: r) } }
struct FlipMod: ViewModifier { var a: Double; func body(content: Content) -> some View { content.rotation3DEffect(.degrees(a), axis: (x: 1, y: 0, z: 0)) } }

// Replaces the view on value change so an insertion/removal transition runs (for non-numericText styles).
struct NumChange<C: View>: View {
    var value: AnyHashable; var t: AnyTransition; var anim: Animation
    @ViewBuilder var content: C
    var body: some View { ZStack { content.id(value).transition(t) }.animation(anim, value: value) }
}

// Animate a changing number per the chosen style (used on the popover's big numbers, not the chart).
extension View {
    @ViewBuilder func numberAnim(_ style: NumberStyle, _ value: some Equatable & Hashable) -> some View {
        switch style {
        case .none:      self
        case .roll:      self.contentTransition(.numericText()).animation(.snappy(duration: 0.45), value: value)
        case .counter:   self.contentTransition(.numericText(countsDown: false)).animation(.easeOut(duration: 0.7), value: value)
        case .fade:      NumChange(value: AnyHashable(value), t: .opacity, anim: .easeInOut(duration: 0.35)) { self }
        case .scale:     NumChange(value: AnyHashable(value), t: .scale.combined(with: .opacity), anim: .spring(response: 0.4, dampingFraction: 0.7)) { self }
        case .pop:       NumChange(value: AnyHashable(value), t: .scale(scale: 0.5).combined(with: .opacity), anim: .spring(response: 0.3, dampingFraction: 0.5)) { self }
        case .bounce:    NumChange(value: AnyHashable(value), t: .scale(scale: 1.5).combined(with: .opacity), anim: .spring(response: 0.45, dampingFraction: 0.45)) { self }
        case .slideUp:   NumChange(value: AnyHashable(value), t: .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)), anim: .spring(response: 0.4, dampingFraction: 0.85)) { self }
        case .slideDown: NumChange(value: AnyHashable(value), t: .asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .move(edge: .bottom).combined(with: .opacity)), anim: .spring(response: 0.4, dampingFraction: 0.85)) { self }
        case .push:      NumChange(value: AnyHashable(value), t: .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)), anim: .easeInOut(duration: 0.4)) { self }
        case .blur:      NumChange(value: AnyHashable(value), t: .modifier(active: BlurMod(r: 7), identity: BlurMod(r: 0)).combined(with: .opacity), anim: .easeOut(duration: 0.4)) { self }
        case .flip:      NumChange(value: AnyHashable(value), t: .modifier(active: FlipMod(a: 90), identity: FlipMod(a: 0)).combined(with: .opacity), anim: .spring(response: 0.4, dampingFraction: 0.7)) { self }
        case .zoom:      NumChange(value: AnyHashable(value), t: .scale(scale: 2.4).combined(with: .opacity), anim: .spring(response: 0.35, dampingFraction: 0.6)) { self }
        }
    }
}

// Feature 14 (Redline): a warm glow that rises over the popover as the session nears its cap -
// a smoldering border + heat blooming up from the top where the big Session % sits. 0 below 85%.
/// Spec 4.6 redline recipe: a 1pt `overLimit` border at 35 percent and a bloom fading 8 -> 0
/// percent over 110pt, the bloom BREATHING 8 to 12 percent on the redline tier's 2.4s period
/// (spec 7.3). The colour is the `overLimit` role token, never a hardcoded hex (spec 7.6).
struct RedlineOverlay: View {
    var heat: Double
    var radius: CGFloat
    var p: Palette
    @State private var bloomHigh = false
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        let anger = p.overLimit
        let on = heat > 0.001
        // The bloom rides 8 -> 12 percent on the redline period. Driven by CORE ANIMATION (a repeating
        // opacity ramp the render server interpolates), NOT a TimelineView: a TimelineView tick
        // re-commits the whole window every frame, which is what made the popover expensive.
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(RadialGradient(colors: [anger.opacity(0.12 * heat), .clear], center: .top, startRadius: 8, endRadius: 110))
                .opacity(bloomHigh ? 1.0 : 0.667)          // 0.12 * (0.667...1.0) == the spec's 8 -> 12 percent
                .animation(reduce ? nil : .easeInOut(duration: BurnTier.redline.period / 2)
                                            .repeatForever(autoreverses: true), value: bloomHigh)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(anger.opacity(0.35 * heat), lineWidth: 1)
        }
        .onAppear { bloomHigh = on }
        .onChange(of: on) { bloomHigh = $0 }
        .allowsHitTesting(false)
        .opacity(on ? 1 : 0)
        .animation(.emberEase(Dur.d480), value: heat)
    }
}

struct MenuCard: View {
    @ObservedObject var engine: UsageEngine
    @ObservedObject var settings: AppSettings
    @ObservedObject var live: LiveActivity
    var onRefresh: () -> Void
    var floating = false                      // true for the floating window (adds pin + right-click menu)
    var onSettings: () -> Void = {}
    var onHideFloating: () -> Void = {}
    var onSignIn: () -> Void = {}
    var onOpenLogs: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @State private var natH: CGFloat = 500
    // The 7-day cost spark is O(records) with per-record price lookups; cache it so a card re-render
    // (the floating window redraws on every live update) does NOT recompute it every frame.
    @State private var spark: [Double] = []
    @State private var sparkKey = -1

    var body: some View {
        let p = Palette.of(scheme)
        let scale = max(0.7, min(1.6, settings.textScale))
        // Redline heat (feature 14): the whole card smolders as the session nears its cap.
        let s = engine.snapshot
        let heat = s.over ? 1.0 : max(0, (min(1, s.sessionPct) - 0.85) / 0.15)
        DetailCard(snapshot: engine.snapshot, settings: settings, live: live,
                   refreshAnchor: engine.refreshAnchor, heartbeat: engine.heartbeat,
                   period: engine.refreshPeriod,
                   signedIn: engine.isSignedIn(), loading: !engine.ready,
                   dailySpark: spark, records: engine.records,
                   apiSpend: engine.apiSpend,
                   onRefresh: onRefresh, onSignIn: onSignIn, onOpenLogs: onOpenLogs)
            .frame(width: 264)
            .background(GeometryReader { g in Color.clear.preference(key: ContentHeightKey.self, value: g.size.height) })
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: 264 * scale, height: natH * scale, alignment: .topLeading)
            .background(CardSurface(settings: settings, p: p))
            .overlay(RedlineOverlay(heat: heat, radius: settings.glassCornerRadius, p: p))
            // Floating window: a soft usage-colored halo around the card (calm clay normally,
            // warming as the session climbs) - it reads "alive" against any desktop.
            .shadow(color: floating ? Color(hex: kAccentHex).opacity(0.16 + 0.30 * heat) : .clear,
                    radius: floating ? 16 : 0)
            // Guard against a preference-change render loop: only update when the height really moved.
            .onPreferenceChange(ContentHeightKey.self) { let h = max(80, $0); if abs(h - natH) > 0.5 { natH = h } }
            // Recompute the cost spark only when the record set actually grows (not every render).
            .onChange(of: engine.records.count) { c in if c != sparkKey { sparkKey = c; spark = dailyCostSpark(engine.records) } }
            .onAppear { if sparkKey != engine.records.count { sparkKey = engine.records.count; spark = dailyCostSpark(engine.records) } }
            // Floating window actions live in a right-click menu (no overlaid pin button: the card is
            // reorderable, so any fixed corner would collide with whatever section sits there).
            .contextMenu {
                if floating {
                    Button(settings.pinnedOnTop ? "Unpin from top" : "Pin on top") { settings.pinnedOnTop.toggle() }
                    Button("Refresh now") { onRefresh() }
                    Divider()
                    Button("Settings…") { onSettings() }
                    Button("Hide floating window") { onHideFloating() }
                }
            }
    }
}
