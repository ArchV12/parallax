class_name EarthTransmissionBanner
extends Control

# Centered "EARTH TRANSMISSION" notification (Docs/Science and Knowledge
# System.md's own mockup) — shown once a TechnologyDef's Knowledge
# requirements are met and its instrument is granted. Fired via
# ActivitiesPanel.milestone_reached (Research._check_milestones does the
# actual granting; this only displays it). No auto-dismiss — the unlock_text
# is meant to be read, not glanced at.

const PANEL_WIDTH := 420.0

var _panel: UIPanel
var _title_label: Label
var _body_label: Label


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
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)
	vbox.add_child(UIPanel.build_title_header("Earth Transmission"))

	var milestone_label := Label.new()
	milestone_label.text = "Scientific Milestone Achieved"
	milestone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	milestone_label.add_theme_font_size_override("font_size", 12)
	milestone_label.add_theme_color_override("font_color", UITheme.dim)
	vbox.add_child(milestone_label)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", UITheme.accent)
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_body_label)

	var dismiss := UIButton.new()
	dismiss.text = "DISMISS"
	dismiss.solid = true
	dismiss.shimmer_enabled = false
	dismiss.custom_minimum_size = Vector2(0, 34)
	dismiss.pressed.connect(_panel.close_animated)
	vbox.add_child(dismiss)


func show_transmission(tech: TechnologyDef) -> void:
	_title_label.text = tech.display_name
	_body_label.text = tech.unlock_text
	_panel.open_animated()
