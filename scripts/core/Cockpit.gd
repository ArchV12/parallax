extends Node3D

# The player's real "game" view — always shows wherever PlayerState says the
# player currently is (orbiting PlayerState.location_id), or, if a GO trip
# is in progress (PlayerState.is_traveling), a transit visual instead. Opens
# on Earth by default — the vertical slice's starting position (see the
# parallax-core-design-decisions memory). Bodies reuse CanonicalBodyGenerator
# directly, the same generator Cosmic Forge/System view use, rather than
# re-deriving a body's look here.
#
# Sol + all 9 planets are REAL, persistent objects in one shared local space
# (see _build_universe/_universe_bodies/_universe_positions) — not just
# whatever's currently orbited. Positions are decorative, not physically
# accurate, and deliberately don't correlate with System view's own (also
# fake, randomized-per-load) layout — each planet gets a stable-but-
# arbitrary direction (seeded off its name, like PlanetarySystemView's
# procedural moons already do) and a distance derived from its real AU
# figure (log-compressed, same idea SystemView's map uses, different
# constants for Cockpit's much smaller working scale). Moons are NOT part of
# this persistent layout — only whichever one is currently relevant (the
# current body itself, or its nearest-moon "secondary" dressing pick) ever
# exists, spawned ad hoc and anchored near its real parent position.
#
# Because every body has one real position now, GO is real point-to-point
# flight, not a fake proxy: the camera moves from an entry point near
# whatever you're leaving to an entry point near the destination — which is
# simply the same persistent (or ad-hoc-but-anchored) object the whole time,
# growing larger because the camera is genuinely approaching it, with every
# other real body passing by in the background along the way. There's no
# more "grow a stand-in, then swap it for the real thing on arrival."
#
# GO (ConsolePanel) always routes here first so the transit visual has
# somewhere to play out; the player can then leave via ViewSwitcher and
# wander other views mid-trip (PlayerState ticks regardless of which scene
# is loaded) — if travel finishes while Cockpit itself is the active scene,
# _on_travel_completed settles into orbit around the (already real, already
# visible) arrived body rather than requiring a scene reload or popping.

# Confirmed by a temporary debug test (2026-07-10): the raw point-to-point
# kinematic curve genuinely does decelerate to a clean stop — the problem
# was that a real, physically-derived deceleration never LOOKS like slowing
# down at real interplanetary distances, and every trip had a different
# final-approach speed. A first attempt fixed this with a Cockpit-local,
# unit-space-only "cruise zone," but that left the HUD's speed/status
# readout (TravelCalc) completely unaware of it — the camera would visibly
# be cruising while the readout still showed a stale "Acceleration Burn"
# and a nonsense multi-million km/s number, since the two were computed by
# two entirely separate, disagreeing formulas. The fix (2026-07-10, take 2):
# the whole burn+cruise flight shape now lives in ONE place —
# TravelCalc.flight_profile()/flight_progress() — and this file's position
# curve just calls flight_progress() directly instead of maintaining its
# own parallel kinematics. See TravelCalc.gd's class comment for the actual
# physics (burn to a peak speed, decelerate to a fixed real CRUISE_SPEED_KM_S,
# glide the final CRUISE_DISTANCE_KM at that speed).

const EARTH_RADIUS := 5.5
const LUNA_RADIUS := 4.0
# Sol's display radius is NOT a hand-tuned constant like every other body
# here — now that distance is a true linear AU scale (see
# PLANET_DIST_AU_TO_UNITS below), Sol's real radius can be run through that
# exact same km-to-units ratio and come out with its correct real apparent
# size (~0.5° from Earth, same as the real sun) for free, no fudging needed.
# Computed in _build_universe once KM_TO_UNITS exists; see that function.

const SPIN := 0.02  # rad/s — idle self-rotation, every body in the scene

# Universe layout — see class comment. A genuine linear scale model, not a
# log-compressed one: real AU distances (KnownBodies.au_distance) are
# multiplied straight through by PLANET_DIST_AU_TO_UNITS, calibrated off the
# one distance a player can feel by eye — Earth to the Moon. Tune
# MOON_ANCHOR_DIST until that specific gap "looks and feels correct," and
# every planet's distance from Sol falls out of the same real ratio
# automatically — Venus is properly far, Neptune is properly, deliberately
# absurd (over a million units out; it was never going to be more than a
# handful of pixels regardless of how it was scaled, so there's no reason
# not to just let it be honestly, astronomically far instead of faked
# closer). PLANET_CONE_DEG still scatters each planet's DIRECTION from Sol
# (real orbital angles aren't tracked, just distance) — wide enough to
# spread across the sky, narrow enough nothing ends up behind the camera.
const SOL_DISTANCE := 480.0                # fixed, along _camera_base_forward — the anchor everything else hangs off of. Unrelated to the AU scale below — just where Sol itself sits relative to the world origin.
const PLANET_CONE_DEG := 42.0
const EARTH_MOON_DISTANCE_KM := 384400.0   # real, for calibration only — see MOON_ANCHOR_DIST/PLANET_DIST_AU_TO_UNITS
const AU_KM := 149597870.0                 # real, for calibration only
const MOON_ANCHOR_DIST := 135.0            # how far a moon sits from its (real) parent position, in-units — the ONE distance in this whole layout that's tuned by eye rather than derived; every planet-from-Sol distance (AND Sol's own display radius) is derived FROM this. Must also clear the camera's own orbit shell around that parent (radius * ORBIT_RADIUS_MULT, ~10.5 for Earth) by a comfortable margin, or the orbit path clips straight through the moon.
const PLANET_DIST_AU_TO_UNITS := MOON_ANCHOR_DIST / (EARTH_MOON_DISTANCE_KM / AU_KM)  # units per AU — MOON_ANCHOR_DIST units represent the real Earth-Moon distance (in AU), so this ratio is the one true "units per AU" scale for the whole system
const KM_TO_UNITS := PLANET_DIST_AU_TO_UNITS / AU_KM   # units per km — same scale, expressed per-km for sizing real body radii (see Sol in _build_universe)
const MOON_ANCHOR_CONE_DEG := 70.0
const MOON_MIN_CLEARANCE := 6.0            # extra breathing room past the parent's own camera-orbit shell — see _moon_anchor_pos

