-- The disc half of the Mega Man X4 example: finds the executable on a disc
-- loaded in Redux, reads its file table, and reads the files it lists.
--
--   local disc = assert(require('mmx4-disc').open(PCSX.getCurrentIso()))
--   local arc = disc:read(64)              -- LOAD_U.ARC, as a string
--
-- The game finds its files through a table in the executable at 0xe1618, not
-- through the filesystem: 163 entries of three 32-bit words, the first sector,
-- the size and a flag word. Entries 0..159 are the ARC, STR and XA files in
-- the order of mmx4-index.lua; 160..162 are SYSTEM.CNF, the executable and
-- ZNULL.DAT. ARC sizes are in bytes. STR and XA files are Mode 2 streams, and
-- their sizes count 2336 bytes per sector: the subheader and the whole payload.

local reader = require 'reader'
local index = require 'mmx4-index'

local D = {}

D.SLUS = 'SLUS_005.61'
D.TABLE, D.ENTRIES, D.FILES = 0xe1618, 163, 160
D.SECTOR, D.RAW_SECTOR = 2048, 2336

local Disc = {}
Disc.__index = Disc

-- `iso` is a Redux Iso object, such as PCSX.getCurrentIso(). Returns a Disc,
-- or nil and a message when this is not a Mega Man X4 (USA) disc.
function D.open(iso)
    if not iso or iso:failed() then return nil, 'no disc loaded' end
    local files = iso:createReader()
    local f = files:open(D.SLUS .. ';1')
    if f:failed() then
        f:close()
        return nil, 'not a Mega Man X4 (USA) disc: ' .. D.SLUS .. ' not found'
    end
    local self = setmetatable({ iso = iso, slus = tostring(f:read(f:size())) }, Disc)
    f:close()
    self.entries = {}
    for i = 0, D.ENTRIES - 1 do
        local o = D.TABLE + i * 12
        self.entries[i] = { sector = reader.u32(self.slus, o), size = reader.u32(self.slus, o + 4), flags = reader.u32(self.slus, o + 8) }
    end
    -- The executable lists itself: a mismatch means another release of the game.
    local me = self.entries[161]
    if me.size ~= #self.slus then return nil, 'unexpected file table in ' .. D.SLUS end
    return self
end

-- STR and XA files are stored as raw Mode 2 sectors.
function Disc:isRaw(i)
    local name = index.names[i]
    return name ~= nil and (name:match('%.STR$') or name:match('%.XA$')) ~= nil
end

-- Sectors entry i spans on the disc.
function Disc:sectors(i)
    local e = self.entries[i]
    local unit = self:isRaw(i) and D.RAW_SECTOR or D.SECTOR
    return math.ceil(e.size / unit)
end

-- Entry i as a File: 2048 bytes per sector, or 2336 for a stream.
function Disc:open(i)
    local e = self.entries[i]
    return self.iso:open(e.sector, e.size, self:isRaw(i) and 'M2_RAW' or 'M2_FORM1')
end

-- Entry i as a string.
function Disc:read(i)
    local f = self:open(i)
    local s = tostring(f:read(self.entries[i].size))
    f:close()
    return s
end

return D
