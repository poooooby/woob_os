-- The Pokédex app (every game): a modern, split-screen Pokédex over src/dex.lua. On the left a grid of
-- the dex's Pokémon (its number, its icon, its name; a silhouette until it's seen, a ball once it's
-- caught); on the right the chosen one's page: its front picture (Emerald's own animation, a breathing
-- idle elsewhere), name, category, types, height and weight, gender ratio, the dex's words, a radar of
-- its base stats, its abilities, and Moves / Where / Info, and Forms where it has any (WoobleDex's: each
-- form's picture and name, a Poké Ball under those caught; each opens its own page: its types, stats, moves
-- and where it's found, by the same rules). The game's rules: unseen nothing, seen the card, where to find
-- it and its forms, caught everything. Narrow (WoobPad upright), the grid and the page
-- take turns.
--   buttons  the D-pad moves in the grid, L / R a page, A the page (Up / Down scroll it, L / R its tab,
--            Left / Right the moves' list, A its cry; on Forms Left / Right a form, A its page, B from a
--            form's page back to the base one), SELECT the regional or National dex, B back,
--            START the game's own Pokédex (when it was opened in its place); Up from the grid's top row the
--            search (A opens its keyboard: the D-pad a key, A types it, B deletes, START goes)
--   touch    a tap picks; the tabs, the moves' chips, the picture (its cry); drag or wheel scrolls; the
--            magnifier the search, its keys typed by a tap, a tap outside it puts it away
--   search   a name (only the seen: an unseen one's name stays hidden) or a number, matched as it's typed:
--            the first whose name starts so, else holds it, else the nearest spelling; a number the entry with
--            it, else the nearest; Go (or START) leaves the grid on it
--
--   window(ctx, env, view) -> win (src/apps.lua)   view: src/apps/pokedex_view.lua's maker; env.dex
--                            (src/dex.lua), env.dexSprite, env.monIcon, env.cry, env.se
--   ctx.classic(): the game's own Pokédex (the START menu's takeover)

local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil

local A = { CELL = 10000, MODE = 900, TAB = 800, KIND = 700, SPRITE = 600, BACK = 590, FORM = 400, KEY = 300,
            SEARCH = 299, KB_SCRIM = 298, KB_GO = 297, CLASSIC = 296 }
-- the search's keyboard: each key's row, its left edge and width in tenths of the row (iOS's: the digits,
-- three rows of letters, the last with Delete, then space and Go)
local KB_ROWS = {
  { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
  { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
  { "A", "S", "D", "F", "G", "H", "J", "K", "L" },
  { "Z", "X", "C", "V", "B", "N", "M", "DEL" },
  { "SPACE", "GO" },
}
local KB = { keys = {}, row = {}, x0 = {}, w = {}, first = {}, count = {} }
for r, keys in ipairs(KB_ROWS) do
  KB.first[r], KB.count[r] = #KB.keys + 1, #keys
  for c, key in ipairs(keys) do
    local k = #KB.keys + 1
    KB.keys[k], KB.row[k] = key, r
    if r <= 2 then KB.x0[k], KB.w[k] = c - 1, 1
    elseif r == 3 then KB.x0[k], KB.w[k] = c - 0.5, 1
    elseif key == "DEL" then KB.x0[k], KB.w[k] = 8.3, 1.7
    elseif r == 4 then KB.x0[k], KB.w[k] = c, 1
    elseif key == "SPACE" then KB.x0[k], KB.w[k] = 0, 7.4
    else KB.x0[k], KB.w[k] = 7.6, 2.4 end
  end
end
local KB_MAX = 12
local KINDS = { "level", "tm", "egg", "tutor" }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })
local HINTS = {
  grid = { { "+", "dex.hint.choose" }, { "A", "dex.hint.page" }, { "L R", "dex.hint.flip" }, { "B", "hint.back" } },
  gridModes = { { "+", "dex.hint.choose" }, { "A", "dex.hint.page" }, { "L R", "dex.hint.flip" },
                { "SELECT", "dex.hint.mode" }, { "B", "hint.back" } },
  page = { { "+", "dex.hint.scroll" }, { "L R", "dex.hint.tabs" }, { "A", "dex.hint.cry" }, { "B", "hint.back" } },
  pageModes = { { "+", "dex.hint.scroll" }, { "L R", "dex.hint.tabs" }, { "A", "dex.hint.cry" },
                { "SELECT", "dex.hint.mode" }, { "B", "hint.back" } },
  forms = { { "< >", "dex.hint.form" }, { "A", "dex.hint.view" }, { "L R", "dex.hint.tabs" }, { "B", "hint.back" } },
  searchBtn = { { "A", "dex.search.open" }, { "+", "dex.hint.choose" }, { "B", "hint.back" } },
  search = { { "+", "dex.hint.choose" }, { "A", "dex.search.type" }, { "B", "dex.search.del" },
             { "START", "dex.search.go" } },
}

-- a name as it's matched: lower case, letters and digits only ("Mr. Mime" -> "mrmime", "Ho-Oh" -> "hooh")
local normOf = setmetatable({}, { __mode = "k" })
local function norm(s) return (tostring(s or ""):lower():gsub("[^%w]", "")) end
local function normName(e)
  local n = normOf[e]
  if not n then
    n = norm(e.name)
    normOf[e] = n
  end
  return n
end
-- how far apart two spellings are (letters to change, add or drop)
local function distance(a, b)
  local la, lb = #a, #b
  if la == 0 then return lb end
  if lb == 0 then return la end
  local prev, cur = {}, {}
  for j = 0, lb do prev[j] = j end
  for i = 1, la do
    cur[0] = i
    local ca = a:byte(i)
    for j = 1, lb do
      local cost = ca == b:byte(j) and 0 or 1
      local v = prev[j] + 1
      if cur[j - 1] + 1 < v then v = cur[j - 1] + 1 end
      if prev[j - 1] + cost < v then v = prev[j - 1] + cost end
      cur[j] = v
    end
    prev, cur = cur, prev
  end
  return prev[lb]
end
-- the list's entry the words find -> its index | nil
local function search(list, text)
  local q = norm(text)
  if q == "" then return nil end
  if q:find("^%d+$") then
    local n, best, bestD = tonumber(q), nil, nil
    for i, e in ipairs(list) do
      local d = math.abs((tonumber(e.num) or 0) - n)
      if d == 0 then return i end
      if not bestD or d < bestD then best, bestD = i, d end
    end
    return best
  end
  local sub
  for i, e in ipairs(list) do
    if e.seen then
      local nm = normName(e)
      if nm:sub(1, #q) == q then return i end
      if not sub and nm:find(q, 1, true) then sub = i end
    end
  end
  if sub then return sub end
  -- (the nearest spelling: against the name's own start as long as the words, or the whole name)
  local best, bestD = nil, math.max(1, math.floor(#q / 3)) + 1
  for i, e in ipairs(list) do
    if e.seen then
      local nm = normName(e)
      local d = math.min(distance(q, nm:sub(1, #q)), distance(q, nm))
      if d < bestD then best, bestD = i, d end
    end
  end
  return best
end

return function(ctx, env, makeView)
  local K, T, Dx = env.K, env.T or NO_T, env.dex
  local W = { title = T("app.pokedex") }
  local s = ctx.session or (env.session and env.session())
  local function se(name) if env.se then pcall(env.se, name) end end

  local book = Dx and Dx.open(s) or { modes = {}, lists = {}, counts = {} }
  local st = {
    book = book, mi = 1, list = book.lists[book.modes[1]] or {}, sel = 1, page = nil, entry = nil,
    focus = "grid", detail = false, narrow = false,
    gridTop = 0, cols = 4, visRows = 3, follow = true,
    detailTop = 0, detailH = 0, detailVis = 80,
    -- (the page's tabs: ids, "moves" / "where" / "info" / "size" / "forms", for the one chosen; st.tab the
    -- index)
    tab = 1, tabId = "moves", tabs = {}, forms = {},
    -- (the forms: the one shown (1, the base) and the one the Forms tab's cursor is on; base: the grid's)
    formAt = 1, formSel = 1, base = nil,
    kind = 1, shown = { 0, 0, 0, 0, 0, 0 }, chosenAt = 0, lines = {},
    modeWords = {},
  }
  W.state, W.A = st, A
  st.KB = KB
  for i, m in ipairs(book.modes) do st.modeWords[i] = T("dex.mode." .. m) end

  local function now() return env.now and env.now() or 0 end

  -- the chosen one's tabs: caught, Moves / Where / Info / Size; seen, Where; and Forms after them where it
  -- has forms. The same tab kept when it's there
  local function setTabs(e)
    local list = st.tabs
    for i = #list, 1, -1 do list[i] = nil end
    if e and e.caught then
      list[1], list[2], list[3], list[4] = "moves", "where", "info", "size"
    elseif e then
      list[1] = "where"
    end
    if #st.forms > 1 then list[#list + 1] = "forms" end
    st.tab = 1
    for i, id in ipairs(list) do
      if id == st.tabId then st.tab = i end
    end
    st.tabId = list[st.tab] or "where"
  end

  -- a Pokémon chosen: its page made (an action, never a draw), its picture's animation started
  local function choose(i, quiet)
    local n = #st.list
    if n == 0 then return end
    i = max(1, min(n, i))
    local moved = i ~= st.sel or not st.entry
    st.sel = i
    st.entry = st.list[i]
    st.page = st.entry.seen and Dx.page(st.entry) or nil
    -- (one not seen yet: where to look for it, its name and the rest still hidden; nil where it isn't found)
    st.hint = nil
    if not st.entry.seen and Dx.where then
      local rows = Dx.where(st.entry)
      if rows and #rows > 0 then st.hint = { where = rows } end
    end
    st.forms = st.entry.seen and Dx.forms and Dx.forms(st.entry, s) or {}
    st.base, st.formAt, st.formSel = st.entry, 1, 1
    setTabs(st.entry)
    st.follow = true
    if moved then
      st.detailTop = 0
      st.chosenAt = now()
      if env.dexSprite and st.entry.seen then env.dexSprite.start(st.entry.sp) end
      if not quiet then se("SE_SELECT") end
    end
  end
  local function cry()
    local e = st.entry
    if not (e and e.seen) then return end
    if env.dexSprite then env.dexSprite.start(e.sp) end
    st.chosenAt = now()
    if env.cry then pcall(env.cry, e.sp) end
  end
  local function setMode(i)
    if #book.modes < 2 then return end
    i = (i - 1) % #book.modes + 1
    if i == st.mi then return end
    local sp = st.entry and st.entry.sp
    st.mi, st.list = i, book.lists[book.modes[i]] or {}
    st.gridTop, st.sel, st.entry = 0, 1, nil
    -- (the same Pokémon when it's in the other dex too)
    for j, e in ipairs(st.list) do
      if e.sp == sp then st.sel = j break end
    end
    choose(st.sel, true)
    se("SE_SELECT")
  end
  -- (a page to open: seen, or where to look for one not seen yet)
  local function hasPage() return st.entry ~= nil and (st.entry.seen or st.hint ~= nil) end
  local function openPage()
    if not hasPage() then return se("SE_FAILURE") end
    if st.narrow then st.detail = true end
    st.focus = "detail"
    cry()
  end
  local function back()
    st.focus = "grid"
    st.detail = false
    se("SE_SELECT")
  end
  local function setTab(t)
    local n = #st.tabs
    if n < 2 then return end
    st.tab = (t - 1) % n + 1
    st.tabId = st.tabs[st.tab]
    st.detailTop = min(st.detailTop, max(0, st.detailH - st.detailVis))
    se("SE_SELECT")
  end
  -- one of the forms opened in the base's place (1: the base again): its own page by the same rules; one
  -- not seen yet, where to look for it (nowhere known: nothing to open)
  local function openForm(k)
    local f = st.forms[k]
    if not (f and st.base) then return end
    st.formSel = k
    if k == st.formAt then return cry() end
    local e = Dx.formEntry and Dx.formEntry(st.base, f) or nil
    if not e then return se("SE_FAILURE") end
    local hint = nil
    if not e.seen then
      local rows = Dx.where and Dx.where(e)
      if not (rows and #rows > 0) then return se("SE_FAILURE") end
      hint = { where = rows }
    end
    st.formAt, st.entry, st.hint = k, e, hint
    st.page = e.seen and Dx.page(e) or nil
    setTabs(e)
    st.detailTop = 0
    st.focus = "detail"
    if st.narrow then st.detail = true end
    st.chosenAt = now()
    if e.seen then
      if env.dexSprite then env.dexSprite.start(e.sp) end
      if env.cry then pcall(env.cry, e.sp) end
    end
    se("SE_SELECT")
  end
  local function moveForm(d)
    local n = #st.forms
    if n < 2 then return end
    st.formSel = (st.formSel - 1 + d) % n + 1
    se("SE_SELECT")
  end

  local function setKind(k)
    st.kind = (k - 1) % #KINDS + 1
    se("SE_SELECT")
  end

  -- ------- the search: a keyboard on a glass sheet; the grid follows the words as they're typed
  local function openSearch()
    if #st.list == 0 then return se("SE_FAILURE") end
    st.kb = { text = "", cur = KB.first[2], from = st.sel, hit = nil, at = now(), typedK = nil, typedAt = -1 }
    st.focus = "grid"
    se("SE_SELECT")
  end
  local function closeSearch(go)
    local kb = st.kb
    if not kb then return end
    st.kb = nil
    if go and kb.hit then
      choose(kb.hit, true)
      st.follow = true
      se("SE_SELECT")
      if st.narrow and hasPage() then openPage() end
    else
      if kb.from ~= st.sel then choose(kb.from, true) end
      st.follow = true
      se("SE_SELECT")
    end
  end
  local function refind()
    local kb = st.kb
    kb.hit = search(st.list, kb.text)
    if kb.hit and kb.hit ~= st.sel then choose(kb.hit, true) end
    st.follow = true
  end
  local function typeKey(k)
    local kb = st.kb
    local key = KB.keys[k]
    if not (kb and key) then return end
    kb.cur, kb.typedK, kb.typedAt = k, k, now()
    if key == "GO" then return closeSearch(true) end
    if key == "DEL" then
      if kb.text == "" then return se("SE_FAILURE") end
      kb.text = kb.text:sub(1, -2)
    elseif key == "SPACE" then
      if kb.text == "" or kb.text:sub(-1) == " " or #kb.text >= KB_MAX then return se("SE_FAILURE") end
      kb.text = kb.text .. " "
    else
      if #kb.text >= KB_MAX then return se("SE_FAILURE") end
      kb.text = kb.text .. key
    end
    se("SE_SELECT")
    refind()
  end
  -- (the D-pad on the keyboard: along a row, wrapping; up or down to the key nearest above or below)
  local function kbMove(dr, dc)
    local kb = st.kb
    local k = kb.cur
    local r = KB.row[k]
    if dc ~= 0 then
      local f, n = KB.first[r], KB.count[r]
      kb.cur = f + (k - f + dc) % n
      return
    end
    local r2 = (r - 1 + dr) % #KB_ROWS + 1
    local mid = KB.x0[k] + KB.w[k] / 2
    local best, bestD = KB.first[r2], nil
    for j = KB.first[r2], KB.first[r2] + KB.count[r2] - 1 do
      local d = math.abs(KB.x0[j] + KB.w[j] / 2 - mid)
      if not bestD or d < bestD then best, bestD = j, d end
    end
    kb.cur = best
  end
  st.search = search

  choose(1, true)

  -- ------- the window's contract

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
    if st.kb then
      if pressed("start") then closeSearch(true)
      elseif pressed("b") then
        if st.kb.text == "" then closeSearch(false) else typeKey(KB.first[4] + KB.count[4] - 1) end
      elseif pressed("a") then typeKey(st.kb.cur)
      elseif nav.left then kbMove(0, -1)
      elseif nav.right then kbMove(0, 1)
      elseif nav.up then kbMove(-1, 0)
      elseif nav.down then kbMove(1, 0) end
      return true
    end
    if st.focus == "searchBtn" then
      if pressed("a") then openSearch()
      elseif nav.down or pressed("b") then st.focus = "grid"
      elseif pressed("select") then setMode(st.mi + 1)
      elseif pressed("start") and ctx.classic then ctx.classic() end
      return true
    end
    if pressed("start") and ctx.classic then
      ctx.classic()
      return true
    end
    if st.focus == "detail" then
      if pressed("b") then
        if st.formAt ~= 1 then openForm(1) else back() end
        return true
      end
      if pressed("select") then setMode(st.mi + 1) return true end
      if nav.up then st.detailTop = max(0, st.detailTop - 12)
      elseif nav.down then st.detailTop = min(max(0, st.detailH - st.detailVis), st.detailTop + 12)
      elseif pressed("l") then setTab(st.tab - 1)
      elseif pressed("r") then setTab(st.tab + 1)
      elseif st.tabId == "moves" and nav.left then setKind(st.kind - 1)
      elseif st.tabId == "moves" and nav.right then setKind(st.kind + 1)
      elseif st.tabId == "forms" and nav.left then moveForm(-1)
      elseif st.tabId == "forms" and nav.right then moveForm(1)
      elseif st.tabId == "forms" and pressed("a") then openForm(st.formSel)
      elseif pressed("a") then cry() end
      return true
    end
    if pressed("b") then return false end
    local cols = max(1, st.cols)
    if nav.left then choose(st.sel - 1)
    elseif nav.right then choose(st.sel + 1)
    elseif nav.up then
      if st.sel - cols < 1 then
        st.focus = "searchBtn"
        se("SE_SELECT")
      else
        choose(st.sel - cols)
      end
    elseif nav.down then choose(st.sel + cols)
    elseif pressed("l") then choose(st.sel - cols * max(1, st.visRows))
    elseif pressed("r") then choose(st.sel + cols * max(1, st.visRows))
    elseif pressed("select") then setMode(st.mi + 1)
    elseif pressed("a") then openPage() end
    return true
  end

  -- (the START menu's: the game's own Pokédex at the toolbar's right, by touch as by START)
  function W.toolbar()
    if ctx.classic then return T("wall.classic"), A.CLASSIC end
  end
  function W.tap(arg)
    if type(arg) ~= "number" then return end
    if st.kb then
      if arg > A.KEY and arg <= A.KEY + #KB.keys then return typeKey(arg - A.KEY) end
      if arg == A.KB_GO then return closeSearch(true) end
      if arg == A.KB_SCRIM then return closeSearch(false) end
      return
    end
    if arg == A.SEARCH then return openSearch() end
    if arg == A.CLASSIC and ctx.classic then return ctx.classic() end
    if arg > A.CELL then
      local i = arg - A.CELL
      if i == st.sel and hasPage() then return openPage() end
      choose(i)
      st.focus = "grid"
      if st.narrow and hasPage() then openPage() end
      return
    end
    if arg > A.MODE and arg <= A.MODE + #book.modes then return setMode(arg - A.MODE) end
    if arg > A.TAB and arg <= A.TAB + #st.tabs then st.focus = "detail" return setTab(arg - A.TAB) end
    if arg > A.KIND and arg <= A.KIND + #KINDS then st.focus = "detail" return setKind(arg - A.KIND) end
    if arg == A.SPRITE then return cry() end
    if arg > A.FORM and arg <= A.FORM + #st.forms then st.focus = "detail" return openForm(arg - A.FORM) end
    if arg == A.BACK then return back() end
  end

  -- the wheel and drags: the pane under the pointer (the page from st.pageX on, else the grid)
  function W.scroll(dy, x)
    local onPage = st.narrow and st.detail or (not st.narrow and x and st.pageX and x >= st.pageX)
    if onPage then
      st.detailTop = max(0, min(max(0, st.detailH - st.detailVis), st.detailTop - dy))
    else
      st.follow = false
      local rows = ceil(#st.list / max(1, st.cols))
      st.gridTop = max(0, min(max(0, rows - st.visRows), st.gridTop - dy / max(1, st.cellH or 24)))
    end
  end

  function W.hints()
    if st.kb then return T.list(HINTS.search) end
    if st.focus == "searchBtn" then return T.list(HINTS.searchBtn) end
    if st.focus == "detail" and st.tabId == "forms" then return T.list(HINTS.forms) end
    if st.focus == "detail" then return T.list(#book.modes > 1 and HINTS.pageModes or HINTS.page) end
    return T.list(#book.modes > 1 and HINTS.gridModes or HINTS.grid)
  end
  function W.close()
    st.kb = nil
    if env.dexSprite then env.dexSprite.stop() end
  end

  local view = makeView and makeView(K, env, T, st, A, KINDS) or nil
  function W.draw(body, clock, portrait)
    if view then view.draw(body, clock, portrait) end
  end

  return W
end
