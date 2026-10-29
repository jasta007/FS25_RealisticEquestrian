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

- **Your riding** is the main way to train every stat. Agility and temperament have their own
  minigames, and stamina and speed come from riding the gallop well (below). A good focused session
  can give up to double what a full day of riding used to; just riding round the gaits trains
  agility and temperament at about a quarter of that.
- **Press Y while riding** to switch the training panel between **Freestyle** (everything),
  the **Stamina**, **Speed**, **Agility** and **Temperament** views (just that stat's training)
  and **Condensed** (only the Exertion bar, with news in a small line above it and a smaller,
  wordless Sprint bar). Every view shows the Exertion bar, and every view trains everything. Help pops
  up at the bottom of the screen the first time you open each view (and the first time you
  gallop); press **H** to see it again (the gallop's help while galloping), and click anywhere to
  move on.
- Welcome popups show the first time you come within 35 m of a horse pen or ride a horse, open
  RLRM's menu with horses on the farm, open its Information tab, open the Events tab, open the Equestrian Staff tab, and open the
  Diseases dialog for a horse. A popup stays until you click through its last page; closed early
  (Esc, getting off), it shows again next time. The **Help popups** setting (Show again) clears
  every seen flag on your machine, so each popup shows once more.
- Jumping doesn't interrupt the gallop: the pace from before take-off counts until shortly after
  landing, so you can jump an obstacle in the way.
- **The riding bar is the horse's energy for the day.** Once it is full the horse is tired, the
  line reads "Training (tired)", and it trains no more until tomorrow. Galloping tires it fastest,
  so choose what to work on. A fit horse's bar fills more slowly (up to 1.4 times as long at
  stamina 100). Riding that trains little (walking or cantering over to a facility) costs only a
  quarter of the usual riding bar, rising to the full rate as focused work (stamina, speed, jump
  combos, routines) earns more effort, averaged over about 20 seconds.

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
- Permanent training is unchanged: your riding still trains faster than staff and is the only
  way to take a stat to its ceiling.

### The gallop and the Exertion bar (experimental)

The gallop has three paces, and exertion only builds at a gallop:

- **Pushing** (W from a canter): the full gallop, its top speed set by Speed. Exertion rises, faster
  the higher it is, and plainly faster near the top (an average horse blows about 15 seconds from
  empty; Stamina slows it).
- **Recovering** (S while Pushing): 80% of the gallop's speed, and exertion falls: quickly in the
  top third of the gallop section, slowly through the middle third (the "zone", marked with ticks),
  quickly again in the bottom third. The horse keeps galloping at an empty bar; W pushes on again.
- **Sprinting** (tap W three times quickly while galloping, and keep tapping): 125% of the gallop's
  speed. Exertion rises slowly at first and ever faster (Speed slows it), so taking it as high as
  you can without crossing the line is the skill. Quick taps ease the rise for a while. The Sprint
  ends when the taps stop, into Recovering, and there is no new Sprint until the bar is empty
  (Pushing is fine).

Pushing up to the line leaves the horse **Fatigued**: it drops to a canter, and it can't gallop until the
bar is empty again. Only a Sprint can run past the line, into the red last-gasp section; a Sprint
that ends there leaves the horse **Blown**: canter only, and while the bar is still past the
line it falls at a fifth of the rate. At a canter or slower the bar falls fast, faster the slower
the gait. The panel lists what you can press now (Sprint ready, S or double tap S to canter), and
the middle of the screen warns **Tiring...** in yellow (in a Sprint from 50%, when Pushing pulsing
from 85%), **Caution** in red and pulsing (in a Sprint from 75%), and **Fatigued!** in red past the line. Slowing from a gallop to a
canter takes one press of S while Recovering with an empty bar, or a quick double tap of S.

The bar shows the gaits too: a line for backing up, standing, walk, trot and canter, then the
gallop section and the red Fatigued section past the line. The marker sits on the gait's line while the bar is
empty, and the section for the current gait lights up (none while standing; the red section lights
while Fatigued or Blown).

**Training on the gallop.** Speed comes from Sprints: every second of a Sprint banks speed effort,
multiplied when it ends by how high it took the bar: x2 half way to the line, rising ever faster to
x10 just short of it (1 + 9 × share^3.17), but only x1 if it ends at or past the line. The panel
shows the multiplier and what the Sprint will bank, and a "Speed x7.3!" burst when it does.

Stamina comes from Pushing and Recovering, at a live multiplier from x1 to x5 shown under the bar.
Behind it the horse has a hidden breath:

- Pushing raises the multiplier, faster the higher the bar is (with its square), and every point of
  exertion pushed uses a hundredth of the breath. With less breath the multiplier rises more slowly
  (down to a tenth of the rate) and falls faster (up to twice as fast), but never stops either way.
- Recovering costs multiplier: quickly in the top third, slowly in the middle zone, quickly again
  in the bottom third. Breath comes back in the middle and bottom thirds, not the top. A canter or
  slower costs multiplier quickly too; a Sprint holds it.
- So the way to x5 is to push close to the line, recover down into the zone and let the horse
  breathe there for a while, then push again. Bouncing between Push and Recover near the top runs
  out of breath and earns little; letting the bar fall too far throws the multiplier away.
- Fatigued (or Blown, a Sprint that ends past the line) drops it to x1, empties the breath and stops
  stamina training until the bar is empty.

### Agility

Agility comes from jump combos: clear jumps one after another (fences, poles, anything solid) for
x2 up to x5. A proper show jump (Riding Hall 2k26's shop jumps, or a map's jump course such as
Elmcreek 25's) trains 1.5 times the agility of a fence, a bale or a parked vehicle. You have 10 seconds to clear the next one; a trot is fine, but stopping, walking or
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
show in the Freestyle, Temperament and Condensed views.

Without dressage markers nearby, that routine trains at 60% of the rate. Near dressage markers (at
least three within 100 m, chained 60 m from each other, not all in a line) the routine rides
between them instead, at the full rate. Markers are the shop's dressage arenas (15x30, 20x40 and
20x60 m, A K E H C M B F round the edge, V S R P on 20x60, D (L) X (I) G flat on the centre line,
no collision) or Riding Hall 2k26's letter boards, whose collision the mod takes off. In one of the shop arenas the routine is a dressage
test: coming within 12 m of the arena (of its rail, not of any letter) starts it with "Move to A to begin a Dressage Routine" (no time limit), then trot to X and halt, 15 more
commands, and a final trot to X and halt. Finishing pays a minute of x8 temperament training at once,
and the next test can start 20 s later. Commands get 20% more time than below, and walks are only
asked for to markers within 12 m:

- Most commands are legs, such as "Trot: B": ride to that marker at that gait (mostly trot, some
  canter, a walk only nearby). Further markers are likelier, a trot needs 10 m and a canter 18 m. The time for a leg
  comes from its length and shrinks as the multiplier climbs. The marker is tagged on the map.
- After 3 seconds to settle, the wrong gait (or a gallop) for 1.5 seconds or running out of time is a
  **fault**: the multiplier drops two steps and a fresh leg starts from where you are. The third
  fault ends the routine, and so does a jump. A leg that starts with a turn gets extra time, up to
  6 seconds at a trot for a full about-turn. Steering is free.
- The next command shows about 3 seconds before the marker; reaching it (3 m at a walk, 4.5 m at a trot, 7 m at a
  canter, so there is room to slow down) is one step up.
- Passing close to another marker may ask for a gait change ("Change: Trot", or "Flying change:
  Canter" from a walk; 2 seconds), worth an extra step, only to a gait the rest of the leg suits.
  Missing it costs nothing.
- At a marker the next command can be a circle (steer one way at a walk or trot until the horse
  has come round), now and then a stop (only at A, C, E, B or X) or, rarely, a rein back for 2.5
  seconds, a stop and a new leg. Turns on the spot are never asked for in a dressage routine.
- In a shop arena, once past X, leaving it (a metre past its letters) for 3 seconds is a fault.
- Markers lose their collision while a horse is ridden, so it rides through them; off the horse it
  comes back, so they can be moved or sold.

### Show jumping courses

Show jumps are linked into a course by riding it, in an edit mode. While editing, every show jump on
the map has no collision, so you ride straight through them in the order you want, and the course's
line and fence numbers are drawn. Show jumps are Riding Hall 2k26's (or any "jumps" facility
placeable), the jumps in the Equestrian Pack's outdoor arena (any part of a facility with a red and
a white flag), map scenery such as Elmcreek's course, and any fence marked with the shop's red and white flags. A jump counts when the horse crosses the
line between its flags (or across its placement area) with 0.75 m to spare; the same jump can come
up again later in the course, but not twice in a row within 4 seconds.

