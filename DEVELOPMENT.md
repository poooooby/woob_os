# WoobleOS: development notes

For people working on the mod. Players want [README.md](README.md).

## Layout

| File | What it is |
|---|---|
| `main.lua` | Wiring: loads the modules below, the engine reads they need (session, clock, the Pokédollar glyph), options, `mod.exports` |
| `src/ui_kit.lua` | The drawing kit: page layout on the window's safe area, rect / hit pools, memoised colours, cached gradient meshes, text, the metal plate, the W logo, hints, toast |
| `src/apps.lua` | The app registry and the built-in apps |
| `src/desktop.lua` | The desktop: monitor, boot, menu bar, home grid with pages, dock, W menu, sheets, buttons / touch / mouse |
| `src/shell.lua` | The PC menu takeover, the UI stack layer, the `render.hud` / `input.pointer` / `input.wheel` hooks, the touch pad hide |

## How the PC is taken over

The game's PC scripts open their menu through `src.ui.game3.pc_menu`'s `show(opts)`, looked up when
they run (`scripting/adapters.lua` `openPc`). The shell wraps that one function, once per process
(`PcMenu.__woobleOs`, which calls the current mod instance), and opens the desktop for
`startMode == "select"` (a Pokémon Center PC's menu) and `opts.bedroom` (the bedroom PC). Every other
call (the storage menu, the player's PC menu the scripts open after a choice) is the game's own.

An app ends the desktop with the row the game's own list (`PcMenu._rootEntries`) has for it, so the
script carries on as if that row was chosen and comes back to the PC menu, which is the desktop
again (without the boot, the app's icon zooming back). Logging off hands back 127. In the bedroom,
Items opens the game's player's PC menu over a closed desktop and reopens the desktop when it
closes.

## Adding an app (from another mod)

```lua
local wos = game.mods.exports.wooble_os
wos.apps.register({
  id = "my_app", label = "My App", glyph = "gear", color = { 90, 160, 120 }, order = 60,
  available = function(ctx) return ctx.mode == "select" end,
  open = function(ctx) ... ctx.done() end,
})
```

`ctx`: `session`, `mode` (`"select"` / `"bedroom"`), `family` (`"frlg"` / `"rse"`), `row(id)`,
`finish(row)`, `done()`, `logoff()`, `original(opts)`, `sheet(kind)`. Glyphs: `ball`, `bag`,
`trophy`, `dex`, `power`, `logo`, `gear`, or a function `(K, cx, cy, size, alpha)`.

## Garbage

The desktop draws every frame. Its draw makes about 0.17 KB a frame in the engine; keep it there:
no table literals or closures in a draw, rectangles from `K.R`, colours from constants or the
memoised `mix` / `light` / `dark` / `fade` (their identity keys the gradient meshes), engine modules
kept (never the mod's `require` per frame), the clock read once a second.

## Tests

From the gen1recomp root (the mod is linked as `mods/wooble_os`):

```bash
luajit mods/wooble_os/tests/desktop_test.lua [firered|leafgreen|ruby|sapphire|emerald]
SHOT_DIR=<dir> POKEPORT_GAME=firered POKEPORT_VERSION=firered \
  POKEPORT_DRIVER=mods/wooble_os/tests/drivers/desktop_probe.lua love .
python tools/modkit.py lint mods/wooble_os
```

The headless test draws through a stand-in for `love.graphics` and checks the rows, the boot, the
warm return, logging off, the bedroom, the options, every window shape and the garbage. The probe
walks to a real Pokémon Center PC, runs Boxes and Items through the game's own scripts and takes
shots (`d*.png`).
