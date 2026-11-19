#!/bin/bash
# usage: no_bordered_prominent.sh <swift files...>  - fails when a Harnessgram UI source uses the system bordered-prominent button style (use .harnessgramFilled)
# Build 23 report: inside a List/Form row that style showed a light-blue label and icon on a blue fill. Comment lines are skipped.
set -u
[ "$#" -gt 0 ] || { echo "no sources given" >&2; exit 2; }
scanned=0
hits=0
for f in "$@"; do
  [ -f "$f" ] || { echo "missing source: $f" >&2; exit 2; }
  scanned=$((scanned + 1))
  if grep -n -E 'borderedProminent|BorderedProminentButtonStyle' "$f" | grep -v -E '^[0-9]+:[[:space:]]*//' ; then
    echo "  ^ in $f: use .buttonStyle(.harnessgramFilled) instead" >&2
    hits=$((hits + 1))
  fi
done
echo "scanned $scanned Harnessgram UI sources, $hits with the bordered-prominent style"
[ "$scanned" -ge 10 ] || { echo "too few sources scanned ($scanned): the glob is broken" >&2; exit 3; }
[ "$hits" -eq 0 ]
