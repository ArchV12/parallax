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
# Gateway/detail/active-operations flow: an AVAILABLE row (the whole row is
# the tap target, not a separate VIEW button) opens ActivityDetailPanel
# (Target/Instrument/Status/Estimated Duration/Potential Discoveries + BEGIN
# SURVEY); starting one moves it into its own ACTIVE OPERATIONS row with a
# live progress bar here, then back to AVAILABLE (with a result) once it
# finishes. Only one operation at a time for now — _running_activity_id —
# multiple concurrent is future scope.
#
# Availability isn't gated per-location yet (see the roadmap's Phase 2 scope
# note) — the same list shows at every destination for now; only which
# instrument tier is owned changes what's on it.

# Fired after a Geological or Resource Survey run when hand-authored rich
# report content exists for the current body (Research.geological_data_for/
# resource_data_for) — Cockpit connects these to SurveyReportPanel's two
# show_*_report entry points, which display the Knowledge-awarded line
# themselves (category/knowledge_awarded, carried here). Not fired at all
# for activities/bodies without one — _result_label's flat "+N Knowledge"
# text is the fallback ONLY for that case now (see _start_activity); showing
# it AND a popup at the same time was redundant.
signal geological_report_ready(location_id: String, data: GeologicalSurveyData, category: String, knowledge_awarded: int)
signal resource_report_ready(location_id: String, data: ResourceSurveyData, category: String, knowledge_awarded: int)

const PANEL_WIDTH := 300.0
const TAB_WIDTH := 30.0
const TAB_HEIGHT := 64.0  # a grab handle, not the full drawer height
const TOP_MARGIN := 92
const RIGHT_MARGIN := 24
const BOTTOM_MARGIN := 210  # stays clear of ConsolePanel's center band
const SLIDE_DURATION := 0.28

var _drawer: Control
var _tab: Button
var _panel: UIPanel
var _active_header: Label
var _active_box: VBoxContainer
var _available_box: VBoxContainer
var _result_label: Label
var _detail_panel: ActivityDetailPanel
var _expanded := false

var _running_activity_id: String = ""


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
	_drawer.visible = false  # nothing to show until the first refresh() (arrival) — see hide_panel/refresh
	add_child(_drawer)

	_build_tab()
	_build_panel()

	_detail_panel = ActivityDetailPanel.new()
	_detail_panel.begin_requested.connect(_start_activity)
	add_child(_detail_panel)

	# A milestone can be granted by ANYTHING that calls Research.add_knowledge
	# — not just this panel's own survey flow (e.g. the F2 Cheat Menu's
	# Science Cheat) — so an AVAILABLE row's instrument subtitle stays in
	# sync regardless of what triggered it. Deliberately only touches the
	# AVAILABLE section, never the active one — see _rebuild_available_rows'
	# own comment for why that matters.
	Research.milestone_reached.connect(func(_tech: TechnologyDef) -> void: _rebuild_available_rows())

	_set_expanded(false, false)  # collapsed initial offsets, no animation — refresh() is what actually reveals this


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
	_tab.tooltip_text = "Activities"
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
	vbox.add_child(UIPanel.build_title_header("Activities"))

	_active_header = _make_section_header("ACTIVE OPERATIONS")
	_active_header.visible = false
	vbox.add_child(_active_header)
	_active_box = VBoxContainer.new()
	_active_box.add_theme_constant_override("separation", 12)
	vbox.add_child(_active_box)

	vbox.add_child(_make_section_header("AVAILABLE ACTIVITIES"))

	# Scrollable — same reasoning as LocationsPanel's own rows container:
	# this list only grows as more Activities get built, and a fixed-height
	# drawer needs somewhere for that growth to go besides off the bottom.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_available_box = VBoxContainer.new()
	_available_box.add_theme_constant_override("separation", 12)
	_available_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_available_box)

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


# Rebuilds the AVAILABLE list from Research's current state, reveals the
# drawer, and resets it to fully expanded — every fresh arrival defaults
# open regardless of whatever collapsed/expanded state a PREVIOUS visit left
# it in (collapse-then-reopen gives the same reveal every single time, not
# just whichever state happened to carry over). Call this on every arrival
# (_build_arrival). Never touches the active section — a fresh arrival
# always starts with nothing running (Cockpit rebuilds this whole panel from
# scratch every scene load).
func refresh() -> void:
	_drawer.visible = true
	_rebuild_available_rows()
	_set_expanded(false, false)
	_set_expanded(true)


# Rebuilds ONLY the AVAILABLE section — deliberately never touches
# _active_box. This is what makes it safe to call from the milestone
# subscription above at any time, including mid-operation: an in-flight
# tween is still driving the (untouched, still-valid) active row's progress
# bar, so there's no freed-object risk the way rebuilding it would create
# (see _start_activity's own comment for that lesson). Shows a placeholder
# row rather than hiding anything if nothing's available — the drawer and
# its tab stay reachable regardless, same as LocationsPanel's own empty state.
func _rebuild_available_rows() -> void:
	for child in _available_box.get_children():
		child.queue_free()

	var ids := Research.available_activities()
	var shown := 0
	for id: String in ids:
		if id == _running_activity_id:
			continue
		_available_box.add_child(_build_available_row(id))
		shown += 1

	if shown == 0:
		_add_empty_row()


func _add_empty_row() -> void:
	var lbl := Label.new()
	lbl.text = "Nothing available here yet."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", UITheme.dim)
	_available_box.add_child(lbl)


