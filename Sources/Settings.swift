import Foundation
import Combine

enum MenuBarShow: String, CaseIterable, Identifiable {
    case session, weekly, both
    var id: String { rawValue }
    var label: String { self == .session ? "Session" : self == .weekly ? "Weekly" : "Both" }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { self == .system ? "System" : self == .light ? "Light" : "Dark" }
}

enum ColorMode: String, CaseIterable, Identifiable {
    case level      // accent that shifts toward red as you near the cap (default)
    case flat       // the accent color, fixed
    case system     // no color,system menu-bar tint (template) + neutral popover
    var id: String { rawValue }
    var label: String { self == .level ? "Adaptive" : self == .flat ? "Solid" : "None" }
}

// A whole-app color scheme. Recolors the popover, widget, settings, floating window, etc.
// (The accent color stays separately adjustable.)
enum PalettePreset: String, CaseIterable, Identifiable {
    case stoneClay, clayLedger, graphiteSlate, paperWhite, sageLinen, midnightInk, blushPastel,
         monoSlate, electricPlum, harvestAmber, tealMist, carbonLime, porcelainIndigo,
         rosewood, forestNight, oceanDeep, sandstone, plumDusk, espresso, arcticBlue, honeyOat
    var id: String { rawValue }
    var label: String {
        switch self {
        case .stoneClay:       return "Stone & Clay"
        case .clayLedger:      return "Clay Ledger"
        case .graphiteSlate:   return "Graphite Slate"
        case .paperWhite:      return "Paper White"
        case .sageLinen:       return "Sage Linen"
        case .midnightInk:     return "Midnight Ink"
        case .blushPastel:     return "Blush Pastel"
        case .monoSlate:       return "Mono Slate"
        case .electricPlum:    return "Electric Plum"
        case .harvestAmber:    return "Harvest Amber"
        case .tealMist:        return "Teal Mist"
        case .carbonLime:      return "Carbon Lime"
        case .porcelainIndigo: return "Porcelain Indigo"
        case .rosewood:        return "Rosewood"
        case .forestNight:     return "Forest Night"
        case .oceanDeep:       return "Ocean Deep"
        case .sandstone:       return "Sandstone"
        case .plumDusk:        return "Plum Dusk"
        case .espresso:        return "Espresso"
        case .arcticBlue:      return "Arctic Blue"
        case .honeyOat:        return "Honey Oat"
        }
    }
}

let kDefaultAccent = "D97757"   // Claude brand orange
let kLiveGreen = "43B97F"       // the LIVE indicator is always this friendly green (online/recording feel)

// The one trust sentence, used verbatim on every surface that mentions privacy: the
// popover signed-out footnote, the Account footer, and the About privacy line. The chmod detail
// lives in exactly ONE place, the About privacy-line tooltip; it appears in no user-facing copy.
let kTrustSentence = "Everything stays on this Mac. Never synced, never uploaded."

// Ember Line styles: eight edge-meter treatments, Ember Line the default.
enum EmberLineStyle: String, CaseIterable, Identifiable {
    case emberLine, filament, segmented, comet, taper, pulseBeads, sparkFront, minimalNode
    var id: String { rawValue }
    var label: String {
        switch self {
        case .emberLine:  return "Ember Line"
        case .filament:   return "Filament"
        case .segmented:  return "Segmented"
        case .comet:      return "Comet"
        case .taper:      return "Taper"
        case .pulseBeads: return "Pulse Beads"
        case .sparkFront: return "Spark Front"
        case .minimalNode: return "Minimal Node"
        }
    }
}

// Ember Line adjust: thickness, spark liveliness, and which displays carry it.
enum TideThickness: String, CaseIterable, Identifiable {
    case hairline, standard, bold
    var id: String { rawValue }
    var label: String { switch self { case .hairline: return "Hairline"; case .standard: return "Standard"; case .bold: return "Bold" } }
    var points: CGFloat { switch self { case .hairline: return 1.5; case .standard: return 2.5; case .bold: return 3.5 } }
}
enum TideSparks: String, CaseIterable, Identifiable {
    case off, calm, lively
    var id: String { rawValue }
    var label: String { switch self { case .off: return "Off"; case .calm: return "Calm"; case .lively: return "Lively" } }
    var rate: Double { switch self { case .off: return 0; case .calm: return 1; case .lively: return 2.2 } }
}
enum TideDisplays: String, CaseIterable, Identifiable {
    case all, main, claude
    var id: String { rawValue }
    var label: String { switch self { case .all: return "All"; case .main: return "Main only"; case .claude: return "With Claude" } }
}

// Menu-bar number format: the percentage sign, bare number, or S/W-labeled.
enum MenuNumberFormat: String, CaseIterable, Identifiable {
    case sign, bare, labeled
    var id: String { rawValue }
    var label: String { switch self { case .sign: return "46%"; case .bare: return "46"; case .labeled: return "S46 W13" } }
}

// FLAME ADJUST: a deliberate deviation from the original spark policy. "Redline" is that
// original behaviour, sparks only at the redline tier. "Always" and the smoke toggle exist
// because at the idle tier the original draws a ~5x7pt flame with no sparks and no smoke, which
// is unreadable on a real menu bar. Standard size + Redline sparks + smoke off reproduces the
// original exactly.
enum FlameSparks: String, CaseIterable, Identifiable {
    case off, redline, always
    var id: String { rawValue }
    var label: String { switch self { case .off: return "Off"; case .redline: return "Redline"; case .always: return "Always" } }
}

// BEACON: what actually winks. The spread runs from "the whole readout changes colour" to marks so
// quiet you only catch them if you happen to be looking at the icon - which is the interesting end.
enum BeaconMark: String, CaseIterable, Identifiable {
    case percent, sign, dot, pip, underline, dotOnly, ringOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .percent:   return "Percent"
        case .sign:      return "% sign only"
        case .dot:       return "Trailing dot"
        case .pip:       return "Corner pip"
        case .underline: return "Underline"
        case .dotOnly:   return "Dot only"
        case .ringOnly:  return "Ring only"
        }
    }
    var blurb: String {
        switch self {
        case .percent:   return "The whole number changes colour. The loudest."
        case .sign:      return "Only the % sign winks; the digits never move. Very quiet."
        case .dot:       return "A small dot after the number lights up. The number stays put."
        case .pip:       return "A 2pt pip above the last digit. Peripheral-vision only."
        case .underline: return "A hairline under the number sweeps in and out."
        case .dotOnly:   return "No number at all - just a dot that breathes. The minimal one."
        case .ringOnly:  return "No number - a hollow ring that fills to your usage as it winks."
        }
    }
    /// Marks that draw no digits, so the glyph is a fixed-size dot instead of text.
    var isBare: Bool { self == .dotOnly || self == .ringOnly }
}

// BEACON: the shape of the wink over time.
// Named Beacon tunes. Each is the whole panel in one line, so a look you liked is one click away
// instead of seven sliders remembered by hand. Applying one writes the real settings - nothing is
// locked afterwards, so a preset is a starting point you can immediately drift away from.
enum BeaconPreset: String, CaseIterable, Identifiable {
    case vitals, blink, whisper, signal, breath
    var id: String { rawValue }
    var label: String {
        switch self {
        case .vitals:  return "Vitals"
        case .blink:   return "Blink (original)"
        case .whisper: return "Whisper"
        case .signal:  return "Signal"
        case .breath:  return "Breath"
        }
    }
    var blurb: String {
        switch self {
        case .vitals:  return "A bare dot pulsing about once a second at a third strength. No number, no rhythm to learn - it just looks alive."
        case .blink:   return "The shipped default: the whole percentage snaps to your accent every 3-5s."
        case .whisper: return "A dot breathing every 9s at a quarter strength. The quietest thing that still says running."
        case .signal:  return "A double heartbeat on the percentage every 5s, full strength, with a glow. Meant to be noticed."
        case .breath:  return "The % sign alone, swelling and fading over a second every 6s. The digits never move."
        }
    }
    /// (every, jitter, length, strength, glow, mark, curve)
    var values: (Double, Double, Double, Double, Double, BeaconMark, BeaconCurve) {
        switch self {
        case .vitals:  return (1.39, 0.00, 0.20, 0.35, 0.00, .dotOnly, .pulse)
        case .blink:   return (4.00, 0.50, 0.42, 1.00, 0.00, .percent, .snap)
        case .whisper: return (9.00, 0.35, 0.90, 0.25, 0.00, .dotOnly, .pulse)
        case .signal:  return (5.00, 0.30, 0.55, 1.00, 0.60, .percent, .beat)
        case .breath:  return (6.00, 0.40, 1.10, 0.55, 0.15, .sign,    .pulse)
        }
    }
}

