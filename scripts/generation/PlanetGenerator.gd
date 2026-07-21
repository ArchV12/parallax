class_name PlanetGenerator
extends RefCounted

# Procedural planet builder — deterministic: the same PlanetParams always
# yields the same planet. Owned by no scene; the Cosmic Forge drives it today
# and the game's system generator will drive it later.
#
# Output is a Node3D containing:
#   - "Terrain": icosphere displaced by seeded FBM noise; the mesh carries only
#     macro relief + a per-vertex base height (in UV.x), and planet_surface
#     .gdshader does the height-band coloring and detail-normal bump per pixel
#   - "Ocean" (if ocean_level > 0): translucent sphere at sea level
#   - "Clouds" (if cloud_amount > 0 and there's an atmosphere): translucent
#     shell driven by planet_clouds.gdshader
#   - "Atmosphere" (if atmosphere > 0): limb-glow shell

# FBM output rarely reaches ±1; treat this as the practical height range.
const NOISE_MAX := 0.75

const ATMO_SHADER := preload("res://shaders/atmosphere.gdshader")
const SURFACE_SHADER := preload("res://shaders/planet_surface.gdshader")
const CLOUD_SHADER := preload("res://shaders/planet_clouds.gdshader")

static func generate(params: PlanetParams) -> Node3D:
	# Zero relief would make the terrain and ocean spheres coincident and
	# z-fight (dot shimmer) — the generator guards it rather than trusting
	# every future caller's UI to.
	params.terrain_height = maxf(params.terrain_height, 0.01)

	var rng := RandomNumberGenerator.new()
	rng.seed = params.seed_value
	var palette := _make_palette(rng)
	# Per-planet noise offset so every seed's surface detail (and clouds) differs
	# rather than all sharing one pattern. Pulled after the palette so palette
	# rolls stay identical to before this field existed.
	var detail_seed := rng.randf() * 100.0

	var noise := FastNoiseLite.new()
	noise.seed = params.seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.fractal_gain = params.roughness
	noise.frequency = 0.9 * params.continent_scale

	var sea: float = lerpf(-NOISE_MAX, NOISE_MAX, params.ocean_level)

	var root := Node3D.new()
	root.name = "Planet"
	root.add_child(_build_terrain(params, noise, sea, palette, detail_seed))
	if params.ocean_level > 0.01:
		root.add_child(_build_ocean(params, sea, palette))
	# Clouds need air to float in — an airless rock stays clear regardless of
	# the cloud_amount knob. Built after the ocean, before the atmosphere shell,
	# so the transparent layers stack surface → ocean → clouds → atmo glow.
	if params.cloud_amount > 0.01 and params.atmosphere > 0.02:
		root.add_child(_build_clouds(params, detail_seed))
	if params.atmosphere > 0.01:
		root.add_child(_build_atmosphere(params, palette))
	return root


# --- Terrain ---

static func _build_terrain(params: PlanetParams, noise: FastNoiseLite,
		sea: float, palette: Dictionary, detail_seed: float) -> MeshInstance3D:
	var sphere := Icosphere.build(params.detail)
	var verts: PackedVector3Array = sphere[0]
	var indices: PackedInt32Array = sphere[1]

	# The mesh carries macro relief (radial displacement) and the raw base
	# height in UV.x — full float precision, no other use for the icosphere's
	# UVs — for the shader to band per pixel.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for unit in verts:
		var h := noise.get_noise_3dv(unit)
		st.set_uv(Vector2(h, 0.0))
		st.add_vertex(unit * params.radius * (1.0 + h * params.terrain_height))
	for idx in indices:
		st.add_index(idx)
	st.generate_normals()

	# surface_detail (0..1) scales both the band-edge jitter and the normal
	# bump; 0 reproduces the old flat, purely macro look.
	var mat := ShaderMaterial.new()
	mat.shader = SURFACE_SHADER
	mat.set_shader_parameter("shallow_color", palette["shallow"])
	mat.set_shader_parameter("deep_color", palette["deep"])
	mat.set_shader_parameter("beach_color", palette["beach"])
	mat.set_shader_parameter("lowland_color", palette["lowland"])
	mat.set_shader_parameter("highland_color", palette["highland"])
	mat.set_shader_parameter("mountain_color", palette["mountain"])
	mat.set_shader_parameter("snow_color", palette["snow"])
	mat.set_shader_parameter("sea", sea)
	mat.set_shader_parameter("noise_max", NOISE_MAX)
	mat.set_shader_parameter("has_caps", palette["has_caps"])
	mat.set_shader_parameter("cap_start", palette["cap_start"])
	mat.set_shader_parameter("detail_freq", 9.0)
	mat.set_shader_parameter("detail_strength", params.surface_detail * 0.05)
	mat.set_shader_parameter("albedo_variation", params.surface_detail * 0.6)
	mat.set_shader_parameter("bump_strength", params.surface_detail * 1.0)
	mat.set_shader_parameter("seed_offset", detail_seed)

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


