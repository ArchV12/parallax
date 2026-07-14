extends Node

# Single source of truth for which physical keys drive movement — WASD or
# ESDF (the same diamond shifted one column right: E/S/D/F instead of
# W/A/S/D, keeping the same relative finger positions but freeing up Q/W/A/Z
# for other bindings — the alternative some players prefer over WASD).
# Every movement-key consumer (SystemView's free-fly, Cockpit's roll) reads
# through the is_*_pressed() queries below instead of hardcoding
# KEY_W/A/S/D directly, so switching schemes in Options updates all of them
# at once, live, mid-session — nothing needs to be rebuilt (see OptionsUI's
# CONTROLS dropdown).

signal scheme_changed

const PREFS_PATH := "user://prefs.json"

enum Scheme { WASD, ESDF }

const DEFAULT_SCHEME := Scheme.WASD

var scheme: Scheme = DEFAULT_SCHEME


func _ready() -> void:
	scheme = _load_saved_scheme()


func set_scheme(s: Scheme) -> void:
	if s == scheme:
		return
	scheme = s
	_save_scheme(s)
	scheme_changed.emit()


func scheme_names() -> Array[String]:
	return ["WASD", "ESDF"]


# --- Direction queries ---
# "Left"/"right" deliberately cover BOTH a strafe key (SystemView's
# free-fly) and a roll key (Cockpit — A/D today, S/F under ESDF) — rolling a
# spacecraft left/right and strafing left/right are the same physical keys
# in either scheme, so one pair of queries serves both consumers.

func is_forward_pressed() -> bool:
	return Input.is_physical_key_pressed(KEY_E if scheme == Scheme.ESDF else KEY_W)


func is_back_pressed() -> bool:
	return Input.is_physical_key_pressed(KEY_D if scheme == Scheme.ESDF else KEY_S)


func is_left_pressed() -> bool:
	return Input.is_physical_key_pressed(KEY_S if scheme == Scheme.ESDF else KEY_A)


func is_right_pressed() -> bool:
	return Input.is_physical_key_pressed(KEY_F if scheme == Scheme.ESDF else KEY_D)


func _load_saved_scheme() -> Scheme:
	var prefs := _read_prefs()
	var idx: int = int(prefs.get("movement_keys", DEFAULT_SCHEME))
	if idx < 0 or idx >= Scheme.values().size():
		return DEFAULT_SCHEME
	return idx as Scheme


func _save_scheme(s: Scheme) -> void:
	var prefs := _read_prefs()
	prefs["movement_keys"] = int(s)
	var file := FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(prefs))


func _read_prefs() -> Dictionary:
	if not FileAccess.file_exists(PREFS_PATH):
		return {}
	var file := FileAccess.open(PREFS_PATH, FileAccess.READ)
	if not file:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}
