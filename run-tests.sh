#!/bin/bash
# Unit tests for Burndown's pure logic. No Xcode / SwiftPM needed: we compile the
# self-contained logic files together with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-tests"

echo "→ Building test binary (Forecast)"
swiftc -O -o "$OUT" Sources/Forecast.swift Tests/main.swift

echo "→ Running"
"$OUT"
