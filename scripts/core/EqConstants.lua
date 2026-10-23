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
