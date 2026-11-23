-- Standalone: luajit mods/woob_os/tests/scenes_test.lua [game] (from the gen1recomp root; needs that cart
-- imported, Emerald by default).
--
-- The moments we stage (src/scenes.lua): an evolution (src/evolve.lua, src/apps/evolution.lua) and a catch's
-- page and a Pokémon's nickname (src/caught.lua, src/apps/caught.lua, src/keyboard.lua) on the scene host.
-- Each wrap made once; the evolution: ours on its own layer, the game told it's open, the change at the point
-- of no return, a move learned after, onDone("evolved"); B stops it (onDone("stopped"), unchanged); a reset
-- closes it quietly. The catch's page: the question answered there goes to the battle's (catch.nickname);
-- Emerald's onDone with the picture. The naming screen for a Pokémon: ours, its flag up while it's open, the
-- name typed (or the species' when nothing is), a catch to the PC saying so; the box's naming the game's;
-- each with its switch off the game's own. Next to no garbage; the text at 130%.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GAME = arg[1] or "emerald"

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
local Sh, Tm, K = X._test.shell, X._test.townmap, X._test.kit
local Stack = require("src.ui.game3.stack")
local Ts, Sc = X._test.sceneHost, X._test.scenes
local ES = require("src.ui.game3.evolution_scene")
local Naming = require("src.ui.game3.naming")
local family = (GAME == "firered" or GAME == "leafgreen") and "frlg" or "rse"
local DexUi = require(family == "frlg" and "src.ui.game3.pokedex" or "src.ui.game3.rse.pokedex")
T.check(Ts ~= nil and Sc ~= nil, "the scene host and the scenes are made")
T.check(ES.__woobOsEvo and ES.__woobOsEvo.impl and Naming.__woobOsNick and DexUi.__woobOsCaught,
        "the evolution, the naming screen and the catch's page wrapped")
local wrapped = ES.start
run.loader.events:emit("game.ready", {})
T.check(ES.start == wrapped, "wrapped once, whatever the game.ready count")

local function input(press)
  local p = {}
  for _, k in ipairs(press or {}) do p[k] = true end
  return { wasPressed = function(_, k) return p[k] == true end, isDown = function(_, k) return p[k] == true end }
end
local VP = { width = 480, height = 320 }
local NONE = input()
-- a frame as the game runs one: the top layer gets the input, then the HUD's draw (Sh.frame)
local function frame(n, press)
  for i = 1, n or 1 do
    clock = clock + 1 / 60
    local inp = i == 1 and press and input({ press }) or NONE
    local top = Stack.top and Stack.top()
    if top and top.id == Sh.SCENE_ID then Sh.sceneLayer.handleInput(inp) end
    Sh.frame(nil, VP)
  end
end
local function waitFor(pred, limit)
  for _ = 1, limit or 2000 do
    if pred() then return true end
    frame(1)
  end
  return pred() and true or false
end
-- (a press, a few frames apart, until pred)
local function pressUntil(pred, key, limit)
  for _ = 1, limit or 120 do
    if pred() then return true end
    frame(1, key or "a")
    frame(6)
  end
  return pred() and true or false
end
local function garbageOf(n)
  local best = math.huge
  for _ = 1, 2 do
    collectgarbage("collect")
    collectgarbage("stop")
    local kb = collectgarbage("count")
    for _ = 1, n do
      clock = clock + 1 / 60
      Ts.draw(G, VP)
    end
    best = math.min(best, (collectgarbage("count") - kb) / n)
    collectgarbage("restart")
  end
  return best
end
local function win() return Ts.isOpen() and Ts.state().win or nil end
local function wst() local w = win() return w and w.state or nil end
local Fx = X._test.env.sceneFx
local function asking() local w = wst() return w ~= nil and w.words.ask and not Fx.typing(w.words, clock) end

-- ------- a session with a team of three
local Bag, Storage = require("src.core.game3.bag"), require("src.core.game3.storage")
local ItemsData, P, Party = require("src.core.game3.items_data"), require("src.core.game3.pokemon"), require("src.core.game3.party")
local s = { name = "WOS", playerName = "WOS", bag = Bag.new(), storage = Storage.new(), party = {}, money = 3000,
            flags = {}, vars = {}, gender = 0, gameStats = {} }
ItemsData.ensureModel(s)
s.dex = { seen = {}, owned = {}, caught = {} }
require("src.core.game3.runtime").getSession = function() return s end
Party.giveMon(s, P.speciesFromNational(4), 12)
Party.giveMon(s, P.speciesFromNational(25), 9)
Party.giveMon(s, P.speciesFromNational(129), 20)
T.eq(#s.party, 3, "a team of three")
local L = run.loader
L.modOptions = L.modOptions or {}

-- ------- an evolution: Charmander into Charmeleon, at 13 (Charmeleon learns Smokescreen there)
do
  local mon = s.party[1]
  mon.level = 13
  local into = P.speciesFromNational(5)
  local moves0 = P.moveSlotCount(mon)
  local got = {}
  ES.start(mon, into, { session = s, onDone = function(r, m) got[#got + 1] = r .. ":" .. tostring(m == mon) end })
  T.check(Sh.sceneOpen("evolution") and Stack.has(Sh.SCENE_ID) and ES.isOpen(),
          "an evolution: ours, on its own layer, the game told it's open")
  T.check(Sh.sceneTop(), "on top")
  T.check(waitFor(function() return wst() and wst().words.pages ~= nil end, 120), "What? It's evolving: the game's words")
  frame(1, "a")
  frame(30)
  T.check(wst().words.pages ~= nil, "A doesn't take those words away (nothing waits on them)")
  T.check(waitFor(function() return wst().phase == "cycle" end, 400), "the swap starts")
  frame(60)
  local kb = garbageOf(60)
  T.check(kb < 0.5, ("the swap: next to no garbage (%.3f KB a frame)"):format(kb))
  K.setTextScale(1.3)
  T.check(pcall(frame, 10), "the text at 130%")
  K.setTextScale(1)
  T.eq(P.speciesOf(mon), P.speciesFromNational(4), "still itself while it swaps")
  T.check(waitFor(function() return P.speciesOf(mon) == into end, 1500), "the change at the point of no return")
  T.check(ES.isOpen() and wst().phase == "burst", "the flash; still open")
  T.check(pressUntil(function() return wst().phase == "stats" end), "after the congratulations: the stats card")
  local job = Ts.state().ctx.scene
  T.check(job.before and job.after and job.after[2] > job.before[2] and job.after[1] > job.before[1],
          "its stats before and after the change (Attack " .. tostring(job.before and job.before[2]) .. " -> "
          .. tostring(job.after and job.after[2]) .. ")")
  -- (measured once the numbers stop counting: each new one's text is made the first time it shows)
  frame(90)
  local kbS = garbageOf(60)
  T.check(kbS < 0.5, ("the stats card: next to no garbage (%.3f KB a frame)"):format(kbS))
  do
    local wn = win()
    local d0, err = wn.draw, nil
    wn.draw = function(...)
      local ok, e = pcall(d0, ...)
      if not ok then err = e end
    end
    frame(5)
    wn.draw = d0
    T.check(err == nil, "the card draws (" .. tostring(err) .. ")")
  end
  K.setTextScale(1.3)
  T.check(pcall(frame, 10), "the card's text at 130%")
  K.setTextScale(1)
  frame(1, "a")
  T.check(wst().phase == "learn", "A: on to the moves")
  T.check(pressUntil(function() return not Sh.sceneOpen() end), "A through the words: closed")
  T.eq(got[1], "evolved:true", "the game's onDone: evolved, with the Pokémon")
  T.check(#got == 1 and not ES.isOpen() and not Stack.has(Sh.SCENE_ID), "once; the game told it's shut, the layer gone")
  T.eq(P.moveSlotCount(mon), moves0 + 1, "the move it learns at its level, learned after")
end

-- ------- B stops it: Magikarp stays Magikarp
do
  local mon = s.party[3]
  local from = P.speciesOf(mon)
  local got = nil
  ES.start(mon, P.speciesFromNational(130), { session = s, onDone = function(r) got = r end })
  T.check(waitFor(function() return wst() and wst().phase == "cycle" end, 400), "another: the swap")
  frame(20)
  frame(1, "b")
  T.check(wst().phase == "cancel", "B: stopped")
  T.check(pressUntil(function() return not Sh.sceneOpen() end), "A: closed")
  T.eq(got, "stopped", "the game's onDone: stopped")
  T.eq(P.speciesOf(mon), from, "unchanged")
end

-- ------- a reset under it: closed quietly, the game told it's shut
do
  local got = nil
  ES.start(s.party[2], P.speciesFromNational(26), { session = s, onDone = function(r) got = r end })
  frame(5)
  Stack.pop(Sh.SCENE_ID)
  frame(2)
  T.check(not Sh.sceneOpen() and not ES.isOpen() and got == nil, "its layer gone: closed, the game told, nothing called")
end

-- ------- its switch off: the game's own
do
  L.modOptions.woob_os = { menuEvolution = false }
  T.eq(Sc.evolution(s.party[2], P.speciesFromNational(26), { session = s }), false, "Evolution off: the game's own")
  L.modOptions.woob_os = { modernMenus = false }
  T.eq(Sc.evolution(s.party[2], P.speciesFromNational(26), { session = s }), false, "Modern Menus off: the game's own")
  L.modOptions.woob_os = nil
end

-- (the keyboard: a key's index by its letter, on the page showing)
local Kb = X._test.env.keyboard
local function keyOf(ch)
  local lay = Kb.layout(wst().kb)
  for k = 1, #lay.keys do if lay.keys[k] == ch then return k end end
end
local function typeWord(word)
  for ch in word:gmatch(".") do
    local at = keyOf(ch)
    if not at then return false end
    win().tap(2200 + at)
  end
  return true
end

-- ------- after a first catch: the page, the question answered there, the battle's question not asked
do
  local sp = P.speciesFromNational(25)
  local done, arg = false, nil
  if family == "frlg" then
    DexUi.showRegistration(sp, { session = s, onDone = function() done = true end })
  else
    DexUi.showCaughtMon(sp, { session = s, personality = 7, onDone = function(c) done, arg = true, c end })
  end
  T.check(Sh.sceneOpen("caught") and wst().kb == nil, "the catch's page: ours, the page first")
  T.check(waitFor(function() return wst().words.pages ~= nil end, 200), "its words")
  T.check(pressUntil(asking), "then the question")
  frame(1, "a")
  T.check(wst().kb ~= nil, "Yes: the keyboard")
  T.check(typeWord("Spark"), "typed")
  T.eq(wst().kb.text, "Spark", "a capital, then small letters")
  frame(1, "b")
  T.eq(wst().kb.text, "Spar", "B: one letter back")
  win().tap(2200 + keyOf("k"))
  frame(20)
  local kb = garbageOf(60)
  T.check(kb < 0.5, ("the keyboard: next to no garbage (%.3f KB a frame)"):format(kb))
  frame(1, "start")
  frame(1, "a")
  T.check(waitFor(function() return not Sh.sceneOpen() end, 60), "OK: closed")
  T.check(done, "the game's onDone")
  if family == "rse" then
    T.check(type(arg) == "table" and arg.species == sp and arg.sprite ~= nil and arg.personality == 7,
            "Emerald's: with the picture it slides back")
  end
  local Runtime = require("src.mods.Runtime")
  local mon = { species = sp }
  T.eq(Runtime.call("catch.nickname", function() return true end, mon, {}), "Spark", "the battle's question: answered")
  T.eq(Runtime.call("catch.nickname", function() return true end, mon, {}), true, "once")
end

-- ------- No on the page: no nickname, not asked again
do
  local sp = P.speciesFromNational(16)
  if family == "frlg" then DexUi.showRegistration(sp, { session = s, onDone = function() end })
  else DexUi.showCaughtMon(sp, { session = s, onDone = function() end }) end
  T.check(pressUntil(asking), "a page: the question")
  local kb = garbageOf(60)
  T.check(kb < 0.5, ("the page: next to no garbage (%.3f KB a frame)"):format(kb))
  K.setTextScale(1.3)
  T.check(pcall(frame, 10), "the page's text at 130%")
  K.setTextScale(1)
  frame(1, "down")
  frame(1, "a")
  T.check(waitFor(function() return not Sh.sceneOpen() end, 60), "No: closed")
  T.eq(require("src.mods.Runtime").call("catch.nickname", function() return true end, { species = sp }, {}), false,
       "the battle keeps the species' name, no question")
end

-- ------- the naming screen for a Pokémon: ours
do
  local sp = P.speciesFromNational(25)
  local named = nil
  local stand = Naming.open({ template = "CAUGHT_MON", maxLen = 10, species = sp, seed = "PIKACHU",
                              title = "PIKACHU's nickname?", sentToPc = false, session = s,
                              onDone = function(n) named = n end })
  T.check(Sh.sceneOpen("caught") and Naming.isOpen() and Naming._state == stand and stand.woobOs,
          "a catch's nickname: ours, the game's flag up")
  T.check(wst().kb ~= nil, "the keyboard at once")
  T.check(pcall(Naming.draw) and pcall(Naming.update, 1 / 60), "the game's own naming screen drawn or ticked meanwhile: nothing")
  frame(10)
  T.check(typeWord("Zap"), "typed")
  K.setTextScale(1.3)
  T.check(pcall(frame, 10), "the text at 130%")
  K.setTextScale(1)
  frame(1, "start")
  frame(1, "a")
  T.check(waitFor(function() return not Sh.sceneOpen() end, 60), "OK: closed")
  T.check(named == "Zap" and not Naming.isOpen() and Naming._state == nil, "the game's onDone with the name, its flag down")
  -- (nothing typed: the species' name, as the game)
  named = nil
  Naming.open({ template = "NICKNAME", maxLen = 10, species = sp, seed = "PIKACHU", session = s,
                onDone = function(n) named = n end })
  T.check(Sh.sceneOpen("caught"), "an Egg's or a gift's: ours too")
  frame(1, "start")
  frame(1, "a")
  T.check(waitFor(function() return not Sh.sceneOpen() end, 60) and named == "PIKACHU", "nothing typed: its own name")
  -- (a catch sent to the PC: where it went, then closed)
  named = nil
  Naming.open({ template = "CAUGHT_MON", maxLen = 10, species = sp, seed = "PIKACHU", sentToPc = true, session = s,
                onDone = function(n) named = n end })
  typeWord("Volt")
  frame(1, "start")
  frame(1, "a")
  -- (when the game has words for it: its naming screen says nothing without them either)
  local okSaid, said = pcall(Storage.pcTransferMessage, s, "Volt", Storage.isDestinationBoxFull(s))
  if okSaid and type(said) == "string" and said ~= "" then
    T.check(Sh.sceneOpen("caught") and wst().words.pages ~= nil and wst().kb == nil, "to the PC: the game says so")
  end
  T.check(pressUntil(function() return not Sh.sceneOpen() end) and named == "Volt", "then closed, with the name")
  -- (the game letting its screen go from outside: ours goes too)
  named = nil
  Naming.open({ template = "CAUGHT_MON", maxLen = 10, species = sp, seed = "PIKACHU", session = s,
                onDone = function(n) named = n end })
  Naming.dismiss()
  frame(2)
  T.check(not Sh.sceneOpen() and named == nil, "dismissed by the game: closed quietly")
  -- (a box's name: the game's own)
  -- (the game's own may not open headless -- Ruby and Sapphire's want their fonts -- but ours stays out)
  local okOwn, own = pcall(Naming.open, { template = "BOX", maxLen = 8, seed = "BOX 1", session = s,
                                          onDone = function() end })
  T.check(not Sh.sceneOpen() and not (okOwn and own and own.woobOs), "a box's name: the game's own")
  pcall(Naming.dismiss)
  -- (its switch off)
  L.modOptions.woob_os = { menuCatch = false }
  okOwn, own = pcall(Naming.open, { template = "CAUGHT_MON", maxLen = 10, species = sp, seed = "PIKACHU",
                                    session = s, onDone = function() end })
  T.check(not Sh.sceneOpen() and not (okOwn and own and own.woobOs), "Catch & Name off: the game's own")
  pcall(Naming.dismiss)
  L.modOptions.woob_os = nil
end

T.finish("woob_os scenes (" .. GAME .. ")")
