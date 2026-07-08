extends Node

# Two-player crossfading music. No music assets exist yet — _play_from()
# silently no-ops when the track file is missing, so play_menu() is safe to
# call now and starts working the day a track lands in assets/music/.

const FADE_TIME  := 2.0
const MUSIC_BASE := "res://assets/music/"

var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active: AudioStreamPlayer
var _fading: AudioStreamPlayer

var _fade_timer:    float  = 0.0
var _fading_out:    bool   = false
var _current_track: String = ""


func _ready() -> void:
	_player_a = _make_player()
	_player_b = _make_player()
	_active = _player_a
	_fading = _player_b
	_apply_saved_volumes()


func _apply_saved_volumes() -> void:
	const PREFS_PATH := "user://prefs.json"
	if not FileAccess.file_exists(PREFS_PATH):
		return
	var file := FileAccess.open(PREFS_PATH, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var prefs: Dictionary = parsed as Dictionary
	_set_bus_vol("Music", prefs.get("music_volume", 0.2))
	_set_bus_vol("SFX",   prefs.get("sfx_volume",   1.0))


func _set_bus_vol(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))


func _process(delta: float) -> void:
	if not _fading_out:
		return
	_fade_timer += delta
	var t := clampf(_fade_timer / FADE_TIME, 0.0, 1.0)
	_active.volume_db = linear_to_db(t)
	_fading.volume_db = linear_to_db(1.0 - t)
	if t >= 1.0:
		_fading.stop()
		_fading.volume_db = 0.0
		_fading_out = false


# --- Public API ---

func play_menu() -> void:
	_play_from("Menu")


func stop(fade: bool = true) -> void:
	_current_track = ""
	if fade:
		_crossfade_to(null)
	else:
		_active.stop()
		_fading.stop()


func set_volume(volume_db: float) -> void:
	_player_a.volume_db = volume_db
	_player_b.volume_db = volume_db


# --- Internal ---

func _play_from(track_name: String) -> void:
	if _current_track == track_name:
		return
	var stream := _load_track(track_name)
	if stream == null:
		return
	_current_track = track_name
	_crossfade_to(stream)


# Tries ogg → wav → mp3 for res://assets/music/<name>.<ext>
func _load_track(track_name: String) -> AudioStream:
	for ext: String in ["ogg", "wav", "mp3"]:
		var path := MUSIC_BASE + track_name + "." + ext
		if ResourceLoader.exists(path):
			var stream: AudioStream = ResourceLoader.load(path)
			if stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = true
			elif stream is AudioStreamWAV:
				(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			return stream
	return null


func _crossfade_to(stream: AudioStream) -> void:
	var temp := _active
	_active = _fading
	_fading = temp

	_fading.volume_db = linear_to_db(1.0 - clampf(_fade_timer / FADE_TIME, 0.0, 1.0)) if _fading_out else 0.0

	if stream != null:
		_active.stream = stream
		_active.volume_db = linear_to_db(0.0)
		_active.play()

	_fade_timer = 0.0
	_fading_out = true


func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = 0.0
	add_child(p)
	return p
