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
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, sin = math.floor, math.max, math.min, math.sin

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
               team = {}, grade = nil, toast = nil, keys = false, recallAt = -10, recallI = nil, typeText = {} }
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
    if not job or #st.team == 0 then st.grade = nil return end
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

  -- a travel board at dusk: teal to navy, warm orange light, the jobs' own colours
  local BG_TOP, BG_FOOT = { 18, 74, 92 }, { 8, 16, 38 }
  local WHITE, SOFT, FAINT = { 255, 255, 255 }, { 200, 224, 232 }, { 126, 156, 172 }
  local GLASS, EDGE = { 255, 255, 255, 0.07 }, { 255, 255, 255, 0.12 }
  local ORANGE, ORANGE_DEEP = { 255, 168, 72 }, { 230, 100, 40 }
  local GREEN, STAR, WARN = { 90, 230, 140 }, { 255, 210, 80 }, { 255, 120, 110 }
  local MEDAL = { great = { 255, 200, 60 }, good = { 200, 210, 226 }, ok = { 210, 140, 90 } }
  local TYPE_C = {
    [0] = { 168, 168, 120 }, [1] = { 192, 48, 40 }, [2] = { 150, 130, 236 }, [3] = { 160, 64, 160 },
    [4] = { 216, 180, 90 }, [5] = { 184, 160, 56 }, [6] = { 150, 170, 30 }, [7] = { 112, 88, 152 },
    [8] = { 170, 170, 200 }, [10] = { 240, 128, 48 }, [11] = { 96, 140, 240 }, [12] = { 110, 190, 76 },
    [13] = { 236, 196, 40 }, [14] = { 240, 88, 136 }, [15] = { 120, 200, 200 }, [16] = { 112, 56, 248 },
    [17] = { 112, 88, 72 },
  }
  local CONFETTI_N = 40
  local CONF = { ORANGE, GREEN, STAR, WHITE, { 96, 200, 255 }, { 255, 110, 170 } }
  local P = {}
  for i = 1, CONFETTI_N do P[i] = { live = false, x = 0, y = 0, vx = 0, vy = 0, t0 = 0, c = nil, spin = 0 } end
  local nextP = 1
  local function confetti(x, y)
    for i = 1, 22 do
      local p = P[nextP]
      nextP = nextP % CONFETTI_N + 1
      local a = (i / 22) * math.pi * 2 + sin(i * 2.3) * 0.4
      local v = 20 + (i * 13 % 28)
      p.live, p.x, p.y, p.vx, p.vy, p.t0 = true, x, y, math.cos(a) * v, sin(a) * v - 16, now()
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
  local function glass(b, rad, a)
    K.col(GLASS, a)
    K.box("fill", b, rad)
    K.ring(b, rad, EDGE, a or 1, 0.4)
  end
  local function tile(job, x, y, size, bob, clock)
    local yy = y + (bob and sin(clock * 2.2) * size * 0.06 or 0)
    K.grad(K.R(x, yy, size, size), size * 0.26, K.light(job.color, 0.18), K.dark(job.color, 0.25))
    K.col(WHITE, 0.18)
    K.box("fill", K.R(x + size * 0.08, yy + size * 0.06, size * 0.84, size * 0.4), size * 0.22)
    if env.glyph then pcall(env.glyph, K.graphics(), job.glyph, K.X(x + size / 2), K.Y(yy + size / 2), size * K.sc, 1, job.color) end
  end
  -- (a: the fill's; the words stay clear)
  local function chip(text, x, y, size, fill, ink, a)
    local w = K.width(text, size) + 4
    K.col(fill, a)
    K.box("fill", K.R(x, y, w, size + 2.4), (size + 2.4) / 2)
    K.text(text, x + 2, y + 1, size, ink)
    return w
  end
  local function medal(cx, cy, r, grade, clock)
    local G = K.graphics()
    local c = MEDAL[grade] or MEDAL.ok
    K.col(c)
    G.circle("fill", K.X(cx), K.Y(cy), r * K.sc)
    K.col(K.dark(c, 0.3))
    G.setLineWidth(max(1, r * 0.18 * K.sc))
    G.circle("line", K.X(cx), K.Y(cy), r * 0.72 * K.sc)
    K.col(WHITE, 0.5 + 0.3 * sin(clock * 3))
    G.circle("fill", K.X(cx - r * 0.3), K.Y(cy - r * 0.35), r * 0.22 * K.sc)
  end
  local function button(b, label, on, focused, clock, top, foot)
    if on then
      K.col(top or ORANGE, 0.2 + 0.12 * sin(clock * 3))
      K.box("fill", K.R(b[1] - 1, b[2] - 1, b[3] + 2, b[4] + 2), b[4] / 2 + 1)
      K.grad(b, b[4] / 2, top or ORANGE, foot or ORANGE_DEEP)
    else
      K.col(WHITE, 0.08)
      K.box("fill", b, b[4] / 2)
    end
    if focused then K.focusRing(b, b[4] / 2) end
    local fs = K.fit(label, 4.6, b[3] - 4)
    K.bold(label, b[1], b[2] + (b[4] - fs * 1.2) / 2, fs, on and WHITE or FAINT, "center", b[3])
  end
  -- the sky: drifting clouds
  local function sky(x, y, w, h, clock)
    local G = K.graphics()
    K.grad(K.R(x, y, w, h), 0, BG_TOP, BG_FOOT)
    K.glow(x + w * 0.85, y + h * 0.15, w * 0.4, h * 0.35, ORANGE, 0.12)
    for i = 0, 3 do
      local cx = x + ((clock * (2 + i) + i * 73) % (w + 60)) - 30
      local cy = y + 10 + i * h * 0.22
      K.col(WHITE, 0.035)
      G.ellipse("fill", K.X(cx), K.Y(cy), (18 + i * 4) * K.sc, (4 + i) * K.sc)
      G.ellipse("fill", K.X(cx + 8), K.Y(cy - 2), (10 + i * 2) * K.sc, (3.5 + i * 0.6) * K.sc)
    end
  end

  -- Jobs | Out: the light sliding to the chosen side; the count of teams back glowing on Out
  local function tabs(x, y, w, clock)
    local h = 9
    K.col(WHITE, 0.08)
    K.box("fill", K.R(x, y, w, h), h / 2)
    local want = st.tab == "jobs" and 0 or 1
    local dt = st.tabT and min(0.1, max(0, now() - st.tabT)) or 0
    st.tabT = now()
    st.tabK = (st.tabK or want) + (want - (st.tabK or want)) * min(1, dt * 12)
    local half = (w - 1) / 2
    K.grad(K.R(x + 0.5 + half * st.tabK, y + 0.5, half, h - 1), (h - 1) / 2, ORANGE, ORANGE_DEEP)
    local l1, l2 = T("errands.jobs"), T("errands.out")
    K.bold(l1, x, y + 1.9, 4.2, st.tab == "jobs" and WHITE or SOFT, "center", half)
    K.bold(l2, x + half, y + 1.9, 4.2, st.tab == "out" and WHITE or SOFT, "center", half)
    local back = Er.waiting()
    if back > 0 then
      local bx = x + half * 2 - 6
      K.col(GREEN, 0.7 + 0.3 * sin(clock * 5))
      K.graphics().circle("fill", K.X(bx), K.Y(y + h / 2), 2.8 * K.sc)
      K.bold(tostring(back), bx - 3, y + h / 2 - 2, 3.4, BG_FOOT, "center", 6)
    end
    K.addHit(K.R(x, y, half, h), "win", TAB_JOBS)
    K.addHit(K.R(x + half, y, half, h), "win", TAB_OUT)
  end

  local function drawJobs(x, y, w, h, clock)
    local board = Er.board(session())
    local lw = floor(w * 0.42)
    local ch = (h - 4) / 3
    for i, p in ipairs(board) do
      local job = Er.job(p.job)
      local b = K.R(x, y + (i - 1) * (ch + 2), lw, ch)
      local on = i == st.job
      if on then
        K.glow(b[1] + lw / 2, b[2] + ch / 2, lw * 0.6, ch * 0.8, job.color, 0.25)
        K.grad(b, 5, K.light(job.color, 0.05), K.dark(job.color, 0.35))
      else
        glass(b, 5, p.taken and 0.6 or 1)
      end
      tile(job, b[1] + 3, b[2] + (ch - 13) / 2, 13, on, clock)
      local name = T("errands.job." .. job.id)
      K.bold(name, b[1] + 19, b[2] + ch / 2 - 5.2, K.fit(name, 4.6, lw - 23), WHITE, nil, nil, p.taken and 0.6 or 1)
      chip(hoursText(p.hours), b[1] + 19, b[2] + ch / 2 + 0.6, 3.2, WHITE, on and WHITE or SOFT, 0.14)
      if p.taken then K.text(T("errands.taken"), b[1], b[2] + ch / 2 + 1, 3.4, FAINT, "right", lw - 4) end
      K.addHit(b, "win", JOB + i)
    end
    -- (the chosen job: a hero card in its colour)
    local p = board[st.job]
    local job = Er.job(p.job)
    local dx, dw = x + lw + 3, w - lw - 3
    local db = K.R(dx, y, dw, h)
    glass(db, 6)
    local hero = K.R(dx, y, dw, 24)
    K.grad(hero, 6, K.light(job.color, 0.1), K.dark(job.color, 0.4))
    K.col(job.color)
    K.box("fill", K.R(dx, y + 18, dw, 6))
    K.grad(K.R(dx, y + 18, dw, 6), 0, K.dark(job.color, 0.4), K.fade(K.dark(job.color, 0.4), 0))
    tile(job, dx + 4, y + 4, 16, true, clock)
    local name = T("errands.job." .. job.id)
    K.bold(name, dx + 23, y + 5, K.fit(name, 5.6, dw - 27), WHITE)
    K.text(hoursText(p.hours), dx + 23, y + 12.5, 3.8, SOFT)
    local desc = T("errands.desc." .. job.id)
    K.text(desc, dx + 4, y + 27, 3.5, SOFT, "left", dw - 8)
    -- (the types it favours, each in its colour; the level; the pay)
    local ty = y + h - 40
    K.text(T("errands.favours"), dx + 4, ty, 3.2, FAINT)
    local cx = dx + 4
    for _, id in ipairs(job.types) do
      local c = TYPE_C[id] or ORANGE
      local wd = chip(typeName(id), cx, ty + 4.2, 3.4, c, WHITE, 0.85)
      cx = cx + wd + 1.5
    end
    chip(bestText(job.level), dx + 4, ty + 11.5, 3.3, WHITE, SOFT, 0.1)
    local f = p.hours >= 8 and 5 or (p.hours >= 4 and 3 or 1)
    K.text(T("errands.pays"), dx + 4, ty + 18.2, 3.2, FAINT)
    local lw2 = money(job.money[1] * f, dx + 4, ty + 22, 4, STAR)
    K.text("-", dx + 5.5 + lw2, ty + 22, 4, SOFT)
    money(job.money[2] * f, dx + 9 + lw2, ty + 22, 4, STAR)
    local gb = K.R(dx + 4, y + h - 13, dw - 8, 10)
    local can = not p.taken and #Er.out() < Er.MAX
    button(gb, T(p.taken and "errands.taken" or "errands.chooseTeam"), can, st.keys and can, clock)
    K.addHit(gb, "win", GO)
  end

  local function drawPicker(x, y, w, h, clock)
    local G = K.graphics()
    local p = post()
    local job = Er.job(p.job)
    local lw = floor(w * 0.56)
    glass(K.R(x, y, lw, h), 5)
    K.chevron(x + 5, y + 5.3, 4, ORANGE, -1)
    K.addHit(K.R(x, y, 12, 10), "win", BOX_PREV)
    K.chevron(x + lw - 5, y + 5.3, 4, ORANGE, 1)
    K.addHit(K.R(x + lw - 12, y, 12, 10), "win", BOX_NEXT)
    local bname = Bx.boxName(session(), st.box) or ""
    K.bold(bname, x + 12, y + 2.7, K.fit(bname, 4.6, lw - 26), WHITE, "center", lw - 24)
    K.col(WHITE, 0.08)
    K.box("fill", K.R(x, y + 10, lw, 0.3))
    local top = y + 10.5
    local lh = y + h - 1 - top
    st.visible = max(1, floor(lh / ROW_H))
    if st.cursor > st.top + st.visible then st.top = st.cursor - st.visible end
    if st.cursor <= st.top then st.top = st.cursor - 1 end
    st.top = max(0, min(st.top, max(0, #st.rows - st.visible)))
    local clip = K.R(x, top, lw, lh)
    K.scissor(clip)
    local first = floor(st.top) + 1
    for i = first, min(#st.rows, first + st.visible + 1) do
      local r = st.rows[i]
      local ry = top + (i - 1 - st.top) * ROW_H
      local rb = K.R(x + 1.5, ry + 0.4, lw - 3, ROW_H - 0.8)
      local picked = chosen(r.addr) ~= nil
      if picked then
        K.col(job.color, 0.3)
        K.box("fill", rb, 3)
      end
      if i == st.cursor then K.ring(rb, 3, ORANGE, 0.9, 0.5) end
      if env.monIconOf then pcall(env.monIconOf, r.mon, x + 3, ry + 0.5, 11, floor(clock * 3) % 2, r.ok and 1 or 0.4) end
      K.text(r.name, x + 15, ry + (r.why and 1.2 or 3.4), K.fit(r.name, 4.4, lw - 44), r.ok and WHITE or FAINT)
      if r.why then K.text(r.why, x + 15, ry + 6.6, 3.1, WARN, "left", lw - 44) end
      K.text(levelText(r.level), x + lw - 4 - 18, ry + 3.4, 3.6, SOFT, "right", 18)
      if r.fit then
        local sx, sy = K.X(x + lw - 26), K.Y(ry + ROW_H / 2)
        local u = (1.5 + 0.3 * sin(clock * 5 + i)) * K.sc
        K.col(STAR)
        G.polygon("fill", sx, sy - u, sx + u * 0.3, sy, sx, sy + u, sx - u * 0.3, sy)
        G.polygon("fill", sx - u, sy, sx, sy - u * 0.3, sx + u, sy, sx, sy + u * 0.3)
      end
      K.addHit(rb, "win", ROW + i, clip)
    end
    if #st.rows == 0 then K.text(T("gts.emptyBox"), x, top + lh / 2 - 3, 4.2, FAINT, "center", lw) end
    K.scrollbar(x + lw, top, lh, st.top, st.visible, #st.rows)
    K.scissor(st.clip)
    -- (the team: three slots lighting up as they fill, the medal they'd earn, Send)
    local tx, tw = x + lw + 3, w - lw - 3
    local tb = K.R(tx, y, tw, h)
    glass(tb, 6)
    K.grad(K.R(tx, y, tw, 17), 6, K.light(job.color, 0.1), K.dark(job.color, 0.4))
    tile(job, tx + 3, y + 3, 11, true, clock)
    local name = T("errands.job." .. job.id)
    K.bold(name, tx + 17, y + 3.6, K.fit(name, 4.6, tw - 21), WHITE)
    K.text(hoursText(p.hours), tx + 17, y + 9.6, 3.3, SOFT)
    K.text(T("errands.team"), tx + 4, y + 20, 3.4, FAINT)
    local slot = (tw - 8 - 4) / 3
    local s = session()
    for i = 1, 3 do
      local sb = K.R(tx + 4 + (i - 1) * (slot + 2), y + 25, slot, slot)
      local a = st.team[i]
      local mon = a and Bx.get(s, a)
      if mon then
        K.glow(sb[1] + slot / 2, sb[2] + slot / 2, slot * 0.7, slot * 0.7, job.color, 0.3)
        K.col(job.color, 0.35)
        K.box("fill", sb, 4)
        K.ring(sb, 4, job.color, 0.9, 0.5)
        local bob = sin(clock * 4 + i) * 0.8
        if env.monIconOf then pcall(env.monIconOf, mon, sb[1] + (slot - 13) / 2, sb[2] + (slot - 13) / 2 + bob, 13, floor(clock * 3) % 2, 1) end
      else
        K.col(WHITE, 0.05)
        K.box("fill", sb, 4)
        K.ring(sb, 4, EDGE, 1, 0.4)
        K.text("+", sb[1], sb[2] + slot / 2 - 3, 5, FAINT, "center", slot)
      end
    end
    if st.grade then
      local my = y + 28 + slot
      medal(tx + 8, my + 3.4, 3.2, st.grade, clock)
      K.bold(T(GRADE_KEY[st.grade]), tx + 13, my + 1.4, 4.2, MEDAL[st.grade])
    end
    local sb = K.R(tx + 4, y + h - 13, tw - 8, 10)
    button(sb, T("errands.send"), #st.team > 0, false, clock)
    K.addHit(sb, "win", SEND)
  end

  -- a team out: their route, the team walking along it to the flag; back: a glow, the medal, Collect
  local function drawOut(x, y, w, h, clock)
    local G = K.graphics()
    local out = Er.out()
    if #out == 0 then
      local cx, cy = x + w / 2, y + h / 2 - 6
      K.glow(cx, cy, 18, 14, ORANGE, 0.12)
      K.text(T("errands.noneOut"), x, cy + 6, 4.2, SOFT, "center", w)
      return
    end
    local ch = min(36, (h - (Er.MAX - 1) * 2) / Er.MAX)
    local t = os.time()
    for i, e in ipairs(out) do
      local job = Er.job(e.job)
      local b = K.R(x, y + (i - 1) * (ch + 2), w, ch)
      if e.back then
        K.col(GREEN, 0.22 + 0.12 * sin(clock * 3 + i))
        K.box("fill", K.R(b[1] - 1, b[2] - 1, b[3] + 2, b[4] + 2), 6)
      end
      glass(b, 5)
      if st.keys and i == st.out then K.focusRing(b, 5) end
      tile(job, b[1] + 3, b[2] + 3, 12, false, clock)
      local name = T("errands.job." .. job.id)
      K.bold(name, b[1] + 18, b[2] + 3.5, K.fit(name, 4.6, w * 0.4), WHITE)
      local right = b[1] + b[3] - 4
      -- (the route: dotted, a flag at its end)
      local rx0, rx1, ry = b[1] + 18, right - 32, b[2] + 19
      local k = e.back and 1 or min(1, 1 - max(0, e.ends - t) / max(1, e.ends - e.at))
      for d = 0, 24 do
        local dx = rx0 + (rx1 - rx0) * d / 24
        K.col(d / 24 <= k and job.color or WHITE, d / 24 <= k and 0.9 or 0.18)
        G.circle("fill", K.X(dx), K.Y(ry), 0.45 * K.sc)
      end
      K.col(WHITE, 0.8)
      K.box("fill", K.R(rx1, ry - 5, 0.4, 5))
      K.col(e.back and GREEN or ORANGE)
      G.polygon("fill", K.X(rx1 + 0.4), K.Y(ry - 5), K.X(rx1 + 4.4 + sin(clock * 4) * 0.4), K.Y(ry - 3.8), K.X(rx1 + 0.4), K.Y(ry - 2.6))
      for m, mon in ipairs(e.team) do
        local px = rx0 + (rx1 - rx0) * k - (m - 1) * 7 - 5
        local hop = e.back and 0 or math.abs(sin(clock * 6 + m)) * 1.2
        if env.monIconOf then pcall(env.monIconOf, mon, px, ry - 9.5 - hop, 9, floor(clock * 4 + m) % 2, 1) end
      end
      if e.back then
        medal(right - 3, b[2] + 6, 2.8, e.grade, clock)
        K.bold(T("errands.back"), right - 48, b[2] + 4, 4, GREEN, "right", 41)
        local cb = K.R(right - 26, b[2] + ch - 12, 26, 9)
        button(cb, T("errands.collect"), true, false, clock, { 110, 240, 160 }, { 30, 170, 96 })
        K.addHit(cb, "win", COLLECT + i)
      else
        K.text(leftText(floor(max(0, e.ends - t) / 60)), right - 60, b[2] + 3.6, 3.6, SOFT, "right", 60)
        local rb = K.R(right - 26, b[2] + ch - 12, 26, 9)
        local armed = st.recallI == i and now() - st.recallAt <= 3
        button(rb, T("errands.recall"), armed, false, clock, { 255, 110, 100 }, { 200, 50, 50 })
        K.addHit(rb, "win", RECALL + i)
      end
      -- (what it brings back)
      local wy = b[2] + ch - 9
      local mw = money(e.reward.money, b[1] + 18, wy, 3.8, STAR)
      if env.itemIcon then pcall(env.itemIcon, e.reward.item, b[1] + 21 + mw, wy - 2, 7.5) end
      K.text(timesText(e.reward.n), b[1] + 29.5 + mw, wy, 3.4, SOFT)
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
    sky(x, y, w, h, clock)
    if st.party and st.party ~= st.partyDone then
      st.partyDone = st.party
      confetti(x + w / 2, y + h * 0.4)
    end
    if not st.picking then tabs(x + M, y + 2, min(120, w - M * 2), clock) end
    local top = st.picking and y + M or y + 13
    local ah = y + h - M - top
    if st.picking then drawPicker(x + M, top, w - M * 2, ah, clock)
    elseif st.tab == "jobs" then drawJobs(x + M, top, w - M * 2, ah, clock)
    else drawOut(x + M, top, w - M * 2, ah, clock) end
    drawConfetti(clock)
    K.scissor(body)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), UI.red, UI.green, UI.hud) then st.toast = nil end
  end

  return W
end