# The camera orbit rig — the actual "you are in orbit" cue. Camera circles
# the primary body's fixed position at a distance scaled off the body's own
# display radius (a tight, dramatic "low orbit" rather than a distant
# survey shot). Deliberately NOT nose-aimed at the body — a real orbit is
# flown tangent to the path (facing the direction of travel), with the body
# off to one side rather than dead ahead. Pure tangent, though, puts the
# body exactly 90° off the forward axis — outside any normal FOV, which is
# why an earlier pass showed nothing but stars (read as "the ship is just
# spinning"). GLANCE blends the heading partway from pure-tangent toward
# body-facing so a real chunk of it curves into view near the left edge
# (which side goes fully into/out of frame as you round the body is exactly
# the "depending on how the ship is rolled" look being asked for) without
# going all the way back to the old dead-centered nose-aimed shot. TILT
# keeps the orbit plane from being a flat, perfectly equatorial circle.
const PLANE_INCLINATION_DEG := 6.0               # max vertical scatter for _seeded_direction — see its comment. Deliberately small and close to real solar-system inclinations (Mercury, the outlier, is ~7°) — the point is keeping every body close to ONE shared near-flat plane, not spreading them realistically.
const ORBIT_RADIUS_MULT := 1.9                   # closer low orbit — see class comment
const ORBIT_ANGULAR_SPEED := -TAU / 60.0         # one full lap every ~60s. Sign is deliberate, not
# arbitrary — it must match the (also flipped, see flat_tangent in
# _orbit_pose) nose direction the camera uses to glance at the body.
# Mismatched signs here are what earlier made the ship look like it was
# flying its own orbit path in reverse (nose pointed opposite the actual
# direction _orbit_angle was sweeping), even though the roll/CCW-vs-CW
# fix on its own was correct.
const ORBIT_TILT_DEG := 14.0
const ORBIT_GLANCE_DEG := 50.0                   # 0 = pure tangent (body at 90°, off-screen); 90 = old nose-aimed look_at

# How long the camera's reorientation-into-orbit takes AFTER arrival — see
# _total_lean_duration/_lean_elapsed and _on_travel_completed. Originally
# 5.5s, sized for a near-90° pole-to-equator swing back when
# _seeded_direction scattered bodies in a full symmetric cone (see that
# function's comment) — now that every body's straight-line approach lands
# close to the shared, near-flat orbital plane by construction, the POSITION
# swing left to play out here is small. But the ORIENTATION swing is NOT
# small even now — raw flight looks dead-center at the target
# (Basis.looking_at), while the orbit pose deliberately glances at it
# off-center (ORBIT_GLANCE_DEG below puts the body ~40° off boresight, not
# centered) — so there's a real ~40° turn to cover regardless of how flat
# the approach is. An earlier cut to 2.2s (before that residual gap was
# isolated from the position-plane issue above) squeezed that swing into
# too little time to read as smooth no matter how the blend curve
# (_apply_lean's eased_t) is shaped — peak angular velocity is a function of
# angle-covered/time, not just curve smoothness. NOT what times the ORBITAL
# INSERTION status label, which is governed by pre_arrival_lead_seconds and
# switches to "IN ORBIT" right at arrival regardless of this constant
# (ConsolePanel._on_travel_completed) — this only paces the camera's own
# post-arrival visual settle.
const ORBIT_SETTLE_DURATION := 4.0

# How long before arrival the camera's lean into orbit starts — NOT a fixed
# constant, computed per-trip (see _pre_swing_lead/_total_lean_duration,
# set once in _build_transit) via TravelCalc.pre_arrival_lead_seconds, which
# scales this as a fraction of the trip's own deceleration time rather than
# a flat number of seconds — a flat value doesn't work across wildly
# different trip lengths (a fixed 2-4s window is a huge chunk of a 15s
# cheat-engine hop, starting the reorientation while the ship is still
# visibly screaming toward the target, but negligible on a real multi-minute
# trip). Scaling with the trip means the swing only starts once the ship is
# ALREADY genuinely slow per the real deceleration curve, not early.
#
# Also solves the original problem this constant existed for: without a
# continuous curve, "approach eases to a stop, THEN a separate reorientation
# eases up from a stop" reads as two motions chained back to back, with a
# dead beat right at the seam (both eases have zero velocity at their own
# start/end). ONE continuous eased curve spans _pre_swing_lead (still
# mid-flight) through ORBIT_SETTLE_DURATION (post-arrival) — see
# _total_lean_duration/_lean_elapsed — so the slow start happens exactly
# once, and velocity is never reset.

# Departure maneuver — a real orientation burn, not a flat single-axis
# swing: the ship starts SUBSTANTIALLY off its heading — target roughly
# behind, off to one side, and above/below (yaw near/past 180°, plus real
# pitch and a hard bank, all at once) — and rotates onto its true heading
# by tweening pitch/yaw/roll as three INDEPENDENT Euler axes (see
# _play_departure_maneuver for why — a single quaternion slerp between the
# two orientations was tried first and looked like a pure yaw, since its
# one combined rotation axis gets dominated by whichever component has the
# largest swing). MANEUVER_TIME is long enough to read as controlled at
# this larger swing (not frantic) and to give AudioManager.engine_power_up()
# (fired right as it starts) room to play out. The ship also holds
# position entirely still until this finishes (see _process) — starting to
# move concurrently with the reorientation undercut the "orient first, then
# go" the maneuver is supposed to sell.
const DEPARTURE_MANEUVER_TIME := TravelCalc.DEPARTURE_HOLD_SECONDS  # single-sourced — TravelCalc.current_speed_km_s (the console's live speed readout) needs to hold at 0 for exactly as long as the ship visually holds still here, or the two would disagree
const DEPARTURE_YAW_RANGE := Vector2(120.0, 165.0)  # degrees off heading, magnitude range (sign randomized) — target starts behind/to one side
const DEPARTURE_PITCH_RANGE := 35.0                 # degrees off heading, +/- — target starts noticeably above or below too
const DEPARTURE_ROLL_RANGE := 45.0                  # degrees of bank — a real "rolling out of a turn" cue, not a light tilt
const DEPARTURE_SKIP_AFTER := 0.5                   # trips older than this are a mid-trip re-entry, not a departure — see _build_transit

var _sun: DirectionalLight3D
var _camera: Camera3D
var _primary: Node3D
var _secondaries: Array[Node3D] = []             # background dressing at the arrived-at body — see _secondary_entries_for: every real moon of a planet, or just the parent if orbiting a moon
var _secondary_is_universe_body: Array[bool] = []  # parallel to _secondaries
var _primary_is_universe_body := false    # avoids double-spinning a body that's both _primary/_secondary AND in _universe_bodies (which all spin every frame regardless — see _process)

