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
    if st.mode == "in" then return min((env.money and env.money(s) or max(0, floor(tonumber(s and s.money) or 0))), Bk.MAX - Bk.balance()) end
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
    st.top = max(0, min(max(0, #Bk.log() - st.visible), st.top - dy / (st.rowH or ROW_H)))
  end

  function W.hints() return T.list(HINTS.main) end

  -- ------- drawing (no tables made here)

  -- a private bank in the Pokédex's glass: mint and gold lights drifting behind; the card a pane of deep
  -- green glass, the wallet, the amount, the chips and the activity on frosted panes, settling in one
  -- after another as it opens
  local CARD_TOP, CARD_FOOT = { 34, 190, 146 }, { 8, 98, 100 }
  local CARD_SOFT = { 206, 242, 230 }
  local SHEEN_TOP, SHEEN_FOOT = { 255, 255, 255, 0.32 }, { 255, 255, 255, 0 }
  local GOLD, GOLD_FOOT = { 255, 222, 128 }, { 196, 146, 44 }
  local MINT, MINT_DEEP, MINT_INK = { 110, 240, 196 }, { 24, 170, 130 }, { 8, 124, 92 }
  local WHITE, INK, SOFT, FAINT = { 255, 255, 255 }, { 28, 28, 30 }, { 112, 112, 120 }, { 160, 160, 170 }
  local SHADE = { 0, 0, 0 }
  local IN_C, OUT_C, OVER_C, RATE_C = { 20, 168, 124 }, { 236, 100, 70 }, { 214, 150, 20 }, { 72, 126, 240 }
  local BTN_TOP, BTN_FOOT = { 52, 214, 160 }, { 14, 140, 104 }
  local COINS = 9
  -- the motion's numbers (the view's own: st is the window's)
  local mv = { lastT = nil, dt = 0, openAt = nil, sw = nil, first = nil, seen = false, slide = 0,
               newAt = -10 }

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
  local ease = K.outCubic
  -- (a pane settling in: the i-th, `since` seconds after the window opened -> how far in, 0..1; its
  -- fade set, the old one returned)
  local function enter(i)
    local e = K.stagger(mv.since, i, 0.07, 0.42)
    local f0 = K.getFade()
    K.setFade(f0 * e)
    return e, f0
  end

  -- the bank card: deep green glass, a sheen sweeping across now and then, the gold chip, contactless
  -- waves, the balance counting to what it is
  local function drawCard(x, y, w, h, clock)
    local G = K.graphics()
    local b = K.R(x, y, w, h)
    K.shadow(b, 6, 1.6, 0.22)
    K.grad(b, 6, CARD_TOP, CARD_FOOT, 0.94)
    K.grad(K.R(x, y, w, min(h, 16)), 6, SHEEN_TOP, SHEEN_FOOT)
    -- (the card's pattern: two large soft circles; the sheen, a band across it every few seconds)
    K.scissor(b)
    K.col(WHITE, 0.08)
    G.circle("fill", K.X(x + w * 0.88), K.Y(y + h * 0.1), h * 0.75 * K.sc)
    K.col(WHITE, 0.06)
    G.circle("fill", K.X(x + w * 0.72), K.Y(y + h * 1.05), h * 0.6 * K.sc)
    local p = (clock * 0.28) % 1.6
    if p < 1 then
      local sx = x - w * 0.3 + p * w * 1.6
      K.col(WHITE, 0.18 * math.sin(p * math.pi))
      G.polygon("fill", K.X(sx), K.Y(y), K.X(sx + w * 0.12), K.Y(y), K.X(sx - w * 0.06), K.Y(y + h), K.X(sx - w * 0.18), K.Y(y + h))
    end
    K.scissor(st.clip)
    K.ring(b, 6, WHITE, 0.6, 0.4)
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
    K.text(T("bank.balance"), x + 5, y + h - 15.5, 3.4, CARD_SOFT)
    -- (the balance, counting up to what it is)
    local target = Bk.balance()
    st.shown = st.shown and K.approach(st.shown, target, mv.dt, 6) or target
    if math.abs(target - st.shown) < 1 then st.shown = target end
    local pulse = max(0, 1 - (now() - st.flash) / 0.6)
    local size = K.fit("000,000,000", 8, w - 10) * (1 + 0.08 * pulse)
    -- (bigger text: a little lower, clear of the label over it)
    money(floor(st.shown + 0.5), x + 5, y + h - 11 + (K.textScale() - 1) * 2.5, size, WHITE)
    st.cardX, st.cardY = x + w * 0.5, y + h * 0.5
  end

  -- the wallet: a ring for how full, what's in it, its cap
  local function drawWallet(x, y, w, clock)
    local G = K.graphics()
    local b = K.R(x, y, w, 15)
    K.glass(b, 4, 0.55)
    local s = session()
    local m = (env.money and env.money(s) or max(0, floor(tonumber(s and s.money) or 0)))
    local cap = Bk.wallet()
    local k = min(1, m / max(1, cap))
    local cx, cy, r = x + 8, y + 7.5, 4.6
    G.setLineWidth(max(1, 1.3 * K.sc))
    K.col(SHADE, 0.08)
    G.circle("line", K.X(cx), K.Y(cy), r * K.sc)
    K.col(k >= 1 and OVER_C or MINT_DEEP)
    if k > 0 then G.arc("line", "open", K.X(cx), K.Y(cy), r * K.sc, -math.pi / 2, -math.pi / 2 + 2 * math.pi * k, 32) end
    if k >= 1 then
      K.col(OVER_C, 0.2 + 0.15 * math.sin(clock * 4))
      G.circle("fill", K.X(cx), K.Y(cy), (r - 1.4) * K.sc)
    end
    K.text(T("bank.wallet"), x + 16, y + 2.4, 3.4, SOFT)
    money(m, x + 16, y + 7, 4.8, INK)
    st.walletX, st.walletY = cx, cy
  end

  -- Deposit | Withdraw: the glass switch, its thumb sliding to the chosen side, a line of mint (in) or
  -- coral (out) under it
  local function drawSwitch(x, y, w, h)
    local want = st.mode == "in" and 1 or 2
    mv.sw = mv.sw and K.approach(mv.sw, want, mv.dt, 16) or want
    K.glassSwitch(x, y, w, h, mv.sw, "win", TAB_IN, T("bank.deposit"), TAB_OUT, T("bank.withdraw"), nil, nil, 4.2)
    local sw = (w - 1) / 2
    K.col(K.mix(IN_C, OUT_C, mv.sw - 1), 0.9)
    K.box("fill", K.R(x + 0.5 + (mv.sw - 1) * sw + sw * 0.3, y + h - 1.9, sw * 0.4, 0.7), 0.35)
  end

  local function drawAmount(x, y, w, clock)
    drawSwitch(x, y, w, 9)
    local ab = K.R(x, y + 11, w, 22)
    K.glass(ab, 5, 0.6)
    local size = K.fit("000,000,000", 8.5, w - 18)
    -- (a change bumps it a little)
    if st.amount ~= st.lastAmount then st.lastAmount, st.bumpAt = st.amount, now() end
    local bump = max(0, 1 - (now() - (st.bumpAt or -10)) / 0.25)
    local s2 = size * (1 + 0.07 * bump)
    local aw = measure(st.amount, s2)
    local ax = x + (w - aw) / 2
    money(st.amount, ax, y + 14 - (s2 - size) * 0.6, s2, st.amount > 0 and INK or FAINT)
    st.amountX, st.amountY = x + w / 2, y + 20
    -- (the digit the buttons change: a glowing bar under it)
    if st.keys and env.amount then
      local sw = measure(0, size) - K.width("0", size)
      local digitW = K.width("0", size)
      local cx = ax + sw + placeAt(st.amount * 16 + st.place) * size / 10
      K.col(MINT_DEEP, 0.6 + 0.4 * sin(clock * 6))
      -- (bigger text: as much lower as the digits' foot came down)
      K.box("fill", K.R(cx, y + 14 + size * 1.15 + (K.textScale() - 1) * size * 0.45, digitW, 0.8), 0.4)
    end
    K.text(upToText(most()), x, y + 27.5, 3.4, SOFT, "center", w)
    -- (the chips: +1,000 +10,000 +100,000 All, clear glass tinted mint, and Clear)
    local cy = y + 35
    local n = #CHIPS + 2
    local cw = (w - (n - 1) * 1.6) / n
    for i = 1, n do
      local cb = K.R(x + (i - 1) * (cw + 1.6), cy, cw, 8)
      local label = i <= #CHIPS and chipText[i] or (i == #CHIPS + 1 and T("hint.all") or T("bank.clear"))
      local last = i == n
      K.col(WHITE, 0.45)
      K.box("fill", cb, 4)
      if not last then
        K.col(MINT, 0.26)
        K.box("fill", cb, 4)
      end
      K.ring(cb, 4, WHITE, 0.8, 0.3)
      local fs = K.fit(label, 3.6, cw - 2)
      K.text(label, cb[1], cb[2] + (8 - fs * 1.2) / 2, fs, last and SOFT or MINT_INK, "center", cw)
      K.addHit(cb, "win", last and CLEAR or CHIP + i)
    end
    -- (the button: lit and breathing when there's something to move, clear glass when there isn't)
    local gb = K.R(x, cy + 10, w, 11)
    local on = st.amount > 0
    if on then
      K.col(MINT_DEEP, 0.14 + 0.1 * sin(clock * 3))
      K.box("fill", K.R(gb[1] - 1, gb[2] - 1, gb[3] + 2, gb[4] + 2), 6.5)
      K.grad(gb, 5.5, BTN_TOP, BTN_FOOT)
      K.ring(gb, 5.5, WHITE, 0.45, 0.35)
    else
      K.glass(gb, 5.5, 0.4)
    end
    if st.keys then K.focusRing(gb, 5.5) end
    local label = T(st.mode == "in" and "bank.deposit" or "bank.withdraw")
    K.bold(label, gb[1], gb[2] + (11 - 5 * 1.2) / 2, K.fit(label, 5, w - 6), on and WHITE or FAINT, "center", w)
    K.addHit(gb, "win", GO)
    return cy + 21 - y
  end

  -- the activity: a line each, a coloured badge (in, out, overflow, interest), the amount; a new line
  -- slides in at the top, pushing the rest down
  local function badge(kind, cx, cy, r)
    local G = K.graphics()
    local c = kind == "in" and IN_C or (kind == "out" and OUT_C or (kind == "over" and OVER_C or RATE_C))
    K.col(c, 0.16)
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
  local function drawActivity(x, y, w, h, clock)
    if h < 14 then return end
    K.bold(T("bank.activity"), x + 1, y, 4.2, SOFT)
    local lb = K.R(x, y + 6.5, w, h - 6.5)
    K.glass(lb, 5, 0.5)
    local log = Bk.log()
    -- (a line as tall as its two lines of words: taller at a bigger text size)
    local g = K.textScale() - 1
    local ROW_H = ROW_H + g * 6
    st.rowH = ROW_H
    st.visible = max(1, floor((lb[4] - 1) / ROW_H))
    st.top = max(0, min(st.top, max(0, #log - st.visible)))
    -- (a new line at the top: it slides in)
    local e1 = log[1]
    if e1 ~= mv.first then
      if mv.seen then mv.slide, mv.newAt = ROW_H, clock end
      mv.first, mv.seen = e1, true
    end
    mv.slide = K.approach(mv.slide, 0, mv.dt, 10)
    if #log == 0 then
      K.text(T("bank.none"), lb[1], lb[2] + lb[4] / 2 - 2.5, 4, SOFT, "center", lb[3])
      return
    end
    local clip = K.R(lb[1], lb[2], lb[3], lb[4])
    K.scissor(clip)
    local t = os.time()
    local first = floor(st.top) + 1
    for i = first, min(#log, first + st.visible) do
      local e = log[i]
      local ry = lb[2] + 0.5 + (i - 1 - st.top) * ROW_H
      -- (offsets and a fade, no transform: a push makes garbage in some stand-ins)
      local k = K.stagger(mv.since, i - first + 3, 0.05, 0.3)
      local rx = x
      if i == 1 then
        k = min(k, ease((clock - mv.newAt) / 0.4))
        rx = x - (1 - k) * 6
      else
        ry = ry - mv.slide
      end
      local f0 = K.getFade()
      K.setFade(f0 * k)
      if i > first then K.hairline(x + 13, ry - 0.3, w - 17) end
      badge(e.kind, rx + 7, ry + ROW_H / 2, 3.4)
      local kind = T(KIND[e.kind] or "bank.kind.in")
      local plus = e.kind ~= "out"
      local c = e.kind == "in" and INK or (plus and IN_C or OUT_C)
      local sign = e.kind == "in" and "" or (plus and "+" or "-")
      -- (bigger text: the sign as much further left as it grew, the kind kept clear of the amount)
      local ks, sx = 4, nil
      if g > 0 then
        sx = rx + w - 4 - measure(e.amount, 4.2) - 3 - K.width(sign, 4.2) * g / (g + 1)
        ks = K.fit(kind, 4, sx - 2 - (rx + 13))
      end
      K.text(kind, rx + 13, ry + 1.6 + g * 1.5, ks, INK)
      K.text(agoText(max(0, floor((t - (e.at or t)) / 60))), rx + 13, ry + 6.3 + g * 4.4, 3.1, SOFT)
      local mw = money(e.amount, rx + w - 4, ry + 3 + g * 3, 4.2, c, true)
      K.text(sign, sx or (rx + w - 4 - mw - 3), ry + 3 + g * 3, 4.2, c)
      K.setFade(f0)
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
    mv.dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT = clock
    mv.openAt = mv.openAt or clock
    mv.since = clock - mv.openAt
    st.clip = body
    st.amount = min(st.amount, most())
    -- (the room: mint and gold lights drifting over a pale green wash)
    K.backdrop(body, clock, 0.24, 0.8, 0.62, 1, 0.8, 0.36)
    K.scissor(body)
    local e, f0
    if not portrait and w >= 200 then
      local lw = floor((w - M * 3) * 0.48)
      local rx, rw = x + M * 2 + lw, w - lw - M * 3
      e, f0 = enter(0)
      drawCard(x + M, y + M + (1 - e) * 5, lw, 36, clock)
      K.setFade(f0)
      e, f0 = enter(1)
      drawWallet(x + M, y + M + 39 + (1 - e) * 5, lw, clock)
      K.setFade(f0)
      e, f0 = enter(2)
      drawActivity(x + M, y + M + 57 + (1 - e) * 5, lw, h - M * 2 - 57, clock)
      K.setFade(f0)
      e, f0 = enter(1)
      drawAmount(rx, y + M + (1 - e) * 5, rw, clock)
      K.setFade(f0)
    else
      local cw = w - M * 2
      e, f0 = enter(0)
      drawCard(x + M, y + M + (1 - e) * 5, cw, 34, clock)
      K.setFade(f0)
      e, f0 = enter(1)
      drawWallet(x + M, y + M + 37 + (1 - e) * 5, cw, clock)
      K.setFade(f0)
      e, f0 = enter(2)
      local used = drawAmount(x + M, y + M + 55 + (1 - e) * 5, cw, clock)
      K.setFade(f0)
      e, f0 = enter(3)
      drawActivity(x + M, y + M + 57 + used + (1 - e) * 5, cw, h - M * 2 - 57 - used, clock)
      K.setFade(f0)
    end
    drawCoins(clock)
    K.scissor(body)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), UI.red, UI.green, UI.hud) then st.toast = nil end
  end

  return W
end
