-- R-Bay: Team Rocket's auction house for Pokémon (the model is src/auction.lua, env.auction). Browse
-- the twelve running auctions: the Hot Auction on its own card at the top (the most wanted running
-- now), the list under it, the chosen one on the right (its picture on a glow in its tier's colour,
-- level, IVs, the price, the time left, the last bids, your maximum); or My Bids (the auctions you're
-- in, then how the ended ones went). A new bid flashes its price up; taking the lead throws
-- confetti; losing it says so.
--   buttons  Up / Down the auction, SELECT the Hot Auction, A bid (then < > one step, ^ v ten,
--            SELECT all you can, A place it, B back), L / R or START Browse | My Bids, B close
--   touch    tap an auction (or the Hot Auction), its - / + and Place Bid; the Browse | My Bids
--            switch; drag (or the wheel) scrolls the list
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, sin, cos, abs, pi = math.floor, math.max, math.min, math.sin, math.cos, math.abs, math.pi

local ROW_H, HEAD_H, M = 13, 10, 3
-- hit args: Browse rows 1.., My Bids rows MINE + i, the rest below
local MINE = 3000
local SEG_BROWSE, SEG_MINE = 2001, 2002
local STEP_MINUS, STEP_PLUS, STEP_GO = 2010, 2011, 2012
local HOT = 2020
local PARTICLES = 60

-- the Rocket look: a dark body, red accents; a colour per tier
local C = {
  bg = { 22, 22, 26 }, card = { 36, 36, 42 }, cardTop = { 46, 44, 52 }, cardHi = { 62, 62, 72 },
  line = { 255, 255, 255, 0.07 }, text = { 238, 238, 242 }, soft = { 152, 152, 162 }, faint = { 104, 104, 114 },
  red = { 226, 36, 48 }, redTop = { 240, 70, 72 }, redDeep = { 150, 18, 30 }, redSoft = { 226, 36, 48, 0.2 },
  green = { 64, 204, 112 }, gold = { 244, 192, 40 }, goldTop = { 255, 230, 120 }, goldDark = { 176, 120, 16 },
  bar = { 255, 255, 255, 0.1 }, ivTop = { 250, 90, 90 }, ivFoot = { 190, 24, 40 }, white = { 255, 255, 255 },
  heroTop = { 78, 18, 28 }, heroFoot = { 26, 12, 16 }, flameOut = { 255, 140, 30 }, flameIn = { 255, 230, 120 },
  shinyInk = { 74, 48, 0 }, wonTop = { 84, 66, 20 }, blue = { 70, 150, 255 }, pink = { 255, 92, 170 }, cyan = { 80, 220, 230 },
}
local CONFETTI = { C.gold, C.red, C.blue, C.pink, C.cyan, C.green, C.white, C.flameOut }
local TIER_C = {
  common = { 128, 128, 140 }, uncommon = { 52, 178, 92 }, rare = { 44, 124, 232 }, prized = { 152, 84, 224 },
  legendary = { 232, 170, 28 }, mythical = { 232, 82, 164 },
}
-- (each tier's colour, dark: the chosen one's header)
local TIER_DARK = {
  common = { 52, 52, 60 }, uncommon = { 22, 70, 40 }, rare = { 20, 50, 100 }, prized = { 60, 34, 96 },
  legendary = { 96, 70, 12 }, mythical = { 96, 30, 70 },
}
local TIER_RANK = { common = 1, uncommon = 2, rare = 3, prized = 4, legendary = 5, mythical = 6 }

