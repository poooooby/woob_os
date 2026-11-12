-- The 3D map's drawing: the region (src/map3d/model.lua) as meshes of our own, drawn into a canvas
-- with a depth buffer and one shader of our own (the engine has none in 3D):
--   - the land: the heightmap in the Town Map's own colours, snow on the peaks, a stone slab under
--     it (the map stands like a model on a table), trees on the forests' greens
--   - the towns: little houses, a red-roofed Center, a blue-roofed Mart, a bigger Gym; their
--     windows light up at night
--   - the sea: a sheet that waves (in the shader), glints by day; the clouds drift over it all
--   - a storm, when there's one to show: Kyogre's rain (dark clouds, falling streaks, lightning) or
--     Groudon's sand (dust wheeling round), two kept meshes moved and animated in the shader
--   - the everyday weather (Ruby / Sapphire / Emerald), far quieter than the storms: a few thin
--     raindrops under pale clouds, ash or sand drifting, a low fog, an overcast; the ground under it
--     softly tinted; each kind's bits and clouds one kept mesh, stretched over each place in the shader
--   - the sky: day, dusk, night (stars), from the device's clock
-- With no shader or mesh (the headless tests, an old GPU) the same camera draws the land as flat
-- polygons, so the overlays (src/map3d/scene.lua) work alike.
--
--   R = Render(deps)                 deps: log(fmt, ...) ; towns (src/map3d/towns.lua: the buildings)
--   R.camera(cam, rect)              cam = { x, y, z (the target), yaw, pitch, dist } ; rect = window
--                                    pixels { x, y, w, h } -> the view-projection kept
--   R.project(x, y, z) -> sx, sy, depth (window pixels; nil behind the eye)
--   R.draw(G, region, rect, t, night, dusk, storm, weather) -> true (3D) | false (the flat fallback drew it)
--                                    storm = { x, z, kind = "rain" | "sand", grow = 0..1 } | nil
--                                    weather = { { kind, x, z, rx, rz, y, y0, grow } } | nil (src/map3d/
--                                    model.lua's M.weather, each with how grown)
--   R.weatherFlash(t, i) -> 0..1: the i-th weather's thunderstorm flash (dim, now and then)
--   R.lightning(t) -> 0..1 (its flash; 0: none), its offset x, z from the storm's middle, its number
--   R.night(hour, minute) -> 0 (day) .. 1 (night) ; R.dusk(hour, minute) -> 0..1
--   R.frost(G, x, y, w, h, rad) -> true: frosted glass (the map blurred) in that rounded rect
--   R.flatCamera(cx, cz, half, rect) ; R.drawPicture(G, region, rect) -> the flat map, north up (the
--   world's own picture, its tiles' art near; else the game's Town Map picture) ; R.drawLand(G, region,
--   rect) (flat, without the picture)

local floor, max, min, abs, sqrt, sin, cos, pi = math.floor, math.max, math.min, math.abs, math.sqrt, math.sin,
  math.cos, math.pi

local SLAB = -0.9          -- the slab's foot
local SEA_ALPHA = 0.78
local FOV = 0.72           -- radians, top to bottom
local NEAR, FAR = 0.3, 260
-- (the near plane moves out with the camera: a far view keeps its depth sharp, so ground just over the
-- water never flickers under it; a close one comes in near)
local NEAR_K, NEAR_MIN, NEAR_MAX = 0.05, 0.05, 2.5
local PROFILE = false

local FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexNormal", "float", 3 },
  { "VertexColor", "byte", 4 },
  { "VertexFlag", "float", 1 },
}
-- flags (VertexFlag): 0 lit, 1 the sea, 2 a window (lit at night), 3 a cloud (drifts; its normal is
-- its anchor), 4 unlit (the slab's sides keep their colour), 5 a rain streak, 6 a storm's puff of cloud or
-- dust, 7 a grain of sand, 8 a bit of everyday weather (its seed in the normal), 9 a lobe of its cloud or
-- haze (its anchor in the normal); the world built to scale (FORMAT_W): 10 the ground, 11 a forest's
-- top, 12 a building's front
local F_SEA, F_WINDOW, F_CLOUD = 1, 2, 3
local F_RAIN, F_PUFF, F_GRAIN = 5, 6, 7
local F_WX, F_WXPUFF = 8, 9
local WX_MAX = 12          -- the most weathers shown at once (the shader's arrays)

-- the tiles' own art, full size, for the world built to scale (src/map3d/render.lua's groundArt): which
-- cell of the atlas each tile is (the index: one texel a tile, its number in red + green * 256, 0 for
-- none), the atlas's 16 x 16 cells and their half- and quarter-size copies below them. Near, each art
-- pixel sharp; further off the smaller copies, then the picture (two pixels a tile), so nothing
-- shimmers as it moves. `r`: screen pixels an art pixel; `w` how much of the art shows
local HIGHP = [[
#if defined(GL_ES) && defined(PIXEL) && defined(GL_FRAGMENT_PRECISION_HIGH)
precision highp float;
#endif
]]
local ART_GLSL = [[
uniform Image uIndex;
uniform Image uAtlas;
uniform vec4 uArtSize;   // the world's columns and rows, the atlas's width and height (pixels); 0: no art
uniform vec2 uArtLv;     // where the half-size cells start and the quarter-size ones (the atlas's y)
vec3 tileArt(vec2 tc, vec3 pic, float r, out float w) {
  w = 0.0;
  if (uArtSize.x < 0.5 || r < 0.125) return pic;
  vec2 t = tc * uArtSize.xy;
  vec2 cell = floor(t);
  vec4 ix = Texel(uIndex, (cell + 0.5) / uArtSize.xy);
  float id = floor(ix.r * 255.0 + 0.5) + floor(ix.g * 255.0 + 0.5) * 256.0;
  if (id < 0.5) return pic;
  id -= 1.0;
  vec2 c = vec2(mod(id, 128.0), floor(id / 128.0 + 0.0001));
  vec2 f = clamp(t - cell, 0.0, 0.9999);
  vec2 inv = 1.0 / uArtSize.zw;
  vec3 a16 = Texel(uAtlas, (c * 16.0 + floor(f * 16.0) + 0.5) * inv).rgb;
  vec3 a8 = Texel(uAtlas, (vec2(0.0, uArtLv.x) + c * 8.0 + clamp(f * 8.0, 0.5, 7.5)) * inv).rgb;
  vec3 a4 = Texel(uAtlas, (vec2(0.0, uArtLv.y) + c * 4.0 + clamp(f * 4.0, 0.5, 3.5)) * inv).rgb;
  vec3 a = mix(a8, a16, clamp((r - 0.5) * 2.0, 0.0, 1.0));
  a = mix(a4, a, clamp((r - 0.25) * 4.0, 0.0, 1.0));
  w = clamp((r - 0.125) * 8.0, 0.0, 1.0);
  return mix(pic, a, w);
}
]]

local ART_NONE = [[
vec3 tileArt(vec2 tc, vec3 pic, float r, out float w) {
  w = 0.0;
  return pic;
}
]]

local function shaderSource(art)
  return HIGHP .. [[
varying vec3 vNormal;
varying float vFlag;
varying float vWave;
varying float vFade;
varying vec2 vGround;
varying vec3 vRel;       // (where it is from the eye: the pixel stage's distance, no uniform shared)
#ifdef VERTEX
uniform mat4 uViewProj;
uniform float uTime;
uniform vec2 uCloud;
uniform vec3 uEye;
uniform vec4 uStorm;     // x, z, how grown (0..1), how fast it turns
uniform vec4 uWxArea;    // a weather's middle x, z and half its size x, z
uniform vec4 uWxMove;    // its fall (a fraction a second), its drift (a fraction a second), its top (the clouds'
                         // base; sand's band), how grown
uniform vec4 uWxLook;    // its bits' width and length, the ground (bits) or a flash (clouds), how its bits move
                         // (0 rain, 1 flakes, 2 sand)
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
    // (the wave's height scaled by the normal's y: the Town Map's sea 1, the world's calmer)
    p.y += ((sin(a) + sin(b)) * 0.018 + sin(c) * 0.008) * VertexNormal.y;
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
  } else if (VertexFlag > 6.5 && VertexFlag < 7.5) {
    vec3 a = VertexNormal;
    float turn = a.y * 6.2832 + uTime * (0.7 + 1.2 / (a.x + 0.5));
    vec3 c = vec3(uStorm.x + cos(turn) * a.x * uStorm.z, a.z + sin(uTime * 2.0 + a.y * 40.0) * 0.05,
                  uStorm.y + sin(turn) * a.x * uStorm.z);
    p = c + vec3(-sin(turn), 0.0, cos(turn)) * p.x * 0.06 + vec3(0.0, 1.0, 0.0) * p.y * 0.022;
    vNormal = vec3(0.0, 1.0, 0.0);
    vFade = uStorm.z;
  } else if (VertexFlag > 7.5 && VertexFlag < 8.5) {
    // (a raindrop falls straight, a flake sways down, a grain of sand blows across low)
    vec3 s = VertexNormal;
    float f = fract(s.y + uTime * uWxMove.x);
    vec2 u = s.xz;
    float y = mix(uWxMove.z, uWxLook.z, f);
    if (uWxLook.w > 1.5) {
      u.x = fract(s.x + uTime * uWxMove.y);
      y = uWxLook.z + 0.03 + s.y * uWxMove.z + sin(uTime * 2.1 + s.z * 37.0) * 0.03;
      f = 0.5;
    } else if (uWxLook.w > 0.5) {
      u.x = clamp(u.x + sin(uTime * 1.3 + s.y * 31.0) * 0.03, 0.0, 1.0);
    }
    vec2 at = uWxArea.xy + (u * 2.0 - 1.0) * uWxArea.zw;
    vec3 base = vec3(at.x, y, at.y);
    vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), uEye - base));
    if (uWxLook.w > 1.5) {
      p = base + vec3(1.0, 0.0, 0.0) * (p.y - 0.5) * uWxLook.y + vec3(0.0, 1.0, 0.0) * p.x * uWxLook.x;
    } else if (uWxLook.w > 0.5) {
      p = base + side * p.x * uWxLook.x + vec3(0.0, 1.0, 0.0) * (p.y - 0.5) * uWxLook.x * 2.0;
    } else {
      p = base + side * p.x * uWxLook.x + vec3(0.0, 1.0, 0.0) * p.y * uWxLook.y;
    }
    float edge = min(min(u.x, 1.0 - u.x), min(u.y, 1.0 - u.y));
    vNormal = vec3(0.0, 1.0, 0.0);
    vFade = uWxMove.w * smoothstep(0.0, 0.18, edge) * smoothstep(0.0, 0.08, f) * (1.0 - smoothstep(0.92, 1.0, f))
      * smoothstep(0.4, 1.4, distance(base, uEye));
  } else if (VertexFlag > 8.5 && VertexFlag < 9.5) {
    // (a lobe of cloud or haze drifting slowly along, growing in where it wraps round)
    vec3 a = VertexNormal;
    vec2 u = vec2(fract(a.x + uTime * uWxMove.y), a.z);
    float edge = min(min(u.x, 1.0 - u.x), min(u.y, 1.0 - u.y));
    vec2 at = uWxArea.xy + (u * 2.0 - 1.0) * uWxArea.zw;
    float k = uWxMove.w * smoothstep(0.0, 0.2, edge) * (1.0 + sin(uTime * 0.6 + a.x * 23.0) * 0.05);
    p = vec3(at.x, uWxMove.z + a.y, at.y) + p * k;
    vNormal = vec3(0.0, 1.0, 0.0);
    vWave = uWxLook.z;
    vFade = k * smoothstep(1.0, 3.2, distance(p, uEye));
  }
  vGround = p.xz;
  vRel = p - uEye;
  return uViewProj * vec4(p, 1.0);
}
#endif
#ifdef PIXEL
]] .. (art and ART_GLSL or ART_NONE) .. [[
uniform float uArtK;     // screen pixels an art pixel at one world unit from the eye
uniform vec3 uSun;
uniform vec3 uSunColor;
uniform vec3 uAmbient;
uniform float uNight;
uniform vec3 uStormAt;   // x, z, how grown
uniform vec4 uStormTint; // what it does to the ground under it: a colour, how much
uniform float uFlash;
uniform vec4 uWxBox[12];  // each everyday weather's x, z and half its size x, z (0: none)
uniform vec4 uWxTint[12]; // what it does to the ground under it: a colour, how much
vec3 underWeather(vec3 c) {
  for (int i = 0; i < 12; i++) {
    vec4 b = uWxBox[i];
    if (b.z > 0.0) {
      vec2 d = abs(vGround - b.xy) / b.zw;
      float r = sqrt(sqrt(d.x * d.x * d.x * d.x + d.y * d.y * d.y * d.y));
      c = mix(c, c * uWxTint[i].rgb, (1.0 - smoothstep(0.7, 1.1, r)) * uWxTint[i].a);
    }
  }
  return c;
}
vec3 underStorm(vec3 c) {
  float k = uStormAt.z * (1.0 - smoothstep(1.2, 2.6, distance(vGround, uStormAt.xy)));
  return mix(c, c * uStormTint.rgb, k * uStormTint.a) + vec3(0.25, 0.28, 0.4) * uFlash * k;
}
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  if (vFlag > 9.5) {
    // (the overworld built to scale: the tiles' own colours from the mesh's picture, their own art near
    // on what faces up, a forest's top (11) and a building's front (12); where the art doesn't show, a
    // forest's top each tile a round crown, lit on its sun side, dark between them; 16 tiles a world unit)
    vec3 pic = Texel(tex, tc).rgb;
    vec3 n = normalize(vNormal);
    vec3 c = pic;
    float near = 0.0;
    if (n.y > 0.5 || vFlag > 10.5) {
      float dist = length(vRel);
      float w = 0.0;
      c = tileArt(tc, pic, uArtK / max(dist, 0.001), w);
      // (the crowns fading out with distance: far off the pattern is finer than a pixel and would shimmer)
      if (vFlag > 10.5 && vFlag < 11.5 && n.y > 0.9) near = (1.0 - smoothstep(3.0, 9.0, dist)) * (1.0 - w);
    }
    vec3 base = color.rgb * c;
    if (near > 0.0) {
      vec2 f = fract(vGround * 16.0) - 0.5;
      float r = length(f);
      n = normalize(mix(n, vec3(f.x * 1.7, 1.0, f.y * 1.7), near));
      base *= 1.0 - smoothstep(0.3, 0.62, r) * 0.42 * near;
    }
    float d = max(dot(n, uSun), 0.0);
    return vec4(underStorm(underWeather(base * (uAmbient + uSunColor * d))), color.a);
  }
  if (vFlag > 5.5 && vFlag < 6.5) {
    float lightOn = max(dot(normalize(vNormal), uSun), 0.0);
    return vec4(color.rgb * (uAmbient + uSunColor * lightOn) + vec3(0.5, 0.55, 0.75) * uFlash, color.a * vFade);
  }
  if (vFlag > 8.5 && vFlag < 9.5) {
    // (a weather's cloud: its shading baked in, the sky's light on it, a dim flash in a thunderstorm's)
    return vec4(color.rgb * min(uAmbient + uSunColor * 0.75, vec3(1.15)) + vec3(0.42, 0.46, 0.6) * vWave,
                color.a * vFade);
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
    return vec4(underStorm(underWeather(color.rgb * (uAmbient + uSunColor * (0.55 + 0.45 * d)) + vec3(glint))), color.a);
  }
  if (vFlag > 1.5 && vFlag < 2.5) lit = mix(lit, vec3(1.0, 0.82, 0.42), uNight);
  return vec4(underStorm(underWeather(lit)), color.a);
}
#endif
]]
end

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

