-- Frosted glass over whatever was drawn: between begin() and finish() the drawing goes to a canvas
-- of its own (the target's size), then out to the target as it was, and a small copy of it is kept;
-- draw() lays that copy, blurred, inside a rounded rectangle. Each desktop (the PC's, WoobPad's) has
-- its own. Without canvases or shaders (headless) begin() says no and the caller tints instead.
--
--   Fr = Frost(deps)   deps: log(fmt, ...)
--   Fr.begin(G) -> true while it's catching the drawing ; Fr.finish(G) (the drawing out, the copy made)
--   Fr.draw(G, x, y, w, h, rad, a) -> true when it drew the glass (window pixels)
--   Fr.release()

local floor, max, min = math.floor, math.max, math.min

-- (a smaller copy, smoothed as it's scaled up, then 25 taps across it: a soft, even blur; inside a
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
local SMALL = 6     -- the copy: a sixth of the size

return function(deps)
  deps = deps or {}
  local Fr = {}
  local full, fullW, fullH, fullDpi = nil, 0, 0, 0
  local small, smallW, smallH = nil, 0, 0
  local shader, tried = nil, false
  local target, catching, ready = nil, false, false
  local RECT, TEXEL = { 0, 0, 1, 1 }, { 0, 0 }

  local function log(fmt, ...) if deps.log then deps.log(fmt, ...) end end

  local function canvas(G, old, w, h, opts)
    if old and old.release then pcall(old.release, old) end
    local ok, c = pcall(G.newCanvas, w, h, opts)
    return ok and c or nil
  end

  function Fr.begin(G)
    ready = false
    if not (G.newCanvas and G.newShader and G.getCanvas and G.setCanvas) then return false end
    if not tried then
      tried = true
      local ok, sh = pcall(G.newShader, BLUR)
      shader = ok and sh or nil
      if not ok then log("the frosted glass couldn't be made: %s", tostring(sh)) end
    end
    if not shader then return false end
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
      if full then full:setFilter("linear", "linear") end
    end
    local sw, sh = max(1, floor(w * dpi / SMALL)), max(1, floor(h * dpi / SMALL))
    if not (small and smallW == sw and smallH == sh) then
      small = canvas(G, small, sw, sh, { dpiscale = 1 })
      smallW, smallH = sw, sh
      if small then small:setFilter("linear", "linear") end
    end
    if not (full and small) then return false end
    G.setCanvas(full)
    G.clear(0, 0, 0, 0)
    catching = true
    return true
  end

  function Fr.finish(G)
    if not catching then return end
    catching = false
    -- (the target first: the state pushed here is what the pop puts back, the canvas with it)
    G.setCanvas(target)
    G.push("all")
    G.origin()
    G.setScissor()
    G.setShader()
    G.setColor(1, 1, 1, 1)
    -- (what was drawn, premultiplied as a canvas drawn over transparency is)
    G.setBlendMode("alpha", "premultiplied")
    G.setCanvas(small)
    G.clear(0, 0, 0, 0)
    G.draw(full, 0, 0, 0, smallW / fullW, smallH / fullH)
    G.setCanvas(target)
    G.draw(full, 0, 0)
    G.pop()
    ready = true
  end

  function Fr.draw(G, x, y, w, h, rad, a)
    if not (ready and shader and small) then return false end
    RECT[1], RECT[2], RECT[3], RECT[4] = x * fullDpi, y * fullDpi, w * fullDpi, h * fullDpi
    TEXEL[1], TEXEL[2] = 1 / smallW, 1 / smallH
    G.push("all")
    G.intersectScissor(max(0, floor(x)), max(0, floor(y)), max(1, floor(w + 1)), max(1, floor(h + 1)))
    G.setShader(shader)
    pcall(shader.send, shader, "uRect", RECT)
    pcall(shader.send, shader, "uRad", (rad or 0) * fullDpi)
    pcall(shader.send, shader, "uTexel", TEXEL)
    G.setColor(1, 1, 1, a or 1)
    G.draw(small, 0, 0, 0, fullW / smallW, fullH / smallH)
    G.pop()
    return true
  end

  function Fr.release()
    if full and full.release then pcall(full.release, full) end
    if small and small.release then pcall(small.release, small) end
    full, small, fullW, smallW, ready = nil, nil, 0, 0, false
  end

  return Fr
end