enum BeaconCurve: String, CaseIterable, Identifiable {
    case snap, pulse, fade, beat
    var id: String { rawValue }
    var label: String {
        switch self {
        case .snap:  return "Snap"
        case .pulse: return "Pulse"
        case .fade:  return "Fade"
        case .beat:  return "Heartbeat"
        }
    }
    var blurb: String {
        switch self {
        case .snap:  return "On instantly, hold, ease off. Reads as a blink."
        case .pulse: return "Smooth in and out, no hold. Reads as a breath."
        case .fade:  return "Instant on, slow decay. Reads as a spark landing."
        case .beat:  return "Two quick blinks, like a pulse. The most alive."
        }
    }
}

// Harvested chat titles are long; how the popover / Insights truncate them.
enum ChatTruncation: String, CaseIterable, Identifiable {
    case middle, end, full
    var id: String { rawValue }
    var label: String { switch self { case .middle: return "Middle"; case .end: return "End"; case .full: return "Full on hover" } }
}

// Frosted-glass material options for the popover / floating window backings.
enum GlassMaterial: String, CaseIterable, Identifiable {
    case popover, menu, hud, sidebar, fullScreen, underWindow
    var id: String { rawValue }
    var label: String {
        switch self {
        case .popover:     return "Popover"
        case .menu:        return "Menu"
        case .hud:         return "HUD"
        case .sidebar:     return "Sidebar"
        case .fullScreen:  return "Full screen"
        case .underWindow: return "Under window"
        }
    }
}

// Tint laid over the clear Liquid Glass: none keeps it fully clear, theme/accent add a colored
// scrim that both tints the glass and improves text contrast over busy desktops.
enum GlassTint: String, CaseIterable, Identifiable {
    case none, theme, accent
    var id: String { rawValue }
    var label: String {
        switch self { case .none: return "None"; case .theme: return "Theme"; case .accent: return "Accent" }
    }
}

// The window/card background treatment. Liquid = real macOS 26 NSGlassEffectView (refraction);
// Frosted = NSVisualEffectView blur; Clear = no material, just the tint scrim over the desktop.
enum GlassStyle: String, CaseIterable, Identifiable {
    case liquid, frosted, clear
    var id: String { rawValue }
    var label: String {
        switch self { case .liquid: return "Liquid Glass"; case .frosted: return "Frosted"; case .clear: return "Clear" }
    }
}

// How numbers animate when they change (session %, cost, tokens, etc.; not the chart).
enum NumberStyle: String, CaseIterable, Identifiable {
    case none, roll, fade, scale, pop, bounce, slideUp, slideDown, push, blur, flip, zoom, counter
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"; case .roll: return "Roll"; case .fade: return "Fade"
        case .scale: return "Scale"; case .pop: return "Pop"; case .bounce: return "Bounce"
        case .slideUp: return "Slide up"; case .slideDown: return "Slide down"; case .push: return "Push"
        case .blur: return "Blur"; case .flip: return "Flip"; case .zoom: return "Zoom"; case .counter: return "Count"
        }
    }
}

// The LIVE indicator color: follow the palette, the accent, a fixed green, or no special color.
enum LiveColor: String, CaseIterable, Identifiable {
    case theme, accent, green, off
    var id: String { rawValue }
    var label: String {
        switch self { case .theme: return "Theme"; case .accent: return "Accent"; case .green: return "Green"; case .off: return "None" }
    }
}
let kAppName = "Burndown"           // app name (floating window title + About). Tagline: "usage monitor for Claude"
let kAppVersion = "0.9.5"           // bump on release builds; 1.0 is reserved for Developer ID signing + multi-provider
let kMinWindowAlpha = 0.45          // most see-through the windows go at 100% transparency (keeps text legible)

// A curated set: every style earns its place, all keep a small footprint (most are
// tiny / horizontally compact; the spark/equalizer ones stay narrow), none look like
// a laptop battery.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case smolder, burnfront, kiln  // the burning-number family; kiln is archived, see isRetired
    case pulse, pace, burn, roll, bars, signal, ember, flame, inferno, ignite, charred, molten, coals, comet  // live,react to real-time token flow
    case beacon   // native system ink that winks to the accent every few seconds
    case stack, ring, orbit, mini, arc, pie, dual, dot, dial  // static,usage / time at a glance
    case twins, splitArc, halfGauge, coPie, vsplit, heatRows, weeklyClock // BOTH-only,session + weekly

    var id: String { rawValue }

    /// Styles that animate to live token consumption (needle swing, rolling digits,
    /// streaming sparkline / bars). The app drives these at ~30fps while tokens flow.
    var isLive: Bool {
        switch self {
        case .smolder, .burnfront, .kiln, .pulse, .pace, .burn, .roll, .bars, .signal, .ember, .flame, .inferno, .ignite, .charred, .molten, .coals, .comet, .beacon: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .smolder:   return "Hearth (live)"
        case .burnfront: return "Burnfront (live)"
        case .kiln:      return "Kiln (live)"   // archived; hidden from the picker via isRetired
        case .pulse:  return "Pulse (live)"
        case .pace:   return "Pace (live)"
        case .burn:   return "Burn rate (live)"
        case .roll:   return "Roll (live)"
        case .bars:   return "Equalizer (live)"
        case .signal: return "Signal (live)"
        case .ember:  return "Ember (live)"
        case .flame:  return "Flame (live)"
        case .inferno: return "Inferno (live)"
        case .ignite: return "Ignite (live)"
        case .charred: return "Charred (live)"
        case .molten: return "Molten (live)"
        case .coals: return "Coals (live)"
        case .comet:  return "Comet (live)"
        case .beacon: return "Beacon (live)"
        case .stack:  return "Stack"
        case .ring:   return "Ring"
        case .orbit:  return "Orbit"
        case .mini:   return "Minimal"
        case .arc:    return "Arc"
        case .pie:    return "Pie"
        case .dual:   return "Dual bars"
        case .dot:    return "Dot"
        case .dial:   return "Dial"
        case .twins:    return "Twin %"
        case .splitArc: return "Twin arcs"
        case .halfGauge:return "Twin gauge"
        case .coPie:    return "Nested pie"
        case .vsplit:   return "Twin tanks"
        case .heatRows: return "Heat rows"
        case .weeklyClock: return "Weekly clock"
        }
    }

    /// Whether this style renders the secondary metric (time, or weekly in Both).
    var showsSecondary: Bool {
        switch self { case .stack, .ring, .orbit, .dual: return true; default: return false }
    }

    /// Live styles that ALSO grow a weekly element in Both (a second row / bar).
    var liveBoth: Bool {
        // Every live style that draws the weekly bar in "Both" mode must be listed here, or the
        // Settings picker filters it out when menuBarShow == .both. The burning-number styles
        // (Hearth/Burnfront/Kiln) render the weekly bar too, so they belong here alongside Flame.
        switch self {
        case .pulse, .bars, .signal, .smolder, .burnfront, .kiln, .flame, .inferno, .ignite, .charred, .molten, .coals, .beacon: return true
        default: return false
        }
    }

    /// Fire styles that stay gently alive even when no tokens flow - the app keeps the
    /// 30fps animator running for these so the fire never freezes.
    var burnsIdle: Bool {
        // The fire family's IDLE CONTRACT: every fire style must show visible motion within
        // any 10s window at idle. If a style is missing here the animator parks once things settle and
        // the glyph freezes on screen - which is exactly what happened to Hearth/Burnfront/Kiln.
        switch self {
        // Beacon is not fire, but it lives by the same contract: its wink is on a 3-5s timer, so the
        // animator must keep ticking at idle or the glyph parks and the wink never comes.
        case .smolder, .burnfront, .kiln, .flame, .inferno, .ignite, .charred, .molten, .coals, .beacon: return true
        default: return false
        }
    }

    /// Styles built to show session + weekly at once,only valid in "Both".
    var bothOnly: Bool {
        switch self { case .twins, .splitArc, .halfGauge, .coPie, .vsplit, .heatRows, .weeklyClock: return true; default: return false }
    }

    /// Family grouping for the style picker (Live / Static gauge / Static text / Both-only).
    enum Family: String, CaseIterable, Identifiable { case live = "Live", gauge = "Static gauge", text = "Static text", both = "Both-only"; var id: String { rawValue } }
    var family: Family {
        if bothOnly { return .both }
        if isLive { return .live }
        switch self { case .stack, .mini: return .text; default: return .gauge }
    }
    /// The curated core set the design surfaces first: one strong, legible template per family.
    /// Beacon joined 2026-07-31 (it became the daily driver); nothing was demoted to make room.
    var isCore: Bool {
        switch self { case .smolder, .burnfront, .flame, .pulse, .pace, .beacon, .ring, .arc, .stack: return true; default: return false }
    }
    /// Fire styles retired or archived (Kiln archived, and the six v1 styles migrated onto the
    /// canonical set); hidden from the picker.
    var isRetired: Bool {
        switch self { case .kiln, .inferno, .ignite, .charred, .molten, .coals: return true; default: return false }
    }

    /// "Both" needs a style that shows two metrics at once; Session/Weekly each show a
    /// single value (so the both-only twin styles are hidden there).
    func supports(_ show: MenuBarShow) -> Bool {
        if bothOnly { return show == .both }
        return show == .both ? (showsSecondary || liveBoth) : true
    }

    func desc(_ show: MenuBarShow) -> String {
        let second = show == .both ? "weekly %" : "time left"
        switch self {
        case .smolder:   return "Charcoal-warm digits lit from the coals, breathing. The calm default."
        case .burnfront: return "The number burns left to right. The seam is your usage."
        case .kiln:      return "Heat convects inside the digits. Faster as you burn."
        case .pulse:  return show == .both
            ? "The % over a live burn spark, with a slim weekly bar beneath. Tall, never wide."
            : "The % with a live burn-rate spark stacked underneath. Tall, never wide."
        case .pace:   return "A compact digital gauge: your % inside an arc that revs with your live token rate."
        case .burn:   return "A live burn-rate sparkline over the last ~40s, beside the %."
        case .roll:   return "The % beside a token count that rolls upward in real time as you work."
        case .bars:   return show == .both
            ? "A live burn equalizer with a slim weekly bar beneath. Tiny."
            : "A live equalizer: five bars dancing to your recent burn rate. Tiny, no text."
        case .signal: return show == .both
            ? "Signal-strength burn bars with a slim weekly bar beneath. Tiny."
            : "Signal-strength bars that light up as your token rate climbs. Tiny, no text."
        case .ember:  return "A glowing ember beside the % that brightens and swells as tokens flow."
        case .flame:  return "A live flame beside the %: it grows and turns white-hot as you burn faster, throws sparks, and rages toward the limit. Burndown's signature."
        case .inferno: return "The % itself cast in living fire: molten color flows upward through the numerals, faster and hotter as you burn."
        case .ignite: return "The numerals ARE the fire: flame tongues lick off the top of the digits, sparks pop, and the whole number rages as burn climbs. The showpiece."
        case .charred: return "The number burns up from below as the session fills: charred black under a crawling ember line, unburned above. Your usage is how much has burned."
        case .molten: return "Liquid fire flows upward inside the numerals - a slow smolder at idle, rushing molten rock under heavy burn, with crisp edges always."
        case .coals: return "The numerals glow like banked coals: breathing embers, drifting sparks, calm and warm until the burn picks up."
        case .comet:  return "A comet whose tail streaks longer and brighter the faster you burn, beside the %."
        case .beacon: return show == .both
            ? "The % in the menu bar's own ink, winking to your accent color for a fraction of a second every few seconds, with a slim weekly bar beneath."
            : "The % in the menu bar's own ink, indistinguishable from a system icon, winking to your accent color for a fraction of a second every few seconds."
        case .stack:  return show == .both
            ? "Session % over weekly %, stacked: session larger, weekly beneath."
            : "Two stacked lines: usage over time left. Just text-width wide."
        case .ring:   return "A \(second) ring with the % inside it. Tiniest."
        case .orbit:  return "Two nested rings: usage outside, \(second) inside."
        case .mini:   return "Just the %."
        case .arc:    return "A half-circle gauge filled to your usage, plus the %."
        case .pie:    return "A filled pie that grows as usage rises. Tiniest, no text."
        case .dual:   return "Two slim bars side by side: usage and \(second)."
        case .dot:    return "A status dot colored by level, beside the %."
        case .dial:   return "A round dial whose needle points to your usage, plus the %."
        case .twins:    return "Session % big with weekly % beneath, aligned and color-coded."
        case .splitArc: return "Two nested arc gauges: session outside, weekly inside."
        case .halfGauge:return "A twin gauge: session fills in from the left, weekly from the right."
        case .coPie:    return "Nested pie: session as the outer ring, weekly as the inner wedge."
        case .vsplit:   return "Two side-by-side tanks: session left, weekly right."
        case .heatRows: return "Two 8-cell rows that light up: session on top, weekly below."
        case .weeklyClock: return "Session % beside the weekly reset countdown (e.g. ‘3d 4h’)."
        }
    }
}

