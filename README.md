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
