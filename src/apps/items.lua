-- The Items app: the Bag and the PC's item storage side by side, a commander. The focused pane's
-- item goes across to the other: A (a stepper for how many when there's more than one), SELECT the
-- whole stack. Landscape: Bag | PC; portrait: one pane at a time under a Bag | PC switch.
--   buttons  Left / Right the pane, Up / Down the item, L / R the Bag's pocket, A move, SELECT move
--            all, START the menu for the pane in focus (the PC: sort, toss; the Bag: sort the
--            pocket), B close
--   stepper  Left / Right one more or less, Up / Down ten, A move, B back
--   touch    tap an item, tap it again to move it; the stepper's - / + / All / Move; < > the pocket;
--            Sort on either pane's head; drag (or the wheel) scrolls a list
-- The model is src/inventory.lua (env.inv); rows are made again only after a change.
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min = math.floor, math.max, math.min

local ROW_H, HEAD_H, FOOT_H = 10, 10, 16
-- hit args: PC rows 1.., Bag rows BAG + i, the rest below
local BAG = 1000
local POCKET_PREV, POCKET_NEXT, SEG_PC, SEG_BAG = 2001, 2002, 2003, 2004
local STEP_MINUS, STEP_PLUS, STEP_ALL, STEP_GO, STEP_BACK = 2010, 2011, 2012, 2013, 2014
local MENU_ROW, SORT_BUTTON, SORT_BAG = 2020, 2030, 2031

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
      refresh()
      toast(T(i == 1 and "items.sortedName" or "items.sortedType"))
    elseif i == TOSS then
      st.focus = "pc"
      begin(true)
    else
      inv.sort(s, i == 1 and "name" or "pocket")
      st.pc.cursor, st.pc.top = 1, 0
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
    st.step = nil
    if arg == POCKET_PREV then return setPocket(st.pocket - 1) end
    if arg == POCKET_NEXT then return setPocket(st.pocket + 1) end
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

  local UI = K.UI

  -- a pane's rows inside its card (x, y, w, h: the list's room); the highlight inset, the rows
  -- parted by hairlines from the name on
  local function drawList(p, name, x, y, w, h, focused)
    local base = name == "bag" and BAG or 0
    local clip = K.R(x, y, w, h)
    K.scissor(clip)
    local top = p.top
    local first = floor(top) + 1
    local last = min(#p.rows, first + st.visible + 1)
    for i = first, last do
      local row = p.rows[i]
      local ry = y + (i - 1 - top) * ROW_H
      local rb = K.R(x + 1.5, ry + 0.4, w - 3, ROW_H - 0.8)
      local on = i == p.cursor
      if on then
        K.selection(rb, focused)
      elseif i < #p.rows and i + 1 ~= p.cursor then
        K.hairline(x + 13, ry + ROW_H - 0.1, w - 15)
      end
      local ink = (on and focused) and K.WHITE or UI.label
      if env.itemIcon then pcall(env.itemIcon, row.id, x + 3, ry + 1, 8) end
      local qw = row.showQty and 14 or 0
      local ns = K.fit(row.name, 4.6, w - 16 - qw)
      K.text(row.name, x + 13, ry + 2.6 + (4.6 - ns) * 0.5, ns, ink)
      if row.showQty then
        K.text(qtyText(row.qty), x + w - 17, ry + 2.6, 4.4, (on and focused) and K.WHITE or UI.secondary, "right", 13)
      end
      K.addHit(rb, "win", base + i, clip)
    end
    if #p.rows == 0 then
      K.text(T(name == "pc" and "items.emptyPc" or "items.emptyPocket"), x, y + h / 2 - 3, 4.6, UI.tertiary,
        "center", w)
    end
    K.scrollbar(x + w, y, h, top, st.visible, #p.rows)
    K.scissor(nil)
  end

  -- a card's head: the Bag's pocket between two chevrons, or the PC's count; each with its Sort button
  local function drawHead(name, x, y, w, focused)
    st[name].hx = x
    local sb = K.R(x + w - 19, y + 1.8, 16, HEAD_H - 3.4)
    K.button(sb, T("items.sort"), "tinted", false, 4)
    K.addHit(sb, "win", name == "pc" and SORT_BUTTON or SORT_BAG)
    if name == "pc" then
      K.bold(st.pcHead, x + 4, y + 2.6, 4.8, UI.label)
    else
      local rw = w - 21
      K.chevron(x + 5, y + HEAD_H / 2 + 0.3, 4, UI.accent, -1)
      K.addHit(K.R(x, y, 12, HEAD_H), "win", POCKET_PREV)
      K.chevron(x + rw - 5, y + HEAD_H / 2 + 0.3, 4, UI.accent, 1)
      K.addHit(K.R(x + rw - 12, y, 12, HEAD_H), "win", POCKET_NEXT)
      local pname = T(st.pocketKey)
      local ps = K.fit(pname, 4.8, rw - 26)
      K.bold(pname, x + 12, y + 2.6 + (4.8 - ps) * 0.5, ps, UI.label, "center", rw - 24)
    end
    K.hairline(x, y + HEAD_H, w)
  end

  -- a pane: the card, its head, its rows
  local function drawPane(name, x, y, w, h, focused, head)
    K.card(K.R(x, y, w, h), 4)
    local top = y
    if head then
      drawHead(name, x, y, w, focused)
      top = y + HEAD_H + 0.5
    end
    local p = st[name]
    st.visible = max(1, floor((y + h - 1 - top) / ROW_H))
    clampPane(p)
    drawList(p, name, x, top, w, y + h - 1 - top, focused)
  end

  -- the foot: the item's words, or how many (a stepper, All, Move / Toss)
  local function drawFoot(x, y, w)
    local sp = st.step
    if sp then
      local label = T(sp.toss and "items.tossHowMany" or "items.howMany")
      K.text(label, x + 4, y + 5.5, 4.8, UI.label)
      local go = K.R(x + w - 26, y + 3, 22, 10)
      K.button(go, T(sp.toss and "items.toss" or "items.move"), sp.toss and "danger" or "accent", false, 4.8)
      K.addHit(go, "win", STEP_GO)
      local all = K.R(go[1] - 18, y + 3, 16, 10)
      K.button(all, T("items.all"), "gray", false, 4.6)
      K.addHit(all, "win", STEP_ALL)
      -- (the stepper: minus | plus in one capsule, the count before it)
      local sb = K.R(all[1] - 24, y + 3, 22, 10)
      K.col(UI.fill)
      K.box("fill", sb, 3.2)
      K.vline(sb[1] + 11, sb[2] + 2.2, 5.6, UI.tertiary)
      K.text("-", sb[1], sb[2] + 1.4, 6, UI.label, "center", 11)
      K.text("+", sb[1] + 11, sb[2] + 1.6, 6, UI.label, "center", 11)
      K.addHit(K.R(sb[1], sb[2], 11, 10), "win", STEP_MINUS)
      K.addHit(K.R(sb[1] + 11, sb[2], 11, 10), "win", STEP_PLUS)
      K.bold(stepText(sp.qty * 1000 + sp.max), sb[1] - 28, y + 5.3, 5, UI.label, "center", 26)
      return
    end
    local p = pane()
    local row = p.rows[p.cursor]
    if row then
      K.text(row.desc, x + 5, y + 1.6, 4.2, UI.secondary, "left", w - 10)
    end
  end

  -- START's menu: a popover under the head of the pane it's for
  local function drawMenu(body)
    local m = st.menu
    if not m then return end
    local list = m.list
    local px = st[m.pane].hx or body[1]
    local mb = K.R(max(body[1] + 2, min(px + 2, body[1] + body[3] - 66)), body[2] + HEAD_H + 4, 64, #list * 10 + 4)
    K.sheet(mb, 4)
    for i, key in ipairs(list) do
      local label = T(key)
      local rb = K.R(mb[1] + 2, mb[2] + 2 + (i - 1) * 10, mb[3] - 4, 10)
      local danger = m.pane == "pc" and i == TOSS
      if i == m.cursor then
        K.selection(rb, true, 2.5, danger and UI.red or UI.accent)
      end
      if danger and i > 1 then K.hairline(rb[1] + 2, rb[2] - 0.1, rb[3] - 4) end
      K.text(label, rb[1] + 4, rb[2] + 2.4, 4.8, i == m.cursor and K.WHITE or (danger and UI.red or UI.label))
      K.addHit(rb, "win", MENU_ROW + i - 1)
    end
  end

  local M = 3
  function W.draw(body, clock, portrait)
    st.portrait = portrait
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local paneH = h - FOOT_H - M
    if portrait then
      -- the Bag | PC switch, then the one pane
      K.segmented(x + M, y + 2, w - M * 2, HEAD_H - 2.5, st.focus == "bag" and 1 or 2, "win",
        SEG_BAG, T("items.bag"), SEG_PC, st.pcHead)
      local name = st.focus
      local top = y + HEAD_H + 1
      drawPane(name, x + M, top, w - M * 2, y + paneH - top, true, name == "bag")
      K.scissor(body)
    else
      local pw = (w - M * 3) / 2
      st.bag.x1, st.bag.x2 = K.X(x), K.X(x + M + pw + M / 2)
      st.pc.x1, st.pc.x2 = K.X(x + M + pw + M / 2), K.X(x + w)
      for k = 1, 2 do
        local name = k == 1 and "bag" or "pc"
        drawPane(name, x + M + (k - 1) * (pw + M), y + M, pw, paneH - M, st.focus == name, true)
        K.scissor(body)
      end
    end
    drawFoot(x, y + h - FOOT_H, w)
    drawMenu(body)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h - FOOT_H), UI.red, UI.green, UI.hud) then
      st.toast = nil
    end
  end

  refresh()
  return W
end
