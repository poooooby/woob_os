-- The Items app's model on the Game Boy games: the PC's item storage (50 kinds) and the Bag (Gen 1: one
-- list of 20; Gen 2: four pockets, Items 20, Balls 12, Key Items 25, TM / HM 57), through the engine's own
-- Bag (src/inventory/Bag.lua), so the save changes exactly as the game's own PC changes it. The same
-- interface as src/inventory.lua, so the Items window is the same.
--
--   Inv = items(host, Gd)   (the interface: src/inventory.lua's header)

return function(H, Gd)
  local engine = H.engine
  local gen = H.gen
  local Inv = {}
  local PC_CAP = 50

  local function Bag() return engine("src.inventory.Bag") end
  local function data() return Gd.data() end

  -- the game's pockets, as the windows' words name them
  local POCKET = { ITEM = "ITEMS", BALL = "POKE_BALLS", KEY_ITEM = "KEY_ITEMS", TM_HM = "TM_CASE" }
  local GAME_POCKET = { ITEMS = "ITEM", POKE_BALLS = "BALL", KEY_ITEMS = "KEY_ITEM", TM_CASE = "TM_HM" }
  local ORDER = { "ITEMS", "POKE_BALLS", "KEY_ITEMS", "TM_CASE" }

  local function pocketOf(id)
    if gen == 1 then return "ITEMS" end
    local it = Gd.item(id)
    return POCKET[it and it.pocket or "ITEM"] or "ITEMS"
  end
  local function important(id)
    local it = Gd.item(id)
    if not it then return false end
    if gen == 2 then return it.pocket == "KEY_ITEM" or (it.pocket == "TM_HM" and tostring(it.name):match("^HM") ~= nil) end
    return it.keyItem == true or tostring(id):match("^HM_") ~= nil
  end
  local function isBadge(id) return type(id) == "string" and id:find("BADGE", 1, true) ~= nil end

  function Inv.pockets(s)
    if gen == 1 then return { { id = "ITEMS" } } end
    local out = {}
    for _, p in ipairs(ORDER) do out[#out + 1] = { id = p } end
    return out
  end

  local function rowFor(id, qty, slot)
    local it = Gd.item(id)
    local imp = important(id)
    local pocket = pocketOf(id)
    local desc = it and it.description or ""
    desc = tostring(desc):gsub("<NEXT>", " "):gsub("[\n\f]", " ")
    return {
      id = id, qty = qty, pocket = pocket, slot = slot,
      name = Gd.itemName(id), desc = desc, important = imp,
      showQty = not (imp or pocket == "KEY_ITEMS"),
    }
  end

  function Inv.pcRows(s)
    local out = {}
    local B = Bag()
    if not (s and B) then return out end
    for _, r in ipairs(B.pcRows(s, data())) do
      if not isBadge(r.id) then out[#out + 1] = rowFor(r.id, tonumber(r.count) or 0, r.slot) end
    end
    return out
  end

  function Inv.bagRows(s, pocket)
    local out = {}
    local B = Bag()
    if not (s and B) then return out end
    for _, r in ipairs(B.rows(s, data())) do
      if not isBadge(r.id) and (gen == 1 or pocketOf(r.id) == pocket) then
        out[#out + 1] = rowFor(r.id, tonumber(r.count) or 0, r.slot)
      end
    end
    return out
  end

  function Inv.pcCount(s)
    return #Inv.pcRows(s), PC_CAP
  end

  function Inv.withdraw(s, pcIdx, qty)
    local B = Bag()
    local row = Inv.pcRows(s)[pcIdx]
    if not (B and row) then return false, "gone" end
    qty = math.max(1, math.min(qty or 1, row.qty))
    if not B.add(s, row.id, qty, data()) then return false, "bag_full" end
    B.pcRemove(s, row.id, qty, data(), row.slot)
    return true
  end

  function Inv.deposit(s, pocket, bagIdx, qty)
    local B = Bag()
    local row = Inv.bagRows(s, pocket)[bagIdx]
    if not (B and row) then return false, "gone" end
    if row.important then return false, "important" end
    qty = math.max(1, math.min(qty or 1, row.qty))
    if not B.pcAdd(s, row.id, qty, data(), PC_CAP) then return false, "pc_full" end
    B.remove(s, row.id, qty, data(), row.slot)
    return true
  end

  function Inv.toss(s, pcIdx, qty)
    local B = Bag()
    local row = Inv.pcRows(s)[pcIdx]
    if not (B and row) then return false, "gone" end
    if row.important then return false, "important" end
    B.pcRemove(s, row.id, math.max(1, math.min(qty or 1, row.qty)), data(), row.slot)
    return true
  end

  -- a stable reorder of an id list by name (or pocket, then name)
  local function sortIds(order, how)
    local rank = {}
    for i, p in ipairs(ORDER) do rank[p] = i end
    local keyed = {}
    for i, id in ipairs(order) do
      keyed[i] = { id = id, i = i, name = Gd.itemName(id):lower(), pocket = rank[pocketOf(id)] or 9,
                   num = tonumber(Gd.item(id) and Gd.item(id).index) or 999 }
    end
    table.sort(keyed, function(a, b)
      if how == "pocket" and a.pocket ~= b.pocket then return a.pocket < b.pocket end
      if how == "type" and a.num ~= b.num then return a.num < b.num end
      if a.name ~= b.name then return a.name < b.name end
      return a.i < b.i
    end)
    for i, k in ipairs(keyed) do order[i] = k.id end
  end

  function Inv.sort(s, how)
    local B = Bag()
    if not (s and B) then return false end
    local order = B.pcOrder(s, data())
    sortIds(order, how)
    return true
  end

  -- a Bag pocket reordered as the game's SELECT moves its slots: within that pocket's places only
  function Inv.sortPocket(s, pocket, how)
    local B = Bag()
    if not (s and B) then return false, "gone" end
    if gen == 2 and pocket == "TM_CASE" then return false, "fixed" end
    local order = B.order(s, data())
    local slots, ids = {}, {}
    for i, id in ipairs(order) do
      if not isBadge(id) and (gen == 1 or pocketOf(id) == pocket) then
        slots[#slots + 1], ids[#ids + 1] = i, id
      end
    end
    sortIds(ids, how)
    for i, at in ipairs(slots) do order[at] = ids[i] end
    return true
  end

  Inv.GAME_POCKET = GAME_POCKET
  return Inv
end
