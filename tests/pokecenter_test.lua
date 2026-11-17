-- Standalone: luajit mods/woob_os/tests/pokecenter_test.lua [game] (from the gen1recomp root; needs that
-- cart imported, Emerald by default).
--
-- The Pokémon Center (src/pokecenter.lua, src/apps/pokecenter.lua, its view): the nurse's shared script
-- found in the cart's own scripts (by its flow reaching the healing machine); a map's nurse run through a
-- stand-in VM with our script.command catch: her `call` runs, ours opens inside it, the VM is taken back
-- out (her `return`) and held until ours closes, her last words' box skipped, her `release` after; the
-- window walked by buttons (the greeting, the choice, the machine's beats, the team healed, "anything
-- else?", the goodbye); the game's side effects (HP / status / PP, the game stat, Pokérus explained
-- once on Ruby / Sapphire / Emerald, Emerald's Gold Card); the game's own nurse when ours can't open;
-- next to no garbage; the text at 130%.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GAME = arg[1] or "emerald"
local RSE = not (GAME == "firered" or GAME == "leafgreen")

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
local Sh, Tm, D, K, env = X._test.shell, X._test.townmap, X._test.desktop, X._test.kit, X._test.env
local Pc = X._test.pokecenter
local Stack = require("src.ui.game3.stack")
T.check(Pc ~= nil and Tm ~= nil, "the Pokémon Center's takeover and the full-screen host are made")

local function input(press, down)
  local p, d = {}, {}
  for _, k in ipairs(press or {}) do p[k] = true end
  for _, k in ipairs(down or {}) do d[k] = true end
  return { wasPressed = function(_, k) return p[k] == true end, isDown = function(_, k) return d[k] == true end }
end
local VP = { width = 480, height = 320 }
local NONE = input()
local function frame(n, press)
  for i = 1, n or 1 do
    clock = clock + 1 / 60
    Tm.input(i == 1 and press and input({ press }) or NONE)
    Tm.draw(G, VP)
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

-- ------- a session with a hurt team
local Bag, Storage = require("src.core.game3.bag"), require("src.core.game3.storage")
local ItemsData, P, Party = require("src.core.game3.items_data"), require("src.core.game3.pokemon"), require("src.core.game3.party")
local function newSession()
  local s = { name = "WOS", playerName = "WOS", bag = Bag.new(), storage = Storage.new(), party = {}, money = 3000,
              flags = {}, vars = {}, gender = 0, gameStats = {} }
  ItemsData.ensureModel(s)
  s.dex = { seen = {}, owned = {}, caught = {} }
  return s
end
local s = newSession()
require("src.core.game3.runtime").getSession = function() return s end
local function sp(nat) return P.speciesFromNational(nat) end
Party.giveMon(s, sp(RSE and 255 or 4), 12)
Party.giveMon(s, sp(25), 9)
Party.giveMon(s, sp(129), 5)
local function hurt()
  for _, mon in ipairs(s.party) do
    mon.hp, mon.status = 1, 0x08
    for k, pp in pairs(mon.pp or {}) do mon.pp[k] = 0 end
  end
end
hurt()
T.eq(#s.party, 3, "a team of three")

-- ------- the cart's own scripts: her shared one found by its flow
local scripts = dofile(GAME .. "/data/generated/gba/scripts/scripts.lua")
if type(scripts.scripts) == "table" then scripts = scripts.scripts end
local Flags = require("src.core.game3.scripting.flags")
local store = { flags = {}, vars = {} }
local vm = { scripts = scripts, store = store }
local perMap, common
for key, list in pairs(scripts) do
  if type(list) == "table" then
    for _, r in ipairs(list) do
      if r.op == "call" and Pc.isNurse(vm, r.target or r[1]) and #list <= 6 then
        perMap, common = key, r.target or r[1]
        break
      end
    end
  end
  if perMap then break end
end
T.check(perMap ~= nil, "a map's nurse found (" .. tostring(perMap) .. " calls " .. tostring(common) .. ")")
-- (only her shared script: the heal machine's own list and an ordinary script aren't hers)
local healList
for key, list in pairs(scripts) do
  if type(list) == "table" then
    for _, r in ipairs(list) do
      if r.op == "dofieldeffect" and tonumber(r[1]) == 25 then healList = key end
    end
  end
end
T.check(healList and not Pc.isNurse(vm, healList), "the machine's own list isn't her script")
-- (headless nothing counts the fanfare down)
require("src.core.game3.audio").isFanfareFinished = function() return true end

-- ------- the stand-in VM: rows run through our catch; `call` / `return` as the game's
local log = {}
local function newVm()
  local v = { scripts = scripts, store = store, ctx = { pc = { listKey = perMap, index = 1 }, stack = {} } }
  v.adapters = {
    nurseHeal = function(done) Party.healAll(s.party); if done then done() end end,
    log = noop,
  }
  return v
end
local function vanilla(v)
  return function(_, op, row)
    log[#log + 1] = op
    local pc = v.ctx.pc
    if op == "call" then
      v.ctx.stack[#v.ctx.stack + 1] = { listKey = pc.listKey, index = pc.index }
      pc.listKey, pc.index = row.target or row[1], 1
    elseif op == "return" then
      local f = table.remove(v.ctx.stack)
      if f then pc.listKey, pc.index = f.listKey, f.index end
    elseif op == "end" then
      v.ended = true
    end
    return false
  end
end
-- runs until it yields or ends -> "yield" | "end"
local function runVm(v)
  local nxt = vanilla(v)
  for _ = 1, 200 do
    local pc = v.ctx.pc
    local list = scripts[pc.listKey]
    local row = list and list[pc.index]
    if not row then return "end" end
    pc.index = pc.index + 1
    local yield = Pc.command(nxt, { runner = v, vm = v }, row.op, row)
    if yield == true then return "yield" end
    if v.ended then return "end" end
  end
  return "runaway"
end

local v = newVm()
local got = runVm(v)
T.eq(got, "yield", "her script held")
T.check(Tm.isOpen() and Tm.state().ctx.app == "pokecenter" and Stack.has(Sh.MAP_ID), "ours open, full screen")
T.check(v.ctx.pc.listKey == perMap and #v.ctx.stack == 0, "taken back out of her shared script (her `return`)")
T.check(v.ctx.mode == "native" and v.ctx.nativePoll and not v.ctx.nativePoll(), "the VM waits on ours")
local W = Tm.state().win
local st = W.state
T.check(Tm.state().opts.chrome == false and Tm.state().opts.noHints == true, "no toolbar, no hints")

-- ------- the window, by buttons
frame(2)
T.check(st.say and st.say.text:find("Pokémon Center", 1, true) and st.after == "menu", "her greeting: " .. tostring(st.say and st.say.text))
frame(1, "a")
frame(1)
T.check(st.full and st.menu, "A: all of it, and the choice")
T.check(st.cursor == 1, "Heal first")
frame(1, "down")
T.eq(st.cursor, 2, "Down: I'm all good")
frame(1, "up")
T.eq(st.cursor, 1, "Up: back to Heal")
local g0 = s.gameStats[15] or 0
frame(1, "a")
T.check(st.say.text:find("Pokémon", 1, true) and st.after == "machine", "Heal: she takes them: " .. st.say.text)
frame(60)
frame(1, "a")
T.eq(st.face, "left", "she turns to the machine")
for _ = 1, 60 do
  frame(1)
  if st.scene == "machine" then break end
end
T.eq(st.scene, "machine", "the machine, after the fade")
local placedAt = {}
local healed = false
for _ = 1, 60 * 9 do
  frame(1)
  if st.mc then placedAt[st.mc.placed] = placedAt[st.mc.placed] or clock end
  if st.mc and st.mc.healed and not healed then
    healed = true
    local ok = true
    for _, mon in ipairs(s.party) do
      if mon.hp ~= mon.maxHp then ok = false end
    end
    T.check(ok, "healed in the glow: every HP full")
  end
  if st.scene == "nurse" and st.black == 0 then break end
end
T.check(placedAt[3] ~= nil and placedAt[1] < placedAt[3], "a ball for each one, one after another")
T.check(healed, "the machine healed them")
T.eq(s.gameStats[15] or 0, g0 + 1, "the game's \"used a Pokémon Center\" stat")
T.check(st.scene == "nurse" and st.say and st.say.text:find("rest of your team", 1, true),
  "back to her: " .. tostring(st.say and st.say.text))
-- (the rest of what she says, to "anything else?")
for _ = 1, 30 do
  if st.menu then break end
  frame(1, "a")
  frame(3)
end
T.check(st.menu and st.say.text:find("anything else", 1, true), "anything else? and the choice again")
local ng = garbageOf(120)
T.check(ng < 0.5, ("the counter's draw: %.3f KB a frame"):format(ng))
frame(1, "b")
T.check(st.say.text:find("again", 1, true) and st.after == "close", "B: I'm all good, her goodbye")
frame(60)
frame(1, "a")
T.check(not Tm.isOpen() and not Stack.has(Sh.MAP_ID), "A: closed")
T.check(v.ctx.nativePoll(), "the VM goes on")
log = {}
got = runVm(v)
T.check(got == "end", "her script ends (" .. got .. ")")
local ops = table.concat(log, " ")
T.check(not ops:find("waitmessage", 1, true) and not ops:find("waitbuttonpress", 1, true), "her last words' box skipped (" .. ops .. ")")
T.check(ops:find("release", 1, true) ~= nil, "her release, as hers")

-- ------- the machine's draw, and the text at 130%
hurt()
v = newVm()
runVm(v)
W = Tm.state().win
st = W.state
st.say, st.after = { text = "x", t = clock, n = 1 }, "machine"
st.full = true
frame(1, "a")
for _ = 1, 120 do
  frame(1)
  if st.scene == "machine" and st.mc and st.mc.placed >= 2 then break end
end
local mg = garbageOf(120)
T.check(mg < 0.5, ("the machine's draw: %.3f KB a frame"):format(mg))
K.setTextScale(1.3)
local okD = pcall(frame, 30)
T.check(okD, "the text at 130%")
K.setTextScale(1)
Tm.state().ctx.done()
T.check(not Tm.isOpen(), "closed")

-- ------- Pokérus, explained once (Ruby / Sapphire / Emerald); Emerald's Gold Card
if RSE then
  hurt()
  s.party[1].pokerus = 0x13
  Flags.setFlag(store, nil, 273, false)
  local m = Pc.make(newVm(), s)
  T.check(m.heal() == true and Flags.getFlag(store, nil, 273), "Pokérus: explained, FLAG_POKERUS_EXPLAINED set")
  T.check(m.heal() == false, "only once")
  s.party[1].pokerus = 0
end
if GAME == "emerald" then
  local FieldRse = require("src.core.game3.scripting.natives_field_rse")
  local stars = FieldRse.countTrainerStars
  FieldRse.countTrainerStars = function() return 4 end
  Flags.setFlag(store, nil, 345, false)
  local m = Pc.make(newVm(), s)
  T.check(m.greet == "gold" and Flags.getFlag(store, nil, 345), "the Gold Card: her words the first time")
  m = Pc.make(newVm(), s)
  T.eq(m.greet, "usual", "the usual, after")
  FieldRse.countTrainerStars = stars
end

-- ------- ours can't open (the desktop's up): her own script
require("src.ui.game3.pc_menu").show({ session = s, startMode = "select", onClose = noop })
T.check(D.isOpen(), "the desktop open")
v = newVm()
log = {}
got = runVm(v)
T.check(got ~= "yield" and not Tm.isOpen() and table.concat(log, " "):find("callstd", 1, true) or
  table.concat(log, " "):find("message", 1, true), "her own script runs (" .. table.concat(log, " "):sub(1, 80) .. ")")

T.finish("woob_os pokecenter (" .. GAME .. ")")