var _universe_bodies: Dictionary = {}     # body_name -> Node3D — Sol + all 9 planets, persistent for the whole scene's life
var _universe_positions: Dictionary = {}  # body_name -> Vector3 — ditto, positions only (also used before a body's node exists, e.g. while computing a moon's anchor)
var _sol_position := Vector3.ZERO         # cached from _build_universe — needed every time _point_sun_at re-aims the light

var _transit_body: Node3D              # only ever set when the DESTINATION is a moon (ad hoc, not persistent) — null for a planet/Sol destination, which is already alive in _universe_bodies
var _transit_start_pos := Vector3.ZERO # an entry point near wherever we're departing FROM
var _transit_end_pos := Vector3.ZERO   # an entry point near the destination — NOT the same as the destination's own position, see _transit_target_anchor
var _transit_target_anchor := Vector3.ZERO  # the destination body's own real position — what the camera actually looks toward, and what orbiting/leaning circles once arrived
var _transit_target_radius := 0.0
var _in_transit := false
var _hidden_from_body: Node3D  # the departure body, hidden for the duration of the trip — see _build_transit/_build_arrival
var _pre_swing_lead := 0.0        # per-trip, set in _build_transit — see the class comment above ORBIT_SETTLE_DURATION for why this isn't a flat constant
var _total_lean_duration := 0.0   # = _pre_swing_lead + ORBIT_SETTLE_DURATION, also set in _build_transit

var _primary_display_radius := 0.0
var _orbit_angle := randf_range(0.0, TAU)  # start partway around the loop, not always fresh at 0
var _camera_base_forward := Vector3.FORWARD  # fixed reference direction the whole universe layout is seeded from — see _build_universe/_seeded_direction

var _settling := false          # true from arrival until the lean finishes — still distinct from _lean_started, which can go true earlier, mid-flight
var _lean_started := false      # whether the lean-into-orbit curve has been seeded yet this trip (reset per _build_transit)
var _lean_elapsed := 0.0        # continuous across the pre-arrival lean AND the post-arrival settle — never reset at arrival, see _total_lean_duration
var _lean_from_pos := Vector3.ZERO    # camera's actual position/orientation at the moment the lean started — captured dynamically (the camera genuinely moves now, unlike the old fixed-at-origin transit), not a fixed constant
var _lean_from_basis := Basis.IDENTITY

var _sun_lean_from_dir := Vector3.ZERO  # sun direction (Sol -> lit body) at the moment the lean started — see _apply_lean's sun blend, and the class comment above _point_sun_at
var _sun_lean_to_pos := Vector3.ZERO    # position the sun should be aimed at once the lean finishes


func _ready() -> void:
	_build_environment()
	_build_universe()
	if PlayerState.is_traveling:
		_build_transit()
	else:
		# Fresh scene load, nothing to blend from — snap straight to orbit.
		_build_arrival(PlayerState.location_id)
		_update_orbit_camera()
	PlayerState.travel_completed.connect(_on_travel_completed)


func _process(delta: float) -> void:
	# Sol + every planet are always alive in the world, spinning gently,
	# regardless of transit/orbit state — see class comment.
	for body: Node3D in _universe_bodies.values():
		body.rotate_y(SPIN * delta)

	if _in_transit:
		if _transit_body != null:
			_transit_body.rotate_y(SPIN * delta)

		# Held at the start point entirely until the departure maneuver
		# (DEPARTURE_MANEUVER_TIME) actually finishes, THEN eases into
		# forward motion — see DEPARTURE_MANEUVER_TIME above. Progress is
		# remapped over the remaining time so the two phases run
		# sequentially in real time, but both formulas agree at
		# elapsed == travel_duration, so this doesn't shift when the trip
		# actually completes.
		var hold_duration := DEPARTURE_MANEUVER_TIME
		var approach_elapsed := maxf(PlayerState.travel_elapsed - hold_duration, 0.0)

		# Position curve is TravelCalc's flight_progress() directly — the same
		# function current_speed_km_s/ship_status read for the HUD, so the
		# camera's actual motion and the readout are provably the same thing,
		# not two formulas that have to be kept in sync by hand.
		var progress := TravelCalc.flight_progress(
				PlayerState.travel_distance_km, approach_elapsed, PlayerState.travel_accel_multiplier)

		# Position (and, once past the hold, orientation) are recomputed
		# fresh from PlayerState every frame — not carried over from
		# whatever a PREVIOUS Cockpit instance had, which is long gone by
		# the time you re-enter mid-trip after visiting another view. This
		# is what makes a mid-trip re-entry land in the geometrically
		# correct spot instead of resetting to the start.
		_camera.position = _transit_start_pos.lerp(_transit_end_pos, progress)

		# Sun direction slews across the whole flight using this SAME
		# `progress` fraction — see the comment on _sun_lean_from_dir/
		# _sun_lean_to_pos in _build_transit for why this replaced blending
		# only during the tail-end lean.
		if _sun != null:
			var sun_target_dir := (_sun_lean_to_pos - _sol_position).normalized()
			var blended_sun_dir := _sun_lean_from_dir.lerp(sun_target_dir, progress)
			if blended_sun_dir.length() > 0.01:
				_apply_sun_dir(blended_sun_dir)

		if PlayerState.travel_elapsed >= hold_duration:
			var to_target := _transit_target_anchor - _camera.position
			if to_target.length() > 0.01:
				_camera.transform.basis = Basis.looking_at(to_target.normalized(), Vector3.UP)
		# else: still mid-departure-maneuver — that tween owns rotation
		# this frame (see _play_departure_maneuver); only position is set
		# above, which the tween never touches.

		# Final-approach lean — see _pre_swing_lead/_total_lean_duration above.
		# Crucially, _lean_from_pos/_lean_from_basis are NOT a one-time
		# snapshot frozen at the moment the lean starts — they're
		# overwritten every frame with wherever the flight formula ABOVE
		# actually put the camera this frame, for as long as we're still
		# genuinely in flight. That's what makes the reorientation blend in
		# WHILE STILL MOVING rather than from a dead stop: at the exact
		# instant the lean begins (eased_t = 0, zero blend-derivative), the
		# displayed position/orientation is 100% the live, still-moving
		# flight value, and only gradually swings toward the orbit pose as
		# eased_t rises — a true crossfade, not a stop-then-go. This only
		# ever stops updating once the trip actually ends (_settling takes
		# over below and this branch no longer runs) — safe to freeze there
		# because the approach above always glides to zero velocity right at
		# that exact instant anyway, so there's essentially nothing left to
		# lose by holding still from that point on.
		var remaining := PlayerState.travel_remaining()
		if remaining <= _pre_swing_lead:
			if not _lean_started:
				_lean_started = true
				_lean_elapsed = 0.0
				var current_offset := _camera.position - _transit_target_anchor
				var untilted := current_offset.rotated(Vector3.RIGHT, -deg_to_rad(ORBIT_TILT_DEG))
				_orbit_angle = atan2(untilted.z, untilted.x)
			_lean_from_pos = _camera.position
			_lean_from_basis = _camera.transform.basis
			_apply_lean(delta, _transit_target_anchor, _transit_target_radius)
		return

	if _settling:
		_apply_lean(delta, _primary.position, _primary_display_radius)
		if _primary != null and not _primary_is_universe_body:
			_primary.rotate_y(SPIN * delta)
		for i in _secondaries.size():
			if not _secondary_is_universe_body[i]:
				_secondaries[i].rotate_y(SPIN * 0.5 * delta)
		if _lean_elapsed >= _total_lean_duration:
			_settling = false
		return

	if _primary != null:
		if not _primary_is_universe_body:
			_primary.rotate_y(SPIN * delta)
		_orbit_angle += ORBIT_ANGULAR_SPEED * delta
		_update_orbit_camera()
	for i in _secondaries.size():
		if not _secondary_is_universe_body[i]:
			_secondaries[i].rotate_y(SPIN * 0.5 * delta)


