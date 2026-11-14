-- The Pokédex window's drawing (src/apps/pokedex.lua holds its state and input). Nothing here makes a
-- table, a closure or a string while it draws: the words are the model's (src/dex.lua, made when a
-- Pokémon is chosen), the lines a text wraps to are made when the text or the width changes, numbers
-- through K.textCache, the radar one kept mesh.
--
--   View(K, env, T, st, A, KINDS) -> { draw(body, clock, portrait) }

local floor, max, min, ceil, sin, cos, pi, abs = math.floor, math.max, math.min, math.ceil, math.sin, math.cos,
  math.pi, math.abs

local M, GAP = 3, 2
local CELL_MIN = 25
local NARROW = 190          -- narrower than this (units): the grid and the page take turns
local STAT_MAX = 200        -- the radar's rim (a base stat over it touches the rim)
-- (the radar's corners from the top, clockwise: HP, Attack, Defense, Speed, Sp. Def, Sp. Atk; the page's
-- stats are HP, Atk, Def, SpA, SpD, Spe)
local CORNER_STAT = { 1, 2, 3, 6, 5, 4 }
local STAT_KEY = { "dex.stat.hp", "dex.stat.atk", "dex.stat.def", "dex.stat.spa", "dex.stat.spd", "dex.stat.spe" }
local C = {
  body = { 242, 242, 247 }, card = { 255, 255, 255 }, ink = { 28, 28, 30 }, soft = { 112, 112, 120 },
  faint = { 170, 170, 178 }, accent = { 10, 132, 255 }, accentSoft = { 10, 132, 255, 0.14 },
  sil = { 40, 44, 56 }, silCard = { 226, 228, 236 }, ball = { 238, 64, 54 }, white = { 255, 255, 255 },
  male = { 10, 132, 255 }, female = { 255, 55, 95 }, track = { 118, 118, 128, 0.18 },
  grid = { 120, 124, 140, 0.35 }, edge = { 255, 255, 255 }, heroDark = { 50, 54, 70 }, heroDarkFoot = { 26, 28, 38 },
  phys = { 236, 104, 60 }, spec = { 90, 120, 230 }, stat = { 150, 150, 160 },
}
-- the types' colours (the game's ids; 18 WoobleDex's Fairy)
local TYPE = {
  [0] = { 168, 168, 120 }, [1] = { 192, 48, 40 }, [2] = { 168, 144, 240 }, [3] = { 160, 64, 160 },
  [4] = { 224, 192, 104 }, [5] = { 184, 160, 56 }, [6] = { 168, 184, 32 }, [7] = { 112, 88, 152 },
  [8] = { 184, 184, 208 }, [9] = { 104, 160, 144 }, [10] = { 240, 128, 48 }, [11] = { 104, 144, 240 },
  [12] = { 120, 200, 80 }, [13] = { 248, 208, 48 }, [14] = { 248, 88, 136 }, [15] = { 152, 216, 216 },
  [16] = { 112, 56, 248 }, [17] = { 112, 88, 72 }, [18] = { 238, 153, 172 },
}
-- (each stat's colour on the radar)
local STAT_C = { { 255, 89, 89 }, { 245, 172, 120 }, { 250, 224, 120 }, { 157, 183, 245 }, { 167, 219, 141 },
                 { 250, 146, 178 } }
local UTF8 = "[%z\1-\127\194-\244][\128-\191]*"

return function(K, env, T, st, A, KINDS)
  local V = {}
  local bodyNow = nil
  local AB = { "ab1", "ab2", "ab3", "ab4", "ab5", "ab6" }
  local EMPTY = { types = {}, stats = { 0, 0, 0, 0, 0, 0 } }
  local num = K.textCache(function(n) return tostring(n) end)
  local heroTop, heroFoot = {}, {}
  local mesh = nil
  local PX, PY = { 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0 }

  local function word(key) return T(key) end

  -- ------- words wrapped to a width: made when the text, its size or the width change, kept by slot
  local function wrap(slot, text, w, size)
    local c = st.lines[slot]
    if c and c.text == text and c.w == w and c.size == size then return c.lines end
    local lines, line = {}, ""
    for wd in tostring(text or ""):gmatch("%S+") do
      local try = line == "" and wd or (line .. " " .. wd)
      if line ~= "" and K.width(try, size) > w then
        lines[#lines + 1] = line
        line = wd
      else
        line = try
      end
    end
    if line ~= "" then lines[#lines + 1] = line end
    st.lines[slot] = { text = text, w = w, size = size, lines = lines }
    return lines
  end
  local function drawLines(lines, x, y, size, c, a)
    local lh = size * 1.25
    for i = 1, #lines do K.text(lines[i], x, y + (i - 1) * lh, size, c, nil, nil, a) end
    return #lines * lh
  end

  -- a type's pill -> its width
  local function pill(id, name, x, y, h, size)
    local pw = K.width(name, size) + 5
    K.col(TYPE[id] or C.faint)
    K.box("fill", K.R(x, y, pw, h), h / 2)
    K.text(name, x, y + (h - size * 1.2) / 2, size, C.white, "center", pw)
    return pw
  end

  -- a small Poké Ball (caught)
  local function ballMark(cx, cy, r)
    local G = K.graphics()
    local px, py, pr = K.X(cx), K.Y(cy), r * K.sc
    K.col(C.ball)
    G.arc("fill", px, py, pr, pi, 2 * pi)
    K.col(C.white)
    G.arc("fill", px, py, pr, 0, pi)
    K.col(C.ink, 0.7)
    G.setLineWidth(max(1, 0.25 * K.sc))
    G.circle("line", px, py, pr)
    G.line(px - pr, py, px + pr, py)
    K.col(C.white)
    G.circle("fill", px, py, pr * 0.32)
  end
  -- (♀ / ♂ drawn: the fonts have no signs)
  local function sexMark(sex, x, y, s)
    local G = K.graphics()
    local c = sex == "f" and C.female or C.male
    K.col(c)
    G.setLineWidth(max(1, s * 0.16 * K.sc))
    local r = s * 0.28
    local cx, cy = x + r, y + s * 0.42
    G.circle("line", K.X(cx), K.Y(cy), r * K.sc)
    if sex == "f" then
      G.line(K.X(cx), K.Y(cy + r), K.X(cx), K.Y(cy + r + s * 0.34))
      G.line(K.X(cx - s * 0.15), K.Y(cy + r + s * 0.17), K.X(cx + s * 0.15), K.Y(cy + r + s * 0.17))
    else
      local d = r * 0.72
      G.line(K.X(cx + d), K.Y(cy - d), K.X(cx + d + s * 0.26), K.Y(cy - d - s * 0.26))
      G.line(K.X(cx + d + s * 0.26), K.Y(cy - d - s * 0.26), K.X(cx + d + s * 0.06), K.Y(cy - d - s * 0.26))
      G.line(K.X(cx + d + s * 0.26), K.Y(cy - d - s * 0.26), K.X(cx + d + s * 0.26), K.Y(cy - d - s * 0.06))
    end
  end

  -- ------- the grid

  local function drawGrid(x, y, w, h, clock)
    local book, list = st.book, st.list
    -- (the header: the dex (a switch when there are two), its counts)
    local hh = 9
    local counts = book.counts[book.modes[st.mi]]
    if #book.modes > 1 then
      local sw = min(w * 0.55, 80)
      K.segmented(x, y, sw, hh, st.mi, "win", A.MODE + 1, st.modeWords[1], A.MODE + 2, st.modeWords[2])
    else
      K.bold(st.modeWords[1] or "", x, y + 2, 5, C.ink)
    end
    if counts then
      local cx = x + w
      local cw = K.width(num(counts.caught), 4)
      cx = cx - cw
      K.bold(num(counts.caught), cx, y + 2.4, 4, C.ink)
      ballMark(cx - 3, y + 4.8, 2)
      cx = cx - 9
      local sw2 = K.width(num(counts.seen), 4)
      cx = cx - sw2
      K.bold(num(counts.seen), cx, y + 2.4, 4, C.ink)
      local G = K.graphics()
      K.col(C.soft)
      G.circle("line", K.X(cx - 3), K.Y(y + 4.8), 1.8 * K.sc)
      G.circle("fill", K.X(cx - 3), K.Y(y + 4.8), 0.8 * K.sc)
    end
    local gy, gh = y + hh + GAP, h - hh - GAP
    local cols = max(2, floor((w + GAP) / (CELL_MIN + GAP)))
    local cw = (w - (cols - 1) * GAP) / cols
    local ch = max(22, cw * 1.08)
    st.cols, st.cellH = cols, ch + GAP
    local n = #list
    local rows = ceil(n / cols)
    st.visRows = max(1, floor((gh + GAP) / (ch + GAP)))
    -- (following the chosen one when the D-pad moved it; free while scrolled by hand)
    if st.follow then
      local r = floor((st.sel - 1) / cols)
      if r < st.gridTop then st.gridTop = r end
      if r > st.gridTop + st.visRows - 1 then st.gridTop = r - st.visRows + 1 end
    end
    st.gridTop = max(0, min(max(0, rows - st.visRows), st.gridTop))
    local area = K.R(x, gy, w, gh)
    K.scissor(area)
    local first = floor(st.gridTop)
    local G = K.graphics()
    local frame = floor(clock * 3) % 2
    for r = first, min(rows - 1, first + st.visRows + 1) do
      local cy = gy + (r - st.gridTop) * (ch + GAP)
      for c = 0, cols - 1 do
        local i = r * cols + c + 1
        local e = list[i]
        if not e then break end
        local cx = x + c * (cw + GAP)
        local cb = K.R(cx, cy, cw, ch)
        local chosen = i == st.sel
        K.col(e.seen and C.card or C.silCard)
        K.box("fill", cb, 3)
        if chosen then
          K.col(C.accentSoft)
          K.box("fill", cb, 3)
          K.ring(cb, 3, C.accent, st.focus == "grid" and 1 or 0.5, 0.6)
        end
        K.text(e.numText, cx + 2, cy + 1.5, 3.2, C.soft)
        if e.caught then ballMark(cx + cw - 3.2, cy + 3.4, 1.7) end
        local is = min(cw - 4, ch - 11)
        local ix, iy = cx + (cw - is) / 2, cy + 5.5 + (ch - 11 - is) / 2
        if env.monIcon then
          if e.seen then
            env.monIcon(e.sp, ix, iy, is, chosen and frame or 0)
          else
            env.monIcon(e.sp, ix, iy, is, 0, 0.16, 0.17, 0.22, 0.55)
          end
        end
        local name = e.seen and e.name or "???"
        local fs = K.fit(name, 3.4, cw - 2)
        K.text(name, cx + 1, cy + ch - 5, fs, e.seen and C.ink or C.faint, "center", cw - 2)
        K.addHit(cb, "win", A.CELL + i, area)
      end
    end
    K.scissor(bodyNow)
    K.scrollbar(x + w + 1.4, gy, gh, min(st.gridTop, max(0, rows - st.visRows)), st.visRows, rows)
  end

  -- ------- the page

  local function hero(x, y, w, e, pg, clock)
    local h = 50
    local b = K.R(x, y, w, h)
    if not e.seen then
      K.grad(b, 5, C.heroDark, C.heroDarkFoot)
      K.bold("???", x + 6, y + h / 2 - 4, 7, C.white)
      return h
    end
    local tc = TYPE[pg.types[1] and pg.types[1].id or 0] or C.faint
    local top = heroTop[tc]
    if not top then
      top, heroFoot[tc] = K.light(tc, 0.25), K.dark(tc, 0.3)
      heroTop[tc] = top
    end
    K.grad(b, 5, top, heroFoot[tc])
    K.glow(x + 24, y + h * 0.55, 26, 22, C.white, 0.22)
    -- (its picture: the game's animation, or our breathing idle)
    local ps = 44
    local px, py = x + 2, y + (h - ps) / 2
    if env.dexSprite then
      env.dexSprite.draw(e.sp, px + ps / 2, py + ps / 2, ps, clock, st.chosenAt)
    elseif env.monPic then
      env.monPic(e.sp, px, py, ps, 1)
    end
    K.addHit(K.R(px, py, ps, ps), "win", A.SPRITE)
    local tx = px + ps + 3
    local tw = x + w - tx - 3
    K.label(e.numText, tx, y + 4, 3.6, C.white, nil, nil, 0.85)
    local fs = K.fit(e.name, 7, tw - 6)
    K.label(e.name, tx, y + 8, fs, C.white)
    if e.sex then sexMark(e.sex, tx + K.width(e.name, fs) + 1.2, y + 9, 5) end
    K.label(pg.category, tx, y + 16, K.fit(pg.category, 4, tw), C.white, nil, nil, 0.9)
    local cx = tx
    for i = 1, #pg.types do cx = cx + pill(pg.types[i].id, pg.types[i].name, cx, y + 22.5, 6, 3.6) + 1.5 end
    K.label(word("dex.height"), tx, y + 32, 3.3, C.white, nil, nil, 0.75)
    K.label(pg.heightText, tx + 15, y + 32, 3.5, C.white)
    K.label(word("dex.weight"), tx, y + 38, 3.3, C.white, nil, nil, 0.75)
    K.label(pg.weightText, tx + 15, y + 38, 3.5, C.white)
    return h
  end

  local function descCard(x, y, w, e, pg)
    local inner = w - 8
    local lines = wrap("desc", pg.description, inner, 3.9)
    local h = 6 + #lines * 3.9 * 1.25 + 12
    K.card(K.R(x, y, w, h), 4)
    drawLines(lines, x + 4, y + 4, 3.9, C.ink)
    -- (the gender ratio)
    local gy = y + h - 9
    K.text(word("dex.gender"), x + 4, gy, 3.4, C.soft)
    local bx, bw = x + 22, w - 26
    if pg.female == nil then
      K.text(word("dex.genderless"), bx, gy, 3.4, C.ink)
    else
      local bar = K.R(bx, gy + 1, bw, 2.4)
      K.col(C.female)
      K.box("fill", bar, 1.2)
      if pg.female < 1 then
        K.col(C.male)
        K.box("fill", K.R(bx, gy + 1, max(2.4, bw * (1 - pg.female)), 2.4), 1.2)
      end
      sexMark("m", bx, gy + 4, 3.2)
      K.text(pg.maleText, bx + 3.6, gy + 4, 3.1, C.soft)
      local fw = K.width(pg.femaleText, 3.1)
      K.text(pg.femaleText, bx + bw - fw - 3.6, gy + 4, 3.1, C.soft)
      sexMark("f", bx + bw - 3, gy + 4, 3.2)
    end
    return h
  end

  local function corner(i, cx, cy, r, v)
    local a = -pi / 2 + (i - 1) * pi / 3
    local k = min(1, v / STAT_MAX)
    return cx + cos(a) * r * k, cy + sin(a) * r * k
  end
  local function radar(x, y, w, pg, dt)
    local h = 76
    K.card(K.R(x, y, w, h), 4)
    K.bold(word("dex.stats"), x + 4, y + 3, 4.2, C.ink)
    local tt = word("dex.total")
    local tw = K.width(pg.totalText, 4.2)
    K.bold(pg.totalText, x + w - 4 - tw, y + 3, 4.2, C.ink)
    K.text(tt, x + w - 6 - tw - K.width(tt, 3.6), y + 3.6, 3.6, C.soft)
    local cx, cy = x + w / 2, y + 39
    local rad = min(22, w * 0.22)
    local G = K.graphics()
    local k = min(1, dt * 8)
    for j = 1, 6 do st.shown[j] = st.shown[j] + (pg.stats[j] - st.shown[j]) * k end
    -- (the grid: three rings and the spokes)
    G.setLineWidth(max(1, 0.25 * K.sc))
    K.col(C.grid)
    for ring = 1, 3 do
      local v = ring * STAT_MAX / 3
      for j = 1, 6 do
        local ax, ay = corner(j, cx, cy, rad, v)
        local bx, by = corner(j % 6 + 1, cx, cy, rad, v)
        G.line(K.X(ax), K.Y(ay), K.X(bx), K.Y(by))
      end
    end
    for j = 1, 6 do
      local ax, ay = corner(j, cx, cy, rad, STAT_MAX)
      G.line(K.X(cx), K.Y(cy), K.X(ax), K.Y(ay))
    end
    -- (the shape: a fan from the middle in the stats' colours, a bright edge)
    for j = 1, 6 do PX[j], PY[j] = corner(j, cx, cy, rad, max(8, st.shown[CORNER_STAT[j]])) end
    if mesh == nil then
      local ok, m = pcall(G.newMesh, 8, "fan", "dynamic")
      mesh = ok and m or false
    end
    if mesh then
      mesh:setVertex(1, K.X(cx), K.Y(cy), 0, 0, 1, 1, 1, 0.55)
      for j = 1, 6 do
        local c = STAT_C[CORNER_STAT[j]]
        mesh:setVertex(j + 1, K.X(PX[j]), K.Y(PY[j]), 0, 0, c[1] / 255, c[2] / 255, c[3] / 255, 0.75)
      end
      local c1 = STAT_C[CORNER_STAT[1]]
      mesh:setVertex(8, K.X(PX[1]), K.Y(PY[1]), 0, 0, c1[1] / 255, c1[2] / 255, c1[3] / 255, 0.75)
      G.setColor(1, 1, 1, 1)
      G.draw(mesh)
    end
    K.col(C.accent, 0.9)
    G.setLineWidth(max(1, 0.5 * K.sc))
    for j = 1, 6 do
      local n = j % 6 + 1
      G.line(K.X(PX[j]), K.Y(PY[j]), K.X(PX[n]), K.Y(PY[n]))
    end
    -- (each corner's stat and value)
    for j = 1, 6 do
      local si = CORNER_STAT[j]
      local lx, ly = corner(j, cx, cy, rad + 9, STAT_MAX)
      K.text(word(STAT_KEY[si]), lx - 16, ly - 4, 3.1, C.soft, "center", 32)
      K.bold(pg.statText[si], lx - 16, ly - 0.4, 3.6, C.ink, "center", 32)
    end
    return h
  end

  local function abilities(x, y, w, pg)
    local inner = w - 8
    local h = 10
    for i = 1, #pg.abilities do
      h = h + 5.5 + #wrap(AB[i] or "ab", pg.abilities[i].desc, inner, 3.5) * 3.5 * 1.25 + 2
    end
    K.card(K.R(x, y, w, h), 4)
    K.bold(word("dex.abilities"), x + 4, y + 3, 4.2, C.ink)
    local ay = y + 10
    for i = 1, #pg.abilities do
      local a = pg.abilities[i]
      K.bold(a.name, x + 4, ay, 4, C.accent)
      ay = ay + 5.5
      ay = ay + drawLines(wrap(AB[i] or "ab", a.desc, inner, 3.5), x + 4, ay, 3.5, C.soft) + 2
    end
    return h
  end

  -- the moves' list (the chosen kind's)
  local function moveRows(x, y, w, pg)
    local chipH, ky = 6, y
    local cx = x
    for i = 1, #KINDS do
      local label = word("dex.moves." .. KINDS[i])
      local cw = K.width(label, 3.5) + 6
      local cb = K.R(cx, ky, cw, chipH)
      local on = i == st.kind
      K.col(on and C.accent or C.track)
      K.box("fill", cb, chipH / 2)
      K.text(label, cx, ky + (chipH - 4.2) / 2, 3.5, on and C.white or C.ink, "center", cw)
      K.addHit(cb, "win", A.KIND + i)
      cx = cx + cw + 1.5
    end
    local rows = pg.moves[KINDS[st.kind]] or {}
    local ry = ky + chipH + 2.5
    if #rows == 0 then
      K.text(word("dex.moves.none"), x + 2, ry + 1, 3.6, C.soft)
      return ry + 8 - y
    end
    local rh = 7
    local wide = w > 120
    -- (columns: the tag, the name, the type, the power, the accuracy, PP; their names over them)
    local nameX = x + 12
    local typeX = x + w * (wide and 0.46 or 0.52)
    local powX = x + w - (wide and 34 or 22)
    K.text(word("dex.col.power"), powX - 4, ry, 3, C.faint, "right", 14)
    if wide then K.text(word("dex.col.acc"), powX + 7, ry, 3, C.faint, "right", 14) end
    K.text(word("dex.col.pp"), powX + (wide and 18 or 7), ry, 3, C.faint, "right", 14)
    ry = ry + 4.5
    for i = 1, #rows do
      local r = rows[i]
      local yy = ry + (i - 1) * rh
      if i % 2 == 0 then
        K.col(C.track, 0.35)
        K.box("fill", K.R(x, yy - 0.8, w, rh), 2)
      end
      K.text(r.tag, x + 1.5, yy + 0.6, 3.3, C.soft)
      K.text(r.name, nameX, yy + 0.4, K.fit(r.name, 3.7, typeX - nameX - 2), C.ink)
      local pw = pill(r.typeId, r.typeName, typeX, yy, 5.2, 3.1)
      if not r.status then
        K.col(r.physical and C.phys or C.spec)
        K.box("fill", K.R(typeX + pw + 1.2, yy + 1.4, 2.4, 2.4), 1.2)
      end
      K.text(r.powerText, powX, yy + 0.6, 3.4, C.ink, "right", 10)
      if wide then K.text(r.accText, powX + 11, yy + 0.6, 3.4, C.ink, "right", 10) end
      K.text(r.ppText, powX + (wide and 22 or 11), yy + 0.6, 3.4, C.soft, "right", 10)
    end
    return ry + #rows * rh - y
  end

  local function whereRows(x, y, w, pg)
    local list = pg.where
    if #list == 0 then
      K.text(word("dex.where.none"), x + 2, y + 1, 3.6, C.soft)
      return 8
    end
    local rh = 9
    for i = 1, #list do
      local r = list[i]
      local yy = y + (i - 1) * rh
      if i % 2 == 0 then
        K.col(C.track, 0.35)
        K.box("fill", K.R(x, yy - 0.8, w, rh), 2)
      end
      K.bold(r.place, x + 1.5, yy + 0.4, K.fit(r.place, 3.8, w * 0.55), C.ink)
      K.text(r.methodText, x + 1.5, yy + 4.4, 3.2, C.soft)
      K.text(r.levels, x + w * 0.55, yy + 0.6, 3.5, C.ink, "right", w * 0.45 - 2)
      K.text(r.chanceText, x + w * 0.55, yy + 4.4, 3.2, C.soft, "right", w * 0.45 - 2)
    end
    return #list * rh
  end

  local function infoRows(x, y, w, e, pg)
    local yy = y
    -- (the evolution chain: the first stage, then each step with how)
    K.bold(word("dex.info.evolution"), x + 1.5, yy, 3.8, C.ink)
    yy = yy + 6
    if #pg.evolutions == 0 then
      K.text(word("dex.evo.none"), x + 1.5, yy, 3.5, C.soft)
      yy = yy + 6
    else
      if env.monIcon then env.monIcon(pg.base, x, yy - 1.5, 8, 0) end
      K.text(pg.baseName, x + 9, yy, 3.6, pg.base == e.sp and C.accent or C.ink)
      yy = yy + 7
      for i = 1, #pg.evolutions do
        local v = pg.evolutions[i]
        local ix = x + 3 + (v.depth - 1) * 5
        local G = K.graphics()
        K.col(C.soft)
        G.setLineWidth(max(1, 0.3 * K.sc))
        G.line(K.X(ix), K.Y(yy + 2.2), K.X(ix + 3), K.Y(yy + 2.2))
        G.polygon("fill", K.X(ix + 3.4), K.Y(yy + 2.2), K.X(ix + 2.2), K.Y(yy + 1.2), K.X(ix + 2.2), K.Y(yy + 3.2))
        if env.monIcon then env.monIcon(v.to, ix + 4, yy - 1.5, 8, 0) end
        K.text(v.toName, ix + 13, yy, 3.6, v.to == e.sp and C.accent or C.ink)
        local hw = x + w - (ix + 13 + K.width(v.toName, 3.6) + 3)
        K.text(v.how, x, yy + 0.3, K.fit(v.how, 3.2, max(10, hw)), C.soft, "right", w - 1.5)
        yy = yy + 7
      end
    end
    yy = yy + 2
    for i = 1, #pg.info do
      local r = pg.info[i]
      if i % 2 == 1 then
        K.col(C.track, 0.35)
        K.box("fill", K.R(x, yy - 0.8, w, 6.4), 2)
      end
      K.text(r.label, x + 1.5, yy + 0.2, 3.4, C.soft)
      K.text(r.value, x + w * 0.42, yy + 0.2, K.fit(r.value, 3.4, w * 0.58 - 2), C.ink, "right", w * 0.58 - 2)
      yy = yy + 6.4
    end
    return yy - y
  end

  local function tabs(x, y, w, e, pg)
    local yy = y
    if e.caught then
      K.segmented(x, yy, w, 8, st.tab, "win", A.TAB + 1, word("dex.tab.moves"), A.TAB + 2, word("dex.tab.where"),
        A.TAB + 3, word("dex.tab.info"))
      yy = yy + 11
    else
      K.bold(word("dex.tab.where"), x + 1, yy + 1, 4.2, C.ink)
      yy = yy + 8
    end
    local tab = e.caught and st.tab or 2
    local ch
    if tab == 1 then ch = moveRows(x + 3, yy + 3, w - 6, pg)
    elseif tab == 2 then ch = whereRows(x + 3, yy + 3, w - 6, pg)
    else ch = infoRows(x + 3, yy + 3, w - 6, e, pg) end
    return yy - y + ch + 8
  end

  local function drawPage(x, y, w, h, clock, dt)
    local e, pg = st.entry, st.page
    st.detailVis = h
    local area = K.R(x, y, w, h)
    K.scissor(area)
    local yy = y - st.detailTop
    if not e then
      K.scissor(bodyNow)
      return
    end
    yy = yy + hero(x, yy, w, e, pg or EMPTY, clock) + GAP
    if e.seen and pg then
      yy = yy + descCard(x, yy, w, e, pg) + GAP
      if e.caught then
        yy = yy + radar(x, yy, w, pg, dt) + GAP
        if #pg.abilities > 0 then yy = yy + abilities(x, yy, w, pg) + GAP end
      else
        local note = word("dex.notCaught")
        K.card(K.R(x, yy, w, 10), 4)
        K.text(note, x + 4, yy + 3, K.fit(note, 3.8, w - 8), C.soft)
        yy = yy + 10 + GAP
      end
      -- (the tabs and their card)
      local ty = yy
      K.card(K.R(x, ty, w, max(10, st.tabH or 30)), 4)
      local th = tabs(x + 2, ty + 2, w - 4, e, pg)
      st.tabH = th + 2
      yy = ty + st.tabH + GAP
    end
    st.detailH = yy + st.detailTop - y
    st.detailTop = max(0, min(st.detailTop, max(0, st.detailH - h)))
    K.scissor(bodyNow)
    K.scrollbar(x + w + 1.4, y, h, st.detailTop, h, max(h, st.detailH))
  end

  function V.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    bodyNow = body
    local dt = st.lastT and max(0, min(0.1, clock - st.lastT)) or 0
    st.lastT = clock
    K.col(C.body)
    K.box("fill", body)
    st.narrow = w < NARROW
    if not st.narrow then st.detail = false end
    if st.narrow then
      if st.detail then
        local bb = K.R(x + M, y + M, 26, 7)
        K.button(bb, word("dex.back"), "gray", false, 3.8)
        K.addHit(bb, "win", A.BACK)
        st.pageX = x
        drawPage(x + M, y + M + 9, w - M * 2, h - M * 2 - 9, clock, dt)
      else
        drawGrid(x + M, y + M, w - M * 2 - 2, h - M * 2, clock)
      end
      return
    end
    local lw = max(96, min(floor(w * 0.47), 190))
    drawGrid(x + M, y + M, lw - 2, h - M * 2, clock)
    local px = x + M + lw + GAP + 1
    st.pageX = px
    drawPage(px, y + M, x + w - M - 2 - px, h - M * 2, clock, dt)
  end

  return V
end
