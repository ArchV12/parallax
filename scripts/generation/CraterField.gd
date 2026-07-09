class_name CraterField
extends RefCounted

# Shared impact-crater placement + height evaluation, used by any generator
# with a cratered airless surface (moons, asteroids...) so the profile only
# has to be tuned in one place.

static func make(rng: RandomNumberGenerator, density: float, size: float) -> Array:
	var count := int(lerpf(6.0, 140.0, density))
	var craters: Array = []
	for i in count:
		# Random points on the unit sphere via Marsaglia's method (three
		# independent normals, normalized) — plain random spherical
		# coordinates would bunch craters near the poles.
		var center := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var size_variance := rng.randf_range(0.35, 1.7)  # a few big craters, many small
		craters.append({"center": center, "radius": size * size_variance})
	return craters


# Height contribution (as a fraction of body radius) at a surface point —
# the single DOMINANT crater at this point, not a sum. Summing every
# overlapping crater would stack into implausibly deep pits in dense fields;
# picking the strongest match is what a real saturated crater field actually
# looks like (each crater overwrites what's beneath it).
static func height_at(unit: Vector3, craters: Array, depth: float) -> float:
	var strongest := 0.0
	for crater: Dictionary in craters:
		var center: Vector3 = crater["center"]
		var radius: float = crater["radius"]
		var max_reach := radius * 1.25
		var d2 := unit.distance_squared_to(center)
		if d2 > max_reach * max_reach:
			continue
		var x := sqrt(d2) / radius
		var c := _profile(x) * depth
		if absf(c) > absf(strongest):
			strongest = c
	return strongest


# x = chordal distance / crater radius: 0 at center, 1 at rim, 1.25 blended
# fully back to the surrounding terrain. Bowl floor -> rising wall -> raised
# rim -> smooth falloff, each a smoothstep-eased lerp between key points.
static func _profile(x: float) -> float:
	if x >= 1.25:
		return 0.0
	if x >= 1.0:
		return lerpf(0.35, 0.0, smoothstep(1.0, 1.25, x))
	if x >= 0.85:
		return lerpf(-0.2, 0.35, smoothstep(0.85, 1.0, x))
	return lerpf(-1.0, -0.2, smoothstep(0.0, 0.85, x))
