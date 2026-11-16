-- The Pokémon model behind the Boxes app: the party and the PC's boxes (14, or as many as the engine
-- has: WoobleDex's Bigger PC makes them 40), through the engine's own
-- Storage (src.core.game3.storage), so the session changes as the game's own storage screens change
-- it (a Pokémon going into a box is healed, the party stays packed, the quest log hears of it).
-- The game's rules hold on all five games: the party keeps a Pokémon that can battle, a Pokémon
-- holding mail stays out of the boxes, eggs and mail holders aren't released.
--
--   Bx = boxes(engine)        engine(name) -> an engine module or nil (kept by the caller)
--   Bx.BOXES (read live: the engine's Storage.TOTAL_BOXES_COUNT), Bx.SLOTS, Bx.COLS, Bx.ROWS, Bx.PARTY
--   Bx.addr(loc, slot, box) -> the one address table for that place ({ loc, slot, boxId })
--   Bx.get(s, addr) -> mon | nil ; Bx.party(s) ; Bx.boxMons(s, b) ; Bx.current(s) / Bx.setCurrent(s, b)
--   Bx.count(s, b) ; Bx.boxName(s, b) ; Bx.rename(s, b, name) ; Bx.wallpaper(s, b) / Bx.setWallpaper(s, b, id)
--   Bx.take(s, addrs) -> held | nil, reason      held = { n, mons, origins, dx, dy } (a box group keeps
--       its shape: dx / dy from its top left cell; a party group its order)
--   Bx.fits(s, held, target) -> true | false, reason   (target: an address; a box group anchors there)
--   Bx.place(s, held, target) -> true, displacedHeld | false, reason   (one Pokémon swaps with whoever
--       is there: they come back as the new held)
--   Bx.putBack(s, held) ; Bx.release(s, addr) -> true, mon | false, reason
--   Bx.takeItem(s, mon) / Bx.giveItem(s, mon, itemId) -> true, itemId | false, reason
--   Bx.holdable(s, itemId) -> bool ; Bx.info(mon) -> the preview's words and pictures (kept per Pokémon
--       until Bx.forget(mon)) ; Bx.shiny(mon) -> bool (kept per Pokémon: the grid's sparkle, every frame)
--   Bx.dynamax = fn() -> WoobleDex's exports.dynamax | nil (main.lua): the preview's Dynamax Level
--       (info.dmax 0..10, nil when it can't Dynamax) and Gigantamax Factor (info.gmax)
--   Bx.galar = fn() -> true while Galar Rising (max_raids) is on (main.lua): the summary's Dynamax row
--   Bx.summary(s, mon, T) -> the summary's page (kept per Pokémon until Bx.forget) ; Bx.swapMoves(mon, a, b)
--   Bx.sendBox(s) the box caught Pokémon go to = the current one (as the game's own screen does on close)
--   Bx.openNaming(s, b, onDone)
--   reasons: "last_usable" | "mail" | "party_full" | "no_room" | "egg" | "gone" | "bag_full" | "holding" |
--       "cant_hold" | "no_item" | "needed" ; the words are lang/*.lua's "reason.box.<reason>"

return function(engine)
  local Bx = { SLOTS = 30, COLS = 6, ROWS = 5, PARTY = 6 }
  local floor, max = math.floor, math.max

  local function Storage() return engine("src.core.game3.storage") end
  local function Pokemon() return engine("src.core.game3.pokemon") end
  local function Mail() return engine("src.core.game3.mail") end

  -- how many boxes the PC has: the engine's own count, which another mod may raise (WoobleDex's
  -- Bigger PC: 40), read each time
  local function boxCount()
    local St = Storage()
    local n = St and tonumber(St.TOTAL_BOXES_COUNT)
    return n and n >= 1 and floor(n) or 14
  end
  Bx.boxCount = boxCount
  setmetatable(Bx, { __index = function(_, k) if k == "BOXES" then return boxCount() end end })

  -- ------- places

  -- (each place's address made once, a box's the first time it's asked for)
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

  local function storage(s)
    local St = Storage()
    if not (s and St) then return nil end
    local ok, got = pcall(St.ensure, s)
    return ok and got or nil
  end
  function Bx.party(s)
    if not s then return {} end
    s.party = s.party or {}
    return s.party
  end
  function Bx.boxMons(s, b)
    local st = storage(s)
    local box = st and st.boxes[b]
    return box and box.mons
  end
  function Bx.get(s, addr)
    if not addr then return nil end
    if addr.loc == "party" then return Bx.party(s)[addr.slot] end
    local mons = Bx.boxMons(s, addr.boxId)
    return mons and mons[addr.slot]
  end
  function Bx.current(s)
    local st = storage(s)
    return st and math.max(1, math.min(Bx.BOXES, tonumber(st.currentBox) or 1)) or 1
  end
  function Bx.setCurrent(s, b)
    local st = storage(s)
    if st then st.currentBox = (b - 1) % Bx.BOXES + 1 end
  end
  function Bx.count(s, b)
    local mons, n = Bx.boxMons(s, b), 0
    if mons then for i = 1, Bx.SLOTS do if mons[i] then n = n + 1 end end end
    return n
  end
  function Bx.boxName(s, b)
    local st = storage(s)
    local box = st and st.boxes[b]
    return box and tostring(box.name or ("BOX " .. b)) or ("BOX " .. b)
  end
  function Bx.rename(s, b, name)
    local st = storage(s)
    local box = st and st.boxes[b]
    if box and type(name) == "string" and name ~= "" then box.name = name end
  end
  function Bx.wallpaper(s, b)
    local st = storage(s)
    local box = st and st.boxes[b]
    return box and tonumber(box.wallpaper) or ((b - 1) % 4 + 1)
  end
  function Bx.setWallpaper(s, b, id)
    local st = storage(s)
    local box = st and st.boxes[b]
    if box then box.wallpaper = id end
  end

  -- ------- the rules

  local function isEgg(mon)
    local P = Pokemon()
    if P and P.isEgg then
      local ok, yes = pcall(P.isEgg, mon)
      if ok then return yes == true end
    end
    return mon.isEgg == true or mon.egg == true
  end
  local function speciesOf(mon)
    return tonumber(mon.species or mon.speciesId) or 0
  end
  -- (a Pokémon that can battle)
  local function usable(mon)
    return type(mon) == "table" and speciesOf(mon) ~= 0 and not isEgg(mon) and (tonumber(mon.hp) or 0) > 0
  end
  local function hasMail(mon)
    local M = Mail()
    local id = mon and (mon.heldItem or mon.item)
    if not (M and M.isMailItem and id) then return false end
    local ok, yes = pcall(M.isMailItem, id)
    return ok and yes == true
  end
  Bx.usable, Bx.hasMail, Bx.isEgg = usable, hasMail, isEgg

  -- ------- taking and placing

  local function newHeld() return { n = 0, mons = {}, origins = {}, dx = {}, dy = {} } end

  -- take the Pokémon at these places into the hand (all or none)
  function Bx.take(s, addrs)
    if not (s and storage(s)) then return nil, "gone" end
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
    -- the shape: a box group from its top left cell
    local minC, minR = math.huge, math.huge
    for _, a in ipairs(addrs) do
      if a.loc == "box" then
        minC = math.min(minC, (a.slot - 1) % Bx.COLS)
        minR = math.min(minR, floor((a.slot - 1) / Bx.COLS))
      end
    end
    local held = newHeld()
    for i, a in ipairs(addrs) do
      local mon = Bx.get(s, a)
      held.n = i
      held.mons[i], held.origins[i] = mon, a
      if a.loc == "box" then
        held.dx[i], held.dy[i] = (a.slot - 1) % Bx.COLS - minC, floor((a.slot - 1) / Bx.COLS) - minR
        Bx.boxMons(s, a.boxId)[a.slot] = nil
      else
        held.dx[i], held.dy[i] = 0, i - 1
        party[a.slot] = nil
      end
    end
    if next(leaving) then Storage().compactParty(party) end
    return held
  end

  -- where a box group lands with its top left at `target` -> the slot of each, or nil
  local function cellFor(held, i, target)
    local c = (target.slot - 1) % Bx.COLS + held.dx[i]
    local r = floor((target.slot - 1) / Bx.COLS) + held.dy[i]
    if c >= Bx.COLS or r >= Bx.ROWS then return nil end
    return r * Bx.COLS + c + 1
  end
  local function shapeOf(held)
    -- (a party group lands in a box as a row: its order across)
    for i = 1, held.n do
      if held.origins[i].loc ~= "box" then return false end
    end
    return true
  end

  function Bx.fits(s, held, target)
    if not (held and held.n > 0 and target) then return false, "gone" end
    if target.loc == "box" then
      for i = 1, held.n do
        if hasMail(held.mons[i]) then return false, "mail" end
      end
      local mons = Bx.boxMons(s, target.boxId)
      if not mons then return false, "gone" end
      -- (one Pokémon swaps with whoever is there: they go to the hand, not the party)
      if held.n == 1 then return true end
      local boxShape = shapeOf(held)
      for i = 1, held.n do
        local slot
        if boxShape then slot = cellFor(held, i, target) else slot = target.slot + i - 1 end
        if not slot or slot > Bx.SLOTS or mons[slot] then return false, "no_room" end
      end
      return true
    end
    -- the party: one swaps with whoever is there; more go on the end
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

  -- the pad's way for a held Pokémon going to `loc`: "out" into the PC, "in" out of it, nil within
  function Bx.way(held, target)
    local from = held and held.origins[1] and held.origins[1].loc
    if from == "party" and target.loc == "box" then return "out" end
    if from == "box" and target.loc == "party" then return "in" end
    return nil
  end

  function Bx.place(s, held, target)
    local ok, why = Bx.fits(s, held, target)
    if not ok then return false, why end
    local St = Storage()
    if held.n == 1 then
      local mon, origin = held.mons[1], held.origins[1]
      local slot = target.slot
      if target.loc == "party" and not Bx.party(s)[slot] then slot = #Bx.party(s) + 1 end
      local done, out = St.placeHeldMon(s, mon, target.loc, slot, target.boxId, origin)
      if not done then return false, "no_room" end
      if out then
        local next = newHeld()
        next.n, next.mons[1], next.origins[1], next.dx[1], next.dy[1] = 1, out, target, 0, 0
        return true, next
      end
      return true
    end
    local boxShape = shapeOf(held)
    for i = 1, held.n do
      local slot
      if target.loc == "box" then
        slot = boxShape and cellFor(held, i, target) or (target.slot + i - 1)
      else
        slot = #Bx.party(s) + 1
      end
      St.placeHeldMon(s, held.mons[i], target.loc, slot, target.boxId, held.origins[i])
    end
    return true
  end

  -- everything in the hand back where it came from (or the nearest free place)
  function Bx.putBack(s, held)
    if not (s and held) then return end
    local St = Storage()
    for i = held.n, 1, -1 do
      local mon = held.mons[i]
      if mon then
        local ok, done = pcall(St.restoreHeldMon, s, mon, held.origins[i])
        if ok and done then held.mons[i] = nil end
      end
    end
  end

  -- ------- release, items

  local function needed(s, mon, addr)
    -- (Ruby / Sapphire: the last Pokémon knowing Surf or Dive comes back)
    local Profile = engine("src.core.game3.profile")
    local ok, row = pcall(function() return Profile.forSession(s) end)
    if not (ok and row and (row.id == "ruby" or row.id == "sapphire")) then return false end
    local Policy = engine("src.ui.game3.rs.storage_policy")
    if not (Policy and Policy.releaseReturns) then return false end
    local ok2, yes = pcall(Policy.releaseReturns, s, mon, addr.loc, addr.boxId, addr.slot)
    return ok2 and yes == true
  end

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
    end
    if needed(s, mon, addr) then return false, "needed" end
    if addr.loc == "party" then
      party[addr.slot] = nil
      Storage().compactParty(party)
    else
      Storage().releaseMon(s, addr.boxId, addr.slot)
    end
    return true, mon
  end

  local function itemsData() return engine("src.core.game3.items_data") end
  function Bx.holdable(s, id)
    id = tonumber(id)
    if not id or id == 0 or hasMail({ heldItem = id }) then return false end
    local I = itemsData()
    local ok, info = pcall(I and I.info or error, id)
    if not (ok and info) then return false end
    if (tonumber(info.importance) or 0) ~= 0 then return false end
    local pocket = tostring(info.pocket or "")
    return not (pocket:find("KEY") or pocket:find("TM"))
  end

  function Bx.takeItem(s, mon)
    if not mon then return false, "gone" end
    local id = mon.heldItem or mon.item
    if not id or id == 0 then return false, "no_item" end
    if hasMail(mon) then return false, "mail" end
    local ok, done = pcall(Storage().detachHeldItem, s, mon)
    if not (ok and done) then return false, "bag_full" end
    Bx.forget(mon)
    return true, id
  end

  function Bx.giveItem(s, mon, id)
    if not mon then return false, "gone" end
    if isEgg(mon) then return false, "egg" end
    local have = mon.heldItem or mon.item
    if have and have ~= 0 then return false, "holding" end
    if not Bx.holdable(s, id) then return false, "cant_hold" end
    local Bag = engine("src.core.game3.bag")
    if not (Bag and s.bag and (Bag.get(s.bag, id) or 0) > 0) then return false, "gone" end
    if not Bag.remove(s.bag, id, 1) then return false, "gone" end
    mon.heldItem, mon.item = id, id
    Bx.forget(mon)
    return true, id
  end

  -- ------- the preview (made once per Pokémon, kept until it changes)

  local infos = setmetatable({}, { __mode = "k" })
  local shinies = setmetatable({}, { __mode = "k" })
  function Bx.forget(mon) if mon then infos[mon], shinies[mon] = nil, nil end end
  local function call(f, ...)
    if not f then return nil end
    local ok, a, b = pcall(f, ...)
    if ok then return a, b end
    return nil
  end
  function Bx.info(mon, T)
    if not mon then return nil end
    local got = infos[mon]
    if got then return got end
    local P = Pokemon()
    got = { mon = mon, moves = {}, types = {} }
    local egg = isEgg(mon)
    got.egg = egg
    got.name = tostring(call(P and P.displayMonName, mon) or mon.nickname or mon.name or "?")
    got.species = speciesOf(mon)
    got.level = tonumber(mon.level) or 1
    got.levelText = T and T.f("boxes.level", got.level) or ("Lv. " .. got.level)
    got.hp, got.maxHp = tonumber(mon.hp) or 0, tonumber(mon.maxHp) or 0
    got.pic = call(P and P.monFrontPic, mon, nil, "box")
    got.icon = call(P and P.monIcon, mon)
    if not egg then
      got.shiny = call(P and P.isShiny, mon) == true
      local SD = engine("src.core.game3.summary_data")
      local g = call(SD and SD.gender, mon)
      got.gender = (g == "M" or g == "F") and g or nil
      local _, nature = call(SD and SD.nature, mon)
      got.nature = nature and tostring(nature) or nil
      local types = call(P and P.types, got.species)
      local Types = engine("src.core.game3.battle.types")
      if type(types) == "table" then
        for i = 1, 2 do
          local t = tonumber(types[i])
          if t and (i == 1 or t ~= tonumber(types[1])) then
            got.types[#got.types + 1] = { id = t, name = tostring(call(Types and Types.name, t) or "") }
          end
        end
      end
      local ability = tonumber(mon.ability or mon.abilityId)
      if not ability then ability = call(P and P.abilityId, got.species, mon.personality) end
      got.ability = ability and call(P and P.abilityName, ability) or nil
      if got.ability then got.ability = tostring(got.ability) end
      -- (Dynamax: WoobleDex's, kept on the Pokémon; Max Raids' dens hand out the levels and factors)
      local Dx = Bx.dynamax and call(Bx.dynamax)
      if type(Dx) == "table" and call(Dx.canDynamax, mon) == true then
        got.dmax = tonumber(call(Dx.level, mon)) or 0
        got.gmax = call(Dx.canGigantamax, mon) == true
      end
      for slot = 1, 4 do
        local id = call(P and P.moveIdAt, mon, slot)
        id = tonumber(id)
        if id and id ~= 0 then got.moves[#got.moves + 1] = tostring(call(P and P.moveName, id) or "?") end
      end
    end
    local item = tonumber(mon.heldItem or mon.item)
    if item and item ~= 0 then
      local I = itemsData()
      got.item = item
      got.itemName = tostring(call(I and I.displayName, item) or ("#" .. item))
    end
    infos[mon] = got
    return got
  end

  -- a shiny? (just that, without the preview's pictures: the game's check, or a mod's shiny.roll,
  -- makes garbage, so once per Pokémon; an egg never)
  function Bx.shiny(mon)
    if not mon then return false end
    local got = shinies[mon]
    if got ~= nil then return got end
    local P = Pokemon()
    got = not isEgg(mon) and call(P and P.isShiny, mon) == true
    shinies[mon] = got
    return got
  end

  -- ------- the summary (made when it's opened, kept per Pokémon until it changes)

  -- (each stat's row: the words' key, the IV / EV key, its value on the Pokémon, its key in the
  -- natures' table; the order HP, Attack, Defense, Sp. Atk, Sp. Def, Speed)
  local STAT_ROWS = {
    { key = "dex.stat.hp", iv = "hp", val = "maxHp" }, { key = "dex.stat.atk", iv = "atk", val = "attack", nat = "atk" },
    { key = "dex.stat.def", iv = "def", val = "defense", nat = "def" },
    { key = "dex.stat.spa", iv = "spa", val = "spAtk", nat = "spAtk" },
    { key = "dex.stat.spd", iv = "spd", val = "spDef", nat = "spDef" },
    { key = "dex.stat.spe", iv = "spe", val = "speed", nat = "spd" },
  }
  -- (the radar's corners: HP at the top, then clockwise Attack, Defense, Speed, Sp. Def, Sp. Atk)
  local RADAR_ORDER = { 1, 2, 3, 6, 5, 4 }
  -- (its labels short: it sits beside the table in a narrow card)
  local RADAR_KEYS = { "auction.ivHp", "auction.ivAtk", "auction.ivDef", "auction.ivSpe", "auction.ivSpd", "auction.ivSpa" }
  local STATUS = { [1] = "sum.status.psn", [2] = "sum.status.par", [3] = "sum.status.slp", [4] = "sum.status.frz",
                   [5] = "sum.status.brn", [7] = "sum.status.fnt" }
  local CONTEST = { [0] = "sum.contest.cool", "sum.contest.beauty", "sum.contest.cute", "sum.contest.smart",
                    "sum.contest.tough" }
  local sums = setmetatable({}, { __mode = "k" })
  local forget0 = Bx.forget
  function Bx.forget(mon)
    forget0(mon)
    if mon then sums[mon] = nil end
  end
  -- (a name the game keeps in capitals, as the Pokédex writes it: "Route 101", "Bold")
  local function titled(s)
    s = tostring(s or "")
    if s:find("%l") then return s end
    return (s:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
  end
  Bx.titled = titled
  local function word(T, key, ...)
    if not T then return key end
    if select("#", ...) > 0 then return T.f(key, ...) end
    return T(key)
  end
  -- a map section's name (where a Pokémon was met), the game's own
  local function placeName(sec)
    sec = tonumber(sec)
    if not sec then return nil end
    local MS = engine("src.import.gba.map_sections_extract")
    local ok, info = pcall(MS and MS.getInfo or error, sec, nil, 0)
    if ok and type(info) == "table" and info.resolved then
      local n = info.rawName or info.name
      if type(n) == "string" and n ~= "" then return titled(n) end
    end
    return nil
  end
  local contestData
  local function contestOf(id)
    if contestData == nil then
      contestData = false
      local GV = engine("src.core.GameVersion")
      local okV, v = pcall(GV and GV.get or error)
      if okV and (v == "ruby" or v == "sapphire" or v == "emerald") then
        -- (the game's own contest data: each move's category and effect, each effect's appeal and jam)
        local Contest = engine("src.core.game3.rse.contest")
        local ok, c = pcall(Contest and Contest.data or error)
        contestData = ok and type(c) == "table" and type(c.moves) == "table" and c or false
      end
    end
    local c = contestData and contestData.moves[id]
    if not c then return nil end
    local e = contestData.effects and contestData.effects[c.effect]
    local SD = engine("src.core.game3.summary_data")
    local desc = e and call(SD and SD.contestEffectDescription, e) or ""
    return { category = tonumber(c.category) or 0,
             appeal = e and e.appeal ~= 0xFF and floor((tonumber(e.appeal) or 0) / 10) or 0,
             jam = e and e.jam ~= 0xFF and floor((tonumber(e.jam) or 0) / 10) or 0,
             desc = tostring(desc or "") }
  end
  -- the egg's words: how soon it hatches (by its cycles left)
  local function eggWords(T, mon)
    local SD = engine("src.core.game3.summary_data")
    local c = tonumber(call(SD and SD.eggCycles, mon)) or tonumber(mon.friendship) or 40
    if c <= 5 then return word(T, "sum.egg.soon") end
    if c <= 10 then return word(T, "sum.egg.close") end
    if c <= 40 then return word(T, "sum.egg.time") end
    return word(T, "sum.egg.long")
  end

  -- one Pokémon's summary -> the page (words made here, never while it draws):
  --   { mon, egg, sp, name, speciesName, dexText, level, levelText, gender ("M" | "F" | nil), shiny, types,
  --     info = { { label, value, tint ("male" | "female" | nil) } }, abilityName, abilityDesc, memo, eggText,
  --     hp, maxHp, status (a word | nil), exp, expNext, expPct, itemId, itemName, ballId, ballName,
  --     markings, rows = { { key, value, iv, ev, nature (1 | -1 | nil) } }, ivMax, evMax, evTotal, evTotalMax,
  --     radar = { 6 values in the rows' order }, friendship, moves = { { id, name, typeId, typeName, pp,
  --     maxPp, powerText, accText, physical, status, desc, contest = { category, appeal, jam, desc } } },
  --     dmax (0..10 | nil), gmax }
  function Bx.summary(s, mon, T)
    if not mon then return nil end
    local got = sums[mon]
    if got then return got end
    local P = Pokemon()
    local SD = engine("src.core.game3.summary_data")
    local Types = engine("src.core.game3.battle.types")
    local info = Bx.info(mon, T)
    local sp = info.species
    got = { mon = mon, egg = info.egg, sp = sp, name = info.name, level = info.level, levelText = info.levelText,
            gender = info.gender, shiny = info.shiny, types = info.types, info = {}, rows = {}, radar = {},
            moves = {}, ivMax = 31, evMax = 252, evTotalMax = tonumber(P and P.MAX_TOTAL_EVS) or 510,
            hp = info.hp, maxHp = info.maxHp, itemId = info.item, itemName = info.itemName,
            markings = tonumber(mon.markings) or 0 }
    local spName = call(P and P.name, sp)
    got.speciesName = titled(spName or info.name)
    -- (not nicknamed: the species' name, as the Pokédex writes it)
    if spName and tostring(spName) == info.name then got.name = got.speciesName end
    local nat = tonumber(call(P and P.national, sp)) or 0
    got.dexText = nat > 0 and ("No. %03d"):format(nat) or "No. ---"
    local rows = got.info
    local function row(label, value, tint) rows[#rows + 1] = { label = label, value = tostring(value or ""), tint = tint } end
    -- (the OT: the trainer who caught it, in blue or red as the game writes it)
    local ot = tostring(mon.otName or mon.ot or mon.originalTrainer or "")
    local otFemale = (tonumber(mon.otGender) or 0) ~= 0
    if got.egg then
      got.eggText = eggWords(T, mon)
      got.name = word(T, "sum.egg")
      row(word(T, "sum.ot"), ot, otFemale and "female" or "male")
      row(word(T, "sum.id"), ("%05d"):format((tonumber(mon.otId) or 0) % 65536))
      sums[mon] = got
      return got
    end
    row(word(T, "sum.species"), got.dexText .. "  " .. got.speciesName)
    row(word(T, "sum.ot"), ot, otFemale and "female" or "male")
    row(word(T, "sum.id"), ("%05d"):format((tonumber(mon.otId) or 0) % 65536))
    -- (the nature, and the stats it raises and lowers)
    local natureId, natureName = call(SD and SD.nature, mon)
    local up, down
    for i, r in ipairs(STAT_ROWS) do
      if r.nat then
        local k = tonumber(call(SD and SD.natureStatModifier, natureId, r.nat)) or 1
        if k > 1 then up = i elseif k < 1 then down = i end
      end
    end
    local nWord = titled(natureName or info.nature or "")
    if up and down then
      nWord = nWord .. "  (+" .. word(T, STAT_ROWS[up].key) .. "  −" .. word(T, STAT_ROWS[down].key) .. ")"
    end
    row(word(T, "sum.nature"), nWord)
    -- (the ability and what it does)
    local ability = tonumber(mon.ability or mon.abilityId)
    if not ability then ability = tonumber(call(P and P.abilityId, sp, mon.personality)) end
    got.abilityName = titled(info.ability or "")
    got.abilityDesc = ability and tostring(call(SD and SD.abilityDescription, ability, got.abilityName) or "") or ""
    row(word(T, "sum.item"), info.itemName or word(T, "boxes.noItem"))
    local ball = tonumber(mon.pokeball or mon.ball)
    if ball and ball > 0 then
      local I = itemsData()
      got.ballId = ball
      got.ballName = titled(call(I and I.displayName, ball) or "")
      row(word(T, "sum.ball"), got.ballName)
    end
    -- (where it came from: met at a level somewhere, hatched, or in a trade)
    local metLevel = tonumber(mon.metLevel)
    local where = mon.metLocationName or placeName(mon.metLocation)
    local traded = call(P and P.isTradedMon, mon, s) == true
    if (tonumber(mon.metLocation) or 0) == 0xFF then got.memo = word(T, "sum.fateful")
    elseif traded and not where then got.memo = word(T, "sum.trade")
    elseif metLevel == 0 then got.memo = where and word(T, "sum.hatchedAt", where) or word(T, "sum.hatched")
    else
      local lv = metLevel or 5
      got.memo = where and word(T, "sum.metAt", lv, where) or word(T, "sum.met", lv)
    end
    if traded and where then got.memo = got.memo .. " " .. word(T, "sum.traded") end
    row(word(T, "sum.origin"), got.memo)
    -- (Pokérus: infected now, or had it and cured: the game's own two marks)
    if call(P and P.hasPokerus, mon) then row(word(T, "sum.pokerus"), word(T, "sum.pokerus.now"))
    elseif call(P and P.hasHadPokerus, mon) then row(word(T, "sum.pokerus"), word(T, "sum.pokerus.cured")) end
    local R = engine("src.core.game3.rse.ribbons")
    local nRib = tonumber(call(R and R.count, mon)) or 0
    if nRib > 0 then row(word(T, "sum.ribbons"), nRib) end
    got.friendship = tonumber(call(P and P.friendshipOf, mon))
    local st = call(SD and SD.statusAilment, mon)
    got.status = STATUS[tonumber(st) or 0] and word(T, STATUS[st]) or nil
    -- (the stats: value, IV, EV, the nature's mark; the EVs read without touching the Pokémon)
    local ivs = type(mon.ivs) == "table" and mon.ivs or {}
    local evs = type(mon.evs) == "table" and mon.evs or {}
    local stats = type(mon.stats) == "table" and mon.stats or {}
    local total = 0
    for i, r in ipairs(STAT_ROWS) do
      local v = tonumber(mon[r.val] or stats[r.val] or stats[r.iv] or mon[r.iv]) or 0
      if i == 1 then v = info.maxHp end
      local ev = floor(max(0, tonumber(evs[r.iv]) or 0))
      total = total + ev
      got.rows[i] = { key = r.key, value = v, iv = floor(tonumber(ivs[r.iv]) or 0), ev = ev,
                      nature = (i == up and 1) or (i == down and -1) or nil }
    end
    for j, i in ipairs(RADAR_ORDER) do got.radar[j] = got.rows[i].ev end
    got.radarKeys = RADAR_KEYS
    got.evTotal = total
    -- (EXP: the total, how far to the next level)
    local prog = call(SD and SD.expProgress, mon, call(P and P.growthRate, sp))
    if type(prog) == "table" then
      got.exp, got.expNext, got.expPct = prog.totalExp, prog.level < 100 and prog.expNeeded or 0, prog.progressPercent
    end
    -- (the moves: PP left of its most, power, accuracy, what it does; Ruby / Sapphire / Emerald's contest side)
    for slot = 1, 4 do
      local id = tonumber(call(P and P.moveIdAt, mon, slot))
      if id and id ~= 0 then
        local m = call(P and P.battleMove, id)
        m = type(m) == "table" and m or {}
        local entry = mon.moves[slot]
        local maxPp = tonumber(type(entry) == "table" and entry.maxPp) or tonumber(mon.maxPp and mon.maxPp[slot])
          or tonumber(m.pp) or 5
        local pp = tonumber(type(entry) == "table" and entry.pp) or tonumber(mon.pp and mon.pp[slot]) or maxPp
        local t = tonumber(m.type) or 0
        local power, acc = tonumber(m.power) or 0, tonumber(m.accuracy) or 0
        local name = tostring(call(P and P.moveName, id) or ("#" .. id))
        got.moves[#got.moves + 1] = {
          id = id, slot = slot, name = titled(name), typeId = t,
          typeName = tostring(call(Types and Types.name, t) or ""), pp = pp, maxPp = maxPp,
          ppText = ("%d/%d"):format(pp, maxPp), powerText = power > 1 and tostring(power) or "—",
          accText = acc > 0 and (tostring(acc) .. "%") or "—", physical = call(Types and Types.isPhysical, t) == true,
          status = power == 0, desc = tostring(call(SD and SD.moveDescription, id, name) or ""):gsub("%s+", " "),
          contest = contestOf(id),
        }
        local c = got.moves[#got.moves].contest
        if c then c.categoryName = word(T, CONTEST[c.category] or CONTEST[0]) end
      end
    end
    -- (Galar Rising's Dynamax: the level and the G-Max Factor, kept by WoobleDex on the Pokémon)
    if Bx.galar and call(Bx.galar) then
      got.dmax, got.gmax = info.dmax, info.gmax
    end
    sums[mon] = got
    return got
  end
  Bx.STAT_ROWS = STAT_ROWS

  -- two of a Pokémon's moves trade places (its PP and PP Ups with them) -> true when done
  function Bx.swapMoves(mon, a, b)
    local P = Pokemon()
    local ok = call(P and P.swapMoves, mon, a, b) == true
    if ok then Bx.forget(mon) end
    return ok
  end

  -- ------- the game's own bits

  -- the box caught Pokémon go to: the one shown last (pokefirered's UpdateBoxToSendMons, as the
  -- game's own storage screen does on close)
  function Bx.sendBox(s)
    if not s then return end
    pcall(function()
      local Profile = engine("src.core.game3.profile")
      local row = Profile.forSession(s)
      local names = row.save and row.save.storage
      if not names then return end
      local C = engine("src.core.game3.constants").of(row.id)
      local Flags = engine("src.core.game3.scripting.flags")
      local Space = package.loaded["src.core.game3.scripting.space"]
      local store = (Space and Space.store) or s.store
      if not (Flags and store) then return end
      if names.boxFullFlag then Flags.setFlag(store, nil, C:require("flags", names.boxFullFlag), false) end
      if names.sendVar then Flags.setVar(store, nil, C:require("vars", names.sendVar), Bx.current(s) - 1) end
    end)
  end

  -- the game's naming screen for a box's name (onDone(name | nil) when it closes)
  function Bx.openNaming(s, b, onDone)
    local Naming = engine("src.ui.game3.naming")
    if not (Naming and Naming.open) then error("the game has no naming screen") end
    local name = Bx.boxName(s, b)
    Naming.open({ template = "BOX", session = s, initialText = name, seed = name, onDone = onDone })
  end

  return Bx
end