// The popover monitoring chart,all selectable live from Settings. (Plots the live
// token burn rate; no dollar figures here,cost lives once, honestly framed, in the
// Session block.)
// The visual treatment of the popover monitor chart (applies to both Burn and Usage modes).
// Only styles the chart bodies actually implement are offered: the old Bars and Zones
// options were selectable no-ops, and their legacy values migrate to Area in init.
enum ChartStyle: String, CaseIterable, Identifiable {
    case area, hairline, gradient, minimal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .area:     return "Area"
        case .hairline: return "Hairline"
        case .gradient: return "Gradient"
        case .minimal:  return "Minimal"
        }
    }
    var blurb: String {
        switch self {
        case .area:     return "Filled area under a clean line. The classic look."
        case .hairline: return "A thin crisp line over a whisper of fill."
        case .gradient: return "A soft top-down gradient fill capped by a line."
        case .minimal:  return "Just the line, no axes. Calm and tiny."
        }
    }
}

// Which series the popover monitor chart shows (toggle lives in the chart header).
// The chart catalogue lives in ChartKinds.swift (enum ChartKind, twenty-four selectable views).


// The popover's stackable modules. The "Claude … usage" header, Session block, monitor
// Chart, and This-week block can each be reordered and shown/hidden; the app-name footer
// is always pinned at the bottom (not a CardSection).
enum CardSection: String, CaseIterable, Identifiable {
    // Default order: the two constraints (session + week) read as a pair, then the chart as evidence.
    case header, session, week, chart
    var id: String { rawValue }
    var label: String {
        switch self {
        case .header:  return "Title + LIVE"
        case .session: return "Session"
        case .chart:   return "Chart"
        case .week:    return "This week"
        }
    }
}

// How long the monitor chart looks back (adjustable). Retention in LiveActivity is sized
// to the largest option (with tiered decimation for the long ranges) so changing this
// never loses history. `.all` means the entire retained history.
enum ChartSpan: String, CaseIterable, Identifiable {
    case m30, h1, h2, h4, h6, h12, h24, w1, mo1, all
    var id: String { rawValue }
    var seconds: TimeInterval {
        switch self {
        case .m30: return 1800;   case .h1: return 3600;    case .h2: return 7200
        case .h4: return 14400;   case .h6: return 21600;   case .h12: return 43200
        case .h24: return 86400;  case .w1: return 604800;  case .mo1: return 2592000
        case .all: return 3.15e9   // sentinel: clamp to the earliest retained sample
        }
    }
    var label: String {
        switch self {
        case .m30: return "30m"; case .h1: return "1h";  case .h2: return "2h";  case .h4: return "4h"
        case .h6: return "6h";   case .h12: return "12h"; case .h24: return "24h"
        case .w1: return "1 week"; case .mo1: return "1 month"; case .all: return "All time"
        }
    }
    var isAllTime: Bool { self == .all }
    // Compact label for a segmented control (all options visible at once).
    var tiny: String {
        switch self {
        case .m30: return "30m"; case .h1: return "1h"; case .h2: return "2h"; case .h4: return "4h"
        case .h6: return "6h"; case .h12: return "12h"; case .h24: return "24h"
        case .w1: return "1w"; case .mo1: return "1mo"; case .all: return "All"
        }
    }
    // The options offered for each chart: burn is a live rate (cap at 24h); usage is a
    // slow % curve worth seeing over long windows.
    // Both burn and usage now offer the same full set of windows (30m … all time).
    static let burnOptions: [ChartSpan]  = allCases
    static let usageOptions: [ChartSpan] = allCases
}

// Dock a small usage widget to an edge of the Claude Desktop window (it follows the
// window and shows only while Claude Desktop is frontmost). Off by default.
// Top/Bottom render a slim horizontal bar; Left/Right render a vertical card.
enum DockEdge: String, CaseIterable, Identifiable {
    case off, top, bottom, left, right
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Off"; case .top: return "Top"; case .bottom: return "Bottom"
        case .left: return "Left"; case .right: return "Right"
        }
    }
    var horizontal: Bool { self == .top || self == .bottom }
}

final class AppSettings: ObservableObject {
    private let d: UserDefaults

