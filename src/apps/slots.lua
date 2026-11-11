-- Rocket Slots: Team Rocket's video slot, played with money (the model is src/slots.lua, env.slots).
-- Five reels, 1 / 5 / 10 / 20 lines, Ditto wild, Bonus for free spins; the rarer wins pay Rocket
-- Tickets too, and the Prizes tab trades the tickets for TMs, rare items and Pokémon (onto the pad).
--
-- The show: a dark stage, the reels in a gold frame with lights running round it, a pay ladder at the
-- side, the round SPIN button and a BALANCE / WIN / BET bar. Two Bonus down hold the remaining reels
-- back (gold light, the notes climb). A small win shows above the reels and its line glows; BIG, MEGA
-- and JACKPOT take the whole window (rays, a shower of coins, the payout counting up), the winning
-- lines then shown one after another. Free spins run by themselves; so does Auto. The prize shop:
-- prizes by rarity (a shimmer on the best), the chosen one on a glow with a bar towards it.
--   buttons  Slots: A spin (A again stops the next reel), < > the bet, ^ v the lines, SELECT Auto,
--            START the pay table; Prizes: Up / Down the prize, A redeem; L / R Slots | Prizes, B close
--   touch    SPIN (a reel, to stop it), the bet's arrows, LINES, AUTO, the ladder for the pay table;
--            a prize, Redeem
--
--   window(ctx, env) -> win (src/apps.lua)
--
-- Every sound it plays is queued to be made when it opens (env.prewarm): the engine makes a sound
-- the first time it's played (8 to 45 ms), which stuttered the reels the first time two Bonus came
-- down and the notes climbed. The spin's and the tease's first, then the wins', the rest last.

local floor, max, min, sin, cos, abs, pi = math.floor, math.max, math.min, math.sin, math.cos, math.abs, math.pi

-- the notes climbing while a reel is held back, and every sound the window plays, by when it's needed
local NOTES = { "SE_NOTE_C", "SE_NOTE_D", "SE_NOTE_E", "SE_NOTE_F", "SE_NOTE_G", "SE_NOTE_A", "SE_NOTE_B", "SE_NOTE_C_HIGH" }
local SOUNDS = {
  { 2, { "SE_BALL_TRAY_ENTER", "SE_BALL_TRAY_BALL", "SE_PIN", NOTES[1], NOTES[2], NOTES[3], NOTES[4], NOTES[5],
         NOTES[6], NOTES[7], NOTES[8] } },
  { 3, { "SE_CONTEST_HEART", "SE_M_PAY_DAY", "SE_SHINY", "SE_M_STAT_INCREASE", "SE_EXP_MAX", "SE_APPLAUSE" } },
  { 4, { "SE_SELECT", "SE_FAILURE", "SE_VEND", "SE_BAG_CURSOR" } },
}

local ROW_H, HEAD_H, M = 12, 10, 3
local NREELS = 5
local SPEED = 26                     -- reel stops a second, spinning
local STOP1, STOP_GAP = 0.75, 0.22   -- the first reel stops by itself after this, the rest after it
local TEASE = 0.9                    -- each reel still to come held back this much more after two Bonus
local BOUNCE = 0.24
local PRESS = 0.3                    -- the SPIN button's press
local LIT = 8                        -- seconds the winning symbols stay lit after the count
local LINE_SHOW = 1.1                -- seconds on each winning line
local INTRO, OUTRO = 2.2, 2.6        -- the free spins' cards
local PARTICLES = 90
-- hit args
local SEG_SLOTS, SEG_PRIZES, BET_DOWN, BET_UP, SPIN, PAYTABLE, REDEEM, LINES_BTN, AUTO_BTN = 2001, 2002, 2003, 2004, 2005, 2006, 2007, 2008, 2009
local REEL = 2100   -- + r
local PRIZE = 3000  -- + i

