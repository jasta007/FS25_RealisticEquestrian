--[[
    EqConstants.lua
    Balance numbers and keys shared by every Realistic Equestrian module.

    Genes use RLRM's genetics scale (RLGenetics.MIN..MAX, 0.25..1.75, average 1.0) so they can
    go straight through RLRM's BreedingMath and band through RLRM's RLGenetics ladder. The
    fallbacks below exist only so the pure modules run headless without RLRM loaded.
]]

EqConstants = {}

-- Canonical stat order. Saves, UI rows and console output all follow it.
EqConstants.STAT_KEYS = { "stamina", "speed", "agility", "temperament" }

EqConstants.GENE_MIN = 0.25
EqConstants.GENE_MAX = 1.75
EqConstants.GENE_MEAN = 1.0

-- Spread of genes rolled for a horse with no recorded parents (dealer, existing saves).
EqConstants.ROLL_SD = 0.22

-- A parent's gene keeps this share of its distance from the mean before inheritance, so two
-- elite parents give a strong foal rather than a reliably better one.
EqConstants.REGRESSION = 0.6

-- Ceiling (0-100) = CEILING_BASE + CEILING_PER_GENE * gene: 40 at the minimum gene, 70 at
-- average, 100 at the maximum.
EqConstants.CEILING_BASE = 30
EqConstants.CEILING_PER_GENE = 40
EqConstants.CEILING_FLOOR = EqConstants.CEILING_BASE + EqConstants.CEILING_PER_GENE * EqConstants.GENE_MIN

-- Talent budget = the most the four ceilings may add up to: 260 at the minimum gene, 290 at
-- average, 320 at the maximum. An average horse (four 70s, 280) is never squeezed. Two stats
-- at 100 fit the best budgets; three top out near 93 and four near 80, so a horse is a
-- specialist or an all-rounder, not both.
EqConstants.BUDGET_BASE = 250
EqConstants.BUDGET_PER_GENE = 40

-- Starting stats: what a horse can already do the first time we see it. Each stat is drawn
-- from a bell curve: around START_FOAL_MEAN for a newborn, widening to START_MEAN with spread
-- START_SD by START_ADULT_MONTHS. A stat leans START_CEILING_LEAN points toward the horse's
-- talent for every ceiling point above or below START_CEILING_PIVOT.
EqConstants.START_FOAL_MEAN = 15
EqConstants.START_FOAL_SD = 4
EqConstants.START_MEAN = 50
EqConstants.START_SD = 13
EqConstants.START_ADULT_MONTHS = 48
EqConstants.START_CEILING_PIVOT = 70
EqConstants.START_CEILING_LEAN = 0.3
EqConstants.START_MIN = 5
-- Every stat of a horse saved before starting stats were drawn sat at this level.
EqConstants.OLD_START_LEVEL = 10

-- Hired staff (the animal worker, RLRM's herdsman) can train a stat up to this share of its
-- ceiling; only the player's own riding reaches the rest.
EqConstants.STAFF_CAP = 0.95

-- Age gates in months.
EqConstants.AGE_GROUNDWORK = 24
EqConstants.AGE_MIN_COMPETE = 36
EqConstants.AGE_PEAK_END = 144
EqConstants.AGE_DECLINE = 192

-- RLRM's metabolism gene (1.0 average) also sets how fast riding builds fitness: each 0.1 above
-- or below average changes fitness gains by METABOLISM_FITNESS_LEAN x 10%, within MIN..MAX.
EqConstants.METABOLISM_FITNESS_LEAN = 0.6
EqConstants.METABOLISM_FITNESS_MIN = 0.6
EqConstants.METABOLISM_FITNESS_MAX = 1.45

-- Save file written beside RLRM's in the savegame folder.
EqConstants.SAVE_FILENAME = "rlEquestrian.xml"
EqConstants.SAVE_VERSION = 2

-- TRAINING (milestone 3)

-- Share of the gap between trained level and cap that a month of full effort closes, in
-- percent. Stamina comes quickest, speed slowest: a horse in full work from 24 months gets
-- most of the way to its ceilings in two to three years.
EqConstants.TRAIN_MONTHLY = { stamina = 12, speed = 8, agility = 10, temperament = 10 }

-- Points a month a stat loses once a horse has stood idle past the grace period, down to
-- FADE_FLOOR of its ceiling. Fitness goes first; manners and speed stay.
EqConstants.FADE_MONTHLY = { stamina = 4, speed = 1, agility = 2, temperament = 1 }
EqConstants.FADE_FLOOR = 0.5
EqConstants.FADE_GRACE_DAYS = 2
EqConstants.FADE_GRACE_MONTHS = 0.5

-- Past AGE_DECLINE every stat loses this many points a month, down to OLD_FLOOR of its ceiling.
EqConstants.OLD_DECLINE_MONTHLY = 2
EqConstants.OLD_FLOOR = 0.3

-- The base game's daily riding target (Rideable / AnimalHorse.getDailyRidingTime): this many
-- gait-weighted milliseconds fill riding from 0 to 100.
EqConstants.RIDING_FULL_MS = 300000

-- Effort per jump taken at canter or gallop: mostly agility, and some temperament, since
-- keeping a horse calm and listening over a jump is manners work too (and walking is dull).
EqConstants.JUMP_AGILITY = 0.04
EqConstants.JUMP_TEMPERAMENT = 0.03

-- A horse whose dirt is at or below this at the day's end counts as groomed, which adds
-- temperament effort (groundwork, so it counts at staff level).
EqConstants.GROOMED_DIRT = 10
EqConstants.GROOMED_TEMPERAMENT = 0.2

-- DEALER HORSES

-- A rolled horse's genes lean toward its RLRM genetics (the average of its RLRM traits, 1.0 is
-- average) by this share, so RLRM's dealer quality setting also sets how talented dealer
-- horses are.
EqConstants.RLRM_GENE_LEAN = 0.35

