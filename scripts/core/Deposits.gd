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
# Vein"-style progression (Docs/Mining.md) to improve it. Difficulty is
# flavor only now (drives energy_usage_label) — it does NOT affect
# yield/time, which are purely a function of Deposit Size (see below).
const DEFAULT_EXTRACTION_DIFFICULTY := "Moderate"

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

var _remaining_fraction: Dictionary = {}  # "body_id:material_name" -> float
var _material_amounts: Dictionary = {}    # material_name -> int, player's running inventory


func reset_for_new_game() -> void:
	_remaining_fraction.clear()
	_material_amounts.clear()


# Every deposit derivable at this body right now — empty if no Resource
# Survey has ever resolved here (Research.resource_data_for returns null),
# same "nothing to show" honesty as Research's own *_data_for methods.
func deposits_for(body_id: String) -> Array[DepositInfo]:
	var result: Array[DepositInfo] = []
	var survey := Research.resource_data_for(body_id)
	if survey == null:
		return result
	for finding: ResourceMaterialFinding in survey.materials:
		result.append(_build_deposit(body_id, finding))
	return result


# A single named deposit at a body, or null if that material was never
# detected there (or the body has no survey at all).
func deposit_for(body_id: String, material_name: String) -> DepositInfo:
	var survey := Research.resource_data_for(body_id)
	if survey == null:
		return null
	for finding: ResourceMaterialFinding in survey.materials:
		if finding.material_name == material_name:
			return _build_deposit(body_id, finding)
	return null


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


# Units per real second a continuous mining operation on this deposit
# awards — the BASE tier total spread evenly across the base tier's
# duration, same as before size-scaling existed. Deliberately NOT run
# through _size_multiplier: rate is "how fast your equipment pulls out
# material of this concentration," which doesn't depend on how much total
# deposit there is to work with — same rate on a planet or a pebble. Size
# instead shows up in TOTAL (total_units) and therefore in how quickly the
# deposit actually runs dry (depletion_rate_per_second) — a small deposit
# empties fast at the same extraction rate, rather than taking the same
# 5-20 minutes as a planet-scale one for 1000x less material.
func extraction_rate_per_second(deposit: DepositInfo) -> float:
	var total: int = TOTAL_UNITS_BY_SIZE.get(deposit.deposit_size, TOTAL_UNITS_BY_SIZE[DEFAULT_DEPOSIT_SIZE])
	var seconds: int = DEPLETE_SECONDS_BY_SIZE.get(deposit.deposit_size, DEPLETE_SECONDS_BY_SIZE[DEFAULT_DEPOSIT_SIZE])
	return float(total) / float(seconds)


# Fraction of remaining_fraction consumed per real second — constant
# regardless of how much is already left, so a half-depleted deposit simply
# takes half as long (in absolute seconds) to finish, not the same duration
# every time. Base seconds scaled by the SAME _size_multiplier as
# total_units, not left alone — a scaled-down total that still took the
# full base duration to extract would imply an ever-shrinking (and
# eventually absurdly slow) effective rate; scaling time down alongside
# total instead keeps extraction_rate_per_second's constant rate the actual
# truth throughout the operation, with the deposit simply running out sooner.
# Floored at 1 real second so a vanishingly small deposit still resolves
# rather than reading as instantaneous/glitchy.
func depletion_rate_per_second(deposit: DepositInfo) -> float:
	var seconds: int = DEPLETE_SECONDS_BY_SIZE.get(deposit.deposit_size, DEPLETE_SECONDS_BY_SIZE[DEFAULT_DEPOSIT_SIZE])
	var scaled_seconds := maxf(float(seconds) * _size_multiplier(deposit.body_id), 1.0)
	return 1.0 / scaled_seconds


# The actual (size-scaled) total this deposit holds fresh — what
# DepositDetailPanel's "Total Deposit" readout shows, and the only place
# TOTAL_UNITS_BY_SIZE's raw tier number gets adjusted for body size. Floored
# at 1 — a survey that found something at all should never display as a
# literal zero-unit deposit, even on the smallest possible asteroid.
func total_units(deposit: DepositInfo) -> int:
	var base: int = TOTAL_UNITS_BY_SIZE.get(deposit.deposit_size, TOTAL_UNITS_BY_SIZE[DEFAULT_DEPOSIT_SIZE])
	return maxi(1, roundi(float(base) * _size_multiplier(deposit.body_id)))


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


# Atomic batch spend for Research.craft_technology — checks every entry is
# affordable FIRST, and only subtracts anything if all of them are, so a
# craft attempt can never partially spend materials then fail partway
# through. Returns false (no-op, nothing spent) if any single one is short.
func spend_materials(requirements: Dictionary) -> bool:
	for material_name: String in requirements:
		if material_amount(material_name) < requirements[material_name]:
			return false
	for material_name: String in requirements:
		_material_amounts[material_name] = material_amount(material_name) - requirements[material_name]
	return true


# The player's whole cargo hold — material_name -> int, ship-wide (not
# broken down by which body it came from; nothing currently needs that
# distinction). A copy, not the live Dictionary, so a caller (CargoPanel)
# can't accidentally mutate inventory state just by iterating it.
func inventory() -> Dictionary:
	return _material_amounts.duplicate()


func _key(body_id: String, material_name: String) -> String:
	return "%s:%s" % [body_id, material_name]


# Thousands-separated integer — "big numbers feel good for the player" (per
# the user's own framing when deposits were scaled up), so a bare
# "1000000" reading as a wall of digits would undercut the whole point.
# Static, same "shared formatting utility living on the relevant data-model
# class" idiom as ActivityDef.format_duration.
static func format_units(n: int) -> String:
	var digits := str(n)
	var result := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		result = digits[i] + result
		count += 1
		if count % 3 == 0 and i != 0:
			result = "," + result
	return result
