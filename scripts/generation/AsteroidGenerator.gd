class_name AsteroidGenerator
extends RefCounted

# Procedural asteroid builder — unlike every other body here, an asteroid's
# BASE SHAPE is irregular, not a lightly-bumped sphere. Low-frequency FBM
# noise (same kind PlanetGenerator uses, just far higher amplitude) displaces
# the surface into broad lumps and dents, and a directional stretch elongates
# the whole body — an approximation of the peanut/contact-binary silhouettes
# real small asteroids often have, without the cost of true metaball
# lobe-blending.
#
# Deliberately NOT ridged noise: ridged formulas (1 - abs(noise)) produce
# thin, sharp ridge lines no matter how low the frequency goes, which at high
# amplitude reads as a spike ball rather than a lumpy rock.
#
# Craters share CraterField/Icosphere with MoonGenerator, AND (2026-07-13)
# its per-pixel cratered_surface.gdshader for actual shading too — the same
# reasoning that shader was written for in the first place (see its own
# header: "Airless rocky surface (moons, asteroids)") applies just as much
# here: a saturated crater field blurs into a flat grey smudge under
# vertex-color interpolation at any sane vertex budget, doubly so on
# asteroids' already-low detail level. See _build_terrain's elongation
# comment for the one adjustment asteroids needed to stay compatible with
# that shader's assumptions.

const TERRAIN_SHADER := preload("res://shaders/cratered_surface.gdshader")


static func generate(params: AsteroidParams) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = params.seed_value
	var palette := _make_palette(rng)
	var craters := CraterField.make(rng, params.crater_density, params.crater_size)
	var elong_axis := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()

	var shape_noise := FastNoiseLite.new()
	shape_noise.seed = params.seed_value
	shape_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	shape_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	shape_noise.fractal_octaves = 3   # few octaves = broad lumps, not fine high-frequency detail
	shape_noise.frequency = 0.7        # low frequency = a handful of dents/bulges across the whole body

	var root := Node3D.new()
	root.name = "Asteroid"
	root.add_child(_build_terrain(params, shape_noise, craters, elong_axis, palette, rng))
	return root


static func _build_terrain(params: AsteroidParams, shape_noise: FastNoiseLite, craters: Dictionary,
		elong_axis: Vector3, palette: Dictionary, rng: RandomNumberGenerator) -> MeshInstance3D:
	var sphere := Icosphere.build(params.detail)
	var verts: PackedVector3Array = sphere[0]
	var indices: PackedInt32Array = sphere[1]
	# Pulled out of the Dictionary ONCE, not once per vertex — see
	# CraterField's own class comment on why that distinction matters.
	var centers: PackedVector3Array = craters["centers"]
	var radii: PackedFloat32Array = craters["radii"]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for unit in verts:
		# FBM simplex noise is already zero-centered, so this bulges AND dents
		# the shape symmetrically — no recentring needed.
		var shape_h := shape_noise.get_noise_3dv(unit) * params.irregularity
		var crater_h := CraterField.height_at(unit, centers, radii, params.crater_depth)
		var h := shape_h + crater_h

		# Elongation folded into the RADIAL scale itself (bigger near the
		# elong_axis poles, unchanged at its equator) rather than the old
		# additive sideways offset — keeps the whole displacement a pure
		# scalar multiple of `unit`, which is exactly what
		# cratered_surface.gdshader's normalize(VERTEX) trick requires to
		# recover the true crater-lookup direction per pixel (see its header
		# comment). A true affine stretch displaces sideways too, which
		# would feed the shader a direction that no longer matches what
		# CraterField was actually evaluated against on the CPU — rims
		# would drift off their geometric bowls.
		var elong_factor := 1.0 + params.elongation * absf(unit.dot(elong_axis))
		# Floored well above 0 — at extreme irregularity (Cosmic Forge's
		# slider goes well past what's ever actually used in-game), shape
		# noise alone can push h below -1, which without this flips (1.0+h)
		# negative and turns the surface inside-out at that vertex: the
		# mesh folds back through the origin and out the other side,
		# rendering as the long inward-pointing spikes/petals of a
		# "flower" asteroid rather than a lumpy rock. This is a hard floor
		# on the geometry itself, not just a slider-range fix, so it can't
		# recur if the sliders ever get widened again later.
		var radial_scale := maxf(1.0 + h, 0.1)
		var pos := unit * params.radius * radial_scale * elong_factor
		st.add_vertex(pos)
	for idx in indices:
		st.add_index(idx)
	st.generate_normals()

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = st.commit()
	mi.material_override = _build_material(craters, palette, rng)
	return mi


# Mirrors MoonGenerator._build_material exactly — same shader, same uniform
# shapes, just fed this generator's own asteroid-flavored palette below.
static func _build_material(craters: Dictionary, palette: Dictionary, rng: RandomNumberGenerator) -> ShaderMaterial:
	var centers: PackedVector3Array = craters["centers"]
	var radii: PackedFloat32Array = craters["radii"]

	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("crater_centers", centers)
	mat.set_shader_parameter("crater_radii", radii)
	mat.set_shader_parameter("crater_count", centers.size())
	# Same rim math as moons, but crater_size (fraction of body radius) runs
	# about the same on both — the difference is that an asteroid's whole
	# body occupies far fewer screen pixels than a moon's does, so craters
	# covering a similar FRACTION of the surface end up covering far more of
	# the object's actual on-screen presence. The rim highlight the moon
	# shader default (0.08) was tuned to be "a hint of lift" on a mostly-
	# plain surface reads as the asteroid's dominant feature instead —
	# dropped to 0 here rather than touching the shared default and
	# affecting moons too.
	mat.set_shader_parameter("rim_strength", 0.0)
	mat.set_shader_parameter("color_dark", palette["dark"])
	mat.set_shader_parameter("color_mid", palette["mid"])
	mat.set_shader_parameter("color_light", palette["light"])
	mat.set_shader_parameter("seed_offset", rng.randf_range(0.0, 20.0))
	return mat


# Seed-derived color scheme, loosely modeled on real asteroid spectral
# classes: mostly dark carbonaceous grays (C-type, most common in the belt),
# sometimes a warmer, brighter silicate tone (S-type), rarely a cool
# metallic sheen (M-type).
static func _make_palette(rng: RandomNumberGenerator) -> Dictionary:
	var roll := rng.randf()
	var hue: float
	var sat: float
	var val_boost: float
	if roll < 0.55:
		hue = rng.randf_range(0.06, 0.1)
		sat = rng.randf_range(0.02, 0.08)
		val_boost = 0.0
	elif roll < 0.85:
		hue = rng.randf_range(0.05, 0.09)
		sat = rng.randf_range(0.15, 0.32)
		val_boost = 0.08
	else:
		hue = rng.randf_range(0.55, 0.62)
		sat = rng.randf_range(0.04, 0.1)
		val_boost = 0.05

	return {
		"dark":  Color.from_hsv(hue, sat, rng.randf_range(0.08, 0.16) + val_boost * 0.5),
		"mid":   Color.from_hsv(hue, sat * 0.9, rng.randf_range(0.22, 0.32) + val_boost),
		"light": Color.from_hsv(hue, sat * 0.7, rng.randf_range(0.42, 0.55) + val_boost),
	}
