-- The GPS's arrow over the field (Settings > Map > Overworld GPS): a small glass chevron going round the
-- player, pointing at the next warp or edge on the way to the waypoint (src/gps/route.lua's target);
-- that warp in sight (a door, a ladder, a hole), a small mark bobbing over it too. It fades in and out
-- as the player is free to move or not. Placed on the field as the engine drew it (its camera, and where
-- and how big its world canvas went on the window: the zoom can differ from the HUD's); no tables made.
--
--   Ar = arrow(deps)   deps: K ; route (Rt) ; on() -> the setting ; player(vp) -> px, py (the player's pixels
--                      on its map), mapId, camX, camY (the field's camera), ox, oy, sx, sy (the world canvas
--                      on the window: its origin and scale; nil: the game's own rectangle, the HUD's scale)
--   Ar.draw(G, vp, free, clock)

local max, min, abs, sqrt, atan2, cos, sin, pi = math.max, math.min, math.abs, math.sqrt, math.atan2 or math.atan,
  math.cos, math.sin, math.pi

local ORBIT = 21          -- pixels from the player's middle
local SIZE = 6.5          -- the chevron's length
local ACCENT, CORE, INK = { 10, 132, 255 }, { 120, 200, 255 }, { 255, 255, 255 }
local SHADOW, GLASS = { 0, 0, 0 }, { 16, 18, 26 }

return function(deps)
  local K = deps.K
  local Ar = { a = 0, angle = nil, last = nil, tx = 0, ty = 0, mark = false }

  local function approach(v, goal, k) return v + (goal - v) * min(1, k) end

  function Ar.draw(G, vp, free, clock)
    local dt = Ar.last and max(0, min(0.1, clock - Ar.last)) or 0
    Ar.last = clock
    local t = deps.route and deps.route.target
    local on = deps.on and deps.on()
    local px, py, map, camX, camY, ox, oy, wsx, wsy
    if on and t and t.on then px, py, map, camX, camY, ox, oy, wsx, wsy = deps.player(vp) end
    local want = free and on and t and t.on and px ~= nil and map == t.map
    Ar.a = approach(Ar.a, want and 1 or 0, dt * (want and 5 or 7))
    if Ar.a < 0.02 or (not want and Ar.angle == nil) then return end
    -- (window pixels throughout: the field's own scale for where things are, a size of the arrow's own
    -- that stays readable however far the field is zoomed out)
    K.place(G, 0, 0, 1, clock)
    local ui = tonumber(vp.scale) or ((tonumber(vp.gameWidth) or 240) / 240)
    local s = wsx or ui
    local cx, cy
    if want then
      if ox and camX then
        cx, cy = ox + (px + 8 - camX) * s, oy + (py + 8 - camY) * (wsy or s)
      else
        cx = (tonumber(vp.gameX) or 0) + (tonumber(vp.gameWidth) or 240 * ui) / 2
        cy = (tonumber(vp.gameY) or 0) + (tonumber(vp.gameHeight) or 160 * ui) / 2
      end
      Ar.cx, Ar.cy, Ar.s = cx, cy, s
    end
    cx, cy, s = Ar.cx, Ar.cy, Ar.s
    if not cx then return end
    local u = max(s, ui * 0.55)
    cy = cy - 3 * s
    if want then
      local dx, dy = t.x * 16 - px, t.y * 16 - py
      -- (over an edge: on past it, the way it leads)
      if t.dx ~= 0 or t.dy ~= 0 then dx, dy = dx + t.dx * 28, dy + t.dy * 28 end
      if dx == 0 and dy == 0 then dx, dy = t.dx, t.dy end
      if dx ~= 0 or dy ~= 0 then
        local goal = atan2(dy, dx)
        if Ar.angle == nil then
          Ar.angle = goal
        else
          local d = (goal - Ar.angle + pi) % (2 * pi) - pi
          Ar.angle = Ar.angle + d * min(1, dt * 9)
        end
      end
      Ar.tx, Ar.ty = cx + dx * s, cy + (3 + dy) * s
      local W, H = tonumber(vp.width) or 0, tonumber(vp.height) or 0
      Ar.mark = not t.dest and t.dx == 0 and t.dy == 0 and sqrt(dx * dx + dy * dy) > 12
        and Ar.tx > 8 and Ar.tx < W - 8 and Ar.ty > 16 and Ar.ty < H - 4
    end
    if Ar.angle == nil then return end
    local a = Ar.a * 0.85
    local ux, uy = cos(Ar.angle), sin(Ar.angle)
    local bob = sin(clock * 3.2) * 1.2
    local orbit = max(ORBIT * u, 26 * s)
    local hx, hy = cx + ux * (orbit + bob * u), cy + uy * (orbit + bob * u) * 0.8
    -- (the chevron: a glass disc, the point in the accent, a fine rim)
    local X, Y, sc = K.X, K.Y, u
    local z = SIZE * u
    local px1, py1 = hx + ux * z * 0.62, hy + uy * z * 0.62
    local bx, by = hx - ux * z * 0.38, hy - uy * z * 0.38
    local wx, wy = -uy * z * 0.5, ux * z * 0.5
    K.col(SHADOW, 0.28 * a)
    G.circle("fill", X(hx), Y(hy + 0.8 * sc), 5.6 * sc)
    K.col(GLASS, 0.55 * a)
    G.circle("fill", X(hx), Y(hy), 5.4 * sc)
    K.col(INK, 0.5 * a)
    G.setLineWidth(max(1, 0.45 * sc))
    G.circle("line", X(hx), Y(hy), 5.4 * sc)
    K.col(ACCENT, a)
    local nx, ny = hx - ux * 0.6 * sc, hy - uy * 0.6 * sc
    G.polygon("fill", X(px1), Y(py1), X(bx + wx), Y(by + wy), X(nx), Y(ny))
    K.col(CORE, a)
    G.polygon("fill", X(px1), Y(py1), X(nx), Y(ny), X(bx - wx), Y(by - wy))
    K.col(INK, 0.9 * a)
    G.setLineWidth(max(1, 0.35 * sc))
    G.polygon("line", X(px1), Y(py1), X(bx + wx), Y(by + wy), X(nx), Y(ny), X(bx - wx), Y(by - wy))
    -- (the warp itself in sight: a small mark bobbing over its tile)
    if Ar.mark and want then
      local mx, my = Ar.tx, Ar.ty - 13 * s - abs(sin(clock * 3)) * 2.2 * u
      local m = 3.2 * u
      local d = 0.6 * u
      K.col(SHADOW, 0.3 * a)
      G.polygon("fill", X(mx - m), Y(my - m * 1.3 + d), X(mx + m), Y(my - m * 1.3 + d), X(mx), Y(my + d))
      K.col(ACCENT, a)
      G.polygon("fill", X(mx - m), Y(my - m * 1.3), X(mx + m), Y(my - m * 1.3), X(mx), Y(my))
      K.col(INK, 0.9 * a)
      G.polygon("line", X(mx - m), Y(my - m * 1.3), X(mx + m), Y(my - m * 1.3), X(mx), Y(my))
    end
  end

  return Ar
end
