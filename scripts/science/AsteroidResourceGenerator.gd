class_name AsteroidResourceGenerator
extends RefCounted

# Procedural Resource Survey content for an asteroid — the same
# ResourceSurveyData/ResourceMaterialFinding shape Earth/Mars/Luna's
# hand-authored .tres files use (see Research.gd's RESOURCE_DATA_PATHS),
# just generated on the fly and cached by Research.gd the first time
# anything actually asks for a given asteroid's data, rather than requiring
# a hand-authored file per asteroid — there's no way to pre-author one for
# an id that doesn't exist until a seeded population rolls it at runtime.
#
# 2026-07-18 — restructured from the original flat BASIC/RARE two-pool
# shape into five tiers matching the Scanner Array T0-T4 discoverability
# chart (see ResourceMaterialFinding.min_scanner_tier): COMMON (T0, the
# original 5-material vocabulary plus Nickel/Copper) through EXOTIC (T4,
# Voidglass/Aetherium/Chronite). Every tier above COMMON is a single-pick
# roll (at most one material from that tier per asteroid) at a
# progressively smaller chance, same shape the original RARE tier already
# used — a genuine surprise, not a windfall. What actually makes an
# asteroid's total haul tiny next to a planet's isn't a special case here
# at all — it's Deposits._size_multiplier, driven by the real radius_km
# rolled below, the same volume-scaling formula every body (asteroid or
# planet) now goes through.
#
# generate() is a pure function of body_id (hashed to seed everything) —
# calling it twice for the same id always produces the identical result, so
# Research.gd caching the first result is purely a performance choice, not
# a correctness requirement, same as every other seeded generator here.

const COMMON_MATERIALS: Array[String] = ["Iron", "Aluminum", "Silicon", "Titanium", "Water Ice", "Nickel", "Copper"]
const UNCOMMON_MATERIALS: Array[String] = ["Chromite"]
const RARE_MATERIALS: Array[String] = ["Platinum", "Palladium", "Iridium"]
# Real asteroid-mining literature's own "why bother" materials (Platinum-
# group) sit at RARE; PRECIOUS is the next step up — gemstones/rare-earth
# concentrate, genuinely concentrated in specific real meteorite classes.
const PRECIOUS_MATERIALS: Array[String] = ["Gold", "Rare Earth Concentrate", "Native Diamond", "Olivine", "Corundum", "Beryl", "Geode Quartz Pockets"]
# Matter that doesn't behave normally — the rarest, gated behind the best
# scanner in the game (Exotic Matter Resonator, T4).
const EXOTIC_MATERIALS: Array[String] = ["Voidglass", "Aetherium", "Chronite"]

# Each COMMON material independently has this chance of showing up at all —
# not every asteroid has every material, same as real ones vary by
# composition/spectral type. Topped up to MIN_COMMON_MATERIALS if an
# unlucky roll would otherwise leave an asteroid with almost nothing —
# every surveyed asteroid should have SOMETHING worth mining.
const COMMON_PRESENCE_CHANCE := 0.55
const MIN_COMMON_MATERIALS := 2

# Every tier above COMMON is a single-pick roll (see class comment) — this
# is the chance an asteroid has ANY material from that tier at all, in
# decreasing order as the tier gets rarer. Once a tier hits, the SAME
# SCARCE_ABUNDANCE_WEIGHTS decides how much of it — the tier's own presence
# chance already carries the "how special is this" weight, so there's no
# need for four near-identical abundance tables on top of that.
const UNCOMMON_MATERIAL_CHANCE := 0.35
const RARE_MATERIAL_CHANCE := 0.12  # roughly 1 in 8 asteroids
const PRECIOUS_MATERIAL_CHANCE := 0.07
const EXOTIC_MATERIAL_CHANCE := 0.03  # roughly 1 in 33

# Weighted, not uniform — most asteroids run modest, "Abundant" is rare,
# same "few giants, mostly small" spirit CraterField's own power-law crater
# size roll already uses elsewhere in this game.
const COMMON_ABUNDANCE_WEIGHTS := {
	"Trace": 0.40,
	"Moderate": 0.35,
	"Common": 0.20,
	"Abundant": 0.05,
}
# Shared by every tier above COMMON — skews even further toward
# barely-there than the common weights, and never "Abundant".
const SCARCE_ABUNDANCE_WEIGHTS := {
	"Trace": 0.55,
	"Moderate": 0.35,
	"Common": 0.10,
}

