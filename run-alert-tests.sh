#!/bin/bash
# Behavioral tests for the pure alert decision logic (Sources/AlertLogic.swift).
# Mirrors run-tests.sh: compile the self-contained logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-alert-tests"

echo "→ Building alert test binary (AlertLogic)"
swiftc -O -o "$OUT" Sources/AlertLogic.swift Tests/alert/main.swift

echo "→ Running"
"$OUT"
