class_name ResearchPanel
extends Control

# The in-game Research dashboard — reached via the console's RESEARCH button
# (Docs/Science and Knowledge System - Implementation Roadmap.md, Phase 4).
# Read-only: surfaces exactly what Research.gd already tracks (Knowledge per
# category, current instrument, next milestone + requirement progress) — no
# new mechanics, all of it built by Phases 1-3. Same full-rect
# backdrop+centered UIPanel shape as PauseMenu/CheatMenu.
#
# Lists every KNOWN activity (Research.known_activities()), not just
# unlocked ones — an activity with no starting instrument still gets a card
# here (shown LOCKED), matching the vision doc's framing that a category's
# progress is visible even before you can act on it. Only Resource Survey
# exists so far, so there's nothing yet to demonstrate that with.

const PANEL_WIDTH := 420.0
const LIST_HEIGHT := 420.0

var _panel: UIPanel
var _cards_box: VBoxContainer


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
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_vbox.add_child(scroll)

	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 16)
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_cards_box)

	_add_close_button(outer_vbox)


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
	for child in _cards_box.get_children():
		child.queue_free()
	var ids := Research.known_activities()
	for i in ids.size():
		_cards_box.add_child(_build_card(ids[i]))
		if i < ids.size() - 1:
			_cards_box.add_child(HSeparator.new())


func _build_card(activity_id: String) -> Control:
	var def := Research.activity_def(activity_id)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = (def.display_name if def != null else activity_id).to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", UITheme.accent)
	box.add_child(title)

	if def == null:
		return box

	_add_stat_row(box, "CURRENT KNOWLEDGE", str(Research.knowledge(def.knowledge_category)))

	var instrument := Research.current_instrument(activity_id)
	_add_stat_row(box, "CURRENT CAPABILITY", instrument.display_name if instrument != null else "LOCKED")

	if not Research.is_unlocked(activity_id):
		box.add_child(_make_note("Requires a starting instrument — not yet available.", UITheme.dim))
		return box

	var next_tech := Research.next_technology(activity_id)
	if next_tech == null:
		box.add_child(_make_note("Future Developments: Unknown", UITheme.dim))
		return box

	box.add_child(HSeparator.new())
	box.add_child(_make_note("NEXT MILESTONE: %s" % next_tech.display_name, UITheme.accent))

	var met_count := 0
	var requirements: Dictionary = next_tech.knowledge_requirements
	for category_id: String in requirements:
		var required: int = requirements[category_id]
		var have := Research.knowledge(category_id)
		var met := have >= required
		if met:
			met_count += 1
		_add_stat_row(box, "%s %s" % ["✓" if met else "□", category_id.capitalize()], "%d / %d" % [have, required])

	box.add_child(_make_note("%d / %d Requirements Met" % [met_count, requirements.size()], UITheme.dim))
	return box


func _add_stat_row(parent: VBoxContainer, label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", UITheme.dim)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 13)
	val.add_theme_color_override("font_color", UITheme.text)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)


func _make_note(text: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	return lbl
