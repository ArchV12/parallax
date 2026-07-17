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
# Display units per natural-log-AU — the actual compression amount. Bumped
# from 6.0 (2026-07-10): at 6.0, adjacent inner-planet orbit GAPS (e.g.
# Venus-Earth ~0.9 units) were only slightly bigger than a planet's own
# rendered diameter (~0.74 units), so two planets landing at a similar angle
# (each planet's start angle rerolls independently every scene load, not a
# simulated conjunction) would visually crowd or nearly touch. Since the
# view can be freely panned/zoomed, there's no need to keep the whole
# system framed by default — spacing was widened for its own sake, and
# STOCK_DISTANCE below widened to match.
const LOG_SCALE := 9.0
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

# --- Asteroids (still no survey data — that's the next step; population and
# orbits are now real seed-derived generation, not fixed dummies) ---
# Real Main Belt range is ~2.2-3.2 AU (Mars is 1.52, Jupiter 5.2) — reuses
# the same log-scaled display_r/Kepler speed formulas as planets below, so a
# belt asteroid drifts at the correct relative pace without a new mechanic.
const ASTEROID_BELT_AU_MIN := 2.2
const ASTEROID_BELT_AU_MAX := 3.2
# Existence + count is free/derived from a seed, never persisted (see the
# "existence + count" tier in the universe-generation-architecture memory) —
# _seeded_count below rolls it once per load from a fixed label string
# rather than a hardcoded number. Sol is the only system today, so a label
# string stands in for what will eventually be a real per-system seed; the
# range itself is just the density that already looked/felt right.
const ASTEROID_BELT_COUNT_MIN := 52
const ASTEROID_BELT_COUNT_MAX := 68
# Near-Earth asteroids: real solar orbits that merely happen to sit close to
# Earth's own (not Earth satellites — see the brainstorm's "asteroids don't
# orbit planets" note), approximated here as a jitter around Earth's au_distance.
const NEA_COUNT_MIN := 3
const NEA_COUNT_MAX := 6
const NEA_AU_JITTER := 0.15
const ASTEROID_RADIUS_MIN := 0.05
const ASTEROID_RADIUS_MAX := 0.16
# Real Main Belt inclinations mostly run 0-20 degrees (with a long tail
# beyond that); NEAs get a smaller range here purely so they still read as
# "near Earth" rather than scattering far off the ecliptic. Signed, not
# 0..max — the sign plus the independently-random asc_node below is a
# simpler stand-in for a real (always-positive) inclination + ascending
# node pair, equivalent in effect for a body with no real orbital history.
const ASTEROID_BELT_INCLINATION_MAX_DEG := 18.0
const NEA_INCLINATION_MAX_DEG := 10.0

# Centaurs: icy/rocky bodies scattered between Jupiter and Neptune on
# unstable, often steeply-inclined orbits (real ones range from Chiron's
# ~7 degrees to Pholus' ~24 — kept on the high end here since "unstable and
# scattered" is the whole character of this population).
const CENTAUR_AU_MIN := 9.5
const CENTAUR_AU_MAX := 28.0
const CENTAUR_COUNT_MIN := 6
const CENTAUR_COUNT_MAX := 12
const CENTAUR_INCLINATION_MAX_DEG := 28.0

# Jupiter Trojans: NOT their own independent orbit — real Trojans share
# Jupiter's own semi-major axis and period, clustered in a cloud around the
# leading (L4, "Greek camp") and trailing (L5, "Trojan camp") Lagrange
# points, 60 degrees ahead of/behind Jupiter itself. See _spawn_trojan/
# _spawn_trojans, which anchor off Jupiter's own live _orbits entry instead
# of an AU range like every other population here.
const TROJAN_CLUSTER_OFFSET_DEG := 60.0
const TROJAN_CLUSTER_SPREAD_DEG := 12.0
const TROJAN_COUNT_MIN := 4  # per cluster (L4 and L5 each roll their own count)
const TROJAN_COUNT_MAX := 8
const TROJAN_INCLINATION_MAX_DEG := 20.0

# Orbit/zoom/pan camera rig — same interaction model as Cosmic Forge's
# viewer, just tuned for this scene's much larger scale (orbits span up to
# ~41 units, vs. Cosmic Forge's single-object close-ups).
const ZOOM_STEP := 0.9
const MIN_DISTANCE := 1.5
const MAX_DISTANCE := 150.0
const ORBIT_SENSITIVITY := 0.008
const PAN_SENSITIVITY := 0.0012
# Free-fly: WASD to move, hold RMB to look — unfocused only (see _process/
# _unhandled_input). Added once the asteroid population made "orbit around a
# fixed pivot" alone feel tedious for hunting scattered targets across empty
# space; click-to-focus-and-orbit (unchanged) is still how you examine a
# specific body once you've found it. Speed scales with current _distance,
# same reasoning as PAN_SENSITIVITY above — otherwise a speed tuned for
# close-in maneuvering crawls at system-wide zoom, or a speed tuned for
# crossing the whole map is unusably twitchy zoomed in on one body. Original
# first-pass value (1.2) read as way too fast, even after one halving —
# what used to be the normal (unmodified) speed is now the Shift-boosted
# speed, and normal is half of that again. Still worth tuning further by feel.
const FREE_FLY_SPEED_MULT := 0.15
const FREE_FLY_SHIFT_MULT := 2.0  # hold Shift for a speed boost — see _process

# "Stock" framing — what Esc returns to when nothing's focused, and what
# every session starts at.
const STOCK_YAW := 0.0
const STOCK_PITCH := -0.74  # matches the old fixed camera's implied angle
const STOCK_DISTANCE := 80.0  # widened alongside LOG_SCALE so the default view keeps roughly the same proportion of the (now bigger) system in frame

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
const CALLOUT_DIAGONAL := Vector2(28.0, -28.0)  # up-right — BodyInfoPanel sits on the left, but the small target callout stays on the right
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

