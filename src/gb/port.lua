-- The Game Boy games' answers for the play-tied models written for Gen 3 (R-Bay, Slots, the GTS, Errands,
-- Challenges, the journal, the Bank): each model takes deps.port and asks it instead of the Gen 3 engine
-- where they differ -- money, the Bag, a Pokémon made and given, EXP, types, the National Dex. Without a
-- port the models run their Gen 3 code as before. Items the models name by their Gen 3 numbers are
-- translated here (ITEM); Pokémon are the games' own string ids ("PIKACHU").
--
--   Pt = port(host, Gd, deps)   deps: bank() -> the Bank (what doesn't fit the wallet), notify
--   Pt.gen ; Pt.MAX_DEX (151 | 251) ; Pt.item(id) -> the game's item id for a Gen 3 number (or the id)
--   Pt.money(s) / Pt.setMoney(s, n) / Pt.pay(s, n) -> what the wallet took (the rest to the Bank)
--   Pt.canGive(s, id, n) / Pt.giveItem(s, id, n) -> true | false ; Pt.itemName(id) ; Pt.itemDesc(id)
--   Pt.species(dex) -> id | nil ; Pt.dex(sp) ; Pt.name(sp) ; Pt.types(sp) -> { Gen 3 type numbers }
--   Pt.typesText(sp) ; Pt.evolutions(sp) -> { { into, level } } ; Pt.shinyOk (Gen 2 only)
--   Pt.make(sp, level, opts) -> mon   opts: ivs (Gen 3's six 0..31: made into DVs), shiny, ot, otId, traded
--   Pt.give(s, mon) -> "party" | "pc" | nil (no room)  (the Pokédex marks it seen and caught)
--   Pt.addExp(s, mon, n) -> levels gained ; Pt.hasMail(mon) ; Pt.isEgg(mon) ; Pt.usable(mon)
--   Pt.shiny(mon) ; Pt.monName(mon)

return function(H, Gd, deps)
  deps = deps or {}
  local engine = H.engine
  local gen = H.gen
  local floor, max, min = math.floor, math.max, math.min
  local Pt = { gen = gen, MAX_DEX = gen == 1 and 151 or 251, shinyOk = gen == 2 }

  -- ------- items: the Gen 3 numbers the models use, as these games' ids
  local ITEM = {
    [1] = "MASTER_BALL", [2] = "ULTRA_BALL", [3] = "GREAT_BALL", [4] = "POKE_BALL", [13] = "POTION",
    [14] = "ANTIDOTE", [15] = "BURN_HEAL", [16] = "ICE_HEAL", [17] = "AWAKENING", [18] = "PARLYZ_HEAL",
    [19] = "FULL_RESTORE", [20] = "MAX_POTION", [21] = "HYPER_POTION", [22] = "SUPER_POTION", [23] = "FULL_HEAL",
    [24] = "REVIVE", [25] = "MAX_REVIVE", [26] = "FRESH_WATER", [27] = "SODA_POP", [28] = "LEMONADE",
    [34] = "ETHER", [35] = "MAX_ETHER", [36] = "ELIXER", [37] = "MAX_ELIXER",
    [63] = "HP_UP", [64] = "PROTEIN", [65] = "IRON", [66] = "CARBOS", [67] = "CALCIUM", [68] = "RARE_CANDY",
    [69] = "PP_UP", [83] = "SUPER_REPEL", [84] = "MAX_REPEL", [85] = "ESCAPE_ROPE", [86] = "REPEL",
    [93] = "SUN_STONE", [94] = "MOON_STONE", [95] = "FIRE_STONE", [96] = "THUNDER_STONE", [97] = "WATER_STONE",
    [98] = "LEAF_STONE", [103] = "TINYMUSHROOM", [104] = "BIG_MUSHROOM", [106] = "PEARL", [107] = "BIG_PEARL",
    [108] = "STARDUST", [109] = "STAR_PIECE", [110] = "NUGGET",
    -- (the Berries: Gen 2's own names for the Gen 3 ones the jobs bring back)
    [133] = "BERRY", [134] = "PRZCUREBERRY", [135] = "MINT_BERRY", [136] = "PSNCUREBERRY", [137] = "BURNT_BERRY",
    [138] = "ICE_BERRY", [139] = "BERRY", [140] = "MYSTERYBERRY", [141] = "BITTER_BERRY", [142] = "GOLD_BERRY",
  }
  -- (what each has where the first answer isn't there: Gen 1's stand-ins)
  local INSTEAD = {
    THUNDER_STONE = "THUNDERSTONE", TINYMUSHROOM = "NUGGET", BIG_MUSHROOM = "NUGGET", PEARL = "NUGGET",
    BIG_PEARL = "NUGGET", STARDUST = "NUGGET", STAR_PIECE = "NUGGET", BERRY = "POTION", PRZCUREBERRY = "PARLYZ_HEAL",
    MINT_BERRY = "AWAKENING", PSNCUREBERRY = "ANTIDOTE", BURNT_BERRY = "ICE_HEAL", ICE_BERRY = "BURN_HEAL",
    MYSTERYBERRY = "ETHER", BITTER_BERRY = "FULL_HEAL", GOLD_BERRY = "SUPER_POTION", SUN_STONE = "MOON_STONE",
    ETHER = "SUPER_POTION", MAX_ETHER = "HYPER_POTION", ELIXER = "HYPER_POTION", MAX_ELIXER = "MAX_POTION",
    PP_UP = "RARE_CANDY",
  }
  function Pt.item(id)
    local got = type(id) == "number" and ITEM[id] or id
    if got and not Gd.item(got) then
      local alt = INSTEAD[got]
      if alt and Gd.item(alt) then return alt end
      alt = alt and INSTEAD[alt]
      if alt and Gd.item(alt) then return alt end
    end
    return got
  end
  Pt.ITEM = ITEM
  function Pt.itemName(id) return Gd.itemName(Pt.item(id)) end
  function Pt.itemDesc(id) return Gd.itemDesc(Pt.item(id)) end

  -- ------- money
  function Pt.money(s) return Gd.money(s) end
  function Pt.setMoney(s, n) Gd.setMoney(s, n) end
  function Pt.pay(s, n)
    n = floor(tonumber(n) or 0)
    if n <= 0 then return 0 end
    local took = Gd.addMoney(s, n)
    local rest = n - took
    local Bk = deps.bank and deps.bank()
    if rest > 0 and Bk and Bk.overflow then pcall(Bk.overflow, s, rest) end
    return took
  end

  -- ------- the Bag
  local function Bag() return engine("src.inventory.Bag") end
  function Pt.canGive(s, id, n)
    id = Pt.item(id)
    local B = Bag()
    if not (s and B and Gd.item(id)) then return false end
    local inv = s.inventory or {}
    if (tonumber(inv[id]) or 0) > 0 then return true end
    local pocket = Gd.gen == 2 and (Gd.item(id).pocket or "ITEM") or nil
    local okS, used = pcall(B.slots, s, Gd.data(), pocket)
    local okC, cap = pcall(B.capacity, Gd.data(), pocket)
    return okS and okC and (tonumber(used) or 0) < (tonumber(cap) or 20)
  end
  function Pt.giveItem(s, id, n)
    id = Pt.item(id)
    local B = Bag()
    if not (s and B and Gd.item(id)) then return false end
    local ok, done = pcall(B.add, s, id, n or 1, Gd.data())
    return ok and done == true
  end

  -- ------- species
  local byDex = nil
  function Pt.species(dex)
    if not byDex then
      byDex = {}
      for _, sp in ipairs(Gd.species()) do
        local d = Gd.dex(sp)
        if d > 0 and not byDex[d] then byDex[d] = sp end
      end
      if next(byDex) == nil then byDex = nil end
    end
    return byDex and byDex[tonumber(dex)] or nil
  end
  function Pt.dex(sp) return Gd.dex(sp) end
  function Pt.name(sp) return Gd.speciesName(sp) end
  function Pt.types(sp)
    local out = {}
    for i, t in ipairs(Gd.typesOf(sp)) do out[i] = t.id end
    return out
  end
  function Pt.typesText(sp)
    local t = Gd.typesOf(sp)
    if #t == 0 then return "" end
    if t[2] then return t[1].name .. " / " .. t[2].name end
    return t[1].name
  end
  -- (what it becomes by level: { into, level })
  function Pt.evolutions(sp)
    local def = Gd.def(sp)
    local out = {}
    for _, e in ipairs(def and def.evolutions or {}) do
      local into = e.into or e.species
      local lv = tonumber(e.level)
      local method = tostring(e.method or "")
      if into then out[#out + 1] = { into = into, level = (method:find("LEVEL") and lv) or nil, method = method } end
    end
    return out
  end

  function Pt.isEgg(mon) return Gd.isEgg(mon) end
  function Pt.usable(mon) return type(mon) == "table" and not Gd.isEgg(mon) and (tonumber(mon.hp) or 0) > 0 end
  function Pt.shiny(mon) return Gd.shiny(mon) end
  function Pt.monName(mon) return Gd.monName(mon) end
  function Pt.hasMail(mon)
    if gen ~= 2 then return false end
    local M = engine("src.core.gen2.Mail")
    local ok, yes = pcall(M and M.monHoldsMail or error, mon)
    return ok and yes == true
  end

  -- ------- a Pokémon made, and given
  local R = function(a, b)
    local r = love and love.math and love.math.random
    if r then return r(a, b) end
    return math.random(a, b)
  end
  -- Gen 3's six IVs (0..31) as the Game Boy's four DVs (0..15; HP's from their low bits); a Gen 2 shiny's
  -- DVs the game's own pattern (Defense, Speed, Special 10, Attack 2/3/6/7/10/11/14/15)
  local function dvsFrom(ivs, shiny)
    local function dv(v) return max(0, min(15, floor((tonumber(v) or R(0, 31)) / 2))) end
    local d = {}
    if ivs then
      d.attack, d.defense, d.speed = dv(ivs.atk), dv(ivs.def), dv(ivs.spe)
      d.special = dv(((tonumber(ivs.spa) or 0) + (tonumber(ivs.spd) or 0)) / 2)
    else
      d.attack, d.defense, d.speed, d.special = R(0, 15), R(0, 15), R(0, 15), R(0, 15)
    end
    if shiny and gen == 2 then
      local ok = { 2, 3, 6, 7, 10, 11, 14, 15 }
      local best = ok[1]
      for _, a in ipairs(ok) do if math.abs(a - d.attack) < math.abs(best - d.attack) then best = a end end
      d.attack, d.defense, d.speed, d.special = best, 10, 10, 10
    end
    d.hp = (d.attack % 2) * 8 + (d.defense % 2) * 4 + (d.speed % 2) * 2 + (d.special % 2)
    return d
  end
  Pt.dvsFrom = dvsFrom

  function Pt.make(sp, level, opts)
    opts = opts or {}
    local d = Gd.data()
    if not (d and Gd.def(sp)) then return nil end
    level = max(1, min(100, floor(tonumber(level) or 5)))
    local dvs = opts.dvs or dvsFrom(opts.ivs, opts.shiny)
    local mon
    if gen == 2 then
      local Mon = engine("src.battle.gen2.Mon")
      local ok, m = pcall(Mon.new, d, sp, level, { dvs = dvs, shiny = opts.shiny and true or nil, happiness = 70 })
      mon = ok and m or nil
      if mon and Mon.refreshStats then pcall(Mon.refreshStats, mon, d) end
    else
      local P, Stats = engine("src.pokemon.Pokemon"), engine("src.pokemon.Stats")
      local ok, m = pcall(P.new, d, sp, level, math.random)
      mon = ok and m or nil
      if mon then
        mon.dvs = { hp = dvs.hp, attack = dvs.attack, defense = dvs.defense, speed = dvs.speed, special = dvs.special }
        local okS, st = pcall(Stats.calc, Gd.def(sp), level, mon.dvs, mon.statExp)
        if okS and st then
          mon.stats = st
          mon.hp = st.hp
        end
      end
    end
    if not mon then return nil end
    mon.hp = Gd.maxHp(mon) > 0 and Gd.maxHp(mon) or mon.hp
    if opts.ot then
      mon.ot, mon.otName, mon.otId, mon.traded = opts.ot, opts.ot, opts.otId or R(0, 65535), opts.traded ~= false
    end
    return mon
  end

  -- (OT: the player, for one they win or buy)
  function Pt.stampOT(s, mon)
    local g = H.game()
    if gen == 2 then
      local Mon = engine("src.battle.gen2.Mon")
      if Mon and Mon.stampOT then pcall(Mon.stampOT, s, mon) end
    else
      local B = engine("src.battle.BattleState")
      if B and B.stampOT then pcall(B.stampOT, s, mon) end
    end
    return g ~= nil
  end

  -- into the party, else the current box (else the next with room) -> "party" | "pc" | nil
  function Pt.give(s, mon)
    if not (s and mon) then return nil end
    if mon.ot == nil and not mon.traded then Pt.stampOT(s, mon) end
    s.party = s.party or {}
    local where
    if #s.party < 6 then
      s.party[#s.party + 1] = mon
      where = "party"
    else
      local Bx = deps.bx and deps.bx()
      local n = Bx and Bx.BOXES or (gen == 2 and 14 or 12)
      local first = Bx and Bx.current(s) or 1
      for k = 0, n - 1 do
        local b = (first - 1 + k) % n + 1
        local box = Bx and Bx.boxMons(s, b)
        if box and #box < 20 then
          box[#box + 1] = mon
          if gen == 2 then
            local B = engine("src.core.gen2.Boxes")
            if B and B.enterBox then pcall(B.enterBox, mon, Gd.data()) end
          end
          where = "pc"
          break
        end
      end
    end
    if not where then return nil end
    -- (the Pokédex: seen and caught, as the game marks a gift)
    s.pokedex = s.pokedex or { seen = {} }
    s.pokedex.seen = s.pokedex.seen or {}
    s.pokedex.seen[mon.species] = true
    local set = gen == 2 and "caught" or "owned"
    s.pokedex[set] = s.pokedex[set] or {}
    s.pokedex[set][mon.species] = true
    return where
  end

  -- the Pokédex's marks for a Pokémon that's now the player's
  function Pt.mark(s, sp)
    if not (s and sp) then return end
    s.pokedex = s.pokedex or { seen = {} }
    s.pokedex.seen = s.pokedex.seen or {}
    s.pokedex.seen[sp] = true
    local set = gen == 2 and "caught" or "owned"
    s.pokedex[set] = s.pokedex[set] or {}
    s.pokedex[set][sp] = true
  end

  -- what a Pokémon just traded becomes (Kadabra, Machoke, Graveler, Haunter; Gen 2 also a held item's:
  -- Onix with the Metal Coat ...) -> species | nil
  function Pt.tradeTarget(mon)
    if type(mon) ~= "table" or Gd.isEgg(mon) then return nil end
    local def = Gd.def(mon.species)
    for _, e in ipairs(def and def.evolutions or {}) do
      local method = tostring(e.method or "")
      if method:find("TRADE") then
        local need = e.item or e.param
        if type(need) ~= "string" or need == "" or need == "NO_ITEM" or need == mon.item then
          return e.into or e.species
        end
      end
    end
    return nil
  end
  -- evolved where it stands (the held item a trade needed used up; a name that was only the species'
  -- follows it; its stats made again)
  function Pt.evolve(s, mon, target)
    if not (mon and target and Gd.def(target)) then return false end
    local old = mon.species
    local oldDef = Gd.def(old)
    local nameWasSpecies = mon.nickname == nil or (oldDef and mon.nickname == oldDef.name)
    mon.species = target
    if nameWasSpecies then
      mon.nickname = nil
      local def = Gd.def(target)
      if gen == 2 then mon.name = def and def.name or mon.name end
    end
    local def = Gd.def(old)
    for _, e in ipairs(def and def.evolutions or {}) do
      if tostring(e.method or ""):find("TRADE") and (e.into or e.species) == target and type(e.item) == "string" then
        if mon.item == e.item then mon.item = nil end
      end
    end
    local d = Gd.data()
    if gen == 2 then
      local Mon = engine("src.battle.gen2.Mon")
      if Mon and Mon.refreshStats then pcall(Mon.refreshStats, mon, d) end
    else
      local Stats = engine("src.pokemon.Stats")
      local oldMax = Gd.maxHp(mon)
      local ok, st = pcall(Stats.calc, Gd.def(target), Gd.level(mon), mon.dvs, mon.statExp)
      if ok and st then
        mon.stats = st
        mon.hp = math.min(st.hp, (tonumber(mon.hp) or 0) + (st.hp - oldMax))
      end
    end
    Pt.mark(s, target)
    return true
  end

  -- EXP out of battle -> levels gained (its stats made again, moves learnt at the levels passed)
  function Pt.addExp(s, mon, n)
    n = floor(tonumber(n) or 0)
    if not (mon and n > 0) or Gd.isEgg(mon) then return 0 end
    local before = Gd.level(mon)
    local d = Gd.data()
    if gen == 2 then
      local Mon = engine("src.battle.gen2.Mon")
      pcall(Mon.gainExperience, mon, n, d)
      pcall(Mon.refreshStats, mon, d)
    else
      local Growth, Stats, P = engine("src.pokemon.Growth"), engine("src.pokemon.Stats"), engine("src.pokemon.Pokemon")
      local def = Gd.def(mon.species)
      if not (Growth and Stats and def) then return 0 end
      mon.exp = (tonumber(mon.exp) or 0) + n
      local cap = tonumber(d and d.constants and d.constants.levelCap) or 100
      local okL, lv = pcall(Growth.levelForExp, def.growthRate, mon.exp, cap, d and d.growth_rates)
      if okL and tonumber(lv) and lv > before then
        local oldMax = Gd.maxHp(mon)
        mon.level = lv
        local okS, st = pcall(Stats.calc, def, lv, mon.dvs, mon.statExp)
        if okS and st then
          mon.stats = st
          mon.hp = math.min(st.hp, (tonumber(mon.hp) or 0) + (st.hp - oldMax))
        end
        if P and P.learnMovesFromDayCare then pcall(P.learnMovesFromDayCare, d, mon, def, before, lv) end
      end
    end
    return Gd.level(mon) - before
  end

  return Pt
end
