-- The game's moments we stage ourselves, in place of its own screens (FireRed, LeafGreen, Ruby, Sapphire,
-- Emerald), each under Modern Menus with a switch of its own:
--   "evolution"  EvolutionScene.start -> src/apps/evolution.lua over src/evolve.lua
--   "catch"      the Pokédex's page after a first catch (FireRed / LeafGreen's Pokedex.showRegistration,
--                Ruby / Sapphire / Emerald's showCaughtMon) and the naming screen for a Pokémon (its CAUGHT_MON
--                and NICKNAME templates) -> src/apps/caught.lua over src/caught.lua
-- Each wrap is made once per process (`__woobOs*` on the module, the mod instance's code swapped in per load)
-- and falls back on the game's own screen when ours can't open: the option off, the scene host busy, no window.
--
--   Sc = Scenes(engine, deps)   deps: Sh, on(kind) -> bool, evolve (src/evolve.lua), caught (src/caught.lua),
--                               family() -> "frlg" | "rse", log
--   Sc.wrap() (at game.ready) ; Sc.nickFor(mon) -> the catch.nickname hook's answer, or nil

return function(engine, deps)
  local Sc = {}
  local Sh, Ev, Cg = deps.Sh, deps.evolve, deps.caught
  local function log(fmt, ...) if deps.log then pcall(deps.log, fmt, ...) end end
  local function on(kind) return deps.on == nil or deps.on(kind) == true end
  local function session()
    local Runtime = engine("src.core.game3.runtime")
    local ok, s = pcall(function() return Runtime.getSession() end)
    return ok and s or nil
  end

  -- -> true when ours took it
  function Sc.evolution(mon, post, opts)
    opts = opts or {}
    if not on("evolution") or opts.headless or not (Ev and Sh.openScene) or Sh.sceneOpen() then return false end
    local job = Ev.job(mon, post, opts)
    if not job then return false end
    if not Sh.openScene("evolution", opts.session or session(), nil, { scene = job }) then
      job.abandon()
      return false
    end
    return true
  end

  function Sc.dexPage(sp, opts, family)
    if not on("catch") or not (Cg and Sh.openScene) or Sh.sceneOpen() then return false end
    local job = Cg.dex(sp, opts, family)
    if not job then return false end
    return Sh.openScene("caught", (opts and opts.session) or session(), nil, { scene = job }) == true
  end

  local NICK = { CAUGHT_MON = true, NICKNAME = true }
  -- -> the stand-in state (as Naming.open returns its own), or nil: the game's
  function Sc.naming(opts)
    opts = opts or {}
    if not NICK[opts.template] or opts.hold or not on("catch") or not (Cg and Sh.openScene) or Sh.sceneOpen() then
      return nil
    end
    local Naming = engine("src.ui.game3.naming")
    if not Naming then return nil end
    -- (the game's way of being open: its flag up, a state of its own that its callers compare against)
    local stand = { template = opts.template, onDone = opts.onDone, woobOs = true }
    local job = Cg.name(opts, stand)
    if not job then return nil end
    local StayMessage = engine("src.ui.game3.message")
    if StayMessage and StayMessage.closeStay then pcall(StayMessage.closeStay) end
    Naming.openFlag, Naming._state = true, stand
    if not Sh.openScene("caught", opts.session or session(), nil, { scene = job }) then
      Naming.openFlag, Naming._state = false, nil
      return nil
    end
    return stand
  end

  function Sc.nickFor(mon)
    if not Cg then return nil end
    return Cg.nickFor(mon)
  end

  -- (one wrap per function, made once: `key` on the module keeps the original and the code that takes it over)
  local function wrap(M, fname, key, impl)
    if type(M) ~= "table" or type(M[fname]) ~= "function" then return end
    local w = M[key]
    if not w then
      w = { orig = M[fname] }
      M[key] = w
      M[fname] = function(...)
        local cur = M[key]
        if cur.impl then
          local ok, took = pcall(cur.impl, ...)
          if not ok then
            if cur.log then pcall(cur.log, "a scene of ours failed to open: %s", tostring(took)) end
          elseif took then
            return took
          end
        end
        return cur.orig(...)
      end
    end
    w.impl, w.log = impl, function(fmt, ...) log(fmt, ...) end
  end

  function Sc.wrap()
    local Scene = engine("src.ui.game3.evolution_scene")
    wrap(Scene, "start", "__woobOsEvo", function(mon, post, opts) return Sc.evolution(mon, post, opts) end)
    local family = deps.family and deps.family() or "rse"
    if family == "frlg" then
      local Dex = engine("src.ui.game3.pokedex")
      wrap(Dex, "showRegistration", "__woobOsCaught", function(sp, opts) return Sc.dexPage(sp, opts, "frlg") end)
    else
      local Dex = engine("src.ui.game3.rse.pokedex")
      wrap(Dex, "showCaughtMon", "__woobOsCaught", function(sp, opts) return Sc.dexPage(sp, opts, "rse") end)
    end
    local Naming = engine("src.ui.game3.naming")
    wrap(Naming, "open", "__woobOsNick", function(opts) return Sc.naming(opts) end)
    -- (while the state is our stand-in, the game's own screen does nothing: whoever draws or ticks it while
    -- its flag is up -- another mod, a scene that draws its naming over itself -- finds nothing to do)
    local function ours() return type(Naming) == "table" and type(Naming._state) == "table" and Naming._state.woobOs end
    wrap(Naming, "draw", "__woobOsNickDraw", function() return ours() end)
    wrap(Naming, "update", "__woobOsNickUpdate", function() return ours() end)
    wrap(Naming, "handleInput", "__woobOsNickInput", function() return ours() end)
  end

  return Sc
end
