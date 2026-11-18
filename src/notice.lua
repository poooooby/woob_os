-- Update notices (FireRed / LeafGreen / Ruby / Sapphire / Emerald): something the player should hear about
-- once, after an update brings it. The first time they're free in the field (a moment after: the screen's
-- fade done), the newest notice not yet seen opens full screen over the field (the app "notice", never on
-- the grid; src/apps/notice.lua). Seen ids are kept in Settings "noticesSeen" (comma-separated; the
-- installation's, not a save's), marked as soon as the player answers: it never shows again, even if the
-- game closes on its last page. A new notice is a new id here (and its words).
-- The Modern Menus notice asks whether to use them: the answer is the real mod option, set as the mod list's
-- own screen sets it (the engine's src.mods.ManagerState setOption: the options the loader reads, saved to
-- options.lua, mod.options_changed), so START > OPTIONS > MODS > WoobOS shows it and changes it after.
--
--   No = notice(engine, deps)   deps: Sh ; Settings ; modId ; log(fmt, ...)
--   No.NOTICES = { { id, option, titleKey, bodyKey, ... } }
--   No.pending() -> the newest unseen notice, or nil
--   No.step(game) (each frame: cheap; opens one when it's time) ; No.answer(n, yes, game) ; No.seen(id)
--   No.now: the clock (tests swap it)

return function(engine, deps)
  local No = {}
  local Settings = deps.Settings

  No.NOTICES = {
    { id = "modernMenus-1", option = "modernMenus", titleKey = "notice.menus.title", bodyKey = "notice.menus.body",
      onKey = "notice.menus.on", offKey = "notice.menus.off", afterKey = "notice.menus.after" },
  }
  No.WAIT = 1.5   -- (seconds free in the field before it opens)

  local function log(fmt, ...) if deps.log then pcall(deps.log, fmt, ...) end end
  function No.now() return love and love.timer and love.timer.getTime() or os.clock() end

  local function seenSet()
    local out = {}
    local v = Settings and Settings.get("noticesSeen", "") or ""
    for id in tostring(v):gmatch("[^,]+") do out[id] = true end
    return out
  end
  function No.seen(id) return seenSet()[id] == true end

  function No.pending()
    local seen = seenSet()
    for i = #No.NOTICES, 1, -1 do
      local n = No.NOTICES[i]
      if not seen[n.id] then return n end
    end
    return nil
  end

  local function markSeen(id)
    if not Settings or No.seen(id) then return end
    local v = tostring(Settings.get("noticesSeen", "") or "")
    Settings.set("noticesSeen", v == "" and id or (v .. "," .. id))
  end

  -- (the mod option, as the mod list's screen sets it)
  local function setOption(game, key, value)
    local MS = engine("src.mods.ManagerState")
    if not (MS and MS.new and game) then return false end
    local ok, err = pcall(function() MS.new(game):setOption(deps.modId, key, value) end)
    if not ok then log("the notice couldn't set %s: %s", tostring(key), tostring(err)) end
    return ok
  end

  -- the player's answer: the option set, the notice seen (before its last page shows)
  function No.answer(n, yes, game)
    if not n then return end
    if n.option then setOption(game or No.game, n.option, yes == true) end
    markSeen(n.id)
  end

  -- each frame: free in the field for a moment with one unseen -> open it (once this run; nothing more to
  -- check after it's been answered)
  local freeSince, done, nextLook = nil, false, 0
  function No.step(game)
    if done then return end
    local Sh = deps.Sh
    if not (Sh and Sh.free and Sh.openFull) then return end
    local t = No.now()
    if not Sh.free(game) then freeSince = nil return end
    if not freeSince then freeSince = t end
    if t - freeSince < No.WAIT or t < nextLook then return end
    nextLook = t + 1
    local n = No.pending()
    if not n then done = true return end
    No.game = game
    local okS, s = pcall(function()
      local rt = engine("src.core.game3.runtime")
      return rt and rt.getSession and rt.getSession() or nil
    end)
    local ok, opened = pcall(Sh.openFull, "notice", okS and s or nil, nil, nil,
      { fade = true, chrome = false, noHints = true, notice = n })
    if ok and opened then done = true
    elseif not ok then log("the notice couldn't open: %s", tostring(opened)) end
  end

  return No
end
