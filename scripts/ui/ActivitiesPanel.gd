class_name ActivitiesPanel
extends Control

# Cockpit-only right-side "what can I do here" panel (Docs/Science and
# Knowledge System - Implementation Roadmap.md, Phase 2) — deliberately NOT
# part of System/Planetary System view: this is what a destination in
# Cockpit actually DOES, not a data readout about it (that's BodyInfoPanel's
# job, on the opposite, left side of the screen).
#
# Slide-out drawer + tab, same mechanics as LocationsPanel's own "KNOWN
# LOCATIONS" drawer in System view (see that class's comment for the anchor/
# offset reasoning — a plain Control tweening offset_left/offset_right,
# not a Container-based layout, since a shrink-wrapped panel has no way to
# park part of itself off-screen). Unlike LocationsPanel (collapsed by
# default, opened by the player), this one DEFAULTS OPEN on every arrival —
# see refresh() — since "what can I do here" is the natural first thing to
# want to see at a new destination, not something to go looking for.
#
# Gateway/detail/active-operations/completed flow: an AVAILABLE row (the
# whole row is the tap target, not a separate VIEW button) opens
# ActivityDetailPanel (Target/Instrument/Status/Estimated Duration/Potential
# Discoveries + BEGIN SURVEY), which starts the operation via the Operations
# autoload — see that class for why operation TIMING/RESOLUTION lives there
# now instead of a Tween/coroutine on this Control: it used to be silently
# abandoned the instant Cockpit's scene tree was freed (GO-ing anywhere, or
# even just switching to System View). This panel is now a pure poller/
# renderer over Operations, the same relationship ConsolePanel already has
# to PlayerState.travel_progress() — it never times or resolves anything
# itself. A running SURVEY shows in ACTIVE OPERATIONS with a live progress
# bar; once Operations resolves it, it moves to COMPLETED (See Results / ✕)
# — deliberately NOT an automatic popup, viewing results is the player's own
# choice, on their own schedule (see _on_see_results_pressed).
#
# Mining is a different shape entirely — CONTINUOUS, not a single resolve
# (see Operations._tick_mining): its active card (_build_mining_active_row)
# has no progress bar, just live "+N Material"/"Deposit Remaining: N%"
# counters and a STOP button, and it never reaches COMPLETED at all — it
# just disappears the instant it ends (stopped/departed/depleted — see
# Operations.operation_stopped), with a HUD toast summarizing what was
# collected. Everything shown was already committed to the player's
# inventory as it ticked, so there's nothing left to "view" afterward.
#
# Availability isn't gated per-location yet for Surveys (see the roadmap's
# Phase 2 scope note) — the same list shows at every destination for now;
# only which instrument tier is owned changes what's on it. Mining is the
# one exception (see _is_available_now) — it needs a Resource Survey to have
# already resolved at the current body.

# Fired after a Geological or Resource Survey run when hand-authored rich
# report content exists for the current body (Research.geological_data_for/
# resource_data_for) — Cockpit connects these to SurveyReportPanel's two
# show_*_report entry points, which display the Knowledge-awarded line
# themselves (category/knowledge_awarded, carried here). Not fired at all
# for activities/bodies without one — _result_label's flat "+N Knowledge"
# text is the fallback ONLY for that case now (see _show_results); showing
# it AND a popup at the same time was redundant.
signal geological_report_ready(location_id: String, data: GeologicalSurveyData, category: String, knowledge_awarded: int)
signal resource_report_ready(location_id: String, data: ResourceSurveyData, category: String, knowledge_awarded: int)

const PANEL_WIDTH := 340.0  # roomy enough for "RESOURCE SURVEY RESULTS"-length titles without wrapping
const TAB_WIDTH := 30.0
const TAB_HEIGHT := 64.0  # a grab handle, not the full drawer height
const TOP_MARGIN := 92
const RIGHT_MARGIN := 24
const BOTTOM_MARGIN := 110  # stays clear of CommandMenu's idle root button + pulsing ring (the console/status-strip rearchitecture moved the always-on readout to the TOP of the screen — this only needs to clear the fan menu's small bottom-center footprint now, not the old 150px console band); the fan's fully-EXPANDED state is expected to visually overlap this drawer, same as any other modal popup already does
const SLIDE_DURATION := 0.28
# Godot's default ScrollContainer scrollbar overlays content instead of
# reserving space for it — this much right margin on the AVAILABLE list
# keeps the scrollbar thumb clear of each row card's own right edge/border.
const SCROLLBAR_GUTTER := 16

