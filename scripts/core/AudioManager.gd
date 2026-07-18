extends Node

# One-shot SFX pool. No audio assets exist yet — play() warns and no-ops on
# a missing file, so callers can wire up sounds before the files arrive.

# Pool size — max simultaneous overlapping sounds.
const POOL_SIZE := 12
const SFX_BASE := "res://Assets/sfx/"
const VO_BASE := "res://Assets/voiceover/"

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

# Same reasoning as _mining_player, for the survey ambient (see
# start_survey_ambient below) — needs its own dedicated player so the pool
# can't steal it out from under stop_survey_ambient(). Burst-scoped now
# (Docs/Arrival Scan System.md): ArrivalScanRow starts/stops this once per
# arrival, not once per individual Survey — see that function's own comment.
var _survey_player: AudioStreamPlayer

# Same reasoning again, for the "Incoming Earth Transmission" button's loop
# (EarthTransmissionBanner) — needs to keep looping for however long the
# button sits unclicked (could be a while), never stolen by the pool.
var _incoming_transmission_player: AudioStreamPlayer

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
	_survey_player = AudioStreamPlayer.new()
	_survey_player.bus = "SFX"
	add_child(_survey_player)
	_incoming_transmission_player = AudioStreamPlayer.new()
	_incoming_transmission_player.bus = "SFX"
	add_child(_incoming_transmission_player)


# play("ui/button_click") — omit extension; tries .wav then .ogg. Returns the
# player the sfx was started on (null if the asset is missing) — launch()
# below uses this to chain the travel loop off the launch cue's own
# `finished` signal. `base`/`bus` default to SFX_BASE/"SFX"; play_vo() below
# passes VO_BASE/"Voice" instead so ship-computer lines live in their own
# Assets/voiceover/ folder and mix on their own bus (its own Options slider,
# see OptionsUI) without needing a second copy of this function.
func play(sfx_path: String, volume_db: float = 0.0, pitch: float = 1.0, base: String = SFX_BASE, bus: String = "SFX") -> AudioStreamPlayer:
	var stream := _load(sfx_path, base)
	if stream == null:
		if not _warned.has(base + sfx_path):
			_warned[base + sfx_path] = true
			push_warning("AudioManager: sfx not found — %s" % (base + sfx_path))
		return null
	# Pooled one-shots must never loop, no matter how the source asset was
	# authored/exported — looping is exclusively the job of the three
	# dedicated continuous players (_travel_player/_mining_player/
	# _survey_player), which set stream.loop themselves and explicitly stop
	# it. _load() caches and reuses the SAME AudioStream resource across
	# every call, so a file with loop metadata baked in (confirmed: this is
	# why survey_complete.ogg was repeating on every reveal even though
	# play_vo() itself was only ever called once per burst — see the Arrival
	# Scan System bugfix conversation) would otherwise repeat forever on
	# whichever pooled player it landed on, since nothing else in this
	# one-shot path ever stops it.
	if stream is AudioStreamOggVorbis:
		stream.loop = false
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	var player := _get_free_player()
	if player == null:
		return null
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.bus = bus
	player.play()
	return player


