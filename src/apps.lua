-- The apps on the desktop: a registry other mods can add to (mod.exports.apps), and the built-in
-- ones: Oak's PC and Hall of Fame open the game's own PC screens; Boxes, Items, Mail, Mart and
-- Settings are our own windows; Decorate (Ruby / Sapphire / Emerald, the bedroom) opens the game's
-- Decoration menu.
--
--   A = Apps(deps)   deps: boxes / items / mail / mart / gts / auction / slots / settings = window(ctx, env) makers ;
--                    auctionBadge(ctx) / gtsBadge(ctx) -> n ; decorate(ctx) (the
--                    game's menu). Built-ins name themselves with labelKey (a lang/*.lua key)
--   A.register(app) -> true | false, why    app = {
--       id       unique string
--       label    under its icon (short: about 10 letters) ; labelKey: a word of lang/*.lua instead
--       glyph    the icon's picture: "ball" | "bag" | "mail" | "cart" | "rocket" | "slots" | "globe" | "home" | "trophy" | "dex" |
--                "power" | "logo" | "gear",
--                or a function(K, cx, cy, size, a) drawing it (window pixels, white on the tile)
--       color    { r, g, b } the tile's colour
--       order    sorts the apps (lower first; built-ins 10..90)
--       dock     true: in the dock, not the home grid
--       watch    false: not on WoobWatch (src/watch.lua shows only apps with a window)
--       badge(ctx) -> n   a count on the icon's corner (read once a second; nil / 0: none)
--       available(ctx) -> bool   (nil: always)
--       open(ctx)                ctx below; an app ends with ctx.finish / ctx.done / its own screen
--       window(ctx, env) -> win  instead of open: a window in the desktop's screen (src/desktop.lua)
--                win = { title, draw(body, clock, portrait), input(input, nav) -> handled,
--                        tap(arg, x, y), scroll(dyUnits, x, y), hints() -> { { key, words } }, close(),
--                        pointer(phase, x, y) (units; takes presses, moves, hover and releases itself,
--                        -> true for a release it used), pad = true (the shelf's pad lit) }
--                draw adds its hits as K.addHit(rect, "win", arg); nav = { up, down, left, right }
--                (repeating); env = { K, session(), se(name), now(), itemIcon(id, x, y, size),
--                monIcon(species, x, y, size), inv, mb, mart, amount(n, x, y, size, c, measure)
--                (money with the game's sign -> its width) } }
--   A.list(ctx) -> the available apps, sorted ; A.byId(id)
--
--   ctx (handed by the desktop): session ; mode ("select": a Pokémon Center PC's menu, "bedroom":
--   the player's own PC, "watch": WoobWatch, anywhere) ; family ("frlg" | "rse") ; row(id) -> the PC menu's row index for one of
--   the game's own rows ("storage", "player", "oak", "hall", "quit") or nil ; finish(result) hands
--   a row back to the game's PC script and closes the desktop ; done() closes the desktop as
--   cancelled ; over(open) opens one of the game's screens over the desktop (open(onClose)), the
--   desktop back when it closes ; original(opts) the same for the game's own PC menu
--   (pc_menu.show) ; sheet(kind) shows one of the desktop's sheets ("about", "logoff")

return function(deps)
  deps = deps or {}
  local A = { apps = {} }
  local byId = {}

  function A.register(app)
    if type(app) ~= "table" or type(app.id) ~= "string" or app.id == "" then return false, "no id" end
    if type(app.open) ~= "function" and type(app.window) ~= "function" then return false, "no open()" end
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

  -- the Pokémon Storage System (SOMEONE'S / BILL'S / LANETTE'S PC): our own window, the party and
  -- every box; the game's own screens when it can't be made
  A.register({ id = "storage", labelKey = "app.storage", label = "Boxes",
               glyph = "ball", color = { 226, 70, 72 }, order = 10, dock = true,
               available = function(ctx)
                 -- (on the watch: our window, there's no PC script to hand a row)
                 if ctx.mode == "watch" then return deps.boxes ~= nil end
                 return ctx.mode == "select" and ctx.row("storage") ~= nil
               end, window = deps.boxes,
               open = not deps.boxes and toRow("storage") or nil })
  -- the player's PC, our own: item storage (PC | Bag) and the mailbox (an inbox)
  if deps.items then
    A.register({ id = "items", labelKey = "app.items", label = "Items",
                 glyph = "bag", color = { 74, 150, 236 }, order = 20, dock = true,
                 window = deps.items })
  end
  if deps.mail then
    A.register({ id = "mail", labelKey = "app.mail", label = "Mail",
                 glyph = "mail", color = { 64, 178, 236 }, order = 25, dock = true,
                 window = deps.mail })
  end
  -- the Mart: the Poké Mart's goods into the Bag (more with each Gym Badge), the Bag's items sold
  if deps.mart then
    A.register({ id = "mart", labelKey = "app.mart", label = "Mart",
                 glyph = "cart", color = { 72, 190, 120 }, order = 27,
                 window = deps.mart })
  end
  -- GTS: the Global Trade Station and Wonder Trade, with trainers from around the world (a count on
  -- its icon: a deposit traded, waiting to be collected)
  if deps.gts then
    A.register({ id = "gts", labelKey = "app.gts", label = "GTS",
                 glyph = "globe", color = { 30, 120, 220 }, order = 26,
                 window = deps.gts, badge = deps.gtsBadge })
  end
  -- R-Bay: Team Rocket's auctions for Pokémon (a count on its icon: ended auctions not looked at)
  if deps.auction then
    A.register({ id = "auction", labelKey = "app.auction", label = "R-Bay",
                 glyph = "rocket", color = { 196, 30, 44 }, order = 28,
                 window = deps.auction, badge = deps.auctionBadge })
  end
  -- Rocket Slots: a slot machine played with money, and a prize corner for its tickets
  if deps.slots then
    A.register({ id = "slots", labelKey = "app.slots", label = "Slots",
                 glyph = "slots", color = { 232, 168, 32 }, order = 29,
                 window = deps.slots })
  end
  -- the bedroom's Decoration (Ruby / Sapphire / Emerald): the game's own menu
  if deps.decorate then
    A.register({ id = "decorate", labelKey = "app.decorate", label = "Decorate",
                 glyph = "home", color = { 156, 112, 220 }, order = 50,
                 available = function(ctx) return ctx.mode == "bedroom" and ctx.family == "rse" end,
                 open = deps.decorate })
  end
  A.register({ id = "oak", labelKey = "app.oak", label = "Oak's PC",
               glyph = "dex", color = { 232, 120, 64 }, order = 30,
               available = hasRow("oak"), open = toRow("oak") })
  A.register({ id = "hall", labelKey = "app.hall", label = "Hall of Fame",
               glyph = "trophy", color = { 236, 176, 48 }, order = 40,
               available = hasRow("hall"), open = toRow("hall") })
  if deps.settings then
    A.register({ id = "settings", labelKey = "app.settings", label = "Settings", glyph = "gear",
                 color = { 132, 140, 158 }, order = 70, window = deps.settings })
  end
  A.register({ id = "about", labelKey = "app.about", label = "About",
               glyph = "logo", color = { 70, 76, 96 }, order = 80, watch = false,
               open = function(ctx) ctx.sheet("about") end })
  A.register({ id = "logoff", labelKey = "app.logoff", label = "Log Off",
               glyph = "power", color = { 120, 128, 146 }, order = 90, dock = true, watch = false,
               open = function(ctx) ctx.sheet("logoff") end })

  return A
end