var _drawer: Control
var _tab: Button
var _panel: UIPanel
var _active_header: Label
var _active_box: VBoxContainer
var _completed_header: Label
var _completed_box: VBoxContainer
var _available_box: VBoxContainer
var _result_label: Label
var _detail_panel: ActivityDetailPanel
var _mining_panel: MiningOperationsPanel
var _expanded := false
var _traveling := false  # see show_for_travel/refresh — suppresses AVAILABLE while in transit


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_drawer = Control.new()
	_drawer.anchor_left = 1.0
	_drawer.anchor_right = 1.0
	_drawer.anchor_top = 0.0
	_drawer.anchor_bottom = 1.0
	_drawer.offset_top = TOP_MARGIN
	_drawer.offset_bottom = -BOTTOM_MARGIN
	_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer.visible = false  # nothing to show until the first refresh()/show_for_travel() (arrival/departure)
	add_child(_drawer)

	_build_tab()
	_build_panel()

	_detail_panel = ActivityDetailPanel.new()
	_detail_panel.begin_requested.connect(_start_activity)
	add_child(_detail_panel)

	_mining_panel = MiningOperationsPanel.new()
	_mining_panel.begin_requested.connect(_start_mining)
	add_child(_mining_panel)

	# Operations is the single source of truth for what's running/complete —
	# any of these can fire from ANYTHING that touches it (this panel's own
	# BEGIN press, a future different UI, even a debug tool), so the rebuild
	# has to be driven by the signal, not just called inline after our own
	# actions.
	Operations.operation_started.connect(func(_op_id: String) -> void: _rebuild_rows())
	Operations.operation_completed.connect(func(_op_id: String) -> void: _rebuild_rows())
	Operations.operation_dismissed.connect(func(_op_id: String) -> void: _rebuild_rows())
	Operations.operation_stopped.connect(func(_activity_id: String, _location_id: String, _summary: Dictionary) -> void: _rebuild_rows())

	# A milestone can be granted by ANYTHING that calls Research.add_knowledge
	# — not just a resolved survey (e.g. the F2 Cheat Menu's Science Cheat) —
	# so an AVAILABLE row's instrument subtitle stays in sync regardless of
	# what triggered it.
	Research.milestone_reached.connect(func(_tech: TechnologyDef) -> void: _rebuild_rows())

	_set_expanded(false, false)  # collapsed initial offsets, no animation — refresh() is what actually reveals this


# Only ever updates VALUES for whatever's currently shown in ACTIVE
# OPERATIONS — full row rebuilds happen exclusively in response to
# Operations' own signals above, never every frame. Up to two rows here in
# practice — a Survey and Mining run as independent tracks (see Operations'
# own class comment on can_start) and can legitimately both be RUNNING at
# once — but iterates generically rather than assuming a fixed count, since
# Operations' own data shape is deliberately ready for more later. Two
# different live-update shapes share this loop: a Survey card polls a
# ProgressBar (see "progress" meta); a Mining card has no progress bar at
# all (continuous, no fixed end — see _build_mining_active_row) and instead
# polls its own yield/remaining Labels directly (see "mining_op_id" meta).
func _process(_delta: float) -> void:
	for row in _active_box.get_children():
		if row.has_meta("progress"):
			var progress: ProgressBar = row.get_meta("progress")
			if is_instance_valid(progress):
				progress.value = Operations.progress(row.get_meta("op_id"))
		elif row.has_meta("mining_op_id"):
			var op := Operations.get_operation(row.get_meta("mining_op_id"))
			if op == null:
				continue
			var yield_label: Label = row.get_meta("mining_yield_label")
			if is_instance_valid(yield_label):
				yield_label.text = "+%d %s" % [op.mining_session_yield, op.deposit_material]
			var remaining_label: Label = row.get_meta("mining_remaining_label")
			if is_instance_valid(remaining_label):
				var deposit := Deposits.deposit_for(op.location_id, op.deposit_material)
				if deposit != null:
					remaining_label.text = "Deposit Remaining: %d%%" % roundi(deposit.remaining_fraction * 100.0)


# A small grab handle vertically centered on the drawer's left edge — same
# shape as LocationsPanel's own tab, not a strip spanning the whole height.
func _build_tab() -> void:
	_tab = Button.new()
	_tab.anchor_left = 0.0
	_tab.anchor_right = 0.0
	_tab.anchor_top = 0.5
	_tab.anchor_bottom = 0.5
	_tab.offset_left = 0.0
	_tab.offset_right = TAB_WIDTH
	_tab.offset_top = -TAB_HEIGHT * 0.5
	_tab.offset_bottom = TAB_HEIGHT * 0.5
	_tab.text = "◀"
	_tab.tooltip_text = "Operations"
	UITheme.style_button(_tab, UITheme.button, UITheme.button_hov, UITheme.border)
	_tab.pressed.connect(func() -> void:
		AudioManager.ui_confirm("menu_slide")  # the drawer's own slide cue, not the generic click — a raw Button, not UIButton/ConsolePadButton, so this has to do it itself
		_set_expanded(not _expanded))
	_drawer.add_child(_tab)


