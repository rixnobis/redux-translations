-- Rebuild a Mega Man X4 (USA) disc with the French patch, through
-- PCSX.isoBuilder. The disc is copied file by file; the four ARC files that
-- carry the font and player graphics are rebuilt, the nine subtitled movies
-- and the intro are replaced with the processed STRs, and the executable's lookup table is
-- rewritten so each entry points at where its file actually landed.
--
-- The game finds its data by the hardcoded sector table, not the filesystem,
-- so this follows the pattern the ISO builder docs describe for a disc with an
-- LBA table: build the tree, let close() assign every LBA, then go back and
-- write the real sectors into the table over the executable's placeholder.

local index = require 'mmx4-index'
local reader = require 'reader'
local edcecc = require 'edcecc'
local u8, s8, u16, u32 = reader.u8, reader.s8, reader.u16, reader.u32
local w32 = reader.w32

local B = {}

local SECTOR, RAW = 2048, 2336
local TABLE, ENTRIES, FILES = 0xe1618, 163, 160

local function sectors(bytes) return math.ceil(bytes / SECTOR) end
local function pad(bytes, to) return bytes .. string.rep('\0', (-#bytes) % to) end

-- Overwrite bytes of string s starting at offset pos (0-based).
local function splice(s, pos, bytes)
    return s:sub(1, pos) .. bytes .. s:sub(pos + #bytes + 1)
end

-- Rebuild an ARC archive, replacing subfiles named in `repl` (0-based index ->
-- bytes). An ARC is a u32 count, a u32 size, then one (u32 flags, u32 size)
-- per subfile; the subfiles follow, each padded to a sector. size is the whole
-- archive's byte length. Replacement subfiles are padded to 4 like the patcher.
function B.arcPatch(arc, repl)
    local n = u32(arc, 0)
    local subs, off = {}, SECTOR
    for k = 0, n - 1 do
        local flags, size = u32(arc, 8 + 8 * k), u32(arc, 8 + 8 * k + 4)
        subs[k] = { flags = flags, size = size, data = arc:sub(off + 1, off + size) }
        off = off + sectors(size) * SECTOR
    end
    for k, bytes in pairs(repl) do
        bytes = pad(bytes, 4)
        subs[k] = { flags = subs[k].flags, size = #bytes, data = bytes }
    end
    local head = w32(n) .. w32(0)
    for k = 0, n - 1 do head = head .. w32(subs[k].flags) .. w32(subs[k].size) end
    local out = pad(head, SECTOR)
    for k = 0, n - 1 do out = out .. pad(subs[k].data, SECTOR) end
    return splice(out, 4, w32(#out))
end

-- ISO9660 directory flags and XA attribute bits, as in pe-build.
local FLAG_HIDDEN, FLAG_DIR = 0x01, 0x02
local XA_FORM2, XA_INTERLEAVED = 0x1000, 0x2000

-- ISO9660 directory records off an Iso, with the XA attribute word.
local function readDir(iso, lba, size)
    local data = tostring(iso:open(lba, size, 'M2_FORM1'):read(size))
    local entries, pos = {}, 0
    while pos < #data do
        local len = u8(data, pos)
        if len == 0 then
            pos = pos - pos % SECTOR + SECTOR
        else
            local nameLen = u8(data, pos + 32)
            local name = data:sub(pos + 34, pos + 33 + nameLen)
            if name ~= '\0' and name ~= '\1' then
                local su = pos + 33 + nameLen + ((nameLen + 1) & 1)
                local e = {
                    name = name:gsub(';1$', ''),
                    lba = u32(data, pos + 2),
                    size = u32(data, pos + 10),
                    date = { u8(data, pos + 18), u8(data, pos + 19), u8(data, pos + 20), u8(data, pos + 21),
                             u8(data, pos + 22), u8(data, pos + 23), s8(data, pos + 24) },
                    flags = u8(data, pos + 25),
                }
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

-- Name -> file table index. ARC/STR/XA names come from the index; the three
-- trailing entries are the config, the executable and the dummy file.
local function tableIndex(disc)
    local byName = {}
    for i = 0, FILES - 1 do byName[index.names[i]] = i end
    byName['SYSTEM.CNF'] = 160
    byName[disc.SLUSNAME or 'SLUS_005.61'] = 161
    byName['ZNULL.DAT'] = 162
    return byName
end

local PVD_FIELDS = {
    { 'SystemIdent', 8, 32 }, { 'VolumeIdent', 40, 32 }, { 'VolSetIdent', 190, 128 },
    { 'PublisherIdent', 318, 128 }, { 'DataPreparerIdent', 446, 128 }, { 'ApplicationIdent', 574, 128 },
    { 'CopyrightFileIdent', 702, 37 }, { 'AbstractFileIdent', 739, 37 }, { 'BibliographicFileIdent', 776, 37 },
}

-- Build the whole disc. `repl[i]` replaces table entry i: { bytes =, raw = }.
-- `hacks` is executable offset -> replacement bytes. Writes to `out`.
function B.build(disc, out, repl, hacks)
    repl, hacks = repl or {}, hacks or {}
    local iso = disc.iso
    local D = require 'mmx4-disc'

    -- The executable, with its code patched and each entry's size set to what
    -- the content will be. Sectors are filled in after the layout is known.
    local slus = disc.slus
    for offset, bytes in pairs(hacks) do slus = splice(slus, offset, bytes) end
    local size = {}
    for i = 0, ENTRIES - 1 do size[i] = disc.entries[i].size end
    for i, r in pairs(repl) do size[i] = #r.bytes end
    for i = 0, ENTRIES - 1 do slus = splice(slus, TABLE + i * 12 + 4, w32(size[i])) end
    local slusFile = Support.File.buffer()
    slusFile:write(slus)
    slusFile:rSeek(0)

    local byName = tableIndex(disc)
    local node = {}

    local builder = PCSX.isoBuilder(out)
    if builder:failed() then return nil, 'cannot write the output file' end
    builder:writeLicense(iso:open(0, 16 * 2352, 'RAW'))
    local pvd = tostring(iso:open(16, SECTOR, 'M2_FORM1'):read(SECTOR))
    for _, f in ipairs(PVD_FIELDS) do
        builder['set' .. f[1]](builder, (pvd:sub(f[2] + 1, f[2] + f[3]):gsub(' +$', '')))
    end

    local rootLBA, rootSize = u32(pvd, 158), u32(pvd, 166)
    local function fill(parent, lba, dsize)
        for _, e in ipairs(readDir(iso, lba, dsize)) do
            local i = byName[e.name]
            local n
            if e.isDir then
                n = builder:createDir(parent, e.name, sectors(e.size))
                fill(n, e.lba, e.size)
            elseif i == 161 then
                n = builder:createFile(parent, e.name, slusFile)
            elseif e.xa and (e.xa & (XA_FORM2 | XA_INTERLEAVED)) ~= 0 then
                -- STR and XA streams keep their raw Mode 2 sectors.
                local content
                if i and repl[i] then
                    -- The edited sectors carry the original check bytes (or
                    -- none, for new ones); M2_RAW writes them as given.
                    local f = Support.File.buffer()
                    f:write(edcecc.stream(repl[i].bytes))
                    f:rSeek(0)
                    content = f
                else
                    content = iso:open(e.lba, sectors(e.size) * RAW, 'M2_RAW')
                end
                n = builder:createFile(parent, e.name, content)
                n:setSectorMode('M2_RAW')
                -- The directory counts 2048 bytes per sector of a stream.
                n:setDeclaredSize((i and repl[i]) and math.floor(#repl[i].bytes / RAW) * SECTOR or e.size)
            elseif i and repl[i] then
                local f = Support.File.buffer()
                f:write(repl[i].bytes)
                f:rSeek(0)
                n = builder:createFile(parent, e.name, f)
            else
                n = builder:createFile(parent, e.name, iso:open(e.lba, e.size, 'M2_FORM1'))
            end
            if e.xa then n:setXAAttribs(e.xa) end
            if (e.flags & FLAG_HIDDEN) ~= 0 then n:setHidden(true) end
            n:setDate(unpack(e.date))
            if i then node[i] = n end
        end
    end
    local root = builder:createRoot(sectors(rootSize))
    fill(root, rootLBA, rootSize)
    local err = builder:close()
    if builder:failed() or (err and err ~= '') then return nil, err or 'build failed' end

    -- Now every file has an LBA: write the real sectors into the table.
    local slusLBA = node[161]:getLBA()
    for i = 0, ENTRIES - 1 do
        if node[i] then slus = splice(slus, TABLE + i * 12, w32(node[i]:getLBA())) end
    end
    local first = (TABLE - TABLE % SECTOR)
    local last = ((TABLE + ENTRIES * 12 - 1))
    for off = first, last, SECTOR do
        local s = math.floor(off / SECTOR)
        builder:writeSectorAt(slus:sub(off + 1, off + SECTOR), slusLBA + s, 'M2_FORM1')
    end

    -- Landing zone past the end of the volume for the drive's seeks.
    local blank = string.rep('\0', SECTOR)
    for _ = 1, 150 do builder:writeSector(blank) end
    return true, { slusLBA = slusLBA }
end

return B
