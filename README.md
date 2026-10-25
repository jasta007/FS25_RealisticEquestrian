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
(`Speed  Very high`) and SKILLS on the right (`Speed  60 - Promising`), the four stats in the same
order in both. Potential is genetic, so it uses RLRM's red-to-green scale. Skill is what training
has done so far, so it runs from white (untrained) through yellow to RLRM's greens, with its own words: Untrained (0),
Novice (10), Trainee (25), Amateur (50), Promising (60), Competitor (70), Contender (80), Champion
(90) and Legendary (98 and up). A horse with Speed 20 and Excellent potential is a good young horse,
not a bad one. The stat grid above keeps only RLRM's rows and shrinks to
fit, so the pane doesn't need to scroll.
Looking at a horse shows a Skills box of its own under RLRM's Genetics box, with `Speed  60 - Promising (Very high)` for each stat: the skill in our words, then the potential (that box has no colours). The game's own Animals screen has room for only five rows and RLRM's horse rows take three, so our stats are not shown there. The console's `eqHorses` still
prints exact ceilings, for testing.

RLRM's Meat Quality is hidden for horses, in the menu's genetics column and the look-at genetics
box. Other animals are not affected and nothing is changed in RLRM. `eqMeatQuality show` brings it
back; the choice is saved for your machine in `modSettings`.

## Breeding

A foal born on a farm inherits its four stat genes, and the hidden talent budget, from its dam and
sire through RLRM's own breeding maths (`BreedingMath.breedOffspring`). Each parent's gene is first
pulled 40% of the way back toward average, so two elite parents give a strong foal, not a
guaranteed better one; selective breeding over generations is how the best horses are made. A
sire bought as a straw breeds true to the stats its identifier rolls.

**Starting stats.** The first time the mod sees a horse, each stat is drawn from a bell curve.
Foals start low (around 15), and the centre rises with age to about 50 for a horse of four or
more, with a wide spread. A talented horse's stats lean a little higher, and a stat never starts
above its potential. Starting above 80 is rare: about one horse in 125. Dealer horses start a
few points lower. Horses from an older save whose stats were all still at the old flat 10 draw
new starting stats the next time they are seen. `eqHorses` shows each horse as `bred` or `rolled`.

## Training

Every horse trains once a day, at RLRM's daily horse tick.

- **Your riding** trains by gait: walking builds temperament, trotting a mix, cantering stamina
  and agility, galloping speed and stamina, and backing up builds agility and temperament fast. Jumps at canter or gallop add agility and some temperament. Every gait trains
  at the same rate, only different stats. The base game's riding bar is the horse's energy for
  the day: once it reaches 100% the horse is tired, the line reads "Training (tired)", and it
  trains no more until tomorrow. Galloping tires a horse three times as fast as walking, and
  galloping until it tires is a full day of speed work, so choose what to work on first. While riding, a
  "Training today" line shows the effort so far.
- **Staff** (the base game's animal worker, or RLRM's herdsman horse-care rule) count for whatever
  share of the riding bar you did not fill yourself. They train to the horse's focus and stop at
  95% of each ceiling; only your own riding takes a stat the last 5%.