func _build_panel() -> void:
	_panel = UIPanel.new()
	_panel.anchor_left = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = TAB_WIDTH
	_panel.offset_right = TAB_WIDTH + PANEL_WIDTH
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	_drawer.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)
	vbox.add_child(UIPanel.build_title_header("Operations"))

	_active_header = _make_section_header("ACTIVE OPERATIONS")
	_active_header.visible = false
	vbox.add_child(_active_header)
	_active_box = VBoxContainer.new()
	_active_box.add_theme_constant_override("separation", 12)
	vbox.add_child(_active_box)

	_completed_header = _make_section_header("COMPLETED")
	_completed_header.visible = false
	vbox.add_child(_completed_header)
	_completed_box = VBoxContainer.new()
	_completed_box.add_theme_constant_override("separation", 12)
	vbox.add_child(_completed_box)

	vbox.add_child(_make_section_header("AVAILABLE OPERATIONS"))

	# Scrollable — same reasoning as LocationsPanel's own rows container:
	# this list only grows as more Activities get built, and a fixed-height
	# drawer needs somewhere for that growth to go besides off the bottom.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var scroll_margin := MarginContainer.new()
	scroll_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_theme_constant_override("margin_right", SCROLLBAR_GUTTER)
	scroll.add_child(scroll_margin)

	_available_box = VBoxContainer.new()
	_available_box.add_theme_constant_override("separation", 12)
	_available_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_child(_available_box)

	_result_label = Label.new()
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 12)
	_result_label.add_theme_color_override("font_color", UITheme.dim)
	_result_label.visible = false
	vbox.add_child(_result_label)


func _make_section_header(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", UITheme.dim)
	return lbl


# Public entry point for the command menu's OPERATIONS leaf — the drawer's
# own tab already toggles this internally (see _build_tab), this just gives
# an external caller the same switch. Does nothing about _traveling/refresh's
# own defaults-open behavior; those are independent of who asked for a toggle.
func toggle() -> void:
	_set_expanded(not _expanded)


# animate = false only for the initial collapse in _ready and the reset step
# in refresh() — snaps straight there instead of visibly sliding in from
# whatever offset the drawer happened to be left at.
func _set_expanded(expanded: bool, animate: bool = true) -> void:
	_expanded = expanded
	_tab.text = "▶" if expanded else "◀"

	var target_left: float
	var target_right: float
	if expanded:
		target_right = -RIGHT_MARGIN
		target_left = -RIGHT_MARGIN - TAB_WIDTH - PANEL_WIDTH
	else:
		target_left = -TAB_WIDTH
		target_right = PANEL_WIDTH

	if not animate:
		_drawer.offset_left = target_left
		_drawer.offset_right = target_right
		return

	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_drawer, "offset_left", target_left, SLIDE_DURATION)
	tw.tween_property(_drawer, "offset_right", target_right, SLIDE_DURATION)


# Rebuilds the drawer and reveals it — every fresh arrival defaults OPEN
# regardless of whatever collapsed/expanded state a PREVIOUS visit left it
# in, via the collapse-then-reopen slide below. But if the player had
# already pulled it open themselves before arriving (e.g. checking on a
# background operation mid-flight via show_for_travel()), it's already
# sitting exactly where it should be — forcing the same snap-closed/
# slide-open sequence in that case just replayed the whole reveal animation
# for no reason, reading as the panel spuriously "reopening" out from under
# the player. Content still updates either way; only the animation is
# conditional.
func refresh() -> void:
	_traveling = false
	_drawer.visible = true
	_rebuild_rows()
	if _expanded:
		return
	_set_expanded(false, false)
	_set_expanded(true)


# Reachable-but-collapsed for the duration of a trip — unlike refresh()
# (arrival), this deliberately does NOT force the drawer open: there's
# nothing new to reveal, just the option to check on a background operation
# while flying. AVAILABLE stays empty the whole time (see _rebuild_rows) —
# there's no target body to run anything against mid-flight — but an
# operation started before departure keeps ticking/resolving via Operations
# regardless of where the player currently is, so ACTIVE/COMPLETED still
# need to be reachable here too. Call this from Cockpit's transit build.
func show_for_travel() -> void:
	_traveling = true
	_drawer.visible = true
	_rebuild_rows()
	_set_expanded(false, false)


