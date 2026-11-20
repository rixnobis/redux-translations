-- Parasite Eve (USA) room format: where a room keeps its script, and how to
-- put a longer or shorter script into it.
--
-- This file only works on strings and calls nothing from Redux, so it can be
-- tested on room dumps without a disc loaded (pe-disc.lua is the half that
-- reads the disc). It uses the C-style bit operators (&, |, <<, >>) that
-- Redux's LuaJIT accepts; a stock LuaJIT does not parse them.
--
-- A room is the third part of a room entry in PE.IMG. Its first two words are
-- the room size and the offset of a pointer block. Pointer 8 of that block
-- leads to the script header, which holds the script size and offset, then a
-- table of entry points into the script, then 12-byte records whose middle
-- word points somewhere in the room.

local reader = require 'reader'
local u32, w32 = reader.u32, reader.w32

local PE = {}

-- Room pointers keep a tag in their top 12 bits and a byte offset in the low 20.
local PTR_MASK = 0xfffff

local function ptr(v)
    return v & PTR_MASK
end

-- Slide a room pointer by `delta` bytes, keeping its tag.
local function movePtr(v, delta)
    assert(ptr(v) + delta <= PTR_MASK, 'room pointer out of range')
    return v + delta
end

-- Round up to a multiple of 4: scripts and room blocks are word-aligned.
local function pad4(n)
    return (n + 3) & ~3
end

PE.ptr, PE.pad4 = ptr, pad4

-- Executable offsets of the tables locating everything inside PE.IMG.
PE.SLUS = { ['SLUS_006.62;1'] = 1, ['SLUS_006.68;1'] = 2 }
PE.ROOM_TABLE = 0x83b78
PE.ROOM_COUNT = 438

-- Which script file each room uses; rooms missing from the table carry no text.
PE.groups = require 'pe-groups'

-- Locate the script inside a room. Offsets are bytes from the start of the room.
function PE.scriptInfo(room)
    local roomSize = u32(room, 0)
    local ptrPtrs = u32(room, 4)
    local header = ptr(u32(room, ptrPtrs + 32))
    local size = u32(room, header + 8)
    local offset = ptr(u32(room, header + 12))
    return {
        roomSize = roomSize, -- bytes used by the room
        ptrPtrs = ptrPtrs, -- the pointer block
        header = header, -- the script header
        size = size, -- script bytes
        offset = offset, -- where the script starts
        -- Entry points into the script: pointers 9 and 10 bracket their table.
        entries = (ptr(u32(room, ptrPtrs + 40)) - ptr(u32(room, ptrPtrs + 36))) / 4,
    }
end

-- The script bytes of a room, and the scriptInfo they came from.
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
    -- Append room bytes [from, to) unchanged.
    local function copy(from, to) out[#out + 1] = room:sub(from + 1, to) end

    -- Room size and pointer block offset both grow by delta.
    out[#out + 1] = w32(info.roomSize + delta)
    out[#out + 1] = w32(p + delta)
    copy(8, info.offset)
    out[#out + 1] = padded
    copy(info.offset + pad4(info.size), p)
    -- The pointer block: the first word stays, the next 12 point past the script.
    copy(p, p + 4)
    for i = 1, 12 do
        out[#out + 1] = w32(movePtr(u32(room, p + i * 4), delta))
    end
    copy(p + 52, info.header + 8)
    -- The script header: new size, then the offset and entry table unchanged.
    out[#out + 1] = w32(#script)
    local pos = info.header + 12
    local keep = 1 + info.entries
    copy(pos, pos + keep * 4)
    pos = pos + keep * 4
    -- The 12-byte records to the end of the room: only the middle word moves.
    while pos + 12 <= info.roomSize do
        copy(pos, pos + 4)
        out[#out + 1] = w32(movePtr(u32(room, pos + 4), delta))
        copy(pos + 8, pos + 12)
        pos = pos + 12
    end
    return table.concat(out)
end

return PE
