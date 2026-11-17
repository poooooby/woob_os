-- Standalone: luajit mods/woob_os/tests/menus_test.lua [game] (from the gen1recomp root; needs that cart
-- imported, Emerald by default).
--
-- The modern menus (src/menus.lua, src/apps/menus.lua over src/apps/summary_ctl.lua and the Boxes'
-- summary view), phase 1: the game's Summary. Its openMenu wrapped once; the party menu's SUMMARY opens
-- ours full screen (Up / Down the party, B back: the cursor and onClose(index) as the game's); a battle's
-- way in (SummaryMenu.isOpen / handleInput, the input once a frame even when the field's layer has it
-- too); choosing a move to forget (the new move below; A forgets one: onClose, then onSelectMove(slot0);
-- the new move or B: nil; an HM refused unless forgetMove); closed from outside (SummaryMenu.close: as B);
-- the game's own for its other callers (the PC's boxes, trades) and with the option off; next to no
-- garbage; the text at 130%.
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
local Mn = X._test.menus
local Stack = require("src.ui.game3.stack")
local SM = require("src.ui.game3.summary_menu")
T.check(Mn ~= nil and SM.__woobOs ~= nil and SM.__woobOs.impl ~= nil, "the summary's takeover is made and wrapped")
local wrapped = SM.openMenu
run.loader.events:emit("game.ready", {})
T.check(SM.openMenu == wrapped, "wrapped once, whatever the game.ready count")

local function input(press)
  local p = {}
  for _, k in ipairs(press or {}) do p[k] = true end
  return { wasPressed = function(_, k) return p[k] == true end, isDown = function() return false end }
end
local VP = { width = 480, height = 320 }
local NONE = input()
-- a frame as the game runs one: the field's layer gets the input, then the HUD's draw (Sh.frame)
local function frame(n, press, battle)
  for i = 1, n or 1 do
    clock = clock + 1 / 60
    local inp = i == 1 and press and input({ press }) or NONE
    if battle then SM.handleInput(inp) else Sh.mapLayer.handleInput(inp) end
    Sh.frame(nil, VP)
  end
end
local function garbageOf(n)
  local best = math.huge
  for _ = 1, 2 do
    collectgarbage("collect")
    collectgarbage("stop")
    local kb = collectgarbage("count")
    for _ = 1, n do
      clock = clock + 1 / 60
      Tm.draw(G, VP)
    end
    best = math.min(best, (collectgarbage("count") - kb) / n)
    collectgarbage("restart")
  end
  return best