    @Published var usageAPI: Bool { didSet { d.set(usageAPI, forKey: "usageAPI") } }   // opt-in: call Claude's OAuth usage API
    /// Consent to borrow Claude Code's existing sign-in (the CLI credential in the Keychain).
    /// Fresh installs must opt in explicitly, so installing Burndown never silently reads
    /// another app's login. Sign-out revokes it.
    @Published var borrowCLI: Bool { didSet { d.set(borrowCLI, forKey: "borrowCLI"); UsageEngine.cliBootstrapAllowed = borrowCLI } }
    /// First-run welcome tour: shown once on a fresh install.
    @Published var onboarded: Bool { didSet { d.set(onboarded, forKey: "onboarded") } }
    /// Plain-English caption under each popover section. On until dismissed.
    @Published var popoverExplain: Bool { didSet { d.set(popoverExplain, forKey: "popoverExplain") } }
    @Published var refreshSeconds: Int { didSet { d.set(refreshSeconds, forKey: "refreshSeconds") } }
    @Published var menuBarStyle: MenuBarStyle { didSet { d.set(menuBarStyle.rawValue, forKey: "menuBarStyle") } }
    @Published var menuBarShow: MenuBarShow { didSet { d.set(menuBarShow.rawValue, forKey: "menuBarShow") } }
    @Published var showWeekly: Bool { didSet { d.set(showWeekly, forKey: "showWeekly") } }
    @Published var showCost: Bool { didSet { d.set(showCost, forKey: "showCost") } }
    @Published var showTokens: Bool { didSet { d.set(showTokens, forKey: "showTokens") } }
    @Published var colorMode: ColorMode { didSet { d.set(colorMode.rawValue, forKey: "colorMode") } }
    /// Draw the menu bar's NUMBER in the system's own label colour rather than the usage colour.
    ///
    /// On by default. The menu bar is a row of system-tinted glyphs that flip black or white to
    /// suit whatever is behind them; a themed number is the one item that can end up fighting its
    /// background. The dot, arc and glow keep the colour, because that is what makes them readable
    /// as a gauge at a glance.
    @Published var menuBarSystemNumber: Bool { didSet { d.set(menuBarSystemNumber, forKey: "menuBarSystemNumber") } }
    @Published var accentHex: String { didSet { d.set(accentHex, forKey: "accentHex") } }
    @Published var theme: AppTheme { didSet { d.set(theme.rawValue, forKey: "theme") } }
    @Published var chartStyle: ChartStyle { didSet { d.set(chartStyle.rawValue, forKey: "chartStyle") } }
    @Published var smartRefresh: Bool { didSet { d.set(smartRefresh, forKey: "smartRefresh") } }
    @Published var floatingShown: Bool { didSet { d.set(floatingShown, forKey: "floatingShown") } }
    @Published var pinnedOnTop: Bool { didSet { d.set(pinnedOnTop, forKey: "pinnedOnTop") } }
    @Published var chartKind: ChartKind { didSet { d.set(chartKind.rawValue, forKey: "chartKind") } }
    /// The charts the popover shows, in order. Persisted as a CSV of ChartKind raw values; `chartKind`
    /// mirrors the first entry so older readers and QA hooks keep working.
    @Published var chartKinds: [ChartKind] {
        didSet {
            d.set(chartKinds.map(\.rawValue).joined(separator: ","), forKey: "chartKinds")
            if let first = chartKinds.first, first != chartKind { chartKind = first }
        }
    }
    /// Span for the day-scale charts (cost per day, hour profile, heatmap), in days.
    @Published var chartDays: Int { didSet { d.set(chartDays, forKey: "chartDays") } }
    /// Hover/scrub readout on the charts.
    @Published var chartHover: Bool { didSet { d.set(chartHover, forKey: "chartHover") } }
    @Published var dockEdge: DockEdge { didSet { d.set(dockEdge.rawValue, forKey: "dockEdge") } }
    @Published var tideLine: Bool { didSet { d.set(tideLine, forKey: "tideLine") } }   // screen-edge remaining-budget filament
    @Published var tideEdge: DockEdge { didSet { d.set(tideEdge.rawValue, forKey: "tideEdge") } }   // which screen edge the tide line hugs
    @Published var tideStyle: EmberLineStyle { didSet { d.set(tideStyle.rawValue, forKey: "tideStyle") } }   // Ember Line style (area 5)
    @Published var tideFlames: Int { didSet { d.set(tideFlames, forKey: "tideFlames") } }   // burn-front flame licks: 0..3
    @Published var tideGlow: Double { didSet { d.set(tideGlow, forKey: "tideGlow") } }       // glow multiplier 0.6..1.4
    @Published var tideThickness: TideThickness { didSet { d.set(tideThickness.rawValue, forKey: "tideThickness") } }
    @Published var tideLength: Double { didSet { d.set(tideLength, forKey: "tideLength") } }        // 0.4..1.0 of the edge
    @Published var tideOpacity: Double { didSet { d.set(tideOpacity, forKey: "tideOpacity") } }     // 0.3..1.0 panel alpha
    @Published var tideSparks: TideSparks { didSet { d.set(tideSparks.rawValue, forKey: "tideSparks") } }
    @Published var tideSmoke: Bool { didSet { d.set(tideSmoke, forKey: "tideSmoke") } }
    @Published var tidePeek: Bool { didSet { d.set(tidePeek, forKey: "tidePeek") } }               // hover readout
    @Published var tideDisplays: TideDisplays { didSet { d.set(tideDisplays.rawValue, forKey: "tideDisplays") } }
    @Published var sectionOrder: [String] { didSet { d.set(sectionOrder, forKey: "sectionOrder") } }
    @Published var sectionsHidden: [String] { didSet { d.set(sectionsHidden, forKey: "sectionsHidden") } }
    @Published var burnSpan: ChartSpan { didSet { d.set(burnSpan.rawValue, forKey: "burnSpan") } }
    // Overall window transparency (1 = opaque, lower = more see-through) and frosted-glass
    // intensity (0 = solid card, 1 = full blur material). Applied to popover, floating, edge.
    @Published var windowOpacity: Double { didSet { d.set(windowOpacity, forKey: "windowOpacity") } }
    // Preview the menu-bar style chips with the user's real live data (default: sample data
    // so the chips always look good, even when idle).
    @Published var chipLivePreview: Bool { didSet { d.set(chipLivePreview, forKey: "chipLivePreview") } }
    // Edge widget placement: inside the window edge vs just outside it, and where along that
    // edge it sits (0 = top/left start, 1 = bottom/right end; 0.5 = centered). Drag also updates it.
    @Published var dockInside: Bool { didSet { d.set(dockInside, forKey: "dockInside") } }
    @Published var edgeOffset: Double { didSet { d.set(edgeOffset, forKey: "edgeOffset") } }   // legacy (fraction); superseded by edgePx
    // Fixed placement along the docked edge: a constant point distance from the anchored corner,
    // so resizing the Claude window never moves the widget. edgePx < 0 means auto-center.
    @Published var edgePx: Double { didSet { d.set(edgePx, forKey: "edgePx") } }
    @Published var edgeFromEnd: Bool { didSet { d.set(edgeFromEnd, forKey: "edgeFromEnd") } }   // anchored to bottom/right vs top/left
    @Published var dockLocked: Bool { didSet { d.set(dockLocked, forKey: "dockLocked") } }   // freeze the widget where the user placed it
    @Published var widgetStyle: WidgetStyle { didSet { d.set(widgetStyle.rawValue, forKey: "widgetStyle") } }
    @Published var widgetScale: Double { didSet { d.set(widgetScale, forKey: "widgetScale") } }   // docked widget size, 0.7…1.8
    @Published var pendingTab: String? = nil   // transient: a settings tab to jump to on open (e.g. from the chart gear)
    @Published var palette: PalettePreset { didSet { d.set(palette.rawValue, forKey: "palette"); Palette.current = palette } }
    // Scales the popover / floating window text and overall size (0.9 to 1.3).
    @Published var textScale: Double { didSet { d.set(textScale, forKey: "textScale") } }
    /// Type size in the Insights window, separate from the popover's zoom: one is a card glanced
    /// at from across the desk, the other a window read up close, and they want different sizes.
    @Published var insightsTextScale: Double { didSet { d.set(insightsTextScale, forKey: "insightsTextScale") } }
    // Corner-grip RESIZE (reflow, not zoom): card width in design points (wider = longer bars and
    // chat names, same font size), and extra plot height added to every popover chart by a
    // vertical drag. Both set by the grip; CardResize holds the limits.
    @Published var cardWidth: Double { didSet { d.set(cardWidth, forKey: "cardWidth") } }
    @Published var cardChartBoost: Double { didSet { d.set(cardChartBoost, forKey: "cardChartBoost") } }
    @Published var floatingChrome: Bool { didSet { d.set(floatingChrome, forKey: "floatingChrome") } }   // show the floating window title bar
    @Published var glassMaterial: GlassMaterial { didSet { d.set(glassMaterial.rawValue, forKey: "glassMaterial") } }
    // ── Glass / background tuning (all stored in display units; CardSurface converts) ──
    @Published var glassStyle: GlassStyle { didSet { d.set(glassStyle.rawValue, forKey: "glassStyle") } }
    @Published var glassOpacity: Double { didSet { d.set(glassOpacity, forKey: "glassOpacity") } }            // 0…100 %
    @Published var glassBlur: Double { didSet { d.set(glassBlur, forKey: "glassBlur") } }                     // 0…40 pt extra blur
    @Published var glassSaturation: Double { didSet { d.set(glassSaturation, forKey: "glassSaturation") } }   // 0…100 % boost
    @Published var glassTintIntensity: Double { didSet { d.set(glassTintIntensity, forKey: "glassTintIntensity") } } // 0…100 %
    @Published var glassBorderOpacity: Double { didSet { d.set(glassBorderOpacity, forKey: "glassBorderOpacity") } } // 0…100 %
    @Published var glassBorderWidth: Double { didSet { d.set(glassBorderWidth, forKey: "glassBorderWidth") } }       // 0…6 pt
    @Published var glassCornerRadius: Double { didSet { d.set(glassCornerRadius, forKey: "glassCornerRadius") } }    // 6…22 pt
    @Published var glassShadow: Double { didSet { d.set(glassShadow, forKey: "glassShadow") } }               // 0…100 %
    @Published var numberStyle: NumberStyle { didSet { d.set(numberStyle.rawValue, forKey: "numberStyle") } }
    // Menu-bar rows.
    @Published var menuNumberFormat: MenuNumberFormat { didSet { d.set(menuNumberFormat.rawValue, forKey: "menuNumberFormat") } }
    @Published var menuTimeToReset: Bool { didSet { d.set(menuTimeToReset, forKey: "menuTimeToReset") } }
    @Published var menuBoldDigits: Bool { didSet { d.set(menuBoldDigits, forKey: "menuBoldDigits") } }   // Semibold vs Regular
    @Published var showDockIcon: Bool { didSet { d.set(showDockIcon, forKey: "showDockIcon") } }   // LSUIElement / activation policy
    @Published var menuShowPct: Bool { didSet { d.set(menuShowPct, forKey: "menuShowPct") } }   // area 2: percentage on/off (Flame -> flame-only)
    @Published var smolderIntensity: Double { didSet { d.set(smolderIntensity, forKey: "smolderIntensity") } }   // x0.75 / x1.0 / x1.25
    @Published var smolderBreathSlow: Bool { didSet { d.set(smolderBreathSlow, forKey: "smolderBreathSlow") } }   // halve tier frequency
    @Published var smolderWarmthWander: Bool { didSet { d.set(smolderWarmthWander, forKey: "smolderWarmthWander") } }   // fixed vs wander
    // FLAME ADJUST: scale the Flame glyph, and choose how alive it is.
    @Published var flameSize: Double { didSet { d.set(flameSize, forKey: "flameSize") } }        // 0.8x ... 2.0x (the menu bar height caps it above that)
    @Published var flameSparks: FlameSparks { didSet { d.set(flameSparks.rawValue, forKey: "flameSparks") } }
    @Published var flameSmoke: Bool { didSet { d.set(flameSmoke, forKey: "flameSmoke") } }
    // BEACON ADJUST: every number in the wink is exposed, with the ranges opened up well past
    // "tasteful" on purpose - the point is to find where it stops being visible, from both ends.
    @Published var beaconEvery: Double { didSet { d.set(beaconEvery, forKey: "beaconEvery") } }        // seconds between winks
    @Published var beaconJitter: Double { didSet { d.set(beaconJitter, forKey: "beaconJitter") } }     // 0…1 randomness on that gap
    @Published var beaconLength: Double { didSet { d.set(beaconLength, forKey: "beaconLength") } }     // seconds the wink lasts
    @Published var beaconStrength: Double { didSet { d.set(beaconStrength, forKey: "beaconStrength") } } // 0…1 how far toward the accent
    @Published var beaconGlow: Double { didSet { d.set(beaconGlow, forKey: "beaconGlow") } }           // 0…1 halo at the peak
    @Published var beaconMark: BeaconMark { didSet { d.set(beaconMark.rawValue, forKey: "beaconMark") } }
    @Published var beaconCurve: BeaconCurve { didSet { d.set(beaconCurve.rawValue, forKey: "beaconCurve") } }
    // The three that make the wink MEAN something rather than just decorate.
    @Published var beaconFollowsBurn: Bool { didSet { d.set(beaconFollowsBurn, forKey: "beaconFollowsBurn") } }  // cadence rides the live rate
    @Published var beaconUsageColor: Bool { didSet { d.set(beaconUsageColor, forKey: "beaconUsageColor") } }     // colour rides usage
    @Published var beaconAlertBeat: Bool { didSet { d.set(beaconAlertBeat, forKey: "beaconAlertBeat") } }        // double-wink near the limit

