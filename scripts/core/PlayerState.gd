extends Node

# Session-scoped "where the player currently is / are they mid-trip" store —
# same in-memory-only shape as Destination.gd (no save system yet). Starts on
# Earth, matching the vertical slice's fixed starting position (see
# Cockpit.gd). travel_to() is the one entry point every "commit to this
# destination" UI routes through (ConsolePanel's GO, LocationsPanel's
# per-row GO) — Cockpit reads the resulting state to reflect "arrived" vs.
# "en route."

signal location_changed
signal travel_started
signal travel_completed

var location_id: String = "Earth"
# In-game calendar (2026-07-19) — starts at the game's real setting year
# (see HUD._year_label) and advances on every arrival by TravelCalc.
# years_for_distance_km(that trip's real distance) — "the date on Earth is
# year + travel distance in LY," the user's own design ask. Deliberately
# applies to every trip uniformly (see that function's own comment for why
# an in-system hop is a no-op at display precision) rather than a special
# interstellar-only code path.
var current_year: float = 2037.0
var is_traveling: bool = false
var travel_target_id: String = ""
var travel_duration: float = 0.0
var travel_elapsed: float = 0.0
var travel_distance_km: float = 0.0  # real distance for the CURRENT trip — see TravelCalc; Cockpit derives a live speed readout from this against travel_duration
# The accel/cap that actually flies the ship for the CURRENT trip — see
# start_travel/resolve_travel_engine. Once a valid engine tier resolves
# (see _effective_engine_tier — in practice always true, since Sub-Light
# Engines is owned from tier 0 onward), this is a GAMEPLAY-scale accel
# solved so the trip's own burn_duration lands on TravelCalc.
# compress_by_tier_reach's compressed number — NOT the tier's own real
# accel/cap directly (that was tried 2026-07-11 and immediately broken:
# pinning Tier 0 made an actual Moon trip take real DAYS of wall-clock
# waiting). The tier's real accel/cap only ever feeds
# travel_real_duration_sec below, never the camera. ENGINE_ACCEL_KM_S2
# uncapped (the pre-tiers flat default) is now only reachable if no valid
# tier resolves at all — a defensive fallback, not the normal path.
var travel_accel_km_s2: float = TravelCalc.ENGINE_ACCEL_KM_S2
var travel_cruise_cap_km_s: float = 0.0

# What THIS SAME trip takes under the tier's REAL (physically-grounded)
# physics — display-only (the "(REAL: ...)" annotation in ConsolePanel),
# computed alongside travel_duration in start_travel but never fed into the
# actual flight. 0.0 only if _effective_engine_tier() can't resolve a valid
# tier at all (defensive — Sub-Light Engines is always owned from tier 0
# onward, so in practice this always has something real to show once a
# trip starts). See the travel-time-scale brainstorm in
# parallax-core-design-decisions memory.
var travel_real_duration_sec: float = 0.0

# Cheat menu (F2 in HUD) — pins the ship to one of TravelCalc.ENGINE_TIERS,
# overriding the player's real Sub-Light Engines progression below. -1 = no
# pin, defer to _effective_engine_tier()'s real-progression fallback.
# Applied at the moment a trip STARTS (see start_travel), not retroactively
# to one already in progress — changing tiers mid-flight just means the
# next GO gets it.
var engine_tier_override: int = -1


# The tier that actually flies the ship right now. engine_tier_override
# (the F2 cheat pin) wins if set; otherwise this falls back to the
# player's real Sub-Light Engines equipment tier (Research.owned_tier) —
# 2026-07-18 hookup: previously engine_tier_override was the ONLY thing
# that could ever select a real ENGINE_TIERS entry, so crafting Fusion
# Drive/Improved Fusion/etc. had no gameplay effect at all. Sub-Light
# Engines is owned from tier 0 (STARTING_ACTIVITIES), so this always
# resolves to a valid ENGINE_TIERS index in practice — the "-1, fall back
# to flat ENGINE_ACCEL_KM_S2" path in resolve_travel_engine/
# real_duration_estimate below is now purely defensive.
func _effective_engine_tier() -> int:
	if engine_tier_override >= 0:
		return engine_tier_override
	return Research.owned_tier("sub_light_engines")


