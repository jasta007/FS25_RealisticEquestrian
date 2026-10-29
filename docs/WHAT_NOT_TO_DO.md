# What not to do

Easy mistakes on this project, each learned the hard way. Add to it when a new one bites.

## Lua

- **No bare `pcall` or `xpcall`.** GIANTS' TestRunner flags every one as hiding errors. Use
  `EqLog.try(context, fn, ...)` (logs a warning), `EqLog.guard` (logs an error) or
  `EqLog.finally(restore, fn, ...)` (restores, then raises the error again). They live in
  `scripts/core/EqLog.lua`, the only file allowed a pcall.
- **Don't name a function `load`, `loadstring`, `loadfile` or `dofile`**, even a local one. The
  TestRunner reads the call as dynamic code loading. `EqThing.load` as a table field is fine.
- **Don't use the `debug` library** (`debug.traceback` and friends). The game may strip it and the
  TestRunner warns about it.
- **Keep lines under 200 characters.** Longer ones are a TestRunner warning.

## Art and placeables

- **Don't edit generated files by hand.** The placeable .i3d, .xml and .dds files under
  `placeables/` come from `art/source/*.py`. Change the script and run it again.
- **Shop images must be BC7, 3D textures must have mipmaps.** Pillow's own DDS writer does neither,
  so the art scripts use `art/source/eqdds.py` (`save_bc7`, `save_dxt1`). Don't go back to
  `img.save(path, pixel_format="DXT1")`.
- **Every placeable needs `<dailyUpkeep>` in its storeData**, even when it is 0.
- **Don't write `*BufferMemoryUsage` / `textureMemoryUsage` into storeData.** The game works them out.
- **Inline i3d geometry fails the TestRunner.** The scripts write shapes into the .i3d; GIANTS Editor
  turns them into a binary `.i3d.shapes` on Save, but only with Preferences > Save "force external
  binary files" switched on (off by default). Running an art script again undoes that, so re-save
  its .i3d files in GIANTS Editor afterwards.
- **Inline collision doesn't work in game.** A collision shape left inline in the .i3d gets a "Mesh
  cooking" warning and gives no physics: the horse rides through and construction can't pick the
  placeable to sell it (show jumps, 2026-10-29). Re-save new placeables in GIANTS Editor before testing.
  `art/source/ge-resave.ps1 -Files a.i3d,b.i3d` does it without touching the keyboard (File > Save
  sent straight to the editor's window).
- **Mod atlas icons in Bitmaps must be made without `sliceId`** (header icon bug, PR #40).

## modDesc

- **descVersion must match the game's** (115 as of TestRunner 0.9.23).
- **Don't add title translations that just repeat the English title.** Only translate when the
  title actually changes.
- **Every description needs a short changelog** for the current version, in each language.
- ModHub wants version 1.0.0.0 or higher. We stay on 0.x while the mod is itch.io only, so the
  TestRunner's version error is expected.

## Test builds and James's PC

- **Never copy the zip into the mods folder while the game is running**, not even at the main menu.
  The game keeps the old zip's index and fails with "Can't load resource .../main.lua". Check
  `log.txt` ends with "Application quit" first, or ask James to close the game.
- **Write the test zip to a temp file and `mv` it into place.** Two threads writing the same zip at
  once left a truncated, corrupt file.
- **Run `luajit tests/run.lua <RLRM path>` before building a zip.**

## Docs

- **Keep README sections short**, a few lines like the release notes. Detailed rules go in
  `docs/MECHANICS.md`.
