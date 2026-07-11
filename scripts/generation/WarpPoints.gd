class_name WarpPoints
extends Node3D

# Stylized "stars zipping by" overlay for transit — added on top of
# StarfieldStars, never replacing it (that field stays exactly as it is at
# rest; this one is fully hidden until a trip actually asks for warp). Real
# physics still governs the ship's position/speed (see TravelCalc); this is
# purely a screen-space flourish layered over that truth, the classic
# sci-fi "flying through stars" read that flat, motionless deep space
# doesn't actually give you.
#
# Deliberately POINTS, not streaks — an earlier version stretched each star
# into a comet-tail streak, but plain points scrolling toward the camera
# reads as the more familiar "flying through a starfield" look (Star Wars-
# style hyperspace tunnel), and it comes free of the streak version's
# trickiest part (getting the streak axis to agree with wherever the camera
# actually happens to be pointed).
#
# Each star lives in an abstract "tunnel" space: a fixed (x, y) Cartesian
# offset from the flight axis, plus a depth along that axis. Depth scrolls
# toward the camera over time (driven by `warp_strength`) and wraps back to
# the far end via mod() once it passes — an infinite tunnel from a fixed
# STAR_COUNT. The offset/depth are generated once, in this abstract space,
# independent of the actual travel direction; `set_axis` just changes the
# two world-space perpendicular uniforms the vertex shader projects that
# abstract space through, so a mid-trip destination swap doesn't need new
# geometry, only new axis uniforms. POINT_SIZE and brightness both scale
# with proximity (nearer = bigger/brighter, matching real parallax) —
# unlike StarfieldStars' fixed-distance shell, these stars have genuine
# varying depth, so that falloff is the actual point of the effect, not
# just decoration.
#
# The (x, y) offset is a FIXED Cartesian value, NOT recomputed from live
# depth each frame, precisely so the flying-past parallax happens at all: as
# a fixed offset's depth shrinks, its projected screen angle atan(r/depth)
# GROWS, which is what reads as "swinging outward as it approaches" — an
# offset that instead scaled WITH depth (r = depth * tan(fixed_angle)) was
# tried first and was wrong in a subtle way: r/depth, and therefore the
# on-screen position, stays constant for that star's entire lifetime, so
# nothing ever appears to move sideways — every star just grows in place at
# a fixed ring radius, which is exactly the static "halo" that looked so
# broken.
#
# A keep-clear angle (MIN_AXIS_ANGLE_DEG/MAX_AXIS_ANGLE_DEG) only comes in
# at SPAWN time, to pick that fixed r: r =
# FAR_FADE_START * tan(chosen_angle), i.e. "the Cartesian offset this star
# would need to already sit at (at minimum) MIN_AXIS_ANGLE_DEG off the
# vanishing point at the depth it first fades into visibility." Since a
# star is invisible for any depth beyond FAR_FADE_START (see that constant)
# and its projected angle only ever GROWS as depth shrinks from there, this
# guarantees every star stays outside MIN_AXIS_ANGLE_DEG for its entire
# visible lifetime, not just at one instant — without freezing its screen
# position the way deriving r from the CURRENT depth did.

const STAR_COUNT := 2000
const MIN_AXIS_ANGLE_DEG := 7.0    # keep-clear cone around the vanishing point/travel axis, guaranteed at every visible depth — see above
const MAX_AXIS_ANGLE_DEG := 24.0   # outer edge of the point field at spawn — stays mostly within the camera's own FOV without needing every star on-screen (off-screen ones are simply culled, harmlessly); actual on-screen angle only grows larger than this as a star approaches
const TUNNEL_LENGTH := 500.0
const MIN_DEPTH := 4.0             # keeps depth (and 1/depth size scaling) from blowing up right as a point wraps past the camera
const MIN_POINT_SIZE := 1.0
const MAX_POINT_SIZE := 9.0
const REFERENCE_DEPTH := 40.0      # depth at which a star renders at its authored (min..max) point size
# Distant points are fully INVISIBLE past FAR_FADE_START, not just dim — a
# continuous fade across the whole tunnel still let the far, densest part
# (screen density goes as 1/depth^2 with a fixed-radius cylinder and uniform
# depth spread) show through as a faint haze/ball around the vanishing
# point. A hard cutoff further out, easing in only over the FAR_FADE_START..
# FAR_FADE_END stretch, keeps that far region genuinely empty and lets
# points read as individually arriving out of the dark instead.
const FAR_FADE_START := TUNNEL_LENGTH * 0.45
const FAR_FADE_END := TUNNEL_LENGTH * 0.12
const NEAR_FADE_START := 10.0      # fades out over depth < this, so a point doesn't pop away right at the wrap

# World units of tunnel-depth scrolled per second at warp_strength == 1 —
# tuned by eye, not tied to the ship's actual km/s (which is a wildly
# different scale from this stylized tunnel).
const SCROLL_SPEED := 140.0

# How fast displayed warp strength chases its target — a soft attack/release
# so the effect ramps in with the burn and eases out with the decay/cruise
# glide instead of snapping, matching how current_speed_km_s itself moves.
const WARP_RESPONSE := 3.0

