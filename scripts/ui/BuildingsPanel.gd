class_name BuildingsPanel
extends Control

# What can be built (and what's already built) at the CURRENT location —
# split out of ActivitiesPanel (which owns Survey/Mining) because Buildings
# isn't really an "Operation": Operations are what the ship is doing right
# now, arrival-relevant, gone the moment they resolve; a structure is left
# behind and runs forever, and reviewing/upgrading one has nothing to do with
# having just arrived. Same full-rect backdrop + centered UIPanel shell as
# CargoPanel/ResearchPanel — opened on demand, never auto-opened on arrival —
# but Cockpit-scene-local rather than HUD-persistent, since "what can I build
# HERE" is exactly the same location-dependent question ActivitiesPanel
# itself is Cockpit-only for (unlike Cargo, which is location-independent).
#
# Only CONSTRUCTION (what's buildable, either fresh or as an upgrade) —
# already-standing structures no longer show here at all, see
# StructuresReadout, the always-on left-side ambient readout that replaced
# this panel's old STRUCTURES HERE section. Keeping "what can I build" and
# "what's already running" in two different places (a menu you open vs. a
# permanent glance) reads clearer than one modal trying to be both a build
# menu and a status board. A small fixed list (tier replaces in place —
# Buildings.construct overwrites the same Structure's tier, never adds a
# second one — so at most one row per category), not a scrollable list.
# Unlike CargoPanel's one-time build, content is location-dependent, so
# open() rebuilds it fresh every time rather than relying on _process alone
# to catch a body change.

const PANEL_WIDTH := 340.0

var _panel: UIPanel
var _construction_header: Label
var _construction_box: VBoxContainer
var _building_detail_panel: BuildingDetailPanel


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

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)
	vbox.add_child(UIPanel.build_title_header("Buildings"))

	_construction_header = _make_section_header("CONSTRUCTION")
	_construction_header.visible = false
	vbox.add_child(_construction_header)
	_construction_box = VBoxContainer.new()
	_construction_box.add_theme_constant_override("separation", 12)
	vbox.add_child(_construction_box)

	_add_close_button(vbox)

	_building_detail_panel = BuildingDetailPanel.new()
	_building_detail_panel.begin_requested.connect(_start_construction)
	add_child(_building_detail_panel)

	Buildings.structure_constructed.connect(func(_category_id: String, _body_id: String) -> void:
		if visible:
			_rebuild())


func open() -> void:
	_rebuild()
	visible = true
	_panel.open_animated()


func close() -> void:
	_panel.close_animated()
	await get_tree().create_timer(UIPanel.ANIM_TIME).timeout
	visible = false


func force_close() -> void:
	visible = false


func _make_section_header(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", UITheme.dim)
	return lbl


func _add_close_button(parent: VBoxContainer) -> void:
	var btn := UIButton.new()
	btn.text = "Close"
	btn.custom_minimum_size = Vector2(0, 36)
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(close)
	parent.add_child(btn)


func _rebuild() -> void:
	for child in _construction_box.get_children():
		child.queue_free()

	var any_construction := false
	var body_id := PlayerState.location_id
	for category_id: String in Buildings.category_ids():
		if Buildings.next_building_def(category_id, body_id) != null and Buildings.has_required_survey(category_id, body_id):
			_construction_box.add_child(_build_construction_row(category_id))
			any_construction = true
	_construction_header.visible = any_construction

	if not any_construction:
		var lbl := Label.new()
		# Distinguishes "nothing here has ever been built" from "everything
		# built here is already at max tier" — Buildings.structures_at is the
		# same query StructuresReadout uses to know whether this body has
		# anything running at all.
		lbl.text = "Fully upgraded here." if not Buildings.structures_at(body_id).is_empty() else "Nothing to build here yet."
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", UITheme.dim)
		_construction_box.add_child(lbl)


# Same whole-row-tappable idiom as ActivitiesPanel's AVAILABLE rows — tapping
# opens BuildingDetailPanel for a final cost/affordability confirm. A tier
# REPLACES whatever's already built here (Buildings.construct overwrites the
# same Structure's tier field, never adds a second one), so an upgrade row
# shows both the outgoing and incoming structure name (current -> arrow ->
# next), not just the next tier's name on its own — otherwise it reads like
# a second structure being added alongside the existing one.
func _build_construction_row(category_id: String) -> Control:
	var body_id := PlayerState.location_id
	var def := Buildings.next_building_def(category_id, body_id)
	var current_def := Buildings.current_building_def(category_id, body_id)
	var is_upgrade := current_def != null

	var wrapper := MarginContainer.new()

	var btn := Button.new()
	UITheme.style_button(btn, UITheme.button, UITheme.button_hov, UITheme.border, 4, false)
	btn.pressed.connect(_on_construction_pressed.bind(category_id))
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
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_margin.add_child(box)

	box.add_child(_row_label("UPGRADE" if is_upgrade else "NEW CONSTRUCTION", 10, UITheme.dim))

	if is_upgrade:
		box.add_child(_row_label(current_def.display_name.to_upper(), 12, UITheme.dim))
		box.add_child(_row_label("↓", 12, UITheme.dim))

	box.add_child(_row_label(def.display_name.to_upper(), 14, UITheme.text))
	box.add_child(_row_label(_format_cost_line(def), 11, UITheme.dim))

	return wrapper


func _row_label(text: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


# "5,000 CR, 10,000 Iron, 5,000 Silicon" — credits first, then every
# material, in whatever order BuildingDef's Dictionary happens to store them.
func _format_cost_line(def: BuildingDef) -> String:
	var parts: Array[String] = ["%s CR" % def.credits_cost]
	for material_name: String in def.materials_requirements:
		parts.append("%s %s" % [def.materials_requirements[material_name], material_name])
	return ", ".join(parts)


func _on_construction_pressed(category_id: String) -> void:
	_building_detail_panel.open_for(category_id, PlayerState.location_id)


# Mirrors ActivitiesPanel._start_activity/_start_mining — BuildingDetailPanel's
# own BUILD already checked Buildings.can_construct before enabling, this is
# defensive only. Buildings.construct itself emits structure_constructed,
# which is what actually triggers the rebuild (see _ready) — the explicit
# call here just avoids a one-frame stale display before that signal
# round-trips.
func _start_construction(category_id: String, body_id: String) -> void:
	if not Buildings.can_construct(category_id, body_id):
		return
	Buildings.construct(category_id, body_id)
	_rebuild()
