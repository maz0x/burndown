import AppKit
import SwiftUI

// Contrast audit. `CUB_CONTRAST=/path/out.csv` writes a row for every text-on-surface pairing the
// app actually draws, across all 21 palettes in both schemes, and exits.
//
// This exists because "is that grey too pale?" is not a question worth answering by eye, especially
// 21 themes deep. It reads the real Palette.of(), so the numbers can never drift from what ships.
//
// The thresholds are WCAG 2.1 AA: 4.5:1 for normal text, 3:1 for large text (18pt+, or 14pt+ bold)
// and for the non-text things that still have to be seen, like a divider or a chart gridline.

enum ContrastAudit {

    /// One thing the app draws, and what it has to be legible against.
    struct Pair {
        let name: String          // role, as the code names it
        let where_: String        // where the reader meets it
        let size: Double          // the point size actually used
        let bold: Bool
        let fg: (Palette) -> Color
        let bg: (Palette) -> Color
        /// Decorative pieces carry information by position, not by being read as text, so WCAG
        /// holds them to 3:1 rather than 4.5:1. Marking one of these is a judgement call, so each
        /// is named individually below rather than inferred from anything.
        let decorative: Bool
        /// Reported with its number, but never counted as a failure. See the structure pairs below.
        var exempt: Bool = false

        var required: Double {
            if decorative { return 3.0 }
            return (size >= 18 || (bold && size >= 14)) ? 3.0 : 4.5
        }
    }

    static let pairs: [Pair] = [
        // --- the card ---
        Pair(name: "ink on bg", where_: "headline numbers and chat names", size: 12.5, bold: false,
             fg: { $0.ink }, bg: { $0.bg }, decorative: false),
        Pair(name: "sub on bg", where_: "rates, secondary readings, stat lines", size: 12, bold: false,
             fg: { $0.sub }, bg: { $0.bg }, decorative: false),
        Pair(name: "faint on bg", where_: "chart captions and axis labels", size: 9.5, bold: false,
             fg: { $0.faint }, bg: { $0.bg }, decorative: false),
        Pair(name: "sub on track", where_: "labels over a filled row or chip", size: 11, bold: false,
             fg: { $0.sub }, bg: { $0.track }, decorative: false),
        Pair(name: "faint on track", where_: "captions over a filled row", size: 9.5, bold: false,
             fg: { $0.faint }, bg: { $0.track }, decorative: false),
        Pair(name: "ink on raisedBg", where_: "text inside an explanation bubble", size: 11.5, bold: false,
             fg: { $0.ink }, bg: { $0.raisedBg }, decorative: false),
        Pair(name: "sub on raisedBg", where_: "second line of an explanation bubble", size: 9.5, bold: false,
             fg: { $0.sub }, bg: { $0.raisedBg }, decorative: false),
        // --- the metric colours ---
        // session and weekly are shown, not read: a dot beside a label, a fill inside a bar. The
        // headline percentage is drawn in the user's chosen accent, not in these. So they are
        // held to the 3:1 WCAG asks of a graphical object. (An earlier draft of this file held
        // them to 4.5:1 as if they were text, which would have meant repainting the identity of
        // all 21 themes to satisfy a pairing the app does not actually draw.)
        Pair(name: "session dot on bg", where_: "the session marker", size: 9, bold: false,
             fg: { $0.session }, bg: { $0.bg }, decorative: true),
        Pair(name: "weekly dot on bg", where_: "the weekly marker", size: 9, bold: false,
             fg: { $0.weekly }, bg: { $0.bg }, decorative: true),
        Pair(name: "warning on bg", where_: "the warning threshold reading", size: 12, bold: true,
             fg: { $0.warning }, bg: { $0.bg }, decorative: false),
        Pair(name: "overLimit on bg", where_: "the over-limit reading", size: 12, bold: true,
             fg: { $0.overLimit }, bg: { $0.bg }, decorative: false),
        Pair(name: "live on bg", where_: "the live indicator", size: 11, bold: false,
             fg: { $0.live }, bg: { $0.bg }, decorative: false),
        // --- structure ---
        // The FILLED part of a usage bar against its own groove is the pair that carries the
        // reading, and WCAG holds that to 3:1. The groove against the window behind it does not:
        // a hairline divider and an empty track are decorative, which 1.4.11 excludes by name.
        // (Measured for the record: they sit at 1.1-1.4:1 in every theme, which is also where
        // AppKit's own separators sit. Holding them to 3:1 would draw heavy black rules through a
        // design nobody asked to change, so they are listed as exempt rather than quietly passed.)
        Pair(name: "session fill on track", where_: "the session usage bar", size: 9, bold: false,
             fg: { $0.session }, bg: { $0.track }, decorative: true),
        Pair(name: "weekly fill on track", where_: "the weekly usage bar", size: 9, bold: false,
             fg: { $0.weekly }, bg: { $0.track }, decorative: true),
        Pair(name: "divider on bg", where_: "hairline between groups (exempt, decorative)", size: 1,
             bold: false, fg: { $0.divider }, bg: { $0.bg }, decorative: true, exempt: true),
        Pair(name: "empty track on bg", where_: "unfilled part of a bar (exempt, decorative)", size: 9,
             bold: false, fg: { $0.track }, bg: { $0.bg }, decorative: true, exempt: true),
    ]

    static func run(to path: String, raw: Bool = false) {
        var out = "palette,scheme,role,where,pt,bold,required,ratio,verdict\n"
        var fails = 0, worst = (ratio: 99.0, line: "")
        let saved = Palette.current
        for preset in PalettePreset.allCases {
            Palette.current = preset
            for scheme in [ColorScheme.light, .dark] {
                // CUB_CONTRAST_RAW audits the palettes BEFORE the legibility correction, so the
                // "what it was like" file stays reproducible instead of being a one-off artefact.
                let p = raw ? Palette.uncorrected(scheme) : Palette.of(scheme)
                for pair in pairs {
                    let r = NSColor.wcagContrast(NSColor(pair.fg(p)), NSColor(pair.bg(p)))
                    let ok = r >= pair.required - 0.005      // rounding slack at the printed precision
                    if !ok, !pair.exempt { fails += 1 }
                    // Quoted: several of the "where" strings contain commas, and an unquoted CSV
                    // silently shifts every column after them.
                    let line = "\(preset.rawValue),\(scheme == .dark ? "dark" : "light"),\(pair.name),"
                        + "\"\(pair.where_)\",\(pair.size),\(pair.bold),\(pair.required),"
                        + String(format: "%.2f", r) + ",\(pair.exempt ? "exempt" : (ok ? "pass" : "FAIL"))"
                    out += line + "\n"
                    if !ok, !pair.exempt, r < worst.ratio { worst = (r, line) }
                }
            }
        }
        Palette.current = saved
        try? out.write(toFile: path, atomically: true, encoding: .utf8)
        let total = PalettePreset.allCases.count * 2 * pairs.filter { !$0.exempt }.count
        print("contrast: \(total - fails)/\(total) pass, \(fails) fail  ->  \(path)")
        if fails > 0 { print("worst: \(worst.line)") }
    }
}
