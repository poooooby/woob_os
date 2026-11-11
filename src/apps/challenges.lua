-- Challenges (the model is src/challenges.lua, env.challenges): this week's five goals, each with its
-- progress, its reward and Claim once it's done; the week's countdown and a ring of how many are
-- claimed; the bonus for claiming all five.
--   buttons  Up / Down a goal (the bonus last), A claim, B close
--   touch    Claim; drag (or the wheel) scrolls when they don't all fit
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, sin, pi = math.floor, math.max, math.min, math.sin, math.pi

local M = 3
local CLAIM, BONUS = 2100, 2200
local HINTS = { main = { { "^ v", "hint.choose" }, { "A", "challenges.claim" }, { "B", "hint.close" } } }
-- each kind's picture (src/icons.lua) and colour
local LOOK = {
  trainer = { "glove", { 255, 69, 58 } }, wild = { "flame", { 255, 149, 0 } }, catch = { "pokeball", { 226, 70, 72 } },
  type = { "pokeball", { 88, 86, 214 } }, new = { "database", { 0, 122, 255 } }, hatch = { "cube", { 255, 189, 46 } },
  evolve = { "send", { 175, 82, 222 } }, items = { "bag", { 52, 170, 220 } }, steps = { "shoes", { 52, 199, 89 } },
  places = { "internet", { 48, 176, 199 } }, levels = { "chart", { 255, 55, 95 } }, swarm = { "fish", { 0, 150, 136 } },
}
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, Ch, T = env.K, env.challenges, env.T or NO_T
  local UI = K.UI
  local W = { title = T("app.challenges") }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local st = { cursor = 1, keys = false, top = 0, toast = nil, texts = {}, flash = {} }
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
  local countText = K.textCache(function(key) return floor(key / 100000) .. " / " .. key % 100000 end)
  local endsText = K.textCache(function(mins)
    if mins >= 1440 then return T.f("challenges.endsDays", floor(mins / 1440), floor(mins % 1440 / 60)) end
    return T.f("challenges.endsHours", floor(mins / 60), mins % 60)
  end)
  local timesText = K.textCache(function(n) return "x" .. n end)
  local doneText = K.textCache(function(n) return n .. "/5" end)

  -- the goals' words: made again for a new week or another language
  local function texts(list)
    local code = T.code and T.code() or ""
    if st.textsList ~= list or st.textsCode ~= code then
      st.textsList, st.textsCode = list, code
      for i, e in ipairs(list) do st.texts[i] = Ch.text(e) end
    end
    return st.texts
  end
  -- (the countdown, worked out once a second: the local time makes tables)
  local function endsMinutes()
    local sec = floor(now())
    if st.endsAt ~= sec then st.endsAt, st.endsMin = sec, floor(Ch.endsIn() / 60) end
    return st.endsMin
  end

  local function toast(text, bad) st.toast = { text = text, bad = bad, t = now() } end
  local function claim(i)
    local s = session()
    local ok, r
    if i > #Ch.list(s) then ok, r = Ch.claimBonus(s) else ok, r = Ch.claim(s, i) end
    if not ok then
      se("SE_FAILURE")
      return toast(T("reason.challenges." .. tostring(r)), true)
    end
    st.flash[i] = now()
    if r.money then
      se("SE_SHOP")
      toast(T.f("challenges.gotMoney", commas(r.money)), false)
    else
      se("SE_SUCCESS")
      local name = env.itemName and env.itemName(r.item) or tostring(r.item)
      toast(T.f("challenges.gotItem", name, r.n), false)
      if env.pad and env.pad.transfer then pcall(env.pad.transfer, r.item, "in") end
    end
  end

  local cur
  function W.input(input, nav)
    cur = input
    if input:wasPressed("b") then return false end
    local n = #Ch.list(session()) + 1
    if nav.up or nav.down then
      if not st.keys then
        st.keys = true
      else
        st.cursor = max(1, min(n, st.cursor + (nav.down and 1 or -1)))
      end
      se("SE_SELECT")
    elseif input:wasPressed("a") then
      st.keys = true
      claim(st.cursor)
    end
    return true
  end
  function W.tap(arg)
    st.keys = false
    if arg == BONUS then return claim(#Ch.list(session()) + 1) end
    if type(arg) == "number" and arg > CLAIM and arg < BONUS then claim(arg - CLAIM) end
  end
  function W.scroll(dy)
    st.top = max(0, min(st.maxTop or 0, st.top - dy))
  end
  function W.hints() return T.list(HINTS.main) end

  -- ------- drawing (no tables made here)

  -- a quest board under a night sky: deep violet, stars, gold
  local BG_TOP, BG_FOOT = { 46, 22, 96 }, { 10, 6, 32 }
  local AURORA, AURORA2 = { 120, 80, 255 }, { 40, 200, 220 }
  local WHITE, SOFT, FAINT = { 255, 255, 255 }, { 210, 200, 240 }, { 140, 128, 182 }
  local GLASS, EDGE = { 255, 255, 255, 0.07 }, { 255, 255, 255, 0.12 }
  local GOLD, GOLD_DEEP, AMBER = { 255, 214, 92 }, { 226, 140, 30 }, { 255, 170, 60 }
  local GREEN = { 90, 230, 140 }
  local CHEST, CHEST_DARK = { 176, 104, 52 }, { 110, 58, 28 }
  local STARS, CONFETTI_N = 34, 48
  local CONF = { GOLD, GREEN, AURORA, AURORA2, { 255, 110, 170 }, WHITE }

  -- confetti (a fixed pool)
  local P = {}
  for i = 1, CONFETTI_N do P[i] = { live = false, x = 0, y = 0, vx = 0, vy = 0, t0 = 0, c = nil, spin = 0 } end
  local nextP = 1
  local function confetti(x, y)
    for i = 1, 22 do
      local p = P[nextP]
      nextP = nextP % CONFETTI_N + 1
      local a = (i / 22) * math.pi * 2 + sin(i * 2.7) * 0.4
      local v = 22 + (i * 17 % 30)
      p.live, p.x, p.y, p.vx, p.vy, p.t0 = true, x, y, math.cos(a) * v, sin(a) * v - 18, now()
      p.c, p.spin = CONF[i % #CONF + 1], (i * 0.37) % 1
    end
  end
  -- (each frame's eased values, kept per goal)
  local barK, rowX, rowY, rowW = {}, {}, {}, {}
  for i = 1, 6 do barK[i], rowX[i], rowY[i], rowW[i] = 0, 0, 0, 0 end
  local ringK = 0

  local function money(n, x, y, size, c, right)
    if not env.amount then return 0 end
    local ok, w = pcall(env.amount, n, 0, 0, size, c, true)
    w = ok and tonumber(w) or 0
    pcall(env.amount, n, right and x - w or x, y, size, c)
    return w
  end
  local function glass(b, rad, a)
    K.col(GLASS, a)
    K.box("fill", b, rad)
    K.ring(b, rad, EDGE, a or 1, 0.4)
  end
  local function check(cx, cy, r, c, a)
    local G = K.graphics()
    K.col(c, a)
    G.circle("fill", K.X(cx), K.Y(cy), r * K.sc)
    G.setColor(1, 1, 1, a or 1)
    G.setLineWidth(max(1, r * 0.28 * K.sc))
    G.line(K.X(cx - r * 0.45), K.Y(cy), K.X(cx - r * 0.1), K.Y(cy + r * 0.35), K.X(cx + r * 0.5), K.Y(cy - r * 0.35))
  end
  -- the sky: stars at places made from their number, twinkling
  local function sky(x, y, w, h, clock)
    local G = K.graphics()
    K.grad(K.R(x, y, w, h), 0, BG_TOP, BG_FOOT)
    K.glow(x + w * (0.3 + 0.08 * sin(clock * 0.2)), y + h * 0.15, w * 0.55, h * 0.35, AURORA, 0.16)
    K.glow(x + w * (0.75 + 0.06 * sin(clock * 0.17 + 2)), y + h * 0.3, w * 0.45, h * 0.3, AURORA2, 0.09)
    for i = 1, STARS do
      local sx = x + ((i * 97.13) % 1000) / 1000 * w
      local sy = y + ((i * 61.71) % 1000) / 1000 * h
      local tw = 0.35 + 0.65 * math.abs(sin(clock * (0.8 + (i % 5) * 0.3) + i))
      K.col(WHITE, 0.5 * tw)
      G.circle("fill", K.X(sx), K.Y(sy), (0.25 + (i % 3) * 0.15) * K.sc)
    end
  end
  local function ring(cx, cy, r, k, width, clock)
    local G = K.graphics()
    G.setLineWidth(max(1, width * K.sc))
    K.col(WHITE, 0.1)
    G.circle("line", K.X(cx), K.Y(cy), r * K.sc)
    if k > 0.001 then
      -- (gold to amber along the arc: a few pieces)
      local pieces = 12
      local a0 = -math.pi / 2
      for i = 0, pieces - 1 do
        local s0, s1 = i / pieces, (i + 1) / pieces
        if s0 >= k then break end
        K.col(K.mix(GOLD, AMBER, s0))
        G.arc("line", "open", K.X(cx), K.Y(cy), r * K.sc, a0 + 2 * math.pi * s0, a0 + 2 * math.pi * min(k, s1), 8)
      end
      local ea = a0 + 2 * math.pi * k
      K.glow(cx + math.cos(ea) * r, cy + sin(ea) * r, width * 2.5, width * 2.5, GOLD, 0.5)
    end
  end
  -- a reward: money, or an item and how many -> its width
  local function reward(r, x, y, right)
    if r.money then return money(r.money, x, y + 1, 4, GOLD, right) end
    local tw = K.width(timesText(r.n), 3.6)
    local w = 10 + tw
    local x0 = right and x - w or x
    K.col(WHITE, 0.1)
    K.graphics().circle("fill", K.X(x0 + 4.5), K.Y(y + 2.5), 4.6 * K.sc)
    if env.itemIcon then pcall(env.itemIcon, r.item, x0 + 0.5, y - 1.5, 8) end
    K.text(timesText(r.n), x0 + 10, y + 1.2, 3.6, SOFT)
    return w
  end
  -- the bonus: a chest; open and glowing once it's ready, the lid lifting
  local function chest(cx, cy, s, ready, opened, clock)
    local G = K.graphics()
    if ready then K.glow(cx, cy, s * 1.6, s * 1.2, GOLD, 0.3 + 0.15 * sin(clock * 3)) end
    local w, h = s * 1.6, s
    local lift = (ready or opened) and (opened and s * 0.35 or s * 0.12 * (1 + sin(clock * 4))) or 0
    K.grad(K.R(cx - w / 2, cy - h * 0.1, w, h * 0.7), s * 0.12, CHEST, CHEST_DARK)
    K.col(GOLD)
    K.box("fill", K.R(cx - w / 2, cy + h * 0.12, w, h * 0.08))
    if ready or opened then
      K.col(GOLD, 0.9)
      K.box("fill", K.R(cx - w * 0.4, cy - h * 0.12 - lift * 0.3, w * 0.8, h * 0.12), s * 0.05)
    end
    K.grad(K.R(cx - w / 2, cy - h * 0.42 - lift, w, h * 0.36), s * 0.18, CHEST, CHEST_DARK)
    K.col(GOLD)
    K.box("fill", K.R(cx - s * 0.12, cy - h * 0.2 - lift, s * 0.24, s * 0.26), s * 0.05)
  end

  local function drawRow(i, e, text, x, y, w, h, clock)
    local G = K.graphics()
    local b = K.R(x, y, w, h)
    rowX[i], rowY[i], rowW[i] = x, y, w
    local look = LOOK[e.kind] or LOOK.catch
    local p, done = Ch.progress(e), Ch.done(e)
    local claimable = done and not e.claimed
    local a = e.claimed and 0.55 or 1
    if claimable then
      K.col(look[2], 0.22 + 0.12 * sin(clock * 3 + i))
      K.box("fill", K.R(x - 1, y - 1, w + 2, h + 2), 5.5)
    end
    glass(b, 4.5, a)
    -- (the badge: a disc in the kind's colour, its picture)
    local r = h * 0.3
    local cx, cy = x + 4 + r, y + h / 2
    K.glow(cx, cy, r * 1.6, r * 1.6, look[2], 0.18 * a)
    K.col(look[2], a)
    G.circle("fill", K.X(cx), K.Y(cy), r * K.sc)
    K.col(WHITE, 0.25 * a)
    G.circle("fill", K.X(cx - r * 0.25), K.Y(cy - r * 0.3), r * 0.45 * K.sc)
    if env.glyph then pcall(env.glyph, G, look[1], K.X(cx), K.Y(cy), r * 2 * K.sc, a, look[2]) end
    -- (the words, the bar easing to the count, a shimmer running along it)
    local tx = cx + r + 3.5
    local right = x + w - 4
    local rw = 24
    local tw = right - rw - tx - 2
    K.text(text, tx, y + h * 0.16, K.fit(text, 4.2, tw), WHITE, nil, nil, a)
    local dt = st.lastT and min(0.1, max(0, now() - st.lastT)) or 0
    local want = p / max(1, e.goal)
    barK[i] = barK[i] + (want - barK[i]) * min(1, dt * 5)
    local bw = tw - 16
    local by = y + h * 0.64
    K.col(WHITE, 0.1 * a)
    K.box("fill", K.R(tx, by, bw, 1.8), 0.9)
    if barK[i] > 0.005 then
      local fw = bw * barK[i]
      K.col(done and GREEN or look[2], a)
      K.box("fill", K.R(tx, by, fw, 1.8), 0.9)
      local sh = (clock * 0.6 + i * 0.17) % 1.4
      if sh < 1 then
        K.col(WHITE, 0.45 * a)
        K.box("fill", K.R(tx + fw * sh, by, min(4, fw * (1 - sh)), 1.8), 0.9)
      end
    end
    K.text(countText(p * 100000 + e.goal), tx + tw - 15, by - 1.3, 3.2, SOFT, "right", 15, a)
    -- (the reward, Claim, or the tick)
    if e.claimed then
      local f = st.flash[i] and max(0, 1 - (now() - st.flash[i]) / 0.4) or 0
      check(right - 4, cy, 3.4 * (1 + 0.5 * f), GREEN, 1)
    elseif claimable then
      local cb = K.R(right - rw, cy - 4.5, rw, 9)
      local pulse = 0.5 + 0.5 * sin(clock * 4)
      K.col(GOLD, 0.25 * pulse)
      K.box("fill", K.R(cb[1] - 1.2, cb[2] - 1.2, cb[3] + 2.4, cb[4] + 2.4), 5.6)
      K.grad(cb, 4.5, GOLD, GOLD_DEEP)
      K.bold(T("challenges.claim"), cb[1], cb[2] + (9 - 4.2 * 1.2) / 2, K.fit(T("challenges.claim"), 4.2, rw - 3), BG_FOOT,
        "center", rw)
      if st.keys and st.cursor == i then K.focusRing(cb, 4.5) end
      K.addHit(cb, "win", CLAIM + i)
    else
      reward(e.reward, right, cy - 2.6, true)
    end
    if st.keys and st.cursor == i and not claimable then K.focusRing(b, 4.5) end
  end

  -- the week: the countdown, the ring of how many are claimed, the bonus chest
  local function drawWeek(x, y, w, h, list, clock)
    local b = K.R(x, y, w, h)
    glass(b, 6)
    local s = session()
    K.bold(T("challenges.week"), x + 5, y + 4, 6, WHITE)
    local ends = endsText(endsMinutes())
    local ew = K.width(ends, 3.4) + 6
    K.col(GOLD, 0.14)
    K.box("fill", K.R(x + 5, y + 12, ew, 6), 3)
    K.text(ends, x + 8, y + 12.8, 3.4, GOLD)
    local claimed = 0
    for _, e in ipairs(list) do if e.claimed then claimed = claimed + 1 end end
    local dt = st.lastT and min(0.1, max(0, now() - st.lastT)) or 0
    ringK = ringK + (claimed / max(1, #list) - ringK) * min(1, dt * 4)
    local rr = min(w * 0.24, (h - 54) / 2)
    local cx, cy = x + w / 2, y + 24 + rr
    if rr > 4 then
      ring(cx, cy, rr, ringK, 2.4, clock)
      K.bold(doneText(claimed), cx - rr, cy - 3.6, 7, WHITE, "center", rr * 2)
      -- (all five: sparks circling)
      if claimed >= #list then
        local G = K.graphics()
        for k = 0, 5 do
          local an = clock * 1.2 + k * math.pi / 3
          K.col(GOLD, 0.7)
          G.circle("fill", K.X(cx + math.cos(an) * (rr + 4)), K.Y(cy + sin(an) * (rr + 4)), 0.7 * K.sc)
        end
      end
    end
    -- (the bonus)
    local bonus = Ch.bonus(s)
    local ready = Ch.bonusReady(s)
    local bb = K.R(x + 4, y + h - 24, w - 8, 20)
    K.col(GOLD, ready and (0.18 + 0.08 * sin(clock * 3)) or 0.08)
    K.box("fill", bb, 5)
    K.ring(bb, 5, GOLD, ready and 0.8 or 0.3, 0.45)
    chest(bb[1] + 9, bb[2] + 11, 7, ready, bonus.claimed, clock)
    K.bold(T("challenges.bonus"), bb[1] + 18, bb[2] + 3, 4, WHITE)
    K.text(T("challenges.bonusNote"), bb[1] + 18, bb[2] + 9, 3.2, SOFT)
    local i = #list + 1
    rowX[i], rowY[i], rowW[i] = bb[1], bb[2], bb[3]
    if bonus.claimed then
      check(bb[1] + bb[3] - 6, bb[2] + 10, 3.4, GREEN)
    elseif ready then
      local cb = K.R(bb[1] + bb[3] - 23, bb[2] + 5.5, 21, 9)
      K.grad(cb, 4.5, GOLD, GOLD_DEEP)
      K.bold(T("challenges.claim"), cb[1], cb[2] + (9 - 4 * 1.2) / 2, K.fit(T("challenges.claim"), 4, 18), BG_FOOT, "center", cb[3])
      if st.keys and st.cursor == i then K.focusRing(cb, 4.5) end
      K.addHit(cb, "win", BONUS)
    else
      reward(bonus, bb[1] + bb[3] - 3, bb[2] + 14, true)
    end
    if st.keys and st.cursor == i and not ready then K.focusRing(bb, 5) end
  end

  local function drawConfetti(clock)
    local G = K.graphics()
    for i = 1, CONFETTI_N do
      local p = P[i]
      if p.live then
        local age = now() - p.t0
        if age > 1.4 then
          p.live = false
        else
          local px, py = p.x + p.vx * age, p.y + p.vy * age + 50 * age * age
          G.push()
          G.translate(K.X(px), K.Y(py))
          G.rotate(clock * 8 + p.spin * 6)
          K.col(p.c, min(1, (1.4 - age) / 0.4))
          local f = math.abs(math.cos(clock * 6 + p.spin * 4))
          G.rectangle("fill", -1.1 * K.sc, -0.5 * K.sc * f - 0.2 * K.sc, 2.2 * K.sc, 1 * K.sc * f + 0.4 * K.sc)
          G.pop()
        end
      end
    end
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    st.clip = body
    local s = session()
    local list = Ch.list(s)
    local words = texts(list)
    sky(x, y, w, h, clock)
    -- (a claim since the last frame: confetti from where it was)
    for i = 1, #list + 1 do
      local f = st.flash[i]
      if f and f ~= st.burst and now() - f < 0.1 then
        st.burst = f
        confetti(rowX[i] + rowW[i] - 14, rowY[i] + 8)
      end
    end
    if not portrait and w >= 200 then
      local lw = floor((w - M * 3) * 0.36)
      drawWeek(x + M, y + M, lw, h - M * 2, list, clock)
      local rx, rw = x + M * 2 + lw, w - lw - M * 3
      local rh = min(22, (h - M * 2 - (#list - 1) * 2) / max(1, #list))
      st.maxTop, st.top = 0, 0
      for i, e in ipairs(list) do drawRow(i, e, words[i], rx, y + M + (i - 1) * (rh + 2), rw, rh, clock) end
    else
      -- (upright: the week's strip, then the goals, scrolling)
      local hh = 34
      local hb = K.R(x + M, y + M, w - M * 2, hh)
      glass(hb, 6)
      K.bold(T("challenges.week"), hb[1] + 4, hb[2] + 3, 5.4, WHITE)
      K.text(endsText(endsMinutes()), hb[1] + 4, hb[2] + 10, 3.4, GOLD)
      local claimed = 0
      for _, e in ipairs(list) do if e.claimed then claimed = claimed + 1 end end
      local dt = st.lastT and min(0.1, max(0, now() - st.lastT)) or 0
      ringK = ringK + (claimed / max(1, #list) - ringK) * min(1, dt * 4)
      ring(hb[1] + hb[3] - 10, hb[2] + 9, 6, ringK, 1.6, clock)
      K.text(doneText(claimed), hb[1] + hb[3] - 16, hb[2] + 7.4, 3.2, WHITE, "center", 12)
      local bonus = Ch.bonus(s)
      local ready = Ch.bonusReady(s)
      chest(hb[1] + 9, hb[2] + 26, 5, ready, bonus.claimed, clock)
      K.text(T("challenges.bonus"), hb[1] + 17, hb[2] + 22, 3.6, WHITE)
      local i = #list + 1
      rowX[i], rowY[i], rowW[i] = hb[1], hb[2] + 18, hb[3]
      if bonus.claimed then
        check(hb[1] + hb[3] - 8, hb[2] + 26, 3, GREEN)
      elseif ready then
        local cb = K.R(hb[1] + hb[3] - 23, hb[2] + 22, 20, 9)
        K.grad(cb, 4.5, GOLD, GOLD_DEEP)
        K.bold(T("challenges.claim"), cb[1], cb[2] + 2.3, K.fit(T("challenges.claim"), 4, 17), BG_FOOT, "center", cb[3])
        if st.keys and st.cursor == i then K.focusRing(cb, 4.5) end
        K.addHit(cb, "win", BONUS)
      else
        reward(bonus, hb[1] + hb[3] - 4, hb[2] + 24, true)
      end
      local top = y + M + hh + 3
      local rh = 20
      local area = K.R(x, top, w, y + h - top)
      st.maxTop = max(0, #list * (rh + 2) - area[4])
      st.top = min(st.top, st.maxTop)
      if st.keys and st.cursor <= #list then
        local cy = (st.cursor - 1) * (rh + 2)
        if cy < st.top then st.top = cy end
        if cy + rh > st.top + area[4] then st.top = cy + rh - area[4] end
      end
      K.scissor(area)
      for j, e in ipairs(list) do drawRow(j, e, words[j], x + M, top + (j - 1) * (rh + 2) - st.top, w - M * 2, rh, clock) end
      K.scissor(body)
    end
    st.lastT = now()
    drawConfetti(clock)
    K.scissor(body)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), UI.red, UI.green, UI.hud) then st.toast = nil end
  end

  return W
end
