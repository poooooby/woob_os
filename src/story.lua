-- Each game's story, for the News (FireRed / LeafGreen's Team Rocket and the Sevii Islands, Ruby /
-- Sapphire / Emerald's Magma, Aqua and the legends): each beat is the game's own flags and variables,
-- the ones the game's scripts set at that moment (DEVELOPMENT.md "The News's story" names each
-- script). Checked when one of those flags changes and on each new map (variables send no event),
-- never per frame. A beat reached while WoobOS watched gets its time and a notification; the beats a
-- save already had the first time it's checked are kept without one (no flood of old news).
-- Kept in the save (mod.save "story"), so it rewinds with it.
--
--   Sy = Story(engine, deps)  deps: save ; now() ; gameId() ; flag(name) ; var(name) ; species(name) -> sp ;
--                             notify(kind, data) ; head(s, { id, team, legend }) -> the News's headline
--   Sy.check(s)   the beats reached since the last check noted (the newest told by a notification)
--   Sy.on(name, ev)   "flag.changed" (a story flag) | "map.entered" -> Sy.check
--   Sy.reached(s) -> { { id, at, team, legend (species), order } }, story order (at 0: before WoobOS saw it)
--   Sy.crisis(s) -> "swing" | "drought" | "downpour" | nil (the weather while the legend is loose)
--   Sy.roamer(s) -> { sp, map } | nil (Latias / Latios, or Raikou / Entei / Suicune, out roaming: where
--        the game has it now)
--   Sy.game() -> the game's id
--   ids (FireRed / LeafGreen): pokedex, mtMoon, burglar, bill, ssAnne, hideout, fuji, snorlax, silph,
--        giovanni, champion, ruby, warehouse, sapphire, network, beast
--   ids (Ruby / Sapphire / Emerald): chimney, institute, orb, orbs, groudon, submarine, spaceCenter,
--        awakened, clash, cave, rayquaza, calm, champion, lati, frontier, tower

local EM = { emerald = true }
local RS = { ruby = true, sapphire = true }
local RSE = { ruby = true, sapphire = true, emerald = true }
local FRLG = { firered = true, leafgreen = true }
local ALL = { ruby = true, sapphire = true, emerald = true, firered = true, leafgreen = true }
local VERSION_TEAM = { emerald = "magma", ruby = "magma", sapphire = "aqua" }
local VERSION_LEGEND = { ruby = "GROUDON", sapphire = "KYOGRE" }

