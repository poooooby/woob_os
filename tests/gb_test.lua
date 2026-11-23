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
    gen2Tilesets = loadLua("data/generated/tilesets.lua"), gen2Palettes = loadLua("data/generated/palettes.lua"),
    -- (since the engine's 0.4.6 the Gen 2 screens read these from the cart, with no fallback: the ROM's
    -- lines, the event tables (Oak's ratings, the phone book), the constants)
    text = loadLua("data/generated/rom_text.lua"), gen2EventTables = loadLua("data/generated/events.lua"),
    gen2Constants = loadLua("data/generated/constants.lua"), gen2Scripts = loadLua("data/generated/scripts.lua"),
    audio = { sfx = {} },
  }
  require("src.core.GameVersion").set(GAME)
  -- (the engine's flags by name, bound from the cart's constants as the game binds them; the phone book and
  -- its calls' scripts from the cart's events, as the game fills them at load)
  pcall(require("src.core.gen2.EngineFlags").bind, data.gen2Constants.engineFlagOrder)
  local GPhone = require("src.core.gen2.Phone")
  pcall(GPhone.useRegistry, data)
  pcall(GPhone.useExtracted, data.gen2EventTables)
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
local world = { acceptsMenuInput = function() return accepts end, events = { get = function() return false end },
                playSfxNamed = function() end }
local overworld = setmetatable({ isOverworld = true, player = {}, update = function() end, draw = function() end },
  { __index = require("src.world.OverworldController") })
local game = { data = data, save = save, stack = stack, input = input, phase = "play", mods = run.loader }
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
-- (the host's fade through black, a shop counter's: run through its steps at once)
local function unveil()
  local Tm = X._test.townmap
  for _ = 1, 6 do
    local st = Tm and Tm.isOpen() and Tm.state()
    local v = st and st.veil
    if not (v and v.phase and v.phase ~= "gone") then return end
    v.t = v.t - 10
    frame(1)
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
  local bedChanged
  Screens.push(game, "Gen2ItemPcMenu", { save = save, house = true, events = {}, onClose = function(changed)
    stack:pop()
    bedClosed, bedChanged = true, changed
  end })
  frame(2)
  T.check(D.isOpen() and D.state().ctx.mode == "bedroom", "the bedroom PC: ours, the bedroom's desktop")
  -- (Decorate: the game's menu over the desktop; a moved decoration answers `changed` at log off)
  if D.skipBoot then D.skipBoot() end
  frame(30)
  T.check(D.launchApp("decorate"), "Decorate opens")
  local deco = stack:top()
  T.check(type(deco) == "table" and deco.categories ~= nil and not D.isOpen(), "the game's decoration menu")
  if type(deco) == "table" and deco.finish then deco.changed = true; deco:finish() end
  frame(3)
  T.check(D.isOpen(), "the desktop back after it")
  logOff()
  T.check(bedClosed and bedChanged == true and #stack.states == base, "log off: the room reloads (changed)")
  -- (the Pokégear's phone, once the Pokégear has its card)
  save.engineFlags = save.engineFlags or {}
  local phoneApp = X._test.apps and X._test.apps.byId("phone")
  T.check(phoneApp and not phoneApp.available({ session = save }), "no Phone before the Pokégear's card")
  save.engineFlags[4], save.engineFlags[2] = true, true
  T.check(phoneApp and phoneApp.available({ session = save }), "the Phone with it")
  local optsP = { save = save, events = {}, onClose = function() stack:pop() end }
  Screens.push(game, "Gen2CenterPcMenu", optsP)
  frame(2)
  if D.skipBoot then D.skipBoot() end
  frame(30)
  -- (ours: the phone book from the save, a call the game's own -- here, with no map, out of service)
  local GPhone = require("src.core.gen2.Phone")
  pcall(GPhone.addContact, save, GPhone.PHONECONTACT_MOM)
  local Ph = X._test.env.phone
  local book = Ph and Ph.contacts(save) or {}
  T.check(#book >= 1 and book[1].name ~= "?" and book[1].canCall, "the phone book: " .. tostring(book[1] and book[1].name))
  local words, okCall = Ph.call(save, book[1])
  T.check(okCall and type(words) == "string" and words ~= "", "a call: the game's own answer (" .. tostring(words) .. ")")
  T.check(#Ph.recents() >= 1 and Ph.recents()[1].name == book[1].name, "logged in the recents")
  T.check(D.launchApp("phone"), "the Phone opens")
  frame(30)
  local PW = D.window()
  T.check(PW and PW.title == "Phone" and stack:top() ~= nil and not D.state().winFailed, "our Phone window, drawing")
  logOff()
  T.eq(#stack.states, base, "the stack as it was")
  -- (the Pokégear's screen: ours for Fly and the walls' map, the game's with the option off)
  local gearOn = true
  local Opt = run.loader.mods and run.loader.mods.woob_os
  local flyClosed, flown = false, nil
  local fly = Screens.build(game, "Gen2Pokegear", { save = save, fly = { { spawn = "SPAWN_NEW_BARK", landmark = "NEW_BARK_TOWN" } },
                                                     onFly = function(sp) flown = sp end,
                                                     onClose = function() flyClosed = true end })
  T.check(type(fly) == "table" and fly.open ~= nil and fly.update ~= nil, "Fly's Pokégear: ours (a carrier)")
  local town = Screens.build(game, "Gen2Pokegear", { save = save, townMap = true, onClose = noop })
  T.check(type(town) == "table" and town.open ~= nil, "the walls' Town Map: ours too")
  -- (the START menu's row: WoobPad in the Pokégear's place)
  local rows = { { id = "pokedex" }, { id = "pokemon" }, { id = "pack" }, { id = "pokegear" }, { id = "status" },
                 { id = "save" } }
  rows = Sh.startRows(rows)
  T.check(rows[4] and rows[4].woobOs and rows[4].onSelect ~= nil and rows[4].value == nil and #rows == 6,
          "START: WoobPad in the POKéGEAR row's place")
  -- (the WoobPad option off: the game's own POKéGEAR row and Pokégear from it; Fly's still ours)
  do
    local env = X._test.env
    local was = env.padOption
    env.padOption = function() return false end
    local plain = Sh.startRows({ { id = "pokedex" }, { id = "pokemon" }, { id = "pack" }, { id = "pokegear" },
                                 { id = "status" }, { id = "save" } })
    T.check(plain[4].id == "pokegear" and not plain[4].woobOs and #plain == 6, "WoobPad off: the POKéGEAR row the game's")
    local own = Screens.build(game, "Gen2Pokegear", { save = save, onClose = noop })
    T.check(type(own) == "table" and own.cancel == nil and own.opts == nil, "and the game's own Pokégear from START")
    local fly2 = Screens.build(game, "Gen2Pokegear", { save = save, fly = { { spawn = "SPAWN_NEW_BARK" } }, onClose = noop })
    T.check(type(fly2) == "table" and fly2.cancel ~= nil, "Fly's map still ours")
    T.check(not Sh.openWatch(save) and not Wt.isOpen(), "no WoobPad at all")
    env.padOption = was
  end
  -- (the Radio: the Pokégear's card, its stations and shows the game's own)
  local Rd = X._test.env.radio
  local radioApp = X._test.apps.byId("radio")
  save.engineFlags[0] = nil
  T.check(radioApp and not radioApp.available({ session = save }), "no Radio before the Radio Card")
  save.engineFlags[0] = true
  T.check(radioApp and radioApp.available({ session = save }), "the Radio with it")
  T.check(Rd.open(), "the radio tunes in")
  local stations = 0
  for _, row in ipairs(Rd.stations()) do if row.station then stations = stations + 1 end end
  T.check(#Rd.stations() > 5 and stations >= 1, "the dial's stations here (" .. stations .. " on the air)")
  local oak
  for _, row in ipairs(Rd.stations()) do if row.station and not oak then oak = row end end
  -- (no station on the air: the shows' checks can't run; the failure above says so)
  if oak then
  Rd.setKnob(oak.knob)
  local sta, nm = Rd.current()
  T.check(sta == oak.station and nm ~= nil, "tuned to " .. tostring(nm))
  for i = 1, 400 do Rd.step(100 + i / 60) end
  local top, bottom = Rd.lines()
  T.check((top .. bottom) ~= "", "the show's lines: " .. top .. " / " .. bottom)
  local nH = Rd.historyCount()
  T.check(nH >= 2 and Rd.history(1) ~= nil and not Rd.history(1):find("<", 1, true),
          "the transcript: " .. nH .. " lines, the newest " .. tostring(Rd.history(1)))
  -- (the game's <PK><MN> as the kit's PkMn mark, never the codes)
  local codes, marks = 0, 0
  for _, row in ipairs(Rd.stations()) do
    if row.name and row.name:find("<", 1, true) then codes = codes + 1 end
    if row.name and row.name:find(X._test.kit.PKMN, 1, true) then marks = marks + 1 end
  end
  T.check(codes == 0, "station names without the game's codes")
  if oak.station == "OAKS_POKEMON_TALK" then
    T.check(marks >= 1 and X._test.kit.hasSign(oak.name) == false, "Oak's talk named with the PkMn mark (not a ♀ / ♂)")
  end
  end
  Rd.close()
  T.check(not Rd.isOpen() and Rd.historyCount() == 0, "closed, the transcript cleared")
  Screens.push(game, "Gen2CenterPcMenu", { save = save, events = {}, onClose = function() stack:pop() end })
  frame(2)
  if D.skipBoot then D.skipBoot() end
  frame(30)
  T.check(D.launchApp("radio"), "the Radio opens")
  frame(60)
  T.check(D.window() and D.window().title == "Radio" and not D.state().winFailed and Rd.isOpen(), "our Radio, playing")
  logOff()
  T.check(not Rd.isOpen() and #stack.states == base, "log off: the radio off, the stack as it was")
  -- (a wall radio: ours, on its station)
  local wall = Screens.build(game, "Gen2MapRadio", { channel = 0, onDone = noop })
  T.check(type(wall) == "table" and wall.open ~= nil, "a wall radio: ours (a carrier)")
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
-- the summary's page: DVs as the IVs (HP's from the others), Stat Exp as the EVs, the moves' PP
do
  p1.dvs = { attack = 15, defense = 14, speed = 1, special = 0 }
  p1.statExp = { hp = 1000, attack = 500, defense = 0, speed = 65535, special = 7 }
  Bx.forget(p1)
  local R = Bx.summary(save, p1, X._test.i18n)
  T.check(R and #R.rows == (GEN == 2 and 6 or 5) and R.ivMax == 15 and R.rows[1].iv == 10 and R.rows[2].iv == 15,
    "the summary: each stat with its DV (HP's 1010 = 10)")
  T.check(#R.radar == 5 and R.radar[4] == 65535 and R.rows[1].ev == 1000 and R.evTotal == 67042,
    "Stat Exp as the EVs, on a radar of five")
  T.check(#R.moves > 0 and R.moves[1].ppText:find("/", 1, true) ~= nil and #R.info >= 3, "the moves with their PP, Info's rows")
  local m1 = R.moves[1].id
  if #R.moves >= 2 then
    local m2 = R.moves[2].id
    T.check(Bx.swapMoves(p1, 1, 2) and Bx.summary(save, p1, X._test.i18n).moves[1].id == m2, "two moves swapped")
    Bx.swapMoves(p1, 1, 2)
    T.eq(Bx.summary(save, p1, X._test.i18n).moves[1].id, m1, "and back")
  end
end
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

-- ------- the play-tied apps
local Mt, Bk, Au, Sl, Gx, Er, Ch, Jr, Sw, Nw, Pt = X._test.mart, X._test.bank, X._test.auction, X._test.slots,
  X._test.gts, X._test.errands, X._test.challenges, X._test.journal, X._test.swarm, X._test.news, X._test.port
T.check(Mt and Bk and Au and Sl and Gx and Er and Ch and Jr and Sw and Nw and Pt, "the play apps' models are made")
local function money() return Gd.money(save) end
Gd.setMoney(save, 5000)
local potions = save.inventory.POTION or 0
local okB = Mt.buy(save, "POTION", 2, 0)
T.check(okB and money() == 4400 and save.inventory.POTION == potions + 2, "the Mart: two Potions bought")
local okSell, earned = Mt.sell(save, "POTION", 1)
T.check(okSell and earned == 150 and money() == 4550, "and one sold for half")
local okLock, whyLock = Mt.buy(save, "ULTRA_BALL", 1, 0)
T.check(not okLock and whyLock == "badges", "a Badge's goods wait for it")
-- (the Bank)
local okDep = Bk.deposit(save, 1000)
T.check(okDep and money() == 3550 and Bk.balance() == 1000, "the Bank: deposited")
local okWd = Bk.withdraw(save, 400)
T.check(okWd and money() == 3950 and Bk.balance() == 600, "withdrawn")
Gd.setMoney(save, 999000)
Pt.pay(save, 5000)
T.check(money() == 999999 and Bk.balance() == 600 + 4001, "what the wallet can't hold: to the Bank")
Gd.setMoney(save, 200000)
-- (R-Bay: a listing of this game's Pokémon, a bid, the win delivered)
local now0 = os.time()
local ls = Au.listings(save, now0)
-- (the cheapest: which auctions are up depends on the hour, and a legendary's may cost more than the wallet)
local L
for _, l in ipairs(ls or {}) do
  if not L or Au.minBid(l) < Au.minBid(L) then L = l end
end
T.check(L and type(L.sp) == "string" and Gd.def(L.sp) ~= nil, "R-Bay: a listing of this game's Pokémon (" .. tostring(L and L.sp) .. ")")
if L then
  local before = money()
  local okBid = Au.bid(save, L, math.min(money(), Au.minBid(L) + 100000), now0)
  T.check(okBid and money() < before, "a bid holds the money")
  local partyN = #save.party
  local won = Au.settle(save, L.finish + 10)
  T.check(won == 1 and (#save.party == partyN + 1 or Bx.count(save, Bx.current(save)) > 0), "won: the Pokémon delivered")
end
-- (Slots)
local reels = { 1, 1, 1, 1, 1 }
local k = 0
Sl.rng = function(n) k = k % 5 + 1; return reels[k] end
local okSpin = Sl.spin(save, 1, 1)
Sl.collect(save)
T.check(okSpin, "Slots: a spin")
local prizes = Sl.prizes()
T.check(#prizes >= 8, "the prize corner (" .. #prizes .. ")")
local dS = Sl.store and Sl.store:get("slots")
if dS then dS.tickets = 1000; Sl.store:set("slots", dS) end
local monPrize, itemPrize
for i, pz in ipairs(prizes) do
  if pz.kind == "mon" and not monPrize then monPrize = i end
  if pz.kind == "item" and not itemPrize then itemPrize = i end
end
local okI, whereI = Sl.redeem(save, itemPrize)
T.check(okI and whereI == "bag", "an item prize to the Bag (" .. tostring(prizes[itemPrize].id) .. ")")
local okM, whereM = Sl.redeem(save, monPrize)
T.check(okM and (whereM == "party" or whereM == "pc"), "a Pokémon prize (" .. tostring(prizes[monPrize].id) .. ")")
-- (the limited prizes: a sought-after Pokémon this game has and a held item, the day's; no tickets or
-- event Pokémon here)
Sl.refresh(save, 1800000000)
local lim = {}
for i, pz in ipairs(Sl.prizes()) do if pz.limited then lim[#lim + 1] = i end end
local lm, li = Sl.prizes()[lim[1]], Sl.prizes()[lim[2]]
T.check(#lim == 2 and lm.kind == "mon" and li.kind == "item" and not lm.event,
  "the limited prizes: a Pokémon and an item (" .. tostring(lm and lm.name) .. ", " .. tostring(li and li.name) .. ")")
local okL, whereL = Sl.redeem(save, lim[1])
T.check(okL and (whereL == "party" or whereL == "pc") and not Sl.redeem(save, lim[1]), "the day's Pokémon: once")
-- (the GTS: a Wonder Trade)
local giveAway = newMon("RATTATA", 7)
table.insert(save.party, giveAway)
local slot = #save.party
local okW, recv = Gx.wonder(save, Bx.addr("party", slot))
T.check(okW and save.party[slot] == recv and recv ~= giveAway and recv.traded, "the GTS: a Wonder Trade, theirs in its place")
-- (Errands: a box Pokémon on a job, back with EXP, money and an item)
local boxMon = newMon("GEODUDE", 12)
local box1 = Bx.boxMons(save, 1)
box1[#box1 + 1] = boxMon
local board = Er.board(save, now0)
local okE = Er.send(save, board[1].key, { Bx.addr("box", #box1, 1) }, now0)
T.check(okE and #Er.out() == 1 and Bx.count(save, 1) == #box1, "Errands: a team sent (out of its box)")
Er.settle(save, now0 + 9 * 3600)
local moneyE = money()
local expBefore = tonumber(boxMon.exp or boxMon.experience) or 0
local okC, errand = Er.collect(save, 1)
T.check(okC and money() > moneyE and (tonumber(boxMon.exp or boxMon.experience) or 0) > expBefore,
  "back: money and EXP")
-- (the journal: the game's own events, as it reads them)
local cBefore = Jr.count("caught")
run.loader.events:emit("pokemon.caught", { mon = newMon("PIDGEY", 4), species = "PIDGEY", isNew = true })
T.check(Jr.count("caught") == cBefore + 1 and Jr.count("t2") >= 1, "the journal: a catch, its types counted")
run.loader.events:emit("battle.started", { battle = { player = { species = p1.species }, enemy = { species = "RATTATA" } },
                                            kind = "wild" })
run.loader.events:emit("battle.ended", { battle = {}, result = "win" })
T.check(Jr.count("wild") >= 1, "a wild battle won")
local chList = Ch.list(save)
T.check(#chList == 5, "Challenges: the week's five")
-- (the swarm)
local sw = Sw.today(save, now0)
T.check(sw and type(sw.species) == "string" and tostring(sw.mapId):find("ROUTE"), "the daily swarm: " ..
  tostring(sw and sw.species) .. " on " .. tostring(sw and sw.mapId))
if sw then
  Sw.rng = function() return 0 end
  local got = Sw.encounter({ species = "RATTATA", level = 3 }, { mapId = sw.mapId, terrain = "grass" })
  T.check(got.species == sw.species, "its route's encounters become it")
  Sw.rng = nil
end
-- (the News)
local bc = Nw.build(save)
T.check(bc and #bc.stories > 0, "the News: today's stories (" .. (bc and #bc.stories or 0) .. ")")
do
  -- (the player by the name the Game Boy games keep on save.player)
  save.player = save.player or {}
  local was = save.player.name
  save.player.name = "KRIS"
  local named = false
  for _, st in ipairs((Nw.build(save) or {}).stories or {}) do
    if tostring(st.head):find("KRIS", 1, true) or tostring(st.body):find("KRIS", 1, true) then named = true end
  end
  T.check(named, "the News names the player (save.player.name)")
  save.player.name = was
end

-- ------- WoobleSpritePack's party icons: its own in the windows, for every Pokémon it has one for
do
  local Art = X._test.art
  local drawn, asked = {}, 0
  local fakeImg = { getDimensions = function() return 64, 32 end }
  local fakeQuad = { [0] = {}, [1] = {} }
  local stillImg = { getDimensions = function() return 40, 30 end }
  local liveImg = { getDimensions = function() return 48, 44 end }
  local pack = { iconArt16 = function(mon, f)
    asked = asked + 1
    if mon.species == "MISSINGNO" then return nil end
    return { full = fakeQuad[f] }, fakeImg, 32
  end,
  frontArt = function(mon) if mon.species ~= "MISSINGNO" then return stillImg, 40, 30 end end,
  monPic = function(ctx) if ctx.natural and ctx.mon.species ~= "MISSINGNO" then return liveImg end end }
  local prevPack, prevDraw = Art.pack, G.draw
  Art.pack = function() return pack end
  G.draw = function(img, q) drawn[#drawn + 1] = { img, q } end
  local mon = newMon(GEN == 2 and "CYNDAQUIL" or "PIKACHU", 5)
  X._test.env.monIconOf(mon, 0, 0, 20, 1, 1)
  T.check(drawn[1] and drawn[1][1] == fakeImg and drawn[1][2] == fakeQuad[1], "a Pokémon's icon: the pack's, its frame")
  local before = asked
  for _ = 1, 30 do X._test.env.monIconOf(mon, 0, 0, 20, 0, 1) end
  T.eq(asked, before, "asked once, then kept")
  local n = #drawn
  X._test.env.monIcon("MISSINGNO", 0, 0, 20, 0)
  T.check(#drawn == n or drawn[#drawn][1] ~= fakeImg, "none from the pack: the game's own")
  G.draw = noop
  local kb = math.huge
  for _ = 1, 3 do
    collectgarbage("collect")
    collectgarbage("stop")
    local c0 = collectgarbage("count")
    for _ = 1, 30 do X._test.env.monIconOf(mon, 0, 0, 20, 0, 1) end
    kb = math.min(kb, (collectgarbage("count") - c0) / 30)
    collectgarbage("restart")
  end
  T.check(kb < 0.05, ("the pack's icons: next to no garbage (%.3f KB)"):format(kb))
  -- (its pictures: the windows its first frame, the Pokédex its animation)
  local sp1 = GEN == 2 and "CYNDAQUIL" or "PIKACHU"
  local still = Art.pic(sp1, mon)
  T.check(still and still.image == stillImg and still.w == 40 and still.h == 30 and still.box > 40,
          "a Pokémon's picture: the pack's, in a square with a margin")
  local livePic = Art.livePic(sp1)
  T.check(livePic and livePic.image == liveImg, "the Pokédex's: the pack's animation")
  T.check((X._test.env.dexSprite.pack(sp1)), "the Pokédex says so")
  local noPack = Art.pic("MISSINGNO")
  T.check(noPack == nil or noPack.image ~= stillImg, "none from the pack: the game's own")
  Art.pack, G.draw = prevPack, prevDraw
end

-- ------- the 3D map: the outdoor maps built to scale
local M3 = X._test.env.map3d
T.check(M3 ~= nil and M3.model ~= nil, "the Map's model is made")
if M3 then
  local Mdl = M3.model
  local first = Mdl.regions()[1].id
  T.eq(first, GEN == 2 and "johto" or "kanto", "the first region")
  local region = Mdl.region(first)
  local W = region and region.world
  T.check(W and #W.maps >= 30 and W.cols > 100, "built from its maps (" .. (W and #W.maps or 0) .. ")")
  local overlap = 0
  for i = 1, W and #W.maps or 0 do
    for j = i + 1, #W.maps do
      local a, b = W.maps[i], W.maps[j]
      if a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h then overlap = overlap + 1 end
    end
  end
  T.eq(overlap, 0, "no two maps on top of each other")
  local feet, gyms, towns = 0, 0, 0
  for _, d in ipairs(W and W.doors or {}) do if d.foot then feet = feet + 1 end end
  for _, p in ipairs(region and region.places or {}) do
    if p.kind == "town" then towns = towns + 1 end
    if p.hasGym and p.badgeName then gyms = gyms + 1 end
  end
  T.check(feet >= 40, "its buildings, from their doors (" .. feet .. ")")
  T.check(towns >= 9 and gyms >= 7, ("its towns (%d), their Gyms (%d)"):format(towns, gyms))
  if GEN == 2 then
    save.position = { map = "NEW_BARK_TOWN", x = 6, y = 4 }
  else
    save.player = save.player or {}
    save.player.map, save.player.x, save.player.y = "PALLET_TOWN", 5, 6
  end
  local rid, px, pz = Mdl.player(save)
  local home
  for _, p in ipairs(region.places) do if p.sym == (GEN == 2 and "NEW_BARK_TOWN" or "PALLET_TOWN") then home = p end end
  T.check(rid == first and home and px >= home.x0 and px <= home.x1 and pz >= home.z0 and pz <= home.z1,
          "the player where they stand (" .. tostring(rid) .. ")")
  Mdl.live(region, save)
  T.check(Mdl.flyCheck() == nil, "no Fly from it")
  -- (the map's markers here too; the GPS on Gold / Silver / Crystal, not Red / Blue / Yellow)
  local Mk = X._test.marks
  T.check(Mk ~= nil and Mk.add(first, home.x, home.z, "ball", home.id) ~= nil, "a marker on the map")
  T.eq(Mk and Mk.onPlace(first, home.id) and Mk.onPlace(first, home.id).kind, "ball", "kept for its town")
  if Mk then for i = #Mk.list(), 1, -1 do Mk.remove(Mk.list()[i]) end end
  if GEN == 1 then
    T.eq(X._test.env.gps, nil, "no GPS on Red / Blue / Yellow: the menu has no waypoint")
  else
    -- ------- the GPS on Gold / Silver / Crystal: the walk graph from every map, routes the story's way
    local Gps = X._test.gps
    T.check(Gps ~= nil and X._test.env.gps ~= nil, "the GPS on Gold / Silver / Crystal")
    if Gps then
      local Gw, Rt = Gps.graph, Gps.route
      local disk = {}
      Gw.cache = { read = function(_, k) return disk[k] end, write = function(_, k, v) disk[k] = v; return true end }
      local t0 = os.clock()
      T.check(Gw.buildNow(), "its walk graph builds")
      local nn, ne = Gw.count()
      T.check(nn > 500 and ne > nn, ("its points and ways (%d, %d; %.2f s)"):format(nn, ne, os.clock() - t0))
      T.check(disk["gps/" .. GAME .. ".txt"] ~= nil, "kept on disk")
      -- (the player as the World has them; the story's flags; their badges and party)
      local flags = {}
      local events0 = world.events
      world.map, world.player, world.playerState = { id = "NEW_BARK_TOWN" }, { cellX = 6, cellY = 4 }, "normal"
      world.events = { get = function(_, id) return flags[id] == true end,
                       objectVisible = function(_, f) return f == nil or f == 0xFFFF or not flags[f] end }
      save.player = save.player or {}
      save.player.badges = {}
      local party0 = save.party
      local mon = { species = "PIDGEY", moves = {} }
      save.party = { mon }
      local function teach(...)
        mon.moves = { ... }
        Rt.refresh()
      end
      local function land(id, x, y)
        local rec = Gw.tiles(id)
        if not rec then return x, y end
        for r = 0, 12 do
          for oy = -r, r do
            for ox = -r, r do
              local tx, ty = x + ox, y + oy
              if tx >= 0 and ty >= 0 and tx < rec.w and ty < rec.h and rec.cls[ty * rec.w + tx] == Gw.LAND
                and not rec.obst[ty * rec.w + tx] then
                return tx, ty
              end
            end
          end
        end
        return x, y
      end
      local function at(id)
        local def = data.gen2Maps[id]
        world.map.id = id
        world.player.cellX, world.player.cellY = land(id, def.width, def.height)
        Rt.refresh()
      end
      local function to(id)
        local def = data.gen2Maps[id]
        local sec
        for _, pl in ipairs(region.places) do if pl.sym == id then sec = pl.id end end
        return Rt.set({ map = id, x = def.width, y = def.height, name = id, sec = sec, region = first })
      end
      local function through(id)
        for _, m in ipairs(Rt.chain() or {}) do if m == id then return true end end
        return false
      end
      local function chainText() return table.concat(Rt.chain() or {}, " > ") end
      local G = Gw.reader.G
      at("NEW_BARK_TOWN")
      T.eq(to("CHERRYGROVE_CITY"), "ok", "New Bark Town to Cherrygrove City: a way")
      T.check(through("ROUTE_29") and Rt.needs == 0, "by Route 29, nothing in the way (" .. chainText() .. ")")
      local L = Rt.line(region)
      T.check(L ~= nil and L.n > 2, "its line on the map (" .. tostring(L and L.n) .. " corners)")
      -- (arriving: anywhere in the town)
      Rt.step("CHERRYGROVE_CITY", 2, 2)
      T.eq(Rt.dest(), nil, "arrived: in the town, the waypoint cleared")
      -- (Azalea to Goldenrod: Ilex Forest's Cut tree, signed until the player can Cut)
      at("AZALEA_TOWN")
      T.eq(to("GOLDENROD_CITY"), "ok", "Azalea Town to Goldenrod City: a way")
      T.check(through("ILEX_FOREST") and Gw.band(Rt.needs, G.CUT.bit) ~= 0,
        "through Ilex Forest, its Cut tree in the way (" .. chainText() .. ")")
      L = Rt.line(region)
      local signed = false
      for k = 1, L and L.hn or 0 do if L.hk[k] == G.CUT.bit then signed = true end end
      T.check(signed, "the line signs it")
      save.player.badges.HIVE = true
      teach("CUT")
      Rt.step("AZALEA_TOWN", world.player.cellX, world.player.cellY)
      T.eq(Rt.needs, 0, "with the Hive Badge and Cut: nothing in the way")
      teach()
      -- (Violet to Ecruteak: Sudowoodo, until it's dealt with)
      at("VIOLET_CITY")
      T.eq(to("ECRUTEAK_CITY"), "ok", "Violet City to Ecruteak City: a way")
      T.check(G.SUDOWOODO.flag ~= nil and Gw.band(Rt.needs, G.SUDOWOODO.bit) ~= 0,
        "Sudowoodo in the way (" .. chainText() .. ")")
      flags[G.SUDOWOODO.flag] = true
      Rt.refresh()
      Rt.step("VIOLET_CITY", world.player.cellX, world.player.cellY)
      T.eq(Gw.band(Rt.needs, G.SUDOWOODO.bit), 0, "Sudowoodo gone: the way's open")
      -- (Cherrygrove to Cianwood: over the sea, only with Surf)
      at("CHERRYGROVE_CITY")
      T.eq(to("CIANWOOD_CITY"), "surf", "Cherrygrove City to Cianwood City without Surf: Requires Surf")
      save.player.badges.FOG = true
      teach("SURF")
      T.eq(to("CIANWOOD_CITY"), "ok", "with the Fog Badge and Surf: a way (" .. chainText() .. ")")
      teach()
      -- (Olivine to Vermilion: the S.S. Aqua, its ticket)
      at("OLIVINE_CITY")
      T.eq(to("VERMILION_CITY"), "ok", "Olivine City to Vermilion City: a way")
      T.check(Gw.band(Rt.needs, G.SHIP.bit) ~= 0 and through("OLIVINE_PORT") and through("VERMILION_PORT"),
        "by the S.S. Aqua, its ticket needed (" .. chainText() .. ")")
      save.inventory = save.inventory or {}
      save.inventory.S_S_TICKET = 1
      Rt.refresh()
      Rt.step("OLIVINE_CITY", world.player.cellX, world.player.cellY)
      T.eq(Gw.band(Rt.needs, G.SHIP.bit), 0, "with the S.S. Ticket: the ship's the way")
      save.inventory.S_S_TICKET = nil
      -- (Fly clears it: World:flyTo, wrapped)
      local World = require("src.world.gen2.World")
      T.check(rawget(World, "__woobOsGps") ~= nil, "World:flyTo wrapped (clears the waypoint)")
      Rt.clear()
      world.events, save.party, save.player.badges = events0, party0, {}
      world.map, world.player = nil, nil
    end
  end
  if GEN == 2 then
    local k = Mdl.region("kanto")
    T.check(k and #k.world.maps >= 25, "Gold / Silver / Crystal's Kanto, a world of its own")
    T.check(not Mdl.available(save, "kanto"), "Kanto shown once the player's been")
  end
end

-- ------- the Pokédex
local Dx = X._test.dex
T.check(Dx ~= nil, "the Pokédex's model is made")
if Dx then
  local book = Dx.open(save)
  local wantModes = GEN == 2 and "johto,national" or "kanto"
  T.eq(table.concat(book.modes, ","), wantModes, "its lists")
  T.eq(#book.lists[GEN == 2 and "national" or "kanto"], GEN == 2 and 251 or 151, "every Pokémon of the game")
  if GEN == 2 then T.eq(book.lists.johto[1].sp, "CHIKORITA", "Johto's first: Chikorita") end
  local bulba
  for _, e in ipairs(book.lists[GEN == 2 and "national" or "kanto"]) do if e.sp == "BULBASAUR" then bulba = e end end
  local pg = Dx.page(bulba)
  T.check(pg and pg.category:find("Seed") and pg.description ~= "", "Bulbasaur: the Seed Pokémon, its words (" ..
    tostring(pg and pg.category) .. ")")
  T.eq(pg and pg.total, GEN == 2 and 318 or 253, "its base stats' total")
  T.check(pg and pg.moves.level[1] and pg.moves.level[1].name == "Tackle", "its first move: Tackle")
  local toxic = false
  for _, r in ipairs(pg and pg.moves.tm or {}) do if r.name == "Toxic" and r.tag == "TM06" then toxic = true end end
  T.check(toxic, "TM06 Toxic")
  T.check(pg and pg.evolutions[1] and pg.evolutions[1].toName == "Ivysaur" and pg.evolutions[1].how:find("16"),
    "evolves into Ivysaur at 16")
  if GEN == 2 then
    T.check(pg.maleText == "87.5%" and #pg.moves.egg > 0, "87.5% male; egg moves")
  else
    T.check(pg.noGender == true, "Red / Blue / Yellow: no gender")
  end
  local pidgey
  for _, e in ipairs(book.lists[GEN == 2 and "national" or "kanto"]) do if e.sp == "PIDGEY" then pidgey = e end end
  local wp = Dx.page(pidgey)
  T.check(wp and #wp.where > 0 and wp.where[1].methodText ~= "", "Pidgey: where it's found (" ..
    tostring(wp and wp.where[1] and wp.where[1].place) .. ")")
  -- (WoobleSpawns: its places in place of the cart's; Gen 2's grass by the time of day, its rods' rows of a
  -- running chance out of 255; Gen 1's Super Rod a list, each as likely)
  local Sa = Dx.spawnArea
  T.check(Sa ~= nil, "the WoobleSpawns reader is there")
  if Sa then
    local prevS, on, useEnc = Sa.spawns, true, false
    -- (its 0.18.0 export: each map's odds as its hook draws them; Gen 2's grass a section per time of day)
    local function encounters(mapId, opts)
      local function sec(method, chance, lo, time)
        return { method = method, time = time, mons = { { id = "PIDGEY", chance = chance, minLevel = lo, maxLevel = lo + 1 },
                                                         { id = "RATTATA", chance = 100 - chance, minLevel = 2, maxLevel = 3 } } }
      end
      if GEN == 2 and mapId == "ROUTE_29" then
        return { mapId = mapId, sections = { sec("grass", 10, 2, "MORN"), sec("grass", 25, 3, "DAY"), sec("grass", 5, 4, "NITE") } }
      elseif GEN == 2 then
        return { mapId = mapId, sections = { sec("good", 40, 12) } }
      elseif mapId == "ROUTE_1" then
        return { mapId = mapId, sections = { sec("grass", 21, 4) } }
      end
      return { mapId = mapId, sections = { sec("super", 30, 5) } }
    end
    local function list(n, at, lv)
      local out = {}
      for i = 1, n do out[i] = { species = "RATTATA", level = 3 } end
      if at then out[at] = { species = "PIDGEY", level = lv } end
      return out
    end
    Sa.spawns = function()
      return {
        isActive = function() return on end,
        settings = function() return { timeOfDay = "off" } end,
        encounters = useEnc and encounters or nil,
        locate = function(id)
          if id ~= "PIDGEY" then return {} end
          if GEN == 2 then return { ROUTE_29 = { grass = true }, ROUTE_30 = { ["fish.good"] = true } } end
          return { ROUTE_1 = { grass = true }, ROUTE_12 = { superRod = true } }
        end,
        tableFor = function(mapId, kind)
          if GEN == 2 and kind == "grass" then
            return { rates = { MORN = 25, DAY = 25, NITE = 25 }, slots = { MORN = list(7), DAY = list(7), NITE = list(7) } }
          elseif GEN == 2 then
            return { { chance = 89, species = "MAGIKARP", level = 10 }, { chance = 178, species = "PIDGEY", level = 12 },
                     { chance = 255, species = "MAGIKARP", level = 15 } }
          elseif kind == "grass" then
            return { rate = 25, slots = list(10, 1, 4) }
          end
          return { { species = "PIDGEY", level = 5 }, { species = "MAGIKARP", level = 5 },
                   { species = "MAGIKARP", level = 10 }, { species = "MAGIKARP", level = 15 } }
        end,
        -- (Gen 2, COMPLETE: the day's second slot -- pool 9 -- can be Pidgey, one of two)
        poolFor = function(mapId, kind)
          if not (GEN == 2 and kind == "grass") then return nil end
          local p = {}
          for i = 1, 21 do p[i] = { "RATTATA" } end
          p[9] = { "RATTATA", "PIDGEY" }
          return p
        end,
      }
    end
    local function rowOf(w, method)
      for _, r in ipairs(w) do if r.method == method then return r end end
    end
    local sw = Dx.page(pidgey).where
    local grass = rowOf(sw, "grass")
    if GEN == 2 then
      local rod = rowOf(sw, "good")
      T.check(grass and grass.chanceText == "15%" and #sw == 2,
              "Gen 2: the day's pool share (" .. tostring(grass and grass.chanceText) .. ", " .. #sw .. " rows)")
      T.check(rod and rod.chanceText == "35%" and rod.lo == 12, "Gen 2: a Good Rod's row (" ..
              tostring(rod and rod.chanceText) .. ")")
    else
      local rod = rowOf(sw, "super")
      T.check(grass and grass.chanceText == "20%" and #sw == 2,
              "Gen 1: a slot of its own (" .. tostring(grass and grass.chanceText) .. ", " .. #sw .. " rows)")
      T.check(rod and rod.chanceText == "25%" and rod.lo == 5, "Gen 1: the Super Rod's list (" ..
              tostring(rod and rod.chanceText) .. ")")
    end
    -- (WoobleSpawns 0.18.0: its own odds, map by map)
    useEnc = true
    sw = Dx.page(pidgey).where
    grass = rowOf(sw, "grass")
    local rodRow = rowOf(sw, GEN == 2 and "good" or "super")
    if GEN == 2 then
      T.check(grass and grass.chanceText == "25%" and grass.lo == 2 and grass.hi == 5,
              "its encounters export: the best of the morning, day and night (" .. tostring(grass and grass.chanceText) .. ")")
      T.check(rodRow and rodRow.chanceText == "40%" and rodRow.lo == 12, "its Good Rod's odds")
    else
      T.check(grass and grass.chanceText == "21%", "its encounters export: its own odds (" ..
              tostring(grass and grass.chanceText) .. ")")
      T.check(rodRow and rodRow.chanceText == "30%" and rodRow.lo == 5, "its Super Rod's odds")
    end
    useEnc = false
    on = false
    T.eq(#Dx.page(pidgey).where, #wp.where, "WoobleSpawns off: the cart's own again")
    Sa.spawns = prevS
  end
  -- (the START menu's Pokédex: ours, the game's flow after)
  local Tm = X._test.townmap
  local backed = false
  local optsD = GEN == 2 and { onClose = function() stack:pop(); backed = true end }
    or { onCancel = function() backed = true end }
  Screens.push(game, GEN == 2 and "Gen2PokedexMenu" or "PokedexMenu", optsD)
  frame(2)
  T.check(Tm and Tm.isOpen() and Tm.state().ctx.app == "pokedex", "the START menu's Pokédex: ours")
  frame(10)
  if Tm and Tm.isOpen() then Tm.state().ctx.done() end
  frame(1)
  T.check(backed and #stack.states == base, "closed: back to the START menu's flow")
end

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
  for _, id in ipairs({ "storage", "items", "mail", "hall", "oak", "settings", "mart", "bank", "auction", "slots",
                        "gts", "errands", "challenges", "news", "pokedex", "map", "radio", "phone" }) do
    if (id ~= "mail" and id ~= "radio" and id ~= "phone") or GEN == 2 then
      local okO = D.openApp(id)
      T.check(okO, "the " .. id .. " app opens")
      -- (every window's cards and rows settle in for half a second in glass: frames past that, and past the
      -- JIT compiling their traces, which lands on the heap once, before measuring)
      local okDr, errDr = pcall(function() frame(150) end)
      T.check(okDr, "the " .. id .. " window draws (" .. tostring(errDr) .. ")")
      if okO and okDr then
        opened = opened + 1
        local kb = garbageOf(30, function() frame() end)
        T.check(kb < 0.5, ("the %s window: next to no garbage (%.3f KB/frame)"):format(id, kb))
        if os.getenv("GB_KB") then print(("KB %s %.3f"):format(id, kb)) end
      end
      -- (Boxes: the summary's three tabs draw)
      local W = id == "storage" and D.window()
      if W and W.summary then
        W.summary(Bx.addr("party", 1))
        for tab = 1, 3 do
          W.state.sum.tab = tab
          -- (its cards settle in on the wall clock, which these frames outrun: frames until that's done --
          -- the test's stand-in graphics make garbage of their own on each push the motion makes)
          local now = X._test.env.now
          local t0 = now()
          local okS, errS = pcall(function() repeat frame(1) until now() - t0 > 1.2 end)
          T.check(okS and not D.state().winFailed, "the summary draws, tab " .. tab .. " (" .. tostring(errS) .. ")")
          -- (our draw alone: the game's own update makes garbage of its own here)
          local kbS = garbageOf(30, function() Sh.frame(game, VP) end)
          T.check(kbS < 0.5, ("the summary, tab %d: next to no garbage (%.3f KB/frame)"):format(tab, kbS))
        end
        W.state.sum = nil
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
do
  local env = X._test.env
  local was = env.padOption
  env.padOption = function() return false end
  local plain = {}
  for i, r in ipairs(rows) do if not r.woobOs then plain[#plain + 1] = r end end
  local n = #plain
  local off = Sh.startRows(plain)
  local any = false
  for _, r in ipairs(off) do if r.woobOs then any = true end end
  T.check(not any and #off == n, "the WoobPad option off: no row")
  env.padOption = was
end

-- ------- the Mart's clerk: made the way the field makes its people (SpriteRenderer.new), so another mod's
-- sprite set (Facets) is his too; made again when a mod's option changes
do
  local SR = require("src.render.SpriteRenderer")
  local own = SR.new
  local fakeImg = { getDimensions = function() return 32, 288 end }
  local frames = {}
  for i = 0, 8 do frames[i] = { i } end
  local gdData = X._test.gd.data()
  local set = gdData and (GEN == 2 and gdData.gen2Sprites or gdData.sprites)
  local clerkDef = set and set.SPRITE_CLERK
  SR.new = function(def, seed, ...)
    if def ~= nil and def == clerkDef then
      return { def = { id = "SPRITE_CLERK", image = "facets/x.png", gbaArt = true }, image = fakeImg, frames = frames,
               frameWidth = 32, frameHeight = 32, frameCount = 9 }
    end
    return own(def, seed, ...)
  end
  run.loader.events:emit("mod.options_changed", { mod = "facets", key = "classicNpcs" })
  local c = X._test.env.clerk()
  -- (the test's data may have no clerk's sprite: nothing to stand in for then)
  T.check(clerkDef == nil or (c and c.image == fakeImg and c.width == 32 and c.height == 32 and c.frameCount == 9
    and c.quads == frames), "the clerk: another mod's sprite set's sheet when it has one")
  SR.new = own
  run.loader.events:emit("mod.options_changed", { mod = "facets", key = "classicNpcs" })
  local c2 = X._test.env.clerk()
  T.check(c2 == nil or (c2.image ~= fakeImg and c2.width == 16), "the set off: the game's own again")
end

-- ------- the real shops: a counter's screen opens our Mart full screen with its own goods; the game hears
-- what its screen would say
do
  local Tm = X._test.townmap
  local Gd = X._test.gd
  -- (a TM names its move, and says what the move does as the game's TM pocket does)
  local tmId
  for id, it in pairs(data.items or {}) do
    if not tmId and type(it) == "table" and tostring(it.name or ""):match("^TM%d") and Gd.tmMove(id) then tmId = id end
  end
  local tmName, tmDesc = tmId and Gd.itemName(tmId) or "", tmId and Gd.itemDesc(tmId) or ""
  T.check(tmId ~= nil and tmName:match("^TM%d+ %a") ~= nil and tmDesc ~= "" and tmDesc ~= "?",
          "a TM: " .. tmName .. " (" .. tmDesc .. ")")
  if os.getenv("GB_KB") then print("TM " .. tmName .. " | " .. tmDesc) end
  local closed = 0
  local c
  if GEN == 2 then
    c = Screens.build(game, "Gen2MartMenu", { save = save, items = data.items, marts = data.gen2Marts, martType = 0,
                                              martId = 0, onClose = function() stack:pop(); closed = closed + 1 end })
  else
    c = Screens.build(game, "ShopMenu", { "POKE_BALL", "POTION", "ANTIDOTE" }, function() closed = closed + 1 end)
  end
  T.check(type(c) == "table" and c.open ~= nil, "a shop counter: ours (a carrier)")
  stack:push(c)
  frame(2)
  T.check(Tm.isOpen() and Tm.state().ctx.shop ~= nil, "the Mart opens full screen")
  T.check(Tm.veiling() and Tm.state().veil.phase == "in", "through black from the field")
  unveil()
  T.check(not Tm.veiling(), "  then the shop, still")
  local shopM = Tm.isOpen() and Tm.state().ctx.shop
  local first = shopM and shopM.tabs()[1].rows[1]
  T.check(first ~= nil and first.price > 0, "its goods: " .. tostring(first and first.name))
  Gd.setMoney(save, 100000)
  local had = X._test.mart.inBag(save, first.id)
  local okB = shopM.buy(save, first.id, 2)
  T.check(okB and X._test.mart.inBag(save, first.id) == had + 2 and Gd.money(save) == 100000 - first.price * 2,
          "two bought, at its price")
  frame(30)
  T.check(not Tm.state().winFailed, "the shop draws")
  Tm.state().ctx.done()
  frame(2)
  T.check(Tm.isOpen() and Tm.veiling() and closed == 0, "closing: back through black, the game waiting")
  unveil()
  frame(2)
  T.check(not Tm.isOpen() and closed == 1 and #stack.states == base, "closed: the game's own answer, the stack as it was")
  if GEN == 2 then
    -- (the Underground's bargain stall: its own prices, one of each, buy only)
    local bc = Screens.build(game, "Gen2MartMenu", { save = save, items = data.items, marts = data.gen2Marts,
                                                     martType = 2, onClose = function() stack:pop() end })
    stack:push(bc)
    frame(2)
    local bm = Tm.isOpen() and Tm.state().ctx.shop
    T.check(bm and bm.buyOnly and bm.oneEach and bm.MAX_QTY == 1, "the bargain stall: buy only, one of each")
    local row = bm and bm.tabs()[1].rows[1]
    if row then
      T.check(bm.buy(save, row.id, 5) and save.bargainShop and save.bargainShop[row.id] == true, "bought: marked, as the game marks it")
      T.check(select(2, bm.buy(save, row.id, 1)) == "gone", "then sold out")
    end
    if Tm.isOpen() then Tm.state().ctx.done() end
    unveil()
    frame(2)
    T.eq(#stack.states, base, "the stack as it was")
  end
end

-- ------- the Pokémon Center: the nurse's counter opens ours full screen; the machine heals the team as the
-- game's does, with the game's own side effects; the game goes on when ours closes
do
  local Tm, Pc = X._test.townmap, X._test.pokecenter
  T.check(Pc ~= nil, "the Pokémon Center's takeover is made")
  local function inp(k)
    return { wasPressed = function(_, kk) return kk == k end, isDown = function() return false end }
  end
  local NONE = inp(nil)
  local function f(n, key)
    for i = 1, n do
      clock = clock + 1 / 60
      Tm.input(i == 1 and key and inp(key) or NONE)
      Tm.draw(G, VP)
    end
  end
  local function hurt()
    for _, m in ipairs(save.party) do m.hp = 1 end
  end
  local function full()
    for _, m in ipairs(save.party) do
      local max = GEN == 2 and m.maxHp or m.stats.hp
      if m.hp ~= max then return false end
    end
    return true
  end
  -- (her greeting to the choice; Heal; the machine; her words to "anything else?"; B, her goodbye; A)
  local function walk(st, label)
    -- (it fades in from the field, the field shown under it, then her counter up from black)
    local W = Tm.state().win
    T.check(W.see() == true and st.scene == "in", label .. ": it opens over the field, fading to black")
    f(80)
    T.check(not W.see() and st.scene == "nurse", label .. ": then her counter")
    for _ = 1, 10 do
      if st.menu then break end
      f(1, "a")
      f(3)
    end
    T.check(st.menu and st.cursor == 1, label .. ": her greeting and the choice (" .. tostring(st.say and st.say.text) .. ")")
    f(1, "a")
    for _ = 1, 6 do
      f(1, "a")
      f(20)
      if st.turnT or st.fadeT or st.scene == "machine" then break end
    end
    for _ = 1, 60 * 14 do
      f(1)
      if st.scene == "machine" and st.mc and st.mc.placed >= 1 and not st.seenBall then st.seenBall = true end
      if st.seenBall and st.scene == "nurse" and st.black == 0 then break end
    end
    T.check(st.seenBall and st.scene == "nurse", label .. ": the machine, then back to her")
    T.check(full(), label .. ": every HP full")
    for _ = 1, 30 do
      if st.menu then break end
      f(1, "a")
      f(3)
    end
    T.check(st.menu and st.say.text:find("anything else", 1, true) ~= nil, label .. ": anything else?")
    local kb = math.huge
    for _ = 1, 2 do
      collectgarbage("collect")
      collectgarbage("stop")
      local k0 = collectgarbage("count")
      for _ = 1, 120 do
        clock = clock + 1 / 60
        Tm.draw(G, VP)
      end
      kb = math.min(kb, (collectgarbage("count") - k0) / 120)
      collectgarbage("restart")
    end
    T.check(kb < 0.5, ("%s: the counter's draw %.3f KB a frame"):format(label, kb))
    f(1, "b")
    f(40)
    f(1, "a")
    -- (her counter to black, then the field back up from it under us; closed once it's up)
    local sawField = false
    for _ = 1, 120 do
      f(1)
      if not Tm.isOpen() then break end
      if W.see() then sawField = true end
    end
    T.check(sawField and not Tm.isOpen(), label .. ": out to black, the field back up, closed")
  end
  save.party = { newMon(GEN == 2 and "CYNDAQUIL" or "PIKACHU", 10), newMon("PIDGEY", 6) }
  hurt()
  if GEN == 1 then
    overworld.map = { id = "VIRIDIAN_POKECENTER" }
    overworld.player = { cellX = 3, cellY = 4 }
    overworld.lastOutdoor = { id = "VIRIDIAN_CITY", x = 23, y = 26 }
    save.lastHeal, save.usedPokecenter = nil, nil
    local done = 0
    local npc = { facePlayer = noop }
    overworld:nurseHeal(function() done = done + 1 end, npc)
    T.check(Tm.isOpen() and Tm.state().ctx.app == "pokecenter", "the nurse: ours, full screen")
    walk(Tm.state().win.state, "Red / Blue / Yellow")
    T.check(not Tm.isOpen() and done == 1 and #stack.states == base, "closed: the field goes on (once)")
    T.check(save.lastHeal and save.lastHeal.map == "VIRIDIAN_POKECENTER" and save.lastHeal.x == 3
            and save.lastHeal.outdoor and save.lastHeal.outdoor.id == "VIRIDIAN_CITY", "the blackout point set here")
    T.check(save.usedPokecenter == true, "\"used a Pokémon Center\"")
    -- (Yellow's Pewter scene stays the game's)
    overworld.map = { id = "PEWTER_POKECENTER" }
    overworld.pikachuPewterSleepScene = true
    T.check(Pc.open1(overworld, noop, npc) == false and not Tm.isOpen(), "Pewter's sleeping-Jigglypuff scene: the game's")
    overworld.pikachuPewterSleepScene = nil
  else
    local Pokerus = require("src.core.gen2.Pokerus")
    local events, flags, ran = { [810] = GAME == "crystal" }, {}, {}
    local vm = { scriptVar = 0, getTimeOfDayFn = function() return 2 end,
                 specials = { party = function() return save.party end } }
    vm.healPartyFn = function() for _, m in ipairs(save.party) do m.hp = m.maxHp end end
    function vm:resume(v)
      local ok, err = coroutine.resume(self.co, v)
      if not ok then error(err) end
    end
    local function nxt(_, op, _, row)
      ran[#ran + 1] = op
      if op == "checkevent" then vm.scriptVar = events[row.event] and 1 or 0
      elseif op == "clearevent" then events[row.event] = false
      elseif op == "checkphonecall" then vm.scriptVar = 0
      elseif op == "checkflag" then vm.scriptVar = flags[row.flag] and 1 or 0
      elseif op == "setflag" then flags[row.flag] = true
      elseif op == "specialphonecall" then vm.call = row.args[1]
      elseif op == "jumpstd" then vm.theirs = true end
    end
    local inParty = Pokerus.inParty
    Pokerus.inParty = function() return true end
    vm.co = coroutine.create(function()
      Pc.command(nxt, { vm = vm }, "jumpstd", {}, { op = "jumpstd", std = "PokecenterNurseScript" })
      vm.finished = true
    end)
    vm:resume()
    Pokerus.inParty = inParty
    T.check(Tm.isOpen() and Tm.state().ctx.app == "pokecenter" and not vm.finished, "her script held, ours open")
    local st = Tm.state().win.state
    T.eq(st.model.time, "night", "the game's time of day")
    T.eq(st.model.greet, GAME == "crystal" and "pokecom" or nil, "Crystal's Pokécom Center welcome")
    walk(st, "Gold / Silver / Crystal")
    T.check(not Tm.isOpen() and vm.finished and not vm.theirs and #stack.states == base, "closed: her script ends, never run")
    T.check(flags[13] == true and vm.call == 1, "Pokérus: flag 13 set, Prof. Elm's call")
    if GAME == "crystal" then T.check(events[810] == false, "the Pokécom welcome cleared") end
  end
end

-- ------- Gen 3's item pictures (src/gb/gen3_icons.lua): these games' items matched to Gen 3's numbers
do
  local Gi = X._test.env.gen3Icons
  T.check(Gi ~= nil, "Gen 3's item pictures: made")
  if Gi then
    T.eq(Gi.number("POTION"), 13, "Potion: by name")
    T.eq(Gi.number("POKE_BALL"), 4, "Poké Ball")
    T.eq(Gi.number("PARLYZ_HEAL"), 18, "Parlyz Heal: Gen 3's Paralyze Heal")
    T.eq(Gi.number("THUNDERSTONE"), 96, "Thunderstone: Thunder Stone")
    T.eq(Gi.number("NOT_AN_ITEM"), nil, "an unknown item: none (its tile)")
    T.eq(Gi.number(nil), nil, "no id: none")
    if GEN == 1 then
      T.eq(Gi.number("TM_MEGA_PUNCH"), 293, "TM01 Mega Punch (Normal): a Normal disc")
      T.eq(Gi.number("TM_ICE_BEAM"), 295, "Ice Beam (Ice): an Ice disc")
      T.eq(Gi.number("HM_SURF"), 341, "HM Surf (Water): HM03's")
    else
      T.eq(Gi.number("TM_DYNAMICPUNCH"), 289, "TM01 DynamicPunch (Fighting): a Fighting disc")
      T.eq(Gi.number("TM_FURY_CUTTER"), nil, "Fury Cutter (Bug): Gen 3 has no Bug disc, its tile")
      T.eq(Gi.number("HM_WHIRLPOOL"), 341, "HM Whirlpool (Water): a Water HM")
      T.eq(Gi.number("MIRACLEBERRY"), 141, "MiracleBerry: the Lum Berry")
    end
    -- (headless: no image module, so no picture is found and the tile is drawn, as with no Gen 3 game)
    T.eq(Gi.source(), nil, "headless: no Gen 3 pictures")
    T.eq(Gi.draw(X._test.kit.graphics(), "POTION", 0, 0, 1, 1), false, "and nothing drawn")
    local ok = pcall(X._test.env.itemIcon, "POTION", 0, 0, 20, 1)
    T.check(ok, "the item's picture: its tile")
  end
end

-- ------- the map's objectives (src/gb/objectives.lua): each place's from the cart, ticked from the save
do
  local O = X._test.env.objectives
  T.check(O ~= nil, "the map's objectives: made")
  local idx = O and O.index()
  T.check(type(idx) == "table" and next(idx) ~= nil, "read from the cart")
  local function find(kind, word)
    for sec, b in pairs(idx or {}) do
      for _, e in ipairs(b[kind] or {}) do
        local w = e.name or e.beat or e.kind
        if tostring(w):find(word, 1, true) then return sec, e end
      end
    end
  end
  local counts = { story = 0, gym = 0, key = 0, people = 0, shops = 0 }
  for _, b in pairs(idx or {}) do for k in pairs(counts) do counts[k] = counts[k] + #b[k] end end
  print(string.format("  objectives: %d story, %d gyms / Elite Four, %d key items, %d people, %d shops",
    counts.story, counts.gym, counts.key, counts.people, counts.shops))
  if GEN == 2 then
    local sec, g = find("gym", "Falkner")
    T.check(sec == "lm6" and g.flag == "EVENT_BEAT_FALKNER", "Falkner at Violet City, done by beating him ("
      .. tostring(sec) .. ", " .. tostring(g and g.flag) .. ")")
    T.check(counts.gym >= 20, "every Gym Leader and the Elite Four (" .. counts.gym .. ")")
    local ks, k = find("key", "Squirtbottle")
    T.check(ks ~= nil and k.flag == "EVENT_GOT_SQUIRTBOTTLE", "the SquirtBottle, done by its event (" .. tostring(k and k.flag) .. ")")
    T.check(find("key", "HM") ~= nil, "HMs among the key items")
    T.check(find("people", "nameRater") ~= nil, "the Name Rater")
    T.check(find("people", "daycare") ~= nil, "the Day Care")
    T.check(find("story", "elm") ~= nil and find("story", "radioTower") ~= nil, "the story's beats, placed")
    T.check(counts.shops >= 10, "the marts (" .. counts.shops .. ")")
    local fk
    for _, e in ipairs(O.at("lm6", save, false) or {}) do if e.kind == "gym" then fk = e end end
    T.check(fk ~= nil and fk.done == false and fk.label:find("Falkner") ~= nil, "Violet City: Falkner, not yet ("
      .. tostring(fk and fk.label) .. ")")
    local id
    for i, n in ipairs(data.gen2Constants.eventFlagOrder) do if n == "EVENT_BEAT_FALKNER" then id = i - 1 end end
    -- (the World's own flags for the save in play; another save's kept bytes)
    local get = world.events.get
    world.events.get = function(_, i) return i == id end
    for _, e in ipairs(O.at("lm6", save, false) or {}) do if e.kind == "gym" then fk = e end end
    T.check(fk ~= nil and fk.done == true, "and done once beaten (the World's flags)")
    world.events.get = get
    local other = { events = { [math.floor(id / 8)] = 2 ^ (id % 8) } }
    for _, e in ipairs(O.at("lm6", other, false) or {}) do if e.kind == "gym" then fk = e end end
    T.check(fk ~= nil and fk.done == true, "and another save's, from its kept flags")
  else
    local sec, g = find("gym", "Brock")
    T.check(sec == "PEWTER_CITY" and g.flags[1] == "EVENT_BEAT_BROCK", "Brock at Pewter City, done by beating him ("
      .. tostring(sec) .. ")")
    T.check(counts.gym >= 12, "the Gym Leaders and the Elite Four (" .. counts.gym .. ")")
    T.eq(find("key", "Bicycle"), "CERULEAN_CITY", "the Bicycle at Cerulean City")
    T.check(find("key", "HM01") ~= nil, "HM01 Cut, from the captain's script")
    T.eq(find("people", "nameRater"), "LAVENDER_TOWN", "the Name Rater at Lavender Town")
    T.eq(find("story", "pokedex"), "PALLET_TOWN", "the Pokédex at Pallet Town")
    T.check(counts.shops >= 8, "the marts (" .. counts.shops .. ")")
    local bk
    for _, e in ipairs(O.at("PEWTER_CITY", save, false) or {}) do if e.kind == "gym" then bk = e end end
    T.check(bk ~= nil and bk.done == false, "Pewter City: Brock, not yet")
    save.flags = save.flags or {}
    save.flags.EVENT_BEAT_BROCK = true
    for _, e in ipairs(O.at("PEWTER_CITY", save, false) or {}) do if e.kind == "gym" then bk = e end end
    T.check(bk ~= nil and bk.done == true, "and done once beaten")
    save.flags.EVENT_BEAT_BROCK = nil
  end
  -- (every label made, nothing missing a word)
  local missing = 0
  for sec in pairs(idx or {}) do
    for _, e in ipairs(O.at(sec, save, true) or {}) do
      if type(e.label) ~= "string" or e.label == "" or e.label:find("^map%.obj") then
        missing = missing + 1
        if missing < 4 then print("  no words: " .. tostring(e.label)) end
      end
    end
  end
  T.eq(missing, 0, "every entry has its words")
  if os.getenv("OBJ_DUMP") then
    local secs = {}
    for sec in pairs(idx or {}) do secs[#secs + 1] = sec end
    table.sort(secs)
    for _, sec in ipairs(secs) do
      local parts = {}
      for _, e in ipairs(O.at(sec, save, true) or {}) do parts[#parts + 1] = e.kind:sub(1, 1) .. ":" .. e.label end
      print(sec, table.concat(parts, " | "))
    end
  end
end

-- ------- OPTIONS, modern (src/gb/options.lua): the game's screen's place taken, its rows ours, answered as it would
do
  local Tm = X._test.townmap
  local Go = X._test.gbOptions
  T.check(Go ~= nil, "OPTIONS: the takeover made")
  local id = GEN == 2 and "Gen2OptionsMenu" or "OptionsMenu"
  local base0 = #stack.states
  local done, cancelled = 0, 0
  game.options = game.options or save.options or {}
  save.options = save.options or game.options
  local opts = GEN == 2 and { options = game.options, onDone = function() done = done + 1; stack:pop() end }
    or { onCancel = function() cancelled = cancelled + 1 end }
  local writes = 0
  game.writeOptions = function() writes = writes + 1 end
  game.persistOptions = game.writeOptions
  game.applyOptions = function() end
  local c = Screens.push(game, id, opts)
  T.check(type(c) == "table" and c.opts ~= nil, "OPTIONS: ours (a carrier in its place)")
  frame(2)
  local st = Tm and Tm.isOpen() and Tm.state()
  T.check(st and st.ctx.app == "options", "the window open, full screen")
  local W = st and st.win
  local ws = W and W.state
  local P = ws and ws.pages[#ws.pages]
  T.check(P ~= nil and #P.rows >= 4, "the top page: the game's rows (" .. tostring(P and #P.rows) .. ")")
  local groups, wr = 0, nil
  for _, r in ipairs(P and P.rows or {}) do
    if r.kind == "group" then groups = groups + 1 end
    if r.id == "woob_os" then wr = r end
  end
  T.check(groups >= 3, "the game's pages (speed, video, audio...): " .. groups)
  T.check(wr ~= nil and wr.modName == "Mod" and wr.label == "WoobOS", "WoobOS's row: its name, tagged ("
    .. tostring(wr and wr.label) .. ", " .. tostring(wr and wr.modName) .. ")")
  local tagged = 0
  for _, r in ipairs(P and P.rows or {}) do if r.modName then tagged = tagged + 1 end end
  T.eq(tagged, 1, "only the mod's row tagged")
  -- (the speed page: A opens it; its text speed steps and the game keeps it)
  local gi
  for i, r in ipairs(P and P.rows or {}) do if r.id == "group.speed" then gi = i end end
  T.check(gi ~= nil, "the SPEED page")
  if gi then
    P.cur = gi
    pressedNow = { a = true }
    frame(1)
    frame(2)
    local P2 = ws.pages[#ws.pages]
    T.check(#ws.pages == 2 and P2 ~= P, "A: the page opened (" .. tostring(P2 and P2.title) .. ")")
    local ti
    for i, r in ipairs(P2.rows) do if r.id == "textSpeed" then ti = i end end
    T.check(ti ~= nil and P2.rows[ti].valueText ~= nil, "Text speed with its value ("
      .. tostring(ti and P2.rows[ti].valueText) .. ")")
    if ti then
      P2.cur = ti
      local before = save.options.textSpeed or game.options.textSpeed
      local v0 = P2.rows[ti].valueText
      pressedNow = { right = true }
      frame(1)
      frame(2)
      local after = save.options.textSpeed or game.options.textSpeed
      T.check(after ~= before and P2.rows[ti].valueText ~= v0, "Right: it changes (" .. tostring(before) .. " -> "
        .. tostring(after) .. ", " .. tostring(v0) .. " -> " .. tostring(P2.rows[ti].valueText) .. ")")
      T.check(writes > 0, "and the game keeps it")
      pressedNow = { left = true }
      frame(1)
    end
    pressedNow = { b = true }
    frame(1)
    T.eq(#ws.pages, 1, "B: back to the top")
  end
  pressedNow = { b = true }
  frame(1)
  frame(2)
  T.check(not Tm.isOpen(), "B at the top: closed")
  if GEN == 2 then T.eq(done, 1, "the game told once (onDone; it pops ours)")
  else T.eq(cancelled, 1, "the game told once (onCancel)") end
  T.eq(#stack.states, base0, "the stack as it was")
  -- (the switch off: the game's own)
  run.loader.modOptions.woob_os = { menuOptions = false }
  local own = Screens.build(game, id, GEN == 2 and { options = game.options, onDone = noop } or {})
  T.check(type(own) == "table" and own.opts == nil and own.rows ~= nil, "Options off: the game's own")
  run.loader.modOptions.woob_os = nil
end

-- ------- the staged scenes (src/gb/scenes.lua): an evolution, a first catch's page, a nickname -- ours, full screen
do
  local Ts = X._test.sceneHost
  T.check(Ts ~= nil and X._test.scenes ~= nil, "the scenes: made")
  local base0 = #stack.states
  -- (A now and then, until `done`)
  local function drive(done, limit)
    for i = 1, limit or 4000 do
      if done() then return true end
      if i % 12 == 0 then pressedNow = { a = true } end
      frame(1)
    end
    return done()
  end
  local function sceneState() return Ts.isOpen() and Ts.state() and Ts.state().win and Ts.state().win.state end
  -- (the keyboard: a name typed, then OK)
  local function typeName(text)
    local ok = drive(function() local s = sceneState() return s ~= nil and s.kb ~= nil end, 1500)
    local s = sceneState()
    if not (ok and s and s.kb) then return false end
    s.kb.text = text
    pressedNow = { start = true }
    frame(1)
    pressedNow = { a = true }
    frame(1)
    return true
  end

  -- an evolution
  local evoMon = newMon("PIDGEY", 18)
  local evolved, result = 0, nil
  if GEN == 1 then
    require("src.pokemon.Evolution").evolve(game, evoMon, "PIDGEOTTO", function() evolved = evolved + 1 end, "LEVEL", false)
  else
    save.party[3] = evoMon
    Screens.push(game, "Gen2EvolutionAnim", { mon = evoMon, entry = { into = "PIDGEOTTO", method = "EVOLVE_LEVEL" },
      index = 3, party = save.party, save = save, onDone = function(r)
        evolved, result = evolved + 1, r
        stack:pop()
      end })
    frame(2)
  end
  T.check(Sh.sceneOpen("evolution"), "an evolution: ours, full screen")
  T.check(drive(function() return evolved > 0 and not Ts.isOpen() end), "it plays through, the game told once ("
    .. evolved .. ")")
  local now = GEN == 2 and save.party[3] or evoMon
  T.check(now and now.species == "PIDGEOTTO", "and the Pokémon evolved (" .. tostring(now and now.species) .. ")")
  if GEN == 2 then
    T.check(result and result.canceled == false and result.evolved == save.party[3], "the game's result: evolved, its record")
    save.party[3] = nil
  end
  T.eq(#stack.states, base0, "the stack as it was")

  -- a first catch's page, its question answered there (a name), the battle's then not asked
  local caught = newMon("RATTATA", 4)
  local fakeBattle
  if GEN == 1 then
    fakeBattle = setmetatable({ isBattleState = true, enemy = { mon = caught }, game = game },
                              { __index = require("src.battle.BattleState") })
  else
    fakeBattle = setmetatable({ screenId = "Gen2BattleState", isBattle = true, battle = { enemy = caught }, game = game,
                                advanceQueue = function(self) self.advanced = true end },
                              { __index = require("src.ui.gen2.BattleState") })
  end
  table.insert(stack.states, fakeBattle)
  local base1 = #stack.states
  local pageDone = 0
  if GEN == 1 then
    Screens.push(game, "DexEntryMenu", "RATTATA", function() pageDone = pageDone + 1 end)
  else
    Screens.push(game, "Gen2PokedexMenu", { entrySpecies = "RATTATA", newEntry = true, onClose = function()
      pageDone = pageDone + 1
      stack:pop()
    end })
  end
  frame(2)
  T.check(Sh.sceneOpen("caught") and sceneState() and Ts.state().ctx.scene.kind == "dex", "the catch's page: ours")
  T.check(typeName("RATS"), "its question: yes, the keyboard")
  T.check(drive(function() return pageDone > 0 and not Ts.isOpen() end, 600), "the page closes, the game told once")
  T.eq(#stack.states, base1, "the battle on top again")
  local q
  if GEN == 1 then
    q = fakeBattle:askNicknameUI(caught, "RATTATA")
    T.check(type(q) == "table" and q.choice == nil and q.update ~= nil, "the battle's question: not asked")
  else
    fakeBattle:askNickname(caught)
    T.check(fakeBattle.advanced == true and fakeBattle.phase == "resolving", "the battle's question: not asked, on it goes")
  end
  T.eq(caught.nickname, "RATS", "the name from the page")
  -- (no page answer: the battle asks as ever)
  local other = newMon("SPEAROW", 4)
  if GEN == 1 then
    -- (headless the game's own question has no ROM text to say: its error is the game's, not ours)
    local okQ, q2 = pcall(fakeBattle.askNicknameUI, fakeBattle, other, "SPEAROW")
    T.check(not okQ or (type(q2) == "table" and q2.choice ~= nil), "another catch: the game's own question")
  else
    fakeBattle.advanced = nil
    fakeBattle:askNickname(other)
    T.check(fakeBattle.phase == "ask-nickname", "another catch: the game's own question")
  end
  while #stack.states >= base1 do stack:pop() end

  -- a nickname, the naming screen's (a gift, an Egg, the Name Rater)
  local named, gotName = 0, nil
  local gift = newMon("EEVEE", 5)
  if GEN == 1 then
    Screens.push(game, "NamingScreen", { mon = gift, maxLen = 10, onDone = function(n) named, gotName = named + 1, n end })
  else
    Screens.push(game, "Gen2NamingScreen", { type = "nickname", mon = gift, onDone = function(n)
      named, gotName = named + 1, n
      stack:pop()
    end, onCancel = function() named = named + 1 stack:pop() end })
  end
  frame(2)
  T.check(Sh.sceneOpen("caught") and Ts.state().ctx.scene.kind == "name", "a nickname: ours, the keyboard at once")
  T.check(typeName("Vee"), "a name typed")
  T.check(drive(function() return named > 0 and not Ts.isOpen() end, 600), "closed, the game told once")
  T.eq(gotName, "Vee", "with the name")
  T.eq(#stack.states, base0, "the stack as it was")
  -- (the switch off: the game's own)
  run.loader.modOptions.woob_os = { menuCatch = false }
  -- (headless the game's own Gen 2 keyboard can't be built: no menu art -- not ours either way)
  local okOwn, own = pcall(Screens.build, game, GEN == 2 and "Gen2NamingScreen" or "NamingScreen",
                           GEN == 2 and { type = "nickname", mon = gift, onDone = noop } or { mon = gift, onDone = noop })
  T.check(not okOwn or (type(own) == "table" and own.open == nil), "Catch off: the game's own naming screen")
  run.loader.modOptions.woob_os = nil
end

-- ------- the modern menus (src/gb/menus.lua, src/gb/party.lua): the party menu and the summary in the game's places
do
  local Tm = X._test.townmap
  local Mn, Pt = X._test.menus, X._test.party
  T.check(Mn ~= nil and Pt ~= nil, "the modern menus: made")
  local base0 = #stack.states
  local function win() return Tm.isOpen() and Tm.state() and Tm.state().win end
  local function party() local w = win() return w and w.state and w.state.party end
  local function press1(k) pressedNow = { [k] = true } frame(1) frame(1) end
  local keep = save.party
  save.party = { newMon(GEN == 2 and "CYNDAQUIL" or "CHARMANDER", 12), newMon("PIDGEY", 9), newMon("RATTATA", 7) }
  local pty = save.party

  -- START's
  local cancelled = 0
  if GEN == 2 then
    Screens.push(game, "Gen2PartyMenu", { prompt = "choose", submenu = true, onCancel = function()
      cancelled = cancelled + 1
      stack:pop()
    end })
  else
    Screens.push(game, "PartyMenu", { onCancel = function() cancelled = cancelled + 1 end })
  end
  frame(2)
  local P = party()
  T.check(P ~= nil and P.n == 3 and P.c.mode == "list", "START's party menu: ours, the party's cards (" .. tostring(P and P.n) .. ")")
  local card = P and P.cards[1]
  T.check(card and card.t1 == 10 and card.levelText ~= "" and card.maxHp > 1 and card.expText ~= nil,
          "a card: its type, level, HP and the way to the next level")
  -- (its menu: STATS, SWITCH, CANCEL...; SWITCH then another: the order swapped)
  local rows = Pt.actions(P.c, 1)
  local acts = {}
  for _, r in ipairs(rows) do acts[#acts + 1] = r.act end
  T.check(table.concat(acts, ","):find("SUMMARY,SWITCH", 1, true) ~= nil, "its menu: " .. table.concat(acts, ","))
  press1("a")
  T.check(P.view == "menu", "A: the Pokémon's menu")
  local si
  for k, r in ipairs(P.menu.rows) do if r.act == "SWITCH" then si = k end end
  P.menu.sel = si or 1
  press1("a")
  T.check(P.view == "switch", "SWITCH: choosing the other")
  P.cur = 2
  press1("a")
  T.check(pty[1].species == "PIDGEY" and P.view == "pick", "the two traded places")
  Pt.swap(P.c, 1, 2)
  -- (STATS: the summary inside)
  press1("a")
  for k, r in ipairs(P.menu.rows) do if r.act == "SUMMARY" then P.menu.sel = k end end
  press1("a")
  T.check(P.view == "summary" and P.sum ~= nil, "STATS: the summary, inside the same window")
  press1("b")
  T.check(P.view == "pick", "B: back to the cards")
  press1("b")
  frame(2)
  T.check(not Tm.isOpen() and cancelled == 1, "B: closed, the game told once")
  T.eq(#stack.states, base0, "the stack as it was")

  -- a battle's SWITCH: refused for the one out, a switch for another; the matchups on the cards
  local foe = newMon(GEN == 2 and "TOTODILE" or "SQUIRTLE", 10)
  local fake
  if GEN == 2 then
    fake = { screenId = "Gen2BattleState", isBattle = true, update = function() end, draw = function() end,
             battle = { enemy = foe, player = pty[1], party = pty,
                        battlerTypes = function(_, m) return m.types end } }
  else
    fake = { isBattleState = true, kind = "wild", update = function() end, draw = function() end,
             enemy = { mon = foe, curTypes = { "WATER" } }, player = { mon = pty[1], curTypes = { "FIRE" } } }
  end
  table.insert(stack.states, fake)
  local base1 = #stack.states
  local chosen, refusedOnce = nil, false
  if GEN == 2 then
    local list
    list = Screens.push(game, "Gen2PartyMenu", { prompt = "choose", battle = true, battleSubmenu = true, party = pty,
      save = save, onCancel = function() stack:pop() end,
      onChoose = function(index, mon)
        if mon == fake.battle.player then
          refusedOnce = true
          return list:refuse("Already out!")
        end
        stack:pop()
        chosen = index
      end })
  else
    Screens.push(game, "PartyMenu", { battle = fake, party = pty, keepOpen = true, onSwitch = function(mon, menu)
      if mon == fake.player.mon then
        refusedOnce = true
        return menu:refuse("Already out!")
      end
      menu:close()
      chosen = mon
    end })
  end
  frame(2)
  P = party()
  T.check(P ~= nil and P.c.battle and P.c.mode == "battle_switch", "a battle's party menu: ours")
  local c1 = P and P.cards[1]
  T.check(c1 and c1.defK == 2 and c1.atkK ~= nil, "the matchups: Water on Fire 2x against it, its moves on the foe ("
    .. tostring(c1 and c1.atkK) .. " / " .. tostring(c1 and c1.defK) .. ")")
  -- (the one out: refused, ours stays)
  P.cur = 1
  press1("a")
  P.menu.sel = 1
  press1("a")
  T.check(refusedOnce and Tm.isOpen() and P.prompt ~= nil and P.prompt.kind == "msg", "the one out: the game's words, ours stays")
  press1("a")
  -- (another: switched, ours gone, the battle on top)
  P.cur = 2
  press1("a")
  P.menu.sel = 1
  press1("a")
  frame(2)
  T.check(not Tm.isOpen() and (chosen == 2 or chosen == pty[2]), "another: the game's choice (" .. tostring(chosen) .. ")")
  T.eq(#stack.states, base1, "the battle on top again")
  for i = #stack.states, 1, -1 do if stack.states[i] == fake then table.remove(stack.states, i) end end

  -- the summary from the game's own screens (the PC's STATS)
  local sumClosed = 0
  if GEN == 2 then
    Screens.push(game, "Gen2SummaryMenu", { party = pty, index = 2, onClose = function()
      sumClosed = sumClosed + 1
      stack:pop()
    end })
  else
    Screens.push(game, "SummaryMenu", pty[2])
  end
  frame(2)
  local w = win()
  T.check(w and w.state and w.state.page == "summary" and w.state.sum and w.state.sum.i == 2, "the summary: ours, on that Pokémon")
  press1("b")
  frame(2)
  T.check(not Tm.isOpen() and (GEN == 1 or sumClosed == 1), "B: closed, the game told")
  T.eq(#stack.states, base0, "the stack as it was")
  -- (the switch off: the game's own)
  run.loader.modOptions.woob_os = { menuParty = false }
  local okOwn, own = pcall(Screens.build, game, GEN == 2 and "Gen2PartyMenu" or "PartyMenu",
                           GEN == 2 and { prompt = "choose", submenu = true, onCancel = noop } or { onCancel = noop })
  T.check(not okOwn or (type(own) == "table" and own.woobOsMenu == nil), "Pokémon Menu off: the game's own")
  run.loader.modOptions.woob_os = nil
  save.party = keep
end

-- ------- the Bag (src/gb/bag.lua, src/gb/menus.lua): in the game's place, USE the game's own
do
  local Tm = X._test.townmap
  local Bg = X._test.bag
  T.check(Bg ~= nil, "the Bag's rules: made")
  local base0 = #stack.states
  local function win() return Tm.isOpen() and Tm.state() and Tm.state().win end
  local function bagSt() local w = win() return w and w.state and w.state.bag end
  local function press1(k) pressedNow = { [k] = true } frame(1) frame(1) end
  local keepParty, keepInv = save.party, save.inventory
  save.party = { newMon(GEN == 2 and "CYNDAQUIL" or "CHARMANDER", 12), newMon("PIDGEY", 9) }
  save.inventory = {}
  local Bag = require("src.inventory.Bag")
  Bag.add(save, "POTION", 3, data)
  Bag.add(save, "POKE_BALL", 5, data)
  Bag.add(save, "ANTIDOTE", 2, data)

  -- START's
  local closedN = 0
  if GEN == 2 then
    -- (START's: its USE goes on to the game's own field item use; the stand-in game lent the game's own spending)
    game.consumeItem = require("src.core.Game2").consumeItem
    Screens.push(game, "Gen2PackMenu", { onClose = function() closedN = closedN + 1 stack:pop() end,
                                         onChoose = function(id) require("src.core.Game2").usePartyItem(game, id) end })
  else
    Screens.push(game, "BagMenu", { onClose = function() end, onCancel = function() closedN = closedN + 1 end })
  end
  frame(2)
  local B = bagSt()
  T.check(B ~= nil and B.c.battle == false, "START's Bag: ours")
  T.eq(#B.pockets, GEN == 2 and 4 or 1, "its pockets")
  local rows = Bg.rows(B.c, B.pockets[1])
  local potion
  for _, r in ipairs(rows) do if r.id == "POTION" then potion = r end end
  T.check(potion and potion.qtyText == "×3" and potion.name ~= nil, "a row: its name and how many")
  local acts = {}
  for _, a in ipairs(Bg.actions(B.c, B.pockets[1], potion)) do acts[#acts + 1] = a.act end
  T.check(table.concat(acts, ","):find("USE", 1, true) == 1 and table.concat(acts, ","):find("TOSS", 1, true) ~= nil,
          "its actions: " .. table.concat(acts, ","))
  -- (TOSS: the game's question, then gone)
  local tossed
  for _, r in ipairs(rows) do if r.id == "ANTIDOTE" then tossed = r end end
  local ui = X._test.env.bagCtl and nil
  local asked, said = nil, nil
  Bg.toss(B.c, tossed, 2, { ask = function(text, after) asked = text after(true) end,
                            say = function(text) said = text end, refresh = function() end })
  T.check((save.inventory.ANTIDOTE or 0) == 0 and asked ~= nil, "TOSS: asked, then thrown away")
  -- (USE: the game's own -- a Potion on a hurt Pokémon, its party list a page of ours)
  local mon = save.party[1]
  local maxHp = Gd.maxHp(mon)
  mon.hp = math.max(1, maxHp - 15)
  local hp0 = mon.hp
  -- (headless, Red / Blue / Yellow's own bag can't be built: no ROM text cache -- the in-game driver covers it)
  local okU, errU = GEN == 1 or pcall(function()
    local P0 = B.pockets[1]
    for i, r in ipairs(Bg.rows(B.c, P0)) do if r.id == "POTION" then B.cur = i end end
    B.rows = {}
    Bg.useHandler(potion, X._test.env.bagCtl and { back = function() end } or { back = function() end })
  end)
  if os.getenv("BAG_DEBUG") then
    for i, st0 in ipairs(stack.states) do
      print("  stack", i, tostring(st0.screenId), tostring(rawget(st0, "woobOs")), tostring(st0.woobOsAbove), tostring(st0.woobOsMenu), tostring(st0.pages and #st0.pages))
    end
    print("  cur", tostring(X._test.menus.cur()), "use err", tostring(errU))
  end
  frame(2)
  local w = win()
  local inner = w and w.state and w.state.gameInner
  if GEN == 2 then
    T.check(okU and inner ~= nil and w.state.page == "party", "USE: the game asks which Pokémon, on a page of ours ("
      .. tostring(okU and "" or errU) .. ")")
  end
  if inner then
    local P = w.state.party
    P.cur = 1
    press1("a")
    for _ = 1, 120 do
      if w.state.party and w.state.party.prompt then press1("a") else frame(1) end
      if mon.hp > hp0 and not w.state.gameInner and not (w.state.party and w.state.party.prompt) then break end
    end
    T.check(mon.hp > hp0, "the Potion healed it, the game's own way (" .. hp0 .. " -> " .. mon.hp .. ")")
    T.check((save.inventory.POTION or 0) == 2, "and one was used")
  end
  -- (B away from wherever it is)
  for _ = 1, 6 do
    if not Tm.isOpen() then break end
    press1("b")
  end
  frame(2)
  T.check(not Tm.isOpen() and (GEN == 1 or closedN == 1), "B: closed, the game told")
  while #stack.states > base0 do stack:pop() end

  -- a battle's: a Ball's catch chance
  local foe = newMon("RATTATA", 3)
  local fake
  if GEN == 2 then
    fake = { screenId = "Gen2BattleState", isBattle = true, update = function() end, draw = function() end,
             battle = { enemy = foe, player = save.party[1], party = save.party, wild = true },
             catchChance = function(_, id) return id == "POKE_BALL" and 37.4 or nil end }
  else
    fake = { isBattleState = true, kind = "wild", update = function() end, draw = function() end,
             enemy = { mon = foe }, player = { mon = save.party[1] },
             catchChance = function(_, id) return id == "POKE_BALL" and 37.4 or nil end }
  end
  table.insert(stack.states, fake)
  if GEN == 2 then
    Screens.push(game, "Gen2PackMenu", { battle = true, world = {}, onClose = function() stack:pop() end,
                                         onChoose = function() stack:pop() end })
  else
    Screens.push(game, "BagMenu", { battle = fake })
  end
  frame(2)
  B = bagSt()
  T.check(B ~= nil and B.c.battle == true, "a battle's Bag: ours")
  local ballRow
  for _, p in ipairs(B and B.pockets or {}) do
    for _, r in ipairs(B.rows[p] or Bg.rows(B.c, p)) do if r.id == "POKE_BALL" then ballRow = r end end
  end
  T.eq(Bg.chanceText(Bg.catchChance(B.c, "POKE_BALL")), "37%", "a Ball's catch chance, the battle's own")
  fake.kind, fake.battle = "trainer", fake.battle and { enemy = foe, wild = false } or nil
  T.eq(Bg.catchChance(B.c, "POKE_BALL"), nil, "none in a trainer's battle")
  press1("b")
  frame(2)
  T.check(not Tm.isOpen(), "B: closed")
  for i = #stack.states, 1, -1 do if stack.states[i] == fake then table.remove(stack.states, i) end end
  while #stack.states > base0 do stack:pop() end
  save.party, save.inventory = keepParty, keepInv
end

T.finish("woob_os gb (" .. GAME .. ")")
