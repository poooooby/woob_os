-- The daily swarm: one route a day where one species appears far more often than it should (the
-- News reports it, a Challenge may ask for one). Picked from the game's own wild tables: a route with
-- land encounters (the further ones as the badges allow), a species found on land elsewhere in this
-- game but not on that route, at that route's own levels. The same all day for a save (its seed and
-- the device's local date); worked out once a day, nothing saved. main.lua wraps the engine's
-- encounter.species hook with Sw.encounter: on that route, on land, CHANCE of the encounters become
-- the swarm's (our own dice, not the game's). Settings "swarms" turns it off.
--
--   Sw = Swarm(engine, deps)  deps: seed(s) ; day(t) (local days) ; now() ; badges(s) ; on() ; session()
--   Sw.today(s) -> { day, key ("group:num"), mapId, species, min, max } | nil
--   Sw.species() -> today's species id (the session's) or nil ; Sw.on()
--   Sw.encounter(enc, ctx) -> enc (the swarm's species on its route, sometimes)
--   Sw.CHANCE

local floor, max, min = math.floor, math.max, math.min
local M31 = 2147483647
local CHANCE = 0.4

local function nextRand(st)
  st.x = (st.x * 48271) % M31
  return st.x
end

return function(engine, deps)
  deps = deps or {}
  local Sw = { CHANCE = CHANCE, now = deps.now or os.time, rng = deps.rng }

  function Sw.on() return not deps.on or deps.on() ~= false end

  -- the game's routes with land encounters, in their own order (keys sorted by group, then number)
  local routes, landSpecies
  local function load()
    if routes then return routes end
    local E, MC = engine("src.core.game3.encounters"), engine("src.import.gba.map_catalog")
    if not (E and MC) then return nil end
    pcall(E.ensureLoaded)
    pcall(MC.ensureRegistry)
    local list, everywhere = {}, {}
    for key, t in pairs(E._tables or {}) do
      local area = type(t) == "table" and (t.land or t.grass)
      local g, n = tostring(key):match("^(%d+):(%d+)$")
      if area and area.slots and g then
        local here = {}
        for _, sl in ipairs(area.slots) do
          local sp = tonumber(sl.species)
          if sp then
            here[sp] = true
            everywhere[sp] = true
          end
        end
        local okI, id = pcall(MC.mapIdFor, tonumber(g), tonumber(n))
        if okI and id and tostring(id):find("ROUTE", 1, true) then
          local lo, hi = 100, 1
          for _, sl in ipairs(area.slots) do
            lo = min(lo, tonumber(sl.minLevel) or lo)
            hi = max(hi, tonumber(sl.maxLevel) or hi)
          end
          list[#list + 1] = { key = tostring(key), mapId = tostring(id), g = tonumber(g), n = tonumber(n), here = here,
                              min = lo, max = max(lo, hi) }
        end
      end
    end
    table.sort(list, function(a, b) if a.g ~= b.g then return a.g < b.g end return a.n < b.n end)
    local sp = {}
    for s in pairs(everywhere) do sp[#sp + 1] = s end
    table.sort(sp)
    routes, landSpecies = list, sp
    return routes
  end

  local cache = { day = nil, seed = nil, badges = nil, pick = nil }
  function Sw.today(s, now)
    if not Sw.on() or not s then return nil end
    now = now or Sw.now()
    local day = deps.day and deps.day(now) or floor(now / 86400)
    local seed = tonumber(deps.seed and deps.seed(s)) or 1
    local b = max(0, floor(tonumber(deps.badges and deps.badges(s)) or 0))
    if cache.day == day and cache.seed == seed and cache.badges == b then return cache.pick end
    cache.day, cache.seed, cache.badges, cache.pick = day, seed, b, nil
    local list = load()
    if not list or #list == 0 or #landSpecies == 0 then return nil end
    local dice = { x = (seed * 3571 + day * 65537 + 11) % M31 }
    if dice.x == 0 then dice.x = 1 end
    for _ = 1, 3 do nextRand(dice) end
    -- (the routes open up with the badges: the first third at the start, all of them by the eighth)
    local reach = max(1, min(#list, floor(#list * (0.34 + 0.66 * min(8, b) / 8) + 0.5)))
    local r = list[nextRand(dice) % reach + 1]
    local choices = {}
    for _, sp in ipairs(landSpecies) do if not r.here[sp] then choices[#choices + 1] = sp end end
    if #choices == 0 then return nil end
    cache.pick = { day = day, key = r.key, mapId = r.mapId, species = choices[nextRand(dice) % #choices + 1],
                   min = r.min, max = r.max }
    return cache.pick
  end
  function Sw.species()
    local p = Sw.today(deps.session and deps.session())
    return p and p.species or nil
  end

  local function roll()
    if Sw.rng then return Sw.rng() end
    local R = love and love.math and love.math.random
    return R and R() or math.random()
  end
  -- the encounter.species hook's turn: the swarm's species, on its route, on land, sometimes
  function Sw.encounter(enc, ctx)
    if type(enc) ~= "table" or type(ctx) ~= "table" or ctx.terrain == "water" then return enc end
    local p = Sw.today(deps.session and deps.session())
    if not p then return enc end
    local MC = engine("src.import.gba.map_catalog")
    local ok, g, n = pcall(MC and MC.groupNumFor or error, ctx.mapId)
    if not (ok and g and n) then return enc end
    if tostring(g) .. ":" .. tostring(n) ~= p.key then return enc end
    if roll() >= CHANCE then return enc end
    local lo, hi = p.min, p.max
    local level = lo + floor(roll() * (hi - lo + 1))
    return { species = p.species, level = min(hi, max(lo, level)) }
  end

  return Sw
end
