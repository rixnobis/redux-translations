-- The model behind a game's Translate views: the open translation database
-- (common/tdb.lua), one string's edit state, the versioned save, the history,
-- and the glyph edits. Nothing here draws, and nothing here knows a game's
-- text format: that comes from the game table given to install().
--
--   local M = require('tmodel').install({}, game)
--
-- A script is whatever object the game uses for one set of strings; this
-- module only hands it back to the game. The game table provides:
--   open(path)                 -> a database (tdb.open with the game's options)
--   onOpen(db)                 optional, called after a database opens
--   key(script), first(script) the database key and the first string index
--   source(script, i)          the original tokens of string i
--   hash(script, i)            the hash stored as srcHash for string i
--   editable(tokens, lookup)   tokens as the text a translator edits
--   parse(script, text, charset) -> tokens, or nil, message, byte position
--   originalBox(script, i)     { x, y, width, height } of string i, numbers or nil
--   saveContext(script, i, lookup)  the context handed to beforeSave hooks
--   defaultCharset()           the characters allowed with no database open
--   glyph                      the glyph format, see the Glyphs section below
--
-- An edit state is a plain table: base (the version it was loaded from), text,
-- status, note, override and boxX/boxY/boxW/boxH, sourceChanged, and
-- optionally author (the translator saving it, M.author when absent).

local tdb = require 'tdb'

local T = {}

function T.install(M, game)
    M.game = game
    M.author = M.author or os.getenv('USER') or ''

    function M.open(path)
        if M.db then M.db:close() end
        M.db, M.dbError = nil, nil
        local ok, db = pcall(game.open, path)
        if ok then
            M.db, M.openPath = db, path
            if game.onOpen then game.onOpen(db) end
        else
            M.dbError = tostring(db)
        end
        return M.db
    end

    -- The edit state of string i as the database holds it now.
    function M.loadEdit(script, i, lookup)
        local row = M.db:get(game.key(script), i)
        local live = row and not row.deletedAt
        local e = {
            base = row and row.version or 0,
            text = game.editable(live and row.tokens or game.source(script, i), lookup),
            status = live and row.status or tdb.status.untranslated,
            note = live and row.note or '',
            override = live and (row.boxX or row.boxY or row.boxW or row.boxH) and true or false,
            sourceChanged = row and row.srcHash and row.srcHash ~= game.hash(script, i),
        }
        local box = game.originalBox(script, i)
        e.boxX = live and row.boxX or box.x or 0
        e.boxY = live and row.boxY or box.y or 0
        e.boxW = live and row.boxW or box.width or 0
        e.boxH = live and row.boxH or box.height or 0
        return e
    end

    -- The edit's text as tokens, or nil, message, byte position. Only
    -- characters of the database's target language parse.
    function M.parse(script, e) return game.parse(script, e.text, M.charset()) end

    -- Characters the open database's target language may use.
    function M.charset() return M.db and M.db:charset() or game.defaultCharset() end

    -- Sets the open database's languages (BCP 47 tags). Returns true, or nil
    -- and a message, in which case neither changed.
    function M.setLanguages(target, source)
        if not M.db then return nil, 'No database open' end
        for _, t in ipairs({ target, source }) do
            if not M.db.languages.valid(t) then return nil, 'Not a language tag: ' .. tostring(t) end
        end
        M.db:setLanguage('target', target)
        M.db:setLanguage('source', source)
        return true
    end

    -- The open database's target and source languages, or the defaults.
    function M.languages()
        if not M.db then return 'fr', 'en' end
        return M.db:targetLanguage(), M.db:sourceLanguage()
    end

    local function rowFromEdit(script, i, e, tokens)
        local author = e.author or M.author
        local row = {
            key = game.key(script), idx = i, srcHash = game.hash(script, i), tokens = tokens, status = e.status,
            author = author ~= '' and author or nil, note = e.note ~= '' and e.note or nil,
        }
        if e.override then row.boxX, row.boxY, row.boxW, row.boxH = e.boxX, e.boxY, e.boxW, e.boxH end
        return row
    end

    -- Saves e as the version after `expected`. Returns 'saved', row;
    -- 'conflict', their row; or 'error', message. On success e.base and
    -- e.sourceChanged follow.
    function M.save(script, i, e, tokens, expected, lookup)
        local ok, r = M.db:put(rowFromEdit(script, i, e, tokens), expected, game.saveContext(script, i, lookup))
        if ok then
            e.base, e.sourceChanged = r.version, false
            return 'saved', r
        elseif ok == false then
            return 'conflict', r
        end
        return 'error', r
    end

    -- First string after `from` (wrapping) with no live translation.
    function M.nextUntranslated(script, count, from)
        local first, key = game.first(script), game.key(script)
        local n = count - first + 1
        for k = 1, n do
            local i = (from - first + k) % n + first
            local row = M.db:get(key, i)
            if not row or row.deletedAt or row.status == tdb.status.untranslated then return i end
        end
        return nil
    end

    -- Counts by status over strings first..count, indexed 0..2.
    function M.counts(script, count)
        local first = game.first(script)
        local c = { [0] = 0, 0, 0 }
        local seen = 0
        for row in M.db:query { script = game.key(script) } do
            if row.idx >= first and row.idx <= count then
                c[row.status] = (c[row.status] or 0) + 1
                seen = seen + 1
            end
        end
        c[0] = c[0] + (count - first + 1 - seen)
        return c
    end

    -- One line per saved version of string i, oldest first.
    function M.history(script, i, lookup)
        local out = {}
        for _, h in ipairs(M.db:history(game.key(script), i)) do
            local t = h.tokens and game.editable(h.tokens, lookup):gsub('\n', ' / ') or ''
            if #t > 80 then t = t:sub(1, 80) .. '...' end
            out[#out + 1] = string.format('v%d %s %s %s%s: %s', h.version, os.date('!%Y-%m-%d %H:%M', h.updatedAt),
                h.author or '?', tdb.statusNames[h.status] or '?', h.deletedAt and ' (deleted)' or '', t)
        end
        return out
    end

    -- Glyphs. The database's target language owns a set of edited and added
    -- glyphs (tdb putGlyph); the views edit them through these. game.glyph
    -- provides rows(data, height), blank(), encode(rows), extent(rows),
    -- origin(ch, lang, live), entries(lang, edits), check(glyph, charset) and
    -- height. A glyph edit state is: ch, base (the stored version it was read
    -- at, 0 for none), rows, width (the advance), origin ('retail', 'letter',
    -- 'edited', 'added' or 'new'), note, and conflict after a stale save.
    local G = game.glyph

    function M.glyphEntries()
        return G.entries(M.db:glyphLanguage(), M.db:glyphEdits())
    end

    function M.loadGlyph(ch)
        local row = M.db:glyph(ch)
        local g = M.db:charset()[ch]
        local live = row and not row.deletedAt
        return {
            ch = ch,
            base = row and row.version or 0,
            rows = g and G.rows(g.data, g.height) or G.blank(),
            width = g and g.width or 1,
            origin = g and G.origin(ch, M.db:targetLanguage(), live) or 'new',
            note = live and row.note or '',
        }
    end

    -- The glyph an edit state describes, as tdb:putGlyph takes it.
    function M.glyphOf(ge)
        return { ch = ge.ch, width = ge.width, height = G.height, data = G.encode(ge.rows),
            note = ge.note ~= '' and ge.note or nil, author = ge.author or M.author }
    end

    -- Problems (refusals) and notes of an edit state.
    function M.checkGlyph(ge) return G.check(M.glyphOf(ge), M.db:charset()) end

    -- Returns 'saved' and the row, 'conflict' and the stored row, or 'error'
    -- and a message. expected defaults to the version the state was read at.
    function M.saveGlyph(ge, expected)
        local ok, r = M.db:putGlyph(M.glyphOf(ge), expected or ge.base)
        if ok then return 'saved', r end
        if ok == false then return 'conflict', r end
        return 'error', r
    end

    -- Back to the retail or language glyph (an added character goes away).
    function M.revertGlyph(ge, expected)
        local ok, r = M.db:deleteGlyph(ge.ch, expected or ge.base, ge.author or M.author)
        if ok then return 'saved', r end
        if ok == false then return r and 'conflict' or 'error', r or 'Nothing to revert: the glyph was never edited.' end
    end

    -- One line per stored version of ch.
    function M.glyphHistory(ch)
        local out = {}
        for _, h in ipairs(M.db:glyphHistory(ch)) do
            out[#out + 1] = string.format('v%d %s %s: %s, advance %d, extent %d%s', h.version,
                os.date('!%Y-%m-%d %H:%M', h.updatedAt), h.author or '?', h.deletedAt and 'reverted' or 'saved',
                h.width, G.extent(G.rows(h.data, h.height)), h.note and (' (' .. h.note .. ')') or '')
        end
        return out
    end

    return M
end

return T
