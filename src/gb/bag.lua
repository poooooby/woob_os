-- The Bag behind the modern menus' Bag on the Game Boy games (src/bag_rules.lua's interface, so src/apps/bag.lua and
-- bag_view.lua are unchanged): Red / Blue / Yellow's one list, Gold / Silver / Crystal's four pockets (Items, Balls,
-- Key Items, TM / HM), through the game's own Bag (src/inventory/Bag.lua, src/gb/items.lua's rows). USE is the
-- game's own: src/gb/menus.lua hands it to the game's bag built off the stack (its choosers and words come back into
-- the same window); TOSS asks how many, then the game's question and words; GIVE (Gold / Silver / Crystal) opens
-- the party over it; a Ball's catch chance in a wild battle, the battle's own.
--
--   Bg = GbBag(H, Gd, deps)   deps: T, inv (src/gb/items.lua's), party (src/gb/party.lua's), log
--   (src/bag_rules.lua's functions) ; Bg.useHandler(row, ui) -> the game's USE (set by src/gb/menus.lua while its
--   Bag is up)

return function(H, Gd, deps)
  local Bg = {}
  local T, Inv, Pt = deps.T, deps.inv, deps.party
  local gen, engine = H.gen, H.engine
  local function log(fmt, ...) if deps.log then pcall(deps.log, fmt, ...) end end
  local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b = pcall(f, ...)
    if not ok then
      log("the bag: %s", tostring(a))
      return nil
    end
    return a, b
  end
  local function data() return Gd.data() end
  local function rom(label, ...)
    local R, d = H.engineFn("src.core.RomText"), data()
    if not (R and d) then return "" end
    local ok, s = pcall(R, d, label, nil, ...)
    return ok and type(s) == "string" and s or ""
  end
  Bg.se = function(name) H.se(name) end

  function Bg.pockets(c)
    local out = {}
    for _, p in ipairs(Inv.pockets(c.session) or {}) do
      local id = type(p) == "table" and p.id or p
      -- (choosing what to give: Key Items can't be held)
      if not (c.location == "party" and id == "KEY_ITEMS") then out[#out + 1] = id end
    end
    if #out == 0 then out[1] = "ITEMS" end
    return out
  end

  -- (Gold / Silver / Crystal's registered item, SELECT's)
  local function registered(c)
    local r = c.session and c.session.registeredItem
    return type(r) == "table" and r.id or r
  end
  function Bg.rows(c, pocket)
    local rows = Inv.bagRows(c.session, pocket) or {}
    local reg = gen == 2 and registered(c) or nil
    for _, r in ipairs(rows) do
      if r.showQty ~= false and (tonumber(r.qty) or 0) > 0 then r.qtyText = "×" .. tostring(r.qty) end
      r.registered = reg ~= nil and r.id == reg
    end
    return rows
  end

  local WORD = { USE = "bag.act.use", GIVE = "bag.act.give", TOSS = "bag.act.toss", CANCEL = "party.act.cancel",
                 SET = "bag.act.register", UNSET = "bag.act.deselect" }
  local function act(a, word) return { act = a, text = T(WORD[word or a]) } end
  local function holdable(id)
    local it = Gd.item(id)
    return type(it) == "table" and it.pocket ~= "KEY_ITEM" and it.canToss ~= false
  end
  function Bg.actions(c, pocket, row)
    if not row then return {} end
    if c.battle then return { act("USE"), act("CANCEL") } end
    local rows = { act("USE") }
    if gen == 2 and holdable(row.id) then rows[#rows + 1] = act("GIVE") end
    if not row.important then rows[#rows + 1] = act("TOSS") end
    -- (SEL: Gold / Silver / Crystal's registered item, for SELECT in the field)
    local it = Gd.item(row.id)
    if gen == 2 and type(it) == "table" and it.canSelect ~= false and it.canSelect ~= nil then
      rows[#rows + 1] = act("SET", row.registered and "UNSET" or nil)
    end
    rows[#rows + 1] = act("CANCEL")
    return rows
  end

  function Bg.act(c, a, row, ui)
    if a == "USE" then
      if Bg.useHandler then return Bg.useHandler(row, ui) end
      return ui.back()
    end
    if a == "GIVE" then
      if c.location == "party" then return ui.chosen(row.id) end
      return ui.party("give", row.id)
    end
    if a == "SET" then
      local s = c.session
      if row.registered then
        s.registeredItem = nil
        ui.refresh()
        return
      end
      local g = H.game()
      local w = g and g.world
      local name = tostring(Gd.item(row.id) and Gd.item(row.id).name or row.name)
      local ok = w and w.registerItem and call(w.registerItem, w, row.id)
      ui.refresh()
      if ok then
        H.sfx("Sfx_FullHeal")
        return ui.say(rom("_RegisteredItemText", name))
      end
      return ui.say(rom("_CantRegisterText"))
    end
  end

  -- TOSS: the game's question, then its words
  function Bg.toss(c, row, qty, ui)
    if row.important then
      Bg.se("SE_FAILURE")
      return ui.say(rom("_TooImportantToTossText"))
    end
    local name = tostring(Gd.item(row.id) and Gd.item(row.id).name or row.name)
    local ask = gen == 2 and rom("_AskQuantityThrowAwayText", qty, name) or rom("_IsItOKToTossItemText", name)
    ui.ask(ask, function(yes)
      if not yes then return end
      local B = engine("src.inventory.Bag")
      if gen == 2 then call(B and B.remove, c.session, row.id, qty)
      else call(B and B.remove, c.session, row.id, qty, data(), row.slot) end
      ui.refresh()
      ui.say(rom(gen == 2 and "_ThrewAwayText" or "_ThrewAwayItemText", name))
    end)
  end

  -- SELECT: an item moved to another place in its pocket (the game's own order, as its bag's SELECT swaps)
  local POCKET_OF = { ITEM = "ITEMS", BALL = "POKE_BALLS", KEY_ITEM = "KEY_ITEMS", TM_HM = "TM_CASE" }
  local function inPocket(id, pocket)
    if type(id) ~= "string" or id:find("BADGE", 1, true) then return false end
    if gen == 1 then return true end
    local it = Gd.item(id)
    return (POCKET_OF[it and it.pocket or "ITEM"] or "ITEMS") == pocket
  end
  function Bg.canMove(c, pocket)
    if c.battle or c.location then return false end
    return not (gen == 2 and pocket == "TM_CASE")
  end
  function Bg.move(c, pocket, from, to)
    local rows = Bg.rows(c, pocket)
    local a, b = rows[from], rows[to]
    if from == to or not (a and b) then return false end
    local B = engine("src.inventory.Bag")
    local order = B and call(B.order, c.session, data())
    if type(order) ~= "table" then return false end
    local slots, ids = {}, {}
    for i, id in ipairs(order) do
      if inPocket(id, pocket) then slots[#slots + 1], ids[#ids + 1] = i, id end
    end
    local fi, ti
    for k, id in ipairs(ids) do
      if id == a.id and not fi then fi = k end
      if id == b.id and not ti then ti = k end
    end
    if not (fi and ti) or fi == ti then return false end
    local x = table.remove(ids, fi)
    table.insert(ids, ti, x)
    for k, at in ipairs(slots) do order[at] = ids[k] end
    return true
  end
  function Bg.canSort(c, pocket)
    if c.battle or c.location then return false end
    return not (gen == 2 and pocket == "TM_CASE")
  end
  function Bg.sort(c, pocket, how) return Inv.sortPocket(c.session, pocket, how) end

  -- a Ball's chance in a wild battle: the battle's own reckoning (nil with a catch.rate hook, a trainer's battle)
  function Bg.catchChance(c, id)
    if not c.battle then return nil end
    local it = Gd.item(id)
    local ball = gen == 2 and (it and it.pocket == "BALL") or tostring(id):find("BALL$") ~= nil
    if not ball then return nil end
    local b = Pt and Pt.battleOf and Pt.battleOf()
    if not (b and b.catchChance) then return nil end
    -- (a wild battle only: a trainer's Pokémon can't be caught)
    if gen == 2 then
      if not (b.battle and b.battle.wild) then return nil end
    elseif b.kind ~= "wild" then
      return nil
    end
    return tonumber(call(b.catchChance, b, id))
  end
  function Bg.chanceText(p)
    if not p then return nil end
    if p >= 99.95 then return "100%" end
    if p < 1 then return "<1%" end
    return string.format("%d%%", math.floor(p + 0.5))
  end

  function Bg.giveSource() return nil end
  function Bg.battleParty(c)
    local s = c.session
    return s and s.party or {}, nil, false
  end
  function Bg.battleUse(c, party, order, i, item, ui) ui.back() end
  function Bg.deposit() end
  function Bg.sell() end
  function Bg.sellPrice() return 0 end

  return Bg
end
