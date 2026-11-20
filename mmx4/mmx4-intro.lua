-- The French credits intro that replaces the Capcom logo movie, the port of
-- the 2004 patcher's create_intro and intro_timeline.
--
--   local raw, frames = require('mmx4-intro').build(capcom20, load)
--
-- `capcom20` is CAPCOM20.STR as raw Mode 2 sectors (2336 bytes each). `load`
-- returns the bytes of a file of the patch's INTRO folder: 320x240 pictures,
-- packed RGB (.rgb) or RGBA (.rgba), and intro.xa, the soundtrack as 2324-byte
-- XA sectors. Returns the new movie as raw sectors, and the frame count the
-- executable has to stop at, which `exeFrames` turns into a patch.
--
-- The timeline below is a list of steps, each showing a picture for a
-- duration, optionally mixed with a second picture by an effect. Each step is
-- sampled at 1/15 s, the frames encoded through PCSX.MDEC into 7 video
-- sectors each, followed by one XA sector. The original movie is then
-- appended with its frame numbers moved past the new frames.

local reader = require 'reader'
local ffi = require 'ffi'
local u32, w16, w32 = reader.u32, reader.w16, reader.w32
local floor = math.floor

local I = {}

local W, H = 320, 240
local RAW, SUB, HDR, PAYLOAD, XA = 2336, 8, 32, 2016, 2324
local CHUNKS = 7
-- Subheader of the new sectors, as the patcher wrote them: file 1, channel 1;
-- video is submode 0x42 (real-time, video) with coding info 0x80, audio is
-- 0x64 (form 2, real-time, audio) with coding info 1 (37.8 kHz stereo).
local VIDEO_SUB = string.char(1, 1, 0x42, 0x80):rep(2)
local AUDIO_SUB = string.char(1, 1, 0x64, 0x01):rep(2)
-- The patcher's STR chunk status and type words.
local ST_STATUS, ST_TYPE = 0x160, 0x8001

-- Where the executable keeps the last frame of the intro movie.
I.EXE_FRAMES = 0xe2508
-- The patcher adds this to its next frame number: the original value at
-- EXE_FRAMES, so the appended Capcom movie still stops where it did.
local CAPCOM_FRAMES = 0x92

local function zeros(n) return string.rep('\0', n) end

-- Alpha-blend a W*H source over the RGB picture `dst`, moved down y rows, as
-- the patcher's blit did: d = (d * (255 - a) + s * a) >> 8. `step` is the
-- source's bytes per pixel; with 3, `a` is the fixed alpha, with 4 the
-- source's own.
local function blend(dst, src, step, y, a)
    local p = ffi.cast('const uint8_t *', src)
    for dy = math.max(0, y), math.min(H, y + H) - 1 do
        local d, s = dy * W * 3, (dy - y) * W * step
        for _ = 1, W do
            local alpha = a or p[s + 3]
            if alpha ~= 0 then
                for c = 0, 2 do
                    dst[d + c] = (dst[d + c] * (255 - alpha) + p[s + c] * alpha) >> 8
                end
            end
            d, s = d + 3, s + step
        end
    end
end

-- The blit took integer positions: C truncates toward zero.
local function trunc(v) return v < 0 and -floor(-v) or floor(v) end

-- The effects mix picture B into picture A (already copied to `dst`) for a
-- position `scale` from 0 to 1 through the step.
local effects = {
    -- Cross-fade from A to B.
    fade_in = function(dst, b, scale) blend(dst, b, 3, 0, floor(scale * 255)) end,
    -- B drops in from above and settles in a damped bounce.
    bounce_in = function(dst, b, scale)
        blend(dst, b, 4, trunc(-240 * math.exp(-scale / .2) * math.cos(2 * math.pi * scale / .55)))
    end,
    -- B falls out the bottom.
    bounce_out = function(dst, b, scale) blend(dst, b, 4, trunc(240 * scale * scale)) end,
    -- B sits over A.
    alpha_blend = function(dst, b) blend(dst, b, 4, 0) end,
}

-- The patcher's intro_timeline: seconds, picture, then picture B and effect.
local function title(n)
    local t = string.format('title-%02d.rgba', n)
    return { 1.6, 'frame-04.rgb', t, 'bounce_in' }, { n == 1 and 4.0 or 3.0, 'frame-04.rgb', t, 'alpha_blend' },
           { 0.6, 'frame-04.rgb', t, 'bounce_out' }