var follow: Node3D = null
var warp_axis := Vector3(0.0, 0.0, -1.0)

var _target_warp := 0.0
var _warp := 0.0
var _scroll := 0.0
var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _build_mesh()
	_material = _build_material()
	_mesh_instance.material_override = _material
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.extra_cull_margin = TUNNEL_LENGTH * 1.5
	_mesh_instance.visible = false
	add_child(_mesh_instance)
	_apply_axis_uniforms()


# Called every frame by Cockpit with the ship's current speed fraction
# (0..1, see Cockpit._process) — never applied directly, just set as the
# target _process eases toward (see WARP_RESPONSE).
func set_target_warp(strength: float) -> void:
	_target_warp = clampf(strength, 0.0, 1.0)


func set_axis(world_dir: Vector3) -> void:
	if world_dir.length() > 0.01:
		warp_axis = world_dir.normalized()
		if _material != null:
			_apply_axis_uniforms()


func _apply_axis_uniforms() -> void:
	# Any vector not parallel to warp_axis works as a seed for building an
	# orthonormal perpendicular pair — swap to a different seed on the rare
	# near-parallel case so the cross product doesn't degenerate.
	var seed_dir := Vector3.UP if absf(warp_axis.y) < 0.99 else Vector3.RIGHT
	var perp1 := warp_axis.cross(seed_dir).normalized()
	var perp2 := warp_axis.cross(perp1).normalized()
	_material.set_shader_parameter("warp_axis", warp_axis)
	_material.set_shader_parameter("perp1", perp1)
	_material.set_shader_parameter("perp2", perp2)


func _process(delta: float) -> void:
	if follow != null:
		global_position = follow.global_position
	_warp = move_toward(_warp, _target_warp, WARP_RESPONSE * delta)
	_mesh_instance.visible = _warp > 0.001
	if _mesh_instance.visible:
		_scroll = fmod(_scroll + SCROLL_SPEED * _warp * delta, TUNNEL_LENGTH)
		_material.set_shader_parameter("warp_strength", _warp)
		_material.set_shader_parameter("scroll", _scroll)


static func _build_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	positions.resize(STAR_COUNT)
	colors.resize(STAR_COUNT)
	for i in STAR_COUNT:
		# r is fixed per star, sized so its projected angle off the axis is
		# already >= MIN_AXIS_ANGLE_DEG at FAR_FADE_START (the depth it fades
		# into visibility) — see the class comment for why r has to stay
		# fixed (not re-derived from live depth) for the parallax to work.
		var axis_angle := deg_to_rad(rng.randf_range(MIN_AXIS_ANGLE_DEG, MAX_AXIS_ANGLE_DEG))
		var r := FAR_FADE_START * tan(axis_angle)
		var azimuth := rng.randf_range(0.0, TAU)
		var depth0 := rng.randf_range(0.0, TUNNEL_LENGTH)
		# VERTEX doubles as raw tunnel-space data here, not a real position —
		# see the vertex shader, which projects (x, y, depth) through the
		# perp1/perp2/warp_axis uniforms rather than MODEL_MATRIX.
		positions[i] = Vector3(r * cos(azimuth), r * sin(azimuth), depth0)

		var b := rng.randf_range(0.4, 1.0) * rng.randf_range(0.6, 1.0)
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

uniform float warp_strength : hint_range(0.0, 1.0) = 0.0;
uniform float scroll = 0.0;
uniform vec3 warp_axis = vec3(0.0, 0.0, -1.0);
uniform vec3 perp1 = vec3(1.0, 0.0, 0.0);
uniform vec3 perp2 = vec3(0.0, 1.0, 0.0);

varying float v_fade;

void vertex() {
	float depth = mod(VERTEX.z - scroll, %.1f) + %.1f;
	vec3 world_offset = warp_axis * depth + perp1 * VERTEX.x + perp2 * VERTEX.y;
	vec3 node_world_pos = MODEL_MATRIX[3].xyz;
	vec3 view_pos = (VIEW_MATRIX * vec4(node_world_pos + world_offset, 1.0)).xyz;

	float near_fade = smoothstep(%.1f, %.1f, depth);
	// Genuinely 0 (not just dim) for depth >= FAR_FADE_START — see the
	// constant's comment — then eases up to fully visible by FAR_FADE_END.
	float far_fade = 1.0 - smoothstep(%.1f, %.1f, depth);
	v_fade = near_fade * far_fade * warp_strength;

	float size = mix(%.1f, %.1f, COLOR.a) * (%.1f / max(depth, %.1f));
	POINT_SIZE = clamp(size, %.1f, %.1f * 3.0);
	POSITION = PROJECTION_MATRIX * vec4(view_pos, 1.0);
}

void fragment() {
	ALBEDO = COLOR.rgb * v_fade;
}
""" % [TUNNEL_LENGTH, MIN_DEPTH,
		MIN_DEPTH, NEAR_FADE_START,
		FAR_FADE_END, FAR_FADE_START,
		MIN_POINT_SIZE, MAX_POINT_SIZE, REFERENCE_DEPTH, MIN_DEPTH,
		MIN_POINT_SIZE, MAX_POINT_SIZE]
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat
