-- Test helper: press pad buttons on a schedule. PE_PLAN="50:START,62:START,66:UP,69:CROSS"
-- (seconds since start). Used with -dofile to drive a rebuilt disc to its first room.
local pad = PCSX.SIO0.slots[1].pads[1]
local B = PCSX.CONSTS.PAD.BUTTON
local plan = {}
for line in (os.getenv('PE_PLAN') or ''):gmatch('[^,]+') do
  local t, b = line:match('(%d+):(%u+)'); plan[#plan + 1] = { tonumber(t), B[b] }
end
local start = os.time()
local prev = DrawImguiFrame
local held, heldUntil, idx = nil, 0, 1
function DrawImguiFrame()
  if prev then prev() end
  local now = os.time() - start
  if held and now >= heldUntil then pad.clearOverride(held); held = nil end
  local p = plan[idx]
  if p and not held and now >= p[1] then pad.setOverride(p[2]); held = p[2]; heldUntil = now + 1; idx = idx + 1 end
end
