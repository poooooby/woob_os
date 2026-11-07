-- The GTS app's model: the Global Trade Station and Wonder Trade, with trainers from around the world
-- (made up: names, home regions, IDs). Their Pokémon come with their own Original Trainer, so the
-- game treats them as traded, as a real trade would (more EXP; a high level may not obey yet).
--
-- Wonder Trade: one of yours goes, a stranger's comes back at once (any tier, legends rarely).
-- GTS: post one of yours asking for a species and level; a stranger answers in real time when the
-- ask is fair (never when it's absurd); collect it when it's traded. Or browse the strangers' own
-- listings (ten each half hour, from the save's seed) and give them what they ask.
-- Kept in the save (mod.save "gts"): the deposit (the Pokémon itself while it's posted), the
-- listings already traded, the last trades.
--
--   Gx = gts(engine, deps)  deps: save (mod.save), now() -> epoch seconds, rng(n) -> 1..n,
--                           seed(s), pools() / tierOf(sp) / minLevel(sp) (R-Bay's), frlg() -> bool,
--                           bx (src/boxes.lua), notify(kind, { name, sp, who }) ("gts": a
--                           deposit traded)
--   Gx.REGIONS, Gx.LEVELS (request ranges)
--   Gx.canSend(s, addr) -> true | false, reason        addr: Bx.addr(...)
--   Gx.candidates(s, box, filter) -> { addr ... }       (the party, then that box)
--   Gx.wonder(s, addr) -> true, recv, stranger | false, reason
--   Gx.deposit(s, addr, species, levels, now) / Gx.withdraw(s) / Gx.settle(s, now) / Gx.collect(s)
--   Gx.posted() -> the deposit { mon, species, levels, at, matchAt, received, stranger } | nil
--   Gx.offers(s, now) -> the strangers' listings ; Gx.matching(s, L) -> { addr } ; Gx.accept(s, L, addr)
--   Gx.evolveTarget(s, mon) -> species | nil (a trade evolution) ; Gx.name(sp) ; Gx.seenSpecies(s)
--   Gx.waiting() -> 1 while a traded deposit waits to be collected
--   reasons: "last" | "egg" | "national" | "mail" | "invalid" | "gone" | "busy" | "traded" |
--       "no_room" | "wrong" (lang/*.lua "reason.gts.<reason>")

local floor, max, min = math.floor, math.max, math.min
local M31 = 2147483647

local REGIONS = { "kanto", "johto", "hoenn", "sinnoh", "unova", "kalos", "alola", "galar", "paldea" }
-- the strangers: a name (seven letters at most, as the game keeps them), a home region, M / F
local STRANGERS = {
  { "Yuki", 2, 1 }, { "Pierre", 6, 0 }, { "Hans", 8, 0 }, { "Lucia", 9, 1 }, { "Giulia", 6, 1 }, { "Mateus", 9, 0 },
  { "Jin", 2, 0 }, { "Amara", 7, 1 }, { "Sven", 4, 0 }, { "Noor", 3, 1 }, { "Kofi", 5, 0 }, { "Mei", 1, 1 },
  { "Ravi", 3, 0 }, { "Ines", 9, 1 }, { "Tomas", 4, 0 }, { "Aiko", 1, 1 }, { "Liam", 5, 0 }, { "Sofia", 6, 1 },
  { "Diego", 7, 0 }, { "Elena", 8, 1 }, { "Kenji", 2, 0 }, { "Maya", 3, 1 }, { "Omar", 5, 0 }, { "Zara", 8, 1 },
  { "Felix", 4, 0 }, { "Nina", 6, 1 }, { "Arjun", 7, 0 }, { "Lea", 6, 1 }, { "Hugo", 8, 0 }, { "Yara", 9, 1 },
  { "Ivan", 4, 0 }, { "Rin", 1, 1 }, { "Theo", 5, 0 }, { "Ada", 7, 1 }, { "Kai", 3, 0 }, { "Luna", 2, 1 },
  { "Mila", 5, 1 }, { "Oscar", 8, 0 }, { "Pia", 4, 1 }, { "Sami", 7, 0 },
}
-- what a stranger's Pokémon might hold (a quarter of the time)
local HELD = { 139, 142, 141, 13, 68, 110, 94, 95, 96, 97, 98 }
-- Wonder Trade's tiers (weights of 1000)
local WEIGHTS = { { "common", 450 }, { "uncommon", 300 }, { "rare", 150 }, { "prized", 80 }, { "legendary", 15 }, { "mythical", 5 } }
local RANK = { common = 1, uncommon = 2, rare = 3, prized = 4, legendary = 5, mythical = 6 }
-- the level ranges a request may ask for (1: any)
local LEVELS = { { 1, 100 }, { 1, 10 }, { 11, 20 }, { 21, 30 }, { 31, 40 }, { 41, 50 }, { 51, 60 }, { 61, 70 },
                 { 71, 80 }, { 81, 90 }, { 91, 100 } }
local OFFERS, WINDOW = 10, 1800
local KEEP = 20

-- the listings' dice (Park-Miller on a table)
local function nextRand(st)
  st.x = (st.x * 48271) % M31
  return st.x
end

return function(engine, deps)
  deps = deps or {}
  local Gx = { REGIONS = REGIONS, LEVELS = LEVELS, STRANGERS = STRANGERS, store = deps.save,
               now = deps.now or os.time, rng = deps.rng }

  local function P() return engine("src.core.game3.pokemon") end
  local function Trade() return engine("src.core.game3.scripting.natives_trade") end
  local function Storage() return engine("src.core.game3.storage") end
  local Bx = deps.bx

  local function roll(n)
    if Gx.rng then return Gx.rng(n) end
    local R = love and love.math and love.math.random
    return R and R(1, n) or math.random(1, n)
  end

  -- ------- the kept part

  local loose
  local function data()
    local store = Gx.store
    local d = store and store:get("gts") or loose
    if type(d) ~= "table" then
      d = { log = {}, done = {} }
      if store then store:set("gts", d) else loose = d end
    end
    d.log, d.done = d.log or {}, d.done or {}
    return d
  end
  local function save(d) if Gx.store then Gx.store:set("gts", d) end end
  function Gx.posted() return data().deposit end
  function Gx.log() return data().log end
  function Gx.waiting()
    local dep = data().deposit
    return dep and dep.received and 1 or 0
  end
  local function logTrade(d, kind, sent, recv, stranger)
    table.insert(d.log, 1, { kind = kind, sp = tonumber(recv.species or recv.speciesId), level = recv.level,
                             sent = sent and tonumber(sent.species or sent.speciesId) or nil, who = stranger and stranger[1],
                             region = stranger and stranger[2] })
    while #d.log > KEEP do d.log[#d.log] = nil end
  end

  -- ------- the rules: what may go, what may come

  local function isEgg(mon)
    local Pk = P()
    local ok, egg = pcall(Pk and Pk.isEgg or error, mon)
    return ok and egg == true or (mon and (mon.isEgg or mon.egg)) and true or false
  end
  local function hasMail(mon)
    local Mail = engine("src.core.game3.mail")
    local ok, has = pcall(Mail and Mail.monHasMail or error, mon)
    return ok and has == true
  end
  local function national(s)
    local Dex = engine("src.core.game3.pokedex_data")
    local ok, yes = pcall(Dex and Dex.isNationalUnlocked or error, s, s and s.dex)
    return ok and yes == true
  end
  -- (FireRed / LeafGreen without the National Dex trade only Kanto's 151, both ways)
  function Gx.allowed(s, sp)
    if not (deps.frlg and deps.frlg()) or national(s) then return true end
    local Pk = P()
    local ok, nat = pcall(Pk and Pk.national or error, sp)
    return ok and nat and nat <= 151 or false
  end
  local STANDIN = { species = 1, hp = 1 }
  local CODES = { [1] = "last", [2] = "national", [3] = "egg", [4] = "invalid", [5] = "egg" }
  function Gx.canSend(s, addr)
    local mon = Bx.get(s, addr)
    if not mon then return false, "gone" end
    if isEgg(mon) then return false, "egg" end
    if hasMail(mon) then return false, "mail" end
    local Tr = Trade()
    local party, idx = { mon, STANDIN }, 0
    if addr.loc == "party" then
      party, idx = Bx.party(s), addr.slot - 1
      -- (and a Pokémon that can still battle stays)
      local other = false
      for i, m in ipairs(party) do
        if i ~= addr.slot and m and not isEgg(m) and (tonumber(m.hp) or 1) > 0 then other = true end
      end
      if not other then return false, "last" end
    end
    if Tr and Tr.canTradeSelectedMon then
      local frlg = deps.frlg and deps.frlg()
      local ok, code = pcall(Tr.canTradeSelectedMon, party, idx, { session = s, nationalDex = (not frlg) or nil })
      if ok and code and code ~= 0 then return false, CODES[code] or "invalid" end
    end
    return true
  end
  -- the party, then box b: the Pokémon there (filter(addr, mon) -> keep?)
  function Gx.candidates(s, b, filter)
    local out = {}
    for i = 1, 6 do
      local addr = Bx.addr("party", i)
      local mon = Bx.get(s, addr)
      if mon and (not filter or filter(addr, mon)) then out[#out + 1] = addr end
    end
    if b then
      for i = 1, Bx.SLOTS do
        local addr = Bx.addr("box", i, b)
        local mon = Bx.get(s, addr)
        if mon and (not filter or filter(addr, mon)) then out[#out + 1] = addr end
      end
    end
    return out
  end

  -- ------- a stranger and their Pokémon

  local function playerPacked(s)
    return (tonumber(s and (s.trainerId or s.id or s.playerId)) or 0) % 65536 + (tonumber(s and s.secretId) or 0) % 65536 * 65536
  end
  local function stranger(s)
    local who = STRANGERS[roll(#STRANGERS)]
    local id
    repeat id = (roll(65535) - 1) + (roll(65535) - 1) * 65536 until id ~= playerPacked(s)
    return who, id
  end
  local function levelOf(level, sp)
    local lo = deps.minLevel and deps.minLevel(sp) or 0
    return max(2, min(100, max(level, lo)))
  end
  -- the stranger's Pokémon: made on a scratch session (the real party and Pokédex untouched), then
  -- theirs: name, ID, gender, met in a trade, perhaps holding something
  function Gx.make(s, sp, level, who, id)
    local Party, Pk = engine("src.core.game3.party"), P()
    if not (Party and Pk) then return nil end
    local tid, sid = id % 65536, floor(id / 65536)
    local scratch = { party = {}, name = who[1], trainerId = tid, secretId = sid,
                      dex = { seen = {}, owned = {}, caught = {} }, gender = who[3] }
    local ok, given, _, mon = pcall(Party.giveMon, scratch, sp, level, nil, nil)
    if not (ok and given and type(mon) == "table") then return nil end
    mon.ot, mon.otName, mon.otId, mon.otSecretId, mon.otGender = who[1], who[1], tid, sid, who[3]
    mon.metLocation = 0xFE
    mon.language = 2
    if roll(4) == 1 then
      local item = HELD[roll(#HELD)]
      local I = engine("src.core.game3.items_data")
      local okI, info = pcall(I and I.info or error, item)
      if okI and info and info.name then mon.item, mon.heldItem = item, item end
    end
    mon.hp = nil
    pcall(Pk.applyStats, mon)
    mon.hp = mon.maxHp
    return mon
  end

  -- one Pokémon of the player's out, another in, where it was: the party's slot (the game's own
  -- trade swap: mail, friendship, the Pokédex) or the box's cell (healed, the Pokédex too)
  function Gx.swap(s, addr, recv, who)
    local Tr = Trade()
    local sent
    if addr.loc == "party" then
      local ok, got = pcall(Tr.tradeMons, s, addr.slot - 1, recv)
      sent = ok and got or nil
    else
      local St = Storage()
      local box = St and St.ensure(s).boxes[addr.boxId]
      sent = box and box.mons[addr.slot]
      if sent then
        box.mons[addr.slot] = recv
        recv.friendship, recv.happiness = 70, 70
        recv.status = nil
        local sp = tonumber(recv.species or recv.speciesId)
        s.dex = s.dex or { seen = {}, owned = {}, caught = {} }
        s.dex.seen = s.dex.seen or {}
        if sp then
          s.dex.seen[sp] = true
          local Dex = engine("src.core.game3.dex")
          pcall(Dex and Dex.handleSetPokedexFlag or error, s.dex, sp, true, recv.personality)
        end
      end
    end
    if sent and Tr and Tr.noteLinkTrade then pcall(Tr.noteLinkTrade, s, sent, recv, who and who[1]) end
    return sent
  end

  -- a species of a tier, one the player may receive
  local function pickSpecies(s, tier)
    local pools = deps.pools and deps.pools() or {}
    local pool = pools[tier] or {}
    for _ = 1, 24 do
      local e = pool[roll(max(1, #pool))]
      if e and Gx.allowed(s, e.sp) then return e.sp end
    end
    local common = pools.common or {}
    for _ = 1, 48 do
      local e = common[roll(max(1, #common))]
      if e and Gx.allowed(s, e.sp) then return e.sp end
    end
    return nil
  end
  local function pickTier()
    local r = roll(1000)
    for _, w in ipairs(WEIGHTS) do
      r = r - w[2]
      if r <= 0 then return w[1] end
    end
    return "common"
  end
  Gx.pickTier = pickTier

  -- ------- Wonder Trade

  function Gx.wonder(s, addr)
    local ok, why = Gx.canSend(s, addr)
    if not ok then return false, why end
    local mine = Bx.get(s, addr)
    local tier = pickTier()
    local sp = pickSpecies(s, tier)
    if not sp then return false, "invalid" end
    local who, id = stranger(s)
    local level = levelOf((tonumber(mine.level) or 5) + roll(11) - 6, sp)
    local recv = Gx.make(s, sp, level, who, id)
    if not recv then return false, "invalid" end
    local sent = Gx.swap(s, addr, recv, who)
    if not sent then return false, "gone" end
    local d = data()
    logTrade(d, "wonder", sent, recv, who)
    save(d)
    return true, recv, who, deps.tierOf and deps.tierOf(sp) or "common", sent
  end

  -- ------- the GTS: your deposit

  local function tierRank(sp) return RANK[deps.tierOf and deps.tierOf(sp) or "uncommon"] or 2 end
  function Gx.deposit(s, addr, species, levels, now)
    now = now or Gx.now()
    local d = data()
    if d.deposit then return false, "busy" end
    local ok, why = Gx.canSend(s, addr)
    if not ok then return false, why end
    local St = Storage()
    local okT, mon = pcall(St.pickUpMon, s, addr.loc, addr.slot, addr.boxId)
    if not (okT and type(mon) == "table") then return false, "gone" end
    -- (how fair the ask is: a rarer species, a higher level, take longer; an absurd one never comes)
    local range = LEVELS[levels] or LEVELS[1]
    local fair = tierRank(species) - tierRank(tonumber(mon.species or mon.speciesId))
    if levels ~= 1 and range[1] > (tonumber(mon.level) or 1) + 10 then fair = fair + 1 end
    local matchAt = false
    if fair <= 0 then matchAt = now + 300 + roll(3300)
    elseif fair == 1 then matchAt = now + 3600 + roll(10800)
    elseif fair == 2 then matchAt = roll(10) <= 3 and (now + roll(21600)) or false end
    d.deposit = { mon = mon, species = species, levels = levels, at = now, matchAt = matchAt }
    save(d)
    return true
  end
  -- a Pokémon to the player: the party, else the PC -> "party" | "pc" | nil
  local function place(s, mon)
    local party = Bx.party(s)
    if #party < 6 then
      party[#party + 1] = mon
      return "party"
    end
    local St = Storage()
    local ok, sent = pcall(St.sendMonToPC, s, mon)
    return ok and sent and "pc" or nil
  end
  function Gx.withdraw(s)
    local d = data()
    local dep = d.deposit
    if not dep then return false, "gone" end
    if dep.received then return false, "traded" end
    local where = place(s, dep.mon)
    if not where then return false, "no_room" end
    d.deposit = nil
    save(d)
    return true, dep.mon, where
  end
  function Gx.settle(s, now)
    now = now or Gx.now()
    local d = data()
    local dep = d.deposit
    if not (s and dep) or dep.received or not dep.matchAt or now < dep.matchAt then return false end
    local range = LEVELS[dep.levels] or LEVELS[1]
    local base = dep.levels == 1 and ((tonumber(dep.mon.level) or 5) + roll(11) - 6) or (range[1] + roll(range[2] - range[1] + 1) - 1)
    local who, id = stranger(s)
    local recv = Gx.make(s, dep.species, levelOf(base, dep.species), who, id)
    if not recv then return false end
    dep.received, dep.stranger = recv, { who[1], who[2], who[3] }
    save(d)
    if deps.notify then
      local sp = tonumber(recv.species or recv.speciesId)
      pcall(deps.notify, "gts", { name = Gx.name(sp), sp = sp, who = who[1] })
    end
    return true
  end
  function Gx.collect(s)
    local d = data()
    local dep = d.deposit
    if not (dep and dep.received) then return false, "gone" end
    local recv = dep.received
    local where = place(s, recv)
    if not where then return false, "no_room" end
    recv.friendship, recv.happiness = 70, 70
    local sp = tonumber(recv.species or recv.speciesId)
    s.dex = s.dex or { seen = {}, owned = {}, caught = {} }
    s.dex.seen = s.dex.seen or {}
    if sp then
      s.dex.seen[sp] = true
      local Dex = engine("src.core.game3.dex")
      pcall(Dex and Dex.handleSetPokedexFlag or error, s.dex, sp, true, recv.personality)
    end
    local Tr = Trade()
    if Tr and Tr.noteLinkTrade then pcall(Tr.noteLinkTrade, s, dep.mon, recv, dep.stranger[1]) end
    logTrade(d, "gts", dep.mon, recv, dep.stranger)
    d.deposit = nil
    save(d)
    return true, recv, dep.stranger, where
  end

  -- ------- the GTS: the strangers' listings

  -- the species the player has (the party and every box): asked for by some listings
  local function owned(s)
    local seen, out = {}, {}
    local function add(mon)
      if mon and not isEgg(mon) then
        local sp = tonumber(mon.species or mon.speciesId)
        if sp and not seen[sp] then seen[sp], out[#out + 1] = true, sp end
      end
    end
    for _, m in ipairs(Bx.party(s)) do add(m) end
    for b = 1, Bx.BOXES do for i = 1, Bx.SLOTS do add(Bx.get(s, Bx.addr("box", i, b))) end end
    table.sort(out)
    return out
  end
  local cache = { wnd = nil, sig = nil, list = nil }
  local dice = { x = 1 }
  local function droll(n) return nextRand(dice) % n + 1 end
  function Gx.offers(s, now)
    now = now or Gx.now()
    local wnd = floor(now / WINDOW)
    local have = owned(s)
    local sig = table.concat(have, ",")
    local d = data()
    if cache.wnd ~= wnd or cache.sig ~= sig then
      local seed = tonumber(deps.seed and deps.seed(s)) or 1
      dice.x = (seed * 7919 + wnd * 104729) % M31
      if dice.x == 0 then dice.x = 1 end
      for _ = 1, 3 do nextRand(dice) end
      local saved = Gx.rng
      Gx.rng = droll
      local list = {}
      for i = 1, OFFERS do
        local L = { key = wnd .. ":" .. i }
        L.who = STRANGERS[droll(#STRANGERS)]
        L.tier = pickTier()
        L.sp = pickSpecies(s, L.tier)
        L.level = levelOf(5 + droll(45), L.sp or 1)
        if droll(10) <= 4 and #have > 0 then
          L.ask = have[droll(#have)]
        else
          L.ask = pickSpecies(s, droll(3) == 1 and "uncommon" or "common")
        end
        L.levels = droll(3) == 1 and (droll(5) + 1) or 1
        if L.sp and L.ask and L.ask ~= L.sp then list[#list + 1] = L end
      end
      Gx.rng = saved
      cache.wnd, cache.sig, cache.list = wnd, sig, list
      -- (listings of past windows forgotten)
      for key in pairs(d.done) do
        if tonumber(key:match("^(%d+):")) ~= wnd then d.done[key] = nil end
      end
    end
    for _, L in ipairs(cache.list) do
      L.done = d.done[L.key] == true
      L.canDo = not L.done and #Gx.matching(s, L) > 0
    end
    return cache.list
  end
  -- the player's Pokémon that answer a listing (the party, then every box)
  function Gx.matching(s, L)
    local out = {}
    local range = LEVELS[L.levels] or LEVELS[1]
    local function fits(addr, mon)
      if tonumber(mon.species or mon.speciesId) ~= L.ask then return false end
      local lv = tonumber(mon.level) or 1
      if lv < range[1] or lv > range[2] then return false end
      return Gx.canSend(s, addr) == true
    end
    for _, addr in ipairs(Gx.candidates(s, nil, fits)) do out[#out + 1] = addr end
    for b = 1, Bx.BOXES do
      for i = 1, Bx.SLOTS do
        local addr = Bx.addr("box", i, b)
        local mon = Bx.get(s, addr)
        if mon and fits(addr, mon) then out[#out + 1] = addr end
      end
    end
    return out
  end
  function Gx.accept(s, L, addr)
    local d = data()
    if d.done[L.key] then return false, "gone" end
    local mon = Bx.get(s, addr)
    local range = LEVELS[L.levels] or LEVELS[1]
    if not mon or tonumber(mon.species or mon.speciesId) ~= L.ask then return false, "wrong" end
    local lv = tonumber(mon.level) or 1
    if lv < range[1] or lv > range[2] then return false, "wrong" end
    local ok, why = Gx.canSend(s, addr)
    if not ok then return false, why end
    local _, id = stranger(s)
    local recv = Gx.make(s, L.sp, L.level, L.who, id)
    if not recv then return false, "invalid" end
    local sent = Gx.swap(s, addr, recv, L.who)
    if not sent then return false, "gone" end
    d.done[L.key] = true
    logTrade(d, "gts", sent, recv, L.who)
    save(d)
    return true, recv, L.who, sent
  end

  -- a species' name (kept), and the species the player has seen that may be asked for, by name
  local names = {}
  function Gx.name(sp)
    local n = names[sp]
    if n == nil then
      local Pk = P()
      local ok, got = pcall(Pk and Pk.name or error, sp)
      n = ok and got and tostring(got) or "?"
      names[sp] = n
    end
    return n
  end
  function Gx.seenSpecies(s)
    local out = {}
    local seen = s and s.dex and s.dex.seen or {}
    for sp, yes in pairs(seen) do
      sp = tonumber(sp)
      if yes and sp and Gx.allowed(s, sp) and Gx.name(sp) ~= "?" then out[#out + 1] = sp end
    end
    table.sort(out, function(a, b) return Gx.name(a) < Gx.name(b) end)
    return out
  end

  -- a trade evolution waiting for the Pokémon just received (Kadabra, a Machoke, an item's ...)
  function Gx.evolveTarget(s, mon)
    local Evo = engine("src.core.game3.evolution")
    local ok, target = pcall(Evo and Evo.tradeTarget or error, mon, s)
    return ok and target or nil
  end

  -- the game's evolution scene for it (headless: evolved at once), onDone after
  function Gx.openEvolution(s, mon, target, onDone)
    local Scene = engine("src.ui.game3.evolution_scene")
    if Scene and Scene.start and love and love.graphics and love.graphics.newImage then
      local ok = pcall(Scene.start, mon, target, { canStop = false, session = s, via = "trade", onDone = onDone })
      if ok then return true end
    end
    local Evo = engine("src.core.game3.evolution")
    pcall(Evo and Evo.apply or error, mon, target, s, s and s.bag, "trade")
    if onDone then onDone() end
    return false
  end

  return Gx
end
