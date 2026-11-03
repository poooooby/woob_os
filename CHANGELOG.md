# Changelog

All notable changes to this mod are documented here, in
[keep a changelog](https://keepachangelog.com/en/1.1.0/) format.

## [0.2.2] - 2026-11-02

### Fixed
- **Slots:** the pay table's Pikachu rows say where Pikachu pays: on the first reel, or the
  first two (it pays only from the left).

## [0.2.1] - 2026-11-02

### Added
- **Slots: more lines.** Play one, three or five lines (Up / Down, or the LINES button): the
  middle row, the top and bottom rows, both diagonals, each line its own bet. Every line pays the
  same share back; the winning ones glow after the banner.

## [0.2.0] - 2026-11-02

### Added
- **GTS.** Wonder Trade (send one, get a surprise back from a Trainer somewhere in the world:
  a globe search, the Poké Balls swapping on the pad, the reveal) and the Global Trade Station
  (Trainers' listings every half hour; deposit one of yours asking for a species and level,
  answered in real time when the ask is fair). Received Pokémon are traded ones (their own OT:
  more EXP, obedience by badges) and trade evolutions play the game's own scene. A deposit is kept
  in the save.
- **Slots.** Team Rocket's slot machine, played with money (₽50 to ₽1,000 a spin): three reels,
  three of a kind on the line pays up to the 500× Rocket jackpot, about 92% paid back over time.
  The rarer wins drop Rocket Tickets for the prize corner: items, TMs, a Master Ball and six
  Pokémon (their level grows with your badges), delivered onto the pad. Tickets are kept in the
  save. The machine puts on a show: a pull-lever, reels that flash as they land, the last reel
  held back when two match, tiered win banners with coin showers and a count-up, tickets flying
  to their counter; prizes by rarity with a progress bar and confetti.
- **R-Bay.** Team Rocket's auction house for Pokémon: twelve three-hour auctions at a time on
  the device's clock, a new one every fifteen minutes. Six tiers from Common to Mythical
  (WoobleDex's Pokémon too), levels that climb with your badges, IVs shown on each listing and
  reflected in the bidding. Rocket bidders compete (keener in the higher tiers); you set your
  maximum and R-Bay bids for you. The maximum is held, a win returns the change and sends the
  Pokémon to the party or the PC with its listed IVs, a loss refunds it all. My Bids, and a count
  on the icon when an auction ends. Bids and results are kept in the save. The Hot Auction card
  spotlights the most wanted listing (SELECT jumps to it); prices flash up on new bids, the last
  ten minutes pulse red, taking the lead throws confetti, and losing it is announced.
- **Mart.** A Poké Mart on the desktop: Poké Balls, medicine, battle items and Repels bought
  straight into the Bag, more of them with each Gym Badge (locked ones say how many badges they
  need). A purchase appears on the pad and goes up into the Bag; Sell takes the Bag's items for
  half their price, and they leave off the pad. Ten Poké Balls at once come with a Premier Ball.
  Prices and names are the game's own.

### Fixed
- **Boxes with WoobleDex's Bigger PC.** All 40 boxes show (L and R go on past box 14), not only
  the first 14; the GTS looks through all of them too.

## [0.1.1] - 2026-11-01

### Changed
- **Items: how many.** Left and Right change it by one, Up and Down by ten (they were the other
  way round).

### Fixed
- **Items from other mods have their pictures.** WoobDex's Exp. Candies, Dynamax Candy, Max
  Mushrooms and the rest showed blank in Items and on the pad: the icon now comes from the Bag's
  own drawing, which those mods add their art to (painted once and kept).

## [0.1.0] - 2026-11-01

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