| Key | Not editing | Editing |
| --- | --- | --- |
| Ctrl+J | Record a new show jumping course, or edit the course within 40 m | Save (if recording) and finish: the line goes and the jumps get their collision back |
| Ctrl+E | Record a new cross country (eventing) course | As Ctrl+J |
| Ctrl+K | | Drop everything after the nearest recorded point and record on from it |
| Ctrl+Backspace | Delete the course within 40 m, after a yes/no question | |

A cross country course is recorded the same way over cross country fences: each pair of a red and a
white flag (the fence runs between them), log piles and drop walls. Their flags' height guides show
while you edit. Only obstacles placed from this mod (log piles, drop walls, show jumps) lose their
collision while you edit; a map or other mod's obstacle marked with flags stays solid, so ride round it. Edit, delete and the round work as for show jumping, but by eventing rules: the time
allowed is at 520 m a minute and each second over costs 0.4; there are no rails; a refusal or
run-out costs 20, a second at the same fence 40, and a third there (or a fourth on the course)
eliminates. After a refusal or run-out the fence stays next ("Go back and jump fence N") and must be
jumped again.

A course needs at least 2 fences to save; a new one with fewer keeps recording. A white line runs from the horse to the nearest
recorded point; after a rewind the next point waits until the horse is 5 m on. A jump ridden twice
shows both numbers ("3, 10"). Getting off the horse (or switching away) ends editing and saves what was recorded; Ctrl+J near
the course edits it again and Ctrl+K records on from the nearest point.

