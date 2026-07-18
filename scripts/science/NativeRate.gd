class_name NativeRate
extends RefCounted

# How much a body's OWN properties support each Knowledge category — a
# 0-100ish value Buildings.gd multiplies by a structure's tier multiplier.
# All 5 buildable categories are implemented (Docs/Buildings System.md) —
# Engineering deliberately has no native rate/building ladder at all, just a
# flat per-construction bonus (see Buildings.ENGINEERING_BONUS_PER_CONSTRUCTION).

const GAS_GIANT_STAR_FLAT_RATE := 15.0
const ATMOSPHERE_PRESERVATION_PENALTY := 0.4
const PRESERVATION_MIN := 0.2

# --- Astrophysics constants ---
const SOL_LIKE_TEMP_K := 5800.0          # conventional "ordinary G-type star" reference point, not Sol's own exact surface_temp_k (5778.0) — deliberately close so Sol itself scores near the floor of the star range (an ordinary star, not an extreme one)
const STAR_TEMP_EXTREMITY_SCALE := 15000.0  # how many K of deviation from SOL_LIKE_TEMP_K maps to "maximally extreme" (1.0)
const STAR_BASE_RATE := 60.0             # stars are always well above any planetary body's ceiling — see Docs/Buildings System.md
const GAS_GIANT_ACTIVITY_BONUS := 10.0   # flat stand-in for the doc's turbulence/storminess/band_contrast term — those are still ephemeral GasGiantParams render knobs, not canonical Entry facts, same simplification precedent as geology()'s has_atmosphere boolean below
const RING_RATE_MULTIPLIER := 25.0
const MOON_RATE_PER_MOON := 2.0
const MOON_RATE_CAP := 10.0
const SIZE_RATE_MULTIPLIER := 2.0

# --- Life Sciences constants ---
const LIFE_GAS_GIANT_FLOOR := 5.0
const LIFE_GAS_GIANT_ACTIVITY_BONUS := 3.0  # flat stand-in for GasGiantParams.turbulence — same simplification precedent as GAS_GIANT_ACTIVITY_BONUS above
const SUBSURFACE_OCEAN_RATE := 60.0         # flat "wait, this scores real points!" reward for the Titan/Europa exception — comparable to Earth's own computed rate (~70)
const GOLDILOCKS_AU := 1.0
const INNER_FALLOFF := 3.0   # steep sunward falloff — Venus (0.72 AU) already scores a low ~0.16 from distance alone, well before its ocean_level=0.0 independently zeroes the whole rate; two separate reasons a hot dry world scores low, not a redundant one
const OUTER_FALLOFF := 1.0   # gentler outward (Mars-ward) falloff — a thick atmosphere could plausibly sustain warmth further out than it could shield against heat closer in
const DRY_ATMOSPHERE_PENALTY := 0.3
const ANCIENT_LIFE_ROLL_CHANCE := 0.05  # user-specified design: "just a dice roll for any rocky planet" — Mars (no current surface water, but real astrobiology's most iconic target) was the motivating case
const ANCIENT_LIFE_BONUS_RATE := 10.0   # "a little bit of life science value" for a body that rolls true

# --- Anomalies constants ---
const ANOMALY_MINOR_CHANCE := 0.04
const ANOMALY_MAJOR_CHANCE := 0.01   # rolled first — a (body, category) pair has at most ONE outcome: none (95%), minor (4%), or major (1%)
const ANOMALY_MINOR_RATE := 15.0
const ANOMALY_MAJOR_RATE := 50.0

# --- Atmospheric Science constants ---
const ATMOSPHERIC_GAS_BASE := 30.0
const ATMOSPHERIC_GAS_TURBULENCE_WEIGHT := 35.0
const ATMOSPHERIC_GAS_STORMINESS_WEIGHT := 25.0
const ATMOSPHERIC_GAS_BAND_CONTRAST_WEIGHT := 10.0
const ATMOSPHERIC_TERRESTRIAL_ATMOSPHERE_WEIGHT := 25.0
const ATMOSPHERIC_TERRESTRIAL_OCEAN_WEIGHT := 35.0
const ATMOSPHERIC_LIFE_BONUS := 25.0
const ATMOSPHERIC_TURBULENCE_WEIGHT := 15.0
const ATMOSPHERIC_LIFE_SCIENCES_THRESHOLD := 40.0  # NativeRate.life_sciences(body_id) at/above this counts as the doc's "has_life" term — no real "confirmed life" flag exists in code (same finding as Life Sciences/Anomalies), so this reuses an already-computed real value instead of inventing a new unbacked boolean

