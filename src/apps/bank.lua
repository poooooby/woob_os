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
    st.amount, st.flash = 0, now()
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

  local CARD_TOP, CARD_FOOT = { 22, 128, 98 }, { 10, 66, 58 }
  local GOLD, GOLD_FOOT = { 246, 214, 120 }, { 196, 150, 52 }
  local WHITE, SOFT = { 255, 255, 255 }, { 255, 255, 255, 0.72 }
  local IN_C, OUT_C = { 40, 170, 90 }, { 28, 28, 30 }

  local function money(n, x, y, size, c, right)
    if not env.amount then return 0 end
    local ok, w = pcall(env.amount, n, 0, 0, size, c, true)
    w = ok and tonumber(w) or 0
    pcall(env.amount, n, right and x - w or x, y, size, c)
    return w
  end

  -- the bank card: a green card, a gold chip, the name, what's kept
  local function drawCard(x, y, w, h, clock)
    local b = K.R(x, y, w, h)
    K.shadow(b, 5, 1.2, 0.22)
    K.grad(b, 5, CARD_TOP, CARD_FOOT)
    -- (a sheen across it)
    K.col(WHITE, 0.08)
    local G = K.graphics()
    G.polygon("fill", K.X(x + w * 0.55), K.Y(y), K.X(x + w * 0.8), K.Y(y), K.X(x + w * 0.5), K.Y(y + h), K.X(x + w * 0.25), K.Y(y + h))
    K.grad(K.R(x + w - 16, y + 5, 11, 8), 1.6, GOLD, GOLD_FOOT)
    K.col(GOLD_FOOT, 0.7)
    K.box("fill", K.R(x + w - 16, y + 8.7, 11, 0.4))
    K.bold(T("bank.name"), x + 5, y + 5, 4.6, WHITE)
    K.text(T("bank.balance"), x + 5, y + h - 17, 3.8, SOFT)
    local pulse = max(0, 1 - (now() - st.flash) / 0.6)
    money(Bk.balance(), x + 5, y + h - 11.5, K.fit("000,000,000", 8, w - 10) * (1 + 0.06 * pulse), WHITE)
  end

  -- the wallet: what's in it, its cap, a bar for how full
  local function drawWallet(x, y, w)
    local b = K.R(x, y, w, 15)
    K.card(b, 4)
    local s = session()
    local m = max(0, floor(tonumber(s and s.money) or 0))
    K.text(T("bank.wallet"), x + 4, y + 2.4, 3.8, UI.secondary)
    money(m, x + w - 4, y + 2, 4.6, UI.label, true)
    local cap = Bk.wallet()
    K.col(UI.fill)
    K.box("fill", K.R(x + 4, y + 10, w - 8, 1.6), 0.8)
    local k = min(1, m / max(1, cap))
    K.col(k >= 1 and UI.orange or UI.green)
    K.box("fill", K.R(x + 4, y + 10, (w - 8) * k, 1.6), 0.8)
  end

  local function drawAmount(x, y, w, clock)
    K.segmented(x, y, w, 9, st.mode == "in" and 1 or 2, "win", TAB_IN, T("bank.deposit"), TAB_OUT, T("bank.withdraw"))
    local ab = K.R(x, y + 11, w, 22)
    K.card(ab, 4)
    local size = K.fit("000,000,000", 8.5, w - 18)
    local aw = 0
    if env.amount then
      local okW, mw = pcall(env.amount, st.amount, 0, 0, size, UI.label, true)
      aw = okW and tonumber(mw) or 0
    end
    local ax = x + (w - aw) / 2
    money(st.amount, ax, y + 14, size, UI.label)
    -- (the digit the buttons change: a line under it)
    if st.keys and env.amount then
      local okS, sw = pcall(env.amount, 0, 0, 0, size, UI.label, true)
      local digitW = K.width("0", size)
      sw = (okS and tonumber(sw) or 0) - digitW
      local cx = ax + sw + placeAt(st.amount * 16 + st.place) * size / 10
      K.col(UI.accent, 0.6 + 0.4 * sin(clock * 6))
      K.box("fill", K.R(cx, y + 14 + size * 1.15, digitW, 0.7), 0.3)
    end
    K.text(upToText(most()), x, y + 27.5, 3.6, UI.secondary, "center", w)
    -- (the chips: +1,000 +10,000 +100,000 All, and Clear)
    local cy = y + 35
    local n = #CHIPS + 2
    local cw = (w - (n - 1) * 1.6) / n
    for i = 1, n do
      local cb = K.R(x + (i - 1) * (cw + 1.6), cy, cw, 8)
      local label = i <= #CHIPS and chipText[i] or (i == #CHIPS + 1 and T("hint.all") or T("bank.clear"))
      K.col(i == n and UI.fill or UI.accentSoft)
      K.box("fill", cb, 4)
      local fs = K.fit(label, 3.8, cw - 2)
      K.text(label, cb[1], cb[2] + (8 - fs * 1.2) / 2, fs, i == n and UI.label or UI.accent, "center", cw)
      K.addHit(cb, "win", i == n and CLEAR or CHIP + i)
    end
    local gb = K.R(x, cy + 10, w, 11)
    K.button(gb, T(st.mode == "in" and "bank.deposit" or "bank.withdraw"), st.amount > 0 and "accent" or nil,
      st.keys, 5)
    K.addHit(gb, "win", GO)
    return cy + 21 - y
  end

  local function drawActivity(x, y, w, h)
    if h < 14 then return end
    K.bold(T("bank.activity"), x + 1, y, 4.4, UI.label)
    local lb = K.R(x, y + 6.5, w, h - 6.5)
    K.card(lb, 4)
    local log = Bk.log()
    st.visible = max(1, floor((lb[4] - 1) / ROW_H))
    st.top = max(0, min(st.top, max(0, #log - st.visible)))
    if #log == 0 then
      K.text(T("bank.none"), lb[1], lb[2] + lb[4] / 2 - 2.5, 4, UI.tertiary, "center", lb[3])
      return
    end
    local clip = K.R(lb[1], lb[2], lb[3], lb[4])
    K.scissor(clip)
    local t = os.time()
    local first = floor(st.top) + 1
    for i = first, min(#log, first + st.visible) do
      local e = log[i]
      local ry = lb[2] + 0.5 + (i - 1 - st.top) * ROW_H
      K.text(T(KIND[e.kind] or "bank.kind.in"), x + 4, ry + 1.6, 4.2, UI.label)
      K.text(agoText(max(0, floor((t - (e.at or t)) / 60))), x + 4, ry + 6.4, 3.3, UI.tertiary)
      local plus = e.kind ~= "in"
      local c = plus and IN_C or OUT_C
      local mw = money(e.amount, x + w - 4, ry + 3, 4.4, c, true)
      K.text(plus and "+" or "-", x + w - 4 - mw - 3, ry + 3, 4.4, c)
      if i > first then K.hairline(x + 4, ry - 0.5, w - 8) end
    end
    K.scrollbar(lb[1] + lb[3], lb[2], lb[4], st.top, st.visible, #log)
    K.scissor(st.clip)
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    st.clip = body
    st.amount = min(st.amount, most())
    if not portrait and w >= 200 then
      local lw = floor((w - M * 3) * 0.48)
      local rx, rw = x + M * 2 + lw, w - lw - M * 3
      drawCard(x + M, y + M, lw, 36, clock)
      drawWallet(x + M, y + M + 39, lw)
      drawActivity(x + M, y + M + 57, lw, h - M * 2 - 57)
      drawAmount(rx, y + M, rw, clock)
    else
      local cw = w - M * 2
      drawCard(x + M, y + M, cw, 34, clock)
      drawWallet(x + M, y + M + 37, cw)
      local used = drawAmount(x + M, y + M + 55, cw, clock)
      drawActivity(x + M, y + M + 57 + used, cw, h - M * 2 - 57 - used)
    end
    K.scissor(body)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), UI.red, UI.green, UI.hud) then st.toast = nil end
  end

  return W
end
