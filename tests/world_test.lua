-- Standalone: luajit mods/woob_os/tests/world_test.lua [game] (from the gen1recomp root; needs that
-- cart imported, FireRed by default).
--
-- The apps tied to play: the Bank (the wallet's overflow through the engine's Prize.apply, deposits,
-- withdrawals, interest, its window), and the journal, Challenges, Errands, the daily swarm and the
-- News as they're added.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GAME = arg[1] or "firered"

local clock = 100
local function noop() end
local fontOf = {}
local function newFont(px)
  local f = fontOf[px]
  if not f then
    f = { getWidth = function(_, s) return #tostring(s) * px * 0.55 end, getHeight = function() return px * 1.2 end,
          getWrap = function(_, s) return 0, { s } end }
    fontOf[px] = f
  end
  return f
end
local G = setmetatable({ newFont = newFont, getFont = function() return newFont(12) end,
                         newMesh = function() error("no meshes headless") end },
                       { __index = function() return noop end })
love = { timer = { getTime = function() return clock end }, graphics = G }

require("src.core.GameVersion").set(GAME)
do
  local CacheBlob = require("src.import.CacheBlob")
  require("src.core.game3.dataset").cache = function()
    return {
      read = function(_, rel)
        local f = io.open(GAME .. "/" .. rel, "rb")
        if not f then return nil end
        local bytes = f:read("*a")
        f:close()
        return CacheBlob.decode(rel, bytes)
      end,
      exists = function(_, rel)
        local f = io.open(GAME .. "/" .. rel, "rb")
        if f then f:close() end
        return f ~= nil
      end,
    }
  end
end

local run = T.sdk.loadMods({ "mods/woob_os" }, { data = {}, generation = 3 })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
run.loader.events:emit("game.ready", {})
local X = run.loader.exports.woob_os
local Nt, Apps, K = X._test.notify, X._test.apps, X._test.kit
local Settings = X._test.settings
Settings.cache = { read = function() return nil end, write = function() end }

local Storage, Bag = require("src.core.game3.storage"), require("src.core.game3.bag")
local ItemsData = require("src.core.game3.items_data")
local Party = require("src.core.game3.party")
local PokeG = require("src.core.game3.pokemon")
local Prize = require("src.core.game3.battle.prize")
local function spOf(nat) return PokeG.speciesFromNational(nat) end
local function newSession()
  local s = { name = "WOS", playerName = "WOS", bag = Bag.new(), storage = Storage.new(), party = {}, money = 3000 }
  ItemsData.ensureModel(s)
  s.trainerId, s.secretId = 4321, 8765
  s.dex = { seen = {}, owned = {}, caught = {} }
  s.meta = { playthroughId = "world-run" }
  return s
end
local s = newSession()
require("src.core.game3.runtime").getSession = function() return s end
Party.giveMon(s, spOf(16), 10)
Party.giveMon(s, spOf(19), 12)

local fakeSave = { data = {} }
function fakeSave.get(self, k) return self.data[k] end
function fakeSave.set(self, k, v) self.data[k] = v end
local tnow = 1800000000

local function input(press)
  local p = {}
  for _, k in ipairs(press or {}) do p[k] = true end
  return { wasPressed = function(_, k) return p[k] == true end, isDown = function() return false end }
end
local NONE = {}
local function nav(dir) return setmetatable({ [dir] = true }, { __index = NONE }) end
local VP = { width = 480, height = 320 }
local PAGE = { height = 160, minWidth = 200, maxWidth = 300, portraitWidth = 160, portraitHeight = 260, portraitAspect = 0.9 }
local function drawWin(W, portrait)
  clock = clock + 1 / 60
  K.frame(G, VP, PAGE, clock)
  W.draw(portrait and { 0, 0, 115, 138 } or { 0, 0, 260, 130 }, clock, portrait)
end
local function garbageOf(n, fn)
  local best = math.huge
  for _ = 1, 2 do
    collectgarbage("collect")
    collectgarbage("stop")
    local kb = collectgarbage("count")
    for _ = 1, n do fn() end
    best = math.min(best, (collectgarbage("count") - kb) / n)
    collectgarbage("restart")
  end
  return best
end

-- ------- the Bank

