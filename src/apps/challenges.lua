-- Challenges (the model is src/challenges.lua, env.challenges): this week's five goals, each with its
-- progress, its reward and Claim once it's done; the week's countdown and a ring of how many are
-- claimed; the bonus for claiming all five.
--   buttons  Up / Down a goal (the bonus last), A claim, B close
--   touch    Claim; drag (or the wheel) scrolls when they don't all fit
--
-- The Pokédex's glass: panes over a backdrop lit by the chosen goal's colour (eased as the choice
-- changes). Its motion, numbers only (`mv`): the goals rising in one after another, the highlight
-- gliding from goal to goal (and to the bonus), the bars and the ring of claimed filling, the week's bar
-- filling, the countdown rolling over each minute, a claimed goal popping with a glow and its tick, the
-- confetti; upright, the list scrolling smoothly.
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, sin, cos, pi, abs = math.floor, math.max, math.min, math.sin, math.cos, math.pi, math.abs

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
    if st.endsAt ~= sec then
      local left = Ch.endsIn()
      st.endsAt, st.endsMin, st.endsSec = sec, floor(left / 60), left
    end
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

  local WEEK = 7 * 86400
  local C = {
    ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, faint = { 160, 160, 170 }, white = { 255, 255, 255 },
    track = { 118, 118, 128, 0.16 }, accent = { 10, 132, 255 }, green = { 52, 199, 89 },
    gold = { 255, 204, 64 }, goldDeep = { 230, 142, 24 }, goldInk = { 168, 104, 0 }, amber = { 255, 160, 40 },
    claimInk = { 70, 40, 0 }, chest = { 176, 104, 52 }, chestDark = { 110, 58, 28 }, violet = { 150, 120, 190 },
  }
  local GLOSS_TOP, GLOSS_FOOT = { 255, 255, 255, 0.4 }, { 255, 255, 255, 0 }
  local CONFETTI_N = 48
  local CONF = { C.gold, C.green, { 120, 80, 255 }, { 40, 200, 220 }, { 255, 110, 170 }, C.accent }
  -- (the backdrop's eased colour, 0..255: for K.col / K.glow / K.ring only, never K.grad or K.mix, which
  -- keep what they make by the table)
  local TINT = { 160, 160, 160 }

  -- confetti (a fixed pool)
  local P = {}
  for i = 1, CONFETTI_N do P[i] = { live = false, x = 0, y = 0, vx = 0, vy = 0, t0 = 0, c = nil, spin = 0 } end
  local nextP = 1
  local function confetti(x, y)
    for i = 1, 22 do
      local p = P[nextP]
      nextP = nextP % CONFETTI_N + 1
      local a = (i / 22) * pi * 2 + sin(i * 2.7) * 0.4
      local v = 22 + (i * 17 % 30)
      p.live, p.x, p.y, p.vx, p.vy, p.t0 = true, x, y, cos(a) * v, sin(a) * v - 18, now()
      p.c, p.spin = CONF[i % #CONF + 1], (i * 0.37) % 1
    end
  end
  -- the motion's numbers (see the top), and where each goal (the bonus last) was drawn
  local mv = {
    lastT = nil, dt = 0, clock = 0, openAt = nil, coloured = false,
    r = 0.6, g = 0.6, b = 0.6, r2 = 1, g2 = 0.8, b2 = 0.3,
    hx = nil, hy = 0, hw = 0, hh = 0, top = 0, ring = 0, week = 0, claimed = nil, ringAt = -10,
    bar = { 0, 0, 0, 0, 0, 0, 0, 0 }, flash = { false, false, false, false, false, false, false, false },
    popAt = { -10, -10, -10, -10, -10, -10, -10, -10 }, endsMin = -1, endsOld = "", endsAt = -10,
  }
  W.motion = mv
  local rowX, rowY, rowW, rowH = {}, {}, {}, {}
  for i = 1, 8 do rowX[i], rowY[i], rowW[i], rowH[i] = 0, 0, 0, 0 end

  local function money(n, x, y, size, c, right)
    if not env.amount then return 0 end
    local ok, w = pcall(env.amount, n, 0, 0, size, c, true)
    w = ok and tonumber(w) or 0
    pcall(env.amount, n, right and x - w or x, y, size, c)
    return w
  end
  local function check(cx, cy, r, c, a)
    if r <= 0.05 then return end
    local G = K.graphics()
    K.col(c, a)
    G.circle("fill", K.X(cx), K.Y(cy), r * K.sc)
    G.setColor(1, 1, 1, (a or 1) * K.getFade())
    G.setLineWidth(max(1, r * 0.28 * K.sc))
    G.line(K.X(cx - r * 0.45), K.Y(cy), K.X(cx - r * 0.1), K.Y(cy + r * 0.35), K.X(cx + r * 0.5), K.Y(cy - r * 0.35))
  end
  -- something popping: drawn `s` times its size round cx, cy until popOut(s) (the transform only: the
  -- kit keeps its meshes by size, so a growing size would make new ones)
  local function popIn(cx, cy, s)
    if s == 1 then return end
    local G = K.graphics()
    G.push()
    G.translate(K.X(cx), K.Y(cy))
    G.scale(s, s)
    G.translate(-K.X(cx), -K.Y(cy))
  end
  local function popOut(s) if s ~= 1 then K.graphics().pop() end end
  -- a bump: 1, swelling by `by` and back over `dur` seconds after `at`
  local function bump(at, by, dur)
    local t = mv.clock - at
    if t < 0 or t >= dur then return 1 end
    return 1 + by * sin(pi * t / dur)
  end
  -- the ring of how many are claimed: gold to amber along the arc, a light at its end
  local function ring(cx, cy, r, k, width)
    local G = K.graphics()
    G.setLineWidth(max(1, width * K.sc))
    K.col(C.track)
    G.circle("line", K.X(cx), K.Y(cy), r * K.sc)
    if k > 0.001 then
      local pieces = 12
      local a0 = -pi / 2
      for i = 0, pieces - 1 do
        local s0, s1 = i / pieces, (i + 1) / pieces
        if s0 >= k then break end
        K.col(K.mix(C.gold, C.amber, s0))
        G.arc("line", "open", K.X(cx), K.Y(cy), r * K.sc, a0 + 2 * pi * s0, a0 + 2 * pi * min(k, s1), 8)
      end
      local ea = a0 + 2 * pi * k
      K.glow(cx + cos(ea) * r, cy + sin(ea) * r, width * 2.5, width * 2.5, C.gold, 0.6)
    end
  end
  -- a reward, centred on cy: money, or an item and how many -> its width
  local function reward(r, x, cy, right, a)
    if r.money then return money(r.money, x, cy - 4 * 0.6, 4, C.goldInk, right) end
    local tw = K.width(timesText(r.n), 3.6)
    local w = 10 + tw
    local x0 = right and x - w or x
    K.col(C.white, 0.55 * (a or 1))
    K.graphics().circle("fill", K.X(x0 + 4.5), K.Y(cy), 4.6 * K.sc)
    if env.itemIcon then
      pcall(env.itemIcon, r.item, x0 + 0.5, cy - 4, 8, (a or 1) * K.getFade())
      K.rescissor()
    end
    K.text(timesText(r.n), x0 + 10, cy - 3.6 * 0.6, 3.6, C.soft, nil, nil, a)
    return w
  end
  -- the bonus: a chest, centred on (cx, cy) closed; open and glowing once it's ready, the lid lifting
  local function chest(cx, cy, s, ready, opened, clock)
    if ready then K.glow(cx, cy, s * 1.6, s * 1.2, C.gold, 0.35 + 0.15 * sin(clock * 3)) end
    local w, h = s * 1.6, s
    cy = cy - h * 0.09
    local lift = (ready or opened) and (opened and s * 0.35 or s * 0.12 * (1 + sin(clock * 4))) or 0
    K.grad(K.R(cx - w / 2, cy - h * 0.1, w, h * 0.7), s * 0.12, C.chest, C.chestDark)
    K.col(C.gold)
    K.box("fill", K.R(cx - w / 2, cy + h * 0.12, w, h * 0.08))
    if ready or opened then
      K.col(C.gold, 0.9)
      K.box("fill", K.R(cx - w * 0.4, cy - h * 0.12 - lift * 0.3, w * 0.8, h * 0.12), s * 0.05)
    end
    K.grad(K.R(cx - w / 2, cy - h * 0.42 - lift, w, h * 0.36), s * 0.18, C.chest, C.chestDark)
    K.col(C.gold)
    K.box("fill", K.R(cx - s * 0.12, cy - h * 0.2 - lift, s * 0.24, s * 0.26), s * 0.05)
  end
  -- Claim: gold, breathing
  local function claimButton(cb, size, focused, clock)
    local rad = cb[4] / 2
    local pulse = 0.5 + 0.5 * sin(clock * 4)
    K.glow(cb[1] + cb[3] / 2, cb[2] + cb[4] / 2, cb[3] * 0.7, cb[4] * 1.4, C.gold, 0.2 + 0.15 * pulse)
    K.shadow(cb, rad, 0.8, 0.16)
    K.grad(cb, rad, C.gold, C.goldDeep)
    K.grad(K.R(cb[1] + 0.6, cb[2] + 0.4, cb[3] - 1.2, cb[4] * 0.5), rad * 0.8, GLOSS_TOP, GLOSS_FOOT)
    local label = T("challenges.claim")
    local cs = K.fit(label, size, cb[3] - 3)
    K.bold(label, cb[1], cb[2] + (cb[4] - cs * 1.2) / 2, cs, C.claimInk, "center", cb[3])
    if focused then K.focusRing(cb, rad) end
  end
  -- the countdown in its chip, the new minute rolling up in place of the last -> its width
  local function countdown(x, y, size)
    local mins = endsMinutes()
    if mv.endsMin ~= mins then
      if mv.endsMin >= 0 then mv.endsOld, mv.endsAt = endsText(mv.endsMin), mv.clock end
      mv.endsMin = mins
    end
    local text = endsText(mins)
    local ew = K.width(text, size) + 6
    local ch = size + 2.6
    K.col(C.gold, 0.26)
    K.box("fill", K.R(x, y, ew, ch), ch / 2)
    local fe = K.outCubic((mv.clock - mv.endsAt) / 0.35)
    if fe < 1 then K.text(mv.endsOld, x + 3, y + 1.3 - fe * 2.5, size, C.goldInk, nil, nil, 1 - fe) end
    K.text(text, x + 3, y + 1.3 + (1 - fe) * 2.5, size, C.goldInk, nil, nil, fe)
    return ew
  end

  local function drawRow(i, e, text, x, y, w, h, clock)
    local G = K.graphics()
    rowX[i], rowY[i], rowW[i], rowH[i] = x, y, w, h
    local look = LOOK[e.kind] or LOOK.catch
    local p, done = Ch.progress(e), Ch.done(e)
    local claimable = done and not e.claimed
    local a = e.claimed and 0.6 or 1
    -- (claimed just now: the goal pops, a gold light flaring from its tick)
    local f = st.flash[i] or false
    if mv.flash[i] ~= f then mv.flash[i], mv.popAt[i] = f, clock end
    local pt = clock - mv.popAt[i]
    local pop = bump(mv.popAt[i], 0.07, 0.5)
    local right = x + w - 4
    local cy = y + h / 2
    if pt < 0.9 then K.glow(right - 4, cy, 28, h * 1.3, C.gold, 0.55 * (1 - pt / 0.9)) end
    popIn(x + w / 2, cy, pop)
    if claimable then
      K.glow(x + w / 2, cy, w * 0.55, h * 0.9, look[2], 0.1 + 0.06 * sin(clock * 3 + i))
      K.col(look[2], 0.24 + 0.12 * sin(clock * 3 + i))
      K.box("fill", K.R(x - 1, y - 1, w + 2, h + 2), 5.5)
    end
    K.glass(K.R(x, y, w, h), 4.5, e.claimed and 0.32 or 0.5)
    -- (the badge: a disc in the kind's colour, its picture)
    local r = h * 0.3
    local bx = x + 4 + r
    K.glow(bx, cy, r * 1.6, r * 1.6, look[2], 0.16 * a)
    K.col(look[2], a)
    G.circle("fill", K.X(bx), K.Y(cy), r * K.sc)
    K.col(C.white, 0.28 * a)
    G.circle("fill", K.X(bx - r * 0.25), K.Y(cy - r * 0.3), r * 0.45 * K.sc)
    if env.glyph then pcall(env.glyph, G, look[1], K.X(bx), K.Y(cy), r * 2 * K.sc, a * K.getFade(), look[2]) end
    -- (the words, the bar easing to the count, a shimmer running along it)
    local tx = bx + r + 3.5
    local rw = 24
    local tw = right - rw - tx - 2
    K.text(text, tx, y + h * 0.16, K.fit(text, 4.2, tw), C.ink, nil, nil, a)
    mv.bar[i] = K.approach(mv.bar[i], p / max(1, e.goal), mv.dt, 5)
    local count = countText(p * 100000 + e.goal)
    local cw = K.width(count, 3.2)
    local bw = tw - max(16, cw + 3)
    local by = y + h * 0.64
    K.col(C.track, a)
    K.box("fill", K.R(tx, by, bw, 1.8), 0.9)
    if mv.bar[i] > 0.005 then
      local fw = bw * mv.bar[i]
      K.col(done and C.green or look[2], a)
      K.box("fill", K.R(tx, by, max(1.8, fw), 1.8), 0.9)
      local sh = (clock * 0.6 + i * 0.17) % 1.4
      if sh < 1 then
        K.col(C.white, 0.5 * a)
        K.box("fill", K.R(tx + fw * sh, by, min(4, fw * (1 - sh)), 1.8), 0.9)
      end
    end
    K.text(count, tx + tw - cw, by + 0.9 - 3.2 * 0.6, 3.2, C.soft, nil, nil, a)
    -- (the reward, Claim, or the tick popping in)
    if e.claimed then
      check(right - 4, cy, 3.4 * K.outBack(pt / 0.4), C.green)
    elseif claimable then
      local cb = K.R(right - rw, cy - 4.5, rw, 9)
      claimButton(cb, 4.2, st.keys and st.cursor == i, clock)
      K.addHit(cb, "win", CLAIM + i)
    else
      reward(e.reward, right, cy, true)
    end
    popOut(pop)
  end

  -- the bonus's line: the chest, its words, and the reward, Claim or the tick (all on its middle line)
  local function drawBonus(bb, small, clock)
    local s = session()
    local bonus = Ch.bonus(s)
    local ready = Ch.bonusReady(s)
    local i = #Ch.list(s) + 1
    rowX[i], rowY[i], rowW[i], rowH[i] = bb[1], bb[2], bb[3], bb[4]
    local f = st.flash[i] or false
    if mv.flash[i] ~= f then mv.flash[i], mv.popAt[i] = f, clock end
    local pt = clock - mv.popAt[i]
    local mid = bb[2] + bb[4] / 2
    if pt < 1.2 then K.glow(bb[1] + 9, mid, 30, 22, C.gold, 0.7 * (1 - pt / 1.2)) end
    K.col(C.gold, ready and (0.2 + 0.1 * sin(clock * 3)) or 0.12)
    K.box("fill", bb, 5)
    K.ring(bb, 5, C.gold, ready and 0.9 or 0.45, 0.45)
    local cs = small and 5 or 7
    local pop = bump(mv.popAt[i], 0.25, 0.5)
    popIn(bb[1] + 9, mid, pop)
    chest(bb[1] + 9, mid, cs, ready, bonus.claimed, clock)
    popOut(pop)
    local tx = bb[1] + (small and 17 or 18)
    local words = bb[3] - (tx - bb[1]) - 26
    if small then
      K.text(T("challenges.bonus"), tx, mid - 3.6 * 0.6, K.fit(T("challenges.bonus"), 3.6, words), C.ink)
    else
      local top = mid - (4 * 1.2 + 1 + 3.2 * 1.2) / 2
      K.bold(T("challenges.bonus"), tx, top, K.fit(T("challenges.bonus"), 4, words), C.ink)
      K.text(T("challenges.bonusNote"), tx, top + 4 * 1.2 + 1, K.fit(T("challenges.bonusNote"), 3.2, words), C.soft)
    end
    if bonus.claimed then
      check(bb[1] + bb[3] - 6, mid, 3.4 * K.outBack(pt / 0.4), C.green)
    elseif ready then
      local cb = K.R(bb[1] + bb[3] - 23, mid - 4.5, 21, 9)
      claimButton(cb, 4, st.keys and st.cursor == i, clock)
      K.addHit(cb, "win", BONUS)
    else
      reward(bonus, bb[1] + bb[3] - 3, mid, true)
    end
  end

  -- how many are claimed, eased; a bump of the ring when it changes
  local function claimedNow(list)
    local claimed = 0
    for i = 1, #list do if list[i].claimed then claimed = claimed + 1 end end
    if mv.claimed ~= claimed then
      if mv.claimed ~= nil then mv.ringAt = mv.clock end
      mv.claimed = claimed
    end
    mv.ring = K.approach(mv.ring, claimed / max(1, #list), mv.dt, 4)
    return claimed
  end
  -- (the week gone by: its bar filling)
  local function weekBar(x, y, w)
    mv.week = K.approach(mv.week, 1 - min(WEEK, st.endsSec or WEEK) / WEEK, mv.dt, 3)
    K.col(C.track)
    K.box("fill", K.R(x, y, w, 1.6), 0.8)
    if mv.week > 0.005 then
      K.col(C.gold)
      K.box("fill", K.R(x, y, max(1.6, w * mv.week), 1.6), 0.8)
    end
  end

  -- the week: the countdown, the week's bar, the ring of how many are claimed, the bonus chest
  local function drawWeek(x, y, w, h, list, clock)
    local G = K.graphics()
    K.glass(K.R(x, y, w, h), 6)
    K.bold(T("challenges.week"), x + 5, y + 4, 6, C.ink)
    countdown(x + 5, y + 12, 3.4)
    weekBar(x + 5, y + 20.5, w - 10)
    local claimed = claimedNow(list)
    local rr = min(w * 0.24, (h - 58) / 2)
    local cx, cy = x + w / 2, y + 27 + rr
    if rr > 4 then
      local pop = bump(mv.ringAt, 0.1, 0.45)
      popIn(cx, cy, pop)
      ring(cx, cy, rr, mv.ring, 2.4)
      K.bold(doneText(claimed), cx - rr, cy - 7 * 0.6, 7, C.ink, "center", rr * 2)
      popOut(pop)
      -- (all five: sparks circling)
      if claimed >= #list then
        for k = 0, 5 do
          local an = clock * 1.2 + k * pi / 3
          K.col(C.gold, 0.85)
          G.circle("fill", K.X(cx + cos(an) * (rr + 4)), K.Y(cy + sin(an) * (rr + 4)), 0.7 * K.sc)
        end
      end
    end
    drawBonus(K.R(x + 4, y + h - 24, w - 8, 20), false, clock)
  end

  -- (upright: the week's strip)
  local function drawStrip(x, y, w, h, list, clock)
    K.glass(K.R(x, y, w, h), 6)
    K.bold(T("challenges.week"), x + 4, y + 3, 5.4, C.ink)
    countdown(x + 4, y + 9.6, 3.2)
    local claimed = claimedNow(list)
    local pop = bump(mv.ringAt, 0.12, 0.45)
    popIn(x + w - 10, y + 9, pop)
    ring(x + w - 10, y + 9, 6, mv.ring, 1.6)
    K.text(doneText(claimed), x + w - 16, y + 9 - 3.2 * 0.6, 3.2, C.ink, "center", 12)
    popOut(pop)
    weekBar(x + 4, y + 16.4, w - 8)
    drawBonus(K.R(x + 2, y + 18.5, w - 4, h - 20.5), true, clock)
  end

  -- the highlight gliding to the chosen goal (or the bonus), in its colour
  local function drawGlide()
    if not st.keys then
      mv.hx = nil
      return
    end
    local i = st.cursor
    local tw = rowW[i]
    if not tw or tw == 0 then return end
    local tx, ty, th = rowX[i], rowY[i], rowH[i]
    if mv.hx == nil then mv.hx, mv.hy, mv.hw, mv.hh = tx, ty, tw, th end
    mv.hx, mv.hy = K.approach(mv.hx, tx, mv.dt, 22), K.approach(mv.hy, ty, mv.dt, 22)
    mv.hw, mv.hh = K.approach(mv.hw, tw, mv.dt, 22), K.approach(mv.hh, th, mv.dt, 22)
    local b = K.R(mv.hx, mv.hy, mv.hw, mv.hh)
    K.col(TINT, 0.12)
    K.box("fill", b, 4.5)
    K.ring(b, 4.5, TINT, 0.95, 0.6)
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
          local f = abs(cos(clock * 6 + p.spin * 4))
          G.rectangle("fill", -1.1 * K.sc, -0.5 * K.sc * f - 0.2 * K.sc, 2.2 * K.sc, 1 * K.sc * f + 0.4 * K.sc)
          G.pop()
        end
      end
    end
  end

  -- (the frame's clock; the backdrop's colours eased to the chosen goal's, gold for the bonus)
  local function track(clock, list)
    local dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT, mv.dt, mv.clock = clock, dt, clock
    if not mv.openAt then mv.openAt = clock end
    local e = list[st.cursor]
    local c1 = e and (LOOK[e.kind] or LOOK.catch)[2] or C.gold
    local c2 = e and C.gold or C.violet
    local rate = mv.coloured and 6 or 1000
    mv.coloured = true
    mv.r, mv.g, mv.b = K.approach(mv.r, c1[1] / 255, dt, rate), K.approach(mv.g, c1[2] / 255, dt, rate),
      K.approach(mv.b, c1[3] / 255, dt, rate)
    mv.r2, mv.g2, mv.b2 = K.approach(mv.r2, c2[1] / 255, dt, rate), K.approach(mv.g2, c2[2] / 255, dt, rate),
      K.approach(mv.b2, c2[3] / 255, dt, rate)
    TINT[1], TINT[2], TINT[3] = mv.r * 255, mv.g * 255, mv.b * 255
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    st.clip = body
    local s = session()
    local list = Ch.list(s)
    local words = texts(list)
    track(clock, list)
    K.backdrop(body, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2)
    -- (a claim since the last frame: confetti from where it was)
    for i = 1, #list + 1 do
      local f = st.flash[i]
      if f and f ~= st.burst and now() - f < 0.1 then
        st.burst = f
        confetti(rowX[i] + rowW[i] - 14, rowY[i] + 8)
      end
    end
    local since = clock - mv.openAt
    if not portrait and w >= 200 then
      local lw = floor((w - M * 3) * 0.36)
      local e0 = K.stagger(since, 0, 0.06, 0.34)
      K.rise(e0, 6)
      drawWeek(x + M, y + M, lw, h - M * 2, list, clock)
      K.settle(e0)
      local rx, rw = x + M * 2 + lw, w - lw - M * 3
      local rh = min(22, (h - M * 2 - (#list - 1) * 2) / max(1, #list))
      st.maxTop, st.top = 0, 0
      for i, e in ipairs(list) do
        local ei = K.stagger(since, i, 0.06, 0.32)
        K.rise(ei, 5)
        drawRow(i, e, words[i], rx, y + M + (i - 1) * (rh + 2), rw, rh, clock)
        K.settle(ei)
      end
      drawGlide()
    else
      -- (upright: the week's strip, then the goals, scrolling smoothly)
      local hh = 34
      local e0 = K.stagger(since, 0, 0.06, 0.34)
      K.rise(e0, 6)
      drawStrip(x + M, y + M, w - M * 2, hh, list, clock)
      K.settle(e0)
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
      mv.top = K.approach(mv.top, st.top, mv.dt, 16)
      K.scissor(area)
      for j, e in ipairs(list) do
        local ej = K.stagger(since, j, 0.06, 0.32)
        K.rise(ej, 5)
        drawRow(j, e, words[j], x + M, top + (j - 1) * (rh + 2) - mv.top, w - M * 2, rh, clock)
        K.settle(ej)
      end
      if st.cursor > #list then K.scissor(body) end
      drawGlide()
      K.scissor(body)
    end
    st.lastT = now()
    drawConfetti(clock)
    K.scissor(body)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), UI.red, UI.green, UI.hud) then st.toast = nil end
  end

  return W
end