-- Now and then a rolled horse is a well-bred prospect: its two best genes and its talent
-- budget get this much more.
EqConstants.PROSPECT_CHANCE = 0.08
EqConstants.PROSPECT_BOOST = 0.4

-- A dealer horse arrives a little green: its starting stats' curve sits this many points lower.
EqConstants.DEALER_START_SHIFT = -5

-- The dealer's view of a stat's potential: usually right, sometimes generous, now and then
-- modest. Chances and ranges in ceiling points. A potential word spans 15 points, so errors
-- this size change the word often enough to matter.
EqConstants.ADVERT_GENEROUS_CHANCE = 0.25
EqConstants.ADVERT_GENEROUS_MIN = 6
EqConstants.ADVERT_GENEROUS_MAX = 14
EqConstants.ADVERT_MODEST_CHANCE = 0.15
EqConstants.ADVERT_MODEST_MIN = 5
EqConstants.ADVERT_MODEST_MAX = 12

-- Months a bought horse is with you before its real potential shows, and before it can compete.
EqConstants.REVEAL_MONTHS = 3
EqConstants.SETTLE_MONTHS = 1

-- Value. A horse's price is RLRM's, plus a premium on top of the subtype's base price for its
-- age. The premium blends what the horse can do now (skill: the mean of its two best stats) with
-- what it could do (talent: the mean of its two best ceilings). Skill SKILL_PIVOT is worth the
-- base price and every SKILL_DOUBLING points more doubles it; likewise talent from VALUE_PIVOT
-- by VALUE_DOUBLING.
EqConstants.SKILL_PIVOT = 60
EqConstants.SKILL_DOUBLING = 10
EqConstants.VALUE_PIVOT = 75
EqConstants.VALUE_DOUBLING = 7.5
EqConstants.VALUE_MIN_FACTOR = 0.4
EqConstants.VALUE_MAX_FACTOR = 12
-- Talent's share of the blend: most of a young horse's value, a small part of a made one's.
-- POTENTIAL_WEIGHT_YOUNG up to AGE_GROUNDWORK, falling to POTENTIAL_WEIGHT_ADULT by
-- POTENTIAL_ADULT_MONTHS.
EqConstants.POTENTIAL_WEIGHT_YOUNG = 0.8
EqConstants.POTENTIAL_WEIGHT_ADULT = 0.2
EqConstants.POTENTIAL_ADULT_MONTHS = 96
-- Of that blend, STUD_SHARE is breeding value: an entire horse's talent, gone once he is gelded.
-- The rest is performance value: skill and talent as a riding horse, scaled by how sound the
-- horse is (RLRM's health, our injuries).
EqConstants.STUD_SHARE = 0.25
-- Performance value kept while on box rest; none once an injury has ended the career.
EqConstants.VALUE_INJURED_FACTOR = 0.6
-- Past its peak a horse's premium shrinks, to this share by AGE_DECLINE.
EqConstants.VALUE_OLD_FACTOR = 0.3
-- The total never falls below this share of RLRM's own price.
EqConstants.VALUE_FLOOR = 0.3

-- COMPETITION LOAD

-- Round events a horse may start in one month. Monthly events are separate (one at a time).
EqConstants.MAX_ROUND_STARTS = 2

-- A mare further than this through her pregnancy (RLRM's reproduction, 0-100) stops competing
-- until she has foaled.
EqConstants.IN_FOAL_LIMIT = 30
-- Months after foaling before a mare competes again (RLRM's own recovery is 3 months).
EqConstants.FOALING_REST_MONTHS = 3
