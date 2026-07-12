class_name TravelCalc
extends RefCounted

# Distance/duration estimate for a GO trip between two KnownBodies ids.
# There's no unified 3D coordinate system yet (Cockpit/System/Planetary
# System views are separate scale contexts — see Cockpit.gd), so this works
# off catalog data (au_distance, parent, parent_distance_km) rather than any
# real travel vector. Shared by ConsolePanel (readout while a destination is
# merely locked) and PlayerState (the actual travel timer once GO is pressed).
#
# A genuine constant-acceleration ("torch drive") model — the ship burns
# hard to a peak speed, then decelerates at that SAME magnitude all the way
# back down to a dead stop (v = 0) exactly at the destination, and ONLY
# THEN is "Orbital Insertion" underway. No cruise coast at the end
# (2026-07-11, fourth attempt at this shape — the previous version
# decelerated to a small fixed CRUISE_SPEED_KM_S instead of 0 and coasted
# the last CRUISE_DISTANCE_KM in at that speed, which read fine in
# isolation but broke the actual ask: "Orbital Insertion" is supposed to
# mean the ship has genuinely stopped, and a nonzero cruise speed — even a
# "small" one like 500 km/s — still reads as "ridiculous" on the HUD right
# as that label appears). Decelerating to a genuine 0 removes the whole
# category of problem: there's no separate cruise phase/speed to keep in
# sync with the label anymore, and "speed reads 0" and "Orbital Insertion"
# become the same moment by construction.
#
# A real symmetric burn: accelerate at `accel` for as long as it takes to
# reach peak speed, then decelerate at that SAME `accel` for exactly as
# long it took to get there — both phases are the same v²=2*accel*d
# kinematics, 0->peak and peak->0, so t1 and t2 come out EXACTLY equal (not
# just approximately, the way decelerating to a nonzero cruise speed only
# gave "very nearly equal") — the cleanest version yet of the "half the
# burn distance speeding up, half braking" mental model this whole shape
# has been chasing.
#
# flight_profile() is the ONE place this whole burn/decel shape is
# computed — estimate() (duration), current_speed_km_s() (the HUD number),
# ship_status() (the HUD phase label), AND Cockpit's own camera position
# curve (see Cockpit.gd _process, which calls flight_progress() below) all
# read the SAME numbers, so the readout and the actual motion on screen can
# never show something different from each other.
const AU_KM := 149597870.0
const EARTH_MOON_DISTANCE_KM := 384400.0     # real — the trip this whole model is calibrated against
# Tuned so Earth<->Luna lands roughly near 15s total under the full
# hold+burn+decel model above — same anchor-trip philosophy each rework of
# this file has kept. Tune by eye.
const ENGINE_ACCEL_KM_S2 := 16669.4
# A handful of same-system pairs sit genuinely close together in real life
# (e.g. Phobos<->Deimos, ~14,000 km apart) — close enough that the computed
# duration comes out too short for Cockpit's own departure-maneuver-plus-
# arrival-hold-plus-orbital-lean choreography (DEPARTURE_HOLD_SECONDS/
# ARRIVAL_HOLD_SECONDS below) to play out sensibly, which would break that
# sequencing outright, not just look rushed. This floor is a game-feel
# constraint, not a physics one — flight_profile()'s own natural timing is
# untouched by it; a floored trip just means the ship finishes its burn
# (already at rest) and waits.
const MIN_DURATION_SECONDS := 8.0

# How long the ship holds fully still at the start of a trip before real
# motion begins — Cockpit's departure-maneuver reorientation plays out during
# this window (see Cockpit.gd's DEPARTURE_MANEUVER_TIME, which reads this
# same constant rather than hardcoding its own copy). current_speed_km_s
# needs to know it too — speed must read exactly 0 during the hold, the same
# window Cockpit is visually holding position, not ramping up early.
const DEPARTURE_HOLD_SECONDS := 3.4