# "YOU ARE HERE" location marker — always on, independent of focus/selection
# entirely (see _update_location_marker). A pulsing ring around the current-
# location body when it's on screen; a triangular arrow clamped to the
# viewport edge, pointing toward it, when it isn't — the free-fly camera can
# point anywhere, so "just don't draw it" would leave a player exactly as
# lost as before this existed whenever they aren't already looking the right
# way. Deliberately a separate small overlay/draw path from the target-
# designator callout above (_callout_*) rather than folded into it — this
# tracks PlayerState.location_id, not whatever's focused/selected, and the
# two can easily be different bodies at once.
const YOU_ARE_HERE_RING_PAD := 10.0        # px beyond the body's own projected on-screen radius
const YOU_ARE_HERE_MIN_RING_RADIUS := 14.0 # floor for a body too small/far to measure a meaningful pixel radius
const YOU_ARE_HERE_PULSE_SPEED := 2.4      # rad/s
const YOU_ARE_HERE_PULSE_AMOUNT := 0.12    # +/- fraction of ring radius
const YOU_ARE_HERE_LABEL_GAP := 6.0
const YOU_ARE_HERE_EDGE_MARGIN := 36.0     # keeps the off-screen arrow/label clear of the viewport edge
const YOU_ARE_HERE_ARROW_LENGTH := 20.0
const YOU_ARE_HERE_ARROW_HALF_WIDTH := 10.0

enum CalloutStage { HIDDEN, WAITING_FOR_SWEEP, REVEALING_LINE, TYPING_NAME, DONE }

var _bodies: Array[Node3D] = []
var _orbits: Array[Dictionary] = []  # body, radius, body_radius, angle, speed, atmo — see _build_system/_process

var _pivot: Node3D
var _camera: Camera3D
var _yaw := STOCK_YAW
var _pitch := STOCK_PITCH
var _distance := STOCK_DISTANCE
var _target_distance := STOCK_DISTANCE
var _panning := false
var _looking := false  # RMB held — orbits the focused body, or free-fly mouselook when unfocused (see _unhandled_input)
var _left_press_pos := Vector2.ZERO
var _focused_body: Node3D = null
var _pan_target := Vector3.ZERO  # where the pivot eases to while unfocused — see _process's pivot-follow lerp
# Camera's actual current local-Z offset from the pivot — eases toward
# _distance (orbiting a focused body) or 0.0 (free-fly, rotate in place) each
# frame; see _process. Starts at 0.0 to match the unfocused starting state —
# _build_camera bakes the stock "pulled back" framing into _pan_target/
# _pivot.position instead, not this.
var _orbit_offset := 0.0

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
var _locations_panel: LocationsPanel

# --- "YOU ARE HERE" location marker (see its constants' own comment) ---
var _location_marker_overlay: Control
var _location_marker_label: Label
var _location_marker_visible := false      # false only when there's no trackable orbit for the current location at all
var _location_marker_on_screen := false
var _location_marker_screen_pos := Vector2.ZERO  # on-screen: the body's own projected center; off-screen: the clamped edge point the arrow sits at
var _location_marker_ring_radius := 0.0


func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_system()
	_build_asteroids()
	_build_callout()
	_build_location_marker()
	_build_body_panel()
	_build_locations_panel()
	AmbientManager.play_map_ambient()
	HUD.set_view("Solar System", "solar_system")
	# Re-clicking the SOLAR SYSTEM tab while already here recenters instead
	# of no-opping — see HUD.recenter_requested's own comment.
	HUD.recenter_requested.connect(_recenter)
	# Registers this view as the source of truth for a lock's real snapshot
	# distance — see Destination.lock()'s own comment for why this has to
	# be a synchronous callback Destination itself calls, not a listener
	# reacting to its own destination_changed signal.
	Destination.set_snapshot_provider(_compute_snapshot_distance_km)


