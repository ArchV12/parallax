class_name ResearchPanel
extends Control

# The in-game Research dashboard — reached via the console's RESEARCH button.
# Redesigned 2026-07-18 (Docs/Upgrading.md) into a Ship Equipment tech tree:
# one row per Research.equipment_slot_ids() (Docs/Ship Equipment.md's own 6
# slots, in that order), 5 cards each — one card per tier. Science Activities
# (Resource/Geological/Astrophysics/Life Sciences/Atmospheric Survey, Mining)
# no longer get their own display here at all; their instrument progression
# moved entirely onto Ship Equipment slots (Scanner Array, Mining System) —
# see Research.gd's own comment on EQUIPMENT_SLOT_PATHS for why they safely
# share Research's underlying owned_tier/craft mechanics without needing a
# parallel system.
#
# Card states, left to right within a row, driven purely by
# Research.owned_tier(slot_id):
# - index <= owned_tier: OWNED (green border) — a tier the player already has.
# - index == owned_tier + 1: NEXT (revealed) — two visibly distinct PHASES
#   within this one state (2026-07-18 ask), not shown together:
#     Phase 1 (RESEARCH, accent border) — Research.is_craftable(slot_id) is
#     false: Knowledge requirements aren't fully met yet, so only the
#     Knowledge cost shows (Materials aren't relevant until the blueprint is
#     actually unlocked).
#     Phase 2 (CRAFT, amber border) — is_craftable is true: Knowledge is
#     done, so only the Materials cost shows now; clicking crafts
#     immediately if Research.can_craft(slot_id) (Materials affordable) is
#     also true.
#   Each requirement line is colored green (currently met) or red (not).
# - index > owned_tier + 1: LOCKED ("?", dim border) — completely unknown,
#   not interactive.
# A "→" connector sits between every pair of cards in a row to read as a path.

# 2026-07-18 revision (user feedback on the first screenshot): cards were
# too narrow (long names like "Precision Mining Laser" clipped) and the
# panel too short to show all 6 rows without an awkward vertical scrollbar.
# Fix: wider/taller cards, a taller panel that fits all 6 rows, and the
# ScrollContainer flipped from vertical to HORIZONTAL scroll — with wider
# cards a row can exceed even a wide panel, so overflow scrolls sideways
# instead of the whole grid needing to shrink to fit.
const PANEL_WIDTH := 1000.0
const LIST_HEIGHT := 620.0
const CARD_SIZE := Vector2(190, 112)
const SLOT_LABEL_WIDTH := 150.0
const ROW_SEPARATION := 14
# Godot's default ScrollContainer scrollbar overlays content instead of
# reserving space for it — SCROLLBAR_GUTTER reserves space for it on
# whichever edge the (now horizontal) scrollbar actually sits, the bottom.
# HOVER_MARGIN mirrors the same fix SellCargoPanel/ArrivalScanRow already
# needed on the other 3 edges: UITheme.wire_hover_pop's scale-up otherwise
# gets clipped by the ScrollContainer on cards flush against its edges.
const SCROLLBAR_GUTTER := 16
const HOVER_MARGIN := 10

const OWNED_BORDER := Color(0.35, 0.85, 0.40)
const LOCKED_BORDER := Color(0.3, 0.32, 0.36)

# The revealed (NEXT) card's two phases need visibly different borders —
# UITheme.accent while still researching (Knowledge phase, used directly at
# the call site since it's a runtime autoload value, not a real constant), a
# distinct amber once the blueprint's unlocked and it's down to paying
# Materials (Craft phase).
const PHASE_CRAFT_BORDER := Color(0.85, 0.65, 0.15)

# Per-requirement cost line colors on a revealed card (2026-07-18 ask) — MET
# reuses OWNED_BORDER's green (same "you have this" language the card
# border already uses); UNMET is a plain red, distinct from either border
# color already in use.
const REQUIREMENT_MET_COLOR := OWNED_BORDER
const REQUIREMENT_UNMET_COLOR := Color(0.85, 0.35, 0.35)

