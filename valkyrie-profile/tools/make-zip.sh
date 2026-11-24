#!/bin/sh
# Assemble vp-translate.zip, the Valkyrie Profile editor as a PCSX-Redux archive.
#   make-zip.sh <font-database.lua> <output.zip>
# font-database.lua is the game's font with a character per glyph; it is game
# data, so it is an input here and never part of the repository.
set -e
font=$1
out=$2
[ -f "$font" ] && [ -n "$out" ] || {
    echo "usage: $0 <font-database.lua> <output.zip>" >&2
    exit 1
}
here=$(cd "$(dirname "$0")/.." && pwd)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
(cd "$here" && ls *.lua translate-web.js | grep -v -e '-test\.lua$' -e '-gen\.lua$' -e '^main\.lua$' -e '^font-database\.lua$') |
    while read -r f; do cp "$here/$f" "$stage/"; done
cp "$font" "$stage/font-database.lua"
mkdir "$stage/common"
for f in "$here"/../common/*.lua; do
    case "$f" in *-test.lua) ;; *) cp "$f" "$stage/common/" ;; esac
done
mkdir -p "$(dirname "$out")"
out=$(cd "$(dirname "$out")" && pwd)/$(basename "$out")
rm -f "$out"
(cd "$stage" && zip -q -X -9 -r -D "$out" .)
echo "wrote $out ($(find "$stage" -type f | wc -l) files)"
