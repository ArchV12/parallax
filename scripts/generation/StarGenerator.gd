class_name StarGenerator
extends RefCounted

# Procedural star builder — a self-luminous plasma sphere, not a lit rocky
# surface. The surface shader is fully unshaded/emissive so the star looks
# the same from every angle: it has no day/night side, because it IS the
# light source. Surface shows granulation (fine convective turbulence) and
# sunspots (sparse dark blotches); an optional corona shell reuses the same
# path-length shell technique as a planet's atmosphere, but with day-side
# dimming disabled (self_luminous) since a star has no dark limb.

const STAR_SHADER := preload("res://shaders/star_surface.gdshader")
const CORONA_SHADER := preload("res://shaders/atmosphere.gdshader")

# Key (Kelvin, Color) stops for a rough blackbody-ish gradient — not
# physically exact, but the right shape: red dwarfs -> orange/yellow (Sun) ->
# white -> blue-white as temperature climbs.
const TEMP_STOPS: Array = [
	[3000.0, Color(1.0, 0.42, 0.22)],
	[4500.0, Color(1.0, 0.65, 0.4)],
	[5800.0, Color(1.0, 0.95, 0.85)],
	[7500.0, Color(0.95, 0.97, 1.0)],
	[10000.0, Color(0.65, 0.75, 1.0)],
	[30000.0, Color(0.55, 0.62, 1.0)],
]

static func generate(params: StarParams) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = params.seed_value
	var base_color := _color_for_temperature(params.temperature)
	# Slight seed-based hue jitter so two stars at the same temperature
	# aren't pixel-identical, without undermining what the slider means.
	base_color = base_color.lerp(Color.from_hsv(rng.randf(), 0.5, 1.0), 0.04)

	var root := Node3D.new()
	root.name = "Star"
	root.add_child(_build_body(params, rng, base_color))
	if params.corona > 0.01:
		root.add_child(_build_corona(params, base_color))
	return root


static func _build_body(params: StarParams, rng: RandomNumberGenerator, base_color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = params.radius
	mesh.height = params.radius * 2.0
	mesh.radial_segments = 96
	mesh.rings = 64

	var mat := ShaderMaterial.new()
	mat.shader = STAR_SHADER
	mat.set_shader_parameter("seed_offset", rng.randf_range(0.0, 20.0))
	mat.set_shader_parameter("turbulence", params.turbulence)
	mat.set_shader_parameter("spot_activity", params.spot_activity)
	mat.set_shader_parameter("star_color", base_color)
	mat.set_shader_parameter("spot_color", base_color.darkened(0.75))

	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func _build_corona(params: StarParams, base_color: Color) -> MeshInstance3D:
	var r: float = params.radius * (1.0 + 0.06 + 0.35 * params.corona)
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 96
	mesh.rings = 48

	var mat := ShaderMaterial.new()
	mat.shader = CORONA_SHADER
	mat.set_shader_parameter("atmo_color", base_color)
	mat.set_shader_parameter("density", params.corona)
	mat.set_shader_parameter("falloff", params.corona_falloff)
	mat.set_shader_parameter("planet_radius", params.radius)
	mat.set_shader_parameter("shell_radius", r)
	mat.set_shader_parameter("self_luminous", true)
	mat.render_priority = 1

	var mi := MeshInstance3D.new()
	mi.name = "Corona"
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func _color_for_temperature(k: float) -> Color:
	var kelvin := clampf(k, TEMP_STOPS[0][0], TEMP_STOPS[TEMP_STOPS.size() - 1][0])
	for i in range(TEMP_STOPS.size() - 1):
		var lo: Array = TEMP_STOPS[i]
		var hi: Array = TEMP_STOPS[i + 1]
		if kelvin <= (hi[0] as float):
			var t := inverse_lerp(lo[0] as float, hi[0] as float, kelvin)
			return (lo[1] as Color).lerp(hi[1] as Color, t)
	return TEMP_STOPS[TEMP_STOPS.size() - 1][1]
