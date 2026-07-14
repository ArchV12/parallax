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
# hard toward a peak speed, then decelerates at that SAME magnitude all the
# way back down to a dead stop (v = 0) exactly at the destination, and ONLY
# THEN is "Orbital Insertion" underway (2026-07-11, fourth attempt at this
# shape — an earlier version decelerated to a small fixed nonzero cruise
# speed instead of 0, which still read as "ridiculous" on the HUD right as
# "Orbital Insertion" appeared). Decelerating to a genuine 0 means "speed
# reads 0" and "Orbital Insertion" are the same moment by construction, for
# EVERY caller — including the gameplay-pacing default (ENGINE_ACCEL_KM_S2,
# uncapped), which never has a cruise phase at all, just accel then decel.
#
# ENGINE_TIERS (below) add an actual, optional CRUISE phase in between —
# accelerate up to a capped speed, hold it, decelerate — used only when a
# tier's cruise_cap_km_s is actually reached (see flight_profile); this is
# a physically-motivated model for real-world-scale distances, entirely
# separate from the gameplay-pacing default every normal trip still uses.
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

# --- Engine tiers (F2 cheat menu, see HUD/CheatMenu/PlayerState) ---
# The player's REAL engine only ever gets this fast in-fiction — see the
# travel-time-scale brainstorm in parallax-core-design-decisions memory.
# ENGINE_ACCEL_KM_S2 above is pure gameplay pacing (tuned so a trip feels
# good in wall-clock seconds) and is NOT physically consistent at
# interplanetary range — run out to Mars distance, its implied peak speed
# is already several times the speed of light. These tiers are a genuinely
# separate, physically-grounded model: modest acceleration up to a capped
# cruise speed (0 = uncapped), each tier roughly an order of magnitude
# faster than the last. Tier 4 (0.99c) puts Pluto at ~5.5 hours — right
# where "distance/c" says it should be. Off by default (PlayerState.
# engine_tier_override == -1) — with no tier pinned, PlayerState.
# start_travel uses ENGINE_ACCEL_KM_S2 directly, exactly like before tiers
# existed. PINNING a tier DOES now drive the actual trip (see
# compress_by_tier_reach/TIER_REACH_KM below) — these accel/cap numbers
# feed PlayerState.real_duration_estimate's honest real-world-scale
# display number, but never touch the camera/flight_profile directly.
#
# real_time_scale (2026-07-12): a DISPLAY-ONLY multiplier applied on top of
# the accel/cap-derived duration, solely in PlayerState.real_duration_estimate
# — never touches accel_km_s2/cruise_cap_km_s themselves, so it can't affect
# gameplay pacing (compress_by_tier_reach) or the camera. Needed because this
# ladder was built top-down from Tier 4's ~0.99c target, stepping each
# earlier tier down by ~10x — so even "Tier 1 Fusion Drive" implies
# sustained ~1.6g acceleration to reach 1% of light speed, giving an
# Earth->Jupiter "real" time of a few DAYS, far faster than any real-or-
# plausible fusion drive. Tier 0 stays unscaled (its whole trip is spent
# well under cruise cap, e.g. Jupiter in ~4.6 real years — already a
# sensible ion-drive number); Tiers 1-4 get a decreasing correction (each
# was progressively less absurd to begin with) so Earth->Jupiter lands
# roughly: T1 ~15 months, T2 ~6 weeks, T3 ~6.5 days, T4 ~1.4 days — a
# believable curve instead of the previous few-day/few-hour cluster.
const ENGINE_TIERS: Array[Dictionary] = [
	{"name": "Tier 0 — Ion Drive", "accel_km_s2": 2.289e-5, "cruise_cap_km_s": 4.33, "real_time_scale": 1.0},
	{"name": "Tier 1 — Fusion Drive", "accel_km_s2": 0.01585, "cruise_cap_km_s": 2997.9, "real_time_scale": 100.0},
	{"name": "Tier 2 — Improved Fusion", "accel_km_s2": 0.1585, "cruise_cap_km_s": 29979.0, "real_time_scale": 30.0},
	{"name": "Tier 3 — Antimatter Drive", "accel_km_s2": 0.7924, "cruise_cap_km_s": 149896.0, "real_time_scale": 10.0},
	{"name": "Tier 4 — Relativistic Cap", "accel_km_s2": 1.5690, "cruise_cap_km_s": 296794.0, "real_time_scale": 3.0},
]

