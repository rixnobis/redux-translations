# Parasite Eve (USA), file by file

This folder is a worked example of a translation tool running inside
PCSX-Redux: it finds the game's text on the disc, lets you edit it, and writes
a new disc image. Read the files in this order.

## How the game stores its text

Almost everything lives in one big file, `PE.IMG`. The executable
(`SLUS_006.62` on Disc 1, `SLUS_006.68` on Disc 2) holds the tables saying
where things sit inside it, as sector numbers:

- a room table of 438 eight-byte entries at `0x83b78`: the room's first sector,
  then the sizes in sectors of its three parts, packed as 8 + 12 + 12 bits;
- a misc file table of 80 sixteen-bit sector numbers at `0x838da` (fonts,
  menus, the map), followed by the music.

The third part of a room holds its code and data, including the script: the
dialogue, as bytes that `pe.tbl` maps to characters. Twenty script files
exist, and several rooms share each one (`pe-groups.lua` lists which).
Inside a room, pointers keep a tag in their top 12 bits and a byte offset in
the low 20, and a longer script pushes everything after it, so changing the
text means moving that data and fixing every pointer that crosses the script.

## The files

- `../common/reader.lua` reads and writes little-endian numbers at byte
  offsets in strings, ffi buffers, and Redux's `LuaBuffer` and `Slice`. The
  other files read the disc through it. `../common/reader-test.lua` is its test.
- `pe.lua` is the room format: `PE.scriptInfo` finds a room's script,
  `PE.roomScript` extracts it, `PE.patchRoom` puts a new one in. It works on
  plain strings and calls nothing from Redux, so it can be tried on room dumps
  with no disc loaded.
- `pe-disc.lua` is the disc side: `open(PCSX.getCurrentIso())` checks the disc
  is Parasite Eve, reads the executable's room table, and reads rooms out of
  `PE.IMG` through Redux's ISO reader.
- `pe-build.lua` writes a whole new disc through `PCSX.isoBuilder`. It copies
  the disc file by file, lays `PE.IMG` out again with the new scripts and
  files, and rewrites the executable's tables to match. Movie and audio files
  are copied with their raw Mode 2 sectors so they keep playing.
- `pe-pack.lua` loads the rest of a translation pack: the replacement font,
  menus and map, and the executable patches.
- `autoexec.lua` runs when Redux mounts the archive. It loads the other files,
  decodes the scripts through `PCSX.TextTable` with `pe.tbl`, and draws the
  editor window with `PCSX.FileViewers.textViewer`.
- `tools/` holds helpers: `make-zip.sh` assembles the release zip, `extract-hacks.lua`
  converts the 2004 patcher's executable patches, `press-plan.lua` is a test helper.

## Trying it

Mount the zip from the releases page with a Parasite Eve (USA) disc loaded,
press "Scan disc", pick a script and edit it, then press "Apply" under the
text so the edit is kept, and "Build disc" to write the new image. The same functions are reachable
from the Lua console through the `ParasiteEve` global, for example
`ParasiteEve.scan()` then `ParasiteEve.build('/tmp/pe.bin')`.

The code uses the C-style bit operators (`&`, `|`, `<<`, `>>`, `~`) that
Redux's LuaJIT accepts. A stock LuaJIT does not parse them, so run the files
through Redux: `pcsx-redux -cli -dofile <script.lua>` works without a window.
`<<` gives a signed 32-bit result, so a value with bit 31 set reads back
negative; read 32-bit fields through `reader.u32`, which returns them unsigned.
