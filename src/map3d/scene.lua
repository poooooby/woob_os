-- The 3D map's window: the region (src/map3d/model.lua) drawn by src/map3d/render.lua, a camera
-- that tilts, turns and zooms, and over it the places' pins, the player's beacon and the chosen
-- place's card (its name, visited or not, Center / Mart, the Gym and its badge, Fly). The same window
-- in every host: the desktop's and WoobPad's Map app, and the game's own Town Map / Fly screen
-- (src/townmap.lua).
--   buttons  the D-pad moves a cursor freely over the land (the way the camera faces; let go near a
--            town or a landmark and it glides onto it, as the game's own map's), L / R (or the right
--            stick) turn, the right stick tilts, A zooms, SELECT the flat map (the game's own picture,
--            north up; there L / R change the region)
--            (Fly mode: A flies to a visited town), the region's chip the next region (Sevii's), START Fly
--            (the app) or the classic map (the Town Map), B back
--   touch    drag turns and tilts, two fingers (or the wheel) zoom, a tap picks a place, the card's
--            Fly button, the region's chip, the "you" chip back to the player, the compass north up
--
--   Scene(ctx, env, opts) -> win (src/apps.lua's window contract)
--     env.map3d = { model, render, clock() -> hour, minute, fly(ctx, region, place) -> ok, reason }
--     opts = { mode = "app" | "fly" | "town", pick(region, place) (Fly mode), classic() (the Town Map's
--              START), footer (units kept clear at the foot: the Town Map's hints) }
--   win.glass(b, rad, a, tint): the overlays' frosted glass, for the host's own pieces

local floor, max, min, abs, sqrt, pi, exp = math.floor, math.max, math.min, math.abs, math.sqrt, math.pi, math.exp

-- hit args
local A_REGION, A_ME, A_FLY, A_NORTH, A_FLAT, A_PLACE = 1001, 1002, 1003, 1004, 1005, 2000
local STICK_DEAD = 0.22    -- the right stick's dead zone
local STICK_TURN, STICK_TILT = 2.2, 1.1   -- radians a second at full tilt
local TURN = 1.7        -- radians a second, L / R held
local EASE = 7          -- the camera's catch-up (per second)
local PITCH_MIN, PITCH_MAX = 0.42, 1.38
local SNAP = 1.1        -- let go this near a town or a landmark (units): the cursor glides onto it
local GLIDE = 11        -- how fast it glides (per second)
local M = 3

local HINTS = {
  flat = { { "+", "map.hint.go" }, { "L R", "map.hint.region" }, { "A", "map.hint.zoom" }, { "SELECT", "map.hint.3d" },
           { "B", "hint.back" } },
  flatFly = { { "+", "map.hint.go" }, { "L R", "map.hint.region" }, { "A", "map.fly" }, { "SELECT", "map.hint.3d" },
              { "B", "hint.back" } },
  app = { { "+", "map.hint.go" }, { "L R", "map.hint.turn" }, { "A", "map.hint.zoom" }, { "SELECT", "map.hint.flat" },
          { "B", "hint.back" } },
  appFly = { { "+", "map.hint.go" }, { "L R", "map.hint.turn" }, { "A", "map.hint.zoom" }, { "SELECT", "map.hint.flat" },
             { "START", "map.fly" },
             { "B", "hint.back" } },
  fly = { { "+", "map.hint.go" }, { "L R", "map.hint.turn" }, { "A", "map.fly" }, { "SELECT", "map.hint.flat" },
          { "B", "hint.back" } },
  town = { { "+", "map.hint.go" }, { "L R", "map.hint.turn" }, { "A", "map.hint.zoom" }, { "SELECT", "map.hint.flat" },
           { "START", "map.classic" },
           { "B", "hint.back" } },
}
local NO_T = setmetatable({ list = function(l) return l end, f = string.format }, { __call = function(_, k) return k end })

return function(ctx, env, opts)
  opts = opts or {}
  local K, T = env.K, env.T or NO_T
  local UI = K.UI
  local Mdl, Rd = env.map3d.model, env.map3d.render
  local mode = opts.mode or "app"
  local W = { title = mode == "fly" and T("map.flyTitle") or T("app.map") }
  local function session() return ctx.session or (env.session and env.session()) end
  -- (the mod's options: the camera's turn and tilt inverted -> -1 or 1 each)
  local function invert()
    local f = env.map3d.invert
    if not f then return 1, 1 end
    local ok, x, y = pcall(f)
    if not ok then return 1, 1 end
    return x and -1 or 1, y and -1 or 1
  end
  local function se(name) if env.se then pcall(env.se, name) end end

  local st = {
    regions = {}, ri = 1, region = nil, nav = {}, sel = 0, player = nil, playerPlace = nil,
    cx = 0, cz = 0, here = nil, snapTo = nil, dirX = 0, dirY = 0, moving = false, flat = false,
    stickX = 0, stickY = 0,
    cam = { x = 0, y = 0, z = 0, yaw = 0.35, pitch = 0.95, dist = 14 },
    goal = { x = 0, y = 0, z = 0, yaw = 0.35, pitch = 0.95, dist = 14 },
    zoom = 2, turn = 0, lastT = nil, liveAt = -10, hour = 12, minute = 0, toast = nil,
    touch = {}, nTouch = 0, rect = { x = 0, y = 0, w = 1, h = 1 }, flyMon = nil, flyWhy = nil, three = false,
  }
  W.state = st

  -- ------- the regions and the places

  local function zoomDist(z)
    local r = st.region
    local size = r and max(r.w, r.h) or 24
    if z == 1 then return size * 1.25 end
    if z == 2 then return size * 0.55 end
    return size * 0.3
  end
  local function zoomPitch(z) return z == 1 and 1.05 or (z == 2 and 0.92 or 0.78) end

  -- the place under the cursor (a town over its landmarks; nothing over the sea)
  local function place() return st.here end
  -- the camera's goal: the cursor (the whole region at the widest zoom, leaning toward it)
  local function follow()
    local r, g = st.region, st.goal
    if not r then return end
    if st.zoom == 1 then
      g.x, g.z, g.y = r.x0 + r.w / 2, r.z0 + r.h / 2, 0
      g.x, g.z = g.x + (st.cx - g.x) * 0.25, g.z + (st.cz - g.z) * 0.25
    else
      g.x, g.z, g.y = st.cx, st.cz, Mdl.heightAt(r, st.cx, st.cz)
    end
  end
  local function aim(snap)
    local r, g = st.region, st.goal
    if not r then return end
    follow()
    g.dist, g.pitch = zoomDist(st.zoom), zoomPitch(st.zoom)
    if snap then
      local c = st.cam
      c.x, c.y, c.z, c.dist, c.pitch, c.yaw = g.x, g.y, g.z, g.dist, g.pitch, g.yaw
    end
  end

  -- (one cell, several places: a town over a landmark over a route)
  local RANK = { town = 3, landmark = 2, route = 1 }
  local function placeAt(region, x, z)
    local best
    for _, p in ipairs(region.places) do
      for _, c in ipairs(p.cells) do
        if x >= c[1] and x < c[1] + 1 and z >= c[2] and z < c[2] + 1 then
          if not best or RANK[p.kind] > RANK[best.kind] then best = p end
        end
      end
    end
    return best
  end

  -- what's under the cursor now (its pin's index for the highlight; a sound on reaching a town)
  local function updateHere()
    local r = st.region
    local p = r and placeAt(r, st.cx, st.cz) or nil
    if p and p.shown == false then p = nil end
    if p ~= st.here then
      st.here = p
      if p and p.kind ~= "route" and st.moving then se("SE_SELECT") end
    end
    st.sel = 0
    local want = p and (p.within or p)
    for i, q in ipairs(st.nav) do
      if q == want then st.sel = i end
    end
  end

  local function refreshLive()
    local s = session()
    if st.region then pcall(Mdl.live, st.region, s) end
    local ok, h, m = pcall(env.map3d.clock)
    if ok and h then st.hour, st.minute = h, m or 0 end
    if mode == "app" and env.map3d.flyCheck then
      local okF, mon, why = pcall(env.map3d.flyCheck, ctx, s)
      st.flyMon, st.flyWhy = okF and mon or nil, okF and why or "none"
    end
  end

  -- a region shown: its places to hop between (towns, then landmarks of their own), the chosen one
  -- kept by its id
  local function setRegion(i, keepId)
    local d = st.regions[i]
    if not d then return end
    st.ri = i
    local ok, region = pcall(Mdl.region, d.id)
    if not ok then
      if env.log then env.log("the map's region %s failed: %s", d.id, tostring(region)) end
      return
    end
    st.region = region
    refreshLive()
    st.nav = {}
    for _, p in ipairs(region.places) do
      if p.kind == "town" and p.shown ~= false then st.nav[#st.nav + 1] = p end
    end
    for _, p in ipairs(region.places) do
      if p.kind == "landmark" and not p.within and p.shown ~= false then st.nav[#st.nav + 1] = p end
    end
    st.sel, st.snapTo = 0, nil
    local want = keepId
    if not want and st.player and st.player[1] == d.id then
      local here = placeAt(region, st.player[2], st.player[3])
      st.playerPlace = here
      if here then want = here.within and here.within.id or here.id end
      -- (on a route: the town nearest the player)
      if here and here.kind == "route" then
        local best, bd = nil, math.huge
        for _, p in ipairs(st.nav) do
          local dd = (p.x - st.player[2]) ^ 2 + (p.z - st.player[3]) ^ 2
          if p.kind == "town" and dd < bd then best, bd = p, dd end
        end
        want = best and best.id
      end
    elseif not (st.player and st.player[1] == d.id) then
      st.playerPlace = nil
    end
    -- (the cursor: on the place wanted, else where the player stands, else the first town)
    local at = nil
    for _, p in ipairs(region.places) do
      if p.id == want then at = p end
    end
    if keepId == nil and st.player and st.player[1] == d.id then
      st.cx, st.cz = st.player[2], st.player[3]
    elseif at or st.nav[1] then
      at = at or st.nav[1]
      st.cx, st.cz = at.x, at.z
    else
      st.cx, st.cz = region.x0 + region.w / 2, region.z0 + region.h / 2
    end
    updateHere()
  end

  local function start()
    local s = session()
    local okP, rid, px, pz = pcall(Mdl.player, s)
    -- (only on one of the map's places: not, say, in the moving truck before the game begins)
    if okP and rid then
      local okR, region = pcall(Mdl.region, rid)
      if okR and region and placeAt(region, px, pz) then st.player = { rid, px, pz } end
    end
    for _, d in ipairs(Mdl.regions()) do
      local okA, yes = pcall(Mdl.available, s, d.id)
      if (okA and yes) or (st.player and st.player[1] == d.id) then st.regions[#st.regions + 1] = d end
    end
    if #st.regions == 0 then st.regions[1] = Mdl.regions()[1] end
    local first = 1
    for i, d in ipairs(st.regions) do
      if st.player and st.player[1] == d.id then first = i end
    end
    local resume = ctx.resume and ctx.resume.app == ctx.app and ctx.resume.state
    if type(resume) == "table" and resume.region then
      for i, d in ipairs(st.regions) do
        if d.id == resume.region then first = i end
      end
    end
    setRegion(first, type(resume) == "table" and resume.place or nil)
    if mode == "fly" then st.zoom = 1 end
    aim(true)
  end

  -- ------- moving about

  -- a place picked (its pin tapped, back to the player): the cursor glides onto it
  local function glideTo(p)
    if not p then return end
    st.snapTo = p
    if st.zoom == 1 then st.zoom = 2 end
    aim()
    se("SE_SELECT")
  end
  local function choose(i) glideTo(st.nav[i]) end
  -- (tests and hosts: the cursor at a place at once)
  function W.focus(p)
    if not p then return end
    st.cx, st.cz, st.snapTo = p.x, p.z, nil
    updateHere()
    follow()
  end

  local function setZoom(z)
    st.zoom = (z - 1) % 3 + 1
    aim()
    se("SE_SELECT")
  end

  local function toastOf(key, bad)
    st.toast = { text = T(key), bad = bad ~= false, t = env.now and env.now() or 0 }
  end

  -- Fly to the chosen place: back to the game's own Fly (its map's callback), or from the app the
  -- game's flight itself (env.map3d.fly)
  local function fly()
    local p, r = place(), st.region
    if not (p and r) then return end
    if p.kind ~= "town" or not p.canFly then
      se("SE_FAILURE")
      return toastOf(p.kind == "town" and "map.notVisited" or "map.cantFlyThere")
    end
    if mode == "fly" then
      se("SE_SELECT")
      if opts.pick then opts.pick(r, p) end
      return
    end
    if mode ~= "app" then return end
    if not st.flyMon then
      se("SE_FAILURE")
      return toastOf("map.why." .. tostring(st.flyWhy or "none"))
    end
    local ok, done, why = pcall(env.map3d.fly, ctx, r, p)
    if not (ok and done) then
      se("SE_FAILURE")
      toastOf("map.why." .. tostring(why or "none"))
    end
  end

  local function nextRegion(d)
    if #st.regions < 2 then return end
    setRegion((st.ri - 1 + d) % #st.regions + 1)
    aim(true)
    se("SE_SELECT")
  end
  local function toPlayer()
    if not st.player then return end
    for i, d in ipairs(st.regions) do
      if d.id == st.player[1] and i ~= st.ri then setRegion(i) end
    end
    st.snapTo = nil
    st.cx, st.cz = st.player[2], st.player[3]
    updateHere()
    if st.zoom == 1 then st.zoom = 2 end
    aim()
    se("SE_SELECT")
  end

  -- ------- the window's contract

  local cur
  local function pressed(k) return cur:wasPressed(k) end
  local function down(k)
    local ok, d = pcall(cur.isDown, cur, k)
    return ok and d == true
  end
  function W.input(input, nav)
    cur = input
    st.turn = st.flat and 0 or ((down("l") and -1 or 0) + (down("r") and 1 or 0))
    -- (the right stick: the engine keeps its position)
    local axis = input.rightStickAxis
    local sx, sy = axis and tonumber(axis.x) or 0, axis and tonumber(axis.y) or 0
    st.stickX = abs(sx) > STICK_DEAD and sx or 0
    st.stickY = abs(sy) > STICK_DEAD and sy or 0
    -- (the D-pad held: the cursor moves, free; let go: it settles)
    st.dirX = (down("right") and 1 or 0) - (down("left") and 1 or 0)
    st.dirY = (down("down") and 1 or 0) - (down("up") and 1 or 0)
    if st.dirX ~= 0 or st.dirY ~= 0 then
      st.snapTo = nil
      return true
    end
    if pressed("a") then
      if mode == "fly" then fly() else setZoom(st.zoom + 1) end
    elseif pressed("select") then
      st.flat = not st.flat
      se("SE_SELECT")
    elseif st.flat and (pressed("l") or pressed("r")) then nextRegion(pressed("l") and -1 or 1)
    elseif pressed("start") then
      if mode == "town" and opts.classic then opts.classic()
      elseif mode == "app" then fly() end
    elseif pressed("b") then
      return false
    end
    return true
  end

  function W.tap(arg)
    if arg == A_REGION then return nextRegion(1) end
    if arg == A_ME then return toPlayer() end
    if arg == A_FLY then return fly() end
    if arg == A_FLAT then
      st.flat = not st.flat
      return se("SE_SELECT")
    end
    if arg == A_NORTH then
      -- (north up: the nearest whole turn)
      local g = st.goal
      g.yaw = 2 * pi * floor(g.yaw / (2 * pi) + 0.5)
      return se("SE_SELECT")
    end
    if type(arg) == "number" and arg > A_PLACE then
      local i = arg - A_PLACE
      if st.nav[i] and st.nav[i] == st.here then
        if mode == "fly" then return fly() end
        return setZoom(st.zoom == 3 and 2 or 3)
      end
      return choose(i)
    end
  end

  -- the wheel (and the hosts' scroll): zoom
  function W.scroll(dy)
    local g = st.goal
    g.dist = max(3.5, min(zoomDist(1) * 1.2, g.dist * exp(-dy * 0.012)))
  end

  -- drags turn and tilt; two fingers pinch to zoom
  function W.pointer(phase, x, y, id)
    id = id or 1
    local tch = st.touch
    if phase == "pressed" then
      if not tch[id] then st.nTouch = st.nTouch + 1 end
      tch[id] = tch[id] or {}
      local t = tch[id]
      t.x, t.y, t.x0, t.y0, t.moved = x, y, x, y, false
      st.pinch = nil
    elseif phase == "moved" then
      local t = tch[id]
      if not t then return false end
      local dx, dy = x - t.x, y - t.y
      t.x, t.y = x, y
      if abs(x - t.x0) > 3 or abs(y - t.y0) > 3 then t.moved = true end
      if st.nTouch >= 2 then
        -- (two fingers: their spread zooms)
        local a, b
        for _, q in pairs(tch) do
          if not a then a = q elseif not b then b = q end
        end
        if a and b then
          local d = sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
          if st.pinch and d > 1 then
            local g = st.goal
            g.dist = max(3.5, min(zoomDist(1) * 1.2, g.dist * st.pinch / d))
            st.cam.dist = g.dist
          end
          st.pinch = d
        end
        return false
      end
      if t.moved then
        local g, c = st.goal, st.cam
        local ix, iy = invert()
        g.yaw = g.yaw - dx * 0.018 * ix
        g.pitch = max(PITCH_MIN, min(PITCH_MAX, g.pitch + dy * 0.012 * iy))
        c.yaw, c.pitch = g.yaw, g.pitch
      end
    elseif phase == "released" or phase == "cancelled" then
      local t = tch[id]
      if not t then return false end
      tch[id] = nil
      st.nTouch = max(0, st.nTouch - 1)
      st.pinch = nil
      return t.moved
    end
    return false
  end

  function W.hints()
    if st.flat then return T.list(mode == "fly" and HINTS.flatFly or HINTS.flat) end
    if mode == "fly" then return T.list(HINTS.fly) end
    if mode == "town" then return T.list(HINTS.town) end
    return T.list(st.flyMon and HINTS.appFly or HINTS.app)
  end

  function W.close() st.touch, st.nTouch = {}, 0 end
  -- (for ctx.resume: the region and the place)
  function W.save()
    local p = place()
    return { region = st.regions[st.ri] and st.regions[st.ri].id, place = p and p.id }
  end

  -- ------- drawing (no tables made here)

  local function U(px) return (px - K.ox) / K.sc end
  local function V(py) return (py - K.oy) / K.sc end

  -- the cursor: moved by the held D-pad the way the camera faces (faster zoomed out, a little slower
  -- over a town: it catches there); let go, it glides onto the nearest town or landmark close by
  local function stepCursor(dt)
    local r = st.region
    if not r then return end
    if st.dirX ~= 0 or st.dirY ~= 0 then
      local yaw = st.flat and 0 or st.cam.yaw
      local fx, fz = -math.sin(yaw), -math.cos(yaw)
      local rx, rz = math.cos(yaw), -math.sin(yaw)
      local mx = rx * st.dirX - fx * st.dirY
      local mz = rz * st.dirX - fz * st.dirY
      local l = sqrt(mx * mx + mz * mz)
      if l > 0 then
        local speed = max(2.4, st.cam.dist * 0.3)
        if st.here and st.here.kind ~= "route" then speed = speed * 0.55 end
        st.cx = max(r.x0, min(r.x0 + r.w, st.cx + mx / l * speed * dt))
        st.cz = max(r.z0, min(r.z0 + r.h, st.cz + mz / l * speed * dt))
      end
      st.moving = true
    else
      if st.moving and not st.snapTo then
        -- (let go: the nearest town or landmark close by)
        local best, bd = nil, SNAP * SNAP
        for _, p in ipairs(st.nav) do
          local d = (p.x - st.cx) ^ 2 + (p.z - st.cz) ^ 2
          if d < bd then best, bd = p, d end
        end
        st.snapTo = best
      end
      st.moving = false
      local p = st.snapTo
      if p then
        local k = 1 - exp(-GLIDE * dt)
        st.cx, st.cz = st.cx + (p.x - st.cx) * k, st.cz + (p.z - st.cz) * k
        if abs(p.x - st.cx) < 0.005 and abs(p.z - st.cz) < 0.005 then
          st.cx, st.cz, st.snapTo = p.x, p.z, nil
        end
      end
    end
    updateHere()
    follow()
  end

  -- the camera catching up with its goal, and L / R turning it
  local function stepCamera(dt)
    local c, g = st.cam, st.goal
    if st.turn ~= 0 then g.yaw = g.yaw + st.turn * TURN * dt end
    if not st.flat and (st.stickX ~= 0 or st.stickY ~= 0) then
      local ix, iy = invert()
      g.yaw = g.yaw + st.stickX * STICK_TURN * dt * ix
      g.pitch = max(PITCH_MIN, min(PITCH_MAX, g.pitch - st.stickY * STICK_TILT * dt * iy))
      c.yaw, c.pitch = g.yaw, g.pitch
    end
    local k = 1 - exp(-EASE * dt)
    c.x, c.y, c.z = c.x + (g.x - c.x) * k, c.y + (g.y - c.y) * k, c.z + (g.z - c.z) * k
    c.dist = c.dist + (g.dist - c.dist) * k
    c.pitch = c.pitch + (g.pitch - c.pitch) * k
    c.yaw = c.yaw + (g.yaw - c.yaw) * min(1, k * 1.6)
  end

  -- ------- the glass (every overlay: the map frosted under it, a dark tint, a gloss, a fine rim)

  local TINT, WHITE, SOFT = { 16, 18, 26 }, { 255, 255, 255 }, { 236, 239, 247, 0.72 }
  local GLOSS, GLOSS0 = { 255, 255, 255, 0.2 }, { 255, 255, 255, 0 }
  local PILL = { 255, 255, 255, 0.13 }
  local GOOD, GOOD_FILL = { 120, 232, 150 }, { 52, 199, 89, 0.24 }
  local LAND_INK, LAND_FILL = { 255, 206, 90 }, { 255, 189, 46, 0.22 }
  local ACCENT, ACCENT_TOP = { 10, 132, 255 }, { 255, 255, 255, 0.32 }
  local SHADOW, BEAM = { 0, 0, 0 }, { 255, 70, 60 }
  local CENTER_C, MART_C, GYM_C = { 255, 92, 80 }, { 80, 150, 255 }, { 170, 196, 186 }

  local function glass(b, rad, a, tint)
    K.shadow(b, rad, 1.4, 0.3)
    local G = K.graphics()
    local frosted = st.three and Rd.frost(G, K.X(b[1]), K.Y(b[2]), b[3] * K.sc, b[4] * K.sc, rad * K.sc)
    K.col(tint or TINT, (a or 0.4) + (frosted and 0 or 0.38))
    K.box("fill", b, rad)
    K.grad(b, rad, GLOSS, GLOSS0)
    K.ring(b, rad, WHITE, 0.3, 0.4)
  end
  W.glass = glass

  -- ------- the pins: a stem from the ground, a glass disc (a city's bigger), the chosen one ringed

  local function drawPins(clock)
    local G = K.graphics()
    local rect = st.rect
    for i, p in ipairs(st.nav) do
      local gx, gy = Rd.project(p.x, p.y or 0, p.z)
      local hx, hy, depth = Rd.project(p.x, (p.y or 0) + 0.6, p.z)
      if gx and hx and hx > rect.x - 20 and hx < rect.x + rect.w + 20 and hy > rect.y - 20 and hy < rect.y + rect.h + 20 then
        local chosen = i == st.sel
        local tierK = p.kind ~= "town" and 0.8 or (p.tier == 3 and 1.25 or (p.tier == 0 and 0.8 or 1))
        local size = max(2.4, min(5.5, 60 / depth)) * tierK * (chosen and 1.3 or 1)
        local rad = size / 2 * K.sc
        K.col(SHADOW, 0.3)
        G.ellipse("fill", gx, gy, rad * 0.7, rad * 0.3)
        K.col(WHITE, 0.55)
        G.setLineWidth(max(1, 0.35 * K.sc))
        G.line(gx, gy, hx, hy + rad)
        if chosen then
          K.col(WHITE, 0.25 * K.pulse())
          G.circle("fill", hx, hy, rad + 2.2 * K.sc)
        end
        K.col(TINT, 0.62)
        if p.kind == "town" then
          G.circle("fill", hx, hy, rad)
          K.col(p.visited and ACCENT or WHITE, p.visited and 1 or 0.75)
          G.circle("fill", hx, hy, rad * 0.5)
        else
          G.polygon("fill", hx, hy - rad, hx + rad, hy, hx, hy + rad, hx - rad, hy)
          K.col(LAND_INK)
          G.polygon("fill", hx, hy - rad * 0.5, hx + rad * 0.5, hy, hx, hy + rad * 0.5, hx - rad * 0.5, hy)
        end
        K.col(WHITE, chosen and 0.95 or 0.6)
        G.setLineWidth(max(1, (chosen and 0.55 or 0.35) * K.sc))
        if p.kind == "town" then
          G.circle("line", hx, hy, rad)
        else
          G.polygon("line", hx, hy - rad, hx + rad, hy, hx, hy + rad, hx - rad, hy)
        end
        local ux, uy = U(hx), V(hy)
        K.addHit(K.R(ux - 5, uy - 5, 10, 10), "win", A_PLACE + i)
      end
    end
    -- (the player: a beam up from where they stand, rings spreading on the ground)
    local pl = st.player
    if pl and st.regions[st.ri] and pl[1] == st.regions[st.ri].id and st.region then
      local h = Mdl.heightAt(st.region, pl[2], pl[3])
      local gx, gy, depth = Rd.project(pl[2], h, pl[3])
      local tx, ty = Rd.project(pl[2], h + 1.1, pl[3])
      if gx and tx then
        local s = max(2, min(6, 70 / depth))
        for k = 0, 1 do
          local wave = (clock * 0.7 + k * 0.5) % 1
          K.col(BEAM, 0.75 * (1 - wave))
          G.setLineWidth(max(1, 0.45 * K.sc))
          G.ellipse("line", gx, gy, s * (0.4 + wave * 1.8) * K.sc, s * (0.18 + wave * 0.8) * K.sc)
        end
        K.col(BEAM, 0.25)
        G.setLineWidth(max(1, s * 0.7 * K.sc))
        G.line(gx, gy, tx, ty)
        K.col(BEAM, 0.8)
        G.setLineWidth(max(1, s * 0.22 * K.sc))
        G.line(gx, gy, tx, ty)
        K.col(BEAM, 0.3)
        G.circle("fill", tx, ty, s * 0.95 * K.sc)
        K.col(WHITE)
        G.circle("fill", tx, ty, s * 0.58 * K.sc)
        K.col(BEAM)
        G.circle("fill", tx, ty, s * 0.42 * K.sc)
      end
    end
  end

  -- the cursor: a ring on the ground where it is, a little marker floating over it
  local CURSOR = { 255, 64, 64 }
  local function drawCursor(clock)
    local r = st.region
    if not r then return end
    local G = K.graphics()
    local h = Mdl.heightAt(r, st.cx, st.cz)
    local gx, gy, depth = Rd.project(st.cx, h, st.cz)
    local tx, ty = Rd.project(st.cx, h + 0.35, st.cz)
    if not (gx and tx) then return end
    local s = max(2.2, min(6, 60 / depth))
    local pulse = 0.75 + 0.25 * math.sin(clock * 6)
    K.col(SHADOW, 0.35)
    G.setLineWidth(max(1, 0.9 * K.sc))
    G.ellipse("line", gx, gy + 0.3 * K.sc, s * 1.1 * K.sc, s * 0.5 * K.sc)
    K.col(CURSOR, 0.95)
    G.setLineWidth(max(1, 0.6 * K.sc))
    G.ellipse("line", gx, gy, s * 1.1 * pulse * K.sc, s * 0.5 * pulse * K.sc)
    K.col(WHITE, 0.9)
    G.ellipse("line", gx, gy, s * 0.55 * K.sc, s * 0.25 * K.sc)
    -- (the marker: a small downward point, bobbing)
    local by = ty - math.abs(math.sin(clock * 3)) * 1.2 * K.sc
    local u = s * 0.45 * K.sc
    K.col(SHADOW, 0.3)
    G.polygon("fill", tx - u, by - u * 1.3 + 0.4 * K.sc, tx + u, by - u * 1.3 + 0.4 * K.sc, tx, by + 0.4 * K.sc)
    K.col(CURSOR)
    G.polygon("fill", tx - u, by - u * 1.3, tx + u, by - u * 1.3, tx, by)
    K.col(WHITE, 0.9)
    G.setLineWidth(max(1, 0.35 * K.sc))
    G.polygon("line", tx - u, by - u * 1.3, tx + u, by - u * 1.3, tx, by)
  end

  -- the chosen place's name over its pin: a glass capsule pointing down at it
  local function drawLabel()
    local p = place()
    if not p then return end
    local lx, lz = p.x, p.z
    local ly = p.y or 0
    if p.kind == "route" or st.sel == 0 then lx, lz, ly = st.cx, st.cz, Mdl.heightAt(st.region, st.cx, st.cz) end
    local hx, hy, depth = Rd.project(lx, ly + 0.6, lz)
    if not hx then return end
    local fs = 4.6
    local tw = K.width(p.name, fs) + 8
    local rad = max(2.4, min(5.5, 60 / depth)) * 0.65
    local b = K.R(U(hx) - tw / 2, V(hy) - rad - 12, tw, 8.5)
    glass(b, 4.25, 0.5)
    local G = K.graphics()
    K.col(TINT, 0.7)
    local cx, by = K.X(b[1] + b[3] / 2), K.Y(b[2] + b[4])
    G.polygon("fill", cx - 1.6 * K.sc, by, cx + 1.6 * K.sc, by, cx, by + 1.8 * K.sc)
    K.bold(p.name, b[1], b[2] + 1.5, fs, WHITE, "center", b[3])
  end

  -- a capsule: a coloured dot and words (the card's facts) -> the x after it
  local function pill(x, y, dot, words, fs, fill, ink)
    local tw = K.width(words, fs)
    local w = tw + (dot and 8.4 or 5)
    local b = K.R(x, y, w, fs + 2.6)
    K.col(fill or PILL)
    K.box("fill", b, b[4] / 2)
    local tx = b[1] + 2.5
    if dot then
      K.col(dot)
      K.box("fill", K.R(tx, b[2] + (b[4] - 3) / 2, 3, 3), 1.5)
      tx = tx + 4.4
    end
    K.text(words, tx, b[2] + 1.15, fs, ink or WHITE)
    return x + w + 2
  end
  local function pillWidth(words, fs, dot) return K.width(words, fs) + (dot and 8.4 or 5) + 2 end
  -- a drawn tick (the default face has no check mark)
  local function tick(x, y, s, c)
    local G = K.graphics()
    K.col(c or GOOD)
    G.setLineWidth(max(1, s * 0.45 * K.sc))
    G.line(K.X(x - s), K.Y(y), K.X(x - s * 0.3), K.Y(y + s * 0.7), K.X(x + s), K.Y(y - s * 0.8))
  end
  -- ("Gym · Boulder Badge": made once per badge)
  local badgeWords = K.textCache(function(name) return T.f("map.gymBadge", name) end)

  local function drawCard(body, compact)
    local p = place()
    if not p then return end
    local x, y, w, h = body[1], body[2], body[3], body[4] - (opts.footer or 0)
    local cw = (w > 190 and not compact) and min(190, w * 0.6) or w - M * 2
    local facts = p.kind == "town" and (p.center or p.mart or p.hasGym or (p.extras and p.extras[1]))
    local ch = facts and 31 or 23
    local b = K.R(x + M, y + h - M - ch, cw, ch)
    glass(b, 6)
    local tx = b[1] + 5
    local flyable = mode == "fly" or (mode == "app" and st.flyMon ~= nil)
    local fw = (flyable and p.kind == "town") and 24 or 0
    local nw = b[3] - 10 - fw
    local fs = K.fit(p.name, compact and 5.8 or 6.6, nw)
    K.bold(p.name, tx, b[2] + 3, fs, WHITE)
    -- (visited or not; a landmark says what it is)
    local sy = b[2] + 3.6 + fs * 1.22
    if p.kind == "route" then
      pill(tx, sy, nil, T("map.route"), 3.8, PILL, SOFT)
    elseif p.kind ~= "town" then
      pill(tx, sy, nil, T("map.landmark"), 3.8, LAND_FILL, LAND_INK)
    elseif p.visited then
      local nx = pill(tx, sy, nil, T("map.visited"), 3.8, GOOD_FILL, GOOD)
      tick(nx + 1.5, sy + 3.3, 1.2)
    else
      pill(tx, sy, nil, T("map.notVisited"), 3.8, PILL, SOFT)
    end
    -- (the facts as capsules: Center, Mart, the Gym and its badge; a town's own landmark)
    if facts then
      local fy = sy + 8.2
      local center, mart = T("map.center"), T("map.mart")
      local gym = p.badgeName and badgeWords(p.badgeName) or T("map.gym")
      local need = (p.center and pillWidth(center, 3.8, true) or 0) + (p.mart and pillWidth(mart, 3.8, true) or 0)
        + (p.hasGym and pillWidth(gym, 3.8, true) + (p.badgeOwned and 3 or 0) or 0)
      if need > b[3] - 10 then center, mart, gym = T("map.centerShort"), T("map.martShort"), T("map.gym") end
      local cx = tx
      if p.center then cx = pill(cx, fy, CENTER_C, center, 3.8) end
      if p.mart then cx = pill(cx, fy, MART_C, mart, 3.8) end
      if p.hasGym then
        cx = pill(cx, fy, p.badgeOwned and UI.yellow or GYM_C, gym, 3.8)
        if p.badgeOwned then tick(cx + 1.5, fy + 3.2, 1.2) end
      end
      if not p.center and not p.mart and not p.hasGym and p.extras and p.extras[1] then
        pill(cx, fy, LAND_INK, p.extras[1].name, 3.8)
      end
    end
    if fw > 0 then
      local fb = K.R(b[1] + b[3] - fw - 4, b[2] + 4, fw, 11)
      if p.canFly then
        K.col(ACCENT)
        K.box("fill", fb, 5.5)
        K.grad(fb, 5.5, ACCENT_TOP, GLOSS0)
        K.ring(fb, 5.5, WHITE, 0.35, 0.4)
        K.bold(T("map.fly"), fb[1], fb[2] + 2.6, 4.8, WHITE, "center", fb[3])
      else
        K.col(PILL)
        K.box("fill", fb, 5.5)
        K.text(T("map.fly"), fb[1], fb[2] + 2.6, 4.8, SOFT, "center", fb[3])
      end
      K.addHit(fb, "win", A_FLY)
    end
  end

  -- the region's capsule (top left; tap: the next), "Fly to where?" (Fly), "you" and the compass
  -- (top right: back to the player; north up)
  local function drawChips(body)
    local G = K.graphics()
    local x, y, w = body[1], body[2], body[3]
    local d = st.regions[st.ri]
    local name = d and T(d.key) or ""
    local many = #st.regions > 1
    local tw = K.width(name, 4.6) + (many and 14 or 9)
    local b = K.R(x + M, y + M, tw, 10)
    glass(b, 5)
    K.bold(name, b[1] + 4.5, b[2] + 2, 4.6, WHITE)
    if many then
      K.chevron(b[1] + b[3] - 5, b[2] + 5, 3.4, SOFT, 1)
      K.addHit(b, "win", A_REGION)
    end
    if mode == "fly" then
      local fw = K.width(W.title, 4.6) + 10
      local fb = K.R(x + w / 2 - fw / 2, y + M, fw, 10)
      glass(fb, 5, 0.55, ACCENT)
      K.bold(W.title, fb[1], fb[2] + 2, 4.6, WHITE, "center", fb[3])
    end
    local right = x + w - M
    if st.player then
      local mb = K.R(right - 10, y + M, 10, 10)
      glass(mb, 5)
      K.col(BEAM)
      G.circle("fill", K.X(mb[1] + 5), K.Y(mb[2] + 5), 1.7 * K.sc)
      K.col(WHITE, 0.9)
      G.setLineWidth(max(1, 0.5 * K.sc))
      G.circle("line", K.X(mb[1] + 5), K.Y(mb[2] + 5), 3 * K.sc)
      K.addHit(mb, "win", A_ME)
      right = right - 12
    end
    -- (3D | 2D: the flat map and back)
    local fb = K.R(right - 13, y + M, 13, 10)
    glass(fb, 5, st.flat and 0.55 or 0.4, st.flat and ACCENT or nil)
    K.bold(st.flat and "2D" or "3D", fb[1], fb[2] + 2.2, 4.4, WHITE, "center", fb[3])
    K.addHit(fb, "win", A_FLAT)
    right = right - 15
    if st.flat then return end
    -- (the compass: the needle points where north is on the screen)
    local cb = K.R(right - 10, y + M, 10, 10)
    glass(cb, 5)
    local c = st.cam
    local ax, ay = Rd.project(c.x, c.y, c.z)
    local nx, ny = Rd.project(c.x, c.y, c.z - 1)
    if ax and nx then
      local dx, dy = nx - ax, ny - ay
      local l = sqrt(dx * dx + dy * dy)
      if l > 0 then dx, dy = dx / l, dy / l end
      local cx, cy, r = K.X(cb[1] + 5), K.Y(cb[2] + 5), 3.6 * K.sc
      local px, py = -dy * r * 0.32, dx * r * 0.32
      K.col(BEAM)
      G.polygon("fill", cx + dx * r, cy + dy * r, cx + px, cy + py, cx - px, cy - py)
      K.col(WHITE, 0.85)
      G.polygon("fill", cx - dx * r, cy - dy * r, cx + px, cy + py, cx - px, cy - py)
    end
    K.addHit(cb, "win", A_NORTH)
  end

  function W.draw(body, clock)
    if not st.region then return end
    local dt = st.lastT and max(0, min(0.1, clock - st.lastT)) or 0
    st.lastT = clock
    if clock - st.liveAt >= 1 or clock < st.liveAt then
      st.liveAt = clock
      refreshLive()
    end
    stepCursor(dt)
    stepCamera(dt)
    local rect = st.rect
    rect.x, rect.y, rect.w, rect.h = K.X(body[1]), K.Y(body[2]), body[3] * K.sc, body[4] * K.sc
    local G = K.graphics()
    K.scissor(body)
    if st.flat then
      -- (the flat map: the camera's distance as how much of it shows, the cursor in the middle)
      local c = st.cam
      Rd.flatCamera(c.x, c.z, c.dist * 0.42, rect)
      st.three = false
      if not Rd.drawPicture(G, st.region, rect) then Rd.drawLand(G, st.region, rect) end
    else
      Rd.camera(st.cam, rect)
      st.three = Rd.draw(G, st.region, rect, clock, Rd.night(st.hour, st.minute), Rd.dusk(st.hour, st.minute))
    end
    drawPins(clock)
    drawCursor(clock)
    drawLabel()
    local compact = body[3] < 150 or body[4] < 110
    drawChips(body)
    drawCard(body, compact)
    if st.toast and not K.toast(st.toast, clock, K.R(body[1], body[2], body[3], body[4] - 34 - (opts.footer or 0)),
        UI.red, UI.green, UI.hud) then
      st.toast = nil
    end
  end

  start()
  return W
end