# --- Environment ---

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.005, 0.007, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.10, 0.12, 0.18)
	env.ambient_light_energy = 0.6

	# Bloom — so Sol (and any other self_luminous body) reads as a genuine
	# blinding light source, not just a bright sphere. ADDITIVE blend and a
	# fairly high HDR threshold keep it from washing out lit planet surfaces
	# (which stay well under 1.0) while still letting Sol's boosted emission
	# (see sol_params.emission_energy in _build_universe) bloom hard.
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_intensity = 1.1
	env.glow_bloom = 0.25
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.96, 0.88)
	_sun.light_energy = 1.3
	add_child(_sun)
	# Rotation finalized in _build_universe, once Sol's real position is
	# known — pointed FROM there so the visible sun and the actual shading
	# agree, rather than a fixed guessed direction.

	# Faint cool fill so a body's night side reads as a silhouette, not a void.
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.5, 0.6, 0.9)
	fill.light_energy = 0.12
	fill.rotation_degrees = Vector3(15, -120, 0)
	add_child(fill)

	# Starting pose only — the whole camera transform gets driven every
	# frame from here on (orbit camera once arrived, flight lerp + look_at
	# during transit). Narrower than Godot's 75° default — at close
	# distances that default reads as an extreme fisheye bulge rather than
	# a majestic orbital view.
	_camera = Camera3D.new()
	_camera.fov = 60.0
	# Real linear AU scale (see PLANET_DIST_AU_TO_UNITS) puts Earth-to-Sol at
	# ~52,500 units — comfortably covers Sol from any inner/mid planet
	# (through Jupiter) without pushing all the way out to Neptune's ~1.6M-
	# unit Sol distance, which would be a wasted, invisible-anyway frustum.
	# Sol genuinely dropping out of view from the outer planets, the same way
	# it does in reality, is correct here, not a bug to fix.
	_camera.far = 300000.0
	_camera.rotation_degrees = Vector3(-3, 8, 0)
	add_child(_camera)
	# Read back the actual computed forward direction (rather than
	# hand-deriving it from the Euler angles, which risks a rotation-order
	# mismatch) — this is the one fixed reference direction the whole
	# universe layout is seeded from (see _build_universe).
	_camera_base_forward = -_camera.global_transform.basis.z

	var stars := StarfieldStars.new()
	stars.follow = _camera
	add_child(stars)


# --- Universe (Sol + all planets, persistent for the scene's whole life) ---

func _build_universe() -> void:
	var sol_entry := KnownBodies.sol()
	var sol_pos := _camera_base_forward * SOL_DISTANCE
	_sol_position = sol_pos
	_universe_positions[sol_entry.body_name] = sol_pos
	var sol_display_radius := sol_entry.real_radius_km * KM_TO_UNITS
	var sol_params := sol_entry.to_params(sol_display_radius)
	# KnownBodies' emission_energy (1.5) is tuned for Cosmic Forge's plain
	# viewer — barely above env.glow_hdr_threshold there, so bloom would be
	# nearly invisible. Cockpit wants Sol to actually blow out, so it gets
	# its own much higher figure here, same spirit as Earth's atmosphere
	# override just below.
	sol_params.emission_energy = 8.0
	var sol_body := CanonicalBodyGenerator.generate(sol_params)
	sol_body.position = sol_pos
	sol_body.rotation.y = randf_range(0.0, TAU)
	add_child(sol_body)
	_universe_bodies[sol_entry.body_name] = sol_body

	for entry: KnownBodies.Entry in KnownBodies.planets():
		var dir := _seeded_direction(entry.body_name, PLANET_CONE_DEG)
		var dist := entry.au_distance * PLANET_DIST_AU_TO_UNITS
		var pos := sol_pos + dir * dist
		_universe_positions[entry.body_name] = pos

		var radius := _primary_radius_for(entry)
		var params := entry.to_params(radius)
		if entry.body_name == "Earth":
			params.atmosphere = 0.20
			params.atmo_falloff = 3.0
		var body := CanonicalBodyGenerator.generate(params)
		body.position = pos
		body.rotation.y = randf_range(0.0, TAU)
		add_child(body)
		_universe_bodies[entry.body_name] = body

	# Initial guess only — Earth is the default starting body (see class
	# comment), but whichever body is actually arrived at overrides this
	# properly in _build_arrival, once _primary is known. Aiming at Earth's
	# real position here (rather than the world origin, which is nowhere
	# near any body once PLANET_DIST_* pushed everything thousands of units
	# out) keeps the visible Sol disc and the lit hemisphere in agreement
	# even during the one frame before _build_arrival runs.
	_point_sun_at(_universe_positions.get("Earth", Vector3.ZERO))


