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
# the whole burn+decel flight shape now lives in ONE place —
# TravelCalc.flight_profile()/flight_progress() — and this file's position
# curve just calls flight_progress() directly instead of maintaining its
# own parallel kinematics. See TravelCalc.gd's class comment for the actual
# physics (a symmetric burn to a peak speed, then decelerate at that same
# rate all the way back down to a dead stop at the destination).

const EARTH_RADIUS := 5.5
const LUNA_RADIUS := 4.0

# Moons span a much wider real size range than planets do (Pluto's Styx,
# ~5km, to Ganymede, ~2634km — over 500x) and _primary_radius_for's planet
# formula (sqrt-compressed + a flat +2.0 floor) was swallowing nearly all of
# that: every non-Luna moon landed in a narrow ~2.0-3.9 unit band regardless
# of real size, so Charon barely read bigger than Pluto's other, genuinely
# tiny moons. This scales almost linearly with real radius_ratio instead
# (only a small floor, for bare visibility of an asteroid-sized moon, not a
# big constant that dominates the result) — tuned so MOON_MIN_RADIUS +
# MOON_RADIUS_SCALE * radius_ratio lands close to LUNA_RADIUS at Luna's own
# real radius_ratio, keeping this consistent with Luna's already-established
# fixed size.
const MOON_MIN_RADIUS := 0.6
const MOON_RADIUS_SCALE := 14.0
const MOON_MAX_RADIUS := 4.5
# Asteroids' own display-radius range — deliberately smaller than even
# MOON_MIN_RADIUS above, so the smallest asteroid still reads as clearly
# tinier than the smallest curated moon. See _primary_radius_for's asteroid
# branch — real_radius_km (0.3-20km, see AsteroidResourceGenerator) maps
# linearly onto this range, not real-to-scale.
const ASTEROID_DISPLAY_RADIUS_MIN := 0.15
const ASTEROID_DISPLAY_RADIUS_MAX := 0.5
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

# A/D roll — the only direct ship control the player ever gets. Purely
# cosmetic framing (which side of the screen the body glances into, how the
# horizon sits) while parked in the idle orbit view — see _roll_angle's own
# comment for why it doesn't persist between locations.
const ROLL_SPEED_DEG := 30.0

# How long the camera's reorientation-into-orbit takes — entirely AFTER
# arrival now (see _begin_orbit_settle/_lean_elapsed and
# _on_travel_completed; 2026-07-11: an earlier version started this turn
# mid-decel, blending continuously from the still-moving flight pose into
# the orbit pose specifically to avoid a "stop, THEN restart" seam — that
# was explicitly asked to stop in favor of a real, visible full stop before
# any reorientation begins, which TravelCalc's ARRIVAL_HOLD_SECONDS pause
# now guarantees, so there's no seam left to blend away). Originally 5.5s,
# sized for a near-90° pole-to-equator swing back when _seeded_direction
# scattered bodies in a full symmetric cone (see that function's comment) —
# now that every body's straight-line approach lands close to the shared,
# near-flat orbital plane by construction, the POSITION swing left to play
# out here is small. But the ORIENTATION swing is NOT small even now — raw
# flight looks dead-center at the target (Basis.looking_at), while the
# orbit pose deliberately glances at it off-center (ORBIT_GLANCE_DEG below
# puts the body ~40° off boresight, not centered) — so there's a real ~40°
# turn to cover regardless of how flat the approach is.
#
# Lives in TravelCalc, not here, even though only Cockpit's camera reads it
# directly — ConsolePanel needs the SAME number too (2026-07-11: it used to
# switch its status readout straight from "Orbital Insertion" to "In Orbit"
# the instant PlayerState.travel_completed fired, which is exactly when
# this turn STARTS, not when it finishes — so the label claimed "in orbit"
# for the full ~2.8s the camera was still visibly swinging around). See
# ConsolePanel._on_location_changed, which now holds "Orbital Insertion" for
# this same duration before switching, so the label and the camera agree.
const ORBIT_SETTLE_DURATION := TravelCalc.ORBIT_SETTLE_DURATION

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

# arrival_stop.ogg reads as "cutting power to the engines," not "we have
# stopped" — it needs to land WHILE the ship is still drifting down, this
# far before the decel burn actually finishes, not once flight_progress
# hits a genuine 1.0 (see _process's _in_transit branch).
const ARRIVAL_STOP_LEAD_SECONDS := 1.0