    /// Which preset the sliders currently sit on, or nil for "Custom". Loose tolerance on purpose:
    /// a preset you nudged by a hair is still that preset as far as the label is concerned.
    var matchingBeaconPreset: BeaconPreset? {
        BeaconPreset.allCases.first { p in
            let v = p.values
            return abs(beaconEvery - v.0) < 0.05 && abs(beaconJitter - v.1) < 0.02
                && abs(beaconLength - v.2) < 0.02 && abs(beaconStrength - v.3) < 0.02
                && abs(beaconGlow - v.4) < 0.02 && beaconMark == v.5 && beaconCurve == v.6
        }
    }

    /// Apply a named tune. Only the seven look knobs - Rhythm / Wink colour / Near the limit are
    /// behaviour choices, not part of a look, so a preset never silently flips them.
    func applyBeaconPreset(_ p: BeaconPreset) {
        let v = p.values
        beaconEvery = v.0; beaconJitter = v.1; beaconLength = v.2
        beaconStrength = v.3; beaconGlow = v.4; beaconMark = v.5; beaconCurve = v.6
    }
    // Per-element popover visibility. Each gates ONE popover element; a hidden element
    // drops and the card content-hugs to a shorter height with no gaps. All default true unless noted.
    @Published var showTimeRing: Bool { didSet { d.set(showTimeRing, forKey: "showTimeRing") } }
    @Published var showForecastLine: Bool { didSet { d.set(showForecastLine, forKey: "showForecastLine") } }
    @Published var showWeekPercent: Bool { didSet { d.set(showWeekPercent, forKey: "showWeekPercent") } }
    @Published var showLast7Days: Bool { didSet { d.set(showLast7Days, forKey: "showLast7Days") } }
    @Published var showWeekResets: Bool { didSet { d.set(showWeekResets, forKey: "showWeekResets") } }
    @Published var showOpusShare: Bool { didSet { d.set(showOpusShare, forKey: "showOpusShare") } }
    @Published var showBurnChart: Bool { didSet { d.set(showBurnChart, forKey: "showBurnChart") } }
    @Published var showCountdownRing: Bool { didSet { d.set(showCountdownRing, forKey: "showCountdownRing") } }
    @Published var showChatsBurning: Bool { didSet { d.set(showChatsBurning, forKey: "showChatsBurning") } }
    @Published var showDeveloperApiLine: Bool { didSet { d.set(showDeveloperApiLine, forKey: "showDeveloperApiLine") } }
    // Collapsible-section memory. The popover tears its content down on close (that's what keeps it at
    // ~0% CPU while hidden), so @State cannot survive a close - these live here and persist, letting a
    // section reopen the way the user last left it. (Legacy key kept so an existing choice carries over.)
    @Published var chatsExpanded: Bool { didSet { d.set(chatsExpanded, forKey: "chatsExpandedByDefault") } }
    @Published var modelsExpanded: Bool { didSet { d.set(modelsExpanded, forKey: "modelsExpanded") } }
    @Published var chatTruncation: ChatTruncation { didSet { d.set(chatTruncation.rawValue, forKey: "chatTruncation") } }
    /// Series hidden on the "Session + week %" chart, by name ("Session", "Week", or a model).
    /// Persisted for the same reason chatsExpanded is: the popover tears its content down on
    /// close, so a @State toggle would forget the choice every single time the card is opened.
    @Published var hiddenUsageSeries: [String] { didSet { d.set(hiddenUsageSeries, forKey: "hiddenUsageSeries") } }
    // Popover chrome switches (the CHROME card in Settings).
    @Published var popoverDividers: Bool { didSet { d.set(popoverDividers, forKey: "popoverDividers") } }
    @Published var popoverEyebrows: Bool { didSet { d.set(popoverEyebrows, forKey: "popoverEyebrows") } }
    @Published var popoverCompact: Bool { didSet { d.set(popoverCompact, forKey: "popoverCompact") } }
    @Published var liveColor: LiveColor { didSet { d.set(liveColor.rawValue, forKey: "liveColor") } }
    @Published var alertsEnabled: Bool { didSet { d.set(alertsEnabled, forKey: "alertsEnabled") } }   // master
    @Published var alertThreshold: Double { didSet { d.set(alertThreshold, forKey: "alertThreshold") } }   // legacy session level
    @Published var alertSession: Bool { didSet { d.set(alertSession, forKey: "alertSession") } }
    @Published var alertSessionAt: Double { didSet { d.set(alertSessionAt, forKey: "alertSessionAt") } }   // 0…1
    @Published var alertWeekly: Bool { didSet { d.set(alertWeekly, forKey: "alertWeekly") } }
    @Published var alertWeeklyAt: Double { didSet { d.set(alertWeeklyAt, forKey: "alertWeeklyAt") } }       // 0…1
    @Published var alertBurn: Bool { didSet { d.set(alertBurn, forKey: "alertBurn") } }
    @Published var alertBurnAt: Double { didSet { d.set(alertBurnAt, forKey: "alertBurnAt") } }             // tokens/min
    @Published var alertOnReset: Bool { didSet { d.set(alertOnReset, forKey: "alertOnReset") } }            // notify when a window resets
    @Published var alertSound: Bool { didSet { d.set(alertSound, forKey: "alertSound") } }
    @Published var alertRepeatMin: Double { didSet { d.set(alertRepeatMin, forKey: "alertRepeatMin") } }    // 0 = once/cycle, else re-alert every N min while over
    @Published var alertOpus: Bool { didSet { d.set(alertOpus, forKey: "alertOpus") } }
    @Published var alertOpusAt: Double { didSet { d.set(alertOpusAt, forKey: "alertOpusAt") } }
    @Published var alertSonnet: Bool { didSet { d.set(alertSonnet, forKey: "alertSonnet") } }
    @Published var alertSonnetAt: Double { didSet { d.set(alertSonnetAt, forKey: "alertSonnetAt") } }
    @Published var alertForecast: Bool { didSet { d.set(alertForecast, forKey: "alertForecast") } }
    @Published var alertForecastMin: Double { didSet { d.set(alertForecastMin, forKey: "alertForecastMin") } }   // alert when ≤ this many minutes to the session limit
    /// Daily background update check (the check itself is a version lookup; nothing is sent).
    @Published var autoUpdateCheck: Bool { didSet { d.set(autoUpdateCheck, forKey: "autoUpdateCheck") } }
    @Published var alertSoundName: String { didSet { d.set(alertSoundName, forKey: "alertSoundName") } }          // "" = system default
    // Alert sound choices. "" = the macOS default notification sound; the rest are Burndown's own
    // original chimes (Sounds/, generated by make_sounds.py), bundled in Resources. Fully
    // redistributable: no Apple audio ships in the app.
    static let soundOptions: [(String, String)] = [("Default", ""), ("Ember", "Ember"), ("Chime", "Chime"),
                                                   ("Drop", "Drop"), ("Pulse", "Pulse"), ("Bloom", "Bloom"), ("Knock", "Knock")]
    @Published var quietHours: Bool { didSet { d.set(quietHours, forKey: "quietHours") } }
    @Published var quietFrom: Double { didSet { d.set(quietFrom, forKey: "quietFrom") } }   // hour 0…23
    @Published var quietTo: Double { didSet { d.set(quietTo, forKey: "quietTo") } }          // hour 0…23
    @Published var glassTint: GlassTint { didSet { d.set(glassTint.rawValue, forKey: "glassTint") } }
    // ── Self-imposed spend budget + the two newer alert toggles ──
    @Published var budgetEnabled: Bool { didSet { d.set(budgetEnabled, forKey: "budgetEnabled") } }
    @Published var budgetMetric: String { didSet { d.set(budgetMetric, forKey: "budgetMetric") } }   // "usd" or "tokens"
    @Published var budgetPeriod: String { didSet { d.set(budgetPeriod, forKey: "budgetPeriod") } }   // "day" or "week"
    @Published var budgetLimit: Double { didSet { d.set(budgetLimit, forKey: "budgetLimit") } }       // dollars or tokens
    @Published var alertBudget: Bool { didSet { d.set(alertBudget, forKey: "alertBudget") } }
    @Published var alertRunaway: Bool { didSet { d.set(alertRunaway, forKey: "alertRunaway") } }
    // Notification moment 4: the weekly digest is OPT-IN and posts once on a Monday.
    @Published var weeklyDigest: Bool { didSet { d.set(weeklyDigest, forKey: "weeklyDigest") } }

