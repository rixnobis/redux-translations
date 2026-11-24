# redux-translations

Translation editors for [PCSX-Redux](https://github.com/pcsx-redux/pcsx-redux),
packaged as Lua archives. Load your own disc, then File > Add Lua archive (or
`-archive parasite-eve.zip` on the command line). The archive's `autoexec.lua`
opens an editor window that decodes the game's text through `PCSX.TextTable`
and writes a new `.bin`/`.cue` through `PCSX.isoBuilder`.

Each game folder has a README walking through its files, and `common/` holds the
modules they share. There is only code in this repository. The zips on the releases page add a finished
translation as the worked example; the disc is never included.

## Parasite Eve (USA)

Works on Disc 1 (`SLUS_006.62`) and Disc 2 (`SLUS_006.68`). "Scan disc" reads
the 438-room table from the executable and lists the 20 script files; pick one,
edit it as text, press "Apply", then "Build disc". `PE.IMG` is laid out again
from scratch, so a room whose text grows simply moves: the French Disc 1 comes
out 181 sectors longer than the original.

The release zip carries the 2004 French translation (text by Torakami, patcher
by Nicolas "Pixel" Noble): the 20 scripts, the font and menu files, and the
executable patches, which `tools/extract-hacks.lua` pulls out of the original
`pe-hack.lua`. `tools/make-zip.sh` rebuilds the zip from those inputs.

## Mega Man X4 (USA)

Works on `SLUS_005.61`. There is nothing to edit: the 2004 French patch is a
finished translation, so "Scan disc" then "Build disc" applies it and writes a
new image. The game loads its files by a hardcoded sector table in the
executable rather than through the filesystem, so the rebuild rewrites that
table to match the new layout. The nine story movies get French subtitles burned
into their FMVs through `PCSX.MDEC`: each subtitled frame is decoded, the
overlay is alpha-blitted over it, and the frame is re-encoded to fit the sectors
it already used.

The release zip carries the 2004 French patch (Génération IX): the font and
player archives, the executable patches, and the subtitle overlays. The intro
rebuild (`create_intro`) and the Japanese-audio option are not ported; see
`mmx4/README.md`.

## Valkyrie Profile (USA)

Works on Disc 1 (`SLUS_011.56`). The archive opens a browser over every file
on the disc and a Translate tab on each room script, backed by a sqlite
translation database, plus the same tool as a web page (`-webserver`, then
`/api/v1/lua/vp`). With "Show translations in game" ticked, a saved line shows
in the game's own textbox the next time the game loads that room. See
`valkyrie-profile/README.md`.
