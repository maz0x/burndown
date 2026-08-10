#!/bin/bash
# Tests for the Foundation-pure usage-aggregation layer (Sources/Aggregation.swift),
# compiled together with Sources/Pricing.swift so cost math runs against the real rate
# table. Mirrors run-chartdata-tests.sh: one self-contained throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-aggregation-tests"

echo "→ Building aggregation test binary (Aggregation + Pricing)"
swiftc -O -o "$OUT" Sources/PrivateFile.swift Sources/Aggregation.swift Sources/SessionTitles.swift Sources/Pricing.swift Tests/aggregation/main.swift

echo "→ Running"
"$OUT"
