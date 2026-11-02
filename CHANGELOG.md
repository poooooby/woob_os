# Changelog

All notable changes to this mod are documented here, in
[keep a changelog](https://keepachangelog.com/en/1.1.0/) format.

## [Unreleased]

### Changed

- **Renamed WoobOS** (mod id `woob_os`), from WoobleOS (`wooble_os`).

### Added
- **Arrange the desktop.** A long press on an app (or SELECT) and the icons wiggle: drag one
  between the home screen and the dock (up to six there), or carry it with A and the D-pad. Held
  at the grid's edge it turns the page. Done, B or a tap on nothing ends it; the arrangement is
  kept in the installation's settings for every PC (an app a PC doesn't show keeps its place).
- **A macOS / iOS look for every window.** A toolbar with the red, yellow and green lights; white
  cards on a soft grey; segmented switches (Bag | PC, Inbox | Held, Fill | Stretch); chevrons;
  hairline separators; capsule buttons with a blue focus ring for the controller; popover menus
  and alerts for the sheets; a System Settings sidebar.

- **The PC as a desktop.** Every Pokémon Center PC and the bedroom PC open a desktop in a monitor:
  a boot screen with the W, a home screen of apps, a dock and a menu bar with your name, money and
  the time. Boxes, Oak's PC and Hall of Fame open the game's own screens and come back to the
  desktop; About; Log Off (B or the power button asks first). Buttons, touch and the mouse all
  work, and the layout fits wide, small and upright windows. The game's "booted up the PC" and
  "Which PC should be accessed?" lines are skipped (the boot does their job); the boot's loading
  bar fills before the desktop fades up.
- **Boxes:** the Pokémon Storage System as our own window.
  - The party, any of the 14 boxes, and a preview of the Pokémon under the cursor (with WoobleDex: its Dynamax Level as a gauge and a G-Max badge for the Gigantamax Factor).
  - Three cursor modes on SELECT or their icons under the box: Select (options: Move, Summary, Item, Release), Swap (pick up and put down; drag and drop with the pointer) and Drag (a rectangle of Pokémon moved together, keeping its shape).
  - The box menu: Jump, Rename (the game's naming screen) and Wallpaper (the game's wallpapers).
  - The Summary and naming screens come back to the window as it was.
  - The game's rules hold on all five games, and a Pokémon crossing between the party and a box shows as a Poké Ball on the pad.
- FireRed / LeafGreen's Help no longer opens on L / R while the desktop is up.
- **Items:** the Bag and the PC's item storage side by side in a window: move items across (how
  many, or SELECT for the whole stack), Bag pockets on L / R, sort the PC by name or pocket, toss.
  Important items stay in the Bag.
- **A shelf under the monitor,** with a digitization pad in its middle:
  - It lights up while Items is open.
  - It shows each item crossing: dropping onto it and digitizing away into the PC, or digitizing in and fading into the Bag.
  - Opening Boxes drops a Poké Ball onto it (with a bounce), and its button slowly glows red while Boxes is open; closing Boxes flashes the button green and lifts the ball off. It sinks into the pad while a Pokémon crosses.
- **Mail:** the mailbox as an inbox: read a letter, move it to the Bag, give it to a Pokémon; a
  Held folder for the party's mail, with Take. FireRed and LeafGreen included.
- **Decorate** on Ruby, Sapphire and Emerald's bedroom PC: the game's Decoration menu.
- **Settings:** Language (English, French, German, Spanish, Italian, Japanese, Brazilian
  Portuguese; one editable `lang/*.lua` each, and any a player adds; kana and CJK drawn with the
  engine's Plain Pixel face) and Wallpaper (the classic colours, five drawn wallpapers tinted
  per game, and the pictures in `wallpapers/`, shown Fill or Stretch). Kept for the installation.
- Options: Desktop (on), Boot Screen (on), 24-Hour Clock (off).
- An app registry other mods can add to (`exports.apps.register`).
