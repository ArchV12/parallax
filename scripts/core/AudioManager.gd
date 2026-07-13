extends Node

# One-shot SFX pool. No audio assets exist yet — play() warns and no-ops on
# a missing file, so callers can wire up sounds before the files arrive.

# Pool size — max simultaneous overlapping sounds.
const POOL_SIZE := 12
const SFX_BASE := "res://Assets/sfx/"

var _pool: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}  # path -> AudioStream
var _warned: Dictionary = {}  # path -> true — a missing sfx only warns once, not on every call

# The travel loop (see travel below) runs continuously for the whole cruise,
# not a one-shot — it needs its own dedicated player so the pool's
# oldest-steals-newest logic in _get_free_player() can never cut it off to
# make room for an unrelated button click or scanner blip mid-flight.
var _travel_player: AudioStreamPlayer

# Same reasoning as _travel_player, for the mining loop (see mining_start
# below) — a continuous operation that can run for many minutes, never
# stolen by the pool.
var _mining_player: AudioStreamPlayer
# Guards _start_mining_loop against firing after mining_end() already
# stopped it — mining_start()'s overlap timer (see MINING_OVERLAP_SECONDS)
# schedules the loop to begin a fraction of a second in the future, and
# mining can end faster than that (a quick STOP, or an already-nearly-
# depleted deposit finishing off).
var _mining_active := false

func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_travel_player = AudioStreamPlayer.new()
	_travel_player.bus = "SFX"
	add_child(_travel_player)
	_mining_player = AudioStreamPlayer.new()
	_mining_player.bus = "SFX"
	add_child(_mining_player)


