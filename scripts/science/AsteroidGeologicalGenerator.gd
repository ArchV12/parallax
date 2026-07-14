class_name AsteroidGeologicalGenerator
extends RefCounted

# Procedural Geological Survey content for an asteroid — the same
# GeologicalSurveyData shape Earth/Mars/Luna's hand-authored .tres files use
# (see Research.gd's GEOLOGICAL_DATA_PATHS), generated on the fly instead of
# hand-authored, same reasoning and same "generate once, cache in Research"
# calling pattern as AsteroidResourceGenerator (there's no way to pre-author
# a file for an id that doesn't exist until a seeded population rolls it at
# runtime — see the universe-generation-architecture memory).
#
# Built around real asteroid spectral classes (C/S/M/V — see SPECTRAL_TYPES)
# rather than inventing composition from nothing: C-types (carbonaceous,
# the real Main Belt majority) dominate the roll, with S-type (silicaceous),
# M-type (metallic), and rare V-type/volatile-rich bodies filling in the
# rest, each with its own plausible composition/feature/volcanism flavor.
# Deliberately NOT cross-referenced against AsteroidResourceGenerator's own
# material roll for the same id — an asteroid classed here as metallic isn't
# guaranteed a rich Iron finding over there, same way a real body's bulk
# spectral class doesn't fully predict what a resource assay finds. Seeded
# from a SALTED hash of body_id (not the bare id AsteroidResourceGenerator
# uses) specifically so the two generators' rolls stay independent instead
# of silently correlating from sharing one RNG sequence.
#
# generate() is a pure function of body_id — calling it twice for the same
# id always produces the identical result, same as AsteroidResourceGenerator.

const SPECTRAL_TYPES := ["C", "S", "M", "V"]
# Roughly matches real Main Belt survey proportions — C-types are the
# actual majority, M-types genuinely rare, V-type (Vesta-family/volatile-
# rich outliers) rarer still.
const SPECTRAL_WEIGHTS := {
	"C": 0.55,
	"S": 0.28,
	"M": 0.12,
	"V": 0.05,
}

const COMPOSITION_BY_TYPE := {
	"C": ["Carbonaceous Chondrite", "Phyllosilicates", "Organic Compounds"],
	"S": ["Silicate Rock", "Olivine", "Nickel-Iron Inclusions"],
	"M": ["Nickel-Iron Alloy", "Metallic Regolith"],
	"V": ["Water Ice", "Frozen Volatiles", "Silicate Dust"],
}
# Each body draws 2 entries from its type's list above (or all of it, if
# shorter) — never the full 3, so two same-type asteroids don't always read
# identically.
const COMPOSITION_PICKS := 2

# Impact Craters is near-universal for an airless body with no resurfacing
# process to erase them — always included, unlike the type-specific pool
# below (1-2 more, drawn per type).
const COMMON_FEATURE := "Impact Craters"
const FEATURES_BY_TYPE := {
	"C": ["Dark, Low-Albedo Surface", "Regolith Fields", "Fracture Ridges"],
	"S": ["Boulder Fields", "Fracture Ridges", "Regolith Fields"],
	"M": ["Smooth Metallic Terrain", "Fracture Ridges", "Boulder Fields"],
	"V": ["Sublimation Pits", "Ice-Rich Regolith", "Fracture Ridges"],
}
const FEATURE_PICKS_MIN := 1
const FEATURE_PICKS_MAX := 2

# Real asteroids are believed to skew rubble-pile (loose, gravity-bound
# collections of fragments) more often than solid monoliths — most actual
# Main Belt bodies above a few hundred meters are thought to be the former.
const TECTONICS_OPTIONS := {
	"None (Rubble Pile Structure)": 0.65,
	"None (Monolithic Structure)": 0.35,
}
# M-type bodies are the one class real planetary science actually suspects
# of past differentiation (believed remnant cores of shattered protoplanets)
# — everything else reads as flatly inactive.
const M_TYPE_VOLCANISM_CHANCE := 0.2

const EROSION_OPTIONS := {
	"Negligible (No Atmosphere)": 0.7,
	"Minimal (Micrometeorite Space Weathering)": 0.3,
}

