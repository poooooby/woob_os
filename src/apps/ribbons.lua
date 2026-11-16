-- The Ribbons app: every Pokémon that wears a Ribbon (src/ribbons.lua), most first, as a display case
-- in the Pokédex's glass: the list of them on the left (upright: below), and the chosen one on a pane of
-- its type's colour (its picture popping up, animated as the Pokédex's, with a Poké Ball turning slowly
-- behind it) with its five contest ranks, its Ribbons in a case of glass, and the chosen Ribbon swinging
-- in the spotlight with what it's for in the game's own words.
-- Its motion (numbers only, in `mv`): the backdrop turning to the chosen Ribbon's colour and the
-- Pokémon's type, the rows rising in one after another as it opens, the list's highlight gliding and the
-- list scrolling smoothly, the Ribbons rising into the case as a Pokémon is shown and its ranks lighting
-- up, the case's highlight gliding from Ribbon to Ribbon, the chosen one bouncing and its words sliding in.
--   buttons  Up / Down the Pokémon, A its Ribbons (the D-pad chooses, B back), B close
--   touch    a row, a Ribbon
--
--   window(ctx, env) -> win (src/apps.lua)   env.ribbons, env.bx, env.dexSprite

local floor, max, min, sin, cos, pi = math.floor, math.max, math.min, math.sin, math.cos, math.pi

