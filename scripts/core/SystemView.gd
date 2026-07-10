extends Node3D

# The system-wide navigation map — angled top-down orbital view with
# log-scaled radial distances (see the System view / Cockpit-System
# transition decision in parallax-core-design-decisions memory). Bodies come
# straight from the KnownBodies catalog — the same source of truth Cosmic
# Forge and Cockpit use — so nothing about a planet's look is redefined here.
#
# Real AU distances span ~100x (Mercury 0.39 AU to Pluto 39.5 AU) — far too
# wide a range to render literally without either crushing the inner
# planets together or pushing the outer ones off-screen. DISPLAY radius
# below (BASE_GAP + LOG_SCALE * log(au)) compresses that range for display
# only; KnownBodies' underlying AU values stay real, ready for whatever real
# orbital-math system eventually drives actual travel/ephemeris.
#
# Not yet interactive — no destination picking, no ship, no travel. Just the
# map itself; switching to/from Cockpit is a quick viewer flicker (HUD.go_to)
# rather than a camera move through space — see the "Star Trek viewscreen"
# transition decision in parallax-core-design-decisions memory. Planet
# angles reroll every scene load (same "dynamic, not yet a real ephemeris"
# spirit as Cockpit's Earth rotation/Luna jitter) since there's no real
# time-of-day/orbital-phase system yet.

const BASE_GAP := 8.0          # display-radius offset before the log term — keeps Mercury clear of Sol's own bulk
const LOG_SCALE := 6.0         # display units per natural-log-AU — the actual compression amount
const BODY_MIN_RADIUS := 0.25
const BODY_SIZE_SCALE := 0.12  # display-radius units per sqrt(real radius ratio)
const ORBIT_RING_WIDTH := 0.008
const SPIN := 0.03             # rad/s — idle rotation, purely for a "living" feel
# Orbital angular speed follows Kepler's third law (period scales with
# distance^1.5, so angular speed scales with 1/distance^1.5) — inner planets
# visibly outpace outer ones, same relative ordering as reality, just sped
# way up for a "living map" feel rather than real orbital timescales (at
# this rate Mercury completes a lap in ~2 minutes; Pluto barely crawls,
# which is itself realistic — outer planets really do move that much slower).
const ORBIT_SPEED := 0.013

# Orbit/zoom/pan camera rig — same interaction model as Cosmic Forge's
# viewer, just tuned for this scene's much larger scale (orbits span up to
# ~30 units, vs. Cosmic Forge's single-object close-ups).
const ZOOM_STEP := 0.9
const MIN_DISTANCE := 1.5
const MAX_DISTANCE := 150.0
const ORBIT_SENSITIVITY := 0.008
const PAN_SENSITIVITY := 0.0012

# "Stock" framing — what Esc returns to when nothing's focused, and what
# every session starts at.
const STOCK_YAW := 0.0
const STOCK_PITCH := -0.74  # matches the old fixed camera's implied angle
const STOCK_DISTANCE := 62.0

# Lower = slower, more dramatic sweep across the map; higher = a snappier
# chase. This is an exponential-decay rate, not a duration — 4.0 reaches
# ~63% of the way in 0.25s, ~95% by 0.75s. Exponential decay's tail is
# inherently long/mushy (it never truly finishes) at low rates — this is
# high enough that the tail is short enough not to read as "creeping up."
const FOCUS_SWEEP_RATE := 4.0
# Focused distance = the body's own display radius times this — a close-up
# scaled to whatever you actually clicked, not the stock overview distance
# (Pluto is tiny; Jupiter isn't — one fixed zoom level can't suit both).
const FOCUS_DISTANCE_MULT := 6.0

# A left click that moves the mouse more than this (pixels) reads as a drag
# (camera orbit), not a selection attempt.
const CLICK_DRAG_THRESHOLD := 6.0
# Hit-test radius multiplier over a body's visual radius — planets are small
# on screen at this scale, so a forgiving click target matters more than
# pixel-perfect accuracy.
const SELECT_RADIUS_PAD := 1.8