The path is kept as points, like AutoDrive's recorder: one every 10 m on a straight, closer as the
horse turns (5, 3, 1.5 and 0.75 m from 2, 5, 10 and 20 degrees). Courses are saved in
rlEquestrian.xml. `eqCourses` lists them and `eqCourses delete <number>` removes one. Editing
works in single player for now.

#### The timed round

Out of edit mode, within 40 m of a saved course you are asked to "Move to the start line to begin
Show Jumping". The start line stands on the route 12 m before fence 1 and the finish line 12 m after
the last fence; both are drawn in gold while they matter, so no objects are needed and a course
can be dressed however you like. Within 12 m behind the start line a 3, 2, 1
countdown runs; crossing it early starts over. After Go! you have 45 seconds to cross it, and the
clock starts as you do. Thin glowing gold poles stand at the next fence's flags (up to the bottom of the pennants) with a faint bar between them at the fence height, its number beside it, and the way to it is drawn in gold. Fences count whichever way you jump them; another fence of the course jumped the recorded way out of order eliminates.

| Fault | Penalty |
| --- | --- |
| Rail down (knocking or landing on the show jump; a crash into anything else is no fault) | 4 |
| Refusal (running into the next fence, within 3 m of its poles) or run-out (going past its end: a fence only counts between its flags) | 4; a second eliminates |
| Jumping another fence of the course, the right way, out of order | Eliminated |
| Each second (or part) over the time allowed | 1 |
| Over twice the time allowed, or not starting within 45 s | Eliminated |

