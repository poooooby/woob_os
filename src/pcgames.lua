-- PC Games (the "PC Games" mod, id pc_solitaire) inside WoobOS. That mod opens itself with its own
-- exports.openGames, which pushes one layer on the engine's UI stack: { draw, handleInput, update }.
-- For that one call the stack's push is stood in for and the layer is kept here instead, so a window
-- can draw it into a picture and feed it the buttons; nothing of the mod is copied or changed. When
-- it closes itself it pops its layer: the pop is watched only while its own code runs here.
--
-- It has no way to be told to close from outside, so closing the window only pauses it: the layer is
-- kept and the next open carries on. It starts afresh at game.ready, as the mod does (H.reset).
--
--   H = PcGames(engine, deps)   deps: find() -> that mod | nil ; game() -> the engine's game ; log
--   H.find (swapped by tests) ; H.game
--   H.available() ; H.open() -> true (kept, new or carried on) | false (it opened some other way, or not)
--   H.input(input) ; H.tick(dt) -> "closed" when it closed itself ; H.draw() ; H.reset()

return function(engine, deps)
  local H = { find = deps.find, game = deps.game }
  local ID = "pc_solitaire"
  local layer, closed, complained = nil, false, false

  local function log(fmt, ...) if deps.log then deps.log(fmt, ...) end end
  local function stack() return engine("src.ui.game3.stack") end
  local function exportsOf()
    local m = H.find and H.find()
    local ex = m and m.exports
    return type(ex) == "table" and type(ex.openGames) == "function" and ex or nil
  end

  function H.available() return exportsOf() ~= nil end
  function H.reset() layer, closed = nil, false end

  function H.open()
    if layer then return true end
    local ex, S, game = exportsOf(), stack(), H.game and H.game()
    if not (ex and S and game) then return false end
    local push, caught = S.push, nil
    S.push = function(id, m, opts)
      if id == ID and type(m) == "table" and type(m.draw) == "function" and type(m.handleInput) == "function"
        and type(m.update) == "function" then
        caught = m
        return
      end
      -- (anything else, or a shape we don't know: as it would have been, on top of the desktop)
      return push(id, m, opts)
    end
    local ok, err = pcall(ex.openGames, game)
    S.push = push
    if not ok then log("PC Games failed to open: %s", tostring(err)) end
    layer, closed = caught, false
    return layer ~= nil
  end

  -- the mod's own code, with its pop watched (no closures: this runs every frame)
  local realPop
  local function watchedPop(id, ...)
    if id == ID then
      closed = true
      return true
    end
    return realPop(id, ...)
  end
  local function run(fn, arg)
    local S = stack()
    realPop = S.pop
    S.pop = watchedPop
    local ok, err = pcall(fn, arg)
    S.pop = realPop
    if not ok and not complained then
      complained = true
      log("PC Games failed: %s", tostring(err))
    end
    if closed then
      layer, closed = nil, false
      return "closed"
    end
  end

  function H.input(input) if layer then return run(layer.handleInput, input) end end
  function H.tick(dt) if layer then return run(layer.update, dt) end end
  function H.draw()
    if not layer then return end
    local ok, err = pcall(layer.draw)
    if not ok and not complained then
      complained = true
      log("PC Games failed to draw: %s", tostring(err))
    end
  end
  return H
end
