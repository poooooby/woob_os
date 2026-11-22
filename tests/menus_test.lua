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
-- (each category's own switch under Modern Menus, Battle Menus for one in a battle, the Pokédex too; Modern
-- Menus off: every one)
do
  local L = run.loader
  L.modOptions = L.modOptions or {}
  local keep = L.modOptions.woob_os
  local o = {}
  L.modOptions.woob_os = o
  T.check(Mn.allowed("bag", false) and Mn.allowed("party", true) and Mn.allowed("summary", false)
          and X._test.env.dexOption(), "all on by default")
  o.menuSummary = false
  T.check(not Mn.allowed("summary", false) and Mn.allowed("bag", false) and Mn.allowed("party", false),
          "Summary off: the summary alone")
  T.eq(Mn.openSummary(s.party, 1, { session = s }), false, "and it isn't ours")
  o.menuSummary = nil
  o.menuBag = false
  T.check(not Mn.allowed("bag", false) and not Mn.allowed("bag", true) and Mn.allowed("party", true), "Bag off: the Bag, in battle too")
  o.menuBag = nil
  o.menuParty = false
  T.check(not Mn.allowed("party", false) and Mn.allowed("bag", false), "Pokémon Menu off: the party alone")
  o.menuParty = nil
  o.menuBattle = false
  T.check(Mn.allowed("bag", false) and not Mn.allowed("bag", true) and not Mn.allowed("party", true)
          and not Mn.allowed("summary", true) and Mn.allowed("summary", false), "Battle Menus off: the game's in a battle only")
  o.menuBattle = nil
  o.pokedex = false
  T.check(not X._test.env.dexOption() and Mn.allowed("bag", false), "Pokédex off: the Pokédex alone")
  o.pokedex = nil
  o.modernMenus = false
  T.check(not Mn.allowed("bag", false) and not Mn.allowed("party", false) and not Mn.allowed("summary", false)
          and not X._test.env.dexOption(), "Modern Menus off: every one, the Pokédex too")
  L.modOptions.woob_os = keep
  -- (the options page: each one shown only with Modern Menus on)
  local rows = dofile("mods/woob_os/options.lua")
  local under = {}
  for _, r in ipairs(rows) do
    if r.visible_if and r.visible_if.key == "modernMenus" and r.visible_if.equals == true then under[#under + 1] = r.key end
  end
  T.eq(table.concat(under, " "), "pokedex menuBag menuParty menuSummary menuBattle gearMenus",
       "under Modern Menus: " .. table.concat(under, " "))
  for _, r in ipairs(rows) do
    local n = #r.label:gsub("[\128-\191]", "")
    T.check(n <= 14 or r.key == "gearMenus", "label fits: " .. r.label)
    -- (a row under another starts "- ", the rest don't)
    T.check((r.visible_if ~= nil) == (r.label:sub(1, 2) == "- "), "a sub-option marked as one: " .. r.label)
  end
end
Mn.on = false
T.check(Mn.openSummary(s.party, 1, { session = s }) == false, "the option off: not ours")
if not RS then
  SM.openMenu(s.party, 1, { session = s })
  T.check(not Tm.isOpen() and SM.isOpen(), "the option off: the game's own")
  SM.close()
end
Mn.on = nil

-- =================== phase 2: the party menu
local PM = require("src.ui.game3.party_menu")
T.check(PM.__woobOs ~= nil and PM.__woobOs.impl ~= nil, "the party menu's takeover is made and wrapped")
local wrappedShow = PM.show
run.loader.events:emit("game.ready", {})
T.check(PM.show == wrappedShow, "the party menu wrapped once")
local I = require("src.core.game3.items_data")
local POTION, RARE_CANDY, TM28, ORAN = 13, 68, 316, 139
-- (Ruby / Sapphire headless have no fonts of their own to lay the game's text boxes out with: its words
-- stand in as their keys)
if RS then
  local RomText = require("src.core.game3.rom_text")
  RomText.box = function(key, ctx) return tostring(key) end
end
-- (a frame for the party: the field's layer, or a battle handing the party menu its input)
local function pframe(n, press, battle)
  for i = 1, n or 1 do
    clock = clock + 1 / 60
    local inp = i == 1 and press and input({ press }) or NONE
    if battle then PM.handleInput(inp) else Sh.mapLayer.handleInput(inp) end
    Sh.frame(nil, VP)
  end
end
local function party() return Tm.isOpen() and Tm.state().win.state.party or nil end
local function open(opts, list)
  PM.show(list or s.party, nil, opts)
  if Tm.isOpen() then pframe(1) end
  return party()
end
-- (every page of what the game says, and its questions, answered A until it's done or `limit`)
local function through(limit, battle)
  for _ = 1, limit or 30 do
    local P = party()
    if not P or not (P.prompt or P.anim) then return end
    pframe(1, "a", battle)
  end
end
local function rowsOf(P)
  local out = {}
  for k, r in ipairs(P.menu and P.menu.rows or {}) do out[k] = r.act end
  return table.concat(out, " ")
end
local function rowAt(P, act)
  for k, r in ipairs(P.menu and P.menu.rows or {}) do if r.act == act then return k end end
end
local function pickRow(P, act, battle)
  local k = rowAt(P, act)
  if not k then return false end
  while P.menu.sel ~= k do pframe(1, "down", battle) end
  pframe(1, "a", battle)
  return true
end

-- ------- the START menu's: ours, full screen
local closes = 0
local P = open({ session = s, onClose = function() closes = closes + 1 end })
T.check(P ~= nil and Tm.state().ctx.app == "menus" and Stack.has(Sh.MAP_ID), "START's party menu: ours, full screen")
T.check(PM.isOpen() == true and PM._party == s.party, "the game asks: it's open, with its party")
T.eq(P.n, 3, "three cards")
pframe(3)
T.check(not Tm.state().winFailed, "it draws")
pframe(1, "down")
T.eq(P.cur, 2, "Down: the next card")
T.eq(PM.cursor, 1, "(the game's cursor follows once it closes)")
pframe(1, "a")
T.check(P.view == "menu" and rowsOf(P):find("^SUMMARY") and rowAt(P, "SWITCH") and rowAt(P, "ITEM") and rowAt(P, "CANCEL"),
        "A: its menu (" .. rowsOf(P) .. ")")
pickRow(P, "SUMMARY")
T.check(P.view == "summary" and P.sum and P.sum.i == 2 and P.sum.party == true, "SUMMARY: the summary inside, on the second")
pframe(1, "down")
T.eq(P.sum.i, 3, "the summary's Down: the next Pokémon")
pframe(1, "b")
T.check(P.view == "pick" and P.cur == 3 and Tm.isOpen(), "B: back on the cards, on the one it ended on")
-- (switching places)
local first, third = s.party[1], s.party[3]
pframe(1, "a")
pickRow(P, "SWITCH")
T.check(P.view == "switch" and P.from == 3, "SWITCH: pick where to")
pframe(1, "up")
pframe(1, "up")
pframe(1, "a")
T.check(s.party[1] == third and s.party[3] == first and P.view == "pick", "the two traded places")
-- (an item held: TAKE puts it in the Bag, the game's words)
s.party[1].item, s.party[1].heldItem = ORAN, ORAN
P.cur = 1
pframe(1, "a")
T.check(rowAt(P, "ITEM") ~= nil, "ITEM on the menu")
pickRow(P, "ITEM")
T.check(P.menu and P.menu.kind == "ITEM" and rowAt(P, "GIVE") and rowAt(P, "TAKE"), "ITEM: give / take (" .. rowsOf(P) .. ")")
local bagBefore = Bag.count and Bag.count(s.bag, ORAN) or 0
pickRow(P, "TAKE")
T.check(P.prompt and P.prompt.kind == "msg" and (tonumber(s.party[1].item) or 0) == 0, "TAKE: taken, the game's words")
through()
T.check(P.view == "pick" and not P.prompt, "back on the cards")
T.check(not Bag.count or Bag.count(s.bag, ORAN) == bagBefore + 1, "the Berry in the Bag")
-- (a field move it knows: on its menu by the move's name; chosen, the game's checks answer. Ruby /
-- Sapphire's list is their menu pack's, which isn't there headless)
local cutter = RS and { moves = {} } or s.party[1]
if not RS then
  local keepMove = cutter.moves[4]
cutter.moves[4] = type(cutter.moves[1]) == "table" and { id = 15, pp = 30, ppUps = 0 } or 15
P.cur = 1
pframe(1, "a")
local cutRow = rowAt(P, "CUT")
T.check(cutRow ~= nil and P.menu.rows[cutRow].fm == true and P.menu.rows[cutRow].text ~= "CUT" or cutRow ~= nil,
        "a field move on its menu (" .. rowsOf(P) .. ")")
if cutRow then
  T.check(pcall(pickRow, P, "CUT"), "chosen: no error")
  through()
end
T.check(Tm.isOpen() and party().view == "pick", "nothing to cut here: back on the cards")
cutter.moves[4] = keepMove
end
-- (B on the item menu: back to the Pokémon's)
pframe(1, "a")
pickRow(P, "ITEM")
pframe(1, "b")
T.check(P.menu and P.menu.kind == "main", "B on ITEM's menu: the Pokémon's again")
pframe(1, "b")
T.check(P.view == "pick", "B: the cards")
local pkb = garbageOf(60)
T.check(pkb < 0.5, ("the party: next to no garbage (%.3f KB a frame)"):format(pkb))
K.setTextScale(1.3)
T.check(pcall(pframe, 20), "the party's text at 130%")
VP.width, VP.height = 320, 480
T.check(pcall(pframe, 10) and P.narrow == true, "a narrow screen: one column")
VP.width, VP.height = 480, 320
K.setTextScale(1)
pframe(1, "b")
T.check(not Tm.isOpen() and not PM.isOpen() and closes == 1, "B: closed, onClose once")

-- ------- the G-Max Factor (WoobleDex's, while Galar Rising is on): its mark under the picture, wide and narrow
do
  local env, gm = X._test.env, s.party[2]
  local galar0, dyn0, mark0 = env.bx.galar, env.bx.dynamax, env.gmaxMark
  env.bx.galar = function() return true end
  env.bx.dynamax = function() return { canGigantamax = function(mon) return mon == gm end } end
  local drew = 0
  env.gmaxMark = function(...) drew = drew + 1 return mark0(...) end
  local Pg = open({ session = s, onClose = function() end })
  T.check(Pg and not Pg.cards[1].gmax and Pg.cards[2].gmax == true, "the G-Max Factor: on its own card alone")
  pframe(2)
  T.check(drew > 0 and not Tm.state().winFailed, "its mark drawn under its icon")
  VP.width, VP.height = 320, 480
  drew = 0
  pframe(2)
  T.check(drew > 0 and Pg.narrow == true, "narrow: its mark drawn too")
  VP.width, VP.height = 480, 320
  pframe(1, "b")
  T.check(not Tm.isOpen(), "closed")
  env.bx.galar, env.bx.dynamax, env.gmaxMark = galar0, dyn0, mark0
  T.check(not env.party.card(gm).gmax, "without Galar Rising: no mark")
end

-- ------- a battle's switch: the battle hands it input; the game's validate; onClose, then onSelect
local order, why = {}, nil
local function battleOpts(mode)
  order = {}
  return { mode = mode or "battle_switch", session = s, battle = true, activeSlot = 1,
           validate = function(slot) order[#order + 1] = "validate:" .. tostring(slot) return why end,
           onSelect = function(slot, mon) order[#order + 1] = "select:" .. tostring(slot) end,
           onClose = function() order[#order + 1] = "close" end }
end
P = open(battleOpts())
T.check(P and P.c.battle and P.cards[1].active, "a battle's switch: ours; the one in battle marked")
pframe(1, "down", true)
pframe(1, "a", true)
T.eq(rowsOf(P), "SHIFT SUMMARY CANCEL", "its menu: shift, summary, cancel")
why = "It's already in battle!"
pickRow(P, "SHIFT", true)
T.check(P.prompt and P.prompt.pages[1]:find("already") and Tm.isOpen(), "the game's reason: said, still open")
through(5, true)
why = nil
pframe(1, "a", true)
pickRow(P, "SHIFT", true)
T.check(not Tm.isOpen() and table.concat(order, " ") == "validate:2 validate:2 close select:2",
        "SHIFT: closed, onClose, then onSelect(2) (" .. table.concat(order, " ") .. ")")
P = open(battleOpts())
pframe(1, "b", true)
T.check(not Tm.isOpen() and table.concat(order, " ") == "close", "B: closed, onClose only")
-- (the battle's order: the shown first is the real second)
local o = battleOpts()
o.battleOrder = { 2, 1, 3 }
P = open(o)
T.check(P.c.party[1] == s.party[2] and P.c.party[2] == s.party[1], "in the battle's order")
pframe(1, "down", true)
pframe(1, "a", true)
pickRow(P, "SHIFT", true)
T.check(table.concat(order, " ") == "validate:1 close select:1", "the real slot given back (" .. table.concat(order, " ") .. ")")
-- (a fainted one replaced: B can't leave)
P = open(battleOpts("battle_faint"))
pframe(1, "b", true)
T.check(Tm.isOpen() and #order == 0, "a send-out can't be cancelled")
pframe(1, "down", true)
pframe(1, "a", true)
T.eq(rowsOf(P), "SEND OUT SUMMARY CANCEL", "its menu: send out")
pickRow(P, "SEND OUT", true)
T.check(not Tm.isOpen() and order[#order] == "select:2", "SEND OUT: chosen")
-- (closed from outside: a battle's end)
P = open(battleOpts())
PM.close()
T.check(not Tm.isOpen() and table.concat(order, " ") == "close", "PartyMenu.close(): ours closes, onClose")
-- (a battle beside a partner -- Emerald's Steven, the Battle Tower's: the partner's after the player's own
-- (playerHalf); theirs named and not sent out by the player)
do
  local Battle = require("src.core.game3.battle")
  local was = Battle._st
  Battle._st = { double = true, playerHalf = 2, partner = { name = "STEVEN" } }
  local ob = battleOpts()
  ob.layout = "double"
  P = open(ob)
  T.check(P and P.c.battle and not P.cards[1].ally and not P.cards[2].ally and P.cards[3].ally == "Steven",
          "beside a partner: ours; the partner's card named (" .. tostring(P and P.cards[3].ally) .. ")")
  pframe(1, "down", true)
  pframe(1, "down", true)
  T.check(P.cur == 3, "on the partner's")
  pframe(1, "a", true)
  T.eq(rowsOf(P), "SUMMARY CANCEL", "the partner's menu: no SHIFT")
  pframe(1, "b", true)
  T.check(pcall(pframe, 10), "the partner's card drawn")
  pframe(1, "b", true)
  T.check(not Tm.isOpen() and table.concat(order, " ") == "close", "B: closed, onClose only")
  Battle._st = was
end

-- ------- an item used from the Bag: a Potion on a hurt one
Bag.add(s.bag, POTION, 1)
local hurt = s.party[2]
hurt.hp = 1
closes = 0
P = open({ session = s, bag = s.bag, item = POTION, mode = "use", onClose = function() closes = closes + 1 end })
T.check(P and P.base == "use" and P.title:find("Potion") or P.title:find("POTION"), "use: ours, the item named (" .. tostring(P and P.title) .. ")")
pframe(1, "down")
pframe(1, "a")
T.check(P.anim and hurt.hp > 1, "the Potion: HP up, its bar filling")
for _ = 1, 120 do if not P.anim then break end pframe(1) end
T.check(P.prompt and P.prompt.kind == "msg", "then the game's words")
through()
T.check(not Tm.isOpen() and closes == 1, "the last Potion: the menu closes")
-- (a TM: each card says whether it can learn it)
Bag.add(s.bag, TM28, 1)
P = open({ session = s, bag = s.bag, item = TM28, mode = "use" })
local tagged = 0
for i = 1, P.n do if P.cards[i].tag then tagged = tagged + 1 end end
T.eq(tagged, P.n, "a TM: every card says able / not able")
pframe(1, "b")
T.check(not Tm.isOpen(), "B: closed")
-- (a Rare Candy: a level, the stats, onwards)
Bag.add(s.bag, RARE_CANDY, 1)
local mon1 = s.party[1]
local lv = mon1.level
P = open({ session = s, bag = s.bag, item = RARE_CANDY, mode = "use" })
pframe(1, "a")
T.eq(mon1.level, lv + 1, "a Rare Candy: a level")
local sawStats = false
for _ = 1, 200 do
  local Pp = party()
  if not Pp then break end
  if Pp.prompt and Pp.prompt.kind == "stats" then sawStats = true end
  if Pp.view == "summary" then pframe(1, "b") else pframe(1, (Pp.prompt or Pp.anim) and "a" or nil) end
  if Pp.view == "pick" and not Pp.prompt and not Pp.anim then break end
end
T.check(sawStats, "the level's stats shown")
if Tm.isOpen() then pframe(1, "b") end
T.check(not Tm.isOpen(), "and away")

-- ------- an item given from the Bag
Bag.add(s.bag, ORAN, 1)
s.party[1].item, s.party[1].heldItem = 0, 0
closes = 0
P = open({ session = s, bag = s.bag, item = ORAN, mode = "give", onClose = function() closes = closes + 1 end })
pframe(1, "a")
T.check(P.prompt and (tonumber(s.party[1].item) or 0) == ORAN, "give: held, the game's words")
through()
T.check(not Tm.isOpen() and closes == 1, "and closed, onClose once")

-- ------- phase 4: choosing one (the Day Care, a trade): A closes with it -- onClose, then onSelect(slot)
order = {}
P = open({ session = s, mode = "choose", onSelect = function(slot) order[#order + 1] = "select:" .. tostring(slot) end,
           onClose = function() order[#order + 1] = "close" end })
T.check(P and P.base == "choose", "choosing one: ours")
pframe(1, "down")
pframe(1, "a")
T.check(not Tm.isOpen() and table.concat(order, " ") == "close select:2", "A: onClose, then onSelect(2) (" .. table.concat(order, " ") .. ")")
order = {}
P = open({ session = s, mode = "choose", onSelect = function() order[#order + 1] = "select" end,
           onClose = function() order[#order + 1] = "close" end })
pframe(1, "b")
T.check(not Tm.isOpen() and table.concat(order, " ") == "close", "B: onClose only")
-- (the caller's words over ours: PartyMenu.showMessage while it's up)
P = open({ session = s, mode = "choose", onSelect = noop })
local dismissed = false
PM.showMessage("Hello there.", function() dismissed = true end)
T.check(P.prompt and P.prompt.pages[1] == "Hello there.", "the caller's words in ours")
pframe(1, "a")
T.check(dismissed and Tm.isOpen(), "dismissed: its callback, still choosing")
pframe(1, "b")

-- ------- choosing a team (the Battle Tower / Frontier): ENTER two, Confirm; the order for the caller
order = {}
local readOrder
P = open({ session = s, mode = "choose_multi", count = 2,
           onSelect = function(list) order[#order + 1] = list and table.concat(list, ",") or "nil" end,
           onClose = function() readOrder = PM.chosenOrder and table.concat(PM.chosenOrder(), ",") end })
T.check(P and P.base == "choose_multi" and P.max == 2, "choosing a team: ours, two to choose")
pframe(1, "a")
T.eq(rowsOf(P), "ENTER SUMMARY CANCEL", "its menu: enter, summary, cancel")
pickRow(P, "ENTER")
T.check(P.order[1] == 1 and P.cards[1].orderN == 1, "the first in, its place on its card")
pframe(1, "down")
pframe(1, "down")
pframe(1, "a")
pickRow(P, "ENTER")
T.check(#P.order == 2 and P.confirmFocus, "the second in: Confirm next")
pframe(1, "up")
pframe(1, "up")
pframe(1, "a")
pickRow(P, "ENTER")
T.check(#P.order == 2 and P.prompt, "a third: the game's words (no more than two)")
through()
pframe(1, "start")
pframe(1, "a")
T.check(not Tm.isOpen() and order[1] == "1,3" and readOrder == "1,3",
        "Confirm: onSelect({1, 3}), PartyMenu.chosenOrder() in onClose (" .. tostring(order[1]) .. " / " .. tostring(readOrder) .. ")")
order = {}
P = open({ session = s, mode = "choose_multi", count = 3, onSelect = function(list) order[#order + 1] = tostring(list) end })
pframe(1, "b")
T.check(P.prompt and P.prompt.kind == "yesno", "B: cancel? (the game's words)")
pframe(1, "a")
T.check(not Tm.isOpen() and order[1] == "nil", "yes: onSelect(nil)")

-- ------- the Move Tutor: each card able / not; the result for the script
local tutorRes
P = open({ session = s, mode = "move_tutor", tutor = 0, onClose = function() tutorRes = PM._tutorResult end })
T.check(P and P.base == "move_tutor" and P.cards[1].tag ~= nil, "the Move Tutor: ours, each card able / not able")
pframe(1, "a")
through(40)
for _ = 1, 20 do
  local Pp = party()
  if not Pp then break end
  if Pp.view == "summary" then pframe(1, "b") else pframe(1, (Pp.prompt or Pp.anim) and "a" or "b") end
end
T.check(not Tm.isOpen() and type(tutorRes) == "boolean", "taught or not: closed, PartyMenu._tutorResult set (" .. tostring(tutorRes) .. ")")

-- ------- the game's own for its other callers
-- (the PC's mailbox giving mail: onChoose answers while ours stays open, through PartyMenu's own calls)
local gaveTo, mbClosed = nil, 0
P = open({ session = s, mode = "choose", promptMode = "give", eggFails = true, fadeIn = true,
           onChoose = function(_, mon)
             gaveTo = mon
             PM.showMessage("The MAIL was transferred.", function() PM.close() end)
           end,
           onClose = function() mbClosed = mbClosed + 1 end })
T.check(P and P.base == "choose", "the mailbox's give: ours")
pframe(1, "a")
T.check(gaveTo == s.party[1] and Tm.isOpen() and P.prompt and P.prompt.pages[1]:find("transferred"),
        "A: its onChoose, still open, its words in ours")
pframe(1, "a")
T.check(not Tm.isOpen() and mbClosed == 1, "the words dismissed: PartyMenu.close(), onClose")
T.check(Mn.openParty(s.party, nil, { session = s, mode = "use", item = POTION, battle = true, onSelect = noop }) == false,
        "an item from the game's bag in battle: not ours (until the Bag is)")
T.check(Mn.openParty(s.party, nil, { session = s, mode = "battle_switch", multi = { [2] = true } }) == false, "a multi battle's: not ours")
Mn.on = false
T.check(Mn.openParty(s.party, nil, { session = s }) == false, "the option off: not ours")
Mn.on = nil

-- =================== phase 3: the Bag
local BM = require("src.ui.game3.bag_menu")
local Screens = require("src.ui.game3.screens")
T.check(BM.__woobOs ~= nil and BM.__woobOs.impl ~= nil and Screens.__woobOs ~= nil, "the bag's takeover is made and wrapped")
local wrappedBag = BM.show
run.loader.events:emit("game.ready", {})
T.check(BM.show == wrappedBag, "the bag wrapped once")
local POKE_BALL = 4
local function count(id)
  local n = 0
  for _, p in ipairs({ "ITEMS", "POKE_BALLS", "KEY_ITEMS", "TM_CASE", "BERRY_POUCH", "BERRIES", "TM_HM" }) do
    local ok, rows = pcall(Bag.listPocket, s.bag, p)
    if ok and rows then for _, r in ipairs(rows) do if tonumber(I.toNumericId(r.id) or r.id) == id then n = n + r.qty end end end
  end
  return n
end
Bag.add(s.bag, POTION, 3)
Bag.add(s.bag, RARE_CANDY, 1)
Bag.add(s.bag, POKE_BALL, 5)
Bag.add(s.bag, ORAN, 2)
local function bag() return Tm.isOpen() and Tm.state().win.state.bag or nil end
local function page() return Tm.isOpen() and Tm.state().win.state.page or nil end
-- (a frame for the Bag: the field's layer, or a battle handing it input through Screens)
local function bframe(n, press, battle)
  for i = 1, n or 1 do
    clock = clock + 1 / 60
    local inp = i == 1 and press and input({ press }) or NONE
    if battle then Screens.handleInput("bag", BM, inp, s) else Sh.mapLayer.handleInput(inp) end
    Sh.frame(nil, VP)
  end
end
local function toRow(B, id)
  for _ = 1, 8 do
    local list = B.rows[B.pockets[B.pi]] or {}
    for k, r in ipairs(list) do
      if tonumber(I.toNumericId(r.id) or r.id) == id then
        while B.cur ~= k do bframe(1, B.cur < k and "down" or "up") end
        return true
      end
    end
    bframe(1, "right")
  end
  return false
end
local function menuPick(B, act)
  for k, r in ipairs(B.menu and B.menu.rows or {}) do
    if r.act == act then
      while B.menu.sel ~= k do bframe(1, "down") end
      bframe(1, "a")
      return true
    end
  end
  return false
end

-- ------- START's BAG: ours, its pockets as pages
closes = 0
BM.show(s.bag, { session = s, onClose = function() closes = closes + 1 end })
local B = bag()
T.check(B ~= nil and page() == "bag" and BM.isOpen() == true, "START's BAG: ours, full screen")
bframe(2)
T.check(not Tm.state().winFailed, "it draws")
T.check(#B.pockets >= 3, "its pockets (" .. table.concat(B.pockets, " ") .. ")")
local pi0 = B.pi
bframe(1, "right")
T.check(B.pi ~= pi0, "Right: the next pocket")
bframe(1, "left")
T.eq(B.pi, pi0, "Left: back")
-- (a Potion used: the party over the Bag, then back to it)
T.check(toRow(B, POTION), "the Potions found")
bframe(1, "a")
T.check(B.view == "menu" and B.menu.rows[1].act == "USE", "A: its menu, USE first")
local hurt2 = s.party[2]
hurt2.hp = 1
menuPick(B, "USE")
T.check(page() == "party" and party() and party().base == "use", "USE: the party over the Bag")
local Pu = party()
while Pu.cur ~= 2 do bframe(1, "down") end
bframe(1, "a")
for _ = 1, 120 do if not Pu.anim then break end bframe(1) end
T.check(hurt2.hp > 1 and Pu.prompt ~= nil, "the Potion: HP up, the game's words")
through()
T.check(page() == "party" and Pu.view == "pick", "more Potions: picking again")
bframe(1, "b")
T.check(page() == "bag" and Tm.isOpen(), "B: back on the Bag")
T.eq(count(POTION), 2, "one Potion used")
-- (TOSS: how many, sure?, gone)
toRow(B, POTION)
bframe(1, "a")
menuPick(B, "TOSS")
T.check(B.view == "qty" and B.qty.n == 1, "TOSS: how many")
bframe(1, "up")
T.eq(B.qty.n, 2, "Up: two")
bframe(1, "a")
T.check(B.prompt and B.prompt.kind == "yesno", "sure? (the game's words)")
bframe(1, "a")
T.check(B.prompt and B.prompt.kind == "msg", "thrown away (the game's words)")
bframe(1, "a")
T.eq(count(POTION), 0, "both Potions gone")
-- (GIVE: the party over the Bag, held)
s.party[1].item, s.party[1].heldItem = 0, 0
toRow(B, ORAN)
bframe(1, "a")
menuPick(B, "GIVE")
T.check(page() == "party" and party().base == "give", "GIVE: the party over the Bag")
bframe(1, "a")
T.check((tonumber(s.party[1].item) or 0) == ORAN, "held")
through()
T.check(page() == "bag", "back on the Bag")
-- (moving an item in its pocket: SELECT, down, A)
local okM = Bag.add(s.bag, POTION, 1)
toRow(B, POTION)
local pocketNow = B.pockets[B.pi]
local list0 = B.rows[pocketNow]
if #list0 > 1 and require("src.core.game3.items_data").BAG_MODEL then
  local first = list0[1].id
  while B.cur ~= 1 do bframe(1, "up") end
  bframe(1, "select")
  if B.view == "move" then
    bframe(1, "down")
    bframe(1, "a")
    T.check(B.rows[pocketNow][2].id == first, "SELECT: moved one down")
  end
end
local bkb = garbageOf(60)
T.check(bkb < 0.5, ("the Bag: next to no garbage (%.3f KB a frame)"):format(bkb))
-- (sorting a pocket: START, or the Sort button by Close; by name, by type)
for _, id in ipairs({ 85, 22, 14 }) do Bag.add(s.bag, id, 1) end   -- (an Escape Rope, a Super Potion, an Antidote)
B.rows = {}
T.check(toRow(B, 85), "the Items pocket")
local spk = B.pockets[B.pi]
T.check(B.rows[spk].sortable == true, "it sorts")
bframe(1, "start")
T.check(B.view == "menu" and B.menu.sort and B.menu.rows[1].act == "SORT_NAME" and B.menu.rows[2].act == "SORT_TYPE",
        "START: Sort by Name / by Type")
menuPick(B, "SORT_NAME")
local function inOrder(key)
  local rows, ok = B.rows[spk] or {}, true
  for k = 2, #rows do
    local a, b = rows[k - 1], rows[k]
    if key == "name" then ok = ok and tostring(a.name):lower() <= tostring(b.name):lower()
    else ok = ok and tonumber(I.toNumericId(a.id) or a.id) <= tonumber(I.toNumericId(b.id) or b.id) end
  end
  return ok and #rows >= 4
end
T.check(inOrder("name") and B.view == "list", "by name: A to Z")
T.check(B.cur == 1 and B.toast ~= nil, "the list from its top, and a word for it")
bframe(5)
Tm.state().win.tap(820)   -- (the Sort button's hit: src/apps/menus.lua A.SORT)
T.check(B.view == "menu" and B.menu.sort, "the Sort button: the same")
menuPick(B, "SORT_TYPE")
T.check(inOrder("type"), "by type: the game's own order")
bframe(1, "start")
menuPick(B, "CANCEL")
T.check(B.view == "list" and inOrder("type"), "Cancel: as it was")
bframe(130)
T.check(B.toast == nil, "the word gone after a moment")
-- (Reorder by touch: in an item's menu, as SELECT; Close while moving leaves it as it was; a row tapped
-- puts it there)
do
  while B.cur ~= 1 do bframe(1, "up") end
  local first = B.rows[spk][1].id
  bframe(1, "a")
  local acts = {}
  for k, r in ipairs(B.menu and B.menu.rows or {}) do acts[k] = r.act end
  T.check(acts[#acts - 1] == "MOVE" and acts[#acts] == "CANCEL", "an item's menu: Reorder, before Cancel (" .. table.concat(acts, " ") .. ")")
  menuPick(B, "MOVE")
  T.eq(B.view, "move", "Reorder: moving it")
  Tm.state().win.tap(741)
  T.check(B.view == "list" and B.rows[spk][1].id == first, "Close while moving: as it was")
  bframe(1, "a")
  menuPick(B, "MOVE")
  Tm.state().win.tap(1000 + 2)
  bframe(1)
  T.check(B.view == "list" and B.rows[spk][2].id == first, "a row tapped: put there")
end
-- (a game screen over a modern menu -- the evolution, the mail reader, Check Tag -- waits on A / B: the touch
-- pad out for it on a phone with no controller, and taps not for ours under it)
do
  local TC = require("src.core.TouchControls")
  local en0 = TC.enabled
  TC.enabled = true
  Sh.frame(nil, VP)
  T.check(TC.enabled == false, "our Bag (made for touch): the touch pad put away")
  local GAME = { isMenu = true, handleInput = function() end, update = function() end, draw = function() end }
  Stack.push("test_game_screen", GAME, { hideBelow = true })
  Sh.frame(nil, VP)
  T.check(TC.enabled ~= false, "a game screen over it: the touch pad out")
  T.eq(Sh.pointer({ phase = "pressed", x = 10, y = 10, id = 1 }), false, "its taps not for our Bag under it")
  Sh.pointer({ phase = "released", x = 10, y = 10, id = 1 })
  Stack.pop("test_game_screen")
  Sh.frame(nil, VP)
  T.check(TC.enabled == false and Tm.isOpen(), "gone: put away again, our Bag back")
  -- (a lesson drawn over ours -- Teachy TV's -- the same: its words wait on A)
  local LESSON = { isMenu = true, drawUnder = true, handleInput = function() end, update = function() end,
                   draw = function() end }
  Stack.push("test_lesson", LESSON, { hideBelow = false })
  Sh.frame(nil, VP)
  T.check(TC.enabled ~= false, "a lesson drawn over it: the touch pad out")
  Stack.pop("test_lesson")
  Sh.frame(nil, VP)
  T.check(TC.enabled == false, "and put away after")
  TC.enabled = en0
end
do
  local Bg = X._test.env.bagRules
  T.check(Bg.canSort({ session = s, bag = s.bag }, spk) and not Bg.canSort({ session = s, bag = s.bag, battle = true }, spk)
          and not Bg.canSort({ session = s, bag = s.bag, location = "party" }, spk)
          and not Bg.canSort({ session = s, bag = s.bag, pyramid = true }, "PYRAMID"),
          "not in a battle, choosing what to give, or the Pyramid's Bag")
  local m = I.BAG_MODEL
  if m and m.sortHmsFirst and m.sortHmsFirst.TM_CASE then
    T.check(not Bg.canSort({ session = s, bag = s.bag }, "TM_CASE"), "nor a pocket the game keeps in order (the TM Case)")
  end
end
K.setTextScale(1.3)
T.check(pcall(bframe, 20), "the Bag's text at 130%")
VP.width, VP.height = 320, 480
T.check(pcall(bframe, 10), "a narrow screen")
VP.width, VP.height = 480, 320
K.setTextScale(1)
bframe(1, "b")
T.check(not Tm.isOpen() and not BM.isOpen() and closes == 1, "B: closed, onClose once")

-- ------- a battle's Bag: a Ball thrown (onBattleUse, no onClose); B: onClose, then onBattleUse(nil)
local used = {}
local function battleBag()
  used = {}
  BM.show(s.bag, { session = s, battle = true,
                   onBattleUse = function(id, slot) used[#used + 1] = "use:" .. tostring(id) .. ":" .. tostring(slot) end,
                   onClose = function() used[#used + 1] = "close" end })
  if Tm.isOpen() then bframe(1, nil, true) end
  return bag()
end
B = battleBag()
T.check(B and B.c.battle, "a battle's BAG: ours")
local gotBall = false
for _ = 1, 6 do
  local list = B.rows[B.pockets[B.pi]] or {}
  for k, r in ipairs(list) do
    if tonumber(I.toNumericId(r.id) or r.id) == POKE_BALL then
      while B.cur ~= k do bframe(1, B.cur < k and "down" or "up", true) end
      gotBall = true
    end
  end
  if gotBall then break end
  bframe(1, "right", true)
end
T.check(gotBall, "the Poké Balls")
bframe(1, "a", true)
T.check(B.menu and B.menu.rows[1].act == "USE", "A: USE")
bframe(1, "a", true)
T.check(not Tm.isOpen() and table.concat(used, " ") == "use:4:nil", "USE: the battle told, no onClose (" .. table.concat(used, " ") .. ")")
T.check(BM._battle == false, "USE: BagMenu._battle cleared, as the game's close (the Berry Pouch reads it)")
B = battleBag()
bframe(1, "b", true)
T.check(not Tm.isOpen() and table.concat(used, " ") == "close use:nil:nil", "B: onClose, then onBattleUse(nil) (" .. table.concat(used, " ") .. ")")
T.check(BM._battle == false, "B: BagMenu._battle cleared")
B = battleBag()
BM.close()
T.check(not Tm.isOpen() and used[1] == "close", "BagMenu.close(): ours closes as B")

-- ------- a Ball's catch chance in a wild battle: the game's odds through its four shake checks
do
  local Bt, Pk, Rt = require("src.core.game3.battle"), require("src.core.game3.pokemon"), require("src.mods.Runtime")
  local Cg = require("src.core.game3.battle.catching")
  local Bg = X._test.env.bagRules
  local st0 = Bt._st
  local function foe(nat, hp, maxHp, status)
    local sp = Pk.speciesFromNational(nat)
    return { species = sp, status = status, mon = { species = sp, level = 10, hp = hp, maxHp = maxHp } }
  end
  -- (the shake check as the cart runs it: b = 1048560 / sqrt(sqrt(16711680 / a)), four rolls of 0..65535 under it)
  local function want(a)
    if a >= 255 then return 100 end
    local b = math.floor(1048560 / math.sqrt(math.sqrt(16711680 / a)))
    return (b / 65536) ^ 4 * 100
  end
  local c = { battle = true, session = s }
  Bt._st = { wild = true, enemy = foe(16, 30, 30) }
  local pa = Cg.catchOdds(POKE_BALL, Bt._st.enemy, Bt._st, s)
  local p1 = Bg.catchChance(c, POKE_BALL)
  T.check(p1 and math.abs(p1 - want(pa)) < 1e-9, ("a Pidgey at full HP, a Poké Ball: %.1f%%"):format(p1 or -1))
  local ultra = Bg.catchChance(c, 2)
  T.check(ultra and ultra > p1, "an Ultra Ball better")
  T.eq(Bg.catchChance(c, 1), 100, "the Master Ball: 100%")
  Bt._st.enemy = foe(143, 1, 300, "SLP")
  local low = Bg.catchChance(c, POKE_BALL)
  local la = Cg.catchOdds(POKE_BALL, Bt._st.enemy, Bt._st, s)
  T.check(low and math.abs(low - want(la)) < 1e-9 and low < p1, ("a sleeping Snorlax at 1 HP: %.1f%%"):format(low or -1))
  -- (by roll: the shake checks run as the cart does, with dice)
  local caught, n = 0, 20000
  local b = math.floor(1048560 / math.sqrt(math.sqrt(16711680 / pa)))
  for _ = 1, n do
    local ok = true
    for _ = 1, 4 do if math.random(0, 65535) >= b then ok = false break end end
    if ok then caught = caught + 1 end
  end
  T.check(math.abs(caught / n * 100 - p1) < 1.5, ("and by %d rolls: %.1f%% against %.1f%%"):format(n, caught / n * 100, p1))
  Bt._st = { wild = false, enemy = foe(16, 30, 30) }
  T.eq(Bg.catchChance(c, POKE_BALL), nil, "a trainer's Pokémon: none")
  Bt._st = { wild = true, oldManTutorial = true, enemy = foe(16, 30, 30) }
  T.eq(Bg.catchChance(c, POKE_BALL), nil, "the Old Man's lesson: none")
  Bt._st = { wild = true, enemy = foe(16, 30, 30) }
  T.eq(Bg.catchChance(c, 13), nil, "not a Ball: none")
  local wants0 = Rt.wantsHook
  Rt.wantsHook = function(name) return name == "catch.rate" end
  T.eq(Bg.catchChance(c, POKE_BALL), nil, "another mod deciding the catch: none")
  Rt.wantsHook = wants0
  T.eq(Bg.chanceText(0.4), "<1%", "under 1%")
  T.eq(Bg.chanceText(37.4), "37%", "a whole percent")
  -- (on the Bag's rows: worked out when the pocket's shown)
  B = battleBag()
  local got = nil
  for _ = 1, 6 do
    for _, r in ipairs(B.rows[B.pockets[B.pi]] or {}) do
      if tonumber(I.toNumericId(r.id) or r.id) == POKE_BALL then got = r end
    end
    if got then break end
    bframe(1, "right", true)
  end
  T.check(got and got.chanceText == Bg.chanceText(p1), "the Ball's row says it (" .. tostring(got and got.chanceText) .. ")")
  T.check(pcall(bframe, 5, nil, true), "and draws")
  bframe(1, "b", true)

  -- ------- the option gearMenus: a battle's Bag on the Kanto Gear's screen, the battle left on the game's
  local Gp = X._test.gearPanel
  local bridge0 = Gp.bridge
  local DISPLAY = { available = function() return true end, pollTouch = function() return nil end,
                    push = function() end }
  Gp.bridge = function() return DISPLAY end
  Mn.gear = true
  local function gframe(n, press)
    for i = 1, n or 1 do
      clock = clock + 1 / 60
      Screens.handleInput("bag", BM, i == 1 and press and input({ press }) or NONE, s)
      Gp.viewport(function(c2) return { x = 0, y = 0, width = c2.width, height = c2.height } end, VP)
      Gp.frame()
      Sh.frame(nil, VP)
    end
  end
  local function gbag()
    local st = Gp.isBattle() and Gp.hostState()
    return st and st.win.state.bag or nil
  end
  used = {}
  BM.show(s.bag, { session = s, battle = true,
                   onBattleUse = function(id, slot) used[#used + 1] = "use:" .. tostring(id) .. ":" .. tostring(slot) end,
                   onClose = function() used[#used + 1] = "close" end })
  T.check(Gp.isBattle() and not Tm.isOpen() and not Stack.has(Sh.MAP_ID), "on the Gear's screen: no layer, the battle seen")
  T.check(Sh.gearOpen("battle") and not Sh.gearOpen("slots"), "the Gear stands down for it (woob_battle shown)")
  B = gbag()
  T.check(B and B.c.battle, "the battle's Bag there")
  gframe(2)
  T.check(B.compact == true and Gp.mode() == "external", "laid out for the Gear's screen, on the second display")
  local gotG = false
  for _ = 1, 6 do
    for k, r in ipairs(B.rows[B.pockets[B.pi]] or {}) do
      if tonumber(I.toNumericId(r.id) or r.id) == POKE_BALL then
        while B.cur ~= k do gframe(1, B.cur < k and "down" or "up") end
        gotG = true
      end
    end
    if gotG then break end
    gframe(1, "right")
  end
  T.check(gotG, "the battle's buttons reach it: the Poké Balls")
  gframe(1, "a")
  T.check(B.menu and B.menu.rows[1].act == "USE", "A: USE")
  gframe(1, "a")
  T.check(not Gp.isOpen() and table.concat(used, " ") == "use:4:nil", "USE: the battle told, as ever (" .. table.concat(used, " ") .. ")")
  T.check(not Sh.gearOpen("battle"), "closed: the Gear back")
  used = {}
  BM.show(s.bag, { session = s, battle = true,
                   onBattleUse = function(id, slot) used[#used + 1] = "use:" .. tostring(id) .. ":" .. tostring(slot) end,
                   onClose = function() used[#used + 1] = "close" end })
  gframe(2)
  -- (its draw: the Gear's host alone, as the Bag's own check measures the game's)

  local gkb = math.huge
  for _ = 1, 2 do
    collectgarbage("collect")
    collectgarbage("stop")
    local k0 = collectgarbage("count")
    for _ = 1, 60 do
      clock = clock + 1 / 60
      Gp.frame()
    end
    gkb = math.min(gkb, (collectgarbage("count") - k0) / 60)
    collectgarbage("restart")
  end
  T.check(gkb < 0.5, ("the Gear's Bag: next to no garbage (%.3f KB a frame)"):format(gkb))
  K.setTextScale(1.3)
  T.check(pcall(gframe, 10), "the Gear's Bag at 130% text")
  K.setTextScale(1)
  gframe(1, "b")
  T.check(not Gp.isOpen() and table.concat(used, " ") == "close use:nil:nil", "B: as ever (" .. table.concat(used, " ") .. ")")
  BM.show(s.bag, { session = s, battle = true, onBattleUse = function() end, onClose = function() end })
  BM.close()
  T.check(not Gp.isOpen() and not BM.isOpen(), "BagMenu.close() (the battle's end): closed there too")
  -- (no screen of the Gear's own: the game's screen, as ever)
  Gp.bridge = function() return nil end
  BM.show(s.bag, { session = s, battle = true, onBattleUse = function() end, onClose = function() end })
  T.check(Tm.isOpen() and not Gp.isOpen(), "the Gear with no screen of its own: full screen as ever")
  BM.close()
  -- (the field's Bag never goes there)
  Gp.bridge = function() return DISPLAY end
  BM.show(s.bag, { session = s, onClose = function() end })
  T.check(Tm.isOpen() and not Gp.isOpen(), "the field's Bag: on the game's screen")
  BM.close()
  if Tm.isOpen() then bframe(1, "b") end
  -- (the party in a battle: there too)
  local PM = require("src.ui.game3.party_menu")
  PM.show(s.party, nil, { session = s, mode = "battle_switch", battle = true, validate = function() return true end,
                          onSelect = function() end, onClose = function() end })
  T.check(Gp.isBattle(), "a battle's party menu: on the Gear's screen")
  T.check(pcall(gframe, 5), "and draws")
  PM.close()
  T.check(not Gp.isOpen(), "closed with the battle")
  Mn.gear = nil
  Gp.bridge = bridge0
  Bt._st = st0
end

-- ------- the party's GIVE: our Bag over the party, the item given at once
s.party[2].item, s.party[2].heldItem = 0, 0
Bag.add(s.bag, ORAN, 1)
P = open({ session = s })
pframe(1, "down")
pframe(1, "a")
pickRow(P, "ITEM")
pickRow(P, "GIVE")
T.check(page() == "bag" and bag().c.location == "party", "the party's GIVE: our Bag over it")
B = bag()
toRow(B, ORAN)
bframe(1, "a")
T.check(page() == "party" and (tonumber(s.party[2].item) or 0) == ORAN, "A: given at once, back on the party")
through()
pframe(1, "b")
T.check(not Tm.isOpen(), "and away")

-- ------- phase 5: a berry tree's Berry (the Berries only; A chooses, B none: onClose, then onChoose)
Bag.add(s.bag, ORAN, 2)
local chose = {}
BM.show(s.bag, { session = s, location = "berry_tree", pocket = "BERRIES",
                 onChoose = function(id) chose[#chose + 1] = "choose:" .. tostring(id) end,
                 onClose = function() chose[#chose + 1] = "close" end })
B = bag()
T.check(B and #B.pockets == 1 and (B.pockets[1] == "BERRY_POUCH" or B.pockets[1] == "BERRIES"), "a berry tree: ours, the Berries only")
bframe(1)
toRow(B, ORAN)
bframe(1, "a")
T.check(not Tm.isOpen() and table.concat(chose, " ") == "close choose:" .. ORAN, "A: onClose, then onChoose(Oran) (" .. table.concat(chose, " ") .. ")")
chose = {}
BM.show(s.bag, { session = s, location = "berry_tree", pocket = "BERRIES", onChoose = function(id) chose[#chose + 1] = tostring(id) end })
bframe(1)
bframe(1, "b")
T.check(not Tm.isOpen() and chose[1] == "0", "B: onChoose(0)")
-- (the Berry Blender: B can't leave; CONFIRM)
chose = {}
BM.show(s.bag, { session = s, location = "blender", pocket = "BERRIES", onChoose = function(id) chose[#chose + 1] = tostring(id) end })
B = bag()
bframe(1)
bframe(1, "b")
T.check(Tm.isOpen(), "the Berry Blender: B can't leave")
toRow(B, ORAN)
bframe(1, "a")
T.check(B.menu and rowAt({ menu = B.menu }, "CONFIRM") ~= nil, "its menu: confirm, check tag, cancel")
menuPick(B, "CONFIRM")
T.check(not Tm.isOpen() and chose[1] == tostring(ORAN), "CONFIRM: that Berry")
-- (the item PC's deposit: how many, the game's words, into the PC)
local St = require("src.core.game3.storage")
Bag.add(s.bag, POTION, 3)
local bagBefore2 = count(POTION)
local pcBefore = 0
for _, e in ipairs(St.ensure(s).items) do if tonumber(I.toNumericId(e.id) or e.id) == POTION then pcBefore = pcBefore + e.qty end end
closes = 0
BM.show(s.bag, { session = s, location = "itempc", onClose = function() closes = closes + 1 end })
B = bag()
bframe(1)
toRow(B, POTION)
bframe(1, "a")
T.check(B.view == "qty" and B.qty.kind == "deposit", "deposit: how many")
bframe(1, "up")
bframe(1, "a")
T.check(B.prompt and B.prompt.kind == "msg", "deposited: the game's words")
bframe(1, "a")
local pcAfter = 0
for _, e in ipairs(St.ensure(s).items) do if tonumber(I.toNumericId(e.id) or e.id) == POTION then pcAfter = pcAfter + e.qty end end
T.check(pcAfter == pcBefore + 2 and count(POTION) == bagBefore2 - 2, "two in the PC, two fewer in the Bag (" .. pcAfter .. ", " .. count(POTION) .. ")")
bframe(1, "b")
T.check(not Tm.isOpen() and closes == 1, "B: onClose")
-- (a shop's selling: what it's worth, sure?, the money)
local money0, potions = s.money, count(POTION)
BM.show(s.bag, { session = s, location = "shop", onClose = noop })
B = bag()
bframe(1)
toRow(B, POTION)
bframe(1, "a")
if B.view == "qty" then
  T.check(B.qty.kind == "sell", "selling: how many")
  bframe(1, "a")
end
T.check(B.prompt and B.prompt.kind == "yesno", "selling a Potion: the price asked")
bframe(1, "a")
T.check(s.money == money0 + 150 and count(POTION) == potions - 1, "sold: 150 (" .. tostring(s.money - money0) .. ")")
for _ = 1, 4 do if bag() and bag().prompt then bframe(1, "a") end end
bframe(1, "b")
T.check(not Tm.isOpen(), "and away")

-- ------- the Battle Pyramid's bag (Emerald): its own list in ours; USE on a Pokémon, TOSS, SELECT
if GAME == "emerald" then
  local Py = require("src.core.game3.rse.frontier.pyramid")
  local PB = require("src.ui.game3.rse.pyramid_bag")
  local okP = pcall(function()
    local items, qty = Py.bagLists(s)
    for k = 1, #items do items[k], qty[k] = 0, 0 end
  end)
  if okP and pcall(Py.bagAdd, s, POTION, 2) and pcall(Py.bagAdd, s, 34, 1) then
    local pyClosed = 0
    PB.show({ session = s, location = "field", onClose = function() pyClosed = pyClosed + 1 end })
    B = bag()
    bframe(1)
    T.check(B and B.c.pyramid and #B.pockets == 1 and #(B.rows.PYRAMID or {}) == 2, "the Pyramid's bag: ours, its own two")
    s.party[2].hp = 1
    bframe(1, "a")
    menuPick(B, "USE")
    T.check(page() == "party" and party().base == "use", "a Potion: the party over it (lent)")
    local Pu = party()
    while Pu.cur ~= 2 do bframe(1, "down") end
    bframe(1, "a")
    for _ = 1, 120 do if not Pu.anim then break end bframe(1) end
    through()
    if page() == "party" then bframe(1, "b") end
    T.check(page() == "bag" and Py.bagCount(s, POTION) == 1, "used: one Potion fewer in the Pyramid's bag (" .. Py.bagCount(s, POTION) .. ")")
    bframe(1, "down")
    bframe(1, "a")
    menuPick(B, "TOSS")
    bframe(1, "a")
    bframe(1, "a")
    T.check(Py.bagCount(s, 34) == 0, "tossed from the Pyramid's bag")
    for _ = 1, 3 do if bag() and bag().prompt then bframe(1, "a") end end
    bframe(1, "b")
    T.check(not Tm.isOpen() and pyClosed == 1 and not PB.isOpen(), "B: closed, onClose")
    -- (in a battle: a Potion is the battle's to use: onUse, then onClose)
    local got = {}
    PB.show({ session = s, location = "battle", onUse = function(id) got[#got + 1] = "use:" .. tostring(id) end,
              onClose = function() got[#got + 1] = "close" end })
    bframe(1)
    bframe(1, "b")
    T.check(not Tm.isOpen() and table.concat(got, " ") == "close", "a battle's Pyramid bag: B, onClose")
  else
    T.check(true, "(no Pyramid state headless)")
  end
end

-- ------- the Pokédude (Teachy TV's battles, the Old Man's lesson): the game's plans played on ours
do
  local got
  Bag.add(s.bag, POKE_BALL, 1)
  BM.showPokedude(s.bag, { session = s, plan = "oldman", onItem = function(id) got = "item:" .. tostring(id) end,
                           onCancel = function() got = "cancel" end })
  T.check(bag() and bag().pd and BM.isPokedude(), "the Old Man's Bag: ours, playing its plan")
  bframe(1, "b", true)
  T.check(Tm.isOpen(), "B can't stop the Old Man's")
  do
    local skip = false
    for _, h in ipairs(X._test.kit.hits) do if h.kind == "win" and h.arg == 741 then skip = true end end
    T.check(not skip, "nor a tap: no Skip on it")
    Tm.state().win.tap(1001)
    T.check(Tm.isOpen() and bag().view == "list", "a tap on a row mid-lesson: nothing")
  end
  for _ = 1, 500 do if not Tm.isOpen() then break end bframe(1, nil, true) end
  T.check(not Tm.isOpen() and got == "item:" .. POKE_BALL, "its plan done: the Poké Ball (" .. tostring(got) .. ")")
  got = nil
  BM.showPokedude(s.bag, { session = s, plan = "catching", onItem = function(id) got = "item" end,
                           onCancel = function() got = "cancel" end })
  bframe(1, nil, true)
  bframe(1, "b", true)
  T.check(not Tm.isOpen() and got == "cancel", "Teachy TV's catching lesson: B stops it, onCancel")
  got = nil
  BM.showPokedude(s.bag, { session = s, plan = "catching", onItem = function(id) got = "item" end,
                           onCancel = function() got = "cancel" end })
  bframe(1, nil, true)
  Tm.state().win.tap(741)
  bframe(1, nil, true)
  T.check(not Tm.isOpen() and got == "cancel", "by touch: its Skip (the Close button), as B")
  -- (the party: a switch, then an item on one)
  local sel
  PM.showPokedude(s.party, { plan = "switch", session = s, activeSlot = 1, validate = function() return nil end,
                             onSelect = function(slot) sel = slot end, onCancel = function() sel = "cancel" end })
  T.check(party() and party().pd and PM.isPokedude(), "the Pokédude's switch: ours")
  Tm.state().win.tap(1000 + 2)
  T.check(Tm.isOpen() and party().pd and sel == nil, "a tap on a Pokémon mid-lesson: nothing")
  for _ = 1, 400 do if not Tm.isOpen() then break end pframe(1, nil, true) end
  T.check(not Tm.isOpen() and sel == 2, "its plan: the second sent in (" .. tostring(sel) .. ")")
  sel = nil
  local usedOn
  PM.showPokedude(s.party, { plan = "item", session = s, bag = s.bag, item = 13, activeSlot = 1,
                             onUse = function(slot) usedOn = slot return "It was cured of its poisoning." end,
                             onSelect = function(slot) sel = slot end, onCancel = function() sel = "cancel" end })
  for _ = 1, 120 do if party() and party().prompt then break end pframe(1, nil, true) end
  T.check(usedOn == 1 and party() and party().prompt, "the item on the one chosen: the game's words")
  pframe(1, "a", true)
  T.check(not Tm.isOpen() and sel == 1, "then its onSelect (" .. tostring(sel) .. ")")
  sel = nil
  PM.showPokedude(s.party, { plan = "switch", session = s, activeSlot = 1, validate = function() return nil end,
                             onSelect = function(slot) sel = slot end, onCancel = function() sel = "cancel" end })
  pframe(1, nil, true)
  Tm.state().win.tap(741)
  pframe(1, nil, true)
  T.check(not Tm.isOpen() and sel ~= 2, "by touch: the party lesson's Skip stops it (" .. tostring(sel) .. ")")
end

-- ------- Teachy TV's lessons (FireRed / LeafGreen): its Bag lesson and its TM Case lesson on ours
if GAME == "firered" or GAME == "leafgreen" then
  local Tv = require("src.ui.game3.teachy_tv")
  local TC = require("src.ui.game3.tm_case")
  local open0, susp0 = Tv.open, Tv.suspended
  Tv.open, Tv.suspended = true, true
  Bag.add(s.bag, TM28, 1)
  local tmClosed = false
  TC.show(s, s.bag, { cursor = 1, scroll = 0, onClose = function() tmClosed = true end })
  B = bag()
  T.check(B and B.m.tmDemo and #B.pockets == 1 and B.pockets[1] == "TM_CASE", "the TM Case lesson: ours, the TM page only")
  TC.mode, TC.messageText = "message", "TMs are numbered."
  bframe(1)
  T.check(B and B.prompt and B.prompt.mirror == "TMs are numbered.", "its words shown in ours")
  TC.mode, TC.messageText = "list", nil
  bframe(1)
  T.check(B and not B.prompt, "and gone with them")
  TC.close()
  T.check(not Tm.isOpen() and tmClosed, "its close: ours closes, its onClose")
  -- (the Register lesson's Bag: ours; it sets the cursor and presses keys)
  local regClosed = false
  BM.show(s.bag, { session = s, pocket = "ITEMS", onClose = function() regClosed = true end })
  B = bag()
  T.check(B and B.m.demo, "a lesson's Bag: ours")
  local rows = BM.list()
  T.check(type(rows) == "table" and rows == B.rows[B.pockets[B.pi]], "BagMenu.list(): ours")
  bframe(1)
  BM.cursor = 2
  BM.handleInput(input({ "a" }))
  bframe(1)
  T.check(B.cur == 2 and B.view == "menu", "the lesson's cursor and its press: in ours")
  BM.close()
  T.check(not Tm.isOpen() and regClosed, "its close: ours closes, its onClose")
  Tv.open, Tv.suspended = open0, susp0
end

-- ------- the game's own for its other callers
T.check(Mn.openBag(s.bag, { session = s, location = "party" }) == false, "the game's party's GIVE: not ours")
T.check(Mn.openBag(s.bag, { session = s, onChoose = noop }) == false, "choosing without a place: not ours")
T.check(Mn.openBag(s.bag, { session = s, battle = true }) == false, "the Pokédude's (no onBattleUse): not ours")
Mn.on = false
T.check(Mn.openBag(s.bag, { session = s }) == false, "the option off: not ours")
Mn.on = nil

-- ------- the update's notice: free in the field a moment -> the question; the answer is the mod option (as
-- the mod list sets it) and the notice seen; the note; never again
do
  local Settings, No = X._test.settings, X._test.env.notice
  local cache0, free0 = Settings.cache, Sh.free
  Settings.cache = { read = function() return nil end, write = function() end }
  -- (from nothing seen, whatever the real settings file says: the player may have answered it already)
  local seen0 = Settings.get("noticesSeen", "")
  Settings.set("noticesSeen", "")
  local MS = require("src.mods.ManagerState")
  local new0, set = MS.new, {}
  MS.new = function() return { setOption = function(_, id, k, v) set[#set + 1] = id .. ":" .. k .. ":" .. tostring(v) end } end
  local t, game = 100, {}
  No.now = function() return t end
  Sh.free = function() return true end
  T.check(No and No.pending() and No.pending().id == "modernMenus-1", "the Modern Menus notice not yet seen")
  No.step(game)
  T.check(not Tm.isOpen(), "not the moment the field's free")
  t = t + 2
  No.step(game)
  T.check(Tm.isOpen() and Tm.state().ctx.app == "notice", "free a moment: the notice opens")
  local Wn = Tm.state().win.state
  pframe(5)
  T.check(Wn.page == "ask" and Wn.focus == 2, "the question, Yes chosen")
  pframe(1, "left")
  T.check(Wn.focus == 1, "Left: No")
  pframe(1, "a")
  T.check(Wn.page == "after" and set[1] == "woob_os:modernMenus:false", "No: the option off (" .. tostring(set[1]) .. ")")
  T.check(No.seen("modernMenus-1") and No.pending() == nil, "seen the moment it's answered")
  K.setTextScale(1.3)
  T.check(pcall(pframe, 10), "the note at 130%")
  K.setTextScale(1)
  pframe(1, "a")
  T.check(not Tm.isOpen(), "OK: closed")
  t = t + 5
  No.step(game)
  T.check(not Tm.isOpen(), "never again")
  Settings.set("noticesSeen", seen0)
  Sh.free, Settings.cache, MS.new = free0, cache0, new0
end

-- ------- the OPTIONS menu's WOOBOS row (the ui.options.rows hook): after the others', its options counted
do
  local Runtime = require("src.mods.Runtime")
  local okR, rows = pcall(Runtime.call, "ui.options.rows", function(_, r) return r end, {},
    { { id = "mods", label = "MODS" } })
  local row
  for _, r in ipairs(okR and rows or {}) do if r.id == "woob_os" then row = r end end
  T.check(okR and rows[1].id == "mods" and row ~= nil and row.label == "WOOBOS", "OPTIONS: a WOOBOS row after the rest")
  local fake = { mods = { optionSchemas = { woob_os = { { key = "a" }, { key = "b" }, { key = "c" } } } } }
  T.check(row and tostring(row.value({})):match("^%d+ OPTIONS$") ~= nil,
          "before the mod manager has loaded the list: counted from options.lua (" .. tostring(row and row.value({})) .. ")")
  T.eq(row and row.value(fake), "3 OPTIONS", "its value: how many options")
end

T.finish("woob_os menus (" .. GAME .. ")")
