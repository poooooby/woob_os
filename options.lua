-- Mod Manager option schema for woob_os.
-- Labels are limited to 14 characters.

return {
  {
    key = "desktop",
    label = "Desktop",
    type = "toggle",
    default = true,
    description = "The PC opens the WoobOS desktop. Off: the game's own PC menu.",
  },
  {
    key = "boot",
    label = "Boot Screen",
    type = "toggle",
    default = true,
    description = "The PC boots with the W logo before the desktop appears. Any button or a tap skips it.",
  },
  {
    key = "clock24",
    label = "24-Hour Clock",
    type = "toggle",
    default = false,
    description = "The menu bar's clock in 24-hour time (15:30) instead of 3:30 PM.",
  },
  {
    key = "textSize",
    label = "Text Size",
    type = "choice",
    default = 100,
    choices = { { "Normal", 100 }, { "Large", 115 }, { "Larger", 130 } },
    description = "Bigger text in every WoobOS app. Words that don't fit get a little smaller to stay in place. Also in Settings > Display.",
  },
  {
    key = "pokedex",
    label = "Pokédex",
    type = "toggle",
    default = true,
    description = "WoobOS's modern Pokédex, from the START menu and as an app on the PC and WoobPad. Off: the game's own Pokédex, and no app.",
  },
  {
    key = "pokegear",
    label = "Pokégear",
    type = "toggle",
    default = true,
    description = "Gold, Silver and Crystal: WoobPad takes the Pokégear's place in the START menu, and its Map, Phone and Radio do the Pokégear's jobs (Fly and the wall maps open the 3D map). Off: the game's own Pokégear.",
  },
  {
    key = "realShops",
    label = "Real Shops",
    type = "toggle",
    default = true,
    description = "Every shop counter opens the WoobOS Mart full screen, with that shop's own goods and look. Off: the game's own shop menus.",
  },
  {
    key = "pokecenter",
    label = "Pokémon Center",
    type = "toggle",
    default = true,
    description = "The nurse's counter opens a close-up of the nurse, and your team heals in the healing machine. Off: the game's own nurse.",
  },
  {
    key = "mapInvertX",
    label = "Map: Invert X",
    type = "toggle",
    default = false,
    description = "The 3D map's camera turns the other way with the right stick and a drag.",
  },
  {
    key = "mapInvertY",
    label = "Map: Invert Y",
    type = "toggle",
    default = false,
    description = "The 3D map's camera tilts the other way with the right stick and a drag.",
  },
}