# How long the ship sits fully stopped — genuinely at rest, v = 0, not just
# reading close to it — AFTER decel finishes and BEFORE the reorientation
# into orbit begins (2026-07-11: the explicit ask was "pull up to the
# planet to a complete stop, pause, THEN reorient" — Cockpit no longer
# starts turning mid-decel at all; see Cockpit.gd's _begin_orbit_settle,
# which now only ever fires once this hold has elapsed, via
# PlayerState.travel_completed). Mirrors DEPARTURE_HOLD_SECONDS on the
# other end of the trip — both are fixed real-time pauses bracketing the
# motion, not scaled to trip length, since they're pacing beats, not
# physics.
const ARRIVAL_HOLD_SECONDS := 2.0

# How long the camera's reorientation-into-orbit takes, once it starts (see
# Cockpit.gd's _begin_orbit_settle, fired by PlayerState.travel_completed —
# i.e., right as ARRIVAL_HOLD_SECONDS ends). Purely a camera/visual timing
# constant — nothing here computes anything from it — but it lives in
# TravelCalc rather than Cockpit.gd because ConsolePanel needs the SAME
# number: PlayerState.travel_completed/location_changed fire the INSTANT
# this turn starts, not once it finishes, so a naive status readout that
# switches to "In Orbit" right on that signal would claim "in orbit" for
# the whole ~2.8s the camera is still visibly swinging around (2026-07-11 —
# exactly this was reported: "Orbital Insertion" cut to "In Orbit" while
# still rotating into place). ConsolePanel._on_location_changed holds
# "Orbital Insertion" for this same duration before switching, so the
# label and the camera settle together.
const ORBIT_SETTLE_DURATION := 2.8  # was 4.0, then trimmed once to 2.8 for pacing — tune by eye, but keep Cockpit.gd's own copy (a straight alias) in sync

# --- Testing cheat (F2 in-game, see HUD/PlayerState) ---
# A flat multiplier on ENGINE_ACCEL_KM_S2, not a separate formula — "a better
# engine" was already defined as "more acceleration," so the cheat is just a
# very good engine, same math and everything. Calibrated so an Earth->Mars
# hop (the trip actually complained about) lands at CHEAT_TARGET_SECONDS
# instead of ~3.5 minutes.
const CHEAT_TARGET_TRIP_AU := 0.52          # Earth<->Mars real AU separation
const CHEAT_TARGET_SECONDS := 15.0
const CHEAT_ENGINE_MULTIPLIER := (4.0 * CHEAT_TARGET_TRIP_AU * AU_KM / (CHEAT_TARGET_SECONDS * CHEAT_TARGET_SECONDS)) / ENGINE_ACCEL_KM_S2


static func estimate(from_id: String, to_id: String, accel_multiplier: float = 1.0) -> Dictionary:
	var from_entry := KnownBodies.get_entry(from_id)
	var to_entry := KnownBodies.get_entry(to_id)
	if from_entry == null or to_entry == null:
		return {"local": true, "distance_au": 0.0, "distance_km": 0.0, "duration_sec": MIN_DURATION_SECONDS}

	var local := _same_system(from_entry, to_entry)
	var distance_km := _real_distance_km(from_entry, to_entry)
	var profile := flight_profile(distance_km, accel_multiplier)
	var burn_duration: float = profile["burn_duration"]
	var duration := maxf(DEPARTURE_HOLD_SECONDS + burn_duration + ARRIVAL_HOLD_SECONDS, MIN_DURATION_SECONDS)
	return {"local": local, "distance_au": distance_km / AU_KM, "distance_km": distance_km, "duration_sec": duration}


