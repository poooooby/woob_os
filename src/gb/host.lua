-- The Game Boy games' host for the shell (src/shell.lua's deps.host): Red / Blue / Yellow (Gen 1) and
-- Gold / Silver / Crystal (Gen 2). Their screens are states on the game's own stack (src/core/StateStack.lua:
-- the top one updates, all draw bottom-up), their save is game.save, their sounds are Sound.play by name.
--
--   - the desktop, WoobPad and the full-screen host are each one state of ours on game.stack (made once per
--     layer id), taking the buttons in update() and handing them to the layer; the desktop's is opaque (the
--     field isn't drawn under it), WoobPad's isn't (the field stays, dimmed by the pad)
--   - the PC: Gen 2's Pokémon Center PC and bedroom PC are screens the World pushes by id
--     ("Gen2CenterPcMenu", "Gen2ItemPcMenu" with opts.house), so ours are registered under those ids at
--     load (mod.content.screens). Ours is a carrier: its first update opens the desktop over it; the
--     desktop's close hands the World's onClose(changed) the answer, which pops the carrier as the game's
--     menu would. Gen 1's which-PC menu is built inside OverworldState:openPC(onDone), so that function is
--     wrapped (once per process, OverworldState.__woobOs); its bedroom PC ("PlayerPC" with opts.direct) is
--     a carrier like Gen 2's. With the Desktop option off, or anything failing, the game's own opens
--   - a sound: the Gen 3 names the apps use (SE_SELECT ...) played as the game's nearest (SFX below)
--
--   H = host(mod, deps)   deps: gen (1 | 2), require, log, enabled() -> the Desktop option
--   H.gen, H.family ("gen1" | "gen2"), H.gameId(), H.bind(game), H.game(), H.session()
--   H.push(id, layer, over) / H.pop(id) / H.has(id) ; H.se(name) ; H.free(game) ; H.rows(opts) ;
--   H.original(o, opts, onClose) ; H.ready(Sh) ; H.install() (load: the screens) ; H.startRows(list, row)