    // Order + visibility of the popover modules (header/session/chart/week).
    func visibleSections() -> [CardSection] {
        sectionOrder.compactMap { CardSection(rawValue: $0) }.filter { !sectionsHidden.contains($0.rawValue) }
    }
    func isHidden(_ s: CardSection) -> Bool { sectionsHidden.contains(s.rawValue) }
    func toggleHidden(_ s: CardSection) {
        if let i = sectionsHidden.firstIndex(of: s.rawValue) { sectionsHidden.remove(at: i) } else { sectionsHidden.append(s.rawValue) }
    }
    func moveSection(_ s: CardSection, up: Bool) {
        guard let i = sectionOrder.firstIndex(of: s.rawValue) else { return }
        let j = up ? i - 1 : i + 1
        guard j >= 0, j < sectionOrder.count else { return }
        sectionOrder.swapAt(i, j)
    }

    /// Are alert quiet-hours muting right now? (mirrors Alerts.quietNow.)
    func quietHoursActive(_ now: Date = Date()) -> Bool {
        guard quietHours else { return false }
        let h = Calendar.current.component(.hour, from: now)
        let from = Int(quietFrom), to = Int(quietTo)
        if from == to { return false }
        return from < to ? (h >= from && h < to) : (h >= from || h < to)
    }
    /// The hour quiet-hours ends, formatted like "8 AM".
    var quietUntilString: String {
        let h = Int(quietTo) % 24, ampm = h < 12 ? "AM" : "PM", h12 = h % 12 == 0 ? 12 : h % 12
        return "\(h12) \(ampm)"
    }

