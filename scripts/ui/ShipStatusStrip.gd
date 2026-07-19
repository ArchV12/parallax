class_name ShipStatusStrip
extends Control

# Contextual "what is the ship doing right now" readout — bottom-left
# corner, mirroring ViewSwitcher's own bottom-right corner treatment. Unlike
# this class's own first version (a permanent strip at the top of the
# screen, before that got called out as crowding the view), SHIP STATUS and
# DESTINATION/EN ROUTE only appear while there's actually something to
# report — "IN ORBIT, no destination locked" is the default/boring state and
# stays fully hidden rather than occupying permanent screen space. CARGO is
# the one line that's always visible, same "always-relevant progress number"
# reasoning the Knowledge bar gets a permanent HUD slot for.
#
# GO is gone: PlayerState.travel_to() is already reachable from
# SystemView/PlanetarySystemView's callout GO buttons and LocationsPanel's
# footer GO button, so nothing here commits a trip.
#
# The whole block grows/shrinks vertically as rows show/hide (a plain
# VBoxContainer skips invisible children automatically), and stays pinned to
# the bottom-left corner regardless of its own current height — same
# deferred size-then-position technique ViewSwitcher uses for its own
# corner, just recomputed every frame here since (unlike the tab row, built
# once) row visibility can change on any frame.

const CORNER_MARGIN := 24.0
const ROW_GAP := 4  # int — add_theme_constant_override wants int, not float

const SPEED_REFRESH_INTERVAL := 0.1  # updating every frame reads as digit-flicker at this font size — see _process
const LOCAL_DISTANCE_THRESHOLD_KM := TravelCalc.AU_KM * 0.05  # below this, the live in-flight distance reads in KM (a same-system hop like Earth<->Luna, ~384K km, would show as "0.00 AU" otherwise); at/above it, AU — see _process

const SHIP_STATUS_PREFIX := "SHIP STATUS: "  # the static, never-typed part — see _ship_status_prefix_label/_ship_status_value_label
# Noticeably quicker than SystemView/PlanetarySystemView/BootSequence's
# shared 35 chars/sec — those type out a one-time narrative reveal (a body's
# name), where a leisurely pace reads as deliberate; this one retypes on
# EVERY status change (several times over one trip), so it needs to read as
# "quick instrument update," not "narration."
const STATUS_TYPE_CHARS_PER_SEC := 70.0
const STATUS_TYPE_MIN_TIME := 0.01

var _vbox: VBoxContainer
var _live_distance_label: Label

var _status_row: HBoxContainer
var _ship_status_prefix_label: Label
var _ship_status_value_label: Label
var _ship_status_distance_label: Label
var _ship_status_text := ""    # the last VALUE (not full string) passed to _set_ship_status — used purely to detect an actual change, see there
var _ship_status_type_id := 0  # bumped on every new type-in request — a running coroutine bails once its captured id goes stale, see _type_ship_status
var _post_arrival_wait_id := 0 # bumped on every arrival — guards the "hold ORBITAL INSERTION through the camera settle" wait in _on_location_changed against a stale run firing after a newer arrival (or a new trip) has already moved on

var _dest_row: HBoxContainer
var _dest_line: Label
var _dest_clear_btn: UIButton

var _cargo_label: Label
var _speed_refresh_elapsed := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_readout()
	Destination.destination_changed.connect(_refresh_destination_readout)
	PlayerState.travel_started.connect(_refresh_destination_readout)
	PlayerState.location_changed.connect(_on_location_changed)
	_refresh_destination_readout()
	_update_cargo_label()
	UITheme.theme_changed.connect(queue_redraw)


