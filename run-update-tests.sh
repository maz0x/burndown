#!/bin/bash
# Tests for the pure update logic in Sources/Updater.swift (version compare, release parsing,
# checksum extraction, dev-checkout detection). The impure half (download, verify, swap) is
# exercised by the real end-to-end install, not here.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(mktemp -d)/burndown-update-tests"
SRC="$(mktemp -d)/UpdateLogic.swift"

# Extract just the Foundation-pure section so the test binary needs no AppKit/SwiftUI.
awk '/^\/\/ MARK: - Pure logic/,/^\/\/ MARK: - The updater/' Sources/Updater.swift \
  | sed '$d' > "$SRC"
sed -i '' '1i\
import Foundation
' "$SRC"

echo "→ Building update test binary (UpdateLogic)"
swiftc -O -o "$OUT" "$SRC" Tests/update/main.swift

echo "→ Running"
"$OUT"
