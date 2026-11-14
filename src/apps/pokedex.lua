-- The Pokédex app (every game): a modern, split-screen Pokédex over src/dex.lua. On the left a grid of
-- the dex's Pokémon (its number, its icon, its name; a silhouette until it's seen, a ball once it's
-- caught); on the right the chosen one's page: its front picture (Emerald's own animation, a breathing
-- idle elsewhere), name, category, types, height and weight, gender ratio, the dex's words, a radar of
-- its base stats, its abilities, and Moves / Where / Info. The game's rules: unseen nothing, seen the
-- card and where to find it, caught everything. Narrow (WoobPad upright), the grid and the page take
-- turns.
--   buttons  the D-pad moves in the grid, L / R a page, A the page (Up / Down scroll it, L / R its tab,
--            Left / Right the moves' list, A its cry), SELECT the regional or National dex, B back,
--            START the game's own Pokédex (when it was opened in its place)
--   touch    a tap picks; the tabs, the moves' chips, the picture (its cry); drag or wheel scrolls
--
--   window(ctx, env, view) -> win (src/apps.lua)   view: src/apps/pokedex_view.lua's maker; env.dex
--                            (src/dex.lua), env.dexSprite, env.monIcon, env.cry, env.se
--   ctx.classic(): the game's own Pokédex (the START menu's takeover)

local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil

local A = { CELL = 10000, MODE = 900, TAB = 800, KIND = 700, SPRITE = 600, BACK = 590 }
local KINDS = { "level", "tm", "egg", "tutor" }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })
local HINTS = {
  grid = { { "+", "dex.hint.choose" }, { "A", "dex.hint.page" }, { "L R", "dex.hint.flip" }, { "B", "hint.back" } },
  gridModes = { { "+", "dex.hint.choose" }, { "A", "dex.hint.page" }, { "L R", "dex.hint.flip" },
                { "SELECT", "dex.hint.mode" }, { "B", "hint.back" } },
  page = { { "+", "dex.hint.scroll" }, { "L R", "dex.hint.tabs" }, { "A", "dex.hint.cry" }, { "B", "hint.back" } },
  pageModes = { { "+", "dex.hint.scroll" }, { "L R", "dex.hint.tabs" }, { "A", "dex.hint.cry" },
                { "SELECT", "dex.hint.mode" }, { "B", "hint.back" } },
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
    tab = 1, kind = 1, shown = { 0, 0, 0, 0, 0, 0 }, chosenAt = 0, lines = {},
    modeWords = {},
  }
  W.state, W.A = st, A
  for i, m in ipairs(book.modes) do st.modeWords[i] = T("dex.mode." .. m) end

  local function now() return env.now and env.now() or 0 end

  -- a Pokémon chosen: its page made (an action, never a draw), its picture's animation started
  local function choose(i, quiet)
    local n = #st.list
    if n == 0 then return end
    i = max(1, min(n, i))
    local moved = i ~= st.sel or not st.entry
    st.sel = i
    st.entry = st.list[i]
    st.page = st.entry.seen and Dx.page(st.entry) or nil
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
  local function openPage()
    if not (st.entry and st.entry.seen) then return se("SE_FAILURE") end
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
    local caught = st.entry and st.entry.caught
    if not caught then return end
    st.tab = (t - 1) % 3 + 1
    st.detailTop = min(st.detailTop, max(0, st.detailH - st.detailVis))
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
      if pressed("b") then back() return true end
      if pressed("select") then setMode(st.mi + 1) return true end
      if nav.up then st.detailTop = max(0, st.detailTop - 12)
      elseif nav.down then st.detailTop = min(max(0, st.detailH - st.detailVis), st.detailTop + 12)
      elseif pressed("l") then setTab(st.tab - 1)
      elseif pressed("r") then setTab(st.tab + 1)
      elseif st.tab == 1 and nav.left then setKind(st.kind - 1)
      elseif st.tab == 1 and nav.right then setKind(st.kind + 1)
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
      if i == st.sel and st.entry and st.entry.seen then return openPage() end
      choose(i)
      st.focus = "grid"
      if st.narrow and st.entry and st.entry.seen then openPage() end
      return
    end
    if arg > A.MODE and arg <= A.MODE + #book.modes then return setMode(arg - A.MODE) end
    if arg > A.TAB and arg <= A.TAB + 3 then st.focus = "detail" return setTab(arg - A.TAB) end
    if arg > A.KIND and arg <= A.KIND + #KINDS then st.focus = "detail" return setKind(arg - A.KIND) end
    if arg == A.SPRITE then return cry() end
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
