-- The Boxes window's drawing (src/apps/boxes.lua keeps the state and the input): the party column,
-- the box (its name, its wallpaper, 6 x 5 Pokémon), the modes' switch and the count, the preview card,
-- the carried Pokémon (at the cursor or the pointer, where they'd land ringed green or red), and the
-- sheets. Fills st.geo with the layout's numbers for the pointer. No tables made per frame.
-- The Pokédex's glass: panes over a backdrop of soft lights in the previewed Pokémon's type colours
-- (eased as it changes). Its motion, numbers kept here: the party and the box's Pokémon rise in one after
-- another as it opens, and the box's when it turns (sliding in from the side it turned to, its name
-- with them); the cursor's highlight glides from cell to cell; the modes' thumb slides; the preview's
-- picture pops up and its words slide in as another Pokémon is shown; a sheet pops up.
--
--   view = boxesView(K, env, T, Bx, st, A) -> { draw(body, clock, portrait, previewMon, modeColor,
--       modeName), modeColor = { select, swap, drag }, C }

local floor, max, min, abs, exp, sin, pi = math.floor, math.max, math.min, math.abs, math.exp, math.sin, math.pi

local function clamp01(t) return t < 0 and 0 or (t > 1 and 1 or t) end
local function outCubic(t)
  t = clamp01(t)
  local u = 1 - t
  return 1 - u * u * u
end
local function outBack(t)
  t = clamp01(t)
  local u = t - 1
  return 1 + 2.70158 * u * u * u + 1.70158 * u * u
end
-- (the modes' switch: the k-th segment's left, the one in use `onW` wide, the others `offW`)
local function segX(x, m, onW, offW, k)
  local sx = x
  for j = 1, k - 1 do sx = sx + (j == m and onW or offW) end
  return sx
end
-- (a value followed smoothly, the same speed whatever the frame rate)
local function approach(cur, target, dt, rate)
  local v = cur + (target - cur) * (1 - exp(-dt * rate))
  if abs(target - v) < 0.002 then return target end
  return v
end

-- the sparkle's star, radius 1 round 0, 0: four points, the sides curving in between them
-- (|x|^0.625 + |y|^0.625 = 1), and its three stars in a square of 1 (centre x, y, radius)
local STAR_N = 48
local STAR_X, STAR_Y = {}, {}
for i = 1, STAR_N do
  local t = (i - 1) / STAR_N * 2 * math.pi
  local c, n = math.cos(t), math.sin(t)
  STAR_X[i] = (c < 0 and -1 or 1) * abs(c) ^ 3.2
  STAR_Y[i] = (n < 0 and -1 or 1) * abs(n) ^ 3.2
end
local CLUSTER = { { 0.3, 0.3, 0.3 }, { 0.76, 0.5, 0.24 }, { 0.42, 0.78, 0.22 } }
local starMesh

