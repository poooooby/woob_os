-- The 3D map kept on disk (mod.cache: the installation's, not a save's), so the next time the game
-- starts a region opens at once instead of being built again. Each region has a folder of its own,
-- map3d/<game>-<region>/:
--   world.lua    the index, written last: the stamp, the world's outline (its maps' places, its doors,
--                its box), what's in the other files
--   terrain.bin  the coarse terrain (src/map3d/world.lua's Wd.terrain), seven bytes a sample
--   meshes.bin   every mesh's vertices and vertex map, as the GPU takes them (compressed)
--   *.bin        the pictures: the tiles' colours, the tiles' art and its index (raw RGBA, compressed)
-- Used again only while its stamp is the same (WoobOS's version, the engine's, the format's, the maps'
-- fingerprint: Wd.fingerprint), else built afresh and written over.
--
--   Mc = MapCache(deps)   deps: cache (mod.cache), loadData(source, name) -> table, version (WoobOS's),
--                         engine (the engine's version), data (love.data: packing and compressing the
--                         meshes and pictures; without it only the outline and terrain), log(fmt, ...)
--   Mc.stamp(fp) -> the stamp | nil (no fingerprint, no cache: nothing kept)
--   Mc.dir(game, region) -> its folder
--   Mc.readWorld(dir, stamp) -> { world, terrain, step, index } | nil: the outline (maps, byId, doors,
--                         x0, y0, cols, rows) and the terrain, while the stamp matches
--   Mc.packW(flat, n, breathe) -> bytes   (13 numbers a vertex: render.lua's FORMAT_W, 40 bytes each)
--   Mc.packV(list, breathe) -> bytes      (a list of vertices: render.lua's FORMAT, 32 bytes each)
--   Mc.packIdx(map, breathe) -> bytes     (a vertex map, from 1 -> uint32 from 0)
--   Mc.write(dir, stamp, parts, breathe) -> true | nil, err
--       parts = { world, terrain, step, meshes = { { slot, fmt ("W" | "V"), n, ni, v = bytes, i = bytes | nil } },
--                 images = { [name] = { w, h, bytes | data (an ImageData, read as it's written) } },
--                 art = { size, lv } | nil }
--   Mc.readDrawing(dir, index) -> { meshes = { { slot, fmt, n, ni, v = Data, i = Data | nil } },
--                                   images = { [name] = { w, h, bytes } }, art } | nil
--   Mc.forget(dir): its index deleted (built afresh next time)

local floor, max, min = math.floor, math.max, math.min

local FORMAT = 1                 -- what's in the files; bumped when it changes
local WORDS_W = "ffffffBBBBfff"  -- render.lua's FORMAT_W: position, normal, colour (bytes), flag, uv
local WORDS_V = "ffffffBBBBf"    -- its FORMAT: position, normal, colour (bytes), flag
local BATCH = 128                -- vertices a pack call (well under the C stack's limit on values)

return function(deps)
  deps = deps or {}
  local Mc = {}
  local cache, D = deps.cache, deps.data
  local function log(...) if deps.log then deps.log(...) end end

  function Mc.stamp(fp)
    if not (fp and cache and cache.write) then return nil end
    return ("%d|%s|%s|%s"):format(FORMAT, tostring(deps.version or "?"), tostring(deps.engine or "?"), fp)
  end
  function Mc.dir(game, region)
    return "map3d/" .. tostring(game):gsub("[^%w_%-]", "_") .. "-" .. tostring(region):gsub("[^%w_%-]", "_")
  end

  -- ------- a plain Lua table as source (numbers, strings, booleans, tables of them)

  local function ser(v, out)
    local t = type(v)
    if t == "number" then
      if v == floor(v) and v > -1e15 and v < 1e15 then out[#out + 1] = ("%d"):format(v)
      else out[#out + 1] = ("%.17g"):format(v) end
    elseif t == "string" then out[#out + 1] = ("%q"):format(v)
    elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
    elseif t == "table" then
      out[#out + 1] = "{"
      local n = #v
      for i = 1, n do
        ser(v[i], out)
        out[#out + 1] = ","
      end
      -- (and its named fields: only string keys, the rest is the list above)
      for k, x in pairs(v) do
        if type(k) == "string" then
          out[#out + 1] = ("[%q]="):format(k)
          ser(x, out)
          out[#out + 1] = ","
        end
      end
      out[#out + 1] = "}"
    else
      out[#out + 1] = "nil"
    end
  end
  local function source(v)
    local out = { "return " }
    ser(v, out)
    return table.concat(out)
  end

  -- ------- the world's outline: what's needed of it once its meshes are made

  local function outline(world)
    local maps, doors = {}, {}
    for i, m in ipairs(world.maps or {}) do
      maps[i] = { id = m.id, x = m.x, y = m.y, w = m.w, h = m.h, sec = m.sec, how = m.how }
    end
    for i, d in ipairs(world.doors or {}) do
      doors[i] = { x = d.x, y = d.y, sec = d.sec, map = d.map, kind = d.kind, dest = d.dest }
    end
    return { x0 = world.x0, y0 = world.y0, cols = world.cols, rows = world.rows, maps = maps, doors = doors }
  end
  local function fromOutline(o)
    local byId = {}
    for _, m in ipairs(o.maps or {}) do byId[m.id] = m end
    return { x0 = o.x0, y0 = o.y0, cols = o.cols, rows = o.rows, maps = o.maps or {}, doors = o.doors or {},
             byId = byId, released = true, cached = true }
  end

  -- ------- the coarse terrain: its height (three bytes, fixed point), colour and land or sea

  local H_ZERO, H_SCALE = 128, 32768
  local function byte01(x) return max(0, min(255, floor((tonumber(x) or 0) * 255 + 0.5))) end
  local function packTerrain(t, breathe)
    local parts, char = {}, string.char
    local n = t.cols * t.rows
    for q = 1, n do
      local h = floor(((tonumber(t.h[q]) or 0) + H_ZERO) * H_SCALE + 0.5)
      h = max(0, min(16777215, h))
      parts[q] = char(h % 256, floor(h / 256) % 256, floor(h / 65536), byte01(t.r[q]), byte01(t.g[q]),
        byte01(t.b[q]), t.kind[q] == "land" and 1 or 0)
      if breathe and q % 4096 == 0 then breathe() end
    end
    return table.concat(parts)
  end
  local function unpackTerrain(bytes, cols, rows, breathe)
    local n = cols * rows
    if type(bytes) ~= "string" or #bytes ~= n * 7 then return nil end
    local t = { cols = cols, rows = rows, h = {}, kind = {}, r = {}, g = {}, b = {}, peak = {}, town = {} }
    local sbyte = string.byte
    for q = 1, n do
      local o = (q - 1) * 7 + 1
      local h0, h1, h2, r, g, b, k = sbyte(bytes, o, o + 6)
      t.h[q] = (h0 + h1 * 256 + h2 * 65536) / H_SCALE - H_ZERO
      t.r[q], t.g[q], t.b[q] = r / 255, g / 255, b / 255
      t.kind[q] = k == 1 and "land" or "sea"
      t.peak[q] = 0
      if breathe and q % 4096 == 0 then breathe() end
    end
    return t
  end

  local function readIndex(dir)
    if not (cache and cache.read and deps.loadData) then return nil end
    local ok, src = pcall(cache.read, cache, dir .. "/world.lua")
    if not (ok and type(src) == "string") then return nil end
    local idx = deps.loadData(src, dir .. "/world.lua")
    return type(idx) == "table" and idx or nil
  end

  function Mc.readWorld(dir, stamp, breathe)
    if not stamp then return nil end
    local idx = readIndex(dir)
    if not (idx and idx.stamp == stamp and type(idx.world) == "table" and type(idx.terrain) == "table") then return nil end
    local okT, bytes = pcall(cache.read, cache, dir .. "/terrain.bin")
    local t = okT and unpackTerrain(bytes, idx.terrain.cols, idx.terrain.rows, breathe)
    if not t then
      log("the kept map's terrain is unreadable: built afresh")
      return nil
    end
    return { world = fromOutline(idx.world), terrain = t, step = idx.terrain.step, index = idx }
  end

  -- ------- the meshes, as the GPU takes them

  local scratch = {}
  local fmtCache = {}
  local function fmtOf(words, n)
    local key = words .. n
    local f = fmtCache[key]
    if not f then
      f = "<" .. string.rep(words, n)
      fmtCache[key] = f
    end
    return f
  end
  function Mc.packW(flat, n, breathe)
    if not (D and D.pack) then return nil end
    local parts, i = {}, 0
    while i < n do
      local m = min(BATCH, n - i)
      local o = 0
      for v = i, i + m - 1 do
        local b = v * 13
        scratch[o + 1], scratch[o + 2], scratch[o + 3] = flat[b + 1], flat[b + 2], flat[b + 3]
        scratch[o + 4], scratch[o + 5], scratch[o + 6] = flat[b + 4], flat[b + 5], flat[b + 6]
        scratch[o + 7], scratch[o + 8] = byte01(flat[b + 7]), byte01(flat[b + 8])
        scratch[o + 9], scratch[o + 10] = byte01(flat[b + 9]), byte01(flat[b + 10])
        scratch[o + 11], scratch[o + 12], scratch[o + 13] = flat[b + 11], flat[b + 12], flat[b + 13]
        o = o + 13
      end
      parts[#parts + 1] = D.pack("string", fmtOf(WORDS_W, m), unpack(scratch, 1, o))
      i = i + m
      if breathe and #parts % 32 == 0 then breathe() end
    end
    return table.concat(parts)
  end

  function Mc.packV(list, breathe)
    if not (D and D.pack) then return nil end
    local n, parts, i = #list, {}, 0
    while i < n do
      local m = min(BATCH, n - i)
      local o = 0
      for v = i + 1, i + m do
        local q = list[v]
        scratch[o + 1], scratch[o + 2], scratch[o + 3] = q[1], q[2], q[3]
        scratch[o + 4], scratch[o + 5], scratch[o + 6] = q[4], q[5], q[6]
        scratch[o + 7], scratch[o + 8] = byte01(q[7]), byte01(q[8])
        scratch[o + 9], scratch[o + 10] = byte01(q[9]), byte01(q[10] or 1)
        scratch[o + 11] = q[11] or 0
        o = o + 11
      end
      parts[#parts + 1] = D.pack("string", fmtOf(WORDS_V, m), unpack(scratch, 1, o))
      i = i + m
      if breathe and #parts % 32 == 0 then breathe() end
    end
    return table.concat(parts)
  end

  function Mc.packIdx(map, breathe)
    if not (D and D.pack) then return nil end
    local n, parts, i = #map, {}, 0
    local B = BATCH * 6
    while i < n do
      local m = min(B, n - i)
      for k = 1, m do scratch[k] = map[i + k] - 1 end
      parts[#parts + 1] = D.pack("string", fmtOf("I4", m), unpack(scratch, 1, m))
      i = i + m
      if breathe and #parts % 32 == 0 then breathe() end
    end
    return table.concat(parts)
  end

  -- ------- writing: the files, the index last (a folder without one is never read)

  local function put(rel, bytes)
    local ok, done, err = pcall(cache.write, cache, rel, bytes)
    if not ok then return nil, done end
    if done == nil or done == false then return nil, err or "the write failed" end
    return true
  end
  local function squeeze(bytes)
    local ok, out = pcall(D.compress, "string", "lz4", bytes)
    return ok and out or nil
  end

  function Mc.write(dir, stamp, parts, breathe)
    if not (stamp and cache and cache.write and D and D.compress) then return nil, "no cache" end
    local breathe0 = breathe or function() end
    -- (the old index first: a half-written folder is never taken for a whole one)
    if cache.delete then pcall(cache.delete, cache, dir .. "/world.lua") end
    local idx = { stamp = stamp, format = FORMAT, world = outline(parts.world), art = parts.art,
                  terrain = { cols = parts.terrain.cols, rows = parts.terrain.rows, step = parts.step },
                  meshes = {}, images = {} }
    local ok, err = put(dir .. "/terrain.bin", packTerrain(parts.terrain, breathe0))
    if not ok then return nil, err end
    breathe0()
    -- (the meshes end to end, each one's vertices then its vertex map)
    local blob, at = {}, 0
    for _, m in ipairs(parts.meshes or {}) do
      local e = { slot = m.slot, fmt = m.fmt, n = m.n, ni = m.ni or 0, vo = at, vl = #m.v }
      blob[#blob + 1] = m.v
      at = at + #m.v
      if m.i then
        e.io, e.il = at, #m.i
        blob[#blob + 1] = m.i
        at = at + #m.i
      end
      idx.meshes[#idx.meshes + 1] = e
    end
    local raw = table.concat(blob)
    blob = nil
    idx.meshBytes = #raw
    breathe0()
    local packed = squeeze(raw)
    raw = nil
    if not packed then return nil, "couldn't compress the meshes" end
    breathe0()
    ok, err = put(dir .. "/meshes.bin", packed)
    if not ok then return nil, err end
    packed = nil
    breathe0()
    for name, im in pairs(parts.images or {}) do
      -- (its bytes taken only now, one picture at a time: they're big)
      local bytes = im.bytes or im.data:getString()
      local p = squeeze(bytes)
      if not p then return nil, "couldn't compress " .. name end
      breathe0()
      ok, err = put(dir .. "/" .. name .. ".bin", p)
      if not ok then return nil, err end
      idx.images[name] = { w = im.w, h = im.h, size = #bytes }
      bytes, p = nil, nil
      breathe0()
    end
    return put(dir .. "/world.lua", source(idx))
  end

  -- ------- reading the drawing back (the index from readWorld)

  function Mc.readDrawing(dir, idx, breathe)
    if not (idx and cache and cache.read and D and D.decompress and D.newDataView) then return nil end
    local breathe0 = breathe or function() end
    local okR, packed = pcall(cache.read, cache, dir .. "/meshes.bin")
    if not (okR and type(packed) == "string") then return nil end
    local okD, blob = pcall(D.decompress, "data", "lz4", packed)
    packed = nil
    if not (okD and blob and blob:getSize() == idx.meshBytes) then return nil end
    breathe0()
    local out = { meshes = {}, images = {}, art = idx.art, blob = blob }
    for _, e in ipairs(idx.meshes or {}) do
      local okV, v = pcall(D.newDataView, blob, e.vo, e.vl)
      if not okV then return nil end
      local i
      if e.io then
        local okI, iv = pcall(D.newDataView, blob, e.io, e.il)
        if not okI then return nil end
        i = iv
      end
      out.meshes[#out.meshes + 1] = { slot = e.slot, fmt = e.fmt, n = e.n, ni = e.ni, v = v, i = i }
    end
    for name, im in pairs(idx.images or {}) do
      local okP, p = pcall(cache.read, cache, dir .. "/" .. name .. ".bin")
      if not (okP and type(p) == "string") then return nil end
      local okU, bytes = pcall(D.decompress, "string", "lz4", p)
      if not (okU and type(bytes) == "string" and #bytes == im.size) then return nil end
      out.images[name] = { w = im.w, h = im.h, bytes = bytes }
      breathe0()
    end
    return out
  end

  function Mc.forget(dir)
    if cache and cache.delete then pcall(cache.delete, cache, dir .. "/world.lua") end
  end

  Mc.FORMAT = FORMAT
  Mc._packTerrain, Mc._unpackTerrain, Mc._source = packTerrain, unpackTerrain, source
  return Mc
end