# Aims the sun FROM its real position along the given direction, then
# refreshes every atmosphere shader's cached sun_dir to match — both need to
# move together whenever the lit direction changes, or the visible Sol disc
# and the terminator/shading on a body (e.g. Earth's) will disagree about
# where "the light side" is. The primitive both _point_sun_at (instant snap
# to face a position) and _apply_lean's sun blend (gradual slew between two
# directions, see _sun_lean_from_dir) funnel through, so there's exactly one
# place that actually writes the sun's transform and the shader uniforms.
func _apply_sun_dir(dir: Vector3) -> void:
	if _sun == null:
		return
	_sun.position = _sol_position
	if dir.length() > 0.01:
		_sun.look_at(_sol_position + dir, Vector3.UP)
	var sun_dir := _sun.global_basis.z
	for body: Node3D in _universe_bodies.values():
		var atmo := body.get_node_or_null("Atmosphere") as MeshInstance3D
		if atmo != null:
			(atmo.material_override as ShaderMaterial).set_shader_parameter("sun_dir", sun_dir)
	if _primary != null and not _primary_is_universe_body:
		var primary_atmo := _primary.get_node_or_null("Atmosphere") as MeshInstance3D
		if primary_atmo != null:
			(primary_atmo.material_override as ShaderMaterial).set_shader_parameter("sun_dir", sun_dir)


# Instantly faces the sun at whatever body is actually being lit right now
# (normally _primary) — only safe to call when nothing should be visibly
# slewing (a cold scene load, or the one-frame placeholder in
# _build_universe before _build_arrival knows the real body). A trip arrival
# must NOT snap this way — see _build_arrival's own comment, and
# _apply_lean's gradual blend, which is what actually keeps the lit
# direction from popping the instant a trip completes.
func _point_sun_at(target_pos: Vector3) -> void:
	if _sun == null:
		return
	var to_target := target_pos - _sol_position
	if to_target.length() > 0.01:
		_apply_sun_dir(to_target.normalized())


# A stable-but-arbitrary direction within `cone_deg` of _camera_base_forward
# — seeded off the body's name (same determinism trick
# PlanetarySystemView._build_moon_body already uses for procedural moon
# variety), so a planet lands in the same spot every session instead of
# reshuffling on every load. Kept within a cone of the reference direction
# (not fully random over the sphere) so nothing ends up surprising-close
# behind the camera — everything reads as "generally out there," scattered.
#
# Deliberately NOT a symmetric cone (an earlier version mixed `right` and
# `up` evenly via a single `spin`/`spread` pair) — that routinely placed a
# body 30-40° above/below the shared plane, so a straight-line GO trip
# to/from it arrived steep, near a pole, rather than near the equator (see
# the Cockpit orbit-orientation memory). Real solar systems are a nearly
# flat disc: wide variation in azimuth (where a body sits "around" the
# cone axis), only mild variation in inclination (how far off the shared
# plane). Splitting those two — wide azimuth around `up`, narrow incline
# around `right`, capped at PLANE_INCLINATION_DEG rather than the full
# cone_deg — keeps every body close to the ONE shared plane the arrival
# orbit ring (ORBIT_TILT_DEG) itself uses, so approaches land close to
# equatorial by construction instead of needing a dramatic post-arrival
# reorientation.
func _seeded_direction(body_name: String, cone_deg: float) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = body_name.hash()
	var right := _camera_base_forward.cross(Vector3.UP)
	if right.length() < 0.01:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(_camera_base_forward).normalized()
	var azimuth := deg_to_rad(rng.randf_range(-cone_deg, cone_deg))
	var incline := deg_to_rad(rng.randf_range(-PLANE_INCLINATION_DEG, PLANE_INCLINATION_DEG))
	var dir := _camera_base_forward.rotated(up, azimuth)
	dir = dir.rotated(right, incline)
	return dir.normalized()


# --- Moons (never persistent — spawned ad hoc, anchored near their real parent) ---

func _moon_anchor_pos(entry: KnownBodies.Entry) -> Vector3:
	var parent_pos: Vector3 = _universe_positions.get(entry.parent, _camera_base_forward * SOL_DISTANCE)
	# Real distance from parent (same KM_TO_UNITS scale everything else in
	# this file uses — see _build_universe/Sol), not a single shared
	# constant — otherwise every moon of a planet would sit at the exact
	# same distance in a random direction instead of actually spreading out
	# the way Saturn's seven curated moons really do (Mimas close in,
	# Iapetus over 3.5 million km out). MOON_ANCHOR_DIST is only a fallback
	# for the unlikely case an entry is missing real data.
	var dist := entry.parent_distance_km * KM_TO_UNITS if entry.parent_distance_km > 0.0 else MOON_ANCHOR_DIST

	# Real distance alone isn't safe to use as-is: Phobos/Deimos really do
	# orbit only a few thousand km from Mars — closer, in real terms, than
	# the Moon is to Earth relative to Earth's own size — and Mars' STYLIZED
	# display radius/camera-orbit-shell here are compressed, not to scale.
	# Scaled real distance alone can land a moon inside (or barely outside)
	# the camera's own orbit around the parent, so it fills the screen
	# instead of sitting "in the distance." Floor it at a clearance derived
	# from the parent's actual orbit shell — this only ever pulls in
	# genuinely-close real moons (Phobos/Deimos); anything already
	# comfortably far (every Saturn/Jupiter/Uranus moon here) is untouched,
	# so their real relative spread is preserved.
	var parent_entry := KnownBodies.get_entry(entry.parent)
	if parent_entry != null:
		var min_clear := _primary_radius_for(parent_entry) * ORBIT_RADIUS_MULT + _primary_radius_for(entry) + MOON_MIN_CLEARANCE
		dist = maxf(dist, min_clear)

	return parent_pos + _seeded_direction(entry.body_name, MOON_ANCHOR_CONE_DEG) * dist


# Position of ANY body, real or moon, WITHOUT spawning anything — used for
# where we're departing FROM (which never needs its own node during transit).
func _body_anchor_pos(entry: KnownBodies.Entry) -> Vector3:
	if _universe_positions.has(entry.body_name):
		return _universe_positions[entry.body_name]
	return _moon_anchor_pos(entry)


func _spawn_moon_body(entry: KnownBodies.Entry) -> Node3D:
	var radius := _primary_radius_for(entry)
	var body := _generate_body(entry, radius)
	body.position = _moon_anchor_pos(entry)
	body.rotation.y = randf_range(0.0, TAU)
	add_child(body)
	var atmo := body.get_node_or_null("Atmosphere") as MeshInstance3D
	if atmo != null:
		(atmo.material_override as ShaderMaterial).set_shader_parameter("sun_dir", _sun.global_basis.z)
	return body


