class_name NativeRate
extends RefCounted

# How much a body's OWN properties support each Knowledge category — a
# 0-100ish value Buildings.gd multiplies by a structure's tier multiplier.
# Isolated from Buildings.gd so the 5 roadmapped categories (Docs/Buildings
# System.md) are an obvious later extension point: add a match branch here,
# nothing else needs to change.

const GAS_GIANT_STAR_FLAT_RATE := 15.0
const ATMOSPHERE_PRESERVATION_PENALTY := 0.4
const PRESERVATION_MIN := 0.2


static func for_category(category_id: String, body_id: String) -> float:
	match category_id:
		"geological":
			return geology(body_id)
		_:
			return 0.0  # atmospheric/life_sciences/astrophysics/anomalies — not implemented this phase


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
