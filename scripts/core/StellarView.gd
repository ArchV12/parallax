extends Node3D

# Stellar View — the neighborhood of real nearby stars around Sol (see
# NearbyStars.gd for the data/real-position derivation). First step toward a
# second travelable star system (2026-07-18 "order of things" design chat).
#
# 2026-07-18, rebuilt from a flat 2D Control board into a genuine 3D scene —
# same free-fly/click-select/target-callout interaction shape as System/
# Planetary System view (see those files), reusing that already-tuned rig
# wholesale a THIRD time rather than inventing a new one, per direct user
# request ("utilize the same control scheme as the other views"). Stars sit
# at real 3D positions now (NearbyStars.Entry.position_ly, real RA/Dec/
# distance), not an arbitrary seeded angle the flat version used.
#
# Trimmed relative to System view's full rig: no orbital motion (nothing
# here orbits anything at this scale), no ScanPrompt/BodyInfoPanel (no
# scanning concept for stars yet), no asteroids/"you are here" edge-arrow
# system. Sol sits at the origin as a fixed, non-selectable anchor (a small
# always-visible label, not the full pulsing-ring "YOU ARE HERE" marker) —
# it represents "the system you're already in," not a peer destination.
#
# LOCK/GO real interstellar travel (2026-07-18) — LOCK is now the shared
# LockButton component (same one System/Planetary System view use), writing
# a real Destination.locked_id; GO calls PlayerState.travel_to() and, on
# success, transitions to Cockpit for the warp-transit sequence — the exact
# same "if PlayerState.travel_to(id): HUD.go_to(cockpit)" shape every other
# GO button in the game already uses (LocationsPanel, System/Planetary
# System view's own callouts). Only ever real for a star with curated
# KnownBodies content AND a real owned Beyond Light Engine (Sub-Light plays
# no role at all here — direct user design decision, see TravelCalc.gd's
# compress_by_star_tier_reach comment) — every other star still plays the
# "not built yet" deny cue, same as before this was wired.

const DISTANCE_SCALE := 8.0  # display units per light-year
const SOL_RADIUS := 1.0
const DEFAULT_BODY_RADIUS := 0.8
# Rough relative real stellar radii by spectral class (first letter) — not
# to scale, just enough for "the hot bright one looks bigger than the red
# dwarfs" instead of every star reading as an identical dot.
const BODY_RADIUS_BY_CLASS := {
	"O": 1.4, "B": 1.2, "A": 1.0, "F": 0.9, "G": 0.8, "K": 0.65, "M": 0.5,
}

const ZOOM_STEP := 0.9
const MIN_DISTANCE := 1.0
const MAX_DISTANCE := 120.0
const ORBIT_SENSITIVITY := 0.008
const PAN_SENSITIVITY := 0.0012
const FREE_FLY_SPEED_MULT := 0.15
const FREE_FLY_SHIFT_MULT := 2.0

const STOCK_YAW := 0.0
const STOCK_PITCH := -0.74
const STOCK_DISTANCE := 60.0

const FOCUS_SWEEP_RATE := 4.0
const FOCUS_DISTANCE_MULT := 6.0
const CLICK_DRAG_THRESHOLD := 6.0
const SELECT_RADIUS_PAD := 1.8

const CALLOUT_DIAGONAL := Vector2(28.0, -28.0)
const CALLOUT_HORIZONTAL := 70.0
const CALLOUT_LABEL_GAP := 8.0
const ARRIVE_WAIT_TIME := 3.0 / FOCUS_SWEEP_RATE
const LINE_REVEAL_TIME := 0.25
const TYPE_CHARS_PER_SEC := 35.0
const TYPE_MIN_TIME := 0.06
const TYPE_CLICK_STRIDE := 2

enum CalloutStage { HIDDEN, WAITING_FOR_SWEEP, REVEALING_LINE, TYPING_NAME, DONE }

