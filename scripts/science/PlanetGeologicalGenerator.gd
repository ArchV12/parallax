class_name PlanetGeologicalGenerator
extends RefCounted

# Procedural Geological Survey content for a non-Sol Star/Terrestrial
# Planet/Dwarf Planet/Gas Giant/Ice Giant/Moon — the same GeologicalSurveyData
# shape Earth/Mars/Luna's hand-authored .tres files use (see Research.gd's
# GEOLOGICAL_DATA_PATHS), generated on the fly instead. Mirrors
# AsteroidGeologicalGenerator's own pattern exactly (see that file's header
# comment for the full "generate once, cache in Research" reasoning) — this
# is that generator's counterpart for everything ELSE KnownBodies.get_entry
# can resolve to that isn't an asteroid. Closes a real gap: PlanetResource
# Generator/MoonResourceGenerator already cover these same body kinds for
# Resource Survey, but Geological Survey had no equivalent until now, so a
# procedurally generated planet/moon's Geological Survey silently returned
# null.
#
# Keyed off KnownBodies.Entry.body_type (a real fact, not a rolled spectral
# class the way AsteroidGeologicalGenerator rolls C/S/M/V) — Star, giant, and
# rocky/moon each get their own composition/feature vocabulary. A Moon
# reuses the rocky vocabulary (a smaller version of the same kind of body)
# rather than getting its own file — split out later if a real reason to
# diverge (e.g. tidal-heating cryovolcanism) shows up; not worth a second
# near-duplicate file today. Salted distinctly from PlanetResourceGenerator's
# own seed (this uses "|geological", that one the bare body_id) so the two
# rolls stay independent, same reasoning as AsteroidGeologicalGenerator's
# own salt.
#
# generate() is a pure function of body_id — calling it twice for the same
# id always produces the identical result, same as AsteroidGeologicalGenerator.

const COVERED_BODY_TYPES: Array[String] = [
	"Star", "Terrestrial Planet", "Dwarf Planet", "Gas Giant", "Ice Giant", "Moon",
]

const ROCKY_COMPOSITION := ["Silicate Rock", "Basaltic Crust", "Iron-Nickel Core Fraction", "Regolith Layer"]
const ROCKY_FEATURES := ["Impact Craters", "Tectonic Ridges", "Canyon Systems", "Volcanic Plains", "Fault Escarpments"]
const GIANT_COMPOSITION := ["Hydrogen-Helium Envelope", "Ammonia/Methane Ices", "Metallic Hydrogen Core (Theoretical)", "Trace Hydrocarbon Compounds"]
const GIANT_FEATURES := ["Banded Cloud Structure", "Storm Systems", "Deep Atmospheric Convection Zones", "Polar Vortex Activity"]
const STAR_COMPOSITION := ["Hydrogen Plasma", "Helium Fusion Byproduct", "Trace Heavy Elements", "Ionized Stellar Wind"]
const STAR_FEATURES := ["Granulation Cells", "Magnetic Sunspot Activity", "Coronal Loops", "Flare Activity"]

const COMPOSITION_PICKS := 2
const FEATURE_PICKS_MIN := 1
const FEATURE_PICKS_MAX := 2

const ROCKY_VOLCANISM_ACTIVE_CHANCE := 0.2
const ROCKY_TECTONICS_ACTIVE_CHANCE := 0.15

const BASE_NOTES := [
	"Procedurally surveyed — no prior Geological data on record for this system.",
	"Preliminary orbital imaging consistent with surface composition estimate.",
	"No anomalous readings beyond standard instrument margin of error.",
]
const RARE_NOTE_CHANCE := 0.08
const RARE_NOTES := [
	"Localized gravitational anomaly detected — possible subsurface density variation.",
	"Surface spectral signature does not fully match predicted composition model.",
]


static func generate(body_id: String) -> GeologicalSurveyData:
	var entry := KnownBodies.get_entry(body_id)
	if entry == null:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s|geological" % body_id).hash()

	var data := GeologicalSurveyData.new()
	data.body_id = body_id
	match entry.body_type:
		"Star":
			data.composition = _sample(rng, STAR_COMPOSITION, COMPOSITION_PICKS)
			data.major_features = _sample(rng, STAR_FEATURES, _feature_picks(rng))
			data.volcanism = "N/A (Stellar Body)"
			data.tectonics = "N/A (Stellar Body)"
			data.erosion = "N/A (Stellar Body)"
		"Gas Giant", "Ice Giant":
			data.composition = _sample(rng, GIANT_COMPOSITION, COMPOSITION_PICKS)
			data.major_features = _sample(rng, GIANT_FEATURES, _feature_picks(rng))
			data.volcanism = "None (No Solid Surface)"
			data.tectonics = "None (No Solid Surface)"
			data.erosion = "None (No Solid Surface)"
		_:  # Terrestrial Planet, Dwarf Planet, Moon
			data.composition = _sample(rng, ROCKY_COMPOSITION, COMPOSITION_PICKS)
			data.major_features = _sample(rng, ROCKY_FEATURES, _feature_picks(rng))
			data.volcanism = "Active" if rng.randf() < ROCKY_VOLCANISM_ACTIVE_CHANCE else "Dormant/Extinct"
			data.tectonics = "Active Plate Boundaries" if rng.randf() < ROCKY_TECTONICS_ACTIVE_CHANCE else "Stable (No Active Plates)"
			data.erosion = "Active (Atmospheric Weathering)" if entry.has_atmosphere else "Minimal (No Atmosphere)"
	data.estimated_age = "~%.1f Billion Years (Estimated)" % rng.randf_range(1.0, 10.0)
	data.notes = _build_notes(rng)
	return data


static func _feature_picks(rng: RandomNumberGenerator) -> int:
	return FEATURE_PICKS_MIN + rng.randi_range(0, FEATURE_PICKS_MAX - FEATURE_PICKS_MIN)


static func _build_notes(rng: RandomNumberGenerator) -> Array[String]:
	var notes: Array[String] = [BASE_NOTES[rng.randi() % BASE_NOTES.size()]]
	if rng.randf() < RARE_NOTE_CHANCE:
		notes.append(RARE_NOTES[rng.randi() % RARE_NOTES.size()])
	return notes


# Same manual seeded partial-shuffle as AsteroidGeologicalGenerator._sample —
# duplicated rather than shared since both files are meant to stay small and
# self-contained (see that file's own comment on premature generalization).
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
