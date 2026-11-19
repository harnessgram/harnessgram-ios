#!/bin/bash
# usage: filled_widget_controls.sh <swift files...>  - fails when a widget or Live Activity source draws a white label (a filled control) without reading widgetRenderingMode
# Build 30 report: in the tinted, Clear and lock-screen looks iOS draws every colour in one tone, so a white label on a
# coloured fill became a blank white pill. A source that sets a white foreground must branch on \.widgetRenderingMode
# (the full-colour look keeps the fill; the others draw an outline or a tint in the label's tone). Comment lines are skipped.
set -u
[ "$#" -gt 0 ] || { echo "no sources given" >&2; exit 2; }
scanned=0
hits=0
for f in "$@"; do
  [ -f "$f" ] || { echo "missing source: $f" >&2; exit 2; }
  scanned=$((scanned + 1))
  white=$(grep -n -E '(foregroundStyle|foregroundColor)\(.*(Color\.white|\(\.white|[ ?:]\.white)' "$f" | grep -v -E '^[0-9]+:[[:space:]]*//')
  if [ -n "$white" ] && ! grep -q 'widgetRenderingMode' "$f"; then
    echo "$white"
    echo "  ^ in $f: a white label needs a variant for the accented and vibrant looks (read @Environment(\\.widgetRenderingMode))" >&2
    hits=$((hits + 1))
  fi
done
echo "scanned $scanned widget sources, $hits with a white label and no rendering-mode variant"
[ "$scanned" -ge 4 ] || { echo "too few sources scanned ($scanned): the glob is broken" >&2; exit 3; }
[ "$hits" -eq 0 ]
