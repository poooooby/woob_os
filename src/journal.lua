-- The journal: what the player does, from the engine's own events, kept in the save (mod.save
-- "journal": it rewinds with the save). Two parts:
--   this week's counts (Monday to Sunday, the device's local time), for Challenges: trainer and wild
--     battles won, Pokémon caught (by type, new to the Pokédex, today's swarm), eggs hatched,
--     evolutions, levels gained, items used, steps, places visited (each once a week)
--   a log of the notable moments, newest first (KEEP of them), for the News: a catch (new to the
--     Pokédex, shiny), a hatch, an evolution, a trainer beaten, a badge earned
--   the News's box scores (kept until newer ones come): the last two trainers beaten, the latest Gym
--     Leader beaten (with its play-by-play), the latest catch
-- A trainer battle is followed while it's fought (memory only): the leads, the last hit on each
-- battler (who, the move, super effective, a critical hit), each knockout in turn. Won, it becomes a
-- box score: where (the map), both teams, the score (knockouts each way), the turns, the finishing
-- blow. A Badge is its flag being set (the Gym's script sets it after the battle).
-- main.lua subscribes it to the events (Jr.on is the one way in: tests use it too). Steps only add to
-- a count in the record already kept, so a step costs no table.
--
--   Jr = Journal(engine, deps)  deps: save (mod.save) ; now() -> epoch seconds ; badges(s) ;
--                               session() ; swarm() -> today's swarm species id or nil ;
--                               leader(trainerClass) -> a Gym Leader's class
--   Jr.on(name, ev)   name: "battle.started" | "battle.damage_dealt" | "battle.battler_switched" |
--                     "battle.fainted" | "battle.ended" | "pokemon.caught" | "egg.hatched" |
--                     "pokemon.evolved" | "pokemon.level_up" | "map.entered" | "world.stepped" |
--                     "item.used" | "flag.changed"
--   Jr.week(t) / Jr.day(t) / Jr.localTime(t) (local) ; Jr.count(key) -> this week's count ; Jr.counts() ; Jr.log()
--   keys: trainer, wild, caught, t<type id>, new, swarm, hatched, evolved, levels, items, steps, places
--   Jr.wins() -> the last two trainers beaten (Gym Leaders apart), newest first ; Jr.gym() ; Jr.catch()
--     a win: { name, cls, map, mine = { species }, theirs = { species }, me, them (knockouts each
--       way), turns, fin = the finishing blow, at } ; the Gym's adds beats = { { k = "ko" | "down",
--       t (the turn), v (who fell), by, mv (the move), sup, crit } }, lead, foeLead, n (Badges), badge
--     the catch: { sp, map, new, shiny, ball, lv, at }

local floor = math.floor

