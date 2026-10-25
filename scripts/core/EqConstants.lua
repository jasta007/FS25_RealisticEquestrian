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

-- Trained level a newborn foal starts every stat at.
EqConstants.FOAL_TRAINED = 10

-- Hired staff (the animal worker, RLRM's herdsman) can train a stat up to this share of its
-- ceiling; only the player's own riding reaches the rest.
EqConstants.STAFF_CAP = 0.95

-- Age gates in months.
EqConstants.AGE_GROUNDWORK = 24
EqConstants.AGE_MIN_COMPETE = 36
EqConstants.AGE_PEAK_END = 144
EqConstants.AGE_DECLINE = 192

-- Save file written beside RLRM's in the savegame folder.
EqConstants.SAVE_FILENAME = "rlEquestrian.xml"
EqConstants.SAVE_VERSION = 1

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

-- A dealer horse arrives green: each stat starts at this share of its ceiling (times how
-- mature the horse is), well below a home-produced horse of the same age.
EqConstants.DEALER_TRAINED_MIN = 0.25
EqConstants.DEALER_TRAINED_MAX = 0.5

-- The dealer's view of a stat's potential: usually right, sometimes generous, now and then
-- modest. Chances and ranges in ceiling points.
EqConstants.ADVERT_GENEROUS_CHANCE = 0.25
EqConstants.ADVERT_GENEROUS_MIN = 3
EqConstants.ADVERT_GENEROUS_MAX = 7
EqConstants.ADVERT_MODEST_CHANCE = 0.15
EqConstants.ADVERT_MODEST_MIN = 2
EqConstants.ADVERT_MODEST_MAX = 5

-- Months a bought horse is with you before its real potential shows, and before it can compete.
EqConstants.REVEAL_MONTHS = 3
EqConstants.SETTLE_MONTHS = 1

-- Value. A horse's price is RLRM's, plus a premium for talent and schooling on top of the
-- subtype's base price for its age. Talent is the mean of the two best ceilings: 75 is worth the
-- base price, and every VALUE_DOUBLING points more doubles it.
EqConstants.VALUE_PIVOT = 75
EqConstants.VALUE_DOUBLING = 7.5
EqConstants.VALUE_MIN_FACTOR = 0.4
EqConstants.VALUE_MAX_FACTOR = 12
-- Schooling: an untrained horse is worth SCHOOL_BASE of its talent value, a fully schooled one
-- SCHOOL_BASE + SCHOOL_RANGE. A green dealer horse of talent 75 comes out near RLRM's own price.
EqConstants.SCHOOL_BASE = 0.85
EqConstants.SCHOOL_RANGE = 0.6
-- Past its peak a horse's talent premium shrinks, to this share by AGE_DECLINE.
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