# Destination.preview_id/preview_distance_km are plain fields (see their own
# comment for why, unlike _snapshot_provider), not a Callable that naturally
# goes invalid when this view is freed — leaving this scene with a body
# still focused would otherwise leave ConsolePanel showing a frozen, wrong
# live-distance readout forever after, since nothing would ever clear it.
func _exit_tree() -> void:
	Destination.clear_preview()


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
		var local_pos := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		# Inclination/ascending-node tilt — real Keplerian elements, unlike
		# the flat circular orbit above. Planets/Sol never set these (default
		# 0.0 here means no rotation, so they stay exactly on the flat
		# ecliptic plane as before); asteroids do, see _spawn_dummy_asteroid —
		# real ones are visibly NOT coplanar the way the planets roughly are,
		# which reads as flat and wrong once bodies are small enough that a
		# perfectly flat field is obvious.
		var inclination: float = orbit.get("inclination", 0.0)
		var asc_node: float = orbit.get("asc_node", 0.0)
		if inclination != 0.0 or asc_node != 0.0:
			local_pos = local_pos.rotated(Vector3.RIGHT, inclination).rotated(Vector3.UP, asc_node)
		body.position = local_pos
		var atmo: MeshInstance3D = orbit["atmo"]
		if atmo != null:
			(atmo.material_override as ShaderMaterial).set_shader_parameter(
					"sun_dir", (-body.position).normalized())

	# Free-fly movement — unfocused only (see FREE_FLY_SPEED_MULT's class
	# comment). Forward/back/strafe move along the CAMERA's current facing
	# (not a fixed world axis), so pitching down before pressing forward
	# flies you down-and-forward — ordinary 6DOF free-cam behavior. Keys
	# come from ControlScheme (WASD or ESDF, player's choice — see Options),
	# not hardcoded here. Space/Ctrl are the odd ones out, deliberately: they
	# move along the WORLD up/down axis, not the camera's local up, which is
	# what "straight up" actually means regardless of which way you're
	# looking — the usual convention (Blender, Unity's scene view, etc.),
	# and scheme-agnostic since there's no WASD/ESDF equivalent to remap.
	# Written straight into both _pivot.position and _pan_target, same
	# lockstep trick the RMB-drag pan below already uses, so the
	# pivot-follow lerp just below has nothing to fight.
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

	# Glide the pivot toward wherever it should be — the focused body's live
	# position, or _pan_target once nothing's focused — instead of snapping.
	# Framerate-independent exponential smoothing rather than a fixed-
	# duration tween: the target itself keeps moving (an orbiting planet),
	# so a tween-to-a-fixed-point would fall behind by the time it finishes;
	# this keeps chasing the live position the whole way, decelerating into
	# it, and handles "switching directly from one planet to another" and
	# "returning to the stock view" the same way, since both are just "the
	# target changed" — no separate transition state needed. _pan_target
	# (not a hardcoded Vector3.ZERO) is what makes manual panning stick —
	# see the mouse-motion handler below, which moves it in lockstep with
	# the pivot itself so this lerp has nothing left to fight.
	var pivot_target := _focused_body.position if _focused_body != null else _pan_target
	var t := 1.0 - exp(-delta * FOCUS_SWEEP_RATE)
	_pivot.position = _pivot.position.lerp(pivot_target, t)

	# Same easing for zoom, toward whatever _select()/_clear_focus() set as
	# the target — a manual wheel-zoom (see _unhandled_input) retargets this
	# too, so it doesn't keep fighting the player's own zoom input.
	if not is_equal_approx(_distance, _target_distance):
		_distance = lerpf(_distance, _target_distance, t)
		_update_camera()

	# Camera's local offset from the pivot eases between two very different
	# meanings depending on focus state: examining a body (offset ~= _distance,
	# camera orbits/swings around it on rotation — the original, unchanged
	# feel) vs. free flight (offset ~= 0, camera rotates IN PLACE instead of
	# sweeping a wide arc around wherever the pivot happens to be). This is
	# the actual fix for "rotating after flying far away sweeps a huge orbit
	# that looks like it's circling the Sun" — the camera used to sit
	# _distance away from the pivot regardless of whether anything was being
	# examined, so turning to look around always orbited that offset point.
	# Eased with the same `t` as the pivot-position lerp above so a focus/
	# unfocus transition glides smoothly between the two instead of popping.
	#
	# Targets _target_distance (the FINAL close-up distance _select() just
	# set), not the live _distance above — _distance is still easing from
	# wherever it was during free-fly (which doubles as the WASD speed dial,
	# so it can be large) toward that same target. Chasing _distance instead
	# of _target_distance meant _orbit_offset ballooned outward first,
	# tracking that stale large number, before finally shrinking back down
	# once _distance itself caught up — the camera visibly pulled back
	# before zooming in, instead of easing straight from "wherever it
	# already was" to the target.
	var target_offset := _target_distance if _focused_body != null else 0.0
	_orbit_offset = lerpf(_orbit_offset, target_offset, t)
	_camera.position = Vector3(0.0, 0.0, _orbit_offset)

	if _callout_stage == CalloutStage.WAITING_FOR_SWEEP:
		_sweep_elapsed += delta

	_update_callout()
	_update_location_marker()


# --- 3D scene ---

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.005, 0.007, 0.012)
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
	_update_camera()  # sets _pivot.rotation from the stock yaw/pitch below

	# Stock framing used to come purely from the camera's own offset
	# (Vector3(0,0,STOCK_DISTANCE) from a pivot fixed at the origin) — that
	# offset is now reserved for actually orbiting a focused body (see
	# _process's _orbit_offset), so the equivalent "pulled back to see the
	# whole system" starting view has to live in the pivot's own POSITION
	# instead, or the very first unfocused frame would put the camera
	# sitting right on top of Sol.
	_pan_target = _pivot.basis * Vector3(0.0, 0.0, STOCK_DISTANCE)
	_pivot.position = _pan_target

	var stars := StarfieldStars.new()
	stars.follow = _camera
	add_child(stars)


func _update_camera() -> void:
	_pitch = clampf(_pitch, -1.45, 1.45)
	_distance = clampf(_distance, MIN_DISTANCE, MAX_DISTANCE)
	_pivot.rotation = Vector3(_pitch, _yaw, 0)
	# Camera's own local offset from the pivot is NOT set here — see
	# _process's _orbit_offset easing, which is now the sole owner of
	# _camera.position (setting it here too would fight that lerp on every
	# discrete drag/zoom event this function also runs on).


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


# Existence + count for a population, purely a function of its own seed
# label — free/derived, never persisted (see the "existence + count" tier in
# the universe-generation-architecture memory). Sol is the only system today,
# so a fixed label string stands in for what will eventually be a real
# per-system seed once other systems exist.
func _seeded_count(seed_label: String, min_count: int, max_count: int) -> int:
	return min_count + posmod(seed_label.hash(), max_count - min_count + 1)


