-- Notifications: what the apps' models tell the player while they're away from them (outbid on
-- R-Bay, an auction won, lost or nearly over, a GTS deposit traded). Each is kept in a list (the
-- notifications sheet shows it, newest first) and shown once as a banner: over the field while the
-- player is free to move (src/shell.lua draws it from render.hud), or in the desktop's / WoobPad's
-- screen while one is open. A tap on a banner opens that app on WoobPad.
--
--   Nt = notify(deps)  deps: K (the kit) ; T (the words) ; now() -> seconds (the frame clock) ;
--                      epoch() -> seconds (the device's clock) ; se(name) ; monIcon(sp, x, y, size) ;
--                      glyph(G, kind, cx, cy, size, a) (an app's picture, window pixels) ;
--                      apps (src/apps.lua) ; enabled() -> the banners on (the list always keeps them)
--   Nt.push(kind, data, quiet) kind "outbid" | "won" | "lost" | "soon" | "gts" | "call"; data { name, sp, key,
--       where }; quiet: into the list only (the app the player is looking at said so itself)
--   Nt.list() -> the records, newest first: { kind, app, title, text, sp, at, state }
--   Nt.unread() / Nt.seen()
--   Nt.step(clock, canShow) -> the banner showing and how far in (0..1) or nil: banners wait their
--       turn (three at most) until a place can show one
--   Nt.drawCard(rec, b, a) (units, the kit's frame) ; Nt.drawField(G, vp, free, clock) ;
--   Nt.hitField(x, y) -> the record under a tap on the field's banner (it goes) or nil
--   Nt.dismiss() (the banner showing: gone)

local floor, max, min = math.floor, math.max, math.min

local KEEP, WAITING = 20, 3
-- a banner: sliding in, held, sliding out (seconds); one left waiting longer than STALE drops to
-- the list only
local IN, HOLD, OUT, STALE = 0.3, 4, 0.35, 600
local APP = { outbid = "auction", won = "auction", lost = "auction", soon = "auction", gts = "gts", call = "phone" }
local SOUND = { outbid = "SE_FAILURE", won = "SE_SUCCESS", lost = "SE_SELECT", soon = "SE_SELECT", gts = "SE_PC_LOGIN",
                call = "SE_POKENAV_CALL" }
local TEXT = { outbid = "notify.outbid", won = "notify.won", lost = "notify.lost", soon = "notify.soon", gts = "notify.gts",
               call = "notify.call" }
local TITLE = { auction = "app.auction", gts = "app.gts", phone = "app.phone" }
-- the field's banner in the game's own pixels (240 x 160)
local FIELD = { x = 36, y = 4, w = 168, h = 22 }

local NO_T = setmetatable({ f = string.format }, { __call = function(_, k) return k end })

return function(deps)
  deps = deps or {}
  local K, T = deps.K, deps.T or NO_T
  local Nt = { IN = IN, HOLD = HOLD, OUT = OUT, FIELD = FIELD }
  local recs, nUnread = {}, 0
  local queue, nQueue = {}, 0
  local showing, showT = nil, 0
  local fieldHit = { 0, 0, 0, 0 }
  local fieldOn = false

  local function now() return deps.now and deps.now() or 0 end
  local function epoch() return deps.epoch and deps.epoch() or os.time() end
  local function se(name) if deps.se then pcall(deps.se, name) end end

  function Nt.push(kind, data, quiet)
    local app = APP[kind]
    if not app then return nil end
    data = data or {}
    local name = tostring(data.name or "?")
    local key = TEXT[kind]
    if kind == "won" then key = data.where == "pc" and "notify.wonPc" or "notify.won" end
    -- (the second word: the stranger's name, or the minutes left)
    local okT, text = pcall(T.f, key, name, data.minutes or tostring(data.who or ""))
    local rec = { kind = kind, app = app, title = TITLE[app],
                  text = okT and text or name, sp = tonumber(data.sp), at = epoch(), t = now(),
                  state = app == "gts" and { tab = "deposit" } or (app == "phone" and { tab = "recents" })
                    or { tab = (kind == "won" or kind == "lost") and "mine" or "browse", key = data.key } }
    table.insert(recs, 1, rec)
    while #recs > KEEP do recs[#recs] = nil end
    nUnread = nUnread + 1
    local on = deps.enabled == nil or deps.enabled() ~= false
    if on and not quiet then
      if nQueue >= WAITING then
        for i = 1, nQueue - 1 do queue[i] = queue[i + 1] end
        nQueue = nQueue - 1
      end
      nQueue = nQueue + 1
      queue[nQueue] = rec
    end
    return rec
  end
  function Nt.list() return recs end
  function Nt.unread() return nUnread end
  function Nt.seen() nUnread = 0 end
  function Nt.dismiss()
    if showing then showing = nil end
  end
  -- (tests: everything forgotten)
  function Nt.reset()
    for i = #recs, 1, -1 do recs[i] = nil end
    for i = 1, nQueue do queue[i] = nil end
    nUnread, nQueue, showing = 0, 0, nil
  end

  -- the banner showing (and how far it's in: 0..1), starting the next one when a place can show it
  function Nt.step(clock, canShow)
    if showing then
      local age = clock - showT
      if age >= IN + HOLD + OUT or age < 0 then
        showing = nil
      else
        local k = age < IN and age / IN or (age > IN + HOLD and 1 - (age - IN - HOLD) / OUT or 1)
        return showing, k * k * (3 - 2 * k)
      end
    end
    if nQueue == 0 or not canShow then return nil end
    local rec = queue[1]
    for i = 1, nQueue - 1 do queue[i] = queue[i + 1] end
    queue[nQueue] = nil
    nQueue = nQueue - 1
    if clock - rec.t > STALE then return Nt.step(clock, canShow) end
    showing, showT = rec, clock
    se(SOUND[rec.kind])
    return rec, 0
  end
  function Nt.showing() return showing end
  function Nt.waiting() return nQueue end

  -- a notification's card (units, in the frame the kit has): the app's round icon, its name and
  -- "now", the line, the Pokémon's icon at the right
  local INK, SOFT, CARD, EDGE = { 255, 255, 255 }, { 170, 172, 184 }, { 30, 31, 38 }, { 255, 255, 255, 0.1 }
  function Nt.drawCard(rec, b, a, when)
    a = a or 1
    local G = K.graphics()
    local rad = min(b[4] / 2, 6)
    K.shadow(b, rad, 1.2, 0.35 * a)
    K.col(CARD, 0.96 * a)
    K.box("fill", b, rad)
    K.ring(b, rad, EDGE, a, 0.4)
    local app = deps.apps and deps.apps.byId(rec.app)
    local s = b[4] - 8
    local cx, cy = b[1] + 4 + s / 2, b[2] + b[4] / 2
    if app then
      K.col(app.color, a)
      G.circle("fill", K.X(cx), K.Y(cy), s / 2 * K.sc)
      if deps.glyph then pcall(deps.glyph, G, app.glyph, K.X(cx), K.Y(cy), s * K.sc, a, app.color) end
    end
    local tx = b[1] + 8 + s
    local right = b[1] + b[3] - (rec.sp and (b[4] + 1) or 5)
    local ts = min(4.2, b[4] * 0.2)
    K.bold(T(rec.title), tx, b[2] + 3, ts, SOFT, nil, nil, a)
    K.text(when or T("notify.now"), tx, b[2] + 3, ts, SOFT, "right", right - tx, a)
    local fs = K.fit(rec.text, min(5, b[4] * 0.24), right - tx)
    K.text(rec.text, tx, b[2] + b[4] - fs * 1.25 - 3, fs, INK, nil, nil, a)
    if rec.sp and deps.monIcon then deps.monIcon(rec.sp, b[1] + b[3] - b[4] + 1, b[2] + 1, b[4] - 2) end
  end

  -- over the field: the banner sliding down from the top of the game's picture
  function Nt.drawField(G, vp, free, clock)
    fieldOn = false
    local rec, k = Nt.step(clock, free)
    if not rec then return false end
    local scale = tonumber(vp.scale) or ((tonumber(vp.gameWidth) or 240) / 240)
    K.place(G, tonumber(vp.gameX) or 0, tonumber(vp.gameY) or 0, scale, clock)
    local y = FIELD.y - (1 - k) * (FIELD.h + FIELD.y + 2)
    local b = K.R(FIELD.x, y, FIELD.w, FIELD.h)
    Nt.drawCard(rec, b, min(1, k * 1.5))
    fieldHit[1], fieldHit[2], fieldHit[3], fieldHit[4] = K.X(b[1]), K.Y(b[2]), b[3] * K.sc, b[4] * K.sc
    fieldOn = true
    G.setColor(1, 1, 1, 1)
    return true
  end
  -- (tests: where the field's banner is, window pixels, while it shows)
  function Nt.fieldRect() return fieldOn and showing and fieldHit or nil end
  function Nt.hitField(x, y)
    if not (fieldOn and showing) then return nil end
    if not K.inside(fieldHit, x, y) then return nil end
    local rec = showing
    showing, fieldOn = nil, false
    return rec
  end

  -- "5m ago" and the like, for the notifications' list (kept per value)
  local agoText = K.textCache(function(m)
    if m < 1 then return T("notify.now") end
    if m < 60 then return T.f("notify.minutes", m) end
    if m < 1440 then return T.f("notify.hours", floor(m / 60)) end
    return T.f("notify.days", floor(m / 1440))
  end)
  function Nt.ago(rec)
    local m = max(0, floor((epoch() - (rec.at or 0)) / 60))
    if m >= 1440 then m = floor(m / 1440) * 1440 elseif m >= 60 then m = floor(m / 60) * 60 end
    return agoText(m)
  end

  return Nt
end
