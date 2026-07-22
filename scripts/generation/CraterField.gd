class_name CraterField
extends RefCounted

# Shared impact-crater placement + height evaluation, used by any generator
# with a cratered airless surface (moons, asteroids, comet nuclei...) so the
# profile only has to be tuned in one place.
#
# make() returns packed arrays ({"centers": PackedVector3Array, "radii":
# PackedFloat32Array}), not an Array of {"center","radius"} Dictionaries
# like it used to (2026-07-13). height_at() runs once per mesh VERTEX per
# crater — at high crater counts (up to 400) and high mesh detail, that's
# well into the tens of millions of iterations for a single body, and a
# scene spawning dozens of bodies at once (SystemView's asteroid field) pays
# that cost dozens of times over in one synchronous burst. Dictionary key
# lookups in that inner loop turned out to dominate the whole cost — visibly
# stalling the game for several seconds — where packed-array indexing (flat,
# contiguous, no per-access hashing) does not. The one-time crater ROLL
# below still builds/sorts an Array of Dictionaries internally, same as
# before — that only runs once per body, never per vertex, so it was never
# the hot path.

# `size` is the MAXIMUM crater radius (as a fraction of body radius) — a
# CEILING on how big a crater can get, not the average. Sizes follow a steep
# power law below it, like real impact populations (a rare giant basin or
# two, overwhelmingly small craters). pow(u, 4.0) skews hard toward small:
# the median crater lands around an eighth of the max and anything near the
# ceiling is genuinely rare, so raising Max Crater Size widens the ceiling
# WITHOUT flooding the surface with big craters. The 0.06 floor just keeps
# the smallest from being sub-pixel pits that waste the count budget.
# (History: a uniform 0.35-1.7x roll made every crater the same middling
# size — artificial; a later pow(u, 2.5) was better but still let ~a quarter
# of craters exceed half the max, reading as "a bunch of large craters.")
static func make(rng: RandomNumberGenerator, density: float, size: float) -> Dictionary:
	# Ceiling must stay == cratered_surface.gdshader's MAX_CRATERS (its
	# uniform arrays are fixed-size). 400 because max density should read as
	# genuinely PEPPERED — the old 140 cap spread over a whole sphere still
	# looked sparse, especially now that the power-law size roll makes most
	# craters small.
	var count := int(lerpf(6.0, 400.0, density))
	var rolled: Array = []
	for i in count:
		# Random points on the unit sphere via Marsaglia's method (three
		# independent normals, normalized) — plain random spherical
		# coordinates would bunch craters near the poles.
		var center := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var size_frac := lerpf(0.06, 1.0, pow(rng.randf(), 4.0))
		# Freshness: 0 = ancient/eroded ghost, 1 = pristine sharp crater. Skewed
		# hard toward OLD (pow(u, 1.8)) because a real surface is dominated by
		# degraded craters with only a few fresh ones — the freshness value
		# scales the whole profile (depth AND rim), so old craters read as faint
		# soft depressions with no bright rim rather than crisp bowls. Big
		# craters skew older still (lerp toward 0.4): the giant overlapping
		# basins were exactly the ones reading as bright-rimmed "bubbles", and
		# on real bodies the largest impacts are overwhelmingly the most ancient.
		var fresh := pow(rng.randf(), 1.8) * lerpf(1.0, 0.4, size_frac)
		rolled.append({"center": center, "radius": size * size_frac, "freshness": fresh})
	# Biggest first: list order is impact order (height_at overwrites in
	# order, later = younger), and on real bodies the giant impacts are
	# overwhelmingly ancient — sorting descending means small young craters
	# pepper the floors and rims of the big old ones (the classic lunar
	# look), and a late giant never wipes an entire small-crater field.
	rolled.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["radius"] > b["radius"])

	var centers := PackedVector3Array()
	var radii := PackedFloat32Array()
	var freshness := PackedFloat32Array()
	centers.resize(rolled.size())
	radii.resize(rolled.size())
	freshness.resize(rolled.size())
	for i in rolled.size():
		centers[i] = rolled[i]["center"]
		radii[i] = rolled[i]["radius"]
		freshness[i] = rolled[i]["freshness"]
	return {"centers": centers, "radii": radii, "freshness": freshness}


# Height contribution (as a fraction of body radius) at a surface point.
# Craters apply in ARRAY ORDER, each overwriting whatever is beneath its
# footprint (array order = impact order; later craters are younger) — real
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
#
# Takes the two packed arrays directly rather than make()'s wrapping
# Dictionary — callers pull those out ONCE before their vertex loop (see
# MoonGenerator/AsteroidGenerator/CometGenerator), not once per vertex.
# freshness (optional; must line up 1:1 with centers/radii when supplied)
# scales each crater's whole profile so old craters are shallow and soft —
# amp = lerp(0.25, 1.0, freshness). Callers that don't pass it (asteroid/comet)
# get amp 1.0, i.e. the pre-freshness behavior unchanged. cratered_surface
# .gdshader applies the identical amp so geometry and shading stay in sync.
static func height_at(unit: Vector3, centers: PackedVector3Array, radii: PackedFloat32Array,
		depth: float, freshness: PackedFloat32Array = PackedFloat32Array()) -> float:
	var h := 0.0
	var has_fresh := freshness.size() == centers.size()
	for i in centers.size():
		var radius := radii[i]
		var max_reach := radius * 1.25
		var d2 := unit.distance_squared_to(centers[i])
		if d2 > max_reach * max_reach:
			continue
		var x := sqrt(d2) / radius
		var influence := 1.0 - smoothstep(1.0, 1.25, x)
		var amp := 1.0
		if has_fresh:
			amp = lerpf(0.25, 1.0, freshness[i])
		h = lerpf(h, _profile(x) * depth * amp, influence)
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
