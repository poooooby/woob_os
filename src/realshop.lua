-- The real shops on FireRed / LeafGreen / Ruby / Sapphire / Emerald: every shop counter's `pokemart` (and
-- Ruby / Sapphire / Emerald's `pokemartdecoration`) opens the game's shop screen through
-- src.ui.game3.shop_menu's show(opts) (opts: items, session, onClose; the VM waits until onClose). That
-- show is wrapped once per process (ShopMenu.__woobOs, as the PC's); with the Real Shops option on, our
-- Mart opens full screen instead (Sh.openFull, the window in shop mode with the shop's own model,
-- src/shop.lua): that counter's goods at its prices, bought as the game's own shop buys them -- the Bag's
-- room, the money; Ruby / Sapphire / Emerald's Premier Ball with ten Poké Balls, its "shopped" game stat,
-- the TV's Smart Shopper (the purchases told on the way out, as the game's quit does), Slateport's half
-- price while the PokéNews says so, the decoration shops one at a time into the PC's decorations;
-- FireRed / LeafGreen's quest log. Selling is the Mart app's own (half price, nothing important). The
-- counter's place and floor name it (the map's section, as the name popup has it), and its look is
-- src/shop_themes.lua's for that place and its goods. opts.onClose() exactly once when it closes;
-- anything failing: the game's own shop.
--
--   Rs = realshop(engine, deps)   deps: Sh (the shell: openFull) ; base (env.mart) ; T ; on() -> the option ;
--                                 place(mapId) -> a map's name (the save menu's) ;
--                                 clerk() -> the Mart clerk's sprite (env.clerk) ; log(fmt, ...)
--   Rs.wrap() (at game.ready) ; Rs.open(opts) -> true when ours opened (the wrap's, and the tests')
--   Rs.make(opts) -> the shop's model (src/shop.lua) or nil