# The single source of truth for the whole burn/decel shape of a trip — see
# the class comment. Burns from rest at `accel` up to a peak speed, covering
# exactly half the distance, then decelerates at that SAME `accel` back
# down to a dead stop, covering the other half — arriving at v = 0 exactly
# at the destination.
#
# Derivation: with peak speed V, each phase covers V²/(2*accel) (accel from
# rest, decel back to rest — the same formula both times, since both start
# or end at 0). Setting the two halves to sum to distance_km:
# V²/(2*accel) + V²/(2*accel) = distance_km, i.e. V²/accel = distance_km,
# so V = sqrt(accel * distance_km). t1 = t2 = V/accel EXACTLY — a true
# 50/50 split in both distance and time, not just approximately.
static func flight_profile(distance_km: float, accel_multiplier: float = 1.0) -> Dictionary:
	var accel := ENGINE_ACCEL_KM_S2 * accel_multiplier
	var peak_speed := sqrt(maxf(accel * distance_km, 0.0))
	var t1 := peak_speed / accel     # accel phase: 0 -> peak, first half of the distance
	var t2 := t1                     # decel phase: peak -> 0, second half — exactly symmetric

	return {
		"peak_speed": peak_speed,
		"t1": t1,
		"t2": t2,
		"burn_duration": t1 + t2,
	}


# 0..1 fraction of distance_km covered at a given elapsed time (measured
# from the END of the departure hold, i.e. "seconds of actual motion so
# far") — what Cockpit's camera position curve is driven by directly, so
# the motion on screen is BY CONSTRUCTION the same shape current_speed_km_s/
# ship_status describe. Holds at 1.0 once burn+decel naturally finish
# (ship at rest), even if the game-clock trip (MIN_DURATION_SECONDS floor)
# runs a little longer — see the class comment on that floor.
static func flight_progress(distance_km: float, motion_elapsed_sec: float, accel_multiplier: float = 1.0) -> float:
	if distance_km <= 0.001:
		return 1.0
	var profile := flight_profile(distance_km, accel_multiplier)
	var t1: float = profile["t1"]
	var t2: float = profile["t2"]
	var peak_speed: float = profile["peak_speed"]
	var accel := ENGINE_ACCEL_KM_S2 * accel_multiplier
	var burn_duration := t1 + t2
	var t := clampf(motion_elapsed_sec, 0.0, burn_duration)
	var dist_covered: float
	if t <= t1:
		dist_covered = 0.5 * accel * t * t
	else:
		var s := t - t1
		var accel_dist := 0.5 * accel * t1 * t1
		var decel_dist := peak_speed * s - 0.5 * accel * s * s
		dist_covered = accel_dist + decel_dist
	return clampf(dist_covered / distance_km, 0.0, 1.0)


# Real distance between the two bodies, approximated from catalog data (no
# unified coordinate system yet — see class comment). Same-system trips (a
# moon and its parent, or two moons of the same parent) use the real
# parent_distance_km figures directly; everything else falls back to the
# heliocentric AU-distance difference already used for the interplanetary
# case, converted to km.
static func _real_distance_km(from_entry: KnownBodies.Entry, to_entry: KnownBodies.Entry) -> float:
	if _same_system(from_entry, to_entry):
		if from_entry.parent == to_entry.body_name:
			return from_entry.parent_distance_km
		if to_entry.parent == from_entry.body_name:
			return to_entry.parent_distance_km
		return absf(from_entry.parent_distance_km - to_entry.parent_distance_km)
	return absf(_anchor_au(from_entry) - _anchor_au(to_entry)) * AU_KM


# True if `a`/`b` are the same planet-and-its-moons neighborhood: one is the
# other's parent, or they share a (non-Sol) parent — e.g. Earth<->Luna, or
# Luna<->some other hypothetical Earth moon.
static func _same_system(a: KnownBodies.Entry, b: KnownBodies.Entry) -> bool:
	if a.parent == b.body_name or b.parent == a.body_name:
		return true
	return a.parent != "" and a.parent == b.parent


