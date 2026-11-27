#!/bin/bash
# Tests for the Foundation-pure reader of the bundled documents (Sources/DocBlocks.swift).
# Mirrors run-recap-tests.sh: compile the self-contained logic file with the test harness into a throwaway binary.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-docblocks-tests"

echo "→ Building docblocks test binary (DocBlocks)"
swiftc -O -o "$OUT" Sources/DocBlocks.swift Tests/docblocks/main.swift

echo "→ Running"
"$OUT"
