# What's new in Burndown

## 0.9.8

- **Burndown no longer sits on a CPU core in the background.** If you have a lot of Claude Code
  history, the part of Burndown that reads your local logs was redoing work it had already done. It
  keeps a cache of what it has already counted, but two of its own scans wanted different amounts of
  history, and each one threw away what the other still needed. The quick scan runs every couple of
  seconds, so the deeper scan spent its life rebuilding a cache that was about to be discarded
  again. Measured on a 1.7 GB folder of logs, that was 162 MB of re-reading every two seconds and
  1.22 GB every ten minutes, none of it producing a different answer. The cache now keeps whatever
  the deepest scan needs, so a shallow scan cannot throw away a deep scan's work. The same numbers
  reach the screen for a small fraction of the effort: on the machine this was found on, a pegged
  core became almost nothing, and memory settled from about 800 MB to about 250 MB.
- **The deep scan can no longer start twice at once.** It runs on a ten minute timer, but the Day
  span setting and the LIVE button fire it too, and it had nothing to stop a second copy starting on
  top of one already running. The other two scans already had that guard.

## 0.9.7

- **Burndown stops asking macOS for permission every time.** If your Mac ever refused to open it
  and offered to move it to the Trash, that was macOS reacting to a downloaded copy it cannot
  verify, not a fault in the app. The button it puts in front of you deletes your install, which is
  a poor thing to have highlighted. Burndown now clears that mark from itself each time it starts,
  so once you have let it open, it stops happening. Updates were never affected: the installer has
  always cleared the mark on the copy it puts in place.
- **The README now answers "it will not open" directly**, in the words you would search for, and
  tells you to press Cancel rather than the button macOS highlights.

## 0.9.6

Three reviews of the whole app, run back to back: one through every calculation it makes, one
through the parts that had never been examined at all, and one through the design of the card.
184 findings. All but four are here. What that means in practice:

### The numbers are right now

- **Insights was counting a lot of your usage twice.** When you resume a conversation, Claude Code
  starts a new log and copies the earlier part of the chat into it. Burndown was adding up both
  copies. On a heavy machine more than half of all the rows turned out to be copies, which meant
  Insights could overstate tokens by about two and a half times and estimated spend by nearly three
  (dollars come off worse because the duplicated rows lean toward the expensive models). The menu
  bar card was always right, which is why the two could disagree about the same day.
- **"Biggest chats, 7 days" was showing a chat's whole lifetime.** If you sent one message
  yesterday to a conversation from months ago, its entire history counted as this week. The same
  fault was in "By project" and in the exports.
- **"7 days" now means seven days.** The summary used to say "7 days" and then, correctly, "across
  8 days", because the window was counted in hours and almost always clipped an eighth day.
- **Older Opus models were priced at a third of their real rate**, because the price list was
  matching against a name those models never actually use.
- **A forecast could quietly draw its "current pace" across a month of history** when the last hour
  was too quiet to read, and present that as a countdown.
- **A budget just after midnight could announce you were about to blow it.** One minute past twelve
  is a fraction of a percent of the day, so a single message was scaled up enormously. Weekly
  budgets also followed a rolling seven days rather than the week Claude actually resets.
- **Timestamps written in a different time zone were read as if they were yours**, which could move
  an evening's work onto the wrong day.
- **Averages, percentages and rounding now agree with each other.** The burn average was pulled
  toward busy moments because it counted samples rather than time. "Used" and "left" were rounded
  separately, so they could add up to 101. Sessions-left rounded up, promising a session that was
  not there. A run-out time on another day showed the hour but dropped the minutes.
- **The day charts no longer merge two days into one bar** when a month boundary falls inside the
  window, and the hour and weekday profiles no longer count a half day as a whole one.

### It behaves properly

- **Only one Burndown runs at a time.** Nothing stopped a second copy starting, so you could end up
  with two identical icons in the menu bar, both polling, with no way to tell which one a click
  would reach. Opening it again now brings the running one forward.
- **Two crashes are fixed.** A chat whose first message mentioned a slash-command tag could take the
  app down while it worked out that chat's name. So could a log written while the Mac's clock was
  wrong.
- **The runaway-burn alert no longer cries wolf.** It learned "your normal rate" from samples taken
  whether or not anything was running, so a quiet minute convinced it your normal was zero and the
  next reply looked infinitely faster than normal. It now learns only from real activity, waits
  until it has seen enough, and will not quietly accept a runaway as the new normal.
- **A threshold alert now re-arms if your reset time moves earlier.** It only noticed the clock
  moving forward, so a correction the other way left alerts silently switched off for that window.
- **Chat names, and the app's memory of them, are no longer lost to a race.** Two parts of the app
  could overwrite each other's work, and a save could write the version from just before the change
  that triggered it.
- **Opening Insights twice in quick succession no longer starts two full scans.**
- **The app gives memory back.** Opening Insights once held your whole history for the rest of the
  session; a widget switched off kept running invisibly; the file tracker never forgot logs that had
  been deleted.

### You can use it without a mouse

- **Every segmented control in Settings was invisible to VoiceOver.** It read the options aloud but
  gave no way to choose one and never said which was selected. They are real buttons now.
- **Renaming a chat is reachable**, where before it needed a hover and a click on a pencil that only
  appears on hover.
- **The seven-day bars, the by-model section and the loading indicator** now describe themselves.
- **Reduce Motion is honoured** by the Insights loading animation.
- **The small info marks are easier to hit**, without moving anything on screen.

### Privacy and safety

- **Files holding your sign-in token, account details and chat names are private from the instant
  they are created**, rather than a moment later.
- **The updater only accepts downloads from GitHub**, and checks versions properly, so a test build
  can no longer look newer than a real one and a half-finished install is rolled back rather than
  left in place.
- **Exports cannot carry surprises.** A conversation named like a spreadsheet formula is no longer
  written in a form a spreadsheet would run, and a name written like a link is no longer turned into
  a working link in the report.
- **A screenshot or test run can no longer write into your real settings**, which previously could
  suppress a genuine alert or move a real timestamp.

### The card and the charts

- **The card reads as one thing.** Rates were written three different ways, headings came in four
  sizes, and a session under half a percent showed "0%" above a line reading two dollars a minute.
  There is one grammar now, and "<1" where "0" would be a lie.
- **A weekly limit's percentage matches the colour of its own bar** instead of borrowing another
  measurement's colour.
- **The week line keeps its own colour when it is running low**, instead of the whole curve turning
  warning brown and looking like a different measurement.
- **A label no longer prints on top of the line it describes.**
- **An empty bar is empty**, and a full ring is a full circle, rather than each showing a small
  artefact that reads as a glitch.
- **The share bar adds up.** With more than six projects it simply did not fill, and nothing said
  why. The remainder is now its own slice.
- **The busiest chat that is running right now is marked**, and chat names in that list follow the
  shortening you chose in Settings.
- **Model lines only appear on windows wide enough to mean something**, instead of drawing flat
  dashes across a four-hour view.
- **Switching a line off in the legend looks switched off**, rather than merely faint.
- **A day that cost forty cents no longer labels its chart "$0"**, and token axes label their middle
  as well as their ends.
- **Charts no longer throw away the spikes** they exist to show, when thinning older history.
- **Quiet hours, the widget edge, and several explanations now say what the app actually does.**
  Quiet hours drops alerts rather than saving them for later, and said the opposite. Turning the
  docked widget off and on again brought it back on the bottom instead of where you put it. The
  first-run tour claimed Burndown "contacts nothing" while the update check was on by default.
- **The widget follows a second Claude window**, and stops polling hard when Claude is not running.

## 0.9.5

- **The Account window is readable.** It was locked to a narrow width, which was the cause of all
  of it: your organization name arrived split across two lines and still cut off with dots, the
  padlock floated in the gap between two lines of a sentence that should have been one, and the
  diagnostics section talked about "folder 0700, files 0600". It is wider now, the organization
  name sits on its own line and simply fits, and the diagnostics say what they mean: your sign-in
  renews itself, and your data is readable only by you.
- **Everything in the card now lines up.** Section headings, rows, bars and numbers share one
  grid, so a total sits in the same place in every chart and a number in one chart ends on the
  same edge as a number in the next. "Last 7 days" was the one heading sitting on the right while
  its bars sat on the left; it reads like the rows above it now.
- **Each weekly limit's percentage is coloured to match its own bar**, in the card and the Account
  window alike, so the number and the bar read as one thing.
- **The average line on the burn charts lost its label.** It printed itself over the newest data
  point on a busy chart; the line under the chart already tells you the average.

- **The screenshot of the Insights window on the site was cut off down its right-hand side.** The
  window was widened in 0.9.4 but the picture of it was still being drawn at the old, narrower
  size, so the last column was sliced off mid-word in every published shot.
- **The "% left" figure on each weekly limit now matches the colour of its own bar**, so the number
  and the bar read as one thing rather than two. It uses a deepened version of that colour: the
  hues used for bars and dots are tuned to be seen, not read, and using them for a number directly
  fell below the readability standard in most of the themes.

## 0.9.4

- **Insights opens in a fraction of a second instead of several.** The scan behind it read every
  session log in full, every time you opened the window, even though yesterday's logs cannot
  change. It now remembers what each file contributed and only re-reads the ones that actually
  moved. Measured on a 1.2GB history: 8.4 seconds the first time, 0.07 seconds every time after.
- **Insights is a window you can read.** It opens twice as wide, remembers whatever size you leave
  it at, and has an A- / A+ control in the corner for text size. Numbers no longer wrap onto two
  lines, every money figure is written the same way, and the 14-day chart no longer skips days
  with no usage, which was making its dates jump.
- **Hovering the 14-day bars is instant.** Every table in the window was recomputing your whole
  history on each hover; at a large history that was over a second of work per frame, which is why
  All time crawled and Today felt fine.
- **"By project" says something useful.** If you run Claude from your home folder, everything used
  to collapse into one "Home folder" row. That row now opens into the conversations inside it, and
  when it is the only row the section lists your chats directly instead.
- **The card stops growing off the bottom of the screen.** Add enough charts and it used to run
  past the edge of the display with no way to reach what fell off. It now stops just short of the
  bottom and scrolls.
