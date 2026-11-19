#!/bin/bash
# usage: make-house-assets.sh <source art dir> - rebuilds Resources/HarnessgramHouse.xcassets; downscales only, with sips
# The catalog ships the DEFAULT art; the owner's replacement lives in the app group (HouseArtStore). Header masters, large radio and empty states ship @2x only (the system scales them up on @3x) to keep the repo small.
set -euo pipefail
SRC="${1:?usage: make-house-assets.sh <source art dir>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/HarnessgramHouse.xcassets"
[ -d "$SRC" ] || { echo "make-house-assets: source art dir not found: $SRC" >&2; exit 2; }
command -v sips >/dev/null || { echo "make-house-assets: sips is required (macOS)" >&2; exit 2; }
# The bundled square control-tower artwork; an explicit environment value may select a different source.
TOWER="${HOUSE_RADIO_TOWER:-$SRC/radio-tower.png}"
[ -f "$TOWER" ] || { echo "make-house-assets: missing $TOWER (set HOUSE_RADIO_TOWER)" >&2; exit 2; }
rm -rf "$OUT"
mkdir -p "$OUT/House"
printf '{\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' > "$OUT/Contents.json"
group() { # <relative dir> : a namespaced folder
    mkdir -p "$OUT/$1"
    printf '{\n  "info" : { "author" : "xcode", "version" : 1 },\n  "properties" : { "provides-namespace" : true }\n}\n' > "$OUT/$1/Contents.json"
}
group House
for g in Rooms RoomCards Radio Windows Empty; do group "House/$g"; done
# imageset <group> <name> <source png> <@2x width> <@2x height> <with @3x: yes|no>
imageset() {
    local dir="$OUT/House/$1/$2.imageset" src="$SRC/$3" w2="$4" h2="$5" three="$6"
    [ -f "$src" ] || { echo "make-house-assets: missing $src" >&2; exit 2; }
    mkdir -p "$dir"
    sips -z "$h2" "$w2" "$src" --out "$dir/$2@2x.png" >/dev/null
    local images='    { "idiom" : "universal", "filename" : "'"$2"'@2x.png", "scale" : "2x" }'
    if [ "$three" = yes ]; then
        sips -z "$((h2 * 3 / 2))" "$((w2 * 3 / 2))" "$src" --out "$dir/$2@3x.png" >/dev/null
        images="$images"',
    { "idiom" : "universal", "filename" : "'"$2"'@3x.png", "scale" : "3x" }'
    fi
    printf '{\n  "images" : [\n%s\n  ],\n  "info" : { "author" : "xcode", "version" : 1 },\n  "properties" : { "compression-type" : "lossy" }\n}\n' "$images" > "$dir/Contents.json"
}
for room in room-gesher room-project-a room-project-b room-project-c room-new life-yoman life-bayit life-reshatot life-projects; do
    imageset Rooms "$room" "$room.png" 780 520 no
    imageset RoomCards "$room-card" "$room.png" 264 176 yes
done
# The radio art is 3:2 (not square): the bar draws it aspect-fit at 44 pt high.
for state in playing paused; do
    imageset Radio "radio-$state-bar" "radio-$state.png" 132 88 yes
    imageset Radio "radio-$state-large" "radio-$state.png" 480 320 no
done
mkdir -p "$OUT/House/Radio/radio-tower.imageset"
sips -z 600 600 "$TOWER" --out "$OUT/House/Radio/radio-tower.imageset/radio-tower@2x.png" >/dev/null
sips -z 900 900 "$TOWER" --out "$OUT/House/Radio/radio-tower.imageset/radio-tower@3x.png" >/dev/null
printf '{\n  "images" : [\n    { "idiom" : "universal", "filename" : "radio-tower@2x.png", "scale" : "2x" },\n    { "idiom" : "universal", "filename" : "radio-tower@3x.png", "scale" : "3x" }\n  ],\n  "info" : { "author" : "xcode", "version" : 1 },\n  "properties" : { "compression-type" : "lossy" }\n}\n' > "$OUT/House/Radio/radio-tower.imageset/Contents.json"
for state in lit dark; do
    imageset Windows "window-$state-20" "window-$state.png" 40 40 yes
    imageset Windows "window-$state-44" "window-$state.png" 88 88 yes
done
imageset Empty empty-waiting empty-waiting.png 600 400 no
imageset Empty empty-rooms empty-rooms.png 600 400 no
# The widget extension gets only what a widget draws (the 44 pt windows), as its own small catalog.
WOUT="$HERE/HarnessgramHouseWidget.xcassets"
rm -rf "$WOUT"
mkdir -p "$WOUT/House/Windows"
cp "$OUT/Contents.json" "$WOUT/Contents.json"
cp "$OUT/House/Contents.json" "$WOUT/House/Contents.json"
cp "$OUT/House/Windows/Contents.json" "$WOUT/House/Windows/Contents.json"
for state in lit dark; do cp -R "$OUT/House/Windows/window-$state-44.imageset" "$WOUT/House/Windows/"; done
du -sk "$OUT" | awk '{printf "make-house-assets: %d KB written to HarnessgramHouse.xcassets\n", $1}'