-- the flat map of the world built to scale: its picture (two pixels a tile), the tiles' own art over it
-- when near enough
local FLAT_ART = HIGHP .. ART_GLSL .. [[
uniform float uArtR;     // screen pixels an art pixel
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec3 pic = Texel(tex, tc).rgb;
  float w = 0.0;
  return vec4(tileArt(tc, pic, uArtR, w), 1.0) * color;
}
]]

return function(deps)
  deps = deps or {}
  local R = {}
  local drawFlatLand, sendArt

  -- ------- the camera: a kept view-projection (column-major, for the shader) and its use

  local VP = {}
  for i = 1, 16 do VP[i] = 0 end
  local VPF = {}          -- the same, upside down (a canvas's rows run the other way)
  for i = 1, 16 do VPF[i] = 0 end
  local view = { x = 0, y = 0, w = 1, h = 1 }
  local EYE = { 0, 0, 0 }
  local nearNow = NEAR
  R.vp = VP

  R.FOV = FOV
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
    local near = max(NEAR_MIN, min(NEAR_MAX, cam.dist * NEAR_K))
    local far = max(FAR, cam.dist * 6)
    nearNow = near
    local a, b = (far + near) / (near - far), (2 * far * near) / (near - far)
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
    nearNow = NEAR
    for i = 1, 16 do VPF[i] = VP[i] end
    view.x, view.y, view.w, view.h = rect.x, rect.y, rect.w, rect.h
  end

  -- the Town Map's own picture under the flat camera (pixel for pixel, sharp) -> false without it
  local pictureQuads = setmetatable({}, { __mode = "k" })
  local SEA_DARK = { 0.16, 0.22, 0.42 }
  local meshesOf = setmetatable({}, { __mode = "k" })
  local flatShader, flatTried = nil, false
  function R.drawPicture(G, region, rect)
    -- (the world built to scale: its own tiles' picture, two pixels a tile, once its meshes are made;
    -- the tiles' own art over it near)
    local wm = region.world and meshesOf[region]
    if region.world then
      local pic = wm and wm.picture
      local ax, ay = R.project(region.x0, 0, region.z0)
      local bx = R.project(region.x0 + 1, 0, region.z0)
      if not (pic and ax and bx) then return false end
      local s = (bx - ax) / (2 * (region.unit or 16))
      G.setColor(SEA_DARK[1], SEA_DARK[2], SEA_DARK[3], 1)
      G.rectangle("fill", rect.x, rect.y, rect.w, rect.h)
      G.setColor(1, 1, 1, 1)
      if wm.art and not flatTried then
        flatTried = true
        local ok, sh = pcall(G.newShader, FLAT_ART)
        flatShader = ok and sh or nil
        if not ok and deps.log then deps.log("the flat map's shader failed: %s", tostring(sh)) end
      end
      local sh = wm.art and flatShader
      local prev = sh and G.getShader and G.getShader() or nil
      if sh then
        G.setShader(sh)
        sendArt(sh, wm.art)
        -- (a picture pixel is half a tile: eight art pixels)
        pcall(sh.send, sh, "uArtR", s / 8)
      end
      G.draw(pic, ax, ay, 0, s, s)
      if sh then G.setShader(prev) end
      return true
    end
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
    if cw <= nearNow * 0.5 then return nil end
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

  -- ------- the overworld built to scale (src/map3d/world.lua): its tiles' colours as one picture
  -- (each tile's four quarters), the ground in chunks of terraces (flat tops of one height merged, walls
  -- only where a tile stands over its neighbour), forests a raised canopy (crowns in the shader), each
  -- building a block: its roof's art on top, its front wall's art (the door, the windows) standing up
  -- as its face. Every vertex carries where it is in the picture.
  local FORMAT_W = {
    { "VertexPosition", "float", 3 },
    { "VertexNormal", "float", 3 },
    { "VertexColor", "byte", 4 },
    { "VertexFlag", "float", 1 },
    { "VertexTexCoord", "float", 2 },
  }
  -- (10 the ground, 11 a forest's top, 12 a building's front: the tiles' art near on 11, 12 and what
  -- faces up)
  local F_GROUND, F_CANOPY, F_FRONT = 10, 11, 12
  local CHUNK = 64
  -- (built in the background, a few milliseconds at a time: a yield whenever the slice is used up)
  local rslice = { start = 0, budget = 0.004 }
  local function rclock() return love and love.timer and love.timer.getTime() or os.clock() end
  local rstage, rlast = "", 0
  local function rbreathe(stage)
    if stage then rstage = stage end
    local now = rclock()
    if PROFILE and now - rlast > 0.03 and rlast > 0 and deps.log then deps.log("map build gap %.0f ms at %s", (now - rlast) * 1000, rstage) end
    rlast = now
    if coroutine.running() and now - rslice.start > rslice.budget then
      coroutine.yield()
      rlast = rclock()
    end
  end
  local TREE_H, SMALL_H = 0.08, 0.035
  local CLIFF_SHADE, TREE_SHADE, BUILD_SHADE = 0.72, 0.5, 0.82

  -- (a world mesh from one flat array, 13 numbers a vertex: no table per vertex, so building the
  -- region leaves little for the collector)
  local VW = 13
  -- (a build that's kept on disk (src/map3d/cache.lua): each mesh's bytes, as the GPU takes them,
  -- gathered as it's made; nil when it isn't kept)
  local rkeep = nil
  local Mc = deps.mapCache
  local function newMeshW(G, flat, map, slot)
    local n = floor(#flat / VW)
    if n == 0 then return nil end
    local ok, m = pcall(G.newMesh, FORMAT_W, n, "triangles", "static")
    if not ok then
      if deps.log then deps.log("the map's mesh failed: %s", tostring(m)) end
      return nil
    end
    for i = 1, n do
      local b = (i - 1) * VW
      m:setVertex(i, flat[b + 1], flat[b + 2], flat[b + 3], flat[b + 4], flat[b + 5], flat[b + 6], flat[b + 7],
        flat[b + 8], flat[b + 9], flat[b + 10], flat[b + 11], flat[b + 12], flat[b + 13])
      if i % 4096 == 0 then rbreathe() end
    end
    if map then pcall(m.setVertexMap, m, map) end
    if rkeep and slot then
      -- (a failure here only means it isn't kept: the map is made all the same)
      local okV, v = pcall(Mc.packW, flat, n, rbreathe)
      local okI, i = true, nil
      if map then okI, i = pcall(Mc.packIdx, map, rbreathe) end
      if okV and okI and v and (i or not map) then
        rkeep.meshes[#rkeep.meshes + 1] = { slot = slot, fmt = "W", n = n, ni = map and #map or 0, v = v, i = i }
      else
        rkeep = nil
      end
    end
    return m
  end

  local rprog = nil   -- (the job's progress, 0..1: { r })
  local function pictureImage(G, data)
    -- (with its smaller copies, so far off it doesn't sparkle as it moves; without, where the GPU
    -- can't)
    local okI, img = pcall(G.newImage, data, { mipmaps = true })
    if okI and img then
      pcall(img.setMipmapFilter, img, "linear")
    else
      okI, img = pcall(G.newImage, data)
    end
    if not (okI and img) then return nil end
    pcall(img.setFilter, img, "linear", "linear")
    pcall(img.setWrap, img, "clamp", "clamp")
    return img
  end
  -- -> the image, its pixels
  local function groundPicture(G, region)
    local W = region.world
    local LI = love and love.image
    if not (LI and LI.newImageData and G.newImage) then return nil end
    local ok, data = pcall(LI.newImageData, W.cols * 2, W.rows * 2)
    if not (ok and data) then return nil end
    for j = 0, W.rows - 1 do
      for i = 0, W.cols - 1 do
        local k = j * W.cols + i + 1
        for q = 0, 3 do
          local r, g, b = W.art(k, q)
          if not r then r, g, b = 38, 78, 160 end
          data:setPixel(i * 2 + q % 2, j * 2 + floor(q / 2), r / 255, g / 255, b / 255, 1)
        end
      end
      if rprog then rprog.r = 0.1 * j / W.rows end
      rbreathe()
    end
    return pictureImage(G, data), data
  end
  -- the art's two images (the index sharp, the atlas smooth) -> index, atlas | nil
  local function artImages(G, index, atlas)
    local okI, iImg = pcall(G.newImage, index)
    local okT, aImg = pcall(G.newImage, atlas)
    if not (okI and iImg and okT and aImg) then return nil end
    pcall(iImg.setFilter, iImg, "nearest", "nearest")
    pcall(iImg.setWrap, iImg, "clamp", "clamp")
    pcall(aImg.setFilter, aImg, "linear", "linear")
    pcall(aImg.setWrap, aImg, "clamp", "clamp")
    return iImg, aImg
  end

  -- the tiles' own art at full size (ART_GLSL): every tile the world uses once in an atlas, 16 x 16 a
  -- cell, 128 cells a row, the half- and quarter-size copies under them; and the index, one texel a
  -- tile, its cell's number (from 1) -> { index, atlas, size = { cols, rows, aw, ah }, lv = { y8, y4 } } |
  -- nil (no art: the picture alone)
  local ATLAS_ROW = 128
  local ATLAS_MAX = ATLAS_ROW * floor(4096 / 28)
  local function groundArt(G, region)
    local W = region.world
    local LI = love and love.image
    if not (W.tile and W.mid and W.pix and LI and LI.newImageData and G.newImage) then return nil end
    local cols, rows, midA, pixA = W.cols, W.rows, W.mid, W.pix
    -- (the tiles used, each once: its tileset's number and its metatile)
    local cellOf, keys = {}, {}
    for k = 1, cols * rows do
      local pi = pixA[k] or 0
      if pi > 0 then
        local key = pi * 65536 + (midA[k] or 0)
        if cellOf[key] == nil and #keys < ATLAS_MAX then
          keys[#keys + 1] = key
          cellOf[key] = #keys
        end
      end
      if k % 65536 == 0 then rbreathe() end
    end
    if #keys == 0 then return nil end
    local cr = math.ceil(#keys / ATLAS_ROW)
    local aw, ah = ATLAS_ROW * 16, cr * 28
    local y8, y4 = cr * 16, cr * 24
    local okA, atlas = pcall(LI.newImageData, aw, ah)
    local okX, index = pcall(LI.newImageData, cols, rows)
    if not (okA and atlas and okX and index) then return nil end
    rbreathe("art")
    local px = {}
    for id = 1, #keys do
      local key = keys[id]
      if W.tile(floor(key / 65536), key % 65536, px) then
        local cx, cy = (id - 1) % ATLAS_ROW, floor((id - 1) / ATLAS_ROW)
        local x16, y16 = cx * 16, cy * 16
        for y = 0, 15 do
          for x = 0, 15 do
            local o = (y * 16 + x) * 3
            atlas:setPixel(x16 + x, y16 + y, px[o + 1] / 255, px[o + 2] / 255, px[o + 3] / 255, 1)
          end
        end
        -- (the smaller copies: each pixel the mean of the 2 x 2 or 4 x 4 under it)
        for s = 2, 4, 2 do
          local n = 16 / s
          local bx, by = cx * n, (s == 2 and y8 or y4) + cy * n
          for y = 0, n - 1 do
            for x = 0, n - 1 do
              local r, g, b = 0, 0, 0
              for dy = 0, s - 1 do
                for dx = 0, s - 1 do
                  local o = ((y * s + dy) * 16 + x * s + dx) * 3
                  r, g, b = r + px[o + 1], g + px[o + 2], b + px[o + 3]
                end
              end
              local k = s * s * 255
              atlas:setPixel(bx + x, by + y, r / k, g / k, b / k, 1)
            end
          end
        end
      else
        cellOf[key] = 0
      end
      if id % 32 == 0 then
        if rprog then rprog.r = 0.1 + 0.15 * id / #keys end
        rbreathe()
      end
    end
    rbreathe("index")
    for j = 0, rows - 1 do
      local row = j * cols
      for i = 0, cols - 1 do
        local k = row + i + 1
        local pi = pixA[k] or 0
        local id = pi > 0 and cellOf[pi * 65536 + (midA[k] or 0)] or 0
        if id > 0 then index:setPixel(i, j, (id % 256) / 255, floor(id / 256) / 255, 0, 1) end
      end
      if j % 16 == 0 then rbreathe() end
    end
    local iImg, aImg = artImages(G, index, atlas)
    if not iImg then return nil end
    if PROFILE and deps.log then deps.log("the map's art: %d tiles, an atlas %d x %d", #keys, aw, ah) end
    -- (its pixels kept while the build is kept on disk; else let go)
    local art = { index = iImg, atlas = aImg, size = { cols, rows, aw, ah }, lv = { y8, y4 } }
    if rkeep then
      art.data = { index = index, atlas = atlas }
    else
      pcall(index.release, index)
      pcall(atlas.release, atlas)
    end
    return art
  end

  -- (a quad of the world's: four corners, one normal, one shade, the picture's place for each corner)
  local function corner(f, o, x, y, z, nx, ny, nz, s, flag, u, v)
    f[o + 1], f[o + 2], f[o + 3], f[o + 4], f[o + 5], f[o + 6] = x, y, z, nx, ny, nz
    f[o + 7], f[o + 8], f[o + 9], f[o + 10], f[o + 11], f[o + 12], f[o + 13] = s, s, s, 1, flag, u, v
  end
  local function faceW(flat, map, ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz, nx, ny, nz, s, flag,
                       ua, va, ub, vb, uc, vc, ud, vd)
    local o = #flat
    local b = o / VW
    corner(flat, o, ax, ay, az, nx, ny, nz, s, flag, ua, va)
    corner(flat, o + VW, bx, by, bz, nx, ny, nz, s, flag, ub, vb)
    corner(flat, o + VW * 2, cx, cy, cz, nx, ny, nz, s, flag, uc, vc)
    corner(flat, o + VW * 3, dx, dy, dz, nx, ny, nz, s, flag, ud, vd)
    local n = #map
    map[n + 1], map[n + 2], map[n + 3], map[n + 4], map[n + 5], map[n + 6] = b + 1, b + 2, b + 3, b + 1, b + 3, b + 4
  end

  -- (one vertex of the world's -> its number; a triangle of three)
  local function vtxW(flat, x, y, z, nx, ny, nz, s, flag, u, v)
    local o = #flat
    corner(flat, o, x, y, z, nx, ny, nz, s, flag, u, v)
    return o / VW + 1
  end
  local function triW(map, a, b, c)
    local n = #map
    map[n + 1], map[n + 2], map[n + 3] = a, b, c
  end

  -- one chunk of the world (tiles i0..i1-1, j0..j1-1 of its grid) -> its solid mesh, its water's mesh:
  --   - the ground: flat tops of one height merged, walls where a tile stands over its neighbour
  --   - the forests: on their edges each tree a rounded crown (its middle up, its corners as high as
  --     the trees round them, a dark skirt down to the ground where it meets open ground), inside a
  --     smooth canopy at the trees' height (the shader's crowns on it)
  --   - bridges and logs: a deck (its own art on top), rails along a bridge's open sides, posts down
  --     into the water
  --   - the water: its surface over each water tile, at its own level (the sea's, a lake's), in pieces
  --     no wider than a world unit (the shader's waves need their corners)
  local SEA_RGB = { 0.24, 0.52, 0.86 }
  local WAVE = 0.35
  local NBR4 = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
  local function worldChunk(G, region, i0, j0, i1, j1)
    local W, C, Hh = region.world, region.classes, region.heights
    local cols, rows, h, cls, ws, deck = W.cols, W.rows, W.h, W.cls, W.ws, W.deck
    local MT = region.unit
    local ox, oz = W.x0, W.y0
    local TREE, SMALL, LOG = C.TREE, C.SMALL, C.LOG
    local function at(i, j)
      if i < 0 or j < 0 or i >= cols or j >= rows then return nil end
      return j * cols + i + 1
    end
    local function surf(i, j)
      local k = at(i, j)
      if not k then return Hh.SEA_BED end
      if cls[k] == SMALL then return h[k] + SMALL_H end
      return h[k]
    end
    local function tree(i, j)
      local k = at(i, j)
      return k ~= nil and cls[k] == TREE
    end
    local flat, map = {}, {}
    rbreathe("tops")
    -- (the ground's tops)
    local used = {}
    for j = j0, j1 - 1 do
      for i = i0, i1 - 1 do
        local k = j * cols + i + 1
        if not used[k] then
          local sv = surf(i, j)
          local w = 1
          while i + w < i1 and not used[k + w] and surf(i + w, j) == sv do w = w + 1 end
          local d = 1
          while j + d < j1 do
            local whole = true
            for x = 0, w - 1 do
              if used[k + d * cols + x] or surf(i + x, j + d) ~= sv then whole = false break end
            end
            if not whole then break end
            d = d + 1
          end
          for y = 0, d - 1 do
            local row = k + y * cols
            for x = 0, w - 1 do used[row + x] = true end
          end
          local x0, z0, x1, z1 = (ox + i) / MT, (oz + j) / MT, (ox + i + w) / MT, (oz + j + d) / MT
          local u0, v0, u1, v1 = i / cols, j / rows, (i + w) / cols, (j + d) / rows
          faceW(flat, map, x0, sv, z0, x1, sv, z0, x1, sv, z1, x0, sv, z1, 0, 1, 0, 1, F_GROUND,
            u0, v0, u1, v0, u1, v1, u0, v1)
        end
      end
      rbreathe()
    end
    used = nil
    rbreathe("walls")
    -- (the ground's walls: runs merged, the picture along the tile's own edge)
    for j = j0, j1 - 1 do
      for side = 1, 2 do
        local nj = side == 1 and j + 1 or j - 1
        local z = (oz + j + (side == 1 and 1 or 0)) / MT
        local vv = (j + (side == 1 and 0.9 or 0.1)) / rows
        local nz = side == 1 and 1 or -1
        local i = i0
        while i < i1 do
          local a, b = surf(i, j), surf(i, nj)
          if a > b + 1e-4 then
            local w = 1
            while i + w < i1 and surf(i + w, j) == a and surf(i + w, nj) == b do w = w + 1 end
            local xa, xb = (ox + i) / MT, (ox + i + w) / MT
            local ua, ub = i / cols, (i + w) / cols
            faceW(flat, map, xa, a, z, xb, a, z, xb, b, z, xa, b, z, 0, 0, nz, CLIFF_SHADE, F_GROUND,
              ua, vv, ub, vv, ub, vv, ua, vv)
            i = i + w
          else
            i = i + 1
          end
        end
      end
      rbreathe()
    end
    for i = i0, i1 - 1 do
      for side = 1, 2 do
        local ni = side == 1 and i + 1 or i - 1
        local x = (ox + i + (side == 1 and 1 or 0)) / MT
        local uu = (i + (side == 1 and 0.9 or 0.1)) / cols
        local nx = side == 1 and 1 or -1
        local j = j0
        while j < j1 do
          local a, b = surf(i, j), surf(ni, j)
          if a > b + 1e-4 then
            local d = 1
            while j + d < j1 and surf(i, j + d) == a and surf(ni, j + d) == b do d = d + 1 end
            local za, zb = (oz + j) / MT, (oz + j + d) / MT
            local va, vb = j / rows, (j + d) / rows
            faceW(flat, map, x, a, za, x, a, zb, x, b, zb, x, b, za, nx, 0, 0, CLIFF_SHADE, F_GROUND,
              uu, va, uu, vb, uu, vb, uu, va)
            j = j + d
          else
            j = j + 1
          end
        end
      end
      rbreathe()
    end
    rbreathe("forests")
    -- (the forests: a corner's height, the trees' tops round it, lower the fewer trees there are)
    local function top(i, j) return h[at(i, j)] + TREE_H end
    local function cornerH(i, j, ci, cj)
      local n, sum = 0, 0
      for dj = -1, 0 do
        for di = -1, 0 do
          if tree(ci + di, cj + dj) then n, sum = n + 1, sum + top(ci + di, cj + dj) end
        end
      end
      local full = sum / max(1, n)
      if n == 4 then return full end
      local g = h[at(i, j)]
      local f = 0.28 + 0.72 * ((n - 1) / 3) ^ 1.3
      return g + (full - g) * f
    end
    local function edge(i, j)
      for dj = -1, 1 do
        for di = -1, 1 do
          if (di ~= 0 or dj ~= 0) and not tree(i + di, j + dj) then return true end
        end
      end
      return false
    end
    local px, pz, pu, pv, hc, vs = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
    for j = j0, j1 - 1 do
      local i = i0
      while i < i1 do
        if tree(i, j) then
          local k = j * cols + i + 1
          local u0, v0, u1, v1 = i / cols, j / rows, (i + 1) / cols, (j + 1) / rows
          local x0, z0, x1, z1 = (ox + i) / MT, (oz + j) / MT, (ox + i + 1) / MT, (oz + j + 1) / MT
          hc[1], hc[2], hc[3], hc[4] = cornerH(i, j, i, j), cornerH(i, j, i + 1, j), cornerH(i, j, i + 1, j + 1),
            cornerH(i, j, i, j + 1)
          px[1], px[2], px[3], px[4] = x0, x1, x1, x0
          pz[1], pz[2], pz[3], pz[4] = z0, z0, z1, z1
          pu[1], pu[2], pu[3], pu[4] = u0, u1, u1, u0
          pv[1], pv[2], pv[3], pv[4] = v0, v0, v1, v1
          local t = top(i, j)
          if not edge(i, j) then
            -- (inside: the canopy; a run at one height when its corners all are)
            if hc[1] == t and hc[2] == t and hc[3] == t and hc[4] == t then
              local w = 1
              while i + w < i1 and tree(i + w, j) and not edge(i + w, j) and top(i + w, j) == t
                  and cornerH(i + w, j, i + w + 1, j) == t and cornerH(i + w, j, i + w + 1, j + 1) == t do
                w = w + 1
              end
              local xw, uw = (ox + i + w) / MT, (i + w) / cols
              faceW(flat, map, x0, t, z0, xw, t, z0, xw, t, z1, x0, t, z1, 0, 1, 0, 1, F_CANOPY,
                u0, v0, uw, v0, uw, v1, u0, v1)
              i = i + w
            else
              for c = 1, 4 do vs[c] = vtxW(flat, px[c], hc[c], pz[c], 0, 1, 0, 1, F_CANOPY, pu[c], pv[c]) end
              triW(map, vs[1], vs[2], vs[3])
              triW(map, vs[1], vs[3], vs[4])
              i = i + 1
            end
          else
            -- (on the edge: a rounded crown, its middle up, a skirt where it meets open ground)
            local g = h[k]
            local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
            local peak = t + 0.012
            local mid = vtxW(flat, cx, peak, cz, 0, 1, 0, 1, F_CANOPY, (u0 + u1) / 2, (v0 + v1) / 2)
            local half = 0.5 / MT
            for c = 1, 4 do
              local dx, dz = (px[c] - cx) / half, (pz[c] - cz) / half
              local slope = (peak - hc[c]) / (half * 1.414)
              local nx, nz = dx * 0.7 * slope, dz * 0.7 * slope
              local l = sqrt(nx * nx + 1 + nz * nz)
              vs[c] = vtxW(flat, px[c], hc[c], pz[c], nx / l, 1 / l, nz / l, 1, F_CANOPY, pu[c], pv[c])
            end
            for c = 1, 4 do triW(map, mid, vs[c], vs[c % 4 + 1]) end
            for e = 1, 4 do
              local ni, nj = i + NBR4[e][1], j + NBR4[e][2]
              if not tree(ni, nj) then
                local a, b = e, e % 4 + 1
                -- (down to the tree's own ground: below that the ground's own wall stands on the same
                -- plane, and two faces on one plane flash)
                local floorY = g
                if hc[a] > floorY + 1e-4 or hc[b] > floorY + 1e-4 then
                  faceW(flat, map, px[a], hc[a], pz[a], px[b], hc[b], pz[b], px[b], floorY, pz[b], px[a], floorY, pz[a],
                    NBR4[e][1], 0, NBR4[e][2], TREE_SHADE, F_GROUND, pu[a], pv[a], pu[b], pv[b], pu[b], pv[b], pu[a], pv[a])
                end
              end
            end
            i = i + 1
          end
        else
          i = i + 1
        end
      end
      rbreathe()
    end
    rbreathe("decks")
    -- (bridges and logs: decks)
    local DT = 0.028
    for j = j0, j1 - 1 do
      for i = i0, i1 - 1 do
        local k = j * cols + i + 1
        local dk = deck and deck[k]
        if dk then
          local isLog = cls[k] == LOG
          local x0, z0, x1, z1 = (ox + i) / MT, (oz + j) / MT, (ox + i + 1) / MT, (oz + j + 1) / MT
          local u0, v0, u1, v1 = i / cols, j / rows, (i + 1) / cols, (j + 1) / rows
          faceW(flat, map, x0, dk, z0, x1, dk, z0, x1, dk, z1, x0, dk, z1, 0, 1, 0, 1, F_GROUND, u0, v0, u1, v0, u1, v1, u0, v1)
          local under = dk - DT
          faceW(flat, map, x0, under, z1, x1, under, z1, x1, under, z0, x0, under, z0, 0, -1, 0, 0.4, F_GROUND,
            u0, v1, u1, v1, u1, v0, u0, v0)
          px[1], pz[1], px[2], pz[2] = x0, z0, x1, z0
          for e = 1, 4 do
            local ni, nj = i + NBR4[e][1], j + NBR4[e][2]
            local nk = at(ni, nj)
            local nd = nk and deck[nk]
            if not nd or abs(nd - dk) > 0.01 then
              local ax, az, bx, bz
              if e == 1 then ax, az, bx, bz = x0, z0, x1, z0
              elseif e == 2 then ax, az, bx, bz = x1, z0, x1, z1
              elseif e == 3 then ax, az, bx, bz = x1, z1, x0, z1
              else ax, az, bx, bz = x0, z1, x0, z0 end
              local land = nk and not ws[nk] and abs(surf(ni, nj) - dk) < 0.05
              -- (its side; beside land only above the land's top: the land's own wall is below, on the
              -- same plane)
              local lo = under
              if nk and not ws[nk] then lo = max(under, surf(ni, nj)) end
              if dk > lo + 1e-4 then
                faceW(flat, map, ax, dk, az, bx, dk, bz, bx, lo, bz, ax, lo, az, NBR4[e][1], 0, NBR4[e][2],
                  0.6, F_GROUND, u0, v0, u1, v0, u1, v0, u0, v0)
              end
              if not isLog and not land then
                local r = 0.035
                faceW(flat, map, ax, dk + r, az, bx, dk + r, bz, bx, dk, bz, ax, dk, az, NBR4[e][1], 0, NBR4[e][2],
                  0.78, F_GROUND, u0, v0, u1, v0, u1, v0, u0, v0)
              end
            end
          end
          -- (a post under every other tile of a bridge over water, down to the bed)
          if not isLog and ws[k] and (i + j) % 2 == 0 then
            local pw = 0.12 / MT
            local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
            local b0 = h[k]
            faceW(flat, map, cx - pw, under, cz + pw, cx + pw, under, cz + pw, cx + pw, b0, cz + pw, cx - pw, b0, cz + pw,
              0, 0, 1, 0.5, F_GROUND, u0, v0, u0, v0, u0, v0, u0, v0)
            faceW(flat, map, cx + pw, under, cz - pw, cx - pw, under, cz - pw, cx - pw, b0, cz - pw, cx + pw, b0, cz - pw,
              0, 0, -1, 0.5, F_GROUND, u0, v0, u0, v0, u0, v0, u0, v0)
            faceW(flat, map, cx + pw, under, cz + pw, cx + pw, under, cz - pw, cx + pw, b0, cz - pw, cx + pw, b0, cz + pw,
              1, 0, 0, 0.5, F_GROUND, u0, v0, u0, v0, u0, v0, u0, v0)
            faceW(flat, map, cx - pw, under, cz - pw, cx - pw, under, cz + pw, cx - pw, b0, cz + pw, cx - pw, b0, cz - pw,
              -1, 0, 0, 0.5, F_GROUND, u0, v0, u0, v0, u0, v0, u0, v0)
          end
        end
      end
      rbreathe()
    end
    rbreathe("solid mesh")
    local solid = newMeshW(G, flat, map, "ground")
    rbreathe("water")
    flat, map = {}, {}
    -- (the water: runs of one surface, cut at every world unit)
    local wused = {}
    local CUT = MT
    for j = j0, j1 - 1 do
      for i = i0, i1 - 1 do
        local k = j * cols + i + 1
        local s = ws[k]
        if s and not wused[k] then
          local w = 1
          while i + w < i1 and w < CUT and not wused[k + w] and ws[k + w] == s and (i + w) % CUT ~= 0 do w = w + 1 end
          local d = 1
          while j + d < j1 and d < CUT and (j + d) % CUT ~= 0 do
            local whole = true
            for x = 0, w - 1 do
              local kk = k + d * cols + x
              if wused[kk] or ws[kk] ~= s then whole = false break end
            end
            if not whole then break end
            d = d + 1
          end
          for y = 0, d - 1 do
            local row = k + y * cols
            for x = 0, w - 1 do wused[row + x] = true end
          end
          local x0, z0, x1, z1 = (ox + i) / MT, (oz + j) / MT, (ox + i + w) / MT, (oz + j + d) / MT
          local b = #flat / VW
          -- (calmer waves than the Town Map's sea (their height in the normal's y): clear of the decks'
          -- undersides and the logs, which would otherwise flash where a wave crosses them)
          corner(flat, b * VW, x0, s, z0, 0, WAVE, 0, 1, F_SEA, 0, 0)
          corner(flat, (b + 1) * VW, x1, s, z0, 0, WAVE, 0, 1, F_SEA, 0, 0)
          corner(flat, (b + 2) * VW, x1, s, z1, 0, WAVE, 0, 1, F_SEA, 0, 0)
          corner(flat, (b + 3) * VW, x0, s, z1, 0, WAVE, 0, 1, F_SEA, 0, 0)
          for c = 0, 3 do
            local o = (b + c) * VW
            flat[o + 7], flat[o + 8], flat[o + 9], flat[o + 10] = SEA_RGB[1], SEA_RGB[2], SEA_RGB[3], SEA_ALPHA
          end
          triW(map, b + 1, b + 2, b + 3)
          triW(map, b + 1, b + 3, b + 4)
        end
      end
      rbreathe()
    end
    rbreathe("water mesh")
    local water = newMeshW(G, flat, map, "water")
    return solid, water
  end

  -- the buildings: a block on each door's footprint, as tall as its front wall's rows (the game draws a
  -- house's front two tiles tall); the roof's rows of the picture over its top, the wall's rows up its
  -- face, the picture's edge down its sides and back; standing on what its door stands on (a deck,
  -- Pacifidlog's logs)
  -- (how tall each kind stands, by its front wall's height: a Gym a good deal taller than a house)
  local KIND_H = { center = 1.15, mart = 1.05, gym = 1.5, lab = 1.15, contest = 1.3, institute = 1.25,
                   space = 1.3, museum = 1.25, school = 1.15, shipyard = 1.2, harbor = 1.15, corner = 1.25,
                   silph = 3.4, mansion = 1.45, plant = 1.3 }
  local function worldBuildings(G, region)
    local W = region.world
    local cols, rows, MT = W.cols, W.rows, region.unit
    local verts, map = {}, {}
    local Tw = deps.towns
    for _, d in ipairs(W.doors) do
      local f = d.foot
      if f and Tw and Tw.replaces and Tw.replaces(d) then f = nil end
      if f then
        local gx0, gy0, gx1, gy1 = f.x0 - W.x0, f.y0 - W.y0, f.x1 - W.x0, f.y1 - W.y0
        local tall = gy1 - gy0
        local wallRows = tall >= 4 and 2 or 1
        local split = gy1 - wallRows
        local base = W.h[d.k] or 0
        for _, kk in ipairs({ d.k, d.k + cols }) do
          local dk = W.deck and W.deck[kk]
          if dk and dk > base then base = dk end
          if W.ws and W.ws[kk] and W.ws[kk] + 0.03 > base then base = W.ws[kk] + 0.03 end
        end
        -- (on sloping ground: its roof from the highest ground under it, its walls down to the lowest)
        local hi, lo = base, base
        for gy = gy0, gy1 - 1 do
          for gx = gx0, gx1 - 1 do
            local hk = W.h[gy * cols + gx + 1]
            if hk and hk > 0 then
              if hk > hi then hi = hk end
              if hk < lo then lo = hk end
            end
          end
        end
        -- (Fortree's houses are up in its trees)
        if d.kind == "house" and d.map:find("FORTREE_CITY", 1, true) then
          lo = base + TREE_H
          if hi < lo then hi = lo end
        end
        local top = hi + wallRows / MT * 1.1 * (KIND_H[d.kind] or 1)
        base = lo
        -- (a hair in from the tiles' edges: the ground's own walls stand on those, and two faces on one
        -- plane flash)
        local E = 0.003
        local x0, z0, x1, z1 = f.x0 / MT + E, f.y0 / MT + E, f.x1 / MT - E, f.y1 / MT - E
        local u0, u1, v0, vs, v1 = gx0 / cols, gx1 / cols, gy0 / rows, split / rows, gy1 / rows
        faceW(verts, map, x0, top, z0, x1, top, z0, x1, top, z1, x0, top, z1, 0, 1, 0, 1, F_GROUND,
          u0, v0, u1, v0, u1, vs, u0, vs)
        faceW(verts, map, x0, top, z1, x1, top, z1, x1, base, z1, x0, base, z1, 0, 0, 1, 1, F_FRONT,
          u0, vs, u1, vs, u1, v1, u0, v1)
        local ve = (gy0 + 0.3) / rows
        faceW(verts, map, x1, top, z0, x0, top, z0, x0, base, z0, x1, base, z0, 0, 0, -1, BUILD_SHADE, F_GROUND,
          u1, ve, u0, ve, u0, ve, u1, ve)
        local uw, ue = (gx0 + 0.3) / cols, (gx1 - 0.3) / cols
        faceW(verts, map, x0, top, z0, x0, top, z1, x0, base, z1, x0, base, z0, -1, 0, 0, BUILD_SHADE, F_GROUND,
          uw, v0, uw, v1, uw, v1, uw, v0)
        faceW(verts, map, x1, top, z1, x1, top, z0, x1, base, z0, x1, base, z1, 1, 0, 0, BUILD_SHADE, F_GROUND,
          ue, v1, ue, v0, ue, v0, ue, v1)
      end
    end
    return newMeshW(G, verts, map, "buildings")
  end

  -- what's kept on disk, written once the meshes are made (the files a few at a time)
  local function keep(region, m, picData)
    local c = region.cache
    local parts = { world = region.world, terrain = region.terrain, step = region.step, meshes = rkeep.meshes,
                    images = {}, art = m.art and { size = m.art.size, lv = m.art.lv } or nil }
    parts.images.picture = { w = picData:getWidth(), h = picData:getHeight(), data = picData }
    local ad = m.art and m.art.data
    if ad then
      parts.images.atlas = { w = ad.atlas:getWidth(), h = ad.atlas:getHeight(), data = ad.atlas }
      parts.images.index = { w = ad.index:getWidth(), h = ad.index:getHeight(), data = ad.index }
    else
      parts.art = nil
    end
    local t0 = rclock()
    local ok, done, err = pcall(Mc.write, c.dir, c.stamp, parts, rbreathe)
    if not (ok and done) then
      if deps.log then deps.log("the map couldn't be kept: %s", tostring(ok and err or done)) end
      Mc.forget(c.dir)
    elseif PROFILE and deps.log then
      deps.log("the map kept in %.0f ms", (rclock() - t0) * 1000)
    end
    if ad then
      pcall(ad.index.release, ad.index)
      pcall(ad.atlas.release, ad.atlas)
      m.art.data = nil
    end
  end

  local function worldMeshes(G, region)
    local W = region.world
    -- (kept on disk once made: when the region has a place there and love.data can pack it)
    local c = region.cache
    rkeep = (Mc and c and c.stamp and not c.kept and love and love.data and love.data.pack) and { meshes = {} } or nil
    rbreathe("picture")
    local img, picData = groundPicture(G, region)
    if not img then
      rkeep = nil
      return nil
    end
    local okArt, art = pcall(groundArt, G, region)
    if not okArt then
      if deps.log then deps.log("the map's art failed: %s", tostring(art)) end
      art = nil
    end
    rbreathe("chunks")
    local m = { ground = {}, water = {}, slab = slabMesh(G, region), picture = img, art = art }
    local nChunks, done = math.ceil(W.rows / CHUNK) * math.ceil(W.cols / CHUNK), 0
    for j0 = 0, W.rows - 1, CHUNK do
      for i0 = 0, W.cols - 1, CHUNK do
        local mesh, water = worldChunk(G, region, i0, j0, min(W.cols, i0 + CHUNK), min(W.rows, j0 + CHUNK))
        if mesh then
          pcall(mesh.setTexture, mesh, img)
          m.ground[#m.ground + 1] = mesh
        end
        if water then m.water[#m.water + 1] = water end
        done = done + 1
        if rprog then rprog.r = 0.25 + 0.6 * done / nChunks end
      end
    end
    rbreathe("buildings")
    m.buildings = worldBuildings(G, region)
    rbreathe("landmarks")
    if deps.towns and deps.towns.landmarks then
      local okL, lv = pcall(deps.towns.landmarks, region)
      if okL then
        m.landmarks = newMesh(G, lv)
        if rkeep and m.landmarks then
          local okV, v = pcall(Mc.packV, lv, rbreathe)
          if okV and v then rkeep.meshes[#rkeep.meshes + 1] = { slot = "landmarks", fmt = "V", n = #lv, ni = 0, v = v } else rkeep = nil end
        end
      elseif deps.log then
        deps.log("the map's landmarks failed: %s", tostring(lv))
      end
    end
    if rprog then rprog.r = 0.9 end
    rbreathe("done")
    if m.buildings then pcall(m.buildings.setTexture, m.buildings, img) end
    m.land = m.ground[1]
    if rkeep then
      rbreathe("keep")
      keep(region, m, picData)
    elseif m.art and m.art.data then
      pcall(m.art.data.index.release, m.art.data.index)
      pcall(m.art.data.atlas.release, m.art.data.atlas)
      m.art.data = nil
    end
    rkeep = nil
    pcall(picData.release, picData)
    return m
  end

  -- a region read back from the disk (src/map3d/cache.lua): its pictures and meshes as they were kept
  -- -> the meshes | nil (unreadable: the index let go, built afresh next time)
  local function keptMeshes(G, region)
    local c = region.cache
    local LI = love and love.image
    if not (Mc and LI and LI.newImageData) then return nil, "no love.image" end
    rbreathe("kept")
    local got, why = Mc.readDrawing(c.dir, c.kept, rbreathe)
    if not got then return nil, why end
    if rprog then rprog.r = 0.35 end
    local function imageData(name)
      local im = got.images[name]
      if not im then return nil end
      local ok, data = pcall(LI.newImageData, im.w, im.h, "rgba8", im.bytes)
      im.bytes = nil
      if not ok then why = name .. ": " .. tostring(data) end
      return ok and data or nil
    end
    local picData = imageData("picture")
    local img = picData and pictureImage(G, picData)
    if picData then pcall(picData.release, picData) end
    if not img then return nil, why or "the picture's image" end
    rbreathe()
    local m = { ground = {}, water = {}, slab = slabMesh(G, region), picture = img }
    local iData, aData = imageData("index"), imageData("atlas")
    if iData and aData and got.art then
      local iImg, aImg = artImages(G, iData, aData)
      if iImg then m.art = { index = iImg, atlas = aImg, size = got.art.size, lv = got.art.lv } end
    end
    if iData then pcall(iData.release, iData) end
    if aData then pcall(aData.release, aData) end
    if rprog then rprog.r = 0.6 end
    rbreathe()
    for n, e in ipairs(got.meshes) do
      local ok, mesh = pcall(G.newMesh, e.fmt == "V" and FORMAT or FORMAT_W, e.n, "triangles", "static")
      if not (ok and mesh) then return nil, "a mesh: " .. tostring(mesh) end
      local okV, errV = pcall(mesh.setVertices, mesh, e.v)
      if not okV then return nil, "a mesh's vertices: " .. tostring(errV) end
      if e.i then
        local okI, errI = pcall(mesh.setVertexMap, mesh, e.i, "uint32")
        if not okI then return nil, "a mesh's map: " .. tostring(errI) end
      end
      if e.slot == "ground" then
        pcall(mesh.setTexture, mesh, img)
        m.ground[#m.ground + 1] = mesh
      elseif e.slot == "water" then
        m.water[#m.water + 1] = mesh
      elseif e.slot == "buildings" then
        pcall(mesh.setTexture, mesh, img)
        m.buildings = mesh
      elseif e.slot == "landmarks" then
        m.landmarks = mesh
      end
      if rprog then rprog.r = 0.6 + 0.4 * n / #got.meshes end
      if n % 4 == 0 then rbreathe() end
    end
    pcall(got.blob.release, got.blob)
    m.land = m.ground[1]
    m.kept = true
    return m
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

  -- ------- the everyday weather: far quieter than the storms (pale clouds, thin rain, a low haze); per
  -- kind one mesh of its bits and one of its clouds, over a unit square: the shader puts them over a place

  local WX_BITS = 900        -- the most bits one weather draws
  -- per kind: its bits (colour, how many a cell, width, length, fall, drift, sand's band, how they move),
  -- its clouds (how many at most, size, colour, alpha; solid, or a haze seen through; high over the
  -- ground, or `low` this far over it; `spread`: a haze past the place's edges), what it does to the ground
  -- (colour, how much)
  local RAIN_BITS = { 0.8, 0.87, 1, 0.6 }
  local WX_LOOK = {
    rain = { bits = RAIN_BITS, perCell = 40, width = 0.01, length = 0.15, fall = 1.1, drift = 0, way = 0,
             clouds = { 12, 0.38, 0.74, 0.77, 0.84 }, solid = true, tint = { 0.84, 0.88, 0.96, 0.35 } },
    thunder = { bits = RAIN_BITS, perCell = 52, width = 0.01, length = 0.16, fall = 1.2, drift = 0, way = 0,
                clouds = { 14, 0.42, 0.56, 0.59, 0.68 }, solid = true, tint = { 0.8, 0.84, 0.92, 0.4 }, flash = true },
    snow = { bits = { 1, 1, 1, 0.85 }, perCell = 45, width = 0.018, length = 0, fall = 0.14, drift = 0, way = 1,
             clouds = { 12, 0.38, 0.88, 0.9, 0.95 }, solid = true, tint = { 1.25, 1.25, 1.3, 0.4 } },
    ash = { bits = { 0.4, 0.38, 0.38, 0.75 }, perCell = 45, width = 0.017, length = 0, fall = 0.1, drift = 0, way = 1,
            clouds = { 10, 0.42, 0.52, 0.5, 0.5, 0.55 }, tint = { 0.74, 0.74, 0.76, 0.5 } },
    sand = { bits = { 0.93, 0.78, 0.5, 0.85 }, perCell = 130, width = 0.016, length = 0.15, fall = 0, drift = 0.22,
             band = 0.5, way = 2, clouds = { 18, 0.58, 0.98, 0.86, 0.62, 0.46 }, low = 0.04, spread = 1.4,
             tint = { 1.12, 0.92, 0.64, 0.55 } },
    fog = { clouds = { 14, 0.5, 0.94, 0.95, 0.98, 0.4 }, low = 0.16, tint = { 1.08, 1.1, 1.14, 0.25 } },
    shade = { tint = { 0.8, 0.82, 0.88, 0.32 } },
    clouds = { clouds = { 8, 0.36, 0.98, 0.99, 1 }, solid = true, tint = { 0.97, 0.98, 1, 0.1 } },
  }
  local CLOUD_DRIFT = 0.004  -- a fraction of its place a second
  local CLOUD_OVER = 0.8     -- a high cloud's base over the highest ground under it
  local CLOUD_MIN = 1.1      -- and never lower than this

  -- one cloud: a few rounded lobes around its anchor (in the normal: 0..1 over the place, a little
  -- height), a flat base, its sunny side baked lighter
  local CLUSTER = { { 0, 0, 0, 1 }, { 0.62, -0.08, 0.12, 0.72 }, { -0.58, -0.1, -0.06, 0.7 },
                    { 0.12, 0.05, -0.5, 0.62 }, { -0.16, -0.06, 0.5, 0.6 } }
  local LOBE_ROWS, LOBE_SEGS = 5, 8
  local SUN_X, SUN_Y, SUN_Z = 0.4344, 0.8068, 0.4758   -- (light()'s sun, as a unit vector)
  local function wxCloud(list, ax, ay, az, size, r, g, b, alpha)
    local base = -0.24 * size
    for _, l in ipairs(CLUSTER) do
      local ox, oy, oz, k = l[1] * size, l[2] * size, l[3] * size, l[4] * size
      local function corner(j, i)
        local a, t = j / LOBE_ROWS * pi, i / LOBE_SEGS * 2 * pi
        local nx, ny, nz = sin(a) * cos(t), cos(a), sin(a) * sin(t)
        local y = oy + ny * k * 0.62
        local bright = 0.64 + 0.36 * max(0, nx * SUN_X + ny * SUN_Y + nz * SUN_Z)
        if y < base then y, bright = base, 0.56 end
        vert(list, ox + nx * k, y, oz + nz * k * 0.86, ax, ay, az, r * bright, g * bright, b * bright, alpha, F_WXPUFF)
      end
      for j = 0, LOBE_ROWS - 1 do
        for i = 0, LOBE_SEGS - 1 do
          corner(j, i); corner(j + 1, i); corner(j + 1, i + 1)
          corner(j, i); corner(j + 1, i + 1); corner(j, i + 1)
        end
      end
    end
  end
  local CLOUD_VERTS = #CLUSTER * LOBE_ROWS * LOBE_SEGS * 6

  local wxMeshes = {}
  local function wxMeshOf(G, kind)
    local m = wxMeshes[kind]
    if m ~= nil then return m or nil end
    local look = WX_LOOK[kind]
    m = false
    if look then
      m = {}
      if look.bits then
        local list, c = {}, look.bits
        for i = 1, WX_BITS do
          -- (spread evenly: two irrationals for where, a hash for when)
          fleck(list, 0, 1, (i * 0.7548776662) % 1, hash(i, 1, 71), (i * 0.5698402910) % 1, c[1], c[2], c[3], c[4], F_WX)
        end
        m.bits = newMesh(G, list)
      end
      if look.clouds then
        local list, c = {}, look.clouds
        for i = 1, c[1] do
          wxCloud(list, (i * 0.7548776662) % 1, hash(i, 3, 73) * 0.14, (i * 0.5698402910 + 0.31) % 1,
            c[2] * (0.8 + hash(i, 2, 73) * 0.4), c[3], c[4], c[5], c[6] or 1)
        end
        m.clouds = newMesh(G, list)
      end
      if (look.bits and not m.bits) or (look.clouds and not m.clouds) then m = false end
    end
    wxMeshes[kind] = m
    return m or nil
  end

  -- a thunderstorm's flash: dim, now and then, each one on its own beat
  function R.weatherFlash(t, i)
    return (R.lightning(t * 0.5 + (i or 0) * 2.3)) * 0.4
  end

  local WX_AREA, WX_MOVE, WX_LOOK_U = { 0, 0, 1, 1 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
  local WX_BOX, WX_TINT = {}, {}
  for i = 1, WX_MAX do WX_BOX[i], WX_TINT[i] = { 0, 0, 0, 0 }, { 1, 1, 1, 0 } end
  local unpack = unpack or table.unpack

  -- the ground under each weather: its box and its tint (a thunderstorm's flash lightening it a moment)
  local function sendWeatherGround(sh, weather, t)
    local n = 0
    if weather then
      for i = 1, #weather do
        local a = weather[i]
        local look = WX_LOOK[a.kind]
        if look and a.grow > 0 and n < WX_MAX then
          n = n + 1
          local b, c, tint = WX_BOX[n], WX_TINT[n], look.tint
          b[1], b[2], b[3], b[4] = a.x, a.z, a.rx, a.rz
          local f = look.flash and R.weatherFlash(t, i) or 0
          c[1], c[2], c[3], c[4] = tint[1] + f * 0.3, tint[2] + f * 0.3, tint[3] + f * 0.36, tint[4] * a.grow
        end
      end
    end
    for i = n + 1, WX_MAX do WX_BOX[i][3] = 0 end
    pcall(sh.send, sh, "uWxBox", unpack(WX_BOX, 1, WX_MAX))
    pcall(sh.send, sh, "uWxTint", unpack(WX_TINT, 1, WX_MAX))
  end

  -- each weather's clouds (solid: they hide what's behind them; or a haze, seen through), then its bits
  local function drawWeather(G, sh, weather, t, solid, bits)
    if not weather then return end
    for i = 1, #weather do
      local a = weather[i]
      local look = WX_LOOK[a.kind]
      local m = look and a.grow > 0 and wxMeshOf(G, a.kind)
      if m then
        local cells = 4 * a.rx * a.rz
        local ground = a.y0 or 0
        local high = max(CLOUD_MIN, (a.y or 0) + CLOUD_OVER)
        WX_AREA[1], WX_AREA[2], WX_AREA[3], WX_AREA[4] = a.x, a.z, a.rx, a.rz
        pcall(sh.send, sh, "uWxArea", WX_AREA)
        if bits and m.bits then
          -- (rain and flakes from the clouds' base to the ground; sand in a band over it)
          local sand = look.way == 2
          WX_MOVE[1], WX_MOVE[2], WX_MOVE[3], WX_MOVE[4] = look.fall, look.drift, sand and look.band or high, a.grow
          WX_LOOK_U[1], WX_LOOK_U[2], WX_LOOK_U[3], WX_LOOK_U[4] = look.width, look.length,
            sand and ground or ground - 0.1, look.way
          pcall(sh.send, sh, "uWxMove", WX_MOVE)
          pcall(sh.send, sh, "uWxLook", WX_LOOK_U)
          m.bits:setDrawRange(1, max(24, min(WX_BITS, floor(cells * look.perCell))) * 6)
          G.draw(m.bits)
        elseif not bits and m.clouds and (look.solid == true) == solid then
          local sp = look.spread or 1
          WX_AREA[3], WX_AREA[4] = a.rx * sp, a.rz * sp
          pcall(sh.send, sh, "uWxArea", WX_AREA)
          cells = cells * sp * sp
          WX_MOVE[1], WX_MOVE[2], WX_MOVE[3], WX_MOVE[4] = 0, CLOUD_DRIFT / max(0.6, a.rx),
            look.low and ground + look.low or high, a.grow
          WX_LOOK_U[1], WX_LOOK_U[2], WX_LOOK_U[3], WX_LOOK_U[4] = 0, 0, look.flash and R.weatherFlash(t, i) or 0, 0
          pcall(sh.send, sh, "uWxMove", WX_MOVE)
          pcall(sh.send, sh, "uWxLook", WX_LOOK_U)
          m.clouds:setDrawRange(1, max(2, min(look.clouds[1], floor(cells * 0.9 + 1.5))) * CLOUD_VERTS)
          G.draw(m.clouds)
        end
      end
    end
  end

  -- ------- the shader, the canvas and the draw

  -- (why the map couldn't be drawn in 3D, in the GPU's or the engine's own words: shown on the map so a
  -- device's failure can be read off it)
  local problem = nil
  function R.problem() return problem end
  local shader, shaderTried = nil, false
  local function getShader(G)
    if shaderTried then return shader end
    shaderTried = true
    if not G.newShader then return nil end
    local t0 = rclock()
    local ok, s = pcall(G.newShader, shaderSource(true))
    if not ok then
      -- (the tiles' art left out where the GPU won't take it: the map in 3D all the same)
      if deps.log then deps.log("the map's shader with the tiles' art failed: %s", tostring(s)) end
      problem = "the tiles' art (the map drawn without it): " .. tostring(s)
      ok, s = pcall(G.newShader, shaderSource(false))
    end
    if PROFILE and deps.log then deps.log("map shader compiled in %.0f ms", (rclock() - t0) * 1000) end
    if ok then
      shader = s
    else
      problem = "the shader: " .. tostring(s)
      if deps.log then deps.log("the map's shader failed: %s", tostring(s)) end
    end
    return shader
  end

  -- the world built to scale: its meshes made by a job of their own (R.prepare in the background, or
  -- here while the map is open: nil until they're done, the flat land meanwhile)
  local jobsOf = setmetatable({}, { __mode = "k" })
  local progOf = setmetatable({}, { __mode = "k" })
  local function stepJob(G, region, budget)
    local job = jobsOf[region]
    if not job then
      progOf[region] = progOf[region] or { r = 0 }
      job = coroutine.create(function()
        local mm
        local c = region.cache
        if c and c.kept then
          local why
          mm, why = keptMeshes(G, region)
          if not mm then
            -- (unreadable here: let go, and the region built afresh (src/map3d/scene.lua sees
            -- region.keptFailed and has the model build it again))
            problem = "the kept map: " .. tostring(why)
            if deps.log then deps.log("the kept map is unreadable: %s", tostring(why)) end
            if Mc then Mc.forget(c.dir) end
            region.keptFailed = true
          end
        else
          mm = worldMeshes(G, region)
        end
        if mm then mm.clouds = cloudMesh(G, region) end
        meshesOf[region] = mm or false
        -- (the tiles themselves aren't needed past this: their arrays let go)
        local W = region.world
        if mm and W and W.release then W.release() end
      end)
      jobsOf[region] = job
    end
    rslice.start, rslice.budget = rclock(), budget
    rprog = progOf[region]
    local ok, err = coroutine.resume(job)
    rprog = nil
    if not ok then
      problem = "the meshes: " .. tostring(err)
      if deps.log then deps.log("the map's meshes failed: %s", tostring(err)) end
      meshesOf[region] = false
    end
    if coroutine.status(job) == "dead" then jobsOf[region] = nil end
    return meshesOf[region] == nil
  end
  -- -> true while there's more to make
  function R.prepare(G, region, budget)
    if not (region and region.world) or meshesOf[region] ~= nil or not (G and G.newMesh) then return false end
    -- (made even when the shader can't be: the flat map's picture comes from this job too)
    getShader(G)
    return stepJob(G, region, budget or 0.004)
  end
  function R.ready(region) return not (region and region.world) or meshesOf[region] ~= nil end
  -- how far its meshes are made, 0..1 (for the map's loading bar)
  function R.progress(region)
    if R.ready(region) then return 1 end
    local p = progOf[region]
    return p and p.r or 0
  end

  local function meshes(G, region)
    local m = meshesOf[region]
    if m == nil then
      if region.world then
        stepJob(G, region, 0.012)
        return meshesOf[region] or nil
      else
        m = { land = landMesh(G, region), slab = slabMesh(G, region), sea = seaMesh(G, region),
              towns = townMesh(G, region), clouds = cloudMesh(G, region) }
      end
      if not (m and m.land) then m = false end
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

  -- (the tiles' art to a shader with ART_GLSL: none, the picture alone)
  local NO_ART = { 0, 0, 1, 1 }
  local TAN_HALF = math.tan(FOV / 2)
  function sendArt(sh, art)
    if art then
      pcall(sh.send, sh, "uIndex", art.index)
      pcall(sh.send, sh, "uAtlas", art.atlas)
      pcall(sh.send, sh, "uArtSize", art.size)
      pcall(sh.send, sh, "uArtLv", art.lv)
    else
      pcall(sh.send, sh, "uArtSize", NO_ART)
    end
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
  function R.draw(G, region, rect, t, night, dusk, storm, weather)
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
    sendArt(sh, m.art)
    pcall(sh.send, sh, "uArtK", h / (2 * TAN_HALF) / ((region.unit or 16) * 16))
    sendWeatherGround(sh, weather, t)
    G.setColor(1, 1, 1, 1)
    G.setDepthMode("lequal", true)
    G.setMeshCullMode("none")
    if m.ground then
      for i = 1, #m.ground do G.draw(m.ground[i]) end
      if m.buildings then G.draw(m.buildings) end
      if m.landmarks then G.draw(m.landmarks) end
    else
      G.draw(m.land)
    end
    if m.slab then G.draw(m.slab) end
    if m.towns then G.draw(m.towns) end
    if m.sea then G.draw(m.sea) end
    if m.water then
      for i = 1, #m.water do G.draw(m.water[i]) end
    end
    -- (a rain cloud is solid; the dust is haze, seen through itself)
    if stormM and storm.kind == "rain" then G.draw(stormM.solid) end
    drawWeather(G, sh, weather, t, true, false)
    G.setDepthMode("lequal", false)
    if stormM and storm.kind ~= "rain" then G.draw(stormM.solid) end
    if stormM then G.draw(stormM.fine) end
    drawWeather(G, sh, weather, t, false, false)
    drawWeather(G, sh, weather, t, false, true)
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
