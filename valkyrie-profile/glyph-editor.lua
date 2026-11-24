-- The glyph editor in Valkyrie Profile's Translate tab: common/glyph-editor.lua
-- drawing in the game font, with the Japanese font's duplicate characters
-- listed under it.

local E = require 'glyph-editor'
VP.glyphEditor = E
local F = VP.fontedit

-- The JP font is read only here: it is what the JP pane draws the disc with.
-- Characters it lists more than once are kept as variants (a room font can
-- use any of them); this lists them so nobody mistakes one for the glyph.
local function drawJapanese(s)
    if not imgui.CollapsingHeader('Japanese font duplicates (read only)') then return end
    local dups = F.jpDuplicates()
    imgui.TextUnformatted(string.format('%d characters have more than one bitmap in the JP font database; ' ..
        'the JP pane recognizes every variant and draws the last one listed.', #dups))
    local shown = {}
    for i = 1, math.min(#dups, 40) do shown[#shown + 1] = dups[i].ch .. 'x' .. dups[i].count end
    imgui.TextUnformatted(table.concat(shown, ' ') .. (#dups > 40 and ' ...' or ''))
end

local view = {
    drawLine = function(text, set) VP.glyphs.drawLine(text, set, VP.translate.previewScale or 2) end,
    refresh = function(glyph) VP.glyphs.refreshGlyph(glyph) end,
    describe = function(lang) return VP.languages.describe(lang) end,
    firstChar = 'é',
    sample = 'Lenneth: Je dois me dépêcher !',
    extra = function(s) drawJapanese(s) end,
}

-- Called from the Translate tab with its viewer table.
function VP.glyphEditor.drawVP(v) E.draw(VP.tmodel, v, view) end
