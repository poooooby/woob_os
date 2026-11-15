-- The Mail app's model on Gold / Silver / Crystal: the PC's mailbox (ten letters) and the letters the party
-- holds, through the engine's own mail (src/core/gen2/Mail.lua: save.mail.box, save.mail.party[slot]; a held
-- letter's stationery is the Pokémon's item). The same interface as src/mailbox.lua. Red / Blue / Yellow
-- have no mail: the app isn't there.
--
--   Mb = mail(host, Gd)   (the interface: src/mailbox.lua's header)

return function(H, Gd)
  local engine = H.engine
  local Mb = {}
  local function Mail() return engine("src.core.gen2.Mail") end
  local function Bag() return engine("src.inventory.Bag") end

  -- (the design: the stationery's place in the game's list, 0 .. 9, for the window's tint)
  local DESIGN = {}
  local function design(id)
    local M = Mail()
    if M and M.ITEMS and not next(DESIGN) then
      for i, it in ipairs(M.ITEMS) do DESIGN[it] = i - 1 end
    end
    return DESIGN[id] or 0
  end
  -- (the message's lines, split here: the engine's own reader tells the game a letter was read)
  local function linesOf(msg)
    local out = {}
    for l in (tostring(msg or "") .. "\n"):gmatch("([^\n]*)\n") do
      l = l:gsub("%s+$", "")
      if l ~= "" then out[#out + 1] = l end
    end
    return out
  end
  local function rowOf(entry, slot, mon)
    local lines = linesOf(entry.message)
    local author = tostring(entry.author or "")
    return {
      rec = entry, slot = slot, mon = mon, monName = mon and Gd.monName(mon) or nil,
      title = Gd.itemName(entry.type), from = author ~= "" and author or "?",
      lines = lines, preview = lines[1] or "", species = entry.species, design = design(entry.type),
    }
  end

  function Mb.inbox(s)
    local out = {}
    local M = Mail()
    if not (M and s) then return out end
    for i, e in ipairs(M.state(s).box) do out[#out + 1] = rowOf(e, i) end
    return out
  end
  function Mb.held(s)
    local out = {}
    local M = Mail()
    if not (M and s) then return out end
    local party = M.state(s).party
    for slot, mon in ipairs(s.party or {}) do
      if M.monHoldsMail(mon) then
        local e = party[slot] or M.entry(mon.item, "", "", 0, mon.species)
        out[#out + 1] = rowOf(e, slot, mon)
      end
    end
    return out
  end

  local function inMailbox(s, row)
    local M = Mail()
    local box = M and s and M.state(s).box
    return box ~= nil and row ~= nil and not row.mon and box[row.slot] == row.rec
  end

  -- to the Bag: the stationery back as an item, the letter gone (as the game's mailbox does)
  function Mb.toBag(s, row)
    if not inMailbox(s, row) then return false, "gone" end
    local B = Bag()
    if not (B and B.add(s, row.rec.type, 1, Gd.data())) then return false, "bag_full" end
    Mail().deleteFromPc(s, row.slot)
    return true
  end

  function Mb.give(s, row, mon)
    if not inMailbox(s, row) then return false, "gone" end
    if type(mon) ~= "table" then return false, "gone" end
    if mon.item and mon.item ~= "" then return false, "holding" end
    local slot
    for i, m in ipairs(s.party or {}) do if m == mon then slot = i end end
    if not slot or Gd.isEgg(mon) then return false, "gone" end
    if not Mail().moveFromPcToParty(s, row.slot, slot) then return false, "gone" end
    return true
  end

  -- a held letter into the PC's mailbox (the Pokémon lets go of it)
  function Mb.take(s, row)
    if not (row and row.mon) then return false, "gone" end
    local M = Mail()
    if M.mailboxFull(s) then return false, "box_full" end
    if not M.sendToPc(s, row.slot) then return false, "gone" end
    return true
  end

  function Mb.party(s)
    local out = {}
    for _, mon in ipairs(s and s.party or {}) do
      local item = mon.item
      out[#out + 1] = { mon = mon, name = Gd.monName(mon), species = mon.species,
                        item = item and item ~= "" and Gd.itemName(item) or nil, held = item ~= nil and item ~= "" }
    end
    return out
  end

  return Mb
end
