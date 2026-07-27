#!/bin/bash
# Tests for the Foundation-pure budget logic (Sources/Budget.swift).
# Mirrors run-chartdata-tests.sh: compile the self-contained logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-budget-tests"

echo "→ Building budget test binary (Budget)"
swiftc -O -o "$OUT" Sources/Budget.swift Tests/budget/main.swift

echo "→ Running"
"$OUT"
