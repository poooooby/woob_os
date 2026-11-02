-- Rocket Slots, the model behind the Slots app: a three-reel machine played with money, and a prize
-- corner. One, three or five lines are played (the middle; the top and bottom rows; the two
-- diagonals), the bet on each; three of a kind on a line pays; the rarer kinds drop Rocket Tickets too, which
-- the prize corner trades for TMs, rare items and a few Pokémon. The outcome is drawn when the
-- spin starts (stopping the reels is only shown). Tickets and the machine's counts are kept in the
-- save (mod.save "slots"), so they rewind with the money they came from.
--
--   Sl = slots(engine, deps)   deps: save (mod.save), rng(n) -> 1..n, badges(s) -> 0..8
--   Sl.BETS { 50, 100, 500, 1000 }   Sl.SYMBOLS   Sl.REELS (three strips of symbol numbers)
--   Sl.PAYS (three of a kind: × the bet, tickets × bet / 50)   Sl.ONE, Sl.TWO (Pikachu from the left)
--   Sl.LINES (each line's row on each reel: -1 top, 0 middle, 1 bottom)   Sl.LINE_SETS { 1, 3, 5 }
--   Sl.at(r, stop, row) -> the symbol on reel r at that row when it stops at `stop`
--   Sl.payout(a, b, c) -> × the bet, tickets per ₽50, jackpot (the symbols on the line)
--   Sl.spin(s, level, lines) -> true, result | false, "money"   (the bet × the lines taken; the win
--       held back until Sl.collect(s), when the reels have stopped, so the money doesn't tell before)
--       result = { stops = { 1..20 x3 }, lines, won = { × per line, 0 if none } x5, symbol (the
--       best three of a kind on a line) | nil, pays (money), tickets, jackpot }
--   Sl.collect(s) -> pays, tickets (the held win, paid once; 0, 0 without one) ; Sl.result (the last)
--   Sl.speciesOf(symbol) -> the engine's species for a Pokémon symbol (kept)
--   Sl.prizes() -> { { kind = "item" | "mon", id, cost, name, level } ... }   (made once)
--   Sl.redeem(s, i) -> true, where ("bag" | "party" | "pc") | false, reason
--   Sl.tickets() ; Sl.stats() -> { spins, bet, won, jackpots }
--   reasons: lang/*.lua "reason.slots.<reason>" ("money" | "tickets" | "bag_full" | "no_room")

local floor, max, min = math.floor, math.max, math.min

local MAX_MONEY = 999999

-- the symbols, commonest to rarest: what's drawn on the reel (an item's picture, a Pokémon's
-- icon by its National Dex number, or the Rocket R)
local SYMBOLS = {
  { item = 4 }, { item = 3 }, { item = 2 }, { item = 68 }, { dex = 25 }, { dex = 52 }, { item = 1 }, { rocket = true },
}
local PIKACHU, ROCKET = 5, 8
-- three of a kind: × the bet, and tickets for every ₽50 bet
local PAYS = {
  { x = 10, t = 0 }, { x = 20, t = 0 }, { x = 30, t = 1 }, { x = 50, t = 2 },
  { x = 75, t = 3 }, { x = 100, t = 5 }, { x = 200, t = 10 }, { x = 500, t = 30 },
}
-- Pikachu from the left: on the first reel the bet comes back; on the first two, eight times it
local ONE, TWO = 1, 8
-- each reel: twenty stops (six Poké Balls, four Great Balls, three Ultra Balls, two Rare Candies,
-- two Pikachu, one each of Meowth, the Master Ball and the R), in its own order
local REELS = {
  { 1, 2, 1, 3, 5, 1, 4, 2, 8, 1, 3, 6, 2, 1, 5, 3, 7, 1, 2, 4 },
  { 2, 1, 3, 1, 4, 5, 2, 1, 7, 3, 1, 2, 6, 1, 4, 3, 2, 8, 1, 5 },
  { 1, 3, 2, 5, 1, 6, 2, 4, 1, 3, 8, 1, 2, 4, 5, 1, 3, 7, 2, 1 },
}
local BETS = { 50, 100, 500, 1000 }
-- the lines: the middle, the top and bottom rows, then the diagonals (rows on reels 1, 2, 3)
local LINES = { { 0, 0, 0 }, { -1, -1, -1 }, { 1, 1, 1 }, { -1, 0, 1 }, { 1, 0, -1 } }
local LINE_SETS = { 1, 3, 5 }

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
  local Sl = { BETS = BETS, SYMBOLS = SYMBOLS, REELS = REELS, PAYS = PAYS, ONE = ONE, TWO = TWO,
               PIKACHU = PIKACHU, ROCKET = ROCKET,
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

  -- what the line pays: × the bet, tickets per ₽50, the jackpot
  function Sl.payout(a, b, c)
    if a == b and b == c then return PAYS[a].x, PAYS[a].t, a == ROCKET end
    if a == PIKACHU and b == PIKACHU then return TWO, 0, false end
    if a == PIKACHU then return ONE, 0, false end
    return 0, 0, false
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

  local result = { stops = { 1, 1, 1 }, lines = 1, won = { 0, 0, 0, 0, 0 }, symbol = nil, pays = 0, tickets = 0,
                   jackpot = false }
  Sl.result = result
  local held = false
  function Sl.collect(s)
    if not held then return 0, 0 end
    held = false
    local pays, tickets = result.pays, result.tickets
    if pays > 0 and s then
      local Prize = engine("src.core.game3.battle.prize")
      if Prize and Prize.apply then Prize.apply(s, pays) else s.money = min(MAX_MONEY, money(s) + pays) end
    end
    if tickets > 0 then
      local d = data()
      d.tickets = d.tickets + tickets
      save(d)
    end
    return pays, tickets
  end
  function Sl.spin(s, level, lines)
    Sl.collect(s)
    local bet = BETS[level] or BETS[1]
    lines = max(1, min(#LINES, floor(tonumber(lines) or 1)))
    local cost = bet * lines
    if not s or money(s) < cost then return false, "money" end
    s.money = money(s) - cost
    local st = result.stops
    for r = 1, 3 do st[r] = roll(#REELS[r]) end
    local pays, tickets, jackpot, symbol = 0, 0, false, nil
    local won = result.won
    for l = 1, #LINES do
      won[l] = 0
      if l <= lines then
        local row = LINES[l]
        local a, b, c = Sl.at(1, st[1], row[1]), Sl.at(2, st[2], row[2]), Sl.at(3, st[3], row[3])
        local x, t, j = Sl.payout(a, b, c)
        won[l] = x
        pays, tickets = pays + x * bet, tickets + t * floor(bet / 50)
        if j then jackpot = true end
        if a == b and b == c and (not symbol or a > symbol) then symbol = a end
      end
    end
    local d = data()
    local sd = d.stats
    sd.spins, sd.bet, sd.won = (sd.spins or 0) + 1, (sd.bet or 0) + cost, (sd.won or 0) + pays
    if jackpot then sd.jackpots = (sd.jackpots or 0) + 1 end
    save(d)
    result.lines, result.symbol = lines, symbol
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