# True if from_id/to_id belong to different star systems — Sub-Light
# Engines/compress_by_tier_reach has no role here at all (direct user design
# decision: "sub-light engines have no use here, we are only using the
# beyond light engines"), see resolve_travel_engine's interstellar branch.
# Defensive false (not interstellar) if either id doesn't resolve — the
# existing local-orbital-transfer fallback already covers that case
# elsewhere (TravelCalc.estimate/resolve_travel_engine).
func _is_interstellar(from_id: String, to_id: String) -> bool:
	var from_entry := KnownBodies.get_entry(from_id)
	var to_entry := KnownBodies.get_entry(to_id)
	if from_entry == null or to_entry == null:
		return false
	return from_entry.star_system != to_entry.star_system


# Public wrapper for whatever trip is CURRENTLY in progress — UI (Ship
# StatusStrip's live EN ROUTE readout) needs this to pick sane units
# (TravelCalc.format_speed_km_s/format_distance_km) without duplicating the
# star_system comparison itself.
func is_current_trip_interstellar() -> bool:
	return _is_interstellar(location_id, travel_target_id)


func start_travel(target_id: String) -> void:
	if is_traveling or target_id == location_id:
		return
	var engine := resolve_travel_engine(location_id, target_id)
	travel_accel_km_s2 = engine["accel_km_s2"]
	travel_cruise_cap_km_s = engine["cruise_cap_km_s"]
	travel_real_duration_sec = engine["real_duration_sec"]
	var est := TravelCalc.estimate(location_id, target_id, travel_accel_km_s2, travel_cruise_cap_km_s)
	travel_target_id = target_id
	travel_duration = est["duration_sec"]
	travel_distance_km = est["distance_km"]
	travel_elapsed = 0.0
	is_traveling = true
	travel_started.emit()


# What a from_id -> to_id trip should ACTUALLY fly at right now, given the
# ship's current effective engine tier (_effective_engine_tier) — shared by
# start_travel (the real snapshot) and ConsolePanel's not-yet-departed ETA
# preview, so the preview never shows a number GO doesn't honor.
#
# No valid tier resolved (defensive only — see _effective_engine_tier's
# comment): the fixed gameplay-pacing default, unchanged from before tiers
# existed.
#
# Valid tier: that tier's REAL accel/cap (see ENGINE_TIERS) computes this
# trip's genuine real-world duration (real_duration_sec, for display only —
# see travel_real_duration_sec) — but what actually FLIES is a synthetic
# gameplay accel solved backward from TravelCalc.compress_by_tier_reach's
# compressed target (distance relative to THIS tier's own comfortable
# reach, not raw real seconds — see that function's comment for why),
# using the same uncapped symmetric-burn shape every default trip already
# uses (burn_duration = 2*sqrt(distance/accel), so
# accel = 4*distance/burn_duration²) — just aimed at a per-tier, per-trip
# target instead of whatever the flat default naturally produces. This is
# what makes each tier's own frontier body feel "comfortable" and anything
# past it feel like a real stretch, at every tier, not just Tier 0.
# Beyond Light Engines is the one equipment slot with NO free starting tier
# (owned_tier 0 == "None," a real placeholder InstrumentDef — its 5 real
# drives sit at owned_tier 1-5, one off from every other slot's 0-4 — see
# the ship-equipment design memory). Maps owned tier 1-5 -> STAR_TIER_REACH_LY
# index 0-4, same mapping Stellar View's own callout already uses
# independently for its travel-time preview (see StellarView._select) — this
# is what makes GO actually fly the trip that preview promised. Tier 0
# ("None") has no valid index at all, handled by the caller (resolve_travel_
# engine returns early before this is ever consulted at tier 0 — see below).
func _beyond_light_tier_index() -> int:
	return Research.owned_tier("beyond_light_engines") - 1


