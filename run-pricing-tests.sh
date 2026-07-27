#!/bin/bash
# Tests for the Foundation-pure cost model (Sources/Pricing.swift).
# Mirrors run-tests.sh: compile the self-contained logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-pricing-tests"

echo "→ Building pricing test binary (Pricing)"
swiftc -O -o "$OUT" Sources/Pricing.swift Tests/pricing/main.swift

echo "→ Running"
"$OUT"
