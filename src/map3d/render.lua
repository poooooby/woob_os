-- The 3D map's drawing: the region (src/map3d/model.lua) as meshes of our own, drawn into a canvas
-- with a depth buffer and one shader of our own (the engine has none in 3D):
--   - the land: the heightmap in the Town Map's own colours, snow on the peaks, a stone slab under
--     it (the map stands like a model on a table), trees on the forests' greens
--   - the towns: little houses, a red-roofed Center, a blue-roofed Mart, a bigger Gym; their
--     windows light up at night
--   - the sea: a sheet that waves (in the shader), glints by day; the clouds drift over it all
--   - a storm, when there's one to show: Kyogre's rain (dark clouds, falling streaks, lightning) or
--     Groudon's sand (dust wheeling round), two kept meshes moved and animated in the shader
--   - the sky: day, dusk, night (stars), from the device's clock
-- With no shader or mesh (the headless tests, an old GPU) the same camera draws the land as flat
-- polygons, so the overlays (src/map3d/scene.lua) work alike.
--
--   R = Render(deps)                 deps: log(fmt, ...) ; towns (src/map3d/towns.lua: the buildings)
--   R.camera(cam, rect)              cam = { x, y, z (the target), yaw, pitch, dist } ; rect = window
--                                    pixels { x, y, w, h } -> the view-projection kept
--   R.project(x, y, z) -> sx, sy, depth (window pixels; nil behind the eye)
--   R.draw(G, region, rect, t, night, dusk, storm) -> true (3D) | false (the flat fallback drew it)
--                                    storm = { x, z, kind = "rain" | "sand", grow = 0..1 } | nil
--   R.lightning(t) -> 0..1 (its flash; 0: none), its offset x, z from the storm's middle, its number
--   R.night(hour, minute) -> 0 (day) .. 1 (night) ; R.dusk(hour, minute) -> 0..1
--   R.frost(G, x, y, w, h, rad) -> true: frosted glass (the map blurred) in that rounded rect
--   R.flatCamera(cx, cz, half, rect) ; R.drawPicture(G, region, rect) -> the flat map (the game's
--   own Town Map picture, north up) ; R.drawLand(G, region, rect) (flat, without the picture)

local floor, max, min, abs, sqrt, sin, cos, pi = math.floor, math.max, math.min, math.abs, math.sqrt, math.sin,
  math.cos, math.pi

local SLAB = -0.9          -- the slab's foot
local SEA_ALPHA = 0.78
local FOV = 0.72           -- radians, top to bottom
local NEAR, FAR = 0.3, 260

local FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexNormal", "float", 3 },
  { "VertexColor", "byte", 4 },
  { "VertexFlag", "float", 1 },
}
-- flags (VertexFlag): 0 lit, 1 the sea, 2 a window (lit at night), 3 a cloud (drifts; its normal is
-- its anchor), 4 unlit (the slab's sides keep their colour), 5 a rain streak, 6 a storm's puff of cloud or
-- dust, 7 a grain of sand
local F_SEA, F_WINDOW, F_CLOUD = 1, 2, 3
local F_RAIN, F_PUFF, F_GRAIN = 5, 6, 7

local SHADER = [[
varying vec3 vNormal;
varying float vFlag;
varying float vWave;
varying float vFade;
varying vec2 vGround;
#ifdef VERTEX
uniform mat4 uViewProj;
uniform float uTime;
uniform vec2 uCloud;
uniform vec3 uEye;
uniform vec4 uStorm;     // x, z, how grown (0..1), how fast it turns
attribute vec3 VertexNormal;
attribute float VertexFlag;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec3 p = vertex_position.xyz;
  vFlag = VertexFlag;
  vNormal = VertexNormal;
  vWave = 0.0;
  vFade = 1.0;
  if (VertexFlag > 0.5 && VertexFlag < 1.5) {
    float a = p.x * 1.9 + uTime * 1.2;
    float b = p.z * 2.4 - uTime * 0.9;
    float c = (p.x + p.z) * 3.1 + uTime * 1.7;
    p.y += (sin(a) + sin(b)) * 0.018 + sin(c) * 0.008;
    vWave = sin(a) * 0.5 + sin(c) * 0.5;
    vNormal = normalize(vec3(-cos(a) * 0.07, 1.0, -cos(b) * 0.08));
  } else if (VertexFlag > 2.5 && VertexFlag < 3.5) {
    vec3 anchor = VertexNormal;
    anchor.x = mod(anchor.x + uTime * 0.22 - uCloud.x, uCloud.y) + uCloud.x;
    // (it grows in and shrinks away at the ends of its drift, where it wraps round)
    float edge = min(anchor.x - uCloud.x, uCloud.x + uCloud.y - anchor.x);
    p = anchor + p * smoothstep(0.0, 1.6, edge);
    vNormal = vec3(0.0, 1.0, 0.0);
    vFade = smoothstep(2.0, 7.0, distance(p, uEye));
  } else if (VertexFlag > 4.5 && VertexFlag < 5.5) {
    vec3 a = VertexNormal;
    float f = fract(a.y + uTime * 1.25);
    vec3 base = vec3(uStorm.x + a.x * uStorm.z, mix(2.2, 0.0, f) - p.y * 0.44, uStorm.y + a.z * uStorm.z);
    vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), uEye - base));
    p = base + side * p.x * 0.02;
    vNormal = vec3(0.0, 1.0, 0.0);
    vFade = uStorm.z * smoothstep(0.0, 0.05, f) * (1.0 - smoothstep(0.9, 1.0, f));
  } else if (VertexFlag > 5.5 && VertexFlag < 6.5) {
    float ca = cos(uTime * uStorm.w);
    float sa = sin(uTime * uStorm.w);
    vNormal = vec3(VertexNormal.x * ca - VertexNormal.z * sa, VertexNormal.y, VertexNormal.x * sa + VertexNormal.z * ca);
    p = vec3(p.x * ca - p.z * sa, p.y, p.x * sa + p.z * ca) * uStorm.z;
    p.x += uStorm.x;
    p.z += uStorm.y;
    vFade = uStorm.z * smoothstep(1.5, 5.0, distance(p, uEye));
  } else if (VertexFlag > 6.5) {
    vec3 a = VertexNormal;
    float turn = a.y * 6.2832 + uTime * (0.7 + 1.2 / (a.x + 0.5));
    vec3 c = vec3(uStorm.x + cos(turn) * a.x * uStorm.z, a.z + sin(uTime * 2.0 + a.y * 40.0) * 0.05,
                  uStorm.y + sin(turn) * a.x * uStorm.z);
    p = c + vec3(-sin(turn), 0.0, cos(turn)) * p.x * 0.06 + vec3(0.0, 1.0, 0.0) * p.y * 0.022;
    vNormal = vec3(0.0, 1.0, 0.0);
    vFade = uStorm.z;
  }
  vGround = p.xz;
  return uViewProj * vec4(p, 1.0);
}
#endif
#ifdef PIXEL
uniform vec3 uSun;
uniform vec3 uSunColor;
uniform vec3 uAmbient;
uniform float uNight;
uniform vec3 uStormAt;   // x, z, how grown
uniform vec4 uStormTint; // what it does to the ground under it: a colour, how much
uniform float uFlash;
vec3 underStorm(vec3 c) {
  float k = uStormAt.z * (1.0 - smoothstep(1.2, 2.6, distance(vGround, uStormAt.xy)));
  return mix(c, c * uStormTint.rgb, k * uStormTint.a) + vec3(0.25, 0.28, 0.4) * uFlash * k;
}
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  if (vFlag > 5.5 && vFlag < 6.5) {
    float lightOn = max(dot(normalize(vNormal), uSun), 0.0);
    return vec4(color.rgb * (uAmbient + uSunColor * lightOn) + vec3(0.5, 0.55, 0.75) * uFlash, color.a * vFade);
  }
  if (vFlag > 4.5) return vec4(color.rgb * mix(1.0, 0.6, uNight), color.a * vFade);
  if (vFlag > 2.5 && vFlag < 3.5) {
    // (color.r: how much sun this side of the cloud gets, baked in; the sky's own light colours it)
    return vec4(min(uAmbient * 1.15 + uSunColor * color.r * 0.8, vec3(1.0)), color.a * vFade);
  }
  if (vFlag > 3.5) return color;
  vec3 n = normalize(vNormal);
  float d = max(dot(n, uSun), 0.0);
  vec3 lit = color.rgb * (uAmbient + uSunColor * d);
  if (vFlag > 0.5 && vFlag < 1.5) {
    float glint = pow(max(vWave, 0.0), 8.0) * 0.22 * (1.0 - uNight);
    return vec4(underStorm(color.rgb * (uAmbient + uSunColor * (0.55 + 0.45 * d)) + vec3(glint)), color.a);
  }
  if (vFlag > 1.5 && vFlag < 2.5) lit = mix(lit, vec3(1.0, 0.82, 0.42), uNight);
  return vec4(underStorm(lit), color.a);
}
#endif
]]

-- the frosted glass under the overlays: the map blurred (a quarter-size copy, 25 taps), inside a
-- rounded rectangle (window pixels: its signed distance)
local GLASS = [[
uniform vec4 uRect;
uniform float uRad;
uniform vec2 uTexel;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec2 h = uRect.zw * 0.5;
  vec2 q = abs(sc - uRect.xy - h) - h + uRad;
  float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - uRad;
  float a = clamp(0.5 - d, 0.0, 1.0);
  vec3 sum = vec3(0.0);
  for (int i = -2; i <= 2; i++) {
    for (int j = -2; j <= 2; j++) {
      sum += Texel(tex, tc + vec2(float(i), float(j)) * uTexel).rgb;
    }
  }
  return vec4(sum / 25.0, a) * color;
}
]]