# category_id -> {"minor": {"name", "description"}, "major": {...}}. Physics/
# chemistry-flavored only — no precursor ruins (tonally archaeology/lore, not
# physics, and wants its own narrative payoff — deliberately deferred), and
# life_sciences wording stays "unexplained trace," never "confirmed life"
# (Life Sciences Knowledge tracks ongoing research, decoupled from a
# separate, much rarer, not-yet-built "confirmed life discovered" narrative
# event — see Docs/Buildings System.md's Life Sciences section).
const ANOMALY_TYPES := {
	"resource": {
		"minor": {"name": "Trace Exotic Alloy", "description": "Scans show a metallic signature that doesn't match any known ore composition."},
		"major": {"name": "Unrefined Antimatter Signature", "description": "A minute but unmistakable antimatter trace, stable enough to detect but far too small to explain."},
	},
	"geological": {
		"minor": {"name": "Non-Standard Strata Layering", "description": "Subsurface layering follows no known geological process."},
		"major": {"name": "Impossible Cave Geometry", "description": "A subsurface cavity with angles and symmetry that shouldn't be able to form naturally."},
	},
	"astrophysics": {
		"minor": {"name": "Erratic Gravitational Fluctuation", "description": "Local gravity readings drift in a pattern with no orbital-mechanics explanation."},
		"major": {"name": "Localized Spacetime Distortion", "description": "A small, stable region where light bends more than the body's mass can account for."},
	},
	"life_sciences": {
		"minor": {"name": "Unidentified Organic Trace", "description": "Chemical residue consistent with organic processes, of uncertain origin."},
		"major": {"name": "Complex Prebiotic Chemistry", "description": "Molecular complexity well beyond what background chemistry alone should produce here."},
	},
	"atmospheric": {
		"minor": {"name": "Anomalous Circulation Pattern", "description": "A persistent atmospheric current that shouldn't be stable under this body's own dynamics."},
		"major": {"name": "Sustained Exotic Storm Chemistry", "description": "A storm system cycling reaction products that ordinary atmospheric chemistry can't account for, and hasn't dissipated."},
	},
}

# Hand-placed, GUARANTEED anomalies for specific curated bodies — the solar
# system is a fixed, curated set (KnownBodies._ensure_built), so a few
# story-worthy bodies can be deliberately seeded with a real anomaly instead
# of leaving it purely to the random roll below. Checked before the roll in
# anomaly_for() and bypasses it entirely for the given (body, category) pair
# — every other (body, category) at that same body still rolls normally.
# body_id -> {"category", "magnitude", "name", "description"}.
const GUARANTEED_ANOMALIES := {
	"Titan": {
		"category": "life_sciences",
		"magnitude": "Major",
		"name": "Sustained Prebiotic Reaction Cycle",
		"description": "Titan's hydrocarbon lakes show an ongoing chemical cycle far too organized to be background weathering — something here keeps assembling the same complex molecules faster than they break down.",
	},
}


static func for_category(category_id: String, body_id: String) -> float:
	match category_id:
		"geological":
			return geology(body_id)
		"astrophysics":
			return astrophysics(body_id)
		"life_sciences":
			return life_sciences(body_id)
		"anomalies":
			return anomalies(body_id)
		"atmospheric":
			return atmospheric(body_id)
		_:
			return 0.0  # unreachable for any real category id — only a typo would land here


