-- The Ribbons app's model: every Pokémon in the party and the boxes that wears a Ribbon, its Ribbons
-- in the game's own order, their words and pictures from the game's PokéNav data (Emerald's Condition
-- pack, Ruby / Sapphire's own). Read only.
--
--   Rb = Ribbons(engine, deps)   deps: family() -> "emerald" | "rs" | nil ; available(s)
--   Rb.available(s) ; Rb.list(s) -> rows { mon, box (nil: the party), slot, count } (most first)
--   Rb.ids(mon) -> normal ids, gift ids ; Rb.desc(s, id) -> its words | nil
--   Rb.contest(mon) -> { Cool, Beauty, Cute, Smart, Tough: ranks won, 0..4 }
--   Rb.icon(id, big) -> image, quad | nil, its size in pixels | nil

return function(engine, deps)
  deps = deps or {}
  local Rb = {}
  local function core() return engine("src.core.game3.rse.ribbons") end
  local function isRs() return deps.family and deps.family() == "rs" end

  local man
  local function manifest()
    if man ~= nil then return man end
    local ok, m
    if isRs() then
      ok, m = pcall(function() return engine("src.ui.game3.rs.pokenav.gfx").manifest("pokenav_ribbons") end)
    else
      ok, m = pcall(function() return engine("src.ui.game3.rse.pokenav.condition").manifest() end)
    end
    man = ok and m or false
    return man
  end

  function Rb.available(s) return deps.available ~= nil and deps.available(s) == true end

  function Rb.list(s)
    local C, out = core(), {}
    if not (C and s) then return out end
    C.forEachMon(s, function(mon, box, slot)
      local n = C.count(mon)
      if n > 0 then out[#out + 1] = { mon = mon, box = box, slot = slot, count = n, order = #out + 1 } end
    end)
    table.sort(out, function(a, b)
      if a.count ~= b.count then return a.count > b.count end
      return a.order < b.order
    end)
    return out
  end

  function Rb.ids(mon)
    local C, m = core(), manifest()
    if not (C and m) then return {}, {} end
    if not isRs() then return C.monRibbonIds(mon, m.ribbonData) end
    local normal, gift, id = {}, {}, 0
    for _, field in ipairs(m.fields) do
      local dst = id > 24 and gift or normal
      for j = 0, C.get(mon, field.name) - 1 do dst[#dst + 1] = id + j end
      id = id + field.count
    end
    return normal, gift
  end

  local CONTESTS = { "cool", "beauty", "cute", "smart", "tough" }
  function Rb.contest(mon)
    local C, out = core(), {}
    for i, k in ipairs(CONTESTS) do
      local ok, n = pcall(C.get, mon, k)
      out[i] = ok and tonumber(n) or 0
    end
    return out
  end

  -- (a gift Ribbon's words depend on the save's table of them)
  local words = {}
  local function join(lines, plain)
    if type(lines) ~= "table" then return nil end
    local out = {}
    for i = 1, #lines do out[i] = plain and plain(lines[i]) or tostring(lines[i]) end
    return (table.concat(out, " "):gsub("%s+", " "))
  end
  function Rb.desc(s, id)
    local C, m = core(), manifest()
    if not (C and m and id) then return nil end
    local lines, plain, key
    if isRs() then
      if id < 25 then lines, key = m.descriptions[id], id
      else
        local index = engine("src.core.game3.profiles.rs.pokenav").giftDescriptionIndex(s, id)
        if index == nil then return nil end
        lines, key = m.giftDescriptions[index], 1000 + index
      end
    else
      local Gfx = engine("src.ui.game3.rse.pokenav.gfx")
      plain = function(k) return Gfx.plain(k) end
      if id < 25 then lines, key = m.ribbonDescriptions[id], id
      else
        local v = C.giftRibbonAt(s, id)
        if v == 0 then return nil end
        lines, key = m.giftRibbonDescriptions[v - 1], 1000 + v
      end
    end
    local got = words[key]
    if got == nil then
      local ok, text = pcall(join, lines, plain)
      got = ok and text or false
      words[key] = got
    end
    return got or nil
  end

  local small, large = {}, {}
  function Rb.icon(id, big)
    local store = big and large or small
    local e = store[id]
    if e == nil then
      e = false
      local m = manifest()
      local ok, got = pcall(function()
        if not m then return nil end
        if isRs() then
          local img = engine("src.ui.game3.rs.pokenav.gfx").image(m.icons[id][big and "large" or "small"])
          return img and { img = img, size = img:getWidth() } or nil
        end
        local Gfx, gfx = engine("src.ui.game3.rse.pokenav.gfx"), m.ribbonGfx[id]
        local sp, size = m.sprites[big and "ribbonsBig" or "ribbonsSmall"], big and 32 or 16
        local img = gfx and Gfx.image(sp.png)
        if not img then return nil end
        local q = love.graphics.newQuad(gfx.pal * size, gfx.tile * size, size, size, img:getWidth(), img:getHeight())
        return { img = img, quad = q, size = size }
      end)
      if ok and got then e = got end
      store[id] = e
    end
    if not e then return nil end
    return e.img, e.quad, e.size
  end

  return Rb
end
