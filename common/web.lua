-- Pieces of a game's Translate web page, served by Redux's web server through
-- a Lua handler (PCSX.WebServer.Handlers) and built with PCSX.Html:
--
--   local web = require 'web'
--   local link = web.linker('/api/v1/lua/<name>')
--   return web.html('200 OK', 'Title', { ... })
--
-- A handler gets the request and returns the whole HTTP response as a string;
-- these build that string. Forms post application/x-www-form-urlencoded.
--
-- web.richScript is the rich editor (rich-text.js) once web.loadRichScript has
-- found it; richPair() makes a textarea it can show as chips.

local H = PCSX.Html

local web = {}

function web.decode(s)
    return (s:gsub('+', ' '):gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end))
end

function web.encode(s)
    return (tostring(s):gsub('[^%w%-%._~/]', function(c) return string.format('%%%02X', c:byte()) end))
end

function web.parseForm(s)
    local t = {}
    for pair in (s or ''):gmatch('[^&]+') do
        local k, v = pair:match('^([^=]*)=?(.*)$')
        t[web.decode(k)] = web.decode(v)
    end
    return t
end

-- A function turning { { name, value }, ... } into base?name=value&...
function web.linker(base)
    return function(params)
        local parts = {}
        for _, kv in ipairs(params) do parts[#parts + 1] = kv[1] .. '=' .. web.encode(kv[2]) end
        return base .. '?' .. table.concat(parts, '&')
    end
end

function web.response(status, body, headers)
    local h = { 'HTTP/1.1 ' .. status }
    for k, v in pairs(headers or {}) do h[#h + 1] = k .. ': ' .. v end
    h[#h + 1] = 'Content-Length: ' .. #body
    h[#h + 1] = 'Connection: close'
    return table.concat(h, '\r\n') .. '\r\n\r\n' .. body
end

function web.redirect(url) return web.response('303 See Other', '', { Location = url }) end

web.style = [[
body { font-family: sans-serif; margin: 1em; background: #1d1f23; color: #ddd; }
a { color: #8cf; } textarea, input { background: #2a2d33; color: #eee; border: 1px solid #555; }
textarea { width: 100%; font-family: monospace; font-size: 14px; }
.cols { display: flex; gap: 1.5em; align-items: flex-start; } .cols > div { flex: 1; } .pages { display: flex; flex-wrap: wrap; gap: 0 1em; }
.red { color: #f66; } .green { color: #6d6; } .yellow { color: #ec4; } .dim { color: #999; }
input[type=number] { width: 5em; }
.screen img { width: 640px; image-rendering: pixelated; border: 1px solid #555; }
.rich { background: #2a2d33; color: #eee; border: 1px solid #555; font-family: monospace; font-size: 14px;
        white-space: pre-wrap; min-height: 6em; padding: 2px; overflow-wrap: anywhere; }
.rich[contenteditable=true] { min-height: 9em; } .rich:focus { outline: 1px solid #8cf; }
.chip { background: #3d5a80; color: #fff; border-radius: 3px; padding: 0 3px; margin: 0 1px; font-size: 12px;
        user-select: all; cursor: default; } .chip-new { background: #80603d; }
img.gamepage { image-rendering: pixelated; border: 1px solid #555; display: block; margin: 4px 0; }
table.list td { padding: 1px 1em 1px 0; } .hist { font-family: monospace; font-size: 12px; }
]]

-- A full HTML page as a response.
function web.html(status, title, body)
    local page = H.html {
        H.head {
            H.meta { charset = 'utf-8' },
            H.title(title),
            H.style(H.raw(web.style)),
        },
        H.body(body),
    }
    return web.response(status, H.render(page), { ['Content-Type'] = 'text/html; charset=utf-8' })
end

-- Reads rich-text.js with readFile(name) (the game's own file reader, which
-- knows where the archive or source tree is), trying each name in turn.
function web.loadRichScript(readFile, names)
    for _, name in ipairs(names) do
        web.richScript = readFile(name)
        if web.richScript then return web.richScript end
    end
    print('web: rich-text.js not found, the editor stays plain text')
end

-- A text-form field that the rich editor can show as chips: the textarea is
-- what the form posts, the div the chips. lang drives the browser spellchecker.
function web.richPair(textarea, lang, readonly)
    textarea.attrs.lang = lang
    textarea.attrs.spellcheck = readonly and 'false' or 'true'
    return H.div { class = 'rich-pair',
        textarea,
        H.div { class = 'rich', lang = lang, spellcheck = readonly and 'false' or 'true',
            contenteditable = not readonly and 'true' or false, style = 'display: none' },
    }
end

-- The script element that turns every rich pair of the page into chips.
function web.richScriptTag()
    return web.richScript and H.script(H.raw(web.richScript)) or false
end

return web