func _process(delta: float) -> void:
	_update_live_distance_preview()
	_update_cargo_label()

	var traveling := PlayerState.is_traveling
	_status_row.visible = traveling
	_dest_row.visible = traveling or Destination.has_destination()
	_dest_clear_btn.visible = Destination.has_destination() and not traveling

	if traveling:
		# Continuous, not event-driven — the phase changes (orienting -> burn
		# -> insertion) happen mid-flight with no signal to hook, purely a
		# function of elapsed time. Cheap enough to just recompute every
		# frame; see _on_location_changed for the idle "IN ORBIT" side of
		# this. _set_ship_status itself no-ops (no retyping) on the frames
		# where the value hasn't actually changed — see its own comment.
		_set_ship_status(TravelCalc.ship_status(
				PlayerState.travel_distance_km, PlayerState.travel_elapsed,
				PlayerState.travel_accel_km_s2, PlayerState.travel_cruise_cap_km_s).to_upper())

		# Speed/distance change every frame at full precision, which reads as
		# the last digit flickering constantly at this font size — sampled a
		# few times a second instead reads as a live instrument, not noise.
		_speed_refresh_elapsed += delta
		if _speed_refresh_elapsed >= SPEED_REFRESH_INTERVAL:
			_speed_refresh_elapsed = 0.0
			var speed := TravelCalc.current_speed_km_s(
					PlayerState.travel_distance_km, PlayerState.travel_duration, PlayerState.travel_elapsed,
					PlayerState.travel_accel_km_s2, PlayerState.travel_cruise_cap_km_s)

			# Same motion_elapsed/flight_progress Cockpit's own camera curve
			# reads (see TravelCalc.flight_progress) — so this shrinking
			# distance is provably the same number the ship is actually
			# flying, not a second formula that could disagree with it.
			var motion_elapsed := maxf(PlayerState.travel_elapsed - TravelCalc.DEPARTURE_HOLD_SECONDS, 0.0)
			var progress := TravelCalc.flight_progress(
					PlayerState.travel_distance_km, motion_elapsed,
					PlayerState.travel_accel_km_s2, PlayerState.travel_cruise_cap_km_s)
			var remaining_km := PlayerState.travel_distance_km * (1.0 - progress)
			var distance_text := ("%.0f KM" % remaining_km) if PlayerState.travel_distance_km < LOCAL_DISTANCE_THRESHOLD_KM \
					else ("%.2f AU" % (remaining_km / TravelCalc.AU_KM))
			_ship_status_distance_label.text = "·  DISTANCE: %s" % distance_text

			var eta_text := "ETA: %s" % TravelCalc.format_duration(PlayerState.travel_remaining())
			if PlayerState.travel_real_duration_sec > 0.0:
				var real_remaining := PlayerState.travel_real_duration_sec * (1.0 - PlayerState.travel_progress())
				eta_text += "  (REAL: %s)" % TravelCalc.format_duration(real_remaining)
			_dest_line.text = "EN ROUTE TO %s  ·  %s  ·  SPEED: %.1f KM/S" % [
					PlayerState.travel_target_id.to_upper(), eta_text, speed]

	_layout_corner()


# Hidden whenever nothing's focused (Destination.preview_id == "" — cleared
# by SystemView the moment focus is lost or the view itself unloads) or
# mid-trip, where a "distance to the thing you're already flying toward"
# readout would just be a second, differently-timed copy of the EN ROUTE line
# already showing.
func _update_live_distance_preview() -> void:
	var id := Destination.preview_id
	if id == "" or Destination.preview_distance_km < 0.0 or PlayerState.is_traveling:
		_live_distance_label.visible = false
		return
	# Takes Destination.preview_distance_km directly (TravelCalc.
	# estimate_for_distance) rather than TravelCalc.estimate(location, id,
	# ...) — a focused body that's ALSO locked would otherwise resolve
	# through estimate()'s own locked_id override and silently show the
	# FROZEN snapshot here instead of the live number this readout exists to
	# provide.
	var engine := PlayerState.resolve_travel_engine(PlayerState.location_id, id)
	var est := TravelCalc.estimate_for_distance(
			Destination.preview_distance_km, engine["accel_km_s2"], engine["cruise_cap_km_s"])
	_live_distance_label.text = TravelCalc.format_distance(est)
	_live_distance_label.visible = true


# Live "how full is the hold" readout — was a sub-label on the console's own
# CARGO pad; moved here since CARGO is now a menu leaf, not a persistent pad
# with room for one. Cheap enough (one Dictionary sum) to just poll every
# frame rather than wiring a change signal for it.
func _update_cargo_label() -> void:
	var used := Deposits.total_cargo_used()
	_cargo_label.text = "CARGO: %s / %s" % [Deposits.format_units(used), Deposits.format_units(Deposits.cargo_capacity())]


