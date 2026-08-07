#!/bin/bash
# Tests for the Foundation-pure time-to-limit forecast helpers (Sources/Forecast.swift).
# Mirrors run-tests.sh: compile the self-contained logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-forecast-tests"

echo "→ Building forecast test binary (Forecast)"
swiftc -O -o "$OUT" Sources/Forecast.swift Sources/Format.swift Tests/forecast/main.swift

echo "→ Running"
"$OUT"
