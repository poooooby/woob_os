-- Standalone: luajit mods/woob_os/tests/optscreen_test.lua [game] (from the gen1recomp root; needs that cart
-- imported, Emerald by default).
--
-- The OPTIONS screen, modern (src/options_screen.lua, src/apps/options.lua): the game's OPTIONS ours, its rows in a
-- sentence's case, its pages, a value changed and kept, another mod's row tagged, WoobOS's page in it with its
-- options as a tree (folding away and back as Modern Menus goes off and on), the mod manager's way in on the
-- scene host, the switch off: the game's own. Next to no garbage; the text at 130%.
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
local Os = X._test.optionsScreen
local Tm, Ts = X._test.townmap, X._test.sceneHost
local family = (GAME == "firered" or GAME == "leafgreen") and "frlg" or ((GAME == "ruby" or GAME == "sapphire") and "rs" or "rse")
local Screens = require("src.ui.game3.screens")
local FrMenu = require("src.ui.game3.option_menu")
local RseMenu = require("src.ui.game3.rse.option_menu")
local RsMenu = require("src.ui.game3.rs.option_menu")
local MS = require("src.mods.ManagerState")
T.check(Os ~= nil and FrMenu.__woobOsOptions and RseMenu.__woobOsOptions and RsMenu.__woobOsOptions and MS.__woobOsOptions,
        "the OPTIONS screens and the mod manager's options page wrapped")
local wrapped = FrMenu.show
run.loader.events:emit("game.ready", {})
T.check(FrMenu.show == wrapped, "wrapped once, whatever the game.ready count")

local function input(press)
  local p = {}
  for _, k in ipairs(press or {}) do p[k] = true end
  return { wasPressed = function(_, k) return p[k] == true end, isDown = function(_, k) return p[k] == true end }
end
local VP = { width = 480, height = 320 }
local NONE = input()
local function frame(n, press)
  for i = 1, n or 1 do
    clock = clock + 1 / 60
    local inp = i == 1 and press and input({ press }) or NONE
    local top = Stack.top and Stack.top()
    if top and top.id == Sh.SCENE_ID then Sh.sceneLayer.handleInput(inp)
    elseif top and top.id == Sh.MAP_ID then Sh.mapLayer.handleInput(inp) end
    Sh.frame(nil, VP)
  end
end
local function garbageOf(host, n)
  local best = math.huge
  for _ = 1, 2 do
    collectgarbage("collect")
    collectgarbage("stop")
    local kb = collectgarbage("count")
    for _ = 1, n do
      clock = clock + 1 / 60
      host.draw(G, VP)
    end
    best = math.min(best, (collectgarbage("count") - kb) / n)
    collectgarbage("restart")
  end
  return best
end

-- ------- a session, and a game the options are kept on
local Bag, Storage = require("src.core.game3.bag"), require("src.core.game3.storage")
local ItemsData = require("src.core.game3.items_data")
local s = { name = "WOS", playerName = "WOS", bag = Bag.new(), storage = Storage.new(), party = {}, money = 3000,
            flags = {}, vars = {}, gender = 0, gameStats = {} }
ItemsData.ensureModel(s)
require("src.core.game3.runtime").getSession = function() return s end
local writes = 0
local game = { mods = run.loader, save = { options = {} }, options = {}, modStatus = nil,
               writeOptions = function() writes = writes + 1 end }