# Once you've arrived somewhere you'd already locked as a destination, the
# lock no longer means anything ("travel to where you already are" doesn't
# make sense) — clearing it also flips the readout back to its base state.
func _on_location_changed() -> void:
	# PlayerState.location_changed fires the INSTANT ARRIVAL_HOLD_SECONDS
	# ends — which is exactly when Cockpit's camera STARTS turning into orbit
	# (_begin_orbit_settle), not when it finishes. Switching straight to "IN
	# ORBIT" here used to claim arrival for the whole ORBIT_SETTLE_DURATION
	# the camera was still visibly rotating. Holding "ORBITAL INSERTION"
	# (already showing — see TravelCalc.ship_status) for that same duration
	# keeps the label honest about what's still happening on screen.
	_post_arrival_wait_id += 1
	var my_id := _post_arrival_wait_id
	if Destination.locked_id == PlayerState.location_id:
		Destination.clear()
	else:
		_refresh_destination_readout()
	await get_tree().create_timer(TravelCalc.ORBIT_SETTLE_DURATION).timeout
	if _post_arrival_wait_id != my_id or PlayerState.is_traveling:
		return  # a newer arrival, or an already-started next trip, has moved on since
	_set_ship_status("IN ORBIT")


# The one path everything (both _process's per-frame poll and
# _on_location_changed's one-off arrival) routes the status value through —
# no-ops if `value` is the same text already showing, so a per-frame caller
# doesn't restart the type-in 60 times a second for an unchanged status.
func _set_ship_status(value: String) -> void:
	if value == _ship_status_text:
		return
	_ship_status_text = value
	_type_ship_status(value)


# Same stepped-reveal technique as SystemView/PlanetarySystemView's
# _type_callout_label (see STATUS_TYPE_CHARS_PER_SEC for why this runs
# quicker) — types the VALUE label only; SHIP_STATUS_PREFIX never retypes.
# _ship_status_type_id guards against overlapping coroutines: if the status
# changes again before a run finishes, the stale run bails the moment it
# notices a newer one has started instead of fighting it for the label text.
func _type_ship_status(value: String) -> void:
	_ship_status_type_id += 1
	var my_id := _ship_status_type_id
	_ship_status_value_label.text = value
	var total_len := value.length()
	if total_len == 0:
		return
	_ship_status_value_label.visible_ratio = 0.0
	var char_time := maxf(1.0 / STATUS_TYPE_CHARS_PER_SEC, STATUS_TYPE_MIN_TIME)
	for i in range(total_len):
		if _ship_status_type_id != my_id:
			return  # a newer status superseded this one mid-type
		_ship_status_value_label.visible_ratio = float(i + 1) / float(total_len)
		await get_tree().create_timer(char_time).timeout
	_ship_status_value_label.visible_ratio = 1.0


