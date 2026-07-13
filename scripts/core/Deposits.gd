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
# awards — TOTAL_UNITS_BY_SIZE spread evenly across DEPLETE_SECONDS_BY_
# SIZE's duration for that same tier, so a bigger deposit is both larger
# AND faster to pull material out of, not just slower to run dry.
func extraction_rate_per_second(deposit: DepositInfo) -> float:
	var total: int = TOTAL_UNITS_BY_SIZE.get(deposit.deposit_size, TOTAL_UNITS_BY_SIZE[DEFAULT_DEPOSIT_SIZE])
	var seconds: int = DEPLETE_SECONDS_BY_SIZE.get(deposit.deposit_size, DEPLETE_SECONDS_BY_SIZE[DEFAULT_DEPOSIT_SIZE])
	return float(total) / float(seconds)


# Fraction of remaining_fraction consumed per real second — constant
# regardless of how much is already left, so a half-depleted deposit simply
# takes half as long (in absolute seconds) to finish, not the same duration
# every time.
func depletion_rate_per_second(deposit: DepositInfo) -> float:
	var seconds: int = DEPLETE_SECONDS_BY_SIZE.get(deposit.deposit_size, DEPLETE_SECONDS_BY_SIZE[DEFAULT_DEPOSIT_SIZE])
	return 1.0 / float(seconds)


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


func _key(body_id: String, material_name: String) -> String:
	return "%s:%s" % [body_id, material_name]
