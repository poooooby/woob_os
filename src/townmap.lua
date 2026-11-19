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
--                        (window(ctx, env)), app, chrome, backKey (the toolbar's way back; default the PokéNav's); cancel(): B, or that) ; Tm.close() ;
--                        Tm.isOpen() ; Tm.state()
--   Tm.draw(G, vp) ; Tm.input(input) ; Tm.pointer(ev) -> true ; Tm.wheel(dy) -> true
--   opts.veil = see(on): a fade through black from the field and back to it, the host's own (a shop
--                        counter): the field to black, then the window up from it; Tm.leave(after) the
--                        same backwards, after() once the field is back. see(true) shows the field
--                        through while it's under the black. Buttons and fingers wait while it fades.

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
    if opts.veil then
      r.veil = { phase = "in", t = now(), after = nil }
      pcall(opts.veil, true)
    end
    return true
  end
  function Tm.close()
    local w = r and r.win
    r = nil
    if w and w.close then pcall(w.close) end
  end

  -- ------- the veil: in (the field to black), up (the window from black), down (the window to black),
  -- out (the field from black); nil while still
  Tm.VEIL = 0.45
  -- -> true when it's going backwards now (after() comes later), false: no veil, close at once
  function Tm.leave(after)
    local v = r and r.veil
    if not v then return false end
    if v.phase == "down" or v.phase == "out" then return true end
    -- (from partway up: down from where it is)
    local k = v.phase == "up" and max(0, 1 - (now() - v.t) / Tm.VEIL) or 0
    if v.phase == "in" then
      -- (the field still showing: straight back out from the black it reached)
      k = min(1, (now() - v.t) / Tm.VEIL)
      v.phase, v.t, v.after = "out", now() - (1 - k) * Tm.VEIL, after
      return true
    end
    v.phase, v.t, v.after = "down", now() - k * Tm.VEIL, after
    return true
  end
  function Tm.veiling() return r ~= nil and r.veil ~= nil and r.veil.phase ~= nil end
  -- (stepped once a frame from the draw: the black's amount; through: the field's under it, not the window)
  local function veilStep()
    local v = r.veil
    if not (v and v.phase) then return 0, false end
    local k = min(1, max(0, (now() - v.t) / Tm.VEIL))
    local ph = v.phase
    if ph == "in" then
      if k >= 1 then
        pcall(r.opts.veil, false)
        v.phase, v.t = "up", now()
        return 1, false
      end
      return k, true
    elseif ph == "up" then
      if k >= 1 then v.phase = nil; return 0, false end
      return 1 - k, false
    elseif ph == "down" then
      if k >= 1 then
        pcall(r.opts.veil, true)
        v.phase, v.t = "out", now()
        return 1, true
      end
      return k, false
    end
    -- (out: the field back up from black; then the window goes and the game hears)
    if k >= 1 then
      local after = v.after
      v.phase, v.after = "gone", nil
      if after then after() end
      return 0, true
    end
    return 1 - k, true
  end

  local cur
  local NAV = {}
  function Tm.input(input)
    if not (r and input) then return end
    cur = input
    if Tm.veiling() then return end
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

  -- (a host that shares the kit with another one in the same frame keeps its own copy of its hits:
  -- deps.keepHits, the Gear's panel)
  local kept, keptN, keptOx, keptOy, keptSc = {}, 0, 0, 0, 1
  local function keepHits()
    local hits = K.hits
    keptN = #hits
    keptOx, keptOy, keptSc = K.ox, K.oy, K.sc
    for i = 1, keptN do
      local h, rec = hits[i], kept[i]
      if not rec then
        rec = {}
        kept[i] = rec
      end
      rec[1], rec[2], rec[3], rec[4], rec.kind, rec.arg = h[1], h[2], h[3], h[4], h.kind, h.arg
    end
  end
  local function hitAt(x, y)
    if deps.keepHits then
      for i = keptN, 1, -1 do
        if K.inside(kept[i], x, y) then return kept[i] end
      end
      return nil
    end
    local hits = K.hits
    for i = #hits, 1, -1 do
      local h = hits[i]
      if K.inside(h, x, y) then return h end
    end
  end
  local function units(x, y)
    if deps.keepHits then return (x - keptOx) / keptSc, (y - keptOy) / keptSc end
    return (x - K.ox) / K.sc, (y - K.oy) / K.sc
  end
  local function locked() return r.opts.locked ~= nil and r.opts.locked() == true end

  -- every finger to the map (it turns, tilts and pinches); a still one's release is a tap
  function Tm.pointer(ev)
    if not (r and type(ev) == "table") then return true end
    if Tm.veiling() then
      r.touch[ev.id or 1] = nil
      return true
    end
    local x, y, id = tonumber(ev.x) or 0, tonumber(ev.y) or 0, ev.id or 1
    local w = r.win
    local ux, uy = units(x, y)
    local stop = locked()
    local sc = deps.keepHits and keptSc or K.sc
    if ev.phase == "pressed" then
      r.touch[id] = { x = x, y = y, ly = y }
      if w.pointer and not stop then pcall(w.pointer, "pressed", ux, uy, id) end
    elseif ev.phase == "moved" then
      local t = r.touch[id]
      if t and (abs(x - t.x) > 4 * sc or abs(y - t.y) > 4 * sc) then t.drag = true end
      if stop then
        if t then t.ly = y end
      elseif w.pointer then
        pcall(w.pointer, "moved", ux, uy, id)
      elseif t and t.drag and w.scroll then
        -- (a window without its own pointer: a drag scrolls it)
        pcall(w.scroll, (y - t.ly) / sc, t.x, t.y)
        t.ly = y
      end
    elseif ev.phase == "released" or ev.phase == "cancelled" then
      local t = r.touch[id]
      r.touch[id] = nil
      local ok, used = false, false
      if w.pointer and not stop then ok, used = pcall(w.pointer, ev.phase, ux, uy, id) end
      if ev.phase == "released" and t and not t.drag and not (ok and used) then
        local h = hitAt(x, y)
        if h and h.kind == "back" then
          if deps.se then deps.se("SE_SELECT") end
          if r.opts.cancel then r.opts.cancel() end
        elseif h and h.kind == "win" and w.tap and not stop then
          local okT, err = pcall(w.tap, h.arg, x, y)
          if not okT then log("the 3D map's tap failed: %s", tostring(err)) end
        end
      end
    end
    return true
  end
  function Tm.wheel(dy)
    if r and r.win.scroll and not Tm.veiling() then pcall(r.win.scroll, dy * 10) end
    return true
  end

  function Tm.draw(G, vp)
    if not r then return end
    local clock = now()
    local pw, ph = K.frame(G, vp, Tm.PAGE, clock - r.t0)
    local b = r.body
    local w = r.win
    -- (the host's veil: only the black over the field while it's under it)
    local black, under = veilStep()
    if not r then return end
    if under then
      if black > 0 then
        G.setColor(0, 0, 0, black)
        G.rectangle("fill", 0, 0, K.ww, K.wh)
      end
      return
    end
    -- (a window fading over the field shows it through: win.see() true)
    local through = false
    if w.see then
      local okS, yes = pcall(w.see)
      through = okS and yes == true
    end
    if not through then
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", 0, 0, K.ww, K.wh)
    end
    local chrome = r.opts.chrome
    if chrome then
      -- (an app: the windows' grey, a toolbar with the way back and its title, the hints below)
      local UI = K.UI
      K.col(UI.grouped)
      K.box("fill", K.R(0, 0, pw, ph))
      local tb = K.R(0, 0, pw, TOOL)
      K.grad(tb, 0, UI.toolbar, UI.toolbarFoot)
      K.hairline(0, TOOL, pw)
      local back = T and T(r.opts.backKey or "pokenav.back") or "PokeNav"
      K.chevron(5, TOOL / 2, 3.6, UI.accent, -1)
      K.text(back, 8, TOOL / 2 - 2.8, 4.8, UI.accent)
      local bw = K.width(back, 4.8) + 14
      K.addHit(K.R(0, 0, bw, TOOL), "back")
      local title = w.title or ""
      if K.textScale() == 1 then
        K.bold(title, 0, TOOL / 2 - 2.9, 5, UI.label, "center", pw)
      else
        -- (bigger text: the title kept clear of the way back, still in the middle)
        local tw = max(10, pw - bw * 2)
        local fs = K.fit(title, 5, tw)
        K.bold(title, (pw - tw) / 2, TOOL / 2 - 2.9 + (5 - fs) * 0.6, fs, UI.label, "center", tw)
      end
      b[1], b[2], b[3], b[4] = 0, TOOL + 0.5, pw, ph - TOOL - 0.5 - (r.opts.noHints and 0 or Tm.FOOT)
    else
      -- (no toolbar: the whole page; an app's above its hints when it has some -- the map keeps clear itself)
      b[1], b[2], b[3], b[4] = 0, 0, pw, ph - ((r.opts.noHints or not r.opts.maker) and 0 or Tm.FOOT)
    end
    local app = r.ctx.app
    local ok, err = pcall(w.draw, b, clock, pw < ph)
    if not ok then log("the full-screen %s's draw failed: %s", tostring(app), tostring(err)) end
    K.scissor()
    -- (the window closed itself while drawing -- a lesson's last press, an HP bar's end: nothing more of it)
    if not r then return end
    if locked() then
      -- (the game's busy: nothing here that changes the party or the money until it's done)
      K.col(K.BLACK, 0.6)
      K.box("fill", b)
      local words = T and T("gear.locked") or "Finish up in the game first"
      K.bold(words, b[1] + 6, b[2] + b[4] / 2 - 3, K.fit(words, 6, b[3] - 12), INK, "center", b[3] - 12)
    end
    -- (the hints: in a glass capsule floating along the map's foot; on a dark bar under an app)
    local okH, hints = true, nil
    if not r.opts.noHints then okH, hints = pcall(w.hints) end
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
    -- (the veil's black over all of it: the toolbar and the hints too)
    if black > 0 then
      G.setColor(0, 0, 0, black)
      G.rectangle("fill", 0, 0, K.ww, K.wh)
    end
    if deps.keepHits then keepHits() end
  end

  return Tm
end
