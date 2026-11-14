-- The Pokédex's model: every Pokémon the game knows (and WoobleDex's, when it's installed) in the dex's
-- order, which are seen and caught, and each one's page, made when it's chosen. Read only: nothing here
-- draws and nothing is written to the save.
--
--   Dx = Dex(engine, deps)   deps: T (the words), typeName(id), placeName(mapId), itemName(id),
--                            wooble() -> WoobleDex's exports | nil, gameId() -> "emerald" ...
--   Dx.open(s) -> book: { modes = { "kanto" | "hoenn", "national"? }, lists = { [mode] = entries },
--                         counts = { [mode] = { seen, caught } } }       (made each time the dex opens)
--     entry = { sp, nat, num, numText, name, sex ("f" | "m" | nil: the name's own sign), seen, caught }
--   Dx.page(entry) -> the entry's page (kept per species; the game's rules decide what the window shows):
--     { category, heightText, weightText, types = { { id, name } }, stats = { hp, atk, def, spa, spd, spe },
--       total, female (0..1 | nil: genderless), description, abilities = { { name, desc } },
--       evolutions = { { from, to, toName, how } }, info = { { label, value } }, forms = { names },
--       moves = { level = rows, tm = rows, egg = rows, tutor = rows },
--       where = { { place, method, levels, chance } } }
--     move row = { name, typeId, typeName, power, acc, pp, physical, tag (level / TM / blank) }
--   Dx.reset(): everything made let go (a game switch, the engine's species pack reloaded)

local floor, max, min = math.floor, math.max, math.min

local GROWTH = { [0] = "medium_fast", "erratic", "fluctuating", "medium_slow", "fast", "slow" }
local LAND_W = { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }
local WATER_W = { 60, 30, 5, 4, 1 }
-- (the fishing slots: Old Rod 1-2, Good Rod 3-5, Super Rod 6-10, each slot's share of its rod's bites)
local FISH = { { "old", 70 }, { "old", 30 }, { "good", 60 }, { "good", 20 }, { "good", 20 },
               { "super", 40 }, { "super", 40 }, { "super", 15 }, { "super", 4 }, { "super", 1 } }
local METHOD_ORDER = { grass = 1, surf = 2, rock = 3, old = 4, good = 5, super = 6 }

local function titled(text)
  return (tostring(text):lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end
-- (a ROM name in WoobOS's words: titled, the gender signs the fonts don't have taken off to a mark)
local function nameOf(raw)
  raw = tostring(raw or "?")
  local sex
  if raw:find("\226\153\128", 1, true) then sex = "f" end
  if raw:find("\226\153\130", 1, true) then sex = "m" end
  raw = raw:gsub("\226\153\128", ""):gsub("\226\153\130", "")
  return titled(raw), sex
end
-- (the game's shouted names -- BULBASAUR, GRASS, POKéMON -- in a sentence's case; HP, PP, TM, HM kept)
local KEEP = { HP = true, PP = true, TM = true, HM = true }
local function unshout(text)
  return (text:gsub("[%a\195\169]+", function(w)
    if #w < 2 or w:find("%l") or KEEP[w] then return w end
    return w:sub(1, 1) .. w:sub(2):lower()
  end))
end
-- (a dex text: one paragraph, as the game's lines run on)
local function paragraph(text)
  if type(text) ~= "string" then return "" end
  return unshout((text:gsub("[\r\n]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")))
end

return function(engine, deps)
  deps = deps or {}
  local T = deps.T
  local Dx = {}

  local function P() return engine("src.core.game3.pokemon") end
  local function word(key, ...)
    if not T then return key end
    if select("#", ...) > 0 then return T.f(key, ...) end
    return T(key)
  end

  local pages, prevOf, whereOf, entriesPack = {}, nil, nil, nil
  function Dx.reset()
    pages, prevOf, whereOf, entriesPack = {}, nil, nil, nil
  end

  local function family()
    local Profile = engine("src.core.game3.profile")
    local ok, Pr = pcall(Profile and Profile.forSession or error, nil)
    return ok and type(Pr) == "table" and Pr.family == "rse" and "rse" or "frlg"
  end
  local function gameId() return deps.gameId and deps.gameId() or "firered" end

  -- the game has given the Pokédex (its own flag, every game)
  function Dx.available(s)
    local Profile, Constants = engine("src.core.game3.profile"), engine("src.core.game3.constants")
    local Flags, Space = engine("src.core.game3.scripting.flags"), engine("src.core.game3.scripting.space")
    local okP, Pr = pcall(Profile and Profile.forSession or error, nil)
    if not (okP and type(Pr) == "table") then return false end
    local okI, id = pcall(function() return Constants.of(Pr.id):flag("FLAG_SYS_POKEDEX_GET") end)
    if not (okI and id) then return false end
    if Flags and Space and Space.store then
      local okF, v = pcall(Flags.getFlag, Space.store, nil, id)
      if okF and v == true then return true end
    end
    local f = s and s.flags
    return f ~= nil and (f[id] == true or f[id] == 1)
  end

  -- ------- the list

  local function dexOf(s) return s and (s.dex or s.pokedex) or nil end

  local function newEntry(Pk, Dex, dex, sp, nat, num)
    local okN, raw = pcall(Pk.name, sp)
    local name, sex = nameOf(okN and raw or "?")
    local okS, seen = pcall(Dex.isSeen, dex, sp)
    local okC, caught = pcall(Dex.isCaught, dex, sp)
    caught = okC and caught == true
    return { sp = sp, nat = nat, num = num, numText = ("%03d"):format(num), name = name, sex = sex,
             seen = caught or (okS and seen == true), caught = caught }
  end

  function Dx.open(s)
    local Pk, Dex = P(), engine("src.core.game3.dex")
    local book = { modes = {}, lists = {}, counts = {} }
    if not (Pk and Dex) then return book end
    local dex = dexOf(s) or {}
    local rse = family() == "rse"
    local national = {}
    local maxNat = tonumber(Dex.NATIONAL_MAX) or 386
    for nat = 1, maxNat do
      local okS, sp = pcall(Pk.speciesFromNational, nat)
      if okS and sp then national[#national + 1] = newEntry(Pk, Dex, dex, sp, nat, nat) end
    end
    -- (the regional dex: Kanto's first 151, or Hoenn's by its own numbers)
    local regional = {}
    if rse then
      for _, e in ipairs(national) do
        local okR, n = pcall(Dex.regionalNumber, e.sp, gameId())
        n = okR and tonumber(n) or nil
        if n and n >= 1 then
          local r = newEntry(Pk, Dex, dex, e.sp, e.nat, n)
          regional[#regional + 1] = r
        end
      end
      table.sort(regional, function(a, b) return a.num < b.num end)
    else
      for i = 1, min(151, #national) do regional[i] = national[i] end
    end
    local rmode = rse and "hoenn" or "kanto"
    book.modes[1], book.lists[rmode] = rmode, regional
    local PD = engine("src.core.game3.pokedex_data")
    local okU, unlocked = pcall(PD and PD.isNationalUnlocked or error, s, dex)
    if okU and unlocked then
      book.modes[2], book.lists.national = "national", national
    end
    for _, mode in ipairs(book.modes) do
      local seen, caught = 0, 0
      for _, e in ipairs(book.lists[mode]) do
        if e.seen then seen = seen + 1 end
        if e.caught then caught = caught + 1 end
      end
      book.counts[mode] = { seen = seen, caught = caught }
    end
    return book
  end

  -- ------- a page's pieces

  local function heightText(dm)
    dm = tonumber(dm) or 0
    local tenths = floor(10000 * dm / 254)
    if tenths % 10 >= 5 then tenths = tenths + 10 end
    local ft = floor(tenths / 120)
    local inch = floor((tenths - ft * 120) / 10)
    return ("%.1f m  ·  %d'%02d\""):format(dm / 10, ft, inch)
  end
  local function weightText(hg)
    hg = tonumber(hg) or 0
    local hund = floor((hg * 100000) / 4536)
    if hund % 10 >= 5 then hund = hund + 10 end
    return ("%.1f kg  ·  %d.%d lbs"):format(hg / 10, floor(hund / 100), floor((hund % 100) / 10))
  end

  local function description(sp)
    if family() == "rse" then
      if entriesPack == nil then
        local Mapsec = engine("src.ui.game3.rse.mapsec")
        local ok, pack = pcall(Mapsec and Mapsec.readLua or error, "pokemon/pokedex/entries.lua")
        entriesPack = ok and type(pack) == "table" and pack or false
      end
      local e = entriesPack and entriesPack[sp]
      if not e then return "" end
      local one = paragraph(e.description)
      local two = paragraph(e.description2)
      if two ~= "" and two ~= one then return one .. " " .. two end
      return one
    end
    local PD = engine("src.core.game3.pokedex_data")
    local ok, e = pcall(PD and PD.getEntry or error, sp)
    return ok and type(e) == "table" and paragraph(e.description) or ""
  end

  local function typeName(id)
    if deps.typeName then return deps.typeName(id) end
    return tostring(id)
  end

  local function moveRow(Pk, id, tag)
    local okM, m = pcall(Pk.battleMove, id)
    m = okM and type(m) == "table" and m or {}
    local okN, name = pcall(Pk.moveName, id)
    local Types = engine("src.core.game3.battle.types")
    local t = tonumber(m.type) or 0
    local okP, phys = pcall(Types and Types.isPhysical or error, t)
    local power, acc = tonumber(m.power) or 0, tonumber(m.accuracy) or 0
    return { id = id, name = titled(okN and name or ("#" .. tostring(id))), typeId = t, typeName = typeName(t),
             powerText = power > 1 and tostring(power) or "-", accText = acc > 0 and tostring(acc) or "-",
             ppText = tostring(tonumber(m.pp) or 0), physical = okP and phys == true, status = power == 0,
             tag = tag or "" }
  end

  local function moves(Pk, sp)
    local out = { level = {}, tm = {}, egg = {}, tutor = {} }
    local okL, ls = pcall(Pk.learnset, sp)
    for _, r in ipairs(okL and ls or {}) do
      local lv, mv = tonumber(r[1] or r.level), tonumber(r[2] or r.move)
      if mv then out.level[#out.level + 1] = moveRow(Pk, mv, lv and lv > 0 and tostring(lv) or "-") end
    end
    local machines = Pk._tmhm and Pk._tmhm.machines
    for i = 0, 57 do
      local okC, can = pcall(Pk.canLearnTmIndex, sp, i)
      local mv = machines and tonumber(machines[i])
      if okC and can and mv then
        local tag = i < 50 and ("TM%02d"):format(i + 1) or ("HM%02d"):format(i - 49)
        out.tm[#out.tm + 1] = moveRow(Pk, mv, tag)
      end
    end
    local okE, eggs = pcall(Pk.eggMoves, sp)
    for _, mv in ipairs(okE and eggs or {}) do out.egg[#out.egg + 1] = moveRow(Pk, mv) end
    local ML = engine("src.core.game3.move_learn")
    local okT, tutors = pcall(ML and ML.tutorMoves or error)
    if okT and type(tutors) == "table" then
      for i = 0, 63 do
        local mv = tutors[i]
        if not mv then break end
        local okC, can = pcall(ML.canLearnTutorMove, sp, i)
        if okC and can then out.tutor[#out.tutor + 1] = moveRow(Pk, mv) end
      end
    end
    return out
  end

  -- (each species' evolution parent, once a dex opening: the chain walks back to its first stage)
  local function parents(Pk)
    if prevOf then return prevOf end
    prevOf = {}
    for sp, list in pairs(Pk._evolutions or {}) do
      for _, e in ipairs(type(list) == "table" and list or {}) do
        local to = tonumber(e.target)
        if to and not prevOf[to] then prevOf[to] = tonumber(sp) end
      end
    end
    return prevOf
  end
  local function howEvolves(e)
    local m, p = tonumber(e.method) or 0, tonumber(e.param) or 0
    local item = function() return deps.itemName and deps.itemName(p) or ("#" .. p) end
    if m == 4 then return word("dex.evo.level", p) end
    if m == 1 then return word("dex.evo.friendship") end
    if m == 2 then return word("dex.evo.friendDay") end
    if m == 3 then return word("dex.evo.friendNight") end
    if m == 5 then return word("dex.evo.trade") end
    if m == 6 then return word("dex.evo.tradeItem", item()) end
    if m == 7 then return word("dex.evo.item", item()) end
    if m == 8 then return word("dex.evo.atkGt", p) end
    if m == 9 then return word("dex.evo.atkEq", p) end
    if m == 10 then return word("dex.evo.atkLt", p) end
    if m == 11 or m == 12 then return word("dex.evo.random", p) end
    if m == 13 then return word("dex.evo.level", p) end
    if m == 14 then return word("dex.evo.shedinja", p) end
    if m == 15 then return word("dex.evo.beauty") end
    return word("dex.evo.other")
  end
  local function evolutions(Pk, sp)
    local prev = parents(Pk)
    local base, guard = sp, 0
    while prev[base] and guard < 8 do base, guard = prev[base], guard + 1 end
    local out = {}
    local function walk(from, depth)
      if depth > 6 then return end
      local okE, list = pcall(Pk.evolutions, from)
      for _, e in ipairs(okE and list or {}) do
        local to = tonumber(e.target)
        if to then
          local okN, raw = pcall(Pk.name, to)
          out[#out + 1] = { from = from, to = to, toName = (nameOf(okN and raw or "?")), how = howEvolves(e),
                            depth = depth }
          walk(to, depth + 1)
        end
      end
    end
    walk(base, 1)
    local okB, rawB = pcall(Pk.name, base)
    return out, base, (nameOf(okB and rawB or "?"))
  end

  -- (where each species is found in the wild: one pass over the game's encounter tables, the first
  -- time any page asks)
  local function where()
    if whereOf then return whereOf end
    whereOf = {}
    local E, MC = engine("src.core.game3.encounters"), engine("src.import.gba.map_catalog")
    local okE, cache = pcall(E and E.loadCacheFile or error)
    if not (okE and type(cache) == "table") then return whereOf end
    local places = {}
    local function placeOf(entry, key)
      local id
      if MC and MC.mapIdFor and entry.mapGroup then
        local okI, got = pcall(MC.mapIdFor, entry.mapGroup, entry.mapNum)
        id = okI and got or nil
      end
      local cacheKey = id or key
      local name = places[cacheKey]
      if not name then
        name = deps.placeName and id and deps.placeName(id) or titled((tostring(key):gsub("_", " ")))
        places[cacheKey] = name
      end
      return name
    end
    local function add(sp, place, method, lo, hi, chance)
      sp = tonumber(sp)
      if not sp then return end
      local list = whereOf[sp]
      if not list then
        list = {}
        whereOf[sp] = list
      end
      for _, r in ipairs(list) do
        if r.place == place and r.method == method then
          r.lo, r.hi, r.chance = min(r.lo, lo), max(r.hi, hi), r.chance + chance
          return
        end
      end
      list[#list + 1] = { place = place, method = method, lo = lo, hi = hi, chance = chance }
    end
    local function section(sec, weights, method, place)
      if type(sec) ~= "table" or type(sec.slots) ~= "table" then return end
      for i, s in ipairs(sec.slots) do
        local w = weights[i] or 0
        add(s.species, place, method, tonumber(s.minLevel) or 0, tonumber(s.maxLevel or s.minLevel) or 0, w)
      end
    end
    -- (a map the cache files under two keys counted once)
    local done = {}
    for key, entry in pairs(cache) do
      local id = type(entry) == "table" and entry.mapGroup and (entry.mapGroup .. ":" .. tostring(entry.mapNum)) or entry
      if type(entry) == "table" and not done[id] then
        done[id] = true
        local place = placeOf(entry, key)
        section(entry.land, LAND_W, "grass", place)
        section(entry.water, WATER_W, "surf", place)
        section(entry.rocks, WATER_W, "rock", place)
        local f = entry.fishing
        if type(f) == "table" and type(f.slots) == "table" then
          for i, s in ipairs(f.slots) do
            local rod = FISH[i]
            if rod then
              add(s.species, place, rod[1], tonumber(s.minLevel) or 0, tonumber(s.maxLevel or s.minLevel) or 0, rod[2])
            end
          end
        end
      end
    end
    for _, list in pairs(whereOf) do
      table.sort(list, function(a, b)
        if a.place ~= b.place then return a.place < b.place end
        return (METHOD_ORDER[a.method] or 9) < (METHOD_ORDER[b.method] or 9)
      end)
      for _, r in ipairs(list) do
        r.methodText = word("dex.where." .. r.method)
        r.levels = r.lo == r.hi and word("dex.lv", r.lo) or word("dex.lvRange", r.lo, r.hi)
        r.chanceText = ("%d%%"):format(min(100, r.chance))
      end
    end
    return whereOf
  end

  local function info(Pk, sp, meta)
    local out = {}
    local function add(label, value) out[#out + 1] = { label = word(label), value = value } end
    if meta then
      local g1, g2 = tonumber(meta.eggGroup1) or 0, tonumber(meta.eggGroup2) or 0
      local groups = word("dex.egg." .. g1)
      if g2 ~= g1 and g2 > 0 then groups = groups .. ", " .. word("dex.egg." .. g2) end
      add("dex.info.eggGroups", groups)
      add("dex.info.hatch", tostring((tonumber(meta.eggCycles) or 0) * 256))
      add("dex.info.catch", tostring(tonumber(meta.catchRate) or 0))
      add("dex.info.exp", tostring(tonumber(meta.expYield) or 0))
      add("dex.info.growth", word("dex.growth." .. (GROWTH[tonumber(meta.growthRate) or 0] or "medium_fast")))
      local ev = {}
      local EVS = { { "evHp", "dex.stat.hp" }, { "evAtk", "dex.stat.atk" }, { "evDef", "dex.stat.def" },
                    { "evSpa", "dex.stat.spa" }, { "evSpd", "dex.stat.spd" }, { "evSpe", "dex.stat.spe" } }
      for _, e in ipairs(EVS) do
        local n = tonumber(meta[e[1]]) or 0
        if n > 0 then ev[#ev + 1] = n .. " " .. word(e[2]) end
      end
      add("dex.info.ev", #ev > 0 and table.concat(ev, ", ") or word("dex.none"))
      local items = {}
      for _, k in ipairs({ "itemCommon", "itemRare" }) do
        local id = tonumber(meta[k]) or 0
        if id > 0 then items[#items + 1] = deps.itemName and deps.itemName(id) or ("#" .. id) end
      end
      add("dex.info.items", #items > 0 and table.concat(items, ", ") or word("dex.none"))
      add("dex.info.friend", tostring(tonumber(meta.friendship) or 0))
    end
    return out
  end

  -- ------- the page

  function Dx.page(entry)
    local sp = entry and entry.sp
    if not sp then return nil end
    local pg = pages[sp]
    if pg then return pg end
    local Pk = P()
    if not Pk then return nil end
    pg = {}
    local okD, de = pcall(Pk.dexEntry, sp)
    de = okD and type(de) == "table" and de or {}
    pg.category = de.category and word("dex.category", titled(de.category)) or ""
    pg.heightText, pg.weightText = heightText(de.height), weightText(de.weight)
    -- (types: the species' own row, not a copy)
    local t = Pk._types and Pk._types[sp]
    pg.types = {}
    if t then
      pg.types[1] = { id = t[1] or 0, name = typeName(t[1] or 0) }
      if t[2] and t[2] ~= t[1] then pg.types[2] = { id = t[2], name = typeName(t[2]) } end
    end
    local okS, st = pcall(Pk.stats, sp)
    st = okS and type(st) == "table" and st or {}
    pg.stats = { tonumber(st.hp) or 0, tonumber(st.atk) or 0, tonumber(st.def) or 0, tonumber(st.spa) or 0,
                 tonumber(st.spd) or 0, tonumber(st.spe) or 0 }
    pg.total = 0
    for i = 1, 6 do pg.total = pg.total + pg.stats[i] end
    pg.totalText = tostring(pg.total)
    pg.statText = {}
    for i = 1, 6 do pg.statText[i] = tostring(pg.stats[i]) end
    local okM, meta = pcall(Pk.speciesMeta, sp)
    meta = okM and type(meta) == "table" and meta or nil
    local ratio = meta and tonumber(meta.genderRatio) or 127
    if ratio >= 255 then pg.female = nil
    elseif ratio >= 254 then pg.female = 1
    elseif ratio <= 0 then pg.female = 0
    else pg.female = (ratio + 1) / 256 end
    if pg.female then
      pg.maleText = ("%g%%"):format(floor((1 - pg.female) * 1000 + 0.5) / 10)
      pg.femaleText = ("%g%%"):format(floor(pg.female * 1000 + 0.5) / 10)
    end
    pg.description = description(sp)
    -- (abilities: each one's name and the game's words for it)
    pg.abilities = {}
    local ab = Pk._abilities and Pk._abilities[sp]
    local SD = engine("src.core.game3.summary_data")
    local seen = {}
    for _, id in ipairs(type(ab) == "table" and ab or {}) do
      id = tonumber(id)
      if id and id > 0 and not seen[id] then
        seen[id] = true
        local okA, name = pcall(Pk.abilityName, id)
        local okW, desc = pcall(SD and SD.abilityDescription or error, id)
        pg.abilities[#pg.abilities + 1] = { name = titled(okA and name or "?"), desc = paragraph(okW and desc or "") }
      end
    end
    pg.evolutions, pg.base, pg.baseName = evolutions(Pk, sp)
    pg.info = info(Pk, sp, meta)
    pg.moves = moves(Pk, sp)
    local w = where()[sp] or {}
    pg.where = w
    -- (WoobleDex: its forms, and whether it can Gigantamax)
    pg.forms = {}
    local wd = deps.wooble and deps.wooble()
    if wd then
      local okF, forms = pcall(wd.formsOf or error, entry.nat)
      for _, f in ipairs(okF and type(forms) == "table" and forms or {}) do
        local label = wd.formLabel and select(2, pcall(wd.formLabel, f.slot)) or nil
        pg.forms[#pg.forms + 1] = type(label) == "string" and label or titled((tostring(f.form or "?"):gsub("_", " ")))
      end
      local dmax = wd.dynamax
      local okG, gmax = pcall(dmax and dmax.gmaxMoveOf or error, sp)
      if okG and gmax then pg.info[#pg.info + 1] = { label = word("dex.info.gmax"), value = word("dex.yes") } end
    end
    if #pg.forms > 0 then pg.info[#pg.info + 1] = { label = word("dex.info.forms"), value = table.concat(pg.forms, ", ") } end
    pages[sp] = pg
    return pg
  end

  Dx.titled = titled
  return Dx
end
