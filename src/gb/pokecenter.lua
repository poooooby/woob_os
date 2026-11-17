-- The Pokémon Center on the Game Boy games: the nurse's counter opens our Pokémon Center full screen
-- (src/apps/pokecenter.lua through Sh.openFull, as on Gen 3), with what the game's own nurse does
-- besides talking done with the game's own pieces.
--   Red / Blue / Yellow: the nurse is OverworldState:nurseHeal(onDone, npc) (no script), wrapped once per
--     process (OverworldState.__woobOsNurse; this instance's impl swapped in). Ours heals as its machine
--     does (Pokemon.heal each one, the map music stopped for the jingle), sets the blackout point
--     (save.lastHeal, SetLastBlackoutMap) and "used a Pokémon Center" (save.usedPokecenter); the machine
--     plays Healing_Machine for each ball and Music_PkmnHealed; onDone() when ours closes (the field
--     goes on). Yellow's Pewter scene (Pikachu and the sleeping Jigglypuff) stays the game's.
--   Gold / Silver / Crystal: every nurse's script is `jumpstd PokecenterNurseScript`; that command is
--     caught (script.command) and not run: the VM waits (Specials.block) while ours is open, then the
--     map's script ends as hers would. What her script does, ours does through the VM: the time of
--     day's greeting (getTimeOfDayFn), Crystal's Pokécom Center welcome (event 810: checked, cleared),
--     HealParty, the jingle (Music_HealPokemon) and RestartMapMusic when it couldn't play, the Pokérus
--     talk when there's no call waiting and it hasn't been had (checkphonecall, flag 13, CheckPokerus),
--     then flag 13 and Prof. Elm's call (specialphonecall), as hers.
-- With the option off, or ours not opening: the game's own nurse.
--
--   Pc = pokecenter(H, Gd, deps)   deps: Sh (the shell) ; on() -> the option ; hooks (mod.hooks) ; log
--   Pc.install() (game.ready) ; Pc.make1(ow, npc) / Pc.make2(vm) -> the window's model (the tests') ;
--   Pc.open1(ow, onDone, npc) -> true when ours opened ; Pc.command(nxt, ctx, op, args, cmd, ...)

