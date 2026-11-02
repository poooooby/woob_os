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
}
