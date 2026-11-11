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

  local GOLD, GREEN, STAR = { 255, 189, 46 }, { 52, 199, 89 }, { 255, 204, 0 }
  local GRADE_C = { great = { 255, 159, 10 }, good = { 52, 199, 89 }, ok = { 120, 120, 128 } }

  local function money(n, x, y, size, c, right)
    if not env.amount then return 0 end
    local ok, w = pcall(env.amount, n, 0, 0, size, c, true)
    w = ok and tonumber(w) or 0
    pcall(env.amount, n, right and x - w or x, y, size, c)
    return w
  end
  local function tile(job, x, y, size)
    K.col(job.color)
    K.box("fill", K.R(x, y, size, size), size * 0.26)
    if env.glyph then pcall(env.glyph, K.graphics(), job.glyph, K.X(x + size / 2), K.Y(y + size / 2), size * K.sc, 1, job.color) end
  end
  local function pill(text, x, y, size, fill, ink)
    local w = K.width(text, size) + 4
    K.col(fill)
    K.box("fill", K.R(x, y, w, size + 2.4), (size + 2.4) / 2)
    K.text(text, x + 2, y + 1, size, ink)
    return w
  end

  local function drawJobs(x, y, w, h, clock)
    local board = Er.board(session())
    local lw = floor(w * 0.44)
    local ch = (h - 4) / 3
    for i, p in ipairs(board) do
      local job = Er.job(p.job)
      local b = K.R(x, y + (i - 1) * (ch + 2), lw, ch)
      K.card(b, 4)
      if i == st.job then K.selection(K.R(b[1] + 0.8, b[2] + 0.8, b[3] - 1.6, b[4] - 1.6), true, 3.4) end
      tile(job, b[1] + 3, b[2] + (ch - 12) / 2, 12)
      local name = T("errands.job." .. job.id)
      K.bold(name, b[1] + 18, b[2] + ch / 2 - 5, K.fit(name, 4.6, lw - 22), i == st.job and UI.card or UI.label)
      K.text(hoursText(p.hours), b[1] + 18, b[2] + ch / 2 + 0.8, 3.6, i == st.job and UI.card or UI.secondary)
      if p.taken then
        K.text(T("errands.taken"), b[1], b[2] + ch / 2 + 0.8, 3.6, i == st.job and UI.card or UI.tertiary, "right", lw - 4)
      end
      K.addHit(b, "win", JOB + i)
    end
    -- (the chosen job)
    local p = board[st.job]
    local job = Er.job(p.job)
    local dx, dw = x + lw + 3, w - lw - 3
    local db = K.R(dx, y, dw, h)
    K.card(db, 5)
    tile(job, dx + 4, y + 4, 16)
    local name = T("errands.job." .. job.id)
    K.bold(name, dx + 23, y + 5, K.fit(name, 5.6, dw - 27), UI.label)
    K.text(hoursText(p.hours), dx + 23, y + 12.5, 3.8, UI.secondary)
    local desc = T("errands.desc." .. job.id)
    K.text(desc, dx + 4, y + 23, 3.6, UI.secondary, "left", dw - 8)
    local ty = y + h - 40
    K.text(T("errands.favours"), dx + 4, ty, 3.4, UI.tertiary)
    K.text(typeText(job), dx + 4, ty + 4.6, K.fit(typeText(job), 4, dw - 8), UI.label)
    K.text(bestText(job.level), dx + 4, ty + 10.5, 3.6, UI.secondary)
    -- (what it pays: the money for its length, an item)
    local f = p.hours >= 8 and 5 or (p.hours >= 4 and 3 or 1)
    K.text(T("errands.pays"), dx + 4, ty + 16.5, 3.4, UI.tertiary)
    local lw2 = money(job.money[1] * f, dx + 4, ty + 21, 4, UI.label)
    K.text("-", dx + 5.5 + lw2, ty + 21, 4, UI.secondary)
    money(job.money[2] * f, dx + 9 + lw2, ty + 21, 4, UI.label)
    local gb = K.R(dx + 4, y + h - 13, dw - 8, 10)
    local can = not p.taken and #Er.out() < Er.MAX
    K.button(gb, T(p.taken and "errands.taken" or "errands.chooseTeam"), can and "accent" or nil, st.keys and can, 4.6)
    K.addHit(gb, "win", GO)
  end

  local function drawPicker(x, y, w, h, clock)
    local lw = floor(w * 0.56)
    local pb = K.R(x, y, lw, h)
    K.card(pb, 4)
    K.chevron(x + 5, y + 5.3, 4, UI.accent, -1)
    K.addHit(K.R(x, y, 12, 10), "win", BOX_PREV)
    K.chevron(x + lw - 5, y + 5.3, 4, UI.accent, 1)
    K.addHit(K.R(x + lw - 12, y, 12, 10), "win", BOX_NEXT)
    local bname = Bx.boxName(session(), st.box) or ""
    K.bold(bname, x + 12, y + 2.7, K.fit(bname, 4.6, lw - 26), UI.label, "center", lw - 24)
    K.hairline(x, y + 10, lw)
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
        K.col(UI.accent, 0.14)
        K.box("fill", rb, 2.5)
      end
      if i == st.cursor then K.ring(rb, 2.5, UI.accent, 0.8, 0.5) end
      if env.monIconOf then pcall(env.monIconOf, r.mon, x + 3, ry + 0.5, 11, floor(clock * 3) % 2, r.ok and 1 or 0.4) end
      K.text(r.name, x + 15, ry + (r.why and 1.2 or 3.4), K.fit(r.name, 4.4, lw - 44), r.ok and UI.label or UI.tertiary)
      if r.why then K.text(r.why, x + 15, ry + 6.6, 3.2, UI.red, "left", lw - 44) end
      K.text(levelText(r.level), x + lw - 4 - 18, ry + 3.4, 3.8, UI.secondary, "right", 18)
      if r.fit then
        K.col(STAR)
        local cx, cy = K.X(x + lw - 26), K.Y(ry + ROW_H / 2)
        local u = 1.6 * K.sc
        K.graphics().polygon("fill", cx, cy - u, cx + u * 0.3, cy, cx, cy + u, cx - u * 0.3, cy)
        K.graphics().polygon("fill", cx - u, cy, cx, cy - u * 0.3, cx + u, cy, cx, cy + u * 0.3)
      end
      if picked then
        K.col(UI.accent)
        K.graphics().circle("fill", K.X(x + lw - 31.5), K.Y(ry + ROW_H / 2), 1.4 * K.sc)
      end
      K.addHit(rb, "win", ROW + i, clip)
    end
    if #st.rows == 0 then K.text(T("gts.emptyBox"), x, top + lh / 2 - 3, 4.2, UI.tertiary, "center", lw) end
    K.scrollbar(x + lw, top, lh, st.top, st.visible, #st.rows)
    K.scissor(st.clip)
    -- (the team: up to three, the grade they'd earn, Send)
    local tx, tw = x + lw + 3, w - lw - 3
    local tb = K.R(tx, y, tw, h)
    K.card(tb, 5)
    local p = post()
    local job = Er.job(p.job)
    tile(job, tx + 4, y + 4, 11)
    local name = T("errands.job." .. job.id)
    K.bold(name, tx + 18, y + 4.5, K.fit(name, 4.6, tw - 22), UI.label)
    K.text(hoursText(p.hours), tx + 18, y + 10.5, 3.4, UI.secondary)
    K.text(T("errands.team"), tx + 4, y + 19, 3.6, UI.tertiary)
    local slot = (tw - 8 - 4) / 3
    local s = session()
    for i = 1, 3 do
      local sb = K.R(tx + 4 + (i - 1) * (slot + 2), y + 24, slot, slot)
      K.col(UI.fill)
      K.box("fill", sb, 3)
      local a = st.team[i]
      local mon = a and Bx.get(s, a)
      if mon and env.monIconOf then pcall(env.monIconOf, mon, sb[1] + (slot - 12) / 2, sb[2] + (slot - 12) / 2, 12, floor(clock * 3) % 2, 1) end
    end
    if st.grade then
      local g = T(GRADE_KEY[st.grade])
      pill(g, tx + 4, y + 26 + slot, 3.8, GRADE_C[st.grade], UI.card)
    end
    local sb = K.R(tx + 4, y + h - 13, tw - 8, 10)
    K.button(sb, T("errands.send"), #st.team > 0 and "accent" or nil, false, 4.6)
    K.addHit(sb, "win", SEND)
  end

  local function drawOut(x, y, w, h, clock)
    local out = Er.out()
    if #out == 0 then
      K.text(T("errands.noneOut"), x, y + h / 2 - 3, 4.4, UI.tertiary, "center", w)
      return
    end
    local ch = min(34, (h - (Er.MAX - 1) * 2) / Er.MAX)
    local t = os.time()
    local s = session()
    for i, e in ipairs(out) do
      local job = Er.job(e.job)
      local b = K.R(x, y + (i - 1) * (ch + 2), w, ch)
      K.card(b, 4)
      if st.keys and i == st.out then K.focusRing(b, 4) end
      tile(job, b[1] + 3, b[2] + 3, 12)
      local name = T("errands.job." .. job.id)
      K.bold(name, b[1] + 18, b[2] + 3.5, K.fit(name, 4.6, w * 0.45), UI.label)
      for k, mon in ipairs(e.team) do
        if env.monIconOf then pcall(env.monIconOf, mon, b[1] + 18 + (k - 1) * 11, b[2] + 9, 10, floor(clock * 3) % 2, 1) end
      end
      local right = b[1] + b[3] - 4
      if e.back then
        local g = T(GRADE_KEY[e.grade] or "errands.grade.ok")
        local gw = K.width(g, 3.6) + 4
        pill(g, right - gw, b[2] + 3, 3.6, GRADE_C[e.grade] or GRADE_C.ok, UI.card)
        K.text(T("errands.back"), right - gw - 40, b[2] + 3.6, 3.8, GREEN, "right", 38)
        local cb = K.R(right - 26, b[2] + ch - 12, 26, 9)
        local pulse = 0.5 + 0.5 * sin(clock * 4)
        K.col(UI.accent, 0.16 * pulse)
        K.box("fill", K.R(cb[1] - 1, cb[2] - 1, cb[3] + 2, cb[4] + 2), 5)
        K.button(cb, T("errands.collect"), "accent", false, 4.2)
        K.addHit(cb, "win", COLLECT + i)
      else
        local left = max(0, e.ends - t)
        K.text(leftText(floor(left / 60)), right - 60, b[2] + 3.6, 3.8, UI.secondary, "right", 60)
        local k = 1 - left / max(1, e.ends - e.at)
        local bar = K.R(b[1] + 18 + 36, b[2] + 13, w - 18 - 36 - 34, 1.8)
        K.col(UI.fill)
        K.box("fill", bar, 0.9)
        K.col(job.color)
        K.box("fill", K.R(bar[1], bar[2], bar[3] * min(1, k), bar[4]), 0.9)
        local rb = K.R(right - 26, b[2] + ch - 12, 26, 9)
        local armed = st.recallI == i and now() - st.recallAt <= 3
        K.button(rb, T("errands.recall"), armed and "danger" or nil, false, 3.8)
        K.addHit(rb, "win", RECALL + i)
      end
      -- (what it brings back)
      local ry = b[2] + ch - 9
      local mw = money(e.reward.money, b[1] + 18, ry, 3.8, UI.label)
      if env.itemIcon then pcall(env.itemIcon, e.reward.item, b[1] + 21 + mw, ry - 2, 7.5) end
      K.text(timesText(e.reward.n), b[1] + 29.5 + mw, ry, 3.6, UI.secondary)
    end
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    st.clip = body
    if not st.picking then
      K.segmented(x + M, y + 2, min(120, w - M * 2), 9, st.tab == "jobs" and 1 or 2, "win", TAB_JOBS, T("errands.jobs"),
        TAB_OUT, T("errands.out"))
    end
    local top = st.picking and y + M or y + 13
    local ah = y + h - M - top
    if st.picking then drawPicker(x + M, top, w - M * 2, ah, clock)
    elseif st.tab == "jobs" then drawJobs(x + M, top, w - M * 2, ah, clock)
    else drawOut(x + M, top, w - M * 2, ah, clock) end
    K.scissor(body)
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), UI.red, UI.green, UI.hud) then st.toast = nil end
  end

  return W
end
