-- The map's markers: a Flag, a Star, a Berry or a Poké Ball the player puts anywhere on the 3D map
-- (twenty in all, a town or a landmark one at most), the save's own (mod.save "marks": they go back
-- with the save). Every game.
--
--   Mk = marks(deps)   deps: save (mod.save)
--   Mk.MAX ; Mk.KINDS = { "flag", "star", "berry", "ball" }
--   Mk.list() -> { { region, x, z, kind, place }, ... } (every region's)
--   Mk.add(region, x, z, kind, place) -> the marker | nil, "full"   (a place already marked: its kind changed)
--   Mk.remove(m) ; Mk.onPlace(region, place) -> the marker | nil ; Mk.load() (the save's, on its loading)

local MAX = 20
local KINDS = { "flag", "star", "berry", "ball" }

return function(deps)
  deps = deps or {}
  local Mk = { MAX = MAX, KINDS = KINDS }
  local list = nil

  local function store() return deps.save end
  function Mk.load()
    list = nil
    local st = store()
    local ok, d = pcall(function() return st and st:get("marks") end)
    local got = {}
    if ok and type(d) == "table" and type(d.list) == "table" then
      for _, m in ipairs(d.list) do
        if type(m) == "table" and m.region ~= nil and tonumber(m.x) and tonumber(m.z) then
          got[#got + 1] = { region = m.region, x = tonumber(m.x), z = tonumber(m.z), kind = m.kind or "flag",
                            place = m.place }
          if #got >= MAX then break end
        end
      end
    end
    list = got
  end
  local function keep()
    local st = store()
    if st then pcall(st.set, st, "marks", { list = list }) end
  end
  function Mk.list()
    if not list then Mk.load() end
    return list
  end
  function Mk.onPlace(region, place)
    if place == nil then return nil end
    for _, m in ipairs(Mk.list()) do
      if m.region == region and m.place == place then return m end
    end
    return nil
  end
  function Mk.add(region, x, z, kind, place)
    local l = Mk.list()
    local had = Mk.onPlace(region, place)
    if had then
      had.kind = kind
      keep()
      return had
    end
    if #l >= MAX then return nil, "full" end
    local m = { region = region, x = x, z = z, kind = kind, place = place }
    l[#l + 1] = m
    keep()
    return m
  end
  function Mk.remove(m)
    local l = Mk.list()
    for i = #l, 1, -1 do
      if l[i] == m then table.remove(l, i) end
    end
    keep()
  end

  return Mk
end