# Rebuilds all three sections from Research/Operations' current state — safe
# to call anytime, including mid-operation: Operations itself owns the
# actual timing (this just re-reads it), so there's no freed-object risk the
# way an earlier Tween-based version had to guard against. Shows a
# placeholder row rather than hiding anything if AVAILABLE is empty — the
# drawer and its tab stay reachable regardless, same as LocationsPanel's own
# empty state.
func _rebuild_rows() -> void:
	for child in _active_box.get_children():
		child.queue_free()
	for child in _completed_box.get_children():
		child.queue_free()
	for child in _available_box.get_children():
		child.queue_free()

	var any_active := false
	var any_completed := false
	var shown_available := 0

	for id: String in Research.available_activities():
		var op := Operations.operation_for_activity(id)
		if op == null:
			# No target body to run anything against mid-flight — an
			# operation begun before departure still shows below via the
			# RUNNING/else branches, this only suppresses starting a NEW one.
			if not _traveling and _is_available_now(id):
				if _is_survey_kind(id) and not Research.can_survey_for_new_info(id, PlayerState.location_id):
					_available_box.add_child(_build_show_results_row(id))
				else:
					_available_box.add_child(_build_available_row(id))
				shown_available += 1
		elif op.status == ActiveOperation.Status.RUNNING:
			if id == "mining":
				_active_box.add_child(_build_mining_active_row(op))
			else:
				_active_box.add_child(_build_active_row(id, op))
			any_active = true
		else:
			_completed_box.add_child(_build_completed_row(id, op))
			any_completed = true

	_active_header.visible = any_active
	_completed_header.visible = any_completed

	if shown_available == 0:
		_add_empty_row()


# Mining additionally needs a Resource Survey to have already resolved at
# the CURRENT location — there's nothing to derive a deposit list from until
# then (see Deposits.deposits_for). Every other Activity has no such gate
# yet (roadmap Phase 2 scope note) and is available everywhere once owned.
func _is_available_now(activity_id: String) -> bool:
	if activity_id == "mining":
		return Research.has_resource_survey(PlayerState.location_id)
	return true


# Resource/Geological Survey specifically — the two activities that award
# Knowledge via Research.run_survey and can go stale at a body (see
# Research.can_survey_for_new_info). Mining never re-shows as "Show
# Results" this way; it has its own entirely different flow.
func _is_survey_kind(activity_id: String) -> bool:
	return activity_id == "resource_survey" or activity_id == "geological_survey"


func _add_empty_row() -> void:
	var lbl := Label.new()
	lbl.text = "Unavailable during transit." if _traveling else "Nothing available here yet."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", UITheme.dim)
	_available_box.add_child(lbl)


