-- What the staged scenes share (src/apps/evolution.lua, src/apps/caught.lua): the game's words typed out in a
-- glass bubble along the foot (a page at a time, an arrow bobbing when there's more, Yes / No beside it when
-- it asks), a Pokémon's picture drawn at any size and colour -- or as a silhouette of one colour (a shader;
-- plain colour tinting without one) --, a four-pointed sparkle, rays from a point. Nothing made while drawing
-- but a bubble's lines when its words, its width or the text size change.
--
--   Fx = SceneFx(K, T)
--   w = Fx.words()                                   (a bubble's state)
--   Fx.say(w, pages, cb, clock, ask) ; Fx.typing(w, clock) ; Fx.press(w, clock) -> "skip" | "next" | "done" |
--     "ask" ; Fx.clear(w) ; Fx.choice(w, yes) (an answer: its callback with yes)
--   Fx.bubble(w, b, clock, hit, hitYes, hitNo) (hit: a tap on the words) ; Fx.bubbleH()
--   Fx.pic(pic, cx, cy, size, scale, r, g, b, a, flat) (pic = { image, box }; centred; flat: a silhouette)
--   Fx.star(cx, cy, r, c, a, turn) ; Fx.rays(cx, cy, len, n, turn, c, a, width)

local floor, max, min, sin, cos, abs, pi = math.floor, math.max, math.min, math.sin, math.cos, math.abs, math.pi

local UTF8 = "[%z\1-\127\194-\244][\128-\191]*"
local CPS = 46
local SIZE = 4.8
local C = { ink = { 28, 28, 30 }, soft = { 112, 112, 120 }, white = { 255, 255, 255 }, accent = { 10, 132, 255 },
            grey = { 206, 210, 220 } }

return function(K, T)
  local Fx = {}
  local word = T or function(k) return k end

  -- ------- the words

  function Fx.words() return { pages = nil, i = 1, t = 0, cb = nil, ask = false, sel = 1, lines = nil } end
  function Fx.say(w, pages, cb, clock, ask)
    w.pages, w.i, w.t, w.cb, w.ask, w.sel = pages, 1, clock, cb, ask and true or false, 1
    w.full = false
  end
  function Fx.clear(w) w.pages, w.cb, w.ask = nil, nil, false end
  local function count(s)
    local _, n = s:gsub(UTF8, "")
    return n
  end
  local function page(w) return w.pages and w.pages[w.i] or "" end
  local function shown(w, clock)
    if w.full then return math.huge end
    return floor((clock - w.t) * CPS)
  end
  function Fx.typing(w, clock)
    if not w.pages then return false end
    if w.full then return false end
    if w.cnt == nil or w.cntOf ~= page(w) then w.cnt, w.cntOf = count(page(w)), page(w) end
    return shown(w, clock) < w.cnt
  end
  -- (A, or a tap on the words) -> what it did
  function Fx.press(w, clock)
    if not w.pages then return nil end
    if Fx.typing(w, clock) then
      w.full = true
      return "skip"
    end
    if w.i < #w.pages then
      w.i, w.t, w.full = w.i + 1, clock, false
      return "next"
    end
    if w.ask then return "ask" end
    local cb = w.cb
    Fx.clear(w)
    if cb then cb() end
    return "done"
  end
  function Fx.choice(w, yes)
    if not (w.pages and w.ask) then return end
    local cb = w.cb
    Fx.clear(w)
    if cb then cb(yes) end
  end
  function Fx.waiting(w, clock) return w.pages ~= nil and not Fx.typing(w, clock) end

  -- (the lines that fit, each line's typed-out beginnings: made when the words, the width or the size change)
  local function linesOf(text, width, size)
    local lines, line = {}, ""
    for wd in tostring(text or ""):gmatch("%S+") do
      local try = line == "" and wd or (line .. " " .. wd)
      if line ~= "" and K.width(try, size) > width then
        lines[#lines + 1] = line
        line = wd
      else
        line = try
      end
    end
    if line ~= "" then lines[#lines + 1] = line end
    local out = { lines = lines, pre = {}, count = {}, size = size, line = size * 1.32 * K.textScale() }
    for j, l in ipairs(lines) do
      local pre, k, acc = {}, 0, ""
      for ch in l:gmatch(UTF8) do
        k = k + 1
        acc = acc .. ch
        pre[k] = acc
      end
      out.pre[j], out.count[j] = pre, k
    end
    return out
  end

  function Fx.bubbleH() return 21 + (K.textScale() - 1) * 10 end
  local YES_W = 26
  function Fx.bubble(w, b, clock, hit, hitYes, hitNo)
    if not w.pages then return end
    local G = K.graphics()
    local e = K.outCubic((clock - (w.shownAt or clock)) / 0.2)
    if w.lastPages ~= w.pages then w.lastPages, w.shownAt, e = w.pages, clock, 0 end
    local f0 = K.getFade()
    K.setFade(f0 * e)
    local by = b[2] + (1 - e) * 4
    local bb = K.R(b[1], by, b[3], b[4])
    K.glass(bb, 5, 0.9, C.white, 0.6, 0.9)
    local tw = b[3] - 14
    local text = page(w)
    local TS = K.textScale()
    local L = w.lines
    if not L or w.linesW ~= floor(tw) or w.linesText ~= text or w.linesTS ~= TS then
      L = linesOf(text, tw, SIZE)
      local sz = SIZE
      while #L.lines * L.line > b[4] - 5 and sz > SIZE * 0.7 do
        sz = sz - 0.3
        L = linesOf(text, tw, sz)
      end
      w.lines, w.linesW, w.linesText, w.linesTS = L, floor(tw), text, TS
    end
    local left = shown(w, clock)
    local total = #L.lines * L.line
    local ly = by + max(2.5, (b[4] - total) / 2 + 0.3)
    for j = 1, #L.lines do
      local cnt = L.count[j]
      if left >= cnt then
        K.text(L.lines[j], b[1] + 7, ly, L.size, C.ink)
        left = left - cnt
      else
        if left > 0 then K.text(L.pre[j][left], b[1] + 7, ly, L.size, C.ink) end
        break
      end
      ly = ly + L.line
    end
    if Fx.waiting(w, clock) and not w.ask and (w.cb or w.i < #w.pages) then
      local ax, ay = b[1] + b[3] - 6, by + b[4] - 4.5 + abs(sin(clock * 5)) * 0.9
      K.col(C.ink, 0.75)
      G.setLineWidth(max(1, 0.7 * K.sc))
      G.line(K.X(ax - 2), K.Y(ay - 1.2), K.X(ax), K.Y(ay + 0.8), K.X(ax + 2), K.Y(ay - 1.2))
    end
    if hit then K.addHit(bb, "win", hit) end
    -- (a question: Yes / No over the bubble's right end, popping up once the words are out)
    if w.ask and Fx.waiting(w, clock) then
      if not w.askAt or w.askOf ~= w.pages then w.askAt, w.askOf = clock, w.pages end
      local k = K.outBack((clock - w.askAt) / 0.24)
      local bw, bh = YES_W + (TS - 1) * 8, 10 + (TS - 1) * 3
      local x0 = b[1] + b[3] - bw
      for i = 1, 2 do
        local y0 = by - (3 - i) * (bh + 2) - 1 + (1 - min(1, k)) * 6
        local r = K.R(x0, y0, bw, bh)
        local on = w.sel == i
        K.glass(r, bh / 2, 0.92, on and C.accent or C.white, 0.5, 0.9)
        local label = i == 1 and word("evo.yes") or word("evo.no")
        local fs = K.fit(label, 4.6, bw - 4)
        K.bold(label, x0, y0 + (bh - fs * 1.2) / 2, fs, on and C.white or C.ink, "center", bw)
        K.addHit(r, "win", i == 1 and hitYes or hitNo)
      end
    end
    K.setFade(f0)
  end

  -- ------- pictures

  local flatShader = nil
  local function shader()
    if flatShader == nil then
      flatShader = false
      local LG = love and love.graphics
      if LG and LG.newShader then
        local ok, sh = pcall(LG.newShader, [[
          vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec4 t = Texel(tex, tc);
            return vec4(color.rgb, t.a * color.a);
          }
        ]])
        if ok and sh then flatShader = sh end
      end
    end
    return flatShader or nil
  end
  -- a picture centred on cx, cy, `size` units for its square, times `scale`; flat: one colour (r, g, b)
  function Fx.pic(pic, cx, cy, size, scale, r, g, b, a, flat)
    if not (pic and pic.image) or scale <= 0.001 then return end
    local G = K.graphics()
    local img = pic.image
    local iw, ih = img:getDimensions()
    local box = pic.box or max(iw, ih)
    local k = size * K.sc / box * scale
    local sh = flat and shader() or nil
    if sh then G.setShader(sh) end
    G.setColor(r, g, b, (a or 1) * K.getFade())
    G.draw(img, K.X(cx), K.Y(cy), 0, k, k, iw / 2, ih / 2)
    if sh then G.setShader() end
  end

  -- ------- light

  -- a four-pointed sparkle: two thin diamonds crossed (love's fills want convex shapes)
  function Fx.star(cx, cy, r, c, a, turn)
    if r <= 0 then return end
    local G = K.graphics()
    K.col(c, a)
    local x, y = K.X(cx), K.Y(cy)
    local s = r * K.sc
    local t = turn or 0
    local ca, sa = cos(t), sin(t)
    local w = s * 0.22
    G.polygon("fill", x + ca * s, y + sa * s, x - sa * w, y + ca * w, x - ca * s, y - sa * s, x + sa * w, y - ca * w)
    G.polygon("fill", x - sa * s, y + ca * s, x - ca * w, y - sa * w, x + sa * s, y - ca * s, x + ca * w, y + sa * w)
  end

  -- n rays from cx, cy, each a thin wedge `width` radians wide, turned by `turn`
  function Fx.rays(cx, cy, len, n, turn, c, a, width)
    local G = K.graphics()
    K.col(c, a)
    local x, y = K.X(cx), K.Y(cy)
    local L = len * K.sc
    local hw = (width or 0.12) / 2
    for i = 0, n - 1 do
      local t = turn + i * 2 * pi / n
      G.polygon("fill", x, y, x + cos(t - hw) * L, y + sin(t - hw) * L, x + cos(t + hw) * L, y + sin(t + hw) * L)
    end
  end

  return Fx
end
