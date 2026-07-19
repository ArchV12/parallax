extends Node

# Mining's data model — session-scoped registry of per-body/material
# depletion, and the derivation rules that turn a Resource Survey's already-
# authored ResourceMaterialFinding rows into DepositInfo records. Kept
# separate from Research.gd deliberately: Mining awards materials, never
# Knowledge, and folding a materials inventory into Research.gd would blur
# that boundary the same way GeologicalSurveyData/ResourceSurveyData are
# already kept as separate schemas rather than one forced-generic one.
#
# Given a body that's already been Resource Surveyed, deposits_for() derives
# what's minable there (never hand-authored, never a second copy of the
# survey's own findings — see DepositInfo's own comment). Mining itself is a
# CONTINUOUS operation (Operations._tick_mining ticks it every frame while
# RUNNING, not a single resolve step) — extraction_rate_per_second/
# depletion_rate_per_second are the two numbers that drive that tick;
# extract_tick() is the only thing that ever changes over a playthrough
# (remaining_fraction depleting, the player's material inventory growing).

# Deposit Size — a direct relabeling of the survey's own Abundance finding
# (5 values in, 5 tiers out, no compression — a "Trace" abundance finding is
# a "Trace" deposit) — how much total material a deposit holds AND how fast
# it comes out both derive from this one tier (see TOTAL_UNITS_BY_SIZE/
# DEPLETE_SECONDS_BY_SIZE below): a "Massive" deposit isn't just bigger, an
# operation of that scale also pulls material out in bulk, so extraction
# time only grows modestly (5 -> 20 min) even as total swells 1000x.
const DEPOSIT_SIZE_BY_ABUNDANCE := {
	"Trace": "Trace",
	"Confirmed": "Small",     # presence-only fact (e.g. ice) — a real but modest claim
	"Moderate": "Moderate",
	"Common": "Large",
	"Abundant": "Massive",
}
const DEFAULT_DEPOSIT_SIZE := "Moderate"

const DIFFICULTY_BY_NOTE_VALUE := {
	"Favorable": "Easy",
	"Difficult": "Hard",
}
# Materials whose ResourceMaterialFinding pairs abundance with something
# other than an "Extraction" note (Water Ice today, paired with "Location"
# instead — see ResourceMaterialFinding's own comment) have no extraction
# note to translate at all. Moderate: harder than a flagged-Favorable metal,
# easier than a flagged-Difficult one, and leaves room for a later "Deep
# Vein"-style progression (Docs/Mining.md) to improve it. Also feeds
# DIFFICULTY_TIME_MULT below (2026-07-14) — used to be flavor-only (just
# energy_usage_label); see that constant's own comment.
const DEFAULT_EXTRACTION_DIFFICULTY := "Moderate"

# How much longer/shorter a deposit takes to fully deplete based on how hard
# it is to extract — layered on TOP of depletion_seconds' existing size- and
# floor-derived duration, not a replacement for it: Deposit Size still says
# "how much material is there" (and a bigger deposit legitimately taking
# longer to fully extract is worth keeping); this says "how hard is it to
# pull out," independently. total_units() is untouched by difficulty — a
# Hard deposit still yields the exact same total as an Easy one of the same
# size, just spread across more real time, which automatically comes out as
# a slower rate too (extraction_rate_per_second already derives from
# total_units/depletion_seconds — see that function's own comment).
const DIFFICULTY_TIME_MULT := {
	"Easy": 0.75,
	"Moderate": 1.0,
	"Hard": 2.0,
}

# Total units obtainable from a FRESH (remaining_fraction == 1.0) deposit if
# mined continuously all the way to full depletion. Big numbers on purpose —
# "10 Iron" read far too small for an operation at this scale; see
# DEPLETE_SECONDS_BY_SIZE for how long each tier takes to fully drain.
const TOTAL_UNITS_BY_SIZE := {
	"Trace": 1000,
	"Small": 10000,
	"Moderate": 50000,
	"Large": 250000,
	"Massive": 1000000,
}

# Real-world seconds a FRESH deposit of this size takes to fully deplete
# under continuous mining. A partially-depleted deposit takes proportionally
# less absolute time to finish (see depletion_rate_per_second — the RATE is
# constant, only the remaining time shrinks).
const DEPLETE_SECONDS_BY_SIZE := {
	"Trace": 300,     # 5 min
	"Small": 480,     # 8 min
	"Moderate": 720,  # 12 min
	"Large": 900,     # 15 min
	"Massive": 1200,  # 20 min
}

const ENERGY_LABEL_BY_DIFFICULTY := {
	"Easy": "Low",
	"Moderate": "Moderate",
	"Hard": "High",
}