# Still no survey data (next step) but population/orbits are now real
# seed-derived generation (see AU_MIN/MAX/_COUNT_MIN/MAX above and
# _seeded_count), not fixed dummies, and now cover more than just the Main
# Belt — real asteroids (as opposed to icy trans-Neptunian objects, a
# distinct population left for a possible future Kuiper Belt/dwarf-planet
# feature) are genuinely scattered well beyond it. No orbit ring on any of
# these (unlike planets/_build_orbit_ring above) — the whole point is a
# drifting field, not something that reads as a planet or moon.
func _build_asteroids() -> void:
	var belt_count := _seeded_count("Sol/AsteroidBelt", ASTEROID_BELT_COUNT_MIN, ASTEROID_BELT_COUNT_MAX)
	for i in belt_count:
		_spawn_dummy_asteroid("AST-BELT-%d" % (i + 1),
				ASTEROID_BELT_AU_MIN, ASTEROID_BELT_AU_MAX, ASTEROID_BELT_INCLINATION_MAX_DEG)

	var earth_au := KnownBodies.get_entry("Earth").au_distance
	var nea_count := _seeded_count("Sol/NEA", NEA_COUNT_MIN, NEA_COUNT_MAX)
	for i in nea_count:
		_spawn_dummy_asteroid("AST-NEA-%d" % (i + 1),
				earth_au - NEA_AU_JITTER, earth_au + NEA_AU_JITTER, NEA_INCLINATION_MAX_DEG)

	var centaur_count := _seeded_count("Sol/Centaurs", CENTAUR_COUNT_MIN, CENTAUR_COUNT_MAX)
	for i in centaur_count:
		_spawn_dummy_asteroid("AST-CENT-%d" % (i + 1),
				CENTAUR_AU_MIN, CENTAUR_AU_MAX, CENTAUR_INCLINATION_MAX_DEG)

	_spawn_trojans()


# Real Trojans aren't on their own AU-band orbit at all — they share
# Jupiter's own semi-major axis/period, clustered around its L4 (leading)
# and L5 (trailing) Lagrange points. Reads Jupiter's already-built _orbits
# entry (from _build_system, which always runs first — see _ready) rather
# than an independent roll.
func _spawn_trojans() -> void:
	var jupiter_orbit := _find_orbit("Jupiter")
	if jupiter_orbit.is_empty():
		return
	var jupiter_angle: float = jupiter_orbit["angle"]
	var jupiter_radius: float = jupiter_orbit["radius"]
	var jupiter_speed: float = jupiter_orbit["speed"]
	# jupiter_radius above is DISPLAY radius (log-scaled units, for the map
	# itself) — registration needs the real AU distance instead, same as
	# _spawn_dummy_asteroid registers for its own population.
	var jupiter_au := KnownBodies.get_entry("Jupiter").au_distance

	for cluster_sign in [1.0, -1.0]:  # L4 leads Jupiter, L5 trails it
		var label := "L4" if cluster_sign > 0.0 else "L5"
		var count := _seeded_count("Sol/Trojans/%s" % label, TROJAN_COUNT_MIN, TROJAN_COUNT_MAX)
		for i in count:
			_spawn_trojan("AST-TROJ-%s-%d" % [label, i + 1], jupiter_angle, jupiter_radius, jupiter_speed, jupiter_au, cluster_sign)


func _find_orbit(body_name: String) -> Dictionary:
	for orbit: Dictionary in _orbits:
		var body: Node3D = orbit["body"]
		if body.name == body_name:
			return orbit
	return {}


# Called SYNCHRONOUSLY by Destination.lock() itself (see that function's
# comment, and set_snapshot_provider above) — returns the real snapshot
# distance for locking `id` right now, using both endpoints' live angle
# data. -1.0 (Destination's own "no snapshot" default) if either endpoint
# isn't a body this view is currently tracking — a lock made for a body
# Planetary System View owns instead, or while docked somewhere with no
# live orbital data at all, just falls back to TravelCalc's existing
# radial-only approximation, same as before this existed.
func _compute_snapshot_distance_km(id: String) -> float:
	var to_orbit := _find_orbit(id)
	var from_orbit := _current_location_orbit()
	if to_orbit.is_empty() or from_orbit.is_empty():
		return -1.0
	return _true_distance_km(from_orbit, to_orbit)


# Wherever the player currently is, resolved to one of THIS view's tracked
# orbits — directly if they're at Sol/a planet/an asteroid (all live here),
# or via its parent planet's orbit if they're docked at a moon (moons
# aren't individually tracked in System view at all — using the parent's
# position is a fine stand-in, since a moon-to-planet offset is negligible
# next to AU-scale distances).
func _current_location_orbit() -> Dictionary:
	var direct := _find_orbit(PlayerState.location_id)
	if not direct.is_empty():
		return direct
	var entry := KnownBodies.get_entry(PlayerState.location_id)
	if entry != null and entry.parent != "":
		return _find_orbit(entry.parent)
	return {}


# Real straight-line distance (km) between two bodies given their actual
# CURRENT 3D position, not just how far each is from Sol. Genuinely 3D, not
# flat law-of-cosines on the pre-tilt angle alone (an earlier version of
# this function did that and was WRONG for any asteroid with a nonzero
# ascending node — asc_node rotates the body's position around the
# vertical axis by up to a full 360 degrees, which measurably swings its
# true angular position around the Sun, not just its height above/below
# the ecliptic; ignoring it meant comparing against an angle that had
# nothing to do with where the body is actually rendered). Planets are
# unaffected either way (inclination/asc_node are always 0 for them), but
# every asteroid needs the real rotated position — see
# _real_orbit_position_au, which applies the exact same rotation _process
# uses for display, just at real au_distance scale instead of the
# log-compressed display radius.
func _true_distance_km(from_orbit: Dictionary, to_orbit: Dictionary) -> float:
	var from_body: Node3D = from_orbit["body"]
	var to_body: Node3D = to_orbit["body"]
	var from_entry := KnownBodies.get_entry(from_body.name)
	var to_entry := KnownBodies.get_entry(to_body.name)
	if from_entry == null or to_entry == null:
		return -1.0
	var from_pos_au := _real_orbit_position_au(from_orbit, from_entry.au_distance)
	var to_pos_au := _real_orbit_position_au(to_orbit, to_entry.au_distance)
	return from_pos_au.distance_to(to_pos_au) * TravelCalc.AU_KM


