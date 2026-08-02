#!/bin/bash
# Tests for the corner-drag resize math (Sources/CardResize.swift): the drag -> scale mapping
# behind the popover / floating card resize grip, and its clamping to the slider's limits.
# Mirrors run-tests.sh: compile the self-contained logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-cardresize-tests"

echo "→ Building card-resize test binary (CardResize)"
swiftc -O -o "$OUT" Sources/CardResize.swift Tests/cardresize/main.swift

echo "→ Running"
"$OUT"
