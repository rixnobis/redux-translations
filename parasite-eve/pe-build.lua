-- Rebuild a Parasite Eve (USA) disc with new room scripts and replacement
-- PE.IMG files, through PCSX.isoBuilder. The disc is copied file by file; only
-- the executable's lookup tables and PE.IMG change.

local PE = require 'pe'
local reader = require 'reader'

local B = {}

-- Executable tables of misc files and music, as sector numbers inside PE.IMG.
local MISC_TABLE, SONG_BASE, MUSIC_TABLE = 0x838da, 0x8397c, 0x83980
local MISC_COUNT, MUSIC_COUNT = 80, 251
local SECTOR = 2048
local u8, s8, u16, u32 = reader.u8, reader.s8, reader.u16, reader.u32
local w16, w32 = reader.w16, reader.w32

-- Overwrite bytes of string s starting at offset pos.
local function splice(s, pos, bytes)
    return s:sub(1, pos) .. bytes .. s:sub(pos + #bytes + 1)
end

local function sectors(bytes)
    return math.ceil(bytes / SECTOR)
end

-- ISO9660 directory flags, and the XA attribute bits for Form 2 sectors.
local FLAG_HIDDEN, FLAG_DIR = 0x01, 0x02
local XA_FORM2, XA_INTERLEAVED = 0x1000, 0x2000

-- ISO9660 directory records off an Iso, with the XA attribute word.
local function readDir(iso, lba, size)
    local data = tostring(iso:open(lba, size, 'M2_FORM1'):read(size))
    local entries, pos = {}, 0
    while pos < #data do
        local len = u8(data, pos)
        if len == 0 then
            -- Records never cross a sector: a zero length means skip to the next one.
            pos = pos - pos % SECTOR + SECTOR
        else
            local nameLen = u8(data, pos + 32)
            local name = data:sub(pos + 34, pos + 33 + nameLen)
            if name ~= '\0' and name ~= '\1' then
                -- The system use area follows the name, padded to an even offset.
                local su = pos + 33 + nameLen + ((nameLen + 1) & 1)
                local e = {
                    name = name:gsub(';1$', ''),
                    lba = u32(data, pos + 2),
                    size = u32(data, pos + 10),
                    -- Years since 1900, month, day, hour, minute, second, then the
                    -- signed GMT offset in 15-minute steps.
                    date = { u8(data, pos + 18), u8(data, pos + 19), u8(data, pos + 20), u8(data, pos + 21),
                             u8(data, pos + 22), u8(data, pos + 23), s8(data, pos + 24) },
                    flags = u8(data, pos + 25),
                }
                -- The XA extension: big-endian attributes, then the 'XA' signature.
                if su + 14 <= pos + len and data:sub(su + 7, su + 8) == 'XA' then
                    e.xa = u8(data, su + 4) << 8 | u8(data, su + 5)
                end
                e.isDir = (e.flags & FLAG_DIR) ~= 0
                entries[#entries + 1] = e
            end
            pos = pos + len
        end
    end
    return entries
end

-- Lay PE.IMG out again. scripts[g] replaces script g in every room using it,
-- files[i] replaces misc file i. Returns the new PE.IMG as a File, and the
-- executable with its tables rewritten.
function B.layoutImage(disc, scripts, files, hacks)
    local slus, img = disc.slus, disc.img
    for offset, bytes in pairs(hacks or {}) do slus = splice(slus, offset, bytes) end
    local misc = {}
    for i = 1, MISC_COUNT do misc[i] = u16(slus, MISC_TABLE + (i - 1) * 2) end
    local songEnd = u16(slus, MUSIC_TABLE + (MUSIC_COUNT - 1) * 2)

    local out = Support.File.buffer()
    local pos = 0
    local function copy(from, count)
        local chunk = 256
        for s = 0, count - 1, chunk do
            local n = math.min(chunk, count - s)
            out:write(img:readAt(n * SECTOR, (from + s) * SECTOR))
        end
        pos = pos + count
    end
    local function put(bytes)
        local n = sectors(#bytes)
        out:write(bytes .. string.rep('\0', n * SECTOR - #bytes))
        pos = pos + n
    end

    copy(0, misc[1])
    local newMisc = {}
    for i = 1, MISC_COUNT - 1 do
        newMisc[i] = pos
        if files[i] then put(files[i]) else copy(misc[i], misc[i + 1] - misc[i]) end
    end
    newMisc[MISC_COUNT] = pos
    -- The music is addressed relative to the last misc entry, so it moves as one block.
    copy(misc[MISC_COUNT], songEnd)

    local rooms = {}
    for i = 1, PE.ROOM_COUNT do
        local r = disc.rooms[i]
        local start = pos
        local sizes = {}
        for part = 1, 3 do
            local from = r.sector
            for k = 1, part - 1 do from = from + r.sizes[k] end
            local before = pos
            local g = PE.groups[i]
            if part == 3 and r.sizes[3] ~= 0 and g and scripts[g] then
                put(PE.patchRoom(disc:readRoom(i), scripts[g]))
            else
                copy(from, r.sizes[part])
            end
            sizes[part] = pos - before
        end
        rooms[i] = { sector = start, sizes = sizes }
    end
    local finish = pos

    for i = 1, MISC_COUNT do slus = splice(slus, MISC_TABLE + (i - 1) * 2, w16(newMisc[i])) end
    if u16(disc.slus, SONG_BASE) == misc[MISC_COUNT] then
        slus = splice(slus, SONG_BASE, w16(newMisc[MISC_COUNT]))
    end
    for i = 1, PE.ROOM_COUNT do
        local s = rooms[i].sizes
        assert(s[1] < 256 and s[2] < 4096 and s[3] < 4096, 'room ' .. i .. ' too large for the table')
        -- Sector, then the three part sizes packed as 8 + 12 + 12 bits (pe-disc.lua).
        local entry = w32(rooms[i].sector) .. w32(s[1] | s[2] << 8 | s[3] << 20)
        slus = splice(slus, PE.ROOM_TABLE + (i - 1) * 8, entry)
    end
    -- The entries past the last room point at the end of the image.
    for k = 0, 10 do
        local o = PE.ROOM_TABLE + (PE.ROOM_COUNT + k) * 8
        if u32(disc.slus, o) == disc.imgSectors then slus = splice(slus, o, w32(finish)) end
    end
    return out, slus, finish
end

local PVD_FIELDS = {
    { 'SystemIdent', 8, 32 }, { 'VolumeIdent', 40, 32 }, { 'VolSetIdent', 190, 128 },
    { 'PublisherIdent', 318, 128 }, { 'DataPreparerIdent', 446, 128 }, { 'ApplicationIdent', 574, 128 },
    { 'CopyrightFileIdent', 702, 37 }, { 'AbstractFileIdent', 739, 37 }, { 'BibliographicFileIdent', 776, 37 },
}

-- Write the whole disc to `out` (a File opened for writing).
function B.build(disc, out, scripts, files, hacks)
    local iso = disc.iso
    local image, slus = B.layoutImage(disc, scripts or {}, files or {}, hacks)
    image:rSeek(0)
    local slusFile = Support.File.buffer()
    slusFile:write(slus)
    slusFile:rSeek(0)

    local builder = PCSX.isoBuilder(out)
    if builder:failed() then return nil, 'cannot write the output file' end
    builder:writeLicense(iso:open(0, 16 * 2352, 'RAW'))
    local pvd = tostring(iso:open(16, SECTOR, 'M2_FORM1'):read(SECTOR))
    for _, f in ipairs(PVD_FIELDS) do
        builder['set' .. f[1]](builder, (pvd:sub(f[2] + 1, f[2] + f[3]):gsub(' +$', '')))
    end

    local rootLBA, rootSize = u32(pvd, 158), u32(pvd, 166)
    local function fill(parent, lba, size)
        for _, e in ipairs(readDir(iso, lba, size)) do
            local node
            if e.isDir then
                node = builder:createDir(parent, e.name, sectors(e.size))
                fill(node, e.lba, e.size)
            elseif e.name == disc.slusName then
                node = builder:createFile(parent, e.name, slusFile)
            elseif e.name == 'PE.IMG' and parent == disc.buildRoot then
                node = builder:createFile(parent, e.name, image)
            elseif e.xa and (e.xa & (XA_FORM2 | XA_INTERLEAVED)) ~= 0 then
                -- Form 2 streams (STR, XA) go across with their subheaders.
                node = builder:createFile(parent, e.name, iso:open(e.lba, sectors(e.size) * 2336, 'M2_RAW'))
                node:setSectorMode('M2_RAW')
                node:setDeclaredSize(e.size)
            else
                node = builder:createFile(parent, e.name, iso:open(e.lba, e.size, 'M2_FORM1'))
            end
            if e.xa then node:setXAAttribs(e.xa) end
            if (e.flags & FLAG_HIDDEN) ~= 0 then node:setHidden(true) end
            node:setDate(unpack(e.date))
        end
    end
    local root = builder:createRoot(sectors(rootSize))
    disc.buildRoot = root
    fill(root, rootLBA, rootSize)
    local err = builder:close()
    disc.buildRoot = nil
    if builder:failed() or (err and err ~= '') then return nil, err or 'build failed' end
    -- Landing zone past the end of the volume for the drive's seeks.
    local blank = string.rep('\0', SECTOR)
    for _ = 1, 150 do builder:writeSector(blank) end
    return true
end

return B
