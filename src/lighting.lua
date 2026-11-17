-- A lighting pass over a drawn scene (the Pokémon Center's): between begin() and finish() the drawing goes
-- to a canvas of its own (the target's size); finish() puts it back out through one shader: a key light
-- (brighter round a point, falling off), a vignette, a gentle contrast and warmth, and bloom (a small copy
-- of what's bright, blurred, added back). Built as src/frost.lua is (the target first, then the push, so
-- the pop restores the right canvas). Without canvases or shaders (headless) begin() says no and the
-- scene is drawn as it is. The shaders pass OpenGL ES: fragment stage only, no `precision` statement.
--
--   Lt = Lighting(deps)   deps: log(fmt, ...)
--   Lt.begin(G) -> true while it's catching the drawing
--   Lt.finish(G, rx, ry, rw, rh, lx, ly, o) the scene's rect and the key light's centre (window pixels);
--     o: { key, vignette, bloom, warm, contrast } (0..1; numbers only, a kept table)
--   Lt.glass(G, x, y, w, h, rad, a) -> true when it drew frosted glass there (window pixels): the scene behind,
--     blurred, inside a rounded rectangle (the words' boxes over it; after finish())
--   Lt.release()

local floor, max = math.floor, math.max

-- (what's bright, for the bloom: above the threshold, kept)
local BRIGHT = [[
uniform float uThreshold;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc);
  vec3 b = max(c.rgb - vec3(uThreshold), vec3(0.0)) / (1.0 - uThreshold);
  return vec4(b, 1.0);
}
]]
-- (the scene back out: the key light, the vignette, the bloom, the grade)
local GRADE = [[
uniform vec4 uRect;     // the scene, in the target's pixels
uniform vec2 uSize;     // the target's pixels
uniform vec2 uLight;    // the key light's centre, 0..1 of the scene
uniform vec4 uLook;     // key, vignette, bloom, warm
uniform float uContrast;
uniform vec2 uTexel;    // one texel of the glow
uniform Image uGlow;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc);
  vec2 p = (tc * uSize - uRect.xy) / uRect.zw;
  // the key light: up to uLook.x brighter at its centre, a little darker far from it
  float d = length((p - uLight) * vec2(1.0, 1.25));
  float key = 1.0 + uLook.x * (1.0 - smoothstep(0.0, 0.85, d)) - uLook.x * 0.35 * smoothstep(0.5, 1.2, d);
  // the vignette: the corners darker
  vec2 v = (p - 0.5) * vec2(1.0, 1.15);
  float vig = 1.0 - uLook.y * smoothstep(0.32, 0.82, length(v));
  // the bloom: the bright copy, blurred over 9 taps two texels apart
  vec3 g = vec3(0.0);
  for (int i = -1; i <= 1; i++) {
    for (int j = -1; j <= 1; j++) {
      g += Texel(uGlow, tc + vec2(float(i), float(j)) * uTexel * 2.0).rgb;
    }
  }
  g = g / 9.0;
  vec3 rgb = c.rgb * key * vig;
  // warmth: a little more red, a little less blue, most in the shadows
  float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
  rgb = mix(rgb, rgb * vec3(1.06, 1.0, 0.92), uLook.w * (1.0 - lum * 0.6));
  // a soft S-curve
  vec3 s = clamp(rgb, 0.0, 1.0);
  rgb = mix(rgb, s * s * (3.0 - 2.0 * s), uContrast);
  rgb += g * uLook.z;
  return vec4(rgb, c.a) * color;
}
]]
-- (frosted glass: a small copy of the scene, smoothed as it's scaled up, then 25 taps across it, inside a
-- rounded rectangle by its signed distance)
local BLUR = [[
uniform vec4 uRect;
uniform float uRad;
uniform vec2 uTexel;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec2 h = uRect.zw * 0.5;
  vec2 q = abs(sc - uRect.xy - h) - h + uRad;
  float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - uRad;
  float a = clamp(0.5 - d, 0.0, 1.0);
  vec4 sum = vec4(0.0);
  for (int i = -2; i <= 2; i++) {
    for (int j = -2; j <= 2; j++) {
      sum += Texel(tex, tc + vec2(float(i), float(j)) * uTexel);
    }
  }
  return vec4(sum.rgb / 25.0, a) * color;
}
]]
local SMALL = 4     -- the bloom's copy: a quarter of the size
local FROST = 6     -- the glass's copy: a sixth

