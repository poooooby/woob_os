-- The Items app: the Bag and the PC's item storage side by side, a commander. The focused pane's
-- item goes across to the other: A (a stepper for how many when there's more than one), SELECT the
-- whole stack. Landscape: Bag | PC; portrait: one pane at a time under a Bag | PC switch.
--   buttons  Left / Right the pane, Up / Down the item, L / R the Bag's pocket, A move, SELECT move
--            all, START the menu (sort, toss), B close
--   stepper  Up / Down one more or less, Left / Right ten, A move, B back
--   touch    tap an item, tap it again to move it; the stepper's - / + / All / Move; < > the pocket;
--            drag (or the wheel) scrolls a list
-- The model is src/inventory.lua (env.inv); rows are made again only after a change.
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min = math.floor, math.max, math.min

local C = {
  ink = { 30, 32, 44 }, soft = { 104, 108, 128 }, faint = { 150, 154, 170 }, accent = { 64, 132, 246 },
  pane = { 255, 255, 255 }, head = { 238, 240, 245 }, headFoot = { 226, 229, 236 }, bad = { 220, 62, 74 },
  good = { 120, 230, 160 }, toastInk = { 30, 32, 44 }, wash = { 64, 132, 246, 0.12 }, chip = { 214, 220, 232 },
}
local ROW_H, HEAD_H, FOOT_H = 10, 10, 16
-- hit args: PC rows 1.., Bag rows BAG + i, the rest below
local BAG = 1000
local POCKET_PREV, POCKET_NEXT, SEG_PC, SEG_BAG = 2001, 2002, 2003, 2004
local STEP_MINUS, STEP_PLUS, STEP_ALL, STEP_GO, STEP_BACK = 2010, 2011, 2012, 2013, 2014
local MENU_ROW, SORT_BUTTON = 2020, 2030

-- (the words are keys of lang/*.lua, through env.T)
local HINTS = {
  main = { { "A", "hint.move" }, { "SELECT", "hint.all" }, { "L R", "hint.pocket" }, { "START", "hint.menu" } },
  step = { { "< >", "hint.ten" }, { "A", "hint.ok" }, { "B", "hint.back" } },
  menu = { { "A", "hint.choose" }, { "B", "hint.back" } },
}
local MENU = { "items.sortName", "items.sortPocket", "items.tossMenu" }
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
  local function clampPane(p)
    p.cursor = max(1, min(p.cursor, #p.rows))
    local vis = st.visible
    if p.cursor > p.top + vis then p.top = p.cursor - vis end
    if p.cursor <= p.top then p.top = p.cursor - 1 end
    p.top = max(0, min(p.top, max(0, #p.rows - vis)))
  end
  local function refresh()
    local s = session()
    st.pockets = inv.pockets(s)
    st.pocket = max(1, min(st.pocket, #st.pockets))
    local pk = st.pockets[st.pocket]
    st.pc.rows = inv.pcRows(s)
    st.bag.rows = pk and inv.bagRows(s, pk.id) or {}
    local used, cap = inv.pcCount(s)
    st.pcHead = T("items.pc") .. "  " .. used .. "/" .. cap
    st.pocketKey = pk and ("pocket." .. pk.id) or "items.bag"
    clampPane(st.pc)
    clampPane(st.bag)
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
      clampPane(p)
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
    i = (i - 1) % n + 1
    if i ~= st.pocket then
      st.pocket = i
      st.bag.cursor, st.bag.top = 1, 0
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
  local function menuChoose(i)
    st.menu = nil
    local s = session()
    if i == 1 or i == 2 then
      inv.sort(s, i == 1 and "name" or "pocket")
      st.pc.cursor, st.pc.top = 1, 0
      refresh()
      toast(T(i == 1 and "items.sortedName" or "items.sortedPocket"))
    elseif i == 3 then
      st.focus = "pc"
      begin(true)
    end
  end

  -- ------- buttons

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
    if st.menu then
      if nav.up or nav.down then
        st.menu.cursor = (st.menu.cursor - 1 + (nav.down and 1 or -1)) % #MENU + 1
        se("SE_SELECT")
      elseif pressed("a") then menuChoose(st.menu.cursor)
      elseif pressed("b") or pressed("start") then
        st.menu = nil
        se("SE_SELECT")
      end
      return true
    end
    if st.step then
      if nav.up then stepBy(1)
      elseif nav.down then stepBy(-1)
      elseif nav.right then stepBy(10)
      elseif nav.left then stepBy(-10)
      elseif pressed("select") then st.step.qty = st.step.max
      elseif pressed("a") then act(st.step.qty, st.step.toss)
      elseif pressed("b") then
        st.step = nil
        se("SE_SELECT")
      end
      return true
    end
    if pressed("start") then
      st.menu = { cursor = 1 }
      se("SE_SELECT")
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
    if arg >= MENU_ROW and arg < MENU_ROW + #MENU then return menuChoose(arg - MENU_ROW + 1) end
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
    st.step = nil
    if arg == POCKET_PREV then return setPocket(st.pocket - 1) end
    if arg == POCKET_NEXT then return setPocket(st.pocket + 1) end
    if arg == SEG_PC then return setFocus("pc") end
    if arg == SEG_BAG then return setFocus("bag") end
    if arg == SORT_BUTTON then
      st.menu = { cursor = 1 }
      return se("SE_SELECT")
    end
    local name, i = "pc", arg
    if arg > BAG then name, i = "bag", arg - BAG end
    local p = st[name]
    if not p.rows[i] then return end
    if st.focus == name and p.cursor == i then return begin(false) end
    st.focus, p.cursor = name, i
    clampPane(p)
    se("SE_SELECT")
  end

  -- a drag or the wheel: the list under it (or the focused one)
  function W.scroll(dy, x)
    local p = pane()
    if x and not st.portrait then
      if x >= st.pc.x1 and x < st.pc.x2 then p = st.pc elseif x >= st.bag.x1 and x < st.bag.x2 then p = st.bag end
    end
    p.top = max(0, min(max(0, #p.rows - st.visible), p.top - dy / ROW_H))
  end

  function W.hints()
    if st.menu then return T.list(HINTS.menu) end
    if st.step then return T.list(HINTS.step) end
    return T.list(HINTS.main)
  end

  -- ------- drawing (no tables made here)

  local function drawList(p, name, x, y, w, h, focused)
    local base = name == "bag" and BAG or 0
    local clip = K.R(x, y, w, h)
    K.scissor(clip)
    local top = p.top
    local first = floor(top) + 1
    for i = first, min(#p.rows, first + st.visible + 1) do
      local row = p.rows[i]
      local ry = y + (i - 1 - top) * ROW_H
      local rb = K.R(x + 1, ry + 0.5, w - 2, ROW_H - 1)
      local on = i == p.cursor
      if on and focused then
        K.col(C.accent)
        K.box("fill", rb, 2.5)
      elseif on then
        K.col(C.wash)
        K.box("fill", rb, 2.5)
      end
      local ink = (on and focused) and K.WHITE or C.ink
      if env.itemIcon then pcall(env.itemIcon, row.id, x + 2, ry + 1, 8) end
      local qw = row.showQty and 14 or 0
      local ns = K.fit(row.name, 4.6, w - 14 - qw)
      K.text(row.name, x + 12, ry + 2.6 + (4.6 - ns) * 0.5, ns, ink)
      if row.showQty then K.text(qtyText(row.qty), x + w - 16, ry + 2.6, 4.4, ink, "right", 13) end
      K.addHit(rb, "win", base + i, clip)
    end
    if #p.rows == 0 then
      K.text(T(name == "pc" and "items.emptyPc" or "items.emptyPocket"), x, y + h / 2 - 3, 4.6, C.faint,
        "center", w)
    end
    -- the scroll bar
    if #p.rows > st.visible then
      local frac = st.visible / #p.rows
      local bh = max(6, h * frac)
      local by = y + (h - bh) * (top / max(1, #p.rows - st.visible))
      K.col(K.BLACK, 0.18)
      K.box("fill", K.R(x + w - 1.6, by, 1.2, bh), 0.6)
    end
    K.scissor(nil)
  end

  local function drawHead(name, x, y, w, focused)
    local hb = K.R(x, y, w, HEAD_H)
    K.grad(hb, 2, C.head, C.headFoot)
    if focused then
      K.col(C.accent)
      K.box("fill", K.R(x + 2, y + HEAD_H - 1.2, w - 4, 1), 0.5)
    end
    if name == "pc" then
      K.text(st.pcHead, x + 4, y + 2.4, 4.8, focused and C.accent or C.ink)
      local sb = K.R(x + w - 18, y + 1.5, 16, HEAD_H - 3)
      K.col(C.chip)
      K.box("fill", sb, 3.5)
      local sl = T("items.sort")
      K.text(sl, sb[1], sb[2] + 1.5, K.fit(sl, 4, sb[3] - 2), C.ink, "center", sb[3])
      K.addHit(sb, "win", SORT_BUTTON)
    else
      K.text("<", x + 3, y + 2.2, 5, C.soft)
      K.addHit(K.R(x, y, 12, HEAD_H), "win", POCKET_PREV)
      K.text(">", x + w - 7, y + 2.2, 5, C.soft)
      K.addHit(K.R(x + w - 12, y, 12, HEAD_H), "win", POCKET_NEXT)
      local pname = T(st.pocketKey)
      local ps = K.fit(pname, 4.8, w - 26)
      K.text(pname, x + 12, y + 2.4 + (4.8 - ps) * 0.5, ps, focused and C.accent or C.ink, "center", w - 24)
    end
  end

  local function drawFoot(x, y, w)
    local fb = K.R(x, y, w, FOOT_H)
    K.col(C.head)
    K.box("fill", fb)
    K.col(K.BLACK, 0.08)
    K.box("fill", K.R(x, y, w, 0.4))
    local sp = st.step
    if sp then
      local label = T(sp.toss and "items.tossHowMany" or "items.howMany")
      K.text(label, x + 4, y + 5.5, 4.8, C.ink)
      local bx = x + w - 4
      local go = K.R(bx - 22, y + 3, 22, 10)
      K.col(sp.toss and C.bad or C.accent)
      K.box("fill", go, 5)
      local gl = T(sp.toss and "items.toss" or "items.move")
      K.text(gl, go[1], go[2] + 2.4, K.fit(gl, 4.8, go[3] - 2), K.WHITE, "center", go[3])
      K.addHit(go, "win", STEP_GO)
      local all = K.R(go[1] - 17, y + 3, 15, 10)
      K.col(C.chip)
      K.box("fill", all, 5)
      local al = T("items.all")
      K.text(al, all[1], all[2] + 2.4, K.fit(al, 4.6, all[3] - 1), C.ink, "center", all[3])
      K.addHit(all, "win", STEP_ALL)
      local plus = K.R(all[1] - 12, y + 3, 10, 10)
      K.col(C.chip)
      K.box("fill", plus, 5)
      K.text("+", plus[1], plus[2] + 1.6, 6, C.ink, "center", plus[3])
      K.addHit(plus, "win", STEP_PLUS)
      local qx = plus[1] - 26
      K.text(stepText(sp.qty * 1000 + sp.max), qx, y + 5.3, 5, C.ink, "center", 26)
      local minus = K.R(qx - 10, y + 3, 10, 10)
      K.col(C.chip)
      K.box("fill", minus, 5)
      K.text("-", minus[1], minus[2] + 1.4, 6, C.ink, "center", minus[3])
      K.addHit(minus, "win", STEP_MINUS)
      return
    end
    local p = pane()
    local row = p.rows[p.cursor]
    if row then
      K.text(row.desc, x + 4, y + 1.8, 4.2, C.soft, "left", w - 8)
    end
  end

  local function drawMenu(body)
    local m = st.menu
    if not m then return end
    local mb = K.R(body[1] + 4, body[2] + HEAD_H + 2, 62, #MENU * 10 + 4)
    K.shadow(mb, 4, 1.2, 0.3)
    K.col(C.pane)
    K.box("fill", mb, 4)
    K.ring(mb, 4, K.BLACK, 0.12, 0.5)
    for i, key in ipairs(MENU) do
      local label = T(key)
      local rb = K.R(mb[1] + 2, mb[2] + 2 + (i - 1) * 10, mb[3] - 4, 10)
      if i == m.cursor then
        K.col(i == 3 and C.bad or C.accent)
        K.box("fill", rb, 2.5)
      end
      K.text(label, rb[1] + 4, rb[2] + 2.4, 4.8, i == m.cursor and K.WHITE or (i == 3 and C.bad or C.ink))
      K.addHit(rb, "win", MENU_ROW + i - 1)
    end
  end

  function W.draw(body, clock, portrait)
    st.portrait = portrait
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local listTop = y + HEAD_H + 1
    local listH = h - HEAD_H - 1 - FOOT_H
    st.visible = max(1, floor(listH / ROW_H))
    if portrait then
      -- the Bag | PC switch, then the one pane
      local half = (w - 8) / 2
      for k = 1, 2 do
        local name = k == 1 and "bag" or "pc"
        local sb = K.R(x + 4 + (k - 1) * half, y + 1.5, half, HEAD_H - 3)
        local on = st.focus == name
        K.col(on and C.accent or C.chip)
        K.box("fill", sb, 3.5)
        K.text(name == "pc" and st.pcHead or T("items.bag"), sb[1], sb[2] + 1.6, 4.4, on and K.WHITE or C.ink,
          "center", sb[3])
        K.addHit(sb, "win", name == "pc" and SEG_PC or SEG_BAG)
      end
      local name = st.focus
      local top = listTop
      if name == "bag" then
        drawHead("bag", x, y + HEAD_H, w, true)
        top = listTop + HEAD_H
      end
      local p = st[name]
      st.visible = max(1, floor((y + h - FOOT_H - top) / ROW_H))
      clampPane(p)
      drawList(p, name, x, top, w, y + h - FOOT_H - top, true)
      K.scissor(body)
    else
      local pw = (w - 1) / 2
      st.bag.x1, st.bag.x2 = K.X(x), K.X(x + pw)
      st.pc.x1, st.pc.x2 = K.X(x + pw + 1), K.X(x + w)
      for k = 1, 2 do
        local name = k == 1 and "bag" or "pc"
        local px = x + (k - 1) * (pw + 1)
        drawHead(name, px, y, pw, st.focus == name)
        drawList(st[name], name, px, listTop, pw, listH, st.focus == name)
        K.scissor(body)
      end
      K.col(K.BLACK, 0.1)
      K.box("fill", K.R(x + pw, y, 1, h - FOOT_H))
    end
    drawFoot(x, y + h - FOOT_H, w)
    drawMenu(body)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h - FOOT_H), C.bad, C.good, C.toastInk) then
      st.toast = nil
    end
  end

  refresh()
  return W
end
