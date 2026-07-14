class_name ConsolePanel
extends Control

# The cockpit's always-on instrument console — a flat center band (reserved
# for context-free readouts; nothing view-specific ever renders here) flanked
# by two wings that taper down toward the screen edges. Each wing is tiled
# edge-to-edge, with zero gap, by big ConsolePadButtons individually shaped
# to match the wing's slanted silhouette at their position — the console's
# entire visible surface outside the center band IS the buttons; none of
# the panel's own translucent fill ever shows through beside or around one.
# Anything context-dependent (mining, crafting, ...) is a separate popup
# layered on top, never absorbed into this shape — see the cockpit-console
# design conversation in parallax-core-design-decisions memory.
#
# Read left to right: SYSTEM, CARGO, GO on the left wing; COMMAND, RESEARCH,
# DATABASE on the right (mirrored). COMMAND/DATABASE have no systems behind
# them yet — left fully interactive (hover/press feedback) rather than
# disabled, they just have nothing connected to `pressed`, so a click
# no-ops. GO, RESEARCH, and CARGO are wired (RESEARCH opens HUD's
# ResearchPanel — Docs/Science and Knowledge System - Implementation
# Roadmap.md, Phase 4; CARGO opens HUD's CargoPanel, same shape). GO is the
# travel-commit
# action once a destination is locked (see LockButton.gd / Destination
# autoload, reached from a target's callout in System/Planetary System view
# — never from the console itself): pressing it starts a PlayerState trip
# and flicks the viewer to Cockpit, which shows the transit visual. SCAN
# used to live here too, but got pulled once the
# in-scene SCAN button made it redundant (see the console-vs-in-scene-
# actions conversation in parallax-core-design-decisions memory) — the
# console only holds actions that don't depend on what's currently
# targeted; SCAN and LOCK both do, so they stay in-scene.
#
# The center band shows the current locked destination (see Destination
# autoload) — name, distance, travel time (via TravelCalc) — with a CLEAR
# button, or (once GO has been pressed) an EN ROUTE readout with a live ETA
# instead, sourced from the PlayerState autoload. Genuinely context-free: it
# reflects the standing lock/trip, not whatever's currently focused.

signal system_pressed
signal research_pressed
signal cargo_pressed

const HEIGHT_CENTER := 150.0
const HEIGHT_EDGE := 56.0
const CENTER_WIDTH_MAX := 620.0
const CENTER_WIDTH_FRAC := 0.42
const EDGE_HALO_WIDTH := 6.0
const EDGE_CORE_WIDTH := 1.5

const LEFT_LABELS := ["SYSTEM", "CARGO", "GO"]
const RIGHT_LABELS := ["COMMAND", "RESEARCH", "DATABASE"]

var _left_buttons: Array[ConsolePadButton] = []
var _right_buttons: Array[ConsolePadButton] = []

const SPEED_REFRESH_INTERVAL := 0.1  # updating every frame reads as digit-flicker at this font size — see _process
const STATUS_STRIP_HEIGHT := 26.0    # fixed reserved band along the top of the center readout — see _ship_status_prefix_label/_ship_status_value_label
const STATUS_STRIP_PADDING := 8.0    # horizontal inset off the center band's own edges — the status/distance labels are left/right-aligned now (see _layout_buttons), so text needs breathing room off the bevel instead of running flush to it
const LOCAL_DISTANCE_THRESHOLD_KM := TravelCalc.AU_KM * 0.05  # below this, the live in-flight distance reads in KM (a same-system hop like Earth<->Luna, ~384K km, would show as "0.00 AU" otherwise); at/above it, AU — see _process
const LIVE_DISTANCE_LABEL_HEIGHT := 20.0  # see _live_distance_label / _layout_buttons
const LIVE_DISTANCE_LABEL_GAP := 8.0      # clearance off the panel's own top edge

const SHIP_STATUS_PREFIX := "SHIP STATUS: "  # the static, never-typed part — see _ship_status_prefix_label/_ship_status_value_label
# Noticeably quicker than SystemView/PlanetarySystemView/BootSequence's
# shared 35 chars/sec — those type out a one-time narrative reveal (a
# body's name), where a leisurely pace reads as deliberate; this one
# retypes on EVERY status change (several times over one trip), so it
# needs to read as "quick instrument update," not "narration," or it'd
# noticeably lag behind the phase changes it's reporting.
const STATUS_TYPE_CHARS_PER_SEC := 70.0
const STATUS_TYPE_MIN_TIME := 0.01