func resolve_travel_engine(from_id: String, to_id: String) -> Dictionary:
	if _is_interstellar(from_id, to_id):
		var bl_tier := _beyond_light_tier_index()
		if bl_tier < 0:
			# No real Beyond Light Engine owned yet — travel_to() already
			# refuses to start a trip in this state (see its own comment);
			# this is a defensive fallback only, matching the "no valid
			# tier resolved" shape every other branch here already uses.
			return {"accel_km_s2": TravelCalc.ENGINE_ACCEL_KM_S2, "cruise_cap_km_s": 0.0, "real_duration_sec": 0.0}
		var from_entry := KnownBodies.get_entry(from_id)
		var to_entry := KnownBodies.get_entry(to_id)
		var distance_ly := TravelCalc.star_distance_ly(from_entry.star_system, to_entry.star_system)
		var distance_km := distance_ly * TravelCalc.LY_TO_KM
		var gameplay_duration := TravelCalc.compress_by_star_tier_reach(distance_ly, bl_tier)
		var motion_target := maxf(
				gameplay_duration - TravelCalc.DEPARTURE_HOLD_SECONDS - TravelCalc.ARRIVAL_HOLD_SECONDS, 1.0)
		var accel_km_s2 := (distance_km * 4.0) / (motion_target * motion_target)
		# real_duration_sec 0.0, deliberately, not routed through real_
		# duration_estimate at all — there's no real-physics accel/cruise
		# ladder for a fictional warp drive the way ENGINE_TIERS has for
		# Sub-Light, so there's nothing honest to show. ShipStatusStrip's
		# "(REAL: ...)" annotation already gates on travel_real_duration_sec
		# > 0.0, so this alone is enough to hide it for an interstellar trip.
		return {"accel_km_s2": accel_km_s2, "cruise_cap_km_s": 0.0, "real_duration_sec": 0.0}

	var tier := _effective_engine_tier()
	if tier < 0 or tier >= TravelCalc.ENGINE_TIERS.size():
		return {"accel_km_s2": TravelCalc.ENGINE_ACCEL_KM_S2, "cruise_cap_km_s": 0.0, "real_duration_sec": 0.0}
	var real_sec := real_duration_estimate(from_id, to_id)
	var distance_km: float = TravelCalc.estimate(from_id, to_id).get("distance_km", 0.0)
	var gameplay_duration := TravelCalc.compress_by_tier_reach(distance_km, tier)
	var motion_target := maxf(
			gameplay_duration - TravelCalc.DEPARTURE_HOLD_SECONDS - TravelCalc.ARRIVAL_HOLD_SECONDS, 1.0)
	var accel_km_s2 := (distance_km * 4.0) / (motion_target * motion_target)
	return {"accel_km_s2": accel_km_s2, "cruise_cap_km_s": 0.0, "real_duration_sec": real_sec}


# What a from_id -> to_id trip would take under the ship's current
# effective engine tier's REAL physics (_effective_engine_tier) — 0.0 if no
# valid tier resolves (defensive only, see that function's comment). Scaled
# by the tier's own real_time_scale (see TravelCalc.ENGINE_TIERS) — display
# only, corrects how unrealistically fast the raw accel/cap ladder reads at
# interplanetary range without touching the accel/cap values that actually
# drive gameplay pacing.
func real_duration_estimate(from_id: String, to_id: String) -> float:
	var tier_index := _effective_engine_tier()
	if tier_index < 0 or tier_index >= TravelCalc.ENGINE_TIERS.size():
		return 0.0
	var tier: Dictionary = TravelCalc.ENGINE_TIERS[tier_index]
	var est := TravelCalc.estimate(from_id, to_id, tier["accel_km_s2"], tier["cruise_cap_km_s"])
	var scale: float = tier.get("real_time_scale", 1.0)
	return est["duration_sec"] * scale


func set_engine_tier(tier: int) -> void:
	engine_tier_override = tier


