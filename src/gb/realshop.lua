-- The real shops on the Game Boy games: a shop counter opens our Mart full screen (Sh.openFull, the window
-- in shop mode with that counter's model, src/shop.lua) in place of the game's shop screen, both pushed by
-- id through the screen registry (mod.content.screens), so ours is registered under the same ids:
--   Red / Blue / Yellow  "ShopMenu", new(game, stock, onQuit): stock = the clerk's item ids; the talk path
--                        gives no onQuit (the field goes on by itself), a script's resumes it; ours pops itself
--   Gold / Silver / Crystal  "Gen2MartMenu", new(game, opts): opts.martType (STANDARD, BITTER the herb shop,
--                        BARGAIN the Underground's stall, PHARMACY; Crystal's rooftop sale as STANDARD, as
--                        the engine has it), opts.martId, opts.marts, opts.onClose (it pops the screen on
--                        top: ours must be)
-- Ours is a carrier state: its first update opens the Mart over it; when the Mart closes, the game hears
-- what its own screen would say. The goods are the game's list for that counter (MartMenu.inventory /
-- bargainRows), at the game's prices (the bargain stall's own, one of each, wBargainShopFlags kept as the
-- engine keeps them); bought as the game's shop buys (the money first, then the Bag's room). Selling is
-- the Mart app's (half price; the Bank takes what the wallet can't). The herb shop, the pharmacy and the
-- bargain stall only sell. With the option off, or anything failing: the game's own screen.
--
--   Gs = realshop(H, Gd, deps)   deps: Sh (the shell) ; base (env.mart) ; T ; makeShop ; themes ; clerk() ;
--                                place(mapId) -> its name ; on() -> the Real Shops option ; log ; screens
--                                (mod.content.screens)
--   Gs.install() (load: the screens) ; Gs.make(kind, list, opts) -> the counter's model (the tests')

