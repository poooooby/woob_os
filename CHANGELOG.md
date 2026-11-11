# Changelog

All notable changes to this mod are documented here, in
[keep a changelog](https://keepachangelog.com/en/1.1.0/) format.

## [Unreleased]

## [0.9.2] - 2026-11-11

### Added
- **News:** Rookie Watch, sports-style coverage of you as a rookie on the rise, newest first: your
  latest Gym (the score, the turns and a play-by-play of every knockout, turn by turn, to the
  finishing blow), your last two trainers beaten (the score, where, both teams and the finisher), your
  latest catch as a signing (where, the level, the Ball) and your week. A story longer than its panel
  follows the words as they type, then scrolls with Up / Down, a drag or the wheel.

### Changed
- **News:** trainers beaten and new Badges are told in the Gym's and the matches' stories rather
  than as one-line moments.

### Fixed
- **Slots:** the reels no longer stutter the first time two Bonus land and the notes climb, nor the
  first time a win's fanfare plays: the machine's sounds are ready as it opens.

## [0.9.1] - 2026-11-11

### Added
- **Settings > Notifications:** a switch for each app that sends notifications (R-Bay, the GTS, the
  Phone on Emerald, the Bank, Errands, Challenges and the News), with the banners switch and R-Bay's
  ending-soon alert alongside. An app switched off sends nothing, not even to the list.

## [0.9.0] - 2026-11-11

### Added
- **Weather on the 3D map (Ruby, Sapphire, Emerald):** each place's everyday weather where the game
  puts it, quieter than the legendary storms: rain clouds and rain, a thunderstorm, falling ash, a
  dust haze over the desert, fog, shade and a few clouds. Route 119's and Route 123's change with the
  game's daily weather. A place's card names its weather.

### Fixed
- **The 3D map's roofs** no longer flicker against their buildings: the Gym's top and the houses',
  Centers' and Marts' eaves.

## [0.8.0] - 2026-11-11

### Added
- **Bank:** a savings account beside your wallet. Money that a full wallet (₽999,999) can't hold goes
  into the bank, up to ₽999,999,999, instead of being lost. Deposit, withdraw, and earn a little
  interest each day.
- **Errands:** send teams of up to three Pokémon on real-time jobs (one, four or eight hours). They
  come back with money, an item and EXP; a team whose types and levels suit the job earns more.
- **Challenges:** five goals a week from real play (battles, catches, Eggs, evolutions, steps,
  places and more), each paying money or items, with a bonus for all five.
- **News:** the day's stories read by the WoobOS News anchor in a TV close-up, talking as the words
  type out: a real daily swarm (one species all over one route), the region's events, R-Bay's
  hottest auction, and what you've done since you last watched.
- **Settings > Gameplay:** daily swarms on or off.

### Changed
- **The Mart** is a shopfront: your game's own Mart clerk behind the counter under a striped awning,
  talking in a speech bubble (a greeting, a word on each purchase and sale, why not when you can't,
  what your latest Badge brought, a tip now and then). Tabs along the list, the chosen item on a lit
  stand, coins flying into and out of the till, and a NEW tag on what a Badge added.
- **The notifications drawer** (PC and WoobPad) follows your finger down from the top of the screen
  over frosted glass, the screen blurred behind it, with the time at its top. Swipe a notification
  left or right to clear it, or Clear to clear them all; push it back up by its handle. Pulling it
  down works on the PC too.
- **The Phone (Emerald):** every contact has a picture. Mom, Scott and Mr. Stone have original
  sprites by Wooble, and Prof. Birch appears as the game's opening shows him.
- **Phone calls (Emerald)** read like a chat: the caller's picture, name and a running timer in a
  header, their words in message bubbles that type themselves out after a "…" bubble (A shows the
  rest at once), a waveform while they talk, and a round red button to hang up.

## [0.7.3] - 2026-11-10

### Fixed
- **Scrolling lists by finger, mouse drag or wheel** stays where you put it, instead of snapping back to
  the chosen row: R-Bay, the Mart, Items, Mail, Slots' prizes, the Phone, Condition and Ribbons.

## [0.7.2] - 2026-11-09

### Fixed
- **Kanto Gear apps on Android's second screen** (Ayn Thor and the like) no longer come out smeared,
  and fill the screen from top to bottom.

## [0.7.1] - 2026-11-09

### Changed
- **Slots:** more free spins: 12, 18 or 30 for three, four or five Bonus coins (was 10, 15 or 25). The
  machine pays back about 96%, up from about 91%.

## [0.7.0] - 2026-11-09

### Added
- **Kanto Gear apps:** Slots, R-Bay and the GTS are in its Silph Store, each opening from its own tile
  and staying on the Gear's second screen with the game still running. They wait while the game is in
  a battle, a menu or a conversation.
- **App Store:** add or remove R-Bay, Slots, the GTS, the Mart, PC Games and any app another mod adds.
  A removed app leaves the home screen and WoobPad, keeps what it saved, and returns to its old
  place when you get it back. The game's PC and PokéNav apps always stay.
- **App icons for other mods:** 33 pictures to choose from (a controller, a flame, a Poké Ball, a
  Pokédollar sign and more), on a tile in any colour. `exports.apps.icons()` lists them; DEVELOPMENT.md
  shows how to add an app.

### Changed
- **`exports.apps.register`** refuses an icon that isn't in the set or a colour that isn't 0..255,
  and says why in its result and the log, instead of showing a blank tile.

## [0.6.0] - 2026-11-09

### Changed
- **Slots is a five-reel video slot:** a new look (a dark stage, wide reels, a pay ladder, a round
  SPIN button, a BALANCE / WIN / BET bar, full-window big wins), 1 / 5 / 10 / 20 lines, and three,
  four or five of a kind from the left. The return stays about 91%.
- **The 3D map's clouds** are rounded and lit: bright tops, shaded flat bases, tinted by dusk and
  night, and they grow in and fade out at the map's edges.
- **The PokéNav's Hoenn Map, Ribbons and Condition search** open WoobOS's apps.
- **WoobPad's START row** sits under BAG before you have the PokéNav (and on FireRed / LeafGreen),
  instead of at the bottom.
- **Decorate** is a WoobOS window: a catalogue of your decorations by category, with Put Away and
  Toss in it. Placing a doll or cushion still uses the game's cursor in your room, and brings you
  back to the catalogue.

### Added
- **Legendary storms on the 3D map** (Emerald): once the Weather Institute has told you where the
  abnormal weather is, a rainstorm hangs over Kyogre's route or a sandstorm over Groudon's. It follows
  each new report and clears when that Pokémon is caught or knocked out.
- **Ribbons app** (Ruby / Sapphire / Emerald): every Pokémon with Ribbons, what each one is for.
- **Hall of Fame app:** your champion teams as a trophy case, on the desktop and WoobPad.
- **Oak's PC app** (FireRed / LeafGreen): the Kanto Pokédex's counts and Oak's rating, also on WoobPad.
- **PC Games app:** with the PC Games mod installed, its games fill the screen of the desktop and
  WoobPad, at a whole-pixel size.
- **Slots:** Ditto is wild; Bonus coins pay anywhere and give 10, 15 or 25 free spins with wins
  tripled; Auto (SELECT).

### Removed
- **Slots:** the lever, and Pikachu paying on the first reels alone.
- **WoobPad's PokéNav app:** the Map, Phone, Condition and Ribbons apps do its jobs.

## [0.5.3] - 2026-11-07

### Added
- **Shinies sparkle in Boxes:** a gold sparkle on a shiny's icon in the box grid, in the party and
  while it's carried (the game's icons have no shiny colours).