# Each tier's own "comfortable frontier" distance (2026-07-11 design ask:
# T0 comfortably reaches Luna, Mars is prohibitive; T1 comfortably reaches
# Mars/Venus/Mercury, not much further; T2 comfortably reaches Jupiter,
# Saturn's a hike; T3 comfortably reaches the ice giants and Pluto; T4+ is
# easy everywhere in-system). This can't fall out of ENGINE_TIERS' own
# accel/cap alone: under the accelerate-cruise-decelerate model, two trips
# at the SAME tier that are both deep in the cruise phase scale roughly
# LINEARLY with distance (an 8x-farther body takes ~8x longer, not more) —
# nowhere near the ~200x-in-distance swing between "comfortable" and
# "prohibitive" that Tier 0's Luna-vs-Mars ask needed. So reach is its own
# explicit per-tier number, and compress_by_tier_reach compresses
# DISTANCE RELATIVE TO IT (not raw real seconds) — a trip AT a tier's own
# reach distance always compresses to the same gameplay time regardless of
# which tier or how far that reach physically is, so "T2's own Jupiter"
# feels exactly as comfortable as "T0's own Luna" did.
const TIER_REACH_KM: Array[float] = [
	384400.0,        # Tier 0 — Luna
	77790893.0,      # Tier 1 — Mars (0.52 AU)
	628311054.0,     # Tier 2 — Jupiter (4.2 AU)
	5759517995.0,    # Tier 3 — Pluto (38.5 AU)
	11519035990.0,   # Tier 4 — beyond Pluto (2x, so even Pluto itself is comfortably inside reach — "easier all around")
]

# Log-scale compression of (trip distance / this tier's TIER_REACH_KM) —
# a straight proportional scale-down would still leave "just past the
# frontier" barely distinguishable from "at the frontier"; log compression
# is the right tool for "vast multiplicative range -> narrow additive
# range." _COMPRESS_A is the gameplay duration AT ratio 1.0 (a trip
# exactly at this tier's own reach) — 120s, the original "Tier 0 to Luna
# should feel like ~2 minutes" ask. _COMPRESS_B is fitted so ratio 202.4
# (Tier 0's real Luna-to-Mars distance ratio) lands at 900s (~15 minutes,
# "prohibitively far" for Tier 0) — every other tier/destination
# combination falls out of that SAME fit against ITS OWN reach, not a
# hand-tuned number per pairing. Floored at MIN_DURATION_SECONDS so a
# trip well inside a tier's reach (Venus at Tier 1, say) can't compress to
# zero or negative.
const _COMPRESS_A := 120.0
const _COMPRESS_B := 146.95


static func compress_by_tier_reach(distance_km: float, tier: int) -> float:
	var reach_km: float = TIER_REACH_KM[clampi(tier, 0, TIER_REACH_KM.size() - 1)]
	var ratio := distance_km / maxf(reach_km, 1.0)
	return maxf(MIN_DURATION_SECONDS, _COMPRESS_A + _COMPRESS_B * log(maxf(ratio, 0.001)))


static func estimate(from_id: String, to_id: String, accel_km_s2: float = ENGINE_ACCEL_KM_S2, cruise_cap_km_s: float = 0.0) -> Dictionary:
	var from_entry := KnownBodies.get_entry(from_id)
	var to_entry := KnownBodies.get_entry(to_id)
	if from_entry == null or to_entry == null:
		return {"local": true, "distance_au": 0.0, "distance_km": 0.0, "duration_sec": MIN_DURATION_SECONDS}

	var local := _same_system(from_entry, to_entry)
	var distance_km := _real_distance_km(from_entry, to_entry)
	# A same-system trip (moon<->parent, etc.) already uses a REAL distance
	# (parent_distance_km) — never overridden. An interplanetary trip TO
	# the currently locked destination uses the true snapshot distance
	# captured the moment it was locked instead — see Destination.
	# locked_distance_km's own comment for why this beats the radial-only
	# |au_from - au_to| approximation _real_distance_km falls back to
	# otherwise (it has no notion of WHERE around its orbit a body
	# currently sits, only how far out).
	if not local and to_id == Destination.locked_id and Destination.locked_distance_km >= 0.0:
		distance_km = Destination.locked_distance_km
	return _finish_estimate(local, distance_km, accel_km_s2, cruise_cap_km_s)