static func _build_clouds(params: PlanetParams, detail_seed: float) -> MeshInstance3D:
	# Shell sits just above the tallest possible terrain and well inside the
	# atmosphere shell (which starts at +0.04..0.14 radius, see
	# _build_atmosphere), so clouds render beneath the limb glow.
	var surface_r: float = params.radius * (1.0 + params.terrain_height * NOISE_MAX)
	var r: float = surface_r + params.radius * 0.02
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 64
	mesh.rings = 32

	var mat := ShaderMaterial.new()
	mat.shader = CLOUD_SHADER
	mat.set_shader_parameter("coverage", params.cloud_amount)
	mat.set_shader_parameter("cloud_freq", 3.0)
	mat.set_shader_parameter("drift_speed", 0.01)
	# Offset from the surface's own seed so cloud masses don't line up with the
	# terrain detail underneath them.
	mat.set_shader_parameter("seed_offset", detail_seed + 50.0)

	var mi := MeshInstance3D.new()
	mi.name = "Clouds"
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func _build_ocean(params: PlanetParams, sea: float, palette: Dictionary) -> MeshInstance3D:
	var sea_r: float = params.radius * (1.0 + sea * params.terrain_height)
	var mesh := SphereMesh.new()
	mesh.radius = sea_r
	mesh.height = sea_r * 2.0
	mesh.radial_segments = 96
	mesh.rings = 48

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = palette["ocean_surface"]
	# A perfectly smooth sphere reads as a glass marble — real ocean glint is
	# "sun glitter": wave facets smearing the highlight into a broad soft
	# patch. Moderate roughness spreads it; a seeded noise normal map breaks
	# it up so it shimmers instead of gleaming.
	mat.roughness = 0.28
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	var wave_noise := FastNoiseLite.new()
	wave_noise.seed = params.seed_value
	wave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	wave_noise.frequency = 0.03
	var wave_tex := NoiseTexture2D.new()
	wave_tex.noise = wave_noise
	wave_tex.seamless = true
	wave_tex.as_normal_map = true
	wave_tex.bump_strength = 4.0
	mat.normal_enabled = true
	mat.normal_texture = wave_tex
	mat.normal_scale = 0.25
	mat.uv1_scale = Vector3(6, 3, 1)

	var mi := MeshInstance3D.new()
	mi.name = "Ocean"
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func _build_atmosphere(params: PlanetParams, palette: Dictionary) -> MeshInstance3D:
	# Shell sits just above the tallest possible terrain, swelling with
	# density. Generous headroom — the shader's path-length falloff reaches
	# zero at the shell edge, so the mesh boundary is invisible.
	var surface_r: float = params.radius * (1.0 + params.terrain_height * NOISE_MAX)
	var r: float = surface_r + params.radius * (0.04 + 0.10 * params.atmosphere)
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
	# Draw after the ocean so the additive glow layers over the water at the limb.
	mat.render_priority = 1

	var mi := MeshInstance3D.new()
	mi.name = "Atmosphere"
	mi.mesh = mesh
	mi.material_override = mat
	return mi


# --- Height → color ---
# The height → band-color ramp now lives in planet_surface.gdshader (evaluated
# per pixel); _make_palette below just supplies its color inputs.

# Seed-derived color scheme. Mostly earthlike ranges with a chance of going
# fully alien — variety is the point while we hone the generator.
static func _make_palette(rng: RandomNumberGenerator) -> Dictionary:
	var alien := rng.randf() < 0.35

	var land_hue := rng.randf() if alien else rng.randf_range(0.07, 0.38)
	var land_sat := rng.randf_range(0.25, 0.55)
	var lowland := Color.from_hsv(land_hue, land_sat, rng.randf_range(0.35, 0.55))
	var highland := Color.from_hsv(
		fposmod(land_hue + rng.randf_range(-0.06, 0.06), 1.0),
		land_sat * rng.randf_range(0.5, 0.9),
		lowland.v * rng.randf_range(0.55, 0.8))
	var mountain := Color.from_hsv(land_hue, land_sat * 0.2, rng.randf_range(0.3, 0.45))

	var ocean_hue := rng.randf() if (alien and rng.randf() < 0.5) else rng.randf_range(0.5, 0.68)
	var ocean_sat := rng.randf_range(0.5, 0.8)

	var atmo_hue := rng.randf() if (alien and rng.randf() < 0.5) else rng.randf_range(0.52, 0.62)
	var atmo := Color.from_hsv(atmo_hue, rng.randf_range(0.45, 0.7), rng.randf_range(0.85, 1.0))
	var shallow := Color.from_hsv(ocean_hue, ocean_sat * 0.8, rng.randf_range(0.4, 0.6))
	var deep := Color.from_hsv(ocean_hue, ocean_sat, rng.randf_range(0.10, 0.22))
	var surface := Color.from_hsv(ocean_hue, ocean_sat * 0.9, rng.randf_range(0.35, 0.55), 0.72)

	return {
		"lowland":  lowland,
		"highland": highland,
		"mountain": mountain,
		"beach":    Color.from_hsv(fposmod(land_hue + 0.03, 1.0), land_sat * 0.6, rng.randf_range(0.55, 0.75)),
		"shallow":  shallow,
		"deep":     deep,
		"ocean_surface": surface,
		"atmo":      atmo,
		"has_caps":  rng.randf() < 0.65,
		"cap_start": rng.randf_range(0.72, 0.9),
		"snow":      Color(0.92, 0.93, 0.96),
	}