## [0.5.2] - 2026-11-07

### Changed
- **WoobPad takes the PokéNav's START row** (Ruby / Sapphire / Emerald): the PokéNav is an app on
  the pad instead, the game's own (Ribbons and the rest; Match Call and Condition open ours); the
  pad comes back when it closes.

## [0.5.1] - 2026-11-07

### Added
- **Options:** Map: Invert X and Map: Invert Y, for the 3D map's camera (the right stick and a
  drag).

### Changed
- **About** is only in the W menu now (top left), no longer an app on the home screen.

### Fixed
- **Phone:** its icon is a handset; the favourites' star is a star; a contact's Call and ★ only
  show the controller's ring once its card is open.

## [0.5.0] - 2026-11-07

### Changed
- **WoobPad** in place of WoobWatch: the PC as a tablet from the START menu (WOOBPAD), with a big
  touch screen. The PC's own home screen, dock, menu bar and app windows, at the PC's size, over the
  game; no boot. Notifications: pull down from the top, or the W menu's Notifications (the PC's
  W menu has it too). B on the home screen puts it away.

### Added
- **The 3D map:** a free cursor (the D-pad moves it over the land; let go near a town or a
  landmark and it glides onto it; routes get their card too), the right stick turns and tilts the
  camera, and a flat map (SELECT or the 2D / 3D button: the game's own Town Map picture, north up).
- **Phone** (Ruby / Sapphire / Emerald): the PokéNav's contacts as a phone, with Favourites,
  Recents and Contacts tabs, a Rematch filter, and cards with pictures and profiles. Emerald's calls
  are the game's own (its words, rematch requests); the field's calls ring as a notification and
  land in Recents. Ruby / Sapphire: Trainer's Eyes' Trainers and their rematches.
- **Condition** (Ruby / Sapphire / Emerald): the contest conditions as a radar chart (sheen,
  nature, ribbons), Search across the party and boxes, Compare, and feeding Pokéblocks with the
  game's rules.
- **The PokéNav:** Match Call (Trainer's Eyes) and Condition open the Phone and Condition; B goes
  back to the PokéNav. Settings > PokéNav keeps its own screens.

## [0.4.0] - 2026-11-07

### Added
- **A 3D Town Map:** the Town Map, the wall maps and the Fly map show the region as a 3D model
  made from the game's own Town Map: hills, forests, the sea, the routes, towns of little houses
  (Pokémon Centers, Marts, Gyms) and mountains, with waves, drifting clouds and day, dusk and night
  from the device's clock. A beacon shows where you are; the D-pad hops between places, each
  with a card (visited, Center, Mart, the Gym and its badge); Fly flies there. L / R turn, A
  zooms, a drag turns and tilts, a pinch or the wheel zooms. The Sevii Islands on FireRed /
  LeafGreen (SELECT). START opens the game's own map.
- **Map app:** the same 3D map on the desktop and WoobWatch. On the watch, outdoors, it flies you
  to a visited town (a Pokémon that knows Fly and the badge needed).
- **Settings > Map:** the 3D Town Map on or off.
- **The 3D map's towns:** each its own. A village's few houses, a city's taller blocks; roofs in
  the town's colour; the places they're known for (Oak's lab, Pewter's museum, the Pokémon Tower,
  Silph Co., the S.S. Anne, the League, Devon's tower, Mauville's dome, Mossdeep's rocket,
  Fortree's tree houses, Pacifidlog on the water …); a Gym's band in its badge's colour.
- **The 3D map's look:** frosted glass under its cards, buttons and hints, and a compass (tap it:
  north up).

## [0.3.2] - 2026-11-06

### Added
- **Shiny Pokémon on R-Bay and the GTS:** about one in ten auctions, GTS listings, Wonder Trades
  and deposit answers is shiny, with a gold Shiny badge and its shiny colours. A shiny auction is
  worth far more, draws more and keener bidders and is almost always the Hot Auction; what you
  win or receive is that shiny.

### Fixed
- **R-Bay and the GTS:** the Pokémon's pictures show their normal colours. They showed the shiny
  ones (a species with no Pokémon behind it read as shiny), while what you got was normal. A
  Pokémon that really is shiny (yours in the GTS's picker, the one Wonder Trade brings) shows as
  shiny.

## [0.3.1] - 2026-11-06

### Added
- **Settings > Watch:** the ending-soon alert: 5, 10, 15 or 30 minutes before an auction ends.

### Changed
- **WoobWatch:** the face shows the wallpaper chosen in Settings. A swipe down opens the
  notifications, a swipe up goes back to the face.
- **WoobWatch:** the apps are drawn at a watch's size: half as large again as on the PC, with
  fewer, bigger rows, text and buttons, on the windows' light grey. The GTS's Wonder Trade card and
  R-Bay keep only what fits (R-Bay's Hot Auction stays one SELECT away).

## [0.3.0] - 2026-11-06

### Added
- **WoobWatch:** the PC's apps on a smartwatch, from a WATCH row in the START menu, anywhere you
  can open it. A face with the time, your money, your party and tiles for R-Bay, the GTS, Slots
  and the Mart; the apps in a honeycomb (L / R turn the crown); Boxes, Items, Mail, GTS, Mart,
  R-Bay, Slots and Settings all on the watch.
- **Notifications:** outbid on R-Bay, an auction with ten minutes left, won or lost, a GTS
  deposit traded. A banner over the game while you're free to move (tap it to open that app on
  the watch), over the PC's or the watch's screen while one is open, and a list on the watch.
- **Settings > Watch:** the START menu's row and the banners, each on or off.

### Changed
- R-Bay and the GTS settle while you play, not only while the PC is open.

### Fixed
- **R-Bay:** outbid, your money comes back at once (it was held until the auction ended), and
  the rival's answer shows as the new top bid.
- **R-Bay:** on a phone (and the watch), the Hot Auction's price sits at the right under its tag,
  clear of the tier badge.

## [0.2.3] - 2026-11-02

### Fixed
- **Items:** sorting works on the Bag too. START (or the Sort button on the Bag's side) sorts the
  pocket by name or by type; the TM Case and the Berries keep the game's own order.
- **Boxes:** Swap mode swaps. A Pokémon put down on another trades places with it (party or box),
  instead of picking the other one up.
- **R-Bay:** in portrait, the chosen auction shows everything: its types, IVs and the last bids.

### Changed
- **Boxes:** the pad's Poké Ball glows red while you carry a Pokémon and flashes green when you
  put it down, instead of a Poké Ball materializing on the pad for each move.

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
