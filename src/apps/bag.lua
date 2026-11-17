-- The modern menus' Bag: its state and input, inside src/apps/menus.lua's window (ctx.menu.kind "bag", or
-- the party menu's GIVE choosing an item); drawn by src/apps/bag_view.lua; the rules src/bag_rules.lua's
-- (env.bagRules). Each pocket a page: L / R (or Left / Right, or its tab) turns them; Up / Down the items;
-- A an item's menu (USE, GIVE, TOSS, SET, CHECK TAG as the game's bag offers them; choosing for GIVE, A
-- gives it at once); SELECT picks an item up to move it in its pocket; B away. TOSS asks how many. The
-- game's words arrive as the party's do (src/apps/party.lua's prompts, the same bubble).
--
--   Bc = bag(env, T, A, Pc)            Pc: the party's controller (its prompts' input)
--   B = Bc.open(m, ctx)                m: ctx.menu ({ kind = "bag", battle, location, ... }) -> the state
--   Bc.input(B, input, nav) / Bc.tap(B, arg) -> "close" | "party" (the party to open over it: B.wantParty)
--     | nil ; Bc.tick(B, clock) ; Bc.hints(B) ; Bc.refresh(B) ; Bc.ui(B)

local max, min, floor = math.max, math.min, math.floor

local HINTS = {
  list = { { "^ v", "hint.move" }, { "L R", "hint.pocket" }, { "A", "hint.choose" }, { "B", "hint.close" } },
  listMove = { { "^ v", "hint.move" }, { "L R", "hint.pocket" }, { "A", "hint.choose" }, { "SELECT", "bag.hint.move" },
               { "B", "hint.close" } },
  give = { { "^ v", "hint.move" }, { "L R", "hint.pocket" }, { "A", "bag.act.give" }, { "B", "hint.back" } },
  -- (one page only -- the Pyramid's, a berry tree's: no L R)
  list1 = { { "^ v", "hint.move" }, { "A", "hint.choose" }, { "B", "hint.close" } },
  listMove1 = { { "^ v", "hint.move" }, { "A", "hint.choose" }, { "SELECT", "bag.hint.move" }, { "B", "hint.close" } },
  pickOne1 = { { "^ v", "hint.move" }, { "A", "hint.choose" }, { "B", "hint.cancel" } },
  menu = { { "^ v", "hint.move" }, { "A", "hint.ok" }, { "B", "hint.back" } },
  qty = { { "^ v", "hint.one" }, { "< >", "hint.ten" }, { "A", "hint.ok" }, { "B", "hint.cancel" } },
  pickOne = { { "^ v", "hint.move" }, { "L R", "hint.pocket" }, { "A", "hint.choose" }, { "B", "hint.cancel" } },
  berry = { { "^ v", "hint.move" }, { "A", "hint.choose" }, { "B", "hint.cancel" } },
  blender = { { "^ v", "hint.move" }, { "A", "hint.choose" } },
  moving = { { "^ v", "hint.move" }, { "A", "hint.drop" }, { "B", "hint.cancel" } },
  msg = { { "A", "hint.ok" } },
  yesno = { { "< >", "hint.move" }, { "A", "hint.ok" }, { "B", "party.no" } },
  pick = { { "^ v", "hint.move" }, { "A", "hint.ok" }, { "B", "hint.cancel" } },
}

-- (where each session's Bag was left: its pocket, each pocket's item)
local kept = setmetatable({}, { __mode = "k" })

