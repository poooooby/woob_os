-- Decorative vector motifs for the modern menus: a picture for each type (the game's ids 0..18, 9 the "???")
-- and for each of the Bag's pockets, drawn in one colour at any size and turn, and a slow drifting scatter of
-- them for a page's background. Shapes are kept as constant point lists (love's fills want convex ones, so
-- each picture is built of convex pieces, circles and lines). Each is painted once, solid white, into a
-- small canvas of its own (the pieces overlap: drawn faded one by one their overlaps showed as seams), then
-- drawn from it tinted and faded; without canvases (headless) the pieces are drawn straight. Nothing is made
-- while drawing but each picture's canvas, once.
--
--   Art = typeArt(K)
--   Art.type(id, cx, cy, size, turn, c, a) ; Art.pocket(name, cx, cy, size, turn, c, a)   (units, centre)
--   Art.scatter(kind, key, b, clock, c, a)   kind "type" | "pocket": a field of them over b, drifting

local sin, cos, pi, floor = math.sin, math.cos, math.pi, math.floor

-- (convex pieces in a -1..1 box)
local P = {
  boltA = { -0.15, -1, 0.5, -1, 0.05, -0.1, -0.45, -0.1 },
  boltB = { 0.05, -0.1, 0.45, -0.1, -0.2, 1, -0.05, 0.25 },
  tri = { 0, -1, 0.87, 0.5, -0.87, 0.5 },
  triDown = { 0, 1, 0.87, -0.5, -0.87, -0.5 },
  flameTop = { -0.55, 0.15, 0, -1, 0.55, 0.15 },
  flameTongue = { -0.4, 0.3, -0.05, -0.75, 0, -1, 0.05, -0.75, 0.4, 0.3 },
  -- (a flame's outline: the tip, down its right side round the base, up to the small lick on the left, into
  -- the notch, up the main tongue's inner edge back to the tip)
  flame = { 0.09, -1.02, 0.22, -0.86, 0.34, -0.65, 0.47, -0.44, 0.56, -0.22, 0.65, 0.02, 0.70, 0.26, 0.68, 0.49,
            0.61, 0.70, 0.49, 0.85, 0.34, 0.93, 0.18, 0.98, 0.02, 1.0, -0.17, 0.98, -0.35, 0.93, -0.50, 0.85,
            -0.62, 0.74, -0.70, 0.58, -0.74, 0.39, -0.74, 0.21, -0.71, 0.04, -0.67, -0.10, -0.60, -0.23,
            -0.56, -0.12, -0.51, -0.03, -0.44, 0.05, -0.36, 0.11, -0.28, 0.14, -0.21, 0.13, -0.19, 0.0,
            -0.20, -0.13, -0.18, -0.31, -0.15, -0.48, -0.10, -0.64, -0.04, -0.79, 0.02, -0.92 },
  flameSmall = { -0.28, 0.45, 0.05, -0.35, 0.32, 0.45 },
  dropTop = { -0.5, 0.25, 0, -0.95, 0.5, 0.25 },
  rock = { -0.7, -0.35, -0.2, -0.8, 0.55, -0.6, 0.85, 0.1, 0.4, 0.75, -0.45, 0.7, -0.85, 0.2 },
  claw = { -0.25, 0.8, 0.0, -0.9, 0.25, 0.8 },
  diamondTall = { 0, -1, 0.22, 0, 0, 1, -0.22, 0 },
  diamondWide = { -1, 0, 0, -0.22, 1, 0, 0, 0.22 },
  diamond = { 0, -0.75, 0.75, 0, 0, 0.75, -0.75, 0 },
  pyramid = { 0, -0.85, 0.95, 0.75, -0.95, 0.75 },
  keyTooth = { 0.62, 0.08, 0.9, 0.08, 0.9, 0.55, 0.62, 0.55 },
  keyTooth2 = { 0.3, 0.08, 0.5, 0.08, 0.5, 0.4, 0.3, 0.4 },
  bottle = { -0.5, -0.2, 0.5, -0.2, 0.5, 0.85, -0.5, 0.85 },
  neck = { -0.2, -0.65, 0.2, -0.65, 0.2, -0.2, -0.2, -0.2 },
  cap = { -0.3, -0.9, 0.3, -0.9, 0.3, -0.65, -0.3, -0.65 },
  hem = { -0.7, -0.1, 0.7, -0.1, 0.7, 0.6, -0.7, 0.6 },
}
local SEG = 28

return function(K)
  local Art = {}
  local G = nil
  local function poly(t) G.polygon("fill", t) end
  local function lw(w) G.setLineWidth(w) end
  -- (the flame's outline cut into triangles, once: it isn't convex)
  local flameT = nil
  local function flameTris()
    if flameT == nil then
      local ok, tris = pcall(function() return love.math.triangulate(P.flame) end)
      flameT = ok and type(tris) == "table" and #tris > 0 and tris or false
    end
    return flameT or nil
  end
  -- (one of a flame's tongues: the stand-in without love.math)
  local function tongue(x, y, turn, k)
    G.push() G.translate(x, y) G.rotate(turn) G.scale(k)
    G.circle("fill", 0, 0.35, 0.42, SEG) poly(P.flameTongue)
    G.pop()
  end

  -- (each type's picture in the -1..1 box, the colour already set)
  local TYPE_DRAW = {
    [0] = function() -- Normal: a ring and its centre
      lw(0.16) G.circle("line", 0, 0, 0.75, SEG) G.circle("fill", 0, 0, 0.28, SEG)
    end,
    [1] = function() -- Fighting: a burst
      poly(P.tri) poly(P.triDown)
    end,
    [2] = function() -- Flying: a wing of three feathers
      for i = 0, 2 do
        G.push() G.rotate(-0.5 + i * 0.45) G.ellipse("fill", 0.25, -0.05, 0.75, 0.2, SEG) G.pop()
      end
    end,
    [3] = function() -- Poison: bubbles
      G.circle("fill", -0.3, 0.3, 0.45, SEG) G.circle("fill", 0.45, -0.1, 0.3, SEG) G.circle("fill", 0.05, -0.65, 0.2, SEG)
    end,
    [4] = function() -- Ground: layers
      G.rectangle("fill", -0.9, 0.35, 1.8, 0.35, 0.15) G.rectangle("fill", -0.65, -0.1, 1.3, 0.32, 0.14)
      G.rectangle("fill", -0.4, -0.52, 0.8, 0.3, 0.13)
    end,
    [5] = function() poly(P.rock) end, -- Rock: a stone
    [6] = function() -- Bug: a beetle
      G.ellipse("fill", 0, 0.2, 0.55, 0.7, SEG) G.circle("fill", 0, -0.65, 0.28, SEG)
      lw(0.1) G.line(-0.12, -0.85, -0.4, -1.05) G.line(0.12, -0.85, 0.4, -1.05)
    end,
    [7] = function() -- Ghost: a sheet with a wavy hem
      G.circle("fill", 0, -0.2, 0.7, SEG) poly(P.hem)
      G.circle("fill", -0.47, 0.6, 0.23, SEG) G.circle("fill", 0, 0.6, 0.23, SEG) G.circle("fill", 0.47, 0.6, 0.23, SEG)
    end,
    [8] = function() -- Steel: a gear
      G.circle("fill", 0, 0, 0.6, SEG)
      for i = 0, 7 do
        G.push() G.rotate(i * pi / 4) G.rectangle("fill", -0.14, -0.92, 0.28, 0.4) G.pop()
      end
    end,
    [9] = function() -- ???: a ring and a dot
      lw(0.18) G.arc("line", "open", 0, -0.25, 0.45, pi * 1.05, pi * 2.35, SEG) G.circle("fill", 0, 0.7, 0.14, SEG)
    end,
    [10] = function() -- Fire: a flame, its main tongue and a small lick (its outline in triangles, made once)
      local tris = flameTris()
      if tris then
        for i = 1, #tris do poly(tris[i]) end
        return
      end
      tongue(-0.36, 0.22, -0.5, 0.62)
      tongue(0, 0, 0, 1)
      G.circle("fill", 0, 0.5, 0.45, SEG)
    end,
    [11] = function() -- Water: a drop
      G.circle("fill", 0, 0.35, 0.52, SEG) poly(P.dropTop)
    end,
    [12] = function() -- Grass: a leaf and its vein
      G.push() G.rotate(pi / 4) G.ellipse("fill", 0, 0, 0.42, 0.95, SEG) G.pop()
      lw(0.07) G.line(-0.55, 0.55, 0.5, -0.5)
    end,
    [13] = function() poly(P.boltA) poly(P.boltB) end, -- Electric: a bolt
    [14] = function() -- Psychic: rings round a point
      lw(0.13) G.circle("line", 0, 0, 0.85, SEG) G.circle("line", 0, 0, 0.5, SEG) G.circle("fill", 0, 0, 0.18, SEG)
    end,
    [15] = function() -- Ice: a snowflake
      lw(0.13)
      for i = 0, 2 do
        G.push() G.rotate(i * pi / 3) G.line(0, -0.9, 0, 0.9)
        G.line(0, -0.6, -0.22, -0.82) G.line(0, -0.6, 0.22, -0.82) G.line(0, 0.6, -0.22, 0.82) G.line(0, 0.6, 0.22, 0.82)
        G.pop()
      end
    end,
    [16] = function() -- Dragon: three claws
      for i = -1, 1 do
        G.push() G.translate(i * 0.45, 0) G.rotate(i * 0.2) poly(P.claw) G.pop()
      end
    end,
    [17] = function() -- Dark: a crescent
      lw(0.32) G.arc("line", "open", 0.12, 0, 0.62, pi * 0.6, pi * 1.4, SEG)
    end,
    [18] = function() -- Fairy: a sparkle
      poly(P.diamondTall) poly(P.diamondWide)
      G.push() G.translate(0.65, -0.6) G.scale(0.35) poly(P.diamondTall) poly(P.diamondWide) G.pop()
    end,
  }

  -- (each pocket's)
  local POCKET_DRAW = {
    ITEMS = function() -- a medicine bottle
      G.rectangle("fill", P.bottle[1], P.bottle[2], 1, 1.05, 0.18) poly(P.neck) poly(P.cap)
    end,
    KEY_ITEMS = function() -- a key, lying across: its bow, its shaft, two teeth
      lw(0.2) G.circle("line", -0.55, 0, 0.32, SEG)
      G.rectangle("fill", -0.25, -0.1, 1.15, 0.2) poly(P.keyTooth) poly(P.keyTooth2)
    end,
    POKE_BALLS = function() -- a Poké Ball's outline
      lw(0.14) G.circle("line", 0, 0, 0.85, SEG) G.line(-0.85, 0, -0.3, 0) G.line(0.3, 0, 0.85, 0)
      G.circle("line", 0, 0, 0.3, SEG) G.circle("fill", 0, 0, 0.13, SEG)
    end,
    TM_CASE = function() -- a disc
      lw(0.14) G.circle("line", 0, 0, 0.85, SEG) G.circle("line", 0, 0, 0.25, SEG)
      G.arc("line", "open", 0, 0, 0.58, -pi * 0.9, -pi * 0.55, SEG)
    end,
    BERRY_POUCH = function() -- a berry, its stem and a broad leaf
      G.circle("fill", 0, 0.25, 0.62, SEG)
      lw(0.1) G.line(0, -0.3, 0.05, -0.62)
      G.push() G.translate(0.32, -0.66) G.rotate(-0.45) G.ellipse("fill", 0, 0, 0.36, 0.17, SEG) G.pop()
      G.push() G.translate(-0.28, -0.6) G.rotate(0.5) G.ellipse("fill", 0, 0, 0.26, 0.12, SEG) G.pop()
    end,
    PYRAMID = function() -- a pyramid
      poly(P.pyramid)
    end,
  }
  POCKET_DRAW.BERRIES, POCKET_DRAW.TM_HM = POCKET_DRAW.BERRY_POUCH, POCKET_DRAW.TM_CASE

  -- (each picture painted once into its own canvas)
  local PX = 256
  local canvases = {}
  local function canvasOf(fn)
    local cv = canvases[fn]
    if cv ~= nil then return cv or nil end
    G = K.graphics()
    local ok, made = pcall(function()
      -- (smoothed edges where the graphics allow it: it's drawn large in a corner)
      local okM, c = pcall(love.graphics.newCanvas, PX, PX, { msaa = 4 })
      if not (okM and c) then c = love.graphics.newCanvas(PX, PX) end
      c:setFilter("linear", "linear")
      local prev = G.getCanvas()
      G.push("all")
      G.setCanvas(c)
      G.clear(0, 0, 0, 0)
      G.origin()
      G.setScissor()
      G.setColor(1, 1, 1, 1)
      G.translate(PX / 2, PX / 2)
      G.scale(PX * 0.44)
      fn()
      G.setCanvas(prev)
      G.pop()
      return c
    end)
    cv = ok and made or false
    canvases[fn] = cv
    K.rescissor()
    return cv or nil
  end

  local function draw(fn, cx, cy, size, turn, c, a)
    if not fn then return end
    G = K.graphics()
    local cv = canvasOf(fn)
    if cv then
      K.col(c, a)
      local k = size * K.sc / (PX * 0.88)
      G.draw(cv, K.X(cx), K.Y(cy), turn or 0, k, k, PX / 2, PX / 2)
      return
    end
    local lw0 = G.getLineWidth()
    K.col(c, a)
    G.push()
    G.translate(K.X(cx), K.Y(cy))
    if turn and turn ~= 0 then G.rotate(turn) end
    G.scale(size * 0.5 * K.sc)
    fn()
    G.pop()
    G.setLineWidth(lw0)
  end
  function Art.type(id, cx, cy, size, turn, c, a) draw(TYPE_DRAW[id or 0] or TYPE_DRAW[0], cx, cy, size, turn, c, a) end
  function Art.pocket(name, cx, cy, size, turn, c, a) draw(POCKET_DRAW[name] or POCKET_DRAW.ITEMS, cx, cy, size, turn, c, a) end

  -- a field of them over b: fixed places (fractions of b), each size and speed its own, drifting and turning
  local FIELD = {
    { 0.08, 0.18, 16, 0.3 }, { 0.3, 0.08, 10, -0.2 }, { 0.52, 0.22, 22, 0.15 }, { 0.78, 0.1, 13, -0.35 },
    { 0.93, 0.36, 18, 0.25 }, { 0.16, 0.55, 12, -0.25 }, { 0.42, 0.62, 9, 0.4 }, { 0.66, 0.5, 15, -0.15 },
    { 0.88, 0.72, 11, 0.3 }, { 0.06, 0.88, 20, -0.1 }, { 0.34, 0.9, 14, 0.2 }, { 0.6, 0.86, 24, -0.3 },
  }
  function Art.scatter(kind, key, b, clock, c, a)
    local x, y, w, h = b[1], b[2], b[3], b[4]
    local one = kind == "pocket" and POCKET_DRAW[key] or TYPE_DRAW[key or 0] or TYPE_DRAW[0]
    for i = 1, #FIELD do
      local f = FIELD[i]
      local sp = f[4]
      local cx = x + w * f[1] + sin(clock * 0.13 * sp + i) * 4
      local cy = y + h * f[2] + cos(clock * 0.11 * sp + i * 1.7) * 3
      -- (upright, swaying a little: a flame or a drop has a way up)
      draw(one, cx, cy, f[3], sp * 0.8 + sin(clock * 0.5 * (0.6 + sp) + i) * 0.22, c, a * (0.75 + 0.25 * sin(clock * 0.4 + i)))
    end
  end

  return Art
end
