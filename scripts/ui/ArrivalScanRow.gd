class_name ArrivalScanRow
extends Control

# Docs/Arrival Scan System.md — the redesign of how Survey activities run.
# Replaces manually opening each Survey one at a time (the old ActivitiesPanel
# AVAILABLE/ACTIVE/COMPLETED gateway/detail flow — deleted entirely, see
# Cockpit._build_survey_ui) with a scrollable stack of parallel scan cards
# down the right side of the Cockpit view (same real estate the old drawer
# used). Arrival itself no longer auto-starts anything — a RUN SCANS button
# appears when at least one owned category has something new to learn, and
# pressing it fires every owned-instrument category in parallel via
# Operations.start_all_surveys, each with its own native-rate-driven
# duration, results streaming in independently as a short tiered summary
# (see refresh_for_arrival/_on_run_scans_pressed). This keeps arrival from
# ever interrupting the player's view uninvited — nothing runs until they
# choose it to. A revisit where nothing owned has new information to learn
# skips straight to a static recap card per category regardless — no
# button, no animation, no wait, since there's nothing to start either way.
#
# Cockpit-only, same CanvasLayer as SurveyReportPanel/MiningOperationsPanel
# (see Cockpit._build_survey_ui). "See More" emits geological_report_ready/
# resource_report_ready for Cockpit to relay to SurveyReportPanel; "Mine"
# emits mine_requested for Cockpit to relay to MiningOperationsPanel — Mining
# keeps its own separate gateway/active-state UI (MiningOperationsPanel/
# MiningStatusStrip) since neither fits a small scan card, see the design
# doc's "what stays manual" section.

signal geological_report_ready(location_id: String, data: GeologicalSurveyData, category: String, knowledge_awarded: int, anomaly: AnomalyResult)
signal resource_report_ready(location_id: String, data: ResourceSurveyData, category: String, knowledge_awarded: int, anomaly: AnomalyResult)
signal mine_requested(location_id: String)

# Right-side vertical stack — same screen real estate and margin values the
# old ActivitiesPanel drawer used (TOP_MARGIN/RIGHT_MARGIN/BOTTOM_MARGIN
# already tuned against this HUD's top status strip and bottom console/
# command fan), now holding auto-fired scan cards instead of a manually
# opened gateway list.
const TOP_MARGIN := 92.0
const RIGHT_MARGIN := 24.0
const BOTTOM_MARGIN := 110.0
const CARD_WIDTH := 260.0
const CARD_SEPARATION := 12.0
# Same reasoning as ActivitiesPanel's own SCROLLBAR_GUTTER — Godot's default
# ScrollContainer scrollbar overlays content instead of reserving space for
# it, so this keeps the thumb clear of each card's own right edge/border.
const SCROLLBAR_GUTTER := 16.0
# UIButton's hover scale-pop (HOVER_SCALE ≈ 1.07) grows outward from each
# button/card's own center — CARD_WIDTH * 0.07 / 2 ≈ 9px of overflow on the
# widest edge — so every non-scrollbar side of the scroll region needs at
# least that much clearance or ScrollContainer's own clip rect cuts it off.
const HOVER_MARGIN := 10.0
const BAR_HEIGHT := 6.0

# Fixed adjective ladder, reused verbatim across every native-rate category
# (Docs/Arrival Scan System.md) — the category name varies, the verdict word
# doesn't, so a player pattern-matches the word instead of re-reading a
# fresh sentence every visit. Thresholds are a first pass, not locked.
const TIER_NEGLIGIBLE := 15.0
const TIER_MINOR := 40.0
const TIER_SIGNIFICANT := 70.0

# Forced minimum gap between same-frame instant resolutions (e.g. a bare
# asteroid's Atmospheric AND Life Sciences bars both hitting a 0 native rate
# — identical duration, started the same frame, would otherwise resolve in
# the exact same frame and read as nothing happened at all).
const STAGGER_SECONDS := 0.25

