# Realistic Equestrian (FS25)

A Farming Simulator 25 mod that gives horses something to do besides being sold: four
competition stats, training through riding and hired staff, breeding that matters, and
daily and monthly events to enter for prize money.

Requires [Realistic Livestock - Ritter version](https://github.com/rittermod/FS25_RealisticLivestockRM)
(`FS25_RealisticLivestockRM`). This mod calls RLRM's own code (breeding maths, genetics bands,
horse data) and hooks its functions; it never copies or patches RLRM files.

## Status

Milestone 3 of 7: stats exist, are rolled for every horse, are saved, show in RLRM's horse
info panels and the look-at info box, and improve with training. Breeding, competitions and the
in-game screen are still to come.

## Trying it

1. Zip the folder contents (not the folder) as `FS25_RealisticEquestrian.zip` and put it in your
   mods folder next to `FS25_RealisticLivestockRM.zip`. RLRM 1.4.2.0-dev.3 or newer is recommended.
2. Enable both mods on a savegame that has horses.
3. Turn on the developer console (`<development><controls>true</controls></development>` in
   `game.xml`), open it with the tilde key and type `eqHorses` (or `eqTraining`).
4. Save, reload and run `eqHorses` again: the numbers should match.

The log (`log.txt`) shows lines tagged `RLEQ`. If RLRM is missing or too old the mod says so there
and stays switched off.

## Stats

Each of Stamina, Speed, Agility and Temperament has a gene on RLRM's 0.25-1.75 scale, which sets a
ceiling from 40 to 100, and a trained level that works up to that ceiling. A hidden talent budget
caps the four ceilings' total, so the best horses can max one or two stats, never all four.

## Training

Every horse trains once a day, at RLRM's daily horse tick.

- **Your riding** trains by gait: walking builds temperament, trotting a mix, cantering stamina
  and agility, galloping speed and stamina. Jumps at canter or gallop add agility. A day's full
  riding (the base game's riding bar reaching 100%) is a full day of effort. While riding, a
  "Training today" line shows the effort so far.
- **Staff** (the base game's animal worker, or RLRM's herdsman horse-care rule) count for whatever
  share of the riding bar you did not fill yourself. They train to the horse's focus and stop at
  95% of each ceiling; only your own riding takes a stat the last 5%.
- A groomed horse (dirt 10% or less at the day's end) gets a little temperament.
- Gains slow as a stat nears its ceiling. Horses under 24 months train at 30%, 24-36 months at
  60%. A horse left idle for more than about half a month fades toward half its ceiling, and past
  16 years every stat slowly declines.

Console commands: `eqTraining` shows each horse's focus and today's riding; `eqFocus <name> <focus>`
sets what staff work on (`balanced`, `showJumping`, `dressage`, `crossCountry`, `racing`).

## Tests

```
luajit tests/run.lua <path to an FS25_RealisticLivestockRM checkout>
```