# --- Body-size yield scaling (2026-07-13) ---
# A body at exactly this real radius gets multiplier 1.0 — today's already-
# tuned TOTAL_UNITS_BY_SIZE numbers stay exactly as they are for anything
# Earth-scale. Smaller/larger real bodies scale their yield by real radius
# relative to this, so "a big planet has more, a tiny asteroid has way
# less" falls out of one formula instead of per-body-type special-casing —
# see _size_multiplier/total_units below, and AsteroidResourceGenerator for
# where a procedural asteroid's own radius comes from.
#
# LINEAR with radius, not real volume (radius CUBED, which is what actual
# physical mass/volume scaling would be) — literal cubic scaling against
# Earth crushes anything asteroid-scale (thousands of times smaller by
# volume) down to fractions of a single unit, reading as broken rather than
# "tiny." This is the same real-world-INSPIRED-not-LITERAL compromise the
# rest of the game already makes (compressed AU distances, sped-up orbits,
# TravelCalc's engine tiers) — directionally correct (bigger body, more
# material) without collapsing to zero across the many orders of magnitude
# of real radius a planet-to-asteroid range actually spans.
const SIZE_REFERENCE_RADIUS_KM := 6371.0  # Earth
const SIZE_EXPONENT := 1.0

# Floor on how long a deposit takes to fully deplete, real seconds —
# legibility, not economy: below this, a continuous-mining operation
# resolves faster than a player can actually watch the percentage/amount
# readouts move (2026-07-14, reported as "mining on asteroids finishes
# before I can even see the numbers"). The OLD floor lived directly on
# depletion_rate_per_second's own scaled_seconds at a bare 1.0 — reasonable
# as a rare edge-case guard when it was written, but every asteroid in the
# actual 0.3-20km radius range (AsteroidResourceGenerator.RADIUS_MIN/MAX_KM)
# scales to well under 1 real second at Earth-reference linear scaling, so
# in practice EVERY asteroid deposit was hitting that floor — collapsing
# Trace/Small/Moderate/Large/Massive into the same near-instant blip instead
# of the tiered pacing DEPLETE_SECONDS_BY_SIZE actually intends. See
# depletion_seconds/extraction_rate_per_second for the other half of this
# fix — raising the time floor ALONE (leaving extraction_rate_per_second at
# its old constant base-tier rate) would have kept awarding the old
# base-tier rate over the new, longer floor time, handing out MORE than
# total_units() actually reports for that deposit. Worth tuning further by
# feel, same as every other by-feel constant in this file.
const MIN_DEPLETE_SECONDS := 12.0

# Companion fix to MIN_DEPLETE_SECONDS above, same 2026-07-14 report — total_
# units() used to floor at a bare 1, which combined with the whole-units-
# only inventory (Operations._tick_mining only ever credits Deposits once
# mining_yield_accumulator crosses a full 1.0) meant a Trace deposit on a
# small asteroid spent the ENTIRE MIN_DEPLETE_SECONDS reading "+0", then
# jumped straight to "+1" in a single lump right at the very end — visually
# indistinguishable from broken, and an unsatisfying reward for a dedicated
# 12-second operation regardless.
#
# A FRACTION of each tier's own TOTAL_UNITS_BY_SIZE base, not one flat
# number shared by every tier — a flat floor (this fix's first pass) still
# preserved the "+0 the whole time" glitch's SIZE symptom, but introduced a
# new one: small enough asteroids collapsed Trace and Moderate to the
# identical floor value, losing the whole point of having size tiers at
# all once a body got small enough. This keeps TOTAL_UNITS_BY_SIZE's own
# 1:10:50:250:1000 ratio intact at 1% of it instead — Trace lands at 10
# (same number the flat version picked), but Moderate now floors at 500 and
# Massive at 10,000, so a richer tier still visibly means more even in the
# extreme-small-body case this floor exists for.
const MIN_UNITS_FRACTION := 0.01

# 2026-07-14 — the ship's cargo hold isn't infinite. Total units across
# EVERY material combined, same "ship-wide, not per-body" shape inventory()
# itself already has. Operations._tick_mining is what actually enforces
# this during a running operation (stops the instant the hold would exceed
# it — see that function); this file just tracks the number.
#
# 2026-07-18 — scaled by Cargo Hold equipment tier (Docs/Ship Equipment.md)
# instead of the old flat 20,000: 5,000 at T0 up to 100,000 at T4, linear
# (23,750/tier). A first-guess curve, not playtested — easy to retune, it's
# just the one array. cargo_capacity() replaces the old CARGO_CAPACITY
# constant; callers now call the function instead of reading a constant.
const CARGO_CAPACITY_BY_TIER: Array[int] = [5000, 28750, 52500, 76250, 100000]

