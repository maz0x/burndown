# What's new in Burndown

## 0.9.2

**Update if you have ever moved the Popover size slider.** At any size other
than 100 percent, the card could measure its own height back into itself and
grow without limit until macOS shut the app down. Setting it back to 100
percent avoided it; this release removes the cause, so every size is safe.

- **Resize the card by dragging its corner.** The popover and the floating
  window now have a grip in the bottom-right corner, and it resizes rather
  than zooms: the type stays the same size and the layout reflows. Drag
  sideways for a wider card, where bars stretch, chat names stop truncating,
  and charts get more room; drag down and every chart plot gets taller.
  Double-click the grip to snap back. The Popover size slider remains the
  separate text zoom, and the two compose.
- **Insights is a studio now.** A time scope (Today · 7 days · 30 days · All
  time) re-filters the recap, biggest chats, projects, and exports; the
  14-day rhythm is a real chart with a hover readout and a peak/avg line;
  exports ask where to save (and confirm) instead of silently writing to
  Downloads; and a stat trio (tokens, est. compute, top model) heads the page.
- **The Account window grew a Diagnostics and storage drawer**: token expiry,
  live-cache age, and exactly where (and how tightly) everything is stored.
- **The dock follower explains itself.** If docking is on without macOS
  Accessibility permission, a card in Settings says so, with one-click Grant
  and Open System Settings buttons. Granting also makes the follower fully
  event-driven, and the fallback tracking now stops burning CPU while events
  are flowing.
- **Escape and Cmd+W close every Burndown window.**
- **The floating window lost its ghost shadow** (the system drew a second,
  rectangular shadow under the card's own).
- **Quieter internals**: network calls moved to modern Swift concurrency (no
  more parked worker threads during slow requests), and the menu bar glyph
  re-renders the moment it moves to a display with a different pixel density.
- **Beacon, a new menu bar style.** It rests in the menu bar's own ink so it
  passes for a system icon, then winks to your accent for a fraction of a
  second every few seconds: proof the app is alive with no demand for
  attention. Five presets, a full set of knobs (mark, wink curve, cadence,
  randomness, length, strength, glow, rhythm), a Try it button, an optional
  double wink past your alert threshold, and a wink color that can ride your
  usage so the hue says how close you are to the cap. Idles at 2.6% of a core,
  lower than any other live style.
- **Floating windows breathe for free.** Perpetual animations moved off
  SwiftUI's display link onto Core Animation, so a breathing dot no longer
  costs a quarter of a CPU core.
- **New social preview card** for link unfurls.

## 0.9.1

Housekeeping, no feature changes.

- **The website moved** to burndown-app.pages.dev, and the Guide menu item now
  opens it directly. The old address is being retired, so update to keep that
  menu item working.
- **Install instructions rewritten.** Both documented ways past Gatekeeper had
  stopped working: Homebrew removed the `--no-quarantine` command-line flag, and
  Apple removed the right-click, Open shortcut in macOS 15. The README, the
  guide and the Homebrew cask now describe four routes that actually work.

## 0.9.0

The first public release.

Burndown is a native macOS menu bar app that shows how much of your Claude
session and weekly limits are left, which conversation is spending them, and
when your current pace reaches a cap.

- **The card.** Session and weekly percentages with reset clocks, every
  per-model weekly cap, live tokens per minute, and what the same work would
  have cost at API list prices.
- **Attribution.** Per-conversation and per-project usage, so the chat that
  quietly ate your week has a name, a token count and an estimated cost.
- **Forecasting.** Time to limit from your recent pace, weekly pacing in plain
  language, model-mix advice, and a pace gauge against the rate that lasts
  exactly to the reset.
- **Alerts, all off by default.** Thresholds, burn spikes, budgets, quiet
  hours, and adaptive runaway detection that learns your normal rate instead of
  using a fixed number.
- **Two dozen charts**, each drawn with sample or live data in a gallery before
  you choose it.
- **Yours to shape.** Twenty-plus themes, real Liquid Glass on macOS 26, a
  couple dozen menu bar glyphs, a widget that follows the Claude window, a
  screen-edge meter, a floating card, and a gauge for the Claude Code
  statusline.
- **Private by design.** Estimate mode makes no network requests at all. Live
  mode is opt-in and talks only to Anthropic. Nothing is sent anywhere else.
- **Self-updating**, verified against a published SHA-256 and the signature.

### Why 0.9 and not 1.0

Everything above works and is tested, but two things are still ahead: releases
are not yet Developer ID signed, so macOS asks once on first open, and support
for other providers is in active development. 1.0 is reserved for when those
land.

If something looks wrong, say so in
[Discussions](https://github.com/maz0x/burndown/discussions) or open an
[issue](https://github.com/maz0x/burndown/issues). Early reports carry the most
weight.