# Floating origin — Godot renders in single-precision floats, and this
# scene's real-scale layout (PLANET_DIST_AU_TO_UNITS) puts Saturn ~500K
# units from the origin (Neptune >1M). A float32's resolution step near
# 500K is ~0.03 units, so camera and vertex positions quantize to a visible
# grid: sub-pixel snapping every frame that reads as jitter/vibration.
# Thin bright ring lines alias hardest (Saturn is where it was actually
# noticed), but body edges shimmer from the same cause; Earth/Mars distances
# (~52-80K units, 4-8x finer steps) merely sat below the visible threshold.
# The fix is the standard space-game one: whenever the camera has drifted
# beyond REBASE_THRESHOLD from the origin, translate the ENTIRE scene so
# the camera is back at zero (see _maybe_rebase_origin). Relative geometry
# is unchanged — every position computation in this file is a difference of
# two positions, so a uniform shift cancels — and precision is only needed
# NEAR the camera: a body a million units away lands on coarse float steps,
# but at that distance it subtends a fraction of a pixel, so its error is
# invisible by construction. At 2048 the ulp is ~0.00024 units, far below
# perception; even a fast interplanetary cruise only rebases a few times a
# second, and each rebase touches only a dozen-odd nodes.
const REBASE_THRESHOLD := 2048.0

var _sun: DirectionalLight3D
var _camera: Camera3D
var _warp_points: WarpPoints
var _activities_panel: ActivitiesPanel  # right-side "what can I do here" panel — see _build_activities_panel
var _transmission_banner: EarthTransmissionBanner  # centered milestone notification — see _build_activities_panel
var _survey_report_panel: SurveyReportPanel  # centered rich survey report (Geological Survey) — see _build_activities_panel
var _transit_peak_speed := 1.0  # set per-trip in _build_transit — current_speed_km_s() normalized against this drives warp point intensity, see _process; 1.0 is just a safe non-zero placeholder before the first trip ever sets a real value
var _transit_burn_duration := 0.0  # set per-trip in _build_transit (flight_profile's t1+t2) — how long the accel+decel burn lasts, used by _process to fire AudioManager.arrival_stop() ARRIVAL_STOP_LEAD_SECONDS before it ends
var _primary: Node3D
var _secondaries: Array[Node3D] = []             # background dressing at the arrived-at body — see _secondary_entries_for: every real moon of a planet, or just the parent if orbiting a moon
var _secondary_is_universe_body: Array[bool] = []  # parallel to _secondaries
var _secondaries_built_for := ""                 # KnownBodies id the current _secondaries set was built for — _build_transit pre-spawns them at trip start, and this is how _build_arrival knows not to spawn a duplicate set on top (see _build_secondaries)
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
var _arrival_stop_played := false  # guards AudioManager.arrival_stop() against firing every frame once progress reaches 1.0 — see _process's _in_transit branch; reset per-trip in _build_transit

var _primary_display_radius := 0.0
var _orbit_angle := randf_range(0.0, TAU)  # start partway around the loop, not always fresh at 0
var _camera_base_forward := Vector3.FORWARD  # fixed reference direction the whole universe layout is seeded from — see _build_universe/_seeded_direction

# User-controlled camera roll around the view axis (A/D), applied only while
# idle in orbit (see _process's _primary-only branch) — purely a preference
# for how the ship happens to be rolled while sightseeing, no gameplay
# effect. Deliberately NOT persisted anywhere (PlayerState, save data, ...)
# and reset to 0 on every fresh arrival (_build_arrival) — the ask was
# explicitly "does not persist... every jump defaults to the current orbit
# setup," i.e. a blank slate each time, not a remembered preference.
var _roll_angle := 0.0

var _settling := false          # true from arrival (PlayerState.travel_completed, see _begin_orbit_settle) until the lean finishes
var _lean_started := false      # whether _lean_from_pos/_lean_from_basis have been seeded yet — guards _begin_orbit_settle against firing twice, see its own comment
var _lean_elapsed := 0.0        # elapsed time within the post-arrival lean — see _begin_orbit_settle/ORBIT_SETTLE_DURATION
var _lean_from_pos := Vector3.ZERO    # camera's actual position/orientation at the moment the lean started — captured dynamically (the camera genuinely moves now, unlike the old fixed-at-origin transit), not a fixed constant
var _lean_from_basis := Basis.IDENTITY

var _sun_lean_from_dir := Vector3.ZERO  # sun direction (Sol -> lit body) at the moment the lean started — see _apply_lean's sun blend, and the class comment above _point_sun_at
var _sun_lean_to_pos := Vector3.ZERO    # position the sun should be aimed at once the lean finishes


