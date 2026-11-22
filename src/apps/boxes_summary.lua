-- The Boxes window's summary (src/apps/boxes.lua keeps its state in st.sum and takes its input): one
-- Pokémon's page in the Pokédex's glass. The top: back, and which of the list it is with arrows to the
-- ones before and after. The Pokémon on a pane of its type's colour (its picture popping up, animated as
-- the Pokédex's, a shiny in its colours; its number, name, level, gender, types, markings), its HP and
-- status, its EXP to the next level, its item, its friendship; Galar Rising's Dynamax Level and G-Max
-- Factor. Then Info | Stats | Moves: the OT, ID, nature, ability, Ball and where it was met; each stat
-- with its IV and EV and the EVs on a radar; the moves with their PP, the chosen one's power, accuracy,
-- category and words (and its contest side on Ruby / Sapphire / Emerald).
-- Wide, the Pokémon on the left and the tabs on the right; narrow, one column that scrolls.
--
-- Nothing here makes a table, a closure or a string while it draws, but once each time another Pokémon
-- is shown (its numbers' words, in `vt`) and when a text is wrapped to a new width (S.lines).
-- Its motion: the backdrop turning to the Pokémon's types, the cards settling in one after another as a
-- Pokémon is shown, its picture popping up, the HP / EXP / friendship bars filling, the radar morphing
-- from the last one's EVs, the tab's thumb sliding, the chosen move's highlight gliding.
--
--   View(K, env, T, st, A, TABS) -> { draw(body, clock, portrait, S) }

local floor, max, min, sin, cos, pi, abs = math.floor, math.max, math.min, math.sin, math.cos, math.pi, math.abs

local M, GAP = 3, 2
local NARROW = 200          -- narrower than this (units): one column
local TOP_H = 9
local HERO_H, HERO_MIN = 50, 40  -- the Pokémon's pane: its height, and the least it gives up to on a wide page
local C = {
  ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, faint = { 160, 160, 170 }, accent = { 10, 132, 255 },
  white = { 255, 255, 255 }, black = { 0, 0, 0 }, male = { 10, 132, 255 }, female = { 255, 55, 95 },
  track = { 118, 118, 128, 0.16 }, grid = { 120, 124, 140, 0.32 }, slate = { 120, 132, 178 },
  slate2 = { 150, 120, 190 }, hpGood = { 52, 199, 89 }, hpMid = { 255, 204, 0 }, hpLow = { 255, 59, 48 },
  exp = { 64, 156, 255 }, heart = { 255, 92, 140 }, gold = { 232, 170, 28 }, up = { 230, 64, 64 },
  down = { 64, 120, 230 }, phys = { 236, 104, 60 }, spec = { 90, 120, 230 }, statusC = { 150, 150, 160 },
  dmax = { 255, 140, 24 }, swap = { 52, 199, 89 }, ppMid = { 230, 160, 0 },
  ppLow = { 240, 110, 30 }, ppOut = { 230, 50, 50 }, mark = { 90, 90, 100 },
}
-- the G-Max Factor's mark (env.gmaxMark): its height in units, its width for each unit of height (34 x 24)
local GMAX_H, GMAX_W = 5.6, 34 / 24
local SHADE_TOP, SHADE_FOOT = { 255, 255, 255, 0.28 }, { 0, 0, 0, 0.16 }
-- the types' colours (the game's ids; 18 WoobleDex's Fairy)
local TYPE = {
  [0] = { 168, 168, 120 }, [1] = { 192, 48, 40 }, [2] = { 168, 144, 240 }, [3] = { 160, 64, 160 },
  [4] = { 224, 192, 104 }, [5] = { 184, 160, 56 }, [6] = { 168, 184, 32 }, [7] = { 112, 88, 152 },
  [8] = { 184, 184, 208 }, [9] = { 104, 160, 144 }, [10] = { 240, 128, 48 }, [11] = { 104, 144, 240 },
  [12] = { 120, 200, 80 }, [13] = { 248, 208, 48 }, [14] = { 248, 88, 136 }, [15] = { 152, 216, 216 },
  [16] = { 112, 56, 248 }, [17] = { 112, 88, 72 }, [18] = { 238, 153, 172 },
}
-- (each stat's colour, in the rows' order HP, Atk, Def, SpA, SpD, Spe; Gen 1's five: HP, Atk, Def, Spc, Spe)
local STAT_C = { { 255, 89, 89 }, { 245, 152, 90 }, { 240, 205, 80 }, { 120, 160, 245 }, { 120, 200, 110 },
                 { 245, 120, 165 } }
-- (the contest's five, as the game colours them: Cool, Beauty, Cute, Smart, Tough)
local CONTEST_C = { [0] = { 232, 72, 64 }, { 64, 120, 240 }, { 240, 120, 176 }, { 72, 176, 96 }, { 224, 184, 40 } }
local INFO_SLOT = { "i1", "i2", "i3", "i4", "i5", "i6", "i7", "i8", "i9", "i10", "i11", "i12", "i13", "i14" }

local function clamp01(t) return t < 0 and 0 or (t > 1 and 1 or t) end

return function(K, env, T, st, A, TABS)
  local V = {}
  local outCubic, outBack, approach = K.outCubic, K.outBack, K.approach
  local G = nil
  local num = K.textCache(function(n) return tostring(n) end)
  local posText = K.textCache(function(k) return tostring(k % 1000) .. " / " .. tostring(floor(k / 1000)) end)
  local evPair = K.textCache(function(k) return tostring(k % 100000) .. " / " .. tostring(floor(k / 100000)) end)
  local mesh = nil
  local PX, PY = { 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0 }
  local bodyNow, pageArea = nil, nil
  -- the motion's numbers
  local mv = { rec = nil, pageAt = 0, tabAt = 0, tab = nil, tabX = 1, moveY = 0, movePrev = nil, coloured = false,
               r = 0.6, g = 0.6, b = 0.6, r2 = 0.6, g2 = 0.6, b2 = 0.6, lastT = nil, top = 0 }
  V.motion = mv
  -- the shown Pokémon's numbers as words (made once per Pokémon, not per frame)
  local vt = { hp = "", exp = "", next = "" }

  local function word(key) return T(key) end

  -- ------- words wrapped to a width (kept per slot until the text, size or width change)
  local function wrap(S, slot, text, w, size)
    local c = S.lines[slot]
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
    S.lines[slot] = { text = text, w = w, size = size, lines = lines }
    return lines
  end
  -- (a wrapped line's step: as tall as the player's text size draws it)
  local function lineH(size) return K.lineH(size) * 1.25 end
  local function drawLines(lines, x, y, size, c, a)
    local lh = lineH(size)
    for i = 1, #lines do K.text(lines[i], x, y + (i - 1) * lh, size, c, nil, nil, a) end
    return #lines * lh
  end
  -- (the player's text size over 100%: 0 at 100%, so every room made of it leaves 100% as it was)
  local function grown() return K.textScale() - 1 end
  -- (how much wider s is drawn than at 100%)
  local function extra(s, size)
    local w = K.width(s, size)
    return w - w / K.textScale()
  end
  -- (a size keeping s inside `room` at the player's text size, never drawn under its 100% size; at 100%
  -- just `size`)
  local function roomy(s, size, room)
    local ts = K.textScale()
    if ts == 1 then return size end
    return max(size / ts, K.fit(s, size, room))
  end

  -- something settling in: `(1 - e) * dy` lower and at `e` of itself; settle(e) after, with the same e
  local FADES, depth = {}, 0
  local function rise(e, dy)
    if e >= 1 then return end
    depth = depth + 1
    FADES[depth] = K.getFade()
    K.setFade(FADES[depth] * e)
    G.push()
    G.translate(0, (1 - e) * dy * K.sc)
  end
  local function settle(e)
    if e >= 1 then return end
    K.setFade(FADES[depth])
    depth = depth - 1
    G.pop()
  end
  local function enter(clock, delay, dur) return outCubic((clock - mv.pageAt - delay) / (dur or 0.4)) end
  local function rowIn(clock, i) return outCubic((clock - mv.tabAt - min(i, 24) * 0.02) / 0.26) end

  -- a type's pill -> its width
  local function pill(id, name, x, y, h, size, a, ring)
    local pw = K.width(name, size) + 5
    local b = K.R(x, y, pw, h)
    K.col(TYPE[id] or C.faint, a)
    K.box("fill", b, h / 2)
    if ring then K.ring(b, h / 2, C.white, 0.55 * (a or 1), 0.4) end
    K.text(name, x, y + (h - size * 1.2) / 2, size, C.white, "center", pw, a)
    return pw
  end
  -- (♀ / ♂ drawn: the fonts have no signs)
  local function sexMark(sex, x, y, s, a, c)
    K.col(c or (sex == "F" and C.female or C.male), a)
    G.setLineWidth(max(1, s * 0.16 * K.sc))
    local r = s * 0.28
    local cx, cy = x + r, y + s * 0.42
    G.circle("line", K.X(cx), K.Y(cy), r * K.sc)
    if sex == "F" then
      G.line(K.X(cx), K.Y(cy + r), K.X(cx), K.Y(cy + r + s * 0.34))
      G.line(K.X(cx - s * 0.15), K.Y(cy + r + s * 0.17), K.X(cx + s * 0.15), K.Y(cy + r + s * 0.17))
    else
      local d = r * 0.72
      G.line(K.X(cx + d), K.Y(cy - d), K.X(cx + d + s * 0.26), K.Y(cy - d - s * 0.26))
      G.line(K.X(cx + d + s * 0.26), K.Y(cy - d - s * 0.26), K.X(cx + d + s * 0.06), K.Y(cy - d - s * 0.26))
      G.line(K.X(cx + d + s * 0.26), K.Y(cy - d - s * 0.26), K.X(cx + d + s * 0.26), K.Y(cy - d - s * 0.06))
    end
  end
  -- a four-pointed star (a shiny's), r units round cx, cy: two thin diamonds crossed (love's fills are convex)
  local function star(cx, cy, r, c, a)
    K.col(c, a)
    local x, y, rr, q = K.X(cx), K.Y(cy), r * K.sc, r * K.sc * 0.3
    G.polygon("fill", x, y - rr, x + q, y, x, y + rr, x - q, y)
    G.polygon("fill", x - rr, y, x, y - q, x + rr, y, x, y + q)
  end
  -- a big Poké Ball's outline turning slowly (the hero's watermark)
  local function ballMarkBig(cx, cy, r, turn, a)
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
  -- the four markings (circle, square, triangle, heart), those set dark, the rest faint
  local function markings(bits, x, y, s, a)
    for i = 0, 3 do
      local on = floor(bits / 2 ^ i) % 2 == 1
      K.col(C.white, (on and 0.95 or 0.35) * (a or 1))
      local cx, cy = K.X(x + i * (s + 1.2) + s / 2), K.Y(y + s / 2)
      local r = s * 0.42 * K.sc
      if i == 0 then G.circle("fill", cx, cy, r)
      elseif i == 1 then G.rectangle("fill", cx - r * 0.85, cy - r * 0.85, r * 1.7, r * 1.7)
      elseif i == 2 then G.polygon("fill", cx, cy - r, cx + r, cy + r * 0.8, cx - r, cy + r * 0.8)
      else
        G.circle("fill", cx - r * 0.45, cy - r * 0.2, r * 0.5)
        G.circle("fill", cx + r * 0.45, cy - r * 0.2, r * 0.5)
        G.polygon("fill", cx - r * 0.92, cy, cx + r * 0.92, cy, cx, cy + r)
      end
    end
  end
  -- a bar filling to k (0..1) of w: its track, its colour
  local function bar(x, y, w, h, k, c, a)
    K.col(C.track, a)
    K.box("fill", K.R(x, y, w, h), h / 2)
    local fw = w * clamp01(k)
    if fw > 0.2 then
      K.col(c, a)
      K.box("fill", K.R(x, y, max(h, fw), h), h / 2)
    end
  end
  -- a heart, s units wide, at x, y (the contest's appeal and jam)
  local function heart(x, y, s, c, a)
    K.col(c, a)
    local r = s * 0.27 * K.sc
    local cx, cy = K.X(x + s / 2), K.Y(y + s * 0.42)
    G.circle("fill", cx - r * 0.9, cy - r * 0.3, r)
    G.circle("fill", cx + r * 0.9, cy - r * 0.3, r)
    G.polygon("fill", cx - r * 1.85, cy - r * 0.05, cx + r * 1.85, cy - r * 0.05, cx, cy + r * 2.2)
  end

  -- ------- the top: back, which of the list, the arrows
  local function drawTop(x, y, w, S)
    local label = word(S.back or "app.storage")
    local backW = K.width(label, 4.2) + 8
    local bb = K.R(x, y, backW, TOP_H)
    K.chevron(x + 2, y + 4.5, 4.2, C.accent, -1)
    K.text(label, x + 4.8, y + 2, 4.2, C.accent)
    K.addHit(bb, "win", A.SUM_BACK)
    -- (the page's title in the middle, clear of the way back and the arrows)
    local n = #S.list
    local side = math.max(backW, n > 1 and 54 or 0) + 2
    local title = word("sum.title")
    local tw = w - side * 2
    if tw > 20 then
      local fs = K.fit(title, 5.4, tw)
      K.bold(title, x + side, y + (TOP_H - fs * 1.2) / 2, fs, C.ink, "center", tw)
    end
    if n > 1 then
      local rx = x + w
      local ab = K.R(rx - 9, y, 9, TOP_H)
      K.chevron(rx - 4.5, y + 4.5, 4, C.accent, 2)
      K.addHit(ab, "win", A.SUM_NEXT)
      ab = K.R(rx - 19, y, 9, TOP_H)
      G.push()
      G.translate(K.X(rx - 14.5), K.Y(y + 4.5))
      G.rotate(pi)
      G.translate(-K.X(rx - 14.5), -K.Y(y + 4.5))
      K.chevron(rx - 14.5, y + 4.5, 4, C.accent, 2)
      G.pop()
      K.addHit(ab, "win", A.SUM_PREV)
      K.text(posText(n * 1000 + S.i), rx - 52, y + 2.3, 3.8, C.soft, "right", 31)
    end
  end

  -- ------- the Pokémon: its pane, its picture, its words
  local function hero(x, y, w, h, R, S, clock)
    local b = K.R(x, y, w, h)
    K.shadow(b, 5, 1.4, 0.1)
    G.setColor(mv.r, mv.g, mv.b, 0.74 * K.getFade())
    K.box("fill", b, 5)
    K.grad(b, 5, SHADE_TOP, SHADE_FOOT)
    K.ring(b, 5, C.white, 0.6, 0.4)
    G.intersectScissor(K.X(x), K.Y(y), w * K.sc, h * K.sc)
    ballMarkBig(x + w - h * 0.3, y + h * 0.62, h * 0.6, clock * 0.18, 0.13)
    K.scissor(pageArea)
    -- (its picture popping up on its shadow, a light behind it)
    local t = clock - mv.pageAt
    local pop = 0.8 + 0.2 * outBack(t / 0.42)
    local fa = outCubic(t / 0.18) * K.getFade()
    local ps = min(44, h - 6)
    local pcx, pcy = x + 3 + ps / 2, y + h / 2 + 1
    K.glow(pcx, pcy, 26, 22, C.white, 0.24 * fa)
    K.col(C.black, 0.2 * fa)
    G.ellipse("fill", K.X(pcx), K.Y(pcy + ps * 0.43), ps * 0.27 * pop * K.sc, ps * 0.06 * K.sc)
    if R.egg or not env.dexSprite then
      if env.monPic then env.monPic(R.sp, pcx - ps / 2 * pop, pcy - ps / 2 * pop, ps * pop, fa, R.mon) end
    else
      env.dexSprite.draw(R.sp, pcx, pcy, ps, clock, S.at, pop, fa, R.shiny, R.mon)
    end
    K.addHit(K.R(pcx - ps / 2, pcy - ps / 2, ps, ps), "win", A.SUM_PIC)
    -- (its words sliding in after it)
    local tx = x + ps + 7
    local tw = x + w - tx - 3
    local e1, e2, e3 = enter(clock, 0.04, 0.32), enter(clock, 0.08, 0.32), enter(clock, 0.12, 0.32)
    local fa1 = e1 * K.getFade()
    K.label(R.egg and "" or R.dexText, tx + (1 - e1) * 6, y + 4, 3.6, C.white, nil, nil, 0.85 * fa1)
    local fs = K.fit(R.name, 7, tw - 8)
    K.label(R.name, tx + (1 - e1) * 8, y + 8, fs, C.white, nil, nil, fa1)
    local nx = tx + (1 - e1) * 8 + K.width(R.name, fs) + 1.2
    if R.gender and not K.hasSign(R.name) then sexMark(R.gender, nx, y + 9, 5, fa1) nx = nx + 5 end
    if R.shiny then star(nx + 2.5, y + 11.5, 2.4 + 0.5 * sin(clock * 5), C.gold, fa1) end
    if not R.egg then
      -- (the lines under the name a little lower as the text grows)
      local g = grown() * 3
      local ox = (1 - e2) * 8
      K.label(R.levelText, tx + ox, y + 16.5 + g, 4.2, C.white, nil, nil, e2 * K.getFade())
      if R.speciesName ~= R.name then
        local lw2 = K.width(R.levelText, 4.2) + 3
        K.label(R.speciesName, tx + ox + lw2, y + 16.9 + g,
          roomy(R.speciesName, K.fit(R.speciesName, 3.6, tw - 24), tw - lw2 - 1), C.white, nil, nil,
          0.8 * e2 * K.getFade())
      end
      local cx = tx + (1 - e3) * 8
      for i = 1, #R.types do
        cx = cx + pill(R.types[i].id, R.types[i].name, cx, y + 23.5 + g, 6, 3.6, e3 * K.getFade(), true) + 1.5
      end
      markings(R.markings or 0, tx + (1 - e3) * 8, y + 33 + g, 3, e3 * K.getFade())
    end
    return h
  end

  -- (the vitals card's height: HP, EXP and the next level; the item, friendship and Dynamax rows)
  local function vitalsH(R)
    local h = R.egg and 0 or 27
    if R.itemName then h = h + 7 end
    if R.friendship then h = h + 7 end
    if R.dmax then h = h + 7 end
    -- (an egg's one row: a little more room at its foot as the text grows; the full card has room)
    if R.egg and h > 0 then h = h + grown() * 2 end
    return h
  end

  -- HP (and its status on its line), EXP to the next level, the item, friendship, Galar Rising's Dynamax
  -- Level (ten segments) and G-Max Factor
  local function vitals(x, y, w, R, clock)
    local h = vitalsH(R)
    if h == 0 then return 0 end
    K.glass(K.R(x, y, w, h), 4)
    local f = enter(clock, 0.15, 0.7)
    local yy = y + 3
    local lw = 13
    if not R.egg then
      K.bold(word("dex.stat.hp"), x + 4, yy, 3.6, C.ink)
      local bx = x + 4 + lw
      if R.status then
        local sw = K.width(R.status, 3.2) + 4
        K.col(C.statusC)
        K.box("fill", K.R(x + 4 + K.width(word("dex.stat.hp"), 3.6) + 2, yy - 0.4, sw, 4.6), 2.3)
        K.text(R.status, x + 4 + K.width(word("dex.stat.hp"), 3.6) + 2, yy, 3.2, C.white, "center", sw)
        bx = max(bx, x + 4 + K.width(word("dex.stat.hp"), 3.6) + 2 + sw + 2)
      end
      local k = R.maxHp > 0 and R.hp / R.maxHp or 0
      bar(bx, yy + 1.2, x + w - 26 - bx, 2.4, k * f, k > 0.5 and C.hpGood or (k > 0.2 and C.hpMid or C.hpLow))
      K.text(vt.hp, x + w - 24, yy, 3.6, C.ink, "right", 20)
      yy = yy + 6
      K.bold(word("sum.exp"), x + 4, yy, 3.6, C.ink)
      K.text(vt.exp, x + w - 34, yy, 3.6, C.ink, "right", 30)
      yy = yy + 5.4
      bar(x + 4, yy, w - 8, 1.8, (R.expPct or 0) * f, C.exp)
      yy = yy + 3.4
      K.text(word("sum.next"), x + 4, yy, 3.2, C.soft)
      K.text(vt.next, x + w - 34, yy, 3.2, C.soft, "right", 30)
      yy = yy + 6.6
    end
    if R.itemName then
      if R.itemId and env.itemIcon then pcall(env.itemIcon, R.itemId, x + 3.2, yy - 0.8, 5.6, K.getFade()) end
      K.text(word("sum.item"), x + 10, yy, 3.4, C.soft)
      K.text(R.itemName, x + 10, yy, K.fit(R.itemName, 3.6, w - 34 - extra(word("sum.item"), 3.4)), C.ink, "right",
        w - 14)
      yy = yy + 7
    end
    if R.friendship then
      K.text(word("sum.friendship"), x + 4, yy, 3.4, C.soft)
      local fx = x + 4 + K.width(word("sum.friendship"), 3.4) + 3
      heart(fx, yy + 0.3, 3.4, C.heart, K.getFade())
      bar(fx + 4.5, yy + 1.1, x + w - 4 - fx - 4.5, 2, R.friendship / 255 * f, C.heart)
      yy = yy + 7
    end
    if R.dmax then
      K.text(word("sum.dmax"), x + 4, yy, 3.4, C.soft)
      local sx = x + 4 + K.width(word("sum.dmax"), 3.4) + 3
      local ex = x + w - 4
      -- (the G-Max Factor: its mark at the row's end)
      if R.gmax and env.gmaxMark then
        local gw = GMAX_H * GMAX_W
        ex = ex - gw
        env.gmaxMark(ex + gw / 2, yy + 4.6, GMAX_H)
        ex = ex - 2
      end
      local seg = (ex - sx) / 10
      for i = 1, 10 do
        K.col(i <= R.dmax * f and C.dmax or C.track)
        K.box("fill", K.R(sx + (i - 1) * seg, yy + 0.9, seg - 0.5, 2.4), 0.8)
      end
    end
    return h
  end

  -- ------- Info: the rows (a value too long for its line goes under its label), the ability
  local function infoTab(x, y, w, R, S, clock)
    local yy = y
    if R.egg and R.eggText then
      local lines = wrap(S, "egg", R.eggText, w - 3, 3.8)
      yy = yy + drawLines(lines, x + 1.5, yy, 3.8, C.ink) + 4
    end
    local rows = R.info
    for i = 1, #rows do
      local r = rows[i]
      local ein = rowIn(clock, i)
      rise(ein, 3)
      local lw = K.width(r.label, 3.4) + 4
      local tint = r.tint == "female" and C.female or (r.tint == "male" and C.male or C.ink)
      local rh
      if K.width(r.value, 3.6) <= w - lw - 3 then
        if i % 2 == 1 then
          K.col(C.track, 0.35)
          K.box("fill", K.R(x, yy - 0.8, w, 6.4), 2)
        end
        K.text(r.label, x + 1.5, yy + 0.2, 3.4, C.soft)
        K.text(r.value, x + lw, yy + 0.1, 3.6, tint, "right", w - lw - 1.5)
        rh = 6.4
      else
        local lines = wrap(S, INFO_SLOT[i] or "ix", r.value, w - 6, 3.6)
        rh = 5.2 + grown() * 3 + #lines * lineH(3.6) + 1.2
        if i % 2 == 1 then
          K.col(C.track, 0.35)
          K.box("fill", K.R(x, yy - 0.8, w, rh), 2)
        end
        K.text(r.label, x + 1.5, yy + 0.2, 3.4, C.soft)
        drawLines(lines, x + 4, yy + 5 + grown() * 3, 3.6, tint)
      end
      settle(ein)
      yy = yy + rh
    end
    if not R.egg and R.abilityName and R.abilityName ~= "" then
      local ein = rowIn(clock, #rows + 1)
      rise(ein, 3)
      yy = yy + 2.5
      local lines = wrap(S, "ab", R.abilityDesc, w - 8, 3.5)
      local g = grown() * 3
      local bh = 5.5 + g + #lines * lineH(3.5)
      G.setColor(mv.r, mv.g, mv.b, 0.85 * K.getFade())
      K.box("fill", K.R(x + 1.5, yy + 0.3, 1.3, bh - 1), 0.65)
      K.text(word("sum.ability"), x + 5, yy, 3.4, C.soft)
      K.bold(R.abilityName, x + 6 + K.width(word("sum.ability"), 3.4) + 2, yy - 0.2, 3.8, C.ink)
      drawLines(lines, x + 5, yy + 5.3 + g, 3.5, C.soft)
      settle(ein)
      yy = yy + bh + 1
    end
    return yy - y
  end

  -- ------- Stats: the EVs on a radar (morphing), each stat with its value, IV and EV
  local function corner(i, n, cx, cy, r, k)
    local a = -pi / 2 + (i - 1) * 2 * pi / n
    return cx + cos(a) * r * k, cy + sin(a) * r * k
  end
  local function radar(cx, cy, rad, R, S, labels, a)
    local n = #R.radar
    local top = R.evMax or 252
    -- (the grid: the rim filled faintly, three rings, the spokes)
    K.col(C.track, 0.55 * a)
    for j = 1, n do
      local ax, ay = corner(j, n, cx, cy, rad, 1)
      local bx, by = corner(j % n + 1, n, cx, cy, rad, 1)
      G.polygon("fill", K.X(cx), K.Y(cy), K.X(ax), K.Y(ay), K.X(bx), K.Y(by))
    end
    G.setLineWidth(max(1, 0.25 * K.sc))
    K.col(C.grid, a)
    for ring = 1, 3 do
      for j = 1, n do
        local ax, ay = corner(j, n, cx, cy, rad, ring / 3)
        local bx, by = corner(j % n + 1, n, cx, cy, rad, ring / 3)
        G.line(K.X(ax), K.Y(ay), K.X(bx), K.Y(by))
      end
    end
    for j = 1, n do
      local ax, ay = corner(j, n, cx, cy, rad, 1)
      G.line(K.X(cx), K.Y(cy), K.X(ax), K.Y(ay))
    end
    -- (the shape: the backdrop's colour, deeper at the edge, a dot at each corner)
    for j = 1, n do PX[j], PY[j] = corner(j, n, cx, cy, rad, max(0.04, min(1, S.shown[j] / top))) end
    if mesh == nil then
      local ok, m = pcall(G.newMesh, 8, "fan", "dynamic")
      mesh = ok and m or false
    end
    local r, g, b = mv.r, mv.g, mv.b
    if mesh then
      mesh:setVertex(1, K.X(cx), K.Y(cy), 0, 0, r, g, b, 0.18)
      for j = 1, 7 do
        local jj = (j - 1) % n + 1
        if j <= n + 1 then mesh:setVertex(j + 1, K.X(PX[jj]), K.Y(PY[jj]), 0, 0, r, g, b, 0.62)
        else mesh:setVertex(j + 1, K.X(PX[1]), K.Y(PY[1]), 0, 0, r, g, b, 0.62) end
      end
      mesh:setDrawRange(1, n + 2)
      G.setColor(1, 1, 1, a * K.getFade())
      G.draw(mesh)
    end
    G.setColor(r * 0.7, g * 0.7, b * 0.7, a * K.getFade())
    G.setLineWidth(max(1, 0.55 * K.sc))
    for j = 1, n do
      local nx = j % n + 1
      G.line(K.X(PX[j]), K.Y(PY[j]), K.X(PX[nx]), K.Y(PY[nx]))
    end
    for j = 1, n do
      K.col(C.white, a)
      G.circle("fill", K.X(PX[j]), K.Y(PY[j]), 1.1 * K.sc)
    end
    if not labels then return end
    -- (the label and its number apart as the text grows)
    local g = grown() * 1.8
    for j = 1, n do
      local lx, ly = corner(j, n, cx, cy, rad + 6.5, 1)
      K.text(word(R.radarKeys[j]), lx - 9, ly - 3.8 - g, 3, C.soft, "center", 18, a)
      K.bold(num(floor(S.shown[j] + 0.5)), lx - 9, ly - 0.6 + g, 3.3, C.ink, "center", 18, a)
    end
  end
  local function statsTab(x, y, w, R, S, clock, dt)
    for j = 1, #R.radar do S.shown[j] = approach(S.shown[j], R.radar[j], dt, 8) end
    -- (wide: the radar, small and labelled, at the left, the table beside it; narrow: one over the other)
    local wide = w >= 108
    local yy = y
    local rad = wide and 10 or min(19, w * 0.2)
    local rx = wide and (x + 23) or (x + w / 2)
    local ry = wide and (y + 11.5 + rad) or (y + 11 + rad)
    -- (the radar's title, the EV total)
    K.bold(word("sum.evs"), x + 1.5, yy, 3.8, C.ink)
    radar(rx, ry, rad, R, S, true, 1)
    if not wide then yy = ry + rad + 10 + grown() * 4 end
    local tx = wide and (x + 48) or x
    local tw = x + w - tx
    local ty = wide and y or yy
    if R.evTotalMax then
      if wide then
        K.text(evPair(R.evTotalMax * 100000 + R.evTotal), x, ry + rad + 11.5, 3.2, C.soft, "center", 46)
      else
        K.text(evPair(R.evTotalMax * 100000 + R.evTotal), tx, ty, 3.4, C.soft, "right", w - 1.5)
        ty = ty + 5
      end
    end
    if wide then ty = y + 1 end
    -- (the columns: stat, value, IV, EV; the nature's raised stat red with an up mark, its lowered blue)
    local vx, ivx = tx + tw * 0.34, tx + tw * 0.52
    -- (the values' right edge: grown, nearer the IV pills, so the stats' names have room; vx + 6 at 100%)
    local vr = vx + 6 + min(grown() * 20, max(0, ivx - 3 - (vx + 6)))
    K.text(word("sum.col.iv"), ivx - 2, ty, 3, C.faint, "center", 10)
    K.text(word("sum.col.ev"), ivx + 10, ty, 3, C.faint)
    ty = ty + 4.4
    for i = 1, #R.rows do
      local r = R.rows[i]
      local ein = rowIn(clock, i)
      rise(ein, 3)
      local ry2 = ty + (i - 1) * 6.6
      if i % 2 == 0 then
        K.col(C.track, 0.35)
        K.box("fill", K.R(tx, ry2 - 0.9, tw, 6.4), 2)
      end
      K.col(STAT_C[i] or C.faint)
      G.circle("fill", K.X(tx + 1.6), K.Y(ry2 + 2.1), 0.9 * K.sc)
      local nc = r.nature == 1 and C.up or (r.nature == -1 and C.down or C.soft)
      -- (the stat's name kept clear of its value, the nature's mark beside it)
      local vs = num(r.value)
      -- (grown, it may go a little under its 100% size: the column is tight even then in some languages)
      local ns = K.textScale() == 1 and 3.3
        or K.fit(word(r.key), 3.3, vr - K.width(vs, 3.6) - 1.5 - (tx + 3.6) - (r.nature and 3.4 or 0))
      K.text(word(r.key), tx + 3.6, ry2 + 0.2, ns, nc)
      if r.nature then
        local ax = tx + 4.6 + K.width(word(r.key), ns)
        K.col(nc)
        if r.nature == 1 then
          G.polygon("fill", K.X(ax), K.Y(ry2 + 3.2), K.X(ax + 1.2), K.Y(ry2 + 1.2), K.X(ax + 2.4), K.Y(ry2 + 3.2))
        else
          G.polygon("fill", K.X(ax), K.Y(ry2 + 1.4), K.X(ax + 2.4), K.Y(ry2 + 1.4), K.X(ax + 1.2), K.Y(ry2 + 3.4))
        end
      end
      K.bold(vs, tx, ry2, 3.6, C.ink, "right", vr - tx)
      local best = r.iv >= (R.ivMax or 31)
      local ivw = 8
      K.col(best and C.gold or C.track, best and 1 or 0.9)
      K.box("fill", K.R(ivx - ivw / 2 + 3, ry2 - 0.2, ivw, 4.6), 2.3)
      K.text(num(r.iv), ivx - ivw / 2 + 3, ry2 + 0.3, 3.2, best and C.white or C.ink, "center", ivw)
      local ex = ivx + 10
      local ew = x + w - ex - 12
      bar(ex, ry2 + 1.3, ew, 1.8, r.ev / max(1, R.evMax or 252), STAT_C[i] or C.faint)
      K.text(num(r.ev), ex + ew + 0.5, ry2 + 0.3, 3.2, C.soft, "right", 11)
      settle(ein)
    end
    ty = ty + #R.rows * 6.6
    return max(ty, wide and (ry + rad + 16) or ty) - y
  end

  -- ------- Moves: the four, then the chosen one's card
  local function ppColour(m)
    if m.pp <= 0 then return C.ppOut end
    if m.pp <= floor(m.maxPp / 4) then return C.ppLow end
    if m.pp <= floor(m.maxPp / 2) then return C.ppMid end
    return C.ink
  end
  local function movesTab(x, y, w, R, S, clock, dt)
    local moves = R.moves
    -- (choosing one to forget: the question above, the move it would learn as a fifth row)
    local learn = S.learn
    local n = #moves + (learn and 1 or 0)
    local rh = 10
    local yy = y
    if learn then
      local q = word("sum.forget")
      K.bold(q, x + 1.5, yy, K.fit(q, 4, w - 3), C.accent)
      yy = yy + 6.5
    end
    if n == 0 then
      K.text(word("dex.moves.none"), x + 2, yy + 1, 3.6, C.soft)
      return 8
    end
    -- (the chosen one's highlight gliding from row to row)
    local sel = S.move
    if sel then
      if mv.movePrev == nil then mv.moveY = sel end
      mv.moveY, mv.movePrev = approach(mv.moveY, sel, dt, 22), sel
      local hb = K.R(x - 0.5, yy + (mv.moveY - 1) * rh - 0.6, w + 1, rh - 0.4)
      K.col(C.accent, 0.12)
      K.box("fill", hb, 2.5)
      K.ring(hb, 2.5, C.accent, 0.9, 0.6)
    else
      mv.movePrev = nil
    end
    for i = 1, n do
      local m = moves[i] or learn
      local ry = yy + (i - 1) * rh
      local ein = rowIn(clock, i)
      rise(ein, 3)
      local nx = x
      if i > #moves then
        -- (the new one: a line above it, its tag)
        K.hairline(x + 1, ry - 0.4, w - 2)
        local tag = word("sum.new")
        local tw = K.width(tag, 2.8) + 4
        K.col(C.swap)
        K.box("fill", K.R(x + 1.5, ry + 1.9, tw, 4.4), 2.2)
        K.bold(tag, x + 1.5, ry + 2.4, 2.8, C.white, "center", tw)
        nx = x + tw + 1.5
      end
      if S.swap == i then
        local sb = K.R(x - 0.5, ry - 0.6, w + 1, rh - 0.4)
        K.col(C.swap, 0.14 + 0.08 * sin(clock * 6))
        K.box("fill", sb, 2.5)
        K.ring(sb, 2.5, C.swap, 0.9, 0.7)
      end
      local pw = pill(m.typeId, m.typeName, nx + 1.5, ry + 1.8, 5.4, 3.1) + (nx - x)
      K.bold(m.name, x + 3.5 + pw, ry + 1.5, K.fit(m.name, 4, w - pw - 30), C.ink)
      if not m.status then
        K.col(m.physical and C.phys or C.spec)
        G.circle("fill", K.X(x + w - 26), K.Y(ry + 4.3), 1.1 * K.sc)
      end
      K.text(word("sum.pp"), x + w - 23, ry + 2.1, 3, C.soft)
      K.text(m.ppText, x + w - 18, ry + 1.6, 3.6, ppColour(m), "right", 16.5)
      local pc = ppColour(m)
      bar(x + w - 18, ry + 6.5, 16.5, 1, m.maxPp > 0 and m.pp / m.maxPp or 0, pc == C.ink and C.exp or pc)
      K.addHit(K.R(x, ry, w, rh), "win", A.SUM_MOVE + i, pageArea)
      settle(ein)
    end
    yy = yy + n * rh + 2
    -- (an HM the game won't let go)
    if S.hm then
      local hm = word("sum.hm")
      K.text(hm, x + 1.5, yy, K.fit(hm, 3.4, w - 3), C.ppOut)
      yy = yy + 6
    end
    local m = sel and (moves[sel] or (sel == n and learn) or nil)
    if not m then
      K.text(word("sum.movesHint"), x + 1.5, yy, K.fit(word("sum.movesHint"), 3.4, w - 3), C.soft)
      return yy + 6 - y
    end
    -- (the chosen one: power, accuracy, category; its words; its contest side)
    local cw = (w - 3) / 3
    local cat = word(m.status and "sum.cat.status" or (m.physical and "sum.cat.physical" or "sum.cat.special"))
    for j = 1, 3 do
      local bx = x + (j - 1) * (cw + 1.5)
      K.col(C.white, 0.45 * K.getFade())
      K.box("fill", K.R(bx, yy, cw, 11), 2.5)
      local lab = word(j == 1 and "dex.col.power" or (j == 2 and "dex.col.acc" or "sum.cat"))
      K.text(lab, bx + 2, yy + 1, roomy(lab, 2.9, cw - 4), C.soft)
      local v = j == 1 and m.powerText or (j == 2 and m.accText or cat)
      K.bold(v, bx + 2, yy + 5, K.fit(v, 3.8, cw - 4), C.ink)
    end
    yy = yy + 13
    if m.desc and m.desc ~= "" then
      local lines = wrap(S, "mv", m.desc, w - 3, 3.6)
      yy = yy + drawLines(lines, x + 1.5, yy, 3.6, C.ink) + 2
    end
    local c = m.contest
    if c then
      yy = yy + 1
      K.hairline(x + 1, yy - 1.2, w - 2)
      local cc = CONTEST_C[c.category] or CONTEST_C[0]
      local cpw = K.width(c.categoryName, 3.2) + 5
      K.col(cc)
      K.box("fill", K.R(x + 1.5, yy + 0.6, cpw, 5), 2.5)
      K.text(c.categoryName, x + 1.5, yy + 1.2, 3.2, C.white, "center", cpw)
      local hx = x + 4 + cpw
      -- (Appeal over Jam, apart as the text grows)
      local g = grown() * 3
      K.text(word("sum.appeal"), hx, yy + 0.2, 3, C.soft)
      K.text(word("sum.jam"), hx, yy + 4.4 + g, 3, C.soft)
      local hx2 = hx + max(K.width(word("sum.appeal"), 3), K.width(word("sum.jam"), 3)) + 2
      for k = 1, 8 do
        heart(hx2 + (k - 1) * 3.6, yy + 0.4, 3, k <= c.appeal and C.heart or C.track)
        heart(hx2 + (k - 1) * 3.6, yy + 4.6 + g, 3, k <= c.jam and C.ink or C.track)
      end
      yy = yy + 10 + g
      if c.desc ~= "" then
        local lines = wrap(S, "cmv", c.desc, w - 3, 3.4)
        yy = yy + drawLines(lines, x + 1.5, yy, 3.4, C.soft) + 1
      end
    end
    return yy - y
  end

  -- the tabs' switch and the chosen one's card -> its height
  local function tabCard(x, y, w, R, S, clock, dt)
    mv.tabX = approach(mv.tabX, S.tab, dt, 18)
    K.glassSwitch(x, y, w, 8, mv.tabX, "win", A.SUM_TAB + 1, word(TABS[1]), A.SUM_TAB + 2, word(TABS[2]),
      A.SUM_TAB + 3, word(TABS[3]), 4.2)
    local cy = y + 10
    local ch = max(12, S.cardH or 30)
    K.glass(K.R(x, cy, w, ch), 4)
    local inner
    if S.tab == 1 then inner = infoTab(x + 3, cy + 3, w - 6, R, S, clock)
    elseif S.tab == 2 then inner = R.egg and 0 or statsTab(x + 3, cy + 3, w - 6, R, S, clock, dt)
    else inner = R.egg and 0 or movesTab(x + 3, cy + 3, w - 6, R, S, clock, dt) end
    S.cardH = inner + 6
    return 10 + S.cardH
  end

  -- ------- the whole page

  -- (the Pokémon's words made once when it's shown: its numbers' texts)
  local function remake(R)
    vt.hp = R.egg and "" or (tostring(R.hp) .. " / " .. tostring(R.maxHp))
    vt.exp = R.exp and tostring(R.exp) or "—"
    vt.next = R.expNext and tostring(R.expNext) or "—"
  end

  function V.draw(body, clock, portrait, S)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    bodyNow = body
    G = K.graphics()
    local R = S.rec
    local dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT = clock
    if not R then return end
    if R ~= mv.rec then
      -- (another Pokémon: everything settles in again from its last place; the same one changed (a move
      -- swapped): only its numbers)
      local again = mv.rec ~= nil and mv.rec.mon == R.mon
      mv.rec = R
      if not again then mv.pageAt, mv.tabAt = clock, clock end
      remake(R)
    end
    if S.tab ~= mv.tab then
      if mv.tab ~= nil then mv.tabAt = clock end
      mv.tab = S.tab
    end
    -- (the colours: its types', slate for an egg; eased, snapped the first time)
    local t1 = not R.egg and R.types[1] and TYPE[R.types[1].id] or nil
    local t2 = t1 and (R.types[2] and TYPE[R.types[2].id] or t1) or C.slate2
    t1 = t1 or C.slate
    local rate = mv.coloured and 8 or 1000
    mv.coloured = true
    mv.r, mv.g, mv.b = approach(mv.r, t1[1] / 255, dt, rate), approach(mv.g, t1[2] / 255, dt, rate),
      approach(mv.b, t1[3] / 255, dt, rate)
    local k2 = t2 == t1 and 0.35 or 0
    mv.r2 = approach(mv.r2, (t2[1] + (255 - t2[1]) * k2) / 255, dt, rate)
    mv.g2 = approach(mv.g2, (t2[2] + (255 - t2[2]) * k2) / 255, dt, rate)
    mv.b2 = approach(mv.b2, (t2[3] + (255 - t2[3]) * k2) / 255, dt, rate)
    K.backdrop(body, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2)
    -- (the type's own pictures drifting behind the glass: its first type's field, its second's large in a
    -- corner; an egg's none)
    local Art = env.typeArt
    if Art and not R.egg and R.types[1] then
      local ta, tb = R.types[1].id, (R.types[2] or R.types[1]).id
      Art.scatter("type", ta, body, clock, C.white, 0.3)
      Art.type(tb, x + w * 0.86, y + h * 0.78, h * 0.62, -0.15 + 0.08 * sin(clock * 0.35), C.white, 0.18)
      K.scissor(body)
    end
    drawTop(x + M, y + 1, w - M * 2, S)
    local top = y + TOP_H + 2
    local ah = y + h - M - top
    pageArea = K.R(x, top, w, ah + M)
    mv.top = approach(mv.top, S.top, dt, 18)
    -- (wide: the Pokémon's pane gives up height down to HERO_MIN so its column fits; past that, one column)
    local vh = vitalsH(R)
    local heroH = max(HERO_MIN, min(HERO_H, ah - (vh > 0 and vh + GAP or 0)))
    if w >= NARROW and heroH + (vh > 0 and vh + GAP or 0) <= ah then
      -- (the Pokémon on the left, its tabs on the right: the right side scrolls)
      local lw = max(96, min(floor(w * 0.42), 160))
      local lx, rx = x + M, x + M + lw + GAP + 1
      local rw = x + w - M - 2 - rx
      K.scissor(pageArea)
      local yy = top
      local c0 = enter(clock, 0)
      rise(c0, 6)
      yy = yy + hero(lx, yy, lw, heroH, R, S, clock) + GAP
      settle(c0)
      local c1 = enter(clock, 0.06)
      rise(c1, 7)
      vitals(lx, yy, lw, R, clock)
      settle(c1)
      local c3 = enter(clock, 0.08)
      rise(c3, 7)
      local th = tabCard(rx, top - mv.top, rw, R, S, clock, dt)
      settle(c3)
      S.h, S.vis = th, ah
      S.top = max(0, min(S.top, max(0, th - ah)))
      K.scissor(bodyNow)
      K.scrollbar(x + w - M + 0.4, top, ah, mv.top, ah, max(ah, th))
      return
    end
    -- (narrow: one column, all of it scrolling)
    K.scissor(pageArea)
    local cx, cw = x + M, w - M * 2 - 2
    local yy = top - mv.top
    local c0 = enter(clock, 0)
    rise(c0, 6)
    yy = yy + hero(cx, yy, cw, HERO_H, R, S, clock) + GAP
    settle(c0)
    local c1 = enter(clock, 0.06)
    rise(c1, 7)
    vitals(cx, yy, cw, R, clock)
    settle(c1)
    yy = yy + (vh > 0 and vh + GAP or 0)
    local c3 = enter(clock, 0.14)
    rise(c3, 7)
    yy = yy + tabCard(cx, yy, cw, R, S, clock, dt)
    settle(c3)
    S.h, S.vis = yy + mv.top - top, ah
    S.top = max(0, min(S.top, max(0, S.h - ah)))
    K.scissor(bodyNow)
    K.scrollbar(x + w - M + 0.4, top, ah, mv.top, ah, max(ah, S.h))
  end

  return V
end