# Autoloads persist across change_scene_to_file (that's the whole point of
# them), which means a stale trip/location from a PREVIOUS session survives
# straight into a fresh "New Game" otherwise — MainMenu._on_new_game calls
# this before handing off to the boot sequence. Emits location_changed so
# any already-built persistent UI (ConsolePanel lives in the HUD autoload,
# not the scene being replaced) picks up the reset immediately rather than
# showing stale text until something else happens to refresh it.
func reset_for_new_game() -> void:
	location_id = "Earth"
	current_year = 2037.0
	is_traveling = false
	travel_target_id = ""
	travel_duration = 0.0
	travel_elapsed = 0.0
	travel_distance_km = 0.0
	travel_accel_km_s2 = TravelCalc.ENGINE_ACCEL_KM_S2
	travel_cruise_cap_km_s = 0.0
	travel_real_duration_sec = 0.0
	engine_tier_override = -1
	location_changed.emit()


# Locks the given id as the destination and starts the trip in one call —
# the shared "commit to this destination" action every GO button routes
# through. Returns false (no-op) under the same conditions start_travel
# already no-ops on, so callers can use the return value to decide whether
# to follow up with a scene transition (e.g. HUD.go_to the cockpit).
func travel_to(id: String) -> bool:
	if is_traveling or id == location_id or id == "":
		return false
	# No real Beyond Light Engine yet (owned_tier 0, "None") -> refuse an
	# interstellar trip outright rather than silently falling back to
	# resolve_travel_engine's defensive ENGINE_ACCEL_KM_S2 shape, which
	# would fly a genuinely interstellar distance at ordinary in-system
	# gameplay pacing (i.e. a light-year trip "completing" in seconds).
	if _is_interstellar(location_id, id) and _beyond_light_tier_index() < 0:
		return false
	Destination.lock(id)
	start_travel(id)
	return true


func travel_progress() -> float:
	if not is_traveling or travel_duration <= 0.0:
		return 0.0
	return clampf(travel_elapsed / travel_duration, 0.0, 1.0)


func travel_remaining() -> float:
	if not is_traveling:
		return 0.0
	return maxf(travel_duration - travel_elapsed, 0.0)


# Live, continuously-interpolated calendar reading while a trip is active —
# current_year itself only ever changes atomically on actual arrival (see
# _process below), and it holds the DEPARTURE-time value for the entire
# trip in between (nothing else touches it mid-flight), so that's exactly
# the base this counts up FROM. Scaled by the same flight_progress fraction
# (real distance covered so far, accounting for the departure hold) every
# other live in-flight readout already reads — ShipStatusStrip's SPEED/
# DISTANCE, Cockpit's own camera curve — so the calendar visibly ticks up in
# sync with the ship's actual motion instead of sitting frozen and then
# jumping the instant travel_completed fires. Equal to plain current_year
# whenever not traveling (progress is moot, nothing to interpolate).
func live_current_year() -> float:
	if not is_traveling:
		return current_year
	var motion_elapsed := maxf(travel_elapsed - TravelCalc.DEPARTURE_HOLD_SECONDS, 0.0)
	var progress := TravelCalc.flight_progress(
			travel_distance_km, motion_elapsed, travel_accel_km_s2, travel_cruise_cap_km_s)
	return current_year + TravelCalc.years_for_distance_km(travel_distance_km) * progress


func _process(delta: float) -> void:
	if not is_traveling:
		return
	travel_elapsed += delta
	if travel_elapsed >= travel_duration:
		location_id = travel_target_id
		travel_target_id = ""
		is_traveling = false
		# Arrival is the zero-distance case of Nav Scan's own radius rule
		# (2026-07-19 design call, see NavScan.gd) — wherever you actually
		# are is always revealed, no scan required for the one body you're
		# standing on. Harmless no-op for anything already revealed (Sol,
		# or a body a previous Nav Scan already found). Without this, a
		# planet reached by LOCKing an unrevealed blip and GOing straight
		# there (skipping Nav Scan entirely) would stay marked unrevealed
		# even after you'd physically arrived — the bug a player hit via
		# ViewSwitcher's PLANETARY tab, which resolves to "whatever planet
		# you're currently orbiting" and expects that planet to already be
		# known.
		Discoveries.mark_scanned(location_id)
		# See current_year's own comment — advances by this trip's real
		# distance regardless of trip type; travel_distance_km is still the
		# just-completed trip's value here, read before anything below could
		# reset it for a next one.
		current_year += TravelCalc.years_for_distance_km(travel_distance_km)
		travel_completed.emit()
		location_changed.emit()
