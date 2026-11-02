-- The Boxes app: the Pokémon Storage System in one window. The party on the left, a box in the
-- middle (any of them: 14, or 40 with WoobleDex's Bigger PC), the Pokémon under the cursor on the right. Three cursor modes, SELECT going
-- round them (or a tap on one of the mode icons under the box):
--   Select (red)    A on a Pokémon: Move, Summary, Item (Take / Give), Release; A on the box's name
--                   (or START): Jump to a box, Rename, Wallpaper
--   Swap (blue)     A picks a Pokémon up, A again puts it down (swapping with whoever is there)
--   Drag (green)    hold A and move: a rectangle; let go and the Pokémon in it move together, A puts
--                   them down (a box group keeps its shape)
--   buttons  the D-pad the cursor (party, box, the box's name), L / R the box (also while carrying),
--            B puts back what's carried, then closes
--   touch    tap a Pokémon (as A); Swap: drag one onto a slot; Drag: drag a rectangle, then tap where
--            they go; hold a carried Pokémon over < or > to turn the box; tap a mode's icon
-- A Pokémon going between the party and a box crosses the shelf's pad as a Poké Ball. The model is
-- src/boxes.lua (env.bx); the drawing src/apps/boxes_view.lua.
--
--   window(ctx, env, makeView) -> win (src/apps.lua)

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

-- hit args
local A = { PARTY = 100, BOX = 200, PREV = 301, NEXT = 302, NAME = 303, MODE = 310,
            DIM = 399, NO = 390, YES = 391, ROW = 400, WALL = 500 }
-- the modes
local SELECT, SWAP, DRAG = 1, 2, 3
local MODE_KEYS = { "boxes.select", "boxes.swap", "boxes.drag" }

-- (the words are keys of lang/*.lua, through env.T)
local HINTS = {
  [SELECT] = { { "A", "hint.options" }, { "SELECT", "hint.mode" }, { "L R", "hint.box" }, { "START", "hint.menu" } },
  [SWAP] = { { "A", "hint.pick" }, { "SELECT", "hint.mode" }, { "L R", "hint.box" }, { "START", "hint.menu" } },
  [DRAG] = { { "A", "hint.grab" }, { "SELECT", "hint.mode" }, { "L R", "hint.box" }, { "START", "hint.menu" } },
  held = { { "A", "hint.drop" }, { "B", "hint.cancel" }, { "L R", "hint.box" }, { "SELECT", "hint.mode" } },
  sheet = { { "A", "hint.choose" }, { "B", "hint.back" } },
}
local ACTIONS = { "boxes.move", "boxes.summary", "boxes.item", "boxes.release" }
local ITEM_ACTIONS = { "boxes.take", "boxes.give" }
local BOX_ACTIONS = { "boxes.jump", "boxes.rename", "boxes.wallpaper" }
local BUTTONS = { "a", "b", "l", "r", "start", "select" }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env, makeView)
  local K, Bx, T = env.K, env.bx, env.T or NO_T
  local W = { title = "Boxes", pad = true, ball = true }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local st = {
    mode = SELECT, area = "box", pi = 1, bi = 1, box = Bx.current(session()),
    held = nil, rect = nil, sheet = nil, toast = nil,
    -- the pointer: where it is (units), whether it's in charge of the carried Pokémon
    ptr = { down = false, x = 0, y = 0, sx = 0, sy = 0, moved = false, area = nil, idx = nil },
    usePtr = false, px = 0, py = 0, hoverArea = nil, hoverIdx = nil, arrow = nil, arrowSince = 0,
    -- the layout's numbers (units), filled by the view each frame: geo.*
    geo = { portrait = false, gx = 0, gy = 0, cell = 1, partyX = 0, partyY = 0, partyW = 0, slotH = 1,
            slotW = 1, prev = { 0, 0, 0, 0 }, next = { 0, 0, 0, 0 } },
    names = {},
  }
  W.state = st

  -- (back from the game's summary or naming screen: as it was)
  local resume = ctx.resume
  if resume and resume.app == ctx.app and type(resume.state) == "table" then
    local r = resume.state
    st.mode, st.area, st.pi, st.bi = r.mode or SELECT, r.area or "box", r.pi or 1, r.bi or 1
    st.box = r.box or st.box
    Bx.setCurrent(session(), st.box)
  end
  ctx.resume = nil

  local function toast(text, bad)
    st.toast = { text = text, bad = bad, t = now() }
    se(bad and "SE_FAILURE" or "SE_SELECT")
  end
  local function why(reason) return T(reason and ("reason.box." .. reason) or "failed") end

  -- ------- places

  local function addrOf(area, idx)
    if area == "party" then return Bx.addr("party", idx) end
    if area == "box" then return Bx.addr("box", idx, st.box) end
    return nil
  end
  local function cursorAddr() return addrOf(st.area, st.area == "party" and st.pi or st.bi) end
  -- the Pokémon the preview shows: the carried one, else under the pointer, else under the cursor
  function W.previewMon()
    local s = session()
    if st.held then return st.held.mons[1] end
    if st.usePtr and st.hoverArea then return Bx.get(s, addrOf(st.hoverArea, st.hoverIdx)) end
    return Bx.get(s, cursorAddr())
  end

  local function setBox(b)
    b = (b - 1) % Bx.BOXES + 1
    if b ~= st.box then
      st.box = b
      Bx.setCurrent(session(), b)
      st.rect = nil
      se("SE_SELECT")
    end
  end

  -- ------- carrying

  local function pick(addrs)
    local held, reason = Bx.take(session(), addrs)
    if not held then return toast(why(reason), true) end
    st.held = held
    se("SE_SELECT")
  end
  local function drop(addr)
    local held = st.held
    if not (held and addr) then return end
    local s = session()
    local way = Bx.way(held, addr)
    local first = held.mons[1]
    local ok, nextHeld = Bx.place(s, held, addr)
    if not ok then return toast(why(nextHeld), true) end
    for i = 1, held.n do Bx.forget(held.mons[i]) end
    st.held = nextHeld
    -- (between the party and a box: a Poké Ball crosses the pad)
    if way and env.pad and env.pad.transfer then
      pcall(env.pad.transfer, tonumber(first.species or first.speciesId) or 0, way, "ball")
    end
    se("SE_SELECT")
  end
  local function putBack()
    if not st.held then return end
    Bx.putBack(session(), st.held)
    st.held = nil
    se("SE_SELECT")
  end
  W.putBack = putBack

  -- the cells inside the rectangle that hold a Pokémon
  local function rectAddrs(rect)
    local out, s = {}, session()
    if rect.area == "party" then
      for i = min(rect.a, rect.b), max(rect.a, rect.b) do
        local a = addrOf("party", i)
        if Bx.get(s, a) then out[#out + 1] = a end
      end
      return out
    end
    local c1, r1 = (rect.a - 1) % Bx.COLS, floor((rect.a - 1) / Bx.COLS)
    local c2, r2 = (rect.b - 1) % Bx.COLS, floor((rect.b - 1) / Bx.COLS)
    for r = min(r1, r2), max(r1, r2) do
      for c = min(c1, c2), max(c1, c2) do
        local a = addrOf("box", r * Bx.COLS + c + 1)
        if Bx.get(s, a) then out[#out + 1] = a end
      end
    end
    return out
  end
  local function finishRect()
    local rect = st.rect
    st.rect = nil
    if not rect then return end
    local addrs = rectAddrs(rect)
    if #addrs > 0 then pick(addrs) end
  end

  -- ------- the sheets

  local function openSheet(kind, rows, extra)
    st.sheet = { kind = kind, rows = rows, cursor = 1, top = 0, extra = extra }
    se("SE_SELECT")
  end
  local function closeSheet()
    st.sheet = nil
    se("SE_SELECT")
  end
  local function words(keys)
    local out = {}
    for i, k in ipairs(keys) do out[i] = T(k) end
    return out
  end
  local function openActions()
    local mon = Bx.get(session(), cursorAddr())
    if not mon then return end
    local info = Bx.info(mon, T)
    openSheet("actions", words(ACTIONS), { addr = cursorAddr(), title = info and info.name or "" })
  end
  local function openBoxMenu()
    openSheet("box", words(BOX_ACTIONS), { title = Bx.boxName(session(), st.box) })
  end

  local function state()
    return { mode = st.mode, area = st.area, pi = st.pi, bi = st.bi, box = st.box }
  end
  -- one of the game's screens over the desktop; the window back as it was after
  local function over(open)
    if not ctx.over then return toast(T("failed"), true) end
    putBack()
    st.sheet = nil
    ctx.over(open, state())
  end

  local function summary(addr)
    local s = session()
    local list, index, context
    if addr.loc == "party" then
      list, index, context = Bx.party(s), addr.slot, "party"
    else
      list, context = {}, "box"
      local mons = Bx.boxMons(s, addr.boxId) or {}
      for i = 1, Bx.SLOTS do
        if mons[i] then
          list[#list + 1] = mons[i]
          if i == addr.slot then index = #list end
        end
      end
    end
    if not index then return end
    over(function(onClose) Bx.openSummary(s, list, index, context, onClose) end)
  end
  local function rename()
    local s, b = session(), st.box
    over(function(onClose)
      Bx.openNaming(s, b, function(name)
        Bx.rename(s, b, name)
        onClose()
      end)
    end)
  end

  -- the Bag's items a Pokémon can hold (made when the list opens)
  local function holdables()
    local s, inv = session(), env.inv
    local rows, ids = {}, {}
    if not (inv and s) then return rows, ids end
    for _, pk in ipairs(inv.pockets(s)) do
      for _, row in ipairs(inv.bagRows(s, pk.id)) do
        if Bx.holdable(s, row.id) then
          rows[#rows + 1] = row.name .. "  ×" .. row.qty
          ids[#ids + 1] = row.id
        end
      end
    end
    return rows, ids
  end

  local function choose(i)
    local sh = st.sheet
    if not sh then return end
    local s = session()
    if sh.kind == "actions" then
      local addr = sh.extra.addr
      st.sheet = nil
      if i == 1 then pick({ addr })
      elseif i == 2 then summary(addr)
      elseif i == 3 then openSheet("item", words(ITEM_ACTIONS), { addr = addr, title = sh.extra.title })
      elseif i == 4 then
        local mon = Bx.get(s, addr)
        if not mon then return end
        openSheet("release", nil, { addr = addr, title = T.f("boxes.releaseTitle", sh.extra.title) })
        st.sheet.cursor = 1
      end
    elseif sh.kind == "item" then
      local addr = sh.extra.addr
      local mon = Bx.get(s, addr)
      st.sheet = nil
      if i == 1 then
        local ok, got = Bx.takeItem(s, mon)
        if not ok then return toast(why(got), true) end
        local I = env.itemName
        toast(T.f("boxes.took", I and I(got) or tostring(got)))
      else
        local rows, ids = holdables()
        if #rows == 0 then return toast(T("boxes.noHoldable"), true) end
        openSheet("give", rows, { addr = addr, ids = ids, title = T("boxes.giveTitle") })
      end
    elseif sh.kind == "give" then
      local addr, id = sh.extra.addr, sh.extra.ids[i]
      st.sheet = nil
      local mon = Bx.get(s, addr)
      local ok, got = Bx.giveItem(s, mon, id)
      if not ok then return toast(why(got), true) end
      local info = Bx.info(mon, T)
      toast(T.f("boxes.gave", info and info.name or "", info and info.itemName or ""))
    elseif sh.kind == "release" then
      local addr = sh.extra.addr
      st.sheet = nil
      if i ~= 2 then return se("SE_SELECT") end
      local mon = Bx.get(s, addr)
      local name = mon and Bx.info(mon, T).name or ""
      local ok, got = Bx.release(s, addr)
      if not ok then return toast(why(got), true) end
      toast(T.f("boxes.released", name))
    elseif sh.kind == "box" then
      st.sheet = nil
      if i == 1 then
        local rows = {}
        for b = 1, Bx.BOXES do rows[b] = Bx.boxName(s, b) end
        openSheet("jump", rows, { title = T("boxes.jump") })
        st.sheet.cursor = st.box
      elseif i == 2 then rename()
      else
        local n = env.boxWallCount and env.boxWallCount() or 16
        openSheet("wall", nil, { title = T("boxes.wallpaper"), count = n })
        st.sheet.cursor = Bx.wallpaper(s, st.box)
      end
    elseif sh.kind == "jump" then
      st.sheet = nil
      setBox(i)
    elseif sh.kind == "wall" then
      st.sheet = nil
      Bx.setWallpaper(s, st.box, i)
      se("SE_SELECT")
    end
  end
  local function sheetCount(sh)
    if sh.kind == "release" then return 2 end
    if sh.kind == "wall" then return sh.extra.count end
    return #sh.rows
  end

  -- ------- the mode

  local function cycleMode()
    if st.rect then st.rect = nil end
    st.mode = st.mode % 3 + 1
    se("SE_SELECT")
    return true
  end
  -- a mode at once (a tap on its icon)
  local function setMode(m)
    if m == st.mode then return end
    st.rect = nil
    st.mode = m
    se("SE_SELECT")
  end
  W.setMode = setMode

  -- A (or a tap on the cursor's place)
  local function actA()
    if st.held then return drop(cursorAddr()) end
    if st.area == "head" then return openBoxMenu() end
    local addr = cursorAddr()
    local mon = Bx.get(session(), addr)
    if st.mode == SELECT then
      if mon then openActions() end
    elseif st.mode == SWAP then
      if mon then pick({ addr }) end
    elseif mon or st.area == "box" then
      -- (Drag: a tap takes just that one; a held A stretches a rectangle, see W.input)
      if mon then pick({ addr }) end
    end
  end

  -- ------- buttons

  local function idx() return st.area == "party" and st.pi or st.bi end
  local function moveCursor(nav)
    local portrait = st.geo.portrait
    local area, pi, bi = st.area, st.pi, st.bi
    local col, row = (bi - 1) % Bx.COLS, floor((bi - 1) / Bx.COLS)
    if area == "party" then
      if portrait then
        if nav.left then pi = max(1, pi - 1)
        elseif nav.right then pi = min(Bx.PARTY, pi + 1)
        elseif nav.down then area = "head"
        end
      else
        if nav.up then pi = max(1, pi - 1)
        elseif nav.down then pi = min(Bx.PARTY, pi + 1)
        elseif nav.right then area, bi = "box", (min(pi, Bx.ROWS) - 1) * Bx.COLS + 1
        end
      end
    elseif area == "head" then
      if nav.left then setBox(st.box - 1)
      elseif nav.right then setBox(st.box + 1)
      elseif nav.down then area = "box"
      elseif nav.up and portrait then area = "party"
      end
    else
      if nav.up then
        if row == 0 then area = "head" else bi = bi - Bx.COLS end
      elseif nav.down then
        if row < Bx.ROWS - 1 then bi = bi + Bx.COLS end
      elseif nav.left then
        if col > 0 then bi = bi - 1
        elseif not portrait then area, pi = "party", min(Bx.PARTY, row + 1)
        end
      elseif nav.right then
        if col < Bx.COLS - 1 then bi = bi + 1 end
      end
    end
    -- (a rectangle stays in its own part)
    if st.rect and area ~= st.rect.area then return end
    if area ~= st.area or pi ~= st.pi or bi ~= st.bi then
      st.area, st.pi, st.bi = area, pi, bi
      se("SE_SELECT")
    end
  end

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
    local any = nav.up or nav.down or nav.left or nav.right
    for i = 1, #BUTTONS do
      if pressed(BUTTONS[i]) then any = true end
    end
    if any then st.usePtr = false end
    local sh = st.sheet
    if sh then
      local n = sheetCount(sh)
      local cols = sh.kind == "wall" and 6 or (sh.kind == "release" and 2 or 1)
      local step = 0
      if cols > 1 then
        if nav.left then step = -1 elseif nav.right then step = 1
        elseif nav.up and cols < n then step = -cols elseif nav.down and cols < n then step = cols end
      else
        if nav.up then step = -1 elseif nav.down then step = 1 end
      end
      if step ~= 0 then
        sh.cursor = max(1, min(n, sh.cursor + step))
        se("SE_SELECT")
      elseif pressed("a") then choose(sh.cursor)
      elseif pressed("b") then closeSheet()
      end
      return true
    end
    -- a rectangle grows while A is held, and is taken when it's let go
    if st.rect and st.rect.keys then
      if any then moveCursor(nav) end
      if st.area == st.rect.area then st.rect.b = idx() end
      if pressed("b") then
        st.rect = nil
        se("SE_SELECT")
      elseif not input:isDown("a") then finishRect()
      end
      return true
    end
    if pressed("b") then
      if st.held then
        putBack()
        return true
      end
      return false
    end
    if pressed("select") then return cycleMode() end
    if pressed("start") then
      openBoxMenu()
      return true
    end
    if pressed("l") then setBox(st.box - 1)
    elseif pressed("r") then setBox(st.box + 1)
    elseif pressed("a") then
      if st.mode == DRAG and not st.held and st.area ~= "head" then
        st.rect = { area = st.area, a = idx(), b = idx(), keys = true }
        se("SE_SELECT")
      else
        actA()
      end
    elseif any then moveCursor(nav)
    end
    return true
  end

  -- ------- touch and the mouse (units)

  -- the place at x, y: "party" | "box", its index; or nil
  local function cellAt(x, y)
    local g = st.geo
    if g.portrait then
      if y >= g.partyY and y < g.partyY + g.slotH and x >= g.partyX and x < g.partyX + g.slotW * Bx.PARTY then
        return "party", min(Bx.PARTY, floor((x - g.partyX) / g.slotW) + 1)
      end
    elseif x >= g.partyX and x < g.partyX + g.partyW and y >= g.partyY and y < g.partyY + g.slotH * Bx.PARTY then
      return "party", min(Bx.PARTY, floor((y - g.partyY) / g.slotH) + 1)
    end
    local c, r = floor((x - g.gx) / g.cell), floor((y - g.gy) / g.cell)
    if x >= g.gx and y >= g.gy and c < Bx.COLS and r < Bx.ROWS then return "box", r * Bx.COLS + c + 1 end
    return nil
  end
  W.cellAt = cellAt
  local function arrowAt(x, y)
    if K.inside(st.geo.prev, x, y) then return -1 end
    if K.inside(st.geo.next, x, y) then return 1 end
    return nil
  end
  local function track(x, y)
    st.px, st.py = x, y
    st.hoverArea, st.hoverIdx = cellAt(x, y)
    local side = st.held and arrowAt(x, y) or nil
    if side ~= st.arrow then st.arrow, st.arrowSince = side, now() end
  end

  function W.pointer(phase, x, y)
    local P = st.ptr
    if phase == "hover" then
      st.usePtr = true
      track(x, y)
      return false
    end
    if phase == "pressed" then
      st.usePtr = true
      track(x, y)
      P.down, P.sx, P.sy, P.moved, P.dragging, P.rect = true, x, y, false, false, false
      P.area, P.idx = cellAt(x, y)
      return false
    end
    if phase == "moved" then
      track(x, y)
      if not P.down then return false end
      if not P.moved and (abs(x - P.sx) > 4 or abs(y - P.sy) > 4) then
        P.moved = true
        if not (st.sheet or st.held) and P.area then
          local addr = addrOf(P.area, P.idx)
          if st.mode == SWAP and Bx.get(session(), addr) then
            pick({ addr })
            P.dragging = st.held ~= nil
          elseif st.mode == DRAG then
            st.rect = { area = P.area, a = P.idx, b = P.idx }
            P.rect = true
          end
        end
      end
      if P.rect and st.rect and st.hoverArea == st.rect.area then st.rect.b = st.hoverIdx end
      return false
    end
    if phase == "released" then
      P.down = false
      track(x, y)
      if P.dragging then
        P.dragging = false
        if st.hoverArea then drop(addrOf(st.hoverArea, st.hoverIdx)) end
        -- (let go anywhere else: it goes back)
        if st.held and not st.hoverArea then putBack() end
        return true
      end
      if P.rect then
        P.rect = false
        finishRect()
        return true
      end
      return P.moved
    end
    if phase == "cancelled" then
      P.down = false
      if P.dragging then putBack() end
      P.dragging, P.rect = false, false
      st.rect = nil
    end
    return false
  end

  function W.tap(arg)
    if type(arg) ~= "number" then return end
    local sh = st.sheet
    if sh then
      if arg >= A.ROW and arg < A.ROW + 100 then return choose(arg - A.ROW + 1) end
      if arg >= A.WALL and arg < A.WALL + 100 then return choose(arg - A.WALL + 1) end
      if arg == A.YES then return choose(2) end
      if arg == A.NO then return choose(1) end
      if arg == A.DIM then return closeSheet() end
      return
    end
    if arg > A.MODE and arg <= A.MODE + 3 then return setMode(arg - A.MODE) end
    if arg == A.PREV then return setBox(st.box - 1) end
    if arg == A.NEXT then return setBox(st.box + 1) end
    if arg == A.NAME then
      st.area = "head"
      return openBoxMenu()
    end
    if arg > A.PARTY and arg <= A.PARTY + Bx.PARTY then
      st.area, st.pi = "party", arg - A.PARTY
    elseif arg > A.BOX and arg <= A.BOX + Bx.SLOTS then
      st.area, st.bi = "box", arg - A.BOX
    else
      return
    end
    actA()
  end

  -- the wheel: the box
  function W.scroll(dy)
    if st.sheet then return end
    if dy > 0 then setBox(st.box - 1) elseif dy < 0 then setBox(st.box + 1) end
  end

  function W.hints()
    if st.sheet then return T.list(HINTS.sheet) end
    if st.held then return T.list(HINTS.held) end
    return T.list(HINTS[st.mode])
  end

  -- B, log off, the desktop closing: nothing stays in the hand; caught Pokémon go to this box
  function W.close()
    st.rect = nil
    if st.held then Bx.putBack(session(), st.held) end
    st.held = nil
    Bx.sendBox(session())
  end

  -- ------- drawing: src/apps/boxes_view.lua

  local view = makeView(K, env, T, Bx, st, A)
  local modeColor = view.modeColor
  function W.draw(body, clock, portrait)
    -- (carried over < or > for a moment: the box turns)
    if st.held and st.usePtr and st.arrow and clock - st.arrowSince > 0.5 then
      setBox(st.box + st.arrow)
      st.arrowSince = clock
    end
    view.draw(body, clock, portrait, W.previewMon(), modeColor[st.mode], T(MODE_KEYS[st.mode]))
    if st.toast and not K.toast(st.toast, clock, body, view.C.bad, view.C.good, K.UI.hud) then
      st.toast = nil
    end
  end

  W.A, W.SELECT, W.SWAP, W.DRAG = A, SELECT, SWAP, DRAG
  return W
end
