-- The nurse's sprite for the Pokémon Center (assets/nurse.png, by InnerMobius): a sheet of 4 x 4 frames,
-- 34 x 36 pixels each, the rows facing down, left, right and up, four steps each. Loaded the first time
-- it's asked for (nearest filter, for whole-pixel scaling), its frames cut with it; nil without it.
--
--   nurse = art(mod) ; nurse() -> { image, quads (0 .. 15: row * 4 + step), w = 34, h = 36 } | nil

local W, H = 34, 36

return function(mod)
  local got = nil
  return function()
    if got == nil then
      got = false
      local LG = love and love.graphics
      local ok, img = pcall(mod.assets.image, mod.assets, "assets/nurse.png")
      if ok and img and LG and LG.newQuad then
        pcall(img.setFilter, img, "nearest", "nearest")
        local iw, ih = img:getDimensions()
        local quads = {}
        for row = 0, 3 do
          for step = 0, 3 do quads[row * 4 + step] = LG.newQuad(step * W, row * H, W, H, iw, ih) end
        end
        got = { image = img, quads = quads, w = W, h = H }
      end
    end
    return got or nil
  end
end
