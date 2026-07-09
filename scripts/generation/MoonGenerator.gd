class_name MoonGenerator
extends RefCounted

# Procedural moon builder — deterministic like PlanetGenerator, but a
# different terrain philosophy: no ocean, no atmosphere, surface dominated
# by impact craters rather than continents. Shares Icosphere (seamless
# sphere mesh) and CraterField (crater placement/profile) with the other
# generators.

static func generate(params: MoonParams) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = params.seed_value
	var palette := _make_palette(rng)
	var craters := CraterField.make(rng, params.crater_density, params.crater_size)

	var base_noise := FastNoiseLite.new()
	base_noise.seed = params.seed_value
	base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	base_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	base_noise.fractal_octaves = 4
	base_noise.frequency = 1.5

	var root := Node3D.new()
	root.name = "Moon"
	root.add_child(_build_terrain(params, base_noise, craters, palette))
	return root


static func _build_terrain(params: MoonParams, base_noise: FastNoiseLite,
		craters: Array, palette: Dictionary) -> MeshInstance3D:
	var sphere := Icosphere.build(params.detail)
	var verts: PackedVector3Array = sphere[0]
	var indices: PackedInt32Array = sphere[1]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for unit in verts:
		var h := _height_at(unit, base_noise, craters, params)
		st.set_color(_height_color(h, palette))
		st.add_vertex(unit * params.radius * (1.0 + h))
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


static func _height_at(unit: Vector3, base_noise: FastNoiseLite, craters: Array, params: MoonParams) -> float:
	var h := base_noise.get_noise_3dv(unit) * params.surface_roughness
	return h + CraterField.height_at(unit, craters, params.crater_depth)


static func _height_color(h: float, palette: Dictionary) -> Color:
	var t := clampf((h + 0.25) / 0.35, 0.0, 1.0)
	var col: Color = (palette["dark"] as Color).lerp(palette["mid"] as Color, smoothstep(0.0, 0.5, t))
	col = col.lerp(palette["light"] as Color, smoothstep(0.5, 1.0, t))
	return col


# Seed-derived color scheme. Mostly desaturated grays (regolith), with an
# occasional tinted outlier (icy, rusty, sulfurous) for variety.
static func _make_palette(rng: RandomNumberGenerator) -> Dictionary:
	var tinted := rng.randf() < 0.4
	var hue: float = rng.randf() if tinted else rng.randf_range(0.08, 0.12)
	var sat: float = rng.randf_range(0.1, 0.3) if tinted else rng.randf_range(0.03, 0.12)
	return {
		"dark":  Color.from_hsv(hue, sat, rng.randf_range(0.12, 0.22)),
		"mid":   Color.from_hsv(hue, sat * 0.8, rng.randf_range(0.32, 0.42)),
		"light": Color.from_hsv(hue, sat * 0.6, rng.randf_range(0.55, 0.68)),
	}