func _ready() -> void:
	AmbientManager.play_ship_ambient()
	_build_environment()
	_build_universe()
	_build_activities_panel()
	if PlayerState.is_traveling:
		_build_transit()
	else:
		# Fresh scene load, nothing to blend from — snap straight to orbit.
		# Already "in orbit" from frame one (no settle to wait through, unlike
		# a trip arrival — see _process's _settling branch), so the panel
		# shows immediately here instead of waiting for that event.
		_build_arrival(PlayerState.location_id)
		_update_orbit_camera()
		_activities_panel.refresh()
	PlayerState.travel_completed.connect(_on_travel_completed)


# See REBASE_THRESHOLD's comment for the why. Shifts every Node3D child
# (bodies, camera, sun, starfield — the starfield re-centers itself on the
# camera each frame anyway, so shifting it is merely harmless) AND every
# stored world-position variable, which MUST move together with the nodes
# or the logical state desyncs from the rendered one. Direction-valued
# state (_sun_lean_from_dir, _camera_base_forward, orientations) is
# untouched — directions are position differences, invariant under a
# uniform translation.
func _maybe_rebase_origin() -> void:
	if _camera == null:
		return
	var cam_pos := _camera.position
	if cam_pos.length_squared() < REBASE_THRESHOLD * REBASE_THRESHOLD:
		return
	var shift := -cam_pos
	for child in get_children():
		if child is Node3D:
			(child as Node3D).position += shift
	_sol_position += shift
	for key: String in _universe_positions:
		_universe_positions[key] += shift
	_transit_start_pos += shift
	_transit_end_pos += shift
	_transit_target_anchor += shift
	_lean_from_pos += shift
	_sun_lean_to_pos += shift


