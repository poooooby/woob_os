-- The 3D map's objectives on the Game Boy games (src/map3d/objectives.lua's, for Red / Blue / Yellow and Gold /
-- Silver / Crystal; the same answers, so the scene's window and objectives_view.lua are unchanged): for each place,
-- what the game has there, read from the cart once per game --
--   Gen 2: each map's own scripts (its people's, signs', steps', scenes' and callbacks', the jumps they make, never
--          the shared std scripts): key items handed out (verbosegiveitem / giveitem: the Key Items pocket or an HM),
--          done by the event the script sets after (else in the Bag); Gym Leaders, the Elite Four (loadtrainer by
--          its class), done by the event set after the battle; marts (pokemart); people by the special they call
--          (Name Rater, Day Care, Move Deleter, Move Tutor, the Lucky Number show) and in-game trades (done once
--          traded); the story's beats where their event is set
--   Gen 1: its scripts are the engine's own Lua, so: the leaders and the Elite Four from the maps' trainers and the
--          engine's victories table; key items from the scripts' give_item rows, the key items lying in the maps
--          and the gifts the scripts hand out in code (GIFTS below); marts from the maps' text pointers; the Name
--          Rater's and the Day Care's houses; trades; the story's beats at their maps (BEATS1)
-- A place is a Town Map location: Gen 2's landmark ("lm6"), Gen 1's outdoor map ("PEWTER_CITY"), as
-- src/gb/map3d.lua makes them; a map with none (a cave, a tower) goes to the place its doors lead to.
--
--   Ob = Objectives(H, Gd, deps)   deps: T, log
--   Ob.at(place, s, spoilers) -> { { kind, label, done, hidden }, ... } | nil ; Ob.reset() ; Ob.index()

local floor = math.floor

-- ------- Gen 2
-- the story's beats: its event, its words (map.obj.story.<id>); placed where a script sets the event
local BEATS2 = {
  { "elm", "EVENT_GOT_A_POKEMON_FROM_ELM" }, { "egg", "EVENT_GOT_MYSTERY_EGG_FROM_MR_POKEMON" },
  { "slowpoke", "EVENT_CLEARED_SLOWPOKE_WELL" }, { "sudowoodo", "EVENT_FOUGHT_SUDOWOODO" },
  { "hideout", "EVENT_CLEARED_ROCKET_HIDEOUT" }, { "lighthouse", "EVENT_JASMINE_RETURNED_TO_GYM" },
  { "radioTower", "EVENT_CLEARED_RADIO_TOWER" }, { "beasts", "EVENT_RELEASED_THE_BEASTS" },
  { "champion", "EVENT_BEAT_CHAMPION_LANCE" }, { "powerPlant", "EVENT_RESTORED_POWER_TO_KANTO" },
  { "snorlax", "EVENT_FOUGHT_SNORLAX" }, { "suicune", "EVENT_FOUGHT_SUICUNE" }, { "hoOh", "EVENT_FOUGHT_HO_OH" },
  { "lugia", "EVENT_FOUGHT_LUGIA" },
}
local LEADER2 = { FALKNER = true, WHITNEY = true, BUGSY = true, MORTY = true, PRYCE = true, JASMINE = true,
                  CHUCK = true, CLAIR = true, BROCK = true, MISTY = true, LT_SURGE = true, ERIKA = true, JANINE = true,
                  SABRINA = true, BLAINE = true, BLUE = true }
local ELITE2 = { WILL = true, KOGA = true, BRUNO = true, KAREN = true }
local PEOPLE2 = { NameRater = "nameRater", DayCareMan = "daycare", DayCareLady = "daycare", DayCareManOutside = "daycare",
                  MoveDeletion = "deleter", MoveTutor = "tutor", CheckForLuckyNumberWinners = "lottery" }
-- (the shared std scripts: never followed)
local STD = { jumpstd = true, callstd = true }
local GIVE2 = { verbosegiveitem = true, giveitem = true }

