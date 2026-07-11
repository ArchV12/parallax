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
# hard to a peak speed, then RELAXES back down toward a small, fixed
# "cruise" speed (CRUISE_SPEED_KM_S) before a final glide and orbital
# insertion, rather than decelerating all the way to a dead stop.
#
# That relaxation is EXPONENTIAL DECAY toward cruise speed, not a linear
# ramp (2026-07-11, second attempt at this — the first used a constant
# deceleration, same magnitude as the accel phase's engine thrust). The
# problem with linear: peak speeds here run into the millions of km/s while
# cruise speed is tens — a linear ramp across FIVE-PLUS ORDERS OF MAGNITUDE
# spends effectively its entire duration still at "still huge," only
# visibly changing in the literal last instant, which reads as an abrupt
# jolt no matter how long the ramp technically takes in seconds (the
# problem was never the DURATION, it was the SHAPE). Exponential decay
# drops by a constant *percentage* per unit time instead of a constant
# *amount*, so it spends comparable time crossing every order of magnitude
# — millions to hundreds of thousands to tens of thousands to hundreds to
# cruise speed, each step visibly legible on the HUD, the way a real
# instrument needle settles rather than a number just vanishing.
# DECEL_SETTLE_MULTIPLES is generous (20 time constants) specifically so
# this converges to a negligible gap from cruise speed regardless of how
# extreme the peak is (millions or billions of km/s) — no visible pop at
# the handoff into the flat cruise glide that follows.
#
# flight_profile() is the ONE place this whole burn/decay/cruise shape is
# computed — estimate() (duration), current_speed_km_s() (the HUD number),
# ship_status() (the HUD phase label), AND Cockpit's own camera position
# curve (see Cockpit.gd _process, which calls flight_progress() below) all
# read the SAME numbers, so the readout and the actual motion on screen can
# never show something different from each other.
const AU_KM := 149597870.0
const EARTH_MOON_DISTANCE_KM := 384400.0     # real — the trip this whole model is calibrated against
const CRUISE_SPEED_KM_S := 300.0             # fixed final-approach speed — the one number every arrival glides in at, tune by eye
const CRUISE_DISTANCE_KM := 100.0            # fixed real distance spent at CRUISE_SPEED_KM_S before arrival (=0.5s glide) — capped at half the trip's real distance for very short hops, see flight_profile
const DECEL_TIME_CONSTANT_SECONDS := 0.25    # tau — how quickly speed decays toward cruise; a FIXED decay rate independent of engine power, so deceleration always reads as gradual regardless of how extreme the peak speed is
const DECEL_SETTLE_MULTIPLES := 20.0         # time constants until the decay is negligibly close to cruise speed (e^-20 ≈ 2e-9 of the original gap, however large that gap is) — not just "mostly done"
const DECEL_DURATION := DECEL_TIME_CONSTANT_SECONDS * DECEL_SETTLE_MULTIPLES  # = 5.0s, fixed — same every trip
# Solved (not derived from a simple formula anymore, since burn+decay+cruise
# doesn't reduce to a clean closed form) so Earth<->Luna lands roughly near
# 15s total under the full hold+burn+decay+cruise model above — same
# anchor-trip philosophy as before, just approximate now. Tune by eye.
const ENGINE_ACCEL_KM_S2 := 16669.4
# A handful of same-system pairs sit genuinely close together in real life
# (e.g. Phobos<->Deimos, ~14,000 km apart) — close enough that the computed
# duration comes out too short for Cockpit's own departure-maneuver-plus-
# orbital-lean choreography (DEPARTURE_HOLD_SECONDS/pre_arrival_lead_seconds
# below) to play out sensibly, which would break that sequencing outright,
# not just look rushed. This floor is a game-feel constraint, not a physics
# one — flight_profile()'s own natural timing is untouched by it; a floored
# trip just means the ship finishes its burn+cruise and then waits.
const MIN_DURATION_SECONDS := 8.0

# How long the ship holds fully still at the start of a trip before real
# motion begins — Cockpit's departure-maneuver reorientation plays out during
# this window (see Cockpit.gd's DEPARTURE_MANEUVER_TIME, which reads this
# same constant rather than hardcoding its own copy). current_speed_km_s
# needs to know it too — speed must read exactly 0 during the hold, the same
# window Cockpit is visually holding position, not ramping up early.
const DEPARTURE_HOLD_SECONDS := 3.4