end
local timeline = {
    { 2.0, 'black.rgb', 'white.rgb', 'fade_in' },
    { 2.0, 'white.rgb', 'frame-01.rgb', 'fade_in' },
    { 1.4, 'frame-01.rgb' },
    { 2.0, 'frame-01.rgb', 'frame-02.rgb', 'fade_in' },
    { 1.2, 'frame-02.rgb' },
    { 2.0, 'frame-02.rgb', 'frame-03.rgb', 'fade_in' },
    { 1.5, 'frame-03.rgb' },
    { 1.0, 'frame-03.rgb', 'frame-04.rgb', 'fade_in' },
    { 0.2, 'frame-04.rgb' },
}
for n = 1, 6 do
    for _, step in ipairs { title(n) } do timeline[#timeline + 1] = step end
end
for _, step in ipairs {
    { 0.3, 'frame-04.rgb' },
    { 1.8, 'frame-04.rgb', 'frame-last.rgb', 'fade_in' },
    { 5.6, 'frame-last.rgb' },
    { 2.0, 'frame-last.rgb', 'black.rgb', 'fade_in' },
    { 3.0, 'black.rgb' },
} do timeline[#timeline + 1] = step end
I.timeline = timeline

-- The 7 video sectors of one frame, then one audio sector.
local function frameSectors(bs, frameNo, audio)
    -- Rounded up to a word like mmx4-str; the patcher wrote the exact size.
    local size = (#bs + 3) & ~3
    bs = bs .. zeros(CHUNKS * PAYLOAD - #bs)
    local out = {}
    for i = 0, CHUNKS - 1 do
        out[#out + 1] = VIDEO_SUB .. w16(ST_STATUS) .. w16(ST_TYPE) .. w16(i) .. w16(CHUNKS) .. w32(frameNo)
            .. w32(size) .. w16(W) .. w16(H) .. zeros(12) .. bs:sub(i * PAYLOAD + 1, (i + 1) * PAYLOAD)
            .. zeros(RAW - SUB - 2048)
    end
    out[#out + 1] = AUDIO_SUB .. audio .. zeros(XA - #audio) .. zeros(RAW - SUB - XA)
    return table.concat(out)
end

function I.build(capcom20, load)
    local pictures = {}
    local function picture(name)
        if not pictures[name] then pictures[name] = assert(load(name), 'missing INTRO/' .. name) end
        return pictures[name]
    end
    local xa = assert(load('intro.xa'), 'missing INTRO/intro.xa')

    local out, frameNo, xaSector = {}, 1, 0
    local rgb = ffi.new('uint8_t[?]', W * H * 3)
    for _, step in ipairs(timeline) do
        local duration, a, b, effect = step[1], picture(step[2]), step[3] and picture(step[3]), effects[step[4]]
        -- The patcher's own loop: time accumulates in 1/15 s steps and the
        -- step ends once it passes the duration, rounding included.
        local t = 0
        while t <= duration do
            ffi.copy(rgb, a, W * H * 3)
            if effect then effect(rgb, b, t / duration) end
            local bs, err = PCSX.MDEC.encodeBS(ffi.string(rgb, W * H * 3), W, H, CHUNKS * PAYLOAD)
            assert(bs, err)
            local audio = xa:sub(xaSector * XA + 1, (xaSector + 1) * XA)
            out[#out + 1] = frameSectors(tostring(bs), frameNo, audio)
            xaSector = xaSector + 1
            t = t + 1 / 15
            frameNo = frameNo + 1
        end
    end

    -- The Capcom movie follows, its frame numbers moved by frameNo. The
    -- patcher rebuilt each sector from its fields; the data is the same
    -- (its empty sectors are zeros on the disc).
    for i = 0, floor(#capcom20 / RAW) - 1 do
        local sec = capcom20:sub(i * RAW + 1, (i + 1) * RAW)
        local cn, sm, ci = sec:byte(2), sec:byte(3), sec:byte(4)
        if (sm & 0x02) ~= 0 or (sm & 0x08) ~= 0 then
            sec = sec:sub(1, SUB + 8) .. w32(u32(sec, SUB + 8) + frameNo) .. sec:sub(SUB + 13)
        elseif (sm & 0x04) == 0 and not (cn == 0 and sm == 0 and ci == 0) then
            error(string.format('unexpected sector %d in CAPCOM20.STR: submode %02x', i, sm))
        end
        out[#out + 1] = sec
    end
    return table.concat(out), frameNo + CAPCOM_FRAMES, xaSector
end

-- The executable patch for the new frame count.
function I.exeFrames(frames) return w16(frames) end

return I
