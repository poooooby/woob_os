-- The Pokédex window's drawing (src/apps/pokedex.lua holds its state and input). Nothing here makes a
-- table, a closure or a string while it draws: the words are the model's (src/dex.lua, made when a
-- Pokémon is chosen), the lines a text wraps to are made when the text or the width changes, numbers
-- through K.textCache, the radar one kept mesh.
--
-- Its motion, all numbers kept here and eased each frame (nothing timed by the host):
--   the grid's cells rise in, one after another, when it opens or the dex changes; the chosen cell's
--   highlight glides from cell to cell; both lists scroll smoothly to where the D-pad or the wheel sent
--   them; the switches' thumbs slide; a newly chosen Pokémon's page settles in card by card, its
--   backdrop's colour turning to its type's, its picture popping up on its shadow, its words sliding in;
--   the radar morphs from the last Pokémon's stats and the numbers count with it; the gender bar fills;
--   a tab's or a list's rows fade in in turn; narrow, the page slides in over the grid and back out.
--
--   View(K, env, T, st, A, KINDS) -> { draw(body, clock, portrait) }

local floor, max, min, ceil, sin, cos, pi, abs, exp = math.floor, math.max, math.min, math.ceil, math.sin, math.cos,
  math.pi, math.abs, math.exp

local M, GAP = 3, 2
local CELL_MIN = 25
local NARROW = 190          -- narrower than this (units): the grid and the page take turns
local STAT_MAX = 180        -- the radar's rim (a base stat over it touches the rim)
local BAR_MAX = 200         -- the stat bars' full length
local WIDE_STATS = 96       -- a page this wide: the radar beside six bars; narrower, the radar labelled
-- (the radar's corners from the top, clockwise: HP, Attack, Defense, Speed, Sp. Def, Sp. Atk; the page's
-- stats are HP, Atk, Def, SpA, SpD, Spe)
local CORNER_STAT = { 1, 2, 3, 6, 5, 4 }
local STAT_KEY = { "dex.stat.hp", "dex.stat.atk", "dex.stat.def", "dex.stat.spa", "dex.stat.spd", "dex.stat.spe" }
local C = {
  body = { 242, 242, 247 }, card = { 255, 255, 255 }, ink = { 28, 28, 30 }, soft = { 112, 112, 120 },
  faint = { 170, 170, 178 }, accent = { 10, 132, 255 }, chosen = { 235, 244, 255 },
  sil = { 40, 44, 56 }, silCard = { 228, 230, 238 }, ball = { 238, 64, 54 }, white = { 255, 255, 255 },
  black = { 0, 0, 0 }, male = { 10, 132, 255 }, female = { 255, 55, 95 }, track = { 118, 118, 128, 0.16 },
  grid = { 120, 124, 140, 0.32 }, heroDark = { 58, 62, 80 }, heroDarkFoot = { 26, 28, 38 },
  phys = { 236, 104, 60 }, spec = { 90, 120, 230 }, slate = { 120, 132, 178 }, slate2 = { 150, 120, 190 },
}
-- (a backdrop's light from the top and shade at the foot, over its colour)
local SHADE_TOP, SHADE_FOOT = { 255, 255, 255, 0.28 }, { 0, 0, 0, 0.16 }
-- the types' colours (the game's ids; 18 WoobleDex's Fairy)
local TYPE = {
  [0] = { 168, 168, 120 }, [1] = { 192, 48, 40 }, [2] = { 168, 144, 240 }, [3] = { 160, 64, 160 },
  [4] = { 224, 192, 104 }, [5] = { 184, 160, 56 }, [6] = { 168, 184, 32 }, [7] = { 112, 88, 152 },
  [8] = { 184, 184, 208 }, [9] = { 104, 160, 144 }, [10] = { 240, 128, 48 }, [11] = { 104, 144, 240 },
  [12] = { 120, 200, 80 }, [13] = { 248, 208, 48 }, [14] = { 248, 88, 136 }, [15] = { 152, 216, 216 },
  [16] = { 112, 56, 248 }, [17] = { 112, 88, 72 }, [18] = { 238, 153, 172 },
}
-- (each stat's colour: the radar's corners and the bars)
local STAT_C = { { 255, 89, 89 }, { 245, 152, 90 }, { 240, 205, 80 }, { 120, 160, 245 }, { 120, 200, 110 },
                 { 245, 120, 165 } }
-- the Size tab's chart: the gridlines' steps (metres on the left, feet ticked on the right; the first step
-- giving at most five lines), the trainer's height in words, the chart's height and its side columns
local STEPS_M = { 0.1, 0.2, 0.25, 0.5, 1, 2, 2.5, 5, 10, 20, 25, 50, 100 }
local STEPS_FT = { 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500 }
local TRAINER_I, TRAINER_M = "5'08\"", "1.7 m"
local CHART_H, CHART_L, CHART_R, CHART_GAP = 80, 11, 9, 7
local FT_PER_M = 3.28084
local function niceStep(list, top, most)
  for i = 1, #list do
    if top / list[i] <= most then return list[i] end
  end
  return list[#list]
end

-- ------- easing (t: 0 .. 1)
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
-- (a value followed smoothly: the same speed whatever the frame rate)
local function approach(cur, target, dt, rate)
  local v = cur + (target - cur) * (1 - exp(-dt * rate))
  if abs(target - v) < 0.002 then return target end
  return v
end

return function(K, env, T, st, A, KINDS)
  local V = {}
  local G = nil               -- (the host's graphics, taken each frame)
  local bodyNow, pageArea = nil, nil
  local AB = { "ab1", "ab2", "ab3", "ab4", "ab5", "ab6" }
  local EMPTY = { types = {}, stats = { 0, 0, 0, 0, 0, 0 } }
  local num = K.textCache(function(n) return tostring(n) end)
  -- (the chart's axis words: metres kept by centimetres, feet by half feet)
  local mLabel = K.textCache(function(cm)
    if cm % 100 == 0 then return ("%d m"):format(floor(cm / 100)) end
    if cm % 10 == 0 then return ("%.1f m"):format(cm / 100) end
    return ("%.2f m"):format(cm / 100)
  end)
  local ftLabel = K.textCache(function(halves)
    if halves % 2 == 0 then return ("%d ft"):format(floor(halves / 2)) end
    return ("%.1f ft"):format(halves / 2)
  end)
  local mesh = nil
  local PX, PY, HX, HY = { 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0 }
  local CHX, CHW = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
  -- (the moves' chips' words' keys, made once)
  local KIND_KEY = {}
  for i = 1, #KINDS do KIND_KEY[i] = "dex.moves." .. KINDS[i] end

  -- the motion's numbers (see the top)
  local mv = {
    first = true, gridAt = 0, pageAt = 0, tabAt = 0, listAt = 0,
    entry = nil, mi = nil, tab = nil, kind = nil,
    top = 0, page = 0, curR = nil, curC = 0, curCols = 0,
    mode = 1, tabX = 1, kindX = 1, push = 0,
    r = 0.6, g = 0.6, b = 0.6, r2 = 0.6, g2 = 0.6, b2 = 0.6,
  }
  V.motion = mv

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

  -- something settling in: drawn `(1 - e) * dy` units lower and at `e` of itself (the kit's fade, so
  -- the glass and the backdrop show through it); `settle(e)` after it, always with the same `e`
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

  local glass = K.glass
  local function backdrop(b, clock) K.backdrop(b, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2) end

  -- a type's pill -> its width (`ring`: a light edge, on a backdrop of its own colour)
  local function pill(id, name, x, y, h, size, a, ring)
    local pw = K.width(name, size) + 5
    local b = K.R(x, y, pw, h)
    K.col(TYPE[id] or C.faint, a)
    K.box("fill", b, h / 2)
    if ring then K.ring(b, h / 2, C.white, 0.55 * (a or 1), 0.4) end
    K.text(name, x, y + (h - size * 1.2) / 2, size, C.white, "center", pw, a)
    return pw
  end

  -- a small Poké Ball (caught)
  local function ballMark(cx, cy, r)
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
  -- a big Poké Ball's outline turning slowly (the backdrop's watermark), r units round cx, cy
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
  -- (♀ / ♂ drawn: the fonts have no signs)
  local function sexMark(sex, x, y, s, a)
    local c = sex == "f" and C.female or C.male
    K.col(c, a)
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

  -- ------- the search: its button by the grid's top, its keyboard on a glass sheet

  -- a magnifier, r units round cx, cy
  local function magnifier(cx, cy, r, c)
    K.col(c)
    G.setLineWidth(max(1, r * 0.3 * K.sc))
    local ox, oy = cx - r * 0.22, cy - r * 0.22
    G.circle("line", K.X(ox), K.Y(oy), r * 0.72 * K.sc)
    G.line(K.X(ox + r * 0.52), K.Y(oy + r * 0.52), K.X(cx + r), K.Y(cy + r))
  end
  local function searchButton(bx, by, s)
    local b = K.R(bx, by, s, s)
    local on = st.focus == "searchBtn" and not st.kb
    K.col(on and C.accent or C.white, on and 0.95 or 0.6)
    K.box("fill", b, s / 2)
    K.ring(b, s / 2, C.white, 0.85, 0.3)
    if on then K.focusRing(b, s / 2) end
    magnifier(bx + s / 2, by + s / 2, s * 0.3, on and C.white or C.accent)
    K.addHit(b, "win", A.SEARCH)
  end
  -- Delete's mark: a key's outline pointing left, a cross in it
  local function backspace(cx, cy, r, c)
    K.col(c)
    G.setLineWidth(max(1, r * 0.2 * K.sc))
    local l, rr, t, b = cx - r * 1.3, cx + r * 1.1, cy - r * 0.75, cy + r * 0.75
    G.line(K.X(l), K.Y(cy), K.X(l + r * 0.6), K.Y(t), K.X(rr), K.Y(t), K.X(rr), K.Y(b), K.X(l + r * 0.6), K.Y(b),
      K.X(l), K.Y(cy))
    local xc, d = cx + r * 0.2, r * 0.32
    G.line(K.X(xc - d), K.Y(cy - d), K.X(xc + d), K.Y(cy + d))
    G.line(K.X(xc - d), K.Y(cy + d), K.X(xc + d), K.Y(cy - d))
  end
  local KEY_GREY, KEY_SHADE = { 206, 210, 220 }, { 0, 0, 0, 0.13 }
  local function drawSearch(body, clock)
    local kb = st.kb
    if not kb then
      mv.kb = nil
      return
    end
    if mv.kb ~= kb then mv.kb, mv.kbAt, mv.typedSeen, mv.typedClock = kb, clock, kb.typedAt, -1 end
    if kb.typedAt ~= mv.typedSeen then mv.typedSeen, mv.typedClock = kb.typedAt, clock end
    local KB = st.KB
    local e = outCubic((clock - mv.kbAt) / 0.24)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    K.scissor(body)
    K.col(C.black, 0.22 * e)
    K.box("fill", body)
    K.addHit(body, "win", A.KB_SCRIM)
    local g = K.textScale() - 1
    local kh, gap = 9 + g * 3, 1.8
    local fh = 12 + g * 3
    local sw = min(w - M * 2, 236)
    local sh = 3 + fh + 3 + 5 * kh + 4 * gap + 3
    local sx = x + (w - sw) / 2
    local sy = y + h - sh - M + (1 - e) * (sh + M + 6)
    local sb = K.R(sx, sy, sw, sh)
    K.glass(sb, 6, 0.95)
    K.addHit(sb, "win", 0)
    -- (the field: the words typed and a blinking caret, or what to type; the match at its right, a tap on
    -- it goes there)
    local fb = K.R(sx + 3, sy + 3, sw - 6, fh)
    K.col(C.white, 0.92)
    K.box("fill", fb, fh / 2)
    K.ring(fb, fh / 2, C.accent, 0.9, 0.6)
    magnifier(fb[1] + 5.5, fb[2] + fh / 2, 2.6, C.soft)
    local ts = 5
    local tx, ty = fb[1] + 10, fb[2] + (fh - ts * 1.2) / 2
    local tw = 0
    if kb.text == "" then
      K.text(word("dex.search.place"), tx, ty, ts, C.faint)
    else
      K.bold(kb.text, tx, ty, ts, C.ink)
      tw = K.width(kb.text, ts) + 0.4
    end
    if floor(clock * 2.2) % 2 == 0 then
      K.col(C.accent)
      G.rectangle("fill", K.X(tx + tw + 0.3), K.Y(ty), max(1, 0.5 * K.sc), ts * 1.2 * K.sc)
    end
    local en = kb.hit and st.list[kb.hit]
    if en then
      local name = en.seen and en.name or "???"
      local ns, nums = 4.4, 3.6
      local nmw = K.width(en.numText, nums)
      local is = fh - 1
      local mw = is + 1 + nmw + 1.5 + K.width(name, ns) + 4
      local mb = K.R(fb[1] + fb[3] - mw - 1, fb[2] + 1, mw, fh - 2)
      K.col(C.accent, 0.12)
      K.box("fill", mb, (fh - 2) / 2)
      if env.monIcon then
        if en.seen then
          env.monIcon(en.sp, mb[1] + 1, fb[2] + 0.2, is, floor(clock * 3) % 2, 1, 1, 1, K.getFade())
        else
          env.monIcon(en.sp, mb[1] + 1, fb[2] + 0.2, is, 0, 0.16, 0.17, 0.22, 0.5 * K.getFade())
        end
        K.rescissor()
        K.scissor(body)
      end
      K.text(en.numText, mb[1] + is + 1, fb[2] + (fh - nums * 1.2) / 2, nums, C.soft)
      K.bold(name, mb[1] + is + 1 + nmw + 1.5, fb[2] + (fh - ns * 1.2) / 2, ns, en.seen and C.ink or C.faint)
      K.addHit(mb, "win", A.KB_GO)
    elseif kb.text ~= "" then
      K.text(word("dex.search.none"), fb[1], fb[2] + (fh - 4 * 1.2) / 2, 4, C.soft, "right", fb[3] - 4)
    end
    -- (the keys: white letters and digits, grey Delete and space, Go in the accent; the D-pad's key ringed,
    -- the one just typed flashing)
    local ky0 = sy + 3 + fh + 3
    local unit = (sw - 6) / 10
    for k = 1, #KB.keys do
      local key = KB.keys[k]
      local kx = sx + 3 + KB.x0[k] * unit + 0.8
      local kw = KB.w[k] * unit - 1.6
      local kyy = ky0 + (KB.row[k] - 1) * (kh + gap)
      local kbx = K.R(kx, kyy, kw, kh)
      local go = key == "GO"
      K.col(KEY_SHADE)
      K.box("fill", K.R(kx, kyy + 0.5, kw, kh), 2)
      if go then K.col(C.accent) elseif key == "DEL" or key == "SPACE" then K.col(KEY_GREY) else K.col(C.white) end
      K.box("fill", kbx, 2)
      if kb.typedK == k and clock - mv.typedClock < 0.14 then
        K.col(C.accent, 0.35)
        K.box("fill", kbx, 2)
      end
      if k == kb.cur then K.ring(kbx, 2, C.accent, 1, 0.8) end
      if key == "DEL" then
        backspace(kx + kw / 2, kyy + kh / 2, kh * 0.3, C.ink)
      else
        local label, ls = key, 4.6
        if key == "SPACE" then label, ls = word("dex.search.space"), 4
        elseif go then label, ls = word("dex.search.go"), 4.2 end
        K.text(label, kx, kyy + (kh - ls * 1.2) / 2, K.fit(label, ls, kw - 2), go and C.white or C.ink, "center", kw)
      end
      K.addHit(kbx, "win", A.KEY + k)
    end
  end

  -- ------- the grid

  local function drawGrid(x, y, w, h, clock, dt)
    local book, list = st.book, st.list
    local hh = 9
    local counts = book.counts[book.modes[st.mi]]
    local swW = min(w * 0.58, 84, w - 46)
    if #book.modes > 1 then
      mv.mode = approach(mv.mode, st.mi, dt, 18)
      K.glassSwitch(x, y, swW, hh, mv.mode, "win", A.MODE + 1, st.modeWords[1], A.MODE + 2,
        st.modeWords[2], nil, nil, 4.3)
    else
      K.bold(st.modeWords[1] or "", x, y + 2, 5, C.ink)
      swW = K.width(st.modeWords[1] or "", 5)
    end
    searchButton(x + swW + 3, y, hh)
    local n = #list
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
      K.col(C.soft)
      G.setLineWidth(max(1, 0.3 * K.sc))
      G.circle("line", K.X(cx - 3), K.Y(y + 4.8), 1.8 * K.sc)
      G.circle("fill", K.X(cx - 3), K.Y(y + 4.8), 0.8 * K.sc)
    end
    -- (the dex's progress: seen pale, caught full, filling as it opens)
    local py = y + hh + 2
    K.col(C.white, 0.5)
    K.box("fill", K.R(x, py, w, 1.4), 0.7)
    if counts and n > 0 then
      local e = outCubic((clock - mv.gridAt - 0.1) / 0.9)
      local sw = w * counts.seen / n * e
      if sw > 0.2 then
        K.col(C.accent, 0.3)
        K.box("fill", K.R(x, py, max(1.4, sw), 1.4), 0.7)
      end
      local cw = w * counts.caught / n * e
      if cw > 0.2 then
        K.col(C.accent)
        K.box("fill", K.R(x, py, max(1.4, cw), 1.4), 0.7)
      end
    end
    local gy = py + 4
    local gh = y + h - gy
    local cols = max(2, floor((w + GAP) / (CELL_MIN + GAP)))
    local cw = (w - (cols - 1) * GAP) / cols
    local ch = max(22, cw * 1.08)
    st.cols, st.cellH = cols, ch + GAP
    local rows = ceil(n / cols)
    st.visRows = max(1, floor((gh + GAP) / (ch + GAP)))
    -- (following the chosen one when the D-pad moved it; free while scrolled by hand)
    if st.follow then
      local r = floor((st.sel - 1) / cols)
      if r < st.gridTop then st.gridTop = r end
      if r > st.gridTop + st.visRows - 1 then st.gridTop = r - st.visRows + 1 end
    end
    st.gridTop = max(0, min(max(0, rows - st.visRows), st.gridTop))
    if mv.curR == nil or mv.curCols ~= cols then
      mv.top = st.gridTop
    else
      mv.top = approach(mv.top, st.gridTop, dt, 20)
    end
    local top = mv.top
    local area = K.R(x - 1.5, gy - 1.5, w + 3, gh + 1.5)
    K.scissor(area)
    -- (the chosen cell's highlight: it glides from one to the next, over the cells)
    local sr, sc = floor((st.sel - 1) / cols), (st.sel - 1) % cols
    if mv.curR == nil or mv.curCols ~= cols then
      mv.curR, mv.curC, mv.curCols = sr, sc, cols
    else
      mv.curR, mv.curC = approach(mv.curR, sr, dt, 26), approach(mv.curC, sc, dt, 26)
    end
    local first = floor(top)
    local frame = floor(clock * 3) % 2
    local since = clock - mv.gridAt
    local hopT = clock - mv.pageAt
    local hop = (hopT >= 0 and hopT < 0.36) and sin(hopT / 0.36 * pi) * 2 or 0
    for r = first, min(rows - 1, first + st.visRows + 1) do
      local cy = gy + (r - top) * (ch + GAP)
      for c = 0, cols - 1 do
        local i = r * cols + c + 1
        local e = list[i]
        if not e then break end
        local cx = x + c * (cw + GAP)
        -- (rising in, one after another, as the grid opens)
        local ein = since < 1.6 and outCubic((since - ((r - first) * cols + c) * 0.022) / 0.34) or 1
        rise(ein, 6)
        local cb = K.R(cx, cy, cw, ch)
        local chosen = i == st.sel
        -- (each a pane of glass: clear while unseen, frosted once seen, brightest when chosen)
        K.col(C.white, e.seen and (chosen and 0.8 or 0.42) or 0.16)
        K.box("fill", cb, 3)
        K.ring(cb, 3, C.white, e.seen and 0.75 or 0.4, 0.3)
        local is = min(cw - 4, ch - 11)
        local ix, iy = cx + (cw - is) / 2, cy + 5.5 + (ch - 11 - is) / 2
        if e.seen and e.t1 and TYPE[e.t1] then
          -- (the type's soft spot behind the icon)
          K.col(TYPE[e.t1], chosen and 0.3 or 0.16)
          G.circle("fill", K.X(ix + is / 2), K.Y(iy + is * 0.55), is * 0.42 * K.sc)
        end
        K.text(e.numText, cx + 2, cy + 1.5, 3.2, chosen and C.accent or C.soft)
        if e.caught then ballMark(cx + cw - 3.2, cy + 3.4, 1.7) end
        if env.monIcon then
          if e.seen then
            env.monIcon(e.sp, ix, iy - (chosen and hop or 0), is, chosen and frame or 0, 1, 1, 1, K.getFade())
          else
            env.monIcon(e.sp, ix, iy, is, 0, 0.16, 0.17, 0.22, 0.5 * K.getFade())
          end
        end
        local name = e.seen and e.name or "???"
        local fs = K.fit(name, 3.4, cw - 2)
        if chosen and e.seen then
          K.bold(name, cx + 1, cy + ch - 5, fs, C.ink, "center", cw - 2)
        else
          K.text(name, cx + 1, cy + ch - 5, fs, e.seen and C.ink or C.faint, "center", cw - 2)
        end
        settle(ein)
        K.addHit(cb, "win", A.CELL + i, area)
      end
    end
    if n > 0 then
      local hb = K.R(x + mv.curC * (cw + GAP) - 0.6, gy + (mv.curR - top) * (ch + GAP) - 0.6, cw + 1.2, ch + 1.2)
      K.col(C.accent, 0.1)
      K.box("fill", hb, 3.5)
      K.ring(hb, 3.5, C.accent, st.focus == "grid" and 1 or 0.45, 0.8)
    end
    K.scissor(bodyNow)
    K.scrollbar(x + w + 1.4, gy, gh, min(top, max(0, rows - st.visRows)), st.visRows, rows)
  end

  -- ------- the page

  -- (how far a card or a word has settled in: the page's i-th, `delay` seconds after the choice)
  local function enter(clock, delay, dur) return outCubic((clock - mv.pageAt - delay) / (dur or 0.4)) end

  local function hero(x, y, w, e, pg, clock, dt)
    local h = 50
    local b = K.R(x, y, w, h)
    K.shadow(b, 5, 1.4, 0.1)
    if not e.seen then
      K.col(C.heroDark, 0.78)
      K.box("fill", b, 5)
      K.grad(b, 5, SHADE_TOP, SHADE_FOOT)
      K.ring(b, 5, C.white, 0.35, 0.35)
      if env.monIcon then env.monIcon(e.sp, x + 5, y + 6, 38, 0, 0, 0, 0, 0.45) end
      K.label(e.numText, x + 50, y + 13, 3.6, C.white, nil, nil, 0.6)
      K.bold("???", x + 50, y + 18, 8, C.white)
      return h
    end
    -- (glass tinted in its first type's colour, turned to from the last one's: V.draw eases mv.r/g/b)
    G.setColor(mv.r, mv.g, mv.b, 0.74)
    K.box("fill", b, 5)
    K.grad(b, 5, SHADE_TOP, SHADE_FOOT)
    K.ring(b, 5, C.white, 0.6, 0.4)
    -- (a Poké Ball turning behind it all, faint; kept inside the backdrop)
    G.intersectScissor(K.X(x), K.Y(y), w * K.sc, h * K.sc)
    ballMarkBig(x + w - h * 0.3, y + h * 0.62, h * 0.6, clock * 0.18, 0.13)
    K.scissor(pageArea)
    -- (its picture popping up on its shadow, with a light behind it)
    local t = clock - mv.pageAt
    local pop = 0.8 + 0.2 * outBack(t / 0.42)
    local fa = outCubic(t / 0.18)
    local ps = 44
    local pcx, pcy = x + 3 + ps / 2, y + h / 2 + 1
    K.glow(pcx, pcy, 26, 22, C.white, 0.24 * fa)
    K.col(C.black, 0.2 * fa)
    G.ellipse("fill", K.X(pcx), K.Y(pcy + ps * 0.43), ps * 0.27 * pop * K.sc, ps * 0.06 * K.sc)
    if env.dexSprite then
      env.dexSprite.draw(e.sp, pcx, pcy, ps, clock, st.chosenAt, pop, fa)
    elseif env.monPic then
      env.monPic(e.sp, pcx - ps / 2, pcy - ps / 2, ps, fa)
    end
    K.addHit(K.R(pcx - ps / 2, pcy - ps / 2, ps, ps), "win", A.SPRITE)
    -- (its words sliding in after it, one after another)
    local tx = x + ps + 7
    local tw = x + w - tx - 3
    local e1, e2, e3, e4 = enter(clock, 0.04, 0.32), enter(clock, 0.08, 0.32), enter(clock, 0.12, 0.32),
      enter(clock, 0.16, 0.32)
    K.label(e.numText, tx + (1 - e1) * 6, y + 4, 3.6, C.white, nil, nil, 0.85 * e1)
    local fs = K.fit(e.name, 7, tw - 6)
    K.label(e.name, tx + (1 - e1) * 8, y + 8, fs, C.white, nil, nil, e1)
    if e.sex then sexMark(e.sex, tx + (1 - e1) * 8 + K.width(e.name, fs) + 1.2, y + 9, 5, e1) end
    -- (the lines under the name a little lower, the chips' three lines apart, as the text grows)
    local g = grown()
    K.label(pg.category, tx + (1 - e2) * 8, y + 16.5 + g * 3, K.fit(pg.category, 4, tw), C.white, nil, nil, 0.9 * e2)
    local cx = tx + (1 - e3) * 8
    for i = 1, #pg.types do
      cx = cx + pill(pg.types[i].id, pg.types[i].name, cx, y + 23 + g * 3, 6, 3.6, e3, true) + 1.5
    end
    -- (height and weight, two frosted chips)
    local chw = min(36, (tw - 1.5) / 2)
    local cy = y + 31.8 + g * 3
    local ox = (1 - e4) * 8
    for j = 1, 2 do
      local bx = tx + ox + (j - 1) * (chw + 1.5)
      K.col(C.white, 0.2 * e4)
      K.box("fill", K.R(bx, cy, chw, 13.2 + g * 4), 2.5)
      -- (the word, metres / kilograms bold, feet / pounds under them)
      local m, imp = j == 1 and pg.heightM or pg.weightM, j == 1 and pg.heightI or pg.weightI
      local lab = word(j == 1 and "dex.height" or "dex.weight")
      K.text(lab, bx + 2.2, cy + 1 - g, roomy(lab, 2.9, chw - 4), C.white, nil, nil, 0.8 * e4)
      K.bold(m or "", bx + 2.2, cy + 4.5 + g * 1.5, K.fit(m or "", 3.6, chw - 4), C.white, nil, nil, e4)
      if imp then K.text(imp, bx + 2.2, cy + 9 + g * 4, roomy(imp, 2.9, chw - 4), C.white, nil, nil, 0.75 * e4) end
    end
    return h
  end

  local function descCard(x, y, w, e, pg, clock)
    local inner = w - 8
    local lines = wrap("desc", pg.description, inner, 3.9)
    local h = 6 + #lines * lineH(3.9) + (pg.noGender and 3 or 12 + grown() * 4)
    glass(K.R(x, y, w, h), 4)
    drawLines(lines, x + 4, y + 4, 3.9, C.ink)
    -- (the gender ratio: each side filling in from its end; Red / Blue / Yellow's Pokémon have none)
    if pg.noGender then return h end
    local gy = y + h - 9 - grown() * 3
    K.text(word("dex.gender"), x + 4, gy, 3.4, C.soft)
    -- (the bar after the word, however big it's drawn)
    local gx = extra(word("dex.gender"), 3.4)
    local bx, bw = x + 22 + gx, w - 26 - gx
    if pg.female == nil then
      K.text(word("dex.genderless"), bx, gy, 3.4, C.ink)
    else
      local f = enter(clock, 0.18, 0.7)
      K.col(C.track)
      K.box("fill", K.R(bx, gy + 1, bw, 2.4), 1.2)
      local mw, fw = bw * (1 - pg.female) * f, bw * pg.female * f
      if mw > 0.3 then
        K.col(C.male)
        K.box("fill", K.R(bx, gy + 1, max(2.4, mw), 2.4), 1.2)
      end
      if fw > 0.3 then
        K.col(C.female)
        K.box("fill", K.R(bx + bw - max(2.4, fw), gy + 1, max(2.4, fw), 2.4), 1.2)
      end
      sexMark("m", bx, gy + 4, 3.2)
      K.text(pg.maleText, bx + 3.6, gy + 4, 3.1, C.soft)
      local tw = K.width(pg.femaleText, 3.1)
      K.text(pg.femaleText, bx + bw - tw - 3.6, gy + 4, 3.1, C.soft)
      sexMark("f", bx + bw - 3, gy + 4, 3.2)
    end
    return h
  end

  local function corner(i, cx, cy, r, v)
    local a = -pi / 2 + (i - 1) * pi / 3
    local k = min(1, v / STAT_MAX)
    return cx + cos(a) * r * k, cy + sin(a) * r * k
  end
  -- the base stats: the radar (morphing from the last Pokémon's), the numbers counting with it; wide,
  -- six bars beside it
  local function stats(x, y, w, pg, dt)
    local wide = w >= WIDE_STATS
    local h = wide and 60 or 76 + grown() * 4
    glass(K.R(x, y, w, h), 4)
    local total = 0
    for j = 1, 6 do
      st.shown[j] = approach(st.shown[j], pg.stats[j], dt, 8)
      total = total + st.shown[j]
    end
    local tt, tv = word("dex.total"), num(floor(total + 0.5))
    local tw = K.width(tv, 4.2)
    K.bold(tv, x + w - 4 - tw, y + 3, 4.2, C.ink)
    local ttw = K.width(tt, 3.6)
    K.text(tt, x + w - 6 - tw - ttw, y + 3.6, 3.6, C.soft)
    -- (the title kept clear of the total)
    K.bold(word("dex.stats"), x + 4, y + 3, roomy(word("dex.stats"), 4.2, w - 12 - tw - ttw), C.ink)
    local rad = wide and 16.5 or min(22, w * 0.22)
    local cx = wide and (x + 6 + rad) or (x + w / 2)
    local cy = wide and (y + 35) or (y + 39)
    -- (the grid: the rim filled faintly, three rings, the spokes)
    for j = 1, 6 do HX[j], HY[j] = corner(j, cx, cy, rad, STAT_MAX) end
    K.col(C.track, 0.55)
    G.polygon("fill", K.X(HX[1]), K.Y(HY[1]), K.X(HX[2]), K.Y(HY[2]), K.X(HX[3]), K.Y(HY[3]), K.X(HX[4]), K.Y(HY[4]),
      K.X(HX[5]), K.Y(HY[5]), K.X(HX[6]), K.Y(HY[6]))
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
    for j = 1, 6 do G.line(K.X(cx), K.Y(cy), K.X(HX[j]), K.Y(HY[j])) end
    -- (the shape: its type's colour, deeper at the edge, a bright line round it, a dot at each corner)
    for j = 1, 6 do PX[j], PY[j] = corner(j, cx, cy, rad, max(6, st.shown[CORNER_STAT[j]])) end
    if mesh == nil then
      local ok, m = pcall(G.newMesh, 8, "fan", "dynamic")
      mesh = ok and m or false
    end
    local r, g, b = mv.r, mv.g, mv.b
    if mesh then
      mesh:setVertex(1, K.X(cx), K.Y(cy), 0, 0, r, g, b, 0.18)
      for j = 1, 6 do mesh:setVertex(j + 1, K.X(PX[j]), K.Y(PY[j]), 0, 0, r, g, b, 0.62) end
      mesh:setVertex(8, K.X(PX[1]), K.Y(PY[1]), 0, 0, r, g, b, 0.62)
      G.setColor(1, 1, 1, K.getFade())
      G.draw(mesh)
    end
    G.setColor(r * 0.7, g * 0.7, b * 0.7, K.getFade())
    G.setLineWidth(max(1, 0.55 * K.sc))
    for j = 1, 6 do
      local nx = j % 6 + 1
      G.line(K.X(PX[j]), K.Y(PY[j]), K.X(PX[nx]), K.Y(PY[nx]))
    end
    for j = 1, 6 do
      K.col(C.white)
      G.circle("fill", K.X(PX[j]), K.Y(PY[j]), 1.15 * K.sc)
      K.col(STAT_C[CORNER_STAT[j]])
      G.circle("fill", K.X(PX[j]), K.Y(PY[j]), 0.75 * K.sc)
    end
    if not wide then
      -- (each corner's stat and value, apart as the text grows)
      local g = grown() * 1.8
      for j = 1, 6 do
        local si = CORNER_STAT[j]
        local lx, ly = corner(j, cx, cy, rad + 9, STAT_MAX)
        K.text(word(STAT_KEY[si]), lx - 16, ly - 4 - g, 3.1, C.soft, "center", 32)
        K.bold(num(floor(st.shown[si] + 0.5)), lx - 16, ly - 0.4 + g, 3.6, C.ink, "center", 32)
      end
      return h
    end
    -- (the bars: each stat's colour dot, its name, its value, its bar)
    local bx = cx + rad + 7
    local lw, vw = 0, 7.5
    for j = 1, 6 do lw = max(lw, K.width(word(STAT_KEY[j]), 3.1)) end
    lw = lw + 4
    local barX = bx + lw + vw + 2
    local barW = x + w - 5 - barX
    for j = 1, 6 do
      local ry = y + 12.5 + (j - 1) * 7.4
      local v = st.shown[j]
      K.col(STAT_C[j])
      G.circle("fill", K.X(bx + 0.9), K.Y(ry + 2.1), 0.9 * K.sc)
      K.text(word(STAT_KEY[j]), bx + 3, ry + 0.2, 3.1, C.soft)
      K.bold(num(floor(v + 0.5)), bx + lw, ry - 0.1, 3.5, C.ink, "right", vw)
      K.col(C.track)
      K.box("fill", K.R(barX, ry + 1, barW, 2.4), 1.2)
      local fw = barW * min(1, v / BAR_MAX)
      if fw > 0.3 then
        K.col(STAT_C[j])
        K.box("fill", K.R(barX, ry + 1, max(2.4, fw), 2.4), 1.2)
      end
    end
    return h
  end

  local function abilities(x, y, w, pg)
    local inner = w - 11
    local h = 10
    for i = 1, #pg.abilities do
      h = h + 5.5 + #wrap(AB[i] or "ab", pg.abilities[i].desc, inner, 3.5) * lineH(3.5) + 3
    end
    glass(K.R(x, y, w, h), 4)
    K.bold(word("dex.abilities"), x + 4, y + 3, 4.2, C.ink)
    local ay = y + 10
    for i = 1, #pg.abilities do
      local a = pg.abilities[i]
      local lines = wrap(AB[i] or "ab", a.desc, inner, 3.5)
      local bh = 5.5 + #lines * lineH(3.5)
      -- (a strip in its type's colour beside each)
      G.setColor(mv.r, mv.g, mv.b, 0.85 * K.getFade())
      K.box("fill", K.R(x + 4, ay + 0.3, 1.3, bh - 1.2), 0.65)
      K.bold(a.name, x + 7.5, ay, 4, C.ink)
      drawLines(lines, x + 7.5, ay + 5.5, 3.5, C.soft)
      ay = ay + bh + 3
    end
    return h
  end

  -- (a list's i-th row fading in after the list changed)
  local function rowIn(clock, i) return outCubic((clock - mv.listAt - min(i, 24) * 0.016) / 0.26) end

  -- the moves' list (the chosen kind's)
  local function moveRows(x, y, w, pg, clock, dt)
    local chipH, ky = 6, y
    local cx = x
    -- (the chips' words smaller when, grown, they'd run past the card; never under their 100% size)
    local cs = 3.5
    if K.textScale() ~= 1 then
      local tw = 0
      for i = 1, #KINDS do tw = tw + K.width(word(KIND_KEY[i]), 3.5) end
      local room = w - #KINDS * 6 - (#KINDS - 1) * 1.5
      if tw > room and tw > 0 then cs = max(3.5 / K.textScale(), 3.5 * room / tw * 0.97) end
    end
    for i = 1, #KINDS do
      local label = word("dex.moves." .. KINDS[i])
      CHX[i], CHW[i] = cx, K.width(label, cs) + 6
      K.col(C.track)
      K.box("fill", K.R(cx, ky, CHW[i], chipH), chipH / 2)
      cx = cx + CHW[i] + 1.5
    end
    -- (the chosen chip's colour sliding between them)
    mv.kindX = approach(mv.kindX, st.kind, dt, 18)
    local k0 = max(1, min(#KINDS, floor(mv.kindX)))
    local k1 = min(#KINDS, k0 + 1)
    local f = mv.kindX - k0
    K.col(C.accent)
    K.box("fill", K.R(CHX[k0] + (CHX[k1] - CHX[k0]) * f, ky, CHW[k0] + (CHW[k1] - CHW[k0]) * f, chipH), chipH / 2)
    for i = 1, #KINDS do
      local on = abs(mv.kindX - i) < 0.5
      local cb = K.R(CHX[i], ky, CHW[i], chipH)
      K.text(word("dex.moves." .. KINDS[i]), CHX[i], ky + (chipH - 4.2) / 2 + (3.5 - cs) * 0.6, cs, on and C.white or C.ink,
        "center", CHW[i])
      K.addHit(cb, "win", A.KIND + i)
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
    -- (each column's name kept to its column as the text grows)
    local hp, ha, hpp = word("dex.col.power"), word("dex.col.acc"), word("dex.col.pp")
    K.text(hp, powX - 4, ry, roomy(hp, 3, 14), C.faint, "right", 14)
    if wide then K.text(ha, powX + 7, ry, roomy(ha, 3, 10.5), C.faint, "right", 14) end
    K.text(hpp, powX + (wide and 18 or 7), ry, roomy(hpp, 3, 10.5), C.faint, "right", 14)
    ry = ry + 4.5
    for i = 1, #rows do
      local r = rows[i]
      local yy = ry + (i - 1) * rh
      local ein = rowIn(clock, i)
      rise(ein, 3)
      if i % 2 == 0 then
        K.col(C.track, 0.35)
        K.box("fill", K.R(x, yy - 0.8, w, rh), 2)
      end
      K.text(r.tag, x + 1.5, yy + 0.6, roomy(r.tag, 3.3, nameX - x - 2.5), C.soft)
      K.text(r.name, nameX, yy + 0.4, K.fit(r.name, 3.7, typeX - nameX - 2), C.ink)
      local pw = pill(r.typeId, r.typeName, typeX, yy, 5.2, 3.1)
      if not r.status then
        K.col(r.physical and C.phys or C.spec)
        K.box("fill", K.R(typeX + pw + 1.2, yy + 1.4, 2.4, 2.4), 1.2)
      end
      K.text(r.powerText, powX, yy + 0.6, 3.4, C.ink, "right", 10)
      if wide then K.text(r.accText, powX + 11, yy + 0.6, 3.4, C.ink, "right", 10) end
      K.text(r.ppText, powX + (wide and 22 or 11), yy + 0.6, 3.4, C.soft, "right", 10)
      settle(ein)
    end
    return ry + #rows * rh - y
  end

  local function whereRows(x, y, w, pg, clock)
    local list = pg.where
    if #list == 0 then
      K.text(word("dex.where.none"), x + 2, y + 1, 3.6, C.soft)
      return 8
    end
    -- (a row taller, its second line lower, as the text grows; 10 and 0 at 100%)
    local rh = 10 + grown() * 4
    local g2 = grown() * 2
    for i = 1, #list do
      local r = list[i]
      local yy = y + (i - 1) * rh
      local ein = rowIn(clock, i)
      rise(ein, 3)
      if i % 2 == 0 then
        K.col(C.track, 0.35)
        K.box("fill", K.R(x, yy - 0.8, w, rh), 2)
      end
      -- (a pin in the backdrop's colour)
      G.setColor(mv.r, mv.g, mv.b, K.getFade())
      G.circle("fill", K.X(x + 2.6), K.Y(yy + 2.4), 1.5 * K.sc)
      K.col(C.white)
      G.circle("fill", K.X(x + 2.6), K.Y(yy + 2.4), 0.6 * K.sc)
      K.bold(r.place, x + 6, yy + 0.4, K.fit(r.place, 3.8, w * 0.55 - 5), C.ink)
      -- (how, kept clear of the chance on its right)
      K.text(r.methodText, x + 6, yy + 4.6 + g2, roomy(r.methodText, 3.2, w - 9 - K.width(r.chanceText, 3.2)), C.soft)
      K.text(r.levels, x + w * 0.55, yy + 0.6, 3.5, C.ink, "right", w * 0.45 - 2)
      K.text(r.chanceText, x + w * 0.55, yy + 4.6 + g2, 3.2, C.soft, "right", w * 0.45 - 2)
      settle(ein)
    end
    return #list * rh
  end

  local function infoRows(x, y, w, e, pg, clock)
    local yy = y
    -- (the evolution chain: the first stage, then each step with how)
    K.bold(word("dex.info.evolution"), x + 1.5, yy, 3.8, C.ink)
    yy = yy + 6
    if #pg.evolutions == 0 then
      K.text(word("dex.evo.none"), x + 1.5, yy, 3.5, C.soft)
      yy = yy + 6
    else
      if pg.base == e.sp then
        K.col(C.accent, 0.12)
        K.box("fill", K.R(x, yy - 2, w, 7.6), 2)
      end
      if env.monIcon then env.monIcon(pg.base, x, yy - 1.5, 8, 0) end
      K.text(pg.baseName, x + 9, yy, 3.6, pg.base == e.sp and C.accent or C.ink)
      yy = yy + 7.6
      for i = 1, #pg.evolutions do
        local v = pg.evolutions[i]
        local ein = rowIn(clock, i)
        rise(ein, 3)
        if v.to == e.sp then
          K.col(C.accent, 0.12)
          K.box("fill", K.R(x, yy - 2, w, 7.6), 2)
        end
        local ix = x + 3 + (v.depth - 1) * 5
        K.col(C.soft)
        G.setLineWidth(max(1, 0.3 * K.sc))
        G.line(K.X(ix), K.Y(yy + 2.2), K.X(ix + 3), K.Y(yy + 2.2))
        G.polygon("fill", K.X(ix + 3.4), K.Y(yy + 2.2), K.X(ix + 2.2), K.Y(yy + 1.2), K.X(ix + 2.2), K.Y(yy + 3.2))
        if env.monIcon then env.monIcon(v.to, ix + 4, yy - 1.5, 8, 0, 1, 1, 1, K.getFade()) end
        K.text(v.toName, ix + 13, yy, 3.6, v.to == e.sp and C.accent or C.ink)
        local hw = x + w - (ix + 13 + K.width(v.toName, 3.6) + 3)
        K.text(v.how, x, yy + 0.3, K.fit(v.how, 3.2, max(10, hw)), C.soft, "right", w - 1.5)
        settle(ein)
        yy = yy + 7.6
      end
    end
    yy = yy + 2
    for i = 1, #pg.info do
      local r = pg.info[i]
      local ein = rowIn(clock, i + #pg.evolutions)
      rise(ein, 3)
      if i % 2 == 1 then
        K.col(C.track, 0.35)
        K.box("fill", K.R(x, yy - 0.8, w, 6.4), 2)
      end
      K.text(r.label, x + 1.5, yy + 0.2, 3.4, C.soft)
      -- (the value kept clear of its label)
      local vs = K.fit(r.value, 3.4, w * 0.58 - 2)
      vs = roomy(r.value, vs, w - 5.5 - K.width(r.label, 3.4))
      K.text(r.value, x + w * 0.42, yy + 0.2, vs, C.ink, "right", w * 0.58 - 2)
      settle(ein)
      yy = yy + 6.4
    end
    return yy - y
  end

  -- the forms (WoobleDex's), the base one first: a tile each, its picture (a silhouette until it's seen),
  -- its name, a Poké Ball under it once it's caught; the one shown brightest, the cursor's ringed (a tap
  -- or A opens one)
  local function formRows(x, y, w, clock)
    local list = st.forms
    local cols = max(2, floor(w / 26))
    local tw = w / cols
    local th = 30
    for i = 1, #list do
      local f = list[i]
      local col0, row = (i - 1) % cols, floor((i - 1) / cols)
      local tx, ty = x + col0 * tw, y + row * th
      local ein = rowIn(clock, i)
      rise(ein, 3)
      local tile = K.R(tx + 1, ty, tw - 2, th - 2)
      local shown = i == st.formAt
      K.col(C.white, (shown and 0.78 or 0.32) * K.getFade())
      K.box("fill", tile, 3)
      if shown then K.ring(tile, 3, C.white, 0.9, 0.4) end
      if i == st.formSel and st.focus == "detail" and st.tabId == "forms" then
        K.ring(tile, 3, C.accent, 1, 0.8)
      end
      K.addHit(tile, "win", A.FORM + i, pageArea)
      local ps = 16
      local px, py = tx + (tw - ps) / 2, ty + 1.5
      if f.seen then
        local drawn = env.monPic and env.monPic(f.sp, px, py, ps, K.getFade())
        if not drawn and env.monIcon then env.monIcon(f.sp, px, py, ps, 0, 1, 1, 1, K.getFade()) end
      elseif env.monIcon then
        env.monIcon(f.sp, px, py, ps, 0, 0.12, 0.12, 0.16, 0.55 * K.getFade())
      end
      local name = f.seen and f.name or "???"
      K.text(name, tx + 1, ty + ps + 2.5, K.fit(name, 3.3, tw - 4), f.seen and C.ink or C.soft, "center", tw - 2)
      if f.caught then ballMark(tx + tw / 2, ty + ps + 9.6, 1.7) end
      settle(ein)
    end
    return ceil(#list / cols) * th
  end

  -- the Size tab: a height chart in glass. The Pokémon in its colours beside the trainer's silhouette (1.7 m),
  -- both standing on one line and drawn to one scale, the taller one filling the chart and the other shrunk
  -- against it, side by side, never over each other; the picture's own drawn pixels are its height
  -- (env.dexSprite.measure), not its frame. Lines across the back at metre steps, named on the left, feet
  -- ticked on the right; each one's height under it. The scale eases from the last Pokémon's, so the lines
  -- and the trainer slide to the new one's; both rise from the line when it opens
  local function sizeChart(x, y, w, e, pg, clock, dt)
    local Sz = env.sizeArt
    local tr = Sz and Sz.trainer()
    local hm = max(0.05, tonumber(pg.heightMeters) or 0)
    local ht = Sz and Sz.TRAINER_M or 1.7
    local m = env.dexSprite and env.dexSprite.measure and env.dexSprite.measure(e.sp)
    local fx0, fy0, fx1, fy1 = -0.4, -0.4, 0.4, 0.5
    if m then fx0, fy0, fx1, fy1 = m.fx0, m.fy0, m.fx1, m.fy1 end
    local artW, artH = max(0.02, fx1 - fx0), max(0.02, fy1 - fy0)
    local tw, th = tr and (tr.u1 - tr.u0) or 9, tr and (tr.v1 - tr.v0) or 30
    local wm, wt = hm * artW / artH, ht * tw / th
    local g = grown()
    local ch = CHART_H + g * 6
    local px0, px1 = x + CHART_L + g * 3, x + w - CHART_R - g * 3
    local top, base = y + 5, y + ch - 14 - g * 7
    local plotH, plotW = base - top, px1 - px0
    -- (the scale: the taller one fills the height, or both fit across)
    local s = min(plotH / (max(hm, ht) * 1.1), (plotW - CHART_GAP - 4) / (wm + wt))
    mv.sizeS = (mv.sizeS and mv.sizeS > 0) and approach(mv.sizeS, s, dt, 9) or s
    s = mv.sizeS
    local fade = K.getFade()
    local grow = outBack((clock - mv.listAt) / 0.55)
    local la = outCubic((clock - mv.listAt) / 0.3)
    -- (the chart's pane)
    local pane = K.R(x, y, w, ch)
    K.col(C.white, 0.24 * fade)
    K.box("fill", pane, 3.5)
    K.ring(pane, 3.5, C.white, 0.7, 0.3)
    -- (metres: a line at each step, its height on the left)
    local topM = plotH / s
    local step = niceStep(STEPS_M, topM, 5)
    G.setLineWidth(max(1, 0.25 * K.sc))
    local i = 1
    while i * step <= topM + 1e-6 do
      local ly = base - i * step * s
      K.col(C.white, 0.75 * fade)
      G.line(K.X(px0), K.Y(ly), K.X(px1), K.Y(ly))
      K.col(C.faint, 0.6 * fade)
      G.line(K.X(px0), K.Y(ly + 0.25), K.X(px1), K.Y(ly + 0.25))
      K.text(mLabel(floor(i * step * 100 + 0.5)), x + 1, ly - 1.5, 2.7, C.soft, "right", px0 - x - 2.5)
      i = i + 1
    end
    K.text(mLabel(0), x + 1, base - 1.5, 2.7, C.soft, "right", px0 - x - 2.5)
    -- (feet: a tick on the right edge at each step)
    local fstep = niceStep(STEPS_FT, topM * FT_PER_M, 5)
    local j = 1
    while j * fstep <= topM * FT_PER_M + 1e-6 do
      local ly = base - j * fstep / FT_PER_M * s
      K.col(C.soft, 0.7 * fade)
      G.line(K.X(px1 - 1.2), K.Y(ly), K.X(px1 + 0.6), K.Y(ly))
      K.text(ftLabel(floor(j * fstep * 2 + 0.5)), px1 + 1.2, ly - 1.4, 2.5, C.soft)
      j = j + 1
    end
    -- (where the two stand: centred together, the Pokémon on the left)
    local wmU, wtU = wm * s, wt * s
    local start = px0 + (plotW - (wmU + CHART_GAP + wtU)) / 2
    local mcx, tcx = start + wmU / 2, start + wmU + CHART_GAP + wtU / 2
    -- (their shadows on the line)
    K.col(C.black, 0.12 * la * fade)
    G.ellipse("fill", K.X(mcx), K.Y(base), max(1, wmU * 0.42) * K.sc, max(0.4, min(1.6, wmU * 0.06)) * K.sc)
    G.ellipse("fill", K.X(tcx), K.Y(base), max(1, wtU * 0.5) * K.sc, max(0.4, min(1.2, wtU * 0.1)) * K.sc)
    -- (the ground line over them)
    K.col(C.ink, 0.32 * fade)
    G.setLineWidth(max(1, 0.4 * K.sc))
    G.line(K.X(px0), K.Y(base), K.X(px1), K.Y(base))
    -- (the Pokémon: its drawn pixels as tall as its height, its feet on the line)
    local size = hm * s * grow / artH
    if size > 0.2 and env.dexSprite then
      env.dexSprite.draw(e.sp, mcx - (fx0 + fx1) / 2 * size, base - fy1 * size, size, clock, -10, 1, la * fade)
    end
    -- (the trainer: a silhouette, see-through on the glass)
    if tr then
      local k = ht * s * grow / th
      G.setColor(1, 1, 1, 0.5 * la * fade)
      G.draw(tr.image, K.X(tcx - (tr.u0 + tw / 2) * k), K.Y(base - tr.v1 * k), 0, k * K.sc, k * K.sc)
    end
    -- (each one's height under it, imperial then metric; kept apart when they stand close)
    local lw = 28 + g * 8
    local lm, lt = mcx, tcx
    if lt - lm < lw then
      local mid = (lm + lt) / 2
      lm, lt = mid - lw / 2, mid + lw / 2
    end
    local ly = base + 2.2
    local hi = pg.heightI or ""
    K.bold(hi, lm - lw / 2, ly, K.fit(hi, 4, lw), C.ink, "center", lw, la)
    K.text(pg.heightM or "", lm - lw / 2, ly + 5 + g * 2, 3, C.soft, "center", lw, la)
    K.bold(TRAINER_I, lt - lw / 2, ly, 4, C.ink, "center", lw, la)
    K.text(TRAINER_M, lt - lw / 2, ly + 5 + g * 2, 3, C.soft, "center", lw, la)
    return ch
  end

  local TAB_WORD = { moves = "dex.tab.moves", where = "dex.tab.where", info = "dex.tab.info", size = "dex.tab.size",
                     forms = "dex.info.forms" }
  local function tabs(x, y, w, e, pg, clock, dt)
    local yy = y
    local list = st.tabs
    local n = #list
    if n >= 2 then
      mv.tabX = approach(mv.tabX, st.tab, dt, 18)
      K.glassSwitch(x, yy, w, 8, mv.tabX, "win", A.TAB + 1, word(TAB_WORD[list[1]]), A.TAB + 2, word(TAB_WORD[list[2]]),
        n >= 3 and A.TAB + 3 or nil, n >= 3 and word(TAB_WORD[list[3]]) or nil, 4.3,
        n >= 4 and A.TAB + 4 or nil, n >= 4 and word(TAB_WORD[list[4]]) or nil,
        n >= 5 and A.TAB + 5 or nil, n >= 5 and word(TAB_WORD[list[5]]) or nil)
      yy = yy + 11
    else
      K.bold(word(TAB_WORD[list[1] or "where"]), x + 1, yy + 1, 4.2, C.ink)
      yy = yy + 8
    end
    local tab = list[st.tab] or "where"
    local ch
    if tab == "moves" then ch = moveRows(x + 3, yy + 3, w - 6, pg, clock, dt)
    elseif tab == "where" then ch = whereRows(x + 3, yy + 3, w - 6, pg, clock)
    elseif tab == "forms" then ch = formRows(x + 3, yy + 3, w - 6, clock)
    elseif tab == "size" then ch = sizeChart(x + 1, yy + 1, w - 2, e, pg, clock, dt)
    else ch = infoRows(x + 3, yy + 3, w - 6, e, pg, clock) end
    return yy - y + ch + 8
  end

  local function drawPage(x, y, w, h, clock, dt)
    local e, pg = st.entry, st.page
    st.detailVis = h
    pageArea = K.R(x, y, w, h)
    K.scissor(pageArea)
    if not e then
      K.scissor(bodyNow)
      return
    end
    mv.page = approach(mv.page, st.detailTop, dt, 18)
    local yy = y - mv.page
    yy = yy + hero(x, yy, w, e, pg or EMPTY, clock, dt) + GAP
    if e.seen and pg then
      -- (each card below settling in after the one above it)
      local c1 = enter(clock, 0.06)
      rise(c1, 7)
      local dh = descCard(x, yy, w, e, pg, clock)
      settle(c1)
      yy = yy + dh + GAP
      if e.caught then
        local c2 = enter(clock, 0.11)
        rise(c2, 7)
        local sh = stats(x, yy, w, pg, dt)
        settle(c2)
        yy = yy + sh + GAP
        if #pg.abilities > 0 then
          local c3 = enter(clock, 0.16)
          rise(c3, 7)
          local ah = abilities(x, yy, w, pg)
          settle(c3)
          yy = yy + ah + GAP
        end
      else
        local note = word("dex.notCaught")
        glass(K.R(x, yy, w, 10), 4)
        K.text(note, x + 4, yy + 3, K.fit(note, 3.8, w - 8), C.soft)
        yy = yy + 10 + GAP
      end
      -- (the tabs and their card)
      local c4 = enter(clock, 0.21)
      rise(c4, 7)
      local ty = yy
      local tabH = max(10, st.tabH or 30)
      glass(K.R(x, ty, w, tabH), 4)
      local th = tabs(x + 2, ty + 2, w - 4, e, pg, clock, dt)
      settle(c4)
      st.tabH = th + 2
      yy = ty + st.tabH + GAP
    elseif st.hint then
      -- (not seen yet: where to look for it, its one card)
      local c1 = enter(clock, 0.06)
      rise(c1, 7)
      local ty = yy
      local tabH = max(10, st.tabH or 30)
      glass(K.R(x, ty, w, tabH), 4)
      K.bold(word("dex.tab.where"), x + 3, ty + 3, 4.2, C.ink)
      local ch = whereRows(x + 5, ty + 13, w - 10, st.hint, clock)
      -- (a form not seen yet: its forms under it, the way back to the others)
      if #st.forms > 1 and st.formAt ~= 1 then
        K.bold(word("dex.info.forms"), x + 3, ty + 17 + ch, 4.2, C.ink)
        ch = ch + 12 + formRows(x + 5, ty + 27 + ch, w - 10, clock)
      end
      settle(c1)
      st.tabH = ch + 18
      yy = ty + st.tabH + GAP
    end
    st.detailH = yy + mv.page - y
    st.detailTop = max(0, min(st.detailTop, max(0, st.detailH - h)))
    K.scissor(bodyNow)
    K.scrollbar(x + w + 1.4, y, h, mv.page, h, max(h, st.detailH))
  end

  -- the narrow page's way back: an arrow and a word, in the accent
  local function backButton(x, y)
    local label = word("dex.back")
    local bb = K.R(x, y, K.width(label, 4.2) + 7, 7)
    K.chevron(x + 2, y + 3.5, 4.2, C.accent, -1)
    K.text(label, x + 4.6, y + 1, 4.2, C.accent)
    K.addHit(bb, "win", A.BACK)
  end

  function V.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    bodyNow = body
    G = K.graphics()
    local dt = st.lastT and max(0, min(0.1, clock - st.lastT)) or 0
    st.lastT = clock
    -- (what changed since the last frame starts its motion)
    if mv.first then
      mv.first, mv.gridAt, mv.pageAt, mv.listAt, mv.tabAt = false, clock, clock, clock, clock
      mv.mode, mv.tabX, mv.kindX = st.mi, st.tab, st.kind
    end
    -- (the colours: the chosen Pokémon's types, slate while it's unseen; eased, snapped on the first frame)
    local ce, cpg = st.entry, st.page
    local t1 = ce and ce.seen and cpg and cpg.types[1] and TYPE[cpg.types[1].id] or nil
    local t2 = t1 and (cpg.types[2] and TYPE[cpg.types[2].id] or t1) or C.slate2
    t1 = t1 or C.slate
    local rate = mv.coloured and 8 or 1000
    mv.coloured = true
    mv.r, mv.g, mv.b = approach(mv.r, t1[1] / 255, dt, rate), approach(mv.g, t1[2] / 255, dt, rate),
      approach(mv.b, t1[3] / 255, dt, rate)
    -- (the second light: the second type, else the first's, lighter)
    local k2 = t2 == t1 and 0.35 or 0
    mv.r2 = approach(mv.r2, (t2[1] + (255 - t2[1]) * k2) / 255, dt, rate)
    mv.g2 = approach(mv.g2, (t2[2] + (255 - t2[2]) * k2) / 255, dt, rate)
    mv.b2 = approach(mv.b2, (t2[3] + (255 - t2[3]) * k2) / 255, dt, rate)
    if st.mi ~= mv.mi then
      if mv.mi ~= nil then mv.gridAt = clock end
      mv.mi, mv.curR = st.mi, nil
    end
    if st.entry ~= mv.entry then
      mv.entry, mv.pageAt, mv.listAt, mv.page = st.entry, clock, clock, st.detailTop
    end
    if st.tab ~= mv.tab or st.kind ~= mv.kind then
      mv.tab, mv.kind, mv.listAt = st.tab, st.kind, clock
    end
    backdrop(body, clock)
    st.narrow = w < NARROW
    if not st.narrow then st.detail = false end
    if st.narrow then
      -- (the page slides in over the grid, the grid easing back under it)
      mv.push = approach(mv.push, st.detail and 1 or 0, dt, 14)
      local p = outCubic(mv.push)
      if p < 0.999 then
        local sh = p > 0.001
        if sh then
          G.push()
          G.translate(-w * 0.3 * p * K.sc, 0)
        end
        drawGrid(x + M, y + M, w - M * 2 - 2, h - M * 2, clock, dt)
        if sh then
          G.pop()
          K.col(C.black, 0.12 * p)
          K.box("fill", body)
        end
      end
      if p > 0.001 then
        local sh = p < 0.999
        if sh then
          G.push()
          G.translate(w * (1 - p) * K.sc, 0)
          K.shadow(body, 0, 0, 0.2)
        end
        backdrop(body, clock)
        backButton(x + M, y + M)
        st.pageX = x
        drawPage(x + M, y + M + 9, w - M * 2, h - M * 2 - 9, clock, dt)
        if sh then G.pop() end
      end
      drawSearch(body, clock)
      return
    end
    mv.push = 0
    local lw = max(96, min(floor(w * 0.47), 190))
    drawGrid(x + M, y + M, lw - 2, h - M * 2, clock, dt)
    local px = x + M + lw + GAP + 1
    st.pageX = px
    drawPage(px, y + M, x + w - M - 2 - px, h - M * 2, clock, dt)
    drawSearch(body, clock)
  end

  return V
end
