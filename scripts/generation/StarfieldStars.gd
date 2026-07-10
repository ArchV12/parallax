class_name StarfieldStars
extends Node3D

# Geometry-based starfield shared by any Node3D screen that needs a sky full
# of stars (Cosmic Forge, Cockpit, System view) — supersedes StarfieldSky.gd,
# which baked stars into a fixed 2048x1024 raster panorama texture. That
# texture looked soft/inconsistent at 4K: individual 1-pixel bright stars
# don't survive mipmap filtering well once magnified across far more screen
# pixels than the texture was baked for.
#
# This instead renders stars as real GPU point primitives (POINT_SIZE set in
# the vertex shader) on a sphere shell. Point sprites are a fixed size in
# actual device pixels regardless of output/backbuffer resolution, so a star
# stays a crisp 1-3px pinprick at 1080p or 4K alike — no texture to filter or
# magnify.
#
# The shell recenters on a target camera's POSITION every frame (never its
# rotation) via `follow`, so the sky reads as infinitely distant with zero
# parallax as the camera moves, while staying fixed in world orientation as
# the camera looks around — the standard "skybox dome tracks camera" trick,
# done with real points instead of a texture.

const STAR_COUNT := 6000
const SHELL_RADIUS := 800.0
const MIN_POINT_SIZE := 1.2
const MAX_POINT_SIZE := 3.0

var follow: Node3D = null


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _build_mesh()
	mi.material_override = _build_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# All STAR_COUNT points sit out at SHELL_RADIUS, but the mesh's own
	# vertices give it a tiny local AABB at the origin — pad the cull margin
	# so the engine doesn't frustum-cull the whole thing as "off-screen"
	# from a naive bounds check.
	mi.extra_cull_margin = SHELL_RADIUS
	add_child(mi)


func _process(_delta: float) -> void:
	if follow != null:
		global_position = follow.global_position


static func _build_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	positions.resize(STAR_COUNT)
	colors.resize(STAR_COUNT)
	for i in STAR_COUNT:
		# Uniform random point on a unit sphere.
		var u := rng.randf_range(-1.0, 1.0)
		var theta := rng.randf_range(0.0, TAU)
		var r := sqrt(1.0 - u * u)
		var dir := Vector3(r * cos(theta), r * sin(theta), u)
		positions[i] = dir * SHELL_RADIUS
		# Weighted toward dim/small — most stars are faint pinpricks; only a
		# few get the biggest, brightest treatment. Color alpha carries the
		# point-size weight through to the shader (color itself doesn't use
		# alpha for anything else here).
		var b := rng.randf_range(0.15, 1.0) * rng.randf_range(0.5, 1.0)
		var size_t := rng.randf_range(0.0, 1.0) * rng.randf_range(0.0, 1.0)
		colors[i] = Color(b, b, b * rng.randf_range(0.85, 1.0), size_t)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_COLOR] = colors

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	return mesh


static func _build_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;

void vertex() {
	POINT_SIZE = mix(%.1f, %.1f, COLOR.a);
}

void fragment() {
	ALBEDO = COLOR.rgb;
}
""" % [MIN_POINT_SIZE, MAX_POINT_SIZE]
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat
