-- Reading and writing little-endian binary data at byte offsets.
--
-- Disc images, executables and game files are bytes laid out like C structs,
-- so this reads them the way C would: take a pointer to the data, cast it to
-- the type wanted, and dereference. LuaJIT's ffi does exactly that, and the
-- result is a plain Lua number.
--
--   local reader = require 'reader'
--   local sector = reader.u32(data, 0x9e)      -- uint32_t at byte 0x9e
--   local x = reader.read(data, 4, 'int16_t')   -- any ffi scalar type
--   local bytes = reader.w32(sector + 1)        -- 4-byte string, to write back
--
-- `data` can be any of:
--   * a Lua string, such as one read from a file;
--   * a LuaBuffer, which is what Redux's File:read() and File:readAt() return;
--   * a Slice, which Redux hands out for memory regions;
--   * an ffi array (uint8_t[N] and the like) or an ffi pointer.
-- Offsets start at 0, as in C, and reads past the end of the data raise an
-- error. A bare pointer carries no size, so it is not bounds-checked.
--
-- Everything is little-endian, like the PlayStation and the PCs Redux runs on.

local ffi = require 'ffi'

local reader = {}

-- Redux declares the LuaBuffer type; elsewhere it does not exist.
local hasLuaBuffer, LuaBuffer = pcall(ffi.typeof, 'LuaBuffer')

local bytePtr = ffi.typeof('const uint8_t *')

-- Returns a byte pointer to `data` and its size in bytes (nil when unknown).
function reader.bytes(data)
    local t = type(data)
    if t == 'string' then return ffi.cast(bytePtr, data), #data end
    if t == 'table' and data._type == 'Slice' then return ffi.cast(bytePtr, data.data), data.size end
    if t == 'cdata' then
        if hasLuaBuffer and ffi.istype(LuaBuffer, data) then return ffi.cast(bytePtr, data.data), data.size end
        -- An array knows its size; a pointer does not (sizeof would give the pointer's own).
        if tostring(ffi.typeof(data)):match('%*>$') then return ffi.cast(bytePtr, data), nil end
        return ffi.cast(bytePtr, data), ffi.sizeof(data)
    end
    error('reader: cannot read from a ' .. t, 2)
end

-- One pointer type per ctype name, built on first use.
local pointerTypes = {}
local function pointerTo(ctype)
    local p = pointerTypes[ctype]
    if not p then
        p = ffi.typeof('const $ *', ffi.typeof(ctype))
        pointerTypes[ctype] = p
    end
    return p
end

-- The value of type `ctype` (an ffi type name such as 'uint16_t' or 'float')
-- stored at byte `offset` of `data`.
function reader.read(data, offset, ctype)
    local base, size = reader.bytes(data)
    if size and (offset < 0 or offset + ffi.sizeof(ctype) > size) then
        error(string.format('reader: %s at offset %d is outside %d bytes', ctype, offset, size), 2)
    end
    return ffi.cast(pointerTo(ctype), base + offset)[0]
end

function reader.u8(data, offset) return reader.read(data, offset, 'uint8_t') end
function reader.s8(data, offset) return reader.read(data, offset, 'int8_t') end
function reader.u16(data, offset) return reader.read(data, offset, 'uint16_t') end
function reader.s16(data, offset) return reader.read(data, offset, 'int16_t') end
function reader.u32(data, offset) return reader.read(data, offset, 'uint32_t') end
function reader.s32(data, offset) return reader.read(data, offset, 'int32_t') end

-- The bytes of `value` stored as `ctype`, as a string: the opposite of read().
function reader.pack(ctype, value)
    return ffi.string(ffi.new(ffi.typeof('$[1]', ffi.typeof(ctype)), value), ffi.sizeof(ctype))
end

function reader.w16(value) return reader.pack('uint16_t', value) end
function reader.w32(value) return reader.pack('uint32_t', value) end

return reader
