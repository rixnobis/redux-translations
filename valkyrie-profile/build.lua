-- Writes a translated Valkyrie Profile disc through PCSX.isoBuilder.
--
-- The original layout is kept sector for sector. Only two things change: a
-- room archive whose script or font the translation database changes is
-- rebuilt and written after the end of VALKYRIE.BIN, and its index entry is
-- pointed there. Everything else is copied, so the disc's own files keep the
-- positions they had on the retail disc.
--
--   local ok, err = VP.build.disc(PCSX.getCurrentIso(), db, out)
--
-- with db a translation database (VP.tdb.open) and out a File open for
-- writing. VALKYRIE.BIN spans the game's whole data area: the index sits at
-- its start (sectors 150-162) and every indexed file after it.

VP.build = VP.build or {}
local build = VP.build
local ffi = require('ffi')

local SECTOR = 2048
local INDEX_SECTORS = 13
local TAIL_PAD = 150

local function u32(s, o) return ffi.cast('const uint32_t*', ffi.cast('const char*', s) + o)[0] end
local function w32(v)
    local b = ffi.new('uint32_t[1]', v)
    return ffi.string(b, 4)
end
local function align4(n) return n + (4 - n % 4) % 4 end
local function sectors(bytes) return math.ceil(bytes / SECTOR) end

function build.bufferOf(s)
    local f = Support.File.buffer()
    f:write(s)
    f:rSeek(0)
    return f
end

