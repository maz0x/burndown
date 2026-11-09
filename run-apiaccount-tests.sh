#!/bin/bash
# Tests for the Foundation-pure Developer API logic (Sources/APIAccount.swift).
# Mirrors run-pricing-tests.sh: compile the logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-apiaccount-tests"

echo "→ Building API account test binary (APIAccount)"
swiftc -O -o "$OUT" Sources/APIAccount.swift Tests/apiaccount/main.swift

echo "→ Running"
"$OUT"
