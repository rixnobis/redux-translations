# Valkyrie Profile (USA), file by file

A translation editor for Valkyrie Profile running inside PCSX-Redux: a browser
over the disc's files, a Translate tab per room script backed by a sqlite
translation database, the same tool as a web page served by Redux, and a
preview that shows a saved translation in the game's own textbox.

The release zip is built by `tools/make-zip.sh <font-database.lua> <out.zip>`.
`font-database.lua` is the game's font with the character each glyph stands
for; it is game data, so it ships in the zip and never in this repository.
To run from a source tree, put a copy next to `browser.lua`.

## How the game stores its text

Every file sits in one index, two XOR-scrambled tables at sectors 150 and 160
(`index.lua`). Most files are SLZ containers (`slz.lua`). Rooms are `.arm`
archives under `GAME/ROOMS`; a room's tag-4 member holds its script (logic,
a pointer table, then the strings) in chunk 0 and a font with only the glyphs
that room uses in chunk 1. A string is a stream of glyph indices into that
font, mixed with control codes (`text.lua`, documented in `tags.lua`).

## The files

- `browser.lua` loads everything else and draws the disc browser;
  `autoexec.lua` is what the zip runs when mounted.
- `vfs.lua` is the lazy tree of the disc; `arcgfx.lua`, `carc.lua`,
  `cscript.lua`, `filemap.lua` and `index.lua` read the containers.
- `text.lua` decodes strings to tokens and encodes them back; `room.lua`,
  `scripts.lua` and `disasm.lua` read room scripts and their text boxes.
- `font.lua`, `glyphs.lua`, `languages.lua` and `fontedit.lua` handle glyphs
  and the letters each target language adds.
- `tdb.lua` is the translation database: strings keyed by a hash of the
  retail script, versioned writes, history, and edited glyphs.
- `translate-model.lua` is shared by the two views: `translate.lua` (the
  ImGui tab) and `translate-web.lua` with `translate-web.js` (the web page).
  `glyph-editor.lua` and `translate-web-glyphs.lua` are the glyph editors.
- `preview.lua` rebuilds a room script from the database and patches it into
  RAM when the game loads that room, so a translation shows in game with no
  disc rebuild.
- `build.lua` writes a new disc through `PCSX.isoBuilder`: every file stays
  where the retail disc has it, each room archive the database changes is
  rebuilt and written after the end of `VALKYRIE.BIN`, and its index entry
  is pointed there. `build-test.lua` builds one and reads it back, and
  `preview-ingame-test.lua` with `VP_INGAME_BUILT=1` plays it to the line.
- `jp.lua` and `jpmatch.lua` show the Japanese script beside the English one
  when a Japanese disc is given.
- `images.lua`, `sounds.lua` and `loadlog.lua` are viewers and a file load
  log for exploring the disc.

The `*-test.lua` files run headless (`pcsx-redux -cli -dofile ...`); the
first lines of each say which disc it needs.
