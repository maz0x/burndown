#!/bin/bash
# Tests for the Foundation-pure usage-fetch scheduling rule (Sources/FetchSchedule.swift).
# Mirrors run-livecontract-tests.sh: compile the self-contained logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-fetchschedule-tests"

echo "→ Building fetch-schedule test binary (FetchSchedule)"
swiftc -O -o "$OUT" Sources/FetchSchedule.swift Tests/fetchschedule/main.swift

echo "→ Running"
"$OUT"
