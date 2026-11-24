-- The ImGui Translate tab over a common/tmodel.lua model: the database row,
-- one string at a time with its original, the editable translation, the box
-- override, the status, the versioned save with its conflict dialog, and the
-- history. What a game draws around that comes from the view table:
--
--   local tab = require 'translate-tab'
--   tab.draw(M, v, script, count, view)
--
-- M is the model, v the per-script state ({ edits = {} } to start), script
-- the game's script object and count the index of its last string. view:
--   lookup(script)                   whatever M.game.editable needs (a font map)
--   title(script)                    the line above the counts, optional
--   tools(v)                         drawn under the database row, optional
--   previews(v, script, i, e, tokens) drawn under the editor, optional;
--                                    tokens is nil while the text does not parse
--
-- The translation is typed in the game's editable text form and parsed on
-- every edit; a problem shows under the box. Saving goes through the
-- database's version check, so a row somebody else saved meanwhile opens a
-- dialog with both versions.

local tdb = require 'tdb'

local tab = {}

tab.RED, tab.GREEN, tab.YELLOW, tab.GREY = 0xff5050ff, 0xff60d060, 0xff40c8e8, 0xff999999
local RED, GREEN = tab.RED, tab.GREEN

function tab.colored(color, text)
    imgui.PushStyleColor(imgui.constant.Col.Text, color)
    imgui.TextUnformatted(text)
    imgui.PopStyleColor()
end
local colored = tab.colored

-- Editor state of string i, loaded from the database on first use.
local function editState(M, v, script, i)
    local e = v.edits[i]
    if e then return e end
    e = M.loadEdit(script, i, v.lookup)
    v.edits[i] = e
    return e
end

local function save(M, v, script, i, e, tokens, expected)
    local result, r = M.save(script, i, e, tokens, expected, v.lookup)
    if result == 'saved' then
        e.message, e.messageColor = 'Saved as version ' .. r.version, GREEN
        e.conflict = nil
    elseif result == 'conflict' then
        e.conflict = r
        e.openConflict = true
    else
        e.message, e.messageColor = r, RED
    end
end

local function drawConflict(M, v, script, i, e, tokens)
    local id = 'Save conflict##' .. i
    if e.openConflict then
        imgui.OpenPopup(id)
        e.openConflict = nil
    end
    -- The binding turns a nil p_open into a pointer to false, which closes the
    -- modal at once; true gives it a working close button.
    imgui.safe.BeginPopupModal(id, true, imgui.constant.WindowFlags.AlwaysAutoResize, function()
        local theirs = e.conflict
        if not theirs then
            imgui.CloseCurrentPopup()
            return
        end
        imgui.TextUnformatted(string.format('%s saved version %d of this string while you were editing version %d.',
            theirs.author or 'Someone', theirs.version, e.base))
        if theirs.deletedAt then imgui.TextUnformatted('Their version deletes the translation.') end
        imgui.Separator()
        imgui.TextUnformatted('Theirs (' .. (tdb.statusNames[theirs.status] or '?') .. '):')
        imgui.extra.InputTextMultiline('##theirs', theirs.tokens and M.game.editable(theirs.tokens, v.lookup) or '',
            600, 100, imgui.constant.InputTextFlags.ReadOnly)
        imgui.TextUnformatted('Yours (' .. (tdb.statusNames[e.status] or '?') .. '):')
        imgui.extra.InputTextMultiline('##yours', e.text, 600, 100, imgui.constant.InputTextFlags.ReadOnly)
        if imgui.Button('Keep mine') then
            save(M, v, script, i, e, tokens, theirs.version)
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine()
        if imgui.Button('Take theirs') then
            v.edits[i] = nil
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine()
        if imgui.Button('Cancel') then
            e.conflict = nil
            imgui.CloseCurrentPopup()
        end
    end)
end