# SIMPLIFIED placeholder formula — see Docs/Buildings System.md for the full
# cross-referenced version (once Atmospheric Science/Life Sciences native
# rates exist, `has_atmosphere` becomes a continuous preservation term
# instead of a flat boolean penalty). Real-world-grounded insight this
# formula preserves even in simplified form: airless/pristine bodies
# (asteroids, Luna) score HIGHER than atmosphere-scoured worlds (Earth) —
# weathering and resurfacing erase the ancient geological record, so "more
# Earth-like" is NOT "more geologically interesting" on this axis.
static func geology(body_id: String) -> float:
	var entry := KnownBodies.get_entry(body_id)
	if entry == null:
		return 0.0
	if not entry.has_solid_surface:
		return GAS_GIANT_STAR_FLAT_RATE
	var preservation := 1.0 - (ATMOSPHERE_PRESERVATION_PENALTY if entry.has_atmosphere else 0.0)
	return 100.0 * clampf(preservation, PRESERVATION_MIN, 1.0) * (0.5 + 0.5 * entry.terrain_ruggedness)


# No hard gate (mass and orbital dynamics apply to every body), unlike
# geology()'s has_solid_surface branch — see Docs/Buildings System.md's
# Astrophysics section. Stars use a completely different shape (temperature
# extremity + stellar activity, anchored well above any planet's ceiling);
# every other body scores off size/rings/moon count, with a flat bonus for
# gas/ice giants standing in for their real atmospheric-dynamics term (see
# GAS_GIANT_ACTIVITY_BONUS above for why that's simplified). Deliberately a
# rough first pass, same as geology() originally was — the doc itself notes
# this category needs relative tuning across the whole body roster once it's
# visible in actual play, not perfect balance up front.
static func astrophysics(body_id: String) -> float:
	var entry := KnownBodies.get_entry(body_id)
	if entry == null:
		return 0.0
	if entry.body_type == "Star":
		var temp_extremity := clampf(absf(entry.surface_temp_k - SOL_LIKE_TEMP_K) / STAR_TEMP_EXTREMITY_SCALE, 0.0, 1.0)
		var activity := entry.star_turbulence + entry.star_spot_activity
		return clampf(STAR_BASE_RATE + temp_extremity * 20.0 + activity * 10.0, STAR_BASE_RATE, 100.0)
	var rate := 5.0 + entry.radius_ratio * SIZE_RATE_MULTIPLIER + entry.rings * RING_RATE_MULTIPLIER \
			+ minf(entry.moon_count, MOON_RATE_CAP) * MOON_RATE_PER_MOON
	if entry.body_type == "Gas Giant" or entry.body_type == "Ice Giant":
		rate += GAS_GIANT_ACTIVITY_BONUS
	return rate


# Tracks ongoing habitability RESEARCH, not confirmed life — a legitimate
# field regardless of outcome, same as real astrobiology (Docs/Buildings
# System.md). Stars and gas/ice giants get their own flat shapes (a gas
# giant's "airborne lifeform" angle is real but never high); every rocky body
# either hits the Titan/Europa subsurface-ocean bypass (a flat high reward —
# these bodies are exciting specifically because they BREAK the normal
# temperature-band rule) or falls through to a goldilocks-zone-distance ×
# atmosphere × ocean_level formula, plus a small seeded chance of scoring a
# flat bonus anyway for a plausible ancient-life past (see
# _rolled_ancient_life — Mars is the motivating case: no current surface
# water, but still real astrobiology's most iconic target).
#
# Real gap in the ORIGINAL design doc's own pseudocode this fixes: its
# temperature_band_score = f(au_distance) silently breaks for every moon —
# Entry.au_distance is explicitly "unused for moons" (stays 0.0, i.e. "at the
# Sun"). Fixed by walking up to the parent's au_distance for any body that
# has one, so a moon's temperature band tracks its actual orbital distance
# from the Sun (via its parent), not a meaningless 0.
static func life_sciences(body_id: String) -> float:
	var entry := KnownBodies.get_entry(body_id)
	if entry == null:
		return 0.0
	if entry.body_type == "Star":
		return 0.0
	if entry.body_type == "Gas Giant" or entry.body_type == "Ice Giant":
		return LIFE_GAS_GIANT_FLOOR + LIFE_GAS_GIANT_ACTIVITY_BONUS
	if not entry.has_solid_surface:
		return 0.0  # defensive only — every non-gas-giant, non-star body in this catalog already has_solid_surface today
	if entry.subsurface_ocean_potential:
		return SUBSURFACE_OCEAN_RATE
	var effective_au := entry.au_distance
	if entry.parent != "":
		var parent_entry := KnownBodies.get_entry(entry.parent)
		effective_au = parent_entry.au_distance if parent_entry != null else entry.au_distance
	var temperature_band_score := _temperature_band_score(effective_au)
	var atmosphere_factor := 1.0 if entry.has_atmosphere else DRY_ATMOSPHERE_PENALTY
	var rate := 100.0 * temperature_band_score * atmosphere_factor * entry.ocean_level
	if _rolled_ancient_life(body_id):
		rate += ANCIENT_LIFE_BONUS_RATE
	return rate


