-- The shop behind the Mart app: the Poké Mart's goods, more of them as the player earns Gym Badges
-- (as the later games' Marts do), bought into the Bag; and the Bag's items sold back for half their
-- price. Prices and names are the game's own (src.core.game3.items_data); money is the session's,
-- the Bag the engine's own (src.core.game3.bag). Rows are made here when something changes.
--
--   Mt = mart(engine)        engine(name) -> an engine module or nil (kept by the caller)
--   Mt.TABS                  { { key = "mart.balls", rows = { { id, badges, price, name } ... } } ... }
--   Mt.badges(s) -> 0..8     Mt.money(s) -> n     Mt.inBag(s, id) -> n
--   Mt.price(id) -> n | nil  Mt.sellPrice(id) -> n | nil (nil: can't be sold)
--   Mt.buy(s, id, qty, badges) -> true, bonus | false, reason   (bonus: a Premier Ball came with it)
--   Mt.sell(s, id, qty) -> true, earned | false, reason
--   Mt.sellRows(s, pocket) -> rows { id, qty, name, desc, price (nil: can't be sold) }
--   reasons: "badges" | "money" | "bag_full" | "cant_sell" | "gone" (lang/*.lua "reason.mart.<reason>")

local floor, max = math.floor, math.max

local PREMIER, POKE_BALL, BONUS_AT = 12, 4, 10
local MAX_QTY = 99

-- the stock, by tab: item id, the badges it needs
local STOCK = {
  { key = "mart.balls", items = {
    { 4, 0 }, { 3, 1 }, { 8, 3 }, { 6, 3 }, { 2, 5 }, { 7, 5 }, { 9, 5 }, { 10, 5 }, { 11, 6 },
  } },
  { key = "mart.medicine", items = {
    { 13, 0 }, { 14, 0 }, { 18, 0 }, { 17, 0 }, { 15, 0 }, { 16, 0 }, { 22, 1 }, { 21, 3 }, { 24, 3 },
    { 23, 5 }, { 20, 7 }, { 19, 8 },
  } },
  { key = "mart.battle", items = {
    { 75, 2 }, { 76, 2 }, { 77, 2 }, { 78, 2 }, { 79, 2 }, { 73, 2 }, { 74, 2 },
  } },
  { key = "mart.field", items = {
    { 86, 0 }, { 85, 0 }, { 83, 3 }, { 84, 5 },
  } },
}

return function(engine)
  local Mt = { MAX_QTY = MAX_QTY, PREMIER = PREMIER }

  local function mods()
    return engine("src.core.game3.bag"), engine("src.core.game3.items_data")
  end
  local function ready(s)
    local Bag, ItemsData = mods()
    if not (s and Bag and ItemsData) then return nil end
    if ItemsData.ensureModel then pcall(ItemsData.ensureModel, s) end
    s.bag = s.bag or Bag.new()
    return Bag, ItemsData
  end
  local function infoOf(id)
    local _, ItemsData = mods()
    if not ItemsData then return nil end
    local ok, info = pcall(ItemsData.info, id)
    return ok and info or nil
  end
  local function descOf(info)
    return ((info and info.description) or ""):gsub("\\n", " "):gsub("\\p", " "):gsub("\n", " ")
  end

  function Mt.price(id)
    local info = infoOf(id)
    local p = info and floor(tonumber(info.price) or 0) or 0
    return p > 0 and p or nil
  end
  function Mt.sellPrice(id)
    local info = infoOf(id)
    if not info or (tonumber(info.importance) or 0) ~= 0 then return nil end
    local p = floor((tonumber(info.price) or 0) / 2)
    return p > 0 and p or nil
  end

  -- the tabs' rows, made once (the game's data is in by the time the window first opens)
  local tabs
  function Mt.tabs()
    if tabs then return tabs end
    local made = {}
    for _, t in ipairs(STOCK) do
      local rows = {}
      for _, e in ipairs(t.items) do
        local info = infoOf(e[1])
        local price = Mt.price(e[1])
        if info and price then
          rows[#rows + 1] = { id = e[1], badges = e[2], price = price, name = info.name or tostring(e[1]),
                              desc = descOf(info) }
        end
      end
      made[#made + 1] = { key = t.key, rows = rows }
    end
    -- (no data yet: try again next time)
    if #made[1].rows > 0 then tabs = made end
    return made
  end

  function Mt.badges(s)
    local Flags = engine("src.core.game3.scripting.flags")
    if not (Flags and Flags.countBadges) then return 8 end
    local Space = engine("src.core.game3.scripting.space")
    local store = Space and Space.getStore and Space.getStore()
    if type(store) ~= "table" or type(store.flags) ~= "table" then
      store = s and type(s.store) == "table" and s.store or { flags = s and s.flags or {} }
    end
    local ok, n = pcall(Flags.countBadges, store)
    return ok and tonumber(n) or 0
  end
  function Mt.inBag(s, id)
    local Bag = ready(s)
    if not Bag then return 0 end
    local ok, n = pcall(Bag.get, s.bag, id)
    return ok and tonumber(n) or 0
  end
  function Mt.money(s)
    return max(0, floor(tonumber(s and s.money) or 0))
  end

  function Mt.buy(s, id, qty, badges)
    qty = max(1, floor(tonumber(qty) or 1))
    local Bag = ready(s)
    if not Bag then return false, "bag_full" end
    local need = 0
    for _, t in ipairs(STOCK) do
      for _, e in ipairs(t.items) do if e[1] == id then need = e[2] end end
    end
    if need > (badges or 0) then return false, "badges" end
    local price = Mt.price(id)
    if not price then return false, "gone" end
    local cost = price * qty
    if cost > Mt.money(s) then return false, "money" end
    local okC, can = pcall(Bag.canAdd, s.bag, id, qty)
    if not (okC and can) then return false, "bag_full" end
    local okA, added = pcall(Bag.add, s.bag, id, qty)
    if not (okA and added) then return false, "bag_full" end
    s.money = Mt.money(s) - cost
    -- (ten Poké Balls at once: a Premier Ball thrown in, as the game's Marts do)
    local bonus = false
    if id == POKE_BALL and qty >= BONUS_AT then
      local okP, room = pcall(Bag.canAdd, s.bag, PREMIER, 1)
      if okP and room then
        local okB, got = pcall(Bag.add, s.bag, PREMIER, 1)
        bonus = okB and got and true or false
      end
    end
    return true, bonus
  end

  function Mt.sell(s, id, qty)
    qty = max(1, floor(tonumber(qty) or 1))
    local Bag = ready(s)
    if not Bag then return false, "gone" end
    local price = Mt.sellPrice(id)
    if not price then return false, "cant_sell" end
    if (tonumber(Bag.get(s.bag, id)) or 0) < qty then return false, "gone" end
    local okR, removed = pcall(Bag.remove, s.bag, id, qty)
    if not (okR and removed) then return false, "gone" end
    local Prize = engine("src.core.game3.battle.prize")
    local earned = price * qty
    if Prize and Prize.apply then
      earned = Prize.apply(s, earned)
    else
      local total = math.min(999999, Mt.money(s) + earned)
      earned, s.money = total - Mt.money(s), total
    end
    -- (the last one sold: it can't stay the registered item)
    if s.registeredItem == id and (tonumber(Bag.get(s.bag, id)) or 0) <= 0 then s.registeredItem = 0 end
    return true, earned
  end

  function Mt.sellRows(s, pocket)
    local out = {}
    local Bag = ready(s)
    if not Bag then return out end
    local ok, rows = pcall(Bag.listPocket, s.bag, pocket)
    if not ok or not rows then return out end
    for _, row in ipairs(rows) do
      local info = infoOf(row.id)
      out[#out + 1] = { id = row.id, qty = tonumber(row.qty) or 0, name = info and info.name or tostring(row.id),
                        desc = descOf(info), price = Mt.sellPrice(row.id) }
    end
    return out
  end

  return Mt
end
