-- The Game Boy games' side of the play-tied apps: the daily swarm's routes (the game's own wild tables),
-- a place's name, where the player is, and the game's events turned into the shape the journal
-- (src/journal.lua) reads (written for Gen 3's): the battles (Gen 2 raises its start and end twice, from the
-- battle and its screen: once here), a trainer's team, a Gym Leader, each hit and knockout, a catch, a
-- hatch, an evolution, a level, a step, a new map, an item used (Gen 1's Bag), and a Badge (these games
-- raise no event for one: the count is watched once a second).
--
--   Pl = play(host, Gd)
--   Pl.routes() -> list, species   (src/swarm.lua's deps.routes)
--   Pl.place(mapId) -> its name ; Pl.mapNow(s) -> the map the player is on
--   Pl.attach(mod, journal) (the events) ; Pl.tick(s) (once a second: a new Badge)

local floor, max, min = math.floor, math.max, math.min

-- the Gym Leaders, by their trainer ids / classes (Gen 1 "OPP_BROCK", Gen 2 "FALKNER")
local LEADERS = {}
for _, n in ipairs({ "BROCK", "MISTY", "LT_SURGE", "ERIKA", "KOGA", "SABRINA", "BLAINE", "GIOVANNI", "FALKNER",
                     "BUGSY", "WHITNEY", "MORTY", "PRYCE", "JASMINE", "CHUCK", "CLAIR", "JANINE", "BLUE" }) do
  LEADERS[n] = true
end

return function(H, Gd)
  local engine = H.engine
  local gen = H.gen
  local Pl = {}

  -- ------- the swarm's routes: the game's routes with grass, in the order the player reaches them
  local routes, species
  function Pl.routes()
    if routes then return routes, species end
    local d = Gd.data()
    if not d then return nil end
    local list, everywhere = {}, {}
    local function addRoute(mapId, slots)
      local here, lo, hi = {}, 100, 1
      for _, sl in ipairs(slots) do
        -- (the game's own Pokémon only: another mod may add others to these tables)
        local sp = sl.species
        if sp and Gd.def(sp) then
          here[sp], everywhere[sp] = true, true
          local lv = tonumber(sl.level) or 5
          lo, hi = min(lo, lv), max(hi, lv)
        end
      end
      local n = tonumber(tostring(mapId):match("^ROUTE_(%d+)$"))
      if n and next(here) then
        -- (Gen 2: Johto's routes, 29 to 46, before Kanto's)
        local order = gen == 2 and (n >= 29 and n - 29 or n + 100) or n
        list[#list + 1] = { key = tostring(mapId), mapId = tostring(mapId), here = here, min = lo, max = max(lo, hi),
                            order = order }
      end
    end
    if gen == 2 then
      local E = d.gen2Encounters or {}
      for mapId, t in pairs(E.grass or {}) do
        local slots = {}
        for _, part in pairs(type(t) == "table" and t.slots or {}) do
          for _, sl in ipairs(part) do slots[#slots + 1] = sl end
        end
        addRoute(mapId, slots)
      end
    else
      for mapId, t in pairs(d.encounters or {}) do
        local g = type(t) == "table" and t.grass
        if g and g.slots then addRoute(mapId, g.slots) end
      end
    end
    table.sort(list, function(a, b) return a.order < b.order end)
    local sp = {}
    for s in pairs(everywhere) do sp[#sp + 1] = s end
    table.sort(sp, function(a, b) return Gd.dex(a) < Gd.dex(b) end)
    if #list > 0 then routes, species = list, sp end
    return list, sp
  end

  -- ------- places
  local names = {}
  function Pl.place(mapId)
    if not mapId then return "?" end
    local got = names[mapId]
    if got then return got end
    local d = Gd.data()
    local name
    if gen == 2 then
      local Nests = engine("src.core.gen2.Nests")
      local m = d and d.gen2Maps and d.gen2Maps[mapId]
      local ok, lm = pcall(Nests and Nests.landmark or error, d, m and m.landmark)
      name = ok and type(lm) == "table" and lm.name or nil
    else
      local loc = d and d.field and d.field.townMap and d.field.townMap.locations and d.field.townMap.locations[mapId]
      name = loc and loc.name or nil
    end
    name = name or tostring(mapId):gsub("_%d*F$", ""):gsub("_", " ")
    got = Gd.title(tostring(name):gsub("\n", " "))
    names[mapId] = got
    return got
  end
  function Pl.mapNow(s)
    if not s then return nil end
    if gen == 2 then
      local p = s.position
      return p and (p.mapId or p.map) or nil
    end
    return s.player and s.player.map or nil
  end

  -- ------- the events, as the journal reads them

  local function species(b)
    if type(b) ~= "table" then return nil end
    if type(b.species) == "string" then return b.species end
    if type(b.mon) == "table" then return b.mon.species end
    return nil
  end
  local fightKind, fightName, fightLeader, startAt, endAt = nil, nil, false, -10, -10
  local function now() return love and love.timer and love.timer.getTime() or os.clock() end
  local function sideOf(battle, battler)
    if type(battle) ~= "table" then return nil end
    local e = battle.enemy
    if battler ~= nil and (battler == e or (type(e) == "table" and battler == e.mon)) then return "enemy" end
    return "player"
  end
  local function trainerOf(ev)
    local b = ev.battle
    local t = ev.trainer or (type(b) == "table" and b.trainer) or nil
    return type(t) == "table" and t or nil
  end
  local function leaderOf(ev)
    local b = ev.battle
    if type(b) == "table" and b.isGymLeader then return true end
    local id = tostring(ev.trainerId or ""):gsub("^OPP_", ""):upper()
    if LEADERS[id] then return true end
    local t = trainerOf(ev)
    local cls = t and tostring(t.className or t.class or t.id or ""):gsub("^OPP_", ""):upper()
    return cls ~= nil and LEADERS[cls] == true
  end

  local translate = {}
  translate["battle.started"] = function(ev)
    -- (once: Gen 2 raises it from the battle and again from its screen)
    local t = now()
    if t - startAt < 2 then return nil end
    startAt = t
    local kind = ev.kind or "trainer"
    local b = type(ev.battle) == "table" and ev.battle or {}
    local tr = trainerOf(ev)
    fightKind = kind
    fightLeader = leaderOf(ev)
    fightName = tr and (tr.name or tr.className) or (ev.trainerId and tostring(ev.trainerId):gsub("^OPP_", "")) or nil
    local foe = {}
    for _, m in ipairs(tr and (tr.party or tr.mons) or {}) do
      if type(m) == "table" and m.species then foe[#foe + 1] = { species = m.species } end
    end
    return { kind = kind, battle = { wild = kind == "wild", link = kind == "link",
                                     player = { species = species(b.player) }, enemy = { species = species(b.enemy) or ev.species },
                                     foeParty = foe } }
  end
  translate["battle.ended"] = function(ev)
    local t = now()
    if t - endAt < 2 then return nil end
    endAt = t
    local kind = fightKind or "wild"
    local b = type(ev.battle) == "table" and ev.battle or {}
    return { result = ev.result, battle = { wild = kind == "wild", link = kind == "link", trainerName = fightName,
                                            trainerClassName = fightName, trainerClass = fightLeader and 1 or 0,
                                            turn = tonumber(b.turn) or tonumber(b.turnCount) or 0 } }
  end
  translate["battle.damage_dealt"] = function(ev)
    local tside = sideOf(ev.battle, ev.target)
    local uside = tside == "enemy" and "player" or "enemy"
    return { targetId = tside == "enemy" and 2 or 1, user = { side = uside, species = species(ev.user) },
             move = { id = ev.moveId or (type(ev.move) == "table" and ev.move.id) }, moveId = ev.moveId,
             typeMult = ev.typeMult, crit = ev.crit, battle = ev.battle }
  end
  translate["battle.battler_switched"] = function(ev)
    local side = sideOf(ev.battle, ev.battler)
    return { sideName = side, speciesId = species(ev.battler), battler = { species = species(ev.battler) } }
  end
  translate["battle.fainted"] = function(ev)
    local side = sideOf(ev.battle, ev.battler)
    return { sideName = side, battlerId = side == "enemy" and 2 or 1, battler = { species = species(ev.battler), side = side },
             battle = ev.battle }
  end
  translate["pokemon.caught"] = function(ev)
    return { speciesId = ev.species or (type(ev.mon) == "table" and ev.mon.species), mon = ev.mon, isNew = ev.isNew }
  end
  translate["egg.hatched"] = function(ev) return { mon = ev.mon, species = ev.species } end
  translate["pokemon.evolved"] = function(ev)
    return { fromSpeciesId = ev.fromSpecies, toSpeciesId = ev.toSpecies, mon = ev.mon }
  end
  translate["pokemon.level_up"] = function(ev) return ev end
  translate["map.entered"] = function(ev) return { mapId = ev and ev.mapId } end
  translate["world.stepped"] = function() return true end

  local Jr = nil
  function Pl.attach(mod, journal)
    Jr = journal
    for name, f in pairs(translate) do
      mod.events:on(name, function(ev)
        if not Jr then return end
        local ok, out = pcall(f, type(ev) == "table" and ev or {})
        if ok and out then
          if out == true then out = nil end
          pcall(Jr.on, name, out)
        end
      end)
    end
    -- (an item used: Gen 1's Bag has the hook; Gen 2 none)
    if gen == 1 then
      mod.hooks:wrap("item.use", function(nxt, ...)
        local a, b, c = nxt(...)
        if a and Jr then pcall(Jr.on, "item.used") end
        return a, b, c
      end)
    end
  end

  -- a new Badge (the count up since last time): the journal's Badge flag
  local lastBadges = nil
  function Pl.tick(s)
    if not (s and Jr) then return end
    local n = Gd.badges(s)
    if lastBadges and n > lastBadges then
      pcall(Jr.on, "flag.changed", { name = ("FLAG_BADGE%02d_GET"):format(math.min(n, 8)), value = true })
    end
    lastBadges = n
  end
  function Pl.resetBadges() lastBadges = nil end

  return Pl
end