var _remaining_fraction: Dictionary = {}  # "body_id:material_name" -> float
var _material_amounts: Dictionary = {}    # material_name -> int, player's running inventory


func reset_for_new_game() -> void:
	_remaining_fraction.clear()
	_material_amounts.clear()


# Every deposit derivable at this body right now — empty if no Resource
# Survey has ever resolved here (Research.resource_data_for returns null),
# same "nothing to show" honesty as Research's own *_data_for methods.
# Further filtered to whatever the player's CURRENT Scanner Array tier can
# actually detect (see ResourceMaterialFinding.min_scanner_tier) — a body
# surveyed back at T0 silently grows more entries here the moment the
# player upgrades, no re-survey required.
func deposits_for(body_id: String) -> Array[DepositInfo]:
	var result: Array[DepositInfo] = []
	var survey := Research.resource_data_for(body_id)
	if survey == null:
		return result
	for finding: ResourceMaterialFinding in survey.materials:
		if _is_detected(finding):
			result.append(_build_deposit(body_id, finding))
	return result


# A single named deposit at a body, or null if that material was never
# detected there (the body has no survey at all, or the player's current
# Scanner Array tier can't pick it out yet — see min_scanner_tier).
func deposit_for(body_id: String, material_name: String) -> DepositInfo:
	var survey := Research.resource_data_for(body_id)
	if survey == null:
		return null
	for finding: ResourceMaterialFinding in survey.materials:
		if finding.material_name == material_name and _is_detected(finding):
			return _build_deposit(body_id, finding)
	return null


func _is_detected(finding: ResourceMaterialFinding) -> bool:
	return finding.min_scanner_tier <= Research.owned_tier("scanner_array")


func _build_deposit(body_id: String, finding: ResourceMaterialFinding) -> DepositInfo:
	var deposit := DepositInfo.new()
	deposit.body_id = body_id
	deposit.material_name = finding.material_name
	deposit.deposit_size = DEPOSIT_SIZE_BY_ABUNDANCE.get(finding.abundance, DEFAULT_DEPOSIT_SIZE)
	if finding.note_label == "Extraction":
		deposit.extraction_difficulty = DIFFICULTY_BY_NOTE_VALUE.get(finding.note_value, DEFAULT_EXTRACTION_DIFFICULTY)
	else:
		deposit.extraction_difficulty = DEFAULT_EXTRACTION_DIFFICULTY
	deposit.remaining_fraction = _remaining_fraction.get(_key(body_id, finding.material_name), 1.0)
	return deposit


# --- Mining System equipment tier scaling (2026-07-18, Docs/Ship
# Equipment.md) --- Two independent levers, "faster AND bigger haul":
# MINING_TIME_MULT_BY_TIER shrinks depletion_seconds per tier (T0
# unchanged); MINING_YIELD_MULT_BY_TIER grows total_units() per tier
# instead (see that function). Since extraction_rate_per_second is
# total_units/depletion_seconds, the two compound automatically — more
# material, arriving faster — without any extra wiring.
#
# The time multiplier is applied INSIDE depletion_seconds' MIN_DEPLETE_
# SECONDS floor (see below), not after it — a top-tier rig meaningfully
# shrinks a Massive deposit's minutes-long extraction, but can never push
# a floor-bound tiny-asteroid deposit below that floor. The floor's whole
# job is legibility (2026-07-14 report: "mining finishes before I can
# even see the numbers move" — see MIN_DEPLETE_SECONDS' own comment), and
# that guarantee should hold at every equipment tier, not just T0.
const MINING_TIME_MULT_BY_TIER: Array[float] = [1.0, 0.8, 0.6, 0.4, 0.2]
const MINING_YIELD_MULT_BY_TIER: Array[float] = [1.0, 1.125, 1.25, 1.375, 1.5]


func _mining_tier() -> int:
	return clampi(Research.owned_tier("mining_system"), 0, MINING_TIME_MULT_BY_TIER.size() - 1)