var _column_box: VBoxContainer
var _run_scans_button: UIButton
var _pending_location_id: String = ""  # what "Run Scans" fires at — set by refresh_for_arrival, read by _on_run_scans_pressed
var _cards: Dictionary = {}  # activity_id -> Dictionary of node refs/state
var _reveal_queue: Array[String] = []
var _reveal_cooldown: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var column := Control.new()
	column.anchor_left = 1.0
	column.anchor_right = 1.0
	column.anchor_top = 0.0
	column.anchor_bottom = 1.0
	column.offset_left = -RIGHT_MARGIN - CARD_WIDTH - SCROLLBAR_GUTTER - HOVER_MARGIN
	column.offset_right = -RIGHT_MARGIN
	column.offset_top = TOP_MARGIN
	column.offset_bottom = -BOTTOM_MARGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	# Scrollable — up to 5 cards stacked, each with real content once
	# revealed (materials list, anomaly banner, buttons), can run taller than
	# the vertical space between the HUD's top strip and bottom console.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var scroll_margin := MarginContainer.new()
	scroll_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_theme_constant_override("margin_right", int(SCROLLBAR_GUTTER))
	# Left/top/bottom get a small buffer too — ScrollContainer clips its
	# content rect, and UIButton's hover scale-pop (HOVER_SCALE, ~7%) grows
	# outward from the button's own center, overflowing straight into that
	# clip edge on whichever side had zero margin (was cutting RUN SCANS'
	# hover state off — only the scrollbar gutter had any breathing room).
	scroll_margin.add_theme_constant_override("margin_left", int(HOVER_MARGIN))
	scroll_margin.add_theme_constant_override("margin_top", int(HOVER_MARGIN))
	scroll_margin.add_theme_constant_override("margin_bottom", int(HOVER_MARGIN))
	scroll.add_child(scroll_margin)

	_column_box = VBoxContainer.new()
	_column_box.add_theme_constant_override("separation", CARD_SEPARATION)
	_column_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_child(_column_box)

	# Sits at the top of the stack (same real estate the topmost scan card
	# occupies) so arrival doesn't auto-fire anything — the player presses
	# this when THEY want the burst to start, letting them sit and look at
	# the view uninterrupted otherwise. A permanent fixture of _column_box,
	# not a per-arrival card — _clear_cards() explicitly spares it (see
	# below) and refresh_for_arrival re-homes it to index 0 each time.
	_run_scans_button = UIButton.new()
	_run_scans_button.text = "RUN SCANS"
	_run_scans_button.accent = true
	_run_scans_button.custom_minimum_size = Vector2(0, 40)
	_run_scans_button.visible = false
	_run_scans_button.pressed.connect(_on_run_scans_pressed)
	_column_box.add_child(_run_scans_button)


func _process(delta: float) -> void:
	if _reveal_cooldown > 0.0:
		_reveal_cooldown -= delta

	for activity_id: String in _cards:
		var card: Dictionary = _cards[activity_id]
		if card.get("revealed", false):
			continue
		var op := Operations.get_operation(card.get("op_id", ""))
		if op == null:
			continue
		var bar: ProgressBar = card.get("bar")
		if is_instance_valid(bar):
			bar.value = op.progress()
		if op.status == ActiveOperation.Status.COMPLETE and not _reveal_queue.has(activity_id):
			_reveal_queue.append(activity_id)

	if _reveal_cooldown <= 0.0 and not _reveal_queue.is_empty():
		_reveal_card(_reveal_queue.pop_front())
		_reveal_cooldown = STAGGER_SECONDS


# The single entry point Cockpit calls at arrival (both the cold-load and
# post-orbit-settle call sites, same moment ActivitiesPanel.refresh() used
# to fire alone). Deliberately does NOT auto-start anything anymore — a
# category with something new to learn shows the RUN SCANS button instead
# of firing immediately, so arrival never interrupts the player's view
# unless/until they choose it to. Anything already RUNNING (reattaching to
# an in-progress scan from a moment ago) and anything with nothing new to
# learn (instant recap) still show immediately either way — neither of
# those involves auto-*starting* anything, so there's nothing to gate.
func refresh_for_arrival(location_id: String) -> void:
	_clear_cards()
	_pending_location_id = location_id

	var any_card := false
	var any_startable := false
	for activity_id: String in Research.available_activities():
		if not Research.is_survey_kind(activity_id):
			continue

		var existing := Operations.operation_for_activity(activity_id)
		if existing != null and existing.status == ActiveOperation.Status.RUNNING and existing.location_id == location_id:
			_add_scanning_card(activity_id, existing.op_id)
			any_card = true
		elif Research.can_survey_for_new_info(activity_id, location_id) and Operations.can_start(activity_id):
			# Nothing running for it here yet, but there's something new to
			# learn — exactly what RUN SCANS will act on (mirrors
			# Operations.start_all_surveys's own per-activity gate). Don't
			# build a card until the player actually presses it.
			any_startable = true
		elif Research.can_survey_for_new_info(activity_id, location_id):
			# Already RUNNING against a DIFFERENT body (a rare edge case,
			# departing mid-scan and returning before it resolves) — nothing
			# new is cached yet either. Deliberately shows no card rather
			# than a premature/wrong one.
			continue
		else:
			_add_recap_card(activity_id, location_id)
			any_card = true

	_run_scans_button.visible = any_startable
	if any_startable:
		_column_box.move_child(_run_scans_button, 0)  # top of the stack, same slot the topmost card would occupy

	visible = any_card or any_startable


