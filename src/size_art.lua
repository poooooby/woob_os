-- The Pokédex's Size tab's pictures: the trainer it measures a Pokémon against (assets/
-- brendan-height-sprite.png, a 40 x 70 silhouette, 1.7 m / 5'08") and where a picture's drawn pixels
-- are inside its sheet (its picture's own size, not its frame's, is what a height means).
--
--   Sz = sizeArt(mod, kit)
--   Sz.trainer() -> { image, light, w, h, u0, v0, u1, v1 } | nil   (loaded once; light: a white copy for
--                                                           the dark themes; u / v the drawn pixels' box,
--                                                           u1 / v1 one past them)
--   Sz.bounds(image) -> u0, v0, u1, v1 | nil                 (read back through a canvas: an action or a
--                                                           one-off per picture, never every frame;
--                                                           the kit's scissor set again after it)
--   Sz.TRAINER_M = 1.7 ; Sz.TRAINER_IN = 68 (inches)

local PATH = "assets/brendan-height-sprite.png"

return function(mod, Kit)
  local Sz = { TRAINER_M = 1.7, TRAINER_IN = 68 }

  -- (the drawn pixels' box in a picture's ImageData; nil when it's empty)
  local function scan(data, w, h)
    local u0, v0, u1, v1 = w, h, -1, -1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local _, _, _, a = data:getPixel(x, y)
        if a > 0.1 then
          if x < u0 then u0 = x end
          if x > u1 then u1 = x end
          if y < v0 then v0 = y end
          if y > v1 then v1 = y end
        end
      end
    end
    if u1 < 0 then return nil end
    return u0, v0, u1 + 1, v1 + 1
  end

  function Sz.bounds(img)
    local G = love and love.graphics
    if not (img and G and G.newCanvas) then return nil end
    local okW, w, h = pcall(img.getDimensions, img)
    if not (okW and w and h and w > 0 and h > 0) then return nil end
    local okC, c = pcall(G.newCanvas, w, h, { dpiscale = 1 })
    if not (okC and c) then return nil end
    G.push("all")
    local okD = pcall(function()
      G.origin()
      G.setScissor()
      G.setShader()
      G.setCanvas(c)
      G.clear(0, 0, 0, 0)
      G.setColor(1, 1, 1, 1)
      G.draw(img, 0, 0)
    end)
    G.setCanvas()
    G.pop()
    if Kit and Kit.rescissor then Kit.rescissor() end
    local okI, data = pcall(c.newImageData, c)
    pcall(c.release, c)
    if not (okD and okI and data) then return nil end
    local u0, v0, u1, v1 = scan(data, w, h)
    pcall(data.release, data)
    return u0, v0, u1, v1
  end

  local got = nil
  function Sz.trainer()
    if got == nil then
      got = false
      local ok, img = pcall(mod.assets.image, mod.assets, PATH)
      if ok and img then
        pcall(img.setFilter, img, "nearest", "nearest")
        local w, h = img:getDimensions()
        -- (its own pixels read from the file: no canvas needed)
        local u0, v0, u1, v1
        local LI, LG = love and love.image, love and love.graphics
        local okP, full = pcall(mod.assets.path, mod.assets, PATH)
        local okD, data = false, nil
        if okP and LI and LI.newImageData then okD, data = pcall(LI.newImageData, full) end
        if okD and data then u0, v0, u1, v1 = scan(data, w, h) end
        got = { image = img, w = w, h = h, u0 = u0 or 0, v0 = v0 or 0, u1 = u1 or w, v1 = v1 or h }
        -- (a white copy, its alpha kept: the silhouette drawn light on the dark themes)
        if okD and data and LG and LG.newImage then
          local okL, light = pcall(function()
            local copy = data:clone()
            copy:mapPixel(function(_, _, _, _, _, a) return 1, 1, 1, a end)
            local im = LG.newImage(copy)
            im:setFilter("nearest", "nearest")
            return im
          end)
          if okL then got.light = light end
        end
      end
    end
    return got or nil
  end

  return Sz
end
