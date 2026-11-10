-- The Decorate app (Ruby / Sapphire / Emerald, the bedroom PC): a furniture catalogue of the
-- decorations the player owns (src/decorate.lua), by the game's categories. A showroom for the chosen
-- piece, where it is, and what can be done with it: into the room (the game's own cursor), back to
-- the PC, or thrown away. The game's rules: only dolls and cushions go in the bedroom, and a
-- decoration in use can't be thrown away.
--   buttons  the D-pad the grid, L / R the category, A its actions, B close
--   touch    a category, a piece, its buttons
--
--   window(ctx, env) -> win (src/apps.lua)   env.decorate

local floor, ceil, max, min, sin = math.floor, math.ceil, math.max, math.min, math.sin

local M, GAP, CELL_MIN = 3, 2, 24
local RAIL, CELL, ACT, YES, NO, DIM = 1000, 2000, 3000, 4001, 4002, 4003
local C = {
  stageTop = { 250, 241, 226 }, stageFoot = { 232, 215, 192 },
  railTop = { 96, 66, 46 }, railFoot = { 62, 42, 30 }, railOn = { 240, 168, 84 }, railOnFoot = { 214, 124, 58 },
  card = { 255, 252, 246 }, cardFoot = { 246, 236, 220 }, line = { 120, 84, 50 },
  wallTop = { 206, 196, 232 }, wallFoot = { 232, 222, 244 }, floorTop = { 186, 134, 88 }, floorFoot = { 138, 94, 60 },
  skirt = { 255, 250, 240 },
  ink = { 62, 42, 30 }, soft = { 134, 106, 84 }, faint = { 176, 152, 128 }, cream = { 255, 244, 228 },
  creamSoft = { 214, 188, 164 }, accent = { 214, 110, 58 }, accentFoot = { 180, 80, 40 }, danger = { 214, 66, 66 },
  off = { 120, 84, 50, 0.14 }, white = { 255, 255, 255 }, dim = { 40, 26, 18 },
  room = { 46, 170, 160 }, base = { 232, 92, 92 }, pc = { 150, 124, 100 },
}
local WHERE = { room = "decor.inRoom", base = "decor.inBase", pc = "decor.inPc" }
local HINTS = { { "+", "hint.choose" }, { "L R", "decor.hint.category" }, { "A", "decor.hint.actions" }, { "B", "hint.close" } }
local HINTS_BARE = { { "+", "hint.choose" }, { "L R", "decor.hint.category" }, { "B", "hint.close" } }
local HINTS_ACT = { { "+", "hint.choose" }, { "A", "hint.ok" }, { "B", "hint.back" } }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, Dc, T = env.K, env.decorate, env.T or NO_T
  local W = { title = T("app.decorate") }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local st = { cat = 1, pick = 1, top = 0, focus = "grid", act = 1, acts = {}, follow = true,
               cols = 4, cell = CELL_MIN, viewH = 0, list = nil, note = nil, roomText = "" }
  W.state = st
  local resume = ctx.resume
  if resume and resume.app == ctx.app and type(resume.state) == "table" then
    st.cat, st.pick = resume.state.cat or 1, resume.state.pick or 1
  end
  ctx.resume = nil

  local function row() return st.list.cats[st.cat] end
  local function chosen() return row().items[st.pick] end

  -- what the chosen piece can do (made on change, read by the draw)
  local function actions()
    local item, r = chosen(), row()
    local acts, full = {}, st.list.used >= st.list.size
    st.note = nil
    if item then
      if item.where == "room" then
        acts[1] = { id = "putAway", key = "decor.putAway" }
      elseif item.where == "pc" then
        if r.room and not full then acts[#acts + 1] = { id = "place", key = "decor.place" } end
        acts[#acts + 1] = { id = "toss", key = "decor.toss", danger = true }
        if not r.room then st.note = "decor.baseOnly" elseif full then st.note = "decor.roomFull" end
      end
    end
    st.acts = acts
    st.act = 1
    if #acts == 0 and st.focus == "acts" then st.focus = "grid" end
  end

  local function refresh()
    st.list = Dc.list(session())
    st.cat = max(1, min(#st.list.cats, st.cat))
    st.pick = max(1, min(max(1, row().count), st.pick))
    st.roomText = T.f("decor.room", st.list.used, st.list.size)
    st.follow = true
    actions()
  end

  local function toast(text, bad) st.toast = { text = text, bad = bad, t = now() } end

  local function pick(i)
    if i == st.pick or not row().items[i] then return end
    st.pick, st.follow = i, true
    se("SE_SELECT")
    actions()
  end
  local function category(i)
    if i == st.cat then return end
    st.cat, st.pick, st.top, st.follow, st.focus = i, 1, 0, true, "grid"
    se("SE_SELECT")
    actions()
  end

  local function perform(act)
    local item = chosen()
    if not (act and item) then return end
    local s = session()
    if act.id == "place" then
      se("SE_SELECT")
      ctx.over(function(onClose) Dc.place(s, item, onClose) end, { cat = st.cat, pick = st.pick })
    elseif act.id == "toss" then
      se("SE_SELECT")
      st.confirm = { item = item, cursor = 2, title = T.f("decor.tossTitle", item.name) }
    elseif act.id == "putAway" then
      if Dc.putAway(s, item) then
        se("SE_SELECT")
        st.focus = "grid"
        refresh()
        toast(T.f("decor.returned", item.name))
      else
        se("SE_FAILURE")
        toast(T("decor.failed"), true)
      end
    end
  end

  local function answer(yes)
    local c = st.confirm
    st.confirm = nil
    if not (c and yes) then se("SE_SELECT"); return end
    if Dc.toss(session(), c.item) then
      se("SE_SELECT")
      st.focus = "grid"
      refresh()
      toast(T.f("decor.tossed", c.item.name))
    else
      se("SE_FAILURE")
      toast(T("decor.failed"), true)
    end
  end

  function W.input(input, nav)
    local function pressed(k) return input:wasPressed(k) end
    if st.confirm then
      local c = st.confirm
      if pressed("b") then answer(false)
      elseif pressed("a") then answer(c.cursor == 1)
      elseif (nav.left and c.cursor == 2) or (nav.right and c.cursor == 1) then
        c.cursor = 3 - c.cursor
        se("SE_SELECT")
      end
      return true
    end
    if st.focus == "acts" then
      if pressed("b") then st.focus = "grid"; se("SE_SELECT")
      elseif pressed("a") then perform(st.acts[st.act])
      elseif nav.left and st.act > 1 then st.act = st.act - 1; se("SE_SELECT")
      elseif nav.right and st.act < #st.acts then st.act = st.act + 1; se("SE_SELECT")
      end
      return true
    end
    if pressed("b") then return false end
    local n = #st.list.cats
    if pressed("l") then category((st.cat - 2) % n + 1)
    elseif pressed("r") then category(st.cat % n + 1)
    elseif pressed("a") then
      if #st.acts > 0 then st.focus, st.act = "acts", 1; se("SE_SELECT") end
    elseif nav.left and (st.pick - 1) % st.cols > 0 then pick(st.pick - 1)
    elseif nav.right and st.pick % st.cols > 0 then pick(st.pick + 1)
    elseif nav.up and st.pick > st.cols then pick(st.pick - st.cols)
    elseif nav.down then
      if st.pick + st.cols <= row().count then pick(st.pick + st.cols)
      elseif ceil(st.pick / st.cols) < ceil(row().count / st.cols) then pick(row().count) end
    end
    return true
  end

  function W.tap(arg)
    if type(arg) ~= "number" then return end
    if st.confirm then
      if arg == YES then answer(true) elseif arg == NO or arg == DIM then answer(false) end
      return
    end
    if arg > ACT then
      st.focus, st.act = "grid", arg - ACT
      perform(st.acts[arg - ACT])
    elseif arg > CELL then
      st.focus = "grid"
      pick(arg - CELL)
    elseif arg > RAIL then
      category(arg - RAIL)
    end
  end

  function W.scroll(dy)
    st.top = st.top - dy
    st.follow = false
  end

  function W.hints()
    if st.confirm or st.focus == "acts" then return T.list(HINTS_ACT) end
    return T.list(#st.acts > 0 and HINTS or HINTS_BARE)
  end

  -- ------- drawing (no tables made here)

  local function picture(decor, cx, cy, size)
    local img = Dc.picture(decor)
    if not img then return end
    local g, sc = K.graphics(), K.sc
    local pw, ph = img:getDimensions()
    local k = size * sc / max(pw, ph)
    if k >= 1 then k = floor(k) end
    g.setColor(1, 1, 1, 1)
    g.draw(img, floor(K.X(cx) - pw * k / 2 + 0.5), floor(K.Y(cy) - ph * k / 2 + 0.5), 0, k, k)
  end

  local function railRow(i, b, on)
    local r = st.list.cats[i]
    if on then
      K.grad(b, 2.5, C.railOn, C.railOnFoot)
    end
    local ty = b[2] + (b[4] - 4.4) / 2 - 0.3
    if r.room then
      K.col(on and C.white or C.railOn)
      local g = K.graphics()
      g.circle("fill", K.X(b[1] + 3.2), K.Y(b[2] + b[4] / 2), 0.9 * K.sc)
    end
    local nameW = b[3] - 22
    K.text(r.name, b[1] + 5.6, ty, K.fit(r.name, 4.4, nameW), on and C.white or C.cream)
    K.text(r.countText, b[1] + b[3] - 18, ty + 0.3, 3.8, on and C.white or C.creamSoft, "right", 16.5)
    K.addHit(b, "win", RAIL + i)
  end

  local function drawRail(x, y, w, h)
    local b = K.R(x, y, w, h)
    K.grad(b, 4, C.railTop, C.railFoot)
    local n = #st.list.cats
    local rh = min(14, (h - 4) / n)
    for i = 1, n do
      railRow(i, K.R(x + 2, y + 2 + (i - 1) * rh, w - 4, rh), i == st.cat)
    end
  end

  -- (portrait: the categories as two rows of chips)
  local function drawChips(x, y, w, h)
    local n = #st.list.cats
    local cols = ceil(n / 2)
    local cw, ch = (w - GAP * (cols - 1)) / cols, (h - GAP) / 2
    for i = 1, n do
      local r = st.list.cats[i]
      local b = K.R(x + (i - 1) % cols * (cw + GAP), y + floor((i - 1) / cols) * (ch + GAP), cw, ch)
      local on = i == st.cat
      if on then K.grad(b, 3, C.railOn, C.railOnFoot) else K.grad(b, 3, C.railTop, C.railFoot) end
      local fs = K.fit(r.name, 4.2, cw - 3)
      K.text(r.name, b[1], b[2] + 1.2, fs, on and C.white or C.cream, "center", cw)
      K.text(r.countText, b[1], b[2] + ch - 4.8, 3.4, on and C.white or C.creamSoft, "center", cw)
      K.addHit(b, "win", RAIL + i)
    end
  end

  local function drawCell(i, item, cx, cy, cs, on, clock)
    local b = K.R(cx, cy, cs, cs)
    K.grad(b, 3, C.card, C.cardFoot)
    if on then
      K.ring(b, 3, C.accent, st.focus == "grid" and 0.8 + 0.2 * sin(clock * 5) or 0.45, 0.9)
    else
      K.ring(b, 3, C.line, 0.14, 0.4)
    end
    picture(item.decor, cx + cs / 2, cy + cs / 2, cs - 5)
    if item.where ~= "pc" then
      local g = K.graphics()
      K.col(C.white)
      g.circle("fill", K.X(cx + cs - 3.4), K.Y(cy + 3.4), 2.1 * K.sc)
      K.col(item.where == "room" and C.room or C.base)
      g.circle("fill", K.X(cx + cs - 3.4), K.Y(cy + 3.4), 1.5 * K.sc)
    end
    K.addHit(b, "win", CELL + i)
  end

  local function drawGrid(x, y, w, h, clock)
    local r = row()
    if r.count == 0 then
      K.text(T("decor.none"), x, y + h / 2 - 3, K.fit(T("decor.none"), 4.8, w - 6), C.soft, "center", w)
      return
    end
    local cols = max(2, floor((w + GAP) / (CELL_MIN + GAP)))
    local cs = (w - GAP * (cols - 1)) / cols
    local step = cs + GAP
    st.cols, st.cell, st.viewH = cols, cs, h
    local full = ceil(r.count / cols) * step - GAP
    local most = max(0, full - h)
    if st.follow then
      st.follow = false
      local py = floor((st.pick - 1) / cols) * step
      if py < st.top then st.top = py elseif py + cs > st.top + h then st.top = py + cs - h end
    end
    st.top = max(0, min(most, st.top))
    K.scissor(K.R(x - 1, y - 1, w + 2, h + 2))
    for i = 1, r.count do
      local cy = y + floor((i - 1) / cols) * step - st.top
      if cy + cs > y - 1 and cy < y + h + 1 then
        drawCell(i, r.items[i], x + (i - 1) % cols * step, cy, cs, i == st.pick, clock)
      end
    end
  end

  local function drawShowroom(x, y, w, h, item, clock)
    local b = K.R(x, y, w, h)
    K.grad(b, 4, C.wallTop, C.wallFoot)
    local fy = y + h * 0.66
    K.grad(K.R(x, fy, w, y + h - fy), 4, C.floorTop, C.floorFoot)
    K.col(C.floorTop)
    K.box("fill", K.R(x, fy, w, 4), 0)
    K.col(C.skirt)
    K.box("fill", K.R(x, fy - 1, w, 1.2), 0)
    K.glow(x + w / 2, y + h * 0.42, w * 0.55, h * 0.6, C.white, 0.3 + 0.04 * sin(clock * 1.6))
    if item then
      local s = min(w - 10, h - 8)
      K.col(C.dim, 0.18)
      K.graphics().ellipse("fill", K.X(x + w / 2), K.Y(y + h * 0.5 + s * 0.46), s * 0.4 * K.sc, 1.7 * K.sc)
      picture(item.decor, x + w / 2, y + h * 0.5, s)
    end
    K.ring(b, 4, C.line, 0.22, 0.5)
  end

  local function button(i, act, bx, by, bw, bh)
    local b = K.R(bx, by, bw, bh)
    local rad = min(3, bh / 2)
    if act.danger then
      K.col(C.white)
      K.box("fill", b, rad)
      K.ring(b, rad, C.danger, 0.7, 0.5)
    else
      K.grad(b, rad, C.accent, C.accentFoot)
    end
    local label = T(act.key)
    local fs = K.fit(label, 4.6, bw - 3)
    K.bold(label, bx, by + (bh - fs) / 2 - 0.2, fs, act.danger and C.danger or C.white, "center", bw)
    if st.focus == "acts" and st.act == i and not st.confirm then
      K.ring(K.R(bx - 1, by - 1, bw + 2, bh + 2), rad + 1, C.ink, 0.75, 0.8)
    end
    K.addHit(b, "win", ACT + i)
  end

  -- the words beside the showroom: name, where it is, its description, its buttons
  local function drawInfo(x, y, w, h, item)
    if not item then
      local words = T("decor.pickNone")
      K.text(words, x, y + 3, K.fit(words, 4.2, w), C.soft, "left", w)
      return
    end
    local fs = K.fit(item.name, 6, w)
    K.bold(item.name, x, y, fs, C.ink)
    local py = y + 7.5
    local words = T(WHERE[item.where])
    local pw = min(w * 0.68, K.width(words, 3.8) + 7)
    local c = C[item.where]
    K.col(c, 0.18)
    K.box("fill", K.R(x, py, pw, 6.6), 3.3)
    K.col(c)
    K.graphics().circle("fill", K.X(x + 3), K.Y(py + 3.3), 1.1 * K.sc)
    K.text(words, x + 5.2, py + 1.2, K.fit(words, 3.8, pw - 6.5), C.ink)
    K.text(st.roomText, x + pw + 1, py + 1.3, K.fit(st.roomText, 3.6, w - pw - 1), C.soft, "right", w - pw - 1)
    K.text(item.desc, x, py + 8.8, 3.8, C.soft, "left", w)
    local n = #st.acts
    local bh, footY = 10, y + h - 10
    if st.note then
      local note = T(st.note)
      K.text(note, x, footY - 5.4, K.fit(note, 3.6, w), C.accentFoot, "left", w)
    end
    for i = 1, n do
      local bw = (w - GAP * (n - 1)) / n
      button(i, st.acts[i], x + (i - 1) * (bw + GAP), footY, bw, bh)
    end
  end

  local function panel(x, y, w, h)
    local b = K.R(x, y, w, h)
    K.grad(b, 4, C.card, C.cardFoot)
    K.ring(b, 4, C.line, 0.14, 0.4)
  end

  local function drawConfirm(body, clock)
    local c = st.confirm
    local x, y, w, h = body[1], body[2], body[3], body[4]
    K.col(C.dim, 0.5)
    K.box("fill", body, 0)
    K.addHit(body, "win", DIM)
    local mw, mh = min(w - 16, 124), 42
    local mx, my = x + (w - mw) / 2, y + (h - mh) / 2
    local b = K.R(mx, my, mw, mh)
    K.shadow(b, 6, 1.6, 0.3)
    K.col(C.card)
    K.box("fill", b, 6)
    K.bold(c.title, mx + 4, my + 5, K.fit(c.title, 5.4, mw - 8), C.ink, "center", mw - 8)
    local note = T("decor.tossNote")
    K.text(note, mx + 4, my + 13.5, K.fit(note, 4.2, mw - 8), C.soft, "center", mw - 8)
    local bw, by = (mw - 8 - GAP) / 2, my + mh - 15
    for i = 1, 2 do
      local bx = mx + 4 + (i - 1) * (bw + GAP)
      local bb = K.R(bx, by, bw, 11)
      if i == 1 then K.col(C.danger) else K.col(C.off) end
      K.box("fill", bb, 3)
      K.bold(T(i == 1 and "decor.toss" or "button.cancel"), bx, by + 3, 4.8, i == 1 and C.white or C.ink, "center", bw)
      if c.cursor == i then K.ring(K.R(bx - 1, by - 1, bw + 2, 13), 4, C.accent, 0.7 + 0.3 * sin(clock * 5), 0.9) end
      K.addHit(bb, "win", i == 1 and YES or NO)
    end
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    K.grad(body, 0, C.stageTop, C.stageFoot)
    local item = chosen()
    if portrait then
      local chipsH, infoH = 24, min(72, floor(h * 0.4))
      drawChips(x + M, y + M, w - M * 2, chipsH)
      local gy = y + M + chipsH + GAP
      local gridH = y + h - M - infoH - GAP - gy
      drawGrid(x + M, gy, w - M * 2, gridH, clock)
      K.scissor(body)
      local py = y + h - M - infoH
      panel(x + M, py, w - M * 2, infoH)
      local sw = min(64, floor(w * 0.36))
      drawShowroom(x + M + 2, py + 2, sw, infoH - 4, item, clock)
      drawInfo(x + M + sw + 5, py + 3, w - M * 2 - sw - 8, infoH - 6, item)
    else
      local railW = 50
      local dw = min(92, floor(w * 0.36))
      drawRail(x + M, y + M, railW, h - M * 2)
      local gx = x + M + railW + GAP + 1
      drawGrid(gx, y + M, x + w - M - dw - GAP - 1 - gx, h - M * 2, clock)
      K.scissor(body)
      local dx = x + w - M - dw
      panel(dx, y + M, dw, h - M * 2)
      local showH = min(50, floor(h * 0.42))
      drawShowroom(dx + 2, y + M + 2, dw - 4, showH, item, clock)
      drawInfo(dx + 4, y + M + showH + 4.5, dw - 8, h - M * 2 - showH - 7.5, item)
    end
    if st.confirm then drawConfirm(body, clock) end
    if st.toast and not K.toast(st.toast, clock, body, K.UI.red, K.UI.green, K.UI.hud) then st.toast = nil end
  end

  refresh()
  return W
end
