# What's new in Burndown

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
