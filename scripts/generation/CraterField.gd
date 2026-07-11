class_name CraterField
extends RefCounted

# Shared impact-crater placement + height evaluation, used by any generator
# with a cratered airless surface (moons, asteroids...) so the profile only
# has to be tuned in one place.

# `size` is the MAXIMUM crater radius (as a fraction of body radius), not
# the average — sizes follow a rough power law below it, like real impact
# populations (our Moon: a couple of giant basins, thousands of small
# craters). pow(u, 2.5) on a uniform sample skews hard toward small: the
# median crater lands under a fifth of the max, and anything near the max
# is rare. The 0.12 floor keeps the smallest craters actually visible
# rather than spending the budget on sub-pixel pits. (Earlier version
# rolled uniform 0.35-1.7x around an average — craters all came out
# roughly the same middling size, which reads as artificial.)
static func make(rng: RandomNumberGenerator, density: float, size: float) -> Array:
	# Ceiling must stay == cratered_surface.gdshader's MAX_CRATERS (its
	# uniform arrays are fixed-size). 400 because max density should read as
	# genuinely PEPPERED — the old 140 cap spread over a whole sphere still
	# looked sparse, especially now that the power-law size roll makes most
	# craters small.
	var count := int(lerpf(6.0, 400.0, density))
	var craters: Array = []
	for i in count:
		# Random points on the unit sphere via Marsaglia's method (three
		# independent normals, normalized) — plain random spherical
		# coordinates would bunch craters near the poles.
		var center := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var size_frac := lerpf(0.12, 1.0, pow(rng.randf(), 2.5))
		craters.append({"center": center, "radius": size * size_frac})
	# Biggest first: list order is impact order (height_at overwrites in
	# order, later = younger), and on real bodies the giant impacts are
	# overwhelmingly ancient — sorting descending means small young craters
	# pepper the floors and rims of the big old ones (the classic lunar
	# look), and a late giant never wipes an entire small-crater field.
	craters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["radius"] > b["radius"])
	return craters


# Height contribution (as a fraction of body radius) at a surface point.
# Craters apply in LIST ORDER, each overwriting whatever is beneath its
# footprint (list order = impact order; later craters are younger) — real
# stratigraphy: a younger impact's bowl erases any older rim arc it lands
# on, and its own rim cuts cleanly across older bowls. Not a sum (summing
# overlaps stacks into implausibly deep pits in dense fields), and not
# "strongest contribution wins" either — that earlier rule compared by
# MAGNITUDE, so where a rim (+0.35 peak) crossed a deep bowl (-1.0), the
# winner flip-flopped through thin bands of the bowl's shallow profile
# zones, rendering as spiky star/sliver artifacts at every crater overlap
# (glaring once cratered_surface.gdshader started painting craters
# per-pixel; keep that shader's crater_signal() in sync with this).
# The overwrite fades over the outer falloff annulus (x 1.0..1.25) so a
# young crater's surroundings still blend into the older terrain instead
# of stamping a hard-edged disc of flatness around itself.
static func height_at(unit: Vector3, craters: Array, depth: float) -> float:
	var h := 0.0
	for crater: Dictionary in craters:
		var center: Vector3 = crater["center"]
		var radius: float = crater["radius"]
		var max_reach := radius * 1.25
		var d2 := unit.distance_squared_to(center)
		if d2 > max_reach * max_reach:
			continue
		var x := sqrt(d2) / radius
		var influence := 1.0 - smoothstep(1.0, 1.25, x)
		h = lerpf(h, _profile(x) * depth, influence)
	return h


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
