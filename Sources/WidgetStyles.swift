import SwiftUI

// Selectable looks for the edge widget. Each renders a slim vertical card (Left/Right dock)
// and a short horizontal bar (Top/Bottom dock). All are intentionally compact.
enum WidgetStyle: String, CaseIterable, Identifiable {
    case meters, bigTile, rings, arcs, twinTanks, pills   // CORE first, then LEGACY
    var id: String { rawValue }
    var label: String {
        switch self {
        case .meters:    return "Meters"
        case .bigTile:   return "Big numbers"
        case .rings:     return "Rings"
        case .arcs:      return "Twin arcs"
        case .twinTanks: return "Twin tanks (legacy)"
        case .pills:     return "Pills (legacy)"
        }
    }
}

// Everything a widget style needs to draw.
struct WData {
    var s: Double      // session 0...1
    var w: Double      // weekly 0...1
    var sc: Color      // session color
    var wc: Color      // weekly color
    var p: Palette
}

private func pctN(_ x: Double) -> String { "\(Int((x * 100).rounded()))" }

// MARK: shared mini shapes

private func tank(_ frac: Double, _ color: Color, _ track: Color, w: CGFloat, h: CGFloat) -> some View {
    ZStack(alignment: .bottom) {
        Capsule().fill(track)
        Capsule().fill(color).frame(height: max(4, h * min(1, max(0, frac))))
    }.frame(width: w, height: h)
}
private func hbar(_ frac: Double, _ color: Color, _ track: Color, w: CGFloat, h: CGFloat = 5) -> some View {
    ZStack(alignment: .leading) {
        Capsule().fill(track)
        Capsule().fill(color).frame(width: max(h, w * min(1, max(0, frac))))
    }.frame(width: w, height: h)
}
private func ring(_ frac: Double, _ color: Color, _ track: Color, size: CGFloat, lw: CGFloat) -> some View {
    ZStack {
        Circle().stroke(track, lineWidth: lw)
        Circle().trim(from: 0, to: max(0.001, min(1, frac)))
            .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round)).rotationEffect(.degrees(-90))
    }.frame(width: size, height: size)
}
private func arc(_ frac: Double, _ color: Color, _ track: Color, size: CGFloat, lw: CGFloat) -> some View {
    ZStack {
        Circle().trim(from: 0, to: 0.75).stroke(track, style: StrokeStyle(lineWidth: lw, lineCap: .round)).rotationEffect(.degrees(135))
        Circle().trim(from: 0, to: 0.75 * max(0.001, min(1, frac)))
            .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round)).rotationEffect(.degrees(135))
    }.frame(width: size, height: size)
}
private func cap(_ t: String, _ c: Color) -> some View {
    Text(t).font(.system(size: 7, weight: .bold)).foregroundStyle(c)
}

// MARK: the style switch