The time allowed is the course length at 350 m a minute (at least 20 s). A finished round pays
agility training worth 12 top-combo show jumps, less 5% per fault (nothing at 20 faults or when
eliminated), on top of the jumps themselves. The result shows for 8 seconds, then the next round
can start.

### How stats change riding

Speed sets a horse's top speed (about 10% slower than the base game at 10, 20% faster at 100);
agility sets how high it jumps and how quickly and tightly it turns (up to 1.65 times, with the
turning circle at every gait shrinking to match); a calm horse (temperament) turns up to 1.2 times
better again, changes pace a little quicker and stands less long after a knock. Canter jumps go higher than the base game's, so a
horse can clear fences without a full gallop. The base game ignores gait keys in the air, so a
press of W or S while jumping (below a gallop) is kept, lights the gait it will land into on the
bar, and takes effect the moment the horse lands. A gallop jump from the bottom third of the bar
(Pushing or Recovering) makes exertion plummet (45 a second) and S queues a canter too: it is made
on landing if exertion is down to the canter line, within 1.5 s. In the air the horse also turns
on A and D at 1.2 times its ground turn rate on top of the base game's turning.

### Staff, age and metabolism

- **Helpers** (the base game's Animal Workers with Riding turned on for a horse pen, or RLRM's
  herdsman horse-care rule) are stable kids keeping horses active: on a day they fill the whole
  riding bar they give 0.08 effort in every stat (a good minigame session is about 1.5), up to 60%
  of each ceiling. They count for whatever share of the riding bar you did not fill yourself.
- **Hired staff** are much better: see [Hired staff](#hired-staff) below. Your riding and staff
  add up: the bigger gain counts in full and the smaller at half, so riding a horse that has a
  groom and a trainer is best. Only your riding takes a stat to its ceiling.
- **Staff bring loose horses home.** A horse you ride and leave out in the world stays there
  overnight, unless you pay Animal Workers (Riding or Grooming) on one of your horse pens or have
  a groom: when they do their round, they fetch your loose horses back to their own pen (or the
  nearest staffed pen with room) and look after them with the rest.
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
  shows it as Retired everywhere for good (the `eqRetire <horse> undo` debug command brings it back with its old role). The role also shows in RLRM's other lists (unless RLRM has a mark there), on the
  Skills box when you look at the horse, in the menu's Skill potential column and at the top of
  the riding panel, with the horse's four skills.
- **Staff can work on a role.** A groom or trainer set to a role works on every horse with that
  role (not retired ones). Each role also keeps a profile of the stats it is about, which the
  `eqFocus` command shows.

### Hired staff

Hire grooms, event trainers, a vet and a broker on the **Equestrian Staff** tab of RLRM's menu:
**Hire** lists the candidates (Decline turns one down; the place refills at the usual hourly rate), **Your staff** your team (both grouped by job, best first), with
Let go. Each person's ten skills show beside the table, and for your staff the controls below. The `eqStaff` console commands do the same. Host only
for now in multiplayer.

- **Jobs.** A groom trains all four stats and cleans horses. A Dressage, Show Jumping, Cross
  Country or Racing trainer trains that event's two main stats (Dressage: temperament and agility;
  Show Jumping: agility and temperament; Cross Country: stamina and agility; Racing: speed and
  stamina; Racing covers steeplechase, Eventing uses the other three). A farm can have only one vet
  and one broker.
- **Skills.** Everyone has ten skills from 0 to 100: the four stats, the four event types,
  Veterinary and Broker. A job's main skills depend on the grade: Junior 25-45 (60% of
  candidates), Experienced 40-65 (28%), Senior 60-80 (10%), Legendary 80-100 (2%). Other skills are
  0-40% of the grade's middle level, and each has a 15% chance to be a talent at 50-90%.