# Luna (and every planet/Sol) has real photographic art and renders through
# CanonicalBodyGenerator; every other real moon here (Phobos through Hydra —
# see Entry.use_canonical_art in KnownBodies) has no texture at all and must
# go through MoonGenerator instead, same as PlanetarySystemView._build_moon_body
# — using CanonicalBodyGenerator for those looks like a flat, untextured ball
# (it was silently falling back to fallback_color/Color.WHITE, since
# texture_subdir is only ever set for canonical-art entries).
func _generate_body(entry: KnownBodies.Entry, radius: float) -> Node3D:
	if entry.use_canonical_art:
		return CanonicalBodyGenerator.generate(entry.to_params(radius))
	var rng := RandomNumberGenerator.new()
	rng.seed = entry.body_name.hash()
	var params := MoonParams.new()
	params.seed_value = entry.body_name.hash()
	params.radius = radius
	params.surface_roughness = rng.randf_range(0.01, 0.04)
	params.crater_density = rng.randf_range(0.25, 0.85)
	params.crater_size = rng.randf_range(0.10, 0.28)
	params.crater_depth = rng.randf_range(0.03, 0.08)
	params.detail = 4
	var body := MoonGenerator.generate(params)
	body.name = entry.body_name
	return body


# --- Arrival ---

func _build_arrival(location_id: String) -> void:
	var was_in_transit := _in_transit  # see the _point_sun_at call below
	_in_transit = false
	var entry := KnownBodies.get_entry(location_id)
	if entry == null:
		entry = KnownBodies.get_entry("Earth")
		location_id = "Earth"

	_primary_display_radius = _primary_radius_for(entry)

	if _universe_bodies.has(location_id):
		_primary = _universe_bodies[location_id]
		_primary_is_universe_body = true
	else:
		# A moon — reuse the node _build_transit already spawned for this
		# trip if there is one (same object the whole flight, no swap —
		# what used to be a "reuse_body" hand-off is now just "it was
		# already real the entire time"); otherwise (a cold load straight
		# into a moon) spawn fresh.
		_primary = _transit_body if _transit_body != null else _spawn_moon_body(entry)
		_primary_is_universe_body = false
	_transit_body = null  # bookkeeping only — if it was just claimed as _primary above, the node itself lives on
	# Snap the sun instantly only on a genuine cold load (nothing was
	# animating to begin with, so there's nothing to pop). A trip arrival
	# must NOT snap here — the lighting direction has already been slewing
	# smoothly toward this exact position across the whole flight (see
	# _sun_lean_from_dir/_sun_lean_to_pos, seeded in _build_transit, applied
	# every frame in _process's _in_transit branch) — an instant snap here
	# would only reintroduce the pop this mechanism exists to avoid.
	if not was_in_transit:
		_point_sun_at(_primary.position)

	if _hidden_from_body != null:  # see _build_transit — reveal the departure body now that orbit is safely established at the destination
		_hidden_from_body.visible = true
		_hidden_from_body = null

	_secondaries.clear()
	_secondary_is_universe_body.clear()
	for secondary_entry: KnownBodies.Entry in _secondary_entries_for(entry):
		if _universe_bodies.has(secondary_entry.body_name):
			_secondaries.append(_universe_bodies[secondary_entry.body_name])
			_secondary_is_universe_body.append(true)
		else:
			_secondaries.append(_spawn_moon_body(secondary_entry))
			_secondary_is_universe_body.append(false)

	HUD.set_view("%s Orbit" % location_id, "cockpit")
	# Only track that exists yet — see the "no location system" gap this
	# leaves for every other destination, same spirit as the rest of this
	# file's "artistic compromise, not complete" comments.
	if location_id == "Earth":
		MusicManager.play_earth_orbit()

	# Camera positioning is the caller's job — a fresh load snaps straight
	# to orbit (_ready), while arriving from a trip blends into it
	# (_on_travel_completed → _begin_orbit_settle) instead of popping.


# Circles the camera around the primary body's fixed position, facing the
# direction of travel (tangent to the orbit) rather than nose-first at the
# body — see the ORBIT_* constants above for why. This is what actually
# reads as "flying an orbit" rather than "parked in front of a spinning
# planet" or "staring straight at it the whole way around."
func _update_orbit_camera() -> void:
	if _camera == null or _primary == null:
		return
	_camera.transform = _orbit_pose(_orbit_angle, _primary.position, _primary_display_radius)


# Pure function: the camera transform for a given point on the orbit around
# the given anchor/radius, with no side effects — shared by
# _update_orbit_camera (continuous per-frame orbiting) and _apply_lean
# (blended orbiting, both pre- and post-arrival).
func _orbit_pose(angle: float, anchor: Vector3, radius: float) -> Transform3D:
	var orbit_radius := radius * ORBIT_RADIUS_MULT

	# Position: standard tilted circle around the body.
	var flat := Vector3(cos(angle), 0.0, sin(angle)) * orbit_radius
	var offset := flat.rotated(Vector3.RIGHT, deg_to_rad(ORBIT_TILT_DEG))
	var camera_pos := anchor + offset

	# Orientation: built from two vectors that are always perpendicular by
	# construction (velocity is tangent to the circle, the body direction is
	# radial) rather than via look_at, so we can precisely place the body at
	# a chosen angle off-axis instead of dead-center.
	#   forward0 = direction of travel (pure tangent, 90° off the body — see
	#              ORBIT_GLANCE_DEG above for why that alone isn't enough).
	#   right0   = radially outward (away from the body).
	# Blending forward0 toward -right0 (the body's direction) by
	# ORBIT_GLANCE_DEG, and right0 by the same angle in lockstep, rotates
	# the pair together within their shared plane — they stay exactly
	# perpendicular for any blend amount, no renormalization needed.
	# NOTE: this is the retrograde (angle-decreasing) tangent, not the
	# prograde d/dangle of `flat` — using the prograde tangent here (as an
	# earlier version did) leaves `right` and `backward` mutually
	# perpendicular but forces `up = backward.cross(right)` to always land
	# pointing world-DOWN for this orbit's TILT/GLANCE values, rendering the
	# whole view rolled 180° ("orbiting upside down" / "arriving at the
	# south pole"). Flipping the tangent's sign only changes which way the
	# camera's nose leads (a pure view-direction/roll choice — the camera's
	# actual physical revolution direction is `angle` itself, driven by
	# ORBIT_ANGULAR_SPEED, and is untouched by this), which both corrects
	# `up` cleanly and reverses the apparent on-screen spin direction (was
	# clockwise, now counterclockwise) — it does NOT affect which side of
	# the screen the body glances into, since that only depends on `right`'s
	# right0 component (see `right` below), which this doesn't touch.
	var flat_tangent := Vector3(sin(angle), 0.0, -cos(angle))
	var forward0 := flat_tangent.rotated(Vector3.RIGHT, deg_to_rad(ORBIT_TILT_DEG)).normalized()
	var right0 := offset.normalized()
	var glance := deg_to_rad(ORBIT_GLANCE_DEG)
	var forward := forward0 * cos(glance) - right0 * sin(glance)
	var right := right0 * cos(glance) + forward0 * sin(glance)
	var backward := -forward
	var up := backward.cross(right)
	return Transform3D(Basis(right, up, backward), camera_pos)