@ViewBuilder
func widgetContent(_ style: WidgetStyle, _ d: WData, horizontal: Bool, scale: CGFloat = 1) -> some View {
    let tk = d.p.track
    // Reflow ladder: S/W spell out at large scale; weekly and eyebrows drop at small scale.
    let words = scale >= 1.3
    let tiny = scale < 0.85
    let sLab = words ? "SESSION" : "S", wLab = words ? "WEEK" : "W"
    switch style {
    case .twinTanks:
        if horizontal {
            HStack(spacing: 6) {
                cap("S", d.p.faint); hbar(d.s, d.sc, tk, w: 30, h: 4); Text(pctN(d.s)).font(.system(size: 10, weight: .semibold)).foregroundStyle(d.sc).frame(width: 17, alignment: .leading)
                cap("W", d.p.faint); hbar(d.w, d.wc, tk, w: 30, h: 4); Text(pctN(d.w)).font(.system(size: 10, weight: .semibold)).foregroundStyle(d.wc).frame(width: 17, alignment: .leading)
            }
        } else {
            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 6) { tank(d.s, d.sc, tk, w: 10, h: 44); tank(d.w, d.wc, tk, w: 10, h: 44) }
                HStack(spacing: 6) {
                    Text(pctN(d.s)).foregroundStyle(d.sc).frame(width: 10)
                    Text(pctN(d.w)).foregroundStyle(d.wc).frame(width: 10)
                }.font(.system(size: 9, weight: .semibold))
            }
        }
    case .meters:
        let block: (String, Double, Color) -> AnyView = { lab, v, c in AnyView(
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) { if !tiny { cap(lab, d.p.faint) }; Text(pctN(v)).font(.system(size: 11, weight: .semibold)).foregroundStyle(d.p.ink) }
                hbar(v, c, tk, w: horizontal ? 42 : 38, h: 3)
            })
        }
        // Below 0.85x the weekly meter drops so the widget stays compact.
        if horizontal { HStack(spacing: 11) { block(sLab, d.s, d.sc); if !tiny { block(wLab, d.w, d.wc) } } }
        else { VStack(alignment: .leading, spacing: 7) { block(sLab, d.s, d.sc); if !tiny { block(wLab, d.w, d.wc) } } }
    case .rings:
        let body = ZStack {
            ring(d.s, d.sc, tk, size: horizontal ? 26 : 36, lw: horizontal ? 3.0 : 3.5)
            if !horizontal { ring(d.w, d.wc, tk, size: 24, lw: 2.5) }
            Text(pctN(d.s)).font(.system(size: horizontal ? 9 : 11, weight: .semibold)).foregroundStyle(d.p.ink)
        }
        if horizontal { HStack(spacing: 7) { body.frame(width: 26, height: 26); Text("W \(pctN(d.w))%").font(.system(size: 10, weight: .medium)).foregroundStyle(d.wc) } }
        else { body }
    case .arcs:
        let one: (String, Double, Color) -> AnyView = { lab, v, c in AnyView(
            ZStack {
                arc(v, c, tk, size: 26, lw: 2.4)
                VStack(spacing: 0) { Text(pctN(v)).font(.system(size: 9, weight: .semibold)).foregroundStyle(d.p.ink); cap(lab, d.p.faint) }
            }.frame(width: 26, height: 26))
        }
        HStack(spacing: 6) { one("S", d.s, d.sc); one("W", d.w, d.wc) }
    case .bigTile:
        let big: (String, Double, Color) -> AnyView = { lab, v, c in AnyView(
            VStack(alignment: horizontal ? .center : .leading, spacing: 0) {
                if !tiny { cap(lab, d.p.faint) }
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(pctN(v)).font(.system(size: horizontal ? 15 : 19, weight: .semibold, design: .rounded)).foregroundStyle(c)
                    Text("%").font(.system(size: 8, weight: .medium)).foregroundStyle(c.opacity(0.7))
                }
            })
        }
        if horizontal { HStack(spacing: 11) { big(words ? "SESSION" : "SESS", d.s, d.sc); if !tiny { big(wLab, d.w, d.wc) } } }
        else if tiny { big(words ? "SESSION" : "SESS", d.s, d.sc) }
        else { VStack(alignment: .leading, spacing: 4) { big(words ? "SESSION" : "SESS", d.s, d.sc); Rectangle().fill(d.p.divider).frame(height: 0.75); big(wLab, d.w, d.wc) } }
    case .pills:
        let pill: (Double, Color, Bool) -> AnyView = { v, c, filled in AnyView(
            Text("\(pctN(v))%").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(filled ? d.p.bg : c)   // knocked-out paper on the filled capsule (was ad-hoc 4A1B0C)
                .frame(width: 42, height: 17)
                .background(filled ? AnyView(Capsule().fill(c)) : AnyView(Capsule().strokeBorder(c, lineWidth: 1.2))))
        }
        if horizontal { HStack(spacing: 6) { pill(d.s, d.sc, true); pill(d.w, d.wc, false) } }
        else { VStack(spacing: 5) { pill(d.s, d.sc, true); pill(d.w, d.wc, false) } }
    }
}
