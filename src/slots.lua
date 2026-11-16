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
--   deps.port (the Game Boy games: src/gb/port.lua -- the wallet, the Bag, the Pokémon) with deps.prizes (their
--   prize corner: { kind = "item", id = "NUGGET", cost } | { kind = "mon", dex, cost })

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

-- the limited prizes (src/slots.lua's "limited" section). The specials: each game's event tickets (the
-- flags the game's own distribution sets: the ferry's first; where the harbor is), and event Pokémon as
-- they were given out (OT, ID, level, moves, held item; Serebii's event pages)
local LILYCOVE, VERMILION = "slots.harbor.lilycove", "slots.harbor.vermilion"
local SPECIALS = {
  { key = "eon", cost = 500, ticket = { item = "ITEM_EON_TICKET", where = { all = LILYCOVE },
    flags = { emerald = { "FLAG_ENABLE_SHIP_SOUTHERN_ISLAND" }, ruby = { "FLAG_SYS_HAS_EON_TICKET" },
              sapphire = { "FLAG_SYS_HAS_EON_TICKET" } } } },
  { key = "mystic", cost = 500, ticket = { item = "ITEM_MYSTIC_TICKET", where = { emerald = LILYCOVE, all = VERMILION },
    flags = { emerald = { "FLAG_ENABLE_SHIP_NAVEL_ROCK", "FLAG_RECEIVED_MYSTIC_TICKET" },
              firered = { "FLAG_ENABLE_SHIP_NAVEL_ROCK", "FLAG_RECEIVED_MYSTIC_TICKET" },
              leafgreen = { "FLAG_ENABLE_SHIP_NAVEL_ROCK", "FLAG_RECEIVED_MYSTIC_TICKET" } } } },
  { key = "aurora", cost = 500, ticket = { item = "ITEM_AURORA_TICKET", where = { emerald = LILYCOVE, all = VERMILION },
    flags = { emerald = { "FLAG_ENABLE_SHIP_BIRTH_ISLAND", "FLAG_RECEIVED_AURORA_TICKET" },
              firered = { "FLAG_ENABLE_SHIP_BIRTH_ISLAND", "FLAG_RECEIVED_AURORA_TICKET" },
              leafgreen = { "FLAG_ENABLE_SHIP_BIRTH_ISLAND", "FLAG_RECEIVED_AURORA_TICKET" } } } },
  { key = "oldSeaMap", cost = 500, ticket = { item = "ITEM_OLD_SEA_MAP", where = { all = LILYCOVE },
    flags = { emerald = { "FLAG_ENABLE_SHIP_FARAWAY_ISLAND", "FLAG_RECEIVED_OLD_SEA_MAP" } } } },
  { key = "auraMew", cost = 800, dex = 151, ot = "Aura", id = 20078, level = 10, moves = { "POUND", "TRANSFORM" } },
  { key = "mystryMew", cost = 800, dex = 151, ot = "MYSTRY", id = 6930, level = 10, moves = { "POUND", "TRANSFORM" } },
  { key = "spaceDeoxys", cost = 1000, dex = 386, ot = "SPACE C", id = 10, level = 70,
    moves = { "COSMIC_POWER", "RECOVER", "PSYCHO_BOOST", "HYPER_BEAM" } },
  { key = "doelDeoxys", cost = 1000, dex = 386, ot = "DOEL", id = 28606, level = 70,
    moves = { "COSMIC_POWER", "RECOVER", "PSYCHO_BOOST", "HYPER_BEAM" } },
}
-- the 10th Anniversary ("10 ANIV", ID 00010, level 70) Pokémon, each with its own moves and item
local function aniv(dex, item, a, b, c, d)
  return { key = "aniv" .. dex, cost = 700, dex = dex, ot = "10 ANIV", id = 10, level = 70, item = item, moves = { a, b, c, d } }
end
local ANIV = {
  aniv(145, nil, "AGILITY", "DETECT", "DRILL_PECK", "CHARGE"),
  aniv(197, nil, "FAINT_ATTACK", "MEAN_LOOK", "SCREECH", "MOONLIGHT"),
  aniv(248, nil, "THRASH", "SCARY_FACE", "CRUNCH", "EARTHQUAKE"),
  aniv(157, nil, "QUICK_ATTACK", "FLAME_WHEEL", "SWIFT", "FLAMETHROWER"),
  aniv(245, nil, "GUST", "AURORA_BEAM", "MIST", "MIRROR_COAT"),
  aniv(243, nil, "QUICK_ATTACK", "SPARK", "REFLECT", "CRUNCH"),
  aniv(25, "LIGHT_BALL", "THUNDERBOLT", "THUNDER", "LIGHT_SCREEN", "AGILITY"),
  aniv(146, nil, "AGILITY", "ENDURE", "FLAMETHROWER", "SAFEGUARD"),
  aniv(381, "SOUL_DEW", "LUSTER_PURGE", "PSYCHIC", "RECOVER", "DRAGON_DANCE"),
  aniv(380, "SOUL_DEW", "MIST_BALL", "PSYCHIC", "RECOVER", "CHARM"),
  aniv(196, nil, "PSYBEAM", "PSYCH_UP", "PSYCHIC", "MORNING_SUN"),
  aniv(244, nil, "FIRE_SPIN", "STOMP", "FLAMETHROWER", "SWAGGER"),
  aniv(149, nil, "AGILITY", "SAFEGUARD", "WING_ATTACK", "OUTRAGE"),
  aniv(6, nil, "WING_ATTACK", "SLASH", "DRAGON_RAGE", "FIRE_SPIN"),
  aniv(1, nil, "SWEET_SCENT", "GROWTH", "SOLAR_BEAM", "SYNTHESIS"),
  aniv(257, nil, "BLAZE_KICK", "SLASH", "MIRROR_MOVE", "SKY_UPPERCUT"),
  aniv(9, nil, "PROTECT", "RAIN_DANCE", "SKULL_BASH", "HYDRO_PUMP"),
  aniv(144, nil, "AGILITY", "MIND_READER", "ICE_BEAM", "REFLECT"),
  aniv(65, nil, "FUTURE_SIGHT", "CALM_MIND", "PSYCHIC", "TRICK"),
  aniv(359, nil, "DOUBLE_TEAM", "SLASH", "FUTURE_SIGHT", "PERISH_SONG"),
}
-- sought-after Pokémon (at the prize corner's level) and held items, a new one each day
local HIGH_MONS = {
  { key = "m371", dex = 371, cost = 350 }, { key = "m374", dex = 374, cost = 350 }, { key = "m246", dex = 246, cost = 350 },
  { key = "m131", dex = 131, cost = 300 }, { key = "m143", dex = 143, cost = 300 }, { key = "m142", dex = 142, cost = 300 },
  { key = "m133", dex = 133, cost = 250 }, { key = "m359", dex = 359, cost = 250 }, { key = "m349", dex = 349, cost = 250 },
  { key = "m113", dex = 113, cost = 250 }, { key = "m175", dex = 175, cost = 250 },
  { key = "m1", dex = 1, cost = 300 }, { key = "m4", dex = 4, cost = 300 }, { key = "m7", dex = 7, cost = 300 },
  { key = "m152", dex = 152, cost = 300 }, { key = "m155", dex = 155, cost = 300 }, { key = "m158", dex = 158, cost = 300 },
  { key = "m252", dex = 252, cost = 300 }, { key = "m255", dex = 255, cost = 300 }, { key = "m258", dex = 258, cost = 300 },
}
local HIGH_ITEMS = {
  { key = "leftovers", id = "ITEM_LEFTOVERS", cost = 250 }, { key = "luckyEgg", id = "ITEM_LUCKY_EGG", cost = 250 },
  { key = "choiceBand", id = "ITEM_CHOICE_BAND", cost = 300 }, { key = "shellBell", id = "ITEM_SHELL_BELL", cost = 200 },
  { key = "focusBand", id = "ITEM_FOCUS_BAND", cost = 200 }, { key = "scopeLens", id = "ITEM_SCOPE_LENS", cost = 150 },
  { key = "amuletCoin", id = "ITEM_AMULET_COIN", cost = 200 }, { key = "expShare", id = "ITEM_EXP_SHARE", cost = 200 },
  { key = "kingsRock", id = "ITEM_KINGS_ROCK", cost = 150 }, { key = "quickClaw", id = "ITEM_QUICK_CLAW", cost = 150 },
  { key = "brightPowder", id = "ITEM_BRIGHT_POWDER", cost = 150 }, { key = "ppMax", id = "ITEM_PP_MAX", cost = 120 },
  { key = "sacredAsh", id = "ITEM_SACRED_ASH", cost = 300 },
}
local HIGH_ITEMS_GB = {
  { key = "leftovers", id = "LEFTOVERS", cost = 250 }, { key = "luckyEgg", id = "LUCKY_EGG", cost = 250 },
  { key = "amuletCoin", id = "AMULET_COIN", cost = 200 }, { key = "expShare", id = "EXP_SHARE", cost = 200 },
  { key = "kingsRock", id = "KINGS_ROCK", cost = 150 }, { key = "quickClaw", id = "QUICK_CLAW", cost = 150 },
  { key = "scopeLens", id = "SCOPE_LENS", cost = 150 }, { key = "focusBand", id = "FOCUS_BAND", cost = 200 },
  { key = "expAll", id = "EXP_ALL", cost = 250 }, { key = "ppUp", id = "PP_UP", cost = 100 },
  { key = "maxElixer", id = "MAX_ELIXER", cost = 150 },
}

return function(engine, deps)
  deps = deps or {}
  local Sl = { BETS = BETS, SYMBOLS = SYMBOLS, REELS = REELS, PAYS = PAYS, ROCKET = ROCKET, WILD = WILD, BONUS = BONUS,
               BONUS_PAY = BONUS_PAY, FREE = FREE, FREE_MULT = FREE_MULT,
               LINES = LINES, LINE_SETS = LINE_SETS, store = deps.save, rng = deps.rng,
               SPECIALS = SPECIALS, ANIV = ANIV, HIGH_MONS = HIGH_MONS, HIGH_ITEMS = HIGH_ITEMS, HIGH_ITEMS_GB = HIGH_ITEMS_GB }

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
  local Port = deps.port
  local function money(s)
    if Port then return Port.money(s) end
    return max(0, floor(tonumber(s and s.money) or 0))
  end
  local function setMoney(s, n)
    if Port then Port.setMoney(s, n) else s.money = n end
  end

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
      if Port then
        Port.pay(s, pays)
      else
        local Prize = engine("src.core.game3.battle.prize")
        if Prize and Prize.apply then Prize.apply(s, pays) else s.money = min(MAX_MONEY, money(s) + pays) end
      end
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
      setMoney(s, money(s) - cost)
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
      local ok, got
      if Port then ok, got = true, dex and Port.species(dex) else ok, got = pcall(P and P.speciesFromNational or error, dex) end
      sp = ok and got or false
      speciesFor[i] = sp
    end
    return sp or nil
  end

  -- ------- the prize corner

  -- (a name in the game's capitals, as the list shows them: "PP MAX" -> "PP Max", "TM24 THUNDERBOLT" ->
  -- "TM24 Thunderbolt", "HO-OH" -> "Ho-Oh", "MR. MIME" -> "Mr. Mime"; an abbreviation or a word with a
  -- digit kept)
  local KEEP = { PP = true, TM = true, HM = true, X = true }
  local function part(w)
    if w:find("%d") or KEEP[w] then return w end
    return w:sub(1, 1):upper() .. w:sub(2):lower()
  end
  local function titled(name)
    return (tostring(name):gsub("[^%s%-]+", part))
  end
  Sl.titled = titled

  local prizes
  -- (the Game Boy games' prize corner: their own items and the Pokémon there are)
  local function portPrizes()
    local out = {}
    for _, p in ipairs(deps.prizes or {}) do
      local e = { kind = p.kind, cost = p.cost }
      if p.kind == "item" then
        local id = Port.item(p.id)
        if id and (deps.hasItem == nil or deps.hasItem(id)) then
          e.id, e.name, e.desc = id, Port.itemName(id), Port.itemDesc(id)
          if deps.tmMove then
            local mv = deps.tmMove(id)
            if mv then e.name = e.name .. " " .. mv end
          end
          out[#out + 1] = e
        end
      else
        local sp = Port.species(p.dex)
        if sp then
          e.id, e.name, e.desc = sp, Port.name(sp), ""
          out[#out + 1] = e
        end
      end
    end
    return out
  end
  local function basePrizes()
    if prizes then return prizes end
    if Port then
      local out = portPrizes()
      if #out > 0 then prizes = out end
      return out
    end
    local P, I = engine("src.core.game3.pokemon"), engine("src.core.game3.items_data")
    local out = {}
    for _, p in ipairs(PRIZES) do
      local e = { kind = p.kind, cost = p.cost }
      if p.kind == "item" then
        local ok, info = pcall(I and I.info or error, p.id)
        if ok and info and info.name then
          e.id, e.name = p.id, titled(info.name)
          e.desc = ((info.description or ""):gsub("\\n", " "):gsub("\\p", " "):gsub("\n", " "))
          -- (a TM: its move's name after the number, as the TM Case shows it)
          local okT, tm = pcall(I.isTm or error, p.id)
          if okT and tm and P and P.moveFromTmItem and P.moveName then
            local okM, mv = pcall(function() return P.moveName(P.moveFromTmItem(p.id)) end)
            if okM and mv and mv ~= "" then e.name = e.name .. " " .. titled(mv) end
          end
          out[#out + 1] = e
        end
      else
        local ok, sp = pcall(P and P.speciesFromNational or error, p.dex)
        local okN, name = pcall(P and P.name or error, ok and sp or 0)
        if ok and sp and okN and name then
          e.id, e.name, e.desc = sp, titled(name), ""
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

  -- ------- the limited prizes: four that change at local midnight, the same all day for this save
  -- (seeded by its playthrough and the day, so reloading never rerolls them). A special (an event
  -- ticket or a named event Pokémon) and a 10th Anniversary Pokémon, each once per save; a sought-after
  -- Pokémon and a held item, once per day. A ticket sets what the game's own distribution sets (the
  -- ticket, the ferry's flag, its "received" flag), so the harbor sails; an event Pokémon has the
  -- event's OT, ID, level, moves and item, met in a fateful encounter (Mew and Deoxys obey)

  -- (a key -> a number, then a pick from it: the day's choice. Park-Miller steps: every product stays
  -- under 2^53, so no low bits are lost to the doubles)
  local function hash(...)
    local h = 1
    for i = 1, select("#", ...) do
      local v = tostring((select(i, ...)))
      for k = 1, #v do h = (h * 48271 + v:byte(k)) % 2147483647 end
      h = (h * 48271 + 101) % 2147483647
    end
    for _ = 1, 4 do h = (h * 48271) % 2147483647 end
    return h
  end
  local function claimed(d) d.claimed = type(d.claimed) == "table" and d.claimed or {} return d.claimed end
  local function C(kind, name)
    local ok, id = pcall(deps.const or error, kind, name)
    return ok and tonumber(id) or nil
  end
  local function flagOn(name)
    local ok, on = pcall(deps.flag or error, name)
    return ok and on == true
  end
  local function gameOf() return deps.gameId and deps.gameId() or "" end
  local function ticketFlags(t, g) return t.flags[g] or t.flags.all end

  -- a ticket is had once its ferry's flag is set; an event Pokémon once it's claimed
  local function isClaimed(s, e, d)
    if e.ticket then
      local fl = ticketFlags(e.ticket, gameOf())
      return fl and flagOn(fl[1]) or false
    end
    return claimed(d)[e.key] ~= nil
  end

  local function eventDesc(e, sp)
    local P = engine("src.core.game3.pokemon")
    local names = {}
    for i, mv in ipairs(e.moves or {}) do
      local num = C("moves", "MOVE_" .. mv)
      local ok, n = pcall(P and P.moveName or error, num)
      names[i] = ok and n and n ~= "" and titled(n) or mv
    end
    local T = deps.T
    if not T then return "" end
    return T.f("slots.event.desc", e.ot, ("%05d"):format(e.id), e.level, table.concat(names, ", "))
  end
  local function speciesName(sp)
    if Port then return Port.name(sp) end
    local P = engine("src.core.game3.pokemon")
    local ok, n = pcall(P and P.name or error, sp)
    if not (ok and n) then return "?" end
    return titled(n)
  end
  local function speciesOfDex(dex)
    if Port then return Port.species(dex) end
    local P = engine("src.core.game3.pokemon")
    local ok, sp = pcall(P and P.speciesFromNational or error, dex)
    return ok and sp or nil
  end
  local function itemEntry(id, cost)
    if Port then
      local pid = Port.item(id)
      if not (pid and (deps.hasItem == nil or deps.hasItem(pid))) then return nil end
      return { kind = "item", id = pid, cost = cost, name = Port.itemName(pid), desc = Port.itemDesc(pid) or "" }
    end
    local num = C("items", id)
    local I = engine("src.core.game3.items_data")
    local ok, info = pcall(I and I.info or error, num)
    if not (num and ok and info and info.name) then return nil end
    return { kind = "item", id = num, cost = cost, name = titled(info.name),
             desc = ((info.description or ""):gsub("\\n", " "):gsub("\\p", " "):gsub("\n", " ")) }
  end

  -- the day's four, by the playthrough's seed and the day; claimed ones say so
  local limited, limitedDay, limitedFor = nil, nil, nil
  local function build(s, day)
    local g, d = gameOf(), data()
    local seed = deps.seed and deps.seed(s) or 1
    local T = deps.T
    local out = {}
    local function pick(list, slot, ok)
      local left = {}
      for _, e in ipairs(list) do if ok(e) then left[#left + 1] = e end end
      if #left == 0 then return nil end
      return left[hash(seed, day, slot) % #left + 1]
    end
    local function add(e, entry, daily)
      if not entry then return end
      entry.limited, entry.key = true, daily and (e.key .. "@" .. day) or e.key
      entry.claimed = daily and claimed(d)[entry.key] ~= nil or isClaimed(s, e, d)
      entry.special = e
      out[#out + 1] = entry
    end
    if not Port then
      -- (the special: a ticket this game's harbor takes, or a named event Pokémon)
      local sp = pick(Sl.SPECIALS, "special", function(e)
        if e.ticket and not ticketFlags(e.ticket, g) then return false end
        if e.ticket and not C("items", e.ticket.item) then return false end
        return not isClaimed(s, e, d)
      end)
      if sp and sp.ticket then
        local entry = itemEntry(sp.ticket.item, sp.cost)
        if entry then
          entry.desc = entry.desc .. " " .. (T and T(sp.ticket.where[g] or sp.ticket.where.all) or "")
          add(sp, entry)
        end
      elseif sp then
        local spc = speciesOfDex(sp.dex)
        if spc then
          add(sp, { kind = "mon", id = spc, cost = sp.cost, level = sp.level, event = true,
                    name = T and T.f("slots.event." .. sp.key, speciesName(spc)) or speciesName(spc), desc = eventDesc(sp, spc) })
        end
      end
      -- (a 10th Anniversary Pokémon)
      local an = pick(Sl.ANIV, "aniv", function(e) return claimed(d)[e.key] == nil end)
      local anSp = an and speciesOfDex(an.dex)
      if anSp then
        add(an, { kind = "mon", id = anSp, cost = an.cost, level = an.level, event = true,
                  name = T and T.f("slots.event.aniv", speciesName(anSp)) or speciesName(anSp), desc = eventDesc(an, anSp) })
      end
    end
    -- (a sought-after Pokémon and a held item, once each this day)
    local mon = pick(Sl.HIGH_MONS, "mon", function(e) return speciesOfDex(e.dex) ~= nil end)
    if mon then
      local spc = speciesOfDex(mon.dex)
      add(mon, { kind = "mon", id = spc, cost = mon.cost, name = speciesName(spc), desc = "" }, true)
    end
    local items = Port and Sl.HIGH_ITEMS_GB or Sl.HIGH_ITEMS
    local it = pick(items, "item", function(e) return itemEntry(e.id, e.cost) ~= nil end)
    if it then add(it, itemEntry(it.id, it.cost), true) end
    -- (yesterday's daily claims forgotten)
    for k in pairs(claimed(d)) do
      local at = tostring(k):match("@(%-?%d+)$")
      if at and tonumber(at) ~= day then claimed(d)[k] = nil end
    end
    return out
  end

  local list
  -- the day's limited prizes made again when the day turns (or the save changes): call it now and
  -- then (the window: once a second), never per frame -> the seconds until the next turn
  function Sl.refresh(s, t)
    t = t or os.time()
    local day = deps.day and deps.day(t) or floor(t / 86400)
    if s and (day ~= limitedDay or s ~= limitedFor or not limited) then
      limited, limitedDay, limitedFor, list = build(s, day), day, s, nil
    end
    return deps.untilNext and deps.untilNext(t) or (86400 - t % 86400)
  end
  function Sl.prizes()
    if list then return list end
    local base = basePrizes()
    if not limited then return base end
    list = {}
    for _, p in ipairs(limited) do list[#list + 1] = p end
    for _, p in ipairs(base) do list[#list + 1] = p end
    return list
  end
  function Sl.limitedCount() return limited and #limited or 0 end

  -- an event Pokémon as the event gave it: made on a scratch session with the event's trainer, then
  -- its moves, item, met in a fateful encounter; never shiny
  local function eventMon(e, sp)
    local Party, P = engine("src.core.game3.party"), engine("src.core.game3.pokemon")
    if not (Party and P) then return nil end
    local mon
    for _ = 1, 8 do
      local scratch = { party = {}, name = e.ot, trainerId = e.id, secretId = 0,
                        dex = { seen = {}, owned = {}, caught = {} }, gender = 0 }
      local pid = (roll(65536) - 1) * 65536 + (roll(65536) - 1)
      local ok, given, _, m = pcall(Party.giveMon, scratch, sp, e.level, nil, { fixedPersonality = pid })
      if ok and given and type(m) == "table" then
        mon = m
        local okS, shiny = pcall(P.isShiny, m)
        if not (okS and shiny) then break end
      end
    end
    if not mon then return nil end
    mon.ot, mon.otName, mon.otId, mon.otSecretId, mon.otGender = e.ot, e.ot, e.id, 0, 0
    for i, mv in ipairs(e.moves or {}) do
      local num = C("moves", "MOVE_" .. mv)
      if num and P.replaceMove then pcall(P.replaceMove, mon, i, num) end
    end
    if e.item then
      local item = C("items", "ITEM_" .. e.item)
      if item then mon.item, mon.heldItem = item, item end
    end
    mon.metLocation, mon.metLevel, mon.language, mon.modernFatefulEncounter = 0xFF, e.level, 2, true
    mon.hp = nil
    pcall(P.applyStats, mon)
    mon.hp = mon.maxHp
    return mon
  end
  -- a Pokémon to the player: the party, else the PC; seen and caught in the Pokédex
  local function place(s, mon, sp)
    local where
    s.party = s.party or {}
    if #s.party < 6 then
      s.party[#s.party + 1] = mon
      where = "party"
    else
      local St = engine("src.core.game3.storage")
      local ok, sent = pcall(St and St.sendMonToPC or error, s, mon)
      where = ok and sent and "pc" or nil
    end
    if where then
      local Dex = engine("src.core.game3.dex")
      s.dex = s.dex or { seen = {}, owned = {}, caught = {} }
      pcall(Dex and Dex.handleSetPokedexFlag or error, s.dex, sp, true, mon.personality)
    end
    return where
  end

  function Sl.redeem(s, i)
    local p = Sl.prizes()[i]
    if not (s and p) then return false, "tickets" end
    local d = data()
    if p.claimed then return false, "claimed" end
    if d.tickets < p.cost then return false, "tickets" end
    local where
    local e = p.limited and p.special
    if e and e.ticket then
      -- (the ticket and the flags its distribution sets)
      local Bag = engine("src.core.game3.bag")
      if not Bag then return false, "bag_full" end
      s.bag = s.bag or Bag.new()
      local okC, can = pcall(Bag.canAdd, s.bag, p.id, 1)
      if not (okC and can) then return false, "bag_full" end
      local okA, added = pcall(Bag.add, s.bag, p.id, 1)
      if not (okA and added) then return false, "bag_full" end
      for _, f in ipairs(ticketFlags(e.ticket, gameOf()) or {}) do pcall(deps.setFlag or error, f, true) end
      where = "bag"
    elseif e and e.ot then
      local mon = eventMon(e, p.id)
      if not mon then return false, "no_room" end
      where = place(s, mon, p.id)
      if not where then return false, "no_room" end
    elseif Port then
      if p.kind == "item" then
        if not (Port.canGive(s, p.id, 1) and Port.giveItem(s, p.id, 1)) then return false, "bag_full" end
        where = "bag"
      else
        local mon = Port.make(p.id, Sl.level(s))
        where = mon and Port.give(s, mon) or nil
        if not where then return false, "no_room" end
      end
    elseif p.kind == "item" then
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
    if p.limited then
      claimed(d)[p.key] = true
      p.claimed = true
    end
    save(d)
    return true, where
  end

  return Sl
end
