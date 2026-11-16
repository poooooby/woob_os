-- The Game Boy games' Pokémon pictures for the windows: a species' menu icon and its front picture, in its
-- own colours. The game's art is 2-bit grey, coloured by a palette shader when it's drawn (Gen 1 PaletteFX
-- with the species' palette, Gen 2 GbcPalette with its colours), so each one is painted once, in colour, into
-- a canvas of its own and kept: the windows then draw it like any picture, at any size, every frame without
-- a shader or a table. A path goes through the engine's own Sprites seams, so another mod's art (a sprite
-- pack) is what's painted. Without canvases (headless) the grey art is kept as it is. With WoobleSpritePack
-- (g9-battle-sprites-gen3) its own art instead, for every Pokémon it has art for: its party icons (as its HD
-- party screen shows them: our windows draw icons that big) and its front pictures (the windows its first
-- frame, the Pokédex its animation).
--
--   Art = art(host, Gd, K, deps)   deps.pack() -> WoobleSpritePack's exports while it's active, else nil
--   Art.icon(sp, mon) -> { image, frames, w = 16, h = 16, quads } | nil   (kept per species / egg)
--   Art.pic(sp, mon) -> { image, w, h, box } | nil  (kept per species and shininess; drawn w x h at the
--                       bottom middle of a box x box square)
--   Art.livePic(sp) -> the same, the pack's animation now (asked 16 times a second) | nil without the pack
--   Art.drawIcon(sp, x, y, size, frame, r, g, b, a, mon)   (units, through the kit)
--   Art.drawPic(sp, x, y, size, a, mon) -> true when drawn
--   Art.forget() (the data changed: everything painted again)

return function(H, Gd, K, deps)
  deps = deps or {}
  -- (Art.pack: the tests' seam)
  local Art = { pack = deps.pack }
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
  local function paint(img, w, h, sp, shiny, trueColor, drawFn, given)
    local G = love and love.graphics
    if not (G and G.newCanvas) then return nil end
    local okC, canvas = pcall(G.newCanvas, w, h)
    if not (okC and canvas) then return nil end
    pcall(canvas.setFilter, canvas, "nearest", "nearest")
    local cols = given or (not trueColor and colours(sp, shiny)) or nil
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
    K.rescissor()
    return ok and canvas or nil
  end

  -- an overworld sprite's whole sheet painted once in four colours (lightest first): the Mart's clerk
  function Art.colourSheet(img, cols)
    if not (img and cols) then return nil end
    local w, h = img:getDimensions()
    local G = love and love.graphics
    return paint(img, w, h, nil, nil, false, function() G.draw(img, 0, 0) end, cols)
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

  -- ------- WoobleSpritePack's icons: both frames asked once per Pokémon (or species) and kept, asked
  -- again a second later (the pack may have rebuilt its atlas); nil where it has none (an Egg)
  local packByMon = setmetatable({}, { __mode = "k" })
  local packBySp = {}
  local REASK = 5
  local function clock() return love and love.timer and love.timer.getTime() or 0 end
  -- (the pack itself looked for once a second, for every icon)
  local packEx, packAt, packFn = nil, -1, nil
  local function packNow(now)
    if packFn ~= Art.pack or now - packAt >= 1 then
      packFn, packAt = Art.pack, now
      local ok, ex = pcall(Art.pack or error)
      packEx = ok and type(ex) == "table" and (ex.iconArt16 or ex.frontArt) and ex or nil
    end
    return packEx
  end
  local function packIcon(sp, mon)
    if not Art.pack or Gd.isEgg(mon) then return nil end
    local now = clock()
    local ex = packNow(now)
    if not ex then return nil end
    local e
    if mon then e = packByMon[mon] else e = packBySp[sp] end
    if e and now - e.at < REASK then return e.ok and e or nil end
    local fn = ex.iconArt16
    e = e or {}
    e.at, e.ok = now, false
    if fn then
      local who = mon or { species = sp }
      local ok0, q0, img, cell = pcall(fn, who, 0)
      local ok1, q1 = pcall(fn, who, 1)
      K.rescissor()
      if ok0 and type(q0) == "table" and q0.full and img and tonumber(cell) then
        e.ok, e.image, e.cell = true, img, tonumber(cell)
        e[0] = q0.full
        e[1] = ok1 and type(q1) == "table" and q1.full or q0.full
      end
    end
    if mon then packByMon[mon] = e else packBySp[sp] = e end
    return e.ok and e or nil
  end

  -- (units through the kit; r, g, b, a: a tint, the Pokédex's dark silhouettes)
  function Art.drawIcon(sp, x, y, size, frame, r, g, b, a, mon)
    local p = packIcon(sp, mon)
    if p then
      -- (the pack's: a 32 px cell with a margin round it, as Gen 3's icons are)
      local G = K.graphics()
      G.setColor(r or 1, g or 1, b or 1, a or 1)
      local k = size * K.sc / p.cell
      G.draw(p.image, p[(frame or 0) % 2], K.X(x), K.Y(y), 0, k, k)
      return
    end
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

  -- WoobleSpritePack's: its first frame at 1:1, kept (asked again every few seconds, as its icons are);
  -- its animation for the Pokédex, the frame playing now asked 16 times a second (each frame is a canvas
  -- the pack keeps). A margin round the art, as the game's pictures have in their 56 px box
  local PACK_MARGIN, PACK_EVERY = 1.25, 1 / 16
  local stillByMon = setmetatable({}, { __mode = "k" })
  local stillBySp = {}
  local function packStill(sp, mon)
    if not Art.pack or Gd.isEgg(mon) then return nil end
    local now = clock()
    local ex = packNow(now)
    if not (ex and ex.frontArt) then return nil end
    local e
    if mon then e = stillByMon[mon] else e = stillBySp[sp] end
    if e and now - e.at < REASK then return e.ok and e or nil end
    e = e or {}
    e.at, e.ok = now, false
    local ok, img, w, h = pcall(ex.frontArt, mon or { species = sp })
    K.rescissor()
    if ok and img and tonumber(w) and tonumber(h) then
      e.ok, e.image, e.w, e.h = true, img, tonumber(w), tonumber(h)
      e.box = math.max(e.w, e.h) * PACK_MARGIN
    end
    if mon then stillByMon[mon] = e else stillBySp[sp] = e end
    return e.ok and e or nil
  end
  local live = { sp = nil, at = -1, ctx = { natural = true, side = "front", mon = nil }, who = {},
                 pic = { image = nil, w = 0, h = 0, box = 0 }, ok = false }
  function Art.livePic(sp)
    if not Art.pack then return nil end
    local now = clock()
    local ex = packNow(now)
    if not ex then return nil end
    if live.sp ~= sp or now - live.at >= PACK_EVERY then
      live.sp, live.at, live.ok = sp, now, false
      live.who.species = sp
      live.ctx.mon = live.who
      local img
      if ex.monPic then
        local ok, got = pcall(ex.monPic, live.ctx)
        K.rescissor()
        img = ok and got or nil
      end
      if img and img.getDimensions then
        local w, h = img:getDimensions()
        local pic = live.pic
        pic.image, pic.w, pic.h, pic.box = img, w, h, math.max(w, h) * PACK_MARGIN
        live.ok = true
      end
    end
    if live.ok then return live.pic end
    -- (its animation off: the first frame)
    return packStill(sp, nil)
  end

  function Art.pic(sp, mon)
    local shiny = mon ~= nil and Gd.shiny(mon) or false
    local egg = Gd.isEgg(mon)
    if egg then return nil end
    local p = packStill(sp, mon)
    if p then return p end
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
        got = { image = painted, w = box, h = box, box = box }
      elseif not quad then
        got = { image = img, w = s, h = s, box = s }
      end
    end
    byShiny[k] = got
    return got or nil
  end

  function Art.drawPic(sp, x, y, size, a, mon)
    local pic = Art.pic(sp, mon)
    if not pic then return false end
    local G = K.graphics()
    local box = pic.box or pic.w or 56
    local k = size * K.sc / box
    G.setColor(1, 1, 1, a or 1)
    -- (at the bottom middle of the square)
    G.draw(pic.image, K.X(x) + (box - pic.w) / 2 * k, K.Y(y) + (box - pic.h) * k, 0, k, k)
    return true
  end

  return Art
end