# Sci-fi target-designator callout — dot on the body, an angled leader line,
# an elbow to horizontal, then the name. Direction (left/right) mirrors
# depending which half of the screen the body's on, so the line never runs
# off the edge. Sequenced: hidden while the camera's still sweeping in, then
# the line draws itself out, then the name types on — see CalloutStage.
const CALLOUT_DIAGONAL := Vector2(28.0, -28.0)
const CALLOUT_HORIZONTAL := 70.0
const CALLOUT_LABEL_GAP := 8.0
# Time-based, not distance-based — the pivot chases the focused body with
# exponential smoothing, which has a permanent steady-state lag behind any
# continuously-moving target (proportional to the body's own orbital
# speed). Close, fast-orbiting bodies like Venus/Mercury never actually
# close that gap to zero, so a distance threshold could get stuck waiting
# forever; a fixed wait (a few sweep time-constants — always "visually
# settled" by then, this scene's fastest planets included) is robust
# regardless of target speed.
const ARRIVE_WAIT_TIME := 3.0 / FOCUS_SWEEP_RATE
const LINE_REVEAL_TIME := 0.25
# Same typewriter convention as BootSequence/CommanderBriefing — click every
# TYPE_CLICK_STRIDE-th character, not every one (blurs into a buzz at 35cps).
const TYPE_CHARS_PER_SEC := 35.0
const TYPE_MIN_TIME := 0.06
const TYPE_CLICK_STRIDE := 2

enum CalloutStage { HIDDEN, WAITING_FOR_SWEEP, REVEALING_LINE, TYPING_NAME, DONE }

var _bodies: Array[Node3D] = []
var _orbits: Array[Dictionary] = []  # body, radius, body_radius, angle, speed, atmo — see _build_system/_process

var _pivot: Node3D
var _camera: Camera3D
var _yaw := STOCK_YAW
var _pitch := STOCK_PITCH
var _distance := STOCK_DISTANCE
var _target_distance := STOCK_DISTANCE
var _orbiting := false
var _panning := false
var _left_press_pos := Vector2.ZERO
var _focused_body: Node3D = null

var _callout_overlay: Control
var _callout_label: Label
var _callout_stage := CalloutStage.HIDDEN
var _callout_line_progress := 0.0
var _line_tween: Tween
var _sweep_elapsed := 0.0


func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_system()
	_build_callout()
	HUD.set_view("Solar System", "Cockpit", "res://scenes/cockpit.tscn")


func _process(delta: float) -> void:
	for body in _bodies:
		# Same fix as Cosmic Forge's idle spin — rotate each child except
		# Rings individually, not the shared body root, or a ringed body's
		# fixed tilt gets dragged around into a precessing wobble.
		for child in body.get_children():
			if child.name != "Rings":
				child.rotate_y(SPIN * delta)

	for orbit: Dictionary in _orbits:
		var angle: float = (orbit["angle"] as float) + (orbit["speed"] as float) * delta
		orbit["angle"] = angle
		var radius: float = orbit["radius"]
		var body: Node3D = orbit["body"]
		body.position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var atmo: MeshInstance3D = orbit["atmo"]
		if atmo != null:
			(atmo.material_override as ShaderMaterial).set_shader_parameter(
					"sun_dir", (-body.position).normalized())

	# Glide the pivot toward wherever it should be — the focused body's live
	# position, or the origin once nothing's focused — instead of snapping.
	# Framerate-independent exponential smoothing rather than a fixed-
	# duration tween: the target itself keeps moving (an orbiting planet),
	# so a tween-to-a-fixed-point would fall behind by the time it finishes;
	# this keeps chasing the live position the whole way, decelerating into
	# it, and handles "switching directly from one planet to another" and
	# "returning to the stock view" the same way, since both are just "the
	# target changed" — no separate transition state needed.
	var pivot_target := _focused_body.position if _focused_body != null else Vector3.ZERO
	var t := 1.0 - exp(-delta * FOCUS_SWEEP_RATE)
	_pivot.position = _pivot.position.lerp(pivot_target, t)

	# Same easing for zoom, toward whatever _select()/_clear_focus() set as
	# the target — a manual wheel-zoom (see _unhandled_input) retargets this
	# too, so it doesn't keep fighting the player's own zoom input.
	if not is_equal_approx(_distance, _target_distance):
		_distance = lerpf(_distance, _target_distance, t)
		_update_camera()

	if _callout_stage == CalloutStage.WAITING_FOR_SWEEP:
		_sweep_elapsed += delta

	_update_callout()


# --- 3D scene ---

func _build_environment() -> void:
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = StarfieldSky.build_texture()
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.08, 0.09, 0.13)
	env.ambient_light_energy = 0.5
	# Sol is self-luminous — needs bloom to actually read as a light source
	# rather than a flat bright disc, same as everywhere else Sol appears.
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.25
	env.glow_hdr_threshold = 1.0

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_camera() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_pivot.add_child(_camera)
	_update_camera()


