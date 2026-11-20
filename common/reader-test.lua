-- Tests for reader.lua. Run them with any PCSX-Redux build:
--   pcsx-redux -cli -dofile common/reader-test.lua
-- They print one line per failure and a summary, then quit Redux.

local here = debug.getinfo(1, 'S').source:match('^@(.*[/\\])') or './'
package.path = here .. '?.lua;' .. package.path
local ffi = require 'ffi'
local r = require 'reader'

local pass, fail = 0, 0
local function eq(name, got, want)
    if got == want then
        pass = pass + 1
    else
        fail = fail + 1
        print(string.format('FAIL %s: got %s, want %s', name, tostring(got), tostring(want)))
    end
end
local function errors(name, f, ...) eq(name .. ' raises', pcall(f, ...), false) end

local s = '\x78\x56\x34\x12\xff\xff\xff\xff\x80'
eq('string u32', r.u32(s, 0), 0x12345678)
eq('string u32 top bit', r.u32(s, 4), 4294967295)
eq('string s32', r.s32(s, 4), -1)
eq('string u16 unaligned', r.u16(s, 1), 0x3456)
eq('string s8', r.s8(s, 8), -128)
errors('string past the end', r.u32, s, 6)
errors('negative offset', r.u8, s, -1)

eq('w32 top bit', r.w32(4294967295), '\xff\xff\xff\xff')
eq('w32 negative wraps', r.w32(-16777216), '\0\0\0\xff')
eq('w16', r.w16(0xbeef), '\xef\xbe')
eq('pack and read float', r.read(r.pack('float', 1.5), 0, 'float'), 1.5)

local arr = ffi.new('uint8_t[4]', 1, 2, 3, 4)
eq('ffi array', r.u32(arr, 0), 0x04030201)
errors('ffi array past the end', r.u16, arr, 3)
eq('ffi pointer', r.u16(ffi.cast('uint8_t *', arr) + 1, 0), 0x0302)
local big = ffi.new('uint8_t[16]')
big[12] = 7
eq('pointer to an array is not bounded by the pointer size', r.u8(ffi.cast('uint8_t (*)[16]', big), 12), 7)

local f = Support.File.buffer()
f:write(s)
f:rSeek(0)
local lb = f:read(9)
eq('LuaBuffer', r.u32(lb, 0), 0x12345678)
errors('LuaBuffer past the end', r.u32, lb, 6)
eq('File:readAt', r.u32(f:readAt(4, 4), 0), 4294967295)

local slice = Support.File.createEmptySlice()
slice.size = 4
for i = 0, 3 do slice[i] = 0x10 + i end
eq('Slice', r.u32(slice, 0), 0x13121110)
errors('Slice past the end', r.u32, slice, 1)

errors('number as data', r.u8, 42, 0)

print(string.format('reader: %d passed, %d failed', pass, fail))
PCSX.quit(fail == 0 and 0 or 1)