func _process(delta: float) -> void:
	# First thing, before any position math this frame — see the function's
	# comment. Everything below is translation-invariant, so it doesn't
	# matter that this may have just moved the whole world.
	_maybe_rebase_origin()

	# Sol + every planet are always alive in the world, spinning gently,
	# regardless of transit/orbit state — see class comment.
	for body: Node3D in _universe_bodies.values():
		body.rotate_y(SPIN * delta)

	if _in_transit:
		if _transit_body != null:
			_transit_body.rotate_y(SPIN * delta)
		# Destination moons are pre-spawned at trip start (see
		# _build_secondaries) — keep them spinning through the flight at the
		# same rate every other state gives them, or their rotation would
		# freeze mid-trip and visibly kick back in at arrival.
		for i in _secondaries.size():
			if not _secondary_is_universe_body[i]:
				_secondaries[i].rotate_y(SPIN * 0.5 * delta)

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
				PlayerState.travel_distance_km, approach_elapsed,
				PlayerState.travel_accel_km_s2, PlayerState.travel_cruise_cap_km_s)

		# "Cutting power to the engines" — fires ARRIVAL_STOP_LEAD_SECONDS
		# before the decel burn actually finishes, i.e. while the ship is
		# still visibly drifting down to rest, not once it's already
		# stopped. Nowhere near PlayerState.travel_completed, which only
		# fires after ARRIVAL_HOLD_SECONDS' full-stop pause on top of that.
		# minf against burn_duration itself covers the rare short/floored
		# trip whose whole burn is shorter than the lead time — fires at
		# the very start of the burn rather than never at all.
		var stop_lead := minf(ARRIVAL_STOP_LEAD_SECONDS, _transit_burn_duration)
		if not _arrival_stop_played and approach_elapsed >= _transit_burn_duration - stop_lead:
			_arrival_stop_played = true
			AudioManager.arrival_stop()
			# The score should start crossfading to the destination's own
			# track at this same "cutting power" moment, not wait for
			# _build_arrival — that only runs once travel_completed fires,
			# well after ARRIVAL_HOLD_SECONDS' full stop on top of this.
			# MusicManager's own _play_from no-ops if this happens to already
			# be playing, so _build_arrival's later call for the cold-load
			# (non-transit) path is still safe to leave as-is.
			var target_entry := KnownBodies.get_entry(PlayerState.travel_target_id)
			if target_entry != null:
				_play_location_music(PlayerState.travel_target_id, target_entry)

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

		# Warp point intensity tracks the same live speed the HUD reads (see
		# class comment on `progress` above) — genuinely zero through the
		# departure hold since motion_elapsed is clamped to 0 there, ramps up
		# through the accel burn, and eases back down to a genuine 0 as the
		# ship decelerates to a full stop (see TravelCalc's class comment) —
		# no separate fade-out override needed, current_speed_km_s already
		# reaches exactly 0 by construction right as the burn ends.
		if _warp_points != null:
			var speed := TravelCalc.current_speed_km_s(
					PlayerState.travel_distance_km, PlayerState.travel_duration,
					PlayerState.travel_elapsed, PlayerState.travel_accel_km_s2, PlayerState.travel_cruise_cap_km_s)
			_warp_points.set_target_warp(speed / _transit_peak_speed)

		if PlayerState.travel_elapsed >= hold_duration:
			var to_target := _transit_target_anchor - _camera.position
			if to_target.length() > 0.01:
				_camera.transform.basis = Basis.looking_at(to_target.normalized(), Vector3.UP)
		# else: still mid-departure-maneuver — that tween owns rotation
		# this frame (see _play_departure_maneuver); only position is set
		# above, which the tween never touches.
		#
		# Nothing else happens once the burn (accel+decel) finishes — the
		# ship just holds here, facing the target, dead still (`progress`
		# above is already clamped to 1.0, so the position/orientation lines
		# above naturally freeze in place) for ARRIVAL_HOLD_SECONDS. See
		# _begin_orbit_settle for the reorientation that follows — it only
		# ever fires once PlayerState.travel_completed does, i.e. once this
		# hold has genuinely elapsed (2026-07-11: turning DURING deceleration,
		# which an earlier version did via a continuous pre/post-arrival
		# blend, was explicitly asked to stop — the ship should visibly
		# come to a complete stop and pause before it starts reorienting).
		return

	if _settling:
		_apply_lean(delta, _primary.position, _primary_display_radius)
		if _primary != null and not _primary_is_universe_body:
			_primary.rotate_y(SPIN * delta)
		for i in _secondaries.size():
			if not _secondary_is_universe_body[i]:
				_secondaries[i].rotate_y(SPIN * 0.5 * delta)
		if _lean_elapsed >= ORBIT_SETTLE_DURATION:
			_settling = false
			_activities_panel.refresh()  # genuinely "in orbit" now — see _build_arrival's comment
		return

	if _primary != null:
		if not _primary_is_universe_body:
			_primary.rotate_y(SPIN * delta)
		_orbit_angle += ORBIT_ANGULAR_SPEED * delta
		# Left/right roll (A/D, or S/F under ESDF — see ControlScheme) — only
		# live here, while genuinely parked in the idle orbit view (not
		# mid-transit, not mid-settle-lean); see _roll_angle's own comment
		# for why this is the only place it moves.
		var roll_input := 0.0
		if ControlScheme.is_right_pressed():
			roll_input -= 1.0
		if ControlScheme.is_left_pressed():
			roll_input += 1.0
		_roll_angle += deg_to_rad(ROLL_SPEED_DEG) * roll_input * delta
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

	_warp_points = WarpPoints.new()
	_warp_points.follow = _camera
	add_child(_warp_points)


# Cockpit-only right-side "what can I do here" panel (Docs/Science and
# Knowledge System - Implementation Roadmap.md, Phase 2), plus the centered
# "Earth Transmission" milestone notification (Phase 3) it can trigger —
# deliberately its own CanvasLayer, not routed through HUD (which is shared
# across every view) or BodyInfoPanel's left-side overlay (a data readout,
# not an action list). Layer 10 matches SystemView's own overlay: above the
# 3D scene, below HUD's own layers. Banner is added after the activities
# panel so it draws on top and intercepts its own DISMISS click.
func _build_activities_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_activities_panel = ActivitiesPanel.new()
	layer.add_child(_activities_panel)
	_transmission_banner = EarthTransmissionBanner.new()
	# Connected to Research directly (not ActivitiesPanel) — a milestone can
	# be granted by anything that calls Research.add_knowledge, not only a
	# RUN SURVEY press (e.g. the F2 Cheat Menu's Science Cheat).
	Research.milestone_reached.connect(_transmission_banner.show_transmission)
	layer.add_child(_transmission_banner)

	_survey_report_panel = SurveyReportPanel.new()
	_activities_panel.geological_report_ready.connect(_survey_report_panel.show_geological_report)
	_activities_panel.resource_report_ready.connect(_survey_report_panel.show_resource_report)
	layer.add_child(_survey_report_panel)


