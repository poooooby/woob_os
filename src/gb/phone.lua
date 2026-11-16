-- The Phone's model on Gold / Silver / Crystal: the Pokégear's phone book (src/core/gen2/Phone.lua), with
-- src/phone.lua's interface so the Phone window is the same. A call is the game's own, made as the
-- Pokégear's phone card makes it (an off-stack Pokégear, H.gear(): its signal check, the ring, its one-line
-- answers -- no service, out of the area, just go talk to them, a wrong number -- and for a call that goes
-- through, the contact's script run by Game2:runPokegearCall, side effects and all: rematches, gifts, Mom's
-- savings). That script's pages are the game's text boxes, pushed over our window and hidden under it (the
-- shell draws over the game): the live call mirrors the box on top (its visible lines, page by page; a
-- YES / NO box's labels and cursor) for the window to show as bubbles, while the buttons go to the boxes as
-- in the game. A tap stands in for A (deps.tap). The recent calls (30) and the favourites are kept in the
-- save ("phone"), as on Ruby / Sapphire / Emerald.
--
--   Ph = phone(H, deps)   deps: save (mod.save) ; now() ; place(mapId) -> its name ; tap(btn) (the game's
--                         buttons, mod.input) ; notify(kind, data)
--   (the interface: src/phone.lua's) ; Ph.call(s, c) -> text, ok, live
--   live = { text, done, choice (the YES / NO box on top: { labels, index }), step() -> changed, press() }

local KEEP = 30

return function(H, deps)
  deps = deps or {}
  local engine = H.engine
  local Ph = { KEEP = KEEP, store = deps.save, now = deps.now or os.time }
  local loose = nil

  function Ph.family() return "gen2" end
  function Ph.available(s) return H.hasPhone and H.hasPhone(s) or false end

  -- ------- the save's part: recents and favourites (as src/phone.lua)
  local function data()
    local store = Ph.store
    local d = store and store:get("phone") or loose
    if type(d) ~= "table" then
      d = { recents = {}, fav = {} }
      if store then store:set("phone", d) else loose = d end
    end
    d.recents, d.fav = d.recents or {}, d.fav or {}
    return d
  end
  local function saved(d) if Ph.store then Ph.store:set("phone", d) end end
  local function log(name, key, text)
    local d = data()
    table.insert(d.recents, 1, { name = tostring(name or "?"), key = key, text = tostring(text or ""),
                                 at = Ph.now(), incoming = false })
    while #d.recents > KEEP do d.recents[#d.recents] = nil end
    saved(d)
  end
  function Ph.recents() return data().recents end
  function Ph.isFav(_, key) return data().fav[key] == true end
  function Ph.toggleFav(_, key)
    local d = data()
    d.fav[key] = not d.fav[key] or nil
    saved(d)
    return d.fav[key] == true
  end
  function Ph.picture() return nil end

  -- "PROF.ELM" -> "Prof.Elm", "COOLTRAINER" -> "Cooltrainer" (the game's words, in a sentence's case)
  local function titled(s)
    s = tostring(s or "")
    return (s:gsub("(%a)([%w'é]*)", function(a, rest) return a:upper() .. rest:lower() end))
  end
  Ph.titled = titled

  -- ------- the contacts: the phone book's ten slots, the filled ones
  local function game() return H.game() end
  function Ph.contacts(s)
    local Phone = engine("src.core.gen2.Phone")
    local g = game()
    if not (Phone and s) then return {} end
    local okL, list = pcall(Phone.contacts, s)
    if not okL then return {} end
    local d = g and g.data or {}
    local trainers = d.trainers or d.gen2Trainers
    local events = g and g.world and g.world.events
    local out = {}
    for slot, id in ipairs(list) do
      id = tonumber(id) or 0
      local row = id ~= 0 and Phone.CONTACTS[id]
      if row then
        local okN, name, className = pcall(Phone.contactName, id, trainers)
        local okR, ready = pcall(Phone.isReadyForRematch, events, id)
        local place = row.map and deps.place and deps.place(row.map) or ""
        local okD, del = pcall(Phone.canDelete, id)
        out[#out + 1] = { key = "g" .. id, id = id, slot = slot, name = okN and titled(name) or "?",
                          desc = okN and className and titled(className) or "", pic = -1,
                          place = place or "", rematch = okR and ready == true, nearby = false, canCall = true,
                          canDelete = okD and del == true, check = {} }
      end
    end
    return out
  end

  -- ------- a call
  local function liveCall(name, key, gearCall)
    local live = { text = "", done = false, choice = nil }
    local pages, box, page, cur = {}, nil, nil, ""
    local function joined()
      local t = table.concat(pages, "\n\n")
      if cur ~= "" then t = t == "" and cur or (t .. "\n\n" .. cur) end
      return t
    end
    local function commit()
      if cur ~= "" then pages[#pages + 1] = cur end
      cur = ""
    end
    -- (each frame: the box on top, its words so far; the call over once the script is done and nothing of
    -- it is left on the stack)
    function live.step()
      if live.done then return false end
      local g = game()
      local stk = g and g.stack
      local top = stk and stk.top and stk:top() or nil
      local changed = false
      if type(top) == "table" and top.visibleText and top.pages then
        if top ~= box or top.pageIndex ~= page then
          commit()
          box, page = top, top.pageIndex
          changed = true
        end
        -- (the page's lines before the one typing, then what the box shows of it: the box scrolls, the
        -- bubble keeps them)
        local okV, vis = pcall(top.visibleText, top)
        local now = ""
        local pg = type(top.pages) == "table" and top.pages[top.pageIndex]
        local li = tonumber(top.lineIndex) or 1
        if okV and type(vis) == "table" and #vis > 0 then
          local parts = {}
          if type(pg) == "table" then
            for k = 1, li - 1 do if type(pg[k]) == "string" then parts[#parts + 1] = pg[k] end end
          end
          parts[#parts + 1] = tostring(vis[#vis])
          now = table.concat(parts, " ")
        end
        if now ~= cur then cur, changed = now, true end
        if live.choice then live.choice, changed = nil, true end
      elseif type(top) == "table" and top.labels and top.index then
        if live.choice ~= top then live.choice, changed = top, true end
      else
        local vm = g and g.world and g.world.vm
        local okR, running = pcall(vm and vm.running or error, vm)
        if not (okR and running) then
          commit()
          live.done, live.choice, changed = true, nil, true
          log(name, key, joined())
        end
      end
      if changed then live.text = joined() end
      return changed
    end
    -- (a tap on the bubbles: the game's A)
    function live.press(btn)
      if live.done or not deps.tap then return end
      pcall(deps.tap, btn or "a")
    end
    live.kind = gearCall and gearCall.kind
    return live
  end

  -- the game's own call (as the Pokégear's card makes it) -> its first words, true, and a live call when
  -- a script runs; a one-line answer (no service, out of the area ...) is the whole call
  function Ph.call(s, c)
    if not (c and c.canCall and c.id) then return nil, false end
    local gear = H.gear and H.gear()
    if not gear then return nil, false end
    local g = game()
    local ran = false
    gear.onCall = function(call)
      if g and g.runPokegearCall then
        local ok, yes = pcall(g.runPokegearCall, g, call)
        ran = ok and yes == true
      end
      return ran
    end
    gear.call = nil
    local ok, err = pcall(gear.callContact, gear, c.id)
    if not ok then
      if H.log then H.log("the call failed: %s", tostring(err)) end
      return nil, false
    end
    local call = gear.call
    if not call then return nil, false end
    if ran then return "", true, liveCall(c.name, c.key, call) end
    local text = tostring(call.text or "")
    -- (the card's own answer: "NAME: ……" with no script is a call that never connected)
    if text == "" then return nil, false end
    log(c.name, c.key, text)
    return text, true
  end

  -- a contact struck off the phone book (Mom and Prof. Elm can't be)
  function Ph.delete(s, c)
    local Phone = engine("src.core.gen2.Phone")
    if not (Phone and c and c.slot and c.canDelete) then return false end
    local ok = pcall(Phone.deleteContactAt, s, c.slot)
    return ok
  end

  function Ph.incoming() end
  return Ph
end