# How much of the DECELERATION half the ship spends visually "settling into
# orbit" (Cockpit's _apply_lean — a separate, artistic smoothstep blend
# toward the orbit target, not itself tied to the real physics) rather than
# still flying the raw constant-acceleration curve. A FRACTION of motion
# time, not a flat number of seconds (see pre_arrival_lead_seconds below) —
# a flat constant doesn't scale: 2s is a big chunk of a 15s cheat-engine hop
# but nothing at all on a real multi-minute trip, so either the swing starts
# while still screaming in (too early) or barely gets any runway at all,
# depending on trip length. Real deceleration DOES bring velocity to ~0
# right at arrival by design — the point of this window isn't to fake
# slowing down, it's to only start the reorientation once the ship is
# ALREADY genuinely slow (per the real curve), so turning away from
# "facing target" doesn't happen while still visibly screaming toward it.
const PRE_ARRIVAL_LEAD_FRACTION := 0.13  # was 0.18 — shortened alongside ORBIT_SETTLE_DURATION so orbital insertion overall reads a bit snappier, tune by eye


# The ACTUAL seconds-before-arrival the lean should start for a trip of this
# total duration — see PRE_ARRIVAL_LEAD_FRACTION. Applied against motion
# time (after the departure hold), not the whole trip, since the hold itself
# has no bearing on how much of the deceleration curve is left.
static func pre_arrival_lead_seconds(duration_sec: float) -> float:
	return maxf(duration_sec - DEPARTURE_HOLD_SECONDS, 0.001) * PRE_ARRIVAL_LEAD_FRACTION

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
	var cruise_duration: float = profile["cruise_duration"]
	var duration := maxf(DEPARTURE_HOLD_SECONDS + burn_duration + cruise_duration, MIN_DURATION_SECONDS)
	return {"local": local, "distance_au": distance_km / AU_KM, "distance_km": distance_km, "duration_sec": duration}


# The single source of truth for the whole burn+decay+cruise shape of a
# trip — see the class comment. Burns from rest, accelerating at `accel`
# for as long as it takes to reach a peak speed, then RELAXES exponentially
# toward CRUISE_SPEED_KM_S over a fixed DECEL_DURATION (not decelerating at
# engine-thrust rate — see class comment on why linear doesn't work here),
# then a fixed final glide at that cruise speed for whatever
# CRUISE_DISTANCE_KM survives the short-hop cap.
#
# Derivation: with peak speed V, the accelerate phase takes t1=V/accel and
# covers V²/(2*accel). The decay phase's distance is the exact integral of
# v(s) = C + (V-C)*e^(-s/tau) from 0 to DECEL_DURATION, which works out to
# C*DECEL_DURATION + (V-C)*tau*(1-e^(-DECEL_DURATION/tau)) — call the decay
# term's coefficient K = tau*(1-e^(-DECEL_DURATION/tau)) (≈tau, since 20 time
# constants makes that exponential negligible). Setting accel_dist +
# decay_dist = burn_dist gives a quadratic in V, solved below.
static func flight_profile(distance_km: float, accel_multiplier: float = 1.0) -> Dictionary:
	var accel := ENGINE_ACCEL_KM_S2 * accel_multiplier
	var cruise_dist := minf(CRUISE_DISTANCE_KM, distance_km * 0.5)
	var burn_dist := maxf(distance_km - cruise_dist, 0.0)
	var cruise_duration := cruise_dist / CRUISE_SPEED_KM_S
	var tau := DECEL_TIME_CONSTANT_SECONDS
	var decel_duration := DECEL_DURATION
	var k := tau * (1.0 - exp(-decel_duration / tau))

	# V² + (2*accel*k)*V + 2*accel*(C*decel_duration - C*k - burn_dist) = 0
	var b := 2.0 * accel * k
	var c_coef := 2.0 * accel * (CRUISE_SPEED_KM_S * decel_duration - CRUISE_SPEED_KM_S * k - burn_dist)
	var discriminant := b * b - 4.0 * c_coef
	var peak_speed: float
	if discriminant < 0.0:
		peak_speed = CRUISE_SPEED_KM_S  # degenerate short/slow trip: nothing to accelerate to beyond cruise speed itself
	else:
		peak_speed = maxf((-b + sqrt(discriminant)) * 0.5, CRUISE_SPEED_KM_S)
	var t1 := peak_speed / accel

	return {
		"burn_dist": burn_dist,
		"cruise_dist": cruise_dist,
		"peak_speed": peak_speed,
		"t1": t1,
		"tau": tau,
		"decel_duration": decel_duration,
		"burn_duration": t1 + decel_duration,
		"cruise_duration": cruise_duration,
	}