var _panel: UIPanel
var _rows_box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.65)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = UIPanel.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	center.add_child(_panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(outer_vbox)
	outer_vbox.add_child(UIPanel.build_title_header("Research"))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_vbox.add_child(scroll)

	var scroll_margin := MarginContainer.new()
	scroll_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_theme_constant_override("margin_bottom", SCROLLBAR_GUTTER)
	scroll_margin.add_theme_constant_override("margin_left", HOVER_MARGIN)
	scroll_margin.add_theme_constant_override("margin_top", HOVER_MARGIN)
	scroll_margin.add_theme_constant_override("margin_right", HOVER_MARGIN)
	scroll.add_child(scroll_margin)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", ROW_SEPARATION)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_child(_rows_box)

	_add_close_button(outer_vbox)

	# Same three-signal live-refresh precedent this panel already used before
	# the redesign — a craft/milestone/mining-stop can change what a card
	# should show while this panel is already sitting open.
	Operations.operation_completed.connect(func(_op_id: String) -> void: _rebuild())
	Operations.operation_stopped.connect(func(_activity_id: String, _location_id: String, _summary: Dictionary) -> void: _rebuild())
	Research.milestone_reached.connect(func(_tech: TechnologyDef) -> void: _rebuild())


func open() -> void:
	_rebuild()
	visible = true
	_panel.open_animated()


func close() -> void:
	_panel.close_animated()
	await get_tree().create_timer(UIPanel.ANIM_TIME).timeout
	visible = false


# Skips the close animation — used when leaving gameplay entirely, same as
# PauseMenu.force_close.
func force_close() -> void:
	visible = false


func _add_close_button(parent: VBoxContainer) -> void:
	var btn := UIButton.new()
	btn.text = "Close"
	btn.custom_minimum_size = Vector2(0, 36)
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(close)
	parent.add_child(btn)


func _rebuild() -> void:
	for child in _rows_box.get_children():
		child.queue_free()
	for slot_id: String in Research.equipment_slot_ids():
		_rows_box.add_child(_build_row(slot_id))


func _build_row(slot_id: String) -> Control:
	var def := Research.activity_def(slot_id)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var slot_label := Label.new()
	slot_label.text = (def.display_name if def != null else slot_id).to_upper()
	slot_label.custom_minimum_size = Vector2(SLOT_LABEL_WIDTH, 0)
	slot_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_label.add_theme_font_size_override("font_size", 13)
	slot_label.add_theme_color_override("font_color", UITheme.accent)
	row.add_child(slot_label)

	if def == null:
		return row

	var owned_tier := Research.owned_tier(slot_id)
	# Beyond Light Engines' instruments[0] is a real "None" InstrumentDef,
	# needed so its owned_tier can start at 0 and reuse the exact same
	# index==owned_tier tech-indexing every other slot uses (see Research.gd's
	# own comment on STARTING_ACTIVITIES) — but it isn't a real equipment
	# tier a player ever chooses to display, so this row skips it and starts
	# at index 1, keeping every row visually at 5 cards as the doc asks for.
	var start_index := 1 if slot_id == "beyond_light_engines" else 0
	for i in range(start_index, def.instruments.size()):
		if i > start_index:
			row.add_child(_build_arrow())
		row.add_child(_build_card(slot_id, def, i, owned_tier))

	return row


func _build_arrow() -> Control:
	var lbl := Label.new()
	lbl.text = "→"
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", UITheme.dim)
	return lbl


func _build_card(slot_id: String, def: ActivityDef, index: int, owned_tier: int) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = CARD_SIZE
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = ""  # content is composited via overlaid Labels below, not btn.text — see _build_card_content

	if index <= owned_tier:
		_style_card(btn, OWNED_BORDER, UITheme.slot)
		btn.add_child(_build_card_content(def.instruments[index].display_name, "", []))
		btn.disabled = true
	elif index == owned_tier + 1:
		var tech := Research.next_technology(slot_id)
		var knowledge_done := Research.is_craftable(slot_id)
		var affordable := Research.can_craft(slot_id)
		_style_card(btn, PHASE_CRAFT_BORDER if knowledge_done else UITheme.accent, UITheme.slot)
		var phase_label := ""
		var lines: Array[Dictionary] = []
		if tech != null:
			if knowledge_done:
				phase_label = "MATERIALS REQUIRED"
				lines = _materials_lines(tech)
			else:
				phase_label = "RESEARCH REQUIRED"
				lines = _knowledge_lines(tech)
		btn.add_child(_build_card_content(def.instruments[index].display_name, phase_label, lines))
		btn.tooltip_text = _requirements_tooltip(tech) if tech != null else ""
		btn.disabled = tech == null or not affordable
		if tech != null:
			btn.pressed.connect(_on_card_pressed.bind(slot_id))
	else:
		_style_card(btn, LOCKED_BORDER, UITheme.slot)
		var mark := Label.new()
		mark.text = "?"
		mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.add_theme_font_size_override("font_size", 22)
		mark.add_theme_color_override("font_color", UITheme.dim)
		btn.add_child(mark)
		btn.disabled = true

	UITheme.wire_hover_pop(btn, 1.05)
	return btn


# name_label, an optional phase_label ("RESEARCH REQUIRED"/"MATERIALS
# REQUIRED" — 2026-07-18 ask, makes the NEXT card's two phases visibly
# distinct beyond just the border color), plus one colored label per
# cost_lines entry. Used for the OWNED state (name only, no phase_label, no
# cost_lines) and the NEXT state (name + phase_label + that phase's own
# requirement lines, each colored green if currently met or red if not). A
# plain Button can only ever show ONE font size/color for its whole .text,
# so all of this needs its own overlaid Labels (mouse_filter IGNORE, same
# "let clicks fall through to the button underneath" idiom LocationsPanel's
# row labels already use) rather than being packed into btn.text itself.
func _build_card_content(name_text: String, phase_label: String, cost_lines: Array[Dictionary]) -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(box)

	var name_label := Label.new()
	name_label.text = name_text
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", UITheme.text)
	box.add_child(name_label)

	if not phase_label.is_empty():
		var phase_header := Label.new()
		phase_header.text = phase_label
		phase_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		phase_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		phase_header.add_theme_font_size_override("font_size", 10)
		phase_header.add_theme_color_override("font_color", UITheme.dim)
		box.add_child(phase_header)

	for line: Dictionary in cost_lines:
		var cost_label := Label.new()
		cost_label.text = line["text"]
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cost_label.add_theme_font_size_override("font_size", 11)
		cost_label.add_theme_color_override("font_color", REQUIREMENT_MET_COLOR if line["met"] else REQUIREMENT_UNMET_COLOR)
		box.add_child(cost_label)

	return margin


# Phase 1 (Knowledge) requirement lines only — shown while
# Research.is_craftable(slot_id) is still false. One line per Knowledge
# category, tagged with whether the player currently has enough so
# _build_card_content can color it green/red.
func _knowledge_lines(tech: TechnologyDef) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for category_id: String in tech.knowledge_requirements:
		var required: int = tech.knowledge_requirements[category_id]
		var have := Research.knowledge(category_id)
		lines.append({"text": "%s: %d" % [category_id.capitalize(), required], "met": have >= required})
	return lines


# Phase 2 (Materials/Craft) requirement lines only — shown once
# Research.is_craftable(slot_id) is true (Knowledge is done, so it's no
# longer relevant to show). One line per Material, same met/unmet tagging.
func _materials_lines(tech: TechnologyDef) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for material_name: String in tech.materials_requirements:
		var required_amount: int = tech.materials_requirements[material_name]
		var have_amount := Deposits.material_amount(material_name)
		lines.append({"text": "%s: %s" % [material_name, Deposits.format_units(required_amount)], "met": have_amount >= required_amount})
	return lines


func _requirements_tooltip(tech: TechnologyDef) -> String:
	var lines: Array[String] = [tech.display_name]
	for category_id: String in tech.knowledge_requirements:
		var required: int = tech.knowledge_requirements[category_id]
		var have := Research.knowledge(category_id)
		lines.append("%s Knowledge: %d / %d" % [category_id.capitalize(), have, required])
	for material_name: String in tech.materials_requirements:
		var required_amount: int = tech.materials_requirements[material_name]
		var have_amount := Deposits.material_amount(material_name)
		lines.append("%s: %s / %s" % [material_name, Deposits.format_units(have_amount), Deposits.format_units(required_amount)])
	return "\n".join(lines)


# _rebuild() unconditionally, regardless of Research.craft_technology's
# return value — it returns null (a no-op) if state changed between this
# card being rendered and the button actually being pressed (can_craft was
# re-checked and failed), and the rebuild is what shows the player why. Only
# plays the install_complete VO line when the craft actually SUCCEEDED (a
# non-null return) — a stale/failed press shouldn't announce an install
# that didn't happen.
func _on_card_pressed(slot_id: String) -> void:
	var tech := Research.craft_technology(slot_id)
	if tech != null:
		AudioManager.play_vo("install_complete")
	_rebuild()


func _style_card(btn: Button, border_col: Color, bg_col: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg_col
	normal.border_color = border_col
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("disabled", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = bg_col.lightened(0.08)
	hover.border_color = border_col.lightened(0.2)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = bg_col.darkened(0.15)
	pressed.border_color = border_col
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("pressed", pressed)