return function(env, T, A, Pc)
  local Bg = env.bagRules
  local Bc = {}
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local function rowsOf(B)
    local p = B.pockets[B.pi]
    local rows = B.rows[p]
    if not rows then
      local ok, got = pcall(Bg.rows, B.c, p)
      rows = ok and got or {}
      for _, r in ipairs(rows) do
        r.qtyText = r.showQty and ("×" .. tostring(r.qty)) or nil
      end
      B.rows[p] = rows
    end
    return rows
  end
  Bc.rowsOf = rowsOf

  local function clamp(B)
    local rows = rowsOf(B)
    B.cur = max(1, min(B.cur, max(1, #rows)))
    B.c.rows, B.c.cursor = rows, B.cur
  end

  local BERRIES = { BERRY_POUCH = true, BERRIES = true }
  function Bc.refresh(B)
    local ok, list = pcall(Bg.pockets, B.c)
    -- (a berry tree or the Berry Blender: the Berries only)
    local loc = B.c.location
    -- (one pocket only: Teachy TV's TM Case lesson)
    if ok and B.m.lockPocket then
      local only = {}
      for _, p in ipairs(list) do if p == B.m.lockPocket then only[1] = p end end
      list = #only > 0 and only or { B.m.lockPocket }
    end
    if ok and (loc == "berry_tree" or loc == "blender") then
      local only = {}
      for _, p in ipairs(list) do if BERRIES[p] then only[#only + 1] = p end end
      if #only > 0 then list = only end
    end
    local was = B.pockets and B.pockets[B.pi]
    B.pockets = ok and list or { "ITEMS" }
    B.rows = {}
    B.pi = 1
    for k, p in ipairs(B.pockets) do if p == was then B.pi = k end end
    clamp(B)
  end

  local function remember(B)
    local s = B.c.session
    -- (a lesson's Bag leaves the player's places as they were)
    if not s or B.m.pd or B.m.demo then return end
    local k = kept[s] or { cur = {} }
    kept[s] = k
    k.pocket = B.pockets[B.pi]
    k.cur[k.pocket] = B.cur
  end

  function Bc.open(m, ctx)
    local s = ctx.session or (env.session and env.session())
    local c = { session = s, bag = m.bag or (s and (s.bag or s.inventory)), battle = m.battle == true,
                location = m.location, pyramid = m.pyramid == true, reopen = m.reopen }
    local B = { m = m, c = c, pockets = nil, rows = {}, pi = 1, cur = 1, view = "list", menu = nil, prompt = nil,
                moving = nil, qty = nil, wait = nil, at = now(), openAt = now(), pageAt = now(), dir = 0 }
    c.view = B
    if m.pd then B.pd = { plan = m.pd, index = 1, frames = 0, item = nil } end
    -- (what Ruby / Sapphire's bag skin reads off the game's bag: ours answers the same)
    B._battle, B._location, B._session, B._bag = c.battle, c.location, s, c.bag
    function B.currentPocket() return B.pockets and B.pockets[B.pi] or "ITEMS" end
    Bc.refresh(B)
    -- (back where it was left; a pocket asked for first; a lesson's from the top)
    local k = s and not (m.pd or m.demo) and kept[s] or nil
    local want = m.pocket or (k and k.pocket)
    for i, p in ipairs(B.pockets) do if p == want then B.pi = i end end
    B.cur = k and k.cur[B.pockets[B.pi]] or 1
    clamp(B)
    local TITLE = { party = "bag.giveWhich", berry_tree = "bag.plantWhich", blender = "bag.berryWhich",
                    itempc = "bag.depositWhich", shop = "bag.sellWhich", choose_toss = "bag.tossWhich" }
    B.title = T(TITLE[c.location or ""] or (c.pyramid and "bag.pyramid" or "bag.title"))
    return B
  end

  function Bc.row(B) return rowsOf(B)[B.cur] end

  -- ------- the flows' way in (src/bag_rules.lua's `ui`)

  local function makeUi(B)
    local ui = {}
    function ui.say(text, after)
      local pages = env.party.pages(text)
      if #pages == 1 and pages[1] == "" then
        if after then after() end
        return
      end
      B.prompt = { kind = "msg", pages = pages, page = 1, after = after, at = now() }
    end
    function ui.ask(text, after)
      local pages = env.party.pages(text)
      B.prompt = { kind = "yesno", pages = { table.concat(pages, " ") }, page = 1, after = after, yes = true, at = now() }
    end
    function ui.pick(prompt, names, after)
      B.prompt = { kind = "pick", pages = { prompt }, page = 1, names = names, sel = 1, after = after, at = now() }
    end
    function ui.wait(frames, fn) B.wait = { untilT = now() + (frames or 8) / 60, fn = fn } end
    function ui.party(mode, item, bag, after)
      B.wantParty = { mode = mode, item = item, bag = bag, after = after }
      B.menu, B.view = nil, "list"
    end
    function ui.chosen(item)
      B.m.result = { chosen = item }
      B.done = true
    end
    function ui.leave(fn)
      B.prompt = nil
      B.m.after = fn
      B.m.result = { leave = true }
      B.done = true
    end
    function ui.battle(id, slot, moveSlot, used)
      B.prompt = nil
      B.m.result = { battle = { id = id, slot = slot, moveSlot = moveSlot, used = used } }
      B.done = true
    end
    function ui.classic()
      B.m.result = { classic = true }
      B.done = true
    end
    function ui.back() B.menu, B.view = nil, "list" end
    function ui.refresh()
      B.rows = {}
      clamp(B)
    end
    return ui
  end
  local uis = setmetatable({}, { __mode = "k" })
  local function uiOf(B)
    local u = uis[B]
    if not u then
      u = makeUi(B)
      uis[B] = u
    end
    return u
  end
  Bc.ui = uiOf

  local function run(B, f, ...)
    local ok, err = pcall(f, ...)
    if not ok then
      if env.log then pcall(env.log, "the bag: %s", tostring(err)) end
      B.menu, B.view = nil, "list"
    end
  end

  -- ------- moving around

  local function setCur(B, i)
    local n = #rowsOf(B)
    if n == 0 then return end
    i = max(1, min(n, i))
    if i == B.cur then return end
    B.cur = i
    B.c.cursor = i
    B.moveAt = now()
    se("SE_SELECT")
  end
  local function turn(B, dir)
    local n = #B.pockets
    if n < 2 then return end
    remember(B)
    local k = kept[B.c.session]
    B.pi = (B.pi - 1 + dir) % n + 1
    B.cur = (k and k.cur[B.pockets[B.pi]]) or 1
    B.dir, B.pageAt = dir, now()
    clamp(B)
    se("SE_SELECT")
  end
  Bc.turn = turn
  local function toPocket(B, i)
    if i == B.pi or not B.pockets[i] then return end
    turn(B, i - B.pi)
    B.dir = i > B.pi and 1 or -1
  end

  local function qtyFor(B, kind, row, cap)
    B.qty = { n = 1, max = min(cap, tonumber(row.qty) or 1), at = now(), kind = kind }
    B.view = "qty"
  end
  local function openMenu(B)
    local row = Bc.row(B)
    if not row then return end
    local loc = B.c.location
    if loc == "party" then
      -- (choosing what to give: straight to it)
      se("SE_SELECT")
      return run(B, Bg.act, B.c, "GIVE", row, uiOf(B))
    elseif loc == "berry_tree" then
      se("SE_SELECT")
      return uiOf(B).chosen(row.id)
    elseif loc == "itempc" then
      se("SE_SELECT")
      if (tonumber(row.qty) or 1) <= 1 then return run(B, Bg.deposit, B.c, row, 1, uiOf(B)) end
      return qtyFor(B, "deposit", row, 999)
    elseif loc == "shop" then
      se("SE_SELECT")
      local okP, unit, cant = pcall(Bg.sellPrice, B.c, row)
      if not okP then return end
      if unit == 0 then return uiOf(B).say(cant) end
      B.sellUnit = unit
      if (tonumber(row.qty) or 1) <= 1 then return run(B, Bg.sell, B.c, row, 1, uiOf(B)) end
      return qtyFor(B, "sell", row, B.pockets[B.pi] == "BERRY_POUCH" and 999 or 99)
    end
    local ok, rows = pcall(Bg.actions, B.c, B.pockets[B.pi], row)
    rows = ok and rows or {}
    if #rows == 0 then return end
    B.menu = { rows = rows, sel = 1, at = now(), i = B.cur }
    B.view = "menu"
    se("SE_SELECT")
  end

  local function runRow(B, r)
    local row = Bc.row(B)
    B.menu, B.view = nil, "list"
    if not row or r.act == "CANCEL" then return se("SE_SELECT") end
    se("SE_SELECT")
    if r.act == "TOSS" then
      if (tonumber(row.qty) or 1) <= 1 then return run(B, Bg.toss, B.c, row, 1, uiOf(B)) end
      return qtyFor(B, "toss", row, 999)
    end
    run(B, Bg.act, B.c, r.act, row, uiOf(B))
  end
  Bc.runRow = runRow

  local function qtyStep(B, d)
    local q = B.qty
    local n = q.n + d
    if d == 1 or d == -1 then n = (n - 1) % q.max + 1 else n = max(1, min(q.max, n)) end
    if n ~= q.n then
      q.n = n
      se("SE_SELECT")
    end
  end
  local function qtyDone(B, ok)
    local q = B.qty
    B.qty, B.view = nil, "list"
    se("SE_SELECT")
    if not ok then return end
    local f = q.kind == "deposit" and Bg.deposit or (q.kind == "sell" and Bg.sell or Bg.toss)
    run(B, f, B.c, Bc.row(B), q.n, uiOf(B))
  end

  local function startMove(B)
    local row = Bc.row(B)
    if not row or B.c.location == "party" or not Bg.canMove(B.c, B.pockets[B.pi]) then return false end
    se("SE_SELECT")
    B.moving = { from = B.cur, at = now() }
    B.view = "move"
    return true
  end
  local function endMove(B, commit)
    local mvg = B.moving
    B.moving, B.view = nil, "list"
    se("SE_SELECT")
    if commit and mvg and mvg.from ~= B.cur then
      if Bg.move(B.c, B.pockets[B.pi], mvg.from, B.cur) then uiOf(B).refresh() end
    end
  end

  local function cancel(B)
    -- (the Berry Blender waits for a Berry; a berry tree's B is none)
    if B.c.location == "blender" then return se("SE_FAILURE") end
    se("SE_SELECT")
    remember(B)
    if B.c.location == "berry_tree" then
      B.m.result = { chosen = 0 }
      B.done = true
      return
    end
    B.m.result = B.m.result or {}
    B.done = true
  end

  -- ------- input

  local function result(B)
    if B.done then remember(B) return "close" end
    if B.wantParty then return "party" end
    return nil
  end

  -- the Pokédude's Bag (Teachy TV's battles, the Old Man's): its own presses only; B stops it (unless it can't be)
  local function pdInput(B, input)
    if input:wasPressed("b") and not B.pd.plan.noInterrupt then
      se("SE_SELECT")
      B.m.result = { pokedude = false }
      B.done = true
    end
    return result(B)
  end
  function Bc.input(B, input, nv)
    local function pressed(k) return input:wasPressed(k) end
    if B.done then return "close" end
    if B.pd and not B.pdFeeding then return pdInput(B, input) end
    if B.wait then return nil end
    if B.prompt then
      Pc.promptInput(B, input, nv)
      return result(B)
    end
    if B.view == "menu" and B.menu then
      local mm = B.menu
      local n = #mm.rows
      if nv.up then mm.sel = (mm.sel - 2) % n + 1 se("SE_SELECT")
      elseif nv.down then mm.sel = mm.sel % n + 1 se("SE_SELECT")
      elseif pressed("a") then runRow(B, mm.rows[mm.sel])
      elseif pressed("b") then B.menu, B.view = nil, "list" se("SE_SELECT") end
      return result(B)
    end
    if B.view == "qty" and B.qty then
      if nv.up then qtyStep(B, 1)
      elseif nv.down then qtyStep(B, -1)
      elseif nv.right then qtyStep(B, 10)
      elseif nv.left then qtyStep(B, -10)
      elseif pressed("a") then qtyDone(B, true)
      elseif pressed("b") then qtyDone(B, false) end
      return result(B)
    end
    if B.view == "move" and B.moving then
      if nv.up then setCur(B, B.cur - 1)
      elseif nv.down then setCur(B, B.cur + 1)
      elseif pressed("a") or pressed("select") then endMove(B, true)
      elseif pressed("b") then endMove(B, false) end
      return result(B)
    end
    if nv.left or pressed("l") then turn(B, -1)
    elseif nv.right or pressed("r") then turn(B, 1)
    elseif nv.up then setCur(B, B.cur - 1)
    elseif nv.down then setCur(B, B.cur + 1)
    elseif pressed("a") then openMenu(B)
    elseif pressed("select") then startMove(B)
    elseif pressed("b") then cancel(B) end
    return result(B)
  end

  function Bc.tap(B, arg)
    if B.done then return "close" end
    if B.wait then return nil end
    if B.prompt then
      Pc.promptTap(B, arg)
      return result(B)
    end
    if B.view == "menu" and B.menu then
      local k = arg - A.MENU
      if k >= 1 and k <= #B.menu.rows then runRow(B, B.menu.rows[k])
      elseif arg == A.SCRIM then B.menu, B.view = nil, "list" se("SE_SELECT") end
      return result(B)
    end
    if B.view == "qty" and B.qty then
      if arg == A.QTY_UP then qtyStep(B, 1)
      elseif arg == A.QTY_DOWN then qtyStep(B, -1)
      elseif arg == A.QTY_OK then qtyDone(B, true)
      elseif arg == A.SCRIM or arg == A.NO then qtyDone(B, false) end
      return result(B)
    end
    if B.view == "move" and B.moving then
      local k = arg - A.ROW
      if k >= 1 and k <= #rowsOf(B) then
        B.cur = k
        endMove(B, true)
      end
      return result(B)
    end
    if arg == A.CANCEL then
      cancel(B)
    elseif arg > A.POCKET and arg <= A.POCKET + #B.pockets then
      toPocket(B, arg - A.POCKET)
    elseif arg > A.ROW and arg <= A.ROW + #rowsOf(B) then
      local k = arg - A.ROW
      if k == B.cur then openMenu(B) else setCur(B, k) end
    end
    return result(B)
  end

  function Bc.scroll(B, dy)
    B.top = max(0, min(max(0, (B.h or 0) - (B.vis or 0)), (B.top or 0) - dy))
    B.scrolled = true
  end

  local function press(k)
    return { wasPressed = function(_, x) return x == k end, isDown = function() return false end }
  end
  local NV = {}
  -- (the Pokédude's next press, a frame at a time)
  local function pdStep(B)
    local pd = B.pd
    pd.frames = pd.frames + 1
    local e = pd.plan[pd.index]
    if not e or pd.frames < (e.at or 0) then return end
    pd.index = pd.index + 1
    if e.item then
      pd.item = e.item
      for k, r in ipairs(rowsOf(B)) do
        if tonumber(r.id) == e.item or tostring(r.id) == tostring(e.item) then B.cur = k end
      end
    end
    if e.exit then
      B.prompt, B.menu, B.view = nil, nil, "list"
      B.m.result = { pokedude = pd.item or false }
      B.done = true
      return
    end
    if e.key then
      NV.up, NV.down, NV.left, NV.right = e.key == "up", e.key == "down", e.key == "left", e.key == "right"
      B.pdFeeding = true
      local ok, err = pcall(Bc.input, B, press(e.key), NV)
      B.pdFeeding = false
      if not ok and env.log then pcall(env.log, "the Pokédude's Bag: %s", tostring(err)) end
    end
  end

  -- once a frame: a delay's end (the flutes, an X item); a lesson's presses; what a lesson set from outside
  function Bc.tick(B, clock)
    if B.m.sync then pcall(B.m.sync, B) end
    -- (the TM Case lesson's words, written into the game's TM Case: shown in ours while they're there)
    if B.m.mirrorText then
      local okT, t = pcall(B.m.mirrorText)
      t = okT and t or nil
      if t then
        if not (B.prompt and B.prompt.mirror == t) then
          B.prompt = { kind = "msg", pages = env.party.pages(t), page = 1, mirror = t, at = now() }
        end
      elseif B.prompt and B.prompt.mirror then
        B.prompt = nil
      end
    end
    if B.pd and not B.done then pdStep(B) end
    local w = B.wait
    if w and clock >= w.untilT then
      B.wait = nil
      local ok, err = pcall(w.fn)
      if not ok and env.log then pcall(env.log, "the bag: %s", tostring(err)) end
    end
    return result(B)
  end

  local LESSON, WATCH = { { "B", "hint.skip" } }, {}
  function Bc.hints(B)
    local h
    -- (a lesson plays itself: B skips it -- the Old Man's can't be)
    if B.pd then return T.list(B.pd.plan.noInterrupt and WATCH or LESSON) end
    if (B.m.demo or B.m.tmDemo) and not B.prompt then return T.list(LESSON) end
    if B.prompt then
      local k = B.prompt.kind
      h = k == "yesno" and HINTS.yesno or (k == "pick" and HINTS.pick or HINTS.msg)
    elseif B.view == "menu" then h = HINTS.menu
    elseif B.view == "qty" then h = HINTS.qty
    elseif B.view == "move" then h = HINTS.moving
    elseif B.c.location == "party" then h = HINTS.give
    elseif B.c.location == "berry_tree" then h = HINTS.berry
    elseif B.c.location == "blender" then h = HINTS.blender
    else
      local one = #B.pockets < 2
      if B.c.location then h = one and HINTS.pickOne1 or HINTS.pickOne
      elseif Bg.canMove(B.c, B.pockets[B.pi]) and #rowsOf(B) > 1 then h = one and HINTS.listMove1 or HINTS.listMove
      else h = one and HINTS.list1 or HINTS.list end
    end
    return T.list(h)
  end

  return Bc
end
