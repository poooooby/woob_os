-- R-Bay, the auction house behind the Auctions app: Team Rocket's market for Pokémon. Twelve
-- auctions run at once, each for three hours; one ends and a new one starts every fifteen minutes,
-- on the device's clock, so the market turns over while the game is closed too.
--
-- Nothing about an auction is stored: it is worked out from the save's seed, its slot and its
-- number (which Pokémon, its tier, level and IVs, its hidden market value, the other bidders, what
-- each will pay and when they bid). Only the player's own bids and results are kept, in the save
-- (mod.save "auction"), so they rewind with the money and the party they belong to.
--
-- Bidding is eBay's: each bidder has a hidden maximum; the price shown is one step over the
-- second-highest maximum, never past the highest; on a tie the earlier bid leads. The player's
-- maximum is held from their money while they lead (a raise takes the difference); outbid, it all
-- comes back at once (`held` 0: a beaten maximum never leads again, a new bid is held afresh).
-- When the auction ends a win pays the price and gets the rest back.
--
--   Au = auction(engine, deps)  deps: save (mod.save), now() -> epoch seconds, seed(s) -> number,
--                               dex() -> WoobleDex's exports or nil, badges(s) -> 0..8
--   Au.listings(s, now) -> the twelve running auctions, soonest to end first, each refreshed (at
--       most once a second): { key, tier, sp, name, level, ivs = { hp, atk, def, spa, spd, spe },
--       ivSum, perfect, start, finish, price, nbids, leader (0: the player; i: bidders[i]; nil),
--       mine (the player's bid or nil), histN, histWho, histAmt, bidders = { { name, max, at } } }
--   Au.step(price) -> the least raise          Au.minBid(L) -> the least the player may bid now
--   Au.pools() -> { tier = { { sp, name } } } ; Au.tierOf(sp) ; Au.minLevel(sp) (an evolution's level)
--   Au.bid(s, L, max, now) -> true | false, reason ("too_low" | "money" | "ended")
--   Au.settle(s, now) -> won, lost, lastSpecies   (ended auctions the player bid on)
--   Au.mine(s, now) -> { bid records, soonest first }   Au.results() -> { newest first }
--   Au.unread() / Au.seen()
--   reasons: lang/*.lua "reason.auction.<reason>"

local floor, max, min = math.floor, math.max, math.min

local DUR, SLOTS = 3 * 3600, 12
local OFF = DUR / SLOTS
local EPOCH = 1700000000
local CLOSE = 30
local M = 2147483647
local CAP, KEEP = 1.35, 20
local MAX_MONEY = 999999

local TIERS = { "common", "uncommon", "rare", "prized", "legendary", "mythical" }
-- weight (of 100), level range, market value range, IV rolls (the best kept), how many bidders,
-- how far over the value the keenest goes, how many bid in the last ten minutes
local TIER = {
  common = { weight = 34, lv = { 5, 12 }, v = { 1000, 3000 }, rolls = 1, bidders = { 1, 3 }, hi = 0.90, snipe = 0.1 },
  uncommon = { weight = 26, lv = { 14, 22 }, v = { 3000, 8000 }, rolls = 1, bidders = { 2, 4 }, hi = 0.95, snipe = 0.15 },
  rare = { weight = 20, lv = { 28, 36 }, v = { 8000, 20000 }, rolls = 2, bidders = { 2, 5 }, hi = 1.00, snipe = 0.2 },
  prized = { weight = 11, lv = { 10, 18 }, v = { 15000, 40000 }, rolls = 2, bidders = { 3, 6 }, hi = 1.10, snipe = 0.3 },
  legendary = { weight = 6, lv = { 45, 50 }, v = { 80000, 200000 }, rolls = 3, bidders = { 4, 7 }, hi = 1.20, snipe = 0.5 },
  mythical = { weight = 3, lv = { 30, 40 }, v = { 150000, 400000 }, rolls = 3, bidders = { 4, 7 }, hi = 1.25, snipe = 0.5 },
}

-- National Dex numbers: the legends, the myths, and the lines everyone wants (starters, the
-- pseudo-legendaries, fossils, Eevee and its evolutions, a few favourites)
local function set(...)
  local out = {}
  for _, n in ipairs({ ... }) do out[n] = true end
  return out
end
local function range(t, a, b) for n = a, b do t[n] = true end return t end
local LEGENDARY = set(144, 145, 146, 150, 243, 244, 245, 249, 250, 377, 378, 379, 380, 381, 382, 383, 384)
local MYTHICAL = set(151, 251, 385, 386)
local PRIZED = set(131, 143, 196, 197, 349, 350, 470, 471, 700)
for _, r in ipairs({ { 1, 9 }, { 152, 160 }, { 252, 260 }, { 387, 395 }, { 495, 503 }, { 650, 658 }, { 722, 730 },
                     { 810, 818 }, { 906, 914 }, { 147, 149 }, { 246, 248 }, { 371, 376 }, { 443, 445 },
                     { 633, 635 }, { 704, 706 }, { 782, 784 }, { 885, 887 }, { 996, 998 }, { 138, 142 },
                     { 345, 348 }, { 133, 136 } }) do
  range(PRIZED, r[1], r[2])
end
-- (never on sale: Shedinja comes from Nincada's shell)
local NEVER = set(292)

local HANDLES = {
  "GruntNo42", "SlowpokeTails", "CeladonCasino", "HideoutVIP", "MeowMoney", "RocketRookie", "GoldenNugget",
  "SilphScoped", "LavenderGhost", "GameCornerKing", "TeamR_Admin", "BossesFavorite", "MagikarpSales",
  "SaffronShade", "CoinCaseCarl", "UndergroundUma", "BlackMarketBea", "StolenGoods", "RareCandyRon",
  "ExpShareEd", "MtMoonMiner", "PokeFlutePete", "SneaselSwipe", "ZubatZach", "KoffingKate", "EkansEddie",
  "DittoDealer", "NightShadeNia", "VoltorbVince", "PersianPurr",
}

local IV_KEYS = { "hp", "atk", "def", "spa", "spd", "spe" }

-- the least raise over a price
local function step(p)
  if p < 1000 then return 50 end
  if p < 5000 then return 100 end
  if p < 20000 then return 250 end
  if p < 100000 then return 1000 end
  return 2500
end
local function roundTo(v, unit) return floor(v / unit + 0.5) * unit end

-- the market's dice: a Park-Miller generator on a table (no closures)
local function nextRand(st)
  st.x = (st.x * 48271) % M
  return st.x
end
local function randInt(st, a, b) return a + nextRand(st) % (b - a + 1) end
local function frac(st) return nextRand(st) / M end

return function(engine, deps)
  deps = deps or {}
  local Au = { SLOTS = SLOTS, DURATION = DUR, TURN = OFF, TIERS = TIERS, IV_KEYS = IV_KEYS, step = step,
               CAP = CAP, store = deps.save, now = deps.now or os.time }

  -- ------- the kept part: the player's bids and results (in the save)

  local loose
  local function data()
    local store = Au.store
    local d = store and store:get("auction") or loose
    if type(d) ~= "table" then
      d = { bids = {}, results = {}, unread = 0 }
      if store then store:set("auction", d) else loose = d end
    end
    d.bids = d.bids or {}
    d.results = d.results or {}
    d.unread = tonumber(d.unread) or 0
    return d
  end
  local function save(d)
    if Au.store then Au.store:set("auction", d) end
  end
  function Au.unread() return data().unread end
  function Au.seen()
    local d = data()
    if d.unread ~= 0 then
      d.unread = 0
      save(d)
    end
  end
  function Au.results() return data().results end

  -- ------- what's on sale: every species in a tier (made once)

  local pools
  local function Pokemon() return engine("src.core.game3.pokemon") end
  local function buildPools()
    local P = Pokemon()
    local out, minLv = {}, {}
    for _, t in ipairs(TIERS) do out[t] = {} end
    if not P then return out, minLv end
    local function add(tier, sp, name)
      local pool = out[tier]
      pool[#pool + 1] = { sp = sp, name = name }
    end
    local function tierOf(nat, from, into)
      if LEGENDARY[nat] then return "legendary" end
      if MYTHICAL[nat] then return "mythical" end
      if PRIZED[nat] then return "prized" end
      if from and not into then return "rare" end
      if into and not from then return "common" end
      return "uncommon"
    end
    -- (the cart's own: which come from another, and at what level)
    local pre, into = {}, {}
    local LEVELED = { [4] = true, [8] = true, [9] = true, [10] = true, [11] = true, [12] = true, [13] = true, [14] = true }
    for nat = 1, 386 do
      local ok, sp = pcall(P.speciesFromNational, nat)
      if ok and sp then
        local okE, evos = pcall(P.evolutions, sp)
        for _, e in ipairs(okE and evos or {}) do
          local target = tonumber(e.target or e[3])
          if target then
            pre[target] = sp
            into[sp] = true
            local method, param = tonumber(e.method or e[1]), tonumber(e.param or e[2])
            if method and LEVELED[method] and param then minLv[target] = max(minLv[target] or 0, param) end
          end
        end
      end
    end
    local Dx = deps.dex and deps.dex()
    Dx = Dx and Dx.exports or Dx
    local okDx = type(Dx) == "table" and (tonumber(Dx.apiVersion) or 0) >= 2
    for nat = 1, 386 do
      local ok, sp = pcall(P.speciesFromNational, nat)
      if ok and sp and not NEVER[nat] then
        local okN, name = pcall(P.name, sp)
        if okN and name then
          local goesOn = into[sp]
          -- (WoobleDex gives some of the cart's Pokémon a new evolution: Rhydon to Rhyperior ...)
          if not goesOn and okDx and Dx.evolutionsOf then
            local okV, ev = pcall(Dx.evolutionsOf, nat)
            goesOn = okV and type(ev) == "table" and type(ev.evolvesInto) == "table" and #ev.evolvesInto > 0
          end
          add(tierOf(nat, pre[sp] ~= nil, goesOn), sp, tostring(name))
        end
      end
    end
    -- (a chain's last step at least as high as the one before it)
    for _ = 1, 2 do
      for sp, from in pairs(pre) do
        if minLv[from] then minLv[sp] = max(minLv[sp] or 0, minLv[from]) end
      end
    end
    -- WoobleDex's species (#387 on), its legends and myths flagged by it
    if okDx and Dx.listSpecies then
      local okL, list = pcall(Dx.listSpecies)
      for _, r in ipairs(okL and list or {}) do
        local nat, sp = tonumber(r.dex), tonumber(r.slot)
        if nat and sp and nat > 386 then
          local from, goes = false, false
          if Dx.evolutionsOf then
            local okV, ev = pcall(Dx.evolutionsOf, nat)
            if okV and type(ev) == "table" then
              goes = type(ev.evolvesInto) == "table" and #ev.evolvesInto > 0
              local f = ev.evolvesFrom
              from = f ~= nil
              local m = type(f) == "table" and type(f.methods) == "table" and f.methods[1]
              local lv = type(m) == "table" and tonumber(m.level)
              if lv then minLv[sp] = lv end
            end
          end
          local tier = (r.legendary and "legendary") or (r.mythical and "mythical") or tierOf(nat, from, goes)
          add(tier, sp, tostring(r.name or sp))
        end
      end
    end
    return out, minLv
  end
  local minLevel
  local function poolsNow()
    if not pools then
      pools, minLevel = buildPools()
      -- (no species yet, the data not in: try again next time)
      if #pools.common == 0 then
        local p = pools
        pools = nil
        return p
      end
    end
    return pools
  end
  Au.pools = poolsNow
  -- a species' tier on the market and the least level it's seen at (for other apps: the GTS)
  local tierFor
  function Au.tierOf(sp)
    local all = poolsNow()
    if not tierFor or tierFor.pools ~= all then
      tierFor = { pools = all }
      for t, pool in pairs(all) do for _, e in ipairs(pool) do tierFor[e.sp] = t end end
    end
    return tierFor[sp]
  end
  function Au.minLevel(sp)
    poolsNow()
    return minLevel and minLevel[sp] or 0
  end

  -- ------- one auction, from the seed, its slot and its number

  local function seedOf(s)
    local v = deps.seed and deps.seed(s)
    v = tonumber(v) or 1
    return v % M
  end
  Au.seedOf = seedOf
  local function typesText(sp)
    local P = Pokemon()
    local Types = engine("src.core.game3.battle.types")
    local ok, t = pcall(P and P.types or error, sp)
    if not (ok and type(t) == "table") then return "" end
    local a, b = tonumber(t[1]), tonumber(t[2])
    local function nm(id)
      local okN, n = pcall(Types and Types.name or error, id)
      return okN and n and tostring(n) or ""
    end
    if not a then return "" end
    if b and b ~= a then return nm(a) .. " / " .. nm(b) end
    return nm(a)
  end

  local rng = { x = 1 }
  local function generate(s, k, n, badges)
    local seed = seedOf(s)
    rng.x = (seed * 7919 + k * 104729 + n * 15485863) % M
    if rng.x == 0 then rng.x = 1 end
    for _ = 1, 4 do nextRand(rng) end
    local start = EPOCH + k * OFF + n * DUR
    local L = { key = k .. ":" .. n, k = k, n = n, seed = seed, start = start, finish = start + DUR,
                histWho = {}, histAmt = {}, histN = 0, nbids = 0 }
    -- the tier, then a Pokémon in it
    local all = poolsNow()
    local roll, tier = randInt(rng, 1, 100), "common"
    for _, t in ipairs(TIERS) do
      roll = roll - TIER[t].weight
      if roll <= 0 then tier = t break end
    end
    if #all[tier] == 0 then tier = "common" end
    local pool = all[tier]
    local pick = pool[randInt(rng, 1, max(1, #pool))] or { sp = 1, name = "?" }
    local def = TIER[tier]
    L.tier, L.sp, L.name = tier, pick.sp, pick.name
    L.level = min(100, max(randInt(rng, def.lv[1], def.lv[2]) + 3 * (badges or 0), minLevel and minLevel[pick.sp] or 0))
    -- the IVs (the higher tiers keep the best of more rolls)
    local ivs, sum, perfect = {}, 0, 0
    for _, key in ipairs(IV_KEYS) do
      local v = 0
      for _ = 1, def.rolls do v = max(v, randInt(rng, 0, 31)) end
      ivs[key] = v
      sum = sum + v
      if v == 31 then perfect = perfect + 1 end
    end
    L.ivs, L.ivSum, L.perfect = ivs, sum, perfect
    local q = sum / 186
    -- the market value: the tier's, better IVs worth more
    local V = (def.v[1] + frac(rng) * (def.v[2] - def.v[1])) * (0.6 + 0.8 * q * q) * (1 + 0.08 * perfect)
    V = min(MAX_MONEY, roundTo(V, V < 10000 and 50 or 500))
    L.value = V
    L.startPrice = max(100, roundTo(V * 0.2, 10))
    -- the other bidders: more of them, and keener, the rarer it is (good IVs draw one more)
    local nb = randInt(rng, def.bidders[1], def.bidders[2]) + (q > 0.75 and 1 or 0)
    local lo, hi = 0.45 + 0.2 * q, min(CAP, def.hi + (q > 0.75 and 0.05 or 0))
    local bidders = {}
    local first = randInt(rng, 1, #HANDLES)
    for i = 1, nb do
      local at
      if frac(rng) < def.snipe then
        at = L.finish - randInt(rng, 5, 600)
      else
        at = start + randInt(rng, 60, DUR - 900)
      end
      local m = min(V * CAP, V * (lo + frac(rng) * (hi - lo)))
      bidders[i] = { name = HANDLES[(first + i * 7) % #HANDLES + 1], max = max(L.startPrice, roundTo(m, 10)), at = at }
    end
    table.sort(bidders, function(a, b) return a.at < b.at end)
    L.bidders = bidders
    L.types = typesText(pick.sp)
    return L
  end
  Au.generate = generate

  -- ------- the bidding up to a moment (eBay's proxy bids); no tables made

  local function hist(L, who, amt)
    L.histN = L.histN + 1
    local i = (L.histN - 1) % 5 + 1
    L.histWho[i], L.histAmt[i] = who, amt
  end
  -- -> price, leader (0 the player, i a bidder, nil none), the leader's maximum
  local function sim(L, t, mine)
    local price, leader, lmax = L.startPrice, nil, -1
    L.histN, L.nbids = 0, 0
    local B = L.bidders
    local steps = mine and mine.steps
    local np = steps and #steps or 0
    local bi, pi = 1, 1
    while true do
      local b = B[bi]
      local bAt = b and b.at <= t and b.at or nil
      local pAt = pi < np and steps[pi] <= t and steps[pi] or nil
      if not bAt and not pAt then break end
      local who, mx
      if bAt and (not pAt or bAt <= pAt) then
        who, mx = bi, b.max
        bi = bi + 1
      else
        who, mx = 0, steps[pi + 1]
        pi = pi + 2
      end
      if who == leader then
        lmax = max(lmax, mx)
      elseif not leader then
        if mx >= price then
          leader, lmax = who, mx
          L.nbids = L.nbids + 1
          hist(L, who, price)
        end
      elseif mx > lmax then
        price = min(mx, lmax + step(lmax))
        leader, lmax = who, mx
        L.nbids = L.nbids + 1
        hist(L, who, price)
      elseif mx > price then
        price = min(lmax, mx + step(mx))
        L.nbids = L.nbids + 2
        hist(L, who, mx)
        -- (the leader's maximum answers at once: the new top bid)
        hist(L, leader, price)
      end
    end
    return price, leader, lmax
  end
  Au.sim = sim

  -- ------- the running auctions

  local cur, sorted, sortedKey = {}, {}, ""
  local refreshedAt = -1
  local function byFinish(a, b) return a.finish < b.finish end
  local pay, refund
  function Au.listings(s, now)
    now = now or Au.now()
    local d = data()
    local seed = seedOf(s)
    local changed = false
    local badges
    for k = 0, SLOTS - 1 do
      local n = floor((now - EPOCH - k * OFF) / DUR)
      local L = cur[k + 1]
      if not L or L.n ~= n or L.seed ~= seed then
        if badges == nil then badges = deps.badges and deps.badges(s) or 0 end
        L = generate(s, k, n, badges)
        cur[k + 1] = L
        changed = true
      end
    end
    if changed or #sorted ~= SLOTS then
      for i = 1, SLOTS do sorted[i] = cur[i] end
      table.sort(sorted, byFinish)
    end
    if changed or now ~= refreshedAt then
      refreshedAt = now
      for i = 1, SLOTS do
        local L = sorted[i]
        local mine = d.bids[L.key]
        L.mine = mine
        L.price, L.leader = sim(L, now, mine)
        if mine and L.leader ~= 0 then refund(s, mine, d) end
      end
    end
    return sorted
  end

  -- the least the player may bid: one step over the price (or over their own maximum while they lead)
  function Au.minBid(L)
    if L.mine and L.leader == 0 then return L.mine.max + step(L.mine.max) end
    if L.nbids == 0 then return L.startPrice end
    return L.price + step(L.price)
  end

  local function money(s) return max(0, floor(tonumber(s and s.money) or 0)) end
  -- what's held from the money for a bid (older saves: all of the maximum)
  local function heldOf(b) return b.held or b.max or 0 end
  Au.heldOf = heldOf
  function pay(s, amount)
    if amount <= 0 then return end
    local Prize = engine("src.core.game3.battle.prize")
    if Prize and Prize.apply then
      Prize.apply(s, amount)
    else
      s.money = min(MAX_MONEY, money(s) + amount)
    end
  end
  -- outbid: what was held comes back now
  function refund(s, b, d)
    local h = heldOf(b)
    if h <= 0 or not s then return end
    b.held = 0
    pay(s, h)
    save(d)
  end

  function Au.bid(s, L, amount, now)
    now = now or Au.now()
    amount = floor(tonumber(amount) or 0)
    if not (s and L) then return false, "ended" end
    if now >= L.finish - CLOSE then return false, "ended" end
    local d = data()
    local mine = d.bids[L.key]
    L.price, L.leader = sim(L, now, mine)
    L.mine = mine
    if amount < Au.minBid(L) then return false, "too_low" end
    local cost = amount - (mine and heldOf(mine) or 0)
    if cost > money(s) then return false, "money" end
    s.money = money(s) - cost
    if not mine then
      local ivs = {}
      for _, key in ipairs(IV_KEYS) do ivs[key] = L.ivs[key] end
      mine = { k = L.k, n = L.n, key = L.key, sp = L.sp, name = L.name, level = L.level, tier = L.tier,
               ivs = ivs, finish = L.finish, steps = {} }
      d.bids[L.key] = mine
    end
    mine.max, mine.held = amount, amount
    mine.steps[#mine.steps + 1] = now
    mine.steps[#mine.steps + 1] = amount
    save(d)
    L.mine = mine
    L.price, L.leader = sim(L, now, mine)
    if L.leader ~= 0 then refund(s, mine, d) end
    refreshedAt = -1
    return true
  end

  -- the player's bids still running, soonest to end first (a list made per call: not a draw's)
  function Au.mine(s, now)
    local out = {}
    for _, b in pairs(data().bids) do out[#out + 1] = b end
    table.sort(out, byFinish)
    return out
  end

  -- a won Pokémon to the player: the listed IVs, its stats again, full HP -> where ("party" | "pc") or nil
  local function deliver(s, b)
    local Party = engine("src.core.game3.party")
    if not (Party and Party.giveMonToPlayer) then return nil end
    local ok, code, mon = pcall(Party.giveMonToPlayer, s, b.sp, b.level)
    if not ok or code == nil or code == 2 or type(mon) ~= "table" then return nil end
    mon.ivs = mon.ivs or {}
    for _, key in ipairs(IV_KEYS) do
      if b.ivs and b.ivs[key] then mon.ivs[key] = b.ivs[key] end
    end
    local P = Pokemon()
    if P and P.applyStats then
      pcall(P.applyStats, mon, s)
      mon.hp = mon.maxHp or mon.hp
    end
    return code == 0 and "party" or "pc"
  end

  -- the ended auctions the player bid on: a win delivered (the change back), a loss refunded
  function Au.settle(s, now)
    now = now or Au.now()
    if not s then return 0, 0 end
    local d = data()
    local won, lost, lastSp = 0, 0, nil
    local any = false
    -- (running bids: one outbid since gets its money back now; listings at most once a second)
    for _, b in pairs(d.bids) do
      if now < (b.finish or 0) and heldOf(b) > 0 then Au.listings(s, now) break end
    end
    for key, b in pairs(d.bids) do
      if now >= (b.finish or 0) then
        any = true
        local price, leader = b.price, b.won
        if leader == nil then
          local L = generate(s, b.k, b.n, 0)
          local p, who = sim(L, b.finish, b)
          price, leader = p, who == 0
          b.price, b.won = price, leader
        end
        if leader then
          local where = deliver(s, b)
          if where then
            pay(s, heldOf(b) - price)
            table.insert(d.results, 1, { sp = b.sp, name = b.name, level = b.level, price = price, won = true,
                                         where = where, at = b.finish, tier = b.tier })
            d.bids[key] = nil
            won, lastSp = won + 1, b.sp
            d.unread = d.unread + 1
          end
          -- (no room in the party or the PC: it waits, won, for the next time)
        else
          pay(s, heldOf(b))
          table.insert(d.results, 1, { sp = b.sp, name = b.name, level = b.level, price = price, won = false,
                                       refund = b.max, at = b.finish, tier = b.tier })
          d.bids[key] = nil
          lost = lost + 1
          d.unread = d.unread + 1
        end
      end
    end
    while #d.results > KEEP do d.results[#d.results] = nil end
    if any then
      save(d)
      refreshedAt = -1
    end
    return won, lost, lastSp
  end

  return Au
end
