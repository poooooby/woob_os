-- Standalone: luajit mods/woob_os/tests/gb_test.lua [red|blue|yellow|gold|silver|crystal] (from the gen1recomp
-- root; needs that cart imported, Crystal by default).
--
-- WoobOS on the Game Boy games (src/gb/*.lua): the mod loads for Gen 1 / Gen 2; the PC takeover (Gen 2's
-- Pokémon Center and bedroom PCs through the screen registry, Gen 1's which-PC menu through
-- OverworldState:openPC and its bedroom PC) opens the desktop and hands the game its answer when it logs
-- off; WoobPad's START row; the field's free test.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GAME = arg[1] or "crystal"
local GEN = (GAME == "red" or GAME == "blue" or GAME == "yellow") and 1 or 2

local clock = 100
local function noop() end
local fontOf = {}
local function newFont(px)
  local f = fontOf[px]
  if not f then
    f = { getWidth = function(_, s) return #tostring(s) * px * 0.55 end, getHeight = function() return px * 1.2 end,
          getWrap = function(_, s) return 0, { s } end, setFallbacks = noop }
    fontOf[px] = f
  end
  return f
end
local G = setmetatable({ newFont = newFont, getFont = function() return newFont(12) end,
                         newMesh = function() error("no meshes headless") end,
                         newCanvas = function() error("no canvases headless") end },
                       { __index = function() return noop end })
love = require("tests.love_stub")
love.graphics = G
love.timer = { getTime = function() return clock end }

-- ------- the game's data, real
local data
if GEN == 2 then
  local function loadLua(rel) return assert(loadfile(GAME .. "/" .. rel))() end
  data = {
    pokemon = loadLua("data/generated/pokemon.lua"), items = loadLua("data/generated/items.lua"),
    moves = loadLua("data/generated/moves.lua"), type_chart = loadLua("data/generated/type_chart.lua"),
    gen2Pokedex = loadLua("data/generated/pokedex.lua"), gen2Landmarks = loadLua("data/generated/landmarks.lua"),
    gen2Maps = loadLua("data/generated/maps.lua"), gen2Encounters = loadLua("data/generated/encounters.lua"),
    gen2Marts = loadLua("data/generated/marts.lua"), gen2Icons = loadLua("data/generated/icons.lua"),
    audio = { sfx = {} },
  }
  require("src.core.GameVersion").set(GAME)
else
  require("src.core.GameVersion").set(GAME)
  local Data = require("src.core.Data")
  if not Data.text_pointers then Data:load() end
  data = Data
end

local run = T.sdk.loadMods({ "mods/woob_os" }, { generation = GEN, data = data })
T.eq(#run.errors, 0, "loads clean on " .. GAME .. " (" .. tostring(run.errors[1]) .. ")")
local X = run.loader.exports.woob_os
T.check(X ~= nil and X._test ~= nil and X._test.host ~= nil, "the Game Boy wiring is made (src/gb/main.lua)")
if not (X and X._test and X._test.host) then return T.finish("woob_os gb (" .. GAME .. ")") end
local Sh, D, Wt, H, Settings = X._test.shell, X._test.desktop, X._test.watch, X._test.host, X._test.settings
Settings.cache = { read = function() return nil end, write = noop }
T.eq(H.gen, GEN, "the host's generation")
T.eq(H.gameId(), GAME, "the game's id")

-- ------- a game: the real stack, a save, the input
local StateStack = require("src.core.StateStack")
local stack = setmetatable({}, { __index = StateStack })
stack:init()
local save
if GEN == 2 then
  save = require("src.core.gen2.Save").newGame()
else
  save = require("src.core.SaveData").newGame()
end
local pressedNow = {}
local input = {
  wasPressed = function(_, k) return pressedNow[k] == true end,
  isDown = function() return false end,
}
local accepts = true
local world = { acceptsMenuInput = function() return accepts end, events = {} }
local overworld = setmetatable({ isOverworld = true, player = {} }, { __index = require("src.world.OverworldController") })
local game = { data = data, save = save, stack = stack, input = input, phase = "play" }
if GEN == 2 then game.world = world else game.overworld = overworld; table.insert(stack.states, overworld) end
run.loader.events:emit("game.ready", { game = game })

local VP = { width = 480, height = 432, gameX = 0, gameY = 0, gameWidth = 480, gameHeight = 432, scale = 3 }
local function frame(n)
  for _ = 1, n or 1 do
    clock = clock + 1 / 60
    stack:update(1 / 60)
    Sh.frame(game, VP)
    pressedNow = {}
  end
end
local function press(k)
  pressedNow = { [k] = true }
  stack:update(1 / 60)
  pressedNow = {}
end
local function logOff()
  -- (the desktop's Log Off sheet, as its app does: ctx.logoff)
  local st = D.state()
  if st and st.ctx then st.ctx.logoff() end
end

-- ------- the free test
local base = #stack.states
T.check(H.free(game), "free in the field")
if GEN == 2 then
  accepts = false
  T.check(not H.free(game), "a script running: not free")
  accepts = true
else
  overworld.transitioning = true
  T.check(not H.free(game), "a warp: not free")
  overworld.transitioning = nil
end

-- ------- the PC
local Screens = require("src.ui.Screens")
if GEN == 2 then
  local closedWith
  local opts = { save = save, events = {}, onClose = function(changed)
    stack:pop()
    closedWith = changed == true
  end }
  local c = Screens.push(game, "Gen2CenterPcMenu", opts)
  T.check(type(c) == "table" and c.dopts ~= nil, "the Pokémon Center PC: ours (a carrier)")
  frame(2)
  T.check(D.isOpen(), "the desktop opens over it")
  T.check(H.has(Sh.LAYER_ID), "its layer on the game's stack")
  for _ = 1, 3 do frame() end
  logOff()
  T.check(not D.isOpen() and closedWith == false, "log off: the game's onClose(false)")
  T.eq(#stack.states, base, "the stack as it was")
  -- (the bedroom PC)
  local bedClosed = false
  Screens.push(game, "Gen2ItemPcMenu", { save = save, house = true, events = {}, onClose = function()
    stack:pop()
    bedClosed = true
  end })
  frame(2)
  T.check(D.isOpen() and D.state().ctx.mode == "bedroom", "the bedroom PC: ours, the bedroom's desktop")
  logOff()
  T.check(bedClosed and #stack.states == base, "log off: the bedroom script goes on")
  -- (the player's PC from the which-PC menu stays the game's)
  local plain = Screens.build(game, "Gen2ItemPcMenu", { save = save, events = {}, onClose = noop })
  T.check(plain and plain.dopts == nil, "the item PC from the which-PC menu: the game's own")
  -- (the Desktop option off: the game's own)
else
  local done = false
  overworld:openPC(function() done = true end)
  frame(2)
  T.check(D.isOpen(), "the which-PC menu: ours")
  logOff()
  T.check(done and not D.isOpen(), "log off: the game's onDone")
  T.eq(#stack.states, base, "the stack as it was")
  local c = Screens.push(game, "PlayerPC", { direct = true })
  T.check(type(c) == "table" and c.dopts ~= nil, "the bedroom PC: ours (a carrier)")
  frame(2)
  T.check(D.isOpen() and D.state().ctx.mode == "bedroom", "the bedroom's desktop")
  logOff()
  T.check(not D.isOpen() and #stack.states == base, "log off: back to the field")
end

-- ------- the models
local Bx, Inv, Mb, Hl, Ok, Gd = X._test.bx, X._test.inv, X._test.mb, X._test.hall, X._test.oak, X._test.gd
T.check(Bx and Inv and Hl and Ok and Gd, "the models are made")
local function newMon(sp, level)
  if GEN == 2 then return require("src.battle.gen2.Mon").new(data, sp, level) end
  return require("src.pokemon.Pokemon").new(data, sp, level, math.random)
end
save.party = { newMon(GEN == 2 and "CYNDAQUIL" or "PIKACHU", 10), newMon("PIDGEY", 6) }
local p1, p2 = save.party[1], save.party[2]
T.check(Gd.monName(p1) == (GEN == 2 and "Cyndaquil" or "Pikachu"), "a Pokémon's name, titled (" .. Gd.monName(p1) .. ")")
T.check(Gd.typesOf(p2.species)[1] and Gd.typesOf(p2.species)[1].id == 0 and Gd.typesOf(p2.species)[2].id == 2,
  "Pidgey: Normal / Flying, as the windows' numbers")
T.eq(Bx.BOXES, GEN == 2 and 14 or 12, "the game's boxes")
-- (the party's last Pokémon that can battle stays)
local held, why = Bx.take(save, { Bx.addr("party", 1), Bx.addr("party", 2) })
T.check(not held and why == "last_usable", "the last one that can battle stays in the party")
held = Bx.take(save, { Bx.addr("party", 2) })
T.check(held and held.n == 1 and #save.party == 1, "one taken from the party: the party packed")
local okP = Bx.place(save, held, Bx.addr("box", 7, 1))
T.check(okP and Bx.count(save, 1) == 1 and Bx.get(save, Bx.addr("box", 1, 1)) == p2,
  "into an empty cell: after the last (the box packed)")
local held2 = Bx.take(save, { Bx.addr("box", 1, 1) })
local okBack = held2 and Bx.place(save, held2, Bx.addr("party", 2))
T.check(okBack and save.party[2] == p2 and Bx.count(save, 1) == 0, "back to the party")
-- (a swap)
local boxed = newMon("RATTATA", 4)
Bx.boxMons(save, 2)[1] = boxed
local h3 = Bx.take(save, { Bx.addr("party", 2) })
local okS, swapped = Bx.place(save, h3, Bx.addr("box", 1, 2))
T.check(okS and swapped and swapped.mons[1] == boxed and Bx.get(save, Bx.addr("box", 1, 2)) == p2,
  "onto another: they swap, the other in the hand")
Bx.putBack(save, swapped)
T.check(Bx.get(save, Bx.addr("box", 1, 2)) == boxed and Bx.get(save, Bx.addr("box", 2, 2)) == p2,
  "put back: where it came from")
local h4 = Bx.take(save, { Bx.addr("box", 2, 2) })
T.check(h4 and Bx.place(save, h4, Bx.addr("party", 2)) and save.party[2] == p2, "and the other back to the party")
local okR = Bx.release(save, Bx.addr("box", 1, 2))
T.check(okR and Bx.count(save, 2) == 0, "released")
local info = Bx.info(p1, X._test.i18n)
T.check(info and info.name == Gd.monName(p1) and #info.moves > 0 and #info.types > 0, "the preview's words")
if GEN == 2 then
  save.inventory = save.inventory or {}
  save.inventory.BERRY = 2
  local okG = Bx.giveItem(save, p1, "BERRY")
  T.check(okG and p1.item == "BERRY" and (save.inventory.BERRY or 0) == 1, "an item given to hold")
  local okT = Bx.takeItem(save, p1)
  T.check(okT and p1.item == nil and save.inventory.BERRY == 2, "and taken back to the Bag")
  T.check(not Bx.holdable(save, "BICYCLE"), "a key item can't be held")
end

-- (items: the Bag and the PC)
save.inventory = save.inventory or {}
save.inventory.POTION = 3
local pocket = GEN == 2 and "ITEMS" or "ITEMS"
local rows = Inv.bagRows(save, pocket)
local potionAt
for i, r in ipairs(rows) do if r.id == "POTION" then potionAt = i end end
T.check(potionAt ~= nil and rows[potionAt].qty == 3 and rows[potionAt].name == "Potion", "the Bag's Potions, by name")
local pcBefore = 0
for _, r in ipairs(Inv.pcRows(save)) do if r.id == "POTION" then pcBefore = r.qty end end
local okD = Inv.deposit(save, pocket, potionAt, 2)
local inPc = 0
for _, r in ipairs(Inv.pcRows(save)) do if r.id == "POTION" then inPc = r.qty end end
T.check(okD and inPc == pcBefore + 2 and save.inventory.POTION == 1, "deposited into the PC")
local pcAt
for i, r in ipairs(Inv.pcRows(save)) do if r.id == "POTION" then pcAt = i end end
local okW = Inv.withdraw(save, pcAt, 2)
T.check(okW and save.inventory.POTION == 3, "withdrawn to the Bag")
local key = GEN == 2 and "BICYCLE" or "BICYCLE"
save.inventory[key] = 1
local keyRows = Inv.bagRows(save, GEN == 2 and "KEY_ITEMS" or "ITEMS")
local keyAt
for i, r in ipairs(keyRows) do if r.id == key then keyAt = i end end
local okK, whyK = Inv.deposit(save, GEN == 2 and "KEY_ITEMS" or "ITEMS", keyAt or 1, 1)
T.check(not okK and whyK == "important", "a key item stays in the Bag")
T.eq(#Inv.pockets(save), GEN == 2 and 4 or 1, "the game's pockets")

-- (mail: Gold / Silver / Crystal)
if GEN == 2 then
  local M = require("src.core.gen2.Mail")
  M.state(save).box[1] = M.entry("FLOWER_MAIL", "HELLO THERE\nFRIEND", "KRIS", 1234, "PIKACHU")
  local inbox = Mb.inbox(save)
  T.check(#inbox == 1 and inbox[1].from == "KRIS" and inbox[1].lines[2] == "FRIEND", "the mailbox's letter")
  local okGv = Mb.give(save, inbox[1], p1)
  T.check(okGv and p1.item == "FLOWER_MAIL" and #Mb.inbox(save) == 0, "given to a Pokémon to hold")
  local heldRows = Mb.held(save)
  T.check(#heldRows == 1 and heldRows[1].mon == p1, "held by the party")
  local okTk = Mb.take(save, heldRows[1])
  T.check(okTk and p1.item == nil and #Mb.inbox(save) == 1, "taken back to the mailbox")
  T.check(Mb.toBag(save, Mb.inbox(save)[1]) and (save.inventory.FLOWER_MAIL or 0) == 1, "the stationery to the Bag")
else
  T.check(Mb == nil, "Red / Blue / Yellow: no mail")
end

-- (the Hall of Fame, Oak's PC)
if GEN == 2 then
  local HoF = require("src.core.gen2.HallOfFame")
  pcall(HoF.induct, save, save.party, {})
else
  save.hallOfFame = { { { species = "PIKACHU", level = 50, nickname = "SPARKY" } } }
end
local teams = Hl.teams(save)
T.check(#teams >= 1 and #teams[1].members >= 1, "the Hall of Fame's team (" .. #teams .. ")")
if GEN == 2 then save.engineFlags = save.engineFlags or {}; save.engineFlags[11] = true
else save.flags.EVENT_GOT_POKEDEX = true end
local caughtSet = GEN == 2 and save.pokedex.caught or save.pokedex.owned
for _, sp in ipairs({ "PIDGEY", "RATTATA", "SPEAROW" }) do save.pokedex.seen[sp] = true; caughtSet[sp] = true end
local rating = Ok.rating(save)
T.check(Ok.available(save) and rating.caught == 3 and rating.words ~= "" and rating.map[16] == 2,
  "Oak's rating: " .. tostring(rating.words))
T.eq(Ok.TOTAL, GEN == 2 and 251 or 151, "Oak's Pokédex")
local rowsNow = H.rows({ session = save })
local hasOak, hasHall = false, false
for _, r in ipairs(rowsNow) do
  if r.id == "oak" then hasOak = true end
  if r.id == "hall" then hasHall = true end
end
T.check(hasOak and hasHall, "the PC's rows: Oak's and the Hall's once there")

-- ------- the windows open and draw (the PC's desktop), next to no garbage
local function garbageOf(n, fn)
  local best = math.huge
  for _ = 1, 3 do
    collectgarbage("collect")
    collectgarbage("stop")
    local kb = collectgarbage("count")
    for _ = 1, n do fn() end
    best = math.min(best, (collectgarbage("count") - kb) / n)
    collectgarbage("restart")
  end
  return best
end
local opened = 0
local closedAll = false
do
  local optsW = { save = save, events = {}, onClose = function() stack:pop(); closedAll = true end }
  if GEN == 2 then Screens.push(game, "Gen2CenterPcMenu", optsW) else overworld:openPC(function() closedAll = true end) end
  frame(2)
  if D.skipBoot then D.skipBoot() end
  frame(30)
  for _, id in ipairs({ "storage", "items", "mail", "hall", "oak", "settings" }) do
    if id ~= "mail" or GEN == 2 then
      local okO = D.openApp(id)
      T.check(okO, "the " .. id .. " app opens")
      local okDr, errDr = pcall(function() frame(20) end)
      T.check(okDr, "the " .. id .. " window draws (" .. tostring(errDr) .. ")")
      if okO and okDr then
        opened = opened + 1
        local kb = garbageOf(30, function() frame() end)
        T.check(kb < 0.5, ("the %s window: next to no garbage (%.3f KB/frame)"):format(id, kb))
      end
    end
  end
  logOff()
end
T.check(closedAll and #stack.states == base, "logged off after the apps")

-- ------- WoobPad's START row
local rows
if GEN == 2 then
  rows = { { label = "POKéDEX", value = "pokedex" }, { label = "PACK", value = "pack" }, { label = "SAVE", value = "save" },
           { label = "EXIT", value = "quit" } }
else
  rows = { { label = "POKéMON" }, { label = "ITEM" }, { label = "SAVE" }, { label = "OPTION" } }
end
local got = Sh.startRows(rows)
local padRow
for i, r in ipairs(got) do if r.woobOs then padRow = i end end
T.check(padRow ~= nil and got[padRow + 1] and (got[padRow + 1].value == "save" or got[padRow + 1].label == "SAVE"),
  "WoobPad's row, before SAVE")
if padRow then
  got[padRow].onSelect(game)
  frame(2)
  T.check(Wt.isOpen(), "WoobPad opens from it")
  T.check(H.has(Sh.WATCH_ID), "its layer on the game's stack")
  local st = Wt.state()
  if st and st.ctx then st.ctx.done() end
  T.check(not Wt.isOpen() and #stack.states == base, "put away: the stack as it was")
end

T.finish("woob_os gb (" .. GAME .. ")")
