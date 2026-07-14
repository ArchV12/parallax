class_name CometGenerator
extends RefCounted

# Procedural comet builder. Three parts:
#  - "Body": an irregular icy nucleus — same base-shape-deformation +
#    cratering approach as AsteroidGenerator (real nuclei are lumpy for the
#    same reason asteroids are: too small for gravity to round them out), but
#    a much darker "dirty snowball" surface. Real comet nuclei are among the
#    darkest objects in the solar system, not bright and icy as the name
#    suggests — the ice sublimating INTO the coma and tail is what's bright,
#    not the crust itself.
#  - "Atmosphere": the coma, reusing the shared atmosphere/corona shell
#    shader. Named "Atmosphere" specifically so the Forge's existing
#    sun-direction patch (built for planets) applies to it automatically.
#  - "Tail": a tapered, wispy cone that must always point away from the star.
#    Built centered at the origin with a default, unrotated transform —
#    "which way is away from the star" is a scene-relative fact a
#    deterministic generator can't know, so the viewer (Forge, later the
#    game) re-orients this node after generate() returns, the same division
#    of labor already used for the Atmosphere sun-direction patch.

const ATMO_SHADER := preload("res://shaders/atmosphere.gdshader")
const TAIL_SHADER := preload("res://shaders/comet_tail.gdshader")

static func generate(params: CometParams) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = params.seed_value
	var palette := _make_palette(rng)
	var craters := CraterField.make(rng, params.crater_density, params.crater_size)

	var shape_noise := FastNoiseLite.new()
	shape_noise.seed = params.seed_value
	shape_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	shape_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	shape_noise.fractal_octaves = 3
	shape_noise.frequency = 0.7

	var root := Node3D.new()
	root.name = "Comet"
	root.add_child(_build_nucleus(params, shape_noise, craters, palette))
	root.add_child(_build_coma(params, palette))
	root.add_child(_build_tail(params, rng, palette))
	return root


static func _build_nucleus(params: CometParams, shape_noise: FastNoiseLite,
		craters: Dictionary, palette: Dictionary) -> MeshInstance3D:
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
		# Same "FBM shape noise, not ridged" lesson as AsteroidGenerator —
		# ridged noise's thin ridge lines read as spikes at high amplitude.
		var shape_h := shape_noise.get_noise_3dv(unit) * params.irregularity
		var crater_h := CraterField.height_at(unit, centers, radii, params.crater_depth)
		var h := shape_h + crater_h
		st.set_color(_height_color(h, palette))
		# Floored well above 0 — see AsteroidGenerator's identical clamp for
		# why: at extreme irregularity, shape noise alone can push h below
		# -1, flipping (1.0+h) negative and turning the surface inside-out
		# at that vertex instead of just deeply dented.
		var radial_scale := maxf(1.0 + h, 0.1)
		st.add_vertex(unit * params.radius * radial_scale)
	for idx in indices:
		st.add_index(idx)
	st.generate_normals()

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0

	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


static func _build_coma(params: CometParams, palette: Dictionary) -> MeshInstance3D:
	var r: float = params.radius * (2.5 + params.coma_size * 4.0)
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 64
	mesh.rings = 32

	var mat := ShaderMaterial.new()
	mat.shader = ATMO_SHADER
	mat.set_shader_parameter("atmo_color", palette["coma"])
	mat.set_shader_parameter("density", clampf(params.coma_size, 0.05, 1.0))
	mat.set_shader_parameter("falloff", 0.8)  # broad, soft haze rather than a crisp planetary limb
	mat.set_shader_parameter("planet_radius", params.radius)
	mat.set_shader_parameter("shell_radius", r)
	mat.render_priority = 1

	var mi := MeshInstance3D.new()
	mi.name = "Atmosphere"  # matches the Forge's existing sun_dir patch by name
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func _build_tail(params: CometParams, rng: RandomNumberGenerator, palette: Dictionary) -> MeshInstance3D:
	var length: float = params.radius * (4.0 + params.tail_length * 10.0)
	var width: float = params.radius * (0.5 + params.tail_width * 3.0)

	var mesh := CylinderMesh.new()
	mesh.top_radius = params.radius * 0.3      # narrow, nucleus-facing end
	mesh.bottom_radius = width                  # wide, far end
	mesh.height = length
	mesh.radial_segments = 24
	mesh.rings = 6
	mesh.cap_top = false
	mesh.cap_bottom = false

	var mat := ShaderMaterial.new()
	mat.shader = TAIL_SHADER
	mat.set_shader_parameter("seed_offset", rng.randf_range(0.0, 20.0))
	mat.set_shader_parameter("tail_color", palette["tail"])

	var mi := MeshInstance3D.new()
	mi.name = "Tail"
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func _height_color(h: float, palette: Dictionary) -> Color:
	var t := clampf((h + 0.35) / 0.6, 0.0, 1.0)
	var col: Color = (palette["dark"] as Color).lerp(palette["mid"] as Color, smoothstep(0.0, 0.5, t))
	col = col.lerp(palette["light"] as Color, smoothstep(0.5, 1.0, t))
	return col


# Comet nuclei are among the darkest objects in the solar system — a "dirty
# snowball" crust, not bright ice. The coma and tail are where the brightness
# comes from, as sublimating ice catches sunlight.
static func _make_palette(rng: RandomNumberGenerator) -> Dictionary:
	var hue := rng.randf_range(0.05, 0.1)
	var sat := rng.randf_range(0.02, 0.08)
	var coma_hue := rng.randf_range(0.45, 0.58)
	return {
		"dark":  Color.from_hsv(hue, sat, rng.randf_range(0.03, 0.06)),
		"mid":   Color.from_hsv(hue, sat, rng.randf_range(0.08, 0.13)),
		"light": Color.from_hsv(hue, sat * 0.6, rng.randf_range(0.18, 0.26)),
		"coma":  Color.from_hsv(coma_hue, rng.randf_range(0.15, 0.35), rng.randf_range(0.85, 1.0)),
		"tail":  Color.from_hsv(coma_hue, rng.randf_range(0.2, 0.4), rng.randf_range(0.85, 1.0)),
	}
