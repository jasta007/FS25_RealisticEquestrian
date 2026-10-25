# Working on Realistic Equestrian

Notes for anyone changing the mod. Players want the [README](README.md); the rules in detail are in
[docs/MECHANICS.md](docs/MECHANICS.md).

## Layout

- `modDesc.xml`: the mod's description, dependency on `FS25_RealisticLivestockRM`, the
  `EQ_DELIVER` input and the one source file, `scripts/main.lua`, which loads everything else.
- `scripts/core/`: constants, the per-horse record, the save registry, stats maths and the
  bridge to RLRM (`EqRLRM.lua`). RLRM functions the mod needs are checked there at start; a
  missing one turns that feature off with a log line instead of an error.
- `scripts/training/`, `scripts/competition/`, `scripts/dealer/`, `scripts/facilities/`,
  `scripts/gui/`: one folder per system. Files ending in `Hooks` attach to the game or RLRM;
  the rest is plain Lua that the headless tests can run.
- `data/events.xml`, `data/feeds.xml`, `data/facilities.xml`: disciplines, tiers, fees, prizes,
  venues, transport routes, feed boosts and the buildings that count as horse facilities.
  Most balance changes and support for new maps, crops and building mods go here, not in code.
- `translations/translation_en.xml`: every player-facing text, including event and venue names.
- `art/`: the icon and logotype sources (see `art/README.md`).
- `tests/`: the headless test runner.

## Building a test zip

Zip the folder's contents, not the folder itself, as `FS25_RealisticEquestrian.zip`: `modDesc.xml`
must sit at the top of the zip. Only `data/`, `gui/`, `scripts/`, `translations/`, `modDesc.xml` and
`icon_RealisticEquestrian.dds` are needed. For example:

```
git archive -o FS25_RealisticEquestrian.zip HEAD data gui scripts translations modDesc.xml icon_RealisticEquestrian.dds
```

## Testing in game

1. Put the zip in your mods folder next to `FS25_RealisticLivestockRM.zip` and enable both on a
   savegame that has horses.
2. Turn on the developer console (`<development><controls>true</controls></development>` in
   `game.xml`) and open it with the tilde key.
3. `eqHorses` prints every horse's stats and exact ceilings. Save, reload and run it again: the
   numbers should match.
4. The log (`log.txt`) shows lines tagged `RLEQ`. If RLRM is missing or too old the mod says so
   there and stays switched off.

Testing-only console commands: `eqHorses` (exact ceilings), `eqDealer` (the dealer's horses with
their real potential), `eqRedraw` (a new set of round events), `eqDeliver <horse>` (deliver a
Manual Transport horse without driving to the dealer), `eqExperience <horse> <discipline> <0-100>`,
`eqFacilities near` (map nodes and placeables around you, for adding buildings to
`data/facilities.xml`) and `eqProbe` (writes the dealer's loading triggers to the log).

## Headless tests

```
luajit tests/run.lua <path to an FS25_RealisticLivestockRM checkout>
```

Run them before every push. New pure logic should come with tests in `tests/run.lua`.

## Releasing to itch.io

`.github/workflows/release.yml` runs the headless tests, builds the zip and pushes it to the
`fs25-mod` channel of jasta007/realistic-equestrian with butler. Pushes to `main` do not publish.
To release, set `<version>` in `modDesc.xml` (for example `0.1.0.0`), merge it to `main`, then push
a matching tag:

```
git tag v0.1.0.0 && git push origin v0.1.0.0
```

The run fails if the tag and `modDesc.xml` disagree. It can also be run by hand from the Actions tab
(Release to itch.io, Run workflow), which uploads whatever version `modDesc.xml` holds. It needs the
`BUTLER_API_KEY` repository secret (an itch.io API key).

## Conventions

- Never change RLRM's files. Hook or wrap its functions, and check they exist first.
- No real organisations or brands in names. Venues are FS25 map names in four regions (North
  America, South America, Europe, Asia and Oceania), written "Town, State", never a bare state.
- Keep the README for players. Put rule details in `docs/MECHANICS.md`.
