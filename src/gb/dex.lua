-- The Pokédex's model on the Game Boy games, the same interface as src/dex.lua so the Pokédex window is the
-- same: every Pokémon the game knows in the dex's order (Gen 1: Kanto's 151; Gen 2: the new Johto order,
-- and the National one), which are seen and caught (save.pokedex), and each one's page from the game's own
-- data -- its category, height and weight, types, base stats (Gen 1's one Special as both), gender (Gen 2),
-- the dex's words, evolutions, egg groups and the rest (Gen 2), its moves (level, TM / HM, egg, tutor) and
-- where it's found (grass, water, Gen 1's rods). No abilities on these games. Read only.
--
--   Dx = dex(host, Gd, deps)   deps: T ; place(mapId) -> its name; spawnArea (src/spawn_area.lua: WoobleSpawns'
--                              places, while it's on; its ids are the game's own, as these are)
--   (the interface: src/dex.lua's header; a page's noGender: Gen 1's Pokémon have none)

local floor, max, min = math.floor, math.max, math.min

local EGG = { EGG_MONSTER = 1, EGG_WATER_1 = 2, EGG_BUG = 3, EGG_FLYING = 4, EGG_GROUND = 5, EGG_FIELD = 5,
              EGG_FAIRY = 6, EGG_PLANT = 7, EGG_GRASS = 7, EGG_HUMANSHAPE = 8, EGG_WATER_3 = 9, EGG_MINERAL = 10,
              EGG_INDETERMINATE = 11, EGG_WATER_2 = 12, EGG_DITTO = 13, EGG_DRAGON = 14, EGG_NONE = 15 }
local GROWTH = { MEDIUM_FAST = "medium_fast", MEDIUM_SLOW = "medium_slow", FAST = "fast", SLOW = "slow",
                 SLIGHTLY_FAST = "medium_fast", SLIGHTLY_SLOW = "medium_slow" }
-- (a wild slot's share: Gen 1's ten grass slots, Gen 2's seven grass and three water)
local G1_LAND = { 20, 20, 15, 10, 10, 10, 5, 5, 4, 1 }
local G2_LAND = { 30, 30, 20, 10, 5, 4, 1 }
local WATER = { 60, 30, 10 }
local METHOD_ORDER = { grass = 1, surf = 2, rock = 3, old = 4, good = 5, super = 6 }
-- (the types Gen 1 / 2 count physical)
local PHYSICAL = { NORMAL = true, FIGHTING = true, FLYING = true, POISON = true, GROUND = true, ROCK = true, BUG = true,
                   GHOST = true, STEEL = true, BIRD = true }
local KEEP = { HP = true, PP = true, TM = true, HM = true }
local function unshout(text)
  return (text:gsub("[%a\195\169]+", function(w)
    if #w < 2 or w:find("%l") or KEEP[w] then return w end
    return w:sub(1, 1) .. w:sub(2):lower()
  end))
end
local function paragraph(text)
  if type(text) ~= "string" then return "" end
  text = text:gsub("<NEXT>", " "):gsub("{[^}]*}", ""):gsub("[\r\n\f\v]+", " "):gsub("%s+", " ")
  return unshout((text:gsub("^%s+", ""):gsub("%s+$", "")))
end

return function(H, Gd, deps)
  deps = deps or {}
  local T = deps.T
  local gen = H.gen
  -- (Dx.spawnArea: WoobleSpawns' places; the tests swap it)
  local Dx = { spawnArea = deps.spawnArea }
  local function word(key, ...)
    if not T then return key end
    if select("#", ...) > 0 then return T.f(key, ...) end
    return T(key)
  end

  local pages, prevOf, whereOf, tmTag = {}, nil, nil, nil
  function Dx.reset() pages, prevOf, whereOf, tmTag = {}, nil, nil, nil end
  Dx.titled = Gd.title

  function Dx.available(s)
    if not s then return false end
    if gen == 2 then return type(s.engineFlags) == "table" and s.engineFlags[11] == true end
    local f = s.flags or {}
    return f.EVENT_GOT_POKEDEX ~= nil and f.EVENT_GOT_POKEDEX ~= false
  end

  -- ------- the list
  local function sets(s)
    local dex = s and s.pokedex or {}
    return dex.seen or {}, (gen == 2 and dex.caught or dex.owned) or {}
  end
  local function nameOf(sp)
    local name, sex = Gd.speciesName(sp), nil
    if tostring(sp):match("_F$") then sex = "f" elseif tostring(sp):match("_M$") then sex = "m" end
    if sex then name = name:gsub("[%s_]*[FfMm]$", ""):gsub("\226\153[\128\130]", "") end
    return name, sex
  end
  local function entry(sp, num, seenSet, caughtSet)
    local name, sex = nameOf(sp)
    local caught = caughtSet[sp] == true
    local t = Gd.typesOf(sp)
    return { sp = sp, nat = Gd.dex(sp), num = num, numText = ("%03d"):format(num), name = name, sex = sex,
             seen = caught or seenSet[sp] == true, caught = caught, t1 = t[1] and t[1].id or nil }
  end
  function Dx.open(s)
    local book = { modes = {}, lists = {}, counts = {} }
    local seenSet, caughtSet = sets(s)
    local all = Gd.species()
    local national = {}
    for _, sp in ipairs(all) do
      local n = Gd.dex(sp)
      if n >= 1 then national[#national + 1] = entry(sp, n, seenSet, caughtSet) end
    end
    if gen == 2 then
      local d = Gd.data()
      local order = d and d.gen2Pokedex and d.gen2Pokedex.newOrder
      local johto = {}
      for i, sp in ipairs(type(order) == "table" and order or {}) do
        if Gd.def(sp) then johto[#johto + 1] = entry(sp, i, seenSet, caughtSet) end
      end
      if #johto > 0 then
        book.modes[#book.modes + 1] = "johto"
        book.lists.johto = johto
      end
    end
    book.modes[#book.modes + 1] = gen == 1 and "kanto" or "national"
    book.lists[book.modes[#book.modes]] = national
    for mode, list in pairs(book.lists) do
      local seen, caught = 0, 0
      for _, e in ipairs(list) do
        if e.seen then seen = seen + 1 end
        if e.caught then caught = caught + 1 end
      end
      book.counts[mode] = { seen = seen, caught = caught }
    end
    return book
  end

  -- ------- a page's pieces

  local function heights(inches)
    inches = tonumber(inches) or 0
    local m = inches * 0.0254
    return ("%.1f m"):format(m), ("%d'%02d\""):format(floor(inches / 12), floor(inches % 12))
  end
  local function weights(tenthsLb)
    local lb = (tonumber(tenthsLb) or 0) / 10
    return ("%.1f kg"):format(lb * 0.45359), ("%.1f lbs"):format(lb)
  end

  local function moveRow(id, tag)
    local d = Gd.data()
    local m = d and d.moves and d.moves[id] or {}
    local t = m.type or "NORMAL"
    local power, acc = tonumber(m.power) or 0, tonumber(m.accuracy) or 0
    return { id = id, name = Gd.moveName(id), typeId = Gd.typeId(t), typeName = Gd.typeName(t),
             powerText = power > 1 and tostring(power) or "-", accText = acc > 0 and tostring(floor(acc)) or "-",
             ppText = tostring(tonumber(m.pp) or 0), physical = PHYSICAL[tostring(t):gsub("_TYPE$", "")] == true,
             status = power == 0, tag = tag or "" }
  end
  -- (a move's TM / HM number, from the game's own machines)
  local function tagOf(move)
    if not tmTag then
      tmTag = {}
      local d = Gd.data()
      for _, it in pairs(d and d.items or {}) do
        local mv = type(it) == "table" and (it.teaches or (it.machine and it.machine.move))
        local label = type(it) == "table" and (it.tmLabel or it.name)
        if mv and label then tmTag[mv] = tostring(label) end
      end
    end
    return tmTag[move]
  end
  local function moves(sp)
    local def = Gd.def(sp) or {}
    local out = { level = {}, tm = {}, egg = {}, tutor = {} }
    for _, mv in ipairs(def.level1Moves or {}) do out.level[#out.level + 1] = moveRow(mv, "1") end
    for _, r in ipairs(def.levelMoves or def.learnset or {}) do
      out.level[#out.level + 1] = moveRow(r.move, tostring(r.level or "-"))
    end
    local d = Gd.data()
    local tutor = {}
    for _, mv in ipairs(gen == 2 and d and d.pokemon and d.pokemon.tutorMoves or {}) do tutor[mv] = true end
    local rows = {}
    for _, mv in ipairs(def.tmhm or {}) do
      if tutor[mv] then
        out.tutor[#out.tutor + 1] = moveRow(mv)
      else
        local tag = tagOf(mv) or ""
        rows[#rows + 1] = moveRow(mv, tag)
      end
    end
    -- (TMs first, by number, then HMs)
    table.sort(rows, function(a, b)
      local ah, bh = a.tag:sub(1, 2) == "HM", b.tag:sub(1, 2) == "HM"
      if ah ~= bh then return not ah end
      return a.tag < b.tag
    end)
    out.tm = rows
    for _, mv in ipairs(def.eggMoves or {}) do out.egg[#out.egg + 1] = moveRow(mv) end
    return out
  end

  local function parents()
    if prevOf then return prevOf end
    prevOf = {}
    for _, sp in ipairs(Gd.species()) do
      local def = Gd.def(sp)
      for _, e in ipairs(def and def.evolutions or {}) do
        local to = e.into or e.species
        if to and not prevOf[to] then prevOf[to] = sp end
      end
    end
    return prevOf
  end
  local function howEvolves(e)
    local m = tostring(e.method or ""):gsub("^EVOLVE_", "")
    local lv = tonumber(e.level) or 0
    local function item() return Gd.itemName(e.item) end
    if m == "LEVEL" then return word("dex.evo.level", lv) end
    if m == "ITEM" then return word("dex.evo.item", item()) end
    if m == "TRADE" then
      if e.item and e.item ~= "" and e.item ~= "NO_ITEM" then return word("dex.evo.tradeItem", item()) end
      return word("dex.evo.trade")
    end
    if m == "HAPPINESS" then
      if e.time == "MORNDAY" then return word("dex.evo.friendDay") end
      if e.time == "NITE" then return word("dex.evo.friendNight") end
      return word("dex.evo.friendship")
    end
    if m == "STAT" then
      local c = tostring(e.cmp or e.stat or e.param or "")
      if c:find("GT") then return word("dex.evo.atkGt", lv) end
      if c:find("LT") then return word("dex.evo.atkLt", lv) end
      return word("dex.evo.atkEq", lv)
    end
    return word("dex.evo.other")
  end
  local function evolutions(sp)
    local prev = parents()
    local base, guard = sp, 0
    while prev[base] and guard < 8 do base, guard = prev[base], guard + 1 end
    local out = {}
    local function walk(from, depth)
      if depth > 6 then return end
      local def = Gd.def(from)
      for _, e in ipairs(def and def.evolutions or {}) do
        local to = e.into or e.species
        if to and Gd.def(to) then
          out[#out + 1] = { from = from, to = to, toName = (nameOf(to)), how = howEvolves(e), depth = depth }
          walk(to, depth + 1)
        end
      end
    end
    walk(base, 1)
    return out, base, (nameOf(base))
  end

  -- (a list's order and words, as src/dex.lua's)
  local function finish(list)
    table.sort(list, function(a, b)
      if a.place ~= b.place then return a.place < b.place end
      return (METHOD_ORDER[a.method] or 9) < (METHOD_ORDER[b.method] or 9)
    end)
    for _, r in ipairs(list) do
      r.methodText = word("dex.where." .. r.method)
      if r.when then r.methodText = r.methodText .. " · " .. word("dex.where." .. r.when) end
      r.levels = r.lo == r.hi and word("dex.lv", r.lo) or word("dex.lvRange", r.lo, r.hi)
      if r.rare then r.chanceText = word("dex.where.rare")
      elseif r.chance > 0 and r.chance < 1 then r.chanceText = "<1%"
      else r.chanceText = ("%d%%"):format(min(100, floor(r.chance + 0.5))) end
    end
    return list
  end

  -- (where each species is found: one pass over the game's wild tables)
  local function where()
    if whereOf then return whereOf end
    whereOf = {}
    local d = Gd.data()
    if not d then return whereOf end
    local place = deps.place or function(m) return tostring(m) end
    local function add(sp, mapId, method, lv, chance)
      if not sp then return end
      local list = whereOf[sp]
      if not list then
        list = {}
        whereOf[sp] = list
      end
      local p = place(mapId)
      lv = tonumber(lv) or 0
      for _, r in ipairs(list) do
        if r.place == p and r.method == method then
          r.lo, r.hi, r.chance = min(r.lo, lv), max(r.hi, lv), r.chance + chance
          return
        end
      end
      list[#list + 1] = { place = p, method = method, lo = lv, hi = lv, chance = chance }
    end
    if gen == 2 then
      local E = d.gen2Encounters or {}
      for mapId, t in pairs(E.grass or {}) do
        -- (the day's slots: the morning's and night's alike count once each)
        local seen = {}
        for _, part in pairs(type(t) == "table" and t.slots or {}) do
          for i, sl in ipairs(part) do
            local k = tostring(sl.species) .. ":" .. i
            if not seen[k] then
              seen[k] = true
              add(sl.species, mapId, "grass", sl.level, G2_LAND[i] or 1)
            end
          end
        end
      end
      for mapId, t in pairs(E.water or {}) do
        for i, sl in ipairs(type(t) == "table" and t.slots or {}) do add(sl.species, mapId, "surf", sl.level, WATER[i] or 1) end
      end
    else
      for mapId, t in pairs(d.encounters or {}) do
        local g, w = type(t) == "table" and t.grass, type(t) == "table" and t.water
        for i, sl in ipairs(g and g.slots or {}) do add(sl.species, mapId, "grass", sl.level, G1_LAND[i] or 1) end
        for i, sl in ipairs(w and w.slots or {}) do add(sl.species, mapId, "surf", sl.level, G1_LAND[i] or 1) end
      end
      for mapId, list in pairs(d.field and d.field.superRod or {}) do
        local n = #list
        for _, sl in ipairs(list) do add(sl.species, mapId, "super", sl.level, floor(100 / max(1, n))) end
      end
    end
    for _, list in pairs(whereOf) do finish(list) end
    return whereOf
  end

  -- (with WoobleSpawns on: the cart's rows give way to its own -- it writes its species into the very
  -- tables read above, but not the other species each slot can turn into, nor the rods' on Gold, Silver and
  -- Crystal; one place under several maps one row, its best chance)
  local function whereNow(sp)
    local cart = where()[sp] or {}
    local Sa = Dx.spawnArea
    local rows = Sa and Sa.rows(sp)
    if not rows then return cart end
    local place = deps.place or function(m) return tostring(m) end
    local list, byKey = {}, {}
    for _, r in ipairs(cart) do
      if not Sa.replaces(r.method) then list[#list + 1] = r end
    end
    for _, r in ipairs(rows) do
      local p = place(r.mapId)
      local key = p .. "|" .. r.method
      local had = byKey[key]
      if had then
        had.lo, had.hi = min(had.lo, r.lo), max(had.hi, r.hi)
        had.chance = max(had.chance, r.chance)
        had.rare = had.rare and r.rare
        if had.when ~= r.when then had.when = nil end
      else
        had = { place = p, method = r.method, lo = r.lo, hi = r.hi, chance = r.chance, rare = r.rare, when = r.when }
        byKey[key] = had
        list[#list + 1] = had
      end
    end
    return finish(list)
  end

  local function info(def)
    local out = {}
    local function add(label, value) out[#out + 1] = { label = word(label), value = value } end
    if gen == 2 then
      local groups = {}
      for _, g in ipairs(def.eggGroups or {}) do
        local w = word("dex.egg." .. (EGG[g] or 0))
        if groups[#groups] ~= w then groups[#groups + 1] = w end
      end
      add("dex.info.eggGroups", #groups > 0 and table.concat(groups, ", ") or word("dex.none"))
      add("dex.info.hatch", tostring((tonumber(def.eggSteps) or 0) * 256))
    end
    add("dex.info.catch", tostring(tonumber(def.catchRate) or 0))
    add("dex.info.exp", tostring(tonumber(def.baseExp) or 0))
    local g = tostring(def.growthRate or ""):gsub("^GROWTH_", "")
    add("dex.info.growth", word("dex.growth." .. (GROWTH[g] or "medium_fast")))
    if gen == 2 then
      local items = {}
      for _, it in ipairs(def.items or {}) do
        if it and it ~= "NO_ITEM" then items[#items + 1] = Gd.itemName(it) end
      end
      add("dex.info.items", #items > 0 and table.concat(items, ", ") or word("dex.none"))
    end
    return out
  end

  -- ------- the page

  -- where it's found alone (one not seen yet: the window shows only this)
  function Dx.where(e)
    return e and e.sp and whereNow(e.sp) or {}
  end

  function Dx.page(e)
    local sp = e and e.sp
    if not sp then return nil end
    local pg = pages[sp]
    if pg then
      pg.where = whereNow(sp)
      return pg
    end
    local def = Gd.def(sp)
    if not def then return nil end
    local d = Gd.data()
    pg = {}
    local kind, inches, tenths, text
    if gen == 2 then
      local de = d and d.gen2Pokedex and d.gen2Pokedex.entries and d.gen2Pokedex.entries[sp] or {}
      kind = de.kind
      local h = tonumber(de.height) or 0
      inches = floor(h / 100) * 12 + h % 100
      tenths = de.weight
      local one, two = paragraph(de.text), paragraph(de.text2)
      text = two ~= "" and (one .. " " .. two) or one
    else
      local de = def.dexEntry or {}
      kind = de.kind
      inches = (tonumber(de.heightFt) or 0) * 12 + (tonumber(de.heightIn) or 0)
      tenths = de.weight
      text = paragraph(de.text and d and d.text and d.text[de.text] or "")
    end
    pg.category = kind and word("dex.category", Gd.title(kind)) or ""
    pg.heightM, pg.heightI = heights(inches)
    pg.heightMeters = (tonumber(inches) or 0) * 0.0254
    pg.weightM, pg.weightI = weights(tenths)
    pg.heightText = pg.heightM .. "  ·  " .. pg.heightI
    pg.weightText = pg.weightM .. "  ·  " .. pg.weightI
    pg.types = {}
    for i, t in ipairs(Gd.typesOf(sp)) do pg.types[i] = { id = t.id, name = t.name } end
    local b = def.baseStats or {}
    local spa = tonumber(b.specialAttack or b.special) or 0
    local spd = tonumber(b.specialDefense or b.special) or 0
    pg.stats = { tonumber(b.hp) or 0, tonumber(b.attack) or 0, tonumber(b.defense) or 0, spa, spd, tonumber(b.speed) or 0 }
    -- (Gen 1's one Special counted once in the total, as its games add them up)
    pg.total = pg.stats[1] + pg.stats[2] + pg.stats[3] + pg.stats[6] + spa + (gen == 2 and spd or 0)
    pg.totalText = tostring(pg.total)
    pg.statText = {}
    for i = 1, 6 do pg.statText[i] = tostring(pg.stats[i]) end
    if gen == 2 then
      local r = tonumber(def.genderRatio) or 127
      if r >= 255 then pg.female = nil
      elseif r >= 254 then pg.female = 1
      elseif r <= 0 then pg.female = 0
      else pg.female = (r + 1) / 256 end
      if pg.female then
        pg.maleText = ("%g%%"):format(floor((1 - pg.female) * 1000 + 0.5) / 10)
        pg.femaleText = ("%g%%"):format(floor(pg.female * 1000 + 0.5) / 10)
      end
    else
      pg.noGender = true
    end
    pg.description = text
    pg.abilities = {}
    pg.evolutions, pg.base, pg.baseName = evolutions(sp)
    pg.info = info(def)
    pg.moves = moves(sp)
    pg.where = whereNow(sp)
    pg.forms = {}
    pages[sp] = pg
    return pg
  end

  return Dx
end
