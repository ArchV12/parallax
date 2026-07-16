class_name BuildingDetailPanel
extends Control

# Centered confirm panel opened by tapping a CONSTRUCTION row in
# ActivitiesPanel — same popup shell as ActivityDetailPanel/DepositDetailPanel
# (UIPanel + centered). Buildings never compete with Operations for the ship
# (they're left behind, not something the ship "does"), so there's no
# "Ship Busy" concept here — the only gates are the survey prerequisite, the
# Knowledge-tier requirement, and credits/materials affordability.

signal begin_requested(category_id: String, body_id: String)

const PANEL_WIDTH := 380.0

var _panel: UIPanel
var _title_label: Label
var _category_value: Label
var _tier_value: Label
var _native_rate_value: Label
var _rate_value: Label
var _cost_value: Label
var _materials_value: Label
var _knowledge_value: Label
var _status_value: Label
var _begin_btn: UIButton
var _category_id: String = ""
var _body_id: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = UIPanel.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.visible = false
	center.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 17)
	_title_label.add_theme_color_override("font_color", UITheme.accent)
	vbox.add_child(_title_label)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1.5)
	divider.color = Color(UITheme.accent.r, UITheme.accent.g, UITheme.accent.b, 0.5)
	vbox.add_child(divider)

	_category_value = _add_field(vbox, "Category")
	_tier_value = _add_field(vbox, "Tier")
	_native_rate_value = _add_field(vbox, "Body Native Rate")
	_rate_value = _add_field(vbox, "Knowledge/sec")
	_cost_value = _add_field(vbox, "Cost")
	_materials_value = _add_field(vbox, "Materials Required")
	_knowledge_value = _add_field(vbox, "Knowledge Requirement")
	_status_value = _add_field(vbox, "Status")

	vbox.add_child(HSeparator.new())

	_begin_btn = UIButton.new()
	_begin_btn.text = "BUILD"
	_begin_btn.solid = true
	_begin_btn.shimmer_enabled = false
	_begin_btn.custom_minimum_size = Vector2(0, 36)
	_begin_btn.pressed.connect(_on_begin_pressed)
	vbox.add_child(_begin_btn)

	var cancel := UIButton.new()
	cancel.text = "Cancel"
	cancel.dim = true
	cancel.custom_minimum_size = Vector2(0, 30)
	cancel.pressed.connect(_panel.close_animated)
	vbox.add_child(cancel)


# Two-column row (label left, value right) — mirrors ActivityDetailPanel/
# DepositDetailPanel's own _add_field.
func _add_field(parent: VBoxContainer, label_text: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", UITheme.dim)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var val := Label.new()
	val.add_theme_font_size_override("font_size", 13)
	val.add_theme_color_override("font_color", UITheme.text)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	return val


func _format_dict(requirements: Dictionary) -> String:
	if requirements.is_empty():
		return "None"
	var parts: Array[String] = []
	for key: String in requirements:
		parts.append("%s %s" % [key, requirements[key]])
	return ", ".join(parts)


func open_for(category_id: String, body_id: String) -> void:
	var def := Buildings.next_building_def(category_id, body_id)
	if def == null:
		return

	_category_id = category_id
	_body_id = body_id

	var native_rate := NativeRate.for_category(category_id, body_id)
	# A tier REPLACES whatever's already built here (Buildings.construct
	# overwrites the same Structure's tier, never adds a second one) — the
	# title/tier readout and BUILD/UPGRADE button both reflect that instead
	# of reading like a second, separate structure is being added.
	var current_def := Buildings.current_building_def(category_id, body_id)
	var is_upgrade := current_def != null

	_title_label.text = "UPGRADE TO %s" % def.display_name.to_upper() if is_upgrade else def.display_name.to_upper()
	_category_value.text = category_id.capitalize()
	_tier_value.text = "%s -> Tier %d" % [current_def.display_name, def.tier + 1] if is_upgrade else "Tier %d" % (def.tier + 1)
	_native_rate_value.text = "%.0f" % native_rate
	_rate_value.text = "%.3f" % (native_rate * def.multiplier / Buildings.RATE_TIME_CONSTANT)
	_cost_value.text = "%s CR" % def.credits_cost
	_materials_value.text = _format_dict(def.materials_requirements)
	_knowledge_value.text = _format_dict(def.knowledge_requirements)

	var status := "Ready"
	if not Buildings.has_required_survey(category_id, body_id):
		status = "Survey Required"
	else:
		var knowledge_met := true
		for cat: String in def.knowledge_requirements:
			if Research.knowledge(cat) < def.knowledge_requirements[cat]:
				knowledge_met = false
				break
		if not knowledge_met:
			status = "Knowledge Requirement Not Met"
		elif not Buildings.can_construct(category_id, body_id):
			status = "Insufficient Credits/Materials"
	_status_value.text = status
	_begin_btn.text = "UPGRADE" if is_upgrade else "BUILD"
	_begin_btn.disabled = not Buildings.can_construct(category_id, body_id)

	_panel.open_animated()


func _on_begin_pressed() -> void:
	_panel.close_animated()
	begin_requested.emit(_category_id, _body_id)