end

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
Party.giveMon(s, P.speciesFromNational(129), 5)
T.eq(#s.party, 3, "a team of three")

-- ------- the party menu's SUMMARY: ours, full screen
local closedAt, closedN = nil, 0
SM.openMenu(s.party, 2, { session = s, onClose = function(i) closedN, closedAt = closedN + 1, i end })
T.check(Tm.isOpen() and Tm.state().ctx.app == "menus" and Stack.has(Sh.MAP_ID), "the party's Summary: ours, full screen")
T.check(SM.isOpen() == true, "the game asks: it's open")
local W = Tm.state().win
local S = W.state.sum
T.check(S and S.i == 2 and S.rec and S.rec.mon == s.party[2], "on the one chosen (the second)")
T.check(S.party == true, "its moves may be reordered (the party's own, not in battle)")
frame(3)
T.check(not Tm.state().winFailed, "it draws")
frame(1, "down")
T.eq(S.i, 3, "Down: the next one")
frame(1, "down")
T.eq(S.i, 1, "round to the first")
frame(1, "r")
T.eq(S.tab, 2, "R: the next tab")
local kb = garbageOf(60)
T.check(kb < 0.5, ("the summary: next to no garbage (%.3f KB a frame)"):format(kb))
K.setTextScale(1.3)
T.check(pcall(frame, 20), "the text at 130%")
K.setTextScale(1)
frame(1, "b")
T.check(not Tm.isOpen() and not Stack.has(Sh.MAP_ID), "B: closed")
T.check(closedN == 1 and closedAt == 1 and SM._cursor == 1 and not SM.isOpen(),
        "the game's onClose once, with the cursor (as the game's own: " .. tostring(closedAt) .. ")")

-- ------- in a battle: the game asks SummaryMenu.isOpen() and hands it the input itself
closedN = 0
SM.openMenu(s.party, 1, { session = s, onClose = function() closedN = closedN + 1 end })
S = Tm.state().win.state.sum
frame(2, nil, true)
frame(1, "down", true)
T.eq(S.i, 2, "the battle's input reaches ours")
-- (both ways in one frame: the field's layer and the battle's call; only the first counts)
clock = clock + 1 / 60
Sh.mapLayer.handleInput(input({ "down" }))
SM.handleInput(input({ "down" }))
Sh.frame(nil, VP)
T.eq(S.i, 3, "the input once a frame, however it comes")
frame(1, "b", true)
T.check(not Tm.isOpen() and closedN == 1, "B: closed, onClose once")

-- ------- choosing a move to forget
local mon = s.party[1]
local learnId = 89
local order = {}
local function forget(opts)
  order = {}
  opts.mode, opts.moveToLearn = "select_move", learnId
  opts.onClose = function() order[#order + 1] = "close" end
  opts.onSelectMove = function(slot) order[#order + 1] = slot == nil and "none" or slot end
  SM.openMenu({ mon }, 1, opts)
  -- (a frame with nothing pressed: the A that opened it, let go)
  if Tm.isOpen() then frame(1) end
  return Tm.isOpen() and Tm.state().win.state.sum
end
S = forget({})
T.check(S and S.learn and S.learn.id == learnId and S.tab == 3 and S.move == 1 and S.party == false,
        "choosing a move to forget: the moves, the new one below, none reordered")
frame(2)
local nMoves = #S.rec.moves
frame(1, "down")
T.eq(S.move, 2, "Down: the next move")
frame(1, "up")
frame(1, "a")
T.check(not Tm.isOpen() and order[1] == "close" and order[2] == 0,
        "A: the first forgotten -- onClose, then onSelectMove(0) (" .. table.concat(order, " ") .. ")")
S = forget({})
for _ = 1, nMoves do frame(1, "down") end
T.eq(S.move, nMoves + 1, "down to the new move")
frame(1, "a")
T.check(not Tm.isOpen() and order[1] == "close" and order[2] == "none", "on the new move: none forgotten")
S = forget({})
frame(1, "b")
T.check(order[2] == "none", "B: none forgotten")
-- (an HM: refused, unless the caller lets one go -- the Move Deleter)
local keep = mon.moves[1]
mon.moves[1] = type(keep) == "table" and { id = 15, pp = 30, ppUps = 0 } or 15
pcall(require("src.core.game3.pokemon").isHmMove, 15)
S = forget({})
frame(1, "a")
T.check(Tm.isOpen() and S.hm == true and #order == 0, "an HM: refused, still open")
frame(1, "b")
S = forget({ forgetMove = true })
frame(1, "a")
T.check(not Tm.isOpen() and order[2] == 0, "the Move Deleter's: an HM may go")
mon.moves[1] = keep

-- ------- closed from outside (a battle's end): as B, nothing chosen
order = {}
S = forget({})
SM.close()
T.check(not Tm.isOpen() and order[1] == "close" and order[2] == "none", "SummaryMenu.close(): ours closes as B")

-- ------- the game's own for its other callers (Ruby / Sapphire's own summary has no art headless: there,
-- only that ours declines)
local RS = GAME == "ruby" or GAME == "sapphire"
T.check(Mn.openSummary(s.party, 1, { session = s, context = "box" }) == false, "the PC's boxes: not ours")
T.check(Mn.openSummary(s.party, 1, { session = s, mode = "trade", enemyParty = true }) == false, "a trade's: not ours")
T.check(Mn.openSummary(s.party, 1, { session = s, context = "factory" }) == false, "the Battle Factory's: not ours")
T.check(Mn.openSummary(s.party, 1, { session = s, context = "party", onClose = noop }) == false,
        "Ruby / Sapphire's Day Care (its own context): not ours")
if not RS then
  local box = false
  SM.openMenu(s.party, 1, { session = s, context = "box", onClose = function() box = true end })
  T.check(not Tm.isOpen() and SM.isOpen(), "the PC's boxes: the game's own Summary")
  SM.close()
  T.check(box and not SM.isOpen(), "and it closes as the game's")
end
Mn.on = false
T.check(Mn.openSummary(s.party, 1, { session = s }) == false, "the option off: not ours")
if not RS then
  SM.openMenu(s.party, 1, { session = s })
  T.check(not Tm.isOpen() and SM.isOpen(), "the option off: the game's own")
  SM.close()
end
Mn.on = nil

T.finish("woob_os menus (" .. GAME .. ")")
