-- The Pokémon Center's look (src/apps/pokecenter.lua's window, the latest games' counter in WoobOS's
-- glass), lit: the scene is drawn through src/lighting.lua (env.lighting: a key light, a vignette, a warm
-- grade and bloom in one shader), the words and the choice over it, sharp.
--   the counter, after Emerald's own Pokémon Center: an orange wall of upright slats under a cream trim, the
--     big rounded window behind her (glints across its glass); the counter an open rectangle round her, its
--     back against the wall with the healing machine on it (the close-up's own, small) on her right, her PC
--     on its desk inside beside her on her left, turned to her; beyond its ends the floor's tiles, the
--     magazine rack and the players' PC, cut by the screen's edges; the nurse at whole pixels in a soft
--     light; the front's cream top with the white pad in front of her, its tan edge, its white front in
--     shadow with grey panels, a big Poké Ball on each front corner turned to face it; the words' box along
--     the foot (a bobbing arrow when there's more), the choice in navy glass beside her, above her PC
--   the machine, three-quarters from above: on the counter, its shadow under it; the base (its top and
--     its front), the hood (its thickness, its cavity, the cyan lines lit), the tray in perspective with a
--     socket and a shaded ball for each Pokémon, sliding into the cavity; the team's screen on the front,
--     each Pokémon's icon and health; the round button; the glow flooding the cavity and spilling out
-- Numbers only on each frame (src/ui_kit.lua's rules); without meshes, canvases or shaders it's drawn plainer.
--
--   V = view(K, env, st, T)   st: the window's state ; V.draw(body, clock, portrait) ; V.release() ;
--   V.ROW_AT, V.BOX, V.SCREEN (hit args)

local floor, max, min, sin, cos, pi, abs = math.floor, math.max, math.min, math.sin, math.cos, math.pi, math.abs

local SIZE, LINE = 5.2, 6.6
local UTF8 = "[%z\1-\127\194-\244][\128-\191]*"
-- (the sheet's rows)
local FACE = { down = 0, left = 1, right = 2, up = 3 }

-- the colours, and the lighting's looks (one table: the factory would have too many upvalues)
local C = {
  -- the room (after Emerald's: an orange wall of slats, the rounded window, her PC)
  WALL_O = { 252, 190, 124 }, WALL_O_D = { 240, 164, 100 }, SLAT_HI = { 255, 222, 172 },
  SEAM = { 204, 102, 38 }, SEAM_SOFT = { 214, 120, 56 }, TRIM = { 255, 238, 204 }, TRIM_D = { 212, 110, 42 },
  SKIRT = { 228, 132, 62 },
  WIN_EDGE = { 74, 74, 96 }, WIN_FRAME = { 242, 242, 246 }, WIN_FRAME_D = { 172, 174, 190 },
  GLASS_TOP = { 190, 200, 230 }, GLASS_FOOT = { 132, 142, 186 },
  PC_BODY = { 252, 252, 254 }, PC_BODY_D = { 210, 212, 222 }, PC_EDGE = { 84, 84, 104 },
  PC_GREY = { 176, 178, 192 }, PC_GREY_D = { 128, 130, 148 }, LED_ON = { 120, 230, 120 },
  SCREEN_LIGHT = { 236, 246, 255 }, SCREEN_EDGE = { 70, 96, 124 },
  GREEN_SCREEN = { 156, 170, 96 }, GREEN_SCREEN_D = { 110, 126, 62 }, RACK_BACK = { 196, 196, 212 },
  MAG_A = { 232, 84, 84 }, MAG_B = { 84, 150, 232 }, MAG_C = { 250, 204, 72 }, MAG_D = { 104, 196, 120 },
  MAG_E = { 196, 120, 220 },
  BACK_FACE = { 196, 192, 222 }, BACK_FACE_D = { 150, 146, 184 },
  FLOOR = { 252, 244, 204 }, FLOOR_FAR = { 230, 216, 164 }, FLOOR_TILE = { 222, 206, 146 },
  AO_DARK = { 40, 30, 40, 0.34 }, AO_CLEAR = { 40, 30, 40, 0 },
  LAMP = { 255, 232, 200 },
  BALL_RED = { 226, 52, 64 }, BALL_INK = { 40, 40, 48 },
  GREAT = { 66, 116, 220 },
  -- the counter (cream top, the pad, a tan edge, white in shadow with grey panels), its lamps
  TOP_CREAM = { 255, 252, 214 }, TOP_CREAM_D = { 242, 232, 178 }, PAD_EDGE = { 160, 158, 150 },
  EDGE_TAN = { 230, 164, 104 }, EDGE_TAN_D = { 186, 116, 68 },
  FRONT_TOP = { 230, 228, 242 }, FRONT_FOOT = { 168, 164, 198 }, FRONT_LINE = { 112, 108, 144 }, KICK = { 92, 88, 120 },
  WHITE = { 255, 255, 255 }, BLACK = { 0, 0, 0 },
  -- the words and the choice
  INK = { 40, 42, 52 }, PINK = { 240, 104, 146 }, PINK_D = { 204, 60, 104 },
  NAVY = { 30, 46, 104 }, NAVY_D = { 16, 26, 66 }, LIME = { 186, 244, 64 },
  SHEEN = { 255, 255, 255, 0.22 }, SHEEN_CLEAR = { 255, 255, 255, 0 },
  -- the machine
  WALL_DIM_TOP = { 24, 10, 16, 0.5 }, WALL_DIM_FOOT = { 24, 10, 16, 0.26 },
  TABLE_FAR = { 150, 138, 100 }, TABLE_NEAR = { 238, 228, 178 },
  BASE_TOP = { 232, 218, 224 }, BASE_TOP_D = { 196, 178, 188 }, BASE_FRONT = { 218, 206, 214 },
  BASE_FRONT_D = { 176, 160, 172 },
  HOOD_TOP = { 246, 104, 128 }, DOME = { 218, 42, 72 }, DOME_D = { 150, 20, 44 }, DOME_L = { 252, 118, 140 },
  CAVITY = { 8, 20, 34 }, SCREEN = { 22, 70, 106 }, SCREEN_D = { 10, 36, 60 }, CYAN = { 110, 236, 255 },
  TRAY = { 84, 180, 222 }, TRAY_D = { 34, 104, 148 }, TRAY_HI = { 200, 244, 255 }, SOCKET = { 16, 58, 88 },
  PANEL = { 14, 24, 44 }, PANEL_D = { 6, 10, 22 },
  HP = { 92, 222, 120 }, HP_LOW = { 240, 184, 60 }, HP_BACK = { 40, 56, 80 },
  -- (the lighting: the counter warm and soft, the machine's neon blooming)
  LOOK_ROOM = { key = 0.1, vignette = 0.4, bloom = 0.22, warm = 0.3, contrast = 0.25, threshold = 0.9 },
  LOOK_MACHINE = { key = 0.1, vignette = 0.55, bloom = 0.85, warm = 0.15, contrast = 0.2, threshold = 0.72 },
}

return function(K, env, st, T)
  local V = { ROW_AT = 100, BOX = 201, SCREEN = 202 }
  local tm = st.timing
  local Lt = env.lighting

  -- ------- two meshes made once: a soft shadow (dark in the middle) and a sphere's shading (dark away
  -- from the light, up and to the left); nothing without meshes
  local blobMesh, shadeMesh
  local function meshes()
    local G = K.graphics()
    if blobMesh == nil then
      local v = { { 0, 0, 0, 0, 0, 0, 0, 1 } }
      for i = 0, 28 do
        local t = i / 28 * 2 * pi
        v[#v + 1] = { cos(t), sin(t), 0, 0, 0, 0, 0, 0 }
      end
      local ok, m = pcall(G.newMesh, v, "fan", "static")
      blobMesh = ok and m or false
    end
    if shadeMesh == nil then
      local v = { { -0.4, -0.45, 0, 0, 0, 0, 0, 0 } }
      for i = 0, 32 do
        local t = i / 32 * 2 * pi
        v[#v + 1] = { cos(t), sin(t), 0, 0, 0, 0, 0, 1 }
      end
      local ok, m = pcall(G.newMesh, v, "fan", "static")
      shadeMesh = ok and m or false
    end
  end
  -- a soft shadow, rx x ry units round cx, cy
  local function shadow(cx, cy, rx, ry, a)
    if not blobMesh then return end
    local G = K.graphics()
    G.setColor(1, 1, 1, (a or 0.4) * K.getFade())
    G.draw(blobMesh, K.X(cx), K.Y(cy), 0, rx * K.sc, ry * K.sc)
  end
  -- a sphere's shading over a round thing of radius r: dark away from the light, a glint near it
  local function shade(cx, cy, r, a)
    local G = K.graphics()
    if shadeMesh then
      G.setColor(1, 1, 1, (a or 0.5) * K.getFade())
      G.draw(shadeMesh, K.X(cx), K.Y(cy), 0, r * K.sc, r * K.sc)
    end
    K.col(C.WHITE, 0.75 * (a and min(1, a * 1.6) or 1))
    G.ellipse("fill", K.X(cx - r * 0.38), K.Y(cy - r * 0.5), r * 0.22 * K.sc, r * 0.13 * K.sc, 12)
  end

  -- ------- shapes (units; the window's own graphics)
  -- (a four-cornered shape, convex, its corners in turn)
  local function quad(x1, y1, x2, y2, x3, y3, x4, y4)
    K.graphics().polygon("fill", K.X(x1), K.Y(y1), K.X(x2), K.Y(y2), K.X(x3), K.Y(y3), K.X(x4), K.Y(y4))
  end
  -- a Poké Ball, shaded as a sphere; `dim` darkens it (inside the machine)
  local function ball(cx, cy, r, a, dim, top)
    local G = K.graphics()
    local X, Y, s = K.X(cx), K.Y(cy), r * K.sc
    K.col(top or C.BALL_RED, a)
    G.arc("fill", "pie", X, Y, s, pi, 2 * pi, 24)
    if top == C.GREAT then
      -- (the Great Ball's red bands)
      K.col(C.BALL_RED, a)
      G.arc("fill", "pie", X - s * 0.3, Y - s * 0.02, s * 0.62, pi * 1.15, pi * 1.42, 10)
      G.arc("fill", "pie", X + s * 0.3, Y - s * 0.02, s * 0.62, pi * 1.58, pi * 1.85, 10)
    end
    K.col(C.WHITE, a)
    G.arc("fill", "pie", X, Y, s, 0, pi, 24)
    K.col(C.BALL_INK, a)
    G.rectangle("fill", X - s, Y - s * 0.08, s * 2, s * 0.16)
    G.circle("fill", X, Y, s * 0.32, 16)
    K.col(C.WHITE, a)
    G.circle("fill", X, Y, s * 0.19, 12)
    shade(cx, cy, r, (a or 1) * (0.45 + (dim or 0) * 0.4))
    G.setLineWidth(max(1, r * 0.08 * K.sc))
    K.col(C.BALL_INK, 0.7 * (a or 1))
    G.circle("line", X, Y, s, 24)
  end
  -- a Poké Ball turned 45 degrees about its upright, seen from the front: the band level, its button off
  -- toward `side` (-1 left, 1 right) and narrowed, as it faces away to that side
  local function turnedBall(cx, cy, r, side)
    local G = K.graphics()
    local X, Y, s = K.X(cx), K.Y(cy), r * K.sc
    K.col(C.BALL_RED)
    G.arc("fill", "pie", X, Y, s, pi, 2 * pi, 28)
    K.col(C.WHITE)
    G.arc("fill", "pie", X, Y, s, 0, pi, 28)
    K.col(C.BALL_INK)
    G.rectangle("fill", X - s, Y - s * 0.085, s * 2, s * 0.17)
    local bx = X + side * s * 0.66
    G.ellipse("fill", bx, Y, s * 0.25, s * 0.34, 20)
    K.col(C.WHITE)
    G.ellipse("fill", bx + side * s * 0.015, Y, s * 0.15, s * 0.21, 16)
    shade(cx, cy, r, 0.45)
    G.setLineWidth(max(1, r * 0.07 * K.sc))
    K.col(C.BALL_INK, 0.75)
    G.circle("line", X, Y, s, 28)
  end

  -- the orange wall of upright slats (`slat` wide, set from cx): each board lit on its left, a shade and a
  -- dark seam on its right, the light falling off down it; the cream trim along its top
  local function slatWall(x, y, w, h, cx, slat)
    K.grad(K.R(x, y, w, h), 0, C.WALL_O, C.WALL_O_D)
    local sx = cx - slat * 0.5 - slat * math.ceil((cx - slat * 0.5 - x) / slat)
    while sx < x + w do
      K.col(C.SLAT_HI, 0.55)
      K.box("fill", K.R(sx + 0.9, y, 1.2, h))
      K.col(C.SEAM_SOFT, 0.35)
      K.box("fill", K.R(sx + slat - 3.2, y, 2.6, h))
      K.col(C.SEAM)
      K.box("fill", K.R(sx + slat - 0.6, y, 0.9, h))
      sx = sx + slat
    end
    K.col(C.TRIM)
    K.box("fill", K.R(x, y, w, 4))
    K.col(C.TRIM_D)
    K.box("fill", K.R(x, y + 4, w, 1.8))
    K.grad(K.R(x, y + 5.8, w, 5), 0, C.AO_DARK, C.AO_CLEAR)
  end
  -- the skirting along the wall's foot (at `foot`)
  local function skirting(x, foot, w)
    K.col(C.SKIRT)
    K.box("fill", K.R(x, foot - 6, w, 6))
    K.col(C.TRIM)
    K.box("fill", K.R(x, foot - 7.2, w, 1.4))
    K.col(C.SEAM, 0.6)
    K.box("fill", K.R(x, foot - 0.6, w, 0.6))
  end

  -- ------- the room, after Emerald's own Pokémon Center: an orange wall of upright slats under a cream
  -- trim, the big rounded window behind her, the counter an open rectangle round her

  -- the rounded window: a grey frame (lit along its top, a dark edge), blue-grey glass, white glints
  -- slanting across it and a bright strip down its left, as the game's
  local function glint(gx, gy, gw, gh, rr, slant, at, bw, a)
    local x0 = gx + rr + slant + gw * at
    if x0 + bw > gx + gw - rr then return end
    K.col(C.WHITE, a)
    K.graphics().polygon("fill", K.X(x0), K.Y(gy), K.X(x0 + bw), K.Y(gy), K.X(x0 + bw - slant), K.Y(gy + gh),
      K.X(x0 - slant), K.Y(gy + gh))
  end
  local function drawWindow(x, y, w, h)
    if w <= 12 or h <= 12 then return end
    local r = min(10, h * 0.2)
    shadow(x + w / 2, y + h * 0.55, w * 0.56, h * 0.58, 0.2)
    K.col(C.WIN_EDGE)
    K.box("fill", K.R(x - 1, y - 1, w + 2, h + 2), r + 1)
    K.grad(K.R(x, y, w, h), r, C.WIN_FRAME, C.WIN_FRAME_D)
    local f = min(4.2, w * 0.05)
    local gx, gy, gw, gh = x + f, y + f, w - f * 2, h - f * 2
    local rr = max(1, r - f)
    K.col(C.WIN_EDGE)
    K.box("fill", K.R(gx - 0.7, gy - 0.7, gw + 1.4, gh + 1.4), rr + 0.7)
    K.grad(K.R(gx, gy, gw, gh), rr, C.GLASS_TOP, C.GLASS_FOOT)
    -- (the sky's light low in it, the frame's shadow along its top)
    K.glow(gx + gw * 0.55, gy + gh * 0.95, gw * 0.5, gh * 0.4, C.WHITE, 0.16)
    K.grad(K.R(gx, gy, gw, min(4, gh * 0.12)), rr, C.AO_DARK, C.AO_CLEAR)
    -- (glints: bands slanting across, clear of the rounded corners; the bright strip down the left)
    local slant = gh * 0.32
    glint(gx, gy, gw, gh, rr, slant, 0.08, gw * 0.07, 0.3)
    glint(gx, gy, gw, gh, rr, slant, 0.2, gw * 0.025, 0.24)
    glint(gx, gy, gw, gh, rr, slant, 0.56, gw * 0.04, 0.14)
    K.col(C.WHITE, 0.85)
    K.box("fill", K.R(gx + 1.6, gy + rr * 0.6 + 1, 1.6, gh - rr * 1.2 - 2), 0.8)
    -- (the frame's lit top)
    K.col(C.WHITE, 0.9)
    K.box("fill", K.R(x + r, y + 0.5, w - r * 2, 0.7))
  end

  -- her PC turned to her: the monitor's side (its front edge toward her, the case narrowing behind it,
  -- vents), on its stand, the screen's light falling on her side of it; `x` its front edge
  local function drawPC(x, foot, w, h)
    local G = K.graphics()
    shadow(x + w * 0.5, foot, w * 0.7, 1.6, 0.4)
    K.grad(K.R(x + w * 0.22, foot - h * 0.2, w * 0.3, h * 0.2), 0.6, C.PC_GREY, C.PC_GREY_D)
    K.col(C.PC_EDGE)
    K.box("fill", K.R(x + w * 0.02, foot - 1.4, w * 0.62, 1.4), 0.6)
    local top, mh = foot - h, h * 0.8
    local fw = w * 0.42
    -- (the case's back, narrowing)
    K.col(C.PC_EDGE)
    quad(x + fw - 1, top + mh * 0.06, x + w, top + mh * 0.2, x + w, top + mh * 0.8, x + fw - 1, top + mh * 0.94)
    K.col(C.PC_BODY_D)
    quad(x + fw - 1, top + mh * 0.06 + 0.8, x + w - 0.8, top + mh * 0.2 + 0.7, x + w - 0.8, top + mh * 0.8 - 0.7,
      x + fw - 1, top + mh * 0.94 - 0.8)
    K.col(C.WHITE, 0.5)
    quad(x + fw - 1, top + mh * 0.06 + 0.8, x + w - 0.8, top + mh * 0.2 + 0.7, x + w - 0.8, top + mh * 0.2 + 1.6,
      x + fw - 1, top + mh * 0.06 + 1.8)
    G.setLineWidth(max(1, 0.45 * K.sc))
    K.col(C.PC_EDGE, 0.55)
    for i = 1, 4 do
      local vy = top + mh * (0.3 + i * 0.1)
      G.line(K.X(x + fw + 1.5), K.Y(vy), K.X(x + w - 2.5), K.Y(vy))
    end
    -- (its front: the bezel's side, full height)
    K.col(C.PC_EDGE)
    K.box("fill", K.R(x - 0.7, top - 0.7, fw + 1.4, mh + 1.4), 1.6)
    K.grad(K.R(x, top, fw, mh), 1.2, C.PC_BODY, C.PC_BODY_D)
    K.col(C.WHITE, 0.8)
    K.box("fill", K.R(x + fw * 0.35, top + 0.6, 0.7, mh - 1.2))
    -- (the screen's edge toward her, its light)
    K.glow(x - 1.5, top + mh * 0.45, w * 0.6, mh * 0.5, C.SCREEN_LIGHT, 0.4)
    K.col(C.SCREEN_EDGE)
    K.box("fill", K.R(x - 0.3, top + mh * 0.1, 1.3, mh * 0.78), 0.5)
  end

  -- the healing machine as its close-up has it, small, on the back of the counter against the wall (R its
  -- size, fb its front's foot): the base's top and front (the team's dark screen, the red button with its
  -- cyan ring), the red hood round the dark cavity, its cyan lines, the empty tray with its six sockets
  local function drawHealer(cx, fb, R, clock)
    local G = K.graphics()
    local S, X0 = K.sc, K.X(cx)
    local ft, depth = fb - R * 0.3, R * 0.34
    local bw, inset = R * 1.16, R * 0.12
    shadow(cx + R * 0.1, ft - depth - R * 0.42, R * 1.12, R * 0.78, 0.3)
    shadow(cx, fb + 0.3, bw * 1.15, R * 0.14, 0.5)
    K.col(C.BASE_TOP_D)
    quad(cx - bw + inset, ft - depth, cx + bw - inset, ft - depth, cx + bw, ft, cx - bw, ft)
    K.col(C.BASE_TOP, 0.85)
    quad(cx - bw + inset * 1.1, ft - depth + 0.4, cx + bw - inset * 1.1, ft - depth + 0.4, cx + bw - 0.4, ft - 0.4,
      cx - bw + 0.4, ft - 0.4)
    -- (the hood's top, the cavity, the arch on its back wall)
    local hoodY, d = ft - depth * 0.55, R * 0.13
    K.col(C.HOOD_TOP)
    G.arc("fill", "pie", X0, K.Y(hoodY - d), R * 0.97 * S, pi, 2 * pi, 40)
    K.col(C.CAVITY)
    G.arc("fill", "pie", X0, K.Y(hoodY), R * 0.78 * S, pi, 2 * pi, 36)
    K.col(C.SCREEN_D)
    G.arc("fill", "pie", X0, K.Y(hoodY - d * 0.9), R * 0.7 * S, pi, 2 * pi, 36)
    K.col(C.SCREEN, 0.85)
    G.arc("fill", "pie", X0, K.Y(hoodY - d * 0.9), R * 0.6 * S, pi, 2 * pi, 32)
    local ar, ay = R * 0.17, hoodY - R * 0.4
    G.setLineWidth(max(1, 0.5 * S))
    K.col(C.CYAN, 0.8)
    G.arc("line", "open", X0, K.Y(ay), ar * S, pi, 2 * pi, 16)
    G.line(K.X(cx - ar), K.Y(ay), K.X(cx - ar), K.Y(ay + R * 0.18))
    G.line(K.X(cx + ar), K.Y(ay), K.X(cx + ar), K.Y(ay + R * 0.18))
    -- (the tray, out, its sockets empty)
    local tfY, tbY, tfW, tbW = ft - R * 0.04, ft - R * 0.24, R * 0.82, R * 0.68
    K.col(C.TRAY_D)
    quad(cx - tfW, tfY, cx + tfW, tfY, cx + tfW, tfY + R * 0.05, cx - tfW, tfY + R * 0.05)
    K.col(C.TRAY)
    quad(cx - tbW, tbY, cx + tbW, tbY, cx + tfW, tfY, cx - tfW, tfY)
    local my, mw = (tfY + tbY) / 2, (tfW + tbW) / 2
    local slot = mw * 2 / 6
    K.col(C.SOCKET)
    for i = 1, 6 do
      G.ellipse("fill", K.X(cx - mw + slot * (i - 0.5)), K.Y(my), slot * 0.36 * S, slot * 0.15 * S, 12)
    end
    -- (the hood's front: the thick red arch, its light, its cyan line)
    local ringY = K.Y(hoodY)
    G.setLineWidth(R * 0.22 * S)
    K.col(C.DOME_D)
    G.arc("line", "open", X0, ringY + 0.5 * S, R * 0.89 * S, pi, 2 * pi, 48)
    K.col(C.DOME)
    G.arc("line", "open", X0, ringY, R * 0.89 * S, pi, 2 * pi, 48)
    G.setLineWidth(max(1, R * 0.08 * S))
    K.col(C.DOME_L, 0.55)
    G.arc("line", "open", X0, ringY, R * 0.92 * S, pi * 1.08, pi * 1.42, 18)
    G.setLineWidth(max(1, 0.5 * S))
    K.col(C.CYAN, 0.75 + 0.2 * sin(clock * 3))
    G.arc("line", "open", X0, ringY, R * 0.86 * S, pi + 0.05, 2 * pi - 0.05, 40)
    -- (the base's front: the dark screen, the button)
    K.grad(K.R(cx - bw, ft, bw * 2, fb - ft), 1.2, C.BASE_FRONT, C.BASE_FRONT_D)
    K.col(C.WHITE, 0.8)
    K.box("fill", K.R(cx - bw + 0.6, ft, bw * 2 - 1.2, 0.4))
    K.grad(K.R(cx - bw + R * 0.1, ft + (fb - ft) * 0.18, bw * 2 - R * 0.2, (fb - ft) * 0.64), 1, C.PANEL, C.PANEL_D, 0.97)
    local btnR, by = (fb - ft) * 0.5, ft + (fb - ft) * 0.5
    K.col(C.DOME_D)
    G.circle("fill", X0, K.Y(by + btnR * 0.12), btnR * 1.04 * S, 24)
    K.col(C.DOME)
    G.circle("fill", X0, K.Y(by), btnR * S, 24)
    G.setLineWidth(max(1, 0.4 * S))
    K.col(C.CYAN, 0.85)
    G.circle("line", X0, K.Y(by), btnR * 0.66 * S, 20)
    K.glow(cx, hoodY - R * 0.3, R * 1.2, R * 0.7, C.CYAN, 0.1)
  end

  -- the magazine rack beside the counter (its right part in sight): a white case, two shelves of
  -- magazines of every colour, leaning a little
  local function drawRack(x, foot, w, h)
    shadow(x + w / 2, foot, w * 0.6, 2, 0.4)
    K.col(C.PC_EDGE)
    K.box("fill", K.R(x - 0.8, foot - h - 0.8, w + 1.6, h + 0.8), 1.6)
    K.grad(K.R(x, foot - h, w, h), 1.2, C.PC_BODY, C.PC_BODY_D)
    local shH = (h - 6) / 2
    for shelf = 0, 1 do
      local sy = foot - h + 2 + shelf * (shH + 2)
      K.col(C.RACK_BACK)
      K.box("fill", K.R(x + 2, sy, w - 4, shH))
      local mx, k = x + 2.6, shelf * 3
      while mx < x + w - 5 do
        k = k + 1
        local mw = 3.4 + (k * 7 % 3) * 0.9
        local mhh = shH * (0.66 + (k * 5 % 4) * 0.08)
        local m = k % 5
        K.col(m == 0 and C.MAG_A or (m == 1 and C.MAG_B or (m == 2 and C.MAG_C or (m == 3 and C.MAG_D or C.MAG_E))))
        K.box("fill", K.R(mx, sy + shH - mhh, mw, mhh), 0.4)
        K.col(C.WHITE, 0.4)
        K.box("fill", K.R(mx + 0.5, sy + shH - mhh + 0.6, 0.6, mhh - 1.2))
        mx = mx + mw + 0.7
      end
      K.col(C.PC_GREY_D)
      K.box("fill", K.R(x + 1, sy + shH, w - 2, 1.4))
    end
  end

  -- the players' PC beside the counter (its left part in sight): white above, its green screen, the keys,
  -- grey below, a green light
  local function drawPlayerPC(x, foot, w, h)
    local G = K.graphics()
    shadow(x + w / 2, foot, w * 0.6, 2, 0.4)
    K.col(C.PC_EDGE)
    K.box("fill", K.R(x - 0.8, foot - h - 0.8, w + 1.6, h + 0.8), 3)
    K.grad(K.R(x, foot - h, w, h), 2.6, C.PC_BODY, C.PC_BODY_D)
    local sx, sy, sw, sh = x + w * 0.14, foot - h + h * 0.18, w * 0.72, h * 0.3
    K.col(C.PC_EDGE)
    K.box("fill", K.R(sx - 0.7, sy - 0.7, sw + 1.4, sh + 1.4), 1.4)
    K.grad(K.R(sx, sy, sw, sh), 1.2, C.GREEN_SCREEN, C.GREEN_SCREEN_D)
    K.col(C.WHITE, 0.45)
    K.box("fill", K.R(sx + 1, sy + 1, 1, sh - 2))
    local ky = sy + sh + h * 0.07
    K.grad(K.R(x + w * 0.1, ky, w * 0.8, h * 0.13), 0.8, C.PC_GREY, C.PC_GREY_D)
    for i = 0, 5 do
      K.col(C.PC_BODY)
      K.box("fill", K.R(x + w * 0.14 + i * w * 0.12, ky + h * 0.03, w * 0.08, h * 0.06), 0.3)
    end
    K.grad(K.R(x + 1, foot - h * 0.3, w - 2, h * 0.3 - 1), 1, C.PC_GREY, C.PC_GREY_D)
    K.col(C.LED_ON)
    G.circle("fill", K.X(x + w * 0.2), K.Y(foot - h * 0.22), 0.8 * K.sc, 10)
  end

  -- the floor beyond the counter's ends: pale, with Emerald's rounded tiles, larger nearer
  local function drawFloor(x, y0, w, y1, cx, L)
    K.grad(K.R(x, y0, w, y1 - y0), 0, C.FLOOR_FAR, C.FLOOR)
    local ty, row = y0 + 2, 0
    while ty < y1 do
      local sz = 4.6 + row * 1.5
      local step = sz * 1.45
      for side = -1, 1, 2 do
        local tx = cx + side * (L + step * 0.5)
        while (side < 0 and tx + sz / 2 > x) or (side > 0 and tx - sz / 2 < x + w) do
          K.col(C.FLOOR_TILE, 0.7)
          K.box("fill", K.R(tx - sz / 2, ty, sz, sz * 0.62), sz * 0.18)
          tx = tx + side * step
        end
      end
      ty = ty + sz * 0.62 + 1.2 + row * 0.4
      row = row + 1
    end
  end

  local SLAT, WING, BACK, BTOP = 24, 20, 25, 6   -- (the slats; the counter's sides, how far back the wall is, its back's top)
  local pcTop = 0    -- (her PC's top, this frame: the choice sits above it)
  -- the room; L: the counter's half width -- an open rectangle round her, its sides at cx +- L, its back
  -- against the wall (the machine on it); her PC on its desk inside, beside her
  local function drawRoom(b, cx, counterY, clock, head, hU, L)
    local x, y, w, h = b[1], b[2], b[3], b[4]
    local wallY = counterY - BACK
    slatWall(x, y, w, wallY - y, cx, SLAT)
    skirting(x, wallY, w)
    -- (ceiling light: a pool on the wall over her)
    K.glow(cx, y + 6, w * 0.42, h * 0.36, C.LAMP, 0.24 + 0.02 * sin(clock * 0.7))
    -- (the window behind her, her head before its lower half)
    local ww = min(w * 0.42, hU * 1.15, 116)
    local wy = y + 12
    drawWindow(cx - ww / 2, wy, ww, min(head + hU * 0.4, wallY - 11) - wy)
    -- (the floor; the counter's top cream all round, the inside in shade: the back's face, the sides' inner
    -- faces, their lit edges)
    drawFloor(x, wallY, w, y + h, cx, L)
    local lx = cx - L
    K.grad(K.R(lx, wallY - 1, L * 2, counterY + 2 - wallY), 2.5, C.TOP_CREAM_D, C.TOP_CREAM)
    local hx, hy, hw = lx + WING, wallY + BTOP, L * 2 - WING * 2
    local hh = counterY + 2 - hy
    K.grad(K.R(hx, hy, hw, hh), 1.2, C.BACK_FACE, C.BACK_FACE_D)
    K.grad(K.R(hx, hy, hw, 1.3), 0, C.EDGE_TAN, C.EDGE_TAN_D)
    for k = 1, 3 do
      K.col(C.BLACK, 0.07)
      K.box("fill", K.R(hx, hy, 1.3 * k, hh))
      K.box("fill", K.R(hx + hw - 1.3 * k, hy, 1.3 * k, hh))
    end
    K.col(C.WHITE, 0.6)
    K.box("fill", K.R(hx - 0.7, hy + 0.6, 0.7, hh))
    K.box("fill", K.R(hx + hw, hy + 0.6, 0.7, hh))
    -- (beyond the counter's ends: the magazine rack on her right, the players' PC on her left)
    local re = cx - L - 5
    if re > x + 3 then drawRack(re - 40, wallY + 9, 40, 40) end
    local pl = cx + L + 5
    if pl < x + w - 3 then drawPlayerPC(pl, wallY + 9, 34, 52) end
    -- (the healing machine against the wall on her right, over the counter)
    local R = min(22, L * 0.19)
    local mcx = min(lx + WING + R * 1.16 + 2, cx - hU * 0.4 - R * 0.46)
    drawHealer(mcx, wallY + BTOP * 0.7, R, clock)
    -- (her PC on its desk inside the counter by its side, on her left: the screen's right, turned to her; the desk
    -- running to the counter's side, its cream top, its tan edge, its front in shade down behind the counter)
    local pw, ph = min(22, w * 0.085), min(28, (counterY - head) * 0.46)
    local px = max(cx + hU * 0.4, cx + L - WING - pw - 6)
    local dx, dy = px - 6, counterY - 10
    local dw = max(pw + 9, cx + L - WING - dx)
    shadow(dx + dw / 2, dy + 2, dw * 0.6, 2.2, 0.3)
    K.grad(K.R(dx, dy + 2.6, dw, counterY + 2 - dy - 2.6), 0, C.BACK_FACE, C.BACK_FACE_D)
    K.grad(K.R(dx, dy - 1.6, dw, 3.4), 1, C.TOP_CREAM_D, C.TOP_CREAM)
    K.grad(K.R(dx, dy + 1.8, dw, 1), 0, C.EDGE_TAN, C.EDGE_TAN_D)
    drawPC(px, dy + 0.6, pw, ph)
    pcTop = dy + 0.6 - ph
  end

  -- the nurse: her sheet's frame for the way she faces, at whole pixels, a soft light round her head;
  -- a nod while she talks, a bow; walking (st.walk: to the machine and back) her sheet's four steps in
  -- turn, a slight lift with each (one pixel), gliding along
  local STEP = 0.15
  local function drawNurse(cx, foot, hU, clock)
    local art = env.nurse and env.nurse()
    if not (art and art.image and art.quads) then return end
    local G = K.graphics()
    local px = max(1, floor(hU * K.sc / art.h + 0.5))
    local t = st.now()
    local face, step, lift = st.face, 0, 0
    local wk = st.walk
    if wk then
      local since = t - wk.t0
      local e = min(1, max(0, since / wk.dur))
      cx = cx + wk.from + (wk.to - wk.from) * e
      if e < 1 then
        face = wk.face
        step = floor(since / STEP) % 4
        lift = floor(abs(sin(since / STEP * pi)) * 0.9 + 0.5) * px
      end
    end
    local q = art.quads[(FACE[face] or 0) * 4 + step] or art.quads[0]
    local sw, sh = art.w * px, art.h * px
    local nod = (st.typing() and floor(clock * 7) % 2 == 1) and px or 0
    local dip = 0
    if st.bowT and t - st.bowT < 0.8 then dip = floor(sin(min(1, (t - st.bowT) / 0.8) * pi) * 2.5 + 0.5) * px end
    local X = floor(K.X(cx) - sw / 2 + 0.5)
    local Y = floor(K.Y(foot) - sh + 0.5) + nod + dip - lift
    K.glow(cx, foot - hU * 0.72, hU * 0.42, hU * 0.36, C.LAMP, 0.22)
    local f = K.getFade()
    G.setColor(1, 1, 1, f)
    G.draw(art.image, q, X, Y, 0, px, px)
  end

  -- the counter's front, as Emerald's (the room drew the rest of its rectangle): the cream top with the
  -- white pad in front of her, a tan front edge, the body white in its own shadow with grey panels, rounded
  -- at its ends; a big Poké Ball on a grey stand on each front corner, turned to face it
  local TOP, PANEL_W = 8.5, 34
  local function drawCounter(x, y, w, h, cx, L)
    local G = K.graphics()
    local lx = cx - L
    shadow(cx, y + 0.6, 22, 2.4, 0.3)
    -- (the top)
    K.grad(K.R(lx, y, L * 2, TOP), TOP * 0.45, C.TOP_CREAM, C.TOP_CREAM_D)
    K.col(C.WHITE, 0.8)
    K.box("fill", K.R(lx + 3, y + 0.4, L * 2 - 6, 0.6))
    -- (the pad in front of her)
    shadow(cx, y + TOP * 0.6, 18, 3.4, 0.22)
    K.col(C.PAD_EDGE)
    G.ellipse("fill", K.X(cx), K.Y(y + TOP * 0.5), 16 * K.sc, 3.1 * K.sc, 40)
    K.col(C.WHITE)
    G.ellipse("fill", K.X(cx), K.Y(y + TOP * 0.46), 15 * K.sc, 2.5 * K.sc, 40)
    K.col(C.PAD_EDGE, 0.35)
    G.ellipse("fill", K.X(cx), K.Y(y + TOP * 0.56), 12.5 * K.sc, 1.2 * K.sc, 32)
    -- (the front edge, rounded: tan, lit along its top)
    K.grad(K.R(lx, y + TOP, L * 2, 2), 1, C.EDGE_TAN, C.EDGE_TAN_D)
    K.col(C.WHITE, 0.35)
    K.box("fill", K.R(lx + 1, y + TOP, L * 2 - 2, 0.4))
    -- (the body: white in shadow, grey panels, a dark kick plate, its rounded ends darker)
    local fy = y + TOP + 2
    local fh = y + h - fy
    K.grad(K.R(lx, fy, L * 2, fh), 0, C.FRONT_TOP, C.FRONT_FOOT)
    K.grad(K.R(lx, fy, L * 2, 4), 0, C.AO_DARK, C.AO_CLEAR)
    local px = cx - PANEL_W * 0.5 - PANEL_W * math.ceil((cx - PANEL_W * 0.5 - lx) / PANEL_W)
    while px < cx + L do
      if px > lx + 4 and px < cx + L - 4 then
        K.col(C.FRONT_LINE, 0.55)
        K.box("fill", K.R(px - 0.4, fy + 3, 0.8, fh - 8))
        K.col(C.WHITE, 0.3)
        K.box("fill", K.R(px + 0.4, fy + 3, 0.5, fh - 8))
      end
      px = px + PANEL_W
    end
    K.col(C.FRONT_LINE, 0.5)
    K.box("fill", K.R(lx, fy + 2.4, L * 2, 0.6))
    K.col(C.KICK)
    K.box("fill", K.R(lx, y + h - 4, L * 2, 4))
    for k = 1, 3 do
      K.col(C.BLACK, 0.08)
      K.box("fill", K.R(lx, y + TOP, 1.4 * k, h - TOP))
      K.box("fill", K.R(cx + L - 1.4 * k, y + TOP, 1.4 * k, h - TOP))
    end
    -- (the Poké Balls on its corners, each turned to face its corner)
    local r = min(10, WING * 0.52)
    for side = -1, 1, 2 do
      local bx, foot = cx + side * (L - WING * 0.5), y + TOP * 0.62
      shadow(bx, foot, r * 1.15, r * 0.24, 0.45)
      K.col(C.PC_EDGE)
      K.box("fill", K.R(bx - r * 0.82, foot - r * 0.44, r * 1.64, r * 0.48), r * 0.2)
      K.grad(K.R(bx - r * 0.72, foot - r * 0.4, r * 1.44, r * 0.36), r * 0.15, C.PC_GREY, C.PC_GREY_D)
      turnedBall(bx, foot - r * 0.98, r, side)
    end
  end

  -- frosted glass under a box: the scene behind it, blurred (the lighting's copy) -> true when it drew
  local function frosted(b, rad)
    if not (Lt and Lt.glass) then return false end
    return Lt.glass(K.graphics(), K.X(b[1]), K.Y(b[2]), b[3] * K.sc, b[4] * K.sc, rad * K.sc, K.getFade())
  end

  -- the words, as lines that fit, with each line's typed-out beginnings (made when the words, the width
  -- or the text size change; never on other frames)
  local function linesOf(text, w, size)
    local lines, line = {}, ""
    for word in tostring(text or ""):gmatch("%S+") do
      local try = line == "" and word or (line .. " " .. word)
      if line ~= "" and K.width(try, size) > w then
        lines[#lines + 1] = line
        line = word
      else
        line = try
      end
    end
    if line ~= "" then lines[#lines + 1] = line end
    local out = { lines = lines, pre = {}, count = {}, size = size, line = LINE * size / SIZE * K.textScale() }
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

  -- the words' box: white glass along the foot, her name on a pink tab, the words typed out, an arrow
  -- bobbing when there's more
  local function drawBox(b, clock)
    local s = st.say
    -- (none until her words start: she's still walking back)
    if not s or st.now() < s.t then return end
    local G = K.graphics()
    local k = K.outCubic((st.now() - s.t) / 0.18)
    local f0 = K.getFade()
    -- (frosted glass: the scene behind it blurred, a white tint over it; plain white without the lighting)
    if frosted(b, 5) then
      K.glass(b, 5, 0.62, C.WHITE, 0.75, 0.95)
    else
      K.glass(b, 5, 0.95, C.WHITE, 0.6, 0.9)
    end
    local nm = T("nurse.name")
    local nw = K.width(nm, 3.4) + 7
    K.grad(K.R(b[1] + 7, b[2] - 2.8, nw, 5.6), 2.8, C.PINK, C.PINK_D)
    K.bold(nm, b[1] + 7, b[2] - 2, 3.4, C.WHITE, "center", nw)
    local tw = b[3] - 16
    local TS = K.textScale()
    local L = st.lines
    if not L or st.linesW ~= floor(tw) or st.linesText ~= s.text or st.linesTS ~= TS then
      L = linesOf(s.text, tw, SIZE)
      local sz = SIZE
      while #L.lines * L.line > b[4] - 6 and sz > SIZE * 0.7 do
        sz = sz - 0.3
        L = linesOf(s.text, tw, sz)
      end
      st.lines, st.linesW, st.linesText, st.linesTS = L, floor(tw), s.text, TS
    end
    K.setFade(f0 * (0.4 + 0.6 * k))
    local left = st.shown()
    local total = #L.lines * L.line
    local ly = b[2] + max(3, (b[4] - total) / 2 + 0.3)
    for j = 1, #L.lines do
      local cnt = L.count[j]
      if left >= cnt then
        K.text(L.lines[j], b[1] + 8, ly, L.size, C.INK)
        left = left - cnt
      else
        if left > 0 then K.text(L.pre[j][left], b[1] + 8, ly, L.size, C.INK) end
        break
      end
      ly = ly + L.line
    end
    K.setFade(f0)
    if not st.typing() and not st.menu and st.after ~= nil then
      local ax, ay = b[1] + b[3] - 7, b[2] + b[4] - 5 + abs(sin(clock * 5)) * 0.9
      K.col(C.INK, 0.75)
      G.setLineWidth(max(1, 0.7 * K.sc))
      G.line(K.X(ax - 2), K.Y(ay - 1.2), K.X(ax), K.Y(ay + 0.8), K.X(ax + 2), K.Y(ay - 1.2))
    end
    K.addHit(b, "win", V.BOX)
  end

  -- the choice: navy glass, the chosen row a white pill with a lime arrow
  local ROW = 11
  local function drawMenu(x, y, w, clock)
    local n = #st.rows
    local e = K.outBack((st.now() - st.menuT) / 0.24)
    local f0 = K.getFade()
    K.setFade(f0 * min(1, max(0, e)))
    local G = K.graphics()
    local h = n * ROW + 3
    local pb = K.R(x + (1 - min(1, e)) * 6, y, w, h)
    K.shadow(pb, 3, 1.4, 0.3)
    -- (frosted navy glass)
    if frosted(pb, 3) then
      K.grad(pb, 3, C.NAVY, C.NAVY_D, 0.72)
      K.grad(K.R(pb[1], pb[2], pb[3], min(pb[4], 8)), 3, C.SHEEN, C.SHEEN_CLEAR)
      K.ring(pb, 3, C.WHITE, 0.35, 0.4)
    else
      K.grad(pb, 3, C.NAVY, C.NAVY_D, 0.94)
      K.ring(pb, 3, C.WHITE, 0.18, 0.4)
    end
    for i = 1, n do
      local rb = K.R(pb[1] + 2, pb[2] + 1.5 + (i - 1) * ROW, pb[3] - 4, ROW)
      local chosen = i == st.cursor
      local fs = K.fit(st.rows[i], 4.6, rb[3] - 9)
      if chosen then
        K.col(C.WHITE)
        K.box("fill", K.R(rb[1] + 4, rb[2] + 1, rb[3] - 4, rb[4] - 2), 1.8)
        local ax, ay = rb[1] + 1.4 + abs(sin(clock * 6)) * 0.7, rb[2] + rb[4] / 2
        K.col(C.LIME)
        G.polygon("fill", K.X(ax - 1.4), K.Y(ay - 2.4), K.X(ax + 2.2), K.Y(ay), K.X(ax - 1.4), K.Y(ay + 2.4))
        K.text(st.rows[i], rb[1] + 7, rb[2] + (ROW - fs * 1.25) / 2, fs, C.INK)
      else
        K.text(st.rows[i], rb[1] + 7, rb[2] + (ROW - fs * 1.25) / 2, fs, C.WHITE)
      end
      K.addHit(rb, "win", V.ROW_AT + i)
    end
    K.setFade(f0)
  end

  -- ------- the healing machine, three-quarters from above
  -- the team's screen on the machine's front: each Pokémon's icon and its health, three either side of
  -- the button
  local function drawTeam(px0, py, pw, ph, gap, e, glow0, clock)
    local team = st.team
    local n = #team
    local half = (pw - gap) / 2
    local colW = half / 3
    local fill = st.mc.healed and K.outCubic((e - glow0) / 1.4) or 0
    local frame = floor(clock * 3) % 2
    for i = 1, n do
      local m = team[i]
      local side = i <= 3 and 0 or 1
      local col = (i - 1) % 3
      local cx0 = px0 + side * (half + gap) + colW * col
      local placed = e >= tm.place0 + (i - 1) * tm.each
      local a = placed and 1 or 0.3
      local isz = min(10, ph - 4)
      if env.monIconOf and m.mon then
        pcall(env.monIconOf, m.mon, cx0 + colW * 0.5 - isz / 2, py + 0.6, isz, frame, a)
      end
      if not m.egg and (m.max or 0) > 0 then
        local r0 = min(1, (m.hp or 0) / m.max)
        local r = r0 + (1 - r0) * fill
        local hb = K.R(cx0 + 1.5, py + ph - 3.2, colW - 3, 1.5)
        K.col(C.HP_BACK)
        K.box("fill", hb, 0.75)
        if hb[3] * r >= 0.8 then
          K.col(r < 0.5 and C.HP_LOW or C.HP, a)
          K.box("fill", K.R(hb[1], hb[2], hb[3] * r, hb[4]), 0.75)
        end
      end
    end
    K.rescissor()
  end

  local teamAt = { 0, 0, 0, 0, 0, 0, 0 }    -- (where the team goes on the machine's screen, this frame)
  local function drawMachine(b, clock)
    local x, y, w, h = b[1], b[2], b[3], b[4]
    local G = K.graphics()
    local mc = st.mc
    local e = st.now() - mc.t0
    local n = #st.team
    local cx = x + w / 2
    local R = min(w * 0.34, h * 0.46)
    local glow0 = tm.place0 + n * tm.each + tm.gap + tm.slide
    local g = e >= glow0 and K.outCubic((e - glow0) / tm.glow) or 0
    local inK = K.inOut((e - (glow0 - tm.slide)) / tm.slide)
    if mc.outT then
      g = g * (1 - K.outCubic((e - mc.outT) / 0.4))
      inK = inK * (1 - K.inOut((e - mc.outT - 0.2) / tm.slide))
    end
    -- (the machine's footprint)
    local ft = y + h * 0.72                  -- the base's front top edge
    local depth = R * 0.34                   -- how far back its top runs
    local fb = ft + R * 0.3                  -- its front's foot
    local bw, inset = R * 1.16, R * 0.12
    -- (the room: the slatted orange wall right behind it, in the dim light, lit by the machine and shadowed by its
    -- hood; the table it stands on meeting the wall just behind its base, glossy, the counter's tan edge
    -- and its white front along the foot)
    local hz = ft - depth - R * 0.03
    slatWall(x, y, w, hz - y + 0.5, cx, 30)
    skirting(x, hz + 0.5, w)
    K.grad(K.R(x, y, w, hz - y + 0.5), 0, C.WALL_DIM_TOP, C.WALL_DIM_FOOT)
    shadow(cx + R * 0.1, hz - R * 0.42, R * 1.12, R * 0.78, 0.42)
    K.glow(cx, hz - R * 0.1, R * 1.9, R * 0.8, C.DOME_L, 0.18 + 0.16 * g)
    K.glow(cx, hz - R * 0.5, R * 1.4, R * 0.9, C.CYAN, 0.06 + 0.26 * g)
    local te = y + h * 0.94
    K.grad(K.R(x, hz, w, te - hz), 0, C.TABLE_FAR, C.TABLE_NEAR)
    K.grad(K.R(x, hz, w, 2.5), 0, C.AO_DARK, C.AO_CLEAR)
    K.col(C.WHITE, 0.55)
    K.box("fill", K.R(x, te - 1.1, w, 0.5))
    K.grad(K.R(x, te, w, 1.6), 0, C.EDGE_TAN, C.EDGE_TAN_D)
    K.grad(K.R(x, te + 1.6, w, y + h - te - 1.6), 0, C.FRONT_TOP, C.FRONT_FOOT)
    shadow(cx, fb + 0.5, bw * 1.18, R * 0.16, 0.6)
    -- (the glow spilling onto the counter)
    if g > 0.01 then K.glow(cx, fb + R * 0.1, R * 1.7, R * 0.3, C.WHITE, 0.22 * g) end
    -- the base's top (lit) and its front
    K.col(C.BASE_TOP_D)
    quad(cx - bw + inset, ft - depth, cx + bw - inset, ft - depth, cx + bw, ft, cx - bw, ft)
    K.col(C.BASE_TOP, 0.85)
    quad(cx - bw + inset * 1.1, ft - depth + 0.6, cx + bw - inset * 1.1, ft - depth + 0.6, cx + bw - 0.6, ft - 0.6,
      cx - bw + 0.6, ft - 0.6)
    -- the hood: its top's thickness (lighter, set back), then the cavity inside it
    local hoodY = ft - depth * 0.55
    local X0, S = K.X(cx), K.sc
    local d = R * 0.13
    K.col(C.HOOD_TOP)
    G.arc("fill", "pie", X0, K.Y(hoodY - d), R * 0.97 * S, pi, 2 * pi, 56)
    K.col(C.CAVITY)
    G.arc("fill", "pie", X0, K.Y(hoodY), R * 0.78 * S, pi, 2 * pi, 48)
    K.col(C.SCREEN_D)
    G.arc("fill", "pie", X0, K.Y(hoodY - d * 0.9), R * 0.7 * S, pi, 2 * pi, 48)
    K.col(C.SCREEN, 0.85)
    G.arc("fill", "pie", X0, K.Y(hoodY - d * 0.9), R * 0.6 * S, pi, 2 * pi, 40)
    -- (the cavity's own shadow, darkest at its top)
    shadow(cx, hoodY - R * 0.62, R * 0.62, R * 0.22, 0.5)
    -- (the arch on its back wall, lit)
    local ar = R * 0.17
    local ay = hoodY - R * 0.4
    G.setLineWidth(max(1, 1.0 * S))
    K.col(C.CYAN, 0.75 + 0.25 * g)
    G.arc("line", "open", X0, K.Y(ay), ar * S, pi, 2 * pi, 20)
    G.arc("line", "open", X0, K.Y(ay), ar * 0.6 * S, pi, 2 * pi, 16)
    G.line(K.X(cx - ar), K.Y(ay), K.X(cx - ar), K.Y(ay + R * 0.18))
    G.line(K.X(cx + ar), K.Y(ay), K.X(cx + ar), K.Y(ay + R * 0.18))
    -- (the glow: the cavity flooding white behind the tray, the balls dark against it)
    if g > 0.01 then
      K.col(C.WHITE, 0.85 * g)
      G.arc("fill", "pie", X0, K.Y(hoodY) - 0.4 * S, R * 0.79 * S, pi, 2 * pi, 48)
    end
    -- the tray, in perspective, sliding back into the cavity (smaller, in its shadow)
    local back = R * 0.28 * inK
    local s = 1 - 0.2 * inK
    local tfY, tbY = ft - R * 0.04 - back, ft - R * 0.24 - back * 0.9
    local tfW, tbW = R * 0.82 * s, R * 0.68 * s
    local thick = R * 0.05 * s
    K.col(C.TRAY_D)
    quad(cx - tfW, tfY, cx + tfW, tfY, cx + tfW, tfY + thick, cx - tfW, tfY + thick)
    K.col(C.TRAY)
    quad(cx - tbW, tbY, cx + tbW, tbY, cx + tfW, tfY, cx - tfW, tfY)
    K.col(C.TRAY_HI, 0.6)
    quad(cx - tbW, tbY, cx + tbW, tbY, cx + tbW, tbY + 0.5, cx - tbW, tbY + 0.5)
    if inK > 0 then
      K.col(C.CAVITY, 0.45 * inK * (1 - g))
      quad(cx - tbW, tbY, cx + tbW, tbY, cx + tfW, tfY + thick, cx - tfW, tfY + thick)
    end
    if g > 0.01 then
      K.col(C.TRAY_HI, 0.4 * g)
      quad(cx - tbW, tbY, cx + tbW, tbY, cx + tfW, tfY + thick, cx - tfW, tfY + thick)
    end
    -- (six sockets along its middle, a ball in each that's come in)
    local my = (tfY + tbY) / 2
    local mw = (tfW + tbW) / 2
    local slot = mw * 2 / 6
    local br = slot * 0.34
    for i = 1, 6 do
      local sx = cx - mw + slot * (i - 0.5)
      K.col(C.SOCKET)
      G.ellipse("fill", K.X(sx), K.Y(my), slot * 0.4 * S, slot * 0.17 * S, 18)
      K.col(C.BLACK, 0.35)
      G.ellipse("fill", K.X(sx), K.Y(my - slot * 0.03), slot * 0.34 * S, slot * 0.11 * S, 16)
      if i <= n then
        local dd = (e - (tm.place0 + (i - 1) * tm.each)) / 0.3
        if dd >= 0 then
          local drop = (1 - K.outBack(dd)) * -R * 0.3
          shadow(sx, my, br * 1.05, br * 0.36, 0.5 * min(1, dd))
          ball(sx, my - br * 0.7 + drop, br, min(1, dd * 2), inK * 0.8)
        end
      end
    end
    -- the hood's front: a thick red arch, lit from the top left, its cyan line
    -- (the arch as one thick stroke, 0.78 R to R: the opening left as it is; its shadow side under it)
    local ringY = K.Y(hoodY)
    G.setLineStyle("smooth")
    G.setLineWidth(R * 0.22 * S)
    K.col(C.DOME_D)
    G.arc("line", "open", X0, ringY + 0.9 * S, R * 0.89 * S, pi, 2 * pi, 64)
    K.col(C.DOME)
    G.arc("line", "open", X0, ringY, R * 0.89 * S, pi, 2 * pi, 64)
    -- (the highlights and the line, all on the ring)
    G.setLineWidth(max(1, R * 0.1 * S))
    K.col(C.DOME_L, 0.55)
    G.arc("line", "open", X0, ringY, R * 0.92 * S, pi * 1.08, pi * 1.42, 24)
    G.setLineWidth(max(1, R * 0.05 * S))
    K.col(C.WHITE, 0.4)
    G.arc("line", "open", X0, ringY, R * 0.95 * S, pi * 1.12, pi * 1.32, 20)
    G.setLineWidth(max(1, 2.4 * S))
    K.col(C.CYAN, 0.28 + 0.3 * g)
    G.arc("line", "open", X0, ringY, R * 0.86 * S, pi + 0.05, 2 * pi - 0.05, 56)
    G.setLineWidth(max(1, 0.9 * S))
    K.col(C.CYAN, 0.75 + 0.25 * sin(clock * 3) * 0.5 + 0.25 * g)
    G.arc("line", "open", X0, ringY, R * 0.86 * S, pi + 0.05, 2 * pi - 0.05, 56)
    -- (the opening's inner edge, its thickness in shadow)
    G.setLineWidth(max(1, R * 0.03 * S))
    K.col(C.DOME_D)
    G.arc("line", "open", X0, ringY, R * 0.785 * S, pi, 2 * pi, 48)
    -- the glow: light out of the cavity, a cyan halo, sparkles over the balls
    if g > 0.01 then
      K.glow(cx, hoodY - R * 0.45, R * 0.9, R * 0.55, C.WHITE, 0.22 * g)
      K.glow(cx, hoodY - R * 0.3, R * 1.6, R, C.CYAN, 0.2 * g)
      for i = 1, 7 do
        local a = clock * 1.4 + i * 0.9
        local sx = cx + cos(a) * R * 0.55
        local sy = hoodY - R * 0.35 + sin(a * 1.3) * R * 0.2
        K.glow(sx, sy, 2.6, 2.6, C.WHITE, g * (0.5 + 0.5 * sin(clock * 9 + i)))
      end
    end
    -- the base's front: lit plastic, the team's screen across it, the round button in the middle
    K.grad(K.R(cx - bw, ft, bw * 2, fb - ft), 2, C.BASE_FRONT, C.BASE_FRONT_D)
    K.col(C.WHITE, 0.8)
    K.box("fill", K.R(cx - bw + 1, ft, bw * 2 - 2, 0.5))
    local panel = K.R(cx - bw + R * 0.1, ft + (fb - ft) * 0.18, bw * 2 - R * 0.2, (fb - ft) * 0.64)
    K.grad(panel, 2, C.PANEL, C.PANEL_D, 0.97)
    K.ring(panel, 2, C.CYAN, 0.3 + 0.2 * g, 0.35)
    K.col(C.WHITE, 0.08)
    K.box("fill", K.R(panel[1] + 1, panel[2] + 0.6, panel[3] - 2, panel[4] * 0.35), 1.5)
    local btnR = (fb - ft) * 0.5
    -- (the team on it: drawn after the lighting, as the words are -- the game's icons punch holes in a canvas)
    teamAt[1], teamAt[2], teamAt[3], teamAt[4], teamAt[5], teamAt[6], teamAt[7] = panel[1] + 1, panel[2], panel[3] - 2, panel[4],
      btnR * 2 + 4, e, glow0
    local by = ft + (fb - ft) * 0.5
    shadow(cx, by + btnR * 0.9, btnR * 1.1, btnR * 0.3, 0.45)
    K.col(C.DOME_D)
    G.circle("fill", X0, K.Y(by + btnR * 0.12), btnR * 1.04 * S, 36)
    K.col(C.DOME)
    G.circle("fill", X0, K.Y(by), btnR * S, 36)
    shade(cx, by, btnR, 0.4)
    G.setLineWidth(max(1, 0.8 * S))
    K.col(C.CYAN, 0.8 + 0.2 * g)
    G.circle("line", X0, K.Y(by), btnR * 0.66 * S, 32)
    -- (Yellow's Pikachu, waiting beside the machine)
    if st.model.pikachu and env.monIcon then
      pcall(env.monIcon, 25, cx + bw + 3, ft - 14, 16, floor(clock * 4) % 2, 1, 1, 1, 1)
      K.rescissor()
    end
  end

  function V.draw(b, clock, portrait)
    local x, y, w, h = b[1], b[2], b[3], b[4]
    local G = K.graphics()
    -- (fading from the field and back to it: only the black over it, the whole window)
    if st.scene == "in" or st.scene == "out" then
      G.setColor(0, 0, 0, st.black)
      G.rectangle("fill", 0, 0, K.ww, K.wh)
      return
    end
    meshes()
    K.addHit(b, "win", V.SCREEN)
    local lit = Lt and Lt.begin(G)
    if st.scene == "machine" and st.mc then
      drawMachine(b, clock)
      if lit then
        Lt.finish(G, K.X(x), K.Y(y), w * K.sc, h * K.sc, K.X(x + w / 2), K.Y(y + h * 0.45), C.LOOK_MACHINE)
        K.rescissor()
      end
      drawTeam(teamAt[1], teamAt[2], teamAt[3], teamAt[4], teamAt[5], teamAt[6], teamAt[7], clock)
    else
      local cx = x + w / 2
      -- (her head near the top, the counter at her waist)
      local hU = portrait and h * 0.46 or h * 0.6
      local head = y + (portrait and h * 0.16 or h * 0.12)
      local foot = head + hU
      local counterY = head + hU * 0.74
      -- (the counter's half width: room beyond its ends for the rack and the PC, never narrower than her)
      local L = max(min(w / 2 - 22, 118), min(w / 2 - 2, hU * 0.5 + WING + 6))
      drawRoom(b, cx, counterY, clock, head, hU, L)
      drawNurse(cx, foot, hU, clock)
      drawCounter(x, counterY, w, y + h - counterY, cx, L)
      if lit then
        Lt.finish(G, K.X(x), K.Y(y), w * K.sc, h * K.sc, K.X(cx), K.Y(head + hU * 0.2), C.LOOK_ROOM)
        K.rescissor()
      end
      local TS = K.textScale()
      local bh = 30 + (TS - 1) * 18
      local bw = min(w - 16, 232)
      local box = K.R(cx - bw / 2, y + h - bh - 6, bw, bh)
      local bx, by, bww = box[1], box[2], box[3]
      drawBox(box, clock)
      if st.menu then
        local mw = min(w - 16, 96 + (TS - 1) * 40)
        local mh = #st.rows * ROW + 3
        -- (beside her, over the wall; upright, above the words: there's room)
        local mx = min(x + w - mw - 8, bx + bww - mw + 14)
        local above = portrait
        if not portrait and mx < cx + 20 then
          -- (narrower screens: clear of her face, narrower; too narrow and it goes above the words)
          mx = cx + 20
          mw = x + w - 8 - mx
          if mw < 66 then
            mw = min(w - 16, 96 + (TS - 1) * 40)
            mx = min(x + w - mw - 8, bx + bww - mw + 14)
            above = true
          end
        end
        -- (beside her: above her PC, the PC in sight)
        drawMenu(mx, above and (by - mh - 5) or min(by - mh - 5, pcTop - mh - 4), mw, clock)
      end
    end
    if st.black > 0 then
      K.col(C.BLACK, st.black)
      K.box("fill", b)
    end
  end

  function V.release() if Lt then Lt.release() end end

  return V
end
