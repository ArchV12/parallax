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
var travel_accel_multiplier: float = 1.0  # the multiplier ACTUALLY used for the current trip's flight_profile — see start_travel; NOT the same as re-reading cheat_engine_enabled live, which could've been toggled since departure

# Testing cheat — F2 in HUD toggles this. Applied at the moment a trip
# STARTS (see start_travel), not retroactively to one already in progress —
# toggling mid-flight just means the next GO gets it.
var cheat_engine_enabled: bool = false


func start_travel(target_id: String) -> void:
	if is_traveling or target_id == location_id:
		return
	travel_accel_multiplier = TravelCalc.CHEAT_ENGINE_MULTIPLIER if cheat_engine_enabled else 1.0
	var est := TravelCalc.estimate(location_id, target_id, travel_accel_multiplier)
	travel_target_id = target_id
	travel_duration = est["duration_sec"]
	travel_distance_km = est["distance_km"]
	travel_elapsed = 0.0
	is_traveling = true
	travel_started.emit()


func toggle_cheat_engine() -> void:
	cheat_engine_enabled = not cheat_engine_enabled


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
	travel_accel_multiplier = 1.0
	cheat_engine_enabled = false
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