# --- Universe (Sol + all planets, persistent for the scene's whole life) ---

func _build_universe() -> void:
	var sol_entry := KnownBodies.sol()
	var sol_pos := _camera_base_forward * SOL_DISTANCE
	_sol_position = sol_pos
	_universe_positions[sol_entry.body_name] = sol_pos
	var sol_display_radius := _primary_radius_for(sol_entry)
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
		# Building the basis straight from `dir` instead of look_at()'s usual
		# position + dir target avoids float32 precision loss: at real-scale
		# Sol distances, _sol_position's magnitude can swallow a unit-length
		# offset entirely, making the "target" round back to the same point
		# and tripping look_at()'s same-position guard every frame.
		_sun.basis = Basis.looking_at(dir, Vector3.UP)
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


# --- Asteroids (never persistent — spawned ad hoc, anchored to Sol like a
# planet, NOT to a parent like a moon — see KnownBodies._synthesize_
# asteroid_entry, which is what gives entry.au_distance/body_type here) ---

func _asteroid_anchor_pos(entry: KnownBodies.Entry) -> Vector3:
	var dist := entry.au_distance * PLANET_DIST_AU_TO_UNITS
	return _sol_position + _seeded_direction(entry.body_name, PLANET_CONE_DEG) * dist


func _spawn_asteroid_body(entry: KnownBodies.Entry) -> Node3D:
	var radius := _primary_radius_for(entry)
	var body := _generate_body(entry, radius)
	body.position = _asteroid_anchor_pos(entry)
	body.rotation.y = randf_range(0.0, TAU)
	add_child(body)
	return body


# Position of ANY body, real or moon, WITHOUT spawning anything — used for
# where we're departing FROM (which never needs its own node during transit).
func _body_anchor_pos(entry: KnownBodies.Entry) -> Vector3:
	if _universe_positions.has(entry.body_name):
		return _universe_positions[entry.body_name]
	if entry.body_type == "Asteroid":
		return _asteroid_anchor_pos(entry)
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
	if entry.body_type == "Asteroid":
		return _generate_asteroid_body(entry, radius)
	if entry.use_canonical_art:
		return CanonicalBodyGenerator.generate(entry.to_params(radius))
	var rng := RandomNumberGenerator.new()
	rng.seed = entry.body_name.hash()
	var params := MoonParams.new()
	params.seed_value = entry.body_name.hash()
	params.radius = radius
	params.surface_roughness = rng.randf_range(0.01, 0.04)
	params.crater_density = rng.randf_range(0.25, 0.85)
	# crater_size is the MAX radius now (power-law distributed below it, see
	# CraterField.make) — range widened from the old average-semantics
	# (0.10, 0.28) so typical craters stay a similar visible size.
	params.crater_size = rng.randf_range(0.2, 0.5)
	params.crater_depth = rng.randf_range(0.03, 0.08)
	params.detail = 4
	var body := MoonGenerator.generate(params)
	body.name = entry.body_name
	return body


# Same AsteroidGenerator/AsteroidParams SystemView's own map uses, and the
# same tightened knob ranges (see SystemView.gd's ASTEROID_BELT_
# INCLINATION_MAX_DEG-era comment) so an asteroid's LOOK stays consistent
# with what the game has already established, even though this seeds a
# fresh RNG stream independently rather than replaying SystemView's exact
# draw sequence — the same asteroid won't render pixel-identical in both
# views, only similarly-styled, same as this was never a goal for any other
# body's shape either (only Luna keeps true cross-view identical art).
func _generate_asteroid_body(entry: KnownBodies.Entry, radius: float) -> Node3D:
	var seed_hash := entry.body_name.hash()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_hash
	var params := AsteroidParams.new()
	params.seed_value = seed_hash
	params.radius = radius
	params.irregularity = rng.randf_range(0.35, 0.6)
	params.elongation = rng.randf_range(0.15, 0.45)
	params.crater_density = rng.randf_range(0.1, 0.25)
	params.crater_size = rng.randf_range(0.12, 0.25)
	params.crater_depth = rng.randf_range(0.05, 0.1)
	params.detail = 4  # a close-up, one-at-a-time view, unlike SystemView's many-at-once map — affords a bit more detail
	var body := AsteroidGenerator.generate(params)
	body.name = entry.body_name
	return body


# --- Arrival ---