- **Wages.** Per day, by job (groom 200, trainer 450, vet 600, broker 400) times the grade
  (x1, x1.8, x3, x5), their skills, 4% per talent and up to 15% luck either way. Paid daily, as
  Horse Staff Wages in Finances, so a junior groom just for the cleaning is cheap. No hiring fee; let staff go at any time.
  A vet's or broker's wage is spread over the month: with 28 days per month, each day costs 1/28 of it
  (at least 5), since they help per event or deal rather than per day of training.
- **Candidates.** Six are on offer, shared by every farm: 2-3 grooms, 2-3 trainers (never two
  for the same event) and now and then a vet or broker (30% for each spare place). Each stays on
  offer 12 to 72 game hours (Time remaining on the Hire tab). When a place is free, someone new
  turns up with a 25% chance each hour, so people come and go a few at a time.
- **Works on.** Like RLRM's Herdsman: **Stables** picks the stables (all by default), and **By
  role** ticks roles (with how many horses have each, retired horses left out) or **Individual**
  ticks horses. A new hire works on every horse. The horses they work on share their full work:
  up to 4 horses each get all of it, more share it (8 horses get half each). Every other horse
  gets 20% of it.
- **Status.** Disabled staff do no work (no training, cleaning, event bonus, vet or broker) and
  get half pay. A switch takes effect at 01:00 the next morning and lasts at least a day, so it
  can't be timed around the day's training, the grooms' round or the wages.
- **Training.** Per day, a trainer gives 0.5 x skill/100 effort in its two stats, and anyone gives
  0.35 x skill/100 in the other stats (so a groom trains everything, and a talented trainer
  helps a little elsewhere). Each person trains a stat up to 60% + 35% x skill/100 of its
  ceiling (Junior about 72%, Legendary about 92%).
- **Diminishing returns.** On one stat the best person's gain counts in full, the second at 40%
  and any more at 10% each, helpers included. A second groom on the same horse adds little.
- **Cleaning.** In the last hour of the day each groom cleans up to 8 horses, the ones they work on
  first. Clean horses count as groomed, and grooms bring loose horses home.
- **Vet.** Works on every horse without being told. A vet at Veterinary 100 cuts the chance of an
  injury at events by 40%, and an injury's rest and treatment fee by 35% (less at lower skill).
  The Events tab's injury risk includes it.
- **Broker.** Works without being told too. At Broker 100 the dealer's "Potential (dealer's view)"
  you see moves 70% of the way to the truth, and a bought horse's real potential shows 2 months
  sooner (never before 1 month). The dealer's prices stay on the dealer's own view. Horses also
  cost up to 5% less from the dealer and sell for up to 5% more (only once you have had the horse
  a month, so buying to sell back gains nothing).
- **Others' vet and broker skill.** The farm's Veterinary and Broker stack over everyone like
  training (best in full, then 40%, then 10%), so a groom with a talent helps a little.
- **Event bonus.** Trainers focus on their two stats but train the others a little, and coach for events: at skill 100 a trainer working on a horse adds 4
  points to the event's most important stat in that month's events, less to the others by the
  event's weights (20% for horses they don't work on). Races use Racing, Eventing the average of
  Dressage, Show Jumping and Cross Country. A trainer helps in another event by their skill in it.
  With Peak form from your riding (up to 8) the bigger counts in full and the smaller at half, up
  to 10 points.
- **All skills count.** Duties are only what a job is best at: everyone uses all ten skills. Grooms
  coach for events by their event skills, and the vet and broker train and coach every horse at the
  20% rate for horses staff aren't set to work on.

### Riding bar and names

