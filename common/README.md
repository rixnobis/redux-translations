# common/

Modules the game folders share. A game folder loads them with `require`, and
its zip carries them (Valkyrie Profile puts them under `common/` in the zip,
the other games beside their own files).

## Disc and file access

- `reader.lua` reads and writes little-endian numbers at byte offsets in
  strings, ffi buffers, `LuaBuffer` and `Slice`. `reader-test.lua` tests it.
- `edcecc.lua` recomputes the EDC and ECC of raw Mode 2 sectors.

## The translation editor

A game supplies its text format and its drawing; these supply the rest.
`valkyrie-profile/` is the worked example of every piece.

- `tdb.lua` is the translation database over sqlite (`PCSX.SQLite`): one row
  per string, keyed by a string key and an index, with versioned writes that
  report a conflict instead of overwriting, a history of every version, soft
  deletes, settings (the source and target languages) and glyphs edited per
  language. The game passes its save checks, its language letters and its
  glyph check to `tdb.open`.
- `tmodel.lua` is what the editor views do with the database: load a string
  for editing, save it, count by status, find the next untranslated string,
  list the history, and load, save and revert glyphs. `install(M, game)`
  takes the game's text codec, textbox geometry and glyph format.
- `translate-tab.lua` is the ImGui Translate tab over a model: the database
  row, one string at a time with its original and its translation, the box
  override, the status, the save with its conflict dialog, and the history.
  The game adds a tools row and its previews.
- `glyph-editor.lua` is the ImGui glyph editor: the language's characters, a
  pixel grid to paint, the advance, and a preview line drawn by the game.
- `web.lua` builds the pages of a Translate web view served by Redux
  (`-webserver`): form parsing, links, the page shell, and text fields the
  rich editor can take over. `rich-text.js` is that editor: control codes
  written as `{tags}` show as chips, and the browser's spellchecker works on
  the text around them.
