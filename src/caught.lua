-- A catch's page and a Pokémon's nickname, for our scene (src/apps/caught.lua draws it). Two ways in:
--   "dex"   in place of the Pokédex's page after a first catch (FireRed / LeafGreen's showRegistration,
--           Ruby / Sapphire / Emerald's showCaughtMon): the Pokémon's page, then the game's question --
--           give it a nickname? -- answered here; the answer waits for the battle's own question
--           (the engine's catch.nickname hook, src/scenes.lua: Sc.nickFor), which then isn't asked
--   "name"  in place of the naming screen for a Pokémon (the templates CAUGHT_MON and NICKNAME: a catch, an
--           Egg hatching, a gift, the Name Rater): the keyboard at once; a catch sent to the PC says so after
-- The game hears back as from its own screens: the dex's onDone (Emerald's with the picture it slides back),
-- the naming screen's onDone(name) with its open flag down first.
--
--   Cg = Caught(engine, deps)     deps: kit, T, log, dexInfo(sp) -> { numText, category, heightText,
--                                 weightText, description } | nil
--   job = Cg.dex(sp, opts, family) | Cg.name(opts, stand) (stand: the naming screen's stand-in state)
--     job.kind ; job.sp ; job.mon (nil when unknown) ; job.name (the species, titled) ; job.nick ;
--     job.types() -> t1, t2 ; job.pic() -> { image, box } | nil ; job.info (the page, "dex") ; job.ball (an item)
--     job.max ; job.seed ; job.title ; job.ask() -> the question's pages ("dex") ; job.pcPages(nick) -> pages | nil
--     job.registered() -> the words for the page ; job.cry() ; job.alive() -> false once the game let it go
--     job.finish(answer) ("dex": a name, false for no; "name": the name) ; job.abandon()
--   Cg.answer -> { sp, personality, nick } | nil (a dex page's answer, until the battle asks)

return function(engine, deps)
  local Cg = {}
  local T = deps.T
  local function log(fmt, ...) if deps.log then pcall(deps.log, fmt, ...) end end
  local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b = pcall(f, ...)
    if not ok then return nil end
    return a, b
  end
  local function titled(s)
    s = tostring(s or "")
    if s:find("%l") then return s end
    return (s:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
  end
  local function pages(text)
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
  Cg.pages = pages

  local function caughtMon()
    local CatchSeq = engine("src.core.game3.battle.catch_seq")
    local res = CatchSeq and call(CatchSeq.catchResult)
    return type(res) == "table" and res.mon or nil, res
  end

  -- (what both ways share: the picture, the types, the cry)
  local function base(job, sp, mon, pid, shiny)
    local P = engine("src.core.game3.pokemon")
    job.sp, job.mon = sp, mon
    job.name = titled(call(P and P.name, sp) or "?")
    local pic = nil
    function job.pic()
      if pic == nil then
        local got = call(P and P.frontPic, call(P and P.picSpecies, sp, pid) or sp, nil, shiny == true, pid, "dex", mon)
        pic = type(got) == "table" and got.image and got or false
        if deps.kit and deps.kit.rescissor then deps.kit.rescissor() end
      end
      return pic or nil
    end
    local t = call(P and P.types, sp)
    local a = type(t) == "table" and tonumber(t[1]) or 0
    local b = type(t) == "table" and tonumber(t[2]) or nil
    if b == a then b = nil end
    function job.types() return a, b end
    function job.cry()
      local Audio = engine("src.core.game3.audio")
      if Audio then call(Audio.playCry, sp) end
    end
    job.shiny = shiny == true
    job.ball = mon and tonumber(mon.pokeball) or nil
    return job
  end

  -- ------- after a first catch: its page, then the nickname

  function Cg.dex(sp, opts, family)
    opts = opts or {}
    sp = tonumber(sp) or 1
    local P = engine("src.core.game3.pokemon")
    local mon, res = caughtMon()
    if not mon then
      local Battle = engine("src.core.game3.battle")
      local st = Battle and Battle._st
      mon = st and st.enemy and st.enemy.mon or nil
    end
    local pid = opts.personality or (mon and mon.personality) or 0
    local shiny = opts.shiny
    if shiny == nil and mon then shiny = call(P and P.isShiny, mon) == true end
    local job = base({ kind = "dex", family = family, max = 10 }, sp, mon, pid, shiny)
    job.toPc = type(res) == "table" and res.location == "pc"
    job.info = deps.dexInfo and call(deps.dexInfo, sp) or nil
    local name = tostring(mon and call(P and P.displayMonName, mon) or call(P and P.name, sp) or "?")
    job.seed = name
    local Naming = engine("src.ui.game3.naming")
    job.title = Naming and call(Naming.monTitle, call(P and P.name, sp) or name) or name
    function job.registered() return T.f("caught.registered", job.name) end
    function job.ask()
      local BT = engine("src.core.game3.battle.battle_text")
      local got = BT and call(BT.get, "STRINGID_GIVENICKNAMECAPTURED", { opponentMon1 = name })
      if type(got) == "string" and got ~= "" then return pages(got) end
      return { T.f("caught.ask", job.name) }
    end
    function job.pcPages() return nil end
    function job.alive() return true end
    local done = false
    function job.finish(answer)
      if done then return end
      done = true
      -- (the answer for the battle's question, which comes next)
      Cg.answer = { sp = sp, personality = pid, nick = answer }
      local cb = opts.onDone or opts.onClose
      if not cb then return end
      local ok, err
      if family == "rse" then
        local pic = job.pic()
        ok, err = pcall(cb, { sprite = { dexNum = sp, img = pic and pic.image, x = 120, y = 80, x2 = 0, y2 = 0, prio = 0 },
                              species = sp, personality = opts.personality, otId = opts.otId,
                              otSecretId = opts.otSecretId, shiny = opts.shiny })
      else
        ok, err = pcall(cb)
      end
      if not ok then log("after the catch's page: %s", tostring(err)) end
    end
    function job.abandon() done = true end
    return job
  end

  -- the battle's question, answered by the page -> a name, false (no), nil (not ours: ask)
  function Cg.nickFor(mon)
    local a = Cg.answer
    Cg.answer = nil
    if not a then return nil end
    local P = engine("src.core.game3.pokemon")
    local sp = mon and tonumber(call(P and P.speciesOf, mon))
    if sp and sp ~= a.sp then return nil end
    if a.nick == false or a.nick == nil then return false end
    return a.nick
  end

  -- ------- a Pokémon's nickname: the naming screen's

  function Cg.name(opts, stand)
    opts = opts or {}
    local P = engine("src.core.game3.pokemon")
    local mon = nil
    if opts.template == "CAUGHT_MON" then mon = caughtMon() end
    local sp = tonumber(opts.species) or (mon and tonumber(call(P and P.speciesOf, mon))) or 1
    if mon and tonumber(call(P and P.speciesOf, mon)) ~= sp then mon = nil end
    local pid = opts.personality or (mon and mon.personality) or 0
    local shiny = mon and call(P and P.isShiny, mon) == true or false
    local job = base({ kind = "name", max = tonumber(opts.maxLen) or 10 }, sp, mon, pid, shiny)
    job.seed = tostring(opts.seed or "")
    job.initial = tostring(opts.initialText or "")
    job.title = type(opts.title) == "string" and opts.title or nil
    function job.registered() return nil end
    function job.ask() return nil end
    -- (a catch sent to the PC: the game says where it went, with its new name)
    function job.pcPages(nick)
      if opts.template ~= "CAUGHT_MON" then return nil end
      local toPc = opts.sentToPc
      if toPc == nil then
        local _, res = caughtMon()
        toPc = type(res) == "table" and res.location == "pc"
      end
      if not toPc then return nil end
      local Storage = engine("src.core.game3.storage")
      local Runtime = engine("src.core.game3.runtime")
      local s = opts.session or (Runtime and call(Runtime.getSession))
      if not (Storage and s) then return nil end
      local text = call(Storage.pcTransferMessage, s, nick, call(Storage.isDestinationBoxFull, s))
      if type(text) ~= "string" or text == "" then return nil end
      return pages(text)
    end
    local Naming = engine("src.ui.game3.naming")
    function job.alive() return Naming ~= nil and Naming._state == stand end
    local done = false
    function job.finish(nick)
      if done then return end
      done = true
      if type(nick) ~= "string" or nick:match("^%s*$") then nick = job.seed end
      if Naming and Naming._state == stand then Naming.openFlag, Naming._state = false, nil end
      if opts.onDone then
        local ok, err = pcall(opts.onDone, nick)
        if not ok then log("after the nickname: %s", tostring(err)) end
      end
    end
    function job.abandon()
      if done then return end
      done = true
      if Naming and Naming._state == stand then Naming.openFlag, Naming._state = false, nil end
    end
    return job
  end

  return Cg
end
