#!/bin/bash
# Tests for the Foundation-pure formatting + chart-math helpers (Sources/Format.swift).
# Mirrors run-tests.sh: compile the self-contained logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-format-tests"

echo "→ Building format test binary (Format)"
swiftc -O -o "$OUT" Sources/Format.swift Tests/format/main.swift

echo "→ Running"
"$OUT"