local C = {
  bg = { 14, 9, 30 }, card = { 38, 28, 72 }, cardHi = { 68, 52, 116 }, line = { 255, 255, 255, 0.07 },
  stageTop = { 34, 16, 66 }, stageHot = { 74, 18, 58 }, stageFoot = { 9, 5, 22 },
  reelTop = { 56, 38, 104 }, reelFoot = { 30, 20, 68 },
  panelTop = { 52, 40, 96, 0.82 }, panelFoot = { 26, 18, 56, 0.82 },
  fadeDark = { 6, 3, 18, 0.72 }, fadeClear = { 6, 3, 18, 0 },
  violet = { 120, 70, 255 }, violetHi = { 150, 110, 255 },
  text = { 240, 236, 246 }, soft = { 168, 156, 196 }, faint = { 112, 100, 140 },
  red = { 232, 40, 72 }, redTop = { 244, 66, 86 }, redDark = { 96, 12, 34 }, redDeep = { 158, 20, 48 },
  gold = { 252, 204, 60 }, goldTop = { 255, 232, 130 }, goldDark = { 170, 116, 16 },
  white = { 255, 255, 255 }, black = { 0, 0, 0 }, shade = { 0, 0, 0, 0.55 }, green = { 64, 214, 122 }, greenDark = { 22, 140, 74 },
  coin = { 255, 210, 70 }, coinEdge = { 196, 132, 20 }, ray = { 255, 230, 140 }, blue = { 70, 150, 255 },
  pink = { 255, 92, 170 }, cyan = { 80, 220, 230 }, purple = { 170, 90, 255 },
  wildTop = { 255, 214, 240 }, wildFoot = { 244, 134, 200 },
}
-- the light behind each symbol
local SYM_GLOW = {
  { 255, 96, 96 }, { 96, 150, 255 }, { 255, 214, 96 }, { 120, 220, 255 }, { 255, 228, 96 }, { 255, 200, 140 },
  { 214, 110, 255 }, { 255, 70, 70 }, { 255, 130, 230 }, { 255, 222, 110 },
}
-- the winning lines' colours, round and round
local LINE_C = { C.gold, C.cyan, C.pink, C.green, C.purple }
local glowMesh  -- (one soft light, kept)
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
  slots = { { "A", "hint.spin" }, { "+", "hint.betLines" }, { "SELECT", "hint.auto" }, { "START", "hint.payTable" }, { "L R", "hint.tab" } },
  spinning = { { "A", "hint.stop" }, { "SELECT", "hint.auto" } },
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
  if env.prewarm then
    for _, group in ipairs(SOUNDS) do pcall(env.prewarm, group[2], group[1]) end
  end

  local st = {
    tab = "slots", bet = 1, lines = 2, spinning = false, t0 = 0, stopAt = { 0, 0, 0, 0, 0 }, stopped = { true, true, true, true, true },
    landT = { -10, -10, -10, -10, -10 }, pos = { 1, 1, 1, 1, 1 }, final = { 1, 1, 1, 1, 1 }, teaseFrom = nil, win = nil, table = false,
    cursor = 1, top = 0, visible = 6, toast = nil, pressT = -10, shownTickets = nil, ticketPop = -10,
    noteAt = 0, note = 0, redeemT = -10, redeemId = nil, auto = false, nextAt = nil, intro = nil, outro = nil,
    bx = 0, by = 0, bw = 240,
  }
  W.state = st

  local numText = K.textCache(function(n) return tostring(n) end)
  local plusTickets = K.textCache(function(n) return T.f("slots.plusTickets", n) end)
  local timesText = K.textCache(function(n) return "×" .. tostring(n) end)
  local levelText = K.textCache(function(n) return T.f("boxes.level", n) end)
  local progressText = K.textCache(function(k) return tostring(floor(k / 100000)) .. " / " .. tostring(k % 100000) end)
  local bonusNote = K.textCache(function() return T.f("slots.bonusNote", Sl.FREE[3], Sl.FREE[4], Sl.FREE[5], Sl.FREE_MULT) end)

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

  -- the bet and the lines in force: a free spin keeps what won it
  local function betLevel()
    local f = Sl.freeState()
    return f and f.level or st.bet
  end
  local function linesPlayed()
    local f = Sl.freeState()
    return f and f.lines or Sl.LINE_SETS[st.lines]
  end
  -- is this reel the one being waited for, with two Bonus down?
  local function teaseOn(r)
    if not (st.teaseFrom and st.spinning and r >= st.teaseFrom) or st.stopped[r] then return false end
    return r == 1 or st.stopped[r - 1]
  end

  local function spin()
    if st.spinning then
      -- (A while spinning: the next reel stops now)
      local t = now()
      for r = 1, NREELS do
        if not st.stopped[r] then
          if st.stopAt[r] > t then
            local shift = st.stopAt[r] - t
            for q = r, NREELS do st.stopAt[q] = st.stopAt[q] - shift end
          end
          return
        end
      end
      return
    end
    local ok, res = Sl.spin(session(), st.bet, Sl.LINE_SETS[st.lines])
    if not ok then
      st.auto, st.nextAt = false, nil
      return toast(T("reason.slots.money"), true)
    end
    local t = now()
    st.spinning, st.t0, st.win, st.pressT, st.nextAt, st.intro, st.outro = true, t, nil, t, nil, nil, nil
    local seen = 0
    st.teaseFrom = nil
    for r = 1, NREELS do
      st.final[r] = res.stops[r]
      st.stopAt[r] = t + STOP1 + STOP_GAP * (r - 1)
      st.stopped[r] = false
      -- (two Bonus down: the rest of the reels are held back)
      if seen >= 2 and not st.teaseFrom then st.teaseFrom = r end
      for row = -1, 1 do
        if Sl.at(r, res.stops[r], row) == Sl.BONUS then
          seen = seen + 1
          break
        end
      end
    end
    if st.teaseFrom then
      for r = st.teaseFrom, NREELS do st.stopAt[r] = st.stopAt[r] + TEASE * (r - st.teaseFrom + 1) end
    end
    st.note = 0
    se("SE_BALL_TRAY_ENTER")
  end

  -- the win, as it lands: its tier, its banner, coins from the line, the tickets flying
  local lineAt = { x = 0, y = 0, w = 0 }
  local lineY = { 0, 0, 0, 0, 0 }   -- each line's height at the middle reel (drawMachine)
  -- the n-th winning line of the last spin (round and round)
  local function nthWin(n)
    local won, wins = Sl.result.won, 0
    for l = 1, #won do if won[l] > 0 then wins = wins + 1 end end
    if wins == 0 then return 1 end
    n = (n - 1) % wins + 1
    for l = 1, #won do
      if won[l] > 0 then
        n = n - 1
        if n == 0 then return l end
      end
    end
    return 1
  end
  local function celebrate(t, pays, tickets, jackpot)
    -- (the size against everything bet: twenty lines and one small win is a WIN, not a BIG one)
    local res = Sl.result
    local bet = Sl.BETS[res.level] * (res.lines or 1)
    local x = pays / max(1, bet)
    local tier = TIERS[#TIERS]
    for _, tr in ipairs(TIERS) do
      if x >= tr.x then tier = tr break end
    end
    if jackpot then tier = TIERS[1] end
    local key = tier.key
    if tier == TIERS[#TIERS] and pays < bet then key = "slots.win" end
    st.win = { pays = pays, tickets = tickets, jackpot = jackpot, t = t, tier = tier, x = x, key = key }
    -- (coins: bursting from the winning lines, raining over the window on a big win)
    for i = 1, tier.coins do
      if tier.coins >= 36 then
        local p = emit(COIN, st.bx + st.bw * ((i * 0.618) % 1), st.by - 6, sin(i * 3.1) * 12, 18 + (i * 13 % 30), 2.6, nil)
        p.t0 = t + i * 0.022
      else
        local a = -pi / 2 + (i / tier.coins - 0.5) * 2.4 + sin(i * 7.1) * 0.2
        local v = 45 + (i * 37 % 40)
        emit(COIN, lineAt.x + lineAt.w * ((i * 0.618) % 1), lineY[nthWin(i)], cos(a) * v, sin(a) * v, 2.2, nil)
      end
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
    if not st.spinning then
      -- (free spins and Auto go on by themselves, on the machine's own tab)
      if st.nextAt and t >= st.nextAt and st.tab == "slots" and not st.table and (st.auto or Sl.freeState()) then
        st.nextAt = nil
        spin()
      end
      return
    end
    for r = 1, NREELS do
      local n = reelLen(r)
      if t < st.stopAt[r] then
        -- (rolling down towards its stop: it arrives exactly there)
        st.pos[r] = st.final[r] - n * 6 + SPEED * (st.stopAt[r] - t)
      else
        local k = min(1, (t - st.stopAt[r]) / BOUNCE)
        st.pos[r] = st.final[r] - 0.18 * sin(k * pi) * (1 - k)
        if not st.stopped[r] then
          st.stopped[r], st.landT[r] = true, t
          se(teaseOn(r) and "SE_PIN" or "SE_BALL_TRAY_BALL")
        end
      end
    end
    -- (a reel held back: the notes climb while it rolls)
    if st.teaseFrom and t >= st.noteAt then
      for r = st.teaseFrom, NREELS do
        if teaseOn(r) then
          st.note = min(#NOTES, st.note + 1)
          st.noteAt = t + 0.17
          se(NOTES[st.note])
          break
        end
      end
    end
    if st.stopped[NREELS] and t >= st.stopAt[NREELS] + BOUNCE then
      st.spinning = false
      local res = Sl.result
      local pays, tickets = Sl.collect(session())
      if pays > 0 or tickets > 0 then celebrate(t, pays, tickets, res and res.jackpot) end
      -- (what's next waits for the banner, then the free spins' cards)
      local wait = 0.55
      if st.win then wait = st.win.tier.count + (st.win.tier.coins >= 36 and 2.1 or 0.9) end
      if res.freeAdded > 0 then
        st.intro = { t = t + wait, n = res.freeAdded }
        seLater("SE_M_STAT_INCREASE", wait)
        wait = wait + INTRO + 0.2
      elseif res.freeTotal then
        st.outro = { t = t + wait, total = res.freeTotal }
        seLater("SE_M_PAY_DAY", wait)
        wait = wait + OUTRO + 0.2
      end
      st.nextAt = t + wait
    end
  end
  local function setBet(i)
    if st.spinning or Sl.freeState() then return end
    i = max(1, min(#Sl.BETS, i))
    if i ~= st.bet then
      st.bet = i
      se("SE_SELECT")
    end
  end
  -- 1, 5, 10 or 20 lines (wrap: true goes round from 20 to 1, for the touch button)
  local function setLines(i, wrap)
    if st.spinning or Sl.freeState() then return end
    local n = #Sl.LINE_SETS
    if wrap then i = (i - 1) % n + 1 else i = max(1, min(n, i)) end
    if i ~= st.lines then
      st.lines, st.linesT = i, now()
      se(i > 1 and "SE_BALL_TRAY_BALL" or "SE_SELECT")
    end
  end

  -- ------- the prizes

  local function prizes() return Sl.prizes() end
  local function rarityOf(p)
    for _, r in ipairs(RARITY) do if p.cost <= r.upto then return r end end
    return RARITY[#RARITY]
  end
  -- (keeps the chosen row in view, unless the list was scrolled by hand since the last press: a drag
  -- or the wheel would otherwise be pulled straight back to it on the next frame)
  local function clampList(follow)
    if follow then st.free = false end
    local n = #prizes()
    st.cursor = max(1, min(st.cursor, n))
    if not st.free then
      if st.cursor > st.top + st.visible then st.top = st.cursor - st.visible end
      if st.cursor <= st.top then st.top = st.cursor - 1 end
    end
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

  local function setAuto(on)
    st.auto = on
    st.nextAt = on and not st.spinning and now() + 0.3 or st.nextAt
    se("SE_SELECT")
  end

  local function setTab(tab)
    if st.tab == tab or st.spinning then return end
    st.tab, st.table = tab, false
    se("SE_SELECT")
  end

  -- ------- buttons

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  -- (the code, on the machine: up up down down left right left right START. Its buttons change the
  -- bet and the lines as they go, so those are put back at the end, and its START isn't the pay table's)
  local CODE = { "up", "up", "down", "down", "left", "right", "left", "right", "start" }
  local CODE_KEYS = { "up", "down", "left", "right", "start", "a", "b", "select", "l", "r" }
  local codeAt, codeBet, codeLines = 0, 1, 1
  local function enterCode()
    local key
    for i = 1, #CODE_KEYS do
      if pressed(CODE_KEYS[i]) then
        key = CODE_KEYS[i]
        break
      end
    end
    if not key then return false end
    if key == CODE[codeAt + 1] then
      codeAt = codeAt + 1
    elseif key ~= CODE[1] then
      codeAt = 0
    elseif codeAt ~= 2 then     -- (a third up keeps the two before it)
      codeAt = 1
    end
    if codeAt == 1 then codeBet, codeLines = st.bet, st.lines end
    if codeAt < #CODE then return false end
    codeAt = 0
    st.bet, st.lines = codeBet, codeLines
    Sl.cheat()
    toast(T.f("slots.cheat", Sl.CHEAT_SPINS), false, "SE_SHINY")
    return true
  end
  function W.input(input, nav)
    cur = input
    if st.table then
      if pressed("b") or pressed("start") or pressed("a") then
        st.table = false
        se("SE_SELECT")
      end
      return true
    end
    if st.tab == "slots" and enterCode() then return true end
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
      elseif pressed("select") then setAuto(not st.auto)
      elseif nav.left then setBet(st.bet - 1)
      elseif nav.right then setBet(st.bet + 1)
      elseif nav.up then setLines(st.lines + 1)
      elseif nav.down then setLines(st.lines - 1)
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
          clampList(true)
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
    if arg == LINES_BTN then return setLines(st.lines + 1, true) end
    if arg == AUTO_BTN then return setAuto(not st.auto) end
    if arg == SPIN or (arg > REEL and arg <= REEL + NREELS) then return spin() end
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
        clampList(true)
        se("SE_SELECT")
      end
    end
  end

  function W.scroll(dy)
    if st.tab == "prizes" then
      st.free = true
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
    st.auto = false
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
  -- scale what's drawn next about cx, cy (units; ky: taller or shorter than wide)
  local function scaleAbout(cx, cy, k, ky)
    local g = G()
    g.push()
    g.translate(K.X(cx), K.Y(cy))
    g.scale(k, ky or k)
    g.translate(-K.X(cx), -K.Y(cy))
  end
  -- text with a dark outline (four shadows), for banners
  local function outlined(s, x, y, size, c, w, a, o)
    o = o or 0.5
    for i = 0, 3 do
      local ox, oy = (i % 2 == 0 and -o or o), (i < 2 and -o or o)
      K.bold(s, x + ox, y + oy, size, C.black, "center", w, (a or 1) * 0.8)
    end
    K.bold(s, x, y, size, c, "center", w, a)
  end
  -- a four-point sparkle, `s` units, at cx, cy
  local function sparkle(cx, cy, s, c, a)
    local g = G()
    K.col(c, a)
    -- (two thin diamonds crossed: love's filled polygons have to be convex)
    local x, y, r, q = K.X(cx), K.Y(cy), s * K.sc, s * K.sc * 0.3
    g.polygon("fill", x, y - r, x + q, y, x, y + r, x - q, y)
    g.polygon("fill", x - r, y, x, y - q, x + r, y, x, y + q)
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
  -- a word on a band across a symbol's foot (not at the ladder's size: it wouldn't read)
  local function ribbon(word, x, y, s, top, foot, a)
    if s < 12 then return end
    local b = K.R(x + s * 0.02, y + s * 0.76, s * 0.96, s * 0.25)
    K.grad(b, s * 0.13, top, foot, a)
    local fs = K.fit(word, s * 0.23, b[3] - 1)
    K.bold(word, b[1], b[2] + (b[4] - fs) / 2 - fs * 0.08, fs, C.white, "center", b[3], a)
  end
  -- a reel symbol, `s` units square at x, y
  local function symbol(i, x, y, s, a)
    local sym = Sl.SYMBOLS[i]
    if not sym then return end
    if sym.rocket then
      K.grad(K.R(x + s * 0.06, y + s * 0.06, s * 0.88, s * 0.88), s * 0.2, C.goldTop, C.goldDark, a)
      K.grad(K.R(x + s * 0.12, y + s * 0.12, s * 0.76, s * 0.76), s * 0.16, C.redTop, C.redDeep, a)
      K.bold("R", x, y + s * 0.16, s * 0.6, C.goldTop, "center", s, a)
    elseif sym.bonus then
      -- (a gold coin with a star, BONUS across it)
      local r = s * 0.4
      local cx, cy = x + s / 2, y + s * 0.42
      K.grad(K.R(cx - r, cy - r, r * 2, r * 2), r, C.goldTop, C.goldDark, a)
      K.grad(K.R(cx - r * 0.78, cy - r * 0.78, r * 1.56, r * 1.56), r * 0.78, C.gold, C.goldDark, a)
      sparkle(cx, cy, r * 0.72, C.white, a)
      ribbon(T("slots.bonus"), x, y, s, C.purple, C.card, a)
    elseif sym.item then
      if env.itemIcon then pcall(env.itemIcon, sym.item, x, y, s, a) end
    else
      -- (the wild on a bright tile of its own)
      if sym.wild and s >= 12 then
        K.grad(K.R(x + s * 0.03, y + s * 0.03, s * 0.94, s * 0.94), s * 0.18, C.goldTop, C.goldDark, a)
        K.grad(K.R(x + s * 0.08, y + s * 0.08, s * 0.84, s * 0.84), s * 0.14, C.wildTop, C.wildFoot, a)
      end
      local sp = Sl.speciesOf(i)
      if sp and env.monIcon then pcall(env.monIcon, sp, x - s * 0.05, y - s * 0.14, s * 1.1) end
      if sym.wild then ribbon(T("slots.wild"), x, y, s, C.pink, C.redDeep, a) end
    end
  end

  -- ------- the stage

  -- a soft light (additive; nothing without meshes), rx x ry units round cx, cy
  local function glow(cx, cy, rx, ry, c, a)
    local g = G()
    if glowMesh == nil then
      glowMesh = false
      if g.newMesh then
        local v = { { 0, 0, 0, 0, 1, 1, 1, 1 } }
        for i = 0, 28 do
          local t = i / 28 * 2 * pi
          v[#v + 1] = { cos(t), sin(t), 0, 0, 1, 1, 1, 0 }
        end
        local ok, m = pcall(g.newMesh, v, "fan", "static")
        glowMesh = ok and m or false
      end
    end
    if not glowMesh then return end
    g.setBlendMode("add")
    K.col(c, a)
    g.draw(glowMesh, K.X(cx), K.Y(cy), 0, rx * K.sc, ry * K.sc)
    g.setBlendMode("alpha")
  end

  -- the free spins going on (the last one too, while it rolls) -> spins left, or nil
  local function inFree()
    local f = Sl.freeState()
    if f then return f.left end
    if st.spinning and Sl.result.free then return 0 end
    return nil
  end

  -- the stage behind it all: dark violet (hot while free spins run), two lights drifting, specks rising
  local function drawStage(body, clock)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local hot = inFree() ~= nil
    K.grad(body, 0, hot and C.stageHot or C.stageTop, C.stageFoot)
    K.scissor(body)
    glow(x + w * (0.3 + 0.1 * sin(clock * 0.31)), y + h * 0.45, w * 0.55, h * 0.8, hot and C.gold or C.violet, hot and 0.2 or 0.3)
    glow(x + w * (0.7 + 0.1 * cos(clock * 0.27)), y + h * 0.55, w * 0.5, h * 0.75, C.red, 0.22)
    for i = 1, 16 do
      local px = x + w * ((i * 0.618) % 1)
      local py = y + h - ((i * 37 + clock * (3 + i % 4)) % h)
      local r = 1.2 + (i % 3) * 0.9
      glow(px, py, r, r, i % 3 == 0 and C.gold or C.violetHi, 0.18 + 0.14 * sin(clock * 1.3 + i))
    end
  end

  -- the win being shown now: its pay counted up in twenty steps
  local function winNow(clock)
    local win = st.win
    if not win then return 0 end
    local f = min(1, (clock - win.t) / max(0.1, win.tier.count))
    if f >= 1 then return win.pays end
    return floor(floor(f * 20 + 0.5) * win.pays / 20 / 10) * 10
  end
  -- the winning symbols stay lit a while after the banner
  local function winLit(clock)
    local win = st.win
    return win and not st.spinning and (clock - win.t) < win.tier.count + LIT and win or nil
  end
  -- which winning line is shown: 0 all of them while the win counts, then one after another
  local function shownLine(clock)
    local win = st.win
    local age = clock - win.t
    if age < win.tier.count + 0.4 then return 0 end
    return nthWin(floor((age - win.tier.count - 0.4) / LINE_SHOW) + 1)
  end

  -- across the top of the reels: ROCKET SLOTS in gold on a red light, a shine crossing it; a small
  -- win takes its place, and the free spins' count while they run
  local function drawLogo(x, y, w, h, clock)
    local cx, cy = x + w / 2, y + h / 2
    local win = st.win
    local left = inFree()
    if left then
      local label = T("slots.freeSpins")
      local size = K.fit(label, 6.6, w * 0.56)
      local lw = K.width(label, size)
      local n = numText(left)
      local nw = K.width(n, 6.6) + 5
      local tx = cx - (lw + 3 + nw + 3 + 9) / 2
      glow(cx, cy, w * 0.52, h * 1.1, C.gold, 0.3 + 0.12 * sin(clock * 5))
      K.bold(label, tx, cy - size * 0.62, size, C.goldTop)
      local cb = K.R(tx + lw + 3, cy - 4, nw, 8)
      K.grad(cb, 2.4, C.goldTop, C.goldDark)
      K.bold(n, cb[1], cb[2] + 0.9, 6, C.bg, "center", cb[3])
      K.bold(timesText(Sl.FREE_MULT), cb[1] + cb[3] + 3, cy - 3.6, 6, C.white)
      return
    end
    if win and win.tier.coins < 36 and not st.spinning and clock - win.t < win.tier.count + 1.6 then
      local label = T(win.key or win.tier.key)
      local amount = winNow(clock)
      local lw = K.width(label, 7)
      local mw = env.amount and select(2, pcall(env.amount, amount, 0, 0, 7, C.white, true)) or 0
      mw = tonumber(mw) or 0
      local tx = cx - (lw + 4 + mw) / 2
      glow(cx, cy, w * 0.5, h * 1.1, C.gold, 0.28 + 0.2 * (0.5 + 0.5 * sin(clock * 9)))
      K.bold(label, tx, cy - 3.9, 7, C.goldTop)
      money(amount, tx + lw + 4, cy - 3.9, 7, C.white)
      return
    end
    glow(cx, cy, w * 0.46, h * 1.05, C.red, 0.42)
    local word = T("slots.title")
    local size = K.fit(word, 8.5, w - 18)
    local tw = K.width(word, size)
    local ty = cy - size * 0.62
    K.bold(word, x, ty + 0.55, size, C.goldDark, "center", w)
    outlined(word, x, ty, size, C.goldTop, w, 1, 0.42)
    -- (the shine)
    local k = (clock % 4.5) / 1.1
    if k < 1 then
      local sx = cx - tw / 2 - 8 + (tw + 16) * k
      K.scissor(K.R(sx, y, 6, h))
      K.bold(word, x, ty, size, C.white, "center", w)
      K.scissor(nil)
    end
    local sa = 0.55 + 0.45 * sin(clock * 3.1)
    sparkle(cx - tw / 2 - 4.5, cy - 0.4, 2.2, C.goldTop, sa)
    sparkle(cx + tw / 2 + 4.5, cy - 0.4, 2.2, C.goldTop, 1 - sa * 0.7)
  end

  -- is this reel's row (-1, 0, 1) part of a win on the line shown (0: on any), or a Bonus that paid?
  local function winCell(r, row, only)
    local res = Sl.result
    if res.scatters >= 3 and only == 0 and Sl.at(r, res.stops[r], row) == Sl.BONUS then return true end
    for l = 1, res.lines do
      if res.won[l] > 0 and (only == 0 or only == l) and r <= res.count[l] and Sl.LINES[l][r] == row then return true end
    end
    return false
  end

  -- one reel: three cells, the strip moving through them; symbols stretch as they roll, each sits on
  -- a light of its own, the winners bounce in gold and the rest go dark
  local function drawReel(r, x, y, cw, ch, clock, lit, only)
    local n = reelLen(r)
    local clip = K.R(x, y, cw, ch * 3)
    K.grad(clip, 2, C.reelTop, C.reelFoot)
    K.scissor(clip)
    local pos = st.pos[r]
    local base = floor(pos)
    local rolling = st.spinning and not st.stopped[r]
    local s = min(ch * 0.92, cw * 0.92)
    local pulse = 0.5 + 0.5 * sin(clock * 8)
    for i = base - 2, base + 2 do
      local sy = y + ch + (i - pos) * ch
      if sy > y - ch and sy < y + ch * 3 then
        local sym = REELS[r][(i - 1) % n + 1]
        local ccx, ccy = x + cw / 2, sy + ch / 2
        local sx, syy = ccx - s / 2, ccy - s / 2
        if rolling then
          scaleAbout(ccx, ccy, 1, 1.5)
          symbol(sym, sx, syy, s, 0.75)
          G().pop()
        else
          local won = lit and winCell(r, i - st.final[r], only)
          if won then
            glow(ccx, ccy, cw * 0.62, ch * 0.72, C.gold, 0.35 + 0.35 * pulse)
            scaleAbout(ccx, ccy, 1 + 0.12 * abs(sin((clock - lit.t) * 6)))
            symbol(sym, sx, syy, s, 1)
            G().pop()
            K.ring(K.R(x + 0.7, sy + 0.7, cw - 1.4, ch - 1.4), 2, C.goldTop, 0.55 + 0.45 * pulse, 0.8)
          else
            glow(ccx, ccy, s * 0.66, s * 0.66, SYM_GLOW[sym] or C.white, 0.42)
            symbol(sym, sx, syy, s, 1)
            if lit then
              K.col(C.black, 0.55)
              K.box("fill", K.R(x, sy, cw, ch))
            end
          end
        end
      end
    end
    -- (the drum's curve: darker to the top and bottom)
    K.grad(K.R(x, y, cw, ch * 0.5), 0, C.fadeDark, C.fadeClear)
    K.grad(K.R(x, y + ch * 2.5, cw, ch * 0.5), 0, C.fadeClear, C.fadeDark)
    -- (landing: a light flash)
    local since = clock - st.landT[r]
    if since >= 0 and since < 0.22 then
      K.col(C.white, 0.28 * (1 - since / 0.22))
      K.box("fill", clip)
    end
    K.scissor(nil)
    -- (the reel being waited for, two Bonus already down: gold light round it)
    if teaseOn(r) then
      local p = 0.5 + 0.5 * sin(clock * 16)
      glow(x + cw / 2, y + ch * 1.5, cw * 0.95, ch * 2.1, C.gold, 0.3 + 0.35 * p)
      K.ring(K.R(x - 0.3, y - 0.3, cw + 0.6, ch * 3 + 0.6), 2.2, C.goldTop, 0.6 + 0.4 * p, 1)
    end
    K.addHit(clip, "win", REEL + r)
  end

  -- a point k (0..1) of the way round a rectangle
  local function roundRect(x, y, w, h, k)
    local d = (k % 1) * 2 * (w + h)
    if d < w then return x + d, y end
    d = d - w
    if d < h then return x + w, y + d end
    d = d - h
    if d < w then return x + w - d, y + h end
    return x, y + h - (d - w)
  end

  -- one line through the reels' middles
  local function polyline(g, xL, xR, c1, step, ry, ch, line)
    g.line(K.X(xL), K.Y(ry + ch * (1.5 + line[1])),
      K.X(c1), K.Y(ry + ch * (1.5 + line[1])),
      K.X(c1 + step), K.Y(ry + ch * (1.5 + line[2])),
      K.X(c1 + step * 2), K.Y(ry + ch * (1.5 + line[3])),
      K.X(c1 + step * 3), K.Y(ry + ch * (1.5 + line[4])),
      K.X(c1 + step * 4), K.Y(ry + ch * (1.5 + line[5])),
      K.X(xR), K.Y(ry + ch * (1.5 + line[5])))
  end
  -- the line's height at x
  local function lineAtX(px, c1, step, ry, ch, line)
    local k = (px - c1) / step
    if k <= 0 then return ry + ch * (1.5 + line[1]) end
    if k >= 4 then return ry + ch * (1.5 + line[5]) end
    local i = floor(k)
    local a, b = line[i + 1], line[i + 2]
    return ry + ch * (1.5 + a + (b - a) * (k - i))
  end

  -- lines are drawn only when they matter: a moment when their count changes, and on a win, glowing
  -- with a spark running along them
  local function drawLines(rx, ry, rw, cw, ch, gap, clock, lit, only)
    local g = G()
    local res = Sl.result
    local n = st.spinning and res.lines or linesPlayed()
    local xL, xR = rx - 3, rx + rw + 3
    local c1, step = rx + cw / 2, cw + gap
    local added = clock - (st.linesT or -10)
    local pulse = 0.6 + 0.4 * sin(clock * 10)
    for l = #Sl.LINES, 1, -1 do
      local line = Sl.LINES[l]
      lineY[l] = ry + ch * (1.5 + line[3])
      local c = LINE_C[(l - 1) % #LINE_C + 1]
      if lit and l <= res.lines and res.won[l] > 0 and (only == 0 or only == l) then
        K.col(c, 0.28 * pulse)
        g.setLineWidth(3.4 * K.sc)
        polyline(g, xL, xR, c1, step, ry, ch, line)
        K.col(c, 1)
        g.setLineWidth(0.9 * K.sc)
        polyline(g, xL, xR, c1, step, ry, ch, line)
        local px = xL + (xR - xL) * ((clock * 0.9 + l * 0.2) % 1)
        glow(px, lineAtX(px, c1, step, ry, ch, line), 5, 5, C.white, 0.9)
      elseif not lit and added >= 0 and added < 0.9 and l <= n then
        K.col(c, 0.75 * (1 - added / 0.9))
        g.setLineWidth(0.7 * K.sc)
        polyline(g, xL, xR, c1, step, ry, ch, line)
      end
    end
  end

  -- the reels in their frame, lights running round it
  local function drawReels(rx, ry, cw, ch, gap, clock)
    local rw, rh = cw * NREELS + gap * (NREELS - 1), ch * 3
    local cx, cy = rx + rw / 2, ry + rh / 2
    local lit = winLit(clock)
    local only = lit and shownLine(clock) or 0
    local hot = st.teaseFrom and st.spinning
    glow(cx, cy, rw * 0.78, rh * 0.86, hot and C.gold or C.violetHi, hot and 0.5 or 0.34)
    local fb = K.R(rx - 2.2, ry - 2.2, rw + 4.4, rh + 4.4)
    K.grad(fb, 3.6, C.goldTop, C.goldDark)
    K.col(C.bg)
    K.box("fill", K.R(rx - 1, ry - 1, rw + 2, rh + 2), 2.6)
    for r = 1, NREELS do drawReel(r, rx + (r - 1) * (cw + gap), ry, cw, ch, clock, lit, only) end
    lineAt.x, lineAt.y, lineAt.w = rx, cy, rw
    drawLines(rx, ry, rw, cw, ch, gap, clock, lit, only)
    -- (the lights on the frame: two slow ones waiting, a racing six while it spins, gold on a win)
    local n = st.spinning and 6 or 2
    local speed = st.spinning and (hot and 0.9 or 0.45) or 0.07
    for i = 1, n do
      local k = clock * speed + i / n
      for t = 0, 3 do
        local px, py = roundRect(fb[1] + 0.8, fb[2] + 0.8, fb[3] - 1.6, fb[4] - 1.6, k - t * 0.012)
        glow(px, py, 3.4 - t * 0.6, 3.4 - t * 0.6, lit and C.gold or C.white, 0.75 - t * 0.17)
      end
    end
  end

  -- the pay ladder: what five of each symbol pay at this bet, the win's row lit; a tap opens the
  -- full table (one column at the side, two under the reels in portrait)
  local function drawLadder(x, y, w, h, clock, twoCol)
    local panel = K.R(x, y, w, h)
    K.grad(panel, 3.5, C.panelTop, C.panelFoot)
    K.ring(panel, 3.5, C.white, 0.09, 0.4)
    local title = T("slots.fiveKind")
    K.bold(title, x + 3, y + 2, K.fit(title, 3.6, w - 13), C.soft)
    local g = G()
    local qx, qy = x + w - 4.6, y + 3.8
    K.col(C.cardHi)
    g.circle("fill", K.X(qx), K.Y(qy), 2.7 * K.sc)
    K.bold("?", qx - 3, qy - 1.9, 3.6, C.gold, "center", 6)
    K.addHit(panel, "win", PAYTABLE)
    local cols = twoCol and 2 or 1
    local perCol = #Sl.PAYS / cols
    local rh = (h - 9) / perCol
    local colW = (w - 2) / cols
    local s = min(rh - 0.5, 8.6)
    local fs = min(4.4, rh * 0.6)
    local winSym = st.win and not st.spinning and Sl.result.symbol
    local bet = Sl.BETS[betLevel()]
    for i = 1, #Sl.PAYS do
      local sym = #Sl.PAYS - i + 1
      local cl, row = floor((i - 1) / perCol), (i - 1) % perCol
      local rx, ry = x + 1 + cl * colW, y + 8 + row * rh
      if winSym == sym then
        K.col(C.gold, 0.2 + 0.25 * (0.5 + 0.5 * sin(clock * 8)))
        K.box("fill", K.R(rx + 0.5, ry, colW - 1, rh - 0.3), 1.6)
      end
      symbol(sym, rx + 1.5, ry + (rh - s) / 2, s, 1)
      local c = i == 1 and C.gold or (i <= 3 and C.goldTop or C.text)
      money(Sl.PAYS[sym].x[3] * bet, rx + colW - 2, ry + (rh - fs) / 2 - 0.3, fs, c, "right")
    end
  end

  -- the round button: gold rim, two arrows chasing round the word (racing while the reels roll)
  local function drawSpin(cx, cy, d, clock)
    local g = G()
    local idle = not st.spinning
    local since = clock - st.pressT
    local press = since >= 0 and since < PRESS and 1 - 0.09 * sin(since / PRESS * pi) or 1
    glow(cx, cy, d * 0.86, d * 0.86, C.red, idle and (0.32 + 0.3 * (0.5 + 0.5 * sin(clock * 3.4))) or 0.22)
    scaleAbout(cx, cy, press)
    local b = K.R(cx - d / 2, cy - d / 2, d, d)
    K.grad(b, d / 2, C.goldTop, C.goldDark)
    local inner = K.R(cx - d / 2 + 1.5, cy - d / 2 + 1.5, d - 3, d - 3)
    if idle then K.grad(inner, d / 2 - 1.5, C.redTop, C.redDeep) else K.grad(inner, d / 2 - 1.5, C.redDeep, C.redDark) end
    K.col(C.white, 0.14)
    g.ellipse("fill", K.X(cx), K.Y(cy - d * 0.2), d * 0.32 * K.sc, d * 0.2 * K.sc)
    local r = d * 0.37
    local turn = clock * (idle and 0.7 or 9)
    K.col(C.white, idle and 0.92 or 0.55)
    g.setLineWidth(max(1, d * 0.05 * K.sc))
    for k = 0, 1 do
      local a0 = turn + k * pi + 0.35
      local a1 = a0 + pi - 0.7
      g.arc("line", "open", K.X(cx), K.Y(cy), r * K.sc, a0, a1, 16)
      local tx, ty = cx + cos(a1) * r, cy + sin(a1) * r
      local ux, uy, nx, ny = -sin(a1), cos(a1), cos(a1), sin(a1)
      local h = d * 0.1
      g.polygon("fill", K.X(tx + ux * h), K.Y(ty + uy * h), K.X(tx + nx * h * 0.75), K.Y(ty + ny * h * 0.75),
        K.X(tx - nx * h * 0.75), K.Y(ty - ny * h * 0.75))
    end
    local label = T(st.spinning and "slots.stop" or "slots.spin")
    local fs = K.fit(label, d * 0.2, d * 0.56)
    outlined(label, cx - d / 2, cy - fs * 0.62, fs, C.white, d, 1, 0.4)
    g.pop()
    K.addHit(b, "win", SPIN)
  end

  -- LINES: 1, 5, 10 or 20, the one played lit; a tap goes on to the next
  local function drawLinesChoice(x, y, w)
    local b = K.R(x, y, w, 14)
    K.grad(b, 3, C.panelTop, C.panelFoot)
    K.ring(b, 3, C.white, 0.09, 0.4)
    K.text(T("slots.lines"), x, y + 1, 3.2, C.soft, "center", w)
    local n = #Sl.LINE_SETS
    local cw = (w - 3) / n
    local played = linesPlayed()
    local locked = st.spinning or Sl.freeState() ~= nil
    for i = 1, n do
      local c = K.R(x + 1.5 + (i - 1) * cw, y + 5.4, cw - 0.6, 7.2)
      local v = Sl.LINE_SETS[i]
      if v == played then
        K.grad(c, 2, C.goldTop, C.goldDark)
        K.bold(numText(v), c[1], c[2] + 1.4, 4, C.bg, "center", c[3])
      else
        K.text(numText(v), c[1], c[2] + 1.4, 4, locked and C.faint or C.text, "center", c[3])
      end
    end
    K.addHit(b, "win", LINES_BTN)
  end

  -- AUTO: lit while it's on
  local function drawAuto(x, y, w, h, clock)
    local b = K.R(x, y, w, h)
    if st.auto then
      glow(x + w / 2, y + h / 2, w * 0.6, h * 1.2, C.green, 0.3 + 0.15 * sin(clock * 6))
      K.grad(b, 3, C.green, C.greenDark)
    else
      K.grad(b, 3, C.panelTop, C.panelFoot)
      K.ring(b, 3, C.white, 0.09, 0.4)
    end
    local t = T("slots.auto")
    local fs = K.fit(t, 4, w - 3)
    K.bold(t, x, y + (h - fs) / 2 - 0.4, fs, st.auto and C.bg or C.text, "center", w)
    K.addHit(b, "win", AUTO_BTN)
  end

  -- the bar along the foot: BALANCE, WIN (counting up as it's paid), BET with its arrows
  local function drawHud(x, y, w, h, clock)
    local bar = K.R(x, y, w, h)
    K.grad(bar, 3.5, C.panelTop, C.panelFoot)
    K.ring(bar, 3.5, C.white, 0.1, 0.4)
    local third = w / 3
    K.vline(x + third, y + 2.5, h - 5, C.white, 0.14)
    K.vline(x + third * 2, y + 2.5, h - 5, C.white, 0.14)
    local s = session()
    local amount = winNow(clock)
    local pending = st.win and (st.win.pays - amount) or 0
    local bal = T("slots.balance")
    K.text(bal, x, y + 2, K.fit(bal, 3.2, third - 4), C.soft, "center", third)
    money(max(0, floor(tonumber(s and s.money) or 0) - pending), x + third / 2, y + 6.6, 5.6, C.text, "center")
    local w2 = x + third
    K.text(T("slots.win"), w2, y + 2, 3.2, C.soft, "center", third)
    local lit = st.win and not st.spinning and amount > 0
    if lit then glow(w2 + third / 2, y + h / 2, third * 0.45, h * 0.7, C.gold, 0.25 + 0.15 * sin(clock * 8)) end
    money(lit and amount or 0, w2 + third / 2, y + 6.6, 5.6, lit and C.goldTop or C.faint, "center")
    local w3 = x + third * 2
    K.text(T("slots.bet"), w3, y + 2, 3.2, C.soft, "center", third)
    money(Sl.BETS[betLevel()] * linesPlayed(), w3 + third / 2, y + 6.6, 5.6, C.goldTop, "center")
    local g = G()
    local cy = y + h / 2
    local locked = st.spinning or Sl.freeState() ~= nil
    for k = -1, 1, 2 do
      local cx = k < 0 and w3 + 6 or w3 + third - 6
      K.col(locked and C.card or C.cardHi)
      g.circle("fill", K.X(cx), K.Y(cy), 4 * K.sc)
      K.chevron(cx + (k < 0 and -0.3 or 0.3), cy, 3.6, locked and C.faint or C.gold, k)
      K.addHit(K.R(cx - 5.5, y, 11, h), "win", k < 0 and BET_DOWN or BET_UP)
    end
  end

  -- it all, by the window's shape: pay ladder | reels | spin in a wide one, stacked in a narrow one
  local function drawMachine(x, y, w, h, clock, portrait)
    local win = st.win
    if win and win.tier.shake > 0 then
      local k = clock - win.t
      if k < 0.7 then
        local f = (1 - k / 0.7) * win.tier.shake * 1.4
        x, y = x + sin(clock * 83) * f, y + cos(clock * 71) * f
      end
    end
    local hudH, gap, rg, frame = 15, 3, 1.2, 4.4
    if not (portrait or w < 170) then
      local sideW = max(38, min(46, floor(w * 0.2)))
      local ladW = max(44, min(58, floor(w * 0.23)))
      local stageH = h - hudH - gap
      local cx, cw0 = x + ladW + gap, w - ladW - sideW - gap * 2
      local logoH = 10
      local ch = (stageH - logoH - frame) / 3
      local cw = min((cw0 - frame - 6 - rg * (NREELS - 1)) / NREELS, ch * 1.5)
      local rw = cw * NREELS + rg * (NREELS - 1)
      drawLadder(x, y, ladW, stageH, clock, false)
      drawLogo(cx, y, cw0, logoH, clock)
      drawReels(cx + (cw0 - rw) / 2, y + logoH + 2.2, cw, ch, rg, clock)
      local sx = x + w - sideW
      drawLinesChoice(sx, y, sideW)
      drawAuto(sx, y + 15.5, sideW, 8, clock)
      local room = stageH - 25
      local d = min(sideW - 1, room - 1, 44)
      drawSpin(sx + sideW / 2, y + 25 + room / 2, d, clock)
      drawHud(x, y + h - hudH, w, hudH, clock)
    else
      local logoH, spinH = 12, 44
      local cw = (w - frame - 6 - rg * (NREELS - 1)) / NREELS
      local ch = min(cw * 1.05, (h - logoH - frame - hudH - spinH - gap * 2) / 3)
      local rw = cw * NREELS + rg * (NREELS - 1)
      local rh = ch * 3 + frame
      drawLogo(x, y, w, logoH, clock)
      drawReels(x + (w - rw) / 2, y + logoH + 2.2, cw, ch, rg, clock)
      local spinY = y + h - hudH - gap - spinH
      local ladY = y + logoH + rh + gap
      if spinY - gap - ladY >= 30 then drawLadder(x, ladY, w, spinY - gap - ladY, clock, true) end
      local sideW = (w - spinH) / 2 - 4
      drawLinesChoice(x, spinY + 6, sideW)
      drawAuto(x, spinY + 22, sideW, 9, clock)
      drawSpin(x + w / 2, spinY + spinH / 2, spinH, clock)
      -- (the pay table's button, for when there's no room for the ladder)
      local qb = K.R(x + w - sideW, spinY + 14, sideW, 14)
      K.grad(qb, 3, C.panelTop, C.panelFoot)
      K.ring(qb, 3, C.white, 0.09, 0.4)
      local t = T("slots.payTable")
      K.text(t, qb[1], qb[2] + 4.6, K.fit(t, 4, qb[3] - 3), st.spinning and C.faint or C.gold, "center", qb[3])
      K.addHit(qb, "win", PAYTABLE)
      drawHud(x, y + h - hudH, w, hudH, clock)
    end
  end

  -- a big win takes the whole window: dimmed, rays turning behind it; then (over the coins) the
  -- words springing in and the payout counting up
  local function bigWinAlpha(clock)
    local win = st.win
    if not win or win.tier.coins < 36 or st.spinning then return nil end
    local age = clock - win.t
    local hold = win.tier.count + 1.6
    if age > hold + 0.5 then return nil end
    return (age < hold and min(1, age / 0.18) or max(0, 1 - (age - hold) / 0.5)), age
  end
  local function drawBigBack(body, clock)
    local a = bigWinAlpha(clock)
    if not a then return end
    local win = st.win
    local cx, cy = body[1] + body[3] / 2, body[2] + body[4] / 2
    K.col(C.black, 0.66 * a)
    K.box("fill", body)
    if win.tier.rays then rays(cx, cy, max(body[3], body[4]) * 0.8, clock, C.ray, 0.13 * a) end
    glow(cx, cy, body[3] * 0.55, body[4] * 0.62, win.tier == TIERS[1] and C.red or C.violetHi, 0.55 * a)
    glow(cx, cy, body[3] * 0.3, body[4] * 0.4, C.gold, 0.4 * a)
  end
  local function spring(age)
    local k = min(1, age / 0.3)
    if k < 1 then return k * 1.22 end
    if age < 0.55 then return 1.22 - (age - 0.3) / 0.25 * 0.22 end
    return 1
  end
  local function drawBigFront(body, clock)
    local a, age = bigWinAlpha(clock)
    if not a then return end
    local win, tier = st.win, st.win.tier
    local cx, cy = body[1] + body[3] / 2, body[2] + body[4] / 2
    local label = T(win.key or tier.key)
    local size = K.fit(label, tier == TIERS[1] and 24 or (tier == TIERS[2] and 20 or 17), body[3] * 0.9)
    local c = tier == TIERS[1] and CONFETTI[floor(clock * 9) % 4 + 1] or C.goldTop
    local top = cy - (size + 13) / 2 - 2
    scaleAbout(cx, cy, spring(age) + (age >= 0.55 and 0.03 * sin(clock * 7) or 0))
    outlined(label, body[1], top, size, c, body[3], a, size * 0.05)
    local amount = winNow(clock)
    local mw = env.amount and select(2, pcall(env.amount, amount, 0, 0, 12, C.white, true)) or 0
    mw = tonumber(mw) or 0
    local tw = win.tickets > 0 and (K.width(plusTickets(win.tickets), 6) + 12) or 0
    local px = cx - (mw + tw) / 2
    local my = top + size * 1.28
    money(amount, px, my + 0.5, 12, C.black)
    money(amount, px, my, 12, C.white)
    if win.tickets > 0 then
      ticket(px + mw + 3, my + 3.2, 5.4, a)
      K.bold(plusTickets(win.tickets), px + mw + 12, my + 2.6, 6, C.gold, nil, nil, a)
    end
    G().pop()
    sparkle(cx - body[3] * 0.33, cy - size * 0.7, 3 + sin(clock * 9) * 1.4, C.white, a)
    sparkle(cx + body[3] * 0.34, cy - size * 0.4, 2.6 + cos(clock * 7) * 1.2, C.goldTop, a)
    sparkle(cx + body[3] * 0.26, cy + size * 0.9, 2.6 + sin(clock * 11) * 1.2, C.white, a)
    if age < tier.count then
      local step = floor(age / tier.count * 20)
      if step ~= st.countStep then
        st.countStep = step
        se("SE_BAG_CURSOR")
      end
    end
  end

  -- free spins won ("FREE SPINS! +10, wins ×3") and over ("TOTAL WIN ₽...")
  local function drawCard(body, clock)
    local intro, outro = st.intro, st.outro
    local card = intro or outro
    if not card then return end
    local age = clock - card.t
    local life = intro and INTRO or OUTRO
    if age < 0 then return end
    if age > life then
      if intro then st.intro = nil else st.outro = nil end
      return
    end
    local a = min(1, age / 0.2) * min(1, (life - age) / 0.3)
    local cx, cy = body[1] + body[3] / 2, body[2] + body[4] / 2
    K.scissor(body)
    K.col(C.black, 0.7 * a)
    K.box("fill", body)
    rays(cx, cy, max(body[3], body[4]) * 0.8, clock, C.ray, 0.12 * a)
    glow(cx, cy, body[3] * 0.55, body[4] * 0.62, C.purple, 0.55 * a)
    glow(cx, cy, body[3] * 0.3, body[4] * 0.4, C.gold, 0.4 * a)
    local label = T(intro and "slots.freeSpins" or "slots.total")
    local size = K.fit(label, 20, body[3] * 0.9)
    local top = cy - (size + 13) / 2 - 2
    scaleAbout(cx, cy, spring(age))
    outlined(label, body[1], top, size, C.goldTop, body[3], a, size * 0.05)
    local y2 = top + size * 1.28
    if intro then
      local t1 = plusTickets(intro.n)
      local t2 = timesText(Sl.FREE_MULT)
      local w1, w2 = K.width(t1, 12), K.width(t2, 12)
      local px = cx - (w1 + 8 + w2) / 2
      K.bold(t1, px, y2, 12, C.white, nil, nil, a)
      K.bold(t2, px + w1 + 8, y2, 12, C.goldTop, nil, nil, a)
    else
      local mw = env.amount and select(2, pcall(env.amount, outro.total, 0, 0, 12, C.white, true)) or 0
      mw = tonumber(mw) or 0
      money(outro.total, cx - mw / 2, y2 + 0.5, 12, C.black)
      money(outro.total, cx - mw / 2, y2, 12, C.white)
    end
    G().pop()
  end

  -- the pay table: three, four and five of each symbol (× the bet on a line, five's tickets), the
  -- wild and the Bonus underneath
  local function drawTable(x, y, w, h)
    K.col(C.shade)
    K.box("fill", K.R(x, y, w, h))
    local tw, th = min(w - 8, 164), min(h - 6, 112)
    local tx, ty = x + (w - tw) / 2, y + (h - th) / 2
    K.grad(K.R(tx, ty, tw, th), 5, C.cardHi, C.card)
    K.ring(K.R(tx, ty, tw, th), 5, C.gold, 0.6, 0.6)
    K.bold(T("slots.payTable"), tx, ty + 2.5, 5, C.gold, "center", tw)
    K.text(T("slots.perLine"), tx + 4, ty + 3.4, 3.2, C.faint)
    K.text(T("slots.ticketNote"), tx + tw - 44, ty + 3.4, 3.2, C.faint, "right", 40)
    local notes = 19
    local rows = #Sl.PAYS
    local rh = (th - 14 - notes) / rows
    local s = min(rh - 0.6, 8.4)
    local col = tw * 0.17
    local cx0 = tx + 20
    for k = 3, 5 do K.bold(numText(k), cx0 + (k - 3) * col, ty + 9, 3.8, C.soft, "right", col - 3) end
    for i = 1, rows do
      local ry = ty + 13.5 + (i - 1) * rh
      local sym = rows - i + 1
      symbol(sym, tx + 5, ry + (rh - s) / 2, s, 1)
      local top = i <= 2
      for k = 1, 3 do
        K.text(timesText(Sl.PAYS[sym].x[k]), cx0 + (k - 1) * col, ry + (rh - 4.2) / 2 - 0.2, 4.2,
          top and C.gold or C.text, "right", col - 3)
      end
      local t = Sl.PAYS[sym].t[3]
      if t > 0 then
        ticket(tx + tw - 21, ry + (rh - 3.2) / 2, 3.2)
        K.text(numText(t), tx + tw - 15, ry + (rh - 4.2) / 2 - 0.2, 4.2, C.gold)
      end
    end
    K.hairline(tx + 4, ty + th - notes + 0.5, tw - 8, C.white, 0.14)
    local ny = ty + th - notes + 2
    symbol(Sl.WILD, tx + 4.5, ny - 0.3, 8, 1)
    local note = T("slots.wildNote")
    K.text(note, tx + 15, ny + 1.9, K.fit(note, 3.9, tw - 19), C.text)
    symbol(Sl.BONUS, tx + 4.5, ny + 8.2, 8, 1)
    local bn = bonusNote(1)
    K.text(bn, tx + 15, ny + 10.4, K.fit(bn, 3.9, tw - 19), C.text)
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
  -- as more land)
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
    local tcx = x + w - 1 - tw / 2
    ticketTo.x, ticketTo.y = tcx - 4, y + 5
    scaleAbout(tcx, y + 5, popK)
    K.text(tt, x + w - 1 - tw, y + 2.4, 5, C.gold)
    ticket(x + w - 8 - tw, y + 3.2, 4)
    G().pop()
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    st.bx, st.by, st.bw = x, y, w
    advance(now())
    drawStage(body, clock)
    drawHead(x + M, y + 1, w - M * 2, clock)
    local top = y + HEAD_H + 1.5
    local bodyH = y + h - M - top
    if st.tab == "slots" then
      drawMachine(x + M, top, w - M * 2, bodyH, clock, portrait)
      K.scissor(body)
      drawBigBack(body, clock)
      -- (the coins behind the words, so they stay clear)
      drawParticles(clock, body)
      K.scissor(body)
      drawBigFront(body, clock)
      drawCard(body, clock)
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
  for r = 1, NREELS do st.pos[r], st.final[r] = r * 5, r * 5 end
  -- (free spins left from before: they carry on)
  if Sl.freeState() then st.nextAt = now() + 1 end
  return W
end