var _dest_container: VBoxContainer
var _dest_header: Label
var _dest_distance: Label
var _dest_time: Label
var _dest_speed: Label
var _dest_clear_btn: UIButton
var _speed_refresh_elapsed := 0.0

# Always-on "what is the ship doing right now" readout — separate from
# _dest_container (which shows nothing at all when no destination is locked
# and nothing en route) because this one is never empty: IN ORBIT is as much
# a status as ORBITAL INSERTION is. Sits in its own fixed strip along the
# top of the center band (see _layout_buttons) rather than living inside
# _dest_container's own ALIGNMENT_CENTER stack, which visibly shifts up/down
# depending on how many of ITS OWN rows happen to be visible — ship status
# needs to stay put regardless of that. Left-aligned, sharing the strip with
# _ship_distance_label (right-aligned) — repurposed depending on what's
# actually true right now: a live shrinking distance-to-target while en
# route, or the name of wherever we are for the whole rest of the time,
# ORBITAL INSERTION included (see _on_location_changed — PlayerState.
# location_id is already true the instant arrival fires, even while the
# camera's still settling into orbit), e.g. "SHIP STATUS: IN ORBIT" / "MARS".
#
# Split into a static prefix label (SHIP_STATUS_PREFIX, never retyped) and
# a separate value label that types itself in fresh every time the status
# actually changes (see _set_ship_status) — the "SHIP STATUS:" part of the
# readout isn't new information each time, only the value after it is, so
# only the value gets the attention-grabbing type-in treatment.
var _ship_status_prefix_label: Label
var _ship_status_value_label: Label
var _ship_status_text := ""    # the last VALUE (not full string) passed to _set_ship_status — used purely to detect an actual change, see there
var _ship_status_type_id := 0  # bumped on every new type-in request — a running coroutine bails once its captured id goes stale, see _type_ship_status
var _post_arrival_wait_id := 0 # bumped on every arrival — guards the "hold ORBITAL INSERTION through the camera settle" wait in _on_location_changed against a stale run firing after a newer arrival (or a new trip) has already moved on
var _ship_distance_label: Label

# Floats just above the console's top edge, centered over the center band —
# a live (recomputed every frame, never frozen) distance to whatever body is
# currently focused in System View, locked or not. Deliberately separate
# from _dest_distance below: that one only ever shows the frozen snapshot
# for a LOCKED destination, which is the whole point of locking (see
# Destination.locked_distance_km) — this one is what lets you actually watch
# for the moment to lock in the first place. Sits above the panel rather
# than inside the center band alongside _dest_container so the two never
# read as the same number — see Destination.preview_id's own comment.
var _live_distance_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -HEIGHT_CENTER
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	for label in LEFT_LABELS:
		var btn := _make_pad(label)
		_left_buttons.append(btn)
		add_child(btn)
	for label in RIGHT_LABELS:
		var btn := _make_pad(label)
		_right_buttons.append(btn)
		add_child(btn)

	_left_buttons[0].pressed.connect(func() -> void: system_pressed.emit())
	_left_buttons[1].pressed.connect(func() -> void: cargo_pressed.emit())
	_left_buttons[2].pressed.connect(_on_go_pressed)
	# press_sfx itself is kept live by _refresh_destination_readout (called
	# below, and on every subsequent destination/travel change) rather than
	# fixed here — it swaps between "go_button" and "error" depending on
	# whether a destination is actually locked, see that function's comment.

	# COMMAND/DATABASE have no systems behind them yet (see class comment) —
	# pressing one is a genuine no-op, so it should sound like one instead of
	# playing the same click every working button uses. RESEARCH is wired
	# (Docs/Science and Knowledge System - Implementation Roadmap.md, Phase
	# 4) — reset back to the default click sound right after this loop.
	for btn in _right_buttons:
		btn.press_sfx = "error"
	_right_buttons[1].press_sfx = "button_general"
	_right_buttons[1].pressed.connect(func() -> void: research_pressed.emit())

	_build_destination_readout()
	Destination.destination_changed.connect(_refresh_destination_readout)
	PlayerState.travel_started.connect(_refresh_destination_readout)
	PlayerState.location_changed.connect(_on_location_changed)
	_refresh_destination_readout()

	resized.connect(_layout_buttons)
	UITheme.theme_changed.connect(queue_redraw)
	_layout_buttons()


