-- The Pokémon Center's look (src/apps/pokecenter.lua's window, the latest games' counter in WoobOS's
-- glass), lit: the scene is drawn through src/lighting.lua (env.lighting: a key light, a vignette, a warm
-- grade and bloom in one shader), the words and the choice over it, sharp.
--   the counter: a wall with a wainscot under ceiling light, a shelf unit between brick pillars (each brick
--     its own shade, the light falling off down them), its shelves stocked (contact shadows, the boards'
--     edges, a warm strip under each), the nurse at whole pixels in a soft light, the
--     counter's glossy top and its lit sign (the Pokémon Center's ball, big, and its name), the words'
--     box along the foot (a bobbing arrow when there's more), the choice in navy glass beside her
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
  -- the room
  WALL_TOP = { 246, 238, 232 }, WALL_FOOT = { 226, 210, 204 },
  WAIN_TOP = { 232, 206, 204 }, WAIN_FOOT = { 206, 176, 178 }, MOLD = { 255, 248, 244 },
  BRICK = { 156, 66, 58 }, BRICK_B = { 140, 56, 50 }, BRICK_C = { 170, 78, 66 }, MORTAR = { 84, 38, 36 },
  BRICK_HI = { 255, 196, 170 },
  FRAME = { 58, 56, 66 }, FRAME_HI = { 120, 118, 132 }, FRAME_LO = { 26, 24, 32 },
  BACK_TOP = { 222, 214, 218 }, BACK_FOOT = { 190, 180, 188 },
  BOARD_TOP = { 150, 146, 158 }, BOARD = { 84, 80, 92 },
  AO_DARK = { 40, 30, 40, 0.34 }, AO_CLEAR = { 40, 30, 40, 0 },
  SHADE_CLEAR = { 30, 16, 20, 0 }, SHADE_DARK = { 30, 16, 20, 0.42 },
  LAMP = { 255, 232, 200 }, LED = { 255, 214, 160 },
  BALL_RED = { 226, 52, 64 }, BALL_INK = { 40, 40, 48 },
  BOX_BLUE = { 92, 150, 214 }, BOX_BLUE_L = { 176, 212, 244 },
  LEAF = { 96, 178, 98 }, LEAF_D = { 52, 120, 66 }, POT = { 244, 244, 244 },
  CAN = { 56, 160, 100 }, CAN_D = { 26, 96, 60 },
  VIAL = { 120, 104, 196 }, VIAL_D = { 70, 58, 138 },
  JAR = { 230, 176, 60 }, JAR_D = { 160, 108, 26 }, LID = { 92, 140, 196 },
  CRATE = { 250, 250, 252 }, CRATE_D = { 196, 198, 210 },
  -- (the healing items: each spray's body, light and dark; the trigger heads; the crystals; the flask)
  POTION = { 168, 104, 214 }, POTION_D = { 104, 56, 156 },
  SUPER = { 250, 160, 64 }, SUPER_D = { 196, 98, 26 },
  HYPER = { 240, 100, 170 }, HYPER_D = { 178, 44, 112 },
  MAXP = { 84, 150, 238 }, MAXP_D = { 38, 88, 182 },
  RESTORE = { 252, 212, 72 }, RESTORE_D = { 200, 148, 24 },
  ANTIDOTE = { 112, 200, 96 }, ANTIDOTE_D = { 54, 136, 52 },
  HEAD = { 86, 88, 102 }, HEAD_D = { 40, 40, 52 }, HEAD_HI = { 150, 152, 168 },
  GEM = { 255, 226, 88 }, GEM_D = { 222, 160, 30 }, GEM_HI = { 255, 250, 210 },
  ETHER = { 96, 196, 236 }, ETHER_D = { 40, 120, 190 }, CORK = { 176, 120, 72 },
  GREAT = { 66, 116, 220 },
  -- the counter and its sign
  SLAB_TOP = { 255, 252, 252 }, SLAB_FOOT = { 240, 214, 220 }, LIP = { 150, 40, 62 },
  COUNTER_TOP = { 232, 74, 100 }, COUNTER_FOOT = { 150, 28, 54 },
  SIGN_FRAME = { 72, 26, 40 }, SIGN_TOP = { 255, 255, 255 }, SIGN_FOOT = { 255, 222, 230 }, SIGN_INK = { 196, 30, 62 },
  SIGN_GLOW = { 255, 150, 180 },
  WHITE = { 255, 255, 255 }, BLACK = { 0, 0, 0 },
  -- the words and the choice
  INK = { 40, 42, 52 }, PINK = { 240, 104, 146 }, PINK_D = { 204, 60, 104 },
  NAVY = { 30, 46, 104 }, NAVY_D = { 16, 26, 66 }, LIME = { 186, 244, 64 },
  SHEEN = { 255, 255, 255, 0.22 }, SHEEN_CLEAR = { 255, 255, 255, 0 },
  -- the machine
  WALL_DIM_TOP = { 12, 6, 16, 0.7 }, WALL_DIM_FOOT = { 12, 6, 16, 0.42 },
  TABLE_FAR = { 140, 88, 104 }, TABLE_NEAR = { 204, 146, 160 },
  BASE_TOP = { 232, 218, 224 }, BASE_TOP_D = { 196, 178, 188 }, BASE_FRONT = { 218, 206, 214 },
  BASE_FRONT_D = { 176, 160, 172 },
  HOOD_TOP = { 246, 104, 128 }, DOME = { 218, 42, 72 }, DOME_D = { 150, 20, 44 }, DOME_L = { 252, 118, 140 },
  CAVITY = { 8, 20, 34 }, SCREEN = { 22, 70, 106 }, SCREEN_D = { 10, 36, 60 }, CYAN = { 110, 236, 255 },
  TRAY = { 84, 180, 222 }, TRAY_D = { 34, 104, 148 }, TRAY_HI = { 200, 244, 255 }, SOCKET = { 16, 58, 88 },
  PANEL = { 14, 24, 44 }, PANEL_D = { 6, 10, 22 },
  HP = { 92, 222, 120 }, HP_LOW = { 240, 184, 60 }, HP_BACK = { 40, 56, 80 },
  -- (the lighting: the counter warm and soft, the machine's neon blooming)
  LOOK_ROOM = { key = 0.1, vignette = 0.45, bloom = 0.22, warm = 0.6, contrast = 0.25, threshold = 0.9 },
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
  local function plant(cx, foot, s)
    local G = K.graphics()
    shadow(cx, foot, s * 0.42, s * 0.08, 0.35)
    K.grad(K.R(cx - s * 0.32, foot - s * 0.42, s * 0.64, s * 0.42), s * 0.08, C.POT, C.CRATE_D)
    for i = 0, 6 do
      local a = -pi * (0.08 + 0.14 * i)
      local lx, ly = cx + cos(a) * s * 0.42, foot - s * 0.44 + sin(a) * s * 0.46
      K.col(i % 2 == 0 and C.LEAF or C.LEAF_D)
      G.ellipse("fill", K.X(lx), K.Y(ly), s * 0.2 * K.sc, s * 0.12 * K.sc, 10)
    end
    K.col(C.LEAF)
    G.circle("fill", K.X(cx), K.Y(foot - s * 0.66), s * 0.17 * K.sc, 10)
    K.col(C.WHITE, 0.25)
    G.circle("fill", K.X(cx - s * 0.05), K.Y(foot - s * 0.72), s * 0.07 * K.sc, 8)
  end
  local function can(cx, foot, w, h, c, d)
    shadow(cx, foot, w * 0.62, w * 0.12, 0.35)
    K.grad(K.R(cx - w / 2, foot - h, w, h), w * 0.22, c, d)
    K.col(C.WHITE, 0.9)
    K.box("fill", K.R(cx - w / 2, foot - h * 0.62, w, h * 0.3))
    ball(cx, foot - h * 0.47, h * 0.11)
    K.col(c)
    K.box("fill", K.R(cx - w * 0.3, foot - h - h * 0.1, w * 0.6, h * 0.14), 0.4)
    -- (a glint down its left side)
    K.col(C.WHITE, 0.32)
    K.box("fill", K.R(cx - w * 0.36, foot - h * 0.95, w * 0.1, h * 0.85), w * 0.05)
  end
  local function jar(cx, foot, s)
    shadow(cx, foot, s * 0.6, s * 0.12, 0.35)
    for k = 0, 1 do
      local y = foot - s * (k + 1) * 0.92
      K.grad(K.R(cx - s * 0.48, y, s * 0.96, s * 0.86), s * 0.3, C.JAR, C.JAR_D)
      K.col(C.LID)
      K.box("fill", K.R(cx - s * 0.42, y - s * 0.08, s * 0.84, s * 0.16), 0.4)
      K.col(C.WHITE, 0.45)
      K.box("fill", K.R(cx - s * 0.32, y + s * 0.16, s * 0.1, s * 0.44), 0.3)
    end
  end
  local function crate(x, foot, w, h)
    shadow(x + w / 2, foot, w * 0.6, h * 0.1, 0.4)
    K.grad(K.R(x, foot - h, w, h), 0.8, C.CRATE, C.CRATE_D)
    K.col(C.CRATE_D)
    K.box("fill", K.R(x + w * 0.3, foot - h * 0.7, w * 0.4, h * 0.16), 0.6)
    K.col(C.WHITE, 0.7)
    K.box("fill", K.R(x + 0.4, foot - h + 0.3, w - 0.8, 0.5), 0.25)
  end
  -- a brick pillar: each brick its own shade with a lit top edge, the light falling off down it, darker
  -- beside the shelves (`toward` -1: the unit is on its left, 1: on its right)
  local function bricks(x, y, w, h, toward)
    K.col(C.MORTAR)
    K.box("fill", K.R(x, y, w, h))
    local rowH = 3.6
    local half = w / 2
    local r = 0
    while y + r * rowH < y + h do
      local ry = y + r * rowH
      local rh = min(rowH - 0.7, y + h - ry - 0.35)
      if rh <= 0 then break end
      local off = (r % 2) * half * 0.5
      for c = -1, 2 do
        local bx0 = x + off + c * half
        local l, rr = max(x, bx0 + 0.35), min(x + w, bx0 + half - 0.35)
        if rr > l then
          local k = (r * 7 + c * 3) % 3
          K.col(k == 0 and C.BRICK_B or (k == 1 and C.BRICK or C.BRICK_C))
          K.box("fill", K.R(l, ry + 0.35, rr - l, rh), 0.3)
          K.col(C.BRICK_HI, 0.22)
          K.box("fill", K.R(l, ry + 0.35, rr - l, 0.45))
        end
      end
      r = r + 1
    end
    -- (the light falling off down it; the shadow beside the unit)
    K.grad(K.R(x, y, w, h), 0, C.SHADE_CLEAR, C.SHADE_DARK)
    for i = 1, 3 do
      K.col(C.BLACK, 0.1)
      local sw = 1.2 * i
      K.box("fill", K.R(toward < 0 and x or (x + w - sw), y, sw, h))
    end
  end

  -- a brick wall across a whole width: bricks of one size, every other row set over by half of one
  local BRICK_W, BRICK_H = 11, 4.6
  local function brickWall(x, y, w, h)
    K.col(C.MORTAR)
    K.box("fill", K.R(x, y, w, h))
    local r = 0
    while y + r * BRICK_H < y + h do
      local ry = y + r * BRICK_H
      local rh = min(BRICK_H - 0.7, y + h - ry - 0.35)
      if rh <= 0 then break end
      local off = (r % 2) * BRICK_W * 0.5
      local c = -1
      while x + off + c * BRICK_W < x + w do
        local bx0 = x + off + c * BRICK_W
        local l, rr = max(x, bx0 + 0.35), min(x + w, bx0 + BRICK_W - 0.35)
        if rr > l then
          local k = (r * 7 + c * 3) % 3
          K.col(k == 0 and C.BRICK_B or (k == 1 and C.BRICK or C.BRICK_C))
          K.box("fill", K.R(l, ry + 0.35, rr - l, rh))
          K.col(C.BRICK_HI, 0.2)
          K.box("fill", K.R(l, ry + 0.35, rr - l, 0.45))
        end
        c = c + 1
      end
      r = r + 1
    end
  end

  -- ------- the healing items (drawn smooth after the games' designs, `s` tall)
  -- a spray bottle (the Potions, Full Restore, Antidote): its body in its colour, a white label with a
  -- stripe of it and a red cross, the shoulder, the dark collar, the trigger head with its nozzle and
  -- trigger, a glint
  local function spray(cx, foot, s, c, d)
    local G = K.graphics()
    shadow(cx, foot, s * 0.36, s * 0.07, 0.4)
    local bw = s * 0.56
    K.grad(K.R(cx - bw / 2, foot - s * 0.6, bw, s * 0.6), s * 0.12, c, d)
    K.col(C.WHITE, 0.95)
    K.box("fill", K.R(cx - bw / 2, foot - s * 0.44, bw, s * 0.2))
    K.col(c)
    K.box("fill", K.R(cx - bw / 2, foot - s * 0.27, bw, s * 0.03))
    K.col(C.BALL_RED)
    K.box("fill", K.R(cx - s * 0.03, foot - s * 0.42, s * 0.06, s * 0.13))
    K.box("fill", K.R(cx - s * 0.065, foot - s * 0.385, s * 0.13, s * 0.06))
    K.grad(K.R(cx - bw * 0.38, foot - s * 0.7, bw * 0.76, s * 0.13), s * 0.06, K.light(c, 0.25), c)
    K.col(C.HEAD_D)
    K.box("fill", K.R(cx - s * 0.1, foot - s * 0.77, s * 0.2, s * 0.08))
    K.grad(K.R(cx - s * 0.17, foot - s * 0.95, s * 0.3, s * 0.18), s * 0.05, C.HEAD, C.HEAD_D)
    K.col(C.HEAD_HI, 0.6)
    K.box("fill", K.R(cx - s * 0.15, foot - s * 0.94, s * 0.24, s * 0.03), s * 0.015)
    K.col(C.HEAD_D)
    K.box("fill", K.R(cx + s * 0.12, foot - s * 0.91, s * 0.11, s * 0.055), s * 0.02)
    G.polygon("fill", K.X(cx + s * 0.04), K.Y(foot - s * 0.78), K.X(cx + s * 0.13), K.Y(foot - s * 0.78),
      K.X(cx + s * 0.1), K.Y(foot - s * 0.66))
    K.col(C.WHITE, 0.38)
    K.box("fill", K.R(cx - bw * 0.4, foot - s * 0.58, bw * 0.13, s * 0.5), s * 0.05)
  end
  -- a Revive: a four-pointed yellow crystal, its faces lit from the top left, a sparkle (`big`: a Max Revive)
  local function revive(cx, foot, s, big)
    local G = K.graphics()
    local r = s * (big and 0.42 or 0.32)
    local cy = foot - r * 1.15
    shadow(cx, foot, r * 0.8, r * 0.16, 0.38)
    local X, Y, S = K.X(cx), K.Y(cy), K.sc
    local t, rr = r * S * 1.15, r * S
    K.col(C.GEM_D)
    G.polygon("fill", X, Y - t, X + rr, Y, X, Y + t, X - rr, Y)
    K.col(C.GEM)
    G.polygon("fill", X, Y - t, X, Y + t, X - rr, Y)
    K.col(C.GEM_HI)
    G.polygon("fill", X, Y - t, X - rr * 0.5, Y - t * 0.05, X - rr * 0.06, Y)
    K.col(C.GEM_D, 0.6)
    G.polygon("fill", X, Y + t, X + rr, Y, X + rr * 0.35, Y + t * 0.12)
    if big then
      K.col(C.WHITE, 0.85)
      G.polygon("fill", X, Y - t * 0.45, X + rr * 0.2, Y, X, Y + t * 0.45, X - rr * 0.2, Y)
    end
    K.glow(cx - r * 0.3, cy - r * 0.55, r * 0.5, r * 0.5, C.WHITE, 0.5)
  end
  -- an Ether: a round flask of blue, its neck, a cork, the glass's glint
  local function ether(cx, foot, s)
    local G = K.graphics()
    local r = s * 0.3
    local cy = foot - r
    shadow(cx, foot, r * 1.05, r * 0.2, 0.4)
    K.col(C.WHITE, 0.55)
    K.box("fill", K.R(cx - r * 0.25, cy - r * 1.75, r * 0.5, r * 0.9), r * 0.12)
    K.col(C.CORK)
    K.box("fill", K.R(cx - r * 0.3, cy - r * 2.05, r * 0.6, r * 0.38), r * 0.1)
    K.col(C.ETHER_D)
    G.circle("fill", K.X(cx), K.Y(cy), r * K.sc, 28)
    K.col(C.ETHER)
    G.circle("fill", K.X(cx - r * 0.08), K.Y(cy - r * 0.08), r * 0.86 * K.sc, 28)
    shade(cx, cy, r, 0.35)
  end

  -- what each shelf holds (along it, 0..1; her middle hides the middle)
  local function stock(i, x, foot, w, bay)
    local s = min(bay * 0.88, 18)
    if i == 1 then
      plant(x + w * 0.1, foot, s * 0.75)
      shadow(x + w * 0.26, foot, s * 0.28, s * 0.06, 0.35)
      ball(x + w * 0.26, foot - s * 0.27, s * 0.27)
      shadow(x + w * 0.36, foot, s * 0.28, s * 0.06, 0.35)
      ball(x + w * 0.36, foot - s * 0.27, s * 0.27, nil, nil, C.GREAT)
      revive(x + w * 0.74, foot, s)
      revive(x + w * 0.88, foot, s, true)
    elseif i == 2 then
      spray(x + w * 0.09, foot, s, C.POTION, C.POTION_D)
      spray(x + w * 0.2, foot, s, C.SUPER, C.SUPER_D)
      spray(x + w * 0.31, foot, s, C.ANTIDOTE, C.ANTIDOTE_D)
      spray(x + w * 0.69, foot, s, C.HYPER, C.HYPER_D)
      spray(x + w * 0.8, foot, s, C.MAXP, C.MAXP_D)
      spray(x + w * 0.91, foot, s, C.RESTORE, C.RESTORE_D)
    else
      crate(x + w * 0.05, foot, s * 0.85, s * 0.62)
      crate(x + w * 0.18, foot, s * 0.85, s * 0.62)
      ether(x + w * 0.7, foot, s)
      ether(x + w * 0.8, foot, s)
      jar(x + w * 0.91, foot, s * 0.42)
    end
  end

  -- the wall (its wainscot), ceiling light, the shelf unit between its pillars
  local function drawRoom(b, cx, counterY, clock)
    local x, y, w, h = b[1], b[2], b[3], b[4]
    K.grad(K.R(x, y, w, h), 0, C.WALL_TOP, C.WALL_FOOT)
    local wy = counterY - h * 0.2
    K.grad(K.R(x, wy, w, counterY - wy + 1), 0, C.WAIN_TOP, C.WAIN_FOOT)
    K.col(C.MOLD)
    K.box("fill", K.R(x, wy - 1.2, w, 1.4))
    K.col(C.BLACK, 0.12)
    K.box("fill", K.R(x, wy + 0.2, w, 0.8))
    local uw = min(w * 0.64, h * 1.3)
    local ux, uy = cx - uw / 2, y + h * 0.03
    local uh = counterY - uy + 2
    local pw = uw * 0.14
    -- (ceiling light: a pool over the unit, a spot on each pillar)
    K.glow(cx, y, uw * 0.7, h * 0.4, C.LAMP, 0.26 + 0.02 * sin(clock * 0.7))
    bricks(ux - pw, y, pw, counterY - y + 2, 1)
    bricks(ux + uw, y, pw, counterY - y + 2, -1)
    K.glow(ux - pw / 2, y + 4, pw * 0.9, h * 0.22, C.LAMP, 0.16)
    K.glow(ux + uw + pw / 2, y + 4, pw * 0.9, h * 0.22, C.LAMP, 0.16)
    -- (the unit: its frame bevelled, its back lit from above and shadowed under each board)
    shadow(cx, uy + uh / 2, uw * 0.58, uh * 0.56, 0.18)
    K.col(C.FRAME)
    K.box("fill", K.R(ux, uy, uw, uh), 0.6)
    K.col(C.FRAME_HI)
    K.box("fill", K.R(ux, uy, uw, 0.5))
    K.box("fill", K.R(ux, uy, 0.5, uh))
    K.col(C.FRAME_LO)
    K.box("fill", K.R(ux + uw - 0.5, uy, 0.5, uh))
    local ix, iw = ux + 2, uw - 4
    K.grad(K.R(ix, uy + 2, iw, uh - 2), 0, C.BACK_TOP, C.BACK_FOOT)
    local bay = (uh - 2) / 3
    for i = 1, 3 do
      local top = uy + 2 + bay * (i - 1)
      local foot = top + bay - 2.2
      -- (the board above's shadow on the back, a warm strip of light under it)
      K.grad(K.R(ix, top, iw, min(bay * 0.35, 5)), 0, C.AO_DARK, C.AO_CLEAR)
      K.glow(ix + iw * 0.5, top + 1.2, iw * 0.46, 2.6, C.LED, 0.35)
      K.glow(ix + iw * 0.5, foot - bay * 0.5, iw * 0.42, bay * 0.45, C.WHITE, 0.18)
      stock(i, ix, foot, iw, bay)
      -- (the board: its top, its front edge)
      K.col(C.BOARD_TOP)
      K.box("fill", K.R(ix - 1, foot - 0.4, iw + 2, 1))
      K.col(C.BOARD)
      K.box("fill", K.R(ix - 1, foot + 0.6, iw + 2, 1.8))
      K.col(C.WHITE, 0.18)
      K.box("fill", K.R(ix - 1, foot + 0.6, iw + 2, 0.35))
    end
  end

  -- the nurse: her sheet's frame for the way she faces, at whole pixels, a soft light round her head;
  -- a nod while she talks, a bow; walking (st.walk: to the machine and back) her sheet's four steps in
  -- turn, a little bounce with each, gliding along
  local STEP = 0.12
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
        lift = floor(abs(sin(since / STEP * pi)) * 1.6 + 0.5) * px
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

  -- the sign on the counter's front: a lit box, its frame, the Pokémon Center's ball (big) and its name
  local function drawSign(cx, y, maxW, h)
    local G = K.graphics()
    local name = T("nurse.title")
    local fs = 7.4
    local r = h * 0.4
    local tw = K.width(name, fs)
    local w = min(maxW, r * 2 + tw + h * 1.1)
    fs = K.fit(name, fs, w - r * 2 - h * 0.9)
    tw = K.width(name, fs)
    local sb = K.R(cx - w / 2, y, w, h)
    K.glow(cx, y + h / 2, w * 0.66, h * 1.1, C.SIGN_GLOW, 0.32)
    K.shadow(sb, 5, 1.6, 0.35)
    K.col(C.SIGN_FRAME)
    K.box("fill", sb, 5)
    local face = K.R(sb[1] + 1.4, sb[2] + 1.4, sb[3] - 2.8, sb[4] - 2.8)
    K.grad(face, 4, C.SIGN_TOP, C.SIGN_FOOT)
    K.glow(face[1] + face[3] / 2, face[2] + face[4] * 0.35, face[3] * 0.5, face[4] * 0.6, C.WHITE, 0.4)
    K.ring(face, 4, C.WHITE, 0.9, 0.5)
    -- (the ball, in a white ring, and the name beside it)
    local bx = face[1] + h * 0.5 + 0.2
    local by = face[2] + face[4] / 2
    K.col(C.WHITE)
    G.circle("fill", K.X(bx), K.Y(by), (r + 1.1) * K.sc, 32)
    ball(bx, by, r)
    local gx = bx + r + 2.6
    K.bold(name, gx, by - fs * 0.62 * K.textScale(), fs, C.SIGN_INK, "center", face[1] + face[3] - gx - 2)
    -- (a sheen across the glass)
    K.col(C.WHITE, 0.22)
    K.box("fill", K.R(face[1] + 2, face[2] + 0.8, face[3] - 4, face[4] * 0.32), 3)
  end

  -- the counter she stands behind: its glossy top, its red front, the sign on it
  local function drawCounter(x, y, w, h, cx)
    shadow(cx, y + 0.6, 22, 2.4, 0.3)
    K.grad(K.R(x, y + 4.6, w, h - 4.6), 0, C.COUNTER_TOP, C.COUNTER_FOOT)
    K.col(C.WHITE, 0.1)
    K.box("fill", K.R(x, y + 9, w, 3))
    K.grad(K.R(x, y, w, 4.6), 0, C.SLAB_TOP, C.SLAB_FOOT)
    K.col(C.WHITE, 0.85)
    K.box("fill", K.R(x, y + 0.5, w, 0.6))
    K.col(C.LIP)
    K.box("fill", K.R(x, y + 4.4, w, 0.8))
    K.col(C.BLACK, 0.18)
    K.box("fill", K.R(x, y + 5.2, w, 1.4))
    drawSign(cx, y + 8, min(w - 24, 160), 22)
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
  -- (a four-cornered shape: back left, back right, front right, front left; units)
  local function quad(x1, y1, x2, y2, x3, y3, x4, y4)
    K.graphics().polygon("fill", K.X(x1), K.Y(y1), K.X(x2), K.Y(y2), K.X(x3), K.Y(y3), K.X(x4), K.Y(y4))
  end
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
    -- (the room: the brick wall right behind it, in the dim light, lit by the machine and shadowed by its
    -- hood; the table it stands on meeting the wall just behind its base, glossy, the counter's red edge
    -- along the foot)
    local hz = ft - depth - R * 0.03
    brickWall(x, y, w, hz - y + 0.5)
    K.grad(K.R(x, y, w, hz - y + 0.5), 0, C.WALL_DIM_TOP, C.WALL_DIM_FOOT)
    shadow(cx + R * 0.1, hz - R * 0.42, R * 1.12, R * 0.78, 0.42)
    K.glow(cx, hz - R * 0.1, R * 1.9, R * 0.8, C.DOME_L, 0.18 + 0.16 * g)
    K.glow(cx, hz - R * 0.5, R * 1.4, R * 0.9, C.CYAN, 0.06 + 0.26 * g)
    local te = y + h * 0.94
    K.grad(K.R(x, hz, w, te - hz), 0, C.TABLE_FAR, C.TABLE_NEAR)
    K.grad(K.R(x, hz, w, 2.5), 0, C.AO_DARK, C.AO_CLEAR)
    K.col(C.WHITE, 0.55)
    K.box("fill", K.R(x, te - 1.1, w, 0.5))
    K.grad(K.R(x, te, w, y + h - te), 0, C.COUNTER_TOP, C.COUNTER_FOOT)
    K.col(C.LIP)
    K.box("fill", K.R(x, te, w, 0.5))
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
      drawRoom(b, cx, counterY, clock)
      drawNurse(cx, foot, hU, clock)
      drawCounter(x, counterY, w, y + h - counterY, cx)
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
        -- (beside her, over the shelves, the counter's sign clear; upright, above the words: there's room)
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
        drawMenu(mx, above and (by - mh - 5) or min(by - mh - 5, counterY - mh - 3), mw, clock)
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
