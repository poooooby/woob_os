-- The Condition app: the contest conditions as a radar chart (src/condition.lua). The party, or
-- every Pokémon in the party and the boxes ranked by one condition; the chosen one's five
-- conditions (Cool, Beauty, Cute, Smart, Tough) as a glossy pentagon that eases from one Pokémon to
-- the next, its sheen as sparkles round it, its nature and ribbons. Compare lays a second one's
-- outline over it. Pokéblocks feeds one from the case, with the game's own rules; the chart grows.
--   buttons  Up / Down the Pokémon, L / R the condition (Search), START Party | Search, SELECT
--            Compare (again: off), A Pokéblocks (then Up / Down a block, A feed, B back), B close
--   touch    Party | Search, a condition's chip, a row, Compare, Pokéblocks, a block, Feed
--
--   window(ctx, env) -> win (src/apps.lua)

local floor, max, min, sin, cos, pi, abs = math.floor, math.max, math.min, math.sin, math.cos, math.pi, math.abs

local ROW_H, M = 11, 3
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
    grow = 0,
  }
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
            level = i and i.levelText or "" }
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

  local function clamp()
    st.cursor = max(1, min(st.cursor, #st.rows))
    if st.cursor > st.top + st.visible then st.top = st.cursor - st.visible end
    if st.cursor <= st.top then st.top = st.cursor - 1 end
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
    if nav.up then st.cursor = st.cursor - 1; clamp(); se("SE_SELECT")
    elseif nav.down then st.cursor = st.cursor + 1; clamp(); se("SE_SELECT")
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
      clamp()
      se("SE_SELECT")
    end
  end

  function W.scroll(dy)
    st.top = max(0, min(max(0, #st.rows - st.visible), st.top - dy / ROW_H))
  end

  function W.hints()
    if st.sheet then return T.list(HINTS.blocks) end
    return T.list(st.mode == "party" and HINTS.party or HINTS.search)
  end

  -- ------- drawing (no tables made here)

  local WHITE, INK = { 255, 255, 255 }, { 40, 40, 52 }
  local GRID, FILL_EDGE = { 120, 124, 140, 0.35 }, { 255, 255, 255, 0.9 }
  local CHART_TOP, CHART_FOOT = { 34, 38, 58 }, { 18, 20, 32 }
  local GLOSS, GLOSS0 = { 255, 255, 255, 0.18 }, { 255, 255, 255, 0 }
  local SPARK = { 255, 250, 200 }
  local mesh, cmesh = nil, nil
  local PX, PY, CX, CY = {}, {}, {}, {}

  -- (the pentagon's corners: Cool at the top, then round clockwise)
  local function corner(i, cx, cy, r, v)
    local a = -pi / 2 + (i - 1) * 2 * pi / 5
    local k = v / 255
    return cx + cos(a) * r * k, cy + sin(a) * r * k
  end

  local function fillMesh(G, m, xs, ys, cx, cy, alpha)
    local px, py = K.X(cx), K.Y(cy)
    m:setVertex(1, px, py, 0, 0, 1, 1, 1, alpha)
    for i = 1, 5 do
      local c = COLOR[i]
      m:setVertex(i + 1, K.X(xs[i]), K.Y(ys[i]), 0, 0, c[1] / 255, c[2] / 255, c[3] / 255, alpha)
    end
    m:setVertex(7, K.X(xs[1]), K.Y(ys[1]), 0, 0, COLOR[1][1] / 255, COLOR[1][2] / 255, COLOR[1][3] / 255, alpha)
    G.setColor(1, 1, 1, 1)
    G.draw(m)
  end

  local function newMesh(G)
    local ok, m = pcall(G.newMesh, 7, "fan", "dynamic")
    return ok and m or false
  end

  local function drawChart(x, y, w, h, clock, dt)
    local G = K.graphics()
    local b = K.R(x, y, w, h)
    K.grad(b, 5, CHART_TOP, CHART_FOOT)
    K.grad(K.R(x, y, w, h * 0.5), 5, GLOSS, GLOSS0)
    local r = row()
    if not r then
      K.text(T("cond.none"), x, y + h / 2 - 3, 4.6, WHITE, "center", w)
      return
    end
    local i = r.info
    -- (the header: name, nature, ribbons)
    K.bold(i.name, x + 4, y + 3, 5.6, WHITE)
    K.text(i.natureText, x + 4, y + 10, 4, WHITE, nil, nil, 0.7)
    K.text(i.ribbonText, x, y + 3.6, 4, WHITE, "right", w - 4, 0.75)
    local cx, cy = x + w / 2, y + h / 2 + 4
    local rad = min(w * 0.36, (h - 30) / 2)
    -- (the values easing toward the chosen one's; a fed one's growing)
    local k = min(1, dt * 7)
    for j = 1, 5 do
      st.shown[j] = st.shown[j] + (r.conds[j] - st.shown[j]) * k
      local cv = st.compare and st.compare.conds[j] or 0
      st.cshown[j] = st.cshown[j] + (cv - st.cshown[j]) * k
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
    for j = 1, 5 do
      local ax, ay = corner(j, cx, cy, rad, 255)
      K.col(GRID)
      G.line(K.X(cx), K.Y(cy), K.X(ax), K.Y(ay))
      local lx, ly = corner(j, cx, cy, rad + 7, 255)
      local label = T(NAME[j])
      K.col(COLOR[j])
      K.box("fill", K.R(lx - 1.2, ly - 1.2, 2.4, 2.4), 1.2)
      K.text(label, lx - 20, ly + 1.6, 3.6, WHITE, "center", 40, 0.85)
    end
    -- (the compared one: an outline)
    if st.compare and st.compare ~= r then
      for j = 1, 5 do CX[j], CY[j] = corner(j, cx, cy, rad, st.cshown[j]) end
      if cmesh == nil then cmesh = newMesh(G) end
      if cmesh then fillMesh(G, cmesh, CX, CY, cx, cy, 0.18) end
      K.col(WHITE, 0.8)
      G.setLineWidth(max(1, 0.45 * K.sc))
      for j = 1, 5 do
        local n = j % 5 + 1
        G.line(K.X(CX[j]), K.Y(CY[j]), K.X(CX[n]), K.Y(CY[n]))
      end
    end
    -- (the chosen one: a glossy fill in the conditions' colours, a bright edge)
    for j = 1, 5 do PX[j], PY[j] = corner(j, cx, cy, rad, max(6, st.shown[j])) end
    if mesh == nil then mesh = newMesh(G) end
    local glow = st.grow > 0 and max(0, 1 - (now() - st.grow) / 1.2) or 0
    if mesh then fillMesh(G, mesh, PX, PY, cx, cy, 0.62 + glow * 0.3) end
    K.col(FILL_EDGE)
    G.setLineWidth(max(1, (0.55 + glow) * K.sc))
    for j = 1, 5 do
      local n = j % 5 + 1
      G.line(K.X(PX[j]), K.Y(PY[j]), K.X(PX[n]), K.Y(PY[n]))
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
    -- (the sheen as a bar along the foot)
    local sb = K.R(x + 6, y + h - 7, w - 12, 2.4)
    K.col(WHITE, 0.15)
    K.box("fill", sb, 1.2)
    K.col(SPARK)
    K.box("fill", K.R(sb[1], sb[2], sb[3] * r.sheen / 255, sb[4]), 1.2)
    K.text(T("cond.sheen"), x + 6, y + h - 13, 3.6, WHITE, nil, nil, 0.7)
  end

  local function drawList(x, y, w, h, focused)
    st.visible = max(1, floor(h / ROW_H))
    clamp()
    if #st.rows == 0 then return end
    K.card(K.R(x, y, w, min(h, (#st.rows - st.top) * ROW_H)), 4)
    for i = st.top + 1, min(#st.rows, st.top + st.visible) do
      local r = st.rows[i]
      local ry = y + (i - st.top - 1) * ROW_H
      local on = i == st.cursor
      if on then K.selection(K.R(x + 1, ry + 0.5, w - 2, ROW_H - 1), focused, 3) end
      local ink = (on and focused) and WHITE or UI.label
      if env.monIcon then pcall(env.monIcon, r.info.species, x + 1, ry - 0.5, 11) end
      local nw = w - 30
      K.text(r.info.name, x + 13, ry + 3, K.fit(r.info.name, 4.6, nw), ink)
      -- (its value: the condition searched, or a mini pentagon's mean)
      local v = st.mode == "search" and r.conds[st.cat] or floor((r.conds[1] + r.conds[2] + r.conds[3] + r.conds[4]
        + r.conds[5]) / 5)
      local bx = x + w - 16
      K.col((on and focused) and WHITE or UI.fill, (on and focused) and 0.35 or 1)
      K.box("fill", K.R(bx, ry + 4.4, 13, 2.4), 1.2)
      K.col(st.mode == "search" and COLOR[st.cat] or UI.accent)
      K.box("fill", K.R(bx, ry + 4.4, 13 * v / 255, 2.4), 1.2)
      if st.compare == r then K.ring(K.R(x + 1, ry + 0.5, w - 2, ROW_H - 1), 3, UI.yellow, 0.9, 0.6) end
      if i > st.top + 1 and not on and i - 1 ~= st.cursor then K.hairline(x + 13, ry, w - 13) end
      K.addHit(K.R(x, ry, w, ROW_H), "win", i)
    end
    K.scrollbar(x + w, y, h, st.top, st.visible, #st.rows)
  end

  local function drawCats(x, y, w)
    local cw = w / 5
    for j = 1, 5 do
      local b = K.R(x + (j - 1) * cw + 0.5, y, cw - 1, 7)
      local on = j == st.cat
      K.col(COLOR[j], on and 1 or 0.18)
      K.box("fill", b, 3.5)
      K.text(T(NAME[j]), b[1], b[2] + 1.4, K.fit(T(NAME[j]), 3.6, b[3] - 1), on and WHITE or UI.label, "center", b[3])
      K.addHit(b, "win", CAT + j)
    end
  end

  local blocksText = K.textCache(function(n) return T.f("cond.blocksN", n) end)
  local numText = K.textCache(function(n) return tostring(n) end)
  local function drawButtons(x, y, w)
    local bw = (w - 2) / 2
    local cb, pb = K.R(x, y, bw, 9), K.R(x + bw + 2, y, bw, 9)
    K.button(cb, T(st.compare and "cond.compareOff" or "cond.compare"), st.compare and "tinted" or "gray", false, 4.2)
    K.button(pb, blocksText(#st.blocks), "gray", false, 4.2)
    K.addHit(cb, "win", COMPARE)
    K.addHit(pb, "win", BLOCKS)
  end

  -- the Pokéblock case, over the window
  local function drawSheet(x, y, w, h)
    K.dim(K.R(x, y, w, h), 0.25)
    local sw, sh = min(w - 10, 150), min(h - 10, 110)
    local b = K.R(x + (w - sw) / 2, y + (h - sh) / 2, sw, sh)
    K.sheet(b, 6)
    local r = row()
    K.bold(T("cond.blocks"), b[1] + 5, b[2] + 4, 5.4, UI.label)
    if r then K.text(r.info.feedTo, b[1] + 5, b[2] + 11, 4, UI.secondary) end
    local ly, lh = b[2] + 18, 10
    local fits = max(1, floor((sh - 34) / lh))
    local top = max(0, min(st.blockCursor - fits, #st.blocks - fits))
    for i = top + 1, min(#st.blocks, top + fits) do
      local bl = st.blocks[i]
      local ry = ly + (i - top - 1) * lh
      local on = i == st.blockCursor
      local rb = K.R(b[1] + 3, ry, sw - 6, lh)
      if on then K.selection(rb, true, 3) end
      K.text(bl.name, rb[1] + 3, ry + 2.4, K.fit(bl.name, 4.2, sw * 0.45), on and WHITE or UI.label)
      -- (its five flavours as little bars, and its feel)
      local fx = rb[1] + sw * 0.5
      for j = 1, 5 do
        local v = bl.flavors[j]
        K.col(FLAVOR[j], v > 0 and 1 or 0.2)
        local bh = 1 + 6 * min(1, v / 40)
        K.box("fill", K.R(fx + (j - 1) * 4, ry + lh - 2 - bh, 2.6, bh), 0.6)
      end
      K.text(numText(bl.feel), rb[1], ry + 2.4, 4, on and WHITE or UI.secondary, "right", rb[3] - 3)
      K.addHit(rb, "win", BLOCK + i)
    end
    local fb = K.R(b[1] + sw - 30, b[2] + sh - 12, 26, 9)
    K.button(fb, T("cond.feed"), "accent", false, 4.4)
    K.addHit(fb, "win", FEED)
    local xb = K.R(b[1] + 4, b[2] + sh - 12, 24, 9)
    K.button(xb, T("hint.back"), "gray", false, 4.4)
    K.addHit(xb, "win", CLOSE)
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    local dt = st.lastT and max(0, min(0.1, clock - st.lastT)) or 0
    st.lastT = clock
    K.segmented(x + M, y + 2, portrait and w - M * 2 or min(110, w * 0.42), 8.5,
      st.mode == "party" and 1 or 2, "win", SEG_PARTY, T("cond.party"), SEG_SEARCH, T("cond.search"))
    local top = y + 13
    if portrait then
      if st.mode == "search" then
        drawCats(x + M, top, w - M * 2)
        top = top + 9
      end
      local ch = min(h * 0.55, w * 0.95)
      drawChart(x + M, top, w - M * 2, ch, clock, dt)
      top = top + ch + 2
      drawButtons(x + M, top, w - M * 2)
      top = top + 11
      drawList(x + M, top, w - M * 2, y + h - M - top, not st.sheet)
    else
      local lw = floor((w - M * 3) * 0.42)
      local ltop = top
      if st.mode == "search" then
        drawCats(x + M, ltop, lw)
        ltop = ltop + 9
      end
      drawList(x + M, ltop, lw, y + h - M - 11 - ltop, not st.sheet)
      K.scissor(body)
      drawButtons(x + M, y + h - M - 9, lw)
      drawChart(x + M * 2 + lw, y + 2, w - lw - M * 3, h - 2 - M, clock, dt)
    end
    K.scissor(body)
    if st.sheet then drawSheet(x, y, w, h) end
    if st.toast and not K.toast(st.toast, clock, K.R(x, y, w, h), UI.red, UI.green, UI.hud) then st.toast = nil end
  end

  refresh()
  return W
end
