-- The Decorate app's model (Ruby / Sapphire / Emerald, the bedroom PC): the decorations the player
-- owns by the game's eight categories, each with where it is, and what can be done with it by the
-- game's own rules. Toss and Put Away happen here; placing is the game's own cursor in the room,
-- entered with the decoration already chosen and left as soon as it's over.
--
--   Dc = Decorate(engine)
--   Dc.list(s) -> { cats (1..8) = { cat, name, size, count, countText, room (dolls and cushions: can
--       go in the bedroom), items = { decor, cat, index, name, desc, where ("pc" | "room" | "base") } },
--       used, size (the room's) }
--   Dc.toss(s, item) -> true | nil ; Dc.putAway(s, item) -> true | nil
--   Dc.place(s, item, onDone)   the game's cursor; onDone() when it's placed or cancelled
--   Dc.picture(decor) -> image | nil   the decoration, painted once
--   Dc.reset()   (a new game: its pictures go)

return function(engine)
  local Dc = {}
  local function inv() return engine("src.core.game3.rse.decoration_inventory") end
  local function core() return engine("src.core.game3.rse.decoration") end
  local function base() return engine("src.core.game3.rse.secret_base") end
  local function rse() return engine("src.core.game3.rse.init") end
  local function screen() return engine("src.ui.game3.rse.decoration") end

  -- (the game's upper-case names, read like the rest of the desktop; TV stays TV)
  local function word(a, rest)
    if #rest < 2 then return a .. rest end
    return a:upper() .. rest:lower()
  end
  local function pretty(name) return (tostring(name or ""):gsub("(%a)([%w']*)", word)) end

  function Dc.list(s)
    local Inv, Core = inv(), core()
    local room = Core.context(s, true)
    local out = { cats = {}, used = 0, size = room.size }
    for i = 1, room.size do
      if room.items[i] ~= 0 then out.used = out.used + 1 end
    end
    for cat = 0, Inv.CATEGORY_COUNT - 1 do
      Inv.condense(cat, s)
      local inBase, inRoom = Core.inUse(s, cat)
      local list = Inv.inventories(s)[cat]
      local row = { cat = cat, name = pretty(Inv.categoryName(cat)), size = Inv.SIZES[cat], items = {},
                    room = cat == Core.CAT.DOLL or cat == Core.CAT.CUSHION }
      for i = 1, row.size do
        local info = list[i] ~= 0 and Inv.info(list[i])
        if info then
          row.items[#row.items + 1] = {
            decor = list[i], cat = cat, index = i, name = pretty(info.name),
            desc = tostring(info.description or ""):gsub("%s*\n%s*", " "),
            where = inBase[i] and "base" or (inRoom[i] and "room" or "pc"),
          }
        end
      end
      row.count = #row.items
      row.countText = row.count .. "/" .. row.size
      out.cats[cat + 1] = row
    end
    return out
  end

  -- the row still holds what the window thinks it does, and it isn't in use
  function Dc.toss(s, item)
    local Inv, Core = inv(), core()
    if Inv.inventories(s)[item.cat][item.index] ~= item.decor then return nil end
    if not Core.isInPc(s, item.cat, item.index) then return nil end
    Core.toss(s, item.cat, item.index)
    return true
  end

  -- back to the PC, and the room's dolls and cushions set out again as the game does after its own
  function Dc.putAway(s, item)
    local Core = core()
    if not Core.isSprite(item.decor) then return nil end
    local room = Core.context(s, true)
    for i = 1, room.size do
      if room.items[i] == item.decor then
        room.items[i], room.pos[i] = 0, 0
        local SB, R = base(), rse()
        SB.hideDecorationSprites(s)
        SB.initDecorationSprites(0, s)
        R.setVar("VAR_SECRET_BASE_INITIALIZED", 1, s)
        return true
      end
    end
    return nil
  end

  local function press(key)
    return { wasPressed = function(_, k) return k == key end, isDown = function() return false end }
  end
  local PRESS_A, PRESS_B = press("a"), press("b")

  -- The game's Decoration menu, walked past its first two lists: open, on the chosen decoration, and
  -- A. Back from the room it would show its list; it's closed there instead, on the black between.
  function Dc.place(s, item, onDone)
    local R, U = rse(), screen()
    local impl = R.system("decorationMenu", "DoPlayerRoomDecorationMenu")
    if not (impl and impl.open) then error("the game has no Decoration menu") end
    impl.open({ session = s, onClose = onDone })
    inv().condense(item.cat, s)
    U.msg = nil
    U.command, U.category, U.scroll, U.row = 0, item.cat, item.index - 1, 0
    U.state, U.view = "items", nil
    U.handleInput(PRESS_A)
    local mine = U._opts
    local started, orig = false, U.handleInput
    local function leave()
      U.handleInput = orig
      U.state = "actions"
      orig(PRESS_B)
    end
    if U.state ~= "fading" then return leave() end   -- (refused: the window checked, so never in play)
    function U.handleInput(input)
      if U._opts ~= mine then       -- (the game was reset under it)
        U.handleInput = orig
        return orig(input)
      end
      if U.mode then
        started = true
      elseif started then
        return leave()
      end
      return orig(input)
    end
  end

  local pics = {}
  function Dc.reset() pics = {} end

  local function paint(decor)
    local G = love and love.graphics
    if not (G and G.newCanvas) then return nil end
    local Core = core()
    local d = Core.info(decor)
    if not d then return nil end
    local spr, quad, ts, NT, cols, rows, w, h
    if d.permission == Core.PERM.SPRITE then
      spr = engine("src.core.game3.ow_sprites").getDraw(d.tiles[1])
      quad = spr and spr.quads and spr.quads[0]
      if not quad then return nil end
      w, h = spr.width, spr.height
    else
      NT = engine("src.core.game3.tileset_native")
      ts = NT.get(Core.ICON_PAIR)
      if not ts then return nil end
      cols, rows = Core.dims(decor)
      w, h = cols * 16, rows * 16
    end
    local canvas = G.newCanvas(w, h)
    local target = G.getCanvas()
    G.push("all")
    local ok = pcall(function()
      G.setCanvas(canvas)
      G.origin()
      G.setScissor()
      G.clear(0, 0, 0, 0)
      G.setColor(1, 1, 1, 1)
      if spr then
        G.draw(spr.image, quad, 0, 0)
      else
        for j = 0, rows - 1 do
          for i = 0, cols - 1 do
            local tile = d.tiles[j * cols + i + 1] or 0
            local img = Core.layerType(tile) == 1 and ts.midImage or ts.overImage
            local q = img and NT.quad(ts, NT.slotFor(ts, tile + Core.PRIMARY))
            if q then G.draw(img, q, i * 16, j * 16) end
          end
        end
      end
    end)
    G.setCanvas(target)   -- (before the pop: it restores the scissor against whichever is bound)
    G.pop()
    if not ok then return nil end
    -- (kept as an image: a canvas comes back blank after the window's mode changes)
    local img = G.newImage(canvas:newImageData())
    img:setFilter("nearest", "nearest")
    return img
  end

  function Dc.picture(decor)
    local got = pics[decor]
    if got == nil then
      local ok, img = pcall(paint, decor)
      got = ok and img or false
      pics[decor] = got
    end
    return got or nil
  end

  return Dc
end