# Shared by the pre-arrival lean (_in_transit branch, once within
# _pre_swing_lead of arrival) and the post-arrival settle (_settling
# branch) — advances the ONE continuous _lean_elapsed/_orbit_angle pair
# and blends the camera from wherever it was when the lean started
# (_lean_from_pos/_lean_from_basis — captured dynamically, see _process)
# toward a live-recomputed orbit pose around whatever anchor/radius the
# caller passes. One continuous curve is the whole point (see
# _total_lean_duration) — this never resets mid-lean.
func _apply_lean(delta: float, anchor: Vector3, radius: float) -> void:
	_lean_elapsed += delta
	var t := clampf(_lean_elapsed / _total_lean_duration, 0.0, 1.0)
	# NEITHER smoothstep NOR a pure ease-out curve — both were tried and
	# both are wrong for this, for opposite reasons:
	#   - smoothstep (3t^2-2t^3) has ZERO derivative at t=0 — the camera
	#     visibly stalled/hesitated for a beat before the turn picked up.
	#   - a pure ease-out (sine or cubic) swung the other way: "ease-out" is
	#     DEFINED by having its MAXIMUM velocity at t=0, decelerating the
	#     whole rest of the way — so the turn's fastest instant is always
	#     its very first one, which reads as a jolt/snap right at the start,
	#     no matter how gentle the ease-out variant (sine's peak-at-start is
	#     merely less extreme than cubic's, not actually different in kind).
	# What's actually wanted is smoothstep's HUMP shape (velocity builds to
	# a peak around the midpoint, eases off at both ends — no jolt) but
	# without the exact zero at the ends — a small blend of pure-linear
	# motion into smoothstep keeps that hump while giving both ends a
	# small-but-real running start/landing speed instead of a dead stop.
	var smooth := t * t * (3.0 - 2.0 * t)
	var eased_t: float = lerp(t, smooth, 0.85)  # lerp() is generic (float/Vector2/Vector3/Color) so its return is Variant — := can't infer a concrete type from it
	_orbit_angle += ORBIT_ANGULAR_SPEED * eased_t * delta
	var target := _orbit_pose(_orbit_angle, anchor, radius)
	var pos := _lean_from_pos.lerp(target.origin, eased_t)
	var rot := Quaternion(_lean_from_basis).slerp(Quaternion(target.basis), eased_t)
	_camera.transform = Transform3D(Basis(rot), pos)
	# Sun direction is NOT blended here — see _build_transit/_process, which
	# now slew it across the whole flight instead of just this tail-end
	# window (an earlier version did it here; crammed into a few seconds
	# right at insertion, it visibly fought the camera's own reorientation
	# and read as the lighting flipping, then flipping back). By the time
	# this runs, the whole-trip blend has already brought it to (or
	# essentially to) the destination's true direction.


# Flips on the post-arrival half of the lean. Normally the pre-arrival half
# (_in_transit branch, above) has already been running for _pre_swing_lead
# seconds by now — comfortably shorter than any real trip's duration — so
# this is usually just _settling = true. The _lean_started guard is a
# fallback for the unlikely case it somehow didn't.
func _begin_orbit_settle() -> void:
	if _camera == null or _primary == null:
		return
	if not _lean_started:
		_lean_from_pos = _camera.position
		_lean_from_basis = _camera.transform.basis
		var current_offset := _camera.position - _primary.position
		var untilted := current_offset.rotated(Vector3.RIGHT, -deg_to_rad(ORBIT_TILT_DEG))
		_orbit_angle = atan2(untilted.z, untilted.x)
		_lean_elapsed = 0.0
		_lean_started = true
	_settling = true


func _primary_radius_for(entry: KnownBodies.Entry) -> float:
	match entry.body_name:
		"Earth": return EARTH_RADIUS
		"Luna": return LUNA_RADIUS
		_: return clampf(2.0 + 3.0 * sqrt(entry.radius_ratio), 1.5, 8.0)


# Background dressing for the arrived-at body: orbiting a moon shows just
# its (real, always-persistent) parent planet; orbiting a planet shows EVERY
# one of its real curated moons, not just the nearest — from Saturn you
# should see all seven, not a single arbitrarily-picked one.
func _secondary_entries_for(entry: KnownBodies.Entry) -> Array[KnownBodies.Entry]:
	if entry.parent != "":
		var parent_entry := KnownBodies.get_entry(entry.parent)
		return [parent_entry] if parent_entry != null else []
	return KnownBodies.moons_of(entry.body_name)


# --- Transit visual ---
# The destination is the real object the whole time — either already alive
# in _universe_bodies (a planet/Sol), or spawned once here and anchored to
# its real parent position (a moon, kept in _transit_body) — so there's
# nothing to swap on arrival, and it naturally grows larger as the camera
# actually approaches through the exact same space every other body lives
# in. Cockpit is rebuilt from scratch every time this scene loads, including
# re-entering it mid-trip after visiting another view (PlayerState itself
# just keeps ticking regardless) — everything here is recomputed fresh from
# PlayerState/the universe layout each time, which is also what makes a
# mid-trip re-entry land in the correct spot rather than resetting (see the
# _process comment on _camera.position). The departure maneuver only makes
# sense as a one-time "leaving orbit" flourish though, so
# DEPARTURE_SKIP_AFTER gates IT specifically to genuine trip starts.

