class_name PlanetResourceGenerator
extends RefCounted

# Procedural Resource Survey content for any catalogued Star/Terrestrial
# Planet/Dwarf Planet/Gas Giant/Ice Giant that doesn't have a hand-authored
# file (see Research.gd's RESOURCE_DATA_PATHS) — the third and last gap in
# the "generate what doesn't need bespoke authorship" precedent, after
# AsteroidResourceGenerator (asteroids) and MoonResourceGenerator (moons).
# Every Sol planet/Sol itself is hand-authored (real, distinguishing lore),
# so this exists purely for bodies OUTSIDE Sol — Proxima Centauri + b + c
# are the first real case (2026-07-19: found while chasing why arriving at
# Proxima had nothing to actually scan/mine — resource_data_for() had a
# procedural fallback for every body_type EXCEPT this one).
#
# Three material vocabularies, keyed off body_type — reusing the exact real
# names Sol's own hand-authored files already use (Mercury/Venus for rocky,
# Jupiter/Saturn/Uranus/Neptune for gas/ice giants, Sol itself for a star),
# so a procedural body reads as a genuine sibling of the real ones instead
# of inventing a parallel vocabulary:
#   - Rocky (Terrestrial Planet, Dwarf Planet): the same mineral pool
#     Mercury/Venus/MoonResourceGenerator's ROCKY profile already draw from.
#   - Gas/Ice Giant: atmospheric gases (Hydrogen, Ammonia Gas, Methane Gas,
#     Deuterium, Helium-3, Neon) — Ice Giants skip Ammonia Gas, mirroring
#     the real Jupiter/Saturn-vs-Uranus/Neptune split in the hand-authored
#     files (ammonia ice clouds over methane haze reads differently at
#     ice-giant temperatures).
#   - Star: Sol's own sparse Hydrogen/Deuterium/Helium-3/Coronal Plasma
#     vocabulary — a star has the least "mineable" complexity of any body
#     type in this game's model, procedural or not.

const COVERED_BODY_TYPES: Array[String] = ["Star", "Terrestrial Planet", "Dwarf Planet", "Gas Giant", "Ice Giant"]

const ROCKY_COMMON: Array[String] = ["Iron", "Nickel", "Silicon", "Titanium", "Chromite"]
const ROCKY_UNCOMMON: Array[String] = ["Sulfur", "Magnesium", "Water Ice"]
const ROCKY_RARE: Array[String] = ["Platinum", "Iridium"]
const ROCKY_EXOTIC: Array[String] = ["Corundum", "Native Diamond", "Chronite", "Voidglass"]

const GIANT_COMMON: Array[String] = ["Hydrogen"]
const GIANT_UNCOMMON: Array[String] = ["Ammonia Gas", "Methane Gas"]  # Ice Giant profile drops Ammonia Gas — see _profile_for
const GIANT_RARE: Array[String] = ["Deuterium"]
const GIANT_EXOTIC: Array[String] = ["Helium-3", "Neon", "Aetherium"]
const GIANT_LOCATIONS := ["Upper Cloud Deck", "Upper Cloud Deck", "Deep Atmosphere", "Convective Layer"]  # common/uncommon/rare/exotic, matches Jupiter/Saturn/Neptune's own progression

const STAR_COMMON: Array[String] = ["Hydrogen"]
const STAR_UNCOMMON: Array[String] = []
const STAR_RARE: Array[String] = ["Deuterium"]
const STAR_EXOTIC: Array[String] = ["Helium-3", "Coronal Plasma"]
const STAR_LOCATIONS := ["Photosphere", "", "Convective Zone", "Stellar Corona"]

const COMMON_PRESENCE_CHANCE := 0.6
const MIN_COMMON_MATERIALS := 1
const UNCOMMON_CHANCE := 0.5
const RARE_CHANCE := 0.3
const EXOTIC_CHANCE := 0.12

const COMMON_ABUNDANCE_WEIGHTS := {
	"Trace": 0.20,
	"Moderate": 0.30,
	"Common": 0.35,
	"Abundant": 0.15,
}
const SCARCE_ABUNDANCE_WEIGHTS := {
	"Trace": 0.55,
	"Moderate": 0.35,
	"Common": 0.10,
}