const RADIUS_MIN_KM := 0.3
const RADIUS_MAX_KM := 20.0
# Same pow(u, N) skew CraterField.make uses for crater sizes — most rolls
# land small, a genuinely large asteroid is the rare case, matching the
# real size-frequency distribution of the actual population (small bodies
# vastly outnumber large ones).
const RADIUS_POWER := 2.2


# The one thing that tells Research.gd "this id is a proceduralizable
# asteroid, not just some other unrecognized body" — matches
# AsteroidDesignation.generate()'s own format exactly (4-digit year, space,
# a half-month letter, a sequence letter, an optional cycle-count digit
# string), so this only ever fires for ids that actually came from there.
static func looks_like_asteroid_id(body_id: String) -> bool:
	var re := RegEx.new()
	re.compile("^\\d{4} [A-Z]{2}\\d*$")
	return re.search(body_id) != null


# Returns {"survey": ResourceSurveyData, "radius_km": float}.
static func generate(body_id: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = body_id.hash()

	var radius_km := lerpf(RADIUS_MIN_KM, RADIUS_MAX_KM, pow(rng.randf(), RADIUS_POWER))

	var present_names: Array[String] = []
	for material_name in COMMON_MATERIALS:
		if rng.randf() < COMMON_PRESENCE_CHANCE:
			present_names.append(material_name)
	while present_names.size() < MIN_COMMON_MATERIALS:
		var pick: String = COMMON_MATERIALS[rng.randi() % COMMON_MATERIALS.size()]
		if pick not in present_names:
			present_names.append(pick)

	var findings: Array[ResourceMaterialFinding] = []
	for material_name in present_names:
		findings.append(_roll_finding(rng, material_name, COMMON_ABUNDANCE_WEIGHTS, 0))

	_maybe_roll_tier(rng, findings, UNCOMMON_MATERIALS, UNCOMMON_MATERIAL_CHANCE, 1)
	_maybe_roll_tier(rng, findings, RARE_MATERIALS, RARE_MATERIAL_CHANCE, 2)
	_maybe_roll_tier(rng, findings, PRECIOUS_MATERIALS, PRECIOUS_MATERIAL_CHANCE, 3)
	_maybe_roll_tier(rng, findings, EXOTIC_MATERIALS, EXOTIC_MATERIAL_CHANCE, 4)

	var survey := ResourceSurveyData.new()
	survey.body_id = body_id
	survey.materials = findings

	return {"survey": survey, "radius_km": radius_km}


# Single-pick roll shared by every tier above COMMON (see class comment) —
# at most one material from `materials`, at `chance`, tagged `tier` and
# forced to "Difficult" extraction (above-common materials are never an
# easy pull). Appends straight into `findings` — a no-op if the roll misses.
static func _maybe_roll_tier(rng: RandomNumberGenerator, findings: Array[ResourceMaterialFinding],
		materials: Array[String], chance: float, tier: int) -> void:
	if rng.randf() >= chance:
		return
	var name: String = materials[rng.randi() % materials.size()]
	var finding := _roll_finding(rng, name, SCARCE_ABUNDANCE_WEIGHTS, tier)
	finding.note_value = "Difficult"
	findings.append(finding)


static func _roll_finding(rng: RandomNumberGenerator, material_name: String, weights: Dictionary, tier: int) -> ResourceMaterialFinding:
	var finding := ResourceMaterialFinding.new()
	finding.material_name = material_name
	finding.abundance = _weighted_pick(rng, weights)
	finding.note_label = "Extraction"
	finding.note_value = "Favorable" if rng.randf() < 0.6 else "Difficult"
	finding.min_scanner_tier = tier
	return finding


static func _weighted_pick(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var roll := rng.randf()
	var cumulative := 0.0
	var keys := weights.keys()
	for key: String in keys:
		cumulative += weights[key]
		if roll < cumulative:
			return key
	return keys[-1]  # float rounding fallback
