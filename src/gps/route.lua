-- The GPS's route (FireRed / LeafGreen / Ruby / Sapphire / Emerald; Gold / Silver / Crystal): a waypoint set on the 3D map, the
-- shortest walk to it over src/gps/graph.lua's points (from the waypoint back: each point's steps to
-- it), the next warp or edge the field's arrow points at, and the line the map draws. The waypoint is
-- the save's own (mod.save "gps"): it goes back with the save.
--
-- The way is the story's: Surf only once the player can use it (else "surf"), and the obstacles (Gw.HMS:
-- Cut trees, Rock Smash rocks, Strength boulders; on Gen 2 whirlpools, waterfalls and the story's gates)
-- stand in the way until the player can pass them (a shortcut one opens is taken). Where the only way goes
-- through one the player can't pass yet, the route goes through it all the same and the line marks the spot
-- (Rt.needs: those bits).
--
--   Rt = route(engine, deps)  deps: graph (Gw) ; save (mod.save) ; session() ; can(s, key, entry) -> the
--                              player can use "SURF", or pass that Gw.HMS entry (an HM: the badge and a
--                              Pokémon that knows it) ; surfing() -> the player on the water now ; where() ->
--                              mapId, x, y, surfing, s (else the session's) ; inSection(mapId, sec) -> that
--                              map is in the waypoint's town (else mapDef(id)'s regionMapSectionId) ;
--                              notify(kind, data) ; log(fmt, ...)
--   Rt.set(spec) -> "ok" | "surf" | "none" | "here" | "busy"   spec = { map, x, y, name, sec (a town's
--       section: anywhere in it is there), region, wx, wz (where the map draws it) }; only "ok" keeps it
--   Rt.needs -> the obstacles the way needs the player can't pass yet (a mask of Gw.HMS's bits) ;
--   Rt.HMS -> Gw.HMS (each { bit, key, word })
--   Rt.clear() ; Rt.dest() -> the spec | nil ; Rt.load(s) (the save's, on its loading)
--   Rt.step(mapId, x, y) (each step and each map: arrived? the arrow's next warp)
--   Rt.target -> { on, map, x, y, dx, dy (the way out over an edge), dest (the waypoint itself) }
--   Rt.line(region) -> { n, x = {}, z = {}, gap = {}, hn, hx = {}, hz = {}, hk = {} } | nil   (world
--       units; gap: a stretch between these two points not on the map -- a cave, a building; hx / hz / hk:
--       the spots that need an HM the player can't use yet, and which), kept while nothing moved
--   Rt.chain() -> the maps on the way ; Rt.spotAt(region, wx, wz) -> mapId, x, y | nil

local floor, max, min, abs, huge = math.floor, math.max, math.min, math.abs, math.huge

local NEAR = 8          -- a waypoint off the path (a roof, the sea): the nearest tile it can stand on this near
local ARRIVE = 2        -- this many steps from it (not a town): there

return function(engine, deps)
  deps = deps or {}
  local Gw = deps.graph
  local bor, band = Gw.bor, Gw.band
  local Rt = { target = { on = false, map = nil, x = 0, y = 0, dx = 0, dy = 0, dest = false }, needs = 0, HMS = Gw.HMS }
  local function log(...) if deps.log then deps.log(...) end end
  local function session() return deps.session and deps.session() or nil end

  local dest = nil
  local sols = {}          -- [mode key] = { dist, succ, mk } (solved for the waypoint, as asked)
  local mode = { surf = false, hms = 0, have = 0 }
  local lineCache = { key = nil, n = 0, x = {}, z = {}, gap = {}, hn = 0, hx = {}, hz = {}, hk = {} }

  local function forget()
    for k in pairs(sols) do sols[k] = nil end
    lineCache.key = nil
  end

  -- ------- the save's

  local function store() return deps.save end
  local function keep()
    local st = store()
    if not st then return end
    pcall(st.set, st, "gps", { dest = dest })
  end
  function Rt.load()
    dest = nil
    Rt.target.on, Rt.needs = false, 0
    forget()
    local st = store()
    local ok, d = pcall(function() return st and st:get("gps") end)
    if ok and type(d) == "table" and type(d.dest) == "table" and type(d.dest.map) == "string" then
      dest = d.dest
    end
  end
  function Rt.dest() return dest end
  function Rt.clear()
    dest = nil
    Rt.target.on, Rt.needs = false, 0
    forget()
    keep()
  end

  -- ------- the steps to the waypoint from every point (Dijkstra, from the waypoint back), for a mode:
  -- Surf or not, and the HMs the way may use

  local HK, HV, hn = {}, {}, 0
  local function hpush(k, v)
    hn = hn + 1
    local i = hn
    HK[i], HV[i] = k, v
    while i > 1 do
      local p = floor(i / 2)
      if HV[p] <= HV[i] then break end
      HK[p], HK[i], HV[p], HV[i] = HK[i], HK[p], HV[i], HV[p]
      i = p
    end
  end
  local function hpop()
    if hn == 0 then return nil end
    local k, v = HK[1], HV[1]
    HK[1], HV[1] = HK[hn], HV[hn]
    HK[hn], HV[hn] = nil, nil
    hn = hn - 1
    local i = 1
    while true do
      local l, r = i * 2, i * 2 + 1
      local m = i
      if l <= hn and HV[l] < HV[m] then m = l end
      if r <= hn and HV[r] < HV[m] then m = r end
      if m == i then break end
      HK[m], HK[i], HV[m], HV[i] = HK[i], HK[m], HV[i], HV[m]
      i = m
    end
    return k, v
  end

  -- (a way's length in a mode, and the HMs that length takes)
  local function costOf(e, surf, hms)
    local plain = surf and Gw.ES[e] or Gw.EL[e]
    local thru = surf and Gw.EHS[e] or Gw.EHL[e]
    local need = (surf and Gw.EMS[e] or Gw.EML[e]) or 0
    local c, m = nil, 0
    if plain and plain >= 0 then c = plain end
    if hms ~= 0 and thru and thru >= 0 and Gw.covers(hms, need) and (c == nil or thru < c) then c, m = thru, need end
    return c, m
  end

  local function solve(surf, hms)
    local key = hms * 2 + (surf and 1 or 0)
    local sol = sols[key]
    if sol then return sol end
    sol = { dist = {}, succ = {}, mk = {}, surf = surf, hms = hms }
    sols[key] = sol
    local dist, succ, mk = sol.dist, sol.succ, sol.mk
    hn = 0
    local dmi = Gw.mi[dest.map]
    local rec = Gw.tiles(dest.map)
    if not (dmi and rec) then return sol end
    local di = dest.y * rec.w + dest.x
    for _, a in ipairs(Gw.arrivals[dmi] or {}) do
      local got, gm
      Gw.walk(rec, Gw.NX[a], Gw.NY[a], false, surf, function(i, d, m)
        if i == di then
          got, gm = d, m
          return true
        end
      end, nil, nil, hms)
      if got then
        dist[a], succ[a], mk[a] = got, 0, gm or 0
        hpush(a, got)
      end
    end
    local EA, into = Gw.EA, Gw.into
    while hn > 0 do
      local n, d = hpop()
      if d <= (dist[n] or huge) then
        for _, e in ipairs(into[n] or {}) do
          local c, m = costOf(e, surf, hms)
          if c then
            local u = EA[e]
            local nd = d + c
            if dist[u] == nil or nd < dist[u] then
              dist[u], succ[u], mk[u] = nd, n, m
              hpush(u, nd)
            end
          end
        end
      end
    end
    return sol
  end

  -- ------- from where the player is: the best way on

  local exitTiles = {}   -- [mi] = { [tile] = { node, ... } }
  local function exitsOn(mi, rec)
    local t = exitTiles[mi]
    if t then return t end
    t = {}
    for _, x in ipairs(Gw.exits[mi] or {}) do
      local i = Gw.NY[x] * rec.w + Gw.NX[x]
      t[i] = t[i] or {}
      t[i][#t[i] + 1] = x
    end
    exitTiles[mi] = t
    return t
  end
  -- (a map left out of the graph -- a house with one way out: its warps straight to where they go)
  local looseExits = {}
  local function looseOn(rec)
    local t = looseExits[rec.id]
    if t then return t end
    t = {}
    for i, wi in pairs(rec.warp) do
      local wp = rec.def.warps and rec.def.warps[wi]
      local m, x, y = wp and Gw.destOf(wp)
      local a = m and Gw.arrivalAt(m, x, y)
      if a then t[i] = a end
    end
    looseExits[rec.id] = t
    return t
  end

  local best = { total = huge, i = nil, node = nil, mk = 0 }
  -- the cheapest way on from a tile in a mode -> its total steps (nil: none), filling `best`
  local function bestFrom(mapId, x, y, surfing, sol, parents)
    best.total, best.i, best.node, best.mk = huge, nil, nil, 0
    local rec = Gw.tiles(mapId)
    if not (rec and dest and sol) then return nil end
    local dist = sol.dist
    local mi = Gw.mi[mapId]
    local exits = mi and exitsOn(mi, rec) or nil
    local loose = not mi and looseOn(rec) or nil
    local di = mapId == dest.map and (dest.y * rec.w + dest.x) or nil
    local i0 = y * rec.w + x
    Gw.walk(rec, x, y, surfing, sol.surf, function(i, d, m)
      if d >= best.total then return true end
      if i == di then
        best.total, best.i, best.node, best.mk = d, i, 0, m or 0
        return true
      end
      local list = exits and exits[i]
      if list then
        for _, n in ipairs(list) do
          local c = dist[n]
          if c then
            local tot = d + c + ((i == i0 and Gw.NK[n] == 1) and 2 or 0)
            if tot < best.total then best.total, best.i, best.node, best.mk = tot, i, n, m or 0 end
          end
        end
      end
      local a = loose and loose[i]
      if a and dist[a] and i ~= i0 then
        local tot = d + 1 + dist[a]
        if tot < best.total then best.total, best.i, best.node, best.mk = tot, i, -a, m or 0 end
      end
    end, nil, parents, sol.hms)
    if best.i == nil then return nil end
    return best.total
  end

  local function where()
    if deps.where then return deps.where() end
    local s = session()
    if not (s and type(s.map) == "string") then return nil end
    local surfing = deps.surfing and deps.surfing() or false
    return s.map, tonumber(s.x) or 0, tonumber(s.y) or 0, surfing, s
  end
  local function can(s, key, h)
    if not deps.can then return false end
    local ok, yes = pcall(deps.can, s, key, h)
    return ok and yes == true
  end
  -- (what the player can use now: Surf, and the HMs' mask; asked of the game again a few seconds on, or at
  -- once after Rt.refresh -- a new map: the game's own checks make garbage, and a step comes four times a second)
  local ab = { at = nil, surf = false, hms = 0 }
  local ABILITY_FOR = 3
  local function clock() return love and love.timer and love.timer.getTime() or os.clock() end
  local function abilities(s)
    local t = clock()
    if ab.at and t - ab.at < ABILITY_FOR and t >= ab.at then return ab.surf, ab.hms end
    local hms = 0
    for _, h in ipairs(Gw.HMS) do
      if can(s, h.key, h) then hms = bor(hms, h.bit) end
    end
    ab.at, ab.surf, ab.hms = t, can(s, "SURF"), hms
    return ab.surf, ab.hms
  end
  function Rt.refresh() ab.at = nil end
  -- (the mode a way is found in: the player's own; else through the HMs they can't use yet, marked)
  local function pick(m, px, py, surfing, s)
    local surf, have = abilities(s)
    mode.have = have
    local sol = solve(surf, have)
    if bestFrom(m, px, py, surfing, sol) then
      mode.surf, mode.hms = surf, have
      return sol
    end
    if have ~= Gw.HM_ALL then
      sol = solve(surf, Gw.HM_ALL)
      if bestFrom(m, px, py, surfing, sol) then
        mode.surf, mode.hms = surf, Gw.HM_ALL
        return sol
      end
    end
    if not surf and bestFrom(m, px, py, surfing, solve(true, Gw.HM_ALL)) then return nil, "surf" end
    return nil, "none"
  end
  local function current() return solve(mode.surf, mode.hms) end

  -- (the arrow's mark: the tile, and for an edge the way over it)
  local function aim(mapId, rec)
    local t = Rt.target
    if not best.i then
      t.on = false
      return
    end
    t.on, t.map = true, mapId
    t.x, t.y = best.i % rec.w, floor(best.i / rec.w)
    t.dx, t.dy, t.dest = 0, 0, best.node == 0
    local n = best.node
    if n and n > 0 and Gw.NK[n] == 2 then
      if t.y == 0 then t.dy = -1 elseif t.y == rec.h - 1 then t.dy = 1
      elseif t.x == 0 then t.dx = -1 else t.dx = 1 end
    end
  end

  local function ensure()
    if not dest then return false end
    return Gw.ready()
  end
  Rt.ensure = ensure

  -- (the HMs the way from here takes: the player's walk on, then each point's)
  local function needsFrom(sol)
    local need = best.mk or 0
    local node = best.node
    if node and node < 0 then node = -node end
    local guard = 0
    while node and node > 0 and guard < 600 do
      guard = guard + 1
      need = bor(need, sol.mk[node] or 0)
      local nxt = sol.succ[node]
      if not nxt or nxt == 0 then break end
      node = nxt
    end
    -- (those the player can use: not needed)
    return band(need, Gw.HM_ALL - band(mode.have, Gw.HM_ALL))
  end

  -- (a waypoint's own tile, or the nearest one near it a player can stand on)
  local function standable(rec, x, y)
    local c = rec.cls[y * rec.w + x]
    return c == Gw.LAND or c == Gw.WATER
  end
  local function settle(spec)
    local rec = Gw.tiles(spec.map)
    if not rec then return nil end
    local x, y = max(0, min(rec.w - 1, floor(spec.x))), max(0, min(rec.h - 1, floor(spec.y)))
    if standable(rec, x, y) and rec.cls[y * rec.w + x] == Gw.LAND then return x, y end
    local bx, by, bd, water
    for r = 1, NEAR do
      for oy = -r, r do
        for ox = -r, r do
          if max(abs(ox), abs(oy)) == r then
            local tx, ty = x + ox, y + oy
            if tx >= 0 and ty >= 0 and tx < rec.w and ty < rec.h and standable(rec, tx, ty) then
              local land = rec.cls[ty * rec.w + tx] == Gw.LAND
              local d = ox * ox + oy * oy
              if (land and (water or not bd or d < bd)) or (not land and not bd) then
                bx, by, bd, water = tx, ty, d, not land
              end
            end
          end
        end
      end
      if bd and not water then break end
    end
    if bd then return bx, by end
    if standable(rec, x, y) then return x, y end
    return nil
  end

  local function arrived(mapId, x, y)
    if not dest then return false end
    if dest.sec ~= nil and deps.inSection then
      local okS, yes = pcall(deps.inSection, mapId, dest.sec)
      if okS and yes then return true end
    elseif dest.sec ~= nil and deps.mapDef then
      local def = deps.mapDef(mapId)
      if def and tonumber(def.regionMapSectionId) == tonumber(dest.sec) then return true end
    end
    return mapId == dest.map and abs(x - dest.x) + abs(y - dest.y) <= ARRIVE
  end

  function Rt.set(spec)
    if not Gw.ready() then return "busy" end
    if type(spec) ~= "table" or type(spec.map) ~= "string" or not Gw.mi[spec.map] then return "none" end
    local x, y = settle(spec)
    if not x then return "none" end
    local old, oldNeeds = dest, Rt.needs
    dest = { map = spec.map, x = x, y = y, name = spec.name, sec = spec.sec, region = spec.region,
             wx = spec.wx, wz = spec.wz, place = spec.place }
    forget()
    ab.at = nil
    local m, px, py, surfing, s = where()
    local function back(status)
      dest, Rt.needs = old, oldNeeds
      forget()
      return status
    end
    if m and arrived(m, px, py) then return back("here") end
    if not m then return back("none") end
    local okP, sol, why = pcall(pick, m, px, py, surfing, s)
    if not okP then
      log("the GPS's route failed: %s", tostring(sol))
      return back("none")
    end
    if not sol then return back(why or "none") end
    Rt.needs = needsFrom(sol)
    keep()
    Rt.step(m, px, py)
    return "ok"
  end

  -- each step: there yet? else the warp or edge the arrow points at
  function Rt.step(mapId, x, y)
    local t = Rt.target
    if not dest then
      t.on = false
      return
    end
    if not ensure() then return end
    mapId = mapId or select(1, where())
    if not mapId then return end
    if arrived(mapId, x, y) then
      local name = dest.name
      Rt.clear()
      if deps.notify then pcall(deps.notify, "gps", { name = name or "?" }) end
      return "arrived"
    end
    local _, _, _, surfing, s = where()
    -- (the mode again: an HM learnt on the way opens its shortcuts)
    local okP, sol = pcall(pick, mapId, x, y, surfing, s)
    if okP and sol then
      Rt.needs = needsFrom(sol)
      local rec = Gw.tiles(mapId)
      if rec then aim(mapId, rec) else t.on = false end
    else
      t.on = false
    end
  end

  -- ------- the line on the map

  local tiles = {}
  local function placed(region, mapId)
    local W = region and region.world
    return W and W.byId and W.byId[mapId] or nil
  end
  function Rt.line(region)
    if not (dest and region and region.world) then return nil end
    if not ensure() then return nil end
    local m, px, py, surfing, s = where()
    if not m then return nil end
    local key = ("%s|%s:%d:%d|%s:%d:%d"):format(tostring(region.id), m, px, py, dest.map, dest.x, dest.y)
    if lineCache.key == key then return lineCache end
    local sol = pick(m, px, py, surfing, s)
    if not sol then return nil end
    local L = lineCache
    L.key, L.n, L.hn = key, 0, 0
    local MT = region.unit or 16
    local gapNext = false
    local function add(mapId, i, w)
      local pm = placed(region, mapId)
      if not pm then
        gapNext = L.n > 0
        return
      end
      local tx, ty = i % w, floor(i / w)
      L.n = L.n + 1
      L.x[L.n], L.z[L.n] = (pm.x + tx + 0.5) / MT, (pm.y + ty + 0.5) / MT
      L.gap[L.n] = gapNext
      gapNext = false
    end
    -- (an HM the player can't use yet on the way: its spot, or a cave's door the line goes in by)
    local function needAt(mapId, i, w, kind)
      local pm = placed(region, mapId)
      L.hn = L.hn + 1
      if pm then
        L.hx[L.hn], L.hz[L.hn] = (pm.x + i % w + 0.5) / MT, (pm.y + floor(i / w) + 0.5) / MT
      elseif L.n > 0 then
        L.hx[L.hn], L.hz[L.hn] = L.x[L.n], L.z[L.n]
      else
        L.hn = L.hn - 1
        return
      end
      L.hk[L.hn] = kind
    end
    -- (a walk on one map from a tile to another, its corners only)
    local function segment(mapId, x, y, surf0, toI)
      local rec = Gw.tiles(mapId)
      if not rec then return end
      local onMap = placed(region, mapId) ~= nil
      Gw.walk(rec, x, y, surf0, sol.surf, function(i) return i == toI end, nil, true, sol.hms)
      Gw.pathTo(toI, tiles)
      local n = #tiles
      for k = 1, n do
        local i = tiles[k]
        local o = rec.obst[i]
        -- (a waterfall only when the way climbs it)
        if o and rec.upOnly and rec.upOnly[i] and not (k > 1 and tiles[k - 1] == i + rec.w) then o = nil end
        if o and band(mode.have, o) == 0 then needAt(mapId, i, rec.w, o) end
        if onMap then
          local keepIt = k == 1 or k == n
          if not keepIt then
            local a, b = tiles[k - 1], tiles[k + 1]
            keepIt = (i - a) ~= (b - i)
          end
          if keepIt then add(mapId, i, rec.w) end
        end
      end
      if not onMap then gapNext = L.n > 0 end
    end
    local succ = sol.succ
    if not bestFrom(m, px, py, surfing, sol, true) then return nil end
    local node = best.node
    segment(m, px, py, surfing, best.i)
    -- (each point to the next: from an arrival, the walk to the next point on its map or to the waypoint;
    -- an exit's to where it leads, and a ride between arrivals, aren't walked)
    if node and node < 0 then node = -node end
    local guard = 0
    while node and node > 0 and guard < 600 do
      guard = guard + 1
      local nxt = succ[node]
      if nxt == nil then break end
      if Gw.NK[node] == 3 then
        -- (a ride through a gate the player can't pass yet: its sign where it leaves)
        local gm = sol.mk[node] or 0
        if gm ~= 0 and nxt ~= 0 and Gw.NM[nxt] ~= Gw.NM[node] then
          local am = Gw.ids[Gw.NM[node]]
          local rec = Gw.tiles(am)
          for _, h in ipairs(Gw.HMS) do
            if rec and band(gm, h.bit) ~= 0 and band(mode.have, h.bit) == 0 then
              needAt(am, Gw.NY[node] * rec.w + Gw.NX[node], rec.w, h.bit)
            end
          end
        end
        if nxt == 0 or Gw.NM[nxt] == Gw.NM[node] then
          local am = Gw.ids[Gw.NM[node]]
          local rec = Gw.tiles(am)
          if rec then
            local toI = nxt == 0 and (dest.y * rec.w + dest.x) or (Gw.NY[nxt] * rec.w + Gw.NX[nxt])
            segment(am, Gw.NX[node], Gw.NY[node], false, toI)
          end
        else
          gapNext = L.n > 0
        end
      end
      if nxt == 0 then break end
      node = nxt
    end
    return L.n > 1 and L or nil
  end

  -- the maps the route goes through, in order, from where the player is (tests; the line's own order)
  function Rt.chain()
    if not (dest and ensure()) then return nil end
    local m, px, py, surfing, s = where()
    if not m then return nil end
    local sol = pick(m, px, py, surfing, s)
    if not (sol and bestFrom(m, px, py, surfing, sol)) then return nil end
    local out = { m }
    local node = best.node
    if node and node < 0 then node = -node end
    local guard = 0
    while node and node > 0 and guard < 600 do
      guard = guard + 1
      local id = Gw.ids[Gw.NM[node]]
      if out[#out] ~= id then out[#out + 1] = id end
      local nxt = sol.succ[node]
      if not nxt or nxt == 0 then break end
      node = nxt
    end
    return out
  end

  function Rt.spotAt(region, wx, wz)
    local W = region and region.world
    if not W then return nil end
    local MT = region.unit or 16
    local tx, ty = floor(wx * MT), floor(wz * MT)
    for _, m in ipairs(W.maps or {}) do
      if tx >= m.x and ty >= m.y and tx < m.x + m.w and ty < m.y + m.h and not m.id:find("_CONNECTION$") then
        return m.id, tx - m.x, ty - m.y
      end
    end
    return nil
  end

  return Rt
end
