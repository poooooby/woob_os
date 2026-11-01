-- The apps on the desktop: a registry other mods can add to (mod.exports.apps), and the built-in
-- ones, which open the game's own PC screens.
--
--   A = Apps()
--   A.register(app) -> true | false, why    app = {
--       id       unique string
--       label    under its icon (short: about 10 letters)
--       glyph    the icon's picture: "ball" | "bag" | "trophy" | "dex" | "power" | "logo" | "gear",
--                or a function(K, cx, cy, size, a) drawing it (window pixels, white on the tile)
--       color    { r, g, b } the tile's colour
--       order    sorts the apps (lower first; built-ins 10..90)
--       dock     true: in the dock, not the home grid
--       available(ctx) -> bool   (nil: always)
--       open(ctx)                ctx below; an app ends with ctx.finish / ctx.done / its own screen }
--   A.list(ctx) -> the available apps, sorted ; A.byId(id)
--
--   ctx (handed by the desktop): session ; mode ("select": a Pokémon Center PC's menu, "bedroom":
--   the player's own PC) ; family ("frlg" | "rse") ; row(id) -> the PC menu's row index for one of
--   the game's own rows ("storage", "player", "oak", "hall", "quit") or nil ; finish(result) hands
--   a row back to the game's PC script and closes the desktop ; done() closes the desktop as
--   cancelled ; original(opts) opens the game's own PC menu (pc_menu.show) over the desktop, which
--   comes back when it closes ; sheet(kind) shows one of the desktop's sheets ("about", "logoff")

return function()
  local A = { apps = {} }
  local byId = {}

  function A.register(app)
    if type(app) ~= "table" or type(app.id) ~= "string" or app.id == "" then return false, "no id" end
    if type(app.open) ~= "function" then return false, "no open()" end
    if byId[app.id] then return false, "an app " .. app.id .. " is already registered" end
    app.label = tostring(app.label or app.id)
    app.order = tonumber(app.order) or 50
    app.color = type(app.color) == "table" and app.color or { 120, 130, 150 }
    byId[app.id] = app
    A.apps[#A.apps + 1] = app
    table.sort(A.apps, function(a, b)
      if a.order ~= b.order then return a.order < b.order end
      return a.id < b.id
    end)
    return true
  end
  function A.byId(id) return byId[id] end

  -- the apps this PC shows (a list made per opening, not per frame)
  function A.list(ctx)
    local out = {}
    for _, app in ipairs(A.apps) do
      local ok, yes = true, true
      if app.available then ok, yes = pcall(app.available, ctx) end
      if ok and yes then out[#out + 1] = app end
    end
    return out
  end

  -- ------- the built-ins

  local function hasRow(id) return function(ctx) return ctx.mode == "select" and ctx.row(id) ~= nil end end
  local function toRow(id) return function(ctx) ctx.finish(ctx.row(id)) end end

  -- the Pokémon Storage System: the game's own (SOMEONE'S / BILL'S / LANETTE'S PC)
  A.register({ id = "storage", label = "Boxes", glyph = "ball", color = { 226, 70, 72 }, order = 10, dock = true,
               available = hasRow("storage"), open = toRow("storage") })
  -- the player's PC: item storage (and the mailbox, decorations in Ruby / Sapphire / Emerald)
  A.register({ id = "items", label = "Items", glyph = "bag", color = { 74, 150, 236 }, order = 20, dock = true,
               available = function(ctx)
                 return ctx.mode == "bedroom" or (ctx.mode == "select" and ctx.row("player") ~= nil)
               end,
               open = function(ctx)
                 if ctx.mode == "select" then return ctx.finish(ctx.row("player")) end
                 -- (the bedroom: the game's own player's PC menu, back to the desktop after)
                 ctx.original({ startMode = "player_pc", bedroom = true })
               end })
  A.register({ id = "oak", label = "Oak's PC", glyph = "dex", color = { 232, 120, 64 }, order = 30,
               available = hasRow("oak"), open = toRow("oak") })
  A.register({ id = "hall", label = "Hall of Fame", glyph = "trophy", color = { 236, 176, 48 }, order = 40,
               available = hasRow("hall"), open = toRow("hall") })
  A.register({ id = "about", label = "About", glyph = "logo", color = { 70, 76, 96 }, order = 80,
               open = function(ctx) ctx.sheet("about") end })
  A.register({ id = "logoff", label = "Log Off", glyph = "power", color = { 120, 128, 146 }, order = 90, dock = true,
               open = function(ctx) ctx.sheet("logoff") end })

  return A
end
