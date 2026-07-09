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
# Craters layer on top the same way MoonGenerator does, sharing CraterField
# and Icosphere with it.

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
	root.add_child(_build_terrain(params, shape_noise, craters, elong_axis, palette))
	return root


static func _build_terrain(params: AsteroidParams, shape_noise: FastNoiseLite,
		craters: Array, elong_axis: Vector3, palette: Dictionary) -> MeshInstance3D:
	var sphere := Icosphere.build(params.detail)
	var verts: PackedVector3Array = sphere[0]
	var indices: PackedInt32Array = sphere[1]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for unit in verts:
		# FBM simplex noise is already zero-centered, so this bulges AND dents
		# the shape symmetrically — no recentring needed.
		var shape_h := shape_noise.get_noise_3dv(unit) * params.irregularity
		var crater_h := CraterField.height_at(unit, craters, params.crater_depth)
		var h := shape_h + crater_h
		st.set_color(_height_color(h, palette))

		var pos := unit * params.radius * (1.0 + h)
		# Directional stretch: extra length added along elong_axis
		# proportional to how far the point already sits along it.
		var along := pos.dot(elong_axis)
		pos += elong_axis * along * params.elongation
		st.add_vertex(pos)
	for idx in indices:
		st.add_index(idx)
	st.generate_normals()

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


static func _height_color(h: float, palette: Dictionary) -> Color:
	var t := clampf((h + 0.35) / 0.6, 0.0, 1.0)
	var col: Color = (palette["dark"] as Color).lerp(palette["mid"] as Color, smoothstep(0.0, 0.5, t))
	col = col.lerp(palette["light"] as Color, smoothstep(0.5, 1.0, t))
	return col


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