# A body's approximate heliocentric distance for interplanetary comparisons —
# its own au_distance if it orbits Sol directly, else its parent's (a moon's
# own orbital radius around its planet is negligible at this scale).
static func _anchor_au(entry: KnownBodies.Entry) -> float:
	if entry.parent == "":
		return entry.au_distance
	var parent_entry := KnownBodies.get_entry(entry.parent)
	return parent_entry.au_distance if parent_entry != null else entry.au_distance


# Live speed for a trip in progress — reads flight_profile() directly (see
# class comment) rather than its own formula, so this can never show a
# number that disagrees with what Cockpit's camera is actually doing.
static func current_speed_km_s(distance_km: float, duration_sec: float, elapsed_sec: float, accel_multiplier: float = 1.0) -> float:
	var motion_elapsed := maxf(elapsed_sec - DEPARTURE_HOLD_SECONDS, 0.0)
	if distance_km <= 0.001:
		return 0.0
	var profile := flight_profile(distance_km, accel_multiplier)
	var t1: float = profile["t1"]
	var t2: float = profile["t2"]
	var peak_speed: float = profile["peak_speed"]
	var burn_duration := t1 + t2
	var t := clampf(motion_elapsed, 0.0, burn_duration)
	var accel := ENGINE_ACCEL_KM_S2 * accel_multiplier
	if t <= t1:
		return accel * t
	var s := t - t1
	return maxf(peak_speed - accel * s, 0.0)


# The always-on "ship status" readout — ConsolePanel shows whichever of
# these is current at all times, not just while en route. Assumes the ship
# IS currently traveling; callers show "IN ORBIT" themselves when
# PlayerState.is_traveling is false (this function has no notion of "not
# traveling," only of where within a trip the ship currently is).
#
# Purely a function of the real t1/t2 boundaries now — NOT gated by
# pre_arrival_lead_seconds/remaining time (2026-07-11: an earlier version
# switched to "Orbital Insertion" whenever remaining-time dropped below
# that flat, short camera-cue window, which is fine for the camera's own
# artistic lean but was flatly wrong as a claim about the SHIP'S state — on
# any trip where t2 (real decel duration) ran longer than that flat window,
# the label flipped to "Orbital Insertion" after completing only a sliver
# of the actual deceleration, with speed still reading almost peak; a
# second attempt decelerated to a nonzero CRUISE_SPEED_KM_S instead of a
# full stop, which still read as "ridiculous" the instant the label
# appeared. Decelerating all the way to v = 0 (see flight_profile) removes
# the whole category of bug: "Orbital Insertion" now literally IS the
# motion_elapsed > t1+t2 state, which is exactly when speed reaches 0, by
# construction — there's no separate threshold to keep in sync with it
# anymore. This one label covers the whole post-stop stretch — the
# ARRIVAL_HOLD_SECONDS full-stop pause AND the reorientation/settle that
# follows it (see Cockpit.gd's _begin_orbit_settle) — since from the
# player's perspective both are just "orbital insertion is underway."
static func ship_status(distance_km: float, elapsed_sec: float, accel_multiplier: float = 1.0) -> String:
	if elapsed_sec < DEPARTURE_HOLD_SECONDS:
		return "Orienting to Target"
	if distance_km <= 0.001:
		return "Orbital Insertion"
	var profile := flight_profile(distance_km, accel_multiplier)
	var t1: float = profile["t1"]
	var t2: float = profile["t2"]
	var motion_elapsed := elapsed_sec - DEPARTURE_HOLD_SECONDS
	if motion_elapsed <= t1:
		return "Acceleration Burn"
	elif motion_elapsed <= t1 + t2:
		return "Deceleration Burn"
	return "Orbital Insertion"


static func format_distance(estimate_result: Dictionary) -> String:
	if estimate_result["local"]:
		return "DISTANCE: Local orbital transfer"
	return "DISTANCE: %.2f AU" % (estimate_result["distance_au"] as float)


static func format_duration(seconds: float) -> String:
	var s := maxi(0, int(ceil(seconds)))
	return "%d:%02d" % [s / 60, s % 60]
