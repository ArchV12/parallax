class_name SurveyReportPanel
extends Control

# Centered "rich survey report" popup — shown after a Geological or Resource
# Survey when hand-authored content exists for the current body (see
# Research.geological_data_for/resource_data_for). Mirrors the sample Luna
# report almost verbatim (sectioned fields, divider lines) rather than
# ActivitiesPanel's tiny flat-text result label, which stays the fallback
# for activities/bodies with no structured report yet.
#
# Two explicit show_*_report entry points (one per known report shape) that
# share this same popup shell, rather than a generic "any survey's report"
# renderer — GeologicalSurveyData and ResourceSurveyData have genuinely
# different fields (see either class's own comment for why they're not one
# forced-common schema); only the presentation chrome is shared here.

const PANEL_WIDTH := 420.0
# Centering container's bottom anchor — less than 1.0 so the effective
# center point sits above true screen-center, clear of the bottom console
# (ConsolePanel.HEIGHT_CENTER, ~150px of a 1080px viewport). Grew a real
# reason to matter once this panel started showing the Knowledge-awarded
# line too (taller content, closer to the console than before).
const CENTER_ANCHOR_BOTTOM := 0.82

var _panel: UIPanel
var _title_label: Label
var _target_label: Label
var _knowledge_label: Label
var _body_box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.anchor_bottom = CENTER_ANCHOR_BOTTOM
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = UIPanel.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.visible = false
	center.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	# Hand-rolled instead of UIPanel.build_title_header — that static helper
	# is for a FIXED title baked in at construction (PauseMenu/CheatMenu/
	# EarthTransmissionBanner all use it that way); this panel's title needs
	# to change per report type, so _title_label needs to be a kept reference.
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 17)
	_title_label.add_theme_color_override("font_color", UITheme.accent)
	vbox.add_child(_title_label)

	# Knowledge awarded now lives here, not ActivitiesPanel's own inline
	# label (see that panel's _start_activity) — showing it in both places
	# was redundant once a report exists; the inline label stays only as
	# the fallback for bodies/activities with no report to show it in. Right
	# under the title, before the divider — reads as the headline result,
	# with Target/the detailed body as the report below it.
	_knowledge_label = Label.new()
	_knowledge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_knowledge_label.add_theme_font_size_override("font_size", 12)
	_knowledge_label.add_theme_color_override("font_color", UITheme.accent)
	vbox.add_child(_knowledge_label)

	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 1.5)
	divider.color = Color(UITheme.accent.r, UITheme.accent.g, UITheme.accent.b, 0.5)
	vbox.add_child(divider)

	_target_label = Label.new()
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_label.add_theme_font_size_override("font_size", 12)
	_target_label.add_theme_color_override("font_color", UITheme.dim)
	vbox.add_child(_target_label)

	_body_box = VBoxContainer.new()
	_body_box.add_theme_constant_override("separation", 10)
	vbox.add_child(_body_box)

	var dismiss := UIButton.new()
	dismiss.text = "DISMISS"
	dismiss.solid = true
	dismiss.shimmer_enabled = false
	dismiss.custom_minimum_size = Vector2(0, 34)
	dismiss.pressed.connect(_panel.close_animated)
	vbox.add_child(dismiss)


func show_geological_report(location_id: String, data: GeologicalSurveyData, category: String, knowledge_awarded: int) -> void:
	_title_label.text = "GEOLOGICAL SURVEY RESULTS"
	_target_label.text = "Target: %s" % location_id
	_knowledge_label.text = "+%d %s Knowledge" % [knowledge_awarded, category.capitalize()]
	_clear_body()

	_add_section("SURFACE COMPOSITION", data.composition)
	_body_box.add_child(HSeparator.new())
	_add_section("MAJOR FEATURES", data.major_features)

	_body_box.add_child(HSeparator.new())
	_add_section_header("GEOLOGICAL ACTIVITY")
	_add_field_line("Volcanism", data.volcanism)
	_add_field_line("Tectonics", data.tectonics)
	_add_field_line("Erosion", data.erosion)

	_body_box.add_child(HSeparator.new())
	_add_section_header("ESTIMATED AGE")
	_add_plain_line(data.estimated_age)

	if not data.notes.is_empty():
		_body_box.add_child(HSeparator.new())
		_add_section_header("NOTES")
		for note: String in data.notes:
			_add_plain_line(note)

	_panel.open_animated()


func show_resource_report(location_id: String, data: ResourceSurveyData, category: String, knowledge_awarded: int) -> void:
	_title_label.text = "RESOURCE SURVEY RESULTS"
	_target_label.text = "Target: %s" % location_id
	_knowledge_label.text = "+%d %s Knowledge" % [knowledge_awarded, category.capitalize()]
	_clear_body()

	_add_section_header("DETECTED MATERIALS")
	for i in data.materials.size():
		var finding: ResourceMaterialFinding = data.materials[i]
		_add_material_name(finding.material_name)
		_add_field_line("Abundance", finding.abundance)
		if finding.note_label != "":
			_add_field_line(finding.note_label, finding.note_value)
		if i < data.materials.size() - 1:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(0, 4)  # small breathing room between materials, no divider line — see the sample's own spacing
			_body_box.add_child(spacer)

	_panel.open_animated()


func _clear_body() -> void:
	for child in _body_box.get_children():
		child.queue_free()


func _add_section(header: String, lines: Array[String]) -> void:
	if lines.is_empty():
		return
	_add_section_header(header)
	for line: String in lines:
		_add_plain_line(line)


func _add_section_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", UITheme.accent)
	_body_box.add_child(lbl)


func _add_plain_line(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", UITheme.text)
	_body_box.add_child(lbl)


# Left-justified, unlike _add_plain_line's centered lines (composition/
# features/notes) — a material name reads as the header of its own
# Abundance/Extraction rows below it, not a standalone centered statement,
# so centering it looked odd against those left-label/right-value rows.
func _add_material_name(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", UITheme.text)
	_body_box.add_child(lbl)


func _add_field_line(label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	_body_box.add_child(row)

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
