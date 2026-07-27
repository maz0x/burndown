#!/bin/bash
# Tests for the Foundation-pure adaptive runaway-burn detection (Sources/Runaway.swift).
# Mirrors run-chartdata-tests.sh: compile the self-contained logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-runaway-tests"

echo "→ Building runaway test binary (Runaway)"
swiftc -O -o "$OUT" Sources/Runaway.swift Tests/runaway/main.swift

echo "→ Running"
"$OUT"
