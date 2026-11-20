-- The disc half of the Parasite Eve example: finds the game's executable and
-- PE.IMG on a disc loaded in Redux, and reads rooms out of PE.IMG.
--
--   local disc = assert(require('pe-disc').open(PCSX.getCurrentIso()))
--   local room = disc:readRoom(1)          -- a string, for pe.lua
--
-- The executable holds a table of 438 eight-byte room entries: a sector in
-- PE.IMG, then the sizes in sectors of the room's three parts, packed as
-- 8 + 12 + 12 bits. The third part is the one holding the script.

local PE = require 'pe'
local reader = require 'reader'

local D = {}

local Disc = {}
Disc.__index = Disc

-- `iso` is a Redux Iso object, such as PCSX.getCurrentIso(). Returns a Disc,
-- or nil and a message when this is not a Parasite Eve (USA) disc.
function D.open(iso)
    local files = iso:createReader()
    local slus, cd, slusName
    for name, n in pairs(PE.SLUS) do
        local f = files:open(name)
        if not f:failed() then slus, cd, slusName = f, n, name:gsub(';1$', '') break end
        f:close()
    end
    if not slus then return nil, 'not a Parasite Eve (USA) disc' end
    local img = files:open('PE.IMG;1')
    if img:failed() then return nil, 'PE.IMG not found' end
    local self = setmetatable({ iso = iso, cd = cd, slus = tostring(slus:read(slus:size())), img = img }, Disc)
    slus:close()
    self.slusName, self.imgSectors = slusName, img:size() / 2048
    self.rooms = {}
    for i = 1, PE.ROOM_COUNT do
        local o = PE.ROOM_TABLE + (i - 1) * 8
        local sizes = reader.u32(self.slus, o + 4)
        self.rooms[i] = {
            sector = reader.u32(self.slus, o),
            sizes = { sizes & 0xff, (sizes >> 8) & 0xfff, sizes >> 20 },
        }
    end
    return self
end

-- Byte offset and size of one part (1..3) of a room inside PE.IMG.
function Disc:roomSpan(i, part)
    local r = self.rooms[i]
    local s = r.sector
    for k = 1, part - 1 do s = s + r.sizes[k] end
    return s * 2048, r.sizes[part] * 2048
end

-- The third part of room i, as a string, or nil for a room without one.
function Disc:readRoom(i)
    local pos, size = self:roomSpan(i, 3)
    if size == 0 then return nil end
    return tostring(self.img:readAt(size, pos))
end

-- The script of a group, read from the first room that uses it, and that room.
function Disc:groupScript(g)
    for i = 1, PE.ROOM_COUNT do
        if PE.groups[i] == g and self.rooms[i].sizes[3] ~= 0 then
            local script = PE.roomScript(self:readRoom(i))
            return script, i
        end
    end
end

return D
