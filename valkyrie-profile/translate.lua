-- The Translate viewer: edits one room script's strings into the translation
-- database (tdb.lua), one pointer at a time.
--
-- The translation is typed in the editable text form of VP.text.toEditable:
-- characters as themselves, control codes as {tags}. Characters must exist in
-- the font database; the text is parsed on every edit and a problem is shown
-- under the box. Saving goes through the database's version check, so a row
-- somebody else saved meanwhile opens a dialog with both versions. The page
-- preview draws the translation in the game font beside the original.
--
-- The editor itself is common/translate-tab.lua over the model in
-- translate-model.lua (VP.tmodel), which the web view shares; this file adds
-- Valkyrie Profile's tools and its page previews. The database path can be
-- changed at the top of the viewer.

VP.translate = VP.translate or {}
local T = VP.translate
local M = VP.tmodel

-- Pixels per game pixel in the page previews.
T.previewScale = T.previewScale or 2
local PAGE_W, PAGE_H = 320, 240
local tab = require 'translate-tab'
local RED, GREEN, YELLOW, GREY = tab.RED, tab.GREEN, tab.YELLOW, tab.GREY
local colored = tab.colored

local function drawPages(window, pages, set, id)
    local SCALE = T.previewScale
    local h = 0
    for _ in ipairs(pages) do h = h + PAGE_H * SCALE + 24 end
    imgui.safe.BeginChild(id, PAGE_W * SCALE + 16, h + 8, 0, function()
        for p, lines in ipairs(pages) do
            if #pages > 1 then imgui.TextUnformatted(string.format('page %d/%d', p, #pages)) end
            VP.glyphs.drawPage(window, lines, set, SCALE)
        end
    end)
end

-- The in-game preview: while armed, every room the game loads gets its saved
-- translations (drafts and reviewed) patched in, from this database.
local function drawPreviewControl()
    local armed = VP.preview.armed()
    local changed, on = imgui.Checkbox('Show translations in game', armed)
    if changed then
        if on then VP.preview.arm(M.db) else VP.preview.disarm() end
    end
    imgui.SameLine()
    if VP.preview.armed() then
        imgui.TextUnformatted('Applies when the game next loads a room. Needs the debugger enabled.')
    else
        imgui.TextUnformatted('Off.')
    end
    local log = VP.preview.log
    if #log > 0 then imgui.TextUnformatted('Last: ' .. log[#log]) end
end

-- A whole disc with this database's translations (drafts and reviewed) in it,
-- written as a .bin and .cue. The window stops responding while it builds.
local function drawBuildControl()
    if not M.buildPath then
        M.buildPath = (M.path or 'valkyrie-profile.tdb'):gsub('%.[^./\\]*$', '') .. '-translated.bin'
    end
    imgui.TextUnformatted('Disc image')
    imgui.SameLine()
    imgui.SetNextItemWidth(400)
    local _, path = imgui.extra.InputText('##buildpath', M.buildPath)
    M.buildPath = path
    imgui.SameLine()
    if imgui.Button('Build disc') then
        if not M.buildPath:lower():match('%.bin$') then
            M.buildResult, M.buildError = nil, 'the disc image name has to end in .bin'
        else
            M.buildResult, M.buildError = VP.build.write(PCSX.getCurrentIso(), M.db, M.buildPath)
        end
    end
    imgui.SameLine()
    imgui.TextUnformatted('Takes a minute or two.')
    if M.buildError then colored(RED, M.buildError) end
    if M.buildResult then imgui.TextUnformatted(M.buildResult) end
end

