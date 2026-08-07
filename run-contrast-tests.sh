#!/bin/bash
# WCAG contrast regression. Builds nothing: it drives the app's own CUB_CONTRAST audit, which reads
# the real Palette.of(), so this can never pass against a palette table that no longer ships.
#
# Any new theme, or any hand-edited hex, has to clear WCAG AA for every pairing the app draws.
set -euo pipefail
cd "$(dirname "$0")"
APP=./Burndown.app/Contents/MacOS/Burndown
[ -x "$APP" ] || { echo "build first: bash build.sh"; exit 1; }
OUT=docs/contrast-audit.csv
CUB_CONTRAST="$PWD/$OUT" "$APP" | tee /tmp/burndown-contrast.txt
FAILS=$(grep -c ',FAIL$' "$OUT" || true)
if [ "$FAILS" != "0" ]; then
  echo; echo "$FAILS FAILURE(S) - see $OUT"; grep ',FAIL$' "$OUT" | head -20; exit 1
fi
echo "ALL PASS"
