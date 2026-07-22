class_name MoonGenerator
extends RefCounted

# Procedural moon builder — deterministic like PlanetGenerator, but a
# different terrain philosophy: no ocean, no atmosphere, surface dominated
# by impact craters rather than continents. Shares Icosphere (seamless
# sphere mesh) and CraterField (crater placement/profile) with the other
# generators.
#
# Geometry displacement (the actual bumps/bowls) is computed here on the CPU
# as before. SHADING is not — a saturated crater field can have well over a
# hundred craters, most too small for a sane vertex budget to resolve, so
# vertex-color shading (the original approach) either blurred them into a
# faint painted smudge or needed an expensive mesh to look sharp. Surface
# color now comes from cratered_surface.gdshader, which recomputes the SAME
# crater math analytically per pixel instead of interpolating it from a
# handful of nearby vertices — crisp rims regardless of mesh resolution,
# plus fine regolith speckle a smooth vertex gradient could never produce.
# See that shader's header comment for the CraterField.gd correspondence.

const TERRAIN_SHADER := preload("res://shaders/cratered_surface.gdshader")

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
	root.add_child(_build_terrain(params, base_noise, craters, palette, rng))
	return root


static func _build_terrain(params: MoonParams, base_noise: FastNoiseLite,
		craters: Dictionary, palette: Dictionary, rng: RandomNumberGenerator) -> MeshInstance3D:
	var sphere := Icosphere.build(params.detail)
	var verts: PackedVector3Array = sphere[0]
	var indices: PackedInt32Array = sphere[1]
	# Pulled out of the Dictionary ONCE, not once per vertex — see
	# CraterField's own class comment on why that distinction matters.
	var centers: PackedVector3Array = craters["centers"]
	var radii: PackedFloat32Array = craters["radii"]
	var freshness: PackedFloat32Array = craters["freshness"]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for unit in verts:
		var h := _height_at(unit, base_noise, centers, radii, freshness, params)
		st.add_vertex(unit * params.radius * (1.0 + h))
	for idx in indices:
		st.add_index(idx)
	st.generate_normals()

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = st.commit()
	mi.material_override = _build_material(craters, palette, rng)
	return mi


static func _build_material(craters: Dictionary, palette: Dictionary, rng: RandomNumberGenerator) -> ShaderMaterial:
	# centers/radii are at most 400 entries each (CraterField.make's own cap,
	# since crater_density is clamped to [0, 1]) — matches
	# cratered_surface.gdshader's MAX_CRATERS array size exactly, so every
	# entry here always fits.
	var centers: PackedVector3Array = craters["centers"]
	var radii: PackedFloat32Array = craters["radii"]
	var freshness: PackedFloat32Array = craters["freshness"]

	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("crater_centers", centers)
	mat.set_shader_parameter("crater_radii", radii)
	mat.set_shader_parameter("crater_freshness", freshness)
	mat.set_shader_parameter("crater_count", centers.size())
	# No crater_depth uniform — the shader shades in raw profile units so the
	# palette always spans dark bowls to bright rims; crater_depth remains a
	# pure geometry knob (how deep the mesh displacement actually is).
	mat.set_shader_parameter("color_dark", palette["dark"])
	mat.set_shader_parameter("color_mid", palette["mid"])
	mat.set_shader_parameter("color_light", palette["light"])
	# Small range on purpose — the shader scales this into its noise domain,
	# and large offsets exhaust float precision (blocky artifacts). Same
	# convention as GasGiantGenerator/StarGenerator/CometGenerator.
	mat.set_shader_parameter("seed_offset", rng.randf_range(0.0, 20.0))
	return mat


static func _height_at(unit: Vector3, base_noise: FastNoiseLite,
		centers: PackedVector3Array, radii: PackedFloat32Array,
		freshness: PackedFloat32Array, params: MoonParams) -> float:
	var h := base_noise.get_noise_3dv(unit) * params.surface_roughness
	return h + CraterField.height_at(unit, centers, radii, params.crater_depth, freshness)


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