# Per-location score — Luna gets its own track only at Luna itself, Mars
# gets its track anywhere in the Mars system (Mars itself OR either of its
# moons, entry.parent == "Mars"), and everywhere else still falls back to
# Earth Orbit (a placeholder for every other destination — see the rest of
# this file's "artistic compromise, not complete" comments; more
# per-location tracks will replace this fallback over time). Called from
# _process right as arrival_stop plays (the real "arriving here" moment) AND
# from _build_arrival (the cold-load path with no transit) — MusicManager's
# own _play_from no-ops if the right track is already playing, so calling
# this twice for the same arrival is harmless.
func _play_location_music(location_id: String, entry: KnownBodies.Entry) -> void:
	if location_id == "Luna":
		MusicManager.play_the_moon()
	elif location_id == "Mars" or entry.parent == "Mars":
		MusicManager.play_mars()
	else:
		MusicManager.play_earth_orbit()


func _build_arrival(location_id: String) -> void:
	var was_in_transit := _in_transit  # see the _point_sun_at call below
	_in_transit = false
	_roll_angle = 0.0  # every fresh arrival is a blank slate for the player's A/D roll preference — see its own comment
	if _warp_points != null:
		_warp_points.set_target_warp(0.0)
	var entry := KnownBodies.get_entry(location_id)
	if entry == null:
		entry = KnownBodies.get_entry("Earth")
		location_id = "Earth"

	_primary_display_radius = _primary_radius_for(entry)

	if _universe_bodies.has(location_id):
		_primary = _universe_bodies[location_id]
		_primary_is_universe_body = true
	else:
		# A moon or an asteroid — reuse the node _build_transit already
		# spawned for this trip if there is one (same object the whole
		# flight, no swap — what used to be a "reuse_body" hand-off is now
		# just "it was already real the entire time"); otherwise (a cold
		# load straight into one) spawn fresh.
		if _transit_body != null:
			_primary = _transit_body
		elif entry.body_type == "Asteroid":
			_primary = _spawn_asteroid_body(entry)
		else:
			_primary = _spawn_moon_body(entry)
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

	# Normally already built by _build_transit at TRIP START (see
	# _build_secondaries — spawning here at arrival made any moon in visual
	# range pop onto the screen right as orbit settled). Only a genuine cold
	# load, where no transit ever ran, still needs them built here; the
	# guard also prevents stacking duplicate moon nodes on the arrival ones.
	if _secondaries_built_for != location_id:
		_build_secondaries(entry)
		_secondaries_built_for = location_id

	HUD.set_view("%s Orbit" % location_id, "cockpit")
	# Activities panel is NOT refreshed/shown here — a trip arrival still has
	# _begin_orbit_settle's reorientation left to play (see _on_travel_completed);
	# popping the panel up mid-turn read as available before the ship was
	# actually "in orbit." It shows once _process's _settling branch below
	# finishes; the cold-load path (no transit, see _ready) has no settle to
	# wait through, so it shows immediately there instead.
	# Normally already started by _process's arrival_stop trigger, well
	# before this runs (see that call site's own comment) — this call only
	# actually does anything for a genuine cold load straight into a
	# location (_ready with no transit in progress), since MusicManager's
	# _play_from no-ops once the right track is already playing.
	_play_location_music(location_id, entry)

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
	var pose := _orbit_pose(_orbit_angle, _primary.position, _primary_display_radius)
	# A/D roll (_roll_angle) — rotating the whole basis around its own view
	# axis (basis.z, "backward") leaves the view direction untouched and
	# just spins right/up around it, i.e. a pure camera roll layered on top
	# of the orbit pose rather than a second thing fighting it.
	if _roll_angle != 0.0:
		pose.basis = pose.basis.rotated(pose.basis.z.normalized(), _roll_angle)
	_camera.transform = pose


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


# The post-arrival reorientation-into-orbit (_settling branch, kicked off
# by _begin_orbit_settle once PlayerState.travel_completed fires — see its
# comment for why this is the ONLY place the lean ever starts now).
# Advances _lean_elapsed/_orbit_angle and blends the camera from wherever
# it was when the lean started (_lean_from_pos/_lean_from_basis — a
# one-time snapshot, since the ship is already stationary by then) toward
# a live-recomputed orbit pose around whatever anchor/radius the caller
# passes.
func _apply_lean(delta: float, anchor: Vector3, radius: float) -> void:
	_lean_elapsed += delta
	var t := clampf(_lean_elapsed / ORBIT_SETTLE_DURATION, 0.0, 1.0)
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