-- The database path and translator row. Returns true when a database is open.
function tab.drawDatabase(M, v)
    imgui.TextUnformatted('Database')
    imgui.SameLine()
    imgui.SetNextItemWidth(400)
    local _, path = imgui.extra.InputText('##tdbpath', M.path)
    M.path = path
    imgui.SameLine()
    if imgui.Button(M.db and M.openPath == M.path and 'Reopen' or 'Open') then
        M.open(M.path)
        v.edits = {}
    end
    imgui.SameLine()
    imgui.TextUnformatted('Translator')
    imgui.SameLine()
    imgui.SetNextItemWidth(150)
    local _, author = imgui.extra.InputText('##tdbauthor', M.author)
    M.author = author
    if M.dbError then colored(RED, M.dbError) end
    if not M.db and not M.dbError then M.open(M.path) end
    return M.db ~= nil
end

function tab.draw(M, v, script, count, view)
    if not tab.drawDatabase(M, v) then return end
    if view.tools then view.tools(v) end

    v.lookup = v.lookup or view.lookup(script)
    local first = M.game.first(script)
    v.cur = v.cur or first

    local c = M.counts(script, count)
    imgui.TextUnformatted(string.format('%s: %d strings, %d untranslated, %d draft, %d reviewed',
        view.title and view.title(script) or 'Script ' .. M.game.key(script), count - first + 1, c[0], c[1], c[2]))
    if imgui.Button('<') and v.cur > first then v.cur = v.cur - 1 end
    imgui.SameLine()
    if imgui.Button('>') and v.cur < count then v.cur = v.cur + 1 end
    imgui.SameLine()
    imgui.SetNextItemWidth(300)
    local changed, n = imgui.SliderInt('pointer', v.cur, first, count)
    if changed then v.cur = n end
    imgui.SameLine()
    if imgui.Button('Next untranslated') then
        local nx = M.nextUntranslated(script, count, v.cur)
        if nx then v.cur = nx else v.message = 'Every string of this script is translated.' end
    end
    if v.message then
        imgui.SameLine()
        imgui.TextUnformatted(v.message)
    end

    local i = v.cur
    local e = editState(M, v, script, i)
    imgui.Separator()
    imgui.TextUnformatted('Original')
    imgui.extra.InputTextMultiline('##original' .. i, M.game.editable(M.game.source(script, i), v.lookup), -1, 90,
        imgui.constant.InputTextFlags.ReadOnly)
    imgui.TextUnformatted('Translation (control codes as {tags}, write {{ and }} for braces)')
    local edited, text = imgui.extra.InputTextMultiline('##translation' .. i, e.text, -1, 120)
    if edited then
        e.text = text
        e.message = nil
    end
    local tokens, perr, ppos = M.parse(script, e)
    if not tokens then colored(RED, string.format('At byte %d: %s', ppos, perr)) end
    if e.sourceChanged then colored(RED, 'The original text changed since this translation was saved.') end

    local cb, ov = imgui.Checkbox('Override box', e.override)
    if cb then e.override = ov end
    if e.override then
        for _, f in ipairs({ { 'x', 'boxX' }, { 'y', 'boxY' }, { 'width', 'boxW' }, { 'height', 'boxH' } }) do
            imgui.SameLine()
            imgui.SetNextItemWidth(90)
            local ch, val = imgui.InputInt(f[1] .. '##box' .. i, e[f[2]], 1, 8)
            if ch then e[f[2]] = math.max(0, val) end
        end
    end
    for s = 0, 2 do
        if imgui.RadioButton(tdb.statusNames[s] .. '##st' .. i, e.status == s) then e.status = s end
        imgui.SameLine()
    end
    imgui.SetNextItemWidth(300)
    local _, note = imgui.extra.InputTextWithHint('##note' .. i, 'note', e.note)
    e.note = note
    imgui.SameLine()
    if imgui.Button('Save') then
        if tokens then
            save(M, v, script, i, e, tokens, e.base)
        else
            e.message, e.messageColor = 'Not saved: ' .. perr, RED
        end
    end
    imgui.SameLine()
    imgui.TextUnformatted(string.format('(editing version %d)', e.base))
    if e.message then colored(e.messageColor or GREEN, e.message) end
    if tokens then drawConflict(M, v, script, i, e, tokens) end

    if view.previews then
        imgui.Separator()
        view.previews(v, script, i, e, tokens)
    end

    if imgui.CollapsingHeader('History##' .. i) then
        for _, line in ipairs(M.history(script, i, v.lookup)) do imgui.TextUnformatted(line) end
    end
end

return tab
