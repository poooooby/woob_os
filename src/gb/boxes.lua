-- The Boxes app's model on the Game Boy games: the party and Bill's PC (Gen 1: 12 boxes, Gen 2: 14, twenty
-- Pokémon each), the same interface as src/boxes.lua so the Boxes window is the same. Their boxes are
-- packed lists, as the games keep them (the game's own PC and the save read them so): a Pokémon taken out
-- closes the gap, one put in an empty cell goes after the last, one dropped on another swaps with it.
-- The games' rules: the party keeps a Pokémon that can battle; a Pokémon holding mail stays out of the
-- boxes (Gen 2); eggs aren't released; Gen 2 heals a Pokémon going into a box (Boxes.enterBox); Yellow's
-- Pikachu minds being put away.
--
--   Bx = boxes(host, Gd, Art, deps)    deps: save (mod.save: the boxes' wallpapers, ours)
--   (the interface: src/boxes.lua's header)

return function(H, Gd, Art, deps)
  local engine = H.engine
  local gen = H.gen
  local Bx = { SLOTS = 20, COLS = 5, ROWS = 4, PARTY = 6 }
  local floor = math.floor
  local function data() return Gd.data() end

  local function Boxes()
    return engine(gen == 2 and "src.core.gen2.Boxes" or "src.pokemon.Boxes")
  end
  local function boxCount()
    local B = Boxes()
    return gen == 2 and (tonumber(B and B.NUM_BOXES) or 14) or (tonumber(B and B.COUNT) or 12)
  end
  Bx.boxCount = boxCount
  setmetatable(Bx, { __index = function(_, k) if k == "BOXES" then return boxCount() end end })

  -- ------- places

  local PARTY_ADDR, BOX_ADDR = {}, {}
  for i = 1, Bx.PARTY do PARTY_ADDR[i] = { loc = "party", slot = i } end
  function Bx.addr(loc, slot, box)
    if loc == "party" then return PARTY_ADDR[slot] end
    local b = tonumber(box)
    if not b or b < 1 or b ~= floor(b) then return nil end
    local row = BOX_ADDR[b]
    if not row then
      row = {}
      for i = 1, Bx.SLOTS do row[i] = { loc = "box", slot = i, boxId = b } end
      BOX_ADDR[b] = row
    end
    return row[slot]
  end

  function Bx.party(s)
    if not s then return {} end
    s.party = s.party or {}
    return s.party
  end
  function Bx.boxMons(s, b)
    if not s then return nil end
    local B = Boxes()
    if gen == 2 then
      local ok, box = pcall(B and B.box or error, s, b)
      return ok and box or nil
    end
    if B and B.ensure then pcall(B.ensure, s) end
    s.boxes = s.boxes or {}
    if b < 1 or b > boxCount() then return nil end
    s.boxes[b] = s.boxes[b] or {}
    return s.boxes[b]
  end
  function Bx.get(s, addr)
    if not addr then return nil end
    if addr.loc == "party" then return Bx.party(s)[addr.slot] end
    local mons = Bx.boxMons(s, addr.boxId)
    return mons and mons[addr.slot]
  end
  function Bx.current(s)
    if gen == 1 then
      local B = Boxes()
      if B and B.ensure then pcall(B.ensure, s) end
    end
    return s and math.max(1, math.min(boxCount(), tonumber(s.currentBox) or 1)) or 1
  end
  function Bx.setCurrent(s, b)
    if not s then return end
    b = (b - 1) % boxCount() + 1
    local B = Boxes()
    if gen == 2 and B and B.setCurrent then
      pcall(B.setCurrent, s, b)
    else
      s.currentBox = b
    end
  end
  function Bx.count(s, b)
    local mons = Bx.boxMons(s, b)
    return mons and #mons or 0
  end
  -- (read each frame: the player's name for it, else the game's default, made once per box)
  local defaults = {}
  function Bx.boxName(s, b)
    local given = gen == 2 and s and s.boxNames and s.boxNames[b]
    if type(given) == "string" and given ~= "" then return given end
    local d = defaults[b]
    if not d then
      d = gen == 2 and ("BOX" .. b) or ("BOX " .. b)
      defaults[b] = d
    end
    return d
  end
  function Bx.rename(s, b, name)
    if gen ~= 2 or type(name) ~= "string" or name == "" then return end
    local B = Boxes()
    if B and B.rename then pcall(B.rename, s, b, name) end
  end
  -- (the boxes' wallpapers are ours: the games have none; read from the mod's save once, kept)
  local wallsKept = nil
  local function walls()
    if wallsKept then return wallsKept end
    wallsKept = {}
    local store = deps and deps.save
    if store then
      local ok, t = pcall(store.get, store, "boxWalls")
      if ok and type(t) == "table" then
        for k, v in pairs(t) do wallsKept[tonumber(k) or k] = v end
      end
    end
    return wallsKept
  end
  function Bx.forgetWalls() wallsKept = nil end
  function Bx.wallpaper(s, b)
    return tonumber(walls()[b]) or ((b - 1) % 4 + 1)
  end
  function Bx.setWallpaper(s, b, id)
    local store = deps and deps.save
    if not store then return end
    local t = walls()
    t[b] = id
    pcall(store.set, store, "boxWalls", t)
  end

  -- ------- the rules

  local function isEgg(mon) return Gd.isEgg(mon) end
  local function usable(mon)
    return type(mon) == "table" and not isEgg(mon) and (tonumber(mon.hp) or 0) > 0
  end
  local function hasMail(mon)
    if gen ~= 2 or type(mon) ~= "table" then return false end
    local M = engine("src.core.gen2.Mail")
    if M and M.monHoldsMail then
      local ok, yes = pcall(M.monHoldsMail, mon)
      if ok then return yes == true end
    end
    return false
  end
  Bx.usable, Bx.hasMail, Bx.isEgg = usable, hasMail, isEgg

  -- (Yellow: the Pikachu that follows the player)
  local function starterPikachu(s, mon)
    local GV = engine("src.core.GameVersion")
    local okY, yellow = pcall(GV and GV.isYellow or error)
    if not (okY and yellow) then return false end
    local PF = engine("src.world.PikachuFollower")
    local ok, yes = pcall(PF and PF.isStarterPikachu or error, s, mon)
    return ok and yes == true
  end

  -- a Pokémon going into a box (Gen 2 heals it and fills its PP; Yellow's Pikachu is unhappy) or out of one
  -- (Gen 1 makes its stats again, a box keeping none)
  local function intoBox(s, mon)
    if gen == 2 then
      local B = Boxes()
      if B and B.enterBox then pcall(B.enterBox, mon, data()) end
    elseif starterPikachu(s, mon) then
      local PF = engine("src.world.PikachuFollower")
      if PF and PF.modifyHappiness then pcall(PF.modifyHappiness, s, "DEPOSITED", mon) end
    end
  end
  local function outOfBox(s, mon)
    if gen == 1 then
      local Stats = engine("src.pokemon.Stats")
      local def = Gd.def(mon.species)
      if Stats and Stats.ensure and def then pcall(Stats.ensure, def, mon) end
    end
  end

  -- ------- taking and placing (the boxes packed, the party packed)

  local function newHeld() return { n = 0, mons = {}, origins = {}, dx = {}, dy = {} } end

  function Bx.take(s, addrs)
    if not s then return nil, "gone" end
    local party = Bx.party(s)
    local leaving, n = {}, 0
    for _, a in ipairs(addrs) do
      if not Bx.get(s, a) then return nil, "gone" end
      if a.loc == "party" then leaving[a.slot] = true end
      n = n + 1
    end
    if n == 0 then return nil, "gone" end
    if next(leaving) then
      local left = false
      for i = 1, #party do
        if not leaving[i] and usable(party[i]) then left = true end
      end
      if not left then return nil, "last_usable" end
    end
    local held = newHeld()
    for i, a in ipairs(addrs) do
      held.n = i
      held.mons[i], held.origins[i] = Bx.get(s, a), a
      held.dx[i], held.dy[i] = 0, i - 1
    end
    -- (out of their lists from the last place first, so the places before stay where they are)
    local order = {}
    for i = 1, held.n do order[i] = i end
    table.sort(order, function(x, y) return held.origins[x].slot > held.origins[y].slot end)
    for _, i in ipairs(order) do
      local a = held.origins[i]
      local list = a.loc == "party" and party or Bx.boxMons(s, a.boxId)
      table.remove(list, a.slot)
    end
    return held
  end

  function Bx.fits(s, held, target)
    if not (held and held.n > 0 and target) then return false, "gone" end
    if target.loc == "box" then
      for i = 1, held.n do
        if hasMail(held.mons[i]) then return false, "mail" end
        if gen == 1 and starterPikachu(s, held.mons[i]) and held.mons[i].status == "SLP" then
          return false, "no_room"
        end
      end
      local mons = Bx.boxMons(s, target.boxId)
      if not mons then return false, "gone" end
      if held.n == 1 and mons[target.slot] then return true end
      if #mons + held.n > Bx.SLOTS then return false, "no_room" end
      return true
    end
    local party = Bx.party(s)
    if held.n == 1 and party[target.slot] then
      local out = party[target.slot]
      if not usable(held.mons[1]) and usable(out) then
        local any = false
        for i = 1, #party do if i ~= target.slot and usable(party[i]) then any = true end end
        if not any then return false, "last_usable" end
      end
      return true
    end
    if #party + held.n > Bx.PARTY then return false, held.n == 1 and "party_full" or "no_room" end
    return true
  end

  function Bx.way(held, target)
    local from = held and held.origins[1] and held.origins[1].loc
    if from == "party" and target.loc == "box" then return "out" end
    if from == "box" and target.loc == "party" then return "in" end
    return nil
  end

  local function arrive(s, mon, loc)
    if loc == "box" then intoBox(s, mon) else outOfBox(s, mon) end
  end

  function Bx.place(s, held, target)
    local ok, why = Bx.fits(s, held, target)
    if not ok then return false, why end
    local list = target.loc == "party" and Bx.party(s) or Bx.boxMons(s, target.boxId)
    if held.n == 1 and list[target.slot] then
      -- (onto another: they swap, the other into the hand)
      local out = list[target.slot]
      list[target.slot] = held.mons[1]
      arrive(s, held.mons[1], target.loc)
      local nh = newHeld()
      nh.n, nh.mons[1], nh.origins[1], nh.dx[1], nh.dy[1] = 1, out, target, 0, 0
      return true, nh
    end
    for i = 1, held.n do
      local at = math.min(target.slot + i - 1, #list + 1)
      table.insert(list, at, held.mons[i])
      arrive(s, held.mons[i], target.loc)
    end
    return true
  end

  -- everything in the hand back where it came from (or the nearest place with room)
  function Bx.putBack(s, held)
    if not (s and held) then return end
    for i = held.n, 1, -1 do
      local mon, o = held.mons[i], held.origins[i]
      if mon and o then
        local list = o.loc == "party" and Bx.party(s) or Bx.boxMons(s, o.boxId)
        local cap = o.loc == "party" and Bx.PARTY or Bx.SLOTS
        if list and #list < cap then
          table.insert(list, math.min(o.slot, #list + 1), mon)
          held.mons[i] = nil
        else
          for b = 1, boxCount() do
            local box = Bx.boxMons(s, b)
            if box and #box < Bx.SLOTS then
              box[#box + 1] = mon
              intoBox(s, mon)
              held.mons[i] = nil
              break
            end
          end
        end
      end
    end
  end

  -- ------- release, items

  function Bx.release(s, addr)
    local mon = Bx.get(s, addr)
    if not mon then return false, "gone" end
    if isEgg(mon) then return false, "egg" end
    if hasMail(mon) then return false, "mail" end
    local party = Bx.party(s)
    if addr.loc == "party" then
      local any = false
      for i = 1, #party do if i ~= addr.slot and usable(party[i]) then any = true end end
      if not any then return false, "last_usable" end
      table.remove(party, addr.slot)
    else
      table.remove(Bx.boxMons(s, addr.boxId), addr.slot)
    end
    return true, mon
  end

  local function Bag() return engine("src.inventory.Bag") end
  function Bx.holdable(s, id)
    if gen ~= 2 or type(id) ~= "string" then return false end
    local M = engine("src.core.gen2.Mail")
    if M and M.isMail then
      local ok, yes = pcall(M.isMail, id)
      if ok and yes then return false end
    end
    local it = Gd.item(id)
    if not it then return false end
    return it.pocket == "ITEM" or it.pocket == "BALL"
  end
  function Bx.takeItem(s, mon)
    if not mon then return false, "gone" end
    local id = mon.item
    if gen ~= 2 or not id or id == "" then return false, "no_item" end
    if hasMail(mon) then return false, "mail" end
    local B = Bag()
    if not (B and B.add(s, id, 1, data())) then return false, "bag_full" end
    mon.item = nil
    Bx.forget(mon)
    return true, id
  end
  function Bx.giveItem(s, mon, id)
    if not mon then return false, "gone" end
    if isEgg(mon) then return false, "egg" end
    if mon.item and mon.item ~= "" then return false, "holding" end
    if not Bx.holdable(s, id) then return false, "cant_hold" end
    local B = Bag()
    if not (B and (tonumber(s.inventory and s.inventory[id]) or 0) > 0) then return false, "gone" end
    B.remove(s, id, 1, data())
    mon.item = id
    Bx.forget(mon)
    return true, id
  end

  -- ------- the preview (made once per Pokémon, kept until it changes)

  local infos = setmetatable({}, { __mode = "k" })
  local shinies = setmetatable({}, { __mode = "k" })
  function Bx.forget(mon) if mon then infos[mon], shinies[mon] = nil, nil end end
  function Bx.info(mon, T)
    if not mon then return nil end
    local got = infos[mon]
    if got then return got end
    got = { mon = mon, moves = {}, types = {} }
    local egg = isEgg(mon)
    got.egg = egg
    got.name = Gd.monName(mon)
    got.species = mon.species
    got.level = Gd.level(mon)
    got.levelText = T and T.f("boxes.level", got.level) or ("Lv. " .. got.level)
    got.hp, got.maxHp = Gd.hp(mon), Gd.maxHp(mon)
    got.pic = Art and Art.pic(mon.species, mon) or nil
    if not egg then
      got.shiny = Gd.shiny(mon)
      got.gender = Gd.gender(mon)
      got.types = Gd.typesOf(mon.species)
      for _, m in ipairs(mon.moves or {}) do
        local id = type(m) == "table" and m.id or m
        if id and id ~= "" and id ~= "NO_MOVE" then got.moves[#got.moves + 1] = Gd.moveName(id) end
      end
    end
    if gen == 2 and mon.item and mon.item ~= "" then
      got.item = mon.item
      got.itemName = Gd.itemName(mon.item)
    end
    infos[mon] = got
    return got
  end
  function Bx.shiny(mon)
    if not mon then return false end
    local got = shinies[mon]
    if got ~= nil then return got end
    got = Gd.shiny(mon)
    shinies[mon] = got
    return got
  end

  -- ------- the summary (the same page as src/boxes.lua's: DVs as the IVs, Stat Exp as the EVs)

  -- (the rows: Gen 1 has one Special, Gen 2 two stats on the one Special DV and Stat Exp)
  local ROWS1 = {
    { key = "dex.stat.hp", stat = "hp" }, { key = "dex.stat.atk", stat = "attack" },
    { key = "dex.stat.def", stat = "defense" }, { key = "sum.stat.spc", stat = "special", dv = "special" },
    { key = "dex.stat.spe", stat = "speed" },
  }
  local ROWS2 = {
    { key = "dex.stat.hp", stat = "hp" }, { key = "dex.stat.atk", stat = "attack" },
    { key = "dex.stat.def", stat = "defense" }, { key = "dex.stat.spa", stat = "specialAttack", dv = "special" },
    { key = "dex.stat.spd", stat = "specialDefense", dv = "special" }, { key = "dex.stat.spe", stat = "speed" },
  }
  -- (the radar: HP at the top, then clockwise Attack, Defense, Speed, Special)
  local RADAR = { "hp", "attack", "defense", "speed", "special" }
  local RADAR_KEYS = { "auction.ivHp", "auction.ivAtk", "auction.ivDef", "auction.ivSpe", "sum.stat.spc" }
  local sums = setmetatable({}, { __mode = "k" })
  local forget0 = Bx.forget
  function Bx.forget(mon)
    forget0(mon)
    if mon then sums[mon] = nil end
  end
  local function word(T, key, ...)
    if not T then return key end
    if select("#", ...) > 0 then return T.f(key, ...) end
    return T(key)
  end
  local function hpDv(dvs)
    local function low(v) return (tonumber(v) or 0) % 2 end
    return low(dvs.attack) * 8 + low(dvs.defense) * 4 + low(dvs.speed) * 2 + low(dvs.special)
  end
  local function expAt(def, level)
    local d = data()
    if gen == 2 then
      local Mon = engine("src.battle.gen2.Mon")
      local ok, v = pcall(function() return Mon.experienceForLevel(Mon.growthFor(d, def.growthRate), level) end)
      return ok and tonumber(v) or nil
    end
    local Growth = engine("src.pokemon.Growth")
    local ok, v = pcall(Growth and Growth.expForLevel or error, def.growthRate, level, d and d.growth_rates)
    return ok and tonumber(v) or nil
  end

  function Bx.summary(s, mon, T)
    if not mon then return nil end
    local got = sums[mon]
    if got then return got end
    local info = Bx.info(mon, T)
    local sp = mon.species
    got = { mon = mon, egg = info.egg, sp = sp, name = info.name, level = info.level, levelText = info.levelText,
            gender = info.gender, shiny = info.shiny, types = info.types, info = {}, rows = {}, radar = {},
            radarKeys = RADAR_KEYS, moves = {}, ivMax = 15, evMax = 65535, hp = info.hp, maxHp = info.maxHp,
            itemId = info.item, itemName = info.itemName, markings = 0 }
    got.speciesName = Gd.speciesName(sp)
    local nat = tonumber(Gd.dex(sp)) or 0
    got.dexText = nat > 0 and ("No. %03d"):format(nat) or "No. ---"
    local rows = got.info
    local function row(label, value, tint) rows[#rows + 1] = { label = label, value = tostring(value or ""), tint = tint } end
    local ot = tostring(mon.ot or mon.otName or "")
    local idText = ("%05d"):format((tonumber(mon.otId or mon.id) or 0) % 65536)
    if got.egg then
      got.name = word(T, "sum.egg")
      local c = tonumber(mon.eggCycles or mon.happiness) or 20
      got.eggText = word(T, c <= 5 and "sum.egg.soon" or (c <= 10 and "sum.egg.close" or "sum.egg.time"))
      row(word(T, "sum.ot"), ot, "male")
      row(word(T, "sum.id"), idText)
      sums[mon] = got
      return got
    end
    row(word(T, "sum.species"), got.dexText .. "  " .. got.speciesName)
    row(word(T, "sum.ot"), ot, mon.otGender == "female" and "female" or "male")
    row(word(T, "sum.id"), idText)
    if gen == 2 then row(word(T, "sum.item"), info.itemName or word(T, "boxes.noItem")) end
    -- (Crystal keeps where and at what level it was caught)
    local lv = tonumber(mon.caughtLevel)
    if lv and lv > 0 then
      got.memo = word(T, "sum.met", lv)
      row(word(T, "sum.origin"), got.memo)
    end
    if gen == 2 and (tonumber(mon.pokerus) or 0) ~= 0 then
      row(word(T, "sum.pokerus"), word(T, (tonumber(mon.pokerus) or 0) % 16 ~= 0 and "sum.pokerus.now" or "sum.pokerus.cured"))
    end
    if gen == 2 then got.friendship = tonumber(mon.happiness or mon.friendship) end
    if (tonumber(mon.hp) or 1) <= 0 then got.status = word(T, "sum.status.fnt") end
    -- (the stats, the DVs and Stat Exp)
    local stats = type(mon.stats) == "table" and mon.stats or {}
    local dvs = type(mon.dvs) == "table" and mon.dvs or {}
    local se = type(mon.statExp) == "table" and mon.statExp or {}
    for i, r in ipairs(gen == 2 and ROWS2 or ROWS1) do
      local v = r.stat == "hp" and info.maxHp or tonumber(stats[r.stat] or (r.dv and stats.special)) or 0
      local dv = r.stat == "hp" and hpDv(dvs) or tonumber(dvs[r.dv or r.stat]) or 0
      local ev = floor(tonumber(se[r.dv or r.stat]) or 0)
      got.rows[i] = { key = r.key, value = v, iv = dv, ev = ev }
    end
    local total = 0
    for i, k in ipairs(RADAR) do
      got.radar[i] = floor(tonumber(se[k]) or 0)
      total = total + got.radar[i]
    end
    got.evTotal = total
    -- (EXP: its total, how far to the next level)
    local def = Gd.def(sp)
    local exp = tonumber(mon.experience or mon.exp)
    if def and exp then
      local lvl = info.level
      local here, nxt = expAt(def, lvl), lvl < 100 and expAt(def, lvl + 1) or nil
      got.exp = exp
      got.expNext = nxt and math.max(0, nxt - exp) or 0
      got.expPct = (here and nxt and nxt > here) and math.max(0, math.min(1, (exp - here) / (nxt - here))) or 1
    end
    -- (the moves)
    local d = data()
    for slot, e in ipairs(mon.moves or {}) do
      local id = type(e) == "table" and e.id or e
      if id and id ~= "" and id ~= "NO_MOVE" then
        local m = d and d.moves and d.moves[id] or {}
        local base = tonumber(m.pp) or 0
        local ups = tonumber(type(e) == "table" and e.ppUps) or 0
        local maxPp = tonumber(type(e) == "table" and e.maxPp) or (base + ups * floor(base / 5))
        local pp = tonumber(type(e) == "table" and e.pp) or maxPp
        local t = m.type or "NORMAL"
        local power, acc = tonumber(m.power) or 0, tonumber(m.accuracy) or 0
        local desc = type(m.description) == "string" and m.description:gsub("<NEXT>", " "):gsub("%s+", " ") or ""
        got.moves[#got.moves + 1] = {
          id = id, slot = slot, name = Gd.moveName(id), typeId = Gd.typeId(t), typeName = Gd.typeName(t),
          pp = pp, maxPp = maxPp, ppText = ("%d/%d"):format(pp, maxPp),
          powerText = power > 1 and tostring(power) or "—", accText = acc > 0 and (tostring(floor(acc)) .. "%") or "—",
          physical = Gd.typeId(t) < 9, status = power == 0, desc = desc,
        }
      end
    end
    sums[mon] = got
    return got
  end

  -- two of a Pokémon's moves trade places (their PP and PP Ups with them)
  function Bx.swapMoves(mon, a, b)
    local mv = mon and mon.moves
    if type(mv) ~= "table" or not (mv[a] and mv[b]) then return false end
    mv[a], mv[b] = mv[b], mv[a]
    Bx.forget(mon)
    return true
  end

  -- ------- the game's own bits

  -- (caught Pokémon go to the current box on both games: nothing to tell them)
  function Bx.sendBox() end
  function Bx.openNaming(s, b, onDone)
    if gen ~= 2 then error("the game's boxes have no names") end
    local game = H.game()
    local Screens = engine("src.ui.Screens")
    if not (game and Screens) then error("the game has no naming screen") end
    local function back(name)
      if game.stack and game.stack:top() then game.stack:pop() end
      onDone(name)
    end
    Screens.push(game, "Gen2NamingScreen", { type = "box", initial = Bx.boxName(s, b),
                                              onDone = function(name) back(name) end,
                                              onCancel = function() back(nil) end })
  end

  return Bx
end
