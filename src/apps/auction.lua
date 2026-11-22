-- R-Bay: Team Rocket's auction house for Pokémon (the model is src/auction.lua, env.auction). Browse
-- the twelve running auctions: the Hot Auction on its own card at the top (the most wanted running
-- now), the list under it, the chosen one on the right (its picture on a glow in its tier's colour,
-- level, IVs, the price, the time left, the last bids, your maximum); or My Bids (the auctions you're
-- in, then how the ended ones went; A on one that ended tells it again, as eBay does: that it's
-- over, the Pokémon, the winning bid, who won it, your maximum, what you paid or got back, where it
-- went, the last bids). A new bid flashes its price up; taking the lead throws confetti; losing it
-- says so. Dark glass: smoked panes over the Rocket dark, soft red lights drifting behind them and one in
-- the shown Pokémon's type colour (eased as it changes); the chosen row's highlight glides, Browse | My
-- Bids' thumb slides, the cards and rows rise in one after another as a tab (or a recap) opens.
--   buttons  Up / Down the auction, SELECT the Hot Auction, A bid (then < > one step, ^ v ten,
--            SELECT all you can, A place it, B back), L / R or START Browse | My Bids, B close;
--            My Bids: A a running bid (to it in Browse) or an ended one (its recap; B back)
--   touch    tap an auction (or the Hot Auction), its - / + and Place Bid; the Browse | My Bids
--            switch; a row of My Bids twice; the recap's < ; drag (or the wheel) scrolls the list
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, sin, cos, abs, pi = math.floor, math.max, math.min, math.sin, math.cos, math.abs, math.pi

local ROW_H, HEAD_H, M = 13, 10, 3
-- hit args: Browse rows 1.., My Bids rows MINE + i, the rest below
local MINE = 3000
local SEG_BROWSE, SEG_MINE = 2001, 2002
local STEP_MINUS, STEP_PLUS, STEP_GO, STEP_MAX = 2010, 2011, 2012, 2013
local HOT = 2020
local RECAP_BACK = 2030
local PARTICLES = 60

-- the Rocket look: a dark body (lit behind its glass), red accents; a colour per tier
local C = {
  bg = { 16, 14, 19 },
  line = { 255, 255, 255, 0.08 }, text = { 240, 238, 244 }, soft = { 160, 158, 170 }, faint = { 116, 114, 126 },
  red = { 226, 36, 48 }, redTop = { 240, 70, 72 }, redDeep = { 150, 18, 30 },
  green = { 64, 204, 112 }, gold = { 244, 192, 40 }, goldTop = { 255, 230, 120 }, goldDark = { 176, 120, 16 },
  bar = { 255, 255, 255, 0.1 }, ivTop = { 250, 90, 90 }, ivFoot = { 190, 24, 40 }, white = { 255, 255, 255 },
  heroTop = { 78, 18, 28 }, flameOut = { 255, 140, 30 }, flameIn = { 255, 230, 120 },
  shinyInk = { 74, 48, 0 }, blue = { 70, 150, 255 }, pink = { 255, 92, 170 }, cyan = { 80, 220, 230 },
}
local CONFETTI = { C.gold, C.red, C.blue, C.pink, C.cyan, C.green, C.white, C.flameOut }
local TIER_C = {
  common = { 128, 128, 140 }, uncommon = { 52, 178, 92 }, rare = { 44, 124, 232 }, prized = { 152, 84, 224 },
  legendary = { 232, 170, 28 }, mythical = { 232, 82, 164 },
}
-- the glass: smoked panes over the backdrop's lights (Rocket reds and the shown Pokémon's type); each
-- tier's colour washing down from the chosen one's header, a win's gold down its row; a pane's sheen
local GLASS = { 12, 10, 14 }
local TIER_WASH, TIER_CLEAR = {}, {}
for k, c in pairs(TIER_C) do
  TIER_WASH[k], TIER_CLEAR[k] = { c[1], c[2], c[3], 0.34 }, { c[1], c[2], c[3], 0 }
end
local WON_WASH, WON_CLEAR = { 244, 192, 40, 0.22 }, { 244, 192, 40, 0 }
local SHEEN, SHEEN_END = { 255, 255, 255, 0.22 }, { 255, 255, 255, 0 }
-- (a type's colour by the first three letters of the game's name for it: FIRE, FIGHT, PSYCHC ...)
local TYPE_C = {
  nor = { 168, 168, 120 }, fig = { 192, 48, 40 }, fly = { 168, 144, 240 }, poi = { 160, 64, 160 },
  gro = { 224, 192, 104 }, roc = { 184, 160, 56 }, bug = { 168, 184, 32 }, gho = { 112, 88, 152 },
  ste = { 184, 184, 208 }, fir = { 240, 128, 48 }, wat = { 104, 144, 240 }, gra = { 120, 200, 80 },
  ele = { 248, 208, 48 }, psy = { 248, 88, 136 }, ice = { 152, 216, 216 }, dra = { 112, 56, 248 },
  dar = { 112, 88, 72 }, fai = { 238, 153, 172 },
}
local TIER_RANK = { common = 1, uncommon = 2, rare = 3, prized = 4, legendary = 5, mythical = 6 }