local Bk = X._test.bank
T.check(Bk ~= nil and Apps.byId("bank") ~= nil, "the Bank and its app")
if Bk then
  Bk.store, Bk.now = fakeSave, function() return tnow end
  -- (the wallet's overflow: every gain goes through the engine's Prize.apply)
  Nt.reset()
  s.money = 999000
  local gained = Prize.apply(s, 5000)
  T.eq(s.money, 999999, "the wallet fills to the game's cap")
  T.eq(Bk.balance(), 4001, "the rest goes into the bank")
  T.eq(gained, 5000, "and all of it counts as gained")
  T.check(Nt.list()[1] and Nt.list()[1].kind == "bank" and Nt.list()[1].text:find("4,001", 1, true),
    "a notification says how much (" .. tostring(Nt.list()[1] and Nt.list()[1].text) .. ")")
  Prize.apply(s, 100)
  T.check(Bk.log()[1].kind == "over" and Bk.log()[1].amount == 4101 and #Bk.log() == 1,
    "overflow moments apart: one line, added up")
  s.money = 1000
  T.eq(select(1, Prize.apply(s, 500)), 500, "with room in the wallet: nothing banked")
  T.eq(Bk.balance(), 4101, "(the bank as it was)")
  -- (deposits and withdrawals)
  local ok, moved = Bk.deposit(s, 1000)
  T.check(ok and moved == 1000 and s.money == 500 and Bk.balance() == 5101, "deposit: from the wallet into the bank")
  ok, moved = Bk.deposit(s, 9999)
  T.check(ok and moved == 500 and s.money == 0, "deposit more than the wallet has: all of it")
  T.check(not Bk.deposit(s, 10), "an empty wallet: nothing to deposit")
  ok, moved = Bk.withdraw(s, 2000)
  T.check(ok and moved == 2000 and s.money == 2000 and Bk.balance() == 3601, "withdraw: into the wallet")
  s.money = 999990
  ok, moved = Bk.withdraw(s, 2000)
  T.check(ok and moved == 9 and s.money == 999999, "withdraw: only what fits in the wallet")
  local okF, why = Bk.withdraw(s, 10)
  T.check(not okF and why == "wallet", "a full wallet: nothing withdrawn (" .. tostring(why) .. ")")
  -- (interest: from the first visit, each whole day, a week at most)
  fakeSave.data.bank.balance = 1000000
  T.eq(Bk.settle(s, tnow), 0, "the first visit starts the count")
  T.eq(Bk.settle(s, tnow + 86400 * 3 + 5), 3003, "three days: a tenth of a percent a day, day on day")
  T.eq(Bk.balance(), 1003003, "paid in")
  T.eq(Bk.settle(s, tnow + 86400 * 3 + 50), 0, "the same day again: nothing")
  fakeSave.data.bank.balance = 900000000
  T.eq(Bk.settle(s, tnow + 86400 * 30), 7 * 5000, "a month away: a week's, at most 5,000 a day")
  -- (kept in the save: another save, another bank)
  local mine = fakeSave.data.bank
  fakeSave.data.bank = nil
  T.eq(Bk.balance(), 0, "another save: its own bank")
  fakeSave.data.bank = mine

  -- (the window)
  s.money = 50000
  fakeSave.data.bank.balance = 120000
  local ctx = { session = s, mode = "pc", app = "bank", rows = {} }
  local W = Apps.byId("bank").window(ctx, X._test.env)
  local st = W.state
  drawWin(W, false)
  W.input(input({ "select" }), NONE)
  T.eq(st.amount, 50000, "SELECT: all of the wallet")
  W.input(input({ "a" }), NONE)
  T.check(s.money == 0 and Bk.balance() == 170000 and st.amount == 0, "A: deposited")
  W.input(input({ "r" }), NONE)
  T.eq(st.mode, "out", "R: Withdraw")
  W.input(input({}), nav("up"))
  T.check(st.keys and st.amount == 0, "the first press of the D-pad only shows the digit")
  W.input(input({}), nav("left"))
  W.input(input({}), nav("left"))
  W.input(input({}), nav("up"))
  W.input(input({}), nav("up"))
  T.eq(st.amount, 200, "Left to the hundreds, Up twice: 200")
  W.tap(2011)
  T.eq(st.amount, 1200, "a tap on +1,000")
  W.tap(2020)
  T.eq(st.amount, 0, "Clear")
  W.tap(2014)
  T.eq(st.amount, 170000, "All: the bank's (it all fits)")
  W.tap(2021)
  T.check(s.money == 170000 and Bk.balance() == 0, "the button: withdrawn")
  T.check(W.input(input({ "b" }), NONE) == false, "B closes")
  local okD, err = pcall(function()
    for _ = 1, 3 do drawWin(W, false) drawWin(W, true) end
  end)
  T.check(okD, "draws wide and upright (" .. tostring(err) .. ")")
  W.input(input({}), nav("up"))
  -- (headless, the game's glyph draw makes garbage of its own: stood in for while measuring)
  local FrlgFont = require("src.ui.game3.frlg_font")
  local realGlyph = FrlgFont.drawGlyph
  FrlgFont.drawGlyph = function() return 7 end
  local kb
  for _ = 1, 2 do kb = garbageOf(60, function() drawWin(W, false) end) end
  FrlgFont.drawGlyph = realGlyph
  T.check(kb < 0.5, ("next to no garbage (%.3f KB a frame)"):format(kb))
end

-- ------- the journal: the engine's events counted for the week, the notable ones logged

local Jr, Ch = X._test.journal, X._test.challenges
T.check(Jr ~= nil and Ch ~= nil, "the journal and Challenges")
if Jr and Ch then
  Jr.store, Jr.now = fakeSave, function() return tnow end
  Ch.store, Ch.now = fakeSave, function() return tnow end
  local Runtime = require("src.mods.Runtime")
  -- (through the engine's own event bus, as the game raises them)
  local ev = run.loader.events
  local okC, Cs = pcall(require("src.core.game3.constants").of, GAME)
  local LEADER = okC and Cs and tonumber(Cs:id("trainer_classes", "TRAINER_CLASS_LEADER")) or -1
  local squirtle, geodude, onix, pidgey = spOf(7), spOf(74), spOf(95), spOf(16)
  local function battler(side, id, sp) return { side = side, id = id, species = sp, mon = { species = sp } } end
  -- a Gym battle, as the engine raises it: Squirtle's super-effective Bubble takes Geodude (turn 1),
  -- Onix's Rock Throw drops Pidgey (turn 2), Squirtle's critical Water Gun finishes Onix (turn 3)
  s.map = "FR_PEWTER_CITY_GYM"
  local gb = { wild = false, trainerName = "BROCK", trainerClassName = "LEADER", trainerClass = LEADER, turn = 0,
               foeParty = { { species = geodude }, { species = onix } } }
  local mine, theirs = battler("player", 0, squirtle), battler("enemy", 1, geodude)
  gb.player, gb.enemy = mine, theirs
  ev:emit("battle.started", { kind = "trainer", battle = gb })
  gb.turn = 1
  ev:emit("battle.damage_dealt", { battle = gb, user = mine, target = theirs, targetId = 1, move = { num = 145 }, typeMult = 20 })
  ev:emit("battle.fainted", { battle = gb, battler = theirs, sideName = "enemy", battlerId = 1 })
  theirs = battler("enemy", 1, onix)
  gb.enemy = theirs
  ev:emit("battle.battler_switched", { battle = gb, sideName = "enemy", battler = theirs, speciesId = onix })
  gb.turn = 2
  local bird = battler("player", 0, pidgey)
  gb.player = bird
  ev:emit("battle.battler_switched", { battle = gb, sideName = "player", battler = bird, speciesId = pidgey })
  ev:emit("battle.damage_dealt", { battle = gb, user = theirs, target = bird, targetId = 0, move = { num = 88 }, typeMult = 10 })
  ev:emit("battle.fainted", { battle = gb, battler = bird, sideName = "player", battlerId = 0 })
  gb.turn = 3
  gb.player = mine
  ev:emit("battle.battler_switched", { battle = gb, sideName = "player", battler = mine, speciesId = squirtle })
  -- (their own recoil on the attacker doesn't count as a hit by the other side)
  ev:emit("battle.damage_dealt", { battle = gb, user = mine, target = mine, targetId = 0, move = { num = 36 }, typeMult = 10 })
  ev:emit("battle.damage_dealt", { battle = gb, user = mine, target = theirs, targetId = 1, move = { num = 55 }, typeMult = 10, crit = true })
  ev:emit("battle.fainted", { battle = gb, battler = theirs, sideName = "enemy", battlerId = 1 })
  ev:emit("battle.ended", { result = "win", battle = gb })
  local g = Jr.gym()
  T.check(g ~= nil and g.me == 2 and g.them == 1 and g.turns == 3, "a Gym won: its box score, 2-1 in 3 turns")
  T.check(g ~= nil and #g.beats == 3 and g.beats[1].k == "ko" and g.beats[1].sup and g.beats[1].mv == 145
    and g.beats[1].by == squirtle and g.beats[1].v == geodude and g.beats[1].t == 1,
    "a knockout: who, the move, super effective, the turn")
  T.check(g ~= nil and g.beats[2].k == "down" and g.beats[2].by == onix and g.beats[2].mv == 88 and g.beats[2].v == pidgey,
    "a setback: their Onix's Rock Throw")
  T.check(g ~= nil and g.fin == g.beats[3] and g.fin.crit and g.fin.mv == 55 and g.fin.by == squirtle and g.fin.v == onix,
    "the finishing blow: a critical Water Gun")
  T.check(g ~= nil and g.map == "FR_PEWTER_CITY_GYM" and g.lead == squirtle and g.foeLead == geodude and g.name == "BROCK",
    "where, the Leader, the leads")
  T.check(g ~= nil and #g.mine == 2 and #g.theirs == 2, "both teams (" .. (g and #g.mine or 0) .. ", " .. (g and #g.theirs or 0) .. ")")
  T.eq(#Jr.wins(), 0, "a Gym Leader: the Gym's box score, not one of the trainers'")
  T.check(Jr.log()[1] and Jr.log()[1].k == "trainer" and Jr.log()[1].name == "BROCK", "the trainer beaten, logged")
  -- (the Badge: its flag, set after the battle; other flags, or one cleared, nothing)
  ev:emit("flag.changed", { name = "FLAG_SYS_POKEDEX_GET", value = true })
  ev:emit("flag.changed", { name = "FLAG_BADGE01_GET", value = false })
  T.check(Jr.log()[1].k == "trainer" and not Jr.gym().badge, "other flags: nothing")
  ev:emit("flag.changed", { name = "FLAG_BADGE01_GET", value = true })
  T.check(Jr.gym().badge == true and Jr.log()[1].k == "badge", "a Badge's flag: the Gym's Badge, logged")
  -- (two trainers after it, and a third: the last two kept, newest first; a clean sweep, a 1-1)
  local function quick(nm, cls, mySp, foeSp, turnsN, map, lost)
    s.map = map
    tnow = tnow + 10
    local q = { wild = false, trainerName = nm, trainerClassName = cls, trainerClass = 1, turn = 0, foeParty = { { species = foeSp } } }
    local a, b = battler("player", 0, mySp), battler("enemy", 1, foeSp)
    q.player, q.enemy = a, b
    ev:emit("battle.started", { kind = "trainer", battle = q })
    q.turn = turnsN
    if lost then
      ev:emit("battle.damage_dealt", { battle = q, user = b, target = a, targetId = 0, move = { num = 33 }, typeMult = 10 })
      ev:emit("battle.fainted", { battle = q, battler = a, sideName = "player", battlerId = 0 })
    end
    ev:emit("battle.damage_dealt", { battle = q, user = a, target = b, targetId = 1, move = { num = 33 }, typeMult = 10 })
    ev:emit("battle.fainted", { battle = q, battler = b, sideName = "enemy", battlerId = 1 })
    ev:emit("battle.ended", { result = "win", battle = q })
  end
  quick("JOEY", "YOUNGSTER", pidgey, spOf(19), 2, "FR_ROUTE22")
  quick("RICK", "BUG CATCHER", squirtle, spOf(10), 4, "FR_VIRIDIAN_FOREST", true)
  quick("BEN", "HIKER", squirtle, geodude, 1, "FR_ROUTE3")
  local wins = Jr.wins()
  T.check(#wins == 2 and wins[1].name == "BEN" and wins[2].name == "RICK", "the last two trainers beaten, newest first")
  T.check(wins[2].me == 1 and wins[2].them == 1 and wins[2].fin and wins[2].fin.mv == 33 and #wins[2].mine == 1,
    "a win with a loss in it: 1-1, the finisher")
  T.check(Jr.gym().name == "BROCK", "the Gym kept through them")
  -- (a wild battle isn't followed; a lost one, a link battle: no box score)
  ev:emit("battle.started", { kind = "wild", battle = { wild = true, turn = 0 } })
  ev:emit("battle.ended", { result = "win", battle = { wild = true } })
  ev:emit("battle.ended", { result = "lose", battle = { wild = false } })
  ev:emit("battle.ended", { result = "win", battle = { link = true } })
  T.check(Jr.count("trainer") == 4 and Jr.count("wild") == 1 and #Jr.wins() == 2 and Jr.wins()[1].name == "BEN",
    "battles won: four trainers, a wild one (not lost, not a link)")
  s.map = "FR_ROUTE1"
  tnow = tnow + 10
  ev:emit("pokemon.caught", { speciesId = squirtle, isNew = true, mon = { species = squirtle } })
  ev:emit("pokemon.caught", { speciesId = spOf(16), isNew = false, ballId = 3, mon = { species = spOf(16), level = 7 } })
  T.check(Jr.count("caught") == 2 and Jr.count("new") == 1, "catches: two, one new to the Pokédex")
  local c = Jr.catch()
  T.check(c ~= nil and c.sp == spOf(16) and c.map == "FR_ROUTE1" and c.lv == 7 and c.ball == 3 and not c.new,
    "the latest catch: where, the level, the Ball")
  T.eq(Jr.count("t11"), 1, "by type: one Water")
  T.check(Jr.count("t0") == 1 and Jr.count("t2") == 1, "Pidgey: Normal and Flying, once each")
  run.loader.events:emit("egg.hatched", { mon = { species = spOf(172) } })
  run.loader.events:emit("pokemon.evolved", { fromSpeciesId = spOf(16), toSpeciesId = spOf(17) })
  run.loader.events:emit("pokemon.level_up", { level = 11 })
  T.check(Jr.count("hatched") == 1 and Jr.count("evolved") == 1 and Jr.count("levels") == 1, "a hatch, an evolution, a level")
  for _ = 1, 25 do run.loader.events:emit("world.stepped", { mapId = "X" }) end
  T.eq(Jr.count("steps"), 25, "steps")
  run.loader.events:emit("map.entered", { mapId = "FR_PALLET_TOWN" })
  run.loader.events:emit("map.entered", { mapId = "FR_ROUTE1" })
  run.loader.events:emit("map.entered", { mapId = "FR_PALLET_TOWN" })
  T.eq(Jr.count("places"), 2, "places: each once a week")
  local used = Runtime.call("item.use", function() return true, "used", "" end, {}, nil, 13, 1, s.bag)
  Runtime.call("item.use", function() return false end, {}, nil, 13, 1, s.bag)
  T.check(used == true and Jr.count("items") == 1, "an item used (the hook's answer passed on; a refused one not counted)")
  T.check(Jr.log()[1].k == "evolve" and Jr.log()[2].k == "hatch", "the log, newest first")
  -- (a new week: the counts from nothing, the log and the box scores kept)
  local w0 = Jr.week(tnow)
  local logN = #Jr.log()
  tnow = tnow + 7 * 86400
  T.check(Jr.week(tnow) == w0 + 1 and Jr.count("trainer") == 0, "a new week: counted from nothing")
  T.check(#Jr.log() == logN and logN == 9 and #Jr.wins() == 2 and Jr.gym() and Jr.catch(),
    "the log kept (" .. logN .. ": four trainers, the Badge, two catches, the hatch, the evolution), the box scores too")
  -- (a week starts on a Monday, local time)
  local okD, d = pcall(os.date, "*t", (Jr.week(tnow) * 7 - 3) * 86400 + 43200 - (Jr.localTime(tnow) - tnow))
  T.check(okD and d.wday == 2, "weeks start on Mondays (" .. tostring(okD and d.wday) .. ")")

  -- ------- Challenges

  local list = Ch.list(s)
  T.eq(#list, 5, "five goals a week")
  local kinds = {}
  for _, e in ipairs(list) do kinds[#kinds + 1] = e.kind .. ":" .. tostring(e.goal) end
  local again = {}
  fakeSave.data.challenges = nil
  for _, e in ipairs(Ch.list(s)) do again[#again + 1] = e.kind .. ":" .. tostring(e.goal) end
  T.eq(table.concat(again, " "), table.concat(kinds, " "), "the same save and week: the same five")
  tnow = tnow + 7 * 86400
  local nextWeek = {}
  for _, e in ipairs(Ch.list(s)) do nextWeek[#nextWeek + 1] = e.kind .. ":" .. tostring(e.goal) end
  T.check(table.concat(nextWeek, " ") ~= table.concat(kinds, " "), "another week: another five")
  local allText = true
  for _, e in ipairs(Ch.list(s)) do
    local t = Ch.text(e)
    if type(t) ~= "string" or t:find("challenges.", 1, true) or (e.goal > 1 and not t:find(tostring(e.goal), 1, true)) then allText = false end
  end
  T.check(allText, "each has its words, with its goal")
  T.eq(X._test.env.typeName(14), "Psychic", "a type's name in full (the game keeps \"PSYCHC\")")
  -- (finish the first: its count raised as the journal would)
  list = Ch.list(s)
  local e1 = list[1]
  local key = e1.kind == "type" and ("t" .. e1.param) or Ch.KINDS and ({ trainer = "trainer", wild = "wild", catch = "caught",
    new = "new", hatch = "hatched", evolve = "evolved", items = "items", steps = "steps", places = "places", levels = "levels",
    swarm = "swarm" })[e1.kind]
  T.check(not Ch.done(e1) and not Ch.claim(s, 1), "not done: nothing to claim")
  fakeSave.data.journal.c[key] = e1.goal + 3
  T.check(Ch.done(e1) and Ch.progress(e1) == e1.goal, "done (the count shown no higher than the goal)")
  Nt.reset()
  Ch.check(s)
  Ch.check(s)
  T.check(#Nt.list() == 1 and Nt.list()[1].kind == "challenge" and Nt.list()[1].app == "challenges",
    "done: a notification, once")
  T.eq(Ch.waiting(s), 1, "a reward waiting (the count on the icon)")
  local money0, bag0 = s.money, Bag.get(s.bag, e1.reward.item or 0)
  s.money = 1000
  money0 = 1000
  local ok, r = Ch.claim(s, 1)
  T.check(ok and (r.money and s.money == money0 + r.money or (Bag.get(s.bag, r.item) or 0) == (bag0 or 0) + r.n),
    "claimed: paid (" .. tostring(r and (r.money or r.item)) .. ")")
  T.check(not Ch.claim(s, 1), "claimed once")
  T.check(not Ch.bonusReady(s), "the bonus waits for all five")
  for i = 2, 5 do
    local e = list[i]
    local k2 = e.kind == "type" and ("t" .. e.param) or ({ trainer = "trainer", wild = "wild", catch = "caught",
      new = "new", hatch = "hatched", evolve = "evolved", items = "items", steps = "steps", places = "places",
      levels = "levels", swarm = "swarm" })[e.kind]
    fakeSave.data.journal.c[k2] = e.goal
  end
  for i = 2, 5 do Ch.claim(s, i) end
  T.check(Ch.bonusReady(s), "all five claimed: the bonus")
  local b = Ch.bonus(s)
  local have = Bag.get(s.bag, b.item) or 0
  T.check(Ch.claimBonus(s) and (Bag.get(s.bag, b.item) or 0) == have + b.n, "the bonus: into the Bag")
  T.eq(Ch.waiting(s), 0, "nothing waiting")
  -- (a full Bag: the reward waits)
  local fullBag = Bag.canAdd
  Bag.canAdd = function() return false end
  fakeSave.data.challenges.list[1].claimed = false
  local item = fakeSave.data.challenges.list[1].reward.item
  local okB, why = Ch.claim(s, 1)
  Bag.canAdd = fullBag
  if item then T.check(not okB and why == "bag_full", "a full Bag: it waits (" .. tostring(why) .. ")")
  else T.check(okB, "(money needs no room)") end
  T.check(Ch.endsIn(tnow) > 0 and Ch.endsIn(tnow) <= 7 * 86400, "the week's countdown")

  -- (the window)
  fakeSave.data.challenges = nil
  local W = Apps.byId("challenges").window({ session = s, mode = "pc", app = "challenges", rows = {} }, X._test.env)
  local cst = W.state
  local okW, err = pcall(function() for _ = 1, 3 do drawWin(W, false) drawWin(W, true) end end)
  T.check(okW, "Challenges draws wide and upright (" .. tostring(err) .. ")")
  local first = Ch.list(s)[1]
  local k1 = first.kind == "type" and ("t" .. first.param) or ({ trainer = "trainer", wild = "wild", catch = "caught",
    new = "new", hatch = "hatched", evolve = "evolved", items = "items", steps = "steps", places = "places", levels = "levels",
    swarm = "swarm" })[first.kind]
  fakeSave.data.journal.c[k1] = first.goal
  W.input(input({ "a" }), NONE)
  T.check(first.claimed, "A on the first: claimed")
  W.input(input({}), nav("down"))
  T.eq(cst.cursor, 2, "Down: the next goal (A already showed the chosen one)")
  T.check(W.input(input({ "b" }), NONE) == false, "B closes")
  local kb
  for _ = 1, 2 do kb = garbageOf(60, function() drawWin(W, false) end) end
  T.check(kb < 0.5, ("Challenges: next to no garbage (%.3f KB a frame)"):format(kb))
end

-- ------- Errands

local Er, Bx = X._test.errands, X._test.bx
T.check(Er ~= nil and Apps.byId("errands") ~= nil, "Errands and its app")
if Er then
  Er.store, Er.now = fakeSave, function() return tnow end
  local es = newSession()
  es.money = 1000
  require("src.core.game3.runtime").getSession = function() return es end
  Party.giveMon(es, spOf(16), 10)
  Party.giveMon(es, spOf(25), 12)
  -- (two into the box: given, then moved there)
  for _, g in ipairs({ { 74, 20 }, { 41, 9 } }) do
    local _, _, m = Party.giveMon(es, spOf(g[1]), g[2])
    table.remove(es.party)
    Storage.sendMonToPC(es, m)
  end
  local function boxAddrOf(nat)
    for i = 1, Bx.SLOTS do
      local a = Bx.addr("box", i, 1)
      local m = Bx.get(es, a)
      if m and tonumber(m.species or m.speciesId) == spOf(nat) then return Bx.addr("box", i, 1) end
    end
  end
  T.check(boxAddrOf(74) ~= nil and #Bx.party(es) == 2, "(a party of two, two in the box)")
  -- (the board: three jobs, the same all six hours)
  local b1 = Er.board(es, tnow)
  local keys = b1[1].key .. b1[2].key .. b1[3].key
  T.check(#b1 == 3 and b1[1].job ~= b1[2].job and b1[2].job ~= b1[3].job, "three different jobs on the board")
  T.eq(Er.board(es, tnow + 60)[1].job, b1[1].job, "the same board a minute on")
  local b2 = Er.board(es, tnow + 6 * 3600)
  T.check(b2[1].key ~= b1[1].key, "a new board six hours on")
  b1 = Er.board(es, tnow)
  -- (who may go)
  local ok, why = Er.send(es, b1[1].key, { Bx.addr("party", 1), Bx.addr("party", 2) })
  T.check(not ok and why == "last", "not the whole party (" .. tostring(why) .. ")")
  local eggAddr = boxAddrOf(41)
  Bx.get(es, eggAddr).isEgg = true
  ok, why = Er.send(es, b1[1].key, { eggAddr })
  T.check(not ok and why == "egg", "an Egg stays home (" .. tostring(why) .. ")")
  Bx.get(es, eggAddr).isEgg = nil
  -- (a team of two: Pikachu from the party, Geodude from the box)
  local geo = boxAddrOf(74)
  local geoMon, pika = Bx.get(es, geo), Bx.get(es, Bx.addr("party", 2))
  local lv0 = tonumber(pika.level)
  local mine = nil
  for _, p in ipairs(b1) do if p.job == "mine" or p.job == "power" then mine = p end end
  local post = mine or b1[1]
  ok, why = Er.send(es, post.key, { Bx.addr("party", 2), geo })
  T.check(ok, "sent (" .. tostring(why) .. ")")
  T.check(#Bx.party(es) == 1 and Bx.get(es, geo) == nil, "they've left the party and the box")
  local e = Er.out()[1]
  T.check(e and #e.team == 2 and e.ends == tnow + post.hours * 3600 and Er.GRADE[e.grade], "out: the team, its time, its grade")
  if mine then T.check(e.grade ~= "ok", "a team that suits the job does better (" .. tostring(e.grade) .. ")") end
  T.check(Er.board(es, tnow)[1].key == b1[1].key and (function()
    for _, p in ipairs(Er.board(es, tnow)) do if p.key == post.key then return p.taken end end
  end)(), "the job's taken")
  T.check(not Er.send(es, post.key, { Bx.addr("party", 1) }), "a job only once")
  -- (back in time, and a notification)
  Nt.reset()
  Er.settle(es, tnow + post.hours * 3600 - 5)
  T.check(not e.back and #Nt.list() == 0, "not back early")
  T.check(not Er.collect(es, 1), "nothing to collect yet")
  tnow = tnow + post.hours * 3600 + 1
  Er.settle(es)
  T.check(e.back and Nt.list()[1] and Nt.list()[1].kind == "errand" and Nt.list()[1].app == "errands", "back: a notification")
  T.eq(Er.waiting(), 1, "a team waiting (the count on the icon)")
  -- (no room: nothing lost)
  local realGet = Bx.get
  local realParty = Bx.party
  Bx.party = function() return { {}, {}, {}, {}, {}, {} } end
  Bx.get = function(s2, a) if a.loc == "box" then return {} end return realGet(s2, a) end
  local okR, whyR = Er.collect(es, 1)
  Bx.get, Bx.party = realGet, realParty
  T.check(not okR and whyR == "no_room" and #Er.out() == 1, "no room for them: they wait (" .. tostring(whyR) .. ")")
  -- (collected: money, the item, EXP, home)
  local money0 = es.money
  local item, n = e.reward.item, e.reward.n
  local have = Bag.get(es.bag, item) or 0
  local okC, done, gained = Er.collect(es, 1)
  T.check(okC and #Er.out() == 0, "collected")
  T.eq(es.money, money0 + done.reward.money, "the money")
  T.eq(Bag.get(es.bag, item), have + n, "the item")
  T.check(tonumber(pika.level) > lv0 and gained[1] + gained[2] > 0, "EXP: levels gained (" .. lv0 .. " -> " .. tostring(pika.level) .. ")")
  T.check(#Bx.party(es) == 3, "home in the party")
  T.eq(Er.log()[1].job, post.job, "logged")
  -- (called back: home with nothing)
  local other
  for _, p in ipairs(Er.board(es, tnow)) do if not p.taken then other = p end end
  local m0 = es.money
  T.check(other and Er.send(es, other.key, { Bx.addr("party", 3) }), "another team out")
  T.check(Er.recall(es, 1) and #Er.out() == 0 and es.money == m0 and #Bx.party(es) == 3, "called back: home, nothing paid")

  -- (the window)
  local W = Apps.byId("errands").window({ session = es, mode = "pc", app = "errands", rows = {} }, X._test.env)
  local est = W.state
  local okW, err = pcall(function() for _ = 1, 3 do drawWin(W, false) drawWin(W, true) end end)
  T.check(okW, "Errands draws its jobs (" .. tostring(err) .. ")")
  -- (a free job chosen, the picker, a team, Send)
  for i, p in ipairs(Er.board(es, tnow)) do if not p.taken then est.job = i end end
  W.input(input({ "a" }), NONE)
  T.check(est.picking and #est.rows >= 3, "A: the picker (the party, then the box)")
  okW, err = pcall(function() for _ = 1, 2 do drawWin(W, false) drawWin(W, true) end end)
  T.check(okW, "draws the picker (" .. tostring(err) .. ")")
  W.input(input({ "a" }), NONE)
  T.eq(#est.team, 1, "A: one on the team")
  T.check(est.grade ~= nil, "the grade they'd earn")
  W.input(input({ "a" }), NONE)
  T.eq(#est.team, 0, "A again: off the team")
  W.input(input({}), nav("down"))
  W.input(input({ "a" }), NONE)
  W.input(input({ "start" }), NONE)
  T.check(not est.picking and est.tab == "out" and #Er.out() == 1, "START: sent, the Out tab")
  okW, err = pcall(function() for _ = 1, 2 do drawWin(W, false) drawWin(W, true) end end)
  T.check(okW, "draws the teams out (" .. tostring(err) .. ")")
  W.input(input({ "select" }), NONE)
  T.eq(#Er.out(), 1, "SELECT once: asked first")
  W.input(input({ "select" }), NONE)
  T.eq(#Er.out(), 0, "SELECT again: called back")
  T.check(W.input(input({ "b" }), NONE) == false, "B closes")
  local FrlgFont = require("src.ui.game3.frlg_font")
  local realGlyph = FrlgFont.drawGlyph
  FrlgFont.drawGlyph = function() return 7 end
  local kb
  est.tab = "jobs"
  for _ = 1, 2 do kb = garbageOf(60, function() drawWin(W, false) end) end
  FrlgFont.drawGlyph = realGlyph
  T.check(kb < 0.5, ("Errands: next to no garbage (%.3f KB a frame)"):format(kb))
  require("src.core.game3.runtime").getSession = function() return s end
end

-- ------- the daily swarm

local Sw, Nw = X._test.swarm, X._test.news
T.check(Sw ~= nil and Nw ~= nil, "the swarm and the News")
if Sw and Nw then
  Sw.now = function() return tnow end
  local Runtime = require("src.mods.Runtime")
  local E = require("src.core.game3.encounters")
  local sw = Sw.today(s, tnow)
  T.check(sw and sw.mapId:find("ROUTE", 1, true) and sw.species and sw.min <= sw.max,
    "today's swarm: a route, a species, levels (" .. tostring(sw and sw.mapId) .. ")")
  local here = false
  for _, sl in ipairs((E._tables[sw.key].land or E._tables[sw.key].grass).slots) do
    if tonumber(sl.species) == sw.species then here = true end
  end
  T.check(not here, "a species that isn't already there")
  T.eq(Sw.today(s, tnow + 3600).species, sw.species, "the same all day")
  local seen = {}
  for d = 1, 6 do seen[Sw.today(s, tnow + d * 86400).key .. "/" .. Sw.today(s, tnow + d * 86400).species] = true end
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  T.check(n >= 3, "another day, another swarm (" .. n .. " in six days)")
  -- (the hook: on its route, on land, sometimes)
  local function vanilla(enc) return enc end
  local function roll(mapId, terrain)
    return Runtime.call("encounter.species", vanilla, { species = spOf(16), level = 3 }, { mapId = mapId, terrain = terrain })
  end
  Sw.rng = function() return 0 end
  local got = roll(sw.mapId, "land")
  T.check(got.species == sw.species and got.level >= sw.min and got.level <= sw.max, "on its route: the swarm's species, at the route's levels")
  T.eq(roll(sw.mapId, "water").species, spOf(16), "not in the water")
  local other = sw.mapId:gsub("%d+$", function(d) return tostring(tonumber(d) == 1 and 2 or 1) end)
  T.eq(roll(other, "land").species, spOf(16), "not on another route (" .. other .. ")")
  Sw.rng = function() return 0.99 end
  T.eq(roll(sw.mapId, "land").species, spOf(16), "and not every time")
  local seed, hits = 12345, 0
  Sw.rng = function() seed = (seed * 48271) % 2147483647 return seed / 2147483647 end
  for _ = 1, 2000 do if roll(sw.mapId, "land").species == sw.species then hits = hits + 1 end end
  T.check(hits > 680 and hits < 920, ("about four in ten (%d of 2000)"):format(hits))
  Sw.rng = nil
  Settings.set("swarms", false)
  T.check(Sw.today(s, tnow) == nil and roll(sw.mapId, "land").species == spOf(16), "Settings off: no swarm")
  Settings.set("swarms", true)
  -- (a swarm catch counts for its challenge)
  local before = Jr.count("swarm")
  run.loader.events:emit("pokemon.caught", { speciesId = sw.species, isNew = true, ballId = 4,
    mon = { species = sw.species, level = sw.min } })
  T.eq(Jr.count("swarm"), before + 1, "caught from the swarm: counted")

  -- ------- the News

  Nw.store, Nw.now = fakeSave, function() return tnow end
  fakeSave.data.news = nil
  local cast = Nw.build(s)
  local keys = {}
  for _, st in ipairs(cast.stories) do keys[#keys + 1] = st.key end
  local joined = " " .. table.concat(keys, " ") .. " "
  local byKey = {}
  for _, st in ipairs(cast.stories) do byKey[st.key] = st end
  -- (the rookie leads, newest first: the swarm catch, the last two trainers, the Gym; then their week)
  T.eq(table.concat(keys, " ", 1, 5), "signing match1 match2 gym week", "the rookie's coverage leads, newest first (" .. joined .. ")")
  local swarmSt = byKey.swarm
  local swName = PokeG.name(sw.species)
  T.check(swarmSt and swarmSt.head:lower():find(swName:lower(), 1, true) and swarmSt.body:find(tostring(sw.min), 1, true),
    "the swarm's words: the species, the levels (" .. tostring(swarmSt and swarmSt.body) .. ")")
  T.check(joined:find(" rbay ", 1, true) and joined:find(" catch ", 1, true) and not joined:find(" trainer ", 1, true)
    and not joined:find(" badge ", 1, true), "R-Bay, an earlier new catch; trainers and Badges as box scores only (" .. joined .. ")")
  local function has(text, part) return tostring(text):lower():find(tostring(part):lower(), 1, true) ~= nil end
  local squirtle, geodude = spOf(7), spOf(74)
  local gym = byKey.gym
  T.check(gym and has(gym.head, "Leader Brock") and has(gym.body, "2-1") and has(gym.body, "3 turns"),
    "the Gym: the Leader, the score, the turns (" .. tostring(gym and (gym.head .. " / " .. gym.body)) .. ")")
  T.check(gym and gym.beats and #gym.beats == 4 and gym.beats[1].mark == "" and has(gym.beats[1].text, "Brock")
    and has(gym.beats[1].text, PokeG.name(geodude)) and gym.beats[2].mark == "T1" and gym.beats[4].mark == "T3",
    "its play-by-play: the leads, then each knockout by its turn")
  local wg, rt = PokeG.moveName(55), PokeG.moveName(88)
  T.check(gym and has(gym.beats[2].text, "Super effective") and has(gym.beats[3].text, rt) and has(gym.beats[3].text, "setback")
    and has(gym.beats[4].text, "critical") and has(gym.beats[4].text, wg) and has(gym.beats[4].text, "That's the match"),
    "the beats: super effective, the setback, the critical finish (" .. tostring(gym and gym.beats[4].text) .. ")")
  local m1, m2 = byKey.match1, byKey.match2
  T.check(m1 and m1.head == "WOS 1, Hiker Ben 0" and has(m1.body, "clean sweep") and has(m1.body, "1 turn.")
    and m1.sp == squirtle, "the last win: the score, a clean sweep, one turn, the finisher's picture (" .. tostring(m1 and m1.body) .. ")")
  T.check(m2 and m2.head == "WOS 1, Bug Catcher Rick 1" and not has(m2.body, "clean sweep") and has(m2.body, "The finisher")
    and has(m2.body, PokeG.name(spOf(10))), "the one before: 1-1, both teams, the finisher (" .. tostring(m2 and m2.body) .. ")")
  local sg = byKey.signing
  T.check(sg and has(sg.head, "signs") and has(sg.head, swName) and sg.sp == sw.species
    and has(sg.body, ": the rookie's newest teammate is a level " .. sw.min .. " " .. swName .. ".")
    and sg.body:find(":", 1, true) > 1 and has(sg.body, "sealed the deal") and has(sg.body, "first for the rookie"),
    "the latest catch: a signing (" .. tostring(sg and (sg.head .. " / " .. sg.body)) .. ")")
  T.check(joined:find(" challenges ", 1, true), "the week's challenges")
  T.check(type(cast.ticker) == "string" and cast.ticker:find(cast.stories[1].head, 1, true), "the ticker: the headlines")
  local again = Nw.build(s)
  local moments = false
  for _, st in ipairs(again.stories) do if st.key == "catch" then moments = true end end
  T.check(not moments, "watched: the same moments aren't told twice")
  -- (the swarm's notification, once a day)
  Nt.reset()
  Nw.tick(s)
  Nw.tick(s)
  T.check(#Nt.list() == 1 and Nt.list()[1].kind == "swarm" and Nt.list()[1].app == "news"
    and Nt.list()[1].state and Nt.list()[1].state.story == "swarm", "the swarm: a notification, once, opening its story")

  -- (the window)
  local W = Apps.byId("news").window({ session = s, mode = "pad", app = "news", rows = {},
    resume = { app = "news", state = { story = "swarm" } } }, X._test.env)
  local nst = W.state
  T.eq(nst.cast.stories[nst.i].key, "swarm", "opened on the swarm's story")
  local okW, err = pcall(function() for _ = 1, 3 do drawWin(W, false) drawWin(W, true) end end)
  T.check(okW, "the News draws wide and upright (" .. tostring(err) .. ")")
  local whole = true
  for j, line in ipairs(nst.lines.lines) do if nst.lines.pre[j][nst.lines.count[j]] ~= line then whole = false end end
  T.check(whole, "the words typed out end as the lines themselves (letters, not bytes)")
  local i0 = nst.i
  W.input(input({ "a" }), NONE)
  T.check(nst.full and nst.i == i0, "A: the rest of the words first")
  W.input(input({ "a" }), NONE)
  T.eq(nst.i, i0 % #nst.cast.stories + 1, "A again: the next story")
  W.input(input({}), nav("left"))
  T.eq(nst.i, i0, "Left: the one before")
  T.check(W.input(input({ "b" }), NONE) == false, "B closes")
  local kb
  for _ = 1, 2 do kb = garbageOf(60, function() drawWin(W, false) end) end
  T.check(kb < 0.5, ("the News: next to no garbage (%.3f KB a frame)"):format(kb))
  -- (the Gym's play-by-play: its beats on lines of their own, marked; taller than the card, it
  -- follows the typing, then scrolls)
  local GW = Apps.byId("news").window({ session = s, mode = "pad", app = "news", rows = {},
    resume = { app = "news", state = { story = "gym" } } }, X._test.env)
  local gst = GW.state
  T.eq(gst.cast.stories[gst.i].key, "gym", "opened on the Gym's story")
  drawWin(GW, true)
  local marks = 0
  for j = 1, #gst.lines.lines do if gst.lines.mark[j] then marks = marks + 1 end end
  T.eq(marks, 4, "four beats, each marked on its first line")
  T.check(#gst.lines.lines > gst.cap, "upright, the Gym's story is taller than the card (" .. #gst.lines.lines .. " lines, "
    .. gst.cap .. " fit)")
  clock = clock + 60
  tnow = tnow + 60
  for _ = 1, 2 do drawWin(GW, true) end
  T.check(gst.top > 0, "typed to the end: the last lines in view (" .. gst.top .. ")")
  local top0 = gst.top
  GW.input(input({}), nav("up"))
  T.eq(gst.top, top0 - 1, "Up: a line back")
  GW.scroll(5.4)
  T.eq(gst.top, top0 - 2, "the wheel too")
  local okG = pcall(function() for _ = 1, 3 do drawWin(GW, false) drawWin(GW, true) end end)
  T.check(okG, "the play-by-play draws wide and upright")
  local kbG
  for _ = 1, 2 do kbG = garbageOf(60, function() drawWin(GW, true) end) end
  T.check(kbG < 0.5, ("the play-by-play: next to no garbage (%.3f KB a frame)"):format(kbG))
  -- (Japanese has no spaces: its lines still fit)
  X._test.env.setLanguage("ja")
  local JW = Apps.byId("news").window({ session = s, mode = "pad", app = "news", rows = {},
    resume = { app = "news", state = { story = "gym" } } }, X._test.env)
  drawWin(JW, true)
  local jst, fits = JW.state, true
  for j, line in ipairs(jst.lines.lines) do
    if K.width(line, 4.1) > jst.linesW - jst.lines.indent[j] + 0.01 then fits = false end
  end
  T.check(fits and #jst.lines.lines > 4, "Japanese: " .. #jst.lines.lines .. " lines, each fitting")
  X._test.env.setLanguage("en")
end

T.finish("woob_os world (" .. GAME .. ")")