-- An SLZ container with chunk i replaced by plain[i] where given, encoded
-- with the chunk's original scheme. Chunks are 16-byte headers (signature,
-- size in, size out, offset to the next chunk or 0) followed by the payload,
-- each starting on a 4-byte boundary.
function build.reslz(member, plain)
    local chunks = {}
    local pos = 0
    while true do
        local sig, sizeIn, sizeOut, nextOff = u32(member, pos), u32(member, pos + 4), u32(member, pos + 8), u32(member, pos + 12)
        local scheme = VP.slz.signatures[sig]
        if not scheme then error('not an SLZ chunk at ' .. pos) end
        chunks[#chunks + 1] = { sig = sig, scheme = scheme, sizeOut = sizeOut, data = member:sub(pos + 17, pos + 16 + sizeIn) }
        if nextOff == 0 then break end
        pos = pos + nextOff
    end
    local out = {}
    for i, c in ipairs(chunks) do
        local data, sizeOut = c.data, c.sizeOut
        if plain[i] then
            if c.scheme ~= 1 and c.scheme ~= 2 then error('chunk ' .. i .. ' is SLZ' .. c.scheme .. ', which cannot be re-encoded') end
            data, sizeOut = VP.slz.encode(c.scheme, plain[i]), #plain[i]
        end
        local body = data .. string.rep('\0', align4(16 + #data) - 16 - #data)
        local nextOff = i < #chunks and 16 + #body or 0
        out[i] = w32(c.sig) .. w32(#data) .. w32(sizeOut) .. w32(nextOff) .. body
    end
    return table.concat(out)
end

-- A room archive: u32 count, u32 offset of the first member (8 + 8 * count),
-- then (tag, size) pairs, then the members back to back.
function build.parseArchive(file)
    local n, offset = u32(file, 0), u32(file, 4)
    if offset ~= 8 + 8 * n then error('not a room archive') end
    local members = {}
    for i = 1, n do
        local tag, size = u32(file, 8 * i), u32(file, 8 * i + 4)
        members[i] = { tag = tag, data = file:sub(offset + 1, offset + size) }
        if #members[i].data ~= size then error('room archive member ' .. i .. ' runs past the file') end
        offset = offset + size
    end
    return members
end

local function packArchive(members)
    local head, body = { w32(#members), w32(8 + 8 * #members) }, {}
    for i, m in ipairs(members) do
        head[#head + 1] = w32(m.tag) .. w32(#m.data)
        body[i] = m.data
    end
    return table.concat(head) .. table.concat(body)
end

-- The room archive with its tag 4 member (script, font) rebuilt from the
-- database, or nil when the database changes nothing in it. Returns the new
-- bytes and the rebuild's problem list.
function build.room(file, db)
    local members = build.parseArchive(file)
    local changed, problems = false, {}
    for _, m in ipairs(members) do
        if m.tag == 4 then
            local chunks = {}
            for i, c in ipairs(VP.slz.chunks(build.bufferOf(m.data))) do chunks[i] = VP.slz.decode(c) end
            local saved = VP.preview.db
            VP.preview.db = db
            local entry = VP.preview.patched(chunks[1], chunks[2])
            VP.preview.db = saved
            if entry.error then error('script ' .. entry.key .. ': ' .. entry.error) end
            if entry.script then
                m.data = build.reslz(m.data, { entry.script, entry.font })
                changed = true
                for _, p in ipairs(entry.problems or {}) do problems[#problems + 1] = p end
            end
        end
    end
    if not changed then return nil, problems end
    return packArchive(members), problems
end

local function bcd(v) return math.floor(v / 10) * 16 + v % 10 end

-- Writes entry i of the index into the 13 index sectors (a string), keeping
-- the scrambling: each byte is XORed with the key bytes stored at the end of
-- its table, which no room entry reaches, so the keys stay as they were.
local function setEntry(index, i, lba, size)
    local locsLen = VP.constants.indexCount * 4
    local sizeBase = locsLen
    local lk, sk = VP.constants.indexLocsKeySize, VP.constants.indexSizeKeySize
    if i * 4 + 3 >= locsLen - lk or i >= VP.constants.indexCount - sk then error('index entry ' .. i .. ' overlaps the keys') end
    if size >= 65536 then error('entry ' .. i .. ' is too large for the index') end
    local a = lba + 150
    local m, s, f = math.floor(a / 4500), math.floor(a / 75) % 60, a % 75
    local plain = { bcd(m), bcd(s), bcd(f), bit.rshift(size, 8) }
    local bytes = ffi.new('uint8_t[?]', #index)
    ffi.copy(bytes, index, #index)
    for j = 0, 3 do
        bytes[i * 4 + j] = bit.bxor(plain[j + 1], bytes[locsLen - lk + (i * 4 + j) % lk])
    end
    bytes[sizeBase + i] = bit.bxor(bit.band(size, 0xff), bytes[sizeBase + VP.constants.indexCount - sk + i % sk])
    return ffi.string(bytes, #index)
end


-- Builds the disc. Returns true, or nil and an error. report (optional) is
-- called with one line per rebuilt room.
function build.disc(iso, db, out, report)
    report = report or function() end
    local disc = VP.vfs.identify(iso)
    if not disc or disc.region ~= 'US' or disc.disc ~= 1 then return nil, 'not Valkyrie Profile USA disc 1' end
    local reader = iso:createReader()
    local binFile = reader:open('VALKYRIE.BIN;1')
    if binFile:failed() then return nil, 'no VALKYRIE.BIN on this disc' end
    local binSectors = sectors(binFile:size())
    binFile:close()
    local binEnd = 150 + binSectors

    VP.globals.index.entries = {}
    VP.globals.isos = { US = { CD1 = { iso = iso } }, JP = {} }
    readIndex()
    local index = tostring(iso:open(150, INDEX_SECTORS * SECTOR, 'M2_FORM1'):read(INDEX_SECTORS * SECTOR))

    -- Rooms whose archive the database changes, in index order.
    local appended, next = {}, binEnd
    for i = 1, VP.constants.indexCount - 1 do
        local entry = VP.globals.index.entries[i]
        local info = VP.globals.filemap[i]
        if entry and info and info.ftype == 'arcroom' and info.ext == 'arm' then
            local file = tostring(iso:open(entry.lba, entry.size * SECTOR, 'M2_FORM1'):read(entry.size * SECTOR))
            local bytes, problems = build.room(file, db)
            if bytes then
                local n = sectors(#bytes)
                index = setEntry(index, i, next, n)
                appended[#appended + 1] = { lba = next, data = bytes }
                report(string.format('room %d: %d -> %d sectors at LBA %d, %d fit problem(s)', i, entry.size, n, next, #problems))
                next = next + n
            end
        end
    end

    local builder = PCSX.isoBuilder(out)
    if builder:failed() then return nil, 'cannot write the output file' end
    builder:writeLicense(iso:open(0, 16 * 2352, 'RAW'))
    local pvd = tostring(iso:open(16, SECTOR, 'M2_FORM1'):read(SECTOR))
    local fields = {
        { 'SystemIdent', 8, 32 }, { 'VolumeIdent', 40, 32 }, { 'VolSetIdent', 190, 128 },
        { 'PublisherIdent', 318, 128 }, { 'DataPreparerIdent', 446, 128 }, { 'ApplicationIdent', 574, 128 },
    }
    for _, f in ipairs(fields) do
        builder['set' .. f[1]](builder, (pvd:sub(f[2] + 1, f[2] + f[3]):gsub(' +$', '')))
    end
    -- Dates of the root directory's records, to copy onto the new ones.
    local dates = {}
    local rootDir = tostring(iso:open(u32(pvd, 158), SECTOR, 'M2_FORM1'):read(SECTOR))
    local pos = 0
    while pos < SECTOR and rootDir:byte(pos + 1) > 0 do
        local len, nameLen = rootDir:byte(pos + 1), rootDir:byte(pos + 33)
        local name = rootDir:sub(pos + 34, pos + 33 + nameLen):gsub(';1$', '')
        local d = { rootDir:byte(pos + 19, pos + 25) }
        if d[7] >= 128 then d[7] = d[7] - 256 end
        dates[name] = d
        pos = pos + len
    end
    local function dated(node, name)
        if dates[name] then node:setDate(unpack(dates[name])) end
        return node
    end
    local root = builder:createRoot(1)
    for _, name in ipairs({ 'SYSTEM.CNF', disc.exe }) do
        dated(builder:createFile(root, name, reader:open(name .. ';1')), name)
    end
    -- VALKYRIE.BIN itself holds the index; its declared size covers the copied
    -- data area and the rebuilt rooms after it.
    local bin = dated(builder:createFile(root, 'VALKYRIE.BIN', build.bufferOf(index)), 'VALKYRIE.BIN')
    bin:setAnchorLBA(150)
    bin:setDeclaredSize((next - 150) * SECTOR)
    local rest = builder:createFile(root, 'DATA', iso:open(150 + INDEX_SECTORS, (binEnd - 150 - INDEX_SECTORS) * SECTOR, 'M2_FORM1'))
    rest:setAnchorLBA(150 + INDEX_SECTORS)
    rest:setSkip(true)
    for k, a in ipairs(appended) do
        local node = builder:createFile(root, string.format('ROOM%04d', k), build.bufferOf(a.data))
        node:setAnchorLBA(a.lba)
        node:setSkip(true)
    end
    local err = builder:close()
    if builder:failed() or (err and err ~= '') then return nil, err or 'build failed' end
    -- Landing zone past the end of the volume for the drive's seeks.
    local blank = string.rep('\0', SECTOR)
    for _ = 1, TAIL_PAD do builder:writeSector(blank) end
    return true, #appended
end

-- Writes path (a .bin) and a .cue beside it. Returns a line saying what was
-- written, or nil and an error.
function build.write(iso, db, path, report)
    local out = Support.File.open(path, 'TRUNCATE')
    if out:failed() then return nil, 'cannot write ' .. path end
    local ok, n = build.disc(iso, db, out, report)
    out:close()
    if not ok then return nil, 'build failed: ' .. tostring(n) end
    local name = path:match('[^/\\]+$')
    local cuePath = path:gsub('%.[^./\\]*$', '') .. '.cue'
    local cue = io.open(cuePath, 'w')
    if not cue then return nil, 'cannot write ' .. cuePath end
    cue:write('FILE "' .. name .. '" BINARY\r\n  TRACK 01 MODE2/2352\r\n    INDEX 01 00:00:00\r\n')
    cue:close()
    return string.format('wrote %s and %s, %d room(s) rebuilt', path, cuePath, n), n
end