# The whole row is the tap target (no separate VIEW button) — instrument is
# dropped here entirely, it's one tap away on the detail panel now. Same
# "plain Button behind ignore-filtered content" idiom LocationsPanel's own
# rows use (see _add_row there): `wrapper` is an outer MarginContainer with
# TWO full-rect-fitted children, `btn` (the click target, no text/margins of
# its own so its visual background fills the whole row) and `content_margin`
# (the actual padded text, mouse_filter IGNORE so clicks fall through to
# btn). A plain Control wouldn't auto-size to fit its children the way
# MarginContainer does, which is why this isn't just one Button with text
# children added directly onto it.
func _build_available_row(activity_id: String) -> Control:
	var def := Research.activity_def(activity_id)

	var wrapper := MarginContainer.new()

	var btn := Button.new()
	UITheme.style_button(btn, UITheme.button, UITheme.button_hov, UITheme.border, 4, false)
	btn.pressed.connect(_on_view_pressed.bind(activity_id))
	btn.pressed.connect(func() -> void: AudioManager.ui_confirm())  # a raw Button, not UIButton/ConsolePadButton — those wire this on their own, this one has to do it itself
	wrapper.add_child(btn)

	var content_margin := MarginContainer.new()
	content_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_margin.add_theme_constant_override("margin_top", 8)
	content_margin.add_theme_constant_override("margin_bottom", 8)
	content_margin.add_theme_constant_override("margin_left", 10)
	content_margin.add_theme_constant_override("margin_right", 10)
	wrapper.add_child(content_margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_margin.add_child(box)

	var name_label := Label.new()
	var display_name := def.display_name.to_upper() if def != null else activity_id
	name_label.text = "%s %s" % [def.icon, display_name] if def != null and def.icon != "" else display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", UITheme.text)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	if def != null and def.description != "":
		var desc_label := Label.new()
		desc_label.text = def.description
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_label.add_theme_font_size_override("font_size", 10)
		desc_label.add_theme_color_override("font_color", UITheme.dim)
		desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(desc_label)

	# Guarded on > 0, not just != null — Mining's ActivityDef leaves this at
	# 0 deliberately (its real duration varies per-deposit, see Deposits.
	# flavor_duration_seconds, so a single flat number here would just be
	# wrong; the real figure shows one tap deeper, in DepositDetailPanel).
	if def != null and def.flavor_duration_seconds > 0:
		var time_label := Label.new()
		time_label.text = "Time: %s" % ActivityDef.format_duration(def.flavor_duration_seconds)
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		time_label.add_theme_font_size_override("font_size", 11)
		time_label.add_theme_color_override("font_color", UITheme.dim)
		time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(time_label)

	return wrapper


# Shown instead of _build_available_row once Research.can_survey_for_new_info
# is false for this body — re-running the same survey at the same (or worse)
# instrument tier wouldn't teach anything new (see Research.run_survey), so
# rather than let the player spend a real wait to learn that, the whole tile
# becomes a direct "go look at what you already found" shortcut: no
# Operation, no wait, straight to the report. Same wrapper/btn/content_margin
# whole-tile-tappable idiom as _build_available_row, just a different label
# and a different press handler (_on_show_results_pressed instead of
# _on_view_pressed). Re-enables itself back to the normal tappable row
# automatically the moment a better instrument tier is owned (this function
# isn't even called in that case — see _rebuild_rows' branch).
func _build_show_results_row(activity_id: String) -> Control:
	var def := Research.activity_def(activity_id)

	var wrapper := MarginContainer.new()

	var btn := Button.new()
	UITheme.style_button(btn, UITheme.button, UITheme.button_hov, UITheme.border, 4, false)
	btn.pressed.connect(_on_show_results_pressed.bind(activity_id))
	btn.pressed.connect(func() -> void: AudioManager.ui_confirm())  # a raw Button, not UIButton/ConsolePadButton — those wire this on their own, this one has to do it itself
	wrapper.add_child(btn)

	var content_margin := MarginContainer.new()
	content_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_margin.add_theme_constant_override("margin_top", 8)
	content_margin.add_theme_constant_override("margin_bottom", 8)
	content_margin.add_theme_constant_override("margin_left", 10)
	content_margin.add_theme_constant_override("margin_right", 10)
	wrapper.add_child(content_margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_margin.add_child(box)

	var name_label := Label.new()
	var display_name := def.display_name.to_upper() if def != null else activity_id
	name_label.text = "%s %s" % [def.icon, display_name] if def != null and def.icon != "" else display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", UITheme.text)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	var status_label := Label.new()
	status_label.text = "Show Results"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.add_theme_color_override("font_color", UITheme.dim)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(status_label)

	return wrapper


# Mining opens a different gateway (a deposit LIST to choose one material
# from — see MiningOperationsPanel's own comment on why this is never
# "extract everything") rather than ActivityDetailPanel's single confirm
# form. can_start(activity_id) — not a bare can_start() — since Mining and
# Survey are independent tracks (see Operations' own class comment): mining
# already running never blocks opening a Survey, and a Survey already
# running never blocks opening Mining.
func _on_view_pressed(activity_id: String) -> void:
	if activity_id == "mining":
		_mining_panel.open_for(PlayerState.location_id, not Operations.can_start("mining"))
	else:
		_detail_panel.open_for(activity_id, PlayerState.location_id, not Operations.can_start(activity_id))


func _build_active_row(activity_id: String, op: ActiveOperation) -> Control:
	var def := Research.activity_def(activity_id)
	var instrument := Research.current_instrument(activity_id)

	# Same bordered card framing as the AVAILABLE/COMPLETED rows (see
	# _build_completed_row) — this row used to be bare loose text, the one
	# place left with no card, which read as visually inconsistent next to
	# the bordered rows above and below it.
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = UITheme.button
	card_style.border_color = UITheme.border
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(4)
	card_style.content_margin_left = 10
	card_style.content_margin_right = 10
	card_style.content_margin_top = 8
	card_style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", card_style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var name_label := Label.new()
	var display_name := def.display_name.to_upper()
	name_label.text = "%s %s" % [def.icon, display_name] if def.icon != "" else display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", UITheme.accent)
	box.add_child(name_label)

	var instrument_label := Label.new()
	instrument_label.text = instrument.display_name if instrument != null else "—"
	instrument_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instrument_label.add_theme_font_size_override("font_size", 11)
	instrument_label.add_theme_color_override("font_color", UITheme.dim)
	box.add_child(instrument_label)

	var progress := ProgressBar.new()
	progress.custom_minimum_size = Vector2(0, 8)
	progress.show_percentage = false
	progress.min_value = 0.0
	progress.max_value = 1.0
	progress.add_theme_stylebox_override("fill", _make_bar_style(UITheme.accent, 1.0))
	progress.add_theme_stylebox_override("background", _make_bar_style(UITheme.border, 0.3))
	box.add_child(progress)

	var remaining_label := Label.new()
	remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	remaining_label.add_theme_font_size_override("font_size", 11)
	remaining_label.add_theme_color_override("font_color", UITheme.dim)
	box.add_child(remaining_label)

	# Live "flavor time remaining" countdown — the FULL flavor_duration_seconds
	# ticking down (e.g. 02:15 -> 00:00) over Operations' own real elapsed
	# time, same compression principle travel already uses: the displayed
	# number is in-fiction, the real wait (BodyInfoPanel.SCAN_DURATION) stays
	# short. Driven by _process setting progress.value each frame (see that
	# function) — value_changed fires the same way regardless of whether the
	# value came from a Tween or a direct assignment, so this wiring is
	# unchanged from when a Tween drove it.
	var update_remaining := func(value: float) -> void:
		if not is_instance_valid(remaining_label):
			return
		var remaining_seconds := int(op.flavor_duration_seconds * (1.0 - value))
		remaining_label.text = "Remaining: %s" % ActivityDef.format_duration(remaining_seconds)
	progress.value_changed.connect(update_remaining)
	progress.value = op.progress()
	update_remaining.call(op.progress())  # seed immediately — value_changed doesn't fire if op.progress() already equals the ProgressBar's default 0.0

	card.set_meta("progress", progress)
	card.set_meta("op_id", op.op_id)
	return card


# Mining's own active-card shape — deliberately NOT _build_active_row's
# progress-bar/countdown layout: mining is continuous (Operations.
# _tick_mining), with no fixed end to count down to. Instead shows the
# running session total and the deposit's live remaining%, both polled
# directly in _process (see "mining_op_id"/"mining_yield_label"/
# "mining_remaining_label" meta below), plus a STOP button — the one way
# the player can end it besides departing or fully depleting the deposit
# (see Operations.stop_mining/_finish_mining).
func _build_mining_active_row(op: ActiveOperation) -> Control:
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = UITheme.button
	card_style.border_color = UITheme.border
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(4)
	card_style.content_margin_left = 10
	card_style.content_margin_right = 10
	card_style.content_margin_top = 8
	card_style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", card_style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var status_label := Label.new()
	status_label.text = "MINING - EXTRACTING..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", UITheme.accent)
	box.add_child(status_label)

	var yield_label := Label.new()
	yield_label.text = "+%d %s" % [op.mining_session_yield, op.deposit_material]
	yield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	yield_label.add_theme_font_size_override("font_size", 13)
	yield_label.add_theme_color_override("font_color", UITheme.text)
	box.add_child(yield_label)

	var remaining_label := Label.new()
	var deposit := Deposits.deposit_for(op.location_id, op.deposit_material)
	remaining_label.text = "Deposit Remaining: %d%%" % roundi((deposit.remaining_fraction if deposit != null else 0.0) * 100.0)
	remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	remaining_label.add_theme_font_size_override("font_size", 11)
	remaining_label.add_theme_color_override("font_color", UITheme.dim)
	box.add_child(remaining_label)

	var stop_btn := UIButton.new()
	stop_btn.text = "STOP"
	stop_btn.solid = true
	stop_btn.shimmer_enabled = false
	stop_btn.custom_minimum_size = Vector2(0, 28)
	stop_btn.add_theme_font_size_override("font_size", 12)
	stop_btn.pressed.connect(func() -> void: Operations.stop_mining(op.op_id))
	box.add_child(stop_btn)

	card.set_meta("mining_op_id", op.op_id)
	card.set_meta("mining_yield_label", yield_label)
	card.set_meta("mining_remaining_label", remaining_label)
	return card


# COMPLETE-but-undismissed — the whole tile is now the tap target for
# results (same "whole row taps" idiom AVAILABLE rows use — see
# _build_available_row's wrapper/btn/content_margin structure, mirrored
# here), with a small "✕" in the corner for dismissing without ever
# looking. Shows WHICH location this result belongs to (op.location_id):
# with results now able to pile up while the player is elsewhere (e.g.
# mid-flight — see show_for_travel), there was no longer just one obvious
# candidate, and nothing else on the card distinguished one from another.
# Neither path can double-award — the reward already happened,
# unconditionally, back when Operations resolved this (see
# Operations._resolve) — this row is purely about whether the player
# bothers to LOOK.
func _build_completed_row(activity_id: String, op: ActiveOperation) -> Control:
	var def := Research.activity_def(activity_id)

	var wrapper := MarginContainer.new()

	var btn := Button.new()
	UITheme.style_button(btn, UITheme.button, UITheme.button_hov, UITheme.border, 4, false)
	btn.pressed.connect(_on_see_results_pressed.bind(op.op_id))
	btn.pressed.connect(func() -> void: AudioManager.ui_confirm())  # a raw Button, not UIButton/ConsolePadButton — those wire this on their own, this one has to do it itself
	wrapper.add_child(btn)

	var content_margin := MarginContainer.new()
	content_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_margin.add_theme_constant_override("margin_top", 8)
	content_margin.add_theme_constant_override("margin_bottom", 8)
	content_margin.add_theme_constant_override("margin_left", 10)
	content_margin.add_theme_constant_override("margin_right", 10)
	wrapper.add_child(content_margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_margin.add_child(box)

	# "RESULTS" suffix replaces the old separate "COMPLETED" line (the
	# section header above already says that) — this instead tells the
	# player what tapping the tile actually shows them.
	var name_label := Label.new()
	var display_name := def.display_name.to_upper() if def != null else activity_id
	name_label.text = "%s %s RESULTS" % [def.icon, display_name] if def != null and def.icon != "" else "%s RESULTS" % display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", UITheme.accent)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	var location_label := Label.new()
	location_label.text = op.location_id
	location_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	location_label.add_theme_font_size_override("font_size", 11)
	location_label.add_theme_color_override("font_color", UITheme.dim)
	location_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(location_label)

	# Knowledge gained shown right on the card now, not just inside the
	# opt-in results view — with "✕" letting the player skip that entirely,
	# this is the one thing they'd otherwise never see at all. has() guard:
	# this row only ever exists for a Survey now — Mining never reaches
	# COMPLETE at all (see Operations.operation_stopped) — so this quietly
	# omits itself for anything without a knowledge_awarded key rather than
	# assuming every op.result looks the same.
	if op.result.has("knowledge_awarded"):
		var knowledge_label := Label.new()
		var category: String = op.result["knowledge_category"]
		knowledge_label.text = "+%d %s Knowledge" % [op.result["knowledge_awarded"], category.capitalize()]
		knowledge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		knowledge_label.add_theme_font_size_override("font_size", 12)
		knowledge_label.add_theme_color_override("font_color", UITheme.accent)
		knowledge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(knowledge_label)

	# "✕" overlaid in the corner on its own layer, NOT arranged into `box`'s
	# vertical flow — an earlier version gave it a whole HBoxContainer row of
	# its own, wasting a full row's height on a 20px glyph. `dismiss_layer`
	# gets forced to the same full-rect as `btn`/`content_margin` by `wrapper`
	# (a MarginContainer/Container), then — being a plain Control rather than
	# a Container itself — lets dismiss_btn's own anchors/offsets place it
	# directly in the top-right corner without a Container fighting it.
	# Added last so it draws (and hit-tests) on top of `btn` in that corner —
	# an IGNORE ancestor only opts ITSELF out of hit-testing, it doesn't
	# disable a descendant Control's own (default STOP) filter, so this
	# still catches its own click before it ever reaches `btn` below.
	var dismiss_layer := Control.new()
	dismiss_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(dismiss_layer)

	# Deliberately NOT a UIButton — its corner-bracket frame decoration
	# (see UIButton._draw_bracket_frame) reads as a boxy, over-decorated
	# icon at this tiny a size instead of a plain close glyph. A bare flat
	# Button with every stylebox state forced empty gives just the "✕"
	# itself, with only its font color shifting on hover for affordance.
	var dismiss_btn := Button.new()
	dismiss_btn.text = "✕"
	dismiss_btn.flat = true
	dismiss_btn.anchor_left = 1.0
	dismiss_btn.anchor_right = 1.0
	dismiss_btn.anchor_top = 0.0
	dismiss_btn.anchor_bottom = 0.0
	dismiss_btn.offset_left = -24.0
	dismiss_btn.offset_right = -4.0
	dismiss_btn.offset_top = 2.0
	dismiss_btn.offset_bottom = 22.0
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		dismiss_btn.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	dismiss_btn.add_theme_font_size_override("font_size", 13)
	dismiss_btn.add_theme_color_override("font_color", UITheme.dim)
	dismiss_btn.add_theme_color_override("font_hover_color", UITheme.text)
	dismiss_btn.add_theme_color_override("font_pressed_color", UITheme.accent)
	dismiss_btn.pressed.connect(func() -> void:
		AudioManager.ui_confirm()  # a raw Button, not UIButton — has to do this itself
		Operations.dismiss(op.op_id))
	dismiss_layer.add_child(dismiss_btn)

	return wrapper


func _on_see_results_pressed(op_id: String) -> void:
	var op := Operations.get_operation(op_id)
	if op == null:
		return
	_show_results(op)
	Operations.dismiss(op_id)


func _make_bar_style(col: Color, alpha: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var c := col
	c.a = alpha
	sb.bg_color = c
	sb.set_corner_radius_all(2)
	return sb


# Player selects activity -> confirms in ActivityDetailPanel -> Operations
# starts and owns the operation from here on (see class comment for why).
# This function's only job is to hand off the request and get out of the
# way — no waiting, no local state.
func _start_activity(activity_id: String) -> void:
	if not Operations.can_start(activity_id):
		return  # BEGIN is disabled while busy (see ActivityDetailPanel.open_for) — defensive only
	Operations.start_survey(activity_id, PlayerState.location_id)
	_rebuild_rows()


# Mirrors _start_activity — MiningOperationsPanel/DepositDetailPanel's own
# BEGIN EXTRACTION already checked Operations.can_start("mining") before
# enabling (see DepositDetailPanel.open_for's ship_busy), this is defensive
# only.
func _start_mining(body_id: String, material_name: String) -> void:
	if not Operations.can_start("mining"):
		return
	Operations.start_mining(body_id, material_name)
	_rebuild_rows()



# Reads an already-resolved op.result (Operations._resolve populated it,
# unconditionally, back when the operation actually finished) — never
# re-runs Research.run_survey. Survey-kind only — Mining never reaches
# COMPLETE, so this row/path never fires for it (see Operations.
# operation_stopped). Uses op.location_id, NOT PlayerState.location_id —
# the player may have traveled elsewhere since this operation was started,
# and results belong to wherever they actually happened.
func _show_results(op: ActiveOperation) -> void:
	var result := op.result
	if result.is_empty():
		return

	var result_instrument: InstrumentDef = result["instrument"]
	var capability: String = result_instrument.capabilities[0] if result_instrument.capabilities.size() > 0 else ""
	var category: String = result["knowledge_category"]
	var awarded: int = result["knowledge_awarded"]

	var geo_data: GeologicalSurveyData = Research.geological_data_for(op.location_id) if op.activity_id == "geological_survey" else null
	var res_data: ResourceSurveyData = Research.resource_data_for(op.location_id) if op.activity_id == "resource_survey" else null

	if geo_data != null:
		geological_report_ready.emit(op.location_id, geo_data, category, awarded)
	elif res_data != null:
		resource_report_ready.emit(op.location_id, res_data, category, awarded)
	else:
		_result_label.text = "%s\n+%d %s Knowledge" % [capability, awarded, category.capitalize()]
		_result_label.visible = true


# The no-operation counterpart to _show_results — reached only via
# _build_show_results_row's tile (Research.can_survey_for_new_info already
# false for this body, so there's nothing to run and nothing new to award).
# Just re-displays the same report the last real survey produced here,
# reading Research's cached data directly instead of an ActiveOperation's
# result. knowledge_awarded is always 0 — SurveyReportPanel/the fallback
# label both know to show that as "already surveyed," not "+0 Knowledge."
func _on_show_results_pressed(activity_id: String) -> void:
	var def := Research.activity_def(activity_id)
	if def == null:
		return
	var location_id := PlayerState.location_id

	var geo_data: GeologicalSurveyData = Research.geological_data_for(location_id) if activity_id == "geological_survey" else null
	var res_data: ResourceSurveyData = Research.resource_data_for(location_id) if activity_id == "resource_survey" else null

	if geo_data != null:
		geological_report_ready.emit(location_id, geo_data, def.knowledge_category, 0)
	elif res_data != null:
		resource_report_ready.emit(location_id, res_data, def.knowledge_category, 0)
	else:
		_result_label.text = "Already surveyed — no new %s Knowledge available." % def.knowledge_category.capitalize()
		_result_label.visible = true
