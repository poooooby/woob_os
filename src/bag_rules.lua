-- The Bag behind the modern menus' Bag (src/apps/bag.lua draws it; src/menus.lua opens it in place of the
-- game's own on FireRed / LeafGreen / Ruby / Sapphire / Emerald). The rules are the game's: each pocket a
-- page (FireRed / LeafGreen's TM Case and Berry Pouch too, while they hold something), each item's actions
-- as the game's bag offers them (Ruby / Sapphire's own grid), what USE does in the field (a Pokémon to
-- choose, a bike or a rod back to the field, Repel's and Escape Rope's callbacks, the VS Seeker, the
-- Itemfinder, the flutes, the game's words) and in a battle (medicine on a Pokémon through BattleItems,
-- an X item's delay, a Ball refused with the party and boxes full), TOSS, SET (the registered item),
-- moving an item in its pocket (SELECT), GIVE (to the party, or the chosen Pokémon's from the party menu).
--
-- A flow talks to the window through `ui`: ui.say(text, then) ; ui.ask(text, then(yes)) ;
-- ui.party(mode, item) (the party opened over the Bag: "use" | "give" | "battleUse") ; ui.wait(frames, fn) ;
-- ui.leave(fn) (everything closed, then fn) ; ui.battle(id, slot, moveSlot, usedInMenu) (the battle's
-- answer: closed with it) ; ui.refresh() ; ui.classic() (the game's own bag instead: Ruby / Sapphire's mail)
--
--   Bg = bagRules(engine, deps)       deps: T, inv (src/inventory.lua's), log
--   Bg.pockets(c) -> { "ITEMS", ... } ; Bg.rows(c, pocket) -> rows (Inv's, with tm = a move's record,
--   registered) ; Bg.actions(c, pocket, row) -> { { act, text } ... } ; Bg.act(c, act, row, ui) ;
--   Bg.canMove(c, pocket) ; Bg.move(c, pocket, from, to) ; Bg.toss(c, row, qty, ui) ;
--   Bg.battleParty(c) -> party (shown order), order, double ; Bg.giveSource(bag) ; Bg.battleUse(c, party, order, i, ui) (an item on the
--   i-th shown in battle)
--   c = { session, bag, battle, location ("party": choosing what to give), onBattleUse }

return function(engine, deps)
  local Bg = {}
  local T, Inv = deps.T, deps.inv
  local function log(fmt, ...) if deps.log then pcall(deps.log, fmt, ...) end end
  local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(f, ...)
    if not ok then
      log("the bag: %s", tostring(a))
      return nil
    end
    return a, b, c, d, e
  end
  local function I() return engine("src.core.game3.items_data") end
  local function IU() return engine("src.core.game3.item_use") end
  local function BI() return engine("src.core.game3.battle.items") end
  local function B() return engine("src.core.game3.bag") end
  local function se(id)
    local Audio, SeIds = engine("src.core.game3.audio"), engine("src.core.game3.se_ids")
    pcall(function() Audio.playSe(type(id) == "number" and id or (SeIds[id] or SeIds.resolve(id))) end)
  end
  Bg.se = se
  local function box(key, vars)
    local R = engine("src.core.game3.rom_text")
    local ok, s = pcall(R.box, key, { stringVars = vars, maxWidth = 216 })
    return ok and s or ""
  end
  local function plain(key, vars)
    local R = engine("src.core.game3.rom_text")
    local ok, s = pcall(R.plain, key, vars and { stringVars = vars } or nil)
    return ok and s or ""
  end
  local function family(s)
    local Pr = engine("src.core.game3.profile")
    local ok, f = pcall(Pr.family, s)
    return ok and f or nil
  end
  local function rs(s)
    local Pr = engine("src.core.game3.profile")
    local ok, row = pcall(Pr.forSession, s)
    return ok and row and (row.id == "ruby" or row.id == "sapphire") or false
  end
  local function skin(s)
    local Screens = engine("src.ui.game3.screens")
    local ok, sk = pcall(Screens.skin, "bag", s)
    return ok and sk or nil
  end
  local function num(id) return tonumber(call(I().toNumericId, id)) or tonumber(id) or 0 end
  local function linked()
    local Map, UR = engine("src.core.game3.map"), engine("src.core.game3.link.union_room")
    local okU, union = pcall(function() return UR.isUnionMap(Map.current) end)
    if okU and union then return true end
    local Link = package.loaded["src.core.game3.link"]
    if type(Link) == "table" and Link.link ~= nil then
      local okL, inRoom = pcall(Link.inLinkRoom)
      return okL and inRoom == true
    end
    return false
  end

  -- ------- pockets and rows

  function Bg.pockets(c)
    local out = {}
    for _, p in ipairs(Inv.pockets(c.session)) do out[#out + 1] = p.id end
    if #out == 0 then out[1] = "ITEMS" end
    return out
  end

  function Bg.rows(c, pocket)
    local rows = Inv.bagRows(c.session, pocket)
    local s = c.session
    local reg = s and s.registeredItem
    local regNum = reg and num(reg) or 0
    local Pk = engine("src.core.game3.pokemon")
    for _, r in ipairs(rows) do
      r.registered = regNum ~= 0 and num(r.id) == regNum
      if call(I().isTm, r.id) then
        local mid = Pk and call(Pk.moveFromTmItem, r.id)
        if mid and deps.moveRecord then r.tm = call(deps.moveRecord, mid, T) end
        if r.tm then
          -- (its move by name beside the number, its type in WoobOS's words: the game keeps six capitals)
          r.name = tostring(r.name) .. " " .. tostring(r.tm.name)
          local key = "type." .. tostring(r.tm.typeId)
          if T.has and T.has(key) then r.tm.typeName = T(key) end
        end
      end
    end
    return rows
  end

  -- ------- each item's actions, as the game's bag offers them

  local WORD = { USE = "bag.act.use", GIVE = "bag.act.give", TOSS = "bag.act.toss", SET = "bag.act.register",
                 CANCEL = "party.act.cancel", CHECK_TAG = "bag.act.checkTag", OPEN = "bag.act.use",
                 CONFIRM = "bag.act.use" }
  local function gameActions(c, pocket, row)
    local sk = skin(c.session)
    if sk and sk.actionsForPocket then
      local ok, list = pcall(sk.actionsForPocket, pocket, row, c.view)
      if ok and type(list) == "table" then return list end
    end
    if c.battle then
      return (row and call(BI().isBattleUsable, row.id)) and { "USE", "CANCEL" } or { "CANCEL" }
    end
    if c.location == "party" then
      return (pocket ~= "KEY_ITEMS" and pocket ~= "TM_CASE") and { "GIVE", "CANCEL" } or { "CANCEL" }
    end
    if linked() then
      local n = row and num(row.id)
      if n == I().ITEM_TM_CASE or n == I().ITEM_BERRY_POUCH then return { "USE", "CANCEL" } end
      if pocket == "KEY_ITEMS" then return { "CANCEL" } end
      return { "GIVE", "CANCEL" }
    end
    local info = row and call(I().info, row.id)
    local registrable = info and (tonumber(info.registrability) or 0) > 0
    if pocket == "KEY_ITEMS" then return registrable and { "USE", "SET", "CANCEL" } or { "USE", "CANCEL" } end
    if pocket == "POKE_BALLS" then return { "GIVE", "TOSS", "CANCEL" } end
    if pocket == "TM_CASE" then return { "USE", "CANCEL" } end
    if pocket == "BERRY_POUCH" then
      if family(c.session) == "rse" then return { "CHECK_TAG", "USE", "GIVE", "TOSS", "CANCEL" } end
      return { "USE", "GIVE", "TOSS", "CANCEL" }
    end
    return { "USE", "GIVE", "TOSS", "CANCEL" }
  end

  function Bg.actions(c, pocket, row)
    local out = {}
    for _, a in ipairs(gameActions(c, pocket, row)) do
      if a then
        local key = WORD[a]
        if a == "SET" and row and row.registered then key = "bag.act.deselect" end
        out[#out + 1] = { act = a, text = key and T(key) or tostring(a) }
      end
    end
    return out
  end

  -- ------- moving an item within its pocket (SELECT), as the game's bag allows it

  function Bg.canMove(c, pocket)
    if c.location ~= nil or not (c.bag and c.bag.pockets) then return false end
    local m = I().BAG_MODEL
    if m and ((m.sortHmsFirst and m.sortHmsFirst[pocket]) or (m.sortById and m.sortById[pocket])) then return false end
    if c.battle then return family(c.session) == "rse" end
    return true
  end
  function Bg.move(c, pocket, from, to)
    call(B().listPocket, c.bag, pocket)
    local slots = c.bag.pockets and c.bag.pockets[pocket]
    if type(slots) ~= "table" or from == to or not slots[from] then return false end
    local slot = table.remove(slots, from)
    table.insert(slots, math.min(#slots + 1, to), slot)
    return true
  end

  -- ------- TOSS (how many already chosen)

  -- (each family's words: FireRed / LeafGreen's, Emerald's, Ruby / Sapphire's)
  local function first(...)
    local R = engine("src.core.game3.rom_text")
    for k = 1, select("#", ...) do
      local key = select(k, ...)
      if R and call(R.has, key) then return key end
    end
    return (...)
  end
  function Bg.toss(c, row, qty, ui)
    local n = tostring(qty)
    local ask = first("gText_ThrowAwayStrVar2OfThisItemQM", "gText_ConfirmTossItems", "gOtherText_OkayToThrowAwayPrompt")
    local said = first("gText_ThrewAwayStrVar2StrVar1s", "gText_ThrewAwayVar2Var1s", "gOtherText_ThrewAwayItem")
    ui.ask(box(ask, ask == "gText_ThrowAwayStrVar2OfThisItemQM" and { [2] = n } or { row.name, n }), function(yes)
      if not yes then return end
      call(B().remove, c.bag, row.id, qty)
      ui.refresh()
      ui.say(box(said, { row.name, n }))
    end)
  end

  -- ------- the battle's party: the live copy, in the battle's order

  function Bg.battleParty(c)
    local PV = engine("src.core.game3.battle.party_view")
    local party = PV and call(PV.live, c.session) or (c.session and c.session.party) or {}
    local Bt = engine("src.core.game3.battle")
    local st = Bt and Bt._st
    local PM = engine("src.ui.game3.party_menu")
    local order = (st and st.playerParty and PM) and call(PM.battleOrder, st) or nil
    local double = type(st) == "table" and st.double == true
    if type(order) ~= "table" then return party, nil, double end
    local view = {}
    for i, pi in ipairs(order) do view[i] = party[pi] end
    return view, order, double
  end

  -- (what an item given from the party's GIVE is taken from: the Bag, as the game's party menu says it)
  function Bg.giveSource(bag)
    local IUm = IU()
    return IUm and call(IUm.partyGiveSource, bag) or nil
  end

  local QUIET = { say = function() end }

  -- an item used on the i-th shown in battle (the game's commitBattlePartyUse)
  function Bg.battleUse(c, party, order, i, item, ui)
    local Bt = engine("src.core.game3.battle")
    local st = Bt and Bt._st
    local mon = party[i]
    local slot = order and order[i] or i
    local IUm, BIm = IU(), BI()
    local function wont(err)
      se("SE_SELECT")
      ui.say(err or box("gText_WontHaveEffect"), function() ui.back("battleUse") end)
    end
    local function commit(moveSlot)
      local ok, err = BIm.canUseOn(st, item, slot, mon, moveSlot)
      if not ok then return wont(err) end
      local h0 = tonumber(mon and mon.hp) or 0
      local result, _, _, _, text = BIm.use(st, QUIET, c.bag, c.session, item, slot, nil, moveSlot)
      if result ~= "heal" then return wont() end
      se(call(BIm.isFlute, item) and "SE_GLASS_FLUTE" or "SE_USE_ITEM")
      ui.refresh()
      local function said() ui.say(text or "", function() ui.battle(item, slot, moveSlot, true) end) end
      local h1 = tonumber(mon and mon.hp) or h0
      if h1 > h0 then ui.hp(i, h0, h1, said) else said() end
    end
    if mon and not mon.isEgg and call(IUm.fieldUseKind, item, c.session, true) == "pp" and call(IUm.ppItemNeedsMove, item) then
      se("SE_SELECT")
      local Pk = engine("src.core.game3.pokemon")
      local names, slots = {}, {}
      for k = 1, 4 do
        local id = call(Pk.moveIdAt, mon, k)
        if id and id > 0 then
          names[#names + 1] = tostring(call(Pk.moveName, id) or "")
          slots[#slots + 1] = k
        end
      end
      local prompt = call(IUm.ppItemBoosts, item) and plain("gText_BoostPp") or plain("gText_RestoreWhichMove")
      return ui.pick(prompt, names, function(k)
        if k == nil then return ui.back("battleUse") end
        commit(slots[k + 1])
      end)
    end
    commit(nil)
  end

  -- ------- an action on an item

  local FIELD_EXIT = { bike = true, rod = true }

  -- (the START menu closed under ours, as the game's bag does when it leaves for the field)
  local function closeStart()
    local StartMenu = engine("src.ui.game3.start_menu")
    if StartMenu and StartMenu.isOpen and call(StartMenu.isOpen) then
      StartMenu.open = false
      StartMenu._onClose = nil
      local Stack = engine("src.ui.game3.stack")
      if Stack then pcall(Stack.pop, "start") end
    end
  end
  local function fadeIn()
    local Fade = engine("src.ui.game3.fade")
    if Fade and Fade.begin and Fade.MODE then pcall(Fade.begin, Fade.MODE.FROM_BLACK, 1) end
  end

  local function fieldUse(c, row, ui)
    local s, IUm = c.session, IU()
    local id = row.id
    local sk = skin(s)
    -- (Ruby / Sapphire: an item with no field use does nothing)
    if sk and sk.beforeAction and rs(s) then
      local info = call(I().info, id)
      if info and tonumber(info.fieldUseFunc) == 0 then return end
    end
    if call(IUm.needsPartyTarget, id) then
      if not (s.party and s.party[1]) then return ui.say(plain("gText_ThereIsNoPokemon")) end
      return ui.party("use", id)
    end
    local ok, kind, text = IUm.useField(s, c.bag, id, nil)
    if kind == "vs_seeker" then
      if not ok then return ui.say(text) end
      return ui.leave(function()
        closeStart()
        fadeIn()
        local Vs = engine("src.core.game3.vs_seeker")
        if Vs then pcall(Vs.use, s, nil) end
      end)
    elseif kind == "itemfinder" then
      return ui.leave(function()
        closeStart()
        fadeIn()
        local Field = engine("src.core.game3.field")
        if Field then pcall(Field.useItemfinder, s, true) end
      end)
    elseif ok and (kind == "escape" or kind == "on_field") then
      return ui.leave(function()
        closeStart()
        fadeIn()
        call(IUm.runOnFieldCallback)
      end)
    elseif ok and FIELD_EXIT[kind] then
      return ui.leave(function()
        closeStart()
        fadeIn()
      end)
    elseif ok and kind == "black_white_flute" then
      return ui.wait(IUm.BLACK_WHITE_FLUTE_DELAY or 8, function()
        call(IUm.playBlackWhiteFlute)
        ui.refresh()
        ui.say(text)
      end)
    end
    ui.refresh()
    if text then ui.say(text) end
  end

  local function battleUse(c, row, ui)
    local id, BIm = row.id, BI()
    if call(BIm.needsPartySelect, id) then return ui.party("battleUse", id) end
    local Bt, Ui = engine("src.core.game3.battle"), engine("src.core.game3.battle.ui")
    local st = Bt and Bt._st
    if call(BIm.isStatBooster, id) then
      local battler = (st and st.double and Ui and Ui._active) or 0
      if not (st and call(BIm.statBoosterHasEffect, st, id, battler)) then
        return ui.say(box("gText_WontHaveEffect"))
      end
      return ui.wait(7, function()
        se("SE_USE_ITEM")
        local _, _, _, _, text = BIm.use(st, QUIET, c.bag, c.session, id, nil, battler)
        ui.say(text or "", function() ui.battle(id, nil, nil, true) end)
      end)
    end
    if call(BIm.isBall, id) then
      local BM = engine("src.ui.game3.bag_menu")
      if BM and call(BM.partyAndStorageFull, c.session) then
        local R = engine("src.core.game3.rom_text")
        local key = (R and call(R.has, "gOtherText_BoxIsFull")) and "gOtherText_BoxIsFull" or "gText_BoxFull"
        return ui.say(box(key))
      end
    end
    ui.battle(id, nil)
  end

  function Bg.act(c, act, row, ui)
    local s = c.session
    if act == "USE" or act == "OPEN" then
      if c.battle then return battleUse(c, row, ui) end
      return fieldUse(c, row, ui)
    elseif act == "GIVE" then
      local sk = skin(s)
      local pocket = row.pocket
      local can = sk and sk.canGive and call(sk.canGive, row, pocket)
      if can == false or (can == nil and (pocket == "KEY_ITEMS" or pocket == "TM_CASE")) then
        return ui.say(box("gText_ItemCantBeHeld", { tostring(row.name) }))
      end
      if c.location == "party" then return ui.chosen(row.id) end
      if not (s.party and s.party[1]) then return ui.say(plain("gText_ThereIsNoPokemon")) end
      -- (Ruby / Sapphire's mail is written in the game's own screens: its bag instead)
      local Mail = engine("src.core.game3.mail")
      if rs(s) and Mail and call(Mail.isMailItem, num(row.id)) then return ui.classic() end
      return ui.party("give", row.id)
    elseif act == "SET" then
      if rs(s) then
        s.registeredItem = row.registered and 0 or num(row.id)
      else
        s.registeredItem = row.registered and nil or row.id
      end
      ui.refresh()
    elseif act == "CHECK_TAG" then
      local Screens = engine("src.ui.game3.screens")
      local okT, Tag = pcall(Screens.get, "berry_tag", s)
      if okT and Tag and Tag.show then
        local list = {}
        for k, r in ipairs(c.rows or {}) do list[k] = r.id end
        pcall(Tag.show, { session = s, list = list, pos = (c.cursor or 1) - 1,
                          onMove = function(_, pos) c.cursor = pos + 1 end, onClose = function() end })
      end
    end
  end

  return Bg
end