-- (the words are keys of lang/*.lua, through env.T)
local HINTS = {
  list = { { "A", "hint.bid" }, { "SELECT", "hint.hot" }, { "L R", "hint.tab" }, { "B", "hint.close" } },
  step = { { "< >", "hint.step" }, { "^ v", "hint.ten" }, { "A", "hint.bid" }, { "B", "hint.back" } },
  mine = { { "A", "hint.open" }, { "L R", "hint.tab" }, { "B", "hint.close" } },
  recap = { { "B", "hint.back" }, { "L R", "hint.tab" } },
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
    tab = "browse", focus = "list", cursor = 1, top = 0, visible = 6, key = nil, amount = 0, rowH = ROW_H,
    mineCursor = 1, mineTop = 0, rows = {}, mineRows = {}, mineN = 0, mineBids = 0, mineAt = -1, toast = nil,
    hotKey = nil, recap = nil, recapBurst = false,
  }
  W.state = st
  -- the motion's numbers: the frame's dt, when the tab / the recap last changed (what rises in after
  -- it), the gliding highlights (their rows, as offsets in the list), the switch's thumb, the backdrop's
  -- light in the shown Pokémon's colour (eased; its numbers changed in place)
  local mv = {
    lastT = nil, clock = 0, dt = 0, tab = nil, tabAt = -10, recap = nil, recapAt = -10,
    rowY = nil, rowTop = 0, mineY = nil, mineTop = 0, thumb = nil, lit = { 226, 36, 48 }, litOn = false,
  }
  W.motion = mv
  -- (opened from a notification: its tab, the auction it was about; a win or a loss opens its recap,
  -- below, once the rows are made)
  local resume = ctx.resume
  local resumeKey
  if resume and resume.app == ctx.app and type(resume.state) == "table" then
    st.tab = resume.state.tab == "mine" and "mine" or "browse"
    st.key = resume.state.key
    if st.tab == "mine" then
      resumeKey = st.key
      if Au.seen then Au.seen() end
    end
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

  -- how long ago an auction ended: by the minute, the hour, the day
  local agoText = K.textCache(function(m)
    if m < 1 then return T("auction.ago.now") end
    if m < 60 then return T.f("auction.ago.m", m) end
    if m < 1440 then return T.f("auction.ago.h", floor(m / 60)) end
    return T.f("auction.ago.d", floor(m / 1440))
  end)
  local function agoKey(secs)
    local m = floor(max(0, secs) / 60)
    if m < 60 then return m end
    if m < 1440 then return floor(m / 60) * 60 end
    return floor(m / 1440) * 1440
  end
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
  -- (keeps the chosen row in view, unless the list was scrolled by hand since the last press: a drag
  -- or the wheel would otherwise be pulled straight back to it on the next frame)
  local function clampList(follow)
    if follow then st.free = false end
    local n = st.tab == "browse" and #st.rows or st.mineN
    local c, top = st.tab == "browse" and st.cursor or st.mineCursor, st.tab == "browse" and st.top or st.mineTop
    c = max(1, min(c, n))
    local vis = st.visible
    if not st.free then
      if c > top + vis then top = c - vis end
      if c <= top then top = c - 1 end
    end
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
    clampList(true)
    se("SE_SELECT")
  end

  local function toast(text, bad, sound)
    st.toast = { text = text, bad = bad, t = now() }
    se(sound or (bad and "SE_FAILURE" or "SE_SELECT"))
  end

  -- ------- bidding

  local function affordable(L)
    local s = session()
    local have = (env.money and env.money(s) or max(0, floor(tonumber(s and s.money) or 0)))
    return have + (L.mine and Au.heldOf(L.mine) or 0)
  end
  -- an ended auction's recap (a result row of My Bids), and back
  local function openRecap(i)
    local r = st.mineRows[i]
    if not r or i <= st.mineBids then return false end
    st.mineCursor = i
    st.recap = Au.recap and Au.recap(session(), r) or nil
    if not st.recap then return false end
    st.recapBurst = st.recap.won
    se(st.recap.won and "SE_SHOP" or "SE_SELECT")
    if st.recap.won then seLater("SE_SHINY", 0.3) end
    return true
  end
  local function closeRecap()
    st.recap = nil
    se("SE_SELECT")
  end
  local function setTab(tab)
    if st.tab == tab then return end
    st.tab, st.focus, st.recap = tab, "list", nil
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
  -- (by touch: - / + held repeat it, tens after a moment; the amount tapped is the most you can bid, as SELECT)
  local hold = K.newHold()
  local function stepping(d)
    if st.recap then hold.d = nil return false end
    if st.focus ~= "step" then begin() end
    -- (a hold that can't bid stops: one refusal, not one a repeat)
    if st.focus ~= "step" then hold.d = nil return false end
    if d then stepBy(d) end
    return true
  end
  local function stepMax()
    local L = current()
    if not L then return end
    st.amount = max(Au.minBid(L), affordable(L))
    se("SE_SELECT")
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
        stepMax()
      elseif pressed("a") then place()
      elseif pressed("b") then
        st.focus = "list"
        se("SE_SELECT")
      end
      return true
    end
    if st.recap then
      if pressed("b") or pressed("a") then closeRecap()
      elseif pressed("l") or pressed("r") or pressed("start") then setTab("browse") end
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
          clampList(true)
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
          clampList(true)
          se("SE_SELECT")
        end
      elseif pressed("a") then
        -- (a running bid: to it in Browse, to raise it; an ended one: its recap)
        local r = st.mineRows[st.mineCursor]
        if r and st.mineCursor <= st.mineBids and listingOf(r.key) then
          st.key, st.tab = r.key, "browse"
          current()
          clampList(true)
          se("SE_SELECT")
        elseif r then
          openRecap(st.mineCursor)
        end
      end
    end
    return true
  end

  function W.tap(arg)
    if type(arg) ~= "number" then return end
    if arg == SEG_BROWSE then return setTab("browse") end
    if arg == SEG_MINE then
      if st.recap and st.tab == "mine" then return closeRecap() end
      return setTab("mine")
    end
    if arg == RECAP_BACK then return closeRecap() end
    if st.recap then return end
    if arg == STEP_MINUS or arg == STEP_PLUS then
      stepping(arg == STEP_PLUS and 1 or -1)
      return
    end
    if arg == STEP_MAX then
      if stepping() then stepMax() end
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
        if st.mineCursor == i and i > st.mineBids then return openRecap(i) end
        if st.mineCursor == i and listingOf(st.mineRows[i].key) then
          st.key, st.tab = st.mineRows[i].key, "browse"
          current()
          clampList(true)
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
      clampList(true)
      se("SE_SELECT")
    end
  end

  function W.pointer(phase, x, y, id) return K.holdPointer(hold, phase, x, y, id, W.scroll) end
  function W.scroll(dy)
    if st.recap then return end
    st.free = true
    if st.tab == "browse" then
      st.top = max(0, min(max(0, #st.rows - st.visible), st.top - dy / st.rowH))
    else
      st.mineTop = max(0, min(max(0, st.mineN - st.visible), st.mineTop - dy / st.rowH))
    end
  end

  function W.hints()
    if st.focus == "step" then return T.list(HINTS.step) end
    if st.recap then return T.list(HINTS.recap) end
    return T.list(st.tab == "browse" and HINTS.list or HINTS.mine)
  end

  -- ------- drawing (no tables made here)

  local function G() return K.graphics() end
  -- (the text size past 100%: 0 at Normal, 0.3 at Larger; set each frame. Room that grows with it is
  -- this times so many units: nothing moves at 100%)
  local gx = 0
  local function money(n, x, y, size, c, right)
    if not env.amount then return 0 end
    local ok, w = pcall(env.amount, n, 0, 0, size, c, true)
    w = ok and tonumber(w) or 0
    pcall(env.amount, n, right and x - w or x, y, size, c)
    return w
  end
  local function moneyW(n, size)
    if not env.amount then return 0 end
    local ok, w = pcall(env.amount, n, 0, 0, size, C.text, true)
    return ok and tonumber(w) or 0
  end
  -- (a pill as tall as its words: grown round its middle with the text size)
  local function pill(text, x, y, size, c, a)
    local w = K.width(text, size) + 3
    local gh = size * 1.35 * gx
    K.col(c, a)
    K.box("fill", K.R(x, y - gh / 2, w, size * 1.35 + gh), size * 0.6 * (1 + gx))
    K.text(text, x, y + size * 0.12, size, C.white, "center", w, a)
    return w
  end
  local function monIcon(sp, x, y, s)
    if env.monIcon then pcall(env.monIcon, sp, x, y, s, 0, 1, 1, 1, K.getFade()) end
  end
  local function monPic(sp, x, y, s, picMon)
    local drawn = env.monPic and env.monPic(sp, x, y, s, K.getFade(), picMon)
    K.rescissor()
    return drawn
  end
  -- a pane of the smoked glass
  local function pane(b, rad, a) K.glass(b, rad or 4, a or 0.52, GLASS, 0.14, 0.15) end
  -- something rising in: drawn at `e` of itself -> the fade to put back
  local function fadeTo(e)
    local f = K.getFade()
    K.setFade(f * e)
    return f
  end
  -- a type's colour from the game's words for it ("FIRE / FLYING": the first), kept per words
  local typeC = {}
  local function typeColour(types)
    if type(types) ~= "string" or types == "" then return nil end
    local c = typeC[types]
    if c == nil then
      c = TYPE_C[types:sub(1, 3):lower()] or false
      typeC[types] = c
    end
    return c or nil
  end
  -- the backdrop: the Rocket dark with soft lights drifting over it, two reds and the shown Pokémon's
  local function backdrop(b, clock)
    local x, y, w, h = b[1], b[2], b[3], b[4]
    K.col(C.bg)
    K.box("fill", b)
    K.scissor(b)
    K.glow(x + w * (0.8 + 0.06 * sin(clock * 0.11)), y + h * (0.16 + 0.08 * cos(clock * 0.09)), w * 0.55, h * 0.75,
      C.red, 0.22)
    K.glow(x + w * (0.2 + 0.08 * cos(clock * 0.07)), y + h * (0.86 + 0.06 * sin(clock * 0.1)), w * 0.5, h * 0.7,
      mv.lit, 0.2)
    K.glow(x + w * (0.48 + 0.1 * sin(clock * 0.05 + 1)), y + h * (0.5 + 0.1 * cos(clock * 0.06)), w * 0.34, h * 0.5,
      C.redDeep, 0.3)
    K.glow(x + w * (0.06 + 0.05 * cos(clock * 0.08)), y + h * (0.1 + 0.06 * sin(clock * 0.12)), w * 0.3, h * 0.45,
      C.pink, 0.07)
  end
  -- a highlight's sheen and its edge (the chosen row, the switch's thumb)
  local function lit(b, rad, c, a, ring)
    K.col(c, a)
    K.box("fill", b, rad)
    K.grad(K.R(b[1], b[2], b[3], b[4] * 0.55), rad, SHEEN, SHEEN_END)
    K.ring(b, rad, c, ring, 0.5)
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
    local gh = size * 1.35 * gx
    local b = K.R(x, y - gh / 2, w, size * 1.35 + gh)
    K.grad(b, size * 0.6 * (1 + gx), C.goldTop, C.goldDark)
    sparkle(x + size * 0.85, y + size * 0.68, size * 0.55 * (0.85 + 0.15 * sin((clock or 0) * 5)), C.white, 1)
    K.bold(word, x + size * 1.6, y + size * 0.12, size, C.shinyInk, "center", w - size * 1.6 - 1)
    return w
  end
  local function shinyW(size) return K.width(T("auction.shiny"), size) + size * 1.6 + 3 end
  -- a row's line of pills (tier, level, Shiny, your standing) bigger than its room: the size to draw them
  -- at, back towards 100% (never under it), so they stop short of what's at the right
  -- (ps the pills' size, 3.4 unless given; ls the level's, 3.8)
  local function pillsK(tierWord, lv, shiny, stand, room, ps, ls)
    if gx <= 0 then return 1 end
    ps, ls = ps or 3.4, ls or 3.8
    -- (what grows with the size, and what doesn't: the pills' ends and the gaps)
    local grows, fixed = K.width(tierWord, ps) + K.width(lv, ls), 7
    if shiny then grows, fixed = grows + shinyW(ps) - 3, fixed + 5 end
    if stand then grows, fixed = grows + K.width(stand, ps), fixed + 3 end
    if grows + fixed <= room then return 1 end
    return max(1 / (1 + gx), (room - fixed) / grows)
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
    -- (the Rocket's red in the glass, its tier's light behind the Pokémon)
    K.glass(b, 4, 0.55, C.heroTop, 0.18, 0.16)
    if not L then return end
    watch(L, clock)
    local tc = TIER_C[L.tier]
    K.scissor(b)
    local ps = h - 6
    local ax, ay = x + 3 + ps / 2, y + h / 2
    rays(ax, ay, w * 0.7, clock, tc, 0.16)
    K.glow(ax, ay, ps * 0.75, ps * 0.7, tc, 0.42)
    local g = G()
    for k = 3, 1, -1 do
      K.col(tc, 0.08 * k)
      g.circle("fill", K.X(ax), K.Y(ay), ps * (0.2 + 0.12 * (3 - k)) * K.sc)
    end
    local bob = sin(clock * 2.2) * 0.8
    if not monPic(L.sp, ax - ps / 2, ay - ps / 2 + bob, ps, L.picMon) then
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
    local fl = flashing(L, clock)
    -- (the tier, level and Shiny stop short of the price beside them on a short card)
    local tier, lv = T(TIER_KEY[L.tier]), levelText(L.level)
    local k = pillsK(tier, lv, L.shiny, nil, h < 32 and tw - moneyW(L.price, 7) - 6 or tw)
    local pw = pill(tier, tx, y + 9.3, 3.4 * k, tc)
    K.text(lv, tx + pw + 2, y + 9.4, 3.8 * k, C.soft)
    local pend = tx + pw + 2 + K.width(lv, 3.8 * k)
    if L.shiny then pend = pend + 2 + shinyBadge(tx + pw + 4 + K.width(lv, 3.8 * k), y + 9.3, 3.4 * k, clock) end
    if h < 32 then
      -- (a short card, a phone's: the price at the right under the tag, the bids under it, so the
      -- tier and level keep their row)
      local right = x + w - 3
      -- (and the price, if they still meet, back towards its 100% size too)
      local psz = 7
      if gx > 0 then
        local pw7 = moneyW(L.price, 7)
        if pw7 > right - pend - 2 then psz = 7 * max(1 / (1 + gx), (right - pend - 2) / pw7) end
      end
      local mw = money(L.price, right, y + 8.6 + (7 - psz) * 0.5, psz, fl and C.white or C.gold, true)
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
    -- (on a short card it stops short of the bids at its right: smaller, back towards 100%, if it must)
    local ends, lt = T("auction.endsIn"), leftText(leftKey(left))
    local ek = 1
    if gx > 0 and h < 32 then
      local room = w - (tx - x) - 3 - K.width(bidsText(L.nbids), 3.6) - 2.5
      local ew = K.width(ends, 3.4) + 1.5 + K.width(lt, 3.6)
      if ew > room then ek = max(1 / (1 + gx), (room - 1.5) / (ew - 1.5)) end
    end
    K.text(ends, tx, y + h - 4.8, 3.4 * ek, C.faint)
    K.text(lt, tx + K.width(ends, 3.4 * ek) + 1.5, y + h - 4.9, 3.6 * ek, urgent and C.red or C.text, nil, nil, la)
    shimmer(b, clock + 1.3, 3.4, 0.1)
    K.scissor(nil)
    K.ring(b, 4, tc, 0.45 + 0.3 * sin(clock * 3), 0.6)
    if st.key == L.key then K.ring(K.R(x - 0.8, y - 0.8, w + 1.6, h + 1.6), 4.6, C.gold, 0.9, 0.7) end
    K.addHit(b, "win", HOT)
  end

  -- one auction's row: the tier down its side, the icon, the name and its price (flashing up on a
  -- new bid); its tier, level, your standing, the time left (red and pulsing near the end)
  -- (the chosen row's highlight is the list's, gliding under the rows)
  local function drawRow(L, i, x, ry, w, on, t, clip, clock)
    watch(L, clock)
    local rh = st.rowH
    -- (a row taller with the text size: its first line a little lower, its second more, the icon centred)
    local d1, d2 = (rh - ROW_H) * 0.25, (rh - ROW_H) * 0.8
    local rb = K.R(x + 1.5, ry + 0.4, w - 3, rh - 0.8)
    local tc = TIER_C[L.tier]
    K.col(tc)
    K.box("fill", K.R(rb[1] + 0.6, rb[2] + 1.6, 1.1, rb[4] - 3.2), 0.5)
    if L.tier == "legendary" or L.tier == "mythical" then
      K.scissor(rb)
      shimmer(rb, clock + i * 0.5, 2.8, 0.1)
      K.scissor(clip)
    end
    monIcon(L.sp, x + 3.5, ry + 1.5 + (rh - ROW_H) * 0.5, 10)
    local fl = flashing(L, clock)
    local pw = money(L.price, x + w - 4, ry + 1.8 + d1, 4.6, fl and C.gold or C.text, true)
    if fl then upArrow(x + w - 7.5 - pw, ry + 2.6 + d1, 2.6, C.green, 1 - (clock - L.flashT) / 0.9) end
    local hot = L.key == st.hotKey
    local ns = K.fit(L.name, 4.6, w - 26 - pw - (hot and 4 or 0))
    K.bold(L.name, x + 15, ry + 1.8 + d1 + (4.6 - ns) * 0.5, ns, C.text)
    if hot then flame(x + 17 + K.width(L.name, ns) + 1.5, ry + 6 + d1, 3.6, clock) end
    local left = L.finish - t
    local urgent = left < 600
    local lt = leftText(leftKey(left))
    local lead = L.mine and L.leader == 0
    local stand = L.mine and T(lead and "auction.winning" or "auction.outbid") or nil
    local tier, lv = T(TIER_KEY[L.tier]), levelText(L.level)
    local k = pillsK(tier, lv, L.shiny, stand, w - 21 - K.width(lt, 3.8))
    local px = x + 15
    px = px + pill(tier, px, ry + 7.3 + d2, 3.4 * k, tc) + 2
    K.text(lv, px, ry + 7.4 + d2, 3.8 * k, C.soft)
    px = px + K.width(lv, 3.8 * k) + 2
    if L.shiny then px = px + shinyBadge(px, ry + 7.3 + d2, 3.4 * k, clock) + 2 end
    if stand then
      pill(stand, px, ry + 7.3 + d2, 3.4 * k, lead and C.green or C.red, lead and 1 or (0.6 + 0.4 * abs(sin(clock * 4))))
    end
    K.text(lt, x + w - 4 - 30, ry + 7.4 + d2, 3.8, urgent and C.red or C.soft, "right", 30, urgent and
      (0.55 + 0.45 * abs(sin(clock * 5))) or 1)
    if not on then
      K.col(C.line)
      K.box("fill", K.R(x + 15, ry + rh - 0.2, w - 17, 0.25))
    end
    K.addHit(rb, "win", i, clip)
  end

  -- a list's highlight, gliding to the chosen row (`rel` its offset in the list; a scroll moves it with
  -- the rows) -> its offset now
  local function glide(cur, rel, top, lastTop)
    if cur == nil then return rel end
    return K.approach(cur - (top - lastTop) * st.rowH, rel, mv.dt, 24)
  end
  local function drawBrowseList(x, y, w, h, focused, t, clock)
    pane(K.R(x, y, w, h), 4)
    st.visible = max(1, floor((h - 2) / st.rowH))
    clampList()
    local clip = K.R(x, y + 1, w, h - 2)
    K.scissor(clip)
    local C0 = st.rows[st.cursor]
    if C0 then
      mv.rowY = glide(mv.rowY, (st.cursor - 1 - st.top) * st.rowH, st.top, mv.rowTop)
      local tc = TIER_C[C0.tier]
      lit(K.R(x + 1.5, y + 1.4 + mv.rowY, w - 3, st.rowH - 0.8), 2.5, tc, focused and 0.24 or 0.14, focused and 0.8 or 0.4)
    end
    mv.rowTop = st.top
    local first = floor(st.top) + 1
    local last = min(#st.rows, first + st.visible + 1)
    local since = mv.clock - mv.tabAt
    for i = first, last do
      -- (the rows rising in one after another as the tab opens)
      local e = K.stagger(since, i - first, 0.035, 0.28)
      local f = fadeTo(e)
      drawRow(st.rows[i], i, x, y + 1 + (i - 1 - st.top) * st.rowH + (1 - e) * 4, w, i == st.cursor, t, clip, clock)
      K.setFade(f)
    end
    K.scrollbar(x + w, y + 1, h - 2, st.top, st.visible, #st.rows)
    K.scissor(nil)
  end

  -- the IVs: two columns of three (the stat, its value, a bar; gold and sparkling at 31), the total
  local function drawIvs(L, x, y, w, clock)
    K.text(ivTotal(L.ivSum), x, y, 3.8, C.soft)
    local cw = (w - 3) / 2
    -- (the stats' words and their numbers take what they grew with the text size; the bars give it up)
    local lg, ng = 0, 0
    if gx > 0 then
      local k = 1 / (1 + gx)
      for i = 1, #IV_LABEL do
        local s = T(IV_LABEL[i])
        lg = max(lg, K.width(s, 3.6) - K.width(s, 3.6 * k))
      end
      ng = K.width("00", 3.6) - K.width("00", 3.6 * k)
    end
    for i, key in ipairs(Au.IV_KEYS) do
      local col, row = (i - 1) % 2, floor((i - 1) / 2)
      local cx, cy = x + col * (cw + 3), y + 5 + row * 5
      local v = L.ivs[key] or 0
      local top = v == 31
      K.text(T(IV_LABEL[i]), cx, cy, 3.6, C.soft)
      K.text(numText(v), cx + 9 + lg, cy, 3.6, top and C.gold or C.text, "right", 6 + ng)
      local bx, bw = cx + 16.5 + lg + ng, cw - 17 - lg - ng
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
    pane(b, 4)
    if not L then return end
    local tc = TIER_C[L.tier]
    local ps = compact and 18 or 26
    local ax, ay = x + 3 + ps / 2, y + 3 + ps / 2
    -- (the header washed in the tier's colour, its light behind the Pokémon, rays behind the rare ones)
    K.grad(K.R(x, y, w, ps + 6), 4, TIER_WASH[L.tier], TIER_CLEAR[L.tier])
    K.scissor(K.R(x, y, w, ps + 6))
    if L.tier == "legendary" or L.tier == "mythical" or L.tier == "prized" then rays(ax, ay, ps * 1.1, clock, tc, 0.18) end
    K.glow(ax, ay, ps * 0.7, ps * 0.65, tc, 0.4)
    local g = G()
    for k = 3, 1, -1 do
      K.col(tc, 0.07 * k)
      g.circle("fill", K.X(ax), K.Y(ay), ps * (0.2 + 0.12 * (3 - k)) * K.sc)
    end
    K.scissor(nil)
    local drawn = monPic(L.sp, x + 3, y + 3, ps, L.picMon)
    if not drawn then monIcon(L.sp, x + 3 + ps * 0.1, y + 3 + ps * 0.1, ps * 0.8) end
    local tx = x + ps + 6
    local ns = K.fit(L.name, 5.4, w - (tx - x) - 3)
    K.bold(L.name, tx, y + 3.5 + (5.4 - ns) * 0.5, ns, C.text)
    local tier, lv = T(TIER_KEY[L.tier]), levelText(L.level)
    local k = pillsK(tier, lv, L.shiny, nil, w - (tx - x) - 3, 3.6, 4)
    local pw = pill(tier, tx, y + 10.3, 3.6 * k, tc)
    K.text(lv, tx + pw + 2, y + 10.4, 4 * k, C.soft)
    if L.shiny then shinyBadge(tx + pw + 4 + K.width(lv, 4 * k), y + 10.3, 3.6 * k, clock) end
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
    -- (the price a little further under its label at a bigger text size, while the bid controls leave room)
    local py = yy + max(0, min(gx * 3, y + h - 25 - (yy + 12)))
    scaleAbout(x + 4, py + 7.4, pk)
    local mw = money(L.price, x + 4, py + 4.4, 6, fl and C.gold or C.text)
    G().pop()
    local bt = bidsText(L.nbids)
    K.text(bt, x + 6 + mw, py + 5.6, 3.8, C.soft)
    -- (your standing beside it: winning or outbid)
    if L.mine then
      local lead = L.leader == 0
      local stand = T(lead and "auction.winning" or "auction.outbid")
      local px = x + 8 + mw + K.width(bt, 3.8)
      -- (back towards 100% when it would run past the card's edge)
      local sk = 1
      if gx > 0 then sk = max(1 / (1 + gx), min(1, (x + w - 3 - px - 3) / K.width(stand, 3.4))) end
      pill(stand, px, py + 5.3, 3.4 * sk, lead and C.green or C.red, lead and 1 or (0.6 + 0.4 * abs(sin(clock * 4))))
    end
    yy = py + 12
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
    K.glass(sb, 3.2, 0.08, C.white, 0.7, 0.22)
    K.col(C.line)
    K.box("fill", K.R(sb[1] + 11, sb[2] + 2.2, 0.3, 5.6))
    K.text("-", sb[1], sb[2] + 1.4, 6, C.text, "center", 11)
    K.text("+", sb[1] + 11, sb[2] + 1.6, 6, C.text, "center", 11)
    local mb, pb = K.R(sb[1], sb[2], 11, 10), K.R(sb[1] + 11, sb[2], 11, 10)
    K.addHit(mb, "win", STEP_MINUS)
    K.addHit(pb, "win", STEP_PLUS)
    K.holdZone(hold, mb, -1)
    K.holdZone(hold, pb, 1)
    K.addHit(K.R(sb[1] + 23, sb[2], x + w - 4 - (sb[1] + 23), 10), "win", STEP_MAX)
    if stepping then K.focusRing(sb, 3.2) end
    K.text(T("auction.max"), sb[1] + 25, sb[2] + 0.4, 3.4, C.soft)
    money(amount, sb[1] + 25, sb[2] + 4.2 + gx * 2, 5, (stepping or L.mine) and C.goldTop or C.faint)
    local go = K.R(x + 4, y + h - 13, w - 8, 10)
    local ended = left <= 30
    if ended then
      K.glass(go, 3.2, 0.06, C.white, 0.4, 0.14)
    else
      local p = 0.5 + 0.5 * sin(clock * 4)
      K.glow(go[1] + go[3] / 2, go[2] + go[4] / 2, go[3] * 0.62, go[4] * 1.3, C.red, 0.16 + 0.14 * p)
      K.grad(go, 3.2, C.redTop, C.redDeep)
      K.grad(K.R(go[1], go[2], go[3], go[4] * 0.5), 3.2, SHEEN, SHEEN_END)
      K.ring(go, 3.2, C.white, 0.22, 0.35)
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
    pane(K.R(x, y, w, h), 4)
    st.visible = max(1, floor((h - 2) / st.rowH))
    clampList()
    local clip = K.R(x, y + 1, w, h - 2)
    K.scissor(clip)
    if st.mineN == 0 then
      K.text(T("auction.none"), x, y + h / 2 - 3, 4.6, C.faint, "center", w)
    end
    if st.mineRows[st.mineCursor] then
      mv.mineY = glide(mv.mineY, (st.mineCursor - 1 - st.mineTop) * st.rowH, st.mineTop, mv.mineTop)
      lit(K.R(x + 1.5, y + 1.4 + mv.mineY, w - 3, st.rowH - 0.8), 2.5, C.red, 0.2, 0.45)
    end
    mv.mineTop = st.mineTop
    local first = floor(st.mineTop) + 1
    local last = min(st.mineN, first + st.visible + 1)
    local since = mv.clock - mv.tabAt
    for i = first, last do
      local e = K.stagger(since, i - first, 0.035, 0.28)
      local f = fadeTo(e)
      local r = st.mineRows[i]
      local ry = y + 1 + (i - 1 - st.mineTop) * st.rowH + (1 - e) * 4
      local rb = K.R(x + 1.5, ry + 0.4, w - 3, st.rowH - 0.8)
      local running = i <= st.mineBids
      local L = running and listingOf(r.key) or nil
      local lead = L and L.leader == 0
      local stripe = running and (L and (lead and C.green or C.red) or C.faint) or (r.won and C.gold or C.faint)
      if r.won and not running then
        K.grad(rb, 2.5, WON_WASH, WON_CLEAR)
        sparkle(x + 12, ry + 2.5, 1 + 0.6 * abs(sin(clock * 4 + i)), C.goldTop, 0.9)
      end
      K.col(stripe, (running and not lead and L) and (0.55 + 0.45 * abs(sin(clock * 4))) or 1)
      K.box("fill", K.R(rb[1] + 0.6, rb[2] + 1.6, 1.1, rb[4] - 3.2), 0.5)
      -- (as Browse's rows: taller with the text size, the lines apart)
      local d1, d2 = (st.rowH - ROW_H) * 0.25, (st.rowH - ROW_H) * 0.8
      monIcon(r.sp, x + 3.5, ry + 1.5 + (st.rowH - ROW_H) * 0.5, 10)
      local ns = K.fit(r.name or "?", 4.6, w - 60)
      K.bold(r.name or "?", x + 15, ry + 1.8 + d1 + (4.6 - ns) * 0.5, ns, C.text)
      -- (the pills stop short of the right side's second line)
      local lt = running and leftText(leftKey((r.finish or 0) - t)) or nil
      local note = not running and (r.won and T(r.where == "pc" and "auction.toPc" or "auction.toParty") or T("auction.refunded"))
      local nw = note and K.width(note, 3.6) or 0
      local rw = lt and K.width(lt, 3.8) or (nw + (r.won and 2 + moneyW(r.price or 0, 3.6) or 0))
      local tier, lv = T(TIER_KEY[r.tier] or TIER_KEY.common), levelText(r.level or 1)
      local k = pillsK(tier, lv, r.shiny, nil, w - 21 - rw)
      local px = x + 15
      px = px + pill(tier, px, ry + 7.3 + d2, 3.4 * k, TIER_C[r.tier] or TIER_C.common) + 2
      K.text(lv, px, ry + 7.4 + d2, 3.8 * k, C.soft)
      if r.shiny then shinyBadge(px + K.width(lv, 3.8 * k) + 2, ry + 7.3 + d2, 3.4 * k, clock) end
      if running then
        local tag = T(L and (lead and "auction.winning" or "auction.outbid") or "auction.ended")
        K.text(tag, x + w - 4 - 40, ry + 1.8 + d1, 4.2, L and (lead and C.green or C.red) or C.soft, "right", 40)
        K.text(lt, x + w - 4 - 30, ry + 7.4 + d2, 3.8, C.soft, "right", 30)
      else
        K.bold(T(r.won and "auction.won" or "auction.lost"), x + w - 4 - 40, ry + 1.8 + d1, 4.2,
          r.won and C.gold or C.soft, "right", 40)
        K.text(note, x + w - 4 - nw, ry + 7.5 + d2, 3.6, C.faint)
        if r.won then money(r.price or 0, x + w - 6 - nw, ry + 7.5 + d2, 3.6, C.soft, true) end
      end
      if i ~= st.mineCursor then
        K.col(C.line)
        K.box("fill", K.R(x + 15, ry + st.rowH - 0.2, w - 17, 0.25))
      end
      K.addHit(rb, "win", MINE + i, clip)
      K.setFade(f)
    end
    K.scrollbar(x + w, y + 1, h - 2, st.mineTop, st.visible, st.mineN)
    K.scissor(nil)
  end

  -- ------- an ended auction's recap

  -- the note across the top: back, ENDED, the auction is over
  local function drawOver(x, y, w)
    local b = K.R(x, y, w, 9)
    K.glass(b, 3, 0.5, GLASS, 0.22, 0.18)
    K.chevron(x + 4.5, y + 4.5, 4.4, C.text, -1)
    K.addHit(K.R(x, y, 14, 9), "win", RECAP_BACK)
    local pw = pill(T("auction.ended"), x + 9.5, y + 2.2, 3.4, C.redDeep)
    local note = T("auction.over")
    local tw = w - (pw + 13) - 3
    K.bold(note, x + 12 + pw, y + 2.4, K.fit(note, 4.2, tw), C.text)
  end
  -- the Pokémon: its picture on its tier's glow, name, tier, level, shiny, types; the IVs when there's room
  local function drawRecapMon(R, x, y, w, h, clock)
    local b = K.R(x, y, w, h)
    pane(b, 4)
    local tier = TIER_C[R.tier] and R.tier or "common"
    local tc = TIER_C[tier]
    local ps = min(26, h - 6)
    local ax, ay = x + 3 + ps / 2, y + 3 + ps / 2
    K.grad(K.R(x, y, w, ps + 6), 4, TIER_WASH[tier], TIER_CLEAR[tier])
    K.scissor(K.R(x, y, w, ps + 6))
    if R.tier == "legendary" or R.tier == "mythical" or R.tier == "prized" then rays(ax, ay, ps * 1.1, clock, tc, 0.18) end
    K.glow(ax, ay, ps * 0.7, ps * 0.65, tc, 0.4)
    local g = G()
    for k = 3, 1, -1 do
      K.col(tc, 0.07 * k)
      g.circle("fill", K.X(ax), K.Y(ay), ps * (0.2 + 0.12 * (3 - k)) * K.sc)
    end
    K.scissor(nil)
    local drawn = monPic(R.sp, x + 3, y + 3, ps, R.picMon)
    if not drawn then monIcon(R.sp, x + 3 + ps * 0.1, y + 3 + ps * 0.1, ps * 0.8) end
    local tx = x + ps + 6
    local name = R.name or "?"
    local ns = K.fit(name, 5.4, w - (tx - x) - 3)
    K.bold(name, tx, y + 3.5 + (5.4 - ns) * 0.5, ns, C.text)
    local tier, lv = T(TIER_KEY[R.tier] or TIER_KEY.common), levelText(R.level)
    local k = pillsK(tier, lv, R.shiny, nil, w - (tx - x) - 3, 3.6, 4)
    local pw = pill(tier, tx, y + 10.3, 3.6 * k, tc)
    K.text(lv, tx + pw + 2, y + 10.4, 4 * k, C.soft)
    if R.shiny then shinyBadge(tx + pw + 4 + K.width(lv, 4 * k), y + 10.3, 3.6 * k, clock) end
    if R.types ~= "" and ps >= 22 then K.text(R.types, tx, y + 16, 3.8, C.faint, "left", w - (tx - x) - 3) end
    if R.ivs and y + h - (y + ps + 6) >= 20 then drawIvs(R, x + 4, y + ps + 6, w - 8, clock) end
  end
  -- one line of the result: its label at the left, a hairline under it -> where its value goes
  -- (factG: the room each line takes more at a bigger text size, as the card has it)
  local factG = 0
  local function fact(label, x, y, w)
    K.text(label, x + 4, y, 3.8, C.soft)
    K.col(C.line)
    K.box("fill", K.R(x + 4, y + 4.9 + factG, w - 8, 0.25))
    return y + 5.6 + factG
  end
  -- how it ended: won or outbid, the winning bid (and when), the winner, your maximum, what you paid
  -- or got back, where it went, how many bid; the last bids while there's room
  local function drawRecapResult(R, x, y, w, h, t, clock)
    local b = K.R(x, y, w, h)
    pane(b, 4)
    if R.won then K.grad(K.R(x, y, w, min(h, 40)), 4, WON_WASH, WON_CLEAR) end
    K.scissor(b)
    local yy = y + 3
    local head = T(R.won and "auction.recap.won" or "auction.recap.lost")
    local hs = K.fit(head, 5, w - 12)
    K.bold(head, x + 4, yy, hs, R.won and C.gold or C.red)
    if R.won then
      local hw = K.width(head, hs)
      sparkle(x + 6.5 + hw, yy + 1.2, 1.2 + 0.6 * abs(sin(clock * 4)), C.goldTop, 0.9)
      if st.recapBurst then
        st.recapBurst = false
        confetti(x + 4 + hw / 2, yy + 3, 40)
      end
    end
    yy = yy + 7.5
    -- (at a bigger text size the lines move apart, as far as the card has room for: the facts are
    -- 5.6 apart, the price 2 under its label)
    local nf = 1 + (R.max and 1 or 0) + (R.nBidders and 1 or 0) + (R.won and (R.where and 2 or 1) or (R.max and 1 or 0))
    local kg = 0
    if gx > 0 then kg = max(0, min(1, (y + h - 1.5 - (yy + 14.1 + nf * 5.6)) / (gx * (2 + nf * 1.5)))) end
    factG = gx * 1.5 * kg
    K.text(T("auction.recap.final"), x + 4, yy, 3.8, C.soft)
    if R.at then K.text(agoText(agoKey(t - R.at)), x + 4, yy, 3.6, C.faint, "right", w - 8) end
    yy = yy + 4.6 + gx * 2 * kg
    local mw = money(R.price, x + 4, yy, 6.5, R.won and C.gold or C.text)
    if R.nbids then K.text(bidsText(R.nbids), x + 6 + mw, yy + 1.9, 3.8, C.soft) end
    yy = yy + 9.5
    local vx, vw = x + 4, w - 8
    -- (the winner: you, a bidder's handle, or not known for an older result)
    local who = R.winner == 0 and T("auction.you") or R.winner or T("auction.recap.someone")
    local vy = yy
    yy = fact(T("auction.recap.winner"), x, yy, w)
    K.bold(who, vx, vy, K.fit(who, 3.8, vw * 0.6), R.winner == 0 and C.gold or C.text, "right", vw)
    if R.max then
      vy = yy
      yy = fact(T("auction.max"), x, yy, w)
      money(R.max, x + w - 4, vy, 3.8, C.text, true)
    end
    if R.won then
      vy = yy
      yy = fact(T("auction.recap.paid"), x, yy, w)
      money(R.price, x + w - 4, vy, 3.8, C.gold, true)
      if R.where then
        vy = yy
        yy = fact(T("auction.recap.sentTo"), x, yy, w)
        K.text(T(R.where == "pc" and "auction.recap.pc" or "auction.recap.party"), vx, vy, 3.8, C.text, "right", vw)
      end
    elseif R.max then
      vy = yy
      yy = fact(T("auction.recap.refunded"), x, yy, w)
      money(R.max, x + w - 4, vy, 3.8, C.green, true)
    end
    if R.nBidders then
      vy = yy
      yy = fact(T("auction.recap.bidders"), x, yy, w)
      K.text(numText(R.nBidders), vx, vy, 3.8, C.text, "right", vw)
    end
    -- (the last bids, newest first: the winning one in gold, yours in red)
    if R.histN > 0 and y + h - yy >= 15 then
      yy = yy + 1.5
      K.bold(T("auction.recap.history"), x + 4, yy, 3.8, C.soft)
      yy = yy + 5.2
      for j = 1, R.histN do
        if yy + 4.2 > y + h - 1.5 then break end
        local hw = R.histWho[j]
        local name = hw == 0 and T("auction.you") or hw
        local top = j == 1
        K.text(name, x + 6, yy, 3.6, hw == 0 and C.red or (top and C.text or C.faint), "left", w - 34)
        money(R.histAmt[j], x + w - 4, yy, 3.6, top and C.gold or C.faint, true)
        yy = yy + 4.6
      end
    end
    K.scissor(nil)
  end
  -- (the note, the Pokémon's card and the result's rising in one after another as it opens)
  local function drawRecap(R, x, y, w, h, t, clock)
    local since = mv.clock - mv.recapAt
    local e = K.stagger(since, 0, 0.07, 0.3)
    local f = fadeTo(e)
    drawOver(x, y + (1 - e) * 4, w)
    K.setFade(f)
    local top = y + 9 + M
    local bh = y + h - top
    local e1, e2 = K.stagger(since, 1, 0.07, 0.32), K.stagger(since, 2, 0.07, 0.32)
    if w >= 150 and w > bh * 1.2 then
      local lw = floor((w - M) * 0.48)
      f = fadeTo(e1)
      drawRecapMon(R, x, top + (1 - e1) * 6, lw, bh, clock)
      K.setFade(f)
      f = fadeTo(e2)
      drawRecapResult(R, x + lw + M, top + (1 - e2) * 6, w - lw - M, bh, t, clock)
      K.setFade(f)
    else
      -- (stacked: the Pokémon's card short, its IVs only when the result still has room)
      local mh = (bh >= 32 + 21 + 60) and 53 or 32
      f = fadeTo(e1)
      drawRecapMon(R, x, top + (1 - e1) * 6, w, mh, clock)
      K.setFade(f)
      f = fadeTo(e2)
      drawRecapResult(R, x, top + mh + M + (1 - e2) * 6, w, bh - mh - M, t, clock)
      K.setFade(f)
    end
  end

  -- the head: the R, Browse | My Bids (a count while results are unread), the money
  local function drawHead(x, y, w, clock)
    K.grad(K.R(x, y + 1, 8, 8), 2, C.redTop, C.redDeep)
    K.bold("R", x, y + 1.9, 5.4, C.white, "center", 8)
    -- (Browse | My Bids: a switch of the smoked glass, its red thumb sliding to the tab)
    local sx, sw = x + 11, min(70, w * 0.5)
    local tb = K.R(sx, y + 1, sw, 8)
    K.glass(tb, 4, 0.4, GLASS, 0.2, 0.2)
    local half = sw / 2
    local want = st.tab == "browse" and 1 or 2
    mv.thumb = mv.thumb and K.approach(mv.thumb, want, mv.dt, 16) or want
    lit(K.R(sx + 0.5 + (mv.thumb - 1) * (half - 0.5), y + 1.5, half - 0.5, 7), 3.5, C.red, 0.42, 0.7)
    for i = 1, 2 do
      local on = abs(mv.thumb - i) < 0.5
      local b = K.R(sx + 0.5 + (i - 1) * half, y + 1.5, half - 1, 7)
      local label = T(i == 1 and "auction.browse" or "auction.mine")
      local fs = K.fit(label, 4.2, half - 4)
      if on then K.bold(label, b[1], b[2] + 1.3, fs, C.white, "center", b[3])
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
    money((env.money and env.money(s) or max(0, floor(tonumber(s and s.money) or 0))), x + w - 1, y + 2.4, 5, C.text, true)
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    K.holdStep(hold, stepping)
    K.holdBegin(hold)
    local t = clockNow()
    seTick(now())
    -- (what changed since the last frame starts its motion)
    local dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT, mv.clock, mv.dt = clock, clock, dt
    -- (the text size: the rows taller with it, so their two lines stay apart)
    gx = K.textScale() - 1
    st.rowH = ROW_H + gx * 6
    if mv.tab ~= st.tab then
      mv.tab, mv.tabAt, mv.rowY, mv.mineY = st.tab, clock, nil, nil
    end
    if mv.recap ~= st.recap then mv.recap, mv.recapAt = st.recap, clock end
    local L = current()
    pickHot(t)
    if st.tab == "mine" then rebuildMine(false) end
    -- (the backdrop's light: the shown Pokémon's type, else its tier's colour; eased)
    local shown, tier = nil, nil
    if st.tab == "browse" then
      if L then shown, tier = typeColour(L.types), L.tier end
    elseif st.recap then
      shown, tier = typeColour(st.recap.types), st.recap.tier
    else
      local r = st.mineRows[st.mineCursor]
      if r then
        local RL = st.mineCursor <= st.mineBids and listingOf(r.key) or nil
        shown, tier = typeColour(RL and RL.types or r.types), r.tier
      end
    end
    shown = shown or TIER_C[tier] or C.red
    local lc = mv.lit
    if mv.litOn then
      lc[1], lc[2], lc[3] = K.approach(lc[1], shown[1], dt, 5), K.approach(lc[2], shown[2], dt, 5),
        K.approach(lc[3], shown[3], dt, 5)
    else
      lc[1], lc[2], lc[3], mv.litOn = shown[1], shown[2], shown[3], true
    end
    backdrop(body, clock)
    K.scissor(body)
    drawHead(x + M, y + 1, w - M * 2, clock)
    local top = y + HEAD_H + 1.5
    local bodyH = y + h - M - top
    -- (the cards rising in, one after another, as the tab opens)
    local since = clock - mv.tabAt
    if st.tab == "mine" and st.recap then
      drawRecap(st.recap, x + M, top, w - M * 2, bodyH, t, clock)
    elseif st.tab == "mine" then
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
      local e = K.stagger(since, 0, 0.08, 0.32)
      local f = fadeTo(e)
      if hh > 0 then drawHot(x + M, top + (1 - e) * 6, w - M * 2, hh, clock, t) end
      K.setFade(f)
      drawBrowseList(x + M, top + hh + gap, w - M * 2, lh, st.focus == "list", t, clock)
      K.scissor(body)
      e = K.stagger(since, 2, 0.08, 0.32)
      f = fadeTo(e)
      drawDetail(L, x + M, top + hh + gap + lh + M + (1 - e) * 6, w - M * 2, dh, t, dh < 92, clock)
      K.setFade(f)
    else
      local lw = floor((w - M * 3) * 0.52)
      local hh = min(34, bodyH * 0.38)
      local e = K.stagger(since, 0, 0.08, 0.32)
      local f = fadeTo(e)
      drawHot(x + M, top + (1 - e) * 6, lw, hh, clock, t)
      K.setFade(f)
      drawBrowseList(x + M, top + hh + M, lw, bodyH - hh - M, st.focus == "list", t, clock)
      K.scissor(body)
      e = K.stagger(since, 1, 0.08, 0.32)
      f = fadeTo(e)
      drawDetail(L, x + M * 2 + lw, top + (1 - e) * 6, w - M * 3 - lw, bodyH, t, bodyH < 80, clock)
      K.setFade(f)
    end
    drawParticles(clock, body)
    K.scissor(body)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), C.red, C.green, K.UI.hud) then
      st.toast = nil
    end
  end

  current()
  -- (a notification of a win or a loss: straight to its recap)
  if resumeKey then
    rebuildMine(true)
    for i = st.mineBids + 1, st.mineN do
      local r = st.mineRows[i]
      if r.k and r.n and (r.k .. ":" .. r.n) == resumeKey then
        st.mineCursor = i
        clampList(true)
        openRecap(i)
        break
      end
    end
  end
  return W
end
