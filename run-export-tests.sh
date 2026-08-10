#!/bin/bash
# Tests for the Foundation-pure export helpers (Sources/Export.swift).
# Mirrors run-chartdata-tests.sh: compile the self-contained logic file with its real dependencies
# (Aggregation + Pricing) and the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-export-tests"

echo "→ Building export test binary (Export)"
swiftc -O -o "$OUT" Sources/PrivateFile.swift Sources/Export.swift Sources/Aggregation.swift Sources/SessionTitles.swift Sources/Pricing.swift Sources/Format.swift Tests/export/main.swift

echo "→ Running"
"$OUT"