-- (the system colours of the kit's K.UI, the macOS / iOS look every window shares)
local C = {
  ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, faint = { 162, 162, 170 }, card = { 255, 255, 255 },
  bad = { 255, 59, 48 }, good = { 52, 199, 89 }, accent = { 10, 132, 255 },
  red = { 255, 69, 58 }, blue = { 10, 132, 255 }, green = { 52, 199, 89 },
  hpGood = { 52, 199, 89 }, hpMid = { 255, 204, 0 }, hpLow = { 255, 59, 48 }, hpBack = { 118, 118, 128, 0.2 },
  male = { 10, 132, 255 }, female = { 255, 55, 95 }, shiny = { 255, 190, 30 }, picBack = { 242, 242, 247 },
  -- Dynamax (WoobleDex's): the level's segments, the empty ones, the G-Max badge
  dmax = { 255, 140, 24 }, dmaxEmpty = { 118, 118, 128, 0.28 }, gmax = { 214, 28, 64 },
  white = { 255, 255, 255 }, black = { 0, 0, 0 }, track = { 118, 118, 128, 0.16 },
  slate = { 120, 132, 178 }, slate2 = { 150, 120, 190 },
}
-- the box's corners (units)
local BOX_R = 3.5
-- the type pills (the game's type ids)
local TYPE = {
  [0] = { 168, 168, 120 }, [1] = { 192, 48, 40 }, [2] = { 168, 144, 240 }, [3] = { 160, 64, 160 },
  [4] = { 224, 192, 104 }, [5] = { 184, 160, 56 }, [6] = { 168, 184, 32 }, [7] = { 112, 88, 152 },
  [8] = { 184, 184, 208 }, [9] = { 104, 160, 144 }, [10] = { 240, 128, 48 }, [11] = { 104, 144, 240 },
  [12] = { 120, 200, 80 }, [13] = { 248, 208, 48 }, [14] = { 248, 88, 136 }, [15] = { 152, 216, 216 },
  [16] = { 112, 56, 248 }, [17] = { 112, 88, 72 }, [18] = { 238, 153, 172 },
}
-- a wallpaper the game's pictures can't show: tints
local WALL_TINT = {
  { { 120, 196, 120 }, { 70, 140, 90 } }, { { 140, 170, 220 }, { 90, 110, 170 } },
  { { 232, 200, 130 }, { 196, 150, 90 } }, { { 210, 190, 140 }, { 160, 140, 96 } },
  { { 180, 170, 160 }, { 120, 110, 104 } }, { { 236, 130, 90 }, { 170, 70, 60 } },
  { { 220, 236, 250 }, { 160, 190, 220 } }, { { 150, 130, 110 }, { 90, 76, 70 } },
}
local HEAD_H = 10
-- (the room between the header and the box, and beside it, for the bezel)
local GAP = 3

return function(K, env, T, Bx, st, A)
  local V = { C = C, modeColor = { C.red, C.blue, C.green } }
  local countText = K.textCache(function(n) return tostring(n) .. "/" .. Bx.SLOTS end)
  local function session() return env.session and env.session() end

  -- the motion's numbers (see the top)
  local mv = {
    openAt = nil, boxAt = -10, box = nil, boxDir = 0, gx = nil, gy = nil, px = nil, py = nil, mode = 1,
    mon = nil, monAt = -10, sheet = nil, sheetAt = -10, lastT = nil, clock = 0, dt = 0,
    r = 0.6, g = 0.6, b = 0.6, r2 = 0.6, g2 = 0.6, b2 = 0.6, coloured = false,
  }
  V.motion = mv
  -- something settling in: `(1 - e) * dy` lower (`dx` across) and at `e` of itself; settle(e) after
  local FADES, depth = {}, 0
  local function rise(e, dy, dx)
    if e >= 1 then return end
    local G = K.graphics()
    depth = depth + 1
    FADES[depth] = K.getFade()
    K.setFade(FADES[depth] * e)
    G.push()
    G.translate((1 - e) * (dx or 0) * K.sc, (1 - e) * dy * K.sc)
  end
  local function settle(e)
    if e >= 1 then return end
    K.setFade(FADES[depth])
    depth = depth - 1
    K.graphics().pop()
  end
  -- (the i-th of a group rising in, `since` seconds after it started)
  local function stagger(since, i, each, dur) return since < 2 and outCubic((since - i * each) / dur) or 1 end

  local sparkle
  -- a Pokémon's icon, `size` units square
  local function icon(mon, x, y, size, frame, a)
    if env.monIconOf then pcall(env.monIconOf, mon, x, y, size, frame, (a or 1) * K.getFade()) end
  end
  -- a shiny's gold sparkle in the top right of its cell (bx, by, bs units square; the white edge
  -- included), the game's icons having no shiny colours
  local function mark(mon, bx, by, bs)
    if not Bx.shiny(mon) then return end
    local s, m = bs * 0.46, bs * 0.05
    sparkle(K.graphics(), bx + bs - m - s * 1.06, by + m + s * 0.07, s, true)
  end
  local function wallpaper(id, x, y, w, h)
    if env.boxWall then
      local ok, drawn = pcall(env.boxWall, id, x, y, w, h)
      if ok and drawn then return end
    end
    local t = WALL_TINT[((tonumber(id) or 1) - 1) % #WALL_TINT + 1]
    K.grad(K.R(x, y, w, h), 2, t[1], t[2])
  end

  -- ------- small pieces

  local function hpBar(mon, x, y, w)
    local hp, mx = tonumber(mon.hp) or 0, tonumber(mon.maxHp) or 0
    if mx <= 0 then return end
    local k = max(0, min(1, hp / mx))
    K.col(C.hpBack)
    K.box("fill", K.R(x, y, w, 1.4), 0.7)
    K.col(k > 0.5 and C.hpGood or (k > 0.2 and C.hpMid or C.hpLow))
    K.box("fill", K.R(x, y, w * k, 1.4), 0.7)
  end
  local function genderMark(G, g, x, y, s)
    if not g then return end
    local sc = K.sc
    K.col(g == "M" and C.male or C.female)
    G.setLineWidth(max(1, s * 0.16 * sc))
    local r = s * 0.3
    if g == "M" then
      local cx, cy = x + r, y + s - r
      G.circle("line", K.X(cx), K.Y(cy), r * sc)
      G.line(K.X(cx + r * 0.7), K.Y(cy - r * 0.7), K.X(x + s), K.Y(y))
      G.line(K.X(x + s - s * 0.35), K.Y(y), K.X(x + s), K.Y(y))
      G.line(K.X(x + s), K.Y(y), K.X(x + s), K.Y(y + s * 0.35))
    else
      local cx, cy = x + s / 2, y + r
      G.circle("line", K.X(cx), K.Y(cy), r * sc)
      G.line(K.X(cx), K.Y(cy + r), K.X(cx), K.Y(y + s))
      G.line(K.X(cx - r * 0.8), K.Y(y + s * 0.8), K.X(cx + r * 0.8), K.Y(y + s * 0.8))
    end
  end
  -- the shiny sparkle: three four-pointed stars with pinched, curved sides (a big one at the top
  -- left, two by it), `s` units square at x, y; `halo`: a white edge under them first, to show on
  -- any wallpaper. Each star is a fan from its centre: a kept mesh, or triangles without meshes
  local function star(G, cx, cy, r)
    local sc = K.sc
    local px, py, pr = K.X(cx), K.Y(cy), r * sc
    if starMesh == nil and G.newMesh then
      local verts = { { 0, 0 } }
      for i = 0, STAR_N do verts[#verts + 1] = { STAR_X[i % STAR_N + 1], STAR_Y[i % STAR_N + 1] } end
      local ok, m = pcall(G.newMesh, verts, "fan", "static")
      starMesh = ok and m or false
    end
    if starMesh then return G.draw(starMesh, px, py, 0, pr, pr) end
    for i = 1, STAR_N do
      local j = i % STAR_N + 1
      G.polygon("fill", px, py, px + STAR_X[i] * pr, py + STAR_Y[i] * pr, px + STAR_X[j] * pr, py + STAR_Y[j] * pr)
    end
  end
  function sparkle(G, x, y, s, halo)
    if halo then
      K.col(K.WHITE, 0.95)
      for k = 1, 3 do star(G, x + CLUSTER[k][1] * s, y + CLUSTER[k][2] * s, CLUSTER[k][3] * s * 1.22) end
    end
    K.col(C.shiny)
    for k = 1, 3 do star(G, x + CLUSTER[k][1] * s, y + CLUSTER[k][2] * s, CLUSTER[k][3] * s) end
  end

  -- ------- the party

  local function drawParty(x, y, w, portrait, clock, color)
    local s, g = session(), st.geo
    local party = Bx.party(s)
    if portrait then K.glass(K.R(g.partyX, g.partyY, g.slotW * Bx.PARTY - 1, g.slotH - 1), 4)
    else K.glass(K.R(g.partyX, g.partyY, g.partyW, g.slotH * Bx.PARTY - 1), 4) end
    -- (the cursor's highlight gliding along the party)
    if st.area == "party" and not st.usePtr then
      local tx = portrait and g.partyX + (st.pi - 1) * g.slotW or g.partyX
      local ty = portrait and g.partyY or g.partyY + (st.pi - 1) * g.slotH
      if mv.px == nil then mv.px, mv.py = tx, ty end
      mv.px, mv.py = approach(mv.px, tx, mv.dt, 26), approach(mv.py, ty, mv.dt, 26)
      local hb = portrait and K.R(mv.px, mv.py, g.slotW - 1, g.slotH - 1) or K.R(mv.px, mv.py, g.partyW, g.slotH - 1)
      K.col(C.white, 0.7)
      K.box("fill", hb, 2.5)
      K.ring(hb, 2.5, color, 0.6 + 0.4 * K.pulse(), 0.9)
    else
      mv.px = nil
    end
    local since = clock - (mv.openAt or clock)
    for i = 1, Bx.PARTY do
      local sx, sy, sw, sh
      if portrait then
        sx, sy, sw, sh = g.partyX + (i - 1) * g.slotW, g.partyY, g.slotW - 1, g.slotH - 1
      else
        sx, sy, sw, sh = g.partyX, g.partyY + (i - 1) * g.slotH, g.partyW, g.slotH - 1
      end
      local rb = K.R(sx, sy, sw, sh)
      local mon = party[i]
      if i > 1 and not portrait then K.hairline(sx + 2, sy - 0.5, sw - 4, C.white, 0.7) end
      if i > 1 and portrait then K.vline(sx - 0.5, sy + 2, sh - 4, C.white, 0.7) end
      local ein = stagger(since, i, 0.04, 0.32)
      rise(ein, 5)
      if mon then
        local on = st.area == "party" and st.pi == i
        local frame = on and floor(clock * 4) % 2 or 0
        if portrait then
          local is = min(sw, sh) * 1.05
          icon(mon, sx + (sw - is) / 2, sy + (sh - is) / 2 - 1, is, frame)
          local bs = min(sw, sh)
          mark(mon, sx + sw - bs, sy, bs)
          hpBar(mon, sx + 2, sy + sh - 2.2, sw - 4)
        else
          local is = sh * 1.25
          icon(mon, sx - 1, sy + (sh - is) / 2 - 0.5, is, frame)
          mark(mon, sx + is - 2 - sh, sy, sh)
          local info = Bx.info(mon, T)
          K.bold(info.levelText, sx + is - 1, sy + 1.6, 3.8, C.ink)
          hpBar(mon, sx + is - 1, sy + sh - 3.2, sw - is - 1)
        end
      end
      settle(ein)
      K.addHit(rb, "win", A.PARTY + i)
    end
    if st.rect and st.rect.area == "party" then
      local a, b = min(st.rect.a, st.rect.b), max(st.rect.a, st.rect.b)
      local rb
      if portrait then
        rb = K.R(g.partyX + (a - 1) * g.slotW, g.partyY, (b - a + 1) * g.slotW - 1, g.slotH - 1)
      else
        rb = K.R(g.partyX, g.partyY + (a - 1) * g.slotH, g.partyW, (b - a + 1) * g.slotH - 1)
      end
      K.col(C.green, 0.22)
      K.box("fill", rb, 2.5)
      K.ring(rb, 2.5, C.green, 0.9, 0.7)
    end
  end

  -- ------- the box

  local function drawHead(x, y, w)
    local s, g = session(), st.geo
    local hb = K.R(x, y, w, HEAD_H)
    K.glass(hb, 3)
    if st.area == "head" and not st.usePtr then K.ring(hb, 2.5, V.modeColor[st.mode], K.pulse(), 0.9) end
    g.prev[1], g.prev[2], g.prev[3], g.prev[4] = x, y, 12, HEAD_H
    g.next[1], g.next[2], g.next[3], g.next[4] = x + w - 12, y, 12, HEAD_H
    local hot = st.held and st.usePtr and st.arrow
    for d = -1, 1, 2 do
      local cx = d < 0 and x + 6 or x + w - 6
      if hot == d then
        K.col(C.accent, 0.16)
        K.graphics().circle("fill", K.X(cx), K.Y(y + HEAD_H / 2), 4 * K.sc)
      end
      K.chevron(cx, y + HEAD_H / 2, 4, C.accent, d)
    end
    K.addHit(g.prev, "win", A.PREV)
    K.addHit(g.next, "win", A.NEXT)
    -- (its name sliding in from the side the box turned to)
    local name = Bx.boxName(s, st.box)
    local ns = K.fit(name, 4.8, w - 26)
    local e = outCubic((mv.clock - mv.boxAt) / 0.3)
    local G = K.graphics()
    G.push()
    G.translate((1 - e) * mv.boxDir * 10 * K.sc, 0)
    K.bold(name, x + 12, y + 2.4 + (4.8 - ns) * 0.5, ns, C.ink, "center", w - 24, e)
    G.pop()
    K.addHit(K.R(x + 12, y, w - 24, HEAD_H), "win", A.NAME)
  end

  -- the box's bezel: a pane of glass round the wallpaper (its corners under the glass's rounded edge)
  local function boxFrame(x, y, w, h)
    K.ring(K.R(x - 1.2, y - 1.2, w + 2.4, h + 2.4), BOX_R + 1.2, C.white, 0.85, 2.2)
    K.ring(K.R(x - 2.5, y - 2.5, w + 5, h + 5), BOX_R + 2.5, C.white, 0.5, 0.4)
    K.ring(K.R(x - 0.1, y - 0.1, w + 0.2, h + 0.2), BOX_R, C.black, 0.12, 0.3)
    K.col(K.WHITE, 0.55)
    K.box("fill", K.R(x + BOX_R, y - 1.9, w - BOX_R * 2, 0.5), 0.25)
  end

  local function drawGrid(clock, color)
    local s, g = session(), st.geo
    local gx, gy, cell = g.gx, g.gy, g.cell
    wallpaper(Bx.wallpaper(s, st.box), gx, gy, cell * Bx.COLS, cell * Bx.ROWS)
    boxFrame(gx, gy, cell * Bx.COLS, cell * Bx.ROWS)
    local mons = Bx.boxMons(s, st.box) or {}
    local is = cell * 1.3
    -- (the cursor's highlight: a pane of glass gliding from cell to cell, under the Pokémon)
    if st.area == "box" and not st.usePtr then
      local tx, ty = gx + (st.bi - 1) % Bx.COLS * cell, gy + floor((st.bi - 1) / Bx.COLS) * cell
      if mv.gx == nil then mv.gx, mv.gy = tx, ty end
      mv.gx, mv.gy = approach(mv.gx, tx, mv.dt, 28), approach(mv.gy, ty, mv.dt, 28)
      local hb = K.R(mv.gx + 0.4, mv.gy + 0.4, cell - 0.8, cell - 0.8)
      K.col(C.white, 0.42)
      K.box("fill", hb, 2)
      K.ring(hb, 2, color, 0.6 + 0.4 * K.pulse(), 0.9)
    else
      mv.gx = nil
    end
    -- (rising in one after another as the box opens or turns, from the side it turned to)
    local since = clock - max(mv.boxAt, mv.openAt or clock)
    for i = 1, Bx.SLOTS do
      local c, r = (i - 1) % Bx.COLS, floor((i - 1) / Bx.COLS)
      local cx, cy = gx + c * cell, gy + r * cell
      local mon = mons[i]
      local on = st.area == "box" and st.bi == i
      if mon then
        local order = mv.boxDir < 0 and (Bx.COLS - 1 - c) + r or c + r
        local ein = stagger(since, order, 0.03, 0.3)
        rise(ein, mv.boxDir == 0 and 5 or 0, mv.boxDir * 8)
        local hover = on or (st.usePtr and st.hoverArea == "box" and st.hoverIdx == i)
        icon(mon, cx + (cell - is) / 2, cy + (cell - is) / 2 - 1, is, hover and floor(clock * 4) % 2 or 0)
        mark(mon, cx, cy, cell)
        settle(ein)
      end
      K.addHit(K.R(cx, cy, cell, cell), "win", A.BOX + i)
    end
    if st.rect and st.rect.area == "box" then
      local c1, r1 = (st.rect.a - 1) % Bx.COLS, floor((st.rect.a - 1) / Bx.COLS)
      local c2, r2 = (st.rect.b - 1) % Bx.COLS, floor((st.rect.b - 1) / Bx.COLS)
      local rb = K.R(gx + min(c1, c2) * cell, gy + min(r1, r2) * cell, (abs(c2 - c1) + 1) * cell,
        (abs(r2 - r1) + 1) * cell)
      K.col(C.green, 0.22)
      K.box("fill", rb, 2)
      K.ring(rb, 2, C.green, 0.9, 0.7)
    end
  end

  -- a mode's icon, `s` units across at cx, cy: Select a Poké Ball's outline, Swap two arrows going
  -- round, Drag a selection's rounded corners
  local BRACKETS = { { -1, -1, 1 }, { 1, -1, 1.5 }, { 1, 1, 0 }, { -1, 1, 0.5 } }
  local function arrowHead(G, x, y, rho, th, len)
    local px, py = x + rho * math.cos(th), y + rho * math.sin(th)
    local tx, ty = -math.sin(th), math.cos(th)
    local nx, ny = math.cos(th), math.sin(th)
    G.line(px, py, px - tx * len + nx * len * 0.7, py - ty * len + ny * len * 0.7)
    G.line(px, py, px - tx * len - nx * len * 0.7, py - ty * len - ny * len * 0.7)
  end
  local function modeIcon(G, m, cx, cy, s, col, a)
    local sc = K.sc
    local x, y, r = K.X(cx), K.Y(cy), s * 0.5 * sc
    K.col(col, a)
    G.setLineWidth(max(1, s * 0.12 * sc))
    if m == 1 then
      G.circle("line", x, y, r * 0.88)
      G.line(x - r * 0.88, y, x - r * 0.3, y)
      G.line(x + r * 0.3, y, x + r * 0.88, y)
      G.circle("line", x, y, r * 0.28)
    elseif m == 2 then
      local rho = r * 0.72
      G.arc("line", "open", x, y, rho, math.pi * 1.12, math.pi * 1.88)
      G.arc("line", "open", x, y, rho, math.pi * 0.12, math.pi * 0.88)
      arrowHead(G, x, y, rho, math.pi * 1.88, r * 0.38)
      arrowHead(G, x, y, rho, math.pi * 0.88, r * 0.38)
    else
      local d, q, l = r * 0.86, r * 0.34, r * 0.3
      for i = 1, 4 do
        local b = BRACKETS[i]
        local ax, ay = x + b[1] * (d - q), y + b[2] * (d - q)
        G.arc("line", "open", ax, ay, q, b[3] * math.pi, (b[3] + 0.5) * math.pi)
        G.line(x + b[1] * d, ay, x + b[1] * d, ay - b[2] * l)
        G.line(ax, y + b[2] * d, ax - b[1] * l, y + b[2] * d)
      end
    end
  end
  V.modeIcon = modeIcon

  -- the modes under the box: a glass switch of three, its thumb in the mode's colour sliding to the one
  -- in use (its icon and name; a tap on it goes on to the next), the other two their icons (a tap picks
  -- one); the box's count on the right
  local function drawFoot(x, y, w, color, modeName)
    local G = K.graphics()
    local m = st.mode
    mv.mode = approach(mv.mode, m, mv.dt, 18)
    local lw = K.width(modeName, 4.2)
    local onW = min(w * 0.42, lw + 14)
    local offW = 10
    local tw = onW + offW * 2
    local tb = K.R(x, y, tw, 9)
    K.col(C.white, 0.32)
    K.box("fill", tb, 4.5)
    K.ring(tb, 4.5, C.white, 0.7, 0.3)
    -- (the thumb between the segments' places as it slides)
    local k0 = max(1, min(3, floor(mv.mode)))
    local k1 = min(3, k0 + 1)
    local f = mv.mode - k0
    local thX = segX(x, m, onW, offW, k0) + (segX(x, m, onW, offW, k1) - segX(x, m, onW, offW, k0)) * f
    local mc = V.modeColor[m]
    K.col(C.black, 0.1)
    K.box("fill", K.R(thX + 0.5, y + 0.9, onW - 1, 8), 4)
    K.col(mc)
    K.box("fill", K.R(thX + 0.5, y + 0.5, onW - 1, 8), 4)
    for k = 1, 3 do
      local sx = segX(x, m, onW, offW, k)
      if k == m then
        modeIcon(G, k, sx + 5.2, y + 4.5, 5.6, K.WHITE, 1)
        K.text(modeName, sx + 9.6, y + 2.2, K.fit(modeName, 4.2, onW - 11.5), K.WHITE)
        K.addHit(K.R(sx, y, onW, 9), "win", A.MODE + m % 3 + 1)
      else
        modeIcon(G, k, sx + offW / 2, y + 4.5, 6, V.modeColor[k], 1)
        K.addHit(K.R(sx, y, offW, 9), "win", A.MODE + k)
      end
    end
    local n = Bx.count(session(), st.box)
    K.text(countText(n), x + w - 24, y + 2.2, 4.4, C.soft, "right", 24)
  end

  -- ------- where the carried Pokémon would land: green when they fit, red when not

  local fitHeld, fitArea, fitIdx, fitBox, fitOk = nil, nil, nil, nil, false
  local function fitsHere()
    local held = st.held
    local idx = st.area == "party" and st.pi or st.bi
    if held ~= fitHeld or st.area ~= fitArea or idx ~= fitIdx or st.box ~= fitBox then
      fitHeld, fitArea, fitIdx, fitBox = held, st.area, idx, st.box
      local addr = st.area == "party" and Bx.addr("party", idx) or (st.area == "box" and Bx.addr("box", idx, st.box))
      fitOk = addr ~= nil and Bx.fits(session(), held, addr) == true
    end
    return fitOk
  end

  local function drawHeld(clock)
    local held = st.held
    if not held then return end
    local g = st.geo
    local cell = g.cell
    local is = cell * 1.3
    local bob = math.sin(clock * 5) * 0.8
    local ox, oy
    if st.usePtr then
      ox, oy = st.px - cell / 2, st.py - cell / 2 - 3
    elseif st.area == "box" then
      ox, oy = g.gx + (st.bi - 1) % Bx.COLS * cell, g.gy + floor((st.bi - 1) / Bx.COLS) * cell - 4
    elseif st.area == "party" then
      if g.portrait then ox, oy = g.partyX + (st.pi - 1) * g.slotW, g.partyY - 3
      else ox, oy = g.partyX + 8, g.partyY + (st.pi - 1) * g.slotH - 3 end
    else
      ox, oy = g.gx + g.cell * 2.5, g.gy - HEAD_H - 4
    end
    -- (with the buttons: the cells they'd take, ringed)
    if not st.usePtr and st.area ~= "head" then
      local ok = fitsHere()
      if st.area == "box" then
        for i = 1, held.n do
          local x, y = g.gx + ((st.bi - 1) % Bx.COLS + held.dx[i]) * cell, g.gy + (floor((st.bi - 1) / Bx.COLS) + held.dy[i]) * cell
          if x < g.gx + cell * Bx.COLS and y < g.gy + cell * Bx.ROWS then
            K.ring(K.R(x + 0.5, y + 0.5, cell - 1, cell - 1), 2, ok and C.green or C.red, 0.95, 0.8)
          end
        end
      end
    end
    for i = 1, held.n do
      local x, y = ox + held.dx[i] * cell, oy + held.dy[i] * cell + bob
      K.col(K.BLACK, 0.18)
      K.graphics().ellipse("fill", K.X(x + cell / 2), K.Y(y + cell + 3), cell * 0.32 * K.sc, cell * 0.1 * K.sc)
      icon(held.mons[i], x + (cell - is) / 2, y + (cell - is) / 2, is, floor(clock * 6) % 2)
      mark(held.mons[i], x, y, cell)
    end
  end

  -- ------- the preview

  -- a labelled line of the card -> the next line's y
  local function previewLine(label, value, tx, ty, tw)
    K.text(label, tx, ty, 3.6, C.faint)
    local lw = K.width(label, 3.6) + 2
    K.text(value, tx + lw, ty, K.fit(value, 3.8, tw - lw), C.ink)
    return ty + 5.4
  end

  -- the Dynamax row: its label and the level as ten segments -> the next line's y
  local function dynamaxLine(level, tx, ty, tw)
    local label = T("boxes.dynamax")
    local ls = K.fit(label, 3.6, tw * 0.5)
    K.text(label, tx, ty, ls, C.faint)
    local gx = tx + K.width(label, ls) + 2
    local seg = min(2.6, (tx + tw - gx) / 10)
    for i = 1, 10 do
      K.col(i <= level and C.dmax or C.dmaxEmpty)
      K.box("fill", K.R(gx + (i - 1) * seg, ty + 0.6, seg - 0.5, 3), 0.6)
    end
    return ty + 5.4
  end
  -- the G-Max badge (the Gigantamax Factor), over the picture's foot
  local function gmaxBadge(cx, by)
    local word = T("boxes.gmax")
    local bw = K.width(word, 3.4) + 5
    local b = K.R(cx - bw / 2, by - 5.5, bw, 5.5)
    K.col(K.WHITE)
    K.box("fill", K.R(b[1] - 0.6, b[2] - 0.6, b[3] + 1.2, b[4] + 1.2), 3.4)
    K.col(C.gmax)
    K.box("fill", b, 2.8)
    K.text(word, b[1], b[2] + 1, 3.4, K.WHITE, "center", bw)
  end

  local function drawPreview(mon, x, y, w, h, horizontal, clock)
    local G = K.graphics()
    local card = K.R(x, y, w, h)
    K.glass(card, 5)
    if not mon then
      K.text(T("boxes.empty"), x, y + h / 2 - 3, 4.6, C.soft, "center", w)
      return
    end
    local info = Bx.info(mon, T)
    K.scissor(card)
    local ps = horizontal and min(h - 6, 40) or min(w - 8, 40)
    local px, py = horizontal and x + 3 or x + (w - ps) / 2, y + 3
    -- (another Pokémon: its picture pops up on a light in its type's colour, its words slide in)
    local t = clock - mv.monAt
    local pop = 0.82 + 0.18 * outBack(t / 0.38)
    local fa = outCubic(t / 0.16)
    local pcx, pcy = px + ps / 2, py + ps / 2
    G.setColor(mv.r, mv.g, mv.b, 0.32 * fa * K.getFade())
    G.circle("fill", K.X(pcx), K.Y(pcy), ps * 0.48 * K.sc)
    K.glow(pcx, pcy, ps * 0.5, ps * 0.45, C.white, 0.3 * fa)
    K.col(C.black, 0.16 * fa)
    G.ellipse("fill", K.X(pcx), K.Y(py + ps * 0.93), ps * 0.26 * pop * K.sc, ps * 0.05 * K.sc)
    local pic = info.pic
    if pic and pic.image then
      -- (a picture smaller than its square -- WoobleSpritePack's on the Game Boy games -- at its bottom
      -- middle; popping up from its feet)
      local box = pic.box or pic.w or 64
      local k = ps * K.sc / box * pop
      G.setColor(1, 1, 1, fa * K.getFade())
      G.draw(pic.image, K.X(pcx) - (pic.w or box) / 2 * k, K.Y(py + ps) - (pic.h or box) * k, 0, k, k)
    end
    if info.gmax then gmaxBadge(px + ps / 2, py + ps - 0.5) end
    local tx, ty, tw
    if horizontal then tx, ty, tw = px + ps + 4, y + 3, w - ps - 10
    else tx, ty, tw = x + 3, py + ps + 1, w - 6 end
    local e1 = outCubic((t - 0.05) / 0.3)
    rise(e1, horizontal and 0 or 4, horizontal and 6 or 0)
    local ns = K.fit(info.name, 5, tw - 8)
    K.bold(info.name, tx, ty, ns, C.ink, horizontal and "left" or "center", tw)
    ty = ty + 6.5
    if not info.egg then
      local lw = K.width(info.levelText, 4.2)
      local lx = horizontal and tx or tx + (tw - lw - 10) / 2
      K.text(info.levelText, lx, ty, 4.2, C.soft)
      if not K.hasSign(info.name) then genderMark(G, info.gender, lx + lw + 2, ty + 0.4, 4) end
      if info.shiny then sparkle(G, lx + lw + 7, ty - 0.3, 5) end
      ty = ty + 6
      -- the types
      local total = 0
      for i = 1, #info.types do total = total + K.width(info.types[i].name, 3.8) + 6 + 1.5 end
      local cx = horizontal and tx or tx + (tw - total + 1.5) / 2
      for i = 1, #info.types do
        local t = info.types[i]
        local pw = K.width(t.name, 3.8) + 6
        K.col(TYPE[t.id] or C.faint)
        K.box("fill", K.R(cx, ty, pw, 6), 3)
        K.text(t.name, cx, ty + 1, 3.8, K.WHITE, "center", pw)
        cx = cx + pw + 1.5
      end
      ty = ty + 8
      local room = floor((y + h - 2 - ty) / 5.4)
      local lines = 0
      if room > lines and info.dmax then lines, ty = lines + 1, dynamaxLine(info.dmax, tx, ty, tw) end
      if room > lines and info.nature then lines, ty = lines + 1, previewLine(T("boxes.nature"), info.nature, tx, ty, tw) end
      if room > lines and info.ability then lines, ty = lines + 1, previewLine(T("boxes.ability"), info.ability, tx, ty, tw) end
      if room > lines then lines, ty = lines + 1, previewLine(T("boxes.held"), info.itemName or T("boxes.noItem"), tx, ty, tw) end
      for i = 1, #info.moves do
        if lines >= room then break end
        lines = lines + 1
        K.text(info.moves[i], tx + 2, ty, K.fit(info.moves[i], 3.8, tw - 2), C.soft)
        ty = ty + 5.4
      end
    end
    settle(e1)
    K.scissor(nil)
  end

  -- ------- the sheets

  local function drawSheetCard(body, sh)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local cw = min(w - 16, sh.kind == "wall" and 132 or 112)
    local title = sh.extra and sh.extra.title or ""
    if sh.kind == "release" then
      -- an alert: the question, Cancel | Release
      local cb = K.R(x + (w - cw) / 2, y + (h - 40) / 2, cw, 40)
      K.sheet(cb, 6)
      K.addHit(cb, "win", -1)
      K.bold(title, cb[1] + 4, cb[2] + 5, K.fit(title, 5.2, cw - 8), C.ink, "center", cw - 8)
      local body2 = T("boxes.releaseBody")
      K.text(body2, cb[1] + 4, cb[2] + 13, K.fit(body2, 4.2, cw - 8), C.soft, "center", cw - 8)
      local bw = (cw - 14) / 2
      for k = 1, 2 do
        local bb = K.R(cb[1] + 5 + (k - 1) * (bw + 4), cb[2] + 26, bw, 10)
        K.button(bb, T(k == 1 and "button.cancel" or "boxes.releaseYes"), k == 2 and "danger" or "gray",
          sh.cursor == k)
        K.addHit(bb, "win", k == 1 and A.NO or A.YES)
      end
      return
    end
    if sh.kind == "wall" then
      local n = sh.extra.count
      local cols = 6
      local tw = (cw - 8 - (cols - 1) * 2) / cols
      local th = tw * 0.8
      local rows = math.ceil(n / cols)
      local ch = 14 + rows * (th + 2) + 2
      local cb = K.R(x + (w - cw) / 2, y + max(2, (h - ch) / 2), cw, min(h - 4, ch))
      K.sheet(cb, 6)
      K.addHit(cb, "win", -1)
      K.bold(title, cb[1], cb[2] + 3.5, 5, C.ink, "center", cw)
      for i = 1, n do
        local c, r = (i - 1) % cols, floor((i - 1) / cols)
        local tx, ty = cb[1] + 4 + c * (tw + 2), cb[2] + 12 + r * (th + 2)
        wallpaper(i, tx, ty, tw, th)
        local tb = K.R(tx, ty, tw, th)
        if i == sh.cursor then K.focusRing(tb, 1.5, 0.6 + 0.4 * K.pulse()) end
        K.addHit(tb, "win", A.WALL + i)
      end
      return
    end
    -- a list: a popover menu (the actions, the box menu) or the boxes to jump to
    local n = #sh.rows
    local vis = max(1, min(n, floor((h - 22) / 10)))
    if sh.cursor > sh.top + vis then sh.top = sh.cursor - vis end
    if sh.cursor <= sh.top then sh.top = sh.cursor - 1 end
    local ch = 14 + vis * 10 + 2
    local cb = K.R(x + (w - cw) / 2, y + (h - ch) / 2, cw, ch)
    K.sheet(cb, 5)
    K.addHit(cb, "win", -1)
    K.bold(title, cb[1] + 4, cb[2] + 3.5, K.fit(title, 5, cw - 8), C.ink, "center", cw - 8)
    K.hairline(cb[1], cb[2] + 11.5, cw)
    local s = session()
    for k = 1, vis do
      local i = sh.top + k
      local label = sh.rows[i]
      if not label then break end
      local rb = K.R(cb[1] + 2, cb[2] + 12.5 + (k - 1) * 10, cw - 4, 10)
      local on = i == sh.cursor
      local danger = sh.kind == "actions" and i == 4
      if on then K.selection(rb, true, 2.5, danger and C.bad or C.accent) end
      if danger and k > 1 and i - 1 ~= sh.cursor then K.hairline(rb[1] + 2, rb[2] - 0.1, rb[3] - 4) end
      local ink = on and K.WHITE or (danger and C.bad or C.ink)
      local right = sh.kind == "jump" and 18 or 0
      K.text(label, rb[1] + 4, rb[2] + 2.4, K.fit(label, 4.8, rb[3] - 8 - right), ink)
      if sh.kind == "jump" then
        K.text(countText(Bx.count(s, i)), rb[1] + rb[3] - 22, rb[2] + 2.6, 4.2, on and K.WHITE or C.soft, "right", 18)
      end
      K.addHit(rb, "win", A.ROW + i - 1)
    end
    K.scrollbar(cb[1] + cw, cb[2] + 12.5, vis * 10, sh.top, vis, n)
  end
  -- (the dim, then the card popping up over it)
  local function drawSheet(body)
    local sh = st.sheet
    if not sh then return end
    local e = outCubic((mv.clock - mv.sheetAt) / 0.22)
    K.dim(body, 0.22 * e)
    K.addHit(body, "win", A.DIM)
    rise(e, 6)
    drawSheetCard(body, sh)
    settle(e)
  end

  -- ------- the whole window

  function V.draw(body, clock, portrait, mon, color, modeName)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local g = st.geo
    g.portrait = portrait
    -- (what changed since the last frame starts its motion)
    local dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT, mv.clock, mv.dt = clock, clock, dt
    if not mv.openAt then mv.openAt = clock end
    if mv.box ~= st.box then
      if mv.box ~= nil then
        local d = st.box - mv.box
        if abs(d) > Bx.BOXES / 2 then d = -d end
        mv.boxAt, mv.boxDir = clock, d > 0 and 1 or -1
      end
      mv.box = st.box
    end
    if mon ~= mv.mon then mv.mon, mv.monAt = mon, clock end
    if st.sheet ~= mv.sheet then mv.sheet, mv.sheetAt = st.sheet, clock end
    -- (the backdrop's lights: the previewed Pokémon's types, eased; kept while no Pokémon is shown)
    local info = mon and Bx.info(mon, T)
    if info or not mv.coloured then
      local t1 = info and not info.egg and info.types[1] and TYPE[info.types[1].id] or nil
      local t2 = t1 and (info.types[2] and TYPE[info.types[2].id] or t1) or C.slate2
      t1 = t1 or C.slate
      local rate = mv.coloured and 6 or 1000
      mv.coloured = true
      mv.r, mv.g, mv.b = approach(mv.r, t1[1] / 255, dt, rate), approach(mv.g, t1[2] / 255, dt, rate),
        approach(mv.b, t1[3] / 255, dt, rate)
      local k2 = t2 == t1 and 0.35 or 0
      mv.r2 = approach(mv.r2, (t2[1] + (255 - t2[1]) * k2) / 255, dt, rate)
      mv.g2 = approach(mv.g2, (t2[2] + (255 - t2[2]) * k2) / 255, dt, rate)
      mv.b2 = approach(mv.b2, (t2[3] + (255 - t2[3]) * k2) / 255, dt, rate)
    end
    K.backdrop(body, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2)
    if portrait then
      g.slotW = (w - 6) / Bx.PARTY
      g.slotH = min(20, g.slotW)
      g.partyX, g.partyY, g.partyW = x + 3, y + 2, w - 6
      local headY = g.partyY + g.slotH + 2
      g.cell = min(floor(w / Bx.COLS), 22)
      g.gx, g.gy = x + (w - g.cell * Bx.COLS) / 2, headY + HEAD_H + GAP
      drawParty(x, y, w, true, clock, color)
      drawHead(g.gx, headY, g.cell * Bx.COLS)
      drawGrid(clock, color)
      local footY = g.gy + g.cell * Bx.ROWS + GAP
      drawFoot(g.gx, footY, g.cell * Bx.COLS, color, modeName)
      local py = footY + 11
      if y + h - py > 20 then drawPreview(mon, x + 3, py, w - 6, y + h - py - 3, true, clock) end
    else
      local partyW = 40
      local cell = max(11, min(16, floor((w - partyW - 62 - GAP * 2 - 2) / Bx.COLS)))
      cell = max(9, min(cell, floor((h - HEAD_H - 14 - GAP * 2) / Bx.ROWS)))
      g.cell = cell
      g.partyX, g.partyY, g.partyW = x + 1, y + HEAD_H + 1, partyW - 1
      g.slotH = min(15, (h - HEAD_H - 2) / Bx.PARTY)
      K.bold(T("boxes.party"), x + 1, y + 2.4, 4.6, C.soft, "center", partyW - 1)
      drawParty(x, y, partyW, false, clock, color)
      local bx = x + partyW + GAP + 1
      drawHead(bx, y, cell * Bx.COLS)
      g.gx, g.gy = bx, y + HEAD_H + GAP
      drawGrid(clock, color)
      drawFoot(bx, g.gy + cell * Bx.ROWS + GAP, cell * Bx.COLS, color, modeName)
      local vx = bx + cell * Bx.COLS + GAP + 1
      drawPreview(mon, vx, y + 1, x + w - vx - 1, h - 2, false, clock)
    end
    K.scissor(body)
    drawHeld(clock)
    drawSheet(body)
  end

  return V
end
