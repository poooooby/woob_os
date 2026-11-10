-- The set of pictures an app's icon can use: white on the app's tile, in the app's colour. Other mods
-- choose one by name when they register an app (see src/apps.lua).
--
--   Ic.NAMES                                  the names, in the order they're documented
--   Ic.has(name) -> bool
--   Ic.draw(G, name, cx, cy, s, a, tile)      centred on cx, cy (window pixels), s the tile's size in
--                                             pixels ; tile = { r, g, b } 0..255: the colour its holes show
--
-- Each picture is drawn on a tile one unit across, centred on 0, 0. Love's polygons must be convex: a
-- curved outline is baked once here and filled as a fan from a point that sees all of it. Nothing
-- in a draw makes garbage.

local pi = math.pi
local cos, sin, max = math.cos, math.sin, math.max

local LINE = 0.078

-- a closed outline through these points, rounded (a point given twice stays sharp)
local function smooth(pts)
  local STEPS = 6
  local out, n = {}, #pts / 2
  local function at(i)
    i = (i - 1) % n
    return pts[i * 2 + 1], pts[i * 2 + 2]
  end
  for i = 1, n do
    local x0, y0 = at(i - 1)
    local x1, y1 = at(i)
    local x2, y2 = at(i + 1)
    local x3, y3 = at(i + 2)
    for k = 0, STEPS - 1 do
      local t = k / STEPS
      local t2, t3 = t * t, t * t * t
      out[#out + 1] = 0.5 * (2 * x1 + (x2 - x0) * t + (2 * x0 - 5 * x1 + 4 * x2 - x3) * t2 + (3 * x1 - x0 - 3 * x2 + x3) * t3)
      out[#out + 1] = 0.5 * (2 * y1 + (y2 - y0) * t + (2 * y0 - 5 * y1 + 4 * y2 - y3) * t2 + (3 * y1 - y0 - 3 * y2 + y3) * t3)
    end
  end
  return out
end

local function fan(G, p, cx, cy)
  local n = #p
  local x0, y0 = p[n - 1], p[n]
  for i = 1, n - 1, 2 do
    local x, y = p[i], p[i + 1]
    G.polygon("fill", cx, cy, x0, y0, x, y)
    x0, y0 = x, y
  end
end

-- the baked outlines
local FLAME = smooth({ 0.05, -0.36, 0.05, -0.36, 0.1, -0.2, 0.23, -0.05, 0.27, 0.12, 0.15, 0.28, 0, 0.32,
  -0.15, 0.28, -0.27, 0.12, -0.25, -0.03, -0.17, -0.15, -0.17, -0.15, -0.11, -0.06, -0.03, -0.17 })
local FLAME_CORE = smooth({ 0.01, -0.03, 0.01, -0.03, 0.09, 0.08, 0.12, 0.17, 0.05, 0.25, -0.05, 0.25, -0.12, 0.17, -0.09, 0.08 })
local BELL = smooth({ 0, -0.26, 0.11, -0.21, 0.16, -0.08, 0.18, 0.05, 0.25, 0.15, 0.25, 0.15, -0.25, 0.15, -0.25, 0.15,
  -0.18, 0.05, -0.16, -0.08, -0.11, -0.21 })
local SHOE = smooth({ -0.32, 0.18, -0.32, 0.18, -0.33, -0.04, -0.28, -0.17, -0.17, -0.13, -0.08, -0.21,
  -0.01, -0.12, 0.12, -0.03, 0.26, 0.02, 0.34, 0.1, 0.34, 0.18, 0.34, 0.18 })
local GLOVE = smooth({ -0.02, -0.33, 0.16, -0.3, 0.27, -0.14, 0.25, 0.04, 0.15, 0.15, 0.15, 0.15, -0.13, 0.15, -0.13, 0.15,
  -0.16, 0.0, -0.17, -0.18 })
local THUMB = smooth({ -0.14, -0.1, -0.25, -0.13, -0.32, -0.04, -0.26, 0.07, -0.13, 0.08 })

-- half an ellipse, its ends at +-rx on y = 0 and bulging downward: the database's rings
local RING = {}
do
  local N = 18
  for i = 0, N do
    local an = i / N * pi
    RING[#RING + 1] = cos(an) * 0.25
    RING[#RING + 1] = sin(an) * 0.09
  end
end

local DRAW = {}

function DRAW.controller(G, a, r, g, b)
  G.rectangle("fill", -0.3, -0.15, 0.6, 0.24, 0.1, 0.1)
  G.circle("fill", -0.21, 0.09, 0.12)
  G.circle("fill", 0.21, 0.09, 0.12)
  G.setColor(r, g, b, a)
  G.rectangle("fill", -0.245, -0.055, 0.15, 0.05)
  G.rectangle("fill", -0.195, -0.105, 0.05, 0.15)
  G.circle("fill", 0.135, -0.005, 0.034)
  G.circle("fill", 0.215, -0.075, 0.034)
end

function DRAW.screen(G)
  G.rectangle("line", -0.3, -0.26, 0.6, 0.39, 0.04, 0.04)
  G.rectangle("fill", -0.04, 0.13, 0.08, 0.11)
  G.rectangle("fill", -0.15, 0.22, 0.3, 0.06, 0.02, 0.02)
end

function DRAW.headphones(G)
  G.setLineWidth(0.075)
  G.arc("line", "open", 0, 0.03, 0.27, pi, 2 * pi)
  G.rectangle("fill", -0.335, 0.01, 0.13, 0.25, 0.05, 0.05)
  G.rectangle("fill", 0.205, 0.01, 0.13, 0.25, 0.05, 0.05)
end

function DRAW.speaker(G)
  G.rectangle("fill", -0.32, -0.1, 0.14, 0.2, 0.02, 0.02)
  G.polygon("fill", -0.19, -0.1, -0.02, -0.26, -0.02, 0.26, -0.19, 0.1)
  G.arc("line", "open", -0.02, 0, 0.14, -pi / 4, pi / 4)
  G.arc("line", "open", -0.02, 0, 0.27, -pi / 4, pi / 4)
end

function DRAW.cube(G, a)
  G.setColor(1, 1, 1, 0.42 * a)
  G.polygon("fill", 0, -0.31, 0.27, -0.155, 0, 0, -0.27, -0.155)
  G.setColor(1, 1, 1, a)
  G.polygon("line", 0, -0.31, 0.27, -0.155, 0.27, 0.155, 0, 0.31, -0.27, 0.155, -0.27, -0.155)
  G.line(-0.27, -0.155, 0, 0, 0.27, -0.155)
  G.line(0, 0, 0, 0.31)
end

function DRAW.letters(G)
  G.setLineWidth(0.085)
  G.setLineJoin("bevel")
  G.line(-0.34, 0.24, -0.15, -0.24, 0.04, 0.24)
  G.setLineJoin("miter")
  G.line(-0.27, 0.07, -0.03, 0.07)
  G.circle("line", 0.195, 0.11, 0.105)
  G.line(0.3, -0.015, 0.3, 0.24)
end

function DRAW.check(G)
  G.setLineWidth(0.115)
  G.line(-0.26, 0.02, -0.07, 0.21, 0.27, -0.2)
  G.circle("fill", -0.26, 0.02, 0.0575)
  G.circle("fill", 0.27, -0.2, 0.0575)
end

function DRAW.eye(G, a, r, g, b)
  local half = 0.4606
  G.arc("line", "open", 0, 0.16, 0.36, pi + half, 2 * pi - half)
  G.arc("line", "open", 0, -0.16, 0.36, half, pi - half)
  G.circle("fill", 0, 0, 0.125)
  G.setColor(r, g, b, a)
  G.circle("fill", 0, 0, 0.052)
end

function DRAW.glove(G, a, r, g, b)
  fan(G, GLOVE, 0.05, -0.1)
  fan(G, THUMB, -0.2, -0.02)
  G.setColor(r, g, b, a)
  G.setLineWidth(0.04)
  G.line(-0.135, -0.11, -0.115, 0.1)
  G.setColor(1, 1, 1, a)
  G.rectangle("fill", -0.15, 0.19, 0.32, 0.11, 0.025, 0.025)
end

function DRAW.hook(G)
  G.setLineWidth(0.07)
  G.circle("line", 0.08, -0.29, 0.042)
  G.line(0.08, -0.25, 0.08, 0.11)
  G.arc("line", "open", -0.07, 0.11, 0.15, 0, pi)
  G.line(-0.22, 0.11, -0.22, -0.03)
  G.polygon("fill", -0.255, 0.0, -0.22, -0.14, -0.125, -0.0)
end

function DRAW.reel(G, a, r, g, b)
  G.rectangle("fill", 0, 0.235, 0.35, 0.065)
  G.circle("fill", 0, 0, 0.3)
  G.setColor(r, g, b, a)
  for i = 0, 4 do
    local an = -pi / 2 + i * 2 * pi / 5
    G.circle("fill", cos(an) * 0.175, sin(an) * 0.175, 0.066)
  end
  G.circle("fill", 0, 0, 0.038)
end

function DRAW.flame(G, a, r, g, b)
  fan(G, FLAME, 0, 0.12)
  G.setColor(r, g, b, a)
  fan(G, FLAME_CORE, 0, 0.16)
end

function DRAW.flower(G, a, r, g, b)
  for i = 0, 4 do
    local an = -pi / 2 + i * 2 * pi / 5
    G.circle("fill", cos(an) * 0.19, sin(an) * 0.19, 0.125)
  end
  G.setColor(r, g, b, a)
  G.circle("fill", 0, 0, 0.115)
  G.setColor(1, 1, 1, a)
  G.circle("fill", 0, 0, 0.07)
end

function DRAW.weight(G)
  G.rectangle("fill", -0.2, -0.04, 0.4, 0.08)
  G.rectangle("fill", -0.255, -0.18, 0.09, 0.36, 0.025, 0.025)
  G.rectangle("fill", 0.165, -0.18, 0.09, 0.36, 0.025, 0.025)
  G.rectangle("fill", -0.34, -0.12, 0.07, 0.24, 0.025, 0.025)
  G.rectangle("fill", 0.27, -0.12, 0.07, 0.24, 0.025, 0.025)
end

function DRAW.medal(G, a, r, g, b)
  G.polygon("fill", -0.24, -0.33, -0.08, -0.33, 0.05, -0.05, -0.1, 0.0)
  G.polygon("fill", 0.24, -0.33, 0.08, -0.33, -0.05, -0.05, 0.1, 0.0)
  G.setColor(r, g, b, a)
  G.circle("fill", 0, 0.1, 0.235)
  G.setColor(1, 1, 1, a)
  G.circle("fill", 0, 0.1, 0.2)
  G.setColor(r, g, b, a)
  G.setLineWidth(0.035)
  G.circle("line", 0, 0.1, 0.13)
end

function DRAW.chart(G)
  G.rectangle("fill", -0.27, 0.0, 0.13, 0.25, 0.02, 0.02)
  G.rectangle("fill", -0.065, -0.14, 0.13, 0.39, 0.02, 0.02)
  G.rectangle("fill", 0.14, -0.3, 0.13, 0.55, 0.02, 0.02)
  G.rectangle("fill", -0.33, 0.27, 0.66, 0.055, 0.02, 0.02)
end

function DRAW.pokeball(G, a, r, g, b)
  G.arc("fill", 0, 0, 0.31, pi, 2 * pi)
  G.setColor(1, 1, 1, 0.58 * a)
  G.arc("fill", 0, 0, 0.31, 0, pi)
  G.setColor(r, g, b, a)
  G.rectangle("fill", -0.32, -0.03, 0.64, 0.06)
  G.circle("fill", 0, 0, 0.125)
  G.setColor(1, 1, 1, a)
  G.circle("fill", 0, 0, 0.075)
end

function DRAW.fish(G, a, r, g, b)
  G.polygon("fill", -0.12, 0, -0.35, -0.17, -0.3, 0, -0.35, 0.17)
  G.polygon("fill", -0.02, -0.12, 0.12, -0.25, 0.14, -0.1)
  G.ellipse("fill", 0.07, 0, 0.26, 0.16)
  G.setColor(r, g, b, a)
  G.circle("fill", 0.21, -0.045, 0.032)
end

function DRAW.mic(G)
  G.rectangle("fill", -0.105, -0.34, 0.21, 0.4, 0.1, 0.1)
  G.setLineWidth(0.07)
  G.arc("line", "open", 0, -0.04, 0.19, 0, pi)
  G.line(0, 0.15, 0, 0.3)
  G.line(-0.13, 0.3, 0.13, 0.3)
end

function DRAW.building(G, a, r, g, b)
  G.rectangle("fill", -0.22, -0.33, 0.44, 0.65, 0.025, 0.025)
  G.setColor(r, g, b, a)
  for row = 0, 3 do
    for col = 0, 2 do
      if not (row == 3 and col == 1) then
        G.rectangle("fill", -0.165 + col * 0.125, -0.27 + row * 0.13, 0.08, 0.075)
      end
    end
  end
  G.rectangle("fill", -0.05, 0.14, 0.1, 0.18)
end

function DRAW.bag(G)
  G.rectangle("line", -0.28, -0.133, 0.56, 0.38, 0.08, 0.08)
  G.arc("line", "open", 0, -0.133, 0.13, pi, 2 * pi)
  G.rectangle("fill", -0.06, -0.0456, 0.12, 0.1)
end

function DRAW.shoes(G, a, r, g, b)
  fan(G, SHOE, -0.1, 0.06)
  G.rectangle("fill", -0.34, 0.16, 0.69, 0.1, 0.04, 0.04)
  G.setColor(r, g, b, a)
  G.setLineWidth(0.03)
  G.line(-0.34, 0.145, 0.35, 0.145)
  G.line(-0.05, -0.08, 0.02, -0.01)
  G.line(0.04, -0.1, 0.1, -0.01)
end

function DRAW.cloud(G)
  G.circle("fill", -0.17, 0.08, 0.14)
  G.circle("fill", 0.17, 0.08, 0.14)
  G.circle("fill", 0.0, -0.05, 0.2)
  G.rectangle("fill", -0.17, 0.06, 0.34, 0.16)
end

function DRAW.at(G)
  G.setLineWidth(0.07)
  G.circle("line", -0.01, 0, 0.115)
  G.line(0.105, -0.12, 0.105, 0.075)
  G.arc("line", "open", 0.195, 0.075, 0.09, pi, 0)
  G.arc("line", "open", 0, 0, 0.3, 0.26, 0.8 - 2 * pi)
end

function DRAW.bell(G)
  fan(G, BELL, 0, 0.02)
  G.rectangle("fill", -0.29, 0.14, 0.58, 0.07, 0.03, 0.03)
  G.circle("fill", 0, -0.29, 0.05)
  G.arc("fill", 0, 0.235, 0.075, 0, pi)
end

function DRAW.speech(G, a, r, g, b)
  G.rectangle("fill", -0.32, -0.27, 0.64, 0.43, 0.11, 0.11)
  G.polygon("fill", -0.2, 0.12, -0.02, 0.12, -0.22, 0.33)
  G.setColor(r, g, b, a)
  for i = -1, 1 do G.circle("fill", i * 0.15, -0.055, 0.042) end
end

function DRAW.internet(G)
  G.setLineWidth(0.06)
  G.circle("line", 0, 0, 0.31)
  G.ellipse("line", 0, 0, 0.14, 0.31)
  G.line(-0.31, 0, 0.31, 0)
  G.line(-0.268, -0.155, 0.268, -0.155)
  G.line(-0.268, 0.155, 0.268, 0.155)
end

function DRAW.send(G, a, r, g, b)
  G.rotate(-0.42)
  G.polygon("fill", -0.33, -0.25, 0.35, 0, -0.2, 0)
  G.polygon("fill", -0.33, 0.25, 0.35, 0, -0.2, 0)
  G.setColor(r, g, b, a)
  G.setLineWidth(0.03)
  G.line(-0.2, 0, 0.12, 0)
end

function DRAW.network(G)
  G.setLineWidth(0.06)
  G.line(0, -0.2, 0, 0.0)
  G.line(-0.24, 0.2, -0.24, 0.0, 0.24, 0.0, 0.24, 0.2)
  G.circle("fill", 0, -0.22, 0.1)
  G.circle("fill", -0.24, 0.22, 0.1)
  G.circle("fill", 0.24, 0.22, 0.1)
end

function DRAW.wifi(G)
  G.setLineWidth(0.085)
  local a0, a1 = -3 * pi / 4, -pi / 4
  G.arc("line", "open", 0, 0.24, 0.18, a0, a1)
  G.arc("line", "open", 0, 0.24, 0.33, a0, a1)
  G.arc("line", "open", 0, 0.24, 0.48, a0, a1)
  G.circle("fill", 0, 0.24, 0.06)
end

function DRAW.database(G)
  G.setLineWidth(0.06)
  G.ellipse("line", 0, -0.22, 0.25, 0.09)
  G.line(-0.25, -0.22, -0.25, 0.22)
  G.line(0.25, -0.22, 0.25, 0.22)
  for i = 0, 2 do
    G.push()
    G.translate(0, -0.075 + i * 0.145)
    G.line(RING)
    G.pop()
  end
end

function DRAW.pencil(G)
  G.rotate(pi / 4)
  G.rectangle("fill", -0.08, -0.24, 0.16, 0.39)
  G.polygon("fill", -0.08, 0.185, 0.08, 0.185, 0, 0.355)
  G.rectangle("fill", -0.08, -0.35, 0.16, 0.08, 0.025, 0.025)
end

function DRAW.pokedollar(G)
  G.setLineWidth(0.085)
  local x0, top, bow = -0.11, -0.28, 0.02
  G.line(x0, top, x0, 0.3)
  G.line(x0 - 0.04, top, 0.05, top)
  G.line(x0 - 0.04, bow, 0.05, bow)
  G.arc("line", "open", 0.05, (top + bow) / 2, (bow - top) / 2, -pi / 2, pi / 2)
  G.setLineWidth(0.058)
  G.line(-0.24, 0.1, 0.13, 0.1)
  G.line(-0.24, 0.205, 0.13, 0.205)
end

local Ic = {
  NAMES = { "controller", "screen", "headphones", "speaker", "cube", "letters", "check", "eye", "glove", "hook",
    "reel", "flame", "flower", "weight", "medal", "chart", "pokeball", "fish", "mic", "building", "bag", "shoes",
    "cloud", "at", "bell", "speech", "internet", "send", "network", "wifi", "database", "pencil", "pokedollar" },
}

function Ic.has(name) return DRAW[name] ~= nil end

function Ic.draw(G, name, cx, cy, s, a, tile)
  local f = DRAW[name]
  if not f then return false end
  local r, g, b = 0.3, 0.32, 0.38
  if tile then r, g, b = tile[1] / 255, tile[2] / 255, tile[3] / 255 end
  G.push()
  G.translate(cx, cy)
  G.scale(s, s)
  G.setColor(1, 1, 1, a)
  G.setLineWidth(max(1 / s, LINE))
  f(G, a, r, g, b)
  G.pop()
  G.setColor(1, 1, 1, a)
  return true
end

return Ic
