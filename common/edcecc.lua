-- Error detection and correction bytes of Mode 2 CD-ROM sectors.
--
-- A sector stored as raw Mode 2 is 2336 bytes: an 8-byte subheader, then the
-- user data and its check bytes. Bit 0x20 of the submode (subheader byte 2)
-- picks the form:
--   * Form 1: 2048 bytes of data, a 4-byte EDC (a CRC over the subheader and
--     data), then 276 bytes of Reed-Solomon ECC, 172 of P then 104 of Q;
--   * Form 2: 2324 bytes of data and a 4-byte EDC.
-- A script that edits a sector's bytes has to recompute these, or a drive that
-- checks them reads the sector as damaged. Emulators usually do not check.
--
--   local edcecc = require 'edcecc'
--   local fixed = edcecc.stream(raw)   -- raw: string of 2336-byte sectors
--
-- The tables and loops follow ECMA-130 annex A and the ECC layout of the
-- CD-ROM XA specification.

local ffi = require 'ffi'
local bit = require 'bit'
local band, bxor, rshift = bit.band, bit.bxor, bit.rshift

local RAW = 2336

local crc = ffi.new('uint32_t[256]')
for i = 0, 255 do
    local e = i
    for _ = 1, 8 do e = bxor(rshift(e, 1), band(e, 1) ~= 0 and 0xd8018001 or 0) end
    crc[i] = e
end

-- GF(2^8) with polynomial 0x11d: f(x) = 2x, and b undoes f(x) ^ x.
local ecc_f, ecc_b = ffi.new('uint8_t[256]'), ffi.new('uint8_t[256]')
for i = 0, 255 do
    local j = bxor(i * 2, band(i, 0x80) ~= 0 and 0x11d or 0)
    ecc_f[i] = j
    ecc_b[bxor(i, j)] = i
end

local function edc(p, len)
    local e = 0
    for i = 0, len - 1 do e = bxor(crc[band(bxor(e, p[i]), 0xff)], rshift(e, 8)) end
    return e
end

-- One ECC channel over src (the 4 header bytes, zeroed, then the sector).
local function block(src, major, minor, mult, inc, dst)
    local size = major * minor
    for m = 0, major - 1 do
        local index = rshift(m, 1) * mult + band(m, 1)
        local a, b = 0, 0
        for _ = 1, minor do
            local t = src[index]
            index = index + inc
            if index >= size then index = index - size end
            a = ecc_f[bxor(a, t)]
            b = bxor(b, t)
        end
        a = ecc_b[bxor(ecc_f[a], b)]
        dst[m] = a
        dst[m + major] = bxor(a, b)
    end
end

local function put32(p, v)
    for k = 0, 3 do p[k] = band(rshift(v, 8 * k), 0xff) end
end

local work = ffi.new('uint8_t[?]', 4 + RAW)

-- Recomputes the EDC (and ECC for Form 1) of the sector at p, in place.
local function fix(p)
    if band(p[2], 0x20) ~= 0 then
        -- Form 2 may leave its EDC as zero, meaning not computed; keep that.
        local q = p + 8 + 2324
        if q[0] == 0 and q[1] == 0 and q[2] == 0 and q[3] == 0 then return end
        put32(q, edc(p, 8 + 2324))
        return
    end
    put32(p + 8 + 2048, edc(p, 8 + 2048))
    -- The ECC covers the sector header as zeroes in Mode 2.
    ffi.fill(work, 4)
    ffi.copy(work + 4, p, RAW)
    block(work, 86, 24, 2, 86, work + 4 + 2060)
    block(work, 52, 43, 86, 88, work + 4 + 2232)
    ffi.copy(p + 2060, work + 4 + 2060, 276)
end

local M = {}

-- Returns `raw`, a string of raw Mode 2 sectors, with every sector's EDC and
-- ECC recomputed from its bytes. A Form 2 sector with a zero EDC keeps it.
function M.stream(raw)
    local n = math.floor(#raw / RAW)
    local buf = ffi.new('uint8_t[?]', #raw)
    ffi.copy(buf, raw, #raw)
    for i = 0, n - 1 do fix(buf + i * RAW) end
    return ffi.string(buf, #raw)
end

M.sector = fix

return M
