# Realistic Equestrian (FS25)

A Farming Simulator 25 mod that gives horses something to do besides being sold: four
competition stats, training through riding and hired staff, breeding that matters, and
daily and monthly events to enter for prize money.

Requires [Realistic Livestock - Ritter version](https://github.com/rittermod/FS25_RealisticLivestockRM)
(`FS25_RealisticLivestockRM`) and works with RL's genetic and breeding maths.

## Status

Milestone 6 of 7, plus the Events tab and dealer horses: stats exist, are saved, show in RLRM's
horse info panels and the look-at info box, improve with training, are inherited when horses
breed, and win prize money in competitions entered from RLRM's menu. Competitions carry risk:
scratches, eliminations and injuries with vet bills. Good horses from the dealer cost real money
and take a year or more to pay back. Multiplayer sync is still to come.

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
animals tab) a horse gets a section under Pedigree and Genetics: SKILL POTENTIAL on the left
(`Speed  Very high`) and SKILLS on the right (`Speed  60 - High`), the four stats in the same order
in both, coloured on RLRM's red-to-green scale with the same ladder, so a horse trained to its full
potential shows the same word in both. The stat grid above keeps only RLRM's rows and shrinks to
fit, so the pane doesn't need to scroll.
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
- **Young horse** classes are for two-year-olds only: a fee, no prize money, a training boost, and
  you still see where the horse placed. Every other event is open from three years.
- Events carry real-world names: show jumping by fence height (1.00m up to Grand Prix), dressage
  by test level (Intro up to Grand Prix), eventing by FEI star level (One-Day Event up to CCI5*),
  flat racing as Maiden, Handicap, Listed and Group 1, and so on. The names live in the
  translation file, so they are easy to change. A Level column shows the tier.
- Steeplechases are rare, as they are today: the discipline's `chance` in `data/events.xml`
  (0.08) scales how often one is drawn.
- Novice has a rating cap (60), so it stays a class for novices. Above it, a horse can always
  enter something it can win.
- A horse can start at most **two round events a month** (monthly events are on top), so a good
  horse is not a daily money tap however many days your months have.
- A farm can make **three entries a month** in all, so you pick your best horses rather than
  sending the whole barn: `eqSettings entriesPerMonth <n>` (0 = no limit).
- Every entry pays **transport** on top of the fee: a quarter of the game's transport price for
  the horse ($150 for an adult). Hauling the horse there yourself instead is a stretch goal.
- A horse can only be in one round event and one monthly event at a time.
- A mare more than 30% through her pregnancy (RLRM's reproduction value) can't be entered, and
  one entered earlier is scratched if she passes 30% before the event, with half the fee back.
  She can compete again after foaling.
- A horse's rating in a discipline weighs its trained stats (show jumping: agility first;
  dressage: temperament; racing: speed and stamina). Cross country, eventing and steeplechase take
  half their rating from the horse's weakest stat, so all-rounders shine there. Outdoor events
  have conditions: firm favours speed, soft and heavy favour stamina, hot weather tests stamina
  and temperament and raises the injury risk. On the day, RLRM's fitness and health
  scale the performance, plus a little luck.
- The top three share the prize pool 50/30/20. Horses from different farms can enter the same
  event.
- Racing can be switched off: `eqSettings racing off`.

**Events tab:** RLRM's menu (Shift+O) gets a Competitions tab with a rosette icon. The left table
lists the open events (fee, prize pool, level, conditions, when results come, and how many of your horses can
enter). Select one, and the right table shows your horses with their **Success** (Favourite,
Contender, Outsider or Long shot: their chance of a top-three place, counting the rivals, their
fitness and the risk of elimination), **Training** (for young horse classes, how much the outing
would teach them: High down to None) and whether they can enter. Under it, a panel shows the
selected horse's trained stats in RLRM's colours. Pick a horse and press Enter. The Results button switches the left table to your results.
For now the tab works in single player and for the host; multiplayer clients get a note.

Console: `eqEvents` lists open events, `eqRatings [horse]` shows ratings and career,
`eqEnter <event number> <horse>` enters (the fee is paid at once), `eqResults` shows results.

## Buying horses

The dealer sells horses of every quality, priced by their talent: an ordinary horse costs about
what it does without this mod ($3,000-6,000), a good prospect $9,000-20,000, and now and then a
championship prospect $25,000-45,000. A good horse is an investment, not a quick flip:

- **Talent:** a horse's potential leans on its RLRM genetics, so RLRM's dealer quality setting
  also sets how talented the dealer's horses are. About 1 in 15 is a really good prospect.
- **Green:** dealer horses arrive with little training, so a good one needs a year or more of
  work before it wins much above Novice.
- **The dealer's word:** the potential words for a dealer horse end in "?" (High?, Very high?).
  They are the dealer's view: usually right, sometimes generous, now and then modest. After three
  months on your farm you find out, with a message saying whether the horse is better, worse or
  about what the dealer said, and its price moves to match.
- **Settling in:** a bought horse can't compete in its first month.
- **Price:** RLRM's price plus a premium for talent (it doubles every 7.5 points of the two best
  potentials) and schooling, shrinking once the horse is past its peak. Selling goes through the
  same price, and RLRM's dealer markup means buying and selling straight back always loses.

In the test model, a talent-85 horse bought for about $12,500 is worth about the same three months
later, has paid for itself within the second year, and makes good money after that, before vet
bills. `eqDealer` (testing) lists the dealer's horses with their real potential and the
dealer's view of it.

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
