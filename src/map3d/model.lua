-- The 3D map's model: the region made from the game's own Town Map. The picture of the Town Map
-- (its greens are shaded by height already) becomes a heightmap and its colours, sampled every
-- 2 pixels; the Town Map's grid (the sections a cursor reads) becomes the places: towns, routes,
-- landmarks, each with its cells, a name, a Center / Mart / Gym from the game's own list of maps
-- (the engine's map catalog: PewterCity_Mart ...) and the Gym's badge. Nothing here draws.
--
--   World units: one Town Map cell (8 pixels) each; x right, z down the picture, y up.
--   FireRed / LeafGreen: Kanto, Sevii 1-3, 4-5, 6-7 (each its own picture and grid); Ruby / Sapphire
--   / Emerald: Hoenn.
--
--   M = Model(engine, deps)   deps: pixels(img, x, y, w, h) -> sample(px, py) -> r, g, b (0..255) | nil
--                             (the picture read back; nil headless: the grid alone makes the land)
--   M.regions(family) -> { { id, key } }       M.region(id) -> the built region (kept)
--   M.live(region, session)   visited / Fly / badges read again (on open, once a second)
--   M.player(session) -> regionId, x, z        (world units, nil when unknown)
--   M.available(session, id) -> bool           (Sevii's pictures only once the game shows them)
--   M.flyCheck(session) -> mon | nil, reason   (the party's Fly, the badge, outdoors)
--   M.pickArgs(place) -> the arguments the game's own map hands its Fly callback
--   M.storm(region, session) -> { kind = "rain" (Kyogre) | "sand" (Groudon), place } | nil   (Emerald: where
--                              the Weather Institute's rumour is, read from the game's own variables)
--   M.weather(region, session) -> { { key, kind, place, x, z, rx, rz, y, y0 } }  (Ruby / Sapphire / Emerald:
--                              the everyday weather where the game's maps put it: kind = "rain" | "thunder" |
--                              "snow" | "fog" | "ash" | "sand" | "shade" | "clouds"; x, z its middle, rx, rz
--                              half its size, y the highest ground under it, y0 the ground's mean, world
--                              units; Route 119's and 123's cycles as they are today)
--   M.weatherData() -> maps, events, scripts   (what it's read from: the maps' definitions, the script
--                              bundle's events and scripts; the tests stand in for it)

local floor, max, min, abs, sqrt = math.floor, math.max, math.min, math.abs, math.sqrt

local STEP = 2          -- picture pixels per terrain sample
local SEA_Y = -0.18     -- the sea bed under the water (the water itself at 0)
local LAND_Y = 0.12     -- the lowest land
local HILL = 0.95       -- the greens' rise, darkest to lightest
local PEAK = 1.35       -- a mountain's own rise over the land
local BAR_Y = -0.04     -- a sea route's sandbar, just under the water

local FRLG_REGIONS = {
  { id = "kanto", key = "map.region.kanto", layout = 0, image = "kanto_map" },
  { id = "sevii123", key = "map.region.sevii123", layout = 1, image = "sevii123_map", flag = "FLAG_SYS_SEVII_MAP_123" },
  { id = "sevii45", key = "map.region.sevii45", layout = 2, image = "sevii45_map", flag = "FLAG_SYS_SEVII_MAP_4567" },
  { id = "sevii67", key = "map.region.sevii67", layout = 3, image = "sevii67_map", flag = "FLAG_SYS_SEVII_MAP_4567" },
}
local RSE_REGIONS = { { id = "hoenn", key = "map.region.hoenn" } }
-- (the part of each picture that is the map: FireRed's has a frame around it)
local CROP = { frlg = { 24, 16, 192, 144 }, rse = { 0, 0, 240, 160 } }
-- the sections that stand up as mountains (our own list)
local PEAKS = {
  MAPSEC_MT_MOON = 1, MAPSEC_ROCK_TUNNEL = 0.8, MAPSEC_KANTO_VICTORY_ROAD = 1.2, MAPSEC_MT_EMBER = 1.4,
  MAPSEC_CERULEAN_CAVE = 0.6, MAPSEC_ICEFALL_CAVE = 0.6, MAPSEC_SEAFOAM_ISLANDS = 0.5,
  MT_CHIMNEY = 1.5,
}
-- landmarks a cursor only finds once the game shows them (FireRed / LeafGreen)
local HIDDEN = {
  MAPSEC_NAVEL_ROCK = "FLAG_WORLD_MAP_NAVEL_ROCK_EXTERIOR", MAPSEC_BIRTH_ISLAND = "FLAG_WORLD_MAP_NAVEL_ROCK_EXTERIOR",
  MAPSEC_CERULEAN_CAVE = "FLAG_SYS_CAN_LINK_WITH_RS",
}
-- FireRed / LeafGreen's map types: 2 visited, 3 not yet (a town); Ruby / Sapphire / Emerald's: 2 can fly,
-- 3 can't (a town), 4 the Battle Frontier, 0 not shown
local FR_VISITED, FR_NOT_VISITED = 2, 3
local RS_NONE, RS_CANFLY, RS_CANTFLY, RS_FRONTIER = 0, 2, 3, 4

return function(engine, deps)
  deps = deps or {}
  local M = { STEP = STEP }
  local built = {}

  local function familyOf()
    local Profile = engine("src.core.game3.profile")
    local ok, P = pcall(Profile and Profile.forSession or error, nil)
    if ok and type(P) == "table" and P.family == "rse" then return "rse" end
    return "frlg"
  end
  M.family = familyOf

  -- "PEWTER CITY" -> "Pewter City" ; "POKéMON TOWER" -> "Pokémon Tower" ; "S.S. ANNE" kept dotted
  local function titled(s)
    s = tostring(s or "")
    return (s:gsub("(%a)([%w'é]*)", function(a, rest) return a:upper() .. rest:lower() end))
  end
  M.titled = titled
  -- "MAPSEC_PEWTER_CITY" or "PEWTER CITY" -> "PewterCity" (the game's map names)
  local function camel(s)
    s = tostring(s or ""):gsub("^MAPSEC_", ""):gsub("_POKECENTER$", "")
    local out = s:gsub("[^%w]+", " "):gsub("(%w)(%w*)", function(a, rest) return a:upper() .. rest:lower() end)
    return (out:gsub(" ", ""))
  end
  M.camel = camel

  -- the game's maps by name (PewterCity_Mart, RustboroCity_Gym ...), from the engine's catalog
  local function hasMap(name)
    local Catalog = engine("src.import.gba.map_catalog")
    local ok, known = pcall(Catalog and Catalog.isKnown or error, name)
    return ok and known == true
  end

  -- the game's badges: { num, flag, name, gym = "PEWTER" } (the trainer card's order)
  local function badgeList()
    local Flags, Profile = engine("src.core.game3.scripting.flags"), engine("src.core.game3.profile")
    if not Flags then return {} end
    local okP, P = pcall(Profile and Profile.forSession or error, nil)
    local okV, t = pcall(Flags.forVersion or error, okP and P and P.id or nil)
    local list = okV and type(t) == "table" and t.BADGES or Flags.BADGES
    return type(list) == "table" and list or {}
  end
  local function flagOn(id)
    if not id then return false end
    local Flags, Space = engine("src.core.game3.scripting.flags"), engine("src.core.game3.scripting.space")
    if not (Flags and Space and Space.store) then return false end
    local ok, v = pcall(Flags.getFlag, Space.store, nil, id)
    return ok and v == true
  end

  -- ------- the land: the picture -> heights and colours

  -- a sample's kind from its colour: "sea", "lane" (a sea route's darker blue), "land" (its green
  -- lightness the height), "path" (a route's yellow), "bridge" (a faded route's beige), nil (a
  -- marker, the frame: filled from around it)
  local function classify(r, g, b)
    if b > r + 20 and b >= g then
      if r > 140 and b > 240 then return "sea" end
      return "lane"
    end
    if g > r and g > b then
      local luma = r * 0.3 + g * 0.59 + b * 0.11
      return "land", min(1, max(0, (luma - 66) / 160))
    end
    if r > 170 and g > 120 and r >= g and b < 130 then return "path" end
    if r > 190 and g > 190 and b > 120 and b < 180 and abs(r - g) < 30 then return "bridge" end
    return nil
  end

  local function newTerrain(cols, rows)
    return { cols = cols, rows = rows, h = {}, kind = {}, r = {}, g = {}, b = {}, peak = {}, town = {} }
  end

  -- from the picture: each sample's kind, height and colour; unknown ones (markers) filled from their
  -- neighbours
  local function fromPicture(t, sample, crop)
    local cols, rows = t.cols, t.rows
    for j = 0, rows - 1 do
      for i = 0, cols - 1 do
        local k = j * cols + i + 1
        local r, g, b = sample(crop[1] + i * STEP + 1, crop[2] + j * STEP + 1)
        local kind, lift = nil, 0
        if r then kind, lift = classify(r, g, b) end
        t.kind[k] = kind or false
        if kind then t.r[k], t.g[k], t.b[k] = r / 255, g / 255, b / 255 end
        if kind == "land" then t.h[k] = LAND_Y + lift * HILL
        elseif kind == "sea" or kind == "lane" then t.h[k] = SEA_Y
        else t.h[k] = false end
      end
    end
  end

  -- headless (no picture): land under the grid's sections, sea elsewhere
  local function fromGrid(t, crop, cells)
    local cols, rows = t.cols, t.rows
    for j = 0, rows - 1 do
      for i = 0, cols - 1 do
        local k = j * cols + i + 1
        local wx, wz = (crop[1] + i * STEP) / 8, (crop[2] + j * STEP) / 8
        local near = false
        for _, c in ipairs(cells) do
          if abs(c[1] - wx) <= 1 and abs(c[2] - wz) <= 1 then
            near = true
            break
          end
        end
        t.kind[k] = near and "land" or "sea"
        t.h[k] = near and LAND_Y + 0.3 or SEA_Y
        if near then t.r[k], t.g[k], t.b[k] = 0.3, 0.7, 0.2 else t.r[k], t.g[k], t.b[k] = 0.6, 0.75, 1 end
      end
    end
  end

  local NB = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
  -- the samples with no height yet (paths, bridges, markers) take their neighbours'; with the sea
  -- around them, a route's yellow is a low bridge and a faded route's beige a sandbar under the water
  local function fill(t)
    local cols, rows = t.cols, t.rows
    for _ = 1, 24 do
      local left = 0
      local nh, nr, ng, nb = {}, {}, {}, {}
      for j = 0, rows - 1 do
        for i = 0, cols - 1 do
          local k = j * cols + i + 1
          if t.h[k] == false then
            local sum, n, sea, cr, cg, cb, cn = 0, 0, 0, 0, 0, 0, 0
            for _, d in ipairs(NB) do
              local ii, jj = i + d[1], j + d[2]
              if ii >= 0 and jj >= 0 and ii < cols and jj < rows then
                local kk = jj * cols + ii + 1
                local h = t.h[kk]
                if h then
                  sum, n = sum + h, n + 1
                  if h < 0 then sea = sea + 1 end
                end
                if t.r[kk] and not t.kind[k] then cr, cg, cb, cn = cr + t.r[kk], cg + t.g[kk], cb + t.b[kk], cn + 1 end
              end
            end
            if n > 0 then
              local h = sum / n
              local seaSide = sea * 2 >= n
              if t.kind[k] == "bridge" then
                h = seaSide and BAR_Y or max(h, LAND_Y * 0.6)
              elseif t.kind[k] == "path" then
                h = seaSide and 0.06 or max(h, LAND_Y * 0.6)
              end
              nh[k] = h
              if cn > 0 then nr[k], ng[k], nb[k] = cr / cn, cg / cn, cb / cn end
            else
              left = left + 1
            end
          end
        end
      end
      for k, h in pairs(nh) do
        t.h[k] = h
        if nr[k] then t.r[k], t.g[k], t.b[k] = nr[k], ng[k], nb[k] end
      end
      if left == 0 then break end
    end
    for k = 1, cols * rows do
      if t.h[k] == false then t.h[k] = SEA_Y end
      if not t.r[k] then t.r[k], t.g[k], t.b[k] = 0.6, 0.75, 1 end
      if not t.kind[k] then t.kind[k] = t.h[k] > 0 and "land" or "sea" end
    end
  end

  -- softened: a 3 x 3 average, twice (the picture's steps become slopes; paths keep their colour)
  local function smooth(t)
    local cols, rows = t.cols, t.rows
    for _ = 1, 2 do
      local out = {}
      for j = 0, rows - 1 do
        for i = 0, cols - 1 do
          local sum, n = 0, 0
          for dj = -1, 1 do
            for di = -1, 1 do
              local ii, jj = i + di, j + dj
              if ii >= 0 and jj >= 0 and ii < cols and jj < rows then
                sum, n = sum + t.h[jj * cols + ii + 1], n + 1
              end
            end
          end
          out[j * cols + i + 1] = sum / n
        end
      end
      t.h = out
    end
  end

  -- a mountain on a section's cells: a rounded cone, its top `rise` over the land
  local function raise(t, crop, cx, cz, rise)
    local cols, rows = t.cols, t.rows
    local rad = 1.0 + rise * 0.7
    for j = 0, rows - 1 do
      for i = 0, cols - 1 do
        local wx, wz = (crop[1] + i * STEP + 1) / 8, (crop[2] + j * STEP + 1) / 8
        local d = sqrt((wx - cx) ^ 2 + (wz - cz) ^ 2)
        if d < rad then
          local k = j * cols + i + 1
          if t.h[k] > 0 then
            local f = 1 - d / rad
            local add = PEAK * rise * f * f * (3 - 2 * f)
            t.h[k] = t.h[k] + add
            t.peak[k] = max(t.peak[k] or 0, f)
          end
        end
      end
    end
  end

  -- a town's cells made level (its houses stand on it): the mean of its land; a town mostly on the
  -- water (Pacifidlog) on boardwalks just over it. Each sample keeps its town (the ground's look)
  local function flatten(t, crop, place)
    local cols = t.cols
    local sum, n, all = 0, 0, 0
    local x0, z0 = place.x0, place.z0
    local i0, i1 = floor((x0 * 8 - crop[1]) / STEP), floor(((place.x1) * 8 - crop[1]) / STEP)
    local j0, j1 = floor((z0 * 8 - crop[2]) / STEP), floor(((place.z1) * 8 - crop[2]) / STEP)
    for j = max(0, j0), min(t.rows - 1, j1) do
      for i = max(0, i0), min(cols - 1, i1) do
        local h = t.h[j * cols + i + 1]
        all = all + 1
        if h > 0 then sum, n = sum + h, n + 1 end
      end
    end
    local level = n > 0 and max(LAND_Y, sum / n) or LAND_Y
    place.water = n < all * 0.35
    if place.water then level = 0.05 end
    for j = max(0, j0), min(t.rows - 1, j1) do
      for i = max(0, i0), min(cols - 1, i1) do
        local k = j * cols + i + 1
        t.h[k] = level
        t.town[k] = place
      end
    end
    place.y = level
  end

  -- ------- the places: the grid's sections

  local function addCell(places, byId, id, x, z, info)
    local p = byId[id]
    if not p then
      p = { id = id, cells = {}, x0 = x, z0 = z, x1 = x + 1, z1 = z + 1 }
      for k, v in pairs(info) do p[k] = v end
      byId[id] = p
      places[#places + 1] = p
    end
    p.cells[#p.cells + 1] = { x, z }
    p.x0, p.z0, p.x1, p.z1 = min(p.x0, x), min(p.z0, z), max(p.x1, x + 1), max(p.z1, z + 1)
  end

  -- a town's size: 0 a Pokémon Center on a route, 1 a town, 2 an island's town, 3 a city
  local function tierOf(sym)
    sym = tostring(sym or "")
    if sym:find("POKECENTER") then return 0 end
    if sym:find("CITY") or sym:find("PLATEAU") then return 3 end
    if sym:find("ISLAND") then return 2 end
    return 1
  end
  M.tierOf = tierOf

  local function finishPlaces(places)
    local badges = badgeList()
    for _, p in ipairs(places) do
      p.tier = p.kind == "town" and tierOf(p.sym) or nil
      local sx, sz = 0, 0
      for _, c in ipairs(p.cells) do sx, sz = sx + c[1] + 0.5, sz + c[2] + 0.5 end
      p.x, p.z, p.y = sx / #p.cells, sz / #p.cells, LAND_Y
      local key = p.census
      if key and key ~= "" then
        p.center = hasMap(key .. "_PokemonCenter_1F")
        p.mart = hasMap(key .. "_Mart") or hasMap(key .. "_DepartmentStore_1F")
        p.hasGym = hasMap(key .. "_Gym") or hasMap(key .. "_Gym_1F")
        if p.hasGym then
          local up = key:upper()
          for _, b in ipairs(badges) do
            if type(b.gym) == "string" and up:sub(1, #b.gym) == b.gym then
              p.badge, p.badgeFlag, p.badgeName = tonumber(b.num), tonumber(b.flag), titled(b.name)
            end
          end
        end
      end
    end
    -- (a landmark in a town's own cells -- Cerulean Cave, the Safari Zone -- is part of the town's card)
    for _, p in ipairs(places) do
      if p.kind == "landmark" then
        for _, town in ipairs(places) do
          if town.kind == "town" and p.x >= town.x0 and p.x < town.x1 and p.z >= town.z0 and p.z < town.z1 then
            p.within = town
            town.extras = town.extras or {}
            town.extras[#town.extras + 1] = p
            break
          end
        end
      end
    end
    table.sort(places, function(a, b)
      if a.kind ~= b.kind then return a.kind == "town" end
      if a.z ~= b.z then return a.z < b.z end
      return a.x < b.x
    end)
  end

  local function frlgPlaces(desc)
    local RX, MS = engine("src.import.gba.region_map_extract"), engine("src.import.gba.map_sections_extract")
    local RM, Strings = engine("src.ui.game3.region_map"), engine("src.core.Strings")
    if not (RX and MS and RM) then return {} end
    RX.ensureGenerated()
    local L = RX.LAYOUTS and RX.LAYOUTS[desc.layout]
    if not L then return {} end
    local NONE = RX.MAPSEC_NONE
    local places, byId = {}, {}
    local function nameOf(sym)
      local n = RX.SECTION_NAMES[sym]
      if n and Strings then
        local ok, s = pcall(Strings, n)
        if ok then n = s end
      end
      return titled(n or sym)
    end
    for _, layer in ipairs({ "map", "dungeon" }) do
      local grid = L[layer]
      for y = 0, 14 do
        for x = 0, 21 do
          local m = grid[y] and grid[y][x]
          if m and m ~= NONE then
            local info = MS.SECTIONS[m]
            local sym = info and info.id
            if sym then
              local kind = layer == "dungeon" and "landmark" or "route"
              if layer == "map" and (sym:find("_TOWN$") or sym:find("_CITY$") or sym:find("_ISLAND$")
                  or sym:find("PLATEAU$") or sym:find("POKECENTER$")) and sym ~= "MAPSEC_BIRTH_ISLAND"
                  and sym ~= "MAPSEC_OUTCAST_ISLAND" then
                kind = "town"
              elseif layer == "map" and not sym:find("^MAPSEC_ROUTE_") then
                kind = "landmark"
              end
              addCell(places, byId, m, x + 4, y + 4, { sym = sym, kind = kind, name = nameOf(sym),
                census = camel(sym), peak = PEAKS[sym], hidden = HIDDEN[sym] })
            end
          end
        end
      end
    end
    return places
  end

  local function rsePlaces()
    local RM = engine("src.ui.game3.rse.region_map")
    if not RM then return {} end
    local okM, man = pcall(RM.manifest)
    if not (okM and man and man.layout) then return {} end
    local NONE = man.mapsecs.NONE
    local first, last = man.mapsecs.LITTLEROOT_TOWN or 0, man.mapsecs.EVER_GRANDE_CITY or 15
    local symOf = {}
    for k, v in pairs(man.mapsecs) do symOf[v] = k end
    local places, byId = {}, {}
    for r, row in ipairs(man.layout) do
      for c, m in ipairs(row) do
        if m ~= NONE then
          local okN, raw = pcall(RM.mapName, m)
          local name = okN and raw or ""
          local sym = symOf[m] or tostring(name):upper():gsub("[^%w]+", "_"):gsub("_$", "")
          local kind = (m >= first and m <= last) and "town" or (tostring(name):find("^ROUTE") and "route" or "landmark")
          addCell(places, byId, m, c, r + 1, { sym = sym, kind = kind, name = titled(name), census = camel(name),
            peak = PEAKS[sym] })
        end
      end
    end
    return places
  end

  -- ------- Emerald's abnormal weather: one rumour at a time (the Weather Institute's scientist starts
  -- and moves it), locations 1..8 Groudon's routes, 9..16 Kyogre's. Over once it's caught (or knocked
  -- out: the game has nothing left to find then)

  local LOCATIONS, KYOGRE_FROM = 16, 9
  function M.storm(region, s)
    if not (region and region.id == "hoenn" and s) then return nil end
    if deps.gameId and deps.gameId() ~= "emerald" then return nil end
    local R = engine("src.core.game3.rse.init")
    local RM = engine("src.ui.game3.rse.region_map")
    if not (R and RM) then return nil end
    local ok, at, ending, kyogre, groudon = pcall(function()
      return R.var("VAR_ABNORMAL_WEATHER_LOCATION", s), R.var("VAR_SHOULD_END_ABNORMAL_WEATHER", s),
        R.flag("FLAG_DEFEATED_KYOGRE", s), R.flag("FLAG_DEFEATED_GROUDON", s)
    end)
    if not ok or at < 1 or at > LOCATIONS or ending ~= 0 then return nil end
    local rain = at >= KYOGRE_FROM
    if (rain and kyogre) or (not rain and groudon) then return nil end
    local okM, man = pcall(RM.manifest)
    local list = okM and man and man.terraOrMarineCaveMapSecIds
    local sec = list and list[at]
    for _, p in ipairs(region.places) do
      if p.id == sec then return { kind = rain and "rain" or "sand", place = p } end
    end
    return nil
  end

  -- ------- the everyday weather (Ruby / Sapphire / Emerald). A map's own weather covers all of it (Mt.
  -- Chimney's ash, Mt. Pyre's fog, Petalburg Woods' shade); a route's comes from tiles on it that change
  -- the weather when stepped on (a weather event, or a script's setweather: Route 111's desert), over
  -- the part of the route those tiles span. A section the Town Map shows as part of another (the game's
  -- own list: Petalburg Woods on Route 104, Mt. Pyre on Route 122) brings its own weather to that one.
  -- Read once (the data doesn't change), the cycles each time.

  -- the game's weather numbers (pokeemerald include/constants/weather.h; Ruby / Sapphire's alike)
  local WX = { [1] = "clouds", [3] = "rain", [4] = "snow", [5] = "thunder", [6] = "fog", [7] = "ash",
               [8] = "sand", [9] = "fog", [11] = "shade", [13] = "thunder" }
  local CYCLE = { [20] = true, [21] = true }     -- Route 119's and Route 123's, a stage a day
  local WX_PAD = 0.12                            -- a route's weather a little past its outermost tiles
  local function shown(w) return w ~= nil and (WX[w] ~= nil or CYCLE[w] == true) end
  local function setweatherOf(script)
    local rows = type(script) == "table" and (script.ops or script) or nil
    if type(rows) ~= "table" then return nil end
    for i = 1, 6 do
      local row = rows[i]
      if type(row) ~= "table" then return nil end
      if row.op == "setweather" then return tonumber(row[1]) end
    end
    return nil
  end

  function M.weatherData()
    local Space = engine("src.core.game3.scripting.space")
    local b = Space and Space.bundle
    return deps.maps and deps.maps() or nil, b and b.events, b and b.scripts
  end

  -- where each weather is: { key, raw (its number, maybe a cycle), place, fx0, fx1, fz0, fz1 (the part of
  -- the place's box, 0..1) }, kept with the region once the maps are in
  function M.weatherSpots(region)
    if region.wxSpots then return region.wxSpots end
    local maps, events, scripts = M.weatherData()
    if type(maps) ~= "table" then return {} end
    local Dataset, CW = engine("src.core.game3.dataset"), engine("src.core.game3.coord_weather")
    local byId, found, spots = {}, {}, {}
    for _, p in ipairs(region.places) do byId[p.id] = p end
    local inside = {}
    local RM = engine("src.ui.game3.rse.region_map")
    local okM, man = pcall(RM and RM.manifest or error)
    for _, sp in ipairs(okM and type(man) == "table" and type(man.specialPlaces) == "table" and man.specialPlaces or {}) do
      if type(sp) == "table" and byId[sp[2]] and not byId[sp[1]] then inside[sp[1]] = byId[sp[2]] end
    end
    local function add(p, w, x0, x1, z0, z1)
      -- (a place one cell across: all of it that way)
      if p.x1 - p.x0 <= 1 then x0, x1 = 0, 1 end
      if p.z1 - p.z0 <= 1 then z0, z1 = 0, 1 end
      local key = tostring(p.id) .. ":" .. w
      local sp = found[key]
      if sp then
        sp.fx0, sp.fx1, sp.fz0, sp.fz1 = min(sp.fx0, x0), max(sp.fx1, x1), min(sp.fz0, z0), max(sp.fz1, z1)
      else
        sp = { key = key, raw = w, place = p, fx0 = x0, fx1 = x1, fz0 = z0, fz1 = z1 }
        found[key] = sp
        spots[#spots + 1] = sp
      end
    end
    for id, def in pairs(maps) do
      local sec = type(def) == "table" and tonumber(def.regionMapSectionId)
      local p, within = sec and byId[sec], sec and inside[sec]
      local okO, outdoor = pcall(Dataset and Dataset.isOutdoorMapType or error, (p or within) and def.mapType)
      if within and okO and outdoor and shown(tonumber(def.weather)) then
        add(within, tonumber(def.weather), 0, 1, 0, 1)
      end
      if p and okO and outdoor then
        local own = tonumber(def.weather)
        if shown(own) then add(p, own, 0, 1, 0, 1) end
        local ev = type(events) == "table" and events[id] or nil
        local mw, mh = max(1, tonumber(def.width) or 1), max(1, tonumber(def.height) or 1)
        local boxes = {}
        for _, e in ipairs(type(ev) == "table" and type(ev.coordEvents) == "table" and ev.coordEvents or {}) do
          local w
          if CW and CW.isWeatherEvent and CW.isWeatherEvent(e) then
            w = CW.BY_TRIGGER and CW.BY_TRIGGER[tonumber(e.var) or -1]
          elseif e.scriptKey and type(scripts) == "table" then
            w = setweatherOf(scripts[e.scriptKey])
          end
          local x, y = tonumber(e.x), tonumber(e.y)
          if shown(w) and x and y then
            local b = boxes[w]
            if b then
              b[1], b[2], b[3], b[4] = min(b[1], x), max(b[2], x), min(b[3], y), max(b[4], y)
            else
              boxes[w] = { x, x, y, y }
            end
          end
        end
        for w, b in pairs(boxes) do
          add(p, w, max(0, b[1] / mw - WX_PAD), min(1, (b[2] + 1) / mw + WX_PAD),
            max(0, b[3] / mh - WX_PAD), min(1, (b[4] + 1) / mh + WX_PAD))
        end
      end
    end
    table.sort(spots, function(a, b) return a.key < b.key end)
    region.wxSpots = spots
    return spots
  end

  -- the ground under a weather: its highest point and its mean (the sea counts as 0)
  local function groundUnder(region, x, z, rx, rz)
    local hi, sum = 0, 0
    for i = 0, 4 do
      for j = 0, 4 do
        local ok, h = pcall(M.heightAt, region, x + (i / 2 - 1) * rx, z + (j / 2 - 1) * rz)
        h = ok and tonumber(h) and max(0, h) or 0
        hi, sum = max(hi, h), sum + h
      end
    end
    return hi, sum / 25
  end

  function M.weather(region, s)
    local out = {}
    if not (region and region.id == "hoenn") then return out end
    local W = engine("src.core.game3.weather")
    for _, sp in ipairs(M.weatherSpots(region)) do
      local w = sp.raw
      if CYCLE[w] then
        local ok, today = pcall(W and W.translate or error, w, s)
        w = ok and tonumber(today) or nil
      end
      local kind = w and WX[w]
      if kind then
        local p = sp.place
        local x0, x1 = p.x0 + (p.x1 - p.x0) * sp.fx0, p.x0 + (p.x1 - p.x0) * sp.fx1
        local z0, z1 = p.z0 + (p.z1 - p.z0) * sp.fz0, p.z0 + (p.z1 - p.z0) * sp.fz1
        local w2 = { key = sp.key, kind = kind, place = p, x = (x0 + x1) / 2, z = (z0 + z1) / 2,
                     rx = max(0.55, (x1 - x0) / 2), rz = max(0.55, (z1 - z0) / 2) }
        w2.y, w2.y0 = groundUnder(region, w2.x, w2.z, w2.rx, w2.rz)
        out[#out + 1] = w2
      end
    end
    return out
  end

  -- ------- building a region (once per game and region)

  function M.regions(family)
    return (family or familyOf()) == "rse" and RSE_REGIONS or FRLG_REGIONS
  end

  local function descOf(id)
    for _, d in ipairs(FRLG_REGIONS) do if d.id == id then return d, "frlg" end end
    return RSE_REGIONS[1], "rse"
  end

  local function sampler(desc, family)
    if not deps.pixels then return nil end
    local img, w, h
    if family == "frlg" then
      local Gpu = engine("src.ui.game3.region_map_gpu")
      local ok, got = pcall(Gpu and Gpu.image or error, desc.image)
      img, w, h = ok and got or nil, 240, 160
    else
      local RM, Kit = engine("src.ui.game3.rse.region_map"), engine("src.ui.game3.rse.scene_kit")
      local okM, man = pcall(RM and RM.manifest or error)
      local entry = okM and man and man.layers and man.layers.map
      local ok, got = pcall(Kit and Kit.image or error, entry and (entry.png or entry))
      img, w, h = ok and got or nil, 240, 160
    end
    if not img then return nil end
    local ok, s = pcall(deps.pixels, img, 0, 0, w, h)
    return ok and s or nil, img
  end

  function M.region(id)
    local game = deps.gameId and deps.gameId() or ""
    local key = game .. ":" .. tostring(id)
    if built[key] then return built[key] end
    local desc, family = descOf(id)
    local crop = CROP[family]
    local places = family == "frlg" and frlgPlaces(desc) or rsePlaces()
    finishPlaces(places)
    local cols, rows = crop[3] / STEP, crop[4] / STEP
    local t = newTerrain(cols, rows)
    local sample, picture = sampler(desc, family)
    if sample then
      fromPicture(t, sample, crop)
    else
      local cells = {}
      for _, p in ipairs(places) do
        for _, c in ipairs(p.cells) do cells[#cells + 1] = { c[1] + 0.5, c[2] + 0.5 } end
      end
      fromGrid(t, crop, cells)
    end
    fill(t)
    smooth(t)
    for _, p in ipairs(places) do
      if p.peak then raise(t, crop, p.x, p.z, p.peak) end
    end
    for _, p in ipairs(places) do
      if p.kind == "town" then flatten(t, crop, p) end
    end
    -- (each place's ground: the terrain under its middle)
    local region = { id = desc.id, key = desc.key, family = family, terrain = t, places = places,
                     x0 = crop[1] / 8, z0 = crop[2] / 8, w = crop[3] / 8, h = crop[4] / 8, step = STEP / 8,
                     fromPicture = sample ~= nil,
                     -- (the Town Map's own picture: the flat map; 240 x 160 at world 0, 0)
                     picture = picture }
    for _, p in ipairs(places) do
      if p.kind ~= "town" then p.y = M.heightAt(region, p.x, p.z) end
    end
    built[key] = region
    return region
  end

  -- the ground's height at a world point (the nearest sample)
  function M.heightAt(region, x, z)
    local t = region.terrain
    local i = floor((x - region.x0) / region.step + 0.5)
    local j = floor((z - region.z0) / region.step + 0.5)
    i, j = max(0, min(t.cols - 1, i)), max(0, min(t.rows - 1, j))
    return max(0, t.h[j * t.cols + i + 1])
  end

  -- ------- what the save says (read on open and once a second)

  local function frlgType(sym)
    local RM = engine("src.ui.game3.region_map")
    if not RM or (RM.isOpen and RM.isOpen()) then return 0 end
    -- (its Pokémon Centers on routes count as towns for Fly only: asked as the Fly map would)
    local prev = RM.mode
    RM.mode = "fly"
    local ok, t = pcall(RM.mapsecType, sym)
    RM.mode = prev
    return ok and tonumber(t) or 0
  end

  function M.live(region, s)
    if not region then return end
    if region.family == "frlg" then
      local RM = engine("src.ui.game3.region_map")
      for _, p in ipairs(region.places) do
        if p.kind == "town" then
          local t = frlgType(p.sym)
          p.visited = t == FR_VISITED
          p.canFly = p.visited
        end
        p.shown = true
        if p.hidden and RM and RM.isFlagSet then
          local ok, on = pcall(RM.isFlagSet, p.hidden)
          p.shown = ok and on == true
        end
      end
    else
      local RM = engine("src.ui.game3.rse.region_map")
      local st = { session = s }
      for _, p in ipairs(region.places) do
        local ok, t = pcall(RM and RM.mapSecType or error, st, p.id)
        t = ok and tonumber(t) or RS_NONE
        p.type = t
        p.visited = t == RS_CANFLY or t == RS_FRONTIER
        p.canFly = p.visited
        p.shown = t ~= RS_NONE
      end
    end
    for _, p in ipairs(region.places) do
      p.badgeOwned = p.badgeFlag ~= nil and flagOn(p.badgeFlag) or false
    end
  end

  -- the Sevii Islands' pictures: once the game's own map has them
  function M.available(s, id)
    local desc = descOf(id)
    if not desc.flag then return true end
    local RM = engine("src.ui.game3.region_map")
    local ok, on = pcall(RM and RM.isFlagSet or error, desc.flag)
    return ok and on == true
  end

  -- where the player is: the region and the cell, as the game's own map works it out
  function M.player(s)
    if not s then return nil end
    if familyOf() == "rse" then
      local RM = engine("src.ui.game3.rse.region_map")
      local ok, st = pcall(RM and RM.newState or error, { session = s, mode = "wall" })
      if not (ok and type(st) == "table" and tonumber(st.playerIconX)) then return nil end
      return "hoenn", st.playerIconX + 0.5, st.playerIconY + 0.5
    end
    local RX, Position = engine("src.import.gba.region_map_extract"), engine("src.ui.game3.region_map_position")
    local Runtime = engine("src.core.game3.runtime")
    if not (RX and Position and Runtime) then return nil end
    local ok, region, x, y = pcall(function()
      RX.ensureGenerated()
      local maps = Runtime._game and Runtime._game.data and Runtime._game.data.maps
      local function def(id) return assert(maps and maps[id], "no map header") end
      local cx, cy = Position.playerCell({ map = s.map, x = s.x, y = s.y, escapeWarp = s.escapeWarp,
        dynamicWarp = s.dynamicWarp, def = def }, RX.GEOMETRY)
      local r = Position.regionFor(def(s.map).regionMapSectionId, RX.LAYOUTS)
      return r, cx, cy
    end)
    if not ok then return nil end
    local desc = FRLG_REGIONS[(tonumber(region) or 0) + 1]
    return desc and desc.id or "kanto", x + 4.5, y + 4.5
  end

  -- Fly from the map app: the party's Pokémon that knows it, the badge, and the player outdoors
  function M.flyCheck(s)
    local FM = engine("src.core.game3.field_moves")
    if not (FM and s) then return nil, "none" end
    local Space = engine("src.core.game3.scripting.space")
    local okB, badge = pcall(FM.hasBadge, { store = Space and Space.store, session = s }, "FLY")
    if not (okB and badge) then return nil, "badge" end
    local okU, mon = pcall(FM.partyMoveUser, s.party, "FLY")
    if not (okU and mon) then return nil, "mon" end
    local Map = engine("src.core.game3.map")
    local okD, def = pcall(Map and Map.currentDef or error)
    if not (okD and def and FM.isOutdoors(def.mapType)) then return nil, "indoors" end
    return mon
  end

  -- the game's own Fly callback's arguments: FireRed / LeafGreen (symbol, number); Ruby / Sapphire /
  -- Emerald (number, { posWithinMapSec, mapSecType })
  function M.pickArgs(region, place)
    if region.family == "frlg" then return place.sym, place.id end
    return place.id, { posWithinMapSec = 0, mapSecType = place.type or RS_CANFLY }
  end

  return M
end
