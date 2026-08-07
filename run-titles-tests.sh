#!/bin/bash
# Chat naming rules: what counts as a raw session id, how a harvested title is tidied, and what a
# chat with no title is called. The rule these protect: a UUID must never reach the reader.
set -euo pipefail
cd "$(dirname "$0")"
OUT="$(mktemp -d)/TitlesTests"
echo "→ Building title test binary (SessionTitles)"
swiftc -O -o "$OUT" Sources/SessionTitles.swift Tests/titles/main.swift
echo "→ Running"
"$OUT"
