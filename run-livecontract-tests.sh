#!/bin/bash
# Tests for the Foundation-pure live JSON contract (Sources/LiveContract.swift).
# Mirrors run-chartdata-tests.sh: compile the self-contained logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-livecontract-tests"

echo "→ Building live-contract test binary (LiveContract)"
swiftc -O -o "$OUT" Sources/LiveContract.swift Tests/livecontract/main.swift

echo "→ Running"
"$OUT"
