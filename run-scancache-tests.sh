#!/bin/bash
# The full-history scan's on-disk cache: round trip, compactness, and refusing anything it cannot
# trust. A cache that half-decodes would put wrong numbers on screen, so every failure path must
# return nil and let the scan rebuild.
set -euo pipefail
cd "$(dirname "$0")"
OUT="$(mktemp -d)/ScanCacheTests"
echo "→ Building scan-cache test binary (ScanCache)"
swiftc -O -o "$OUT" Sources/ScanCache.swift Tests/scancache/main.swift
echo "→ Running"
"$OUT"
