-- A Pokémon evolving, full screen (the scene host, src/shell.lua's Sh.openScene; the model ctx.scene is
-- src/evolve.lua's job). The game's evolution as it goes -- "What? X is evolving!", its cry, the music, the
-- old Pokémon and the new one trading places as white silhouettes, shrinking and growing faster and faster,
-- then the flash and the new one -- with more light: a night sky lit in the new Pokémon's colours, rays
-- turning behind it, sparkles swirling round it in three dimensions (behind it, then in front) and spiralling
-- in faster as it speeds up, its glow, the flash breaking into a ring and a shower of stars, the screen
-- shaking, the new Pokémon popping out of the white in colour among twinkles.
--   buttons  A the words (the rest of them, then on), B stops it while it still can (as the game), Up / Down
--            and A a question's Yes / No, B No
--   touch    tap the words to go on, Stop at the top while it can be stopped, Yes / No
-- Its timing is the game's: the swap's speed rises by 2 / 256 each half-turn from 8, at 60 a second, and it's
-- past stopping at 128.

local floor, max, min, sin, cos, abs, pi, sqrt = math.floor, math.max, math.min, math.sin, math.cos, math.abs,
  math.pi, math.sqrt

local A = { WORDS = 2001, YES = 2002, NO = 2003, STOP = 2004, STATS = 2005 }
-- (the stats card: each row counting up, one after another; out)
local COUNT, STAGGER, CARD_OUT = 0.55, 0.12, 0.25
local STAT_KEYS = { "dex.stat.hp", "dex.stat.atk", "dex.stat.def", "dex.stat.spa", "dex.stat.spd", "dex.stat.spe" }
-- (Red / Blue / Yellow's five: one Special)
local STAT_KEYS5 = { "dex.stat.hp", "dex.stat.atk", "dex.stat.def", "dex.stat.spc", "dex.stat.spe" }
local GREEN, RED = { 52, 199, 89 }, { 255, 59, 48 }
-- (when each beat comes, seconds from the start)
local T_WORDS, T_CRY, T_INTRO, T_MUSIC, T_CYCLE = 0.3, 1.05, 1.8, 2.4, 2.75
local T_CRY2, T_CONGRATS = 0.6, 1.35
local OUT = 0.4
-- (the particles: swirling, the burst's, the twinkles round the new one, the night's lights)
local NS, NB, NT, NL = 150, 72, 26, 22
local TYPE = {
  [0] = { 168, 168, 120 }, [1] = { 192, 48, 40 }, [2] = { 168, 144, 240 }, [3] = { 160, 64, 160 },
  [4] = { 224, 192, 104 }, [5] = { 184, 160, 56 }, [6] = { 168, 184, 32 }, [7] = { 112, 88, 152 },
  [8] = { 184, 184, 208 }, [9] = { 104, 160, 144 }, [10] = { 240, 128, 48 }, [11] = { 104, 144, 240 },
  [12] = { 120, 200, 80 }, [13] = { 248, 208, 48 }, [14] = { 248, 88, 136 }, [15] = { 152, 216, 216 },
  [16] = { 112, 56, 248 }, [17] = { 112, 88, 72 }, [18] = { 238, 153, 172 },
}
local C = { white = { 255, 255, 255 }, black = { 0, 0, 0 }, night = { 10, 12, 28 }, nightFoot = { 4, 4, 12 },
            ice = { 214, 236, 255 }, gold = { 255, 220, 120 }, ink = { 28, 28, 30 }, accent = { 10, 132, 255 },
            soft = { 112, 112, 120 } }

return function(ctx, env)
  local K, T = env.K, env.T
  local Fx = env.sceneFx
  local job = ctx.scene
  local function now() return env.now and env.now() or (love and love.timer and love.timer.getTime() or 0) end
  local rnd = love and love.math and love.math.random or math.random

  local W = { title = "" }
  if not (job and Fx) then
    function W.draw() if ctx.done then ctx.done() end end
    function W.input() return true end
    return W
  end

  local t0 = now()
  local st = {
    phase = "intro", at = t0, beat = 0,
    -- (the game's swap: its speed, which way, each one's size, the frames counted at 60 a second)
    speed = 8, dir = 0, pre = 1, post = 1 / 16, acc = 0, last = t0, frame = 0,
    burstAt = nil, cancelAt = nil, doneAt = nil, outAt = nil, result = nil,
    words = Fx.words(), waitUntil = nil, waitFn = nil, finished = false,
    hop = -10, spawnAcc = 0,
  }
  W.state = st
  local c1 = TYPE[(job.types("from"))] or TYPE[0]
  local t1, t2 = job.types("to")
  local n1, n2 = TYPE[t1] or TYPE[0], TYPE[t2 or t1] or TYPE[t1] or TYPE[0]

  -- the particle pools (numbers in arrays: nothing made while it plays)
  local S = { on = {}, t = {}, life = {}, a = {}, w = {}, r = {}, y = {}, size = {}, hue = {}, star = {} }
  for i = 1, NS do S.on[i] = false end
  local B = { on = {}, t = {}, life = {}, a = {}, v = {}, size = {}, hue = {}, spin = {} }
  for i = 1, NB do B.on[i] = false end
  local TW = { x = {}, y = {}, at = {}, size = {}, hue = {} }
  for i = 1, NT do
    local a = rnd() * 2 * pi
    local d = 0.45 + rnd() * 0.55
    TW.x[i], TW.y[i], TW.at[i], TW.size[i], TW.hue[i] = cos(a) * d, sin(a) * d * 0.8, rnd() * 2.2, 1.2 + rnd() * 1.8, rnd()
  end
  local LT = { x = {}, y = {}, s = {}, v = {}, hue = {} }
  for i = 1, NL do
    LT.x[i], LT.y[i], LT.s[i], LT.v[i], LT.hue[i] = rnd(), rnd(), 3 + rnd() * 9, 0.015 + rnd() * 0.03, rnd()
  end

  local function spawnSwirl(clock, cyc)
    for i = 1, NS do
      if not S.on[i] then
        S.on[i], S.t[i] = true, clock
        S.life[i] = (0.9 + rnd() * 0.7) / (0.6 + cyc * 1.4)
        S.a[i] = rnd() * 2 * pi
        S.w[i] = 2.2 + rnd() * 2.2 + cyc * 7
        S.r[i] = 0.75 + rnd() * 0.55
        S.y[i] = (rnd() - 0.5) * 0.9
        S.size[i] = 1.3 + rnd() * 1.7
        S.hue[i] = rnd()
        S.star[i] = rnd() < 0.45
        return
      end
    end
  end
  local function spawnBurst(clock)
    for i = 1, NB do
      B.on[i], B.t[i] = true, clock
      B.life[i] = 0.8 + rnd() * 1.1
      B.a[i] = (i / NB) * 2 * pi + (rnd() - 0.5) * 0.3
      B.v[i] = 0.55 + rnd() * 0.9
      B.size[i] = 1.2 + rnd() * 2.4
      B.hue[i] = rnd()
      B.spin[i] = (rnd() - 0.5) * 6
    end
  end

  -- ------- the flow

  local ui = {}
  function ui.say(pages, cb) Fx.say(st.words, pages, cb, now(), false) end
  function ui.ask(pages, cb) Fx.say(st.words, pages, cb, now(), true) end
  function ui.wait(sec, fn) st.waitUntil, st.waitFn = now() + sec, fn end
  function ui.done()
    if st.outAt then return end
    st.result, st.outAt = "evolved", now()
  end

  local function startCancel(clock, huh)
    st.phase, st.cancelAt = "cancel", clock
    job.silence()
    if not huh then job.cancelSound() end
    ui.say(job.say(huh and "huh" or "stopped"), function()
      st.result, st.outAt = "stopped", now()
    end)
  end
  local function canStop() return st.phase == "cycle" and job.canStop and st.speed < 128 end
  -- (the stats card: A once to finish the counting, again to go on to the moves)
  local function counted(clock) return clock - st.statsAt >= COUNT + STAGGER * 5 + 0.1 end
  local function statsNext(clock)
    if not counted(clock) then
      st.statsAt = clock - COUNT - STAGGER * 5 - 0.1
      return
    end
    st.phase, st.statsOut = "learn", clock
    job.learn(ui)
  end

  -- (the game's swap, a frame at 60 a second)
  local function swapFrame()
    local spd = st.speed / 256
    if st.dir == 0 then
      st.pre, st.post = max(1 / 16, st.pre - spd), min(1, st.post + spd)
      if st.pre <= 1 / 16 and st.post >= 1 then st.dir, st.speed = 1, st.speed + 2 end
    else
      st.pre, st.post = min(1, st.pre + spd), max(1 / 16, st.post - spd)
      if st.pre >= 1 and st.post <= 1 / 16 then st.dir, st.speed = 0, st.speed + 2 end
    end
  end

  local function step(clock)
    local t = clock - st.at
    if st.phase == "intro" then
      if st.beat == 0 and t >= T_WORDS then
        st.beat = 1
        ui.say(job.say("evolving"), nil)
      end
      if st.beat == 1 and t >= T_CRY then st.beat, st.hop = 2, clock job.cry("from") end
      if st.beat == 2 and t >= T_INTRO then st.beat = 3 job.introMusic() end
      if st.beat == 3 and t >= T_MUSIC then st.beat = 4 job.music() end
      if st.beat == 4 and t >= T_CYCLE then
        st.phase, st.cycleAt, st.last, st.acc = "cycle", clock, clock, 0
        if job.autoCancel then return startCancel(clock, true) end
      end
    elseif st.phase == "cycle" then
      st.acc = st.acc + min(0.25, clock - st.last) * 60
      st.last = clock
      while st.acc >= 1 and st.phase == "cycle" do
        st.acc = st.acc - 1
        st.frame = st.frame + 1
        swapFrame()
        if st.speed >= 128 then
          -- (the point of no return: the change, the flash, the burst)
          st.phase, st.burstAt, st.beat = "burst", clock, 0
          st.pre, st.post = 0, 1
          job.silence()
          job.apply()
          job.burst()
          spawnBurst(clock)
        end
      end
    elseif st.phase == "burst" then
      if st.beat == 0 and clock - st.burstAt >= T_CRY2 then st.beat, st.hop = 1, clock job.cry("to") end
      if st.beat == 1 and clock - st.burstAt >= T_CONGRATS then
        st.beat = 2
        job.fanfare()
        ui.say(job.say("congrats"), function()
          job.restore()
          -- (what each stat gained, on a card, before the moves)
          if job.before and job.after then
            st.phase, st.statsAt = "stats", now()
          else
            st.phase = "learn"
            job.learn(ui)
          end
        end)
      end
    end
    if st.phase == "learn" then job.pump() end
    if st.waitUntil and clock >= st.waitUntil then
      local fn = st.waitFn
      st.waitUntil, st.waitFn = nil, nil
      if fn then fn() end
    end
    -- (the end: down to black, then the game hears back, after the host's gone)
    if st.outAt and not st.finished and clock - st.outAt >= OUT then
      st.finished = true
      if ctx.done then ctx.done() end
      job.finish(st.result or "evolved")
    end
  end

  -- ------- input

  local function press(clock)
    local w = st.words
    if w.pages and w.ask and Fx.waiting(w, clock) then
      Fx.choice(w, w.sel == 1)
      return
    end
    -- (words nothing waits on -- "What? X is evolving!" through the swap -- stay up: A only types them out)
    if w.pages and not w.cb and not w.ask then
      if Fx.typing(w, clock) then w.full = true end
      return
    end
    Fx.press(w, clock)
  end

  function W.input(input, nav)
    local clock = now()
    step(clock)
    if st.outAt then return true end
    if canStop() and (input:wasPressed("b") or (input.isDown and input:isDown("b"))) then
      startCancel(clock, false)
      return true
    end
    if st.phase == "stats" then
      if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then statsNext(clock) end
      return true
    end
    local w = st.words
    if w.pages and w.ask and Fx.waiting(w, clock) then
      if nav and (nav.up or nav.down) then
        w.sel = w.sel == 1 and 2 or 1
        if env.se then pcall(env.se, "SE_SELECT") end
      end
      if input:wasPressed("a") then Fx.choice(w, w.sel == 1)
      elseif input:wasPressed("b") then Fx.choice(w, false) end
      return true
    end
    if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then press(clock) end
    return true
  end

  function W.tap(arg)
    local clock = now()
    if st.outAt then return end
    if arg == A.STOP and canStop() then return startCancel(clock, false) end
    if st.phase == "stats" then return statsNext(clock) end
    if arg == A.YES then return Fx.choice(st.words, true) end
    if arg == A.NO then return Fx.choice(st.words, false) end
    press(clock)
  end

  function W.hints() return nil end
  function W.close()
    -- (taken away before its end, a reset: the game told it's shut, nothing more)
    if not st.finished then
      st.finished = true
      if job.abandon then job.abandon() end
    end
  end

  -- ------- drawing

  -- (the stats card's words and numbers: made once)
  local statWords, statWords5 = {}, {}
  for i = 1, 6 do statWords[i] = T(STAT_KEYS[i]) end
  for i = 1, 5 do statWords5[i] = T(STAT_KEYS5[i]) end
  -- (six stats, or the Game Boy's first games' five)
  local function nStats() return (job.before and #job.before == 5) and 5 or 6 end
  local numT = K.textCache(function(n) return tostring(n) end)
  local plusT = K.textCache(function(n) return (n >= 0 and "+" or "") .. tostring(n) end)
  local levelWord = T.f and T.f("boxes.level", job.level) or ("Lv. " .. tostring(job.level))
  local cardName = tostring(job.toName or "")
  local function cardH() return 13 + nStats() * (8 + (K.textScale() - 1) * 3) + 4 end
  -- the stats card: the new one's name and level, each stat from before to after, counting up, the gain
  local function statsCard(x, y, w, clock, k)
    local G = K.graphics()
    local before, after = job.before, job.after
    local rowH = 8 + (K.textScale() - 1) * 3
    local f0 = K.getFade()
    K.setFade(f0 * min(1, k))
    local card = K.R(x, y, w, cardH())
    K.glass(card, 6, 0.9, C.white, 0.55, 0.9)
    K.bold(cardName, x + 5, y + 3.5, K.fit(cardName, 5.4, w - 30), C.ink)
    K.text(levelWord, x, y + 4, 4.2, C.soft, "right", w - 5)
    local t = clock - st.statsAt
    local vx, ax, nx = x + w * 0.45, x + w * 0.6, x + w * 0.66
    local n = nStats()
    local words = n == 5 and statWords5 or statWords
    for i = 1, n do
      local ry = y + 13 + (i - 1) * rowH
      local e = K.outCubic(min(1, max(0, (t - (i - 1) * STAGGER) / COUNT)))
      if i % 2 == 0 then
        K.col(C.ink, 0.05)
        K.box("fill", K.R(x + 3, ry - 1, w - 6, rowH), 2)
      end
      local ty = ry + (rowH - 4.4 * 1.2) / 2 - 1
      K.text(words[i], x + 6, ty, 4.4, C.soft)
      K.text(numT(before[i]), vx - 14, ty, 4.4, C.soft, "right", 14)
      K.col(C.soft, 0.8)
      G.setLineWidth(max(1, 0.5 * K.sc))
      local my = ty + 2.6
      G.line(K.X(ax - 3), K.Y(my), K.X(ax + 1.5), K.Y(my))
      G.line(K.X(ax), K.Y(my - 1.3), K.X(ax + 1.6), K.Y(my), K.X(ax), K.Y(my + 1.3))
      local shown = floor(before[i] + (after[i] - before[i]) * e + 0.5)
      K.bold(numT(shown), nx, ty, 4.6, C.ink)
      local gain = after[i] - before[i]
      if e > 0.02 and gain ~= 0 then
        local f1 = K.getFade()
        K.setFade(f1 * min(1, e * 2))
        K.bold(plusT(gain), x, ty, 4.4, gain > 0 and GREEN or RED, "right", w - 6)
        K.setFade(f1)
      end
    end
    K.addHit(card, "win", A.STATS)
    K.setFade(f0)
  end

  -- (the new one's name and types: a ribbon down from the top once it's out of the flash)
  local function typeWord(id)
    if not id then return "" end
    local k = "type." .. tostring(id)
    return T.has and T.has(k) and T(k) or ""
  end
  local w1, w2 = typeWord(t1), t2 and typeWord(t2) or nil
  local newName = tostring(job.toName or "")
  local function chip(id, name, x, y, h)
    local tw = K.width(name, h * 0.6) + h * 1.25
    K.col(TYPE[id] or TYPE[0], 0.95)
    K.box("fill", K.R(x, y, tw, h), h / 2)
    if env.typeArt then pcall(env.typeArt.type, id, x + h * 0.55, y + h / 2, h * 0.64, 0, C.white, 0.95) end
    K.bold(name, x + h * 0.98, y + h * 0.18, h * 0.6, C.white)
    return tw
  end
  local function ribbon(x, y, w, clock)
    if not st.burstAt or st.phase == "cancel" then return end
    local e = K.outBack(min(1, max(0, (clock - st.burstAt - 0.9) / 0.45)))
    if e <= 0 then return end
    local ns, ch = 6.6, 6.2
    local nw = K.width(newName, ns)
    local cw = K.width(w1, ch * 0.6) + ch * 1.25 + (w2 and K.width(w2, ch * 0.6) + ch * 1.25 + 2 or 0)
    local rw = nw + 6 + cw + 12
    local rh = 12
    local rx, ry = x + (w - rw) / 2, y + 5 - (1 - e) * 16
    local f0 = K.getFade()
    K.setFade(f0 * min(1, e))
    K.glass(K.R(rx, ry, rw, rh), rh / 2, 0.3, C.white, 0.35, 0.7)
    K.bold(newName, rx + 6, ry + (rh - ns * 1.2) / 2, ns, C.white)
    local cx = rx + 6 + nw + 6
    cx = cx + chip(t1, w1, cx, ry + (rh - ch) / 2, ch) + 2
    if t2 then chip(t2, w2, cx, ry + (rh - ch) / 2, ch) end
    K.setFade(f0)
  end

  local function swirl(cx, cy, rad, clock, front, cyc)
    for i = 1, NS do
      if S.on[i] then
        local age = (clock - S.t[i]) / S.life[i]
        if age >= 1 then
          S.on[i] = false
        else
          local th = S.a[i] + S.w[i] * (clock - S.t[i])
          local depth = sin(th)
          if (depth >= 0) == front then
            local rr = rad * S.r[i] * (1 - age) ^ 1.25
            local x = cx + cos(th) * rr
            local y = cy + depth * rr * 0.36 + S.y[i] * rad * (1 - age)
            local a = sin(pi * age) * (0.55 + 0.45 * (depth + 1) / 2)
            local s = S.size[i] * (0.75 + 0.35 * depth) * (0.8 + cyc * 0.5)
            local c = S.hue[i] < 0.4 and C.white or (S.hue[i] < 0.7 and n1 or n2)
            -- (a short tail along its way)
            for k = 3, 1, -1 do
              local tk = th - k * 0.11
              local tx = cx + cos(tk) * rr * (1 + k * 0.02)
              local ty = cy + sin(tk) * rr * 0.36 + S.y[i] * rad * (1 - age)
              K.glow(tx, ty, s * (1 - k * 0.2), s * (1 - k * 0.2), c, a * 0.22 / k)
            end
            K.glow(x, y, s * 2.6, s * 2.6, c, a * 0.62)
            if S.star[i] then
              Fx.star(x, y, s * 1.3, C.white, a, clock * 3 + i)
            else
              K.col(C.white, a)
              K.graphics().circle("fill", K.X(x), K.Y(y), max(0.6, s * 0.45 * K.sc))
            end
          end
        end
      end
    end
  end

  local function burst(cx, cy, rad, clock)
    if not st.burstAt then return end
    local G = K.graphics()
    for i = 1, NB do
      if B.on[i] then
        local tt = clock - B.t[i]
        local age = tt / B.life[i]
        if age >= 1 then
          B.on[i] = false
        else
          local d = rad * 1.6 * B.v[i] * K.outCubic(min(1, tt / 0.9))
          local x = cx + cos(B.a[i]) * d
          local y = cy + sin(B.a[i]) * d * 0.8 + 10 * age * age
          local a = (1 - age) ^ 1.4
          local c = B.hue[i] < 0.35 and C.gold or (B.hue[i] < 0.7 and n1 or n2)
          K.glow(x, y, B.size[i] * 2.2, B.size[i] * 2.2, c, a * 0.5)
          Fx.star(x, y, B.size[i] * (1 - age * 0.5), C.white, a, B.spin[i] * tt)
        end
      end
    end
    -- (the ring: out from the Pokémon, thinning)
    local rt = (clock - st.burstAt) / 0.7
    if rt < 1 then
      local rr = rad * (0.3 + 2.4 * K.outCubic(rt))
      G.setBlendMode("add")
      K.col(C.white, (1 - rt) * 0.8)
      G.setLineWidth(max(1, (5 * (1 - rt) + 0.5) * K.sc))
      G.ellipse("line", K.X(cx), K.Y(cy), rr * K.sc, rr * 0.82 * K.sc)
      K.col(n1, (1 - rt) * 0.5)
      G.setLineWidth(max(1, (2.5 * (1 - rt) + 0.4) * K.sc))
      G.ellipse("line", K.X(cx), K.Y(cy), rr * 0.8 * K.sc, rr * 0.66 * K.sc)
      G.setBlendMode("alpha")
    end
  end

  -- (round the new one: stars winking in and out)
  local function twinkles(cx, cy, rad, clock)
    if not st.burstAt then return end
    local tb = clock - st.burstAt
    for i = 1, NT do
      local tt = tb - 0.3 - TW.at[i] * 0.6
      if tt > 0 then
        local a = max(0, sin((tt * 1.3 + TW.at[i]) * pi)) * min(1, tt * 2)
        if a > 0.02 then
          local c = TW.hue[i] < 0.5 and C.white or (TW.hue[i] < 0.8 and n1 or C.gold)
          local x, y = cx + TW.x[i] * rad * 1.4, cy + TW.y[i] * rad * 1.2
          K.glow(x, y, TW.size[i] * 2, TW.size[i] * 2, c, a * 0.4)
          Fx.star(x, y, TW.size[i] * a, C.white, a, 0)
        end
      end
    end
  end

  function W.draw(body, clock, portrait)
    clock = now()
    step(clock)
    local G = K.graphics()
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local bh = Fx.bubbleH()
    local foot = y + h - bh - 4
    local rad = min((foot - y) * 0.42, w * 0.3, 52)
    local cx, cy = x + w / 2, y + (foot - y) * 0.5 + 2
    -- (the stats card: the Pokémon steps aside for it when there's room, the card beside it; else over its foot)
    local sk = 0
    if st.statsAt and st.phase == "stats" then sk = K.outCubic(min(1, (clock - st.statsAt) / 0.35))
    elseif st.statsOut then sk = 1 - min(1, (clock - st.statsOut) / CARD_OUT) end
    local side = w >= 200 and not portrait
    if side and sk > 0 then cx = cx - w * 0.2 * sk end
    -- (how lit the sky is: up as the music starts, full through the swap, calming after)
    local t = clock - st.at
    local lit = 0
    if st.phase == "intro" then lit = max(0, min(1, (t - T_MUSIC) / (T_CYCLE - T_MUSIC))) * 0.85
    elseif st.phase == "cycle" then lit = 0.85 + min(0.15, (st.speed - 8) / 800)
    elseif st.phase == "cancel" then lit = max(0, 0.85 - (clock - st.cancelAt) * 1.5)
    else lit = st.burstAt and max(0.45, 1 - (clock - st.burstAt) * 0.4) or 0.45 end
    local cyc = st.phase == "cycle" and min(1, (st.speed - 8) / 120) or (st.phase == "burst" and 1 or 0)
    -- (the screen shaking at the flash)
    if st.burstAt then
      local ts = clock - st.burstAt
      if ts < 0.6 then
        local s = (1 - ts / 0.6) * 2.2
        cx, cy = cx + sin(ts * 71) * s, cy + cos(ts * 53) * s * 0.7
      end
    end

    -- the night: dark, a light in the new one's colours rising behind it, the far lights drifting up
    local b = K.R(x, y, w, h)
    K.grad(b, 0, C.night, C.nightFoot)
    K.glow(cx, cy, w * 0.75, h * 0.7, n1, 0.18 + 0.35 * lit)
    K.glow(cx, cy + rad * 0.3, w * 0.5, h * 0.45, n2, 0.12 + 0.25 * lit)
    for i = 1, NL do
      local yy = (LT.y[i] - clock * LT.v[i]) % 1
      local lx, ly = x + LT.x[i] * w, y + yy * h
      K.glow(lx, ly, LT.s[i], LT.s[i], LT.hue[i] < 0.5 and n1 or C.ice, (0.05 + 0.08 * lit) * sin(yy * pi))
    end
    -- (rays turning behind it, faster as it speeds up)
    if lit > 0.01 then
      G.setBlendMode("add")
      local turn = clock * (0.12 + cyc * 0.9)
      Fx.rays(cx, cy, max(w, h), 14, turn, n1, 0.07 * lit, 0.13)
      Fx.rays(cx, cy, max(w, h), 14, -turn * 0.7 + 0.11, C.white, 0.05 * lit, 0.06)
      G.setBlendMode("alpha")
    end
    -- (sparkles swirling in while it changes)
    if st.phase == "cycle" then
      st.spawnAcc = st.spawnAcc + (clock - (st.spawnLast or clock)) * (34 + cyc * 90)
      while st.spawnAcc >= 1 do
        st.spawnAcc = st.spawnAcc - 1
        spawnSwirl(clock, cyc)
      end
    end
    st.spawnLast = clock
    swirl(cx, cy, rad * 1.25, clock, false, cyc)

    -- the Pokémon: in colour, going white as the music starts, the two silhouettes trading places, the new one
    -- out of the flash in colour
    local size = rad * 1.75
    local hopY = 0
    if st.hop and clock - st.hop < 0.5 then hopY = -abs(sin((clock - st.hop) / 0.5 * pi * 2)) * 2.5 end
    K.glow(cx, cy, rad * (1.1 + 0.25 * cyc), rad * (1.0 + 0.2 * cyc), C.white, 0.12 + 0.3 * lit)
    local picFrom, picTo = job.pic("from"), job.pic("to")
    if st.phase == "intro" then
      local wht = max(0, min(1, (t - T_MUSIC) / (T_CYCLE - T_MUSIC)))
      Fx.pic(picFrom, cx, cy + hopY, size, 1, 1, 1, 1, 1, false)
      if wht > 0 then Fx.pic(picFrom, cx, cy + hopY, size, 1, 1, 1, 1, wht, true) end
    elseif st.phase == "cycle" then
      -- (each one's glow behind its silhouette)
      G.setBlendMode("add")
      Fx.pic(picFrom, cx, cy, size, st.pre * 1.08, 0.75, 0.85, 1, 0.35, true)
      Fx.pic(picTo, cx, cy, size, st.post * 1.08, n1[1] / 255, n1[2] / 255, n1[3] / 255, 0.35, true)
      G.setBlendMode("alpha")
      Fx.pic(picFrom, cx, cy, size, st.pre, 0.94, 0.97, 1, 1, true)
      Fx.pic(picTo, cx, cy, size, st.post, 1, 1, 1, 1, true)
    elseif st.phase == "cancel" then
      local k = min(1, (clock - st.cancelAt) / 0.6)
      local pre = st.pre + (1 - st.pre) * K.outCubic(k)
      local post = st.post * (1 - K.outCubic(k))
      Fx.pic(picTo, cx, cy, size, post, 1, 1, 1, 1, true)
      Fx.pic(picFrom, cx, cy, size, pre, 1, 1, 1, 1, false)
      Fx.pic(picFrom, cx, cy, size, pre, 1, 1, 1, 1 - k, true)
    else
      local tb = st.burstAt and clock - st.burstAt or 1
      local pop = 0.86 + 0.14 * K.outBack(min(1, tb / 0.5))
      local breathe = 1 + sin(clock * 2.2) * 0.012
      Fx.pic(picTo, cx, cy + hopY, size, pop * breathe, 1, 1, 1, 1, false)
      local wa = 1 - min(1, tb / 0.7)
      if wa > 0 then Fx.pic(picTo, cx, cy + hopY, size, pop, 1, 1, 1, wa, true) end
    end
    swirl(cx, cy, rad * 1.25, clock, true, cyc)
    burst(cx, cy, rad, clock)
    twinkles(cx, cy, rad, clock)

    ribbon(x, y, w, clock)
    if sk > 0 and job.before and job.after then
      local cw = side and min(130, w * 0.42) or min(w - 16, 140)
      local ch = cardH()
      local cardX = side and (x + w * 0.5 + (w * 0.5 - cw) / 2 + (1 - sk) * 20) or (x + (w - cw) / 2)
      local cardY = side and (y + (foot - y - ch) / 2 + 4) or (foot - ch + (1 - sk) * 10)
      statsCard(cardX, cardY, cw, clock, sk)
    end
    -- (the flash: white over everything, held a moment, then fading as the new one shows)
    if st.burstAt then
      local tb = clock - st.burstAt
      local fa = tb < 0.12 and 1 or max(0, 1 - (tb - 0.12) / 0.75)
      if fa > 0 then
        K.col(C.white, fa)
        K.box("fill", b)
      end
    end
    -- (a tap anywhere goes on with the words; the buttons over it)
    if st.words.pages and not st.words.ask then K.addHit(K.R(x, y, w, foot - y), "win", A.WORDS) end
    -- (Stop: while it still can be stopped)
    if canStop() then
      local label = T("evo.stop")
      local sw = K.width(label, 4.2) + 12
      local sb = K.R(x + w - sw - 4, y + 4, sw, 9)
      K.glass(sb, 4.5, 0.35, C.white, 0.3, 0.6)
      K.text("B", sb[1] + 3, sb[2] + 2.2, 3.6, C.white)
      K.bold(label, sb[1] + 8, sb[2] + 1.9, 4.2, C.white)
      K.addHit(sb, "win", A.STOP)
    end
    -- the words along the foot
    Fx.bubble(st.words, K.R(x + 6, y + h - bh - 3, w - 12, bh), clock, A.WORDS, A.YES, A.NO)
    -- (in from black, out to it)
    local black = 1 - min(1, (clock - t0) / 0.35)
    if st.outAt then black = max(black, min(1, (clock - st.outAt) / OUT)) end
    if black > 0 then
      K.col(C.black, black)
      K.box("fill", b)
    end
  end

  return W
end
