-- The Game Boy games' Pokémon pictures for the windows: a species' menu icon and its front picture, in its
-- own colours. The game's art is 2-bit grey, coloured by a palette shader when it's drawn (Gen 1 PaletteFX
-- with the species' palette, Gen 2 GbcPalette with its colours), so each one is painted once, in colour, into
-- a canvas of its own and kept: the windows then draw it like any picture, at any size, every frame without
-- a shader or a table. A path goes through the engine's own Sprites seams, so another mod's art (a sprite
-- pack) is what's painted. Without canvases (headless) the grey art is kept as it is.
--
--   Art = art(host, Gd)
--   Art.icon(sp, mon) -> { image, frames, w = 16, h = 16, quads } | nil   (kept per species / egg)
--   Art.pic(sp, mon) -> { image, w, h } | nil  (kept per species and shininess)
--   Art.drawIcon(sp, x, y, size, frame, r, g, b, a, mon)   (units, through the kit)
--   Art.drawPic(sp, x, y, size, a, mon) -> true when drawn
--   Art.forget() (the data changed: everything painted again)

return function(H, Gd, K)
  local Art = {}
  local engine = H.engine
  local floor = math.floor

  local icons, pics = {}, {}
  local ICON_FILL = 0.72
  function Art.forget() icons, pics = {}, {} end

  local function image(path)
    local Assets = engine("src.render.Assets")
    if not (Assets and path) then return nil end
    local ok, img = pcall(Assets.image, path)
    return ok and img or nil
  end

  -- the species' colours: four { r, g, b } (0..255) lightest first, or nil
  local function colours(sp, shiny)
    local d = Gd.data()
    if not d then return nil end
    if Gd.gen == 2 then
      local Pal = engine("src.world.gen2.Palettes")
      local ok, c = pcall(Pal and Pal.monColors or error, d.gen2Palettes, sp, shiny)
      return ok and c or nil
    end
    local Fx = engine("src.render.PaletteFX")
    local ok, c = pcall(Fx and Fx.monPal or error, d, sp)
    return ok and c or nil
  end

  -- paint `img` (a quad of it, or all of it) into a new canvas w x h in the species' colours; nil without
  -- canvases (the caller keeps the grey image)
  local function paint(img, w, h, sp, shiny, trueColor, drawFn)
    local G = love and love.graphics
    if not (G and G.newCanvas) then return nil end
    local okC, canvas = pcall(G.newCanvas, w, h)
    if not (okC and canvas) then return nil end
    pcall(canvas.setFilter, canvas, "nearest", "nearest")
    local cols = not trueColor and colours(sp, shiny) or nil
    G.push("all")
    local ok = pcall(function()
      G.setCanvas(canvas)
      G.origin()
      G.setScissor()
      G.clear(0, 0, 0, 0)
      G.setColor(1, 1, 1, 1)
      if cols and Gd.gen == 2 then
        local Gbc = engine("src.render.GbcPalette")
        if Gbc and Gbc.available and Gbc.available() then
          Gbc.with(cols, drawFn)
          return
        end
      elseif cols then
        local Fx = engine("src.render.PaletteFX")
        local sh = Fx and Fx.shader and Fx.shader()
        if sh then
          G.setShader(sh)
          Fx.sendColors(sh, cols)
          drawFn()
          G.setShader()
          return
        end
      end
      drawFn()
    end)
    G.pop()
    return ok and canvas or nil
  end

  -- ------- icons

  local function iconPath(sp, mon)
    local d = Gd.data()
    if not d then return nil end
    local Sprites = engine("src.pokemon.Sprites")
    local who = mon or { species = sp }
    if Gd.gen == 2 then
      local set = d.gen2Icons
      if not set then return nil end
      local id = Gd.isEgg(mon) and "ICON_EGG" or (set.species and set.species[sp])
      local entry = id and set.icons and set.icons[id]
      local path = entry and entry.image
      if Sprites and Sprites.iconPath and path then
        local ok, p, tc = pcall(Sprites.iconPath, d, who, path, { name = id })
        if ok and p then return p, tc end
      end
      return path, false
    end
    local set = d.icons
    if not set then return nil end
    local def = Gd.def(sp)
    local entry = (set.bySpecies and set.bySpecies[sp]) or (def and def.icon)
    local name, path, tc
    if type(entry) == "string" then
      name, path = entry, set.icons and set.icons[entry]
    elseif type(entry) == "table" then
      path, tc = entry.image, entry.trueColor
    end
    if not path then
      name = def and def.dex and set.byDex and set.byDex[def.dex]
      path = name and set.icons and set.icons[name]
    end
    if Sprites and Sprites.iconPath and path then
      local ok, p, t2 = pcall(Sprites.iconPath, d, who, path, { name = name, trueColor = tc })
      if ok and p then return p, t2 end
    end
    return path, tc
  end

  function Art.icon(sp, mon)
    local egg = Gd.isEgg(mon)
    local key = egg and "EGG" or sp
    if not key then return nil end
    local got = icons[key]
    if got ~= nil then return got or nil end
    got = false
    local path, tc = iconPath(sp, mon)
    local img = image(path)
    if img then
      local iw, ih = img:getDimensions()
      local frames = math.max(1, floor(ih / 16))
      local fw = math.min(iw, 16)
      local G = love and love.graphics
      local painted = paint(img, fw, frames * 16, sp, false, tc, function() G.draw(img, 0, 0) end)
      local src = painted or img
      local sw, sh = src:getDimensions()
      local quads = {}
      for f = 0, frames - 1 do quads[f] = G.newQuad(0, f * 16, fw, 16, sw, sh) end
      got = { image = src, frames = frames, w = fw, h = 16, quads = quads }
    end
    icons[key] = got
    return got or nil
  end

  -- (units through the kit; r, g, b, a: a tint, the Pokédex's dark silhouettes)
  function Art.drawIcon(sp, x, y, size, frame, r, g, b, a, mon)
    local e = Art.icon(sp, mon)
    if not e then return end
    local q = e.quads[(frame or 0) % e.frames] or e.quads[0]
    local G = K.graphics()
    G.setColor(r or 1, g or 1, b or 1, a or 1)
    -- (the Game Boy's icons fill their 16 px; the windows' cells are made for Gen 3's, a 32 px picture with
    -- a margin round it: these are drawn the size those look)
    local s = size * ICON_FILL
    local o = (size - s) / 2
    G.draw(e.image, q, K.X(x + o), K.Y(y + o + size * 0.04), 0, s * K.sc / e.w, s * K.sc / e.h)
  end

  -- ------- front pictures

  function Art.pic(sp, mon)
    local shiny = mon ~= nil and Gd.shiny(mon) or false
    local egg = Gd.isEgg(mon)
    if egg then return nil end
    local byShiny = pics[sp]
    if not byShiny then
      byShiny = {}
      pics[sp] = byShiny
    end
    local k = shiny and 2 or 1
    local got = byShiny[k]
    if got ~= nil then return got or nil end
    got = false
    local d = Gd.data()
    local Sprites = engine("src.pokemon.Sprites")
    local path, tc
    if d and Sprites and Sprites.path then
      local ok, p, t2 = pcall(Sprites.path, d, sp, "front", { kind = "box", mon = mon })
      if ok then path, tc = p, t2 end
    end
    local img = image(path)
    if img then
      local iw, ih = img:getDimensions()
      -- (a sheet of frames side by side or stacked: its first square)
      local s = math.min(iw, ih)
      local G = love and love.graphics
      local quad = (iw ~= ih) and G.newQuad(0, 0, s, s, iw, ih) or nil
      -- (in the games' 7 x 7 tile box, 56 px: a small Pokémon stays small, centred on its feet)
      local box = math.max(56, s)
      local ox, oy = floor((box - s) / 2), box - s
      local painted = paint(img, box, box, sp, shiny, tc, function()
        if quad then G.draw(img, quad, ox, oy) else G.draw(img, ox, oy) end
      end)
      if painted then
        got = { image = painted, w = box, h = box }
      elseif not quad then
        got = { image = img, w = s, h = s }
      end
    end
    byShiny[k] = got
    return got or nil
  end

  function Art.drawPic(sp, x, y, size, a, mon)
    local pic = Art.pic(sp, mon)
    if not pic then return false end
    local G = K.graphics()
    local k = size * K.sc / (pic.w or 56)
    G.setColor(1, 1, 1, a or 1)
    G.draw(pic.image, K.X(x), K.Y(y), 0, k, k)
    return true
  end

  return Art
end
