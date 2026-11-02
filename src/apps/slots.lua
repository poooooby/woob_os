-- Rocket Slots: Team Rocket's slot machine, played with money (the model is src/slots.lua,
-- env.slots). Three reels; three of a kind on the gold line pays, the rarer kinds with Rocket
-- Tickets too, and the Prizes tab trades the tickets for TMs, rare items and Pokémon (onto the pad).
--
-- The show: the lever pulls, the reels roll and land with a flash; two good symbols on the line hold
-- the last reel back (it glows, the notes climb). A win plays by its size: WIN, BIG WIN, MEGA WIN,
-- JACKPOT (a banner, rays behind the big ones, the cabinet shaking), coins burst from the line, the
-- payout counts up and the tickets fly to their counter. The prize shop: prizes by rarity (a shimmer
-- on the best), the chosen one on a glow with a bar towards it, confetti when it's redeemed.
--   buttons  Slots: A spin (A again stops the next reel), < > the bet, START the pay table;
--            Prizes: Up / Down the prize, A redeem; L / R Slots | Prizes, B close
--   touch    SPIN or the lever (a reel, to stop it), the bet's arrows, "?" the pay table; a prize, Redeem
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, sin, cos, abs, pi = math.floor, math.max, math.min, math.sin, math.cos, math.abs, math.pi

local ROW_H, HEAD_H, M = 12, 10, 3
local SPEED = 22                     -- reel stops a second, spinning
local STOP1, STOP_GAP = 1.0, 0.4     -- the first reel stops by itself after this, the rest after it
local TEASE = 1.5                    -- the last reel held back this much longer when two match
local BOUNCE = 0.28
local LEVER = 0.45
local PARTICLES = 90
-- hit args
local SEG_SLOTS, SEG_PRIZES, BET_DOWN, BET_UP, SPIN, PAYTABLE, REDEEM = 2001, 2002, 2003, 2004, 2005, 2006, 2007
local REEL = 2100   -- + r
local PRIZE = 3000  -- + i

local C = {
  bg = { 20, 16, 20 }, card = { 36, 32, 38 }, cardHi = { 62, 56, 66 }, line = { 255, 255, 255, 0.07 },
  text = { 240, 236, 232 }, soft = { 160, 152, 150 }, faint = { 108, 100, 104 },
  red = { 222, 34, 48 }, redTop = { 236, 60, 66 }, redDark = { 110, 12, 22 }, redDeep = { 150, 18, 30 },
  gold = { 252, 204, 60 }, goldTop = { 255, 232, 130 }, goldDark = { 170, 116, 16 },
  glassTop = { 255, 255, 255 }, glassFoot = { 236, 228, 212 }, lightOff = { 92, 60, 40 }, white = { 255, 255, 255 },
  black = { 0, 0, 0 }, shade = { 0, 0, 0, 0.45 }, redSoft = { 222, 34, 48, 0.22 }, green = { 64, 204, 112 },
  coin = { 255, 210, 70 }, coinEdge = { 196, 132, 20 }, ray = { 255, 230, 140 }, blue = { 70, 150, 255 },
  pink = { 255, 92, 170 }, cyan = { 80, 220, 230 }, purple = { 170, 90, 255 },
}
-- the prizes' rarity, by what they cost: its colour
local RARITY = {
  { upto = 25, key = "slots.rarity1", c = { 120, 170, 210 } },
  { upto = 90, key = "slots.rarity2", c = { 70, 150, 255 } },
  { upto = 150, key = "slots.rarity3", c = { 170, 90, 255 } },
  { upto = 99999, key = "slots.rarity4", c = { 252, 196, 40 } },
}
local CONFETTI = { C.gold, C.red, C.blue, C.pink, C.cyan, C.green, C.purple, C.white }
-- the win's size: × the bet it starts at, its banner, how long the payout counts, how many coins
local TIERS = {
  { x = 500, key = "slots.jackpot", count = 3.2, coins = 90, rays = true, shake = 1.0 },
  { x = 75, key = "slots.mega", count = 2.4, coins = 60, rays = true, shake = 0.6 },
  { x = 20, key = "slots.big", count = 1.6, coins = 36, rays = false, shake = 0 },
  { x = 2, key = "slots.win", count = 0.9, coins = 16, rays = false, shake = 0 },
  { x = 0, key = "slots.betBack", count = 0.4, coins = 0, rays = false, shake = 0 },
}

