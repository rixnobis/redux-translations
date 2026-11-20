#!/bin/sh
# Assemble the Mega Man X4 archive for PCSX-Redux.
#   make-zip.sh <unpacked patch dir> <mmx4-hack.lua> <output.zip>
# The patch dir is the French patch unpacked: FONT.BIN, PL00.BIN, PL01.BIN and
# SUBS-US/<movie>/{index.lua,sub-N.rgba}, and INTRO/ for the credits intro.
set -e
paq=$1
hack=$2
out=$3
[ -d "$paq/SUBS-US" ] && [ -f "$hack" ] && [ -n "$out" ] || {
    echo "usage: $0 <unpacked patch dir> <mmx4-hack.lua> <output.zip>" >&2
    exit 1
}
here=$(cd "$(dirname "$0")/.." && pwd)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp "$here"/autoexec.lua "$here"/mmx4-index.lua "$here"/mmx4-disc.lua \
   "$here"/mmx4-str.lua "$here"/mmx4-intro.lua "$here"/mmx4-build.lua "$here"/../common/reader.lua "$stage/"
for f in FONT.BIN PL00.BIN PL01.BIN; do
    cp "$paq/$f" "$stage/"
done
cp -r "$paq/SUBS-US" "$stage/"
[ -d "$paq/INTRO" ] && cp -r "$paq/INTRO" "$stage/"
luajit "$here/tools/extract-hacks.lua" "$hack" "$stage/slus-hacks.lua"
mkdir -p "$(dirname "$out")"
out=$(cd "$(dirname "$out")" && pwd)/$(basename "$out")
rm -f "$out"
(cd "$stage" && zip -qr "$out" .)
echo "wrote $out ($(ls "$stage"/SUBS-US | wc -l) movies)"
