-- The OPTIONS screen, modern (FireRed, LeafGreen, Ruby, Sapphire, Emerald; Modern Menus' "Options" switch): the
-- game's own rows and the engine's, built as each game builds them (FireRed / LeafGreen's src.ui.game3.option_rows,
-- Ruby / Sapphire / Emerald's cart rows over it), the same pages (SPEED, VIDEO, AUDIO...), each row doing what it
-- does there; a row another mod adds to the top (the engine's ui.options.rows hook) tagged with its mod's name;
-- and each mod's own options page -- where the mod manager would open it -- with its options' trees (an option
-- shown while another has a value: indented under it) and their descriptions. src/apps/options.lua draws it.
--
--   Os = OptionsScreen(engine, deps)   deps: Sh, on() -> the switch, family() -> "frlg" | "rse" | "rs" (Ruby /
--                                     Sapphire's own screen), log
--   Os.wrap() (at game.ready) ; Os.isOpen() ; Os.modPage(modId, game) -> a page | nil
--   model = ctx.menu: { kind = "options" | "mod", ctx (the engine's { session, game, options }), top (a page), pages
--     to open: openPage(title, rows) set by the window, persist(), close() (the game's onClose) }
--   page = { title, rows = { row ... }, mod (its id, a mod's page) }
--   row  = { id, label, value(ctx) -> text | nil, step(ctx, dir) -> changed, activate(ctx), kind ("toggle" |
--            "choice" | "number" | "text" | "group" | "action" | "plain"), on (a toggle's state: fn), depth (a mod
--            page's tree), desc, modName (a top row another mod added), choices (a choice's { label } list),
--            reset (the mod page's Reset Defaults) }

return function(engine, deps)
  local Os = {}
  local Sh = deps.Sh
  local function log(fmt, ...) if deps.log then pcall(deps.log, fmt, ...) end end
  local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b = pcall(f, ...)
    if not ok then return nil end
    return a, b
  end
  local function on() return deps.on == nil or deps.on() == true end
  local open = false
  function Os.isOpen() return open end

  local function stripColors(s)
    s = tostring(s or "")
    s = s:gsub("{COLOR[^}]*}", ""):gsub("{SHADOW[^}]*}", ""):gsub("{HIGHLIGHT[^}]*}", "")
    s = s:gsub("\252[\1\2\3].", ""):gsub("\252\4...", "")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
  end
  -- (a game's shouted words in a sentence's case: TEXT SPEED -> Text speed; HP, PP, FX, UI, FPS... kept)
  local KEEP = { HP = true, PP = true, FX = true, UI = true, FPS = true, LR = true, ["L=A"] = true, GBA = true,
                 CRT = true, VSYNC = true, GB = true, GBC = true, RTC = true, BGM = true, SFX = true, ["2X"] = true, ["3X"] = true, ["1X"] = true }
  local function sentence(s)
    s = stripColors(s)
    if s == "" or s:find("%l") then return s end
    local first = true
    return (s:gsub("[%w%.=']+", function(w)
      if KEEP[w] or w:find("%d") then first = false return w end
      local out = first and (w:sub(1, 1) .. w:sub(2):lower()) or w:lower()
      first = false
      return out
    end))
  end
  Os.sentence = sentence

  -- ------- the game's rows

  local function managerState(game)
    local MS = engine("src.mods.ManagerState")
    if not (MS and game) then return nil end
    local ms = call(MS.new, game)
    if ms then call(ms.refresh, ms) end
    return ms
  end

  -- Ruby / Sapphire / Emerald's own rows: their words and choices are the cart's (src/ui/game3/rse/option_menu.lua)
  local function rseCartRows(ctx)
    local RseMenu, Options = engine("src.ui.game3.rse.option_menu"), engine("src.core.game3.options")
    local RomText, Chrome = engine("src.core.game3.rom_text"), engine("src.ui.game3.chrome")
    if not (RseMenu and RseMenu.CART and Options and RomText) then return nil end
    local function cart() return Options.block(ctx.options) end
    local function cur(key) return tonumber(cart()[key]) or 0 end
    local function set(key, v)
      Options.set({ options = cart() }, key, v)
      local g = ctx.game
      if g and g.writeOptions then pcall(g.writeOptions, g) end
    end
    local out = {}
    for _, r in ipairs(RseMenu.CART) do
      local row = { id = r.id, label = sentence(RomText.plain(r.label)), cartRow = true }
      if r.frame then
        row.kind = "choice"
        row.value = function()
          return sentence(RomText.plain("gText_FrameType")) .. " " .. tostring(cur(r.key) + 1)
        end
        row.step = function(_, dir)
          local n = Chrome and call(Chrome.userFrameCount) or 20
          local v = ((cur(r.key) + (dir < 0 and -1 or 1)) % n + n) % n
          set(r.key, v)
          if Chrome then call(Chrome.setFrameType, v) end
          return false
        end
      else
        row.kind = "choice"
        row.choices = {}
        for i, key in ipairs(r.choices) do row.choices[i] = sentence(RomText.plain(key)) end
        row.value = function() return row.choices[cur(r.key) + 1] or "?" end
        row.step = function(_, dir)
          local v = cur(r.key)
          local nv = r.toggle and (1 - v) or (((v + (dir < 0 and -1 or 1)) % r.count + r.count) % r.count)
          set(r.key, nv)
          if r.id == "sound" then
            local Audio = engine("src.core.game3.audio")
            if Audio then call(Audio.applyOptions, { options = cart() }) end
          end
          return false
        end
      end
      out[r.id] = row
    end
    return out
  end

  -- Ruby / Sapphire's own rows: their words the cart's menu data (src/ui/game3/rs/option_menu.lua's), each change
  -- kept at once (theirs on the way out)
  local RS_KEYS = { "textSpeed", "battleScene", "battleStyle", "sound", "buttonMode", "frameType" }
  local RS_COUNTS = { 3, 2, 2, 2, 3, 20 }
  local RS_WORDS = { { "Text Speed", { "Slow", "Mid", "Fast" } }, { "Battle Scene", { "On", "Off" } },
                     { "Battle Style", { "Shift", "Set" } }, { "Sound", { "Mono", "Stereo" } },
                     { "Button Mode", { "Normal", "LR", "L=A" } }, { "Frame", {} } }
  local function rsCartRows(ctx)
    local Options, Kit, Chrome = engine("src.core.game3.options"), engine("src.ui.game3.rse.scene_kit"), engine("src.ui.game3.chrome")
    if not Options then return nil end
    local man = Kit and call(Kit.manifest, "rse/menus")
    local d = type(man) == "table" and type(man.option) == "table" and man.option or nil
    local block = call(Options.bind, ctx.session or {}, ctx.options) or call(Options.block, ctx.options) or {}
    local function cur(key) return tonumber(block[key]) or 0 end
    local function set(key, v)
      call(Options.set, ctx.session, key, v)
      block[key] = v
      local g = ctx.game
      if g and g.writeOptions then pcall(g.writeOptions, g) end
    end
    local out = {}
    for i, key in ipairs(RS_KEYS) do
      local dr = d and d.rows and d.rows[i]
      local row = { id = key, label = sentence(dr and dr.text or RS_WORDS[i][1]), cartRow = true, kind = "choice" }
      if key == "frameType" then
        local word = sentence(d and d.frameLabel or "Type")
        row.value = function() return word .. " " .. tostring(cur(key) + 1) end
      else
        row.choices = {}
        for j = 1, RS_COUNTS[i] do
          local ch = dr and dr.choices and dr.choices[j]
          row.choices[j] = sentence(ch and ch.text or RS_WORDS[i][2][j] or tostring(j))
        end
        row.value = function() return row.choices[cur(key) + 1] or "?" end
      end
      row.step = function(_, dir)
        local n = RS_COUNTS[i]
        local v = n == 2 and (1 - cur(key)) or (((cur(key) + (dir < 0 and -1 or 1)) % n + n) % n)
        set(key, v)
        if key == "sound" then
          local Audio = engine("src.core.game3.audio")
          if Audio and Audio.setCryStereo then call(Audio.setCryStereo, v) end
        elseif key == "frameType" and Chrome then
          call(Chrome.setFrameType, v)
        end
        return false
      end
      out[key] = row
    end
    return out
  end

  -- (each row's kind, for its control: a page, an action, a two-way choice shown as a switch)
  local SWITCH = { ON = true, OFF = true }
  local function classify(row, ctx)
    if row.kind then return end
    if row.group then row.kind = "group" return end
    if row.activate and not row.step then row.kind = "action" return end
    local v = row.value and call(row.value, ctx)
    if type(v) == "string" and SWITCH[v:upper()] then row.kind = "toggle" else row.kind = "choice" end
  end

  -- the OPTIONS screen's top page: the game's rows, grouped as the game groups them; another mod's rows tagged
  function Os.top(ctx, family, openPage)
    local Rows, Runtime = engine("src.ui.game3.option_rows"), engine("src.mods.Runtime")
    if not Rows then return nil end
    local cartRows = family == "rse" and rseCartRows(ctx) or (family == "rs" and rsCartRows(ctx)) or nil
    -- (Ruby / Sapphire leave the event tickets' row out, as their own screen does)
    local exclude = family == "rs" and { eventTickets = true } or nil
    local function build()
      if cartRows then return call(Rows.withCart, ctx, cartRows, openPage, exclude) end
      local flat = call(Rows.build, ctx)
      return flat and call(Rows.group, flat, openPage) or nil
    end
    -- (the rows the game and the engine make: the hook asked for nothing, once, to tell the mods' apart)
    local own = {}
    if Runtime and type(Runtime.wantsHook) == "function" then
      local wants = Runtime.wantsHook
      Runtime.wantsHook = function(name, ...)
        if name == "ui.options.rows" then return false end
        return wants(name, ...)
      end
      local plain = build()
      Runtime.wantsHook = wants
      for _, r in ipairs(plain or {}) do if r.id then own[r.id] = true end end
    end
    local rows = build()
    if type(rows) ~= "table" then return nil end
    local ms = managerState(ctx.game)
    local byId = ms and ms:manifestMap() or {}
    for _, r in ipairs(rows) do
      r.label = sentence(r.label or r.id or "?")
      if r.id and next(own) and not own[r.id] then
        local m = byId[r.id]
        local name = m and (m.name or m.id) or nil
        -- (a row named for its mod: the mod's own spelling, the tag just "Mod")
        local function bare(x) return (tostring(x or ""):upper():gsub("[^%w]", "")) end
        if name and bare(name) == bare(r.label) then
          r.label, r.modName = name, "Mod"
        else
          r.modName = name or "Mod"
        end
      end
      classify(r, ctx)
    end
    return rows
  end
  -- (a page's rows, opened from a group row: in the sentence's case, each one's kind)
  function Os.pageRows(ctx, rows)
    for _, r in ipairs(rows) do
      if not r.cased then
        r.label, r.cased = sentence(r.label or r.id or "?"), true
      end
      classify(r, ctx)
    end
    return rows
  end

  -- ------- a mod's own options page

  local TYPES = { toggle = true, choice = true, number = true, text = true }
  function Os.modPage(modId, game)
    local ms = managerState(game)
    local m = ms and ms.byId and ms.byId[modId]
    local schema = m and call(ms.schemaFor, ms, m)
    if type(schema) ~= "table" then return nil end
    local byKey = {}
    for _, row in ipairs(schema) do if type(row) == "table" and type(row.key) == "string" then byKey[row.key] = row end end
    local function value(row) return ms:optionValue(modId, row) end
    -- (shown: its condition holds, and its parent's is shown)
    local function shown(row, depth)
      depth = depth or 0
      if depth > 8 then return false end
      local c = row.visible_if
      if c == nil then return true end
      if type(c) ~= "table" or type(c.key) ~= "string" then return false end
      local parent = byKey[c.key] or { key = c.key }
      local v = value(parent)
      local ok
      if c.equals ~= nil then ok = v == c.equals elseif c.not_equals ~= nil then ok = v ~= c.not_equals else ok = false end
      if not ok then return false end
      return byKey[c.key] == nil or shown(byKey[c.key], depth + 1)
    end
    local function depthOf(row, n)
      n = n or 0
      local c = row.visible_if
      if n > 8 or type(c) ~= "table" or not byKey[c.key] then return n end
      return depthOf(byKey[c.key], n + 1)
    end
    local page = { title = (m.name or modId), mod = modId, rows = {} }
    -- (the rows that are shown, made again whenever a value changes: the tree opens and closes)
    function page.rebuild()
      local rows = {}
      for _, row in ipairs(schema) do
        if type(row) == "table" and type(row.key) == "string" and TYPES[row.type] and shown(row) then
          local depth = depthOf(row)
          local label = tostring(row.label or row.key)
          -- (the vanilla screen's "- " for an option under another: the tree says it here)
          if depth > 0 then label = label:gsub("^%-+%s*", "") end
          local r = { id = row.key, label = label, desc = row.description, depth = depth, kind = row.type, schema = row }
          if row.type == "toggle" then
            r.on = function() return value(row) == true end
            r.value = function() return value(row) and "ON" or "OFF" end
            r.step = function()
              ms:setOption(modId, row.key, not value(row))
              return true
            end
          elseif row.type == "choice" then
            r.choices = {}
            for i, ch in ipairs(row.choices or {}) do r.choices[i] = tostring(ch[1]) end
            r.value = function()
              local v = value(row)
              for _, ch in ipairs(row.choices or {}) do if ch[2] == v then return tostring(ch[1]) end end
              local first = (row.choices or {})[1]
              return first and tostring(first[1]) or "----"
            end
            r.index = function()
              local v = value(row)
              for i, ch in ipairs(row.choices or {}) do if ch[2] == v then return i end end
              return 1
            end
            r.step = function(_, dir)
              local choices = row.choices or {}
              if #choices == 0 then return false end
              local i = r.index() + (dir < 0 and -1 or 1)
              i = math.max(1, math.min(#choices, i))
              ms:setOption(modId, row.key, choices[i][2])
              return true
            end
            r.pick = function(i)
              local ch = (row.choices or {})[i]
              if ch then ms:setOption(modId, row.key, ch[2]) end
              return true
            end
          elseif row.type == "number" then
            local function clamp(v)
              if row.min then v = math.max(row.min, v) end
              if row.max then v = math.min(row.max, v) end
              return v
            end
            r.value = function() return tostring(value(row) or 0) end
            r.step = function(_, dir)
              ms:setOption(modId, row.key, clamp((tonumber(value(row)) or 0) + (dir < 0 and -1 or 1) * (row.step or 1)))
              return true
            end
          elseif row.type == "text" then
            r.value = function() return tostring(value(row) or "") end
            r.maxLen = row.maxLen or 7
            r.setText = function(text)
              ms:setOption(modId, row.key, text)
              return true
            end
          end
          rows[#rows + 1] = r
        end
      end
      rows[#rows + 1] = { id = "__reset", kind = "action", reset = true, label = "",
        activate = function()
          for _, row in ipairs(schema) do
            if type(row) == "table" and type(row.key) == "string" and TYPES[row.type] then
              ms:setOption(modId, row.key, row.default)
            end
          end
          return true
        end }
      page.rows = rows
      return rows
    end
    page.rebuild()
    return page
  end

  -- ------- the takeover

  -- (the shader picker: drawn by the options screen it opens from; ours lends it a layer of its own while it's up)
  local FxLayer = { isMenu = true }
  function FxLayer.handleInput(input)
    local M = engine("src.ui.game3.shaderfx_menu")
    if M and M.isOpen() then call(M.handleInput, input) end
  end
  function FxLayer.update()
    local M, Stack = engine("src.ui.game3.shaderfx_menu"), engine("src.ui.game3.stack")
    if M then call(M.update) end
    if not (M and M.isOpen()) and Stack and Stack.has("woob_shaderfx") then pcall(Stack.pop, "woob_shaderfx") end
  end
  function FxLayer.draw()
    local M = engine("src.ui.game3.shaderfx_menu")
    if M and M.isOpen() then call(M.draw) end
  end
  function Os.lendShaderLayer()
    local M, Stack = engine("src.ui.game3.shaderfx_menu"), engine("src.ui.game3.stack")
    if M and M.isOpen() and Stack and not Stack.has("woob_shaderfx") then
      pcall(Stack.push, "woob_shaderfx", FxLayer, { hideBelow = true, fullscreen = true })
    end
  end

  local function openOptions(family, opts)
    -- (the family by the game: Emerald's OPTIONS may come through FireRed's module, which hands it on)
    if deps.family then family = deps.family() or family end
    if open or not on() or not (Sh and Sh.openFull) then return false end
    -- (an OPTIONS with no save loaded -- the title screen's -- stays the game's)
    if not opts or not opts.session then return false end
    local Options, Runtime = engine("src.core.game3.options"), engine("src.core.game3.runtime")
    local game = opts.game or (Runtime and Runtime._game)
    local engineOpts = Options and call(Options.engine, opts.session) or (game and game.options)
      or (opts.session and opts.session.options) or {}
    if Options then call(Options.bind, opts.session or {}, engineOpts) end
    local ctx = { session = opts.session, game = game, options = engineOpts }
    local model = { kind = "options", ctx = ctx, family = family }
    function model.persist()
      local g = ctx.game
      if g and g.writeOptions then pcall(g.writeOptions, g) end
    end
    model.top = { title = "Options", rows = {} }
    function model.build(openPage)
      model.top.rows = Os.top(ctx, family, openPage) or {}
      return model.top
    end
    -- (the game's own screen says it's open while ours is: FireRed / LeafGreen's flag, Ruby / Sapphire's)
    local Fr = (family == "frlg" and engine("src.ui.game3.option_menu")) or (family == "rs" and engine("src.ui.game3.rs.option_menu")) or nil
    if Fr then Fr.open = true end
    open = true
    local function closed()
      open = false
      if Fr then Fr.open = false end
      for _, name in ipairs({ "src.ui.game3.controls_menu", "src.ui.game3.mod_manager" }) do
        local child = engine(name)
        if type(child) == "table" and child.open and child.close then pcall(child.close) end
      end
      local M = engine("src.ui.game3.shaderfx_menu")
      if M and M.isOpen() then call(M.close) end
      if opts.onClose then
        local ok, err = pcall(opts.onClose)
        if not ok then log("after OPTIONS: %s", tostring(err)) end
      end
    end
    if not Sh.openFull("options", opts.session, closed, nil, { menu = model, chrome = false, noHints = true }) then
      open = false
      if Fr then Fr.open = false end
      return false
    end
    return true
  end

  -- a mod's options page where the mod manager would open it: ours, over whatever's up
  local function openModPage(ms, m)
    if not on() or not (Sh and Sh.openScene) or Sh.sceneOpen() or not (m and m.id) then return false end
    local page = Os.modPage(m.id, ms and ms.game)
    if not page then return false end
    local model = { kind = "mod", page = page, ctx = { game = ms and ms.game } }
    local Runtime = engine("src.core.game3.runtime")
    local s = Runtime and call(Runtime.getSession)
    return Sh.openScene("options", s, nil, { scene = model }) == true
  end

  local function wrapFn(M, fname, key, impl)
    if type(M) ~= "table" or type(M[fname]) ~= "function" then return end
    local w = M[key]
    if not w then
      w = { orig = M[fname] }
      M[key] = w
      M[fname] = function(...)
        local cur = M[key]
        if cur.impl then
          local ok, took = pcall(cur.impl, ...)
          if ok and took then return end
          if not ok and cur.log then pcall(cur.log, "the modern OPTIONS failed to open: %s", tostring(took)) end
        end
        return cur.orig(...)
      end
    end
    w.impl, w.log = impl, function(fmt, ...) log(fmt, ...) end
  end

  function Os.wrap()
    wrapFn(engine("src.ui.game3.option_menu"), "show", "__woobOsOptions", function(opts) return openOptions("frlg", opts) end)
    wrapFn(engine("src.ui.game3.rse.option_menu"), "show", "__woobOsOptions", function(opts) return openOptions("rse", opts) end)
    wrapFn(engine("src.ui.game3.rs.option_menu"), "show", "__woobOsOptions", function(opts) return openOptions("rs", opts) end)
    wrapFn(engine("src.mods.ManagerState"), "openOptions", "__woobOsOptions", function(self, m) return openModPage(self, m) end)
  end
  Os.openModPage = openModPage

  return Os
end
