-- The MODS screen, modern (every game; Modern Menus' "Mods" switch): the mod manager's own lists and rules -- the
-- engine's ManagerState, built off the stack over the game -- drawn by src/apps/options.lua as OPTIONS is. The
-- installed mods under a section for each kind (Content, Gameplay, Mechanics, Graphics, Interface, Tools, Other:
-- each manifest's `category`), each with its switch and a word on where it stands; a mod's own page (its switch,
-- its options, trying it on a game it wasn't made for, its place in the load order, what it is and what it may
-- touch, its problem); a change waiting for a restart offered at the top, with undoing it. Turning one on or off
-- asks what the manager would (the mods it needs or that need it, a conflict, an experimental mod) in our words.
-- Profiles and the rest stay the game's own manager's: "Classic" opens it.
--   Gen 3: src.ui.game3.mod_manager.show wrapped (Mm.wrap); Gen 1 / 2: the "ManagerState" screen taken over
--   (Mm.install), START's and OPTIONS' MODS alike. Opened from our OPTIONS window: its pages pushed in that window.
--
--   Mm = ModsScreen(engine, deps)   deps: Sh, Os (src/options_screen.lua's), T, on() -> the switch, gen (1 | 2 | 3),
--                                   noId (src/gb/host.lua's H.noId, Game Boy), log
--   Mm.model(game, opts) -> the window's model { kind = "mods", top(ui) -> page, ... } ; Mm.isOpen()
--   Mm.wrap() (Gen 3, at game.ready) ; Mm.install(screens) (Game Boy) ; Mm.inWindow (set by an open OPTIONS window)
--   ui (the window's): push(page), ok(text), confirm(text, yes), toast(text), close(), refresh()

-- (the sections, in this order; a category not here after them, by name)
local SECTIONS = { "CONTENT", "GAMEPLAY", "MECHANIC", "GRAPHICS", "UI", "TOOL", "OTHER" }
local SECTION_KEY = { CONTENT = "mods.cat.content", GAMEPLAY = "mods.cat.gameplay", MECHANIC = "mods.cat.mechanic",
                      GRAPHICS = "mods.cat.graphics", UI = "mods.cat.ui", TOOL = "mods.cat.tool", OTHER = "mods.cat.other" }
-- (the same kind spelled another way)
local SAME = { TOOLS = "TOOL", MECHANICS = "MECHANIC", INTERFACE = "UI", GFX = "GRAPHICS" }
local BADGE = { CONTENT = { 52, 199, 89 }, GAMEPLAY = { 255, 149, 0 }, MECHANIC = { 175, 82, 222 },
                GRAPHICS = { 255, 45, 85 }, UI = { 10, 132, 255 }, TOOL = { 142, 142, 147 }, OTHER = { 48, 176, 199 } }
local PERMISSION_KEY = { engine_internals = "mods.perm.engine", network = "mods.perm.network",
                         filesystem = "mods.perm.files", steps = "mods.perm.steps", background = "mods.perm.background",
                         compute = "mods.perm.compute" }

return function(engine, deps)
  local Mm = {}
  local Sh, Os, T = deps.Sh, deps.Os, deps.T
  local function log(fmt, ...) if deps.log then pcall(deps.log, fmt, ...) end end
  local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b = pcall(f, ...)
    if not ok then
      log("the mods screen: %s", tostring(a))
      return nil
    end
    return a, b
  end
  local function on() return deps.on == nil or deps.on() == true end
  local open = false
  function Mm.isOpen() return open end
  local function sentence(s) return Os and Os.sentence and Os.sentence(s) or tostring(s or "") end
  local function safeMode()
    local R = engine("src.mods.Runtime")
    return type(R) == "table" and R.safeMode == true
  end

  -- the manager, built off the stack over the game (Gen 3: as the game's own screen builds it, over a stand-in that
  -- holds the options and restarts)
  local function manager(game, onRestart)
    local MS = engine("src.mods.ManagerState")
    if not (MS and type(MS.new) == "function" and type(game) == "table") then return nil end
    local over = game
    if deps.gen == 3 then
      over = setmetatable({
        stack = { pop = function() end, push = function() end },
        save = type(game.options) == "table" and { options = game.options } or nil,
        restartWithMods = function()
          if onRestart then pcall(onRestart) end
          if game.restartWithMods then return game:restartWithMods() end
          local HS = engine("src.core.HostShell")
          if HS and HS.restart then HS.restart() end
        end,
      }, { __index = game })
    end
    local ms = call(MS.new, over)
    if not ms then return nil end
    -- (its first look: a profile seeded as the game's own screen does)
    if not call(ms.enter, ms) then call(ms.refresh, ms) end
    if not ms.status then return nil end
    return ms
  end

  local function kindOf(m)
    local c = tostring(m.category or "OTHER"):upper():gsub("[^%w]", "")
    return SAME[c] or (c ~= "" and c or "OTHER")
  end
  local function sectionWord(kind)
    local k = SECTION_KEY[kind]
    if k then return T(k) end
    return sentence(kind:lower())
  end
  local function nameOf(ms, id)
    local m = ms.byId and ms.byId[id]
    return tostring(m and (m.name or m.id) or id)
  end
  local function names(ms, ids)
    local out = {}
    for i, id in ipairs(ids) do out[i] = nameOf(ms, id) end
    return table.concat(out, ", ")
  end
  local function authorOf(m)
    local raw = type(m.raw) == "table" and m.raw or {}
    local a = raw.author or m.author or raw.authors
    if type(a) == "table" then
      local out = {}
      for _, x in ipairs(a) do out[#out + 1] = type(x) == "table" and tostring(x.name or "") or tostring(x) end
      a = table.concat(out, ", ")
    end
    return a and tostring(a) ~= "" and tostring(a) or nil
  end

  -- where a mod stands: its word and its tone
  local function status(ms, m)
    if ms:isStaged(m) then return T(m.enabled and "mods.st.onAfter" or "mods.st.offAfter"), "accent" end
    if not m.enabled then return T("mods.st.off"), nil end
    if m.state == "wrong_generation" or not call(ms.runsHere, ms, m) then return T("mods.st.notHere"), nil end
    if m.state == "blocked_dependency" then return T("mods.st.waiting"), "red" end
    if m.error then return T("mods.st.problem"), "red" end
    return T("mods.st.on"), "green"
  end

  -- ------- turning one on or off: the manager's own resolution, its questions ours
  local function toggle(ms, m, ui)
    if safeMode() then return ui.toast(T("mods.safe")) end
    local want = not m.enabled
    local loader = ms.game and ms.game.mods
    local r
    if loader and loader.resolveToggle then r = call(loader.resolveToggle, loader, m.id, want, ms:enabledSet())
    else
      local MS = engine("src.mods.ManagerState")
      r = MS and call(MS.resolveToggle, ms:manifestMap(), m.id, want, ms:enabledSet())
    end
    if type(r) ~= "table" then return end
    local function commit()
      call(ms.commitToggle, ms, r.apply)
      ui.refresh()
    end
    local function proceed()
      -- (what stops it: a mod it needs that isn't here, a conflict, a version)
      local lines = {}
      for _, id in ipairs(r.missing or {}) do lines[#lines + 1] = T.f("mods.ask.missing", tostring(id)) end
      for _, id in ipairs(r.conflicts or {}) do lines[#lines + 1] = T.f("mods.ask.conflict", nameOf(ms, id)) end
      for _, bad in ipairs(r.badVersion or {}) do
        if bad.engine then lines[#lines + 1] = T.f("mods.ask.engine", tostring(bad.need), tostring(bad.got))
        else lines[#lines + 1] = T.f("mods.ask.version", nameOf(ms, bad.id), tostring(bad.need)) end
      end
      if #lines > 0 then return ui.ok(table.concat(lines, "\n")) end
      if want and #(r.alsoEnable or {}) > 0 then
        return ui.confirm(T.f("mods.ask.alsoOn", names(ms, r.alsoEnable)), commit)
      end
      if not want and #(r.alsoDisable or {}) > 0 then
        return ui.confirm(T.f("mods.ask.alsoOff", names(ms, r.alsoDisable)), commit)
      end
      commit()
    end
    if want and m.experimental then return ui.confirm(T("mods.ask.experimental"), proceed) end
    proceed()
  end

  -- ------- a mod's own page
  local function modPage(model, ms, id, ui)
    local page = { title = nameOf(ms, id), rows = {} }
    function page.rebuild()
      call(ms.refresh, ms)
      local m = ms.byId and ms.byId[id]
      local rows = {}
      page.rows = rows
      if not m then return rows end
      page.title = tostring(m.name or m.id)
      local desc = m.description and tostring(m.description) or nil
      page.desc = desc
      local word, tone = status(ms, m)
      -- (a word under its switch only when it says more than on or off)
      local more = tone == "accent" or tone == "red" or (m.enabled and tone ~= "green")
      rows[#rows + 1] = { id = "on", kind = "toggle", label = T("mods.row.on"), sub = more and word or nil, subTone = tone,
                          desc = desc,
                          on = function() return m.enabled == true end,
                          value = function() return m.enabled and "On" or "Off" end,
                          step = function() toggle(ms, m, ui) return false end }
      -- (its options: OPTIONS' page for it)
      if not safeMode() and call(ms.schemaFor, ms, m) and Os and Os.modPage then
        rows[#rows + 1] = { id = "options", kind = "group", label = T("mods.row.options"), desc = desc,
                            activate = function()
                              local p = Os.modPage(id, ms.game)
                              if p then ui.push(p) end
                            end }
      end
      -- (a game it wasn't made for: try it anyway, on the next start)
      local MT = engine("src.mods.ModTargets")
      local version, gen = call(ms.targetGame, ms)
      local loader = ms.game and ms.game.mods
      if MT and loader and loader.setGen2Forced and not safeMode() and not call(MT.supports, m, version, gen) then
        rows[#rows + 1] = { id = "try", kind = "toggle", label = T("mods.row.try"), desc = T("mods.desc.try"),
                            on = function() return m.gen2Forced == true end,
                            value = function() return m.gen2Forced and "On" or "Off" end,
                            step = function()
                              ms.overlay = nil
                              call(ms.toggleGen2Force, ms, m)
                              local o = ms.overlay
                              ms.overlay, ms.notice = nil, nil
                              if o and o.onYes then
                                ui.confirm(T("mods.ask.try"), function() call(o.onYes) ms.notice = nil ui.refresh() end)
                              end
                              return false
                            end }
      end
      -- (its place in the load order: Left / Right moves it, on the next start)
      local LO = engine("src.mods.LoadOrder")
      local report = loader and loader.cartReport
      if not safeMode() and LO then
        local locked = report and report.rank and report.rank[m.id]
        rows[#rows + 1] = { id = "order", kind = "choice", label = T("mods.row.order"), desc = T(locked and "mods.desc.orderCart" or "mods.desc.order"),
                            value = function()
                              local shown = call(ms.loadOrderList, ms) or {}
                              local at = call(LO.position, shown, m.id)
                              if locked then return T("mods.order.cart") end
                              return at and T.f("mods.order.at", at, #shown) or "-"
                            end,
                            step = (not locked) and function(_, dir)
                              local moved = call(ms.moveOrder, ms, m, dir < 0 and -1 or 1)
                              ms.notice = nil
                              return moved == true
                            end or nil }
      end
      -- (what it is)
      rows[#rows + 1] = { id = "version", kind = "plain", label = T("mods.row.version"), desc = desc,
                          value = function() return tostring(m.version or "-") end }
      local who = authorOf(m)
      if who then
        rows[#rows + 1] = { id = "author", kind = "plain", label = T("mods.row.author"), desc = desc, value = function() return who end }
      end
      rows[#rows + 1] = { id = "kind", kind = "plain", label = T("mods.row.kind"), desc = desc,
                          value = function() return sectionWord(kindOf(m)) end }
      local games = MT and call(MT.label, m)
      if games then
        rows[#rows + 1] = { id = "games", kind = "plain", label = T("mods.row.games"), desc = desc, value = function() return games end }
      end
      -- (what it may touch)
      local perms = {}
      for _, p in ipairs(m.permissions or {}) do
        local k = PERMISSION_KEY[p]
        perms[#perms + 1] = k and T(k) or sentence(tostring(p):gsub("_", " "))
      end
      rows[#rows + 1] = { id = "perms", kind = "plain", label = T("mods.row.perms"),
                          desc = #perms > 0 and T("mods.desc.perms") or desc,
                          value = function()
                            if #perms == 0 then return T("mods.perm.none") end
                            return (table.concat(perms, ", "):gsub("^%l", string.upper))
                          end }
      if m.experimental then
        rows[#rows + 1] = { id = "exp", kind = "plain", label = T("mods.row.experimental"), desc = T("mods.desc.experimental") }
      end
      if m.error then
        rows[#rows + 1] = { id = "error", kind = "plain", label = T("mods.row.problem"), subTone = "red",
                            sub = tostring(m.error):gsub("%s+", " "):sub(1, 80), desc = tostring(m.error) }
      end
      return rows
    end
    page.rebuild()
    return page
  end

  -- ------- the list
  local function topPage(model, ms, ui)
    local page = { title = T("mods.title"), rows = {} }
    function page.rebuild()
      call(ms.refresh, ms)
      local rows = {}
      page.rows = rows
      if safeMode() then
        rows[#rows + 1] = { id = "__safe", kind = "plain", label = T("mods.safeTitle"), sub = T("mods.safe"), subTone = "red" }
      end
      -- (a change waiting: restart now, or undo it)
      if ms.restartPending then
        local sec = T("mods.sec.changes")
        rows[#rows + 1] = { id = "__restart", kind = "action", label = T("mods.row.restart"), tone = "accent", section = sec,
                            desc = T("mods.desc.restart"),
                            activate = function() ui.confirm(T("mods.ask.restart"), function() model.restart() end) end }
        rows[#rows + 1] = { id = "__discard", kind = "action", label = T("mods.row.discard"), tone = "red", section = sec,
                            activate = function()
                              call(ms.discardChanges, ms)
                              ms.notice = nil
                              ui.toast(T("mods.discarded"))
                              ui.refresh()
                            end }
      end
      -- (the mods the game's own list shows: the manager's modRows, which another mod may filter -- Cleaner Mod
      -- Options' HIDE DISABLED / HIDE OTHER GAMES -- the same ones here; unanswerable: all of them)
      local shown
      local mrows = call(ms.modRows, ms)
      if type(mrows) == "table" then
        shown = {}
        for _, r in ipairs(mrows) do
          if type(r) == "table" and type(r.mod) == "table" then shown[r.mod] = true end
        end
      end
      -- (each kind its section)
      local byKind, kinds, hidden = {}, {}, 0
      for _, m in ipairs(ms.status and ms.status.available or {}) do
        if shown and not shown[m] then
          hidden = hidden + 1
        else
          local k = kindOf(m)
          if not byKind[k] then byKind[k], kinds[#kinds + 1] = {}, k end
          table.insert(byKind[k], m)
        end
      end
      local rank = {}
      for i, k in ipairs(SECTIONS) do rank[k] = i end
      table.sort(kinds, function(a, b)
        local ra, rb = rank[a] or 100, rank[b] or 100
        if ra ~= rb then return ra < rb end
        return a < b
      end)
      for _, k in ipairs(kinds) do
        local list = byKind[k]
        table.sort(list, function(a, b) return tostring(a.name or a.id):lower() < tostring(b.name or b.id):lower() end)
        local sec = sectionWord(k)
        for _, m in ipairs(list) do
          local word, tone = status(ms, m)
          local name = tostring(m.name or m.id)
          -- (on or off on a chip by its name, the line under it only when it says more; A its page, where its switch
          -- is; no description card here, the list kept whole while moving along it: it's on the mod's page)
          local plain = word == T("mods.st.on") or word == T("mods.st.off")
          rows[#rows + 1] = { id = m.id, kind = "group", label = name, section = sec,
                              sub = not plain and word or nil, subTone = tone,
                              chip = { on = m.enabled == true, key = m.enabled and "mods.st.on" or "mods.st.off" },
                              badge = { letter = name:match("[%w]") or "?", colour = BADGE[k] or BADGE.OTHER },
                              open = function() return modPage(model, ms, m.id, ui) end }
        end
      end
      if #(ms.status and ms.status.available or {}) == 0 then
        rows[#rows + 1] = { id = "__none", kind = "plain", label = T("mods.none") }
      elseif #kinds == 0 then
        rows[#rows + 1] = { id = "__none", kind = "plain", label = T.f("mods.allHidden", tostring(hidden)) }
      end
      -- (the loader's problems; the rest -- profiles -- the game's own manager)
      local more = T("mods.sec.more")
      local errs = ms.status and ms.status.errors or {}
      if #errs > 0 then
        rows[#rows + 1] = { id = "__errors", kind = "group", label = T("mods.row.problems"), section = more,
                            value = function() return tostring(#errs) end,
                            activate = function()
                              local p = { title = T("mods.row.problems"), rows = {} }
                              for i, e in ipairs(errs) do
                                local text = tostring(e)
                                p.rows[i] = { id = "e" .. i, kind = "plain", label = text:gsub("%s+", " "):sub(1, 60),
                                              desc = text }
                              end
                              ui.push(p)
                            end }
      end
      if model.classic then
        rows[#rows + 1] = { id = "__classic", kind = "action", label = T("mods.row.classic"), section = more,
                            desc = T("mods.desc.classic"), activate = function() model.classic() end }
      end
      return rows
    end
    page.rebuild()
    return page
  end

  -- the window's model
  function Mm.model(game, opts)
    opts = opts or {}
    local model = { kind = "mods", ctx = game, game = game }
    local ms = manager(game, function() if model.ui then model.ui.close() end end)
    if not ms then return nil end
    model.ms = ms
    function model.top(ui)
      model.ui = ui
      return topPage(model, ms, ui)
    end
    function model.restart()
      if model.ui then model.ui.close() end
      call(ms.restartGame, ms)
    end
    model.classic = opts.classic
    function model.persist() call(ms.persistOptions, ms) end
    return model
  end

  -- ------- the takeover

  local function openFull(model, s, onClose)
    open = true
    local ok, got = pcall(Sh.openFull, "options", s, function()
      open = false
      if onClose then
        local okC, err = pcall(onClose)
        if not okC then log("after MODS: %s", tostring(err)) end
      end
    end, nil, { menu = model, chrome = false, noHints = true })
    if not (ok and got) then
      open = false
      if not ok then log("the modern MODS failed to open: %s", tostring(got)) end
      return false
    end
    return true
  end

  -- Gen 3: the game's own screen's show
  local function openMods3(orig, opts)
    if open or not on() or not (Sh and Sh.openFull) or type(opts) ~= "table" or not opts.game or not opts.session then
      return false
    end
    local model
    -- (Classic: ours closes and the game's own opens in its place, the caller's close then its)
    local toClassic = false
    model = Mm.model(opts.game, { classic = function()
      toClassic = true
      if model.ui then model.ui.close() end
      local MM = engine("src.ui.game3.mod_manager")
      local w = MM and rawget(MM, "__woobOsMods")
      if w then
        w.bypass = true
        local ok, err = pcall(w.orig, { game = opts.game, session = opts.session, onClose = opts.onClose })
        w.bypass = false
        if not ok then log("the game's own MODS: %s", tostring(err)) end
      end
    end })
    if not model then return false end
    -- (asked for from our OPTIONS window: its pages there)
    if Mm.inWindow and Mm.inWindow(model) then return true end
    return openFull(model, opts.session, function()
      if not toClassic and opts.onClose then opts.onClose() end
    end)
  end

  function Mm.wrap()
    local MM = engine("src.ui.game3.mod_manager")
    if type(MM) ~= "table" or type(MM.show) ~= "function" then return end
    local w = rawget(MM, "__woobOsMods")
    if not w then
      w = { orig = MM.show }
      MM.__woobOsMods = w
      MM.show = function(opts, ...)
        local cw = rawget(MM, "__woobOsMods")
        if cw.impl and not cw.bypass then
          local ok, took = pcall(cw.impl, cw.orig, opts)
          if ok and took then return end
          if not ok then log("the modern MODS failed to open: %s", tostring(took)) end
        end
        return cw.orig(opts, ...)
      end
    end
    w.impl = openMods3
  end

  -- Game Boy: the "ManagerState" screen (START's MODS, OPTIONS' MODS, F10): a carrier of ours in its place, popped
  -- when ours closes (as the game's pops itself)
  function Mm.install(screens)
    if not (screens and screens.register) then return false end
    local noId = deps.noId or function(t) return t end
    local function own(game) return engine("src.mods.ManagerState").new(game) end
    screens:register("ManagerState", { new = function(game, ...)
      local playing = type(game) == "table" and game.save ~= nil and (game.phase == nil or game.phase == "play"
        or game.phase == "field")
      if not (on() and playing and Sh and Sh.openFull) then return own(game) end
      -- (F10 again while ours is up: ours closes, as the game's toggles)
      if open then
        local s = noId({ isOpaque = false, draw = function() end })
        s.update = function(me)
          local stk = game.stack
          if stk and stk:top() == me then pcall(stk.pop, stk) end
          local h = Sh.host and Sh.host()
          local st = h and h.state and h.state()
          if st and st.ctx and st.ctx.done then pcall(st.ctx.done) end
        end
        return s
      end
      local c = noId({ isOpaque = true, game = game })
      local model
      local function pop()
        local stk = game.stack
        if stk and stk:top() == c then pcall(stk.pop, stk) end
      end
      model = Mm.model(game, { classic = function()
        if model.ui then model.ui.close() end
        game.stack:push(own(game))
      end })
      if not model then return own(game) end
      c.draw = function(self)
        if not self.isOpaque then return end
        local G = love and love.graphics
        if G then
          G.setColor(0, 0, 0, 1)
          G.rectangle("fill", 0, 0, 160, 144)
          G.setColor(1, 1, 1, 1)
        end
      end
      c.update = function(self)
        if self.opened then
          -- (back on top with ours gone)
          if not self.done and not (Sh.hostOpen and Sh.hostOpen()) then
            self.done = true
            pop()
          end
          return
        end
        self.opened = true
        -- (asked for from our OPTIONS window: its pages there)
        if Mm.inWindow and Mm.inWindow(model) then
          self.done = true
          pop()
          return
        end
        if not openFull(model, game.save, function()
          if self.done then return end
          self.done = true
          -- (the classic manager pushed meanwhile stays: only ours goes)
          local stk = game.stack
          local list = stk and stk.states or {}
          for i = #list, 1, -1 do if list[i] == c then table.remove(list, i) break end end
        end) then
          self.done = true
          pop()
          game.stack:push(own(game))
        end
      end
      return c
    end })
    return true
  end

  return Mm
end
