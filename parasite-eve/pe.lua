-- Parasite Eve (USA) disc layout: room table, script blocks, and room rewriting.
--
-- Pure Lua over strings, so it runs both inside PCSX-Redux and under a plain
-- LuaJIT for testing. The disc-facing half (PE.open) takes a PCSX Iso object.

local PE = {}

local function u16(s, o)
    local a, b = s:byte(o + 1, o + 2)
    return a + b * 256
end

local function u32(s, o)
    local a, b, c, d = s:byte(o + 1, o + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function w32(v)
    v = v % 4294967296
    return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216))
end

-- Pointers in a room keep a tag in their top 12 bits and an offset in the low 20.
local function ptr(v)
    return v % 1048576
end

local function movePtr(v, delta)
    assert(ptr(v) + delta < 1048576, 'room pointer out of range')
    return v + delta
end

local function pad4(n)
    return n + (4 - n % 4) % 4
end

PE.u16, PE.u32, PE.w32, PE.pad4 = u16, u32, w32, pad4

-- Executable offsets of the tables locating everything inside PE.IMG.
PE.SLUS = { ['SLUS_006.62;1'] = 1, ['SLUS_006.68;1'] = 2 }
PE.ROOM_TABLE = 0x83b78
PE.ROOM_COUNT = 438

-- Which script file each room uses; rooms missing from the table carry no text.
PE.groups = require 'pe-groups'

-- Locate the script inside a room's third part.
function PE.scriptInfo(room)
    local roomSize = u32(room, 0)
    local ptrPtrs = u32(room, 4)
    local header = ptr(u32(room, ptrPtrs + 32))
    local size = u32(room, header + 8)
    local offset = ptr(u32(room, header + 12))
    return {
        roomSize = roomSize,
        ptrPtrs = ptrPtrs,
        header = header,
        size = size,
        offset = offset,
        entries = (ptr(u32(room, ptrPtrs + 40)) - ptr(u32(room, ptrPtrs + 36))) / 4,
    }
end

function PE.roomScript(room)
    local info = PE.scriptInfo(room)
    return room:sub(info.offset + 1, info.offset + info.size), info
end

-- Put a new script into a room, moving everything after it and fixing the
-- pointers that cross it. Returns the new room, without sector padding.
function PE.patchRoom(room, script)
    local info = PE.scriptInfo(room)
    local padded = script .. string.rep('\0', pad4(#script) - #script)
    local delta = #padded - pad4(info.size)
    local p = info.ptrPtrs
    local out = {}
    local function copy(from, to) out[#out + 1] = room:sub(from + 1, to) end

    out[#out + 1] = w32(info.roomSize + delta)
    out[#out + 1] = w32(p + delta)
    copy(8, info.offset)
    out[#out + 1] = padded
    copy(info.offset + pad4(info.size), p)
    copy(p, p + 4)
    for i = 1, 12 do
        out[#out + 1] = w32(movePtr(u32(room, p + i * 4), delta))
    end
    copy(p + 52, info.header + 8)
    out[#out + 1] = w32(#script)
    local pos = info.header + 12
    local keep = 1 + info.entries
    copy(pos, pos + keep * 4)
    pos = pos + keep * 4
    while pos + 12 <= info.roomSize do
        copy(pos, pos + 4)
        out[#out + 1] = w32(movePtr(u32(room, pos + 4), delta))
        copy(pos + 8, pos + 12)
        pos = pos + 12
    end
    return table.concat(out)
end

-- Disc side. `iso` is a PCSX Iso object (PCSX.getCurrentIso()).
local Disc = {}
Disc.__index = Disc

function PE.open(iso)
    local reader = iso:createReader()
    local slus, cd, slusName
    for name, n in pairs(PE.SLUS) do
        local f = reader:open(name)
        if not f:failed() then slus, cd, slusName = f, n, name:gsub(';1$', '') break end
        f:close()
    end
    if not slus then return nil, 'not a Parasite Eve (USA) disc' end
    local img = reader:open('PE.IMG;1')
    if img:failed() then return nil, 'PE.IMG not found' end
    local self = setmetatable({ iso = iso, cd = cd, slus = tostring(slus:read(slus:size())), img = img }, Disc)
    slus:close()
    self.slusName, self.imgSectors = slusName, img:size() / 2048
    self.rooms = {}
    for i = 1, PE.ROOM_COUNT do
        local o = PE.ROOM_TABLE + (i - 1) * 8
        local b1, b2, b3, b4 = self.slus:byte(o + 5, o + 8)
        self.rooms[i] = {
            sector = u32(self.slus, o),
            sizes = { b1, b2 + (b3 % 16) * 256, math.floor(b3 / 16) + b4 * 16 },
        }
    end
    return self
end

-- Byte span of one part (1..3) of a room inside PE.IMG.
function Disc:roomSpan(i, part)
    local r = self.rooms[i]
    local s = r.sector
    for k = 1, part - 1 do s = s + r.sizes[k] end
    return s * 2048, r.sizes[part] * 2048
end

function Disc:readRoom(i)
    local pos, size = self:roomSpan(i, 3)
    if size == 0 then return nil end
    return tostring(self.img:readAt(size, pos))
end

-- The script of a group, read from the first room that uses it.
function Disc:groupScript(g)
    for i = 1, PE.ROOM_COUNT do
        if PE.groups[i] == g and self.rooms[i].sizes[3] ~= 0 then
            local script = PE.roomScript(self:readRoom(i))
            return script, i
        end
    end
end

return PE