# Kicks off the ENTIRE reorientation-into-orbit — called once, right when
# PlayerState.travel_completed fires (see _on_travel_completed), which by
# construction only happens once the ship has been sitting fully stopped
# for ARRIVAL_HOLD_SECONDS (see TravelCalc.estimate/ARRIVAL_HOLD_SECONDS).
# Nothing in the _in_transit branch ever starts this early anymore — the
# ship flies straight, comes to a complete stop, pauses, and ONLY THEN
# turns; see the class comment on ORBIT_SETTLE_DURATION and _process's
# _in_transit branch for why (2026-07-11: turning mid-decel, which an
# earlier continuous pre/post-arrival blend did specifically to avoid a
# stop-then-go seam, was explicitly asked to stop — with the ship now
# genuinely at rest before this ever runs, there's no seam to avoid in the
# first place). _lean_started still guards against a double-call.
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
		"Sol": return entry.real_radius_km * KM_TO_UNITS  # real-scale, not the generic planet formula below — see _build_universe's sol_display_radius, which shares this
		"Earth": return EARTH_RADIUS
		"Luna": return LUNA_RADIUS
		_:
			if entry.body_type == "Asteroid":
				# Stylized, NOT real-to-scale like Sol above — a genuinely
				# few-km body rendered at this scene's real-world AU/KM
				# scale would be smaller than a pixel and effectively
				# invisible on arrival. Same "compressed, not to scale"
				# precedent moons already set (see MOON_MIN_RADIUS's own
				# comment) — just a smaller, asteroid-specific range, since
				# these should read as meaningfully tinier than even the
				# smallest curated moon.
				var t := clampf(entry.real_radius_km / AsteroidResourceGenerator.RADIUS_MAX_KM, 0.0, 1.0)
				return lerpf(ASTEROID_DISPLAY_RADIUS_MIN, ASTEROID_DISPLAY_RADIUS_MAX, t)
			if entry.parent != "":  # a moon, not a planet — see MOON_MIN_RADIUS's own comment for why this needs its own curve
				return clampf(MOON_MIN_RADIUS + MOON_RADIUS_SCALE * entry.radius_ratio, MOON_MIN_RADIUS, MOON_MAX_RADIUS)
			return clampf(2.0 + 3.0 * sqrt(entry.radius_ratio), 1.5, 8.0)


# Background dressing for the arrived-at body: orbiting a moon shows just
# its (real, always-persistent) parent planet; orbiting a planet shows EVERY
# one of its real curated moons, not just the nearest — from Saturn you
# should see all seven, not a single arbitrarily-picked one.
func _secondary_entries_for(entry: KnownBodies.Entry) -> Array[KnownBodies.Entry]:
	if entry.parent != "":
		var parent_entry := KnownBodies.get_entry(entry.parent)
		var result: Array[KnownBodies.Entry] = []
		if parent_entry != null:
			result.append(parent_entry)
		return result
	return KnownBodies.moons_of(entry.body_name)