static func generate(body_id: String) -> ResourceSurveyData:
	var entry := KnownBodies.get_entry(body_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = body_id.hash()

	var profile := _profile_for(entry)
	var gas_like: bool = profile["gas_like"]
	var locations: Array = profile["locations"]
	var findings: Array[ResourceMaterialFinding] = []

	var present_names: Array[String] = []
	var common: Array[String] = profile["common"]
	for material_name in common:
		if rng.randf() < COMMON_PRESENCE_CHANCE:
			present_names.append(material_name)
	while present_names.size() < MIN_COMMON_MATERIALS and not common.is_empty():
		var pick: String = common[rng.randi() % common.size()]
		if pick not in present_names:
			present_names.append(pick)
	for material_name in present_names:
		findings.append(_roll_finding(rng, material_name, COMMON_ABUNDANCE_WEIGHTS, 0, gas_like, locations[0]))

	_maybe_roll_tier(rng, findings, profile["uncommon"], UNCOMMON_CHANCE, 1, gas_like, locations[1])
	_maybe_roll_tier(rng, findings, profile["rare"], RARE_CHANCE, 2, gas_like, locations[2])
	_maybe_roll_tier(rng, findings, profile["exotic"], EXOTIC_CHANCE, 4, gas_like, locations[3])

	var survey := ResourceSurveyData.new()
	survey.body_id = body_id
	survey.materials = findings
	return survey


# Star and Gas/Ice Giant both read their findings as atmospheric/stellar
# LOCATION notes (see GIANT_LOCATIONS/STAR_LOCATIONS); Terrestrial/Dwarf
# Planet reads as ordinary EXTRACTION difficulty, same as every hand-
# authored rocky body and MoonResourceGenerator's own rocky profile.
static func _profile_for(entry: KnownBodies.Entry) -> Dictionary:
	var body_type := entry.body_type if entry != null else "Terrestrial Planet"
	if body_type == "Star":
		return {"common": STAR_COMMON, "uncommon": STAR_UNCOMMON, "rare": STAR_RARE, "exotic": STAR_EXOTIC,
				"gas_like": true, "locations": STAR_LOCATIONS}
	if body_type == "Gas Giant" or body_type == "Ice Giant":
		# Real Jupiter/Saturn (Gas Giant) vs Uranus/Neptune (Ice Giant) split
		# in the hand-authored files — Ice Giants never roll Ammonia Gas.
		var uncommon: Array[String] = ["Methane Gas"]
		if body_type == "Gas Giant":
			uncommon = GIANT_UNCOMMON
		return {"common": GIANT_COMMON, "uncommon": uncommon, "rare": GIANT_RARE, "exotic": GIANT_EXOTIC,
				"gas_like": true, "locations": GIANT_LOCATIONS}
	# locations is read positionally (locations[0..3]) regardless of gas_like
	# — _roll_finding only actually USES it when gas_like is true, but the
	# indexing itself happens unconditionally as each tier's call is built,
	# so this needs 4 real (if unused) entries, not an empty array — an
	# empty one would throw on the very first "Invalid index" access.
	return {"common": ROCKY_COMMON, "uncommon": ROCKY_UNCOMMON, "rare": ROCKY_RARE, "exotic": ROCKY_EXOTIC,
			"gas_like": false, "locations": ["", "", "", ""]}


static func _maybe_roll_tier(rng: RandomNumberGenerator, findings: Array[ResourceMaterialFinding],
		materials: Array, chance: float, tier: int, gas_like: bool, location: String) -> void:
	if materials.is_empty() or rng.randf() >= chance:
		return
	var name: String = materials[rng.randi() % materials.size()]
	var finding := _roll_finding(rng, name, SCARCE_ABUNDANCE_WEIGHTS, tier, gas_like, location)
	if not gas_like:
		finding.note_value = "Difficult"
	findings.append(finding)


static func _roll_finding(rng: RandomNumberGenerator, material_name: String, weights: Dictionary,
		tier: int, gas_like: bool, location: String) -> ResourceMaterialFinding:
	var finding := ResourceMaterialFinding.new()
	finding.material_name = material_name
	finding.abundance = _weighted_pick(rng, weights)
	finding.min_scanner_tier = tier
	if gas_like:
		finding.note_label = "Location"
		finding.note_value = location
	else:
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
