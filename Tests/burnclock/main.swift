import Foundation

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print((cond ? "  ok   " : "  FAIL ") + msg); if !cond { failures += 1 }
}

// Tier ladder
check(BurnClock.tier(usage: 0.4, over: false, burnRatio: 0, threshold: 0.85, tokensFlowing: false) == .idle, "no tokens -> idle")
check(BurnClock.tier(usage: 0.4, over: false, burnRatio: 0.3, threshold: 0.85, tokensFlowing: true) == .low, "flowing, low burn -> low")
check(BurnClock.tier(usage: 0.4, over: false, burnRatio: 1.0, threshold: 0.85, tokensFlowing: true) == .mid, "mid burn -> mid")
check(BurnClock.tier(usage: 0.4, over: false, burnRatio: 2.0, threshold: 0.85, tokensFlowing: true) == .heavy, "high burn -> heavy")
check(BurnClock.tier(usage: 0.75, over: false, burnRatio: 0, threshold: 0.85, tokensFlowing: true) == .heavy, "near threshold -> heavy")
check(BurnClock.tier(usage: 0.9, over: false, burnRatio: 0, threshold: 0.85, tokensFlowing: true) == .redline, "at threshold -> redline")
check(BurnClock.tier(usage: 1.0, over: true, burnRatio: 3, threshold: 0.85, tokensFlowing: true) == .overLimit, "over -> overLimit")

// Tempo ladder periods
check(BurnTier.idle.period == 8.0 && BurnTier.redline.period == 2.4 && BurnTier.overLimit.period == 10.0, "tempo ladder periods")

// Phase + breath
var c = BurnClock(); c.elapsed = 0; c.retier(usage: 0.9, over: false, burnRatio: 0, threshold: 0.85, tokensFlowing: true)
check(c.tier == .redline && c.period == 2.4, "retier sets tier + period")
check(abs(c.breath) < 0.001, "breath at phase 0 is ~0")
c.elapsed = 1.2   // half of 2.4s -> phase 0.5 -> breath peak = amplitude (1.5)
check(abs(c.breath - 1.5) < 0.001, "breath at phase 0.5 is amplitude")

// Contract: tempo changes interpolate over one full current cycle with phase preserved, and
// never snap. The period changes with the tier, so a naive `elapsed mod period` discontinuously
// jumps on every retier. Lock the continuity in.
print("phase continuity across a tempo change:")
var t = BurnClock()
t.elapsed = 0
t.retier(usage: 0.10, over: false, burnRatio: 0, threshold: 0.85, tokensFlowing: false)  // idle, 8.0s
t.elapsed = 3.0                                    // phase = 3/8 = 0.375
let before = t.phase
check(abs(before - 0.375) < 1e-9, "idle phase at t=3s is 0.375")
t.retier(usage: 0.90, over: false, burnRatio: 0, threshold: 0.85, tokensFlowing: true)   // -> redline, 2.4s
check(t.period == 2.4, "tier escalated to redline (2.4s period)")
check(abs(t.phase - before) < 1e-9, "phase is PRESERVED across the tempo change (no snap)")
t.elapsed = 3.0 + 1.0 / 30.0                       // and keeps advancing smoothly, not jumping
check(t.phase > before && t.phase - before < 0.02, "phase advances continuously after the change")
let held = t.phase                                 // a retier to the SAME tier must not re-anchor
t.retier(usage: 0.90, over: false, burnRatio: 0, threshold: 0.85, tokensFlowing: true)
check(abs(t.phase - held) < 1e-12, "re-tiering to the same tier does not move phase")

// Hard oscillation ceiling of 2.5 Hz, everywhere, no exceptions.
print("2.5 Hz oscillation ceiling:")
for tier in BurnTier.allCases {
    check(tier.flameFlick.hz <= BurnTier.hzCeiling, "\(tier.rawValue) flame flick <= 2.5 Hz")
    check(tier.flameSway.hz <= BurnTier.hzCeiling, "\(tier.rawValue) flame sway <= 2.5 Hz")
    check((tier.flameFlick2?.hz ?? 0) <= BurnTier.hzCeiling, "\(tier.rawValue) secondary flick <= 2.5 Hz")
    check(tier.seamHz <= BurnTier.hzCeiling, "\(tier.rawValue) burnfront seam <= 2.5 Hz")
    check(tier.smolderBreathHz <= BurnTier.hzCeiling, "\(tier.rawValue) smolder breath <= 2.5 Hz")
}
// The idle contract - no idle motion cycle completes in under 4s (idle freqs <= 0.25 Hz).
check(BurnTier.idle.flameFlick.hz <= 0.25 && BurnTier.idle.flameSway.hz <= 0.25
      && BurnTier.idle.seamHz <= 0.25 && BurnTier.idle.smolderBreathHz <= 0.25,
      "idle contract: every idle fire frequency is at or below 0.25 Hz")
// The heat ladder.
check(BurnTier.idle.heat == 0.15 && BurnTier.low.heat == 0.30 && BurnTier.mid.heat == 0.50
      && BurnTier.heavy.heat == 0.85 && BurnTier.redline.heat == 1.0 && BurnTier.overLimit.heat == 0.10,
      "heat ladder matches the BurnTier table")

if failures == 0 { print("\nALL PASS") } else { print("\n\(failures) FAILED"); exit(1) }