# RUN SCANS press handler — the actual Operations.start_all_surveys call
# that used to fire automatically in refresh_for_arrival now lives here
# instead, gated behind the player's own choice.
func _on_run_scans_pressed() -> void:
	_run_scans_button.visible = false

	var started := Operations.start_all_surveys(_pending_location_id)
	if not started.is_empty():
		AudioManager.scans_initiated()
		AudioManager.start_survey_ambient()
	for op_id: String in started:
		var op := Operations.get_operation(op_id)
		if op != null:
			_add_scanning_card(op.activity_id, op_id)
	visible = true


func hide_for_travel() -> void:
	visible = false
	# Whatever was still scanning keeps ticking in the background (Operations
	# owns that, survives the scene/view change same as it always has) — but
	# the ambient loop is a purely audible/visual burst cue, and it would
	# otherwise never get a chance to stop if departure happens mid-burst
	# (the next refresh_for_arrival clears _cards without ever passing back
	# through _reveal_card's own stop for whatever was still running).
	AudioManager.stop_survey_ambient()


func _clear_cards() -> void:
	for child in _column_box.get_children():
		if child != _run_scans_button:
			child.queue_free()
	_run_scans_button.visible = false
	_cards.clear()
	_reveal_queue.clear()
	_reveal_cooldown = 0.0
	# Defensive — stops a still-playing ambient from a previous burst that
	# never reached _reveal_card's own stop (e.g. re-arriving here again
	# before it finished). Idempotent, and refresh_for_arrival restarts it
	# fresh below if the new burst has anything of its own.
	AudioManager.stop_survey_ambient()


# --- Card construction ---

func _add_scanning_card(activity_id: String, op_id: String) -> void:
	var def := Research.activity_def(activity_id)
	var card_root := _build_card_shell(def)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.add_theme_stylebox_override("fill", _make_bar_style(UITheme.accent, 1.0))
	bar.add_theme_stylebox_override("background", _make_bar_style(UITheme.border, 0.3))
	card_root["box"].add_child(bar)

	var result_box := VBoxContainer.new()
	result_box.add_theme_constant_override("separation", 4)
	result_box.visible = false
	card_root["box"].add_child(result_box)

	_cards[activity_id] = {
		"op_id": op_id,
		"bar": bar,
		"result_box": result_box,
		"revealed": false,
	}


# Revisit path — nothing running, no wait, no animation. Populates directly
# from cached Research/NativeRate data (mirrors the old ActivitiesPanel
# "Show Results" shortcut's own cached-lookup logic).
func _add_recap_card(activity_id: String, location_id: String) -> void:
	var def := Research.activity_def(activity_id)
	var card_root := _build_card_shell(def)

	var result_box := VBoxContainer.new()
	result_box.add_theme_constant_override("separation", 4)
	card_root["box"].add_child(result_box)

	_cards[activity_id] = {
		"result_box": result_box,
		"revealed": true,
	}
	_populate_result(activity_id, result_box, location_id)


func _build_card_shell(def: ActivityDef) -> Dictionary:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.button
	style.border_color = UITheme.border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column_box.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	var name_label := Label.new()
	var display_name := def.display_name.to_upper() if def != null else "SURVEY"
	name_label.text = "%s %s" % [def.icon, display_name] if def != null and def.icon != "" else display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", UITheme.text)
	box.add_child(name_label)

	return {"card": card, "box": box}


