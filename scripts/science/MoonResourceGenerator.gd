class_name MoonResourceGenerator
extends RefCounted

# Procedural Resource Survey content for any catalogued Moon-type body that
# doesn't have a hand-authored file (see Research.gd's RESOURCE_DATA_PATHS).
# Luna/Io/Europa/Titan/Triton stay hand-authored — each has real
# distinguishing lore (permanently-shadowed polar craters, sulfur
# volcanism, methane lakes, nitrogen geysers) a generic roll can't
# replicate. Everything else (Phobos, Deimos, Ganymede, Callisto, Mimas,
# Enceladus, Tethys, Dione, Rhea, Iapetus, Miranda, Ariel, Umbriel,
# Titania, Oberon, Charon, Styx, Nix, Kerberos, Hydra, and any future
# catalogued moon) rolls from here instead — same "generate what doesn't
# need bespoke authorship" precedent AsteroidResourceGenerator already set
# for the asteroid population, just keyed off which PLANET a moon orbits
# rather than an AU band.
#
# Unlike asteroids, a moon's real_radius_km is already a curated
# KnownBodies fact (not something this needs to roll/cache itself), so
# generate() only ever needs to return a ResourceSurveyData.
#
# Material pool depends on the parent planet's real distance from Sol —
# rough "closer = rockier/carbonaceous, farther = icier" solar-system
# chemistry: Mars's moons draw from a rocky pool (real theory: Phobos/
# Deimos are captured asteroids), the gas/ice giants' moons draw from an
# icy pool, Pluto's moons draw from the coldest/most exotic pool. Any moon
# flagged subsurface_ocean_potential (KnownBodies.Entry — Enceladus is the
# one un-authored example today) gets an extra independent shot at
# Cryptobiotic Residue on top of its pool, matching Europa/Titan's own
# hand-authored placement.

const ROCKY_COMMON: Array[String] = ["Iron", "Nickel", "Silicon", "Chromite"]
const ROCKY_RARE: Array[String] = ["Native Diamond", "Iridium"]

const ICY_GIANT_COMMON: Array[String] = ["Water Ice", "Silicon", "Iron", "Chromite"]
const ICY_GIANT_UNCOMMON: Array[String] = ["Methane Ice", "Ammonia Ice", "Geode Quartz Pockets"]
const ICY_GIANT_RARE: Array[String] = ["Olivine", "Platinum", "Voidglass"]

const DISTANT_ICE_COMMON: Array[String] = ["Water Ice", "Dry Ice (CO2 Frost)"]
const DISTANT_ICE_UNCOMMON: Array[String] = ["Liquid Nitrogen Pockets"]
const DISTANT_ICE_RARE: Array[String] = ["Umbral Quartz", "Chronite"]

const COMMON_PRESENCE_CHANCE := 0.5
const MIN_COMMON_MATERIALS := 1
const UNCOMMON_CHANCE := 0.3
const RARE_CHANCE := 0.1
const OCEAN_RESIDUE_CHANCE := 0.4  # only rolled at all for subsurface_ocean_potential moons

const COMMON_ABUNDANCE_WEIGHTS := {
	"Trace": 0.35,
	"Moderate": 0.35,
	"Common": 0.25,
	"Abundant": 0.05,
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
	var findings: Array[ResourceMaterialFinding] = []

	var present_names: Array[String] = []
	var common: Array[String] = profile["common"]
	for material_name in common:
		if rng.randf() < COMMON_PRESENCE_CHANCE:
			present_names.append(material_name)
	while present_names.size() < MIN_COMMON_MATERIALS:
		var pick: String = common[rng.randi() % common.size()]
		if pick not in present_names:
			present_names.append(pick)
	for material_name in present_names:
		findings.append(_roll_finding(rng, material_name, COMMON_ABUNDANCE_WEIGHTS, 0))

	var uncommon: Array[String] = profile["uncommon"]
	if not uncommon.is_empty() and rng.randf() < UNCOMMON_CHANCE:
		var name: String = uncommon[rng.randi() % uncommon.size()]
		findings.append(_roll_finding(rng, name, SCARCE_ABUNDANCE_WEIGHTS, 1))

	var rare: Array[String] = profile["rare"]
	if not rare.is_empty() and rng.randf() < RARE_CHANCE:
		var name: String = rare[rng.randi() % rare.size()]
		var finding := _roll_finding(rng, name, SCARCE_ABUNDANCE_WEIGHTS, 3)
		finding.note_value = "Difficult"
		findings.append(finding)

	if entry != null and entry.subsurface_ocean_potential and rng.randf() < OCEAN_RESIDUE_CHANCE:
		var residue := ResourceMaterialFinding.new()
		residue.material_name = "Cryptobiotic Residue"
		residue.abundance = _weighted_pick(rng, SCARCE_ABUNDANCE_WEIGHTS)
		residue.note_label = "Location"
		residue.note_value = "Suspected Subsurface Ocean"
		residue.min_scanner_tier = 3
		findings.append(residue)

	var survey := ResourceSurveyData.new()
	survey.body_id = body_id
	survey.materials = findings
	return survey


# Mars's moons: rocky. Pluto's moons: coldest/most exotic. Everything else
# (Jupiter/Saturn/Uranus/Neptune's un-authored moons, and any future
# catalogued moon this doesn't specifically recognize) defaults to the icy
# pool — a safe fallback, since most of the solar system beyond Mars is icy.
static func _profile_for(entry: KnownBodies.Entry) -> Dictionary:
	var parent := entry.parent if entry != null else ""
	if parent == "Mars":
		return {"common": ROCKY_COMMON, "uncommon": [], "rare": ROCKY_RARE}
	if parent == "Pluto":
		return {"common": DISTANT_ICE_COMMON, "uncommon": DISTANT_ICE_UNCOMMON, "rare": DISTANT_ICE_RARE}
	return {"common": ICY_GIANT_COMMON, "uncommon": ICY_GIANT_UNCOMMON, "rare": ICY_GIANT_RARE}


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
