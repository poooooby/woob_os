-- Rocket Slots, the model behind the Slots app: a five-reel video slot played with money, and a prize
-- corner. 1, 5, 10 or 20 lines are played, the bet on each; a line pays for three, four or five of
-- a kind from the left. Ditto is wild (it stands in for anything but Bonus; reels 2 to 4 only). Bonus
-- counts anywhere on the reels: three or more pay on the whole bet and give free spins, whose wins are
-- tripled and which can give more. The rarer wins drop Rocket Tickets too, which the prize corner
-- trades for TMs, rare items and a few Pokémon. The outcome is drawn when the spin starts (stopping
-- the reels is only shown). Tickets, free spins and the machine's counts are kept in the save
-- (mod.save "slots"), so they rewind with the money they came from.
--
--   Sl = slots(engine, deps)   deps: save (mod.save), rng(n) -> 1..n, badges(s) -> 0..8
--   Sl.BETS { 50, 100, 500, 1000 }   Sl.SYMBOLS   Sl.REELS (five strips of symbol numbers)
--   Sl.WILD, Sl.BONUS, Sl.ROCKET   Sl.PAYS[sym] = { x = { 3, 4, 5 of a kind: × the bet }, t = { tickets × bet / 50 } }
--   Sl.BONUS_PAY[n], Sl.FREE[n] (n Bonus: × the whole bet, free spins)   Sl.FREE_MULT
--   Sl.LINES (each line's row on each reel: -1 top, 0 middle, 1 bottom)   Sl.LINE_SETS { 1, 5, 10, 20 }
--   Sl.at(r, stop, row) -> the symbol on reel r at that row when it stops at `stop`
--   Sl.payout(a, b, c, d, e) -> × the bet, tickets per ₽50, jackpot, the symbol, how many (the line)
--   Sl.bonusOn(stops) -> how many Bonus show
--   Sl.spin(s, level, lines) -> true, result | false, "money"   (the bet × the lines taken, nothing on
--       a free spin, which keeps the bet that won it; the win held back until Sl.collect(s), when the
--       reels have stopped, so the money doesn't tell before)
--       result = { stops = { 1..30 x5 }, level, lines, won = { × per line } x20, count = { how many in
--       a row } x20, sym = { the line's symbol } x20, symbol (the best paid), scatters, free (a free
--       spin), mult, freeAdded, pays, tickets, jackpot, freeTotal (the last free spin: what they won) }
--   Sl.collect(s) -> pays, tickets (the held win, paid once; 0, 0 without one) ; Sl.result (the last)
--   Sl.cheat() (the window's code: Sl.CHEAT_SPINS free spins on the next spin, for this run) ; Sl.cheatArmed()
--   Sl.freeState() -> { left, level, lines, total } | nil
--   Sl.speciesOf(symbol) -> the engine's species for a Pokémon symbol (kept)
--   Sl.prizes() -> { { kind = "item" | "mon", id, cost, name, level } ... }   (made once)
--   Sl.redeem(s, i) -> true, where ("bag" | "party" | "pc") | false, reason
--   Sl.tickets() ; Sl.stats() -> { spins, bet, won, jackpots }
--   reasons: lang/*.lua "reason.slots.<reason>" ("money" | "tickets" | "bag_full" | "no_room")

local floor, max, min = math.floor, math.max, math.min

local MAX_MONEY = 999999

-- the symbols, commonest to rarest: what's drawn on the reel (an item's picture, a Pokémon's
-- icon by its National Dex number, or the Rocket R), then the wild and the Bonus
local SYMBOLS = {
  { item = 4 }, { item = 3 }, { item = 2 }, { item = 68 }, { dex = 25 }, { dex = 52 }, { item = 1 }, { rocket = true },
  { dex = 132, wild = true }, { bonus = true },
}
local ROCKET, WILD, BONUS = 8, 9, 10
-- three, four, five of a kind from the left: × the bet, and tickets for every ₽50 bet
local PAYS = {
  { x = { 4, 10, 25 }, t = { 0, 0, 1 } }, { x = { 5, 15, 45 }, t = { 0, 0, 2 } },
  { x = { 8, 25, 90 }, t = { 0, 1, 3 } }, { x = { 12, 50, 150 }, t = { 0, 1, 5 } },
  { x = { 20, 75, 250 }, t = { 1, 2, 8 } }, { x = { 30, 125, 500 }, t = { 1, 3, 12 } },
  { x = { 50, 250, 1000 }, t = { 2, 6, 25 } }, { x = { 60, 300, 2500 }, t = { 3, 15, 100 } },
}
-- n Bonus anywhere: × the whole bet, and free spins; a free spin's wins are tripled
local BONUS_PAY = { [3] = 2, [4] = 10, [5] = 50 }
local FREE = { [3] = 12, [4] = 18, [5] = 30 }
local FREE_MULT = 3
-- each reel: thirty stops in its own order. Over the rules' return (tests walk every combination):
-- 68.7% from the lines, 2.1% Bonus pays, 25.1% free spins = 95.9%
local REELS = {
  { 2, 8, 1, 7, 4, 2, 3, 1, 4, 3, 5, 4, 5, 2, 1, 3, 10, 1, 6, 2, 1, 3, 1, 2, 3, 2, 1, 8, 2, 1 },
  { 1, 2, 1, 2, 4, 1, 5, 4, 6, 1, 10, 4, 3, 2, 3, 9, 1, 3, 2, 3, 7, 1, 3, 2, 8, 1, 2, 9, 1, 5 },
  { 1, 5, 4, 6, 2, 6, 7, 9, 1, 4, 1, 3, 2, 3, 2, 1, 8, 3, 2, 4, 5, 9, 1, 3, 1, 10, 1, 2, 1, 2 },
  { 1, 5, 2, 1, 4, 9, 6, 4, 1, 2, 1, 2, 3, 9, 1, 4, 8, 1, 2, 3, 2, 3, 2, 1, 3, 5, 10, 1, 3, 7 },
  { 3, 4, 1, 2, 1, 2, 4, 1, 2, 1, 3, 8, 6, 1, 2, 5, 1, 3, 8, 3, 1, 5, 4, 3, 7, 2, 1, 10, 1, 2 },
}
local BETS = { 50, 100, 500, 1000 }
-- the twenty lines (rows on reels 1 to 5)
local LINES = {
  { 0, 0, 0, 0, 0 }, { -1, -1, -1, -1, -1 }, { 1, 1, 1, 1, 1 }, { -1, 0, 1, 0, -1 }, { 1, 0, -1, 0, 1 },
  { 0, -1, -1, -1, 0 }, { 0, 1, 1, 1, 0 }, { -1, -1, 0, 1, 1 }, { 1, 1, 0, -1, -1 }, { 0, 1, 0, -1, 0 },
  { 0, -1, 0, 1, 0 }, { -1, 0, 0, 0, -1 }, { 1, 0, 0, 0, 1 }, { -1, 0, -1, 0, -1 }, { 1, 0, 1, 0, 1 },
  { 0, 0, -1, 0, 0 }, { 0, 0, 1, 0, 0 }, { -1, -1, 1, -1, -1 }, { 1, 1, -1, 1, 1 }, { -1, 1, -1, 1, -1 },
}
local LINE_SETS = { 1, 5, 10, 20 }
local NREELS = #REELS

-- the prize corner: items by id, Pokémon by National Dex number; tickets each
local PRIZES = {
  { kind = "item", id = 110, cost = 10 }, { kind = "item", id = 68, cost = 15 }, { kind = "item", id = 69, cost = 25 },
  { kind = "mon", dex = 63, cost = 40 }, { kind = "mon", dex = 35, cost = 40 },
  { kind = "item", id = 301, cost = 60 }, { kind = "item", id = 312, cost = 60 }, { kind = "item", id = 323, cost = 60 },
  { kind = "item", id = 314, cost = 80 }, { kind = "mon", dex = 123, cost = 90 }, { kind = "mon", dex = 127, cost = 90 },
  { kind = "item", id = 303, cost = 100 }, { kind = "mon", dex = 147, cost = 150 }, { kind = "mon", dex = 137, cost = 200 },
  { kind = "item", id = 1, cost = 600 },
}

return function(engine, deps)
  deps = deps or {}
  local Sl = { BETS = BETS, SYMBOLS = SYMBOLS, REELS = REELS, PAYS = PAYS, ROCKET = ROCKET, WILD = WILD, BONUS = BONUS,
               BONUS_PAY = BONUS_PAY, FREE = FREE, FREE_MULT = FREE_MULT,
               LINES = LINES, LINE_SETS = LINE_SETS, store = deps.save, rng = deps.rng }

  local loose
  local function data()
    local store = Sl.store
    local d = store and store:get("slots") or loose
    if type(d) ~= "table" then
      d = { tickets = 0, stats = { spins = 0, bet = 0, won = 0, jackpots = 0 } }
      if store then store:set("slots", d) else loose = d end
    end
    d.tickets = tonumber(d.tickets) or 0
    d.stats = d.stats or { spins = 0, bet = 0, won = 0, jackpots = 0 }
    return d
  end
  local function save(d) if Sl.store then Sl.store:set("slots", d) end end
  function Sl.tickets() return data().tickets end
  function Sl.stats() return data().stats end
  -- (tests and the probe lend tickets)
  function Sl.setTickets(n)
    local d = data()
    d.tickets = max(0, floor(n))
    save(d)
  end

  -- what the line pays: × the bet, tickets per ₽50, the jackpot, its symbol, how many in a row
  -- (from the left, wilds standing in; reel 1 has none, so the first symbol is the line's)
  function Sl.payout(a, b, c, d, e)
    if a == WILD or a == BONUS then return 0, 0, false, nil, 0 end
    if not ((b == a or b == WILD) and (c == a or c == WILD)) then return 0, 0, false, nil, 0 end
    local n = 3
    if d == a or d == WILD then
      n = 4
      if e == a or e == WILD then n = 5 end
    end
    local pay = PAYS[a]
    return pay.x[n - 2], pay.t[n - 2], a == ROCKET and n == 5, a, n
  end

  function Sl.at(r, stop, row)
    local reel = REELS[r]
    return reel[(stop - 1 + row) % #reel + 1]
  end

  local function roll(n)
    if Sl.rng then return Sl.rng(n) end
    local R = love and love.math and love.math.random
    return R and R(1, n) or math.random(1, n)
  end
  local function money(s) return max(0, floor(tonumber(s and s.money) or 0)) end

  local function newResult()
    local r = { stops = {}, level = 1, lines = 1, won = {}, count = {}, sym = {}, symbol = nil, scatters = 0, free = false,
                mult = 1, freeAdded = 0, pays = 0, tickets = 0, jackpot = false, freeTotal = nil }
    for i = 1, NREELS do r.stops[i] = 1 end
    for l = 1, #LINES do r.won[l], r.count[l], r.sym[l] = 0, 0, false end
    return r
  end
  local result = newResult()
  Sl.result = result
  local held = false
  local cheat = false
  Sl.CHEAT_SPINS = 12
  function Sl.cheat() cheat = true end
  function Sl.cheatArmed() return cheat end

  function Sl.freeState()
    local f = data().free
    return type(f) == "table" and (tonumber(f.left) or 0) > 0 and f or nil
  end

  function Sl.collect(s)
    if not held then return 0, 0 end
    held = false
    local pays, tickets = result.pays, result.tickets
    if pays > 0 and s then
      local Prize = engine("src.core.game3.battle.prize")
      if Prize and Prize.apply then Prize.apply(s, pays) else s.money = min(MAX_MONEY, money(s) + pays) end
    end
    local d = data()
    if tickets > 0 then d.tickets = d.tickets + tickets end
    -- (the free spins' running total; the last one ends them)
    if type(d.free) == "table" then
      d.free.total = (tonumber(d.free.total) or 0) + pays
      if (tonumber(d.free.left) or 0) <= 0 then
        result.freeTotal = d.free.total
        d.free = nil
      end
    end
    save(d)
    return pays, tickets
  end

  -- how many Bonus show on the reels at these stops (at most one a reel)
  function Sl.bonusOn(stops)
    local n = 0
    for r = 1, NREELS do
      for row = -1, 1 do
        if Sl.at(r, stops[r], row) == BONUS then
          n = n + 1
          break
        end
      end
    end
    return n
  end

  function Sl.spin(s, level, lines)
    Sl.collect(s)
    if not s then return false, "money" end
    local d = data()
    local free = Sl.freeState()
    local cost = 0
    if free then
      level, lines = free.level, free.lines
      free.left = free.left - 1
    end
    local bet = BETS[level] or BETS[1]
    lines = max(1, min(#LINES, floor(tonumber(lines) or 1)))
    if not free then
      cost = bet * lines
      if money(s) < cost then return false, "money" end
      s.money = money(s) - cost
    end
    local st = result.stops
    for r = 1, NREELS do st[r] = roll(#REELS[r]) end
    local mult = free and FREE_MULT or 1
    local pays, tickets, jackpot, symbol, bestX = 0, 0, false, nil, 0
    local won, count, sym = result.won, result.count, result.sym
    for l = 1, #LINES do
      won[l], count[l], sym[l] = 0, 0, false
      if l <= lines then
        local row = LINES[l]
        local x, t, j, a, n = Sl.payout(Sl.at(1, st[1], row[1]), Sl.at(2, st[2], row[2]), Sl.at(3, st[3], row[3]),
          Sl.at(4, st[4], row[4]), Sl.at(5, st[5], row[5]))
        won[l], count[l], sym[l] = x, n, a or false
        pays, tickets = pays + x * bet * mult, tickets + t * floor(bet / 50)
        if j then jackpot = true end
        if x > bestX then symbol, bestX = a, x end
      end
    end
    -- (Bonus, on the whole bet)
    local scatters = Sl.bonusOn(st)
    local added = FREE[scatters] or 0
    if added > 0 then pays = pays + BONUS_PAY[scatters] * bet * lines * mult end
    if cheat then
      cheat = false
      added = added + Sl.CHEAT_SPINS
    end
    if added > 0 then
      if free then free.left = free.left + added
      else d.free = { left = added, level = level, lines = lines, total = 0 } end
    end
    local sd = d.stats
    sd.spins, sd.bet, sd.won = (sd.spins or 0) + 1, (sd.bet or 0) + cost, (sd.won or 0) + pays
    if jackpot then sd.jackpots = (sd.jackpots or 0) + 1 end
    save(d)
    result.level, result.lines, result.symbol, result.scatters = level, lines, symbol, scatters
    result.free, result.mult, result.freeAdded, result.freeTotal = free ~= nil, mult, added, nil
    result.pays, result.tickets, result.jackpot = pays, tickets, jackpot
    held = true
    return true, result
  end

  local speciesFor = {}
  function Sl.speciesOf(i)
    local sp = speciesFor[i]
    if sp == nil then
      local P = engine("src.core.game3.pokemon")
      local dex = SYMBOLS[i] and SYMBOLS[i].dex
      local ok, got = pcall(P and P.speciesFromNational or error, dex)
      sp = ok and got or false
      speciesFor[i] = sp
    end
    return sp or nil
  end

  -- ------- the prize corner

  local prizes
  function Sl.prizes()
    if prizes then return prizes end
    local P, I = engine("src.core.game3.pokemon"), engine("src.core.game3.items_data")
    local out = {}
    for _, p in ipairs(PRIZES) do
      local e = { kind = p.kind, cost = p.cost }
      if p.kind == "item" then
        local ok, info = pcall(I and I.info or error, p.id)
        if ok and info and info.name then
          e.id, e.name = p.id, tostring(info.name)
          e.desc = ((info.description or ""):gsub("\\n", " "):gsub("\\p", " "):gsub("\n", " "))
          -- (a TM: its move's name after the number, as the TM Case shows it)
          local okT, tm = pcall(I.isTm or error, p.id)
          if okT and tm and P and P.moveFromTmItem and P.moveName then
            local okM, mv = pcall(function() return P.moveName(P.moveFromTmItem(p.id)) end)
            if okM and mv and mv ~= "" then e.name = e.name .. " " .. tostring(mv) end
          end
          out[#out + 1] = e
        end
      else
        local ok, sp = pcall(P and P.speciesFromNational or error, p.dex)
        local okN, name = pcall(P and P.name or error, ok and sp or 0)
        if ok and sp and okN and name then
          e.id, e.name, e.desc = sp, tostring(name), ""
          out[#out + 1] = e
        end
      end
    end
    if #out > 0 then prizes = out end
    return out
  end
  -- a Pokémon prize's level: grows with the badges
  function Sl.level(s)
    local b = deps.badges and deps.badges(s) or 0
    return min(100, 10 + 3 * (tonumber(b) or 0))
  end

  function Sl.redeem(s, i)
    local p = Sl.prizes()[i]
    if not (s and p) then return false, "tickets" end
    local d = data()
    if d.tickets < p.cost then return false, "tickets" end
    local where
    if p.kind == "item" then
      local Bag = engine("src.core.game3.bag")
      if not Bag then return false, "bag_full" end
      s.bag = s.bag or Bag.new()
      local okC, can = pcall(Bag.canAdd, s.bag, p.id, 1)
      if not (okC and can) then return false, "bag_full" end
      local okA, added = pcall(Bag.add, s.bag, p.id, 1)
      if not (okA and added) then return false, "bag_full" end
      where = "bag"
    else
      local Party = engine("src.core.game3.party")
      local ok, code = pcall(Party and Party.giveMonToPlayer or error, s, p.id, Sl.level(s))
      if not ok or code == nil or code == 2 then return false, "no_room" end
      where = code == 0 and "party" or "pc"
    end
    d.tickets = d.tickets - p.cost
    save(d)
    return true, where
  end

  return Sl
end
