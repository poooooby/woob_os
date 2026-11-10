-- The Kanto Gear apps' own screen, apart from the PC and WoobPad: a second full-screen host (a
-- src/townmap.lua of its own, keeping its own hits) drawn into a canvas, with no layer on the game's
-- stack. The game keeps running above it, and physical buttons stay with the game: this is touch and
-- mouse only, as the Gear's own apps are.
--   - a separate display (the engine's SecondScreen: Android's or the desktop companion window): the
--     canvas is sent there, the game keeps the whole window
--   - otherwise, under the game in the window: where the Gear's own combined layout was just before it
--     stood down, or the bottom half
--
--   Gp = GearPanel(deps)   deps: host (src/townmap.lua's, with keepHits) ; kit ; bridge() -> SecondScreen | nil ; log
--   Gp.open(ctx, opts) -> true ; Gp.reopen(ctx, opts) ; Gp.close() ; Gp.isOpen() ; Gp.app() ; Gp.mode() ->
--   "external" | "stacked" | nil ; Gp.bridge (a test swaps it)
--   Gp.viewport(nxt, ctx) (render.viewport) ; Gp.frame() (render.hud) ; Gp.window(nxt, game, ctx)
--   (render.window) ; Gp.pointer(ev) -> true when it took it ; Gp.wheel(dy) -> true

local floor, abs = math.floor, math.abs

return function(deps)
  local host = deps.host
  local Gp = { bridge = deps.bridge }
  -- (a separate display's picture. The engine can't ask a display its size, and a picture is fitted
  -- whole, so bars fill whatever shape differs: this is the shape of the dual-screen handhelds' lower
  -- screen, the Ayn Thor's 1240 x 1080, with a page laid out for it)
  local EXT_W, EXT_H, EXT_EVERY = 744, 648, 1 / 30
  local EXT_PAGE = { height = 192, minWidth = 220, maxWidth = 400, portraitWidth = 160, portraitHeight = 260,
                     portraitAspect = 0.9 }
  local WINDOW_PAGE = host.PAGE

  local seen = nil                 -- the Gear's own layout, as fractions of the window, while it was up
  local ext = nil                  -- the bridge, while it has a display
  local game = { x = 0, y = 0, width = 1, height = 1 }
  local panel = { x = 0, y = 0, width = 1, height = 1 }
  local canvas, canvasW, canvasH
  local pushedAt = -1
  local held = {}
  local VP = { width = 1, height = 1, noSafeArea = true }
  local EXACT = { dpiscale = 1 }
  local EV = { id = 1, phase = "pressed", x = 0, y = 0 }
  local extX, extY = 0, 0

  local function log(fmt, ...) if deps.log then deps.log(fmt, ...) end end
  local function clock() return love and love.timer and love.timer.getTime() or 0 end

  function Gp.isOpen() return host.isOpen() end
  function Gp.app()
    local st = host.state()
    return st and st.ctx.app or nil
  end
  function Gp.hostState() return host.state() end
  function Gp.mode()
    if not host.isOpen() then return nil end
    return ext and "external" or "stacked"
  end
  local function reset()
    ext, pushedAt = nil, -1
    for id in pairs(held) do held[id] = nil end
  end
  function Gp.open(ctx, opts)
    reset()
    return host.open(ctx, opts)
  end
  function Gp.reopen(ctx, opts)
    host.close()
    if not host.open(ctx, opts) then
      log("the Gear's %s couldn't come back", tostring(ctx.app))
      return false
    end
    return true
  end
  function Gp.close()
    host.close()
    reset()
    if canvas and canvas.release then canvas:release() end
    canvas, canvasW, canvasH = nil, nil, nil
  end

  local function display()
    local b = Gp.bridge and Gp.bridge()
    if not (b and b.available) then return nil end
    local ok, up = pcall(b.available)
    return ok and up and b or nil
  end

  -- the game's rectangle, and the panel in the largest side left over
  local function layout(ctx)
    local w, h = ctx.width, ctx.height
    if seen then
      game.x, game.y, game.width, game.height = floor(seen[1] * w), floor(seen[2] * h), floor(seen[3] * w), floor(seen[4] * h)
    else
      game.x, game.y, game.width, game.height = 0, 0, w, floor(h / 2)
    end
    local below, above, right, left = h - game.y - game.height, game.y, w - game.x - game.width, game.x
    local most = math.max(below * w, above * w, right * h, left * h)
    if below * w == most then panel.x, panel.y, panel.width, panel.height = 0, game.y + game.height, w, below
    elseif above * w == most then panel.x, panel.y, panel.width, panel.height = 0, 0, w, above
    elseif right * h == most then panel.x, panel.y, panel.width, panel.height = game.x + game.width, 0, right, h
    else panel.x, panel.y, panel.width, panel.height = 0, 0, left, h end
  end

  function Gp.viewport(nxt, ctx)
    if not host.isOpen() then
      local rect = nxt(ctx)
      if type(rect) == "table" and (rect.width < ctx.width or rect.height < ctx.height) then
        seen = seen or {}
        seen[1], seen[2], seen[3], seen[4] = rect.x / ctx.width, rect.y / ctx.height, rect.width / ctx.width, rect.height / ctx.height
      else
        seen = nil
      end
      return rect
    end
    ext = not seen and display() or nil
    if ext then return nxt(ctx) end
    layout(ctx)
    return game
  end

  local function feed(phase, x, y)
    EV.id, EV.phase, EV.x, EV.y = "gear", phase, x, y
    host.pointer(EV)
  end
  -- (a separate display's taps, in the picture's own pixels. The desktop's companion sends only presses
  -- and releases: a release somewhere else counts as a drag there, so lists still scroll)
  local function pollTouches()
    for _ = 1, 32 do
      local ok, event = pcall(ext.pollTouch)
      if not (ok and type(event) == "string") then return end
      local action, sx, sy = event:match("^(%a+),(-?%d+),(-?%d+)$")
      local x, y = tonumber(sx) or 0, tonumber(sy) or 0
      if action == "down" then
        extX, extY = x, y
        feed("pressed", x, y)
      elseif action == "move" then
        extX, extY = x, y
        feed("moved", x, y)
      elseif action == "up" then
        if abs(x - extX) > 0 or abs(y - extY) > 0 then feed("moved", x, y) end
        feed("released", x, y)
      elseif action == "cancel" then
        feed("cancelled", extX, extY)
      end
      if not host.isOpen() then return end
    end
  end

  local canvasExact = false
  local function canvasOf(G, w, h, exact)
    if canvas and canvasW == w and canvasH == h and canvasExact == exact then return canvas end
    if canvas and canvas.release then canvas:release() end
    if G.newCanvas then
      if exact then canvas = G.newCanvas(w, h, EXACT) else canvas = G.newCanvas(w, h) end
    else
      canvas = nil
    end
    canvasW, canvasH, canvasExact = w, h, exact
    return canvas
  end

  function Gp.frame()
    if not host.isOpen() then return end
    local G = love and love.graphics
    if not G then return end
    local w, h = panel.width, panel.height
    if ext then
      pollTouches()
      if not host.isOpen() then return end
      local t = clock()
      if t - pushedAt < EXT_EVERY and t >= pushedAt then return end
      pushedAt = t
      w, h = EXT_W, EXT_H
    end
    if w < 1 or h < 1 then return end
    -- (a separate display reads rows of exact pixels, and Android is always high-DPI, where a plain
    -- canvas holds more pixels than its size: so this one is one pixel a unit, with fonts to match)
    local exact = ext ~= nil
    local c = canvasOf(G, w, h, exact)
    local target = c and G.getCanvas()
    G.push("all")
    G.origin()
    G.setScissor()
    G.setShader()
    G.setBlendMode("alpha")
    if c then
      G.setCanvas(c)
      G.clear(0, 0, 0, 1)
    end
    VP.width, VP.height = w, h
    host.PAGE = exact and EXT_PAGE or WINDOW_PAGE
    if deps.kit then deps.kit.exactFonts(exact) end
    local ok, err = pcall(host.draw, G, VP)
    if deps.kit then deps.kit.exactFonts(false) end
    if c then G.setCanvas(target) end
    G.pop()
    if not ok then log("the Gear's screen failed to draw: %s", tostring(err)) end
    if ext and c and c.newImageData then
      local data = c:newImageData()
      local pw, ph = w, h
      if data and data.getDimensions then pw, ph = data:getDimensions() end
      local okP, errP = pcall(ext.push, data, pw, ph, 0, "secondary")
      if not okP then log("the second screen failed: %s", tostring(errP)) end
      if data and data.release then data:release() end
    end
  end

  function Gp.window(nxt, gm, ctx)
    nxt(gm, ctx)
    if not (host.isOpen() and not ext and canvas) then return end
    local G = love.graphics
    G.setColor(1, 1, 1, 1)
    G.setBlendMode("alpha", "premultiplied")
    G.draw(canvas, panel.x, panel.y)
    G.setBlendMode("alpha")
  end

  -- a press in the panel is ours until it's let go; everything else is the game's
  function Gp.pointer(ev)
    if not (host.isOpen() and not ext and type(ev) == "table") then return false end
    local id = ev.id or 1
    local x, y = (tonumber(ev.x) or 0) - panel.x, (tonumber(ev.y) or 0) - panel.y
    if ev.phase == "pressed" then
      if x < 0 or y < 0 or x >= panel.width or y >= panel.height then return false end
      held[id] = true
    elseif not held[id] then
      return false
    elseif ev.phase == "released" or ev.phase == "cancelled" then
      held[id] = nil
    end
    EV.id, EV.phase, EV.x, EV.y = id, ev.phase, x, y
    host.pointer(EV)
    return true
  end

  function Gp.wheel(dy)
    if not (host.isOpen() and not ext and love and love.mouse) then return false end
    local mx, my = love.mouse.getPosition()
    if mx < panel.x or my < panel.y or mx >= panel.x + panel.width or my >= panel.y + panel.height then return false end
    host.wheel(dy)
    return true
  end

  return Gp
end
