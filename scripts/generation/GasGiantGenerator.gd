class_name GasGiantGenerator
extends RefCounted

# Procedural gas/ice giant builder — deterministic like PlanetGenerator, but a
# completely different pipeline: no vertex terrain, no ocean. A smooth sphere
# wears a banded, turbulence-warped cloud shader, wrapped in the same
# atmosphere shell used by rocky planets (giants are mostly atmosphere by
# volume, so it's the dominant visual here). Optionally wears a ring system
# (RingSystem, shared with any other body type that gets rings later).

const ATMO_SHADER := preload("res://shaders/atmosphere.gdshader")
const GIANT_SHADER := preload("res://shaders/gas_giant.gdshader")

static func generate(params: GasGiantParams) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = params.seed_value
	var palette := _make_palette(rng, params.ice)

	var root := Node3D.new()
	root.name = "IceGiant" if params.ice else "GasGiant"
	root.add_child(_build_body(params, rng, palette))
	if params.atmosphere > 0.01:
		root.add_child(_build_atmosphere(params, palette))
	if params.rings > 0.01:
		root.add_child(RingSystem.build(rng, params.radius, params.rings, palette["ring_tint"]))
	return root


static func _build_body(params: GasGiantParams, rng: RandomNumberGenerator, palette: Dictionary) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = params.radius
	mesh.height = params.radius * 2.0
	mesh.radial_segments = 96
	mesh.rings = 64

	var mat := ShaderMaterial.new()
	mat.shader = GIANT_SHADER
	# Small range on purpose — the shader scales this into its noise domain,
	# and large offsets exhaust float precision (blocky artifacts).
	mat.set_shader_parameter("seed_offset", rng.randf_range(0.0, 20.0))
	mat.set_shader_parameter("band_scale", params.band_scale)
	mat.set_shader_parameter("turbulence", params.turbulence)
	mat.set_shader_parameter("storminess", params.storminess)
	mat.set_shader_parameter("band_contrast", params.band_contrast)
	mat.set_shader_parameter("color_a", palette["band_a"])
	mat.set_shader_parameter("color_b", palette["band_b"])
	mat.set_shader_parameter("color_c", palette["band_c"])
	mat.set_shader_parameter("storm_color", palette["storm"])

	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func _build_atmosphere(params: GasGiantParams, palette: Dictionary) -> MeshInstance3D:
	var r: float = params.radius * (1.0 + 0.05 + 0.12 * params.atmosphere)
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 96
	mesh.rings = 48

	var mat := ShaderMaterial.new()
	mat.shader = ATMO_SHADER
	mat.set_shader_parameter("atmo_color", palette["atmo"])
	mat.set_shader_parameter("density", params.atmosphere)
	mat.set_shader_parameter("falloff", params.atmo_falloff)
	mat.set_shader_parameter("planet_radius", params.radius)
	mat.set_shader_parameter("shell_radius", r)
	mat.render_priority = 1

	var mi := MeshInstance3D.new()
	mi.name = "Atmosphere"
	mi.mesh = mesh
	mi.material_override = mat
	return mi


# Seed-derived color scheme. Gas giants lean warm (Jupiter/Saturn tones) with
# an occasional alien hue; ice giants lean cool blue/cyan with calmer storms.
static func _make_palette(rng: RandomNumberGenerator, ice: bool) -> Dictionary:
	var hue: float
	var sat: float
	if ice:
		hue = rng.randf_range(0.5, 0.62)
		sat = rng.randf_range(0.2, 0.4)
	else:
		hue = rng.randf_range(0.05, 0.13) if rng.randf() < 0.7 else rng.randf()
		sat = rng.randf_range(0.35, 0.6)

	var band_a := Color.from_hsv(hue, sat, rng.randf_range(0.75, 0.95))
	var band_b := Color.from_hsv(
		fposmod(hue + rng.randf_range(-0.05, 0.08), 1.0),
		sat * rng.randf_range(0.7, 1.1),
		rng.randf_range(0.55, 0.8))
	var band_c := Color.from_hsv(
		fposmod(hue + rng.randf_range(-0.1, 0.1), 1.0),
		sat * rng.randf_range(0.5, 0.9),
		rng.randf_range(0.4, 0.65))
	var storm := Color(0.95, 0.97, 1.0) if ice else \
		Color.from_hsv(fposmod(hue + 0.5, 1.0), sat * 1.2, rng.randf_range(0.6, 0.9))

	var atmo_hue := rng.randf_range(0.55, 0.62) if ice else hue
	var atmo := Color.from_hsv(atmo_hue, sat * 0.8, rng.randf_range(0.85, 1.0))

	# Rings are pale — mostly dust/ice, tinted only faintly by the body's hue.
	var ring_tint := Color.from_hsv(
		fposmod(hue + rng.randf_range(-0.05, 0.05), 1.0),
		sat * 0.35,
		rng.randf_range(0.55, 0.75))

	return {
		"band_a": band_a,
		"band_b": band_b,
		"band_c": band_c,
		"storm":  storm,
		"atmo":   atmo,
		"ring_tint": ring_tint,
	}
