-- The Decorate app (Ruby / Sapphire / Emerald, the bedroom PC): a furniture catalogue of the
-- decorations the player owns (src/decorate.lua), by the game's categories. A showroom for the chosen
-- piece, where it is, and what can be done with it: into the room (the game's own cursor), back to
-- the PC, or thrown away. The game's rules: only dolls and cushions go in the bedroom, and a
-- decoration in use can't be thrown away.
--   buttons  the D-pad the grid, L / R the category, A its actions, B close
--   touch    a category, a piece, its buttons
-- The Pokédex's glass: panes over a backdrop lit by the category's colour (eased as it changes). Its
-- motion, numbers only: the category's highlight glides along the rail (the chips, portrait), the chosen
-- piece's ring glides from cell to cell and the grid scrolls smoothly; the pieces rise in one after
-- another as the window opens or the category turns (sliding from the side it turned to); the showroom's
-- piece pops up on its shadow and its words slide in as another is chosen; the toss question pops up
-- over a dim.
--
--   window(ctx, env) -> win (src/apps.lua)   env.decorate

local floor, ceil, max, min, sin, abs, pi = math.floor, math.ceil, math.max, math.min, math.sin, math.abs, math.pi

local M, GAP, CELL_MIN = 3, 2, 24
local RAIL, CELL, ACT, YES, NO, DIM, CARD = 1000, 2000, 3000, 4001, 4002, 4003, 4004
local C = {
  ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, faint = { 162, 162, 170 }, white = { 255, 255, 255 },
  black = { 0, 0, 0 }, accent = { 10, 132, 255 }, danger = { 255, 59, 48 }, warn = { 230, 120, 20 },
  track = { 118, 118, 128, 0.16 }, slate = { 120, 132, 178 },
  room = { 46, 170, 160 }, base = { 232, 92, 92 }, pc = { 120, 124, 140 },
}
-- each category's colour, in the game's order (desk, chair, plant, ornament, mat, poster, doll, cushion)
local CAT_C = { { 196, 140, 90 }, { 240, 150, 70 }, { 90, 186, 100 }, { 170, 120, 230 }, { 50, 176, 190 },
                { 90, 140, 240 }, { 245, 116, 168 }, { 238, 96, 96 } }
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
    st.follow, st.dragged = false, true
  end

  function W.hints()
    if st.confirm or st.focus == "acts" then return T.list(HINTS_ACT) end
    return T.list(#st.acts > 0 and HINTS or HINTS_BARE)
  end

  -- ------- drawing (no tables made here)

  local approach, outCubic, outBack, stagger = K.approach, K.outCubic, K.outBack, K.stagger
  local G, bodyNow = nil, nil
  -- the motion's numbers (see the top)
  local mv = { lastT = nil, openAt = nil, coloured = false, r = 0.6, g = 0.6, b = 0.6, r2 = 0.6, g2 = 0.6, b2 = 0.6,
               cat = nil, catAt = -10, catDir = 0, rail = nil, chipX = nil, chipY = nil, gx = nil, gy = nil,
               top = nil, item = nil, itemAt = -10, confirm = nil, confirmAt = -10 }
  W.motion = mv

  -- (everything drawn after it at `e` of itself, until unfade(); numbers only)
  local FADES, nFade = {}, 0
  local function fade(e)
    nFade = nFade + 1
    FADES[nFade] = K.getFade()
    K.setFade(FADES[nFade] * (e > 0 and e or 0))
  end
  local function unfade()
    K.setFade(FADES[nFade])
    nFade = nFade - 1
  end
  local function catColour(i)
    local r = st.list.cats[i]
    return r and CAT_C[r.cat + 1] or C.slate
  end

  -- a decoration's picture, `size` units round cx, cy (whole pixels once settled; `pop` scales it)
  local function picture(decor, cx, cy, size, pop)
    local img = Dc.picture(decor)
    K.rescissor()
    if not img then return end
    local sc = K.sc
    local pw, ph = img:getDimensions()
    local k = size * sc / max(pw, ph)
    if k >= 1 then k = floor(k) end
    if pop and pop ~= 1 then k = k * pop end
    G.setColor(1, 1, 1, K.getFade())
    G.draw(img, floor(K.X(cx) - pw * k / 2 + 0.5), floor(K.Y(cy) - ph * k / 2 + 0.5), 0, k, k)
  end

  -- a category's dot: filled when it can go in the bedroom, a ring when it can't
  local function catDot(cx, cy, r, c, room)
    K.col(c)
    if room then
      G.circle("fill", K.X(cx), K.Y(cy), r * K.sc)
    else
      G.setLineWidth(max(1, 0.4 * K.sc))
      G.circle("line", K.X(cx), K.Y(cy), (r - 0.2) * K.sc)
    end
  end

  -- ------- the categories: a rail (its highlight gliding) or, portrait, two rows of chips

  local function drawRail(x, y, w, h, clock, dt)
    K.glass(K.R(x, y, w, h), 4, 0.5)
    local n = #st.list.cats
    local rh = min(12, (h - 4) / n)
    if mv.rail == nil then mv.rail = st.cat end
    mv.rail = approach(mv.rail, st.cat, dt, 24)
    local hb = K.R(x + 2, y + 2 + (mv.rail - 1) * rh, w - 4, rh)
    K.col(C.white, 0.88)
    K.box("fill", hb, 2.5)
    K.ring(hb, 2.5, K.dark(catColour(st.cat), 0.1), st.focus == "grid" and 0.8 or 0.45, 0.6)
    local since = clock - mv.openAt
    for i = 1, n do
      local r = st.list.cats[i]
      local b = K.R(x + 2, y + 2 + (i - 1) * rh, w - 4, rh)
      local e = stagger(since, i - 1, 0.03, 0.28)
      local ox = (1 - e) * -5
      fade(e)
      local on = i == st.cat
      local ty = b[2] + (b[4] - 4.4 * 1.2) / 2 + 0.2
      catDot(b[1] + 3.4 + ox, b[2] + b[4] / 2, 1.2, CAT_C[r.cat + 1] or C.slate, r.room)
      local nameW = b[3] - 22
      local fs = K.fit(r.name, 4.4, nameW)
      if on then K.bold(r.name, b[1] + 6 + ox, ty, fs, C.ink) else K.text(r.name, b[1] + 6 + ox, ty, fs, C.ink) end
      K.text(r.countText, b[1] + b[3] - 18 + ox, ty + 0.4, 3.6, on and C.ink or C.soft, "right", 16.5)
      unfade()
      K.addHit(b, "win", RAIL + i)
    end
  end

  local function drawChips(x, y, w, h, clock, dt)
    local n = #st.list.cats
    local cols = ceil(n / 2)
    local cw, ch = (w - GAP * (cols - 1)) / cols, (h - GAP) / 2
    local tc, tr = (st.cat - 1) % cols, floor((st.cat - 1) / cols)
    if mv.chipX == nil then mv.chipX, mv.chipY = tc, tr end
    mv.chipX, mv.chipY = approach(mv.chipX, tc, dt, 22), approach(mv.chipY, tr, dt, 22)
    for i = 1, n do
      local b = K.R(x + (i - 1) % cols * (cw + GAP), y + floor((i - 1) / cols) * (ch + GAP), cw, ch)
      K.col(C.white, 0.34)
      K.box("fill", b, 3)
      K.ring(b, 3, C.white, 0.7, 0.3)
    end
    local hb = K.R(x + mv.chipX * (cw + GAP), y + mv.chipY * (ch + GAP), cw, ch)
    K.col(C.black, 0.08)
    K.box("fill", K.R(hb[1], hb[2] + 0.4, hb[3], hb[4]), 3)
    K.col(C.white)
    K.box("fill", hb, 3)
    K.ring(hb, 3, K.dark(catColour(st.cat), 0.1), 0.7, 0.5)
    for i = 1, n do
      local r = st.list.cats[i]
      local b = K.R(x + (i - 1) % cols * (cw + GAP), y + floor((i - 1) / cols) * (ch + GAP), cw, ch)
      local on = i == st.cat
      local fs = K.fit(r.name, 4.2, cw - 3)
      if on then K.bold(r.name, b[1], b[2] + 1.4, fs, C.ink, "center", cw)
      else K.text(r.name, b[1], b[2] + 1.4, fs, C.ink, "center", cw) end
      local tw = K.width(r.countText, 3.4)
      catDot(b[1] + (cw - tw) / 2 - 1.8, b[2] + ch - 2.8, 1, CAT_C[r.cat + 1] or C.slate, r.room)
      K.text(r.countText, b[1] + 0.8, b[2] + ch - 4.9, 3.4, on and C.ink or C.soft, "center", cw)
      K.addHit(b, "win", RAIL + i)
    end
  end

  -- ------- the pieces: panes of glass, the chosen one's ring gliding over them; rising in by turns

  local function drawGrid(x, y, w, h, clock, dt)
    local r = st.list.cats[st.cat]
    local since = clock - mv.catAt
    if r.count == 0 then
      local words = T("decor.none")
      local e = stagger(since, 0, 0, 0.3)
      K.text(words, x, y + h / 2 - 3 + (1 - e) * 4, K.fit(words, 4.8, w - 6), C.soft, "center", w, e)
      mv.gx = nil
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
    -- (smoothly to where the D-pad sent it; with the finger, at once)
    if mv.top == nil or st.dragged then mv.top = st.top else mv.top = approach(mv.top, st.top, dt, 20) end
    st.dragged = nil
    local top = mv.top
    K.scissor(K.R(x - 1, y - 1, w + 2, h + 2))
    local tx, ty = (st.pick - 1) % cols * step, floor((st.pick - 1) / cols) * step
    if mv.gx == nil then mv.gx, mv.gy = tx, ty end
    mv.gx, mv.gy = approach(mv.gx, tx, dt, 26), approach(mv.gy, ty, dt, 26)
    local hopT = clock - mv.itemAt
    local hop = (hopT >= 0 and hopT < 0.34) and sin(hopT / 0.34 * pi) * 1.6 or 0
    local firstRow = floor(top / step)
    local dir = mv.catDir
    for i = 1, r.count do
      local row = floor((i - 1) / cols)
      local cy = y + row * step - top
      if cy + cs > y - 1 and cy < y + h + 1 then
        local cx = x + (i - 1) % cols * step
        local e = stagger(since, (row - firstRow) * cols + (i - 1) % cols, 0.025, 0.28)
        local ox, oy = (1 - e) * dir * 8, (1 - e) * (dir == 0 and 5 or 2)
        fade(e)
        local on = i == st.pick
        local b = K.R(cx + ox, cy + oy, cs, cs)
        K.col(C.white, on and 0.8 or 0.42)
        K.box("fill", b, 3)
        K.ring(b, 3, C.white, 0.75, 0.3)
        local item = r.items[i]
        picture(item.decor, cx + cs / 2 + ox, cy + cs / 2 + oy - (on and hop or 0), cs - 5)
        if item.where ~= "pc" then
          K.col(C.white)
          G.circle("fill", K.X(cx + cs - 3.4 + ox), K.Y(cy + 3.4 + oy), 2.1 * K.sc)
          K.col(item.where == "room" and C.room or C.base)
          G.circle("fill", K.X(cx + cs - 3.4 + ox), K.Y(cy + 3.4 + oy), 1.5 * K.sc)
        end
        unfade()
        K.addHit(K.R(cx, cy, cs, cs), "win", CELL + i)
      end
    end
    local hb = K.R(x + mv.gx - 0.6, y + mv.gy - top - 0.6, cs + 1.2, cs + 1.2)
    local c = K.dark(catColour(st.cat), 0.1)
    K.col(c, 0.1)
    K.box("fill", hb, 3.5)
    K.ring(hb, 3.5, c, st.focus == "grid" and (0.75 + 0.25 * K.pulse()) or 0.45, 0.8)
    K.scissor(bodyNow)
    K.scrollbar(x + w + 1.6, y, h, top, h, full)
  end

  -- ------- the showroom: the chosen piece popping up in a little room of its category's colour

  local function drawShowroom(x, y, w, h, item, clock)
    local b = K.R(x, y, w, h)
    local c = catColour(st.cat)
    K.col(c, 0.16)
    K.box("fill", b, 3.5)
    local fy = y + h * 0.68
    K.col(c, 0.2)
    K.box("fill", K.R(x, fy, w, y + h - fy), 3.5)
    K.col(C.white, 0.7)
    K.box("fill", K.R(x, fy - 0.6, w, 0.6), 0)
    K.glow(x + w / 2, y + h * 0.44, w * 0.5, h * 0.55, C.white, 0.34 + 0.05 * sin(clock * 1.6))
    if item then
      local t = clock - mv.itemAt
      local pop = 0.6 + 0.4 * outBack(t / 0.38)
      local fa = outCubic(t / 0.16)
      local s = min(w - 10, h - 8)
      fade(fa)
      K.col(C.black, 0.16)
      G.ellipse("fill", K.X(x + w / 2), K.Y(y + h * 0.5 + s * 0.46), s * 0.38 * pop * K.sc, 1.6 * K.sc)
      picture(item.decor, x + w / 2, y + h * 0.5 + (1 - pop) * s * 0.3, s, pop)
      unfade()
    end
    K.ring(b, 3.5, C.white, 0.8, 0.35)
  end

  -- an action's button: Place / Put Away filled in the accent, Toss in red words on glass; the
  -- controller's focus ringed
  local function button(i, act, bx, by, bw, bh)
    local b = K.R(bx, by, bw, bh)
    local rad = min(3, bh / 2)
    if act.danger then
      K.col(C.white, 0.75)
      K.box("fill", b, rad)
      K.ring(b, rad, C.danger, 0.55, 0.4)
    else
      K.col(C.accent)
      K.box("fill", b, rad)
    end
    local label = T(act.key)
    local fs = K.fit(label, 4.6, bw - 3)
    K.bold(label, bx, by + (bh - fs * 1.2) / 2, fs, act.danger and C.danger or C.white, "center", bw)
    if st.focus == "acts" and st.act == i and not st.confirm then K.focusRing(b, rad, 0.75 + 0.25 * K.pulse()) end
    K.addHit(b, "win", ACT + i)
  end

  -- the words beside (or under) the showroom: name, where it is, its description, its buttons; sliding
  -- in as another piece is chosen
  local function drawInfo(x, y, w, h, item, clock)
    if not item then
      local words = T("decor.pickNone")
      K.text(words, x, y + 3, K.fit(words, 4.2, w), C.soft, "left", w)
      return
    end
    local e = outCubic((clock - mv.itemAt - 0.05) / 0.3)
    local ox = (1 - e) * 6
    fade(e)
    local fs = K.fit(item.name, 6, w)
    K.bold(item.name, x + ox, y, fs, C.ink)
    local py = y + 7.5
    local words = T(WHERE[item.where])
    local pw = min(w * 0.68, K.width(words, 3.8) + 7)
    local c = C[item.where]
    K.col(c, 0.18)
    K.box("fill", K.R(x + ox, py, pw, 6.6), 3.3)
    K.col(c)
    G.circle("fill", K.X(x + 3 + ox), K.Y(py + 3.3), 1.1 * K.sc)
    K.text(words, x + 5.2 + ox, py + 1.2, K.fit(words, 3.8, pw - 6.5), C.ink)
    K.text(st.roomText, x + pw + 1 + ox, py + 1.3, K.fit(st.roomText, 3.6, w - pw - 1), C.soft, "right", w - pw - 1)
    K.text(item.desc, x + ox, py + 8.8, 3.8, C.soft, "left", w)
    unfade()
    local n = #st.acts
    local bh, footY = 10, y + h - 10
    if st.note then
      local note = T(st.note)
      K.text(note, x, footY - 5.4, K.fit(note, 3.6, w), C.warn, "left", w)
    end
    for i = 1, n do
      local bw = (w - GAP * (n - 1)) / n
      button(i, st.acts[i], x + (i - 1) * (bw + GAP), footY, bw, bh)
    end
  end

  -- the toss question: a card popping up over a dim
  local function drawConfirm(body, clock)
    local c = st.confirm
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local e = outCubic((clock - mv.confirmAt) / 0.22)
    K.dim(body, 0.26 * e)
    K.addHit(body, "win", DIM)
    local mw, mh = min(w - 16, 124), 42
    local mx, my = x + (w - mw) / 2, y + (h - mh) / 2 + (1 - e) * 8
    local b = K.R(mx, my, mw, mh)
    fade(e)
    K.shadow(b, 6, 1.6, 0.28)
    K.glass(b, 6, 0.92)
    K.addHit(b, "win", CARD)
    K.bold(c.title, mx + 4, my + 5, K.fit(c.title, 5.4, mw - 8), C.ink, "center", mw - 8)
    local note = T("decor.tossNote")
    K.text(note, mx + 4, my + 13.5, K.fit(note, 4.2, mw - 8), C.soft, "center", mw - 8)
    local bw, by = (mw - 8 - GAP) / 2, my + mh - 15
    for i = 1, 2 do
      local bb = K.R(mx + 4 + (i - 1) * (bw + GAP), by, bw, 11)
      K.button(bb, T(i == 1 and "decor.toss" or "button.cancel"), i == 1 and "danger" or "gray", c.cursor == i, 4.8)
      K.addHit(bb, "win", i == 1 and YES or NO)
    end
    unfade()
  end

  -- (the backdrop's lights: the category's colour, lighter behind; eased)
  local function tint(dt)
    local t1 = catColour(st.cat)
    local rate = mv.coloured and 6 or 1000
    mv.coloured = true
    mv.r, mv.g, mv.b = approach(mv.r, t1[1] / 255, dt, rate), approach(mv.g, t1[2] / 255, dt, rate),
      approach(mv.b, t1[3] / 255, dt, rate)
    mv.r2 = approach(mv.r2, (t1[1] + (255 - t1[1]) * 0.4) / 255, dt, rate)
    mv.g2 = approach(mv.g2, (t1[2] + (255 - t1[2]) * 0.4) / 255, dt, rate)
    mv.b2 = approach(mv.b2, (t1[3] + (255 - t1[3]) * 0.4) / 255, dt, rate)
  end

  function W.draw(body, clock, portrait)
    G = K.graphics()
    bodyNow = body
    local dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT = clock
    local x, y, w, h = body[1], body[2], body[3], body[4]
    -- (what changed since the last frame starts its motion)
    if not mv.openAt then mv.openAt, mv.catAt = clock, clock end
    if mv.cat ~= st.cat then
      if mv.cat ~= nil then
        local n = #st.list.cats
        local d = st.cat - mv.cat
        if abs(d) > n / 2 then d = -d end
        mv.catAt, mv.catDir, mv.gx, mv.top = clock, d > 0 and 1 or -1, nil, nil
      end
      mv.cat = st.cat
    end
    local item = chosen()
    if item ~= mv.item then mv.item, mv.itemAt = item, clock end
    if st.confirm ~= mv.confirm then mv.confirm, mv.confirmAt = st.confirm, clock end
    tint(dt)
    K.backdrop(body, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2)
    K.scissor(body)
    if portrait then
      local chipsH, infoH = 24, min(72, floor(h * 0.4))
      drawChips(x + M, y + M, w - M * 2, chipsH, clock, dt)
      local gy = y + M + chipsH + GAP
      local gridH = y + h - M - infoH - GAP - gy
      drawGrid(x + M, gy, w - M * 2 - 3, gridH, clock, dt)
      K.scissor(body)
      local py = y + h - M - infoH
      K.glass(K.R(x + M, py, w - M * 2, infoH), 4, 0.6)
      local sw = min(64, floor(w * 0.36))
      drawShowroom(x + M + 2, py + 2, sw, infoH - 4, item, clock)
      drawInfo(x + M + sw + 5, py + 3, w - M * 2 - sw - 8, infoH - 6, item, clock)
    else
      local railW = 50
      local dw = min(92, floor(w * 0.36))
      drawRail(x + M, y + M, railW, h - M * 2, clock, dt)
      local gx = x + M + railW + GAP + 1
      drawGrid(gx, y + M, x + w - M - dw - GAP - 4 - gx, h - M * 2, clock, dt)
      K.scissor(body)
      local dx = x + w - M - dw
      K.glass(K.R(dx, y + M, dw, h - M * 2), 4, 0.6)
      local showH = min(50, floor(h * 0.42))
      drawShowroom(dx + 2, y + M + 2, dw - 4, showH, item, clock)
      drawInfo(dx + 4, y + M + showH + 4.5, dw - 8, h - M * 2 - showH - 7.5, item, clock)
    end
    if st.confirm then drawConfirm(body, clock) end
    if st.toast and not K.toast(st.toast, clock, body, C.danger, K.UI.green, K.UI.hud) then st.toast = nil end
  end

  refresh()
  return W
end