# How long this SPECIFIC deposit (its own size tier, at its own body's real
# scale, at its own extraction difficulty, at the player's own Mining
# System tier) takes to fully deplete under continuous mining — the base
# tier duration scaled by the same _size_multiplier as total_units AND the
# current MINING_TIME_MULT_BY_TIER speed bonus, floored at
# MIN_DEPLETE_SECONDS for legibility (see that constant's own comment),
# THEN scaled again by DIFFICULTY_TIME_MULT (applied last, after the
# floor, so difficulty still has an effect even on a floor-bound tiny
# asteroid deposit — a Hard Trace deposit takes noticeably longer than an
# Easy one even though both would otherwise floor to the identical
# MIN_DEPLETE_SECONDS). The one shared duration both rate functions below
# derive from, so they can never diverge from each other the way
# independently-floored numbers could.
func depletion_seconds(deposit: DepositInfo) -> float:
	var seconds: int = DEPLETE_SECONDS_BY_SIZE.get(deposit.deposit_size, DEPLETE_SECONDS_BY_SIZE[DEFAULT_DEPOSIT_SIZE])
	var time_mult := MINING_TIME_MULT_BY_TIER[_mining_tier()]
	var base_duration := maxf(float(seconds) * _size_multiplier(deposit.body_id) * time_mult, MIN_DEPLETE_SECONDS)
	var difficulty_mult: float = DIFFICULTY_TIME_MULT.get(
			deposit.extraction_difficulty, DIFFICULTY_TIME_MULT[DEFAULT_EXTRACTION_DIFFICULTY])
	return base_duration * difficulty_mult


# Units per real second a continuous mining operation on this deposit
# awards — this deposit's own (size-scaled) total_units spread evenly across
# its own (size-, floor-, AND difficulty-scaled) depletion_seconds, so
# extraction ALWAYS finishes with exactly total_units in hand right as
# remaining_fraction hits 0, never more or less, regardless of which of
# size/floor/difficulty is doing the work that particular deposit. At
# Moderate difficulty with MIN_DEPLETE_SECONDS not engaged, this reduces to
# exactly the original constant base-tier rate (total_units and
# depletion_seconds both scale by the identical _size_multiplier, which
# cancels, and DIFFICULTY_TIME_MULT["Moderate"] is 1.0) — same rate on a
# planet regardless of which specific planet. Easy/Hard shift the rate up/
# down from there for the SAME total, and the floor engaging (small
# asteroids) drops it further still — see MIN_DEPLETE_SECONDS and
# DIFFICULTY_TIME_MULT for why each exists.
func extraction_rate_per_second(deposit: DepositInfo) -> float:
	return float(total_units(deposit)) / depletion_seconds(deposit)


# Fraction of remaining_fraction consumed per real second — constant
# regardless of how much is already left, so a half-depleted deposit simply
# takes half as long (in absolute seconds) to finish, not the same duration
# every time.
func depletion_rate_per_second(deposit: DepositInfo) -> float:
	return 1.0 / depletion_seconds(deposit)


# The actual (size-scaled) total this deposit holds fresh — what
# DepositDetailPanel's "Total Deposit" readout shows, and the only place
# TOTAL_UNITS_BY_SIZE's raw tier number gets adjusted for body size. Floored
# at MIN_UNITS_FRACTION of that SAME tier's own base (see that constant's
# own comment for why a flat number across every tier wasn't enough) — a
# survey that found something at all should never display as a literal
# zero- or one-unit deposit, even on the smallest possible asteroid, but
# the floor still has to keep a "Massive" reading bigger than a "Trace" one.
# MINING_YIELD_MULT_BY_TIER (see that constant's own comment) is applied
# last, after size-scaling and its floor — the player's current Mining
# System tier means the SAME deposit yields more, not a special case for
# small deposits only.
func total_units(deposit: DepositInfo) -> int:
	var base: int = TOTAL_UNITS_BY_SIZE.get(deposit.deposit_size, TOTAL_UNITS_BY_SIZE[DEFAULT_DEPOSIT_SIZE])
	var floor_units := roundi(float(base) * MIN_UNITS_FRACTION)
	var size_scaled := maxi(floor_units, roundi(float(base) * _size_multiplier(deposit.body_id)))
	return roundi(float(size_scaled) * MINING_YIELD_MULT_BY_TIER[_mining_tier()])


func _size_multiplier(body_id: String) -> float:
	var radius_km := _real_radius_km_for(body_id)
	var ratio := maxf(radius_km, 0.001) / SIZE_REFERENCE_RADIUS_KM
	return pow(ratio, SIZE_EXPONENT)


# Real radius for whatever body_id is. KnownBodies.get_entry now covers
# both curated bodies AND registered asteroids on its own (it synthesizes
# an Entry for the latter from Research's registries) — so this no longer
# needs its own separate asteroid fallback the way it used to. Falls back
# to SIZE_REFERENCE_RADIUS_KM itself (multiplier 1.0) for anything truly
# unresolvable, so an unknown body defaults to "no scaling effect" rather
# than an arbitrary penalty.
func _real_radius_km_for(body_id: String) -> float:
	var entry := KnownBodies.get_entry(body_id)
	if entry != null and entry.real_radius_km > 0.0:
		return entry.real_radius_km
	return SIZE_REFERENCE_RADIUS_KM


