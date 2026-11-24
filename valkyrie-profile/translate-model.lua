-- The model behind the Translate views (translate.lua for ImGui, the web view
-- for a browser): common/tmodel.lua with Valkyrie Profile's text format,
-- textboxes and glyphs, plus the page previews. Nothing here draws.
--
-- A script here is a room script viewer's `extra` (VP.vfs.ptrs): key, first,
-- tokens, raw, textboxes and style. Edit texts are VP.text.toEditable.
--
-- The database file is VP_TDB from the environment, or vp-fr.tdb in the current
-- directory.

VP.tmodel = VP.tmodel or {}
local M = VP.tmodel
M.path = M.path or os.getenv('VP_TDB') or 'vp-fr.tdb'
M.author = M.author or os.getenv('VP_AUTHOR') or os.getenv('USER') or ''

-- The <window .../> line glyphs.windowGeometry reads, for a textbox as
-- extractTextboxes found it, with the row's overrides applied.
function M.windowHead(tb, row)
    if not tb then return nil end
    local over = row and (row.boxX or row.boxY or row.boxW or row.boxH)
    if not over then
        if tb.typ == 'fixed' then return '<window type="fixed"/>' end
        if tb.typ == 'auto' then return '<window type="auto"/>' end
    end
    local x, y = row and row.boxX or tb.x, row and row.boxY or tb.y
    local w, h = row and row.boxW or tb.width, row and row.boxH or tb.height
    if tb.typ == 'fixed' then x, y, w, h = row.boxX or 64, row.boxY or 32, row.boxW or 192, row.boxH or 14 end
    return string.format('<window x="%s" y="%s" width="%s" height="%s"%s/>', tostring(x), tostring(y), tostring(w),
        tostring(h), tb.placement and ' placement="helper"' or '')
end

-- The original box, as the fit check sees it: numbers where they are known.
-- A 16x16 box at 16,16 is the placeholder rooms pass for messages the field
-- executable opens with its own geometry (room.lua, nativeWindows); the real
-- size is unknown unless extraction already replaced it. On USA disc 1 it is
-- 1120 of the 1164 retail strings wider than their recorded box.
function M.originalBox(tb)
    if not tb then return {} end
    if tb.typ == 'fixed' then return { x = 64, y = 32, width = 192, height = 14 } end
    if tb.x == 16 and tb.y == 16 and tb.width == 16 and tb.height == 16 then return {} end
    return { x = tonumber(tb.x), y = tonumber(tb.y), width = tonumber(tb.width), height = tonumber(tb.height) }
end

require('tmodel').install(M, {
    open = function(path) return VP.tdb.open(path) end,
    -- An armed in-game preview follows the database the editor uses.
    onOpen = function(db) if VP.preview and VP.preview.armed() then VP.preview.db = db end end,
    key = function(extra) return extra.key end,
    first = function(extra) return extra.first end,
    source = function(extra, i) return extra.tokens[i] end,
    hash = function(extra, i) return VP.text.fnv1a64(extra.raw[i]) end,
    editable = function(tokens, lookup) return VP.text.toEditable(tokens, lookup) end,
    parse = function(extra, text, charset) return VP.text.fromEditable(text, extra.style, charset) end,
    originalBox = function(extra, i) return M.originalBox(extra.textboxes[i]) end,
    saveContext = function(extra, i, lookup) return { box = M.originalBox(extra.textboxes[i]), lookup = lookup } end,
    defaultCharset = function() return VP.constants.font end,
    glyph = setmetatable({}, { __index = function(_, k)
        local F = VP.fontedit
        if k == 'height' then return F.HEIGHT end
        if k == 'blank' then return function() return F.blank() end end
        return F[k]
    end }),
})

-- The original page as the game leaves it: window, pages.
function M.originalPreview(ptrText, extra, i, lookup)
    local tb = extra.textboxes[i]
    local ob = M.originalBox(tb)
    local pages = VP.glyphs.pagesFromTokens(extra.tokens[i], lookup, extra.style)
    return VP.glyphs.parse(ptrText), VP.glyphs.scrollPages((VP.glyphs.wrapPages(pages, ob.width)), ob.height)
end

-- The translation in its (possibly overridden) box: window, pages (wrapped,
-- and a page taller than the box scrolled to its last lines), problems, notes.
function M.translationPreview(extra, i, e, tokens, lookup)
    local tb = extra.textboxes[i]
    local row = e.override and { boxX = e.boxX, boxY = e.boxY, boxW = e.boxW, boxH = e.boxH } or nil
    local head = M.windowHead(tb, row)
    local window = head and VP.glyphs.windowGeometry(head) or nil
    local box = VP.tdb.effectiveBox(row or {}, M.originalBox(tb))
    local problems, notes, wrapped = VP.tdb.fitProblems(tokens, box, lookup, M.charset())
    return window, VP.glyphs.scrollPages(wrapped, box.height), problems, notes
end
