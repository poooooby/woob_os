-- The PC Games window: that mod's screen (src/pcgames.lua), as it looks on its own: drawn at 240 x 160
-- into a picture and shown at a whole number of screen pixels, so it stays crisp, in a frame of the
-- dock's glass over the wallpaper, across the whole monitor (win.fullscreen). The buttons pass straight
-- through. A close button shows for a moment when the mouse moves or the screen is touched.
--
--   window(ctx, env) -> win (src/apps.lua)   env.pcgames

local floor, max, min = math.floor, math.max, math.min

local BLACK, WHITE, RED = { 0, 0, 0 }, { 255, 255, 255 }, { 255, 95, 87 }
local SHOW, FADE = 2.5, 0.3     -- seconds the close button stays, and fades
local BEZEL, RADIUS = 2.6, 4     -- the glass frame round the picture, units
local HINTS = { { "B", "hint.back" } }
local canvas

return function(ctx, env)
  local K, H, T = env.K, env.pcgames, env.T
  local W = { title = "PC Games", fullscreen = true }
  local st = { ok = H.open(), live = false, last = nil, touched = -100 }
  W.state = st

  local function finish()
    if ctx.closeWindow then ctx.closeWindow() end
  end

  function W.input(input)
    st.live = true
    if H.input(input) then finish() end
    return true
  end

  function W.hints() return T.list(HINTS) end

  -- (any movement or touch brings the close button; a tap on it goes through as usual)
  function W.pointer()
    if env.now then st.touched = env.now() end
    return false
  end

  -- the mod's screen into the picture (no tables made here)
  local function picture()
    local g = K.graphics()
    if not (g.newCanvas and g.setCanvas) then return nil end
    if canvas == nil then
      local ok, c = pcall(g.newCanvas, 240, 160, { dpiscale = 1 })
      canvas = ok and c or false
      if canvas then canvas:setFilter("nearest", "nearest") end
    end
    if not canvas then return nil end
    local target = g.getCanvas()
    g.push("all")
    g.setCanvas(canvas)
    g.origin()
    g.setShader()
    g.setScissor()
    g.setBlendMode("alpha")
    g.clear(0, 0, 0, 1)
    H.draw()
    -- (back on the screen before the pop: restored with the picture still the target, the window's
    -- clip would be worked out for the picture and cut the wrong part of the screen)
    g.setCanvas(target)
    g.pop()
    return canvas
  end

  function W.draw(body, clock)
    if not st.ok then return finish() end
    local t = env.now and env.now() or clock
    if st.live and st.last then
      if H.tick(min(0.1, t - st.last)) == "closed" then return finish() end
    end
    st.last, st.live = t, false

    local x, y, w, h = body[1], body[2], body[3], body[4]
    local g = K.graphics()
    local img = picture()
    if img then
      -- (whole screen pixels only, leaving room for the frame)
      local k = max(1, floor(min((w - BEZEL * 2) * K.sc / 240, (h - BEZEL * 2) * K.sc / 160)))
      local sw, sh = 240 * k / K.sc, 160 * k / K.sc
      local sx, sy = x + (w - sw) / 2, y + (h - sh) / 2
      -- (the dock's glass)
      local frame = K.R(sx - BEZEL, sy - BEZEL, sw + BEZEL * 2, sh + BEZEL * 2)
      K.shadow(frame, RADIUS, 1, 0.3)
      K.col(WHITE, 0.26)
      K.box("fill", frame, RADIUS)
      K.ring(frame, RADIUS, WHITE, 0.4, 0.5)
      g.setColor(1, 1, 1, 1)
      g.setBlendMode("alpha", "premultiplied")
      g.draw(img, floor(K.X(sx) + 0.5), floor(K.Y(sy) + 0.5), 0, k, k)
      g.setBlendMode("alpha")
    end

    -- the close button, in the corner the window's own would be
    local since = t - st.touched
    if since >= 0 and since < SHOW then
      local a = min(1, (SHOW - since) / FADE)
      local cx, cy, r = x + 7, y + 7, 3.4
      K.col(BLACK, 0.55 * a)
      g.circle("fill", K.X(cx), K.Y(cy), (r + 1.4) * K.sc)
      K.col(RED, a)
      g.circle("fill", K.X(cx), K.Y(cy), r * K.sc)
      K.col(WHITE, a)
      g.setLineWidth(max(1, 0.6 * K.sc))
      local d = 1.4
      g.line(K.X(cx - d), K.Y(cy - d), K.X(cx + d), K.Y(cy + d))
      g.line(K.X(cx - d), K.Y(cy + d), K.X(cx + d), K.Y(cy - d))
      K.addHit(K.R(x, y, 14, 14), "winclose")
    end
  end

  return W
end
