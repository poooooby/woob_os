-- Slots, R-Bay and the GTS as Kanto Gear apps, through the hook Kanto Gear offers other mods
-- (exports.modules, api 1). Each is a tile with its own Silph Store listing and opens straight into
-- that app; the full-screen host is the shell's (Sh.openFromGear). Separate from the App Store: the
-- Silph Store says what's on the Gear, the App Store what's on the WoobOS home screen.
--
--   Gear = KantoGear(deps)   deps: find(id) -> mod.find's handle ; open(appId) -> true when it took the
--                            screen ; shown(appId) ; color(appId) -> { r, g, b } ; glyph(G, kind, cx, cy,
--                            size, a, tile) ; log(fmt, ...)
--   Gear.bind()      (game.ready: at most once, and only if Kanto Gear's there)
--   Gear.specs       what was handed over ; Gear.results[id] = true | the reason it was refused
--   Gear.find        where the hook is looked up (a test swaps it)

local APPS = {
  { app = "slots", id = "woob_slots", label = "ROCKET SLOTS", accent = "amber", glyph = "slots",
    lines = { "FIVE REELS, WILDS AND FREE SPINS.", "WIN TICKETS FOR THE PRIZE CORNER." },
    words = {
      de = { "FÜNF WALZEN, WILDS UND FREISPIELE.", "GEWINNE TICKETS FÜR DIE PREISECKE." },
      es = { "CINCO RODILLOS, COMODINES Y GIROS GRATIS.", "GANA FICHAS PARA EL RINCÓN DE PREMIOS." },
      fr = { "CINQ ROULEAUX, JOKERS ET TOURS GRATUITS.", "GAGNEZ DES TICKETS POUR LES LOTS." },
      it = { "CINQUE RULLI, JOLLY E GIRI GRATIS.", "VINCI BIGLIETTI PER L'ANGOLO PREMI." },
      ja = { "5リール ワイルド フリースピン", "チケットを あつめて けいひんと こうかん" },
    } },
  { app = "auction", id = "woob_rbay", label = "R-BAY", accent = "red", glyph = "rocket",
    lines = { "TEAM ROCKET'S POKÉMON AUCTIONS.", "BID AGAINST OTHER TRAINERS." },
    words = {
      de = { "TEAM ROCKETS POKÉMON-AUKTIONEN.", "BIETE GEGEN ANDERE TRAINER." },
      es = { "LAS SUBASTAS DEL TEAM ROCKET.", "PUJA CONTRA OTROS ENTRENADORES." },
      fr = { "LES ENCHÈRES DE LA TEAM ROCKET.", "ENCHÉRISSEZ CONTRE D'AUTRES DRESSEURS." },
      it = { "LE ASTE DEL TEAM ROCKET.", "FAI OFFERTE CONTRO ALTRI ALLENATORI." },
      ja = { "ロケットだんの オークション", "ほかの トレーナーと きそって おとす" },
    } },
  { app = "gts", id = "woob_gts", label = "GTS", accent = "blue", glyph = "globe",
    lines = { "WONDER TRADE AND TRADE LISTINGS", "WITH TRAINERS AROUND THE WORLD." },
    words = {
      de = { "WUNDERTAUSCH UND TAUSCHANGEBOTE", "MIT TRAINERN AUS ALLER WELT." },
      es = { "INTERCAMBIO MILAGRO Y ANUNCIOS", "CON ENTRENADORES DE TODO EL MUNDO." },
      fr = { "ÉCHANGE MIRACLE ET OFFRES", "AVEC DES DRESSEURS DU MONDE ENTIER." },
      it = { "SCAMBIO PRODIGIOSO E ANNUNCI", "CON ALLENATORI DI TUTTO IL MONDO." },
      ja = { "ミラクルこうかんと こうかんリスト", "せかいじゅうの トレーナーと" },
    } },
}
local GREY = { 128, 132, 140 }

return function(deps)
  local Gear = { specs = {}, results = {}, find = deps.find }
  local bound = false

  local function specOf(it)
    local translations = {}
    for code, lines in pairs(it.words) do
      translations[code] = { [it.lines[1]] = lines[1], [it.lines[2]] = lines[2] }
    end
    return {
      id = it.id, label = it.label, category = "GAMES", accent = it.accent,
      description = { it.lines[1], it.lines[2] },
      translations = translations,
      icon = function(x, y, grey)
        local G = love.graphics
        local tile = grey and GREY or deps.color(it.app) or GREY
        G.setColor(tile[1] / 255, tile[2] / 255, tile[3] / 255, 1)
        G.rectangle("fill", x, y, 24, 24, 5, 5)
        deps.glyph(G, it.glyph, x + 12, y + 12, 24, 1, tile)
        G.setColor(1, 1, 1, 1)
      end,
      available = function(ctx) return ctx ~= nil and ctx.generation == 3 end,
      shown = function() return deps.shown(it.app) == true end,
      open = function() return deps.open(it.app) == true end,
    }
  end

  function Gear.bind()
    if bound then return end
    local handle = Gear.find and Gear.find("kanto_gear")
    local modules = handle and handle.exports and handle.exports.modules
    if not (modules and modules.api == 1 and type(modules.register) == "function") then return end
    bound = true
    for _, it in ipairs(APPS) do
      local spec = specOf(it)
      Gear.specs[#Gear.specs + 1] = spec
      local ok, accepted, why = pcall(modules.register, spec)
      if ok and accepted then
        Gear.results[it.id] = true
      else
        local reason = tostring(ok and why or accepted)
        Gear.results[it.id] = reason
        if deps.log then deps.log("Kanto Gear refused %s: %s", it.id, reason) end
      end
    end
  end

  return Gear
end
