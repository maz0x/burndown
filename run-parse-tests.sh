#!/bin/bash
# Golden-fixture tests for the Foundation-pure parsers: parseISO + clampPct (Sources/Parsing.swift) and the
# usage-service reader, live-cache codec and plan names (Sources/UsageParse.swift).
# Mirrors run-tests.sh: compile the self-contained logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-parse-tests"

echo "→ Building parse test binary (Parsing + UsageParse)"
swiftc -O -o "$OUT" Sources/Parsing.swift Sources/UsageParse.swift Tests/parse/main.swift

echo "→ Running"
"$OUT"
