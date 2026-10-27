# How Realistic Equestrian works

The full rules behind the mod, for players who want the numbers. The [README](../README.md) has
the short version. Most numbers live in the `data/` XML files and can be changed without code.

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

- **Your riding** is the main way to train. Stamina and speed train best from focused work, watched
  by an **Exertion** meter while you ride (it rises in canter and gallop and falls at slower gaits
  and at a halt). A good focused session can give up to double what a full day of riding used to;
  just riding round the gaits trains them at about a quarter of that.
- **Press Y while riding** to switch the training panel between **Freestyle** (the meter and a line
  for each stat) and the **Stamina**, **Speed**, **Agility** and **Temperament** views. Colours
  show how each is going. Help pops up at the bottom of the screen the first time you open each
  view; press **H** to see it again, and click anywhere to move on. Welcome popups do the same
  the first time you come within 35 m of a horse pen or ride a horse, open RLRM's menu with
  horses on the farm, open its Information tab, open the Events tab, and open the Diseases dialog
  for a horse. A popup stays until you click through its last page; closed early (Esc, getting
  off), it shows again next time. The **Help popups** setting (Show again) clears every seen flag
  on your machine, so each popup shows once more.
- One kind of training talks at a time, each in its own colour: a steady canter starts stamina
  (blue) until the tempo breaks, a cleared jump starts agility (green) until the combo ends, a
  warm-up gallop starts speed (orange) until the Sprint is over. Temperament (purple) routines
  always run. Only that training's popups and prompts show; the panel stays the same.
- Jumping doesn't interrupt a run or a sprint: the pace from before take-off counts until shortly
  after landing, so you can jump an obstacle in the way.
- **The riding bar is the horse's energy for the day.** Once it is full the horse is tired, the
  line reads "Training (tired)", and it trains no more until tomorrow. Galloping tires it fastest,
  so choose what to work on. A fit horse's bar fills more slowly (up to 1.4 times as long at
  stamina 100). Below 30% exertion a horse standing or walking recovers quickly, a fit one faster
  still.

### Peak form