# Builds the _secondaries set for a destination. Called from _build_transit
# at TRIP START — not just from _build_arrival — because moons are anchored
# near their real parent position and grow into view during the approach
# exactly like the destination itself does; when they were only spawned on
# arrival, any moon already in visual range popped onto the screen right as
# orbit settled. Pre-spawning is the same "already real the entire time"
# philosophy the destination body follows (see the transit-visual comment
# block below). The previous _secondaries entries just stop being tracked
# (their nodes live on in the world where they belong — ad-hoc moons are
# anchored dressing, and universe bodies were never Cockpit's to free).
func _build_secondaries(entry: KnownBodies.Entry) -> void:
	_secondaries.clear()
	_secondary_is_universe_body.clear()
	for secondary_entry: KnownBodies.Entry in _secondary_entries_for(entry):
		if _universe_bodies.has(secondary_entry.body_name):
			_secondaries.append(_universe_bodies[secondary_entry.body_name])
			_secondary_is_universe_body.append(true)
		else:
			_secondaries.append(_spawn_moon_body(secondary_entry))
			_secondary_is_universe_body.append(false)


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
	_arrival_stop_played = false
	_activities_panel.show_for_travel()
	# Just a location-ish readout, same role _view_label always plays — NOT
	# a status message anymore (see ConsolePanel's always-on ship-status
	# strip, TravelCalc.ship_status, for "Orienting to Target"/"Acceleration
	# Burn"/etc.). Stays fixed for the whole trip; no more swapping between
	# different phase text up here.
	HUD.set_view("En Route to %s" % PlayerState.travel_target_id.to_upper(), "cockpit")

	# Warp point intensity (see _process) is current speed as a fraction of
	# THIS trip's own peak — a short hop with a modest peak speed should
	# still show a mild effect at "full" warp, not a fraction of some
	# unrelated fixed ceiling every trip is judged against. Floored well
	# above 0 purely to avoid a division blowing up for a degenerate
	# zero-distance profile — real trips always have a real peak speed.
	var speed_profile := TravelCalc.flight_profile(
			PlayerState.travel_distance_km, PlayerState.travel_accel_km_s2, PlayerState.travel_cruise_cap_km_s)
	_transit_peak_speed = maxf(speed_profile["cruise_speed"], 1.0)
	_transit_burn_duration = speed_profile["burn_duration"]

	var target_id := PlayerState.travel_target_id
	var from_id := PlayerState.location_id
	var entry := KnownBodies.get_entry(target_id)
	var from_entry := KnownBodies.get_entry(from_id)

	if entry != null and from_entry != null:
		var end_body: Node3D
		if _universe_bodies.has(target_id):
			end_body = _universe_bodies[target_id]
		else:
			end_body = _spawn_asteroid_body(entry) if entry.body_type == "Asteroid" else _spawn_moon_body(entry)
			_transit_body = end_body

		# The destination's moons become real NOW, not at arrival — they're
		# anchored near the destination and grow into view during the
		# approach exactly like the destination itself; spawned on arrival
		# they popped onto the screen right as orbit settled. See
		# _build_secondaries; _secondaries_built_for is what tells
		# _build_arrival not to spawn a duplicate set on top of these.
		_build_secondaries(entry)
		_secondaries_built_for = target_id

		var from_pos := _body_anchor_pos(from_entry)
		var end_pos := end_body.position
		var travel_dir := end_pos - from_pos
		var travel_dir_n := travel_dir.normalized() if travel_dir.length() > 0.01 else _camera_base_forward
		if _warp_points != null:
			_warp_points.set_axis(travel_dir_n)
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
		#
		# NOT _primary — GO always routes through a fresh Cockpit scene load
		# (see class comment), and _ready() goes straight to _build_transit()
		# without ever calling _build_arrival() first when a trip is already
		# in progress, so _primary is still null at this point every single
		# time. Have to find the departure body's node by other means:
		#   - A planet/Sol is always in _universe_bodies, found by from_id.
		#   - A moon isn't (ad-hoc, only ever spawned by _build_arrival/
		#     _build_secondaries) — the moon we just left never got spawned
		#     in THIS fresh scene UNLESS it's also one of the destination's
		#     own secondaries (its parent planet, or a sibling moon of the
		#     same parent — see _build_secondaries just above), which is
		#     exactly the moon<->parent case this needs to cover: leaving a
		#     moon for its own parent planet respawns that same moon as the
		#     parent's background dressing, sitting right in the flight path.
		#     Anything else (the departure moon isn't part of the
		#     destination's own system) has no node here to hide in the
		#     first place, so there's nothing to do.
		var hide_target: Node3D = _universe_bodies.get(from_id)
		if hide_target == null:
			for secondary: Node3D in _secondaries:
				if secondary.name == from_id:
					hide_target = secondary
					break
		if hide_target != null:
			_hidden_from_body = hide_target
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
		#
		# Derived from from_pos (Sol -> departure body), NOT _sun.global_basis.z
		# — the sun's actual basis.z is the OPPOSITE of that (Godot's look_at
		# convention points -Z at the target, so basis.z ends up as
		# body -> Sol, "direction to the sun," which is exactly what the
		# atmosphere shader wants it for elsewhere — see _apply_sun_dir's
		# `sun_dir` uniform — but is backwards as a `dir`-shaped input here).
		# Reading the basis fed a near-antiparallel pair into the lerp below
		# whenever from/to were close together in Sol's sky (leaving a moon
		# for its own parent planet, or vice versa): the blend passes through
		# zero length right around the midpoint, which the `length() > 0.01`
		# guard then freezes on, and the direction effectively flips sign
		# partway through the trip — read as the destination swinging from
		# lit to fully dark mid-flight.
		var from_sol_dir := from_pos - _sol_position
		_sun_lean_from_dir = (from_sol_dir.normalized() if from_sol_dir.length() > 0.01
				else (_sun.global_basis.z if _sun != null else Vector3.ZERO))
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
	AudioManager.launch()  # the very start of the trip — see AudioManager.launch's own comment
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
