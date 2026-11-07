-- The full-screen host: a third host, next to the desktop and WoobPad (src/shell.lua pushes its
-- layer and routes the hooks to it), for the game's own screens WoobOS takes over:
--   - the Town Map in 3D: the game's region map (the Town Map item, the wall maps, Fly from the
--     party menu) replaced by the 3D map (src/map3d/scene.lua) over the whole window; the game's
--     own screen a button away (START: the classic map), and Settings can keep it
--   - the PokéNav's Phone and Condition (src/pokenav.lua): an app's window (`opts.maker`) under a
--     toolbar with "< PokéNav" (`opts.chrome`)
--
--   Tm = TownMap(deps)   deps: kit, T, env (with map3d), scene (src/map3d/scene.lua's maker), se, log
--   Tm.open(ctx, opts) -> true (opts: the scene's { mode = "town" | "fly", pick, classic }, or maker
--                        (window(ctx, env)), app, chrome; cancel(): B, or "< PokéNav") ; Tm.close() ;
--                        Tm.isOpen() ; Tm.state()
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
  local INK, KEY, BAR = { 255, 255, 255 }, { 36, 36, 40 }, { 28, 28, 32 }
  local TOOL = 13

  local r = nil
  local function now() return love and love.timer and love.timer.getTime() or 0 end
  local function log(fmt, ...) if deps.log then deps.log(fmt, ...) end end

  function Tm.isOpen() return r ~= nil end
  function Tm.state() return r end

  function Tm.open(ctx, opts)
    ctx.app = opts.app or "map"
    -- (the map's card keeps clear of the hints' glass along the foot)
    if not opts.maker then opts.footer = Tm.FOOT end
    local ok, w
    if opts.maker then ok, w = pcall(opts.maker, ctx, deps.env) else ok, w = pcall(deps.scene, ctx, deps.env, opts) end
    if not (ok and type(w) == "table") then
      log("the full-screen %s failed to open: %s", ctx.app, tostring(w))
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
      r.touch[id] = { x = x, y = y, ly = y }
      if w.pointer then pcall(w.pointer, "pressed", ux, uy, id) end
    elseif ev.phase == "moved" then
      local t = r.touch[id]
      if t and (abs(x - t.x) > 4 * K.sc or abs(y - t.y) > 4 * K.sc) then t.drag = true end
      if w.pointer then
        pcall(w.pointer, "moved", ux, uy, id)
      elseif t and t.drag and w.scroll then
        -- (a window without its own pointer: a drag scrolls it)
        pcall(w.scroll, (y - t.ly) / K.sc, t.x, t.y)
        t.ly = y
      end
    elseif ev.phase == "released" or ev.phase == "cancelled" then
      local t = r.touch[id]
      r.touch[id] = nil
      local ok, used = false, false
      if w.pointer then ok, used = pcall(w.pointer, ev.phase, ux, uy, id) end
      if ev.phase == "released" and t and not t.drag and not (ok and used) then
        local h = hitAt(x, y)
        if h and h.kind == "back" then
          if deps.se then deps.se("SE_SELECT") end
          if r.opts.cancel then r.opts.cancel() end
        elseif h and h.kind == "win" and w.tap then
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
    local w = r.win
    local chrome = r.opts.chrome
    if chrome then
      -- (an app: the windows' grey, a toolbar with the way back and its title, the hints below)
      local UI = K.UI
      K.col(UI.grouped)
      K.box("fill", K.R(0, 0, pw, ph))
      local tb = K.R(0, 0, pw, TOOL)
      K.grad(tb, 0, UI.toolbar, UI.toolbarFoot)
      K.hairline(0, TOOL, pw)
      local back = T and T("pokenav.back") or "PokeNav"
      K.chevron(5, TOOL / 2, 3.6, UI.accent, -1)
      K.text(back, 8, TOOL / 2 - 2.8, 4.8, UI.accent)
      K.addHit(K.R(0, 0, K.width(back, 4.8) + 14, TOOL), "back")
      K.bold(w.title or "", 0, TOOL / 2 - 2.9, 5, UI.label, "center", pw)
      b[1], b[2], b[3], b[4] = 0, TOOL + 0.5, pw, ph - TOOL - 0.5 - Tm.FOOT
    else
      b[1], b[2], b[3], b[4] = 0, 0, pw, ph
    end
    local ok, err = pcall(w.draw, b, clock, pw < ph)
    if not ok then log("the full-screen %s's draw failed: %s", tostring(r.ctx.app), tostring(err)) end
    K.scissor()
    -- (the hints: in a glass capsule floating along the map's foot; on a dark bar under an app)
    local okH, hints = pcall(w.hints)
    if okH and hints then
      local hb = K.R(3, ph - Tm.FOOT + 1, pw - 6, Tm.FOOT - 4)
      if w.glass then
        pcall(w.glass, hb, hb[4] / 2)
      else
        K.col(BAR)
        K.box("fill", K.R(0, ph - Tm.FOOT, pw, Tm.FOOT))
      end
      K.hints(hints, K.R(hb[1] + 3, hb[2] + 1, hb[3] - 6, 8), KEY, true, INK, INK)
    end
    K.scissor()
  end

  return Tm
end
