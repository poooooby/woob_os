-- One of the game's own shop counters as the Mart window's model (the window in shop mode, full screen:
-- src/apps/mart.lua with ctx.shop): that shop's goods only, at its prices, bought by its game's rules (the
-- per-game piece hands them in: src/realshop.lua on Gen 3, src/gb/realshop.lua on the Game Boy games);
-- selling as the app's own Mart model sells (half price, nothing the game won't buy). The same interface
-- as src/mart.lua, so the window is the same, plus what a counter is: its place, its look, buy-only
-- shops (herbs, the pharmacy, the bargain stall, decorations), one-of-each stalls.
--
--   Sp = shop(spec)   spec: base (the app's model: money, inBag, sell, sellRows) ; rows { { id, price, name,
--                     desc, pocket (its tab, when the stock is long), soldOut, decor } } ; buy(s, row, qty) ->
--                     ok, bonus | reason ; buyOnly ; oneEach (a bargain stall: one of each, then sold out) ;
--                     maxQty ; title (the place) ; sub (the floor or the kind of shop) ; theme
--                     (src/shop_themes.lua) ; tabKey (a short stock's one tab: a word of lang/*.lua) ;
--                     close() (the shop's end, as the game's own: the TV's Smart Shopper ...) ; clerk (the
--                     counter's own clerk's sprite, as env.clerk() answers)
--   (the interface: src/mart.lua's) ; Sp.shop = true ; Sp.title, Sp.sub, Sp.theme, Sp.buyOnly, Sp.oneEach

local LONG = 10 -- (more goods than this: a tab for each pocket)

return function(spec)
  local base = spec.base
  local Sp = { shop = true, MAX_QTY = spec.oneEach and 1 or (spec.maxQty or 99), title = spec.title,
               sub = spec.sub, theme = spec.theme, buyOnly = spec.buyOnly == true, oneEach = spec.oneEach == true,
               kind = spec.kind, clerk = spec.clerk }

  -- the shelves: one tab, or one a pocket in the order they first come
  local tabs = {}
  local rows = spec.rows or {}
  for _, r in ipairs(rows) do r.badges = 0 end
  if #rows > LONG then
    local byPocket = {}
    for _, r in ipairs(rows) do
      local p = r.pocket or "ITEMS"
      local t = byPocket[p]
      if not t then
        t = { key = "pocket." .. p, rows = {} }
        byPocket[p] = t
        tabs[#tabs + 1] = t
      end
      t.rows[#t.rows + 1] = r
    end
  end
  if #tabs < 2 then tabs = { { key = spec.tabKey or "app.mart", rows = rows } } end
  function Sp.tabs() return tabs end
  function Sp.badges() return 0 end

  function Sp.money(s) return base.money(s) end
  function Sp.inBag(s, id) return base.inBag(s, id) end
  function Sp.sell(s, id, qty) return base.sell(s, id, qty) end
  function Sp.sellRows(s, pocket) return base.sellRows(s, pocket) end
  function Sp.price(id)
    for _, r in ipairs(rows) do if r.id == id then return r.price end end
    return nil
  end

  function Sp.buy(s, id, qty)
    local row
    for _, r in ipairs(rows) do if r.id == id then row = r end end
    if not row or row.soldOut then return false, "gone" end
    if Sp.oneEach then qty = 1 end
    local ok, got = spec.buy(s, row, qty)
    if ok and Sp.oneEach then row.soldOut = true end
    return ok, got
  end

  function Sp.close() if spec.close then pcall(spec.close) end end
  return Sp
end