    // `defaults` is UserDefaults.standard in the app; the QA snapshot harness passes a
    // throwaway suite so renders never mutate the user's real settings.
    init(defaults: UserDefaults = .standard) {
        d = defaults
        theme = AppTheme(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        // Opt-in gate for the OAuth usage API. Existing installs (a live.json cache already exists) keep it
        // on so nothing breaks; a brand-new / freshly distributed install starts off so the app never calls
        // Claude's usage endpoint with your token until you explicitly turn it on.
        if d.object(forKey: "usageAPI") == nil {
            let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/burndown/live.json")
            let existingInstall = FileManager.default.fileExists(atPath: cache.path)
            usageAPI = existingInstall
            d.set(existingInstall, forKey: "usageAPI")
        } else {
            usageAPI = d.bool(forKey: "usageAPI")
        }
        // Borrow-consent + onboarding migrations: an install that already has a private token (it has
        // been running on the bootstrapped or in-app sign-in) keeps working and skips the tour; a
        // brand-new install gets the tour and must consent before the CLI credential is ever read.
        let tokenFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/burndown/token.json")
        let liveFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/burndown/live.json")
        let establishedInstall = FileManager.default.fileExists(atPath: tokenFile.path)
            || FileManager.default.fileExists(atPath: liveFile.path)
        if d.object(forKey: "borrowCLI") == nil {
            borrowCLI = establishedInstall
            d.set(establishedInstall, forKey: "borrowCLI")
        } else {
            borrowCLI = d.bool(forKey: "borrowCLI")
        }
        if d.object(forKey: "onboarded") == nil {
            onboarded = establishedInstall
            d.set(establishedInstall, forKey: "onboarded")
        } else {
            onboarded = d.bool(forKey: "onboarded")
        }
        popoverExplain = (d.object(forKey: "popoverExplain") as? Bool) ?? true
        refreshSeconds = (d.object(forKey: "refreshSeconds") as? Int) ?? 60   // 60s recommended (rate-limit friendly)
        // Burning numbers are the product's identity, so the DEFAULT menu-bar style is a fire style
        // (Hearth). Fire v2 migration: retire v1's styles onto the canonical set.
        var mbs = MenuBarStyle(rawValue: d.string(forKey: "menuBarStyle") ?? "") ?? .smolder
        switch mbs {
        case .inferno, .coals, .molten, .ignite, .kiln: mbs = .smolder   // Kiln archived -> Hearth
        case .charred:                                  mbs = .burnfront
        default: break
        }
        // One-time move off the old plain "pulse" default onto the burning-number identity, so the
        // fire actually shows. Runs once (guarded by a flag) and never overrides a later user choice.
        if d.object(forKey: "fireDefaultMigrated") == nil {
            d.set(true, forKey: "fireDefaultMigrated")
            if mbs == .pulse { mbs = .smolder }
        }
        menuBarStyle = mbs
        menuBarShow = MenuBarShow(rawValue: d.string(forKey: "menuBarShow") ?? "") ?? .session
        showWeekly = (d.object(forKey: "showWeekly") as? Bool) ?? true
        showCost = (d.object(forKey: "showCost") as? Bool) ?? true
        showTokens = (d.object(forKey: "showTokens") as? Bool) ?? true
        let oldMono = (d.object(forKey: "monochrome") as? Bool) ?? false
        colorMode = ColorMode(rawValue: d.string(forKey: "colorMode") ?? "") ?? (oldMono ? .flat : .level)
        menuBarSystemNumber = (d.object(forKey: "menuBarSystemNumber") as? Bool) ?? true
        accentHex = d.string(forKey: "accentHex") ?? kDefaultAccent   // Claude orange
        // Default to the design's clean soft-area. Legacy "bars"/"zones" values (removed as
        // selectable no-ops) fail rawValue parsing and land on Area automatically.
        chartStyle = ChartStyle(rawValue: d.string(forKey: "chartStyle") ?? "") ?? .area
        smartRefresh = (d.object(forKey: "smartRefresh") as? Bool) ?? true
        floatingShown = (d.object(forKey: "floatingShown") as? Bool) ?? false
        pinnedOnTop = (d.object(forKey: "pinnedOnTop") as? Bool) ?? true
        // Hourly leads: it is the view with real numbers on both axes and a visible shape. A session
        // burndown is mostly empty runway early in its window, which is a poor first impression.
        // Volume bars lead: real numbers on both axes and a visible shape. Legacy chartMode values
        // (burn/usage/session/week/hourly) do not parse as a ChartKind and fall through to it.
        chartKind = ChartKind(rawValue: d.string(forKey: "chartKind") ?? "") ?? .burnBars
        // Multi-chart selection: parse the CSV, drop anything unknown, fall back to the single
        // legacy chartKind so an existing install keeps its chart on first launch after update.
        let kindsCSV = d.string(forKey: "chartKinds") ?? ""
        let parsedKinds = kindsCSV.split(separator: ",").compactMap { ChartKind(rawValue: String($0)) }
        chartKinds = parsedKinds.isEmpty
            ? [ChartKind(rawValue: d.string(forKey: "chartKind") ?? "") ?? .burnBars]
            : parsedKinds
        chartDays = (d.object(forKey: "chartDays") as? Int) ?? 14
        chartHover = (d.object(forKey: "chartHover") as? Bool) ?? true
        dockEdge = DockEdge(rawValue: d.string(forKey: "dockEdge") ?? "") ?? .off
        tideLine = (d.object(forKey: "tideLine") as? Bool) ?? false
        tideEdge = DockEdge(rawValue: d.string(forKey: "tideEdge") ?? "") ?? .bottom   // default to the bottom edge
        tideStyle = EmberLineStyle(rawValue: d.string(forKey: "tideStyle") ?? "") ?? .emberLine
        tideFlames = (d.object(forKey: "tideFlames") as? Int) ?? 2
        tideGlow = (d.object(forKey: "tideGlow") as? Double) ?? 1.0
        tideThickness = TideThickness(rawValue: d.string(forKey: "tideThickness") ?? "") ?? .standard
        tideLength = min(1.0, max(0.4, (d.object(forKey: "tideLength") as? Double) ?? 1.0))
        tideOpacity = min(1.0, max(0.3, (d.object(forKey: "tideOpacity") as? Double) ?? 1.0))
        tideSparks = TideSparks(rawValue: d.string(forKey: "tideSparks") ?? "") ?? .calm
        tideSmoke = d.object(forKey: "tideSmoke") as? Bool ?? true
        tidePeek = d.object(forKey: "tidePeek") as? Bool ?? false
        tideDisplays = TideDisplays(rawValue: d.string(forKey: "tideDisplays") ?? "") ?? .all
        burnSpan = ChartSpan(rawValue: d.string(forKey: "burnSpan") ?? "") ?? .h1
        windowOpacity = (d.object(forKey: "windowOpacity") as? Double) ?? 1.0   // 1 = opaque (today's look)
        chipLivePreview = (d.object(forKey: "chipLivePreview") as? Bool) ?? false
        dockInside = (d.object(forKey: "dockInside") as? Bool) ?? false
        edgeOffset = (d.object(forKey: "edgeOffset") as? Double) ?? 0.5
        edgePx = (d.object(forKey: "edgePx") as? Double) ?? -1   // -1 = auto-center until the user places it
        edgeFromEnd = (d.object(forKey: "edgeFromEnd") as? Bool) ?? false
        dockLocked = (d.object(forKey: "dockLocked") as? Bool) ?? false
        widgetStyle = WidgetStyle(rawValue: d.string(forKey: "widgetStyle") ?? "") ?? .meters
        widgetScale = (d.object(forKey: "widgetScale") as? Double) ?? 1.0
        palette = PalettePreset(rawValue: d.string(forKey: "palette") ?? "") ?? .stoneClay
        textScale = (d.object(forKey: "textScale") as? Double) ?? 1.0
        insightsTextScale = (d.object(forKey: "insightsTextScale") as? Double) ?? 1.0
        cardWidth = (d.object(forKey: "cardWidth") as? Double) ?? 264
        cardChartBoost = (d.object(forKey: "cardChartBoost") as? Double) ?? 0
        floatingChrome = (d.object(forKey: "floatingChrome") as? Bool) ?? false   // clean borderless card by default
        glassMaterial = GlassMaterial(rawValue: d.string(forKey: "glassMaterial") ?? "") ?? .popover
        numberStyle = NumberStyle(rawValue: d.string(forKey: "numberStyle") ?? "") ?? .roll
        menuNumberFormat = MenuNumberFormat(rawValue: d.string(forKey: "menuNumberFormat") ?? "") ?? .sign
        menuTimeToReset = d.object(forKey: "menuTimeToReset") as? Bool ?? false
        menuBoldDigits = d.object(forKey: "menuBoldDigits") as? Bool ?? true
        showDockIcon = d.object(forKey: "showDockIcon") as? Bool ?? false
        menuShowPct = d.object(forKey: "menuShowPct") as? Bool ?? true
        smolderIntensity = (d.object(forKey: "smolderIntensity") as? Double) ?? 1.0
        smolderBreathSlow = d.object(forKey: "smolderBreathSlow") as? Bool ?? false
        smolderWarmthWander = d.object(forKey: "smolderWarmthWander") as? Bool ?? true
        flameSize = min(2.0, max(0.8, (d.object(forKey: "flameSize") as? Double) ?? 1.7))
        flameSparks = FlameSparks(rawValue: d.string(forKey: "flameSparks") ?? "") ?? .always
        flameSmoke = d.object(forKey: "flameSmoke") as? Bool ?? true
        // Beacon defaults = the shipped wink: every ~4s ±50%, 0.42s long, full accent, no glow.
        beaconEvery = (d.object(forKey: "beaconEvery") as? Double) ?? 4.0
        beaconJitter = (d.object(forKey: "beaconJitter") as? Double) ?? 0.5
        beaconLength = (d.object(forKey: "beaconLength") as? Double) ?? 0.42
        beaconStrength = (d.object(forKey: "beaconStrength") as? Double) ?? 1.0
        beaconGlow = (d.object(forKey: "beaconGlow") as? Double) ?? 0.0
        beaconMark = BeaconMark(rawValue: d.string(forKey: "beaconMark") ?? "") ?? .percent
        beaconCurve = BeaconCurve(rawValue: d.string(forKey: "beaconCurve") ?? "") ?? .snap
        beaconFollowsBurn = d.object(forKey: "beaconFollowsBurn") as? Bool ?? false
        beaconUsageColor = d.object(forKey: "beaconUsageColor") as? Bool ?? false
        beaconAlertBeat = d.object(forKey: "beaconAlertBeat") as? Bool ?? false
        showTimeRing = d.object(forKey: "showTimeRing") as? Bool ?? true
        showForecastLine = d.object(forKey: "showForecastLine") as? Bool ?? true
        showWeekPercent = d.object(forKey: "showWeekPercent") as? Bool ?? true
        showLast7Days = d.object(forKey: "showLast7Days") as? Bool ?? true
        showWeekResets = d.object(forKey: "showWeekResets") as? Bool ?? true
        showOpusShare = d.object(forKey: "showOpusShare") as? Bool ?? true
        showBurnChart = d.object(forKey: "showBurnChart") as? Bool ?? true
        // Honor the retired legacy "showCadence" key (same meaning) so an old install that had
        // hidden the countdown keeps it hidden.
        showCountdownRing = (d.object(forKey: "showCountdownRing") as? Bool)
            ?? (d.object(forKey: "showCadence") as? Bool) ?? true
        showChatsBurning = d.object(forKey: "showChatsBurning") as? Bool ?? true
        showDeveloperApiLine = d.object(forKey: "showDeveloperApiLine") as? Bool ?? true
        chatsExpanded = d.object(forKey: "chatsExpandedByDefault") as? Bool ?? false
        modelsExpanded = d.object(forKey: "modelsExpanded") as? Bool ?? false
        chatTruncation = ChatTruncation(rawValue: d.string(forKey: "chatTruncation") ?? "") ?? .middle
        hiddenUsageSeries = (d.array(forKey: "hiddenUsageSeries") as? [String]) ?? []
        popoverDividers = d.object(forKey: "popoverDividers") as? Bool ?? true
        popoverEyebrows = d.object(forKey: "popoverEyebrows") as? Bool ?? true
        popoverCompact = d.object(forKey: "popoverCompact") as? Bool ?? false
        liveColor = LiveColor(rawValue: d.string(forKey: "liveColor") ?? "") ?? .green
        alertsEnabled = d.object(forKey: "alertsEnabled") as? Bool ?? false
        alertThreshold = (d.object(forKey: "alertThreshold") as? Double) ?? 0.9
        let legacyAt = (d.object(forKey: "alertThreshold") as? Double) ?? 0.9
        alertSession = d.object(forKey: "alertSession") as? Bool ?? true
        alertSessionAt = (d.object(forKey: "alertSessionAt") as? Double) ?? legacyAt
        alertWeekly = d.object(forKey: "alertWeekly") as? Bool ?? true
        alertWeeklyAt = (d.object(forKey: "alertWeeklyAt") as? Double) ?? legacyAt
        alertBurn = d.object(forKey: "alertBurn") as? Bool ?? false
        alertBurnAt = (d.object(forKey: "alertBurnAt") as? Double) ?? 60_000
        alertOnReset = d.object(forKey: "alertOnReset") as? Bool ?? false
        alertSound = d.object(forKey: "alertSound") as? Bool ?? true
        alertRepeatMin = (d.object(forKey: "alertRepeatMin") as? Double) ?? 0
        alertOpus = d.object(forKey: "alertOpus") as? Bool ?? false
        alertOpusAt = (d.object(forKey: "alertOpusAt") as? Double) ?? 0.9
        alertSonnet = d.object(forKey: "alertSonnet") as? Bool ?? false
        alertSonnetAt = (d.object(forKey: "alertSonnetAt") as? Double) ?? 0.9
        alertForecast = d.object(forKey: "alertForecast") as? Bool ?? false
        alertForecastMin = (d.object(forKey: "alertForecastMin") as? Double) ?? 30
        budgetEnabled = d.object(forKey: "budgetEnabled") as? Bool ?? false
        budgetMetric = d.string(forKey: "budgetMetric") ?? "usd"
        budgetPeriod = d.string(forKey: "budgetPeriod") ?? "week"
        budgetLimit = (d.object(forKey: "budgetLimit") as? Double) ?? 50
        alertBudget = d.object(forKey: "alertBudget") as? Bool ?? false
        alertRunaway = d.object(forKey: "alertRunaway") as? Bool ?? false
        weeklyDigest = d.object(forKey: "weeklyDigest") as? Bool ?? false   // opt-in
        // Migrate the retired Apple-sound names onto the closest original chime.
        let legacySounds = ["Glass": "Chime", "Ping": "Pulse", "Funk": "Knock",
                            "Submarine": "Ember", "Hero": "Bloom", "Pop": "Drop"]
        let rawSound = d.string(forKey: "alertSoundName") ?? ""
        autoUpdateCheck = (d.object(forKey: "autoUpdateCheck") as? Bool) ?? true
        alertSoundName = legacySounds[rawSound] ?? rawSound
        quietHours = d.object(forKey: "quietHours") as? Bool ?? false
        quietFrom = (d.object(forKey: "quietFrom") as? Double) ?? 23
        quietTo = (d.object(forKey: "quietTo") as? Double) ?? 8
        glassTint = GlassTint(rawValue: d.string(forKey: "glassTint") ?? "") ?? .theme
        glassStyle = GlassStyle(rawValue: d.string(forKey: "glassStyle") ?? "") ?? .liquid
        glassOpacity = (d.object(forKey: "glassOpacity") as? Double) ?? 100
        glassBlur = (d.object(forKey: "glassBlur") as? Double) ?? 0
        glassSaturation = (d.object(forKey: "glassSaturation") as? Double) ?? 0
        glassTintIntensity = (d.object(forKey: "glassTintIntensity") as? Double) ?? 50
        glassBorderOpacity = (d.object(forKey: "glassBorderOpacity") as? Double) ?? 15
        glassBorderWidth = (d.object(forKey: "glassBorderWidth") as? Double) ?? 0
        glassCornerRadius = (d.object(forKey: "glassCornerRadius") as? Double) ?? 14
        glassShadow = (d.object(forKey: "glassShadow") as? Double) ?? 18
        // Section order,sanitized so it always contains exactly the current CardSections.
        let valid = CardSection.allCases.map { $0.rawValue }
        var order = (d.array(forKey: "sectionOrder") as? [String])?.filter { valid.contains($0) } ?? valid
        for r in valid where !order.contains(r) { order.append(r) }
        sectionOrder = order
        var hidden = (d.array(forKey: "sectionsHidden") as? [String])?.filter { valid.contains($0) } ?? []
        // migrate the old "Show weekly section" toggle into the modular hidden set
        if (d.object(forKey: "showWeekly") as? Bool) == false, !hidden.contains("week") { hidden.append("week") }
        sectionsHidden = hidden
        // migrate the old "0 = Smart" sentinel → explicit toggle + a sane fixed base
        if (d.object(forKey: "refreshSeconds") as? Int) == 0 { smartRefresh = true; refreshSeconds = 30 }
        // migrate old "menuBarMetric" → menuBarShow
        if let m = d.string(forKey: "menuBarMetric"), m == "weekly" { menuBarShow = .weekly }
        Palette.current = palette   // apply the saved palette before any view renders
    }

    // Restore the glass / background controls to their shipped defaults.
    func resetGlass() { applyGlassPreset("Liquid") }

    static let glassPresets = ["Liquid", "Crystal", "Frosted", "Vivid", "Minimal"]

    // One-tap looks. Each sets the whole glass control set to a nice, distinct combination.
    func applyGlassPreset(_ name: String) {
        switch name {
        case "Liquid":   // the refractive default
            glassStyle = .liquid; glassOpacity = 100; glassBlur = 0; glassSaturation = 0
            glassTint = .theme; glassTintIntensity = 50; glassBorderOpacity = 15; glassBorderWidth = 0; glassCornerRadius = 14; glassShadow = 18
        case "Crystal":  // clear glass, but still readable, with a bright glassy edge
            glassStyle = .clear; glassOpacity = 100; glassBlur = 7; glassSaturation = 25
            glassTint = .accent; glassTintIntensity = 30; glassBorderOpacity = 40; glassBorderWidth = 1; glassCornerRadius = 16; glassShadow = 22
        case "Frosted":  // classic soft blur
            glassStyle = .frosted; glassMaterial = .popover; glassOpacity = 100; glassBlur = 0; glassSaturation = 0
            glassTint = .theme; glassTintIntensity = 45; glassBorderOpacity = 10; glassBorderWidth = 0; glassCornerRadius = 14; glassShadow = 16
        case "Vivid":    // saturated, strongly tinted, glowy
            glassStyle = .liquid; glassOpacity = 100; glassBlur = 0; glassSaturation = 70
            glassTint = .accent; glassTintIntensity = 60; glassBorderOpacity = 25; glassBorderWidth = 1; glassCornerRadius = 14; glassShadow = 20
        case "Minimal":  // truly clear, almost no chrome
            glassStyle = .clear; glassOpacity = 100; glassBlur = 0; glassSaturation = 0
            glassTint = .none; glassTintIntensity = 0; glassBorderOpacity = 0; glassBorderWidth = 0; glassCornerRadius = 10; glassShadow = 8
        default: break
        }
    }
}
