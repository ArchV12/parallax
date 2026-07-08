extends Node

# One-shot SFX pool. No audio assets exist yet — play() warns and no-ops on
# a missing file, so callers can wire up sounds before the files arrive.

# Pool size — max simultaneous overlapping sounds.
const POOL_SIZE := 12
const SFX_BASE := "res://assets/sfx/"

var _pool: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}  # path -> AudioStream

func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)


# play("ui/button_click") — omit extension; tries .wav then .ogg.
func play(sfx_path: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream := _load(sfx_path)
	if stream == null:
		push_warning("AudioManager: sfx not found — %s" % sfx_path)
		return
	var player := _get_free_player()
	if player == null:
		return
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


# Stops any currently-playing instance of this sfx — for repeating/interruptible
# sounds that need to cut off immediately rather than ring out to their
# natural end.
func stop(sfx_path: String) -> void:
	var stream: AudioStream = _cache.get(sfx_path)
	if stream == null:
		return
	for p in _pool:
		if p.stream == stream and p.playing:
			p.stop()


func _load(sfx_path: String) -> AudioStream:
	if _cache.has(sfx_path):
		return _cache[sfx_path]
	for ext in ["wav", "ogg"]:
		var full: String = SFX_BASE + sfx_path + "." + ext
		if ResourceLoader.exists(full):
			var stream: AudioStream = ResourceLoader.load(full)
			_cache[sfx_path] = stream
			return stream
	_cache[sfx_path] = null  # cache miss so we don't re-scan every call
	return null


func _get_free_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	# All busy — steal the one that started earliest (longest running).
	var oldest: AudioStreamPlayer = _pool[0]
	for p in _pool:
		if p.get_playback_position() > oldest.get_playback_position():
			oldest = p
	oldest.stop()
	return oldest
