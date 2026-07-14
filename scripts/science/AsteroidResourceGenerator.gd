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
# Reuses the SAME 5-material vocabulary planets already use (Iron,
# Aluminum, Silicon, Titanium, Water Ice) as the "standard" baseline every
# asteroid draws from, plus a rare chance at a platinum-group metal
# (Platinum/Palladium/Iridium — real asteroid-mining literature's own
# "why bother" materials, genuinely concentrated in real M-type asteroids)
# as an occasional surprise. What actually makes an asteroid's total haul
# tiny next to a planet's isn't a special case here at all — it's
# Deposits._size_multiplier, driven by the real radius_km rolled below,
# the same volume-scaling formula every body (asteroid or planet) now goes
# through.
#
# generate() is a pure function of body_id (hashed to seed everything) —
# calling it twice for the same id always produces the identical result, so
# Research.gd caching the first result is purely a performance choice, not
# a correctness requirement, same as every other seeded generator here.

const BASIC_MATERIALS: Array[String] = ["Iron", "Aluminum", "Silicon", "Titanium", "Water Ice"]
const RARE_MATERIALS: Array[String] = ["Platinum", "Palladium", "Iridium"]

# Each basic material independently has this chance of showing up at all —
# not every asteroid has every material, same as real ones vary by
# composition/spectral type. Topped up to MIN_BASIC_MATERIALS if an
# unlucky roll would otherwise leave an asteroid with almost nothing —
# every surveyed asteroid should have SOMETHING worth mining.
const BASIC_PRESENCE_CHANCE := 0.55
const MIN_BASIC_MATERIALS := 2

# Weighted, not uniform — most asteroids run modest, "Abundant" is rare,
# same "few giants, mostly small" spirit CraterField's own power-law crater
# size roll already uses elsewhere in this game.
const ABUNDANCE_WEIGHTS := {
	"Trace": 0.40,
	"Moderate": 0.35,
	"Common": 0.20,
	"Abundant": 0.05,
}
# Rare materials skew even further toward barely-there when they DO show
# up — a surprise, not a windfall; never "Abundant".
const RARE_ABUNDANCE_WEIGHTS := {
	"Trace": 0.55,
	"Moderate": 0.35,
	"Common": 0.10,
}

const RARE_MATERIAL_CHANCE := 0.12  # roughly 1 in 8 asteroids

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
	for material_name in BASIC_MATERIALS:
		if rng.randf() < BASIC_PRESENCE_CHANCE:
			present_names.append(material_name)
	while present_names.size() < MIN_BASIC_MATERIALS:
		var pick: String = BASIC_MATERIALS[rng.randi() % BASIC_MATERIALS.size()]
		if pick not in present_names:
			present_names.append(pick)

	var findings: Array[ResourceMaterialFinding] = []
	for material_name in present_names:
		findings.append(_roll_finding(rng, material_name, ABUNDANCE_WEIGHTS))

	if rng.randf() < RARE_MATERIAL_CHANCE:
		var rare_name: String = RARE_MATERIALS[rng.randi() % RARE_MATERIALS.size()]
		var finding := _roll_finding(rng, rare_name, RARE_ABUNDANCE_WEIGHTS)
		finding.note_value = "Difficult"  # rare materials are never an easy pull
		findings.append(finding)

	var survey := ResourceSurveyData.new()
	survey.body_id = body_id
	survey.materials = findings

	return {"survey": survey, "radius_km": radius_km}


static func _roll_finding(rng: RandomNumberGenerator, material_name: String, weights: Dictionary) -> ResourceMaterialFinding:
	var finding := ResourceMaterialFinding.new()
	finding.material_name = material_name
	finding.abundance = _weighted_pick(rng, weights)
	finding.note_label = "Extraction"
	finding.note_value = "Favorable" if rng.randf() < 0.6 else "Difficult"
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
