-- The party behind the modern menus' Pokémon screen (src/apps/party.lua draws it; src/menus.lua opens it
-- in place of the game's own party menu on FireRed / LeafGreen / Ruby / Sapphire / Emerald). The rules
-- are the game's: what each Pokémon's menu offers (its field moves, SWITCH, ITEM or MAIL, as the game's
-- party menu builds it, Ruby / Sapphire's own order, another mod's rows through the engine's
-- ui.party.submenu hook), the field moves through the engine's FieldMoves / Field, held items through
-- ItemUse (give, switch, take; mail to the PC), an item used on a Pokémon (a TM or HM, a Rare Candy, an
-- evolution stone, medicine, PP) through ItemUse / LearnMove / Evolution and the game's evolution scene.
-- The words the game says on the way are its own (ROM text), cleaned of its codes here.
--
-- A flow talks to the window through `ui` (the window's): ui.say(text, then) ; ui.ask(text, then(yes)) ;
-- ui.pick(prompt, names, then(i0 | nil)) ; ui.hp(i, from, to, then) (an HP bar filling) ;
-- ui.stats(mon, old, new, then) (a level's stats) ; ui.forget(i, moveId, then(slot0 | nil)) (the summary,
-- choosing a move to forget) ; ui.back(mode) (to picking again: "list" | "use" | "softboiled") ;
-- ui.close() (the menu closes, the game's onClose) ; ui.leave(fn) (closed, then fn: a field move) ;
-- ui.refresh() (the cards made again).
--
--   Pt = party(engine, deps)          deps: T, log, gmax(mon) -> true when it has the G-Max Factor
--   Pt.card(mon, T) -> a card's words and numbers (made in actions only) ; Pt.pages(text) -> plain pages
--   Pt.actions(c, i) -> { { act, text, fm, onSelect } ... } for the i-th's menu (c: the open menu's model,
--       below) ; Pt.itemActions(kind) ; Pt.battleActions(c, i)
--   Pt.fieldMove(c, i, act, ui) ; Pt.softboiled(c, from, to, ui) ; Pt.take(c, i, ui) ; Pt.takeMail(c, i, ui) ;
--   Pt.readMail(c, i, ui) ; Pt.give(c, i, item, source, ui, after) ; Pt.use(c, i, ui) ; Pt.tag(c, mon) -> a
--   tag key for the cards while an item's being used ("party.able" ...) | nil
--   c = { session, party (the shown order), order (the real slot of each shown one, a battle's), bag, item,
--         giveSource, battle, mode }

return function(engine, deps)
  local Pt = {}
  local T = deps.T
  local floor, max, min = math.floor, math.max, math.min
  local function log(fmt, ...) if deps.log then pcall(deps.log, fmt, ...) end end
  local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(f, ...)
    if not ok then
      log("the party: %s", tostring(a))
      return nil
    end
    return a, b, c, d, e
  end
  local function P() return engine("src.core.game3.pokemon") end
  local function Items() return engine("src.core.game3.items_data") end
  local function IU() return engine("src.core.game3.item_use") end
  local function RomText() return engine("src.core.game3.rom_text") end
  local function Bag() return engine("src.core.game3.bag") end
  local function se(id)
    local Audio, SeIds = engine("src.core.game3.audio"), engine("src.core.game3.se_ids")
    pcall(function() Audio.playSe(type(id) == "number" and id or SeIds.resolve(id)) end)
  end
  Pt.se = se
  local function fanfare(name)
    local Audio = engine("src.core.game3.audio")
    pcall(function() Audio.playFanfare(name) end)
  end
  local function quest(s, key, args)
    local Q = engine("src.core.game3.quest_log_recorder")
    if Q then pcall(Q.event, s, key, args) end
  end
  local function box(key, vars)
    local R = RomText()
    local ok, s = pcall(R.box, key, { stringVars = vars, maxWidth = 216 })
    return ok and s or ""
  end
  local function plainKey(key, ctx)
    local R = RomText()
    local ok, s = pcall(R.plain, key, ctx)
    return ok and s or ""
  end
  local function profile(s)
    local Pr = engine("src.core.game3.profile")
    local ok, row = pcall(Pr.forSession, s)
    return ok and row or nil
  end
  local function family(s)
    local Pr = engine("src.core.game3.profile")
    local ok, f = pcall(Pr.family, s)
    return ok and f or nil
  end
  local function rse(s) return family(s) == "rse" end
  local function rs(s)
    local row = profile(s)
    return row and (row.id == "ruby" or row.id == "sapphire") or false
  end
  -- (the game's party skin: Ruby / Sapphire's own rules, Emerald's field moves)
  local function partyUi(s)
    local row = profile(s)
    local p = row and type(row.ui) == "table" and row.ui.party or nil
    if type(p) == "string" then
      local ok, m = pcall(require, p)
      p = ok and m or nil
    end
    return type(p) == "table" and p or nil
  end
  Pt.partyUi = partyUi
  local function num(v)
    local I = Items()
    return (I and call(I.toNumericId, v)) or tonumber(v) or 0
  end
  local function heldOf(mon)
    local id = mon and (mon.item or mon.heldItem)
    id = num(id)
    return id ~= 0 and id or nil
  end
  local function isMail(id)
    local Mail = engine("src.core.game3.mail")
    return id ~= nil and Mail and call(Mail.isMailItem, id) == true or false
  end

  -- ------- words

  -- a game text box (pages split on its page breaks) -> plain pages: its codes out, its lines joined
  function Pt.pages(text)
    local TextIR = engine("src.core.game3.scripting.text_ir")
    local raw = tostring(text or "")
    local list = TextIR and call(TextIR.splitPages, raw, false) or { raw }
    local out = {}
    for _, page in ipairs(list or { raw }) do
      local s = TextIR and call(TextIR.protectExt, page) or page
      s = s:gsub("\255%x*\254", ""):gsub("{PKMN}", "POKéMON"):gsub("{PK}{MN}", "POKéMON"):gsub("{[%u_]+}", "")
      s = s:gsub("[%c]", " "):gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
      if s ~= "" then out[#out + 1] = s end
    end
    if #out == 0 then out[1] = "" end
    return out
  end

  -- (a name the game keeps in capitals, as the summary writes it: "Bold", "Blaze")
  local function titledName(s)
    s = tostring(s or "")
    if s == "" then return nil end
    if s:find("%l") then return s end
    return (s:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
  end

  local STATUS = { [1] = "sum.status.psn", [2] = "sum.status.par", [3] = "sum.status.slp", [4] = "sum.status.frz",
                   [5] = "sum.status.brn", [7] = "sum.status.fnt" }

  -- a card's words and numbers (an action, never a draw)
  function Pt.card(mon, Tw)
    Tw = Tw or T
    local p = P()
    local egg = p and call(p.isEgg, mon) == true or (mon and mon.isEgg == true)
    local c = { mon = mon, egg = egg }
    c.sp = p and tonumber(call(p.speciesOf, mon)) or tonumber(mon and (mon.species or mon.speciesId)) or 0
    c.name = tostring(p and call(p.displayMonName, mon) or (mon and mon.nickname) or "?")
    c.level = tonumber(mon and mon.level) or 1
    c.levelText = egg and "" or (Tw and Tw.f and Tw.f("boxes.level", c.level) or ("Lv. " .. c.level))
    c.maxHp = max(1, tonumber(mon and (mon.maxHp or mon.maxhp)) or 1)
    if not egg then
      c.shiny = p and call(p.isShiny, mon) == true or false
      -- (Galar Rising's G-Max Factor: its mark under the picture)
      c.gmax = deps.gmax and call(deps.gmax, mon) == true or false
      local SD = engine("src.core.game3.summary_data")
      local g = SD and call(SD.gender, mon)
      c.gender = (g == "M" or g == "F") and g or nil
      local st = SD and tonumber(call(SD.statusAilment, mon)) or 0
      if (tonumber(mon.hp) or 0) <= 0 then st = 7 end
      c.status = STATUS[st] and Tw and Tw(STATUS[st]) or nil
      c.statusId = st
      local types = p and call(p.types, c.sp)
      if type(types) == "table" then c.t1, c.t2 = tonumber(types[1]), tonumber(types[2]) end
      if c.t2 == c.t1 then c.t2 = nil end
      -- (the way to the next level, the nature and the ability: the lead's card shows them)
      local prog = SD and call(SD.expProgress, mon, p and call(p.growthRate, c.sp))
      if type(prog) == "table" then
        c.expK = tonumber(prog.progressPercent) or 0
        c.expNext = (tonumber(prog.level) or 100) < 100 and tonumber(prog.expNeeded) or nil
        c.expText = c.expNext and Tw and Tw.f and Tw.f("party.toNext", c.expNext) or nil
      end
      local _, nature = call(SD and SD.nature, mon)
      c.nature = nature and titledName(nature) or nil
      local ability = tonumber(mon.ability or mon.abilityId)
      if not ability then ability = tonumber(p and call(p.abilityId, c.sp, mon.personality)) end
      local an = ability and p and call(p.abilityName, ability)
      c.ability = an and titledName(an) or nil
    end
    c.item = heldOf(mon)
    c.mail = isMail(c.item)
    if c.item then
      local I = Items()
      c.itemName = tostring(I and call(I.displayName, c.item) or "")
      c.itemTitle = titledName(c.itemName)
    end
    return c
  end

  -- ------- each Pokémon's menu

  -- (the game's field moves: FireRed / LeafGreen's twelve, Emerald's (and Ruby / Sapphire's) from its manifest)
  local FRLG_FIELD = { "FLASH", "CUT", "FLY", "STRENGTH", "SURF", "ROCK_SMASH", "WATERFALL", "TELEPORT",
                       "DIG", "MILK_DRINK", "SOFTBOILED", "SWEET_SCENT" }
  local FRLG_INDEX = {}
  for j, name in ipairs(FRLG_FIELD) do FRLG_INDEX[(name:gsub("_", " "))] = j - 1 end
  local function gameFields(s)
    local p = partyUi(s)
    if not (p and p.manifest) then return nil end
    local Kit = engine("src.ui.game3.rse.scene_kit")
    local m = Kit and call(Kit.manifest, p.manifest)
    local party = m and m.party
    if not party then return nil end
    local labels, moves = party.cursorOptions, party.fieldMoves
    if type(labels) ~= "table" or type(moves) ~= "table" then return nil end
    local base = #labels - #moves
    local index, byMove = {}, {}
    for j, move in ipairs(moves) do
      local label = labels[base + j]
      index[label] = j - 1
      byMove[move] = label
    end
    return { labels = labels, base = base, index = index, byMove = byMove, moves = moves }
  end
  local function fieldLabel(move, g)
    local FM = engine("src.core.game3.field_moves")
    if not FM then return nil end
    if type(move) == "table" then move = move.id or move.move or move.moveId or move[1] end
    if type(move) == "string" then move = move:gsub("^MOVE_", "") end
    local id = call(FM.normalizeMoveId, move)
    if not id then return nil end
    if g then return g.byMove[id] end
    local name = FM.MOVE_NAME_BY_ID and FM.MOVE_NAME_BY_ID[id]
    local label = name and (name:gsub("_", " "))
    return label and FRLG_INDEX[label] and label or nil
  end
  -- a field move's label -> its move's name, as the summary shows it
  local function fieldText(label, g)
    local FM, p = engine("src.core.game3.field_moves"), P()
    local id
    if g and g.index[label] then id = g.moves[g.index[label] + 1] end
    if not id and FM and FM.MOVES then id = FM.MOVES[(tostring(label):gsub(" ", "_"))] end
    local nm = id and p and call(p.moveName, id)
    return nm and tostring(nm) or tostring(label)
  end
  Pt.fieldText = fieldText

  local ACT_WORD = { SUMMARY = "party.act.summary", SWITCH = "party.act.switch", ITEM = "party.act.item",
                     MAIL = "party.act.mail", CANCEL = "party.act.cancel", GIVE = "party.act.give",
                     TAKE = "party.act.take", READ = "party.act.read", TAKE_MAIL = "party.act.take",
                     CANCEL2 = "party.act.cancel", ITEM_CANCEL = "party.act.cancel",
                     SHIFT = "party.act.shift", ["SEND OUT"] = "party.act.sendOut", ENTER = "party.act.enter",
                     ["NO ENTRY"] = "party.act.noEntry" }
  Pt.ACT_WORD = ACT_WORD
  local function row(act, g, fm)
    local key = ACT_WORD[act]
    return { act = act, fm = fm or nil, text = key and T and T(key) or (fm and fieldText(act, g) or tostring(act)) }
  end

  local function pike(s)
    local p = partyUi(s)
    if p and p.frontierPike == false then return false end
    if not rse(s) then return false end
    local Pike = engine("src.core.game3.rse.frontier.pike")
    return Pike and call(Pike.inBattlePike, s) == true or false
  end

  -- another mod's rows through the engine's hook (as the game's party menu asks it): kept when they're
  -- the game's own actions, field moves or rows with their own onSelect; anything odd: ours as they were
  local function hooked(c, i, rows, g)
    local Runtime = engine("src.mods.Runtime")
    if not (Runtime and call(Runtime.wantsHook, "ui.party.submenu")) then return rows end
    local s = c.session
    local native = engine("src.core.game3.runtime")
    local game = (s and s.game) or (native and native._game)
    local items, allowed = {}, {}
    for k, r in ipairs(rows) do
      items[k] = { label = r.text, action = r.act }
      allowed[r.act] = true
    end
    local ok, out = pcall(Runtime.call, "ui.party.submenu", function(_, list) return list end, game, items,
      c.party[i], { battle = c.battle, overworld = game and (game.overworld or game.world) })
    if not (ok and type(out) == "table") then return rows end
    local fieldIndex = g and g.index or FRLG_INDEX
    local res = {}
    for k = 1, #out do
      local r = out[k]
      if type(r) ~= "table" then return rows end
      if r.action == nil and type(r.onSelect) == "function" then
        local label = r.label or (r.move ~= nil and fieldLabel(r.move, g)) or ""
        res[k] = { act = "HOOK", text = tostring(label), onSelect = r.onSelect }
      elseif r.move == nil and allowed[r.action] then
        local base = rows[1]
        for _, x in ipairs(rows) do if x.act == r.action then base = x break end end
        res[k] = { act = r.action, fm = base and base.fm, text = type(r.label) == "string" and r.label or base.text }
      else
        local fm = (r.move ~= nil and fieldLabel(r.move, g)) or (r.action ~= nil and fieldIndex[r.action] ~= nil and r.action)
        if not fm then return rows end
        res[k] = { act = fm, fm = true, text = type(r.label) == "string" and r.label or fieldText(fm, g) }
      end
    end
    return res
  end

  -- the menu of the i-th shown, outside a battle: SUMMARY, its field moves, SWITCH, ITEM / MAIL, CANCEL
  -- (Ruby / Sapphire: its field moves first, as the game's)
  function Pt.actions(c, i)
    local s, mon = c.session, c.party[i]
    local g = gameFields(s)
    local p = partyUi(s)
    local rows = {}
    if p and p.buildActions then
      local ok, acts, names = pcall(p.buildActions, mon, c.party, g)
      if ok and type(acts) == "table" then
        for _, a in ipairs(acts) do rows[#rows + 1] = row(a, g, type(names) == "table" and names[a] == true) end
        return hooked(c, i, rows, g)
      end
    end
    rows[1] = row("SUMMARY", g)
    local egg = mon and (mon.isEgg or (P() and call(P().isEgg, mon) == true))
    if mon and not egg and type(mon.moves) == "table" then
      local seen = {}
      local index = g and g.index or FRLG_INDEX
      for k = 1, 4 do
        local label = fieldLabel(mon.moves[k], g)
        if label and index[label] and not seen[label] then
          seen[label] = true
          rows[#rows + 1] = row(label, g, true)
        end
      end
    end
    if not pike(s) then
      if egg or c.party[2] then rows[#rows + 1] = row("SWITCH", g) end
      if not egg then rows[#rows + 1] = row(isMail(heldOf(mon)) and "MAIL" or "ITEM", g) end
    end
    rows[#rows + 1] = row("CANCEL", g)
    return hooked(c, i, rows, g)
  end

  -- a battle's: SHIFT (SEND OUT when one fainted), SUMMARY, CANCEL; an egg or a party of one, SUMMARY only
  -- a partner's Pokémon in a battle fought beside one (Emerald's Steven, the Battle Tower's partner: the battle's
  -- playerHalf, the partner's after the player's own) -> the partner's name ("" without one); nil for the player's
  -- own. (A link's multi battle never gets here: that party menu is the game's.)
  function Pt.ally(c, i)
    if not c.battle then return nil end
    local B = engine("src.core.game3.battle")
    local st = B and B._st
    local half = type(st) == "table" and tonumber(st.playerHalf) or nil
    if not half then return nil end
    local slot = tonumber(c.order and c.order[i] or i) or i
    if slot <= half then return nil end
    local p = type(st.partner) == "table" and st.partner or nil
    return p and titledName(p.name) or ""
  end

  function Pt.battleActions(c, i)
    local mon = c.party[i]
    local egg = mon and (mon.isEgg or (P() and call(P().isEgg, mon) == true))
    local rows = {}
    -- (a partner's can't be sent out by the player: SUMMARY only, as the game's "can't switch with an ally")
    if c.party[2] and not egg and not Pt.ally(c, i) then
      rows[1] = row(c.mode == "battle_faint" and "SEND OUT" or "SHIFT")
    end
    rows[#rows + 1] = row("SUMMARY")
    rows[#rows + 1] = row("CANCEL")
    return hooked(c, i, rows, nil)
  end

  -- choosing a team: ENTER (or NO ENTRY once it's in), SUMMARY, CANCEL; one that can't go, SUMMARY only
  function Pt.multiActions(c, i, order)
    local rows = {}
    if Pt.eligible(c, i) then
      local inIt = false
      for _, sl in ipairs(order or {}) do if sl == i then inIt = true end end
      rows[1] = row(inIt and "NO ENTRY" or "ENTER")
    end
    rows[#rows + 1] = row("SUMMARY")
    rows[#rows + 1] = row("CANCEL")
    return rows
  end

  function Pt.itemActions(c, kind)
    local p = partyUi(c.session)
    local list
    if p and p.submenuActions then
      local ok, got = pcall(p.submenuActions, kind)
      if ok and type(got) == "table" then list = got end
    end
    list = list or (kind == "MAIL" and { "READ", "TAKE_MAIL", "CANCEL2" } or { "GIVE", "TAKE", "CANCEL" })
    local rows = {}
    for k, a in ipairs(list) do rows[k] = row(a) end
    return rows
  end

  -- ------- the field moves (the game's checks: FieldMoves.fromMenu on what the player faces)

  local function mapFlag(def, key) return def ~= nil and (tonumber(def[key]) or 0) ~= 0 end
  local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

  -- (Teleport / Dig: where it would take them, by name)
  local function placeName(s, mapId)
    local Field = engine("src.core.game3.field")
    local game = Field and Field._game
    local def = game and game.data and game.data.maps and game.data.maps[mapId]
    if rse(s) then
      local Ms = engine("src.ui.game3.rse.mapsec")
      return tostring(Ms and call(Ms.name, def and def.regionMapSectionId) or "")
    end
    local Sections = engine("src.import.gba.map_sections_extract")
    return tostring(Sections and call(Sections.getPlaceName, mapId, def and def.regionMapSectionId) or "")
  end

  function Pt.fieldMove(c, i, act, ui)
    local FieldMoves = engine("src.core.game3.field_moves")
    local mon = c.party[i]
    local s = c.session
    if act == "SOFTBOILED" or act == "MILK DRINK" then
      local maxHp = mon and (mon.maxHp or (mon.stats and mon.stats.hp)) or 0
      local cost = floor(maxHp / 5)
      if (mon and mon.hp or 0) <= cost or cost <= 0 then
        se("SE_SELECT")
        return ui.say(box("gText_NotEnoughHp"), function() ui.back("list") end)
      end
      se("SE_SELECT")
      return ui.back("softboiled", i)
    end
    local Pl = engine("src.core.game3.player")
    local Collision, Objects, Map = engine("src.core.game3.collision"), engine("src.core.game3.objects"),
      engine("src.core.game3.map")
    local Space = engine("src.core.game3.scripting.space")
    if not (FieldMoves and Pl and Collision and Map) then return ui.back("list") end
    local d = DELTA[Pl.facing or "down"] or DELTA.down
    local fx, fy = (Pl.cellX or 0) + d[1], (Pl.cellY or 0) + d[2]
    local function grass3x3(px, py)
      if not Collision.isGrass then return false end
      local elev = Pl.elevation
      for y = py - 1, py + 1 do
        for x = px - 1, px + 1 do
          local e = Collision.elevationAt and Collision.elevationAt(x, y)
          if (elev == nil or e == elev) and Collision.isGrass(x, y) then return true end
        end
      end
      return false
    end
    local def = call(Map.currentDef)
    local beh = Collision.behavior and call(Collision.behavior, fx, fy)
    local okG, grass = pcall(grass3x3, Pl.cellX, Pl.cellY)
    local ctx = {
      party = c.party, mon = mon, store = Space and Space.store, session = s,
      facingObject = Objects and call(Objects.at, fx, fy),
      isFacingWater = Collision.isWater and call(Collision.isWater, fx, fy),
      isFacingWaterfall = call(FieldMoves.isWaterfallBehavior, beh),
      facing = Pl.facing, isSurfing = Pl.surfing == true,
      hasCuttableGrass = okG and grass == true,
      mapType = def and def.mapType, isCave = mapFlag(def, "cave"), canEscapeRope = mapFlag(def, "allowEscaping"),
      escapeWarp = s and s.escapeWarp,
    }
    local okR, res = pcall(FieldMoves.fromMenu, act, ctx)
    if not okR then
      log("the field move %s: %s", tostring(act), tostring(res))
      res = nil
    end
    se("SE_SELECT")
    if not res or not res.ok then
      return ui.say((res and res.text) or plainKey("gText_CantUseHere"), function() ui.back("list") end)
    end
    local function run()
      local Field = engine("src.core.game3.field")
      local PM = engine("src.ui.game3.party_menu")
      local back = res.action == "fly" and { party = c.party, session = s, slot = i } or nil
      ui.leave(function()
        -- (the region map's B comes back to the party, as the game's: PartyMenu.returnFromFlyMap)
        if PM then PM._flyReturn = back end
        local StartMenu = engine("src.ui.game3.start_menu")
        if StartMenu and StartMenu.isOpen and call(StartMenu.isOpen) then pcall(StartMenu.close, true) end
        if Field and Field.executeFieldMove then
          local ok, err = pcall(Field.executeFieldMove, res)
          if not ok then log("the field move failed: %s", tostring(err)) end
        end
      end)
    end
    if (res.action == "teleport" or res.action == "dig") and not rs(s) then
      local dest, key = s and s.healMap, "gText_ReturnToHealingSpot"
      if res.action == "dig" then
        dest = s and s.escapeWarp and s.escapeWarp.map
        key = rse(s) and "gText_EscapeFromHere" or "gText_EscapeFromHereAndReturnTo"
      end
      return ui.ask(box(key, { placeName(s, dest) }), function(yes)
        if yes then run() else ui.back("list") end
      end)
    end
    run()
  end

  -- Softboiled / Milk Drink: a fifth of the user's HP to another
  function Pt.softboiled(c, from, to, ui)
    local FieldMoves = engine("src.core.game3.field_moves")
    local user, target = c.party[from], c.party[to]
    local h0 = tonumber(target and target.hp) or 0
    local ok, a = pcall(FieldMoves.softboiledTransfer, user, target)
    if not (ok and a) then
      se("SE_SELECT")
      return ui.say(box("gText_WontHaveEffect"), function() ui.back("softboiled") end)
    end
    se("SE_BIKE_BELL")
    ui.hp(to, h0, tonumber(target.hp) or h0, function()
      local p = P()
      local healed = (tonumber(target.hp) or 0) - h0
      ui.say(box("gText_PkmnHPRestoredByVar2", { tostring(p and call(p.displayMonName, target) or ""), tostring(healed) }),
        function() ui.back("list") end)
    end)
  end

  -- ------- switching places, another mod's row, the game's bag to give from, the move learning's turn

  -- (two of the party trade places, the moves' overlay with them; outside a battle the quest log hears)
  function Pt.swap(c, a, b)
    local party = c.party
    if a == b or not (party[a] and party[b]) then return end
    if not c.battle then
      local p = P()
      quest(c.session, "SwitchMon1WithMon2", { tostring(call(p.displayMonName, party[a]) or ""),
        tostring(call(p.displayMonName, party[b]) or "") })
    end
    party[a], party[b] = party[b], party[a]
    local ov = c.overlay
    if type(ov) == "table" then ov[a], ov[b] = ov[b], ov[a] end
  end

  function Pt.hookRow(c, i, r)
    local s = c.session
    local native = engine("src.core.game3.runtime")
    local game = (s and s.game) or (native and native._game)
    if r.onSelect then r.onSelect(c.party[i], game) end
  end

  -- GIVE: the game's bag (src.ui.game3.bag_menu, the party's way in); its GIVE comes back through the
  -- party menu's show (src/menus.lua hands it to the window) -> true when it opened
  function Pt.openBag(c, onClose)
    local Screens = engine("src.ui.game3.screens")
    local s = c.session
    local ok, B = pcall(Screens.get, "bag", s)
    if not (ok and B and B.show) then return false end
    local okS, err = pcall(B.show, c.bag, { session = s, bag = c.bag, location = "party", onClose = onClose })
    if not okS then
      log("the bag: %s", tostring(err))
      return false
    end
    return true
  end

  function Pt.pump()
    local LearnMove = engine("src.core.game3.battle.learn_move")
    if LearnMove and LearnMove.busy and LearnMove.busy() and LearnMove.pump then LearnMove.pump() end
  end

  -- ------- held items and mail

  function Pt.take(c, i, ui)
    local p = partyUi(c.session)
    local slot = c.order and c.order[i] or i
    local f = p and p.takeItem or (IU() and IU().takeFromMon)
    local ok, _, _, text = pcall(f, c.session, c.bag, slot)
    se("SE_SELECT")
    ui.refresh()
    ui.say(ok and text or "", function() ui.back("list") end)
  end

  -- (the mail to the PC's mailbox: its first free slot after the party's six)
  local function mailToPc(s, mon)
    local Mail = engine("src.core.game3.mail")
    local pool, src = Mail.pool(s), Mail.slot(s, mon.mail)
    if not src then return false end
    for id = 6, Mail.MAIL_COUNT - 1 do
      if Mail.isEmpty(pool[id + 1]) then
        pool[id + 1] = Mail.copy(src)
        src.itemId = 0
        mon.mail, mon.item, mon.heldItem = Mail.MAIL_NONE, 0, 0
        return true
      end
    end
    return false
  end

  -- a stand-in for the game's party menu, for Ruby / Sapphire's own mail flows (they talk to it)
  local function standIn(c, i, ui)
    local o = { _session = c.session, _party = c.party, _bag = c.bag, cursor = i, mode = "action", actionCursor = 1 }
    function o.showMessage(text, cb) ui.say(text, function() if cb then cb() end ui.back("list", nil, true) end) end
    function o.showYesNo(text, cb) ui.ask(text, function(yes) if cb then cb(yes) end ui.back("list", nil, true) end) end
    return o
  end

  function Pt.takeMail(c, i, ui)
    local s, mon = c.session, c.party[i]
    local p = partyUi(s)
    se("SE_SELECT")
    if p and p.takeMail then
      local ok, err = pcall(p.takeMail, standIn(c, i, ui))
      if not ok then log("the mail: %s", tostring(err)) ui.back("list") end
      return
    end
    local function done(key)
      ui.refresh()
      ui.say(box(key), function() ui.back("list") end)
    end
    ui.ask(box("gText_SendMailToPC"), function(yes)
      if yes then
        local ok, sent = pcall(mailToPc, s, mon)
        return done((ok and sent) and "gText_MailSentToPC" or "gText_PCMailboxFull")
      end
      ui.ask(box("gText_MailMessageWillBeLost"), function(lose)
        if not lose then return ui.back("list") end
        local item = heldOf(mon)
        local B = Bag()
        if not (item and B and call(B.add, c.bag, item, 1)) then
          local IUm = IU()
          return ui.say(IUm and call(IUm.bagFullText, item) or "", function() ui.back("list") end)
        end
        local Mail = engine("src.core.game3.mail")
        pcall(Mail.takeMailFromMon, s, mon)
        done("gText_MailTakenFromPkmn")
      end)
    end)
  end

  -- read the mail it holds: the game's own reader over ours, back to the menu after
  function Pt.readMail(c, i, ui)
    local s, mon = c.session, c.party[i]
    local p = partyUi(s)
    se("SE_SELECT")
    if p and p.readMail then
      local ok, err = pcall(p.readMail, standIn(c, i, ui))
      if not ok then log("the mail: %s", tostring(err)) end
      return ui.back("list")
    end
    local Mail = engine("src.core.game3.mail")
    local record = Mail and call(Mail.get, s, mon.mail)
    local Reader = engine(rse(s) and "src.ui.game3.rse.mail" or "src.ui.game3.mail")
    if not (record and Reader) then return ui.back("list") end
    local ok, err = pcall(Reader.read, record, { session = s, onClose = function() ui.back("list") end })
    if not ok then
      log("the mail reader: %s", tostring(err))
      ui.back("list")
    end
  end

  -- an item given to the i-th to hold (`after`: once it's done, the game's caller's onClose): the game's
  -- checks (a key item, mail first, already holding one -> switch?)
  function Pt.give(c, i, item, source, ui, after)
    local s = c.session
    local slot = c.order and c.order[i] or i
    local IUm = IU()
    local kind, _, text = IUm.checkGive(s, item, slot)
    local function finish()
      ui.refresh()
      if after then after() else ui.back("list") end
    end
    if kind == "give" then
      text = IUm.giveHeld(s, c.bag, item, slot, source)
      se("SE_SELECT")
      ui.refresh()
      return ui.say(text, finish)
    end
    if kind == "switch" then
      se("SE_SELECT")
      return ui.ask(text, function(yes)
        if not yes then return finish() end
        local _, switched = IUm.switchHeld(s, c.bag, item, slot, source)
        ui.refresh()
        ui.say(switched, finish)
      end)
    end
    se("SE_SELECT")
    ui.say(text or "", finish)
  end

  -- ------- an item used on a Pokémon (the field's: a TM / HM, a Rare Candy, a stone, medicine, PP)

  local function learnOpts(c, i, ui, mon, name)
    return {
      displayName = name,
      pushMsg = function(t, cb) ui.say(t, cb) end,
      askYesNo = function(a, b)
        local cb = type(a) == "function" and a or b
        ui.ask(type(a) == "string" and a or "", function(yes) if cb then cb(yes == true) end end)
      end,
      askForget = function(a, b, cc)
        local cb = type(b) == "function" and b or cc
        local LearnMove = engine("src.core.game3.battle.learn_move")
        ui.forget(i, (LearnMove and LearnMove._moveId) or c.learning, function(slot) if cb then cb(slot) end end)
      end,
    }
  end

  local function statsOf(mon)
    return { maxHp = tonumber(mon.maxHp or mon.maxhp) or 1, atk = tonumber(mon.attack or mon.atk) or 1,
             def = tonumber(mon.defense or mon.def) or 1, spa = tonumber(mon.spAtk or mon.spa) or 1,
             spd = tonumber(mon.spDef or mon.spd) or 1, spe = tonumber(mon.speed or mon.spe) or 1 }
  end

  -- (after an item: another go while there's more of it, else the menu closes)
  local function more(c, ui)
    local B = Bag()
    if B and call(B.has, c.bag, c.item, 1) then ui.back("use") else ui.close() end
  end

  local function evolve(c, i, ui, mon, to, opts, after)
    local Scene, Audio = engine("src.ui.game3.evolution_scene"), engine("src.core.game3.audio")
    if not Scene then return after() end
    opts.session, opts.bag, opts.savedSong = c.session, c.bag, Audio and Audio._mapSong
    opts.onDone = function()
      ui.refresh()
      after()
    end
    local ok, err = pcall(Scene.start, mon, to, opts)
    if not ok then
      log("the evolution: %s", tostring(err))
      after()
    end
  end

  local function tm(c, i, ui, mon)
    local IUm, p, I = IU(), P(), Items()
    local status, msg, moveId, moveName = IUm.checkTmPreflight(mon, c.item)
    se("SE_SELECT")
    if status ~= "ok" then return ui.say(msg or "", function() ui.back("use") end) end
    local hm = call(I.isHm, c.item) == true
    local name = tostring(call(p.displayMonName, mon) or "")
    local function learned()
      call(p.adjustFriendship, mon, p.FRIENDSHIP_EVENT_LEARN_TMHM, { mapSec = call(p.currentMapSec, c.session) })
      quest(c.session, hm and "MonLearnedMoveFromHM" or "MonLearnedMoveFromTM", { name, moveName })
      if not hm then call(Bag().remove, c.bag, c.item, 1) end
      fanfare("MUS_LEVEL_UP")
      ui.refresh()
    end
    if (tonumber(call(p.moveSlotCount, mon)) or 4) < 4 then
      if call(p.teachMove, mon, moveId) then
        learned()
        return ui.say(box("gText_PkmnLearnedMove3", { name, moveName }), function() ui.close() end)
      end
      return ui.back("use")
    end
    local LearnMove = engine("src.core.game3.battle.learn_move")
    c.learning = moveId
    local o = learnOpts(c, i, ui, mon, name)
    o.mon, o.moveId = mon, moveId
    o.onDone = function(ok)
      if ok then
        learned()
        ui.close()
      else
        ui.back("use")
      end
    end
    local ok, err = pcall(LearnMove.begin, o)
    if not ok then
      log("learning a move: %s", tostring(err))
      ui.back("use")
    end
  end

  local function rareCandy(c, i, ui, mon)
    local IUm, p, I = IU(), P(), Items()
    local enigma = (num(c.item) == 175) and call(engine("src.core.game3.rs.enigma").matches, c.session) == true
    local lvl, hp = tonumber(mon.level) or 1, tonumber(mon.hp) or 0
    if lvl >= 100 or (hp <= 0 and not enigma) then
      se("SE_SELECT")
      return ui.say(box("gText_WontHaveEffect"), function() ui.back("use") end)
    end
    se("SE_USE_ITEM")
    local old = statsOf(mon)
    if enigma and not call(IUm.applyEnigmaItem, c.session, mon, 1, { bag = c.bag, emitLevel = false }) then
      return ui.say(box("gText_WontHaveEffect"), function() ui.back("use") end)
    end
    call(Bag().remove, c.bag, c.item, 1)
    quest(c.session, "UsedItemOnMonAtThisLocation", { tostring(call(I.displayName, c.item) or ""),
      tostring(call(p.displayMonName, mon) or "") })
    if not enigma then
      mon.level = lvl + 1
      call(p.applyStats, mon)
    end
    local new = statsOf(mon)
    local newHp = min(new.maxHp, hp + max(0, new.maxHp - old.maxHp))
    if not enigma then mon.hp = newHp end
    call(IUm.levelUpEvent, mon, mon.level)
    fanfare("MUS_LEVEL_UP")
    local name = tostring(call(p.displayMonName, mon) or "")
    ui.refresh()
    local function checkEvolution()
      local Evolution = engine("src.core.game3.evolution")
      local to = Evolution and call(Evolution.levelTarget, mon, c.session)
      local blocked = false
      if not to and Evolution then
        local raw = call(Evolution.targetSpecies, mon, Evolution.EVO_MODE_NORMAL)
        if raw and raw ~= 0 and not call(Evolution.nationalAllows, raw, c.session) then to, blocked = raw, true end
      end
      if to then
        return evolve(c, i, ui, mon, to, { canStop = true, autoCancel = blocked }, function() ui.back("list") end)
      end
      more(c, ui)
    end
    local function afterLevel()
      local sp = tonumber(call(p.speciesOf, mon)) or tonumber(mon.species)
      local moves = call(p.movesLearnedAt, sp, mon.level) or {}
      if #moves > 0 then
        local LearnMove = engine("src.core.game3.battle.learn_move")
        local o = learnOpts(c, i, ui, mon, name)
        o.onDone = function() checkEvolution() end
        local ok, started = pcall(LearnMove.beginQueue, mon, { mon.level }, o)
        if not (ok and started) then checkEvolution() end
      else
        checkEvolution()
      end
    end
    local lvlMsg = plainKey("gText_PkmnElevatedToLvVar2", { stringVars = { name, tostring(mon.level) } })
    ui.hp(i, hp, newHp, function()
      ui.say(lvlMsg, function() ui.stats(mon, old, new, afterLevel) end)
    end)
  end

  local function stone(c, i, ui, mon)
    local Evolution = engine("src.core.game3.evolution")
    local to = Evolution and call(Evolution.itemTarget, mon, c.item, c.session)
    if not to then
      se("SE_SELECT")
      return ui.say(box("gText_WontHaveEffect"), function() ui.back("use") end)
    end
    call(Bag().remove, c.bag, c.item, 1)
    evolve(c, i, ui, mon, to, { canStop = false }, function() more(c, ui) end)
  end

  local function medicine(c, i, ui, mon, moveSlot)
    local IUm = IU()
    local h0 = tonumber(mon.hp) or 0
    local slot = c.order and c.order[i] or i
    local ok, _, text = IUm.useField(c.session, c.bag, c.item, slot, moveSlot)
    local h1 = tonumber(mon.hp) or h0
    if not ok then
      se("SE_SELECT")
      return ui.say(text or box("gText_WontHaveEffect"), function() ui.back("use") end)
    end
    se(call(IUm.isFlute, c.item) and 110 or 1)
    ui.refresh()
    local function said() ui.say(text or "", function() more(c, ui) end) end
    if h1 > h0 then ui.hp(i, h0, h1, said) else said() end
  end

  -- the item (c.item) used on the i-th shown
  function Pt.use(c, i, ui)
    local mon = c.party[i]
    if not mon then return end
    local I, IUm = Items(), IU()
    if call(I.isTm, c.item) then return tm(c, i, ui, mon) end
    if call(IUm.fieldUseKind, c.item, c.session) == "level" then return rareCandy(c, i, ui, mon) end
    local PM = engine("src.ui.game3.party_menu")
    if PM and call(PM.itemIsEvolutionStone, c.item) then return stone(c, i, ui, mon) end
    if call(IUm.fieldUseKind, c.item, c.session) == "pp" and call(IUm.ppItemNeedsMove, c.item) then
      se("SE_SELECT")
      local p = P()
      local names, slots = {}, {}
      for k = 1, 4 do
        local id = call(p.moveIdAt, mon, k)
        if id and id > 0 then
          names[#names + 1] = tostring(call(p.moveName, id) or "")
          slots[#slots + 1] = k
        end
      end
      local prompt = call(IUm.ppItemBoosts, c.item) and plainKey("gText_BoostPp") or plainKey("gText_RestoreWhichMove")
      return ui.pick(prompt, names, function(k)
        if k == nil then return ui.back("use") end
        medicine(c, i, ui, mon, slots[k + 1])
      end)
    end
    medicine(c, i, ui, mon, nil)
  end

  -- ------- choosing for something (the Day Care, a contest, a trade, the Frontier) and the Move Tutor

  -- (may it go in? the caller's rule: a function (slot, mon), a list of 0-based slots, else able to battle)
  function Pt.eligible(c, i)
    local mon = c.party[i]
    if not mon or mon.isEgg or (P() and call(P().isEgg, mon) == true) then return false end
    local rule = c.eligible
    if type(rule) == "function" then
      local ok, yes = pcall(rule, i, mon)
      return ok and yes and true or false
    elseif type(rule) == "table" then
      for _, sl in ipairs(rule) do if (tonumber(sl) or -1) + 1 == i then return true end end
      return false
    end
    return (tonumber(mon.hp) or 0) > 0
  end

  -- the words when no more may go in (the caller's, else the game's "no more than two / three")
  function Pt.fullText(c, max)
    if c.chooseFullMessage then return c.chooseFullMessage end
    if rse(c.session) then return box("gText_NoMoreThanVar1Pkmn", { tostring(max) }) end
    return box(max == 2 and "gText_NoMoreThanTwoMayEnter" or "gText_NoMoreThanThreeMayEnter")
  end
  function Pt.noneText() return plainKey("gText_NoPokemonForBattle") end
  function Pt.cancelText() return plainKey("gText_CancelBattle") end

  -- the move the tutor teaches, and its name
  function Pt.tutorMove(c)
    local ML = engine("src.core.game3.move_learn")
    local id = ML and tonumber(c.tutor) and call(ML.tutorMove, tonumber(c.tutor))
    local p = P()
    return id, id and tostring(call(p.moveName, id) or "") or ""
  end

  -- the tutor's move taught to the i-th (the game's TryTutorSelectedMon): its words, learning (a move to
  -- forget through the summary), the result kept for the script (c.tutorResult)
  function Pt.tutor(c, i, ui)
    local mon = c.party[i]
    local ML = engine("src.core.game3.move_learn")
    local p = P()
    local moveId, moveName = Pt.tutorMove(c)
    if not (mon and moveId and ML) then return ui.close() end
    local name = tostring(call(p.displayMonName, mon) or "")
    local status = call(ML.canMonLearnTutorMove, mon, tonumber(c.tutor))
    if status == ML.CANNOT_LEARN_MOVE or status == ML.CANNOT_LEARN_MOVE_IS_EGG then
      return ui.say(box("gText_PkmnCantLearnMove", { name, moveName }), function() ui.close() end)
    end
    if status == ML.ALREADY_KNOWS_MOVE then
      return ui.say(box("gText_PkmnAlreadyKnows", { name, moveName }), function() ui.close() end)
    end
    if (tonumber(call(p.moveSlotCount, mon)) or 4) < 4 then
      if call(p.teachMove, mon, moveId) then
        fanfare("MUS_LEVEL_UP")
        ui.refresh()
        return ui.say(box("gText_PkmnLearnedMove3", { name, moveName }), function()
          c.tutorResult = true
          ui.close()
        end)
      end
      return ui.close()
    end
    local LearnMove = engine("src.core.game3.battle.learn_move")
    c.learning = moveId
    local o = learnOpts(c, i, ui, mon, name)
    o.mon, o.moveId = mon, moveId
    o.onDone = function(learned)
      if learned then c.tutorResult = true end
      ui.refresh()
      ui.close()
    end
    local ok, err = pcall(LearnMove.begin, o)
    if not ok then
      log("the tutor: %s", tostring(err))
      ui.close()
    end
  end

  -- what each card says while choosing for the tutor
  function Pt.tutorTag(c, mon)
    local ML = engine("src.core.game3.move_learn")
    if not (ML and mon and c.tutor) then return nil end
    local status = call(ML.canMonLearnTutorMove, mon, tonumber(c.tutor))
    if status == ML.ALREADY_KNOWS_MOVE then return "party.learned" end
    if status == ML.CAN_LEARN_MOVE then return "party.able" end
    return "party.notAble"
  end

  -- what each card says while an item's being used: a TM's (able / not able / learned), a stone's
  function Pt.tag(c, mon)
    if not (c.item and mon) or mon.isEgg then return nil end
    local I, IUm = Items(), IU()
    if call(I.isTm, c.item) then
      local status = IUm and call(IUm.checkTmPreflight, mon, c.item)
      if status == "ok" then return "party.able" end
      if status == "knows" then return "party.learned" end
      return "party.notAble"
    end
    local PM = engine("src.ui.game3.party_menu")
    if PM and call(PM.itemIsEvolutionStone, c.item) then
      local Evolution = engine("src.core.game3.evolution")
      return (Evolution and call(Evolution.itemTarget, mon, c.item, c.session)) and "party.able" or "party.notAble"
    end
    return nil
  end

  return Pt
end
