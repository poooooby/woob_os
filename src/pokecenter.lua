-- The Pokémon Center on FireRed / LeafGreen / Ruby / Sapphire / Emerald: the nurse's counter opens our
-- Pokémon Center full screen (src/apps/pokecenter.lua, Sh.openFull) in place of her script's words, its
-- YES / NO and the healing machine on the field.
--
-- The catch (script.command): every nurse `call`s one shared script (Emerald / Ruby / Sapphire's
-- Common_EventScript_PkmnCenterNurse; FireRed / LeafGreen's has no label) whose flow reaches the healing
-- machine (`dofieldeffect 25`, FLDEFF_POKECENTER_HEAL: one list in each game). The `call` runs as the
-- game's; the first command inside it after its `lock` / `faceplayer` is where ours opens: the VM is
-- taken straight back out of it (its own `return`) and held (Natives.yieldHost) until ours closes, so
-- the nurse's own `release` comes after, as it would; Emerald / Ruby / Sapphire's `waitmessage` /
-- `waitbuttonpress` after the call (her last words' box) are skipped.
--
-- What her script does besides talking is done here with the game's own pieces: the heal (special 0,
-- HealPlayerParty, through the VM's adapters as the special has it), the "used a Pokémon Center" game
-- stat (15), FireRed / LeafGreen's quest log (special 361), Ruby / Sapphire / Emerald's Pokérus (her
-- words about it once: FLAG_POKERUS_EXPLAINED, 273), Emerald's Gold Card (four trainer stars: her
-- words the first time, FLAG_NURSE_MENTIONS_GOLD_CARD 345, "the usual" after); the machine's sounds
-- (SE_BALL a ball, the heal fanfare). With the option off, or ours not opening: her own script.
--
--   Pc = pokecenter(engine, deps)   deps: Sh (the shell: openFull) ; on() -> the option ; log(fmt, ...)
--   Pc.command(nxt, ctx, op, row, ...) (the script.command wrap) ; Pc.isNurse(vm, key) ;
--   Pc.make(vm, s) -> the window's model (ctx.nurse) ; Pc.take(vm, ctx, nxt) -> true when ours opened

local FLDEFF_POKECENTER_HEAL, GAME_STAT_USED_POKECENTER = 25, 15
local SPECIAL_HEAL, SPECIAL_QUEST_LOG = 0, 361
local FLAG_POKERUS_EXPLAINED, FLAG_NURSE_MENTIONS_GOLD_CARD = 273, 345
local RETURN = { op = "return" }

return function(engine, deps)
  local Pc = {}
  local function log(fmt, ...) if deps.log then deps.log(fmt, ...) end end
  local function session() local R = engine("src.core.game3.runtime"); return R and R.getSession and R.getSession() end
  local function profile(s)
    local Profile = engine("src.core.game3.profile")
    local ok, P = pcall(Profile and Profile.forSession or error, s)
    if not (ok and type(P) == "table") then return "frlg", "" end
    return P.family or "frlg", tostring(P.id or "")
  end

  -- ------- which `call` is the nurse's: its flow reaches the healing machine (not the machine's own list)
  local known = setmetatable({}, { __mode = "k" })     -- the game's script table -> { key -> bool }
  local function heals(list)
    for _, r in ipairs(list) do
      if r.op == "dofieldeffect" and tonumber(r[1]) == FLDEFF_POKECENTER_HEAL then return true end
    end
    return false
  end
  -- (breadth first, a few jumps deep: the nearest way to the machine counts)
  local function reaches(scripts, key)
    local seen, level = { [key] = true }, { key }
    for _ = 0, 4 do
      local nextLevel = {}
      for _, k in ipairs(level) do
        local list = scripts[k]
        if type(list) == "table" then
          if heals(list) then return true end
          for _, r in ipairs(list) do
            local op, to = r.op, nil
            if op == "goto" or op == "call" then to = r.target or r[1]
            elseif op == "goto_if" or op == "call_if" then to = r.target or r[2] end
            if type(to) == "string" and not seen[to] then
              seen[to] = true
              nextLevel[#nextLevel + 1] = to
            end
          end
        end
      end
      if #nextLevel == 0 then return false end
      level = nextLevel
    end
    return false
  end
  function Pc.isNurse(vm, key)
    local scripts = vm and vm.scripts
    if type(scripts) ~= "table" or type(key) ~= "string" then return false end
    local byKey = known[scripts]
    if not byKey then
      byKey = {}
      known[scripts] = byKey
    end
    local v = byKey[key]
    if v == nil then
      local list = scripts[key]
      v = type(list) == "table" and not heals(list) and reaches(scripts, key) or false
      byKey[key] = v
    end
    return v
  end

  -- ------- the model: the team as it came in, her greeting, the heal and its side effects, the sounds
  local function nice(name)
    name = tostring(name or "")
    if name:find("%l") then return name end
    return (name:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
  end
  local function timeOfDay()
    local ok, d = pcall(os.date, "*t")
    local h = ok and type(d) == "table" and d.hour or 12
    if h >= 4 and h < 10 then return "morning" end
    if h >= 10 and h < 18 then return "day" end
    return "night"
  end

  function Pc.make(vm, s)
    s = s or session()
    local family, game = profile(s)
    local Pk = engine("src.core.game3.pokemon")
    local Flags = engine("src.core.game3.scripting.flags")
    local store = vm and vm.store
    local function flag(id)
      local ok, on = pcall(Flags.getFlag, store, vm and vm.ctx, id)
      return ok and on == true
    end
    local function setFlag(id) pcall(Flags.setFlag, store, vm and vm.ctx, id, true) end
    local party = (s and s.party) or {}
    local team, lead = {}, nil
    for i, mon in ipairs(party) do
      local okE, egg = pcall(Pk.isEgg, mon)
      egg = okE and egg == true
      local name = nil
      if not egg then
        local okN, n = pcall(Pk.displayMonName, mon)
        name = nice(okN and n or mon.nickname or "?")
      end
      team[i] = { mon = mon, egg = egg, name = name, hp = tonumber(mon.hp) or 0, max = tonumber(mon.maxHp) or 0 }
      lead = lead or name
    end
    local m = { team = team, lead = lead, time = timeOfDay(), gen = 3 }
    -- (Emerald's Gold Card: four stars on the trainer card)
    if game == "emerald" then
      local FieldRse = engine("src.core.game3.scripting.natives_field_rse")
      local okS, stars = pcall(FieldRse and FieldRse.countTrainerStars or error, s)
      if okS and (tonumber(stars) or 0) >= 4 then
        if flag(FLAG_NURSE_MENTIONS_GOLD_CARD) then
          m.greet = "usual"
        else
          m.greet = "gold"
          setFlag(FLAG_NURSE_MENTIONS_GOLD_CARD)
        end
      end
    end
    function m.heal()
      local Natives = engine("src.core.game3.scripting.natives")
      local adapters = vm and vm.adapters
      local ok, err = pcall(Natives.special, {}, SPECIAL_HEAL, adapters)
      if not ok then log("the heal failed: %s", tostring(err)) end
      if s then
        s.gameStats = s.gameStats or {}
        local cur = tonumber(s.gameStats[GAME_STAT_USED_POKECENTER]) or 0
        s.gameStats[GAME_STAT_USED_POKECENTER] = math.min(0xFFFFFF, cur + 1)
      end
      if family == "frlg" then pcall(Natives.special, {}, SPECIAL_QUEST_LOG, adapters) end
      if family == "rse" and not flag(FLAG_POKERUS_EXPLAINED) then
        local okP, got = pcall(Pk.checkPartyPokerus, party, 0x3F)
        if okP and (tonumber(got) or 0) ~= 0 then
          setFlag(FLAG_POKERUS_EXPLAINED)
          return true
        end
      end
      return false
    end
    local function audio() return engine("src.core.game3.audio") end
    function m.ball()
      local Audio, SE = audio(), engine("src.core.game3.se_ids")
      if Audio and Audio.playSe and SE and SE.SE_BALL then pcall(Audio.playSe, SE.SE_BALL) end
    end
    function m.jingle()
      local Audio = audio()
      if not (Audio and Audio.playFanfare) then return end
      local okR, id = pcall(Audio.role or error, "heal")
      pcall(Audio.playFanfare, okR and id or 256)
    end
    function m.jingleDone()
      local Audio = audio()
      if Audio and Audio.isFanfareFinished then
        local ok, done = pcall(Audio.isFanfareFinished)
        return not ok or done == true
      end
      return true
    end
    return m
  end

  -- ------- the takeover: back out of her script, held until ours closes
  local hold = setmetatable({}, { __mode = "k" })     -- the VM -> { key } (inside her call) | { tail }
  function Pc.take(vm, ctx, nxt)
    local Sh = deps.Sh
    if not (Sh and Sh.openFull) then return false end
    local s = session()
    local okM, model = pcall(Pc.make, vm, s)
    if not (okM and model) then
      log("the Pokémon Center couldn't be made: %s", tostring(model))
      return false
    end
    local release, closedEarly = nil, false
    local opened = Sh.openFull("pokecenter", s, function()
      if release then release() else closedEarly = true end
    end, nil, { nurse = model, chrome = false, noHints = true })
    if opened ~= true then return false end
    nxt(ctx, "return", RETURN)
    hold[vm] = { tail = true }
    local Natives = engine("src.core.game3.scripting.natives")
    Natives.yieldHost(vm.ctx, vm.adapters, function(done)
      if closedEarly then done() else release = done end
    end)
    return true
  end

  function Pc.command(nxt, ctx, op, row, ...)
    local vm = type(ctx) == "table" and (ctx.runner or ctx.vm) or nil
    if not vm then return nxt(ctx, op, row, ...) end
    local h = hold[vm]
    if h then
      if h.tail then
        -- (her last words' box, which ours said: skipped; anything else and the script's its own again)
        if op == "waitmessage" or op == "waitbuttonpress" then return false end
        hold[vm] = nil
      else
        local pc = vm.ctx and vm.ctx.pc
        if pc and pc.listKey == h.key then
          if op == "lock" or op == "lockall" or op == "faceplayer" then return nxt(ctx, op, row, ...) end
          hold[vm] = nil
          local ok, took = pcall(Pc.take, vm, ctx, nxt)
          if ok and took then return true end
          if not ok then log("the Pokémon Center failed to open: %s", tostring(took)) end
          return nxt(ctx, op, row, ...)
        end
        hold[vm] = nil
      end
    end
    if op == "call" and (not deps.on or deps.on()) then
      local key = row and (row.target or row[1])
      if Pc.isNurse(vm, key) then hold[vm] = { key = key } end
    end
    return nxt(ctx, op, row, ...)
  end

  return Pc
end