- Your own riding is mostly preparation for contests. Minigame work in a stat puts the horse in
  **Peak form** for the month's events: up to **+8** to that stat, in full at a strong session
  (1.5 times a full day of plain riding's work in that stat) and in proportion below it. Just riding
  the gaits gives no form.
- **Once a month:** sessions on several days of a month don't add up. Each stat keeps the best
  session of the month, so at 1 day a month it is simply the day you ride.
- Peak form counts in every event the horse runs that month, including Advanced and Championship
  events that resolve at the month change, and the Events tab's chances include it. It adds to the
  stats the course's checks roll against and to the horse's rating on the day, and may lift a
  stat past its ceiling (to at most 100). It never counts toward which events a horse may enter.
- It shows as **Peak form** in the riding panel and the horse's Skills box, and clears once the
  month's events have run. A popup explains it the first time a horse gets it.
- Permanent training is unchanged: your riding still trains faster than staff and takes a stat
  the last 5% of its ceiling.

### Stamina

Stamina comes from runs at canter or gallop. Canter 8 seconds without jumping or galloping,
starting under 40% exertion, to start stamina training; then the tempo multiplies it (up to x5,
2.5 times the gains). Only well-timed gait changes raise the tempo: when the middle of the screen
says **Canter! (S)** or **Gallop! (W)**, press that key right then and your horse gets a breather (a
bigger one the more tired it is, so hitting every change keeps it under blowing hard); three good
changes (a perfect one counts double) raise the tempo. Pressing too early or missing one loses the
progress to the next step, and the next change comes soon after. Timing tightens as the tempo
climbs. Blowing hard (over 85% exertion) for 5 seconds or more than a few seconds below a canter
ends the run: rest under 40%, then canter to start again. Gait changes pause during a Sprint or a
routine command.

### Speed

Speed comes mostly from Sprint. Fast gallops while the horse is fresh (exertion under 25%) add only
a little; stand still (4 s) or walk (5 s) and exertion drops quickly. Two good warm-up gallops warm
the horse up; keep galloping and press **W** when **Sprint!** shows to run 25% faster, held on the
limit just short of blowing hard (keep tapping W to spur it on; a slower horse runs out sooner),
with three times the speed training. Then rest right down before warming up again.

### Agility

Agility comes from jump combos: clear jumps one after another (fences, poles, anything solid) for
x2 up to x5. You have 10 seconds to clear the next one; a trot is fine, but stopping, walking or
backing up runs the clock down ten times as fast. A jump is judged once the horse has landed:
hitting something or landing on it takes 3 seconds off the combo clock. Horses jump higher and stay
in the air longer from a canter, and pick up speed faster, so a controlled canter approach can clear
a fence.

### Temperament

Temperament comes from a routine: walk to start one, then do each movement asked for (walk, trot,
stop, back up, turn left, turn right) within 3 seconds, for x2 up to x8. Each step up brings the
requests quicker and gives less time to react (1.5 seconds at x8), and from x4 the horse must hold
its pace between requests: changing gait unasked breaks the routine (passing through a walk on the
way to a requested stop is fine). A canter, gallop, jump or a missed request breaks it. Steer freely: a turn request only needs the left or right key held for a
moment, at any pace from backing up to a trot, and the other requests ignore steering. Requests
show in the Freestyle and Temperament views.

### How stats change riding

Speed sets a horse's top speed (about 10% slower than the base game at 10, 20% faster at 100);
agility sets how high it jumps and how quickly it turns; a calm horse (temperament) changes pace a
little quicker and stands less long after a knock. Canter jumps go higher than the base game's, so a
horse can clear fences without a full gallop.

### Staff, age and metabolism

- **Staff** (the base game's Animal Workers with Riding turned on for a horse pen, added in patch
  1.25, or RLRM's herdsman horse-care rule) count for whatever share of the riding bar you did not
  fill yourself, at half the rate of a full day of plain riding. They train to the horse's role
  and stop at 95% of each ceiling; your own focused riding trains a stat up to four times as fast,
  and only it takes a stat the last 5%.
- **Staff bring loose horses home.** A horse you ride and leave out in the world stays there
  overnight, unless you pay Animal Workers (Riding or Grooming) on one of your horse pens: when they
  do their round, they fetch your loose horses back to their own pen (or the nearest staffed pen
  with room) and look after them with the rest.
- A groomed horse (dirt 10% or less at the day's end) gets a little temperament.
- **Metabolism** (RLRM's gene) already sets how much a horse eats. It now also sets how fast riding
  builds fitness: a fast-metabolism horse costs more to feed but gets fit sooner (up to 45% faster),
  and a slow one is cheap to keep but slow to bring back into condition (down to 60%). Fitness
  lost is not changed, and it doesn't change how fast stats train.
- Gains slow as a stat nears its ceiling, and a green horse learns the basics fast: a stat below
  40 trains faster, up to three times as fast at 0 (twice at 20). Young horses train at full speed
  up to twelve years old, then slow down. A horse left idle for more than about half a month fades toward half its ceiling, and past
  16 years every stat slowly declines.

### Roles

- A **role** is a reminder of what a horse is for: Dressage, Show Jumping, Cross Country, Eventing,
  Racing, Breeding or For sale (or No role). Press **G** (the Role button) on a horse in RLRM's
  Info tab to cycle it. Host only for now in multiplayer.
- Once any horse in a pen has a role, the Info tab lists the pen's horses in groups by role, then
  No role, then Retired. Retired is not on the Role button: retiring a horse (RLRM's Diseases tab)
  shows it as Retired everywhere, and bringing it back gives it its old role again. The role also shows in RLRM's other lists (unless RLRM has a mark there), on the
  Skills box when you look at the horse, in the menu's Skill potential column and at the top of
  the riding panel, with the horse's four skills.
- **Staff train toward the role.** Each role has a staff profile (Dressage leans on temperament
  and agility, Racing on speed and stamina, Eventing on all but speed; Breeding, For sale and No
  role keep every stat ticking over). Staff don't manage it equally well every day: the role's
  own stats get between 50% and 150% of their effort each day, 100% on average. `eqChanges` shows
  how they did.

### Riding bar and names

- When a horse's riding bar is full it trains no more that day: the look-at Skills box says so in
  red, the Daily riding value reads "100 % - full" (red in RLRM's menu) and the riding panel shows
  a red line.
- The look-at box is headed with the horse's name instead of "Animal".

Console commands: `eqTraining` shows each horse's role and today's riding; `eqFocus <name> <role>`
sets it (`balanced` for no role, `showJumping`, `dressage`, `crossCountry`, `eventing`, `racing`,
`breeding`, `sale`).

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
has a row each for Oats, Barley and Corn, plus Hay, Treats and (while it holds any) Other grain.
In place of the base game's percentage each row names the stats its feed boosts, with a
strength mark: + for a small boost (10%), ++ for moderate (20%), +++ for strong (30%), e.g.
"Corn (Speed+++)", "Oats (Stamina+, Temperament+)", "Hay (no boost)". The grain rows are display only: oats, barley and corn still feed as
one hard-feed group, so a horse on oats alone is as well fed as one on all three. While riding, a "Feed" line shows the boost, and `eqFeed` lists the horse food groups and each horse's boost.

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
| Round pen (the base game's round roofed barn02, on any map: Elmcreek 25, Frontier) | Temperament; a little Agility | Dressage |

Plain stables (the Horse Stable mod, the Equestrian Pack L barn) only house horses and give no
bonus.

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
- Every other event teaches a little too, less the higher the level (half a young horse class at
  Novice, down to a fifth at Championship), and less again for horses past their peak (12 years).
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
  at once. A farm can enter at most two horses in one event; the second on the same Auto
  Transport trip shares the truck and pays a quarter of that haul (quarantine abroad is still
  per horse). **Manual Transport** pays no transport, but you take the horse to the animal dealer
  yourself before the event runs (before the next round's results, or by month end for monthly
  events); a horse never delivered doesn't start and the fee is lost. The Events tab shows both
  totals, and has an Enter button for each. A horse waiting to be delivered shows "Awaiting
  delivery" on its card in RLRM's animal lists, so you can see which one to load. To deliver,
  drive the trailer into the dealer's loading area and press **Left Alt + R** ("Deliver to
  event", beside the dealer's own prompt; rebindable in Controls). The horse goes home, hidden
  until its event is over, so it needs a free place in one of your pastures. Costs are in
  `data/events.xml` (`<transport>`, `<routes>`).
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
- **Event experience:** every start (a finish or an elimination) teaches the horse that
  discipline, quickly at first and slower as it fills up: about 10 starts to half way, 30 to
  nearly full. Full experience adds 8 points to the horse's rating there, on top of its stats.
  Related disciplines pick up a little: eventing teaches some show jumping, dressage and cross
  country, and the reverse; the races and steeplechase teach each other. Experience holds for
  three months without a start in that discipline, then fades by 5% a month. The horse's
  **Favourite event** shows its best discipline, two close ones ("Show Jumping & Dressage"),
  **3 Day Eventer** when show jumping, dressage and cross country are close, **Racehorse** for
  close races, or **All Rounder** for three or more others. It shows in the Events tab's horse
  panel, RLRM's Skills section and the look-at box.
- The top three share the prize pool 50/30/20. Horses from different farms can enter the same
  event.
- Racing can be switched off: `eqSettings racing off`.

**Events tab:** RLRM's menu (Shift+O) gets a Competitions tab with a rosette icon. The left table
lists the open events (fee, prize pool, level, conditions, when results come, and how many of your horses can
enter). Select one, and the right table shows your horses with their **Success** (Favourite,
Contender, Outsider or Long shot: their chance of a top-three place, counting the rivals, their
fitness and the risk of elimination), **Training** (how much the outing would teach them: High
down to None) and whether they can enter. Success and Training stay blank for a horse that can't enter, and retired horses are left off. Under it, a panel shows the
selected horse's trained stats in RLRM's colours. Pick a horse and press Enter. The Results button switches the left table to your results.
For now the tab works in single player and for the host; multiplayer clients get a note.

Console: `eqEvents` lists open events, `eqRatings [horse]` shows ratings (with experience),
favourite event and career, `eqExperience <horse> <discipline> <0-100>` sets experience for testing,
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
  months on your farm you find out. Usually you just "have a firmer idea of their potential";
  after a big overstatement you "might have been misled"; now and then the horse is better than
  the dealer let on. Its price moves to match.
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

**Horses that come with a farm:** some maps put horses in their farms' barns with no age and no
health (Midwest Moraines 4X does). Nobody feeds an unowned barn, so with RLRM they starve to
nothing before you buy the farm. When one of these reaches your farm it gets a fresh start: an
adult age of 4 to 12, full health, a normal weight and starting stats for that age. Only a
newborn with no mother, never ridden and almost no health counts, so a real foal or a sick
horse is never touched.

## Risk and retirement

- **Scratches:** a horse that is injured, ill, retired or unsound on the day doesn't start, and
  half the entry fee comes back. Now and then a horse loses a shoe.
- **Health:** RLRM's health follows feeding: a well-fed horse sits at 100, and it falls hour by
  hour while the pen's food is short, then climbs back once fed. Under 50 health a horse may be
  unsound on the day: a 10% chance for every 5 points (or part of 5) under 50, so 45 to 49 is
  10%, 40 to 44 is 20%, and 26 to 29 is 50%. At 25 or under it can't be entered, and one that
  drops that low after entering is scratched. The Events tab shows the chance in the horse's
  status ("Low health: 20% scratch") and the entry message repeats it. Poor health also raises
  the injury chance: 1.5x at 50 health, 2x at 0.
- **Eliminations:** refusals and falls over fences, pulled up in races. Cross country and
  steeplechase are the riskiest, dressage the safest. A horse out of its depth for the tier, or
  with low temperament, goes out more often. Eliminated horses win nothing.
- **Injuries:** rare, more likely on firm going, after a long trip abroad, for unfit or
  unhealthy horses, with low stamina and after a fall. An injury shows on the horse's Diseases
  page in Realistic Livestock. Treat it there (the vet bills RLRM's medicine line daily while the
  course runs) or leave it to heal for free, more slowly; or cull. Nothing is charged unless you
  start treatment, and the time counts in days, so an injury lasts its full time whatever day it
  happened. A hurt horse can't compete, doesn't train (its stats fade a little) and can't be sold.

  | Injury | How often | Treatment | Untreated |
  |---|---|---|---|
  | Bruised sole | 25% | 1 day, $400 | 1 month |
  | Hoof abscess | 18% | 1 day, $800 | 1.5 months |
  | Overreach cut | 17% | 1 day, $1,500 | 2 months |
  | Sore back | 15% | 1 month, $2,500 | 3 months |
  | Splints | 10% | 2 months, $1,200 a month | 4 months |
  | Tendon strain | 8% | 4 months, $4,000 a month | 9 months |
  | Chip fracture | 4% | 2 months, $12,000 a month | 12 months |
  | Torn suspensory | 3% | 6 months, $6,000 a month | 12 months |

  Resting always takes at least 2 days, so at 1 day a month the 1-month rests take 2 (treatment
  still takes 1). Injuries never spread and never kill. With RLRM's diseases switched off they are plain box
  rest for the untreated time, with no bills.
- **Illness:** every start carries 3 times RLRM's own monthly chance of its horse diseases
  (colic), times the trip's injury factor. A sick horse can't be entered until it is better.
- **Injury risk** shows on the Events tab as Low, Minor, Moderate or Risky (from about 0.75%, 2% and 3% injury chance a run): the Risk column
  is for a typical horse (discipline, level, conditions and how far the venue is), and the
  selected horse's panel shows that horse's own risk (its fitness, stamina, health and how likely
  it is to fall). It reads Off with injuries turned off.
- **Retirement is your choice:** the Retire button on the horse's Diseases page (or `eqRetire
  <horse>`) retires a horse, and the same button (or `eqRetire <horse> undo`) brings it back.
  An injured horse still has to heal, but retired, its treatment costs 60% less, even mid-course.
- **Forced retirement** is off by default. With `eqSettings forcedRetirement on`, 1 in 10 chip
  fractures and 1 in 4 torn suspensories end a horse's career. `eqSettings injuries off` turns injuries off entirely.

