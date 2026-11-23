-- The moments we stage ourselves on the Game Boy games (src/scenes.lua's for Red / Blue / Yellow and Gold / Silver /
-- Crystal: the same windows, src/apps/evolution.lua and src/apps/caught.lua, over models made here from the games'
-- own pieces), each under Modern Menus with a switch of its own:
--   "evolution"  Gen 1: src.pokemon.Evolution's evolve(game, mon, newSpecies, onDone, via, batch) wrapped (every
--                caller goes through it: a battle's level up, a stone, a Rare Candy, a trade); the change is the
--                game's Evolution.apply, its moves after are the game's (a full set: its MoveLearnMenu). Gen 2: the
--                "Gen2EvolutionAnim" screen (a carrier in its place); the change is the game's own screen's commit
--                (built off the stack), its moves through Mon.learnMove / game:learnMoveOn; onDone(result) to the
--                caller, which pops it
--   "catch"      a first catch's Pokédex page (Gen 1's "DexEntryMenu" pushed by the battle, Gen 2's
--                "Gen2PokedexMenu" with a new entry -- through src/gb/host.lua's registration) with the game's
--                question, give it a nickname?, answered there; the battle's own question (Gen 1's askNicknameUI,
--                Gen 2's askNickname) then isn't asked. And the naming screen for a Pokémon (Gen 1's "NamingScreen"
--                with a mon, Gen 2's "Gen2NamingScreen" of type nickname: a catch, a gift, an Egg, the Name Rater):
--                the keyboard
-- With the option off, the scene host busy, or anything failing: the game's own screen.
--
--   Sc = GbScenes(H, Gd, Art, deps)   deps: Sh, on(kind) -> bool, T, log, screens (mod.content.screens),
--                                     dexInfo(sp) -> the page's words | nil
--   Sc.install() (load: the screens) ; Sc.wrap() (game.ready: the functions) ; Sc.evolveJob / Sc.dexJob /
--   Sc.nameJob (the tests')

local floor = math.floor

return function(H, Gd, Art, deps)
  local Sc = {}
  local gen, engine = H.gen, H.engine
  local T, Sh = deps.T, deps.Sh
  local function log(fmt, ...) if deps.log then pcall(deps.log, fmt, ...) end end
  local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b = pcall(f, ...)
    if not ok then
      log("a scene: %s", tostring(a))
      return nil
    end
    return a, b
  end
  local function on(kind) return deps.on == nil or deps.on(kind) == true end
  local function data() return Gd.data() end
  local function free() return Sh and Sh.openScene and not Sh.sceneOpen() end

  -- ------- the games' words, sounds and music

  -- (the cart's line, its codes taken out)
  local function rom(label, fallback, ...)
    local R, d = H.engineFn("src.core.RomText"), data()
    local s
    if R and d then
      local ok, got = pcall(R, d, label, fallback, ...)
      if ok and type(got) == "string" then s = got end
    end
    if not s then
      local ok, got = pcall(string.format, fallback or "", ...)
      s = ok and got or ""
    end
    if gen == 2 then
      local CT = engine("src.core.gen2.CommonText")
      if CT and CT.plain then
        local ok, p = pcall(CT.plain, s)
        if ok and type(p) == "string" then s = p end
      end
    end
    return s
  end
  -- (plain pages: one per "\f", its lines joined; Red / Blue / Yellow's text-box codes -- {DONE}, {PROMPT},
  -- {SCROLL} -- taken out, the names they stand for put in)
  local function pages(text)
    local out = {}
    local s0 = tostring(text or "")
    if s0:find("{", 1, true) then
      local g = H.game()
      local sv = g and g.save
      local p = sv and sv.player
      local player = type(p) == "table" and p.name or ""
      local rival = sv and (sv.rivalName or (type(sv.rival) == "table" and sv.rival.name) or nil) or ""
      s0 = s0:gsub("{PLAYER}", tostring(player)):gsub("{RIVAL}", tostring(rival)):gsub("{COLON}", ":")
      s0 = s0:gsub("{[%u_][%u_%d]*}", "")
    end
    for page in (s0 .. "\f"):gmatch("(.-)\f") do
      local s = page:gsub("[\n\r\t]", " "):gsub("%c", ""):gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
      if s ~= "" then out[#out + 1] = s end
    end
    if #out == 0 then out[1] = "" end
    return out
  end
  Sc.pages = pages
  local function sound(name)
    local g, S = H.game(), engine("src.core.Sound")
    if g and g.data and S and S.play then pcall(S.play, g.data, name) end
  end
  local function cry(sp)
    local g, S = H.game(), engine("src.core.Sound")
    if g and g.data and S and S.playCry then pcall(S.playCry, g.data, sp) end
  end
  local function music(f, ...)
    local M = engine("src.core.Music")
    if M and M[f] then pcall(M[f], ...) end
  end
  local function evolutionMusic()
    local g, M = H.game(), engine("src.core.Music")
    if not (g and g.data and M) then return end
    if gen == 2 then
      local songs = g.data.audio and g.data.audio.songs
      if songs and songs.Music_Evolution then pcall(M.play, g.data, "Music_Evolution", true, { reason = "evolution" }) end
    else
      local okS, song = pcall(M.special, g.data, "evolution")
      if okS and song then pcall(M.play, g.data, song) end
    end
  end
  local function emit(name, payload)
    local R = engine("src.mods.Runtime")
    if R and R.emit then pcall(R.emit, name, payload) end
  end
  -- (the name the game says: its nickname, else the species' as the game writes it)
  local function gameName(mon)
    if type(mon) ~= "table" then return "?" end
    local nick = mon.nickname
    if type(nick) == "string" and nick ~= "" then return nick end
    local def = Gd.def(mon.species)
    return tostring(def and def.name or mon.name or mon.species or "?")
  end
  local function speciesWord(sp)
    local def = Gd.def(sp)
    return tostring(def and def.name or sp or "?")
  end

  -- (what both scenes share: the picture, the types, the cry)
  local function typesOf(sp)
    local list = Gd.typesOf(sp) or {}
    local a = list[1] and tonumber(list[1].id) or 0
    local b = list[2] and tonumber(list[2].id) or nil
    if b == a then b = nil end
    return a, b
  end
  local function picOf(sp, mon)
    local K = deps.kit
    local pic = Art and call(Art.pic, sp, mon) or nil
    if K and K.rescissor then K.rescissor() end
    return pic
  end

  -- (a carrier: the state the game pushes for its screen; its first update opens our scene over it, and the
  -- game's own screen takes its place when ours can't open)
  local function carrierDraw(self)
    local G = love and love.graphics
    if G and self.isOpaque then
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", 0, 0, 160, 144)
      G.setColor(1, 1, 1, 1)
    end
  end
  local function carrierUpdate(self)
    if self.opened then
      -- (back on top with no scene: it went away without a word)
      if not self.done and not Sh.sceneOpen() then self.lost() end
      return
    end
    self.opened = true
    local ok, got = pcall(self.open)
    if ok and got then return end
    if not ok then log("a scene of ours failed to open: %s", tostring(got)) end
    self.done = true
    local stk = self.game.stack
    if stk and stk:top() == self then pcall(stk.pop, stk) end
    if self.fallback then
      local okF, errF = pcall(self.fallback)
      if not okF then log("the game's own screen: %s", tostring(errF)) end
    end
  end
  local function carrier(game, open, fallback)
    local c = { isMenu = true, isOpaque = true, update = carrierUpdate, draw = carrierDraw, game = game,
                open = open, fallback = fallback }
    function c.lost() c.done = true end
    return c
  end
  local function popIfTop(game, st)
    local stk = game and game.stack
    if stk and stk:top() == st then pcall(stk.pop, stk) end
  end

  -- ------- an evolution

  local function statsOf(mon)
    local s = type(mon) == "table" and mon.stats or {}
    if gen == 2 then
      return { tonumber(mon.maxHp or s.hp) or 0, tonumber(s.attack) or 0, tonumber(s.defense) or 0,
               tonumber(s.specialAttack) or 0, tonumber(s.specialDefense) or 0, tonumber(s.speed) or 0 }
    end
    -- (Red / Blue / Yellow's one Special, on both rows: as the Pokédex shows it)
    return { tonumber(s.hp) or 0, tonumber(s.attack) or 0, tonumber(s.defense) or 0, tonumber(s.special) or 0,
             tonumber(s.special) or 0, tonumber(s.speed) or 0 }
  end

  -- the model the evolution window draws (src/evolve.lua's job): `how` the game's own pieces --
  --   { apply(job), learn(job, ui), finish(job, result), canStop, old (the name the game says) }
  function Sc.evolveJob(mon, toSp, how)
    local job = { mon = mon, from = mon.species, to = toSp, canStop = how.canStop ~= false, autoCancel = false,
                  battle = false }
    job.nick = Gd.monName(mon)
    job.fromName = Gd.monName(mon)
    job.toName = Gd.speciesName(toSp)
    job.level = tonumber(mon.level) or 1
    job.shiny = Gd.shiny(mon) == true
    local old, new = how.old or gameName(mon), speciesWord(toSp)
    local pics = {}
    function job.pic(which)
      local sp = which == "to" and toSp or job.from
      if pics[sp] == nil then pics[sp] = picOf(sp, mon) or false end
      return pics[sp] or nil
    end
    function job.types(which) return typesOf(which == "to" and toSp or job.from) end
    function job.say(key)
      if gen == 2 then
        if key == "congrats" then
          local a, b = pages(rom("_CongratulationsYourPokemonText", nil, old)), pages(rom("_EvolvedIntoText", nil, new))
          for _, p in ipairs(b) do a[#a + 1] = p end
          return a
        end
        if key == "stopped" or key == "huh" then return pages(rom("_StoppedEvolvingText", nil, old)) end
        return pages(rom("_EvolvingText", nil, old))
      end
      if key == "congrats" then
        return pages(rom("_EvolvedText", "%s evolved", old) .. rom("_IntoText", "\ninto %s!", new))
      end
      if key == "stopped" or key == "huh" then
        return pages(rom("_StoppedEvolvingText", "Huh? %s\nstopped evolving!", old))
      end
      return pages(rom("_IsEvolvingText", "What?\n%s is\nevolving!", old))
    end
    function job.cry(which) cry(which == "to" and toSp or job.from) end
    function job.introMusic() evolutionMusic() end
    function job.music() end
    function job.silence() music("stop") end
    function job.burst() if gen == 2 then sound("Sfx_Evolved") end end
    function job.cancelSound() end
    function job.fanfare() sound(gen == 2 and "Sfx_CaughtMon" or "Get_Item2") end
    function job.restore() end
    local applied = false
    function job.apply()
      if applied then return end
      applied = true
      job.before = statsOf(job.mon)
      local ok, err = pcall(how.apply, job)
      if not ok then log("the evolution's change: %s", tostring(err)) end
      job.after = statsOf(job.mon)
      job.fromName = Gd.monName(job.mon)
    end
    function job.pump() end
    function job.learn(ui)
      local ok, err = pcall(how.learn, job, ui)
      if not ok then
        log("the moves after evolving: %s", tostring(err))
        ui.done()
      end
    end
    local done = false
    function job.abandon() done = true end
    function job.finish(result)
      if done then return end
      done = true
      local ok, err = pcall(how.finish, job, result)
      if not ok then log("after the evolution: %s", tostring(err)) end
    end
    return job
  end

  -- (Red / Blue / Yellow: the moves the new species learns at its level; a full set, the game's own menu)
  local function learn1(job, ui)
    local game = H.game()
    local mon = job.mon
    local Exp = engine("src.battle.Experience")
    local def = Gd.def(mon.species)
    local moves = (Exp and def and call(Exp.movesLearnedAt, def, mon.level)) or {}
    local i = 0
    local function nxt()
      i = i + 1
      local moveId = moves[i]
      if not moveId then return ui.done() end
      for _, mv in ipairs(mon.moves or {}) do if mv.id == moveId then return nxt() end end
      local mdef = game.data.moves and game.data.moves[moveId]
      if not mdef then return nxt() end
      if #(mon.moves or {}) < 4 then
        table.insert(mon.moves, { id = moveId, pp = mdef.pp })
        local PF = engine("src.world.PikachuFollower")
        if PF and PF.onMoveLearned then pcall(PF.onMoveLearned, game.save, mon, moveId) end
        emit("pokemon.move_learned", { mon = mon, moveId = moveId })
        sound("Get_Item1")
        ui.say(pages(rom("_LearnedMove1Text", "%s learned\n%s!", gameName(mon), mdef.name)), nxt)
      else
        local Screens = engine("src.ui.Screens")
        local okP = Screens and pcall(Screens.push, game, "MoveLearnMenu", mon, moveId, function() nxt() end)
        if not okP then nxt() end
      end
    end
    nxt()
  end

  -- Gen 1: in place of Evolution.evolve -> true when ours took it
  function Sc.evolve1(game, mon, newSpecies, onDone, via, batch)
    if not (on("evolution") and free() and type(mon) == "table" and Gd.def(newSpecies)) then return false end
    local Evo = engine("src.pokemon.Evolution")
    if not (Evo and Evo.apply) then return false end
    local job = Sc.evolveJob(mon, newSpecies, {
      canStop = via ~= "TRADE" and via ~= "ITEM",
      apply = function() Evo.apply(game, mon, newSpecies, via) end,
      learn = learn1,
      finish = function(_, result)
        -- (between a battle's evolutions the game keeps the screen; after the last, the map's music)
        if not batch then
          local okM, M = pcall(engine, "src.core.Music")
          if okM and M and M.restoreMap then pcall(M.restoreMap, game.data) end
        end
        if onDone then onDone() end
      end,
    })
    return Sh.openScene("evolution", game.save, nil, { scene = job }) == true
  end

  -- Gen 2: the "Gen2EvolutionAnim" screen's place -> a carrier, or nil (the game's own)
  local function evolve2(game, opts)
    if not (on("evolution") and Sh and Sh.openScene) or type(opts) ~= "table" then return nil end
    local EA, Mon = engine("src.ui.gen2.EvolutionAnim"), engine("src.battle.gen2.Mon")
    local into = type(opts.entry) == "table" and opts.entry.into
    local mon = opts.mon or (opts.party or (game.save or {}).party or {})[opts.index or 1]
    if not (EA and EA.new and Mon and into and type(mon) == "table" and Gd.def(into)) then return nil end
    local c
    local inst
    c = carrier(game, function()
      if not free() then return false end
      -- (the game's own screen, off the stack: its change and its moves' list)
      local okN, made = pcall(EA.new, game, opts)
      if not okN then return false end
      inst = made
      local job = Sc.evolveJob(mon, into, {
        canStop = not opts.force, old = inst.nick,
        apply = function(j)
          inst:commit()
          if inst.evolved then j.mon = inst.evolved end
        end,
        learn = function(j, ui)
          local pend, i = inst.pending or {}, 0
          local d = game.data
          local function nxt()
            i = i + 1
            local moveId = pend[i]
            if not (moveId and inst.evolved) then return ui.done() end
            local mdef = d.moves and d.moves[moveId]
            local name = (mdef and mdef.name) or tostring(moveId)
            local okL, ok, why = pcall(Mon.learnMove, inst.evolved, moveId, d)
            if okL and ok then
              inst.learned[#inst.learned + 1] = moveId
              return ui.say(pages(rom("_LearnedMoveText", nil, inst.nick, name)), nxt)
            elseif okL and why == "full" and game.learnMoveOn then
              -- (the game asks which to forget, over ours)
              return game:learnMoveOn(inst.evolved, moveId, function(learned)
                if learned then inst.learned[#inst.learned + 1] = moveId else inst.full[#inst.full + 1] = moveId end
                nxt()
              end)
            end
            nxt()
          end
          nxt()
        end,
        finish = function(_, result)
          c.done = true
          inst.canceled = result == "stopped"
          if opts.onDone then
            local okD, errD = pcall(opts.onDone, { canceled = inst.canceled, evolved = inst.evolved,
                                                   learned = inst.learned, full = inst.full })
            if not okD then log("after the evolution: %s", tostring(errD)) end
          end
          popIfTop(game, c)
        end,
      })
      return Sh.openScene("evolution", game.save, nil, { scene = job }) == true
    end, function()
      game.stack:push(EA.new(game, opts))
    end)
    function c.lost()
      c.done = true
      if opts.onDone then pcall(opts.onDone, { canceled = true, learned = {}, full = {} }) end
      popIfTop(game, c)
    end
    return c
  end

  -- ------- a catch: its page and its nickname

  -- (a first catch's page answers the battle's question: kept by species until the battle asks)
  local answer = nil
  function Sc.answer() return answer end

  local function catchJob(kind, sp, mon, max)
    local job = { kind = kind, sp = sp, mon = mon, max = max or 10 }
    job.name = Gd.speciesName(sp)
    job.shiny = mon ~= nil and Gd.shiny(mon) == true or false
    local pic = nil
    function job.pic()
      if pic == nil then pic = picOf(sp, mon) or false end
      return pic or nil
    end
    function job.types() return typesOf(sp) end
    function job.cry() cry(sp) end
    job.ball = gen == 2 and mon and type(mon.caughtBall) == "string" and mon.caughtBall or nil
    return job
  end

  -- the page after a first catch -> a carrier, or nil (the game's own). onClose: how the game hears back
  local function dexPage(game, sp, mon, onClose)
    if not (on("catch") and Sh and Sh.openScene and Gd.def(sp)) then return nil end
    local job = catchJob("dex", sp, mon, 10)
    job.info = deps.dexInfo and call(deps.dexInfo, sp) or nil
    job.title = job.name
    job.seed = speciesWord(sp)
    local said = gameName(mon or { species = sp })
    function job.registered() return T.f("caught.registered", job.name) end
    function job.ask()
      local text = gen == 2 and rom("_AskGiveNicknameText", nil, said) or rom("_DoYouWantToNicknameText", "Do you want to\ngive a nickname\nto %s?", said)
      local got = pages(text)
      if got[1] == "" then return { T.f("caught.ask", job.name) } end
      return got
    end
    function job.pcPages() return nil end
    function job.alive() return true end
    local c
    function job.finish(a)
      if c.done then return end
      c.done = true
      answer = { sp = sp, nick = a }
      if onClose then onClose(c) end
    end
    function job.abandon() if c then c.done = true end end
    c = carrier(game, function()
      if not free() then return false end
      return Sh.openScene("caught", game.save, nil, { scene = job }) == true
    end, nil)
    function c.lost()
      c.done = true
      if onClose then onClose(c) end
    end
    return c
  end
  Sc.dexJob = function(sp, mon) return catchJob("dex", sp, mon, 10) end

  -- (the battle on top: the one catching)
  local function battleOf(game)
    local top = game and game.stack and game.stack:top()
    if type(top) ~= "table" then return nil end
    if top.isBattleState or top.isBattle or top.screenId == "Gen2BattleState" then return top end
    return nil
  end

  -- Gen 1: "DexEntryMenu" while a battle's catching -> ours
  local function dexEntry1(game, speciesOrOpts, onDone)
    local sp = type(speciesOrOpts) == "table" and speciesOrOpts.species or speciesOrOpts
    local b = battleOf(game)
    local mon = b and b.enemy and b.enemy.mon
    if not (type(mon) == "table" and mon.species == sp) then return nil end
    return dexPage(game, sp, mon, function(c)
      -- (the game's page pops itself, then onDone)
      popIfTop(game, c)
      if onDone then pcall(onDone) end
    end)
  end
  -- Gen 2: "Gen2PokedexMenu" with a new entry, from a battle -> ours (src/gb/host.lua asks)
  function Sc.caughtPage(game, opts)
    if gen ~= 2 or not (opts and opts.entrySpecies and opts.newEntry) then return nil end
    local b = battleOf(game)
    local mon = b and b.battle and b.battle.enemy
    if type(mon) ~= "table" or mon.species ~= opts.entrySpecies then mon = nil end
    if not b then return nil end
    return dexPage(game, opts.entrySpecies, mon, function(c)
      -- (the battle's onClose pops it)
      if opts.onClose then
        local ok, err = pcall(opts.onClose)
        if not ok then log("after the catch's page: %s", tostring(err)) end
      end
      popIfTop(game, c)
    end)
  end

  -- the battle's question, answered by the page -> the answer (a name, or false), or nil (ask)
  local function takeAnswer(mon)
    local a = answer
    answer = nil
    if not (a and type(mon) == "table" and mon.species == a.sp) then return nil end
    if type(a.nick) == "string" and a.nick ~= "" then return a.nick end
    return false
  end
  local function clip(name)
    local TC = engine("src.core.TextClip")
    local Font = engine("src.render.Font")
    if TC and TC.clip then
      local ok, got = pcall(TC.clip, name, 10, Font and Font.split)
      if ok and type(got) == "string" then return got end
    end
    return name:sub(1, 10)
  end

  -- the naming screen for a Pokémon -> a carrier, or nil (the game's own)
  local function naming(game, opts, finishFn)
    if not (on("catch") and Sh and Sh.openScene) or type(opts) ~= "table" or type(opts.mon) ~= "table" then return nil end
    local mon = opts.mon
    local sp = mon.species
    if not Gd.def(sp) then return nil end
    local job = catchJob("name", sp, mon, tonumber(opts.maxLen or opts.maxLength) or 10)
    job.seed = ""
    job.initial = tostring(opts.initial or "")
    job.title = job.name
    function job.registered() return nil end
    function job.ask() return nil end
    function job.pcPages() return nil end
    function job.alive() return true end
    local c
    function job.finish(nick)
      if c.done then return end
      c.done = true
      if type(nick) ~= "string" or nick:match("^%s*$") then nick = nil end
      finishFn(c, nick)
    end
    function job.abandon() if c then c.done = true end end
    c = carrier(game, function()
      if not free() then return false end
      return Sh.openScene("caught", game.save, nil, { scene = job }) == true
    end, nil)
    function c.lost()
      c.done = true
      finishFn(c, nil)
    end
    return c
  end

  -- ------- the takeover

  local function wrap(M, fname, key, impl)
    if type(M) ~= "table" or type(M[fname]) ~= "function" then return end
    local w = rawget(M, key)
    if not w then
      w = { orig = M[fname] }
      M[key] = w
      M[fname] = function(...)
        local cur = rawget(M, key)
        if cur.impl then
          local ok, took = pcall(cur.impl, ...)
          if not ok then
            if cur.log then pcall(cur.log, "a scene of ours failed to open: %s", tostring(took)) end
          elseif took then
            if took == true then return end
            return took
          end
        end
        return cur.orig(...)
      end
    end
    w.impl, w.log = impl, function(fmt, ...) log(fmt, ...) end
  end

  -- (the screens: at load, through the registry; each falls back on the game's own)
  function Sc.install()
    local reg = deps.screens
    if not (reg and reg.register) then return false end
    if gen == 2 then
      reg:register("Gen2EvolutionAnim", { new = function(game, opts)
        local c = evolve2(game, opts)
        if c then return c end
        return engine("src.ui.gen2.EvolutionAnim").new(game, opts)
      end })
      reg:register("Gen2NamingScreen", { new = function(game, opts)
        local NS = engine("src.ui.gen2.NamingScreen")
        local c = opts and opts.type == "nickname" and naming(game, opts, function(_, nick)
          -- (the caller pops it, as it pops the game's)
          if nick then
            if opts.onDone then pcall(opts.onDone, nick) end
          elseif opts.onCancel then pcall(opts.onCancel)
          elseif opts.onDone then pcall(opts.onDone, nil) end
        end) or nil
        if c then
          c.fallback = function() game.stack:push(NS.new(game, opts)) end
          return c
        end
        return NS.new(game, opts)
      end })
    else
      reg:register("DexEntryMenu", { new = function(game, speciesOrOpts, onDone)
        local M = engine("src.ui.DexEntryMenu")
        local c = dexEntry1(game, speciesOrOpts, onDone)
        if c then
          c.fallback = function() game.stack:push(M.new(game, speciesOrOpts, onDone)) end
          return c
        end
        return M.new(game, speciesOrOpts, onDone)
      end })
      reg:register("NamingScreen", { new = function(game, opts)
        local NS = engine("src.ui.NamingScreen")
        local c = opts and not opts.presets and naming(game, opts, function(c0, nick)
          -- (the game's pops itself, then onDone(name, custom))
          popIfTop(game, c0)
          if opts.onDone then pcall(opts.onDone, nick or (opts.default or ""), true) end
        end) or nil
        if c then
          c.fallback = function() game.stack:push(NS.new(game, opts)) end
          return c
        end
        return NS.new(game, opts)
      end })
    end
    return true
  end

  -- (the functions: once per process, this instance's code swapped in)
  function Sc.wrap()
    if gen == 1 then
      wrap(engine("src.pokemon.Evolution"), "evolve", "__woobOsEvo", function(game, mon, newSpecies, onDone, via, batch)
        return Sc.evolve1(game, mon, newSpecies, onDone, via, batch)
      end)
      -- (the battle's question: the page answered it)
      wrap(engine("src.battle.BattleState"), "askNicknameUI", "__woobOsNick", function(self, mon)
        local a = takeAnswer(mon)
        if a == nil then return nil end
        if a then mon.nickname = clip(a) end
        self.blankForAskName = false
        -- (a state the battle waits on: gone at once)
        local st = { isMenu = true, draw = function() end }
        st.update = function(me) popIfTop(self.game, me) end
        return st
      end)
    else
      wrap(engine("src.ui.gen2.BattleState"), "askNickname", "__woobOsNick", function(self, mon)
        local a = takeAnswer(mon)
        if a == nil then return nil end
        if a then mon.nickname = clip(a) end
        self.nicknameMon = nil
        self.message = nil
        self.phase = "resolving"
        self:advanceQueue()
        return true
      end)
    end
  end

  return Sc
end
