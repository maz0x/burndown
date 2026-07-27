#!/bin/bash
# Tests for the Foundation-pure screen-time recap (Sources/Recap.swift).
# Mirrors run-chartdata-tests.sh: compile the self-contained logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-recap-tests"

echo "→ Building recap test binary (Recap)"
swiftc -O -o "$OUT" Sources/Recap.swift Sources/Aggregation.swift Sources/Pricing.swift Tests/recap/main.swift

echo "→ Running"
"$OUT"
