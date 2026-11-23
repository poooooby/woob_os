-- The 3D map's objectives (FireRed, LeafGreen, Ruby, Sapphire, Emerald; the mod option `mapObjectives`): for each
-- place, what the game has there, read from the cart's own maps and scripts once per game --
--   key items  each one a script hands out (the game's "obtain item" routine, std 0 / 1, with an item from the Key
--              Items pocket or an HM), done when the flag its script sets after is set (else when it's in the Bag)
--   gyms       its Gym Leader (a LEADER trainer's battle), the Elite Four and the Champion, done by the flag the
--              script sets after the battle (the Badge's)
--   story      the story's beats (src/story.lua's, as the News follows them), placed where each happens
--   shops      its Marts, department store floors and other shops (a pokemart in its scripts), named from the map
--   people     its Move Tutors, Move Relearner, Move Deleter, Name Rater, Day Care, in-game trades, Lottery Corner
--              (by the game's own special called); a trade done once its flag is set
-- Only a map's own scripts are followed (the shared Common_ ones -- naming a gift -- would make every gift spot a
-- Name Rater).
--
--   Ob = Objectives(engine, deps)   deps: maps() -> the map definitions ; gameId() ; family() -> "frlg" | "rse" ;
--                                   flag(name, s) -> bool ; reached(s) -> { [beatId] = true } ; hasItem(s, id) -> bool ;
--                                   T ; log
--   Ob.at(sec, s, spoilers) -> { { kind, label, done (true / false; nil: no box), hidden (a story beat not reached,
--       its words hidden) }, ... } in the order story, gyms, key items, people, shops; nil when there's nothing
--   Ob.reset()

local floor = math.floor

-- the story's beats, where each happens (its map without the game's prefix; the first that's a place wins)
local BEAT_AT = {
  pokedex = { "PALLET_TOWN" }, mtMoon = { "MT_MOON_B2F" }, burglar = { "CERULEAN_CITY" },
  bill = { "ROUTE_25_SEA_COTTAGE" }, ssAnne = { "SSANNE_CAPTAINS_OFFICE", "VERMILION_CITY" },
  hideout = { "ROCKET_HIDEOUT_B4F", "CELADON_CITY" }, fuji = { "POKEMON_TOWER_7F", "LAVENDER_TOWN" },
  snorlax = { "ROUTE_12" }, silph = { "SILPH_CO_11F", "SAFFRON_CITY" }, giovanni = { "VIRIDIAN_CITY_GYM" },
  champion = { "POKEMON_LEAGUE_CHAMPIONS_ROOM", "EVER_GRANDE_CITY_CHAMPIONS_ROOM" },
  ruby = { "MT_EMBER_RUBY_PATH_B3F", "MT_EMBER_RUBY_PATH_1F" }, warehouse = { "FIVE_ISLAND_ROCKET_WAREHOUSE" },
  sapphire = { "FIVE_ISLAND_ROCKET_WAREHOUSE" }, network = { "ONE_ISLAND" },
  chimney = { "MT_CHIMNEY" }, institute = { "ROUTE119_WEATHER_INSTITUTE_1F" }, orb = { "MT_PYRE_SUMMIT" },
  orbs = { "MT_PYRE_SUMMIT" }, groudon = { "MAGMA_HIDEOUT_1F", "JAGGED_PASS" },
  submarine = { "AQUA_HIDEOUT_1F", "SLATEPORT_CITY_HARBOR", "LILYCOVE_CITY" },
  spaceCenter = { "MOSSDEEP_CITY_SPACE_CENTER_1F" }, awakened = { "SEAFLOOR_CAVERN_ROOM9" },
  clash = { "SOOTOPOLIS_CITY" }, cave = { "CAVE_OF_ORIGIN_ENTRANCE" }, rayquaza = { "SKY_PILLAR_TOP", "SKY_PILLAR_1F" },
  calm = { "SOOTOPOLIS_CITY" }, frontier = { "BATTLE_FRONTIER_OUTSIDE_WEST" }, tower = { "BATTLE_TOWER_OUTSIDE" },
}
-- Ruby / Sapphire: the legend calmed in the Cave of Origin, not over Sootopolis
local BEAT_AT_RS = { calm = { "CAVE_OF_ORIGIN_ENTRANCE" } }
local BEAT_ORDER = { "pokedex", "mtMoon", "burglar", "bill", "ssAnne", "hideout", "fuji", "snorlax", "silph", "giovanni",
  "champion", "ruby", "warehouse", "sapphire", "network", "chimney", "institute", "orb", "orbs", "groudon", "submarine",
  "spaceCenter", "awakened", "clash", "cave", "rayquaza", "calm", "frontier", "tower" }
local RS = { ruby = true, sapphire = true }
local FRLG_BEATS = { pokedex = true, mtMoon = true, burglar = true, bill = true, ssAnne = true, hideout = true,
  fuji = true, snorlax = true, silph = true, giovanni = true, champion = true, ruby = true, warehouse = true,
  sapphire = true, network = true }
local RSE_BEATS = { chimney = true, institute = true, submarine = true, awakened = true, cave = true, calm = true,
  champion = true }
local EM_BEATS = { orbs = true, groudon = true, spaceCenter = true, clash = true, rayquaza = true, frontier = true }
local RS_BEATS = { orb = true, tower = true }

-- the people: the game's own specials -> the kind of person
local PEOPLE = {
  ChooseMonForMoveTutor = "tutor", ChooseMonForMoveRelearner = "relearner", TeachMoveRelearnerMove = "relearner",
  MoveDeleterChooseMoveToForget = "deleter", BufferMoveDeleterNicknameAndMove = "deleter",
  NameRaterWasNicknameChanged = "nameRater",
  GetDaycareMonNicknames = "daycare", ShowDaycareLevelMenu = "daycare", StoreSelectedPokemonInDaycare = "daycare",
  CreateInGameTradePokemon = "trade", RetrieveLotteryNumber = "lottery",
}
local ONCE = { trade = true }
local PEOPLE_ORDER = { "tutor", "relearner", "deleter", "nameRater", "daycare", "trade", "lottery" }
-- (the Champion is the story's own beat there: its rival's name is the player's choice)
local TRAINER_KIND = { LEADER = "gym", ELITE_FOUR = "elite", ["ELITE FOUR"] = "elite" }
-- (people known by their house's map: Ruby / Sapphire / Emerald's Name Rater calls nothing of its own)
local HOUSE = { NAME_RATER = "nameRater", MOVE_DELETER = "deleter", DAYCARE = "daycare" }
-- (and by their own script's name: Ruby / Sapphire's Name Rater lives in a house numbered like any other)
local PERSON_LABEL = { ["EventScript_NameRater$"] = "nameRater", ["EventScript_MoveDeleter$"] = "deleter" }
-- (the event tickets: handed out by every Pokémon Center's Mystery Gift man, never a place's own)
local EVENT_ITEMS = { "ITEM_EON_TICKET", "ITEM_MYSTIC_TICKET", "ITEM_AURORA_TICKET", "ITEM_OLD_SEA_MAP" }
-- (the standard routines that hand out an item set in VAR_0x8000: obtain, find, received)
local GIVE_STD = { [0] = true, [1] = true, [9] = true }

return function(engine, deps)
  local Ob = {}
  local T = deps.T
  local function log(fmt, ...) if deps.log then pcall(deps.log, fmt, ...) end end
  local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b = pcall(f, ...)
    if not ok then return nil end
    return a, b
  end
  local function titled(s)
    s = tostring(s or "")
    if s:find("%l") then return s end
    return (s:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
  end

  local index, indexOf = nil, nil

  -- ------- reading the cart, once per game

  local function build()
    local defs = deps.maps and deps.maps()
    local Space = engine("src.core.game3.scripting.space")
    local B = Space and Space.bundle
    if type(defs) ~= "table" or not (B and B.scripts) then return nil end
    local gid = deps.gameId and deps.gameId() or "emerald"
    local cgame = (gid == "leafgreen" and "firered") or (gid == "sapphire" and "ruby") or gid
    local Constants = engine("src.core.game3.constants")
    local C = Constants and call(Constants.of, gid)
    local specials = C and C.specials and C.specials.byId or {}
    local okF, Flags = pcall(engine, "src.core.game3.constants." .. cgame .. ".flags")
    -- (a flag's name by its number: from the names, which have the system flags -- the Badges -- byId lacks)
    local flagName = {}
    if okF and type(Flags) == "table" then
      for id, name in pairs(Flags.byId or {}) do flagName[tonumber(id) or id] = name end
      for name, id in pairs(Flags.byName or {}) do
        if tonumber(id) and flagName[tonumber(id)] == nil then flagName[tonumber(id)] = name end
      end
    end
    local I, Tr = engine("src.core.game3.items_data"), engine("src.core.game3.scripting.trainers")
    local Pk = engine("src.core.game3.pokemon")
    local event = {}
    local itemIds = C and C.items and C.items.byName or {}
    for _, nm in ipairs(EVENT_ITEMS) do if itemIds[nm] then event[tonumber(itemIds[nm])] = true end end
    -- (an item's name as the Bag would say it: "HM06 Rock Smash", "Pokéblock Case", "VS Seeker")
    local function itemTitle(id)
      local info = I and call(I.info, id)
      local raw = type(info) == "table" and info.name or ("#" .. id)
      local s = titled(raw):gsub("{Pokeblock}", "Pokéblock"):gsub("{POKEBLOCK}", "Pokéblock"):gsub("Pokemon", "Pokémon")
      s = s:gsub("^Hm(%d)", "HM%1"):gsub("^Tm(%d)", "TM%1"):gsub(" Tv$", " TV"):gsub("^Vs ", "VS ")
      local move = s:find("^HM%d") and Pk and call(Pk.moveFromTmItem, id)
      local mname = move and Pk and call(Pk.moveName, move)
      if type(mname) == "string" and mname ~= "" then s = s .. " " .. titled(mname) end
      return s
    end
    -- (a label's name: the global ones are shared scripts, not followed)
    local labelOf = {}
    for name, key in pairs(B.labels or {}) do labelOf[key] = name end
    local function shared(key)
      local l = labelOf[key]
      return l ~= nil and (l:find("^Common_") or l:find("^Std_") or l:find("^EventScript_")) ~= nil
    end
    local function isKey(id)
      local pocket = I and call(I.pocketOf, id)
      if event[id] then return false end
      if pocket == "KEY_ITEMS" then return true end
      local info = I and call(I.info, id)
      return type(info) == "table" and type(info.name) == "string" and info.name:find("^HM%d") ~= nil
    end
    -- (the first flag a script sets from command i on, following its jumps a little way)
    local function flagAfter(key, i, depth, seen)
      local sc = B.scripts[key]
      if not sc or depth > 4 then return nil end
      for j = i, math.min(#sc, i + 24) do
        local cmd = sc[j]
        if cmd.op == "setflag" then return flagName[tonumber(cmd.flag or cmd[1])] end
        if cmd.op == "end" or cmd.op == "return" or cmd.op == "releaseall" then return nil end
        if (cmd.op == "goto" or cmd.op == "call") and cmd.target and not seen[cmd.target] and not shared(cmd.target) then
          seen[cmd.target] = true
          local f = flagAfter(cmd.target, 1, depth + 1, seen)
          if f then return f end
          if cmd.op == "goto" then return nil end
        end
      end
      return nil
    end

    local bySec = {}
    local function bucket(sec)
      local b = bySec[sec]
      if not b then
        b = { story = {}, gym = {}, key = {}, people = {}, shops = {}, seen = {} }
        bySec[sec] = b
      end
      return b
    end
    local prefix = (next(defs) or ""):match("^(%u%u_)") or ""
    -- (each section's outdoor map: the shortest map id in it, for naming its shops)
    local outdoor = {}
    for id, def in pairs(defs) do
      local sec = type(def) == "table" and tonumber(def.regionMapSectionId)
      if sec and type(id) == "string" and (not outdoor[sec] or #id < #outdoor[sec]) then outdoor[sec] = id end
    end
    local function shopName(id, sec)
      local bare = id:sub(#prefix + 1)
      local floorWord = bare:match("DEPARTMENT_STORE_(%w+)$")
      if floorWord and floorWord ~= "ROOFTOP" and floorWord ~= "ELEVATOR" then
        return T.f("map.obj.shop.floor", floorWord)
      end
      -- (a Mart, a Pokémon Center's counter, the League's lobby)
      if bare:find("_MART$") or bare:find("POKEMON_CENTER", 1, true) or bare:find("POKEMON_LEAGUE$")
          or bare:find("POKEMON_LEAGUE_1F$") then
        return T("map.obj.shop.mart")
      end
      local town = outdoor[sec] and outdoor[sec]:sub(#prefix + 1)
      if town and bare == town then return T("map.obj.shop.stall") end
      if town and bare:sub(1, #town + 1) == town .. "_" then bare = bare:sub(#town + 2) end
      return (titled(bare:gsub("_", " ")):gsub("Pokemon", "Pokémon"))
    end

    for id, def in pairs(defs) do
      local sec = type(def) == "table" and tonumber(def.regionMapSectionId)
      if sec and type(id) == "string" then
        local b = bucket(sec)
        -- (the scripts the map's people, signs, steps and map scripts start, and where they go)
        local todo, seen = {}, {}
        local function add(key) if type(key) == "string" and not seen[key] and not shared(key) then seen[key] = true todo[#todo + 1] = key end end
        for _, o in ipairs(def.objects or {}) do
          add(o.scriptKey)
          local l = labelOf[o.scriptKey]
          for pat, kind in pairs(type(l) == "string" and PERSON_LABEL or {}) do
            if l:find(pat) and not b.seen["p" .. kind] then
              b.seen["p" .. kind] = true
              b.people[#b.people + 1] = { kind = kind }
            end
          end
        end
        for _, c in ipairs(def.coordEvents or {}) do add(c.scriptKey) end
        for _, g in ipairs(def.bgEvents or {}) do add(g.scriptKey) end
        -- (its map scripts: on load, on a frame when a variable says so -- the Elite Four's rooms start there)
        for _, v in pairs(type(def.mapScripts) == "table" and def.mapScripts or {}) do
          if type(v) == "string" then add(v)
          elseif type(v) == "table" then
            for _, e in ipairs(v) do if type(e) == "table" then add(e.scriptKey or e.script) end end
          end
        end
        -- (a house known by its map's name)
        for word, kind in pairs(HOUSE) do
          if id:find(word, 1, true) and not b.seen["p" .. kind] then
            b.seen["p" .. kind] = true
            b.people[#b.people + 1] = { kind = kind }
          end
        end
        local function keyItem(item, key, i)
          if item and item > 0 and item < 0x4000 and isKey(item) and not b.seen["k" .. item] then
            b.seen["k" .. item] = true
            b.key[#b.key + 1] = { item = item, name = itemTitle(item), flag = flagAfter(key, i + 1, 0, {}) }
          end
        end
        local badge, gyms = nil, {}
        local n = 1
        while n <= #todo and n < 400 do
          local key = todo[n]
          n = n + 1
          local sc = B.scripts[key] or {}
          for i, cmd in ipairs(sc) do
            local op = cmd.op
            if (op == "goto" or op == "call" or op == "goto_if" or op == "call_if") and cmd.target then add(cmd.target) end
            -- (the Badge: set somewhere in the Gym's scripts, often the one its leader's battle goes on to)
            if op == "setflag" and not badge then
              local nm = flagName[tonumber(cmd.flag or cmd[1])]
              if type(nm) == "string" and nm:find("^FLAG_BADGE%d+_GET") then badge = nm end
            end
            -- (an item handed out: its number set, then the game's obtain-item routine)
            if op == "callstd" and GIVE_STD[tonumber(cmd.std or cmd[1]) or -1] then
              local item
              for j = i - 1, math.max(1, i - 4), -1 do
                local p = sc[j]
                if p.op == "setorcopyvar" and tonumber(p[1]) == 0x8000 then item = tonumber(p[2]) end
              end
              keyItem(item, key, i)
            elseif op == "additem" then
              keyItem(tonumber(cmd[1]), key, i)
            elseif op == "trainerbattle" then
              -- (the scripts a battle goes on to, after a win)
              for _, v in pairs(cmd) do if type(v) == "string" and B.scripts[v] then add(v) end end
              local tid = tonumber(cmd.trainer or cmd[1])
              local info = tid and Tr and call(Tr.get, tid)
              local kind = type(info) == "table" and TRAINER_KIND[info.className]
              -- (one each: a rematch's team is the same person)
              local who = kind and ("t" .. kind .. tostring(info.name))
              if kind and not b.seen[who] then
                b.seen[who] = true
                b.gym[#b.gym + 1] = { kind = kind, name = titled(info.name or "?"), flag = flagAfter(key, i + 1, 0, {}) }
                if kind == "gym" then gyms[#gyms + 1] = b.gym[#b.gym] end
              end
            elseif op == "pokemart" or op == "pokemartdecoration" or op == "pokemartdecoration2" then
              local label = shopName(id, sec)
              if not b.seen["s" .. label] then
                b.seen["s" .. label] = true
                b.shops[#b.shops + 1] = { name = label }
              end
            elseif op == "special" or op == "specialvar" then
              local sid = op == "special" and tonumber(cmd.id or cmd[1]) or tonumber(cmd[2])
              local kind = sid and PEOPLE[specials[sid] or ""]
              if kind and not b.seen["p" .. kind] then
                b.seen["p" .. kind] = true
                b.people[#b.people + 1] = { kind = kind, flag = ONCE[kind] and flagAfter(key, i + 1, 0, {}) or nil }
              end
            end
          end
        end
        -- (a Gym Leader done with the Badge)
        if badge then for _, gy in ipairs(gyms) do gy.flag = badge end end
      end
    end
    -- (the story's beats, at the first of their maps that has a section)
    local fam = deps.family and deps.family() or "rse"
    for _, beat in ipairs(BEAT_ORDER) do
      local mine = (fam == "frlg" and FRLG_BEATS[beat]) or (fam ~= "frlg" and RSE_BEATS[beat])
        or (gid == "emerald" and EM_BEATS[beat]) or (RS[gid] and RS_BEATS[beat])
      if mine then
        local at = (RS[gid] and BEAT_AT_RS[beat]) or BEAT_AT[beat]
        local sec
        for _, m in ipairs(at) do
          local def = defs[prefix .. m]
          sec = type(def) == "table" and tonumber(def.regionMapSectionId) or nil
          if sec then break end
        end
        if sec then
          local b = bucket(sec)
          b.story[#b.story + 1] = { beat = beat }
        end
      end
    end
    -- (the people in the game's order)
    for _, b in pairs(bySec) do
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
    local gid = deps.gameId and deps.gameId() or "?"
    if index == nil or indexOf ~= gid then
      local ok, got = pcall(build)
      if not ok then log("the map's objectives: %s", tostring(got)) end
      index, indexOf = ok and got or false, gid
    end
    return index or nil
  end

  -- what a place lists now: the words made here, the boxes from the save
  function Ob.at(sec, s, spoilers)
    local all = ensure()
    local b = all and all[tonumber(sec) or -1]
    if not b then return nil end
    local flag = deps.flag or function() return false end
    local out = {}
    local reached = (#b.story > 0 and deps.reached) and (call(deps.reached, s) or {}) or {}
    for _, e in ipairs(b.story) do
      local done = reached[e.beat] == true
      out[#out + 1] = { kind = "story", label = T("map.obj.story." .. e.beat), done = done,
                        hidden = not done and not spoilers }
    end
    for _, e in ipairs(b.gym) do
      local done = e.flag and flag(e.flag, s) == true or false
      out[#out + 1] = { kind = "gym", label = T.f("map.obj." .. e.kind, e.name), done = done }
    end
    for _, e in ipairs(b.key) do
      local done
      if e.flag then done = flag(e.flag, s) == true end
      if not done and deps.hasItem then done = deps.hasItem(s, e.item) == true end
      out[#out + 1] = { kind = "key", label = e.name, done = done or false }
    end
    for _, e in ipairs(b.people) do
      local r = { kind = "people", label = T("map.obj.people." .. e.kind) }
      if e.flag then r.done = flag(e.flag, s) == true end
      out[#out + 1] = r
    end
    for _, e in ipairs(b.shops) do out[#out + 1] = { kind = "shop", label = e.name } end
    if #out == 0 then return nil end
    return out
  end
  -- (the index itself, for the tests)
  function Ob.index() return ensure() end

  return Ob
end