func energy_usage_label(deposit: DepositInfo) -> String:
	return ENERGY_LABEL_BY_DIFFICULTY.get(deposit.extraction_difficulty, ENERGY_LABEL_BY_DIFFICULTY[DEFAULT_EXTRACTION_DIFFICULTY])


# One continuous-mining tick's worth of progress — called every frame by
# Operations._tick_mining while a mining operation is RUNNING (never a
# single lump sum the way a survey resolves once). amount is already an
# integer whole-unit delta (Operations accumulates the fractional part
# itself, only calling this when a new whole unit is ready to commit) so the
# player's inventory only ever holds whole numbers; fraction_delta is applied
# every tick regardless, so depletion stays smooth even between whole units.
func extract_tick(body_id: String, material_name: String, amount: int, fraction_delta: float) -> float:
	var key := _key(body_id, material_name)
	var remaining: float = maxf(_remaining_fraction.get(key, 1.0) - fraction_delta, 0.0)
	_remaining_fraction[key] = remaining
	if amount > 0:
		_material_amounts[material_name] = material_amount(material_name) + amount
	return remaining


func material_amount(material_name: String) -> int:
	return _material_amounts.get(material_name, 0)


# Atomic batch spend for Research.craft_technology (and now SellCargoPanel)
# — checks every entry is affordable FIRST, and only subtracts anything if
# all of them are, so a spend attempt can never partially go through then
# fail partway. Returns false (no-op, nothing spent) if any single one is
# short. Erases a material entirely once it hits 0 rather than leaving a
# lingering "0" entry behind — inventory()/total_cargo_used() would both
# have read that identically to it never existing anyway (material_amount
# already defaults missing keys to 0), but a stale 0 entry visibly lingered
# in CargoPanel/SellCargoPanel's own lists forever after being fully spent.
func spend_materials(requirements: Dictionary) -> bool:
	for material_name: String in requirements:
		if material_amount(material_name) < requirements[material_name]:
			return false
	for material_name: String in requirements:
		# requirements[material_name] is an untyped Dictionary value lookup
		# (Variant) — := can't infer a type from it, unlike material_amount()'s
		# own declared int return, so this needs an explicit annotation.
		var remaining: int = material_amount(material_name) - requirements[material_name]
		if remaining <= 0:
			_material_amounts.erase(material_name)
		else:
			_material_amounts[material_name] = remaining
	return true


# The player's whole cargo hold — material_name -> int, ship-wide (not
# broken down by which body it came from; nothing currently needs that
# distinction). A copy, not the live Dictionary, so a caller (CargoPanel)
# can't accidentally mutate inventory state just by iterating it.
func inventory() -> Dictionary:
	return _material_amounts.duplicate()


# Summed across every material — cargo_capacity() is one shared hold, not a
# per-material allowance. Computed fresh from _material_amounts every call
# rather than tracked as a running counter, so it stays correct even though
# the hold can also shrink (spend_materials, crafting) as well as grow.
func total_cargo_used() -> int:
	var total := 0
	for amount: int in _material_amounts.values():
		total += amount
	return total


func cargo_capacity() -> int:
	var tier := clampi(Research.owned_tier("cargo_hold"), 0, CARGO_CAPACITY_BY_TIER.size() - 1)
	return CARGO_CAPACITY_BY_TIER[tier]


func cargo_space_remaining() -> int:
	return maxi(0, cargo_capacity() - total_cargo_used())


func is_cargo_full() -> bool:
	return total_cargo_used() >= cargo_capacity()


func _key(body_id: String, material_name: String) -> String:
	return "%s:%s" % [body_id, material_name]


# Thousands-separated integer — "big numbers feel good for the player" (per
# the user's own framing when deposits were scaled up), so a bare
# "1000000" reading as a wall of digits would undercut the whole point.
# Not static (unlike ActivityDef.format_duration) — every call site reaches
# this through the Deposits autoload singleton, not the script's type
# directly, which is exactly what triggers GDScript's STATIC_CALLED_ON_
# INSTANCE warning on a static func. No internal state needed either way.
func format_units(n: int) -> String:
	var digits := str(n)
	var result := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		result = digits[i] + result
		count += 1
		if count % 3 == 0 and i != 0:
			result = "," + result
	return result
