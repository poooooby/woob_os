-- The Oak's PC app (FireRed / LeafGreen): the Kanto Pokédex as a dashboard (src/oak.lua). A ring filling
-- to how much is caught and the counts running up to it, all 151 as a mosaic that lights up in
-- turn, and Professor Oak's rating in his own words with how far it is to the next one.
--   buttons  B close
--
--   window(ctx, env) -> win (src/apps.lua)   env.oak

local floor, max, min, sin, cos, pi = math.floor, math.max, math.min, math.sin, math.cos, math.pi

local M, GAP = 3, 2.5
local COUNT_UP = 1.0        -- seconds the ring and the counts take
local C = {
  stageTop = { 12, 70, 84 }, stageFoot = { 6, 14, 30 },
  panelTop = { 34, 98, 112, 0.8 }, panelFoot = { 12, 42, 60, 0.8 },
  lime = { 130, 244, 170 }, limeDeep = { 40, 170, 120 }, gold = { 252, 204, 60 }, goldDeep = { 190, 130, 20 },
  seen = { 90, 170, 190 }, none = { 255, 255, 255, 0.07 }, track = { 255, 255, 255, 0.12 },
  text = { 240, 250, 248 }, soft = { 170, 204, 206 }, white = { 255, 255, 255 },
}
local HINTS = { { "B", "hint.close" } }
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env)
  local K, Ok, T = env.K, env.oak, env.T or NO_T
  local W = { title = T("app.oak") }
  local s = ctx.session or (env.session and env.session())
  local r = Ok.rating(s)
  local st = { rating = r, t0 = nil, cols = 0, rows = 0, tile = 0, forW = -1, forH = -1 }
  W.state = st

  local numText = K.textCache(function(n) return tostring(n) end)
  local pctText = K.textCache(function(n) return tostring(n) .. "%" end)
  local ofText = "/ " .. tostring(Ok.TOTAL)
  local part = min(1, r.caught / Ok.TOTAL)
  local accent, accentDeep = r.complete and C.gold or C.lime, r.complete and C.goldDeep or C.limeDeep
  local nextText = r.complete and T("oak.complete") or (r.toNext and T.f("oak.next", r.toNext)) or ""
  local portrait0 = Ok.picture()

  function W.input(input)
    if input:wasPressed("b") then return false end
    return true
  end
  function W.hints() return T.list(HINTS) end

  local function panel(b, rad)
    K.grad(b, rad, C.panelTop, C.panelFoot)
    K.ring(b, rad, C.white, 0.1, 0.4)
  end

  local function sparkle(cx, cy, size, c, a)
    local g = K.graphics()
    K.col(c, a)
    local x, y, q, n = K.X(cx), K.Y(cy), size * K.sc, size * K.sc * 0.3
    g.polygon("fill", x, y - q, x + n, y, x, y + q, x - n, y)
    g.polygon("fill", x - q, y, x, y - n, x + q, y, x, y + n)
  end

  local function drawRing(cx, cy, rad, e, clock)
    local g = K.graphics()
    local now = part * e
    K.glow(cx, cy, rad * 1.9, rad * 1.9, accent, 0.22 + 0.05 * sin(clock * 2))
    g.setLineWidth(max(1, rad * 0.24 * K.sc))
    K.col(C.track)
    g.circle("line", K.X(cx), K.Y(cy), rad * K.sc, 64)
    if now > 0 then
      K.col(accent)
      g.arc("line", "open", K.X(cx), K.Y(cy), rad * K.sc, -pi / 2, -pi / 2 + now * 2 * pi, 64)
      -- (its leading end, lit)
      local a = -pi / 2 + now * 2 * pi
      local ex, ey = cx + cos(a) * rad, cy + sin(a) * rad
      K.glow(ex, ey, rad * 0.26, rad * 0.26, C.white, 0.55)
    end
    local fs = rad * 0.62
    K.bold(pctText(floor(now * 100 + 0.5)), cx - rad, cy - fs * 0.62, fs, accent, "center", rad * 2)
    if r.complete then
      for i = 1, 5 do
        local t = clock * 0.6 + i * 2 * pi / 5
        sparkle(cx + cos(t) * rad * 1.35, cy + sin(t) * rad * 1.35, 1.6 + sin(clock * 5 + i), C.gold, 0.9)
      end
    end
  end

  local function stat(x, y, w, h, label, value)
    panel(K.R(x, y, w, h), 3)
    K.text(label, x, y + 1.4, K.fit(label, 3.6, w - 2), C.soft, "center", w)
    K.bold(numText(value), x, y + 5.6, 7, C.white, "center", w)
    K.text(ofText, x, y + h - 5, 3.2, C.soft, "center", w)
  end

  -- how many columns make the tiles biggest in w x h (worked out when the size changes)
  local function fit(w, h)
    if st.forW == w and st.forH == h then return end
    st.forW, st.forH = w, h
    local best = 0
    for cols = 8, 40 do
      local rows = math.ceil(Ok.TOTAL / cols)
      local tile = min(w / cols, h / rows)
      if tile > best then best, st.cols, st.rows = tile, cols, rows end
    end
    st.tile = best
  end

  -- all 151: lit in turn, the caught ones shimmering
  local function drawMosaic(x, y, w, h, age, clock)
    panel(K.R(x, y, w, h), 4)
    local ix, iy, iw, ih = x + 3, y + 3, w - 6, h - 6
    fit(iw, ih)
    local t = st.tile
    local ox, oy = ix + (iw - t * st.cols) / 2, iy + (ih - t * st.rows) / 2
    local cell = t * 0.84
    local map = r.map
    for i = 1, Ok.TOTAL do
      local cx, cy = ox + (i - 1) % st.cols * t, oy + floor((i - 1) / st.cols) * t
      local v = map[i]
      local a = min(1, max(0, (age * 150 - i) / 18))
      if v == 2 then
        K.col(accent, a * (0.78 + 0.22 * sin(clock * 2 - i * 0.22)))
      elseif v == 1 then
        K.col(C.seen, a * 0.6)
      else
        K.col(C.none, a)
      end
      K.box("fill", K.R(cx, cy, cell, cell), cell * 0.28)
    end
  end

  local function drawBubble(x, y, w, h, e)
    panel(K.R(x, y, w, h), 4)
    local ps = min(h - 6, 30)
    local px, py = x + 3, y + (h - ps) / 2
    local g = K.graphics()
    K.glow(px + ps / 2, py + ps / 2, ps * 0.8, ps * 0.8, accent, 0.3)
    K.col(C.white, 0.12)
    g.circle("fill", K.X(px + ps / 2), K.Y(py + ps / 2), ps * 0.5 * K.sc)
    if portrait0 then
      local k = ps * K.sc / portrait0:getWidth()
      g.setColor(1, 1, 1, 1)
      g.draw(portrait0, K.X(px), K.Y(py), 0, k, k)
    end
    local tx = px + ps + 4
    local tw = x + w - tx - 4
    K.bold(T("oak.rating"), tx, y + 3, 4.6, accent)
    K.text(r.words, tx, y + 9.5, 4.3, C.text, "left", tw)
    -- how far to his next rating
    local by = y + h - 9
    K.text(nextText, tx, by, K.fit(nextText, 3.6, tw), C.soft)
    local bar = K.R(tx, y + h - 4, tw, 1.8)
    K.col(C.track)
    K.box("fill", bar, 0.9)
    local f = (r.complete and 1 or r.toward) * e
    if f > 0 then K.grad(K.R(tx, y + h - 4, max(1.8, tw * f), 1.8), 0.9, accent, accentDeep) end
  end

  function W.draw(body, clock, portrait)
    local x, y, w, h = body[1], body[2], body[3], body[4]
    st.t0 = st.t0 or clock
    local age = clock - st.t0
    local e = min(1, age / COUNT_UP)
    e = 1 - (1 - e) * (1 - e) * (1 - e)
    K.grad(body, 0, C.stageTop, C.stageFoot)
    K.glow(x + w * 0.2, y + h * 0.35, w * 0.5, h * 0.8, C.lime, 0.08)
    local seen, caught = floor(r.seen * e + 0.5), floor(r.caught * e + 0.5)
    if portrait then
      local ringH = min(h * 0.3, 74)
      local rad = min(ringH * 0.4, w * 0.2)
      drawRing(x + M + rad * 1.5, y + M + ringH / 2, rad, e, clock)
      local sx = x + M + rad * 3.1
      local sw = (x + w - M - sx - GAP) / 2
      stat(sx, y + M + (ringH - 22) / 2, sw, 22, T("oak.seen"), seen)
      stat(sx + sw + GAP, y + M + (ringH - 22) / 2, sw, 22, T("oak.caught"), caught)
      local my = y + M + ringH + GAP
      local bubble = min(50, h * 0.26)
      drawMosaic(x + M, my, w - M * 2, y + h - M - bubble - GAP - my, age, clock)
      drawBubble(x + M, y + h - M - bubble, w - M * 2, bubble, e)
    else
      local lw = max(66, floor(w * 0.32))
      local statH = 22
      local rad = min((h - M * 2 - statH - GAP) * 0.36, lw * 0.33)
      drawRing(x + M + lw / 2, y + M + (h - M * 2 - statH - GAP) / 2, rad, e, clock)
      local sw = (lw - GAP) / 2
      local sy = y + h - M - statH
      stat(x + M, sy, sw, statH, T("oak.seen"), seen)
      stat(x + M + sw + GAP, sy, sw, statH, T("oak.caught"), caught)
      local rx = x + M + lw + GAP
      local rw = w - M * 2 - lw - GAP
      local bubble = min(46, floor(h * 0.44))
      drawMosaic(rx, y + M, rw, h - M * 2 - bubble - GAP, age, clock)
      drawBubble(rx, y + h - M - bubble, rw, bubble, e)
    end
  end

  return W
end