# Most bodies read as primordial (as old as the Solar System itself); a
# minority are instead young collisional-family fragments — a real
# distinction in actual asteroid science, and a nice bit of variety against
# every rock otherwise reporting the same "4.5 billion years."
const COLLISIONAL_FRAGMENT_CHANCE := 0.2
const FRAGMENT_AGE_MIN_MYR := 50.0
const FRAGMENT_AGE_MAX_MYR := 2000.0

const BASE_NOTES := [
	"Consistent with Main Belt asteroid formation.",
	"Surface displays significant space weathering.",
	"No evidence of past cryovolcanic or geologic activity.",
]
const RARE_NOTE_CHANCE := 0.08
const RARE_NOTES := [
	"Possible small companion object detected in close orbit.",
	"Bilobate shape suggests a possible contact-binary origin.",
]


static func generate(body_id: String) -> GeologicalSurveyData:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s|geological" % body_id).hash()

	var spectral_type: String = _weighted_pick(rng, SPECTRAL_WEIGHTS)

	var data := GeologicalSurveyData.new()
	data.body_id = body_id
	data.composition = _sample(rng, COMPOSITION_BY_TYPE[spectral_type], COMPOSITION_PICKS)
	data.major_features = _build_features(rng, spectral_type)
	data.volcanism = "Extinct (Differentiated Core)" \
			if spectral_type == "M" and rng.randf() < M_TYPE_VOLCANISM_CHANCE \
			else "None (Undifferentiated Body)"
	data.tectonics = _weighted_pick(rng, TECTONICS_OPTIONS)
	data.erosion = _weighted_pick(rng, EROSION_OPTIONS)
	data.estimated_age = _build_age(rng)
	data.notes = _build_notes(rng)
	return data


static func _build_features(rng: RandomNumberGenerator, spectral_type: String) -> Array[String]:
	var picks := FEATURE_PICKS_MIN + rng.randi_range(0, FEATURE_PICKS_MAX - FEATURE_PICKS_MIN)
	var extra := _sample(rng, FEATURES_BY_TYPE[spectral_type], picks)
	var features: Array[String] = [COMMON_FEATURE]
	features.append_array(extra)
	return features


static func _build_age(rng: RandomNumberGenerator) -> String:
	if rng.randf() < COLLISIONAL_FRAGMENT_CHANCE:
		var age_myr := rng.randf_range(FRAGMENT_AGE_MIN_MYR, FRAGMENT_AGE_MAX_MYR)
		return "~%.0f Million Years (Collisional Fragment)" % age_myr
	return "~4.5 Billion Years (Primordial)"


static func _build_notes(rng: RandomNumberGenerator) -> Array[String]:
	var notes: Array[String] = [BASE_NOTES[rng.randi() % BASE_NOTES.size()]]
	if rng.randf() < RARE_NOTE_CHANCE:
		notes.append(RARE_NOTES[rng.randi() % RARE_NOTES.size()])
	return notes


# Picks up to `count` distinct entries from `pool`, in pool order (not
# shuffled — keeps a consistent read order like composition-by-abundance
# would, rather than scrambling every report). Clamps to the pool's own
# size, so a 2-entry pool with count=3 just returns both. A manual partial
# Fisher-Yates through the SEEDED `rng` rather than Array.shuffle() — that
# method draws from the engine's own global RNG stream, not the seed passed
# in here, which would make generate() non-deterministic across calls (it's
# documented, and Research.gd relies on it, as a pure function of body_id).
static func _sample(rng: RandomNumberGenerator, pool: Array, count: int) -> Array[String]:
	var indices: Array[int] = []
	for i in pool.size():
		indices.append(i)
	var pick_count: int = mini(count, indices.size())
	for i in pick_count:
		var j := i + (rng.randi() % (indices.size() - i))
		var tmp: int = indices[i]
		indices[i] = indices[j]
		indices[j] = tmp
	var chosen := indices.slice(0, pick_count)
	chosen.sort()
	var result: Array[String] = []
	for i in chosen:
		result.append(pool[i])
	return result


static func _weighted_pick(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var roll := rng.randf()
	var cumulative := 0.0
	var keys := weights.keys()
	for key in keys:
		cumulative += weights[key]
		if roll < cumulative:
			return key
	return keys[-1]