func _update_camera() -> void:
	_pitch = clampf(_pitch, -1.45, 1.45)
	_distance = clampf(_distance, MIN_DISTANCE, MAX_DISTANCE)
	_pivot.rotation = Vector3(_pitch, _yaw, 0)
	_camera.position = Vector3(0, 0, _distance)


func _build_system() -> void:
	var sol_entry := KnownBodies.sol()
	var sol_radius := BODY_MIN_RADIUS + BODY_SIZE_SCALE * sqrt(sol_entry.radius_ratio)
	var sol := CanonicalBodyGenerator.generate(sol_entry.to_params(sol_radius))
	add_child(sol)
	_bodies.append(sol)
	# Sol never orbits — radius 0 and speed 0 keep it pinned at the origin
	# every frame — but folding it into _orbits too means click-selection
	# and camera-follow (both driven by this array) work uniformly for Sol
	# without a separate special case.
	_orbits.append({
		"body": sol,
		"radius": 0.0,
		"body_radius": sol_radius,
		"angle": 0.0,
		"speed": 0.0,
		"atmo": sol.get_node_or_null("Atmosphere") as MeshInstance3D,
	})

	# Sol lights every planet from its own position — a single directional
	# light (as Cockpit/Cosmic Forge use) would light every planet from the
	# same fixed direction regardless of where it actually sits relative to
	# Sol, which breaks the moment more than one body is on screen at once.
	var sun_light := OmniLight3D.new()
	sun_light.light_color = Color(1.0, 0.96, 0.88)
	sun_light.light_energy = 3.0
	sun_light.omni_range = 200.0
	add_child(sun_light)

	for entry: KnownBodies.Entry in KnownBodies.planets():
		var display_r := BASE_GAP + LOG_SCALE * log(entry.au_distance + 1.0)
		add_child(_build_orbit_ring(display_r))

		var body_r := BODY_MIN_RADIUS + BODY_SIZE_SCALE * sqrt(entry.radius_ratio)
		var body := CanonicalBodyGenerator.generate(entry.to_params(body_r))
		var start_angle := randf_range(0.0, TAU)  # rerolled each load
		# Position (and sun_dir below) set immediately, not just registered
		# for _process to place next frame — otherwise every planet flashes
		# at the origin (Sol's own position), wrongly lit, for one frame
		# before its orbit angle first applies.
		body.position = Vector3(cos(start_angle) * display_r, 0.0, sin(start_angle) * display_r)
		add_child(body)
		_bodies.append(body)

		var atmo := body.get_node_or_null("Atmosphere") as MeshInstance3D
		if atmo != null:
			(atmo.material_override as ShaderMaterial).set_shader_parameter(
					"sun_dir", (-body.position).normalized())

		_orbits.append({
			"body": body,
			"radius": display_r,
			"body_radius": body_r,
			"angle": start_angle,
			"speed": ORBIT_SPEED / pow(entry.au_distance, 1.5),
			"atmo": atmo,
		})


func _build_orbit_ring(radius: float) -> MeshInstance3D:
	const SEGMENTS := 128
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGMENTS:
		var a0 := (float(i) / SEGMENTS) * TAU
		var a1 := (float(i + 1) / SEGMENTS) * TAU
		var in0 := Vector3(cos(a0), 0.0, sin(a0)) * (radius - ORBIT_RING_WIDTH)
		var out0 := Vector3(cos(a0), 0.0, sin(a0)) * (radius + ORBIT_RING_WIDTH)
		var in1 := Vector3(cos(a1), 0.0, sin(a1)) * (radius - ORBIT_RING_WIDTH)
		var out1 := Vector3(cos(a1), 0.0, sin(a1)) * (radius + ORBIT_RING_WIDTH)
		st.add_vertex(in0)
		st.add_vertex(out0)
		st.add_vertex(out1)
		st.add_vertex(in0)
		st.add_vertex(out1)
		st.add_vertex(in1)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.5, 0.55, 0.65, 0.12)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Default backface culling only draws one side of each triangle — pan
	# the camera underneath the system plane and the rings vanish. A thin
	# reference ring should read the same from either side.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