# A body that's both focused AND locked needs to report two DIFFERENT
# numbers at once depending on who's asking: the committed destination
# readout (estimate() above) must keep showing the frozen locked_distance_km
# it locked in, while the live preview readout (ConsolePanel, via this)
# needs to keep tracking the body's real current position regardless of
# whether it's also locked — that's the whole point of it existing (see
# Destination.preview_id). Routing both through the SAME estimate() call
# with an implicit global-state lookup can't satisfy both at once, so this
# takes the distance explicitly instead of resolving it itself.
static func estimate_for_distance(
		distance_km: float, accel_km_s2: float = ENGINE_ACCEL_KM_S2, cruise_cap_km_s: float = 0.0) -> Dictionary:
	return _finish_estimate(false, distance_km, accel_km_s2, cruise_cap_km_s)


static func _finish_estimate(local: bool, distance_km: float, accel_km_s2: float, cruise_cap_km_s: float) -> Dictionary:
	var profile := flight_profile(distance_km, accel_km_s2, cruise_cap_km_s)
	var burn_duration: float = profile["burn_duration"]
	var duration := maxf(DEPARTURE_HOLD_SECONDS + burn_duration + ARRIVAL_HOLD_SECONDS, MIN_DURATION_SECONDS)
	return {"local": local, "distance_au": distance_km / AU_KM, "distance_km": distance_km, "duration_sec": duration}


# The single source of truth for the whole burn/cruise/decel shape of a
# trip — see the class comment. Accelerates from rest at `accel_km_s2`
# toward a peak speed; if that natural peak would exceed `cruise_cap_km_s`
# (and a cap is actually set — 0 means uncapped), the ship instead
# accelerates only up to the cap, CRUISES at that constant speed for
# whatever distance is left, then decelerates back to a dead stop at that
# same `accel_km_s2` — arriving at v = 0 exactly at the destination either
# way. A short hop (Moon-scale, under the gameplay-pacing constant, or any
# tier's own natural range) never reaches its cap at all and this reduces
# to the plain symmetric burn/decel shape used everywhere before tiers
# existed.
#
# Uncapped derivation: with peak speed V, each phase covers V²/(2*accel)
# (accel from rest, decel back to rest — the same formula both times).
# V²/accel = distance_km, so V = sqrt(accel * distance_km), t1 = t2 = V/accel.
#
# Capped derivation: accel phase covers accel_dist = cap²/(2*accel) in
# t1 = cap/accel; decel mirrors it exactly; whatever distance remains
# (cruise_dist) is covered at the constant cap speed in cruise_dist/cap.
static func flight_profile(distance_km: float, accel_km_s2: float, cruise_cap_km_s: float = 0.0) -> Dictionary:
	var natural_peak := sqrt(maxf(accel_km_s2 * distance_km, 0.0))
	if cruise_cap_km_s <= 0.0 or natural_peak <= cruise_cap_km_s or accel_km_s2 <= 0.0:
		var t1 := (natural_peak / accel_km_s2) if accel_km_s2 > 0.0 else 0.0
		return {
			"cruise_speed": natural_peak,
			"t1": t1,
			"accel_dist": distance_km * 0.5,
			"cruise_dist": 0.0,
			"burn_duration": t1 + t1,
		}

	var t1 := cruise_cap_km_s / accel_km_s2
	var accel_dist := 0.5 * accel_km_s2 * t1 * t1
	var cruise_dist := maxf(distance_km - 2.0 * accel_dist, 0.0)
	var cruise_time := cruise_dist / cruise_cap_km_s
	return {
		"cruise_speed": cruise_cap_km_s,
		"t1": t1,
		"accel_dist": accel_dist,
		"cruise_dist": cruise_dist,
		"burn_duration": 2.0 * t1 + cruise_time,
	}