local ROW_H, M, GAP, PER_ROW = 11, 3, 2, 9
local RIBBON = 2000   -- + its place
local POP = 0.22      -- a Ribbon chosen: its bounce
local C = {
  ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, faint = { 160, 160, 170 }, accent = { 10, 132, 255 },
  white = { 255, 255, 255 }, black = { 0, 0, 0 }, gold = { 252, 204, 60 }, goldTop = { 255, 228, 120 },
  goldDark = { 214, 150, 20 }, goldInk = { 92, 60, 0 }, pipOff = { 255, 255, 255, 0.3 },
  track = { 118, 118, 128, 0.16 }, slate = { 120, 132, 178 }, slate2 = { 150, 120, 190 },
}
local SHADE_TOP, SHADE_FOOT = { 255, 255, 255, 0.28 }, { 0, 0, 0, 0.16 }
-- the contests' colours: Cool, Beauty, Cute, Smart, Tough
local CAT = { { 240, 80, 60 }, { 70, 140, 255 }, { 255, 120, 190 }, { 70, 200, 110 }, { 255, 196, 40 } }
local CAT_NAME = { "cond.cool", "cond.beauty", "cond.cute", "cond.smart", "cond.tough" }
-- the types' colours (the game's ids; 18 WoobleDex's Fairy)
local TYPE = {
  [0] = { 168, 168, 120 }, [1] = { 192, 48, 40 }, [2] = { 168, 144, 240 }, [3] = { 160, 64, 160 },
  [4] = { 224, 192, 104 }, [5] = { 184, 160, 56 }, [6] = { 168, 184, 32 }, [7] = { 112, 88, 152 },
  [8] = { 184, 184, 208 }, [9] = { 104, 160, 144 }, [10] = { 240, 128, 48 }, [11] = { 104, 144, 240 },
  [12] = { 120, 200, 80 }, [13] = { 248, 208, 48 }, [14] = { 248, 88, 136 }, [15] = { 152, 216, 216 },
  [16] = { 112, 56, 248 }, [17] = { 112, 88, 72 }, [18] = { 238, 153, 172 },
}
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
  function W.close() if env.dexSprite then pcall(env.dexSprite.stop) end end

  -- ------- drawing (no tables, closures or strings made here)

  local G, bodyNow = nil, nil
  -- the motion's numbers
  local mv = { openAt = nil, lastT = nil, rec = nil, recAt = 0, pick = nil, pickAt = 0, selY = nil, top = 0,
               gx = nil, gy = nil, gs = nil, coloured = false, r = 0.6, g = 0.6, b = 0.6, r2 = 0.6, g2 = 0.6, b2 = 0.6 }
  W.motion = mv

  -- (a paragraph's size at the player's text size: the biggest, from its size grown down to its size at
  -- 100%, whose lines fit maxH units; worked out when what it's given changes and kept in `rec`)
  local function paraFit(rec, s, size, w, maxH)
    local ts = K.textScale()
    if ts == 1 or not s or s == "" then return size end
    if rec.s == s and rec.size == size and rec.w == w and rec.h == maxH and rec.ts == ts and rec.sc == K.sc then
      return rec.out
    end
    local drawn = size * ts
    while drawn > size do
      local f = K.font(drawn * K.sc)
      local ok, _, lines = pcall(f.getWrap, f, s, w * K.sc)
      local n = ok and type(lines) == "table" and #lines or 1
      if n * f:getHeight() / K.sc <= maxH + 0.01 then break end
      drawn = max(size, drawn - 0.2)
    end
    rec.s, rec.size, rec.w, rec.h, rec.ts, rec.sc, rec.out = s, size, w, maxH, ts, K.sc, drawn / ts
    return rec.out
  end
  local descFit = {}

  -- a Ribbon's picture centred on cx, cy, `size` units, turned by `turn` from its top
  local function drawIcon(id, cx, cy, size, big, turn)
    local img, q, px = Rb.icon(id, big)
    if not img then return end
    local k = size * K.sc / px
    G.setColor(1, 1, 1, K.getFade())
    local hang = turn and px * 0.08 or px / 2
    local y = turn and cy - size / 2 + px * 0.08 * k / K.sc or cy
    if q then G.draw(img, q, K.X(cx), K.Y(y), turn or 0, k, k, px / 2, hang)
    else G.draw(img, K.X(cx), K.Y(y), turn or 0, k, k, px / 2, hang) end
  end
  -- a big Poké Ball's outline turning slowly (the pane's watermark)
  local function ballMark(cx, cy, r, turn, a)
    local pr = r * K.sc
    G.push()
    G.translate(K.X(cx), K.Y(cy))
    G.rotate(turn)
    K.col(C.white, a)
    G.setLineWidth(max(1, r * 0.11 * K.sc))
    G.circle("line", 0, 0, pr)
    G.line(-pr, 0, -pr * 0.36, 0)
    G.line(pr * 0.36, 0, pr, 0)
    G.circle("line", 0, 0, pr * 0.3)
    G.circle("fill", 0, 0, pr * 0.14)
    G.pop()
  end
  local function rays(cx, cy, r, clock, c, a)
    G.push()
    G.translate(K.X(cx), K.Y(cy))
    G.rotate(clock * 0.5)
    K.col(c, a)
    local rr = r * K.sc
    for i = 0, 7 do
      local t = i * pi / 4
      G.polygon("fill", 0, 0, cos(t) * rr, sin(t) * rr, cos(t + 0.3) * rr, sin(t + 0.3) * rr)
    end
    G.pop()
  end

  -- ------- the list: a pane of glass, the highlight gliding, the rows rising in as it opens
  local function drawList(x, y, w, h, clock, dt)
    st.visible = max(1, floor((h - 2) / ROW_H))
    clamp()
    K.glass(K.R(x, y, w, h), 4, 0.55)
    local focused = st.focus == "list"
    -- (smooth to where the D-pad sent it; scrolled by hand, right where the hand left it)
    if st.free then mv.top = st.top else mv.top = K.approach(mv.top, st.top, dt, 20) end
    local top = mv.top
    local psx, psy, psw, psh
    if G.getScissor then psx, psy, psw, psh = G.getScissor() end
    local area = K.R(x, y + 1, w, h - 2)
    K.scissor(area)
    -- (the chosen row's highlight, gliding from row to row)
    if mv.selY == nil then mv.selY = st.cursor else mv.selY = K.approach(mv.selY, st.cursor, dt, 24) end
    local hb = K.R(x + 1.2, y + 1 + (mv.selY - 1 - top) * ROW_H + 0.4, w - 2.4, ROW_H - 0.8)
    if focused then
      K.col(C.accent)
      K.box("fill", hb, 3)
    else
      K.col(C.white, 0.75)
      K.box("fill", hb, 3)
      K.ring(hb, 3, C.white, 0.9, 0.3)
    end
    local since = clock - mv.openAt
    local first = floor(top) + 1
    for i = first, min(#st.rows, first + st.visible) do
      local r = fill(st.rows[i])
      local ry = y + 1 + (i - 1 - top) * ROW_H
      local on = i == st.cursor
      local e = K.outCubic((since - (i - first) * 0.035) / 0.3)
      K.rise(e, 4)
      local ink = (on and focused) and C.white or C.ink
      if env.monIconOf then pcall(env.monIconOf, r.mon, x + 1, ry - 0.5, 11, nil, K.getFade()) end
      local count = numText(r.count)
      local pw = max(7, K.width(count, 4) + 4)
      local name = r.info and r.info.name or "?"
      K.text(name, x + 13, ry + 3, K.fit(name, 4.6, w - 18 - pw), ink)
      local pill = K.R(x + w - pw - 3, ry + 2.3, pw, 6.4)
      K.grad(pill, 3.2, C.goldTop, C.goldDark)
      K.ring(pill, 3.2, C.white, 0.6, 0.3)
      K.bold(count, pill[1], pill[2] + 0.9, 4, C.goldInk, "center", pw)
      if i > first and not on and i - 1 ~= st.cursor then K.hairline(x + 13, ry, w - 15) end
      K.addHit(K.R(x, ry, w, ROW_H), "win", i, area)
      K.settle(e)
    end
    if psx then G.setScissor(psx, psy, psw, psh) else G.setScissor() end
    K.scrollbar(x + w, y + 1, h - 2, top, st.visible, #st.rows)
  end

  -- the five contests: a word and four pips, one for each rank won, lighting up one after another
  local function drawTracks(r, x, y, w, rowH, since)
    for i = 1, 5 do
      local ry = y + (i - 1) * rowH
      local word = T(CAT_NAME[i])
      K.label(word, x, ry + 0.2, K.fit(word, 3.2, w * 0.5), C.white, nil, nil, 0.9 * K.getFade())
      local pw = 4.2
      for p = 1, 4 do
        local px = x + w - (5 - p) * (pw + 0.8)
        local pb = K.R(px, ry + 1, pw, 2.6)
        K.col(C.pipOff)
        K.box("fill", pb, 1.2)
        if p <= r.contest[i] then
          local e = K.outCubic((since - (i + p) * 0.04) / 0.22)
          if e > 0 then
            K.col(CAT[i], e)
            K.box("fill", K.R(px, ry + 1, pw * e, 2.6), 1.2)
          end
        end
      end
    end
  end

  -- the chosen one: its pane, its picture, its words and ranks
  local function hero(r, x, y, w, h, clock)
    local b = K.R(x, y, w, h)
    K.shadow(b, 5, 1.4, 0.1)
    G.setColor(mv.r2, mv.g2, mv.b2, 0.74 * K.getFade())
    K.box("fill", b, 5)
    K.grad(b, 5, SHADE_TOP, SHADE_FOOT)
    K.ring(b, 5, C.white, 0.6, 0.4)
    G.intersectScissor(K.X(x), K.Y(y), w * K.sc, h * K.sc)
    ballMark(x + w - h * 0.4, y + h * 0.62, h * 0.72, clock * 0.18, 0.13)
    K.scissor(bodyNow)
    local t = clock - mv.recAt
    local pop = 0.8 + 0.2 * K.outBack(t / 0.42)
    local fa = K.outCubic(t / 0.18) * K.getFade()
    local ps = min(h - 4, 30)
    local pcx, pcy = x + 2.5 + ps / 2, y + h / 2
    K.glow(pcx, pcy, ps * 0.6, ps * 0.5, C.white, 0.24 * fa)
    K.col(C.black, 0.2 * fa)
    G.ellipse("fill", K.X(pcx), K.Y(pcy + ps * 0.43), ps * 0.27 * pop * K.sc, ps * 0.06 * K.sc)
    local info = r.info
    if info then
      if info.egg or not env.dexSprite then
        if env.monPic then pcall(env.monPic, info.species, pcx - ps / 2 * pop, pcy - ps / 2 * pop, ps * pop, fa, r.mon) end
      else
        pcall(env.dexSprite.draw, info.species, pcx, pcy, ps, clock, mv.recAt, pop, fa, info.shiny == true, r.mon)
      end
      K.rescissor()
    end
    -- (its words sliding in after it; the ranks at the right, room allowing)
    local tracksW = w >= 96 and min(42, w * 0.34) or 0
    local tx = x + ps + 5
    local room = x + w - tx - tracksW - (tracksW > 0 and 5 or 3)
    local f0 = K.getFade()
    local e1 = K.outCubic((t - 0.04) / 0.32)
    local e2 = K.outCubic((t - 0.1) / 0.32)
    local name = info and info.name or "?"
    local fs = K.fit(name, 5.4, room)
    -- (the lines apart as the text grows, the pill taller: nothing at 100%)
    local gs = K.textScale() - 1
    local ty = y + max(2, (h - 21 - gs * 11) / 2)
    K.label(name, tx + (1 - e1) * 8, ty, fs, C.white, nil, nil, e1 * f0)
    K.label(r.whereText, tx + (1 - e2) * 8, ty + 7 + gs * 4, K.fit(r.whereText, 3.8, room), C.white, nil, nil,
      0.85 * e2 * f0)
    -- (the count on a gold pill)
    local cw = K.width(r.countText, 3.8) + 5
    local cb = K.R(tx + (1 - e2) * 8, ty + 12.6 + gs * 7, min(cw, room), 5.8 + gs * 3.8)
    K.setFade(f0 * e2)
    K.grad(cb, 2.9, C.goldTop, C.goldDark)
    K.ring(cb, 2.9, C.white, 0.6, 0.3)
    K.bold(r.countText, cb[1], cb[2] + 0.6 + gs * 1.9, K.fit(r.countText, 3.8, cb[3] - 3), C.goldInk, "center", cb[3])
    K.setFade(f0)
    if tracksW > 0 then
      local rowH = min(5.5, (h - 4) / 5)
      drawTracks(r, x + w - tracksW - 3, y + (h - rowH * 5) / 2, tracksW, rowH, t)
    end
  end

  -- the case: the Ribbons on glass, rising in as the Pokémon is shown, the highlight gliding between them
  local function drawCase(r, x, y, w, h, clock, dt)
    K.glass(K.R(x, y, w, h), 4, 0.42)
    local cs = min((w - 5) / PER_ROW, 14, (h - 3) / max(1, r.rows))
    local gx = x + (w - cs * PER_ROW) / 2
    local gy = y + 1.5
    if st.pick > #r.items then st.pick = 1 end
    local p = st.pick
    -- (the chosen one's pane, gliding)
    if r.items[p] then
      local hx = gx + r.colOf[p] * cs
      local hy = gy + r.rowOf[p] * cs + (r.rowOf[p] >= r.giftRow and 0.8 or 0)
      if mv.gx == nil or mv.gs ~= cs then
        mv.gx, mv.gy, mv.gs = hx, hy, cs
      else
        mv.gx, mv.gy = K.approach(mv.gx, hx, dt, 26), K.approach(mv.gy, hy, dt, 26)
      end
      local hb = K.R(mv.gx + 0.3, mv.gy + 0.3, cs - 0.6, cs - 0.6)
      K.col(C.white, st.focus == "grid" and 0.8 or 0.5)
      K.box("fill", hb, 2)
      K.ring(hb, 2, st.focus == "grid" and C.accent or C.white, st.focus == "grid" and 0.6 + 0.4 * K.pulse() or 0.8, 0.6)
    end
    if r.giftRow < r.rows and r.giftRow > 0 then
      K.hairline(x + 4, gy + r.giftRow * cs + 0.4, w - 8, C.white, 0.8)
    end
    local since = clock - mv.recAt
    local pt = clock - mv.pickAt
    for i = 1, #r.items do
      local cx = gx + r.colOf[i] * cs + cs / 2
      local cy = gy + r.rowOf[i] * cs + cs / 2 + (r.rowOf[i] >= r.giftRow and 0.8 or 0)
      local id = r.items[i]
      local on = i == p
      local e = K.outCubic((since - i * 0.018) / 0.28)
      K.rise(e, 3)
      K.glow(cx, cy, cs * (on and 0.8 or 0.5), cs * (on and 0.8 or 0.5), colorOf(id), on and 0.32 or 0.14)
      local k = 0.88
      if on and pt >= 0 and pt < POP then k = 0.88 + 0.32 * sin(pt / POP * pi) end
      drawIcon(id, cx, cy, cs * k, false)
      K.addHit(K.R(cx - cs / 2, cy - cs / 2, cs, cs), "win", RIBBON + i)
      K.settle(e)
    end
  end

  -- the chosen Ribbon in the spotlight: swinging, its words sliding in
  local function drawSpot(r, x, y, w, h, clock)
    local id = r.items[st.pick]
    K.glass(K.R(x, y, w, h), 4, 0.6)
    if not id then return end
    local cx, cy = x + 11, y + h / 2
    local c = colorOf(id)
    local t = clock - mv.pickAt
    local e = K.outCubic(t / 0.3)
    G.intersectScissor(K.X(x), K.Y(y), w * K.sc, h * K.sc)
    rays(cx, cy, 13, clock, c, 0.2 * e)
    K.glow(cx, cy, 12, 11, c, 0.45 * e)
    local s = min(16.5, h - 3) * (0.8 + 0.2 * K.outBack(t / 0.4))
    drawIcon(id, cx, cy, s, true, sin(clock * 2.2) * 0.1)
    -- (a shine crossing the words now and then: the rest of the time it waits past the pane's edge, clipped)
    K.col(C.white, 0.35)
    K.box("fill", K.R(x + 20 + (w - 16) * min(1.1, (clock % 5) / 1.2), y + 1, 5, h - 2), 1)
    K.scissor(bodyNow)
    local f0 = K.getFade()
    local fs = h < 18 and 3.4 or 3.8
    local words = r.descs[st.pick]
    K.text(words, x + 23 + (1 - e) * 6, y + 2.5, paraFit(descFit, words, fs, w - 26, h - 3), C.ink, "left", w - 26, e * f0)
  end

  local function drawDetail(x, y, w, h, clock, dt)
    local r = current()
    if not r then return end
    local heroH = h >= 90 and 34 or 26
    local spotH = h >= 90 and 22 or 18
    local open = K.outCubic((clock - mv.openAt) / 0.4)
    K.rise(open, 6)
    hero(r, x, y, w, heroH, clock)
    K.settle(open)
    local caseY = y + heroH + GAP
    local caseH = h - heroH - spotH - GAP * 2
    local o2 = K.outCubic((clock - mv.openAt - 0.06) / 0.4)
    K.rise(o2, 7)
    drawCase(r, x, caseY, w, caseH, clock, dt)
    K.settle(o2)
    local o3 = K.outCubic((clock - mv.openAt - 0.12) / 0.4)
    K.rise(o3, 7)
    drawSpot(r, x, caseY + caseH + GAP, w, spotH, clock)
    K.settle(o3)
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    G = K.graphics()
    bodyNow = body
    local dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT = clock
    if not mv.openAt then mv.openAt = clock end
    local r = current()
    -- (what changed since the last frame starts its motion: another Pokémon, another Ribbon)
    if r ~= mv.rec then
      mv.rec, mv.recAt = r, clock
      mv.gx = nil
      if r and r.info and not r.info.egg and env.dexSprite then
        pcall(env.dexSprite.start, r.info.species, r.info.shiny == true)
      end
    end
    if st.pick ~= mv.pick or mv.pickAt < mv.recAt then mv.pick, mv.pickAt = st.pick, clock end
    -- (the lights: the chosen Ribbon's colour and the Pokémon's type, slate while there's none; eased)
    local id = r and r.items[st.pick]
    local c1 = id and colorOf(id) or C.slate
    local tp = r and r.info and r.info.types and r.info.types[1]
    local c2 = tp and TYPE[tp.id] or C.slate2
    local rate = mv.coloured and 8 or 1000
    mv.coloured = true
    mv.r, mv.g, mv.b = K.approach(mv.r, c1[1] / 255, dt, rate), K.approach(mv.g, c1[2] / 255, dt, rate),
      K.approach(mv.b, c1[3] / 255, dt, rate)
    mv.r2, mv.g2, mv.b2 = K.approach(mv.r2, c2[1] / 255, dt, rate), K.approach(mv.g2, c2[2] / 255, dt, rate),
      K.approach(mv.b2, c2[3] / 255, dt, rate)
    K.backdrop(body, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2)
    if #st.rows == 0 then
      ballMark(x + w / 2, y + h / 2 - 6, min(w, h) * 0.18, clock * 0.18, 0.5)
      K.text(T("ribbons.none"), x + 6, y + h / 2 + min(w, h) * 0.18 - 2, 4.6, C.soft, "center", w - 12)
      K.scissor(body)
      return
    end
    if portrait then
      local dh = min(h * 0.62, 130)
      drawDetail(x + M, y + M, w - M * 2, dh, clock, dt)
      local o = K.outCubic((clock - mv.openAt - 0.16) / 0.4)
      K.rise(o, 7)
      drawList(x + M, y + M + dh + GAP, w - M * 2, h - dh - M * 2 - GAP, clock, dt)
      K.settle(o)
    else
      local lw = floor((w - M * 3) * 0.36)
      drawList(x + M, y + M, lw, h - M * 2, clock, dt)
      drawDetail(x + M * 2 + lw, y + M, w - M * 3 - lw, h - M * 2, clock, dt)
    end
    K.scissor(body)
  end

  return W
end