-- ------- Gen 1
-- the story's beats: { id (the Gen 3 words, the same story), its flag, its map }
local BEATS1 = {
  { "pokedex", "EVENT_GOT_POKEDEX", "OAKS_LAB" }, { "mtMoon", { "EVENT_GOT_DOME_FOSSIL", "EVENT_GOT_HELIX_FOSSIL" }, "MT_MOON_B2F" },
  { "burglar", "EVENT_BEAT_CERULEAN_ROCKET_THIEF", "CERULEAN_CITY" }, { "bill", "EVENT_GOT_SS_TICKET", "BILLS_HOUSE" },
  { "ssAnne", "EVENT_GOT_HM01", "SS_ANNE_CAPTAINS_ROOM" }, { "hideout", "EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI", "ROCKET_HIDEOUT_B4F" },
  { "fuji", "EVENT_RESCUED_MR_FUJI", "POKEMON_TOWER_7F" },
  { "snorlax", { "EVENT_BEAT_ROUTE12_SNORLAX", "EVENT_BEAT_ROUTE16_SNORLAX" }, "ROUTE_12" },
  { "silph", "EVENT_BEAT_SILPH_CO_GIOVANNI", "SILPH_CO_11F" }, { "champion", "EVENT_BEAT_CHAMPION_RIVAL", "CHAMPIONS_ROOM" },
}
-- the key items the engine's scripts hand out in code (their give_item rows are read from the scripts themselves)
local GIFTS = {
  { "COIN_CASE", "CELADON_DINER", "EVENT_GOT_COIN_CASE" }, { "BICYCLE", "BIKE_SHOP", "EVENT_GOT_BICYCLE" },
  { "HM_FLY", "ROUTE_16_FLY_HOUSE", "EVENT_GOT_HM02" }, { "HM_FLASH", "ROUTE_2_GATE", "EVENT_GOT_HM05" },
  { "ITEMFINDER", "ROUTE_11_GATE_2F", "EVENT_GOT_ITEMFINDER" }, { "EXP_ALL", "ROUTE_15_GATE_2F", "EVENT_GOT_EXP_ALL" },
  { "OLD_AMBER", "MUSEUM_1F", "EVENT_GOT_OLD_AMBER" },
  { "DOME_FOSSIL", "MT_MOON_B2F", "EVENT_GOT_DOME_FOSSIL" }, { "HELIX_FOSSIL", "MT_MOON_B2F", "EVENT_GOT_HELIX_FOSSIL" },
}
local ELITE1 = { LORELEI = true, BRUNO = true, AGATHA = true, LANCE = true }
-- (the Elite Four in the order they're fought)
local ELITE_ORDER = { WILL = 1, KOGA = 2, BRUNO = 3, KAREN = 4, LORELEI = 1, AGATHA = 3, LANCE = 4 }
-- (people known by their house)
local HOUSE = { NAME_RATER = "nameRater", DAYCARE = "daycare", DAY_CARE = "daycare", MOVE_DELETER = "deleter" }
local PEOPLE_ORDER = { "tutor", "relearner", "deleter", "nameRater", "daycare", "trade", "lottery" }

return function(H, Gd, deps)
  local Ob = {}
  local T = deps.T
  local gen = H.gen
  local engine = H.engine
  local function log(fmt, ...) if deps.log then pcall(deps.log, fmt, ...) end end
  local function titleOf(s)
    local t = Gd.title(tostring(s or ""):gsub("_", " "))
    return (t:gsub("^Lt ", "Lt. "):gsub("Pokemon", "Pokémon"))
  end
  -- (an item's name as the Bag says it: "HM02 Fly", "Squirtbottle")
  local function itemTitle(id) return (tostring(Gd.itemName(id)):gsub("^Gs ", "GS ")) end
  local function isKey(id)
    local it = Gd.item(id)
    if type(it) ~= "table" then return false end
    if gen == 2 then return it.pocket == "KEY_ITEM" or tostring(id):find("^HM_") ~= nil end
    return it.keyItem == true or tostring(id):find("^HM_") ~= nil
  end

  local index, indexOf = nil, nil
  local bySec
  local function bucket(sec)
    local b = bySec[sec]
    if not b then
      b = { story = {}, gym = {}, key = {}, people = {}, shops = {}, seen = {} }
      bySec[sec] = b
    end
    return b
  end
  local function addKey(b, item, flag)
    if item and isKey(item) and not b.seen["k" .. item] then
      b.seen["k" .. item] = true
      b.key[#b.key + 1] = { item = item, name = itemTitle(item), flag = flag }
    end
  end
  local function addPerson(b, kind, flag)
    if kind and not b.seen["p" .. kind] then
      b.seen["p" .. kind] = true
      b.people[#b.people + 1] = { kind = kind, flag = flag }
    end
  end
  local function addShop(b, name)
    if not b.seen["s" .. name] then
      b.seen["s" .. name] = true
      b.shops[#b.shops + 1] = { name = name }
    end
  end
  -- (a shop's name from its map: a department store's floor, a Mart, else the map's own words past the town's)
  local function shopName(id, town)
    local floorWord = id:match("DEPT_STORE_(%w+)$") or id:match("_MART_(%d+F)$")
    if id:find("DEPT_STORE_ROOF$") then floorWord = "Roof" end
    if floorWord and (floorWord == "Roof" or floorWord:find("^%d")) and not id:find("_MART_1F$") then
      return T.f("map.obj.shop.floor", floorWord)
    end
    if id:find("_MART$") or id:find("_MART_1F$") or id:find("POKECENTER") or id:find("POKEMON_CENTER") or id:find("LOBBY") then
      return T("map.obj.shop.mart")
    end
    local bare = id
    local base = town and town:gsub("_CITY$", ""):gsub("_TOWN$", "")
    if town and bare:sub(1, #town + 1) == town .. "_" then bare = bare:sub(#town + 2)
    elseif base and bare:sub(1, #base + 1) == base .. "_" then bare = bare:sub(#base + 2) end
    return titleOf(bare)
  end

  -- ------- Gen 2: the cart's scripts
  local function build2(d)
    local defs, scripts, C = d.gen2Maps, d.gen2Scripts, d.gen2Constants
    if type(defs) ~= "table" or type(scripts) ~= "table" or type(C) ~= "table" then return nil end
    local items, evOrder, specials = C.itemOrder or {}, C.eventFlagOrder or {}, C.specialOrder or {}
    local classes = C.trainerClassOrder or {}
    local function eventName(id) return id and evOrder[tonumber(id) + 1] end
    -- (each landmark with a place, and the map that stands for it: the outdoor maps)
    local placed, town = {}, {}
    for id, def in pairs(defs) do
      if type(def) == "table" and (def.environment == "TOWN" or def.environment == "ROUTE") and def.landmark then
        placed[def.landmark] = true
        if not town[def.landmark] or #id < #town[def.landmark] then town[def.landmark] = id end
      end
    end
    -- (a map's place: its landmark's, else the place its doors lead to, a few maps out)
    local function placeOf(id, depth, seen)
      local def = defs[id]
      if type(def) ~= "table" then return nil end
      if placed[def.landmark] then return def.landmark end
      if depth > 5 then return nil end
      seen[id] = true
      for _, w in ipairs(def.warps or {}) do
        local to = w.destMap or w.map
        if type(to) == "string" and not seen[to] then
          local lm = placeOf(to, depth + 1, seen)
          if lm then return lm end
        end
      end
      return nil
    end
    -- (the first event a script sets from command i on, following its jumps a little way)
    local function eventAfter(key, i, depth, seen)
      local sc = scripts[key]
      if type(sc) ~= "table" or depth > 4 then return nil end
      for j = i, math.min(#sc, i + 30) do
        local cmd = sc[j]
        if cmd.op == "setevent" then return eventName(cmd.event) end
        if cmd.op == "end" or cmd.op == "endcallback" then return nil end
        if (cmd.op == "sjump" or cmd.op == "scall" or cmd.op == "farsjump" or cmd.op == "farscall")
          and cmd.script and not seen[cmd.script] then
          seen[cmd.script] = true
          local f = eventAfter(cmd.script, 1, depth + 1, seen)
          if f then return f end
          if cmd.op == "sjump" or cmd.op == "farsjump" then return nil end
        end
      end
      return nil
    end
    local beatAt = {}
    for _, bt in ipairs(BEATS2) do beatAt[bt[2]] = bt end
    local beatSec = {}
    local ids = {}
    for id in pairs(defs) do if type(id) == "string" then ids[#ids + 1] = id end end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local def = defs[id]
      local lm = type(def) == "table" and placeOf(id, 0, {})
      if lm then
        local sec = "lm" .. tostring(lm)
        local b = bucket(sec)
        local todo, seen = {}, {}
        local function add(key) if type(key) == "string" and not seen[key] then seen[key] = true todo[#todo + 1] = key end end
        for _, o in ipairs(def.objects or {}) do
          add(o.scriptKey)
          if type(o.trainer) == "table" then add(o.trainer.scriptKey) end
          -- (a key item lying there, a ball: done once picked up -- its flag is the object's own)
          if type(o.itemball) == "table" then
            local item = items[tonumber(o.itemball.item) or -1]
            if item and isKey(item) then addKey(b, item, eventName(o.eventFlag ~= 65535 and o.eventFlag or nil)) end
          end
        end
        for _, g in ipairs(def.bgEvents or {}) do if g.kind == 0 then add(g.scriptKey) end end
        for _, c in ipairs(def.coordEvents or {}) do add(c.scriptKey) end
        for _, c in ipairs(def.callbacks or {}) do add(c.scriptKey) end
        for _, c in pairs(def.sceneScripts or {}) do if type(c) == "table" then add(c.scriptKey) end end
        for word, kind in pairs(HOUSE) do if id:find(word, 1, true) then addPerson(b, kind) end end
        local n = 1
        while n <= #todo and n < 400 do
          local key = todo[n]
          n = n + 1
          local sc = scripts[key]
          for i, cmd in ipairs(type(sc) == "table" and sc or {}) do
            local op = cmd.op
            if not STD[op] and type(cmd.script) == "string" and scripts[cmd.script] then add(cmd.script) end
            if GIVE2[op] then
              addKey(b, items[tonumber(cmd.item) or -1], eventAfter(key, i + 1, 0, {}))
            elseif op == "loadtrainer" then
              local cls = classes[(tonumber(cmd.class) or -1) + 1]
              local kind = (LEADER2[cls] and "gym") or (ELITE2[cls] and "elite") or nil
              if kind and not b.seen["t" .. cls] then
                b.seen["t" .. cls] = true
                b.gym[#b.gym + 1] = { kind = kind, name = titleOf(cls), flag = eventAfter(key, i + 1, 0, {}),
                                      rank = ELITE_ORDER[cls] or 0 }
              end
            elseif op == "pokemart" then
              addShop(b, shopName(id, town[lm]))
            elseif op == "special" then
              addPerson(b, PEOPLE2[specials[(tonumber(cmd.id) or -1) + 1] or ""])
            elseif op == "trade" then
              local tr = tonumber(cmd.trade)
              if tr and not b.seen["p" .. "trade" .. tr] then
                b.seen["p" .. "trade" .. tr] = true
                if not b.seen.ptrade then
                  b.seen.ptrade = true
                  b.people[#b.people + 1] = { kind = "trade", trade = tr }
                end
              end
            elseif op == "setevent" then
              local nm = eventName(cmd.event)
              local bt = nm and beatAt[nm]
              if bt and not beatSec[bt[1]] then beatSec[bt[1]] = sec end
            end
          end
        end
      end
    end
    -- (the story's beats, in their order, where their event is set)
    for _, bt in ipairs(BEATS2) do
      local sec = beatSec[bt[1]]
      if sec then
        local b = bucket(sec)
        b.story[#b.story + 1] = { beat = bt[1], flags = { bt[2] } }
      end
    end
    return true
  end

  -- ------- Gen 1: the engine's scripts and the cart's maps
  local function build1(d)
    local defs = d.maps
    if type(defs) ~= "table" then return nil end
    local TM = d.field and d.field.townMap
    local locs = TM and TM.locations or {}
    -- (the outdoor maps are the places; any other map goes to the one of its Town Map location: its name, else its
    -- square, else the nearest)
    local outdoor = {}
    for id, def in pairs(defs) do
      if type(def) == "table" and (def.tileset == "OVERWORLD" or def.tileset == "PLATEAU") and locs[id] then
        outdoor[#outdoor + 1] = id
      end
    end
    table.sort(outdoor)
    local placeOf = {}
    local function place(id)
      if placeOf[id] ~= nil then return placeOf[id] or nil end
      local def, l = defs[id], locs[id]
      local got = false
      if type(def) == "table" and (def.tileset == "OVERWORLD" or def.tileset == "PLATEAU") then got = id
      elseif l then
        local best, bd
        for _, o in ipairs(outdoor) do
          local ol = locs[o]
          if ol.name == l.name then best, bd = o, -1 break end
          local dist = (ol.x - l.x) ^ 2 + (ol.y - l.y) ^ 2
          if not bd or dist < bd then best, bd = o, dist end
        end
        got = best or false
      end
      placeOf[id] = got
      return got or nil
    end
    -- the leaders and the Elite Four: the maps' trainers the victories table knows
    local V = engine("data.scripts.victories")
    local ids = {}
    for id in pairs(defs) do if type(id) == "string" then ids[#ids + 1] = id end end
    table.sort(ids)
    local labelTo = {}
    for _, id in ipairs(ids) do
      local def = defs[id]
      local sec = type(def) == "table" and place(id)
      if sec then
        local b = bucket(sec)
        if def.label then labelTo[def.label] = id end
        for _, o in ipairs(def.objects or {}) do
          local cls = o.trainerClass
          local v = cls and type(V) == "table" and V[cls .. "#" .. tostring(o.trainerParty or 1)]
          if type(v) == "table" then
            local who = tostring(cls):gsub("^OPP_", "")
            local kind = v.badge and "gym" or (ELITE1[who] and "elite") or nil
            if kind and not b.seen["t" .. who] then
              b.seen["t" .. who] = true
              b.gym[#b.gym + 1] = { kind = kind, name = titleOf(who), flags = { v.flag }, rank = ELITE_ORDER[who] or 0 }
            end
          end
          -- (a key item lying there: done once it's in the Bag)
          local item = o.item
          if type(item) == "string" and item ~= "0" then addKey(b, item, nil) end
        end
        for word, kind in pairs(HOUSE) do if id:find(word, 1, true) then addPerson(b, kind) end end
      end
    end
    -- the marts: the maps' clerks with a stock
    for label, tp in pairs(type(d.text_pointers) == "table" and d.text_pointers or {}) do
      local id = labelTo[label]
      local sec = id and place(id)
      if sec and type(tp) == "table" then
        for _, e in pairs(tp) do
          if type(e) == "table" and e.mart then addShop(bucket(sec), shopName(id, sec)) break end
        end
      end
    end
    -- the scripts' gifts and trades: their give_item and trade rows, the flag each sets after
    -- (the engine's map scripts, as the field loads them)
    local MS = engine("data.scripts.init")
    if not (MS and type(MS.get) == "function") then MS = engine("src.script.MapScripts") end
    local function walk(list, b, depth)
      if type(list) ~= "table" or depth > 4 then return end
      for i, row in ipairs(list) do
        if type(row) == "table" then
          local op = row[1]
          if op == "give_item" and type(row[2]) == "string" then
            local flag
            for j = i + 1, math.min(#list, i + 4) do
              local r = list[j]
              if type(r) == "table" and r[1] == "set_flag" then flag = r[2] break end
            end
            addKey(b, row[2], flag)
          elseif op == "trade" then
            if not b.seen.ptrade then
              b.seen.ptrade = true
              b.people[#b.people + 1] = { kind = "trade", flag = type(row[3]) == "string" and row[3] or nil }
            end
          elseif type(op) ~= "string" then
            walk(row, b, depth + 1)
          end
        end
      end
    end
    if MS and type(MS.get) == "function" then
      for _, id in ipairs(ids) do
        local sec = place(id)
        local okG, ms = pcall(MS.get, id)
        if sec and okG and type(ms) == "table" and type(ms.talk) == "table" then
          for _, sc in pairs(ms.talk) do walk(sc, bucket(sec), 0) end
        end
      end
    end
    for _, g in ipairs(GIFTS) do
      local sec = defs[g[2]] and place(g[2])
      if sec then addKey(bucket(sec), g[1], g[3]) end
    end
    for _, bt in ipairs(BEATS1) do
      local sec = defs[bt[3]] and place(bt[3])
      if sec then
        local b = bucket(sec)
        b.story[#b.story + 1] = { beat = bt[1], flags = type(bt[2]) == "table" and bt[2] or { bt[2] } }
      end
    end
    return true
  end

  local function build()
    local d = Gd.data()
    if type(d) ~= "table" then return nil end
    bySec = {}
    local ok = gen == 2 and build2(d) or (gen == 1 and build1(d))
    if not ok then return nil end
    for _, b in pairs(bySec) do
      -- (the Gym Leader first, then the Elite Four as they're fought)
      table.sort(b.gym, function(a, c)
        if a.kind ~= c.kind then return a.kind == "gym" end
        if a.rank ~= c.rank then return a.rank < c.rank end
        return a.name < c.name
      end)
      table.sort(b.people, function(a, c)
        local ia, ic = 0, 0
        for k, v in ipairs(PEOPLE_ORDER) do if v == a.kind then ia = k end if v == c.kind then ic = k end end
        return ia < ic
      end)
      b.seen = nil
    end
    return bySec
  end

  function Ob.reset() index, indexOf = nil, nil end
  local function ensure()
    local gid = H.gameId()
    if index == nil or indexOf ~= gid then
      local ok, got = pcall(build)
      if not ok then log("the map's objectives: %s", tostring(got)) end
      index, indexOf = ok and got or false, gid
    end
    return index or nil
  end

  -- ------- the save: a flag set, an item had
  local evIds = nil
  local function flagOn(name, s)
    if type(name) ~= "string" or type(s) ~= "table" then return false end
    if gen == 1 then
      local f = s.flags
      return type(f) == "table" and f[name] ~= nil and f[name] ~= false
    end
    if evIds == nil then
      evIds = {}
      local d = Gd.data()
      for i, nm in ipairs(d and d.gen2Constants and d.gen2Constants.eventFlagOrder or {}) do evIds[nm] = i - 1 end
    end
    local id = evIds[name]
    if not id then return false end
    -- (the live save: the World's own flags; another, its kept bytes)
    local g = H.game()
    local ev = g and g.save == s and g.world and g.world.events
    if type(ev) == "table" and type(ev.get) == "function" then
      local ok, on = pcall(ev.get, ev, id)
      if ok then return on == true end
    end
    local bytes = s.events
    if type(bytes) ~= "table" then return false end
    local byte = bytes[floor(id / 8)] or bytes[tostring(floor(id / 8))] or 0
    return floor((tonumber(byte) or 0) / 2 ^ (id % 8)) % 2 == 1
  end
  local function anyOn(list, s)
    for _, f in ipairs(list or {}) do if flagOn(f, s) then return true end end
    return false
  end
  local function hasItem(s, id)
    local inv = type(s) == "table" and s.inventory
    return type(inv) == "table" and (tonumber(inv[id]) or 0) > 0
  end
  local function traded(s, tr)
    local tf = type(s) == "table" and s.tradeFlags
    return type(tf) == "table" and tf[tr] == true
  end

  -- what a place lists now: the words made here, the boxes from the save
  function Ob.at(sec, s, spoilers)
    local all = ensure()
    local b = all and all[sec]
    if not b then return nil end
    local out = {}
    for _, e in ipairs(b.story) do
      local done = anyOn(e.flags, s)
      out[#out + 1] = { kind = "story", label = T("map.obj.story." .. e.beat), done = done,
                        hidden = not done and not spoilers }
    end
    for _, e in ipairs(b.gym) do
      local done = (e.flags and anyOn(e.flags, s)) or (e.flag ~= nil and flagOn(e.flag, s)) or false
      out[#out + 1] = { kind = "gym", label = T.f("map.obj." .. e.kind, e.name), done = done }
    end
    for _, e in ipairs(b.key) do
      local done = (e.flag ~= nil and flagOn(e.flag, s)) or hasItem(s, e.item)
      out[#out + 1] = { kind = "key", label = e.name, done = done or false }
    end
    for _, e in ipairs(b.people) do
      local r = { kind = "people", label = T("map.obj.people." .. e.kind) }
      if e.flag then r.done = flagOn(e.flag, s) elseif e.trade then r.done = traded(s, e.trade) end
      out[#out + 1] = r
    end
    for _, e in ipairs(b.shops) do out[#out + 1] = { kind = "shop", label = e.name } end
    if #out == 0 then return nil end
    return out
  end
  function Ob.index() return ensure() end

  return Ob
end
