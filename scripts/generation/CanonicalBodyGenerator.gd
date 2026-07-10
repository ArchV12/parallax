class_name CanonicalBodyGenerator
extends RefCounted

# Renders known, real-world bodies (Earth, Mars, Jupiter, ...) — these are
# documented reality, not something a seed should invent, so unlike every
# other generator here this one is not deterministic-from-seed, it's
# deterministic-from-texture. A UV sphere (not Icosphere — that mesh shares
# vertices seamlessly and has no UVs at all, by design) gets a real
# equirectangular texture mapped onto it.
#
# The texture is expected at CanonicalBodyParams.albedo_texture_path
# (convention: res://Assets/textures/<body>/albedo.png). If it hasn't been
# added yet, this falls back to a flat placeholder color with a one-time
# warning — same graceful-missing-asset pattern as AudioManager/MusicManager
# — so a canonical body can be wired into the picker before its art lands.
#
# Sol (self_luminous = true) is the one exception to "lit rocky surface":
# unshaded + emissive, same idea as StarGenerator's procedural sun, just
# textured instead of noise-shaded.
#
# Saturn (rings > 0) is the other exception: its defining feature isn't on
# the surface texture at all, so it reuses RingSystem — the same utility
# GasGiantGenerator uses for procedural gas giants.

const ATMO_SHADER := preload("res://shaders/atmosphere.gdshader")
const SPHERE_SEGMENTS := 64

static var _warned: Dictionary = {}  # texture path -> true, so a missing file only warns once


static func generate(params: CanonicalBodyParams) -> Node3D:
	var root := Node3D.new()
	root.name = params.body_name
	root.add_child(_build_surface(params))
	if params.atmosphere > 0.01:
		root.add_child(_build_atmosphere(params))
	if params.rings > 0.01:
		# RingSystem only uses the RNG for the band pattern's noise offset (and
		# tilt, if ring_tilt_degrees is left at -1) — seeding it from the body's
		# own name (not a random roll) keeps a curated body's look stable
		# across regenerations, same spirit as everything else here being
		# authored rather than rolled.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(params.body_name)
		root.add_child(RingSystem.build(rng, params.radius, params.rings, params.ring_tracks,
				params.ring_tint, params.ring_tilt_degrees))
	return root


static func _build_surface(params: CanonicalBodyParams) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = params.radius
	mesh.height = params.radius * 2.0
	mesh.radial_segments = SPHERE_SEGMENTS
	mesh.rings = SPHERE_SEGMENTS / 2

	var mat := StandardMaterial3D.new()
	var tex := _load_texture(params.albedo_texture_path)
	if tex != null:
		mat.albedo_texture = tex
	else:
		mat.albedo_color = params.fallback_color
	mat.roughness = 0.9
	# A rocky/photographic surface shouldn't be glossy at all. specular_mode
	# disables the analytic-light specular lobe (sun/fill light hotspots),
	# but ambient/environment reflections (the Forge's procedural starfield
	# sky reflecting off the surface) are a separate code path keyed off
	# metallic_specular (F0), not specular_mode — a blurred reflected star,
	# invisible against the bright day side, reads as a stray bright "pimple"
	# against the near-black night side. Both need zeroing to actually kill
	# every source of a highlight, not just direct-light specular.
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.metallic_specular = 0.0

	# Sol: unshaded (no day/night side — it IS the light source) and emissive
	# so it actually blooms, same as StarGenerator's self-luminous surface.
	if params.self_luminous:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		if tex != null:
			mat.emission_texture = tex
		else:
			mat.emission = params.fallback_color
		mat.emission_energy_multiplier = params.emission_energy

	var mi := MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = mesh
	mi.material_override = mat
	# SphereMesh has real geometric poles (many thin triangles converging to
	# one vertex) — unlike Icosphere, which has none, by design. That
	# degenerate geometry causes shadow-map self-shadowing errors right at
	# the pole: a bright pinch with a V-shaped dark wedge trailing it,
	# regardless of surface material settings. The day/night terminator is
	# already handled by the material's own lighting response, not shadows,
	# so the sphere never needed to self-shadow in the first place.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _build_atmosphere(params: CanonicalBodyParams) -> MeshInstance3D:
	var r := params.radius * (1.0 + 0.04 + 0.10 * params.atmosphere)
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = SPHERE_SEGMENTS
	mesh.rings = SPHERE_SEGMENTS / 2

	var mat := ShaderMaterial.new()
	mat.shader = ATMO_SHADER
	mat.set_shader_parameter("atmo_color", params.atmo_color)
	mat.set_shader_parameter("density", params.atmosphere)
	mat.set_shader_parameter("falloff", params.atmo_falloff)
	mat.set_shader_parameter("planet_radius", params.radius)
	mat.set_shader_parameter("shell_radius", r)
	# Self-luminous bodies (Sol) have no dark limb to dim — same corona
	# technique StarGenerator uses.
	mat.set_shader_parameter("self_luminous", params.self_luminous)
	# Draw after the surface so the additive glow layers over it at the limb —
	# same convention as PlanetGenerator's atmosphere.
	mat.render_priority = 1

	var mi := MeshInstance3D.new()
	mi.name = "Atmosphere"
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func _load_texture(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		if path != "" and not _warned.has(path):
			_warned[path] = true
			push_warning("CanonicalBodyGenerator: texture not found — %s" % path)
		return null
	return ResourceLoader.load(path) as Texture2D