- **Chats have names.** The card showed raw session ids like `ca73b9d7-2539-...` because only
  Insights ever read the real titles. Both now share one index, so a conversation is named
  everywhere it appears.
- **Export writes a real report.** It was a bare per-day table. The Markdown export is now a full
  report: totals, per model, per project with the home folder broken out, biggest conversations,
  day by day, and a note explaining what the dollar figures mean. Each button says what it gives
  you, and the period is in the filename.
- **The menu bar number matches your clock.** It takes the system colour by default now, so it
  stays readable over any wallpaper. The dot and glow keep their colour. Switchable in Appearance.
- **Every section in Insights explains itself**, with the same info marks the card uses.
- **The card reads properly at every width.** Chat names in Top chats now get a whole line to
  themselves with their bar underneath, so full titles fit instead of being cut to
  "Weebly m...redesign". Several rows had indents left over from chart layouts that no longer
  exist, which is why a lone model row sat pushed to the right and a chart's total hung in space
  away from the numbers it added up. The plan name in the header stays whole rather than shrinking
  while the word beside it stayed large.
- **One conversation, one row.** Claude Code starts a new log file when a chat is resumed or
  compacted, so a long piece of work appeared four or five times over with four different numbers.
  Those rows are added together now, with a count of how many logs it took. Chats with no title
  are never merged into each other, since their label is generated rather than their name.
- Big numbers read properly: a heavy week showed as "6972.0M" where it now says "7.0B".
- The card no longer contradicts itself: the token rate under the session number and the burn
  chart's headline read the same figure, and each model limit says "% left" in words rather than
  leaving a bar and a number to disagree.
- **The card no longer slows down while you use it.** Sixteen of the charts worked out their
  numbers from scratch every time the card redrew, which happens on the live tick and again on
  every mouse movement over a chart. On a long history that was most of a second of work,
  dozens of times a second, which is the sluggishness you could feel with the tokens-per-day
  chart on screen. Each chart now works out its numbers once and reuses them, and the daily
  roll-up itself is around 200 times faster.
- **Every model shows on the Session + week chart.** It used to draw a line only for models that
  have a weekly cap of their own, which on most accounts is one model, so Opus and Haiku simply
  had no line. Each line is now that model's share of your weekly allowance, so everything you
  use appears and the model lines add up to the week line. Click a name in the legend to hide
  its line, and it stays hidden until you bring it back.
- **The pace chart is readable.** The half-circle dial has been replaced by one strip each for
  the session and the week, so a comfortable week can no longer hide behind a busy session,
  with a line under each saying whether your current pace lasts to the reset or runs out before
  it. The stray white line across the old dial is gone with it.
- **Faded text is readable everywhere.** Every text colour in all 21 themes, light and dark, was
  measured against the accessibility contrast standard. 180 of those combinations fell short,
  the faintest greys worst of all. All of them now pass, and six themes also had a usage bar too
  close in colour to the groove behind it.
- **Chat names and renaming.** Hover a chat in "chats burning now" to read its full name, and
  click the pencil to rename it. Renaming had only ever been on the right-click menu, with
  nothing to tell you so, and the full name on hover never worked at all.
- **Chart explanations are complete.** In the chart gallery they were cut off after two lines,
  mid-sentence. They now show in full.
- **"Explain each section" is where you can find it**, at the top of the Popover pane instead of
  inside a collapsed drawer at the bottom.
- Sessions run from your home folder now say "Home folder" rather than "Home".
- **The small "?" marks in the card explain themselves again.** Clicking one now opens the
  explanation, the same way the ⓘ marks in Settings already did. Previously nothing happened at
  all, on click or on hover: the card's marks had never been given the tap behaviour the
  Settings ones got, and the hover tooltip they did have does not work inside the card.
  The card also stays open while you read, instead of closing under you.

## 0.9.3

- **Settings has been rebuilt around what you actually use.** The window used
  to open on a General pane holding twenty-six controls, most of which you set
  once and never touch again. Now every pane leads with the handful that
  matter and keeps the rest one click away in an Advanced drawer. Nothing was
  removed: every option that existed before is still there, still does the
  same thing, and your current settings carry over untouched.
- **A new Companions pane.** The floating window, the widget that attaches to
  the Claude window, and the screen-edge ember line have moved out of General
  into a pane of their own, one section each. General is down to the basics
  plus updates, and now also holds Export and Reset under Your data.
- **The menu bar pane leads with the styles worth trying.** Nine core styles
  are shown; the full library sits under All styles, which opens itself
  automatically if the style you are using lives in there, so your choice is
  never hidden. Number format and digit options moved into their own drawer.
- **Appearance is calm again.** The background section shows a live preview,
  the three styles and the five one-tap presets. The nine fine-tuning sliders
  are still all there, now behind Fine-tune background.
- **Alerts reads in the order you would set it up**: the levels first, then
  the extra warnings, then how alerts reach you, then a button to test one.
- **Popover size moved to the Popover pane**, where you would look for it.
- The window is slightly taller, section headings are consistent everywhere,
  and the whole thing was checked in both light and dark mode.

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
