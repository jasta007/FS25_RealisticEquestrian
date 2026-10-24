# Realistic Equestrian (FS25)

A Farming Simulator 25 mod that gives horses something to do besides being sold: four
competition stats, training through riding and hired staff, breeding that matters, and
daily and monthly events to enter for prize money.

Requires [Realistic Livestock - Ritter version](https://github.com/rittermod/FS25_RealisticLivestockRM)
(`FS25_RealisticLivestockRM`). This mod calls RLRM's own code (breeding maths, genetics bands,
horse data) and hooks its functions; it never copies or patches RLRM files.

## Status

Milestone 6 of 7: stats exist, are saved, show in RLRM's horse info panels and the look-at info
box, improve with training, are inherited when horses breed, and win prize money in competitions
(entered from the console for now). Competitions carry risk: scratches, eliminations and
injuries with vet bills. The in-game screen and multiplayer sync are still to come.

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

Players never see a ceiling as a number, only as a word in RLRM's genetics style (Average, High,
Very high...). The words follow the event tiers: 40-54 is Average (Novice), 55-69 High
(Intermediate), 70-84 Very high (Advanced), 85 and up Extremely high (Championship); below 40 is
Low, below 30 Very low, below 20 Extremely low. In RLRM's menu (Shift+O, or R in the
animals tab) the stat grid shows each stat's potential, such as `Speed potential  Very high`, and the
Genetics column shows the trained level, such as `Speed 60 - High`, coloured on RLRM's red-to-green
scale with the same ladder, so a horse trained to its full potential shows the same word in both.
The box you get when looking at a horse shows `Speed 60 (Very high)`. The console's `eqHorses` still
prints exact ceilings, for testing.

RLRM's Meat Quality is hidden for horses, in the menu's genetics column and the look-at genetics
box. Other animals are not affected and nothing is changed in RLRM. `eqMeatQuality show` brings it
back; the choice is saved for your machine in `modSettings`.

## Breeding

A foal born on a farm inherits its four stat genes, and the hidden talent budget, from its dam and
sire through RLRM's own breeding maths (`BreedingMath.breedOffspring`). Each parent's gene is first
pulled 40% of the way back toward average, so two elite parents give a strong foal, not a
guaranteed better one; selective breeding over generations is how the best horses are made. A
sire bought as a straw breeds true to the stats its identifier rolls. Foals start every stat at
10 and train up from there. `eqHorses` shows each horse as `bred` or `rolled`.

## Training

Every horse trains once a day, at RLRM's daily horse tick.

- **Your riding** trains by gait: walking builds temperament, trotting a mix, cantering stamina
  and agility, galloping speed and stamina. Jumps at canter or gallop add agility and some temperament. A day's full
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

## Competitions

Events come from `data/events.xml`, so disciplines, tiers, fees and prizes can be changed without
code. Each round draws a fresh set: usually several events per discipline at different fees and
prizes, and sometimes none in a discipline.

- **Round events** (Training, Novice, Intermediate) open every round and give results at the start
  of the next. A round is a day or a month: `eqSettings cadence day|month`.
- **Monthly events** (Advanced, Championship) open each month and give results the next month.
- **Training Events** are for two-year-olds only: a fee, no prize money, a training boost, and you
  still see where the horse placed. Every other event is open from three years.
- Each tier has a rating band, so a strong horse can't farm easy wins in Novice.
- A horse's rating in a discipline weighs its trained stats (show jumping: agility first;
  dressage: temperament; racing: speed and stamina). Cross country, eventing and steeplechase take
  half their rating from the horse's weakest stat, so all-rounders shine there. Outdoor events
  have a going: firm favours speed, soft favours stamina. On the day, RLRM's fitness and health
  scale the performance, plus a little luck.
- The top three share the prize pool 50/30/20. Horses from different farms can enter the same
  event.
- Racing can be switched off: `eqSettings racing off`.

Console: `eqEvents` lists open events, `eqRatings [horse]` shows ratings and career,
`eqEnter <event number> <horse>` enters (the fee is paid at once), `eqResults` shows results.

## Risk and retirement

- **Scratches:** a horse that is injured, retired or unsound on the day (RLRM health under 50)
  doesn't start, and half the entry fee comes back. Now and then a horse loses a shoe.
- **Eliminations:** refusals and falls over fences, pulled up in races. Cross country and
  steeplechase are the riskiest, dressage the safest. A horse out of its depth for the tier, or
  with low temperament, goes out more often. Eliminated horses win nothing.
- **Injuries:** rare, more likely on firm going, for unfit horses, with low stamina and after a
  fall. Most are a strain (1 month of box rest, $1,000 a month in vet bills), some a tendon
  injury (3 months, $3,500 a month), and a few serious (6 months, $10,000 a month). Bills are
  charged at the start of each month. A resting horse can't compete and doesn't train, so its
  stats fade a little.
- **Retirement is your choice:** `eqRetire <horse>` retires a horse, and `eqRetire <horse> undo`
  brings it back. Retiring an injured horse stops the treatment and the bills.
- **Forced retirement** is off by default. With `eqSettings forcedRetirement on`, about 1 in 10
  serious injuries ends a horse's career. `eqSettings injuries off` turns injuries off entirely.

## Tests

```
luajit tests/run.lua <path to an FS25_RealisticLivestockRM checkout>
```
