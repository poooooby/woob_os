-- The PokéNav's Match Call (Emerald) or Trainer's Eyes (Ruby / Sapphire) and its Condition (the
-- party's graph) open WoobOS's Phone and Condition apps instead, full screen over the PokéNav (the
-- shell's host, src/townmap.lua); closing them is the PokéNav's menu again, exactly as the game's own
-- screens leave it. No engine edits: the screens' constructors are wrapped once per process
-- (`__woobOs` on each module, calling this instance's `impl`), and our stand-in screens speak the
-- PokéNav's own screen protocol:
--   - Emerald (src.ui.game3.rse.pokenav.*): new(shell, menuId) -> a screen with open (a coroutine),
--     callback(inp) -> 0 | a number for loopTask | the next menu's id, loopTask, frame, draw, free.
--     Opened on black with the header slid up; the way out runs the original's: the header back
--     down, the left headers hidden, then MAIN_MENU_CURSOR_ON_MATCH_CALL / CONDITION_MENU. The
--     tutorial's forced call and the condition search's graph stay the game's
--   - Ruby / Sapphire (src.ui.game3.rs.pokenav.*): a feature object, frame(inp) -> "exit" when done,
--     draw(); Trainer's Eyes only when it has trainers (the game's own empty answer otherwise)
--
--   Pn = Pokenav(engine, deps)   deps: open(appId, session, onClose) -> true (our host up) ;
--                                enabled() -> the takeover wanted ; log
--   Pn.install() (at game.ready) -> true

return function(engine, deps)
  local Pn = {}
  local EXIT_TASK = 99

  local function log(fmt, ...) if deps.log then deps.log(fmt, ...) end end
  local function on() return not deps.enabled or deps.enabled() ~= false end

  -- the wrap of `mod.new`, once per process
  local function wrap(name, impl)
    local mod = engine(name)
    if not (mod and type(mod.new) == "function") then return false end
    local w = rawget(mod, "__woobOs")
    if not w then
      w = { orig = mod.new }
      mod.__woobOs = w
      mod.new = function(...)
        local f = w.impl
        if f then
          local ok, got = pcall(f, w.orig, ...)
          if ok and got then return got end
          if not ok then log("the PokéNav's app failed: %s", tostring(got)) end
        end
        return w.orig(...)
      end
    end
    w.impl = impl
    return true
  end

  -- ------- Emerald: a stand-in screen

  local Em = {}
  Em.__index = Em
  local function emScreen(shell, app, back, slideBack)
    return setmetatable({ shell = shell, session = shell.session, app = app, back = back, slideBack = slideBack }, Em)
  end
  function Em:open()
    local me = self
    local ok, opened = pcall(deps.open, self.app, self.session, function() me.closed = true end)
    if not (ok and opened) then
      if not ok then log("the PokéNav's %s failed to open: %s", self.app, tostring(opened)) end
      self.closed = true
    end
  end
  function Em:callback()
    if self.exitReady then return self.back end
    if self.closed and not self.leaving then
      self.leaving = true
      return EXIT_TASK
    end
    return 0
  end
  function Em:loopTask(func)
    if func ~= EXIT_TASK then return end
    -- (as the game's screen leaves: black, the header back, the left headers hidden)
    local shell = self.shell
    pcall(shell.fade, shell, "to_black")
    local slide = self.slideBack and shell:slideHeader(false) or nil
    coroutine.yield()
    while shell:fadeActive() or (slide and shell:busy(slide)) do coroutine.yield() end
    if self.slideBack ~= "condition" then pcall(shell.hideLeftHeaders, shell) end
    self.exitReady = true
  end
  function Em:frame() end
  function Em:draw() end
  function Em:free() end

  -- ------- Ruby / Sapphire: a stand-in feature

  local Rs = {}
  Rs.__index = Rs
  local function rsFeature(session, app, entries)
    return setmetatable({ session = session, app = app, entries = entries or {} }, Rs)
  end
  function Rs:frame()
    if not self.opened then
      self.opened = true
      local me = self
      local ok, opened = pcall(deps.open, self.app, self.session, function() me.done = true end)
      if not (ok and opened) then return "exit" end
    end
    if self.done then return "exit" end
  end
  function Rs:draw()
    local G = love and love.graphics
    if G then
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", 0, 0, 240, 160)
      G.setColor(1, 1, 1, 1)
    end
  end
  function Rs:help() return nil end
  function Rs:close() end

  function Pn.install()
    local n = 0
    local Nav = engine("src.ui.game3.rse.pokenav.init")
    local MENU = Nav and Nav.MENU or {}
    local MODE = Nav and Nav.MODE or {}
    -- (Emerald's Match Call: not in the tutorial's forced call)
    if wrap("src.ui.game3.rse.pokenav.match_call", function(orig, shell, menuId)
      if not on() or not shell then return nil end
      if shell.mode ~= nil and shell.mode ~= (MODE.NORMAL or 0) then return nil end
      return emScreen(shell, "phone", MENU.MAIN_MENU_CURSOR_ON_MATCH_CALL or "main_menu_cursor_on_match_call", true)
    end) then n = n + 1 end
    -- (Emerald's Condition: the party's graph; the search's stays the game's)
    if wrap("src.ui.game3.rse.pokenav.condition", function(orig, shell, menuId)
      if not on() or not shell or menuId ~= (MENU.CONDITION_GRAPH_PARTY or "condition_graph_party") then return nil end
      return emScreen(shell, "condition", MENU.CONDITION_MENU or "condition_menu", "condition")
    end) then n = n + 1 end
    -- (Ruby / Sapphire's Trainer's Eyes: our Phone when there are trainers)
    if wrap("src.ui.game3.rs.pokenav.eyes", function(orig, session, game, man, region)
      if not on() then return nil end
      local o = orig(session, game, man, region)
      if not (o and o.entries and #o.entries > 0) then return o end
      return rsFeature(session, "phone", o.entries)
    end) then n = n + 1 end
    -- (Ruby / Sapphire's Condition: the party's graph)
    if wrap("src.ui.game3.rs.pokenav.condition", function(orig, session, rows, index, category)
      if not on() or rows ~= nil then return nil end
      return rsFeature(session, "condition")
    end) then n = n + 1 end
    return n > 0
  end

  Pn.EXIT_TASK = EXIT_TASK
  return Pn
end