func _process(delta: float) -> void:
	_update_live_distance_preview()

	if not PlayerState.is_traveling:
		return
	# Continuous, not event-driven — the phase changes (orienting -> burn ->
	# insertion) happen mid-flight with no signal to hook, purely a function
	# of elapsed time. Cheap enough to just recompute every frame; see
	# _on_location_changed for the idle "IN ORBIT" side of this. _set_ship_status
	# itself no-ops (no retyping) on the frames where the value hasn't
	# actually changed — see its own comment.
	_set_ship_status(TravelCalc.ship_status(
			PlayerState.travel_distance_km, PlayerState.travel_elapsed,
			PlayerState.travel_accel_km_s2, PlayerState.travel_cruise_cap_km_s).to_upper())
	_dest_time.text = "ETA: %s" % TravelCalc.format_duration(PlayerState.travel_remaining())
	# Real-world-scale remaining time for whatever tier was pinned when this
	# trip started (see PlayerState.travel_real_duration_sec) — shrinks
	# alongside the gameplay ETA using the SAME progress fraction, rather
	# than its own independent countdown, so "half the gameplay trip done"
	# and "half the real duration done" always agree with each other.
	if PlayerState.travel_real_duration_sec > 0.0:
		var real_remaining := PlayerState.travel_real_duration_sec * (1.0 - PlayerState.travel_progress())
		_dest_time.text += "  (REAL: %s)" % TravelCalc.format_duration(real_remaining)
	_ship_distance_label.visible = true

	# Speed/distance change every frame at full precision, which reads as
	# the last digit flickering constantly at this font size — visibly
	# re-rendering the label text only a few times a second reads as a live
	# instrument, not noise, without actually lying about the value (it's
	# still the true instantaneous reading each time it does update, just
	# sampled less often).
	_speed_refresh_elapsed += delta
	if _speed_refresh_elapsed >= SPEED_REFRESH_INTERVAL:
		_speed_refresh_elapsed = 0.0
		var speed := TravelCalc.current_speed_km_s(
				PlayerState.travel_distance_km, PlayerState.travel_duration, PlayerState.travel_elapsed,
				PlayerState.travel_accel_km_s2, PlayerState.travel_cruise_cap_km_s)
		_dest_speed.text = "SPEED: %.1f KM/S" % speed

		# Same motion_elapsed/flight_progress Cockpit's own camera curve
		# reads (see TravelCalc.flight_progress) — so this shrinking
		# distance is provably the same number the ship is actually flying,
		# not a second formula that could disagree with it.
		var motion_elapsed := maxf(PlayerState.travel_elapsed - TravelCalc.DEPARTURE_HOLD_SECONDS, 0.0)
		var progress := TravelCalc.flight_progress(
				PlayerState.travel_distance_km, motion_elapsed,
				PlayerState.travel_accel_km_s2, PlayerState.travel_cruise_cap_km_s)
		var remaining_km := PlayerState.travel_distance_km * (1.0 - progress)
		var distance_text := ("%.0f KM" % remaining_km) if PlayerState.travel_distance_km < LOCAL_DISTANCE_THRESHOLD_KM \
				else ("%.2f AU" % (remaining_km / TravelCalc.AU_KM))
		_ship_distance_label.text = "DISTANCE: %s" % distance_text


# Hidden whenever nothing's focused (Destination.preview_id == "" — cleared
# by SystemView the moment focus is lost or the view itself unloads, see
# its own comments) or mid-trip, where a "distance to the thing you're
# already flying toward" readout would just be a second, differently-timed
# copy of the ETA/DISTANCE readout already showing in the center band.
func _update_live_distance_preview() -> void:
	var id := Destination.preview_id
	if id == "" or Destination.preview_distance_km < 0.0 or PlayerState.is_traveling:
		_live_distance_label.visible = false
		return
	# Takes Destination.preview_distance_km directly (TravelCalc.
	# estimate_for_distance) rather than TravelCalc.estimate(location, id,
	# ...) — a focused body that's ALSO locked would otherwise resolve
	# through estimate()'s own locked_id override and silently show the
	# FROZEN snapshot here instead of the live number this readout exists
	# to provide. See estimate_for_distance's own comment.
	var engine := PlayerState.resolve_travel_engine(PlayerState.location_id, id)
	var est := TravelCalc.estimate_for_distance(
			Destination.preview_distance_km, engine["accel_km_s2"], engine["cruise_cap_km_s"])
	_live_distance_label.text = TravelCalc.format_distance(est)
	_live_distance_label.visible = true