- When a horse's riding bar is full it trains no more that day: the look-at Skills box says so in
  red, the Daily riding value reads "100 % - full" (red in RLRM's menu) and the riding panel shows
  a red line. Everything earned before it filled is kept: jumps, routines and stamina count as
  they happen, and a Sprint running when the bar fills is banked at once at the multiplier it had
  reached ("Speed xN!" beside the panel).
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
| Cross country course (the shop's log piles and drop walls) | Stamina, Agility; Speed while riding round it. Eight fences give the full bonus | Cross Country, Eventing |
| Round pen (the base game's round roofed barn02, on any map: Elmcreek 25, Frontier) | Temperament; a little Agility | Dressage |

Plain stables (the Horse Stable mod, the Equestrian Pack L barn) only house horses and give no
bonus.

Cross country fences: Cross Country Flags is a spline fence, placed like the base game's pillar
fences, whose segment types (N/M) are a white flag, a gold bar for a 0.6, 0.9 or 1.2 m fence, and a
red flag. Place a white flag, stretch a bar over anything you want jumped (a map's logs, a table or
hedge from any mod), then place a red flag. Each red flag pairs with the nearest white flag 1 to
15 m away and the line between them is the fence; the bar nearest its middle gives its height
(`eqXcFences` lists them). A pair with no bar between is a gate: ride between the flags; in a round only its poles glow. The bars show only in construction mode and while a course is edited; the flags hide like the other pieces (below). The flags
and bars have small collision boxes so they can be picked to delete. The cross country pieces
(flags, log piles, drop walls) can be placed on land you don't own (`EqPlaceAnywhere` lets their
land ownership error through; other placement errors still apply). The shop's log piles (0.71 m and 1.00 m) are solid fences with their own pair of flags.
Drop walls (0.8, 1.2 and 1.6 m) are plank retaining walls for a drop: sculpt a bank, set the wall
on its flat top with the lip at the edge (the lip is 1 m in front of the placement point), and the
triangle side walls hide the steep sculpted slope. A plank deck covers the top, so the bank top
needn't be flat. The terrain is not levelled. The face, deck and side walls are solid: the horse
rides over the deck and drops off the lip.

Hidden pieces: the cross country pieces (flags, log piles, drop walls) are hidden with no collision
while you just ride or drive around, so a course can cross the map without leaving flags and logs
everywhere (`EqXcHide`). They show in construction mode (with collision, to pick and sell), while
a course is edited (seen but ridden through), and in a round from 60 m before the start line to the
result (with collision). Buy a log pile or drop wall with the shop's **Always visible: Yes**
configuration to keep it in the world all the time; the flags always hide. In multiplayer they
always show. Show jumps are never hidden. A vehicle left on a hidden piece can be thrown when its
collision comes back. Road traffic is switched
off from crossing a cross country round's start line to its finish and back on after (the savegame's traffic
setting is not changed).

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
- **Eventing** is scored the real way, in penalties, and the lowest total wins. Dressage gives
  marks: about 22 for the best test, more the further behind it a horse is. Show jumping gives 4
  for each fence down or refusal plus a penalty a second over the time; cross country 20 for a
  refusal plus 0.4 a second over the time. About 40% of show jumping rounds are clear and about
  1 in 10 horses has a cross country refusal. The Results tab shows the scoresheet: each phase's
  place and penalties ("Cross Country: 6th, 21.2 penalties (1 refusal, 1.2 time)"), then the
  total. A horse eliminated on the cross country gets no total. The rules are
  `EqPerformance.PHASE_SCORING`.
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

### Hosting your own event

The Events tab's third tab, **Host**, lists every event your farm could host: Dressage, Show
Jumping, Cross Country or a 3 Day Event, each at **Novice**, **Intermediate** or **Championship**
(the rules are `data/hosting.xml`, read by `EqHosting`).

| Rating | Field | Setup fee | Dressage arena | Show jumps | Cross country | Bleachers |
| --- | --- | --- | --- | --- | --- | --- |
| Novice | 8 | 5,000 | 15x30 | 6 | 1000 m, 20 jumps | 0 |
| Intermediate | 16 | 20,000 | 20x40 | 10 | 2000 m, 30 jumps | 1 |
| Championship | 32 | 80,000 | 20x60 | 12 | 3000 m, 40 jumps | 2 |

- **Courses** are the ones you record by riding (Ctrl+J); the best one that qualifies counts.
  **Arenas** are our dressage arenas and Riding Hall letter boards. **Bleachers** count within
  60 m of a course or arena; an indoor arena counts as one. A 3 Day Event needs all three, with
  seating at both the arena and the show jumping course, and costs 1.5x to set up.
- **Bleachers:** the shop's Horses tab has our own, 3 rows x 6 m, 5 x 10 m and 8 x 16 m (any
  placeable named like a bleacher, grandstand or tribune counts too). Their sponsor boards show the
  brands of the farm's machines, most owned first, then other brands from the game.
