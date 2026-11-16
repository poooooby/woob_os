-- Errands (the model is src/errands.lua, env.errands). Two tabs:
--   Jobs  the three jobs posted (new every six hours) beside the chosen one: what it is, the types it
--         favours, the level it has in mind, how long, what it pays; Choose Team opens the picker (the
--         party, then a box): up to three, a star on the ones whose types suit it, the grade they'd
--         earn, Send
--   Out   the teams out: how long is left, then Back and Collect (money, the item, EXP for each);
--         Call Back brings a team home early with nothing (asked twice)
--   buttons  L / R the tab (the box, picking), Up / Down choose, A choose / add / collect, START send,
--            SELECT call back, B back / close
--   touch    the tabs, a row, the buttons; drag (or the wheel) scrolls the picker
--
-- The Pokédex's glass: panes over a backdrop lit by the chosen job's colour (eased as the choice
-- changes). Its motion, numbers only (`mv`): the cards rising in one after another on a tab, the chosen
-- job's highlight gliding, its card sliding in, Jobs | Out's thumb sliding, the picker's rows rising in
-- from the side the box turned to and its highlight gliding, a team's Pokémon popping into their slots,
-- the medal popping and the strength bar filling, the teams' rings filling and a second hand sweeping
-- them, the time left flipping over each minute, a team back glowing.
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, sin, cos, pi, abs = math.floor, math.max, math.min, math.sin, math.cos, math.pi, math.abs

local M, ROW_H = 3, 12
local TAB_JOBS, TAB_OUT, GO, BOX_PREV, BOX_NEXT, SEND, ROW, JOB, COLLECT, RECALL =
  2001, 2002, 2003, 2004, 2005, 2006, 3000, 4000, 5000, 5100
