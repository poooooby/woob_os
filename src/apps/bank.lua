-- The Bank (the model is src/bank.lua, env.bank): a bank card with what's kept and the wallet beside
-- it, Deposit | Withdraw with an amount (a digit at a time on the buttons, or the chips: +1,000,
-- +10,000, +100,000, All), the button, and the latest activity (deposits, withdrawals, the wallet's
-- overflow, interest).
--   buttons  L / R (or START) Deposit | Withdraw, Left / Right the digit, Up / Down it, SELECT all,
--            A the button, B close
--   touch    the tabs, the chips, Clear, the button; drag (or the wheel) scrolls the activity
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, sin = math.floor, math.max, math.min, math.sin

local M = 3
local TAB_IN, TAB_OUT, CHIP, CLEAR, GO = 2001, 2002, 2010, 2020, 2021
local CHIPS = { 1000, 10000, 100000 }
local ROW_H = 11
local HINTS = {
  main = { { "L R", "hint.tab" }, { "< >", "bank.hint.digit" }, { "^ v", "bank.hint.amount" }, { "SELECT", "hint.all" },
           { "A", "hint.ok" }, { "B", "hint.close" } },
}
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, Bk, T = env.K, env.bank, env.T or NO_T
  local UI = K.UI
  local W = { title = T("app.bank") }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local st = { mode = "in", amount = 0, place = 0, keys = false, top = 0, visible = 4, toast = nil, flash = -10 }
  W.state = st
  ctx.resume = nil

  local function commas(n)
    local s = tostring(floor(n))
    repeat
      local k
      s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return s
  end
  local upToText = K.textCache(function(n) return T.f("bank.upTo", commas(n)) end)
  local agoText = K.textCache(function(m)
    if m < 1 then return T("notify.now") end
    if m < 60 then return T.f("notify.minutes", m) end
    if m < 1440 then return T.f("notify.hours", floor(m / 60)) end
    return T.f("notify.days", floor(m / 1440))
  end)
  -- (where a place's digit starts in the amount, at size 10: made once per amount and place)
  local placeAt = K.textCache(function(key)
    local n, p = floor(key / 16), key % 16
    local txt = commas(n)
    local seen, i = 0, #txt
    while i >= 1 do
      if txt:sub(i, i) ~= "," then
        if seen == p then return K.width(txt:sub(1, i - 1), 10) end
        seen = seen + 1
      end
      i = i - 1
    end
    return -K.width("0", 10) * (p - seen + 1)
  end)
  local KIND = { ["in"] = "bank.kind.in", out = "bank.kind.out", over = "bank.kind.over", interest = "bank.kind.interest" }
  local chipText = {}
  for i, v in ipairs(CHIPS) do chipText[i] = "+" .. commas(v) end

  -- the most this way: the wallet's money (and the bank's room) in, the bank's (and the wallet's room) out
  local function most()
    local s = session()
    if st.mode == "in" then return min(max(0, floor(tonumber(s and s.money) or 0)), Bk.MAX - Bk.balance()) end
    return min(Bk.balance(), Bk.room(s))
  end
  local function setAmount(n)
    st.amount = max(0, min(floor(n), most()))
  end
  local function setMode(m)
    if st.mode == m then return end
    st.mode, st.amount, st.place = m, 0, 0
    se("SE_SELECT")
  end
  local function toast(text, bad)
    st.toast = { text = text, bad = bad, t = now() }
  end
  local function go()
    local s = session()
    if st.amount <= 0 then
      se("SE_FAILURE")
      return toast(T("reason.bank.none"), true)
    end
    local ok, moved
    if st.mode == "in" then ok, moved = Bk.deposit(s, st.amount) else ok, moved = Bk.withdraw(s, st.amount) end
    if not ok then
      se("SE_FAILURE")
      return toast(T("reason.bank." .. tostring(moved)), true)
    end
    se("SE_SHOP")
    st.amount, st.flash, st.burst = 0, now(), { t = now(), out = st.mode == "out" }
    toast(T.f(st.mode == "in" and "bank.didIn" or "bank.didOut", commas(moved)), false)
  end

  -- the interest due since the last visit, paid on opening
  do
    local s = session()
    if s then
      local paid = Bk.settle(s)
      if paid > 0 then toast(T.f("bank.interestPaid", commas(paid)), false) end
    end
  end

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
    if pressed("b") then return false end
    if pressed("l") or pressed("r") or pressed("start") then
      setMode(st.mode == "in" and "out" or "in")
      return true
    end
    if nav.left or nav.right or nav.up or nav.down then
      if not st.keys then
        st.keys = true
        se("SE_SELECT")
        return true
      end
      local digits = #tostring(max(1, most()))
      if nav.left then st.place = min(digits - 1, st.place + 1)
      elseif nav.right then st.place = max(0, st.place - 1)
      elseif nav.up then setAmount(st.amount + 10 ^ st.place)
      elseif nav.down then setAmount(st.amount - 10 ^ st.place) end
      se("SE_SELECT")
    elseif pressed("select") then
      setAmount(most())
      se("SE_SELECT")
    elseif pressed("a") then
      go()
    end
    return true
  end

  function W.tap(arg)
    st.keys = false
    if arg == TAB_IN then return setMode("in") end
    if arg == TAB_OUT then return setMode("out") end
    if arg == GO then return go() end
    if arg == CLEAR then
      st.amount = 0
      return se("SE_SELECT")
    end
    if type(arg) == "number" and arg > CHIP and arg <= CHIP + #CHIPS + 1 then
      local i = arg - CHIP
      if i > #CHIPS then setAmount(most()) else setAmount(st.amount + CHIPS[i]) end
      se("SE_SELECT")
    end
  end

  function W.scroll(dy)
    st.top = max(0, min(max(0, #Bk.log() - st.visible), st.top - dy / ROW_H))
  end

  function W.hints() return T.list(HINTS.main) end

  -- ------- drawing (no tables made here)

  -- a private bank at night: deep green glass, mint light, gold
  local BG_TOP, BG_FOOT = { 10, 44, 44 }, { 3, 14, 20 }
  local CARD_TOP, CARD_FOOT = { 34, 190, 146 }, { 8, 78, 84 }
  local GOLD, GOLD_FOOT = { 255, 222, 128 }, { 196, 146, 44 }
  local MINT, MINT_DEEP = { 110, 240, 196 }, { 24, 170, 130 }
  local WHITE, SOFT, FAINT = { 255, 255, 255 }, { 196, 226, 218 }, { 118, 160, 152 }
  local GLASS, EDGE = { 255, 255, 255, 0.06 }, { 255, 255, 255, 0.1 }
  local IN_C, OUT_C, OVER_C, RATE_C = { 110, 240, 196 }, { 255, 150, 120 }, { 255, 214, 110 }, { 150, 190, 255 }
  local BTN_TOP, BTN_FOOT, BTN_OFF = { 70, 230, 170 }, { 18, 150, 112 }, { 255, 255, 255, 0.08 }
  local COINS = 9

  local function money(n, x, y, size, c, right)
    if not env.amount then return 0 end
    local ok, w = pcall(env.amount, n, 0, 0, size, c, true)
    w = ok and tonumber(w) or 0
    pcall(env.amount, n, right and x - w or x, y, size, c)
    return w
  end
  local function measure(n, size)
    if not env.amount then return 0 end
    local ok, w = pcall(env.amount, n, 0, 0, size, WHITE, true)
    return ok and tonumber(w) or 0
  end
  local function glass(b, rad)
    K.col(GLASS)
    K.box("fill", b, rad)
    K.ring(b, rad, EDGE, 1, 0.4)
  end
  local function ease(k) k = min(1, max(0, k)) return 1 - (1 - k) * (1 - k) * (1 - k) end

  -- the bank card: deep green, a sheen sweeping across now and then, the gold chip, contactless
  -- waves, the balance counting to what it is
  local function drawCard(x, y, w, h, clock)
    local G = K.graphics()
    local b = K.R(x, y, w, h)
    K.glow(x + w / 2, y + h * 0.7, w * 0.6, h * 0.7, MINT_DEEP, 0.22)
    K.shadow(b, 6, 2, 0.45)
    K.grad(b, 6, CARD_TOP, CARD_FOOT)
    -- (the card's pattern: two large soft circles; the sheen, a band across it every few seconds)
    K.scissor(b)
    K.col(WHITE, 0.07)
    G.circle("fill", K.X(x + w * 0.88), K.Y(y + h * 0.1), h * 0.75 * K.sc)
    K.col(WHITE, 0.05)
    G.circle("fill", K.X(x + w * 0.72), K.Y(y + h * 1.05), h * 0.6 * K.sc)
    local p = (clock * 0.28) % 1.6
    if p < 1 then
      local sx = x - w * 0.3 + p * w * 1.6
      K.col(WHITE, 0.16 * math.sin(p * math.pi))
      G.polygon("fill", K.X(sx), K.Y(y), K.X(sx + w * 0.12), K.Y(y), K.X(sx - w * 0.06), K.Y(y + h), K.X(sx - w * 0.18), K.Y(y + h))
    end
    K.scissor(st.clip)
    -- (the chip, the waves)
    local cb = K.R(x + 5, y + 11, 10, 7)
    K.grad(cb, 1.8, GOLD, GOLD_FOOT)
    K.col(GOLD_FOOT, 0.8)
    K.box("fill", K.R(cb[1], cb[2] + 3.3, cb[3], 0.35))
    K.box("fill", K.R(cb[1] + 4.8, cb[2], 0.35, cb[4]))
    G.setLineWidth(max(1, 0.45 * K.sc))
    for i = 1, 3 do
      K.col(WHITE, 0.55 - i * 0.12)
      G.arc("line", "open", K.X(x + 17.5), K.Y(y + 14.5), (1.2 + i * 1.1) * K.sc, -0.7, 0.7, 10)
    end
    K.bold(T("bank.name"), x + 5, y + 4.5, 4.4, WHITE)
    K.text(T("bank.balance"), x + 5, y + h - 15.5, 3.4, SOFT)
    -- (the balance, counting up to what it is)
    local target = Bk.balance()
    local dt = st.lastT and min(0.1, max(0, now() - st.lastT)) or 0
    st.lastT = now()
    st.shown = st.shown and (st.shown + (target - st.shown) * min(1, dt * 6)) or target
    if math.abs(target - st.shown) < 1 then st.shown = target end
    local pulse = max(0, 1 - (now() - st.flash) / 0.6)
    local size = K.fit("000,000,000", 8, w - 10) * (1 + 0.08 * pulse)
    money(floor(st.shown + 0.5), x + 5, y + h - 11, size, WHITE)
    st.cardX, st.cardY = x + w * 0.5, y + h * 0.5
  end

  -- the wallet: a ring for how full, what's in it, its cap
  local function drawWallet(x, y, w, clock)
    local G = K.graphics()
    local b = K.R(x, y, w, 15)
    glass(b, 4)
    local s = session()
    local m = max(0, floor(tonumber(s and s.money) or 0))
    local cap = Bk.wallet()
    local k = min(1, m / max(1, cap))
    local cx, cy, r = x + 8, y + 7.5, 4.6
    G.setLineWidth(max(1, 1.3 * K.sc))
    K.col(WHITE, 0.1)
    G.circle("line", K.X(cx), K.Y(cy), r * K.sc)
    K.col(k >= 1 and OVER_C or MINT)
    if k > 0 then G.arc("line", "open", K.X(cx), K.Y(cy), r * K.sc, -math.pi / 2, -math.pi / 2 + 2 * math.pi * k, 32) end
    if k >= 1 then
      K.col(OVER_C, 0.25 + 0.2 * math.sin(clock * 4))
      G.circle("fill", K.X(cx), K.Y(cy), (r - 1.4) * K.sc)
    end
    K.text(T("bank.wallet"), x + 16, y + 2.4, 3.4, FAINT)
    money(m, x + 16, y + 7, 4.8, WHITE)
    st.walletX, st.walletY = cx, cy
  end

  -- Deposit | Withdraw: a pill, its light sliding to the chosen side
  local function drawSwitch(x, y, w, h, clock)
    local b = K.R(x, y, w, h)
    K.col(WHITE, 0.07)
    K.box("fill", b, h / 2)
    local want = st.mode == "in" and 0 or 1
    local dt = st.swT and min(0.1, max(0, now() - st.swT)) or 0
    st.swT = now()
    st.swK = (st.swK or want) + (want - (st.swK or want)) * min(1, dt * 12)
    local half = (w - 1) / 2
    local hb = K.R(x + 0.5 + half * st.swK, y + 0.5, half, h - 1)
    K.grad(hb, (h - 1) / 2, BTN_TOP, BTN_FOOT)
    local l1, l2 = T("bank.deposit"), T("bank.withdraw")
    K.bold(l1, x, y + (h - 4.2 * 1.2) / 2, K.fit(l1, 4.2, half - 3), st.mode == "in" and BG_FOOT or SOFT, "center", half)
    K.bold(l2, x + half, y + (h - 4.2 * 1.2) / 2, K.fit(l2, 4.2, half - 3), st.mode == "out" and BG_FOOT or SOFT, "center", half)
    K.addHit(K.R(x, y, half, h), "win", TAB_IN)
    K.addHit(K.R(x + half, y, half, h), "win", TAB_OUT)
  end

  local function drawAmount(x, y, w, clock)
    drawSwitch(x, y, w, 9, clock)
    local ab = K.R(x, y + 11, w, 22)
    glass(ab, 5)
    K.glow(x + w / 2, y + 21, w * 0.45, 9, MINT_DEEP, 0.18)
    local size = K.fit("000,000,000", 8.5, w - 18)
    -- (a change bumps it a little)
    if st.amount ~= st.lastAmount then st.lastAmount, st.bumpAt = st.amount, now() end
    local bump = max(0, 1 - (now() - (st.bumpAt or -10)) / 0.25)
    local s2 = size * (1 + 0.07 * bump)
    local aw = measure(st.amount, s2)
    local ax = x + (w - aw) / 2
    money(st.amount, ax, y + 14 - (s2 - size) * 0.6, s2, st.amount > 0 and WHITE or FAINT)
    st.amountX, st.amountY = x + w / 2, y + 20
    -- (the digit the buttons change: a glowing bar under it)
    if st.keys and env.amount then
      local sw = measure(0, size) - K.width("0", size)
      local digitW = K.width("0", size)
      local cx = ax + sw + placeAt(st.amount * 16 + st.place) * size / 10
      K.col(MINT, 0.6 + 0.4 * sin(clock * 6))
      K.box("fill", K.R(cx, y + 14 + size * 1.15, digitW, 0.8), 0.4)
    end
    K.text(upToText(most()), x, y + 27.5, 3.4, FAINT, "center", w)
    -- (the chips: +1,000 +10,000 +100,000 All, and Clear)
    local cy = y + 35
    local n = #CHIPS + 2
    local cw = (w - (n - 1) * 1.6) / n
    for i = 1, n do
      local cb = K.R(x + (i - 1) * (cw + 1.6), cy, cw, 8)
      local label = i <= #CHIPS and chipText[i] or (i == #CHIPS + 1 and T("hint.all") or T("bank.clear"))
      local last = i == n
      K.col(last and WHITE or MINT, last and 0.06 or 0.12)
      K.box("fill", cb, 4)
      K.ring(cb, 4, last and EDGE or MINT, last and 1 or 0.45, 0.4)
      local fs = K.fit(label, 3.6, cw - 2)
      K.text(label, cb[1], cb[2] + (8 - fs * 1.2) / 2, fs, last and SOFT or MINT, "center", cw)
      K.addHit(cb, "win", last and CLEAR or CHIP + i)
    end
    -- (the button: lit and breathing when there's something to move)
    local gb = K.R(x, cy + 10, w, 11)
    local on = st.amount > 0
    if on then
      K.col(MINT, 0.18 + 0.12 * sin(clock * 3))
      K.box("fill", K.R(gb[1] - 1, gb[2] - 1, gb[3] + 2, gb[4] + 2), 6.5)
      K.grad(gb, 5.5, BTN_TOP, BTN_FOOT)
    else
      K.col(BTN_OFF)
      K.box("fill", gb, 5.5)
    end
    if st.keys then K.focusRing(gb, 5.5) end
    local label = T(st.mode == "in" and "bank.deposit" or "bank.withdraw")
    K.bold(label, gb[1], gb[2] + (11 - 5 * 1.2) / 2, K.fit(label, 5, w - 6), on and BG_FOOT or FAINT, "center", w)
    K.addHit(gb, "win", GO)
    return cy + 21 - y
  end

  -- the activity: a line each, a coloured badge (in, out, overflow, interest), the amount
  local function badge(kind, cx, cy, r)
    local G = K.graphics()
    local c = kind == "in" and IN_C or (kind == "out" and OUT_C or (kind == "over" and OVER_C or RATE_C))
    K.col(c, 0.18)
    G.circle("fill", K.X(cx), K.Y(cy), r * K.sc)
    K.col(c)
    G.setLineWidth(max(1, r * 0.22 * K.sc))
    local X, Y, u = K.X(cx), K.Y(cy), r * 0.5 * K.sc
    if kind == "in" then
      G.line(X, Y - u, X, Y + u)
      G.line(X - u * 0.7, Y + u * 0.2, X, Y + u, X + u * 0.7, Y + u * 0.2)
    elseif kind == "out" then
      G.line(X, Y + u, X, Y - u)
      G.line(X - u * 0.7, Y - u * 0.2, X, Y - u, X + u * 0.7, Y - u * 0.2)
    elseif kind == "over" then
      G.circle("line", X, Y, u)
      G.line(X, Y - u * 0.5, X, Y + u * 0.5)
    else
      G.circle("fill", X - u * 0.55, Y - u * 0.55, u * 0.25)
      G.circle("fill", X + u * 0.55, Y + u * 0.55, u * 0.25)
      G.line(X + u * 0.7, Y - u * 0.7, X - u * 0.7, Y + u * 0.7)
    end
  end
  local function drawActivity(x, y, w, h)
    if h < 14 then return end
    K.bold(T("bank.activity"), x + 1, y, 4.2, SOFT)
    local lb = K.R(x, y + 6.5, w, h - 6.5)
    glass(lb, 5)
    local log = Bk.log()
    st.visible = max(1, floor((lb[4] - 1) / ROW_H))
    st.top = max(0, min(st.top, max(0, #log - st.visible)))
    if #log == 0 then
      K.text(T("bank.none"), lb[1], lb[2] + lb[4] / 2 - 2.5, 4, FAINT, "center", lb[3])
      return
    end
    local clip = K.R(lb[1], lb[2], lb[3], lb[4])
    K.scissor(clip)
    local t = os.time()
    local first = floor(st.top) + 1
    for i = first, min(#log, first + st.visible) do
      local e = log[i]
      local ry = lb[2] + 0.5 + (i - 1 - st.top) * ROW_H
      badge(e.kind, x + 7, ry + ROW_H / 2, 3.4)
      K.text(T(KIND[e.kind] or "bank.kind.in"), x + 13, ry + 1.6, 4, WHITE)
      K.text(agoText(max(0, floor((t - (e.at or t)) / 60))), x + 13, ry + 6.3, 3.1, FAINT)
      local plus = e.kind ~= "out"
      local c = e.kind == "in" and SOFT or (plus and IN_C or OUT_C)
      local mw = money(e.amount, x + w - 4, ry + 3, 4.2, c, true)
      K.text(e.kind == "in" and "" or (plus and "+" or "-"), x + w - 4 - mw - 3, ry + 3, 4.2, c)
      if i > first then
        K.col(WHITE, 0.06)
        K.box("fill", K.R(x + 13, ry - 0.3, w - 17, 0.3))
      end
    end
    K.scrollbar(lb[1] + lb[3], lb[2], lb[4], st.top, st.visible, #log)
    K.scissor(st.clip)
  end

  -- coins: from the amount to the card (a deposit), from the card to the wallet (a withdrawal); each
  -- coin's path made from its number and the time, nothing kept
  local function drawCoins(clock)
    local b = st.burst
    if not b then return end
    local age = now() - b.t
    if age > 1.1 then st.burst = nil return end
    local G = K.graphics()
    local fx, fy, tx, ty = st.amountX or 0, st.amountY or 0, st.cardX or 0, st.cardY or 0
    if b.out then fx, fy, tx, ty = st.cardX or 0, st.cardY or 0, st.walletX or 0, st.walletY or 0 end
    for i = 1, COINS do
      local k = ease((age - i * 0.045) / 0.7)
      if k > 0 and k < 1 then
        local lift = sin(k * math.pi) * (12 + (i % 3) * 4)
        local spread = (i - COINS / 2) * 1.6 * sin(k * math.pi)
        local px, py = fx + (tx - fx) * k + spread, fy + (ty - fy) * k - lift
        local r = 3 * (1 - 0.25 * k)
        local spin = math.abs(math.cos(clock * 8 + i))
        K.col(GOLD_FOOT, 1 - k * 0.3)
        G.ellipse("fill", K.X(px), K.Y(py), r * max(0.2, spin) * K.sc, r * K.sc)
        K.col(GOLD, 1 - k * 0.3)
        G.ellipse("fill", K.X(px), K.Y(py), (r - 0.5) * max(0.15, spin) * K.sc, (r - 0.5) * K.sc)
      end
    end
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    st.clip = body
    st.amount = min(st.amount, most())
    -- (the room: deep green, two soft lights drifting)
    K.grad(body, 0, BG_TOP, BG_FOOT)
    K.glow(x + w * (0.2 + 0.05 * sin(clock * 0.3)), y + h * 0.2, w * 0.45, h * 0.5, MINT_DEEP, 0.16)
    K.glow(x + w * (0.85 + 0.04 * sin(clock * 0.23 + 1)), y + h * 0.9, w * 0.4, h * 0.45, GOLD_FOOT, 0.1)
    if not portrait and w >= 200 then
      local lw = floor((w - M * 3) * 0.48)
      local rx, rw = x + M * 2 + lw, w - lw - M * 3
      drawCard(x + M, y + M, lw, 36, clock)
      drawWallet(x + M, y + M + 39, lw, clock)
      drawActivity(x + M, y + M + 57, lw, h - M * 2 - 57)
      drawAmount(rx, y + M, rw, clock)
    else
      local cw = w - M * 2
      drawCard(x + M, y + M, cw, 34, clock)
      drawWallet(x + M, y + M + 37, cw, clock)
      local used = drawAmount(x + M, y + M + 55, cw, clock)
      drawActivity(x + M, y + M + 57 + used, cw, h - M * 2 - 57 - used)
    end
    drawCoins(clock)
    K.scissor(body)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), UI.red, UI.green, UI.hud) then st.toast = nil end
  end

  return W
end
