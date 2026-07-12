extends Node

# Two-player crossfading ambient bed — same shape as MusicManager's own
# crossfade, kept as a separate manager (and separate "Ambient" bus, see
# default_bus_layout.tres) since this is a continuous environmental loop
# keyed to "which kind of view is up" rather than MusicManager's per-scene
# score tracks. System/Planetary System both play "map_ambient"; Cockpit
# plays "ship_ambient". Calling play_*() with whichever's already active is
# a no-op (see _play_from), so toggling between System <-> Planetary System
# (two separate scene loads, each calling play_map_ambient() in _ready())
# never restarts or refades the loop underneath.

const AMBIENT_BASE := "res://Assets/ambient/"
const CROSSFADE_TIME := 1.2

var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active: AudioStreamPlayer
var _fading: AudioStreamPlayer

var _fade_timer := 0.0
var _fading_out := false
var _current_track := ""


func _ready() -> void:
	_player_a = _make_player()
	_player_b = _make_player()
	_active = _player_a
	_fading = _player_b


func _process(delta: float) -> void:
	if not _fading_out:
		return
	_fade_timer += delta
	var t := clampf(_fade_timer / CROSSFADE_TIME, 0.0, 1.0)
	_active.volume_db = linear_to_db(t)
	_fading.volume_db = linear_to_db(1.0 - t)
	if t >= 1.0:
		_fading.stop()
		_fading.volume_db = 0.0
		_fading_out = false


# --- Public API ---

# System/Planetary System's shared ambient bed — call from both views' own
# _ready().
func play_map_ambient() -> void:
	_play_from("map_ambient")


# Cockpit's ambient bed — call from Cockpit._ready().
func play_ship_ambient() -> void:
	_play_from("ship_ambient")


func stop(fade: bool = true) -> void:
	_current_track = ""
	if fade:
		_crossfade_to(null)
	else:
		_active.stop()
		_fading.stop()


# --- Internal ---

func _play_from(track_name: String) -> void:
	if _current_track == track_name:
		return
	var stream := _load(track_name)
	if stream == null:
		return
	_current_track = track_name
	_crossfade_to(stream)


func _crossfade_to(stream: AudioStream) -> void:
	var temp := _active
	_active = _fading
	_fading = temp

	_fading.volume_db = linear_to_db(1.0 - clampf(_fade_timer / CROSSFADE_TIME, 0.0, 1.0)) if _fading_out else 0.0

	if stream != null:
		_active.stream = stream
		_active.volume_db = linear_to_db(0.0)
		_active.play()

	_fade_timer = 0.0
	_fading_out = true


func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Ambient"
	add_child(p)
	return p


func _load(track_name: String) -> AudioStream:
	for ext: String in ["ogg", "wav"]:
		var full := AMBIENT_BASE + track_name + "." + ext
		if ResourceLoader.exists(full):
			var stream: AudioStream = ResourceLoader.load(full)
			if stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = true
			elif stream is AudioStreamWAV:
				(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			return stream
	push_warning("AmbientManager: ambient track not found — %s" % track_name)
	return null
