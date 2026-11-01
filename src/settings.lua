-- The Settings app's choices, kept for the installation (not one save): mod.cache's settings.lua,
-- written only when a choice changes and read back as data only (an empty environment).
--
--   S = settings(deps)   deps: cache (mod.cache, or nil: kept in memory only) ; loadData(source,
--                        name) -> table | nil, err (src/i18n.lua's) ; log(fmt, ...)
--   S.get(key, default) ; S.set(key, value) -> true when it changed (strings, numbers, booleans)
--   S.cache: where set() writes (a test swaps in its own)

return function(deps)
  local S = {}
  local KEY = "settings.lua"
  local values = {}

  local cache = deps.cache
  S.cache = cache
  if cache and cache.read then
    local ok, source = pcall(cache.read, cache, KEY)
    if ok and type(source) == "string" then
      local data, err = deps.loadData(source, KEY)
      if type(data) == "table" then
        for k, v in pairs(data) do
          local t = type(v)
          if type(k) == "string" and (t == "string" or t == "number" or t == "boolean") then values[k] = v end
        end
      elseif deps.log then
        deps.log("the settings couldn't be read (%s): back to the defaults", tostring(err))
      end
    end
  end

  local function write()
    local cache = S.cache
    if not (cache and cache.write) then return end
    local keys = {}
    for k in pairs(values) do keys[#keys + 1] = k end
    table.sort(keys)
    local lines = { "-- WoobleOS's settings (the Settings app writes this file).", "return {" }
    for _, k in ipairs(keys) do
      local v = values[k]
      lines[#lines + 1] = ("  [%q] = %s,"):format(k, type(v) == "string" and ("%q"):format(v) or tostring(v))
    end
    lines[#lines + 1] = "}"
    local ok, err = pcall(cache.write, cache, KEY, table.concat(lines, "\n") .. "\n")
    if not ok and deps.log then deps.log("the settings couldn't be saved: %s", tostring(err)) end
  end

  function S.get(key, default)
    local v = values[key]
    if v == nil then return default end
    return v
  end

  function S.set(key, value)
    if values[key] == value then return false end
    values[key] = value
    write()
    return true
  end

  return S
end
