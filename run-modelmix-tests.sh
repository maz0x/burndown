#!/bin/bash
# Tests for the Foundation-pure model-mix advisor (Sources/ModelMix.swift).
# Mirrors run-chartdata-tests.sh: compile the self-contained logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-modelmix-tests"

echo "→ Building model-mix test binary (ModelMix)"
swiftc -O -o "$OUT" Sources/ModelMix.swift Tests/modelmix/main.swift

echo "→ Running"
"$OUT"
