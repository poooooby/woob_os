-- The Boxes window's drawing (src/apps/boxes.lua keeps the state and the input): the party column,
-- the box (its name, its wallpaper, 6 x 5 Pokémon), the mode chip and the count, the preview card,
-- the carried Pokémon (at the cursor or the pointer, where they'd land ringed green or red), and the
-- sheets. Fills st.geo with the layout's numbers for the pointer. No tables made per frame.
--
--   view = boxesView(K, env, T, Bx, st, A) -> { draw(body, clock, portrait, previewMon, modeColor,
--       modeName), modeColor = { select, swap, drag }, C }

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local C = {
  ink = { 30, 32, 44 }, soft = { 104, 108, 128 }, faint = { 150, 154, 170 }, card = { 255, 255, 255 },
  slot = { 255, 255, 255, 0.72 }, slotEmpty = { 255, 255, 255, 0.32 }, head = { 238, 240, 245 },
  headFoot = { 226, 229, 236 }, bad = { 220, 62, 74 }, good = { 120, 230, 160 }, accent = { 64, 132, 246 },
  red = { 232, 72, 72 }, blue = { 64, 132, 246 }, green = { 60, 186, 106 }, chip = { 214, 220, 232 },
  hpGood = { 88, 208, 120 }, hpMid = { 240, 196, 60 }, hpLow = { 232, 80, 72 }, hpBack = { 0, 0, 0, 0.18 },
  male = { 64, 132, 246 }, female = { 236, 88, 120 }, shiny = { 250, 196, 40 }, picBack = { 238, 241, 248 },
  dim = { 0, 0, 0 }, sheetRow = { 64, 132, 246 },
  -- the window's own white (the box's rounded corners are cut in it), the box's bezel
  body = { 248, 248, 251 }, bezel = { 204, 208, 218 }, bezelIn = { 146, 152, 168 },
  -- Dynamax (WoobleDex's): the level's segments, the empty ones, the G-Max badge
  dmax = { 255, 140, 24 }, dmaxEmpty = { 214, 218, 228 }, gmax = { 214, 28, 64 },
}
-- the box's corners (units); each corner: which side in x and y, its arc's start and end (half turns)
local BOX_R = 3.5
local CORNERS = { { -1, -1, 1, 1.5 }, { 1, -1, 1.5, 2 }, { 1, 1, 0, 0.5 }, { -1, 1, 0.5, 1 } }
-- the type pills (the game's type ids)
local TYPE = {
  [0] = { 168, 168, 120 }, [1] = { 192, 48, 40 }, [2] = { 168, 144, 240 }, [3] = { 160, 64, 160 },
  [4] = { 224, 192, 104 }, [5] = { 184, 160, 56 }, [6] = { 168, 184, 32 }, [7] = { 112, 88, 152 },
  [8] = { 184, 184, 208 }, [9] = { 104, 160, 144 }, [10] = { 240, 128, 48 }, [11] = { 104, 144, 240 },
  [12] = { 120, 200, 80 }, [13] = { 248, 208, 48 }, [14] = { 248, 88, 136 }, [15] = { 152, 216, 216 },
  [16] = { 112, 56, 248 }, [17] = { 112, 88, 72 },
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

  local function icon(mon, x, y, size, frame, a)
    if env.monIconOf then pcall(env.monIconOf, mon, x, y, size, frame, a) end
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
  local function sparkle(G, x, y, s)
    local sc = K.sc
    K.col(C.shiny)
    G.setLineWidth(max(1, s * 0.18 * sc))
    G.line(K.X(x + s / 2), K.Y(y), K.X(x + s / 2), K.Y(y + s))
    G.line(K.X(x), K.Y(y + s / 2), K.X(x + s), K.Y(y + s / 2))
    G.line(K.X(x + s * 0.2), K.Y(y + s * 0.2), K.X(x + s * 0.8), K.Y(y + s * 0.8))
    G.line(K.X(x + s * 0.8), K.Y(y + s * 0.2), K.X(x + s * 0.2), K.Y(y + s * 0.8))
  end

  -- ------- the party

  local function drawParty(x, y, w, portrait, clock, color)
    local s, g = session(), st.geo
    local party = Bx.party(s)
    for i = 1, Bx.PARTY do
      local sx, sy, sw, sh
      if portrait then
        sx, sy, sw, sh = g.partyX + (i - 1) * g.slotW, g.partyY, g.slotW - 1, g.slotH - 1
      else
        sx, sy, sw, sh = g.partyX, g.partyY + (i - 1) * g.slotH, g.partyW, g.slotH - 1
      end
      local rb = K.R(sx, sy, sw, sh)
      local mon = party[i]
      K.col(mon and C.slot or C.slotEmpty)
      K.box("fill", rb, 2.5)
      if mon then
        local on = st.area == "party" and st.pi == i
        local frame = on and floor(clock * 4) % 2 or 0
        if portrait then
          local is = min(sw, sh) * 1.05
          icon(mon, sx + (sw - is) / 2, sy + (sh - is) / 2 - 1, is, frame)
          hpBar(mon, sx + 2, sy + sh - 2.2, sw - 4)
        else
          local is = sh * 1.25
          icon(mon, sx - 1, sy + (sh - is) / 2 - 0.5, is, frame)
          local info = Bx.info(mon, T)
          K.text(info.levelText, sx + is - 1, sy + 1.6, 3.8, C.ink)
          hpBar(mon, sx + is - 1, sy + sh - 3.2, sw - is - 1)
        end
      end
      if st.area == "party" and st.pi == i and not st.usePtr then K.ring(rb, 2.5, color, K.pulse(), 0.9) end
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
    K.grad(hb, 2.5, C.head, C.headFoot)
    if st.area == "head" and not st.usePtr then K.ring(hb, 2.5, V.modeColor[st.mode], K.pulse(), 0.9) end
    g.prev[1], g.prev[2], g.prev[3], g.prev[4] = x, y, 12, HEAD_H
    g.next[1], g.next[2], g.next[3], g.next[4] = x + w - 12, y, 12, HEAD_H
    local hot = st.held and st.usePtr and st.arrow
    K.text("<", x + 3, y + 2.2, 5, hot == -1 and C.accent or C.soft)
    K.text(">", x + w - 7, y + 2.2, 5, hot == 1 and C.accent or C.soft)
    K.addHit(g.prev, "win", A.PREV)
    K.addHit(g.next, "win", A.NEXT)
    local name = Bx.boxName(s, st.box)
    local ns = K.fit(name, 4.8, w - 26)
    K.text(name, x + 12, y + 2.4 + (4.8 - ns) * 0.5, ns, C.ink, "center", w - 24)
    K.addHit(K.R(x + 12, y, w - 24, HEAD_H), "win", A.NAME)
  end

  -- the box's rounded corners (cut in the window's white over the wallpaper) and its bezel
  local function boxFrame(x, y, w, h)
    local G = K.graphics()
    local R = BOX_R * K.sc
    G.setLineWidth(R * 0.7)
    K.col(C.body)
    for i = 1, 4 do
      local a = CORNERS[i]
      local cx = a[1] < 0 and x + BOX_R or x + w - BOX_R
      local cy = a[2] < 0 and y + BOX_R or y + h - BOX_R
      G.arc("line", "open", K.X(cx), K.Y(cy), R * 1.35, a[3] * math.pi - 0.08, a[4] * math.pi + 0.08)
    end
    K.ring(K.R(x - 1.1, y - 1.1, w + 2.2, h + 2.2), BOX_R + 1.1, C.bezel, 1, 1.6)
    K.ring(K.R(x - 0.25, y - 0.25, w + 0.5, h + 0.5), BOX_R + 0.25, C.bezelIn, 0.9, 0.5)
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
    for i = 1, Bx.SLOTS do
      local c, r = (i - 1) % Bx.COLS, floor((i - 1) / Bx.COLS)
      local cx, cy = gx + c * cell, gy + r * cell
      local mon = mons[i]
      local on = st.area == "box" and st.bi == i
      if mon then
        local hover = on or (st.usePtr and st.hoverArea == "box" and st.hoverIdx == i)
        icon(mon, cx + (cell - is) / 2, cy + (cell - is) / 2 - 1, is, hover and floor(clock * 4) % 2 or 0)
      end
      local cb = K.R(cx, cy, cell, cell)
      if on and not st.usePtr then K.ring(cb, 2, color, K.pulse(), 0.9) end
      K.addHit(cb, "win", A.BOX + i)
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

  -- the modes under the box: the one in use a pill (its icon and name; a tap goes on to the next),
  -- the other two their icons (a tap picks one); the box's count on the right
  local function drawFoot(x, y, w, color, modeName)
    local G = K.graphics()
    local m = st.mode
    local lw = K.width(modeName, 4.4)
    local cw = min(w * 0.55, lw + 15)
    local cb = K.R(x, y, cw, 9)
    K.col(color)
    K.box("fill", cb, 4.5)
    modeIcon(G, m, x + 5.2, y + 4.5, 6, K.WHITE, 1)
    K.text(modeName, x + 10, y + 2.1, K.fit(modeName, 4.4, cw - 12), K.WHITE)
    K.addHit(cb, "win", A.MODE + m % 3 + 1)
    local ix = x + cw + 2
    for k = 1, 2 do
      local other = (m + k - 1) % 3 + 1
      local ib = K.R(ix, y, 9, 9)
      modeIcon(G, other, ix + 4.5, y + 4.5, 6.5, V.modeColor[other], 1)
      K.addHit(ib, "win", A.MODE + other)
      ix = ix + 10
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

  local function drawPreview(mon, x, y, w, h, horizontal)
    local G = K.graphics()
    local card = K.R(x, y, w, h)
    K.col(C.card, 0.94)
    K.box("fill", card, 3)
    if not mon then
      K.text(T("boxes.empty"), x, y + h / 2 - 3, 4.6, C.faint, "center", w)
      return
    end
    local info = Bx.info(mon, T)
    K.scissor(card)
    local ps = horizontal and min(h - 6, 40) or min(w - 8, 40)
    local px, py = horizontal and x + 3 or x + (w - ps) / 2, y + 3
    K.col(C.picBack)
    G.circle("fill", K.X(px + ps / 2), K.Y(py + ps / 2), ps * 0.48 * K.sc)
    local pic = info.pic
    if pic and pic.image then
      local k = ps * K.sc / (pic.w or 64)
      G.setColor(1, 1, 1, 1)
      G.draw(pic.image, K.X(px), K.Y(py), 0, k, k)
    end
    if info.gmax then gmaxBadge(px + ps / 2, py + ps - 0.5) end
    local tx, ty, tw
    if horizontal then tx, ty, tw = px + ps + 4, y + 3, w - ps - 10
    else tx, ty, tw = x + 3, py + ps + 1, w - 6 end
    local ns = K.fit(info.name, 5, tw - 8)
    K.text(info.name, tx, ty, ns, C.ink, horizontal and "left" or "center", tw)
    ty = ty + 6.5
    if not info.egg then
      local lw = K.width(info.levelText, 4.2)
      local lx = horizontal and tx or tx + (tw - lw - 10) / 2
      K.text(info.levelText, lx, ty, 4.2, C.soft)
      genderMark(G, info.gender, lx + lw + 2, ty + 0.4, 4)
      if info.shiny then sparkle(G, lx + lw + 7, ty + 0.4, 4) end
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
    K.scissor(nil)
  end

  -- ------- the sheets

  local function drawSheet(body)
    local sh = st.sheet
    if not sh then return end
    local x, y, w, h = body[1], body[2], body[3], body[4]
    K.col(C.dim, 0.28)
    K.box("fill", body)
    K.addHit(body, "win", A.DIM)
    local cw = min(w - 16, sh.kind == "wall" and 132 or 112)
    local title = sh.extra and sh.extra.title or ""
    if sh.kind == "release" then
      local cb = K.R(x + (w - cw) / 2, y + (h - 40) / 2, cw, 40)
      K.shadow(cb, 4, 1.2, 0.3)
      K.col(C.card)
      K.box("fill", cb, 4)
      K.addHit(cb, "win", -1)
      K.text(title, cb[1] + 4, cb[2] + 4, K.fit(title, 5.2, cw - 8), C.ink, "center", cw - 8)
      local body2 = T("boxes.releaseBody")
      K.text(body2, cb[1] + 4, cb[2] + 12, K.fit(body2, 4.2, cw - 8), C.soft, "center", cw - 8)
      local bw = (cw - 12) / 2
      for k = 1, 2 do
        local bb = K.R(cb[1] + 4 + (k - 1) * (bw + 4), cb[2] + 26, bw, 10)
        local on = sh.cursor == k
        K.col(k == 2 and (on and C.bad or C.chip) or (on and C.accent or C.chip))
        K.box("fill", bb, 5)
        local label = T(k == 1 and "button.cancel" or "boxes.releaseYes")
        K.text(label, bb[1], bb[2] + 2.4, K.fit(label, 4.6, bw - 2), on and K.WHITE or (k == 2 and C.bad or C.ink),
          "center", bw)
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
      K.shadow(cb, 4, 1.2, 0.3)
      K.col(C.card)
      K.box("fill", cb, 4)
      K.addHit(cb, "win", -1)
      K.text(title, cb[1], cb[2] + 3, 5, C.ink, "center", cw)
      for i = 1, n do
        local c, r = (i - 1) % cols, floor((i - 1) / cols)
        local tx, ty = cb[1] + 4 + c * (tw + 2), cb[2] + 12 + r * (th + 2)
        wallpaper(i, tx, ty, tw, th)
        local tb = K.R(tx, ty, tw, th)
        if i == sh.cursor then K.ring(tb, 2, C.accent, K.pulse(), 1) end
        K.addHit(tb, "win", A.WALL + i)
      end
      return
    end
    -- a list
    local n = #sh.rows
    local vis = max(1, min(n, floor((h - 22) / 10)))
    if sh.cursor > sh.top + vis then sh.top = sh.cursor - vis end
    if sh.cursor <= sh.top then sh.top = sh.cursor - 1 end
    local ch = 14 + vis * 10 + 2
    local cb = K.R(x + (w - cw) / 2, y + (h - ch) / 2, cw, ch)
    K.shadow(cb, 4, 1.2, 0.3)
    K.col(C.card)
    K.box("fill", cb, 4)
    K.addHit(cb, "win", -1)
    K.text(title, cb[1] + 4, cb[2] + 3.5, K.fit(title, 5, cw - 8), C.ink, "center", cw - 8)
    local s = session()
    for k = 1, vis do
      local i = sh.top + k
      local label = sh.rows[i]
      if not label then break end
      local rb = K.R(cb[1] + 2, cb[2] + 12 + (k - 1) * 10, cw - 4, 10)
      local on = i == sh.cursor
      local danger = sh.kind == "actions" and i == 4
      if on then
        K.col(danger and C.bad or C.sheetRow)
        K.box("fill", rb, 2.5)
      end
      local ink = on and K.WHITE or (danger and C.bad or C.ink)
      local right = sh.kind == "jump" and 18 or 0
      K.text(label, rb[1] + 4, rb[2] + 2.4, K.fit(label, 4.8, rb[3] - 8 - right), ink)
      if sh.kind == "jump" then
        K.text(countText(Bx.count(s, i)), rb[1] + rb[3] - 22, rb[2] + 2.6, 4.2, on and K.WHITE or C.soft, "right", 18)
      end
      K.addHit(rb, "win", A.ROW + i - 1)
    end
  end

  -- ------- the whole window

  function V.draw(body, clock, portrait, mon, color, modeName)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local g = st.geo
    g.portrait = portrait
    if portrait then
      g.slotW = w / Bx.PARTY
      g.slotH = min(20, g.slotW)
      g.partyX, g.partyY, g.partyW = x, y + 1, w
      local headY = g.partyY + g.slotH + 2
      g.cell = min(floor(w / Bx.COLS), 22)
      g.gx, g.gy = x + (w - g.cell * Bx.COLS) / 2, headY + HEAD_H + GAP
      drawParty(x, y, w, true, clock, color)
      drawHead(g.gx, headY, g.cell * Bx.COLS)
      drawGrid(clock, color)
      local footY = g.gy + g.cell * Bx.ROWS + GAP
      drawFoot(g.gx, footY, g.cell * Bx.COLS, color, modeName)
      local py = footY + 11
      if y + h - py > 20 then drawPreview(mon, x + 2, py, w - 4, y + h - py - 1, true) end
    else
      local partyW = 40
      local cell = max(11, min(16, floor((w - partyW - 62 - GAP * 2 - 2) / Bx.COLS)))
      cell = max(9, min(cell, floor((h - HEAD_H - 14 - GAP * 2) / Bx.ROWS)))
      g.cell = cell
      g.partyX, g.partyY, g.partyW = x + 1, y + HEAD_H + 1, partyW - 1
      g.slotH = min(15, (h - HEAD_H - 2) / Bx.PARTY)
      K.text(T("boxes.party"), x + 1, y + 2.4, 4.6, C.soft, "center", partyW - 1)
      drawParty(x, y, partyW, false, clock, color)
      local bx = x + partyW + GAP + 1
      drawHead(bx, y, cell * Bx.COLS)
      g.gx, g.gy = bx, y + HEAD_H + GAP
      drawGrid(clock, color)
      drawFoot(bx, g.gy + cell * Bx.ROWS + GAP, cell * Bx.COLS, color, modeName)
      local vx = bx + cell * Bx.COLS + GAP + 1
      drawPreview(mon, vx, y + 1, x + w - vx - 1, h - 2, false)
    end
    K.scissor(body)
    drawHeld(clock)
    drawSheet(body)
  end

  return V
end
