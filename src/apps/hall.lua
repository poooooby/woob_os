-- The Hall of Fame app: every team the game recorded (src/hall.lua), newest first, as a trophy case:
-- the team's six on their cards, the chosen one large with its name, level and ID. Each one chosen
-- calls out.
--   buttons  the D-pad the Pokémon, L / R the team, A its cry, B close
--   touch    a card, the arrows by the title
--
--   window(ctx, env) -> win (src/apps.lua)   env.hall

local floor, max, min, sin = math.floor, math.max, math.min, math.sin

local M, GAP = 3, 2
local OLDER, NEWER, CARD = 2001, 2002, 2100
local C = {
  stageTop = { 54, 40, 18 }, stageFoot = { 16, 11, 8 }, cardTop = { 74, 58, 30 }, cardFoot = { 42, 32, 18 },
  on = { 104, 82, 40 }, onFoot = { 62, 48, 24 }, gold = { 252, 204, 60 }, goldTop = { 255, 232, 130 }, goldDark = { 170, 116, 16 },
  text = { 248, 242, 226 }, soft = { 204, 188, 150 }, faint = { 130, 114, 84 }, male = { 110, 170, 255 }, female = { 255, 120, 150 },
  white = { 255, 255, 255 },
}
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
    end
  end

  local function current() return st.teams[st.team] end
  local function chosen()
    local t = current()
    return t and t.members[st.pick]
  end
  local function pick(i)
    local t = current()
    if not (t and t.members[i]) or i == st.pick then return end
    st.pick = i
    Hl.cry(chosen())
  end
  local function team(d)
    local i = max(1, min(#st.teams, st.team + d))
    if i == st.team then return end
    st.team, st.pick = i, 1
    se("SE_SELECT")
    Hl.cry(chosen())
  end
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
    if type(arg) == "number" and arg > CARD then pick(arg - CARD) end
  end
  function W.hints() return T.list(HINTS) end
  function W.close() Hl.stop() end

  -- ------- drawing (no tables made here)

  local function genderMark(g, x, y, s)
    if not g then return end
    local G, sc = K.graphics(), K.sc
    K.col(g == "M" and C.male or C.female)
    G.setLineWidth(max(1, s * 0.16 * sc))
    local r = s * 0.28
    if g == "M" then
      local cx, cy = x + r, y + s - r
      G.circle("line", K.X(cx), K.Y(cy), r * sc)
      G.line(K.X(cx + r * 0.7), K.Y(cy - r * 0.7), K.X(x + s), K.Y(y))
      G.line(K.X(x + s - s * 0.32), K.Y(y), K.X(x + s), K.Y(y))
      G.line(K.X(x + s), K.Y(y), K.X(x + s), K.Y(y + s * 0.32))
    else
      local cx, cy = x + s / 2, y + r
      G.circle("line", K.X(cx), K.Y(cy), r * sc)
      G.line(K.X(cx), K.Y(cy + r), K.X(cx), K.Y(y + s))
      G.line(K.X(cx - s * 0.24), K.Y(y + s * 0.78), K.X(cx + s * 0.24), K.Y(y + s * 0.78))
    end
  end

  local function pic(m, x, y, size)
    if env.monPic then pcall(env.monPic, m.species, x, y, size, 1, m.picMon) end
  end

  local function drawHeader(x, y, w)
    local t = current()
    K.bold(t.title, x, y + 1.5, 6, C.goldTop, "center", w)
    if st.team < #st.teams then
      K.chevron(x + 5, y + 5, 5, C.gold, -1)
      K.addHit(K.R(x, y, 14, 11), "win", OLDER)
    end
    if st.team > 1 then
      K.chevron(x + w - 5, y + 5, 5, C.gold, 1)
      K.addHit(K.R(x + w - 14, y, 14, 11), "win", NEWER)
    end
  end

  local function drawCards(x, y, w, h, clock)
    local t = current()
    local cw, ch = (w - GAP * 2) / 3, (h - GAP) / 2
    for i = 1, 6 do
      local cx, cy = x + (i - 1) % 3 * (cw + GAP), y + floor((i - 1) / 3) * (ch + GAP)
      local b = K.R(cx, cy, cw, ch)
      local m = t.members[i]
      if m then
        local on = i == st.pick
        if on then K.grad(b, 3.5, C.on, C.onFoot) else K.grad(b, 3.5, C.cardTop, C.cardFoot) end
        if on then K.ring(b, 3.5, C.gold, 0.75 + 0.25 * sin(clock * 5), 0.8) end
        local s = min(cw - 4, ch - 8)
        pic(m, cx + (cw - s) / 2, cy + 1, s)
        local fs = K.fit(m.nickname, 4, cw - 3)
        K.text(m.nickname, cx, cy + ch - fs - 1.6, fs, on and C.goldTop or C.text, "center", cw)
        K.addHit(b, "win", CARD + i)
      else
        K.col(C.cardFoot, 0.4)
        K.box("fill", b, 3.5)
      end
    end
  end

  local function drawDetail(x, y, w, h)
    local m = chosen()
    if not m then return end
    local b = K.R(x, y, w, h)
    K.grad(b, 4, C.cardTop, C.cardFoot)
    K.ring(b, 4, C.gold, 0.4, 0.5)
    local s = min(w - 8, h - 30, 56)
    pic(m, x + (w - s) / 2, y + 2, s)
    local ty = y + s + 3
    local fs = K.fit(m.nickname, 6, w - 6)
    K.bold(m.nickname, x, ty, fs, C.goldTop, "center", w)
    local below = ty + 7.5
    if m.sameName then
      -- (no nickname: the name once, its gender beside it)
      genderMark(m.gender, x + (w + K.width(m.nickname, fs)) / 2 + 1.5, ty + 1, 3.6)
    else
      local nw = K.width(m.name, 4.4)
      local left = x + (w - nw - (m.gender and 5 or 0)) / 2
      K.text(m.name, left, below, 4.4, C.soft)
      genderMark(m.gender, left + nw + 1.5, below + 0.2, 3.6)
      below = below + 5.5
    end
    K.text(m.levelText, x, below, 4.4, C.text, "center", w)
    K.text(m.idText, x, below + 5.5, 3.8, C.soft, "center", w)
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    K.grad(body, 0, C.stageTop, C.stageFoot)
    if not current() then
      K.text(T("hall.none"), x, y + h / 2 - 3, 5, C.soft, "center", w)
      return
    end
    local top = y + 14
    local bodyH = h - 14 - M
    if portrait then
      drawHeader(x + M, y + M, w - M * 2)
      local cards = min(bodyH * 0.5, (w - M * 2) * 0.8)
      drawCards(x + M, top, w - M * 2, cards, clock)
      drawDetail(x + M, top + cards + GAP, w - M * 2, bodyH - cards - GAP)
    else
      local dw = min(70, floor(w * 0.34))
      local cw = w - M * 2 - GAP - dw
      drawHeader(x + M, y + M, cw)
      drawCards(x + M, top, cw, bodyH, clock)
      drawDetail(x + w - M - dw, y + M, dw, h - M * 2)
    end
  end

  return W
end
