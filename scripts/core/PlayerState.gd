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
var is_traveling: bool = false
var travel_target_id: String = ""
var travel_duration: float = 0.0
var travel_elapsed: float = 0.0
var travel_distance_km: float = 0.0  # real distance for the CURRENT trip — see TravelCalc; Cockpit derives a live speed readout from this against travel_duration
# The accel/cap that actually flies the ship for the CURRENT trip — see
# start_travel/resolve_travel_engine. With no tier pinned this is just
# ENGINE_ACCEL_KM_S2 uncapped, exactly like before tiers existed. With a
# tier pinned, this is a GAMEPLAY-scale accel solved so the trip's own
# burn_duration lands on TravelCalc.compress_by_tier_reach's compressed
# number — NOT the tier's own real accel/cap directly (that was tried
# 2026-07-11 and immediately broken: pinning Tier 0 made an actual Moon
# trip take real DAYS of wall-clock waiting). The tier's real accel/cap
# only ever feeds travel_real_duration_sec below, never the camera.
var travel_accel_km_s2: float = TravelCalc.ENGINE_ACCEL_KM_S2
var travel_cruise_cap_km_s: float = 0.0

# What THIS SAME trip takes under the tier's REAL (physically-grounded)
# physics — display-only (the "(REAL: ...)" annotation in ConsolePanel),
# computed alongside travel_duration in start_travel but never fed into the
# actual flight. 0.0 when no tier is selected (engine_tier_override == -1),
# meaning there's nothing "real" to show. See the travel-time-scale
# brainstorm in parallax-core-design-decisions memory.
var travel_real_duration_sec: float = 0.0

# Cheat menu (F2 in HUD) — pins the ship to one of TravelCalc.ENGINE_TIERS.
# -1 = off, use ENGINE_ACCEL_KM_S2 uncapped exactly like before tiers
# existed. Applied at the moment a trip STARTS (see start_travel), not
# retroactively to one already in progress — changing tiers mid-flight just
# means the next GO gets it.
var engine_tier_override: int = -1


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
# current engine_tier_override — shared by start_travel (the real snapshot)
# and ConsolePanel's not-yet-departed ETA preview, so the preview never
# shows a number GO doesn't honor.
#
# No tier pinned: the fixed gameplay-pacing default, unchanged from before
# tiers existed.
#
# Tier pinned: the tier's REAL accel/cap (see ENGINE_TIERS) computes this
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
func resolve_travel_engine(from_id: String, to_id: String) -> Dictionary:
	if engine_tier_override < 0 or engine_tier_override >= TravelCalc.ENGINE_TIERS.size():
		return {"accel_km_s2": TravelCalc.ENGINE_ACCEL_KM_S2, "cruise_cap_km_s": 0.0, "real_duration_sec": 0.0}
	var real_sec := real_duration_estimate(from_id, to_id)
	var distance_km: float = TravelCalc.estimate(from_id, to_id).get("distance_km", 0.0)
	var gameplay_duration := TravelCalc.compress_by_tier_reach(distance_km, engine_tier_override)
	var motion_target := maxf(
			gameplay_duration - TravelCalc.DEPARTURE_HOLD_SECONDS - TravelCalc.ARRIVAL_HOLD_SECONDS, 1.0)
	var accel_km_s2 := (distance_km * 4.0) / (motion_target * motion_target)
	return {"accel_km_s2": accel_km_s2, "cruise_cap_km_s": 0.0, "real_duration_sec": real_sec}


# What a from_id -> to_id trip would take under the currently cheat-menu-
# selected engine tier's REAL physics — 0.0 if no tier is selected.
func real_duration_estimate(from_id: String, to_id: String) -> float:
	if engine_tier_override < 0 or engine_tier_override >= TravelCalc.ENGINE_TIERS.size():
		return 0.0
	var tier: Dictionary = TravelCalc.ENGINE_TIERS[engine_tier_override]
	var est := TravelCalc.estimate(from_id, to_id, tier["accel_km_s2"], tier["cruise_cap_km_s"])
	return est["duration_sec"]


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


func _process(delta: float) -> void:
	if not is_traveling:
		return
	travel_elapsed += delta
	if travel_elapsed >= travel_duration:
		location_id = travel_target_id
		travel_target_id = ""
		is_traveling = false
		travel_completed.emit()
		location_changed.emit()
