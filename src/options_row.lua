-- A WOOBOS row in the game's OPTIONS menu (every game), straight to this mod's own options: the engine's mod
-- manager opened on WoobOS's options page, so B there comes back to OPTIONS. Added through the engine's
-- ui.options.rows hook (others' rows kept: next() first, ours on the end, which lands it under MODS).
-- The manager: Gen 3 its own screen (src.ui.game3.mod_manager.show, the manager in ._mgr); the Game Boy
-- games the shared one pushed by src.ui.Screens ("ManagerState", entered as it's pushed). Either way
-- ManagerState:openOptions(the mod's entry), its way back emptied (goBack then leaves the manager).
--
--   install(mod, require) -- once, at load; `require` finds an engine module (looked up when chosen only)

local LABEL, VALUE = "WOOBOS", "OPTIONS"

return function(mod, req)
  if not (mod and mod.hooks and mod.hooks.wrap) then return end
  local modId = mod.id or "woob_os"

  local function find(name)
    local ok, m = pcall(req, name)
    return ok and m or nil
  end

  local function open(game)
    local m
    local MM = (mod.generation == nil or mod.generation == 3) and find("src.ui.game3.mod_manager") or nil
    if MM and MM.show then
      MM.show({ game = game })
      m = MM._mgr
    else
      local Screens = find("src.ui.Screens")
      m = Screens and Screens.push and Screens.push(game, "ManagerState") or nil
    end
    if not (m and m.openOptions) then return end
    local entry = m.byId and m.byId[modId]
    if not entry then return end
    m:openOptions(entry)
    if m.screen == "options" then m.backStack = {} end
  end

  -- (how many options, as the mod list says it -- "12 OPTIONS": the schema the engine loaded when it has it,
  -- which is only once the mod manager has been open; before that, the rows of our own options.lua, counted
  -- once here)
  local counted, fromFile = nil, VALUE
  do
    local okR, src = pcall(mod.read, mod, "options.lua")
    if okR and type(src) == "string" then
      local n = 0
      for _ in src:gmatch("key%s*=%s*[\"']") do n = n + 1 end
      if n > 0 then fromFile = n .. " " .. VALUE end
    end
  end
  local function value(game)
    if counted then return counted end
    local loader = type(game) == "table" and game.mods or nil
    local schema = loader and loader.optionSchemas and loader.optionSchemas[modId]
    if type(schema) ~= "table" then return fromFile end
    local n = 0
    for _, row in ipairs(schema) do if type(row) == "table" and type(row.key) == "string" then n = n + 1 end end
    counted = n > 0 and (n .. " " .. VALUE) or fromFile
    return counted
  end
  local function activate(game)
    local ok, err = pcall(open, game)
    if not ok then mod.log:warn("the options' WOOBOS row: %s", tostring(err)) end
  end

  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    out[#out + 1] = { id = modId, label = LABEL, value = value, activate = activate }
    return out
  end)
end
