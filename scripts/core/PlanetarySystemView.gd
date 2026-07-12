extends Node3D

# A planet's own orbital map — moons instead of planets, the planet itself
# fixed at the center instead of Sol. Deliberately its own scene (matching
# the "each view is a separate scene/context" convention), but borrows
# System view's whole interaction shape wholesale: camera rig, click-to-
# select, scan-gated callout + data panel. Reached either via the "Planetary
# System" button on a scanned planet's BodyInfoPanel, or the ViewSwitcher's
# own PLANETARY tab (2026-07-11) — which resolves to whatever planet you're
# currently orbiting, or the parent of whatever moon you're at (see
# ViewSwitcher._current_planet_for_view), including moonless planets (an
# empty system reads better than a tab that mysteriously does nothing).
# Still parameterized per-planet rather than a fixed peer scope either way —
# both entry points go through HUD.go_to_planetary_system (see
# the planetary-system-view conversation in parallax-core-design-decisions
# memory).
#
# Real moon names/facts come from KnownBodies, same as every other body in
# the game. Only Luna keeps its real canonical texture (KnownBodies.Entry.
# use_canonical_art); every other moon here is a procedurally generated
# MoonGenerator body, seeded off its own name so it looks the same every
# time you visit rather than reshuffling.

const GAP_BASE := 3.0
const GAP_SCALE := 2.2
const BODY_MIN_RADIUS := 0.18  # floor for bare visibility/clickability of an asteroid-sized moon (Styx, Deimos, ...), not a size that's meant to read as "normal"
# Scales almost linearly with real radius_ratio (not sqrt-compressed) — moons
# span a much wider real size range than planets do (Pluto's Styx, ~5km, to
# Ganymede, ~2634km — over 500x), and sqrt-compressing that on top of
# BODY_MIN_RADIUS's own floor left everything reading as "similar dots"
# regardless of real size — Charon barely looked bigger than Pluto's other,
# genuinely tiny moons. This keeps the "big real moons clearly read as big,
# tiny ones clearly read as tiny" distinction instead.
const BODY_SIZE_SCALE := 3.0
const PLANET_RADIUS := 2.2    # the central planet is a fixed display size, not scaled by its real radius_ratio — Jupiter and Mars would otherwise need wildly different camera distances
const ORBIT_RING_WIDTH := 0.006
const SPIN := 0.05
# Tuned directly against real orbital_period_days (see _build_system),
# unlike System view's AU^1.5 proxy — moons have real period data on hand.
# Phobos' real period (0.32 days, the fastest of any cataloged moon) sets
# the ceiling: this value keeps it at roughly System view's Mercury speed
# (~0.05 rad/s, a ~2 minute lap) rather than several rotations per second,
# which made it nearly impossible to click. Slower-orbiting moons (most of
# them) end up well under that, same as System view's outer planets crawl.
const ORBIT_SPEED := 0.016

const ZOOM_STEP := 0.9
const MIN_DISTANCE := 0.8
const MAX_DISTANCE := 60.0
const ORBIT_SENSITIVITY := 0.008
const PAN_SENSITIVITY := 0.0012

const STOCK_YAW := 0.0
const STOCK_PITCH := -0.74
const STOCK_DISTANCE := 16.0

const FOCUS_SWEEP_RATE := 4.0
const FOCUS_DISTANCE_MULT := 6.0
const CLICK_DRAG_THRESHOLD := 6.0
const SELECT_RADIUS_PAD := 1.8
const CALLOUT_DIAGONAL := Vector2(28.0, -28.0)  # up-right — BodyInfoPanel sits on the left, but the small target callout stays on the right
const CALLOUT_HORIZONTAL := 70.0
const CALLOUT_LABEL_GAP := 8.0
const ARRIVE_WAIT_TIME := 3.0 / FOCUS_SWEEP_RATE
const LINE_REVEAL_TIME := 0.25
const TYPE_CHARS_PER_SEC := 35.0
const TYPE_MIN_TIME := 0.06
const TYPE_CLICK_STRIDE := 2

enum CalloutStage { HIDDEN, WAITING_FOR_SWEEP, REVEALING_LINE, TYPING_NAME, DONE }

