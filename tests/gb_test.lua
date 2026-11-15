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