func _build_transit() -> void:
	_in_transit = true
	# Just a location-ish readout, same role _view_label always plays — NOT
	# a status message anymore (see ConsolePanel's always-on ship-status
	# strip, TravelCalc.ship_status, for "Orienting to Target"/"Acceleration
	# Burn"/etc.). Stays fixed for the whole trip; no more swapping between
	# different phase text up here.
	HUD.set_view("En Route to %s" % PlayerState.travel_target_id.to_upper(), "cockpit")

	_pre_swing_lead = TravelCalc.pre_arrival_lead_seconds(PlayerState.travel_duration)
	_total_lean_duration = _pre_swing_lead + ORBIT_SETTLE_DURATION

	var target_id := PlayerState.travel_target_id
	var from_id := PlayerState.location_id
	var entry := KnownBodies.get_entry(target_id)
	var from_entry := KnownBodies.get_entry(from_id)

	if entry != null and from_entry != null:
		var end_body: Node3D
		if _universe_bodies.has(target_id):
			end_body = _universe_bodies[target_id]
		else:
			end_body = _spawn_moon_body(entry)
			_transit_body = end_body

		var from_pos := _body_anchor_pos(from_entry)
		var end_pos := end_body.position
		var travel_dir := end_pos - from_pos
		var travel_dir_n := travel_dir.normalized() if travel_dir.length() > 0.01 else _camera_base_forward
		var from_radius := _primary_radius_for(from_entry)
		var end_radius := _primary_radius_for(entry)

		# The entry point sits on the FAR side of the departure body (see
		# _transit_start_pos below) — the straight-line flight to the
		# destination necessarily passes right through the body's own
		# volume on the way out, since we deliberately aren't routing
		# around it (real orbital mechanics would need actual pathfinding
		# for that, not worth it here). Hiding the body for the trip's
		# duration — under full black from the GO fade by the time this
		# runs, see HUD.go_to — sidesteps the problem instead of solving
		# it geometrically; it reappears once orbit around the destination
		# is actually established (_build_arrival), since it may well be
		# visible from there too (e.g. Earth from Moon orbit).
		if _universe_bodies.has(from_id):
			_hidden_from_body = _universe_bodies[from_id]
			_hidden_from_body.visible = false

		# Entry points just outside each body, on the side facing the other
		# — not the bodies' own positions, which is what the camera
		# actually orbits/settles around once arrived.
		_transit_start_pos = from_pos - travel_dir_n * (from_radius * ORBIT_RADIUS_MULT)
		_transit_target_anchor = end_pos
		_transit_target_radius = end_radius
		_transit_end_pos = end_pos - travel_dir_n * (end_radius * ORBIT_RADIUS_MULT)
		_camera.position = _transit_start_pos

		# Sun direction slews across the WHOLE trip (see _process's _in_transit
		# branch), not just the short pre-arrival lean — an earlier version
		# only started this blend at the lean, which meant the sun sat frozen
		# on wherever the PREVIOUS body was for the entire cruise, then had to
		# sweep the whole real gap to the new body crammed into a few seconds
		# right as insertion began — competing with the camera's own
		# reorientation there and reading as the lighting flipping, then
		# flipping again as the two motions fought each other. Spreading it
		# across real travel time instead means it's already essentially at
		# the destination's true direction well before insertion ever starts.
		_sun_lean_from_dir = _sun.global_basis.z if _sun != null else Vector3.ZERO
		_sun_lean_to_pos = end_pos

	# EN ROUTE/ETA/SPEED all live in ConsolePanel's own center-band readout
	# now (see ConsolePanel._refresh_destination_readout/_process) — that's
	# the HUD's one standing "current trip" display, always correctly
	# docked at the bottom-center console regardless of which view is
	# active. This scene used to float a second, separate readout of its
	# own on top of the 3D view; it ended up overlapping the top HUD chrome
	# instead of sitting where every other readout in the game does, so it
	# was removed rather than repositioned — no reason to show the same
	# numbers twice in two different places anyway.
	if PlayerState.travel_elapsed < DEPARTURE_SKIP_AFTER:
		_play_departure_maneuver()
	# else: re-entering an already-in-progress trip — _process recomputes
	# the correct position/orientation from PlayerState every frame anyway,
	# so nothing extra needed here; just don't replay the maneuver.


# Rotates the camera from an arbitrary off-heading orientation onto its
# TRUE heading — facing the real destination, computed from _transit_target_anchor
# (there's no fixed "base pose" to return to anymore, now that the camera
# genuinely moves through real space; facing the real target is the only
# heading that still makes sense here). Deliberately tweens pitch/yaw/roll
# as THREE INDEPENDENT Euler axes (Node3D.rotation, component-wise lerp)
# rather than a single quaternion slerp between the two orientations: slerp
# traces one fixed rotation axis for the whole tween, and since
# DEPARTURE_YAW_RANGE is so much larger than the pitch/roll ranges, that
# combined axis ends up nearly vertical — the roll and pitch get
# mathematically absorbed into "mostly yaw" instead of staying visually
# distinct. Independent per-axis tweening keeps the roll reading as a
# genuine bank and the pitch as a genuine tilt the entire time, layered on
# top of the yaw sweep, not smeared into it. Position never moves here
# (held by _process until this finishes); only orientation changes.
func _play_departure_maneuver() -> void:
	var to_target := _transit_target_anchor - _camera.position
	var target_basis: Basis
	if to_target.length() > 0.01:
		target_basis = Basis.looking_at(to_target.normalized(), Vector3.UP)
	else:
		target_basis = _camera.transform.basis
	var base_euler := target_basis.get_euler()

	var yaw_sign := 1.0 if randf() < 0.5 else -1.0
	var start_euler := base_euler + Vector3(
		deg_to_rad(randf_range(-DEPARTURE_PITCH_RANGE, DEPARTURE_PITCH_RANGE)),
		deg_to_rad(yaw_sign * randf_range(DEPARTURE_YAW_RANGE.x, DEPARTURE_YAW_RANGE.y)),
		deg_to_rad(randf_range(-DEPARTURE_ROLL_RANGE, DEPARTURE_ROLL_RANGE)),
	)
	_camera.rotation = start_euler

	AudioManager.engine_power_up()

	var tw := create_tween()
	tw.tween_property(_camera, "rotation", base_euler, DEPARTURE_MANEUVER_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_travel_completed() -> void:
	if not _in_transit:
		return  # not the active scene when the trip finished — nothing to rebuild
	_build_arrival(PlayerState.location_id)
	_begin_orbit_settle()
	# _build_arrival already set the location readout to "X Orbit" — no
	# separate "performing orbital insertion" override needed anymore, that
	# now lives entirely in ConsolePanel's always-on ship-status strip.


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		HUD.open_system_menu()
