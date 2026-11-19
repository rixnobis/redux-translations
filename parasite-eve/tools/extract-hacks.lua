-- Turn the executable patches of the 2004 French patcher (pe-hack.lua) into
-- slus-hacks.lua for the archive. Run with luajit: extract-hacks.lua pe-hack.lua out.lua
local src = assert(io.open(arg[1], 'rb')):read('*a')
src = src:gsub('\nmainpatch%(%)%s*$', '\n')
local env = {}
setfenv(assert(loadstring(src, '@' .. arg[1])), env)()
-- 0x1b4c renames PE.IMG to PE.TIM, which only that patcher's disc layout needs.
local skip = { [0x1b4c] = true }
local keys = {}
for k in pairs(env.slus_hacks) do if not skip[k] then keys[#keys + 1] = k end end
table.sort(keys)
local out = assert(io.open(arg[2], 'w'))
out:write('-- Executable offset -> replacement bytes.\nreturn {\n')
for _, k in ipairs(keys) do
    local b = {}
    for i, v in ipairs(env.slus_hacks[k]) do b[i] = string.format('\\%d', v) end
    out:write(string.format('    [0x%05x] = "%s",\n', k, table.concat(b)))
end
out:write('}\n')
out:close()
print(#keys .. ' patches')