-- (the words are keys of lang/*.lua, through env.T)
local HINTS = {
  list = { { "A", "hint.bid" }, { "SELECT", "hint.hot" }, { "L R", "hint.tab" }, { "B", "hint.close" } },
  step = { { "< >", "hint.step" }, { "^ v", "hint.ten" }, { "A", "hint.bid" }, { "B", "hint.back" } },
  mine = { { "A", "hint.open" }, { "L R", "hint.tab" }, { "B", "hint.close" } },
}
local TIER_KEY = {
  common = "auction.tier.common", uncommon = "auction.tier.uncommon", rare = "auction.tier.rare",
  prized = "auction.tier.prized", legendary = "auction.tier.legendary", mythical = "auction.tier.mythical",
}
local IV_LABEL = { "auction.ivHp", "auction.ivAtk", "auction.ivDef", "auction.ivSpa", "auction.ivSpd", "auction.ivSpe" }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, Au, T = env.K, env.auction, env.T or NO_T
  local W = { title = "R-Bay" }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end
  local function clockNow() return Au.now() end

  local st = {
    tab = "browse", focus = "list", cursor = 1, top = 0, visible = 6, key = nil, amount = 0,
    mineCursor = 1, mineTop = 0, rows = {}, mineRows = {}, mineN = 0, mineBids = 0, mineAt = -1, toast = nil,
    hotKey = nil,
  }
  W.state = st
  -- (opened from a notification: its tab, the auction it was about)
  local resume = ctx.resume
  if resume and resume.app == ctx.app and type(resume.state) == "table" then
    st.tab = resume.state.tab == "mine" and "mine" or "browse"
    st.key = resume.state.key
    if st.tab == "mine" and Au.seen then Au.seen() end
  end
  ctx.resume = nil

  -- the confetti: a fixed pool (no tables made after this)
  local P = {}
  for i = 1, PARTICLES do P[i] = { live = false, x = 0, y = 0, vx = 0, vy = 0, t0 = 0, life = 0, spin = 0, c = nil } end
  local nextP = 1
  local goAt = { x = 0, y = 0 }
  local function confetti(x, y, n)
    for i = 1, n do
      local p = P[nextP]
      nextP = nextP % PARTICLES + 1
      local a = -pi / 2 + (i / n - 0.5) * 2.6 + sin(i * 3.1) * 0.2
      local v = 35 + (i * 29 % 40)
      p.live, p.x, p.y, p.vx, p.vy, p.t0, p.life = true, x, y, cos(a) * v, sin(a) * v, now(), 1.7
      p.spin, p.c = (i * 0.37) % 1, CONFETTI[i % #CONFETTI + 1]
    end
  end
  -- sounds a moment apart (the engine plays one at a time)
  local seName, seAt = {}, {}
  local function seLater(name, delay)
    for i = 1, 3 do
      if not seName[i] then
        seName[i], seAt[i] = name, now() + delay
        return
      end
    end
  end
  local function seTick(t)
    for i = 1, 3 do
      if seName[i] and t >= seAt[i] then
        se(seName[i])
        seName[i] = nil
      end
    end
  end
  W.state.particles = P

  local levelText = K.textCache(function(n) return T.f("boxes.level", n) end)
  local bidsText = K.textCache(function(n) return n == 1 and T("auction.bid1") or T.f("auction.bids", n) end)
  local ivTotal = K.textCache(function(n) return T.f("auction.ivTotal", n) end)
  local numText = K.textCache(function(n) return tostring(n) end)
  -- time left: by the minute over a minute, by the second under it
  local leftText = K.textCache(function(k)
    if k <= 0 then return T("auction.ended") end
    if k < 60 then return T.f("auction.s", k) end
    local mins = floor(k / 60)
    if mins >= 60 then return T.f("auction.hm", floor(mins / 60), mins % 60) end
    return T.f("auction.m", mins)
  end)
  local function leftKey(secs)
    if secs <= 0 then return 0 end
    if secs < 60 then return secs end
    return floor(secs / 60) * 60
  end

  -- ------- the model, read

  local function listings() return Au.listings(session(), clockNow()) end
  local function current()
    local rows = listings()
    st.rows = rows
    -- (the chosen auction kept by its key while the list turns over)
    if st.key then
      for i, L in ipairs(rows) do
        if L.key == st.key then st.cursor = i break end
      end
    end
    st.cursor = max(1, min(st.cursor, #rows))
    local L = rows[st.cursor]
    st.key = L and L.key
    return L
  end
  local function clampList()
    local n = st.tab == "browse" and #st.rows or st.mineN
    local c, top = st.tab == "browse" and st.cursor or st.mineCursor, st.tab == "browse" and st.top or st.mineTop
    c = max(1, min(c, n))
    local vis = st.visible
    if c > top + vis then top = c - vis end
    if c <= top then top = c - 1 end
    top = max(0, min(top, max(0, n - vis)))
    if st.tab == "browse" then st.cursor, st.top = c, top else st.mineCursor, st.mineTop = c, top end
  end
  -- My Bids: the running bids, then the results (rows made once a second, not per frame)
  local function rebuildMine(force)
    local t = clockNow()
    if not force and t == st.mineAt then return end
    st.mineAt = t
    local rows = st.mineRows
    local bids = Au.mine(session(), t)
    local n = 0
    for _, b in ipairs(bids) do
      n = n + 1
      rows[n] = b
    end
    st.mineBids = n
    for _, r in ipairs(Au.results()) do
      n = n + 1
      rows[n] = r
    end
    for i = n + 1, #rows do rows[i] = nil end
    st.mineN = n
  end
  local function listingOf(key)
    for _, L in ipairs(st.rows) do if L.key == key then return L end end
    return nil
  end
  -- the Hot Auction: the rarest running (with more than a minute left), then the priciest, the most
  -- bid on, the ones ending within half an hour (picked once a second)
  local hotAt = -1
  local function pickHot(t)
    if t == hotAt then return end
    hotAt = t
    local best, bestScore = nil, -1
    for _, L in ipairs(st.rows) do
      local left = L.finish - t
      if left > 60 then
        -- (a shiny almost always: worth more than four tiers)
        local s = (TIER_RANK[L.tier] or 0) * 1000000 + (L.shiny and 4500000 or 0) + (L.value or 0) + L.nbids * 2000
          + (left < 1800 and 30000 or 0)
        if s > bestScore then best, bestScore = L, s end
      end
    end
    st.hotKey = best and best.key or nil
  end
  local function hotListing() return st.hotKey and listingOf(st.hotKey) or nil end
  local function toHot()
    local L = hotListing()
    if not L then return end
    for i, R in ipairs(st.rows) do if R == L then st.cursor = i end end
    st.key = L.key
    clampList()
    se("SE_SELECT")
  end

  local function toast(text, bad, sound)
    st.toast = { text = text, bad = bad, t = now() }
    se(sound or (bad and "SE_FAILURE" or "SE_SELECT"))
  end

  -- ------- bidding

  local function affordable(L)
    local s = session()
    local have = max(0, floor(tonumber(s and s.money) or 0))
    return have + (L.mine and Au.heldOf(L.mine) or 0)
  end
  local function setTab(tab)
    if st.tab == tab then return end
    st.tab, st.focus = tab, "list"
    if tab == "mine" then
      rebuildMine(true)
      Au.seen()
    end
    se("SE_SELECT")
  end
  local function begin()
    local L = current()
    if not L then return end
    if clockNow() >= L.finish - 30 then return toast(T("reason.auction.ended"), true) end
    local least = Au.minBid(L)
    if least > affordable(L) then return toast(T("reason.auction.money"), true) end
    st.focus, st.amount = "step", least
    se("SE_SELECT")
  end
  local function stepBy(n)
    local L = current()
    if not L then return end
    local a = st.amount
    for _ = 1, math.abs(n) do
      if n > 0 then a = a + Au.step(a) else a = a - Au.step(max(0, a - 1)) end
    end
    a = max(Au.minBid(L), min(max(Au.minBid(L), affordable(L)), a))
    if a ~= st.amount then
      st.amount = a
      se("SE_SELECT")
    end
  end
  local function place()
    local L = current()
    if not L then return end
    local ok, why = Au.bid(session(), L, st.amount, clockNow())
    if not ok then return toast(T(why and ("reason.auction." .. why) or "failed"), true) end
    st.focus = "list"
    if L.leader == 0 then
      -- (the lead: confetti from the button, a sparkle after the till)
      L.wasLead = true
      confetti(goAt.x, goAt.y, 40)
      toast(T("auction.leading"), false, "SE_SHOP")
      seLater("SE_SHINY", 0.35)
    else
      toast(T("auction.outbidNow"), true)
    end
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
      elseif pressed("select") then
        local L = current()
        if L then st.amount = max(Au.minBid(L), affordable(L)) end
        se("SE_SELECT")
      elseif pressed("a") then place()
      elseif pressed("b") then
        st.focus = "list"
        se("SE_SELECT")
      end
      return true
    end
    if pressed("b") then return false end
    if pressed("l") or pressed("r") or pressed("start") then
      setTab(st.tab == "browse" and "mine" or "browse")
      return true
    end
    if st.tab == "browse" then
      local d = nav.up and -1 or (nav.down and 1 or 0)
      if d ~= 0 and #st.rows > 0 then
        local c = max(1, min(#st.rows, st.cursor + d))
        if c ~= st.cursor then
          st.cursor = c
          st.key = st.rows[c].key
          clampList()
          se("SE_SELECT")
        end
      elseif pressed("select") then toHot()
      elseif pressed("a") then begin()
      end
    else
      local d = nav.up and -1 or (nav.down and 1 or 0)
      if d ~= 0 and st.mineN > 0 then
        local c = max(1, min(st.mineN, st.mineCursor + d))
        if c ~= st.mineCursor then
          st.mineCursor = c
          clampList()
          se("SE_SELECT")
        end
      elseif pressed("a") then
        -- (a running bid: to it in Browse, to raise it)
        local r = st.mineRows[st.mineCursor]
        if r and st.mineCursor <= st.mineBids and listingOf(r.key) then
          st.key, st.tab = r.key, "browse"
          current()
          clampList()
          se("SE_SELECT")
        end
      end
    end
    return true
  end

  function W.tap(arg)
    if type(arg) ~= "number" then return end
    if arg == SEG_BROWSE then return setTab("browse") end
    if arg == SEG_MINE then return setTab("mine") end
    if arg == STEP_MINUS or arg == STEP_PLUS then
      if st.focus ~= "step" then begin() end
      if st.focus == "step" then stepBy(arg == STEP_PLUS and 1 or -1) end
      return
    end
    if arg == STEP_GO then
      if st.focus ~= "step" then return begin() end
      return place()
    end
    if arg == HOT then
      local L = hotListing()
      if L and st.key == L.key then return begin() end
      st.focus = "list"
      return toHot()
    end
    if arg > MINE then
      local i = arg - MINE
      if st.mineRows[i] then
        if st.mineCursor == i and i <= st.mineBids and listingOf(st.mineRows[i].key) then
          st.key, st.tab = st.mineRows[i].key, "browse"
          current()
          clampList()
        else
          st.mineCursor = i
        end
        se("SE_SELECT")
      end
      return
    end
    if st.rows[arg] then
      st.focus = "list"
      if st.cursor == arg then return begin() end
      st.cursor, st.key = arg, st.rows[arg].key
      clampList()
      se("SE_SELECT")
    end
  end

  function W.scroll(dy)
    if st.tab == "browse" then
      st.top = max(0, min(max(0, #st.rows - st.visible), st.top - dy / ROW_H))
    else
      st.mineTop = max(0, min(max(0, st.mineN - st.visible), st.mineTop - dy / ROW_H))
    end
  end

  function W.hints()
    if st.focus == "step" then return T.list(HINTS.step) end
    return T.list(st.tab == "browse" and HINTS.list or HINTS.mine)
  end

  -- ------- drawing (no tables made here)

  local function G() return K.graphics() end
  local function money(n, x, y, size, c, right)
    if not env.amount then return 0 end
    local ok, w = pcall(env.amount, n, 0, 0, size, c, true)
    w = ok and tonumber(w) or 0
    pcall(env.amount, n, right and x - w or x, y, size, c)
    return w
  end
  local function pill(text, x, y, size, c, a)
    local w = K.width(text, size) + 3
    K.col(c, a)
    K.box("fill", K.R(x, y, w, size * 1.35), size * 0.6)
    K.text(text, x, y + size * 0.12, size, C.white, "center", w, a)
    return w
  end
  local function monIcon(sp, x, y, s)
    if env.monIcon then pcall(env.monIcon, sp, x, y, s) end
  end
  local function scaleAbout(cx, cy, k)
    local g = G()
    g.push()
    g.translate(K.X(cx), K.Y(cy))
    g.scale(k, k)
    g.translate(-K.X(cx), -K.Y(cy))
  end
  local function sparkle(cx, cy, s, c, a)
    local g = G()
    K.col(c, a)
    -- (two thin diamonds crossed: love's filled polygons have to be convex)
    local x, y, r, q = K.X(cx), K.Y(cy), s * K.sc, s * K.sc * 0.3
    g.polygon("fill", x, y - r, x + q, y, x, y + r, x - q, y)
    g.polygon("fill", x - r, y, x, y - q, x + r, y, x, y + q)
  end
  -- the Shiny badge: gold, a star at its left -> its width
  local function shinyBadge(x, y, size, clock)
    local word = T("auction.shiny")
    local w = K.width(word, size) + size * 1.6 + 3
    local b = K.R(x, y, w, size * 1.35)
    K.grad(b, size * 0.6, C.goldTop, C.goldDark)
    sparkle(x + size * 0.85, y + size * 0.68, size * 0.55 * (0.85 + 0.15 * sin((clock or 0) * 5)), C.white, 1)
    K.bold(word, x + size * 1.6, y + size * 0.12, size, C.shinyInk, "center", w - size * 1.6 - 1)
    return w
  end
  local function rays(cx, cy, r, clock, c, a)
    local g = G()
    g.push()
    g.translate(K.X(cx), K.Y(cy))
    g.rotate(clock * 0.5)
    K.col(c, a)
    local rr = r * K.sc
    for i = 0, 11 do
      local a0 = i * pi / 6
      g.polygon("fill", 0, 0, cos(a0) * rr, sin(a0) * rr, cos(a0 + 0.24) * rr, sin(a0 + 0.24) * rr)
    end
    g.pop()
  end
  -- a flickering flame, `s` units tall, its foot at cx, cy
  local function flame(cx, cy, s, clock)
    local g = G()
    local f = sin(clock * 13) * 0.08 + sin(clock * 7.3) * 0.06
    local x, y, sc = K.X(cx), K.Y(cy), s * K.sc
    K.col(C.flameOut)
    g.polygon("fill", x, y - sc * (1 + f), x + sc * 0.42, y - sc * 0.35, x + sc * 0.3, y, x - sc * 0.3, y, x - sc * 0.42, y - sc * 0.35)
    K.col(C.flameIn)
    g.polygon("fill", x + sc * f, y - sc * 0.62, x + sc * 0.2, y - sc * 0.2, x, y, x - sc * 0.2, y - sc * 0.2)
  end
  -- a light sweeping across b every `every` seconds
  local function shimmer(b, clock, every, a)
    local k = (clock % every) / 0.8
    if k >= 1 then return end
    local g = G()
    K.col(C.white, a)
    local sx = b[1] - 10 + (b[3] + 20) * k
    g.polygon("fill", K.X(sx), K.Y(b[2]), K.X(sx + 6), K.Y(b[2]), K.X(sx + 2), K.Y(b[2] + b[4]), K.X(sx - 4), K.Y(b[2] + b[4]))
  end
  -- a small arrow up (a price that just went up)
  local function upArrow(x, y, s, c, a)
    local g = G()
    K.col(c, a)
    g.polygon("fill", K.X(x), K.Y(y + s), K.X(x + s / 2), K.Y(y), K.X(x + s), K.Y(y + s))
  end

  -- a price just moved (a new bid): flash it a moment; you lost the lead: say so
  local function watch(L, clock)
    if L.seenPrice == nil then L.seenPrice = L.price end
    if L.price ~= L.seenPrice then
      L.seenPrice, L.flashT = L.price, clock
    end
    local lead = L.mine ~= nil and L.leader == 0
    if L.wasLead and L.mine and not lead then
      st.toast = { text = T("auction.outbidNow"), bad = true, t = now() }
      se("SE_FAILURE")
    end
    L.wasLead = lead
  end
  local function flashing(L, clock) return L.flashT and clock - L.flashT < 0.9 end

  -- the confetti (taking the lead)
  local function drawParticles(clock, body)
    local g = G()
    K.scissor(body)
    for i = 1, PARTICLES do
      local p = P[i]
      if p.live then
        local age = clock - p.t0
        if age > p.life then
          p.live = false
        elseif age >= 0 then
          local px, py = p.x + p.vx * age, p.y + p.vy * age + 55 * age * age
          local a = min(1, (p.life - age) / 0.4)
          g.push()
          g.translate(K.X(px), K.Y(py))
          g.rotate(clock * 8 + p.spin * 6)
          K.col(p.c, a)
          local f = abs(cos(clock * 6 + p.spin * 4))
          g.rectangle("fill", -1.2 * K.sc, -0.6 * K.sc * f - 0.2 * K.sc, 2.4 * K.sc, 1.2 * K.sc * f + 0.4 * K.sc)
          g.pop()
        end
      end
    end
    K.scissor(nil)
  end

  -- the Hot Auction: the most wanted running now, on its own card: rays in its tier's colour, the
  -- Pokémon bobbing on a glow, the flame, the price big and gold, the clock ticking down
  local function drawHot(x, y, w, h, clock, t)
    local L = hotListing()
    local b = K.R(x, y, w, h)
    K.shadow(b, 4, 0.8, 0.3)
    K.grad(b, 4, C.heroTop, C.heroFoot)
    if not L then return end
    watch(L, clock)
    local tc = TIER_C[L.tier]
    K.scissor(b)
    local ps = h - 6
    local ax, ay = x + 3 + ps / 2, y + h / 2
    rays(ax, ay, w * 0.7, clock, tc, 0.16)
    local g = G()
    for k = 3, 1, -1 do
      K.col(tc, 0.12 * k)
      g.circle("fill", K.X(ax), K.Y(ay), ps * (0.2 + 0.12 * (3 - k)) * K.sc)
    end
    local bob = sin(clock * 2.2) * 0.8
    if not (env.monPic and env.monPic(L.sp, ax - ps / 2, ay - ps / 2 + bob, ps, 1, L.picMon)) then
      monIcon(L.sp, ax - ps * 0.4, ay - ps * 0.4 + bob, ps * 0.8)
    end
    sparkle(ax - ps * 0.42, ay - ps * 0.3, 1 + 0.7 * abs(sin(clock * 3)), C.white, 0.9)
    sparkle(ax + ps * 0.45, ay + ps * 0.3, 0.9 + 0.6 * abs(sin(clock * 4 + 1)), tc, 0.9)
    -- (the words)
    local tx = x + ps + 7
    local tw = w - (tx - x) - 3
    -- (the tag: HOT AUCTION with its flame)
    local tag = T("auction.hot")
    local tgw = K.width(tag, 3.4) + 8
    local tb = K.R(x + w - tgw - 2, y + 2, tgw, 5.4)
    K.grad(tb, 2.7, C.flameOut, C.red)
    flame(tb[1] + 3, tb[2] + 4.8, 4.2, clock)
    K.bold(tag, tb[1] + 5.5, tb[2] + 0.9, 3.4, C.white)
    local ns = K.fit(L.name, 5.6, tw - tgw - 2)
    K.bold(L.name, tx, y + 2.6 + (5.6 - ns) * 0.5, ns, C.text)
    local pw = pill(T(TIER_KEY[L.tier]), tx, y + 9.3, 3.4, tc)
    K.text(levelText(L.level), tx + pw + 2, y + 9.4, 3.8, C.soft)
    if L.shiny then shinyBadge(tx + pw + 4 + K.width(levelText(L.level), 3.8), y + 9.3, 3.4, clock) end
    local fl = flashing(L, clock)
    if h < 32 then
      -- (a short card, a phone's: the price at the right under the tag, the bids under it, so the
      -- tier and level keep their row)
      local right = x + w - 3
      local mw = money(L.price, right, y + 8.6, 7, fl and C.white or C.gold, true)
      if fl then upArrow(right - mw - 4.5, y + 10.4, 3, C.green, 1) end
      K.text(bidsText(L.nbids), tx, y + h - 4.9, 3.6, C.soft, "right", right - tx)
    else
      local mw = money(L.price, tx, y + h - 12.5, 7, fl and C.white or C.gold)
      if fl then upArrow(tx + mw + 1.5, y + h - 11, 3, C.green, 1) end
      K.text(bidsText(L.nbids), tx + mw + (fl and 6 or 2), y + h - 10.6, 3.6, C.soft)
    end
    local left = L.finish - t
    local urgent = left < 600
    local la = urgent and (0.6 + 0.4 * abs(sin(clock * 5))) or 1
    K.text(T("auction.endsIn"), tx, y + h - 4.8, 3.4, C.faint)
    K.text(leftText(leftKey(left)), tx + K.width(T("auction.endsIn"), 3.4) + 1.5, y + h - 4.9, 3.6,
      urgent and C.red or C.text, nil, nil, la)
    shimmer(b, clock + 1.3, 3.4, 0.1)
    K.scissor(nil)
    K.ring(b, 4, tc, 0.45 + 0.3 * sin(clock * 3), 0.6)
    if st.key == L.key then K.ring(K.R(x - 0.8, y - 0.8, w + 1.6, h + 1.6), 4.6, C.gold, 0.9, 0.7) end
    K.addHit(b, "win", HOT)
  end

  -- one auction's row: the tier down its side, the icon, the name and its price (flashing up on a
  -- new bid); its tier, level, your standing, the time left (red and pulsing near the end)
  local function drawRow(L, i, x, ry, w, on, focused, t, clip, clock)
    watch(L, clock)
    local rb = K.R(x + 1.5, ry + 0.4, w - 3, ROW_H - 0.8)
    local tc = TIER_C[L.tier]
    if on then
      K.col(tc, focused and 0.24 or 0.14)
      K.box("fill", rb, 2.5)
      K.ring(rb, 2.5, tc, focused and 0.8 or 0.4, 0.5)
    end
    K.col(tc)
    K.box("fill", K.R(rb[1] + 0.6, rb[2] + 1.6, 1.1, rb[4] - 3.2), 0.5)
    if L.tier == "legendary" or L.tier == "mythical" then
      K.scissor(rb)
      shimmer(rb, clock + i * 0.5, 2.8, 0.1)
      K.scissor(clip)
    end
    monIcon(L.sp, x + 3.5, ry + 1.5, 10)
    local fl = flashing(L, clock)
    local pw = money(L.price, x + w - 4, ry + 1.8, 4.6, fl and C.gold or C.text, true)
    if fl then upArrow(x + w - 7.5 - pw, ry + 2.6, 2.6, C.green, 1 - (clock - L.flashT) / 0.9) end
    local hot = L.key == st.hotKey
    local ns = K.fit(L.name, 4.6, w - 26 - pw - (hot and 4 or 0))
    K.bold(L.name, x + 15, ry + 1.8 + (4.6 - ns) * 0.5, ns, C.text)
    if hot then flame(x + 17 + K.width(L.name, ns) + 1.5, ry + 6, 3.6, clock) end
    local px = x + 15
    px = px + pill(T(TIER_KEY[L.tier]), px, ry + 7.3, 3.4, tc) + 2
    K.text(levelText(L.level), px, ry + 7.4, 3.8, C.soft)
    px = px + K.width(levelText(L.level), 3.8) + 2
    if L.shiny then px = px + shinyBadge(px, ry + 7.3, 3.4, clock) + 2 end
    if L.mine then
      local lead = L.leader == 0
      pill(T(lead and "auction.winning" or "auction.outbid"), px, ry + 7.3, 3.4, lead and C.green or C.red,
        lead and 1 or (0.6 + 0.4 * abs(sin(clock * 4))))
    end
    local left = L.finish - t
    local urgent = left < 600
    K.text(leftText(leftKey(left)), x + w - 4 - 30, ry + 7.4, 3.8, urgent and C.red or C.soft, "right", 30, urgent and
      (0.55 + 0.45 * abs(sin(clock * 5))) or 1)
    if not on then
      K.col(C.line)
      K.box("fill", K.R(x + 15, ry + ROW_H - 0.2, w - 17, 0.25))
    end
    K.addHit(rb, "win", i, clip)
  end

  local function drawBrowseList(x, y, w, h, focused, t, clock)
    K.grad(K.R(x, y, w, h), 4, C.cardTop, C.card)
    st.visible = max(1, floor((h - 2) / ROW_H))
    clampList()
    local clip = K.R(x, y + 1, w, h - 2)
    K.scissor(clip)
    local first = floor(st.top) + 1
    local last = min(#st.rows, first + st.visible + 1)
    for i = first, last do
      drawRow(st.rows[i], i, x, y + 1 + (i - 1 - st.top) * ROW_H, w, i == st.cursor, focused, t, clip, clock)
    end
    K.scrollbar(x + w, y + 1, h - 2, st.top, st.visible, #st.rows)
    K.scissor(nil)
  end

  -- the IVs: two columns of three (the stat, its value, a bar; gold and sparkling at 31), the total
  local function drawIvs(L, x, y, w, clock)
    K.text(ivTotal(L.ivSum), x, y, 3.8, C.soft)
    local cw = (w - 3) / 2
    for i, key in ipairs(Au.IV_KEYS) do
      local col, row = (i - 1) % 2, floor((i - 1) / 2)
      local cx, cy = x + col * (cw + 3), y + 5 + row * 5
      local v = L.ivs[key] or 0
      local top = v == 31
      K.text(T(IV_LABEL[i]), cx, cy, 3.6, C.soft)
      K.text(numText(v), cx + 9, cy, 3.6, top and C.gold or C.text, "right", 6)
      local bx, bw = cx + 16.5, cw - 17
      K.col(C.bar)
      K.box("fill", K.R(bx, cy + 1.1, bw, 2.2), 1.1)
      local fw = max(2.2, bw * v / 31)
      if top then
        K.grad(K.R(bx, cy + 1.1, fw, 2.2), 1.1, C.goldTop, C.goldDark)
        sparkle(bx + fw - 0.5, cy + 2.2, 1 + 0.6 * abs(sin(clock * 5 + i)), C.white, 0.9)
      else
        K.grad(K.R(bx, cy + 1.1, fw, 2.2), 1.1, C.ivTop, C.ivFoot)
      end
    end
  end

  -- the chosen auction: who (on a glow in its tier's colour), what it's worth so far, the last bids,
  -- your maximum and Place Bid (breathing, a shine across it)
  local function drawDetail(L, x, y, w, h, t, compact, clock)
    local b = K.R(x, y, w, h)
    K.grad(b, 4, C.cardTop, C.card)
    if not L then return end
    local tc = TIER_C[L.tier]
    local ps = compact and 18 or 26
    local ax, ay = x + 3 + ps / 2, y + 3 + ps / 2
    -- (the header tinted by the tier, rays behind the rare ones)
    K.grad(K.R(x, y, w, ps + 6), 4, TIER_DARK[L.tier], C.card)
    K.scissor(K.R(x, y, w, ps + 6))
    if L.tier == "legendary" or L.tier == "mythical" or L.tier == "prized" then rays(ax, ay, ps * 1.1, clock, tc, 0.18) end
    local g = G()
    for k = 3, 1, -1 do
      K.col(tc, 0.1 * k)
      g.circle("fill", K.X(ax), K.Y(ay), ps * (0.2 + 0.12 * (3 - k)) * K.sc)
    end
    K.scissor(nil)
    local drawn = env.monPic and env.monPic(L.sp, x + 3, y + 3, ps, 1, L.picMon)
    if not drawn then monIcon(L.sp, x + 3 + ps * 0.1, y + 3 + ps * 0.1, ps * 0.8) end
    local tx = x + ps + 6
    local ns = K.fit(L.name, 5.4, w - (tx - x) - 3)
    K.bold(L.name, tx, y + 3.5 + (5.4 - ns) * 0.5, ns, C.text)
    local pw = pill(T(TIER_KEY[L.tier]), tx, y + 10.3, 3.6, tc)
    K.text(levelText(L.level), tx + pw + 2, y + 10.4, 4, C.soft)
    if L.shiny then shinyBadge(tx + pw + 4 + K.width(levelText(L.level), 4), y + 10.3, 3.6, clock) end
    if not compact and L.types ~= "" then K.text(L.types, tx, y + 16, 3.8, C.faint, "left", w - (tx - x) - 3) end
    local yy = y + ps + 6
    if not compact then
      drawIvs(L, x + 4, yy, w - 8, clock)
      yy = yy + 21
    end
    -- the price, the bids, the time left; your standing
    K.text(T(L.nbids > 0 and "auction.current" or "auction.starting"), x + 4, yy, 3.8, C.soft)
    local left = L.finish - t
    local urgent = left < 600
    K.text(leftText(leftKey(left)), x + w - 4 - 34, yy, 3.8, urgent and C.red or C.soft, "right", 34,
      urgent and (0.55 + 0.45 * abs(sin(clock * 5))) or 1)
    local fl = flashing(L, clock)
    local pk = fl and (1 + 0.12 * sin((clock - L.flashT) / 0.9 * pi)) or 1
    scaleAbout(x + 4, yy + 7.4, pk)
    local mw = money(L.price, x + 4, yy + 4.4, 6, fl and C.gold or C.text)
    G().pop()
    local bt = bidsText(L.nbids)
    K.text(bt, x + 6 + mw, yy + 5.6, 3.8, C.soft)
    -- (your standing beside it: winning or outbid)
    if L.mine then
      local lead = L.leader == 0
      pill(T(lead and "auction.winning" or "auction.outbid"), x + 8 + mw + K.width(bt, 3.8), yy + 5.3, 3.4,
        lead and C.green or C.red, lead and 1 or (0.6 + 0.4 * abs(sin(clock * 4))))
    end
    yy = yy + 12
    -- the last bids, newest first (while there's room above the bid controls)
    local room = floor((y + h - 27 - yy) / 4.6)
    local nh = min(L.histN, 5, max(0, room))
    for j = 0, nh - 1 do
      local i = (L.histN - 1 - j) % 5 + 1
      local who = L.histWho[i]
      local name = who == 0 and T("auction.you") or (L.bidders[who] and L.bidders[who].name or "?")
      K.text(name, x + 4, yy, 3.6, who == 0 and C.red or C.faint, "left", w - 30)
      money(L.histAmt[i], x + w - 4, yy, 3.6, j == 0 and C.soft or C.faint, true)
      yy = yy + 4.6
    end
    -- your maximum: - / + and the amount, then Place Bid (Raise while you're in it)
    local stepping = st.focus == "step"
    -- (not stepping: your maximum while it leads, else the least you could bid)
    local amount = stepping and st.amount or (L.mine and L.leader == 0 and L.mine.max or Au.minBid(L))
    local sb = K.R(x + 4, y + h - 25, 22, 10)
    K.grad(sb, 3.2, C.cardHi, C.card)
    K.col(C.line)
    K.box("fill", K.R(sb[1] + 11, sb[2] + 2.2, 0.3, 5.6))
    K.text("-", sb[1], sb[2] + 1.4, 6, C.text, "center", 11)
    K.text("+", sb[1] + 11, sb[2] + 1.6, 6, C.text, "center", 11)
    K.addHit(K.R(sb[1], sb[2], 11, 10), "win", STEP_MINUS)
    K.addHit(K.R(sb[1] + 11, sb[2], 11, 10), "win", STEP_PLUS)
    if stepping then K.focusRing(sb, 3.2) end
    K.text(T("auction.max"), sb[1] + 25, sb[2] + 0.4, 3.4, C.soft)
    money(amount, sb[1] + 25, sb[2] + 4.2, 5, (stepping or L.mine) and C.goldTop or C.faint)
    local go = K.R(x + 4, y + h - 13, w - 8, 10)
    local ended = left <= 30
    if ended then
      K.col(C.cardHi)
      K.box("fill", go, 3.2)
    else
      local p = 0.5 + 0.5 * sin(clock * 4)
      K.col(C.red, 0.25 * p)
      K.box("fill", K.R(go[1] - 1.5, go[2] - 1.5, go[3] + 3, go[4] + 3), 4.5)
      K.grad(go, 3.2, C.redTop, C.redDeep)
      K.scissor(go)
      shimmer(go, clock, 3.2, 0.3)
      K.scissor(nil)
    end
    if stepping then K.focusRing(go, 3.2) end
    local label = T(L.mine and "auction.raise" or "auction.place")
    local fs = K.fit(label, 4.8, go[3] - 3)
    K.bold(label, go[1], go[2] + (go[4] - fs * 1.2) / 2, fs, ended and C.faint or C.white, "center", go[3])
    K.addHit(go, "win", STEP_GO)
    goAt.x, goAt.y = go[1] + go[3] / 2, go[2]
  end

  -- My Bids: the running ones (your max, winning or outbid, the time left), then the results (a win
  -- in gold, sparkling)
  local function drawMine(x, y, w, h, t, clock)
    K.grad(K.R(x, y, w, h), 4, C.cardTop, C.card)
    st.visible = max(1, floor((h - 2) / ROW_H))
    clampList()
    local clip = K.R(x, y + 1, w, h - 2)
    K.scissor(clip)
    if st.mineN == 0 then
      K.text(T("auction.none"), x, y + h / 2 - 3, 4.6, C.faint, "center", w)
    end
    local first = floor(st.mineTop) + 1
    local last = min(st.mineN, first + st.visible + 1)
    for i = first, last do
      local r = st.mineRows[i]
      local ry = y + 1 + (i - 1 - st.mineTop) * ROW_H
      local rb = K.R(x + 1.5, ry + 0.4, w - 3, ROW_H - 0.8)
      local running = i <= st.mineBids
      local L = running and listingOf(r.key) or nil
      local lead = L and L.leader == 0
      local stripe = running and (L and (lead and C.green or C.red) or C.faint) or (r.won and C.gold or C.faint)
      if r.won and not running then
        K.grad(rb, 2.5, C.wonTop, C.card)
        sparkle(x + 12, ry + 2.5, 1 + 0.6 * abs(sin(clock * 4 + i)), C.goldTop, 0.9)
      end
      if i == st.mineCursor then
        K.col(C.redSoft)
        K.box("fill", rb, 2.5)
      end
      K.col(stripe, (running and not lead and L) and (0.55 + 0.45 * abs(sin(clock * 4))) or 1)
      K.box("fill", K.R(rb[1] + 0.6, rb[2] + 1.6, 1.1, rb[4] - 3.2), 0.5)
      monIcon(r.sp, x + 3.5, ry + 1.5, 10)
      local ns = K.fit(r.name or "?", 4.6, w - 60)
      K.bold(r.name or "?", x + 15, ry + 1.8 + (4.6 - ns) * 0.5, ns, C.text)
      local px = x + 15
      px = px + pill(T(TIER_KEY[r.tier] or TIER_KEY.common), px, ry + 7.3, 3.4, TIER_C[r.tier] or TIER_C.common) + 2
      K.text(levelText(r.level or 1), px, ry + 7.4, 3.8, C.soft)
      if r.shiny then shinyBadge(px + K.width(levelText(r.level or 1), 3.8) + 2, ry + 7.3, 3.4, clock) end
      if running then
        local tag = T(L and (lead and "auction.winning" or "auction.outbid") or "auction.ended")
        K.text(tag, x + w - 4 - 40, ry + 1.8, 4.2, L and (lead and C.green or C.red) or C.soft, "right", 40)
        K.text(leftText(leftKey((r.finish or 0) - t)), x + w - 4 - 30, ry + 7.4, 3.8, C.soft, "right", 30)
      else
        K.bold(T(r.won and "auction.won" or "auction.lost"), x + w - 4 - 40, ry + 1.8, 4.2,
          r.won and C.gold or C.soft, "right", 40)
        local note = r.won and T(r.where == "pc" and "auction.toPc" or "auction.toParty") or T("auction.refunded")
        local nw = K.width(note, 3.6)
        K.text(note, x + w - 4 - nw, ry + 7.5, 3.6, C.faint)
        if r.won then money(r.price or 0, x + w - 6 - nw, ry + 7.5, 3.6, C.soft, true) end
      end
      if i ~= st.mineCursor then
        K.col(C.line)
        K.box("fill", K.R(x + 15, ry + ROW_H - 0.2, w - 17, 0.25))
      end
      K.addHit(rb, "win", MINE + i, clip)
    end
    K.scrollbar(x + w, y + 1, h - 2, st.mineTop, st.visible, st.mineN)
    K.scissor(nil)
  end

  -- the head: the R, Browse | My Bids (a count while results are unread), the money
  local function drawHead(x, y, w, clock)
    K.grad(K.R(x, y + 1, 8, 8), 2, C.redTop, C.redDeep)
    K.bold("R", x, y + 1.9, 5.4, C.white, "center", 8)
    local sx, sw = x + 11, min(70, w * 0.5)
    K.col(C.card)
    K.box("fill", K.R(sx, y + 1, sw, 8), 2.6)
    local half = sw / 2
    for i = 1, 2 do
      local on = (i == 1) == (st.tab == "browse")
      local b = K.R(sx + 0.5 + (i - 1) * half, y + 1.5, half - 1, 7)
      if on then K.grad(b, 2.2, C.cardHi, C.card) end
      local label = T(i == 1 and "auction.browse" or "auction.mine")
      local fs = K.fit(label, 4.2, half - 4)
      if on then K.bold(label, b[1], b[2] + 1.3, fs, C.text, "center", b[3])
      else K.text(label, b[1], b[2] + 1.3, fs, C.soft, "center", b[3]) end
      K.addHit(b, "win", i == 1 and SEG_BROWSE or SEG_MINE)
    end
    local unread = Au.unread()
    if unread > 0 then
      local g = G()
      local bx, by = sx + sw - 1.5, y + 1.5
      local k = 1 + 0.12 * abs(sin(clock * 3))
      K.col(C.red)
      g.circle("fill", K.X(bx), K.Y(by), 2.6 * k * K.sc)
      K.text(numText(unread), bx - 3, by - 1.6, 3.2, C.white, "center", 6)
    end
    local s = session()
    money(max(0, floor(tonumber(s and s.money) or 0)), x + w - 1, y + 2.4, 5, C.text, true)
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local t = clockNow()
    seTick(now())
    K.col(C.bg)
    K.box("fill", body)
    local L = current()
    pickHot(t)
    if st.tab == "mine" then rebuildMine(false) end
    drawHead(x + M, y + 1, w - M * 2, clock)
    local top = y + HEAD_H + 1.5
    local bodyH = y + h - M - top
    if st.tab == "mine" then
      drawMine(x + M, top, w - M * 2, bodyH, t, clock)
    elseif portrait then
      -- (the whole detail -- types, IVs, the last bids -- when it fits, the list takes what's left)
      local dh = min(122, bodyH * 0.56)
      local hh = min(30, (bodyH - dh) * 0.3)
      -- (too short for the Hot Auction's three lines, a small window's: the list has its room; SELECT
      -- still goes to it)
      local gap = M
      if hh < 22 then hh, gap = 0, 0 end
      local lh = bodyH - dh - hh - gap - M
      if hh > 0 then drawHot(x + M, top, w - M * 2, hh, clock, t) end
      drawBrowseList(x + M, top + hh + gap, w - M * 2, lh, st.focus == "list", t, clock)
      K.scissor(body)
      drawDetail(L, x + M, top + hh + gap + lh + M, w - M * 2, dh, t, dh < 92, clock)
    else
      local lw = floor((w - M * 3) * 0.52)
      local hh = min(34, bodyH * 0.38)
      drawHot(x + M, top, lw, hh, clock, t)
      drawBrowseList(x + M, top + hh + M, lw, bodyH - hh - M, st.focus == "list", t, clock)
      K.scissor(body)
      drawDetail(L, x + M * 2 + lw, top, w - M * 3 - lw, bodyH, t, bodyH < 80, clock)
    end
    drawParticles(clock, body)
    K.scissor(body)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), C.red, C.green, K.UI.hud) then
      st.toast = nil
    end
  end

  current()
  return W
end