return function(deps)
  deps = deps or {}
  local R = {}
  local drawFlatLand

  -- ------- the camera: a kept view-projection (column-major, for the shader) and its use

  local VP = {}
  for i = 1, 16 do VP[i] = 0 end
  local VPF = {}          -- the same, upside down (a canvas's rows run the other way)
  for i = 1, 16 do VPF[i] = 0 end
  local view = { x = 0, y = 0, w = 1, h = 1 }
  local EYE = { 0, 0, 0 }
  R.vp = VP

  function R.camera(cam, rect)
    local cp, sp = cos(cam.pitch), sin(cam.pitch)
    local ex = cam.x + cam.dist * cp * sin(cam.yaw)
    local ey = cam.y + cam.dist * sp
    local ez = cam.z + cam.dist * cp * cos(cam.yaw)
    -- (look at the target: forward f, right s, up u)
    local fx, fy, fz = cam.x - ex, cam.y - ey, cam.z - ez
    local fl = sqrt(fx * fx + fy * fy + fz * fz)
    fx, fy, fz = fx / fl, fy / fl, fz / fl
    local sx, sy, sz = fz * 0 - fy * 0, 0, 0
    -- s = f x up(0,1,0) = (-fz, 0, fx) ... normalised
    sx, sy, sz = -fz, 0, fx
    local sl = sqrt(sx * sx + sz * sz)
    sx, sz = sx / sl, sz / sl
    -- u = s x f
    local ux, uy, uz = sy * fz - sz * fy, sz * fx - sx * fz, sx * fy - sy * fx
    local aspect = max(0.1, rect.w / max(1, rect.h))
    local f = 1 / math.tan(FOV / 2)
    local a, b = (FAR + NEAR) / (NEAR - FAR), (2 * FAR * NEAR) / (NEAR - FAR)
    -- view rows: s, u, -f (and the eye's translation)
    local tx = -(sx * ex + sy * ey + sz * ez)
    local ty = -(ux * ex + uy * ey + uz * ez)
    local tz = (fx * ex + fy * ey + fz * ez)
    local px, py = f / aspect, f
    -- P * V, column-major: column c = (row0, row1, row2, row3) of column c
    -- row0 = px * s ; row1 = py * u ; row2 = a * (-f) + (b on w) ; row3 = -(-f) = f . (x, y, z) - ...
    VP[1], VP[2], VP[3], VP[4] = px * sx, py * ux, -a * fx, fx
    VP[5], VP[6], VP[7], VP[8] = px * sy, py * uy, -a * fy, fy
    VP[9], VP[10], VP[11], VP[12] = px * sz, py * uz, -a * fz, fz
    VP[13], VP[14], VP[15], VP[16] = px * tx, py * ty, a * tz + b, -tz
    for i = 1, 16 do VPF[i] = VP[i] end
    VPF[2], VPF[6], VPF[10], VPF[14] = -VP[2], -VP[6], -VP[10], -VP[14]
    view.x, view.y, view.w, view.h = rect.x, rect.y, rect.w, rect.h
    EYE[1], EYE[2], EYE[3] = ex, ey, ez
  end

  -- the flat map: looking straight down, north up, `half` world units from the middle to the top
  -- edge (heights lift a little, so a pin still stands over its place)
  function R.flatCamera(cx, cz, half, rect)
    local aspect = max(0.1, rect.w / max(1, rect.h))
    local k = 1 / max(0.5, half)
    for i = 1, 16 do VP[i] = 0 end
    VP[1], VP[13] = k / aspect, -cx * k / aspect
    VP[6], VP[10], VP[14] = k * 0.25, -k, cz * k
    VP[16] = 1
    for i = 1, 16 do VPF[i] = VP[i] end
    view.x, view.y, view.w, view.h = rect.x, rect.y, rect.w, rect.h
  end

  -- the Town Map's own picture under the flat camera (pixel for pixel, sharp) -> false without it
  local pictureQuads = setmetatable({}, { __mode = "k" })
  local SEA_DARK = { 0.16, 0.22, 0.42 }
  function R.drawPicture(G, region, rect)
    local img = region.picture
    if not img then return false end
    local q = pictureQuads[img]
    if not q then
      local ok, made = pcall(G.newQuad, 0, 0, 240, 160, img:getWidth(), img:getHeight())
      q = ok and made or false
      pictureQuads[img] = q
      pcall(img.setFilter, img, "nearest", "nearest")
    end
    if not q then return false end
    local ax, ay = R.project(0, 0, 0)
    local bx = R.project(8, 0, 0)
    if not (ax and bx) then return false end
    local s = (bx - ax) / 64
    G.setColor(SEA_DARK[1], SEA_DARK[2], SEA_DARK[3], 1)
    G.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
    G.setColor(1, 1, 1, 1)
    G.draw(img, q, ax, ay, 0, s, s)
    return true
  end
  -- (no picture: the land's cells, flat)
  function R.drawLand(G, region, rect) return drawFlatLand(G, region, rect) end

  function R.project(x, y, z)
    local cx = VP[1] * x + VP[5] * y + VP[9] * z + VP[13]
    local cy = VP[2] * x + VP[6] * y + VP[10] * z + VP[14]
    local cw = VP[4] * x + VP[8] * y + VP[12] * z + VP[16]
    if cw <= NEAR * 0.5 then return nil end
    return view.x + (cx / cw * 0.5 + 0.5) * view.w, view.y + (0.5 - cy / cw * 0.5) * view.h, cw
  end
  local project = R.project

  -- ------- the light: day, dusk and night from the clock

  -- 0 by day (7:00 - 17:30), 1 at night (20:00 - 5:00), between at dawn and dusk
  function R.night(hour, minute)
    local h = (tonumber(hour) or 12) + (tonumber(minute) or 0) / 60
    if h >= 7 and h < 17.5 then return 0 end
    if h >= 20 or h < 5 then return 1 end
    if h < 7 then return 1 - (h - 5) / 2 end
    return (h - 17.5) / 2.5
  end
  -- the warm hour (an orange sky) at both ends of the day
  function R.dusk(hour, minute)
    local h = (tonumber(hour) or 12) + (tonumber(minute) or 0) / 60
    local function bump(c, wd) return max(0, 1 - abs(h - c) / wd) end
    return max(bump(18.6, 1.6), bump(6, 1.2))
  end

  -- ------- building the meshes (once per region)

  local function hash(i, j, k)
    local h = (i * 73856093 + j * 19349663 + (k or 0) * 83492791) % 2147483647
    h = (h * 1103515245 + 12345) % 2147483648
    return h / 2147483648
  end

  local function vert(list, x, y, z, nx, ny, nz, r, g, b, a, flag)
    list[#list + 1] = { x, y, z, nx, ny, nz, r, g, b, a or 1, flag or 0 }
  end
  local function quad(list, ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz, r, g, b, a, flag, nx, ny, nz)
    -- (a wall: its own outward normal)
    vert(list, ax, ay, az, nx, ny, nz, r, g, b, a, flag)
    vert(list, bx, by, bz, nx, ny, nz, r, g, b, a, flag)
    vert(list, cx, cy, cz, nx, ny, nz, r, g, b, a, flag)
    vert(list, ax, ay, az, nx, ny, nz, r, g, b, a, flag)
    vert(list, cx, cy, cz, nx, ny, nz, r, g, b, a, flag)
    vert(list, dx, dy, dz, nx, ny, nz, r, g, b, a, flag)
  end

  local function newMesh(G, verts, mode, map)
    if #verts == 0 then return nil end
    local ok, m = pcall(G.newMesh, FORMAT, verts, mode or "triangles", "static")
    if not ok then
      if deps.log then deps.log("the map's mesh failed: %s", tostring(m)) end
      return nil
    end
    if map then pcall(m.setVertexMap, m, map) end
    return m
  end

  -- the land: one vertex per sample, smooth normals; the town's ground paved, snow up high
  local SNOW = 0.95
  local function landMesh(G, region)
    local t, x0, z0, st = region.terrain, region.x0, region.z0, region.step
    local cols, rows = t.cols, t.rows
    local verts = {}
    local function hAt(i, j)
      i, j = max(0, min(cols - 1, i)), max(0, min(rows - 1, j))
      return t.h[j * cols + i + 1]
    end
    for j = 0, rows - 1 do
      for i = 0, cols - 1 do
        local k = j * cols + i + 1
        local h = t.h[k]
        local nx, nz = hAt(i - 1, j) - hAt(i + 1, j), hAt(i, j - 1) - hAt(i, j + 1)
        local ny = 2 * st
        local l = sqrt(nx * nx + ny * ny + nz * nz)
        local r, g, b = t.r[k], t.g[k], t.b[k]
        if h < 0 then
          -- (the sea bed: sand near the shore, deeper blue-green away)
          local d = min(1, -h / 0.18)
          r, g, b = 0.78 - d * 0.42, 0.76 - d * 0.22, 0.56 + d * 0.06
        elseif t.town[k] then
          -- (a town's ground: a village's square, a city's paving, Pacifidlog's boardwalks)
          if deps.towns then r, g, b = deps.towns.ground(t.town[k]) else r, g, b = 0.84, 0.82, 0.74 end
        elseif (t.peak[k] or 0) > 0 then
          -- (the mountain's rock showing through, snow on its top)
          local s = min(0.85, t.peak[k] * 1.4)
          r, g, b = r + (0.52 - r) * s, g + (0.45 - g) * s, b + (0.38 - b) * s
          if t.peak[k] > 0.7 and h > SNOW then
            local w = min(1, (t.peak[k] - 0.7) / 0.18)
            r, g, b = r + (0.95 - r) * w, g + (0.96 - g) * w, b + (0.98 - b) * w
          end
        end
        vert(verts, x0 + i * st, h, z0 + j * st, nx / l, ny / l, nz / l, r, g, b, 1, 0)
      end
    end
    local map = {}
    for j = 0, rows - 2 do
      for i = 0, cols - 2 do
        local a = j * cols + i + 1
        local b, c, d = a + 1, a + cols, a + cols + 1
        map[#map + 1], map[#map + 2], map[#map + 3] = a, c, b
        map[#map + 1], map[#map + 2], map[#map + 3] = b, c, d
      end
    end
    return newMesh(G, verts, "triangles", map)
  end

  -- the slab: the map's four sides, down to its foot (soil over stone)
  local function slabMesh(G, region)
    local t, x0, z0, st = region.terrain, region.x0, region.z0, region.step
    local cols, rows = t.cols, t.rows
    local verts = {}
    local function top(i, j) return max(0, t.h[j * cols + i + 1]) end
    local function side(i0, j0, i1, j1, nx, nz)
      local ax, az = x0 + i0 * st, z0 + j0 * st
      local bx, bz = x0 + i1 * st, z0 + j1 * st
      local ah, bh = top(i0, j0), top(i1, j1)
      quad(verts, ax, ah, az, bx, bh, bz, bx, SLAB, bz, ax, SLAB, az, 0.42, 0.33, 0.24, 1, 4, nx, 0, nz)
    end
    for i = 0, cols - 2 do
      side(i, 0, i + 1, 0, 0, -1)
      side(i + 1, rows - 1, i, rows - 1, 0, 1)
    end
    for j = 0, rows - 2 do
      side(0, j + 1, 0, j, -1, 0)
      side(cols - 1, j, cols - 1, j + 1, 1, 0)
    end
    -- (a darker band at the foot: the stone)
    local w, h = (cols - 1) * st, (rows - 1) * st
    local fy = SLAB + 0.25
    quad(verts, x0, fy, z0, x0 + w, fy, z0, x0 + w, SLAB, z0, x0, SLAB, z0, 0.27, 0.22, 0.18, 1, 4, 0, 0, -1)
    quad(verts, x0 + w, fy, z0 + h, x0, fy, z0 + h, x0, SLAB, z0 + h, x0 + w, SLAB, z0 + h, 0.27, 0.22, 0.18, 1, 4, 0, 0, 1)
    quad(verts, x0, fy, z0 + h, x0, fy, z0, x0, SLAB, z0, x0, SLAB, z0 + h, 0.27, 0.22, 0.18, 1, 4, -1, 0, 0)
    quad(verts, x0 + w, fy, z0, x0 + w, fy, z0 + h, x0 + w, SLAB, z0 + h, x0 + w, SLAB, z0, 0.27, 0.22, 0.18, 1, 4, 1, 0, 0)
    return newMesh(G, verts)
  end

  -- the sea: a sheet over the whole slab, the shader's waves on it
  local function seaMesh(G, region)
    local w, h = region.w - region.step, region.h - region.step
    local cols, rows = floor(w / 0.5) + 1, floor(h / 0.5) + 1
    local verts = {}
    for j = 0, rows - 1 do
      for i = 0, cols - 1 do
        local x, z = region.x0 + w * i / (cols - 1), region.z0 + h * j / (rows - 1)
        vert(verts, x, 0, z, 0, 1, 0, 0.24, 0.52, 0.86, SEA_ALPHA, F_SEA)
      end
    end
    local map = {}
    for j = 0, rows - 2 do
      for i = 0, cols - 2 do
        local a = j * cols + i + 1
        map[#map + 1], map[#map + 2], map[#map + 3] = a, a + cols, a + 1
        map[#map + 1], map[#map + 2], map[#map + 3] = a + 1, a + cols, a + cols + 1
      end
    end
    return newMesh(G, verts, "triangles", map)
  end

  -- the towns, their landmarks and the forests' trees (src/map3d/towns.lua): one mesh
  local function townMesh(G, region)
    if not deps.towns then return nil end
    local ok, verts = pcall(deps.towns.build, region)
    if not ok then
      if deps.log then deps.log("the map's towns failed: %s", tostring(verts)) end
      return nil
    end
    return newMesh(G, verts)
  end

  -- the clouds: a few flat puffs high up, each with its anchor in the normal (the shader drifts it)
  -- one rounded lobe of a cloud, around the cloud's own middle (its anchor goes in the normal, for the
  -- drift), cut flat underneath. How much sun each part gets is baked into the colour
  local CLOUD_BASE = -0.06
  local CLOUD_SUN_X, CLOUD_SUN_Y, CLOUD_SUN_Z = 0.4344, 0.8068, 0.4758   -- (light()'s sun, as a unit vector)
  local function cloudLobe(verts, ax, ay, az, ox, oy, oz, rx, ry, rz)
    local ROWS, SEGS = 7, 10
    local function corner(j, i)
      local a, t = j / ROWS * pi, i / SEGS * 2 * pi
      local nx, ny, nz = sin(a) * cos(t), cos(a), sin(a) * sin(t)
      local y = oy + ny * ry
      local bright = 0.32 + 0.68 * max(0, nx * CLOUD_SUN_X + ny * CLOUD_SUN_Y + nz * CLOUD_SUN_Z)
      if y < CLOUD_BASE then y, bright = CLOUD_BASE, 0.12 end
      verts[#verts + 1] = { ox + nx * rx, y, oz + nz * rz, ax, ay, az, bright, bright, bright, 1, F_CLOUD }
    end
    for j = 0, ROWS - 1 do
      for i = 0, SEGS - 1 do
        corner(j, i); corner(j + 1, i); corner(j + 1, i + 1)
        corner(j, i); corner(j + 1, i + 1); corner(j, i + 1)
      end
    end
  end

  local function cloudMesh(G, region)
    local verts = {}
    local n = max(4, floor(region.w * region.h / 70))
    for c = 1, n do
      -- (spread evenly over the map: two irrational steps)
      local ax = region.x0 + ((c * 0.7548776662) % 1) * region.w
      local az = region.z0 + ((c * 0.5698402910) % 1) * region.h
      local ay = 3.1 + ((c * 0.6180339887) % 1) * 0.9
      local lobes = 4 + c % 3
      local reach = 0.5 + lobes * 0.13
      local turn = (hash(c, 1, 22) - 0.5) * 0.9
      for k = 1, lobes do
        -- (biggest in the middle, smaller toward the ends, some set back for depth)
        local t = (k - 0.5) / lobes * 2 - 1
        local rad = (0.62 - 0.3 * abs(t)) * (0.85 + hash(c, k, 24) * 0.3)
        local ox, oz = t * reach + (hash(c, k, 22) - 0.5) * 0.14, (hash(c, k, 23) - 0.5) * 0.5
        local rx, rz = ox * cos(turn) - oz * sin(turn), ox * sin(turn) + oz * cos(turn)
        cloudLobe(verts, ax, ay, az, rx, rad * 0.24, rz, rad, rad * 0.74, rad * 0.86)
      end
    end
    return newMesh(G, verts)
  end

  -- ------- the storms: built once, around the origin; the shader puts them where they are

  -- one rounded puff (an ellipsoid), shaded darker underneath
  local function puff(list, cx, cy, cz, rx, ry, rz, r, g, b, alpha)
    local ROWS, SEGS = 8, 12
    local function corner(j, i)
      local a, t = j / ROWS * pi, i / SEGS * 2 * pi
      local nx, ny, nz = sin(a) * cos(t), cos(a), sin(a) * sin(t)
      local shade = 0.74 + 0.26 * (ny + 1) / 2
      vert(list, cx + nx * rx, cy + ny * ry, cz + nz * rz, nx, ny, nz, r * shade, g * shade, b * shade, alpha, F_PUFF)
    end
    for j = 0, ROWS - 1 do
      for i = 0, SEGS - 1 do
        corner(j, i); corner(j + 1, i); corner(j + 1, i + 1)
        corner(j, i); corner(j + 1, i + 1); corner(j, i + 1)
      end
    end
  end

  -- a little quad of the given flag: its corners at x = +-1, y0 and y1, its seed in the normal
  local function fleck(list, y0, y1, a, b, c, r, g, bl, alpha, flag)
    local function v(x, y) vert(list, x, y, 0, a, b, c, r, g, bl, alpha, flag) end
    v(-1, y0); v(1, y0); v(1, y1)
    v(-1, y0); v(1, y1); v(-1, y1)
  end

  local function rainMeshes(G)
    local solid, fine = {}, {}
    for i = 1, 14 do
      local a, d = hash(i, 1, 51) * 2 * pi, sqrt(hash(i, 2, 51)) * 0.95
      local s = 0.42 + hash(i, 3, 51) * 0.3
      local tone = 0.92 + hash(i, 4, 51) * 0.2
      puff(solid, cos(a) * d, 2.3 + hash(i, 5, 51) * 0.36, sin(a) * d, s, s * 0.55, s * 0.9,
        0.4 * tone, 0.44 * tone, 0.54 * tone, 1)
    end
    for i = 1, 460 do
      -- (spread evenly over the disc: a golden-angle spiral, their timing from another irrational)
      local a, d = i * 2.39996, sqrt(i / 460) * 1.9
      fleck(fine, 0, 1, cos(a) * d, (i * 0.7548776662) % 1, sin(a) * d, 0.8, 0.88, 1, 0.85, F_RAIN)
    end
    return { solid = newMesh(G, solid), fine = newMesh(G, fine) }
  end

  local function sandMeshes(G)
    local solid, fine = {}, {}
    for layer = 0, 2 do
      local n, ring = 10 - layer * 2, 1.35 - layer * 0.36
      for i = 1, n do
        local a = (i + hash(i, layer, 61) * 0.6) / n * 2 * pi
        local s = 0.54 - layer * 0.06 + hash(i, layer, 62) * 0.14
        local tone = 0.92 + hash(i, layer, 63) * 0.16
        puff(solid, cos(a) * ring, 0.34 + layer * 0.42, sin(a) * ring, s, s * 0.72, s,
          0.97 * tone, 0.82 * tone, 0.58 * tone, 0.36)
      end
    end
    for i = 1, 720 do
      fleck(fine, -1, 1, 0.3 + ((i * 0.7548776662) % 1) * 2.0, (i * 0.6180339887) % 1, 0.08 + ((i * 0.5698402910) % 1) * 1.9,
        0.98, 0.86, 0.62, 0.95, F_GRAIN)
    end
    return { solid = newMesh(G, solid), fine = newMesh(G, fine) }
  end

  local stormMeshes = {}
  local function stormOf(G, kind)
    local m = stormMeshes[kind]
    if m == nil then
      m = (kind == "rain" and rainMeshes or sandMeshes)(G)
      if not (m.solid and m.fine) then m = false end
      stormMeshes[kind] = m
    end
    return m or nil
  end

  -- how each one turns and what it does to the ground under it
  local STORM_LOOK = { rain = { spin = 0.1, 0.42, 0.48, 0.64, 0.95 }, sand = { spin = 0.75, 1.05, 0.84, 0.54, 0.9 } }

  local LIGHTNING_EVERY, LIGHTNING_LASTS = 3.4, 0.28
  function R.lightning(t)
    local n = floor(t / LIGHTNING_EVERY)
    local age = t - n * LIGHTNING_EVERY - hash(n, 1, 41) * (LIGHTNING_EVERY - LIGHTNING_LASTS)
    if age < 0 or age > LIGHTNING_LASTS then return 0 end
    local a, d = hash(n, 2, 41) * 2 * pi, sqrt(hash(n, 3, 41)) * 1.1
    return 1 - age / LIGHTNING_LASTS, cos(a) * d, sin(a) * d, n
  end

  -- ------- the shader, the canvas and the draw

  local shader, shaderTried = nil, false
  local function getShader(G)
    if shaderTried then return shader end
    shaderTried = true
    if not G.newShader then return nil end
    local ok, s = pcall(G.newShader, SHADER)
    if ok then shader = s elseif deps.log then deps.log("the map's shader failed: %s", tostring(s)) end
    return shader
  end

  local meshesOf = setmetatable({}, { __mode = "k" })
  local function meshes(G, region)
    local m = meshesOf[region]
    if m == nil then
      m = { land = landMesh(G, region), slab = slabMesh(G, region), sea = seaMesh(G, region),
            towns = townMesh(G, region), clouds = cloudMesh(G, region) }
      if not m.land then m = false end
      meshesOf[region] = m
    end
    return m or nil
  end

  local canvas, canvasW, canvasH = nil, 0, 0
  local TARGET = { nil, depth = true }
  local function target(G, w, h)
    if canvas and canvasW == w and canvasH == h then return canvas end
    if canvas and canvas.release then pcall(canvas.release, canvas) end
    canvas = nil
    local ok, c = pcall(G.newCanvas, w, h, { msaa = 4, dpiscale = 1 })
    if not ok then ok, c = pcall(G.newCanvas, w, h, { dpiscale = 1 }) end
    if ok and c then
      canvas, canvasW, canvasH = c, w, h
      TARGET[1] = c
    end
    return canvas
  end

  -- the blurred copy (a quarter of the canvas, smoothed) and the glass shader that draws it
  local small, smallW, smallH, glassShader, glassTried = nil, 0, 0, nil, false
  local RECT, TEXEL = { 0, 0, 1, 1 }, { 0, 0 }
  local frosted = false
  local function blurTarget(G, w, h)
    if small and smallW == w and smallH == h then return small end
    if small and small.release then pcall(small.release, small) end
    small = nil
    local ok, c = pcall(G.newCanvas, w, h, { dpiscale = 1 })
    if ok and c then
      pcall(c.setFilter, c, "linear", "linear")
      small, smallW, smallH = c, w, h
    end
    return small
  end
  -- frosted glass over the last 3D frame in a rounded rect (window pixels) -> false when it can't
  function R.frost(G, x, y, w, h, rad)
    if not (frosted and small) then return false end
    if not glassTried then
      glassTried = true
      local ok, sh = pcall(G.newShader, GLASS)
      glassShader = ok and sh or nil
      if not ok and deps.log then deps.log("the map's glass failed: %s", tostring(sh)) end
    end
    if not glassShader then return false end
    RECT[1], RECT[2], RECT[3], RECT[4] = x, y, w, h
    TEXEL[1], TEXEL[2] = 1.1 / smallW, 1.1 / smallH
    G.push("all")
    G.intersectScissor(max(0, floor(x)), max(0, floor(y)), max(1, floor(w + 1)), max(1, floor(h + 1)))
    G.setShader(glassShader)
    pcall(glassShader.send, glassShader, "uRect", RECT)
    pcall(glassShader.send, glassShader, "uRad", rad)
    pcall(glassShader.send, glassShader, "uTexel", TEXEL)
    G.setColor(1, 1, 1, 1)
    G.draw(small, view.x, view.y, 0, view.w / smallW, view.h / smallH)
    G.pop()
    return true
  end

  local SUN, SUN_COLOR, AMBIENT, CLOUD = { 0, 1, 0 }, { 1, 1, 1 }, { 0.4, 0.4, 0.4 }, { 0, 1 }
  local STORM, STORM_AT, STORM_TINT = { 0, 0, 0, 0 }, { 0, 0, 0 }, { 1, 1, 1, 0 }
  -- the sky: a gradient behind the map, and stars at night
  local sky = nil
  local STARS = {}
  for i = 1, 70 do STARS[i] = { hash(i, 1, 31), hash(i, 2, 31) * 0.7, 0.4 + hash(i, 3, 31) * 0.6 } end
  local function skyColours(night, dusk)
    -- top, foot
    local tr, tg, tb = 0.40 + dusk * 0.25, 0.64 - dusk * 0.12, 0.94 - dusk * 0.3
    local fr, fg, fb = 0.80 + dusk * 0.18, 0.90 - dusk * 0.22, 1.0 - dusk * 0.45
    tr, tg, tb = tr + (0.03 - tr) * night, tg + (0.05 - tg) * night, tb + (0.16 - tb) * night
    fr, fg, fb = fr + (0.10 - fr) * night, fg + (0.13 - fg) * night, fb + (0.30 - fb) * night
    return tr, tg, tb, fr, fg, fb
  end
  local function drawSky(G, w, h, night, dusk, t)
    if not sky then
      local ok, m = pcall(G.newMesh, { { 0, 0, 0, 0, 1, 1, 1, 1 }, { 1, 0, 0, 0, 1, 1, 1, 1 },
        { 1, 1, 0, 0, 1, 1, 1, 1 }, { 0, 1, 0, 0, 1, 1, 1, 1 } }, "fan", "dynamic")
      sky = ok and m or false
    end
    local tr, tg, tb, fr, fg, fb = skyColours(night, dusk)
    if sky then
      sky:setVertex(1, 0, 0, 0, 0, tr, tg, tb, 1)
      sky:setVertex(2, w, 0, 0, 0, tr, tg, tb, 1)
      sky:setVertex(3, w, h, 0, 0, fr, fg, fb, 1)
      sky:setVertex(4, 0, h, 0, 0, fr, fg, fb, 1)
      G.setColor(1, 1, 1, 1)
      G.draw(sky)
    else
      G.clear(tr, tg, tb, 1)
    end
    if night > 0.2 then
      for i = 1, #STARS do
        local s = STARS[i]
        local tw = 0.6 + 0.4 * sin(t * 2 + i)
        G.setColor(1, 1, 1, (night - 0.2) * s[3] * tw)
        local sz = max(1, h / 300)
        G.rectangle("fill", s[1] * w, s[2] * h, sz, sz)
      end
    end
  end

  local function light(night, dusk)
    -- (the sun goes round and down; the moon's light is cool and dim)
    SUN[1], SUN[2], SUN[3] = 0.42, 0.78, 0.46
    local l = sqrt(SUN[1] ^ 2 + SUN[2] ^ 2 + SUN[3] ^ 2)
    SUN[1], SUN[2], SUN[3] = SUN[1] / l, SUN[2] / l, SUN[3] / l
    SUN_COLOR[1] = 0.72 + dusk * 0.2 - night * 0.52
    SUN_COLOR[2] = 0.70 - dusk * 0.05 - night * 0.5
    SUN_COLOR[3] = 0.64 - dusk * 0.18 - night * 0.36
    AMBIENT[1] = 0.42 - night * 0.24
    AMBIENT[2] = 0.44 - night * 0.22
    AMBIENT[3] = 0.48 - night * 0.14
  end

  -- the flat fallback: the land's cells as polygons through the same camera
  local function drawFlat(G, region, rect)
    return drawFlatLand(G, region, rect)
  end
  function drawFlatLand(G, region, rect)
    local t, x0, z0, st = region.terrain, region.x0, region.z0, region.step
    G.setColor(0.24, 0.5, 0.84, 1)
    G.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
    local stride = 4
    for j = 0, t.rows - 1 - stride, stride do
      for i = 0, t.cols - 1 - stride, stride do
        local k = j * t.cols + i + 1
        if t.h[k] > 0 then
          local h = t.h[k]
          local ax, ay = project(x0 + i * st, h, z0 + j * st)
          local bx, by = project(x0 + (i + stride) * st, h, z0 + j * st)
          local cx, cy = project(x0 + (i + stride) * st, h, z0 + (j + stride) * st)
          local dx, dy = project(x0 + i * st, h, z0 + (j + stride) * st)
          if ax and bx and cx and dx then
            G.setColor(t.r[k], t.g[k], t.b[k], 1)
            G.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
          end
        end
      end
    end
  end

  -- the region into rect (window pixels) at time t; night / dusk 0..1 -> true when drawn in 3D
  function R.draw(G, region, rect, t, night, dusk, storm)
    night, dusk = night or 0, dusk or 0
    local sh = getShader(G)
    local m = sh and meshes(G, region)
    local w, h = max(1, floor(rect.w)), max(1, floor(rect.h))
    local c = m and target(G, w, h)
    frosted = false
    if not c then
      drawFlat(G, region, rect)
      return false
    end
    G.push("all")
    G.origin()
    G.setScissor()
    G.setCanvas(TARGET)
    G.clear(0, 0, 0, 0, false, true)
    G.setShader()
    G.setDepthMode("always", false)
    drawSky(G, w, h, night, dusk, t)
    light(night, dusk)
    CLOUD[1], CLOUD[2] = region.x0 - 2, region.w + 4
    G.setShader(sh)
    sh:send("uViewProj", "column", VPF)
    pcall(sh.send, sh, "uTime", t % 3600)
    pcall(sh.send, sh, "uCloud", CLOUD)
    pcall(sh.send, sh, "uEye", EYE)
    pcall(sh.send, sh, "uSun", SUN)
    pcall(sh.send, sh, "uSunColor", SUN_COLOR)
    pcall(sh.send, sh, "uAmbient", AMBIENT)
    pcall(sh.send, sh, "uNight", night)
    local stormM = storm and stormOf(G, storm.kind)
    local flash = 0
    if stormM then
      local look = STORM_LOOK[storm.kind]
      STORM[1], STORM[2], STORM[3], STORM[4] = storm.x, storm.z, storm.grow, look.spin
      STORM_AT[1], STORM_AT[2], STORM_AT[3] = storm.x, storm.z, storm.grow
      STORM_TINT[1], STORM_TINT[2], STORM_TINT[3], STORM_TINT[4] = look[1], look[2], look[3], look[4]
      if storm.kind == "rain" then flash = (R.lightning(t)) * storm.grow end
    else
      STORM_AT[3], STORM_TINT[4] = 0, 0
    end
    pcall(sh.send, sh, "uStorm", STORM)
    pcall(sh.send, sh, "uStormAt", STORM_AT)
    pcall(sh.send, sh, "uStormTint", STORM_TINT)
    pcall(sh.send, sh, "uFlash", flash)
    G.setColor(1, 1, 1, 1)
    G.setDepthMode("lequal", true)
    G.setMeshCullMode("none")
    G.draw(m.land)
    if m.slab then G.draw(m.slab) end
    if m.towns then G.draw(m.towns) end
    if m.sea then G.draw(m.sea) end
    -- (a rain cloud is solid; the dust is haze, seen through itself)
    if stormM and storm.kind == "rain" then G.draw(stormM.solid) end
    G.setDepthMode("lequal", false)
    if stormM and storm.kind ~= "rain" then G.draw(stormM.solid) end
    if stormM then G.draw(stormM.fine) end
    -- (solid, so they write depth: a cloud's far side stays hidden behind its near side)
    G.setDepthMode("lequal", true)
    if m.clouds then G.draw(m.clouds) end
    G.setDepthMode("always", false)
    G.setShader()
    -- (the blurred copy for the glass)
    local b = blurTarget(G, max(1, floor(w / 4)), max(1, floor(h / 4)))
    if b then
      G.setCanvas(b)
      G.setColor(1, 1, 1, 1)
      G.draw(c, 0, 0, 0, smallW / w, smallH / h)
      frosted = true
    end
    G.setCanvas()
    G.pop()
    G.setColor(1, 1, 1, 1)
    G.draw(c, rect.x, rect.y)
    return true
  end

  return R
end