- Two places are yours; every other place is a visiting horse, which needs a **free stable place**
  in your horse pens and a month of **horse feed** (troughs and silos both count).
- **Popularity** (0-100): 30 to start, up to 15 for a course or arena beyond the minimum, up to
  15 for extra bleachers or an indoor arena, up to 10 for horse facilities, and your hosting
  reputation. It sets the turnout (half the visiting places at 0, all at 100) and so the takings:
  each visitor's entry fee (double for a 3 Day Event) plus each bleacher's gate. The Host list
  shows the most an event could take (at popularity 100); its details show the expected takings
  at today's popularity, which can still change before the event.
- **Booking:** one event at a time, from next month up to a year ahead, and at least the
  **Months between hosted events** setting (3, 4, 6 or 12; default 6) after your last one.
  Booking pays the setup fee. Cancelling two or more months ahead refunds half; later, nothing.
- When its month starts the event opens on the Upcoming tab as "Show Jumping at <your farm>".
  Your horses enter with one **Enter** button: no fee, no transport, and they stay at home. It
  counts toward Entries per month, and results come at the end of the month with the other
  monthly events.
- **The event month:** your farm is checked when the event opens and every day after. If
  anything is short (including that day's feed for the visitors) you get a warning; still short
  the next day, the event is cancelled and your reputation drops 15. Each day the visitors eat
  a month's horse ration divided by the days in a month, taken from your silos first, then your
  horse troughs.
- **Results:** at the end of the month popularity is worked out again, plus 10 if one of your
  entries is rated 90 or more for the event, and minus 10 for cross country in winter. That sets
  how many visitors came (the field is them plus your entered horses). Their entry fees and the
  gate are paid to you, and your reputation rises 8 (from -25 up to 20). The event is run even
  if none of your horses entered. **Your events**, at the top of the Results tab, shows each
  one's winners, turnout, takings against the setup fee, and how your horses did.
- **Ride it yourself:** while the event runs, a round you ride on one of your entered horses,
  on a course that meets the rating, is that horse's show jumping or cross country, with its
  real faults and time. In an arena big enough, the dressage test is the rating's length (15,
  20 or 25 movements) and scores 22 plus 6 for each fault; a third fault eliminates. Each horse
  gets one go at each phase, and later rounds are practice. Phases you don't ride are
  simulated. A one-phase event with a ridden round is scored in penalties like eventing, and
  your round is placed against the simulated field. Coming up to the start line on an entered
  horse, a gold announcement says whether this round counts, is practice (phase already
  ridden) or the course is too small; the finish says what was kept and when results come.

Console: `eqHostCheck [type] [rating]` prints what your farm has against each requirement.

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
- **Retirement is your choice, and permanent:** the Retire button on the horse's Diseases page
  (or `eqRetire <horse>`) retires a horse after a warning that it can't be undone, and the button
  then goes away. Only the `eqRetire <horse> undo` debug command brings a horse back.
  An injured horse still has to heal, but retired, its treatment costs 60% less, even mid-course.
- **Forced retirement** is off by default. With `eqSettings forcedRetirement on`, 1 in 10 chip
  fractures and 1 in 4 torn suspensories end a horse's career. `eqSettings injuries off` turns injuries off entirely.