-- in story order. team / legend: one for every game, or a table by game. FireRed / LeafGreen's
-- (DEVELOPMENT.md names the map each one's script plays on): roaming = Raikou, Entei or Suicune out
-- roaming (no flag: the game's own roamer), kept once seen
local BEATS = {
  { id = "pokedex", games = FRLG, flag = "FLAG_SYS_POKEDEX_GET" },
  { id = "mtMoon", games = FRLG, flag = "FLAG_GOT_FOSSIL_FROM_MT_MOON", team = "rocket" },
  { id = "burglar", games = FRLG, flag = "FLAG_GOT_TM28_FROM_ROCKET", team = "rocket" },
  { id = "bill", games = FRLG, flag = "FLAG_HELPED_BILL_IN_SEA_COTTAGE" },
  { id = "ssAnne", games = FRLG, flag = "FLAG_GOT_HM01" },
  { id = "hideout", games = FRLG, flag = "FLAG_HIDE_CELADON_ROCKETS", team = "rocket" },
  { id = "fuji", games = FRLG, flag = "FLAG_RESCUED_MR_FUJI", team = "rocket" },
  { id = "snorlax", games = FRLG, flag = "FLAG_WOKE_UP_ROUTE_12_SNORLAX", legend = "SNORLAX" },
  { id = "silph", games = FRLG, flag = "FLAG_HIDE_SAFFRON_ROCKETS", team = "rocket" },
  { id = "giovanni", games = FRLG, flag = "FLAG_DEFEATED_LEADER_GIOVANNI", team = "rocket" },
  { id = "champion", games = FRLG, flag = "FLAG_SYS_GAME_CLEAR" },
  { id = "ruby", games = FRLG, flag = "FLAG_GOT_RUBY", team = "rocket" },
  { id = "warehouse", games = FRLG, flag = "FLAG_DEFEATED_ROCKETS_IN_WAREHOUSE", team = "rocket" },
  { id = "sapphire", games = FRLG, flag = "FLAG_RECOVERED_SAPPHIRE", team = "rocket" },
  { id = "network", games = FRLG, flag = "FLAG_SYS_CAN_LINK_WITH_RS" },
  { id = "beast", games = FRLG, roaming = true, roamer = true },
  { id = "chimney", games = RSE, flag = "FLAG_DEFEATED_EVIL_TEAM_MT_CHIMNEY", team = VERSION_TEAM },
  { id = "institute", games = RSE, var = "VAR_WEATHER_INSTITUTE_STATE", min = 1,
    team = { emerald = "aqua", ruby = "magma", sapphire = "aqua" } },
  { id = "orb", games = RS, flag = "FLAG_MT_PYRE_ORB_STOLEN", team = VERSION_TEAM },
  { id = "orbs", games = EM, var = "VAR_MT_PYRE_STATE", min = 1 },
  { id = "groudon", games = EM, flag = "FLAG_GROUDON_AWAKENED_MAGMA_HIDEOUT", legend = "GROUDON", team = "magma" },
  { id = "submarine", games = EM, flag = "FLAG_TEAM_AQUA_ESCAPED_IN_SUBMARINE", team = "aqua" },
  { id = "submarine", games = RS, var = "VAR_SLATEPORT_HARBOR_STATE", min = 2, team = VERSION_TEAM },
  { id = "spaceCenter", games = EM, var = "VAR_MOSSDEEP_CITY_STATE", min = 3, team = "magma" },
  { id = "awakened", games = EM, flag = "FLAG_KYOGRE_ESCAPED_SEAFLOOR_CAVERN", legend = "KYOGRE", team = "aqua" },
  { id = "awakened", games = RS, flag = "FLAG_LEGEND_ESCAPED_SEAFLOOR_CAVERN", legend = VERSION_LEGEND,
    team = VERSION_TEAM },
  { id = "clash", games = EM, var = "VAR_SOOTOPOLIS_CITY_STATE", min = 2, legend = "GROUDON" },
  { id = "cave", games = EM, var = "VAR_SOOTOPOLIS_CITY_STATE", min = 3 },
  { id = "cave", games = RS, var = "VAR_SOOTOPOLIS_STATE", min = 2, legend = VERSION_LEGEND },
  { id = "rayquaza", games = EM, var = "VAR_SKY_PILLAR_STATE", min = 1, legend = "RAYQUAZA" },
  { id = "calm", games = EM, var = "VAR_SKY_PILLAR_STATE", min = 2, legend = "RAYQUAZA" },
  { id = "calm", games = RS, flag = "FLAG_LEGENDARY_BATTLE_COMPLETED", legend = VERSION_LEGEND },
  { id = "champion", games = RSE, flag = "FLAG_SYS_GAME_CLEAR" },
  { id = "lati", games = RSE, flag = "FLAG_LATIOS_OR_LATIAS_ROAMING", roamer = true },
  { id = "frontier", games = EM, flag = "FLAG_SYS_FRONTIER_PASS" },
  { id = "tower", games = RS, flag = "FLAG_LANDMARK_BATTLE_TOWER" },
}
-- the flags whose change can mean a beat (a script sets flags all the time: only these look)
local WATCH = { FLAG_SYS_WEATHER_CTRL = true }
for _, b in ipairs(BEATS) do if b.flag then WATCH[b.flag] = true end end

return function(engine, deps)
  deps = deps or {}
  local Sy = { store = deps.save, now = deps.now or os.time, BEATS = BEATS, WATCH = WATCH }

  local loose
  local function data()
    local store = Sy.store
    local d = store and store:get("story") or loose
    if type(d) ~= "table" then
      d = {}
      if store then store:set("story", d) else loose = d end
    end
    d.seen = type(d.seen) == "table" and d.seen or {}
    return d
  end
  local function save(d) if Sy.store then Sy.store:set("story", d) end end

  local function game() return deps.gameId and deps.gameId() or "" end
  local function flag(name)
    local ok, on = pcall(deps.flag or error, name)
    return ok and on == true
  end
  local function var(name)
    local ok, v = pcall(deps.var or error, name)
    return ok and tonumber(v) or 0
  end
  local function pick(v, g)
    if type(v) == "table" then return v[g] end
    return v
  end
  local spCache = {}
  local function species(name)
    if not name then return nil end
    local hit = spCache[name]
    if hit == nil then
      local ok, sp = pcall(deps.species or error, name)
      hit = ok and tonumber(sp) or false
      spCache[name] = hit
    end
    return hit or nil
  end

  -- (Latias or Latios: the roamer the game made, else the one it will make -- Emerald's choice at the
  -- TV report, Ruby's Latios, Sapphire's Latias)
  local function roamerSp(s, g)
    local r = type(s) == "table" and type(s.roamer) == "table" and s.roamer or nil
    if r and tonumber(r.species) then return tonumber(r.species) end
    if FRLG[g] then return nil end
    if g == "emerald" then return species(var("VAR_ROAMER_POKEMON") == 0 and "LATIAS" or "LATIOS") end
    return species(g == "ruby" and "LATIOS" or "LATIAS")
  end
  local function legendOf(b, s, g)
    if b.roamer then return roamerSp(s, g) end
    return species(pick(b.legend, g))
  end

  local function roaming(s)
    local r = type(s) == "table" and type(s.roamer) == "table" and s.roamer or nil
    return r ~= nil and r.active == true and r.map ~= nil and tonumber(r.species) ~= nil
  end
  local function isReached(b, s)
    if b.roaming then return roaming(s) end
    if b.flag then return flag(b.flag) end
    return var(b.var) >= (b.min or 1)
  end

  -- the beats this game has, reached now (story order; a roamer's, once seen, stays)
  local function reachedNow(g, s, seen)
    local out = {}
    for i, b in ipairs(BEATS) do
      if b.games[g] and (isReached(b, s) or (b.roaming and seen and seen[b.id] ~= nil)) then out[#out + 1] = i end
    end
    return out
  end
  function Sy.game() return game() end

  function Sy.check(s)
    local g = game()
    if not (s and ALL[g]) then return end
    local d = data()
    local first = not d.init
    local newest
    for _, i in ipairs(reachedNow(g, s, d.seen)) do
      local id = BEATS[i].id
      if d.seen[id] == nil then
        d.seen[id] = first and 0 or Sy.now()
        if not first then newest = i end
      end
    end
    if first or newest then
      d.init = true
      save(d)
    end
    if newest and deps.notify then
      local b = BEATS[newest]
      local rec = { id = b.id, team = pick(b.team, g), legend = legendOf(b, s, g) }
      local okH, head = pcall(deps.head or error, s, rec)
      pcall(deps.notify, "story", { name = okH and head or b.id, sp = rec.legend, state = { story = "story." .. b.id } })
    end
  end

  function Sy.on(name, ev, s)
    if name == "flag.changed" then
      if not (type(ev) == "table" and WATCH[ev.name]) then return end
    elseif name ~= "map.entered" then
      return
    end
    Sy.check(s)
  end

  function Sy.reached(s)
    local g = game()
    local out = {}
    if not (s and ALL[g]) then return out end
    local seen = data().seen
    for _, i in ipairs(reachedNow(g, s, seen)) do
      local b = BEATS[i]
      out[#out + 1] = { id = b.id, at = tonumber(seen[b.id]) or 0, order = i, team = pick(b.team, g),
                        legend = legendOf(b, s, g) }
    end
    return out
  end

  -- the weather while the awakened legend is loose: Emerald's swings between drought and downpour
  -- round Sootopolis, Ruby's drought, Sapphire's rain (the game's own flag, set at the Seafloor Cavern)
  function Sy.crisis(s)
    local g = game()
    if not (s and RSE[g]) or not flag("FLAG_SYS_WEATHER_CTRL") then return nil end
    if g == "emerald" then return "swing" end
    return g == "ruby" and "drought" or "downpour"
  end

  -- Latias / Latios, or Raikou / Entei / Suicune, out roaming: where the game has it now (the
  -- Pokédex's Area shows the same)
  function Sy.roamer(s)
    local g = game()
    if not (s and ALL[g]) or not roaming(s) then return nil end
    if RSE[g] and not flag("FLAG_LATIOS_OR_LATIAS_ROAMING") then return nil end
    return { sp = tonumber(s.roamer.species), map = s.roamer.map }
  end

  return Sy
end