local STD = "PokecenterNurseScript"
-- (her script's own rows, run through the VM as hers would)
local CHECK_POKECOM, CLEAR_POKECOM = { op = "checkevent", event = 810 }, { op = "clearevent", event = 810 }
local CHECK_CALL = { op = "checkphonecall" }
local CHECK_POKERUS, SET_POKERUS = { op = "checkflag", flag = 13 }, { op = "setflag", flag = 13 }
local ELM_CALL = { op = "specialphonecall", args = { 1, 0 } }

return function(H, Gd, deps)
  local engine, gen = H.engine, H.gen
  local Pc = {}
  local function log(fmt, ...) if deps.log then deps.log(fmt, ...) end end
  local function on() return not deps.on or deps.on() end
  local function nice(name)
    name = tostring(name or "")
    if name:find("%l") then return name end
    return (name:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
  end
  local function deviceTime()
    local ok, d = pcall(os.date, "*t")
    local h = ok and type(d) == "table" and d.hour or 12
    if h >= 4 and h < 10 then return "morning" end
    if h >= 10 and h < 18 then return "day" end
    return "night"
  end
  local function music() return engine("src.core.Music") end
  local function open(model, onClose)
    local Sh = deps.Sh
    if not (Sh and Sh.openFull) then return false end
    return Sh.openFull("pokecenter", H.session(), onClose, nil,
      { nurse = model, chrome = false, noHints = true }) == true
  end

  -- ------- Red / Blue / Yellow
  function Pc.make1(ow, npc)
    local game = H.game()
    local save = game and game.save or {}
    local Pokemon = engine("src.pokemon.Pokemon")
    local team, lead = {}, nil
    for i, mon in ipairs(save.party or {}) do
      local name = nice(Gd.monName(mon))
      local max = tonumber(mon.stats and mon.stats.hp) or tonumber(mon.maxHp) or 0
      team[i] = { mon = mon, egg = false, name = name, hp = tonumber(mon.hp) or 0, max = max }
      lead = lead or name
    end
    local GV, Follower = engine("src.core.GameVersion"), engine("src.world.PikachuFollower")
    local okY, yellow = pcall(GV and GV.isYellow or error)
    local okF, pika = pcall(Follower and Follower.current or error, ow)
    local m = { team = team, lead = lead, time = deviceTime(), gen = 1,
                pikachu = okY and yellow == true and okF and pika ~= nil }
    save.usedPokecenter = true
    function m.heal()
      local Music = music()
      if Music and Music.stop then pcall(Music.stop) end
      for _, mon in ipairs(save.party or {}) do pcall(Pokemon.heal, mon) end
      -- (SetLastBlackoutMap: this Pokémon Center, and the town's door for the way out)
      local out = ow and ow.lastOutdoor
      save.lastHeal = { map = ow and ow.map and ow.map.id, x = ow and ow.player and ow.player.cellX,
                        y = ow and ow.player and ow.player.cellY,
                        outdoor = out and { id = out.id, x = out.x, y = out.y } or nil }
      return false
    end
    function m.ball()
      local Sound = engine("src.core.Sound")
      if Sound and Sound.play and game then pcall(Sound.play, game.data, "Healing_Machine") end
    end
    function m.jingle()
      local Music = music()
      local ok, played = pcall(Music and Music.playOnce or error, game and game.data, "Music_PkmnHealed")
      m.played = ok and played == true
    end
    function m.jingleDone()
      local Music = music()
      if not (m.played and Music and Music.oneShotPlaying) then return true end
      local ok, playing = pcall(Music.oneShotPlaying)
      return not ok or playing ~= true
    end
    function m.after()
      if m.played then return end
      local Music = music()
      if Music and Music.restoreMap and game then pcall(Music.restoreMap, game.data, "pokecenter") end
    end
    return m
  end

  function Pc.open1(ow, onDone, npc)
    if not on() then return false end
    if ow and ow.map and ow.map.id == "PEWTER_POKECENTER" and ow.pikachuPewterSleepScene then return false end
    local okM, model = pcall(Pc.make1, ow, npc)
    if not (okM and model) then
      log("the Pokémon Center couldn't be made: %s", tostring(model))
      return false
    end
    return open(model, function()
      if npc and npc.facePlayer and ow and ow.player then pcall(npc.facePlayer, npc, ow.player) end
      if onDone then onDone() end
    end)
  end

  local function wrapNurse()
    local OW = engine("src.world.OverworldController")
    if not (OW and type(OW.nurseHeal) == "function") then return false end
    local w = rawget(OW, "__woobOsNurse")
    if not w then
      w = { orig = OW.nurseHeal }
      OW.__woobOsNurse = w
      OW.nurseHeal = function(self, onDone, npc)
        local impl = w.impl
        if impl then
          local ok, opened = pcall(impl, self, onDone, npc)
          if ok and opened then return end
          if not ok and w.log then w.log("the Pokémon Center failed to open: %s", tostring(opened)) end
        end
        return w.orig(self, onDone, npc)
      end
    end
    w.impl, w.log = Pc.open1, log
    return true
  end

  -- ------- Gold / Silver / Crystal
  local function truthy(v) return v ~= nil and v ~= false and v ~= 0 end
  local function special(vm, name)
    local Specials = engine("src.script.gen2.Specials")
    local f = Specials and Specials.ALL and Specials.ALL[name]
    if type(f) ~= "function" then return false end
    local ok, err = pcall(f, vm)
    if not ok then log("%s failed: %s", name, tostring(err)) end
    return ok
  end

  function Pc.make2(vm)
    local game = H.game()
    local save = game and game.save or {}
    local Breeding = engine("src.core.gen2.Breeding")
    local team, lead = {}, nil
    for i, mon in ipairs(save.party or {}) do
      local okE, egg = pcall(Breeding and Breeding.isEgg or error, mon)
      egg = okE and egg == true or mon.isEgg == true
      local name = not egg and nice(Gd.monName(mon)) or nil
      team[i] = { mon = mon, egg = egg, name = name, hp = tonumber(mon.hp) or 0, max = tonumber(mon.maxHp) or 0 }
      lead = lead or name
    end
    local time = "day"
    local okT, t = pcall(vm and vm.getTimeOfDayFn or error)
    if okT then time = t == 0 and "morning" or (t == 1 and "day" or "night") end
    local m = { team = team, lead = lead, time = time, gen = 2 }
    function m.heal()
      special(vm, "HealParty")
      m.healed = true
      return m.virus == true
    end
    function m.ball() H.sfx("Sfx_SecondPartOfItemfinder") end
    function m.jingle()
      local Music = music()
      local ok, played = pcall(Music and Music.playOnce or error, game and game.data, "Music_HealPokemon")
      m.played = ok and played == true
    end
    function m.jingleDone()
      local Music = music()
      if not (m.played and Music and Music.oneShotPlaying) then return true end
      local ok, playing = pcall(Music.oneShotPlaying)
      return not ok or playing ~= true
    end
    function m.after()
      if not m.played then special(vm, "RestartMapMusic") end
    end
    return m
  end

  -- (her script, held: ours open, the VM waiting on it; nil when ours didn't open, so hers runs)
  function Pc.take2(vm, ctx, nxt)
    local function run(row) return nxt(ctx, row.op, row.args, row) end
    local crystal = H.gameId() == "crystal"
    local pokecom = false
    if crystal then
      run(CHECK_POKECOM)
      pokecom = truthy(vm.scriptVar)
    end
    local model = Pc.make2(vm)
    if pokecom then model.greet = "pokecom" end
    -- (her Pokérus talk: no call waiting, never had, one in the party now)
    run(CHECK_CALL)
    local waiting = truthy(vm.scriptVar)
    run(CHECK_POKERUS)
    local had = truthy(vm.scriptVar)
    if not waiting and not had and special(vm, "CheckPokerus") then model.virus = truthy(vm.scriptVar) end
    local Specials = engine("src.script.gen2.Specials")
    local opened = false
    Specials.block(vm, function(done)
      opened = open(model, function() done(true) end)
      if not opened then done(false) end
    end)
    if not opened then return false end
    if crystal then run(CLEAR_POKECOM) end
    if model.healed and model.virus then
      run(SET_POKERUS)
      run(ELM_CALL)
    end
    return true
  end

  function Pc.command(nxt, ctx, op, args, cmd, ...)
    if op ~= "jumpstd" or type(cmd) ~= "table" or cmd.std ~= STD or not on() then
      return nxt(ctx, op, args, cmd, ...)
    end
    local vm = type(ctx) == "table" and ctx.vm or nil
    if not vm then return nxt(ctx, op, args, cmd, ...) end
    local ok, took = pcall(Pc.take2, vm, ctx, nxt)
    if ok and took then return nil end
    if not ok then log("the Pokémon Center failed to open: %s", tostring(took)) end
    return nxt(ctx, op, args, cmd, ...)
  end

  function Pc.install()
    if gen == 1 then return wrapNurse() end
    if deps.hooks and not Pc.hooked then
      Pc.hooked = true
      deps.hooks:wrap("script.command", function(nxt, ctx, op, args, cmd, ...)
        return Pc.command(nxt, ctx, op, args, cmd, ...)
      end)
    end
    return true
  end

  return Pc
end
