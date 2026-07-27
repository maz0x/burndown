#!/bin/bash
# Golden-fixture tests for the Foundation-pure parsers (parseISO + clampPct in Sources/Parsing.swift).
# Mirrors run-tests.sh: compile the self-contained logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-parse-tests"

echo "→ Building parse test binary (Parsing)"
swiftc -O -o "$OUT" Sources/Parsing.swift Tests/parse/main.swift

echo "→ Running"
"$OUT"