run.loader.modOptions = run.loader.modOptions or {}
local function win() return Tm.isOpen() and Tm.state().win or nil end
local function st() local w = win() return w and w.state or nil end
local function pg() local x = st() return x and x.pages[#x.pages] or nil end
local function rowAt(p, id) for i, r in ipairs(p.rows) do if r.id == id then return i, r end end end
local function moveTo(p, i) while p.cur ~= i do frame(1, p.cur < i and "down" or "up") end end

-- ------- the game's OPTIONS: ours
local closed = 0
Screens.get("option", s).show({ session = s, game = game, onClose = function() closed = closed + 1 end })
T.check(Tm.isOpen() and Tm.state().ctx.app == "options" and Stack.has(Sh.MAP_ID) and Os.isOpen(),
        "OPTIONS: ours, full screen")
frame(3)
local P0 = pg()
T.check(P0 and #P0.rows > 5, "the top page: the game's rows (" .. tostring(P0 and #P0.rows) .. ")")
local _, ts = rowAt(P0, "buttonMode")
T.check(ts ~= nil and ts.label:find("%l") ~= nil and ts.valueText ~= nil, "Button mode: in a sentence's case, its value ("
  .. tostring(ts and ts.label) .. ": " .. tostring(ts and ts.valueText) .. ")")
local groups = 0
for _, r in ipairs(P0.rows) do if r.kind == "group" then groups = groups + 1 end end
T.check(groups >= 3, "the game's pages (speed, video, audio...): " .. groups)
local _, wr = rowAt(P0, "woob_os")
T.check(wr and wr.modName == "Mod" and wr.label == "WoobOS", "WoobOS's row at the top: its name, tagged a mod (" .. tostring(wr and wr.label) .. ", " .. tostring(wr and wr.modName) .. ")")
local mods = 0
for _, r in ipairs(P0.rows) do if r.modName then mods = mods + 1 end end
T.check(mods == 1, "only the mod's rows tagged (" .. mods .. ")")
frame(2)
local wi0 = rowAt(P0, "woob_os")
T.check(P0.firstMod == wi0, "the divider above the first row a mod added (row " .. tostring(P0.firstMod) .. ")")
-- (a value: Right changes it, and the game keeps it)
local ti = rowAt(P0, "buttonMode")
moveTo(P0, ti)
local before, w0 = ts.valueText, writes
frame(1, "right")
frame(2)
T.check(ts.valueText ~= before, "Right: Button mode changes (" .. tostring(before) .. " -> " .. tostring(ts.valueText) .. ")")
T.check(writes > w0 or family == "rse", "and the game keeps it (" .. (writes - w0) .. " writes)")
frame(1, "left")
-- (a page: A opens it, B back)
local gi
for i, r in ipairs(P0.rows) do if r.kind == "group" and not gi then gi = i end end
moveTo(P0, gi)
frame(1, "a")
frame(2)
T.check(#st().pages == 2 and pg() ~= P0 and #pg().rows > 0, "A on a page: opened (" .. tostring(pg().title) .. ")")
frame(1, "b")
T.check(#st().pages == 1, "B: back to the top")
-- (garbage, text size)
frame(30)
local kb = garbageOf(Tm, 60)
T.check(kb < 0.5, ("the OPTIONS screen: next to no garbage (%.3f KB a frame)"):format(kb))
K.setTextScale(1.3)
T.check(pcall(frame, 10), "the text at 130%")
K.setTextScale(1)

-- ------- WoobOS's row: its page here, its options as a tree
local wi = rowAt(P0, "woob_os")
moveTo(P0, wi)
frame(1, "a")
frame(2)
local MP = pg()
T.check(MP and MP.mod == "woob_os" and #st().pages == 2, "WOOBOS: its page in ours, not the mod manager")
local _, mb = rowAt(MP, "menuBag")
local _, mm = rowAt(MP, "modernMenus")
T.check(mb and mb.depth == 1 and mm and mm.depth == 0, "Bag under Modern Menus: one level in")
T.check(mb and not mb.label:find("^%-"), "its label without the old screen's \"- \" (" .. tostring(mb and mb.label) .. ")")
T.check(mm and mm.desc and #mm.desc > 20, "Modern Menus' description, for the card along the foot")
local n0 = #MP.rows
local mmi = rowAt(MP, "modernMenus")
moveTo(MP, mmi)
frame(1, "a")
frame(2)
T.check(run.loader.modOptions.woob_os and run.loader.modOptions.woob_os.modernMenus == false, "A: Modern Menus off")
T.check(#MP.rows < n0 and rowAt(MP, "menuBag") == nil, "its options folded away (" .. n0 .. " -> " .. #MP.rows .. ")")
T.check(MP.rows[MP.cur].id == "modernMenus", "the cursor still on it")
frame(1, "a")
frame(2)
T.check(#MP.rows == n0 and rowAt(MP, "menuBag") ~= nil, "on again: back")
K.setTextScale(1.3)
T.check(pcall(frame, 10), "the page's text at 130%")
K.setTextScale(1)
frame(30)
kb = garbageOf(Tm, 60)
T.check(kb < 0.5, ("a mod's page: next to no garbage (%.3f KB a frame)"):format(kb))
frame(1, "b")
T.check(#st().pages == 1, "B: back to the top")
frame(1, "b")
T.check(not Tm.isOpen() and closed == 1 and not Os.isOpen(), "B at the top: closed, the game told once")
T.check((family ~= "frlg" or FrMenu.open == false) and (family ~= "rs" or RsMenu.open == false), "the game's own flag down")

-- ------- a mod's row added past the hook, by wrapping the engine's grouping (as Vivid Worlds adds its page),
-- with an id that isn't its mod's: tagged all the same, named by the mod whose name it carries
do
  local Rows = require("src.ui.game3.option_rows")
  local group = Rows.group
  Rows.group = function(rows, openPage, ...)
    local view = group(rows, openPage, ...)
    view[#view + 1] = { id = "other_page", label = "WOOBOS", value = function() return "" end, activate = function() end }
    return view
  end
  local okT, rows = pcall(Os.top, { session = s, game = game }, family, function() end)
  Rows.group = group
  local got
  for _, r in ipairs(okT and rows or {}) do if r.id == "other_page" then got = r end end
  T.check(got ~= nil and got.modName == "Mod" and got.label == "WoobOS",
          "a row added by wrapping the grouping: tagged, named for its mod (" .. tostring(got and got.label) .. ", "
          .. tostring(got and got.modName) .. ")")
  local tagged = 0
  for _, r in ipairs(okT and rows or {}) do if r.modName then tagged = tagged + 1 end end
  T.check(tagged == 2, "and still only the mods' rows tagged (" .. tagged .. ")")
end

-- ------- the mod manager's way in: a mod's options page ours, over it
do
  local ms = MS.new(game)
  ms:refresh()
  local entry = ms.byId and ms.byId.woob_os
  T.check(entry ~= nil, "the mod manager knows WoobOS")
  if entry then
    ms:openOptions(entry)
    T.check(Ts.isOpen() and Sh.sceneOpen("options"), "the manager's OPTIONS for a mod: our page, on top")
    frame(5)
    frame(1, "b")
    T.check(not Ts.isOpen(), "B: closed, back to the manager")
  end
end

-- ------- the switch off: the game's own
run.loader.modOptions.woob_os = { menuOptions = false }
local okOwn = pcall(Screens.get("option", s).show, { session = s, game = game, onClose = function() end })
T.check(not Tm.isOpen() and (not okOwn or Stack.has("option")), "Options off: the game's own")
if Stack.has("option") then pcall(Screens.get("option", s).close) end
run.loader.modOptions.woob_os = nil

T.finish("woob_os options screen (" .. GAME .. ")")
