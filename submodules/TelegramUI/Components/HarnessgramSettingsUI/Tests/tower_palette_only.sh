#!/bin/bash
# Fails when a Cockpit, hosting boundary or Live Activity view bypasses its appearance palette.
set -eu
python3 - "$@" <<'PYTHON'
import pathlib
import re
import sys


def included(path):
    return (path.name not in {"HouseTowerPalette.swift", "HarnessgramTaskActivityPalette.swift"}
            and ("Cockpit" in path.parts or path.name in {
                "HarnessgramHostingScreen.swift", "HarnessgramTaskLiveActivity.swift", "HarnessgramFlightDeckViews.swift"}))


fixed_color = re.compile(r"harnessgramHex|Color\(red|UIColor\(red|HarnessgramRGB\(hex|Color\.black|UIColor\.black|Color\(\.black\)")
forced_dark = re.compile(r"colorScheme\s*,\s*\.dark|preferredColorScheme\s*\(\s*\.dark|overrideUserInterfaceStyle\s*=\s*\.dark")


def violations(source):
    # Keep line positions while ignoring comment lines. Appearance calls may wrap across lines.
    source = re.sub(r"(?m)^[ \t]*//[^\n]*", "", source)
    hits = []
    for match in fixed_color.finditer(source):
        line = source[source.rfind("\n", 0, match.start()) + 1:source.find("\n", match.end()) if "\n" in source[match.end():] else len(source)]
        if "shadow" not in line.lower():
            hits.append(match)
    hits.extend(forced_dark.finditer(source))
    return [(source.count("\n", 0, match.start()) + 1, match.group()) for match in hits]


# Positive and negative controls: all three spellings, multiline calls and the theme-driven hosting selection.
for source in [
    r".environment(\.colorScheme, .dark)",
    ".preferredColorScheme(.dark)",
    "controller.overrideUserInterfaceStyle = .dark",
    ".preferredColorScheme(\n    .dark\n)",
    "controller.overrideUserInterfaceStyle =\n    .dark",
    r".environment(\.colorScheme," + "\n    .dark)",
]:
    if not violations(source):
        sys.exit("forced-dark regression control was missed: " + source)
for source in [
    "controller.overrideUserInterfaceStyle = theme.overallDarkAppearance ? .dark : .light",
    "controller.overrideUserInterfaceStyle = dark ? .dark : .light",
    r".environment(\.colorScheme, dark ? .dark : .light)",
    ".preferredColorScheme(dark ? .dark : .light)",
    "// .preferredColorScheme(.dark)",
]:
    if violations(source):
        sys.exit("theme-driven appearance was rejected: " + source)
if not included(pathlib.Path("Sources/HarnessgramHostingScreen.swift")):
    sys.exit("hosting boundary is missing from the source filter")

if len(sys.argv) < 2:
    sys.exit("no sources given")
scanned = 0
hits = 0
for name in sys.argv[1:]:
    path = pathlib.Path(name)
    if not path.is_file():
        sys.exit("missing source: " + name)
    if not included(path):
        continue
    scanned += 1
    found = violations(path.read_text())
    if found:
        hits += 1
        for line, text in found:
            print(f"{name}:{line}: {text}: use a palette colour or theme-driven appearance", file=sys.stderr)
print(f"scanned {scanned} Cockpit, hosting and Live Activity views, {hits} with a palette violation")
if scanned < 8:
    sys.exit(f"too few views scanned ({scanned}): the glob is broken")
sys.exit(1 if hits else 0)
PYTHON