# Same as play(), pointed at Assets/voiceover/ and the Voice bus instead of
# Assets/sfx/ and SFX — the ship computer's spoken lines (see the "Ship
# computer voiceover" section below). Kept as a thin wrapper rather than
# folding callers over to play() directly so call sites read as "this is a
# VO line," not a generic sfx.
func play_vo(vo_path: String, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	return play(vo_path, volume_db, pitch, VO_BASE, "Voice")


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
# Pitch is randomized +/-5% ONLY for the plain button_general click — a
# generic click benefits from that variation so a rapid run of them doesn't
# sound identical, but an overridden sfx_path (go_button, lock_button, ...)
# is a deliberately distinct, branded cue and should always play true, not
# get randomly detuned along with it.
func ui_confirm(sfx_path: String = "button_general") -> void:
	var pitch := randf_range(0.95, 1.05) if sfx_path == "button_general" else 1.0
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


# --- Survey sounds ---
# The Arrival Scan System (Docs/Arrival Scan System.md) fires up to 5
# Surveys in parallel per arrival, each resolving at its own native-rate-
# driven pace — so unlike Flight/Mining above, the ambient LOOP is scoped to
# the whole burst (one start_survey_ambient/stop_survey_ambient pair per
# arrival, called by ArrivalScanRow), while survey_start()/survey_complete()
# stay one-shot cues fired per individual Survey (HUD._on_operation_started/
# _on_operation_completed) — a short chirp/ding per bar is a nice per-bar
# beat; restarting or cutting the shared ambient per bar was the actual bug
# (the first bar to resolve was killing the loop while 4 others still spun).

# Fired once per Survey op actually starting — a short "sensor activating"
# chirp, safe to overlap across several bars starting together (pooled, not
# the dedicated ambient player below).
func survey_start() -> void:
	play("survey_start")


# One shared ambient loop for the WHOLE scan burst — called once by
# ArrivalScanRow when a burst begins, not per Survey. Idempotent: a second
# call while already playing (e.g. a mid-visit rescan starting while an
# earlier one somehow hasn't resolved yet) is a no-op rather than
# restarting the loop out from under itself.
func start_survey_ambient() -> void:
	if _survey_player.playing:
		return
	var stream := _load("survey")
	if stream == null:
		if not _warned.has("survey"):
			_warned["survey"] = true
			push_warning("AudioManager: sfx not found — survey")
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_survey_player.stream = stream
	_survey_player.play()


# Counterpart to start_survey_ambient — called once by ArrivalScanRow when
# the LAST bar in a burst resolves, not per Survey.
func stop_survey_ambient() -> void:
	_survey_player.stop()


# Loops sfx/incoming_transmission.ogg for as long as EarthTransmissionBanner's
# "Incoming Earth Transmission" button is showing (started when it becomes
# visible, stopped the instant it's clicked or the queue is emptied out from
# under it). Idempotent like start_survey_ambient — a second call while
# already playing is a no-op, not a restart.
func start_incoming_transmission_loop() -> void:
	if _incoming_transmission_player.playing:
		return
	var stream := _load("incoming_transmission")
	if stream == null:
		if not _warned.has("incoming_transmission"):
			_warned["incoming_transmission"] = true
			push_warning("AudioManager: sfx not found — incoming_transmission")
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_incoming_transmission_player.stream = stream
	_incoming_transmission_player.play()


func stop_incoming_transmission_loop() -> void:
	_incoming_transmission_player.stop()


# Fired once per Survey op resolving — the one-shot completion ding, safe to
# overlap across several bars resolving close together (pooled). The
# ambient loop itself is a separate, burst-scoped concern (see
# stop_survey_ambient above).
func survey_complete() -> void:
	play("survey_complete")


# --- Boot sequence sounds ---

func boot_tone() -> void:
	play("boot/tone", -8.0)


func boot_confirm() -> void:
	play("access_granted")


# Fired once, right as BootSequence hands off to the cockpit (_finish) —
# the ship coming to life under its new commander, timed to the long
# COCKPIT_REVEAL_TIME fade-in rather than the snappy default view-switch fade.
func ship_startup() -> void:
	play("ship_startup")


# Terminal-style typing click, meant to be retriggered rapidly as text types
# on — a little pitch wobble keeps a fast run of clicks from sounding like
# one clip stuttering.
func type_char() -> void:
	play("type_char", -10.0, randf_range(0.92, 1.08))


# --- Ship computer voiceover ---
# Spoken lines from Assets/voiceover/, routed through play_vo() instead of
# play() so they're loaded from their own folder (see VO_BASE/play_vo above).

# Fired once BootSequence's cockpit fade-in has fully resolved — see
# HUD.go_to's on_revealed callback param, and BootSequence._finish, its only
# caller.
func good_morning() -> void:
	play_vo("good_morning")


# Fired alongside the "CARGO FULL" toast — see HUD._on_operation_stopped,
# the "cargo_full" reason arm (matches AudioManager.mining_end, already
# firing there for the sfx side of the same event).
func cargo_full() -> void:
	play_vo("cargo_full")


# Fired the instant a destination is actually locked (not on unlock) — see
# LockButton._on_pressed.
func target_locked() -> void:
	play_vo("target_locked")


# Fired the instant a trip resolves — see Cockpit._on_travel_completed,
# alongside _begin_orbit_settle.
func destination_reached() -> void:
	play_vo("destination_reached")


# Fired once per arrival by ArrivalScanRow.refresh_for_arrival, right before
# the parallel scan bars start filling — only when at least one Survey
# actually started (see Operations.start_all_surveys's return), not on a
# pure-recap revisit with nothing new to learn.
func scans_initiated() -> void:
	play_vo("scans_initiated")


# Fired on a completed construction — see HUD._on_structure_constructed,
# listening to Buildings.structure_constructed (fires for both a new build
# and a tier upgrade; this VO line plays for either).
func construction_complete() -> void:
	play_vo("construction_complete")


# Fired once per arrival BURST by ArrivalScanRow._reveal_card, once every
# card has resolved — not per individual Survey (see that function's own
# comment on why: this used to be named survey_complete_vo() with an asset
# key of "survey_complete", the exact same key AudioManager.survey_complete()
# (the short per-bar ding, still SFX_BASE, unrelated) used — a real asset
# ended up misplaced in the sfx folder under that shared name, which is
# exactly the bug that prompted renaming this to scans_complete/"scans_complete"
# instead: a name that can never collide with the sfx cue again.
func scans_complete() -> void:
	play_vo("scans_complete")


# Fired right alongside scans_complete(), but only when the just-
# resolved survey's own category actually rolled an anomaly at that body
# (NativeRate.anomaly_for) — a deliberate attention-grab so the player
# actually opens the report instead of skipping it, per the anomaly's whole
# "wait, this body has something" design goal (Docs/Buildings System.md).
func anomaly_detected() -> void:
	play_vo("anomaly_detected")


# Stops any currently-playing instance of this sfx — for repeating/interruptible
# sounds that need to cut off immediately rather than ring out to their
# natural end.
func stop(sfx_path: String, base: String = SFX_BASE) -> void:
	var stream: AudioStream = _cache.get(base + sfx_path)
	if stream == null:
		return
	for p in _pool:
		if p.stream == stream and p.playing:
			p.stop()


func _load(sfx_path: String, base: String = SFX_BASE) -> AudioStream:
	var cache_key := base + sfx_path
	if _cache.has(cache_key):
		return _cache[cache_key]
	for ext in ["wav", "ogg"]:
		var full: String = base + sfx_path + "." + ext
		if ResourceLoader.exists(full):
			var stream: AudioStream = ResourceLoader.load(full)
			_cache[cache_key] = stream
			return stream
	_cache[cache_key] = null  # cache miss so we don't re-scan every call
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
