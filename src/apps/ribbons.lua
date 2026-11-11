-- The Ribbons app: every Pokémon that wears a Ribbon (src/ribbons.lua), most first, as a display case
-- on a dark stage: the chosen one on a lit disc with its five contest ranks, its Ribbons each on a
-- light of their colour, and the chosen Ribbon swinging in the spotlight with what it's for in the
-- game's own words.
--   buttons  Up / Down the Pokémon, A its Ribbons (the D-pad chooses, B back), B close
--   touch    a row, a Ribbon
--
--   window(ctx, env) -> win (src/apps.lua)   env.ribbons, env.bx

local floor, max, min, sin, cos, pi = math.floor, math.max, math.min, math.sin, math.cos, math.pi

local ROW_H, M, PER_ROW = 11, 3, 9
local RIBBON = 2000   -- + its place
local POP = 0.22      -- a Ribbon chosen: its bounce
local C = {
  stageTop = { 66, 22, 70 }, stageFoot = { 14, 8, 28 },
  panelTop = { 92, 50, 104, 0.82 }, panelFoot = { 40, 22, 60, 0.82 },
  caseTop = { 10, 6, 22, 0.62 }, caseFoot = { 22, 12, 36, 0.62 },
  onTop = { 138, 90, 150 }, onFoot = { 92, 54, 108 },
  gold = { 252, 204, 60 }, goldTop = { 255, 232, 130 }, goldDark = { 170, 116, 16 },
  text = { 246, 240, 250 }, soft = { 196, 180, 208 }, faint = { 120, 100, 136 }, ink = { 40, 22, 48 },
  white = { 255, 255, 255 }, black = { 0, 0, 0 }, pipOff = { 255, 255, 255, 0.14 },
}
-- the contests' colours: Cool, Beauty, Cute, Smart, Tough
local CAT = { { 240, 80, 60 }, { 70, 140, 255 }, { 255, 120, 190 }, { 70, 200, 110 }, { 255, 196, 40 } }
local CAT_NAME = { "cond.cool", "cond.beauty", "cond.cute", "cond.smart", "cond.tough" }
local HINTS = {
  list = { { "^ v", "cond.hint.mon" }, { "A", "app.ribbons" }, { "B", "hint.close" } },
  grid = { { "+", "ribbons.hint.choose" }, { "B", "hint.back" } },
}
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

-- a Ribbon's colour: its contest's, gold for the rest
local function colorOf(id)
  if id >= 1 and id <= 20 then return CAT[floor((id - 1) / 4) + 1] end
  return C.gold
end

