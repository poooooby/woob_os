-- An evolution's model, for our scene (src/apps/evolution.lua draws it): everything the game's own evolution
-- scene does besides drawing, through the engine's pieces -- its words (ROM text), its music and sounds,
-- the Pokémon's pictures, the change itself at the point of no return (Evolution.apply: species, stats,
-- nickname, the Pokédex, Shedinja), the moves it learns at its level after (LearnMove, asking through the
-- window), and the game hearing back (EvolutionScene's open flag, its onDone(result, mon)).
--
--   Ev = Evolve(engine, deps)          deps: log
--   job = Ev.job(mon, postSpecies, opts) -> the scene's model, or nil (opts: EvolutionScene.start's:
--         canStop, autoCancel, session, bag, isBattle, savedSong, via, onDone)
--     job.from, job.to (species) ; job.fromName, job.toName ; job.canStop ; job.autoCancel
--     job.types(which) -> t1, t2 ("from" | "to") ; job.pic(which) -> { image, box } | nil
--     job.say(key) -> the game's line as pages ("evolving" | "congrats" | "stopped" | "huh")
--     job.cry(which) ; job.introMusic() ; job.music() ; job.silence() ; job.burst() (the sound at the
--     flash) ; job.fanfare() ; job.cancelSound() ; job.restore() (the music from before)
--     job.apply() (the point of no return, once; job.before / job.after its six stats either side, job.level)
--     job.pump() (each frame: the move's questions)
--     job.learn(ui) (the moves after: ui.say(pages, cb), ui.ask(pages, cb(yes)), ui.done())
--     job.finish(result) ("evolved" | "stopped": the game hears back, once)
--   Ev.pages(text) -> plain pages (the game's codes taken out)

return function(engine, deps)
  local Ev = {}
  local function log(fmt, ...) if deps and deps.log then pcall(deps.log, fmt, ...) end end
  local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b = pcall(f, ...)
    if not ok then return nil end
    return a, b
  end

  -- (the songs that are a fanfare or the evolution's own: never the one to go back to; the game's list)
  local NON_MAP = {
    MUS_HEAL = true, MUS_LEVEL_UP = true, MUS_OBTAIN_ITEM = true, MUS_EVOLVED = true, MUS_OBTAIN_BADGE = true,
    MUS_OBTAIN_TMHM = true, MUS_OBTAIN_BERRY = true, MUS_EVOLUTION_INTRO = true, MUS_EVOLUTION = true,
    MUS_RS_VS_GYM_LEADER = true, MUS_RS_VS_TRAINER = true, MUS_SCHOOL = true, MUS_SLOTS_JACKPOT = true,
    MUS_SLOTS_WIN = true, MUS_MOVE_DELETED = true, MUS_TOO_BAD = true, MUS_DEX_RATING = true,
    MUS_OBTAIN_KEY_ITEM = true, MUS_POKE_FLUTE = true, MUS_AWAKEN_LEGEND = true, MUS_RG_POKE_FLUTE = true,
    MUS_RG_OBTAIN_KEY_ITEM = true, MUS_RG_DEX_RATING = true, MUS_OBTAIN_B_POINTS = true,
    MUS_OBTAIN_SYMBOL = true, MUS_REGISTER_MATCH_CALL = true,
  }
  local function passing(id)
    id = tonumber(id)
    if not id or id == 0 or id == 0xFFFF then return true end
    local Song = engine("src.core.game3.song_ids")
    local name = Song and call(Song.nameOf, id)
    return name ~= nil and NON_MAP[name] == true
  end

  function Ev.pages(text)
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

  -- (Ruby / Sapphire keep these lines under the battle's names)
  local RS_TEXT = {
    gText_PkmnIsEvolving = "BattleText_StartEvo", gText_CongratsPkmnEvolved = "BattleText_FinishEvo",
    gText_PkmnStoppedEvolving = "BattleText_StopEvo", gText_EllipsisQuestionMark = "BattleText_StopEvo",
  }
  local KEYS = { evolving = "gText_PkmnIsEvolving", congrats = "gText_CongratsPkmnEvolved",
                 stopped = "gText_PkmnStoppedEvolving", huh = "gText_EllipsisQuestionMark" }
  local function box(key, vars)
    local RomText = engine("src.core.game3.rom_text")
    if not RomText then return "" end
    if RS_TEXT[key] and not call(RomText.has, key) then
      return call(RomText.box, RS_TEXT[key], { stringVars = vars, battle = { [2] = vars[1], [3] = vars[2] } }) or ""
    end
    return call(RomText.box, key, { stringVars = vars }) or ""
  end

  local function clean(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("%z+", ""):match("^%s*(.-)%s*$")) or ""
  end

  function Ev.job(mon, postSpecies, opts)
    opts = opts or {}
    local P = engine("src.core.game3.pokemon")
    local Audio, Song = engine("src.core.game3.audio"), engine("src.core.game3.song_ids")
    local Scene = engine("src.ui.game3.evolution_scene")
    if not (P and Audio and Song and Scene and mon) then return nil end
    local from = tonumber(call(P.speciesOf, mon)) or 1
    local to = tonumber(call(P.speciesFromName, postSpecies)) or tonumber(postSpecies) or from
    local job = { mon = mon, from = from, to = to, canStop = opts.canStop ~= false,
                  autoCancel = opts.autoCancel and true or false, battle = opts.isBattle and true or false }
    local nick = clean(mon.nickname)
    if nick == "" then nick = clean(call(P.name, from)) end
    job.nick = nick ~= "" and nick or "POKéMON"
    job.fromName = tostring(call(P.displayMonName, mon) or job.nick)
    job.toName = tostring(call(P.name, to) or "POKéMON")
    -- (the music to go back to: the one asked for, else what's playing, else the map's)
    local saved = opts.savedSong
    if not saved or passing(saved) then
      if Audio._currentSong and not passing(Audio._currentSong.id) then saved = Audio._currentSong.id end
    end
    if not saved or passing(saved) then saved = Audio._mapSong end

    -- (the game asks: it's open, with this Pokémon)
    Scene.open, Scene._mon, Scene._onDone = true, mon, opts.onDone
    Scene._preSpecies, Scene._postSpecies = from, to

    local pid = mon.personality
    local shiny = call(P.isShiny, mon) == true
    local pics = {}
    function job.pic(which)
      local sp = which == "to" and to or from
      if pics[sp] == nil then
        local got = call(P.frontPic, call(P.picSpecies, sp, pid) or sp, nil, shiny, pid, "evolution", mon)
        pics[sp] = type(got) == "table" and got.image and got or false
        local K = deps.kit
        if K and K.rescissor then K.rescissor() end
      end
      return pics[sp] or nil
    end
    local types = {}
    function job.types(which)
      local sp = which == "to" and to or from
      if not types[sp] then
        local t = call(P.types, sp)
        local a = type(t) == "table" and tonumber(t[1]) or 0
        local b = type(t) == "table" and tonumber(t[2]) or nil
        types[sp] = { a, b ~= a and b or nil }
      end
      return types[sp][1], types[sp][2]
    end
    job.shiny = shiny

    function job.say(key)
      if key == "congrats" then return Ev.pages(box(KEYS.congrats, { job.nick, job.toName })) end
      return Ev.pages(box(KEYS[key] or key, { job.fromName }))
    end

    local function sound(f, ...) if Audio then call(Audio[f], ...) end end
    function job.cry(which) sound("playCry", which == "to" and to or from) end
    function job.introMusic() sound("playSong", Song.MUS_EVOLUTION_INTRO, { loop = false }) end
    function job.music() sound("playSong", Song.MUS_EVOLUTION, { restart = true, loop = true }) end
    function job.silence() sound("playSong", 0) end
    local SE = engine("src.core.game3.se_ids")
    function job.burst() sound("playSe", SE and SE.SE_M_PETAL_DANCE or 195) end
    function job.cancelSound() sound("playSe", SE and SE.SE_NOT_EFFECTIVE or 2) end
    function job.fanfare()
      sound("stopCry")
      sound("playFanfare", Song.MUS_EVOLVED)
    end
    function job.restore()
      if saved and not passing(saved) then sound("playSong", saved)
      elseif Audio._mapSong then sound("playSong", Audio._mapSong) end
    end

    -- (its six stats: before the change, and after it -- the window shows what each gained)
    local function statsOf(m)
      return { tonumber(m.maxHp or m.maxhp) or 0, tonumber(m.attack or m.atk) or 0,
               tonumber(m.defense or m.def) or 0, tonumber(m.spAtk or m.spa) or 0,
               tonumber(m.spDef or m.spd) or 0, tonumber(m.speed or m.spe) or 0 }
    end
    job.level = tonumber(mon.level) or 1
    local applied = false
    function job.apply()
      if applied then return end
      applied = true
      job.before = statsOf(mon)
      local Evolution = engine("src.core.game3.evolution")
      local ok, err = pcall(Evolution.apply, mon, to, opts.session, opts.bag, opts.via)
      if not ok then log("the evolution's change: %s", tostring(err)) end
      job.after = statsOf(mon)
      job.fromName = tostring(call(P.displayMonName, mon) or job.fromName)
    end

    function job.pump()
      local LearnMove = engine("src.core.game3.battle.learn_move")
      if LearnMove and call(LearnMove.busy) and LearnMove.pump then call(LearnMove.pump) end
    end

    -- the moves it learns at its level, one after another, the game asking through the window
    function job.learn(ui)
      local LearnMove = engine("src.core.game3.battle.learn_move")
      local queue = LearnMove and call(LearnMove.movesForLevels, mon, { tonumber(mon.level) or 1 }) or nil
      local name = tostring(call(P.displayMonName, mon) or job.nick)
      local i = 0
      local function nxt()
        i = i + 1
        local item = type(queue) == "table" and queue[i]
        if not item then return ui.done() end
        local o = {
          mon = mon, moveId = item.moveId, displayName = name, battleText = true,
          pushMsg = function(t, cb) ui.say(Ev.pages(t), cb) end,
          askYesNo = function(a, b)
            local cb = type(a) == "function" and a or b
            local prompt = type(a) == "string" and a or ""
            ui.ask(Ev.pages(prompt), function(yes) if cb then cb(yes == true) end end)
          end,
          askForget = function(_, cb, cctx)
            local SummaryMenu = engine("src.ui.game3.summary_menu")
            local ok, err = pcall(SummaryMenu.openMenu, { mon }, 1, {
              mode = "select_move", moveToLearn = (cctx and cctx.moveId) or LearnMove._moveId,
              onSelectMove = function(slot) if cb then cb(slot) end end,
            })
            if not ok then
              log("choosing a move to forget: %s", tostring(err))
              if cb then cb(nil) end
            end
          end,
          onDone = function(learned)
            if learned then ui.wait(1.07, nxt) else nxt() end
          end,
        }
        local ok, err = pcall(LearnMove.begin, o)
        if not ok then
          log("a move after evolving: %s", tostring(err))
          nxt()
        end
      end
      nxt()
    end

    local done = false
    -- (taken away before its end, a reset: the game told it's shut, nothing called)
    function job.abandon()
      if done then return end
      done = true
      Scene.open, Scene._onDone, Scene._mon = false, nil, nil
    end
    function job.finish(result)
      if done then return end
      done = true
      job.restore()
      local cb = Scene._onDone
      Scene.open, Scene._onDone, Scene._mon = false, nil, nil
      if cb then
        local ok, err = pcall(cb, result, mon)
        if not ok then log("after the evolution: %s", tostring(err)) end
      end
    end
    return job
  end

  return Ev
end