-- The database's languages: the target picks the letters a translation may
-- use, and both are what the web view tells the browser's spellchecker.
local function drawLanguages(v)
    local target, source = M.languages()
    if v.langDb ~= M.db then v.langDb, v.target, v.source = M.db, target, source end
    imgui.TextUnformatted('Translating from')
    imgui.SameLine()
    imgui.SetNextItemWidth(80)
    local _, src = imgui.extra.InputText('##srclang', v.source)
    v.source = src
    imgui.SameLine()
    imgui.TextUnformatted('to')
    imgui.SameLine()
    imgui.SetNextItemWidth(80)
    local _, tgt = imgui.extra.InputText('##tgtlang', v.target)
    v.target = tgt
    imgui.SameLine()
    if (v.target ~= target or v.source ~= source) and imgui.Button('Set languages') then
        local ok, err = M.setLanguages(v.target, v.source)
        v.langMessage = ok and nil or err
        v.edits = {}
    end
    imgui.SameLine()
    imgui.TextUnformatted(VP.languages.describe(target))
    if v.langMessage then colored(RED, v.langMessage) end
end

-- The Japanese disc whose script shows beside the English one.
local function drawJapaneseDisc(v)
    VP.jp.status() -- opens VP_DISC_JP on first use
    if v.jpPath == nil then v.jpPath = VP.jp.path or '' end
    imgui.TextUnformatted('Japanese disc')
    imgui.SameLine()
    imgui.SetNextItemWidth(420)
    local _, p = imgui.extra.InputTextWithHint('##jpdisc', 'path to a JP disc 1 .cue', v.jpPath)
    v.jpPath = p
    imgui.SameLine()
    if imgui.Button('Open##jpdisc') then VP.jp.setDisc(v.jpPath) end
    imgui.SameLine()
    local st = VP.jp.status()
    if st == 'ok' then colored(GREEN, VP.jp.disc.exe) elseif st ~= 'unset' then colored(RED, st) end
end

-- The previews under the editor: the original as the Preview tab draws it,
-- the Japanese original when a JP disc is open, and the translation from its
-- tokens in the (possibly overridden) box, all as the game leaves them.
local function drawPreviews(v, ptrs, extra, i, e, tokens)
    imgui.BeginGroup()
    imgui.TextUnformatted('Original')
    local origWindow, origPages = M.originalPreview(ptrs[i], extra, i, v.lookup)
    drawPages(origWindow, origPages, 'US', 'origpages')
    imgui.EndGroup()
    imgui.SameLine()
    imgui.BeginGroup()
    imgui.TextUnformatted('Japanese original')
    local jps, jerr = VP.jp.string(extra, i)
    if jps then
        colored(GREY, string.format('JP pointer %d (%s)', jps.ptr, jps.how == 'same' and 'same index' or
            'paired by the room logic'))
        drawPages(jps.window, jps.pages, 'JP', 'jppages')
    else
        colored(GREY, jerr)
    end
    imgui.EndGroup()
    imgui.SameLine()
    imgui.BeginGroup()
    imgui.TextUnformatted('Translation')
    if tokens then
        local trWindow, trPages, problems, notes = M.translationPreview(extra, i, e, tokens, v.lookup)
        if #problems == 0 and #notes == 0 then
            colored(GREEN, 'Fits the box.')
        else
            for _, p in ipairs(problems) do colored(RED, p) end
            for _, n in ipairs(notes) do colored(YELLOW, n) end
        end
        drawPages(trWindow, trPages, M.charset(), 'trpages')
    end
    imgui.EndGroup()
end

local function drawTools(v)
    drawLanguages(v)
    drawJapaneseDisc(v)
    drawPreviewControl()
    drawBuildControl()
    VP.glyphEditor.draw(v)
    VP.tags.drawImgui()
end

local function drawTranslate(v, room)
    local ptrs, err = VP.vfs.ptrs(room)
    if not ptrs then
        colored(RED, 'Error: ' .. tostring(err))
        return
    end
    tab.draw(M, v, room.extra, #ptrs, {
        lookup = function(extra) return resolveFont(extra.font) end,
        tools = drawTools,
        previews = function(_, extra, i, e, tokens) drawPreviews(v, ptrs, extra, i, e, tokens) end,
    })
end

-- The viewer for a room script viewer (vfs.lua roomScriptViewer).
function T.viewer(room)
    local v = { name = 'Translate', edits = {} }
    v.draw = function() drawTranslate(v, room) end
    return v
end
