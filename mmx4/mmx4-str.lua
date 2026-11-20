-- Burn French subtitles into a Mega Man X4 STR movie, the port of the 2004
-- patcher's str_process + apply_ssa.
--
--   local new, n = require('mmx4-str').process(raw, subs)
--
-- `raw` is the movie as raw Mode 2 sectors (2336 bytes each, from the disc in
-- M2_RAW mode). `subs` describes the subtitles:
--   subs.pos     = { [n] = { x, y, w, h } }   -- where overlay n sits
--   subs.frames  = { [frameNo] = n }          -- which frame shows overlay n
--   subs.overlay = function(n) -> rgba        -- overlay n, w*h*4 bytes RGBA
--
-- An STR sector carries a 32-byte chunk header then 2016 bytes of frame data;
-- a frame is the concatenation of its chunks. For a frame the subtitles name,
-- the chunks are decoded through PCSX.MDEC, the overlay is alpha-blitted over
-- the picture, and the frame is re-encoded to fit the sectors it already used.
-- Every other sector -- audio, empty, and the video of unsubtitled frames --
-- is copied through byte for byte. Returns the new raw bytes and the number of
-- frames that got a subtitle.

local reader = require 'reader'
local floor = math.floor

local S = {}

local RAW, SUB, HDR, PAYLOAD = 2336, 8, 32, 2016
-- Submode bits in the sector subheader: video, audio, real-time.
local SM_VIDEO, SM_AUDIO = 0x08 | 0x02, 0x04

local u16, u32, w32 = reader.u16, reader.u32, reader.w32

-- Alpha-blit an RGBA overlay over a packed RGB picture. The picture is pw*ph,
-- three bytes per pixel; the overlay is ow*oh, four, placed at (ox, oy).
local function blit(rgb, pw, ph, overlay, ow, oh, ox, oy)
    for yy = 0, oh - 1 do
        local py = oy + yy
        if py >= 0 and py < ph then
            local srow = (yy * ow) * 4
            local drow = (py * pw + ox) * 3
            for xx = 0, ow - 1 do
                local px = ox + xx
                if px >= 0 and px < pw then
                    local s = srow + xx * 4
                    local a = overlay:byte(s + 4)
                    if a ~= 0 then
                        local d = drow + xx * 3
                        local ia = 255 - a
                        for c = 0, 2 do
                            rgb.data[d + c] = floor((rgb.data[d + c] * ia + overlay:byte(s + 1 + c) * a) / 255)
                        end
                    end
                end
            end
        end
    end
end

function S.process(raw, subs)
    local nsectors = floor(#raw / RAW)
    -- One editable copy of each sector; only subtitled video sectors change.
    local out = {}
    for i = 0, nsectors - 1 do out[i] = raw:sub(i * RAW + 1, i * RAW + RAW) end

    local overlays = {}
    local function overlay(n)
        if overlays[n] == nil then overlays[n] = assert(subs.overlay(n), 'missing overlay ' .. n) end
        return overlays[n]
    end

    local sm = function(i) return out[i]:byte(3) end  -- subheader submode byte (offset 2)
    local function field(i, off) return u32(out[i], SUB + off) end

    local processed = 0
    for i = 0, nsectors - 1 do
        -- A frame starts at its chunk 0; the other chunks are handled with it.
        if (sm(i) & SM_VIDEO) ~= 0 and u16(out[i], SUB + 4) == 0 then
            local count = u16(out[i], SUB + 6)
            local frameNo = field(i, 8)
            local n = subs.frames[frameNo]
            -- Gather the frame's chunks, in chunk-index order, past any audio.
            local chunks, parts, found, j = {}, {}, 0, i
            while found < count and j < nsectors do
                if (sm(j) & SM_VIDEO) ~= 0 and field(j, 8) == frameNo then
                    local idx = u16(out[j], SUB + 4)
                    chunks[idx] = j
                    parts[idx + 1] = out[j]:sub(SUB + HDR + 1, SUB + HDR + PAYLOAD)
                    found = found + 1
                end
                j = j + 1
            end
            if n and found == count then
                local width, height = u16(out[i], SUB + 16), u16(out[i], SUB + 18)
                local rgb, pw, ph = PCSX.MDEC.decodeBS(table.concat(parts), width, height)
                assert(rgb, pw)
                local p = subs.pos[n]
                blit(rgb, pw, ph, overlay(n), p.w, p.h, p.x, p.y)
                local enc, q = PCSX.MDEC.encodeBS(rgb, pw, ph, count * PAYLOAD)
                assert(enc, q)
                enc = tostring(enc)
                local size = (#enc + 3) & ~3
                enc = enc .. string.rep('\0', count * PAYLOAD - #enc)
                for idx = 0, count - 1 do
                    local sec = out[chunks[idx]]
                    -- New frame-size field, then this chunk's slice of the stream.
                    sec = sec:sub(1, SUB + 12) .. w32(size) .. sec:sub(SUB + 17)
                    sec = sec:sub(1, SUB + HDR) .. enc:sub(idx * PAYLOAD + 1, (idx + 1) * PAYLOAD) .. sec:sub(SUB + HDR + PAYLOAD + 1)
                    out[chunks[idx]] = sec
                end
                processed = processed + 1
            end
        end
    end

    local res = {}
    for k = 0, nsectors - 1 do res[k + 1] = out[k] end
    return table.concat(res), processed
end

return S
