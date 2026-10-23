# Realistic Equestrian (FS25)

A Farming Simulator 25 mod that gives horses something to do besides being sold: four
competition stats, training through riding and hired staff, breeding that matters, and
daily and monthly events to enter for prize money.

Requires [Realistic Livestock - Ritter version](https://github.com/rittermod/FS25_RealisticLivestockRM)
(`FS25_RealisticLivestockRM`). This mod calls RLRM's own code (breeding maths, genetics bands,
horse data) and hooks its functions; it never copies or patches RLRM files.

## Status

Milestone 1 of 7: stats exist, are rolled for every horse, and are saved. Training, breeding,
competitions and the in-game screen are still to come.

## Trying it

1. Zip the folder contents (not the folder) as `FS25_RealisticEquestrian.zip` and put it in your
   mods folder next to `FS25_RealisticLivestockRM.zip`. RLRM 1.4.2.0-dev.3 or newer is recommended.
2. Enable both mods on a savegame that has horses.
3. Turn on the developer console (`<development><controls>true</controls></development>` in
   `game.xml`), open it with the tilde key and type `eqHorses`.
4. Save, reload and run `eqHorses` again: the numbers should match.

The log (`log.txt`) shows lines tagged `RLEQ`. If RLRM is missing or too old the mod says so there
and stays switched off.

## Stats

Each of Stamina, Speed, Agility and Temperament has a gene on RLRM's 0.25-1.75 scale, which sets a
ceiling from 40 to 100, and a trained level that works up to that ceiling. A hidden talent budget
caps the four ceilings' total, so the best horses can max one or two stats, never all four.

## Tests

```
luajit tests/run.lua <path to an FS25_RealisticLivestockRM checkout>
```
