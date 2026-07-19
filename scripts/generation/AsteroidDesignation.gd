class_name AsteroidDesignation
extends RefCounted

# Real IAU-style provisional designation ("2019 GT3"): year, then a
# half-month letter (A-Y, skipping I — 24 letters for the year's 24
# half-months) and a sequence letter (A-Z, skipping I — 25 letters, cycling
# with a trailing cycle count once a half-month's 25 slots run out). We have
# no real discovery date to derive this from, so every component is instead
# seeded off the asteroid's own id — stable and repeatable, not meaningful
# astronomically the way a real one's letters/date actually are.

const HALF_MONTH_LETTERS := "ABCDEFGHJKLMNOPQRSTUVWXY"  # 24 — skips I
const SEQUENCE_LETTERS := "ABCDEFGHJKLMNOPQRSTUVWXYZ"    # 25 — skips I
# Game's present is YEAR 2037 (BootSequence) — designations are drawn from
# before that so they read as already-catalogued finds, not discovered today.
const YEAR_MIN := 1995
const YEAR_MAX := 2036


static func generate(seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var year := rng.randi_range(YEAR_MIN, YEAR_MAX)
	var half_month := HALF_MONTH_LETTERS[rng.randi() % HALF_MONTH_LETTERS.length()]
	# How far into the half-month's sequence — occasionally rolls far enough
	# to need a cycle suffix, same as a real crowded half-month would.
	var position := rng.randi() % 300
	@warning_ignore("integer_division")  # floor division into a whole cycle count is the intent
	var cycle := position / SEQUENCE_LETTERS.length()
	var seq_letter := SEQUENCE_LETTERS[position % SEQUENCE_LETTERS.length()]
	var suffix := "" if cycle == 0 else str(cycle)
	return "%d %s%s%s" % [year, half_month, seq_letter, suffix]
