#!/bin/bash
# Tests for the Foundation-pure chart-data helpers (Sources/ChartData.swift).
# Mirrors run-tests.sh: compile the self-contained logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-chartdata-tests"

echo "→ Building chart-data test binary (ChartData)"
# Aggregation.swift comes along for modelFamily() and UsageRecord.totalTokens, which the
# per-model chart series depends on.
swiftc -O -o "$OUT" Sources/PrivateFile.swift Sources/ChartData.swift Sources/Aggregation.swift Sources/SessionTitles.swift Sources/Pricing.swift Tests/chartdata/main.swift

echo "→ Running"
"$OUT"

# Source policy: every Swift Charts plot goes through chartPlot(), which clips it.
#
# Swift Charts draws marks that fall outside the declared domain at extrapolated positions,
# OUTSIDE the plot, over whatever is next to them. That is not hypothetical: the week burndown
# trimmed to 6h painted its line and pace diagonal across the whole card. The clip lives in one
# shared modifier so a new chart cannot forget it, and this check is what keeps that true.
echo "→ Checking every chart plot is clipped"
# The directory is a variable so this gate can be proven non-vacuous: point CUB_CHART_SRC at a
# scratch copy of Sources carrying one unclipped Chart and the run must FAIL. Defaults to the
# real tree, so a normal run is unchanged.
CHART_SRC="${CUB_CHART_SRC:-Sources}"
# Trailing comments are stripped before the match rather than filtering whole doc-comment lines.
# Filtering on "///" cut both ways: real code that happened to sit on a line ending in a doc
# comment was excused, and a line that only NAMED chartPlotStyle in prose still had to be excused
# by hand. Strip from the first "//" and judge what is left.
BARE=$(grep -n "chartPlotStyle" "$CHART_SRC"/*.swift \
       | awk '{ code=$0; sub(/^[^:]*:[0-9]+:/, "", code); sub(/\/\/.*$/, "", code);
                if (code ~ /chartPlotStyle/) print }' \
       | grep -v "func chartPlot()" || true)
if [ -n "$BARE" ]; then
    echo "FAIL: chartPlotStyle used directly; use .chartPlot() so the plot is clipped:"
    echo "$BARE"
    exit 1
fi
# Counted across ALL of Sources, not just the chart files: this check found the Insights window's
# daily-tokens chart, which had been drawing unclipped for as long as it has existed.
#
# The pattern matches Chart followed by "{" OR "(", so the initialiser forms count too:
# `Chart(rows) {`, `Chart(data, id: \.id) {` and `Chart(rows, id: \.day) {` were all invisible to
# the old `^ *Chart {`, which only saw the bare trailing-closure form on its own line. The leading
# class keeps it from matching inside a longer name (MonitorChart(, TopChatsChart(), and whole
# comment lines are dropped so a Chart named in prose is not counted as one drawn.
CHARTS=$(grep -hE '(^|[^A-Za-z0-9_.])Chart[[:space:]]*[({]' "$CHART_SRC"/*.swift \
         | grep -vE '^[[:space:]]*//' | wc -l | tr -d ' ' || true)
PLOTS=$(grep -h "\.chartPlot()" "$CHART_SRC"/*.swift | grep -v "func chartPlot()" | wc -l | tr -d ' ' || true)
if [ "$CHARTS" -ne "$PLOTS" ]; then
    echo "FAIL: $CHARTS Chart bodies but $PLOTS clipped plots. Every Chart needs .chartPlot()."
    exit 1
fi
echo "✓ $CHARTS chart plots, all clipped"
