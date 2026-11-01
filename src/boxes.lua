-- The Pokémon model behind the Boxes app: the party and the PC's 14 boxes, through the engine's own
-- Storage (src.core.game3.storage), so the session changes as the game's own storage screens change
-- it (a Pokémon going into a box is healed, the party stays packed, the quest log hears of it).
-- The game's rules hold on all five games: the party keeps a Pokémon that can battle, a Pokémon
-- holding mail stays out of the boxes, eggs and mail holders aren't released.
--
--   Bx = boxes(engine)        engine(name) -> an engine module or nil (kept by the caller)
--   Bx.BOXES, Bx.SLOTS, Bx.COLS, Bx.ROWS, Bx.PARTY
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
--       until Bx.forget(mon))
--   Bx.dynamax = fn() -> WoobleDex's exports.dynamax | nil (main.lua): the preview's Dynamax Level
--       (info.dmax 0..10, nil when it can't Dynamax) and Gigantamax Factor (info.gmax)
--   Bx.sendBox(s) the box caught Pokémon go to = the current one (as the game's own screen does on close)
--   Bx.openSummary(s, mons, index, context, onClose) ; Bx.openNaming(s, b, onDone)
--   reasons: "last_usable" | "mail" | "party_full" | "no_room" | "egg" | "gone" | "bag_full" | "holding" |
--       "cant_hold" | "no_item" | "needed" ; the words are lang/*.lua's "reason.box.<reason>"

return function(engine)
  local Bx = { BOXES = 14, SLOTS = 30, COLS = 6, ROWS = 5, PARTY = 6 }
  local floor = math.floor

  local function Storage() return engine("src.core.game3.storage") end
  local function Pokemon() return engine("src.core.game3.pokemon") end
  local function Mail() return engine("src.core.game3.mail") end

  -- ------- places

  local PARTY_ADDR, BOX_ADDR = {}, {}
  for i = 1, Bx.PARTY do PARTY_ADDR[i] = { loc = "party", slot = i } end
  for b = 1, Bx.BOXES do
    local row = {}
    for i = 1, Bx.SLOTS do row[i] = { loc = "box", slot = i, boxId = b } end
    BOX_ADDR[b] = row
  end
  function Bx.addr(loc, slot, box)
    if loc == "party" then return PARTY_ADDR[slot] end
    return BOX_ADDR[box] and BOX_ADDR[box][slot]
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
  function Bx.forget(mon) if mon then infos[mon] = nil end end
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

  -- the game's summary screen over a list of Pokémon (onClose: when it closes)
  function Bx.openSummary(s, mons, index, context, onClose)
    local Summary = engine("src.ui.game3.summary_menu")
    if not (Summary and Summary.openMenu) then error("the game has no summary screen") end
    Summary.openMenu(mons, index, { session = s, context = context, onClose = onClose })
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
