-- The Condition app: the contest conditions as a radar chart (src/condition.lua). The party, or
-- every Pokémon in the party and the boxes ranked by one condition; the chosen one's five
-- conditions (Cool, Beauty, Cute, Smart, Tough) as a glossy pentagon that eases from one Pokémon to
-- the next, each corner with its number, its sheen as sparkles round it and a bar, its picture, nature
-- and ribbons. The Pokédex's glass (the kit's) over soft lights in the colours of the chosen one's best
-- conditions (the searched one's first), turning as it changes; the chart smoked glass. Compare lays a
-- second one's outline over it. Pokéblocks feeds one from the case, with the game's own rules; the chart
-- grows, a ring bursting from it.
-- Its motion (numbers only): the panes settling in as it opens, the rows rising in one after another as
-- the list is made again (Party | Search, another condition), the list's highlight gliding and the list
-- scrolling smoothly, the switch's and the conditions' thumbs sliding, the chosen one's picture popping up
-- and its words sliding in, the numbers counting to the new ones, the sheen filling; the Pokéblock case
-- popping up over a dim, its rows rising in, its highlight gliding.
--   buttons  Up / Down the Pokémon, L / R the condition (Search), START Party | Search, SELECT
--            Compare (again: off), A Pokéblocks (then Up / Down a block, A feed, B back), B close
--   touch    Party | Search, a condition's chip, a row, Compare, Pokéblocks, a block, Feed
--
--   window(ctx, env) -> win (src/apps.lua)   env.condition, env.bx, env.dexSprite

local floor, max, min, sin, cos, pi, abs = math.floor, math.max, math.min, math.sin, math.cos, math.pi, math.abs

local ROW_H, M, GAP = 11, 3, 2
local SEG_PARTY, SEG_SEARCH, COMPARE, BLOCKS, FEED, CLOSE = 2001, 2002, 2003, 2004, 2005, 2006
local CAT, BLOCK = 2100, 2200
local HINTS = {
  party = { { "^ v", "cond.hint.mon" }, { "A", "cond.blocks" }, { "SELECT", "cond.compare" }, { "START", "cond.search" },
            { "B", "hint.close" } },
  search = { { "^ v", "cond.hint.mon" }, { "L R", "cond.hint.cat" }, { "SELECT", "cond.compare" },
             { "START", "cond.party" }, { "B", "hint.close" } },
  blocks = { { "^ v", "cond.hint.block" }, { "A", "cond.feed" }, { "B", "hint.back" } },
}
-- the conditions' colours (the contests')
local COLOR = { { 240, 80, 60 }, { 70, 140, 255 }, { 255, 120, 190 }, { 70, 200, 110 }, { 255, 196, 40 } }
local NAME = { "cond.cool", "cond.beauty", "cond.cute", "cond.smart", "cond.tough" }
-- the flavours' colours (spicy, dry, sweet, bitter, sour)
local FLAVOR = { { 240, 80, 60 }, { 70, 140, 255 }, { 255, 120, 190 }, { 70, 200, 110 }, { 255, 196, 40 } }
-- (the backdrop's lights when nothing stands out: slate, lilac)
local SLATE, LILAC = { 120, 132, 178 }, { 150, 120, 190 }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, Cd, T = env.K, env.condition, env.T or NO_T
  local UI = K.UI
  local W = { title = T("app.condition") }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end
  local function now() return env.now and env.now() or 0 end

  local st = {
    mode = "party", cat = 1, rows = {}, cursor = 1, top = 0, visible = 6, compare = nil, sheet = false,
    blocks = {}, blockCursor = 1, toast = nil, shown = { 0, 0, 0, 0, 0 }, cshown = { 0, 0, 0, 0, 0 }, lastT = nil,
    grow = 0, seg = 1,
  }
  -- (the backdrop's two lights, 0..1, eased toward the chosen one's colours)
  local lit = { 0.6, 0.6, 0.6, 0.6, 0.6, 0.6 }
  W.state = st
  -- (opened on the search: from the PokéNav's menu)
  do
    local resume = ctx.resume and ctx.resume.app == ctx.app and ctx.resume.state
    if resume then
      st.mode, st.cat = resume.mode or st.mode, resume.cat or st.cat
      ctx.resume = nil
    end
  end

  local nameOf = setmetatable({}, { __mode = "k" })
  local function info(mon)
    local got = nameOf[mon]
    if got then return got end
    local i = env.bx and env.bx.info(mon, T) or nil
    got = { name = i and i.name or "?", species = i and i.species or 0, nature = i and i.nature or "",
            level = i and i.levelText or "", shiny = i and i.shiny == true or false, egg = i and i.egg == true or false }
    got.ribbons = Cd.ribbons(mon)
    got.ribbonText = T.f("cond.ribbons", got.ribbons)
    got.natureText = got.nature ~= "" and T.f("cond.nature", got.nature) or ""
    got.feedTo = T.f("cond.feedTo", got.name)
    nameOf[mon] = got
    return got
  end

  local function refresh()
    local s = session()
    local keep = st.rows[st.cursor] and st.rows[st.cursor].mon
    st.rows = st.mode == "party" and Cd.party(s) or Cd.search(s, st.cat)
    st.cursor = 1
    for i, r in ipairs(st.rows) do if r.mon == keep then st.cursor = i end end
    for _, r in ipairs(st.rows) do r.info = info(r.mon) end
    if st.compare then
      local c = st.compare.mon
      st.compare = nil
      for _, r in ipairs(st.rows) do if r.mon == c then st.compare = r end end
    end
    st.blocks = Cd.blocks(s)
    st.blockCursor = max(1, min(st.blockCursor, #st.blocks))
  end
  W.refresh = refresh

  -- (keeps the chosen row in view, unless the list was scrolled by hand since the last press: a drag
  -- or the wheel would otherwise be pulled straight back to it on the next frame)
  local function clamp(follow)
    if follow then st.free = false end
    st.cursor = max(1, min(st.cursor, #st.rows))
    if not st.free then
      if st.cursor > st.top + st.visible then st.top = st.cursor - st.visible end
      if st.cursor <= st.top then st.top = st.cursor - 1 end
    end
    st.top = max(0, min(st.top, max(0, #st.rows - st.visible)))
  end
  local function row() return st.rows[st.cursor] end
  local function toast(text, bad) st.toast = { text = text, bad = bad ~= false, t = now() } end

  local function setMode(m)
    if m == st.mode then return end
    st.mode, st.top, st.sheet = m, 0, false
    refresh()
    se("SE_SELECT")
  end
  local function setCat(c)
    st.cat = (c - 1) % 5 + 1
    if st.mode == "search" then refresh() end
    se("SE_SELECT")
  end
  local function compare()
    local r = row()
    if st.compare then st.compare = nil
    elseif r then
      -- (the next one along is the other side; the chosen one moves on from there)
      st.compare = r
      toast(T("cond.comparePick"), false)
    end
    se("SE_SELECT")
  end
  local function openBlocks()
    st.blocks = Cd.blocks(session())
    if #st.blocks == 0 then
      se("SE_FAILURE")
      return toast(T("cond.noBlocks"))
    end
    st.sheet = true
    se("SE_SELECT")
  end
  -- (the gains in words: "Cool +12, Beauty +3", or the game's nothing)
  local function gains(before, after)
    local parts = {}
    for i = 1, 5 do
      if after[i] ~= before[i] then parts[#parts + 1] = T(NAME[i]) .. " +" .. tostring(after[i] - before[i]) end
    end
    return #parts > 0 and table.concat(parts, ", ") or T("cond.nothing")
  end
  local function feed()
    local r, b = row(), st.blocks[st.blockCursor]
    if not (r and b) then return end
    local before = { r.conds[1], r.conds[2], r.conds[3], r.conds[4], r.conds[5] }
    local ok, why = Cd.feed(session(), b.slot, r.mon)
    if not ok then
      se("SE_FAILURE")
      return toast(T("cond.why." .. tostring(why)))
    end
    se("SE_SUCCESS")
    local fresh = Cd.row(r.mon, r.where)
    r.conds, r.sheen, r.sparkles = fresh.conds, fresh.sheen, fresh.sparkles
    st.grow = now()
    toast(gains(before, r.conds), false)
    st.blocks = Cd.blocks(session())
    if #st.blocks == 0 then st.sheet = false end
    st.blockCursor = max(1, min(st.blockCursor, #st.blocks))
  end

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
    if st.sheet then
      if pressed("b") then st.sheet = false; se("SE_SELECT")
      elseif nav.up and st.blockCursor > 1 then st.blockCursor = st.blockCursor - 1; se("SE_SELECT")
      elseif nav.down and st.blockCursor < #st.blocks then st.blockCursor = st.blockCursor + 1; se("SE_SELECT")
      elseif pressed("a") then feed() end
      return true
    end
    if pressed("b") then return false end
    if nav.up then st.cursor = st.cursor - 1; clamp(true); se("SE_SELECT")
    elseif nav.down then st.cursor = st.cursor + 1; clamp(true); se("SE_SELECT")
    elseif pressed("l") then setCat(st.cat - 1)
    elseif pressed("r") then setCat(st.cat + 1)
    elseif pressed("start") then setMode(st.mode == "party" and "search" or "party")
    elseif pressed("select") then compare()
    elseif pressed("a") then openBlocks()
    end
    return true
  end

  function W.tap(arg)
    if arg == SEG_PARTY then return setMode("party") end
    if arg == SEG_SEARCH then return setMode("search") end
    if arg == COMPARE then return compare() end
    if arg == BLOCKS then return openBlocks() end
    if arg == FEED then return feed() end
    if arg == CLOSE then st.sheet = false; return se("SE_SELECT") end
    if type(arg) ~= "number" then return end
    if arg > CAT and arg <= CAT + 5 then
      st.cat = arg - CAT
      if st.mode == "search" then refresh() end
      return se("SE_SELECT")
    end
    if arg > BLOCK and st.blocks[arg - BLOCK] then
      st.blockCursor = arg - BLOCK
      return se("SE_SELECT")
    end
    if st.rows[arg] then
      st.cursor = arg
      clamp(true)
      se("SE_SELECT")
    end
  end

  function W.scroll(dy)
    st.free = true
    st.top = max(0, min(max(0, #st.rows - st.visible), st.top - dy / ROW_H))
  end

  function W.hints()
    if st.sheet then return T.list(HINTS.blocks) end
    return T.list(st.mode == "party" and HINTS.party or HINTS.search)
  end
  function W.close() if env.dexSprite then pcall(env.dexSprite.stop) end end

  -- ------- drawing (no tables, closures or strings made here)

  local WHITE = { 255, 255, 255 }
  local GRID, FILL_EDGE = { 120, 124, 140, 0.35 }, { 255, 255, 255, 0.9 }
  local SMOKE = { 24, 28, 48 }
  local SPARK = { 255, 250, 200 }
  local mesh, cmesh = nil, nil
  local PX, PY, CX, CY = {}, {}, {}, {}
  local G = nil
  local num = K.textCache(function(n) return tostring(n) end)
  local blocksText = K.textCache(function(n) return T.f("cond.blocksN", n) end)
  -- the motion's numbers
  local mv = { openAt = nil, rec = nil, recAt = 0, listAt = 0, mode = nil, cat = nil, selY = nil, top = 0, catX = nil,
               sheet = false, sheetAt = -10, blockY = nil, sheen = 0, growAt = nil, growClock = -10 }
  W.motion = mv

  -- (the pentagon's corners: Cool at the top, then round clockwise)
  local function corner(i, cx, cy, r, v)
    local a = -pi / 2 + (i - 1) * 2 * pi / 5
    local k = v / 255
    return cx + cos(a) * r * k, cy + sin(a) * r * k
  end

  local function fillMesh(m, xs, ys, cx, cy, alpha)
    local px, py = K.X(cx), K.Y(cy)
    m:setVertex(1, px, py, 0, 0, 1, 1, 1, alpha)
    for i = 1, 5 do
      local c = COLOR[i]
      m:setVertex(i + 1, K.X(xs[i]), K.Y(ys[i]), 0, 0, c[1] / 255, c[2] / 255, c[3] / 255, alpha)
    end
    m:setVertex(7, K.X(xs[1]), K.Y(ys[1]), 0, 0, COLOR[1][1] / 255, COLOR[1][2] / 255, COLOR[1][3] / 255, alpha)
    G.setColor(1, 1, 1, K.getFade())
    G.draw(m)
  end

  local function newMesh()
    local ok, m = pcall(G.newMesh, 7, "fan", "dynamic")
    return ok and m or false
  end

  -- the chosen one's picture centred on cx, cy, popping up as it's chosen
  local function picture(r, cx, cy, size, clock)
    local i = r.info
    local t = clock - mv.recAt
    local pop = 0.8 + 0.2 * K.outBack(t / 0.42)
    local fa = K.outCubic(t / 0.18) * K.getFade()
    K.glow(cx, cy, size * 0.6, size * 0.5, WHITE, 0.16 * fa)
    if i.egg or not env.dexSprite then
      if env.monPic then pcall(env.monPic, i.species, cx - size / 2 * pop, cy - size / 2 * pop, size * pop, fa, r.mon) end
    else
      pcall(env.dexSprite.draw, i.species, cx, cy, size, clock, mv.recAt, pop, fa, i.shiny, r.mon)
    end
    K.rescissor()
  end

  local function drawChart(x, y, w, h, clock, dt)
    local b = K.R(x, y, w, h)
    K.glass(b, 5, 0.74, SMOKE, 0.4, 0.45)
    local r = row()
    if not r then
      K.text(T("cond.none"), x, y + h / 2 - 3, 4.6, WHITE, "center", w)
      return
    end
    local i = r.info
    local f0 = K.getFade()
    -- (the header: its picture, name, nature, ribbons, sliding in after the picture)
    local t = clock - mv.recAt
    local e1, e2 = K.outCubic((t - 0.04) / 0.32), K.outCubic((t - 0.1) / 0.32)
    local ps = max(10, min(17, h * 0.2))
    picture(r, x + 3 + ps / 2, y + 2 + ps / 2, ps, clock)
    local hx = x + ps + 5
    K.bold(i.name, hx + (1 - e1) * 6, y + 3, K.fit(i.name, 5.6, w * 0.5 - ps), WHITE, nil, nil, e1)
    K.text(i.natureText, hx + (1 - e2) * 6, y + 10, 4, WHITE, nil, nil, 0.7 * e2)
    K.text(i.ribbonText, x, y + 3.6, 4, WHITE, "right", w - 4 - (1 - e2) * 6, 0.75 * e2)
    local cx, cy = x + w / 2, y + h / 2 + 5
    -- (a touch smaller as the corners' words grow, clear of the header and the sheen: nothing at 100%)
    local rad = max(4, min(w * 0.36, (h - 34 - (K.textScale() - 1) * 6) / 2))
    -- (the values easing toward the chosen one's; a fed one's growing)
    for j = 1, 5 do
      st.shown[j] = K.approach(st.shown[j], r.conds[j], dt, 7)
      local cv = st.compare and st.compare.conds[j] or 0
      st.cshown[j] = K.approach(st.cshown[j], cv, dt, 7)
    end
    -- (the grid: rings and spokes)
    G.setLineWidth(max(1, 0.3 * K.sc))
    for ring = 1, 4 do
      K.col(GRID)
      local v = ring * 255 / 4
      for j = 1, 5 do
        local ax, ay = corner(j, cx, cy, rad, v)
        local bx, by = corner(j % 5 + 1, cx, cy, rad, v)
        G.line(K.X(ax), K.Y(ay), K.X(bx), K.Y(by))
      end
    end
    -- (each corner: its colour's dot, its word and its number counting to the chosen one's)
    for j = 1, 5 do
      local ax, ay = corner(j, cx, cy, rad, 255)
      K.col(GRID)
      G.line(K.X(cx), K.Y(cy), K.X(ax), K.Y(ay))
      local lx, ly = corner(j, cx, cy, rad + 7, 255)
      local label = T(NAME[j])
      K.col(COLOR[j])
      K.box("fill", K.R(lx - 1.2, ly - 1.2, 2.4, 2.4), 1.2)
      local value = num(floor(st.shown[j] + 0.5))
      local lw, vw = K.width(label, 3.4), K.width(value, 3.4)
      -- (grown with the text size, the side corners' words grow outward, away from the chart: their inner
      -- end stays where it is at 100%)
      local side = lx > cx + 0.5 and 1 or (lx < cx - 0.5 and -1 or 0)
      local sx = lx - (lw + vw + 1.2) / 2 + side * (lw + vw) * (1 - 1 / K.textScale()) / 2
      K.text(label, sx, ly + 1.6, 3.4, WHITE, nil, nil, 0.8)
      K.bold(value, sx + lw + 1.2, ly + 1.6, 3.4, WHITE)
    end
    -- (the compared one: an outline)
    if st.compare and st.compare ~= r then
      for j = 1, 5 do CX[j], CY[j] = corner(j, cx, cy, rad, st.cshown[j]) end
      if cmesh == nil then cmesh = newMesh() end
      if cmesh then fillMesh(cmesh, CX, CY, cx, cy, 0.18 * f0) end
      K.col(WHITE, 0.8)
      G.setLineWidth(max(1, 0.45 * K.sc))
      for j = 1, 5 do
        local n = j % 5 + 1
        G.line(K.X(CX[j]), K.Y(CY[j]), K.X(CX[n]), K.Y(CY[n]))
      end
    end
    -- (the chosen one: a glossy fill in the conditions' colours, a bright edge)
    for j = 1, 5 do PX[j], PY[j] = corner(j, cx, cy, rad, max(6, st.shown[j])) end
    if mesh == nil then mesh = newMesh() end
    -- (fed: it glows and a ring bursts from it, on the draw's clock from the moment it was seen)
    if st.grow ~= mv.growAt then mv.growAt, mv.growClock = st.grow, (st.grow ~= 0) and clock or -10 end
    local glow = max(0, 1 - (clock - mv.growClock) / 1.2)
    if mesh then fillMesh(mesh, PX, PY, cx, cy, (0.62 + glow * 0.3) * f0) end
    K.col(FILL_EDGE)
    G.setLineWidth(max(1, (0.55 + glow) * K.sc))
    for j = 1, 5 do
      local n = j % 5 + 1
      G.line(K.X(PX[j]), K.Y(PY[j]), K.X(PX[n]), K.Y(PY[n]))
    end
    if glow > 0 then
      K.col(SPARK, glow * 0.7)
      G.setLineWidth(max(1, 0.6 * K.sc))
      G.circle("line", K.X(cx), K.Y(cy), rad * (0.5 + (1 - glow) * 0.75) * K.sc)
    end
    -- (the sheen: sparkles twinkling round it)
    for s = 1, r.sparkles do
      local a = clock * 0.6 + s * 2 * pi / max(1, r.sparkles)
      local sx, sy = cx + cos(a) * rad * 1.05, cy + sin(a) * rad * 0.95
      local tw = 0.5 + 0.5 * abs(sin(clock * 3 + s))
      local u = (0.8 + tw) * K.sc
      K.col(SPARK, 0.4 + 0.6 * tw)
      local px, py = K.X(sx), K.Y(sy)
      G.polygon("fill", px, py - u * 1.6, px + u * 0.4, py, px, py + u * 1.6, px - u * 0.4, py)
      G.polygon("fill", px - u * 1.6, py, px, py - u * 0.4, px + u * 1.6, py, px, py + u * 0.4)
    end
    -- (the sheen as a bar along the foot, filling to it)
    mv.sheen = K.approach(mv.sheen, r.sheen, dt, 6)
    local sb = K.R(x + 6, y + h - 7, w - 12, 2.4)
    K.col(WHITE, 0.15)
    K.box("fill", sb, 1.2)
    local fw = sb[3] * mv.sheen / 255
    if fw > 0.2 then
      K.col(SPARK)
      K.box("fill", K.R(sb[1], sb[2], max(2.4, fw), sb[4]), 1.2)
    end
    K.text(T("cond.sheen"), x + 6, y + h - 13, 3.6, WHITE, nil, nil, 0.7)
    K.text(num(floor(mv.sheen + 0.5)), x + 6, y + h - 13, 3.6, WHITE, "right", w - 12, 0.85)
  end

  local function drawList(x, y, w, h, focused, clock, dt)
    st.visible = max(1, floor(h / ROW_H))
    clamp()
    if #st.rows == 0 then return end
    -- (smooth to where the D-pad sent it; scrolled by hand, right where the hand left it)
    if st.free then mv.top = st.top else mv.top = K.approach(mv.top, st.top, dt, 20) end
    local top = mv.top
    -- (its pane as tall as the rows left from where the list will settle: a size that eases would make the
    -- kit a gradient for each)
    K.glass(K.R(x, y, w, min(h, (#st.rows - st.top) * ROW_H)), 4, 0.55)
    -- (scrolled by hand, the top falls between rows: from the row it's in, clipped to the list)
    local psx, psy, psw, psh
    if G.getScissor then psx, psy, psw, psh = G.getScissor() end
    local area = K.R(x, y, w, h)
    K.scissor(area)
    -- (the chosen row's highlight, gliding from row to row)
    if mv.selY == nil then mv.selY = st.cursor else mv.selY = K.approach(mv.selY, st.cursor, dt, 24) end
    local hb = K.R(x + 1, y + (mv.selY - 1 - top) * ROW_H + 0.5, w - 2, ROW_H - 1)
    if focused then
      K.col(UI.accent)
      K.box("fill", hb, 3)
    else
      K.col(WHITE, 0.7)
      K.box("fill", hb, 3)
      K.ring(hb, 3, WHITE, 0.9, 0.3)
    end
    local since = clock - mv.listAt
    local first = floor(top) + 1
    for i = first, min(#st.rows, first + st.visible) do
      local r = st.rows[i]
      local ry = y + (i - 1 - top) * ROW_H
      local on = i == st.cursor
      local e = K.outCubic((since - (i - first) * 0.035) / 0.28)
      K.rise(e, 4)
      local ink = (on and focused) and WHITE or UI.label
      if env.monIcon then pcall(env.monIcon, r.info.species, x + 1, ry - 0.5, 11, 0, 1, 1, 1, K.getFade()) end
      local nw = w - 30
      K.text(r.info.name, x + 13, ry + 3, K.fit(r.info.name, 4.6, nw), ink)
      -- (its value: the condition searched, or a mini pentagon's mean, filling as it rises in)
      local v = st.mode == "search" and r.conds[st.cat] or floor((r.conds[1] + r.conds[2] + r.conds[3] + r.conds[4]
        + r.conds[5]) / 5)
      local bx = x + w - 16
      K.col((on and focused) and WHITE or UI.fill, (on and focused) and 0.35 or 1)
      K.box("fill", K.R(bx, ry + 4.4, 13, 2.4), 1.2)
      local fw = 13 * v / 255 * e
      if fw > 0.2 then
        K.col(st.mode == "search" and COLOR[st.cat] or UI.accent)
        K.box("fill", K.R(bx, ry + 4.4, max(2.4, fw), 2.4), 1.2)
      end
      if st.compare == r then K.ring(K.R(x + 1, ry + 0.5, w - 2, ROW_H - 1), 3, UI.yellow, 0.9, 0.6) end
      if i > first and not on and i - 1 ~= st.cursor then K.hairline(x + 13, ry, w - 13) end
      K.addHit(K.R(x, ry, w, ROW_H), "win", i, area)
      K.settle(e)
    end
    if psx then G.setScissor(psx, psy, psw, psh) else G.setScissor() end
    K.scrollbar(x + w, y, h, top, st.visible, #st.rows)
  end

  -- the five conditions' chips: clear glass tinted each one's colour, a thumb of the chosen one's sliding
  local function drawCats(x, y, w, dt)
    local cw = w / 5
    if mv.catX == nil then mv.catX = st.cat else mv.catX = K.approach(mv.catX, st.cat, dt, 18) end
    for j = 1, 5 do
      local b = K.R(x + (j - 1) * cw + 0.5, y, cw - 1, 7)
      K.col(WHITE, 0.32)
      K.box("fill", b, 3.5)
      K.col(COLOR[j], 0.22)
      K.box("fill", b, 3.5)
      K.ring(b, 3.5, WHITE, 0.75, 0.3)
    end
    -- (the thumb, its colour turning from one chip's to the next's as it slides)
    local lo = max(1, min(5, floor(mv.catX)))
    local hi = min(5, lo + 1)
    local k = mv.catX - lo
    local c1, c2 = COLOR[lo], COLOR[hi]
    G.setColor((c1[1] + (c2[1] - c1[1]) * k) / 255, (c1[2] + (c2[2] - c1[2]) * k) / 255,
      (c1[3] + (c2[3] - c1[3]) * k) / 255, K.getFade())
    local tb = K.R(x + (mv.catX - 1) * cw + 0.5, y, cw - 1, 7)
    K.box("fill", tb, 3.5)
    K.ring(tb, 3.5, WHITE, 0.6, 0.3)
    for j = 1, 5 do
      local b = K.R(x + (j - 1) * cw + 0.5, y, cw - 1, 7)
      local on = abs(mv.catX - j) < 0.5
      local word = T(NAME[j])
      local fs = K.fit(word, 3.6, b[3] - 1)
      if on then K.bold(word, b[1], b[2] + 1.4, fs, WHITE, "center", b[3])
      else K.text(word, b[1], b[2] + 1.4, fs, UI.label, "center", b[3]) end
      K.addHit(b, "win", CAT + j)
    end
  end

  local function glassButton(b, label, on)
    local rad = min(b[4] / 2, 3.2)
    if on then
      K.col(UI.accent, 0.88)
      K.box("fill", b, rad)
      K.ring(b, rad, WHITE, 0.6, 0.3)
    else
      K.glass(b, rad, 0.5)
    end
    local fs = K.fit(label, 4.2, b[3] - 3)
    K.bold(label, b[1], b[2] + (b[4] - fs * 1.2) / 2, fs, on and WHITE or UI.label, "center", b[3])
  end
  local function drawButtons(x, y, w)
    local bw = (w - 2) / 2
    local cb, pb = K.R(x, y, bw, 9), K.R(x + bw + 2, y, bw, 9)
    glassButton(cb, T(st.compare and "cond.compareOff" or "cond.compare"), st.compare ~= nil)
    glassButton(pb, blocksText(#st.blocks), false)
    K.addHit(cb, "win", COMPARE)
    K.addHit(pb, "win", BLOCKS)
  end

  -- the Pokéblock case, popping up over the window: its rows rising in, the highlight gliding
  local function drawSheet(x, y, w, h, clock, dt)
    local e = K.outCubic((clock - mv.sheetAt) / 0.22)
    K.dim(K.R(x, y, w, h), 0.25 * e)
    local sw, sh = min(w - 10, 150), min(h - 10, 110)
    local b = K.R(x + (w - sw) / 2, y + (h - sh) / 2, sw, sh)
    K.rise(e, 6)
    K.shadow(b, 6, 1.6, 0.25)
    K.glass(b, 6, 0.84)
    local r = row()
    -- (the title, the words under it and the rows apart as the text grows: nothing at 100%)
    local gs = K.textScale() - 1
    K.bold(T("cond.blocks"), b[1] + 5, b[2] + 4 - gs * 1.5, 5.4, UI.label)
    if r then K.text(r.info.feedTo, b[1] + 5, b[2] + 11 + gs * 1.5, 4, UI.secondary) end
    local ly, lh = b[2] + 18 + gs * 5, 10
    local fits = max(1, floor((sh - 34 - gs * 5) / lh))
    local top = max(0, min(st.blockCursor - fits, #st.blocks - fits))
    if mv.blockY == nil then mv.blockY = st.blockCursor else mv.blockY = K.approach(mv.blockY, st.blockCursor, dt, 24) end
    if #st.blocks > 0 then
      local hy = ly + (max(top + 1, min(top + fits, mv.blockY)) - top - 1) * lh
      K.selection(K.R(b[1] + 3, hy, sw - 6, lh), true, 3)
    end
    local since = clock - mv.sheetAt
    for i = top + 1, min(#st.blocks, top + fits) do
      local bl = st.blocks[i]
      local ry = ly + (i - top - 1) * lh
      local on = i == st.blockCursor
      local rb = K.R(b[1] + 3, ry, sw - 6, lh)
      local ei = K.outCubic((since - (i - top) * 0.03) / 0.26)
      K.rise(ei, 3)
      K.text(bl.name, rb[1] + 3, ry + 2.4, K.fit(bl.name, 4.2, sw * 0.45), on and WHITE or UI.label)
      -- (its five flavours as little bars, growing as it rises in, and its feel)
      local fx = rb[1] + sw * 0.5
      for j = 1, 5 do
        local v = bl.flavors[j]
        K.col(FLAVOR[j], v > 0 and 1 or 0.2)
        local bh = 1 + 6 * min(1, v / 40) * ei
        K.box("fill", K.R(fx + (j - 1) * 4, ry + lh - 2 - bh, 2.6, bh), 0.6)
      end
      K.text(num(bl.feel), rb[1], ry + 2.4, 4, on and WHITE or UI.secondary, "right", rb[3] - 3)
      K.addHit(rb, "win", BLOCK + i)
      K.settle(ei)
    end
    local fb = K.R(b[1] + sw - 30, b[2] + sh - 12, 26, 9)
    K.button(fb, T("cond.feed"), "accent", false, 4.4)
    K.addHit(fb, "win", FEED)
    local xb = K.R(b[1] + 4, b[2] + sh - 12, 24, 9)
    K.button(xb, T("hint.back"), "gray", false, 4.4)
    K.addHit(xb, "win", CLOSE)
    K.settle(e)
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    G = K.graphics()
    local dt = st.lastT and max(0, min(0.1, clock - st.lastT)) or 0
    if not mv.openAt then mv.openAt, mv.listAt = clock, clock end
    -- (what changed since the last frame starts its motion: another Pokémon, the list made again, the
    -- case opened)
    local r = row()
    if r ~= mv.rec then
      mv.rec, mv.recAt = r, clock
      if r and not r.info.egg and env.dexSprite then pcall(env.dexSprite.start, r.info.species, r.info.shiny) end
    end
    if st.mode ~= mv.mode or (st.mode == "search" and st.cat ~= mv.cat) then
      if mv.mode ~= nil then mv.listAt = clock end
      mv.mode, mv.cat = st.mode, st.cat
    end
    if st.sheet ~= mv.sheet then
      mv.sheet, mv.sheetAt = st.sheet, clock
      mv.blockY = nil
    end
    -- (the lights: the searched condition's colour, else the chosen one's best; its next best second)
    local c1, c2 = SLATE, LILAC
    if r then
      local i1, i2 = 0, 0
      for j = 1, 5 do
        local v = r.conds[j]
        if v > 0 and (i1 == 0 or v > r.conds[i1]) then i1, i2 = j, i1
        elseif v > 0 and (i2 == 0 or v > r.conds[i2]) then i2 = j end
      end
      if st.mode == "search" then
        i2 = i1 ~= st.cat and i1 or i2
        i1 = st.cat
      end
      if i1 > 0 then c1 = COLOR[i1] end
      if i2 > 0 then c2 = COLOR[i2] elseif i1 > 0 then c2 = LILAC end
    end
    local rate = st.lastT and 6 or 1000
    lit[1], lit[2], lit[3] = K.approach(lit[1], c1[1] / 255, dt, rate), K.approach(lit[2], c1[2] / 255, dt, rate),
      K.approach(lit[3], c1[3] / 255, dt, rate)
    lit[4], lit[5], lit[6] = K.approach(lit[4], c2[1] / 255, dt, rate), K.approach(lit[5], c2[2] / 255, dt, rate),
      K.approach(lit[6], c2[3] / 255, dt, rate)
    st.lastT = clock
    K.backdrop(body, clock, lit[1], lit[2], lit[3], lit[4], lit[5], lit[6])
    st.seg = K.approach(st.seg, st.mode == "party" and 1 or 2, dt, 18)
    -- (the panes settling in one after another as it opens; eased straight from the clock, so that every
    -- branch the motion takes has been taken within half a second)
    local since = clock - mv.openAt
    local o1, o2, o3 = K.outCubic(since / 0.4), K.outCubic((since - 0.06) / 0.4), K.outCubic((since - 0.12) / 0.4)
    K.rise(o1, 5)
    K.glassSwitch(x + M, y + 2, portrait and w - M * 2 or min(110, w * 0.42), 8.5, st.seg, "win",
      SEG_PARTY, T("cond.party"), SEG_SEARCH, T("cond.search"), nil, nil, 4.3)
    K.settle(o1)
    local top = y + 13
    if portrait then
      if st.mode == "search" then
        drawCats(x + M, top, w - M * 2, dt)
        top = top + 9
      end
      local ch = min(h * 0.55, w * 0.95)
      K.rise(o2, 7)
      drawChart(x + M, top, w - M * 2, ch, clock, dt)
      K.settle(o2)
      top = top + ch + GAP
      K.rise(o3, 7)
      drawButtons(x + M, top, w - M * 2)
      top = top + 11
      drawList(x + M, top, w - M * 2, y + h - M - top, not st.sheet, clock, dt)
      K.settle(o3)
    else
      local lw = floor((w - M * 3) * 0.42)
      local ltop = top
      if st.mode == "search" then
        drawCats(x + M, ltop, lw, dt)
        ltop = ltop + 9
      end
      K.rise(o2, 7)
      drawList(x + M, ltop, lw, y + h - M - 11 - ltop, not st.sheet, clock, dt)
      K.scissor(body)
      drawButtons(x + M, y + h - M - 9, lw)
      K.settle(o2)
      K.rise(o3, 7)
      drawChart(x + M * 2 + lw, y + 2, w - lw - M * 3, h - 2 - M, clock, dt)
      K.settle(o3)
    end
    K.scissor(body)
    if st.sheet then drawSheet(x, y, w, h, clock, dt) end
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), UI.red, UI.green, UI.hud) then st.toast = nil end
  end

  refresh()
  return W
end