# Once you've arrived somewhere you'd already locked as a destination, the
# lock no longer means anything ("travel to where you already are" doesn't
# make sense) — clearing it also flips the readout back to its base state.
func _on_location_changed() -> void:
	# PlayerState.location_changed fires the INSTANT ARRIVAL_HOLD_SECONDS
	# ends — which is exactly when Cockpit's camera STARTS turning into
	# orbit (_begin_orbit_settle), not when it finishes. Switching straight
	# to "IN ORBIT" here used to claim arrival for the whole
	# ORBIT_SETTLE_DURATION the camera was still visibly rotating — see
	# TravelCalc.ORBIT_SETTLE_DURATION's comment. Holding "ORBITAL
	# INSERTION" (already showing — see TravelCalc.ship_status) for that
	# same duration keeps the label honest about what's still happening on
	# screen.
	_post_arrival_wait_id += 1
	var my_id := _post_arrival_wait_id
	# PlayerState.location_id is already true the instant this fires — the
	# ship has genuinely arrived, even though the camera's still settling
	# into orbit (ORBITAL INSERTION) — so the name belongs on screen now,
	# not held back until "IN ORBIT" catches up below.
	_ship_distance_label.text = PlayerState.location_id.to_upper()
	_ship_distance_label.visible = true
	if Destination.locked_id == PlayerState.location_id:
		Destination.clear()
	else:
		_refresh_destination_readout()
	await get_tree().create_timer(TravelCalc.ORBIT_SETTLE_DURATION).timeout
	if _post_arrival_wait_id != my_id or PlayerState.is_traveling:
		return  # a newer arrival, or an already-started next trip, has moved on since
	_set_ship_status("IN ORBIT")


func _on_go_pressed() -> void:
	if Destination.has_destination() and PlayerState.travel_to(Destination.locked_id):
		HUD.go_to("res://scenes/cockpit.tscn")


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
# quicker) — types the VALUE label only; SHIP_STATUS_PREFIX never moves or
# retypes. _ship_status_type_id guards against overlapping coroutines: if
# the status changes again before a run finishes (a fast cheat-engine trip
# can blow through a whole phase in well under a type-in's duration), the
# stale run bails the moment it notices a newer one has started instead of
# fighting it for the label's text.
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


func _build_destination_readout() -> void:
	_ship_status_prefix_label = Label.new()
	_ship_status_prefix_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ship_status_prefix_label.add_theme_font_size_override("font_size", 14)
	_ship_status_prefix_label.add_theme_color_override("font_color", UITheme.accent)
	_ship_status_prefix_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ship_status_prefix_label.text = SHIP_STATUS_PREFIX
	add_child(_ship_status_prefix_label)

	_ship_status_value_label = Label.new()
	_ship_status_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ship_status_value_label.add_theme_font_size_override("font_size", 14)
	_ship_status_value_label.add_theme_color_override("font_color", UITheme.accent)
	_ship_status_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Starts already fully shown, not typed — there's nothing to announce a
	# CHANGE from on the very first frame the console exists.
	_ship_status_text = "IN ORBIT"
	_ship_status_value_label.text = _ship_status_text
	_ship_status_value_label.visible_ratio = 1.0
	add_child(_ship_status_value_label)

	_ship_distance_label = Label.new()
	_ship_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ship_distance_label.add_theme_font_size_override("font_size", 14)
	_ship_distance_label.add_theme_color_override("font_color", UITheme.accent)
	_ship_distance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A fresh scene load starts already "IN ORBIT" (see above) — the
	# right-hand slot repurposes to name wherever we are (see
	# _on_location_changed) rather than hiding until the first trip.
	_ship_distance_label.text = PlayerState.location_id.to_upper()
	_ship_distance_label.visible = true
	add_child(_ship_distance_label)

	_live_distance_label = Label.new()
	_live_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_live_distance_label.add_theme_font_size_override("font_size", 14)
	_live_distance_label.add_theme_color_override("font_color", UITheme.accent)
	_live_distance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live_distance_label.visible = false
	add_child(_live_distance_label)

	_dest_container = VBoxContainer.new()
	_dest_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_dest_container.add_theme_constant_override("separation", 4)
	_dest_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dest_container)

	_dest_header = Label.new()
	_dest_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dest_header.add_theme_font_size_override("font_size", 14)
	_dest_header.add_theme_color_override("font_color", UITheme.accent)
	_dest_container.add_child(_dest_header)

	_dest_distance = Label.new()
	_dest_distance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dest_distance.add_theme_font_size_override("font_size", 12)
	_dest_distance.add_theme_color_override("font_color", UITheme.dim)
	_dest_container.add_child(_dest_distance)

	_dest_time = Label.new()
	_dest_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dest_time.add_theme_font_size_override("font_size", 12)
	_dest_time.add_theme_color_override("font_color", UITheme.dim)
	_dest_container.add_child(_dest_time)

	# EN ROUTE only — a locked-but-not-yet-departed destination has no speed
	# to show (see _refresh_destination_readout).
	_dest_speed = Label.new()
	_dest_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dest_speed.add_theme_font_size_override("font_size", 12)
	_dest_speed.add_theme_color_override("font_color", UITheme.dim)
	_dest_speed.visible = false
	_dest_container.add_child(_dest_speed)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	_dest_container.add_child(spacer)

	_dest_clear_btn = UIButton.new()
	_dest_clear_btn.text = "CLEAR"
	_dest_clear_btn.dim = true
	_dest_clear_btn.shimmer_enabled = false
	_dest_clear_btn.custom_minimum_size = Vector2(70, 22)
	_dest_clear_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_dest_clear_btn.add_theme_font_size_override("font_size", 10)
	_dest_clear_btn.pressed.connect(func() -> void: Destination.clear())
	_dest_container.add_child(_dest_clear_btn)


