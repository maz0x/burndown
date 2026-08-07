#!/bin/bash
# Tests for the Foundation-pure chart-data helpers (Sources/ChartData.swift).
# Mirrors run-tests.sh: compile the self-contained logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-chartdata-tests"

echo "→ Building chart-data test binary (ChartData)"
# Aggregation.swift comes along for modelFamily() and UsageRecord.totalTokens, which the
# per-model chart series depends on.
swiftc -O -o "$OUT" Sources/ChartData.swift Sources/Aggregation.swift Sources/SessionTitles.swift Sources/Pricing.swift Tests/chartdata/main.swift

echo "→ Running"
"$OUT"
