-- The mail model behind the Mail app, on the engine's own mail pool (src.core.game3.mail): 16
-- records, slots 1-6 held by the party (mon.mail = 0..5), slots 7-16 the PC's mailbox. A record:
-- { words[9], playerName, trainerId, species (mail species), itemId (121..132; 0 = empty) }.
-- Rows are made here when something changes (never per frame).
--
--   Mb = mailbox(engine)
--   Mb.inbox(s) -> rows (the PC's mail, first to last) ; Mb.held(s) -> rows (the party's)
--       row = { rec, slot (pool index), mon, monName, title, from, lines, preview, species, design }
--   Mb.toBag(s, row) ; Mb.give(s, row, mon) ; Mb.take(s, row)
--       -> true | false, reason ("bag_full" | "holding" | "box_full" | "gone"; the words are
--       lang/*.lua's "reason.mail.<reason>")
--   Mb.party(s) -> { { mon, name, species, item (its name or nil), held = bool }, ... }

return function(engine)
  local Mb = {}
  local PARTY, COUNT = 6, 16

  local function Mail() return engine("src.core.game3.mail") end

  local function itemName(id)
    local ItemsData = engine("src.core.game3.items_data")
    local ok, name = pcall(ItemsData.displayName, id)
    return ok and name or "Mail"
  end
  local function monName(mon)
    local P = engine("src.core.game3.pokemon")
    local ok, name = pcall(P.displayMonName, mon)
    if ok and type(name) == "string" and name ~= "" then return name end
    ok, name = pcall(P.name, mon.species or mon.speciesId)
    return ok and name or "?"
  end
  local function speciesOf(mon) return tonumber(mon and (mon.species or mon.speciesId)) or 0 end

  -- the message's lines: Emerald's own layout per stationery, else three lines of three words
  local function linesOf(s, rec)
    local out = {}
    local Profile = engine("src.core.game3.profile")
    local okF, fam = pcall(Profile.family, s)
    local GV = engine("src.core.GameVersion")
    local game = GV and tostring(GV.current or "") or ""
    if okF and fam == "rse" and game:find("emerald", 1, true) then
      local MailRead = engine("src.ui.game3.rse.mail")
      local ok, design = pcall(MailRead.designOf, rec)
      local okL, got = false, nil
      if ok then okL, got = pcall(MailRead.lines, rec, design) end
      if okL and type(got) == "table" then
        for _, l in ipairs(got) do if l ~= "" then out[#out + 1] = l end end
        return out
      end
    end
    local Ec = engine("src.core.game3.easy_chat_text")
    local ok, text = pcall(Ec.phrase, rec.words, 3, 3)
    if ok and type(text) == "string" then
      for l in text:gmatch("[^\n]+") do out[#out + 1] = l end
    end
    return out
  end

  local function rowOf(s, rec, slot, mon)
    local M = Mail()
    local sp = speciesOf(nil)
    local okS, species = pcall(M.mailSpeciesToSpecies, rec.species)
    if okS then sp = tonumber(species) or 0 end
    local lines = linesOf(s, rec)
    local name = tostring(rec.playerName or "")
    return {
      rec = rec, slot = slot, mon = mon, monName = mon and monName(mon) or nil,
      title = itemName(rec.itemId), from = name ~= "" and name or "?",
      lines = lines, preview = lines[1] or "", species = sp,
      design = (tonumber(rec.itemId) or 121) - 121,
    }
  end

  function Mb.inbox(s)
    local out = {}
    local M = Mail()
    local pool = M and s and M.pool(s)
    if not pool then return out end
    Mb.compact(s)
    for i = PARTY + 1, COUNT do
      if not M.isEmpty(pool[i]) then out[#out + 1] = rowOf(s, pool[i], i) end
    end
    return out
  end

  function Mb.held(s)
    local out = {}
    local M = Mail()
    local pool = M and s and M.pool(s)
    if not pool then return out end
    for _, mon in ipairs(s.party or {}) do
      if M.monHasMail(mon) then
        local rec = M.slot(s, mon.mail)
        if rec and not M.isEmpty(rec) then out[#out + 1] = rowOf(s, rec, tonumber(mon.mail) + 1, mon) end
      end
    end
    return out
  end

  -- the PC's mail first to last, no gaps
  function Mb.compact(s)
    local M = Mail()
    local pool = M and s and M.pool(s)
    if not pool then return end
    local n = PARTY
    for i = PARTY + 1, COUNT do
      if not M.isEmpty(pool[i]) then
        n = n + 1
        if n ~= i then pool[n], pool[i] = pool[i], pool[n] end
      end
    end
  end

  local function live(s, row)
    local M = Mail()
    local pool = M and s and M.pool(s)
    return pool and row and pool[row.slot] == row.rec and not M.isEmpty(row.rec)
  end

  -- to the Bag: the stationery back as an item, the message lost (as the game does)
  function Mb.toBag(s, row)
    if not live(s, row) then return false, "gone" end
    local Bag = engine("src.core.game3.bag")
    local ItemsData = engine("src.core.game3.items_data")
    if ItemsData and ItemsData.ensureModel then pcall(ItemsData.ensureModel, s) end
    local id = tonumber(row.rec.itemId)
    if not (Bag and s.bag and Bag.canAdd(s.bag, id, 1) and Bag.add(s.bag, id, 1)) then return false, "bag_full" end
    Mail().clear(row.rec)
    Mb.compact(s)
    return true
  end

  function Mb.give(s, row, mon)
    if not live(s, row) then return false, "gone" end
    if type(mon) ~= "table" then return false, "gone" end
    if (tonumber(mon.item or mon.heldItem) or 0) ~= 0 then return false, "holding" end
    local M = Mail()
    if M.giveMailToMon2(s, mon, M.copy(row.rec)) == M.MAIL_NONE then return false, "gone" end
    M.clear(row.rec)
    Mb.compact(s)
    return true
  end

  -- a held mail into the PC's mailbox (the Pokémon lets go of it)
  function Mb.take(s, row)
    if not (row and row.mon and live(s, row)) then return false, "gone" end
    local M = Mail()
    local pool = M.pool(s)
    for i = PARTY + 1, COUNT do
      if M.isEmpty(pool[i]) then
        pool[i] = M.copy(row.rec)
        M.takeMailFromMon(s, row.mon)
        return true
      end
    end
    return false, "box_full"
  end

  function Mb.party(s)
    local out = {}
    for _, mon in ipairs(s and s.party or {}) do
      local item = tonumber(mon.item or mon.heldItem) or 0
      if speciesOf(mon) > 0 then
        out[#out + 1] = { mon = mon, name = monName(mon), species = speciesOf(mon),
                          item = item ~= 0 and itemName(item) or nil, held = item ~= 0 }
      end
    end
    return out
  end

  return Mb
end
