<div align="center">

# WoobOS 🖥️

*The PC as a modern desktop. Boot it up, tap an app, and get on with your Pokémon.*

</div>

A mod for [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp)'s Generation 3 games: FireRed,
LeafGreen, Ruby, Sapphire and Emerald. Every PC in a Pokémon Center, and the one in your bedroom,
opens a desktop in a sleek monitor instead of a text menu.

## ✨ Features

### Core Mechanics

- 🖥️ **A desktop in a monitor:** an aluminium screen with a black glass border, a home screen of
  app icons, a dock along the bottom and a menu bar along the top showing your name, your money
  and the time.
- 🧲 **A shelf under the monitor:** a digitization pad in its middle. Open Boxes and a Poké Ball
  drops onto the pad, its button slowly glowing red; close it and the button flashes green before
  the ball lifts off. The pad lights up while Items is open. An item you send to the PC drops onto
  it and digitizes away, and an item you take out digitizes onto it before fading into your Bag.
- ⚡ **A boot screen:** the PC starts up with the W logo and a loading bar before the desktop fades
  in. Any button or a tap skips it, and it only plays when you first turn the PC on.
- 🎮 **Made for controllers and touch:** move between icons with the D-pad, open with A, flip
  pages with L and R, and press START for the W menu. On a touch screen, tap an icon or swipe
  between pages. A mouse works too: click, hover and scroll.
- 🗂️ **Arrange your apps:** press and hold an app (or press SELECT) and the icons wiggle. Drag an
  app to a new place, from the home screen into the dock or back out again; with a controller,
  A picks it up, the D-pad carries it and A puts it down. The dock holds up to six. Done, B or a
  tap on an empty spot finishes, and every PC remembers the arrangement.
- 📐 **Fits your screen:** wide windows, small windows and phones held upright all get a layout of
  their own.

### Apps

- 🎒 **Items:** your Bag and your PC's item storage side by side. Pick an item and send it across:
  choose how many, or press SELECT to move the whole stack. L and R flip through the Bag's
  pockets, and START sorts the PC by name or pocket or tosses an item. Important items stay in
  the Bag.
- ✉️ **Mail:** your mailbox as an inbox. Read each letter on its own stationery, move it to the
  Bag, or give it to a Pokémon in your party. The Held folder shows the mail your Pokémon are
  carrying, and Take files a letter back in the inbox. Works in all five games.
- 🔴 **Boxes:** the Pokémon Storage System in one window: your party on the left, a box in the
  middle (L and R go through all 14), and the Pokémon under the cursor on the right, with its
  picture, types, nature, ability, item and moves. With WoobleDex, its Dynamax Level shows as a
  gauge of ten, and a G-Max badge marks a Pokémon with the Gigantamax Factor. Three cursor modes, switched with SELECT or a
  tap on their icons under the box:
  - **Select** (red): A opens a Pokémon's options: Move, Summary, Item (take it to the Bag or give
    one) and Release. A on the box's name, or START, jumps to a box, renames it or changes its
    wallpaper.
  - **Swap** (blue): A picks a Pokémon up and A puts it down, swapping with whoever is there. With
    the mouse or a finger, drag it onto its new place.
  - **Drag** (green): hold A and move to draw a rectangle (or drag one out), let go, and every
    Pokémon in it moves together. They keep their shape in the new box.

  A Pokémon going between your party and a box crosses the pad as a Poké Ball. Holding a carried
  Pokémon over the box's arrows turns the box.
- 📟 **Oak's PC:** your Pokédex rating, once you have the Pokédex (FireRed and LeafGreen).
- 🏆 **Hall of Fame:** your champion teams, once you've beaten the Elite Four.
- 🛋️ **Decorate:** your room's decorations, from the bedroom PC (Ruby, Sapphire and Emerald).
- ⚙️ **Settings:** like a phone's or a Mac's.
  - 🌐 **Language:** WoobOS in English, Français, Deutsch, Español, Italiano, 日本語 or
    Português (Brasil). The game's own text, such as item names and mail, stays as it is.
  - 🖼️ **Wallpaper:** the classic colours of your game, five drawn wallpapers (Ribbon, Hills,
    Coast, Waves and Bloom, each tinted to your game), or your own pictures.
- ℹ️ **About:** which version you're running.
- ⏻ **Log Off:** turns the PC off. B, or the power button under the screen, asks first.

Boxes, Items, Mail and Settings open in a window on the desktop, in the style of macOS and iOS:
white cards on a soft grey, segmented switches, and a blue ring round whatever the controller is
on. B or the red button closes it. Oak's PC,
Hall of Fame and Decorate open the game's own screens, and closing them brings you back to the
desktop.

## ⚙️ Options

| Option | Choices | Default | What it does |
|---|---|---|---|
| Desktop | On / Off | On | The PC opens the desktop. Off: the game's own PC menu. |
| Boot Screen | On / Off | On | The W boot screen before the desktop. |
| 24-Hour Clock | On / Off | Off | The menu bar's clock as 15:30 instead of 3:30 PM. |

## 💾 Installation

Install it from Gen1Recomp's mod manager, or unzip a release into the game's `mods` folder, then
turn it on for your Generation 3 games.

## 🔗 Works With

- **Any save:** the mod keeps no data of its own in your save. Items and mail move exactly as the
  game's own PC moves them, so you can turn the mod on and off whenever you like.
- **Other mods:** other mods can add their own apps to the desktop.
- **WoobleDex:** the Boxes preview shows a Pokémon's Dynamax Level and G-Max Factor (from
  WoobleDex's Dynamax Candy and Max Soup, or Max Raids' dens), as the game's summary does.

## 📌 Good to Know

- The PC's own sounds and its screen flicker when you turn it on are kept as they are. The game's
  "booted up the PC" and "Which PC should be accessed?" lines are skipped: the boot screen does
  their job.
- With the Desktop option off, every PC opens the game's original menu.
- **Boxes follows the game's rules:** your party always keeps a Pokémon that can battle, a Pokémon
  holding mail stays out of the boxes (take the letter off in Mail first), and Eggs can't be
  released. A Pokémon put in a box is healed, as in the game. On FireRed and LeafGreen, L and R
  turn the boxes and pages here instead of opening the game's Help.
- **Your own wallpapers:** put PNG or JPG pictures in the mod's `wallpapers` folder, then pick them
  in Settings. With one of your pictures chosen, a Fill / Stretch switch appears by the title
  (SELECT or a tap): Fill covers the screen and crops the picture from its centre, Stretch shows
  the whole picture stretched to the screen's shape.
- **Your own language:** copy `lang/en.lua` to a new file in the same folder (for example
  `lang/pt.lua`), write the language's name at the top and translate the words. It shows up in
  Settings. The other languages' files can be edited the same way.
- Your Settings choices are kept for the whole game, not per save file.

## 🪪 Credits

Made by Wooble. The touch-screen look grew out of WoobleDex's vending machines.

---

[MIT License](LICENSE) · [Changelog](CHANGELOG.md) · [Development](DEVELOPMENT.md)
