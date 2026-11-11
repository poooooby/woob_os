-- The Mart app: the Poké Mart's goods (more as the Gym Badges come in) bought straight into the
-- Bag, the item appearing on the shelf's pad; and the Bag's items sold for half their price, the
-- item leaving off the pad. A list on the left (a strip on top in portrait), the chosen item on the
-- right: its picture, how many are in the Bag, its words, how many to buy, the total.
--   buttons  Up / Down the item, L / R the tab (Buy: Balls, Medicine, Battle, Field; Sell: the
--            Bag's pockets), START Buy | Sell, A the item (then < > one, ^ v ten, SELECT as many
--            as there are / as money buys, A buy or sell, B back), B close
--   touch    tap an item, its - / + and Buy / Sell; the Buy | Sell switch; < > the tab; drag (or
--            the wheel) scrolls the list
-- The model is src/mart.lua (env.mart); rows are made again only after a change.
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min = math.floor, math.max, math.min

local ROW_H, HEAD_H, M = 10, 10, 3
-- hit args: rows 1.., the rest below
local SEG_BUY, SEG_SELL, TAB_PREV, TAB_NEXT = 2001, 2002, 2003, 2004
local STEP_MINUS, STEP_PLUS, STEP_GO = 2010, 2011, 2012
local FLASH = 0.6

