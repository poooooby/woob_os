-- Arranging the desktop: which apps sit in the dock and which on the home screen, in what order.
-- The player's arrangement is kept (src/settings.lua) as two lists of app ids; an app it doesn't
-- name goes where it would by default (app.dock), after the named ones. An app named there but
-- not on this PC (the bedroom's Decorate, another mod's) keeps its place for the PCs that show it.
--
--   Ar.decode(text) -> { id, ... }          ("storage,items,mail")
--   Ar.place(apps, dockText, gridText) -> grid, dock   (apps: the available ones, in their order)
--   Ar.encode(dock, grid, dockText, gridText) -> dockText, gridText   (the lists as shown, plus
--       the ids the old texts named that aren't shown here, each in its own list)
--   Ar.move(lists, from, i, to, j) -> j   (lists = { grid = {...}, dock = {...} }: the app at
--       lists[from][i] moved to lists[to] at j, clamped; -> where it landed)
--   Ar.DOCK_MAX   the most apps the dock holds

local Ar = { DOCK_MAX = 6 }

function Ar.decode(text)
  local out = {}
  if type(text) ~= "string" then return out end
  for id in text:gmatch("[^,]+") do out[#out + 1] = id end
  return out
end

function Ar.place(apps, dockText, gridText)
  local byId = {}
  for _, app in ipairs(apps) do byId[app.id] = app end
  local grid, dock, used = {}, {}, {}
  for _, id in ipairs(Ar.decode(dockText)) do
    local app = byId[id]
    if app and not used[id] and #dock < Ar.DOCK_MAX then
      dock[#dock + 1], used[id] = app, true
    end
  end
  for _, id in ipairs(Ar.decode(gridText)) do
    local app = byId[id]
    if app and not used[id] then grid[#grid + 1], used[id] = app, true end
  end
  for _, app in ipairs(apps) do
    if not used[app.id] then
      if app.dock and #dock < Ar.DOCK_MAX then dock[#dock + 1] = app else grid[#grid + 1] = app end
    end
  end
  return grid, dock
end

function Ar.encode(dock, grid, dockText, gridText)
  local shown = {}
  for _, app in ipairs(dock) do shown[app.id] = true end
  for _, app in ipairs(grid) do shown[app.id] = true end
  local function text(list, old)
    local ids = {}
    for _, app in ipairs(list) do ids[#ids + 1] = app.id end
    for _, id in ipairs(Ar.decode(old)) do
      if not shown[id] then
        ids[#ids + 1] = id
        shown[id] = true
      end
    end
    return table.concat(ids, ",")
  end
  local d = text(dock, dockText)
  return d, text(grid, gridText)
end

function Ar.move(lists, from, i, to, j)
  local src, dst = lists[from], lists[to]
  local app = src[i]
  if not app then return i end
  table.remove(src, i)
  j = math.max(1, math.min(#dst + 1, j))
  table.insert(dst, j, app)
  return j
end

return Ar