var _stars: Array[Dictionary] = []  # {"entry": NearbyStars.Entry, "body": Node3D, "body_radius": float}
var _sol_body: Node3D

var _pivot: Node3D
var _camera: Camera3D
var _yaw := STOCK_YAW
var _pitch := STOCK_PITCH
var _distance := STOCK_DISTANCE
var _target_distance := STOCK_DISTANCE
var _panning := false
var _looking := false
var _left_press_pos := Vector2.ZERO
var _focused_body: Node3D = null
var _focused_entry: NearbyStars.Entry = null
var _pan_target := Vector3.ZERO
var _orbit_offset := 0.0

var _overlay_layer: CanvasLayer
var _callout_overlay: Control
var _callout_label: Label
var _distance_label: Label
var _spectral_label: Label
var _travel_time_label: Label
var _callout_stage := CalloutStage.HIDDEN
var _callout_line_progress := 0.0
var _line_tween: Tween
var _sweep_elapsed := 0.0
var _lock_btn: LockButton
var _go_btn: UIButton

var _sol_label: Label


func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_stars()
	_build_callout()

	AmbientManager.play_map_ambient()
	HUD.set_view("Stellar Neighborhood", "stellar")


func _process(delta: float) -> void:
	if _focused_body == null:
		var move := Vector3.ZERO
		if ControlScheme.is_forward_pressed():
			move -= _camera.global_basis.z
		if ControlScheme.is_back_pressed():
			move += _camera.global_basis.z
		if ControlScheme.is_right_pressed():
			move += _camera.global_basis.x
		if ControlScheme.is_left_pressed():
			move -= _camera.global_basis.x
		if Input.is_physical_key_pressed(KEY_SPACE):
			move += Vector3.UP
		if Input.is_physical_key_pressed(KEY_CTRL):
			move += Vector3.DOWN
		if move.length() > 0.01:
			var speed_mult := FREE_FLY_SPEED_MULT
			if Input.is_physical_key_pressed(KEY_SHIFT):
				speed_mult *= FREE_FLY_SHIFT_MULT
			var fly_offset := move.normalized() * (_distance * speed_mult) * delta
			_pivot.position += fly_offset
			_pan_target += fly_offset

	var pivot_target := _focused_body.position if _focused_body != null else _pan_target
	var t := 1.0 - exp(-delta * FOCUS_SWEEP_RATE)
	_pivot.position = _pivot.position.lerp(pivot_target, t)

	if not is_equal_approx(_distance, _target_distance):
		_distance = lerpf(_distance, _target_distance, t)
		_update_camera()

	var target_offset := _target_distance if _focused_body != null else 0.0
	_orbit_offset = lerpf(_orbit_offset, target_offset, t)
	_camera.position = Vector3(0.0, 0.0, _orbit_offset)

	if _callout_stage == CalloutStage.WAITING_FOR_SWEEP:
		_sweep_elapsed += delta

	_update_callout()
	_update_sol_label()


# --- 3D scene ---

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.005, 0.007, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.08, 0.09, 0.13)
	env.ambient_light_energy = 0.5
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

	_pan_target = _pivot.basis * Vector3(0.0, 0.0, STOCK_DISTANCE)
	_pivot.position = _pan_target

	var stars_bg := StarfieldStars.new()
	stars_bg.follow = _camera
	add_child(stars_bg)


func _update_camera() -> void:
	_pitch = clampf(_pitch, -1.45, 1.45)
	_distance = clampf(_distance, MIN_DISTANCE, MAX_DISTANCE)
	_pivot.rotation = Vector3(_pitch, _yaw, 0)


func _player_star_system() -> String:
	var entry := KnownBodies.get_entry(PlayerState.location_id)
	return entry.star_system if entry != null else "Sol"


