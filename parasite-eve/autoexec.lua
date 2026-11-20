-- Parasite Eve translation editor. Mount this archive in PCSX-Redux with a
-- Parasite Eve (USA) disc loaded, then use the "Parasite Eve" window.

-- Redux's require() does not search mounted archives yet, so point it at this
-- archive's modules by hand. This goes away once it does.
for _, m in ipairs { 'reader', 'pe', 'pe-groups', 'pe-disc', 'pe-build', 'pe-pack' } do
    package.preload[m] = function() return Support.extra.dofile(m .. '.lua') end
end

local PE = require 'pe'
local PEDisc = require 'pe-disc'

local function readArchived(name)
    local f = Support.extra.open(name)
    if f:failed() then f:close() return nil end
    local s = tostring(f:read(f:size()))
    f:close()
    return s
end

local tbl = assert(PCSX.TextTable.parse(assert(readArchived('pe.tbl'), 'pe.tbl missing from the archive')))

local state = { group = 1, viewers = {}, scripts = {}, edited = {} }

local function scan()
    state.err = nil
    state.disc, state.err = PEDisc.open(PCSX.getCurrentIso())
    state.viewers, state.scripts, state.edited = {}, {}, {}
    if not state.disc then return end
    -- The translation shipped with the archive, if any, is the starting point.
    for g = 1, 20 do
        local shipped = readArchived(string.format('scripts/%02d.bin', g))
        local original, room = state.disc:groupScript(g)
        if original then
            state.scripts[g] = { bytes = shipped or original, original = original, room = room }
        end
    end
end

-- Rooms of this disc whose script no longer fits the sectors the room has.
local function overflowing(g, bytes)
    local n = 0
    for i = 1, PE.ROOM_COUNT do
        if PE.groups[i] == g and state.disc.rooms[i].sizes[3] ~= 0 then
            local room = state.disc:readRoom(i)
            local info = PE.scriptInfo(room)
            local grown = info.roomSize + PE.pad4(#bytes) - PE.pad4(info.size)
            if grown > state.disc.rooms[i].sizes[3] * 2048 then n = n + 1 end
        end
    end
    return n
end

local function viewer(g)
    if state.viewers[g] then return state.viewers[g] end
    local s = state.scripts[g]
    local v = PCSX.FileViewers.textViewer(function()
        local f = Support.File.buffer()
        f:write(s.bytes)
        return f
    end, {
        table = tbl,
        onSave = function(bytes)
            s.bytes = bytes
            state.edited[g] = true
            s.overflow = overflowing(g, bytes)
        end,
    })
    state.viewers[g] = v
    return v
end

local function exportScripts(dir)
    local n = 0
    for g, s in pairs(state.scripts) do
        local f = io.open(string.format('%s/%02d.bin', dir, g), 'wb')
        if not f then return nil, 'cannot write into ' .. dir end
        f:write(s.bytes)
        f:close()
        n = n + 1
    end
    return n
end

-- Write a complete disc image (.bin plus .cue) carrying the current scripts.
local function buildDisc(path)
    local scripts = {}
    for g, s in pairs(state.scripts) do scripts[g] = s.bytes end
    local out = Support.File.open(path, 'TRUNCATE')
    if out:failed() then return 'cannot write ' .. path end
    local files, hacks = require('pe-pack').load(state.disc, readArchived)
    local ok, err = require('pe-build').build(state.disc, out, scripts, files, hacks)
    out:close()
    if not ok then return 'build failed: ' .. tostring(err) end
    local name = path:match('[^/\\]+$')
    local cue = io.open((path:gsub('%.[^./\\]*$', '') .. '.cue'), 'w')
    if cue then
        cue:write('FILE "' .. name .. '" BINARY\r\n  TRACK 01 MODE2/2352\r\n    INDEX 01 00:00:00\r\n')
        cue:close()
    end
    return 'wrote ' .. path
end

-- Reachable from the Lua console and from scripts.
ParasiteEve = { PE = PE, Disc = PEDisc, table = tbl, state = state, scan = scan, export = exportScripts, build = buildDisc }

local exportDir, buildPath = '', ''
local previous = DrawImguiFrame
function DrawImguiFrame()
    if previous then previous() end
    imgui.safe.Begin('Parasite Eve', true, function()
        if imgui.Button('Scan disc') then scan() end
        if state.err then
            imgui.SameLine()
            imgui.TextUnformatted(state.err)
        end
        if not state.disc then return end
        imgui.SameLine()
        imgui.TextUnformatted(string.format('CD %d', state.disc.cd))
        if imgui.BeginCombo('script', string.format('Script %02d', state.group)) then
            for g = 1, 20 do
                if state.scripts[g] then
                    local label = string.format('%sScript %02d (room %d)', state.edited[g] and '* ' or '', g, state.scripts[g].room)
                    if imgui.Selectable(label, g == state.group) then state.group = g end
                end
            end
            imgui.EndCombo()
        end
        local s = state.scripts[state.group]
        if not s then
            imgui.TextUnformatted('This disc carries no rooms using that script.')
            return
        end
        if s.overflow and s.overflow > 0 then
            imgui.TextUnformatted(string.format('%d rooms outgrow their sectors with this text: a rebuilt disc is needed.', s.overflow))
        end
        local c, n = imgui.extra.InputText('export to', exportDir)
        if c then exportDir = n end
        imgui.SameLine()
        if imgui.Button('Export scripts') and exportDir ~= '' then
            local count, err = exportScripts(exportDir)
            state.exportInfo = count and string.format('wrote %d scripts', count) or err
        end
        if state.exportInfo then imgui.TextUnformatted(state.exportInfo) end
        c, n = imgui.extra.InputText('new disc', buildPath)
        if c then buildPath = n end
        imgui.SameLine()
        if imgui.Button('Build disc') and buildPath ~= '' then
            state.buildInfo = buildDisc(buildPath)
        end
        if state.buildInfo then imgui.TextUnformatted(state.buildInfo) end
        viewer(state.group).draw()
    end)
end