# Asymmetric goldilocks-zone curve — steeper on the sunward side (runaway
# greenhouse is a hard cliff) than the outward side (a thick atmosphere can
# plausibly sustain warmth further out than it could shield against heat
# closer in). Venus (0.72 AU) lands deep enough in the steep inner falloff to
# already score low from distance alone, independent of its ocean_level=0.0
# separately zeroing the whole rate.
static func _temperature_band_score(au_distance: float) -> float:
	var delta := au_distance - GOLDILOCKS_AU
	var falloff := INNER_FALLOFF if delta < 0.0 else OUTER_FALLOFF
	return clampf(1.0 - absf(delta) * falloff, 0.0, 1.0)


# Deterministic per-body roll, not re-rolled every call (Buildings._process
# calls NativeRate.for_category continuously) — same salted-seed idiom
# KnownBodies._synthesize_asteroid_entry already uses for asteroid
# terrain_ruggedness, so the same body always rolls the same result for the
# rest of the session (and every future one — nothing time-seeds this).
# Applies uniformly to every body that reaches this point in life_sciences()
# (i.e. every "normal" rocky body — gas giants and the subsurface-ocean
# bypass above never reach here), curated or procedural alike. Mars is the
# motivating example but is NOT special-cased — genuinely any rocky body,
# including asteroids, can roll it.
static func _rolled_ancient_life(body_id: String) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s|ancient_life_potential" % body_id).hash()
	return rng.randf() < ANCIENT_LIFE_ROLL_CHANCE


