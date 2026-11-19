#!/bin/sh
# Assemble the Parasite Eve archive for PCSX-Redux.
#   make-zip.sh <unpacked patch dir> <pe-hack.lua> <output.zip>
# The patch dir is the French patch's .paq unpacked (scripts/, font.tim, ...).
set -e
paq=$1
hack=$2
out=$3
[ -d "$paq/scripts" ] && [ -f "$hack" ] && [ -n "$out" ] || {
    echo "usage: $0 <unpacked patch dir> <pe-hack.lua> <output.zip>" >&2
    exit 1
}
here=$(cd "$(dirname "$0")/.." && pwd)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/scripts"
cp "$here"/autoexec.lua "$here"/pe.lua "$here"/pe-groups.lua "$here"/pe-build.lua \
   "$here"/pe-pack.lua "$here"/pe.tbl "$stage/"
cp "$paq"/scripts/*.bin "$stage/scripts/"
for f in various.bin menus.bin font.tim mainmenu.bin names.tim map.bin; do
    cp "$paq/$f" "$stage/"
done
luajit "$here/tools/extract-hacks.lua" "$hack" "$stage/slus-hacks.lua"
out=$(cd "$(dirname "$out")" && pwd)/$(basename "$out")
rm -f "$out"
(cd "$stage" && zip -qr "$out" .)
echo "wrote $out ($(ls "$stage/scripts" | wc -l) scripts)"
