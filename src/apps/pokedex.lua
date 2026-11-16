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
--            START the game's own Pokédex (when it was opened in its place)
--   touch    a tap picks; the tabs, the moves' chips, the picture (its cry); drag or wheel scrolls
--
--   window(ctx, env, view) -> win (src/apps.lua)   view: src/apps/pokedex_view.lua's maker; env.dex
--                            (src/dex.lua), env.dexSprite, env.monIcon, env.cry, env.se
--   ctx.classic(): the game's own Pokédex (the START menu's takeover)

local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil

local A = { CELL = 10000, MODE = 900, TAB = 800, KIND = 700, SPRITE = 600, BACK = 590, FORM = 400 }
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
}

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
    -- (the page's tabs: ids, "moves" / "where" / "info" / "forms", for the one chosen; st.tab the index)
    tab = 1, tabId = "moves", tabs = {}, forms = {},
    -- (the forms: the one shown (1, the base) and the one the Forms tab's cursor is on; base: the grid's)
    formAt = 1, formSel = 1, base = nil,
    kind = 1, shown = { 0, 0, 0, 0, 0, 0 }, chosenAt = 0, lines = {},
    modeWords = {},
  }
  W.state, W.A = st, A
  for i, m in ipairs(book.modes) do st.modeWords[i] = T("dex.mode." .. m) end

  local function now() return env.now and env.now() or 0 end

  -- the chosen one's tabs: caught, Moves / Where / Info; seen, Where; and Forms after them where it has
  -- forms. The same tab kept when it's there
  local function setTabs(e)
    local list = st.tabs
    for i = #list, 1, -1 do list[i] = nil end
    if e and e.caught then
      list[1], list[2], list[3] = "moves", "where", "info"
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

  choose(1, true)

  -- ------- the window's contract

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
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
    elseif nav.up then choose(st.sel - cols)
    elseif nav.down then choose(st.sel + cols)
    elseif pressed("l") then choose(st.sel - cols * max(1, st.visRows))
    elseif pressed("r") then choose(st.sel + cols * max(1, st.visRows))
    elseif pressed("select") then setMode(st.mi + 1)
    elseif pressed("a") then openPage() end
    return true
  end

  function W.tap(arg)
    if type(arg) ~= "number" then return end
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
    if st.focus == "detail" and st.tabId == "forms" then return T.list(HINTS.forms) end
    if st.focus == "detail" then return T.list(#book.modes > 1 and HINTS.pageModes or HINTS.page) end
    return T.list(#book.modes > 1 and HINTS.gridModes or HINTS.grid)
  end
  function W.close() if env.dexSprite then env.dexSprite.stop() end end

  local view = makeView and makeView(K, env, T, st, A, KINDS) or nil
  function W.draw(body, clock, portrait)
    if view then view.draw(body, clock, portrait) end
  end

  return W
end