# Instant, unanimated hide for departure — matches the rest of Cockpit's
# "moon hidden for the duration of the trip" gameplay-state hides (see
# Cockpit._hidden_from_body), not the drawer's own interactive slide.
func hide_panel() -> void:
	_drawer.visible = false


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

	if def != null:
		var time_label := Label.new()
		time_label.text = "Time: %s" % ActivityDef.format_duration(def.flavor_duration_seconds)
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		time_label.add_theme_font_size_override("font_size", 11)
		time_label.add_theme_color_override("font_color", UITheme.dim)
		time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(time_label)

	return wrapper


func _on_view_pressed(activity_id: String) -> void:
	_detail_panel.open_for(activity_id, PlayerState.location_id, _running_activity_id != "")


func _build_active_row(activity_id: String, def: ActivityDef, instrument: InstrumentDef) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

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
	remaining_label.text = "Remaining: %s" % ActivityDef.format_duration(def.flavor_duration_seconds)
	remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	remaining_label.add_theme_font_size_override("font_size", 11)
	remaining_label.add_theme_color_override("font_color", UITheme.dim)
	box.add_child(remaining_label)

	# Live "flavor time remaining" countdown — the FULL flavor_duration_seconds
	# ticking down (e.g. 02:15 -> 00:00) over the SHORT real animation window
	# (BodyInfoPanel.SCAN_DURATION), same compression principle travel
	# already uses: the displayed number is in-fiction, the real wait stays
	# short. is_instance_valid guards are extra insurance, not load-bearing —
	# progress/remaining_label are always freed together (same `box`,
	# _finish_activity's single queue_free) so one can't outlive the other.
	progress.value_changed.connect(func(value: float) -> void:
		if not is_instance_valid(remaining_label):
			return
		var remaining_seconds := int(def.flavor_duration_seconds * (1.0 - value))
		remaining_label.text = "Remaining: %s" % ActivityDef.format_duration(remaining_seconds))

	box.set_meta("progress", progress)
	return box


func _make_bar_style(col: Color, alpha: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var c := col
	c.a = alpha
	sb.bg_color = c
	sb.set_corner_radius_all(2)
	return sb


# Player selects activity -> confirms in ActivityDetailPanel -> ship begins
# operation (moves from AVAILABLE to its own ACTIVE OPERATIONS row) ->
# progress bar -> results generated/Knowledge awarded/possible discoveries
# (_finish_activity, once the bar fills). Deliberately all the way from here
# through _finish_activity without ever splitting the running row's Node
# references across a typed-parameter function-call boundary — a row freed
# mid-animation (see _rebuild_available_rows' own comment on why THAT stays
# safe) taught that GDScript hard-errors passing an already-freed Object
# through ANY typed parameter, even the base Object type, before a callee's
# body (is_instance_valid included) ever runs. Keeping it one function with
# only local variables sidesteps that entirely.
func _start_activity(activity_id: String) -> void:
	if _running_activity_id != "":
		return  # BEGIN is disabled while busy (see ActivityDetailPanel.open_for) — defensive only
	var def := Research.activity_def(activity_id)
	var instrument := Research.current_instrument(activity_id)
	if def == null or instrument == null:
		return

	_running_activity_id = activity_id
	_result_label.visible = false
	_rebuild_available_rows()  # removes this activity from AVAILABLE

	_active_header.visible = true
	var row := _build_active_row(activity_id, def, instrument)
	_active_box.add_child(row)
	var progress: ProgressBar = row.get_meta("progress")

	var tw := create_tween()
	tw.tween_property(progress, "value", 1.0, BodyInfoPanel.SCAN_DURATION)
	await tw.finished

	if is_instance_valid(row):
		row.queue_free()
	_running_activity_id = ""
	# queue_free is deferred (the row isn't actually gone from
	# _active_box's children until later this frame) — but only one
	# operation ever runs at a time, so it's always safe to say the active
	# section is empty again right here, without re-checking child count.
	_active_header.visible = false

	var result := Research.run_survey(activity_id)
	if result.is_empty():
		_rebuild_available_rows()
		return

	var result_instrument: InstrumentDef = result["instrument"]
	var capability: String = result_instrument.capabilities[0] if result_instrument.capabilities.size() > 0 else ""
	var category: String = result["knowledge_category"]
	var awarded: int = result["knowledge_awarded"]
	# Research.run_survey's internal add_knowledge call already fired
	# milestone_reached (synchronously, before this runs) for anything
	# granted — _rebuild_available_rows below picks up any tier change.

	# A rich report (when one exists for this body) shows the Knowledge
	# line itself — see SurveyReportPanel.show_*_report. _result_label is
	# ONLY the fallback for bodies/activities with no report, so Knowledge
	# never shows in two places for the same survey.
	var geo_data: GeologicalSurveyData = Research.geological_data_for(PlayerState.location_id) if activity_id == "geological_survey" else null
	var res_data: ResourceSurveyData = Research.resource_data_for(PlayerState.location_id) if activity_id == "resource_survey" else null

	if geo_data != null:
		geological_report_ready.emit(PlayerState.location_id, geo_data, category, awarded)
	elif res_data != null:
		resource_report_ready.emit(PlayerState.location_id, res_data, category, awarded)
	else:
		_result_label.text = "%s\n+%d %s Knowledge" % [capability, awarded, category.capitalize()]
		_result_label.visible = true

	_rebuild_available_rows()
