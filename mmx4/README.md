# Mega Man X4 (USA), file by file

This folder is a worked example of a translation tool running inside
PCSX-Redux. Unlike Parasite Eve, the text here is not edited on the disc: the
2004 French patch is a finished translation, and the archive's job is to apply
it to a disc the player loads, writing a new `.bin`/`.cue`. The most interesting
part is the movies, whose French subtitles are burned into the FMVs through
`PCSX.MDEC`. Read the files in this order.

## How the game stores its data

The game does not find its files through the ISO9660 filesystem. The executable
(`SLUS_005.61`) holds a table at `0xe1618` of 163 entries, each three 32-bit
words: the file's first sector, its size, and a flag word. Entries 0..159 are
the `ARC`, `STR` and `XA` files in a fixed order; 160..162 are `SYSTEM.CNF`, the
executable and `ZNULL.DAT`. The game loads by these hardcoded sector numbers, so
a rebuilt disc has to rewrite the table to match where every file lands.

- `ARC` files are small archives: a count, a size, then one (flags, size) pair
  per subfile, with the subfiles following, each padded to a sector. The French
  patch rebuilds four of them to drop in a new font and player graphics.
- `STR` files are movies, stored as raw Mode 2 sectors (2336 bytes each): a
  32-byte chunk header then 2016 bytes of frame data, a frame being the
  concatenation of its chunks. The patch re-encodes the subtitled frames.
- `XA` files are audio, copied through untouched.

The size field counts bytes for an ARC, but 2336 per sector for a stream.

## The files

- `../common/reader.lua` reads and writes little-endian numbers at byte offsets
  in strings, buffers and Redux's `LuaBuffer` and `Slice`. The others read the
  disc through it.
- `mmx4-index.lua` is pure structure, generated from the patcher: the table's
  160 file names, which ARC gets which replacement subfile, and which movie
  gets which subtitles. It carries no translated content, so it lives here.
- `mmx4-disc.lua` is the disc side: `open(PCSX.getCurrentIso())` checks the disc
  is Mega Man X4 (USA), reads the 163-entry file table, and reads any entry as
  bytes.
- `mmx4-str.lua` is the movie format: `process` walks a movie's sectors, and for
  a frame the subtitle index names, decodes it with `PCSX.MDEC`, alpha-blits the
  RGBA overlay at its position, and re-encodes it to fit the sectors it used.
  Audio, empty and unsubtitled frames pass through byte for byte.
- `mmx4-intro.lua` is the credits intro that replaces the Capcom logo movie:
  it plays the patch's timeline of still pictures and effects at 15 frames a
  second, encodes each frame with `PCSX.MDEC`, interleaves the intro's XA
  soundtrack, and appends `CAPCOM20.STR` with its frames renumbered.
- `mmx4-build.lua` writes a whole new disc through `PCSX.isoBuilder`. It copies
  the disc file by file, rebuilds the four ARC archives and the subtitled
  movies, applies the executable patches, and -- once `close()` has placed every
  file -- rewrites the executable's table so each entry points at its new LBA.
- `autoexec.lua` runs when Redux mounts the archive. It loads the other files
  and draws the "Mega Man X4" window.
- `tools/` holds helpers: `make-zip.sh` assembles the release zip, and
  `extract-hacks.lua` pulls the patcher's executable patches and file-table
  shape out of the original `mmx4-hack.lua`.

The release zip adds the 2004 French patch (Génération IX): the font and player
files, the executable patches, the subtitle overlays for the nine movies, and
the intro's pictures and soundtrack. The disc is never included.

## Trying it

Mount the zip from the releases page with a Mega Man X4 (USA) disc loaded, press
"Scan disc", then "Build disc" to write the translated image. The same is
reachable from the Lua console through the `MegaManX4` global, for example
`MegaManX4.scan()` then `MegaManX4.build('/tmp/mmx4-fr.bin')`.

The code uses the C-style bit operators (`&`, `|`, `<<`, `>>`, `~`) Redux's
LuaJIT accepts; it does not use the `//` operator, which that LuaJIT rejects.
Run the files through Redux, not a stock LuaJIT.

## What the patch does, and what is skipped

- The font (`LOAD_U.ARC`) and the three player archives (`PL00/01/02_U.ARC`) are
  rebuilt with the translated graphics.
- The nine story movies (`X1_U`..`X4_U`, `Z1_U`..`Z5_U`) get French subtitles.
- The executable's three code patches hook the text renderer.
- `CAPCOM20.STR` becomes the credits intro followed by the Capcom logo, and the
  executable's frame count for it (at `0xe2508`) is raised to match.
- The Japanese-audio option (`videos_jap`, which swaps the movie soundtracks and
  uses the Japanese subtitle set) is **not** ported: none of the nine story
  movies has as many audio sectors as its Japanese XA file holds. The
  Japanese-disc path is not supported either, as in the original (it errors
  out).
