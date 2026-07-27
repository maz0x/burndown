#!/bin/bash
# Tests for the Foundation-pure weekly pacing advisor (Sources/Pacing.swift).
# Mirrors run-chartdata-tests.sh: compile the self-contained logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-pacing-tests"

echo "→ Building pacing test binary (Pacing)"
swiftc -O -o "$OUT" Sources/Pacing.swift Tests/pacing/main.swift

echo "→ Running"
"$OUT"