func _make_bar_style(col: Color, alpha: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var c := col
	c.a = alpha
	sb.bg_color = c
	sb.set_corner_radius_all(2)
	return sb


# --- Reveal / result population ---

func _reveal_card(activity_id: String) -> void:
	var card: Dictionary = _cards.get(activity_id)
	if card == null:
		return
	var op := Operations.get_operation(card.get("op_id", ""))
	if op == null:
		return

	card["revealed"] = true
	var bar: ProgressBar = card.get("bar")
	if is_instance_valid(bar):
		bar.visible = false
	var result_box: VBoxContainer = card["result_box"]
	result_box.visible = true

	# op.location_id, not whatever the row's own most-recent arrival was —
	# the player may have already left for a body while this one was still
	# ticking in the background (Operations' whole reason to exist). The
	# knowledge award itself isn't surfaced as its own line here (deliberately
	# minimal, per Docs/Arrival Scan System.md's compact-summary examples) —
	# it's still fully applied via Research.run_survey regardless of whether
	# this card is ever looked at.
	_populate_result(activity_id, result_box, op.location_id)
	Operations.dismiss(op.op_id)

	if not _any_card_still_scanning():
		AudioManager.stop_survey_ambient()
		AudioManager.scans_complete()


# Single source of truth for "is the burst done" — derived directly from
# _cards' own revealed flags every time, not a separately-maintained
# counter. A counter that increments in refresh_for_arrival and decrements
# here can drift out of sync with what's actually in _cards (this was the
# real bug behind the VO firing on every bar instead of just the last one:
# once the counter dipped to/past zero early, the `<= 0` check stayed true
# for every subsequent bar too). This can't drift — it just asks the cards.
func _any_card_still_scanning() -> bool:
	for card: Dictionary in _cards.values():
		if not card.get("revealed", false):
			return true
	return false


func _populate_result(activity_id: String, result_box: VBoxContainer, location_id: String) -> void:
	for child in result_box.get_children():
		child.queue_free()

	var def := Research.activity_def(activity_id)
	if def == null:
		return
	var anomaly := NativeRate.anomaly_for(location_id, def.knowledge_category)

	if anomaly != null:
		var banner := Label.new()
		banner.text = "⚠ %s ANOMALY DETECTED ⚠\n%s" % [anomaly.magnitude.to_upper(), anomaly.name]
		banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner.autowrap_mode = TextServer.AUTOWRAP_WORD
		banner.add_theme_font_size_override("font_size", 11)
		banner.add_theme_color_override("font_color", SurveyReportPanel.ANOMALY_COLOR)
		result_box.add_child(banner)

	if activity_id == "resource_survey":
		_populate_resource_result(result_box, location_id, anomaly)
	else:
		_populate_rated_result(activity_id, def, result_box, location_id, anomaly)


func _populate_rated_result(activity_id: String, def: ActivityDef, result_box: VBoxContainer, location_id: String, anomaly: AnomalyResult) -> void:
	var rate := clampf(NativeRate.for_category(def.knowledge_category, location_id), 0.0, 100.0)
	var tier := _tier_for(rate)
	var category_word: String = def.knowledge_category.replace("_", " ")

	var summary := Label.new()
	summary.text = "%s %s data acquired." % [tier[0], category_word]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	summary.add_theme_font_size_override("font_size", 12)
	summary.add_theme_color_override("font_color", tier[1])
	result_box.add_child(summary)

	# "See More" only where a rich report class actually exists today
	# (Geological/Resource) — Astrophysics/Life Sciences/Atmospheric fall
	# back to the one-liner above being the whole story, matching the design
	# doc's own deferral rather than opening an empty/placeholder panel.
	if activity_id == "geological_survey":
		var geo_data := Research.geological_data_for(location_id)
		if geo_data != null:
			var see_more := UIButton.new()
			see_more.text = "See More"
			see_more.solid = true
			see_more.shimmer_enabled = false
			see_more.custom_minimum_size = Vector2(0, 26)
			see_more.add_theme_font_size_override("font_size", 11)
			see_more.pressed.connect(func() -> void:
				geological_report_ready.emit(location_id, geo_data, def.knowledge_category, 0, anomaly))
			result_box.add_child(see_more)


func _populate_resource_result(result_box: VBoxContainer, location_id: String, anomaly: AnomalyResult) -> void:
	var data := Research.resource_data_for(location_id)
	var names: Array[String] = []
	if data != null:
		for finding: ResourceMaterialFinding in data.materials:
			names.append(finding.material_name)

	var summary := Label.new()
	summary.text = ", ".join(names) if not names.is_empty() else "No materials detected."
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	summary.add_theme_font_size_override("font_size", 12)
	summary.add_theme_color_override("font_color", UITheme.text if not names.is_empty() else UITheme.dim)
	result_box.add_child(summary)

	if names.is_empty():
		return

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 6)
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	result_box.add_child(button_row)

	var mine_btn := UIButton.new()
	mine_btn.text = "Mine"
	mine_btn.solid = true
	mine_btn.shimmer_enabled = false
	mine_btn.custom_minimum_size = Vector2(0, 26)
	mine_btn.add_theme_font_size_override("font_size", 11)
	mine_btn.pressed.connect(func() -> void: mine_requested.emit(location_id))
	button_row.add_child(mine_btn)

	if data != null:
		var see_more := UIButton.new()
		see_more.text = "Details"
		see_more.dim = true
		see_more.shimmer_enabled = false
		see_more.custom_minimum_size = Vector2(0, 26)
		see_more.add_theme_font_size_override("font_size", 11)
		see_more.pressed.connect(func() -> void:
			resource_report_ready.emit(location_id, data, "resource", 0, anomaly))
		button_row.add_child(see_more)


func _tier_for(rate: float) -> Array:
	if rate < TIER_NEGLIGIBLE:
		return ["Negligible", UITheme.dim]
	if rate < TIER_MINOR:
		return ["Minor", UITheme.text]
	if rate < TIER_SIGNIFICANT:
		return ["Significant", UITheme.accent]
	return ["Exceptional", UITheme.accent]
