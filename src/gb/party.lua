-- The party behind the modern menus' Pokémon screen on the Game Boy games (src/party.lua's interface, so
-- src/apps/party.lua and party_view.lua are unchanged): Red / Blue / Yellow and Gold / Silver / Crystal. The rules
-- are the games' own: each Pokémon's menu as their party menu builds it (its field moves in its moves' order,
-- STATS, SWITCH, Gold / Silver / Crystal's ITEM or MAIL, another mod's rows through ui.party.submenu), the field
-- moves through the games' own field (Gen 1: the overworld's useCut / useSurf / useStrength / useFlash, Fly's Town
-- Map, Teleport / Dig; Gen 2: World:useFieldMove and what the party menu does with its answer), SWITCH as the game
-- swaps (Gen 2's mail with it), held items through Gen 2's own give / take rules. The words are the games' (ROM
-- text), cleaned of their codes.
--
-- A flow talks to the window through `ui` (src/party.lua's header).
--
--   Pt = GbParty(H, Gd, deps)   deps: T, log
--   (src/party.lua's functions) ; Pt.battleOf(game) -> the battle on the stack | nil

local floor, max, min = math.floor, math.max, math.min

-- (each generation's status words -> the cards' ids: 1 psn, 2 par, 3 slp, 4 frz, 5 brn, 7 fainted)
local STATUS = { SLP = 3, PSN = 1, BRN = 5, FRZ = 4, PAR = 2, sleep = 3, poison = 1, toxic = 1, paralyze = 2,
                 burn = 5, freeze = 4 }
local STATUS_KEY = { [1] = "sum.status.psn", [2] = "sum.status.par", [3] = "sum.status.slp", [4] = "sum.status.frz",
                     [5] = "sum.status.brn", [7] = "sum.status.fnt" }
local ACT_WORD = { SUMMARY = "party.act.summary", SWITCH = "party.act.switch", ITEM = "party.act.item",
                   MAIL = "party.act.mail", CANCEL = "party.act.cancel", GIVE = "party.act.give", TAKE = "party.act.take",
                   READ = "party.act.read", TAKE_MAIL = "party.act.take", SHIFT = "party.act.shift",
                   ["SEND OUT"] = "party.act.sendOut" }
-- (Red / Blue / Yellow's field moves, the party menu's own)
local FIELD1 = { FLY = true, FLASH = true, CUT = true, SURF = true, STRENGTH = true, SOFTBOILED = true, TELEPORT = true,
                 DIG = true }
-- (the dungeon tilesets Dig works in: escape_rope_tilesets.asm)
local DIG_TILESETS = { FOREST = true, CEMETERY = true, CAVERN = true, FACILITY = true, INTERIOR = true }

return function(H, Gd, deps)
  local Pt = {}
  local T = deps.T
  local gen, engine = H.gen, H.engine
  local function log(fmt, ...) if deps.log then pcall(deps.log, fmt, ...) end end
  local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b, c = pcall(f, ...)
    if not ok then
      log("the party: %s", tostring(a))
      return nil
    end
    return a, b, c
  end
  local function game() return H.game() end
  local function data() return Gd.data() end
  function Pt.se(name) H.se(name) end

  -- ------- the games' words

  local function rom(label, ...)
    local R, d = H.engineFn("src.core.RomText"), data()
    if not (R and d) then return "" end
    local ok, s = pcall(R, d, label, nil, ...)
    return ok and type(s) == "string" and s or ""
  end
  local function gameName(mon)
    if type(mon) ~= "table" then return "?" end
    if type(mon.nickname) == "string" and mon.nickname ~= "" then return mon.nickname end
    local def = Gd.def(mon.species)
    return tostring(def and def.name or mon.name or mon.species or "?")
  end
  function Pt.pages(text)
    local s0 = tostring(text or "")
    if gen == 2 then
      local CT = engine("src.core.gen2.CommonText")
      if CT and CT.plain then
        local ok, p = pcall(CT.plain, s0)
        if ok and type(p) == "string" then s0 = p end
      end
    end
    if s0:find("{", 1, true) then
      local g = game()
      local p = g and g.save and g.save.player
      s0 = s0:gsub("{PLAYER}", tostring(type(p) == "table" and p.name or "")):gsub("{COLON}", ":")
      s0 = s0:gsub("{RAM:[%w_]+}", ""):gsub("{[%u_][%u_%d]*}", "")
    end
    local out = {}
    for page in (s0 .. "\f"):gmatch("(.-)\f") do
      local s = page:gsub("[\n\r\t]", " "):gsub("%c", ""):gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
      if s ~= "" then out[#out + 1] = s end
    end
    if #out == 0 then out[1] = "" end
    return out
  end

  -- ------- a card

  local function expOf(mon, def)
    local d = data()
    if not (d and def) then return nil end
    local level = tonumber(mon.level) or 1
    if level >= 100 then return nil end
    if gen == 2 then
      local Mon = engine("src.battle.gen2.Mon")
      if not Mon then return nil end
      local curve = call(Mon.growthFor, d, def.growthRate)
      local lo = tonumber(call(Mon.experienceForLevel, curve, level)) or 0
      local hi = tonumber(call(Mon.experienceForLevel, curve, level + 1)) or lo
      return tonumber(mon.experience) or lo, lo, hi
    end
    local Growth = engine("src.pokemon.Growth")
    if not Growth then return nil end
    local lo = tonumber(call(Growth.expForLevel, def.growthRate, level, d.growth_rates)) or 0
    local hi = tonumber(call(Growth.expForLevel, def.growthRate, level + 1, d.growth_rates)) or lo
    return tonumber(mon.exp) or lo, lo, hi
  end
  local function heldOf(mon) return gen == 2 and type(mon) == "table" and mon.item ~= nil and mon.item ~= "" and mon.item or nil end
  local function isMail(item)
    if gen ~= 2 or not item then return false end
    local M = engine("src.core.gen2.Mail")
    if M and M.isMail then
      local ok, yes = pcall(M.isMail, item)
      if ok then return yes == true end
    end
    return tostring(item):find("MAIL", 1, true) ~= nil
  end

  function Pt.card(mon, Tw)
    Tw = Tw or T
    local egg = Gd.isEgg(mon) == true
    local c = { mon = mon, egg = egg, sp = mon and mon.species or 0 }
    c.name = Gd.monName(mon)
    c.level = tonumber(mon and mon.level) or 1
    c.levelText = egg and "" or (Tw and Tw.f and Tw.f("boxes.level", c.level) or ("Lv. " .. c.level))
    c.maxHp = max(1, tonumber(Gd.maxHp(mon)) or 1)
    if not egg then
      c.shiny = Gd.shiny(mon) == true
      local g = Gd.gender(mon)
      c.gender = (g == "M" or g == "F") and g or nil
      local st = STATUS[mon.status or ""] or 0
      if (tonumber(mon.hp) or 0) <= 0 then st = 7 end
      c.statusId = st
      c.status = STATUS_KEY[st] and Tw and Tw(STATUS_KEY[st]) or nil
      local types = Gd.typesOf(mon.species) or {}
      c.t1 = types[1] and tonumber(types[1].id) or nil
      c.t2 = types[2] and tonumber(types[2].id) or nil
      if c.t2 == c.t1 then c.t2 = nil end
      local now, lo, hi = expOf(mon, Gd.def(mon.species))
      if now and hi and hi > lo then
        c.expK = max(0, min(100, floor((now - lo) / (hi - lo) * 100)))
        c.expNext = max(0, hi - now)
        c.expText = Tw and Tw.f and Tw.f("party.toNext", c.expNext) or nil
      end
    end
    c.item = heldOf(mon)
    c.mail = isMail(c.item)
    if c.item then
      c.itemName = tostring(Gd.itemName(c.item) or c.item)
      c.itemTitle = c.itemName
    end
    return c
  end

  -- (a TM or a stone for the game's bag's picker: whether it can take it)
  function Pt.tag(c, mon)
    if Gd.isEgg(mon) then return "party.notAble" end
    local def = Gd.def(mon.species)
    if c.tmMove then
      for _, m in ipairs(def and (def.tmhm or def.tmhmMoves) or {}) do
        if m == c.tmMove then return "party.able" end
      end
      return "party.notAble"
    end
    if c.stone then
      for _, e in ipairs(def and def.evolutions or {}) do
        if type(e) == "table" and (e.item == c.stone or e.param == c.stone) then return "party.able" end
      end
      return "party.notAble"
    end
    return nil
  end
  -- ------- Crystal's Move Tutor: c.tutor is the game's own tutor (src.ui.gen2.MoveTutor, built off the stack by
  -- src/gb/menus.lua): its move, who can learn it, and what it does with the one chosen (its words, the move to
  -- forget, its finish)
  function Pt.tutorMove(c)
    local t = c.tutor
    if type(t) ~= "table" then return nil, "" end
    return t.move, Gd.moveName(t.move)
  end
  function Pt.tutorTag(c, mon)
    local t = c.tutor
    if type(t) ~= "table" or type(mon) ~= "table" or Gd.isEgg(mon) then return nil end
    for _, mv in ipairs(mon.moves or {}) do
      if (type(mv) == "table" and mv.id or mv) == t.move then return "party.learned" end
    end
    local MT = engine("src.ui.gen2.MoveTutor")
    local can = MT and MT.canLearn and call(MT.canLearn, t.view and t.view[mon.species], t.move)
    return can and "party.able" or "party.notAble"
  end
  function Pt.tutor(c, i, ui)
    local t, mon = c.tutor, c.party[i]
    if not (type(t) == "table" and mon) then return ui.back("list") end
    local ok, err = pcall(t.picked, t, mon)
    if not ok then
      log("the Move Tutor: %s", tostring(err))
      ui.back("list")
    end
  end
  function Pt.eligible() return true end
  function Pt.ally() return nil end
  function Pt.multiActions() return {} end
  function Pt.fullText() return "" end
  function Pt.noneText() return "" end
  function Pt.cancelText() return "" end
  function Pt.pump() end

  -- ------- the battle: its foe, and how each of ours fares against it

  function Pt.battleOf(g)
    g = g or game()
    local list = g and g.stack and g.stack.states
    if type(list) ~= "table" then return nil end
    for i = #list, 1, -1 do
      local s = list[i]
      if type(s) == "table" and (s.isBattleState or s.screenId == "Gen2BattleState" or (gen == 2 and s.isBattle and s.battle)) then
        return s
      end
    end
    return nil
  end
  -- (a move type on defending types, as a multiple: the games' charts give tenths)
  local function mult(moveType, defTypes, b)
    local d = data()
    if gen == 2 then
      local Damage = engine("src.battle.gen2.Damage")
      if not (Damage and Damage.typeMultiplier) then return nil end
      local matchups = d and d.type_chart and d.type_chart.matchups
      local k = tonumber(call(Damage.typeMultiplier, moveType, defTypes, matchups))
      return k and k / 10 or nil
    end
    local TC = engine("src.battle.TypeChart")
    if not (TC and TC.effectiveness) then return nil end
    if d then pcall(TC.load, d) end
    local k = tonumber(call(TC.effectiveness, moveType, defTypes))
    return k and k / 10 or nil
  end
  local function speciesTypes(sp)
    local def = Gd.def(sp)
    local t = def and def.types
    if type(t) ~= "table" then return nil end
    local out = {}
    for _, x in ipairs(t) do
      local dup = false
      for _, y in ipairs(out) do if y == x then dup = true end end
      if not dup then out[#out + 1] = x end
    end
    return out
  end

  -- its best damaging move on the foe, the foe's worst type on it: multiples (4 .. 0), nil when unknown
  function Pt.matchup(c, mon)
    if not (c.battle and mon) or Gd.isEgg(mon) then return nil end
    local b = Pt.battleOf()
    if not b then return nil end
    local foeTypes, mine
    if gen == 2 then
      local bt = b.battle
      local foe = bt and bt.enemy
      if not foe then return nil end
      foeTypes = (bt.battlerTypes and call(bt.battlerTypes, bt, foe)) or foe.types or speciesTypes(foe.species)
      if bt.player == mon then mine = call(bt.battlerTypes, bt, mon) end
    else
      local foe = b.enemy
      if not foe then return nil end
      foeTypes = foe.curTypes or (foe.def and foe.def.types) or speciesTypes(foe.mon and foe.mon.species)
      if b.player and b.player.mon == mon then mine = b.player.curTypes end
    end
    mine = mine or speciesTypes(mon.species)
    if type(foeTypes) ~= "table" or type(mine) ~= "table" or not foeTypes[1] then return nil end
    local def = 0
    for _, ft in ipairs(foeTypes) do
      local k = mult(ft, mine)
      if k and k > def then def = k end
    end
    local atk = nil
    local moves = data() and data().moves or {}
    for _, mv in ipairs(mon.moves or {}) do
      local id = type(mv) == "table" and (mv.id or mv.move) or mv
      local m = id and moves[id]
      if type(m) == "table" and (tonumber(m.power) or 0) > 0 then
        local k = mult(m.type, foeTypes)
        if k and (atk == nil or k > atk) then atk = k end
      end
    end
    return atk, def
  end

  -- ------- each Pokémon's menu

  local function row(act, text, fm)
    local key = ACT_WORD[act]
    return { act = act, fm = fm or nil, text = text or (key and T and T(key)) or tostring(act) }
  end
  local function moveName(id)
    local d = data()
    local m = d and d.moves and d.moves[id]
    return Gd.title(tostring(m and m.name or id):gsub("_", " "))
  end
  local function knows(mon, id)
    for _, mv in ipairs(mon and mon.moves or {}) do if (type(mv) == "table" and mv.id or mv) == id then return true end end
    return false
  end
  local function fieldMoves(mon)
    local out = {}
    if Gd.isEgg(mon) then return out end
    if gen == 2 then
      local PM = engine("src.ui.gen2.PartyMenu")
      for _, id in ipairs(PM and PM.FIELD_MOVES or {}) do if knows(mon, id) then out[#out + 1] = id end end
    else
      for _, mv in ipairs(mon.moves or {}) do
        local id = type(mv) == "table" and mv.id or mv
        if FIELD1[id] then out[#out + 1] = id end
      end
    end
    return out
  end

  -- another mod's rows through the engine's hook (as the game's party menu asks it): a row with its own onSelect kept
  local function hooked(c, i, rows)
    local Runtime = engine("src.mods.Runtime")
    if not (Runtime and Runtime.call) then return rows end
    local items, base = {}, {}
    for k, r in ipairs(rows) do
      items[k] = { label = r.text, action = r.act, id = r.act }
      base[r.act] = r
    end
    local g = game()
    local ok, out = pcall(Runtime.call, "ui.party.submenu", function(_, list) return list end, g, items, c.party[i],
      { battle = c.battle, overworld = g and (g.overworld or g.world) })
    if not (ok and type(out) == "table") then return rows end
    local res = {}
    for k = 1, #out do
      local r = out[k]
      if type(r) ~= "table" then return rows end
      local key = r.action or r.id
      if base[key] then
        res[#res + 1] = { act = key, fm = base[key].fm, text = type(r.label) == "string" and r.label or base[key].text }
      elseif type(r.onSelect) == "function" then
        res[#res + 1] = { act = "HOOK", text = tostring(r.label or ""), onSelect = r.onSelect }
      end
    end
    return #res > 0 and res or rows
  end

  -- the menu of the i-th outside a battle: STATS, its field moves (first, as the games list them), SWITCH,
  -- ITEM / MAIL (Gold / Silver / Crystal), CANCEL
  function Pt.actions(c, i)
    local mon = c.party[i]
    local rows = {}
    for _, id in ipairs(fieldMoves(mon)) do rows[#rows + 1] = row(id, moveName(id), true) end
    rows[#rows + 1] = row("SUMMARY")
    if c.party[2] then rows[#rows + 1] = row("SWITCH") end
    if gen == 2 and not Gd.isEgg(mon) then rows[#rows + 1] = row(isMail(heldOf(mon)) and "MAIL" or "ITEM") end
    rows[#rows + 1] = row("CANCEL")
    return hooked(c, i, rows)
  end
  function Pt.battleActions(c, i)
    local mon = c.party[i]
    local rows = {}
    if c.party[2] and not Gd.isEgg(mon) then rows[1] = row(c.mode == "battle_faint" and "SEND OUT" or "SHIFT") end
    rows[#rows + 1] = row("SUMMARY")
    rows[#rows + 1] = row("CANCEL")
    return rows
  end
  function Pt.itemActions(c, kind)
    if kind == "MAIL" then return { row("READ"), row("TAKE_MAIL"), row("CANCEL") } end
    return { row("GIVE"), row("TAKE"), row("CANCEL") }
  end
  function Pt.hookRow(c, i, r)
    local g = game()
    if r and r.onSelect then r.onSelect(g, c.party[i]) end
  end

  -- ------- SWITCH: two places traded (Gold / Silver / Crystal's mail with them)
  function Pt.swap(c, a, b)
    local party = c.party
    if not (party[a] and party[b]) then return end
    party[a], party[b] = party[b], party[a]
    local s = c.session
    if gen == 2 and s and party == s.party then
      local M = engine("src.core.gen2.Mail")
      if M and M.swapSlots then pcall(M.swapSlots, s, a, b) end
    end
  end

  -- ------- the field moves

  -- (Red / Blue / Yellow: as the party menu's own, through the overworld; refusals in our words box, the move
  -- itself once ours is closed)
  local function field1(c, i, act, ui)
    local g = game()
    local ow = g and g.overworld
    local mon = c.party[i]
    if not (ow and mon) then return ui.back("list") end
    local name = gameName(mon)
    local function badge() return ui.say(rom("_NewBadgeRequiredText"), function() ui.back("list") end) end
    local function refuse(label) return ui.say((rom(label, name):gsub("{RAM:wNameBuffer}", name)), function() ui.back("list") end) end
    local Map = engine("src.world.Map")
    local FD = engine("src.world.FieldDefaults")
    local function outside()
      local okO, out = pcall(Map.isOutside, ow.map.def, FD and FD.field(g.data, "outsideTilesets"))
      return okO and out == true
    end
    if act == "FLY" then
      if not call(ow.partyKnows, ow, "FLY") then return badge() end
      if not outside() then return refuse("_CannotFlyHereText") end
      return ui.leave(function()
        local Screens = engine("src.ui.Screens")
        pcall(Screens.push, g, "TownMap", { fly = true, onFly = function(mapId)
          local top = g.stack:top()
          if top and top.fly then g.stack:pop() end
          ow:flyTo(mapId)
        end })
      end)
    elseif act == "FLASH" then
      if not call(ow.partyKnows, ow, "FLASH") then return badge() end
      return ui.leave(function() ow:useFlashFieldMove(function() end) end)
    elseif act == "SURF" then
      local reason = call(ow.useSurfFieldMove, ow)
      if reason == "ok" then
        local fx, fy = ow.player:facingCell()
        return ui.leave(function() ow:trySurf(fx, fy, function() end) end)
      elseif reason == "dismount" then
        return ui.leave(function() ow:stopSurfing(function() end) end)
      end
      local key = ({ no_badge = "_NewBadgeRequiredText", forced_bike = "_CyclingIsFunText",
                     current = "_CurrentTooFastText", no_place = "_SurfingNoPlaceToGetOffText" })[reason or ""]
                  or "_NoSurfingHereText"
      return refuse(key)
    elseif act == "CUT" then
      local reason = call(ow.useCutFieldMove, ow)
      if reason == "ok" then
        local fx, fy = ow.player:facingCell()
        return ui.leave(function() ow:tryCut(fx, fy) end)
      end
      return refuse(reason == "no_badge" and "_NewBadgeRequiredText" or "_NothingToCutText")
    elseif act == "STRENGTH" then
      if ow.useStrengthFieldMove then
        if not call(ow.partyKnows, ow, "STRENGTH") then return badge() end
        return ui.leave(function() ow:useStrengthFieldMove(mon, function() end) end)
      end
      return ui.leave(function() if ow.useFieldMove then ow:useFieldMove("STRENGTH", mon) end end)
    elseif act == "SOFTBOILED" then
      local maxHp = tonumber(Gd.maxHp(mon)) or 1
      if (tonumber(mon.hp) or 0) <= floor(maxHp / 5) then
        local d = data()
        return ui.say(d and d.text and d.text._NotHealthyEnoughText or rom("_NotHealthyEnoughText"), function() ui.back("list") end)
      end
      return ui.back("softboiled", i)
    elseif act == "TELEPORT" or act == "DIG" then
      if act == "TELEPORT" then
        if not outside() then return refuse("_CannotUseTeleportNowText") end
        local d = data()
        return ui.say(d and d.text and d.text._WarpToLastPokemonCenterText or "", function()
          ui.leave(function() ow:beginTeleportOut() end)
        end)
      end
      if not (DIG_TILESETS[ow.map.def.tileset] and ow.map.id ~= "AGATHAS_ROOM") then
        local p = g.save and g.save.player
        return ui.say(rom("_ItemUseNotTimeText", type(p) == "table" and p.name or ""), function() ui.back("list") end)
      end
      return ui.leave(function() ow:beginTeleportOut() end)
    end
    ui.back("list")
  end

  -- (Gold / Silver / Crystal: World:useFieldMove asked, its refusal said here; then the party menu's own steps)
  local function field2(c, i, act, ui)
    local g = game()
    local w = g and g.world
    local mon = c.party[i]
    if not (w and w.useFieldMove and mon) then return ui.back("list") end
    local said
    local show = w.showText
    w.showText = function(_, text) said = text end
    local okU, result = pcall(w.useFieldMove, w, act, mon)
    w.showText = show
    if not okU then
      log("a field move: %s", tostring(result))
      return ui.back("list")
    end
    if not (result and result.ok) then
      if said then return ui.say(said, function() ui.back("list") end) end
      return ui.back("list")
    end
    if result.inMenu then
      c.softCost = result.cost
      return ui.back("softboiled", i)
    end
    -- (out to the field: everything closed, as the party menu's exitToField; Fly's map first)
    local function exit()
      local stk = g.stack
      if stk and stk.clear then
        stk:clear()
        if w.exitMenusFade and not w.mapSetup then pcall(w.exitMenusFade, w) end
      end
    end
    ui.leave(function()
      if result.action == "rocksmash" then
        w.queuedFieldMove = nil
        local FM = engine("src.world.gen2.FieldMoves")
        local script = FM and call(FM.rockSmashFromMenuScript, w.stdScripts, w.vm and w.vm.scripts,
          function(name) return w:specialIdNamed(name) end)
        if script then
          if w.vm then w.vm.lastTalked = result.lastTalked end
          w.queuedScript = script
        end
        return exit()
      end
      if result.action == "fly" and w.openFlyMap then
        w.queuedFieldMove = nil
        local opened = w:openFlyMap(mon, {
          onChosen = function(spawnId)
            result.flySpawn = spawnId
            w.queuedFieldMove = result
            if w.exitMenusFadeForFly then w:exitMenusFadeForFly() elseif w.exitMenusFade then w:exitMenusFade() end
            exit()
          end,
          onCancel = function() end,
        })
        if opened then return end
        w.queuedFieldMove = result
      end
      exit()
    end)
  end

  function Pt.fieldMove(c, i, act, ui)
    if gen == 2 then return field2(c, i, act, ui) end
    return field1(c, i, act, ui)
  end

  -- Softboiled / Milk Drink: a fifth of its HP to another (each game's own transfer and words)
  function Pt.softboiled(c, from, to, ui)
    local a, b = c.party[from], c.party[to]
    if not (a and b) or from == to then return ui.back("softboiled", from) end
    local a0, b0 = tonumber(a.hp) or 0, tonumber(b.hp) or 0
    local before, after
    if gen == 2 then
      local FM = engine("src.world.gen2.FieldMoves")
      before, after = call(FM and FM.softboiledTransfer, a, b, c.softCost or 0)
    else
      local heal = a.stats and floor((tonumber(a.stats.hp) or 0) / 5) or 0
      if not (Gd.isEgg(b) or b0 <= 0 or b0 >= (tonumber(b.stats and b.stats.hp) or 0) or a0 <= heal) then
        before = b0
        a.hp = a0 - heal
        b.hp = math.min(tonumber(b.stats.hp) or b0, b0 + heal)
        after = b.hp
      end
    end
    if not before then
      H.se("SE_FAILURE")
      return ui.say(rom(gen == 2 and "_ItemCantUseOnMonText" or "_ItemUseNoEffectText"), function()
        ui.back("softboiled", from)
      end)
    end
    c.softCost = nil
    H.sfx(gen == 2 and "Sfx_Potion" or "Heal_HP")
    ui.hp(from, a0, tonumber(a.hp) or 0, function()
      ui.hp(to, before, after, function()
        ui.say(rom(gen == 2 and "_RecoveredSomeHPText" or "_PotionText", gameName(b), after - before), function()
          ui.refresh()
          ui.back("list")
        end)
      end)
    end)
  end

  -- ------- held items (Gold / Silver / Crystal): the game's own rules, through its menu built off the stack (its
  -- words in our box, its question in ours, a mail to write over ours)
  local function heldMenu(c, i, ui, after, path)
    local g = game()
    local HM = engine(path or "src.ui.gen2.HeldItemMenu")
    if not (HM and HM.new) then return nil end
    local text = (g and g.world and g.world.text) or (data() and data().gen2Text)
    local okN, held = pcall(HM.new, g, { save = c.session, slot = i, items = data() and data().items, text = text,
                                         onClose = function() end })
    if not okN then
      log("the game's %s: %s", tostring(path or "held item menu"), tostring(held))
      return nil
    end
    -- (its words: pages, each a page's lines -- or one string)
    local function text(list)
      if type(list) ~= "table" then return tostring(list or "") end
      local pages = {}
      for k, pg in ipairs(list) do
        pages[k] = type(pg) == "table" and table.concat(pg, " ") or tostring(pg)
      end
      return table.concat(pages, "\f")
    end
    held.say = function(_, list, cb)
      ui.refresh()
      ui.say(text(list), function() if cb then cb() end end)
    end
    held.ask = function(_, list, onYes, onNo)
      ui.ask(text(list), function(yes)
        if yes then if onYes then onYes() end elseif onNo then onNo() end
      end)
    end
    held.close = function()
      ui.refresh()
      ui.back("list")
      if after then after() end
    end
    -- (it goes back to the pack on a refusal: ours goes back to the cards)
    held.openPack = held.close
    return held
  end
  function Pt.take(c, i, ui)
    local held = heldMenu(c, i, ui)
    if not held then return ui.back("list") end
    local ok, err = pcall(held.takeItem, held)
    if not ok then
      log("taking an item: %s", tostring(err))
      ui.back("list")
    end
  end
  -- (mail: the game's own mail menu built off the stack -- TAKE's questions and words in ours; READ its own reader,
  -- over ours, as the Gen 3 games' is)
  local function mailDo(c, i, ui, how)
    local mm = heldMenu(c, i, ui, nil, "src.ui.gen2.MailMenu")
    if not mm then return ui.back("list") end
    local ok, err = pcall(mm[how], mm)
    if not ok then
      log("the mail: %s", tostring(err))
      ui.back("list")
    end
  end
  function Pt.takeMail(c, i, ui) mailDo(c, i, ui, "take") end
  function Pt.readMail(c, i, ui) mailDo(c, i, ui, "read") end
  function Pt.give(c, i, item, source, ui, after)
    local held = item and heldMenu(c, i, ui, after)
    if not held then
      if after then after() end
      return
    end
    local ok, err = pcall(held.giveItem, held, item)
    if not ok then
      log("giving an item: %s", tostring(err))
      if after then after() end
    end
  end
  -- (an item's GIVE from the party: the game's pack in give mode, over ours)
  function Pt.openBag(c, onClose)
    if gen ~= 2 then return false end
    local g = game()
    local Screens = engine("src.ui.Screens")
    local ok = Screens and pcall(Screens.push, g, "Gen2PackMenu", { save = c.session, give = true, world = {},
      onChoose = function(id)
        g.stack:pop()
        if Pt.giveHandler then Pt.giveHandler(id) end
      end,
      onClose = function()
        g.stack:pop()
        if onClose then onClose() end
      end })
    return ok == true
  end
  function Pt.use(c, i, ui) ui.back("list") end

  return Pt
end