return function(mod, deps)
  local req = deps.require or require
  local log = deps.log
  local gen = deps.gen == 1 and 1 or 2
  local H = { gen = gen, family = gen == 1 and "gen1" or "gen2" }

  local engineMods = {}
  local function engine(name)
    local m = engineMods[name]
    if m ~= nil then return m or nil end
    local ok
    ok, m = pcall(req, name)
    m = ok and type(m) == "table" and m or false
    engineMods[name] = m
    return m or nil
  end
  H.engine = engine

  local cur = nil
  local Sh = nil                 -- (the shell, from H.ready)
  function H.bind(game) if type(game) == "table" then cur = game end end
  function H.game()
    if cur then return cur end
    local g = mod.game
    if type(g) == "table" then return g end
    return nil
  end
  function H.session()
    local g = H.game()
    return g and g.save or nil
  end

  local GAMES = { "red", "blue", "yellow", "gold", "silver", "crystal" }
  function H.gameId()
    local GV = engine("src.core.GameVersion")
    local ok, id = pcall(GV and GV.get or error)
    id = ok and tostring(id or "") or ""
    for _, g in ipairs(GAMES) do
      if id:find(g, 1, true) then return g end
    end
    return id ~= "" and id or (gen == 1 and "red" or "crystal")
  end

  -- ------- sounds: the apps' Gen 3 names, as each generation's nearest
  local SFX1 = {
    SE_SELECT = "Press_AB", SE_FAILURE = "Denied", SE_SUCCESS = "Get_Item1", SE_SHOP = "Purchase",
    SE_VEND = "Purchase", SE_M_PAY_DAY = "Purchase", SE_PC_LOGIN = "Enter_PC", SE_PC_ON = "Turn_On_PC",
    SE_PC_OFF = "Turn_Off_PC", SE_WARP_IN = "Withdraw_Deposit", SE_WARP_OUT = "Withdraw_Deposit",
    SE_BALL_TRAY_BALL = "Ball_Toss", SE_BALL_TRAY_ENTER = "Ball_Poof", SE_BALL_TRADE = "Trade_Machine",
    SE_BALL_CLICK = "Tink", SE_BALL_BOUNCE_1 = "Tink", SE_SHINY = "Shooting_Star", SE_PIN = "Tink",
    SE_M_STAT_INCREASE = "Level_Up", SE_EXP_MAX = "Level_Up", SE_APPLAUSE = "Get_Key_Item",
    SE_BAG_CURSOR = "Press_AB", SE_DEX_SEARCH = "Dex_Page_Added", SE_CONTEST_HEART = "Tink",
    SE_POKENAV_CALL = "Start_Menu", SE_POKENAV_ON = "Start_Menu", SE_POKENAV_HANG_UP = "Press_AB",
    SE_NOTE_C = "Tink", SE_NOTE_D = "Tink", SE_NOTE_E = "Tink", SE_NOTE_F = "Tink", SE_NOTE_G = "Tink",
    SE_NOTE_A = "Tink", SE_NOTE_B = "Tink", SE_NOTE_C_HIGH = "Tink",
  }
  local SFX2 = {
    SE_SELECT = "Sfx_ReadText2", SE_FAILURE = "Sfx_Wrong", SE_SUCCESS = "Sfx_Item", SE_SHOP = "Sfx_Transaction",
    SE_VEND = "Sfx_Transaction", SE_M_PAY_DAY = "Sfx_PayDay", SE_PC_LOGIN = "Sfx_ChoosePcOption",
    SE_PC_ON = "Sfx_BootPc", SE_PC_OFF = "Sfx_ShutDownPc", SE_WARP_IN = "Sfx_WarpTo", SE_WARP_OUT = "Sfx_WarpFrom",
    SE_BALL_TRAY_BALL = "Sfx_BallBounce", SE_BALL_TRAY_ENTER = "Sfx_BallPoof", SE_BALL_TRADE = "Sfx_GiveTrademon",
    SE_BALL_CLICK = "Sfx_SwitchPokemon", SE_BALL_BOUNCE_1 = "Sfx_BallBounce", SE_SHINY = "Sfx_Shine",
    SE_PIN = "Sfx_Tally", SE_M_STAT_INCREASE = "Sfx_LevelUp", SE_EXP_MAX = "Sfx_HitEndOfExpBar",
    SE_APPLAUSE = "Sfx_Fanfare", SE_BAG_CURSOR = "Sfx_SwitchPockets", SE_DEX_SEARCH = "Sfx_ChangeDexMode",
    SE_CONTEST_HEART = "Sfx_Twinkle", SE_POKENAV_CALL = "Sfx_Call", SE_POKENAV_ON = "Sfx_Menu",
    SE_POKENAV_HANG_UP = "Sfx_HangUp", SE_NOTE_C = "Sfx_GlassTing", SE_NOTE_D = "Sfx_GlassTing",
    SE_NOTE_E = "Sfx_GlassTing2", SE_NOTE_F = "Sfx_GlassTing2", SE_NOTE_G = "Sfx_Tingle", SE_NOTE_A = "Sfx_Tingle",
    SE_NOTE_B = "Sfx_Twinkle", SE_NOTE_C_HIGH = "Sfx_Twinkle",
  }
  H.SFX = gen == 1 and SFX1 or SFX2
  function H.sfx(name)
    local g = H.game()
    local Sound = engine("src.core.Sound")
    if g and g.data and Sound and Sound.play then pcall(Sound.play, g.data, name) end
  end
  function H.se(name)
    local mapped = H.SFX[name] or name
    H.sfx(mapped)
  end

  -- ------- the stack: one state of ours per layer id
  local states = {}
  local function stack()
    local g = H.game()
    return g and g.stack or nil
  end
  local function indexOf(st)
    local stk = stack()
    local list = stk and stk.states
    if not list then return nil end
    for i = #list, 1, -1 do
      if list[i] == st then return i end
    end
    return nil
  end
  -- (the layer gets the game's input each frame it's on top; L / R from the pad's shoulders are the
  -- game's speed keys unless a state asks for them: ours do)
  local function stateUpdate(self)
    local g = H.game()
    if g and g.input and self.layer and self.layer.handleInput then self.layer.handleInput(g.input) end
  end
  local function stateDraw(self)
    if not self.isOpaque then return end
    local G = love and love.graphics
    if G then
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", 0, 0, 160, 144)
      G.setColor(1, 1, 1, 1)
    end
  end
  local function shoulders() return true end
  local function stateFor(id)
    local st = states[id]
    if not st then
      st = { woobOs = id, isMenu = true, update = stateUpdate, draw = stateDraw, wantsShoulders = shoulders }
      states[id] = st
    end
    return st
  end
  function H.push(id, layer, over)
    local st = stateFor(id)
    st.layer, st.isOpaque = layer, not over
    if indexOf(st) then return true end
    local stk = stack()
    if not (stk and stk.push) then return false end
    local ok, err = pcall(stk.push, stk, st)
    if not ok then
      if log then log:warn("the desktop could not open: %s", tostring(err)) end
      return false
    end
    return true
  end
  function H.pop(id)
    local st = states[id]
    local i = st and indexOf(st)
    if not i then return end
    local stk = stack()
    if i == #stk.states then
      pcall(stk.pop, stk)
    else
      table.remove(stk.states, i)
    end
  end
  function H.has(id)
    local st = states[id]
    return st ~= nil and indexOf(st) ~= nil
  end

  -- the player free to move in the field: the game in play, nothing on the stack over the field (Gen 2
  -- keeps the overworld off the stack; Gen 1 has it at the bottom), and the field taking the START button
  -- as the game's own test has it (no script, text, step, warp, battle)
  function H.free(game)
    game = game or H.game()
    if type(game) ~= "table" then return false end
    if game.phase ~= nil and game.phase ~= "play" and game.phase ~= "field" then return false end
    local stk = game.stack
    local top = stk and stk.top and stk:top() or nil
    if gen == 2 then
      local w = game.world
      if top ~= nil or type(w) ~= "table" then return false end
      if type(w.acceptsMenuInput) == "function" then
        local ok, yes = pcall(w.acceptsMenuInput, w)
        return ok and yes == true
      end
      return true
    end
    local ow = game.overworld
    if type(ow) ~= "table" or top ~= ow then return false end
    if ow.transitioning or ow.flyAnim or ow.teleportOut or ow.engaging or ow.emote or ow.pikaHop or ow.healAnim then
      return false
    end
    local p = ow.player
    if type(p) == "table" and (p.moving or p.inputLocked) then return false end
    local r = ow.runner
    if type(r) == "table" and type(r.isRunning) == "function" then
      local ok, running = pcall(r.isRunning, r)
      if ok and running then return false end
    end
    return #(ow.scriptMoves or {}) == 0
  end

  -- one of the game's screens opened over ours (Boxes' summary, the game's own PC menu): ours comes back
  -- when it's gone -- by its own callback, or, for a screen that just pops itself, once the stack is
  -- back to where it was (H.tick, each frame)
  local pending, pendingDepth = nil, 0
  function H.hold(reopen)
    local stk = stack()
    pending, pendingDepth = reopen, stk and #stk.states or 0
  end
  function H.tick(game)
    H.bind(game)
    if not pending then return end
    if Sh and Sh.hostOpen and Sh.hostOpen() then
      pending = nil
      return
    end
    local stk = stack()
    if stk and #stk.states <= pendingDepth then
      local f = pending
      pending = nil
      f()
    end
  end

  -- ------- the PC

  -- the which-PC menu's rows, by id (the apps ask ctx.row(id)): the Pokémon storage, the player's own,
  -- Prof. Oak's once the game has given the Pokédex, the Hall of Fame once there's a team in it
  function H.rows(opts)
    local s = opts and opts.session or H.session()
    local rows = { { id = "storage" }, { id = "player" } }
    if s then
      local dexGot
      if gen == 2 then
        dexGot = type(s.engineFlags) == "table" and (s.engineFlags[11] == true or s.engineFlags[11] == 1)
      else
        local f = s.flags or {}
        dexGot = f.EVENT_GOT_POKEDEX == true or f.EVENT_GOT_POKEDEX == 1
      end
      if dexGot then rows[#rows + 1] = { id = "oak" } end
      local hof = s.hallOfFame
      local teams = type(hof) == "table" and (tonumber(hof.count) or #(hof.teams or hof)) or 0
      if teams > 0 then rows[#rows + 1] = { id = "hall" } end
    end
    return rows
  end

  -- the carrier: the state the game pushes for its PC menu; its first update opens the desktop over it
  local function carrierUpdate(self)
    if self.done then return end
    if pending then return end
    if self.opened then
      -- (back on top without the desktop: it went away without a word; the game's menu is closed)
      if not (Sh and Sh.hostOpen and Sh.hostOpen()) then
        self.done = true
        self.finish(self.changed)
      end
      return
    end
    self.opened = true
    H.carrierNow = self
    local opened = false
    if Sh then
      local ok, got = pcall(Sh.openDesktop, self.dopts, self.mode, nil)
      opened = ok and got == true
      if not ok and log then log:warn("the desktop failed to open: %s", tostring(got)) end
    end
    if not opened then
      -- (the game's own menu instead, in this one's place)
      self.done = true
      local stk = stack()
      if stk and stk:top() == self then pcall(stk.pop, stk) end
      if self.fallback then pcall(self.fallback) end
    end
  end
  local function carrier(game, mode, finish, fallback)
    local c = { isMenu = true, mode = mode, update = carrierUpdate, draw = stateDraw, isOpaque = true,
                finish = finish, fallback = fallback, changed = false }
    c.dopts = { session = game.save, bedroom = mode == "bedroom", carrier = c,
                onClose = function(result)
                  c.done = true
                  c.result = result
                  finish(c.changed, result)
                end }
    return c
  end
  H.carrier = carrier

  -- ------- Gen 2's own screens, opened from an app (src/gb/main.lua): the room's decorations. onClose: the
  -- desktop (or the pad) back

  -- the bedroom's decorations: the game's menu; a moved one makes the bedroom script reload the room
  -- once the PC closes (the carrier answers `changed`)
  function H.decorate(onClose)
    local game = H.game()
    local Screens = engine("src.ui.Screens")
    if not (game and Screens and gen == 2) then error("no decorations here") end
    local c = H.carrierNow
    Screens.push(game, "Gen2DecorationMenu", { save = game.save, events = game.world and game.world.events,
                                               onDone = function(changed)
                                                 if changed and c then c.changed = true end
                                                 local stk = stack()
                                                 if stk and stk:top() then pcall(stk.pop, stk) end
                                                 onClose()
                                               end })
  end
  -- the Pokégear's cards: the phone's (Mom's), the radio's (the Radio Tower's quiz)
  local RADIO_FLAG, PHONE_FLAG, GEAR_FLAG = 0, 2, 4
  function H.hasPhone(s)
    s = s or H.session()
    if gen ~= 2 or type(s) ~= "table" then return false end
    local f, e = s.pokegearFlags or {}, s.engineFlags or {}
    local gear = e[GEAR_FLAG] == true or (s.inventory and (tonumber(s.inventory.POKEGEAR) or 0) > 0)
      or s.pokegearReceived == true
    return gear and (f.phone == true or e[PHONE_FLAG] == true)
  end
  function H.hasRadio(s)
    s = s or H.session()
    if gen ~= 2 or type(s) ~= "table" then return false end
    local f, e = s.pokegearFlags or {}, s.engineFlags or {}
    local gear = e[GEAR_FLAG] == true or (s.inventory and (tonumber(s.inventory.POKEGEAR) or 0) > 0)
      or s.pokegearReceived == true
    return gear and (f.radio == true or e[RADIO_FLAG] == true)
  end
  -- an off-stack Pokégear (never pushed: the game's own card code, for the Phone's calls and the Radio's
  -- shows; made fresh each time, so it knows where the player is now)
  function H.gear()
    local game = H.game()
    local M = engine("src.ui.gen2.Pokegear")
    if not (game and M and M.new and gen == 2) then return nil end
    local lm = nil
    if game.currentLandmark then
      local ok, id = pcall(game.currentLandmark, game)
      if ok then lm = id end
    end
    local ok, gear = pcall(M.new, game, { save = game.save, currentLandmark = lm, onClose = function() end })
    if not ok and log then log:warn("the Pokégear couldn't be made: %s", tostring(gear)) end
    return ok and gear or nil
  end
  function H.log(fmt, ...) if log then log:warn(fmt, ...) end end

  -- the game's own PC menu over the desktop (o.bedroom: the bedroom's)
  function H.original(o, opts, onClose)
    local game = H.game()
    if not game then error("no game") end
    if gen == 2 then
      local M = engine(o and o.bedroom and "src.ui.gen2.ItemPcMenu" or "src.ui.gen2.CenterPcMenu")
      local c = H.carrierNow
      local menu = M.new(game, { save = game.save, house = o and o.bedroom or nil, events = game.world and
                                 game.world.events, onClose = function(changed)
                                   if changed and c then c.changed = true end
                                   local stk = stack()
                                   if stk then pcall(stk.pop, stk) end
                                   onClose()
                                 end })
      game.stack:push(menu)
      return
    end
    local w = H.pcWrap
    if w and w.orig and game.overworld then
      w.orig(game.overworld, function() onClose() end)
      return
    end
    error("the game's PC menu isn't there")
  end

  -- (Gen 2: the World's onClose(changed) pops the carrier; the shell has popped the desktop already)
  local function gen2Screens()
    local reg = mod.content and mod.content.screens
    if not (reg and reg.register) then return false end
    local function builtin(path, game, opts)
      local M = engine(path)
      return M.new(game, opts)
    end
    reg:register("Gen2CenterPcMenu", { new = function(game, opts)
      opts = opts or {}
      if not (Sh and (not deps.enabled or deps.enabled())) then return builtin("src.ui.gen2.CenterPcMenu", game, opts) end
      return carrier(game, "select", function(changed)
        H.sfx("Sfx_ShutDownPc")
        if opts.onClose then opts.onClose(changed) end
      end, function() game.stack:push(builtin("src.ui.gen2.CenterPcMenu", game, opts)) end)
    end })
    reg:register("Gen2ItemPcMenu", { new = function(game, opts)
      opts = opts or {}
      if not (opts.house and Sh and (not deps.enabled or deps.enabled())) then
        return builtin("src.ui.gen2.ItemPcMenu", game, opts)
      end
      return carrier(game, "bedroom", function(changed)
        -- (as the game's: no shutdown sound when the room is about to reload)
        if not changed then H.sfx("Sfx_ShutDownPc") end
        if opts.onClose then opts.onClose(changed) end
      end, function() game.stack:push(builtin("src.ui.gen2.ItemPcMenu", game, opts)) end)
    end })
    return true
  end
  -- (Gen 1: the bedroom PC, pushed by id with opts.direct; a carrier pops itself)
  local function gen1Screens()
    local reg = mod.content and mod.content.screens
    if not (reg and reg.register) then return false end
    reg:register("PlayerPC", { new = function(game, opts)
      opts = opts or {}
      local M = engine("src.ui.PlayerPC")
      if not (opts.direct and Sh and (not deps.enabled or deps.enabled())) then return M.new(game, opts) end
      local c
      c = carrier(game, "bedroom", function()
        H.sfx("Turn_Off_PC")
        local stk = stack()
        if stk and stk:top() == c then pcall(stk.pop, stk) end
        if opts.onClose then pcall(opts.onClose) end
      end, function() game.stack:push(M.new(game, opts)) end)
      return c
    end })
    return true
  end
  -- the START menu's Pokédex: ours full screen (deps.dexOn: the option and Settings), the game's own a START
  -- away. Gen 1's pops itself and calls onCancel (the START menu back); Gen 2's onClose pops it
  local function dexCarrierUpdate(self)
    if self.done then return end
    if self.opened then
      if not (Sh and Sh.hostOpen and Sh.hostOpen()) then
        self.done = true
        self.finish()
      end
      return
    end
    self.opened = true
    local ok, got = false, false
    if Sh and Sh.openFull then
      ok, got = pcall(Sh.openFull, "pokedex", self.game.save, function()
        if not self.done then
          self.done = true
          self.finish()
        end
      end, nil, { mode = "dex", backKey = "dex.toMenu", classic = function()
        self.done = true
        local stk = stack()
        if stk and stk:top() == self then pcall(stk.pop, stk) end
        self.fallback()
      end })
    end
    if not (ok and got) then
      self.done = true
      local stk = stack()
      if stk and stk:top() == self then pcall(stk.pop, stk) end
      self.fallback()
    end
  end
  local function dexScreen()
    local reg = mod.content and mod.content.screens
    if not (reg and reg.register) then return false end
    local id = gen == 2 and "Gen2PokedexMenu" or "PokedexMenu"
    local path = gen == 2 and "src.ui.gen2.PokedexMenu" or "src.ui.PokedexMenu"
    reg:register(id, { new = function(game, opts)
      opts = opts or {}
      local M = engine(path)
      local wanted = Sh and (not deps.enabled or deps.enabled()) and deps.dexOn and deps.dexOn()
      -- (only the START menu's: one with a way back to it)
      if not (wanted and (opts.onCancel or opts.onClose) and not opts.entrySpecies) then return M.new(game, opts) end
      local c = { isMenu = true, update = dexCarrierUpdate, draw = stateDraw, isOpaque = true, game = game }
      c.finish = function()
        if gen == 2 then
          if opts.onClose then opts.onClose() end
        else
          local stk = stack()
          if stk and stk:top() == c then pcall(stk.pop, stk) end
          if opts.onCancel then opts.onCancel() end
        end
      end
      c.fallback = function() game.stack:push(M.new(game, opts)) end
      return c
    end })
    return true
  end

  -- ------- Gold / Silver / Crystal's Pokégear (deps.gearOn: the Pokégear option). One screen serves four
  -- callers, each with its own contract (src/ui/gen2/Pokegear.lua):
  --   Fly (opts.fly, World:openFlyMap): our map in its Fly mode, only the game's own points; a pick
  --     answers opts.onFly(spawn), B opts.onClose(); the World pops the screen in both
  --   the walls' Town Map (opts.townMap): our map; it pops itself, then opts.onClose() (the script goes on)
  --   the START menu's (no fly / townMap): WoobPad, which has the Map, Phone and Radio (onClose() closes the
  --     START menu's item; the START row is WoobPad's already, so this is rare)
  -- With the option off, without the desktop, or anything failing: the game's own Pokégear
  local function gearBuiltin(game, opts)
    local M = engine("src.ui.gen2.Pokegear")
    return M.new(game, opts)
  end
  local function gearCarrierUpdate(self)
    if self.done then return end
    if self.opened then
      if not (Sh and Sh.hostOpen and Sh.hostOpen()) then
        -- (the map went away without a word: as B)
        self.done = true
        self.cancel()
      end
      return
    end
    self.opened = true
    local ok, got = pcall(self.open, self)
    if not (ok and got) then
      if not ok and log then log:warn("the Pokégear's screen failed: %s", tostring(got)) end
      self.done = true
      local stk = stack()
      if stk and stk:top() == self then pcall(stk.pop, stk) end
      local okB, gear = pcall(self.fallback or gearBuiltin, self.game, self.opts)
      if okB and gear and stk then stk:push(gear) end
    end
  end
  local function gearScreen()
    local reg = mod.content and mod.content.screens
    if not (reg and reg.register) then return false end
    reg:register("Gen2Pokegear", { new = function(game, opts)
      opts = opts or {}
      local wanted = Sh and (not deps.enabled or deps.enabled()) and (not deps.gearOn or deps.gearOn())
      if not wanted then return gearBuiltin(game, opts) end
      local c = { isMenu = true, update = gearCarrierUpdate, draw = stateDraw, isOpaque = true, game = game,
                  opts = opts }
      local function popSelf()
        local stk = stack()
        if stk and stk:top() == c then pcall(stk.pop, stk) end
      end
      if opts.fly then
        local only = {}
        for _, pt in ipairs(type(opts.fly) == "table" and opts.fly or {}) do
          if type(pt) == "table" and pt.spawn then only[pt.spawn] = true end
        end
        c.cancel = function() if opts.onClose then opts.onClose() end end
        c.open = function()
          return Sh.openMapScreen({ session = game.save, mode = "fly", only = only,
            onPick = function(_, place)
              c.done = true
              if place and place.spawn and opts.onFly then opts.onFly(place.spawn) else c.cancel() end
            end,
            onClose = function()
              c.done = true
              c.cancel()
            end })
        end
      elseif opts.townMap then
        c.cancel = function()
          popSelf()
          if opts.onClose then opts.onClose() end
        end
        c.open = function()
          return Sh.openMapScreen({ session = game.save, mode = "town",
            onClose = function()
              c.done = true
              c.cancel()
            end,
            -- (START: the game's own, in ours' place: it closes itself, as it would have)
            classic = function()
              c.done = true
              popSelf()
              local okB, gear = pcall(gearBuiltin, game, opts)
              local stk = stack()
              if okB and gear and stk then stk:push(gear) elseif opts.onClose then opts.onClose() end
            end })
        end
      else
        c.cancel = function() end
        c.open = function()
          c.done = true
          if opts.onClose then opts.onClose() end
          if Sh.openWatch then Sh.openWatch(nil) end
          return true
        end
      end
      return c
    end })
    -- the walls' radios: our Radio, full screen, on the station the game resolves for this one (its
    -- MapRadio built, never pushed: the same reads); closing it leaves the music as the game's does
    -- (the window's Radio.close), then pops it and lets the script go on
    reg:register("Gen2MapRadio", { new = function(game, opts)
      opts = opts or {}
      local M = engine("src.ui.gen2.MapRadio")
      local wanted = Sh and Sh.openFull and (not deps.enabled or deps.enabled()) and (not deps.gearOn or deps.gearOn())
      if not wanted then return M.new(game, opts) end
      local okB, mr = pcall(M.new, game, opts)
      if not (okB and mr and mr.station) then return M.new(game, opts) end
      local c = { isMenu = true, update = gearCarrierUpdate, draw = stateDraw, isOpaque = false, game = game,
                  opts = opts }
      local function finish()
        if c.done then return end
        c.done = true
        local stk = stack()
        if stk and stk:top() == c then pcall(stk.pop, stk) end
        if opts.onDone then opts.onDone() end
      end
      c.cancel = finish
      c.fallback = function(g, o) return M.new(g, o) end
      c.open = function()
        return Sh.openFull("radio", game.save, finish, { station = mr.station }, { mode = "radio", backKey = "hint.close" })
      end
      return c
    end })
    return true
  end

  function H.install()
    local ok, err = pcall(gen == 2 and gen2Screens or gen1Screens)
    if not ok and log then log:warn("the PC screens weren't taken over: %s", tostring(err)) end
    local okD, errD = pcall(dexScreen)
    if not okD and log then log:warn("the Pokédex wasn't taken over: %s", tostring(errD)) end
    if gen == 2 then
      local okG, errG = pcall(gearScreen)
      if not okG and log then log:warn("the Pokégear wasn't taken over: %s", tostring(errG)) end
    end
  end

  -- (Gen 1: OverworldState:openPC wrapped once per process; this instance's impl swapped in)
  local function wrapOpenPC()
    local OW = engine("src.world.OverworldController")
    if not (OW and type(OW.openPC) == "function") then return false end
    local w = rawget(OW, "__woobOs")
    if not w then
      w = { orig = OW.openPC }
      OW.__woobOs = w
      OW.openPC = function(self, onDone)
        local impl = w.impl
        if impl then
          local ok, opened = pcall(impl, self, onDone)
          if ok and opened then return end
          if not ok and w.log then w.log:warn("the desktop failed to open: %s", tostring(opened)) end
        end
        return w.orig(self, onDone)
      end
    end
    w.log = log
    w.impl = function(ow, onDone)
      if deps.enabled and not deps.enabled() then return false end
      local game = H.game()
      if not (Sh and game) then return false end
      H.sfx("Turn_On_PC")
      local done = onDone or function() end
      return Sh.openDesktop({ session = game.save, onClose = function()
        H.sfx("Turn_Off_PC")
        done()
      end }, "select", nil)
    end
    H.pcWrap = w
    return true
  end

  function H.ready(shell)
    Sh = shell
    if gen == 1 then return wrapOpenPC() end
    return true
  end

  -- the START menu: WoobPad's row before SAVE (Gen 2's rows carry ids in `value` and a two-line `desc`;
  -- Gen 1's are labels)
  -- (Gold / Silver / Crystal with the Pokégear option on: in the POKéGEAR row's place, as WoobPad takes the
  -- PokéNav's on Ruby / Sapphire / Emerald; its Map, Phone and Radio do the Pokégear's jobs)
  function H.startRows(list, row)
    if type(list) ~= "table" then return list end
    local at, gear = nil, nil
    for i, e in ipairs(list) do
      if type(e) == "table" then
        if e.woobOs then return list end
        local id = e.value or e.id or e.label
        if type(id) == "string" and id:upper() == "SAVE" and not at then at = i end
        if type(id) == "string" and id:lower() == "pokegear" then gear = i end
      end
    end
    local entry = { label = row.label, keepOpen = true, woobOs = true, onSelect = function() row.onSelect() end }
    if gen == 2 then entry.desc = row.desc or { "WOOBOS", "" } end
    if gen == 2 and gear and (not deps.gearOn or deps.gearOn()) then
      -- (no value or id: the menu runs a mod's row by its onSelect)
      list[gear] = entry
      return list
    end
    if not at then return list end
    table.insert(list, at, entry)
    return list
  end

  return H
end
