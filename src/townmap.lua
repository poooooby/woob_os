-- The Town Map in 3D: the game's own region map (the Town Map item, the wall maps, Fly from the
-- party menu) replaced by the 3D map (src/map3d/scene.lua) over the whole window. A third host,
-- next to the desktop and the watch (src/shell.lua pushes its layer and routes the hooks to it);
-- the game's own screen stays a button away (START: the classic map), and Settings can keep it.
--
--   Tm = TownMap(deps)   deps: kit, T, env (with map3d), scene (src/map3d/scene.lua's maker), se, log
--   Tm.open(ctx, opts) -> true (opts: the scene's { mode = "town" | "fly", pick, classic } and
--                        cancel(), B on the map) ; Tm.close() ; Tm.isOpen() ; Tm.state()
--   Tm.draw(G, vp) ; Tm.input(input) ; Tm.pointer(ev) -> true ; Tm.wheel(dy) -> true

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

return function(deps)
  local K, T = deps.kit, deps.T
  local Tm = {}
  -- (any shape: the map fills the window; the hints along its foot)
  Tm.PAGE = { height = 160, minWidth = 200, maxWidth = 400, portraitWidth = 160, portraitHeight = 260,
              portraitAspect = 0.9 }
  Tm.REPEAT_START, Tm.REPEAT_EVERY = 20, 4
  Tm.FOOT = 14
  local repeated = K.repeater(Tm.REPEAT_START, Tm.REPEAT_EVERY)
  local INK, KEY = { 255, 255, 255 }, { 36, 36, 40 }

  local r = nil
  local function now() return love and love.timer and love.timer.getTime() or 0 end
  local function log(fmt, ...) if deps.log then deps.log(fmt, ...) end end

  function Tm.isOpen() return r ~= nil end
  function Tm.state() return r end

  function Tm.open(ctx, opts)
    ctx.app = "map"
    -- (the map's card keeps clear of the hints' glass along the foot)
    opts.footer = Tm.FOOT
    local ok, w = pcall(deps.scene, ctx, deps.env, opts)
    if not (ok and type(w) == "table") then
      log("the 3D map failed to open: %s", tostring(w))
      return false
    end
    r = { ctx = ctx, opts = opts, win = w, held = {}, touch = {}, t0 = now(), body = {} }
    -- (the A that chose the Town Map / Fly is still down: waited out)
    r.waitRelease = true
    return true
  end
  function Tm.close()
    local w = r and r.win
    r = nil
    if w and w.close then pcall(w.close) end
  end

  local cur
  local NAV = {}
  function Tm.input(input)
    if not (r and input) then return end
    cur = input
    if r.waitRelease then
      local okD, down = pcall(input.isDown, input, "a")
      if input:wasPressed("a") or (okD and down) then return end
      r.waitRelease = false
    end
    local held = r.held
    NAV.up, NAV.down = repeated(input, "up", held), repeated(input, "down", held)
    NAV.left, NAV.right = repeated(input, "left", held), repeated(input, "right", held)
    local w = r.win
    local ok, used = pcall(w.input, input, NAV)
    if not ok then log("the 3D map's input failed: %s", tostring(used)) end
    if ok and not used and input:wasPressed("b") and r then
      local opts = r.opts
      if deps.se then deps.se("SE_SELECT") end
      if opts.cancel then opts.cancel() end
    end
  end

  local function hitAt(x, y)
    local hits = K.hits
    for i = #hits, 1, -1 do
      local h = hits[i]
      if K.inside(h, x, y) then return h end
    end
  end
  local function units(x, y) return (x - K.ox) / K.sc, (y - K.oy) / K.sc end

  -- every finger to the map (it turns, tilts and pinches); a still one's release is a tap
  function Tm.pointer(ev)
    if not (r and type(ev) == "table") then return true end
    local x, y, id = tonumber(ev.x) or 0, tonumber(ev.y) or 0, ev.id or 1
    local w = r.win
    local ux, uy = units(x, y)
    if ev.phase == "pressed" then
      r.touch[id] = { x = x, y = y }
      pcall(w.pointer, "pressed", ux, uy, id)
    elseif ev.phase == "moved" then
      local t = r.touch[id]
      if t and (abs(x - t.x) > 4 * K.sc or abs(y - t.y) > 4 * K.sc) then t.drag = true end
      pcall(w.pointer, "moved", ux, uy, id)
    elseif ev.phase == "released" or ev.phase == "cancelled" then
      local t = r.touch[id]
      r.touch[id] = nil
      local ok, used = pcall(w.pointer, ev.phase, ux, uy, id)
      if ev.phase == "released" and t and not t.drag and not (ok and used) then
        local h = hitAt(x, y)
        if h and h.kind == "win" and w.tap then
          local okT, err = pcall(w.tap, h.arg, x, y)
          if not okT then log("the 3D map's tap failed: %s", tostring(err)) end
        end
      end
    end
    return true
  end
  function Tm.wheel(dy)
    if r and r.win.scroll then pcall(r.win.scroll, dy * 10) end
    return true
  end

  function Tm.draw(G, vp)
    if not r then return end
    local clock = now()
    local pw, ph = K.frame(G, vp, Tm.PAGE, clock - r.t0)
    G.setColor(0, 0, 0, 1)
    G.rectangle("fill", 0, 0, K.ww, K.wh)
    local b = r.body
    b[1], b[2], b[3], b[4] = 0, 0, pw, ph
    local w = r.win
    local ok, err = pcall(w.draw, b, clock, pw < ph)
    if not ok then log("the 3D map's draw failed: %s", tostring(err)) end
    -- (the hints in a glass capsule floating along the foot)
    local okH, hints = pcall(w.hints)
    if okH and hints then
      local hb = K.R(3, ph - Tm.FOOT + 1, pw - 6, Tm.FOOT - 4)
      if w.glass then pcall(w.glass, hb, hb[4] / 2) end
      K.hints(hints, K.R(hb[1] + 3, hb[2] + 1, hb[3] - 6, 8), KEY, true, INK, INK)
    end
    K.scissor()
  end

  return Tm
end