func _build_stars() -> void:
	_sol_body = _build_star_sphere(SOL_RADIUS, Color(1.0, 0.9, 0.6), true)
	_sol_body.position = Vector3.ZERO
	add_child(_sol_body)

	var current_system := _player_star_system()

	# Sol itself becomes a real, selectable travel target once the player is
	# actually away from it — the return trip home. Not offered while
	# already at Sol, same "don't offer your own current location as a
	# destination" shape LocationsPanel's "HERE" label already uses.
	# distance_ly reuses the current system's own NearbyStars entry (the
	# same real number TravelCalc.star_distance_ly would independently
	# compute either direction, Sol being the fixed origin) rather than a
	# second lookup.
	if current_system != "Sol":
		var current_star_entry := NearbyStars.get_entry(current_system)
		var sol_entry := NearbyStars.Entry.new()
		sol_entry.star_name = "Sol"
		sol_entry.distance_ly = current_star_entry.distance_ly if current_star_entry != null else 0.0
		sol_entry.spectral_type = "G2V"
		_stars.append({"entry": sol_entry, "body": _sol_body, "body_radius": SOL_RADIUS})

	for entry: NearbyStars.Entry in NearbyStars.all():
		if entry.star_name == current_system:
			continue  # don't show your own current star as a travel target
		var body_radius: float = BODY_RADIUS_BY_CLASS.get(entry.spectral_type.substr(0, 1), DEFAULT_BODY_RADIUS)
		var body := _build_star_sphere(body_radius, entry.color, false)
		body.name = entry.star_name
		body.position = entry.position_ly() * DISTANCE_SCALE
		add_child(body)
		_stars.append({"entry": entry, "body": body, "body_radius": body_radius})