# 0..1 fraction of distance_km covered at a given elapsed time (measured
# from the END of the departure hold, i.e. "seconds of actual motion so
# far") — what Cockpit's camera position curve is driven by directly, so
# the motion on screen is BY CONSTRUCTION the same shape current_speed_km_s/
# ship_status describe. Holds at 1.0 once burn+cruise+decel naturally
# finish (ship at rest), even if the game-clock trip (MIN_DURATION_SECONDS
# floor) runs a little longer — see the class comment on that floor.
static func flight_progress(distance_km: float, motion_elapsed_sec: float, accel_km_s2: float, cruise_cap_km_s: float = 0.0) -> float:
	if distance_km <= 0.001:
		return 1.0
	var profile := flight_profile(distance_km, accel_km_s2, cruise_cap_km_s)
	var t1: float = profile["t1"]
	var accel_dist: float = profile["accel_dist"]
	var cruise_dist: float = profile["cruise_dist"]
	var cruise_speed: float = profile["cruise_speed"]
	var burn_duration: float = profile["burn_duration"]
	var cruise_time := burn_duration - 2.0 * t1
	var t := clampf(motion_elapsed_sec, 0.0, burn_duration)
	var dist_covered: float
	if t <= t1:
		dist_covered = 0.5 * accel_km_s2 * t * t
	elif t <= t1 + cruise_time:
		dist_covered = accel_dist + cruise_speed * (t - t1)
	else:
		var s := t - t1 - cruise_time
		dist_covered = accel_dist + cruise_dist + (cruise_speed * s - 0.5 * accel_km_s2 * s * s)
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
static func current_speed_km_s(distance_km: float, duration_sec: float, elapsed_sec: float, accel_km_s2: float, cruise_cap_km_s: float = 0.0) -> float:
	var motion_elapsed := maxf(elapsed_sec - DEPARTURE_HOLD_SECONDS, 0.0)
	if distance_km <= 0.001:
		return 0.0
	var profile := flight_profile(distance_km, accel_km_s2, cruise_cap_km_s)
	var t1: float = profile["t1"]
	var cruise_speed: float = profile["cruise_speed"]
	var burn_duration: float = profile["burn_duration"]
	var cruise_time := burn_duration - 2.0 * t1
	var t := clampf(motion_elapsed, 0.0, burn_duration)
	if t <= t1:
		return accel_km_s2 * t
	if t <= t1 + cruise_time:
		return cruise_speed
	var s := t - t1 - cruise_time
	return maxf(cruise_speed - accel_km_s2 * s, 0.0)


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
# A capped tier adds a fourth phase, "Cruise," between the burn and the
# decel — only ever reached when flight_profile actually hit its cap (see
# that function), so an uncapped/never-capped trip's cruise_time is exactly
# 0 and this collapses back to the original three-phase (burn/decel/
# insertion) reading.
static func ship_status(distance_km: float, elapsed_sec: float, accel_km_s2: float, cruise_cap_km_s: float = 0.0) -> String:
	if elapsed_sec < DEPARTURE_HOLD_SECONDS:
		return "Orienting to Target"
	if distance_km <= 0.001:
		return "Orbital Insertion"
	var profile := flight_profile(distance_km, accel_km_s2, cruise_cap_km_s)
	var t1: float = profile["t1"]
	var burn_duration: float = profile["burn_duration"]
	var cruise_time := burn_duration - 2.0 * t1
	var motion_elapsed := elapsed_sec - DEPARTURE_HOLD_SECONDS
	if motion_elapsed <= t1:
		return "Acceleration Burn"
	elif motion_elapsed <= t1 + cruise_time:
		return "Cruise"
	elif motion_elapsed <= burn_duration:
		return "Deceleration Burn"
	return "Orbital Insertion"


static func format_distance(estimate_result: Dictionary) -> String:
	if estimate_result["local"]:
		return "DISTANCE: Local orbital transfer"
	return "DISTANCE: %.2f AU" % (estimate_result["distance_au"] as float)


# Every normal-gameplay-pacing trip stays well under an hour, so this only
# ever showed MM:SS before tiers existed — a slow tier (see ENGINE_TIERS)
# can genuinely put a trip in the days/months/years range, where MM:SS
# would just be an unreadable wall of digits, so this degrades to
# coarser units the longer the duration actually is.
static func format_duration(seconds: float) -> String:
	var s := maxi(0, int(ceil(seconds)))
	if s < 3600:
		return "%d:%02d" % [s / 60, s % 60]
	if s < 86400:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	const SECONDS_PER_YEAR := 31557600  # 365.25 days — close enough for a display readout, not an orbital calculation
	if s < SECONDS_PER_YEAR:
		return "%dd %02dh" % [s / 86400, (s % 86400) / 3600]
	return "%dy %dd" % [s / SECONDS_PER_YEAR, (s % SECONDS_PER_YEAR) / 86400]