-- (the words are keys of lang/*.lua, through env.T)
local HINTS = {
  buy = { { "A", "hint.choose" }, { "L R", "hint.tab" }, { "START", "hint.sell" } },
  sell = { { "A", "hint.choose" }, { "L R", "hint.pocket" }, { "START", "hint.buy" } },
  stepBuy = { { "< >", "hint.one" }, { "^ v", "hint.ten" }, { "A", "hint.buy" }, { "B", "hint.back" } },
  stepSell = { { "< >", "hint.one" }, { "^ v", "hint.ten" }, { "A", "hint.sell" }, { "B", "hint.back" } },
}
-- (the Bag's pockets with nothing in them a Mart buys)
local NO_SELL = { KEY_ITEMS = true }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, mart, T = env.K, env.mart, env.T or NO_T
  -- (pad: the shelf's item pad lights up while the window is open)
  local W = { title = "Mart", pad = true }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local st = {
    mode = "buy", focus = "list", tab = 1, tabs = {}, sellTab = 1, pockets = {},
    rows = {}, cursor = 1, top = 0, visible = 6, qty = 1, inBag = 0,
    badges = mart.badges(session()), toast = nil, flash = -10, tabKey = "",
  }
  W.state = st

  local qtyText = K.textCache(function(n) return "×" .. tostring(n) end)
  local inBagText = K.textCache(function(n) return T.f("mart.inBag", n) end)
  local needsText = K.textCache(function(n) return n == 1 and T("mart.needsOne") or T.f("mart.needs", n) end)
  local badgeText = K.textCache(function(n) return T.f("mart.badgesShort", n) end)

  local function row() return st.rows[st.cursor] end
  local function locked(r) return st.mode == "buy" and r and (r.badges or 0) > st.badges end
  -- (keeps the chosen row in view, unless the list was scrolled by hand since the last press: a drag
  -- or the wheel would otherwise be pulled straight back to it on the next frame)
  local function clampList(follow)
    if follow then st.free = false end
    st.cursor = max(1, min(st.cursor, #st.rows))
    local vis = st.visible
    if not st.free then
      if st.cursor > st.top + vis then st.top = st.cursor - vis end
      if st.cursor <= st.top then st.top = st.cursor - 1 end
    end
    st.top = max(0, min(st.top, max(0, #st.rows - vis)))
  end
  -- how many the stepper goes up to: as many as there are to sell; 99 to buy
  local function qtyMax()
    local r = row()
    if not r then return 1 end
    if st.mode == "sell" then return max(1, r.qty or 1) end
    return mart.MAX_QTY
  end
  local function readBag()
    local r = row()
    st.inBag = r and mart.inBag(session(), r.id) or 0
  end
  local function refresh()
    local s = session()
    if st.mode == "buy" then
      st.tabs = mart.tabs()
      st.tab = max(1, min(st.tab, #st.tabs))
      local t = st.tabs[st.tab]
      st.rows = t and t.rows or {}
      st.tabKey = t and t.key or "app.mart"
    else
      local pockets = {}
      for _, p in ipairs(env.inv and env.inv.pockets(s) or {}) do
        if not NO_SELL[p.id] then pockets[#pockets + 1] = p end
      end
      st.pockets = pockets
      st.sellTab = max(1, min(st.sellTab, #pockets))
      local p = pockets[st.sellTab]
      st.rows = p and mart.sellRows(s, p.id) or {}
      st.tabKey = p and ("pocket." .. p.id) or "items.bag"
    end
    clampList(true)
    st.qty = max(1, min(st.qty, qtyMax()))
    readBag()
  end
  W.refresh = refresh

  local function toast(text, bad, sound)
    st.toast = { text = text, bad = bad, t = now() }
    se(sound or (bad and "SE_FAILURE" or "SE_SELECT"))
  end

  local function setCursor(c)
    c = max(1, min(#st.rows, c))
    if c ~= st.cursor and #st.rows > 0 then
      st.cursor, st.qty, st.focus = c, 1, "list"
      clampList(true)
      readBag()
      se("SE_SELECT")
    end
  end
  local function setTab(i)
    local n = st.mode == "buy" and #st.tabs or #st.pockets
    if n == 0 then return end
    i = (i - 1) % n + 1
    local cur = st.mode == "buy" and st.tab or st.sellTab
    if i == cur then return end
    if st.mode == "buy" then st.tab = i else st.sellTab = i end
    st.cursor, st.top, st.qty, st.focus = 1, 0, 1, "list"
    refresh()
    se("SE_SELECT")
  end
  local function setMode(mode)
    if st.mode == mode then return end
    st.mode, st.cursor, st.top, st.qty, st.focus = mode, 1, 0, 1, "list"
    refresh()
    se("SE_SELECT")
  end
  local function stepBy(d)
    local q = max(1, min(qtyMax(), st.qty + d))
    if q ~= st.qty then
      st.qty = q
      se("SE_SELECT")
    end
  end
  -- SELECT in the stepper: all of them (selling), as many as the money buys (buying)
  local function stepAll()
    local r = row()
    if not r then return end
    if st.mode == "sell" then
      st.qty = qtyMax()
    else
      st.qty = max(1, min(mart.MAX_QTY, floor(mart.money(session()) / max(1, r.price))))
    end
    se("SE_SELECT")
  end

  -- buy or sell st.qty of the chosen item
  local function act()
    local r = row()
    if not r then return end
    local s = session()
    if locked(r) then return toast(needsText(r.badges), true) end
    if st.mode == "buy" then
      local ok, got = mart.buy(s, r.id, st.qty, st.badges)
      if not ok then
        if got == "money" then st.flash = now() end
        return toast(T(got and ("reason.mart." .. got) or "failed"), true)
      end
      -- (it appears on the pad, then goes up into the Bag)
      if env.pad and env.pad.transfer then pcall(env.pad.transfer, r.id, "in") end
      local what = r.name .. " ×" .. st.qty
      toast(got and T.f("mart.boughtBonus", what) or T.f("mart.bought", what), false, "SE_SHOP")
    else
      local ok, got = mart.sell(s, r.id, st.qty)
      if not ok then return toast(T(got and ("reason.mart." .. got) or "failed"), true) end
      if env.pad and env.pad.transfer then pcall(env.pad.transfer, r.id, "out") end
      toast(T.f("mart.sold", r.name .. " ×" .. st.qty, tostring(got)), false, "SE_SHOP")
    end
    st.qty, st.focus = 1, "list"
    refresh()
  end
  -- A on an item: how many (a locked or unsellable one says why)
  local function begin()
    local r = row()
    if not r then return end
    if locked(r) then return toast(needsText(r.badges), true) end
    if st.mode == "sell" and not r.price then return toast(T("reason.mart.cant_sell"), true) end
    st.focus = "step"
    se("SE_SELECT")
  end

  -- ------- buttons

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
    if st.focus == "step" then
      if nav.right then stepBy(1)
      elseif nav.left then stepBy(-1)
      elseif nav.up then stepBy(10)
      elseif nav.down then stepBy(-10)
      elseif pressed("select") then stepAll()
      elseif pressed("a") then act()
      elseif pressed("b") then
        st.focus = "list"
        se("SE_SELECT")
      end
      return true
    end
    if pressed("b") then return false end
    if nav.up then setCursor(st.cursor - 1)
    elseif nav.down then setCursor(st.cursor + 1)
    elseif pressed("l") then setTab((st.mode == "buy" and st.tab or st.sellTab) - 1)
    elseif pressed("r") then setTab((st.mode == "buy" and st.tab or st.sellTab) + 1)
    elseif pressed("start") then setMode(st.mode == "buy" and "sell" or "buy")
    elseif pressed("a") then begin()
    end
    return true
  end

  function W.tap(arg)
    if type(arg) ~= "number" then return end
    if arg == SEG_BUY then return setMode("buy") end
    if arg == SEG_SELL then return setMode("sell") end
    if arg == TAB_PREV then return setTab((st.mode == "buy" and st.tab or st.sellTab) - 1) end
    if arg == TAB_NEXT then return setTab((st.mode == "buy" and st.tab or st.sellTab) + 1) end
    if arg == STEP_MINUS or arg == STEP_PLUS then
      local r = row()
      if not r or locked(r) or (st.mode == "sell" and not r.price) then return end
      st.focus = "step"
      return stepBy(arg == STEP_PLUS and 1 or -1)
    end
    if arg == STEP_GO then return act() end
    if st.rows[arg] then
      if st.cursor == arg then
        if st.focus == "list" then return begin() end
        return
      end
      setCursor(arg)
    end
  end

  function W.scroll(dy)
    st.free = true
    st.top = max(0, min(max(0, #st.rows - st.visible), st.top - dy / ROW_H))
  end

  function W.hints()
    if st.focus == "step" then return T.list(st.mode == "buy" and HINTS.stepBuy or HINTS.stepSell) end
    return T.list(st.mode == "buy" and HINTS.buy or HINTS.sell)
  end

  -- ------- drawing (no tables made here)

  local UI = K.UI

  -- the money, right-aligned at x (the game's Pokédollar sign before it) -> its width
  local function money(n, x, y, size, c)
    if not env.amount then return 0 end
    local ok, w = pcall(env.amount, n, 0, 0, size, c, true)
    w = ok and tonumber(w) or 0
    pcall(env.amount, n, x - w, y, size, c)
    return w
  end

  -- a small padlock, `s` units tall, its top left at x, y
  local function padlock(x, y, s, c)
    local G = K.graphics()
    K.col(c)
    K.box("fill", K.R(x, y + s * 0.42, s * 0.8, s * 0.58), s * 0.12)
    G.setLineWidth(max(1, s * 0.13 * K.sc))
    G.arc("line", "open", K.X(x + s * 0.4), K.Y(y + s * 0.42), s * 0.26 * K.sc, math.pi, math.pi * 2)
  end

  local function drawList(x, y, w, h, focused)
    local clip = K.R(x, y, w, h)
    K.scissor(clip)
    local top = st.top
    local first = floor(top) + 1
    local last = min(#st.rows, first + st.visible + 1)
    local sell = st.mode == "sell"
    for i = first, last do
      local r = st.rows[i]
      local ry = y + (i - 1 - top) * ROW_H
      local rb = K.R(x + 1.5, ry + 0.4, w - 3, ROW_H - 0.8)
      local on = i == st.cursor
      if on then
        K.selection(rb, focused)
      elseif i < #st.rows and i + 1 ~= st.cursor then
        K.hairline(x + 13, ry + ROW_H - 0.1, w - 15)
      end
      local white = on and focused
      local off = locked(r) or (sell and not r.price)
      local ink = white and K.WHITE or (off and UI.tertiary or UI.label)
      local soft = white and K.WHITE or UI.secondary
      if env.itemIcon then pcall(env.itemIcon, r.id, x + 3, ry + 1, 8, off and 0.45 or 1) end
      local rw = 0
      if locked(r) then
        local bt = badgeText(r.badges)
        rw = K.width(bt, 4.2) + 6
        K.text(bt, x + w - 4 - rw + 5, ry + 2.9, 4.2, soft)
        padlock(x + w - 4 - rw, ry + 2.6, 4, soft)
      elseif r.price then
        rw = money(r.price, x + w - 4, ry + 2.7, 4.4, soft)
      end
      if sell then
        local qt = qtyText(r.qty)
        local qw = K.width(qt, 4.2)
        K.text(qt, x + w - 7 - rw - qw, ry + 2.9, 4.2, soft)
        rw = rw + qw + 3
      end
      local ns = K.fit(r.name, 4.6, w - 18 - rw)
      K.text(r.name, x + 13, ry + 2.6 + (4.6 - ns) * 0.5, ns, ink)
      K.addHit(rb, "win", i, clip)
    end
    if #st.rows == 0 then
      K.text(T(sell and "items.emptyPocket" or "mart.soldOut"), x, y + h / 2 - 3, 4.6, UI.tertiary, "center", w)
    end
    K.scrollbar(x + w, y, h, top, st.visible, #st.rows)
    K.scissor(nil)
  end

  -- the list's card: the tab between two chevrons, the rows
  local function drawListPane(x, y, w, h, focused)
    K.card(K.R(x, y, w, h), 4)
    K.chevron(x + 5, y + HEAD_H / 2 + 0.3, 4, UI.accent, -1)
    K.addHit(K.R(x, y, 12, HEAD_H), "win", TAB_PREV)
    K.chevron(x + w - 5, y + HEAD_H / 2 + 0.3, 4, UI.accent, 1)
    K.addHit(K.R(x + w - 12, y, 12, HEAD_H), "win", TAB_NEXT)
    local name = T(st.tabKey)
    local ns = K.fit(name, 4.8, w - 26)
    K.bold(name, x + 12, y + 2.6 + (4.8 - ns) * 0.5, ns, UI.label, "center", w - 24)
    K.hairline(x, y + HEAD_H, w)
    local top = y + HEAD_H + 0.5
    st.visible = max(1, floor((y + h - 1 - top) / ROW_H))
    clampList()
    drawList(x, top, w, y + h - 1 - top, focused)
  end

  -- the chosen item: its picture, name and count; its words when there's room; how many, the
  -- total and Buy / Sell at the foot (or why it can't be had)
  local function drawDetail(x, y, w, h, clock)
    K.card(K.R(x, y, w, h), 4)
    local r = row()
    if not r then return end
    local big = h >= 60
    local is = big and 16 or 12
    if env.itemIcon then pcall(env.itemIcon, r.id, x + 4, y + 3, is) end
    local tx = x + is + 7
    local ns = K.fit(r.name, 5, w - (tx - x) - 4)
    K.bold(r.name, tx, y + 4 + (5 - ns) * 0.5, ns, UI.label)
    K.text(inBagText(st.inBag), tx, y + 10.5, 4.2, UI.secondary)
    if big and r.desc ~= "" then
      K.scissor(K.R(x, y + is + 6, w, h - is - 6 - 28))
      K.text(r.desc, x + 4, y + is + 6, 4.2, UI.secondary, "left", w - 8)
      K.scissor(nil)
    end
    local go = K.R(x + 4, y + h - 13, w - 8, 10)
    local sell = st.mode == "sell"
    local stepping = st.focus == "step"
    if locked(r) then
      padlock(x + 4, y + h - 25.5, 4.4, UI.red)
      K.text(needsText(r.badges), x + 10, y + h - 25.5, 4.2, UI.red, "left", w - 14)
      K.button(go, T("mart.buy"), "gray", false, 4.8)
      return
    end
    if sell and not r.price then
      K.text(T("reason.mart.cant_sell"), x + 4, y + h - 25.5, 4.2, UI.secondary, "left", w - 8)
      K.button(go, T("mart.sell"), "gray", false, 4.8)
      return
    end
    -- (the stepper: minus | plus in one capsule, how many after it, the total on the right)
    local sb = K.R(x + 4, y + h - 27, 22, 10)
    K.col(UI.fill)
    K.box("fill", sb, 3.2)
    K.vline(sb[1] + 11, sb[2] + 2.2, 5.6, UI.tertiary)
    K.text("-", sb[1], sb[2] + 1.4, 6, UI.label, "center", 11)
    K.text("+", sb[1] + 11, sb[2] + 1.6, 6, UI.label, "center", 11)
    K.addHit(K.R(sb[1], sb[2], 11, 10), "win", STEP_MINUS)
    K.addHit(K.R(sb[1] + 11, sb[2], 11, 10), "win", STEP_PLUS)
    if stepping then K.focusRing(sb, 3.2) end
    K.bold(qtyText(st.qty), sb[1] + 25, sb[2] + 2.6, 5, UI.label)
    local total = (r.price or 0) * st.qty
    local short = not sell and total > mart.money(session())
    money(total, x + w - 4, sb[2] + 2.6, 5, short and UI.red or UI.label)
    K.button(go, T(sell and "mart.sell" or "mart.buy"), short and "gray" or "accent", stepping, 4.8)
    K.addHit(go, "win", STEP_GO)
  end

  -- the head: Buy | Sell, the money on the right (red a moment when it falls short)
  local function drawHead(x, y, w)
    local segW = min(56, w * 0.45)
    K.segmented(x, y + 1, segW, HEAD_H - 2.5, st.mode == "buy" and 1 or 2, "win",
      SEG_BUY, T("mart.buy"), SEG_SELL, T("mart.sell"))
    local flash = now() - st.flash < FLASH
    money(mart.money(session()), x + w - 1, y + 2.4, 5, flash and UI.red or UI.label)
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    drawHead(x + M, y + 1, w - M * 2)
    local top = y + HEAD_H + 1.5
    local focused = st.focus == "list"
    if portrait then
      local dh = min(44, (y + h - M - top) * 0.45)
      local lh = y + h - M - top - dh - M
      drawListPane(x + M, top, w - M * 2, lh, focused)
      K.scissor(body)
      drawDetail(x + M, top + lh + M, w - M * 2, dh, clock)
    else
      local lw = floor((w - M * 3) * 0.55)
      drawListPane(x + M, top, lw, y + h - M - top, focused)
      K.scissor(body)
      drawDetail(x + M * 2 + lw, top, w - M * 3 - lw, y + h - M - top, clock)
    end
    K.scissor(body)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), UI.red, UI.green, UI.hud) then
      st.toast = nil
    end
  end

  refresh()
  return W
end