- A groomed horse (dirt 10% or less at the day's end) gets a little temperament.
- **Metabolism** (RLRM's gene) already sets how much a horse eats. It now also sets how fast riding
  builds fitness: a fast-metabolism horse costs more to feed but gets fit sooner (up to 45% faster),
  and a slow one is cheap to keep but slow to bring back into condition (down to 60%). Fitness
  lost is not changed.
- Gains slow as a stat nears its ceiling. Horses under 24 months train at 30%, 24-36 months at
  60%. A horse left idle for more than about half a month fades toward half its ceiling, and past
  16 years every stat slowly declines.

Console commands: `eqTraining` shows each horse's focus and today's riding; `eqFocus <name> <focus>`
sets what staff work on (`balanced`, `showJumping`, `dressage`, `crossCountry`, `racing`).

### Feed

What is in a horse's trough speeds its training up (it never trains a horse that is not worked).
The mod rewrites every map's horse food list from `data/feeds.xml`, keeping the map's own groups
and weights:

| Feed | Group | Training boost |
| --- | --- | --- |
| Hay, grass, alfalfa, clover (and Geistal's chaff) | hay | none |
| Oats | grain | +10% stamina and temperament |
| Barley, winter barley | grain | +20% stamina and agility |
| Corn (maize) | grain | +30% speed |
| Wheat, winter wheat, spelt, triticale, rye | grain | none |
| Carrots | treat | +30% temperament |
| Apples (Orchards and Greenhouses' `APPLE`, Geistal's `APPLE_GT`) | treat | +30% temperament |
| Parsnips, beetroot | treat | none |

Sorghum is no longer accepted: it is toxic to horses. Feeds a map or mod does not have are
skipped. Every feed in the trough gives its full boost and the boosts add up, so oats, barley and
corn together give all three; carrots and apples are the exception and count once between them. A horse pen's food list
names the groups Hay, Hard feed and Treats and shows what each does in place of the base game's
percentage: the boost while it holds feed ("Treats (Tem +30%)"), the stats it can boost while it is
empty ("Hard feed (Sta Spd Agi Tem)"). While riding, a "Feed" line shows the boost, and `eqFeed` lists the horse food groups and each horse's boost.

## Horse facilities

Horse buildings on your farm make your horses train faster, and a little better on the day of
some events. Owning one speeds up all training (staff and your own riding); riding inside one
yourself speeds your riding up a lot more, by the share of the day's riding you did in there.

| Facility | Training it speeds up | Events it helps |
| --- | --- | --- |
| Riding hall (Equestrian Pack, Riding Hall 2k26) | Agility, Temperament; Stamina while riding in it | Dressage, Show Jumping |
| Riding centre (Riding Stable) | Agility, Temperament, Stamina | Dressage, Show Jumping |
| Outdoor arena (Equestrian Pack outdoor training area) | Stamina, Agility; Speed while riding in it | Cross Country, Eventing |
| Jump course (Riding Hall 2k26 jumps, map courses like Elmcreek 25's) | Agility; Temperament while riding through it. Six fences give the full bonus | Show Jumping, Eventing |
| Round pen (Elmcreek 25's round roofed arena, the base game barn02) | Temperament; a little Agility | Dressage |
| Horse stable mods (Horse Stable, Equestrian Pack L barn) | Temperament, a little | Dressage, a little |

Owned bonuses add up to at most +25% a stat, riding inside to at most +60% more, and the event
bonus to at most +5% condition. Feed boosts stack with these by adding. Matched buildings say
"Improves ... training" in the shop.

Map scenery counts for the farm that owns the farmland under it. Other mods and maps are added
in `data/facilities.xml` without code. `eqFacilities` lists your facilities and what they give;
`eqFacilities near` lists the map nodes and placeables around you, to find a building's name.

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
  by test level (Intro up to Grand Prix), eventing by star level (One-Day Event up to Four-Star),
  flat racing as Maiden, Handicap, Listed and Group 1, and so on. Advanced and Championship events are held at a venue named after a map: the
  base game's maps and popular ModHub maps in four regions (North America, South America,
  Europe, Asia and Oceania), such as "Pallegney Grand Prix" or "Gage, Kentucky Gold Cup (2m)". The
  horses go there in spirit only, so none of those maps needs to be installed. Event names live
  in the translation file and venues in `data/events.xml`, so both are easy to change. A Level column shows the tier.
- Steeplechases are rare, as they are today: the discipline's `chance` in `data/events.xml`
  (0.08) scales how often one is drawn.
- Novice has a rating cap (60), so it stays a class for novices. Above it, a horse can always
  enter something it can win.
- A horse can start at most **two round events a month** (monthly events are on top), so a good
  horse is not a daily money tap however many days your months have.
- A farm can make **three entries a month** in all, so you pick your best horses rather than
  sending the whole barn: `eqSettings entriesPerMonth <n>` (0 = no limit).
- Every entry picks how the horse gets there. **Auto Transport** pays transport on top of the fee
  (a quarter of the game's transport price for the horse, $150 for an adult) and the horse leaves
  at once. **Manual Transport** pays no transport, but you take the horse to the animal dealer
  yourself before the event runs (before the next round's results, or by month end for monthly
  events); a horse never delivered doesn't start and the fee is lost. The Events tab shows both
  totals, and has an Enter button for each. Delivering at the dealer is still being built; for
  now `eqDeliver <horse>` stands in for it. Costs are in `data/events.xml` (`<transport>`, `<routes>`).
- Venues abroad cost more to reach. Your home region comes from the map: a map named in
  `<home>` in `data/events.xml` (Catuaí is South America), else RLRM's map country (RLRM's
  "map country" setting can change it). `eqSettings` shows it. North America to Europe or South America is
  an **overseas** trip: Auto Transport costs 4x plus $1,000 quarantine, Manual pays the dealer's
  $300 quarantine yard. Europe to South America, and Asia and Oceania to anywhere, is a
  **long-haul** trip: 8x plus $2,500, or $500 Manual. The dearer the trip, the rarer it is: about
  60% of named events are in your home region, 30% overseas and 10% long-haul.
- A horse can only be in one round event and one monthly event at a time.
- A horse entered in an event **leaves your pasture** until its result is in: the next round
  for round events, the next month for monthly ones. It still eats, ages and trains with staff in
  RLRM's books; it just isn't there to see or ride. (Single player and host for now.)
- A mare more than 30% through her pregnancy (RLRM's reproduction value) can't be entered, and
  one entered earlier is scratched if she passes 30% before the event, with half the fee back.
  She can compete again three months after foaling.
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
`eqEnter <event number> <horse> [auto|manual]` enters (the fee is paid at once), `eqResults` shows results.

## Buying horses

The dealer sells horses of every quality, priced by their talent: an ordinary horse costs about
what it does without this mod ($3,000-6,000), a good prospect $9,000-20,000, and now and then a
championship prospect $25,000-45,000. A good horse is an investment, not a quick flip:

- **Talent:** a horse's potential leans on its RLRM genetics, so RLRM's dealer quality setting
  also sets how talented the dealer's horses are. About 1 in 15 is a really good prospect.
- **Green:** dealer horses start a few points lower than a home-produced horse of the same age,
  so a good one needs a year or more of work before it wins much above Novice.
- **The dealer's word:** the potential words for a dealer horse end in "?" (High?, Very high?),
  under a "Potential (dealer's view)" heading. They are the dealer's view: usually right, about
  a quarter of the time generous by 6-14 points, and now and then modest by 5-12, so a word is
  sometimes a band too high or too low. After three
  months on your farm you find out, with a message saying whether the horse is better, worse or
  about what the dealer said, and its price moves to match.
- **Settling in:** a bought horse can't compete in its first month.
- **Price:** RLRM's price plus a premium. What the horse can do now (its two best stats) drives
  most of it: the premium doubles every 10 points above 60, so a horse with stats in the 80s is
  very expensive. Potential (the two best potentials, doubling every 7.5 points) is most of a
  young horse's value and a small part of a made horse's. A quarter of the premium is stud value,
  which a gelding loses. The rest scales with RLRM's health, drops while the horse is injured, and
  is gone once an injury has ended its career. The premium shrinks once the horse is past its peak. Selling goes through the
  same price, and RLRM's dealer markup means buying and selling straight back always loses.

In the test model, a talent-85 horse bought for about $10,500 is worth about the same three months
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
