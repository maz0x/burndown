# What's new in Burndown

## 1.2

- **Now under the Apache License 2.0**, still free and still open source. Same
  permissive terms as before, plus an explicit patent grant and, in section 6,
  an explicit statement that the licence does not hand over the name or the
  flame mark. Fork it and sell it if you like; just give your version its own
  name. See TRADEMARK.md.
- **Help and feedback in the menu.** Right-click the glyph for the guide, the
  welcome tour, and the two places to reach a human.
- **The About window got fixed up.** The lock icon sat in the gap between two
  lines of text; it now reads as part of the sentence. The credit links to
  GitHub, and the California line lights up when you point at it.
- **Better menu bar style picker artwork.** The style sheet was showing six
  retired styles you cannot actually choose, and its rows overlapped each other.
  It now shows exactly the styles in the picker, one clean row each.
- **Fixes:** the budget switches in Insights rendered as placeholder blocks in
  exported images, and the Insights window carried a band of empty space below
  its content.

## 1.1

- **Automatic updates.** Burndown checks GitHub once a day (a version lookup,
  nothing about you is sent), tells you in the menu when a new build exists,
  and installs it on one click: the download is checked against its published
  SHA-256, the signature is verified, the app is replaced in place and
  restarts. Turn the daily check off in Settings, General.
- **Explanations got out of the way.** The plain-English notes are now a small
  faint question dot beside each section and chart title; hover for the
  explanation. The card is calm again.
- Original alert sounds (Ember, Chime, Drop, Pulse, Bloom, Knock) replace the
  system ones.
- Universal build: Apple Silicon and Intel.

## 1.0

The first release.

- **Menu bar flame** that burns with your session: quiet when you are idle,
  raging when you are near the limit. Many other styles to choose from.
- **The card**: your 5-hour session, your week, per-model limits, live burn
  rate, and what the usage would have cost at API prices.
- **24 charts**, from burn rate and burndown runway to hour-of-day rhythm
  and cache efficiency. Pick the ones you want in Settings, Charts; the card
  stacks up to six.
- **Alerts** (optional): session, weekly, and per-model thresholds, burn
  spikes, time-to-limit forecasts, budgets, quiet hours.
- **Insights window**: per-project and per-chat attribution, weekly recap,
  pacing, model mix, and CSV/JSON/Markdown export.
- **Privacy**: everything stays on this Mac. Live numbers are opt-in and
  come straight from Claude's own usage service. See Privacy in the About
  window.

Downloaded copies are ad-hoc signed for now: macOS will warn on first open.
Right-click the app, choose Open, then Open again. Building from source with
./build.sh avoids the warning.
