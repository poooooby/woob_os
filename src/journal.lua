-- The journal: what the player does, from the engine's own events, kept in the save (mod.save
-- "journal": it rewinds with the save). Two parts:
--   this week's counts (Monday to Sunday, the device's local time), for Challenges: trainer and wild
--     battles won, Pokémon caught (by type, new to the Pokédex, today's swarm), eggs hatched,
--     evolutions, levels gained, items used, steps, places visited (each once a week)
--   a log of the notable moments, newest first (KEEP of them), for the News: a catch (new to the
--     Pokédex, shiny), a hatch, an evolution, a trainer beaten, a badge earned
-- main.lua subscribes it to the events (Jr.on is the one way in: tests use it too). Steps only add to
-- a count in the record already kept, so a step costs no table.
--
--   Jr = Journal(engine, deps)  deps: save (mod.save) ; now() -> epoch seconds ; badges(s) ;
--                               session() ; swarm() -> today's swarm species id or nil
--   Jr.on(name, ev)   name: "battle.ended" | "pokemon.caught" | "egg.hatched" | "pokemon.evolved" |
--                     "pokemon.level_up" | "map.entered" | "world.stepped" | "item.used"
--   Jr.week(t) / Jr.day(t) / Jr.localTime(t) (local) ; Jr.count(key) -> this week's count ; Jr.counts() ; Jr.log()
--   keys: trainer, wild, caught, t<type id>, new, swarm, hatched, evolved, levels, items, steps, places

local floor = math.floor

local KEEP = 40

return function(engine, deps)
  deps = deps or {}
  local Jr = { store = deps.save, now = deps.now or os.time, KEEP = KEEP }

  -- (local time: the device's offset from UTC, so a week starts at its own Monday midnight)
  local function offset(t)
    local okL, l = pcall(os.date, "*t", t)
    local okU, u = pcall(os.date, "!*t", t)
    if not (okL and okU and l and u) then return 0 end
    l.isdst = false
    return os.time(l) - os.time(u)
  end
  -- the device's local time, as seconds
  function Jr.localTime(t)
    t = t or Jr.now()
    return t + offset(t)
  end
  function Jr.day(t) return floor(Jr.localTime(t) / 86400) end
  -- (the epoch's day 0 was a Thursday: three days on, weeks start on Mondays; worked out at most
  -- once a minute for now, as os.date makes tables and steps come several a second)
  local weekAt, weekNow = nil, nil
  function Jr.week(t)
    if t then return floor((Jr.day(t) + 3) / 7) end
    local now = Jr.now()
    if not weekAt or now < weekAt or now - weekAt >= 60 then
      weekAt, weekNow = now, floor((Jr.day(now) + 3) / 7)
    end
    return weekNow
  end

  local loose
  local function data()
    local store = Jr.store
    local d = store and store:get("journal") or loose
    if type(d) ~= "table" then
      d = { week = Jr.week(), c = {}, maps = {}, log = {} }
      if store then store:set("journal", d) else loose = d end
    end
    d.c, d.maps, d.log = d.c or {}, d.maps or {}, d.log or {}
    -- (a new week: its counts from nothing)
    local w = Jr.week()
    if d.week ~= w then
      d.week, d.c, d.maps = w, {}, {}
      if store then store:set("journal", d) end
    end
    return d
  end
  local function save(d) if Jr.store then Jr.store:set("journal", d) end end
  local function add(d, key, n) d.c[key] = (d.c[key] or 0) + (n or 1) end
  local function note(d, rec)
    rec.at = Jr.now()
    table.insert(d.log, 1, rec)
    while #d.log > KEEP do d.log[#d.log] = nil end
  end

  function Jr.count(key) return data().c[key] or 0 end
  function Jr.counts() return data().c end
  function Jr.log() return data().log end
  function Jr.weekOf() return data().week end

  local function P() return engine("src.core.game3.pokemon") end
  local function speciesOf(mon)
    return mon and tonumber(mon.species or mon.speciesId) or nil
  end
  local function shiny(mon)
    -- (a Pokémon without a personality reads as shiny to the engine: only a real one counts)
    if type(mon) ~= "table" or mon.personality == nil then return false end
    local Pk = P()
    local ok, yes = pcall(Pk and Pk.isShiny or error, mon)
    return ok and yes == true
  end
  local function badges()
    local s = deps.session and deps.session()
    return s and deps.badges and tonumber(deps.badges(s)) or nil
  end

  local handlers = {}
  handlers["battle.ended"] = function(d, ev)
    local b = type(ev.battle) == "table" and ev.battle or {}
    if b.link then return end
    if ev.result == "win" then
      if b.wild then
        add(d, "wild")
      else
        add(d, "trainer")
        note(d, { k = "trainer", name = b.trainerName, cls = b.trainerClassName })
      end
    end
    -- (a badge: the count is higher than the last battle left it)
    local n = badges()
    if n then
      if d.badges and n > d.badges then note(d, { k = "badge", n = n }) end
      d.badges = n
    end
  end
  handlers["pokemon.caught"] = function(d, ev)
    local sp = tonumber(ev.speciesId) or speciesOf(ev.mon)
    add(d, "caught")
    if ev.isNew then add(d, "new") end
    if sp then
      local Pk = P()
      local ok, types = pcall(Pk and Pk.types or error, sp)
      if ok and type(types) == "table" then
        local seen
        for i = 1, #types do
          local t = tonumber(types[i])
          if t and t ~= seen then add(d, "t" .. t) end
          seen = t
        end
      end
      if deps.swarm and deps.swarm() == sp then add(d, "swarm") end
    end
    note(d, { k = "catch", sp = sp, new = ev.isNew == true, shiny = shiny(ev.mon) })
  end
  handlers["egg.hatched"] = function(d, ev)
    add(d, "hatched")
    note(d, { k = "hatch", sp = speciesOf(ev.mon) or tonumber(ev.species), shiny = shiny(ev.mon) })
  end
  handlers["pokemon.evolved"] = function(d, ev)
    add(d, "evolved")
    note(d, { k = "evolve", from = tonumber(ev.fromSpeciesId), sp = tonumber(ev.toSpeciesId) })
  end
  handlers["pokemon.level_up"] = function(d) add(d, "levels") end
  handlers["item.used"] = function(d) add(d, "items") end
  handlers["map.entered"] = function(d, ev)
    local id = ev.mapId and tostring(ev.mapId)
    if id and not d.maps[id] then
      d.maps[id] = true
      add(d, "places")
    end
  end

  function Jr.on(name, ev)
    ev = type(ev) == "table" and ev or {}
    if name == "world.stepped" then
      -- (every step: the count in the record already kept, nothing made)
      local d = data()
      d.c.steps = (d.c.steps or 0) + 1
      return
    end
    local h = handlers[name]
    if not h then return end
    local d = data()
    h(d, ev)
    save(d)
  end

  return Jr
end
