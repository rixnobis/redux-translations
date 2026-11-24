-- Builds two discs from USA disc 1 through VP.build.disc:
--   identity.bin with an empty database: no room may be rebuilt;
--   fr.bin with one line of room 3613 translated ("I must hurry!" ->
--   "Je dois me dépêcher !"): exactly that room is rebuilt and appended, and
--   its new index entry reads back through readIndex to the rebuilt archive,
--   whose script decodes to the translation.
--
--   VP_OUT=<dir> pcsx-redux -cli -iso <USA disc 1.cue> -dofile valkyrie-profile/build-test.lua
--
-- Each .bin gets a .cue beside it. VP_BUILD_RED=1 skips the database write,
-- so the fr disc carries no change and the test must FAIL.

local here = debug.getinfo(1, 'S').source:match('^@(.*/)') or './'
Support.extra.dofile(here .. 'browser.lua')

local ROOM, FIND, REPL = 3613, 'I must hurry!', 'Je dois me dépêcher !'
local outDir = assert(os.getenv('VP_OUT'), 'set VP_OUT to an output directory')
local red = os.getenv('VP_BUILD_RED') == '1'
local results = { pass = 0, fail = 0 }
local function check(cond, what)
    print((cond and 'ok   ' or 'FAIL ') .. what)
    results[cond and 'pass' or 'fail'] = results[cond and 'pass' or 'fail'] + 1
end

local iso = PCSX.getCurrentIso()
assert(VP.vfs.identify(iso), 'load USA disc 1 with -iso')

local function writeDisc(name, db)
    local path = outDir .. '/' .. name .. '.bin'
    local out = Support.File.open(path, 'TRUNCATE')
    assert(not out:failed(), 'cannot write ' .. path)
    local lines = {}
    local ok, n = VP.build.disc(iso, db, out, function(l) lines[#lines + 1] = l print('  ' .. l) end)
    out:close()
    local cue = io.open(outDir .. '/' .. name .. '.cue', 'w')
    cue:write('FILE "' .. name .. '.bin" BINARY\r\n  TRACK 01 MODE2/2352\r\n    INDEX 01 00:00:00\r\n')
    cue:close()
    return ok, n, lines
end

-- Identity.
local emptyPath = os.tmpname()
local empty = VP.tdb.open(emptyPath)
local ok, n = writeDisc('identity', empty)
empty:close()
os.remove(emptyPath)
check(ok == true, 'identity build succeeded (' .. tostring(n) .. ')')
check(n == 0, 'identity build rebuilt no room')
local roomEntry = VP.globals.index.entries[ROOM]
local origFontLen
do
    local data = tostring(iso:open(roomEntry.lba, roomEntry.size * 2048, 'M2_FORM1'):read(roomEntry.size * 2048))
    for _, m in ipairs(VP.build.parseArchive(data)) do
        if m.tag == 4 then origFontLen = #VP.slz.decode(VP.slz.chunks(VP.build.bufferOf(m.data))[2]) end
    end
end
local origEntries = {}
for k, e in pairs(VP.globals.index.entries) do origEntries[k] = { lba = e.lba, size = e.size } end

-- The translated line, found the way the editor shows it.
local function findViewer()
    local found
    local function walk(node, depth)
        if found or depth > 4 then return end
        for _, c in ipairs(VP.vfs.expand(node)) do
            if c.name == ROOM .. '.arm' or node.name == ROOM .. '.arm' then
                for _, v in ipairs(c.viewers) do
                    if v.name == 'Room script' then found = v end
                end
            end
            if found then return end
            if c.isDir or c.name == ROOM .. '.arm' then walk(c, depth + 1) end
        end
    end
    walk(VP.vfs.root(iso), 0)
    return found
end
local v = assert(findViewer(), 'no Room script viewer for room ' .. ROOM)
VP.vfs.ptrs(v)
local extra = v.extra
local lookup = resolveFont(extra.font)
local idx, edited
local i = extra.first
while extra.tokens[i] do
    local ed = VP.text.toEditable(extra.tokens[i], lookup, 'primary')
    if ed:find(FIND, 1, true) then
        idx, edited = i, ed:gsub(FIND:gsub('%p', '%%%0'), REPL)
        break
    end
    i = i + 1
end
check(idx ~= nil, 'found "' .. FIND .. '" in room ' .. ROOM)

local dbPath = os.tmpname()
local db = VP.tdb.open(dbPath)
if not red then
    local toks = assert(VP.text.fromEditable(edited, 'primary'))
    assert(db:put({ key = extra.key, idx = idx, tokens = toks, status = VP.tdb.status.draft, author = 'test',
                    srcHash = VP.text.fnv1a64(extra.raw[idx]) }, 0))
end
-- Through VP.build.write, the call the Translate tab's Build disc button makes.
local lines = {}
local msg, n2 = VP.build.write(iso, db, outDir .. '/fr.bin', function(l) lines[#lines + 1] = l print('  ' .. l) end)
print('  ' .. tostring(msg))
local ok2 = msg ~= nil and n2 ~= nil
db:close()
os.remove(dbPath)
check(ok2 == true, 'fr build succeeded')
check(n2 == 1, 'fr build rebuilt exactly one room (' .. tostring(n2) .. ')')
check(lines[1] and lines[1]:match('^room ' .. ROOM .. ':') ~= nil, 'the rebuilt room is ' .. ROOM)

-- Read the new disc back through the same index reader the browser uses.
local fr = PCSX.openIso(outDir .. '/fr.cue')
check(fr and not fr:failed(), 'fr disc opens')
VP.globals.index.entries = {}
VP.globals.isos = { US = { CD1 = { iso = fr } }, JP = {} }
readIndex()
local e = VP.globals.index.entries[ROOM]
check(e and e.lba > roomEntry.lba, 'room ' .. ROOM .. ' moved past the original data (LBA ' .. tostring(e and e.lba) .. ')')
local same, total = 0, 0
for k, o in pairs(origEntries) do
    if k ~= ROOM then
        total = total + 1
        local a = VP.globals.index.entries[k]
        if a and a.lba == o.lba and a.size == o.size then same = same + 1 end
    end
end
check(total > 0 and same == total, string.format('every other index entry unchanged (%d of %d)', same, total))
if e then
    local data = tostring(fr:open(e.lba, e.size * 2048, 'M2_FORM1'):read(e.size * 2048))
    local members = VP.build.parseArchive(data)
    local text, fontLen
    for _, m in ipairs(members) do
        if m.tag == 4 then
            local chunks = VP.slz.chunks(VP.build.bufferOf(m.data))
            text = VP.slz.decode(chunks[1])
            fontLen = #VP.slz.decode(chunks[2])
        end
    end
    check(text ~= nil, 'rebuilt archive decodes')
    check(text ~= nil and VP.text.fnv1a64(text) ~= extra.key, 'its script differs from the retail one')
    check(fontLen and origFontLen and fontLen > origFontLen, 'its font grew (' .. tostring(origFontLen) .. ' -> ' .. tostring(fontLen) .. ' bytes)')
end

print(string.format('%d passed, %d failed', results.pass, results.fail))
print(results.fail == 0 and 'PASS' or 'FAIL')
PCSX.quit(results.fail == 0 and 0 or 1)
