-- Mega Man X4 French translation builder. Mount this archive in PCSX-Redux
-- with a Mega Man X4 (USA) disc loaded, then use the "Mega Man X4" window:
-- "Scan disc" checks the disc, "Build disc" writes a translated .bin/.cue.

-- Redux's require() does not search mounted archives yet, so point it at this
-- archive's modules by hand. This goes away once it does.
for _, m in ipairs { 'reader', 'edcecc', 'mmx4-index', 'mmx4-disc', 'mmx4-str', 'mmx4-intro', 'mmx4-build' } do
    package.preload[m] = function() return Support.extra.dofile(m .. '.lua') end
end

local D = require 'mmx4-disc'
local index = require 'mmx4-index'

local function readArchived(name)
    local f = Support.extra.open(name)
    if f:failed() then f:close() return nil end
    local s = tostring(f:read(f:size()))
    f:close()
    return s
end

local state = { disc = nil, err = nil }

local function scan()
    state.disc, state.err = D.open(PCSX.getCurrentIso())
end

-- Load a subtitle index (the patch's Lua 5.0 sub_pos/frames globals) from the
-- archive, returning the two tables, or nil if the folder is not shipped.
local function subtitles(folder)
    local src = readArchived('SUBS-US/' .. folder .. '/index.lua')
    if not src then return nil end
    local env = {}
    assert(load(src, '@' .. folder, 't', env))()
    return { pos = env.sub_pos, frames = env.frames, folder = folder }
end

-- Everything the build replaces: the four rebuilt ARCs, the processed movies,
-- and the executable patches. Returns repl (table index -> bytes) and hacks.
local function prepare(disc, report)
    local repl, applied = {}, {}
    local hackSrc = readArchived('slus-hacks.lua')
    local hacks = hackSrc and assert(loadstring(hackSrc, '@slus-hacks.lua'))() or {}
    if hackSrc then applied[#applied + 1] = 'executable patches' end

    local str = require 'mmx4-str'
    for i, repls in pairs(index.arcs) do
        local sub = {}
        local any = false
        for k, name in pairs(repls) do
            local b = readArchived(name)
            if b then sub[k] = b any = true end
        end
        if any then
            repl[i] = { bytes = require('mmx4-build').arcPatch(disc:read(i), sub), raw = false }
            applied[#applied + 1] = index.names[i]
        end
    end

    for i, m in pairs(index.movies) do
        if m.subs then
            local subs = subtitles(m.subs)
            if subs then
                local new, n = str.process(disc:read(i), {
                    pos = subs.pos, frames = subs.frames,
                    overlay = function(nn) return readArchived('SUBS-US/' .. m.subs .. '/sub-' .. nn .. '.rgba') end,
                })
                repl[i] = { bytes = new, raw = true }
                applied[#applied + 1] = string.format('%s (%d subtitles)', index.names[i], n)
            end
        end
        if report then report(index.names[i]) end
    end

    -- The credits intro replaces the Capcom logo movie, when INTRO/ is shipped.
    if readArchived('INTRO/intro.xa') then
        local intro = require 'mmx4-intro'
        for i in pairs(index.intro) do
            local new, frames = intro.build(disc:read(i), function(name) return readArchived('INTRO/' .. name) end)
            repl[i] = { bytes = new, raw = true }
            hacks[intro.EXE_FRAMES] = intro.exeFrames(frames)
            applied[#applied + 1] = string.format('%s (intro, last frame %d)', index.names[i], frames)
            if report then report(index.names[i]) end
        end
    end
    return repl, hacks, applied
end

local function buildDisc(path)
    if not state.disc then return 'scan a disc first' end
    local out = Support.File.open(path, 'TRUNCATE')
    if out:failed() then return 'cannot write ' .. path end
    local repl, hacks, applied = prepare(state.disc)
    local ok, err = require('mmx4-build').build(state.disc, out, repl, hacks)
    out:close()
    if not ok then return 'build failed: ' .. tostring(err) end
    local name = path:match('[^/\\]+$')
    local cue = io.open((path:gsub('%.[^./\\]*$', '') .. '.cue'), 'w')
    if cue then
        cue:write('FILE "' .. name .. '" BINARY\r\n  TRACK 01 MODE2/2352\r\n    INDEX 01 00:00:00\r\n')
        cue:close()
    end
    return 'wrote ' .. path .. ' (' .. table.concat(applied, ', ') .. ')'
end

-- Reachable from the Lua console and from scripts.
MegaManX4 = { Disc = D, state = state, scan = scan, prepare = prepare, build = buildDisc }

local buildPath = ''
local previous = DrawImguiFrame
function DrawImguiFrame()
    if previous then previous() end
    imgui.safe.Begin('Mega Man X4', true, function()
        if imgui.Button('Scan disc') then scan() end
        if state.err then
            imgui.SameLine()
            imgui.TextUnformatted(state.err)
        end
        if not state.disc then return end
        imgui.SameLine()
        imgui.TextUnformatted('Mega Man X4 (USA)')
        local c, n = imgui.extra.InputText('new disc', buildPath)
        if c then buildPath = n end
        imgui.SameLine()
        if imgui.Button('Build disc') and buildPath ~= '' then
            state.buildInfo = buildDisc(buildPath)
        end
        if state.buildInfo then imgui.TextUnformatted(state.buildInfo) end
    end)
end
