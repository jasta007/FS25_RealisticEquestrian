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
