-- The Hall of Fame app: every team the game recorded (src/hall.lua; src/gb/hall.lua on the Game Boy
-- games), newest first, in the Pokédex's glass. The top: the entry, which of them it is and the arrows to
-- the older and newer ones. The chosen Pokémon on a pane of its type's colour (its picture popping up,
-- animated as the Pokédex's, a shiny in its colours; its name, species, gender, level, ID and types) with
-- a Poké Ball turning slowly behind it and glints twinkling over it; the team's six on panes of glass
-- beside it. Each one chosen calls out.
-- Its motion (numbers only, in `mv`): the backdrop turning to the chosen one's types, the six rising in
-- one after another as a team is shown (sliding in from the side it came from), the highlight gliding
-- from card to card, the chosen one's card hopping, its picture popping up and its words sliding in.
--   buttons  the D-pad the Pokémon, L / R the team, A its cry, B close
--   touch    a card, the arrows at the top, the picture (its cry)
--
--   window(ctx, env) -> win (src/apps.lua)   env.hall, env.bx (the types), env.dexSprite

local floor, max, min, sin, pi = math.floor, math.max, math.min, math.sin, math.pi

local M, GAP, TOP_H = 3, 2, 9
local OLDER, NEWER, HERO, CARD = 2001, 2002, 2003, 2100
local C = {
  ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, faint = { 160, 160, 170 }, accent = { 10, 132, 255 },
  white = { 255, 255, 255 }, black = { 0, 0, 0 }, male = { 10, 132, 255 }, female = { 255, 55, 95 },
  gold = { 232, 170, 28 }, glint = { 255, 244, 200 },
  -- (the backdrop's lights while the chosen one's types aren't known: the champion's gold, amber)
  champ = { 226, 176, 64 }, champ2 = { 255, 178, 120 },
}
local SHADE_TOP, SHADE_FOOT = { 255, 255, 255, 0.28 }, { 0, 0, 0, 0.16 }
-- the types' colours (the game's ids; 18 WoobleDex's Fairy)
local TYPE = {
  [0] = { 168, 168, 120 }, [1] = { 192, 48, 40 }, [2] = { 168, 144, 240 }, [3] = { 160, 64, 160 },
  [4] = { 224, 192, 104 }, [5] = { 184, 160, 56 }, [6] = { 168, 184, 32 }, [7] = { 112, 88, 152 },
  [8] = { 184, 184, 208 }, [9] = { 104, 160, 144 }, [10] = { 240, 128, 48 }, [11] = { 104, 144, 240 },
  [12] = { 120, 200, 80 }, [13] = { 248, 208, 48 }, [14] = { 248, 88, 136 }, [15] = { 152, 216, 216 },
  [16] = { 112, 56, 248 }, [17] = { 112, 88, 72 }, [18] = { 238, 153, 172 },
}
local NO_TYPES = {}
local HINTS = { { "+", "hall.hint.pick" }, { "L R", "hall.hint.team" }, { "A", "hall.hint.cry" }, { "B", "hint.close" } }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, Hl, T = env.K, env.hall, env.T or NO_T
  local W = { title = T("app.hall") }
  local function session() return ctx.session or (env.session and env.session()) end
  local function se(name) if env.se then pcall(env.se, name) end end

  local st = { teams = Hl.teams(session()), team = 1, pick = 1 }
  W.state = st
  for _, t in ipairs(st.teams) do
    t.title = T.f("hall.entry", t.number)
    for _, m in ipairs(t.members) do
      m.levelText = T.f("boxes.level", m.level)
      m.idText = T.f("hall.id", string.format("%05d", m.trainerId))
      m.types, m.shiny = NO_TYPES, m.picMon and m.picMon.shiny == true or false
    end
  end

  local function current() return st.teams[st.team] end
  local function chosen()
    local t = current()
    return t and t.members[st.pick]
  end
  -- (a team's types and shininess from the Boxes' model, read once, the first time the team is shown)
  local function prepare(t)
    if not t or t.prepared then return end
    t.prepared = true
    local Bx = env.bx
    if not (Bx and Bx.info) then return end
    for _, m in ipairs(t.members) do
      if not m.egg and m.picMon then
        local ok, info = pcall(Bx.info, m.picMon, T)
        if ok and type(info) == "table" then
          if type(info.types) == "table" then
            -- (our own list: the model's is shared, and its names are the game's short capitals)
            local list = {}
            for i, ty in ipairs(info.types) do
              local okN, nm = pcall(env.typeName or error, ty.id)
              list[i] = { id = ty.id, name = okN and type(nm) == "string" and nm or ty.name }
            end
            m.types = list
          end
          if info.shiny == true then m.shiny = true end
        end
      end
    end
    -- (the model may have made a picture: the scissor set again after it)
    K.rescissor()
  end
  -- (the chosen one's animation from the start, as the Pokédex's)
  local function show()
    local m = chosen()
    if m and not m.egg and env.dexSprite then pcall(env.dexSprite.start, m.species, m.shiny) end
  end
  local function pick(i)
    local t = current()
    if not (t and t.members[i]) or i == st.pick then return end
    st.pick = i
    show()
    Hl.cry(chosen())
  end
  local function team(d)
    local i = max(1, min(#st.teams, st.team + d))
    if i == st.team then return end
    st.team, st.pick = i, 1
    prepare(current())
    se("SE_SELECT")
    show()
    Hl.cry(chosen())
  end
  prepare(current())
  show()
  Hl.cry(chosen())

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  function W.input(input, nav)
    cur = input
    if pressed("b") then return false end
    if pressed("l") then team(1)        -- (older: further down the list)
    elseif pressed("r") then team(-1)
    elseif pressed("a") then Hl.cry(chosen())
    elseif nav.left and (st.pick - 1) % 3 > 0 then pick(st.pick - 1)
    elseif nav.right and (st.pick - 1) % 3 < 2 then pick(st.pick + 1)
    elseif nav.up and st.pick > 3 then pick(st.pick - 3)
    elseif nav.down and st.pick <= 3 then pick(st.pick + 3)
    end
    return true
  end
  function W.tap(arg)
    if arg == OLDER then return team(1) end
    if arg == NEWER then return team(-1) end
    if arg == HERO then return Hl.cry(chosen()) end
    if type(arg) == "number" and arg > CARD then pick(arg - CARD) end
  end
  function W.hints() return T.list(HINTS) end
  function W.close()
    Hl.stop()
    if env.dexSprite then pcall(env.dexSprite.stop) end
  end

  -- ------- drawing (no tables, closures or strings made here)

  local G, bodyNow = nil, nil
  local posText = K.textCache(function(k) return tostring(k % 1000) .. " / " .. tostring(floor(k / 1000)) end)
  -- the motion's numbers
  local mv = { team = nil, teamAt = 0, dir = 0, pickM = nil, pickAt = 0, openAt = nil, gx = nil, gy = nil, gw = nil,
               lastT = nil, coloured = false, r = 0.6, g = 0.6, b = 0.6, r2 = 0.6, g2 = 0.6, b2 = 0.6 }
  W.motion = mv

  -- (a type's pill -> its width)
  local function pill(id, name, x, y, h, size, a)
    local pw = K.width(name, size) + 5
    local b = K.R(x, y, pw, h)
    K.col(TYPE[id] or C.faint, a)
    K.box("fill", b, h / 2)
    K.ring(b, h / 2, C.white, 0.55 * (a or 1), 0.4)
    K.text(name, x, y + (h - size * 1.2) / 2, size, C.white, "center", pw, a)
    return pw
  end
  local function pillsWidth(m, size)
    local wsum = 0
    for i = 1, #m.types do wsum = wsum + K.width(m.types[i].name or "", size) + 5 + (i > 1 and 1.5 or 0) end
    return wsum
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
  -- a four-pointed star, r units round cx, cy: two thin diamonds crossed (love's fills are convex)
  local function star(cx, cy, r, c, a)
    K.col(c, a)
    local x, y, rr, q = K.X(cx), K.Y(cy), r * K.sc, r * K.sc * 0.3
    G.polygon("fill", x, y - rr, x + q, y, x, y + rr, x - q, y)
    G.polygon("fill", x - rr, y, x, y - q, x + rr, y, x, y + q)
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
  -- the chosen one's picture centred on cx, cy, `size` units at `pop` of itself (eggs and windows without
  -- the Pokédex's animation: the still picture)
  local function picture(m, cx, cy, size, pop, a, clock)
    if m.egg or not env.dexSprite then
      if env.monPic then pcall(env.monPic, m.species, cx - size / 2 * pop, cy - size / 2 * pop, size * pop, a, m.picMon) end
    else
      pcall(env.dexSprite.draw, m.species, cx, cy, size, clock, mv.pickAt, pop, a, m.shiny, m.picMon)
    end
    K.rescissor()
  end
  local function enter(clock, delay) return K.outCubic((clock - mv.pickAt - delay) / 0.32) end

  -- ------- the top: the entry, which of them, the arrows (older to the left, as L)
  local function drawTop(x, y, w, clock)
    local t = current()
    local n = #st.teams
    local e = K.outCubic((clock - mv.teamAt) / 0.3)
    local ox = (1 - e) * mv.dir * 6
    local fa = e * K.getFade()
    star(x + 3 + ox, y + 4.5, 2.8 + 0.3 * sin(clock * 3), C.gold, fa)
    K.bold(t.title, x + 7.5 + ox, y + 2, K.fit(t.title, 4.6, w - 60), C.ink, nil, nil, fa)
    if n > 1 then
      local rx = x + w
      local newer, older = st.team > 1, st.team < n
      K.chevron(rx - 4.5, y + 4.5, 4, C.accent, 1, newer and 1 or 0.28)
      if newer then K.addHit(K.R(rx - 9, y, 9, TOP_H), "win", NEWER) end
      K.chevron(rx - 14.5, y + 4.5, 4, C.accent, -1, older and 1 or 0.28)
      if older then K.addHit(K.R(rx - 19, y, 9, TOP_H), "win", OLDER) end
      -- (which of them, oldest the first: the left arrow lowers it)
      K.text(posText(n * 1000 + (n - st.team + 1)), rx - 52, y + 2.3, 3.8, C.soft, "right", 31)
    end
  end

  -- ------- the chosen one: its pane, its picture, its words; `tall`: the picture over the words
  local function hero(x, y, w, h, m, clock, tall)
    local b = K.R(x, y, w, h)
    K.shadow(b, 5, 1.4, 0.1)
    G.setColor(mv.r, mv.g, mv.b, 0.74 * K.getFade())
    K.box("fill", b, 5)
    K.grad(b, 5, SHADE_TOP, SHADE_FOOT)
    K.ring(b, 5, C.white, 0.6, 0.4)
    -- (where its picture goes, the words' block centred with it: the words' height, roughly)
    local words = 21.5 + (m.sameName and 0 or 5) + (#m.types > 0 and 6 or 0)
    local ps, pcx, pcy
    if tall then
      ps = max(16, min(w - 12, h - 44, 58))
      pcx, pcy = x + w / 2, y + max(3, (h - ps - words - 3) / 2) + ps / 2
    else
      ps = max(16, min(44, h - 6, w * 0.42))
      pcx, pcy = x + 3 + ps / 2, y + h / 2 + 1
    end
    G.intersectScissor(K.X(x), K.Y(y), w * K.sc, h * K.sc)
    if tall then ballMark(pcx, pcy, ps * 0.62, clock * 0.18, 0.12)
    else ballMark(x + w - h * 0.3, y + h * 0.62, h * 0.6, clock * 0.18, 0.13) end
    -- (glints twinkling over it, each in its own place and time)
    for i = 1, 5 do
      local tw = sin(clock * (1.3 + i * 0.37) + i * 2.1)
      if tw > 0.2 then
        local gx = x + w * ((i * 0.618) % 1) * 0.9 + w * 0.05
        local gy = y + h * ((i * 0.382 + 0.13) % 1) * (tall and 0.55 or 0.85) + 2
        star(gx, gy, 0.9 + 1.1 * tw, C.glint, (tw - 0.2) * 0.8)
      end
    end
    K.scissor(bodyNow)
    -- (its picture popping up on its shadow, a light behind it)
    local t = clock - mv.pickAt
    local pop = 0.8 + 0.2 * K.outBack(t / 0.42)
    local fa = K.outCubic(t / 0.18) * K.getFade()
    K.glow(pcx, pcy, ps * 0.6, ps * 0.5, C.white, 0.24 * fa)
    K.col(C.black, 0.2 * fa)
    G.ellipse("fill", K.X(pcx), K.Y(pcy + ps * 0.43), ps * 0.27 * pop * K.sc, ps * 0.06 * K.sc)
    picture(m, pcx, pcy, ps, pop, fa, clock)
    K.addHit(K.R(pcx - ps / 2, pcy - ps / 2, ps, ps), "win", HERO)
    -- (its words sliding in after it)
    local e1, e2, e3 = enter(clock, 0.04), enter(clock, 0.08), enter(clock, 0.12)
    local f0 = K.getFade()
    if tall then
      local ty = pcy + ps / 2 + 3
      local fs = K.fit(m.nickname, 6, w - 16)
      local d1 = (1 - e1) * 5
      K.label(m.nickname, x, ty + d1, fs, C.white, "center", w, e1 * f0)
      local nx = x + (w + K.width(m.nickname, fs)) / 2 + 1.2
      if m.gender and m.sameName and not K.hasSign(m.nickname) then sexMark(m.gender, nx, ty + 1 + d1, 5, e1 * f0) nx = nx + 5 end
      if m.shiny then star(nx + 2.5, ty + 3.4 + d1, 2.2 + 0.5 * sin(clock * 5), C.gold, e1 * f0) end
      ty = ty + fs * 1.25 + 0.5
      local d2 = (1 - e2) * 5
      if not m.sameName then
        local sw = K.width(m.name, 3.8)
        local sx = x + (w - sw - ((m.gender and not K.hasSign(m.name)) and 5 or 0)) / 2
        K.label(m.name, sx, ty + d2, 3.8, C.white, nil, nil, 0.85 * e2 * f0)
        if m.gender and not K.hasSign(m.name) then sexMark(m.gender, sx + sw + 1.2, ty + 0.2 + d2, 4.2, e2 * f0) end
        ty = ty + 5.2
      end
      K.label(m.levelText, x, ty + d2, 4.2, C.white, "center", w, e2 * f0)
      ty = ty + 5.4
      local d3 = (1 - e3) * 5
      K.label(m.idText, x, ty + d3, 3.4, C.white, "center", w, 0.8 * e3 * f0)
      ty = ty + 5.2
      if #m.types > 0 and ty + 6 <= y + h - 1 then
        local cx = x + (w - pillsWidth(m, 3.4)) / 2
        for i = 1, #m.types do
          cx = cx + pill(m.types[i].id, m.types[i].name or "", cx, ty + d3, 5.6, 3.4, e3 * f0) + 1.5
        end
      end
      return
    end
    local tx = x + ps + 7
    local tw = x + w - tx - 3
    local fs = K.fit(m.nickname, 6.4, tw - 8)
    local o1 = (1 - e1) * 8
    local wy = y + max(3, (h - words) / 2)
    K.label(m.nickname, tx + o1, wy, fs, C.white, nil, nil, e1 * f0)
    local nx = tx + o1 + K.width(m.nickname, fs) + 1.2
    if m.gender and m.sameName and not K.hasSign(m.nickname) then sexMark(m.gender, nx, wy + 1, 5, e1 * f0) nx = nx + 5 end
    if m.shiny then star(nx + 2.5, wy + 3.5, 2.2 + 0.5 * sin(clock * 5), C.gold, e1 * f0) end
    local yy = wy + fs * 1.25 + 0.6
    local o2 = (1 - e2) * 8
    if not m.sameName then
      local sw = K.width(m.name, 3.6)
      K.label(m.name, tx + o2, yy, K.fit(m.name, 3.6, tw - 6), C.white, nil, nil, 0.85 * e2 * f0)
      if m.gender and not K.hasSign(m.name) then sexMark(m.gender, tx + o2 + min(sw, tw - 6) + 1.2, yy + 0.1, 4, e2 * f0) end
      yy = yy + 4.8
    end
    K.label(m.levelText, tx + o2, yy, 4.2, C.white, nil, nil, e2 * f0)
    yy = yy + 5.4
    local o3 = (1 - e3) * 8
    K.label(m.idText, tx + o3, yy, 3.4, C.white, nil, nil, 0.8 * e3 * f0)
    yy = yy + 5
    if #m.types > 0 and yy + 6 <= y + h - 1 then
      local cx = tx + o3
      for i = 1, #m.types do
        cx = cx + pill(m.types[i].id, m.types[i].name or "", cx, yy, 5.6, 3.4, e3 * f0) + 1.5
      end
    end
  end

  -- ------- the team's six on glass: rising in one after another as it's shown, the highlight gliding
  local function cards(x, y, w, h, clock, dt)
    local t = current()
    local cw, ch = (w - GAP * 2) / 3, (h - GAP) / 2
    local since = clock - mv.teamAt
    local p = st.pick
    local hx, hy = x + (p - 1) % 3 * (cw + GAP), y + floor((p - 1) / 3) * (ch + GAP)
    if mv.gx == nil or mv.gw ~= cw then
      mv.gx, mv.gy, mv.gw = hx, hy, cw
    else
      mv.gx, mv.gy = K.approach(mv.gx, hx, dt, 26), K.approach(mv.gy, hy, dt, 26)
    end
    -- (the chosen one's pane: brighter glass under it, gliding)
    local hb = K.R(mv.gx, mv.gy, cw, ch)
    K.col(C.white, 0.5)
    K.box("fill", hb, 3.5)
    local hopT = clock - mv.pickAt
    local hop = (hopT >= 0 and hopT < 0.36) and sin(hopT / 0.36 * pi) * 2 or 0
    for i = 1, 6 do
      local cx, cy = x + (i - 1) % 3 * (cw + GAP), y + floor((i - 1) / 3) * (ch + GAP)
      local m = t.members[i]
      local e = K.outCubic((since - (i - 1) * 0.045) / 0.34)
      K.rise(e, 5, mv.dir * 6)
      local b = K.R(cx, cy, cw, ch)
      if m then
        K.col(C.white, 0.34)
        K.box("fill", b, 3.5)
        K.ring(b, 3.5, C.white, 0.75, 0.3)
        local on = i == p
        local small = ch < 30
        local s = max(8, min(cw - 4, ch - (small and 7 or 11)))
        local py = cy + 1.5 - (on and hop or 0)
        if env.monPic then pcall(env.monPic, m.species, cx + (cw - s) / 2, py, s, K.getFade(), m.picMon) end
        K.rescissor()
        if m.shiny then star(cx + cw - 3.2, cy + 3.2, 1.8, C.gold) end
        local fs = K.fit(m.nickname, 3.8, cw - 3)
        if small then
          K.text(m.nickname, cx, cy + ch - fs * 1.2 - 0.8, fs, C.ink, "center", cw)
        else
          K.bold(m.nickname, cx, cy + ch - 9.4, fs, C.ink, "center", cw)
          K.text(m.levelText, cx, cy + ch - 4.9, 3, C.soft, "center", cw)
        end
        K.addHit(b, "win", CARD + i)
      else
        K.col(C.white, 0.14)
        K.box("fill", b, 3.5)
        K.ring(b, 3.5, C.white, 0.35, 0.3)
      end
      K.settle(e)
    end
    -- (its ring over the cards)
    K.ring(K.R(mv.gx, mv.gy, cw, ch), 3.5, C.gold, 0.7 + 0.3 * sin(clock * 5), 0.8)
  end

  -- ------- the whole window

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    G = K.graphics()
    bodyNow = body
    local dt = mv.lastT and max(0, min(0.1, clock - mv.lastT)) or 0
    mv.lastT = clock
    if not mv.openAt then mv.openAt = clock end
    local t = current()
    local m = chosen()
    -- (what changed since the last frame starts its motion)
    if st.team ~= mv.team then
      mv.dir = mv.team and (st.team > mv.team and -1 or 1) or 0
      mv.team, mv.teamAt = st.team, clock
    end
    if m ~= mv.pickM then mv.pickM, mv.pickAt = m, clock end
    -- (the lights: the chosen one's types, the champion's gold while they aren't known; eased)
    local t1 = m and m.types[1] and TYPE[m.types[1].id] or nil
    local t2 = t1 and (m.types[2] and TYPE[m.types[2].id] or t1) or C.champ2
    t1 = t1 or C.champ
    local rate = mv.coloured and 8 or 1000
    mv.coloured = true
    mv.r, mv.g, mv.b = K.approach(mv.r, t1[1] / 255, dt, rate), K.approach(mv.g, t1[2] / 255, dt, rate),
      K.approach(mv.b, t1[3] / 255, dt, rate)
    local k2 = t2 == t1 and 0.35 or 0
    mv.r2 = K.approach(mv.r2, (t2[1] + (255 - t2[1]) * k2) / 255, dt, rate)
    mv.g2 = K.approach(mv.g2, (t2[2] + (255 - t2[2]) * k2) / 255, dt, rate)
    mv.b2 = K.approach(mv.b2, (t2[3] + (255 - t2[3]) * k2) / 255, dt, rate)
    K.backdrop(body, clock, mv.r, mv.g, mv.b, mv.r2, mv.g2, mv.b2)
    if not (t and m) then
      ballMark(x + w / 2, y + h / 2 - 6, min(w, h) * 0.18, clock * 0.18, 0.5)
      K.text(T("hall.none"), x + 6, y + h / 2 + min(w, h) * 0.18 - 2, 4.6, C.soft, "center", w - 12)
      K.scissor(body)
      return
    end
    drawTop(x + M, y + 1, w - M * 2, clock)
    local top = y + TOP_H + 2
    local ah = y + h - M - top
    local open = K.outCubic((clock - mv.openAt) / 0.4)
    if portrait or w < 170 then
      -- (narrow: the chosen one over the six)
      local hh = max(30, min(52, ah * 0.44))
      K.rise(open, 6)
      hero(x + M, top, w - M * 2, hh, m, clock, false)
      K.settle(open)
      cards(x + M, top + hh + GAP, w - M * 2, ah - hh - GAP, clock, dt)
    else
      -- (wide: the chosen one on the left, the six beside it)
      local lw = max(90, min(floor(w * 0.4), 130))
      K.rise(open, 6)
      hero(x + M, top, lw, ah, m, clock, ah >= 80)
      K.settle(open)
      cards(x + M + lw + GAP + 1, top, w - M * 2 - lw - GAP - 1, ah, clock, dt)
    end
    K.scissor(body)
  end

  return W
end
