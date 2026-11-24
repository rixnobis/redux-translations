-- Translation database for Valkyrie Profile: common/tdb.lua, opened with this
-- game's rules. Keys are VP.text.scriptKey (rooms sharing a script share
-- rows) and the pointer index in that script; srcHash is the FNV-1a 64 of the
-- original string's bytes, tokens come from VP.text.fromEditable. A reviewed
-- row has to fit its textbox (fitHook below), letters come from
-- VP.languages, and edited glyphs are checked by VP.fontedit.check.

local core = require 'tdb'

VP.tdb = VP.tdb or {}
for k, v in pairs(core) do VP.tdb[k] = v end

function VP.tdb.open(target, options)
    local o = {}
    for k, v in pairs(options or {}) do o[k] = v end
    o.beforeSave = o.beforeSave or { VP.tdb.fitHook }
    o.languages = o.languages or VP.languages
    o.checkGlyph = o.checkGlyph or function(g) return VP.fontedit.check(g) end
    o.glyphHeight = o.glyphHeight or VP.fontedit.HEIGHT
    return core.open(target, o)
end

-- The geometry a row will be shown in: its overrides over the original box.
-- original is { x, y, width, height } or nil.
function VP.tdb.effectiveBox(row, original)
    original = original or {}
    return {
        x = row.boxX or original.x,
        y = row.boxY or original.y,
        width = row.boxW or original.width,
        height = row.boxH or original.height,
    }
end

-- beforeSave hook: a reviewed row must be showable in its box. The game wraps
-- a line wider than the box at a space and scrolls a page with more lines than
-- the box holds (14 pixels a line: a 12 pixel box holds one line, 42 three, 70
-- five), so neither stops a review; a missing glyph or a single word wider than
-- the box does. When the width is only known at run time, wrapping is not
-- checked. context.box is the original textbox, context.lookup the script
-- font's glyph-to-character map for any {g} token. A character outside the
-- database's target language (tdb:charset) has no glyph.
function VP.tdb.fitHook(row, context, db)
    if row.status ~= VP.tdb.status.reviewed or not row.tokens then return nil end
    local box = VP.tdb.effectiveBox(row, context.box)
    local problems = VP.tdb.fitProblems(row.tokens, box, context.lookup, db and db:charset())
    if #problems > 0 then return 'Cannot be marked reviewed: ' .. problems[1] end
    return nil
end

-- Returns the problems that stop a review, and the notes that do not (pages
-- that scroll). charset is the characters that have a glyph (the font
-- database when nil).
function VP.tdb.fitProblems(tokens, box, lookup, charset)
    local problems, notes = {}, {}
    local widths, missing = VP.glyphs.measureTokens(tokens, lookup, nil, charset)
    if missing > 0 then problems[#problems + 1] = missing .. ' characters have no glyph' end
    local pages, tooWide = VP.glyphs.wrapPages(VP.glyphs.pagesFromTokens(tokens, lookup), box.width, charset)
    if tooWide then
        problems[#problems + 1] = string.format('a word is wider than the box (%d px) and cannot wrap', box.width)
    end
    local maxLines = type(box.height) == 'number' and math.floor((box.height + 2) / 14) or nil
    for p, page in ipairs(pages) do
        if maxLines and #page > maxLines then
            notes[#notes + 1] = string.format('page %d is %d lines in a %d-line box, it scrolls', p, #page, maxLines)
        end
    end
    return problems, notes, pages
end
