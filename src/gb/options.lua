-- The OPTIONS screen, modern, on the Game Boy games (src/options_screen.lua's model for src/apps/options.lua): the
-- game's own rows -- built by its own screen (src.ui.OptionsMenu on Red / Blue / Yellow, src.ui.gen2.OptionsMenu on
-- Gold / Silver / Crystal), off the stack -- each doing what it does there, the same pages (SPEED, VIDEO, AUDIO...),
-- a row another mod adds tagged with its mod's name. Taken over through the screen registry ("OptionsMenu" /
-- "Gen2OptionsMenu"): a carrier of ours in the game's screen's place opens the window over it, and answers as the
-- game's screen does once it closes -- Gen 1's pops itself, then onCancel(); Gen 2's hands onDone(options) to its
-- caller, which pops it. A row that opens one of the game's screens (the mod manager, the palettes, the shaders,
-- the controls) opens it over ours; ours waits under it. The title screen's OPTIONS (no game in play) stays the
-- game's.
--
--   Go = GbOptions(H, Os, deps)   Os: src/options_screen.lua's (its words, pages, a mod's page) ; deps: Sh, on(),
--                                 screens (mod.content.screens), log
--   Go.install() (load: the screens) ; Go.model(game, opts) -> the window's model (the tests')

-- the game's pages: Gen 1's and Gen 2's own groups and the top page's order (src/ui/OptionsMenu.lua GROUPS / ORDER,
-- src/ui/gen2/OptionsMenu.lua's)
local GROUPS1 = {
  { id = "group.battle", label = "BATTLE OPTIONS",
    members = { "animations", "battleStyle", "battleLayout", "battleFit", "battleHud", "battleBg" } },
  { id = "group.audio", label = "AUDIO", members = { "musicVol", "sfxVol", "pikaVol", "musicFilter", "audioMode" } },
  { id = "group.video", label = "VIDEO",
    members = { "uiLayout", "videoMode", "orientation", "faithfulRes", "screenPos", "fpsCap", "vsync", "logicClock" } },
  { id = "group.speed", label = "SPEED", members = { "textSpeed", "speedOverworld", "speedBattle", "speedMenu" } },
  { id = "group.graphics", label = "GRAPHICS", members = { "colors", "uiLetterbox", "shaderfx", "shaderfx2" } },
  { id = "group.extras", label = "EXTRAS", members = { "tilt", "zoom", "voidFill" } },
}
local ORDER1 = { "group.speed", "controls", "group.video", "group.graphics", "group.audio", "performance", "ruleset",
                 "group.battle", "group.extras", "mods" }
local GROUPS2 = {
  { id = "group.speed", label = "SPEED", members = { "textSpeed", "speed" } },
  { id = "group.video", label = "VIDEO",
    members = { "uiLayout", "videoMode", "orientation", "faithfulRes", "screenPos", "fpsCap", "vsync", "logicClock" } },
  { id = "group.graphics", label = "GRAPHICS", members = { "color", "uiLetterbox", "shaderfx", "shaderfx2", "frame" } },
  { id = "group.audio", label = "AUDIO", members = { "sound", "musicVol", "sfxVol", "musicFilter", "audioMode" } },
  { id = "group.battle", label = "BATTLE OPTIONS",
    members = { "battleScene", "battleStyle", "battleLayout", "battleHud", "battleFit", "battleBg" } },
  { id = "group.extras", label = "EXTRAS", members = { "zoom", "voidFill", "tilt" } },
}
local ORDER2 = { "group.speed", "controls", "group.video", "group.graphics", "group.audio", "performance",
                 "group.battle", "group.extras" }

return function(H, Os, deps)
  local Go = {}
  local gen = H.gen
  local engine = H.engine
  local Sh = deps.Sh
  local function log(fmt, ...) if deps.log then pcall(deps.log, fmt, ...) end end
  local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b = pcall(f, ...)
    if not ok then return nil end
    return a, b
  end
  local function on() return deps.on == nil or deps.on() == true end
  local open = false
  function Go.isOpen() return open end
  local PATH = gen == 2 and "src.ui.gen2.OptionsMenu" or "src.ui.OptionsMenu"

  -- (the engine's words, translated as its own screen shows them)
  local function words(s, ...)
    local S = engine("src.core.Strings")
    if type(s) ~= "string" then return tostring(s or "") end
    if S then
      local ok, t = pcall(S, s, ...)
      if ok and type(t) == "string" then return t end
    end
    return s
  end

  -- the game's own screen, built off the stack (its rows, its options table); `plain`: the ui.options.rows hook
  -- asked for nothing, to tell the rows mods add apart
  local function build(game, options, plain)
    local M = engine(PATH)
    if not (M and M.new) then return nil end
    local Runtime = engine("src.mods.Runtime")
    local real = Runtime and Runtime.call
    if plain and real then
      Runtime.call = function(name, vanilla, ...)
        if name == "ui.options.rows" then return vanilla(...) end
        return real(name, vanilla, ...)
      end
    end
    local ok, inst = pcall(M.new, game, gen == 2 and { options = options } or {})
    if plain and real then Runtime.call = real end
    if not ok then
      log("the game's OPTIONS rows: %s", tostring(inst))
      return nil
    end
    return inst
  end

  -- a row of the game's as the window's: its words, its value, its step and its action
  local function wrapRow(inst, row, game)
    local r = { id = row.id, src = row }
    if gen == 2 and row.romLabel then r.label = tostring(row.label or "") else r.label = words(row.label) end
    if row.cancel then return nil end
    if gen == 2 then
      local function valueText()
        local o = inst.options or {}
        if row.frame then return tostring(o.frame or 1) end
        if row.text then return call(row.text, o) end
        if row.values then
          local v = o[row.key]
          if row.display then
            local d = row.display[v]
            return row.romDisplay and d or words(d)
          end
          return tostring(v)
        end
        if type(row.value) == "function" then return call(row.value, game) end
        return nil
      end
      -- (the cart's words padded to its value column: trimmed, so ON / OFF read as a switch)
      r.value = function()
        local v = valueText()
        if type(v) == "string" then v = v:gsub("^%s+", ""):gsub("%s+$", "") end
        return v
      end
      if row.activate then
        r.activate = function() return row.activate(game) end
      elseif row.step or row.cycle or row.frame or row.values then
        r.step = function(_, dir)
          inst:cycle(row, dir < 0 and -1 or 1)
          return true
        end
      end
    else
      if type(row.value) == "function" then r.value = function() return row.value(game) end end
      if row.step then r.step = function(_, dir) return row.step(game, dir < 0 and -1 or 1) == true end end
      if row.activate then r.activate = function() return row.activate(game) end end
    end
    return r
  end

  -- the top page: the game's rows grouped as the game groups them; a mod's rows tagged
  function Go.top(game, inst, openPage)
    local plainInst = build(game, inst.options, true)
    local own = {}
    for _, row in ipairs(plainInst and plainInst.rows or {}) do if row.id then own[row.id] = true end end
    local groups, order = gen == 2 and GROUPS2 or GROUPS1, gen == 2 and ORDER2 or ORDER1
    local owner, picked = {}, {}
    for _, g in ipairs(groups) do
      for _, id in ipairs(g.members) do owner[id] = g end
      picked[g.id] = {}
      own[g.id] = true
    end
    local wrapped = {}
    for _, row in ipairs(inst.rows or {}) do
      local r = wrapRow(inst, row, game)
      if r then
        wrapped[#wrapped + 1] = r
        local g = r.id and owner[r.id]
        if g then picked[g.id][#picked[g.id] + 1] = r end
      end
    end
    local made = {}
    for _, g in ipairs(groups) do
      local members = picked[g.id]
      if #members > 0 then
        local label = words(g.label)
        made[g.id] = { id = g.id, label = label, group = true, kind = "group",
                       activate = function() openPage(label, members) end }
      end
    end
    local byId, view, taken = {}, {}, {}
    for _, r in ipairs(wrapped) do if r.id and not owner[r.id] then byId[r.id] = r end end
    for _, id in ipairs(order) do
      local r = made[id] or byId[id]
      if r then
        view[#view + 1] = r
        taken[id] = true
      end
    end
    for _, r in ipairs(wrapped) do
      if not (r.id and (owner[r.id] or taken[r.id])) then view[#view + 1] = r end
    end
    -- (the words in a sentence's case, each row's kind, a mod's tagged)
    local MS = engine("src.mods.ManagerState")
    local ms = MS and call(MS.new, game)
    if ms then call(ms.refresh, ms) end
    local byMod = ms and call(ms.manifestMap, ms) or {}
    local function bare(x) return (tostring(x or ""):upper():gsub("[^%w]", "")) end
    for _, r in ipairs(view) do
      if r.id and next(own) and not own[r.id] then
        local m = byMod[r.id]
        if not m then
          for _, mm in pairs(byMod) do
            if type(mm) == "table" and mm.name and bare(mm.name) == bare(r.label) then m = mm break end
          end
        end
        local name = m and (m.name or m.id) or nil
        if name and bare(name) == bare(r.label) then r.label, r.modName = name, "Mod" else r.modName = name or "Mod" end
      end
    end
    Os.pageRows(game, view)
    for _, r in ipairs(view) do r.cased = true end
    return view
  end

  -- the window's model for the game's OPTIONS
  function Go.model(game, opts)
    local options = gen == 2 and (opts and opts.options or game.options) or nil
    local inst = build(game, options, false)
    if not inst then return nil end
    local model = { kind = "options", ctx = game, game = game, family = H.family, inst = inst }
    model.top = { title = "Options", rows = {} }
    function model.build(openPage)
      model.top.rows = Go.top(game, inst, openPage) or {}
      return model.top
    end
    function model.persist()
      if gen == 2 then
        if game.applyOptions then pcall(game.applyOptions, game) end
        local write = game.persistOptions or game.writeOptions
        if write then pcall(write, game) end
      elseif game.writeOptions then
        pcall(game.writeOptions, game)
      end
    end
    return model
  end

  -- ------- the takeover: a carrier in the game's screen's place
  local function carrierDraw(self)
    if not self.isOpaque then return end
    local G = love and love.graphics
    if G then
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", 0, 0, 160, 144)
      G.setColor(1, 1, 1, 1)
    end
  end
  local function carrierUpdate(self)
    if self.done then return end
    if self.opened then
      -- (back on top with ours gone: closed without a word)
      if not (Sh.hostOpen and Sh.hostOpen()) then self.finish() end
      return
    end
    self.opened = true
    local model = Go.model(self.game, self.opts)
    local ok, got = false, false
    if model then
      open = true
      ok, got = pcall(Sh.openFull, "options", self.game.save, function() self.finish() end, nil,
                      { menu = model, chrome = false, noHints = true })
      if not ok then log("the modern OPTIONS failed to open: %s", tostring(got)) end
    end
    if not (ok and got) then
      open = false
      self.done = true
      local stk = self.game.stack
      if stk and stk:top() == self then pcall(stk.pop, stk) end
      local M = engine(PATH)
      if M then stk:push(M.new(self.game, self.opts)) end
    end
  end

  function Go.install()
    local reg = deps.screens
    if not (reg and reg.register) then return false end
    local id = gen == 2 and "Gen2OptionsMenu" or "OptionsMenu"
    reg:register(id, { new = function(game, opts)
      opts = opts or {}
      local M = engine(PATH)
      -- (ours only in play: the title screen's, and a group's own page, stay the game's)
      local playing = type(game) == "table" and game.save ~= nil and (game.phase == nil or game.phase == "play"
        or game.phase == "field")
      if not (M and on() and playing and not opts.rows) then return M.new(game, opts) end
      local c = H.noId({ update = carrierUpdate, draw = carrierDraw, isOpaque = true, game = game, opts = opts })
      c.finish = function()
        if c.done then return end
        c.done = true
        open = false
        local stk = game.stack
        if gen == 2 then
          -- (the caller pops it, as it pops the game's)
          if opts.onDone then
            local okD, errD = pcall(opts.onDone, opts.options or game.options)
            if not okD then log("after OPTIONS: %s", tostring(errD)) end
          end
          if stk and stk:top() == c then pcall(stk.pop, stk) end
        else
          if stk and stk:top() == c then pcall(stk.pop, stk) end
          if opts.onCancel then
            local okC, errC = pcall(opts.onCancel)
            if not okC then log("after OPTIONS: %s", tostring(errC)) end
          end
        end
      end
      return c
    end })
    return true
  end

  return Go
end