# Real (not display-compressed) 3D position in AU, Sol-centered — the same
# inclination/ascending-node rotation _process applies when placing the
# body on screen (see that function's own comment), just computed at real
# au_distance scale so the RESULT is a genuine AU-space position, not a
# display-space one.
func _real_orbit_position_au(orbit: Dictionary, radius_au: float) -> Vector3:
	var angle: float = orbit["angle"] as float
	var flat := Vector3(cos(angle) * radius_au, 0.0, sin(angle) * radius_au)
	var inclination: float = orbit.get("inclination", 0.0)
	var asc_node: float = orbit.get("asc_node", 0.0)
	if inclination != 0.0 or asc_node != 0.0:
		flat = flat.rotated(Vector3.RIGHT, inclination).rotated(Vector3.UP, asc_node)
	return flat


# Shared by every asteroid spawner below — builds the visual + designation,
# leaving position/orbit-dict entirely to the caller since Trojans place
# themselves very differently (see _spawn_trojan) from an AU-band population
# (see _spawn_dummy_asteroid). Returns the built radius alongside the body
# since AsteroidParams itself isn't otherwise visible to the caller.
func _build_asteroid_body(rng: RandomNumberGenerator, seed_hash: int) -> Dictionary:
	var params := AsteroidParams.new()
	params.seed_value = seed_hash
	params.radius = rng.randf_range(ASTEROID_RADIUS_MIN, ASTEROID_RADIUS_MAX)
	# Ranges tightened 2026-07-13 after Cosmic Forge experimentation settled
	# on new caps (irregularity 0.6, crater density/size 0.25, depth 0.1) —
	# see CosmicForge.gd's ASTEROID_KNOBS, which these mirror.
	params.irregularity = rng.randf_range(0.35, 0.6)
	params.elongation = rng.randf_range(0.15, 0.45)
	params.crater_density = rng.randf_range(0.1, 0.25)
	params.crater_size = rng.randf_range(0.12, 0.25)
	params.crater_depth = rng.randf_range(0.05, 0.1)
	params.detail = 3  # capped flat — even the low end of the old 3-5 random range (2026-07-13) was still a noticeable load hitch across a whole belt population at this scale

	var body := AsteroidGenerator.generate(params)
	body.name = AsteroidDesignation.generate(seed_hash)
	return {"body": body, "radius": params.radius}


# `seed_id` is internal only — it seeds the shape/designation below AND now
# the asteroid's own orbital elements (AU distance, inclination, ascending
# node), so a given slot's whole identity — not just its name — stays
# stable across reloads, the way a real cataloged object's orbit wouldn't
# just change between sessions. body.name (what selection/Discoveries/the
# callout label all key off, same as every other body in this file) is the
# generated designation, so two asteroids never collide with each other's
# seed string either.
func _spawn_dummy_asteroid(seed_id: String, au_min: float, au_max: float, inclination_max_deg: float) -> void:
	var seed_hash := seed_id.hash()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_hash

	var au := rng.randf_range(au_min, au_max)
	var inclination := deg_to_rad(rng.randf_range(-inclination_max_deg, inclination_max_deg))
	var asc_node := rng.randf_range(0.0, TAU)
	var built := _build_asteroid_body(rng, seed_hash)
	var body: Node3D = built["body"]
	# Registers the EXACT au this asteroid is actually placed at below —
	# see Research.gd's _asteroid_au_distance comment for why Cockpit/
	# TravelCalc read this back instead of independently re-rolling their
	# own guess at the same number.
	Research.register_asteroid_orbit(body.name, au)

	# Phase along the orbit is the one thing that still rerolls each load —
	# same "no real ephemeris yet" simplification the planets above already
	# use (see their own "rerolled each load" comment); everything else
	# about the orbit itself (au/inclination/asc_node above) is now fixed
	# per identity, not just the shape/name.
	var start_angle := randf_range(0.0, TAU)
	var display_r := BASE_GAP + LOG_SCALE * log(au + 1.0)
	var flat_pos := Vector3(cos(start_angle) * display_r, 0.0, sin(start_angle) * display_r)
	body.position = flat_pos.rotated(Vector3.RIGHT, inclination).rotated(Vector3.UP, asc_node)
	add_child(body)
	_bodies.append(body)

	_orbits.append({
		"body": body,
		"radius": display_r,
		"body_radius": built["radius"],
		"angle": start_angle,
		"speed": ORBIT_SPEED / pow(au, 1.5),
		"inclination": inclination,
		"asc_node": asc_node,
		"atmo": null,
	})