return function(engine, deps)
  local Rs = {}
  local makeShop = deps.makeShop
  local Th = deps.themes

  local function session() local R = engine("src.core.game3.runtime"); return R and R.getSession and R.getSession() end
  local function family()
    local Profile = engine("src.core.game3.profile")
    local ok, P = pcall(Profile and Profile.forSession or error, session())
    return ok and type(P) == "table" and P.family or "frlg", ok and P and tostring(P.id or "") or ""
  end
  local function const(s, kind, name)
    local Constants, Profile = engine("src.core.game3.constants"), engine("src.core.game3.profile")
    local ok, id = pcall(function() return Constants.of(Profile.forSession(s).id):id(kind, name) end)
    return ok and id or nil
  end

  -- "CELADON CITY" -> "Celadon City" (the game's capitals as a name)
  local function titled(s)
    s = tostring(s or ""):gsub("{[^}]*}", "")
    return (s:gsub("(%a)([%w'é]*)", function(a, rest) return a:upper() .. rest:lower() end))
  end

  -- where the counter is: the map's id, its place's name, the floor
  local function where()
    local Map = engine("src.core.game3.map")
    local def = Map and Map.currentDef and Map.currentDef() or nil
    local mapId = tostring(def and (def.id or def.name) or (Map and Map.current) or "")
    local secId = def and (def.regionMapSectionId or def.region_map_section_id or def.mapsec)
    local floorNum = def and tonumber(def.floorNum or def.floor_num or def.floor) or 0
    local MS = engine("src.import.gba.map_sections_extract")
    local okI, info = pcall(MS and MS.getInfo or error, secId, mapId, floorNum)
    local name = okI and type(info) == "table" and info.resolved ~= false and info.name or nil
    -- (else the save menu's name for it, as the News has it)
    if not name and deps.place then
      local okP, n = pcall(deps.place, mapId)
      if okP and n and n ~= "" then return mapId, n, floorNum end
    end
    return mapId, name and titled(name) or nil, floorNum
  end
  local function floorText(n)
    n = tonumber(n) or 0
    if n == 127 then return deps.T and deps.T("shop.rooftop") or "Rooftop" end
    if n < 0 then return string.format("B%dF", -n) end
    if n > 0 then return string.format("%dF", n) end
    return nil
  end

  -- the counter's clerk: the one the player is talking to (the last talked-to object's own sprite), else
  -- the Mart's clerk
  local function clerkHere()
    local Flags, Objects, Ow = engine("src.core.game3.scripting.flags"), engine("src.core.game3.objects"),
      engine("src.core.game3.ow_sprites")
    local s = session()
    local var = const(s, "vars", "VAR_LAST_TALKED") or 0x800F
    local okV, lid = pcall(Flags and Flags.getVar or error, nil, nil, var)
    local eo = okV and Objects and Objects.find and Objects.find(tonumber(lid) or 0) or nil
    local gid = type(eo) == "table" and tonumber(eo.graphicsId) or nil
    if gid and Ow and Ow.getDraw then
      local okS, spr = pcall(Ow.getDraw, gid)
      if okS and type(spr) == "table" and spr.image and spr.quads then return spr end
    end
    return nil
  end

  -- the mart's own entry (its decoration kind), by the item list the VM handed over
  local function entryOf(items)
    local Marts = engine("src.core.game3.marts")
    for _, e in pairs(Marts and Marts._byKey or {}) do
      if type(e) == "table" and e.items == items then return e end
    end
    return nil
  end

  function Rs.make(opts)
    local s = opts.session or session()
    local items = opts.items or {}
    if not (s and #items > 0 and deps.base) then return nil end
    local fam = family()
    local rse = fam == "rse"
    local entry = entryOf(items)
    local mt = opts.martType or (entry and entry.martType)
    local decor = rse and mt ~= nil and mt ~= "NORMAL"
    local ItemsData, Bag = engine("src.core.game3.items_data"), engine("src.core.game3.bag")
    local Dec = decor and engine("src.core.game3.rse.decoration_inventory") or nil
    if not (ItemsData and Bag) or (decor and not Dec) then return nil end

    -- (Slateport's half price, while the PokéNews says so: as the game's own shop asks)
    local half = false
    if rse and not decor then
      local Tv, Rse = engine("src.core.game3.rse.tv"), engine("src.core.game3.rse.init")
      local ok, on = pcall(function()
        return Tv.isPokeNewsActive(s, 1, function(kind)
          return Rse.call("tv", "shouldApplyPokeNews", "ShouldApplyPokeNewsEffect", nil, kind) == true
        end)
      end)
      half = ok and on == true
    end

    local rows, names = {}, {}
    for _, id in ipairs(items) do
      local row
      if decor then
        local okD, d = pcall(Dec.info, id)
        if okD and type(d) == "table" then
          row = { id = id, price = tonumber(d.price) or 0, name = titled(d.name or tostring(id)),
                  desc = tostring(d.description or d.desc or ""), decor = id }
        end
      else
        local okI, info = pcall(ItemsData.info, id)
        if okI and type(info) == "table" then
          local p = math.max(0, math.floor(tonumber(info.price) or 0))
          if half then p = math.floor(p / 2) end
          local okP, pocket = pcall(ItemsData.pocketOf, id)
          local okDs, desc = pcall(ItemsData.description, id)
          desc = okDs and type(desc) == "string" and desc or tostring(info.description or "")
          desc = desc:gsub("\\n", " "):gsub("\\p", " "):gsub("\n", " ")
          row = { id = id, price = p, name = info.name or tostring(id), pocket = okP and pocket or "ITEMS",
                  desc = desc }
        end
      end
      if row then
        rows[#rows + 1] = row
        names[#names + 1] = row.name
      end
    end
    if #rows == 0 then return nil end

    local history = {}
    local SHOPPED = 38
    local function shopped()
      if not rse then return end
      if type(s.gameStats) ~= "table" then s.gameStats = {} end
      local n = math.floor(tonumber(s.gameStats[SHOPPED]) or 0)
      s.gameStats[SHOPPED] = n < 0xFFFFFF and n + 1 or 0xFFFFFF
    end
    local function remember(id, qty)
      for _, h in ipairs(history) do
        if h.itemId == id and h.quantity ~= 0 then
          h.quantity = math.min(255, h.quantity + qty)
          return
        end
      end
      if #history < 3 then history[#history + 1] = { itemId = id, quantity = qty } end
    end
    local function money() return math.max(0, math.floor(tonumber(s.money) or 0)) end

    local buy
    if decor then
      buy = function(s2, row)
        if row.price > money() then return false, "money" end
        local ok, added = pcall(Dec.add, row.id, s2)
        if not (ok and added) then return false, "decor_full" end
        s2.money = money() - row.price
        shopped()
        return true, false
      end
    else
      local BALL, PREMIER = const(s, "items", "ITEM_POKE_BALL"), const(s, "items", "ITEM_PREMIER_BALL")
      buy = function(s2, row, qty)
        local cost = row.price * qty
        if cost > money() then return false, "money" end
        local okC, can = pcall(Bag.canAdd, s2.bag, row.id, qty)
        if not (okC and can) then return false, "bag_full" end
        local okA, added = pcall(Bag.add, s2.bag, row.id, qty)
        if not (okA and added) then return false, "bag_full" end
        s2.money = money() - cost
        local bonus = false
        if rse then
          remember(row.id, qty)
          shopped()
          if BALL and PREMIER and row.id == BALL and qty >= 10 then
            local okP, got = pcall(Bag.add, s2.bag, PREMIER, 1)
            bonus = okP and got and true or false
          end
        else
          -- (the quest log: as FireRed / LeafGreen's own shop writes it)
          local Q, R = engine("src.core.game3.quest_log_recorder"), engine("src.core.game3.runtime")
          if Q and Q.event then
            pcall(function()
              Q.event(s2, qty == 1 and "BoughtItem" or "BoughtItemsIncludingItem",
                { D0 = Q.location(R and R._game, s2), D1 = ItemsData.displayName(row.id), D2 = cost })
            end)
          end
        end
        return true, bonus
      end
    end

    local mapId, place, floorNum = where()
    local kind = decor and "decor" or nil
    if mapId:upper():find("HERB", 1, true) then kind = "herb" end
    local theme, kindKey = Th.pick({ map = mapId, kind = kind or "mart", names = names })
    local T = deps.T
    local sub = T and T("shop.kind." .. kindKey) or kindKey
    local fl = floorText(floorNum)
    -- (Ruby / Sapphire / Emerald's maps carry no floor: the map's own name has it, "..._2F")
    if not fl then
      local f2 = Th.floor(mapId)
      if f2 and f2 ~= "rooftop" then fl = f2 end
    end
    -- (a floor for the stores with floors, unless the place's name has it already: FireRed's "Celadon Dept. 2F")
    local title = place or (T and T("app.mart")) or "Mart"
    if fl and (kindKey == "dept" or kindKey == "decor") and not title:upper():find(fl, 1, true) then
      sub = sub .. " · " .. fl
    end
    return makeShop({
      base = deps.base, rows = rows, buy = buy, buyOnly = decor, maxQty = decor and 1 or 99, kind = kindKey,
      title = title, sub = sub, theme = theme, tabKey = "shop.goods",
      clerk = clerkHere() or (deps.clerk and deps.clerk()) or nil,
      close = rse and not decor and function()
        local Rse = engine("src.core.game3.rse.init")
        if Rse and Rse.call then
          pcall(Rse.call, "tv", "tryPutSmartShopperOnAir", "TryPutSmartShopperOnAir", nil, history)
        end
      end or nil,
    })
  end

  function Rs.open(opts)
    if deps.on and not deps.on() then return false end
    local Sh = deps.Sh
    if not (Sh and Sh.openFull) then return false end
    local okM, model = pcall(Rs.make, opts)
    if not (okM and model) then
      if not okM and deps.log then deps.log("the shop couldn't be made: %s", tostring(model)) end
      return false
    end
    local closed = false
    local function onClose()
      if closed then return end
      closed = true
      model.close()
      if opts.onClose then opts.onClose() end
    end
    return Sh.openFull("mart", opts.session or session(), onClose, nil, { mode = "shop", shop = model,
                                                                          backKey = "hint.close" }) == true
  end

  -- (once per process; this instance's open swapped in)
  function Rs.wrap()
    local ShopMenu = engine("src.ui.game3.shop_menu")
    if not (ShopMenu and type(ShopMenu.show) == "function") then return false end
    local w = rawget(ShopMenu, "__woobOs")
    if not w then
      w = { orig = ShopMenu.show }
      ShopMenu.__woobOs = w
      ShopMenu.show = function(opts)
        local impl = w.impl
        if impl then
          local ok, opened = pcall(impl, opts or {})
          if ok and opened then return end
          if not ok and w.log then w.log("the shop failed to open: %s", tostring(opened)) end
        end
        return w.orig(opts)
      end
    end
    w.impl, w.log = Rs.open, deps.log
    return true
  end

  return Rs
end