func _refresh_destination_readout() -> void:
	var id := Destination.locked_id
	var has_dest := id != ""

	# GO's own click sound is fixed per-instance (ConsolePadButton.press_sfx,
	# same override mechanism as go_button/lock_button everywhere else) and
	# fires unconditionally on click, decoupled from whatever _on_go_pressed
	# decides to do — so the only way to make a no-destination press SOUND
	# like a no-op rather than a real GO is to swap which sfx is armed
	# BEFORE the click, here, rather than trying to override it after the
	# fact from inside _on_go_pressed.
	_left_buttons[2].press_sfx = "go_button" if has_dest else "error"

	if PlayerState.is_traveling:
		_dest_header.text = "EN ROUTE TO %s" % PlayerState.travel_target_id.to_upper()
		_dest_distance.text = ""
		_dest_time.text = "ETA: %s" % TravelCalc.format_duration(PlayerState.travel_remaining())
		_dest_distance.visible = false
		_dest_time.visible = true
		_dest_speed.visible = true
		_speed_refresh_elapsed = SPEED_REFRESH_INTERVAL  # force an immediate first read instead of waiting out the throttle
		_dest_clear_btn.visible = false
		return

	_dest_header.text = ("DESTINATION: %s" % id.to_upper()) if has_dest else "NO DESTINATION LOCKED"
	if has_dest:
		# Same resolution GO itself uses (PlayerState.start_travel) — so this
		# preview never shows a TRAVEL TIME that GO doesn't actually honor,
		# whether or not a cheat-menu tier is pinned.
		var engine := PlayerState.resolve_travel_engine(PlayerState.location_id, id)
		var est := TravelCalc.estimate(PlayerState.location_id, id, engine["accel_km_s2"], engine["cruise_cap_km_s"])
		_dest_distance.text = TravelCalc.format_distance(est)
		_dest_time.text = "TRAVEL TIME: %s" % TravelCalc.format_duration(est["duration_sec"])
		var real_sec: float = engine["real_duration_sec"]
		if real_sec > 0.0:
			_dest_time.text += "  (REAL: %s)" % TravelCalc.format_duration(real_sec)
	_dest_distance.visible = has_dest
	_dest_time.visible = has_dest
	_dest_speed.visible = false
	_dest_clear_btn.visible = has_dest


func _make_pad(label: String) -> ConsolePadButton:
	var btn := ConsolePadButton.new()
	btn.label_text = label
	return btn


func _center_half_width() -> float:
	return minf(CENTER_WIDTH_MAX, size.x * CENTER_WIDTH_FRAC) * 0.5


# Top-edge height at a given x within the LEFT wing's diagonal, which runs
# from (0, h - HEIGHT_EDGE) up to (x0, 0) at the center bend.
func _left_edge_y(x: float, x0: float, h: float) -> float:
	if x0 <= 0.0:
		return h - HEIGHT_EDGE
	return lerpf(h - HEIGHT_EDGE, 0.0, clampf(x / x0, 0.0, 1.0))


