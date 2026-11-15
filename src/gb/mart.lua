-- The Mart app's shop on the Game Boy games: the Poké Mart's goods, more of them with each Gym Badge,
-- bought into the Bag (the engine's own, src/inventory/Bag.lua) and the Bag's items sold back for half their
-- price. Prices and names are the game's own data (an item the game prices at 0 isn't sold). The same
-- interface as src/mart.lua, so the Mart window is the same; there's no Premier Ball on these games, so no
-- bonus ball. Gold / Silver / Crystal's sixteen Badges count to eight here (the shelves stop growing there).
--
--   Mt = mart(host, Gd, deps)   deps.save (mod.save: "mart", the Badges the clerk last saw) ;
--       pay(s, n) -> what went into the wallet (the rest to the Bank)
--   (the interface: src/mart.lua's header)

local floor, max, min = math.floor, math.max, math.min
local MAX_QTY = 99

-- the stock by tab: the item's id, the Badges it needs
local STOCK = {
  { key = "mart.balls", items = { { "POKE_BALL", 0 }, { "GREAT_BALL", 2 }, { "ULTRA_BALL", 4 } } },
  { key = "mart.medicine", items = {
    { "POTION", 0 }, { "ANTIDOTE", 0 }, { "PARLYZ_HEAL", 0 }, { "AWAKENING", 0 }, { "BURN_HEAL", 0 },
    { "ICE_HEAL", 0 }, { "SUPER_POTION", 1 }, { "FULL_HEAL", 3 }, { "REVIVE", 3 }, { "ETHER", 4 },
    { "HYPER_POTION", 5 }, { "MAX_POTION", 7 }, { "FULL_RESTORE", 8 },
  } },
  { key = "mart.battle", items = {
    { "X_ATTACK", 2 }, { "X_DEFEND", 2 }, { "X_SPEED", 2 }, { "X_SPECIAL", 2 }, { "X_ACCURACY", 2 },
    { "GUARD_SPEC", 2 }, { "DIRE_HIT", 2 },
  } },
  { key = "mart.field", items = { { "ESCAPE_ROPE", 0 }, { "REPEL", 0 }, { "SUPER_REPEL", 3 }, { "MAX_REPEL", 5 } } },
}

return function(H, Gd, deps)
  deps = deps or {}
  local engine = H.engine
  local Mt = { MAX_QTY = MAX_QTY, store = deps.save }
  local function Bag() return engine("src.inventory.Bag") end

  local function important(id)
    local it = Gd.item(id)
    if not it then return true end
    if Gd.gen == 2 then return it.pocket == "KEY_ITEM" or (it.pocket == "TM_HM" and tostring(it.name):match("^HM") ~= nil) end
    return it.keyItem == true or tostring(id):match("^HM_") ~= nil
  end
  local function descOf(id) return Gd.itemDesc(id) end

  function Mt.price(id)
    local it = Gd.item(id)
    local p = it and floor(tonumber(it.price) or 0) or 0
    return p > 0 and p or nil
  end
  function Mt.sellPrice(id)
    if important(id) then return nil end
    local it = Gd.item(id)
    local p = floor((tonumber(it and it.price) or 0) / 2)
    return p > 0 and p or nil
  end

  local tabs
  function Mt.tabs()
    if tabs then return tabs end
    local made = {}
    for _, t in ipairs(STOCK) do
      local rows = {}
      for _, e in ipairs(t.items) do
        local price = Mt.price(e[1])
        if price then
          rows[#rows + 1] = { id = e[1], badges = e[2], price = price, name = Gd.itemName(e[1]), desc = descOf(e[1]) }
        end
      end
      made[#made + 1] = { key = t.key, rows = rows }
    end
    if #made[1].rows > 0 then tabs = made end
    return made
  end

  function Mt.badges(s) return min(8, Gd.badges(s)) end
  function Mt.inBag(s, id) return tonumber(s and s.inventory and s.inventory[id]) or 0 end
  function Mt.money(s) return Gd.money(s) end

  function Mt.buy(s, id, qty, badges)
    qty = max(1, floor(tonumber(qty) or 1))
    local B = Bag()
    if not (s and B) then return false, "bag_full" end
    local need = nil
    for _, t in ipairs(STOCK) do
      for _, e in ipairs(t.items) do if e[1] == id then need = e[2] end end
    end
    if not need then return false, "gone" end
    if need > (badges or 0) then return false, "badges" end
    local price = Mt.price(id)
    if not price then return false, "gone" end
    local cost = price * qty
    if cost > Mt.money(s) then return false, "money" end
    if not B.add(s, id, qty, Gd.data()) then return false, "bag_full" end
    Gd.setMoney(s, Mt.money(s) - cost)
    return true, false
  end

  function Mt.sell(s, id, qty)
    qty = max(1, floor(tonumber(qty) or 1))
    local B = Bag()
    if not (s and B) then return false, "gone" end
    local price = Mt.sellPrice(id)
    if not price then return false, "cant_sell" end
    if Mt.inBag(s, id) < qty then return false, "gone" end
    B.remove(s, id, qty, Gd.data())
    local earned = price * qty
    if deps.pay then earned = deps.pay(s, earned) else earned = Gd.addMoney(s, earned) end
    return true, earned
  end

  -- the Bag's pocket, sellable or not (the window greys what can't be)
  function Mt.sellRows(s, pocket)
    local out = {}
    local B = Bag()
    if not (s and B) then return out end
    local GP = { ITEMS = "ITEM", POKE_BALLS = "BALL", KEY_ITEMS = "KEY_ITEM", TM_CASE = "TM_HM" }
    for _, r in ipairs(B.rows(s, Gd.data())) do
      local id = r.id
      if not (type(id) == "string" and id:find("BADGE", 1, true)) then
        local it = Gd.item(id)
        local inPocket = Gd.gen == 1 or (it and it.pocket or "ITEM") == (GP[pocket] or "ITEM")
        if inPocket then
          out[#out + 1] = { id = id, qty = tonumber(r.count) or 0, name = Gd.itemName(id), desc = descOf(id),
                            price = Mt.sellPrice(id) }
        end
      end
    end
    return out
  end

  local loose
  function Mt.seen()
    local d = Mt.store and Mt.store:get("mart") or loose
    return type(d) == "table" and tonumber(d.seen) or nil
  end
  function Mt.see(n)
    local d = { seen = floor(tonumber(n) or 0) }
    if Mt.store then Mt.store:set("mart", d) else loose = d end
  end

  return Mt
end