func _build_readout() -> void:
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", ROW_GAP)
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vbox)

	_live_distance_label = Label.new()
	_live_distance_label.add_theme_font_size_override("font_size", 14)
	_live_distance_label.add_theme_color_override("font_color", UITheme.accent)
	UITheme.style_label_shadow(_live_distance_label)
	_live_distance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live_distance_label.visible = false
	_vbox.add_child(_live_distance_label)

	# Hidden by default (see _process) — only shown while PlayerState.is_traveling.
	_status_row = HBoxContainer.new()
	_status_row.add_theme_constant_override("separation", 6)
	_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_row.visible = false
	_vbox.add_child(_status_row)

	_ship_status_prefix_label = Label.new()
	_ship_status_prefix_label.add_theme_font_size_override("font_size", 14)
	_ship_status_prefix_label.add_theme_color_override("font_color", UITheme.accent)
	UITheme.style_label_shadow(_ship_status_prefix_label)
	_ship_status_prefix_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ship_status_prefix_label.text = SHIP_STATUS_PREFIX
	_status_row.add_child(_ship_status_prefix_label)

	_ship_status_value_label = Label.new()
	_ship_status_value_label.add_theme_font_size_override("font_size", 14)
	_ship_status_value_label.add_theme_color_override("font_color", UITheme.accent)
	UITheme.style_label_shadow(_ship_status_value_label)
	_ship_status_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Starts already fully shown, not typed — there's nothing to announce a
	# CHANGE from the first time this row ever becomes visible.
	_ship_status_text = "IN ORBIT"
	_ship_status_value_label.text = _ship_status_text
	_ship_status_value_label.visible_ratio = 1.0
	_status_row.add_child(_ship_status_value_label)

	_ship_status_distance_label = Label.new()
	_ship_status_distance_label.add_theme_font_size_override("font_size", 12)
	_ship_status_distance_label.add_theme_color_override("font_color", UITheme.dim)
	UITheme.style_label_shadow(_ship_status_distance_label)
	_ship_status_distance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_row.add_child(_ship_status_distance_label)

	# Hidden by default (see _process) — shown while traveling OR a
	# destination is locked; both cases collapsed into one row, same as
	# before (see _refresh_destination_readout for exactly what's joined in).
	_dest_row = HBoxContainer.new()
	_dest_row.add_theme_constant_override("separation", 10)
	_dest_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dest_row.visible = false
	_vbox.add_child(_dest_row)

	_dest_line = Label.new()
	_dest_line.add_theme_font_size_override("font_size", 12)
	_dest_line.add_theme_color_override("font_color", UITheme.dim)
	UITheme.style_label_shadow(_dest_line)
	_dest_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dest_row.add_child(_dest_line)

	_dest_clear_btn = UIButton.new()
	_dest_clear_btn.text = "CLEAR"
	_dest_clear_btn.dim = true
	_dest_clear_btn.shimmer_enabled = false
	_dest_clear_btn.custom_minimum_size = Vector2(56, 22)
	_dest_clear_btn.add_theme_font_size_override("font_size", 10)
	_dest_clear_btn.visible = false
	_dest_clear_btn.pressed.connect(func() -> void: Destination.clear())
	_dest_row.add_child(_dest_clear_btn)

	# Always visible — see class comment for why this one line doesn't share
	# the rest of this readout's "hidden unless there's something to report."
	_cargo_label = Label.new()
	_cargo_label.add_theme_font_size_override("font_size", 11)
	_cargo_label.add_theme_color_override("font_color", UITheme.dim)
	UITheme.style_label_shadow(_cargo_label)
	_cargo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(_cargo_label)


# Text content only — row VISIBILITY is centralized in _process (traveling/
# has_destination checks), so this never needs to touch it.
func _refresh_destination_readout() -> void:
	var id := Destination.locked_id
	var has_dest := id != ""

	if PlayerState.is_traveling:
		# _process fills in the live ETA/SPEED tail every SPEED_REFRESH_INTERVAL
		# — seed the header half immediately so there's no blank frame before
		# the first refresh.
		_dest_line.text = "EN ROUTE TO %s" % PlayerState.travel_target_id.to_upper()
		_speed_refresh_elapsed = SPEED_REFRESH_INTERVAL  # force an immediate first read instead of waiting out the throttle
		return

	if not has_dest:
		return  # _dest_row is hidden entirely in this state (see _process) — nothing to set

	# Same resolution GO itself uses (PlayerState.start_travel) — so this
	# preview never shows a TRAVEL TIME that GO doesn't actually honor,
	# whether or not a cheat-menu tier is pinned.
	var engine := PlayerState.resolve_travel_engine(PlayerState.location_id, id)
	var est := TravelCalc.estimate(PlayerState.location_id, id, engine["accel_km_s2"], engine["cruise_cap_km_s"])
	var time_text := "TRAVEL TIME: %s" % TravelCalc.format_duration(est["duration_sec"])
	var real_sec: float = engine["real_duration_sec"]
	if real_sec > 0.0:
		time_text += "  (REAL: %s)" % TravelCalc.format_duration(real_sec)
	_dest_line.text = "DESTINATION: %s  ·  %s  ·  %s" % [id.to_upper(), TravelCalc.format_distance(est), time_text]


# Positions the whole block by its own actual size so it stays pinned to the
# bottom-left corner regardless of how many rows are currently visible — same
# "set size, then position (which Godot preserves while moving)" technique
# ViewSwitcher uses for its own corner, just re-run every frame here since
# row visibility (and therefore height) can change on any frame, not just
# once at startup.
func _layout_corner() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	size = _vbox.size
	position = Vector2(CORNER_MARGIN, viewport_size.y - _vbox.size.y - CORNER_MARGIN)
