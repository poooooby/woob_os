-- The item model behind the Items app: the PC's item storage and the Bag, through the engine's own
-- Storage (src.core.game3.storage) and Bag (src.core.game3.bag), so the session changes exactly as
-- the game's own screens change it. Rows are made here when something changes (never per frame).
--
--   Inv = inventory(engine)      engine(name) -> an engine module or nil (kept by the caller)
--   Inv.pockets(s) -> { { id = "ITEMS", label = "Items" }, ... } (the game's order; containers
--       only when they hold something)
--   Inv.pcRows(s) / Inv.bagRows(s, pocket) -> rows { id, qty, name, desc, showQty, important }
--   Inv.pcCount(s) -> used, capacity
--   Inv.withdraw(s, pcIdx, qty) / Inv.deposit(s, pocket, bagIdx, qty) / Inv.toss(s, pcIdx, qty)
--       -> true | false, reason ("bag_full" | "pc_full" | "stack_full" | "important" | "gone")
--   Inv.sort(s, how)  how: "name" | "pocket" (a stable reorder of the PC's list)
--   Inv.REASON[reason] -> the words for a refusal

return function(engine)
  local Inv = {}

  Inv.REASON = {
    bag_full = "No room in the Bag.",
    pc_full = "The PC is full.",
    stack_full = "That stack is full.",
    important = "Important items stay in the Bag.",
    gone = "That item isn't there any more.",
  }
  local LABELS = { ITEMS = "Items", KEY_ITEMS = "Key Items", POKE_BALLS = "Poké Balls", TM_CASE = "TMs & HMs",
                   BERRY_POUCH = "Berries" }
  -- (pockets whose quantities the game doesn't show)
  local NO_QTY = { KEY_ITEMS = true, TM_CASE = true }

  local function mods()
    return engine("src.core.game3.storage"), engine("src.core.game3.bag"), engine("src.core.game3.items_data")
  end
  local function ready(s)
    local Storage, Bag, ItemsData = mods()
    if not (s and Storage and Bag and ItemsData) then return nil end
    if ItemsData.ensureModel then pcall(ItemsData.ensureModel, s) end
    s.bag = s.bag or Bag.new()
    return Storage, Bag, ItemsData
  end

  local function profileBag(s)
    local Profile = engine("src.core.game3.profile")
    local ok, row = pcall(function() return Profile.forSession(s) end)
    return ok and row and row.bag or nil
  end

  function Inv.pockets(s)
    local out = {}
    local Storage, Bag = ready(s)
    local pb = profileBag(s)
    local order = pb and pb.pockets or { "ITEMS", "KEY_ITEMS", "POKE_BALLS", "TM_CASE", "BERRY_POUCH" }
    local visible = {}
    for _, p in ipairs(pb and pb.visible or order) do visible[p] = true end
    for _, p in ipairs(order) do
      local show = visible[p]
      if not show and Bag then
        local ok, rows = pcall(Bag.listPocket, s.bag, p)
        show = ok and rows and #rows > 0
      end
      if show then out[#out + 1] = { id = p, label = LABELS[p] or p } end
    end
    return out
  end

  local function important(info)
    return info ~= nil and (tonumber(info.importance) or 0) ~= 0
  end
  local function rowFor(ItemsData, id, qty, pocket)
    local ok, info = pcall(ItemsData.info, id)
    info = ok and info or nil
    pocket = pocket or (info and info.pocket) or "ITEMS"
    local imp = important(info)
    local okH, hm = pcall(ItemsData.isHm or function() return false end, id)
    return {
      id = id, qty = qty, pocket = pocket,
      name = info and info.name or tostring(id),
      desc = ((info and info.description) or ""):gsub("\\n", " "):gsub("\\p", " "):gsub("\n", " "),
      important = imp,
      showQty = not (imp or NO_QTY[pocket] or (okH and hm)),
    }
  end

  function Inv.pcRows(s)
    local out = {}
    local Storage, _, ItemsData = ready(s)
    if not Storage then return out end
    for _, e in ipairs(Storage.ensure(s).items) do
      out[#out + 1] = rowFor(ItemsData, e.id, tonumber(e.qty) or 0)
    end
    return out
  end

  function Inv.bagRows(s, pocket)
    local out = {}
    local _, Bag, ItemsData = ready(s)
    if not Bag then return out end
    local ok, rows = pcall(Bag.listPocket, s.bag, pocket)
    if not ok or not rows then return out end
    for _, row in ipairs(rows) do out[#out + 1] = rowFor(ItemsData, row.id, row.qty, pocket) end
    return out
  end

  function Inv.pcCount(s)
    local Storage = ready(s)
    if not Storage then return 0, 0 end
    local ok, cap = pcall(Storage.pcItemsCount, s)
    return #Storage.ensure(s).items, ok and tonumber(cap) or 0
  end

  local function same(a, b, ItemsData)
    if a == b then return true end
    local na = ItemsData.toNumericId and ItemsData.toNumericId(a) or tonumber(a)
    local nb = ItemsData.toNumericId and ItemsData.toNumericId(b) or tonumber(b)
    return na ~= nil and na == nb
  end

  function Inv.withdraw(s, pcIdx, qty)
    local Storage = ready(s)
    if not Storage then return false, "gone" end
    local ok, err = Storage.withdrawItem(s, pcIdx, qty)
    if ok then return true end
    if err == "bag_full" or err == "no_bag" then return false, "bag_full" end
    return false, "gone"
  end

  function Inv.deposit(s, pocket, bagIdx, qty)
    local Storage, Bag, ItemsData = ready(s)
    if not Storage then return false, "gone" end
    local rows = Bag.listPocket(s.bag, pocket)
    local row = rows and rows[bagIdx]
    if not row then return false, "gone" end
    if important(row.info) then return false, "important" end
    local id = row.id
    local ok, err = Storage.depositItem(s, pocket, bagIdx, qty)
    if not ok then
      if err == "pc_items_full" then return false, "pc_full" end
      if err == "pc_item_stack_full" then return false, "stack_full" end
      return false, "gone"
    end
    -- (the last one out of the Bag: it can't stay the registered item)
    if s.registeredItem and same(s.registeredItem, id, ItemsData) and (Bag.get(s.bag, id) or 0) <= 0 then
      s.registeredItem = 0
    end
    return true
  end

  function Inv.toss(s, pcIdx, qty)
    local Storage, _, ItemsData = ready(s)
    if not Storage then return false, "gone" end
    local e = Storage.ensure(s).items[pcIdx]
    if not e then return false, "gone" end
    local ok, info = pcall(ItemsData.info, e.id)
    if ok and important(info) then return false, "important" end
    if not Storage.tossItem(s, pcIdx, qty) then return false, "gone" end
    return true
  end

  -- a stable reorder of the PC's list: by name, or by pocket (the game's order) then name
  function Inv.sort(s, how)
    local Storage, _, ItemsData = ready(s)
    if not Storage then return false end
    local items = Storage.ensure(s).items
    local rank = {}
    local pb = profileBag(s)
    for i, p in ipairs(pb and pb.pockets or {}) do rank[p] = i end
    local keyed = {}
    for i, e in ipairs(items) do
      local ok, info = pcall(ItemsData.info, e.id)
      info = ok and info or nil
      keyed[i] = { e = e, i = i, name = tostring(info and info.name or e.id):lower(),
                   pocket = rank[info and info.pocket or "ITEMS"] or 99 }
    end
    table.sort(keyed, function(a, b)
      if how == "pocket" and a.pocket ~= b.pocket then return a.pocket < b.pocket end
      if a.name ~= b.name then return a.name < b.name end
      return a.i < b.i
    end)
    for i, k in ipairs(keyed) do items[i] = k.e end
    return true
  end

  return Inv
end
