-- The non-script half of a translation pack, in the layout of the 2004 French
-- patch: replacement PE.IMG files and executable patches. `read(name)` returns
-- a file's bytes from the pack, or nil.

local PE = require 'pe'
local u32, w32, pad4 = PE.u32, PE.w32, PE.pad4

local P = {}

local MISC_TABLE = 0x838da
local WIDTHS = 0x81ea1

-- Bytes of misc file i (1..79) as the original disc holds it.
function P.miscFile(disc, i)
    local a = PE.u16(disc.slus, MISC_TABLE + (i - 1) * 2)
    local b = PE.u16(disc.slus, MISC_TABLE + i * 2)
    return tostring(disc.img:readAt((b - a) * 2048, a * 2048))
end

-- Menu file: its glyph advance table follows the executable's width table
-- from glyph 78 on, so the characters the translation adds get their widths.
local function menus(bytes, widths)
    local o = u32(bytes, 0x28)
    local t = {}
    for i = 78, 144 do
        local v = widths:byte(i)
        if not v or v == 0 then break end
        t[#t + 1] = { o + i - 1, string.char((v - 1) * 16 % 256) }
    end
    for _, p in ipairs(t) do bytes = bytes:sub(1, p[1]) .. p[2] .. bytes:sub(p[1] + 2) end
    return bytes
end

-- Map file: two TIMs behind an offset header.
local function map(font, names)
    return w32(8) .. w32(#font + 8) .. font .. names
end

-- Day 1 file: four blocks behind an offset header; block 2 is the map text.
local function day1(original, text)
    local offs = {}
    for i = 1, 4 do offs[i] = u32(original, (i - 1) * 4) end
    offs[5] = offs[4] + u32(original, offs[4])
    local blocks = {}
    for i = 1, 4 do blocks[i] = original:sub(offs[i] + 1, offs[i + 1]) end
    blocks[2] = text .. string.rep('\0', pad4(#text) - #text)
    local header, pos = {}, 0x10
    for i = 1, 4 do
        header[i] = w32(pos)
        pos = pos + #blocks[i]
    end
    return table.concat(header) .. table.concat(blocks)
end

-- Returns files (misc index -> bytes) and hacks (executable offset -> bytes).
function P.load(disc, read)
    local files, hacks = {}, nil
    local hackSrc = read('slus-hacks.lua')
    if hackSrc then hacks = assert(loadstring(hackSrc, '@slus-hacks.lua'))() end
    local function set(i, name)
        local b = read(name)
        if b then files[i] = b end
        return b
    end
    set(1, 'various.bin')
    local m = read('menus.bin')
    if m and hacks and hacks[WIDTHS] then files[2] = menus(m, hacks[WIDTHS]) end
    local font = set(10, 'font.tim')
    set(70, 'mainmenu.bin')
    local names = read('names.tim')
    if font and names then files[72] = map(font, names) end
    local text = read('map.bin')
    if text then files[76] = day1(P.miscFile(disc, 76), text) end
    return files, hacks or {}
end

return P