local HINTS = {
  slots = { { "A", "hint.spin" }, { "< >", "hint.bet" }, { "START", "hint.payTable" }, { "L R", "hint.tab" } },
  spinning = { { "A", "hint.stop" } },
  prizes = { { "A", "hint.redeem" }, { "L R", "hint.tab" }, { "B", "hint.close" } },
  table = { { "B", "hint.back" } },
}
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, Sl, T = env.K, env.slots, env.T or NO_T
  local W = { title = "Slots", pad = true }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local st = {
    tab = "slots", bet = 2, spinning = false, t0 = 0, stopAt = { 0, 0, 0 }, stopped = { true, true, true },
    landT = { -10, -10, -10 }, pos = { 1, 1, 1 }, final = { 1, 1, 1 }, tease = false, win = nil, table = false,
    cursor = 1, top = 0, visible = 6, toast = nil, leverT = -10, shownTickets = nil, ticketPop = -10,
    noteAt = 0, note = 0, redeemT = -10, redeemId = nil,
  }
  W.state = st

  local numText = K.textCache(function(n) return tostring(n) end)
  local plusTickets = K.textCache(function(n) return T.f("slots.plusTickets", n) end)
  local timesText = K.textCache(function(n) return "×" .. tostring(n) end)
  local levelText = K.textCache(function(n) return T.f("boxes.level", n) end)
  local progressText = K.textCache(function(k) return tostring(floor(k / 100000)) .. " / " .. tostring(k % 100000) end)

  -- sounds a moment apart (the engine plays one at a time): a few kept, in order
  local seName, seAt = {}, {}
  local function seLater(name, delay)
    for i = 1, 4 do
      if not seName[i] then
        seName[i], seAt[i] = name, now() + delay
        return
      end
    end
  end
  local function seTick(t)
    for i = 1, 4 do
      if seName[i] and t >= seAt[i] then
        se(seName[i])
        seName[i] = nil
      end
    end
  end

  local function toast(text, bad, sound)
    st.toast = { text = text, bad = bad, t = now() }
    se(sound or (bad and "SE_FAILURE" or "SE_SELECT"))
  end

  -- ------- particles: coins, confetti, flying tickets (a fixed pool, no tables made after this)

  local P = {}
  for i = 1, PARTICLES do P[i] = { live = false, kind = 0, x = 0, y = 0, vx = 0, vy = 0, t0 = 0, life = 0, spin = 0, c = nil } end
  local nextP = 1
  local function emit(kind, x, y, vx, vy, life, c)
    local p = P[nextP]
    nextP = nextP % PARTICLES + 1
    p.live, p.kind, p.x, p.y, p.vx, p.vy, p.t0, p.life, p.c = true, kind, x, y, vx, vy, now(), life, c
    p.spin = (nextP * 0.37) % 1
    return p
  end
  local COIN, CONF, TICKET = 1, 2, 3
  local ticketTo = { x = 0, y = 0 }

  -- ------- the machine

  local REELS = Sl.REELS
  local function reelLen(r) return #REELS[r] end

  local function spin()
    if st.spinning then
      -- (A while spinning: the next reel stops now)
      local t = now()
      for r = 1, 3 do
        if not st.stopped[r] then
          if st.stopAt[r] > t then
            local shift = st.stopAt[r] - t
            for q = r, 3 do st.stopAt[q] = st.stopAt[q] - shift end
          end
          return
        end
      end
      return
    end
    local ok, res = Sl.spin(session(), st.bet)
    if not ok then return toast(T("reason.slots.money"), true) end
    local t = now()
    st.spinning, st.t0, st.win, st.leverT = true, t, nil, t
    for r = 1, 3 do
      st.final[r] = res.stops[r]
      st.stopAt[r] = t + STOP1 + STOP_GAP * (r - 1)
      st.stopped[r] = false
    end
    -- (the first two reels show something good on the line: the last one is held back)
    local a, b = REELS[1][res.stops[1]], REELS[2][res.stops[2]]
    st.tease = a == b and a >= 3
    if st.tease then st.stopAt[3] = st.stopAt[3] + TEASE end
    st.note = 0
    se("SE_BALL_TRAY_ENTER")
  end

  -- the win, as it lands: its tier, its banner, coins from the line, the tickets flying
  local NOTES = { "SE_NOTE_C", "SE_NOTE_D", "SE_NOTE_E", "SE_NOTE_F", "SE_NOTE_G", "SE_NOTE_A", "SE_NOTE_B", "SE_NOTE_C_HIGH" }
  local lineAt = { x = 0, y = 0, w = 0 }
  local function celebrate(t, pays, tickets, jackpot)
    local bet = Sl.BETS[st.bet]
    local x = pays / max(1, bet)
    local tier = TIERS[#TIERS]
    for _, tr in ipairs(TIERS) do
      if x >= tr.x then tier = tr break end
    end
    if jackpot then tier = TIERS[1] end
    st.win = { pays = pays, tickets = tickets, jackpot = jackpot, t = t, tier = tier, x = x }
    for i = 1, tier.coins do
      local a = -pi / 2 + (i / tier.coins - 0.5) * 2.4 + sin(i * 7.1) * 0.2
      local v = 45 + (i * 37 % 40)
      emit(COIN, lineAt.x + lineAt.w * ((i * 0.618) % 1), lineAt.y, cos(a) * v, sin(a) * v, 2.2, nil)
    end
    for i = 1, min(tickets, 10) do
      local p = emit(TICKET, lineAt.x + lineAt.w / 2, lineAt.y, 0, 0, 0.8, nil)
      p.t0 = t + 0.5 + i * 0.09
    end
    if tier == TIERS[1] then
      se("SE_EXP_MAX")
      seLater("SE_APPLAUSE", 0.5)
      seLater("SE_SHINY", 1.4)
    elseif tier == TIERS[2] then
      se("SE_M_STAT_INCREASE")
      seLater("SE_SHINY", 0.5)
      seLater("SE_M_PAY_DAY", 1.0)
    elseif tier == TIERS[3] then
      se("SE_SHINY")
      seLater("SE_M_PAY_DAY", 0.4)
    elseif tier == TIERS[4] then
      se("SE_M_PAY_DAY")
    else
      se("SE_CONTEST_HEART")
    end
  end

  -- the reels at time t (positions in stops); a landing flashes and clunks, the last one the result
  local function advance(t)
    seTick(t)
    if not st.spinning then return end
    for r = 1, 3 do
      local n = reelLen(r)
      if t < st.stopAt[r] then
        -- (rolling down towards its stop: it arrives exactly there)
        st.pos[r] = st.final[r] - n * 6 + SPEED * (st.stopAt[r] - t)
      else
        local k = min(1, (t - st.stopAt[r]) / BOUNCE)
        st.pos[r] = st.final[r] - 0.18 * sin(k * pi) * (1 - k)
        if not st.stopped[r] then
          st.stopped[r], st.landT[r] = true, t
          se(r == 3 and st.tease and "SE_PIN" or "SE_BALL_TRAY_BALL")
        end
      end
    end
    -- (the last reel held back: the notes climb while it rolls)
    if st.tease and st.stopped[2] and not st.stopped[3] and t >= st.noteAt then
      st.note = min(#NOTES, st.note + 1)
      st.noteAt = t + 0.19
      se(NOTES[st.note])
    end
    if st.stopped[3] and t >= st.stopAt[3] + BOUNCE then
      st.spinning = false
      local res = Sl.result
      local pays, tickets = Sl.collect(session())
      if pays > 0 or tickets > 0 then celebrate(t, pays, tickets, res and res.jackpot) end
    end
  end
  local function setBet(i)
    if st.spinning then return end
    i = max(1, min(#Sl.BETS, i))
    if i ~= st.bet then
      st.bet = i
      se("SE_SELECT")
    end
  end

  -- ------- the prizes

  local function prizes() return Sl.prizes() end
  local function rarityOf(p)
    for _, r in ipairs(RARITY) do if p.cost <= r.upto then return r end end
    return RARITY[#RARITY]
  end
  local function clampList()
    local n = #prizes()
    st.cursor = max(1, min(st.cursor, n))
    if st.cursor > st.top + st.visible then st.top = st.cursor - st.visible end
    if st.cursor <= st.top then st.top = st.cursor - 1 end
    st.top = max(0, min(st.top, max(0, n - st.visible)))
  end
  local detailAt = { x = 0, y = 0 }
  local function redeem()
    local p = prizes()[st.cursor]
    if not p then return end
    local ok, where = Sl.redeem(session(), st.cursor)
    if not ok then return toast(T("reason.slots." .. tostring(where)), true) end
    if env.pad and env.pad.transfer then
      if p.kind == "mon" then pcall(env.pad.transfer, p.id, "in", "ball") else pcall(env.pad.transfer, p.id, "in") end
    end
    local t = now()
    st.redeemT, st.redeemId = t, st.cursor
    -- (confetti from the prize)
    for i = 1, 60 do
      local a = (i / 60) * pi * 2 + sin(i * 3.3) * 0.3
      local v = 30 + (i * 29 % 45)
      emit(CONF, detailAt.x, detailAt.y, cos(a) * v, sin(a) * v - 25, 1.8, CONFETTI[i % #CONFETTI + 1])
    end
    local key = where == "party" and "slots.toParty" or (where == "pc" and "slots.toPc" or "slots.toBag")
    toast(T.f(key, p.name), false, "SE_VEND")
    seLater("SE_SHINY", 0.35)
  end

  local function setTab(tab)
    if st.tab == tab or st.spinning then return end
    st.tab, st.table = tab, false
    se("SE_SELECT")
  end

  -- ------- buttons

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
    if st.table then
      if pressed("b") or pressed("start") or pressed("a") then
        st.table = false
        se("SE_SELECT")
      end
      return true
    end
    if pressed("b") then
      if st.spinning then return true end
      return false
    end
    if pressed("l") or pressed("r") then
      setTab(st.tab == "slots" and "prizes" or "slots")
      return true
    end
    if st.tab == "slots" then
      if pressed("a") then spin()
      elseif nav.left then setBet(st.bet - 1)
      elseif nav.right then setBet(st.bet + 1)
      elseif pressed("start") and not st.spinning then
        st.table = true
        se("SE_SELECT")
      end
    else
      local d = nav.up and -1 or (nav.down and 1 or 0)
      if d ~= 0 then
        local c = max(1, min(#prizes(), st.cursor + d))
        if c ~= st.cursor then
          st.cursor = c
          clampList()
          se("SE_SELECT")
        end
      elseif pressed("a") then redeem()
      end
    end
    return true
  end

  function W.tap(arg)
    if type(arg) ~= "number" then return end
    if st.table then
      st.table = false
      return
    end
    if arg == SEG_SLOTS then return setTab("slots") end
    if arg == SEG_PRIZES then return setTab("prizes") end
    if arg == BET_DOWN then return setBet(st.bet - 1) end
    if arg == BET_UP then return setBet(st.bet + 1) end
    if arg == SPIN or (arg > REEL and arg <= REEL + 3) then return spin() end
    if arg == PAYTABLE and not st.spinning then
      st.table = true
      return se("SE_SELECT")
    end
    if arg == REDEEM then return redeem() end
    if arg > PRIZE then
      local i = arg - PRIZE
      if prizes()[i] then
        if st.cursor == i then return redeem() end
        st.cursor = i
        clampList()
        se("SE_SELECT")
      end
    end
  end

  function W.scroll(dy)
    if st.tab == "prizes" then
      st.top = max(0, min(max(0, #prizes() - st.visible), st.top - dy / ROW_H))
    end
  end

  function W.hints()
    if st.table then return T.list(HINTS.table) end
    if st.tab == "prizes" then return T.list(HINTS.prizes) end
    return T.list(st.spinning and HINTS.spinning or HINTS.slots)
  end

  -- (closing mid-spin: the win is paid all the same)
  function W.close()
    if st.spinning then
      st.spinning = false
      Sl.collect(session())
    end
  end

  -- ------- drawing (no tables made here)

  local function G() return K.graphics() end
  local function money(n, x, y, size, c, align)
    if not env.amount then return 0 end
    local ok, w = pcall(env.amount, n, 0, 0, size, c, true)
    w = ok and tonumber(w) or 0
    local dx = align == "right" and x - w or (align == "center" and x - w / 2 or x)
    pcall(env.amount, n, dx, y, size, c)
    return w
  end
  -- scale what's drawn next about cx, cy (units)
  local function scaleAbout(cx, cy, k)
    local g = G()
    g.push()
    g.translate(K.X(cx), K.Y(cy))
    g.scale(k, k)
    g.translate(-K.X(cx), -K.Y(cy))
  end
  -- text with a dark outline (four shadows), for banners
  local function outlined(s, x, y, size, c, w, a)
    for i = 0, 3 do
      local ox, oy = (i % 2 == 0 and -0.5 or 0.5), (i < 2 and -0.5 or 0.5)
      K.bold(s, x + ox, y + oy, size, C.black, "center", w, (a or 1) * 0.8)
    end
    K.bold(s, x, y, size, c, "center", w, a)
  end
  -- a four-point sparkle, `s` units, at cx, cy
  local function sparkle(cx, cy, s, c, a)
    local g = G()
    K.col(c, a)
    local x, y, r, q = K.X(cx), K.Y(cy), s * K.sc, s * K.sc * 0.22
    g.polygon("fill", x, y - r, x + q, y - q, x + r, y, x + q, y + q, x, y + r, x - q, y + q, x - r, y, x - q, y - q)
  end
  -- light rays turning behind cx, cy
  local function rays(cx, cy, r, clock, c, a)
    local g = G()
    g.push()
    g.translate(K.X(cx), K.Y(cy))
    g.rotate(clock * 0.6)
    K.col(c, a)
    local rr = r * K.sc
    for i = 0, 11 do
      local a0 = i * pi / 6
      g.polygon("fill", 0, 0, cos(a0) * rr, sin(a0) * rr, cos(a0 + 0.22) * rr, sin(a0 + 0.22) * rr)
    end
    g.pop()
  end
  -- a Rocket Ticket: a gold stub with notched ends
  local function ticket(x, y, s, a)
    K.col(C.gold, a)
    K.box("fill", K.R(x, y, s * 1.5, s), s * 0.15)
    local g = G()
    K.col(C.bg, a)
    g.circle("fill", K.X(x), K.Y(y + s / 2), s * 0.22 * K.sc)
    g.circle("fill", K.X(x + s * 1.5), K.Y(y + s / 2), s * 0.22 * K.sc)
    K.col(C.goldDark, a)
    K.box("fill", K.R(x + s * 0.45, y + s * 0.2, s * 0.6, s * 0.6), s * 0.1)
  end
  -- a reel symbol, `s` units square at x, y
  local function symbol(i, x, y, s, a)
    local sym = Sl.SYMBOLS[i]
    if not sym then return end
    if sym.rocket then
      K.grad(K.R(x + s * 0.08, y + s * 0.08, s * 0.84, s * 0.84), s * 0.18, C.redTop, C.redDeep, a)
      K.bold("R", x, y + s * 0.14, s * 0.62, C.gold, "center", s, a)
    elseif sym.item then
      if env.itemIcon then pcall(env.itemIcon, sym.item, x, y, s, a) end
    else
      local sp = Sl.speciesOf(i)
      if sp and env.monIcon then pcall(env.monIcon, sp, x - s * 0.05, y - s * 0.1, s * 1.1) end
    end
  end

  -- the marquee: bulbs round a rectangle; chasing while it spins (racing in a tease), every colour
  -- flashing on a win
  local function marquee(x, y, w, h, clock, step)
    local g = G()
    local nx, ny = max(2, floor(w / step)), max(2, floor(h / step))
    local total = 2 * (nx + ny)
    local winning = st.win and (clock - st.win.t) < st.win.tier.count + 1.5 and st.win.tier.coins > 0
    local chase = floor(clock * (st.tease and st.spinning and 30 or 12))
    for i = 0, total - 1 do
      local px, py
      if i < nx then px, py = x + (i + 0.5) * w / nx, y
      elseif i < nx + ny then px, py = x + w, y + (i - nx + 0.5) * h / ny
      elseif i < 2 * nx + ny then px, py = x + w - (i - nx - ny + 0.5) * w / nx, y + h
      else px, py = x, y + h - (i - 2 * nx - ny + 0.5) * h / ny end
      local c, on = C.gold, false
      if winning then
        on = (i + floor(clock * 10)) % 2 == 0
        c = CONFETTI[(i + floor(clock * 8)) % 4 + 1]
      elseif st.spinning then on = (i + chase) % 4 == 0
      else on = (i + floor(clock * 2)) % 2 == 0 end
      if on then
        K.col(c, 0.35)
        g.circle("fill", K.X(px), K.Y(py), 2 * K.sc)
      end
      K.col(on and c or C.lightOff)
      g.circle("fill", K.X(px), K.Y(py), (on and 1.05 or 0.85) * K.sc)
    end
  end

  -- one reel's window: three symbols, the strip moving through it; it flashes as it lands, and
  -- glows while it's the one held back
  local function drawReel(r, x, y, cs, clock)
    local n = reelLen(r)
    local clip = K.R(x, y, cs, cs * 3)
    K.grad(clip, 2, C.glassTop, C.glassFoot)
    K.scissor(clip)
    local pos = st.pos[r]
    local base = floor(pos)
    local rolling = st.spinning and not st.stopped[r]
    local win = st.win and (clock - st.win.t) < 3.5 and Sl.result and Sl.result.symbol
    for i = base - 2, base + 2 do
      local sy = y + cs + (i - pos) * cs
      if sy > y - cs and sy < y + cs * 3 then
        local s = cs * 0.76
        local onLine = win and abs(i - st.final[r]) < 0.01 and not st.spinning
        if onLine then
          -- (the winning symbols bounce)
          local k = 1 + 0.16 * abs(sin((clock - st.win.t) * 7))
          scaleAbout(x + cs / 2, sy + cs / 2, k)
          symbol(REELS[r][(i - 1) % n + 1], x + cs * 0.12, sy + cs * 0.12, s, 1)
          G().pop()
        else
          symbol(REELS[r][(i - 1) % n + 1], x + cs * 0.12, sy + cs * 0.12, s, rolling and 0.7 or 1)
        end
      end
    end
    -- (rolling: streaks over it)
    if rolling then
      K.col(C.white, 0.25)
      for k = 0, 2 do
        local yy = y + ((clock * 140 + k * cs) % (cs * 3))
        K.box("fill", K.R(x, yy, cs, cs * 0.12))
      end
    end
    -- (the glass's shading: darker to the top and bottom, a shine)
    K.col(C.shade, 0.35)
    K.box("fill", K.R(x, y, cs, cs * 0.35))
    K.box("fill", K.R(x, y + cs * 2.65, cs, cs * 0.35))
    K.col(C.white, 0.35)
    K.box("fill", K.R(x + cs * 0.12, y + 1, cs * 0.18, cs * 2.6), cs * 0.09)
    -- (landing: a white flash)
    local since = clock - st.landT[r]
    if since >= 0 and since < 0.25 then
      K.col(C.white, 0.6 * (1 - since / 0.25))
      K.box("fill", clip)
    end
    K.scissor(nil)
    -- (held back: a pulsing gold glow round it)
    if st.tease and st.spinning and r == 3 and st.stopped[2] and not st.stopped[3] then
      local p = 0.5 + 0.5 * sin(clock * 16)
      K.ring(K.R(x - 1.2, y - 1.2, cs + 2.4, cs * 3 + 2.4), 2.5, C.gold, 0.5 + 0.5 * p, 0.9 + p * 0.6)
      K.ring(K.R(x - 2.6, y - 2.6, cs + 5.2, cs * 3 + 5.2), 3.5, C.gold, 0.25 * p, 1.2)
    end
    K.addHit(clip, "win", REEL + r)
  end

  -- the lever on the cabinet's right: pulled down as a spin starts, springing back
  local function drawLever(x, y, h, clock)
    local g = G()
    local k = clock - st.leverT
    local pull = 0
    if k >= 0 and k < LEVER then pull = k < 0.15 and k / 0.15 or 1 - (k - 0.15) / (LEVER - 0.15) end
    local baseY = y + h * 0.55
    local tipY = baseY - h * 0.45 * (1 - pull * 1.6)
    K.grad(K.R(x - 2.5, baseY - 4, 5, 8), 1.5, C.goldTop, C.goldDark)
    K.col(C.goldDark)
    g.setLineWidth(1.6 * K.sc)
    g.line(K.X(x), K.Y(baseY), K.X(x), K.Y(tipY))
    K.col(C.gold)
    g.setLineWidth(0.8 * K.sc)
    g.line(K.X(x - 0.3), K.Y(baseY), K.X(x - 0.3), K.Y(tipY))
    K.col(C.redDark)
    g.circle("fill", K.X(x), K.Y(tipY), 3.4 * K.sc)
    K.col(C.red)
    g.circle("fill", K.X(x), K.Y(tipY), 3 * K.sc)
    K.col(C.white, 0.7)
    g.circle("fill", K.X(x - 1), K.Y(tipY - 1), 0.9 * K.sc)
    K.addHit(K.R(x - 5, min(tipY, baseY) - 5, 10, h * 0.55 + 10), "win", SPIN)
  end

  local function drawMachine(x, y, w, h, clock)
    -- (a big win shakes the cabinet)
    local win = st.win
    local ox, oy = 0, 0
    if win and win.tier.shake > 0 then
      local k = clock - win.t
      if k < 0.7 then
        local f = (1 - k / 0.7) * win.tier.shake * 1.4
        ox, oy = sin(clock * 83) * f, cos(clock * 71) * f
      end
    end
    x, y = x + ox, y + oy
    local bw = w - 10
    -- the sign on top: ROCKET SLOTS, its bulbs chasing
    local sb = K.R(x + 10, y, bw - 20, 12)
    K.shadow(sb, 3, 0.8, 0.3)
    K.grad(sb, 3, C.goldTop, C.goldDark)
    K.grad(K.R(sb[1] + 1, sb[2] + 1, sb[3] - 2, sb[4] - 2), 2.5, C.redDeep, C.redDark)
    marquee(sb[1] + 2.5, sb[2] + 2.5, sb[3] - 5, sb[4] - 5, clock, 4.5)
    outlined(T("slots.title"), sb[1], sb[2] + 3.1, 5.6, C.gold, sb[3])
    -- the cabinet: red shading, the gold trim, the marquee round it
    local cb = K.R(x, y + 10, bw, h - 10)
    K.shadow(cb, 5, 1.2, 0.35)
    K.grad(cb, 5, C.goldTop, C.goldDark)
    K.grad(K.R(cb[1] + 1.4, cb[2] + 1.4, cb[3] - 2.8, cb[4] - 2.8), 4, C.redTop, C.redDeep)
    marquee(cb[1] + 3, cb[2] + 3, cb[3] - 6, cb[4] - 6, clock, 6)
    drawLever(x + bw + 4.5, cb[2], cb[4], clock)
    -- the reels
    local cs = min((bw - 26) / 3, (cb[4] - 14) / 3)
    local rw = cs * 3 + 8
    local rx, ry = cb[1] + (bw - rw) / 2, cb[2] + (cb[4] - cs * 3) / 2
    K.grad(K.R(rx - 3, ry - 3, rw + 6, cs * 3 + 6), 3.5, C.goldTop, C.goldDark)
    K.col(C.bg)
    K.box("fill", K.R(rx - 1.6, ry - 1.6, rw + 3.2, cs * 3 + 3.2), 2.5)
    for r = 1, 3 do drawReel(r, rx + (r - 1) * (cs + 4), ry, cs, clock) end
    lineAt.x, lineAt.y, lineAt.w = rx, ry + cs * 1.5, rw
    -- the gold pay line, glowing on a win
    local glow = win and (clock - win.t) < 3 and (0.6 + 0.4 * sin(clock * 14)) or 0.85
    local g = G()
    if win and (clock - win.t) < 3 then
      K.col(C.gold, 0.3 * glow)
      K.box("fill", K.R(rx - 3.5, ry + cs * 1.5 - 2, rw + 7, 4))
    end
    K.col(C.gold, glow)
    K.box("fill", K.R(rx - 3.5, ry + cs * 1.5 - 0.45, rw + 7, 0.9))
    g.polygon("fill", K.X(rx - 5.5), K.Y(ry + cs * 1.5 - 2.2), K.X(rx - 2), K.Y(ry + cs * 1.5), K.X(rx - 5.5), K.Y(ry + cs * 1.5 + 2.2))
    g.polygon("fill", K.X(rx + rw + 5.5), K.Y(ry + cs * 1.5 - 2.2), K.X(rx + rw + 2), K.Y(ry + cs * 1.5),
      K.X(rx + rw + 5.5), K.Y(ry + cs * 1.5 + 2.2))
    return rx, ry, rw, cs
  end

  -- the win's banner over the reels: it springs in, rays behind the big ones; the payout counting up
  local function drawBanner(rx, ry, rw, cs, clock)
    local win = st.win
    if not win then return end
    local age = clock - win.t
    local tier = win.tier
    local hold = tier.count + 1.6
    if age > hold + 0.5 then return end
    local a = age < hold and 1 or max(0, 1 - (age - hold) / 0.5)
    local cx, cy = rx + rw / 2, ry + cs * 1.5
    if tier.rays then
      rays(cx, cy, rw * 0.9, clock, C.ray, 0.22 * a)
      sparkle(cx - rw * 0.42, cy - cs * 0.9, 2.5 + sin(clock * 9) * 1.2, C.white, a)
      sparkle(cx + rw * 0.45, cy - cs * 0.6, 2 + cos(clock * 7) * 1, C.goldTop, a)
      sparkle(cx + rw * 0.3, cy + cs * 1.1, 2 + sin(clock * 11) * 1, C.white, a)
    end
    -- (the banner springs in: past full size, then settles)
    local k = min(1, age / 0.35)
    local s = k < 1 and (k * 1.25) or (1 + 0.04 * sin(clock * 8))
    if age > 0.35 and age < 0.6 then s = 1.25 - (age - 0.35) / 0.25 * 0.25 end
    local big = tier.coins >= 36
    local size = tier == TIERS[1] and 10 or (big and 8.5 or 6.5)
    local bh = size * 2.4 + 8
    local bb = K.R(cx - rw / 2 - 4, cy - bh / 2, rw + 8, bh)
    scaleAbout(cx, cy, s)
    K.col(C.black, 0.72 * a)
    K.box("fill", bb, 4)
    K.ring(bb, 4, C.gold, a, 0.9)
    local color = tier == TIERS[1] and CONFETTI[floor(clock * 10) % 4 + 1] or C.gold
    outlined(T(tier.key), bb[1], bb[2] + 2, size, color, bb[3], a)
    -- the payout counting up (in twenty steps), then the tickets
    local f = min(1, age / max(0.1, tier.count))
    local amount = floor(floor(win.pays * f * 20 / max(1, win.pays) + 0.5) * win.pays / 20 / 10) * 10
    if f >= 1 then amount = win.pays end
    local mw = env.amount and select(2, pcall(env.amount, amount, 0, 0, 5.5, C.white, true)) or 0
    mw = tonumber(mw) or 0
    local tw = win.tickets > 0 and (K.width(plusTickets(win.tickets), 4.6) + 9) or 0
    local px = cx - (mw + tw) / 2
    K.text("+", px - 4, bb[2] + size * 1.2 + 2.6, 5.5, C.white, nil, nil, a)
    money(amount, px, bb[2] + size * 1.2 + 2.6, 5.5, C.white)
    if win.tickets > 0 then
      ticket(px + mw + 2, bb[2] + size * 1.2 + 3.3, 4, a)
      K.text(plusTickets(win.tickets), px + mw + 9, bb[2] + size * 1.2 + 2.9, 4.6, C.gold, nil, nil, a)
    end
    G().pop()
    -- (a tick as each step lands, the big ones)
    if f < 1 and big then
      local step = floor(f * 20)
      if step ~= st.countStep then
        st.countStep = step
        se("SE_BAG_CURSOR")
      end
    end
  end

  -- the particles: coins tumbling, confetti, tickets flying to their counter
  local function drawParticles(clock, body)
    local g = G()
    K.scissor(body)
    for i = 1, PARTICLES do
      local p = P[i]
      if p.live then
        local age = clock - p.t0
        if age > p.life then
          p.live = false
          if p.kind == TICKET then st.ticketPop = clock end
        elseif age >= 0 then
          if p.kind == TICKET then
            -- (an arc from the line to the counter)
            local k = age / p.life
            local e = k * k * (3 - 2 * k)
            local px = p.x + (ticketTo.x - p.x) * e
            local py = p.y + (ticketTo.y - p.y) * e - sin(k * pi) * 22
            ticket(px - 3, py - 2, 4, 1)
          else
            local px = p.x + p.vx * age
            local py = p.y + p.vy * age + 60 * age * age
            local a = min(1, (p.life - age) / 0.4)
            if p.kind == COIN then
              local flip = abs(cos(clock * 9 + p.spin * 6))
              K.col(C.coinEdge, a)
              g.ellipse("fill", K.X(px), K.Y(py), (0.6 + 1.9 * flip) * K.sc, 2.5 * K.sc)
              K.col(C.coin, a)
              g.ellipse("fill", K.X(px), K.Y(py), (0.4 + 1.5 * flip) * K.sc, 2.0 * K.sc)
              K.col(C.white, 0.7 * a * flip)
              g.circle("fill", K.X(px - 0.5 * flip), K.Y(py - 0.7), 0.5 * K.sc)
            else
              g.push()
              g.translate(K.X(px), K.Y(py))
              g.rotate(clock * 8 + p.spin * 6)
              K.col(p.c, a)
              g.rectangle("fill", -1.2 * K.sc, -0.6 * K.sc * abs(cos(clock * 6 + p.spin * 4)) - 0.2 * K.sc,
                2.4 * K.sc, 1.2 * K.sc * abs(cos(clock * 6 + p.spin * 4)) + 0.4 * K.sc)
              g.pop()
            end
          end
        end
      end
    end
    K.scissor(nil)
  end

  -- under the machine: the bet (< ₽100 >), "?", SPIN (it breathes while it waits, a shine across it)
  local function drawControls(x, y, w, clock)
    local bw = 46
    K.grad(K.R(x, y, bw, 11), 3, C.cardHi, C.card)
    K.chevron(x + 4.5, y + 5.5, 4, st.spinning and C.faint or C.gold, -1)
    K.chevron(x + bw - 4.5, y + 5.5, 4, st.spinning and C.faint or C.gold, 1)
    K.addHit(K.R(x, y, 11, 11), "win", BET_DOWN)
    K.addHit(K.R(x + bw - 11, y, 11, 11), "win", BET_UP)
    K.text(T("slots.bet"), x, y + 0.6, 3.2, C.soft, "center", bw)
    money(Sl.BETS[st.bet], x + bw / 2, y + 4.6, 5, C.goldTop, "center")
    local qb = K.R(x + bw + 3, y, 11, 11)
    K.grad(qb, 3, C.cardHi, C.card)
    K.bold("?", qb[1], qb[2] + 2.5, 5.5, st.spinning and C.faint or C.gold, "center", qb[3])
    K.addHit(qb, "win", PAYTABLE)
    local sb = K.R(x + bw + 17, y, w - bw - 17, 11)
    local idle = not st.spinning
    if idle then
      local p = 0.5 + 0.5 * sin(clock * 4)
      K.col(C.red, 0.25 * p)
      K.box("fill", K.R(sb[1] - 1.5, sb[2] - 1.5, sb[3] + 3, sb[4] + 3), 5)
    end
    K.col(C.redDark)
    K.box("fill", K.R(sb[1], sb[2] + 0.9, sb[3], sb[4]), 3.5)
    if idle then K.grad(sb, 3.5, C.redTop, C.redDeep) else K.grad(sb, 3.5, C.cardHi, C.card) end
    -- (the shine sweeping across it every few seconds)
    if idle then
      local k = (clock % 3.2) / 0.7
      if k < 1 then
        K.scissor(sb)
        local g = G()
        K.col(C.white, 0.35)
        local sx = sb[1] - 10 + (sb[3] + 20) * k
        g.polygon("fill", K.X(sx), K.Y(sb[2]), K.X(sx + 5), K.Y(sb[2]), K.X(sx + 1), K.Y(sb[2] + sb[4]), K.X(sx - 4), K.Y(sb[2] + sb[4]))
        K.scissor(nil)
      end
    end
    local label = T(st.spinning and "slots.stop" or "slots.spin")
    outlined(label, sb[1], sb[2] + 2.4, 5.6, C.white, sb[3])
    K.addHit(sb, "win", SPIN)
  end

  -- the pay table: each three of a kind (× the bet, its tickets), Pikachu from the left
  local function drawTable(x, y, w, h)
    K.col(C.shade)
    K.box("fill", K.R(x, y, w, h))
    local tw, th = min(w - 10, 130), min(h - 8, 96)
    local tx, ty = x + (w - tw) / 2, y + (h - th) / 2
    K.grad(K.R(tx, ty, tw, th), 5, C.cardHi, C.card)
    K.ring(K.R(tx, ty, tw, th), 5, C.gold, 0.6, 0.6)
    K.bold(T("slots.payTable"), tx, ty + 2.5, 5, C.gold, "center", tw)
    -- (the tickets column: per ₽50 bet)
    K.text(T("slots.ticketNote"), tx + tw - 40, ty + 3.4, 3.2, C.faint, "right", 36)
    local rows = #Sl.PAYS + 2
    local rh = (th - 12) / rows
    local s = min(rh - 1, 8)
    for i = 1, rows do
      local ry = ty + 10 + (i - 1) * rh
      local sx = tx + 6
      if i <= #Sl.PAYS then
        local sym = #Sl.PAYS - i + 1
        for k = 0, 2 do symbol(sym, sx + k * (s + 1), ry, s) end
        K.text(timesText(Sl.PAYS[sym].x), tx + tw * 0.55, ry + (s - 4.4) / 2, 4.4, i <= 2 and C.gold or C.text)
        local t = Sl.PAYS[sym].t
        if t > 0 then
          ticket(tx + tw - 22, ry + (s - 3.4) / 2, 3.4)
          K.text(numText(t), tx + tw - 16, ry + (s - 4.2) / 2, 4.2, C.gold)
        end
      else
        local two = i == rows - 1
        symbol(Sl.PIKACHU, sx, ry, s)
        if two then symbol(Sl.PIKACHU, sx + s + 1, ry, s) end
        K.text(T("slots.any"), sx + (two and 2 or 1) * (s + 1) + 1, ry + (s - 3.8) / 2, 3.8, C.faint)
        K.text(timesText(two and Sl.TWO or Sl.ONE), tx + tw * 0.55, ry + (s - 4.4) / 2, 4.4, C.text)
      end
    end
  end

  -- the prize shop: a row per prize (its rarity's colour down the side, a shimmer across the best),
  -- the chosen one on a glow with a bar towards it and Redeem
  local function drawPrizes(x, y, w, h, portrait, clock)
    local list = prizes()
    local have = st.shownTickets or Sl.tickets()
    local lw = portrait and w or floor(w * 0.55)
    local lh = portrait and h - 46 - M or h
    K.col(C.card)
    K.box("fill", K.R(x, y, lw, lh), 4)
    st.visible = max(1, floor((lh - 2) / ROW_H))
    clampList()
    local clip = K.R(x, y + 1, lw, lh - 2)
    K.scissor(clip)
    local first = floor(st.top) + 1
    for i = first, min(#list, first + st.visible + 1) do
      local p = list[i]
      local rar = rarityOf(p)
      local ry = y + 1 + (i - 1 - st.top) * ROW_H
      local rb = K.R(x + 1.5, ry + 0.4, lw - 3, ROW_H - 0.8)
      local can = p.cost <= Sl.tickets()
      if i == st.cursor then
        K.col(rar.c, 0.22)
        K.box("fill", rb, 2.5)
        K.ring(rb, 2.5, rar.c, 0.7, 0.5)
      end
      K.col(rar.c, can and 1 or 0.4)
      K.box("fill", K.R(rb[1] + 0.6, rb[2] + 1.5, 1.1, rb[4] - 3), 0.5)
      -- (the best prizes: a shimmer sweeping across)
      if rar == RARITY[#RARITY] or rar == RARITY[#RARITY - 1] then
        local k = ((clock + i * 0.4) % 2.6) / 0.9
        if k < 1 then
          K.scissor(rb)
          local g = G()
          K.col(C.white, 0.12)
          local sx = rb[1] - 10 + (rb[3] + 20) * k
          g.polygon("fill", K.X(sx), K.Y(rb[2]), K.X(sx + 6), K.Y(rb[2]), K.X(sx + 2), K.Y(rb[2] + rb[4]), K.X(sx - 4), K.Y(rb[2] + rb[4]))
          K.scissor(clip)
        end
      end
      if p.kind == "mon" then
        if env.monIcon then pcall(env.monIcon, p.id, x + 3.5, ry + 1, 10) end
      elseif env.itemIcon then
        pcall(env.itemIcon, p.id, x + 4, ry + 1.5, 9, can and 1 or 0.5)
      end
      local cw = K.width(numText(p.cost), 4.4) + 8
      local ns = K.fit(p.name, 4.6, lw - 22 - cw)
      K.text(p.name, x + 15, ry + 3.2 + (4.6 - ns) * 0.5, ns, can and C.text or C.faint)
      ticket(x + lw - 4 - cw, ry + 4, 3.6, can and 1 or 0.5)
      K.text(numText(p.cost), x + lw - 4 - cw + 6.5, ry + 3.4, 4.4, can and C.gold or C.faint)
      if can then sparkle(x + lw - 4 - cw - 2, ry + 3, 1.1 + 0.5 * sin(clock * 6 + i), C.goldTop, 0.8) end
      K.addHit(rb, "win", PRIZE + i, clip)
    end
    K.scrollbar(x + lw, y + 1, lh - 2, st.top, st.visible, #list)
    K.scissor(nil)
    -- the chosen prize
    local p = list[st.cursor]
    local dx, dy, dw, dh
    if portrait then dx, dy, dw, dh = x, y + lh + M, w, 46 else dx, dy, dw, dh = x + lw + M, y, w - lw - M, h end
    K.grad(K.R(dx, dy, dw, dh), 4, C.cardHi, C.card)
    if not p then return end
    local rar = rarityOf(p)
    local ps = portrait and 18 or 30
    local ax, ay = dx + 4 + ps / 2, dy + 4 + ps / 2
    detailAt.x, detailAt.y = ax, ay
    -- (its art on a glow in its rarity's colour; rays behind the best; sparkles round it)
    local g = G()
    if rar == RARITY[#RARITY] then rays(ax, ay, ps * 0.9, clock, rar.c, 0.18) end
    for k = 3, 1, -1 do
      K.col(rar.c, 0.1 * k)
      g.circle("fill", K.X(ax), K.Y(ay), ps * (0.22 + 0.12 * (3 - k)) * K.sc)
    end
    local pop = 1
    local since = clock - st.redeemT
    if st.redeemId == st.cursor and since >= 0 and since < 0.5 then pop = 1 + 0.35 * sin(since / 0.5 * pi) end
    scaleAbout(ax, ay, pop * (1 + 0.03 * sin(clock * 3)))
    if p.kind == "mon" then
      if not (env.monPic and env.monPic(p.id, ax - ps / 2, ay - ps / 2, ps)) and env.monIcon then
        pcall(env.monIcon, p.id, ax - ps * 0.4, ay - ps * 0.4, ps * 0.8)
      end
    elseif env.itemIcon then
      pcall(env.itemIcon, p.id, ax - ps * 0.32, ay - ps * 0.32, ps * 0.64)
    end
    g.pop()
    sparkle(ax - ps * 0.45, ay - ps * 0.35, 1.2 + 0.8 * abs(sin(clock * 3)), C.white, 0.9)
    sparkle(ax + ps * 0.42, ay + ps * 0.25, 1 + 0.7 * abs(sin(clock * 4 + 1)), rar.c, 0.9)
    local tx = dx + ps + 9
    local ns = K.fit(p.name, 5, dw - (tx - dx) - 3)
    K.bold(p.name, tx, dy + 4 + (5 - ns) * 0.5, ns, C.text)
    local rw = K.width(T(rar.key), 3.4) + 3
    K.col(rar.c)
    K.box("fill", K.R(tx, dy + 10.5, rw, 4.6), 2.3)
    K.text(T(rar.key), tx, dy + 10.7, 3.4, C.bg, "center", rw)
    if p.kind == "mon" then
      K.text(levelText(Sl.level(session())), tx + rw + 2, dy + 10.6, 4.2, C.soft)
    end
    -- (the bar towards it)
    local tickets = Sl.tickets()
    local fb = K.R(tx, dy + 17, dw - (tx - dx) - 4, 3.4)
    K.col(C.black, 0.4)
    K.box("fill", fb, 1.7)
    local f = min(1, tickets / max(1, p.cost))
    if f > 0 then K.grad(K.R(fb[1], fb[2], max(3.4, fb[3] * f), fb[4]), 1.7, C.goldTop, C.goldDark) end
    ticket(tx, dy + 22.2, 3.4)
    K.text(progressText(min(tickets, 99999) * 100000 + p.cost), tx + 6.5, dy + 21.8, 4, f >= 1 and C.gold or C.soft)
    if not portrait and p.desc ~= "" then
      K.scissor(K.R(dx, dy + ps + 10, dw, dh - ps - 10 - 16))
      K.text(p.desc, dx + 4, dy + ps + 10, 4, C.soft, "left", dw - 8)
      K.scissor(nil)
    end
    local go = K.R(dx + 4, dy + dh - 13, dw - 8, 10)
    local can = p.cost <= tickets
    if can then
      local pp = 0.5 + 0.5 * sin(clock * 4)
      K.col(C.red, 0.3 * pp)
      K.box("fill", K.R(go[1] - 1.5, go[2] - 1.5, go[3] + 3, go[4] + 3), 4.5)
      K.grad(go, 3.2, C.redTop, C.redDeep)
    else
      K.col(C.cardHi)
      K.box("fill", go, 3.2)
    end
    outlined(T("slots.redeem"), go[1], go[2] + 2.2, 4.8, can and C.white or C.faint, go[3])
    K.addHit(go, "win", REDEEM)
  end

  -- the head: the gold R, Slots | Prizes (the prizes you can afford counted), the tickets (they pop
  -- as more land) and the money
  local function drawHead(x, y, w, clock)
    K.grad(K.R(x, y + 1, 8, 8), 2, C.goldTop, C.goldDark)
    K.bold("R", x, y + 1.9, 5.4, C.red, "center", 8)
    local sx, sw = x + 11, min(66, w * 0.45)
    K.col(C.card)
    K.box("fill", K.R(sx, y + 1, sw, 8), 2.6)
    local half = sw / 2
    for i = 1, 2 do
      local on = (i == 1) == (st.tab == "slots")
      local b = K.R(sx + 0.5 + (i - 1) * half, y + 1.5, half - 1, 7)
      if on then K.grad(b, 2.2, C.cardHi, C.card) end
      local label = T(i == 1 and "slots.machine" or "slots.prizes")
      local fs = K.fit(label, 4.2, half - 4)
      if on then K.bold(label, b[1], b[2] + 1.3, fs, C.text, "center", b[3])
      else K.text(label, b[1], b[2] + 1.3, fs, C.soft, "center", b[3]) end
      K.addHit(b, "win", i == 1 and SEG_SLOTS or SEG_PRIZES)
    end
    -- (how many prizes the tickets reach: a red count on Prizes)
    local tickets = Sl.tickets()
    local n = 0
    for _, p in ipairs(prizes()) do if p.cost <= tickets then n = n + 1 end end
    if n > 0 then
      local g = G()
      local bx, by = sx + sw - 1.5, y + 1.5
      local k = 1 + 0.12 * abs(sin(clock * 3))
      K.col(C.red)
      g.circle("fill", K.X(bx), K.Y(by), 2.6 * k * K.sc)
      K.text(numText(n), bx - 3, by - 1.6, 3.2, C.white, "center", 6)
    end
    local s = session()
    local mw = money(max(0, floor(tonumber(s and s.money) or 0)), x + w - 1, y + 2.4, 5, C.text, "right")
    -- (the tickets shown catch up with the real count as the flying ones land)
    local real = tickets
    local shown = st.shownTickets or real
    if shown < real then
      local flying = false
      for i = 1, PARTICLES do if P[i].live and P[i].kind == TICKET then flying = true break end end
      if not flying then shown = real elseif clock - st.ticketPop < 0.05 then shown = min(real, shown + max(1, floor((real - shown) / 3))) end
    elseif shown > real then
      shown = max(real, shown - max(1, floor((shown - real) / 6)))
    end
    st.shownTickets = shown
    local tt = numText(shown)
    local tw = K.width(tt, 5)
    local popK = clock - st.ticketPop < 0.25 and 1 + 0.35 * (1 - (clock - st.ticketPop) / 0.25) or 1
    local tcx = x + w - mw - 9 - tw / 2
    ticketTo.x, ticketTo.y = tcx - 4, y + 5
    scaleAbout(tcx, y + 5, popK)
    K.text(tt, x + w - mw - 6 - tw, y + 2.4, 5, C.gold)
    ticket(x + w - mw - 13 - tw, y + 3.2, 4)
    G().pop()
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    advance(now())
    K.col(C.bg)
    K.box("fill", body)
    drawHead(x + M, y + 1, w - M * 2, clock)
    local top = y + HEAD_H + 1.5
    local bodyH = y + h - M - top
    if st.tab == "slots" then
      local cw = min(w - M * 2, portrait and w or 180)
      local cx = x + (w - cw) / 2
      local rx, ry, rw, cs = drawMachine(cx, top, cw, bodyH - 14, clock)
      drawControls(cx, top + bodyH - 11, cw - 10, clock)
      -- (the coins behind the banner, so its words stay clear)
      drawParticles(clock, body)
      K.scissor(body)
      drawBanner(rx, ry, rw, cs, clock)
    else
      drawPrizes(x + M, top, w - M * 2, bodyH, portrait, clock)
      drawParticles(clock, body)
    end
    K.scissor(body)
    if st.table then drawTable(x, y, w, h) end
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), C.red, C.green, K.UI.hud) then
      st.toast = nil
    end
  end

  -- (the reels start somewhere of their own)
  for r = 1, 3 do st.pos[r], st.final[r] = r * 5, r * 5 end
  return W
end
