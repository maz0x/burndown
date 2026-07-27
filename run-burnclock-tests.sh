#!/bin/bash
# Tests for the Foundation-pure One Pulse clock (Sources/BurnClock.swift).
set -euo pipefail
cd "$(dirname "$0")"
OUT="$(mktemp -d)/burndown-burnclock-tests"
echo "→ Building burnclock test binary"
swiftc -O -o "$OUT" Sources/BurnClock.swift Tests/burnclock/main.swift
echo "→ Running"
"$OUT"
