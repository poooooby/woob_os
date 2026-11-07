-- The 3D map's towns and landmarks (for src/map3d/render.lua): every town its own. A town's size
-- (the model's tier: a Pokémon Center on a route, a town, an island's town, a city) sets how many
-- buildings stand on it, how tall, and its ground (a village's sandy square, a city's paving); its
-- name sets its roofs' colour (Kanto's towns are named for colours: Lavender's are purple,
-- Cerulean's blue, Vermilion's red ...), and the places the games are known for stand out: Oak's
-- lab, Pewter's museum, the Pokémon Tower, Silph Co., the S.S. Anne at Vermilion's dock, Celadon's
-- department store, the Pokémon League; Devon's tower in Rustboro, Mauville's dome, Mossdeep's
-- rocket, Fortree's tree houses, Pacifidlog on the water ... (our own list of what to build). The
-- Center (a red roof), the Mart (a blue one) and the Gym (its badge's band round its top) in every
-- town that has them. Trees on the forests' greens. Windows (flag 2) light up at night.
--
--   Tw = Towns()   Tw.build(region) -> vertices (render.lua's FORMAT) ; Tw.ground(place) -> r, g, b ;
--                  Tw.styleOf(place) -> the structure's name or nil (the tests)

local floor, max, min, abs, sqrt, sin, cos, pi = math.floor, math.max, math.min, math.abs, math.sqrt, math.sin,
  math.cos, math.pi

local F_SEA, F_WINDOW = 1, 2

-- the towns' signature structures (by the game's section names; FireRed's MAPSEC_*, Ruby's names;
-- Silph Co. and the S.S. Anne have no cell on the Town Map: Saffron's and Vermilion's own)
local STYLE = {
  MAPSEC_PALLET_TOWN = "lab", MAPSEC_PEWTER_CITY = "museum", MAPSEC_CERULEAN_CITY = "bridge",
  MAPSEC_VERMILION_CITY = "port", MAPSEC_SAFFRON_CITY = "skyscraper", MAPSEC_CELADON_CITY = "deptstore", MAPSEC_CINNABAR_ISLAND = "lab",
  MAPSEC_INDIGO_PLATEAU = "league", MAPSEC_VIRIDIAN_CITY = "school",
  MAPSEC_ONE_ISLAND = "pier", MAPSEC_TWO_ISLAND = "pier", MAPSEC_THREE_ISLAND = "pier", MAPSEC_FOUR_ISLAND = "pier",
  MAPSEC_FIVE_ISLAND = "pier", MAPSEC_SIX_ISLAND = "pier", MAPSEC_SEVEN_ISLAND = "pier",
  LITTLEROOT_TOWN = "lab", RUSTBORO_CITY = "skyscraper", SLATEPORT_CITY = "harbor", MAUVILLE_CITY = "dome",
  LILYCOVE_CITY = "deptstore", MOSSDEEP_CITY = "rocket", FORTREE_CITY = "treehouses", SOOTOPOLIS_CITY = "crater",
  EVER_GRANDE_CITY = "league", DEWFORD_TOWN = "harbor", LAVARIDGE_TOWN = "springs", FALLARBOR_TOWN = "ash",
  PETALBURG_CITY = "school", VERDANTURF_TOWN = "meadow",
}
-- the landmarks' own (a section of their own, in a town or out in the country)
local LANDMARK = {
  MAPSEC_POKEMON_TOWER = "tower", MAPSEC_SILPH_CO = "skyscraper", MAPSEC_S_S_ANNE = "ship",
  MAPSEC_POWER_PLANT = "plant", MAPSEC_POKEMON_MANSION = "mansion", MAPSEC_ROCKET_HIDEOUT = "corner",
  MAPSEC_TRAINER_TOWER = "tower", MAPSEC_BIRTH_ISLAND = "pyramid", MAPSEC_NAVEL_ROCK = "pillar",
  MAPSEC_VIRIDIAN_FOREST = "forest", MAPSEC_BERRY_FOREST = "forest", MAPSEC_PATTERN_BUSH = "forest",
  MAPSEC_TANOBY_RUINS = "ruins", MAPSEC_ROCKET_WAREHOUSE = "plant", MAPSEC_MEMORIAL_PILLAR = "pillar",
  MAPSEC_RESORT_GORGEOUS = "villa", MAPSEC_KANTO_SAFARI_ZONE = "gate",
  BATTLE_FRONTIER = "frontier", BATTLE_TOWER = "tower", SAFARI_ZONE = "forest", SOUTHERN_ISLAND = "forest",
}
-- roofs by name (the rest: a mix of their own)
local ROOF = {
  MAPSEC_PALLET_TOWN = { 0.93, 0.93, 0.9 }, MAPSEC_VIRIDIAN_CITY = { 0.26, 0.62, 0.42 },
  MAPSEC_PEWTER_CITY = { 0.55, 0.55, 0.6 }, MAPSEC_CERULEAN_CITY = { 0.25, 0.5, 0.88 },
  MAPSEC_VERMILION_CITY = { 0.88, 0.3, 0.2 }, MAPSEC_LAVENDER_TOWN = { 0.62, 0.46, 0.8 },
  MAPSEC_CELADON_CITY = { 0.4, 0.74, 0.6 }, MAPSEC_FUCHSIA_CITY = { 0.88, 0.36, 0.64 },
  MAPSEC_SAFFRON_CITY = { 0.94, 0.74, 0.26 }, MAPSEC_CINNABAR_ISLAND = { 0.84, 0.2, 0.18 },
  MAPSEC_INDIGO_PLATEAU = { 0.32, 0.32, 0.64 },
  LITTLEROOT_TOWN = { 0.8, 0.34, 0.26 }, OLDALE_TOWN = { 0.64, 0.45, 0.28 }, PETALBURG_CITY = { 0.9, 0.52, 0.62 },
  RUSTBORO_CITY = { 0.68, 0.35, 0.2 }, DEWFORD_TOWN = { 0.46, 0.72, 0.88 }, SLATEPORT_CITY = { 0.42, 0.5, 0.64 },
  MAUVILLE_CITY = { 0.92, 0.78, 0.3 }, VERDANTURF_TOWN = { 0.42, 0.7, 0.32 }, FALLARBOR_TOWN = { 0.62, 0.62, 0.64 },
  LAVARIDGE_TOWN = { 0.86, 0.32, 0.18 }, FORTREE_CITY = { 0.56, 0.38, 0.22 }, LILYCOVE_CITY = { 0.72, 0.56, 0.88 },
  MOSSDEEP_CITY = { 0.38, 0.56, 0.3 }, SOOTOPOLIS_CITY = { 0.96, 0.96, 0.98 }, PACIFIDLOG_TOWN = { 0.62, 0.43, 0.25 },
  EVER_GRANDE_CITY = { 0.92, 0.8, 0.36 },
}
local MIX = { { 0.74, 0.36, 0.24 }, { 0.36, 0.52, 0.30 }, { 0.62, 0.46, 0.30 }, { 0.44, 0.40, 0.56 }, { 0.70, 0.56, 0.22 } }
-- each structure's footprint across (world units at scale 1), kept clear of the houses
local FOOT = { lab = 0.42, museum = 0.44, school = 0.4, deptstore = 0.36, skyscraper = 0.26, tower = 0.34,
  plant = 0.46, mansion = 0.38, corner = 0.4, league = 0.62, dome = 0.72, rocket = 0.36, pyramid = 0.5,
  pillar = 0.12, villa = 0.36, ruins = 0.34, frontier = 0.6, forest = 0.5, springs = 0.26, crater = 0.4,
  gate = 0.34 }
local WALL, BLOCK, GLASS = { 0.95, 0.92, 0.84 }, { 0.86, 0.87, 0.9 }, { 0.5, 0.66, 0.82 }
local WIN = { 0.28, 0.34, 0.46 }
local CENTER_ROOF, MART_ROOF, GYM_WALL = { 0.92, 0.24, 0.22 }, { 0.22, 0.44, 0.92 }, { 0.78, 0.8, 0.76 }
-- the badges' colours, for a Gym's band (in order: Kanto's, then Hoenn's look alike enough)
local BADGE = { { 0.62, 0.62, 0.66 }, { 0.3, 0.6, 0.95 }, { 0.95, 0.78, 0.2 }, { 0.4, 0.8, 0.5 },
                { 0.9, 0.45, 0.7 }, { 0.95, 0.75, 0.25 }, { 0.92, 0.3, 0.2 }, { 0.3, 0.75, 0.4 } }

return function()
  local Tw = {}

  local function hash(i, j, k)
    local h = (i * 73856093 + j * 19349663 + (k or 0) * 83492791) % 2147483647
    h = (h * 1103515245 + 12345) % 2147483648
    return h / 2147483648
  end

  -- ------- pieces (vertices: x, y, z, nx, ny, nz, r, g, b, a, flag)

  local function vert(L, x, y, z, nx, ny, nz, c, a, flag, shade)
    local s = shade or 1
    L[#L + 1] = { x, y, z, nx, ny, nz, c[1] * s, c[2] * s, c[3] * s, a or 1, flag or 0 }
  end
  local function tri(L, ax, ay, az, bx, by, bz, cx, cy, cz, c, flag, shade)
    local ux, uy, uz = bx - ax, by - ay, bz - az
    local vx, vy, vz = cx - ax, cy - ay, cz - az
    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    local l = sqrt(nx * nx + ny * ny + nz * nz)
    if l > 0 then nx, ny, nz = nx / l, ny / l, nz / l end
    if ny < 0 then nx, ny, nz = -nx, -ny, -nz end
    vert(L, ax, ay, az, nx, ny, nz, c, 1, flag, shade)
    vert(L, bx, by, bz, nx, ny, nz, c, 1, flag, shade)
    vert(L, cx, cy, cz, nx, ny, nz, c, 1, flag, shade)
  end
  local function quad(L, ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz, c, flag, nx, ny, nz, shade)
    vert(L, ax, ay, az, nx, ny, nz, c, 1, flag, shade)
    vert(L, bx, by, bz, nx, ny, nz, c, 1, flag, shade)
    vert(L, cx, cy, cz, nx, ny, nz, c, 1, flag, shade)
    vert(L, ax, ay, az, nx, ny, nz, c, 1, flag, shade)
    vert(L, cx, cy, cz, nx, ny, nz, c, 1, flag, shade)
    vert(L, dx, dy, dz, nx, ny, nz, c, 1, flag, shade)
  end

  -- a box (rotated `rot` about its middle): four walls, a flat roof, rows of windows when `win`
  local function box(L, x, y, z, w, d, h, wall, roof, rot, win)
    local cw, sw = cos(rot), sin(rot)
    local hw, hd = w / 2, d / 2
    local function at(lx, lz) return x + lx * cw - lz * sw, z + lx * sw + lz * cw end
    local ax, az = at(-hw, -hd)
    local bx, bz = at(hw, -hd)
    local cx, cz = at(hw, hd)
    local dx, dz = at(-hw, hd)
    local base, top = y - 0.05, y + h
    quad(L, ax, top, az, bx, top, bz, bx, base, bz, ax, base, az, wall, 0, sw, 0, -cw)
    quad(L, bx, top, bz, cx, top, cz, cx, base, cz, bx, base, bz, wall, 0, cw, 0, sw, 0.9)
    quad(L, cx, top, cz, dx, top, dz, dx, base, dz, cx, base, cz, wall, 0, -sw, 0, cw)
    quad(L, dx, top, dz, ax, top, az, ax, base, az, dx, base, dz, wall, 0, -cw, 0, -sw, 0.9)
    if roof then quad(L, ax, top, az, bx, top, bz, cx, top, cz, dx, top, dz, roof, 0, 0, 1, 0) end
    if not win then return end
    -- (windows: rows up the walls, a few along each side, just off them)
    local rows = max(1, floor((h - 0.04) / 0.1))
    for side = 0, 3 do
      local len = (side % 2 == 0) and w or d
      local n = max(1, floor(len / 0.085))
      for row = 0, rows - 1 do
        local wy = y + 0.035 + row * (h - 0.05) / rows
        local wh = min(0.045, (h - 0.05) / rows * 0.55)
        for k = 0, n - 1 do
          local t0 = -len / 2 + (k + 0.25) * len / n
          local t1 = t0 + len / n * 0.5
          local lx0, lz0, lx1, lz1, nx, nz
          if side == 0 then lx0, lz0, lx1, lz1, nx, nz = t0, -hd - 0.004, t1, -hd - 0.004, sw, -cw
          elseif side == 1 then lx0, lz0, lx1, lz1, nx, nz = hw + 0.004, t0, hw + 0.004, t1, cw, sw
          elseif side == 2 then lx0, lz0, lx1, lz1, nx, nz = t1, hd + 0.004, t0, hd + 0.004, -sw, cw
          else lx0, lz0, lx1, lz1, nx, nz = -hw - 0.004, t1, -hw - 0.004, t0, -cw, -sw end
          local p1x, p1z = at(lx0, lz0)
          local p2x, p2z = at(lx1, lz1)
          quad(L, p1x, wy + wh, p1z, p2x, wy + wh, p2z, p2x, wy, p2z, p1x, wy, p1z, WIN, F_WINDOW, nx, 0, nz)
        end
      end
    end
  end

  -- a hip roof over a box's top (a little over its walls, to a ridge)
  local function hipRoof(L, x, top, z, w, d, rh, c, rot)
    local cw, sw = cos(rot), sin(rot)
    local function at(lx, lz) return x + lx * cw - lz * sw, z + lx * sw + lz * cw end
    local hw, hd, o = w / 2 * 1.12, d / 2 * 1.12, 1
    local ax, az = at(-hw, -hd)
    local bx, bz = at(hw, -hd)
    local cx, cz = at(hw, hd)
    local dx, dz = at(-hw, hd)
    local p1x, p1z = at(-hw * 0.35, 0)
    local p2x, p2z = at(hw * 0.35, 0)
    local ry = top + rh * o
    tri(L, ax, top, az, bx, top, bz, p2x, ry, p2z, c)
    tri(L, ax, top, az, p2x, ry, p2z, p1x, ry, p1z, c)
    tri(L, cx, top, cz, dx, top, dz, p1x, ry, p1z, c, 0, 0.9)
    tri(L, cx, top, cz, p1x, ry, p1z, p2x, ry, p2z, c, 0, 0.9)
    tri(L, bx, top, bz, cx, top, cz, p2x, ry, p2z, c, 0, 0.8)
    tri(L, dx, top, dz, ax, top, az, p1x, ry, p1z, c, 0, 0.8)
  end

  -- a house: walls, a window each side, a hip roof
  local function house(L, x, y, z, w, d, h, roof, rh, rot)
    box(L, x, y, z, w, d, h, WALL, nil, rot, false)
    local cw, sw = cos(rot), sin(rot)
    for _, side in ipairs({ -1, 1 }) do
      local lz = side * (d / 2 + 0.004)
      local ww = min(w * 0.28, 0.09)
      local w1x, w1z = x - ww * cw - lz * sw, z - ww * sw + lz * cw
      local w2x, w2z = x + ww * cw - lz * sw, z + ww * sw + lz * cw
      local wy, wh = y + h * 0.3, h * 0.34
      quad(L, w1x, wy + wh, w1z, w2x, wy + wh, w2z, w2x, wy, w2z, w1x, wy, w1z, WIN, F_WINDOW, -side * sw, 0, side * cw)
    end
    hipRoof(L, x, y + h, z, w, d, rh, roof, rot)
  end

  -- an n-sided frustum standing at x, y, z (radius r0 at the foot, r1 at the top; r1 0: a cone), a
  -- cap on it when `cap`
  local function prism(L, x, y, z, n, r0, r1, h, c, flag, cap, rot)
    rot = rot or 0
    local slope = (r0 - r1) / max(0.001, h)
    for k = 0, n - 1 do
      local a1, a2 = rot + k / n * 2 * pi, rot + (k + 1) / n * 2 * pi
      local am = (a1 + a2) / 2
      local nl = sqrt(1 + slope * slope)
      local nx, ny, nz = cos(am) / nl, slope / nl, sin(am) / nl
      local x1, z1, x2, z2 = cos(a1), sin(a1), cos(a2), sin(a2)
      quad(L, x + x1 * r1, y + h, z + z1 * r1, x + x2 * r1, y + h, z + z2 * r1, x + x2 * r0, y, z + z2 * r0,
        x + x1 * r0, y, z + z1 * r0, c, flag, nx, ny, nz, (k % 2 == 0) and 1 or 0.93)
      if cap and r1 > 0 then
        vert(L, x, y + h, z, 0, 1, 0, c, 1, flag)
        vert(L, x + x2 * r1, y + h, z + z2 * r1, 0, 1, 0, c, 1, flag)
        vert(L, x + x1 * r1, y + h, z + z1 * r1, 0, 1, 0, c, 1, flag)
      end
    end
  end
  -- a dome: stacked frustums
  local function dome(L, x, y, z, r, c, steps)
    steps = steps or 4
    for i = 0, steps - 1 do
      local a0, a1 = i / steps * pi / 2, (i + 1) / steps * pi / 2
      prism(L, x, y + sin(a0) * r, z, 12, cos(a0) * r, cos(a1) * r, (sin(a1) - sin(a0)) * r, c, 0, i == steps - 1)
    end
  end

  local function tree(L, x, y, z, s, shade)
    local c = { 0.12 + shade * 0.08, 0.42 + shade * 0.12, 0.16 }
    prism(L, x, y - 0.02, z, 5, s * 0.55, 0, s * 1.6, c, 0, false)
  end

  -- ------- the land under it (the model's samples)

  local function heightAt(region, x, z)
    local t = region.terrain
    local i = floor((x - region.x0) / region.step + 0.5)
    local j = floor((z - region.z0) / region.step + 0.5)
    if i < 0 or j < 0 or i >= t.cols or j >= t.rows then return -1 end
    return t.h[j * t.cols + i + 1]
  end
  -- the nearest open water to x, z (within r): its point, and the last land on the way to it
  local function seaNear(region, x, z, r)
    local best, bx, bz
    for a = 0, 23 do
      local an = a / 24 * 2 * pi
      for d = 0.25, r, 0.125 do
        local px, pz = x + cos(an) * d, z + sin(an) * d
        if heightAt(region, px, pz) < -0.08 then
          if not best or d < best then best, bx, bz = d, px, pz end
          break
        end
      end
    end
    if not best then return nil end
    -- (the shore: back from the water to the last land)
    local sx, sz = bx, bz
    for k = 1, 20 do
      local t = k / 20
      local px, pz = bx + (x - bx) * t, bz + (z - bz) * t
      if heightAt(region, px, pz) > 0.02 then
        sx, sz = px, pz
        break
      end
    end
    return bx, bz, sx, sz
  end

  -- ------- the structures (at x, y, z; s their scale)

  local BUILD = {}
  function BUILD.lab(L, x, y, z, s, rot)
    box(L, x, y, z, 0.42 * s, 0.28 * s, 0.17 * s, WALL, { 0.6, 0.66, 0.72 }, rot, true)
    prism(L, x + 0.12 * s, y + 0.17 * s, z, 8, 0.05 * s, 0.05 * s, 0.03 * s, { 0.85, 0.85, 0.88 }, 0, true)
  end
  function BUILD.museum(L, x, y, z, s, rot)
    box(L, x, y, z, 0.44 * s, 0.34 * s, 0.16 * s, { 0.9, 0.86, 0.78 }, { 0.7, 0.68, 0.64 }, rot, true)
    dome(L, x, y + 0.16 * s, z, 0.13 * s, { 0.55, 0.72, 0.68 })
  end
  function BUILD.school(L, x, y, z, s, rot)
    box(L, x, y, z, 0.4 * s, 0.24 * s, 0.15 * s, { 0.94, 0.9, 0.8 }, nil, rot, true)
    hipRoof(L, x, y + 0.15 * s, z, 0.4 * s, 0.24 * s, 0.07 * s, { 0.3, 0.55, 0.36 }, rot)
  end
  function BUILD.deptstore(L, x, y, z, s, rot)
    box(L, x, y, z, 0.36 * s, 0.3 * s, 0.6 * s, BLOCK, { 0.94, 0.94, 0.96 }, rot, true)
    box(L, x, y + 0.6 * s, z, 0.14 * s, 0.12 * s, 0.06 * s, { 0.95, 0.4, 0.4 }, { 0.95, 0.4, 0.4 }, rot, false)
  end
  function BUILD.skyscraper(L, x, y, z, s, rot)
    box(L, x, y, z, 0.26 * s, 0.26 * s, 1.0 * s, GLASS, { 0.4, 0.46, 0.55 }, rot, true)
    box(L, x, y + 1.0 * s, z, 0.16 * s, 0.16 * s, 0.12 * s, GLASS, { 0.4, 0.46, 0.55 }, rot, true)
    prism(L, x, y + 1.12 * s, z, 4, 0.012 * s, 0.004 * s, 0.25 * s, { 0.8, 0.8, 0.85 }, 0, false)
  end
  function BUILD.tower(L, x, y, z, s, rot)
    local c1, c2 = { 0.58, 0.44, 0.72 }, { 0.44, 0.32, 0.58 }
    local h = y
    for i = 0, 4 do
      local r = (0.17 - i * 0.025) * s
      prism(L, x, h, z, 4, r, r * 0.92, 0.17 * s, i % 2 == 0 and c1 or c2, 0, true, pi / 4 + (rot or 0))
      h = h + 0.17 * s
    end
    prism(L, x, h, z, 4, 0.06 * s, 0, 0.16 * s, c2, 0, false, pi / 4 + (rot or 0))
  end
  function BUILD.plant(L, x, y, z, s, rot)
    box(L, x, y, z, 0.46 * s, 0.32 * s, 0.17 * s, { 0.7, 0.72, 0.7 }, { 0.5, 0.52, 0.5 }, rot, true)
    for k = -1, 1, 2 do
      local px, pz = x + cos(rot) * k * 0.13 * s, z + sin(rot) * k * 0.13 * s
      prism(L, px, y + 0.17 * s, pz, 8, 0.035 * s, 0.03 * s, 0.32 * s, { 0.9, 0.9, 0.9 }, 0, true)
      prism(L, px, y + 0.42 * s, pz, 8, 0.031 * s, 0.031 * s, 0.07 * s, { 0.88, 0.25, 0.2 }, 0, true)
    end
  end
  function BUILD.mansion(L, x, y, z, s, rot)
    box(L, x, y, z, 0.38 * s, 0.32 * s, 0.24 * s, { 0.55, 0.52, 0.5 }, nil, rot, true)
    hipRoof(L, x, y + 0.24 * s, z, 0.38 * s, 0.32 * s, 0.1 * s, { 0.3, 0.26, 0.26 }, rot)
  end
  function BUILD.corner(L, x, y, z, s, rot)
    box(L, x, y, z, 0.4 * s, 0.26 * s, 0.2 * s, { 0.95, 0.82, 0.3 }, { 0.92, 0.35, 0.55 }, rot, true)
  end
  function BUILD.league(L, x, y, z, s, rot)
    box(L, x, y, z, 0.62 * s, 0.42 * s, 0.22 * s, { 0.92, 0.92, 0.95 }, { 0.6, 0.62, 0.72 }, rot, true)
    dome(L, x, y + 0.22 * s, z, 0.16 * s, { 0.9, 0.78, 0.35 })
    for i = 0, 3 do
      local lx, lz = (i % 2 == 0 and -1 or 1) * 0.28 * s, (i < 2 and -1 or 1) * 0.18 * s
      local px, pz = x + lx * cos(rot) - lz * sin(rot), z + lx * sin(rot) + lz * cos(rot)
      prism(L, px, y, pz, 6, 0.04 * s, 0.03 * s, 0.5 * s, { 0.86, 0.86, 0.9 }, 0, true)
      prism(L, px, y + 0.5 * s, pz, 6, 0.04 * s, 0, 0.12 * s, { 0.92, 0.75, 0.3 }, 0, false)
    end
  end
  function BUILD.dome(L, x, y, z, s)
    dome(L, x, y, z, 0.36 * s, { 0.78, 0.84, 0.9 }, 5)
    prism(L, x, y + 0.36 * s, z, 8, 0.04 * s, 0.0, 0.1 * s, { 0.95, 0.8, 0.3 }, 0, false)
  end
  function BUILD.rocket(L, x, y, z, s)
    prism(L, x, y, z, 10, 0.18 * s, 0.18 * s, 0.02 * s, { 0.55, 0.56, 0.6 }, 0, true)
    prism(L, x, y + 0.02 * s, z, 10, 0.06 * s, 0.06 * s, 0.5 * s, { 0.96, 0.96, 0.98 }, 0, false)
    prism(L, x, y + 0.52 * s, z, 10, 0.06 * s, 0, 0.16 * s, { 0.9, 0.24, 0.2 }, 0, false)
    prism(L, x, y + 0.02 * s, z, 3, 0.1 * s, 0.05 * s, 0.12 * s, { 0.9, 0.24, 0.2 }, 0, false)
    box(L, x + 0.11 * s, y, z, 0.03 * s, 0.03 * s, 0.58 * s, { 0.7, 0.4, 0.3 }, nil, 0, false)
  end
  function BUILD.pyramid(L, x, y, z, s)
    prism(L, x, y, z, 4, 0.28 * s, 0, 0.32 * s, { 0.72, 0.66, 0.6 }, 0, false, pi / 4)
  end
  function BUILD.pillar(L, x, y, z, s)
    prism(L, x, y, z, 6, 0.06 * s, 0.05 * s, 0.4 * s, { 0.78, 0.76, 0.72 }, 0, true)
  end
  function BUILD.villa(L, x, y, z, s, rot)
    box(L, x, y, z, 0.36 * s, 0.26 * s, 0.16 * s, { 0.98, 0.96, 0.92 }, nil, rot, true)
    hipRoof(L, x, y + 0.16 * s, z, 0.36 * s, 0.26 * s, 0.07 * s, { 0.9, 0.55, 0.35 }, rot)
  end
  function BUILD.ruins(L, x, y, z, s)
    for k = 0, 4 do
      local a = k / 5 * 2 * pi
      box(L, x + cos(a) * 0.14 * s, y, z + sin(a) * 0.14 * s, 0.06 * s, 0.06 * s, (0.08 + hash(k, 3, 3) * 0.12) * s,
        { 0.66, 0.62, 0.55 }, { 0.6, 0.56, 0.5 }, a, false)
    end
  end
  function BUILD.frontier(L, x, y, z, s, rot)
    BUILD.tower(L, x - 0.2 * s, y, z, s * 0.9, rot)
    dome(L, x + 0.2 * s, y, z + 0.1 * s, 0.16 * s, { 0.85, 0.85, 0.92 })
    BUILD.pyramid(L, x + 0.15 * s, y, z - 0.25 * s, s * 0.6)
  end
  function BUILD.forest(L, x, y, z, s, _, region)
    for k = 1, 16 do
      local a, d = hash(k, 1, 41) * 2 * pi, 0.1 + hash(k, 2, 41) * 0.45
      local px, pz = x + cos(a) * d * s, z + sin(a) * d * s
      local h = heightAt(region, px, pz)
      if h > 0.05 then tree(L, px, h, pz, (0.1 + hash(k, 3, 41) * 0.06) * s, hash(k, 4, 41)) end
    end
  end
  function BUILD.gate(L, x, y, z, s, rot)
    -- (the Safari Zone's gate: two posts, a beam, a hut beside it)
    local cw, sw = cos(rot), sin(rot)
    for k = -1, 1, 2 do
      box(L, x + cw * k * 0.12 * s, y, z + sw * k * 0.12 * s, 0.05 * s, 0.05 * s, 0.22 * s, { 0.55, 0.4, 0.26 },
        { 0.5, 0.36, 0.22 }, rot, false)
    end
    box(L, x, y + 0.2 * s, z, 0.32 * s, 0.06 * s, 0.05 * s, { 0.4, 0.62, 0.32 }, { 0.36, 0.56, 0.28 }, rot, false)
    house(L, x - sw * 0.16 * s, y, z + cw * 0.16 * s, 0.16 * s, 0.13 * s, 0.1 * s, { 0.4, 0.62, 0.32 }, 0.06 * s, rot)
  end
  function BUILD.springs(L, x, y, z, s)
    prism(L, x, y - 0.01, z, 12, 0.13 * s, 0.13 * s, 0.03 * s, { 0.55, 0.8, 0.92 }, F_SEA, true)
  end
  function BUILD.crater(L, x, y, z, s)
    prism(L, x, y - 0.01, z, 14, 0.2 * s, 0.2 * s, 0.025 * s, { 0.2, 0.45, 0.85 }, F_SEA, true)
  end
  -- (by the water: a lighthouse on the shore, a boat at a pier, the S.S. Anne off the dock)
  local function lighthouse(L, x, y, z, s)
    for i = 0, 3 do
      prism(L, x, y + i * 0.1 * s, z, 8, (0.06 - i * 0.006) * s, (0.054 - i * 0.006) * s, 0.1 * s,
        i % 2 == 0 and { 0.96, 0.96, 0.96 } or { 0.88, 0.22, 0.2 }, 0, true)
    end
    prism(L, x, y + 0.4 * s, z, 8, 0.04 * s, 0.04 * s, 0.05 * s, { 0.95, 0.85, 0.4 }, F_WINDOW, true)
    prism(L, x, y + 0.45 * s, z, 8, 0.05 * s, 0, 0.06 * s, { 0.88, 0.22, 0.2 }, 0, false)
  end
  local function boat(L, x, z, s, rot, big)
    local len, wid = (big and 0.75 or 0.22) * s, (big and 0.2 or 0.08) * s
    box(L, x, -0.01, z, len, wid, (big and 0.1 or 0.04) * s, { 0.95, 0.95, 0.97 }, { 0.75, 0.55, 0.35 }, rot, big)
    if big then
      box(L, x, 0.09 * s, z, len * 0.55, wid * 0.7, 0.08 * s, { 0.96, 0.96, 0.98 }, { 0.9, 0.9, 0.92 }, rot, true)
      for k = -1, 1, 2 do
        prism(L, x + cos(rot) * k * 0.1 * s, 0.17 * s, z + sin(rot) * k * 0.1 * s, 8, 0.03 * s, 0.028 * s, 0.12 * s,
          { 0.9, 0.26, 0.2 }, 0, true)
      end
    end
  end
  local function byWater(L, region, p, kind, s)
    local bx, bz, sx, sz = seaNear(region, p.x, p.z, 3)
    if not bx then return end
    local rot = math.atan2(bz - sz, bx - sx)
    if kind == "harbor" then
      lighthouse(L, sx, max(0.02, heightAt(region, sx, sz)), sz, s)
      boat(L, bx, bz, s, rot + pi / 2, false)
    elseif kind == "pier" then
      local mx, mz = (sx + bx) / 2, (sz + bz) / 2
      local len = sqrt((bx - sx) ^ 2 + (bz - sz) ^ 2)
      box(L, mx, 0.02, mz, len, 0.07 * s, 0.03, { 0.6, 0.44, 0.28 }, { 0.62, 0.46, 0.3 }, rot, false)
      boat(L, bx, bz, s, rot + pi / 2, false)
    elseif kind == "ship" then
      boat(L, bx + cos(rot) * 0.2, bz + sin(rot) * 0.2, s, rot + pi / 2, true)
    end
  end

  -- ------- a town

  function Tw.styleOf(p)
    if p.kind == "town" then return STYLE[p.sym] end
    return LANDMARK[p.sym]
  end
  function Tw.ground(p)
    if p.water then return 0.58, 0.43, 0.28 end
    local style = STYLE[p.sym]
    if style == "ash" then return 0.72, 0.72, 0.72 end
    if style == "crater" then return 0.9, 0.9, 0.88 end
    local tier = p.tier or 1
    if tier >= 3 then return 0.74, 0.75, 0.78 end
    if tier == 2 then return 0.88, 0.82, 0.66 end
    return 0.84, 0.82, 0.7
  end

  local function buildTown(L, region, p)
    local w, d = p.x1 - p.x0, p.z1 - p.z0
    local tier = p.tier or 1
    local style = STYLE[p.sym]
    local roof = ROOF[p.sym] or MIX[1 + floor(hash(p.id, 1, 5) * #MIX) % #MIX]
    if style == "ash" then roof = { 0.55, 0.55, 0.58 } end
    local n = tier == 0 and 0 or (tier >= 3 and min(22, 10 + #p.cells * 5) or (tier == 2 and 8 or 5 + #p.cells))
    local placed = {}
    -- (the town's ground reaches a little past its cells)
    local fx0, fz0, fw, fd = p.x0 - 0.08, p.z0 - 0.08, w + 0.16, d + 0.16
    local function free(hx, hz, size)
      if hx < fx0 + size * 0.5 or hx > fx0 + fw - size * 0.5 or hz < fz0 + size * 0.5 or hz > fz0 + fd - size * 0.5 then
        return false
      end
      for _, q in ipairs(placed) do
        if abs(q[1] - hx) < (q[3] + size) * 0.52 and abs(q[2] - hz) < (q[3] + size) * 0.52 then return false end
      end
      return true
    end
    local function spot(size, seed)
      for tries = 1, 160 do
        local hx = fx0 + hash(p.id, tries, seed) * fw
        local hz = fz0 + hash(p.id, tries, seed + 1) * fd
        if free(hx, hz, size) then
          placed[#placed + 1] = { hx, hz, size }
          return hx, hz, floor(hash(p.id, tries, seed + 2) * 4) * pi / 2
        end
      end
    end
    local y = p.y or 0.12
    -- (the town's own structure first, in its middle)
    local s = tier >= 3 and 1.1 or 0.9
    if BUILD[style] then
      placed[#placed + 1] = { p.x, p.z, (FOOT[style] or 0.4) * s }
      BUILD[style](L, p.x, y, p.z, s, 0, region)
    elseif style == "harbor" or style == "pier" or style == "port" then
      -- (a port: the lighthouse, and the S.S. Anne at the dock)
      byWater(L, region, p, style == "port" and "harbor" or style, 1)
      if style == "port" then byWater(L, region, p, "ship", 1) end
    end
    -- (its landmarks: the Pokémon Tower in Lavender, Silph Co. in Saffron, the S.S. Anne off Vermilion)
    for i, e in ipairs(p.extras or {}) do
      local es = LANDMARK[e.sym]
      if es == "ship" then
        byWater(L, region, p, "ship", 1)
      elseif BUILD[es] and not (e.hidden and e.shown == false) then
        local hx, hz, rot = spot((FOOT[es] or 0.4) * 0.85, 81 + i * 7)
        if hx then BUILD[es](L, hx, y, hz, 0.85, rot, region) end
      end
    end
    if style == "bridge" then
      -- (Cerulean: the river's bridge north of town, as a stone span)
      box(L, p.x, y + 0.02, p.z0 + 0.05, 0.6, 0.12, 0.04, { 0.7, 0.66, 0.6 }, { 0.74, 0.7, 0.62 }, 0, false)
    end
    -- (the Center, the Mart and the Gym)
    if p.center then
      local hx, hz, rot = spot(0.2, 11)
      if hx then
        box(L, hx, y, hz, 0.2, 0.16, 0.13, WALL, nil, rot, false)
        hipRoof(L, hx, y + 0.13, hz, 0.2, 0.16, 0.06, CENTER_ROOF, rot)
        prism(L, hx, y + 0.19, hz, 8, 0.016, 0.016, 0.025, { 1, 1, 1 }, 0, true)
      end
    end
    if p.mart then
      local hx, hz, rot = spot(0.18, 21)
      if hx then
        box(L, hx, y, hz, 0.18, 0.15, 0.12, WALL, nil, rot, false)
        hipRoof(L, hx, y + 0.12, hz, 0.18, 0.15, 0.055, MART_ROOF, rot)
      end
    end
    if p.hasGym then
      local hx, hz, rot = spot(0.27, 31)
      if hx then
        box(L, hx, y, hz, 0.28, 0.22, 0.17, GYM_WALL, { 0.5, 0.52, 0.5 }, rot, false)
        local band = BADGE[p.badge or 1] or BADGE[1]
        box(L, hx, y + 0.13, hz, 0.3, 0.24, 0.04, band, band, rot, false)
      end
    end
    -- (the houses: a city's taller blocks among them; Fortree's up in the trees)
    for k = 1, n do
      local block = tier >= 3 and hash(p.id, k, 51) < 0.45
      local size = block and 0.15 or (0.12 + hash(p.id, k, 52) * 0.03)
      local hx, hz, rot = spot(size, 60 + k * 3)
      if not hx then break end
      local shade = 0.88 + hash(p.id, k, 53) * 0.2
      local rc = { min(1, roof[1] * shade), min(1, roof[2] * shade), min(1, roof[3] * shade) }
      if style == "treehouses" then
        prism(L, hx, y - 0.02, hz, 6, 0.012, 0.01, 0.3, { 0.45, 0.32, 0.2 }, 0, false)
        tree(L, hx, y + 0.08, hz, 0.11, hash(p.id, k, 54))
        house(L, hx, y + 0.26, hz, 0.12, 0.1, 0.07, rc, 0.04, rot)
      elseif block then
        local bh = 0.2 + hash(p.id, k, 55) * 0.28
        box(L, hx, y, hz, size, size * 0.9, bh, BLOCK, rc, rot, true)
      else
        house(L, hx, y, hz, size, size * 0.85, 0.09 + hash(p.id, k, 56) * 0.04, rc, 0.06, rot)
      end
    end
    -- (a town's trees round its edge; a meadow's many)
    local nt = style == "meadow" and 10 or (tier <= 1 and 4 or 2)
    for k = 1, nt do
      local a = hash(p.id, k, 71) * 2 * pi
      local tx, tz = p.x + cos(a) * (w / 2 + 0.1), p.z + sin(a) * (d / 2 + 0.1)
      local h = heightAt(region, tx, tz)
      if h > 0.06 then tree(L, tx, h, tz, 0.09 + hash(p.id, k, 72) * 0.04, hash(p.id, k, 73)) end
    end
  end

  function Tw.build(region)
    local L = {}
    for _, p in ipairs(region.places) do
      if p.kind == "town" then
        buildTown(L, region, p)
      elseif not p.within and not (p.hidden and p.shown == false) then
        local style = LANDMARK[p.sym]
        if style == "ship" then
          byWater(L, region, p, "ship", 1)
        elseif BUILD[style] then
          BUILD[style](L, p.x, max(0.02, heightAt(region, p.x, p.z)), p.z, 1, 0, region)
        end
      end
    end
    -- (trees: on the darkest greens, away from the towns and the paths)
    local t, x0, z0, st = region.terrain, region.x0, region.z0, region.step
    for j = 1, t.rows - 2, 2 do
      for i = 1, t.cols - 2, 2 do
        local k = j * t.cols + i + 1
        local h = t.h[k]
        if t.kind[k] == "land" and not t.town[k] and h > 0.08 and h < 0.55 and (t.peak[k] or 0) < 0.3
            and t.g[k] < 0.62 and hash(i, j, 7) < 0.42 then
          local jx, jz = (hash(i, j, 8) - 0.5) * st, (hash(i, j, 9) - 0.5) * st
          tree(L, x0 + i * st + jx, h, z0 + j * st + jz, 0.09 + hash(i, j, 10) * 0.05, hash(i, j, 11))
        end
      end
    end
    return L
  end

  return Tw
end
