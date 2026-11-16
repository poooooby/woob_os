-- The Items app: the Bag and the PC's item storage side by side, a commander. The focused pane's
-- item goes across to the other: A (a stepper for how many when there's more than one), SELECT the
-- whole stack. Landscape: Bag | PC; portrait: one pane at a time under a Bag | PC switch.
--   buttons  Left / Right the pane, Up / Down the item, L / R the Bag's pocket, A move, SELECT move
--            all, START the menu for the pane in focus (the PC: sort, toss; the Bag: sort the
--            pocket), B close
--   stepper  Left / Right one more or less, Up / Down ten, A move, B back
--   touch    tap an item, tap it again to move it; the stepper's - / + / All / Move (the dim: back);
--            a pocket on the switch; Sort on either pane's head; drag (or the wheel) scrolls a list
-- The model is src/inventory.lua (env.inv); rows are made again only after a change.
-- The Pokédex's glass: two panes over a backdrop lit by the pocket in focus (the Bag's pocket, or the
-- pocket of the PC's chosen item), the Bag's pockets a glass switch whose thumb slides (the chosen one
-- wide, with its name), the PC's head a filling capacity bar. Its motion, numbers only: the chosen row's
-- highlight glides, the lists scroll smoothly, the rows rise in one after another as a pane opens, a
-- pocket turns (sliding from the side it turned to) or a sort lands; the chosen item's card pops its icon
-- up and slides its words in; the stepper and the menu pop up over a dim.
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local ROW_H, HEAD_H, FOOT_H, GAP = 10, 10, 20, 2
-- hit args: PC rows 1.., Bag rows BAG + i, the rest below
local BAG = 1000
local POCKET_PREV, POCKET_NEXT, SEG_PC, SEG_BAG = 2001, 2002, 2003, 2004
local STEP_MINUS, STEP_PLUS, STEP_ALL, STEP_GO, STEP_BACK, STEP_CARD = 2010, 2011, 2012, 2013, 2014, 2015
local MENU_ROW, MENU_DIM, SORT_BUTTON, SORT_BAG = 2020, 2029, 2030, 2031
local POCKET_TAB = 2040   -- (+ the pocket's place: the switch's segments)
-- each pocket's colour (the backdrop's lights, its dot on the switch, the item card's tile)
local POCKET_C = { ITEMS = { 255, 149, 60 }, KEY_ITEMS = { 230, 176, 30 }, POKE_BALLS = { 240, 80, 80 },
                   TM_CASE = { 82, 140, 245 }, BERRY_POUCH = { 84, 190, 96 } }
local POCKET_KEY = setmetatable({}, { __index = function(t, id)
  local k = "pocket." .. tostring(id)
  t[id] = k
  return k
end })
local C = {
  ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, faint = { 162, 162, 170 }, white = { 255, 255, 255 },
  black = { 0, 0, 0 }, accent = { 10, 132, 255 }, red = { 255, 59, 48 }, orange = { 255, 149, 0 },
  track = { 118, 118, 128, 0.18 }, slate = { 120, 132, 178 }, slate2 = { 150, 120, 190 },
}

-- (the words are keys of lang/*.lua, through env.T)
local HINTS = {
  main = { { "A", "hint.move" }, { "SELECT", "hint.all" }, { "L R", "hint.pocket" }, { "START", "hint.menu" } },
  step = { { "< >", "hint.one" }, { "^ v", "hint.ten" }, { "A", "hint.ok" }, { "B", "hint.back" } },
  menu = { { "A", "hint.choose" }, { "B", "hint.back" } },
}
-- START's menu, by the pane in focus
local MENU = {
  pc = { "items.sortName", "items.sortPocket", "items.tossMenu" },
  bag = { "items.sortName", "items.sortType" },
}
local TOSS = 3   -- (the PC's menu: the row that tosses)
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, inv, T = env.K, env.inv, env.T or NO_T
  -- (pad: the shelf's item pad lights up while the window is open)
  local W = { title = "Items", pad = true }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local st = {
    focus = "pc", pocket = 1, pockets = {},
    pc = { rows = {}, cursor = 1, top = 0, x1 = 0, x2 = 0 },
    bag = { rows = {}, cursor = 1, top = 0, x1 = 0, x2 = 0 },
    step = nil, menu = nil, toast = nil, visible = 6, portrait = false,
    pcHead = "PC", qtyText = {},
  }
  W.state = st

  local qtyText = K.textCache(function(n) return "×" .. tostring(n) end)
  local stepText = K.textCache(function(k) return tostring(floor(k / 1000)) .. " / " .. tostring(k % 1000) end)

  local function pane(name) return st[name or st.focus] end
  -- (keeps the chosen row in view, unless the list was scrolled by hand since the last press: a drag
  -- or the wheel would otherwise be pulled straight back to it on the next frame)
  local function clampPane(p, follow)
    if follow then p.free = false end
    p.cursor = max(1, min(p.cursor, #p.rows))
    local vis = st.visible
    if not p.free then
      if p.cursor > p.top + vis then p.top = p.cursor - vis end
      if p.cursor <= p.top then p.top = p.cursor - 1 end
    end
    p.top = max(0, min(p.top, max(0, #p.rows - vis)))
  end
  local function refresh()
    local s = session()
    st.pockets = inv.pockets(s)
    for _, p in ipairs(st.pockets) do p.key = POCKET_KEY[p.id] end
    st.pocket = max(1, min(st.pocket, #st.pockets))
    local pk = st.pockets[st.pocket]
    st.pc.rows = inv.pcRows(s)
    st.bag.rows = pk and inv.bagRows(s, pk.id) or {}
    local used, cap = inv.pcCount(s)
    st.pcHead = T("items.pc") .. "  " .. used .. "/" .. cap
    st.pcUsed, st.pcCap, st.pcCountText = used, cap, used .. "/" .. cap
    st.pocketKey = pk and ("pocket." .. pk.id) or "items.bag"
    clampPane(st.pc, true)
    clampPane(st.bag, true)
  end
  W.refresh = refresh

  local function toast(text, bad)
    st.toast = { text = text, bad = bad, t = now() }
    se(bad and "SE_FAILURE" or "SE_SELECT")
  end

  local function moveCursor(p, d)
    if #p.rows == 0 then return end
    local c = max(1, min(#p.rows, p.cursor + d))
    if c ~= p.cursor then
      p.cursor = c
      clampPane(p, true)
      se("SE_SELECT")
    end
  end
  local function setFocus(name)
    if st.focus ~= name then
      st.focus = name
      se("SE_SELECT")
    end
  end
  local function setPocket(i)
    local n = #st.pockets
    if n == 0 then return end
    local dir = i > st.pocket and 1 or -1
    i = (i - 1) % n + 1
    if i ~= st.pocket then
      st.pocket = i
      st.bag.cursor, st.bag.top = 1, 0
      -- (its rows rise in again, from the side it turned to)
      st.bag.at, st.bag.dir = nil, dir
      refresh()
      se("SE_SELECT")
    end
  end

  -- move `qty` of the focused item across (or toss it)
  local function act(qty, toss)
    local s = session()
    local p = pane()
    local row = p.rows[p.cursor]
    st.step = nil
    if not row then return end
    local ok, why
    if toss then
      ok, why = inv.toss(s, p.cursor, qty)
    elseif st.focus == "pc" then
      ok, why = inv.withdraw(s, p.cursor, qty)
    else
      local pk = st.pockets[st.pocket]
      ok, why = inv.deposit(s, pk and pk.id or "ITEMS", p.cursor, qty)
    end
    if ok then
      -- (the item crosses the pad: into the PC, or out of it into the Bag)
      if not toss and env.pad and env.pad.transfer then
        pcall(env.pad.transfer, row.id, st.focus == "pc" and "in" or "out")
      end
      local what = row.name .. (row.showQty and (" ×" .. qty) or "")
      toast(T.f(toss and "items.tossed" or (st.focus == "pc" and "items.toBag" or "items.toPc"), what))
    else
      toast(T(why and ("reason.item." .. why) or "failed"), true)
    end
    refresh()
  end
  -- A on an item: one moves at once, more ask how many (the whole stack to start)
  local function begin(toss)
    local p = pane()
    local row = p.rows[p.cursor]
    if not row then return end
    if row.important and (toss or st.focus == "bag") then return toast(T("reason.item.important"), true) end
    if row.qty <= 1 then return act(1, toss) end
    st.step = { qty = row.qty, max = row.qty, toss = toss }
    se("SE_SELECT")
  end
  local function stepBy(d)
    local sp = st.step
    local q = max(1, min(sp.max, sp.qty + d))
    if q ~= sp.qty then
      sp.qty = q
      se("SE_SELECT")
    end
  end
  local function openMenu(name)
    st.focus = name
    st.menu = { cursor = 1, pane = name, list = MENU[name] }
    se("SE_SELECT")
  end
  local function menuChoose(i)
    local m = st.menu
    st.menu = nil
    if not (m and m.list[i]) then return end
    local s = session()
    if m.pane == "bag" then
      local pk = st.pockets[st.pocket]
      local ok, why = inv.sortPocket(s, pk and pk.id or "ITEMS", i == 1 and "name" or "type")
      if not ok then return toast(T("reason.item." .. tostring(why)), true) end
      st.bag.cursor, st.bag.top = 1, 0
      st.bag.at, st.bag.dir = nil, 0
      refresh()
      toast(T(i == 1 and "items.sortedName" or "items.sortedType"))
    elseif i == TOSS then
      st.focus = "pc"
      begin(true)
    else
      inv.sort(s, i == 1 and "name" or "pocket")
      st.pc.cursor, st.pc.top = 1, 0
      st.pc.at, st.pc.dir = nil, 0
      refresh()
      toast(T(i == 1 and "items.sortedName" or "items.sortedPocket"))
    end
  end

  -- ------- buttons

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
    if st.menu then
      if nav.up or nav.down then
        st.menu.cursor = (st.menu.cursor - 1 + (nav.down and 1 or -1)) % #st.menu.list + 1
        se("SE_SELECT")
      elseif pressed("a") then menuChoose(st.menu.cursor)
      elseif pressed("b") or pressed("start") then
        st.menu = nil
        se("SE_SELECT")
      end
      return true
    end
    if st.step then
      if nav.right then stepBy(1)
      elseif nav.left then stepBy(-1)
      elseif nav.up then stepBy(10)
      elseif nav.down then stepBy(-10)
      elseif pressed("select") then st.step.qty = st.step.max
      elseif pressed("a") then act(st.step.qty, st.step.toss)
      elseif pressed("b") then
        st.step = nil
        se("SE_SELECT")
      end
      return true
    end
    if pressed("start") then
      openMenu(st.focus)
      return true
    end
    if pressed("b") then return false end
    if nav.left then setFocus("bag")
    elseif nav.right then setFocus("pc")
    elseif nav.up then moveCursor(pane(), -1)
    elseif nav.down then moveCursor(pane(), 1)
    elseif pressed("l") then setPocket(st.pocket - 1)
    elseif pressed("r") then setPocket(st.pocket + 1)
    elseif pressed("a") then begin(false)
    elseif pressed("select") then
      local p = pane()
      local row = p.rows[p.cursor]
      if row then
        if row.important and st.focus == "bag" then
          toast(T("reason.item.important"), true)
        else
          act(row.qty, false)
        end
      end
    end
    return true
  end

  function W.tap(arg)
    if type(arg) ~= "number" then return end
    if st.menu and arg >= MENU_ROW and arg < MENU_ROW + #st.menu.list then return menuChoose(arg - MENU_ROW + 1) end
    if st.menu then
      st.menu = nil
      return
    end
    if arg == STEP_MINUS then return st.step and stepBy(-1) end
    if arg == STEP_PLUS then return st.step and stepBy(1) end
    if arg == STEP_ALL then
      if st.step then st.step.qty = st.step.max end
      return
    end
    if arg == STEP_GO then return st.step and act(st.step.qty, st.step.toss) end
    if arg == STEP_BACK then
      st.step = nil
      return
    end
    if arg == STEP_CARD then return end
    st.step = nil
    if arg == POCKET_PREV then return setPocket(st.pocket - 1) end
    if arg == POCKET_NEXT then return setPocket(st.pocket + 1) end
    if arg > POCKET_TAB and arg <= POCKET_TAB + #st.pockets then
      st.focus = "bag"
      return setPocket(arg - POCKET_TAB)
    end
    if arg == SEG_PC then return setFocus("pc") end
    if arg == SEG_BAG then return setFocus("bag") end
    if arg == SORT_BUTTON then return openMenu("pc") end
    if arg == SORT_BAG then return openMenu("bag") end
    local name, i = "pc", arg
    if arg > BAG then name, i = "bag", arg - BAG end
    local p = st[name]
    if not p.rows[i] then return end
    if st.focus == name and p.cursor == i then return begin(false) end
    st.focus, p.cursor = name, i
    clampPane(p, true)
    se("SE_SELECT")
  end

  -- a drag or the wheel: the list under it (or the focused one)
  function W.scroll(dy, x)
    local p = pane()
    if x and not st.portrait then
      if x >= st.pc.x1 and x < st.pc.x2 then p = st.pc elseif x >= st.bag.x1 and x < st.bag.x2 then p = st.bag end
    end
    p.free = true
    p.top = max(0, min(max(0, #p.rows - st.visible), p.top - dy / ROW_H))
  end

  function W.hints()
    if st.menu then return T.list(HINTS.menu) end
    if st.step then return T.list(HINTS.step) end
    return T.list(HINTS.main)
  end

  -- ------- drawing (no tables made here)

  local approach, outCubic, outBack, stagger = K.approach, K.outCubic, K.outBack, K.stagger
  local G, bodyNow = nil, nil
  -- the motion's numbers (see the top); the panes keep their own: `at` (when their rows started rising
  -- in; nil: now), `dir` (the side they slide from), `glide` (the highlight's row), `shown` (the eased top)
  local mv = { lastT = nil, coloured = false, r = 0.6, g = 0.6, b = 0.6, r2 = 0.6, g2 = 0.6, b2 = 0.6,
               pk = nil, seg = nil, focus = nil, fk = nil, cap = nil, itemId = nil, itemPane = nil, itemAt = -10,
               step = nil, stepAt = -10, qty = 0, qtyShown = nil, qtyAt = -10, menu = nil, menuAt = -10,
               menuCur = nil }
  W.motion = mv

  -- (everything drawn after it at `e` of itself, until unfade(); numbers only)
  local FADES, nFade = {}, 0
  local function fade(e)
    nFade = nFade + 1
    FADES[nFade] = K.getFade()
    K.setFade(FADES[nFade] * (e > 0 and e or 0))
  end
  local function unfade()
    K.setFade(FADES[nFade])
    nFade = nFade - 1
  end
  local function pocketColour(id) return POCKET_C[id] or C.slate end
  local function icon(id, x, y, size)
    if env.itemIcon then pcall(env.itemIcon, id, x, y, size, K.getFade()) end
  end

  -- (the backdrop's lights: the pocket in focus first, the other pane's after it; eased)
  local function tint(dt)
    local bk = st.pockets[st.pocket]
    local bagC = bk and pocketColour(bk.id) or C.slate
    local row = st.pc.rows[st.pc.cursor]
    local pcC = row and pocketColour(row.pocket) or C.slate2
    local t1, t2 = bagC, pcC
    if st.focus == "pc" then t1, t2 = pcC, bagC end
    local rate = mv.coloured and 6 or 1000
    mv.coloured = true
    mv.r, mv.g, mv.b = approach(mv.r, t1[1] / 255, dt, rate), approach(mv.g, t1[2] / 255, dt, rate),
      approach(mv.b, t1[3] / 255, dt, rate)
    local k2 = t2 == t1 and 0.35 or 0
    mv.r2 = approach(mv.r2, (t2[1] + (255 - t2[1]) * k2) / 255, dt, rate)
    mv.g2 = approach(mv.g2, (t2[2] + (255 - t2[2]) * k2) / 255, dt, rate)
    mv.b2 = approach(mv.b2, (t2[3] + (255 - t2[3]) * k2) / 255, dt, rate)
    return bagC, pcC
  end

  -- the Bag's pockets: a glass switch, its thumb sliding to the chosen one, which widens to its name;
  -- the others a dot of their colour (one pocket: its name alone)
  local function pocketSwitch(x, y, w, h, dt)
    local n = #st.pockets
    if n <= 1 then
      local name = T(st.pocketKey)
      local fs = K.fit(name, 4.8, w - 4)
      K.bold(name, x + 2, y + (h - fs * 1.2) / 2, fs, C.ink)
      return
    end
    if mv.pk == nil then mv.pk = st.pocket end
    mv.pk = approach(mv.pk, st.pocket, dt, 16)
    local p = max(1, min(n, mv.pk))
    local rad = h / 2
    local tb = K.R(x, y, w, h)
    K.col(C.white, 0.32)
    K.box("fill", tb, rad)
    K.ring(tb, rad, C.white, 0.7, 0.3)
    local off = min(9, (w - 1) / (n + 2))
    local onW = w - 1 - off * (n - 1)
    local k0 = min(n - 1, floor(p))
    local f = p - k0
    local sx, tx = x + 0.5, x + 0.5
    for k = 1, n do
      local wk = off + (onW - off) * max(0, 1 - abs(p - k))
      if k == k0 then tx = sx + f * wk end
      sx = sx + wk
    end
    K.col(C.black, 0.1)
    K.box("fill", K.R(tx, y + 0.9, onW, h - 1), rad - 0.5)
    K.col(C.white)
    K.box("fill", K.R(tx, y + 0.5, onW, h - 1), rad - 0.5)
    sx = x + 0.5
    for k = 1, n do
      local q = max(0, 1 - abs(p - k))
      local wk = off + (onW - off) * q
      local pk = st.pockets[k]
      local cx = sx + min(wk / 2, 4.2)
      K.col(pocketColour(pk.id))
      G.circle("fill", K.X(cx), K.Y(y + h / 2), (1.2 + 0.3 * q) * K.sc)
      if q > 0.3 then
        local name = T(pk.key)
        local fs = K.fit(name, 4.2, onW - 9)
        local a = (q - 0.3) / 0.7
        K.scissor(K.R(sx, y, wk, h))
        K.bold(name, sx + 6.5, y + (h - fs * 1.2) / 2, fs, C.ink, nil, nil, a * a)
        K.scissor(bodyNow)
      end
      K.addHit(K.R(sx, y, wk, h), "win", POCKET_TAB + k)
      sx = sx + wk
    end
  end

  -- the PC's head: its name, how full, and a bar filling to it (orange near full, red when full)
  local function pcHead(x, y, w, h, dt)
    local label = T("items.pc")
    K.bold(label, x + 2, y + (h - 4.8 * 1.2) / 2, 4.8, C.ink)
    local lx = x + 2 + K.width(label, 4.8) + 3
    K.text(st.pcCountText or "", lx, y + (h - 3.8 * 1.2) / 2 + 0.3, 3.8, C.soft)
    local bx = lx + K.width(st.pcCountText or "", 3.8) + 3
    local bw = x + w - bx - 1
    if bw < 6 then return end
    local k = (st.pcCap or 0) > 0 and st.pcUsed / st.pcCap or 0
    mv.cap = approach(mv.cap or 0, k, dt, 6)
    K.col(C.white, 0.6)
    K.box("fill", K.R(bx, y + h / 2 - 0.8, bw, 1.6), 0.8)
    if mv.cap > 0.004 then
      K.col(k >= 1 and C.red or (k > 0.85 and C.orange or C.accent))
      K.box("fill", K.R(bx, y + h / 2 - 0.8, max(1.6, bw * min(1, mv.cap)), 1.6), 0.8)
    end
  end

  -- a pane's head: the Bag's pockets or the PC's count; each with its Sort button
  local function drawHead(name, x, y, w, dt)
    st[name].hx, st[name].hy = x, y + HEAD_H
    local sb = K.R(x + w - 18, y + 1.8, 15, HEAD_H - 3.6)
    K.button(sb, T("items.sort"), "tinted", false, 4)
    K.addHit(sb, "win", name == "pc" and SORT_BUTTON or SORT_BAG)
    if name == "pc" then pcHead(x + 2, y + 1.5, w - 22, HEAD_H - 3, dt)
    else pocketSwitch(x + 2, y + 1.6, w - 22, HEAD_H - 3.2, dt) end
    K.hairline(x + 2, y + HEAD_H, w - 4)
  end

  -- a pane's rows inside its glass (x, y, w, h: the list's room): the highlight gliding under them,
  -- the rows rising in one after another (sliding from `dir`), parted by hairlines from the name on
  local function drawList(p, name, x, y, w, h, focused, ringC, clock, dt)
    local base = name == "bag" and BAG or 0
    local clip = K.R(x, y, w, h)
    K.scissor(clip)
    if p.at == nil then p.at, p.glide, p.shown = clock, nil, nil end
    if p.shown == nil or p.free then p.shown = p.top else p.shown = approach(p.shown, p.top, dt, 20) end
    local top = p.shown
    local n = #p.rows
    if n > 0 then
      if p.glide == nil then p.glide = p.cursor end
      p.glide = approach(p.glide, p.cursor, dt, 24)
      local hb = K.R(x + 1.5, y + (p.glide - 1 - top) * ROW_H + 0.4, w - 3, ROW_H - 0.8)
      K.col(C.white, focused and 0.88 or 0.45)
      K.box("fill", hb, 2.5)
      if focused then K.ring(hb, 2.5, ringC, 0.55 + 0.35 * K.pulse(), 0.6) end
    end
    local first = floor(top) + 1
    local last = min(n, first + st.visible + 1)
    local since = clock - p.at
    local dir = p.dir or 0
    for i = first, last do
      local row = p.rows[i]
      local ry = y + (i - 1 - top) * ROW_H
      local e = stagger(since, i - first, 0.025, 0.26)
      local oy, ox = (1 - e) * 4, (1 - e) * dir * 10
      fade(e)
      local on = i == p.cursor
      if i < n and not on and i + 1 ~= p.cursor then K.hairline(x + 13 + ox, ry + ROW_H - 0.1 + oy, w - 15) end
      icon(row.id, x + 3 + ox, ry + 1 + oy, 8)
      local qw = row.showQty and 14 or 0
      local ns = K.fit(row.name, 4.6, w - 16 - qw)
      local ty = ry + 2.6 + (4.6 - ns) * 0.5 + oy
      if on then K.bold(row.name, x + 13 + ox, ty, ns, C.ink) else K.text(row.name, x + 13 + ox, ty, ns, C.ink) end
      if row.showQty then
        K.text(qtyText(row.qty), x + w - 17 + ox, ry + 2.6 + oy, 4.4, on and C.ink or C.soft, "right", 13)
      end
      unfade()
      K.addHit(K.R(x, ry, w, ROW_H), "win", base + i, clip)
    end
    if n == 0 then
      local words = T(name == "pc" and "items.emptyPc" or "items.emptyPocket")
      local e = stagger(since, 0, 0, 0.3)
      K.text(words, x, y + h / 2 - 3 + (1 - e) * 4, K.fit(words, 4.6, w - 6), C.soft, "center", w, e)
    end
    K.scrollbar(x + w, y, h, top, st.visible, n)
    K.scissor(bodyNow)
  end

  -- a pane: its glass (clearer when it hasn't the focus), its head, its rows
  local function drawPane(name, x, y, w, h, focused, glassA, ringC, clock, dt)
    K.glass(K.R(x, y, w, h), 4, glassA)
    drawHead(name, x, y, w, dt)
    local top = y + HEAD_H + 0.5
    local p = st[name]
    st.visible = max(1, floor((y + h - 1 - top) / ROW_H))
    clampPane(p)
    drawList(p, name, x, top, w, y + h - 1 - top, focused, ringC, clock, dt)
  end

  -- the chosen item's card: its icon popping up on a tile of its pocket's colour, its name, how many,
  -- its pocket (the PC's), its words sliding in after
  local function drawFoot(x, y, w, h, clock)
    local cb = K.R(x, y, w, h)
    K.glass(cb, 4, 0.58)
    local p = pane()
    local row = p.rows[p.cursor]
    if not row then
      mv.itemId = nil
      return
    end
    if row.id ~= mv.itemId or st.focus ~= mv.itemPane then mv.itemId, mv.itemPane, mv.itemAt = row.id, st.focus, clock end
    local t = clock - mv.itemAt
    local pop = 0.55 + 0.45 * outBack(t / 0.34)
    local c = pocketColour(row.pocket)
    local ts = h - 4
    local tx, ty = x + 2, y + 2
    local tile = K.R(tx, ty, ts, ts)
    K.col(c, 0.26)
    K.box("fill", tile, 3)
    K.ring(tile, 3, C.white, 0.75, 0.35)
    K.glow(tx + ts / 2, ty + ts / 2, ts * 0.55, ts * 0.55, C.white, 0.32 * outCubic(t / 0.2))
    local is = (ts - 4) * pop
    icon(row.id, tx + (ts - is) / 2, ty + (ts - is) / 2, is)
    local e = outCubic((t - 0.04) / 0.3)
    local ox = (1 - e) * 6
    fade(e)
    local wx = tx + ts + 3 + ox
    local ww = x + w - 3 - wx
    local qw = row.showQty and (K.width(qtyText(row.qty), 4.4) + 2) or 0
    local ns = K.fit(row.name, 4.8, ww - qw - 2)
    K.bold(row.name, wx, y + 2.2 + (4.8 - ns) * 0.5, ns, C.ink)
    if row.showQty then K.bold(qtyText(row.qty), wx, y + 2.5, 4.4, C.soft, "right", ww) end
    local dy = y + 8.2
    if st.focus == "pc" then
      -- (the PC holds every pocket's items: which one it goes to)
      local pname = T(POCKET_KEY[row.pocket])
      local pw = K.width(pname, 3.2) + 5
      local nx = wx + K.width(row.name, ns) + 2.5
      if nx + pw < wx + ww - qw then
        local chip = K.R(nx, y + 2.7, pw, 4.6)
        K.col(c, 0.22)
        K.box("fill", chip, 2.3)
        K.text(pname, chip[1], chip[2] + 0.4, 3.2, K.dark(c, 0.35), "center", pw)
      end
    end
    local TS = K.textScale()
    if TS > 1 then
      -- (bigger text: its lines cut at a whole line, not through one)
      local top = dy - 0.6 * (TS - 1) * 3.6
      local lh = K.font(3.6 * TS * K.sc):getHeight() / K.sc
      local n = max(1, floor((y + h - top) / lh))
      K.scissor(K.R(x, y, w, min(h, top + n * lh + 0.2 - y)))
    else
      K.scissor(cb)
    end
    K.text(row.desc, wx, dy, 3.6, C.soft, "left", ww)
    K.scissor(bodyNow)
    unfade()
  end

  -- how many: a card popping up over a dim, the item, - count +, a bar filling to the count, All, Move /
  -- Toss
  local function drawStep(body, clock, dt)
    local sp = st.step
    if not sp then return end
    local e = outCubic((clock - mv.stepAt) / 0.22)
    K.dim(body, 0.24 * e)
    K.addHit(body, "win", STEP_BACK)
    local cw, ch = min(body[3] - 12, 124), 52
    local cx = body[1] + (body[3] - cw) / 2
    local cy = body[2] + max(2, (body[4] - ch) / 2) + (1 - e) * 8
    local b = K.R(cx, cy, cw, ch)
    fade(e)
    K.shadow(b, 6, 1.6, 0.28)
    K.glass(b, 6, 0.92)
    K.addHit(b, "win", STEP_CARD)
    local title = T(sp.toss and "items.tossHowMany" or "items.howMany")
    K.bold(title, cx + 4, cy + 3.5, K.fit(title, 5, cw - 8), C.ink, "center", cw - 8)
    local p = pane()
    local row = p.rows[p.cursor]
    if row then
      local ns = K.fit(row.name, 4, cw - 26)
      local nw = K.width(row.name, ns)
      local ix = cx + (cw - nw - 9) / 2
      icon(row.id, ix, cy + 10, 7)
      K.text(row.name, ix + 9, cy + 11.2 + (4 - ns) * 0.5, ns, C.soft)
    end
    local by = cy + 19
    local mb, pb = K.R(cx + 6, by, 14, 10), K.R(cx + cw - 20, by, 14, 10)
    K.button(mb, "-", "gray", false, 6)
    K.button(pb, "+", "gray", false, 6)
    K.addHit(mb, "win", STEP_MINUS)
    K.addHit(pb, "win", STEP_PLUS)
    -- (the count bumps as it changes)
    if sp.qty ~= mv.qtyShown then
      if mv.qtyShown ~= nil then mv.qtyAt = clock end
      mv.qtyShown = sp.qty
    end
    local bump = 1 - outCubic((clock - mv.qtyAt) / 0.18)
    local fs = 6 * (1 + 0.14 * bump)
    K.bold(stepText(sp.qty * 1000 + sp.max), cx + 20, by + 5 - fs * 0.6, fs, C.ink, "center", cw - 40)
    mv.qty = approach(mv.qty, sp.qty / max(1, sp.max), dt, 16)
    local track = K.R(cx + 8, by + 12.5, cw - 16, 1.6)
    K.col(C.track)
    K.box("fill", track, 0.8)
    K.col(sp.toss and C.red or C.accent)
    K.box("fill", K.R(track[1], track[2], max(1.6, track[3] * mv.qty), 1.6), 0.8)
    local bw = (cw - 10 - GAP) / 2
    local fy = cy + ch - 14
    local all = K.R(cx + 5, fy, bw, 10)
    K.button(all, T("items.all"), "gray", false, 4.6)
    K.addHit(all, "win", STEP_ALL)
    local go = K.R(cx + 5 + bw + GAP, fy, bw, 10)
    K.button(go, T(sp.toss and "items.toss" or "items.move"), sp.toss and "danger" or "accent", true, 4.8)
    K.addHit(go, "win", STEP_GO)
    unfade()
  end

  -- START's menu: a popover dropping from the head of the pane it's for, over a light dim; the chosen
  -- row's highlight gliding
  local function drawMenu(body, clock, dt)
    local m = st.menu
    if not m then return end
    local e = outCubic((clock - mv.menuAt) / 0.2)
    K.dim(body, 0.12 * e)
    K.addHit(body, "win", MENU_DIM)
    local list = m.list
    local mw = 66
    local px = st[m.pane].hx or body[1]
    local py = st[m.pane].hy or (body[2] + HEAD_H + 3)
    local mb = K.R(max(body[1] + 2, min(px + 2, body[1] + body[3] - mw - 2)), py + 1 - (1 - e) * 4, mw, #list * 10 + 4)
    fade(e)
    K.shadow(mb, 5, 1.6, 0.25)
    K.glass(mb, 5, 0.92)
    if mv.menuCur == nil then mv.menuCur = m.cursor end
    mv.menuCur = approach(mv.menuCur, m.cursor, dt, 26)
    local tossOn = m.pane == "pc" and m.cursor == TOSS
    K.col(tossOn and C.red or C.accent)
    K.box("fill", K.R(mb[1] + 2, mb[2] + 2 + (mv.menuCur - 1) * 10, mb[3] - 4, 10), 2.5)
    for i = 1, #list do
      local rb = K.R(mb[1] + 2, mb[2] + 2 + (i - 1) * 10, mb[3] - 4, 10)
      local danger = m.pane == "pc" and i == TOSS
      if danger and i > 1 and m.cursor ~= i and m.cursor ~= i - 1 then K.hairline(rb[1] + 2, rb[2] - 0.1, rb[3] - 4) end
      local label = T(list[i])
      K.text(label, rb[1] + 4, rb[2] + 2.4, K.fit(label, 4.8, rb[3] - 8),
        i == m.cursor and C.white or (danger and C.red or C.ink))
      K.addHit(rb, "win", MENU_ROW + i - 1)
    end
    unfade()
  end

  local M = 3
  function W.draw(body, clock, portrait)
    G = K.graphics()
    bodyNow = body
    st.portrait = portrait
    local dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT = clock
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local bagC, pcC = tint(dt)
    K.backdrop(body, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2)
    K.scissor(body)
    if st.step ~= mv.step then mv.step, mv.stepAt, mv.qty, mv.qtyShown = st.step, clock, 0, nil end
    if st.menu ~= mv.menu then mv.menu, mv.menuAt, mv.menuCur = st.menu, clock, nil end
    local bagOn = st.focus == "bag" and 1 or 0
    mv.fk = mv.fk and approach(mv.fk, bagOn, dt, 14) or bagOn
    local footH = portrait and min(30, floor(h * 0.16)) or FOOT_H
    local footY = y + h - footH - M
    if portrait then
      -- the Bag | PC switch, then the one pane (its rows rising in as it changes)
      mv.seg = mv.seg and approach(mv.seg, 2 - bagOn, dt, 18) or 2 - bagOn
      K.glassSwitch(x + M, y + 2, w - M * 2, 8, mv.seg, "win", SEG_BAG, T("items.bag"), SEG_PC, st.pcHead, nil, nil, 4.2)
      if mv.focus ~= st.focus then
        if mv.focus ~= nil then
          local p = pane()
          p.at, p.dir = nil, st.focus == "pc" and 1 or -1
        end
        mv.focus = st.focus
      end
      local name = st.focus
      local top = y + 12
      drawPane(name, x + M, top, w - M * 2, footY - GAP - top, true, 0.6, K.dark(name == "bag" and bagC or pcC, 0.15),
        clock, dt)
    else
      mv.focus = st.focus
      local pw = (w - M * 3) / 2
      st.bag.x1, st.bag.x2 = K.X(x), K.X(x + M + pw + M / 2)
      st.pc.x1, st.pc.x2 = K.X(x + M + pw + M / 2), K.X(x + w)
      local ph = footY - GAP - (y + M)
      drawPane("bag", x + M, y + M, pw, ph, st.focus == "bag", 0.4 + 0.22 * mv.fk, K.dark(bagC, 0.15), clock, dt)
      drawPane("pc", x + M * 2 + pw, y + M, pw, ph, st.focus == "pc", 0.62 - 0.22 * mv.fk, K.dark(pcC, 0.15), clock, dt)
    end
    K.scissor(body)
    drawFoot(x + M, footY, w - M * 2, footH, clock)
    drawMenu(body, clock, dt)
    drawStep(body, clock, dt)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, footY - y), C.red, K.UI.green, K.UI.hud) then
      st.toast = nil
    end
  end

  refresh()
  return W
end