# 0..1 fraction of distance_km covered at a given elapsed time (measured
# from the END of the departure hold, i.e. "seconds of actual motion so
# far") — what Cockpit's camera position curve is driven by directly, so
# the motion on screen is BY CONSTRUCTION the same shape current_speed_km_s/
# ship_status describe. Holds at 1.0 once burn+decay+cruise naturally
# finish, even if the game-clock trip (MIN_DURATION_SECONDS floor) runs a
# little longer — see the class comment on that floor.
static func flight_progress(distance_km: float, motion_elapsed_sec: float, accel_multiplier: float = 1.0) -> float:
	if distance_km <= 0.001:
		return 1.0
	var profile := flight_profile(distance_km, accel_multiplier)
	var t1: float = profile["t1"]
	var tau: float = profile["tau"]
	var decel_duration: float = profile["decel_duration"]
	var cruise_duration: float = profile["cruise_duration"]
	var peak_speed: float = profile["peak_speed"]
	var burn_dist: float = profile["burn_dist"]
	var accel := ENGINE_ACCEL_KM_S2 * accel_multiplier
	var burn_duration := t1 + decel_duration
	var t := clampf(motion_elapsed_sec, 0.0, burn_duration + cruise_duration)
	var dist_covered: float
	if t <= t1:
		dist_covered = 0.5 * accel * t * t
	elif t <= burn_duration:
		var s := t - t1
		var accel_dist := 0.5 * accel * t1 * t1
		var decay_dist := CRUISE_SPEED_KM_S * s + (peak_speed - CRUISE_SPEED_KM_S) * tau * (1.0 - exp(-s / tau))
		dist_covered = accel_dist + decay_dist
	else:
		var cruise_t := t - burn_duration
		dist_covered = burn_dist + CRUISE_SPEED_KM_S * cruise_t
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
	var tau: float = profile["tau"]
	var decel_duration: float = profile["decel_duration"]
	var cruise_duration: float = profile["cruise_duration"]
	var peak_speed: float = profile["peak_speed"]
	var burn_duration := t1 + decel_duration
	var t := clampf(motion_elapsed, 0.0, burn_duration + cruise_duration)
	var accel := ENGINE_ACCEL_KM_S2 * accel_multiplier
	if t <= t1:
		return accel * t
	elif t <= burn_duration:
		var s := t - t1
		return CRUISE_SPEED_KM_S + (peak_speed - CRUISE_SPEED_KM_S) * exp(-s / tau)
	return CRUISE_SPEED_KM_S


# The always-on "ship status" readout — ConsolePanel shows whichever of
# these is current at all times, not just while en route. Assumes the ship
# IS currently traveling; callers show "IN ORBIT" themselves when
# PlayerState.is_traveling is false (this function has no notion of "not
# traveling," only of where within a trip the ship currently is).
static func ship_status(distance_km: float, duration_sec: float, elapsed_sec: float, accel_multiplier: float = 1.0) -> String:
	if elapsed_sec < DEPARTURE_HOLD_SECONDS:
		return "Orienting to Target"
	if duration_sec - elapsed_sec <= pre_arrival_lead_seconds(duration_sec):
		return "Orbital Insertion"
	if distance_km <= 0.001:
		return "Cruising"
	var profile := flight_profile(distance_km, accel_multiplier)
	var t1: float = profile["t1"]
	var decel_duration: float = profile["decel_duration"]
	var motion_elapsed := elapsed_sec - DEPARTURE_HOLD_SECONDS
	if motion_elapsed <= t1:
		return "Acceleration Burn"
	elif motion_elapsed <= t1 + decel_duration:
		return "Deceleration Burn"
	return "Cruising"


static func format_distance(estimate_result: Dictionary) -> String:
	if estimate_result["local"]:
		return "DISTANCE: Local orbital transfer"
	return "DISTANCE: %.2f AU" % (estimate_result["distance_au"] as float)


static func format_duration(seconds: float) -> String:
	var s := maxi(0, int(ceil(seconds)))
	return "%d:%02d" % [s / 60, s % 60]