# --- Camera input ---
# Click a body — select/focus it, camera follows it around its orbit.
# Drag — orbit · Wheel — zoom · Right/middle-drag — pan (pan is a no-op
# while focused — _process re-glues the pivot to the body every frame, so
# any pan gets overwritten the instant it's applied). Esc clears focus, or
# leaves to Cockpit if nothing's focused.

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _focused_body != null:
			_clear_focus()
		else:
			HUD.go_to("res://scenes/cockpit.tscn")
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_distance *= ZOOM_STEP
				_target_distance = _distance  # manual zoom overrides any focus-zoom in progress
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance /= ZOOM_STEP
				_target_distance = _distance
				_update_camera()
			MOUSE_BUTTON_LEFT:
				_orbiting = mb.pressed
				if mb.pressed:
					_left_press_pos = mb.position
				elif mb.position.distance_to(_left_press_pos) < CLICK_DRAG_THRESHOLD:
					# Released close to where it was pressed — a click, not
					# a drag; try to select whatever's under the cursor.
					_try_select(mb.position)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			_yaw -= mm.relative.x * ORBIT_SENSITIVITY
			_pitch -= mm.relative.y * ORBIT_SENSITIVITY
			_update_camera()
		elif _panning and _focused_body == null:
			var scale_factor := _distance * PAN_SENSITIVITY
			_pivot.position += (-_camera.global_basis.x * mm.relative.x
					+ _camera.global_basis.y * mm.relative.y) * scale_factor


# --- Selection ---

func _try_select(screen_pos: Vector2) -> void:
	var ray_origin := _camera.project_ray_origin(screen_pos)
	var ray_dir := _camera.project_ray_normal(screen_pos)

	var hit_orbit: Dictionary = {}
	var hit_t := INF
	for orbit: Dictionary in _orbits:
		var body: Node3D = orbit["body"]
		var radius: float = (orbit["body_radius"] as float) * SELECT_RADIUS_PAD
		var t := _ray_sphere_hit(ray_origin, ray_dir, body.position, radius)
		if t >= 0.0 and t < hit_t:
			hit_t = t
			hit_orbit = orbit

	if not hit_orbit.is_empty():
		_select(hit_orbit["body"], hit_orbit["body_radius"])


# Ray-sphere intersection; returns the near hit distance along the ray, or
# -1 if it misses. dir must be normalized (project_ray_normal guarantees it).
func _ray_sphere_hit(origin: Vector3, dir: Vector3, center: Vector3, radius: float) -> float:
	var oc := origin - center
	var b := oc.dot(dir)
	var c := oc.length_squared() - radius * radius
	var discriminant := b * b - c
	if discriminant < 0.0:
		return -1.0
	var t := -b - sqrt(discriminant)
	if t < 0.0:
		t = -b + sqrt(discriminant)
	return t if t >= 0.0 else -1.0


func _select(body: Node3D, body_radius: float) -> void:
	if body == _focused_body:
		return  # already focused on this one — don't restart the reveal for nothing

	# No snap — _process's continuous lerp sweeps the pivot AND zoom to the
	# new target from wherever they currently are.
	_focused_body = body
	_target_distance = maxf(body_radius * FOCUS_DISTANCE_MULT, MIN_DISTANCE)
	# The generator names its root node after the body (see
	# CanonicalBodyGenerator), so the node's own name is already the display
	# name — no separate lookup needed.
	_callout_label.text = body.name.to_upper()

	# Restart the reveal fresh for the new target, killing whatever reveal
	# was mid-flight for the previous one (switching targets mid-reveal is
	# a hard restart, not a blend).
	if _line_tween != null:
		_line_tween.kill()
	_callout_stage = CalloutStage.WAITING_FOR_SWEEP
	_callout_line_progress = 0.0
	_sweep_elapsed = 0.0
	_callout_label.visible = false


func _clear_focus() -> void:
	# Pivot and zoom both ease back the same way; yaw/pitch still reset
	# immediately for now (only position/zoom sweep was asked for).
	_focused_body = null
	_target_distance = STOCK_DISTANCE
	_yaw = STOCK_YAW
	_pitch = STOCK_PITCH
	_update_camera()

	if _line_tween != null:
		_line_tween.kill()
	_callout_stage = CalloutStage.HIDDEN
	_callout_line_progress = 0.0
	_callout_label.visible = false


# --- Callout ---
# A sci-fi target-designator: dot on the body, angled leader line, elbow to
# horizontal, name label. Screen-space overlay recomputed every frame from
# the focused body's projected position — it has to track both camera
# movement and the body's own orbital motion.

func _build_callout() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10  # above the 3D scene, below HUD's own layers
	add_child(layer)

	_callout_overlay = Control.new()
	_callout_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_callout_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_callout_overlay.draw.connect(_draw_callout)
	layer.add_child(_callout_overlay)

	_callout_label = Label.new()
	_callout_label.add_theme_font_size_override("font_size", 16)
	_callout_label.add_theme_color_override("font_color", UITheme.accent)
	_callout_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_callout_label.visible = false
	layer.add_child(_callout_label)


# Cached each frame by _update_callout, read by both the label positioning
# below and the _draw_callout draw callback — computed once, not twice.
var _callout_visible := false
var _callout_anchor := Vector2.ZERO
var _callout_elbow := Vector2.ZERO
var _callout_line_end := Vector2.ZERO


func _update_callout() -> void:
	# Line/label only ever show once the reveal has actually started — stays
	# fully hidden while still WAITING_FOR_SWEEP.
	_callout_visible = (_focused_body != null
			and _callout_stage != CalloutStage.HIDDEN
			and _callout_stage != CalloutStage.WAITING_FOR_SWEEP
			and not _camera.is_position_behind(_focused_body.position))

	if _focused_body != null and not _camera.is_position_behind(_focused_body.position):
		# Always the same fixed direction (up-right), not mirrored by screen
		# half — the callout only ever shows while a body is focused, and the
		# camera is specifically built to keep the focused body dead-centered
		# (that's the whole point of the pivot-follow rig), so there's no
		# edge to run off. Dynamic mirroring here just meant small residual
		# lag (the pivot never perfectly catches up to a still-orbiting body)
		# could nudge the projection across the centerline and flip sides.
		_callout_anchor = _camera.unproject_position(_focused_body.position)
		_callout_elbow = _callout_anchor + CALLOUT_DIAGONAL
		_callout_line_end = _callout_elbow + Vector2(CALLOUT_HORIZONTAL, 0.0)

		_callout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_callout_label.position = Vector2(
				_callout_line_end.x + CALLOUT_LABEL_GAP, _callout_line_end.y - _callout_label.size.y * 0.5)

		if _callout_stage == CalloutStage.WAITING_FOR_SWEEP and _sweep_elapsed >= ARRIVE_WAIT_TIME:
			_callout_stage = CalloutStage.REVEALING_LINE
			_reveal_line()

	_callout_overlay.queue_redraw()


func _reveal_line() -> void:
	_callout_line_progress = 0.0
	_line_tween = create_tween()
	_line_tween.tween_property(self, "_callout_line_progress", 1.0, LINE_REVEAL_TIME)
	_line_tween.tween_callback(_start_name_typing)


func _start_name_typing() -> void:
	if _focused_body == null:
		return
	_callout_stage = CalloutStage.TYPING_NAME
	_callout_label.visible = true
	_type_callout_label(_focused_body)


# Same stepped-reveal technique as BootSequence._type_append /
# CommanderBriefing._type_label: types one character at a time so a click
# sfx can fire in lockstep, rather than a single continuous tween.
func _type_callout_label(for_body: Node3D) -> void:
	var total_len := _callout_label.text.length()
	if total_len == 0:
		return
	_callout_label.visible_ratio = 0.0
	var char_time := maxf(1.0 / TYPE_CHARS_PER_SEC, TYPE_MIN_TIME)
	var clickable_count := 0
	for i in range(total_len):
		# Bail if the target changed (cleared or switched) mid-type.
		if _focused_body != for_body:
			return
		_callout_label.visible_ratio = float(i + 1) / float(total_len)
		var ch := _callout_label.text[i]
		if ch != " ":
			clickable_count += 1
			if clickable_count % TYPE_CLICK_STRIDE == 1:
				AudioManager.type_char()
		await get_tree().create_timer(char_time).timeout
	if _focused_body == for_body:
		_callout_stage = CalloutStage.DONE


func _draw_callout() -> void:
	if not _callout_visible:
		return
	var color := UITheme.accent
	# First half of progress draws the diagonal leg, second half the
	# horizontal leg — the line draws itself out rather than popping in.
	var diagonal_t := clampf(_callout_line_progress * 2.0, 0.0, 1.0)
	var elbow_point := _callout_anchor.lerp(_callout_elbow, diagonal_t)
	_callout_overlay.draw_circle(_callout_anchor, 4.0, color)
	_callout_overlay.draw_line(_callout_anchor, elbow_point, color, 1.5)
	if _callout_line_progress > 0.5:
		var horiz_t := clampf((_callout_line_progress - 0.5) * 2.0, 0.0, 1.0)
		var end_point := _callout_elbow.lerp(_callout_line_end, horiz_t)
		_callout_overlay.draw_line(_callout_elbow, end_point, color, 1.5)