var _planet_name: String = "Earth"

var _bodies: Array[Node3D] = []
var _orbits: Array[Dictionary] = []

var _pivot: Node3D
var _camera: Camera3D
var _sun: DirectionalLight3D
var _yaw := STOCK_YAW
var _pitch := STOCK_PITCH
var _distance := STOCK_DISTANCE
var _target_distance := STOCK_DISTANCE
var _orbiting := false
var _panning := false
var _left_press_pos := Vector2.ZERO
var _focused_body: Node3D = null

var _overlay_layer: CanvasLayer
var _callout_overlay: Control
var _callout_label: Label
var _callout_stage := CalloutStage.HIDDEN
var _callout_line_progress := 0.0
var _line_tween: Tween
var _sweep_elapsed := 0.0
var _body_panel: BodyInfoPanel
var _scan_prompt: ScanPrompt
var _lock_button: LockButton
var _callout_go_btn: UIButton
var _return_scene: String = "res://scenes/system_view.tscn"  # where "back" (Esc or the button) actually goes — see _ready/HUD.pending_return_scene


func _ready() -> void:
	_planet_name = HUD.pending_planet_name if HUD.pending_planet_name != "" else "Earth"
	HUD.pending_planet_name = ""
	if HUD.pending_return_scene != "":
		_return_scene = HUD.pending_return_scene
	HUD.pending_return_scene = ""
	_build_environment()
	_build_camera()
	_build_system()
	_build_callout()
	_build_body_panel()
	_build_back_button()
	AmbientManager.play_map_ambient()
	HUD.set_view("%s System" % _planet_name, "planetary")


func _process(delta: float) -> void:
	for body in _bodies:
		for child in body.get_children():
			if child.name != "Rings":
				child.rotate_y(SPIN * delta)

	for orbit: Dictionary in _orbits:
		var angle: float = (orbit["angle"] as float) + (orbit["speed"] as float) * delta
		orbit["angle"] = angle
		var radius: float = orbit["radius"]
		var body: Node3D = orbit["body"]
		body.position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

	var pivot_target := _focused_body.position if _focused_body != null else Vector3.ZERO
	var t := 1.0 - exp(-delta * FOCUS_SWEEP_RATE)
	_pivot.position = _pivot.position.lerp(pivot_target, t)

	if not is_equal_approx(_distance, _target_distance):
		_distance = lerpf(_distance, _target_distance, t)
		_update_camera()

	if _callout_stage == CalloutStage.WAITING_FOR_SWEEP:
		_sweep_elapsed += delta

	_update_callout()


# --- 3D scene ---

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.005, 0.007, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.08, 0.09, 0.13)
	env.ambient_light_energy = 0.5

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Everything here sits clustered tightly around one planet (unlike System
	# view's system-wide spread), so a single directional Sun is a fine
	# approximation — same technique Cockpit/Cosmic Forge use, rather than
	# System view's per-position OmniLight (needed there specifically because
	# planets are spread across wildly different real distances from Sol).
	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.96, 0.88)
	_sun.light_energy = 1.3
	_sun.rotation_degrees = Vector3(-25, 55, 0)
	add_child(_sun)


func _build_camera() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_pivot.add_child(_camera)
	_update_camera()

	var stars := StarfieldStars.new()
	stars.follow = _camera
	add_child(stars)


func _update_camera() -> void:
	_pitch = clampf(_pitch, -1.45, 1.45)
	_distance = clampf(_distance, MIN_DISTANCE, MAX_DISTANCE)
	_pivot.rotation = Vector3(_pitch, _yaw, 0)
	_camera.position = Vector3(0, 0, _distance)


func _build_system() -> void:
	var planet_entry := KnownBodies.get_entry(_planet_name)
	var planet := CanonicalBodyGenerator.generate(planet_entry.to_params(PLANET_RADIUS))
	add_child(planet)
	_bodies.append(planet)
	# Fixed at the origin, radius/speed 0 — folded into _orbits anyway so
	# click-selection works uniformly for the planet without a special case,
	# same trick System view uses for Sol.
	_orbits.append({
		"body": planet,
		"radius": 0.0,
		"body_radius": PLANET_RADIUS,
		"angle": 0.0,
		"speed": 0.0,
	})

	# The planet doesn't move (unlike System view's orbiting planets), so
	# this only needs setting once, not every frame.
	var atmo := planet.get_node_or_null("Atmosphere") as MeshInstance3D
	if atmo != null:
		(atmo.material_override as ShaderMaterial).set_shader_parameter("sun_dir", _sun.global_basis.z)

	var moons := KnownBodies.moons_of(_planet_name)
	for i in moons.size():
		var entry: KnownBodies.Entry = moons[i]
		var display_r := GAP_BASE + GAP_SCALE * (i + 1)
		add_child(_build_orbit_ring(display_r))

		var body_r := BODY_MIN_RADIUS + BODY_SIZE_SCALE * entry.radius_ratio
		var body := _build_moon_body(entry, body_r)
		var start_angle := randf_range(0.0, TAU)  # rerolled each load
		body.position = Vector3(cos(start_angle) * display_r, 0.0, sin(start_angle) * display_r)
		add_child(body)
		_bodies.append(body)

		_orbits.append({
			"body": body,
			"radius": display_r,
			"body_radius": body_r,
			"angle": start_angle,
			"speed": ORBIT_SPEED / maxf(entry.orbital_period_days, 0.1),
		})


func _build_moon_body(entry: KnownBodies.Entry, display_radius: float) -> Node3D:
	if entry.use_canonical_art:
		return CanonicalBodyGenerator.generate(entry.to_params(display_radius))

	# Deterministic per moon name — same look every visit, not reshuffled —
	# with a little seeded knob variety so a row of moons doesn't look like
	# copies of one another.
	var rng := RandomNumberGenerator.new()
	rng.seed = entry.body_name.hash()
	var params := MoonParams.new()
	params.seed_value = entry.body_name.hash()
	params.radius = display_radius
	params.surface_roughness = rng.randf_range(0.01, 0.04)
	params.crater_density = rng.randf_range(0.25, 0.85)
	# crater_size is the MAX radius now (power-law distributed below it, see
	# CraterField.make) — range widened from the old average-semantics
	# (0.10, 0.28) so typical craters stay a similar visible size. Keep in
	# sync with Cockpit._spawn_moon_body: same rng seed (body_name.hash) and
	# same draw sequence is what makes the same moon look identical in both
	# views.
	params.crater_size = rng.randf_range(0.2, 0.5)
	params.crater_depth = rng.randf_range(0.03, 0.08)
	params.detail = 4
	var body := MoonGenerator.generate(params)
	body.name = entry.body_name
	return body


func _build_orbit_ring(radius: float) -> MeshInstance3D:
	const SEGMENTS := 96
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
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


# --- Camera input ---
# Same interaction model as System view: click a body to focus it, drag to
# orbit, wheel to zoom, right/middle-drag to pan. Esc clears focus, or
# leaves back to wherever this view was entered from if nothing's focused
# (see _return_scene).

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _focused_body != null:
			_clear_focus()
		else:
			HUD.go_to(_return_scene)
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_distance *= ZOOM_STEP
				_target_distance = _distance
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
		return

	_focused_body = body
	_target_distance = maxf(body_radius * FOCUS_DISTANCE_MULT, MIN_DISTANCE)
	_callout_label.text = body.name.to_upper()

	if _line_tween != null:
		_line_tween.kill()
	_callout_stage = CalloutStage.WAITING_FOR_SWEEP
	_callout_line_progress = 0.0
	_sweep_elapsed = 0.0
	_callout_label.visible = false
	_body_panel.hide_panel()
	_scan_prompt.reset()
	_lock_button.reset()
	_callout_go_btn.visible = false


func _clear_focus() -> void:
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
	_body_panel.hide_panel()
	_scan_prompt.reset()
	_lock_button.reset()
	_callout_go_btn.visible = false


# --- Callout ---

func _build_callout() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 10  # above the 3D scene, below HUD's own layers
	add_child(_overlay_layer)

	_callout_overlay = Control.new()
	_callout_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_callout_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_callout_overlay.draw.connect(_draw_callout)
	_overlay_layer.add_child(_callout_overlay)

	_callout_label = Label.new()
	_callout_label.add_theme_font_size_override("font_size", 16)
	_callout_label.add_theme_color_override("font_color", UITheme.accent)
	_callout_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_callout_label.visible = false
	_overlay_layer.add_child(_callout_label)

	_scan_prompt = ScanPrompt.new()
	_scan_prompt.pressed_for.connect(_on_scan_requested)
	_overlay_layer.add_child(_scan_prompt)

	_lock_button = LockButton.new()
	_overlay_layer.add_child(_lock_button)

	# GO, right under LOCK/UNLOCK — mirrors System view's callout so locking a
	# moon here and hitting GO works the same way instead of needing a detour
	# through the control panel. See SystemView.gd's own copy of this block.
	_callout_go_btn = UIButton.new()
	_callout_go_btn.text = "GO"
	_callout_go_btn.solid = true
	_callout_go_btn.shimmer_enabled = false
	_callout_go_btn.custom_minimum_size = Vector2(90.0, 28.0)
	_callout_go_btn.add_theme_font_size_override("font_size", 12)
	_callout_go_btn.visible = false
	_callout_go_btn.press_sfx = "go_button"  # override — see AudioManager.ui_confirm
	_callout_go_btn.pressed.connect(_on_callout_go_pressed)
	_overlay_layer.add_child(_callout_go_btn)


# --- Body info panel ---

func _build_body_panel() -> void:
	_body_panel = BodyInfoPanel.new()
	_body_panel.scan_finished.connect(_on_scan_finished)
	_overlay_layer.add_child(_body_panel)


func _on_callout_go_pressed() -> void:
	if _focused_body == null:
		return
	if PlayerState.travel_to(_focused_body.name):
		HUD.go_to("res://scenes/cockpit.tscn")


func _on_scan_requested(id: String) -> void:
	if _focused_body == null or _focused_body.name != id:
		return
	var entry := KnownBodies.get_entry(id)
	if entry != null:
		_body_panel.start_scan(entry)


func _on_scan_finished(id: String) -> void:
	if _focused_body != null and _focused_body.name == id:
		_scan_prompt.mark_scanned()


# --- Back button ---
# Esc already does this (see _unhandled_input), but that's not discoverable
# on its own — and "back" isn't always System view anymore now that
# PLANETARY is reachable from Cockpit's tab too (see _return_scene), so the
# button's own label has to match wherever it's actually going, not a fixed
# "SOLAR SYSTEM" caption that would be a lie whenever you arrived from
# Cockpit. _return_label() looks the display name up from ViewSwitcher.VIEWS
# (same {id, label, scene} table the top tab row itself is built from)
# rather than duplicating a second scene->label mapping here.
func _build_back_button() -> void:
	var btn := UIButton.new()
	btn.text = "◀ %s" % _return_label()
	btn.solid = true
	btn.shimmer_enabled = false
	btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	btn.offset_left = 24.0
	btn.offset_top = 78.0
	btn.custom_minimum_size = Vector2(0, 30)
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(func() -> void: HUD.go_to(_return_scene))
	_overlay_layer.add_child(btn)


func _return_label() -> String:
	for view: Dictionary in ViewSwitcher.VIEWS:
		if view["scene"] == _return_scene:
			return view["label"]
	return "SOLAR SYSTEM"  # fallback — matches this view's original always-System-view behavior


var _callout_visible := false
var _callout_anchor := Vector2.ZERO
var _callout_elbow := Vector2.ZERO
var _callout_line_end := Vector2.ZERO


func _update_callout() -> void:
	_callout_visible = (_focused_body != null
			and _callout_stage != CalloutStage.HIDDEN
			and _callout_stage != CalloutStage.WAITING_FOR_SWEEP
			and not _camera.is_position_behind(_focused_body.position))

	if _focused_body != null and not _camera.is_position_behind(_focused_body.position):
		_callout_anchor = _camera.unproject_position(_focused_body.position)
		_callout_elbow = _callout_anchor + CALLOUT_DIAGONAL
		_callout_line_end = _callout_elbow + Vector2(CALLOUT_HORIZONTAL, 0.0)

		# Stays on the right even though BodyInfoPanel now sits on the left —
		# the two are deliberately on opposite sides here.
		_callout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_callout_label.position = Vector2(
				_callout_line_end.x + CALLOUT_LABEL_GAP, _callout_line_end.y - _callout_label.size.y * 0.5)
		_scan_prompt.position = Vector2(
				_callout_label.position.x, _callout_label.position.y + _callout_label.size.y + 6.0)
		_lock_button.position = Vector2(
				_callout_label.position.x, _scan_prompt.position.y + _scan_prompt.size.y + 4.0)
		_callout_go_btn.position = Vector2(
				_callout_label.position.x, _lock_button.position.y + _lock_button.size.y + 4.0)

		if _callout_stage == CalloutStage.WAITING_FOR_SWEEP and _sweep_elapsed >= ARRIVE_WAIT_TIME:
			_callout_stage = CalloutStage.REVEALING_LINE
			_reveal_line()

	_scan_prompt.visible = _callout_visible
	_lock_button.visible = _callout_visible

	# GO only for a focused body that's ALSO the current locked destination —
	# appears the moment you LOCK, disappears on UNLOCK (or if focus moves to
	# a different body than the one you locked).
	var focused_id: String = String(_focused_body.name) if _focused_body != null else ""
	_callout_go_btn.visible = _callout_visible and Destination.is_locked(focused_id)
	if _callout_go_btn.visible:
		var already_here: bool = focused_id == PlayerState.location_id
		_callout_go_btn.text = "HERE" if already_here else "GO"
		_callout_go_btn.disabled = PlayerState.is_traveling or already_here

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


func _type_callout_label(for_body: Node3D) -> void:
	var total_len := _callout_label.text.length()
	if total_len == 0:
		return
	_callout_label.visible_ratio = 0.0
	var char_time := maxf(1.0 / TYPE_CHARS_PER_SEC, TYPE_MIN_TIME)
	var clickable_count := 0
	for i in range(total_len):
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
		_scan_prompt.present(for_body.name)
		_lock_button.present(for_body.name)
		if Discoveries.is_scanned(for_body.name):
			var entry := KnownBodies.get_entry(for_body.name)
			if entry != null:
				_body_panel.show_for(entry)


func _draw_callout() -> void:
	if not _callout_visible:
		return
	var color := UITheme.accent
	var diagonal_t := clampf(_callout_line_progress * 2.0, 0.0, 1.0)
	var elbow_point := _callout_anchor.lerp(_callout_elbow, diagonal_t)
	_callout_overlay.draw_circle(_callout_anchor, 4.0, color)
	_callout_overlay.draw_line(_callout_anchor, elbow_point, color, 1.5)
	if _callout_line_progress > 0.5:
		var horiz_t := clampf((_callout_line_progress - 0.5) * 2.0, 0.0, 1.0)
		var end_point := _callout_elbow.lerp(_callout_line_end, horiz_t)
		_callout_overlay.draw_line(_callout_elbow, end_point, color, 1.5)

	# One unified backdrop behind the name AND the scan/lock controls below
	# it, not separately-boxed floating elements — reads as a single panel.
	# Drawn under all three (this overlay is added to the tree before
	# _callout_label/_scan_prompt/_lock_button, so it paints first).
	if _callout_label.visible:
		var pad := Vector2(8.0, 7.0)
		var bg_rect := Rect2(_callout_label.position - pad, _callout_label.size + pad * 2.0)
		if _scan_prompt.visible:
			bg_rect = bg_rect.merge(Rect2(_scan_prompt.position - pad, _scan_prompt.size + pad * 2.0))
		if _lock_button.visible:
			bg_rect = bg_rect.merge(Rect2(_lock_button.position - pad, _lock_button.size + pad * 2.0))
		if _callout_go_btn.visible:
			bg_rect = bg_rect.merge(Rect2(_callout_go_btn.position - pad, _callout_go_btn.size + pad * 2.0))
		var bg_col: Color = UITheme.panel
		bg_col.a = 0.85
		_callout_overlay.draw_rect(bg_rect, bg_col)
		var border: Color = UITheme.accent
		border.a = 0.5
		_callout_overlay.draw_rect(bg_rect, border, false, 1.5)