local KEEP = 40
local WINS = 2        -- the trainers beaten kept for the News
local BEATS = 12      -- a battle's knockouts kept (the latest)
local TEAM = 6

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
    d.c, d.maps, d.log, d.wins = d.c or {}, d.maps or {}, d.log or {}, d.wins or {}
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
  function Jr.wins() return data().wins end
  function Jr.gym() return data().gym end
  function Jr.catch() return data().catch end

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

  local function mapNow()
    local s = deps.session and deps.session()
    return s and s.map or nil
  end
  local function spOf(b)
    if type(b) ~= "table" then return nil end
    return tonumber(b.species or b.speciesId) or speciesOf(b.mon)
  end
  local function join(list, sp)
    if not sp or #list >= TEAM then return end
    for i = 1, #list do if list[i] == sp then return end end
    list[#list + 1] = sp
  end
  local function turnOf(ev) return type(ev.battle) == "table" and tonumber(ev.battle.turn) or 0 end

  -- the trainer battle being fought (memory only)
  local fight
  local live = {}
  live["battle.started"] = function(ev)
    fight = nil
    local b = ev.battle
    if type(b) ~= "table" or b.wild or b.link or ev.kind == "wild" or ev.kind == "link" then return end
    fight = { map = mapNow(), hit = {}, beats = {}, me = 0, them = 0, mine = {}, theirs = {},
              lead = spOf(b.player), foeLead = spOf(b.enemy) }
    join(fight.mine, fight.lead)
    join(fight.theirs, fight.foeLead)
    for _, m in ipairs(type(b.foeParty) == "table" and b.foeParty or {}) do join(fight.theirs, speciesOf(m)) end
  end
  -- (the last hit each battler took: who, the move, how it landed)
  live["battle.damage_dealt"] = function(ev)
    local id, u = tonumber(ev.targetId), ev.user
    if not (fight and id and type(u) == "table") then return end
    local h = fight.hit[id]
    if not h then
      h = {}
      fight.hit[id] = h
    end
    h.side, h.sp, h.turn = u.side, spOf(u), turnOf(ev)
    h.mv = type(ev.move) == "table" and tonumber(ev.move.num) or tonumber(ev.moveNum)
    h.sup, h.crit = (tonumber(ev.typeMult) or 10) > 10, ev.crit == true
  end
  live["battle.battler_switched"] = function(ev)
    if not fight then return end
    local sp = tonumber(ev.speciesId) or spOf(ev.battler)
    if ev.sideName == "player" then join(fight.mine, sp) elseif ev.sideName == "enemy" then join(fight.theirs, sp) end
  end
  -- (a knockout: who fell, and who did it when the last hit on them came this turn from the other side)
  live["battle.fainted"] = function(ev)
    if not fight then return end
    local v = ev.battler
    local side = ev.sideName or (type(v) == "table" and v.side) or nil
    local id = tonumber(ev.battlerId) or (type(v) == "table" and tonumber(v.id)) or nil
    local turn = turnOf(ev)
    local foe = side == "enemy"
    if foe then fight.me = fight.me + 1 else fight.them = fight.them + 1 end
    local beat = { k = foe and "ko" or "down", t = turn, v = spOf(v) }
    local h = id and fight.hit[id]
    if h and h.turn == turn and h.side ~= side and h.sp then
      beat.by, beat.mv = h.sp, h.mv
      if h.sup then beat.sup = true end
      if h.crit then beat.crit = true end
    end
    if #fight.beats >= BEATS then table.remove(fight.beats, 1) end
    fight.beats[#fight.beats + 1] = beat
  end

  local handlers = {}
  handlers["battle.ended"] = function(d, ev)
    local b = type(ev.battle) == "table" and ev.battle or {}
    local f = fight
    fight = nil
    if b.link then return end
    if ev.result == "win" then
      if b.wild then
        add(d, "wild")
      else
        add(d, "trainer")
        note(d, { k = "trainer", name = b.trainerName, cls = b.trainerClassName })
        if f then
          -- (the box score; the finishing blow is the last of their team to fall)
          local rec = { name = b.trainerName, cls = b.trainerClassName, map = f.map or mapNow(), mine = f.mine,
                        theirs = f.theirs, me = f.me, them = f.them, turns = tonumber(b.turn) or 0, at = Jr.now() }
          for i = #f.beats, 1, -1 do
            if f.beats[i].k == "ko" then
              rec.fin = f.beats[i]
              break
            end
          end
          local okL, leader = pcall(deps.leader or error, tonumber(b.trainerClass))
          if okL and leader then
            rec.beats, rec.lead, rec.foeLead, rec.n = f.beats, f.lead, f.foeLead, badges()
            d.gym = rec
          else
            table.insert(d.wins, 1, rec)
            while #d.wins > WINS do d.wins[#d.wins] = nil end
          end
        end
      end
    end
  end
  -- a Badge: its flag set (after the Gym's battle); the Gym's box score gets its number
  handlers["flag.changed"] = function(d)
    local n = badges()
    note(d, { k = "badge", n = n })
    local g = d.gym
    if g and not g.badge and Jr.now() - (tonumber(g.at) or 0) < 900 then g.badge, g.n = true, n end
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
    local sh = shiny(ev.mon)
    note(d, { k = "catch", sp = sp, new = ev.isNew == true, shiny = sh })
    d.catch = { sp = sp, map = mapNow(), new = ev.isNew == true, shiny = sh or nil, ball = tonumber(ev.ballId),
                lv = type(ev.mon) == "table" and tonumber(ev.mon.level) or nil, at = Jr.now() }
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
    local l = live[name]
    if l then return l(ev) end
    -- (only a Badge's flag; scripts set flags all the time)
    if name == "flag.changed" and not (ev.value == true and type(ev.name) == "string" and ev.name:find("^FLAG_BADGE0%d_GET$")) then
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