return function(H, Gd, deps)
  local engine = H.engine
  local gen = H.gen
  local Gs = {}
  local Th = deps.themes

  local GB_POCKET = { ITEM = "ITEMS", BALL = "POKE_BALLS", KEY_ITEM = "KEY_ITEMS", TM_HM = "TM_CASE" }
  local function stack() local g = H.game(); return g and g.stack or nil end

  -- where the counter is: the map's id (CELADON_MART_4F), the place's name
  local function where()
    local g = H.game()
    local id
    if gen == 2 then
      local m = g and g.world and g.world.map
      id = m and (m.id or (m.def and m.def.id))
    else
      -- (the map's constant id, CELADON_MART_4F, before its label, CeladonMart4F)
      local m = g and g.overworld and g.overworld.map
      local cid = m and (type(m.id) == "string" and m.id or (m.def and type(m.def.id) == "string" and m.def.id))
      id = cid or (m and m.def and m.def.label) or (m and m.id)
    end
    id = tostring(id or "")
    local name = deps.place and deps.place(id) or nil
    if name == id then name = nil end
    return id, name
  end
  local function floorText(fl)
    if fl == "rooftop" then return nil end
    return fl
  end

  local function money(s) return Gd.money(s) end
  local function bag() return engine("src.inventory.Bag") end

  -- kind: "mart" | "herb" | "pharmacy" | "bargain" | "rooftop"; list: item ids, or (bargain) { item, price }
  function Gs.make(kind, list, opts)
    opts = opts or {}
    local s = H.session()
    if not (s and deps.base and deps.makeShop) then return nil end
    local rows, names = {}, {}
    local sold = kind == "bargain" and (s.bargainShop or {}) or {}
    for _, e in ipairs(list or {}) do
      local id = type(e) == "table" and (e.item or e.id or e[1]) or e
      local it = id and Gd.item(id)
      if it then
        local price = kind == "bargain" and tonumber(type(e) == "table" and (e.price or e[2])) or tonumber(it.price)
        price = math.max(0, math.floor(price or 0))
        rows[#rows + 1] = { id = id, price = price, name = Gd.itemName(id), desc = Gd.itemDesc(id),
                            pocket = gen == 2 and GB_POCKET[it.pocket or "ITEM"] or "ITEMS", soldOut = sold[id] == true }
        names[#names + 1] = rows[#rows].name
      end
    end
    if #rows == 0 then return nil end
    local buy = function(s2, row, qty)
      local cost = row.price * qty
      if cost > money(s2) then return false, "money" end
      local B = bag()
      if not (B and B.add(s2, row.id, qty, Gd.data())) then return false, "bag_full" end
      if kind == "bargain" then
        s2.bargainShop = s2.bargainShop or {}
        s2.bargainShop[row.id] = true
      end
      Gd.setMoney(s2, money(s2) - cost)
      return true, false
    end
    local mapId, place = where()
    local theme, kindKey = Th.pick({ map = mapId, kind = kind, names = names })
    local T = deps.T
    local sub = T and T("shop.kind." .. kindKey) or kindKey
    local fl = floorText(Th.floor(mapId))
    local title = place or (T and T("app.mart")) or "Mart"
    if fl and (kindKey == "dept" or kindKey == "decor") and not title:upper():find(fl, 1, true) then
      sub = sub .. " · " .. fl
    end
    return deps.makeShop({
      base = deps.base, rows = rows, buy = buy, kind = kindKey, theme = theme, sub = sub, tabKey = "shop.goods",
      title = title, buyOnly = kind ~= "mart" and kind ~= "rooftop",
      oneEach = kind == "bargain", clerk = deps.clerk and deps.clerk() or nil,
    })
  end

  -- the carrier: the screen the game pushed; its first update opens the Mart over it
  local function carrierUpdate(self)
    if self.done then return end
    if self.opened then
      if not (deps.Sh and deps.Sh.hostOpen and deps.Sh.hostOpen()) then self.finish() end
      return
    end
    self.opened = true
    local ok, got = pcall(self.open)
    if not (ok and got) then
      if not ok and deps.log then deps.log("the shop failed to open: %s", tostring(got)) end
      self.done = true
      local stk = stack()
      if stk and stk:top() == self then pcall(stk.pop, stk) end
      local okB, screen = pcall(self.fallback)
      if okB and screen and stk then stk:push(screen) end
    end
  end
  local function noDraw() end
  local function carrier(model, finish, fallback)
    local c = { isMenu = true, update = carrierUpdate, draw = noDraw, isOpaque = false }
    c.finish = function()
      if c.done then return end
      c.done = true
      finish(c)
    end
    c.fallback = fallback
    c.open = function()
      return deps.Sh.openFull("mart", H.session(), c.finish, nil, { mode = "shop", shop = model, backKey = "hint.close" })
    end
    return c
  end
  local function wanted() return deps.Sh and deps.Sh.openFull and (not deps.on or deps.on()) end

  local TYPES = { [0] = "STANDARD", [1] = "BITTER", [2] = "BARGAIN", [3] = "PHARMACY", [4] = "ROOFTOP" }
  local KIND = { STANDARD = "mart", BITTER = "herb", BARGAIN = "bargain", PHARMACY = "pharmacy", ROOFTOP = "rooftop" }

  function Gs.install()
    local reg = deps.screens
    if not (reg and reg.register) then return false end
    if gen == 1 then
      reg:register("ShopMenu", { new = function(game, stock, onQuit)
        local M = engine("src.ui.ShopMenu")
        local function builtin() return M.new(game, stock, onQuit) end
        if not wanted() then return builtin() end
        local okM, model = pcall(Gs.make, "mart", stock)
        if not (okM and model) then return builtin() end
        return carrier(model, function(c)
          local stk = stack()
          if stk and stk:top() == c then pcall(stk.pop, stk) end
          if onQuit then onQuit() end
        end, builtin)
      end })
      return true
    end
    reg:register("Gen2MartMenu", { new = function(game, opts)
      opts = opts or {}
      local M = engine("src.ui.gen2.MartMenu")
      local function builtin() return M.new(game, opts) end
      if not wanted() then return builtin() end
      local t = opts.martType
      local name = type(t) == "string" and t:upper() or TYPES[tonumber(t) or 0] or "STANDARD"
      local kind = KIND[name] or "mart"
      local okL, list
      if kind == "bargain" then
        okL, list = pcall(M.bargainRows, opts.marts)
      else
        okL, list = pcall(M.inventory, opts.marts, tonumber(opts.martId) or 0)
      end
      if not okL then return builtin() end
      local okM, model = pcall(Gs.make, kind, list)
      if not (okM and model) then return builtin() end
      return carrier(model, function()
        -- (the World's onClose pops the screen on top: ours, now the Mart has gone)
        if opts.onClose then opts.onClose() end
      end, builtin)
    end })
    return true
  end

  return Gs
end