# Co-orbital with Jupiter, not an independent orbit — same radius/speed as
# Jupiter itself keeps this angular offset fixed forever (a real Lagrange
# point relationship), not just accurate at the moment of spawn.
func _spawn_trojan(seed_id: String, jupiter_angle: float, jupiter_radius: float,
		jupiter_speed: float, jupiter_au: float, cluster_sign: float) -> void:
	var seed_hash := seed_id.hash()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_hash

	var offset := deg_to_rad(cluster_sign * TROJAN_CLUSTER_OFFSET_DEG
			+ rng.randf_range(-TROJAN_CLUSTER_SPREAD_DEG, TROJAN_CLUSTER_SPREAD_DEG))
	var inclination := deg_to_rad(rng.randf_range(-TROJAN_INCLINATION_MAX_DEG, TROJAN_INCLINATION_MAX_DEG))
	var asc_node := rng.randf_range(0.0, TAU)
	var built := _build_asteroid_body(rng, seed_hash)
	var body: Node3D = built["body"]
	# Co-orbital with Jupiter — registers Jupiter's own real AU distance,
	# same reasoning as _spawn_dummy_asteroid's own registration.
	Research.register_asteroid_orbit(body.name, jupiter_au)

	var angle := jupiter_angle + offset
	var flat_pos := Vector3(cos(angle) * jupiter_radius, 0.0, sin(angle) * jupiter_radius)
	body.position = flat_pos.rotated(Vector3.RIGHT, inclination).rotated(Vector3.UP, asc_node)
	add_child(body)
	_bodies.append(body)

	_orbits.append({
		"body": body,
		"radius": jupiter_radius,
		"body_radius": built["radius"],
		"angle": angle,
		"speed": jupiter_speed,
		"inclination": inclination,
		"asc_node": asc_node,
		"atmo": null,
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
# Hold RMB — rotate (orbits the focused body if there is one, so you can
# look at it from any angle; turns the free-fly camera in place otherwise);
# cursor hides for the duration of the hold and reappears on release, same
# idiom as any mouselook control (see _unhandled_input's MOUSE_BUTTON_RIGHT
# case) · Wheel — zoom · Middle-drag — pan · movement keys (WASD or ESDF,
# see ControlScheme) — free-fly, unfocused only (see FREE_FLY_SPEED_MULT's
# class comment). LMB is click-to-select only now (2026-07-16) — it used to
# double as a rotate-drag too, but that made a plain click-to-focus attempt
# too easy to accidentally spin the camera with instead. Pan/free-fly are
# no-ops while focused — _process re-glues the pivot to the body every
# frame, so anything that moves the pivot manually gets overwritten the
# instant it's applied. Esc clears focus, or leaves to Cockpit if nothing's
# focused.

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
				# Focused only — unfocused, _distance is purely the free-fly
				# speed dial (see FREE_FLY_SPEED_MULT), not a camera-position
				# input (_orbit_offset ignores it entirely while unfocused,
				# see _process), so scrolling while unfocused used to have NO
				# visible effect yet silently changed WASD speed anyway — a
				# player would notice speed randomly drifting with no idea
				# why. _clear_focus already resets _target_distance back to
				# STOCK_DISTANCE on unfocus specifically so speed doesn't
				# stay wherever a prior zoom left it; a no-op wheel here is
				# what keeps that reset meaningful instead of immediately
				# overwritable by a stray scroll.
				if _focused_body != null:
					_distance *= ZOOM_STEP
					_target_distance = _distance  # manual zoom overrides any focus-zoom in progress
					_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if _focused_body != null:
					_distance /= ZOOM_STEP
					_target_distance = _distance
					_update_camera()
			MOUSE_BUTTON_LEFT:
				# Click-to-select only — no longer a rotate-drag (see class
				# comment above _unhandled_input), so pressing LMB no longer
				# needs to track anything but where it went down.
				if mb.pressed:
					_left_press_pos = mb.position
				elif mb.position.distance_to(_left_press_pos) < CLICK_DRAG_THRESHOLD:
					# Released close to where it was pressed — a click, not
					# a drag; try to select whatever's under the cursor.
					_try_select(mb.position)
			MOUSE_BUTTON_RIGHT:
				_looking = mb.pressed
				# Hidden for the duration of the hold, not CAPTURED — this
				# only needs to hide the cursor, not confine/re-center it
				# (which would fight the OS cursor position once released).
				Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if mb.pressed else Input.MOUSE_MODE_VISIBLE
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _looking:
			# Orbits around the focused body when there is one (lets you
			# look at it from any angle), or turns the free-fly camera in
			# place when there isn't (see _process's _orbit_offset, which is
			# what actually decides "orbit around a point" vs. "rotate in
			# place" — this input handler doesn't need to care which one is
			# currently happening).
			_yaw -= mm.relative.x * ORBIT_SENSITIVITY
			_pitch -= mm.relative.y * ORBIT_SENSITIVITY
			_update_camera()
		elif _panning and _focused_body == null:
			var scale_factor := _distance * PAN_SENSITIVITY
			var offset := (-_camera.global_basis.x * mm.relative.x
					+ _camera.global_basis.y * mm.relative.y) * scale_factor
			_pivot.position += offset
			_pan_target += offset  # keep _process's pivot-follow lerp from pulling the pan straight back to Sol


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
	# Old target's readout/scan prompt would otherwise still be showing while
	# the camera sweeps to the new one.
	_body_panel.hide_panel()
	_scan_prompt.reset()
	_lock_button.reset()
	_callout_go_btn.visible = false


func _clear_focus() -> void:
	# Camera stays exactly where it is instead of sweeping back to the
	# stock Sol-centered view (2026-07-13 feedback: deselecting should just
	# untarget, not yank you back across the map). While focused, the
	# camera's actual world position is _pivot.position + _pivot.basis *
	# Vector3(0,0,_orbit_offset) — the body's position, plus the orbit
	# offset back out toward the camera (see _process's _orbit_offset
	# comment). Capturing that as the new _pivot.position, and zeroing
	# _orbit_offset in the same breath, just re-labels which variables
	# encode the SAME physical camera position — a pure bookkeeping
	# handoff, not a move, so there's nothing to visually pop or ease.
	# Yaw/pitch are left alone for the same reason — you keep looking
	# exactly the way you were.
	var camera_world_pos := _pivot.position + _pivot.basis * Vector3(0.0, 0.0, _orbit_offset)
	_focused_body = null
	_pivot.position = camera_world_pos
	_pan_target = camera_world_pos
	_orbit_offset = 0.0
	_camera.position = Vector3.ZERO
	# Distance itself still resets — now that it's purely the free-fly
	# speed dial once unfocused (see FREE_FLY_SPEED_MULT), not a camera-
	# position input, resetting it can't reintroduce the sweep above; it
	# just brings WASD speed back to a sane default instead of staying
	# crawl-slow from whatever close-up zoom you were just at.
	_target_distance = STOCK_DISTANCE

	if _line_tween != null:
		_line_tween.kill()
	_callout_stage = CalloutStage.HIDDEN
	_callout_line_progress = 0.0
	_callout_label.visible = false
	_body_panel.hide_panel()
	_scan_prompt.reset()
	_lock_button.reset()
	_callout_go_btn.visible = false


# The "I flew off into empty space and got lost" recovery — unlike Esc/
# _clear_focus above (which now deliberately leaves the camera exactly
# where it is), this is SUPPOSED to sweep back to the stock Sol-centered
# view, so it resets yaw/pitch and recomputes the stock pan target the same
# way _clear_focus used to before that changed. Calls _clear_focus first
# so a still-focused body gets properly deselected (UI reset, etc.) as
# part of the same action, then overrides the position/rotation targets
# it just set.
func _recenter() -> void:
	_clear_focus()
	_yaw = STOCK_YAW
	_pitch = STOCK_PITCH
	_update_camera()
	# Same "pulled back" trick _build_camera uses for the initial view (see
	# its own comment); _pivot.basis is already correct since _update_camera
	# just applied the new rotation above. Only _pan_target is set, not
	# _pivot.position directly — the existing pivot-follow lerp in _process
	# sweeps there smoothly instead of snapping.
	_pan_target = _pivot.basis * Vector3(0.0, 0.0, STOCK_DISTANCE)


# --- Callout ---
# A sci-fi target-designator: dot on the body, angled leader line, elbow to
# horizontal, name label. Screen-space overlay recomputed every frame from
# the focused body's projected position — it has to track both camera
# movement and the body's own orbital motion.

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
	UITheme.style_label_shadow(_callout_label)
	_callout_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_callout_label.visible = false
	_overlay_layer.add_child(_callout_label)

	_scan_prompt = ScanPrompt.new()
	_scan_prompt.pressed_for.connect(_on_scan_requested)
	_overlay_layer.add_child(_scan_prompt)

	_lock_button = LockButton.new()
	_overlay_layer.add_child(_lock_button)

	# GO, right under LOCK/UNLOCK — only for whichever body is BOTH focused
	# AND currently locked (see _update_callout), so you can commit to a trip
	# without detouring through LocationsPanel just to press GO. Same
	# lock+travel+viewer-swap sequence LocationsPanel's own GO uses.
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


# --- "You are here" location marker ---
# See its constants' own comment for why this is entirely separate from the
# target-designator callout above.

func _build_location_marker() -> void:
	_location_marker_overlay = Control.new()
	_location_marker_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_location_marker_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_location_marker_overlay.draw.connect(_draw_location_marker)
	_overlay_layer.add_child(_location_marker_overlay)

	_location_marker_label = Label.new()
	_location_marker_label.text = "YOU ARE HERE"
	_location_marker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_location_marker_label.add_theme_font_size_override("font_size", 12)
	_location_marker_label.add_theme_color_override("font_color", UITheme.accent)
	UITheme.style_label_shadow(_location_marker_label)
	_location_marker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_location_marker_label.visible = false
	_overlay_layer.add_child(_location_marker_label)


# Recomputed every frame (camera moves, and the location body itself keeps
# orbiting) — resolves PlayerState.location_id the same way the snapshot-
# distance system already does (_current_location_orbit, moon-docked players
# fall back to their parent planet's orbit, the only one actually tracked
# here) and projects it to screen space.
func _update_location_marker() -> void:
	var orbit := _current_location_orbit()
	if orbit.is_empty():
		_location_marker_visible = false
		_location_marker_label.visible = false
		_location_marker_overlay.queue_redraw()
		return
	_location_marker_visible = true

	var body: Node3D = orbit["body"]
	var world_pos := body.position
	var behind := _camera.is_position_behind(world_pos)
	var viewport_size := _location_marker_overlay.size
	var center := viewport_size * 0.5
	var screen_pos := _camera.unproject_position(world_pos)
	if behind:
		# unproject_position mirrors a behind-camera point through the screen
		# center rather than returning something usable directly — flip it
		# back before treating it as a direction to point the edge arrow in.
		screen_pos = center + (center - screen_pos)

	var margin := YOU_ARE_HERE_EDGE_MARGIN
	_location_marker_on_screen = (not behind
			and screen_pos.x >= margin and screen_pos.x <= viewport_size.x - margin
			and screen_pos.y >= margin and screen_pos.y <= viewport_size.y - margin)

	if _location_marker_on_screen:
		_location_marker_screen_pos = screen_pos
		# Same "project a world-space offset, measure the pixel gap" trick
		# used nowhere else in this file yet — the body's own display radius
		# (orbit["body_radius"]) alone doesn't say how BIG that reads on
		# screen at the camera's current zoom, so an actual second
		# projection is the only way to get a screen-space ring size that
		# tracks zoom correctly.
		var body_radius: float = orbit.get("body_radius", 0.3)
		var edge_world := world_pos + _camera.global_transform.basis.x * body_radius
		var px_radius := screen_pos.distance_to(_camera.unproject_position(edge_world))
		_location_marker_ring_radius = maxf(px_radius + YOU_ARE_HERE_RING_PAD, YOU_ARE_HERE_MIN_RING_RADIUS)
		_location_marker_label.position = Vector2(
				screen_pos.x - _location_marker_label.size.x * 0.5,
				screen_pos.y + _location_marker_ring_radius + YOU_ARE_HERE_LABEL_GAP)
	else:
		_location_marker_screen_pos = _clamp_to_edge(center, screen_pos, viewport_size, margin)
		_location_marker_label.position = Vector2(
				_location_marker_screen_pos.x - _location_marker_label.size.x * 0.5,
				_location_marker_screen_pos.y + YOU_ARE_HERE_ARROW_LENGTH + YOU_ARE_HERE_LABEL_GAP)

	_location_marker_label.visible = true
	_location_marker_overlay.queue_redraw()


# Where a ray from `center` through `target` crosses the inset viewport
# rectangle's boundary — standard AABB ray-clamp, used to place the
# off-screen arrow. `target` can lie far outside the viewport (an
# unproject_position result is unbounded), so this only ever uses its
# DIRECTION from center, never its magnitude.
func _clamp_to_edge(center: Vector2, target: Vector2, viewport_size: Vector2, margin: float) -> Vector2:
	var dir := target - center
	if dir.length() < 0.001:
		dir = Vector2.UP  # degenerate (dead-on behind/in front of camera) — arbitrary but stable direction
	dir = dir.normalized()
	var half := Vector2(viewport_size.x * 0.5 - margin, viewport_size.y * 0.5 - margin)
	var t := INF
	if absf(dir.x) > 0.0001:
		t = minf(t, half.x / absf(dir.x))
	if absf(dir.y) > 0.0001:
		t = minf(t, half.y / absf(dir.y))
	return center + dir * t


func _draw_location_marker() -> void:
	if not _location_marker_visible:
		return
	var color := UITheme.accent
	var pulse := 1.0 + sin(Time.get_ticks_msec() / 1000.0 * YOU_ARE_HERE_PULSE_SPEED) * YOU_ARE_HERE_PULSE_AMOUNT

	if _location_marker_on_screen:
		_location_marker_overlay.draw_arc(
				_location_marker_screen_pos, _location_marker_ring_radius * pulse, 0.0, TAU, 48, color, 2.0, true)
	else:
		var center := _location_marker_overlay.size * 0.5
		var dir := (_location_marker_screen_pos - center).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var back := _location_marker_screen_pos - dir * YOU_ARE_HERE_ARROW_LENGTH * pulse
		_location_marker_overlay.draw_colored_polygon(PackedVector2Array([
			_location_marker_screen_pos,
			back + perp * YOU_ARE_HERE_ARROW_HALF_WIDTH,
			back - perp * YOU_ARE_HERE_ARROW_HALF_WIDTH,
		]), color)


# --- Body info panel ---
# Gated behind ScanPrompt now, not automatic — planets are unknown
# properties until scanned (see the scanning design conversation in
# parallax-core-design-decisions memory). Pressing SCAN/RESCAN runs the
# panel's own scanning animation; BodyInfoPanel.scan_finished then flips the
# button to RESCAN. Already-scanned bodies skip straight to the data (see
# _select() below), no animation needed.

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
		return  # focus moved on before this fired — stale, ignore
	var entry := KnownBodies.get_entry(id)
	if entry != null:
		_body_panel.start_scan(entry)


func _on_scan_finished(id: String) -> void:
	if _focused_body != null and _focused_body.name == id:
		_scan_prompt.mark_scanned()
	_locations_panel.refresh()


# --- Known Locations panel ---
# Standing, not focus-gated like the callout controls above — see
# LocationsPanel.gd for why (the friction it's solving) and how it stays in
# sync (refreshed here on a fresh scan; a moon scanned in Planetary System
# view doesn't need a live hook since returning here is always a fresh
# scene load).

func _build_locations_panel() -> void:
	_locations_panel = LocationsPanel.new()
	_locations_panel.location_selected.connect(_on_locations_panel_selected)
	_overlay_layer.add_child(_locations_panel)


# Mirrors a panel selection into this view's own 3D focus — same _select()
# a direct click on the body would trigger. Only Sol/planets actually exist
# in this scene's _orbits; a moon selected in the panel has nothing here to
# focus, so this simply no-ops for it (see LocationsPanel.gd's header).
func _on_locations_panel_selected(id: String) -> void:
	for orbit: Dictionary in _orbits:
		var body: Node3D = orbit["body"]
		if body.name == id:
			_select(body, orbit["body_radius"])
			return


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
		# Stays on the right even though BodyInfoPanel now sits on the left —
		# the two are deliberately on opposite sides here.
		_callout_anchor = _camera.unproject_position(_focused_body.position)
		_callout_elbow = _callout_anchor + CALLOUT_DIAGONAL
		_callout_line_end = _callout_elbow + Vector2(CALLOUT_HORIZONTAL, 0.0)

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

	# Tracks the same camera-relative visibility as the label/line — the
	# SCAN/LOCK controls shouldn't float on screen once you've panned the
	# focused body behind the camera.
	_scan_prompt.visible = _callout_visible
	_lock_button.visible = _callout_visible

	# GO only for a focused body that's ALSO the current locked destination —
	# appears the moment you LOCK, disappears on UNLOCK (or if focus moves to
	# a different body than the one you locked).
	var focused_id: String = String(_focused_body.name) if _focused_body != null else ""

	# Live distance-to-focused-body preview (see Destination.preview_id) —
	# pushed every frame regardless of callout visibility/stage, since the
	# whole point is watching the number while a body is focused, even
	# before its callout has finished sweeping in. ConsolePanel is the
	# reader; ANY focused id works here, not just ones with a callout shown,
	# since _compute_snapshot_distance_km already no-ops (-1.0) for ids this
	# view doesn't track.
	if focused_id != "":
		Destination.set_preview(focused_id, _compute_snapshot_distance_km(focused_id))
	else:
		Destination.clear_preview()

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
		# SCAN/RESCAN prompt appears once the name has actually finished
		# typing — reads as "target lock acquired," not an instant data pop
		# the moment you click. Already-scanned bodies skip straight to
		# showing the cached data (no animation needed); a fresh scan only
		# starts once SCAN is actually pressed (_on_scan_requested).
		_scan_prompt.present(for_body.name)
		# LOCK isn't gated behind scanning at all — you can commit to a
		# destination you've never scanned. It IS gated behind having a real
		# KnownBodies entry, though — Cockpit's whole transit-build sequence
		# (_build_transit) looks the destination up via KnownBodies.get_entry
		# and silently skips building a flight path at all if that's null.
		# This now passes for asteroids too — get_entry synthesizes a real
		# Entry for any REGISTERED one (see KnownBodies._synthesize_asteroid_
		# entry / Research.register_asteroid_orbit, called the instant this
		# asteroid was actually spawned) — so a body that's visible/
		# selectable here has always already been registered, and this never
		# blocks a real, clickable asteroid.
		if KnownBodies.get_entry(for_body.name) != null:
			_lock_button.present(for_body.name)
		if Discoveries.is_scanned(for_body.name):
			var entry := KnownBodies.get_entry(for_body.name)
			if entry != null:
				_body_panel.show_for(entry)


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