return function(ctx, env)
  local K, Rb, Bx, T = env.K, env.ribbons, env.bx, env.T or NO_T
  local W = { title = T("app.ribbons") }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local st = { rows = {}, cursor = 1, top = 0, visible = 6, focus = "list", pick = 1, pickT = -10 }
  W.state = st

  local numText = K.textCache(function(n) return tostring(n) end)

  -- a row's Ribbons with their places in the grid, made once (normal rows of nine, the gifts below)
  local function fill(r)
    if r.items then return r end
    local s = session()
    local normal, gift = Rb.ids(r.mon)
    r.items, r.colOf, r.rowOf = {}, {}, {}
    local rows = 0
    for i, id in ipairs(normal) do
      r.items[i], r.colOf[i], r.rowOf[i] = id, (i - 1) % PER_ROW, floor((i - 1) / PER_ROW)
      rows = r.rowOf[i] + 1
    end
    r.giftRow = rows
    for j, id in ipairs(gift) do
      local i = #normal + j
      r.items[i], r.colOf[i], r.rowOf[i] = id, j - 1, rows
    end
    r.rows = rows + (#gift > 0 and 1 or 0)
    r.info = Bx and Bx.info(r.mon, T) or nil
    r.countText = T.f("ribbons.count", r.count)
    r.whereText = r.box and tostring(Bx and Bx.boxName(s, r.box) or r.box) or T("cond.party")
    r.contest = Rb.contest(r.mon)
    r.descs = {}
    for i, id in ipairs(r.items) do r.descs[i] = Rb.desc(s, id) or "" end
    return r
  end

  -- (keeps the chosen row in view, unless the list was scrolled by hand since the last press: a drag
  -- or the wheel would otherwise be pulled straight back to it on the next frame)
  local function clamp(follow)
    if follow then st.free = false end
    local n = #st.rows
    st.cursor = max(1, min(st.cursor, max(1, n)))
    if not st.free then
      if st.cursor > st.top + st.visible then st.top = st.cursor - st.visible end
      if st.cursor <= st.top then st.top = st.cursor - 1 end
    end
    st.top = max(0, min(st.top, max(0, n - st.visible)))
  end
  st.rows = Rb.list(session())

  local function current()
    local r = st.rows[st.cursor]
    return r and fill(r) or nil
  end
  local function setPick(i)
    st.pick, st.pickT = i, now()
  end

  local function moveCursor(d)
    local c = max(1, min(#st.rows, st.cursor + d))
    if c ~= st.cursor then
      st.cursor = c
      setPick(1)
      clamp(true)
      se("SE_SELECT")
    end
  end

  -- to the Ribbon that way: along its row, or the nearest in the next row that has any
  local function moveGrid(dc, dr)
    local r = current()
    if not r then return end
    local p = st.pick
    local best
    if dr == 0 then
      for i = 1, #r.items do
        if r.rowOf[i] == r.rowOf[p] and r.colOf[i] == r.colOf[p] + dc then best = i end
      end
    else
      local line = r.rowOf[p] + dr
      local gap = math.huge
      for i = 1, #r.items do
        if r.rowOf[i] == line and math.abs(r.colOf[i] - r.colOf[p]) < gap then
          best, gap = i, math.abs(r.colOf[i] - r.colOf[p])
        end
      end
    end
    if best then
      setPick(best)
      se("SE_SELECT")
    end
  end

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
    if st.focus == "grid" then
      if pressed("b") then st.focus = "list"; se("SE_SELECT")
      elseif nav.left then moveGrid(-1, 0)
      elseif nav.right then moveGrid(1, 0)
      elseif nav.up then moveGrid(0, -1)
      elseif nav.down then moveGrid(0, 1)
      end
      return true
    end
    if pressed("b") then return false end
    if nav.up then moveCursor(-1)
    elseif nav.down then moveCursor(1)
    elseif (pressed("a") or nav.right) and current() and #current().items > 0 then
      st.focus = "grid"
      se("SE_SELECT")
    end
    return true
  end

  function W.tap(arg)
    if type(arg) ~= "number" then return end
    if arg > RIBBON then
      local r = current()
      if r and r.items[arg - RIBBON] then
        setPick(arg - RIBBON)
        st.focus = "grid"
        se("SE_SELECT")
      end
      return
    end
    if st.rows[arg] then
      if st.cursor ~= arg then setPick(1) end
      st.cursor, st.focus = arg, "list"
      clamp(true)
      se("SE_SELECT")
    end
  end

  function W.scroll(dy)
    st.free = true
    st.top = max(0, min(max(0, #st.rows - st.visible), st.top - dy / ROW_H))
  end

  function W.hints() return T.list(HINTS[st.focus]) end

  -- ------- drawing (no tables made here)

  -- a Ribbon's picture centred on cx, cy, `size` units, turned by `turn` from its top
  local function drawIcon(id, cx, cy, size, big, turn)
    local img, q, px = Rb.icon(id, big)
    if not img then return end
    local g = K.graphics()
    local k = size * K.sc / px
    g.setColor(1, 1, 1, 1)
    local hang = turn and px * 0.08 or px / 2
    local y = turn and cy - size / 2 + px * 0.08 * k / K.sc or cy
    if q then g.draw(img, q, K.X(cx), K.Y(y), turn or 0, k, k, px / 2, hang)
    else g.draw(img, K.X(cx), K.Y(y), turn or 0, k, k, px / 2, hang) end
  end

  local function panel(b, rad)
    K.grad(b, rad, C.panelTop, C.panelFoot)
    K.ring(b, rad, C.white, 0.1, 0.4)
  end

  local function drawList(x, y, w, h)
    st.visible = max(1, floor((h - 2) / ROW_H))
    clamp()
    panel(K.R(x, y, w, h), 4)
    local focused = st.focus == "list"
    -- (scrolled by hand, the top falls between rows: from the row it's in, clipped to the list)
    local G = K.graphics()
    local psx, psy, psw, psh
    if G.getScissor then psx, psy, psw, psh = G.getScissor() end
    local area = K.R(x, y + 1, w, h - 2)
    K.scissor(area)
    local first = floor(st.top) + 1
    for i = first, min(#st.rows, first + st.visible) do
      local r = fill(st.rows[i])
      local ry = y + 1 + (i - 1 - st.top) * ROW_H
      local on = i == st.cursor
      local rb = K.R(x + 1.2, ry + 0.4, w - 2.4, ROW_H - 0.8)
      if on then
        K.grad(rb, 3, C.onTop, C.onFoot)
        if focused then K.ring(rb, 3, C.gold, 0.9, 0.7) end
      end
      if env.monIconOf then pcall(env.monIconOf, r.mon, x + 1, ry - 0.5, 11) end
      local count = numText(r.count)
      local pw = max(7, K.width(count, 4) + 4)
      local name = r.info and r.info.name or "?"
      K.text(name, x + 13, ry + 3, K.fit(name, 4.6, w - 18 - pw), on and C.white or C.text)
      local pill = K.R(x + w - pw - 3, ry + 2.3, pw, 6.4)
      K.grad(pill, 3.2, C.goldTop, C.goldDark)
      K.bold(count, pill[1], pill[2] + 0.9, 4, C.ink, "center", pw)
      K.addHit(K.R(x, ry, w, ROW_H), "win", i, area)
    end
    if psx then G.setScissor(psx, psy, psw, psh) else G.setScissor() end
    K.scrollbar(x + w, y + 1, h - 2, st.top, st.visible, #st.rows)
  end

  -- the five contests: a word and four pips, one for each rank won
  local function drawTracks(r, x, y, w)
    local rowH = 5.5
    for i = 1, 5 do
      local ry = y + (i - 1) * rowH
      local word = T(CAT_NAME[i])
      K.text(word, x, ry + 0.4, K.fit(word, 3.3, w * 0.52), C.soft)
      local pw = 4.4
      for p = 1, 4 do
        local px = x + w - (5 - p) * (pw + 0.8)
        if p <= r.contest[i] then K.col(CAT[i]) else K.col(C.pipOff) end
        K.box("fill", K.R(px, ry + 1, pw, 2.8), 1.2)
      end
    end
  end

  local function rays(cx, cy, r, clock, c, a)
    local g = K.graphics()
    g.push()
    g.translate(K.X(cx), K.Y(cy))
    g.rotate(clock * 0.5)
    K.col(c, a)
    local rr = r * K.sc
    for i = 0, 7 do
      local t = i * pi / 4
      g.polygon("fill", 0, 0, cos(t) * rr, sin(t) * rr, cos(t + 0.3) * rr, sin(t + 0.3) * rr)
    end
    g.pop()
  end

  local function drawDetail(x, y, w, h, clock)
    local r = current()
    if not r then return end
    panel(K.R(x, y, w, h), 4)
    local top = r.items[1] and colorOf(r.items[1]) or C.gold
    -- the Pokémon, on a lit disc
    local ps = 26
    local px, py = x + 3, y + 3
    local g = K.graphics()
    K.glow(px + ps / 2, py + ps / 2, ps * 0.85, ps * 0.85, top, 0.5)
    K.col(C.white, 0.1)
    g.circle("fill", K.X(px + ps / 2), K.Y(py + ps / 2), ps * 0.5 * K.sc)
    if r.info and env.monPic then pcall(env.monPic, r.info.species, px, py, ps, 1, r.mon) end
    local tracksW = min(44, w * 0.38)
    local tx = px + ps + 3
    local room = w - (tx - x) - tracksW - 6
    local name = r.info and r.info.name or "?"
    K.bold(name, tx, y + 4, K.fit(name, 5.4, room), C.white)
    K.text(r.whereText, tx, y + 11, 4.2, C.soft)
    K.bold(r.countText, tx, y + 17.5, 4.8, C.goldTop)
    drawTracks(r, x + w - tracksW - 3, y + 3.5, tracksW)
    -- the case
    local caseY = y + ps + 5
    local descH = 20
    local caseH = h - (caseY - y) - descH - 3
    K.grad(K.R(x + 2.5, caseY, w - 5, caseH), 3, C.caseTop, C.caseFoot)
    local gx = x + 4
    local cs = min((w - 8) / PER_ROW, 14, (caseH - 3) / max(1, r.rows))
    if st.pick > #r.items then st.pick = 1 end
    local since = clock - st.pickT
    local gy = caseY + 1.5
    for i = 1, #r.items do
      local cx = gx + r.colOf[i] * cs + cs / 2
      local cy = gy + r.rowOf[i] * cs + cs / 2 + (r.rowOf[i] >= r.giftRow and 0.8 or 0)
      local id = r.items[i]
      local on = i == st.pick
      K.glow(cx, cy, cs * (on and 0.95 or 0.6), cs * (on and 0.95 or 0.6), colorOf(id), on and 0.7 or 0.3)
      local k = 0.92
      if on and since >= 0 and since < POP then k = 0.92 + 0.35 * sin(since / POP * pi) end
      drawIcon(id, cx, cy, cs * k, false)
      if on then
        K.ring(K.R(cx - cs / 2 + 0.2, cy - cs / 2 + 0.2, cs - 0.4, cs - 0.4), 2, C.gold,
          st.focus == "grid" and 0.75 + 0.25 * sin(clock * 5) or 0.35, 0.7)
      end
      K.addHit(K.R(cx - cs / 2, cy - cs / 2, cs, cs), "win", RIBBON + i)
    end
    -- the chosen one, in the spotlight
    local dy = y + h - descH
    local id = r.items[st.pick]
    if not id then return end
    local cx, cy = x + 12, dy + descH / 2 - 0.5
    local c = colorOf(id)
    rays(cx, cy, 13, clock, c, 0.12)
    K.glow(cx, cy, 13, 12, c, 0.65)
    drawIcon(id, cx, cy, 16.5, true, sin(clock * 2.2) * 0.1)
    K.text(r.descs[st.pick], x + 24, dy + 3, 4, C.text, "left", w - 28)
    -- (a shine crossing the words now and then)
    local k = (clock % 5) / 1.2
    if k < 1 then
      local sx = x + 20 + (w - 16) * k
      K.col(C.white, 0.08)
      K.box("fill", K.R(sx, dy + 1, 6, descH - 3), 1)
    end
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    K.grad(body, 0, C.stageTop, C.stageFoot)
    K.glow(x + w * 0.75, y + h * 0.3, w * 0.55, h * 0.8, C.gold, 0.1)
    if #st.rows == 0 then
      K.glow(x + w / 2, y + h / 2, w * 0.4, h * 0.45, CAT[3], 0.3)
      K.text(T("ribbons.none"), x, y + h / 2 - 3, 5, C.soft, "center", w)
      return
    end
    if portrait then
      local dh = min(h * 0.58, 124)
      drawDetail(x + M, y + M, w - M * 2, dh, clock)
      drawList(x + M, y + M * 2 + dh, w - M * 2, h - dh - M * 3)
    else
      local lw = floor((w - M * 3) * 0.34)
      drawList(x + M, y + M, lw, h - M * 2)
      drawDetail(x + M * 2 + lw, y + M, w - M * 3 - lw, h - M * 2, clock)
    end
  end

  return W
end