# play("ui/button_click") — omit extension; tries .wav then .ogg. Returns the
# player the sfx was started on (null if the asset is missing) — launch()
# below uses this to chain the travel loop off the launch cue's own
# `finished` signal.
func play(sfx_path: String, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	var stream := _load(sfx_path)
	if stream == null:
		if not _warned.has(sfx_path):
			_warned[sfx_path] = true
			push_warning("AudioManager: sfx not found — %s" % sfx_path)
		return null
	var player := _get_free_player()
	if player == null:
		return null
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()
	return player


# --- UI semantic sounds ---
# Every UIButton/UIPanel routes through these instead of hardcoding a path —
# sound design changes happen in one place. ui_confirm() has a real asset
# (button_general.ogg, directly under Assets/sfx/ — not the ui/ subfolder
# the rest of these use) and works today; the others don't have files yet,
# but play() no-ops gracefully on a missing asset, so they're safe to call
# now and will start working the day their sfx land in Assets/sfx/ui/.

func ui_hover() -> void:
	play("ui/hover", -6.0)


# The default press sound for every button in the game (UIButton,
# ConsolePadButton, and the couple of raw Buttons in LocationsPanel all
# route through this) — button_general.ogg. `sfx_path` lets a specific
# button override it with a different sound entirely (see UIButton.press_sfx/
# ConsolePadButton.press_sfx) while still going through the same call site.
# Pitch is randomized +/-20% ONLY for the plain button_general click — a
# generic click benefits from that variation so a rapid run of them doesn't
# sound identical, but an overridden sfx_path (go_button, lock_button, ...)
# is a deliberately distinct, branded cue and should always play true, not
# get randomly detuned along with it.
func ui_confirm(sfx_path: String = "button_general") -> void:
	var pitch := randf_range(0.8, 1.2) if sfx_path == "button_general" else 1.0
	play(sfx_path, 0.0, pitch)


func ui_deny() -> void:
	play("ui/deny")


func ui_panel_open() -> void:
	play("ui/panel_open")


func ui_panel_close() -> void:
	play("ui/panel_close")


# --- Flight sounds ---

# How much of the travel loop's start overlaps the tail of launch.ogg —
# starting it only once launch.ogg fully finishes read as two disjoint
# sounds; starting it this far before launch.ogg ends instead blends them
# into one continuous cue (launch swoosh building into the cruise loop).
const LAUNCH_OVERLAP_SECONDS := 0.6

# The very start of a trip — fired once, right as _play_departure_maneuver
# begins (the "Orienting to Target" hold, before the departure maneuver's
# own rotation tween or the acceleration burn that follows it). Has a real
# asset (launch.ogg). Schedules the looping travel() cue to start
# LAUNCH_OVERLAP_SECONDS before launch.ogg's own runtime ends, so the two
# overlap rather than playing back to back.
func launch() -> void:
	var player := play("launch")
	if player != null and player.stream != null:
		var launch_length: float = player.stream.get_length()
		var delay := maxf(launch_length - LAUNCH_OVERLAP_SECONDS, 0.0)
		get_tree().create_timer(delay).timeout.connect(_start_travel_loop)
	else:
		# No launch asset to time the overlap against — start the loop
		# immediately rather than silently dropping it for the whole trip.
		_start_travel_loop()


# The looping cruise sound — started automatically once launch() finishes
# (see above), not called directly. Runs on its own dedicated player (not
# the pool) since it needs to keep looping for the whole flight.
func _start_travel_loop() -> void:
	var stream := _load("travelling")
	if stream == null:
		if not _warned.has("travelling"):
			_warned["travelling"] = true
			push_warning("AudioManager: sfx not found — travelling")
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_travel_player.stream = stream
	_travel_player.play()


# Cuts the travel loop — call right as the ship comes to its full stop
# prior to orbital insertion (see Cockpit.gd's _process, the moment
# TravelCalc.flight_progress first reaches 1.0), not on travel_completed —
# that fires only after ARRIVAL_HOLD_SECONDS' full-stop pause has already
# elapsed, well after the sound should have already changed over.
func stop_travel_loop() -> void:
	_travel_player.stop()


# The ship reaching a genuine dead stop, right before the arrival hold/
# orbital insertion lean begins — see stop_travel_loop's comment for exactly
# when this fires. Cuts the travel loop and plays the one-shot stop cue.
func arrival_stop() -> void:
	stop_travel_loop()
	play("arrival_stop")


# Cockpit's departure maneuver (see DEPARTURE_MANEUVER_TIME/
# _play_departure_maneuver in Cockpit.gd) — fired once, right as the ship
# starts rotating onto its heading, same moment as launch() above. No asset
# yet; safe to call now, same as every other sound here.
func engine_power_up() -> void:
	play("engine/power_up")


# --- Mining sounds ---
# Same start-cue/looping-cruise/stop shape as the Flight sounds above
# (launch/_start_travel_loop/stop_travel_loop) — a continuous operation
# needs the same "one-shot spin-up blending into a loop" treatment a trip
# does.

# How much of mining-start.ogg's tail overlaps the beginning of mining-loop.
# ogg — see LAUNCH_OVERLAP_SECONDS' own comment for why (blends into one
# continuous cue instead of playing back to back).
const MINING_OVERLAP_SECONDS := 0.6

# Fired once, the instant a mining operation actually starts (see
# HUD._on_operation_started) — has a real asset (mining-start.ogg).
# Schedules the looping mining_loop cue to start MINING_OVERLAP_SECONDS
# before mining-start.ogg's own runtime ends.
func mining_start() -> void:
	_mining_active = true
	var player := play("mining-start")
	if player != null and player.stream != null:
		var start_length: float = player.stream.get_length()
		var delay := maxf(start_length - MINING_OVERLAP_SECONDS, 0.0)
		get_tree().create_timer(delay).timeout.connect(_start_mining_loop)
	else:
		# No start asset to time the overlap against — start the loop
		# immediately rather than silently dropping it for the whole operation.
		_start_mining_loop()


# The looping "extracting" cue — started automatically once mining_start()
# finishes (see above), not called directly. Runs on its own dedicated
# player (not the pool) since it needs to keep looping for however long the
# operation runs (potentially many minutes — see Deposits.DEPLETE_SECONDS_
# BY_SIZE).
func _start_mining_loop() -> void:
	if not _mining_active:
		return  # mining_end() already fired before this delayed callback ran
	var stream := _load("mining-loop")
	if stream == null:
		if not _warned.has("mining-loop"):
			_warned["mining-loop"] = true
			push_warning("AudioManager: sfx not found — mining-loop")
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_mining_player.stream = stream
	_mining_player.play()


# Cuts the mining loop and plays the one-shot end cue — fired once, the
# instant a mining operation ends, for ANY of its three causes (player STOP,
# departure, full depletion — see Operations.operation_stopped and
# HUD._on_operation_stopped, the single call site for this regardless of
# which cause it was).
func mining_end() -> void:
	_mining_active = false
	_mining_player.stop()
	play("mining-end")


# --- Boot sequence sounds ---

func boot_tone() -> void:
	play("boot/tone", -8.0)


func boot_confirm() -> void:
	play("access_granted")


# Terminal-style typing click, meant to be retriggered rapidly as text types
# on — a little pitch wobble keeps a fast run of clicks from sounding like
# one clip stuttering.
func type_char() -> void:
	play("type_char", -10.0, randf_range(0.92, 1.08))


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