local HINTS = {
  jobs = { { "^ v", "hint.choose" }, { "A", "errands.chooseTeam" }, { "L R", "hint.tab" }, { "B", "hint.close" } },
  pick = { { "A", "errands.add" }, { "L R", "hint.box" }, { "START", "errands.send" }, { "B", "hint.back" } },
  out = { { "^ v", "hint.choose" }, { "A", "errands.collect" }, { "SELECT", "errands.recall" }, { "L R", "hint.tab" },
          { "B", "hint.close" } },
}
local GRADE_KEY = { great = "errands.grade.great", good = "errands.grade.good", ok = "errands.grade.ok" }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, Er, Bx, T = env.K, env.errands, env.bx, env.T or NO_T
  local UI = K.UI
  local W = { title = T("app.errands"), pad = true }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local st = { tab = "jobs", job = 1, out = 1, picking = false, box = 1, rows = {}, cursor = 1, top = 0, visible = 6,
               team = {}, grade = nil, score = 0, toast = nil, keys = false, recallAt = -10, recallI = nil, typeText = {} }
  W.state = st
  if Bx and Bx.current then st.box = Bx.current(session()) or 1 end
  local resume = ctx.resume
  if resume and resume.app == ctx.app and type(resume.state) == "table" and resume.state.tab == "out" then st.tab = "out" end
  ctx.resume = nil

  local function commas(n)
    local s = tostring(floor(n))
    repeat
      local k
      s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return s
  end
  local levelText = K.textCache(function(n) return T.f("boxes.level", n) end)
  local hoursText = K.textCache(function(h) return T.f("errands.hours", h) end)
  local bestText = K.textCache(function(n) return T.f("errands.best", n) end)
  local leftText = K.textCache(function(mins)
    if mins >= 60 then return T.f("errands.leftH", floor(mins / 60), mins % 60) end
    return T.f("errands.leftM", max(1, mins))
  end)
  local timesText = K.textCache(function(n) return "x" .. n end)
  -- (each job's favoured types, in the game's own words, once)
  local function typeText(job)
    local t = st.typeText[job.id]
    if not t then
      local parts = {}
      for i, id in ipairs(job.types) do
        local ok, name = false, nil
        if env.typeName then ok, name = pcall(env.typeName, id) end
        parts[i] = ok and name or tostring(id)
      end
      t = table.concat(parts, " · ")
      st.typeText[job.id] = t
    end
    return t
  end

  local function toast(text, bad) st.toast = { text = text, bad = bad, t = now() } end
  local function why(reason) return T("reason.errands." .. tostring(reason)) end
  local function post() return Er.board(session())[st.job] end

  -- ------- the picker (rows made on a change, never in a draw)
  local function chosen(addr)
    for i, a in ipairs(st.team) do if a == addr then return i end end
    return nil
  end
  local function rebuild()
    local s = session()
    local rows = st.rows
    local job = post() and Er.job(post().job)
    local n = 0
    for _, addr in ipairs(Er.candidates(s, st.box)) do
      local mon = Bx.get(s, addr)
      if mon then
        n = n + 1
        local r = rows[n] or {}
        rows[n] = r
        local info = Bx.info(mon, T)
        r.addr, r.mon, r.name, r.level, r.party = addr, mon, info.name or "?", info.level or 1, addr.loc == "party"
        local ok, reason = Er.canSend(s, addr)
        r.ok, r.why = ok, (not ok) and why(reason) or nil
        r.fit = job and Er.fit(job, mon) or false
      end
    end
    for i = n + 1, #rows do rows[i] = nil end
    st.cursor = max(1, min(st.cursor, n))
  end
  -- the grade the chosen team would earn (worked out on a change)
  local function regrade()
    local job = post() and Er.job(post().job)
    if not job or #st.team == 0 then st.grade, st.score = nil, 0 return end
    local s = session()
    local score = #st.team - 1
    for _, addr in ipairs(st.team) do
      local mon = Bx.get(s, addr)
      if mon then
        if Er.fit(job, mon) then score = score + 2 end
        if (tonumber(mon.level) or 1) >= job.level then score = score + 1 end
      end
    end
    st.grade = score >= 6 and "great" or (score >= 3 and "good" or "ok")
    st.score = score
  end
  local function openPicker()
    local p = post()
    if not p then return end
    if p.taken then se("SE_FAILURE") return toast(why("taken"), true) end
    if #Er.out() >= Er.MAX then se("SE_FAILURE") return toast(why("busy"), true) end
    st.picking, st.team, st.cursor, st.top = true, {}, 1, 0
    rebuild()
    regrade()
    se("SE_SELECT")
  end
  local function toggle(i)
    local r = st.rows[i]
    if not r then return end
    local at = chosen(r.addr)
    if at then
      table.remove(st.team, at)
    elseif not r.ok then
      se("SE_FAILURE")
      return toast(r.why, true)
    elseif #st.team >= 3 then
      se("SE_FAILURE")
      return toast(why("team"), true)
    else
      st.team[#st.team + 1] = r.addr
    end
    regrade()
    se("SE_SELECT")
  end
  local function send()
    if #st.team == 0 then se("SE_FAILURE") return toast(why("team"), true) end
    local p = post()
    -- (addresses are shared records: copied, as the party shifts while they go)
    local addrs = {}
    for i, a in ipairs(st.team) do addrs[i] = Bx.addr(a.loc, a.slot, a.boxId) end
    local ok, e = Er.send(session(), p.key, addrs)
    if not ok then se("SE_FAILURE") return toast(why(e), true) end
    se("SE_BALL_TRAY_BALL")
    if env.pad and env.pad.transfer then
      pcall(env.pad.transfer, tonumber(e.team[1].species or e.team[1].speciesId), "out", "ball")
    end
    st.picking, st.team, st.tab, st.out = false, {}, "out", #Er.out()
    toast(T.f("errands.sent", T("errands.job." .. e.job)), false)
  end
  local function collect(i)
    local e = Er.out()[i]
    if not e then return end
    if not e.back then se("SE_FAILURE") return toast(why("not_back"), true) end
    local ok, done, gained = Er.collect(session(), i)
    if not ok then se("SE_FAILURE") return toast(why(done), true) end
    se("SE_SUCCESS")
    st.party = now()
    local lv = 0
    for _, g in ipairs(gained or {}) do lv = lv + g end
    local item = env.itemName and env.itemName(done.reward.item) or tostring(done.reward.item)
    toast(T.f(lv > 0 and "errands.gotLevels" or "errands.got", commas(done.reward.money), item, done.reward.n, lv), false)
    if env.pad and env.pad.transfer then pcall(env.pad.transfer, done.reward.item, "in") end
    st.out = max(1, min(st.out, #Er.out()))
  end
  local function recall(i)
    local e = Er.out()[i]
    if not e or e.back then return collect(i) end
    if st.recallI ~= i or now() - st.recallAt > 3 then
      st.recallI, st.recallAt = i, now()
      se("SE_SELECT")
      return toast(T("errands.recallAsk"), false)
    end
    st.recallI = nil
    local ok, reason = Er.recall(session(), i)
    if not ok then se("SE_FAILURE") return toast(why(reason), true) end
    se("SE_SELECT")
    toast(T("errands.recalled"), false)
    st.out = max(1, min(st.out, #Er.out()))
  end

  -- ------- buttons and taps

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
    local s = session()
    pcall(Er.settle, s)
    if st.picking then
      if pressed("b") then st.picking = false se("SE_SELECT") return true end
      if pressed("l") or pressed("r") then
        st.box = (st.box - 1 + (pressed("r") and 1 or -1)) % (Bx.BOXES or 14) + 1
        rebuild()
        se("SE_SELECT")
      elseif pressed("start") then send()
      elseif pressed("a") then toggle(st.cursor)
      elseif nav.up or nav.down then
        st.cursor = max(1, min(#st.rows, st.cursor + (nav.down and 1 or -1)))
        se("SE_SELECT")
      end
      return true
    end
    if pressed("b") then return false end
    if pressed("l") or pressed("r") or pressed("start") then
      st.tab = st.tab == "jobs" and "out" or "jobs"
      se("SE_SELECT")
      return true
    end
    if nav.up or nav.down then
      st.keys = true
      local d = nav.down and 1 or -1
      if st.tab == "jobs" then st.job = max(1, min(3, st.job + d)) else st.out = max(1, min(max(1, #Er.out()), st.out + d)) end
      se("SE_SELECT")
    elseif pressed("a") then
      st.keys = true
      if st.tab == "jobs" then openPicker() else collect(st.out) end
    elseif pressed("select") and st.tab == "out" then
      recall(st.out)
    end
    return true
  end

  function W.tap(arg)
    st.keys = false
    if arg == TAB_JOBS then st.tab, st.picking = "jobs", false return se("SE_SELECT") end
    if arg == TAB_OUT then st.tab, st.picking = "out", false return se("SE_SELECT") end
    if arg == GO then return openPicker() end
    if arg == SEND then return send() end
    if arg == BOX_PREV or arg == BOX_NEXT then
      st.box = (st.box - 1 + (arg == BOX_NEXT and 1 or -1)) % (Bx.BOXES or 14) + 1
      rebuild()
      return se("SE_SELECT")
    end
    if type(arg) ~= "number" then return end
    if arg > RECALL and arg <= RECALL + 3 then return recall(arg - RECALL) end
    if arg > COLLECT and arg <= COLLECT + 3 then return collect(arg - COLLECT) end
    if arg > JOB and arg <= JOB + 3 then
      if st.job == arg - JOB then return openPicker() end
      st.job = arg - JOB
      return se("SE_SELECT")
    end
    if arg > ROW and arg < JOB then
      st.cursor = arg - ROW
      return toggle(arg - ROW)
    end
  end

  function W.scroll(dy)
    if st.picking then st.top = max(0, min(max(0, #st.rows - st.visible), st.top - dy / ROW_H)) end
  end

  function W.hints()
    if st.picking then return T.list(HINTS.pick) end
    return T.list(st.tab == "jobs" and HINTS.jobs or HINTS.out)
  end


  -- ------- drawing (no tables made here)

  local GAP = 2
  local NARROW = 170          -- narrower than this (units): the jobs across the top, the team over the list
  local C = {
    ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, faint = { 160, 160, 170 }, white = { 255, 255, 255 },
    track = { 118, 118, 128, 0.16 }, grey = { 118, 118, 128, 0.16 }, accent = { 10, 132, 255 },
    green = { 52, 199, 89 }, greenTop = { 96, 222, 128 }, greenFoot = { 28, 156, 68 }, greenInk = { 24, 140, 60 },
    redTop = { 255, 112, 100 }, redFoot = { 214, 44, 40 }, gold = { 206, 140, 8 }, warn = { 230, 60, 50 },
    orange = { 255, 149, 0 }, violet = { 150, 120, 190 }, star = { 255, 186, 30 },
  }
  local GLOSS_TOP, GLOSS_FOOT = { 255, 255, 255, 0.38 }, { 255, 255, 255, 0 }
  local MEDAL = { great = { 240, 178, 28 }, good = { 158, 168, 188 }, ok = { 206, 132, 76 } }
  -- the types' colours (the game's ids; 18 WoobleDex's Fairy)
  local TYPE = {
    [0] = { 168, 168, 120 }, [1] = { 192, 48, 40 }, [2] = { 168, 144, 240 }, [3] = { 160, 64, 160 },
    [4] = { 224, 192, 104 }, [5] = { 184, 160, 56 }, [6] = { 168, 184, 32 }, [7] = { 112, 88, 152 },
    [8] = { 184, 184, 208 }, [9] = { 104, 160, 144 }, [10] = { 240, 128, 48 }, [11] = { 104, 144, 240 },
    [12] = { 120, 200, 80 }, [13] = { 248, 208, 48 }, [14] = { 248, 88, 136 }, [15] = { 152, 216, 216 },
    [16] = { 112, 56, 248 }, [17] = { 112, 88, 72 }, [18] = { 238, 153, 172 },
  }
  local NOBODY = { color = C.orange, glyph = "send" }
  -- (the backdrop's eased colour, 0..255: for K.col / K.glow / K.ring only, never K.grad or K.mix, which
  -- keep what they make by the table)
  local TINT = { 160, 160, 160 }
  local num = K.textCache(function(n) return tostring(n) end)

  -- the motion's numbers (see the top)
  local mv = {
    lastT = nil, dt = 0, openAt = nil, tab = nil, tabAt = 0, tabX = st.tab == "out" and 2 or 1,
    job = nil, jobAt = 0, jobY = nil, picking = false, pickAt = 0, box = nil, boxAt = 0, boxDir = 0,
    curY = nil, top = 0, outY = nil, secT = 0, secAt = 0, coloured = false,
    r = 0.6, g = 0.6, b = 0.6, r2 = 0.6, g2 = 0.6, b2 = 0.6, score = 0, grade = nil, gradeAt = -10,
    slot = { false, false, false }, slotAt = { -10, -10, -10 },
    outKey = { false, false, false }, prog = { 0, 0, 0 }, wasBack = { false, false, false }, backAt = { -10, -10, -10 },
    leftMin = { -1, -1, -1 }, leftAt = { -10, -10, -10 }, leftOld = { "", "", "" },
  }
  W.motion = mv

  local CONFETTI_N = 40
  local CONF = { C.orange, C.green, C.star, C.accent, { 255, 55, 95 }, { 175, 82, 222 } }
  local P = {}
  for i = 1, CONFETTI_N do P[i] = { live = false, x = 0, y = 0, vx = 0, vy = 0, t0 = 0, c = nil, spin = 0 } end
  local nextP = 1
  local function confetti(x, y)
    for i = 1, 22 do
      local p = P[nextP]
      nextP = nextP % CONFETTI_N + 1
      local a = (i / 22) * pi * 2 + sin(i * 2.3) * 0.4
      local v = 20 + (i * 13 % 28)
      p.live, p.x, p.y, p.vx, p.vy, p.t0 = true, x, y, cos(a) * v, sin(a) * v - 16, now()
      p.c, p.spin = CONF[i % #CONF + 1], (i * 0.41) % 1
    end
  end
  -- (each type's name, once)
  local typeNames = {}
  local function typeName(id)
    local n = typeNames[id]
    if not n then
      local ok, got = false, nil
      if env.typeName then ok, got = pcall(env.typeName, id) end
      n = ok and got or tostring(id)
      typeNames[id] = n
    end
    return n
  end

  local function money(n, x, y, size, c, right)
    if not env.amount then return 0 end
    local ok, w = pcall(env.amount, n, 0, 0, size, c, true)
    w = ok and tonumber(w) or 0
    pcall(env.amount, n, right and x - w or x, y, size, c)
    return w
  end
  -- a job's tile: its colour, a gloss, its picture
  local function tile(job, x, y, size, a)
    a = a or 1
    local b = K.R(x, y, size, size)
    local rad = size * 0.26
    K.shadow(b, rad, 0.6, 0.16 * a)
    K.grad(b, rad, K.light(job.color, 0.18), K.dark(job.color, 0.2), a)
    K.grad(K.R(x + size * 0.06, y + size * 0.04, size * 0.88, size * 0.46), rad * 0.85, GLOSS_TOP, GLOSS_FOOT, a)
    K.ring(b, rad, C.white, 0.3 * a, 0.4)
    if env.glyph then
      pcall(env.glyph, K.graphics(), job.glyph, K.X(x + size / 2), K.Y(y + size / 2), size * K.sc, a * K.getFade(), job.color)
    end
  end
  -- a type's pill -> its width
  local function pill(id, x, y, h, size)
    local name = typeName(id)
    local pw = K.width(name, size) + 5
    K.col(TYPE[id] or C.faint)
    K.box("fill", K.R(x, y, pw, h), h / 2)
    K.text(name, x, y + (h - size * 1.2) / 2, size, C.white, "center", pw)
    return pw
  end
  -- (a: the whole chip's)
  local function chip(text, x, y, size, ink, a)
    local w = K.width(text, size) + 4
    K.col(C.track, a)
    K.box("fill", K.R(x, y, w, size + 2.4), (size + 2.4) / 2)
    K.text(text, x + 2, y + 1.2, size, ink or C.soft, nil, nil, a)
    return w
  end
  local function medal(cx, cy, r, grade, clock)
    if r <= 0.05 then return end
    local G = K.graphics()
    local c = MEDAL[grade] or MEDAL.ok
    K.glow(cx, cy, r * 2.2, r * 2.2, c, 0.25)
    K.col(c)
    G.circle("fill", K.X(cx), K.Y(cy), r * K.sc)
    K.col(K.dark(c, 0.25))
    G.setLineWidth(max(1, r * 0.18 * K.sc))
    G.circle("line", K.X(cx), K.Y(cy), r * 0.72 * K.sc)
    K.col(C.white, 0.45 + 0.3 * sin(clock * 3))
    G.circle("fill", K.X(cx - r * 0.3), K.Y(cy - r * 0.35), r * 0.22 * K.sc)
  end
  -- a four-pointed star: two thin diamonds crossed (love's fills are convex)
  local function star(cx, cy, r)
    local G = K.graphics()
    K.col(C.star)
    local x, y, rr, q = K.X(cx), K.Y(cy), r * K.sc, r * K.sc * 0.3
    G.polygon("fill", x, y - rr, x + q, y, x, y + rr, x - q, y)
    G.polygon("fill", x - rr, y, x, y - q, x + rr, y, x, y + q)
  end
  -- a capsule: filled top to foot when on (a soft light breathing round it), grey when not
  local function button(b, label, on, focused, top, foot, clock)
    local rad = b[4] / 2
    if on then
      K.glow(b[1] + b[3] / 2, b[2] + b[4] / 2, b[3] * 0.62, b[4] * 1.3, top, 0.14 + 0.08 * sin(clock * 3))
      K.shadow(b, rad, 0.8, 0.16)
      K.grad(b, rad, top, foot)
      K.grad(K.R(b[1] + 0.6, b[2] + 0.4, b[3] - 1.2, b[4] * 0.5), rad * 0.8, GLOSS_TOP, GLOSS_FOOT)
    else
      K.col(C.grey)
      K.box("fill", b, rad)
    end
    if focused then K.focusRing(b, rad) end
    local fs = K.fit(label, 4.4, b[3] - 4)
    K.bold(label, b[1], b[2] + (b[4] - fs * 1.2) / 2, fs, on and C.white or C.faint, "center", b[3])
  end
  -- a ring filling to k (0..1) from the top, on its track
  local function arcRing(cx, cy, r, k, width, c)
    local G = K.graphics()
    G.setLineWidth(max(1, width * K.sc))
    K.col(C.track)
    G.circle("line", K.X(cx), K.Y(cy), r * K.sc)
    if k > 0.002 then
      K.col(c)
      G.arc("line", "open", K.X(cx), K.Y(cy), r * K.sc, -pi / 2, -pi / 2 + 2 * pi * min(1, k), 28)
    end
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
  -- the chosen one's highlight, in the backdrop's colour
  local function glide(b, rad)
    K.col(TINT, 0.2)
    K.box("fill", b, rad)
    K.ring(b, rad, TINT, 0.85, 0.55)
  end

  -- ------- Jobs | Out: the thumb sliding; the count of teams back on Out
  local function drawTabs(x, y, w, clock)
    mv.tabX = K.approach(mv.tabX, st.tab == "jobs" and 1 or 2, mv.dt, 18)
    K.glassSwitch(x, y, w, 8, mv.tabX, "win", TAB_JOBS, T("errands.jobs"), TAB_OUT, T("errands.out"), nil, nil, 4.2)
    local back = Er.waiting()
    if back > 0 then
      local G = K.graphics()
      local bx, by = x + w - 5, y + 4
      K.glow(bx, by, 5, 5, C.green, 0.25 + 0.15 * sin(clock * 4))
      K.col(C.green)
      G.circle("fill", K.X(bx), K.Y(by), (2.7 + 0.2 * sin(clock * 5)) * K.sc)
      K.bold(num(back), bx - 3, by - 3.4 * 0.6, 3.4, C.white, "center", 6)
    end
  end

  -- ------- Jobs: the three posted, the chosen one's card
  local function jobCard(i, p, b, clock, wide)
    local job = Er.job(p.job)
    local a = p.taken and 0.5 or 1
    local on = i == st.job
    local bob = on and sin(clock * 2.2) * 0.6 or 0
    if wide then
      local ts = min(13, b[4] - 6)
      tile(job, b[1] + 3, b[2] + (b[4] - ts) / 2 - bob, ts, a)
      local name = T("errands.job." .. job.id)
      local nx = b[1] + ts + 6
      K.bold(name, nx, b[2] + b[4] / 2 - 5.4, K.fit(name, 4.4, b[1] + b[3] - nx - 3), C.ink, nil, nil, a)
      local cw = chip(hoursText(p.hours), nx, b[2] + b[4] / 2 + 0.6, 3.2, on and C.ink or C.soft, a)
      if p.taken then K.text(T("errands.taken"), nx + cw + 2, b[2] + b[4] / 2 + 1.8, 3.2, C.soft) end
    else
      local ts = min(12, b[4] - 9)
      tile(job, b[1] + (b[3] - ts) / 2, b[2] + 2 - bob, ts, a)
      local word = p.taken and T("errands.taken") or hoursText(p.hours)
      K.text(word, b[1], b[2] + b[4] - 5.6, K.fit(word, 3.2, b[3] - 2), on and C.ink or C.soft, "center", b[3], a)
    end
    K.addHit(b, "win", JOB + i)
  end
  local function drawDetail(p, x, y, w, h, clock)
    local job = Er.job(p.job)
    local since = clock - mv.jobAt
    K.glass(K.R(x, y, w, h), 6)
    -- (the hero: the job's colour, its tile, its picture big and faint at the right)
    local hero = K.R(x + 2, y + 2, w - 4, 21)
    K.grad(hero, 4.5, K.light(job.color, 0.12), K.dark(job.color, 0.22))
    K.grad(K.R(hero[1], hero[2], hero[3], 10), 4.5, GLOSS_TOP, GLOSS_FOOT, 0.6)
    if env.glyph then
      pcall(env.glyph, K.graphics(), job.glyph, K.X(hero[1] + hero[3] - 11), K.Y(hero[2] + hero[4] / 2),
        19 * K.sc, 0.2 * K.getFade(), job.color)
    end
    local e0 = 0.7 + 0.3 * K.outBack(since / 0.4)
    popIn(hero[1] + 10.5, hero[2] + 10.5, e0)
    tile(job, hero[1] + 3, hero[2] + 3 - sin(clock * 2.2) * 0.6, 15)
    popOut(e0)
    local name = T("errands.job." .. job.id)
    local tx = hero[1] + 21
    local e1 = K.stagger(since, 1, 0.04, 0.3)
    K.rise(e1, 0, 5)
    K.label(name, tx, hero[2] + 3.6, K.fit(name, 5.4, hero[1] + hero[3] - tx - 20), C.white)
    K.label(hoursText(p.hours), tx, hero[2] + 11.6, 3.8, C.white, nil, nil, 0.9)
    K.settle(e1)
    -- (what it is)
    local e2 = K.stagger(since, 2, 0.04, 0.3)
    K.rise(e2, 3)
    K.text(T("errands.desc." .. job.id), x + 4, y + 26, 3.5, C.soft, "left", w - 8)
    K.settle(e2)
    -- (the types it favours, popping in in turn; the level; the pay)
    local ty = y + h - 40
    local e3 = K.stagger(since, 3, 0.04, 0.3)
    K.rise(e3, 3)
    K.text(T("errands.favours"), x + 4, ty, 3.2, C.faint)
    K.settle(e3)
    local cx = x + 4
    for k = 1, #job.types do
      local ek = K.stagger(since, 3 + k, 0.04, 0.26)
      K.rise(ek, 2.5)
      cx = cx + pill(job.types[k], cx, ty + 4.2, 5.4, 3.3) + 1.5
      K.settle(ek)
    end
    local e4 = K.stagger(since, 5, 0.04, 0.3)
    K.rise(e4, 3)
    chip(bestText(job.level), x + 4, ty + 11.5, 3.3, C.soft)
    local f = p.hours >= 8 and 5 or (p.hours >= 4 and 3 or 1)
    K.text(T("errands.pays"), x + 4, ty + 18.2, 3.2, C.faint)
    local lw2 = money(job.money[1] * f, x + 4, ty + 22, 4, C.gold)
    K.text("-", x + 5.5 + lw2, ty + 22, 4, C.soft)
    money(job.money[2] * f, x + 9 + lw2, ty + 22, 4, C.gold)
    K.settle(e4)
    local gb = K.R(x + 4, y + h - 13, w - 8, 10)
    local can = not p.taken and #Er.out() < Er.MAX
    button(gb, T(p.taken and "errands.taken" or "errands.chooseTeam"), can, st.keys and can, K.light(job.color, 0.08),
      K.dark(job.color, 0.2), clock)
    K.addHit(gb, "win", GO)
  end
  local function drawJobs(x, y, w, h, clock)
    local board = Er.board(session())
    local n = #board
    if n == 0 then return end
    local wide = w >= NARROW
    local since = clock - mv.tabAt
    local lw = floor(w * 0.4)
    local ch = wide and (h - (n - 1) * GAP) / n or 22
    local cw = (w - (n - 1) * GAP) / n
    if mv.jobY == nil then mv.jobY = st.job end
    mv.jobY = K.approach(mv.jobY, st.job, mv.dt, 20)
    -- (the panes rising in one after another, the highlight gliding over them, then what's on them)
    for i = 1, n do
      local e = K.stagger(since, i - 1, 0.05, 0.3)
      K.rise(e, 5)
      local b = wide and K.R(x, y + (i - 1) * (ch + GAP), lw, ch) or K.R(x + (i - 1) * (cw + GAP), y, cw, ch)
      K.glass(b, 5, board[i].taken and 0.3 or 0.5)
      K.settle(e)
    end
    local e0 = K.stagger(since, 1, 0.05, 0.3)
    K.rise(e0, 0)
    if wide then glide(K.R(x, y + (mv.jobY - 1) * (ch + GAP), lw, ch), 5)
    else glide(K.R(x + (mv.jobY - 1) * (cw + GAP), y, cw, ch), 5) end
    K.settle(e0)
    for i = 1, n do
      local e = K.stagger(since, i - 1, 0.05, 0.3)
      K.rise(e, 5)
      local b = wide and K.R(x, y + (i - 1) * (ch + GAP), lw, ch) or K.R(x + (i - 1) * (cw + GAP), y, cw, ch)
      jobCard(i, board[i], b, clock, wide)
      K.settle(e)
    end
    -- (the chosen job's card sliding in as the choice changes)
    local p = board[st.job]
    if not p then return end
    local dx, dy, dw, dh
    if wide then dx, dy, dw, dh = x + lw + GAP + 1, y, w - lw - GAP - 1, h
    else dx, dy, dw, dh = x, y + ch + GAP, w, h - ch - GAP end
    local ed = min(K.stagger(since, 2, 0.05, 0.34), 0.4 + 0.6 * K.outCubic((clock - mv.jobAt) / 0.3))
    K.rise(ed, wide and 0 or 4, wide and 7 or 0)
    drawDetail(p, dx, dy, dw, dh, clock)
    K.settle(ed)
  end

  -- ------- the picker: the box's Pokémon, the team's three slots, how well they suit it, Send
  local function drawPickTop(x, y, w, job)
    local label = T("errands.jobs")
    K.chevron(x + 2, y + 4.5, 4.2, C.accent, -1)
    K.text(label, x + 4.8, y + 2, 4.2, C.accent)
    K.addHit(K.R(x - 1, y, K.width(label, 4.2) + 9, 9), "win", TAB_JOBS)
    local name = T("errands.job." .. job.id)
    local side = K.width(label, 4.2) + 10
    K.bold(name, x + side, y + 2, K.fit(name, 4.6, w - side * 2), C.ink, "center", w - side * 2)
  end
  local function drawList(x, y, w, h, clock)
    local G = K.graphics()
    K.glass(K.R(x, y, w, h), 5)
    K.chevron(x + 5, y + 5.3, 4, C.accent, -1)
    K.addHit(K.R(x, y, 12, 10), "win", BOX_PREV)
    K.chevron(x + w - 5, y + 5.3, 4, C.accent, 1)
    K.addHit(K.R(x + w - 12, y, 12, 10), "win", BOX_NEXT)
    local since = clock - mv.boxAt
    local eb = K.outCubic(since / 0.26)
    local bname = Bx.boxName(session(), st.box) or ""
    K.bold(bname, x + 12 + (1 - eb) * mv.boxDir * 6, y + 2.7, K.fit(bname, 4.6, w - 26), C.ink, "center", w - 24, eb)
    K.hairline(x + 2, y + 10, w - 4)
    local top = y + 10.5
    local lh = y + h - 1 - top
    st.visible = max(1, floor(lh / ROW_H))
    if st.cursor > st.top + st.visible then st.top = st.cursor - st.visible end
    if st.cursor <= st.top then st.top = st.cursor - 1 end
    st.top = max(0, min(st.top, max(0, #st.rows - st.visible)))
    mv.top = K.approach(mv.top, st.top, mv.dt, 18)
    local clip = K.R(x, top, w, lh)
    K.scissor(clip)
    -- (the cursor's highlight gliding from row to row)
    if #st.rows > 0 then
      if mv.curY == nil then mv.curY = st.cursor end
      mv.curY = K.approach(mv.curY, st.cursor, mv.dt, 24)
      local hb = K.R(x + 1.5, top + (mv.curY - 1 - mv.top) * ROW_H + 0.4, w - 3, ROW_H - 0.8)
      K.col(C.accent, 0.12)
      K.box("fill", hb, 3)
      K.ring(hb, 3, C.accent, 0.85, 0.5)
    end
    -- (the rows rising in, from the side the box turned to)
    local first = floor(mv.top) + 1
    local right = x + w - 4
    for i = first, min(#st.rows, first + st.visible + 1) do
      local r = st.rows[i]
      local ry = top + (i - 1 - mv.top) * ROW_H
      local e = K.stagger(since, i - first, 0.025, 0.24)
      K.rise(e, mv.boxDir == 0 and 3 or 0, mv.boxDir * 8)
      local rb = K.R(x + 1.5, ry + 0.4, w - 3, ROW_H - 0.8)
      local at = chosen(r.addr)
      if at then
        K.col(TINT, 0.24)
        K.box("fill", rb, 3)
      end
      if env.monIconOf then
        pcall(env.monIconOf, r.mon, x + 3, ry + 0.5, 11, floor(clock * 3) % 2, (r.ok and 1 or 0.4) * K.getFade())
      end
      K.text(r.name, x + 15, ry + (r.why and 1.2 or 3.4), K.fit(r.name, 4.4, w - 44), r.ok and C.ink or C.faint)
      if r.why then K.text(r.why, x + 15, ry + 6.6, K.fit(r.why, 3.1, w - 40), C.warn) end
      K.text(levelText(r.level), right - 18, ry + 3.4, 3.6, C.soft, "right", 18)
      if r.fit then star(right - 22, ry + ROW_H / 2, 1.6 + 0.3 * sin(clock * 5 + i)) end
      if at then
        -- (its place on the team)
        local dcx, dcy = x + 13.2, ry + 2.6
        K.col(TINT)
        G.circle("fill", K.X(dcx), K.Y(dcy), 2.3 * K.sc)
        K.text(num(at), dcx - 2.5, dcy - 3 * 0.6, 3, C.white, "center", 5)
      end
      K.addHit(rb, "win", ROW + i, clip)
      K.settle(e)
    end
    if #st.rows == 0 then K.text(T("gts.emptyBox"), x, top + lh / 2 - 3, 4.2, C.faint, "center", w) end
    K.scrollbar(x + w, top, lh, mv.top, st.visible, #st.rows)
    K.scissor(st.clip)
  end
  -- the three slots, s units square: each Pokémon popping in as it's added
  local function drawSlots(x, y, s, clock)
    local sess = session()
    for i = 1, 3 do
      local a = st.team[i]
      local want = a or false
      if mv.slot[i] ~= want then mv.slot[i], mv.slotAt[i] = want, clock end
      local sb = K.R(x + (i - 1) * (s + GAP), y, s, s)
      local cx, cy = sb[1] + s / 2, sb[2] + s / 2
      local mon = a and Bx.get(sess, a)
      if mon then
        local pe = K.outBack((clock - mv.slotAt[i]) / 0.36)
        K.glow(cx, cy, s * 0.7, s * 0.7, TINT, 0.22 * min(1, pe))
        K.col(TINT, 0.22)
        K.box("fill", sb, 4)
        K.ring(sb, 4, TINT, 0.85, 0.5)
        local is = min(13, s - 3) * (0.3 + 0.7 * pe)
        local bob = sin(clock * 4 + i) * 0.6
        if env.monIconOf then
          pcall(env.monIconOf, mon, cx - is / 2, cy - is / 2 + bob, is, floor(clock * 3) % 2, K.getFade())
        end
      else
        K.col(C.white, 0.32)
        K.box("fill", sb, 4)
        K.ring(sb, 4, C.faint, 0.5, 0.35)
        K.text("+", sb[1], cy - 3, 5, C.faint, "center", s)
      end
    end
  end
  -- the medal they'd earn popping up, its word, the bar of how well they suit it filling (OK | Good | Great)
  local function drawGrade(x, y, w, clock)
    if mv.grade ~= st.grade then mv.grade, mv.gradeAt = st.grade, clock end
    mv.score = K.approach(mv.score, min(1, (st.score or 0) / 8), mv.dt, 6)
    local by = y + 8.5
    K.col(C.track)
    K.box("fill", K.R(x, by, w, 2), 1)
    if st.grade and mv.score > 0.01 then
      K.col(MEDAL[st.grade])
      K.box("fill", K.R(x, by, max(2, w * mv.score), 2), 1)
    end
    K.col(C.white, 0.9)
    K.box("fill", K.R(x + w * 3 / 8 - 0.2, by, 0.4, 2))
    K.box("fill", K.R(x + w * 6 / 8 - 0.2, by, 0.4, 2))
    if st.grade then
      local pe = K.outBack((clock - mv.gradeAt) / 0.42)
      medal(x + 3.2, y + 3.4, 3.2 * pe, st.grade, clock)
      K.bold(T(GRADE_KEY[st.grade]), x + 8.5, y + 1.4, 4.2, K.dark(MEDAL[st.grade], 0.25), nil, nil, min(1, pe))
    end
  end
  local function drawTeam(x, y, w, h, job, p, clock)
    K.glass(K.R(x, y, w, h), 6)
    local hero = K.R(x + 2, y + 2, w - 4, 15)
    K.grad(hero, 4.5, K.light(job.color, 0.12), K.dark(job.color, 0.22))
    tile(job, hero[1] + 2, hero[2] + 2, 11)
    local name = T("errands.job." .. job.id)
    K.label(name, hero[1] + 16, hero[2] + 2.2, K.fit(name, 4.6, hero[3] - 19), C.white)
    K.label(hoursText(p.hours), hero[1] + 16, hero[2] + 8.4, 3.3, C.white, nil, nil, 0.9)
    K.text(T("errands.team"), x + 4, y + 20, 3.4, C.faint)
    local slot = min(32, (w - 8 - 2 * GAP) / 3)
    drawSlots(x + 4, y + 25, slot, clock)
    drawGrade(x + 4, y + 28 + slot, w - 8, clock)
    local sb = K.R(x + 4, y + h - 13, w - 8, 10)
    button(sb, T("errands.send"), #st.team > 0, false, K.light(job.color, 0.08), K.dark(job.color, 0.2), clock)
    K.addHit(sb, "win", SEND)
  end
  -- (narrow: the team in a strip over the list)
  local function drawStrip(x, y, w, h, job, clock)
    K.glass(K.R(x, y, w, h), 5)
    local s = 15
    drawSlots(x + 3, y + 3, s, clock)
    local gx = x + 3 + 3 * s + 2 * GAP + 4
    drawGrade(gx, y + 3, x + w - 3 - gx, clock)
    local sb = K.R(gx, y + h - 12, x + w - 3 - gx, 9)
    button(sb, T("errands.send"), #st.team > 0, false, K.light(job.color, 0.08), K.dark(job.color, 0.2), clock)
    K.addHit(sb, "win", SEND)
  end
  local function drawPicker(x, y, w, h, clock)
    local p = post()
    if not p then return end
    local job = Er.job(p.job)
    local since = clock - mv.pickAt
    drawPickTop(x, y, w, job)
    local top = y + 10
    local ah = y + h - top
    if w >= NARROW then
      local lw = floor(w * 0.56)
      local e1 = K.stagger(since, 0, 0.06, 0.32)
      K.rise(e1, 6)
      drawList(x, top, lw, ah, clock)
      K.settle(e1)
      local e2 = K.stagger(since, 1, 0.06, 0.32)
      K.rise(e2, 6)
      drawTeam(x + lw + GAP + 1, top, w - lw - GAP - 1, ah, job, p, clock)
      K.settle(e2)
    else
      local sh = 29
      local e1 = K.stagger(since, 0, 0.06, 0.32)
      K.rise(e1, 6)
      drawStrip(x, top, w, sh, job, clock)
      K.settle(e1)
      local e2 = K.stagger(since, 1, 0.06, 0.32)
      K.rise(e2, 6)
      drawList(x, top + sh + GAP, w, ah - sh - GAP, clock)
      K.settle(e2)
    end
  end

  -- ------- Out: each team's ring filling round its job (a second hand sweeping it), the team walking
  -- its route to the flag, the time left flipping over; back: a glow, the medal popping, Collect
  local function drawTeamOut(i, e, b, tf, t, clock)
    local G = K.graphics()
    local job = Er.job(e.job)
    local x, y, w, h = b[1], b[2], b[3], b[4]
    if mv.outKey[i] ~= e.key then
      mv.outKey[i], mv.prog[i], mv.leftMin[i], mv.wasBack[i] = e.key, 0, -1, e.back and true or false
      mv.backAt[i] = e.back and clock or -10
    end
    if e.back and not mv.wasBack[i] then mv.wasBack[i], mv.backAt[i] = true, clock end
    if e.back then
      K.glow(x + w / 2, y + h / 2, w * 0.55, h * 0.9, C.green, 0.1 + 0.06 * sin(clock * 3 + i))
      K.col(C.green, 0.22 + 0.14 * sin(clock * 3 + i))
      K.box("fill", K.R(x - 1, y - 1, w + 2, h + 2), 6)
    end
    K.glass(b, 5)
    local k = e.back and 1 or min(1, max(0, 1 - (e.ends - tf) / max(1, e.ends - e.at)))
    mv.prog[i] = K.approach(mv.prog[i], k, mv.dt, 4)
    local kk = mv.prog[i]
    local rcx, rcy = x + 10, y + 10
    arcRing(rcx, rcy, 7.4, kk, 1.1, e.back and C.green or job.color)
    if not e.back then
      local an = -pi / 2 + 2 * pi * ((tf % 60) / 60)
      K.col(job.color)
      G.circle("fill", K.X(rcx + cos(an) * 7.4), K.Y(rcy + sin(an) * 7.4), 1 * K.sc)
    end
    tile(job, rcx - 5.5, rcy - 5.5, 11)
    local name = T("errands.job." .. job.id)
    K.bold(name, x + 20, y + 3.5, K.fit(name, 4.6, w * 0.42), C.ink)
    local right = x + w - 4
    -- (the route: dotted, a flag at its end, the team walking along it)
    local rx0, rx1, ry = x + 20, right - 32, y + 19
    for d = 0, 24 do
      local on = d / 24 <= kk
      K.col(on and job.color or C.faint, on and 0.95 or 0.5)
      G.circle("fill", K.X(rx0 + (rx1 - rx0) * d / 24), K.Y(ry), (on and 0.5 or 0.4) * K.sc)
    end
    K.col(C.soft, 0.8)
    K.box("fill", K.R(rx1, ry - 5, 0.4, 5))
    K.col(e.back and C.green or C.orange)
    G.polygon("fill", K.X(rx1 + 0.4), K.Y(ry - 5), K.X(rx1 + 4.4 + sin(clock * 4) * 0.4), K.Y(ry - 3.8), K.X(rx1 + 0.4),
      K.Y(ry - 2.6))
    for m = 1, #e.team do
      local px = rx0 + (rx1 - rx0) * kk - (m - 1) * 7 - 5
      local hop = e.back and 0 or abs(sin(clock * 6 + m)) * 1.2
      if env.monIconOf then
        pcall(env.monIconOf, e.team[m], px, ry - 9.5 - hop, 9, floor(clock * 4 + m) % 2, K.getFade())
      end
    end
    if e.back then
      local pe = K.outBack((clock - mv.backAt[i]) / 0.45)
      medal(right - 3, y + 6, 2.8 * pe, e.grade, clock)
      K.bold(T("errands.back"), right - 48, y + 4, 4, C.greenInk, "right", 41, min(1, pe))
      local cb = K.R(right - 26, y + h - 12, 26, 9)
      button(cb, T("errands.collect"), true, false, C.greenTop, C.greenFoot, clock)
      K.addHit(cb, "win", COLLECT + i)
    else
      -- (the time left: the new minute rolling up in place of the last)
      local mins = floor(max(0, e.ends - t) / 60)
      if mv.leftMin[i] ~= mins then
        if mv.leftMin[i] >= 0 then mv.leftOld[i], mv.leftAt[i] = leftText(mv.leftMin[i]), clock end
        mv.leftMin[i] = mins
      end
      local fe = K.outCubic((clock - mv.leftAt[i]) / 0.35)
      if fe < 1 then K.text(mv.leftOld[i], right - 60, y + 3.6 - fe * 3, 3.6, C.soft, "right", 60, 1 - fe) end
      K.text(leftText(mins), right - 60, y + 3.6 + (1 - fe) * 3, 3.6, C.soft, "right", 60, fe)
      local rb = K.R(right - 26, y + h - 12, 26, 9)
      local armed = st.recallI == i and now() - st.recallAt <= 3
      button(rb, T("errands.recall"), armed, false, C.redTop, C.redFoot, clock)
      K.addHit(rb, "win", RECALL + i)
    end
    -- (what it brings back)
    local wy = y + h - 9
    local mw = money(e.reward.money, x + 20, wy, 3.8, C.gold)
    if env.itemIcon then
      pcall(env.itemIcon, e.reward.item, x + 23 + mw, wy - 2, 7.5, K.getFade())
      K.rescissor()
    end
    K.text(timesText(e.reward.n), x + 31.5 + mw, wy, 3.4, C.soft)
  end
  local function drawOut(x, y, w, h, clock)
    local out = Er.out()
    local since = clock - mv.tabAt
    if #out == 0 then
      local e = K.stagger(since, 0, 0, 0.4)
      K.rise(e, 4)
      local cx, cy = x + w / 2, y + h / 2 - 8
      K.glow(cx, cy, 22, 16, C.orange, 0.12)
      tile(NOBODY, cx - 8, cy - 10 - sin(clock * 2) * 0.8, 16)
      K.text(T("errands.noneOut"), x + 10, cy + 10, 4.2, C.soft, "center", w - 20)
      K.settle(e)
      return
    end
    local ch = min(36, (h - (Er.MAX - 1) * GAP) / Er.MAX)
    -- (the clock: os.time ticks once a second; the frames' clock makes it smooth in between)
    local t = os.time()
    if t ~= mv.secT then mv.secT, mv.secAt = t, clock end
    local tf = t + min(0.999, clock - mv.secAt)
    for i = 1, #out do
      local ein = K.stagger(since, i - 1, 0.06, 0.32)
      K.rise(ein, 5)
      drawTeamOut(i, out[i], K.R(x, y + (i - 1) * (ch + GAP), w, ch), tf, t, clock)
      K.settle(ein)
    end
    -- (the controller's focus gliding from team to team)
    if st.keys then
      if mv.outY == nil then mv.outY = st.out end
      mv.outY = K.approach(mv.outY, min(st.out, #out), mv.dt, 20)
      K.focusRing(K.R(x, y + (mv.outY - 1) * (ch + GAP), w, ch), 5)
    else
      mv.outY = nil
    end
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

  -- (what changed since the last frame starts its motion; the backdrop's colours eased to the chosen job's)
  local function track(clock)
    local dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT, mv.dt = clock, dt
    if not mv.openAt then mv.openAt, mv.tabAt, mv.jobAt, mv.pickAt, mv.boxAt = clock, clock, clock, clock, clock end
    if mv.tab ~= st.tab then
      if mv.tab ~= nil then mv.tabAt = clock end
      mv.tab = st.tab
    end
    if mv.picking ~= st.picking then
      mv.picking, mv.pickAt, mv.boxAt, mv.boxDir, mv.curY, mv.top = st.picking, clock, clock, 0, nil, st.top
      if not st.picking then mv.tabAt, mv.jobAt = clock, clock end
    end
    if mv.box ~= st.box then
      if mv.box ~= nil then
        local d = st.box - mv.box
        if abs(d) > (Bx.BOXES or 14) / 2 then d = -d end
        mv.boxAt, mv.boxDir = clock, d > 0 and 1 or -1
      end
      mv.box = st.box
    end
    if mv.job ~= st.job then mv.job, mv.jobAt = st.job, clock end
    local job
    if st.tab == "out" and not st.picking then
      local e = Er.out()[st.out]
      job = e and Er.job(e.job)
    else
      local p = post()
      job = p and Er.job(p.job)
    end
    local c1 = job and job.color or C.orange
    local c2 = job and job.types and TYPE[job.types[1]] or C.violet
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
    track(clock)
    K.backdrop(body, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2)
    if st.party and st.party ~= st.partyDone then
      st.partyDone = st.party
      confetti(x + w / 2, y + h * 0.4)
    end
    if st.picking then
      drawPicker(x + M, y + 1, w - M * 2, h - M - 1, clock)
    else
      local tw = min(110, w - M * 2)
      drawTabs(x + (w - tw) / 2, y + 2, tw, clock)
      local top = y + 12.5
      local ah = y + h - M - top
      if st.tab == "jobs" then drawJobs(x + M, top, w - M * 2, ah, clock)
      else drawOut(x + M, top, w - M * 2, ah, clock) end
    end
    drawConfetti(clock)
    K.scissor(body)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), UI.red, UI.green, UI.hud) then st.toast = nil end
  end

  return W
end