# No dedicated "Anomaly Scan" — per user design, any of the 4 existing survey
# activities (resource_survey/geological_survey/astrophysics_survey/
# life_sciences_survey) can independently reveal an anomaly at a body, one
# roll per (body, category) pair rather than one per body — a single body can
# have a Geological anomaly AND a separate Astrophysics anomaly, discovered
# independently by running each survey there. Deterministic per (body,
# category), same salted-seed idiom as _rolled_ancient_life/
# KnownBodies._synthesize_asteroid_entry's terrain_ruggedness — stable for
# the rest of the session, not re-rolled every call.
#
# resource_survey's own category ("resource") is deliberately included even
# though it's NOT one of the 6 Buildings Knowledge categories (a separate,
# older Mining-gating pool) — a Resource Survey can occasionally reveal an
# Anomalies-category finding even though Resource Survey itself never
# otherwise touches the 6-category system, matching the user's literal "any
# of the other scan types."
#
# GUARANTEED_ANOMALIES overrides the random roll entirely for specific
# (body, category) pairs hand-placed by design (currently just Titan) — see
# that const's own comment.
static func anomaly_for(body_id: String, category_id: String) -> AnomalyResult:
	if not ANOMALY_TYPES.has(category_id):
		return null
	var entry := KnownBodies.get_entry(body_id)
	if entry == null:
		return null
	# Geological anomaly flavor (cave geometry/strata) genuinely needs solid
	# ground — narrower than geology()'s own gate (which still gives airless/
	# gas bodies a flat rate), a deliberate content constraint, not a bug.
	if category_id == "geological" and not entry.has_solid_surface:
		return null
	# Life Sciences mirrors life_sciences()'s OWN gate exactly (Star only) —
	# NOT has_solid_surface, so gas/ice giants stay eligible, matching that
	# formula's own "airborne lifeform, never high" flavor for them.
	if category_id == "life_sciences" and entry.body_type == "Star":
		return null
	# Mirrors atmospheric()'s own gate exactly — no atmosphere, no anomaly.
	if category_id == "atmospheric" and not entry.has_atmosphere:
		return null
	if GUARANTEED_ANOMALIES.has(body_id):
		var g: Dictionary = GUARANTEED_ANOMALIES[body_id]
		if g["category"] == category_id:
			var rate := ANOMALY_MAJOR_RATE if g["magnitude"] == "Major" else ANOMALY_MINOR_RATE
			return _make_anomaly(g, g["magnitude"], rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s|anomaly|%s" % [body_id, category_id]).hash()
	var roll := rng.randf()
	var pool: Dictionary = ANOMALY_TYPES[category_id]
	if roll < ANOMALY_MAJOR_CHANCE:
		return _make_anomaly(pool["major"], "Major", ANOMALY_MAJOR_RATE)
	if roll < ANOMALY_MAJOR_CHANCE + ANOMALY_MINOR_CHANCE:
		return _make_anomaly(pool["minor"], "Minor", ANOMALY_MINOR_RATE)
	return null


static func _make_anomaly(data: Dictionary, magnitude: String, rate: float) -> AnomalyResult:
	var a := AnomalyResult.new()
	a.name = data["name"]
	a.description = data["description"]
	a.magnitude = magnitude
	a.rate = rate
	return a


# Buildings-facing total — sums whatever each of the 4 source categories
# independently rolled (0 for any that rolled nothing).
static func anomalies(body_id: String) -> float:
	var total := 0.0
	for category_id: String in ANOMALY_TYPES:
		var a := anomaly_for(body_id, category_id)
		if a != null:
			total += a.rate
	return total


# The last roadmapped category — see Docs/Buildings System.md's Atmospheric
# Science section. Gas/ice giants use their own turbulence/storminess/
# band_contrast facts (Entry.gas_*, hand-authored from real astronomy — see
# that field's own comment on why there was no existing render value to
# promote); terrestrial/moon bodies weigh atmosphere thickness, ocean_level,
# a "has_life" stand-in, and Entry.atmospheric_turbulence together — "a
# thin-but-active atmosphere (Earth) should outscore a thick-but-static one
# (Venus)" is the whole point of that last term.
#
# `has_life` in the original doc formula has no backing data anywhere (same
# finding as the Life Sciences/Anomalies passes — no "confirmed life
# discovered" system exists in code) — substituted with a threshold on the
# already-computed life_sciences() rate instead of inventing a new unbacked
# boolean fact.
static func atmospheric(body_id: String) -> float:
	var entry := KnownBodies.get_entry(body_id)
	if entry == null or not entry.has_atmosphere:
		return 0.0
	if entry.body_type == "Gas Giant" or entry.body_type == "Ice Giant":
		return ATMOSPHERIC_GAS_BASE + entry.gas_turbulence * ATMOSPHERIC_GAS_TURBULENCE_WEIGHT \
				+ entry.gas_storminess * ATMOSPHERIC_GAS_STORMINESS_WEIGHT + entry.gas_band_contrast * ATMOSPHERIC_GAS_BAND_CONTRAST_WEIGHT
	var life_bonus := ATMOSPHERIC_LIFE_BONUS if life_sciences(body_id) >= ATMOSPHERIC_LIFE_SCIENCES_THRESHOLD else 0.0
	return entry.atmosphere * ATMOSPHERIC_TERRESTRIAL_ATMOSPHERE_WEIGHT + entry.ocean_level * ATMOSPHERIC_TERRESTRIAL_OCEAN_WEIGHT \
			+ life_bonus + entry.atmospheric_turbulence * ATMOSPHERIC_TURBULENCE_WEIGHT
