-- WoobOS's words, by language: lang/<code>.lua files, lang/en.lua the master (every key; what
-- any other language leaves out). Each file is data only, loaded with an empty environment, so a
-- file a player drops in can return words and do nothing else.
--
--   T = i18n(deps)   deps: read(path) -> source ; list(dir) -> names ; log(fmt, ...)
--   T(key) -> the word (the language, then English, then the key itself; no garbage: a draw may call it)
--   T.f(key, ...) -> string.format of it (an action, not a draw: it makes a string)
--   T.list(spec) -> spec translated: a list of keys -> their words; a list of { cap, key } (the
--       button hints) -> { cap, word }; kept per spec and language, so a draw may call it
--   T.languages() -> { { code, name } }, English first ; T.set(code) -> true | false ; T.code()
--   T.has(key) (English has it)

return function(deps)
  local langs, cur, en = {}, nil, nil
  local cache = setmetatable({}, { __mode = "k" })

  -- a data file: `return { ... }`, run with nothing in reach
  local function loadData(source, name)
    if type(source) ~= "string" then return nil, "missing" end
    local env = {}
    local chunk, err = load(source, "@" .. name, "t", env)
    if not chunk then return nil, err end
    if setfenv then setfenv(chunk, env) end
    local ok, data = pcall(chunk)
    if not ok then return nil, data end
    if type(data) ~= "table" then return nil, "it doesn't return a table" end
    return data
  end

  local function scan()
    local names = {}
    local ok, got = pcall(deps.list, "lang")
    if ok and type(got) == "table" then names = got end
    for _, file in ipairs(names) do
      local code = type(file) == "string" and file:match("^([%w_%-]+)%.lua$")
      if code then
        local okR, source = pcall(deps.read, "lang/" .. file)
        local data, err = loadData(okR and source or nil, "lang/" .. file)
        if data and type(data.strings) == "table" then
          local strings = {}
          for k, v in pairs(data.strings) do
            if type(k) == "string" and type(v) == "string" then strings[k] = v end
          end
          langs[code] = { code = code, name = type(data.name) == "string" and data.name or code, strings = strings }
        elseif deps.log then
          deps.log("lang/%s was skipped: %s", file, tostring(err or "no strings table"))
        end
      end
    end
    en = langs.en or { code = "en", name = "English", strings = {} }
    langs.en = en
    cur = en
  end
  scan()

  local T = {}
  T.loadData = loadData
  setmetatable(T, { __call = function(_, key)
    local s = cur.strings[key]
    if s == nil then s = en.strings[key] end
    if s == nil then return key end
    return s
  end })

  function T.f(key, ...)
    local ok, s = pcall(string.format, T(key), ...)
    if ok then return s end
    -- (a translation whose %s don't match: the English)
    ok, s = pcall(string.format, en.strings[key] or key, ...)
    return ok and s or key
  end

  function T.has(key) return en.strings[key] ~= nil end
  function T.code() return cur.code end

  function T.set(code)
    local l = langs[code]
    if not l then return false end
    cur = l
    return true
  end

  function T.languages()
    local out = {}
    for code, l in pairs(langs) do out[#out + 1] = { code = code, name = l.name } end
    table.sort(out, function(a, b)
      if (a.code == "en") ~= (b.code == "en") then return a.code == "en" end
      return a.code < b.code
    end)
    return out
  end
  -- (tests: a language's own words, without English under them)
  function T.raw(code) return langs[code] and langs[code].strings or nil end

  function T.list(spec)
    local byLang = cache[spec]
    if not byLang then
      byLang = {}
      cache[spec] = byLang
    end
    local out = byLang[cur]
    if not out then
      out = {}
      for i, e in ipairs(spec) do
        if type(e) == "table" then out[i] = { e[1], T(e[2]) } else out[i] = T(e) end
      end
      byLang[cur] = out
    end
    return out
  end

  return T
end