return function(deps)
  deps = deps or {}
  local Lt = {}
  local full, fullW, fullH, fullDpi = nil, 0, 0, 0
  local small, smallW, smallH = nil, 0, 0
  local frost, frostW, frostH = nil, 0, 0
  local bright, grade, blur, tried = nil, nil, nil, false
  local ready = false
  local GRECT, GTEXEL = { 0, 0, 1, 1 }, { 0, 0 }
  local target, catching = nil, false
  local RECT, SIZE, LIGHT, LOOK, TEXEL = { 0, 0, 1, 1 }, { 1, 1 }, { 0.5, 0.3 }, { 0, 0, 0, 0 }, { 0, 0 }

  local function log(fmt, ...) if deps.log then deps.log(fmt, ...) end end
  local function canvas(G, old, w, h, opts)
    if old and old.release then pcall(old.release, old) end
    local ok, c = pcall(G.newCanvas, w, h, opts)
    return ok and c or nil
  end

  function Lt.begin(G)
    if catching then return false end
    if not (G.newCanvas and G.newShader and G.getCanvas and G.setCanvas) then return false end
    if not tried then
      tried = true
      local okB, b = pcall(G.newShader, BRIGHT)
      local okG, g = pcall(G.newShader, GRADE)
      bright, grade = okB and b or nil, okG and g or nil
      if not (okB and okG) then log("the lighting couldn't be made: %s", tostring(okB and g or b)) end
      local okF, f = pcall(G.newShader, BLUR)
      blur = okF and f or nil
      if not okF then log("the lighting's glass couldn't be made: %s", tostring(f)) end
    end
    if not (bright and grade) then return false end
    target = G.getCanvas()
    local w, h, dpi
    if target then
      w, h = target:getDimensions()
      dpi = target.getDPIScale and target:getDPIScale() or 1
    else
      w, h = G.getDimensions()
      dpi = G.getDPIScale and G.getDPIScale() or 1
    end
    w, h = max(1, floor(w)), max(1, floor(h))
    if not (full and fullW == w and fullH == h and fullDpi == dpi) then
      full = canvas(G, full, w, h, { dpiscale = dpi })
      fullW, fullH, fullDpi = w, h, dpi
    end
    local sw, sh = max(1, floor(w * dpi / SMALL)), max(1, floor(h * dpi / SMALL))
    if not (small and smallW == sw and smallH == sh) then
      small = canvas(G, small, sw, sh, { dpiscale = 1 })
      smallW, smallH = sw, sh
      if small then small:setFilter("linear", "linear") end
    end
    local fw, fh = max(1, floor(w * dpi / FROST)), max(1, floor(h * dpi / FROST))
    if blur and not (frost and frostW == fw and frostH == fh) then
      frost = canvas(G, frost, fw, fh, { dpiscale = 1 })
      frostW, frostH = fw, fh
      if frost then frost:setFilter("linear", "linear") end
    end
    if not (full and small) then return false end
    ready = false
    G.setCanvas(full)
    G.clear(0, 0, 0, 0)
    catching = true
    return true
  end

  function Lt.finish(G, rx, ry, rw, rh, lx, ly, o)
    if not catching then return end
    catching = false
    G.setCanvas(target)
    G.push("all")
    G.origin()
    G.setScissor()
    G.setColor(1, 1, 1, 1)
    -- (what's bright, a quarter of the size)
    G.setBlendMode("replace")
    G.setShader(bright)
    pcall(bright.send, bright, "uThreshold", o and o.threshold or 0.72)
    G.setCanvas(small)
    G.clear(0, 0, 0, 1)
    G.draw(full, 0, 0, 0, smallW / fullW, smallH / fullH)
    -- (the scene back out, lit)
    G.setCanvas(target)
    G.setBlendMode("alpha", "premultiplied")
    G.setShader(grade)
    -- (all in the target's own units, as the scene was drawn)
    RECT[1], RECT[2], RECT[3], RECT[4] = rx, ry, max(1, rw), max(1, rh)
    SIZE[1], SIZE[2] = fullW, fullH
    LIGHT[1], LIGHT[2] = (lx - rx) / max(1, rw), (ly - ry) / max(1, rh)
    LOOK[1], LOOK[2] = o and o.key or 0.18, o and o.vignette or 0.4
    LOOK[3], LOOK[4] = o and o.bloom or 0.5, o and o.warm or 0.5
    TEXEL[1], TEXEL[2] = 1 / smallW, 1 / smallH
    pcall(grade.send, grade, "uRect", RECT)
    pcall(grade.send, grade, "uSize", SIZE)
    pcall(grade.send, grade, "uLight", LIGHT)
    pcall(grade.send, grade, "uLook", LOOK)
    pcall(grade.send, grade, "uContrast", o and o.contrast or 0.25)
    pcall(grade.send, grade, "uTexel", TEXEL)
    pcall(grade.send, grade, "uGlow", small)
    G.draw(full, 0, 0)
    -- (the glass's copy: the scene a sixth of the size)
    if blur and frost then
      G.setShader()
      G.setCanvas(frost)
      G.clear(0, 0, 0, 0)
      G.draw(full, 0, 0, 0, frostW / fullW, frostH / fullH)
      G.setCanvas(target)
      ready = true
    end
    G.pop()
  end

  function Lt.glass(G, x, y, w, h, rad, a)
    if not (ready and blur and frost) then return false end
    local d = fullDpi
    GRECT[1], GRECT[2], GRECT[3], GRECT[4] = x * d, y * d, w * d, h * d
    GTEXEL[1], GTEXEL[2] = 1 / frostW, 1 / frostH
    G.push("all")
    G.intersectScissor(max(0, floor(x)), max(0, floor(y)), max(1, floor(w + 1)), max(1, floor(h + 1)))
    G.setShader(blur)
    pcall(blur.send, blur, "uRect", GRECT)
    pcall(blur.send, blur, "uRad", (rad or 0) * d)
    pcall(blur.send, blur, "uTexel", GTEXEL)
    G.setColor(1, 1, 1, a or 1)
    G.draw(frost, 0, 0, 0, fullW / frostW, fullH / frostH)
    G.pop()
    return true
  end

  function Lt.release()
    if full and full.release then pcall(full.release, full) end
    if small and small.release then pcall(small.release, small) end
    if frost and frost.release then pcall(frost.release, frost) end
    full, small, frost, fullW, smallW, frostW, catching, ready = nil, nil, nil, 0, 0, 0, false, false
  end

  return Lt
end
