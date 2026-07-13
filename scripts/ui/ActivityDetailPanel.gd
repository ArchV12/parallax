class_name ActivityDetailPanel
extends Control

# Centered confirm panel opened by clicking an AVAILABLE row in
# ActivitiesPanel's gateway list — Target/Instrument/Status/Estimated
# Duration/Potential Discoveries, then BEGIN SURVEY. Same popup shell as
# EarthTransmissionBanner/SurveyReportPanel (UIPanel + centered).

signal begin_requested(activity_id: String)

const PANEL_WIDTH := 380.0

var _panel: UIPanel
var _title_label: Label
var _target_value: Label
var _instrument_value: Label
var _status_value: Label
var _duration_value: Label
var _discoveries_box: VBoxContainer
var _begin_btn: UIButton
var _activity_id: String = ""


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

	_target_value = _add_field(vbox, "Target")
	_instrument_value = _add_field(vbox, "Instrument")
	_status_value = _add_field(vbox, "Status")
	_duration_value = _add_field(vbox, "Estimated Duration")

	vbox.add_child(HSeparator.new())
	var discoveries_header := Label.new()
	discoveries_header.text = "Potential Discoveries"
	discoveries_header.add_theme_font_size_override("font_size", 12)
	discoveries_header.add_theme_color_override("font_color", UITheme.dim)
	vbox.add_child(discoveries_header)

	_discoveries_box = VBoxContainer.new()
	_discoveries_box.add_theme_constant_override("separation", 2)
	vbox.add_child(_discoveries_box)

	vbox.add_child(HSeparator.new())

	_begin_btn = UIButton.new()
	_begin_btn.text = "BEGIN SURVEY"
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


# Two-column row (label left, value right) — mirrors BodyInfoPanel/
# ResearchPanel's own row idiom. Returns the value Label so the caller can
# store it for later updates (see the _target_value/etc. fields above).
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


# ship_busy — true if a DIFFERENT activity is already running (Phase's
# "single operation at a time" constraint) — disables BEGIN and shows a
# busy status instead of Ready.
func open_for(activity_id: String, location_id: String, ship_busy: bool) -> void:
	var def := Research.activity_def(activity_id)
	var instrument := Research.current_instrument(activity_id)
	if def == null:
		return

	_activity_id = activity_id
	_title_label.text = def.display_name.to_upper()
	_target_value.text = location_id
	_instrument_value.text = instrument.display_name if instrument != null else "—"
	_duration_value.text = ActivityDef.format_duration(def.flavor_duration_seconds)

	_status_value.text = "Ship Busy" if ship_busy else "Ready"
	_begin_btn.disabled = ship_busy

	for child in _discoveries_box.get_children():
		child.queue_free()
	for discovery: String in def.potential_discoveries:
		var lbl := Label.new()
		lbl.text = "• %s" % discovery
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", UITheme.text)
		_discoveries_box.add_child(lbl)

	_panel.open_animated()


func _on_begin_pressed() -> void:
	_panel.close_animated()
	begin_requested.emit(_activity_id)