# Mirror of the above for the RIGHT wing's diagonal, from (x1, 0) at the
# bend out to (w, h - HEIGHT_EDGE) at the screen edge.
func _right_edge_y(x: float, x1: float, w: float, h: float) -> float:
	if w <= x1:
		return 0.0
	return lerpf(0.0, h - HEIGHT_EDGE, clampf((x - x1) / (w - x1), 0.0, 1.0))


func _layout_buttons() -> void:
	var h := size.y
	var half := _center_half_width()
	var x0 := size.x * 0.5 - half
	var x1 := size.x * 0.5 + half

	var count := _left_buttons.size()
	for i in count:
		var xa := x0 * (float(i) / count)
		var xb := x0 * (float(i + 1) / count)
		var btn := _left_buttons[i]
		btn.position = Vector2(xa, 0.0)
		btn.size = Vector2(xb - xa, h)
		btn.set_top_edge(_left_edge_y(xa, x0, h), _left_edge_y(xb, x0, h))

	var rcount := _right_buttons.size()
	for i in rcount:
		var xa := x1 + (size.x - x1) * (float(i) / rcount)
		var xb := x1 + (size.x - x1) * (float(i + 1) / rcount)
		var btn := _right_buttons[i]
		btn.position = Vector2(xa, 0.0)
		btn.size = Vector2(xb - xa, h)
		btn.set_top_edge(_right_edge_y(xa, x1, size.x, h), _right_edge_y(xb, x1, size.x, h))

	# Value label starts right where the (fixed-text, so fixed-width) prefix
	# label's natural width ends — get_minimum_size() works off the font's
	# own metrics even without either label ever being laid out by a
	# container, so this stays correct regardless of font/theme changes.
	var status_prefix_width := _ship_status_prefix_label.get_minimum_size().x
	_ship_status_prefix_label.position = Vector2(x0 + STATUS_STRIP_PADDING, 6.0)
	_ship_status_prefix_label.size = Vector2(status_prefix_width, STATUS_STRIP_HEIGHT)

	_ship_status_value_label.position = Vector2(x0 + STATUS_STRIP_PADDING + status_prefix_width, 6.0)
	_ship_status_value_label.size = Vector2(
			x1 - x0 - STATUS_STRIP_PADDING * 2.0 - status_prefix_width, STATUS_STRIP_HEIGHT)

	_ship_distance_label.position = Vector2(x0 + STATUS_STRIP_PADDING, 6.0)
	_ship_distance_label.size = Vector2(x1 - x0 - STATUS_STRIP_PADDING * 2.0, STATUS_STRIP_HEIGHT)

	_dest_container.position = Vector2(x0, STATUS_STRIP_HEIGHT)
	_dest_container.size = Vector2(x1 - x0, h - STATUS_STRIP_HEIGHT)

	# Negative local y — deliberately floats above the panel's own top edge
	# (local y = 0), over the center band's width, rather than competing for
	# space inside it. Controls render fine outside their parent's rect;
	# nothing here clips it.
	_live_distance_label.position = Vector2(x0, -LIVE_DISTANCE_LABEL_HEIGHT - LIVE_DISTANCE_LABEL_GAP)
	_live_distance_label.size = Vector2(x1 - x0, LIVE_DISTANCE_LABEL_HEIGHT)

	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var half := _center_half_width()
	var x0 := w * 0.5 - half
	var x1 := w * 0.5 + half

	# Only the center band's own fill is drawn here — the wings are fully
	# tiled by pad buttons on top, so painting fill under them would never
	# actually be seen.
	var fill: Color = UITheme.panel
	fill.a = 0.92
	draw_colored_polygon(PackedVector2Array([
		Vector2(x0, 0.0), Vector2(x1, 0.0), Vector2(x1, h), Vector2(x0, h),
	]), fill)

	var edge := PackedVector2Array([
		Vector2(0.0, h - HEIGHT_EDGE), Vector2(x0, 0.0), Vector2(x1, 0.0), Vector2(w, h - HEIGHT_EDGE),
	])
	var halo: Color = UITheme.accent
	halo.a = 0.35
	draw_polyline(edge, halo, EDGE_HALO_WIDTH, true)
	draw_polyline(edge, UITheme.accent, EDGE_CORE_WIDTH, true)