# A plain unshaded, self-emissive sphere — deliberately not CanonicalBody
# Generator (that's built for a real planet/star surface with albedo
# texture/atmosphere, far more than a board marker needs here). Sol gets
# a stronger glow than the neighbor stars, matching its role as the map's
# fixed anchor rather than a peer destination.
func _build_star_sphere(display_radius: float, color: Color, is_sol: bool) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = display_radius
	mesh.height = display_radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5 if is_sol else 1.4

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- Camera input --- same interaction model as System view (click select,
# RMB-hold look/free-fly-mouselook, wheel zoom while focused, middle-drag
# pan, WASD/ESDF free-fly when unfocused). Esc clears focus, or leaves to
# Cockpit if nothing's focused.

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _focused_body != null:
			_clear_focus()
		else:
			HUD.go_to("res://scenes/cockpit.tscn")
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var over_ui := (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN) \
				and get_viewport().gui_get_hovered_control() != null
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if _focused_body != null and not over_ui:
					_distance *= ZOOM_STEP
					_target_distance = _distance
					_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if _focused_body != null and not over_ui:
					_distance /= ZOOM_STEP
					_target_distance = _distance
					_update_camera()
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_left_press_pos = mb.position
				elif mb.position.distance_to(_left_press_pos) < CLICK_DRAG_THRESHOLD:
					_try_select(mb.position)
			MOUSE_BUTTON_RIGHT:
				_looking = mb.pressed
				Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if mb.pressed else Input.MOUSE_MODE_VISIBLE
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _looking:
			_yaw -= mm.relative.x * ORBIT_SENSITIVITY
			_pitch -= mm.relative.y * ORBIT_SENSITIVITY
			_update_camera()
		elif _panning and _focused_body == null:
			var scale_factor := _distance * PAN_SENSITIVITY
			var offset := (-_camera.global_basis.x * mm.relative.x
					+ _camera.global_basis.y * mm.relative.y) * scale_factor
			_pivot.position += offset
			_pan_target += offset


# --- Selection ---

func _try_select(screen_pos: Vector2) -> void:
	var ray_origin := _camera.project_ray_origin(screen_pos)
	var ray_dir := _camera.project_ray_normal(screen_pos)

	var hit: Dictionary = {}
	var hit_t := INF
	for star: Dictionary in _stars:
		var body: Node3D = star["body"]
		var radius: float = (star["body_radius"] as float) * SELECT_RADIUS_PAD
		var t := _ray_sphere_hit(ray_origin, ray_dir, body.position, radius)
		if t >= 0.0 and t < hit_t:
			hit_t = t
			hit = star

	if not hit.is_empty():
		_select(hit["entry"], hit["body"], hit["body_radius"])


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


func _select(entry: NearbyStars.Entry, body: Node3D, body_radius: float) -> void:
	if body == _focused_body:
		return

	_focused_body = body
	_focused_entry = entry
	_target_distance = maxf(body_radius * FOCUS_DISTANCE_MULT, MIN_DISTANCE)
	_callout_label.text = entry.star_name.to_upper()
	_distance_label.text = "DISTANCE: %.2f ly" % entry.distance_ly
	_spectral_label.text = "SPECTRAL TYPE: %s" % entry.spectral_type
	# Beyond Light Engines only — Sub-Light has no role in interstellar
	# travel (direct user design decision). Same compress_by_tier_reach
	# shape/tuning System view's own Sub-Light pacing uses, just with
	# STAR_TIER_REACH_LY instead of TIER_REACH_KM — see TravelCalc.gd's
	# compress_by_star_tier_reach for the full "mirror" reasoning.
	#
	# Beyond Light Engines is the one equipment slot with NO free starting
	# tier (owned_tier 0 == "None", a real placeholder InstrumentDef, not a
	# usable drive — see Research.gd's own comment on EQUIPMENT_SLOT_PATHS/
	# TECHNOLOGY_PATHS) — its 5 real drives (Warp Bubble Generator ...
	# Singularity Drive) sit at owned_tier 1-5, one off from every other
	# slot's 0-4. STAR_TIER_REACH_LY indexes 0-4 assume the player-facing
	# "T0" (Warp Bubble Generator), so this maps owned_tier 1-5 -> index
	# 0-4, and treats "None" honestly as no FTL capability at all rather
	# than silently reusing Tier 0's numbers.
	var owned_tier := Research.owned_tier("beyond_light_engines")
	if owned_tier <= 0:
		_travel_time_label.text = "TRAVEL TIME: NO BEYOND LIGHT ENGINE"
	else:
		var travel_seconds := TravelCalc.compress_by_star_tier_reach(entry.distance_ly, owned_tier - 1)
		_travel_time_label.text = "TRAVEL TIME: %s" % TravelCalc.format_duration(travel_seconds)
	# Reset from whatever the previously-selected star left behind — LOCK's
	# real state now lives on Destination itself, reacquired via .present()
	# once typing finishes (see _type_callout_label, mirrors SystemView.
	# _type_callout_label's own LOCK-appears-on-DONE timing).
	_lock_btn.reset()
	# GO's own deny-vs-confirm cue, picked fresh per star — real for one
	# with curated KnownBodies content AND a real owned Beyond Light Engine;
	# the existing "not built yet" deny cue otherwise. See _on_go_pressed
	# for the actual gating (GO is only VISIBLE once locked — this just
	# decides what pressing it sounds/does like once it is).
	var can_travel := KnownBodies.get_entry(entry.star_name) != null and Research.owned_tier("beyond_light_engines") > 0
	_go_btn.press_sfx = "go_button" if can_travel else "error"

	if _line_tween != null:
		_line_tween.kill()
	_callout_stage = CalloutStage.WAITING_FOR_SWEEP
	_callout_line_progress = 0.0
	_sweep_elapsed = 0.0
	_callout_label.visible = false
	_distance_label.visible = false
	_spectral_label.visible = false
	_travel_time_label.visible = false
	_go_btn.visible = false


func _clear_focus() -> void:
	var camera_world_pos := _pivot.position + _pivot.basis * Vector3(0.0, 0.0, _orbit_offset)
	_focused_body = null
	_focused_entry = null
	_pivot.position = camera_world_pos
	_pan_target = camera_world_pos
	_orbit_offset = 0.0
	_camera.position = Vector3.ZERO
	_target_distance = STOCK_DISTANCE

	if _line_tween != null:
		_line_tween.kill()
	_callout_stage = CalloutStage.HIDDEN
	_callout_line_progress = 0.0
	_callout_label.visible = false
	_distance_label.visible = false
	_spectral_label.visible = false
	_travel_time_label.visible = false
	_lock_btn.reset()
	_go_btn.visible = false


# --- Callout ---

func _build_callout() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 10
	add_child(_overlay_layer)

	_callout_overlay = Control.new()
	_callout_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_callout_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_callout_overlay.draw.connect(_draw_callout)
	_overlay_layer.add_child(_callout_overlay)

	_callout_label = Label.new()
	_callout_label.add_theme_font_size_override("font_size", 16)
	_callout_label.add_theme_color_override("font_color", UITheme.accent)
	UITheme.style_label_shadow(_callout_label)
	_callout_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_callout_label.visible = false
	_overlay_layer.add_child(_callout_label)

	_distance_label = Label.new()
	_distance_label.add_theme_font_size_override("font_size", 12)
	_distance_label.add_theme_color_override("font_color", UITheme.text)
	_distance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_distance_label.visible = false
	_overlay_layer.add_child(_distance_label)

	_spectral_label = Label.new()
	_spectral_label.add_theme_font_size_override("font_size", 12)
	_spectral_label.add_theme_color_override("font_color", UITheme.text)
	_spectral_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spectral_label.visible = false
	_overlay_layer.add_child(_spectral_label)

	_travel_time_label = Label.new()
	_travel_time_label.add_theme_font_size_override("font_size", 12)
	_travel_time_label.add_theme_color_override("font_color", UITheme.accent)
	_travel_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_travel_time_label.visible = false
	_overlay_layer.add_child(_travel_time_label)

	_lock_btn = LockButton.new()
	_overlay_layer.add_child(_lock_btn)

	_go_btn = UIButton.new()
	_go_btn.text = "GO"
	_go_btn.solid = true
	_go_btn.shimmer_enabled = false
	_go_btn.custom_minimum_size = Vector2(90.0, 28.0)
	_go_btn.add_theme_font_size_override("font_size", 12)
	_go_btn.visible = false
	# 2026-07-18 — real for a star with curated KnownBodies content
	# (Proxima Centauri today), the same "not built yet, plays a deny cue"
	# placeholder ViewSwitcher's own empty-scene tabs use otherwise — see
	# _select()'s own comment for how press_sfx gets picked per star.
	_go_btn.pressed.connect(_on_go_pressed)
	_overlay_layer.add_child(_go_btn)

	_sol_label = Label.new()
	_sol_label.text = "SOL"
	_sol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sol_label.add_theme_font_size_override("font_size", 12)
	_sol_label.add_theme_color_override("font_color", UITheme.dim)
	UITheme.style_label_shadow(_sol_label)
	_sol_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sol_label.size = Vector2(60.0, 16.0)
	_overlay_layer.add_child(_sol_label)


# Only reachable once GO is visible at all (locked — see _update_callout),
# so _focused_entry is guaranteed non-null here. Real navigation for a star
# with curated KnownBodies content AND a real owned Beyond Light Engine —
# the exact "if PlayerState.travel_to(id): HUD.go_to(cockpit)" shape every
# other GO button in the game already uses. Every other star's press_sfx is
# already the "error" deny cue (set in _select) and has no real KnownBodies
# entry at all, so the explicit guard below is what actually prevents
# PlayerState.travel_to from ever being asked to fly toward one of them —
# the sound alone isn't a safety mechanism, just the honest-feeling half.
func _on_go_pressed() -> void:
	if _focused_entry == null:
		return
	if KnownBodies.get_entry(_focused_entry.star_name) == null:
		return
	if PlayerState.travel_to(_focused_entry.star_name):
		HUD.go_to("res://scenes/cockpit.tscn")


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

		_callout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_callout_label.position = Vector2(
				_callout_line_end.x + CALLOUT_LABEL_GAP, _callout_line_end.y - _callout_label.size.y * 0.5)
		_distance_label.position = Vector2(
				_callout_label.position.x, _callout_label.position.y + _callout_label.size.y + 4.0)
		_spectral_label.position = Vector2(
				_distance_label.position.x, _distance_label.position.y + _distance_label.size.y + 2.0)
		_travel_time_label.position = Vector2(
				_spectral_label.position.x, _spectral_label.position.y + _spectral_label.size.y + 2.0)
		_lock_btn.position = Vector2(
				_callout_label.position.x, _travel_time_label.position.y + _travel_time_label.size.y + 6.0)
		_go_btn.position = Vector2(
				_lock_btn.position.x + _lock_btn.size.x + 8.0, _lock_btn.position.y)

		if _callout_stage == CalloutStage.WAITING_FOR_SWEEP and _sweep_elapsed >= ARRIVE_WAIT_TIME:
			_callout_stage = CalloutStage.REVEALING_LINE
			_reveal_line()

	_distance_label.visible = _callout_visible and _callout_stage == CalloutStage.DONE
	_spectral_label.visible = _distance_label.visible
	_travel_time_label.visible = _distance_label.visible
	_lock_btn.visible = _distance_label.visible
	# GO only for a focused star that's ALSO the current REAL locked
	# destination — same "appears the moment you LOCK" shape System/
	# Planetary View's own callout GO uses.
	_go_btn.visible = _distance_label.visible and _focused_entry != null and Destination.is_locked(_focused_entry.star_name)

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
		# LOCK isn't gated behind having real KnownBodies content — same
		# "you can commit to a destination you've never scanned/that isn't
		# built yet" shape System view's own LOCK uses — but IS gated here
		# to a star that resolves for real, since PlayerState.travel_to
		# would otherwise silently no-op on a Destination.locked_id with no
		# real system behind it. See SystemView._type_callout_label's own
		# matching gate.
		if _focused_entry != null and KnownBodies.get_entry(_focused_entry.star_name) != null:
			_lock_btn.present(_focused_entry.star_name)


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

	if _callout_label.visible:
		var pad := Vector2(8.0, 7.0)
		var bg_rect := Rect2(_callout_label.position - pad, _callout_label.size + pad * 2.0)
		if _distance_label.visible:
			bg_rect = bg_rect.merge(Rect2(_distance_label.position - pad, _distance_label.size + pad * 2.0))
		if _spectral_label.visible:
			bg_rect = bg_rect.merge(Rect2(_spectral_label.position - pad, _spectral_label.size + pad * 2.0))
		if _travel_time_label.visible:
			bg_rect = bg_rect.merge(Rect2(_travel_time_label.position - pad, _travel_time_label.size + pad * 2.0))
		if _lock_btn.visible:
			bg_rect = bg_rect.merge(Rect2(_lock_btn.position - pad, _lock_btn.size + pad * 2.0))
		if _go_btn.visible:
			bg_rect = bg_rect.merge(Rect2(_go_btn.position - pad, _go_btn.size + pad * 2.0))
		var bg_col: Color = UITheme.panel
		bg_col.a = 0.85
		_callout_overlay.draw_rect(bg_rect, bg_col)
		var border: Color = UITheme.accent
		border.a = 0.5
		_callout_overlay.draw_rect(bg_rect, border, false, 1.5)


# --- Sol label (fixed anchor, not the full "you are here" ring system —
# just a simple always-on screen-space label near Sol's projected
# position, hidden when it swings behind the camera during free-fly) ---

func _update_sol_label() -> void:
	if _camera.is_position_behind(_sol_body.position):
		_sol_label.visible = false
		return
	var screen_pos := _camera.unproject_position(_sol_body.position)
	_sol_label.visible = true
	_sol_label.position = Vector2(screen_pos.x - _sol_label.size.x * 0.5, screen_pos.y + 14.0)
